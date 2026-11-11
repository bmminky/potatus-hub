import AppKit
import Combine

/// Owns the menu-bar item. With no metrics chosen it is the plain app icon;
/// otherwise it shows `[icon] 62%` for each chosen metric. A left click
/// toggles the panels; a right click shows the menu built by `menuProvider`.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let monitor: SystemMonitor
    private let settings: AppSettings
    private let onToggle: () -> Void
    private let menuProvider: () -> NSMenu
    private let appIcon: NSImage?
    private var subscriptions = Set<AnyCancellable>()
    private var redrawPending = false

    /// The screen the menu-bar icon is on, if it has one yet.
    var screen: NSScreen? { statusItem.button?.window?.screen }

    init(monitor: SystemMonitor, settings: AppSettings = .shared,
         onToggle: @escaping () -> Void, menuProvider: @escaping () -> NSMenu) {
        self.monitor = monitor
        self.settings = settings
        self.onToggle = onToggle
        self.menuProvider = menuProvider
        let image = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png")
            .flatMap(NSImage.init(contentsOf:))
            ?? NSImage(systemSymbolName: "gauge.with.dots.needle.50percent", accessibilityDescription: "potatus hub")
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        self.appIcon = image
        super.init()
        if let button = statusItem.button {
            button.toolTip = "potatus hub"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        reload()
    }

    /// Re-read the chosen metrics (after the menu changed them) and redraw.
    func reload() {
        subscriptions.removeAll()
        for kind in settings.menuBarKinds {
            monitor.metric(for: kind).$value
                .sink { [weak self] _ in
                    MainActor.assumeIsolated { self?.scheduleRedraw() }
                }
                .store(in: &subscriptions)
        }
        redraw()
    }

    // @Published notifies before it stores the new value, so redraw on the
    // next run-loop turn, once (several metrics can change in one tick).
    private func scheduleRedraw() {
        guard !redrawPending else { return }
        redrawPending = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.redrawPending = false
                self?.redraw()
            }
        }
    }

    private func redraw() {
        guard let button = statusItem.button else { return }
        let kinds = settings.menuBarKinds
        if kinds.isEmpty {
            statusItem.length = NSStatusItem.squareLength
            button.image = appIcon
            return
        }
        var values: [MetricKind: Double?] = [:]
        for kind in kinds { values[kind] = monitor.metric(for: kind).value }
        let items = MenuBarDisplay.items(kinds: kinds, values: values)
        statusItem.length = NSStatusItem.variableLength
        button.image = MenuBarImage.make(items: items)
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showTrayMenu()
        } else {
            onToggle()
        }
    }

    private func showTrayMenu() {
        statusItem.menu = menuProvider()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
}
