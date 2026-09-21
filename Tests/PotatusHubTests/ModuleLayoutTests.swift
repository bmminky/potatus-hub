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
}
