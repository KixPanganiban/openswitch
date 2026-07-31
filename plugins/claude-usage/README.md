# Claude Usage (sample plugin)

Shows Claude Code **5-hour** and **weekly** usage in the OpenSwitch menu.

**Not enabled by default.** OpenSwitch never ships this plugin inside the app bundle. Nothing appears until you install it under `~/.config/openswitch/plugins/` yourself.

## Requirements

- Claude Code signed in on this Mac (OAuth credentials in Keychain, service `Claude Code-credentials`)
- `jq` (Homebrew: `brew install jq`)
- `curl` and `security` (macOS)

## Install

From the OpenSwitch repo root:

```sh
mkdir -p ~/.config/openswitch/plugins
ln -sf "$(pwd)/plugins/claude-usage" ~/.config/openswitch/plugins/claude-usage
chmod +x ~/.config/openswitch/plugins/claude-usage/*.sh
```

Or copy the directory instead of symlinking. Then **quit and relaunch** OpenSwitch.

## Uninstall

```sh
rm ~/.config/openswitch/plugins/claude-usage
```

Relaunch OpenSwitch. The plugin section disappears if no other plugins remain.

## What you see

Top-level item: **🤖 Claude Usage**

Submenu rows (labels from live API data):

- `5h  <pct>%  ·  resets <time>`
- `weekly  <pct>%  ·  resets <time>`

Rows are labels only (no click actions).

## How it works

1. `5h.sh` / `weekly.sh` source `claude-usage-lib.sh`.
2. The library reads Keychain service `Claude Code-credentials` and takes `.claudeAiOauth.accessToken`.
3. It calls `https://api.anthropic.com/api/oauth/usage` with:
   - `Authorization: Bearer …`
   - `anthropic-beta: oauth-2025-04-20`
   - `User-Agent: claude-code/2.1.72`
4. It prints one line from `five_hour` / `seven_day` (`utilization`, or `used_percentage` if present) and `resets_at`.

Scripts set a Finder-safe `PATH` so Homebrew `jq` resolves when OpenSwitch was not started from a shell.

## Files

| File | Role |
| --- | --- |
| `plugin.json` | Manifest (title, icon, children) |
| `claude-usage-lib.sh` | Shared auth, curl, formatting |
| `5h.sh` | 5-hour usage label |
| `weekly.sh` | Weekly usage label |

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| Plugin missing from menu | Not installed under `~/.config/openswitch/plugins/`, or app not relaunched |
| `dir: script is not executable` | Run `chmod +x *.sh` |
| `missing dependency: jq` | Install `jq`; confirm PATH in the script |
| `Claude Code credentials not found` | Sign in with Claude Code on this Mac |
| `oauth access token missing` | Keychain entry shape changed; inspect with Keychain Access / `security` |
| `usage request failed` | Network, token expiry, or API rate limits |

General plugin rules: [docs/PLUGINS.md](../../docs/PLUGINS.md).
