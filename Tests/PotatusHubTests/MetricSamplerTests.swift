import XCTest
@testable import PotatusHub

private final class FakeSampler: MetricSampler, @unchecked Sendable {
    let kind: MetricKind
    let tickInterval: Int
    let samplesOnStart: Bool
    var values: [Double?]
    private(set) var calls = 0

    init(kind: MetricKind, tickInterval: Int = 1, samplesOnStart: Bool = true, values: [Double?]) {
        self.kind = kind
        self.tickInterval = tickInterval
        self.samplesOnStart = samplesOnStart
        self.values = values
    }

    func sample() -> Double? {
        defer { calls += 1 }
        return values[min(calls, values.count - 1)]
    }
}

@MainActor
final class MetricSamplerTests: XCTestCase {
    func testMemoryIsWithinRange() throws {
        let value = try XCTUnwrap(MemorySampler().sample())
        XCTAssertTrue((0...100).contains(value))
    }

    func testCPUFirstSampleIsNilThenInRange() {
        let cpu = CPUSampler()
        XCTAssertNil(cpu.sample())
        // Burn a little time so the tick counters move.
        var x = 0.0
        for i in 0..<2_000_000 { x += Double(i).squareRoot() }
        XCTAssertGreaterThan(x, 0)
        if let value = cpu.sample() {
            XCTAssertTrue((0...100).contains(value))
        }
    }

    func testStartSkipsSamplersThatCannotSampleYetAndRoundsValues() {
        let ram = FakeSampler(kind: .ram, values: [10.4, 10.2, 11.6])
        let cpu = FakeSampler(kind: .cpu, samplesOnStart: false, values: [50])
        let monitor = SystemMonitor(samplers: [ram, cpu])
        monitor.start()
        monitor.stop()
        XCTAssertEqual(monitor.metric(for: .ram).value, 10)
        XCTAssertNil(monitor.metric(for: .cpu).value)
        XCTAssertEqual(cpu.calls, 0)

        monitor.tick()
        XCTAssertEqual(monitor.metric(for: .ram).value, 10)
        XCTAssertEqual(monitor.metric(for: .cpu).value, 50)
        monitor.tick()
        XCTAssertEqual(monitor.metric(for: .ram).value, 12)
    }

    func testTickIntervalRunsEveryNthTickAndFirstTick() {
        let slow = FakeSampler(kind: .gpu, tickInterval: 2, values: [1])
        let monitor = SystemMonitor(samplers: [slow])
        monitor.start()   // tick 1: runs
        monitor.stop()
        XCTAssertEqual(slow.calls, 1)
        monitor.tick()    // tick 2: runs
        monitor.tick()    // tick 3: skipped
        XCTAssertEqual(slow.calls, 2)
        monitor.tick()    // tick 4: runs
        XCTAssertEqual(slow.calls, 3)
    }

    func testRefreshSamplesEverythingNow() {
        let slow = FakeSampler(kind: .gpu, tickInterval: 2, values: [7])
        let fast = FakeSampler(kind: .ram, values: [3])
        let monitor = SystemMonitor(samplers: [slow, fast])
        monitor.refresh()
        XCTAssertEqual(monitor.metric(for: .gpu).value, 7)
        XCTAssertEqual(monitor.metric(for: .ram).value, 3)
    }
}
