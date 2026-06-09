import Foundation

public enum FuzzyCaseMode: String, Codable, Equatable {
    case smart
    case caseInsensitive
    case caseSensitive
}

public enum FuzzyTiebreak: String, Codable, Equatable {
    case length
    case chunk
    case index
    case begin
    case end
}

public enum FuzzyScheme: String, Codable, Equatable {
    case `default`
    case path
    case history
}

public struct FuzzySearchOptions: Codable, Equatable {
    public var caseMode: FuzzyCaseMode
    public var tiebreaks: [FuzzyTiebreak]
    public var exactMode: Bool
    public var sort: Bool
    public var scheme: FuzzyScheme

    public init(
        caseMode: FuzzyCaseMode = .smart,
        tiebreak: FuzzyTiebreak = .length,
        tiebreaks: [FuzzyTiebreak]? = nil,
        exactMode: Bool = false,
        sort: Bool = true,
        scheme: FuzzyScheme = .default
    ) {
        self.caseMode = caseMode
        self.tiebreaks = tiebreaks ?? [tiebreak]
        self.exactMode = exactMode
        self.sort = sort
        self.scheme = scheme
    }

    public init(
        caseInsensitive: Bool,
        tiebreak: FuzzyTiebreak = .length,
        tiebreaks: [FuzzyTiebreak]? = nil,
        exactMode: Bool = false,
        sort: Bool = true,
        scheme: FuzzyScheme = .default
    ) {
        caseMode = caseInsensitive ? .caseInsensitive : .caseSensitive
        self.tiebreaks = tiebreaks ?? [tiebreak]
        self.exactMode = exactMode
        self.sort = sort
        self.scheme = scheme
    }

    public var caseInsensitive: Bool {
        get {
            caseMode == .caseInsensitive
        }
        set {
            caseMode = newValue ? .caseInsensitive : .caseSensitive
        }
    }

    public func resolved(for query: String) -> FuzzySearchOptions {
        guard caseMode == .smart else {
            return self
        }
        let containsUppercase = query.unicodeScalars.contains {
            CharacterSet.uppercaseLetters.contains($0)
        }
        return FuzzySearchOptions(
            caseMode: containsUppercase ? .caseSensitive : .caseInsensitive,
            tiebreaks: tiebreaks,
            exactMode: exactMode,
            sort: sort,
            scheme: scheme
        )
    }
}

public struct FuzzySearchMatch: Codable, Equatable {
    public var index: Int
    public var row: PaletteRow
    public var score: Int
    public var ranges: [FuzzyMatchRange]

    public init(index: Int, row: PaletteRow, score: Int, ranges: [FuzzyMatchRange] = []) {
        self.index = index
        self.row = row
        self.score = score
        self.ranges = ranges
    }
}

public struct FuzzyMatchRange: Codable, Equatable {
    public var start: Int
    public var length: Int

    public init(start: Int, length: Int) {
        self.start = start
        self.length = length
    }
}

public final class NativeFuzzySearchEngine {
    private var rows: [PaletteRow] = []
    private var caseSensitiveRows: [[UInt8]] = []
    private var caseSensitiveTextRows: [String] = []
    private var caseInsensitiveRows: [[UInt8]] = []
    private var caseInsensitiveTextRows: [String] = []
    private var displayLengths: [Int] = []
    private var selection = SelectionModel()
    private let options: FuzzySearchOptions

    public init(rows: [PaletteRow] = [], options: FuzzySearchOptions = FuzzySearchOptions()) {
        self.options = options
        replaceRows(rows)
    }

    public var allRows: [PaletteRow] {
        rows
    }

    public func replaceRows(_ rows: [PaletteRow]) {
        self.rows = rows
        caseSensitiveRows = rows.map { normalizedSearchBytes($0.search, options: .caseSensitiveOptions) }
        caseSensitiveTextRows = rows.map { normalizedSearchText($0.search, options: .caseSensitiveOptions) }
        caseInsensitiveRows = rows.map { normalizedSearchBytes($0.search, options: .caseInsensitiveOptions) }
        caseInsensitiveTextRows = rows.map { normalizedSearchText($0.search, options: .caseInsensitiveOptions) }
        displayLengths = rows.map { $0.display.utf8.count }
        selection.deselectAll()
    }

