import Foundation
import XCTest
@testable import FzfPaletteCore

final class FzfParityTests: XCTestCase {
    func testEmptyQueryPreservesInputOrderLikeFzfFilter() throws {
        let rows = [
            "src/app.swift",
            "src/core.swift",
            "docs/readme.md"
        ]

        let fzfRows = try runFzfFilter(rows: rows, query: "")
        let nativeRows = SimpleMatcher.match(query: "", rows: rows).map(\.text)

        XCTAssertEqual(nativeRows, fzfRows)
    }

    func testSimpleFuzzyFilterMatchesFzfForBasicFixture() throws {
        let rows = try fixtureRows("basic.txt")

        let fzfRows = try runFzfFilter(rows: rows, query: "palette")
        let nativeRows = SimpleMatcher.match(query: "palette", rows: rows).map(\.text)

        XCTAssertEqual(nativeRows, fzfRows)
    }

    func testSimpleFuzzyRankingMatchesFzfForOrderedFixture() throws {
        let rows = try fixtureRows("ordered.txt")

        let fzfRows = try runFzfFilter(rows: rows, query: "abc")
        let nativeRows = SimpleMatcher.match(query: "abc", rows: rows).map(\.text)

        XCTAssertEqual(nativeRows, fzfRows)
    }

    func testDelimiterWithNthKeepsOriginalFzfOutputAndNativeHiddenResultField() throws {
        let rows = try fixtureRows("tab-hidden.txt")

        let fzfRows = try runFzfFilter(
            rows: rows,
            query: "first",
            options: ["--delimiter=\t", "--with-nth=1"]
        )

        XCTAssertEqual(fzfRows, ["first\t/hidden/one"])
        XCTAssertEqual(
            RowFormatting.displayText(
                for: fzfRows[0],
                display: DisplayConfig(delimiter: "\t", withNth: "1")
            ),
            "first"
        )
        XCTAssertEqual(
            RowFormatting.selectedText(
                for: fzfRows[0],
                display: DisplayConfig(delimiter: "\t", withNth: "1"),
                result: ResultConfig(fields: "2", join: .newline)
            ),
            "/hidden/one"
        )
    }

    func testExtendedAndInverseTermsMatchFzfForLocalSubset() throws {
        let rows = try fixtureRows("extended.txt")

        let fzfRows = try runFzfFilter(rows: rows, query: "^music .mp3$ !fire 'alpha")
        let nativeRows = SimpleMatcher.match(query: "^music .mp3$ !fire 'alpha", rows: rows).map(\.text)

        XCTAssertEqual(nativeRows, fzfRows)
    }

    func testEscapedSpaceMatchesFzfForLocalSubset() throws {
        let rows = [
            "hello world.txt",
            "hello-world.txt",
            "world hello.txt"
        ]

        let fzfRows = try runFzfFilter(rows: rows, query: "hello\\ world", useDefaultOptions: false)
        let nativeRows = SimpleMatcher.match(
            query: "hello\\ world",
            rows: rows,
            options: FuzzySearchOptions(caseMode: .smart)
        ).map(\.text)

        XCTAssertEqual(nativeRows, fzfRows)
    }

    func testExactModeMatchesFzfForLocalSubset() throws {
        let rows = [
            "alpha",
            "a/l/p/h/a",
            "alpaca",
            "beta"
        ]

        let fzfRows = try runFzfFilter(
            rows: rows,
            query: "alp",
            options: ["--exact"],
            useDefaultOptions: false
        )
        let nativeRows = SimpleMatcher.match(
            query: "alp",
            rows: rows,
            options: FuzzySearchOptions(caseMode: .smart, exactMode: true)
        ).map(\.text)

        XCTAssertEqual(nativeRows, fzfRows)
    }

    func testExactModeQuoteUnquotesTermLikeFzfForLocalSubset() throws {
        let rows = [
            "alpha",
            "a/l/p/h/a",
            "alpaca",
            "beta"
        ]

        let fzfRows = try runFzfFilter(
            rows: rows,
            query: "'alp",
            options: ["--exact"],
            useDefaultOptions: false
        )
        let nativeRows = SimpleMatcher.match(
            query: "'alp",
            rows: rows,
            options: FuzzySearchOptions(caseMode: .smart, exactMode: true)
        ).map(\.text)

        XCTAssertEqual(nativeRows, fzfRows)
    }

    func testOrClauseMatchesFzfForLocalSubset() throws {
        let rows = try fixtureRows("or-clause.txt")

        let fzfRows = try runFzfFilter(rows: rows, query: "^core go$ | rb$")
        let nativeRows = SimpleMatcher.match(query: "^core go$ | rb$", rows: rows).map(\.text)

        XCTAssertEqual(nativeRows, fzfRows)
    }

