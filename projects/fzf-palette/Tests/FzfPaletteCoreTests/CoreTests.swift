import Foundation
import XCTest
@testable import FzfPaletteCore

final class CoreTests: XCTestCase {
    func testWireProtocolRoundTripsStatusRequest() throws {
        let request = PaletteClientRequest(type: .status, id: "request-1")

        let data = try WireCoding.encodeLine(request)
        let decoded = try WireCoding.decodeRequest(data)

        XCTAssertEqual(decoded, request)

        let physicalHotKeyRequest = PaletteClientRequest(
            type: .testPhysicalHotkey,
            id: "physical-hotkey-1",
            query: "context-files"
        )
        let decodedPhysicalHotKeyRequest = try WireCoding.decodeRequest(WireCoding.encodeLine(physicalHotKeyRequest))
        XCTAssertEqual(decodedPhysicalHotKeyRequest, physicalHotKeyRequest)

        let physicalTypeRequest = PaletteClientRequest(
            type: .testPhysicalType,
            id: "physical-type-1",
            query: "banana"
        )
        let decodedPhysicalTypeRequest = try WireCoding.decodeRequest(WireCoding.encodeLine(physicalTypeRequest))
        XCTAssertEqual(decodedPhysicalTypeRequest, physicalTypeRequest)

        let physicalKeyRequest = PaletteClientRequest(
            type: .testPhysicalKey,
            id: "physical-key-1",
            query: "return"
        )
        let decodedPhysicalKeyRequest = try WireCoding.decodeRequest(WireCoding.encodeLine(physicalKeyRequest))
        XCTAssertEqual(decodedPhysicalKeyRequest, physicalKeyRequest)
    }

    func testWireProtocolRoundTripsSettingsRequestAndResponse() throws {
        let settings = PaletteSettings(hotkey: "shift+cmd+k", profile: "context-files")
        let request = PaletteClientRequest(type: .settingsSet, id: "settings-1", settings: settings)

        let decodedRequest = try WireCoding.decodeRequest(WireCoding.encodeLine(request))
        XCTAssertEqual(decodedRequest, request)

        let response = PaletteResponse(type: .result, id: "settings-1", status: .selected, settings: settings)
        let decodedResponse = try WireCoding.decodeResponse(WireCoding.encodeLine(response))
        XCTAssertEqual(decodedResponse, response)
    }

    func testPickerSourceRoundTripsCommand() throws {
        let request = PickerRequest(
            id: "picker-1",
            profile: "git-status",
            cwd: "/tmp",
            source: .command("git status -s"),
            fzfOptions: ["--ansi", "--preview", "~/bin/status-preview.sh {}"],
            preview: PreviewConfig(command: "~/bin/status-preview.sh {}")
        )

        let data = try WireCoding.encoder.encode(request)
        let decoded = try WireCoding.decoder.decode(PickerRequest.self, from: data)

        XCTAssertEqual(decoded, request)
    }

    func testPickerRequestRoundTripsCommandResultMode() throws {
        let request = PickerRequest(
            id: "picker-command-result",
            profile: "action",
            cwd: "/tmp",
            source: .command("printf 'friendly\\t/hidden/id\\n'"),
            display: DisplayConfig(
                delimiter: "\t",
                withNth: "1",
                prompt: "sessions>",
                header: "Pick a session",
                pointer: ">",
                marker: "*",
                info: "inline"
            ),
            result: ResultConfig(
                mode: .command,
                fields: "2",
                join: .newline,
                command: "do-something {}"
            ),
            resultMode: .command
        )

        let data = try WireCoding.encoder.encode(request)
        let decoded = try WireCoding.decoder.decode(PickerRequest.self, from: data)

        XCTAssertEqual(decoded, request)
        XCTAssertEqual(decoded.display.prompt, "sessions>")
        XCTAssertEqual(decoded.display.header, "Pick a session")
        XCTAssertEqual(decoded.display.pointer, ">")
        XCTAssertEqual(decoded.display.marker, "*")
        XCTAssertEqual(decoded.display.info, "inline")
    }

    func testClassifiesLocalFzfOptions() {
        let classifications = FzfOptionClassifier.classify([
            "--height", "40%",
            "--reverse",
            "--border",
            "--border-label", " repo picker ",
            "--extended",
            "--scheme=path",
            "--scheme=history",
            "--no-sort",
            "--exact",
            "-i",
            "+i",
            "-e",
            "+e",
            "-x",
            "+s",
            "-m",
            "+m",
            "-n2..,..",
            "--nth", "1",
            "--tiebreak=begin,end",
            "--tiebreak=chunk",
            "--bind", "ctrl-A:select-all,ctrl-d:deselect-all",
            "--color=fg:#f8f8f2",
            "--prompt", "sessions>",
            "--header=Pick a session",
            "--pointer", ">",
            "--marker=*",
            "--info=inline",
            "--preview", "git show --color=always {1}",
            "--preview-window=right:60%:wrap"
        ])

        XCTAssertFalse(classifications.contains { $0.disposition == .unsupported || $0.disposition == .error })
        XCTAssertTrue(classifications.contains { $0.option == "--height" && $0.disposition == .ignored })
        XCTAssertTrue(classifications.contains { $0.option == "--no-sort" && $0.disposition == .supported })
        XCTAssertTrue(classifications.contains { $0.option == "+s" && $0.disposition == .supported })
        XCTAssertTrue(classifications.contains { $0.option == "--prompt" && $0.disposition == .supported })
        XCTAssertTrue(classifications.contains { $0.option == "--header=Pick a session" && $0.disposition == .supported })
        XCTAssertTrue(classifications.contains { $0.option == "--pointer" && $0.disposition == .supported })
        XCTAssertTrue(classifications.contains { $0.option == "--marker=*" && $0.disposition == .supported })
        XCTAssertTrue(classifications.contains { $0.option == "--info=inline" && $0.disposition == .supported })
        XCTAssertTrue(classifications.contains { $0.option == "--bind" && $0.disposition == .supported })
        XCTAssertTrue(classifications.contains { $0.option == "--exact" && $0.disposition == .supported })
        XCTAssertTrue(classifications.contains { $0.option == "--extended" && $0.disposition == .supported })
        XCTAssertTrue(classifications.contains { $0.option == "--scheme=path" && $0.disposition == .supported })
        XCTAssertTrue(classifications.contains { $0.option == "--scheme=history" && $0.disposition == .supported })
        XCTAssertTrue(classifications.contains { $0.option == "--tiebreak=begin,end" && $0.disposition == .supported })
        XCTAssertTrue(classifications.contains { $0.option == "--tiebreak=chunk" && $0.disposition == .supported })
        XCTAssertTrue(classifications.contains { $0.option == "--border-label" && $0.disposition == .ignored })
    }

    func testRejectsUnsupportedBindActions() {
        let classifications = FzfOptionClassifier.classify(["--bind", "ctrl-r:reload(fd .)"])

        XCTAssertEqual(classifications.first?.disposition, .unsupported)
    }

