import XCTest
@testable import FzfPaletteCore

final class BenchmarkTests: XCTestCase {
    func testNativeFuzzySearchEngineMediumFixtureUnderKeystrokeHardMax() {
        let rows = (0..<10_000).map {
            PaletteRow(original: "src/module/file-\($0).swift", display: "src/module/file-\($0).swift")
        }
        let engine = NativeFuzzySearchEngine(rows: rows)
        let start = ContinuousClock.now

        let results = engine.search(query: "smf42")

        let elapsed = start.duration(to: ContinuousClock.now)
        let milliseconds = Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000

        XCTAssertFalse(results.isEmpty)
        XCTAssertLessThan(milliseconds, 50, "Native fuzzy engine smoke benchmark exceeded the 50 ms keystroke hard max")
    }
}
