#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/codex-usage-lib.sh"

json="$(fetch_usage_json)"
# ~7 day window (6d–8d)
format_usage_line "weekly" "$json" 518400 691200
