import Foundation

/// Whether measuring should run. Floating panels keep the old rule (sample
/// while one is actually visible; occlusion already covers sleep and lock).
/// Menu-bar readouts also need the display awake and the session active.
enum SamplingPolicy {
    static func shouldSample(
        panelVisible: Bool,
        menuBarKindsSelected: Bool,
        displayAwake: Bool,
        sessionActive: Bool
    ) -> Bool {
        panelVisible || (menuBarKindsSelected && displayAwake && sessionActive)
    }
}
