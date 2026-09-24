import AppKit
import SwiftUI
import QuartzCore

final class ModulePanel: NSPanel {
    // Matches potatoken hub exactly: 2 cells = its 320pt large width,
    // 3 stacked cells = its 207pt large height.
    static let cellSize = NSSize(width: 160, height: 69)
    static let singlePanelHeight: CGFloat = 78

    /// Transparent room for the shape-following shadow. The 0pt experiment
    /// clipped the blur to the window's square bounds, exposing its corners.
    /// This margin lets the shorter, subtler shadow fade out naturally.
    ///
    /// Every place in this file and in AppDelegate that used to treat `frame`
    /// as the visible card's bounds now goes through `visibleFrame` /
    /// `setVisibleFrame` instead, so the margin is invisible to layout math:
    /// docking gaps, merge unions, and cell hit-testing all keep working in
    /// visible-card coordinates.
    static let shadowMargin: CGFloat = 18

    /// The visible card's bounds, in screen coordinates — `frame` inset by
    /// the transparent shadow margin on every edge.
    var visibleFrame: NSRect { frame.insetBy(dx: Self.shadowMargin, dy: Self.shadowMargin) }

    /// Window size for a given visible card size.
    static func windowSize(forVisible visibleSize: NSSize) -> NSSize {
        NSSize(width: visibleSize.width + 2 * shadowMargin, height: visibleSize.height + 2 * shadowMargin)
    }

    /// Sets the window's frame from the desired *visible* card rect, doing the
    /// margin conversion in one place rather than at each call site.
    func setVisibleFrame(_ visibleRect: NSRect, display: Bool, animate: Bool = false) {
        let windowFrame = visibleRect.insetBy(dx: -Self.shadowMargin, dy: -Self.shadowMargin)
        if animate {
            animator().setFrame(windowFrame, display: display)
        } else {
            setFrame(windowFrame, display: display)
        }
    }

    /// Moves the window so the visible card's origin lands at `point`, without
    /// changing size.
    func setVisibleOrigin(_ point: NSPoint, animate: Bool = false) {
        let windowOrigin = NSPoint(x: point.x - Self.shadowMargin, y: point.y - Self.shadowMargin)
        if animate {
            animator().setFrameOrigin(windowOrigin)
        } else {
            setFrameOrigin(windowOrigin)
        }
    }