    public func appendRows(_ rows: [PaletteRow]) {
        self.rows.append(contentsOf: rows)
        caseSensitiveRows.append(contentsOf: rows.map { normalizedSearchBytes($0.search, options: .caseSensitiveOptions) })
        caseSensitiveTextRows.append(contentsOf: rows.map { normalizedSearchText($0.search, options: .caseSensitiveOptions) })
        caseInsensitiveRows.append(contentsOf: rows.map { normalizedSearchBytes($0.search, options: .caseInsensitiveOptions) })
        caseInsensitiveTextRows.append(contentsOf: rows.map { normalizedSearchText($0.search, options: .caseInsensitiveOptions) })
        displayLengths.append(contentsOf: rows.map { $0.display.utf8.count })
    }

    public var selectedCount: Int {
        selection.count
    }

    public var hasSelection: Bool {
        !selection.isEmpty
    }

    public func isSelected(sourceIndex: Int) -> Bool {
        selection.contains(sourceIndex)
    }

    public func toggleSelection(sourceIndex: Int) {
        selection.toggle(sourceIndex)
    }

    public func selectAll(rows visibleRows: [PaletteRow]) {
        selection.selectAll(visibleRows.map(\.sourceIndex))
    }

    public func deselectAll() {
        selection.deselectAll()
    }

    public func selectedRows() -> [PaletteRow] {
        selection.orderedSelection(from: rows)
    }

    public func acceptedRows(fallback fallbackRow: PaletteRow) -> [PaletteRow] {
        let selected = selectedRows()
        return selected.isEmpty ? [fallbackRow] : selected
    }

    public func searchRows(query: String) -> [PaletteRow] {
        searchRows(query: query, includeRanges: false)
    }

    public func searchRows(query: String, includeRanges: Bool) -> [PaletteRow] {
        let parsed = parsedSearch(query: query)
        guard !parsed.query.isEmpty else {
            return rows
        }

        if !includeRanges, canUseScoreOnlyRows(parsed: parsed) {
            return searchRowIndexes(parsed: parsed).map { rows[$0] }
        }

        return searchCandidates(parsed: parsed, includeRanges: includeRanges).map { candidate in
            rows[candidate.index]
        }
    }

    public func search(query: String, includeRanges: Bool = true) -> [FuzzySearchMatch] {
        let parsed = parsedSearch(query: query)
        guard !parsed.query.isEmpty else {
            return rows.enumerated().map { index, row in
                FuzzySearchMatch(index: index, row: row, score: 0)
            }
        }

        return searchCandidates(parsed: parsed, includeRanges: includeRanges).map { candidate in
            FuzzySearchMatch(
                index: candidate.index,
                row: rows[candidate.index],
                score: candidate.score,
                ranges: candidate.ranges
            )
        }
    }

    private func parsedSearch(query: String) -> ParsedFuzzySearch {
        let resolvedOptions = options.resolved(for: query)
        let parsedQuery = FuzzyQuery.parse(query, options: resolvedOptions)
        return ParsedFuzzySearch(query: parsedQuery, options: resolvedOptions)
    }

    private func canUseScoreOnlyRows(parsed: ParsedFuzzySearch) -> Bool {
        parsed.options.scheme != .path
            && !parsed.options.tiebreaks.contains { $0 == .begin || $0 == .end || $0 == .chunk }
    }

    private func searchRowIndexes(parsed: ParsedFuzzySearch) -> [Int] {
        let searchRows = normalizedRows(for: parsed.options)
        let searchTexts = normalizedTextRows(for: parsed.options)
        var candidates: [ScoredFuzzyIndex] = []
        candidates.reserveCapacity(searchRows.count)

        if let simpleFuzzyBytes = parsed.query.simpleFuzzyBytes {
            for index in searchRows.indices {
                guard let score = FuzzyScorer.scoreOnly(query: simpleFuzzyBytes, row: searchRows[index]) else {
                    continue
                }
                candidates.append(ScoredFuzzyIndex(index: index, score: score))
            }
        } else {
            for index in searchRows.indices {
                guard let score = parsed.query.matchScore(rowBytes: searchRows[index], rowText: searchTexts[index]) else {
                    continue
                }
                candidates.append(ScoredFuzzyIndex(index: index, score: score))
            }
        }

        if parsed.options.sort {
            candidates.sort { left, right in
                if left.score == right.score {
                    return tieSort(left, right, options: parsed.options)
                }
                return left.score > right.score
            }
        }

        return candidates.map(\.index)
    }

