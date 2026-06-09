import Foundation

public struct MatchResult: Codable, Equatable {
    public var index: Int
    public var text: String
    public var score: Int

    public init(index: Int, text: String, score: Int) {
        self.index = index
        self.text = text
        self.score = score
    }
}

public enum SimpleMatcher {
    public static func match(query: String, rows: [String], caseInsensitive: Bool = true) -> [MatchResult] {
        NativeFuzzySearchEngine.matchStrings(
            query: query,
            rows: rows,
            caseInsensitive: caseInsensitive
        )
    }

    public static func match(query: String, rows: [String], options: FuzzySearchOptions) -> [MatchResult] {
        NativeFuzzySearchEngine.matchStrings(
            query: query,
            rows: rows,
            options: options
        )
    }
}
