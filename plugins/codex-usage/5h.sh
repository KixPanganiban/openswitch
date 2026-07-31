#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/codex-usage-lib.sh"

json="$(fetch_usage_json)"
# ~5 hour window (4h–6h)
format_usage_line "5h" "$json" 14400 21600