    private func searchCandidates(parsed: ParsedFuzzySearch, includeRanges: Bool) -> [FuzzySearchCandidate] {
        let searchRows = normalizedRows(for: parsed.options)
        let searchTexts = normalizedTextRows(for: parsed.options)
        let needsTieMetrics = parsed.options.sort
            && parsed.options.tiebreaks.contains { $0 == .begin || $0 == .end || $0 == .chunk }
        let needsRanges = includeRanges || needsTieMetrics || parsed.options.scheme == .path

        var candidates: [FuzzySearchCandidate] = []
        candidates.reserveCapacity(searchRows.count)

        if !needsRanges, let simpleFuzzyBytes = parsed.query.simpleFuzzyBytes {
            for index in searchRows.indices {
                guard let score = FuzzyScorer.scoreOnly(query: simpleFuzzyBytes, row: searchRows[index]) else {
                    continue
                }
                candidates.append(FuzzySearchCandidate(index: index, score: score, ranges: [], tieMetrics: nil))
            }
        } else {
            for index in searchRows.indices {
                let rowBytes = searchRows[index]
                let score: Int
                let ranges: [FuzzyMatchRange]
                let tieRanges: [FuzzyMatchRange]
                if needsRanges {
                    guard let result = parsed.query.match(rowBytes: rowBytes, rowText: searchTexts[index]) else {
                        continue
                    }
                    score = result.score + pathSchemeBonus(
                        rowText: searchTexts[index],
                        ranges: result.ranges,
                        options: parsed.options
                    )
                    ranges = includeRanges ? result.ranges : []
                    tieRanges = result.ranges
                } else {
                    guard let result = parsed.query.matchScore(rowBytes: rowBytes, rowText: searchTexts[index]) else {
                        continue
                    }
                    score = result
                    ranges = []
                    tieRanges = []
                }
                candidates.append(
                    FuzzySearchCandidate(
                        index: index,
                        score: score,
                        ranges: ranges,
                        tieMetrics: needsTieMetrics
                            ? FuzzyTieMetrics(rowText: searchTexts[index], ranges: tieRanges)
                            : nil
                    )
                )
            }
        }

        if parsed.options.sort {
            candidates.sort { left, right in
                if left.score == right.score {
                    return tieSort(left, right, options: parsed.options)
                }
                return left.score > right.score
            }
        }

        return candidates
    }

    public func matchRanges(query: String, sourceIndex: Int) -> [FuzzyMatchRange] {
        guard sourceIndex >= 0, sourceIndex < rows.count else {
            return []
        }

        let resolvedOptions = options.resolved(for: query)
        let parsedQuery = FuzzyQuery.parse(query, options: resolvedOptions)
        guard !parsedQuery.isEmpty else {
            return []
        }

        let searchRows = normalizedRows(for: resolvedOptions)
        let searchTexts = normalizedTextRows(for: resolvedOptions)
        return parsedQuery.match(
            rowBytes: searchRows[sourceIndex],
            rowText: searchTexts[sourceIndex]
        )?.ranges ?? []
    }

    public static func matchStrings(
        query: String,
        rows: [String],
        caseInsensitive: Bool = true
    ) -> [MatchResult] {
        let engine = NativeFuzzySearchEngine(
            rows: rows.map { PaletteRow(original: $0, display: $0) },
            options: FuzzySearchOptions(caseInsensitive: caseInsensitive)
        )
        return engine.search(query: query).map {
            MatchResult(index: $0.index, text: $0.row.original, score: $0.score)
        }
    }