    func testSmartCaseMatchesFzfDefaultForLocalSubset() throws {
        let rows = try fixtureRows("case.txt")

        let lowercaseFzfRows = try runFzfFilter(rows: rows, query: "rea", useDefaultOptions: false)
        let lowercaseNativeRows = SimpleMatcher.match(
            query: "rea",
            rows: rows,
            options: FuzzySearchOptions(caseMode: .smart)
        ).map(\.text)
        XCTAssertEqual(lowercaseNativeRows, lowercaseFzfRows)

        let uppercaseFzfRows = try runFzfFilter(rows: rows, query: "REA", useDefaultOptions: false)
        let uppercaseNativeRows = SimpleMatcher.match(
            query: "REA",
            rows: rows,
            options: FuzzySearchOptions(caseMode: .smart)
        ).map(\.text)
        XCTAssertEqual(uppercaseNativeRows, uppercaseFzfRows)
    }

    func testAnsiMatchingAndOutputMatchFzfForLocalSubset() throws {
        let rows = [
            "\u{001B}[31mred-target\u{001B}[0m",
            "blue-target"
        ]
        let display = DisplayConfig(ansi: true)

        let fzfRows = try runFzfFilter(
            rows: rows,
            query: "red",
            options: ["--ansi"],
            useDefaultOptions: false
        )
        let engine = NativeFuzzySearchEngine(
            rows: RowFormatting.rows(from: rows, display: display),
            options: FuzzySearchOptions(caseMode: .smart)
        )
        let nativeRows = engine.search(query: "red").map {
            RowFormatting.selectedText(for: $0.row.original, display: display, result: ResultConfig())
        }

        XCTAssertEqual(nativeRows, fzfRows)
    }

    func testNthSearchScopeMatchesFzfForLocalSubset() throws {
        let rows = [
            "src/App.swift:10:1:alpha match",
            "docs/App.md:20:1:alpha match",
            "src/Other.swift:30:1:beta match"
        ]
        let display = DisplayConfig(delimiter: ":", nth: "1")

        let fzfRows = try runFzfFilter(
            rows: rows,
            query: "src",
            options: ["--delimiter=:", "--nth=1"],
            useDefaultOptions: false
        )
        let engine = NativeFuzzySearchEngine(
            rows: RowFormatting.rows(from: rows, display: display),
            options: FuzzySearchOptions(caseMode: .smart)
        )
        let nativeRows = engine.search(query: "src").map(\.row.original)

        XCTAssertEqual(nativeRows, fzfRows)
        XCTAssertEqual(
            NativeFuzzySearchEngine(rows: RowFormatting.rows(from: rows, display: display))
                .search(query: "alpha")
                .map(\.row.original),
            []
        )
    }

    func testNthNegativeFieldMatchesFzfForLocalSubset() throws {
        let rows = [
            "src/App.swift:10:1:alpha match",
            "docs/App.md:20:1:alpha match",
            "src/Other.swift:30:1:beta match"
        ]
        let display = DisplayConfig(delimiter: ":", nth: "-1")

        let fzfRows = try runFzfFilter(
            rows: rows,
            query: "beta",
            options: ["--delimiter=:", "--nth=-1"],
            useDefaultOptions: false
        )
        let engine = NativeFuzzySearchEngine(
            rows: RowFormatting.rows(from: rows, display: display),
            options: FuzzySearchOptions(caseMode: .smart)
        )
        let nativeRows = engine.search(query: "beta").map(\.row.original)

        XCTAssertEqual(nativeRows, fzfRows)
    }

    func testTiebreakIndexMatchesFzfForLocalSubset() throws {
        let rows = try fixtureRows("tiebreak-index.txt")

        let fzfRows = try runFzfFilter(
            rows: rows,
            query: "abc",
            options: ["--tiebreak=index"],
            useDefaultOptions: false
        )
        let nativeRows = SimpleMatcher.match(
            query: "abc",
            rows: rows,
            options: FuzzySearchOptions(tiebreak: .index)
        ).map(\.text)

        XCTAssertEqual(nativeRows, fzfRows)
    }

    func testTiebreakBeginMatchesFzfForLocalSubset() throws {
        let rows = [
            "xxabc",
            "abcxx",
            "xabcx",
            "abc"
        ]

        let fzfRows = try runFzfFilter(
            rows: rows,
            query: "abc",
            options: ["--tiebreak=begin"],
            useDefaultOptions: false
        )
        let nativeRows = SimpleMatcher.match(
            query: "abc",
            rows: rows,
            options: FuzzySearchOptions(tiebreak: .begin)
        ).map(\.text)

        XCTAssertEqual(nativeRows, fzfRows)
    }

    func testTiebreakEndMatchesFzfForLocalSubset() throws {
        let rows = [
            "abcde",
            "abcd",
            "abc",
            "abcxyz"
        ]

        let fzfRows = try runFzfFilter(
            rows: rows,
            query: "abc",
            options: ["--tiebreak=end"],
            useDefaultOptions: false
        )
        let nativeRows = SimpleMatcher.match(
            query: "abc",
            rows: rows,
            options: FuzzySearchOptions(tiebreak: .end)
        ).map(\.text)

        XCTAssertEqual(nativeRows, fzfRows)
    }

