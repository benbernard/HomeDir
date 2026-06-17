import AppKit
import FzfPaletteCore

private struct RenderedPixelMetrics {
    var width: Int = 0
    var height: Int = 0
    var sampledPixels: Int = 0
    var distinctColorBuckets: Int = 0
    var nonBackgroundSampleRatio: Double = 0
    var averageLuminance: Double = 0
    var luminanceStandardDeviation: Double = 0
}

private struct RGBSample {
    var red: Double
    var green: Double
    var blue: Double
}

private enum PaletteVisualStyle {
    static let contentCornerRadius: CGFloat = 18
    static let paneCornerRadius: CGFloat = 12
    static let paneBorderWidth: CGFloat = 0.8
    static let rowSelectionCornerRadius: CGFloat = 8

    static func cgColor(_ color: NSColor, alpha: CGFloat = 1) -> CGColor {
        let resolved = color.withAlphaComponent(alpha).usingColorSpace(.deviceRGB)
        return resolved?.cgColor ?? NSColor(calibratedWhite: 0.5, alpha: alpha).cgColor
    }

    static func adaptiveColor(light: NSColor, dark: NSColor, for view: NSView?) -> NSColor {
        let appearance = view?.effectiveAppearance ?? NSApp.effectiveAppearance
        let bestMatch = appearance.bestMatch(from: [.darkAqua, .aqua])
        return bestMatch == .darkAqua ? dark : light
    }

    static func rootBorderColor(for view: NSView?) -> CGColor {
        cgColor(
            adaptiveColor(
                light: NSColor(calibratedWhite: 0.56, alpha: 1),
                dark: NSColor(calibratedWhite: 0.78, alpha: 1),
                for: view
            ),
            alpha: 0.30
        )
    }

    static func paneBackgroundColor(for view: NSView?) -> CGColor {
        cgColor(
            adaptiveColor(
                light: NSColor(calibratedRed: 0.995, green: 0.995, blue: 1.0, alpha: 1),
                dark: NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.13, alpha: 1),
                for: view
            ),
            alpha: 0.86
        )
    }

    static func contentBackgroundColor(for view: NSView?) -> CGColor {
        cgColor(
            adaptiveColor(
                light: NSColor(calibratedRed: 0.935, green: 0.948, blue: 0.965, alpha: 1),
                dark: NSColor(calibratedRed: 0.055, green: 0.065, blue: 0.080, alpha: 1),
                for: view
            ),
            alpha: 0.84
        )
    }

    static func paneBorderColor(for view: NSView?) -> CGColor {
        cgColor(
            adaptiveColor(
                light: NSColor(calibratedWhite: 0.62, alpha: 1),
                dark: NSColor(calibratedWhite: 0.92, alpha: 1),
                for: view
            ),
            alpha: 0.18
        )
    }

    static func selectionFillColor(for view: NSView?) -> NSColor {
        adaptiveColor(
            light: NSColor.controlAccentColor.withSystemEffect(.pressed),
            dark: NSColor.controlAccentColor,
            for: view
        ).withAlphaComponent(0.24)
    }

    static func selectionStrokeColor(for view: NSView?) -> NSColor {
        NSColor.controlAccentColor.withAlphaComponent(0.34)
    }
}

private final class PaletteResultRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else {
            return
        }

        let selectionRect = bounds.insetBy(dx: 3, dy: 2)
        let path = NSBezierPath(
            roundedRect: selectionRect,
            xRadius: PaletteVisualStyle.rowSelectionCornerRadius,
            yRadius: PaletteVisualStyle.rowSelectionCornerRadius
        )
        PaletteVisualStyle.selectionFillColor(for: self).withAlphaComponent(window?.isKeyWindow == true ? 0.28 : 0.14).setFill()
        path.fill()
        PaletteVisualStyle.selectionStrokeColor(for: self).setStroke()
        path.lineWidth = 0.8
        path.stroke()
    }
}

enum PanelOutcome: Equatable {
    case selected([String])
    case cancelled
}

final class PalettePanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSSearchFieldDelegate {
    private let resultFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private let resultHighlightFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
    private let promptLabel = NSTextField(labelWithString: ">")
    private let queryField = NSSearchField(frame: .zero)
    private let headerLabel = NSTextField(labelWithString: "")
    private let tableView = NSTableView(frame: .zero)
    private let splitView = NSSplitView(frame: .zero)
    private let resultsScrollView = NSScrollView(frame: .zero)
    private let previewScrollView = NSScrollView(frame: .zero)
    private let previewTextView = NSTextView(frame: .zero)
    private let statusLabel = NSTextField(labelWithString: "Ready")
    private let accentLine = NSView(frame: .zero)
    private var allRows: [PaletteRow] = []
    private var matchRangesBySourceIndex: [Int: [FuzzyMatchRange]] = [:]
    private var searchEngine = NativeFuzzySearchEngine()
    private var allowsMultipleSelection = false
    private var allowsPreviewToggle = false
    private var isPreviewPaneVisible = true
    private var pointerSymbol: String?
    private var markerSymbol: String?
    private var infoStyle: String?
    private var previewLayout = PreviewWindowLayout()
    private var previewAnsiSpanCount = 0
    private var previewAnsiRGBSpanCount = 0
    private var previewAnsiBackgroundSpanCount = 0
    private var previewAnsiTextStyleSpanCount = 0
    private var activeRowChangeHandler: ((PaletteRow?) -> Void)?
    private var lastNotifiedSourceIndex: Int?
    private var completion: ((PanelOutcome) -> Void)?
    private var keyMonitor: Any?
    private var rows: [PaletteRow] = [
        PaletteRow(original: "Native panel ready", display: "Native panel ready"),
        PaletteRow(original: "Source streaming pending", display: "Source streaming pending"),
        PaletteRow(original: "Engine integration pending", display: "Engine integration pending")
    ]

