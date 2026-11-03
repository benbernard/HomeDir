// scrolldebounce — suppress fabricated direction reversals in mouse-wheel scrolling.
//
// The Naga X wheel encoder intermittently emits steps in the wrong direction during a
// single-direction scroll, and macOS scroll acceleration amplifies one step into a big
// visible jump. This filter withholds opposing events until they are confirmed as a real
// reversal. Withheld events are NOT discarded when the reversal is confirmed — their
// deltas are folded into the confirming event, so no scroll distance is lost.
//
// Every decision is kept in a rolling in-memory window and written to a snapshot file,
// so the recent history can be copied out after a problem occurs.
//
// build: bin/scrollfix-build
//   Signs with $CODESIGN_ID when set (keeps the Accessibility grant stable across
//   rebuilds), otherwise ad-hoc signs, which macOS re-prompts for after each build.
//
// usage: scrolldebounce [-n] [-v] [--confirm N] [--gap S]
//                       [--log PATH] [--log-all] [--log-window SECONDS]
//   -n               dry run: log decisions, suppress nothing
//   -v               verbose: echo HOLD/DROP decisions to stderr
//   --confirm N      consecutive opposing events needed to accept a real reversal (default 3)
//   --gap S          seconds of silence that resets the committed direction (default 0.30)
//   --log PATH       keep a rolling snapshot of the last --log-window seconds at PATH
//   --log-all        include continuous/trackpad scroll in the snapshot
//   --log-window S   how much history to retain (default 600 = 10 minutes)
//   --replay         EXPERIMENTAL: re-post withheld deltas on a confirmed reversal.
//
// Snapshot on demand:  kill -USR1 $(pgrep -x scrolldebounce)
import Foundation
import CoreGraphics
import ApplicationServices

// ---- arguments
let argv = CommandLine.arguments
func argValue(_ name: String) -> String? {
    guard let i = argv.firstIndex(of: name), i + 1 < argv.count else { return nil }
    return argv[i + 1]
}
// Empirical: this encoder emits glitches of 1 or 2 consecutive wrong-direction steps,
// so CONFIRM must exceed 2 to catch the pairs.
let CONFIRM = argValue("--confirm").flatMap { Int($0) } ?? 3
let GAP = argValue("--gap").flatMap { Double($0) } ?? 0.30
let dryRun = argv.contains("-n")
let verbose = argv.contains("-v") || dryRun
let logAll = argv.contains("--log-all")
// Re-posting withheld deltas is EXPERIMENTAL: posting at cghidEventTap from inside a
// session-height tap was observed to make other taps at that height stop delivering
// events, so it is off by default.
let replayEnabled = argv.contains("--replay")
let logPath = argValue("--log")
let logWindow = argValue("--log-window").flatMap { Double($0) } ?? 600.0
let maxEntries = 200_000
// Marks events we posted ourselves so the tap never re-processes them.
let REPLAY_MARK: Int64 = 0x5C0FF5EE

// ---- state
var committed = 0        // +1 / -1 / 0: direction of the current scroll burst
var opposites = 0        // consecutive events opposing `committed`
var heldLine = 0         // withheld line delta, awaiting confirmation
var heldPoint = 0.0      // withheld point delta, awaiting confirmation
var lastTime = 0.0
var passed = 0
var dropped = 0
var tapRef: CFMachPort?

func note(_ s: String) {
    FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
}

// ---- rolling event window
var ring: [(t: Double, line: String)] = []
var lastFlush = 0.0

func flushRing() {
    guard let logPath else { return }
    var out = "ts\tdecision\td1\td2\tcontinuous\tcommitted\topposites\theld\tdiscarded\n"
    out.reserveCapacity(ring.count * 48)
    for e in ring { out += e.line }

    // Atomic replace so a reader never sees a half-written snapshot.
    let tmp = logPath + ".tmp"
    do {
        try out.write(toFile: tmp, atomically: false, encoding: .utf8)
        try? FileManager.default.removeItem(atPath: logPath)
        try FileManager.default.moveItem(atPath: tmp, toPath: logPath)
    } catch {
        note("log write failed: \(error.localizedDescription)")
    }
    lastFlush = CFAbsoluteTimeGetCurrent()
}

func recordEvent(_ decision: String, _ d1: Int64, _ d2: Int64, _ continuous: Int64,
                 held: Int, discarded: Int) {
    guard logPath != nil else { return }
    let now = CFAbsoluteTimeGetCurrent()
    let line = "\(String(format: "%.4f", now))\t\(decision)\t\(d1)\t\(d2)\t\(continuous)"
        + "\t\(committed)\t\(opposites)\t\(held)\t\(discarded)\n"
    ring.append((now, line))
    if ring.count > maxEntries {
        ring.removeFirst(ring.count - maxEntries)
    }
}

// Trim by age in one pass, off the event path.
func trimAndFlush() {
    guard logPath != nil else { return }
    let cutoff = CFAbsoluteTimeGetCurrent() - logWindow
    if let firstKeep = ring.firstIndex(where: { $0.t >= cutoff }), firstKeep > 0 {
        ring.removeFirst(firstKeep)
    }
    flushRing()
}

