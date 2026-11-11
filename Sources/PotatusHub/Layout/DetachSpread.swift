import Foundation

/// How far each cell of a group moves when "Detach" turns it into separate
/// cards: every neighbouring pair ends up `step` apart. Offsets are in screen
/// coordinates (y grows upward), relative to the cell's current position.
enum DetachSpread {
    static let step: CGFloat = 24

    static func offsets(for layout: ModuleLayout) -> [MetricKind: CGVector] {
        let centerColumn = CGFloat(layout.columnCount - 1) / 2
        let centerRow = CGFloat(layout.rowCount - 1) / 2
        var result: [MetricKind: CGVector] = [:]
        for cell in layout.cells {
            result[cell.kind] = CGVector(
                dx: (CGFloat(cell.position.column) - centerColumn) * step,
                dy: (centerRow - CGFloat(cell.position.row)) * step
            )
        }
        return result
    }
}
