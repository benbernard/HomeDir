import Darwin
import Foundation

public struct CommandRunResult: Codable, Equatable {
    public var stdout: String
    public var stderr: String
    public var exitCode: Int32
    public var durationMs: Double

    public var stdoutLines: [String] {
        stdout.split(whereSeparator: \.isNewline).map(String.init)
    }

    public init(stdout: String, stderr: String, exitCode: Int32, durationMs: Double) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.durationMs = durationMs
    }
}

public enum CommandRunError: Error, Equatable, CustomStringConvertible {
    case emptyCommand
    case cancelled(command: String)
    case timedOut(command: String, timeoutSeconds: TimeInterval)
    case nonZeroExit(command: String, exitCode: Int32, stderr: String)

    public var description: String {
        switch self {
        case .emptyCommand:
            return "Command cannot be empty"
        case let .cancelled(command):
            return "Command cancelled: \(command)"
        case let .timedOut(command, timeoutSeconds):
            return "Command timed out after \(timeoutSeconds)s: \(command)"
        case let .nonZeroExit(command, exitCode, stderr):
            return "Command failed with exit \(exitCode): \(command)\n\(stderr)"
        }
    }
}

public final class CommandCancellationToken {
    private let lock = NSLock()
    private var processIdentifier: Int32?
    public private(set) var isCancelled = false

    public init() {}

    public func cancel() {
        let pid: Int32? = lock.withLock {
            isCancelled = true
            return processIdentifier
        }

        if let pid {
            ProcessTree.terminate(rootPID: pid)
        }
    }

    fileprivate func attach(process: Process) {
        lock.withLock {
            processIdentifier = process.processIdentifier
            if isCancelled {
                ProcessTree.terminate(rootPID: process.processIdentifier)
            }
        }
    }

    fileprivate func detach(process: Process) {
        lock.withLock {
            if processIdentifier == process.processIdentifier {
                processIdentifier = nil
            }
        }
    }
}

public final class CommandRunner {
    public init() {}

    public func run(
        _ command: String,
        cwd: String = FileManager.default.currentDirectoryPath,
        environment: [String: String] = [:],
        timeoutSeconds: TimeInterval = 10,
        maxOutputBytes: Int = 1_000_000,
        cancellationToken: CommandCancellationToken? = nil
    ) throws -> CommandRunResult {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CommandRunError.emptyCommand
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", trimmed]
        process.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, override in override }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let lock = NSLock()
        var stdout = Data()
        var stderr = Data()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            lock.withLock {
                if stdout.count < maxOutputBytes {
                    stdout.append(chunk.prefix(maxOutputBytes - stdout.count))
                }
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            lock.withLock {
                if stderr.count < maxOutputBytes {
                    stderr.append(chunk.prefix(maxOutputBytes - stderr.count))
                }
            }
        }

        let start = ContinuousClock.now
        try process.run()
        cancellationToken?.attach(process: process)
        defer { cancellationToken?.detach(process: process) }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning && Date() < deadline {
            if cancellationToken?.isCancelled == true {
                ProcessTree.terminate(rootPID: process.processIdentifier)
                process.waitUntilExit()
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                throw CommandRunError.cancelled(command: trimmed)
            }
            Thread.sleep(forTimeInterval: 0.01)
        }

        if process.isRunning {
            ProcessTree.terminate(rootPID: process.processIdentifier)
            process.waitUntilExit()
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw CommandRunError.timedOut(command: trimmed, timeoutSeconds: timeoutSeconds)
        }

        process.waitUntilExit()
        Thread.sleep(forTimeInterval: 0.01)
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let duration = start.duration(to: ContinuousClock.now)
        let durationMs = Double(duration.components.seconds) * 1000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000

        let result = lock.withLock {
            CommandRunResult(
                stdout: String(data: stdout, encoding: .utf8) ?? "",
                stderr: String(data: stderr, encoding: .utf8) ?? "",
                exitCode: process.terminationStatus,
                durationMs: durationMs
            )
        }

        if cancellationToken?.isCancelled == true {
            throw CommandRunError.cancelled(command: trimmed)
        }

        if result.exitCode != 0 {
            throw CommandRunError.nonZeroExit(
                command: trimmed,
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        return result
    }
}

public final class SourceCommandRunner {
    private let runner: CommandRunner

    public init(runner: CommandRunner = CommandRunner()) {
        self.runner = runner
    }

    public func collectRows(
        command: String,
        cwd: String = FileManager.default.currentDirectoryPath,
        environment: [String: String] = [:],
        timeoutSeconds: TimeInterval = 10,
        cancellationToken: CommandCancellationToken? = nil
    ) throws -> [String] {
        try runner.run(
            command,
            cwd: cwd,
            environment: environment,
            timeoutSeconds: timeoutSeconds,
            cancellationToken: cancellationToken
        ).stdoutLines
    }

