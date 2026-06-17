import XCTest
@testable import FzfPaletteCore

final class UITests: XCTestCase {
    func testStatusResponseCarriesFieldsNeededByCLIAndUITests() throws {
        let status = AppStatus(
            running: true,
            pid: 123,
            socketPath: "/tmp/fzf-palette.sock",
            uptimeMs: 42,
            version: "test",
            logDirectory: "/tmp/logs",
            activePicker: true,
            panelVisible: true,
            visibleRows: 3,
            previewVisible: true,
            prompt: "sessions>",
            header: "Pick a session",
            pointer: ">",
            marker: "*",
            info: "inline",
            hotkey: "ctrl+option+space",
            hotkeyRegistered: true,
            hotkeyError: nil,
            hotkeys: [
                ProfileHotKeyStatus(profile: "default", hotkey: "ctrl+option+space", registered: true),
                ProfileHotKeyStatus(profile: "context-files", hotkey: "shift+cmd+k", registered: true)
            ],
            settingsHotkey: "shift+cmd+k",
            settingsProfile: "context-files",
            settingsVisible: true,
            programContext: ProgramContext(
                cwd: "/Users/benbernard/projects/fzf-palette",
                provider: "codex-bridge",
                appName: "Codex",
                bundleIdentifier: "com.openai.codex",
                detail: "thread workspace"
            ),
            lastCompletionReason: "panel_cancelled"
        )
        let response = PaletteResponse(type: .status, app: status)

        let decoded = try WireCoding.decodeResponse(WireCoding.encodeLine(response))

        XCTAssertEqual(decoded.app?.running, true)
        XCTAssertEqual(decoded.app?.socketPath, "/tmp/fzf-palette.sock")
        XCTAssertEqual(decoded.app?.logDirectory, "/tmp/logs")
        XCTAssertEqual(decoded.app?.activePicker, true)
        XCTAssertEqual(decoded.app?.panelVisible, true)
        XCTAssertEqual(decoded.app?.visibleRows, 3)
        XCTAssertEqual(decoded.app?.previewVisible, true)
        XCTAssertEqual(decoded.app?.prompt, "sessions>")
        XCTAssertEqual(decoded.app?.header, "Pick a session")
        XCTAssertEqual(decoded.app?.pointer, ">")
        XCTAssertEqual(decoded.app?.marker, "*")
        XCTAssertEqual(decoded.app?.info, "inline")
        XCTAssertEqual(decoded.app?.hotkey, "ctrl+option+space")
        XCTAssertEqual(decoded.app?.hotkeyRegistered, true)
        XCTAssertNil(decoded.app?.hotkeyError)
        XCTAssertEqual(decoded.app?.hotkeys.count, 2)
        XCTAssertEqual(decoded.app?.hotkeys.last?.profile, "context-files")
        XCTAssertEqual(decoded.app?.hotkeys.last?.hotkey, "shift+cmd+k")
        XCTAssertEqual(decoded.app?.settingsHotkey, "shift+cmd+k")
        XCTAssertEqual(decoded.app?.settingsProfile, "context-files")
        XCTAssertEqual(decoded.app?.settingsVisible, true)
        XCTAssertEqual(decoded.app?.programContext?.cwd, "/Users/benbernard/projects/fzf-palette")
        XCTAssertEqual(decoded.app?.programContext?.provider, "codex-bridge")
        XCTAssertEqual(decoded.app?.programContext?.appName, "Codex")
        XCTAssertEqual(decoded.app?.programContext?.bundleIdentifier, "com.openai.codex")
        XCTAssertEqual(decoded.app?.lastCompletionReason, "panel_cancelled")
    }

