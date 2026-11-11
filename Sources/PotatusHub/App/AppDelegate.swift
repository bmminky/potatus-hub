import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = SystemMonitor()
    private lazy var coordinator = PanelCoordinator(monitor: monitor)
    private let settings = AppSettings.shared
    private lazy var menu = AppMenu(coordinator: coordinator, monitor: monitor, settings: settings) { [weak self] in
        self?.statusItemController.reload()
        self?.updateSampling()
    }
    private var displayAwake = true
    private var sessionActive = true
    private var statusItemController: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController = StatusItemController(
            monitor: monitor,
            settings: settings,
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
        // (notification, concerns the display (else the login session), new state)
        let stateChanges: [(Notification.Name, Bool, Bool)] = [
            (NSWorkspace.screensDidSleepNotification, true, false),
            (NSWorkspace.screensDidWakeNotification, true, true),
            (NSWorkspace.sessionDidResignActiveNotification, false, false),
            (NSWorkspace.sessionDidBecomeActiveNotification, false, true),
        ]
        for (name, isDisplay, state) in stateChanges {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if isDisplay {
                        self.displayAwake = state
                    } else {
                        self.sessionActive = state
                        // A missed screens-did-wake must not leave readouts frozen.
                        if state { self.displayAwake = true }
                    }
                    self.updateSampling()
                }
            }
        }
        updateSampling()
    }

    /// Sample only while a panel is on screen or a menu-bar readout is chosen
    /// (see `SamplingPolicy`).
    private func updateSampling() {
        let shouldSample = SamplingPolicy.shouldSample(
            panelVisible: coordinator.panels.contains { $0.occlusionState.contains(.visible) },
            menuBarKindsSelected: !settings.menuBarKinds.isEmpty,
            displayAwake: displayAwake,
            sessionActive: sessionActive
        )
        if shouldSample {
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