    func testOrderedTiebreakListMatchesFzfForLocalSubset() throws {
        let rows = [
            "xxabc",
            "abcxx",
            "xabcx",
            "abc"
        ]

        let fzfRows = try runFzfFilter(
            rows: rows,
            query: "abc",
            options: ["--tiebreak=begin,end"],
            useDefaultOptions: false
        )
        let nativeRows = SimpleMatcher.match(
            query: "abc",
            rows: rows,
            options: FuzzySearchOptions(tiebreaks: [.begin, .end])
        ).map(\.text)

        XCTAssertEqual(nativeRows, fzfRows)
    }

    func testTiebreakChunkMatchesFzfForLocalSubset() throws {
        let rows = [
            "1 foobarbaz ba",
            "2 foobar baz",
            "3 foo barbaz"
        ]

        let fzfRows = try runFzfFilter(
            rows: rows,
            query: "o",
            options: ["--tiebreak=chunk"],
            useDefaultOptions: false
        )
        let nativeRows = SimpleMatcher.match(
            query: "o",
            rows: rows,
            options: FuzzySearchOptions(tiebreak: .chunk)
        ).map(\.text)

        XCTAssertEqual(nativeRows, fzfRows)
    }

    func testNoSortMatchesFzfForLocalSubset() throws {
        let rows = try fixtureRows("tiebreak-index.txt")

        let fzfRows = try runFzfFilter(
            rows: rows,
            query: "abc",
            options: ["+s"],
            useDefaultOptions: false
        )
        let nativeRows = SimpleMatcher.match(
            query: "abc",
            rows: rows,
            options: FuzzySearchOptions(sort: false)
        ).map(\.text)

        XCTAssertEqual(nativeRows, fzfRows)
    }

    func testPathSchemeMatchesFzfForLocalPathSubset() throws {
        let rows = [
            "foo/bar/baz/qux.txt",
            "foo-baz-qux.txt",
            "bar/foo/qux-baz.txt",
            "qux/foo/bar/baz.txt",
            "qux.txt"
        ]

        let fzfRows = try runFzfFilter(
            rows: rows,
            query: "qux",
            options: ["--scheme=path"],
            useDefaultOptions: false
        )
        let nativeRows = SimpleMatcher.match(
            query: "qux",
            rows: rows,
            options: FuzzySearchOptions(scheme: .path)
        ).map(\.text)

        XCTAssertEqual(nativeRows, fzfRows)
    }

    func testHistorySchemeMatchesFzfScoreOnlyTiesForLocalSubset() throws {
        let rows = [
            "abcxxxx",
            "abc",
            "xabcx",
            "xxabc"
        ]

        let fzfRows = try runFzfFilter(
            rows: rows,
            query: "abc",
            options: ["--scheme=history", "--tiebreak=length"],
            useDefaultOptions: false
        )
        let nativeRows = SimpleMatcher.match(
            query: "abc",
            rows: rows,
            options: FuzzySearchOptions(tiebreaks: [], scheme: .history)
        ).map(\.text)

        XCTAssertEqual(nativeRows, fzfRows)
    }

    private func fixtureRows(_ name: String) throws -> [String] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/engine-parity")
            .appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
    }

    private func runFzfFilter(
        rows: [String],
        query: String,
        options: [String] = [],
        useDefaultOptions: Bool = true
    ) throws -> [String] {
        let fzf = try fzfPath()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: fzf)
        process.arguments = ["--filter", query] + options
        if !useDefaultOptions {
            var environment = ProcessInfo.processInfo.environment
            environment.removeValue(forKey: "FZF_DEFAULT_OPTS")
            environment.removeValue(forKey: "FZF_DEFAULT_OPTS_FILE")
            process.environment = environment
        }

        let stdout = Pipe()
        let stdin = Pipe()
        process.standardOutput = stdout
        process.standardInput = stdin
        process.standardError = Pipe()

        try process.run()
        stdin.fileHandleForWriting.write(Data((rows.joined(separator: "\n") + "\n").utf8))
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()

        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            XCTFail("fzf exited with \(process.terminationStatus)")
            return []
        }

        return String(data: output, encoding: .utf8)?
            .split(whereSeparator: \.isNewline)
            .map(String.init) ?? []
    }

    private func fzfPath() throws -> String {
        let candidates = [
            ProcessInfo.processInfo.environment["FZF_PALETTE_TEST_FZF"],
            "/Users/benbernard/submodules/fzf/bin/fzf",
            "/opt/homebrew/bin/fzf",
            "/usr/local/bin/fzf"
        ].compactMap { $0 }

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }

        throw XCTSkip("fzf binary not available")
    }
}
