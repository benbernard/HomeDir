import Foundation
import FzfPaletteCore

enum CLIError: Error, CustomStringConvertible {
    case usage(String)
    case requestFailed(PaletteResponse)

    var description: String {
        switch self {
        case let .usage(message):
            return message
        case let .requestFailed(response):
            return response.message ?? response.code ?? response.status?.rawValue ?? "Request failed"
        }
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())

do {
    try run(arguments)
} catch {
    fputs("fzf-palette: \(error)\n", stderr)
    exit(1)
}

func run(_ arguments: [String]) throws {
    guard let command = arguments.first else {
        printHelp()
        return
    }

    let rest = Array(arguments.dropFirst())
    switch command {
    case "status":
        let json = rest.contains("--json")
        let response = try sendWithLaunch(.init(type: .status))
        try printStatus(response, json: json)
    case "env":
        guard rest.first == "reload" else {
            throw CLIError.usage("Usage: fzf-palette env reload")
        }
        let response = try sendWithLaunch(.init(type: .envReload))
        try printStatus(response, json: rest.contains("--json"))
    case "open":
        let request = try parseOpenRequest(rest)
        let response = try sendWithLaunch(.init(type: .open, id: request.id, request: request))
        try printResult(response)
    case "cancel":
        let response = try sendWithLaunch(.init(type: .cancel))
        try printCancel(response)
    case "bench":
        try runLocalBench(rest)
    case "settings":
        try runSettings(rest)
    case "context":
        try runContext(rest)
    case "test-control":
        try runTestControl(rest)
    case "help", "--help", "-h":
        printHelp()
    default:
        throw CLIError.usage("Unknown command: \(command)")
    }
}

func runSettings(_ arguments: [String]) throws {
    guard let action = arguments.first else {
        throw CLIError.usage(settingsUsage)
    }

    let json = arguments.contains("--json")
    let response: PaletteResponse
    switch action {
    case "get":
        response = try sendWithLaunch(.init(type: .settingsGet))
    case "set":
        let settings = try parseSettingsSet(Array(arguments.dropFirst()))
        response = try sendWithLaunch(.init(type: .settingsSet, settings: settings))
    case "clear":
        response = try sendWithLaunch(.init(type: .settingsClear))
    case "show":
        response = try sendWithLaunch(.init(type: .settingsShow))
    case "close":
        response = try sendWithLaunch(.init(type: .settingsClose))
    default:
        throw CLIError.usage(settingsUsage)
    }

    try printSettings(response, json: json)
}

func parseSettingsSet(_ arguments: [String]) throws -> PaletteSettings {
    var hotkey: String?
    var profile = "default"
    var index = 0
    while index < arguments.count {
        let arg = arguments[index]
        func requireValue() throws -> String {
            guard index + 1 < arguments.count else {
                throw CLIError.usage("Missing value for \(arg)")
            }
            index += 1
            return arguments[index]
        }

        switch arg {
        case "--hotkey":
            hotkey = try requireValue()
        case "--profile":
            profile = try requireValue()
        case "--json":
            break
        default:
            throw CLIError.usage("Unknown settings option: \(arg)")
        }
        index += 1
    }

    guard let hotkey, !hotkey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw CLIError.usage("Usage: fzf-palette settings set --hotkey value [--profile name]")
    }

    return PaletteSettings(hotkey: hotkey, profile: profile)
}

func printSettings(_ response: PaletteResponse, json: Bool) throws {
    if response.type == .error {
        throw CLIError.requestFailed(response)
    }

    guard let settings = response.settings else {
        throw CLIError.requestFailed(response)
    }

    if json {
        let data = try WireCoding.encoder.encode(response)
        print(String(decoding: data, as: UTF8.self))
        return
    }

    print("settings_hotkey: \(settings.hotkey ?? "")")
    print("settings_profile: \(settings.profile)")
}

let settingsUsage = "Usage: fzf-palette settings get|show|close|clear [--json] OR fzf-palette settings set --hotkey value [--profile name] [--json]"