    func testRejectsUnsupportedInfoModes() {
        let classifications = FzfOptionClassifier.classify(["--info=hidden"])

        XCTAssertEqual(classifications.first?.disposition, .unsupported)
    }

    func testRejectsUnsupportedSchemes() {
        let classifications = FzfOptionClassifier.classify(["--scheme=scoreless"])

        XCTAssertEqual(classifications.first?.disposition, .unsupported)
    }

    func testRejectsUnsupportedTiebreakCriteria() {
        XCTAssertEqual(FzfOptionClassifier.classify(["--tiebreak=score"]).first?.disposition, .unsupported)
        XCTAssertEqual(FzfOptionClassifier.classify(["--tiebreak=chunk,chunk"]).first?.disposition, .unsupported)
        XCTAssertEqual(FzfOptionClassifier.classify(["--tiebreak=index,begin"]).first?.disposition, .unsupported)
    }

    func testPreviewWindowLayoutParsesLocalRightAndUpForms() {
        XCTAssertEqual(
            PreviewWindowLayout.parse("right:60%:wrap"),
            PreviewWindowLayout(position: .right, sizeFraction: 0.6, wrap: true)
        )
        XCTAssertEqual(
            PreviewWindowLayout.parse("up:60%"),
            PreviewWindowLayout(position: .up, sizeFraction: 0.6, wrap: false)
        )
    }

    func testPreviewWindowLayoutKeepsScrollExpressionWithoutChangingDefaultPane() {
        XCTAssertEqual(
            PreviewWindowLayout.parse("+{2}-/2"),
            PreviewWindowLayout(position: .right, sizeFraction: 0.5, wrap: false, scrollExpression: "+{2}-/2")
        )
    }

    func testPreviewWindowLayoutResolvesScrollTargetFromRowField() {
        let layout = PreviewWindowLayout.parse("+{2}-/2")

        XCTAssertEqual(
            layout.scrollTarget(row: "Sources/App.swift:80:body", delimiter: ":"),
            PreviewScrollTarget(line: 80, centerInPreview: true)
        )
    }

    func testPreviewWindowLayoutResolvesLiteralScrollTarget() {
        XCTAssertEqual(
            PreviewWindowLayout.scrollTarget(expression: "+25", row: "ignored", delimiter: nil),
            PreviewScrollTarget(line: 25)
        )
        XCTAssertNil(PreviewWindowLayout.scrollTarget(expression: "+{2}", row: "missing-field", delimiter: ":"))
    }

    func testProfileValidationFindsUnsupportedOptions() {
        let profile = PickerProfile(
            name: "bad",
            title: "Bad",
            source: .command("printf 'a\\n'"),
            fzfOptions: ["--bind", "ctrl-r:reload(fd .)"]
        )

        XCTAssertTrue(profile.validationErrors().contains { $0.field == "fzfOptions" })
    }

    func testProfileValidationFindsEmptySourceCommand() {
        let profile = PickerProfile(
            name: "bad",
            title: "Bad",
            source: .command(" ")
        )

        XCTAssertTrue(profile.validationErrors().contains { $0.field == "source.command" })
    }

    func testProfileStoreLoadsConfigProfilesAndResolvesRequests() throws {
        let profile = PickerProfile(
            name: "config-test",
            title: "Config Test",
            source: .command("printf 'friendly\\t/hidden/profile.json\\n'"),
            query: "friendly",
            fzfOptions: ["--ansi", "--bind", "ctrl-/:toggle-preview"],
            display: DisplayConfig(
                ansi: true,
                delimiter: "\t",
                withNth: "1",
                prompt: "config>",
                header: "Config profile",
                pointer: ">",
                marker: "*",
                info: "inline"
            ),
            preview: PreviewConfig(command: "printf '%s' {}", window: "right:60%:wrap"),
            result: ResultConfig(mode: .return, fields: "2", join: .space)
        )
        let fileURL = try temporaryProfilesFile(profiles: [profile])
        let store = try ProfileStore.load(fileURL: fileURL)

        let resolved = try store.resolvedRequest(for: PickerRequest(profile: "config-test", cwd: "/tmp"))

        XCTAssertEqual(resolved.profile, "config-test")
        XCTAssertEqual(resolved.source, profile.source)
        XCTAssertEqual(resolved.query, "friendly")
        XCTAssertEqual(resolved.fzfOptions, profile.fzfOptions)
        XCTAssertEqual(resolved.display.delimiter, "\t")
        XCTAssertEqual(resolved.display.withNth, "1")
        XCTAssertEqual(resolved.display.prompt, "config>")
        XCTAssertEqual(resolved.preview, profile.preview)
        XCTAssertEqual(resolved.result.fields, "2")
        XCTAssertEqual(resolved.result.join, .space)
    }

    func testProfileStoreLoadsHotkeysFromConfigCollection() throws {
        let profile = PickerProfile(
            name: "config-test",
            title: "Config Test",
            source: .staticItems(["ok"])
        )
        let hotkey = ProfileHotKeyBinding(
            profile: "config-test",
            binding: try HotKeyBinding.parse("cmd+shift+k")
        )
        let fileURL = try temporaryProfilesFile(profiles: [profile], hotkeys: [hotkey])
        let store = try ProfileStore.load(fileURL: fileURL)

        XCTAssertEqual(store.hotkeys, [
            ProfileHotKeyBinding(
                profile: "config-test",
                binding: HotKeyBinding(modifiers: [.shift, .command], key: "k")
            )
        ])
    }

    func testProfileStoreLetsRequestOverridesWin() throws {
        let profile = PickerProfile(
            name: "config-test",
            title: "Config Test",
            source: .command("printf 'profile\\n'"),
            query: "profile",
            display: DisplayConfig(prompt: "profile>", header: "Profile header"),
            preview: PreviewConfig(command: "printf profile"),
            result: ResultConfig(fields: "1")
        )
        let store = ProfileStore(profiles: [profile])
        let resolved = try store.resolvedRequest(for: PickerRequest(
            profile: "config-test",
            query: "request",
            source: .command("printf 'request\\n'"),
            display: DisplayConfig(prompt: "request>"),
            preview: PreviewConfig(command: "printf request"),
            result: ResultConfig(fields: "2")
        ))

        XCTAssertEqual(resolved.query, "request")
        XCTAssertEqual(resolved.source, .command("printf 'request\\n'"))
        XCTAssertEqual(resolved.display.prompt, "request>")
        XCTAssertEqual(resolved.display.header, "Profile header")
        XCTAssertEqual(resolved.preview?.command, "printf request")
        XCTAssertEqual(resolved.result.fields, "2")
    }

    func testProfileStoreReportsUnknownProfile() {
        XCTAssertThrowsError(try ProfileStore().resolvedRequest(for: PickerRequest(profile: "missing"))) { error in
            XCTAssertEqual(error as? ProfileStoreError, .unknownProfile("missing"))
        }
    }