// ---- event tap
let callback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tapRef { CGEvent.tapEnable(tap: tapRef, enable: true) }
        note("tap re-enabled")
        return Unmanaged.passUnretained(event)
    }
    guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }
    if event.getIntegerValueField(.eventSourceUserData) == REPLAY_MARK {
        if verbose { note("own replayed event seen by tap d1=\(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))") }
        return Unmanaged.passUnretained(event)
    }

    let d1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
    let d2 = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
    let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous)

    // Trackpad, momentum and horizontal scrolling are never filtered.
    if continuous != 0 || d2 != 0 || d1 == 0 {
        passed += 1
        if logAll { recordEvent("CONT", d1, d2, continuous, held: 0, discarded: 0) }
        return Unmanaged.passUnretained(event)
    }

    let sign = d1 > 0 ? 1 : -1
    let now = Double(event.timestamp) / 1_000_000_000
    var decision = "PASS"
    var suppress = false
    var discarded = 0
    var folded = 0

    if committed == 0 || now - lastTime > GAP {
        // Fresh gesture (or long pause): believe whatever comes first.
        discarded = heldLine
        heldLine = 0
        heldPoint = 0
        committed = sign
        opposites = 0
        decision = "FRESH"
    } else if sign == committed {
        // Continuation of the burst; anything withheld was a glitch. Discard it.
        discarded = heldLine
        heldLine = 0
        heldPoint = 0
        opposites = 0
    } else {
        opposites += 1
        if opposites >= CONFIRM {
            // Commit the new direction BEFORE posting, so that if our own tap sees the
            // replayed event it is recognised as same-direction and passed rather than
            // withheld again.
            let pendingLine = heldLine
            let pendingPoint = heldPoint
            heldLine = 0
            heldPoint = 0
            committed = sign
            opposites = 0

            // Real reversal: hand back everything we withheld by re-posting it, so the
            // full scroll distance is delivered instead of being silently lost.
            if (pendingLine != 0 || pendingPoint != 0) && replayEnabled {
                folded = pendingLine
                let made = CGEvent(scrollWheelEvent2Source: CGEventSource(stateID: .hidSystemState),
                                   units: .line, wheelCount: 1,
                                   wheel1: Int32(pendingLine), wheel2: 0, wheel3: 0)
                if verbose { note("posting replay wheel1=\(pendingLine) created=\(made != nil)") }
                if let replay = made {
                    replay.setIntegerValueField(.eventSourceUserData, value: REPLAY_MARK)
                    replay.setIntegerValueField(.scrollWheelEventIsContinuous, value: 0)
                    replay.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: pendingPoint)
                    replay.post(tap: .cghidEventTap)
                }
                decision = "REPLAY"
            } else if pendingLine != 0 || pendingPoint != 0 {
                // Withheld notches are dropped (default). Log what was lost.
                discarded += pendingLine
                decision = "REVERSAL"
            } else {
                decision = "REVERSAL"
            }
        } else {
            // Withhold: either an encoder glitch or the start of a real reversal.
            heldLine += Int(d1)
            heldPoint += event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            suppress = true
            decision = "DROP"
            if verbose {
                note("HOLD d1=\(d1) committed=\(committed) held=\(heldLine) at \(String(format: "%.3f", now))")
            }
        }
    }

    lastTime = now
    if suppress { dropped += 1 } else { passed += 1 }
    recordEvent(decision, d1, d2, continuous, held: decision == "REPLAY" ? folded : heldLine, discarded: discarded)

    if suppress && !dryRun { return nil }
    return Unmanaged.passUnretained(event)
}

let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)

// A launchd-started process has to be granted Accessibility by hand. Prompt once,
// then wait instead of crash-looping under KeepAlive.
var prompted = false
var attempts = 0
while true {
    attempts += 1
    if let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: mask,
        callback: callback,
        userInfo: nil
    ) {
        tapRef = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        break
    }
    if !prompted {
        prompted = true
        note("Accessibility permission required — requesting it now.")
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }
    if attempts == 1 || attempts % 10 == 0 {
        note("waiting for Accessibility grant (System Settings > Privacy & Security > Accessibility), attempt \(attempts)")
    }
    Thread.sleep(forTimeInterval: 3)
}

note("scrolldebounce active\(dryRun ? " (DRY RUN)" : "") — confirm=\(CONFIRM) gap=\(GAP)s")
if let logPath { note("keeping last \(Int(logWindow))s of scroll events at \(logPath)") }

// Snapshot periodically so the file always holds roughly the last logWindow seconds.
if logPath != nil {
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + 10, repeating: 10)
    timer.setEventHandler { trimAndFlush() }
    timer.resume()
    // Keep the timer alive for the lifetime of the process.
    _ = timer
    flushRing()
}

// Flush on demand (kill -USR1) and on shutdown.
let usr1 = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
usr1.setEventHandler {
    trimAndFlush()
    note("snapshot written to \(logPath ?? "(no --log configured)")")
}
usr1.resume()
signal(SIGUSR1, SIG_IGN)

let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
term.setEventHandler {
    trimAndFlush()
    exit(0)
}
term.resume()
signal(SIGTERM, SIG_IGN)

let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sigint.setEventHandler {
    trimAndFlush()
    note("summary: passed=\(passed) withheld=\(dropped)")
    exit(0)
}
sigint.resume()
signal(SIGINT, SIG_IGN)

CFRunLoopRun()
