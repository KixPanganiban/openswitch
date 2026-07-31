# Codex Usage (sample plugin)

Shows Codex / ChatGPT subscription **5-hour** and **weekly** usage in the OpenSwitch menu.

**Not enabled by default.** OpenSwitch never ships this plugin inside the app bundle. Nothing appears until you install it under `~/.config/openswitch/plugins/` yourself.

## Requirements

- Codex signed in with a ChatGPT account (`~/.codex/auth.json` with `tokens.access_token` and `tokens.account_id`)
- `jq` (Homebrew: `brew install jq`)
- `curl`

API-key-only Codex auth does not expose these ChatGPT subscription windows.

## Install

From the OpenSwitch repo root:

```sh
mkdir -p ~/.config/openswitch/plugins
ln -sf "$(pwd)/plugins/codex-usage" ~/.config/openswitch/plugins/codex-usage
chmod +x ~/.config/openswitch/plugins/codex-usage/*.sh
```

Or copy the directory instead of symlinking. Then **quit and relaunch** OpenSwitch.

## Uninstall

```sh
rm ~/.config/openswitch/plugins/codex-usage
```

Relaunch OpenSwitch. The plugin section disappears if no other plugins remain.

## What you see

Top-level item: **📦 Codex Usage**

Submenu rows:

- `5h  <pct>%  ·  resets <local time>` — or `5h  unavailable` if this plan has no ~5h window
- `weekly  <pct>%  ·  resets <local time>` — or `weekly  unavailable` if missing

Rows are labels only (no click actions). Windows are matched by `limit_window_seconds` (not by primary/secondary names), because plans differ in which slot is 5h vs weekly.

## How it works

1. `5h.sh` / `weekly.sh` source `codex-usage-lib.sh`.
2. The library reads `~/.codex/auth.json` (override with `CODEX_AUTH_JSON`).
3. It calls `https://chatgpt.com/backend-api/wham/usage` with:
   - `Authorization: Bearer …`
   - `ChatGPT-Account-Id: …`
4. It picks `rate_limit.primary_window` / `secondary_window` by duration and prints one line. `reset_at` is a unix timestamp formatted in local time.

Both rows share one cached json under `~/.cache/openswitch/codex-usage/usage.json` (60s ttl, file lock). on http errors, stale cache is reused when present.

## Files

| File | Role |
| --- | --- |
| `plugin.json` | Manifest (title, icon, children) |
| `codex-usage-lib.sh` | Shared auth, curl, cache, formatting |
| `5h.sh` | ~5-hour usage label |
| `weekly.sh` | ~weekly usage label |

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| Plugin missing from menu | Not installed under `~/.config/openswitch/plugins/`, or app not relaunched |
| `dir: script is not executable` | Run `chmod +x *.sh` |
| `missing dependency: jq` | Install `jq` |
| `Codex auth not found` / token missing | Run `codex login` |
| `5h  unavailable` | Plan has no ~5h window (common on some tiers); weekly may still work |
| `usage request failed (HTTP 429…)` | Rate limited; wait and reopen, or rely on cache under `~/.cache/openswitch/codex-usage/` |

General plugin rules: [docs/PLUGINS.md](../../docs/PLUGINS.md).