func runContext(_ arguments: [String]) throws {
    guard let action = arguments.first else {
        throw CLIError.usage(contextUsage)
    }

    let json = arguments.contains("--json")
    switch action {
    case "set":
        let options = try parseContextOptions(Array(arguments.dropFirst()))
        let app = options.app
        let cwd = try ProgramContextBridge.normalizedExistingDirectory(options.cwd)
        let context = ProgramContext(
            cwd: cwd,
            provider: "\(app.rawValue)-bridge",
            appName: app.displayName,
            bundleIdentifier: app.defaultBundleIdentifier,
            detail: options.detail,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        let url = try ProgramContextBridge.writeContext(context, for: app)
        try printContext(context, path: url.path, json: json)
    case "get":
        let options = try parseContextOptions(Array(arguments.dropFirst()), requireCwd: false)
        do {
            let context = try ProgramContextBridge.loadContext(for: options.app)
            let url = ProgramContextBridge.contextFileURL(for: options.app)
            try printContext(context, path: url.path, json: json)
        } catch ProgramContextBridgeError.missingContextFile {
            throw CLIError.usage("No context is recorded for \(options.app.rawValue).")
        }
    case "clear":
        let options = try parseContextOptions(Array(arguments.dropFirst()), requireCwd: false)
        let url = try ProgramContextBridge.removeContext(for: options.app)
        if json {
            let data = try WireCoding.encoder.encode(ContextClearResponse(path: url.path, cleared: true))
            print(String(decoding: data, as: UTF8.self))
        } else {
            print("cleared: \(url.path)")
        }
    default:
        throw CLIError.usage(contextUsage)
    }
}

struct ContextClearResponse: Codable {
    var path: String
    var cleared: Bool
}

func parseContextOptions(
    _ arguments: [String],
    requireCwd: Bool = true
) throws -> (app: ProgramContextApp, cwd: String, detail: String?) {
    var app: ProgramContextApp?
    var cwd = FileManager.default.currentDirectoryPath
    var detail: String?

    var index = 0
    while index < arguments.count {
        let arg = arguments[index]
        func requireValue() throws -> String {
            guard index + 1 < arguments.count else {
                throw CLIError.usage("Missing value for \(arg)")
            }
            index += 1
            return arguments[index]
        }

        switch arg {
        case "--app":
            let rawApp = try requireValue()
            guard let parsed = ProgramContextBridge.app(named: rawApp) else {
                throw CLIError.usage("Unsupported context app: \(rawApp)")
            }
            app = parsed
        case "--cwd":
            cwd = try requireValue()
        case "--detail":
            detail = try requireValue()
        case "--json":
            break
        default:
            throw CLIError.usage("Unknown context option: \(arg)")
        }
        index += 1
    }

    guard let app else {
        throw CLIError.usage(contextUsage)
    }

    if requireCwd, cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        throw CLIError.usage("context set requires --cwd")
    }

    return (app, cwd, detail)
}

func printContext(_ context: ProgramContext, path: String, json: Bool) throws {
    if json {
        let data = try WireCoding.encoder.encode(context)
        print(String(decoding: data, as: UTF8.self))
        return
    }

    print("app: \(context.appName ?? "")")
    print("bundle_id: \(context.bundleIdentifier ?? "")")
    print("provider: \(context.provider)")
    print("cwd: \(context.cwd)")
    print("path: \(path)")
}

let contextUsage = "Usage: fzf-palette context set|get|clear --app codex|claude|ghostty [--cwd dir] [--detail text] [--json]"

