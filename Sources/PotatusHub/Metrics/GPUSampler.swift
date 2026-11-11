import Foundation
import IOKit

final class GPUSampler: MetricSampler {
    let kind = MetricKind.gpu
    let tickInterval = 2
    let runsOffMain = true

    /// Same counter `ioreg -c AGXAccelerator` prints, read in-process so each
    /// sample no longer forks a subprocess and parses its whole output.
    func sample() -> Double? {
        guard let matching = IOServiceMatching("AGXAccelerator") else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard let property = IORegistryEntryCreateCFProperty(
                service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0
              )?.takeRetainedValue(),
              let statistics = property as? [String: Any],
              let value = (statistics["Device Utilization %"] as? NSNumber)?.doubleValue else {
            return nil
        }
        return min(100, max(0, value))
    }
}
