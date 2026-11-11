import AppKit
import SwiftUI
import QuartzCore

/// Owns every module panel: creating, showing, hiding, arranging, combining,
/// detaching, and saving/restoring their positions. Docking (drag-to-merge,
/// long-press extraction) lives in `+Docking`, orientation springs in
/// `+Orientation`.
@MainActor
final class PanelCoordinator: NSObject, NSWindowDelegate {
    struct SavedGroup: Codable {
        let kinds: [MetricKind]
        let axis: ModuleAxis
        let layout: ModuleLayout?
        let frame: String
    }

    let monitor: SystemMonitor
    var panels: [ModulePanel] = []
    var isApplyingSnap = false
    var pendingSnaps: [ObjectIdentifier: DispatchWorkItem] = [:]
    var extractionSession: ExtractionSession?
    var isAnimatingPresentation = false
    var pendingOrientation: (panel: ModulePanel, targetFrame: NSRect, minSize: NSSize, maxSize: NSSize)?
    var orientationGeneration = 0
    var orientationAnimation: Timer?
    var detachmentAnimation: Timer?

    /// Called whenever a panel's presence may have changed (removed, shown,
    /// hidden) so the owner can start or stop sampling.
    var onPresenceChanged: (() -> Void)?
    /// Right-click on a panel.
    var onContextMenu: ((ModulePanel, NSEvent) -> Void)?
    /// The screen the menu-bar icon is on, used to place and arrange panels.
    var screenProvider: () -> NSScreen? = { nil }

    static let visibilityPrefix = "PotatusHub.visible."
    static let legacyFramePrefix = "PotatusHub.frame."
    static let groupsKey = "PotatusHub.groups.v1"
    static let savedShadowMarginKey = "PotatusHub.savedShadowMargin"
    let snapDistance: CGFloat = 28
    let minimumMergeOverlap = NSSize(width: 30, height: 22)
    let horizontalLaneTolerance: CGFloat = 32
    let verticalLaneTolerance: CGFloat = 64

    init(monitor: SystemMonitor) {
        self.monitor = monitor
        super.init()
    }

    func togglePanelPresentation() {
        setPanelPresentation(show: !panels.contains { $0.isVisible })
    }

    func hidePanels() {
        setPanelPresentation(show: false)
    }

