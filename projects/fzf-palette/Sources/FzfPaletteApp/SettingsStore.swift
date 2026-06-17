import Foundation
import FzfPaletteCore

final class SettingsStore {
    private let defaults: UserDefaults
    private let hotkeyKey = "settings.hotkey"
    private let profileKey = "settings.profile"

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        if let suite = environment["FZF_PALETTE_USER_DEFAULTS_SUITE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !suite.isEmpty,
           let suiteDefaults = UserDefaults(suiteName: suite) {
            defaults = suiteDefaults
        } else {
            defaults = .standard
        }
    }

    func load() -> PaletteSettings {
        PaletteSettings(
            hotkey: defaults.string(forKey: hotkeyKey),
            profile: defaults.string(forKey: profileKey) ?? "default"
        )
    }

    func save(_ settings: PaletteSettings) {
        if let hotkey = settings.hotkey?.trimmingCharacters(in: .whitespacesAndNewlines), !hotkey.isEmpty {
            defaults.set(hotkey, forKey: hotkeyKey)
        } else {
            defaults.removeObject(forKey: hotkeyKey)
        }
        defaults.set(settings.profile.isEmpty ? "default" : settings.profile, forKey: profileKey)
        defaults.synchronize()
    }

    func clear() {
        defaults.removeObject(forKey: hotkeyKey)
        defaults.removeObject(forKey: profileKey)
        defaults.synchronize()
    }
}
