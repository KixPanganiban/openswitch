#!/bin/bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/openswitch/claude-usage"
CACHE_JSON="${CACHE_DIR}/usage.json"
CACHE_LOCK="${CACHE_DIR}/lock"
CACHE_TTL_SECONDS=60
# On transient errors only, reuse cache up to this age. Never for auth failures.
MAX_STALE_SECONDS=300
OAUTH_CLIENT_ID="9d1c250a-e61b-44d9-88ed-5944d1962f5e"
OAUTH_TOKEN_URL="https://platform.claude.com/v1/oauth/token"
USAGE_URL="https://api.anthropic.com/api/oauth/usage"
KEYCHAIN_SERVICE="Claude Code-credentials"
KEYCHAIN_ACCOUNT="$(whoami)"

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

read_fresh_cache() {
  if [[ -f "$CACHE_JSON" ]] && (( $(cache_age_seconds) < CACHE_TTL_SECONDS )); then
    read_cache
    return 0
  fi
  return 1
}

read_stale_cache() {
  if [[ -f "$CACHE_JSON" ]] && (( $(cache_age_seconds) < MAX_STALE_SECONDS )); then
    read_cache
    return 0
  fi
  return 1
}

acquire_lock() {
  mkdir -p "$CACHE_DIR"
  local waited=0
  while ! mkdir "$CACHE_LOCK" 2>/dev/null; do
    if read_fresh_cache >/dev/null; then
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

read_keychain_creds() {
  security find-generic-password -s "$KEYCHAIN_SERVICE" -w 2>/dev/null || true
}

write_keychain_creds() {
  local json="$1"
  security add-generic-password -U \
    -s "$KEYCHAIN_SERVICE" \
    -a "$KEYCHAIN_ACCOUNT" \
    -w "$json" >/dev/null
}

# Prints a usable access token. Refreshes and updates Keychain when expired.
# Pass "force" to refresh even if local expiresAt is still in the future.
ensure_access_token() {
  local force="${1:-}"
  local creds token refresh expires_at now_ms body tmp code new_json access new_refresh expires_in new_expires

  creds="$(read_keychain_creds)"
  if [[ -z "$creds" ]]; then
    echo "Claude Code credentials not found in keychain" >&2
    return 1
  fi

  token="$(printf '%s' "$creds" | jq -r '.claudeAiOauth.accessToken // empty')"
  refresh="$(printf '%s' "$creds" | jq -r '.claudeAiOauth.refreshToken // empty')"
  expires_at="$(printf '%s' "$creds" | jq -r '.claudeAiOauth.expiresAt // 0')"
  now_ms="$(($(date +%s) * 1000))"

  if [[ -z "$force" && -n "$token" && "$token" != "null" ]] && (( expires_at > now_ms + 60000 )); then
    printf '%s' "$token"
    return 0
  fi

  if [[ -z "$refresh" || "$refresh" == "null" ]]; then
    echo "oauth token expired; no refresh token (run claude /login)" >&2
    return 1
  fi

  body="$(jq -nc \
    --arg rt "$refresh" \
    --arg cid "$OAUTH_CLIENT_ID" \
    '{grant_type:"refresh_token",refresh_token:$rt,client_id:$cid}')"
  tmp="$(mktemp "${CACHE_DIR}/oauth.XXXXXX")"
  code="$(curl -sS -o "$tmp" -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -H "User-Agent: claude-code/2.1.72" \
    -d "$body" \
    "$OAUTH_TOKEN_URL" || true)"

  if [[ "$code" != "200" ]] || ! jq -e . >/dev/null 2>&1 <"$tmp"; then
    rm -f "$tmp"
    echo "oauth refresh failed (HTTP ${code:-000}); run claude /login" >&2
    return 1
  fi

  access="$(jq -r '.access_token // empty' "$tmp")"
  new_refresh="$(jq -r '.refresh_token // empty' "$tmp")"
  expires_in="$(jq -r '.expires_in // 28800' "$tmp")"
  rm -f "$tmp"

  if [[ -z "$access" ]]; then
    echo "oauth refresh returned no access_token" >&2
    return 1
  fi
  if [[ -z "$new_refresh" || "$new_refresh" == "null" ]]; then
    new_refresh="$refresh"
  fi
  new_expires="$((now_ms + expires_in * 1000))"

  new_json="$(printf '%s' "$creds" | jq -c \
    --arg at "$access" \
    --arg rt "$new_refresh" \
    --argjson exp "$new_expires" \
    '.claudeAiOauth.accessToken=$at
     | .claudeAiOauth.refreshToken=$rt
     | .claudeAiOauth.expiresAt=$exp')"
  if ! write_keychain_creds "$new_json"; then
    echo "oauth refresh ok but keychain update failed" >&2
    return 1
  fi

  printf '%s' "$access"
  return 0
}

request_usage() {
  local token="$1"
  local out="$2"
  curl -sS -o "$out" -w "%{http_code}" \
    -H "Authorization: Bearer ${token}" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "User-Agent: claude-code/2.1.72" \
    "$USAGE_URL" || true
}

fetch_usage_json() {
  local token tmp code

  if read_fresh_cache; then
    return
  fi

  if ! acquire_lock; then
    if read_fresh_cache; then
      return
    fi
    echo "usage request failed (busy)" >&2
    exit 1
  fi

  if read_fresh_cache; then
    release_lock
    return
  fi

  if ! token="$(ensure_access_token)"; then
    release_lock
    exit 1
  fi

  mkdir -p "$CACHE_DIR"
  tmp="$(mktemp "${CACHE_DIR}/usage.XXXXXX")"
  code="$(request_usage "$token" "$tmp")"

  if [[ "$code" == "401" ]]; then
    if ! token="$(ensure_access_token force)"; then
      rm -f "$tmp"
      release_lock
      exit 1
    fi
    code="$(request_usage "$token" "$tmp")"
  fi

  if [[ "$code" == "200" ]] && jq -e . >/dev/null 2>&1 <"$tmp"; then
    mv "$tmp" "$CACHE_JSON"
    release_lock
    read_cache
    return
  fi

  rm -f "$tmp"
  release_lock

  # Auth failures must not show stale percentages.
  if [[ "$code" == "401" || "$code" == "403" ]]; then
    echo "usage request failed (HTTP ${code}; auth). run claude /login" >&2
    exit 1
  fi

  if [[ "$code" == "429" || "$code" == "500" || "$code" == "502" || "$code" == "503" ]]; then
    if read_stale_cache; then
      return
    fi
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