    public func streamRows(
        command: String,
        cwd: String = FileManager.default.currentDirectoryPath,
        environment: [String: String] = [:],
        timeoutSeconds: TimeInterval = 10,
        cancellationToken: CommandCancellationToken? = nil,
        onRows: @escaping ([String]) -> Void
    ) throws {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CommandRunError.emptyCommand
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", trimmed]
        process.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, override in override }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let lock = NSLock()
        var pending = ""
        var stderr = Data()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }

            let rowsToEmit: [String] = lock.withLock {
                pending += String(data: chunk, encoding: .utf8) ?? ""
                let endedWithNewline = pending.last?.isNewline == true
                var parts = pending.split(whereSeparator: \.isNewline).map(String.init)
                if endedWithNewline {
                    pending = ""
                } else {
                    pending = parts.popLast() ?? pending
                }
                return parts
            }

            if !rowsToEmit.isEmpty {
                onRows(rowsToEmit)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            lock.withLock {
                stderr.append(chunk)
            }
        }

        try process.run()
        cancellationToken?.attach(process: process)
        defer { cancellationToken?.detach(process: process) }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning && Date() < deadline {
            if cancellationToken?.isCancelled == true {
                ProcessTree.terminate(rootPID: process.processIdentifier)
                process.waitUntilExit()
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                throw CommandRunError.cancelled(command: trimmed)
            }
            Thread.sleep(forTimeInterval: 0.01)
        }

        if process.isRunning {
            ProcessTree.terminate(rootPID: process.processIdentifier)
            process.waitUntilExit()
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw CommandRunError.timedOut(command: trimmed, timeoutSeconds: timeoutSeconds)
        }

        process.waitUntilExit()
        Thread.sleep(forTimeInterval: 0.01)
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let trailing = lock.withLock { () -> String? in
            guard !pending.isEmpty else {
                return nil
            }
            let value = pending
            pending = ""
            return value
        }
        if let trailing {
            onRows([trailing])
        }

        if process.terminationStatus != 0 {
            if cancellationToken?.isCancelled == true {
                throw CommandRunError.cancelled(command: trimmed)
            }
            let stderrText = lock.withLock {
                String(data: stderr, encoding: .utf8) ?? ""
            }
            throw CommandRunError.nonZeroExit(
                command: trimmed,
                exitCode: process.terminationStatus,
                stderr: stderrText
            )
        }
    }
}

public final class PreviewCommandRunner {
    private let runner: CommandRunner

    public init(runner: CommandRunner = CommandRunner()) {
        self.runner = runner
    }

    public func renderPreview(
        template: String,
        row: String,
        cwd: String = FileManager.default.currentDirectoryPath,
        delimiter: String? = nil,
        query: String = "",
        lines: Int = 20,
        environment: [String: String] = [:],
        timeoutSeconds: TimeInterval = 3,
        cancellationToken: CommandCancellationToken? = nil
    ) throws -> String {
        let command = PlaceholderExpansion.expand(
            template: template,
            row: row,
            delimiter: delimiter,
            query: query,
            lines: lines
        )
        return try runner.run(
            command,
            cwd: cwd,
            environment: environment,
            timeoutSeconds: timeoutSeconds,
            maxOutputBytes: 200_000,
            cancellationToken: cancellationToken
        ).stdout
    }
}

enum ProcessTree {
    static func terminate(rootPID: Int32) {
        let pids = descendantPIDs(of: rootPID) + [rootPID]

        for pid in pids.reversed() {
            Darwin.kill(pid, SIGTERM)
        }

        let deadline = Date().addingTimeInterval(0.5)
        while Date() < deadline {
            if pids.allSatisfy({ !isAlive($0) }) {
                return
            }
            Thread.sleep(forTimeInterval: 0.02)
        }

        for pid in pids.reversed() where isAlive(pid) {
            Darwin.kill(pid, SIGKILL)
        }
    }

    private static func descendantPIDs(of rootPID: Int32) -> [Int32] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid="]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        var childrenByParent: [Int32: [Int32]] = [:]

        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count == 2,
                  let pid = Int32(parts[0]),
                  let parent = Int32(parts[1]) else {
                continue
            }
            childrenByParent[parent, default: []].append(pid)
        }

        var result: [Int32] = []
        var stack = childrenByParent[rootPID] ?? []
        while let pid = stack.popLast() {
            result.append(pid)
            stack.append(contentsOf: childrenByParent[pid] ?? [])
        }
        return result
    }

    private static func isAlive(_ pid: Int32) -> Bool {
        Darwin.kill(pid, 0) == 0 || errno == EPERM
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
