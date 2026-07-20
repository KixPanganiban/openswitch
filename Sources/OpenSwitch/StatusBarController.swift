import AppKit
import CoreAudio

/// Menu-item payload identifying an audio device and the role to assign it to.
private struct AudioTarget {
    let role: AudioManager.Role
    let id: AudioDeviceID
}

/// Owns the menu bar item and its menu, and wires its controls.
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let keepAwake = KeepAwakeManager()
    private let clipboard = ClipboardManager()

    private let keepAwakeItem: NSMenuItem
    private let darkModeItem: NSMenuItem
    private let killSubmenu = NSMenu(title: "Kill Process")
    private let clipboardSubmenu = NSMenu(title: "Clipboard")
    private let audioSubmenu = NSMenu(title: "Audio")

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        keepAwakeItem = NSMenuItem(title: "☕️ Keep Awake", action: nil, keyEquivalent: "")
        darkModeItem = NSMenuItem(title: "🌙 Dark Mode", action: nil, keyEquivalent: "")
        super.init()

        configureButton()
        configureMenu()
        clipboard.start()
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

        let audioItem = NSMenuItem(title: "🔊 Audio", action: nil, keyEquivalent: "")
        audioItem.toolTip = "Switch the default output, input, or alert sound device."
        audioSubmenu.delegate = self
        audioSubmenu.autoenablesItems = false
        audioItem.submenu = audioSubmenu
        menu.addItem(audioItem)

        menu.addItem(.separator())

        let lockItem = NSMenuItem(title: "🔒 Lock", action: #selector(lockScreen), keyEquivalent: "")
        lockItem.target = self
        menu.addItem(lockItem)

        let sleepItem = NSMenuItem(title: "🛏️ Sleep", action: #selector(sleepNow), keyEquivalent: "")
        sleepItem.target = self
        menu.addItem(sleepItem)

        // Parent item has no action — hovering reveals the submenu of processes.
        // The submenu is rebuilt each time it opens (see menuNeedsUpdate).
        let killItem = NSMenuItem(title: "☠️ Kill Process", action: nil, keyEquivalent: "")
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

        let clipboardItem = NSMenuItem(title: "📋 Clipboard", action: nil, keyEquivalent: "")
        clipboardItem.toolTip = "Recent copies. Click one to copy it again, then paste with ⌘V.\nPasswords and other sensitive copies are skipped."
        clipboardSubmenu.delegate = self
        clipboardSubmenu.autoenablesItems = false
        clipboardItem.submenu = clipboardSubmenu
        menu.addItem(clipboardItem)

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

    @objc private func lockScreen() {
        LockManager.lock()
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

    @objc private func copyClipboardEntry(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? ClipboardEntry else { return }
        clipboard.copyToPasteboard(entry)
    }

    @objc private func clearClipboard() {
        clipboard.clear()
    }

    @objc private func selectAudioDevice(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? AudioTarget else { return }
        AudioManager.setDefault(target.id, for: target.role)
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
        if menu === clipboardSubmenu {
            rebuildClipboardSubmenu()
            return
        }
        if menu === audioSubmenu {
            rebuildAudioSubmenu()
            return
        }
        // Reflect any changes made outside the app (e.g. appearance toggled in System Settings).
        refreshStates()
    }

    private func rebuildAudioSubmenu() {
        audioSubmenu.removeAllItems()

        let categories: [(title: String, role: AudioManager.Role)] = [
            ("🔈 Output", .output),
            ("🎙️ Input", .input),
            ("🔔 Alerts", .systemOutput),
        ]

        for category in categories {
            let item = NSMenuItem(title: category.title, action: nil, keyEquivalent: "")
            item.submenu = deviceMenu(for: category.role)
            audioSubmenu.addItem(item)
        }
    }

    private func deviceMenu(for role: AudioManager.Role) -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        let devices = AudioManager.devices(for: role)
        guard !devices.isEmpty else {
            let empty = NSMenuItem(title: "No devices", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
            return submenu
        }

        for device in devices {
            let item = NSMenuItem(title: device.name, action: #selector(selectAudioDevice(_:)), keyEquivalent: "")
            item.target = self
            item.state = device.isDefault ? .on : .off
            item.representedObject = AudioTarget(role: role, id: device.id)
            submenu.addItem(item)
        }
        return submenu
    }

    private func rebuildClipboardSubmenu() {
        clipboardSubmenu.removeAllItems()

        let entries = clipboard.history
        guard !entries.isEmpty else {
            let empty = NSMenuItem(title: "No items", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            clipboardSubmenu.addItem(empty)
            return
        }

        for entry in entries {
            let item = NSMenuItem(title: "", action: #selector(copyClipboardEntry(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry

            switch entry.content {
            case .text(let string):
                item.title = textPreview(string)
                item.image = symbolImage("doc.on.clipboard")
            case .image(let image):
                item.title = imageLabel(image)
                item.image = thumbnail(image)
            }
            clipboardSubmenu.addItem(item)
        }

        clipboardSubmenu.addItem(.separator())
        let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearClipboard), keyEquivalent: "")
        clearItem.target = self
        clipboardSubmenu.addItem(clearItem)
    }

    /// A single-line, length-limited preview of copied text.
    private func textPreview(_ text: String) -> String {
        let collapsed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        let limit = 50
        return collapsed.count > limit ? String(collapsed.prefix(limit)) + "…" : collapsed
    }

    private func imageLabel(_ image: NSImage) -> String {
        if let rep = image.representations.first, rep.pixelsWide > 0 {
            return "Image — \(rep.pixelsWide) × \(rep.pixelsHigh)"
        }
        return "Image"
    }

    private func thumbnail(_ image: NSImage) -> NSImage {
        let copy = image.copy() as! NSImage
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }

    private func symbolImage(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
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
            let stats = String(format: "%.0f%% · %.0f MB", process.cpuPercent, process.memoryMB)
            let item = NSMenuItem(
                title: "\(process.name)  —  \(stats)",
                action: #selector(killProcess(_:)),
                keyEquivalent: ""
            )
            item.attributedTitle = processTitle(name: process.name, stats: stats)
            if let icon = process.icon {
                let sized = icon.copy() as! NSImage
                sized.size = NSSize(width: 16, height: 16)
                item.image = sized
            }
            item.target = self
            item.representedObject = process
            item.toolTip = "PID \(process.pid)  ·  ⌘ skip confirm  ·  ⌥ force kill (SIGKILL)"
            killSubmenu.addItem(item)
        }
    }

    /// App name in normal color followed by a muted, resource-usage suffix.
    private func processTitle(name: String, stats: String) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let title = NSMutableAttributedString(
            string: name,
            attributes: [.font: font, .foregroundColor: NSColor.labelColor]
        )
        title.append(NSAttributedString(
            string: "   \(stats)",
            attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        ))
        return title
    }
}
