import AppKit
import QuartzCore

/// Drag-to-merge docking and long-press extraction.
extension PanelCoordinator {
    typealias MergeSide = MergeDirection

    struct SnapCandidate {
        let score: CGFloat
        let origin: NSPoint
        let other: ModulePanel
        let side: MergeSide
        let targetKind: MetricKind?
    }

    struct ExtractionSession {
        let source: ModulePanel
        let kind: MetricKind
        let ghost: ModulePanel
        let initialGhostFrame: NSRect
        let initialPointer: NSPoint
    }

    func windowDidMove(_ notification: Notification) {
        guard let moving = notification.object as? ModulePanel else { return }
        guard !isApplyingSnap,
              !moving.isHandlingPointerInteraction else { return }

        let id = ObjectIdentifier(moving)
        pendingSnaps[id]?.cancel()
        let work = DispatchWorkItem { [weak self, weak moving] in
            guard let self, let moving else { return }
            self.pendingSnaps[id] = nil
            self.snap(moving)
            if !self.isApplyingSnap { self.saveLayout() }
        }
        pendingSnaps[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    @discardableResult
    func snap(_ moving: ModulePanel) -> Bool {
        guard !isApplyingSnap else { return false }
        let others = panels.filter { $0 !== moving && $0.isVisible }
        var best: SnapCandidate?

        for other in others {
            let movingFrame = moving.visibleFrame
            let otherFrame = other.visibleFrame
            let overlap = movingFrame.intersection(otherFrame)
            let preferredAxis = mergeAxis(for: movingFrame, relativeTo: otherFrame)
            let targetKind = other.closestKind(to: NSPoint(x: movingFrame.midX, y: movingFrame.midY))

            // A clear overlap is enough to join. The resulting combined panel
            // still snaps to a clean row or column, so users don't need to
            // align window edges precisely before releasing the drag.
            if !overlap.isNull,
               overlap.width >= minimumMergeOverlap.width,
               overlap.height >= minimumMergeOverlap.height {
                let (side, origin) = mergePlacement(
                    axis: preferredAxis,
                    moving: movingFrame,
                    other: otherFrame
                )
                let overlapArea = overlap.width * overlap.height
                consider(
                    SnapCandidate(
                        score: -overlapArea,
                        origin: origin,
                        other: other,
                        side: side,
                        targetKind: targetKind
                    ),
                    asBest: &best
                )
            }

            let horizontal: [(MergeSide, CGFloat, CGFloat)] = [
                (.left, otherFrame.minX - movingFrame.width, abs(movingFrame.midY - otherFrame.midY)),
                (.right, otherFrame.maxX, abs(movingFrame.midY - otherFrame.midY)),
            ]
            for (side, x, crossDistance) in horizontal
                where preferredAxis == .horizontal && crossDistance <= horizontalLaneTolerance {
                let edgeDistance = abs(movingFrame.minX - x)
                guard edgeDistance <= snapDistance else { continue }
                consider(
                    SnapCandidate(
                        score: edgeDistance + crossDistance * 0.2,
                        origin: NSPoint(x: x, y: otherFrame.minY),
                        other: other,
                        side: side,
                        targetKind: targetKind
                    ),
                    asBest: &best
                )
            }

            let vertical: [(MergeSide, CGFloat, CGFloat)] = [
                (.below, otherFrame.minY - movingFrame.height, abs(movingFrame.midX - otherFrame.midX)),
                (.above, otherFrame.maxY, abs(movingFrame.midX - otherFrame.midX)),
            ]
            for (side, y, crossDistance) in vertical
                where preferredAxis == .vertical && crossDistance <= verticalLaneTolerance {
                let edgeDistance = abs(movingFrame.minY - y)
                guard edgeDistance <= snapDistance else { continue }
                consider(
                    SnapCandidate(
                        score: edgeDistance + crossDistance * 0.2,
                        origin: NSPoint(x: otherFrame.minX, y: y),
                        other: other,
                        side: side,
                        targetKind: targetKind
                    ),
                    asBest: &best
                )
            }
        }

        guard let best else { return false }
        animateMerge(moving, with: best)
        return true
    }

    func consider(_ candidate: SnapCandidate, asBest best: inout SnapCandidate?) {
        if best == nil || candidate.score < best!.score {
            best = candidate
        }
    }

    /// Compare movement in each axis as a fraction of that axis's window size.
    /// A module moved below another therefore selects a vertical stack even
    /// though the cells are much wider than they are tall.
    func mergeAxis(for moving: NSRect, relativeTo other: NSRect) -> ModuleAxis {
        let horizontalDistance = abs(moving.midX - other.midX) / max(moving.width, other.width, 1)
        let verticalDistance = abs(moving.midY - other.midY) / max(moving.height, other.height, 1)
        return horizontalDistance >= verticalDistance ? .horizontal : .vertical
    }

    func mergePlacement(
        axis: ModuleAxis,
        moving: NSRect,
        other: NSRect
    ) -> (MergeSide, NSPoint) {
        switch axis {
        case .horizontal:
            if moving.midX < other.midX {
                return (.left, NSPoint(x: other.minX - moving.width, y: other.minY))
            }
            return (.right, NSPoint(x: other.maxX, y: other.minY))
        case .vertical:
            if moving.midY < other.midY {
                return (.below, NSPoint(x: other.minX, y: other.minY - moving.height))
            }
            return (.above, NSPoint(x: other.minX, y: other.maxY))
        }
    }

    func animateMerge(_ moving: ModulePanel, with candidate: SnapCandidate) {
        isApplyingSnap = true
        // candidate.origin describes where the visible card should land;
        // moving.frame.origin is the real (padded) window origin, so convert
        // before driving the window animation.
        let targetOrigin = NSPoint(
            x: candidate.origin.x - ModulePanel.shadowMargin,
            y: candidate.origin.y - ModulePanel.shadowMargin
        )
        let start = moving.frame.origin
        let dx = targetOrigin.x - start.x
        let dy = targetOrigin.y - start.y
        let distance = max(1, hypot(dx, dy))
        let overshoot = NSPoint(
            x: targetOrigin.x + dx / distance * 3,
            y: targetOrigin.y + dy / distance * 3
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.82, 0.18, 1)
            moving.animator().setFrameOrigin(overshoot)
        } completionHandler: { [weak self, weak moving] in
            guard let self, let moving else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.10
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                moving.animator().setFrameOrigin(targetOrigin)
            } completionHandler: { [weak self, weak moving] in
                Task { @MainActor in
                    guard let self, let moving else { return }
                    self.merge(
                        moving,
                        with: candidate.other,
                        side: candidate.side,
                        targetKind: candidate.targetKind
                    )
                }
            }
        }
    }

