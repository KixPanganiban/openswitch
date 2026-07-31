#!/bin/bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/openswitch/claude-usage"
CACHE_JSON="${CACHE_DIR}/usage.json"
CACHE_LOCK="${CACHE_DIR}/lock"
CACHE_TTL_SECONDS=60

for tool in security curl jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "missing dependency: $tool" >&2
    exit 1
  fi
done

cache_age_seconds() {
  if [[ ! -f "$CACHE_JSON" ]]; then
    printf '%s' "999999"
    return
  fi
  local mtime now
  mtime="$(stat -f %m "$CACHE_JSON")"
  now="$(date +%s)"
  printf '%s' "$((now - mtime))"
}

read_cache() {
  if [[ -f "$CACHE_JSON" ]]; then
    cat "$CACHE_JSON"
    return 0
  fi
  return 1
}

acquire_lock() {
  mkdir -p "$CACHE_DIR"
  local waited=0
  while ! mkdir "$CACHE_LOCK" 2>/dev/null; do
    if [[ -f "$CACHE_JSON" ]] && (( $(cache_age_seconds) < CACHE_TTL_SECONDS )); then
      return 1
    fi
    sleep 0.05
    waited=$((waited + 1))
    if (( waited > 200 )); then
      return 1
    fi
  done
  return 0
}

release_lock() {
  rmdir "$CACHE_LOCK" 2>/dev/null || true
}

fetch_usage_json() {
  local creds token tmp code

  if [[ -f "$CACHE_JSON" ]] && (( $(cache_age_seconds) < CACHE_TTL_SECONDS )); then
    read_cache
    return
  fi

  if ! acquire_lock; then
    if read_cache; then
      return
    fi
    echo "usage request failed (busy)" >&2
    exit 1
  fi

  if [[ -f "$CACHE_JSON" ]] && (( $(cache_age_seconds) < CACHE_TTL_SECONDS )); then
    release_lock
    read_cache
    return
  fi

  creds="$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null || true)"
  if [[ -z "$creds" ]]; then
    release_lock
    echo "Claude Code credentials not found in keychain" >&2
    exit 1
  fi

  token="$(printf '%s' "$creds" | jq -r '.claudeAiOauth.accessToken // empty')"
  if [[ -z "$token" || "$token" == "null" ]]; then
    release_lock
    echo "oauth access token missing from keychain entry" >&2
    exit 1
  fi

  tmp="$(mktemp "${CACHE_DIR}/usage.XXXXXX")"
  code="$(curl -sS -o "$tmp" -w "%{http_code}" \
    -H "Authorization: Bearer ${token}" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "User-Agent: claude-code/2.1.72" \
    "https://api.anthropic.com/api/oauth/usage" || true)"

  if [[ "$code" == "200" ]] && jq -e . >/dev/null 2>&1 <"$tmp"; then
    mv "$tmp" "$CACHE_JSON"
    release_lock
    read_cache
    return
  fi

  rm -f "$tmp"
  release_lock

  if read_cache; then
    return
  fi

  if [[ "$code" == "429" ]]; then
    echo "usage request failed (HTTP 429 rate limited)" >&2
  else
    echo "usage request failed (HTTP ${code:-000})" >&2
  fi
  exit 1
}

format_reset_time() {
  local iso="$1"
  local with_date="${2:-}"
  local truncated epoch formatted
  if [[ "$iso" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
    truncated="${BASH_REMATCH[1]}"
  else
    truncated="${iso%%.*}"
  fi
  epoch="$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "$truncated" "+%s" 2>/dev/null || true)"
  if [[ -n "$epoch" ]]; then
    if [[ -n "$with_date" ]]; then
      formatted="$(date -r "$epoch" "+%b %d %l:%M%p" 2>/dev/null || true)"
      formatted="$(printf '%s' "$formatted" | awk '{$1=$1; print}')"
    else
      formatted="$(date -r "$epoch" "+%l:%M%p" 2>/dev/null || true)"
      formatted="${formatted// /}"
    fi
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
  local pct reset with_date=
  pct="$(printf '%s' "$json" | jq -r ".${field}.utilization // .${field}.used_percentage // empty")"
  reset="$(printf '%s' "$json" | jq -r ".${field}.resets_at // empty")"
  if [[ -z "$pct" || "$pct" == "null" ]]; then
    echo "${field} data unavailable" >&2
    exit 1
  fi
  if [[ "$label" == "weekly" ]]; then
    with_date=1
  fi
  if [[ -n "$reset" && "$reset" != "null" ]]; then
    printf '%s  %s%%  ·  %s\n' "$label" "$pct" "$(format_reset_time "$reset" "$with_date")"
  else
    printf '%s  %s%%\n' "$label" "$pct"
  fi
}
