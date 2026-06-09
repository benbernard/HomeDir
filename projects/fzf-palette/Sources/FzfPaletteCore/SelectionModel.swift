import Foundation

public struct SelectionModel: Codable, Equatable {
    public private(set) var selectedIndexes: Set<Int>

    public init(selectedIndexes: Set<Int> = []) {
        self.selectedIndexes = selectedIndexes
    }

    public mutating func toggle(_ index: Int) {
        if selectedIndexes.contains(index) {
            selectedIndexes.remove(index)
        } else {
            selectedIndexes.insert(index)
        }
    }

    public mutating func selectAll(_ indexes: some Sequence<Int>) {
        selectedIndexes.formUnion(indexes)
    }

    public mutating func deselectAll() {
        selectedIndexes.removeAll()
    }

    public var isEmpty: Bool {
        selectedIndexes.isEmpty
    }

    public var count: Int {
        selectedIndexes.count
    }

    public func contains(_ index: Int) -> Bool {
        selectedIndexes.contains(index)
    }

    public func orderedSelection(from rows: [String]) -> [String] {
        selectedIndexes
            .sorted()
            .compactMap { index in
                guard rows.indices.contains(index) else {
                    return nil
                }
                return rows[index]
            }
    }

    public func orderedSelection(from rows: [PaletteRow]) -> [PaletteRow] {
        var bySourceIndex: [Int: PaletteRow] = [:]
        for row in rows {
            bySourceIndex[row.sourceIndex] = row
        }
        return selectedIndexes
            .sorted()
            .compactMap { bySourceIndex[$0] }
    }
}
