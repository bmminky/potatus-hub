import AppKit
import SwiftUI
import QuartzCore

final class ModulePanel: NSPanel {
    // Matches potatoken hub exactly: 2 cells = its 320pt large width,
    // 3 stacked cells = its 207pt large height.
    static let cellSize = NSSize(width: 160, height: 69)
    static let singlePanelHeight: CGFloat = 78

    private(set) var layout: ModuleLayout
    var kinds: [MetricKind] { layout.kinds }
    var axis: ModuleAxis { layout.primaryAxis }
    private let monitor: SystemMonitor
    private var liftedKind: MetricKind?
    private var downScreenPoint: NSPoint?
    private var downFrame: NSRect?
    private var pendingKind: MetricKind?
    private var longPressWork: DispatchWorkItem?
    private var isDraggingPanel = false
    private var isExtracting = false

    var onContextMenu: ((ModulePanel, NSEvent) -> Void)?
    var onDoubleClick: ((ModulePanel) -> Void)?
    var onInteractionStart: ((ModulePanel) -> Void)?
    var onExtractionBegan: ((ModulePanel, MetricKind, NSRect, NSPoint) -> Void)?
    var onExtractionChanged: ((ModulePanel, NSPoint) -> Void)?
    var onExtractionEnded: ((ModulePanel, NSPoint) -> Void)?
    var onPanelDragEnded: ((ModulePanel) -> Void)?

    /// AppKit's background dragging must never run alongside a long press.
    /// Otherwise the original group follows the extracted cell for one frame.
    var isHandlingPointerInteraction: Bool {
        downScreenPoint != nil || isDraggingPanel || isExtracting
    }

