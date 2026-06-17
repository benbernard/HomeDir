import Darwin
import XCTest
@testable import FzfPaletteCore

final class IntegrationTests: XCTestCase {
    func testEnvironmentSnapshotParsesNullSeparatedOutput() {
        let data = Data("PATH=/bin\u{0}FZF_DEFAULT_COMMAND=rg --files\u{0}".utf8)

        let snapshot = EnvironmentSnapshot.parseNullSeparatedEnv(data)

        XCTAssertEqual(snapshot.values["PATH"], "/bin")
        XCTAssertEqual(snapshot.values["FZF_DEFAULT_COMMAND"], "rg --files")
    }

    func testOpenRequestCanRepresentSourceCommandAndPreview() throws {
        let request = PaletteClientRequest(
            type: .open,
            id: "open-1",
            request: PickerRequest(
                id: "open-1",
                profile: "custom",
                cwd: "/tmp",
                source: .command("git status -s"),
                fzfOptions: ["--ansi", "--delimiter", " "],
                preview: PreviewConfig(command: "~/bin/status-preview.sh {}"),
                resultMode: .return
            )
        )

        let response = PaletteResponse(type: .error, id: "open-1", code: "open_not_implemented", message: "pending")

        XCTAssertEqual(try WireCoding.decodeRequest(WireCoding.encodeLine(request)), request)
        XCTAssertEqual(try WireCoding.decodeResponse(WireCoding.encodeLine(response)), response)
    }

    func testSocketPathMatchesDocumentedLocation() {
        let path = FzfPalettePaths.socketURL.path

        XCTAssertTrue(path.hasSuffix("Library/Application Support/FzfPalette/fzf-palette.sock"))
    }

    func testSourceCommandRunnerCollectsRowsWithoutPTY() throws {
        let runner = SourceCommandRunner()

        let rows = try runner.collectRows(
            command: "printf 'alpha\\nbeta\\n'",
            timeoutSeconds: 2
        )

        XCTAssertEqual(rows, ["alpha", "beta"])
    }

    func testSourceCommandRunnerStreamsRowsBeforeCommandExit() throws {
        let runner = SourceCommandRunner()
        var observed: [(String, TimeInterval)] = []
        let start = Date()

        try runner.streamRows(
            command: "printf 'first\\n'; sleep 0.8; printf 'second\\n'",
            timeoutSeconds: 2
        ) { rows in
            for row in rows {
                observed.append((row, Date().timeIntervalSince(start)))
            }
        }

        XCTAssertEqual(observed.map(\.0), ["first", "second"])
        XCTAssertLessThan(observed[0].1, 0.6, "first streamed row arrived only after the delayed command was nearly complete")
    }

    func testPreviewCommandRunnerExpandsFieldPlaceholders() throws {
        let runner = PreviewCommandRunner()

        let preview = try runner.renderPreview(
            template: "printf '%s:%s\\n' {1} {2}",
            row: "file.swift:42:body",
            delimiter: ":",
            timeoutSeconds: 2
        )

        XCTAssertEqual(preview, "file.swift:42\n")
    }

    func testCommandRunnerTimesOut() {
        let runner = CommandRunner()

        XCTAssertThrowsError(try runner.run("sleep 2", timeoutSeconds: 0.05)) { error in
            guard case CommandRunError.timedOut = error else {
                return XCTFail("Expected timeout, got \(error)")
            }
        }
    }

    func testSourceCommandCancellationKillsChildProcessTree() throws {
        let runner = SourceCommandRunner()
        let token = CommandCancellationToken()
        let childPIDLock = NSLock()
        var childPID: Int32?
        let sawChild = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        var thrownError: Error?

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try runner.streamRows(
                    command: "sleep 30 & child=$!; echo $child; wait $child",
                    timeoutSeconds: 10,
                    cancellationToken: token
                ) { rows in
                    if let first = rows.first, let pid = Int32(first) {
                        childPIDLock.lock()
                        childPID = pid
                        childPIDLock.unlock()
                        sawChild.signal()
                    }
                }
            } catch {
                thrownError = error
            }
            finished.signal()
        }

        XCTAssertEqual(sawChild.wait(timeout: .now() + 2), .success)
        token.cancel()
        XCTAssertEqual(finished.wait(timeout: .now() + 3), .success)

        guard let thrownError, case CommandRunError.cancelled = thrownError else {
            return XCTFail("Expected cancellation error, got \(String(describing: thrownError))")
        }

        childPIDLock.lock()
        let pid = childPID
        childPIDLock.unlock()

        if let pid {
            XCTAssertFalse(processIsAlive(pid), "child process \(pid) survived cancellation")
        }
    }

    private func processIsAlive(_ pid: Int32) -> Bool {
        Darwin.kill(pid, 0) == 0 || errno == EPERM
    }
}
