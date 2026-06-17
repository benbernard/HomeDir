import AppKit
import ApplicationServices
import Carbon
import Foundation
import FzfPaletteCore
import os

private enum PhysicalKeyboardPostResult: Equatable {
    case posted
    case accessibilityNotTrusted
    case missingText
    case unsupportedKey(String)
    case eventCreationFailed

    var isPosted: Bool {
        self == .posted
    }

    var code: String {
        switch self {
        case .posted:
            return "posted"
        case .accessibilityNotTrusted:
            return "accessibility_not_trusted"
        case .missingText:
            return "missing_text"
        case .unsupportedKey:
            return "unsupported_key"
        case .eventCreationFailed:
            return "event_creation_failed"
        }
    }

    var message: String {
        switch self {
        case .posted:
            return "Physical keyboard input posted."
        case .accessibilityNotTrusted:
            return "Physical keyboard input tests require Accessibility permission for the app posting CGEvent keyboard input."
        case .missingText:
            return "Physical keyboard text input cannot be empty."
        case let .unsupportedKey(key):
            return "Unsupported physical keyboard key: \(key)."
        case .eventCreationFailed:
            return "Could not create one or more CGEvent keyboard events."
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "dev.benbernard.fzf-palette", category: "app")
    private let startDate = Date()
    private let panelController = PalettePanelController()
    private let socketServer = SocketServer()
    private let hotKeyController = HotKeyController()
    private let sourceRunner = SourceCommandRunner()
    private let previewRunner = PreviewCommandRunner()
    private let resultCommandRunner = CommandRunner()
    private let activePickerLock = NSLock()
    private let activeWorkLock = NSLock()
    private let programContextLock = NSLock()
    private let completionReasonLock = NSLock()
    private var environmentSnapshot = EnvironmentSnapshot()
    private var hasActivePicker = false
    private var activeSourceToken: CommandCancellationToken?
    private var activePreviewToken: CommandCancellationToken?
    private var activeResultToken: CommandCancellationToken?
    private var activePreviewDebounce: DispatchWorkItem?
    private var previewGeneration = 0
    private var hotKeyConfigurationError: String?
    private var profileStore = ProfileStore()
    private var profileStoreLoadError: String?
    private var lastProgramContext: ProgramContext?
    private var lastCompletionReason = "not_started"
    private let settingsStore = SettingsStore()
    private lazy var settingsWindowController = SettingsWindowController(
        loadSettings: { [weak self] in
            self?.settingsStore.load() ?? PaletteSettings()
        },
        saveSettings: { [weak self] settings in
            guard let self else {
                return .failure("Settings are unavailable.")
            }
            do {
                return .success(try self.saveSettings(settings))
            } catch {
                return .failure(String(describing: error))
            }
        }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            applyForcedAppearanceIfRequested()
            try FzfPalettePaths.ensureRuntimeDirectories()
            panelController.prepare()
            try socketServer.start(handler: handleRequest(_:))
            captureEnvironmentSnapshot()
            reloadProfileStore()
            reloadHotKeys()
            logger.info("fzf-palette app started")
        } catch {
            logger.error("Startup failed: \(String(describing: error))")
            fputs("fzf-palette startup failed: \(error)\n", stderr)
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        socketServer.stop()
    }

    private func applyForcedAppearanceIfRequested() {
        guard let rawAppearance = ProcessInfo.processInfo.environment["FZF_PALETTE_APPEARANCE"]?.lowercased(),
              !rawAppearance.isEmpty else {
            return
        }

        switch rawAppearance {
        case "light", "aqua":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "dark", "darkaqua", "dark-aqua":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            logger.warning("Ignoring unsupported FZF_PALETTE_APPEARANCE value \(rawAppearance, privacy: .public)")
        }
    }

    private func handleRequest(_ request: PaletteClientRequest) -> PaletteResponse {
        switch request.type {
        case .status:
            return .init(type: .status, id: request.id, app: appStatus())
        case .envReload:
            captureEnvironmentSnapshot()
            reloadProfileStore()
            reloadHotKeys()
            return .init(type: .status, id: request.id, app: appStatus())
        case .open:
            guard let pickerRequest = request.request else {
                return .init(
                    type: .error,
                    id: request.id,
                    code: "missing_request",
                    message: "Open requests require a picker request payload."
                )
            }
            return runOpenRequest(pickerRequest)
        case .bench:
            return runBench(request.bench ?? BenchRequest(name: "panel"), id: request.id)
        case .settingsGet:
            return settingsResponse(id: request.id)
        case .settingsSet:
            guard let settings = request.settings else {
                return .init(
                    type: .error,
                    id: request.id,
                    code: "missing_settings",
                    message: "settings.set requires a settings payload."
                )
            }
            do {
                let saved = try saveSettings(settings)
                return settingsResponse(id: request.id, settings: saved)
            } catch {
                return .init(
                    type: .error,
                    id: request.id,
                    code: "settings_invalid",
                    message: String(describing: error)
                )
            }
        case .settingsClear:
            settingsStore.clear()
            reloadHotKeys()
            return settingsResponse(id: request.id)
        case .settingsShow:
            performSettingsWindowControl { controller in
                controller.show()
            }
            return settingsResponse(id: request.id)
        case .settingsClose:
            performSettingsWindowControl { controller in
                controller.close()
            }
            return settingsResponse(id: request.id)
        case .cancel:
            DispatchQueue.main.async { [weak self] in
                self?.panelController.cancelActivePicker()
            }
            cancelActiveWork()
            return .init(type: .result, id: request.id, status: .cancelled)
        case .testAccept:
            guard isTestControlEnabled else {
                return .init(
                    type: .error,
                    id: request.id,
                    code: "test_control_disabled",
                    message: "Set FZF_PALETTE_ENABLE_TEST_CONTROL=1 in the app environment to use test controls."
                )
            }
            performPanelControl { panel in
                panel.acceptCurrentSelection()
            }
            return .init(type: .result, id: request.id, status: .selected)
        case .testCancel:
            guard isTestControlEnabled else {
                return .init(
                    type: .error,
                    id: request.id,
                    code: "test_control_disabled",
                    message: "Set FZF_PALETTE_ENABLE_TEST_CONTROL=1 in the app environment to use test controls."
                )
            }
            performPanelControl { panel in
                panel.cancelActivePicker()
            }
            cancelActiveWork()
            return .init(type: .result, id: request.id, status: .cancelled)
        case .testHotkey:
            guard isTestControlEnabled else {
                return .init(
                    type: .error,
                    id: request.id,
                    code: "test_control_disabled",
                    message: "Set FZF_PALETTE_ENABLE_TEST_CONTROL=1 in the app environment to use test controls."
                )
            }
            performPanelControl { _ in
                self.hotKeyController.simulateHotKeyForTests(profile: request.query)
            }
            return .init(type: .status, id: request.id, app: appStatus())
        case .testCarbonHotkey:
            guard isTestControlEnabled else {
                return .init(
                    type: .error,
                    id: request.id,
                    code: "test_control_disabled",
                    message: "Set FZF_PALETTE_ENABLE_TEST_CONTROL=1 in the app environment to use test controls."
                )
            }
            let status = hotKeyController.postCarbonHotKeyEventForTests(profile: request.query)
            guard status == noErr else {
                return .init(
                    type: .error,
                    id: request.id,
                    code: "carbon_hotkey_failed",
                    message: "Posting Carbon hotkey event failed: \(status)"
                )
            }
            guard waitForPanelVisibleAfterHotKey(timeoutMs: 250) else {
                return .init(
                    type: .error,
                    id: request.id,
                    code: "carbon_hotkey_timeout",
                    message: "Carbon hotkey event did not show the panel within 250ms."
                )
            }
            return .init(type: .status, id: request.id, app: appStatus())
        case .testPhysicalHotkey:
            guard isTestControlEnabled else {
                return .init(
                    type: .error,
                    id: request.id,
                    code: "test_control_disabled",
                    message: "Set FZF_PALETTE_ENABLE_TEST_CONTROL=1 in the app environment to use test controls."
                )
            }
            let result = hotKeyController.postPhysicalHotKeyEventForTests(profile: request.query)
            guard result.isPosted else {
                return .init(
                    type: .error,
                    id: request.id,
                    code: "physical_hotkey_\(result.code)",
                    message: result.message
                )
            }
            guard waitForPanelVisibleAfterHotKey(timeoutMs: 250) else {
                return .init(
                    type: .error,
                    id: request.id,
                    code: "physical_hotkey_timeout",
                    message: "Physical CGEvent hotkey did not show the panel within 250ms."
                )
            }
            return .init(type: .status, id: request.id, app: appStatus())
        case .testPhysicalType:
            guard isTestControlEnabled else {
                return .init(
                    type: .error,
                    id: request.id,
                    code: "test_control_disabled",
                    message: "Set FZF_PALETTE_ENABLE_TEST_CONTROL=1 in the app environment to use test controls."
                )
            }
            performPanelControl { panel in
                panel.refocusQueryFieldForTests()
            }
            let result = postPhysicalTextForTests(request.query ?? "")
            guard result.isPosted else {
                return .init(
                    type: .error,
                    id: request.id,
                    code: "physical_keyboard_\(result.code)",
                    message: result.message
                )
            }
            usleep(80_000)
            return .init(type: .status, id: request.id, app: appStatus())
        case .testPhysicalKey:
            guard isTestControlEnabled else {
                return .init(
                    type: .error,
                    id: request.id,
                    code: "test_control_disabled",
                    message: "Set FZF_PALETTE_ENABLE_TEST_CONTROL=1 in the app environment to use test controls."
                )
            }
            guard let key = request.query else {
                return .init(
                    type: .error,
                    id: request.id,
                    code: "missing_key",
                    message: "test.physicalKey requires a key payload."
                )
            }
            performPanelControl { panel in
                panel.refocusQueryFieldForTests()
            }
            let result = postPhysicalKeyForTests(key)
            guard result.isPosted else {
                return .init(
                    type: .error,
                    id: request.id,
                    code: "physical_keyboard_\(result.code)",
                    message: result.message
                )
            }
            usleep(80_000)
            return .init(type: .status, id: request.id, app: appStatus())
        case .testToggleSelection:
            guard isTestControlEnabled else {
                return .init(
                    type: .error,
                    id: request.id,
                    code: "test_control_disabled",
                    message: "Set FZF_PALETTE_ENABLE_TEST_CONTROL=1 in the app environment to use test controls."
                )
            }
            performPanelControl { panel in
                panel.toggleCurrentSelection()
            }
            return .init(type: .result, id: request.id, status: .selected)
        case .testSelectAll:
            guard isTestControlEnabled else {
                return .init(
                    type: .error,
                    id: request.id,
                    code: "test_control_disabled",
                    message: "Set FZF_PALETTE_ENABLE_TEST_CONTROL=1 in the app environment to use test controls."
                )
            }
            performPanelControl { panel in
                panel.selectAllVisibleRows()
            }
            return .init(type: .result, id: request.id, status: .selected)
        case .testDeselectAll:
            guard isTestControlEnabled else {
                return .init(
                    type: .error,
                    id: request.id,
                    code: "test_control_disabled",
                    message: "Set FZF_PALETTE_ENABLE_TEST_CONTROL=1 in the app environment to use test controls."
                )
            }
            performPanelControl { panel in
                panel.deselectAllRows()
            }
            return .init(type: .result, id: request.id, status: .selected)
        case .testSetQuery:
            guard isTestControlEnabled else {
                return .init(
                    type: .error,
                    id: request.id,
                    code: "test_control_disabled",
                    message: "Set FZF_PALETTE_ENABLE_TEST_CONTROL=1 in the app environment to use test controls."
                )
            }
            guard let query = request.query else {
                return .init(
                    type: .error,
                    id: request.id,
                    code: "missing_query",
                    message: "test.setQuery requires a query payload."
                )
            }
            performPanelControl { panel in
                panel.setQuery(query)
            }
            return .init(type: .result, id: request.id, status: .selected)
        case .testKey:
            guard isTestControlEnabled else {
                return .init(
                    type: .error,
                    id: request.id,
                    code: "test_control_disabled",
                    message: "Set FZF_PALETTE_ENABLE_TEST_CONTROL=1 in the app environment to use test controls."
                )
            }
            guard let key = request.query else {
                return .init(
                    type: .error,
                    id: request.id,
                    code: "missing_key",
                    message: "test.key requires a key payload."
                )
            }
            var handled = false
            performPanelControl { panel in
                handled = panel.handleSyntheticKey(key)
            }
            guard handled else {
                return .init(
                    type: .error,
                    id: request.id,
                    code: "unsupported_key",
                    message: "Unsupported synthetic key: \(key)"
                )
            }
            return .init(type: .status, id: request.id, app: appStatus())
        case .testMoveDown:
            guard isTestControlEnabled else {
                return .init(
                    type: .error,
                    id: request.id,
                    code: "test_control_disabled",
                    message: "Set FZF_PALETTE_ENABLE_TEST_CONTROL=1 in the app environment to use test controls."
                )
            }
            performPanelControl { panel in
                panel.selectNextRow()
            }
            return .init(type: .result, id: request.id, status: .selected)
        case .testMoveUp:
            guard isTestControlEnabled else {
                return .init(
                    type: .error,
                    id: request.id,
                    code: "test_control_disabled",
                    message: "Set FZF_PALETTE_ENABLE_TEST_CONTROL=1 in the app environment to use test controls."
                )
            }
            performPanelControl { panel in
                panel.selectPreviousRow()
            }
            return .init(type: .result, id: request.id, status: .selected)
        case .testTogglePreview:
            guard isTestControlEnabled else {
                return .init(
                    type: .error,
                    id: request.id,
                    code: "test_control_disabled",
                    message: "Set FZF_PALETTE_ENABLE_TEST_CONTROL=1 in the app environment to use test controls."
                )
            }
            var message = "preview:unknown"
            performPanelControl { panel in
                message = panel.togglePreviewVisibility()
            }
            return .init(type: .result, id: request.id, status: .selected, message: message)
        case .testVisualSnapshot:
            guard isTestControlEnabled else {
                return .init(
                    type: .error,
                    id: request.id,
                    code: "test_control_disabled",
                    message: "Set FZF_PALETTE_ENABLE_TEST_CONTROL=1 in the app environment to use test controls."
                )
            }
            var snapshot: PanelVisualSnapshot?
            performPanelControl { panel in
                snapshot = panel.visualSnapshot()
            }
            return .init(type: .result, id: request.id, status: .selected, snapshot: snapshot)
        }
    }

    private func showPaletteForHotKey(profile: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                return
            }

            let context = self.resolveProgramContextForHotKey()
            self.setLastProgramContext(context)

            var request = PickerRequest(profile: profile)
            if let context {
                request.cwd = context.cwd
                request.env.merge(context.environmentValues) { _, contextValue in contextValue }
            }

            _ = self.runOpenRequest(request)
        }
    }

    private func runBench(_ request: BenchRequest, id: String?) -> PaletteResponse {
        switch request.name {
        case "panel":
            return runPanelBench(request, id: id)
        case "hotkey":
            return runDirectHotKeyBench(request, id: id)
        case "carbon-hotkey":
            return runCarbonHotKeyBench(request, id: id)
        case "physical-hotkey":
            return runPhysicalHotKeyBench(request, id: id)
        case "keystroke":
            return runKeystrokeBench(request, id: id, rowCount: 10_000, targetP95Ms: 10)
        case "large-keystroke":
            return runKeystrokeBench(request, id: id, rowCount: 100_000, targetP95Ms: 20)
        case "movement":
            return runMovementBench(request, id: id)
        case "main-thread":
            return runMainThreadBench(request, id: id)
        case "source":
            return runSourceBench(request, id: id)
        case "preview":
            return runPreviewBench(request, id: id)
        case "result":
            return runResultDeliveryBench(request, id: id)
        case "lifecycle":
            return runLifecycleBench(request, id: id)
        default:
            return .init(
                type: .error,
                id: id,
                code: "unsupported_bench",
                message: "Unsupported benchmark: \(request.name)"
            )
        }
    }

    private func runResultDeliveryBench(_ request: BenchRequest, id: String?) -> PaletteResponse {
        let totalRuns = max(1, request.runs + request.warmup)
        let rows = [
            "Alpha Session\t/hidden/alpha.json",
            "Beta Session\t/hidden/beta.json",
            "Gamma Session\t/hidden/gamma.json"
        ]
        let pickerRequest = PickerRequest(
            profile: "bench-result",
            source: .staticItems(rows),
            display: DisplayConfig(delimiter: "\t", withNth: "1"),
            result: ResultConfig(mode: .return, fields: "2")
        )
        var values: [Double] = []
        var failures: [String] = []

        for index in 0..<totalRuns {
            let responseLock = NSLock()
            let finished = DispatchSemaphore(value: 0)
            var response: PaletteResponse?
            var start: ContinuousClock.Instant?

            DispatchQueue.main.sync {
                panelController.clearCompletion()
                panelController.clearActiveRowChangeHandler()
                panelController.setCompletion { [weak self] outcome in
                    guard let self else {
                        responseLock.withLock {
                            response = .init(
                                type: .error,
                                code: "app_unavailable",
                                message: "The app delegate was released before result benchmark delivery."
                            )
                        }
                        finished.signal()
                        return
                    }

                    switch outcome {
                    case let .selected(originalRows):
                        self.deliverSelection(
                            originalRows: originalRows,
                            request: pickerRequest,
                            pasteTargetApplication: nil
                        ) { deliveredResponse in
                            responseLock.withLock {
                                response = deliveredResponse
                            }
                            finished.signal()
                        }
                    case .cancelled:
                        responseLock.withLock {
                            response = .init(type: .result, status: .cancelled)
                        }
                        finished.signal()
                    }
                }
                panelController.showRows(
                    title: "bench-result",
                    rows: rows,
                    display: pickerRequest.display,
                    preview: "Result delivery benchmark",
                    allowsMultipleSelection: false,
                    allowsPreviewToggle: false
                )
                start = ContinuousClock.now
                panelController.acceptCurrentSelection()
            }

            guard let start else {
                failures.append("result delivery benchmark did not record a start time")
                break
            }
            if finished.wait(timeout: .now() + 1) == .timedOut {
                failures.append("result delivery did not finish within 1s")
                break
            }

            let delivered = responseLock.withLock { response }
            guard delivered?.status == .selected, delivered?.text == "/hidden/alpha.json" else {
                failures.append("result delivery returned unexpected response: \(String(describing: delivered))")
                break
            }

            let panelHidden = DispatchQueue.main.sync {
                !panelController.isPanelVisible
            }
            guard panelHidden else {
                failures.append("result delivery left the panel visible")
                break
            }

            if index >= request.warmup {
                values.append(milliseconds(start.duration(to: ContinuousClock.now)))
            }
        }

        DispatchQueue.main.sync {
            panelController.clearCompletion()
            panelController.clearActiveRowChangeHandler()
            panelController.hide()
        }

        let summary = MetricSummary(values: values)
        if summary.max >= 80 {
            failures.append("selection to result max \(summary.max)ms >= 80ms hard max")
        }
        if summary.p95 >= 45 {
            failures.append("selection to result p95 \(summary.p95)ms >= 45ms target")
        }

        return .init(
            type: failures.isEmpty ? .result : .error,
            id: id,
            code: failures.isEmpty ? nil : "benchmark_failed",
            message: failures.isEmpty ? nil : failures.joined(separator: "; "),
            bench: BenchReport(
                name: request.name,
                runs: values.count,
                warmup: request.warmup,
                budgets: [
                    "hard_max_ms": 80,
                    "target_p95_ms": 45
                ],
                metrics: ["selection_to_result_ms": summary],
                failures: failures
            )
        )
    }

    private func runKeystrokeBench(
        _ request: BenchRequest,
        id: String?,
        rowCount: Int,
        targetP95Ms: Double
    ) -> PaletteResponse {
        let totalRuns = max(1, request.runs + request.warmup)
        let rows = benchmarkRows(count: rowCount)
        let queries = benchmarkQueries(count: totalRuns)
        let durations = DispatchQueue.main.sync {
            panelController.benchmarkKeystrokeFiltering(rows: rows, queries: queries)
        }
        let values = Array(durations.dropFirst(min(request.warmup, durations.count)))
        let summary = MetricSummary(values: values)
        var failures: [String] = []
        if summary.max >= 50 {
            failures.append("keystroke max \(summary.max)ms >= 50ms hard max")
        }
        if summary.p95 >= targetP95Ms {
            failures.append("keystroke p95 \(summary.p95)ms >= \(targetP95Ms)ms target")
        }

        return .init(
            type: failures.isEmpty ? .result : .error,
            id: id,
            code: failures.isEmpty ? nil : "benchmark_failed",
            message: failures.isEmpty ? nil : failures.joined(separator: "; "),
            bench: BenchReport(
                name: request.name,
                runs: values.count,
                warmup: request.warmup,
                budgets: [
                    "hard_max_ms": 50,
                    "target_p95_ms": targetP95Ms,
                    "rows": Double(rows.count)
                ],
                metrics: ["key_to_rows_rendered_ms": summary],
                failures: failures
            )
        )
    }

    private func runMovementBench(_ request: BenchRequest, id: String?) -> PaletteResponse {
        let totalRuns = max(1, request.runs + request.warmup)
        let rows = benchmarkRows(count: 10_000)
        let pickerRequest = PickerRequest(
            profile: "bench-movement",
            preview: PreviewConfig(command: "printf 'preview %s\\n' {}", debounceMs: 100)
        )
        let durations = DispatchQueue.main.sync {
            configurePreviewUpdates(for: pickerRequest)
            let durations = panelController.benchmarkSelectionMovement(
                rows: rows,
                steps: totalRuns,
                previewConfig: pickerRequest.preview
            )
            panelController.clearActiveRowChangeHandler()
            return durations
        }
        cancelPreviewWork()
        let values = Array(durations.dropFirst(min(request.warmup, durations.count)))
        let summary = MetricSummary(values: values)
        var failures: [String] = []
        if summary.max >= 16 {
            failures.append("selection movement max \(summary.max)ms >= 16ms hard max")
        }
        if summary.p95 >= 8 {
            failures.append("selection movement p95 \(summary.p95)ms >= 8ms target")
        }

        return .init(
            type: failures.isEmpty ? .result : .error,
            id: id,
            code: failures.isEmpty ? nil : "benchmark_failed",
            message: failures.isEmpty ? nil : failures.joined(separator: "; "),
            bench: BenchReport(
                name: request.name,
                runs: values.count,
                warmup: request.warmup,
                budgets: [
                    "hard_max_ms": 16,
                    "target_p95_ms": 8,
                    "rows": Double(rows.count)
                ],
                metrics: ["selection_movement_ms": summary],
                failures: failures
            )
        )
    }

    private func runMainThreadBench(_ request: BenchRequest, id: String?) -> PaletteResponse {
        let totalRuns = max(1, request.runs + request.warmup)
        let rows = benchmarkRows(count: 10_000)
        let queries = benchmarkQueries(count: totalRuns)
        let durations = DispatchQueue.main.sync {
            panelController.benchmarkKeystrokeFiltering(rows: rows, queries: queries)
        }
        let values = Array(durations.dropFirst(min(request.warmup, durations.count)))
        let summary = MetricSummary(values: values)
        var failures: [String] = []
        if summary.max >= 16 {
            failures.append("main-thread query task max \(summary.max)ms >= 16ms hard max")
        }
        if summary.p95 >= 10 {
            failures.append("main-thread query task p95 \(summary.p95)ms >= 10ms target")
        }

        return .init(
            type: failures.isEmpty ? .result : .error,
            id: id,
            code: failures.isEmpty ? nil : "benchmark_failed",
            message: failures.isEmpty ? nil : failures.joined(separator: "; "),
            bench: BenchReport(
                name: request.name,
                runs: values.count,
                warmup: request.warmup,
                budgets: [
                    "hard_max_ms": 16,
                    "target_p95_ms": 10,
                    "rows": Double(rows.count)
                ],
                metrics: ["main_thread_query_task_ms": summary],
                failures: failures
            )
        )
    }

    private func runPreviewBench(_ request: BenchRequest, id: String?) -> PaletteResponse {
        let totalRuns = max(1, request.runs + request.warmup)
        var renderValues: [Double] = []
        var failures: [String] = []

        for index in 0..<totalRuns {
            let start = ContinuousClock.now
            do {
                _ = try previewRunner.renderPreview(
                    template: "printf 'preview %s\\n' {}",
                    row: "bench-row",
                    cwd: FileManager.default.currentDirectoryPath,
                    timeoutSeconds: 2
                )
            } catch {
                failures.append("preview command failed: \(error)")
                break
            }

            if index >= request.warmup {
                renderValues.append(milliseconds(start.duration(to: ContinuousClock.now)))
            }
        }

        let responsiveness = measurePreviewResponsiveness(totalRuns: totalRuns)
        failures.append(contentsOf: responsiveness.failures)

        let renderSummary = MetricSummary(values: renderValues)
        let querySummary = MetricSummary(values: Array(responsiveness.queryValues.dropFirst(min(request.warmup, responsiveness.queryValues.count))))

        if renderSummary.max >= 300 {
            failures.append("preview render max \(renderSummary.max)ms >= 300ms hard max")
        }
        if renderSummary.p95 >= 250 {
            failures.append("preview render p95 \(renderSummary.p95)ms >= 250ms target")
        }
        if querySummary.max >= 50 {
            failures.append("preview query max \(querySummary.max)ms >= 50ms hard max")
        }
        if querySummary.p95 >= 10 {
            failures.append("preview query p95 \(querySummary.p95)ms >= 10ms target")
        }

        return .init(
            type: failures.isEmpty ? .result : .error,
            id: id,
            code: failures.isEmpty ? nil : "benchmark_failed",
            message: failures.isEmpty ? nil : failures.joined(separator: "; "),
            bench: BenchReport(
                name: request.name,
                runs: renderValues.count,
                warmup: request.warmup,
                budgets: [
                    "preview_render_hard_max_ms": 300,
                    "preview_render_target_p95_ms": 250,
                    "query_hard_max_ms": 50,
                    "query_target_p95_ms": 10,
                    "rows": 10_000
                ],
                metrics: [
                    "preview_render_ms": renderSummary,
                    "query_while_preview_ms": querySummary
                ],
                failures: failures
            )
        )
    }

    private func measurePreviewResponsiveness(totalRuns: Int) -> (queryValues: [Double], failures: [String]) {
        let token = CommandCancellationToken()
        let started = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let errorLock = NSLock()
        var previewError: Error?

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                errorLock.withLock {
                    previewError = CommandRunError.cancelled(command: "preview benchmark app unavailable")
                }
                finished.signal()
                return
            }

            started.signal()
            do {
                _ = try self.previewRunner.renderPreview(
                    template: "sleep 5; printf 'slow preview\\n'",
                    row: "bench-row",
                    cwd: FileManager.default.currentDirectoryPath,
                    timeoutSeconds: 10,
                    cancellationToken: token
                )
            } catch {
                errorLock.withLock {
                    previewError = error
                }
            }
            finished.signal()
        }

        var failures: [String] = []
        if started.wait(timeout: .now() + 1) == .timedOut {
            failures.append("preview responsiveness command did not start")
        }

        Thread.sleep(forTimeInterval: 0.03)
        let rows = benchmarkRows(count: 10_000)
        let queries = benchmarkQueries(count: totalRuns)
        let queryValues = DispatchQueue.main.sync {
            panelController.benchmarkKeystrokeFiltering(rows: rows, queries: queries)
        }

        token.cancel()
        if finished.wait(timeout: .now() + 2) == .timedOut {
            failures.append("preview responsiveness command did not stop after cancellation")
        }

        let error = errorLock.withLock { previewError }
        if let error, !isCancellation(error) {
            failures.append("preview responsiveness command failed unexpectedly: \(error)")
        }

        return (queryValues, failures)
    }

    private func isCancellation(_ error: Error) -> Bool {
        if case CommandRunError.cancelled = error {
            return true
        }
        return false
    }

    private func runSourceBench(_ request: BenchRequest, id: String?) -> PaletteResponse {
        let totalRuns = max(1, request.runs + request.warmup)
        let command = "i=0; while [ $i -lt 100 ]; do printf 'bench-row-%s\\n' \"$i\"; i=$((i+1)); done"
        var firstRowValues: [Double] = []
        var completionValues: [Double] = []
        var failures: [String] = []

        for index in 0..<totalRuns {
            let firstRowLock = NSLock()
            let start = ContinuousClock.now
            var firstRowMs: Double?

            do {
                try sourceRunner.streamRows(
                    command: command,
                    cwd: FileManager.default.currentDirectoryPath,
                    timeoutSeconds: 3
                ) { rows in
                    guard !rows.isEmpty else {
                        return
                    }
                    firstRowLock.withLock {
                        if firstRowMs == nil {
                            firstRowMs = self.milliseconds(start.duration(to: ContinuousClock.now))
                        }
                    }
                }
            } catch {
                failures.append("source command failed: \(error)")
                break
            }

            let completionMs = milliseconds(start.duration(to: ContinuousClock.now))
            let measuredFirstRowMs = firstRowLock.withLock { firstRowMs } ?? completionMs
            if index >= request.warmup {
                firstRowValues.append(measuredFirstRowMs)
                completionValues.append(completionMs)
            }
        }

        let firstRowSummary = MetricSummary(values: firstRowValues)
        let completionSummary = MetricSummary(values: completionValues)
        if firstRowSummary.max >= 250 {
            failures.append("source first row max \(firstRowSummary.max)ms >= 250ms hard max")
        }
        if firstRowSummary.p95 >= 100 {
            failures.append("source first row p95 \(firstRowSummary.p95)ms >= 100ms target")
        }
        if completionSummary.max >= 500 {
            failures.append("source completion max \(completionSummary.max)ms >= 500ms hard max")
        }
        if completionSummary.p95 >= 250 {
            failures.append("source completion p95 \(completionSummary.p95)ms >= 250ms target")
        }

        return .init(
            type: failures.isEmpty ? .result : .error,
            id: id,
            code: failures.isEmpty ? nil : "benchmark_failed",
            message: failures.isEmpty ? nil : failures.joined(separator: "; "),
            bench: BenchReport(
                name: request.name,
                runs: firstRowValues.count,
                warmup: request.warmup,
                budgets: [
                    "first_row_hard_max_ms": 250,
                    "first_row_target_p95_ms": 100,
                    "completion_hard_max_ms": 500,
                    "completion_target_p95_ms": 250,
                    "rows": 100
                ],
                metrics: [
                    "first_source_row_ms": firstRowSummary,
                    "source_complete_ms": completionSummary
                ],
                failures: failures
            )
        )
    }

    private func runLifecycleBench(_ request: BenchRequest, id: String?) -> PaletteResponse {
        let totalRuns = max(1, request.runs + request.warmup)
        var cycleValues: [Double] = []
        var rssGrowthValues: [Double] = []
        var leakedProcessValues: [Double] = []
        var failures: [String] = []
        var baselineRSS = residentMemoryMB()

        for index in 0..<totalRuns {
            autoreleasepool {
                if index == request.warmup {
                    baselineRSS = residentMemoryMB()
                }

                let marker = "fzf-palette-lifecycle-\(UUID().uuidString)"
                let start = ContinuousClock.now

                _ = DispatchQueue.main.sync {
                    autoreleasepool {
                        panelController.benchmarkPanelShow(title: "lifecycle \(index + 1)")
                    }
                }
                failures.append(contentsOf: runLifecycleSourceCancellation(marker: "\(marker)-source"))
                failures.append(contentsOf: runLifecyclePreviewCancellation(marker: "\(marker)-preview"))

                let leakedCount = processCount(containing: marker)
                let elapsed = milliseconds(start.duration(to: ContinuousClock.now))
                if index >= request.warmup {
                    cycleValues.append(elapsed)
                    rssGrowthValues.append(max(0, residentMemoryMB() - baselineRSS))
                    leakedProcessValues.append(Double(leakedCount))
                }

                if leakedCount > 0 {
                    failures.append("lifecycle leaked \(leakedCount) marker processes for \(marker)")
                }
            }

            if !failures.isEmpty {
                break
            }
        }

        let cycleSummary = MetricSummary(values: cycleValues)
        let rssSummary = MetricSummary(values: rssGrowthValues)
        let leakedSummary = MetricSummary(values: leakedProcessValues)

        if cycleSummary.max >= 2_500 {
            failures.append("lifecycle cycle max \(cycleSummary.max)ms >= 2500ms hard max")
        }
        if cycleSummary.p95 >= 1_500 {
            failures.append("lifecycle cycle p95 \(cycleSummary.p95)ms >= 1500ms target")
        }
        if rssSummary.max >= 50 {
            failures.append("lifecycle RSS growth \(rssSummary.max)MB >= 50MB hard max")
        }
        if leakedSummary.max > 0 {
            failures.append("lifecycle leaked process count \(leakedSummary.max) > 0")
        }

        return .init(
            type: failures.isEmpty ? .result : .error,
            id: id,
            code: failures.isEmpty ? nil : "benchmark_failed",
            message: failures.isEmpty ? nil : failures.joined(separator: "; "),
            bench: BenchReport(
                name: request.name,
                runs: cycleValues.count,
                warmup: request.warmup,
                budgets: [
                    "cycle_hard_max_ms": 2_500,
                    "cycle_target_p95_ms": 1_500,
                    "rss_growth_hard_max_mb": 50,
                    "leaked_processes_hard_max": 0
                ],
                metrics: [
                    "lifecycle_cycle_ms": cycleSummary,
                    "rss_growth_mb": rssSummary,
                    "leaked_processes": leakedSummary
                ],
                failures: failures
            )
        )
    }

    private func runLifecycleSourceCancellation(marker: String) -> [String] {
        let token = CommandCancellationToken()
        let rowsStarted = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let errorLock = NSLock()
        var sourceError: Error?

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                errorLock.withLock {
                    sourceError = CommandRunError.cancelled(command: "lifecycle source benchmark app unavailable")
                }
                finished.signal()
                return
            }

            do {
                try self.sourceRunner.streamRows(
                    command: "python3 -c 'import time; time.sleep(30)' \(marker) & printf 'ready\\n'; wait",
                    cwd: FileManager.default.currentDirectoryPath,
                    timeoutSeconds: 10,
                    cancellationToken: token
                ) { rows in
                    if !rows.isEmpty {
                        rowsStarted.signal()
                    }
                }
            } catch {
                errorLock.withLock {
                    sourceError = error
                }
            }
            finished.signal()
        }

        var failures: [String] = []
        if rowsStarted.wait(timeout: .now() + 1) == .timedOut {
            failures.append("lifecycle source process did not start for \(marker)")
        }

        token.cancel()
        if finished.wait(timeout: .now() + 2) == .timedOut {
            failures.append("lifecycle source process did not stop after cancellation for \(marker)")
        }

        let error = errorLock.withLock { sourceError }
        if let error, !isCancellation(error) {
            failures.append("lifecycle source failed unexpectedly for \(marker): \(error)")
        }

        failures.append(contentsOf: waitForNoProcesses(containing: marker))
        return failures
    }

    private func runLifecyclePreviewCancellation(marker: String) -> [String] {
        let token = CommandCancellationToken()
        let finished = DispatchSemaphore(value: 0)
        let errorLock = NSLock()
        var previewError: Error?

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                errorLock.withLock {
                    previewError = CommandRunError.cancelled(command: "lifecycle preview benchmark app unavailable")
                }
                finished.signal()
                return
            }

            do {
                _ = try self.previewRunner.renderPreview(
                    template: "python3 -c 'import time; time.sleep(30)' \(marker)",
                    row: "bench-row",
                    cwd: FileManager.default.currentDirectoryPath,
                    timeoutSeconds: 10,
                    cancellationToken: token
                )
            } catch {
                errorLock.withLock {
                    previewError = error
                }
            }
            finished.signal()
        }

        var failures: [String] = []
        if !waitForProcessStart(containing: marker) {
            failures.append("lifecycle preview process did not start for \(marker)")
        }

        token.cancel()
        if finished.wait(timeout: .now() + 2) == .timedOut {
            failures.append("lifecycle preview process did not stop after cancellation for \(marker)")
        }

        let error = errorLock.withLock { previewError }
        if let error, !isCancellation(error) {
            failures.append("lifecycle preview failed unexpectedly for \(marker): \(error)")
        }

        failures.append(contentsOf: waitForNoProcesses(containing: marker))
        return failures
    }

    private func waitForProcessStart(containing marker: String) -> Bool {
        for _ in 0..<20 {
            if processCount(containing: marker) > 0 {
                return true
            }
            usleep(50_000)
        }
        return false
    }

    private func waitForNoProcesses(containing marker: String) -> [String] {
        for _ in 0..<30 {
            if processCount(containing: marker) == 0 {
                return []
            }
            usleep(50_000)
        }
        return ["processes containing marker \(marker) remained after cancellation"]
    }

    private func processCount(containing marker: String) -> Int {
        guard let output = processOutput(
            executable: "/bin/ps",
            arguments: ["-axo", "command="]
        ) else {
            return 0
        }

        return output
            .split(whereSeparator: \.isNewline)
            .filter { $0.contains(marker) }
            .count
    }

    private func residentMemoryMB() -> Double {
        guard let output = processOutput(
            executable: "/bin/ps",
            arguments: ["-o", "rss=", "-p", String(getpid())]
        ),
            let rssKB = Double(output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return 0
        }

        return rssKB / 1024
    }

    private func processOutput(executable: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        } catch {
            return nil
        }
    }

    private func runPanelBench(_ request: BenchRequest, id: String?) -> PaletteResponse {
        let totalRuns = max(1, request.runs + request.warmup)
        var values: [Double] = []

        for index in 0..<totalRuns {
            let duration = DispatchQueue.main.sync {
                panelController.benchmarkPanelShow(title: "bench \(index + 1)")
            }
            if index >= request.warmup {
                values.append(duration)
            }
        }

        let summary = MetricSummary(values: values)
        var failures: [String] = []
        if summary.max >= 200 {
            failures.append("panel max \(summary.max)ms >= 200ms hard max")
        }
        if summary.p95 >= 75 {
            failures.append("panel p95 \(summary.p95)ms >= 75ms target")
        }

        return .init(
            type: failures.isEmpty ? .result : .error,
            id: id,
            code: failures.isEmpty ? nil : "benchmark_failed",
            message: failures.isEmpty ? nil : failures.joined(separator: "; "),
            bench: BenchReport(
                name: request.name,
                runs: values.count,
                warmup: request.warmup,
                budgets: [
                    "hard_max_ms": 200,
                    "target_p95_ms": 75
                ],
                metrics: ["panel_show_ms": summary],
                failures: failures
            )
        )
    }

    private func runDirectHotKeyBench(_ request: BenchRequest, id: String?) -> PaletteResponse {
        let totalRuns = max(1, request.runs + request.warmup)
        var values: [Double] = []

        for index in 0..<totalRuns {
            var failures: [String] = []
            let duration = DispatchQueue.main.sync {
                panelController.hide()
                let start = ContinuousClock.now
                hotKeyController.simulateHotKeyForTests()
                return start
            }
            guard waitForPanelVisibleAfterHotKey(timeoutMs: 250) else {
                failures.append("Direct hotkey callback did not show the panel within 250ms")
                return hotKeyBenchResponse(
                    request: request,
                    id: id,
                    metricName: "hotkey_to_panel_ms",
                    values: values,
                    failures: failures
                )
            }
            let elapsed = milliseconds(duration.duration(to: ContinuousClock.now))
            cancelActivePickerForBench()
            if index >= request.warmup {
                values.append(elapsed)
            }
        }

        return hotKeyBenchResponse(
            request: request,
            id: id,
            metricName: "hotkey_to_panel_ms",
            values: values,
            failures: []
        )
    }

    private func runCarbonHotKeyBench(_ request: BenchRequest, id: String?) -> PaletteResponse {
        let totalRuns = max(1, request.runs + request.warmup)
        var values: [Double] = []
        var failures: [String] = []

        for index in 0..<totalRuns {
            DispatchQueue.main.sync {
                panelController.hide()
            }

            let start = ContinuousClock.now
            let status = hotKeyController.postCarbonHotKeyEventForTests()
            if status != noErr {
                failures.append("Carbon hotkey event post failed: \(status)")
                break
            }
            guard waitForPanelVisibleAfterHotKey(timeoutMs: 250) else {
                failures.append("Carbon hotkey event did not show the panel within 250ms")
                break
            }
            let duration = milliseconds(start.duration(to: ContinuousClock.now))
            cancelActivePickerForBench()

            if index >= request.warmup {
                values.append(duration)
            }
        }

        return hotKeyBenchResponse(
            request: request,
            id: id,
            metricName: "carbon_hotkey_to_panel_ms",
            values: values,
            failures: failures
        )
    }

    private func runPhysicalHotKeyBench(_ request: BenchRequest, id: String?) -> PaletteResponse {
        let totalRuns = max(1, request.runs + request.warmup)
        var values: [Double] = []
        var failures: [String] = []

        for index in 0..<totalRuns {
            DispatchQueue.main.sync {
                panelController.hide()
            }

            let start = ContinuousClock.now
            let postResult = hotKeyController.postPhysicalHotKeyEventForTests()
            guard postResult.isPosted else {
                failures.append("Physical hotkey post failed: \(postResult.message)")
                break
            }
            guard waitForPanelVisibleAfterHotKey(timeoutMs: 250) else {
                failures.append("Physical hotkey event did not show the panel within 250ms")
                break
            }
            let duration = milliseconds(start.duration(to: ContinuousClock.now))
            cancelActivePickerForBench()

            if index >= request.warmup {
                values.append(duration)
            }
        }

        return hotKeyBenchResponse(
            request: request,
            id: id,
            metricName: "physical_hotkey_to_panel_ms",
            values: values,
            failures: failures
        )
    }

    private func hotKeyBenchResponse(
        request: BenchRequest,
        id: String?,
        metricName: String,
        values: [Double],
        failures existingFailures: [String]
    ) -> PaletteResponse {
        let summary = MetricSummary(values: values)
        var failures = existingFailures
        if summary.max >= 200 {
            failures.append("\(metricName) max \(summary.max)ms >= 200ms hard max")
        }
        if summary.p95 >= 75 {
            failures.append("\(metricName) p95 \(summary.p95)ms >= 75ms target")
        }

        return .init(
            type: failures.isEmpty ? .result : .error,
            id: id,
            code: failures.isEmpty ? nil : "benchmark_failed",
            message: failures.isEmpty ? nil : failures.joined(separator: "; "),
            bench: BenchReport(
                name: request.name,
                runs: values.count,
                warmup: request.warmup,
                budgets: [
                    "hard_max_ms": 200,
                    "target_p95_ms": 75
                ],
                metrics: [metricName: summary],
                failures: failures
            )
        )
    }

    private func benchmarkRows(count: Int) -> [String] {
        (0..<count).map { index in
            let module = index % 12
            let depth = index % 7
            return "src/module-\(module)/component-\(depth)/file-\(index).swift"
        }
    }

    private func benchmarkQueries(count: Int) -> [String] {
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

    private func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000
    }

    private func runOpenRequest(_ incomingRequest: PickerRequest) -> PaletteResponse {
        let request: PickerRequest
        do {
            request = try profileStore.resolvedRequest(for: incomingRequest)
        } catch {
            return .init(
                type: .error,
                id: incomingRequest.id,
                status: .error,
                code: "profile_failed",
                message: profileStoreLoadError.map { "\($0); \(error)" } ?? String(describing: error)
            )
        }

        guard beginActivePicker() else {
            return .init(
                type: .error,
                id: request.id,
                code: "picker_busy",
                message: "Another picker is already active."
            )
        }
        setLastCompletionReason("running:\(request.profile)")
        defer { endActivePicker() }

        let pasteTargetApplication = currentPasteTargetApplication()
        let box = PickerResponseBox()
        let semaphore = DispatchSemaphore(value: 0)

        func finish(_ response: PaletteResponse) {
            if box.finish(response) {
                if currentCompletionReason().hasPrefix("running:") {
                    setLastCompletionReason(completionReason(for: response))
                }
                cancelActiveWork()
                semaphore.signal()
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.panelController.setCompletion { [weak self] outcome in
                switch outcome {
                case let .selected(originalRows):
                    guard let self else {
                        finish(.init(
                            type: .error,
                            id: request.id,
                            status: .error,
                            code: "app_unavailable",
                            message: "The app delegate was released before selection delivery."
                        ))
                        return
                    }
                    self.handleSelection(
                        originalRows: originalRows,
                        request: request,
                        pasteTargetApplication: pasteTargetApplication,
                        finish: finish
                    )
                case .cancelled:
                    self?.setLastCompletionReason("panel_cancelled")
                    finish(.init(type: .result, id: request.id, status: .cancelled))
                }
            }
            self?.panelController.showPlaceholder(
                title: request.profile,
                message: "Loading source rows..."
            )
            self?.configurePreviewUpdates(for: request)
        }

        loadSourceAsync(for: request, finish: finish)

        let timeoutSeconds = request.timeoutMs > 0 ? Double(request.timeoutMs) / 1000 : 300
        if semaphore.wait(timeout: .now() + timeoutSeconds) == .timedOut {
            setLastCompletionReason("request_timeout")
            cancelActiveWork()
            DispatchQueue.main.async { [weak self] in
                self?.panelController.clearCompletion()
                self?.panelController.clearActiveRowChangeHandler()
                self?.panelController.hide()
            }
            return .init(
                type: .error,
                id: request.id,
                code: "timeout",
                message: "Picker timed out after \(timeoutSeconds)s."
            )
        }

        DispatchQueue.main.async { [weak self] in
            self?.panelController.clearCompletion()
            self?.panelController.clearActiveRowChangeHandler()
        }

        return box.response ?? .init(type: .result, id: request.id, status: .cancelled)
    }

    private func handleSelection(
        originalRows: [String],
        request: PickerRequest,
        pasteTargetApplication: NSRunningApplication?,
        finish: @escaping (PaletteResponse) -> Void
    ) {
        if case let .twoStage(source) = request.source {
            continueTwoStage(
                source,
                firstSelection: originalRows,
                request: request,
                pasteTargetApplication: pasteTargetApplication,
                finish: finish
            )
            return
        }

        deliverSelection(
            originalRows: originalRows,
            request: request,
            pasteTargetApplication: pasteTargetApplication,
            finish: finish
        )
    }

    private func continueTwoStage(
        _ source: TwoStageSource,
        firstSelection originalRows: [String],
        request: PickerRequest,
        pasteTargetApplication: NSRunningApplication?,
        finish: @escaping (PaletteResponse) -> Void
    ) {
        guard let originalRow = originalRows.first else {
            finish(.init(type: .result, id: request.id, status: .noMatch))
            return
        }

        let firstStageRequest = source.first.resolvedRequest(base: request)
        let selectedText = RowFormatting.selectedText(
            for: originalRow,
            display: firstStageRequest.display,
            result: firstStageRequest.result
        )
        let secondStageRequest = source.second.resolvedRequest(base: request, selectedText: selectedText)

        cancelActiveWork()

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                finish(.init(
                    type: .error,
                    id: request.id,
                    status: .error,
                    code: "app_unavailable",
                    message: "The app delegate was released before second-stage selection delivery."
                ))
                return
            }

            self.panelController.setCompletion { [weak self] outcome in
                switch outcome {
                case let .selected(originalRows):
                    guard let self else {
                        finish(.init(
                            type: .error,
                            id: secondStageRequest.id,
                            status: .error,
                            code: "app_unavailable",
                            message: "The app delegate was released before second-stage selection delivery."
                        ))
                        return
                    }
                    self.deliverSelection(
                        originalRows: originalRows,
                        request: secondStageRequest,
                        pasteTargetApplication: pasteTargetApplication,
                        finish: finish
                    )
                case .cancelled:
                    self?.setLastCompletionReason("second_stage_panel_cancelled")
                    finish(.init(type: .result, id: secondStageRequest.id, status: .cancelled))
                }
            }
            self.panelController.showPlaceholder(
                title: secondStageRequest.profile,
                message: "Loading source rows..."
            )
            self.configurePreviewUpdates(for: secondStageRequest)
        }

        loadSourceAsync(for: secondStageRequest, finish: finish)
    }

    private func loadSourceAsync(
        for request: PickerRequest,
        finish: @escaping (PaletteResponse) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                return
            }

            do {
                try self.loadSource(for: request)
            } catch CommandRunError.cancelled {
                self.setLastCompletionReason("source_cancelled")
                finish(.init(type: .result, id: request.id, status: .cancelled))
            } catch {
                DispatchQueue.main.async {
                    self.panelController.showError(
                        title: request.profile,
                        message: String(describing: error)
                    )
                }
                self.setLastCompletionReason("source_failed")
                finish(.init(
                    type: .error,
                    id: request.id,
                    code: "source_failed",
                    message: String(describing: error)
                ))
            }
        }
    }

    private func deliverSelection(
        originalRows: [String],
        request: PickerRequest,
        pasteTargetApplication: NSRunningApplication?,
        finish: @escaping (PaletteResponse) -> Void
    ) {
        let selectedTexts = originalRows.map {
            RowFormatting.selectedText(for: $0, display: request.display, result: request.result)
        }
        let selectedText = selectedTexts.count == 1
            ? selectedTexts[0]
            : RowFormatting.join(selectedTexts, mode: request.result.join)
        let mode = effectiveResultMode(for: request)

        cancelActiveWork()

        switch mode {
        case .return:
            finish(selectedResponse(id: request.id, text: selectedText, items: selectedTexts))
        case .copy:
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(selectedText, forType: .string)
            finish(selectedResponse(id: request.id, text: selectedText, items: selectedTexts))
        case .paste:
            do {
                try pasteSelectedText(selectedText, targetApplication: pasteTargetApplication)
                finish(selectedResponse(id: request.id, text: selectedText, items: selectedTexts))
            } catch {
                finish(.init(
                    type: .error,
                    id: request.id,
                    status: .error,
                    code: "paste_failed",
                    message: String(describing: error)
                ))
            }
        case .open:
            guard openSelectedValues(selectedTexts) else {
                finish(.init(
                    type: .error,
                    id: request.id,
                    status: .error,
                    code: "open_failed",
                    message: "Could not open selected value: \(selectedText)"
                ))
                return
            }
            finish(selectedResponse(id: request.id, text: selectedText, items: selectedTexts))
        case .command:
            runResultCommand(
                originalRows: originalRows,
                selectedText: selectedText,
                selectedTexts: selectedTexts,
                request: request,
                finish: finish
            )
        case .ignore:
            finish(.init(type: .result, id: request.id, status: .selected))
        }
    }

    private func effectiveResultMode(for request: PickerRequest) -> ResultMode {
        request.result.mode == .return ? request.resultMode : request.result.mode
    }

    private func selectedResponse(id: String, text: String, items: [String]? = nil) -> PaletteResponse {
        .init(
            type: .result,
            id: id,
            status: .selected,
            text: text,
            items: items ?? [text]
        )
    }

    private func pasteSelectedText(_ text: String, targetApplication: NSRunningApplication?) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw PasteDeliveryError.pasteboardWriteFailed
        }

        if let logPath = ProcessInfo.processInfo.environment["FZF_PALETTE_PASTE_LOG"], !logPath.isEmpty {
            guard recordText(text, to: logPath) else {
                throw PasteDeliveryError.logWriteFailed(logPath)
            }
            return
        }

        guard AXIsProcessTrusted() else {
            throw PasteDeliveryError.accessibilityNotTrusted
        }

        guard let targetApplication else {
            throw PasteDeliveryError.missingTargetApplication
        }

        if targetApplication.processIdentifier != NSRunningApplication.current.processIdentifier {
            guard targetApplication.activate(options: []) else {
                throw PasteDeliveryError.targetActivationFailed
            }
            usleep(50_000)
        }

        try postPasteShortcut()
    }

    private func currentPasteTargetApplication() -> NSRunningApplication? {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        guard application.processIdentifier != NSRunningApplication.current.processIdentifier else {
            return nil
        }

        return application
    }

    private func resolveProgramContextForHotKey() -> ProgramContext? {
        let resolver = ProgramContextResolver(environment: programContextEnvironment())
        return resolver.resolve(frontmostApplication: frontmostApplicationForContext())
    }

    private func programContextEnvironment() -> [String: String] {
        environmentSnapshot.values.merging(ProcessInfo.processInfo.environment) { _, processValue in
            processValue
        }
    }

    private func frontmostApplicationForContext() -> FrontmostApplicationInfo? {
        let environment = ProcessInfo.processInfo.environment
        let hasTestFrontmostOverride = environment["FZF_PALETTE_TEST_FRONTMOST_APP_NAME"] != nil
            || environment["FZF_PALETTE_TEST_FRONTMOST_APP_BUNDLE_ID"] != nil
        if isTestControlEnabled, hasTestFrontmostOverride {
            let pid = environment["FZF_PALETTE_TEST_FRONTMOST_APP_PID"].flatMap(Int32.init)
            return FrontmostApplicationInfo(
                name: environment["FZF_PALETTE_TEST_FRONTMOST_APP_NAME"],
                bundleIdentifier: environment["FZF_PALETTE_TEST_FRONTMOST_APP_BUNDLE_ID"],
                processIdentifier: pid
            )
        }

        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != NSRunningApplication.current.processIdentifier else {
            return nil
        }

        return FrontmostApplicationInfo(
            name: application.localizedName,
            bundleIdentifier: application.bundleIdentifier,
            processIdentifier: application.processIdentifier
        )
    }

    private func setLastProgramContext(_ context: ProgramContext?) {
        programContextLock.withLock {
            lastProgramContext = context
        }
    }

    private func currentProgramContext() -> ProgramContext? {
        programContextLock.withLock {
            lastProgramContext
        }
    }

    private func setLastCompletionReason(_ reason: String) {
        completionReasonLock.withLock {
            lastCompletionReason = reason
        }
    }

    private func currentCompletionReason() -> String {
        completionReasonLock.withLock {
            lastCompletionReason
        }
    }

    private func completionReason(for response: PaletteResponse) -> String {
        if response.type == .error {
            return response.code.map { "error:\($0)" } ?? "error"
        }

        switch response.status {
        case .selected:
            return "selected"
        case .cancelled:
            return "cancelled"
        case .noMatch:
            return "no_match"
        case .error:
            return response.code.map { "error:\($0)" } ?? "error"
        case nil:
            return response.code ?? response.type.rawValue
        }
    }

    private func postPasteShortcut() throws {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            throw PasteDeliveryError.pasteEventCreationFailed
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func postPhysicalTextForTests(_ text: String) -> PhysicalKeyboardPostResult {
        guard AXIsProcessTrusted() else {
            return .accessibilityNotTrusted
        }
        guard !text.isEmpty else {
            return .missingText
        }
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return .eventCreationFailed
        }
        source.localEventsSuppressionInterval = 0

        for codeUnit in text.utf16 {
            guard postUnicodeKeyboardEvent(source: source, codeUnit: codeUnit, keyDown: true),
                  postUnicodeKeyboardEvent(source: source, codeUnit: codeUnit, keyDown: false) else {
                return .eventCreationFailed
            }
        }
        return .posted
    }

    private func postPhysicalKeyForTests(_ key: String) -> PhysicalKeyboardPostResult {
        guard AXIsProcessTrusted() else {
            return .accessibilityNotTrusted
        }
        guard let keyCode = physicalKeyboardKeyCode(for: key) else {
            return .unsupportedKey(key)
        }
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return .eventCreationFailed
        }
        source.localEventsSuppressionInterval = 0

        guard postKeyboardEvent(source: source, keyCode: keyCode, keyDown: true),
              postKeyboardEvent(source: source, keyCode: keyCode, keyDown: false) else {
            return .eventCreationFailed
        }
        return .posted
    }

    private func postUnicodeKeyboardEvent(source: CGEventSource, codeUnit: UTF16.CodeUnit, keyDown: Bool) -> Bool {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown) else {
            return false
        }
        var unit = codeUnit
        event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
        event.post(tap: .cghidEventTap)
        return true
    }

    private func postKeyboardEvent(source: CGEventSource, keyCode: CGKeyCode, keyDown: Bool) -> Bool {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else {
            return false
        }
        event.post(tap: .cghidEventTap)
        return true
    }

    private func physicalKeyboardKeyCode(for key: String) -> CGKeyCode? {
        switch key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "return", "enter":
            return CGKeyCode(kVK_Return)
        case "escape", "esc":
            return CGKeyCode(kVK_Escape)
        case "up", "arrowup":
            return CGKeyCode(kVK_UpArrow)
        case "down", "arrowdown":
            return CGKeyCode(kVK_DownArrow)
        case "left", "arrowleft":
            return CGKeyCode(kVK_LeftArrow)
        case "right", "arrowright":
            return CGKeyCode(kVK_RightArrow)
        case "tab":
            return CGKeyCode(kVK_Tab)
        case "space":
            return CGKeyCode(kVK_Space)
        case "delete", "backspace":
            return CGKeyCode(kVK_Delete)
        default:
            return nil
        }
    }

    private func openSelectedValues(_ values: [String]) -> Bool {
        if let logPath = ProcessInfo.processInfo.environment["FZF_PALETTE_OPEN_LOG"], !logPath.isEmpty {
            return recordOpenValues(values, to: logPath)
        }
        return values.allSatisfy(openSelectedValue(_:))
    }

    private func recordOpenValues(_ values: [String], to logPath: String) -> Bool {
        let body = values.joined(separator: "\n") + "\n"
        return recordText(body, to: logPath)
    }

    private func recordText(_ text: String, to logPath: String) -> Bool {
        guard let data = text.data(using: .utf8) else {
            return false
        }

        let expandedPath = (logPath as NSString).expandingTildeInPath
        if !FileManager.default.fileExists(atPath: expandedPath) {
            return FileManager.default.createFile(atPath: expandedPath, contents: data)
        }

        do {
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: expandedPath))
            defer {
                try? handle.close()
            }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            return true
        } catch {
            return false
        }
    }

    private func openSelectedValue(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }

        if let url = URL(string: trimmed), url.scheme != nil {
            return NSWorkspace.shared.open(url)
        }

        return NSWorkspace.shared.open(URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath))
    }

    private func runResultCommand(
        originalRows: [String],
        selectedText: String,
        selectedTexts: [String],
        request: PickerRequest,
        finish: @escaping (PaletteResponse) -> Void
    ) {
        guard let template = request.result.command?.trimmingCharacters(in: .whitespacesAndNewlines),
              !template.isEmpty else {
            finish(.init(
                type: .error,
                id: request.id,
                status: .error,
                code: "missing_result_command",
                message: "Result mode command requires --result-command or a profile result command."
            ))
            return
        }

        let command = PlaceholderExpansion.expand(
            template: template,
            row: originalRows.count == 1 ? originalRows[0] : RowFormatting.join(originalRows, mode: request.result.join),
            delimiter: request.display.delimiter,
            query: request.query
        )
        let token = CommandCancellationToken()
        setActiveResultToken(token)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                finish(.init(
                    type: .error,
                    id: request.id,
                    status: .error,
                    code: "app_unavailable",
                    message: "The app delegate was released before result command delivery."
                ))
                return
            }

            do {
                _ = try self.resultCommandRunner.run(
                    command,
                    cwd: request.cwd,
                    environment: self.environmentSnapshot.values.merging(request.env) { _, override in override },
                    timeoutSeconds: request.timeoutMs > 0 ? Double(request.timeoutMs) / 1000 : 10,
                    cancellationToken: token
                )
                self.clearActiveResultToken(token)
                finish(self.selectedResponse(id: request.id, text: selectedText, items: selectedTexts))
            } catch CommandRunError.cancelled {
                self.clearActiveResultToken(token)
                finish(.init(type: .result, id: request.id, status: .cancelled))
            } catch {
                self.clearActiveResultToken(token)
                finish(.init(
                    type: .error,
                    id: request.id,
                    status: .error,
                    code: "result_command_failed",
                    message: String(describing: error)
                ))
            }
        }
    }

    private func loadSource(for request: PickerRequest) throws {
        let fzfOptions = effectiveFzfOptions(for: request)
        switch request.source {
        case .staticItems(let items):
            DispatchQueue.main.async {
                self.configurePreviewUpdates(for: request)
                self.panelController.showRows(
                    title: request.profile,
                    rows: items,
                    display: request.display,
                    preview: self.previewPlaceholder(for: request, rows: items),
                    previewConfig: request.preview,
                    allowsMultipleSelection: self.isMultiSelectEnabled(fzfOptions: fzfOptions),
                    allowsPreviewToggle: self.isPreviewToggleEnabled(fzfOptions: fzfOptions),
                    initialQuery: request.query,
                    searchOptions: FzfRuntimeOptions.searchOptions(fzfOptions)
                )
            }
        case .stdin:
            let rows = (request.input ?? "")
                .split(whereSeparator: \.isNewline)
                .map(String.init)
            DispatchQueue.main.async {
                self.configurePreviewUpdates(for: request)
                self.panelController.showRows(
                    title: request.profile,
                    rows: rows,
                    display: request.display,
                    preview: self.previewPlaceholder(for: request, rows: rows),
                    previewConfig: request.preview,
                    allowsMultipleSelection: self.isMultiSelectEnabled(fzfOptions: fzfOptions),
                    allowsPreviewToggle: self.isPreviewToggleEnabled(fzfOptions: fzfOptions),
                    initialQuery: request.query,
                    searchOptions: FzfRuntimeOptions.searchOptions(fzfOptions)
                )
            }
        case .command(let command):
            try streamSourceCommand(
                command: command,
                request: request
            )
        case .twoStage(let source):
            try loadSource(for: source.first.resolvedRequest(base: request))
        case .profile:
            let command = FzfSourceCommands.command(
                forProfile: request.profile,
                environment: environmentSnapshot.values
            )
            try streamSourceCommand(
                command: command,
                request: request
            )
        }
    }

    private func streamSourceCommand(command: String, request: PickerRequest) throws {
        let sourceToken = CommandCancellationToken()
        let fzfOptions = effectiveFzfOptions(for: request)
        setActiveSourceToken(sourceToken)
        defer { clearActiveSourceToken(sourceToken) }

        DispatchQueue.main.async {
            self.configurePreviewUpdates(for: request)
            self.panelController.showRows(
                title: request.profile,
                rows: [],
                display: request.display,
                preview: "Streaming source rows...",
                previewConfig: request.preview,
                allowsMultipleSelection: self.isMultiSelectEnabled(fzfOptions: fzfOptions),
                allowsPreviewToggle: self.isPreviewToggleEnabled(fzfOptions: fzfOptions),
                initialQuery: request.query,
                searchOptions: FzfRuntimeOptions.searchOptions(fzfOptions)
            )
        }

        try sourceRunner.streamRows(
            command: command,
            cwd: request.cwd,
            environment: environmentSnapshot.values.merging(request.env) { _, override in override },
            timeoutSeconds: request.timeoutMs > 0 ? Double(request.timeoutMs) / 1000 : 10,
            cancellationToken: sourceToken
        ) { [weak self] rows in
            DispatchQueue.main.async {
                self?.panelController.appendRows(
                    rows,
                    title: request.profile,
                    display: request.display
                )
            }
        }
    }

    private func previewPlaceholder(for request: PickerRequest, rows: [String]) -> String {
        guard request.preview != nil, !rows.isEmpty else {
            return "\(rows.count) source rows loaded."
        }
        return "Loading preview..."
    }

    private func configurePreviewUpdates(for request: PickerRequest) {
        guard request.preview != nil else {
            panelController.clearActiveRowChangeHandler()
            return
        }

        panelController.setActiveRowChangeHandler({ [weak self] row in
            self?.schedulePreview(for: request, row: row?.original)
        }, notifyImmediately: false)
    }

    private func schedulePreview(for request: PickerRequest, row: String?) {
        guard let preview = request.preview, let row else {
            cancelPreviewWork()
            panelController.showPreview("No preview row")
            return
        }

        let generation = cancelPreviewWork()
        let workItem = DispatchWorkItem { [weak self] in
            self?.runPreview(preview: preview, row: row, request: request, generation: generation)
        }

        activeWorkLock.withLock {
            activePreviewDebounce = workItem
        }

        panelController.showPreview("Loading preview...")
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + .milliseconds(max(0, preview.debounceMs)),
            execute: workItem
        )
    }

    private func runPreview(
        preview: PreviewConfig,
        row: String,
        request: PickerRequest,
        generation: Int
    ) {
        guard isCurrentPreviewGeneration(generation) else {
            return
        }

        let token = CommandCancellationToken()
        setActivePreviewToken(token)

        do {
            let text = try previewRunner.renderPreview(
                template: preview.command,
                row: row,
                cwd: request.cwd,
                lines: 20,
                environment: environmentSnapshot.values.merging(request.env) { _, override in override },
                timeoutSeconds: 2,
                cancellationToken: token
            )
            clearActivePreviewToken(token)

            let scrollTarget = preview.layout.scrollTarget(
                row: row,
                delimiter: request.display.delimiter
            )
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isCurrentPreviewGeneration(generation) else {
                    return
                }
                self.panelController.showPreview(text, scrollTarget: scrollTarget)
            }
        } catch CommandRunError.cancelled {
            clearActivePreviewToken(token)
            return
        } catch {
            clearActivePreviewToken(token)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isCurrentPreviewGeneration(generation) else {
                    return
                }
                self.panelController.showPreview("Preview failed: \(error)")
            }
        }
    }

    @discardableResult
    private func cancelPreviewWork() -> Int {
        activeWorkLock.withLock {
            previewGeneration += 1
            activePreviewDebounce?.cancel()
            activePreviewDebounce = nil
            activePreviewToken?.cancel()
            activePreviewToken = nil
            return previewGeneration
        }
    }

    private func beginActivePicker() -> Bool {
        activePickerLock.lock()
        defer { activePickerLock.unlock() }
        guard !hasActivePicker else {
            return false
        }
        hasActivePicker = true
        return true
    }

    private func endActivePicker() {
        activePickerLock.lock()
        hasActivePicker = false
        activePickerLock.unlock()
    }

    private func isActivePickerRunning() -> Bool {
        activePickerLock.lock()
        defer { activePickerLock.unlock() }
        return hasActivePicker
    }

    private func cancelActiveWork() {
        let tokens: (CommandCancellationToken?, CommandCancellationToken?, CommandCancellationToken?) = activeWorkLock.withLock {
            previewGeneration += 1
            activePreviewDebounce?.cancel()
            activePreviewDebounce = nil
            let tokens = (activeSourceToken, activePreviewToken, activeResultToken)
            activeSourceToken = nil
            activePreviewToken = nil
            activeResultToken = nil
            return tokens
        }
        tokens.0?.cancel()
        tokens.1?.cancel()
        tokens.2?.cancel()
    }

    private func setActiveSourceToken(_ token: CommandCancellationToken) {
        let oldToken = activeWorkLock.withLock { () -> CommandCancellationToken? in
            let oldToken = activeSourceToken
            activeSourceToken = token
            return oldToken
        }
        oldToken?.cancel()
    }

    private func clearActivePreviewToken(_ token: CommandCancellationToken) {
        activeWorkLock.withLock {
            if activePreviewToken === token {
                activePreviewToken = nil
            }
        }
    }

    private func clearActiveResultToken(_ token: CommandCancellationToken) {
        activeWorkLock.withLock {
            if activeResultToken === token {
                activeResultToken = nil
            }
        }
    }

    private func clearActiveSourceToken(_ token: CommandCancellationToken) {
        activeWorkLock.withLock {
            if activeSourceToken === token {
                activeSourceToken = nil
            }
        }
    }

    private func setActivePreviewToken(_ token: CommandCancellationToken) {
        let oldToken = activeWorkLock.withLock { () -> CommandCancellationToken? in
            let oldToken = activePreviewToken
            activePreviewToken = token
            return oldToken
        }
        oldToken?.cancel()
    }

    private func setActiveResultToken(_ token: CommandCancellationToken) {
        let oldToken = activeWorkLock.withLock { () -> CommandCancellationToken? in
            let oldToken = activeResultToken
            activeResultToken = token
            return oldToken
        }
        oldToken?.cancel()
    }

    private func nextPreviewGeneration() -> Int {
        activeWorkLock.withLock {
            previewGeneration += 1
            return previewGeneration
        }
    }

    private func isCurrentPreviewGeneration(_ generation: Int) -> Bool {
        activeWorkLock.withLock {
            previewGeneration == generation
        }
    }

    private func appStatus() -> AppStatus {
        let settings = settingsStore.load()
        return AppStatus(
            running: true,
            pid: getpid(),
            socketPath: FzfPalettePaths.socketURL.path,
            uptimeMs: UInt64(Date().timeIntervalSince(startDate) * 1000),
            version: "0.1.0-dev",
            logDirectory: FzfPalettePaths.logDirectory.path,
            activePicker: isActivePickerRunning(),
            panelVisible: panelVisibleForStatus(),
            visibleRows: visibleRowCountForStatus(),
            previewVisible: previewVisibleForStatus(),
            prompt: promptForStatus(),
            header: headerForStatus(),
            pointer: pointerForStatus(),
            marker: markerForStatus(),
            info: infoForStatus(),
            hotkey: hotKeyController.activeBinding?.displayString,
            hotkeyRegistered: hotKeyController.isRegistered,
            hotkeyError: hotKeyConfigurationError ?? hotKeyController.registrationError,
            hotkeys: hotKeyController.hotKeyStatuses,
            settingsHotkey: settings.hotkey,
            settingsProfile: settings.profile,
            settingsVisible: settingsWindowVisibleForStatus(),
            programContext: currentProgramContext(),
            lastCompletionReason: currentCompletionReason()
        )
    }

    private var isTestControlEnabled: Bool {
        ProcessInfo.processInfo.environment["FZF_PALETTE_ENABLE_TEST_CONTROL"] == "1"
    }

    private func configuredProfileHotKeys() -> [ProfileHotKeyBinding] {
        let environment = ProcessInfo.processInfo.environment
        var bindings: [ProfileHotKeyBinding] = []
        var errors: [String] = []

        if let rawValue = environment["FZF_PALETTE_HOTKEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawValue.isEmpty {
            let profile = environment["FZF_PALETTE_HOTKEY_PROFILE"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            do {
                bindings.append(ProfileHotKeyBinding(
                    profile: profile?.isEmpty == false ? profile! : "default",
                    binding: try HotKeyBinding.parse(rawValue)
                ))
            } catch {
                errors.append("Invalid FZF_PALETTE_HOTKEY '\(rawValue)': \(error). Falling back to \(HotKeyBinding.default.displayString).")
                bindings.append(ProfileHotKeyBinding(profile: "default", binding: .default))
            }
        }

        let settings = settingsStore.load()
        if let rawValue = settings.hotkey?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawValue.isEmpty {
            do {
                bindings.append(ProfileHotKeyBinding(
                    profile: settings.profile.isEmpty ? "default" : settings.profile,
                    binding: try HotKeyBinding.parse(rawValue)
                ))
            } catch {
                errors.append("Invalid settings hotkey '\(rawValue)': \(error).")
            }
        }

        bindings.append(contentsOf: profileStore.hotkeys)

        if bindings.isEmpty {
            bindings = [ProfileHotKeyBinding(profile: "default", binding: .default)]
        }

        var seenBindings: Set<String> = []
        let validatedBindings = bindings.compactMap { binding -> ProfileHotKeyBinding? in
            let key = binding.binding.displayString
            guard !seenBindings.contains(key) else {
                errors.append("Duplicate hotkey binding ignored: \(key)")
                return nil
            }
            seenBindings.insert(key)

            guard profileStore.profile(named: binding.profile) != nil else {
                errors.append("Hotkey \(key) references unknown profile: \(binding.profile)")
                return nil
            }
            return binding
        }

        hotKeyConfigurationError = errors.isEmpty ? nil : errors.joined(separator: "; ")
        if let hotKeyConfigurationError {
            logger.error("\(hotKeyConfigurationError, privacy: .public)")
        }
        return validatedBindings.isEmpty
            ? [ProfileHotKeyBinding(profile: "default", binding: .default)]
            : validatedBindings
    }

    private func reloadHotKeys() {
        hotKeyController.start(bindings: configuredProfileHotKeys()) { [weak self] binding in
            self?.showPaletteForHotKey(profile: binding.profile)
        }
    }

    private func saveSettings(_ settings: PaletteSettings) throws -> PaletteSettings {
        let profile = settings.profile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "default"
            : settings.profile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard profileStore.profile(named: profile) != nil else {
            throw SettingsValidationError.unknownProfile(profile)
        }

        let rawHotkey = settings.hotkey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let canonicalHotkey: String?
        if let rawHotkey, !rawHotkey.isEmpty {
            canonicalHotkey = try HotKeyBinding.parse(rawHotkey).displayString
        } else {
            canonicalHotkey = nil
        }

        let saved = PaletteSettings(hotkey: canonicalHotkey, profile: profile)
        settingsStore.save(saved)
        reloadHotKeys()
        return saved
    }

    private func settingsResponse(id: String?, settings: PaletteSettings? = nil) -> PaletteResponse {
        .init(
            type: .result,
            id: id,
            status: .selected,
            settings: settings ?? settingsStore.load()
        )
    }

    private func performSettingsWindowControl(_ action: @escaping (SettingsWindowController) -> Void) {
        if Thread.isMainThread {
            action(settingsWindowController)
        } else {
            DispatchQueue.main.sync {
                action(settingsWindowController)
            }
        }
    }

    private func settingsWindowVisibleForStatus() -> Bool {
        if Thread.isMainThread {
            return settingsWindowController.isVisible
        }
        return DispatchQueue.main.sync {
            settingsWindowController.isVisible
        }
    }

    private func effectiveFzfOptions(for request: PickerRequest) -> [String] {
        FzfDefaultOptions.arguments(environment: environmentSnapshot.values) + request.fzfOptions
    }

    private func isMultiSelectEnabled(fzfOptions: [String]) -> Bool {
        FzfRuntimeOptions.isMultiSelectEnabled(fzfOptions)
    }

    private func isPreviewToggleEnabled(fzfOptions: [String]) -> Bool {
        FzfRuntimeOptions.isPreviewToggleEnabled(fzfOptions)
    }

    private func performPanelControl(_ action: @escaping (PalettePanelController) -> Void) {
        if Thread.isMainThread {
            action(panelController)
        } else {
            DispatchQueue.main.sync {
                action(panelController)
            }
        }
    }

    private func visibleRowCountForStatus() -> Int {
        if Thread.isMainThread {
            return panelController.visibleRowCount
        }
        return DispatchQueue.main.sync {
            panelController.visibleRowCount
        }
    }

    private func panelVisibleForStatus() -> Bool {
        if Thread.isMainThread {
            return panelController.isPanelVisible
        }
        return DispatchQueue.main.sync {
            panelController.isPanelVisible
        }
    }

    private func waitForPanelVisibleAfterHotKey(timeoutMs: Int) -> Bool {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000)
        while Date() < deadline {
            if panelVisibleForStatus() {
                return true
            }
            usleep(1_000)
        }
        return panelVisibleForStatus()
    }

    private func waitForInactivePicker(timeoutMs: Int) {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000)
        while Date() < deadline {
            if !isActivePickerRunning() {
                return
            }
            usleep(1_000)
        }
    }

    private func cancelActivePickerForBench() {
        DispatchQueue.main.sync {
            panelController.cancelActivePicker()
            panelController.hide()
        }
        cancelActiveWork()
        waitForInactivePicker(timeoutMs: 250)
    }

    private func previewVisibleForStatus() -> Bool {
        if Thread.isMainThread {
            return panelController.isPreviewVisible
        }
        return DispatchQueue.main.sync {
            panelController.isPreviewVisible
        }
    }

    private func promptForStatus() -> String {
        if Thread.isMainThread {
            return panelController.currentPrompt
        }
        return DispatchQueue.main.sync {
            panelController.currentPrompt
        }
    }

    private func headerForStatus() -> String {
        if Thread.isMainThread {
            return panelController.currentHeader
        }
        return DispatchQueue.main.sync {
            panelController.currentHeader
        }
    }

    private func pointerForStatus() -> String? {
        if Thread.isMainThread {
            return panelController.currentPointer
        }
        return DispatchQueue.main.sync {
            panelController.currentPointer
        }
    }

    private func markerForStatus() -> String? {
        if Thread.isMainThread {
            return panelController.currentMarker
        }
        return DispatchQueue.main.sync {
            panelController.currentMarker
        }
    }

    private func infoForStatus() -> String? {
        if Thread.isMainThread {
            return panelController.currentInfo
        }
        return DispatchQueue.main.sync {
            panelController.currentInfo
        }
    }

    private func captureEnvironmentSnapshot() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", "env -0"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let shellSnapshot = EnvironmentSnapshot.parseNullSeparatedEnv(data)
                let merged = EnvironmentSnapshot().merged(with: shellSnapshot.values)
                DispatchQueue.main.async {
                    self?.environmentSnapshot = merged
                }
            } catch {
                self?.logger.error("Environment snapshot failed: \(String(describing: error))")
            }
        }
    }

    private func reloadProfileStore() {
        do {
            profileStore = try ProfileStore.load()
            profileStoreLoadError = nil
        } catch {
            profileStore = ProfileStore()
            profileStoreLoadError = "Profile config failed to load: \(error)"
            logger.error("\(self.profileStoreLoadError ?? "Profile config failed to load", privacy: .public)")
        }
    }
}

