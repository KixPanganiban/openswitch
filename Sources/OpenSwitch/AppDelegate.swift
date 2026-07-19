import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only utility: no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)
        statusBarController = StatusBarController()
    }
}
