import Foundation

/// Decides where a just-moved card should dock. Pure geometry: it knows
/// nothing about windows. All rects are *visible-card* rects in screen
/// coordinates (no shadow margin).
enum SnapEngine {
    static let snapDistance: CGFloat = 28
    static let minimumMergeOverlap = CGSize(width: 30, height: 22)
    static let horizontalLaneTolerance: CGFloat = 32
    static let verticalLaneTolerance: CGFloat = 64

    struct Cell {
        let kind: MetricKind
        let frame: CGRect
    }

    /// A card (single or grouped) the moved card could dock to. `cells` are
    /// in the card's own kind order.
    struct Target {
        let frame: CGRect
        let cells: [Cell]
    }

    struct Decision: Equatable {
        /// Index into the `targets` passed to `decide`.
        let targetIndex: Int
        let side: MergeDirection
        /// Where the moved card's visible origin should land.
        let origin: CGPoint
        /// The target's cell nearest the moved card's centre.
        let targetKind: MetricKind?
    }

    private struct Candidate {
        let score: CGFloat
        let decision: Decision
    }

    /// `movingIsSingleCard`: the moved thing is one card (not a group). Only
    /// then the empty-slot rule below applies.
    static func decide(moving: CGRect, movingIsSingleCard: Bool = false, targets: [Target]) -> Decision? {
        // A single card dropped into the empty slot of an L-shaped group fills
        // that slot, whatever the edge-distance rules would say.
        if movingIsSingleCard {
            for (index, target) in targets.enumerated() {
                if let decision = emptySlotDecision(moving: moving, index: index, target: target) {
                    return decision
                }
            }
        }

        var best: Candidate?

        func consider(_ candidate: Candidate) {
            if best == nil || candidate.score < best!.score {
                best = candidate
            }
        }

        for (index, target) in targets.enumerated() {
            let otherFrame = target.frame
            let overlap = moving.intersection(otherFrame)
            let preferredAxis = mergeAxis(for: moving, relativeTo: otherFrame)
            let targetKind = closestKind(in: target.cells, to: CGPoint(x: moving.midX, y: moving.midY))

            // A clear overlap is enough to join. The resulting combined panel
            // still snaps to a clean row or column, so users don't need to
            // align window edges precisely before releasing the drag.
            if !overlap.isNull,
               overlap.width >= minimumMergeOverlap.width,
               overlap.height >= minimumMergeOverlap.height {
                let (side, origin) = mergePlacement(axis: preferredAxis, moving: moving, other: otherFrame)
                let overlapArea = overlap.width * overlap.height
                consider(Candidate(
                    score: -overlapArea,
                    decision: Decision(targetIndex: index, side: side, origin: origin, targetKind: targetKind)
                ))
            }

            let horizontal: [(MergeDirection, CGFloat, CGFloat)] = [
                (.left, otherFrame.minX - moving.width, abs(moving.midY - otherFrame.midY)),
                (.right, otherFrame.maxX, abs(moving.midY - otherFrame.midY)),
            ]
            for (side, x, crossDistance) in horizontal
                where preferredAxis == .horizontal && crossDistance <= horizontalLaneTolerance {
                let edgeDistance = abs(moving.minX - x)
                guard edgeDistance <= snapDistance else { continue }
                consider(Candidate(
                    score: edgeDistance + crossDistance * 0.2,
                    decision: Decision(targetIndex: index, side: side,
                                       origin: CGPoint(x: x, y: otherFrame.minY), targetKind: targetKind)
                ))
            }

            let vertical: [(MergeDirection, CGFloat, CGFloat)] = [
                (.below, otherFrame.minY - moving.height, abs(moving.midX - otherFrame.midX)),
                (.above, otherFrame.maxY, abs(moving.midX - otherFrame.midX)),
            ]
            for (side, y, crossDistance) in vertical
                where preferredAxis == .vertical && crossDistance <= verticalLaneTolerance {
                let edgeDistance = abs(moving.minY - y)
                guard edgeDistance <= snapDistance else { continue }
                consider(Candidate(
                    score: edgeDistance + crossDistance * 0.2,
                    decision: Decision(targetIndex: index, side: side,
                                       origin: CGPoint(x: otherFrame.minX, y: y), targetKind: targetKind)
                ))
            }
        }

        return best?.decision
    }

    private static func emptySlotDecision(moving: CGRect, index: Int, target: Target) -> Decision? {
        let center = CGPoint(x: moving.midX, y: moving.midY)
        guard target.frame.contains(center),
              !target.cells.contains(where: { $0.frame.contains(center) }) else { return nil }

        func overlapsAnyCell(_ rect: CGRect) -> Bool {
            target.cells.contains {
                let overlap = rect.intersection($0.frame)
                return !overlap.isNull && overlap.width > 0.5 && overlap.height > 0.5
            }
        }

        var best: (distance: CGFloat, decision: Decision)?
        for cell in target.cells {
            let f = cell.frame
            let neighbours: [(MergeDirection, CGRect)] = [
                (.left, f.offsetBy(dx: -f.width, dy: 0)),
                (.right, f.offsetBy(dx: f.width, dy: 0)),
                (.above, f.offsetBy(dx: 0, dy: f.height)),
                (.below, f.offsetBy(dx: 0, dy: -f.height)),
            ]
            for (side, rect) in neighbours where rect.contains(center) && !overlapsAnyCell(rect) {
                let distance = hypot(f.midX - center.x, f.midY - center.y)
                if best == nil || distance < best!.distance {
                    best = (distance, Decision(targetIndex: index, side: side, origin: rect.origin, targetKind: cell.kind))
                }
            }
        }
        return best?.decision
    }

    /// Compare movement in each axis as a fraction of that axis's window size.
    /// A module moved below another therefore selects a vertical stack even
    /// though the cells are much wider than they are tall.
    static func mergeAxis(for moving: CGRect, relativeTo other: CGRect) -> ModuleAxis {
        let horizontalDistance = abs(moving.midX - other.midX) / max(moving.width, other.width, 1)
        let verticalDistance = abs(moving.midY - other.midY) / max(moving.height, other.height, 1)
        return horizontalDistance >= verticalDistance ? .horizontal : .vertical
    }

    static func mergePlacement(axis: ModuleAxis, moving: CGRect, other: CGRect) -> (MergeDirection, CGPoint) {
        switch axis {
        case .horizontal:
            if moving.midX < other.midX {
                return (.left, CGPoint(x: other.minX - moving.width, y: other.minY))
            }
            return (.right, CGPoint(x: other.maxX, y: other.minY))
        case .vertical:
            if moving.midY < other.midY {
                return (.below, CGPoint(x: other.minX, y: other.minY - moving.height))
            }
            return (.above, CGPoint(x: other.minX, y: other.maxY))
        }
    }

    private static func closestKind(in cells: [Cell], to point: CGPoint) -> MetricKind? {
        cells.min {
            hypot($0.frame.midX - point.x, $0.frame.midY - point.y)
                < hypot($1.frame.midX - point.x, $1.frame.midY - point.y)
        }?.kind
    }
}