    init(kinds: [MetricKind], axis: ModuleAxis = .horizontal, monitor: SystemMonitor) {
        self.layout = ModuleLayout(kinds: kinds, axis: axis)
        self.monitor = monitor
        super.init(
            contentRect: NSRect(origin: .zero, size: layout.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        // Window movement is driven below, from the same pointer state machine
        // that owns long-press extraction. This prevents two drag owners.
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .utilityWindow
        rebuildContent()
    }

    init(layout: ModuleLayout, monitor: SystemMonitor) {
        self.layout = layout
        self.monitor = monitor
        super.init(
            contentRect: NSRect(origin: .zero, size: layout.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .utilityWindow
        rebuildContent()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func contains(_ kind: MetricKind) -> Bool {
        kinds.contains(kind)
    }

    func update(kinds: [MetricKind], axis: ModuleAxis, resizeToFit: Bool = true) {
        update(layout: ModuleLayout(kinds: kinds, axis: axis), resizeToFit: resizeToFit)
    }

    func update(layout: ModuleLayout, resizeToFit: Bool = true) {
        self.layout = layout
        rebuildContent(resizeToFit: resizeToFit)
    }

    func setLiftedKind(_ kind: MetricKind?) {
        let preservedFrame = frame
        liftedKind = kind
        rebuildContent(resizeToFit: false)
        // Replacing an NSHostingController can temporarily collapse a borderless
        // panel to 0×0 and shift its origin. Keep the visible group fixed while
        // only the selected cell's opacity changes.
        setFrame(preservedFrame, display: true)
    }

    func cellFrameOnScreen(for kind: MetricKind) -> NSRect? {
        guard let position = layout.position(for: kind) else { return nil }
        // The panel uses a transparent full-size titlebar to match potatoken
        // hub. `convertToScreen` works in the content coordinate space, which
        // has a titlebar-dependent vertical origin; using it here made every
        // detached card acquire the same upward offset. The module grid is
        // already expressed directly inside this window frame, so calculate
        // its screen rect from the frame itself.
        return NSRect(
            x: frame.minX + CGFloat(position.column) * Self.cellSize.width,
            y: frame.maxY - CGFloat(position.row + 1) * layout.cellHeight,
            width: Self.cellSize.width,
            height: layout.cellHeight
        )
    }

    func closestKind(to screenPoint: NSPoint) -> MetricKind? {
        kinds.min { lhs, rhs in
            let lhsDistance = cellFrameOnScreen(for: lhs).map {
                hypot($0.midX - screenPoint.x, $0.midY - screenPoint.y)
            } ?? .greatestFiniteMagnitude
            let rhsDistance = cellFrameOnScreen(for: rhs).map {
                hypot($0.midX - screenPoint.x, $0.midY - screenPoint.y)
            } ?? .greatestFiniteMagnitude
            return lhsDistance < rhsDistance
        }
    }

    func animatePudding(axis: ModuleAxis, intensity: CGFloat = 1) {
        guard let layer = contentView?.layer else { return }
        layer.removeAnimation(forKey: "potatus.pudding.x")
        layer.removeAnimation(forKey: "potatus.pudding.y")

        let spread = 1 + 0.032 * intensity
        let squeeze = 1 - 0.024 * intensity
        let xValues: [NSNumber]
        let yValues: [NSNumber]
        let spreadValue = NSNumber(value: Double(spread))
        let squeezeValue = NSNumber(value: Double(squeeze))
        if axis == .horizontal {
            xValues = [1, spreadValue, 0.988, 1]
            yValues = [1, squeezeValue, 1.014, 1]
        } else {
            xValues = [1, squeezeValue, 1.014, 1]
            yValues = [1, spreadValue, 0.988, 1]
        }

        let x = CAKeyframeAnimation(keyPath: "transform.scale.x")
        x.values = xValues
        x.keyTimes = [0, 0.28, 0.62, 1]
        x.duration = 0.38
        x.timingFunctions = puddingTimingFunctions

        let y = CAKeyframeAnimation(keyPath: "transform.scale.y")
        y.values = yValues
        y.keyTimes = x.keyTimes
        y.duration = x.duration
        y.timingFunctions = puddingTimingFunctions

        layer.add(x, forKey: "potatus.pudding.x")
        layer.add(y, forKey: "potatus.pudding.y")
    }

    /// Matches the compact centered ease-in-out feel used by potatoken hub
    /// without changing the saved frame or disturbing attached modules.
    func animatePresentation(show: Bool, completion: @escaping () -> Void) {
        guard let layer = contentView?.layer else {
            if show { orderFrontRegardless() } else { orderOut(nil) }
            completion()
            return
        }

        let duration: TimeInterval = 0.26
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = show ? 0.92 : 1
        scale.toValue = show ? 1 : 0.94
        scale.duration = duration
        scale.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(scale, forKey: "potatus.presentation.scale")

        if show {
            alphaValue = 0
            orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().alphaValue = show ? 1 : 0
        } completionHandler: { [weak self] in
            if !show {
                self?.orderOut(nil)
                self?.alphaValue = 1
            }
            completion()
        }
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .rightMouseDown:
            onContextMenu?(self, event)

        case .leftMouseDown:
            beginPointerTracking(event)

        case .leftMouseDragged where downScreenPoint != nil:
            continuePointerTracking()

        case .leftMouseUp where downScreenPoint != nil:
            endPointerTracking()

        default:
            super.sendEvent(event)
        }
    }

    static func size(for count: Int, axis: ModuleAxis) -> NSSize {
        ModuleLayout(kinds: Array(MetricKind.allCases.prefix(count)), axis: axis).size
    }

    private var puddingTimingFunctions: [CAMediaTimingFunction] {
        [
            CAMediaTimingFunction(controlPoints: 0.18, 0.82, 0.2, 1),
            CAMediaTimingFunction(controlPoints: 0.25, 0.72, 0.28, 1),
            CAMediaTimingFunction(name: .easeOut),
        ]
    }

    private func beginPointerTracking(_ event: NSEvent) {
        // Match potatoken hub's resize interaction: a fresh pointer-down
        // settles any running spring before this click starts new work.
        onInteractionStart?(self)

        if event.clickCount == 2, kinds.count > 1 {
            onDoubleClick?(self)
            return
        }

        let point = NSEvent.mouseLocation
        guard let kind = kind(at: event.locationInWindow) else {
            super.sendEvent(event)
            return
        }

        downScreenPoint = point
        downFrame = frame
        pendingKind = kind
        isDraggingPanel = false
        isExtracting = false

        guard kinds.count > 1 else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  let kind = self.pendingKind,
                  let start = self.downScreenPoint,
                  let cellFrame = self.cellFrameOnScreen(for: kind),
                  hypot(NSEvent.mouseLocation.x - start.x, NSEvent.mouseLocation.y - start.y) < 5 else { return }
            self.isExtracting = true
            self.setLiftedKind(kind)
            self.onExtractionBegan?(self, kind, cellFrame, start)
        }
        longPressWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42, execute: work)
    }

    private func continuePointerTracking() {
        guard let start = downScreenPoint, let startFrame = downFrame else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - start.x
        let dy = current.y - start.y

        if isExtracting {
            onExtractionChanged?(self, current)
            return
        }

        if hypot(dx, dy) >= 5 {
            longPressWork?.cancel()
            pendingKind = nil
            isDraggingPanel = true
            setFrameOrigin(NSPoint(x: startFrame.minX + dx, y: startFrame.minY + dy))
        }
    }

    private func endPointerTracking() {
        longPressWork?.cancel()
        let current = NSEvent.mouseLocation
        if isExtracting {
            onExtractionEnded?(self, current)
        } else if isDraggingPanel {
            onPanelDragEnded?(self)
        }
        resetPointerTracking()
    }

    private func resetPointerTracking() {
        longPressWork = nil
        downScreenPoint = nil
        downFrame = nil
        pendingKind = nil
        isDraggingPanel = false
        isExtracting = false
    }

    private func kind(at point: NSPoint) -> MetricKind? {
        let column = Int(point.x / Self.cellSize.width)
        let row = Int((frame.height - point.y) / layout.cellHeight)
        return layout.cells.first {
            $0.position.column == column && $0.position.row == row
        }?.kind
    }

    private func rebuildContent(resizeToFit: Bool = true) {
        let hosting = NSHostingController(
            rootView: ModuleGroupView(
                layout: layout,
                liftedKind: liftedKind,
                monitor: monitor
            )
            // The borderless panel already maps content directly to its frame.
            .ignoresSafeArea()
        )
        hosting.sizingOptions = []
        contentViewController = hosting
        contentView?.wantsLayer = true
        if resizeToFit {
            // A transparent titled window adds a titlebar-sized amount when
            // `setContentSize` is used. The module surface is drawn against
            // the full frame (like potatoken hub), so size that frame itself
            // to the layout and preserve its visible top edge.
            let current = frame
            setFrame(
                NSRect(
                    x: current.minX,
                    y: current.maxY - layout.size.height,
                    width: layout.size.width,
                    height: layout.size.height
                ),
                display: true
            )
        }
    }
}