func runTestControl(_ arguments: [String]) throws {
    guard let action = arguments.first else {
        throw CLIError.usage(testControlUsage)
    }

    let json = arguments.contains("--json")
    let requestType: RequestType
    var query: String?
    switch action {
    case "accept":
        requestType = .testAccept
    case "cancel":
        requestType = .testCancel
    case "hotkey":
        requestType = .testHotkey
        query = firstNonFlagArgument(after: arguments.dropFirst())
    case "carbon-hotkey":
        requestType = .testCarbonHotkey
        query = firstNonFlagArgument(after: arguments.dropFirst())
    case "physical-hotkey":
        requestType = .testPhysicalHotkey
        query = firstNonFlagArgument(after: arguments.dropFirst())
    case "physical-type":
        guard arguments.count >= 2 else {
            throw CLIError.usage("Usage: fzf-palette test-control physical-type value")
        }
        requestType = .testPhysicalType
        query = arguments.dropFirst().joined(separator: " ")
    case "physical-key":
        guard let key = firstNonFlagArgument(after: arguments.dropFirst()) else {
            throw CLIError.usage("Usage: fzf-palette test-control physical-key return|escape|up|down|left|right|tab|space|delete")
        }
        requestType = .testPhysicalKey
        query = key
    case "key":
        guard let key = firstNonFlagArgument(after: arguments.dropFirst()) else {
            throw CLIError.usage("Usage: fzf-palette test-control key return|escape|up|down|tab|space")
        }
        requestType = .testKey
        query = key
    case "toggle":
        requestType = .testToggleSelection
    case "select-all":
        requestType = .testSelectAll
    case "deselect-all":
        requestType = .testDeselectAll
    case "query":
        guard arguments.count >= 2 else {
            throw CLIError.usage("Usage: fzf-palette test-control query value")
        }
        requestType = .testSetQuery
        query = arguments.dropFirst().joined(separator: " ")
    case "move-down":
        requestType = .testMoveDown
    case "move-up":
        requestType = .testMoveUp
    case "toggle-preview":
        requestType = .testTogglePreview
    case "snapshot":
        requestType = .testVisualSnapshot
    default:
        throw CLIError.usage(testControlUsage)
    }

    let response = try sendWithLaunch(.init(type: requestType, query: query))
    if response.type == .error {
        throw CLIError.requestFailed(response)
    }
    if let snapshot = response.snapshot {
        if json {
            let data = try WireCoding.encoder.encode(snapshot)
            print(String(decoding: data, as: UTF8.self))
        } else {
            print(
                "visible=\(snapshot.panelVisible) focused=\(snapshot.queryFieldFocused) " +
                    "size=\(Int(snapshot.width))x\(Int(snapshot.height)) " +
                    "non_background=\(String(format: "%.4f", snapshot.nonBackgroundSampleRatio)) " +
                    "luminance=\(String(format: "%.4f", snapshot.averageLuminance)) " +
                    "appearance=\(snapshot.effectiveAppearanceName) " +
                    "colors=\(snapshot.distinctColorBuckets) violations=\(snapshot.layoutViolationCount)"
            )
        }
        return
    }
    print(response.message ?? response.status?.rawValue ?? response.type.rawValue)
}

let testControlUsage = "Usage: fzf-palette test-control accept|cancel|hotkey [profile]|carbon-hotkey [profile]|physical-hotkey [profile]|physical-type value|physical-key key|key key|toggle|toggle-preview|select-all|deselect-all|query value|move-down|move-up|snapshot [--json]"

func firstNonFlagArgument<S: Sequence>(after arguments: S) -> String? where S.Element == String {
    arguments.first { !$0.hasPrefix("--") }
}

func sendWithLaunch(_ request: PaletteClientRequest) throws -> PaletteResponse {
    let client = PaletteSocketClient()
    var lastError: Error?
    var launched = false

    for attempt in 0..<12 {
        do {
            return try client.send(request)
        } catch {
            lastError = error
            if !launched {
                launchAppIfAvailable()
                launched = true
            }
            usleep(UInt32(min(250_000, 30_000 + attempt * 20_000)))
        }
    }

    throw lastError ?? CLIError.usage("Could not connect to fzf-palette")
}

