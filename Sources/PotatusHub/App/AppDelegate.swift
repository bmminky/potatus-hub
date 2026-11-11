import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = SystemMonitor()
    private lazy var coordinator = PanelCoordinator(monitor: monitor)
    private lazy var menu = AppMenu(coordinator: coordinator, monitor: monitor)
    private var statusItemController: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController = StatusItemController(
            onToggle: { [weak self] in self?.coordinator.togglePanelPresentation() },
            menuProvider: { [weak self] in self?.menu.makeMenu() ?? NSMenu() }
        )
        coordinator.screenProvider = { [weak self] in self?.statusItemController.screen }
        coordinator.onPresenceChanged = { [weak self] in self?.updateSampling() }
        coordinator.onContextMenu = { [weak self] panel, event in
            self?.menu.showPanelMenu(panel, event: event)
        }

        coordinator.restorePanels()

        // Occlusion covers hide, screen sleep, lock and another Space in one
        // signal; the workspace notifications are a fallback so sampling
        // always resumes.
        let center = NotificationCenter.default
        center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) {
            [weak self] note in
            guard note.object is ModulePanel else { return }
            MainActor.assumeIsolated { self?.updateSampling() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateSampling() }
            }
        }
        updateSampling()
    }

    /// Sample only while some panel is actually on screen.
    private func updateSampling() {
        if coordinator.panels.contains(where: { $0.occlusionState.contains(.visible) }) {
            monitor.start()
        } else {
            monitor.stop()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        coordinator.saveLayout()
    }
}
