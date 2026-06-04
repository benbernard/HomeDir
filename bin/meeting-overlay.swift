import Cocoa
import Foundation

// MARK: - Data

struct MeetingInfo: Codable {
    var title: String
    var url: String
    var time: String
}

struct Config {
    var meetings: [MeetingInfo] = []
    var calUrl: String?
}

// MARK: - Arg parsing

var config = Config()
var i = 1
let args = CommandLine.arguments
while i < args.count {
    switch args[i] {
    case "--meetings-json":
        i += 1
        if i < args.count,
           let data = args[i].data(using: .utf8),
           let m = try? JSONDecoder().decode([MeetingInfo].self, from: data) {
            config.meetings = m
        }
    case "--cal-url": i += 1; if i < args.count { config.calUrl = args[i] }
    // Legacy single-meeting flags (for testing)
    case "--title": i += 1; if i < args.count {
        if config.meetings.isEmpty { config.meetings.append(MeetingInfo(title: args[i], url: "", time: "")) }
        else { config.meetings[0].title = args[i] }
    }
    case "--url": i += 1; if i < args.count {
        if config.meetings.isEmpty { config.meetings.append(MeetingInfo(title: "", url: args[i], time: "")) }
        else { config.meetings[0].url = args[i] }
    }
    case "--time": i += 1; if i < args.count {
        if config.meetings.isEmpty { config.meetings.append(MeetingInfo(title: "", url: "", time: args[i])) }
        else { config.meetings[0].time = args[i] }
    }
    default: break
    }
    i += 1
}

if config.meetings.isEmpty {
    config.meetings.append(MeetingInfo(title: "Meeting Starting", url: "", time: ""))
}

// MARK: - NSButton subclass to carry meeting URL

class OverlayButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func performKeyEquivalent(with event: NSEvent) -> Bool { false }
}

class MeetingButton: OverlayButton {
    var meetingURL: String = ""
}

// MARK: - Window + View

class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func keyDown(with event: NSEvent) {}
    override func performKeyEquivalent(with event: NSEvent) -> Bool { false }
}

class OverlayView: NSView {
    override var acceptsFirstResponder: Bool { false }
    override func keyDown(with event: NSEvent) {}
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var snoozeTimer: Timer?
    var clockTimer: Timer?
    var clockLabel: NSTextField?
    let cfg: Config

    init(_ cfg: Config) { self.cfg = cfg }

    func applicationDidFinishLaunching(_ notification: Notification) { show() }

    func show() {
        window?.close()
        let screen = NSScreen.main ?? NSScreen.screens[0]
        window = OverlayWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        window.backgroundColor = NSColor(calibratedRed: 0.04, green: 0.04, blue: 0.12, alpha: 0.96)
        window.isOpaque = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let overlay = OverlayView(frame: window.contentView!.bounds)
        overlay.autoresizingMask = [.width, .height]

        let buttons = buildContent(in: overlay)

        window.contentView = overlay
        window.orderFrontRegardless()

        for btn in buttons { btn.isEnabled = false; btn.alphaValue = 0.4 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            for btn in buttons { btn.isEnabled = true; btn.alphaValue = 1.0 }
        }
    }

    // MARK: - Layout

