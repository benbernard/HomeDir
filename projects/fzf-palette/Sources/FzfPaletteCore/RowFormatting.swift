import Foundation

public struct PaletteRow: Codable, Equatable {
    public var original: String
    public var display: String
    public var search: String
    public var searchToDisplayMap: [SearchDisplayRangeMap]?
    public var ansiStyleSpans: [AnsiStyleSpan]
    public var sourceIndex: Int

    public init(
        original: String,
        display: String,
        sourceIndex: Int = 0,
        search: String? = nil,
        searchToDisplayMap: [SearchDisplayRangeMap]? = nil,
        ansiStyleSpans: [AnsiStyleSpan] = []
    ) {
        self.original = original
        self.display = display
        self.search = search ?? display
        self.searchToDisplayMap = searchToDisplayMap
        self.ansiStyleSpans = ansiStyleSpans
        self.sourceIndex = sourceIndex
    }
}

public enum AnsiColor: String, Codable, Equatable {
    case black
    case red
    case green
    case yellow
    case blue
    case magenta
    case cyan
    case white
    case brightBlack
    case brightRed
    case brightGreen
    case brightYellow
    case brightBlue
    case brightMagenta
    case brightCyan
    case brightWhite
}

public struct AnsiRGBColor: Codable, Equatable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

public struct AnsiStyleSpan: Codable, Equatable {
    public var start: Int
    public var length: Int
    public var foreground: AnsiColor?
    public var foregroundRGB: AnsiRGBColor?
    public var background: AnsiColor?
    public var backgroundRGB: AnsiRGBColor?
    public var bold: Bool
    public var dim: Bool
    public var italic: Bool
    public var underline: Bool
    public var strikethrough: Bool

    public init(
        start: Int,
        length: Int,
        foreground: AnsiColor? = nil,
        foregroundRGB: AnsiRGBColor? = nil,
        background: AnsiColor? = nil,
        backgroundRGB: AnsiRGBColor? = nil,
        bold: Bool = false,
        dim: Bool = false,
        italic: Bool = false,
        underline: Bool = false,
        strikethrough: Bool = false
    ) {
        self.start = start
        self.length = length
        self.foreground = foreground
        self.foregroundRGB = foregroundRGB
        self.background = background
        self.backgroundRGB = backgroundRGB
        self.bold = bold
        self.dim = dim
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
    }
}

public struct AnsiParsedText: Codable, Equatable {
    public var text: String
    public var spans: [AnsiStyleSpan]

    public init(text: String, spans: [AnsiStyleSpan]) {
        self.text = text
        self.spans = spans
    }
}

public struct SearchDisplayRangeMap: Codable, Equatable {
    public var searchStart: Int
    public var displayStart: Int
    public var length: Int

    public init(searchStart: Int, displayStart: Int, length: Int) {
        self.searchStart = searchStart
        self.displayStart = displayStart
        self.length = length
    }
}

public enum RowFormatting {
    public static func row(from original: String, display: DisplayConfig, sourceIndex: Int = 0) -> PaletteRow {
        let formatted = formattedRow(for: original, display: display)
        return PaletteRow(
            original: original,
            display: formatted.display,
            sourceIndex: sourceIndex,
            search: formatted.search,
            searchToDisplayMap: formatted.searchToDisplayMap,
            ansiStyleSpans: formatted.ansiStyleSpans
        )
    }

    public static func rows(from originals: [String], display: DisplayConfig, startingAt startIndex: Int = 0) -> [PaletteRow] {
        originals.enumerated().map { offset, original in
            row(from: original, display: display, sourceIndex: startIndex + offset)
        }
    }

    public static func displayText(for row: String, display: DisplayConfig) -> String {
        let fields = PlaceholderExpansion.splitFields(row: row, delimiter: display.delimiter)
        guard let withNth = display.withNth, !withNth.isEmpty else {
            return display.ansi ? stripANSI(row) : row
        }

        let selected = selectFields(fields, expression: withNth)
        let text = selected.joined(separator: display.delimiter ?? " ")
        return display.ansi ? stripANSI(text) : text
    }