    func testProfileStoreIncludesContextFilesTwoStageProfile() throws {
        let request = try ProfileStore().resolvedRequest(for: PickerRequest(profile: "context-files"))
        guard case let .twoStage(source) = request.source else {
            return XCTFail("context-files should resolve to a two-stage source")
        }

        let rootRequest = source.first.resolvedRequest(base: request)
        XCTAssertEqual(rootRequest.display.delimiter, "\t")
        XCTAssertEqual(rootRequest.display.withNth, "1")
        XCTAssertEqual(rootRequest.result.fields, "2")
        XCTAssertEqual(
            RowFormatting.selectedText(
                for: "fzf-palette\t/tmp/fzf-palette",
                display: rootRequest.display,
                result: rootRequest.result
            ),
            "/tmp/fzf-palette"
        )

        let filesRequest = source.second.resolvedRequest(base: request, selectedText: "/tmp/fzf-palette")
        guard case let .command(command) = filesRequest.source else {
            return XCTFail("context-files second stage should resolve to a command source")
        }

        XCTAssertTrue(command.contains("root=/tmp/fzf-palette"))
        XCTAssertEqual(filesRequest.display.delimiter, "\t")
        XCTAssertEqual(filesRequest.display.withNth, "1")
        XCTAssertEqual(filesRequest.result.fields, "2")
        XCTAssertEqual(filesRequest.preview?.window, "right:60%:wrap")
    }

    func testProfileStoreIncludesCtrlTProfileBackedByFzfEnvironment() throws {
        let request = try ProfileStore().resolvedRequest(
            for: PickerRequest(profile: FzfSourceCommands.ctrlTProfileName)
        )

        XCTAssertEqual(request.profile, FzfSourceCommands.ctrlTProfileName)
        XCTAssertEqual(request.source, .profile)
        XCTAssertEqual(request.display.prompt, "files>")
        XCTAssertEqual(request.display.header, "Pick files")
        XCTAssertEqual(request.display.pointer, ">")
        XCTAssertEqual(request.display.marker, "*")
        XCTAssertEqual(request.display.info, "inline")
    }

    func testTwoStageProfileValidationReportsNestedIssues() {
        let profile = PickerProfile(
            name: "bad-two-stage",
            title: "Bad Two Stage",
            source: .twoStage(TwoStageSource(
                first: PickerStage(source: .command("")),
                second: PickerStage(
                    source: .staticItems(["ok"]),
                    preview: PreviewConfig(command: "")
                )
            ))
        )

        let issues = profile.validationErrors()

        XCTAssertTrue(issues.contains {
            $0.field == "source.first.source.command" && $0.message == "Source command cannot be empty"
        })
        XCTAssertTrue(issues.contains {
            $0.field == "source.second.preview.command" && $0.message == "Preview command cannot be empty"
        })
    }

    func testHotKeyBindingParsesAliasesAndCanonicalDisplay() throws {
        let defaultBinding = try HotKeyBinding.parse("control + alt + space")
        XCTAssertEqual(defaultBinding, HotKeyBinding.default)
        XCTAssertEqual(defaultBinding.displayString, "ctrl+option+space")

        let customBinding = try HotKeyBinding.parse("cmd+shift+K")
        XCTAssertEqual(customBinding.modifiers, [.shift, .command])
        XCTAssertEqual(customBinding.key, "k")
        XCTAssertEqual(customBinding.displayString, "shift+cmd+k")

        let functionKeyBinding = try HotKeyBinding.parse("ctrl+option+shift+f18")
        XCTAssertEqual(functionKeyBinding.displayString, "ctrl+option+shift+f18")
    }

    func testHotKeyBindingRejectsUnsafeOrUnsupportedBindings() {
        XCTAssertThrowsError(try HotKeyBinding.parse(""))
        XCTAssertThrowsError(try HotKeyBinding.parse("space"))
        XCTAssertThrowsError(try HotKeyBinding.parse("ctrl+space+k"))
        XCTAssertThrowsError(try HotKeyBinding.parse("ctrl+fn+space"))
        XCTAssertThrowsError(try HotKeyBinding.parse("ctrl+f21"))
    }

    func testProfileHotKeyBindingDecodesStringBinding() throws {
        let data = Data(#"{"profile":"context-files","binding":"cmd+shift+k"}"#.utf8)
        let binding = try JSONDecoder().decode(ProfileHotKeyBinding.self, from: data)

        XCTAssertEqual(binding.profile, "context-files")
        XCTAssertEqual(binding.binding.displayString, "shift+cmd+k")
    }

    func testPlaceholderExpansionUsesFieldsAndLines() {
        let command = PlaceholderExpansion.expand(
            template: "bat --highlight-line {2} {1} | head -$LINES",
            row: "Sources/Foo.swift:12:3:hello world",
            delimiter: ":",
            lines: 18
        )

        XCTAssertEqual(command, "bat --highlight-line 12 Sources/Foo.swift | head -18")
    }

    func testPlaceholderExpansionShellEscapesUnsafeValues() {
        let command = PlaceholderExpansion.expand(
            template: "preview {}",
            row: "hello world's file"
        )

        XCTAssertEqual(command, "preview 'hello world'\\''s file'")
    }

    func testPlaceholderExpansionHandlesEmptyRows() {
        let command = PlaceholderExpansion.expand(
            template: "root={}; printf {1}",
            row: ""
        )

        XCTAssertEqual(command, "root=''; printf {1}")
    }

    func testMetricSummaryCalculatesMaxAndPercentiles() {
        let summary = MetricSummary(values: [1, 2, 3, 4, 100])

        XCTAssertEqual(summary.count, 5)
        XCTAssertEqual(summary.max, 100)
        XCTAssertTrue(summary.exceeds(maximum: 50))
        XCTAssertEqual(summary.p50, 3)
    }

    func testSelectionModelReturnsRowsInSourceOrder() {
        var selection = SelectionModel()
        selection.toggle(2)
        selection.toggle(0)

        XCTAssertEqual(selection.orderedSelection(from: ["a", "b", "c"]), ["a", "c"])
    }

    func testSelectionModelReturnsPaletteRowsInSourceOrderAfterFiltering() {
        var selection = SelectionModel()
        selection.toggle(2)
        selection.toggle(0)

        let filteredRows = [
            PaletteRow(original: "c", display: "c", sourceIndex: 2),
            PaletteRow(original: "a", display: "a", sourceIndex: 0)
        ]

        XCTAssertEqual(selection.orderedSelection(from: filteredRows).map(\.original), ["a", "c"])
    }

    func testNativeFuzzySearchEngineOwnsMultiSelectStateInSourceOrder() {
        let display = DisplayConfig()
        let initialRows = RowFormatting.rows(from: ["gamma", "alpha", "beta"], display: display)
        let engine = NativeFuzzySearchEngine(rows: initialRows)

        engine.selectAll(rows: [initialRows[2], initialRows[0]])

        XCTAssertEqual(engine.selectedCount, 2)
        XCTAssertTrue(engine.isSelected(sourceIndex: 0))
        XCTAssertTrue(engine.isSelected(sourceIndex: 2))
        XCTAssertEqual(engine.selectedRows().map(\.original), ["gamma", "beta"])
        XCTAssertEqual(engine.acceptedRows(fallback: initialRows[1]).map(\.original), ["gamma", "beta"])

        engine.toggleSelection(sourceIndex: 2)
        XCTAssertEqual(engine.selectedRows().map(\.original), ["gamma"])

        let appended = RowFormatting.rows(from: ["delta"], display: display, startingAt: initialRows.count)
        engine.appendRows(appended)
        engine.toggleSelection(sourceIndex: 3)
        XCTAssertEqual(engine.selectedRows().map(\.original), ["gamma", "delta"])

        engine.deselectAll()
        XCTAssertFalse(engine.hasSelection)
        XCTAssertEqual(engine.acceptedRows(fallback: initialRows[1]).map(\.original), ["alpha"])
    }

    func testNativeFuzzySearchEngineClearsSelectionWhenRowsAreReplaced() {
        let display = DisplayConfig()
        let engine = NativeFuzzySearchEngine(rows: RowFormatting.rows(from: ["old"], display: display))
        engine.toggleSelection(sourceIndex: 0)

        engine.replaceRows(RowFormatting.rows(from: ["new"], display: display))

        XCTAssertEqual(engine.selectedCount, 0)
        XCTAssertEqual(engine.selectedRows(), [])
    }

    func testFzfRuntimeOptionsDetectMultiSelect() {
        XCTAssertTrue(FzfRuntimeOptions.isMultiSelectEnabled(["--height", "40%", "-m"]))
        XCTAssertTrue(FzfRuntimeOptions.isMultiSelectEnabled(["--multi=3"]))
        XCTAssertFalse(FzfRuntimeOptions.isMultiSelectEnabled(["-m", "+m"]))
        XCTAssertFalse(FzfRuntimeOptions.isMultiSelectEnabled(["--multi", "--no-multi"]))
        XCTAssertTrue(FzfRuntimeOptions.isMultiSelectEnabled(["+m", "-m"]))
        XCTAssertFalse(FzfRuntimeOptions.isMultiSelectEnabled(["--height", "40%"]))
    }

    func testFzfDefaultOptionsParsesEnvironmentAndOptionsFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fzf-palette-default-opts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let optionsFile = directory.appendingPathComponent("fzf-default-opts")
        try "--height 100% --border-label ' file label '\n".write(to: optionsFile, atomically: true, encoding: .utf8)

        let arguments = FzfDefaultOptions.arguments(environment: [
            "FZF_DEFAULT_OPTS_FILE": optionsFile.path,
            "FZF_DEFAULT_OPTS": "-i -m --bind 'ctrl-A:select-all,ctrl-d:deselect-all' +m"
        ])

        XCTAssertEqual(
            arguments,
            [
                "--height", "100%",
                "--border-label", " file label ",
                "-i",
                "-m",
                "--bind", "ctrl-A:select-all,ctrl-d:deselect-all",
                "+m"
            ]
        )
        XCTAssertFalse(FzfRuntimeOptions.isMultiSelectEnabled(arguments))
    }

