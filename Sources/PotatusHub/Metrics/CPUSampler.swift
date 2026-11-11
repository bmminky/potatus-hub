import Foundation
import Darwin

// Only ever called from the main thread, so its baseline needs no lock.
final class CPUSampler: MetricSampler, @unchecked Sendable {
    let kind = MetricKind.cpu
    let samplesOnStart = false

    private typealias Ticks = (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)
    private var previousTicks: Ticks?

    /// A pause leaves the baseline stale; re-baseline so the first reading
    /// covers one tick, not the whole time sampling was stopped.
    func prepare() {
        _ = sample()
    }

    func sample() -> Double? {
        var load = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &load) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        // cpu_ticks is indexed by CPU_STATE_USER/SYSTEM/IDLE/NICE (0...3).
        let current: Ticks = (load.cpu_ticks.0, load.cpu_ticks.1, load.cpu_ticks.2, load.cpu_ticks.3)
        guard let previous = previousTicks else {
            previousTicks = current
            return nil
        }
        previousTicks = current

        let idle = UInt64(current.idle &- previous.idle)
        let total = UInt64(current.user &- previous.user) + UInt64(current.system &- previous.system)
            + idle + UInt64(current.nice &- previous.nice)
        guard total > 0 else { return nil }
        return min(100, max(0, Double(total - idle) / Double(total) * 100))
    }
}
