#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/claude-usage-lib.sh"

json="$(fetch_usage_json)"
format_usage_line "weekly" "$json" "seven_day"