    public static func matchStrings(
        query: String,
        rows: [String],
        options: FuzzySearchOptions
    ) -> [MatchResult] {
        let engine = NativeFuzzySearchEngine(
            rows: rows.map { PaletteRow(original: $0, display: $0) },
            options: options
        )
        return engine.search(query: query).map {
            MatchResult(index: $0.index, text: $0.row.original, score: $0.score)
        }
    }

    private func normalizedRows(for options: FuzzySearchOptions) -> [[UInt8]] {
        options.caseMode == .caseInsensitive ? caseInsensitiveRows : caseSensitiveRows
    }

    private func normalizedTextRows(for options: FuzzySearchOptions) -> [String] {
        options.caseMode == .caseInsensitive ? caseInsensitiveTextRows : caseSensitiveTextRows
    }

    private func tieSort(
        _ left: FuzzySearchCandidate,
        _ right: FuzzySearchCandidate,
        options: FuzzySearchOptions
    ) -> Bool {
        for criterion in options.tiebreaks {
            switch criterion {
            case .index:
                if left.index != right.index {
                    return left.index < right.index
                }
            case .length:
                let leftLength = displayLengths[left.index]
                let rightLength = displayLengths[right.index]
                if leftLength != rightLength {
                    return leftLength < rightLength
                }
            case .chunk:
                let leftChunk = left.tieMetrics?.chunk ?? Int.max
                let rightChunk = right.tieMetrics?.chunk ?? Int.max
                if leftChunk != rightChunk {
                    return leftChunk < rightChunk
                }
            case .begin:
                let leftBegin = left.tieMetrics?.begin ?? Int.max
                let rightBegin = right.tieMetrics?.begin ?? Int.max
                if leftBegin != rightBegin {
                    return leftBegin < rightBegin
                }
            case .end:
                let leftEnd = left.tieMetrics?.end ?? Int.max
                let rightEnd = right.tieMetrics?.end ?? Int.max
                if leftEnd != rightEnd {
                    return leftEnd < rightEnd
                }
            }
        }
        return left.index < right.index
    }

    private func tieSort(
        _ left: ScoredFuzzyIndex,
        _ right: ScoredFuzzyIndex,
        options: FuzzySearchOptions
    ) -> Bool {
        for criterion in options.tiebreaks {
            switch criterion {
            case .index:
                if left.index != right.index {
                    return left.index < right.index
                }
            case .length:
                let leftLength = displayLengths[left.index]
                let rightLength = displayLengths[right.index]
                if leftLength != rightLength {
                    return leftLength < rightLength
                }
            case .chunk, .begin, .end:
                continue
            }
        }
        return left.index < right.index
    }

    private func pathSchemeBonus(
        rowText: String,
        ranges: [FuzzyMatchRange],
        options: FuzzySearchOptions
    ) -> Int {
        guard options.scheme == .path, let firstRange = ranges.min(by: { $0.start < $1.start }) else {
            return 0
        }

        let basenameStart = lastPathSeparatorOffset(in: rowText).map { $0 + 1 } ?? 0
        let basenameLength = max(0, rowText.utf8.count - basenameStart)
        let firstStart = firstRange.start
        let matchedLength = ranges.reduce(0) { $0 + $1.length }

        if firstStart == basenameStart {
            return 100 + basenameClosenessBonus(basenameLength: basenameLength, matchedLength: matchedLength)
        }

        if firstStart > basenameStart {
            return 10
        }

        if firstStart == 0 {
            return 15
        }

        return 0
    }

    private func basenameClosenessBonus(basenameLength: Int, matchedLength: Int) -> Int {
        max(0, 30 - max(0, basenameLength - matchedLength))
    }

    private func lastPathSeparatorOffset(in rowText: String) -> Int? {
        guard let slash = rowText.utf8.lastIndex(of: UInt8(ascii: "/")) else {
            return nil
        }
        return rowText.utf8.distance(from: rowText.utf8.startIndex, to: slash)
    }
}

private struct FuzzySearchCandidate {
    var index: Int
    var score: Int
    var ranges: [FuzzyMatchRange]
    var tieMetrics: FuzzyTieMetrics?
}

private struct ScoredFuzzyIndex {
    var index: Int
    var score: Int
}