    func setPanelPresentation(show: Bool) {
        guard !isAnimatingPresentation else { return }
        guard !panels.isEmpty else { return }
        finishOrientationAnimation()
        pendingSnaps.values.forEach { $0.cancel() }
        pendingSnaps.removeAll()
        saveLayout()
        isAnimatingPresentation = true
        let group = DispatchGroup()
        for panel in panels {
            group.enter()
            panel.animatePresentation(show: show) {
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            self?.isAnimatingPresentation = false
            self?.onPresenceChanged?()
        }
    }

    func toggleModule(_ kind: MetricKind) {
        if isVisible(kind) {
            hide(kind)
        } else {
            show(kind)
        }
        saveLayout()
    }

    func arrangeModulesHorizontally() {
        let visible = panels.filter(\.isVisible)
        guard let screen = screenProvider() ?? NSScreen.main else { return }
        let gap: CGFloat = 8
        let totalWidth = visible.reduce(CGFloat(0)) { $0 + $1.visibleFrame.width }
            + CGFloat(max(0, visible.count - 1)) * gap
        var x = screen.visibleFrame.maxX - totalWidth - 18
        let y = screen.visibleFrame.maxY - 88

        isApplyingSnap = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for panel in visible {
                panel.setVisibleOrigin(NSPoint(x: x, y: y), animate: true)
                x += panel.visibleFrame.width + gap
            }
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.isApplyingSnap = false
                self?.saveLayout()
            }
        }
    }

    func arrangeModulesVertically() {
        let visible = panels.filter(\.isVisible)
        guard let screen = screenProvider() ?? NSScreen.main else { return }
        let gap: CGFloat = 8
        let widest = visible.map(\.visibleFrame.width).max() ?? 0
        let x = screen.visibleFrame.maxX - widest - 18
        var y = screen.visibleFrame.maxY - 18

        isApplyingSnap = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for panel in visible {
                y -= panel.visibleFrame.height
                panel.setVisibleOrigin(NSPoint(x: x, y: y), animate: true)
                y -= gap
            }
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.isApplyingSnap = false
                self?.saveLayout()
            }
        }
    }

    func combineAllModules() {
        guard panels.count > 1, !isAnimatingPresentation, !isApplyingSnap,
              extractionSession == nil else { return }
        finishOrientationAnimation()
        let cells = panels.flatMap { panel in
            panel.kinds.compactMap { kind in
                panel.cellFrameOnScreen(for: kind).map { (kind: kind, frame: $0) }
            }
        }
        guard cells.count > 1 else { return }
        let xs = cells.map { $0.frame.midX }
        let ys = cells.map { $0.frame.midY }
        let horizontalSpread = (xs.max() ?? 0) - (xs.min() ?? 0)
        let verticalSpread = (ys.max() ?? 0) - (ys.min() ?? 0)
        let axis: ModuleAxis = horizontalSpread >= verticalSpread ? .horizontal : .vertical
        let sorted = cells.sorted {
            if axis == .horizontal {
                return $0.frame.midX == $1.frame.midX
                    ? $0.frame.midY > $1.frame.midY : $0.frame.midX < $1.frame.midX
            }
            return $0.frame.midY == $1.frame.midY
                ? $0.frame.midX < $1.frame.midX : $0.frame.midY > $1.frame.midY
        }
        let layout = ModuleLayout(kinds: sorted.map(\.kind), axis: axis)
        let bounds = cells.reduce(CGRect.null) { $0.union($1.frame) }
        var origin = NSPoint(x: bounds.midX - layout.size.width / 2,
                             y: bounds.midY - layout.size.height / 2)
        let anchor = panels.first(where: { $0.isVisible }) ?? panels[0]
        if let screen = anchor.screen?.visibleFrame {
            origin.x = max(screen.minX + 4, min(origin.x, screen.maxX - layout.size.width - 4))
            origin.y = max(screen.minY + 4, min(origin.y, screen.maxY - layout.size.height - 4))
        }
        let wasPresented = panels.contains { $0.isVisible }
        isApplyingSnap = true
        let previous = panels
        previous.forEach(removePanel)
        let combined = makePanel(layout: layout, origin: windowOrigin(forVisibleOrigin: origin))
        if wasPresented {
            combined.orderFrontRegardless()
            combined.animatePudding(axis: axis)
        }
        isApplyingSnap = false
        saveLayout()
    }

    func detachAllModules() {
        finishOrientationAnimation()

        // Rebuild every currently shown module, not just the panels that are
        // grouped at this instant. That makes "Detach" idempotent and avoids
        // a 2:1 leftover when a group has just changed orientation or another
        // module was already independent.
        let cellFrames = panels.flatMap { panel in
            panel.kinds.compactMap { kind in
                panel.cellFrameOnScreen(for: kind).map { (kind, $0) }
            }
        }
        guard !cellFrames.isEmpty else { return }

        let groupBounds = cellFrames.map(\.1).reduce(CGRect.null) { $0.union($1) }
        let detachedFrames = cellFrames.map { kind, frame -> (MetricKind, CGRect, CGRect) in
            let dx = frame.midX - groupBounds.midX
            let dy = frame.midY - groupBounds.midY
            let spread: CGFloat = 24
            // A three-row group uses 69pt cells to match potatoken hub's
            // large height, while every standalone card is 78pt tall. Keep
            // each original cell's top edge fixed as it becomes a standalone
            // card, so detaching never makes the whole group jump upward.
            let singleHeight = ModulePanel.singlePanelHeight
            let start = CGRect(
                x: frame.minX,
                y: frame.maxY - singleHeight,
                width: ModulePanel.cellSize.width,
                height: singleHeight
            )
            var target = start
            // Spread along the cell's dominant direction from the group's
            // centre. A middle cell has no dominant direction and stays put.
            if abs(dx) > abs(dy), abs(dx) > 1 {
                target.origin.x += dx > 0 ? spread : -spread
            } else if abs(dy) > 1 {
                target.origin.y += dy > 0 ? spread : -spread
            }
            return (kind, start, target)
        }

        // `setFrameOrigin` on each freshly made panel sends windowDidMove.
        // These frames intentionally start next to one another, so allowing
        // that callback through would schedule a new snap and immediately
        // recreate the very 2:1 grouping this command is meant to remove.
        isApplyingSnap = true
        let currentPanels = panels
        currentPanels.forEach(removePanel)

        var spawnedPanels: [(panel: ModulePanel, startFrame: CGRect, targetFrame: CGRect)] = []
        for (kind, startFrame, targetFrame) in detachedFrames {
            let panel = makePanel(kinds: [kind], origin: startFrame.origin)
            spawnedPanels.append((panel, startFrame, targetFrame))
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
        animateDetachment(spawnedPanels)
    }

    func show(_ kind: MetricKind) {
        setVisible(true, kind: kind)
        guard panel(containing: kind) == nil else { return }
        let panel = makePanel(kinds: [kind], origin: windowOrigin(forVisibleOrigin: defaultOrigin(for: kind)))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.animator().alphaValue = 1
    }

    /// `defaultOrigin` and legacy saved origins are expressed in visible-card
    /// space; `makePanel`/`setFrameOrigin` want the padded window origin.
    func windowOrigin(forVisibleOrigin origin: NSPoint) -> NSPoint {
        NSPoint(x: origin.x - ModulePanel.shadowMargin, y: origin.y - ModulePanel.shadowMargin)
    }

    func hide(_ kind: MetricKind) {
        setVisible(false, kind: kind)
        guard let panel = panel(containing: kind) else { return }
        let remainingLayout = panel.layout.removing(kind)
        if remainingLayout.cells.isEmpty {
            removePanel(panel)
            return
        }

        let oldFrame = panel.frame
        panel.update(layout: remainingLayout)
        let newSize = ModulePanel.windowSize(forVisible: remainingLayout.size)
        panel.setFrame(NSRect(origin: oldFrame.origin, size: newSize), display: true, animate: true)
    }

    func panel(containing kind: MetricKind) -> ModulePanel? {
        panels.first { $0.contains(kind) }
    }

    @discardableResult
    func makePanel(
        kinds: [MetricKind],
        axis: ModuleAxis = .horizontal,
        origin: NSPoint
    ) -> ModulePanel {
        makePanel(layout: ModuleLayout(kinds: kinds, axis: axis), origin: origin)
    }

    @discardableResult
    func makePanel(layout: ModuleLayout, origin: NSPoint) -> ModulePanel {
        let panel = ModulePanel(layout: layout, monitor: monitor)
        panel.delegate = self
        panel.onContextMenu = { [weak self] panel, event in
            self?.onContextMenu?(panel, event)
        }
        panel.onDoubleClick = { [weak self] panel in
            self?.toggleOrientation(of: panel)
        }
        panel.onInteractionStart = { [weak self] _ in
            self?.finishOrientationAnimation()
        }
        panel.onExtractionBegan = { [weak self] panel, kind, frame, point in
            self?.beginExtraction(from: panel, kind: kind, cellFrame: frame, pointer: point)
        }
        panel.onExtractionChanged = { [weak self] panel, point in
            self?.changeExtraction(from: panel, pointer: point)
        }
        panel.onExtractionEnded = { [weak self] panel, point in
            self?.endExtraction(from: panel, pointer: point)
        }
        panel.onPanelDragEnded = { [weak self] panel in
            guard let self else { return }
            self.snap(panel)
            if !self.isApplyingSnap { self.saveLayout() }
        }
        panel.setFrameOrigin(origin)
        panels.append(panel)
        return panel
    }

    func removePanel(_ panel: ModulePanel) {
        pendingSnaps[ObjectIdentifier(panel)]?.cancel()
        pendingSnaps[ObjectIdentifier(panel)] = nil
        panel.orderOut(nil)
        panel.delegate = nil
        panels.removeAll { $0 === panel }
        onPresenceChanged?()
    }

    func restorePanels() {
        var restored = Set<MetricKind>()
        var repairedDisconnectedGroup = false
        // Previously saved frames used 14pt, 8pt or 0pt padding. Keep their
        // visible cards in place as the shadow's rendering margin changes.
        let savedMargin = UserDefaults.standard.object(forKey: Self.savedShadowMarginKey)
            .flatMap { $0 as? CGFloat } ?? 14
        if let data = UserDefaults.standard.data(forKey: Self.groupsKey),
           let groups = try? JSONDecoder().decode([SavedGroup].self, from: data) {
            for saved in groups {
                let allowed = Set(saved.kinds.filter { isVisible($0) && !restored.contains($0) })
                let layout = (saved.layout ?? ModuleLayout(kinds: saved.kinds, axis: saved.axis))
                    .filtering(allowed)
                guard !layout.cells.isEmpty else { continue }
                layout.kinds.forEach { restored.insert($0) }
                // saved.frame is the real (padded) window frame saveLayout()
                // recorded; convert its origin back to visible-card space so
                // the cell arithmetic below works in the same units as
                // layout.cellHeight / ModulePanel.cellSize.
                let size = layout.size
                let savedWindowOrigin = NSRectFromString(saved.frame).origin
                var visibleFrame = NSRect(
                    origin: NSPoint(
                        x: savedWindowOrigin.x + savedMargin,
                        y: savedWindowOrigin.y + savedMargin
                    ),
                    size: size
                )
                let windowFrame = ModulePanel.windowSize(forVisible: size)
                if !frameIsOnScreen(NSRect(origin: windowOrigin(forVisibleOrigin: visibleFrame.origin), size: windowFrame)) {
                    visibleFrame.origin = defaultOrigin(for: layout.kinds[0])
                }

                let components = layout.edgeConnectedComponents
                repairedDisconnectedGroup = repairedDisconnectedGroup || components.count > 1
                for cells in components {
                    let component = ModuleLayout(cells: cells)
                    let minColumn = cells.map(\.position.column).min() ?? 0
                    let minRow = cells.map(\.position.row).min() ?? 0
                    let topY = visibleFrame.maxY - CGFloat(minRow) * layout.cellHeight
                    let origin = NSPoint(
                        x: visibleFrame.minX + CGFloat(minColumn) * ModulePanel.cellSize.width,
                        y: topY - component.size.height
                    )
                    let panel = makePanel(layout: component, origin: windowOrigin(forVisibleOrigin: origin))
                    panel.orderFrontRegardless()
                }
            }
        }

        for kind in MetricKind.allCases where isVisible(kind) && !restored.contains(kind) {
            let legacyKey = Self.legacyFramePrefix + kind.rawValue
            let legacyFrame = UserDefaults.standard.string(forKey: legacyKey).map(NSRectFromString)
            // A legacy saved frame predates the shadow margin, so its origin
            // is already window-space (no conversion); the default fallback is
            // visible-space and needs padding out like everywhere else.
            let origin = legacyFrame.flatMap { frameIsOnScreen($0) ? $0.origin : nil }
                ?? windowOrigin(forVisibleOrigin: defaultOrigin(for: kind))
            makePanel(kinds: [kind], origin: origin).orderFrontRegardless()
        }

        // Persist the repaired topology so a bad legacy shape cannot return
        // after the next relaunch.
        if repairedDisconnectedGroup {
            saveLayout()
        }
    }

    func saveLayout() {
        // Hidden windows are still enabled modules. Preserve their grouping
        // and positions when quitting while the presentation is hidden.
        let groups = panels.map {
            SavedGroup(kinds: $0.kinds, axis: $0.axis, layout: $0.layout, frame: NSStringFromRect($0.frame))
        }
        guard let data = try? JSONEncoder().encode(groups) else { return }
        UserDefaults.standard.set(data, forKey: Self.groupsKey)
        UserDefaults.standard.set(Double(ModulePanel.shadowMargin), forKey: Self.savedShadowMarginKey)
    }

    func isVisible(_ kind: MetricKind) -> Bool {
        let key = Self.visibilityPrefix + kind.rawValue
        if UserDefaults.standard.object(forKey: key) == nil { return true }
        return UserDefaults.standard.bool(forKey: key)
    }

    func setVisible(_ visible: Bool, kind: MetricKind) {
        UserDefaults.standard.set(visible, forKey: Self.visibilityPrefix + kind.rawValue)
    }

    func defaultOrigin(for kind: MetricKind) -> NSPoint {
        guard let screen = screenProvider() ?? NSScreen.main else { return .zero }
        let index = MetricKind.allCases.firstIndex(of: kind) ?? 0
        return NSPoint(
            x: screen.visibleFrame.maxX - ModulePanel.cellSize.width - 18
                - CGFloat(index) * (ModulePanel.cellSize.width + 8),
            y: screen.visibleFrame.maxY - ModulePanel.singlePanelHeight - 18
        )
    }

    func frameIsOnScreen(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
    }
}
