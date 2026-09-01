import AppKit

struct ModuleGridPosition: Codable, Hashable {
    var column: Int
    var row: Int
}

struct ModuleLayoutCell: Codable, Hashable {
    let kind: MetricKind
    var position: ModuleGridPosition
}

/// A compact grid for the three supported modules. It preserves an L-shaped
/// arrangement rather than flattening it back into a row or column.
struct ModuleLayout: Codable, Hashable {
    var cells: [ModuleLayoutCell]

    init(kinds: [MetricKind], axis: ModuleAxis = .horizontal) {
        cells = kinds.enumerated().map { index, kind in
            ModuleLayoutCell(
                kind: kind,
                position: axis == .horizontal
                    ? ModuleGridPosition(column: index, row: 0)
                    : ModuleGridPosition(column: 0, row: index)
            )
        }
    }

    init(cells: [ModuleLayoutCell]) {
        self.cells = cells
        normalize()
    }

    var kinds: [MetricKind] {
        cells.sorted {
            $0.position.row == $1.position.row
                ? $0.position.column < $1.position.column
                : $0.position.row < $1.position.row
        }.map(\.kind)
    }

    var columnCount: Int {
        (cells.map(\.position.column).max() ?? -1) + 1
    }

    var rowCount: Int {
        (cells.map(\.position.row).max() ?? -1) + 1
    }

    var size: NSSize {
        NSSize(
            width: ModulePanel.cellSize.width * CGFloat(columnCount),
            height: cellHeight * CGFloat(rowCount)
        )
    }

    /// Every normal module row matches potatoken hub's 78pt compact height.
    /// The sole exception is an exact three-module vertical stack: its 69pt
    /// pitch makes the complete stack match the 207pt large panel height.
    var cellHeight: CGFloat {
        isThreeModuleVerticalStack ? ModulePanel.cellSize.height : ModulePanel.singlePanelHeight
    }

    private var isThreeModuleVerticalStack: Bool {
        cells.count == 3 && columnCount == 1 && rowCount == 3
    }

    var primaryAxis: ModuleAxis {
        columnCount >= rowCount ? .horizontal : .vertical
    }

    /// Cells belong to the same movable module only when they share a full
    /// horizontal or vertical edge. A corner touch is visual proximity, not a
    /// physical connection, so it must never make two cards travel together.
    var edgeConnectedComponents: [[ModuleLayoutCell]] {
        var remaining = Dictionary(uniqueKeysWithValues: cells.map {
            (ModuleGridPosition(column: $0.position.column, row: $0.position.row), $0)
        })
        var components: [[ModuleLayoutCell]] = []

        while let seed = remaining.values.first {
            var component: [ModuleLayoutCell] = []
            var queue = [seed]
            remaining.removeValue(forKey: seed.position)

            while let cell = queue.popLast() {
                component.append(cell)
                let neighbors = [
                    ModuleGridPosition(column: cell.position.column - 1, row: cell.position.row),
                    ModuleGridPosition(column: cell.position.column + 1, row: cell.position.row),
                    ModuleGridPosition(column: cell.position.column, row: cell.position.row - 1),
                    ModuleGridPosition(column: cell.position.column, row: cell.position.row + 1),
                ]
                for position in neighbors {
                    if let neighbor = remaining.removeValue(forKey: position) {
                        queue.append(neighbor)
                    }
                }
            }
            components.append(component)
        }

        return components
    }

    var isEdgeConnected: Bool {
        edgeConnectedComponents.count <= 1
    }

    func position(for kind: MetricKind) -> ModuleGridPosition? {
        cells.first(where: { $0.kind == kind })?.position
    }

    func removing(_ kind: MetricKind) -> ModuleLayout {
        compactedAfterRemoval(cells.filter { $0.kind != kind })
    }

    func filtering(_ allowed: Set<MetricKind>) -> ModuleLayout {
        compactedAfterRemoval(cells.filter { allowed.contains($0.kind) })
    }

    static func merged(
        moving: ModuleLayout,
        other: ModuleLayout,
        side: MergeDirection,
        target: MetricKind?
    ) -> ModuleLayout {
        // Adding one module to the side of a perpendicular row/column creates
        // an L layout at the nearest cell instead of flattening the group.
        if moving.cells.count == 1,
           let movingCell = moving.cells.first,
           let target,
           let targetPosition = other.position(for: target),
           side.axis == .horizontal,
           other.columnCount == 1 {
            let column = side == .left ? -1 : 1
            return ModuleLayout(cells: other.cells + [
                ModuleLayoutCell(
                    kind: movingCell.kind,
                    position: ModuleGridPosition(column: column, row: targetPosition.row)
                ),
            ])
        }

        if moving.cells.count == 1,
           let movingCell = moving.cells.first,
           let target,
           let targetPosition = other.position(for: target),
           side.axis == .vertical,
           other.rowCount == 1 {
            let row = side == .above ? -1 : 1
            return ModuleLayout(cells: other.cells + [
                ModuleLayoutCell(
                    kind: movingCell.kind,
                    position: ModuleGridPosition(column: targetPosition.column, row: row)
                ),
            ])
        }

        var left = moving.cells
        var right = other.cells
        switch side {
        case .left:
            right = right.map { cell in
                var cell = cell
                cell.position.column += moving.columnCount
                return cell
            }
        case .right:
            left = left.map { cell in
                var cell = cell
                cell.position.column += other.columnCount
                return cell
            }
        case .above:
            right = right.map { cell in
                var cell = cell
                cell.position.row += moving.rowCount
                return cell
            }
        case .below:
            left = left.map { cell in
                var cell = cell
                cell.position.row += other.rowCount
                return cell
            }
        }
        return ModuleLayout(cells: left + right)
    }

    private mutating func normalize() {
        guard !cells.isEmpty else { return }
        let minColumn = cells.map(\.position.column).min() ?? 0
        let minRow = cells.map(\.position.row).min() ?? 0
        for index in cells.indices {
            cells[index].position.column -= minColumn
            cells[index].position.row -= minRow
        }
    }

    /// A row or column has no intentional blank space. If its middle cell is
    /// removed, close that gap so the two survivors remain attached. L-shaped
    /// grids intentionally retain their empty corner and are left untouched.
    private func compactedAfterRemoval(_ remaining: [ModuleLayoutCell]) -> ModuleLayout {
        var result = ModuleLayout(cells: remaining)
        if columnCount == 1 {
            let rows = Array(Set(result.cells.map(\.position.row))).sorted()
            for index in result.cells.indices {
                result.cells[index].position.row = rows.firstIndex(of: result.cells[index].position.row) ?? 0
            }
        } else if rowCount == 1 {
            let columns = Array(Set(result.cells.map(\.position.column))).sorted()
            for index in result.cells.indices {
                result.cells[index].position.column = columns.firstIndex(of: result.cells[index].position.column) ?? 0
            }
        }
        return result
    }
}

enum MergeDirection: String, Codable {
    case left
    case right
    case below
    case above

    var axis: ModuleAxis {
        switch self {
        case .left, .right: return .horizontal
        case .below, .above: return .vertical
        }
    }
}
