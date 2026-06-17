import Foundation

public struct EnvironmentSnapshot: Codable, Equatable {
    public var values: [String: String]

    public init(values: [String: String] = ProcessInfo.processInfo.environment) {
        self.values = values
    }

    public func merged(with overrides: [String: String]) -> EnvironmentSnapshot {
        var merged = values
        for (key, value) in overrides {
            merged[key] = value
        }
        return EnvironmentSnapshot(values: merged)
    }

    public static func parseNullSeparatedEnv(_ data: Data) -> EnvironmentSnapshot {
        let parts = data.split(separator: 0)
        var values: [String: String] = [:]

        for part in parts {
            guard let text = String(data: Data(part), encoding: .utf8),
                  let equals = text.firstIndex(of: "=") else {
                continue
            }
            let key = String(text[..<equals])
            let value = String(text[text.index(after: equals)...])
            values[key] = value
        }

        return EnvironmentSnapshot(values: values)
    }
}