    func testFzfSourceCommandsResolveDefaultAndCtrlTEnvironment() {
        XCTAssertEqual(
            FzfSourceCommands.defaultCommand(environment: ["FZF_DEFAULT_COMMAND": " fd --type f "]),
            "fd --type f"
        )
        XCTAssertEqual(
            FzfSourceCommands.defaultCommand(environment: [:]),
            FzfSourceCommands.fallbackDefaultCommand
        )
        XCTAssertEqual(
            FzfSourceCommands.ctrlTCommand(environment: [
                "FZF_DEFAULT_COMMAND": "fd --type f",
                "FZF_CTRL_T_COMMAND": "rg --files"
            ]),
            "rg --files"
        )
        XCTAssertEqual(
            FzfSourceCommands.ctrlTCommand(environment: [
                "FZF_DEFAULT_COMMAND": "fd --type f",
                "FZF_CTRL_T_COMMAND": " "
            ]),
            "fd --type f"
        )
        XCTAssertEqual(
            FzfSourceCommands.command(
                forProfile: FzfSourceCommands.ctrlTProfileName,
                environment: [
                    "FZF_DEFAULT_COMMAND": "fd --type f",
                    "FZF_CTRL_T_COMMAND": "printf 'ctrl\\n'"
                ]
            ),
            "printf 'ctrl\\n'"
        )
    }

    func testFzfRuntimeOptionsDetectPreviewToggleBind() {
        XCTAssertTrue(FzfRuntimeOptions.isPreviewToggleEnabled(["--bind", "ctrl-/:toggle-preview"]))
        XCTAssertTrue(FzfRuntimeOptions.isPreviewToggleEnabled(["--bind=ctrl-A:select-all,ctrl-/:toggle-preview"]))
        XCTAssertFalse(FzfRuntimeOptions.isPreviewToggleEnabled(["--bind", "ctrl-A:select-all"]))
    }

    func testFzfRuntimeOptionsDetectSearchCaseMode() {
        XCTAssertEqual(FzfRuntimeOptions.searchOptions([]), FuzzySearchOptions(caseMode: .smart))
        XCTAssertEqual(FzfRuntimeOptions.searchOptions(["-i"]), FuzzySearchOptions(caseInsensitive: true))
        XCTAssertEqual(FzfRuntimeOptions.searchOptions(["+i"]), FuzzySearchOptions(caseInsensitive: false))
        XCTAssertEqual(FzfRuntimeOptions.searchOptions(["+i", "-i"]), FuzzySearchOptions(caseInsensitive: true))
        XCTAssertEqual(
            FzfRuntimeOptions.searchOptions(["--tiebreak", "index"]),
            FuzzySearchOptions(caseMode: .smart, tiebreak: .index)
        )
        XCTAssertEqual(
            FzfRuntimeOptions.searchOptions(["--tiebreak=index", "-i"]),
            FuzzySearchOptions(caseMode: .caseInsensitive, tiebreak: .index)
        )
        XCTAssertEqual(
            FzfRuntimeOptions.searchOptions(["--tiebreak", "begin"]),
            FuzzySearchOptions(caseMode: .smart, tiebreak: .begin)
        )
        XCTAssertEqual(
            FzfRuntimeOptions.searchOptions(["--tiebreak=begin,end"]),
            FuzzySearchOptions(caseMode: .smart, tiebreaks: [.begin, .end])
        )
        XCTAssertEqual(
            FzfRuntimeOptions.searchOptions(["--tiebreak=begin,index"]),
            FuzzySearchOptions(caseMode: .smart, tiebreaks: [.begin, .index])
        )
        XCTAssertEqual(
            FzfRuntimeOptions.searchOptions(["--tiebreak=chunk,begin"]),
            FuzzySearchOptions(caseMode: .smart, tiebreaks: [.chunk, .begin])
        )
        XCTAssertEqual(
            FzfRuntimeOptions.searchOptions(["--exact"]),
            FuzzySearchOptions(caseMode: .smart, exactMode: true)
        )
        XCTAssertEqual(
            FzfRuntimeOptions.searchOptions(["-e", "+e"]),
            FuzzySearchOptions(caseMode: .smart, exactMode: false)
        )
        XCTAssertEqual(
            FzfRuntimeOptions.searchOptions(["+s"]),
            FuzzySearchOptions(caseMode: .smart, sort: false)
        )
        XCTAssertEqual(
            FzfRuntimeOptions.searchOptions(["--no-sort", "-i"]),
            FuzzySearchOptions(caseMode: .caseInsensitive, sort: false)
        )
        XCTAssertEqual(
            FzfRuntimeOptions.searchOptions(["--scheme", "path"]),
            FuzzySearchOptions(caseMode: .smart, scheme: .path)
        )
        XCTAssertEqual(
            FzfRuntimeOptions.searchOptions(["--scheme=default", "--scheme=path"]),
            FuzzySearchOptions(caseMode: .smart, scheme: .path)
        )
        XCTAssertEqual(
            FzfRuntimeOptions.searchOptions(["--scheme=history"]),
            FuzzySearchOptions(caseMode: .smart, tiebreaks: [], scheme: .history)
        )
        XCTAssertEqual(
            FzfRuntimeOptions.searchOptions(["--scheme=history", "--tiebreak=length"]),
            FuzzySearchOptions(caseMode: .smart, tiebreaks: [], scheme: .history)
        )
    }

