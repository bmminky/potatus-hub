import XCTest
@testable import PotatusHub

final class ModuleLayoutTests: XCTestCase {
    func testRemovingMiddleClosesVerticalGap() {
        let layout = ModuleLayout(kinds: [.ram, .cpu, .gpu], axis: .vertical).removing(.cpu)
        XCTAssertEqual(layout.kinds, [.ram, .gpu])
        XCTAssertEqual(layout.rowCount, 2)
        XCTAssertTrue(layout.isEdgeConnected)
    }

    func testCornerTouchDoesNotConnectModules() {
        let layout = ModuleLayout(cells: [
            .init(kind: .ram, position: .init(column: 0, row: 0)),
            .init(kind: .cpu, position: .init(column: 1, row: 1))
        ])
        XCTAssertFalse(layout.isEdgeConnected)
        XCTAssertEqual(layout.edgeConnectedComponents.count, 2)
    }

    func testSideMergePreservesLShapeAndSelectedNeighbor() {
        let layout = ModuleLayout.merged(
            moving: ModuleLayout(kinds: [.gpu]),
            other: ModuleLayout(kinds: [.ram, .cpu], axis: .vertical),
            side: .right, target: .cpu
        )
        XCTAssertEqual(layout.position(for: .gpu), .init(column: 1, row: 1))
        XCTAssertEqual(layout.cells.count, 3)
        XCTAssertTrue(layout.isEdgeConnected)
    }

    func testRemovingLCornerKeepsSurvivorsConnected() {
        let layout = ModuleLayout(cells: [
            .init(kind: .ram, position: .init(column: 0, row: 0)),
            .init(kind: .cpu, position: .init(column: 0, row: 1)),
            .init(kind: .gpu, position: .init(column: 1, row: 1))
        ]).removing(.cpu)
        XCTAssertEqual(layout.kinds.count, 2)
        XCTAssertTrue(layout.isEdgeConnected)
    }

    func testSavedLayoutRoundTripPreservesGrouping() throws {
        let original = ModuleLayout(kinds: [.gpu, .ram, .cpu], axis: .vertical)
        let restored = try JSONDecoder().decode(ModuleLayout.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored, original)
    }

    // MARK: four modules

    func testFourStackedVerticallyUsesCompactCellsAndSize() {
        let layout = ModuleLayout(kinds: [.ram, .cpu, .gpu, .disk], axis: .vertical)
        XCTAssertEqual(layout.size, NSSize(width: 160, height: 312))
        XCTAssertEqual(layout.cellHeight, 78)
    }

    func testFourInARowSize() {
        let layout = ModuleLayout(kinds: [.ram, .cpu, .gpu, .disk], axis: .horizontal)
        XCTAssertEqual(layout.size, NSSize(width: 640, height: 78))
    }

    func testThreeVerticalStillUsesTightCells() {
        let layout = ModuleLayout(kinds: [.ram, .cpu, .gpu], axis: .vertical)
        XCTAssertEqual(layout.size, NSSize(width: 160, height: 207))
        XCTAssertEqual(layout.cellHeight, 69)
    }

    private var lShape: ModuleLayout {
        ModuleLayout(cells: [
            .init(kind: .ram, position: .init(column: 0, row: 0)),
            .init(kind: .cpu, position: .init(column: 0, row: 1)),
            .init(kind: .gpu, position: .init(column: 1, row: 1)),
        ])
    }

    func testLPlusOneBecomesTwoByTwo() {
        let layout = ModuleLayout.merged(
            moving: ModuleLayout(kinds: [.disk]), other: lShape, side: .above, target: .gpu
        )
        XCTAssertEqual(layout.position(for: .disk), .init(column: 1, row: 0))
        XCTAssertEqual(layout.columnCount, 2)
        XCTAssertEqual(layout.rowCount, 2)
        XCTAssertTrue(layout.isEdgeConnected)
    }

    func testOccupiedSlotFallsBackToBoundingBoxJoin() {
        // gpu's left slot is occupied by cpu, so the disk joins the whole side.
        let layout = ModuleLayout.merged(
            moving: ModuleLayout(kinds: [.disk]), other: lShape, side: .left, target: .gpu
        )
        XCTAssertEqual(layout.cells.count, 4)
        XCTAssertTrue(layout.isEdgeConnected)
    }

    func testRemovingFromTwoByTwoKeepsL() {
        let square = ModuleLayout.merged(
            moving: ModuleLayout(kinds: [.disk]), other: lShape, side: .above, target: .gpu
        )
        let layout = square.removing(.disk)
        XCTAssertEqual(layout.cells.count, 3)
        XCTAssertEqual(layout.columnCount, 2)
        XCTAssertEqual(layout.rowCount, 2)
        XCTAssertTrue(layout.isEdgeConnected)
    }

    func testRemovingTMiddleFlattensIntoRowInReadingOrder() {
        let t = ModuleLayout(cells: [
            .init(kind: .ram, position: .init(column: 0, row: 0)),
            .init(kind: .cpu, position: .init(column: 1, row: 0)),
            .init(kind: .gpu, position: .init(column: 2, row: 0)),
            .init(kind: .disk, position: .init(column: 1, row: 1)),
        ])
        let layout = t.removing(.cpu)
        XCTAssertEqual(layout.kinds, [.ram, .gpu, .disk])
        XCTAssertEqual(layout.rowCount, 1)
        XCTAssertEqual(layout.columnCount, 3)
    }

    func testRemovingFromFourVerticalClosesGap() {
        let layout = ModuleLayout(kinds: [.ram, .cpu, .gpu, .disk], axis: .vertical).removing(.cpu)
        XCTAssertEqual(layout.kinds, [.ram, .gpu, .disk])
        XCTAssertEqual(layout.rowCount, 3)
        XCTAssertEqual(layout.columnCount, 1)
    }

    func testFourCellSavedLayoutRoundTrip() throws {
        let original = ModuleLayout.merged(
            moving: ModuleLayout(kinds: [.disk]), other: lShape, side: .above, target: .gpu
        )
        let restored = try JSONDecoder().decode(ModuleLayout.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored, original)
    }
}