    func testVisualSnapshotRoundTripsForE2EAssertions() throws {
        let snapshot = PanelVisualSnapshot(
            panelVisible: true,
            queryFieldFocused: true,
            queryFieldActionBound: false,
            windowNumber: 42,
            captureX: 10,
            captureY: 20,
            captureWidth: 920,
            captureHeight: 560,
            width: 920,
            height: 560,
            renderedWidth: 1840,
            renderedHeight: 1120,
            sampledPixels: 6400,
            distinctColorBuckets: 12,
            nonBackgroundSampleRatio: 0.18,
            averageLuminance: 0.72,
            luminanceStandardDeviation: 0.12,
            effectiveAppearanceName: "NSAppearanceNameAqua",
            usesVibrantBackground: true,
            contentCornerRadius: 16,
            resultsCornerRadius: 10,
            previewCornerRadius: 10,
            usesCustomSelectionStyle: true,
            visibleRows: 3,
            selectedRowIndex: 1,
            activeRowText: "beta",
            previewVisible: true,
            previewWidth: 420,
            previewHeight: 360,
            resultsWidth: 430,
            resultsHeight: 360,
            previewPosition: "right",
            previewWrap: true,
            previewCharacterCount: 80,
            previewAnsiSpanCount: 2,
            previewAnsiRGBSpanCount: 1,
            previewAnsiBackgroundSpanCount: 1,
            previewAnsiTextStyleSpanCount: 2,
            previewContainsEscapeSequences: false,
            previewTextSample: "preview text",
            previewScrollOffsetY: 128,
            layoutViolationCount: 0
        )
        let response = PaletteResponse(type: .result, snapshot: snapshot)

        let decoded = try WireCoding.decodeResponse(WireCoding.encodeLine(response))

        XCTAssertEqual(decoded.snapshot?.panelVisible, true)
        XCTAssertEqual(decoded.snapshot?.queryFieldFocused, true)
        XCTAssertEqual(decoded.snapshot?.queryFieldActionBound, false)
        XCTAssertEqual(decoded.snapshot?.windowNumber, 42)
        XCTAssertEqual(decoded.snapshot?.captureX, 10)
        XCTAssertEqual(decoded.snapshot?.captureY, 20)
        XCTAssertEqual(decoded.snapshot?.captureWidth, 920)
        XCTAssertEqual(decoded.snapshot?.captureHeight, 560)
        XCTAssertEqual(decoded.snapshot?.width, 920)
        XCTAssertEqual(decoded.snapshot?.height, 560)
        XCTAssertEqual(decoded.snapshot?.distinctColorBuckets, 12)
        XCTAssertEqual(decoded.snapshot?.nonBackgroundSampleRatio, 0.18)
        XCTAssertEqual(decoded.snapshot?.averageLuminance, 0.72)
        XCTAssertEqual(decoded.snapshot?.luminanceStandardDeviation, 0.12)
        XCTAssertEqual(decoded.snapshot?.effectiveAppearanceName, "NSAppearanceNameAqua")
        XCTAssertEqual(decoded.snapshot?.usesVibrantBackground, true)
        XCTAssertEqual(decoded.snapshot?.contentCornerRadius, 16)
        XCTAssertEqual(decoded.snapshot?.resultsCornerRadius, 10)
        XCTAssertEqual(decoded.snapshot?.previewCornerRadius, 10)
        XCTAssertEqual(decoded.snapshot?.usesCustomSelectionStyle, true)
        XCTAssertEqual(decoded.snapshot?.selectedRowIndex, 1)
        XCTAssertEqual(decoded.snapshot?.activeRowText, "beta")
        XCTAssertEqual(decoded.snapshot?.previewVisible, true)
        XCTAssertEqual(decoded.snapshot?.previewWidth, 420)
        XCTAssertEqual(decoded.snapshot?.previewHeight, 360)
        XCTAssertEqual(decoded.snapshot?.resultsWidth, 430)
        XCTAssertEqual(decoded.snapshot?.resultsHeight, 360)
        XCTAssertEqual(decoded.snapshot?.previewPosition, "right")
        XCTAssertEqual(decoded.snapshot?.previewWrap, true)
        XCTAssertEqual(decoded.snapshot?.previewAnsiSpanCount, 2)
        XCTAssertEqual(decoded.snapshot?.previewAnsiRGBSpanCount, 1)
        XCTAssertEqual(decoded.snapshot?.previewAnsiBackgroundSpanCount, 1)
        XCTAssertEqual(decoded.snapshot?.previewAnsiTextStyleSpanCount, 2)
        XCTAssertEqual(decoded.snapshot?.previewContainsEscapeSequences, false)
        XCTAssertEqual(decoded.snapshot?.previewTextSample, "preview text")
        XCTAssertEqual(decoded.snapshot?.previewScrollOffsetY, 128)
        XCTAssertEqual(decoded.snapshot?.layoutViolationCount, 0)
    }
}