    public static func searchText(for row: String, display: DisplayConfig) -> String {
        guard let nth = display.nth, !nth.isEmpty else {
            return displayText(for: row, display: display)
        }

        let fields = PlaceholderExpansion.splitFields(row: row, delimiter: display.delimiter)
        let selected = selectFields(fields, expression: nth)
        let text = selected.joined(separator: display.delimiter ?? " ")
        return display.ansi ? stripANSI(text) : text
    }

    public static func displayRanges(for searchRanges: [FuzzyMatchRange], row: PaletteRow) -> [FuzzyMatchRange] {
        if row.search == row.display {
            return searchRanges
        }

        guard let maps = row.searchToDisplayMap, !maps.isEmpty else {
            return []
        }

        var displayRanges: [FuzzyMatchRange] = []
        for searchRange in searchRanges {
            let searchEnd = searchRange.start + searchRange.length
            for map in maps {
                let mapEnd = map.searchStart + map.length
                let overlapStart = max(searchRange.start, map.searchStart)
                let overlapEnd = min(searchEnd, mapEnd)
                guard overlapStart < overlapEnd else {
                    continue
                }
                displayRanges.append(FuzzyMatchRange(
                    start: map.displayStart + overlapStart - map.searchStart,
                    length: overlapEnd - overlapStart
                ))
            }
        }

        return mergeRanges(displayRanges)
    }

    public static func selectedText(for row: String, display: DisplayConfig, result: ResultConfig) -> String {
        guard let fieldsExpression = result.fields, !fieldsExpression.isEmpty else {
            return display.ansi ? stripANSI(row) : row
        }

        let fields = PlaceholderExpansion.splitFields(row: row, delimiter: display.delimiter)
        let selected = selectFields(fields, expression: fieldsExpression).map {
            display.ansi ? stripANSI($0) : $0
        }
        if selected.count == 1 {
            return selected[0]
        }
        return join(selected, mode: result.join)
    }

    public static func joinedSelectedText(for rows: [String], display: DisplayConfig, result: ResultConfig) -> String {
        join(rows.map { selectedText(for: $0, display: display, result: result) }, mode: result.join)
    }

    public static func selectFields(_ fields: [String], expression: String) -> [String] {
        selectFieldItems(fields.enumerated().map { FieldItem(index: $0.offset + 1, text: $0.element, sourceStart: 0) }, expression: expression)
            .map(\.text)
    }

    private static func formattedRow(for row: String, display: DisplayConfig) -> FormattedRow {
        let fields = fieldItems(row: row, delimiter: display.delimiter)
        let usesOriginalDisplay = display.withNth?.isEmpty ?? true
        let displayFields = usesOriginalDisplay
            ? fields
            : selectFieldItems(fields, expression: display.withNth ?? "")
        let displayText = usesOriginalDisplay
            ? row
            : joinedText(displayFields.map(\.text), display: display)
        let usesDisplayForSearch = display.nth?.isEmpty ?? true
        let searchFields = usesDisplayForSearch
            ? []
            : selectFieldItems(fields, expression: display.nth ?? "")
        let searchText = usesDisplayForSearch
            ? displayText
            : joinedText(searchFields.map(\.text), display: display)

        if display.ansi {
            let parsedDisplay = parseANSI(displayText)
            let parsedSearch = parseANSI(searchText)
            return FormattedRow(
                display: parsedDisplay.text,
                search: parsedSearch.text,
                searchToDisplayMap: nil,
                ansiStyleSpans: parsedDisplay.spans
            )
        }

        return FormattedRow(
            display: displayText,
            search: searchText,
            searchToDisplayMap: usesDisplayForSearch
                ? nil
                : projectionMap(
                    searchFields: searchFields,
                    displayFields: displayFields,
                    display: display,
                    usesOriginalDisplay: usesOriginalDisplay
                ),
            ansiStyleSpans: []
        )
    }

    public static func stripANSI(_ value: String) -> String {
        parseANSI(value).text
    }

