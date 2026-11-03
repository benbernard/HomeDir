// scrolltrace — capture raw HID wheel reports and post-OS scroll events side by side.
// usage: scrolltrace <out.tsv> <seconds>
import Foundation
import IOKit.hid
import CoreGraphics

func ts() -> String { String(format: "%.4f", CFAbsoluteTimeGetCurrent()) }
let out = FileHandle.standardOutput
func emit(_ s: String) { out.write((s + "\n").data(using: .utf8)!) }

// ---- HID level: values as reported by the device, before macOS event processing
let hidValueCb: IOHIDValueCallback = { _, _, _, value in
    let element = IOHIDValueGetElement(value)
    let page = IOHIDElementGetUsagePage(element)
    let usage = IOHIDElementGetUsage(element)
    guard page == 0x01, usage == 0x38 || usage == 0x3D else { return }
    let v = IOHIDValueGetIntegerValue(value)
    let t = IOHIDValueGetTimeStamp(value)
    let name = usage == 0x38 ? "WHEEL" : "HPAN"
    emit("RAW\t\(ts())\t\(t)\t\(name)\t\(v)")
}

let hidMatchCb: IOHIDDeviceCallback = { _, _, _, device in
    let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "?"
    let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? "?"
    let primary = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? -1
    emit("MATCH\t\(ts())\t\(product)\t\(transport)\tUSAGE=\(primary)")
}

// ---- OS level: scroll events as delivered to apps (post event-taps)
var traceTap: CFMachPort?
let cgCb: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        emit("TRACER_TAP_DISABLED\t\(type.rawValue)")
        if let traceTap { CGEvent.tapEnable(tap: traceTap, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    if type == .scrollWheel {
        let line = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let point = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let cont = event.getIntegerValueField(.scrollWheelEventIsContinuous)
        let instant = event.getDoubleValueField(.scrollWheelEventInstantMouser)
        emit("CG\t\(ts())\t\(event.timestamp)\t\(line)\t\(String(format: "%.4f", point))\t\(cont)\t\(instant)")
    }
    return Unmanaged.passUnretained(event)
}

let args = CommandLine.arguments
let seconds = args.count > 1 ? (Double(args[1]) ?? 60) : 60

// ---- permission diagnostics
let listenOK = CGPreflightListenEventAccess()
let postOK = CGPreflightPostEventAccess()
let hidAccess = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
let hidAccessName: String
switch hidAccess.rawValue {
case 0: hidAccessName = "granted"
case 1: hidAccessName = "denied"
default: hidAccessName = "unknown"
}
emit("PERM\tCGListen=\(listenOK)\tCGPost=\(postOK)\tHIDInputMonitoring=\(hidAccessName)")

// ---- HID manager for the Razer Naga X (0x1532:0x0096)
let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
let matching: [String: Any] = [
    kIOHIDVendorIDKey: 0x1532,
    kIOHIDProductIDKey: 0x0096,
]
IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
IOHIDManagerRegisterDeviceMatchingCallback(manager, hidMatchCb, nil)
IOHIDManagerRegisterInputValueCallback(manager, hidValueCb, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
emit("HID_OPEN\tresult=\(openResult)")

// ---- event tap
var tap: CFMachPort? = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .tailAppendEventTap,
    options: .listenOnly,
    eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
    callback: cgCb,
    userInfo: nil
)
emit("TAP\tcreated=\(tap != nil)")

if let tap {
    traceTap = tap
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
}

emit("READY\tseconds=\(seconds)")
CFRunLoopRunInMode(.defaultMode, seconds, false)
emit("DONE\t\(ts())")
