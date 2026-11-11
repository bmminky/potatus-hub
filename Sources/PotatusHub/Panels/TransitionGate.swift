import Foundation

/// "Code is moving the windows right now." While busy, `windowDidMove` must
/// not start a new docking pass. A plain flag (not a counter): `end()` always
/// clears it. If `end()` never arrives (an animation completion that does
/// not fire), the gate releases itself after `timeout` and calls `onTimeout`
/// so the position still gets saved.
@MainActor
final class TransitionGate {
    static let timeout: TimeInterval = 2

    private(set) var isBusy = false
    private var watchdog: DispatchWorkItem?
    var onTimeout: (() -> Void)?

    func begin() {
        isBusy = true
        watchdog?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isBusy else { return }
            self.isBusy = false
            self.watchdog = nil
            self.onTimeout?()
        }
        watchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeout, execute: work)
    }

    func end() {
        isBusy = false
        watchdog?.cancel()
        watchdog = nil
    }
}