    public static func parseANSI(_ value: String) -> AnsiParsedText {
        var terminal = AnsiTerminalBuffer()
        var activeStyle = ActiveAnsiStyle()

        var index = value.startIndex
        while index < value.endIndex {
            if value[index] == "\u{001B}",
               let sequence = ansiSequence(in: value, startingAt: index) {
                if sequence.final == "m" {
                    activeStyle.applySGR(parameters: sequence.parameters)
                } else {
                    terminal.applyControl(sequence)
                }
                index = sequence.end
                continue
            }

            terminal.write(value[index], style: activeStyle)
            index = value.index(after: index)
        }

        return terminal.parsedText()
    }

    private static func projectionMap(
        searchFields: [FieldItem],
        displayFields: [FieldItem],
        display: DisplayConfig,
        usesOriginalDisplay: Bool
    ) -> [SearchDisplayRangeMap]? {
        guard !searchFields.isEmpty, !displayFields.isEmpty else {
            return nil
        }

        var searchOffsets: [(item: FieldItem, start: Int)] = []
        var searchStart = 0
        for field in searchFields {
            searchOffsets.append((field, searchStart))
            searchStart += field.text.utf8.count + separatorLength(display)
        }

        var displayOffsets: [(item: FieldItem, start: Int)] = []
        var displayStart = 0
        for field in displayFields {
            displayOffsets.append((field, usesOriginalDisplay ? field.sourceStart : displayStart))
            displayStart += field.text.utf8.count + separatorLength(display)
        }

        var usedDisplayOffsets = Set<Int>()
        var maps: [SearchDisplayRangeMap] = []
        for searchField in searchOffsets {
            guard searchField.item.index > 0 else {
                continue
            }
            guard let displayField = displayOffsets.first(where: {
                $0.item.index == searchField.item.index && !usedDisplayOffsets.contains($0.start)
            }) else {
                continue
            }
            usedDisplayOffsets.insert(displayField.start)
            maps.append(SearchDisplayRangeMap(
                searchStart: searchField.start,
                displayStart: displayField.start,
                length: min(searchField.item.text.utf8.count, displayField.item.text.utf8.count)
            ))
        }

        return maps.isEmpty ? nil : maps
    }

    private static func selectFieldItems(_ fields: [FieldItem], expression: String) -> [FieldItem] {
        let tokens = expression
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var selected: [FieldItem] = []
        for token in tokens {
            selected.append(contentsOf: selectFieldRange(fields, token: token))
        }
        return selected
    }

    private static func selectFieldRange(_ fields: [FieldItem], token: String) -> [FieldItem] {
        if token == ".." {
            return fields
        }

        if token.hasSuffix("..") {
            let startText = token.dropLast(2)
            guard let start = resolveIndex(startText, fieldCount: fields.count) else {
                return []
            }
            return Array(fields.dropFirst(start - 1))
        }

        if token.hasPrefix("..") {
            let endText = token.dropFirst(2)
            guard let end = resolveIndex(endText, fieldCount: fields.count) else {
                return []
            }
            return Array(fields.prefix(end))
        }

        if let range = token.range(of: "..") {
            let startText = token[..<range.lowerBound]
            let endText = token[range.upperBound...]
            guard let start = resolveIndex(startText, fieldCount: fields.count),
                  let end = resolveIndex(endText, fieldCount: fields.count),
                  end >= start else {
                return []
            }
            return fields.enumerated().compactMap { index, field in
                let oneBased = index + 1
                return (start...end).contains(oneBased) ? field : nil
            }
        }

        guard let index = resolveIndex(token[...], fieldCount: fields.count), fields.indices.contains(index - 1) else {
            return []
        }
        return [fields[index - 1]]
    }

    private static func fieldItems(row: String, delimiter: String?) -> [FieldItem] {
        guard let delimiter, !delimiter.isEmpty else {
            var fields: [FieldItem] = []
            var fieldStart: String.Index?

            for index in row.indices {
                if row[index] == " " || row[index] == "\t" {
                    if let start = fieldStart {
                        fields.append(FieldItem(
                            index: fields.count + 1,
                            text: String(row[start..<index]),
                            sourceStart: row[..<start].utf8.count
                        ))
                        fieldStart = nil
                    }
                } else if fieldStart == nil {
                    fieldStart = index
                }
            }

            if let start = fieldStart {
                fields.append(FieldItem(
                    index: fields.count + 1,
                    text: String(row[start...]),
                    sourceStart: row[..<start].utf8.count
                ))
            }
            return fields
        }

        var fields: [FieldItem] = []
        var offset = 0
        for field in row.components(separatedBy: delimiter) {
            fields.append(FieldItem(index: fields.count + 1, text: field, sourceStart: offset))
            offset += field.utf8.count + delimiter.utf8.count
        }
        return fields
    }

