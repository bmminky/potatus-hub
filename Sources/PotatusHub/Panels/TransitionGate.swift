import Foundation

/// "Code is moving the windows right now." While busy, `windowDidMove` must
/// not start a new docking pass. A plain flag (not a counter): `end()` always
/// clears it. If `end()` never arrives (an animation completion that does
/// not fire), the gate releases itself after `timeout` (2s by default) and calls `onTimeout`
/// so the position still gets saved.
@MainActor
final class TransitionGate {
    static let defaultTimeout: TimeInterval = 2

    private let timeout: TimeInterval

    init(timeout: TimeInterval = TransitionGate.defaultTimeout) {
        self.timeout = timeout
    }

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
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
    }

    func end() {
        isBusy = false
        watchdog?.cancel()
        watchdog = nil
    }
}
