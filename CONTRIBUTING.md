# Contributing to OpenSwitch

Thanks for your interest in improving OpenSwitch! It's a small, focused utility, so contributions of any size are welcome.

## Getting started

1. Fork and clone the repo.
2. Make sure you have the Swift toolchain (Xcode or Command Line Tools: `xcode-select --install`).
3. Build and run:
   ```sh
   ./build.sh
   open ./OpenSwitch.app
   ```

## Project layout

```
Sources/OpenSwitch/
  main.swift               NSApplication bootstrap (accessory / no Dock icon)
  AppDelegate.swift        Owns the status bar controller
  StatusBarController.swift Menu bar item, menu, and wiring
  KeepAwakeManager.swift    IOKit power assertion
  AppearanceManager.swift   Reads / toggles system appearance
  LockManager.swift         Locks the screen (private login framework)
  SleepManager.swift        Triggers system sleep
  ProcessManager.swift      Lists foreground apps and kills them (SIGTERM/SIGKILL)
  ClipboardManager.swift    Polls the pasteboard for recent text/image history
Resources/Info.plist       Bundle metadata, LSUIElement, permissions
build.sh                    Builds and assembles OpenSwitch.app
```

## Making changes

- Keep the app small and dependency-free — AppKit and system frameworks only.
- Match the existing style: clear names, small focused types, a short doc comment on each type.
- Run `swift build` to confirm it compiles before opening a PR.
- Update the [README](README.md) if you add or change user-facing behavior.
- Bump `CFBundleShortVersionString` in [Info.plist](Resources/Info.plist) for user-visible releases.

## Testing your change

There are no automated UI tests, so verify behavior by hand:

- **Keep Awake** — toggle on, confirm with `pmset -g assertions | grep -i openswitch`; toggle off and confirm it clears.
- **Dark Mode** — toggle and confirm the system appearance flips (approve the Automation prompt the first time).
- **Sleep** — click and confirm the machine sleeps.

## Submitting

1. Create a branch for your change.
2. Keep commits focused and write a clear commit message.
3. Open a pull request describing what changed and why.

## Reporting bugs & ideas

Open an issue describing the problem or suggestion, including your macOS version and steps to reproduce for bugs.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
