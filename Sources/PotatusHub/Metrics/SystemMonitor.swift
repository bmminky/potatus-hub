import Foundation

/// One metric's latest value. Each cell observes only its own, so a change
/// in one metric never re-renders another cell.
@MainActor
final class MetricValue: ObservableObject {
    @Published private(set) var value: Double?

    /// Panels show whole percents, so a change below 1% is not worth a SwiftUI
    /// update. Storing the rounded value makes the equality check exact.
    func publish(_ newValue: Double?) {
        let rounded = newValue?.rounded()
        if value != rounded { value = rounded }
    }
}

/// Runs the samplers on a 1-second timer, each at its own cadence.
@MainActor
final class SystemMonitor {
    /// The list of things to measure. A new metric adds one line here.
    nonisolated static func defaultSamplers() -> [MetricSampler] {
        [MemorySampler(), CPUSampler(), GPUSampler(), DiskSampler()]
    }

    private let samplers: [MetricSampler]
    private let values: [MetricKind: MetricValue]
    private var timer: Timer?
    private var inFlight = Set<MetricKind>()
    private var tickCount = 0

    init(samplers: [MetricSampler] = SystemMonitor.defaultSamplers()) {
        self.samplers = samplers
        var values: [MetricKind: MetricValue] = [:]
        for kind in MetricKind.allCases { values[kind] = MetricValue() }
        self.values = values
    }

    func metric(for kind: MetricKind) -> MetricValue {
        values[kind]!
    }

    /// Idempotent: the owner calls this whenever panel visibility may have
    /// changed. Sampling only runs while a panel can actually be seen.
    func start() {
        guard timer == nil else { return }
        samplers.forEach { $0.prepare() }
        tickCount = 0
        runTick(isStart: true)
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
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

    /// Measure everything now, regardless of cadence (menu "Refresh").
    func refresh() {
        for sampler in samplers { run(sampler) }
    }

    func tick() {
        runTick(isStart: false)
    }

    private func runTick(isStart: Bool) {
        tickCount += 1
        for sampler in samplers {
            if isStart && !sampler.samplesOnStart { continue }
            if tickCount == 1 || tickCount.isMultiple(of: sampler.tickInterval) {
                run(sampler)
            }
        }
    }

    private func run(_ sampler: MetricSampler) {
        let kind = sampler.kind
        guard sampler.runsOffMain else {
            metric(for: kind).publish(sampler.sample())
            return
        }
        guard !inFlight.contains(kind) else { return }
        inFlight.insert(kind)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let value = sampler.sample()
            DispatchQueue.main.async {
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.metric(for: kind).publish(value)
                    self.inFlight.remove(kind)
                }
            }
        }
    }
}