    var visibleRowCount: Int {
        rows.count
    }

    var isPanelVisible: Bool {
        panel.isVisible
    }

    var isPreviewVisible: Bool {
        isPreviewPaneVisible
    }

    var currentPrompt: String {
        promptLabel.stringValue
    }

    var currentHeader: String {
        headerLabel.stringValue
    }

    var currentPointer: String? {
        pointerSymbol
    }

    var currentMarker: String? {
        markerSymbol
    }

    var currentInfo: String? {
        infoStyle
    }

    func visualSnapshot() -> PanelVisualSnapshot {
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.contentView?.displayIfNeeded()
        let pixelMetrics = renderedPixelMetrics(for: panel.contentView)
        let captureRect = screenCaptureRect()

        return PanelVisualSnapshot(
            panelVisible: panel.isVisible,
            queryFieldFocused: isQueryFieldFocused,
            queryFieldActionBound: queryField.target != nil || queryField.action != nil,
            windowNumber: panel.windowNumber,
            captureX: captureRect.x,
            captureY: captureRect.y,
            captureWidth: captureRect.width,
            captureHeight: captureRect.height,
            width: panel.frame.width,
            height: panel.frame.height,
            renderedWidth: pixelMetrics.width,
            renderedHeight: pixelMetrics.height,
            sampledPixels: pixelMetrics.sampledPixels,
            distinctColorBuckets: pixelMetrics.distinctColorBuckets,
            nonBackgroundSampleRatio: pixelMetrics.nonBackgroundSampleRatio,
            averageLuminance: pixelMetrics.averageLuminance,
            luminanceStandardDeviation: pixelMetrics.luminanceStandardDeviation,
            effectiveAppearanceName: panel.effectiveAppearance.name.rawValue,
            usesVibrantBackground: panel.contentView is NSVisualEffectView,
            contentCornerRadius: Double(panel.contentView?.layer?.cornerRadius ?? 0),
            resultsCornerRadius: Double(resultsScrollView.layer?.cornerRadius ?? 0),
            previewCornerRadius: Double(previewScrollView.layer?.cornerRadius ?? 0),
            usesCustomSelectionStyle: true,
            visibleRows: rows.count,
            selectedRowIndex: tableView.selectedRow,
            activeRowText: activeRow()?.original ?? "",
            previewVisible: isPreviewPaneVisible,
            previewWidth: isPreviewPaneVisible ? previewScrollView.frame.width : 0,
            previewHeight: isPreviewPaneVisible ? previewScrollView.frame.height : 0,
            resultsWidth: resultsScrollView.frame.width,
            resultsHeight: resultsScrollView.frame.height,
            previewPosition: previewLayout.position.rawValue,
            previewWrap: previewLayout.wrap,
            previewCharacterCount: previewTextView.string.count,
            previewAnsiSpanCount: previewAnsiSpanCount,
            previewAnsiRGBSpanCount: previewAnsiRGBSpanCount,
            previewAnsiBackgroundSpanCount: previewAnsiBackgroundSpanCount,
            previewAnsiTextStyleSpanCount: previewAnsiTextStyleSpanCount,
            previewContainsEscapeSequences: previewTextView.string.contains("\u{001B}"),
            previewTextSample: String(previewTextView.string.prefix(1_000)),
            previewScrollOffsetY: previewScrollView.contentView.bounds.origin.y,
            layoutViolationCount: layoutViolationCount()
        )
    }

    private func screenCaptureRect() -> (x: Int, y: Int, width: Int, height: Int) {
        let frame = panel.frame
        let screenFrame = panel.screen?.frame ?? NSScreen.main?.frame ?? frame
        let x = Int((frame.minX - screenFrame.minX).rounded())
        let y = Int((screenFrame.maxY - frame.maxY).rounded())
        return (
            x: max(0, x),
            y: max(0, y),
            width: max(1, Int(frame.width.rounded())),
            height: max(1, Int(frame.height.rounded()))
        )
    }

    @discardableResult
    func benchmarkPanelShow(title: String = "fzf-palette bench") -> Double {
        let start = ContinuousClock.now
        showPlaceholder(title: title, message: "Panel benchmark")
        let elapsed = start.duration(to: ContinuousClock.now)
        hide()
        return Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
    }

    func benchmarkKeystrokeFiltering(rows sourceRows: [String], queries: [String]) -> [Double] {
        showRows(
            title: "keystroke bench",
            rows: sourceRows,
            display: DisplayConfig(),
            preview: "Keystroke benchmark",
            allowsMultipleSelection: false
        )

        let durations = queries.map { query in
            queryField.stringValue = query
            return applyCurrentQuery(statusContext: "keystroke bench")
        }

        hide()
        return durations
    }

