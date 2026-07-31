#!/bin/bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/openswitch/codex-usage"
CACHE_JSON="${CACHE_DIR}/usage.json"
CACHE_LOCK="${CACHE_DIR}/lock"
CACHE_TTL_SECONDS=60
AUTH_JSON="${CODEX_AUTH_JSON:-$HOME/.codex/auth.json}"
USAGE_URL="https://chatgpt.com/backend-api/wham/usage"

for tool in curl jq; do
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
  local token account_id tmp code

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

  if [[ ! -f "$AUTH_JSON" ]]; then
    release_lock
    echo "Codex auth not found at ${AUTH_JSON}" >&2
    exit 1
  fi

  token="$(jq -r '.tokens.access_token // empty' "$AUTH_JSON")"
  account_id="$(jq -r '.tokens.account_id // empty' "$AUTH_JSON")"
  if [[ -z "$token" || "$token" == "null" ]]; then
    release_lock
    echo "Codex access token missing from auth.json" >&2
    exit 1
  fi
  if [[ -z "$account_id" || "$account_id" == "null" ]]; then
    release_lock
    echo "Codex account_id missing from auth.json" >&2
    exit 1
  fi

  tmp="$(mktemp "${CACHE_DIR}/usage.XXXXXX")"
  code="$(curl -sS -o "$tmp" -w "%{http_code}" \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: application/json" \
    -H "ChatGPT-Account-Id: ${account_id}" \
    "$USAGE_URL" || true)"

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
  local epoch="$1"
  local with_date="${2:-}"
  local formatted
  if [[ -z "$epoch" || "$epoch" == "null" ]]; then
    return 1
  fi
  if [[ -n "$with_date" ]]; then
    formatted="$(date -r "$epoch" "+%b %d %l:%M%p" 2>/dev/null || true)"
    formatted="$(printf '%s' "$formatted" | awk '{$1=$1; print}')"
  else
    formatted="$(date -r "$epoch" "+%l:%M%p" 2>/dev/null || true)"
    formatted="${formatted// /}"
  fi
  if [[ -n "$formatted" ]]; then
    printf 'resets %s' "$formatted"
    return 0
  fi
  return 1
}

# Pick a rate_limit window whose limit_window_seconds falls in [min,max].
# Checks rate_limit.primary_window and rate_limit.secondary_window only
# (skips per-model additional_rate_limits).
extract_window_json() {
  local json="$1"
  local min_s="$2"
  local max_s="$3"
  printf '%s' "$json" | jq -c --argjson min "$min_s" --argjson max "$max_s" '
    def ok($w):
      ($w != null)
      and ($w.limit_window_seconds != null)
      and ($w.limit_window_seconds >= $min)
      and ($w.limit_window_seconds <= $max);
    .rate_limit as $rl
    | if ok($rl.primary_window) then $rl.primary_window
      elif ok($rl.secondary_window) then $rl.secondary_window
      else empty
      end
  '
}

format_usage_line() {
  local label="$1"
  local json="$2"
  local min_s="$3"
  local max_s="$4"
  local window pct reset line_reset with_date=

  window="$(extract_window_json "$json" "$min_s" "$max_s" || true)"
  if [[ -z "$window" ]]; then
    printf '%s  unavailable\n' "$label"
    return 0
  fi

  pct="$(printf '%s' "$window" | jq -r '.used_percent // empty')"
  reset="$(printf '%s' "$window" | jq -r '.reset_at // empty')"
  if [[ -z "$pct" || "$pct" == "null" ]]; then
    echo "${label} data unavailable" >&2
    exit 1
  fi

  if [[ "$label" == "weekly" ]]; then
    with_date=1
  fi

  if line_reset="$(format_reset_time "$reset" "$with_date")"; then
    printf '%s  %s%%  ·  %s\n' "$label" "$pct" "$line_reset"
  else
    printf '%s  %s%%\n' "$label" "$pct"
  fi
}
