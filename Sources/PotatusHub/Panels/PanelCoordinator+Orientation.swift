import AppKit
import QuartzCore

/// Orientation toggle (double-click) and the detach spring animation.
extension PanelCoordinator {
    /// Drive every detached window from one timer. Multiple independent
    /// NSWindow animator transactions can be coalesced by AppKit, which is
    /// what made the previous split look like a series of jumps.
    func animateDetachment(_ panels: [(panel: ModulePanel, startFrame: CGRect, targetFrame: CGRect)]) {
        detachmentAnimation?.invalidate()
        let duration: CFTimeInterval = 0.38
        let startTime = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else {
                    timer.invalidate()
                    return
                }

                let progress = min((CACurrentMediaTime() - startTime) / duration, 1)
                let eased = Self.springEase(progress)
                for item in panels {
                    item.panel.setFrameOrigin(NSPoint(
                        x: item.startFrame.origin.x + (item.targetFrame.origin.x - item.startFrame.origin.x) * eased,
                        y: item.startFrame.origin.y + (item.targetFrame.origin.y - item.startFrame.origin.y) * eased
                    ))
                }

                if progress >= 1 {
                    timer.invalidate()
                    self.detachmentAnimation = nil
                    panels.forEach { $0.panel.setFrameOrigin($0.targetFrame.origin) }
                    self.gate.end()
                    self.saveLayout()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        detachmentAnimation = timer
    }

    /// A grouped card has two deliberate, compact arrangements. L-shaped
    /// groups are also normalized here, so a double-click always has an
    /// unambiguous horizontal or vertical destination.
    func toggleOrientation(of panel: ModulePanel) {
        guard panel.kinds.count > 1 else { return }

        finishOrientationAnimation()

        let targetAxis: ModuleAxis = panel.axis == .horizontal ? .vertical : .horizontal
        let targetLayout = ModuleLayout(kinds: panel.kinds, axis: targetAxis)
        // springOrient animates the real (padded) window frame directly, so
        // this stays the window frame throughout — only the *target*, built
        // below from visible-space quantities, needs converting to match.
        let currentFrame = panel.frame
        let targetSize = targetLayout.size
        guard targetSize != panel.visibleFrame.size else { return }

        // Keep the middle module stationary in both directions. Previously
        // only vertical→horizontal used this anchor; horizontal→vertical then
        // placed the new top cell where the old middle cell was, making the
        // whole stack visibly drop below the cursor's reference point.
        let anchorKind = panel.kinds[panel.kinds.count / 2]
        let sourceAnchor = panel.cellFrameOnScreen(for: anchorKind)
        let targetAnchor = targetLayout.position(for: anchorKind)
        var targetX: CGFloat
        var targetY: CGFloat
        if let sourceAnchor, let targetAnchor {
            targetX = sourceAnchor.midX
                - (CGFloat(targetAnchor.column) + 0.5) * LayoutMetrics.cellSize.width
            targetY = sourceAnchor.midY
                - targetSize.height
                + (CGFloat(targetAnchor.row) + 0.5) * targetLayout.cellHeight
        } else {
            let visibleNow = panel.visibleFrame
            targetX = visibleNow.midX - targetSize.width / 2
            targetY = visibleNow.maxY - targetSize.height
        }
        if let visible = panel.screen?.visibleFrame {
            targetX = min(max(targetX, visible.minX + 4), visible.maxX - targetSize.width - 4)
            targetY = min(max(targetY, visible.minY + 4), visible.maxY - targetSize.height - 4)
        }
        // targetX/Y/Size describe the visible card; pad out to the window
        // frame springOrient and panel.minSize/maxSize actually operate on.
        let targetVisibleFrame = NSRect(x: targetX, y: targetY, width: targetSize.width, height: targetSize.height)
        let targetFrame = targetVisibleFrame.insetBy(dx: -ModulePanel.shadowMargin, dy: -ModulePanel.shadowMargin)
        springOrient(panel, from: currentFrame, to: targetFrame) {
            panel.update(layout: targetLayout, resizeToFit: false)
        }
    }

    /// Uses potatoken hub's exact one-pass 0.5s damped spring. Keeping this
    /// as one timer rather than chaining several AppKit animation contexts is
    /// important: those transactions were coalescing into a late visual jump.
    func springOrient(
        _ panel: ModulePanel,
        from startFrame: NSRect,
        to targetFrame: NSRect,
        installDestination: () -> Void
    ) {
        // Resizing changes the frame origin while its top edge is held fixed.
        // Do not let that programmatic movement enter the drag-snap pipeline:
        // a delayed snap could otherwise interrupt the spring after 0.12s.
        gate.begin()
        let savedMin = panel.minSize
        let savedMax = panel.maxSize
        let slack: CGFloat = 90
        panel.minSize = NSSize(
            width: max(min(startFrame.width, targetFrame.width) - slack, 1),
            height: max(min(startFrame.height, targetFrame.height) - slack, 1)
        )
        panel.maxSize = NSSize(
            width: max(startFrame.width, targetFrame.width) + slack,
            height: max(startFrame.height, targetFrame.height) + slack
        )
        // Replacing the SwiftUI host can otherwise perform one implicit
        // intrinsic-size transaction before the spring owns the frame. Open
        // the limits first, install the destination, then explicitly restore
        // the start frame so the timer is the sole frame owner from frame 1.
        installDestination()
        panel.setFrame(startFrame, display: true)
        pendingOrientation = (panel, targetFrame, savedMin, savedMax)
        orientationGeneration &+= 1
        let generation = orientationGeneration
        func frame(at progress: CGFloat) -> NSRect {
            // A tier change in potatoken grows or shrinks both dimensions in
            // the same direction, so its spring can safely pass 100% on each
            // axis. An orientation change does the opposite: width shrinks
            // while height grows (or vice versa). Letting both axes overshoot
            // produces a one-frame ultra-thin card, which reads as a diagonal
            // wobble instead of a soft settle. Keep potatoken's exact spring
            // progress for the expanding axis, but settle a shrinking axis at
            // its destination before that overshoot begins.
            let widthProgress = targetFrame.width < startFrame.width ? min(progress, 1) : progress
            let heightProgress = targetFrame.height < startFrame.height ? min(progress, 1) : progress
            let width = startFrame.width + (targetFrame.width - startFrame.width) * widthProgress
            let height = startFrame.height + (targetFrame.height - startFrame.height) * heightProgress
            let centerX = startFrame.midX + (targetFrame.midX - startFrame.midX) * widthProgress
            let topY = startFrame.maxY + (targetFrame.maxY - startFrame.maxY) * heightProgress

            return NSRect(
                x: centerX - width / 2,
                y: topY - height,
                width: width,
                height: height
            )
        }

        let duration: CFTimeInterval = 0.5
        let startTime = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self, weak panel] timer in
            MainActor.assumeIsolated {
                guard let self, let panel, self.orientationGeneration == generation else {
                    timer.invalidate()
                    return
                }

                let progress = min((CACurrentMediaTime() - startTime) / duration, 1)
                panel.setFrame(frame(at: Self.springEase(progress)), display: true)

                guard progress >= 1 else { return }
                timer.invalidate()
                self.orientationAnimation = nil
                self.pendingOrientation = nil
                panel.minSize = savedMin
                panel.maxSize = savedMax
                panel.setFrame(targetFrame, display: true)
                self.gate.end()
                self.saveLayout()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        orientationAnimation = timer
    }

    func finishOrientationAnimation() {
        orientationAnimation?.invalidate()
        orientationAnimation = nil
        guard let pending = pendingOrientation else { return }
        orientationGeneration &+= 1
        pendingOrientation = nil
        pending.panel.minSize = pending.minSize
        pending.panel.maxSize = pending.maxSize
        pending.panel.setFrame(pending.targetFrame, display: true)
        gate.end()
        saveLayout()
    }

    static func springEase(_ t: Double) -> CGFloat {
        guard t < 1 else { return 1 }
        return CGFloat(1 - exp(-6 * t) * cos(9 * t))
    }
}