    private(set) var layout: ModuleLayout
    var kinds: [MetricKind] { layout.kinds }
    var axis: ModuleAxis { layout.primaryAxis }
    private let monitor: SystemMonitor
    /// Keep one hosting controller for the lifetime of the panel. Replacing
    /// the controller during an orientation spring lets AppKit renegotiate the
    /// borderless window frame on a later run-loop pass, producing the stray
    /// diagonal frame seen between the requested spring frames.
    private var hostingController: NSHostingController<AnyView>?
    private var liftedKind: MetricKind?
    private var downScreenPoint: NSPoint?
    private var downFrame: NSRect?
    private var pendingKind: MetricKind?
    private var longPressWork: DispatchWorkItem?
    private var isDraggingPanel = false
    private var isExtracting = false
    /// A click that activates a non-key panel can be replayed by AppKit with
    /// the same event number. Handle it once so a replay cannot cancel a
    /// freshly-started double-click orientation animation.
    private var lastHandledMouseDownEventNumber: Int?

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
            contentRect: NSRect(origin: .zero, size: Self.windowSize(forVisible: layout.size)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        // AppKit's own window shadow is cast from the window's rectangular
        // alpha mask, not the SwiftUI content's rounded shape (ModuleSurfaceShape)
        // — against a busy/textured wallpaper that mismatch reads as a hard dark
        // ring right at the rounded corners, exactly as in potatoken hub. A soft
        // shadow drawn in SwiftUI (see ModuleGroupView) follows the actual shape
        // instead.
        hasShadow = false
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
            contentRect: NSRect(origin: .zero, size: Self.windowSize(forVisible: layout.size)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        // AppKit's own window shadow is cast from the window's rectangular
        // alpha mask, not the SwiftUI content's rounded shape (ModuleSurfaceShape)
        // — against a busy/textured wallpaper that mismatch reads as a hard dark
        // ring right at the rounded corners, exactly as in potatoken hub. A soft
        // shadow drawn in SwiftUI (see ModuleGroupView) follows the actual shape
        // instead.
        hasShadow = false
        level = .floating
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .utilityWindow
        rebuildContent()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// AppKit's default implementation fits the frame to whichever screen the
    /// window is landing on, and resizes/repositions it to do so. Crossing
    /// into a display with a different backing scale mid-drag made it inject
    /// this adjustment inline — the window would teleport to a wrong frame
    /// for one tick, then our own delta-based tracking would snap it back on
    /// the next mouse-move — reading as a stutter right at the display
    /// boundary. Dragging here is entirely our own pointer tracking (see
    /// continuePointerTracking), never native window dragging, so there's no
    /// reason to let AppKit's screen-fitting run at all.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    /// The frame-teleport above is gone, but crossing into a screen with a
    /// different backing scale still visibly hitches: the SwiftUI-hosted
    /// content view has to re-rasterize itself at the new pixel density the
    /// instant `backingScaleFactor` changes, and that redraw is the stutter.
    /// Pinning this to a constant means it never changes as the panel moves
    /// between displays, so that redraw never happens mid-drag — the tradeoff
    /// is that on a non-Retina display the panel renders supersampled rather
    /// than at native resolution, which costs a little GPU time but never
    /// looks worse than native.
    override var backingScaleFactor: CGFloat { 2 }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
    }

    override func setFrameOrigin(_ point: NSPoint) {
        super.setFrameOrigin(point)
    }

    func contains(_ kind: MetricKind) -> Bool {
        kinds.contains(kind)
    }

    func update(kinds: [MetricKind], axis: ModuleAxis, resizeToFit: Bool = true) {
        update(layout: ModuleLayout(kinds: kinds, axis: axis), resizeToFit: resizeToFit)
    }

    func update(layout: ModuleLayout, resizeToFit: Bool = true) {
        // Preserve the current frame when the caller owns sizing. The existing
        // hosting controller only receives a new root view below; it is never
        // replaced during a transition.
        let preservedFrame = frame
        self.layout = layout
        rebuildContent(resizeToFit: resizeToFit)
        if !resizeToFit {
            setFrame(preservedFrame, display: true)
        }
    }

    func setLiftedKind(_ kind: MetricKind?) {
        let preservedFrame = frame
        liftedKind = kind
        rebuildContent(resizeToFit: false)
        // Keep the visible group fixed while only the selected cell's opacity
        // changes.
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
        let visible = visibleFrame
        return NSRect(
            x: visible.minX + CGFloat(position.column) * Self.cellSize.width,
            y: visible.maxY - CGFloat(position.row + 1) * layout.cellHeight,
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
            guard event.eventNumber != lastHandledMouseDownEventNumber else { return }
            lastHandledMouseDownEventNumber = event.eventNumber
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
            let target = NSPoint(x: startFrame.minX + dx, y: startFrame.minY + dy)
            setFrameOrigin(target)
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
        let margin = Self.shadowMargin
        let localX = point.x - margin
        let localY = point.y - margin
        let visibleHeight = frame.height - 2 * margin
        guard localX >= 0, localX < frame.width - 2 * margin,
              localY >= 0, localY < visibleHeight else { return nil }
        let column = Int(localX / Self.cellSize.width)
        let row = Int((visibleHeight - localY) / layout.cellHeight)
        return layout.cells.first {
            $0.position.column == column && $0.position.row == row
        }?.kind
    }

    private func rebuildContent(resizeToFit: Bool = true) {
        let rootView = AnyView(
            ModuleGroupView(
                layout: layout,
                liftedKind: liftedKind,
                monitor: monitor
            )
            // The borderless panel already maps content directly to its frame.
            .ignoresSafeArea()
            // Leaves room around the visible card for its shadow (see
            // ModuleGroupView) to render into, instead of being clipped flush
            // with the card's own edge.
            .padding(Self.shadowMargin)
        )
        if let hostingController {
            hostingController.rootView = rootView
        } else {
            let hosting = NSHostingController(rootView: rootView)
            hosting.sizingOptions = []
            hostingController = hosting
            contentViewController = hosting
        }
        contentView?.wantsLayer = true
        if resizeToFit {
            // A transparent titled window adds a titlebar-sized amount when
            // `setContentSize` is used. The module surface is drawn against
            // the full frame (like potatoken hub), so size that frame itself
            // to the layout and preserve its visible top edge.
            // The margin is constant across resizes, so anchoring on the
            // window's own top edge (as before) keeps the visible card's top
            // edge fixed too.
            let current = frame
            let windowSize = Self.windowSize(forVisible: layout.size)
            setFrame(
                NSRect(
                    x: current.minX,
                    y: current.maxY - windowSize.height,
                    width: windowSize.width,
                    height: windowSize.height
                ),
                display: true
            )
        }
    }
}
