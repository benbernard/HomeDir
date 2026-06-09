import Foundation

public struct PickerProfile: Codable, Equatable {
    public var name: String
    public var title: String
    public var cwd: String?
    public var source: PickerSource
    public var query: String
    public var fzfOptions: [String]
    public var display: DisplayConfig
    public var preview: PreviewConfig?
    public var result: ResultConfig

    public init(
        name: String,
        title: String,
        cwd: String? = nil,
        source: PickerSource = .profile,
        query: String = "",
        fzfOptions: [String] = [],
        display: DisplayConfig = DisplayConfig(),
        preview: PreviewConfig? = nil,
        result: ResultConfig = ResultConfig()
    ) {
        self.name = name
        self.title = title
        self.cwd = cwd
        self.source = source
        self.query = query
        self.fzfOptions = fzfOptions
        self.display = display
        self.preview = preview
        self.result = result
    }

    public func validationErrors() -> [ProfileValidationIssue] {
        var issues: [ProfileValidationIssue] = []

        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(ProfileValidationIssue(field: "name", message: "Profile name cannot be empty"))
        }

        issues.append(contentsOf: source.validationIssues())

        for classification in FzfOptionClassifier.classify(fzfOptions) {
            if classification.disposition == .unsupported || classification.disposition == .error {
                issues.append(ProfileValidationIssue(
                    field: "fzfOptions",
                    message: "\(classification.option): \(classification.reason)"
                ))
            }
        }

        if let preview {
            issues.append(contentsOf: preview.validationIssues())
        }

        return issues
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case title
        case cwd
        case source
        case query
        case fzfOptions
        case display
        case preview
        case result
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? name
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        source = try container.decodeIfPresent(PickerSource.self, forKey: .source) ?? .profile
        query = try container.decodeIfPresent(String.self, forKey: .query) ?? ""
        fzfOptions = try container.decodeIfPresent([String].self, forKey: .fzfOptions) ?? []
        display = try container.decodeIfPresent(DisplayConfig.self, forKey: .display) ?? DisplayConfig()
        preview = try container.decodeIfPresent(PreviewConfig.self, forKey: .preview)
        result = try container.decodeIfPresent(ResultConfig.self, forKey: .result) ?? ResultConfig()
    }
}

public enum PickerSource: Codable, Equatable {
    case profile
    case command(String)
    case stdin
    case staticItems([String])
    case twoStage(TwoStageSource)

    private enum CodingKeys: String, CodingKey {
        case type
        case command
        case items
        case first
        case second
    }

    private enum SourceType: String, Codable {
        case profile
        case command
        case stdin
        case staticItems = "static"
        case twoStage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(SourceType.self, forKey: .type)
        switch type {
        case .profile:
            self = .profile
        case .command:
            self = .command(try container.decode(String.self, forKey: .command))
        case .stdin:
            self = .stdin
        case .staticItems:
            self = .staticItems(try container.decode([String].self, forKey: .items))
        case .twoStage:
            self = .twoStage(TwoStageSource(
                first: try container.decode(PickerStage.self, forKey: .first),
                second: try container.decode(PickerStage.self, forKey: .second)
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .profile:
            try container.encode(SourceType.profile, forKey: .type)
        case let .command(command):
            try container.encode(SourceType.command, forKey: .type)
            try container.encode(command, forKey: .command)
        case .stdin:
            try container.encode(SourceType.stdin, forKey: .type)
        case let .staticItems(items):
            try container.encode(SourceType.staticItems, forKey: .type)
            try container.encode(items, forKey: .items)
        case let .twoStage(source):
            try container.encode(SourceType.twoStage, forKey: .type)
            try container.encode(source.first, forKey: .first)
            try container.encode(source.second, forKey: .second)
        }
    }

    public func validationIssues(path: String = "source") -> [ProfileValidationIssue] {
        switch self {
        case let .command(command) where command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            return [ProfileValidationIssue(field: "\(path).command", message: "Source command cannot be empty")]
        case let .twoStage(source):
            return source.validationIssues(path: path)
        default:
            return []
        }
    }
}

public struct TwoStageSource: Codable, Equatable {
    public var first: PickerStage
    public var second: PickerStage

    public init(first: PickerStage, second: PickerStage) {
        self.first = first
        self.second = second
    }

    public func validationIssues(path: String = "source") -> [ProfileValidationIssue] {
        first.validationIssues(path: "\(path).first") + second.validationIssues(path: "\(path).second")
    }
}

public struct PickerStage: Codable, Equatable {
    public var title: String?
    public var cwd: String?
    public var query: String
    public var source: StageSource
    public var fzfOptions: [String]
    public var display: DisplayConfig
    public var preview: PreviewConfig?
    public var result: ResultConfig