    func buildContent(in view: NSView) -> [NSButton] {
        let b = view.bounds
        let cx = b.width / 2
        let meetings = cfg.meetings
        let count = meetings.count
        let isMulti = count > 1

        var buttons: [NSButton] = []

        // Layout measurements
        let rowW: CGFloat = min(b.width - 240, 1000)
        let rowH: CGFloat = isMulti ? 76 : 0   // single uses no row
        let rowGap: CGFloat = 10
        let clockH: CGFloat = 88
        let headerH: CGFloat = isMulti ? 110 : 230
        let joinBtnH: CGFloat = isMulti ? 0 : 62   // single: standalone join btn
        let bottomH: CGFloat = 110
        let rowsH = CGFloat(count) * rowH + CGFloat(max(0, count - 1)) * rowGap
        let totalH = clockH + headerH + rowsH + (isMulti ? 0 : joinBtnH + 20) + bottomH

        var topY = b.height / 2 + totalH / 2

        installClock(in: view, centerX: cx, topY: topY)
        topY -= clockH

        // --- Header ---
        if isMulti {
            // Warning line
            let iconW: CGFloat = 52
            let warnText = "\(count) MEETINGS STARTING NOW"
            let warnFont = NSFont.boldSystemFont(ofSize: 34)
            let warnW = (warnText as NSString).size(withAttributes: [.font: warnFont]).width + 4
            let lineW = iconW + 12 + warnW
            let lineX = cx - lineW / 2

            let icon = lbl("⚠️", 44, false, .white)
            icon.frame = NSRect(x: lineX, y: topY - 58, width: iconW, height: 58)
            view.addSubview(icon)

            let warn = lbl(warnText, 34, true, NSColor(red: 1, green: 0.58, blue: 0.1, alpha: 1))
            warn.frame = NSRect(x: lineX + iconW + 12, y: topY - 54, width: warnW, height: 50)
            view.addSubview(warn)

            let sub = lbl("Starting in the next 15 minutes", 16, false, NSColor(white: 0.5, alpha: 1))
            sub.alignment = .center
            sub.frame = NSRect(x: cx - 250, y: topY - 96, width: 500, height: 24)
            view.addSubview(sub)

            topY -= headerH
        } else {
            // Single meeting: big icon + title + time + join
            let m = meetings[0]

            let icon = lbl("📅", 68, false, .white)
            icon.frame = NSRect(x: cx - 44, y: topY - 84, width: 88, height: 84)
            view.addSubview(icon)

            let title = lbl(m.title, 48, true, .white)
            title.alignment = .center
            title.frame = NSRect(x: cx - rowW / 2, y: topY - 158, width: rowW, height: 68)
            view.addSubview(title)

            if !m.time.isEmpty {
                let time = lbl(formatTime(m.time), 24, false, NSColor(white: 0.65, alpha: 1))
                time.alignment = .center
                time.frame = NSRect(x: cx - rowW / 2, y: topY - 196, width: rowW, height: 32)
                view.addSubview(time)
            }

            topY -= headerH

            // Big join button
            let joinBtn = MeetingButton()
            joinBtn.meetingURL = m.url
            let hasURL = !m.url.isEmpty
            styleBtn(joinBtn, title: hasURL ? "Join" : "No Link", size: 22,
                     color: hasURL ? NSColor(red: 0.15, green: 0.72, blue: 0.28, alpha: 1)
                                   : NSColor(white: 0.3, alpha: 1))
            joinBtn.isEnabled = hasURL
            joinBtn.target = self; joinBtn.action = #selector(joinFromButton(_:))
            joinBtn.frame = NSRect(x: cx - 120, y: topY - joinBtnH, width: 240, height: joinBtnH)
            view.addSubview(joinBtn)

            topY -= joinBtnH + 20
        }

        // --- Meeting rows (multi only) ---
        let rowX = cx - rowW / 2
        for m in meetings {
            let rowY = topY - rowH

            let card = NSView(frame: NSRect(x: rowX, y: rowY, width: rowW, height: rowH))
            card.wantsLayer = true
            card.layer?.backgroundColor = NSColor(white: 1, alpha: 0.07).cgColor
            card.layer?.cornerRadius = 12
            view.addSubview(card)

            let joinBtnW: CGFloat = 100
            let pad: CGFloat = 18
            let timeW: CGFloat = 90

            let timeStr = formatTime(m.time)
            let titleW = rowW - joinBtnW - timeW - pad * 2 - 12

            let titleLbl = lbl(m.title, 21, true, .white)
            titleLbl.lineBreakMode = .byTruncatingTail
            titleLbl.frame = NSRect(x: pad, y: (rowH - 28) / 2, width: titleW, height: 28)
            card.addSubview(titleLbl)

            let timeLbl = lbl(timeStr, 16, false, NSColor(white: 0.58, alpha: 1))
            timeLbl.frame = NSRect(x: pad + titleW + 8, y: (rowH - 22) / 2, width: timeW, height: 22)
            card.addSubview(timeLbl)

            let hasURL = !m.url.isEmpty
            let joinBtn = MeetingButton()
            joinBtn.meetingURL = m.url
            styleBtn(joinBtn, title: hasURL ? "Join" : "No Link", size: 16,
                     color: hasURL ? NSColor(red: 0.15, green: 0.72, blue: 0.28, alpha: 1)
                                   : NSColor(white: 0.28, alpha: 1))
            joinBtn.isEnabled = hasURL
            joinBtn.target = self; joinBtn.action = #selector(joinFromButton(_:))
            joinBtn.frame = NSRect(x: rowW - joinBtnW - pad, y: (rowH - 40) / 2, width: joinBtnW, height: 40)
            card.addSubview(joinBtn)

            topY -= rowH + rowGap
        }

        topY -= 18

        // --- Bottom: Snooze + Dismiss ---
        let bW: CGFloat = 190, bH: CGFloat = 52, gap: CGFloat = 16
        let totalBW = bW * 2 + gap
        let snoozeBtn = btn("Snooze 2 min", NSColor(red: 0.85, green: 0.55, blue: 0.05, alpha: 1), 19)
        let dismissBtn = btn("Dismiss", NSColor(red: 0.65, green: 0.18, blue: 0.18, alpha: 1), 19)
        snoozeBtn.frame = NSRect(x: cx - totalBW / 2,           y: topY - bH, width: bW, height: bH)
        dismissBtn.frame = NSRect(x: cx - totalBW / 2 + bW + gap, y: topY - bH, width: bW, height: bH)
        snoozeBtn.target = self; snoozeBtn.action = #selector(snooze)
        dismissBtn.target = self; dismissBtn.action = #selector(dismiss)
        view.addSubview(snoozeBtn); view.addSubview(dismissBtn)
        buttons.append(contentsOf: [snoozeBtn, dismissBtn])

        topY -= bH + 10

        // Calendar button
        let calBtn = btn("Google Calendar", NSColor(white: 0.2, alpha: 1), 15)
        calBtn.frame = NSRect(x: cx - totalBW / 2, y: topY - 38, width: totalBW, height: 38)
        calBtn.target = self; calBtn.action = #selector(openCalendar)
        view.addSubview(calBtn)

        return buttons
    }