    private static func joinedText(_ fields: [String], display: DisplayConfig) -> String {
        fields.joined(separator: display.delimiter ?? " ")
    }

    private static func separatorLength(_ display: DisplayConfig) -> Int {
        (display.delimiter ?? " ").utf8.count
    }

    private static func resolveIndex<S: StringProtocol>(_ text: S, fieldCount: Int) -> Int? {
        guard let parsed = Int(text), parsed != 0 else {
            return nil
        }
        return parsed < 0 ? fieldCount + parsed + 1 : parsed
    }

    public static func join(_ fields: [String], mode: JoinMode) -> String {
        switch mode {
        case .newline:
            return fields.joined(separator: "\n")
        case .space:
            return fields.joined(separator: " ")
        case .nul:
            return fields.joined(separator: "\0")
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            let data = (try? encoder.encode(fields)) ?? Data("[]".utf8)
            return String(decoding: data, as: UTF8.self)
        }
    }
}

private struct FieldItem: Equatable {
    var index: Int
    var text: String
    var sourceStart: Int
}

private struct FormattedRow: Equatable {
    var display: String
    var search: String
    var searchToDisplayMap: [SearchDisplayRangeMap]?
    var ansiStyleSpans: [AnsiStyleSpan]
}

private struct ActiveAnsiStyle: Equatable {
    var foreground: AnsiColor?
    var foregroundRGB: AnsiRGBColor?
    var background: AnsiColor?
    var backgroundRGB: AnsiRGBColor?
    var bold = false
    var dim = false
    var italic = false
    var underline = false
    var strikethrough = false

    var isVisible: Bool {
        foreground != nil ||
            foregroundRGB != nil ||
            background != nil ||
            backgroundRGB != nil ||
            bold ||
            dim ||
            italic ||
            underline ||
            strikethrough
    }

    mutating func applySGR(parameters: [Int]) {
        let parameters = parameters.isEmpty ? [0] : parameters
        var index = 0
        while index < parameters.count {
            let parameter = parameters[index]
            switch parameter {
            case 0:
                reset()
            case 1:
                bold = true
                dim = false
            case 2:
                dim = true
            case 3:
                italic = true
            case 4:
                underline = true
            case 9:
                strikethrough = true
            case 22:
                bold = false
                dim = false
            case 23:
                italic = false
            case 24:
                underline = false
            case 29:
                strikethrough = false
            case 30...37, 90...97:
                foreground = AnsiColor(sgrForeground: parameter)
                foregroundRGB = nil
            case 39:
                foreground = nil
                foregroundRGB = nil
            case 40...47, 100...107:
                background = AnsiColor(sgrBackground: parameter)
                backgroundRGB = nil
            case 49:
                background = nil
                backgroundRGB = nil
            case 38:
                index = applyExtendedColor(parameters: parameters, index: index, target: .foreground)
            case 48:
                index = applyExtendedColor(parameters: parameters, index: index, target: .background)
            default:
                break
            }
            index += 1
        }
    }

    private mutating func reset() {
        foreground = nil
        foregroundRGB = nil
        background = nil
        backgroundRGB = nil
        bold = false
        dim = false
        italic = false
        underline = false
        strikethrough = false
    }

    private enum ExtendedColorTarget {
        case foreground
        case background
    }

    private mutating func applyExtendedColor(
        parameters: [Int],
        index: Int,
        target: ExtendedColorTarget
    ) -> Int {
        guard index + 1 < parameters.count else {
            return index
        }

        switch parameters[index + 1] {
        case 5:
            guard index + 2 < parameters.count else {
                return index + 1
            }
            setColor(ansi256Color(parameters[index + 2]), target: target)
            return index + 2
        case 2:
            guard index + 4 < parameters.count else {
                return index + 1
            }
            setColor(
                AnsiRGBColor(
                    red: clampedByte(parameters[index + 2]),
                    green: clampedByte(parameters[index + 3]),
                    blue: clampedByte(parameters[index + 4])
                ),
                target: target
            )
            return index + 4
        default:
            return index + 1
        }
    }