func launchAppIfAvailable() {
    let environment = ProcessInfo.processInfo.environment
    let bundlePath = environment["FZF_PALETTE_APP_BUNDLE"] ?? FzfPalettePaths.defaultInstallURL.path
    guard FileManager.default.fileExists(atPath: bundlePath) else {
        return
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-gj", bundlePath]
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try? process.run()
}

func parseOpenRequest(_ arguments: [String]) throws -> PickerRequest {
    var profile = "default"
    var cwd = FileManager.default.currentDirectoryPath
    var source: PickerSource = .profile
    var preview: PreviewConfig?
    var fzfOptions: [String] = []
    var resultMode = ResultMode.return
    var result = ResultConfig()
    var display = DisplayConfig()
    var input: String?
    var query = ""
    var timeoutMs = 0

    var index = 0
    while index < arguments.count {
        let arg = arguments[index]
        func requireValue() throws -> String {
            guard index + 1 < arguments.count else {
                throw CLIError.usage("Missing value for \(arg)")
            }
            index += 1
            return arguments[index]
        }

        switch arg {
        case "--profile":
            profile = try requireValue()
        case "--cwd":
            cwd = try requireValue()
        case "--source-command":
            source = .command(try requireValue())
        case "--preview-command":
            preview = PreviewConfig(command: try requireValue())
        case "--preview-window":
            let window = try requireValue()
            if let existing = preview {
                preview = PreviewConfig(command: existing.command, window: window, debounceMs: existing.debounceMs)
            } else {
                preview = PreviewConfig(command: "", window: window)
            }
        case "--ansi":
            display.ansi = true
            fzfOptions.append(arg)
        case "--delimiter", "-d":
            let delimiter = try requireValue()
            display.delimiter = delimiter
            fzfOptions.append(arg)
            fzfOptions.append(delimiter)
        case let option where option.hasPrefix("--delimiter="):
            display.delimiter = String(option.dropFirst("--delimiter=".count))
            fzfOptions.append(arg)
        case let option where option.hasPrefix("-d") && option.count > 2:
            display.delimiter = String(option.dropFirst(2))
            fzfOptions.append(arg)
        case "--nth", "-n":
            let nth = try requireValue()
            display.nth = nth
            fzfOptions.append(arg)
            fzfOptions.append(nth)
        case let option where option.hasPrefix("--nth="):
            display.nth = String(option.dropFirst("--nth=".count))
            fzfOptions.append(arg)
        case let option where option.hasPrefix("-n") && option.count > 2:
            display.nth = String(option.dropFirst(2))
            fzfOptions.append(arg)
        case "--with-nth":
            let withNth = try requireValue()
            display.withNth = withNth
            fzfOptions.append(arg)
            fzfOptions.append(withNth)
        case let option where option.hasPrefix("--with-nth="):
            display.withNth = String(option.dropFirst("--with-nth=".count))
            fzfOptions.append(arg)
        case "--prompt":
            let prompt = try requireValue()
            display.prompt = prompt
            fzfOptions.append(arg)
            fzfOptions.append(prompt)
        case let option where option.hasPrefix("--prompt="):
            display.prompt = String(option.dropFirst("--prompt=".count))
            fzfOptions.append(arg)
        case "--header":
            let header = try requireValue()
            display.header = header
            fzfOptions.append(arg)
            fzfOptions.append(header)
        case let option where option.hasPrefix("--header="):
            display.header = String(option.dropFirst("--header=".count))
            fzfOptions.append(arg)
        case "--pointer":
            let pointer = try requireValue()
            display.pointer = pointer
            fzfOptions.append(arg)
            fzfOptions.append(pointer)
        case let option where option.hasPrefix("--pointer="):
            display.pointer = String(option.dropFirst("--pointer=".count))
            fzfOptions.append(arg)
        case "--marker":
            let marker = try requireValue()
            display.marker = marker
            fzfOptions.append(arg)
            fzfOptions.append(marker)
        case let option where option.hasPrefix("--marker="):
            display.marker = String(option.dropFirst("--marker=".count))
            fzfOptions.append(arg)
        case "--info":
            let info = try requireValue()
            guard info == "inline" else {
                throw CLIError.usage("Unsupported --info value: \(info)")
            }
            display.info = info
            fzfOptions.append(arg)
            fzfOptions.append(info)
        case let option where option.hasPrefix("--info="):
            let info = String(option.dropFirst("--info=".count))
            guard info == "inline" else {
                throw CLIError.usage("Unsupported --info value: \(info)")
            }
            display.info = info
            fzfOptions.append(arg)
        case "--stdin":
            input = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8)
            source = .stdin
        case "--multi", "-m":
            fzfOptions.append(arg)
        case "--query", "-q":
            query = try requireValue()
        case "--result":
            let mode = try requireValue()
            guard let parsed = ResultMode(rawValue: mode) else {
                throw CLIError.usage("Unsupported result mode: \(mode)")
            }
            resultMode = parsed
            result.mode = parsed
        case "--result-fields":
            result.fields = try requireValue()
        case "--result-command":
            result.command = try requireValue()
        case "--join":
            let joinMode = try requireValue()
            guard let parsed = JoinMode(rawValue: joinMode) else {
                throw CLIError.usage("Unsupported join mode: \(joinMode)")
            }
            result.join = parsed
        case "--timeout-ms":
            let value = try requireValue()
            guard let parsed = Int(value), parsed >= 0 else {
                throw CLIError.usage("Invalid --timeout-ms value: \(value)")
            }
            timeoutMs = parsed
        default:
            fzfOptions.append(arg)
        }
        index += 1
    }

    return PickerRequest(
        profile: profile,
        cwd: cwd,
        query: query,
        source: source,
        fzfOptions: fzfOptions,
        display: display,
        preview: preview,
        input: input,
        result: result,
        resultMode: resultMode,
        timeoutMs: timeoutMs
    )
}

