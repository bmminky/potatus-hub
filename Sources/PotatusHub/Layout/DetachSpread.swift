import Foundation

/// How far each cell of a group moves when "Detach" turns it into separate
/// cards: every neighbouring pair ends up `step` apart. Offsets are in screen
/// coordinates (y grows upward), relative to the cell's current position.
/// A direction with exactly two cells keeps the wider gap (each moves a full
/// `step`) that two-module groups have always had.
enum DetachSpread {
    static let step: CGFloat = 24

    static func offsets(for layout: ModuleLayout) -> [MetricKind: CGVector] {
        let centerColumn = CGFloat(layout.columnCount - 1) / 2
        let centerRow = CGFloat(layout.rowCount - 1) / 2
        var result: [MetricKind: CGVector] = [:]
        let columnStep = layout.columnCount == 2 ? step * 2 : step
        let rowStep = layout.rowCount == 2 ? step * 2 : step
        for cell in layout.cells {
            result[cell.kind] = CGVector(
                dx: (CGFloat(cell.position.column) - centerColumn) * columnStep,
                dy: (centerRow - CGFloat(cell.position.row)) * rowStep
            )
        }
        return result
    }
}