private struct ParsedFuzzySearch {
    var query: FuzzyQuery
    var options: FuzzySearchOptions
}

private struct FuzzyTieMetrics {
    var chunk: Int
    var begin: Int
    var end: Int

    init(rowText: String, ranges: [FuzzyMatchRange]) {
        guard !ranges.isEmpty else {
            chunk = Int.max
            begin = Int.max
            end = Int.max
            return
        }

        let rowBytes = Array(rowText.utf8)
        let minBegin = ranges.map(\.start).min() ?? 0
        let minEnd = ranges.map { $0.start + $0.length }.min() ?? 0
        let maxEnd = ranges.map { $0.start + $0.length }.max() ?? 0
        var chunkBegin = minBegin
        while chunkBegin >= 1 {
            if isChunkWhitespace(rowBytes[chunkBegin - 1]) {
                break
            }
            chunkBegin -= 1
        }
        var chunkEnd = maxEnd
        while chunkEnd < rowBytes.count {
            if isChunkWhitespace(rowBytes[chunkEnd]) {
                break
            }
            chunkEnd += 1
        }
        chunk = max(0, chunkEnd - chunkBegin)

        let trimmedLength = max(1, rowText.trimmingCharacters(in: .whitespaces).utf8.count)
        let whitePrefixLength = rowText.utf8.prefix { byte in
            byte == UInt8(ascii: " ") || byte == 9
        }.count
        let adjustedPrefixLength = min(whitePrefixLength, minBegin)

        begin = max(0, minEnd - adjustedPrefixLength)
        let matchEndRatio = Double(maxEnd - adjustedPrefixLength) / Double(trimmedLength)
        end = Int((1.0 - matchEndRatio) * 1_000_000)
    }
}

private func isChunkWhitespace(_ byte: UInt8) -> Bool {
    byte == UInt8(ascii: " ") || byte == 9
}

private struct FuzzyQuery {
    var clauses: [[FuzzyQueryTerm]]

    var isEmpty: Bool {
        clauses.isEmpty
    }

    var simpleFuzzyBytes: [UInt8]? {
        guard clauses.count == 1,
              clauses[0].count == 1,
              let term = clauses[0].first,
              term.kind == .fuzzy,
              !term.inverse else {
            return nil
        }
        return term.bytes
    }

    static func parse(_ query: String, options: FuzzySearchOptions) -> FuzzyQuery {
        let tokens = tokenize(query)
        var clauses: [[FuzzyQueryTerm]] = []
        var currentClause: [FuzzyQueryTerm] = []
        var previousTokenWasOr = false

        for token in tokens {
            if token == "|" {
                previousTokenWasOr = true
                continue
            }

            let term = FuzzyQueryTerm.parse(token, options: options)
            if currentClause.isEmpty {
                currentClause = [term]
            } else if previousTokenWasOr {
                currentClause.append(term)
            } else {
                clauses.append(currentClause)
                currentClause = [term]
            }
            previousTokenWasOr = false
        }

        if !currentClause.isEmpty {
            clauses.append(currentClause)
        }

        return FuzzyQuery(clauses: clauses)
    }

    private static func tokenize(_ query: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var index = query.startIndex

        while index < query.endIndex {
            let character = query[index]

            if character == "\\" {
                let nextIndex = query.index(after: index)
                if nextIndex < query.endIndex, query[nextIndex].isWhitespace {
                    current.append(query[nextIndex])
                    index = query.index(after: nextIndex)
                    continue
                }
            }

            if character.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current.removeAll(keepingCapacity: true)
                }
            } else {
                current.append(character)
            }

            index = query.index(after: index)
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }

    func match(rowBytes: [UInt8], rowText: String) -> FuzzyTermResult? {
        var totalScore = 0
        var ranges: [FuzzyMatchRange] = []
        for clause in clauses {
            let clauseResult = clause.compactMap { $0.match(rowBytes: rowBytes, rowText: rowText) }
                .max { $0.score < $1.score }
            guard let clauseResult else {
                return nil
            }
            totalScore += clauseResult.score
            ranges.append(contentsOf: clauseResult.ranges)
        }
        return FuzzyTermResult(
            score: totalScore,
            ranges: clauses.count == 1 ? ranges : mergeRanges(ranges)
        )
    }

    func matchScore(rowBytes: [UInt8], rowText: String) -> Int? {
        var totalScore = 0
        for clause in clauses {
            let clauseScore = clause.compactMap { $0.score(rowBytes: rowBytes, rowText: rowText) }.max()
            guard let clauseScore else {
                return nil
            }
            totalScore += clauseScore
        }
        return totalScore
    }
}