    private lazy var panel: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 560),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "fzf-palette"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.contentView = buildContentView()
        return panel
    }()

    func prepare() {
        _ = panel
    }

    func setCompletion(_ completion: ((PanelOutcome) -> Void)?) {
        self.completion = completion
    }

    func clearCompletion() {
        completion = nil
    }

    func setActiveRowChangeHandler(_ handler: ((PaletteRow?) -> Void)?, notifyImmediately: Bool = true) {
        activeRowChangeHandler = handler
        lastNotifiedSourceIndex = nil
        if notifyImmediately {
            notifyActiveRowChanged()
        }
    }

    func clearActiveRowChangeHandler() {
        activeRowChangeHandler = nil
        lastNotifiedSourceIndex = nil
    }

    func showPlaceholder(title: String, message: String) {
        rows = [
            PaletteRow(original: title, display: title, sourceIndex: 0),
            PaletteRow(original: "Socket trigger received", display: "Socket trigger received", sourceIndex: 1),
            PaletteRow(
                original: "Next implementation slice: source streaming, filtering, and selection",
                display: "Next implementation slice: source streaming, filtering, and selection",
                sourceIndex: 2
            )
        ]
        allRows = rows
        matchRangesBySourceIndex = [:]
        allowsMultipleSelection = false
        allowsPreviewToggle = false
        configureChrome(title: title, display: DisplayConfig())
        configurePreviewLayout(PreviewWindowLayout())
        setPreviewPaneVisible(true, updateStatus: false)
        searchEngine.replaceRows(rows)
        setPlainPreviewText(message)
        updateStatus(context: "native panel")
        tableView.reloadData()
        showPanel()
    }

    func showRows(
        title: String,
        rows newRows: [String],
        display: DisplayConfig = DisplayConfig(),
        preview: String? = nil,
        previewConfig: PreviewConfig? = nil,
        allowsMultipleSelection: Bool = false,
        allowsPreviewToggle: Bool = false,
        initialQuery: String = "",
        searchOptions: FuzzySearchOptions = FuzzySearchOptions()
    ) {
        allRows = RowFormatting.rows(from: newRows, display: display)
        searchEngine = NativeFuzzySearchEngine(rows: allRows, options: searchOptions)
        self.allowsMultipleSelection = allowsMultipleSelection
        self.allowsPreviewToggle = allowsPreviewToggle
        configureChrome(title: title, display: display)
        configurePreviewLayout(previewConfig?.layout ?? PreviewWindowLayout())
        queryField.stringValue = initialQuery
        updateRows(for: initialQuery)
        setPlainPreviewText(preview ?? "Rows loaded for \(title)")
        setPreviewPaneVisible(true, updateStatus: false)
        updateStatus(context: title)
        tableView.reloadData()
        selectFirstVisibleRow()
        notifyActiveRowChanged()
        showPanel()
    }

    func appendRows(_ newRows: [String], title: String, display: DisplayConfig) {
        guard !newRows.isEmpty else {
            return
        }

        let formattedRows = RowFormatting.rows(from: newRows, display: display, startingAt: allRows.count)
        allRows.append(contentsOf: formattedRows)
        searchEngine.appendRows(formattedRows)
        let query = queryField.stringValue
        updateRows(for: query)
        updateStatus(context: title)
        tableView.reloadData()
        if tableView.selectedRow < 0 {
            selectFirstVisibleRow()
        }
        notifyActiveRowChanged()
    }

    func showError(title: String, message: String) {
        allRows = []
        matchRangesBySourceIndex = [:]
        allowsMultipleSelection = false
        allowsPreviewToggle = false
        configureChrome(title: title, display: DisplayConfig(header: message))
        configurePreviewLayout(PreviewWindowLayout())
        setPreviewPaneVisible(true, updateStatus: false)
        searchEngine.replaceRows([])
        rows = [
            PaletteRow(original: title, display: title, sourceIndex: 0),
            PaletteRow(original: message, display: message, sourceIndex: 1)
        ]
        setPlainPreviewText(message)
        statusLabel.stringValue = "error | native panel"
        tableView.reloadData()
        showPanel()
    }

    func showPreview(_ text: String, scrollTarget: PreviewScrollTarget? = nil) {
        let parsed = RowFormatting.parseANSI(text)
        updatePreviewAnsiMetrics(parsed.spans)
        previewTextView.textStorage?.setAttributedString(attributedPreviewText(parsed))
        applyPreviewScrollTarget(scrollTarget)
    }

    private func setPlainPreviewText(_ text: String) {
        updatePreviewAnsiMetrics([])
        previewTextView.string = text
        applyPreviewScrollTarget(nil)
    }

    private func updatePreviewAnsiMetrics(_ spans: [AnsiStyleSpan]) {
        previewAnsiSpanCount = spans.count
        previewAnsiRGBSpanCount = spans.filter { $0.foregroundRGB != nil || $0.backgroundRGB != nil }.count
        previewAnsiBackgroundSpanCount = spans.filter { $0.background != nil || $0.backgroundRGB != nil }.count
        previewAnsiTextStyleSpanCount = spans.filter {
            $0.bold || $0.dim || $0.italic || $0.underline || $0.strikethrough
        }.count
    }

    func controlTextDidChange(_ notification: Notification) {
        applyCurrentQuery(statusContext: "native filter")
    }

    func setQuery(_ query: String) {
        queryField.stringValue = query
        applyCurrentQuery(statusContext: "test query")
    }

    func refocusQueryFieldForTests() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(queryField)
    }

    func selectNextRow() {
        _ = moveSelection(delta: 1)
    }

    func selectPreviousRow() {
        _ = moveSelection(delta: -1)
    }

    func handleSyntheticKey(_ key: String) -> Bool {
        switch key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "down", "arrowdown":
            return handlePaletteKey(keyCode: 125, charactersIgnoringModifiers: nil, modifierFlags: [])
        case "up", "arrowup":
            return handlePaletteKey(keyCode: 126, charactersIgnoringModifiers: nil, modifierFlags: [])
        case "tab":
            return handlePaletteKey(keyCode: 48, charactersIgnoringModifiers: "\t", modifierFlags: [])
        case "return", "enter":
            return handlePaletteKey(keyCode: 36, charactersIgnoringModifiers: "\r", modifierFlags: [])
        case "escape", "esc":
            return handlePaletteKey(keyCode: 53, charactersIgnoringModifiers: "\u{1b}", modifierFlags: [])
        case "space":
            return handlePaletteKey(keyCode: 49, charactersIgnoringModifiers: " ", modifierFlags: [])
        default:
            return false
        }
    }

    @discardableResult
    func benchmarkSelectionMovement(
        rows sourceRows: [String],
        steps: Int,
        previewConfig: PreviewConfig? = nil
    ) -> [Double] {
        showRows(
            title: "movement bench",
            rows: sourceRows,
            display: DisplayConfig(),
            preview: "Movement benchmark",
            previewConfig: previewConfig,
            allowsMultipleSelection: false
        )

        let durations = (0..<max(0, steps)).map { _ in moveSelection(delta: 1) }
        hide()
        return durations
    }

    @discardableResult
    private func moveSelection(delta: Int) -> Double {
        let start = ContinuousClock.now
        guard !rows.isEmpty else {
            return milliseconds(start.duration(to: ContinuousClock.now))
        }

        let current = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
        let next = max(0, min(current + delta, rows.count - 1))
        guard next != current else {
            return milliseconds(start.duration(to: ContinuousClock.now))
        }

        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
        tableView.displayIfNeeded()
        return milliseconds(start.duration(to: ContinuousClock.now))
    }

    @discardableResult
    private func applyCurrentQuery(statusContext: String) -> Double {
        let start = ContinuousClock.now
        let query = queryField.stringValue
        updateRows(for: query)
        updateStatus(context: statusContext)
        tableView.reloadData()
        selectFirstVisibleRow()
        notifyActiveRowChanged()
        tableView.layoutSubtreeIfNeeded()
        tableView.displayIfNeeded()

        let elapsed = start.duration(to: ContinuousClock.now)
        return Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
    }

    private func showPanel() {
        if let screen = NSScreen.main {
            let frame = panel.frame
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: visible.midX - frame.width / 2,
                y: visible.midY - frame.height / 2
            ))
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(queryField)
        panel.contentView?.layoutSubtreeIfNeeded()
        layoutPreviewPaneIfNeeded()
        panel.contentView?.layoutSubtreeIfNeeded()
        installKeyMonitor()
    }

    func hide() {
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    func cancelActivePicker() {
        let callback = completion
        completion = nil
        hide()
        callback?(.cancelled)
    }

    func acceptCurrentSelection() {
        guard !rows.isEmpty else {
            cancelActivePicker()
            return
        }

        let selected = acceptedRows().map(\.original)
        let callback = completion
        completion = nil
        hide()
        callback?(.selected(selected))
    }

    func toggleCurrentSelection() {
        guard allowsMultipleSelection, !rows.isEmpty else {
            return
        }

        let rowIndex = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
        let row = rows[min(rowIndex, rows.count - 1)]
        searchEngine.toggleSelection(sourceIndex: row.sourceIndex)
        updateStatus(context: "multi-select")
        tableView.reloadData()
    }

    func selectAllVisibleRows() {
        guard allowsMultipleSelection else {
            return
        }

        searchEngine.selectAll(rows: rows)
        updateStatus(context: "multi-select")
        tableView.reloadData()
    }

    func deselectAllRows() {
        guard allowsMultipleSelection else {
            return
        }

        searchEngine.deselectAll()
        updateStatus(context: "multi-select")
        tableView.reloadData()
    }

    func togglePreviewVisibility() -> String {
        guard allowsPreviewToggle else {
            return previewStateMessage
        }

        setPreviewPaneVisible(!isPreviewPaneVisible, updateStatus: true)
        return previewStateMessage
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("ResultCell")
        let textField: NSTextField

        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField {
            textField = reused
        } else {
            textField = NSTextField(labelWithString: "")
            textField.identifier = identifier
            textField.lineBreakMode = .byTruncatingMiddle
            textField.font = resultFont
        }

        guard row >= 0, row < rows.count else {
            textField.stringValue = ""
            return textField
        }

        let prefix = rowPrefix(forVisibleRow: row)
        textField.attributedStringValue = attributedDisplayText(for: rows[row], prefix: prefix)
        return textField
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let identifier = NSUserInterfaceItemIdentifier("ResultRow")
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? PaletteResultRowView {
            return reused
        }

        let rowView = PaletteResultRowView()
        rowView.identifier = identifier
        rowView.selectionHighlightStyle = .regular
        return rowView
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if pointerSymbol != nil {
            tableView.reloadData()
        }
        notifyActiveRowChanged()
    }

    private func acceptedRows() -> [PaletteRow] {
        let rowIndex = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
        let fallback = rows[min(rowIndex, rows.count - 1)]
        if allowsMultipleSelection {
            return searchEngine.acceptedRows(fallback: fallback)
        }
        return [fallback]
    }

    private func activeRow() -> PaletteRow? {
        guard !rows.isEmpty else {
            return nil
        }

        let rowIndex = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
        return rows[min(rowIndex, rows.count - 1)]
    }

    private func notifyActiveRowChanged() {
        guard let activeRowChangeHandler else {
            return
        }

        let row = activeRow()
        let sourceIndex = row?.sourceIndex
        guard sourceIndex != lastNotifiedSourceIndex else {
            return
        }

        lastNotifiedSourceIndex = sourceIndex
        activeRowChangeHandler(row)
    }

    private func updateStatus(context: String) {
        let selectedCount = allowsMultipleSelection ? searchEngine.selectedCount : 0
        let mode = allowsMultipleSelection ? "multi" : "single"
        if infoStyle == "inline" {
            statusLabel.stringValue = "\(rows.count)/\(allRows.count) rows | \(selectedCount) selected | \(mode) | \(context)"
        } else {
            statusLabel.stringValue = "\(selectedCount) selected | \(rows.count)/\(allRows.count) rows | \(mode) | \(context)"
        }
    }

    private func configureChrome(title: String, display: DisplayConfig) {
        let prompt = display.prompt?.isEmpty == false ? display.prompt! : "\(title)>"
        promptLabel.stringValue = prompt
        let header = display.header ?? ""
        headerLabel.stringValue = header
        headerLabel.isHidden = header.isEmpty
        pointerSymbol = display.pointer?.isEmpty == false ? display.pointer : nil
        markerSymbol = display.marker?.isEmpty == false ? display.marker : nil
        infoStyle = display.info
    }

    private func updateRows(for query: String) {
        guard !query.isEmpty else {
            rows = allRows
            matchRangesBySourceIndex = [:]
            return
        }

        rows = searchEngine.searchRows(query: query, includeRanges: false)
        matchRangesBySourceIndex = [:]
    }

    private func rowPrefix(forVisibleRow rowIndex: Int) -> String {
        let pointerPrefix: String
        if let pointerSymbol {
            let isActive = rowIndex == tableView.selectedRow
            pointerPrefix = (isActive ? pointerSymbol : blankSymbol(for: pointerSymbol)) + " "
        } else {
            pointerPrefix = ""
        }

        guard allowsMultipleSelection else {
            return pointerPrefix
        }

        let selected = searchEngine.isSelected(sourceIndex: rows[rowIndex].sourceIndex)
        if let markerSymbol {
            return pointerPrefix + (selected ? markerSymbol : blankSymbol(for: markerSymbol)) + " "
        }

        return pointerPrefix + (selected ? "[x] " : "[ ] ")
    }

    private func blankSymbol(for symbol: String) -> String {
        String(repeating: " ", count: max(1, symbol.count))
    }

    private func attributedDisplayText(for row: PaletteRow, prefix: String) -> NSAttributedString {
        let output = prefix + row.display
        let attributed = NSMutableAttributedString(
            string: output,
            attributes: [
                .font: resultFont,
                .foregroundColor: NSColor.labelColor
            ]
        )

        applyAnsiStyles(
            to: attributed,
            spans: row.ansiStyleSpans,
            in: row.display,
            prefixUTF16Length: prefix.utf16.count,
            baseFont: resultFont,
            boldFont: resultHighlightFont
        )

        let ranges = matchRanges(for: row)
        guard !ranges.isEmpty else {
            return attributed
        }

        let displayRanges = RowFormatting.displayRanges(for: ranges, row: row)
        guard !displayRanges.isEmpty else {
            return attributed
        }

        let markerLength = prefix.utf16.count
        for range in displayRanges {
            guard let nsRange = nsRange(for: range, in: row.display, prefixUTF16Length: markerLength) else {
                continue
            }
            attributed.addAttributes(
                [
                    .font: resultHighlightFont,
                    .foregroundColor: NSColor.controlAccentColor
                ],
                range: nsRange
            )
        }

        return attributed
    }

    private func matchRanges(for row: PaletteRow) -> [FuzzyMatchRange] {
        if let cached = matchRangesBySourceIndex[row.sourceIndex] {
            return cached
        }

        let query = queryField.stringValue
        guard !query.isEmpty else {
            return []
        }

        let ranges = searchEngine.matchRanges(query: query, sourceIndex: row.sourceIndex)
        matchRangesBySourceIndex[row.sourceIndex] = ranges
        return ranges
    }

    private func attributedPreviewText(_ parsed: AnsiParsedText) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            string: parsed.text,
            attributes: [
                .font: previewTextView.font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ]
        )
        applyAnsiStyles(
            to: attributed,
            spans: parsed.spans,
            in: parsed.text,
            prefixUTF16Length: 0,
            baseFont: previewTextView.font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            boldFont: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        )
        return attributed
    }

    private func applyAnsiStyles(
        to attributed: NSMutableAttributedString,
        spans: [AnsiStyleSpan],
        in text: String,
        prefixUTF16Length: Int,
        baseFont: NSFont,
        boldFont: NSFont
    ) {
        for span in spans {
            guard let nsRange = nsRange(
                for: FuzzyMatchRange(start: span.start, length: span.length),
                in: text,
                prefixUTF16Length: prefixUTF16Length
            ) else {
                continue
            }

            var attributes: [NSAttributedString.Key: Any] = [:]
            var foregroundColor = ansiForegroundColor(for: span)
            if span.dim {
                foregroundColor = (foregroundColor ?? NSColor.labelColor).withAlphaComponent(0.65)
            }
            if let foregroundColor {
                attributes[.foregroundColor] = foregroundColor
            }
            if let backgroundColor = ansiBackgroundColor(for: span) {
                attributes[.backgroundColor] = backgroundColor.withAlphaComponent(0.28)
            }
            if span.bold || span.italic {
                attributes[.font] = ansiFont(baseFont: baseFont, boldFont: boldFont, bold: span.bold, italic: span.italic)
            }
            if span.underline {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            if span.strikethrough {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            attributed.addAttributes(attributes, range: nsRange)
        }
    }

    private func ansiForegroundColor(for span: AnsiStyleSpan) -> NSColor? {
        if let rgb = span.foregroundRGB {
            return nsColor(for: rgb)
        }
        if let foreground = span.foreground {
            return nsColor(for: foreground)
        }
        return nil
    }

    private func ansiBackgroundColor(for span: AnsiStyleSpan) -> NSColor? {
        if let rgb = span.backgroundRGB {
            return nsColor(for: rgb)
        }
        if let background = span.background {
            return nsColor(for: background)
        }
        return nil
    }

    private func ansiFont(baseFont: NSFont, boldFont: NSFont, bold: Bool, italic: Bool) -> NSFont {
        let font = bold ? boldFont : baseFont
        guard italic else {
            return font
        }
        return NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }

    private func nsColor(for color: AnsiColor) -> NSColor {
        switch color {
        case .black:
            return .tertiaryLabelColor
        case .red:
            return .systemRed
        case .green:
            return .systemGreen
        case .yellow:
            return .systemYellow
        case .blue:
            return .systemBlue
        case .magenta:
            return .systemPurple
        case .cyan:
            return .systemTeal
        case .white:
            return .labelColor
        case .brightBlack:
            return .secondaryLabelColor
        case .brightRed:
            return .systemRed
        case .brightGreen:
            return .systemGreen
        case .brightYellow:
            return .systemYellow
        case .brightBlue:
            return .systemBlue
        case .brightMagenta:
            return .systemPink
        case .brightCyan:
            return .systemCyan
        case .brightWhite:
            return .textColor
        }
    }

    private func nsColor(for color: AnsiRGBColor) -> NSColor {
        NSColor(
            red: CGFloat(color.red) / 255.0,
            green: CGFloat(color.green) / 255.0,
            blue: CGFloat(color.blue) / 255.0,
            alpha: 1.0
        )
    }

    private func nsRange(
        for range: FuzzyMatchRange,
        in text: String,
        prefixUTF16Length: Int
    ) -> NSRange? {
        guard range.start >= 0, range.length > 0 else {
            return nil
        }

        let endOffset = range.start + range.length
        guard endOffset <= text.utf8.count else {
            return nil
        }

        let utf8Start = text.utf8.index(text.utf8.startIndex, offsetBy: range.start)
        let utf8End = text.utf8.index(text.utf8.startIndex, offsetBy: endOffset)
        guard let stringStart = String.Index(utf8Start, within: text),
              let stringEnd = String.Index(utf8End, within: text),
              let utf16Start = stringStart.samePosition(in: text.utf16),
              let utf16End = stringEnd.samePosition(in: text.utf16) else {
            return nil
        }

        let location = text.utf16.distance(from: text.utf16.startIndex, to: utf16Start)
        let length = text.utf16.distance(from: utf16Start, to: utf16End)
        return NSRange(location: prefixUTF16Length + location, length: length)
    }

    private func selectFirstVisibleRow() {
        guard !rows.isEmpty else {
            tableView.deselectAll(nil)
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else {
            return
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else {
                return event
            }

            return self.handlePaletteKey(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else {
            return
        }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }

    private func handleMultiSelectShortcut(_ event: NSEvent) -> Bool {
        handleMultiSelectShortcut(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifierFlags: event.modifierFlags
        )
    }

    private func handleMultiSelectShortcut(
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.control) else {
            return false
        }

        switch charactersIgnoringModifiers?.lowercased() {
        case "a":
            selectAllVisibleRows()
            return true
        case "d":
            deselectAllRows()
            return true
        default:
            return false
        }
    }

    private func handlePreviewShortcut(_ event: NSEvent) -> Bool {
        handlePreviewShortcut(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifierFlags: event.modifierFlags
        )
    }

    private func handlePreviewShortcut(
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.control),
              charactersIgnoringModifiers == "/",
              allowsPreviewToggle else {
            return false
        }

        _ = togglePreviewVisibility()
        return true
    }

    private func handlePaletteKey(_ event: NSEvent) -> Bool {
        handlePaletteKey(
            keyCode: event.keyCode,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifierFlags: event.modifierFlags
        )
    }

    private func handlePaletteKey(
        keyCode: UInt16,
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        switch keyCode {
        case 36:
            acceptCurrentSelection()
            return true
        case 48:
            if allowsMultipleSelection {
                toggleCurrentSelection()
            } else {
                acceptCurrentSelection()
            }
            return true
        case 53:
            cancelActivePicker()
            return true
        case 49 where allowsMultipleSelection:
            toggleCurrentSelection()
            return true
        case 125:
            selectNextRow()
            return true
        case 126:
            selectPreviousRow()
            return true
        default:
            if handlePreviewShortcut(
                charactersIgnoringModifiers: charactersIgnoringModifiers,
                modifierFlags: modifierFlags
            ) {
                return true
            }
            if allowsMultipleSelection,
               handleMultiSelectShortcut(
                   charactersIgnoringModifiers: charactersIgnoringModifiers,
                   modifierFlags: modifierFlags
               ) {
                return true
            }
            return false
        }
    }

    private func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000
    }

    private var previewStateMessage: String {
        isPreviewPaneVisible ? "preview:visible" : "preview:hidden"
    }

    private var isQueryFieldFocused: Bool {
        guard let firstResponder = panel.firstResponder else {
            return false
        }
        if firstResponder === queryField {
            return true
        }
        if let editor = queryField.currentEditor(), firstResponder === editor {
            return true
        }
        return false
    }

    private func setPreviewPaneVisible(_ visible: Bool, updateStatus shouldUpdateStatus: Bool) {
        isPreviewPaneVisible = visible
        previewScrollView.isHidden = !visible
        if visible {
            layoutPreviewPaneIfNeeded()
        }
        splitView.adjustSubviews()
        if shouldUpdateStatus {
            updateStatus(context: "preview")
        }
    }

    private func configurePreviewLayout(_ layout: PreviewWindowLayout) {
        previewLayout = layout
        splitView.isVertical = layout.isVerticalSplit
        setPreviewWrapping(layout.wrap)

        let orderedSubviews: [NSView]
        switch layout.position {
        case .left, .up:
            orderedSubviews = [previewScrollView, resultsScrollView]
        case .right, .down:
            orderedSubviews = [resultsScrollView, previewScrollView]
        }

        if splitView.arrangedSubviews != orderedSubviews {
            for subview in splitView.arrangedSubviews {
                subview.removeFromSuperview()
            }
            for subview in orderedSubviews {
                splitView.addArrangedSubview(subview)
            }
        }

        layoutPreviewPaneIfNeeded()
    }

    private func setPreviewWrapping(_ wraps: Bool) {
        previewScrollView.hasHorizontalScroller = !wraps
        previewTextView.isHorizontallyResizable = !wraps
        previewTextView.autoresizingMask = wraps ? [.width] : []
        previewTextView.textContainer?.widthTracksTextView = wraps
        if wraps {
            previewTextView.textContainer?.containerSize = NSSize(
                width: previewScrollView.contentSize.width,
                height: CGFloat.greatestFiniteMagnitude
            )
        } else {
            previewTextView.textContainer?.containerSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            previewTextView.maxSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
    }

    private func applyPreviewScrollTarget(_ target: PreviewScrollTarget?) {
        previewTextView.layoutSubtreeIfNeeded()
        if let textContainer = previewTextView.textContainer {
            previewTextView.layoutManager?.ensureLayout(for: textContainer)
        }

        guard !previewTextView.string.isEmpty,
              let target,
              let location = previewCharacterLocation(forLine: targetLine(for: target)),
              let layoutManager = previewTextView.layoutManager else {
            scrollPreview(toY: 0)
            return
        }

        let glyphIndex = layoutManager.glyphIndexForCharacter(at: location)
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        scrollPreview(toY: lineRect.minY)
    }

    private func targetLine(for target: PreviewScrollTarget) -> Int {
        guard target.centerInPreview else {
            return target.line
        }
        let lineHeight = max(1, previewTextView.font?.boundingRectForFont.height ?? 14)
        let visibleLines = max(1, Int(previewScrollView.contentSize.height / lineHeight))
        return max(1, target.line - visibleLines / 2)
    }

    private func previewCharacterLocation(forLine line: Int) -> Int? {
        guard line > 0 else {
            return nil
        }
        if line == 1 {
            return 0
        }

        let text = previewTextView.string
        var currentLine = 1
        var index = text.startIndex
        while index < text.endIndex {
            if text[index].isNewline {
                currentLine += 1
                if currentLine == line {
                    let nextIndex = text.index(after: index)
                    guard let utf16Index = nextIndex.samePosition(in: text.utf16) else {
                        return nil
                    }
                    return text.utf16.distance(from: text.utf16.startIndex, to: utf16Index)
                }
            }
            index = text.index(after: index)
        }

        return max(0, text.utf16.count - 1)
    }

    private func scrollPreview(toY requestedY: CGFloat) {
        let documentHeight = previewTextView.bounds.height
        let visibleHeight = previewScrollView.contentSize.height
        let maximumY = max(0, documentHeight - visibleHeight)
        let y = min(max(0, requestedY), maximumY)
        previewScrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
        previewScrollView.reflectScrolledClipView(previewScrollView.contentView)
    }

    private func renderedPixelMetrics(for view: NSView?) -> RenderedPixelMetrics {
        guard let view else {
            return RenderedPixelMetrics()
        }
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            return RenderedPixelMetrics()
        }

        bitmap.size = bounds.size
        view.cacheDisplay(in: bounds, to: bitmap)

        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        guard width > 0, height > 0 else {
            return RenderedPixelMetrics()
        }

        let step = max(1, min(width, height) / 80)
        var sampledPixels = 0
        var nonBackgroundPixels = 0
        var buckets = Set<Int>()
        var background: RGBSample?
        var luminanceValues: [Double] = []

        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                guard let color = bitmap.colorAt(x: x, y: y),
                      let sample = rgbSample(for: color) else {
                    continue
                }
                if background == nil {
                    background = sample
                }
                sampledPixels += 1
                buckets.insert(colorBucket(for: sample))
                luminanceValues.append(luminance(for: sample))
                if let background, colorDistance(sample, background) > 0.08 {
                    nonBackgroundPixels += 1
                }
            }
        }

        let ratio = sampledPixels == 0 ? 0 : Double(nonBackgroundPixels) / Double(sampledPixels)
        let averageLuminance = luminanceValues.isEmpty ? 0 : luminanceValues.reduce(0, +) / Double(luminanceValues.count)
        let luminanceVariance = luminanceValues.isEmpty
            ? 0
            : luminanceValues.reduce(0) { total, value in
                let delta = value - averageLuminance
                return total + delta * delta
            } / Double(luminanceValues.count)
        return RenderedPixelMetrics(
            width: width,
            height: height,
            sampledPixels: sampledPixels,
            distinctColorBuckets: buckets.count,
            nonBackgroundSampleRatio: ratio,
            averageLuminance: averageLuminance,
            luminanceStandardDeviation: sqrt(luminanceVariance)
        )
    }

    private func rgbSample(for color: NSColor) -> RGBSample? {
        guard let rgb = color.usingColorSpace(NSColorSpace.deviceRGB) else {
            return nil
        }
        return RGBSample(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
    }

    private func colorBucket(for sample: RGBSample) -> Int {
        let red = min(15, max(0, Int((sample.red * 15).rounded())))
        let green = min(15, max(0, Int((sample.green * 15).rounded())))
        let blue = min(15, max(0, Int((sample.blue * 15).rounded())))
        return red << 8 | green << 4 | blue
    }

    private func colorDistance(_ lhs: RGBSample, _ rhs: RGBSample) -> Double {
        (abs(lhs.red - rhs.red) + abs(lhs.green - rhs.green) + abs(lhs.blue - rhs.blue)) / 3
    }

    private func luminance(for sample: RGBSample) -> Double {
        0.2126 * sample.red + 0.7152 * sample.green + 0.0722 * sample.blue
    }

    private func layoutPreviewPaneIfNeeded() {
        guard isPreviewPaneVisible,
              splitView.arrangedSubviews.count == 2 else {
            return
        }

        splitView.layoutSubtreeIfNeeded()
        let total = previewLayout.isVerticalSplit ? splitView.bounds.width : splitView.bounds.height
        guard total > 0 else {
            return
        }

        let minimumPaneSize: CGFloat = min(previewLayout.isVerticalSplit ? 220 : 150, total / 3)
        let previewSize = max(
            minimumPaneSize,
            min(total - minimumPaneSize, total * previewLayout.sizeFraction)
        )

        let previewIsFirst = previewLayout.position == .left || previewLayout.position == .up
        let dividerPosition = previewIsFirst ? previewSize : total - previewSize
        splitView.setPosition(dividerPosition, ofDividerAt: 0)
        splitView.adjustSubviews()
    }

    private func layoutViolationCount() -> Int {
        var violations = 0
        if panel.frame.width < 800 || panel.frame.height < 480 {
            violations += 1
        }
        if promptLabel.frame.maxX > queryField.frame.minX {
            violations += 1
        }
        if statusLabel.frame.maxY > splitView.frame.minY {
            violations += 1
        }
        if splitView.frame.maxY > headerLabel.frame.minY {
            violations += 1
        }
        if !headerLabel.isHidden, headerLabel.frame.maxY > queryField.frame.minY {
            violations += 1
        }
        if resultsScrollView.frame.width < 100 || resultsScrollView.frame.height < 100 {
            violations += 1
        }
        if isPreviewPaneVisible && (previewScrollView.frame.width < 100 || previewScrollView.frame.height < 100) {
            violations += 1
        }
        return violations
    }

    private func buildContentView() -> NSView {
        let root = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 920, height: 560))
        root.material = .hudWindow
        root.blendingMode = .behindWindow
        root.state = .active
        root.wantsLayer = true
        root.layer?.cornerRadius = PaletteVisualStyle.contentCornerRadius
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = true
        root.layer?.borderWidth = PaletteVisualStyle.paneBorderWidth
        root.layer?.borderColor = PaletteVisualStyle.rootBorderColor(for: root)
        root.autoresizingMask = [.width, .height]

        let content = NSView(frame: root.bounds)
        content.translatesAutoresizingMaskIntoConstraints = false
        content.wantsLayer = true
        content.layer?.backgroundColor = PaletteVisualStyle.contentBackgroundColor(for: content)
        root.addSubview(content)

        promptLabel.translatesAutoresizingMaskIntoConstraints = false
        promptLabel.font = NSFont.monospacedSystemFont(ofSize: 15, weight: .bold)
        promptLabel.textColor = .controlAccentColor
        promptLabel.lineBreakMode = .byTruncatingMiddle
        promptLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        promptLabel.setContentHuggingPriority(.required, for: .horizontal)

        queryField.translatesAutoresizingMaskIntoConstraints = false
        queryField.placeholderString = "fzf-palette"
        queryField.font = NSFont.systemFont(ofSize: 19, weight: .medium)
        queryField.controlSize = .large
        queryField.cell?.controlSize = .large
        queryField.focusRingType = .none
        queryField.delegate = self

        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        headerLabel.textColor = .secondaryLabelColor
        headerLabel.lineBreakMode = .byTruncatingTail
        headerLabel.isHidden = true

        accentLine.translatesAutoresizingMaskIntoConstraints = false
        accentLine.wantsLayer = true
        accentLine.layer?.backgroundColor = PaletteVisualStyle.cgColor(.controlAccentColor, alpha: 0.30)
        accentLine.layer?.cornerRadius = 0.5

        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Result"))
        tableColumn.title = "Result"
        tableColumn.resizingMask = .autoresizingMask
        tableView.headerView = nil
        tableView.rowHeight = 30
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.selectionHighlightStyle = .regular
        tableView.backgroundColor = .clear
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.addTableColumn(tableColumn)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.reloadData()

        resultsScrollView.translatesAutoresizingMaskIntoConstraints = false
        resultsScrollView.hasVerticalScroller = true
        resultsScrollView.drawsBackground = false
        resultsScrollView.contentInsets = NSEdgeInsets(top: 7, left: 8, bottom: 7, right: 8)
        stylePane(resultsScrollView)
        resultsScrollView.documentView = tableView

        previewTextView.isEditable = false
        previewTextView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        previewTextView.drawsBackground = false
        previewTextView.textContainerInset = NSSize(width: 12, height: 12)
        previewTextView.string = "Preview pane ready"
        previewScrollView.translatesAutoresizingMaskIntoConstraints = false
        previewScrollView.hasVerticalScroller = true
        previewScrollView.drawsBackground = false
        previewScrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        stylePane(previewScrollView)
        previewScrollView.documentView = previewTextView

        splitView.addArrangedSubview(resultsScrollView)
        splitView.addArrangedSubview(previewScrollView)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor

        content.addSubview(promptLabel)
        content.addSubview(queryField)
        content.addSubview(headerLabel)
        content.addSubview(accentLine)
        content.addSubview(splitView)
        content.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: root.topAnchor),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            promptLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            promptLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            promptLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 220),
            promptLabel.centerYAnchor.constraint(equalTo: queryField.centerYAnchor),

            queryField.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            queryField.leadingAnchor.constraint(equalTo: promptLabel.trailingAnchor, constant: 12),
            queryField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            queryField.heightAnchor.constraint(equalToConstant: 36),

            headerLabel.topAnchor.constraint(equalTo: queryField.bottomAnchor, constant: 9),
            headerLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            headerLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            headerLabel.heightAnchor.constraint(equalToConstant: 16),

            accentLine.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 10),
            accentLine.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            accentLine.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            accentLine.heightAnchor.constraint(equalToConstant: 1),

            splitView.topAnchor.constraint(equalTo: accentLine.bottomAnchor, constant: 13),
            splitView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            splitView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            splitView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -12),

            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            statusLabel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            statusLabel.heightAnchor.constraint(equalToConstant: 18)
        ])

        return root
    }

    private func stylePane(_ scrollView: NSScrollView) {
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = PaletteVisualStyle.paneCornerRadius
        scrollView.layer?.cornerCurve = .continuous
        scrollView.layer?.masksToBounds = true
        scrollView.layer?.borderWidth = PaletteVisualStyle.paneBorderWidth
        scrollView.layer?.borderColor = PaletteVisualStyle.paneBorderColor(for: scrollView)
        scrollView.layer?.backgroundColor = PaletteVisualStyle.paneBackgroundColor(for: scrollView)
        scrollView.contentView.wantsLayer = true
        scrollView.contentView.layer?.backgroundColor = PaletteVisualStyle.cgColor(.clear, alpha: 0)
    }
}
