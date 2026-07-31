#!/bin/bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

for tool in security curl jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "missing dependency: $tool" >&2
    exit 1
  fi
done

fetch_usage_json() {
  local creds token response
  creds="$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null || true)"
  if [[ -z "$creds" ]]; then
    echo "Claude Code credentials not found in keychain" >&2
    exit 1
  fi

  token="$(printf '%s' "$creds" | jq -r '.claudeAiOauth.accessToken // empty')"
  if [[ -z "$token" || "$token" == "null" ]]; then
    echo "oauth access token missing from keychain entry" >&2
    exit 1
  fi

  response="$(curl -fsS \
    -H "Authorization: Bearer ${token}" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "User-Agent: claude-code/2.1.72" \
    "https://api.anthropic.com/api/oauth/usage")" || {
    echo "usage request failed" >&2
    exit 1
  }

  printf '%s' "$response"
}

format_reset_time() {
  local iso="$1"
  local truncated epoch formatted
  if [[ "$iso" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
    truncated="${BASH_REMATCH[1]}"
  else
    truncated="${iso%%.*}"
  fi
  epoch="$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "$truncated" "+%s" 2>/dev/null || true)"
  if [[ -n "$epoch" ]]; then
    formatted="$(date -r "$epoch" "+%l:%M%p" 2>/dev/null || true)"
    formatted="${formatted// /}"
    if [[ -n "$formatted" ]]; then
      printf 'resets %s' "$formatted"
      return
    fi
  fi
  printf 'resets %s' "$iso"
}

format_usage_line() {
  local label="$1"
  local json="$2"
  local field="$3"
  local pct reset
  pct="$(printf '%s' "$json" | jq -r ".${field}.utilization // .${field}.used_percentage // empty")"
  reset="$(printf '%s' "$json" | jq -r ".${field}.resets_at // empty")"
  if [[ -z "$pct" || "$pct" == "null" ]]; then
    echo "${field} data unavailable" >&2
    exit 1
  fi
  if [[ -n "$reset" && "$reset" != "null" ]]; then
    printf '%s  %s%%  ·  %s\n' "$label" "$pct" "$(format_reset_time "$reset")"
  else
    printf '%s  %s%%\n' "$label" "$pct"
  fi
}