    func testSimpleMatcherPreservesSourceOrderForEmptyQuery() {
        let rows = ["b.swift", "a.swift"]

        XCTAssertEqual(SimpleMatcher.match(query: "", rows: rows).map(\.text), rows)
    }

    func testSimpleMatcherRanksContiguousMatchesHigher() {
        let rows = ["source/foo/palette.swift", "p/a/l/e/t/t/e.swift", "palette.swift"]

        XCTAssertEqual(SimpleMatcher.match(query: "palette", rows: rows).first?.text, "palette.swift")
    }

    func testNativeFuzzySearchEnginePreservesSourceOrderForEmptyQuery() {
        let engine = NativeFuzzySearchEngine(rows: [
            PaletteRow(original: "b.swift", display: "b.swift"),
            PaletteRow(original: "a.swift", display: "a.swift")
        ])

        XCTAssertEqual(engine.searchRows(query: "").map(\.original), ["b.swift", "a.swift"])
    }

    func testNativeFuzzySearchEngineRanksContiguousMatchesHigher() {
        let engine = NativeFuzzySearchEngine(rows: [
            PaletteRow(original: "source/foo/palette.swift", display: "source/foo/palette.swift"),
            PaletteRow(original: "p/a/l/e/t/t/e.swift", display: "p/a/l/e/t/t/e.swift"),
            PaletteRow(original: "palette.swift", display: "palette.swift")
        ])

        XCTAssertEqual(engine.searchRows(query: "palette").first?.original, "palette.swift")
    }

    func testNativeFuzzySearchEngineReturnsFuzzyMatchRanges() throws {
        let engine = NativeFuzzySearchEngine(rows: [
            PaletteRow(original: "palette.swift", display: "palette.swift")
        ])

        let match = try XCTUnwrap(engine.search(query: "plt").first)

        XCTAssertEqual(match.row.original, "palette.swift")
        XCTAssertEqual(
            match.ranges,
            [
                FuzzyMatchRange(start: 0, length: 1),
                FuzzyMatchRange(start: 2, length: 1),
                FuzzyMatchRange(start: 4, length: 1)
            ]
        )
    }

    func testNativeFuzzySearchEngineCanDeferMatchRangesForPanelRendering() throws {
        let engine = NativeFuzzySearchEngine(rows: [
            PaletteRow(original: "palette.swift", display: "palette.swift"),
            PaletteRow(original: "source/foo/palette.swift", display: "source/foo/palette.swift"),
            PaletteRow(original: "p/a/l/e/t/t/e.swift", display: "p/a/l/e/t/t/e.swift")
        ])

        let matchesWithoutRanges = engine.search(query: "palette", includeRanges: false)
        let matchesWithRanges = engine.search(query: "palette")

        XCTAssertEqual(matchesWithoutRanges.map(\.row.original), matchesWithRanges.map(\.row.original))
        XCTAssertTrue(matchesWithoutRanges.allSatisfy(\.ranges.isEmpty))
        XCTAssertEqual(
            engine.matchRanges(query: "plt", sourceIndex: 0),
            [
                FuzzyMatchRange(start: 0, length: 1),
                FuzzyMatchRange(start: 2, length: 1),
                FuzzyMatchRange(start: 4, length: 1)
            ]
        )
    }

    func testNativeFuzzySearchEngineReturnsExactMatchRanges() throws {
        let engine = NativeFuzzySearchEngine(rows: [
            PaletteRow(original: "music/alpha.mp3", display: "music/alpha.mp3")
        ])

        let match = try XCTUnwrap(engine.search(query: "'alpha").first)

        XCTAssertEqual(match.ranges, [FuzzyMatchRange(start: 6, length: 5)])
    }

    func testNativeFuzzySearchEngineTreatsEscapedSpaceAsLiteralSpace() {
        let engine = NativeFuzzySearchEngine(rows: [
            PaletteRow(original: "hello world.txt", display: "hello world.txt"),
            PaletteRow(original: "hello-world.txt", display: "hello-world.txt"),
            PaletteRow(original: "world hello.txt", display: "world hello.txt")
        ])

        XCTAssertEqual(engine.searchRows(query: "hello\\ world").map(\.original), ["hello world.txt"])
    }

    func testNativeFuzzySearchEngineSupportsIncrementalRows() {
        let engine = NativeFuzzySearchEngine()
        engine.replaceRows([
            PaletteRow(original: "alpha", display: "alpha")
        ])
        engine.appendRows([
            PaletteRow(original: "beta", display: "beta"),
            PaletteRow(original: "alphabet", display: "alphabet")
        ])

        XCTAssertEqual(engine.searchRows(query: "alp").map(\.original), ["alpha", "alphabet"])
    }

    func testNativeFuzzySearchEngineCanBeCaseSensitive() {
        let engine = NativeFuzzySearchEngine(
            rows: [
                PaletteRow(original: "Readme.md", display: "Readme.md"),
                PaletteRow(original: "README.md", display: "README.md")
            ],
            options: FuzzySearchOptions(caseInsensitive: false)
        )

        XCTAssertEqual(engine.searchRows(query: "REA").map(\.original), ["README.md"])
    }

    func testNativeFuzzySearchEngineSupportsExactModeAndQuoteUnquote() {
        let rows = [
            PaletteRow(original: "alpha", display: "alpha"),
            PaletteRow(original: "a/l/p/h/a", display: "a/l/p/h/a"),
            PaletteRow(original: "alpaca", display: "alpaca")
        ]
        let engine = NativeFuzzySearchEngine(
            rows: rows,
            options: FuzzySearchOptions(caseMode: .smart, exactMode: true)
        )

        XCTAssertEqual(engine.searchRows(query: "alp").map(\.original), ["alpha", "alpaca"])
        XCTAssertEqual(engine.searchRows(query: "'alp").map(\.original), ["alpha", "alpaca", "a/l/p/h/a"])
    }

