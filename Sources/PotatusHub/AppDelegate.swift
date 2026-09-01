import AppKit
import SwiftUI
import QuartzCore
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private struct SavedGroup: Codable {
        let kinds: [MetricKind]
        let axis: ModuleAxis
        let layout: ModuleLayout?
        let frame: String
    }

    private typealias MergeSide = MergeDirection

    private struct SnapCandidate {
        let score: CGFloat
        let origin: NSPoint
        let other: ModulePanel
        let side: MergeSide
        let targetKind: MetricKind?
    }

    private struct ExtractionSession {
        let source: ModulePanel
        let kind: MetricKind
        let ghost: ModulePanel
        let initialGhostFrame: NSRect
        let initialPointer: NSPoint
    }

    private let monitor = SystemMonitor()
    private var statusItem: NSStatusItem!
    private var panels: [ModulePanel] = []
    private var isApplyingSnap = false
    private var pendingSnaps: [ObjectIdentifier: DispatchWorkItem] = [:]
    private var extractionSession: ExtractionSession?
    private var isAnimatingPresentation = false
    private var orientationAnimation: Timer?
    private var pendingOrientation: (panel: ModulePanel, targetFrame: NSRect, minSize: NSSize, maxSize: NSSize)?
    private var detachmentAnimation: Timer?

    private static let visibilityPrefix = "PotatusHub.visible."
    private static let legacyFramePrefix = "PotatusHub.frame."
    private static let groupsKey = "PotatusHub.groups.v1"
    private let snapDistance: CGFloat = 28
    private let minimumMergeOverlap = NSSize(width: 30, height: 22)
    private let horizontalLaneTolerance: CGFloat = 32
    private let verticalLaneTolerance: CGFloat = 64

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png")
                .flatMap(NSImage.init(contentsOf:))
                ?? NSImage(systemSymbolName: "gauge.with.dots.needle.50percent", accessibilityDescription: "potatus hub")
            image?.size = NSSize(width: 18, height: 18)
            image?.isTemplate = true
            button.image = image
            button.toolTip = "potatus hub"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        restorePanels()
        monitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        saveLayout()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showTrayMenu()
        } else {
            togglePanelPresentation()
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let heading = NSMenuItem(title: L.t(ko: "모듈", en: "Modules", ja: "モジュール", zh: "模块"), action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)

        for kind in MetricKind.allCases {
            let item = NSMenuItem(title: kind.title, action: #selector(toggleModule(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = kind.rawValue
            item.state = isVisible(kind) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let refresh = NSMenuItem(title: L.t(ko: "새로고침", en: "Refresh", ja: "更新", zh: "刷新"), action: #selector(refresh), keyEquivalent: "")
        refresh.target = self
        menu.addItem(refresh)

        let vertical = NSMenuItem(title: L.t(ko: "세로 정렬", en: "Arrange Vertically", ja: "縦に整列", zh: "纵向排列"), action: #selector(arrangeModulesVertically), keyEquivalent: "")
        vertical.target = self
        menu.addItem(vertical)

        let horizontal = NSMenuItem(title: L.t(ko: "가로 정렬", en: "Arrange Horizontally", ja: "横に整列", zh: "横向排列"), action: #selector(arrangeModulesHorizontally), keyEquivalent: "")
        horizontal.target = self
        menu.addItem(horizontal)

        let detach = NSMenuItem(title: L.t(ko: "분리", en: "Detach", ja: "分離", zh: "分离"), action: #selector(detachAllModules), keyEquivalent: "")
        detach.target = self
        detach.isEnabled = panels.contains { $0.kinds.count > 1 }
        menu.addItem(detach)

        menu.addItem(.separator())
        let launchAtLogin = NSMenuItem(title: L.t(ko: "로그인 시 자동 실행", en: "Launch at Login", ja: "ログイン時に自動起動", zh: "登录时启动"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLogin.target = self
        launchAtLogin.state = isLaunchAtLoginEnabled ? .on : .off
        menu.addItem(launchAtLogin)

        menu.addItem(languageMenuItem())

        let about = NSMenuItem(title: L.t(ko: "potatus hub 정보", en: "About potatus hub", ja: "potatus hub について", zh: "关于 potatus hub"), action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: L.t(ko: "potatus hub 종료", en: "Quit potatus hub", ja: "potatus hub を終了", zh: "退出 potatus hub"), action: #selector(quit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    private func showTrayMenu() {
        statusItem.menu = makeMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func showPanelMenu(_ panel: ModulePanel, event: NSEvent) {
        guard let view = panel.contentView else { return }
        NSMenu.popUpContextMenu(makeMenu(), with: event, for: view)
    }

    private func languageMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "언어 / Language / 言語 / 语言", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let options: [(L.Language, String)] = [
            (.system, L.t(ko: "시스템 언어 따름", en: "Follow System", ja: "システム言語に従う", zh: "跟随系统语言")),
            (.korean, "한국어"),
            (.english, "English"),
            (.japanese, "日本語"),
            (.chinese, "中文"),
        ]
        for (language, title) in options {
            let option = NSMenuItem(title: title, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            option.target = self
            option.representedObject = language.rawValue
            option.state = L.languagePreference == language ? .on : .off
            submenu.addItem(option)
        }
        item.submenu = submenu
        return item
    }

    private func togglePanelPresentation() {
        guard !isAnimatingPresentation else { return }
        let hasPresentedPanel = panels.contains { $0.isVisible }
        guard !panels.isEmpty else { return }
        isAnimatingPresentation = true
        let group = DispatchGroup()
        for panel in panels {
            group.enter()
            panel.animatePresentation(show: !hasPresentedPanel) {
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            self?.isAnimatingPresentation = false
        }
    }

    @objc private func toggleModule(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let kind = MetricKind(rawValue: rawValue) else { return }

        if isVisible(kind) {
            hide(kind)
        } else {
            show(kind)
        }
        saveLayout()
    }

    @objc private func refresh() {
        monitor.refresh()
    }

    @objc private func arrangeModulesHorizontally() {
        let visible = panels.filter(\.isVisible)
        guard let screen = statusItem.button?.window?.screen ?? NSScreen.main else { return }
        let gap: CGFloat = 8
        let totalWidth = visible.reduce(CGFloat(0)) { $0 + $1.frame.width }
            + CGFloat(max(0, visible.count - 1)) * gap
        var x = screen.visibleFrame.maxX - totalWidth - 18
        let y = screen.visibleFrame.maxY - 88

        isApplyingSnap = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for panel in visible {
                panel.animator().setFrameOrigin(NSPoint(x: x, y: y))
                x += panel.frame.width + gap
            }
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.isApplyingSnap = false
                self?.saveLayout()
            }
        }
    }

    @objc private func arrangeModulesVertically() {
        let visible = panels.filter(\.isVisible)
        guard let screen = statusItem.button?.window?.screen ?? NSScreen.main else { return }
        let gap: CGFloat = 8
        let widest = visible.map(\.frame.width).max() ?? 0
        let x = screen.visibleFrame.maxX - widest - 18
        var y = screen.visibleFrame.maxY - 18

        isApplyingSnap = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for panel in visible {
                y -= panel.frame.height
                panel.animator().setFrameOrigin(NSPoint(x: x, y: y))
                y -= gap
            }
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.isApplyingSnap = false
                self?.saveLayout()
            }
        }
    }

    private var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if isLaunchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = L.t(ko: "로그인 시 자동 실행을 변경할 수 없습니다", en: "Unable to change Launch at Login", ja: "ログイン時の自動起動を変更できません", zh: "无法更改登录时启动")
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let language = L.Language(rawValue: rawValue) else { return }
        L.languagePreference = language
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "potatus hub"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0"
        alert.informativeText = L.t(
            ko: "버전 \(version)\nApple Silicon용 로컬 시스템 모니터\nCPU, RAM, GPU 사용량을 모듈 형태로 표시합니다.",
            en: "Version \(version)\nA local system monitor for Apple Silicon.\nDisplays CPU, RAM, and GPU usage as modules.",
            ja: "バージョン \(version)\nApple Silicon向けローカルシステムモニター。\nCPU・RAM・GPUの使用率をモジュールで表示します。",
            zh: "版本 \(version)\n适用于 Apple Silicon 的本地系统监视器。\n以模块形式显示 CPU、RAM 和 GPU 使用率。"
        )
        alert.addButton(withTitle: L.t(ko: "확인", en: "OK", ja: "OK", zh: "好"))
        alert.runModal()
    }

    @objc private func detachAllModules() {
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

    /// Drive every detached window from one timer. Multiple independent
    /// NSWindow animator transactions can be coalesced by AppKit, which is
    /// what made the previous split look like a series of jumps.
    private func animateDetachment(_ panels: [(panel: ModulePanel, startFrame: CGRect, targetFrame: CGRect)]) {
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
                    self.isApplyingSnap = false
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
    private func toggleOrientation(of panel: ModulePanel) {
        guard panel.kinds.count > 1 else { return }

        finishOrientationAnimation()

        let targetAxis: ModuleAxis = panel.axis == .horizontal ? .vertical : .horizontal
        let targetLayout = ModuleLayout(kinds: panel.kinds, axis: targetAxis)
        let currentFrame = panel.frame
        let targetSize = targetLayout.size
        guard targetSize != currentFrame.size else { return }

        var targetX = currentFrame.midX - targetSize.width / 2
        if let visible = panel.screen?.visibleFrame {
            targetX = min(max(targetX, visible.minX + 4), visible.maxX - targetSize.width - 4)
        }
        let targetFrame = NSRect(
            x: targetX,
            y: currentFrame.maxY - targetSize.height,
            width: targetSize.width,
            height: targetSize.height
        )

        // Install the destination arrangement before driving the frame, just
        // like potatoken swaps its tier content before its spring resize.
        panel.update(layout: targetLayout, resizeToFit: false)
        springOrient(panel, from: currentFrame, to: targetFrame)
    }

    /// Uses the exact 0.5s damped ease from potatoken hub's large/small
    /// double-click transition. A timer is needed because the overshoot must
    /// briefly go beyond the target frame, which AppKit's normal animator
    /// clamps away.
    private func springOrient(_ panel: ModulePanel, from startFrame: NSRect, to targetFrame: NSRect) {
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
        pendingOrientation = (panel, targetFrame, savedMin, savedMax)

        let duration: CFTimeInterval = 0.5
        let startTime = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self, weak panel] timer in
            Task { @MainActor [weak self, weak panel] in
                guard let self, let panel else {
                    timer.invalidate()
                    return
                }

                let progress = min((CACurrentMediaTime() - startTime) / duration, 1)
                let eased = Self.springEase(progress)
                panel.setFrame(
                    NSRect(
                        x: startFrame.origin.x + (targetFrame.origin.x - startFrame.origin.x) * eased,
                        y: startFrame.origin.y + (targetFrame.origin.y - startFrame.origin.y) * eased,
                        width: startFrame.width + (targetFrame.width - startFrame.width) * eased,
                        height: startFrame.height + (targetFrame.height - startFrame.height) * eased
                    ),
                    display: true
                )

                if progress >= 1 {
                    timer.invalidate()
                    self.orientationAnimation = nil
                    self.pendingOrientation = nil
                    panel.minSize = savedMin
                    panel.maxSize = savedMax
                    panel.setFrame(targetFrame, display: true)
                    self.saveLayout()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        orientationAnimation = timer
    }

    private func finishOrientationAnimation() {
        guard let timer = orientationAnimation, let pending = pendingOrientation else { return }
        timer.invalidate()
        orientationAnimation = nil
        pendingOrientation = nil
        pending.panel.minSize = pending.minSize
        pending.panel.maxSize = pending.maxSize
        pending.panel.setFrame(pending.targetFrame, display: true)
        saveLayout()
    }

    private static func springEase(_ t: Double) -> CGFloat {
        guard t < 1 else { return 1 }
        return CGFloat(1 - exp(-6 * t) * cos(9 * t))
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
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

    private func snap(_ moving: ModulePanel) {
        guard !isApplyingSnap else { return }
        let others = panels.filter { $0 !== moving && $0.isVisible }
        var best: SnapCandidate?

        for other in others {
            let movingFrame = moving.frame
            let otherFrame = other.frame
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

        guard let best else { return }
        animateMerge(moving, with: best)
    }

    private func consider(_ candidate: SnapCandidate, asBest best: inout SnapCandidate?) {
        if best == nil || candidate.score < best!.score {
            best = candidate
        }
    }

    /// Compare movement in each axis as a fraction of that axis's window size.
    /// A module moved below another therefore selects a vertical stack even
    /// though the cells are much wider than they are tall.
    private func mergeAxis(for moving: NSRect, relativeTo other: NSRect) -> ModuleAxis {
        let horizontalDistance = abs(moving.midX - other.midX) / max(moving.width, other.width, 1)
        let verticalDistance = abs(moving.midY - other.midY) / max(moving.height, other.height, 1)
        return horizontalDistance >= verticalDistance ? .horizontal : .vertical
    }

    private func mergePlacement(
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

    private func animateMerge(_ moving: ModulePanel, with candidate: SnapCandidate) {
        isApplyingSnap = true
        let start = moving.frame.origin
        let dx = candidate.origin.x - start.x
        let dy = candidate.origin.y - start.y
        let distance = max(1, hypot(dx, dy))
        let overshoot = NSPoint(
            x: candidate.origin.x + dx / distance * 3,
            y: candidate.origin.y + dy / distance * 3
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
                moving.animator().setFrameOrigin(candidate.origin)
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

    private func merge(
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
        let size = layout.size
        let joined = moving.frame.union(other.frame)
        let finalFrame = NSRect(
            x: joined.midX - size.width / 2,
            y: joined.midY - size.height / 2,
            width: size.width,
            height: size.height
        )

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

    private func show(_ kind: MetricKind) {
        setVisible(true, kind: kind)
        guard panel(containing: kind) == nil else { return }
        let panel = makePanel(kinds: [kind], origin: defaultOrigin(for: kind))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.animator().alphaValue = 1
    }

    private func hide(_ kind: MetricKind) {
        setVisible(false, kind: kind)
        guard let panel = panel(containing: kind) else { return }
        let remainingLayout = panel.layout.removing(kind)
        if remainingLayout.cells.isEmpty {
            removePanel(panel)
            return
        }

        let oldFrame = panel.frame
        panel.update(layout: remainingLayout)
        panel.setFrame(NSRect(origin: oldFrame.origin, size: remainingLayout.size), display: true, animate: true)
    }

    private func panel(containing kind: MetricKind) -> ModulePanel? {
        panels.first { $0.contains(kind) }
    }

    private func beginExtraction(
        from source: ModulePanel,
        kind: MetricKind,
        cellFrame: NSRect,
        pointer: NSPoint
    ) {
        guard extractionSession == nil, source.kinds.count > 1 else { return }
        pendingSnaps[ObjectIdentifier(source)]?.cancel()
        pendingSnaps[ObjectIdentifier(source)] = nil

        let ghost = ModulePanel(kinds: [kind], monitor: monitor)
        ghost.setFrame(cellFrame, display: true)
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
            initialGhostFrame: cellFrame,
            initialPointer: pointer
        )
    }

    private func changeExtraction(from source: ModulePanel, pointer: NSPoint) {
        guard let session = extractionSession, session.source === source else { return }
        session.ghost.setFrameOrigin(NSPoint(
            x: session.initialGhostFrame.minX + pointer.x - session.initialPointer.x,
            y: session.initialGhostFrame.minY + pointer.y - session.initialPointer.y
        ))
    }

    private func endExtraction(from source: ModulePanel, pointer: NSPoint) {
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

    private func cancelExtraction(_ session: ExtractionSession) {
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

    private func completeExtraction(_ session: ExtractionSession) {
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
        let newSize = remainingLayout.size
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
                source?.setFrame(sourceFrame, display: true)
                self?.isApplyingSnap = false
                self?.saveLayout()
            }
        }
    }

    @discardableResult
    private func makePanel(
        kinds: [MetricKind],
        axis: ModuleAxis = .horizontal,
        origin: NSPoint
    ) -> ModulePanel {
        makePanel(layout: ModuleLayout(kinds: kinds, axis: axis), origin: origin)
    }

    @discardableResult
    private func makePanel(layout: ModuleLayout, origin: NSPoint) -> ModulePanel {
        let panel = ModulePanel(layout: layout, monitor: monitor)
        panel.delegate = self
        panel.onContextMenu = { [weak self] panel, event in
            self?.showPanelMenu(panel, event: event)
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

    private func removePanel(_ panel: ModulePanel) {
        pendingSnaps[ObjectIdentifier(panel)]?.cancel()
        pendingSnaps[ObjectIdentifier(panel)] = nil
        panel.orderOut(nil)
        panel.delegate = nil
        panels.removeAll { $0 === panel }
    }

    private func restorePanels() {
        var restored = Set<MetricKind>()
        if let data = UserDefaults.standard.data(forKey: Self.groupsKey),
           let groups = try? JSONDecoder().decode([SavedGroup].self, from: data) {
            for saved in groups {
                let allowed = Set(saved.kinds.filter { isVisible($0) && !restored.contains($0) })
                let layout = (saved.layout ?? ModuleLayout(kinds: saved.kinds, axis: saved.axis))
                    .filtering(allowed)
                guard !layout.cells.isEmpty else { continue }
                layout.kinds.forEach { restored.insert($0) }
                let size = layout.size
                var frame = NSRect(origin: NSRectFromString(saved.frame).origin, size: size)
                if !frameIsOnScreen(frame) {
                    frame.origin = defaultOrigin(for: layout.kinds[0])
                }
                let panel = makePanel(layout: layout, origin: frame.origin)
                panel.orderFrontRegardless()
            }
        }

        for kind in MetricKind.allCases where isVisible(kind) && !restored.contains(kind) {
            let legacyKey = Self.legacyFramePrefix + kind.rawValue
            let legacyFrame = UserDefaults.standard.string(forKey: legacyKey).map(NSRectFromString)
            let origin = legacyFrame.flatMap { frameIsOnScreen($0) ? $0.origin : nil }
                ?? defaultOrigin(for: kind)
            makePanel(kinds: [kind], origin: origin).orderFrontRegardless()
        }
    }

    private func saveLayout() {
        let groups = panels.filter(\.isVisible).map {
            SavedGroup(kinds: $0.kinds, axis: $0.axis, layout: $0.layout, frame: NSStringFromRect($0.frame))
        }
        guard let data = try? JSONEncoder().encode(groups) else { return }
        UserDefaults.standard.set(data, forKey: Self.groupsKey)
    }

    private func isVisible(_ kind: MetricKind) -> Bool {
        let key = Self.visibilityPrefix + kind.rawValue
        if UserDefaults.standard.object(forKey: key) == nil { return true }
        return UserDefaults.standard.bool(forKey: key)
    }

    private func setVisible(_ visible: Bool, kind: MetricKind) {
        UserDefaults.standard.set(visible, forKey: Self.visibilityPrefix + kind.rawValue)
    }

    private func defaultOrigin(for kind: MetricKind) -> NSPoint {
        guard let screen = statusItem.button?.window?.screen ?? NSScreen.main else { return .zero }
        let index = MetricKind.allCases.firstIndex(of: kind) ?? 0
        return NSPoint(
            x: screen.visibleFrame.maxX - ModulePanel.cellSize.width - 18
                - CGFloat(index) * (ModulePanel.cellSize.width + 8),
            y: screen.visibleFrame.maxY - ModulePanel.singlePanelHeight - 18
        )
    }

    private func frameIsOnScreen(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
    }

}
