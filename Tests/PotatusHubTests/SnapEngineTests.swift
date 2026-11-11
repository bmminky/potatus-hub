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

    // MARK: empty slot of an L-shaped group

    /// 2x2 grid minus one corner. Grid (column, row), row 0 on top.
    private func lGroup(missing: (Int, Int)) -> (SnapEngine.Target, ModuleLayout, [(Int, Int)]) {
        let kinds: [MetricKind] = [.ram, .cpu, .gpu]
        let slots = [(0, 0), (1, 0), (0, 1), (1, 1)].filter { $0 != missing }
        func frame(_ c: Int, _ r: Int) -> CGRect {
            CGRect(x: CGFloat(c) * w, y: CGFloat(1 - r) * h, width: w, height: h)
        }
        let cells = zip(kinds, slots).map { SnapEngine.Cell(kind: $0, frame: frame($1.0, $1.1)) }
        let layout = ModuleLayout(cells: zip(kinds, slots).map {
            ModuleLayoutCell(kind: $0, position: .init(column: $1.0, row: $1.1))
        })
        let target = SnapEngine.Target(frame: CGRect(x: 0, y: 0, width: 2 * w, height: 2 * h), cells: cells)
        return (target, layout, slots)
    }

    func testDroppingIntoEmptySlotFillsItInAllFourOrientations() throws {
        for missing in [(0, 0), (1, 0), (0, 1), (1, 1)] {
            let (target, layout, _) = lGroup(missing: missing)
            let slotOrigin = CGPoint(x: CGFloat(missing.0) * w, y: CGFloat(1 - missing.1) * h)
            for jitter in [CGPoint(x: 0, y: 0), CGPoint(x: 12, y: -9), CGPoint(x: -15, y: 11)] {
                let card = moving(x: slotOrigin.x + jitter.x, y: slotOrigin.y + jitter.y)
                let d = try XCTUnwrap(SnapEngine.decide(moving: card, movingIsSingleCard: true, targets: [target]))
                XCTAssertEqual(d.origin, slotOrigin, "missing \(missing) jitter \(jitter)")
                let merged = ModuleLayout.merged(
                    moving: ModuleLayout(kinds: [.disk]), other: layout, side: d.side, target: d.targetKind
                )
                XCTAssertEqual(merged.columnCount, 2)
                XCTAssertEqual(merged.rowCount, 2)
                XCTAssertEqual(merged.cells.count, 4)
                XCTAssertEqual(merged.position(for: .disk), .init(column: missing.0, row: missing.1))
            }
        }
    }

    func testEmptySlotRuleIgnoredWhenMovingAGroup() {
        let (target, _, _) = lGroup(missing: (1, 0))
        let card = moving(x: w, y: h)   // centred in the empty slot
        let withRule = SnapEngine.decide(moving: card, movingIsSingleCard: true, targets: [target])
        let withoutRule = SnapEngine.decide(moving: card, movingIsSingleCard: false, targets: [target])
        XCTAssertEqual(withRule?.origin, CGPoint(x: w, y: h))
        XCTAssertNotEqual(withoutRule?.origin, withRule?.origin)
    }
}
