import XCTest
@testable import PotatusHub

final class DetachSpreadTests: XCTestCase {
    private func lShape() -> ModuleLayout {
        ModuleLayout(cells: [
            .init(kind: .ram, position: .init(column: 0, row: 0)),
            .init(kind: .cpu, position: .init(column: 0, row: 1)),
            .init(kind: .gpu, position: .init(column: 1, row: 1)),
        ])
    }

    private func square() -> ModuleLayout {
        ModuleLayout(cells: [
            .init(kind: .ram, position: .init(column: 0, row: 0)),
            .init(kind: .cpu, position: .init(column: 1, row: 0)),
            .init(kind: .gpu, position: .init(column: 0, row: 1)),
            .init(kind: .disk, position: .init(column: 1, row: 1)),
        ])
    }

    /// Standalone cards (78pt tall, top edge kept) after the spread.
    private func detachedFrames(_ layout: ModuleLayout) -> [CGRect] {
        let offsets = DetachSpread.offsets(for: layout)
        return layout.cells.map { cell in
            let pitch = layout.cellHeight
            let top = CGFloat(layout.rowCount - cell.position.row) * pitch
            let o = offsets[cell.kind]!
            return CGRect(
                x: CGFloat(cell.position.column) * 160 + o.dx,
                y: top - 78 + o.dy,
                width: 160, height: 78
            )
        }
    }

    private func assertNoTouchingOrOverlap(_ layout: ModuleLayout, file: StaticString = #filePath, line: UInt = #line) {
        let frames = detachedFrames(layout)
        for i in frames.indices {
            for j in frames.indices where j > i {
                XCTAssertFalse(frames[i].insetBy(dx: -0.01, dy: -0.01).intersects(frames[j]),
                               "cards \(i) and \(j) touch", file: file, line: line)
            }
        }
    }

    func testHorizontalThreeSpreadsMinusZeroPlus24() {
        let layout = ModuleLayout(kinds: [.ram, .cpu, .gpu], axis: .horizontal)
        let o = DetachSpread.offsets(for: layout)
        XCTAssertEqual(o[.ram], CGVector(dx: -24, dy: 0))
        XCTAssertEqual(o[.cpu], CGVector(dx: 0, dy: 0))
        XCTAssertEqual(o[.gpu], CGVector(dx: 24, dy: 0))
    }

    func testFourInARowSpreadsEvenly() {
        let o = DetachSpread.offsets(for: ModuleLayout(kinds: [.ram, .cpu, .gpu, .disk], axis: .horizontal))
        XCTAssertEqual([o[.ram]!.dx, o[.cpu]!.dx, o[.gpu]!.dx, o[.disk]!.dx], [-36, -12, 12, 36])
    }

    func testVerticalTopMovesUp() {
        let o = DetachSpread.offsets(for: ModuleLayout(kinds: [.ram, .cpu, .gpu], axis: .vertical))
        XCTAssertEqual(o[.ram]?.dy, 24)
        XCTAssertEqual(o[.gpu]?.dy, -24)
    }

    func testSingleCardDoesNotMove() {
        XCTAssertEqual(DetachSpread.offsets(for: ModuleLayout(kinds: [.ram]))[.ram], CGVector(dx: 0, dy: 0))
    }

    func testNoTwoCardsTouchAfterDetach() {
        assertNoTouchingOrOverlap(ModuleLayout(kinds: [.ram, .cpu, .gpu], axis: .horizontal))
        assertNoTouchingOrOverlap(ModuleLayout(kinds: [.ram, .cpu, .gpu], axis: .vertical))
        assertNoTouchingOrOverlap(ModuleLayout(kinds: [.ram, .cpu, .gpu, .disk], axis: .horizontal))
        assertNoTouchingOrOverlap(ModuleLayout(kinds: [.ram, .cpu, .gpu, .disk], axis: .vertical))
        assertNoTouchingOrOverlap(square())
        assertNoTouchingOrOverlap(lShape())
    }
}
