import XCTest
@testable import PotatusHub

@MainActor
final class TransitionGateTests: XCTestCase {
    func testBeginEndIsPlainFlag() {
        let gate = TransitionGate()
        XCTAssertFalse(gate.isBusy)
        gate.begin()
        gate.begin()
        XCTAssertTrue(gate.isBusy)
        gate.end()
        XCTAssertFalse(gate.isBusy)
    }

    func testReleasesItselfAndSavesIfEndNeverComes() {
        let gate = TransitionGate()
        let released = expectation(description: "timeout")
        gate.onTimeout = { released.fulfill() }
        gate.begin()
        wait(for: [released], timeout: TransitionGate.timeout + 1)
        XCTAssertFalse(gate.isBusy)
    }

    func testEndCancelsTimeout() {
        let gate = TransitionGate()
        let fired = expectation(description: "must not fire")
        fired.isInverted = true
        gate.onTimeout = { fired.fulfill() }
        gate.begin()
        gate.end()
        wait(for: [fired], timeout: TransitionGate.timeout + 0.5)
    }
}