private struct FuzzyTermResult: Equatable {
    var score: Int
    var ranges: [FuzzyMatchRange]
}

private struct FuzzyQueryTerm {
    enum Kind {
        case fuzzy
        case exact
        case prefix
        case suffix
    }

    var kind: Kind
    var inverse: Bool
    var text: String
    var bytes: [UInt8]

    static func parse(_ token: String, options: FuzzySearchOptions) -> FuzzyQueryTerm {
        var token = token
        var inverse = false

        if token.hasPrefix("!") {
            inverse = true
            token.removeFirst()
        }

        let kind: Kind
        if token.hasPrefix("^") {
            kind = .prefix
            token.removeFirst()
        } else if token.hasPrefix("'") {
            kind = options.exactMode ? .fuzzy : .exact
            token.removeFirst()
        } else if token.hasSuffix("$") {
            kind = .suffix
            token.removeLast()
        } else if inverse {
            kind = .exact
        } else {
            kind = options.exactMode ? .exact : .fuzzy
        }

        let normalized = normalizedSearchText(token, options: options)
        return FuzzyQueryTerm(
            kind: kind,
            inverse: inverse,
            text: normalized,
            bytes: Array(normalized.utf8)
        )
    }

    func match(rowBytes: [UInt8], rowText: String) -> FuzzyTermResult? {
        let positiveResult: FuzzyTermResult?
        switch kind {
        case .fuzzy:
            positiveResult = FuzzyScorer.match(query: bytes, row: rowBytes)
        case .exact:
            positiveResult = exactMatch(rowText: rowText, scoreBonus: 0)
        case .prefix:
            positiveResult = prefixMatch(rowText: rowText)
        case .suffix:
            positiveResult = suffixMatch(rowText: rowText)
        }

        if inverse {
            return positiveResult == nil ? FuzzyTermResult(score: 0, ranges: []) : nil
        }
        return positiveResult
    }

    func score(rowBytes: [UInt8], rowText: String) -> Int? {
        let positiveScore: Int?
        switch kind {
        case .fuzzy:
            positiveScore = FuzzyScorer.scoreOnly(query: bytes, row: rowBytes)
        case .exact:
            positiveScore = exactScore(rowText: rowText, scoreBonus: 0)
        case .prefix:
            positiveScore = prefixScore(rowText: rowText)
        case .suffix:
            positiveScore = suffixScore(rowText: rowText)
        }

        if inverse {
            return positiveScore == nil ? 0 : nil
        }
        return positiveScore
    }

    private func exactMatch(rowText: String, scoreBonus: Int) -> FuzzyTermResult? {
        guard !text.isEmpty, let range = rowText.range(of: text) else {
            return nil
        }

        let start = rowText[..<range.lowerBound].utf8.count
        let length = text.utf8.count
        return FuzzyTermResult(
            score: max(1, text.count * 4 + scoreBonus),
            ranges: [FuzzyMatchRange(start: start, length: length)]
        )
    }

    private func exactScore(rowText: String, scoreBonus: Int) -> Int? {
        guard !text.isEmpty, rowText.contains(text) else {
            return nil
        }
        return max(1, text.count * 4 + scoreBonus)
    }

    private func prefixMatch(rowText: String) -> FuzzyTermResult? {
        guard rowText.hasPrefix(text), !text.isEmpty else {
            return nil
        }
        return FuzzyTermResult(
            score: max(1, text.count * 4 + 8),
            ranges: [FuzzyMatchRange(start: 0, length: text.utf8.count)]
        )
    }

    private func prefixScore(rowText: String) -> Int? {
        guard rowText.hasPrefix(text), !text.isEmpty else {
            return nil
        }
        return max(1, text.count * 4 + 8)
    }

