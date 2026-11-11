import AppKit

/// Owns the menu-bar icon. A left click toggles the panels; a right click
/// shows the menu built by `menuProvider`.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let onToggle: () -> Void
    private let menuProvider: () -> NSMenu

    /// The screen the menu-bar icon is on, if it has one yet.
    var screen: NSScreen? { statusItem.button?.window?.screen }

    init(onToggle: @escaping () -> Void, menuProvider: @escaping () -> NSMenu) {
        self.onToggle = onToggle
        self.menuProvider = menuProvider
        super.init()
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