    func testNativeFuzzySearchEngineSupportsSmartCase() {
        let engine = NativeFuzzySearchEngine(
            rows: [
                PaletteRow(original: "Readme.md", display: "Readme.md"),
                PaletteRow(original: "README.md", display: "README.md"),
                PaletteRow(original: "readme.md", display: "readme.md")
            ],
            options: FuzzySearchOptions(caseMode: .smart)
        )

        XCTAssertEqual(engine.searchRows(query: "rea").map(\.original), ["Readme.md", "README.md", "readme.md"])
        XCTAssertEqual(engine.searchRows(query: "REA").map(\.original), ["README.md"])
    }

    func testNativeFuzzySearchEngineSupportsTiebreakIndex() {
        let rows = [
            PaletteRow(original: "abcxxxx", display: "abcxxxx"),
            PaletteRow(original: "abc", display: "abc")
        ]
        let defaultEngine = NativeFuzzySearchEngine(rows: rows)
        let indexEngine = NativeFuzzySearchEngine(
            rows: rows,
            options: FuzzySearchOptions(tiebreak: .index)
        )

        XCTAssertEqual(defaultEngine.searchRows(query: "abc").map(\.original), ["abc", "abcxxxx"])
        XCTAssertEqual(indexEngine.searchRows(query: "abc").map(\.original), ["abcxxxx", "abc"])
    }

    func testNativeFuzzySearchEngineSupportsBeginAndEndTiebreaks() {
        let beginRows = [
            "xxabc",
            "abcxx",
            "xabcx",
            "abc"
        ].map { PaletteRow(original: $0, display: $0) }
        let beginEngine = NativeFuzzySearchEngine(
            rows: beginRows,
            options: FuzzySearchOptions(tiebreak: .begin)
        )

        XCTAssertEqual(
            beginEngine.searchRows(query: "abc").map(\.original),
            ["abcxx", "abc", "xabcx", "xxabc"]
        )

        let endRows = [
            "abcde",
            "abcd",
            "abc",
            "abcxyz"
        ].map { PaletteRow(original: $0, display: $0) }
        let endEngine = NativeFuzzySearchEngine(
            rows: endRows,
            options: FuzzySearchOptions(tiebreak: .end)
        )

        XCTAssertEqual(
            endEngine.searchRows(query: "abc").map(\.original),
            ["abc", "abcd", "abcde", "abcxyz"]
        )
    }

    func testNativeFuzzySearchEngineSupportsOrderedTiebreakLists() {
        let rows = [
            "xxabc",
            "abcxx",
            "xabcx",
            "abc"
        ].map { PaletteRow(original: $0, display: $0) }
        let engine = NativeFuzzySearchEngine(
            rows: rows,
            options: FuzzySearchOptions(tiebreaks: [.begin, .end])
        )

        XCTAssertEqual(
            engine.searchRows(query: "abc").map(\.original),
            ["abc", "abcxx", "xabcx", "xxabc"]
        )
    }

    func testNativeFuzzySearchEngineSupportsChunkTiebreak() {
        let rows = [
            "1 foobarbaz ba",
            "2 foobar baz",
            "3 foo barbaz"
        ].map { PaletteRow(original: $0, display: $0) }
        let engine = NativeFuzzySearchEngine(
            rows: rows,
            options: FuzzySearchOptions(tiebreak: .chunk)
        )

        XCTAssertEqual(
            engine.searchRows(query: "o").map(\.original),
            ["3 foo barbaz", "2 foobar baz", "1 foobarbaz ba"]
        )
    }

    func testNativeFuzzySearchEngineSupportsPathSchemeRanking() {
        let rows = [
            "foo/bar/baz/qux.txt",
            "foo-baz-qux.txt",
            "bar/foo/qux-baz.txt",
            "qux/foo/bar/baz.txt",
            "qux.txt"
        ].map { PaletteRow(original: $0, display: $0) }
        let engine = NativeFuzzySearchEngine(
            rows: rows,
            options: FuzzySearchOptions(scheme: .path)
        )

        XCTAssertEqual(
            engine.searchRows(query: "qux").map(\.original),
            [
                "qux.txt",
                "foo/bar/baz/qux.txt",
                "bar/foo/qux-baz.txt",
                "qux/foo/bar/baz.txt",
                "foo-baz-qux.txt"
            ]
        )
    }

    func testNativeFuzzySearchEngineSupportsHistorySchemeScoreOnlyTies() {
        let rows = [
            "abcxxxx",
            "abc",
            "xabcx",
            "xxabc"
        ].map { PaletteRow(original: $0, display: $0) }
        let engine = NativeFuzzySearchEngine(
            rows: rows,
            options: FuzzySearchOptions(tiebreaks: [], scheme: .history)
        )

        XCTAssertEqual(
            engine.searchRows(query: "abc").map(\.original),
            ["abcxxxx", "abc", "xabcx", "xxabc"]
        )
    }

    func testNativeFuzzySearchEngineCanPreserveSourceOrderForNonEmptyQuery() {
        let engine = NativeFuzzySearchEngine(
            rows: [
                PaletteRow(original: "abcxxxx", display: "abcxxxx"),
                PaletteRow(original: "abc", display: "abc"),
                PaletteRow(original: "zzz", display: "zzz")
            ],
            options: FuzzySearchOptions(sort: false)
        )

        XCTAssertEqual(engine.searchRows(query: "abc").map(\.original), ["abcxxxx", "abc"])
    }

    func testNativeFuzzySearchEngineUsesSearchTextSeparatelyFromDisplayText() {
        let rows = RowFormatting.rows(
            from: [
                "src/App.swift:10:1:alpha match",
                "docs/App.md:20:1:alpha match",
                "src/Other.swift:30:1:beta match"
            ],
            display: DisplayConfig(delimiter: ":", nth: "1", withNth: "4")
        )
        let engine = NativeFuzzySearchEngine(rows: rows)

        XCTAssertEqual(rows[0].display, "alpha match")
        XCTAssertEqual(rows[0].search, "src/App.swift")
        XCTAssertEqual(
            try XCTUnwrap(engine.search(query: "src").first { $0.row.original == "src/App.swift:10:1:alpha match" }).ranges,
            [FuzzyMatchRange(start: 0, length: 3)]
        )
        XCTAssertEqual(
            engine.searchRows(query: "src").map(\.original).sorted(),
            [
                "src/App.swift:10:1:alpha match",
                "src/Other.swift:30:1:beta match"
            ]
        )
        XCTAssertEqual(engine.searchRows(query: "alpha").map(\.original), [])
    }

    func testNativeFuzzySearchEngineSupportsExtendedAndInverseTerms() {
        let engine = NativeFuzzySearchEngine(rows: [
            PaletteRow(original: "music/alpha.mp3", display: "music/alpha.mp3"),
            PaletteRow(original: "music/fire.mp3", display: "music/fire.mp3"),
            PaletteRow(original: "music/alpha.flac", display: "music/alpha.flac"),
            PaletteRow(original: "docs/alpha.mp3", display: "docs/alpha.mp3")
        ])

        XCTAssertEqual(
            engine.searchRows(query: "^music .mp3$ !fire 'alpha").map(\.original),
            ["music/alpha.mp3"]
        )
    }