    func merge(
        _ moving: ModulePanel,
        with other: ModulePanel,
        side: MergeSide,
        targetKind: MetricKind?
    ) {
        guard panels.contains(where: { $0 === moving }),
              panels.contains(where: { $0 === other }) else {
            isApplyingSnap = false
            return
        }

        let layout = ModuleLayout.merged(
            moving: moving.layout,
            other: other.layout,
            side: side,
            target: targetKind
        )
        // Never create a group from cells that only meet at a corner or have
        // an empty gap between them. They remain independent panels instead.
        guard layout.isEdgeConnected else {
            isApplyingSnap = false
            return
        }
        let size = layout.size
        let joined = moving.visibleFrame.union(other.visibleFrame)
        let finalVisibleFrame = NSRect(
            x: joined.midX - size.width / 2,
            y: joined.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        let finalFrame = finalVisibleFrame.insetBy(dx: -ModulePanel.shadowMargin, dy: -ModulePanel.shadowMargin)

        removePanel(moving)
        removePanel(other)

        let group = makePanel(layout: layout, origin: finalFrame.origin)
        let bulged = finalFrame.insetBy(dx: -4, dy: 2)
        let squeezed = finalFrame.insetBy(dx: 2, dy: -2)
        group.setFrame(bulged, display: true)
        group.alphaValue = 0.86
        group.orderFrontRegardless()
        group.animatePudding(axis: layout.primaryAxis)

        // The shared surface briefly spreads, rebounds in the perpendicular
        // direction, then settles. Because the old windows have already been
        // replaced, no internal seam can flash during this pudding motion.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.13
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
            group.animator().setFrame(squeezed, display: true)
            group.animator().alphaValue = 1
        } completionHandler: { [weak self, weak group] in
            guard let self, let group else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.15, 0.9, 0.25, 1)
                group.animator().setFrame(finalFrame, display: true)
            } completionHandler: { [weak self] in
                Task { @MainActor in
                    self?.isApplyingSnap = false
                    self?.saveLayout()
                }
            }
        }
    }

    func beginExtraction(
        from source: ModulePanel,
        kind: MetricKind,
        cellFrame: NSRect,
        pointer: NSPoint
    ) {
        guard extractionSession == nil, source.kinds.count > 1 else { return }
        pendingSnaps[ObjectIdentifier(source)]?.cancel()
        pendingSnaps[ObjectIdentifier(source)] = nil

        // cellFrame is a visible-card rect; the ghost is a real ModulePanel
        // whose window is always padded for its shadow, so pad this out too —
        // otherwise the ghost's visible card wouldn't match a normal panel's.
        let ghostWindowFrame = cellFrame.insetBy(dx: -ModulePanel.shadowMargin, dy: -ModulePanel.shadowMargin)
        let ghost = ModulePanel(kinds: [kind], monitor: monitor)
        ghost.setFrame(ghostWindowFrame, display: true)
        ghost.level = .popUpMenu
        ghost.ignoresMouseEvents = true
        ghost.alphaValue = 0.68
        ghost.orderFrontRegardless()
        ghost.animatePudding(axis: source.axis, intensity: 0.75)
        source.animatePudding(axis: source.axis, intensity: 0.55)

        extractionSession = ExtractionSession(
            source: source,
            kind: kind,
            ghost: ghost,
            initialGhostFrame: ghostWindowFrame,
            initialPointer: pointer
        )
    }

    func changeExtraction(from source: ModulePanel, pointer: NSPoint) {
        guard let session = extractionSession, session.source === source else { return }
        session.ghost.setFrameOrigin(NSPoint(
            x: session.initialGhostFrame.minX + pointer.x - session.initialPointer.x,
            y: session.initialGhostFrame.minY + pointer.y - session.initialPointer.y
        ))
    }

    func endExtraction(from source: ModulePanel, pointer: NSPoint) {
        guard let session = extractionSession, session.source === source else { return }
        extractionSession = nil
        let travel = hypot(
            pointer.x - session.initialPointer.x,
            pointer.y - session.initialPointer.y
        )

        guard travel >= 28 else {
            cancelExtraction(session)
            return
        }
        completeExtraction(session)
    }

    func cancelExtraction(_ session: ExtractionSession) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.82, 0.2, 1)
            session.ghost.animator().setFrame(session.initialGhostFrame, display: true)
            session.ghost.animator().alphaValue = 0.2
        } completionHandler: {
            Task { @MainActor in
                session.ghost.orderOut(nil)
                session.source.setLiftedKind(nil)
                session.source.animatePudding(axis: session.source.axis, intensity: 0.45)
            }
        }
    }

    func completeExtraction(_ session: ExtractionSession) {
        let source = session.source
        let sourceFrameBeforeExtraction = source.frame
        let remainingLayout = source.layout.removing(session.kind)
        guard !remainingLayout.cells.isEmpty else {
            session.ghost.orderOut(nil)
            source.setLiftedKind(nil)
            return
        }

        isApplyingSnap = true
        source.setLiftedKind(nil)
        let newSize = ModulePanel.windowSize(forVisible: remainingLayout.size)
        // Keep the group's original anchor fixed. Removing a middle or leading
        // cell only contracts the surface; it must not jump toward another cell.
        let sourceFrame = NSRect(origin: sourceFrameBeforeExtraction.origin, size: newSize)
        source.update(layout: remainingLayout, resizeToFit: false)

        let detachedFrame = session.ghost.frame
        session.ghost.orderOut(nil)
        let detached = makePanel(kinds: [session.kind], origin: detachedFrame.origin)
        detached.alphaValue = 0.68
        detached.orderFrontRegardless()
        detached.animatePudding(axis: source.axis, intensity: 0.8)
        source.animatePudding(axis: source.axis, intensity: 0.7)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.82, 0.2, 1)
            source.animator().setFrame(sourceFrame, display: true)
            detached.animator().alphaValue = 1
        } completionHandler: { [weak self, weak source] in
            Task { @MainActor in
                guard let self else { return }
                source?.setFrame(sourceFrame, display: true)
                // A long-press extraction creates a new panel instead of
                // going through ModulePanel's normal drag-end callback. Run
                // the same docking decision now that both the remaining group
                // and detached card have their final frames, so dropping onto
                // another card merges immediately rather than leaving a card
                // floating above it.
                self.isApplyingSnap = false
                if !self.snap(detached) {
                    self.saveLayout()
                }
            }
        }
    }
}
