import Foundation

public struct DurationMetric: Codable, Equatable {
    public var name: String
    public var milliseconds: Double

    public init(name: String, milliseconds: Double) {
        self.name = name
        self.milliseconds = milliseconds
    }
}

public struct MetricSummary: Codable, Equatable {
    public var count: Int
    public var p50: Double
    public var p95: Double
    public var p99: Double
    public var max: Double

    public init(values: [Double]) {
        let sorted = values.sorted()
        self.count = sorted.count
        self.p50 = Self.percentile(sorted, 0.50)
        self.p95 = Self.percentile(sorted, 0.95)
        self.p99 = Self.percentile(sorted, 0.99)
        self.max = sorted.last ?? 0
    }

    public func exceeds(maximum hardMax: Double) -> Bool {
        max > hardMax
    }

    private static func percentile(_ sorted: [Double], _ percentile: Double) -> Double {
        guard !sorted.isEmpty else {
            return 0
        }
        let index = Int((Double(sorted.count - 1) * percentile).rounded(.up))
        return sorted[Swift.min(Swift.max(index, 0), sorted.count - 1)]
    }
}