    public init(
        title: String? = nil,
        cwd: String? = nil,
        query: String = "",
        source: StageSource,
        fzfOptions: [String] = [],
        display: DisplayConfig = DisplayConfig(),
        preview: PreviewConfig? = nil,
        result: ResultConfig = ResultConfig()
    ) {
        self.title = title
        self.cwd = cwd
        self.query = query
        self.source = source
        self.fzfOptions = fzfOptions
        self.display = display
        self.preview = preview
        self.result = result
    }

    public func validationIssues(path: String) -> [ProfileValidationIssue] {
        var issues = source.validationIssues(path: "\(path).source")

        for classification in FzfOptionClassifier.classify(fzfOptions) {
            if classification.disposition == .unsupported || classification.disposition == .error {
                issues.append(ProfileValidationIssue(
                    field: "\(path).fzfOptions",
                    message: "\(classification.option): \(classification.reason)"
                ))
            }
        }

        if let preview {
            issues.append(contentsOf: preview.validationIssues(path: "\(path).preview"))
        }

        return issues
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case cwd
        case query
        case source
        case fzfOptions
        case display
        case preview
        case result
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        query = try container.decodeIfPresent(String.self, forKey: .query) ?? ""
        source = try container.decode(StageSource.self, forKey: .source)
        fzfOptions = try container.decodeIfPresent([String].self, forKey: .fzfOptions) ?? []
        display = try container.decodeIfPresent(DisplayConfig.self, forKey: .display) ?? DisplayConfig()
        preview = try container.decodeIfPresent(PreviewConfig.self, forKey: .preview)
        result = try container.decodeIfPresent(ResultConfig.self, forKey: .result) ?? ResultConfig()
    }
}

public enum StageSource: Codable, Equatable {
    case command(String)
    case staticItems([String])

    private enum CodingKeys: String, CodingKey {
        case type
        case command
        case items
    }

    private enum SourceType: String, Codable {
        case command
        case staticItems = "static"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(SourceType.self, forKey: .type)
        switch type {
        case .command:
            self = .command(try container.decode(String.self, forKey: .command))
        case .staticItems:
            self = .staticItems(try container.decode([String].self, forKey: .items))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .command(command):
            try container.encode(SourceType.command, forKey: .type)
            try container.encode(command, forKey: .command)
        case let .staticItems(items):
            try container.encode(SourceType.staticItems, forKey: .type)
            try container.encode(items, forKey: .items)
        }
    }

    public func validationIssues(path: String) -> [ProfileValidationIssue] {
        switch self {
        case let .command(command) where command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            return [ProfileValidationIssue(field: "\(path).command", message: "Source command cannot be empty")]
        default:
            return []
        }
    }
}

public struct DisplayConfig: Codable, Equatable {
    public var ansi: Bool
    public var delimiter: String?
    public var nth: String?
    public var withNth: String?
    public var prompt: String?
    public var header: String?
    public var pointer: String?
    public var marker: String?
    public var info: String?

    public init(
        ansi: Bool = false,
        delimiter: String? = nil,
        nth: String? = nil,
        withNth: String? = nil,
        prompt: String? = nil,
        header: String? = nil,
        pointer: String? = nil,
        marker: String? = nil,
        info: String? = nil
    ) {
        self.ansi = ansi
        self.delimiter = delimiter
        self.nth = nth
        self.withNth = withNth
        self.prompt = prompt
        self.header = header
        self.pointer = pointer
        self.marker = marker
        self.info = info
    }

    private enum CodingKeys: String, CodingKey {
        case ansi
        case delimiter
        case nth
        case withNth
        case prompt
        case header
        case pointer
        case marker
        case info
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ansi = try container.decodeIfPresent(Bool.self, forKey: .ansi) ?? false
        delimiter = try container.decodeIfPresent(String.self, forKey: .delimiter)
        nth = try container.decodeIfPresent(String.self, forKey: .nth)
        withNth = try container.decodeIfPresent(String.self, forKey: .withNth)
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
        header = try container.decodeIfPresent(String.self, forKey: .header)
        pointer = try container.decodeIfPresent(String.self, forKey: .pointer)
        marker = try container.decodeIfPresent(String.self, forKey: .marker)
        info = try container.decodeIfPresent(String.self, forKey: .info)
    }
}

public struct PreviewConfig: Codable, Equatable {
    public var command: String
    public var window: String
    public var debounceMs: Int

    public init(command: String, window: String = "right:50%:wrap", debounceMs: Int = 75) {
        self.command = command
        self.window = window
        self.debounceMs = debounceMs
    }

    public var layout: PreviewWindowLayout {
        PreviewWindowLayout.parse(window)
    }

