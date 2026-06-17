import AppKit
import FzfPaletteCore

final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let loadSettings: () -> PaletteSettings
    private let saveSettings: (PaletteSettings) -> SettingsWindowSaveResult
    private let hotkeyField = NSTextField(string: "")
    private let profileField = NSTextField(string: "default")
    private let statusLabel = NSTextField(labelWithString: "")
    private lazy var window: NSWindow = makeWindow()

    init(
        loadSettings: @escaping () -> PaletteSettings,
        saveSettings: @escaping (PaletteSettings) -> SettingsWindowSaveResult
    ) {
        self.loadSettings = loadSettings
        self.saveSettings = saveSettings
        super.init()
    }

    var isVisible: Bool {
        window.isVisible
    }

    func show() {
        loadFields()
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(hotkeyField)
    }

    func close() {
        window.orderOut(nil)
    }

    private func loadFields() {
        let settings = loadSettings()
        hotkeyField.stringValue = settings.hotkey ?? ""
        profileField.stringValue = settings.profile
        statusLabel.stringValue = "Ready"
    }

    @objc private func saveButtonPressed() {
        let settings = PaletteSettings(
            hotkey: hotkeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            profile: profileField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        switch saveSettings(settings) {
        case let .success(saved):
            hotkeyField.stringValue = saved.hotkey ?? ""
            profileField.stringValue = saved.profile
            statusLabel.stringValue = "Saved"
        case let .failure(message):
            statusLabel.stringValue = message
        }
    }

    private func makeWindow() -> NSWindow {
        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "fzf-palette Settings")
        title.font = NSFont.systemFont(ofSize: 18, weight: .semibold)

        let hotkeyLabel = NSTextField(labelWithString: "Hotkey")
        let profileLabel = NSTextField(labelWithString: "Profile")
        hotkeyField.placeholderString = HotKeyBinding.default.displayString
        profileField.placeholderString = "default"
        statusLabel.textColor = .secondaryLabelColor

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveButtonPressed))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        let grid = NSGridView(views: [
            [hotkeyLabel, hotkeyField],
            [profileLabel, profileField]
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 12
        grid.columnSpacing = 14
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).width = 260

        for view in [title, grid, statusLabel, saveButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            title.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),

            grid.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 22),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),

            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: saveButton.leadingAnchor, constant: -16),
            statusLabel.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),

            saveButton.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 24),
            saveButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            saveButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -22)
        ])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 210),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "fzf-palette Settings"
        window.contentView = content
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }
}

enum SettingsWindowSaveResult {
    case success(PaletteSettings)
    case failure(String)
}