func printStatus(_ response: PaletteResponse, json: Bool) throws {
    guard response.type == .status, let status = response.app else {
        throw CLIError.requestFailed(response)
    }

    if json {
        let data = try WireCoding.encoder.encode(response)
        print(String(decoding: data, as: UTF8.self))
        return
    }

    print("fzf-palette running")
    print("pid: \(status.pid)")
    print("socket: \(status.socketPath)")
    print("uptime_ms: \(status.uptimeMs)")
    print("logs: \(status.logDirectory)")
    if let hotkey = status.hotkey {
        print("hotkey: \(hotkey)")
        print("hotkey_registered: \(status.hotkeyRegistered)")
    }
    if !status.hotkeys.isEmpty {
        for hotkey in status.hotkeys {
            var line = "hotkey_profile: \(hotkey.profile) \(hotkey.hotkey) registered=\(hotkey.registered)"
            if let error = hotkey.error {
                line += " error=\(error)"
            }
            print(line)
        }
    }
    if let hotkeyError = status.hotkeyError {
        print("hotkey_error: \(hotkeyError)")
    }
    print("settings_hotkey: \(status.settingsHotkey ?? "")")
    print("settings_profile: \(status.settingsProfile ?? "default")")
    print("settings_visible: \(status.settingsVisible)")
    if let context = status.programContext {
        print("program_context_provider: \(context.provider)")
        print("program_context_app: \(context.appName ?? "")")
        print("program_context_cwd: \(context.cwd)")
    }
}

func printResult(_ response: PaletteResponse) throws {
    if response.type == .error {
        throw CLIError.requestFailed(response)
    }

    guard response.status == .selected else {
        throw CLIError.requestFailed(response)
    }

    if let text = response.text {
        print(text)
    } else if let items = response.items {
        print(items.joined(separator: "\n"))
    }
}

func printCancel(_ response: PaletteResponse) throws {
    if response.type == .error {
        throw CLIError.requestFailed(response)
    }

    print(response.status?.rawValue ?? "cancelled")
}

func runLocalBench(_ arguments: [String]) throws {
    let json = arguments.contains("--json")
    let target = arguments.first { !$0.hasPrefix("-") } ?? "engine"
    switch target {
    case "engine":
        try runEngineBench(arguments, json: json)
    case "cli-roundtrip":
        try runCliRoundtripBench(arguments, json: json)
    case "panel", "hotkey", "carbon-hotkey", "physical-hotkey", "keystroke", "large-keystroke", "movement", "main-thread", "source", "preview", "result", "lifecycle":
        try runAppBench(arguments, name: target, json: json)
    default:
        throw CLIError.usage("Unsupported benchmark: \(target)")
    }
}

func runEngineBench(_ arguments: [String], json: Bool) throws {
    let runs = valueAfter("--runs", in: arguments).flatMap(Int.init) ?? 100
    let warmup = valueAfter("--warmup", in: arguments).flatMap(Int.init) ?? 10
    let measuredRuns = max(1, runs)
    let totalRuns = measuredRuns + max(0, warmup)
    let rows = benchmarkRows(count: 10_000).enumerated().map { index, row in
        PaletteRow(original: row, display: row, sourceIndex: index)
    }
    let engine = NativeFuzzySearchEngine(rows: rows)
    let queries = benchmarkQueries(count: totalRuns)
    var values: [Double] = []

    for index in 0..<totalRuns {
        let start = ContinuousClock.now
        let query = queries[index]
        let matches = engine.searchRows(query: query, includeRanges: false)
        for row in matches.prefix(20) {
            _ = engine.matchRanges(query: query, sourceIndex: row.sourceIndex)
        }
        if index >= warmup {
            values.append(milliseconds(start.duration(to: ContinuousClock.now)))
        }
    }

    let summary = MetricSummary(values: values)
    var failures: [String] = []
    if summary.max >= 50 {
        failures.append("engine query max \(summary.max)ms >= 50ms hard max")
    }
    if summary.p95 >= 10 {
        failures.append("engine query p95 \(summary.p95)ms >= 10ms target")
    }

    let report = BenchReport(
        name: "engine",
        runs: values.count,
        warmup: warmup,
        budgets: [
            "hard_max_ms": 50,
            "target_p95_ms": 10,
            "rows": 10_000
        ],
        metrics: ["engine_query_ms": summary],
        failures: failures
    )

    try printBenchReport(report, json: json)
    try failIfBenchFailed(report)
}

func runAppBench(_ arguments: [String], name: String, json: Bool) throws {
    let runs = valueAfter("--runs", in: arguments).flatMap(Int.init) ?? 100
    let warmup = valueAfter("--warmup", in: arguments).flatMap(Int.init) ?? 10
    let response = try sendWithLaunch(.init(
        type: .bench,
        bench: BenchRequest(name: name, runs: runs, warmup: warmup)
    ))

    guard let report = response.bench else {
        throw CLIError.requestFailed(response)
    }

    try printBenchReport(report, json: json)
    try failIfBenchFailed(report)
}