private final class PickerResponseBox {
    private let lock = NSLock()
    private(set) var response: PaletteResponse?

    func finish(_ response: PaletteResponse) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard self.response == nil else {
            return false
        }
        self.response = response
        return true
    }
}

private enum PasteDeliveryError: Error, CustomStringConvertible {
    case accessibilityNotTrusted
    case logWriteFailed(String)
    case missingTargetApplication
    case pasteboardWriteFailed
    case pasteEventCreationFailed
    case targetActivationFailed

    var description: String {
        switch self {
        case .accessibilityNotTrusted:
            return "Paste mode requires Accessibility permission so fzf-palette can send Cmd-V to the previous app."
        case let .logWriteFailed(path):
            return "Could not write paste test log: \(path)"
        case .missingTargetApplication:
            return "Paste mode could not identify the app that had focus before the palette opened."
        case .pasteboardWriteFailed:
            return "Paste mode could not write the selected text to the pasteboard."
        case .pasteEventCreationFailed:
            return "Paste mode could not create the Cmd-V keyboard event."
        case .targetActivationFailed:
            return "Paste mode could not restore focus to the app that was active before the palette opened."
        }
    }
}

private enum SettingsValidationError: Error, CustomStringConvertible {
    case unknownProfile(String)

    var description: String {
        switch self {
        case let .unknownProfile(profile):
            return "Unknown settings profile: \(profile)"
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
