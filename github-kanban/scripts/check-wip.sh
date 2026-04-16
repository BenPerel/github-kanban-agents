#!/usr/bin/env bash
# Check WIP limit for a kanban stage.
#
# Usage: check-wip.sh [OPTIONS]
#
# Options:
#   --stage STAGE       Stage to check (required)
#   --config PATH       Path to .kanban-config.json (default: auto-detect)
#   --help              Show this help
#
# Exit codes:
#   0  Under WIP limit (can add)
#   1  At or over WIP limit
#   2  GitHub API error

set -euo pipefail

# --- Help ---
show_help() {
  sed -n '2,/^$/{ s/^# \?//; p }' "$0"
  echo ""
  echo "Examples:"
  echo "  check-wip.sh --stage in-progress"
  echo "  check-wip.sh --stage backlog"
  echo "  check-wip.sh --stage in-review"
}

if [[ "${1:-}" == "--help" ]]; then
  show_help
  exit 0
fi

# --- Locate config ---
find_config() {
  if [ -n "${CONFIG_PATH:-}" ]; then
    echo "$CONFIG_PATH"
    return
  fi
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "ERROR: Not in a git repo" >&2; exit 1; }
  local config="$root/.kanban-config.json"
  if [ ! -f "$config" ]; then
    echo "ERROR: .kanban-config.json not found at $config" >&2
    echo "Run setup.sh first to generate it." >&2
    exit 1
  fi
  echo "$config"
}

# --- WIP limits ---
declare -A WIP_LIMITS
WIP_LIMITS=(
  [backlog]=10
  [in-progress]=3
  [in-review]=5
)

# --- Parse arguments ---
STAGE=""
CONFIG_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stage)  STAGE="$2"; shift 2 ;;
    --config) CONFIG_PATH="$2"; shift 2 ;;
    --help)   show_help; exit 0 ;;
    *)        echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
  esac
done

# --- Validate ---
if [ -z "$STAGE" ]; then
  echo "ERROR: --stage is required" >&2
  exit 1
fi

if [ -z "${WIP_LIMITS[$STAGE]:-}" ]; then
  echo "ERROR: No WIP limit defined for stage '$STAGE'" >&2
  echo "Stages with WIP limits: backlog (10), in-progress (3), in-review (5)" >&2
  exit 1
fi

# --- Read config ---
CONFIG=$(find_config)
REPO=$(jq -r '.repo' "$CONFIG")

# --- Get the stage label ---
STAGE_LABEL=$(jq -r --arg s "$STAGE" '.stages[$s].label' "$CONFIG")
LIMIT="${WIP_LIMITS[$STAGE]}"

# --- Count open issues in this stage ---
COUNT=$(gh issue list --repo "$REPO" --label "$STAGE_LABEL" --state open --json number --jq 'length' 2>&1) || {
  echo "ERROR: Failed to count issues for $STAGE_LABEL" >&2
  echo "$COUNT" >&2
  exit 2
}

# --- Output ---
AVAILABLE=$((LIMIT - COUNT))
if [ "$AVAILABLE" -lt 0 ]; then
  AVAILABLE=0
fi

jq -n \
  --arg stage "$STAGE" \
  --argjson count "$COUNT" \
  --argjson limit "$LIMIT" \
  --argjson available "$AVAILABLE" \
  --arg status "$([ "$COUNT" -lt "$LIMIT" ] && echo "under" || echo "at_or_over")" \
  '{stage: $stage, count: $count, limit: $limit, available: $available, status: $status}'

if [ "$COUNT" -ge "$LIMIT" ]; then
  echo "$STAGE: $COUNT/$LIMIT — AT OR OVER LIMIT" >&2
  exit 1
else
  echo "$STAGE: $COUNT/$LIMIT — $AVAILABLE slots available" >&2
  exit 0
fi