    func testNativeFuzzySearchEngineSupportsOrClauses() {
        let engine = NativeFuzzySearchEngine(rows: [
            PaletteRow(original: "core.go", display: "core.go"),
            PaletteRow(original: "core.rb", display: "core.rb"),
            PaletteRow(original: "core.py", display: "core.py"),
            PaletteRow(original: "core.js", display: "core.js"),
            PaletteRow(original: "lib.rb", display: "lib.rb")
        ])

        XCTAssertEqual(
            engine.searchRows(query: "^core go$ | rb$").map(\.original),
            ["core.go", "core.rb"]
        )
    }

    func testRowFormattingSupportsWithNthDisplay() {
        let display = DisplayConfig(delimiter: "\t", withNth: "1")

        XCTAssertEqual(
            RowFormatting.displayText(for: "friendly name\t/hidden/session.json", display: display),
            "friendly name"
        )
    }

    func testRowFormattingSupportsNthSearchScope() {
        let display = DisplayConfig(delimiter: ":", nth: "1")

        XCTAssertEqual(
            RowFormatting.searchText(for: "src/App.swift:10:1:alpha match", display: display),
            "src/App.swift"
        )
        XCTAssertEqual(
            RowFormatting.searchText(for: "src/App.swift:10:1:alpha match", display: DisplayConfig(delimiter: ":", nth: "4")),
            "alpha match"
        )
    }

    func testRowFormattingPreservesOriginalDisplaySpacingWithoutWithNth() {
        let row = RowFormatting.row(from: "one   two\tthree", display: DisplayConfig())

        XCTAssertEqual(row.display, "one   two\tthree")
        XCTAssertEqual(row.search, "one   two\tthree")
        XCTAssertNil(row.searchToDisplayMap)
    }

    func testRowFormattingProjectsNthSearchRangesOntoOriginalDisplay() {
        let row = RowFormatting.row(
            from: "src/App.swift:10:1:alpha match",
            display: DisplayConfig(delimiter: ":", nth: "1")
        )

        XCTAssertEqual(row.display, "src/App.swift:10:1:alpha match")
        XCTAssertEqual(row.search, "src/App.swift")
        XCTAssertEqual(
            RowFormatting.displayRanges(for: [FuzzyMatchRange(start: 0, length: 3)], row: row),
            [FuzzyMatchRange(start: 0, length: 3)]
        )
    }

    func testRowFormattingProjectsNthSearchRangesOntoWithNthDisplay() {
        let row = RowFormatting.row(
            from: "id:src/App.swift:alpha",
            display: DisplayConfig(delimiter: ":", nth: "2", withNth: "3,2")
        )

        XCTAssertEqual(row.display, "alpha:src/App.swift")
        XCTAssertEqual(row.search, "src/App.swift")
        XCTAssertEqual(
            RowFormatting.displayRanges(for: [FuzzyMatchRange(start: 0, length: 3)], row: row),
            [FuzzyMatchRange(start: 6, length: 3)]
        )
    }

    func testRowFormattingDoesNotProjectHiddenNthSearchRanges() {
        let row = RowFormatting.row(
            from: "src/App.swift:10:1:alpha match",
            display: DisplayConfig(delimiter: ":", nth: "1", withNth: "4")
        )

        XCTAssertEqual(row.display, "alpha match")
        XCTAssertEqual(row.search, "src/App.swift")
        XCTAssertEqual(
            RowFormatting.displayRanges(for: [FuzzyMatchRange(start: 0, length: 3)], row: row),
            []
        )
    }

    func testRowFormattingSupportsNegativeFieldExpressions() {
        let fields = RowFormatting.selectFields(
            ["history-id", "git", "status", "--short"],
            expression: "2..,..,-1"
        )

        XCTAssertEqual(fields, ["git", "status", "--short", "history-id", "git", "status", "--short", "--short"])
    }

    func testRowFormattingSupportsResultFieldExtraction() {
        let display = DisplayConfig(delimiter: "\t", withNth: "1")
        let result = ResultConfig(fields: "2", join: .newline)

        XCTAssertEqual(
            RowFormatting.selectedText(
                for: "friendly name\t/hidden/session.json",
                display: display,
                result: result
            ),
            "/hidden/session.json"
        )
    }

    func testRowFormattingJoinsMultiSelectedRows() {
        let rows = [
            "friendly\t/hidden/session.json",
            "other\t/hidden/other.json"
        ]
        let display = DisplayConfig(delimiter: "\t", withNth: "1")
        let result = ResultConfig(fields: "2", join: .space)
        let selected = rows.map {
            RowFormatting.selectedText(for: $0, display: display, result: result)
        }

        XCTAssertEqual(RowFormatting.join(selected, mode: result.join), "/hidden/session.json /hidden/other.json")
    }

    func testMultiSelectOutputUsesSourceOrderHiddenFieldsAndJoinModes() {
        var selection = SelectionModel()
        selection.toggle(2)
        selection.toggle(0)

        let display = DisplayConfig(delimiter: "\t", withNth: "1")
        let visibleRows = RowFormatting.rows(
            from: [
                "gamma\t/hidden/gamma.json",
                "alpha\t/hidden/alpha.json",
                "beta\t/hidden/beta.json"
            ],
            display: display
        )
        let filteredRows = [
            visibleRows[2],
            visibleRows[0],
            visibleRows[1]
        ]
        let selectedRows = selection.orderedSelection(from: filteredRows).map(\.original)

        XCTAssertEqual(selectedRows, [
            "gamma\t/hidden/gamma.json",
            "beta\t/hidden/beta.json"
        ])
        XCTAssertEqual(
            RowFormatting.joinedSelectedText(
                for: selectedRows,
                display: display,
                result: ResultConfig(fields: "2", join: .newline)
            ),
            "/hidden/gamma.json\n/hidden/beta.json"
        )
        XCTAssertEqual(
            RowFormatting.joinedSelectedText(
                for: selectedRows,
                display: display,
                result: ResultConfig(fields: "2", join: .space)
            ),
            "/hidden/gamma.json /hidden/beta.json"
        )
        XCTAssertEqual(
            RowFormatting.joinedSelectedText(
                for: selectedRows,
                display: display,
                result: ResultConfig(fields: "2", join: .nul)
            ),
            "/hidden/gamma.json\0/hidden/beta.json"
        )
        XCTAssertEqual(
            RowFormatting.joinedSelectedText(
                for: selectedRows,
                display: display,
                result: ResultConfig(fields: "2", join: .json)
            ),
            #"["/hidden/gamma.json","/hidden/beta.json"]"#
        )
    }

    func testRowFormattingSupportsRangesAndJsonJoin() {
        let result = ResultConfig(fields: "2..3", join: .json)

        XCTAssertEqual(
            RowFormatting.selectedText(
                for: "one:two:three:four",
                display: DisplayConfig(delimiter: ":"),
                result: result
            ),
            #"["two","three"]"#
        )
        XCTAssertEqual(
            RowFormatting.selectedText(
                for: "one:two:three",
                display: DisplayConfig(delimiter: ":"),
                result: ResultConfig(fields: "2", join: .json)
            ),
            "two"
        )
    }