    private func suffixMatch(rowText: String) -> FuzzyTermResult? {
        guard rowText.hasSuffix(text), !text.isEmpty else {
            return nil
        }
        let length = text.utf8.count
        return FuzzyTermResult(
            score: max(1, text.count * 4 + 8),
            ranges: [FuzzyMatchRange(start: rowText.utf8.count - length, length: length)]
        )
    }

    private func suffixScore(rowText: String) -> Int? {
        guard rowText.hasSuffix(text), !text.isEmpty else {
            return nil
        }
        return max(1, text.count * 4 + 8)
    }
}

public enum FuzzyScorer {
    public static func score(query: [UInt8], row: [UInt8]) -> Int? {
        match(query: query, row: row)?.score
    }

    public static func scoreOnly(query: [UInt8], row: [UInt8]) -> Int? {
        var searchIndex = 0
        var score = 0
        var lastMatch: Int?

        for byte in query {
            var found: Int?
            var index = searchIndex
            while index < row.count {
                if row[index] == byte {
                    found = index
                    break
                }
                index += 1
            }

            guard let found else {
                return nil
            }

            let distance = found - searchIndex
            score += max(1, 20 - distance)
            if let lastMatch, lastMatch + 1 == found {
                score += 10
            }
            if found == 0 || row[found - 1] == UInt8(ascii: "/") || row[found - 1] == UInt8(ascii: "-") {
                score += 5
            }

            lastMatch = found
            searchIndex = found + 1
        }

        return score
    }

    fileprivate static func match(query: [UInt8], row: [UInt8]) -> FuzzyTermResult? {
        var searchIndex = 0
        var score = 0
        var lastMatch: Int?
        var ranges: [FuzzyMatchRange] = []
        ranges.reserveCapacity(query.count)

        for byte in query {
            var found: Int?
            var index = searchIndex
            while index < row.count {
                if row[index] == byte {
                    found = index
                    break
                }
                index += 1
            }

            guard let found else {
                return nil
            }

            let distance = found - searchIndex
            score += max(1, 20 - distance)
            if let lastMatch, lastMatch + 1 == found {
                score += 10
            }
            if found == 0 || row[found - 1] == UInt8(ascii: "/") || row[found - 1] == UInt8(ascii: "-") {
                score += 5
            }

            lastMatch = found
            searchIndex = found + 1
            if let lastRange = ranges.last, lastRange.start + lastRange.length == found {
                ranges[ranges.count - 1] = FuzzyMatchRange(
                    start: lastRange.start,
                    length: lastRange.length + 1
                )
            } else {
                ranges.append(FuzzyMatchRange(start: found, length: 1))
            }
        }

        return FuzzyTermResult(score: score, ranges: ranges)
    }
}

private func mergeRanges(_ ranges: [FuzzyMatchRange]) -> [FuzzyMatchRange] {
    guard !ranges.isEmpty else {
        return []
    }

    let sorted = ranges
        .filter { $0.length > 0 }
        .sorted {
            if $0.start == $1.start {
                return $0.length < $1.length
            }
            return $0.start < $1.start
        }

    var merged: [FuzzyMatchRange] = []
    for range in sorted {
        guard let last = merged.last else {
            merged.append(range)
            continue
        }

        let lastEnd = last.start + last.length
        let rangeEnd = range.start + range.length
        if range.start <= lastEnd {
            merged[merged.count - 1] = FuzzyMatchRange(
                start: last.start,
                length: max(lastEnd, rangeEnd) - last.start
            )
        } else {
            merged.append(range)
        }
    }
    return merged
}

private func normalizedSearchBytes(_ value: String, options: FuzzySearchOptions) -> [UInt8] {
    Array(normalizedSearchText(value, options: options).utf8)
}

private func normalizedSearchText(_ value: String, options: FuzzySearchOptions) -> String {
    options.caseMode == .caseInsensitive ? value.lowercased() : value
}

private extension FuzzySearchOptions {
    static let caseSensitiveOptions = FuzzySearchOptions(caseMode: .caseSensitive)
    static let caseInsensitiveOptions = FuzzySearchOptions(caseMode: .caseInsensitive)
}
