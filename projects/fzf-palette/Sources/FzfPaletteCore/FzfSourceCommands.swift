import Foundation

public enum FzfSourceCommands {
    public static let fallbackDefaultCommand = "rg --hidden -g '!.git/' --files"
    public static let ctrlTProfileName = "ctrl-t"

    public static func defaultCommand(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        nonEmpty(environment["FZF_DEFAULT_COMMAND"]) ?? fallbackDefaultCommand
    }

    public static func ctrlTCommand(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        nonEmpty(environment["FZF_CTRL_T_COMMAND"]) ?? defaultCommand(environment: environment)
    }

    public static func command(
        forProfile profile: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        if profile == ctrlTProfileName {
            return ctrlTCommand(environment: environment)
        }
        return defaultCommand(environment: environment)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
