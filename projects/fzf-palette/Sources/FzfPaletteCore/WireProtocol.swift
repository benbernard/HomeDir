import Foundation

public struct PaletteClientRequest: Codable, Equatable {
    public var type: RequestType
    public var id: String?
    public var request: PickerRequest?
    public var bench: BenchRequest?
    public var query: String?
    public var settings: PaletteSettings?

    public init(
        type: RequestType,
        id: String? = nil,
        request: PickerRequest? = nil,
        bench: BenchRequest? = nil,
        query: String? = nil,
        settings: PaletteSettings? = nil
    ) {
        self.type = type
        self.id = id
        self.request = request
        self.bench = bench
        self.query = query
        self.settings = settings
    }
}

public enum RequestType: String, Codable, Equatable {
    case status
    case open
    case cancel
    case envReload = "env.reload"
    case bench
    case settingsGet = "settings.get"
    case settingsSet = "settings.set"
    case settingsClear = "settings.clear"
    case settingsShow = "settings.show"
    case settingsClose = "settings.close"
    case testAccept = "test.accept"
    case testCancel = "test.cancel"
    case testHotkey = "test.hotkey"
    case testCarbonHotkey = "test.carbonHotkey"
    case testPhysicalHotkey = "test.physicalHotkey"
    case testPhysicalType = "test.physicalType"
    case testPhysicalKey = "test.physicalKey"
    case testToggleSelection = "test.toggleSelection"
    case testSelectAll = "test.selectAll"
    case testDeselectAll = "test.deselectAll"
    case testSetQuery = "test.setQuery"
    case testKey = "test.key"
    case testMoveDown = "test.moveDown"
    case testMoveUp = "test.moveUp"
    case testTogglePreview = "test.togglePreview"
    case testVisualSnapshot = "test.visualSnapshot"
}

public struct PickerRequest: Codable, Equatable {
    public var id: String
    public var profile: String
    public var cwd: String
    public var query: String
    public var source: PickerSource
    public var fzfOptions: [String]
    public var display: DisplayConfig
    public var preview: PreviewConfig?
    public var env: [String: String]
    public var input: String?
    public var result: ResultConfig
    public var resultMode: ResultMode
    public var timeoutMs: Int

    public init(
        id: String = UUID().uuidString,
        profile: String = "default",
        cwd: String = FileManager.default.currentDirectoryPath,
        query: String = "",
        source: PickerSource = .profile,
        fzfOptions: [String] = [],
        display: DisplayConfig = DisplayConfig(),
        preview: PreviewConfig? = nil,
        env: [String: String] = [:],
        input: String? = nil,
        result: ResultConfig = ResultConfig(),
        resultMode: ResultMode = .return,
        timeoutMs: Int = 0
    ) {
        self.id = id
        self.profile = profile
        self.cwd = cwd
        self.query = query
        self.source = source
        self.fzfOptions = fzfOptions
        self.display = display
        self.preview = preview
        self.env = env
        self.input = input
        self.result = result
        self.resultMode = resultMode
        self.timeoutMs = timeoutMs
    }
}

public struct PaletteResponse: Codable, Equatable {
    public var type: ResponseType
    public var id: String?
    public var status: ResultStatus?
    public var text: String?
    public var items: [String]?
    public var code: String?
    public var message: String?
    public var app: AppStatus?
    public var bench: BenchReport?
    public var snapshot: PanelVisualSnapshot?
    public var settings: PaletteSettings?

    public init(
        type: ResponseType,
        id: String? = nil,
        status: ResultStatus? = nil,
        text: String? = nil,
        items: [String]? = nil,
        code: String? = nil,
        message: String? = nil,
        app: AppStatus? = nil,
        bench: BenchReport? = nil,
        snapshot: PanelVisualSnapshot? = nil,
        settings: PaletteSettings? = nil
    ) {
        self.type = type
        self.id = id
        self.status = status
        self.text = text
        self.items = items
        self.code = code
        self.message = message
        self.app = app
        self.bench = bench
        self.snapshot = snapshot
        self.settings = settings
    }
}

public enum ResponseType: String, Codable, Equatable {
    case result
    case error
    case status
}

public enum ResultStatus: String, Codable, Equatable {
    case selected
    case cancelled
    case noMatch = "no_match"
    case error
}

public struct AppStatus: Codable, Equatable {
    public var running: Bool
    public var pid: Int32
    public var socketPath: String
    public var uptimeMs: UInt64
    public var version: String
    public var logDirectory: String
    public var activePicker: Bool
    public var panelVisible: Bool
    public var visibleRows: Int
    public var previewVisible: Bool
    public var prompt: String?
    public var header: String?
    public var pointer: String?
    public var marker: String?
    public var info: String?
    public var hotkey: String?
    public var hotkeyRegistered: Bool
    public var hotkeyError: String?
    public var hotkeys: [ProfileHotKeyStatus]
    public var settingsHotkey: String?
    public var settingsProfile: String?
    public var settingsVisible: Bool
    public var programContext: ProgramContext?
    public var lastCompletionReason: String?

