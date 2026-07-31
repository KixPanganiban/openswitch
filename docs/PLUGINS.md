# OpenSwitch plugins

OpenSwitch can show extra top-level menu items from scripts you install under your home directory. The core app stays dependency-free. Plugins are optional and never ship enabled inside the app bundle.

## Install location

```
~/.config/openswitch/plugins/<name>/plugin.json
~/.config/openswitch/plugins/<name>/<scripts…>
```

OpenSwitch scans that directory **once at launch**. Add, remove, or edit a plugin, then relaunch the app (`Quit OpenSwitch`, then open it again).

If the plugins directory is missing or empty, the menu looks like a stock install — no plugin section, no extra separators.

## Manifest (`plugin.json`)

```json
{
  "title": "My Plugin",
  "icon": "🧩",
  "onClick": "./action.sh",
  "children": [
    { "onRender": "./label.sh" },
    { "onRender": "./label.sh", "onClick": "./action.sh" }
  ]
}
```

| Field | Rules |
| --- | --- |
| `title` | Required. Menu label. |
| `icon` | Optional. Literal emoji or text prepended to `title`. No shortcodes, no image files. |
| `onClick` | Relative path to an **executable** file under the plugin directory. Required for leaf plugins (no `children`). Ignored when `children` is non-empty. |
| `children` | Optional. Non-empty list → parent becomes a submenu. |
| `children[].onRender` | Required for every child. Relative executable that prints the row label on stdout. |
| `children[].onClick` | Optional. Relative executable run when the row is clicked. |

### Leaf vs submenu

- **Leaf** — no `children`. Clicking the top-level item runs `onClick`.
- **Submenu** — `children` present. Hover opens the submenu. Parent `onClick` is ignored. A child with only `onRender` is a disabled label. A child with `onRender` and `onClick` is clickable.

### Scripts

- Values must be **relative paths to regular executable files** inside the plugin directory (symlink-safe; paths may not escape the plugin dir). No inline shell strings in JSON.
- Working directory for each run is the plugin directory.
- Mark scripts executable: `chmod +x *.sh`.
- Set `PATH` inside scripts if you need Homebrew tools. A menu bar app launched from Finder often has a minimal environment (`/usr/bin`, `/bin`).

Example PATH line for scripts:

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
```

## Menu placement

Plugin items appear as **top-level** entries, separated from the built-in actions and from About / Quit. Invalid plugins show as a disabled row: `<directory>: <reason>`.

## `onRender` refresh

When a plugin submenu opens:

1. Every child `onRender` script starts **concurrently**.
2. OpenSwitch waits up to **500 ms** for that whole batch (one budget, not 500 ms per child).
3. Finished scripts update the row title and the success cache.
4. Scripts still running show the **last successful** title, or `…` on first open.
5. Late finishes update the live row if that menu open is still current.

Failures paint an error string on the row for that open. The success cache is not overwritten by failures, so the next slow open can still show the last good label.

Hung scripts are killed after **30 seconds** (process group). `onClick` runs off the main thread; failures show an alert.

## Output rules

- Stdout on exit 0 → row title (whitespace collapsed to one line, capped at 80 characters).
- Non-zero exit → error text from stderr (else stdout, else `exit <code>` / `timeout`).

## Invalid plugins

A bad `plugin.json`, missing `title`, missing required scripts, non-executable files, or path escape yields one disabled top-level item. Other plugins still load.

## Samples

Samples under `plugins/` in the repo are **not** enabled by default. Copy or symlink them into `~/.config/openswitch/plugins/` yourself.

See [Claude Usage](../plugins/claude-usage/README.md) for the shipped sample.
