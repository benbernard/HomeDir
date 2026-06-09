import Foundation

public enum FzfOptionDisposition: String, Codable, Equatable {
    case supported
    case ignored
    case unsupported
    case error
}

public struct FzfOptionClassification: Codable, Equatable {
    public var option: String
    public var disposition: FzfOptionDisposition
    public var reason: String

    public init(option: String, disposition: FzfOptionDisposition, reason: String) {
        self.option = option
        self.disposition = disposition
        self.reason = reason
    }
}

public enum FzfOptionClassifier {
    private static let ignoredLongOptions = [
        "--height",
        "--reverse",
        "--border",
        "--border-label",
        "--border-label-pos",
        "--color"
    ]

    private static let supportedLongOptions = [
        "--multi",
        "--no-multi",
        "--ansi",
        "--no-sort",
        "--exact",
        "--no-exact",
        "--extended",
        "--scheme",
        "--tiebreak",
        "--nth",
        "-n",
        "--delimiter",
        "--with-nth",
        "--query",
        "--prompt",
        "--header",
        "--pointer",
        "--marker",
        "--info",
        "--preview",
        "--preview-window",
        "--bind"
    ]

    public static func classify(_ arguments: [String]) -> [FzfOptionClassification] {
        var classifications: [FzfOptionClassification] = []
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            let next = index + 1 < arguments.count ? arguments[index + 1] : nil
            let normalized = optionName(argument)

            if argument == "-i"
                || argument == "+i"
                || argument == "-e"
                || argument == "+e"
                || argument == "-x"
                || argument == "+s"
                || argument == "-m"
                || argument == "+m"
                || argument == "-q"
                || argument == "-d"
                || argument == "-n" {
                classifications.append(.init(
                    option: argument,
                    disposition: .supported,
                    reason: "Used by local fzf configuration"
                ))
                index += consumesValue(argument) ? 2 : 1
                continue
            }

            if let normalized, ignoredLongOptions.contains(normalized) {
                classifications.append(.init(
                    option: argument,
                    disposition: .ignored,
                    reason: "Native UI owns this presentation detail"
                ))
                index += consumesValue(normalized, argument: argument) ? 2 : 1
                continue
            }

            if let normalized, supportedLongOptions.contains(normalized) {
                classifications.append(classifySupported(option: normalized, argument: argument, next: next))
                index += consumesValue(normalized, argument: argument) ? 2 : 1
                continue
            }

            classifications.append(.init(
                option: argument,
                disposition: .unsupported,
                reason: "Not in the initial supported local fzf subset"
            ))
            index += 1
        }

        return classifications
    }

    private static func classifySupported(
        option: String,
        argument: String,
        next: String?
    ) -> FzfOptionClassification {
        if option == "--bind" {
            let value = inlineValue(argument) ?? next ?? ""
            if isSupportedBind(value) {
                return .init(
                    option: argument,
                    disposition: .supported,
                    reason: "Supported local bind action"
                )
            }
            return .init(
                option: argument,
                disposition: .unsupported,
                reason: "Only select-all, deselect-all, and toggle-preview binds are supported initially"
            )
        }

        if option == "--tiebreak" {
            let value = inlineValue(argument) ?? next ?? ""
            if parseSupportedTiebreaks(value) != nil {
                return .init(option: argument, disposition: .supported, reason: "Mapped to native fuzzy ranking")
            }
            return .init(
                option: argument,
                disposition: .unsupported,
                reason: "Only --tiebreak length, chunk, begin, end, and index criteria are supported initially"
            )
        }

        if option == "--scheme" {
            let value = inlineValue(argument) ?? next ?? ""
            if value == "default" || value == "path" || value == "history" {
                return .init(option: argument, disposition: .supported, reason: "Mapped to native fuzzy ranking")
            }
            return .init(
                option: argument,
                disposition: .unsupported,
                reason: "Only --scheme=default, --scheme=path, and --scheme=history are supported initially"
            )
        }

        if option == "--info" {
            let value = inlineValue(argument) ?? next ?? ""
            if value == "inline" {
                return .init(option: argument, disposition: .supported, reason: "Mapped to native inline status")
            }
            return .init(
                option: argument,
                disposition: .unsupported,
                reason: "Only --info=inline is supported initially"
            )
        }

        return .init(
            option: argument,
            disposition: .supported,
            reason: "Required by local fzf workflows"
        )
    }

    private static func optionName(_ argument: String) -> String? {
        if argument.hasPrefix("--") {
            if let equals = argument.firstIndex(of: "=") {
                return String(argument[..<equals])
            }
            return argument
        }
        if argument.hasPrefix("-d"), argument.count > 2 {
            return "-d"
        }
        if argument.hasPrefix("-n"), argument.count > 2 {
            return "-n"
        }
        if argument.hasPrefix("-q"), argument.count > 2 {
            return "-q"
        }
        return nil
    }

    private static func inlineValue(_ argument: String) -> String? {
        guard let equals = argument.firstIndex(of: "=") else {
            return nil
        }
        return String(argument[argument.index(after: equals)...])
    }

    private static func consumesValue(_ shortOption: String) -> Bool {
        shortOption == "-q" || shortOption == "-d" || shortOption == "-n"
    }

    private static func consumesValue(_ normalized: String, argument: String) -> Bool {
        guard inlineValue(argument) == nil else {
            return false
        }
        return [
            "--height",
            "--border-label",
            "--border-label-pos",
            "--prompt",
            "--header",
            "--pointer",
            "--marker",
            "--info",
            "--color",
            "--scheme",
            "--tiebreak",
            "--nth",
            "--delimiter",
            "--with-nth",
            "--query",
            "--preview",
            "--preview-window",
            "--bind"
        ].contains(normalized)
    }

    private static func isSupportedBind(_ value: String) -> Bool {
        let actions = value.split(separator: ",").map(String.init)
        return actions.allSatisfy { action in
            action == "ctrl-A:select-all"
                || action == "ctrl-a:select-all"
                || action == "ctrl-d:deselect-all"
                || action == "ctrl-/:toggle-preview"
        }
    }

    fileprivate static func parseSupportedTiebreaks(_ value: String) -> [FuzzyTiebreak]? {
        let rawCriteria = value
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard !rawCriteria.isEmpty, rawCriteria.count <= 3 else {
            return nil
        }

        var seen: Set<String> = []
        var parsed: [FuzzyTiebreak] = []
        for (index, criterion) in rawCriteria.enumerated() {
            guard !criterion.isEmpty, !seen.contains(criterion) else {
                return nil
            }
            seen.insert(criterion)

            switch criterion {
            case "length":
                parsed.append(.length)
            case "chunk":
                parsed.append(.chunk)
            case "begin":
                parsed.append(.begin)
            case "end":
                parsed.append(.end)
            case "index":
                guard index == rawCriteria.count - 1 else {
                    return nil
                }
                parsed.append(.index)
            default:
                return nil
            }
        }
        return parsed
    }
}

