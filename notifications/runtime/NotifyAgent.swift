import AppKit
import Foundation
import UserNotifications

struct NotificationActionPayload: Codable {
    var id: String
    var title: String?
    var kind: String
    var target: String?
    var argv: [String]?
    var minutes: Int?
}

struct NotificationPayload: Codable {
    var notificationId: String
    var title: String
    var subtitle: String?
    var body: String
    var sound: String?
    var defaultAction: NotificationActionPayload?
    var actions: [NotificationActionPayload]
}

struct ProfileMetadata: Codable {
    var profileName: String
    var bundleId: String
    var displayName: String
    var permissionPrompt: String?
}

final class NotificationAgentDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var exitWorkItem: DispatchWorkItem?
    private lazy var profileMetadata: ProfileMetadata? = loadProfileMetadata()
    private lazy var logFileURL: URL? = makeLogFileURL()

    func applicationDidFinishLaunching(_ notification: Notification) {
        center.delegate = self

        if let payload = parseSendPayload() {
            scheduleNotification(payload)
            return
        }

        // Notification Center may launch the app after a click with no args.
        scheduleExit(after: 5.0)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer {
            completionHandler()
            scheduleExit(after: 0.5)
        }

        guard let payload = decodePayload(from: response.notification.request.content.userInfo) else {
            return
        }

        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            if let defaultAction = payload.defaultAction {
                dispatch(action: defaultAction, payload: payload)
            } else if let firstAction = payload.actions.first {
                dispatch(action: firstAction, payload: payload)
            }
        case UNNotificationDismissActionIdentifier:
            break
        default:
            if let action = payload.actions.first(where: { $0.id == response.actionIdentifier }) {
                dispatch(action: action, payload: payload)
            }
        }
    }

    private func scheduleNotification(_ payload: NotificationPayload) {
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.handleNotificationSettings(settings, payload: payload)
            }
        }
    }

    private func handleNotificationSettings(_ settings: UNNotificationSettings, payload: NotificationPayload) {
        log("Notification settings: authorization=\(settings.authorizationStatus.rawValue) alert=\(settings.alertSetting.rawValue) sound=\(settings.soundSetting.rawValue)")

        if settings.authorizationStatus == .notDetermined {
            guard presentPermissionPrimer() else {
                scheduleExit(after: 0.25)
                return
            }

            requestAuthorizationAndSchedule(payload)
            return
        }

        guard settings.authorizationStatus != .denied else {
            presentSettingsGuidance()
            return
        }

        registerCategory(for: payload) {
            self.addNotification(payload, delaySeconds: 1.0)
        }
    }

    private func requestAuthorizationAndSchedule(_ payload: NotificationPayload) {
        activateForAlert()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            DispatchQueue.main.async {
                if let error {
                    self.log("Failed to request notification permission: \(error.localizedDescription)")
                    self.scheduleExit(after: 0.25)
                    return
                }

                guard granted else {
                    self.log("Notification permission prompt was dismissed or denied.")
                    self.scheduleExit(after: 0.25)
                    return
                }

                // On first grant, macOS can lag briefly before getNotificationSettings
                // reflects the new authorized state. Trust the grant callback and
                // schedule the notification instead of bouncing the user into Settings.
                self.registerCategory(for: payload) {
                    self.addNotification(payload, delaySeconds: 1.0)
                }
            }
        }
    }

    private func presentPermissionPrimer() -> Bool {
        log("Presenting permission primer.")
        let alert = NSAlert()
        alert.messageText = "Enable \(appDisplayName) Notifications?"
        alert.informativeText = permissionPromptText()
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Enable Notifications")
        alert.addButton(withTitle: "Not Now")
        activateForAlert()
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func presentSettingsGuidance() {
        log("Presenting settings guidance.")
        let alert = NSAlert()
        alert.messageText = "Enable \(appDisplayName) Notifications"
        alert.informativeText =
            "Notifications are currently disabled for \(appDisplayName). Open System Settings > Notifications and allow alerts for this app, then try again."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        activateForAlert()

        if alert.runModal() == .alertFirstButtonReturn {
            openNotificationSettings()
        }

        scheduleExit(after: 0.25)
    }

    private func activateForAlert() {
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openNotificationSettings() {
        let settingsURLs = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.notifications",
        ]

        for rawValue in settingsURLs {
            guard let url = URL(string: rawValue) else {
                continue
            }

            if NSWorkspace.shared.open(url) {
                return
            }
        }

        let fallbackApps = [
            "/System/Applications/System Settings.app",
            "/System/Applications/System Preferences.app",
        ]

        for path in fallbackApps where FileManager.default.fileExists(atPath: path) {
            if NSWorkspace.shared.open(URL(fileURLWithPath: path)) {
                return
            }
        }
    }

    private func registerCategory(for payload: NotificationPayload, completion: @escaping () -> Void) {
        let visibleActions = payload.actions.prefix(4).compactMap { action -> UNNotificationAction? in
            guard let title = action.title, !title.isEmpty else {
                return nil
            }
            return UNNotificationAction(identifier: action.id, title: title, options: [])
        }

        let category = UNNotificationCategory(
            identifier: categoryIdentifier(for: payload),
            actions: Array(visibleActions),
            intentIdentifiers: [],
            options: []
        )

        center.getNotificationCategories { existingCategories in
            DispatchQueue.main.async {
                var mergedCategories = Dictionary(
                    uniqueKeysWithValues: existingCategories.map { ($0.identifier, $0) }
                )
                mergedCategories[category.identifier] = category
                self.center.setNotificationCategories(Set(mergedCategories.values))
                completion()
            }
        }
    }

    private func addNotification(_ payload: NotificationPayload, delaySeconds: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = payload.title
        if let subtitle = payload.subtitle, !subtitle.isEmpty {
            content.subtitle = subtitle
        }
        content.body = payload.body

        if let sound = payload.sound, !sound.isEmpty {
            if sound == "default" {
                content.sound = .default
            } else {
                content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: sound))
            }
        }

        content.categoryIdentifier = categoryIdentifier(for: payload)

        if let payloadData = try? encoder.encode(payload),
           let payloadJSON = String(data: payloadData, encoding: .utf8) {
            content.userInfo = ["notificationPayload": payloadJSON]
        }

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1.0, delaySeconds),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: payload.notificationId,
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            DispatchQueue.main.async {
                if let error {
                    self.log("Failed to schedule notification: \(error.localizedDescription)")
                }
                self.scheduleExit(after: 0.75)
            }
        }
    }

    private func dispatch(action: NotificationActionPayload, payload: NotificationPayload) {
        switch action.kind {
        case "open-url":
            guard let target = action.target, let url = URL(string: target) else {
                log("Invalid open-url target: \(action.target ?? "(nil)")")
                return
            }
            NSWorkspace.shared.open(url)
        case "run-command":
            guard let argv = action.argv, let executable = argv.first, !executable.isEmpty else {
                log("Invalid run-command argv.")
                return
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = Array(argv.dropFirst())

            do {
                try process.run()
            } catch {
                log("Failed to launch command: \(error.localizedDescription)")
            }
        case "reschedule":
            guard let minutes = action.minutes, minutes > 0 else {
                log("Invalid reschedule action: \(String(describing: action.minutes))")
                return
            }

            var nextPayload = payload
            nextPayload.notificationId = "\(payload.notificationId)-\(UUID().uuidString)"
            registerCategory(for: nextPayload) {
                self.addNotification(nextPayload, delaySeconds: TimeInterval(minutes * 60))
            }
        default:
            log("Unknown action kind: \(action.kind)")
        }
    }

    private func parseSendPayload() -> NotificationPayload? {
        let arguments = CommandLine.arguments
        guard let flagIndex = arguments.firstIndex(of: "--send-base64"),
              arguments.indices.contains(flagIndex + 1) else {
            return nil
        }

        let encoded = arguments[flagIndex + 1]
        guard let data = Data(base64Encoded: encoded) else {
            log("Could not decode notification payload.")
            return nil
        }

        do {
            return try decoder.decode(NotificationPayload.self, from: data)
        } catch {
            log("Could not parse notification payload: \(error.localizedDescription)")
            return nil
        }
    }

    private func decodePayload(from userInfo: [AnyHashable: Any]) -> NotificationPayload? {
        guard let json = userInfo["notificationPayload"] as? String,
              let data = json.data(using: .utf8) else {
            return nil
        }

        return try? decoder.decode(NotificationPayload.self, from: data)
    }

    private func categoryIdentifier(for payload: NotificationPayload) -> String {
        return "notify.\(payload.notificationId)"
    }

    private var appDisplayName: String {
        if let displayName = profileMetadata?.displayName,
           !displayName.isEmpty {
            return displayName
        }

        if let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !displayName.isEmpty {
            return displayName
        }

        return Bundle.main.bundleURL.deletingPathExtension().lastPathComponent
    }

    private func permissionPromptText() -> String {
        if let prompt = profileMetadata?.permissionPrompt?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !prompt.isEmpty {
            return prompt
        }

        return "\(appDisplayName) needs notification permission so it can show alerts and run the action attached to a notification when you click it."
    }

    private func loadProfileMetadata() -> ProfileMetadata? {
        guard let profileURL = Bundle.main.url(forResource: "profile", withExtension: "json") else {
            return nil
        }

        do {
            let data = try Data(contentsOf: profileURL)
            return try decoder.decode(ProfileMetadata.self, from: data)
        } catch {
            log("Could not load profile metadata: \(error.localizedDescription)")
            return nil
        }
    }

    private func scheduleExit(after delay: TimeInterval) {
        exitWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            NSApp.terminate(nil)
        }
        exitWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func log(_ message: String) {
        fputs("[notify-agent] \(message)\n", stderr)

        guard let logFileURL else {
            return
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"

        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFileURL.path),
               let handle = try? FileHandle(forWritingTo: logFileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: logFileURL, options: .atomic)
            }
        }
    }

    private func makeLogFileURL() -> URL? {
        let bundleID = Bundle.main.bundleIdentifier ?? profileMetadata?.bundleId ?? "unknown"
        let logsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/NotificationApps", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
            return logsDirectory.appendingPathComponent("\(bundleID).log")
        } catch {
            fputs("[notify-agent] Failed to create log directory: \(error.localizedDescription)\n", stderr)
            return nil
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = NotificationAgentDelegate()
app.delegate = delegate
app.run()