func runCliRoundtripBench(_ arguments: [String], json: Bool) throws {
    let runs = valueAfter("--runs", in: arguments).flatMap(Int.init) ?? 100
    let warmup = valueAfter("--warmup", in: arguments).flatMap(Int.init) ?? 10
    let totalRuns = max(1, runs + warmup)
    let client = PaletteSocketClient()
    var values: [Double] = []

    _ = try sendWithLaunch(.init(type: .status))

    for index in 0..<totalRuns {
        let start = ContinuousClock.now
        let response = try client.send(.init(type: .status))
        guard response.type == .status, response.app != nil else {
            throw CLIError.requestFailed(response)
        }
        let elapsed = start.duration(to: ContinuousClock.now)
        let milliseconds = Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
        if index >= warmup {
            values.append(milliseconds)
        }
    }

    let summary = MetricSummary(values: values)
    var failures: [String] = []
    if summary.max >= 200 {
        failures.append("cli roundtrip max \(summary.max)ms >= 200ms hard max")
    }
    if summary.p95 >= 80 {
        failures.append("cli roundtrip p95 \(summary.p95)ms >= 80ms target")
    }

    let report = BenchReport(
        name: "cli-roundtrip",
        runs: values.count,
        warmup: warmup,
        budgets: [
            "hard_max_ms": 200,
            "target_p95_ms": 80
        ],
        metrics: ["cli_roundtrip_ms": summary],
        failures: failures
    )

    try printBenchReport(report, json: json)
    try failIfBenchFailed(report)
}

func printBenchReport(_ report: BenchReport, json: Bool) throws {
    if json {
        let data = try WireCoding.encoder.encode(report)
        print(String(decoding: data, as: UTF8.self))
    } else {
        for (metricName, summary) in report.metrics.sorted(by: { $0.key < $1.key }) {
            print("\(report.name) \(metricName) max_ms=\(String(format: "%.3f", summary.max)) p95_ms=\(String(format: "%.3f", summary.p95))")
        }
    }
}

func failIfBenchFailed(_ report: BenchReport) throws {
    if !report.failures.isEmpty {
        throw CLIError.requestFailed(.init(
            type: .error,
            code: "benchmark_failed",
            message: report.failures.joined(separator: "; "),
            bench: report
        ))
    }
}

func valueAfter(_ option: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: option), index + 1 < arguments.count else {
        return nil
    }
    return arguments[index + 1]
}

func benchmarkRows(count: Int) -> [String] {
    (0..<count).map { index in
        let module = index % 12
        let depth = index % 7
        return "src/module-\(module)/component-\(depth)/file-\(index).swift"
    }
}

func benchmarkQueries(count: Int) -> [String] {
    let corpus = [
        "s",
        "sr",
        "src",
        "src/",
        "src/m",
        "sm",
        "smf",
        "file",
        "file-4",
        "module-1",
        "component-3",
        "nomatch"
    ]
    return (0..<count).map { corpus[$0 % corpus.count] }
}

func milliseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1000
        + Double(duration.components.attoseconds) / 1_000_000_000_000_000
}

func printHelp() {
    print(
        """
        Usage:
          fzf-palette status [--json]
          fzf-palette env reload [--json]
          fzf-palette open [--profile name] [--source-command command] [--multi] [--exact] [--preview-command command] [--prompt text] [--header text] [--pointer text] [--marker text] [--info inline] [--delimiter value] [--nth fields] [--with-nth fields] [--result-fields fields] [--result-command command] [--timeout-ms ms]
          fzf-palette settings get|show|close|clear [--json]
          fzf-palette settings set --hotkey value [--profile name] [--json]
          fzf-palette context set|get|clear --app codex|claude|ghostty [--cwd dir] [--detail text] [--json]
          fzf-palette cancel
          fzf-palette bench [engine|panel|hotkey|carbon-hotkey|physical-hotkey|keystroke|large-keystroke|movement|main-thread|source|preview|result|lifecycle|cli-roundtrip] [--runs n] [--warmup n] [--json]
          fzf-palette test-control accept|cancel|hotkey|carbon-hotkey|physical-hotkey|physical-type|physical-key|key|toggle|toggle-preview|select-all|deselect-all|query value|move-down|move-up|snapshot [--json]
        """
    )
}
