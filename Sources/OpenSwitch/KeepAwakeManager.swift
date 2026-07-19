import IOKit.pwr_mgt

/// Prevents the display (and therefore the system) from going to sleep while active,
/// using an IOKit power assertion. Default state is inactive — no assertion is held.
final class KeepAwakeManager {
    private var assertionID: IOPMAssertionID = 0
    private(set) var isActive = false

    /// Turn keep-awake on or off. Idempotent.
    func setActive(_ active: Bool) {
        active ? start() : stop()
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
