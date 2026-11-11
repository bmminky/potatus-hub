import AppKit

/// AppDelegate wires the menu-bar icon and the module panels together. A placeholder
/// SwiftUI Settings scene could appear as an empty window on a fresh launch.
@main
@MainActor
enum PotatusHubApp {
    private static let appDelegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = appDelegate
        app.finishLaunching()
        app.run()
    }
}