    // MARK: - Helpers

    func lbl(_ text: String, _ size: CGFloat, _ bold: Bool, _ color: NSColor) -> NSTextField {
        let tf = NSTextField(labelWithString: text)
        tf.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        tf.textColor = color
        tf.lineBreakMode = .byTruncatingTail
        tf.maximumNumberOfLines = 1
        return tf
    }

    func btn(_ title: String, _ color: NSColor, _ size: CGFloat) -> NSButton {
        let b = OverlayButton()
        styleBtn(b, title: title, size: size, color: color)
        return b
    }

    func styleBtn(_ b: NSButton, title: String, size: CGFloat, color: NSColor) {
        b.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.boldSystemFont(ofSize: size),
        ])
        b.wantsLayer = true
        b.layer?.backgroundColor = color.cgColor
        b.layer?.cornerRadius = 11
        b.isBordered = false
        b.keyEquivalent = ""
        b.refusesFirstResponder = true
    }

    func installClock(in view: NSView, centerX: CGFloat, topY: CGFloat) {
        clockTimer?.invalidate()

        let panelW: CGFloat = 360
        let panelH: CGFloat = 72
        let panel = NSView(frame: NSRect(x: centerX - panelW / 2, y: topY - panelH, width: panelW, height: panelH))
        panel.wantsLayer = true
        panel.layer?.backgroundColor = NSColor(white: 1, alpha: 0.08).cgColor
        panel.layer?.borderColor = NSColor(red: 0.95, green: 0.72, blue: 0.22, alpha: 0.85).cgColor
        panel.layer?.borderWidth = 2
        panel.layer?.cornerRadius = 12
        view.addSubview(panel)

        let title = lbl("CURRENT TIME", 13, true, NSColor(red: 0.95, green: 0.72, blue: 0.22, alpha: 1))
        title.alignment = .center
        title.frame = NSRect(x: 0, y: 43, width: panelW, height: 18)
        panel.addSubview(title)

        let label = lbl("", 34, true, .white)
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 8, width: panelW, height: 38)
        panel.addSubview(label)
        clockLabel = label

        updateClock()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateClock()
        }
    }

    func updateClock() {
        let df = DateFormatter()
        df.timeStyle = .short
        df.dateStyle = .none
        clockLabel?.stringValue = df.string(from: Date())
    }

    func formatTime(_ s: String) -> String {
        // MeetingBar format: "Thursday, May 21, 2026 at 11:00:00 AM"
        var tm = tm()
        if strptime(s, "%A, %B %d, %Y at %I:%M:%S %p", &tm) != nil {
            var buf = [CChar](repeating: 0, count: 32)
            strftime(&buf, 32, "%I:%M %p", &tm)
            let r = String(cString: buf)
            return r.hasPrefix("0") ? String(r.dropFirst()) : r
        }
        // ISO8601: "2026-05-21T09:30:00-07:00"
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: s) {
            let df = DateFormatter()
            df.timeStyle = .short; df.dateStyle = .none
            return df.string(from: date)
        }
        return s
    }

    // MARK: - Actions

    @objc func joinFromButton(_ sender: NSButton) {
        guard let b = sender as? MeetingButton,
              !b.meetingURL.isEmpty,
              let u = URL(string: b.meetingURL) else { return }
        NSWorkspace.shared.open(u)
        NSApp.terminate(nil)
    }

    @objc func snooze() {
        window.orderOut(nil)
        snoozeTimer?.invalidate()
        snoozeTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { [weak self] _ in
            self?.show()
        }
    }

    @objc func dismiss() { NSApp.terminate(nil) }

    @objc func openCalendar() {
        if let u = cfg.calUrl.flatMap(URL.init(string:)) { NSWorkspace.shared.open(u) }
        NSApp.terminate(nil)
    }
}

// MARK: - Main

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate(config)
app.delegate = delegate
app.run()