    private mutating func setColor(_ color: AnsiRGBColor, target: ExtendedColorTarget) {
        switch target {
        case .foreground:
            foreground = nil
            foregroundRGB = color
        case .background:
            background = nil
            backgroundRGB = color
        }
    }
}

private struct AnsiTerminalBuffer {
    private var lines: [[AnsiTerminalCell]] = [[]]
    private var row = 0
    private var column = 0
    private var savedRow = 0
    private var savedColumn = 0

    mutating func write(_ character: Character, style: ActiveAnsiStyle) {
        switch character {
        case "\n":
            row += 1
            column = 0
            ensureLine(row)
        case "\r":
            column = 0
        case "\t":
            let spaces = max(1, 8 - (column % 8))
            for _ in 0..<spaces {
                put(" ", style: style)
            }
        case "\u{0008}":
            column = max(0, column - 1)
        default:
            guard !character.isANSIIgnoredControl else {
                return
            }
            put(character, style: style)
        }
    }

    mutating func applyControl(_ sequence: AnsiSequence) {
        switch sequence.final {
        case "A":
            row = max(0, row - controlParameter(sequence, defaultValue: 1))
            ensureLine(row)
        case "B":
            row += controlParameter(sequence, defaultValue: 1)
            ensureLine(row)
        case "C":
            column += controlParameter(sequence, defaultValue: 1)
        case "D":
            column = max(0, column - controlParameter(sequence, defaultValue: 1))
        case "E":
            row += controlParameter(sequence, defaultValue: 1)
            column = 0
            ensureLine(row)
        case "F":
            row = max(0, row - controlParameter(sequence, defaultValue: 1))
            column = 0
            ensureLine(row)
        case "G":
            column = max(0, controlParameter(sequence, defaultValue: 1) - 1)
        case "H", "f":
            row = max(0, controlParameter(sequence, at: 0, defaultValue: 1) - 1)
            column = max(0, controlParameter(sequence, at: 1, defaultValue: 1) - 1)
            ensureLine(row)
        case "d":
            row = max(0, controlParameter(sequence, defaultValue: 1) - 1)
            ensureLine(row)
        case "J":
            clearScreen(mode: controlParameter(sequence, defaultValue: 0))
        case "K":
            clearLine(mode: controlParameter(sequence, defaultValue: 0))
        case "L":
            insertLines(count: controlParameter(sequence, defaultValue: 1))
        case "M":
            deleteLines(count: controlParameter(sequence, defaultValue: 1))
        case "S":
            scrollUp(count: controlParameter(sequence, defaultValue: 1))
        case "T":
            scrollDown(count: controlParameter(sequence, defaultValue: 1))
        case "s":
            savedRow = row
            savedColumn = column
        case "u":
            row = savedRow
            column = savedColumn
            ensureLine(row)
        default:
            break
        }
    }

    func parsedText() -> AnsiParsedText {
        var output = ""
        var spans: [AnsiStyleSpan] = []
        var activeStyle: ActiveAnsiStyle?
        var activeSpanStart = 0

        func closeActiveSpan() {
            guard let style = activeStyle else {
                return
            }
            let length = output.utf8.count - activeSpanStart
            if length > 0 {
                spans.append(AnsiStyleSpan(
                    start: activeSpanStart,
                    length: length,
                    foreground: style.foreground,
                    foregroundRGB: style.foregroundRGB,
                    background: style.background,
                    backgroundRGB: style.backgroundRGB,
                    bold: style.bold,
                    dim: style.dim,
                    italic: style.italic,
                    underline: style.underline,
                    strikethrough: style.strikethrough
                ))
            }
            activeStyle = nil
        }

        for (lineIndex, line) in lines.enumerated() {
            for cell in line {
                if cell.style.isVisible {
                    if activeStyle != cell.style {
                        closeActiveSpan()
                        activeStyle = cell.style
                        activeSpanStart = output.utf8.count
                    }
                } else {
                    closeActiveSpan()
                }
                output.append(cell.character)
            }

            if lineIndex < lines.count - 1 {
                closeActiveSpan()
                output.append("\n")
            }
        }
        closeActiveSpan()

        return AnsiParsedText(text: output, spans: spans)
    }

