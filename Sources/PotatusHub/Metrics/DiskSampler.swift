import Foundation

/// Main-drive usage in percent. Uses the same "available for important
/// usage" figure Finder shows (purgeable space counts as free), falling back
/// to plain available capacity when that is missing or zero.
final class DiskSampler: MetricSampler {
    let kind = MetricKind.disk
    let tickInterval = 30
    let runsOffMain = true

    func sample() -> Double? {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity else { return nil }
        var available = values.volumeAvailableCapacityForImportantUsage ?? 0
        if available <= 0 {
            available = Int64(values.volumeAvailableCapacity ?? 0)
        }
        return Self.usage(total: Int64(total), available: available)
    }

    static func usage(total: Int64, available: Int64) -> Double? {
        guard total > 0 else { return nil }
        let used = Double(total - available) / Double(total) * 100
        return min(100, max(0, used))
    }
}
