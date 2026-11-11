import XCTest
@testable import PotatusHub

final class SnapEngineTests: XCTestCase {
    private let w: CGFloat = 160
    private let h: CGFloat = 78

    private func card(_ kind: MetricKind, x: CGFloat, y: CGFloat) -> SnapEngine.Target {
        let frame = CGRect(x: x, y: y, width: w, height: h)
        return SnapEngine.Target(frame: frame, cells: [.init(kind: kind, frame: frame)])
    }

    private func moving(x: CGFloat, y: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: w, height: h)
    }

    func testClearOverlapMerges() {
        let d = SnapEngine.decide(moving: moving(x: 100, y: 10), targets: [card(.ram, x: 0, y: 0)])
        XCTAssertEqual(d?.side, .right)
        XCTAssertEqual(d?.origin, CGPoint(x: 160, y: 0))
        XCTAssertEqual(d?.targetKind, .ram)
    }

    func testNearHorizontalEdgeSnaps() {
        let d = SnapEngine.decide(moving: moving(x: 180, y: 0), targets: [card(.ram, x: 0, y: 0)])
        XCTAssertEqual(d?.side, .right)
        XCTAssertEqual(d?.origin, CGPoint(x: 160, y: 0))
    }

    func testFarAwayDoesNotSnap() {
        XCTAssertNil(SnapEngine.decide(moving: moving(x: 260, y: 0), targets: [card(.ram, x: 0, y: 0)]))
    }

    func testDroppedBelowIsJudgedVertical() {
        let d = SnapEngine.decide(moving: moving(x: 0, y: -90), targets: [card(.ram, x: 0, y: 0)])
        XCTAssertEqual(d?.side, .below)
        XCTAssertEqual(d?.origin, CGPoint(x: 0, y: -78))
    }

    func testDroppedAboveIsJudgedVertical() {
        let d = SnapEngine.decide(moving: moving(x: 0, y: 90), targets: [card(.ram, x: 0, y: 0)])
        XCTAssertEqual(d?.side, .above)
        XCTAssertEqual(d?.origin, CGPoint(x: 0, y: 78))
    }

    func testPicksCloserOfTwoCandidates() {
        // Right edge of A is 10pt away; left edge slot of B is 20pt away.
        let a = card(.ram, x: 0, y: 0)
        let b = card(.cpu, x: 350, y: 0)
        XCTAssertEqual(SnapEngine.decide(moving: moving(x: 170, y: 0), targets: [a, b])?.targetIndex, 0)
        XCTAssertEqual(SnapEngine.decide(moving: moving(x: 170, y: 0), targets: [b, a])?.targetIndex, 1)
    }

    func testOutsideLaneToleranceDoesNotSnap() {
        // 50pt off-centre vertically exceeds the 32pt horizontal lane.
        XCTAssertNil(SnapEngine.decide(moving: moving(x: 180, y: 50), targets: [card(.ram, x: 0, y: 0)]))
    }

    func testTargetKindIsNearestCellOfGroup() {
        let ram = CGRect(x: 0, y: 0, width: w, height: h)
        let cpu = CGRect(x: w, y: 0, width: w, height: h)
        let group = SnapEngine.Target(
            frame: ram.union(cpu),
            cells: [.init(kind: .ram, frame: ram), .init(kind: .cpu, frame: cpu)]
        )
        let d = SnapEngine.decide(moving: moving(x: 100, y: 80), targets: [group])
        XCTAssertEqual(d?.side, .above)
        XCTAssertEqual(d?.targetKind, .cpu)
    }
}