    private mutating func put(_ character: Character, style: ActiveAnsiStyle) {
        ensureLine(row)
        if column > lines[row].count {
            lines[row].append(contentsOf: Array(repeating: AnsiTerminalCell.blank, count: column - lines[row].count))
        }
        let cell = AnsiTerminalCell(character: character, style: style)
        if column == lines[row].count {
            lines[row].append(cell)
        } else {
            lines[row][column] = cell
        }
        column += 1
    }

    private mutating func ensureLine(_ index: Int) {
        while lines.count <= index {
            lines.append([])
        }
    }

    private mutating func clearLine(mode: Int) {
        ensureLine(row)
        switch mode {
        case 1:
            guard !lines[row].isEmpty else {
                return
            }
            let end = min(column, max(0, lines[row].count - 1))
            if end >= 0 {
                for index in 0...end {
                    lines[row][index] = .blank
                }
            }
        case 2:
            lines[row].removeAll(keepingCapacity: true)
        default:
            if column < lines[row].count {
                lines[row].removeSubrange(column..<lines[row].count)
            }
        }
    }

    private mutating func clearScreen(mode: Int) {
        switch mode {
        case 1:
            if row > 0 {
                for index in 0..<min(row, lines.count) {
                    lines[index].removeAll(keepingCapacity: true)
                }
            }
            clearLine(mode: 1)
        case 2, 3:
            lines = [[]]
            row = 0
            column = 0
        default:
            clearLine(mode: 0)
            if row + 1 < lines.count {
                lines.removeSubrange((row + 1)..<lines.count)
            }
        }
    }

    private mutating func insertLines(count: Int) {
        ensureLine(row)
        let blanks = Array(repeating: [AnsiTerminalCell](), count: max(0, count))
        guard !blanks.isEmpty else {
            return
        }
        lines.insert(contentsOf: blanks, at: row)
    }

    private mutating func deleteLines(count: Int) {
        ensureLine(row)
        let removeCount = min(max(0, count), lines.count - row)
        guard removeCount > 0 else {
            return
        }
        lines.removeSubrange(row..<(row + removeCount))
        if lines.isEmpty {
            lines = [[]]
            row = 0
            column = 0
        } else {
            row = min(row, lines.count - 1)
        }
    }

    private mutating func scrollUp(count: Int) {
        let removeCount = min(max(0, count), lines.count)
        guard removeCount > 0 else {
            return
        }
        lines.removeFirst(removeCount)
        if lines.isEmpty {
            lines = [[]]
        }
        row = min(row, lines.count - 1)
    }

    private mutating func scrollDown(count: Int) {
        let blanks = Array(repeating: [AnsiTerminalCell](), count: max(0, count))
        guard !blanks.isEmpty else {
            return
        }
        lines.insert(contentsOf: blanks, at: 0)
    }

    private func controlParameter(_ sequence: AnsiSequence, at index: Int = 0, defaultValue: Int) -> Int {
        guard sequence.parameters.indices.contains(index), sequence.parameters[index] > 0 else {
            return defaultValue
        }
        return sequence.parameters[index]
    }
}

private struct AnsiTerminalCell: Equatable {
    var character: Character
    var style: ActiveAnsiStyle

    static let blank = AnsiTerminalCell(character: " ", style: ActiveAnsiStyle())
}

private struct AnsiSequence {
    var parameters: [Int]
    var final: Character
    var end: String.Index
}

private func ansiSequence(in value: String, startingAt start: String.Index) -> AnsiSequence? {
    let afterEscape = value.index(after: start)
    guard afterEscape < value.endIndex, value[afterEscape] == "[" else {
        return nil
    }

    var index = value.index(after: afterEscape)
    let parametersStart = index
    while index < value.endIndex {
        let character = value[index]
        if character.isASCIIAlpha {
            let parametersText = String(value[parametersStart..<index])
            let parameters = parametersText
                .split(separator: ";", omittingEmptySubsequences: false)
                .compactMap { Int($0) }
            return AnsiSequence(
                parameters: parameters,
                final: character,
                end: value.index(after: index)
            )
        }
        index = value.index(after: index)
    }

    return nil
}

