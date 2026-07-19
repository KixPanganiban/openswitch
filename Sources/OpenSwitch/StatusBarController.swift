import AppKit

/// Owns the menu bar item and its menu, and wires the three controls.
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let keepAwake = KeepAwakeManager()

    private let keepAwakeItem: NSMenuItem
    private let darkModeItem: NSMenuItem
    private let killSubmenu = NSMenu(title: "Kill Process")

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

        // Parent item has no action — hovering reveals the submenu of processes.
        // The submenu is rebuilt each time it opens (see menuNeedsUpdate).
        let killItem = NSMenuItem(title: "Kill Process", action: nil, keyEquivalent: "")
        killItem.toolTip = """
        Pick an app to quit it.
        Click: confirm, then SIGTERM
        ⌘-click: skip the confirmation
        ⌥-click: force kill (SIGKILL)
        ⌘⌥-click: force kill, no confirmation
        """
        killSubmenu.delegate = self
        killSubmenu.autoenablesItems = false
        killItem.submenu = killSubmenu
        menu.addItem(killItem)

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

    @objc private func killProcess(_ sender: NSMenuItem) {
        guard let process = sender.representedObject as? NamedProcess else { return }

        let modifiers = NSApp.currentEvent?.modifierFlags ?? []
        // Orthogonal modifiers: Option chooses the signal, Command skips the prompt.
        let signal: KillSignal = modifiers.contains(.option) ? .kill : .term
        let skipConfirmation = modifiers.contains(.command)

        if skipConfirmation || confirmKill(process, signal: signal) {
            ProcessManager.kill(process, signal: signal)
        }
    }

    /// Presents a modal confirmation. Returns true if the user chose to proceed.
    private func confirmKill(_ process: NamedProcess, signal: KillSignal) -> Bool {
        let force = (signal == .kill)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = force ? "Force-kill “\(process.name)”?" : "Kill “\(process.name)”?"
        alert.informativeText = force
            ? "Sends SIGKILL to “\(process.name)” (PID \(process.pid)). It quits immediately — unsaved work is lost."
            : "Sends SIGTERM to “\(process.name)” (PID \(process.pid))."
        alert.addButton(withTitle: force ? "Force Kill" : "Kill")
        alert.addButton(withTitle: "Cancel")

        // Accessory apps aren't active by default; activate so the alert comes to front.
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
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
        if menu === killSubmenu {
            rebuildKillSubmenu()
            return
        }
        // Reflect any changes made outside the app (e.g. appearance toggled in System Settings).
        refreshStates()
    }

    private func rebuildKillSubmenu() {
        killSubmenu.removeAllItems()

        let processes = ProcessManager.userApplications()
        guard !processes.isEmpty else {
            let empty = NSMenuItem(title: "No applications", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            killSubmenu.addItem(empty)
            return
        }

        // Disabled header explaining the modifiers (tooltips on the parent are
        // preempted when the submenu auto-opens, so this is the reliable hint).
        let hint = NSMenuItem(title: "⌘ skip confirm   ·   ⌥ force kill", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        killSubmenu.addItem(hint)
        killSubmenu.addItem(.separator())

        for process in processes {
            let item = NSMenuItem(
                title: process.name,
                action: #selector(killProcess(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = process
            item.toolTip = "PID \(process.pid)  ·  ⌘ skip confirm  ·  ⌥ force kill (SIGKILL)"
            killSubmenu.addItem(item)
        }
    }
}
