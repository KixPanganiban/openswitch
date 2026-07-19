# OpenSwitch

**Simple switches to do simple things.**

A tiny native macOS menu bar app that puts three everyday toggles one click away.

- **Keep Awake** — off by default. When on, your display and system won't sleep (via an IOKit power assertion).
- **Dark Mode** — reflects the current system appearance; toggles the system-wide Light/Dark setting.
- **Lock** — a momentary action that locks the screen immediately (shows the password prompt).
- **Sleep** — a momentary action that puts the computer to sleep immediately.
- **Kill Process** — a submenu of your running foreground apps (the ⌘-Tab list; helper and system processes are excluded). Click one to terminate it after a confirmation. Modifiers: **⌘-click** skips the confirmation, **⌥-click** sends `SIGKILL` (force) instead of `SIGTERM` — combine them (⌘⌥) to force-kill with no prompt.

Lives entirely in the menu bar — no Dock icon, no window.

## Requirements

- macOS 13 or later
- Swift toolchain (Xcode or Command Line Tools — `xcode-select --install`)

## Build & run

```sh
./build.sh          # builds and assembles OpenSwitch.app
open ./OpenSwitch.app
```

`build.sh` runs `swift build -c release`, bundles the binary into `OpenSwitch.app` with its `Info.plist`, and ad-hoc code-signs it (a stable identity so macOS remembers the Automation permission across rebuilds).

To quit: use **Quit OpenSwitch** in the menu, or `pkill -f OpenSwitch`.

## Permissions

Toggling **Dark Mode** scripts System Events, so the first time you use it macOS will ask for **Automation** permission — approve it once. **Keep Awake** and **Sleep** need no special permissions.

## How it works

| Feature | Mechanism |
| --- | --- |
| Keep Awake | `IOPMAssertionCreateWithName` with `kIOPMAssertionTypePreventUserIdleDisplaySleep` |
| Dark Mode | AppleScript → System Events `appearance preferences` |
| Lock | `SACLockScreenImmediate` from the private `login` framework (via `dlopen`) |
| Sleep | `pmset sleepnow` |
| Kill Process | `NSWorkspace.runningApplications` (regular apps only) to list, `kill(pid, SIGTERM/SIGKILL)` to terminate |

Built with AppKit (`NSStatusItem` + `NSMenu`) and Swift Package Manager. No third-party dependencies.

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).
