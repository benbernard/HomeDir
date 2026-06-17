import Foundation

public enum FzfPalettePaths {
    public static let appName = "FzfPalette"
    public static let socketFileName = "fzf-palette.sock"

    public static var applicationSupportDirectory: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(appName, isDirectory: true)
    }

    public static var socketURL: URL {
        applicationSupportDirectory.appendingPathComponent(socketFileName)
    }

    public static var profilesURL: URL {
        applicationSupportDirectory.appendingPathComponent("profiles.json")
    }

    public static var logDirectory: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
            .appendingPathComponent(appName, isDirectory: true)
    }

    public static var defaultInstallURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("FzfPalette.app", isDirectory: true)
    }

    public static func ensureRuntimeDirectories() throws {
        try FileManager.default.createDirectory(
            at: applicationSupportDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: logDirectory,
            withIntermediateDirectories: true
        )
    }
}