    public func validationIssues(path: String = "preview") -> [ProfileValidationIssue] {
        if command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [ProfileValidationIssue(field: "\(path).command", message: "Preview command cannot be empty")]
        }
        return []
    }

    private enum CodingKeys: String, CodingKey {
        case command
        case window
        case debounceMs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        command = try container.decode(String.self, forKey: .command)
        window = try container.decodeIfPresent(String.self, forKey: .window) ?? "right:50%:wrap"
        debounceMs = try container.decodeIfPresent(Int.self, forKey: .debounceMs) ?? 75
    }
}

public enum PreviewWindowPosition: String, Codable, Equatable {
    case right
    case left
    case up
    case down
}

public struct PreviewWindowLayout: Codable, Equatable {
    public var position: PreviewWindowPosition
    public var sizeFraction: Double
    public var wrap: Bool
    public var scrollExpression: String?

    public init(
        position: PreviewWindowPosition = .right,
        sizeFraction: Double = 0.5,
        wrap: Bool = false,
        scrollExpression: String? = nil
    ) {
        self.position = position
        self.sizeFraction = sizeFraction
        self.wrap = wrap
        self.scrollExpression = scrollExpression
    }

    public static func parse(_ value: String) -> PreviewWindowLayout {
        var layout = PreviewWindowLayout()
        let tokens = value
            .split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init)

        for token in tokens {
            switch token.lowercased() {
            case "right":
                layout.position = .right
            case "left":
                layout.position = .left
            case "up":
                layout.position = .up
            case "down":
                layout.position = .down
            case "wrap":
                layout.wrap = true
            case "nowrap", "no-wrap":
                layout.wrap = false
            default:
                if let fraction = percentFraction(token) {
                    layout.sizeFraction = fraction
                } else if token.hasPrefix("+") {
                    layout.scrollExpression = token
                }
            }
        }

        return layout
    }

    public var isVerticalSplit: Bool {
        position == .left || position == .right
    }

    public func scrollTarget(row: String, delimiter: String?) -> PreviewScrollTarget? {
        Self.scrollTarget(expression: scrollExpression, row: row, delimiter: delimiter)
    }

    public static func scrollTarget(
        expression: String?,
        row: String,
        delimiter: String?
    ) -> PreviewScrollTarget? {
        guard var expression, expression.hasPrefix("+") else {
            return nil
        }

        expression.removeFirst()
        let fields = PlaceholderExpansion.splitFields(row: row, delimiter: delimiter)
        for fieldIndex in 1...fields.count {
            expression = expression.replacingOccurrences(
                of: "{\(fieldIndex)}",
                with: fields[fieldIndex - 1]
            )
        }

        let shouldCenter = expression.contains("-/2")
        guard let lineRange = expression.range(of: #"^\d+"#, options: .regularExpression),
              let line = Int(expression[lineRange]),
              line > 0 else {
            return nil
        }

        return PreviewScrollTarget(line: line, centerInPreview: shouldCenter)
    }

    private static func percentFraction(_ token: String) -> Double? {
        guard token.hasSuffix("%") else {
            return nil
        }
        let numberText = token.dropLast()
        guard let percent = Double(numberText) else {
            return nil
        }
        return min(0.9, max(0.1, percent / 100))
    }
}

public struct PreviewScrollTarget: Codable, Equatable {
    public var line: Int
    public var centerInPreview: Bool

    public init(line: Int, centerInPreview: Bool = false) {
        self.line = line
        self.centerInPreview = centerInPreview
    }
}

public struct ResultConfig: Codable, Equatable {
    public var mode: ResultMode
    public var fields: String?
    public var join: JoinMode
    public var command: String?

    public init(
        mode: ResultMode = .return,
        fields: String? = nil,
        join: JoinMode = .newline,
        command: String? = nil
    ) {
        self.mode = mode
        self.fields = fields
        self.join = join
        self.command = command
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case fields
        case join
        case command
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(ResultMode.self, forKey: .mode) ?? .return
        fields = try container.decodeIfPresent(String.self, forKey: .fields)
        join = try container.decodeIfPresent(JoinMode.self, forKey: .join) ?? .newline
        command = try container.decodeIfPresent(String.self, forKey: .command)
    }
}

public enum ResultMode: String, Codable, Equatable {
    case `return`
    case copy
    case paste
    case open
    case command
    case ignore
}

public enum JoinMode: String, Codable, Equatable {
    case newline
    case space
    case nul
    case json
}

public struct ProfileValidationIssue: Codable, Equatable {
    public var field: String
    public var message: String

    public init(field: String, message: String) {
        self.field = field
        self.message = message
    }
}
