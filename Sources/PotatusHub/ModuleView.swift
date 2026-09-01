import SwiftUI
import AppKit

enum ModuleAxis: String, Codable {
    case horizontal
    case vertical
}

struct ModuleGroupView: View {
    let layout: ModuleLayout
    let liftedKind: MetricKind?
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // The shell must fill the window's live presentation size.
                // Fixing it to `layout.size` made the destination card sit at
                // the animated window's top-left until the frame caught up,
                // which looked like a diagonal wobble even though the window
                // itself remained centred.
                ModuleSurfaceShape(layout: layout)
                    .fill(.regularMaterial)

                // Keep the destination module grid centred while the shell
                // expands or contracts around it. The middle module therefore
                // stays on the same screen point in both directions, and the
                // outer modules reveal from that centre instead of walking in
                // from a corner.
                ZStack(alignment: .topLeading) {
                    ModuleDividerShape(layout: layout)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    cells
                }
                .frame(width: layout.size.width, height: layout.size.height)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    @ViewBuilder
    private var cells: some View {
        ForEach(layout.cells, id: \.kind) { cell in
            let kind = cell.kind
            ModuleCellView(kind: kind, height: layout.cellHeight, monitor: monitor)
                .opacity(liftedKind == kind ? 0.18 : 1)
                .animation(.easeOut(duration: 0.14), value: liftedKind)
                .offset(
                    x: CGFloat(cell.position.column) * ModulePanel.cellSize.width,
                    y: CGFloat(cell.position.row) * layout.cellHeight
                )
        }
    }
}

private struct ModuleSurfaceShape: Shape {
    let layout: ModuleLayout
    private let radius: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        // potatoken hub uses SwiftUI's continuous 14pt card corners. A plain
        // circular arc has the same numeric radius but a visibly different
        // shoulder, so use the exact curve for ordinary row/column groups.
        if layout.cells.count == layout.columnCount * layout.rowCount {
            return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
        }

        var path = Path()
        for cell in layout.cells {
            let position = cell.position
            let tile = CGRect(
                x: rect.minX + CGFloat(position.column) * ModulePanel.cellSize.width,
                y: rect.minY + CGFloat(position.row) * layout.cellHeight,
                width: ModulePanel.cellSize.width,
                height: layout.cellHeight
            )
            let top = !contains(column: position.column, row: position.row - 1)
            let bottom = !contains(column: position.column, row: position.row + 1)
            let left = !contains(column: position.column - 1, row: position.row)
            let right = !contains(column: position.column + 1, row: position.row)
            appendTile(
                to: &path,
                rect: tile,
                topLeft: top && left,
                topRight: top && right,
                bottomRight: bottom && right,
                bottomLeft: bottom && left
            )
        }
        return path
    }

    private func contains(column: Int, row: Int) -> Bool {
        layout.cells.contains { $0.position.column == column && $0.position.row == row }
    }

    private func appendTile(
        to path: inout Path,
        rect: CGRect,
        topLeft: Bool,
        topRight: Bool,
        bottomRight: Bool,
        bottomLeft: Bool
    ) {
        let r = radius
        path.move(to: CGPoint(x: rect.minX + (topLeft ? r : 0), y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - (topRight ? r : 0), y: rect.minY))
        if topRight {
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - (bottomRight ? r : 0)))
        if bottomRight {
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.minX + (bottomLeft ? r : 0), y: rect.maxY))
        if bottomLeft {
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + (topLeft ? r : 0)))
        if topLeft {
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        }
        path.closeSubpath()
    }
}

/// Draws only edges facing empty space. Adjacent module cells therefore share
/// the material continuously while the whole group keeps potatoken hub's thin,
/// translucent white perimeter band.
private struct ModuleBorderShape: Shape {
    let layout: ModuleLayout
    private let radius: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        // Keep the perimeter stroke on the same continuous curve as the
        // material surface. L-shaped groups still use the custom edge path
        // below because they have intentional inner corners.
        if layout.cells.count == layout.columnCount * layout.rowCount {
            return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
        }

