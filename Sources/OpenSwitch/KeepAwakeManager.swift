import Foundation
import IOKit.pwr_mgt

/// Prevents the display (and therefore the system) from going to sleep while active,
/// using an IOKit power assertion. The active state persists across app restarts.
final class KeepAwakeManager {
    private static let defaultsKey = "KeepAwakeEnabled"

    private var assertionID: IOPMAssertionID = 0
    private(set) var isActive = false

    /// Restores the persisted state, re-creating the assertion if it was left on.
    init() {
        if UserDefaults.standard.bool(forKey: Self.defaultsKey) {
            start()
        }
    }

    /// Turn keep-awake on or off. Idempotent. Persists the new state.
    func setActive(_ active: Bool) {
        active ? start() : stop()
        UserDefaults.standard.set(isActive, forKey: Self.defaultsKey)
    }

    /// Convenience: flip the current state and return the new value.
    @discardableResult
    func toggle() -> Bool {
        setActive(!isActive)
        return isActive
    }

    private func start() {
        guard !isActive else { return }
        let reason = "OpenSwitch Keep Awake" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )
        isActive = (result == kIOReturnSuccess)
    }

    private func stop() {
        guard isActive else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isActive = false
    }
}
