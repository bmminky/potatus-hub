import Foundation
import Darwin
import IOKit

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var ramUsage: Double?
    @Published private(set) var cpuUsage: Double?
    @Published private(set) var gpuUsage: Double?

    private let cpuSampler = CPUSampler()
    private var timer: Timer?
    private var gpuRefreshInFlight = false
    private var refreshCount = 0

    /// Idempotent: AppDelegate calls this whenever panel visibility may have
    /// changed. Sampling only runs while a panel can actually be seen.
    func start() {
        guard timer == nil else { return }
        // A pause leaves the CPU baseline stale; re-baseline so the first
        // reading covers one tick, not the whole time we were stopped.
        _ = cpuSampler.sample()
        refreshCount = 0
        refresh(includeCPU: false)
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // Lets the system coalesce this wakeup with other timers.
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        refresh(includeCPU: true)
    }

    private func refresh(includeCPU: Bool) {
        publish(\.ramUsage, MemorySampler.sample())
        if includeCPU { publish(\.cpuUsage, cpuSampler.sample()) }

        refreshCount += 1
        if refreshCount == 1 || refreshCount.isMultiple(of: 2) {
            refreshGPU()
        }
    }

    /// Panels show whole percents, so a change below 1% is not worth a SwiftUI
    /// update. Storing the rounded value makes the equality check exact.
    private func publish(_ keyPath: ReferenceWritableKeyPath<SystemMonitor, Double?>, _ value: Double?) {
        let rounded = value?.rounded()
        if self[keyPath: keyPath] != rounded { self[keyPath: keyPath] = rounded }
    }

    func value(for kind: MetricKind) -> Double? {
        switch kind {
        case .ram: return ramUsage
        case .cpu: return cpuUsage
        case .gpu: return gpuUsage
        }
    }

    private func refreshGPU() {
        guard !gpuRefreshInFlight else { return }
        gpuRefreshInFlight = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let value = GPUSampler.sample()
            DispatchQueue.main.async {
                self?.publish(\.gpuUsage, value)
                self?.gpuRefreshInFlight = false
            }
        }
    }
}

private enum MemorySampler {
    static func sample() -> Double? {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let pageSize = UInt64(vm_kernel_page_size)
        let usedPages = UInt64(statistics.active_count)
            + UInt64(statistics.inactive_count)
            + UInt64(statistics.wire_count)
            + UInt64(statistics.compressor_page_count)
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        guard totalBytes > 0 else { return nil }

        let usedBytes = min(totalBytes, usedPages * pageSize)
        return min(100, max(0, Double(usedBytes) / Double(totalBytes) * 100))
    }
}

private final class CPUSampler {
    private typealias Ticks = (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)
    private var previousTicks: Ticks?

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

private enum GPUSampler {
    /// Same counter `ioreg -c AGXAccelerator` prints, read in-process so each
    /// sample no longer forks a subprocess and parses its whole output.
    static func sample() -> Double? {
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