        var path = Path()
        for cell in layout.cells {
            let position = cell.position
            let tile = CGRect(
                x: rect.minX + CGFloat(position.column) * ModulePanel.cellSize.width,
                y: rect.minY + CGFloat(position.row) * layout.cellHeight,
                width: ModulePanel.cellSize.width,
                height: layout.cellHeight
            )
            let top = !contains(column: position.column, row: position.row - 1)
            let bottom = !contains(column: position.column, row: position.row + 1)
            let left = !contains(column: position.column - 1, row: position.row)
            let right = !contains(column: position.column + 1, row: position.row)
            let topLeft = top && left
            let topRight = top && right
            let bottomRight = bottom && right
            let bottomLeft = bottom && left
            let r = radius

            if top {
                path.move(to: CGPoint(x: tile.minX + (topLeft ? r : 0), y: tile.minY))
                path.addLine(to: CGPoint(x: tile.maxX - (topRight ? r : 0), y: tile.minY))
            }
            if topRight {
                path.addArc(center: CGPoint(x: tile.maxX - r, y: tile.minY + r), radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            }
            if right {
                path.move(to: CGPoint(x: tile.maxX, y: tile.minY + (topRight ? r : 0)))
                path.addLine(to: CGPoint(x: tile.maxX, y: tile.maxY - (bottomRight ? r : 0)))
            }
            if bottomRight {
                path.addArc(center: CGPoint(x: tile.maxX - r, y: tile.maxY - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            }
            if bottom {
                path.move(to: CGPoint(x: tile.maxX - (bottomRight ? r : 0), y: tile.maxY))
                path.addLine(to: CGPoint(x: tile.minX + (bottomLeft ? r : 0), y: tile.maxY))
            }
            if bottomLeft {
                path.addArc(center: CGPoint(x: tile.minX + r, y: tile.maxY - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            }
            if left {
                path.move(to: CGPoint(x: tile.minX, y: tile.maxY - (bottomLeft ? r : 0)))
                path.addLine(to: CGPoint(x: tile.minX, y: tile.minY + (topLeft ? r : 0)))
            }
            if topLeft {
                path.addArc(center: CGPoint(x: tile.minX + r, y: tile.minY + r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            }
        }
        return path
    }

    private func contains(column: Int, row: Int) -> Bool {
        layout.cells.contains { $0.position.column == column && $0.position.row == row }
    }
}

/// Each shared edge is drawn once using AppKit's separator color, the same
/// system color SwiftUI's Divider resolves to in potatoken hub.
private struct ModuleDividerShape: Shape {
    let layout: ModuleLayout

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for cell in layout.cells {
            let position = cell.position
            let x = rect.minX + CGFloat(position.column) * ModulePanel.cellSize.width
            let y = rect.minY + CGFloat(position.row) * layout.cellHeight
            if contains(column: position.column + 1, row: position.row) {
                path.move(to: CGPoint(x: x + ModulePanel.cellSize.width, y: y))
                path.addLine(to: CGPoint(x: x + ModulePanel.cellSize.width, y: y + layout.cellHeight))
            }
            if contains(column: position.column, row: position.row + 1) {
                path.move(to: CGPoint(x: x, y: y + layout.cellHeight))
                path.addLine(to: CGPoint(x: x + ModulePanel.cellSize.width, y: y + layout.cellHeight))
            }
        }
        return path
    }

    private func contains(column: Int, row: Int) -> Bool {
        layout.cells.contains { $0.position.column == column && $0.position.row == row }
    }
}

private struct ModuleCellView: View {
    let kind: MetricKind
    let height: CGFloat
    @ObservedObject var monitor: SystemMonitor

    private var value: Double? { monitor.value(for: kind) }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(kind.accent)

                Text(kind.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Text(formattedValue)
                    .font(.system(size: 12, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(value == nil ? Color.secondary : kind.accent)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.2))
                    Capsule()
                        .fill(kind.accent)
                        .frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: ModulePanel.cellSize.width, height: height)
    }

    private var formattedValue: String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))%"
    }

    private var fraction: CGFloat {
        CGFloat(min(100, max(0, value ?? 0)) / 100)
    }
}
