import Foundation

public enum HotKeyModifier: String, Codable, Equatable, CaseIterable {
    case control
    case option
    case shift
    case command

    public var displayName: String {
        switch self {
        case .control:
            return "ctrl"
        case .option:
            return "option"
        case .shift:
            return "shift"
        case .command:
            return "cmd"
        }
    }
}

public struct HotKeyBinding: Codable, Equatable {
    public static let `default` = HotKeyBinding(modifiers: [.control, .option], key: "space")

    public var modifiers: [HotKeyModifier]
    public var key: String

    public init(modifiers: [HotKeyModifier], key: String) {
        self.modifiers = HotKeyBinding.canonicalModifiers(modifiers)
        self.key = HotKeyBinding.normalizedKeyName(key) ?? key.lowercased()
    }

    public var displayString: String {
        (modifiers.map(\.displayName) + [key]).joined(separator: "+")
    }

    public static func parse(_ rawValue: String) throws -> HotKeyBinding {
        let parts = rawValue
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else {
            throw HotKeyBindingParseError("Hotkey cannot be empty")
        }

        var modifiers: [HotKeyModifier] = []
        var key: String?
        for part in parts {
            if let modifier = normalizedModifier(part) {
                if modifiers.contains(modifier) {
                    throw HotKeyBindingParseError("Duplicate modifier: \(modifier.displayName)")
                }
                modifiers.append(modifier)
                continue
            }

            guard let normalizedKey = normalizedKeyName(part) else {
                throw HotKeyBindingParseError("Unsupported hotkey key: \(part)")
            }
            if key != nil {
                throw HotKeyBindingParseError("Hotkey must contain exactly one key")
            }
            key = normalizedKey
        }

        guard !modifiers.isEmpty else {
            throw HotKeyBindingParseError("Hotkey must include at least one modifier")
        }
        guard let key else {
            throw HotKeyBindingParseError("Hotkey must include a key")
        }

        return HotKeyBinding(modifiers: modifiers, key: key)
    }

    private static func normalizedModifier(_ value: String) -> HotKeyModifier? {
        switch value {
        case "ctrl", "control", "ctl":
            return .control
        case "opt", "option", "alt":
            return .option
        case "shift":
            return .shift
        case "cmd", "command", "meta":
            return .command
        default:
            return nil
        }
    }

    public static func normalizedKeyName(_ value: String) -> String? {
        let key = value.lowercased()
        if key.count == 1, key.first?.isLetter == true || key.first?.isNumber == true {
            return key
        }

        if key.range(of: #"^f([1-9]|1[0-9]|20)$"#, options: .regularExpression) != nil {
            return key
        }

        switch key {
        case "space", "spc":
            return "space"
        case "enter", "return":
            return "return"
        case "tab":
            return "tab"
        case "esc", "escape":
            return "escape"
        case "delete", "backspace":
            return "delete"
        case "up", "arrowup":
            return "up"
        case "down", "arrowdown":
            return "down"
        case "left", "arrowleft":
            return "left"
        case "right", "arrowright":
            return "right"
        case "-", "minus":
            return "minus"
        case "=", "equal", "equals":
            return "equal"
        case "[", "leftbracket":
            return "leftbracket"
        case "]", "rightbracket":
            return "rightbracket"
        case "\\", "backslash":
            return "backslash"
        case ";", "semicolon":
            return "semicolon"
        case "'", "quote":
            return "quote"
        case ",", "comma":
            return "comma"
        case ".", "period":
            return "period"
        case "/", "slash":
            return "slash"
        case "`", "grave", "backtick":
            return "grave"
        default:
            return nil
        }
    }

    private static func canonicalModifiers(_ modifiers: [HotKeyModifier]) -> [HotKeyModifier] {
        HotKeyModifier.allCases.filter { modifiers.contains($0) }
    }
}

public struct HotKeyBindingParseError: Error, Equatable, CustomStringConvertible {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String {
        message
    }
}

public struct ProfileHotKeyBinding: Codable, Equatable {
    public var profile: String
    public var binding: HotKeyBinding

    public init(profile: String, binding: HotKeyBinding) {
        self.profile = profile
        self.binding = binding
    }

    private enum CodingKeys: String, CodingKey {
        case profile
        case binding
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profile = try container.decodeIfPresent(String.self, forKey: .profile) ?? "default"
        if let bindingText = try? container.decode(String.self, forKey: .binding) {
            do {
                binding = try HotKeyBinding.parse(bindingText)
            } catch {
                throw DecodingError.dataCorruptedError(
                    forKey: .binding,
                    in: container,
                    debugDescription: String(describing: error)
                )
            }
        } else {
            binding = try container.decode(HotKeyBinding.self, forKey: .binding)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(profile, forKey: .profile)
        try container.encode(binding.displayString, forKey: .binding)
    }
}