    func testRowFormattingStripsANSIWhenRequested() {
        let display = DisplayConfig(ansi: true)

        XCTAssertEqual(
            RowFormatting.displayText(for: "\u{001B}[31mred\u{001B}[0m", display: display),
            "red"
        )
        XCTAssertEqual(
            RowFormatting.selectedText(
                for: "\u{001B}[31mred\u{001B}[0m",
                display: display,
                result: ResultConfig()
            ),
            "red"
        )
        XCTAssertEqual(
            RowFormatting.selectedText(
                for: "friendly:\u{001B}[31m/hidden/red\u{001B}[0m",
                display: DisplayConfig(ansi: true, delimiter: ":"),
                result: ResultConfig(fields: "2", join: .newline)
            ),
            "/hidden/red"
        )
    }

    func testRowFormattingCreatesANSIStyleSpansWhenRequested() {
        let row = RowFormatting.row(
            from: "\u{001B}[31mred\u{001B}[0m plain \u{001B}[1;32mbold-green\u{001B}[22m-green\u{001B}[39m",
            display: DisplayConfig(ansi: true)
        )

        XCTAssertEqual(row.display, "red plain bold-green-green")
        XCTAssertEqual(row.search, "red plain bold-green-green")
        XCTAssertEqual(
            row.ansiStyleSpans,
            [
                AnsiStyleSpan(start: 0, length: 3, foreground: .red),
                AnsiStyleSpan(start: 10, length: 10, foreground: .green, bold: true),
                AnsiStyleSpan(start: 20, length: 6, foreground: .green)
            ]
        )
    }

    func testANSIParserHandlesBrightColorsAndNonStyleSequences() {
        let parsed = RowFormatting.parseANSI("\u{001B}[90mdim\u{001B}[K text\u{001B}[0m")

        XCTAssertEqual(parsed.text, "dim text")
        XCTAssertEqual(
            parsed.spans,
            [
                AnsiStyleSpan(start: 0, length: 8, foreground: .brightBlack)
            ]
        )
    }

    func testANSIParserHandlesExtendedColorsAndTextStyles() {
        let parsed = RowFormatting.parseANSI(
            "\u{001B}[3;4;9;38;5;196;48;2;10;20;30mstyled\u{001B}[23;24;29;39;49m plain " +
                "\u{001B}[2;38;2;1;2;3mdim\u{001B}[22;39m normal"
        )

        XCTAssertEqual(parsed.text, "styled plain dim normal")
        XCTAssertEqual(
            parsed.spans,
            [
                AnsiStyleSpan(
                    start: 0,
                    length: 6,
                    foregroundRGB: AnsiRGBColor(red: 255, green: 0, blue: 0),
                    backgroundRGB: AnsiRGBColor(red: 10, green: 20, blue: 30),
                    italic: true,
                    underline: true,
                    strikethrough: true
                ),
                AnsiStyleSpan(
                    start: 13,
                    length: 3,
                    foregroundRGB: AnsiRGBColor(red: 1, green: 2, blue: 3),
                    dim: true
                )
            ]
        )
    }

    func testANSIParserHandlesBackgroundColorsAndPartialResets() {
        let parsed = RowFormatting.parseANSI(
            "\u{001B}[1;42mbold-bg\u{001B}[22m-bg\u{001B}[49m plain"
        )

        XCTAssertEqual(parsed.text, "bold-bg-bg plain")
        XCTAssertEqual(
            parsed.spans,
            [
                AnsiStyleSpan(start: 0, length: 7, background: .green, bold: true),
                AnsiStyleSpan(start: 7, length: 3, background: .green)
            ]
        )
    }

    func testANSIParserAppliesCarriageReturnBackspaceAndClearLineControls() {
        XCTAssertEqual(RowFormatting.stripANSI("loading 10%\r\u{001B}[2Kdone\n"), "done\n")
        XCTAssertEqual(RowFormatting.stripANSI("abc\u{0008}X"), "abX")
        XCTAssertEqual(RowFormatting.stripANSI("abc\u{001B}[1K"), "   ")
        XCTAssertEqual(RowFormatting.stripANSI("abc\rz\u{001B}[K"), "z")
    }

    func testANSIParserAppliesCursorMovementAndClearScreenControls() {
        let cursorParsed = RowFormatting.parseANSI(
            "one\ntwo\u{001B}[1A\r\u{001B}[2Kuno\u{001B}[1B\rthree"
        )
        XCTAssertEqual(cursorParsed.text, "uno\nthree")

        XCTAssertEqual(RowFormatting.stripANSI("old\u{001B}[2J\u{001B}[Hnew"), "new")
        XCTAssertEqual(RowFormatting.stripANSI("abc\u{001B}[2DXY"), "aXY")
        XCTAssertEqual(RowFormatting.stripANSI("a\u{001B}[5Gz"), "a   z")
    }

    func testANSIParserAppliesAdditionalTerminalCursorControls() {
        XCTAssertEqual(
            RowFormatting.stripANSI("one\ntwo\nthree\u{001B}[2Ftop"),
            "top\ntwo\nthree"
        )
        XCTAssertEqual(
            RowFormatting.stripANSI("one\u{001B}[2Ethree"),
            "one\n\nthree"
        )
        XCTAssertEqual(
            RowFormatting.stripANSI("a\nb\nc\u{001B}[2d\rB"),
            "a\nB\nc"
        )
    }

    func testANSIParserAppliesLineInsertDeleteAndScrollControls() {
        XCTAssertEqual(
            RowFormatting.stripANSI("one\ntwo\nthree\u{001B}[2;1H\u{001B}[Linsert"),
            "one\ninsert\ntwo\nthree"
        )
        XCTAssertEqual(
            RowFormatting.stripANSI("one\ntwo\nthree\u{001B}[2;1H\u{001B}[M"),
            "one\nthree"
        )
        XCTAssertEqual(
            RowFormatting.stripANSI("one\ntwo\nthree\u{001B}[1S"),
            "two\nthree"
        )
        XCTAssertEqual(
            RowFormatting.stripANSI("one\ntwo\u{001B}[1T\rtop"),
            "\ntop\ntwo"
        )
    }

    func testANSIParserStylesFinalTerminalCellsAfterOverwrites() {
        let parsed = RowFormatting.parseANSI(
            "\u{001B}[31mred\r\u{001B}[32mgreen\u{001B}[0m"
        )

        XCTAssertEqual(parsed.text, "green")
        XCTAssertEqual(parsed.spans, [
            AnsiStyleSpan(start: 0, length: 5, foreground: .green)
        ])
    }

    private func temporaryProfilesFile(
        profiles: [PickerProfile],
        hotkeys: [ProfileHotKeyBinding] = []
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fzf-palette-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("profiles.json")
        let data = try JSONEncoder().encode(ProfileCollection(profiles: profiles, hotkeys: hotkeys))
        try data.write(to: url)
        return url
    }
}