    public init(
        running: Bool,
        pid: Int32,
        socketPath: String,
        uptimeMs: UInt64,
        version: String,
        logDirectory: String,
        activePicker: Bool = false,
        panelVisible: Bool = false,
        visibleRows: Int = 0,
        previewVisible: Bool = false,
        prompt: String? = nil,
        header: String? = nil,
        pointer: String? = nil,
        marker: String? = nil,
        info: String? = nil,
        hotkey: String? = nil,
        hotkeyRegistered: Bool = false,
        hotkeyError: String? = nil,
        hotkeys: [ProfileHotKeyStatus] = [],
        settingsHotkey: String? = nil,
        settingsProfile: String? = nil,
        settingsVisible: Bool = false,
        programContext: ProgramContext? = nil,
        lastCompletionReason: String? = nil
    ) {
        self.running = running
        self.pid = pid
        self.socketPath = socketPath
        self.uptimeMs = uptimeMs
        self.version = version
        self.logDirectory = logDirectory
        self.activePicker = activePicker
        self.panelVisible = panelVisible
        self.visibleRows = visibleRows
        self.previewVisible = previewVisible
        self.prompt = prompt
        self.header = header
        self.pointer = pointer
        self.marker = marker
        self.info = info
        self.hotkey = hotkey
        self.hotkeyRegistered = hotkeyRegistered
        self.hotkeyError = hotkeyError
        self.hotkeys = hotkeys
        self.settingsHotkey = settingsHotkey
        self.settingsProfile = settingsProfile
        self.settingsVisible = settingsVisible
        self.programContext = programContext
        self.lastCompletionReason = lastCompletionReason
    }
}

public struct PaletteSettings: Codable, Equatable {
    public var hotkey: String?
    public var profile: String

    public init(hotkey: String? = nil, profile: String = "default") {
        self.hotkey = hotkey
        self.profile = profile
    }
}

public struct ProfileHotKeyStatus: Codable, Equatable {
    public var profile: String
    public var hotkey: String
    public var registered: Bool
    public var error: String?

    public init(profile: String, hotkey: String, registered: Bool, error: String? = nil) {
        self.profile = profile
        self.hotkey = hotkey
        self.registered = registered
        self.error = error
    }
}

public struct BenchRequest: Codable, Equatable {
    public var name: String
    public var runs: Int
    public var warmup: Int

    public init(name: String, runs: Int = 100, warmup: Int = 10) {
        self.name = name
        self.runs = runs
        self.warmup = warmup
    }
}

public struct BenchReport: Codable, Equatable {
    public var name: String
    public var runs: Int
    public var warmup: Int
    public var budgets: [String: Double]
    public var metrics: [String: MetricSummary]
    public var failures: [String]

    public init(
        name: String,
        runs: Int,
        warmup: Int,
        budgets: [String: Double],
        metrics: [String: MetricSummary],
        failures: [String] = []
    ) {
        self.name = name
        self.runs = runs
        self.warmup = warmup
        self.budgets = budgets
        self.metrics = metrics
        self.failures = failures
    }
}

public struct PanelVisualSnapshot: Codable, Equatable {
    public var panelVisible: Bool
    public var queryFieldFocused: Bool
    public var queryFieldActionBound: Bool
    public var windowNumber: Int
    public var captureX: Int
    public var captureY: Int
    public var captureWidth: Int
    public var captureHeight: Int
    public var width: Double
    public var height: Double
    public var renderedWidth: Int
    public var renderedHeight: Int
    public var sampledPixels: Int
    public var distinctColorBuckets: Int
    public var nonBackgroundSampleRatio: Double
    public var averageLuminance: Double
    public var luminanceStandardDeviation: Double
    public var effectiveAppearanceName: String
    public var usesVibrantBackground: Bool
    public var contentCornerRadius: Double
    public var resultsCornerRadius: Double
    public var previewCornerRadius: Double
    public var usesCustomSelectionStyle: Bool
    public var visibleRows: Int
    public var selectedRowIndex: Int
    public var activeRowText: String
    public var previewVisible: Bool
    public var previewWidth: Double
    public var previewHeight: Double
    public var resultsWidth: Double
    public var resultsHeight: Double
    public var previewPosition: String
    public var previewWrap: Bool
    public var previewCharacterCount: Int
    public var previewAnsiSpanCount: Int
    public var previewAnsiRGBSpanCount: Int
    public var previewAnsiBackgroundSpanCount: Int
    public var previewAnsiTextStyleSpanCount: Int
    public var previewContainsEscapeSequences: Bool
    public var previewTextSample: String
    public var previewScrollOffsetY: Double
    public var layoutViolationCount: Int

