import Foundation
import Darwin

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var ramUsage: Double?
    @Published private(set) var cpuUsage: Double?
    @Published private(set) var gpuUsage: Double?

    private let cpuSampler = CPUSampler()
    private var timer: Timer?
    private var gpuRefreshInFlight = false
    private var refreshCount = 0

    init() {
        _ = cpuSampler.sample()
    }

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        ramUsage = MemorySampler.sample()
        cpuUsage = cpuSampler.sample()

        refreshCount += 1
        if refreshCount == 1 || refreshCount.isMultiple(of: 2) {
            refreshGPU()
        }
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
                self?.gpuUsage = value
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
    private var previousTicks: [UInt32]?

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

        let current = withUnsafeBytes(of: load.cpu_ticks) {
            Array($0.bindMemory(to: UInt32.self))
        }
        guard let previousTicks, previousTicks.count == current.count else {
            self.previousTicks = current
            return nil
        }
        self.previousTicks = current

        let deltas = zip(current, previousTicks).map { $0 &- $1 }
        let total = deltas.reduce(UInt64(0)) { $0 + UInt64($1) }
        guard total > 0, deltas.count > Int(CPU_STATE_IDLE) else { return nil }

        let idle = UInt64(deltas[Int(CPU_STATE_IDLE)])
        return min(100, max(0, Double(total - idle) / Double(total) * 100))
    }
}

private enum GPUSampler {
    static func sample() -> Double? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        process.arguments = ["-r", "-d", "1", "-w", "0", "-c", "AGXAccelerator"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        let pattern = #"\"Device Utilization %\"\s*=\s*(\d+)"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: output,
                range: NSRange(output.startIndex..., in: output)
              ),
              let range = Range(match.range(at: 1), in: output),
              let value = Double(output[range]) else {
            return nil
        }
        return min(100, max(0, value))
    }
}
