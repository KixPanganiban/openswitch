import AppKit

/// Owns the menu bar item and its menu, and wires the three controls.
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let keepAwake = KeepAwakeManager()

    private let keepAwakeItem: NSMenuItem
    private let darkModeItem: NSMenuItem

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        keepAwakeItem = NSMenuItem(title: "Keep Awake", action: nil, keyEquivalent: "")
        darkModeItem = NSMenuItem(title: "Dark Mode", action: nil, keyEquivalent: "")
        super.init()

        configureButton()
        configureMenu()
    }

    private func configureButton() {
        if let button = statusItem.button {
            let image = NSImage(
                systemSymbolName: "switch.2",
                accessibilityDescription: "OpenSwitch"
            )
            image?.isTemplate = true
            button.image = image
        }
    }

    private func configureMenu() {
        let menu = NSMenu()
        menu.delegate = self

        keepAwakeItem.target = self
        keepAwakeItem.action = #selector(toggleKeepAwake)
        menu.addItem(keepAwakeItem)

        darkModeItem.target = self
        darkModeItem.action = #selector(toggleDarkMode)
        menu.addItem(darkModeItem)

        menu.addItem(.separator())

        let sleepItem = NSMenuItem(title: "Sleep", action: #selector(sleepNow), keyEquivalent: "")
        sleepItem.target = self
        menu.addItem(sleepItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(
            title: "About OpenSwitch",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(
            title: "Quit OpenSwitch",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        statusItem.menu = menu
        refreshStates()
    }

    // MARK: - Actions

    @objc private func toggleKeepAwake() {
        keepAwake.toggle()
        refreshStates()
    }

    @objc private func toggleDarkMode() {
        AppearanceManager.toggle()
        // Appearance change is asynchronous; menuNeedsUpdate will re-sync on next open.
    }

    @objc private func sleepNow() {
        SleepManager.sleepNow()
    }

    @objc private func showAbout() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.1"
        let build = info?["CFBundleVersion"] as? String ?? "1"

        let credits = NSAttributedString(
            string: "Simple switches to do simple things.\n\nKix Panganiban (github.com/kixpanganiban)",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )

        // Accessory apps aren't active by default; activate so the panel comes to front.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "OpenSwitch",
            .applicationVersion: version,
            .version: build,
            .credits: credits,
        ])
    }

    // MARK: - State sync

    private func refreshStates() {
        keepAwakeItem.state = keepAwake.isActive ? .on : .off
        darkModeItem.state = AppearanceManager.isDark ? .on : .off
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Reflect any changes made outside the app (e.g. appearance toggled in System Settings).
        refreshStates()
    }
}