private extension Character {
    var isASCIIAlpha: Bool {
        guard unicodeScalars.count == 1, let scalar = unicodeScalars.first else {
            return false
        }
        return (65...90).contains(Int(scalar.value)) || (97...122).contains(Int(scalar.value))
    }

    var isANSIIgnoredControl: Bool {
        guard unicodeScalars.count == 1, let scalar = unicodeScalars.first else {
            return false
        }
        return scalar.value < 32 || scalar.value == 127
    }
}

private extension AnsiColor {
    init?(sgrForeground code: Int) {
        switch code {
        case 30: self = .black
        case 31: self = .red
        case 32: self = .green
        case 33: self = .yellow
        case 34: self = .blue
        case 35: self = .magenta
        case 36: self = .cyan
        case 37: self = .white
        case 90: self = .brightBlack
        case 91: self = .brightRed
        case 92: self = .brightGreen
        case 93: self = .brightYellow
        case 94: self = .brightBlue
        case 95: self = .brightMagenta
        case 96: self = .brightCyan
        case 97: self = .brightWhite
        default: return nil
        }
    }

    init?(sgrBackground code: Int) {
        switch code {
        case 40: self = .black
        case 41: self = .red
        case 42: self = .green
        case 43: self = .yellow
        case 44: self = .blue
        case 45: self = .magenta
        case 46: self = .cyan
        case 47: self = .white
        case 100: self = .brightBlack
        case 101: self = .brightRed
        case 102: self = .brightGreen
        case 103: self = .brightYellow
        case 104: self = .brightBlue
        case 105: self = .brightMagenta
        case 106: self = .brightCyan
        case 107: self = .brightWhite
        default: return nil
        }
    }
}

private func clampedByte(_ value: Int) -> UInt8 {
    UInt8(max(0, min(255, value)))
}

private func ansi256Color(_ code: Int) -> AnsiRGBColor {
    let clamped = max(0, min(255, code))
    let standardColors: [AnsiRGBColor] = [
        AnsiRGBColor(red: 0, green: 0, blue: 0),
        AnsiRGBColor(red: 205, green: 49, blue: 49),
        AnsiRGBColor(red: 13, green: 188, blue: 121),
        AnsiRGBColor(red: 229, green: 229, blue: 16),
        AnsiRGBColor(red: 36, green: 114, blue: 200),
        AnsiRGBColor(red: 188, green: 63, blue: 188),
        AnsiRGBColor(red: 17, green: 168, blue: 205),
        AnsiRGBColor(red: 229, green: 229, blue: 229),
        AnsiRGBColor(red: 102, green: 102, blue: 102),
        AnsiRGBColor(red: 241, green: 76, blue: 76),
        AnsiRGBColor(red: 35, green: 209, blue: 139),
        AnsiRGBColor(red: 245, green: 245, blue: 67),
        AnsiRGBColor(red: 59, green: 142, blue: 234),
        AnsiRGBColor(red: 214, green: 112, blue: 214),
        AnsiRGBColor(red: 41, green: 184, blue: 219),
        AnsiRGBColor(red: 229, green: 229, blue: 229)
    ]

    if clamped < standardColors.count {
        return standardColors[clamped]
    }

    if clamped >= 232 {
        let level = UInt8(8 + (clamped - 232) * 10)
        return AnsiRGBColor(red: level, green: level, blue: level)
    }

    let cubeIndex = clamped - 16
    let red = cubeIndex / 36
    let green = (cubeIndex % 36) / 6
    let blue = cubeIndex % 6
    func component(_ value: Int) -> UInt8 {
        UInt8(value == 0 ? 0 : 55 + value * 40)
    }
    return AnsiRGBColor(red: component(red), green: component(green), blue: component(blue))
}

private func mergeRanges(_ ranges: [FuzzyMatchRange]) -> [FuzzyMatchRange] {
    guard !ranges.isEmpty else {
        return []
    }

    var merged: [FuzzyMatchRange] = []
    for range in ranges.sorted(by: { $0.start < $1.start }) {
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