    public init(
        panelVisible: Bool,
        queryFieldFocused: Bool,
        queryFieldActionBound: Bool = false,
        windowNumber: Int = 0,
        captureX: Int = 0,
        captureY: Int = 0,
        captureWidth: Int = 0,
        captureHeight: Int = 0,
        width: Double,
        height: Double,
        renderedWidth: Int,
        renderedHeight: Int,
        sampledPixels: Int,
        distinctColorBuckets: Int,
        nonBackgroundSampleRatio: Double,
        averageLuminance: Double = 0,
        luminanceStandardDeviation: Double = 0,
        effectiveAppearanceName: String = "",
        usesVibrantBackground: Bool = false,
        contentCornerRadius: Double = 0,
        resultsCornerRadius: Double = 0,
        previewCornerRadius: Double = 0,
        usesCustomSelectionStyle: Bool = false,
        visibleRows: Int,
        selectedRowIndex: Int = -1,
        activeRowText: String = "",
        previewVisible: Bool,
        previewWidth: Double,
        previewHeight: Double = 0,
        resultsWidth: Double,
        resultsHeight: Double = 0,
        previewPosition: String = "right",
        previewWrap: Bool = false,
        previewCharacterCount: Int,
        previewAnsiSpanCount: Int = 0,
        previewAnsiRGBSpanCount: Int = 0,
        previewAnsiBackgroundSpanCount: Int = 0,
        previewAnsiTextStyleSpanCount: Int = 0,
        previewContainsEscapeSequences: Bool = false,
        previewTextSample: String = "",
        previewScrollOffsetY: Double = 0,
        layoutViolationCount: Int
    ) {
        self.panelVisible = panelVisible
        self.queryFieldFocused = queryFieldFocused
        self.queryFieldActionBound = queryFieldActionBound
        self.windowNumber = windowNumber
        self.captureX = captureX
        self.captureY = captureY
        self.captureWidth = captureWidth
        self.captureHeight = captureHeight
        self.width = width
        self.height = height
        self.renderedWidth = renderedWidth
        self.renderedHeight = renderedHeight
        self.sampledPixels = sampledPixels
        self.distinctColorBuckets = distinctColorBuckets
        self.nonBackgroundSampleRatio = nonBackgroundSampleRatio
        self.averageLuminance = averageLuminance
        self.luminanceStandardDeviation = luminanceStandardDeviation
        self.effectiveAppearanceName = effectiveAppearanceName
        self.usesVibrantBackground = usesVibrantBackground
        self.contentCornerRadius = contentCornerRadius
        self.resultsCornerRadius = resultsCornerRadius
        self.previewCornerRadius = previewCornerRadius
        self.usesCustomSelectionStyle = usesCustomSelectionStyle
        self.visibleRows = visibleRows
        self.selectedRowIndex = selectedRowIndex
        self.activeRowText = activeRowText
        self.previewVisible = previewVisible
        self.previewWidth = previewWidth
        self.previewHeight = previewHeight
        self.resultsWidth = resultsWidth
        self.resultsHeight = resultsHeight
        self.previewPosition = previewPosition
        self.previewWrap = previewWrap
        self.previewCharacterCount = previewCharacterCount
        self.previewAnsiSpanCount = previewAnsiSpanCount
        self.previewAnsiRGBSpanCount = previewAnsiRGBSpanCount
        self.previewAnsiBackgroundSpanCount = previewAnsiBackgroundSpanCount
        self.previewAnsiTextStyleSpanCount = previewAnsiTextStyleSpanCount
        self.previewContainsEscapeSequences = previewContainsEscapeSequences
        self.previewTextSample = previewTextSample
        self.previewScrollOffsetY = previewScrollOffsetY
        self.layoutViolationCount = layoutViolationCount
    }
}

public enum WireCoding {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    public static let decoder = JSONDecoder()

    public static func encodeLine<T: Encodable>(_ value: T) throws -> Data {
        var data = try encoder.encode(value)
        data.append(0x0A)
        return data
    }

    public static func decodeRequest(_ data: Data) throws -> PaletteClientRequest {
        try decoder.decode(PaletteClientRequest.self, from: data.trimmedNewline())
    }

    public static func decodeResponse(_ data: Data) throws -> PaletteResponse {
        try decoder.decode(PaletteResponse.self, from: data.trimmedNewline())
    }
}

private extension Data {
    func trimmedNewline() -> Data {
        var copy = self
        while copy.last == 0x0A || copy.last == 0x0D {
            copy.removeLast()
        }
        return copy
    }
}
