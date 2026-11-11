import Foundation

/// One way of measuring one `MetricKind`. `SystemMonitor` runs a list of
/// these; adding a metric means one `MetricKind` case, one sampler file and
/// one line in `SystemMonitor.defaultSamplers`.
protocol MetricSampler: AnyObject, Sendable {
    var kind: MetricKind { get }
    /// Measure every N timer ticks (1 = every second).
    var tickInterval: Int { get }
    /// Slow samplers run on a background queue so they never block the UI.
    var runsOffMain: Bool { get }
    /// False when a reading right at `start()` would be meaningless (CPU
    /// needs two readings a tick apart).
    var samplesOnStart: Bool { get }
    /// Called by `start()` before the first tick, e.g. to re-baseline.
    func prepare()
    /// 0...100, or nil when unavailable.
    func sample() -> Double?
}

extension MetricSampler {
    var tickInterval: Int { 1 }
    var runsOffMain: Bool { false }
    var samplesOnStart: Bool { true }
    func prepare() {}
}
