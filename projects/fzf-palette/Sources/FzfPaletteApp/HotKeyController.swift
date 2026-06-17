import Carbon
import ApplicationServices
import Foundation
import FzfPaletteCore
import os

enum PhysicalHotKeyPostResult: Equatable {
    case posted
    case accessibilityNotTrusted
    case noRegisteredHotKey
    case unsupportedKey(String)
    case eventCreationFailed

    var isPosted: Bool {
        self == .posted
    }

    var code: String {
        switch self {
        case .posted:
            return "posted"
        case .accessibilityNotTrusted:
            return "accessibility_not_trusted"
        case .noRegisteredHotKey:
            return "no_registered_hotkey"
        case .unsupportedKey:
            return "unsupported_key"
        case .eventCreationFailed:
            return "event_creation_failed"
        }
    }

    var message: String {
        switch self {
        case .posted:
            return "Physical hotkey event posted."
        case .accessibilityNotTrusted:
            return "Physical hotkey tests require Accessibility permission for the app posting CGEvent keyboard input."
        case .noRegisteredHotKey:
            return "No registered hotkey is available for the requested profile."
        case let .unsupportedKey(key):
            return "Unsupported physical hotkey key: \(key)."
        case .eventCreationFailed:
            return "Could not create one or more CGEvent keyboard events."
        }
    }
}

final class HotKeyController {
    private let logger = Logger(subsystem: "dev.benbernard.fzf-palette", category: "hotkey")
    private var eventHandlerRef: EventHandlerRef?
    private var registrationsByID: [UInt32: HotKeyRegistration] = [:]
    private var orderedRegistrationIDs: [UInt32] = []
    private var onHotKey: ((ProfileHotKeyBinding) -> Void)?
    private(set) var registrationError: String?

    private struct HotKeyRegistration {
        var id: UInt32
        var configuration: ProfileHotKeyBinding
        var ref: EventHotKeyRef?
        var error: String?
    }

    var isRegistered: Bool {
        registrationsByID.values.contains { $0.ref != nil }
    }

    var activeBinding: HotKeyBinding? {
        activeBindings.first?.binding
    }

    var activeBindings: [ProfileHotKeyBinding] {
        orderedRegistrationIDs.compactMap { registrationsByID[$0]?.configuration }
    }

    var hotKeyStatuses: [ProfileHotKeyStatus] {
        orderedRegistrationIDs.compactMap { id in
            guard let registration = registrationsByID[id] else {
                return nil
            }
            return ProfileHotKeyStatus(
                profile: registration.configuration.profile,
                hotkey: registration.configuration.binding.displayString,
                registered: registration.ref != nil,
                error: registration.error
            )
        }
    }

    func start(bindings: [ProfileHotKeyBinding], onHotKey: @escaping (ProfileHotKeyBinding) -> Void) {
        self.onHotKey = onHotKey
        installEventHandlerIfNeeded()
        registerHotKeys(bindings)
    }

    func simulateHotKeyForTests(profile: String? = nil) {
        guard let registration = registration(for: profile) else {
            return
        }
        onHotKey?(registration.configuration)
    }

    func postCarbonHotKeyEventForTests(profile: String? = nil) -> OSStatus {
        guard let registration = registration(for: profile), registration.ref != nil else {
            return OSStatus(-1)
        }

        var event: EventRef?
        let createStatus = CreateEvent(
            nil,
            OSType(kEventClassKeyboard),
            UInt32(kEventHotKeyPressed),
            GetCurrentEventTime(),
            UInt32(kEventAttributeNone),
            &event
        )
        guard createStatus == noErr, let event else {
            return createStatus
        }
        defer {
            ReleaseEvent(event)
        }

        var eventHotKeyID = makeHotKeyID(id: registration.id)
        let setStatus = SetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            MemoryLayout<EventHotKeyID>.size,
            &eventHotKeyID
        )
        guard setStatus == noErr else {
            return setStatus
        }

