import Foundation

public struct FrontmostApplicationInfo: Equatable {
    public var name: String?
    public var bundleIdentifier: String?
    public var processIdentifier: Int32?

    public init(name: String?, bundleIdentifier: String?, processIdentifier: Int32? = nil) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
    }
}

public final class ProgramContextResolver {
    private let environment: [String: String]
    private let homeDirectory: URL
    private let fileManager: FileManager
    private let timeoutMs: Int
    private let startedAt = DispatchTime.now()

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
        let requestedTimeoutMs = Int(environment["FZF_PALETTE_PROGRAM_CONTEXT_TIMEOUT_MS"] ?? "") ?? 40
        self.timeoutMs = min(max(10, requestedTimeoutMs), 50)
    }

    public func resolve(frontmostApplication: FrontmostApplicationInfo?) -> ProgramContext? {
        guard environment["FZF_PALETTE_DISABLE_PROGRAM_CONTEXT"] != "1",
              let frontmostApplication,
              let app = ProgramContextApp.classify(
                  bundleIdentifier: frontmostApplication.bundleIdentifier,
                  appName: frontmostApplication.name
              ) else {
            return nil
        }

        switch app {
        case .codex, .claude:
            return resolveBridgeContext(app: app, frontmostApplication: frontmostApplication)
        case .ghostty:
            return resolveGhosttyContext(frontmostApplication: frontmostApplication)
        }
    }

    private func resolveBridgeContext(
        app: ProgramContextApp,
        frontmostApplication: FrontmostApplicationInfo
    ) -> ProgramContext? {
        do {
            return try ProgramContextBridge.loadContext(
                for: app,
                environment: environment,
                homeDirectory: homeDirectory,
                fileManager: fileManager,
                appName: frontmostApplication.name,
                bundleIdentifier: frontmostApplication.bundleIdentifier
            )
        } catch {
            return nil
        }
    }

    private func resolveGhosttyContext(frontmostApplication: FrontmostApplicationInfo) -> ProgramContext? {
        if let testCwd = environment["FZF_PALETTE_TEST_GHOSTTY_TMUX_CWD"],
           let context = contextForDirectory(
               testCwd,
               provider: "ghostty-tmux",
               app: .ghostty,
               frontmostApplication: frontmostApplication,
               detail: "test override"
           ) {
            return context
        }

        if let bridge = resolveBridgeContext(app: .ghostty, frontmostApplication: frontmostApplication) {
            return bridge
        }

        guard let paneID = explicitTmuxPaneID() ?? activeDefaultTmuxPaneID(),
              let panePath = resolveTmuxPanePath(paneID),
              let context = contextForDirectory(
                  panePath,
                  provider: "ghostty-tmux",
                  app: .ghostty,
                  frontmostApplication: frontmostApplication,
                  detail: paneID
              ) else {
            return nil
        }

        return context
    }

    private func contextForDirectory(
        _ path: String,
        provider: String,
        app: ProgramContextApp,
        frontmostApplication: FrontmostApplicationInfo,
        detail: String?
    ) -> ProgramContext? {
        guard let cwd = try? ProgramContextBridge.normalizedExistingDirectory(path, fileManager: fileManager) else {
            return nil
        }

        return ProgramContext(
            cwd: cwd,
            provider: provider,
            appName: frontmostApplication.name ?? app.displayName,
            bundleIdentifier: frontmostApplication.bundleIdentifier ?? app.defaultBundleIdentifier,
            detail: detail
        )
    }

    private func explicitTmuxPaneID() -> String? {
        guard let paneID = environment["FZF_PALETTE_GHOSTTY_TMUX_PANE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !paneID.isEmpty else {
            return nil
        }
        return paneID
    }

    private func activeDefaultTmuxPaneID() -> String? {
        if let session = mostRecentDefaultTmuxClientSession() {
            return tmuxOutput(["-L", "default", "display-message", "-t", session, "-p", "#{pane_id}"])
        }

        return tmuxOutput(["-L", "default", "display-message", "-p", "#{pane_id}"])
    }

    private func mostRecentDefaultTmuxClientSession() -> String? {
        let output = tmuxOutput(["-L", "default", "list-clients", "-F", "#{client_activity}\t#{client_session}"])

        return output?
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> (activity: Int, session: String)? in
                let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
                guard parts.count == 2,
                      let activity = Int(parts[0]),
                      !parts[1].isEmpty else {
                    return nil
                }
                return (activity, parts[1])
            }
            .max { $0.activity < $1.activity }?
            .session
    }

    private func resolveTmuxPanePath(_ paneID: String) -> String? {
        if let resolverPath = environment["FZF_PALETTE_TMUX_RESOLVE_PANE_PATH"],
           !resolverPath.isEmpty,
           let resolved = shellOutput(executable: resolverPath, arguments: [paneID]) {
            return resolved
        }

        let defaultResolver = homeDirectory
            .appendingPathComponent("bin/tmux-resolve-pane-path")
            .path
        if fileManager.isExecutableFile(atPath: defaultResolver),
           let resolved = shellOutput(executable: defaultResolver, arguments: [paneID]) {
            return resolved
        }

        return tmuxOutput(["-L", "default", "display-message", "-t", paneID, "-p", "#{pane_current_path}"])
    }

    private func tmuxOutput(_ arguments: [String]) -> String? {
        for executable in [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux"
        ] {
            if let output = shellOutput(executable: executable, arguments: arguments) {
                return output
            }
        }
        return shellOutput(executable: "/usr/bin/env", arguments: ["tmux"] + arguments)
    }

    private func shellOutput(executable: String, arguments: [String]) -> String? {
        guard fileManager.isExecutableFile(atPath: executable) else {
            return nil
        }
        guard let remainingMs = remainingTimeoutMilliseconds() else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            finished.signal()
        }

        do {
            try process.run()
        } catch {
            return nil
        }

        if finished.wait(timeout: .now() + .milliseconds(remainingMs)) == .timedOut {
            process.terminate()
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }

    private func remainingTimeoutMilliseconds() -> Int? {
        let elapsedNs = DispatchTime.now().uptimeNanoseconds - startedAt.uptimeNanoseconds
        let elapsedMs = Int(elapsedNs / 1_000_000)
        let remainingMs = timeoutMs - elapsedMs
        return remainingMs > 0 ? remainingMs : nil
    }
}
