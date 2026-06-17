import Foundation

public enum ProgramContextApp: String, Codable, Equatable {
    case codex
    case claude
    case ghostty

    public var displayName: String {
        switch self {
        case .codex:
            return "Codex"
        case .claude:
            return "Claude"
        case .ghostty:
            return "Ghostty"
        }
    }

    public var defaultBundleIdentifier: String {
        switch self {
        case .codex:
            return "com.openai.codex"
        case .claude:
            return "com.anthropic.claudefordesktop"
        case .ghostty:
            return "com.mitchellh.ghostty"
        }
    }

    public var contextEnvironmentKey: String {
        switch self {
        case .codex:
            return "FZF_PALETTE_CODEX_CONTEXT_FILE"
        case .claude:
            return "FZF_PALETTE_CLAUDE_CONTEXT_FILE"
        case .ghostty:
            return "FZF_PALETTE_GHOSTTY_CONTEXT_FILE"
        }
    }

    public static func classify(
        bundleIdentifier: String?,
        appName: String?
    ) -> ProgramContextApp? {
        let normalizedBundle = bundleIdentifier?.lowercased()
        let normalizedName = appName?.lowercased()

        if normalizedBundle == "com.mitchellh.ghostty" || normalizedName == "ghostty" {
            return .ghostty
        }

        if normalizedBundle == "com.openai.codex" || normalizedName == "codex" {
            return .codex
        }

        if normalizedBundle == "com.anthropic.claudefordesktop" || normalizedName == "claude" {
            return .claude
        }

        return nil
    }
}

public struct ProgramContext: Codable, Equatable {
    public var cwd: String
    public var provider: String
    public var appName: String?
    public var bundleIdentifier: String?
    public var detail: String?
    public var updatedAt: String?

    public init(
        cwd: String,
        provider: String,
        appName: String? = nil,
        bundleIdentifier: String? = nil,
        detail: String? = nil,
        updatedAt: String? = nil
    ) {
        self.cwd = cwd
        self.provider = provider
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.detail = detail
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case cwd
        case provider
        case appName
        case bundleIdentifier
        case detail
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cwd = try container.decode(String.self, forKey: .cwd)
        provider = try container.decodeIfPresent(String.self, forKey: .provider) ?? ""
        appName = try container.decodeIfPresent(String.self, forKey: .appName)
        bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    public var environmentValues: [String: String] {
        var values = [
            "FZF_PALETTE_PROGRAM_CONTEXT_CWD": cwd,
            "FZF_PALETTE_PROGRAM_CONTEXT_PROVIDER": provider
        ]
        if let appName, !appName.isEmpty {
            values["FZF_PALETTE_PROGRAM_CONTEXT_APP"] = appName
        }
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            values["FZF_PALETTE_PROGRAM_CONTEXT_BUNDLE_ID"] = bundleIdentifier
        }
        if let detail, !detail.isEmpty {
            values["FZF_PALETTE_PROGRAM_CONTEXT_DETAIL"] = detail
        }
        return values
    }
}

public enum ProgramContextBridgeError: Error, Equatable, CustomStringConvertible {
    case unknownApp(String)
    case missingContextFile(String)
    case invalidDirectory(String)

    public var description: String {
        switch self {
        case .unknownApp(let app):
            return "Unknown program-context app: \(app)"
        case .missingContextFile(let path):
            return "Program context file does not exist: \(path)"
        case .invalidDirectory(let path):
            return "Program context cwd is not an existing directory: \(path)"
        }
    }
}

public enum ProgramContextBridge {
    public static let genericContextFileEnvironmentKey = "FZF_PALETTE_PROGRAM_CONTEXT_FILE"

    public static func app(named rawValue: String) -> ProgramContextApp? {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "codex", "com.openai.codex":
            return .codex
        case "claude", "com.anthropic.claudefordesktop":
            return .claude
        case "ghostty", "com.mitchellh.ghostty":
            return .ghostty
        default:
            return nil
        }
    }

    public static func defaultContextFileURL(
        for app: ProgramContextApp,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appendingPathComponent("Library/Application Support/FzfPalette/program-context", isDirectory: true)
            .appendingPathComponent("\(app.defaultBundleIdentifier).json")
    }

    public static func contextFileURL(
        for app: ProgramContextApp,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if let rawPath = environment[app.contextEnvironmentKey], !rawPath.isEmpty {
            return URL(fileURLWithPath: expandedPath(rawPath))
        }
        if let rawPath = environment[genericContextFileEnvironmentKey], !rawPath.isEmpty {
            return URL(fileURLWithPath: expandedPath(rawPath))
        }
        return defaultContextFileURL(for: app, homeDirectory: homeDirectory)
    }

    public static func loadContext(
        for app: ProgramContextApp,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        appName: String? = nil,
        bundleIdentifier: String? = nil
    ) throws -> ProgramContext {
        let url = contextFileURL(for: app, environment: environment, homeDirectory: homeDirectory)
        guard fileManager.fileExists(atPath: url.path) else {
            throw ProgramContextBridgeError.missingContextFile(url.path)
        }

        let data = try Data(contentsOf: url)
        var context = try JSONDecoder().decode(ProgramContext.self, from: data)
        context.cwd = try normalizedExistingDirectory(context.cwd, fileManager: fileManager)
        context.provider = context.provider.isEmpty ? "\(app.rawValue)-bridge" : context.provider
        context.appName = context.appName ?? appName ?? app.displayName
        context.bundleIdentifier = context.bundleIdentifier ?? bundleIdentifier ?? app.defaultBundleIdentifier
        return context
    }

    public static func writeContext(
        _ context: ProgramContext,
        for app: ProgramContextApp,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) throws -> URL {
        let url = contextFileURL(for: app, environment: environment, homeDirectory: homeDirectory)
        let parent = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

        var normalized = context
        normalized.cwd = try normalizedExistingDirectory(context.cwd, fileManager: fileManager)
        normalized.provider = normalized.provider.isEmpty ? "\(app.rawValue)-bridge" : normalized.provider
        normalized.appName = normalized.appName ?? app.displayName
        normalized.bundleIdentifier = normalized.bundleIdentifier ?? app.defaultBundleIdentifier

        let data = try JSONEncoder().encode(normalized)
        try data.write(to: url, options: [.atomic])
        return url
    }

    public static func removeContext(
        for app: ProgramContextApp,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) throws -> URL {
        let url = contextFileURL(for: app, environment: environment, homeDirectory: homeDirectory)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        return url
    }

    public static func normalizedExistingDirectory(
        _ rawPath: String,
        fileManager: FileManager = .default
    ) throws -> String {
        let normalized = expandedPath(rawPath)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: normalized, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ProgramContextBridgeError.invalidDirectory(normalized)
        }
        return (normalized as NSString).standardizingPath
    }

    private static func expandedPath(_ rawPath: String) -> String {
        (rawPath as NSString).expandingTildeInPath
    }
}
