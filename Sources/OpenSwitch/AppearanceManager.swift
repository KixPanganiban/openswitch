import AppKit

/// Reads and toggles the system-wide Light/Dark appearance.
///
/// Reading is done via the `AppleInterfaceStyle` global default. Toggling is done by
/// scripting System Events, which triggers a one-time macOS Automation permission prompt
/// (declared via `NSAppleEventsUsageDescription` in Info.plist).
enum AppearanceManager {

    /// True when the system is currently in Dark mode.
    static var isDark: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    /// Flip the system appearance.
    static func toggle() {
        setDark(!isDark)
    }

    /// Set the system appearance to dark (`true`) or light (`false`).
    static func setDark(_ dark: Bool) {
        let source = """
        tell application "System Events"
            tell appearance preferences
                set dark mode to \(dark)
            end tell
        end tell
        """

        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return }
        script.executeAndReturnError(&error)

        if let error {
            NSLog("OpenSwitch: failed to set appearance: \(error)")
        }
    }
}