        return SendEventToEventTarget(event, GetEventDispatcherTarget())
    }

    func postPhysicalHotKeyEventForTests(profile: String? = nil) -> PhysicalHotKeyPostResult {
        guard AXIsProcessTrusted() else {
            return .accessibilityNotTrusted
        }
        guard let registration = registration(for: profile), registration.ref != nil else {
            return .noRegisteredHotKey
        }
        guard let keyCode = carbonKeyCode(for: registration.configuration.binding.key) else {
            return .unsupportedKey(registration.configuration.binding.key)
        }
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return .eventCreationFailed
        }

        source.localEventsSuppressionInterval = 0
        let modifiers = registration.configuration.binding.modifiers
        let finalFlags = cgEventFlags(for: modifiers)
        var activeFlags = CGEventFlags()

        for modifier in modifiers {
            activeFlags.insert(cgEventFlag(for: modifier))
            guard postKeyboardEvent(
                source: source,
                keyCode: modifierKeyCode(for: modifier),
                keyDown: true,
                flags: activeFlags
            ) else {
                return .eventCreationFailed
            }
        }

        guard postKeyboardEvent(
            source: source,
            keyCode: CGKeyCode(keyCode),
            keyDown: true,
            flags: finalFlags
        ), postKeyboardEvent(
            source: source,
            keyCode: CGKeyCode(keyCode),
            keyDown: false,
            flags: finalFlags
        ) else {
            releasePhysicalModifiers(source: source, modifiers: modifiers, activeFlags: activeFlags)
            return .eventCreationFailed
        }

        releasePhysicalModifiers(source: source, modifiers: modifiers, activeFlags: activeFlags)
        return .posted
    }

    deinit {
        unregisterHotKeys()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let userData else {
                    return noErr
                }
                let controller = Unmanaged<HotKeyController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                controller.handleHotKeyPressed(event: event)
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        if status != noErr {
            logger.error("InstallEventHandler failed: \(status)")
        }
    }

    private func registerHotKeys(_ bindings: [ProfileHotKeyBinding]) {
        unregisterHotKeys()
        registrationError = nil
        let requestedBindings = bindings.isEmpty
            ? [ProfileHotKeyBinding(profile: "default", binding: .default)]
            : bindings
        var errors: [String] = []

        for (index, configuration) in requestedBindings.enumerated() {
            let id = UInt32(index + 1)
            orderedRegistrationIDs.append(id)

            guard let keyCode = carbonKeyCode(for: configuration.binding.key) else {
                let error = "Unsupported hotkey key: \(configuration.binding.key)"
                errors.append(error)
                registrationsByID[id] = HotKeyRegistration(id: id, configuration: configuration, ref: nil, error: error)
                logger.error("\(error, privacy: .public)")
                continue
            }

            var hotKeyRef: EventHotKeyRef?
            let modifiers = carbonModifierMask(for: configuration.binding.modifiers)
            let status = RegisterEventHotKey(
                keyCode,
                modifiers,
                makeHotKeyID(id: id),
                GetEventDispatcherTarget(),
                0,
                &hotKeyRef
            )

            if status == noErr {
                registrationsByID[id] = HotKeyRegistration(id: id, configuration: configuration, ref: hotKeyRef, error: nil)
                logger.info("Registered global hotkey \(configuration.binding.displayString, privacy: .public) for profile \(configuration.profile, privacy: .public)")
            } else {
                let error = "RegisterEventHotKey failed for \(configuration.binding.displayString): \(status)"
                errors.append(error)
                registrationsByID[id] = HotKeyRegistration(id: id, configuration: configuration, ref: nil, error: error)
                logger.error("\(error, privacy: .public)")
            }
        }

        if !errors.isEmpty {
            registrationError = errors.joined(separator: "; ")
        }
    }

    private func unregisterHotKeys() {
        for registration in registrationsByID.values {
            if let ref = registration.ref {
                UnregisterEventHotKey(ref)
            }
        }
        registrationsByID = [:]
        orderedRegistrationIDs = []
    }

    private func handleHotKeyPressed(event: EventRef?) {
        let id = hotKeyID(from: event)
        DispatchQueue.main.async { [weak self] in
            guard let self, let registration = self.registrationsByID[id] ?? self.registration(for: nil) else {
                return
            }
            self.onHotKey?(registration.configuration)
        }
    }

    private func registration(for profile: String?) -> HotKeyRegistration? {
        if let profile {
            return orderedRegistrationIDs.compactMap { registrationsByID[$0] }.first { $0.configuration.profile == profile }
        }
        return orderedRegistrationIDs.compactMap { registrationsByID[$0] }.first { $0.ref != nil }
            ?? orderedRegistrationIDs.compactMap { registrationsByID[$0] }.first
    }

    private func hotKeyID(from event: EventRef?) -> UInt32 {
        guard let event else {
            return orderedRegistrationIDs.first ?? 1
        }

        var eventHotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &eventHotKeyID
        )
        guard status == noErr else {
            return orderedRegistrationIDs.first ?? 1
        }
        return eventHotKeyID.id
    }

    private func fourCharCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { result, byte in
            (result << 8) + OSType(byte)
        }
    }

    private func makeHotKeyID(id: UInt32) -> EventHotKeyID {
        EventHotKeyID(
            signature: fourCharCode("FZFP"),
            id: id
        )
    }

    private func carbonModifierMask(for modifiers: [HotKeyModifier]) -> UInt32 {
        modifiers.reduce(0) { mask, modifier in
            switch modifier {
            case .control:
                return mask | UInt32(controlKey)
            case .option:
                return mask | UInt32(optionKey)
            case .shift:
                return mask | UInt32(shiftKey)
            case .command:
                return mask | UInt32(cmdKey)
            }
        }
    }

    private func cgEventFlags(for modifiers: [HotKeyModifier]) -> CGEventFlags {
        modifiers.reduce(CGEventFlags()) { flags, modifier in
            var result = flags
            result.insert(cgEventFlag(for: modifier))
            return result
        }
    }

    private func cgEventFlag(for modifier: HotKeyModifier) -> CGEventFlags {
        switch modifier {
        case .control:
            return .maskControl
        case .option:
            return .maskAlternate
        case .shift:
            return .maskShift
        case .command:
            return .maskCommand
        }
    }

    private func modifierKeyCode(for modifier: HotKeyModifier) -> CGKeyCode {
        switch modifier {
        case .control:
            return CGKeyCode(kVK_Control)
        case .option:
            return CGKeyCode(kVK_Option)
        case .shift:
            return CGKeyCode(kVK_Shift)
        case .command:
            return CGKeyCode(kVK_Command)
        }
    }

    private func postKeyboardEvent(
        source: CGEventSource,
        keyCode: CGKeyCode,
        keyDown: Bool,
        flags: CGEventFlags
    ) -> Bool {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else {
            return false
        }
        event.flags = flags
        event.post(tap: .cghidEventTap)
        return true
    }

    private func releasePhysicalModifiers(
        source: CGEventSource,
        modifiers: [HotKeyModifier],
        activeFlags: CGEventFlags
    ) {
        var flags = activeFlags
        for modifier in modifiers.reversed() {
            let flag = cgEventFlag(for: modifier)
            flags.remove(flag)
            _ = postKeyboardEvent(
                source: source,
                keyCode: modifierKeyCode(for: modifier),
                keyDown: false,
                flags: flags
            )
        }
    }

    private func carbonKeyCode(for key: String) -> UInt32? {
        switch key {
        case "a": return UInt32(kVK_ANSI_A)
        case "b": return UInt32(kVK_ANSI_B)
        case "c": return UInt32(kVK_ANSI_C)
        case "d": return UInt32(kVK_ANSI_D)
        case "e": return UInt32(kVK_ANSI_E)
        case "f": return UInt32(kVK_ANSI_F)
        case "g": return UInt32(kVK_ANSI_G)
        case "h": return UInt32(kVK_ANSI_H)
        case "i": return UInt32(kVK_ANSI_I)
        case "j": return UInt32(kVK_ANSI_J)
        case "k": return UInt32(kVK_ANSI_K)
        case "l": return UInt32(kVK_ANSI_L)
        case "m": return UInt32(kVK_ANSI_M)
        case "n": return UInt32(kVK_ANSI_N)
        case "o": return UInt32(kVK_ANSI_O)
        case "p": return UInt32(kVK_ANSI_P)
        case "q": return UInt32(kVK_ANSI_Q)
        case "r": return UInt32(kVK_ANSI_R)
        case "s": return UInt32(kVK_ANSI_S)
        case "t": return UInt32(kVK_ANSI_T)
        case "u": return UInt32(kVK_ANSI_U)
        case "v": return UInt32(kVK_ANSI_V)
        case "w": return UInt32(kVK_ANSI_W)
        case "x": return UInt32(kVK_ANSI_X)
        case "y": return UInt32(kVK_ANSI_Y)
        case "z": return UInt32(kVK_ANSI_Z)
        case "0": return UInt32(kVK_ANSI_0)
        case "1": return UInt32(kVK_ANSI_1)
        case "2": return UInt32(kVK_ANSI_2)
        case "3": return UInt32(kVK_ANSI_3)
        case "4": return UInt32(kVK_ANSI_4)
        case "5": return UInt32(kVK_ANSI_5)
        case "6": return UInt32(kVK_ANSI_6)
        case "7": return UInt32(kVK_ANSI_7)
        case "8": return UInt32(kVK_ANSI_8)
        case "9": return UInt32(kVK_ANSI_9)
        case "space": return UInt32(kVK_Space)
        case "return": return UInt32(kVK_Return)
        case "tab": return UInt32(kVK_Tab)
        case "escape": return UInt32(kVK_Escape)
        case "delete": return UInt32(kVK_Delete)
        case "up": return UInt32(kVK_UpArrow)
        case "down": return UInt32(kVK_DownArrow)
        case "left": return UInt32(kVK_LeftArrow)
        case "right": return UInt32(kVK_RightArrow)
        case "minus": return UInt32(kVK_ANSI_Minus)
        case "equal": return UInt32(kVK_ANSI_Equal)
        case "leftbracket": return UInt32(kVK_ANSI_LeftBracket)
        case "rightbracket": return UInt32(kVK_ANSI_RightBracket)
        case "backslash": return UInt32(kVK_ANSI_Backslash)
        case "semicolon": return UInt32(kVK_ANSI_Semicolon)
        case "quote": return UInt32(kVK_ANSI_Quote)
        case "comma": return UInt32(kVK_ANSI_Comma)
        case "period": return UInt32(kVK_ANSI_Period)
        case "slash": return UInt32(kVK_ANSI_Slash)
        case "grave": return UInt32(kVK_ANSI_Grave)
        case "f1": return UInt32(kVK_F1)
        case "f2": return UInt32(kVK_F2)
        case "f3": return UInt32(kVK_F3)
        case "f4": return UInt32(kVK_F4)
        case "f5": return UInt32(kVK_F5)
        case "f6": return UInt32(kVK_F6)
        case "f7": return UInt32(kVK_F7)
        case "f8": return UInt32(kVK_F8)
        case "f9": return UInt32(kVK_F9)
        case "f10": return UInt32(kVK_F10)
        case "f11": return UInt32(kVK_F11)
        case "f12": return UInt32(kVK_F12)
        case "f13": return UInt32(kVK_F13)
        case "f14": return UInt32(kVK_F14)
        case "f15": return UInt32(kVK_F15)
        case "f16": return UInt32(kVK_F16)
        case "f17": return UInt32(kVK_F17)
        case "f18": return UInt32(kVK_F18)
        case "f19": return UInt32(kVK_F19)
        case "f20": return UInt32(kVK_F20)
        default: return nil
        }
    }
}
