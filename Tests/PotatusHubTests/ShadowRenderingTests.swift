import XCTest
import SwiftUI
import AppKit
@testable import PotatusHub

@MainActor
final class ShadowRenderingTests: XCTestCase {
    func testRenderedCardHasTransparentWindowCorners() throws {
        let layout = ModuleLayout(kinds: [.cpu, .gpu], axis: .vertical)
        let size = ModulePanel.windowSize(forVisible: layout.size)
        let renderer = ImageRenderer(content:
            ModuleGroupView(layout: layout, liftedKind: nil, monitor: SystemMonitor())
                .padding(ModulePanel.shadowMargin)
                .frame(width: size.width, height: size.height)
        )
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        // A shadow that still has alpha on the outer bitmap border will be
        // clipped by the rectangular NSWindow and appear as a square rim.
        let border = (0..<width).flatMap { x in [(x, 0), (x, height - 1)] }
            + (0..<height).flatMap { y in [(0, y), (width - 1, y)] }
        for (x, y) in border {
            XCTAssertLessThanOrEqual(bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 1, 0.01)
        }
        let center = try XCTUnwrap(bitmap.colorAt(x: width / 2, y: height / 2))
        XCTAssertGreaterThan(center.alphaComponent, 0.8)
    }
}
