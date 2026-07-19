# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Always

- **Read [CONTRIBUTING.md](CONTRIBUTING.md) before making changes.** It holds the working conventions and the canonical project layout.
- **Keep the project layout in CONTRIBUTING.md up to date on every change** that adds, removes, or renames a source file. When you touch the file tree, update the layout block in the same commit.

## What this is

OpenSwitch is a native macOS menu bar utility (AppKit, no Dock icon). It exposes a small set of one-click actions from the status bar: Keep Awake, Dark Mode, Lock, Sleep, and a Kill Process submenu.

## Build & run

Only the Swift toolchain is required — no full Xcode (`.xcodeproj`/`xcodebuild` are not used).

```sh
./build.sh          # swift build -c release, assembles OpenSwitch.app, ad-hoc signs it
open ./OpenSwitch.app
pkill -f OpenSwitch  # quit a running instance (or use Quit OpenSwitch in the menu)
```

Rebuild and relaunch (`pkill` then `./build.sh` then `open`) after changing code — the running app is not hot-reloaded.

## Architecture

- Swift Package Manager executable target; bundled into `OpenSwitch.app` by `build.sh`. No third-party dependencies (AppKit, IOKit, Darwin only).
- `main.swift` sets `.accessory` activation policy (with `LSUIElement` in `Info.plist`) so the app is menu-bar-only.
- `StatusBarController` owns the `NSStatusItem` + `NSMenu`, wires every action, and syncs toggle checkmarks in `menuNeedsUpdate`.
- Each feature lives in its own focused type (`KeepAwakeManager`, `AppearanceManager`, `LockManager`, `SleepManager`, `ProcessManager`). Add new features as a new manager plus wiring in `StatusBarController`.
- User-visible version comes from `CFBundleShortVersionString` in `Resources/Info.plist`; bump it there for releases.

## Conventions

- Keep the app small and dependency-free; prefer system frameworks.
- Match existing style: clear names, small focused types, a short doc comment on each type.
- Run `swift build` to confirm it compiles before committing.
- Update [README.md](README.md) when user-facing behavior changes, and CONTRIBUTING.md's layout when the file tree changes.
- Private/undocumented APIs (e.g. `SACLockScreenImmediate` in `LockManager`) are acceptable when there's no public equivalent, but note them.

## Verifying changes

There are no automated tests. Verify by hand — build, launch, and exercise the affected menu item. For destructive actions (Lock, Sleep, Kill Process), verify the code path without triggering the irreversible effect where possible (e.g. resolve symbols / list processes rather than actually locking or killing).