public enum FzfRuntimeOptions {
    public static func isMultiSelectEnabled(_ arguments: [String]) -> Bool {
        var enabled = false
        for argument in arguments {
            if argument == "-m" || argument == "--multi" || argument.hasPrefix("--multi=") {
                enabled = true
            } else if argument == "+m" || argument == "--no-multi" {
                enabled = false
            }
        }
        return enabled
    }

    public static func searchOptions(_ arguments: [String]) -> FuzzySearchOptions {
        var caseMode = FuzzyCaseMode.smart
        var tiebreaks = [FuzzyTiebreak.length]
        var exactMode = false
        var sort = true
        var scheme = FuzzyScheme.default
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "+i" {
                caseMode = .caseSensitive
            } else if argument == "-i" {
                caseMode = .caseInsensitive
            } else if argument == "-e" || argument == "--exact" {
                exactMode = true
            } else if argument == "+e" || argument == "--no-exact" {
                exactMode = false
            } else if argument == "+s" || argument == "--no-sort" {
                sort = false
            } else if argument == "--tiebreak", index + 1 < arguments.count {
                if let parsed = FzfOptionClassifier.parseSupportedTiebreaks(arguments[index + 1]) {
                    tiebreaks = parsed
                }
                index += 1
            } else if argument.hasPrefix("--tiebreak=") {
                let value = String(argument.dropFirst("--tiebreak=".count))
                if let parsed = FzfOptionClassifier.parseSupportedTiebreaks(value) {
                    tiebreaks = parsed
                }
            } else if argument == "--scheme", index + 1 < arguments.count {
                if let parsed = FuzzyScheme(rawValue: arguments[index + 1]) {
                    scheme = parsed
                }
                index += 1
            } else if argument.hasPrefix("--scheme=") {
                let value = String(argument.dropFirst("--scheme=".count))
                if let parsed = FuzzyScheme(rawValue: value) {
                    scheme = parsed
                }
            }
            index += 1
        }
        if scheme == .history {
            tiebreaks = []
        }
        return FuzzySearchOptions(
            caseMode: caseMode,
            tiebreaks: tiebreaks,
            exactMode: exactMode,
            sort: sort,
            scheme: scheme
        )
    }

    public static func isPreviewToggleEnabled(_ arguments: [String]) -> Bool {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--bind", index + 1 < arguments.count {
                if bindListContainsTogglePreview(arguments[index + 1]) {
                    return true
                }
                index += 1
            } else if argument.hasPrefix("--bind=") {
                let value = String(argument.dropFirst("--bind=".count))
                if bindListContainsTogglePreview(value) {
                    return true
                }
            }
            index += 1
        }
        return false
    }

    private static func bindListContainsTogglePreview(_ value: String) -> Bool {
        value.split(separator: ",").contains { action in
            action == "ctrl-/:toggle-preview"
        }
    }
}

public enum FzfDefaultOptions {
    public static func arguments(environment: [String: String] = ProcessInfo.processInfo.environment) -> [String] {
        var arguments: [String] = []
        if let filePath = environment["FZF_DEFAULT_OPTS_FILE"], !filePath.isEmpty {
            let expanded = (filePath as NSString).expandingTildeInPath
            if let contents = try? String(contentsOfFile: expanded, encoding: .utf8) {
                arguments.append(contentsOf: ShellWords.split(contents))
            }
        }
        if let value = environment["FZF_DEFAULT_OPTS"], !value.isEmpty {
            arguments.append(contentsOf: ShellWords.split(value))
        }
        return arguments
    }
}

private enum ShellWords {
    static func split(_ value: String) -> [String] {
        var words: [String] = []
        var current = ""
        var quote: Character?
        var escaping = false

        for character in value {
            if escaping {
                current.append(character)
                escaping = false
                continue
            }

            if character == "\\", quote != "'" {
                escaping = true
                continue
            }

            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }

            if character == "'" || character == "\"" {
                quote = character
                continue
            }

            if character.isWhitespace {
                if !current.isEmpty {
                    words.append(current)
                    current.removeAll(keepingCapacity: true)
                }
                continue
            }

            current.append(character)
        }

        if escaping {
            current.append("\\")
        }
        if !current.isEmpty {
            words.append(current)
        }
        return words
    }
}
