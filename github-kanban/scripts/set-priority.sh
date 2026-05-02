#!/usr/bin/env bash
# Set the priority of an issue on the kanban board.
#
# Usage: set-priority.sh [OPTIONS]
#
# Options:
#   --issue NUMBER      Issue number (required)
#   --priority PRIORITY New priority: p0|p1|p2 (required)
#   --config PATH       Path to .kanban-config.json (default: auto-detect)
#   --help              Show this help
#
# Exit codes:
#   0  Priority updated successfully
#   1  Invalid arguments
#   2  GitHub API error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# --- Help ---
show_help() {
  sed -n '2,/^$/{ s/^# \?//; p }' "$0"
  echo ""
  echo "Examples:"
  echo "  set-priority.sh --issue 15 --priority p0"
  echo "  set-priority.sh --issue 15 --priority p2"
}

if [[ "${1:-}" == "--help" ]]; then
  show_help
  exit 0
fi

# --- Parse arguments ---
ISSUE=""
PRIORITY=""
CONFIG_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue)    ISSUE="$2"; shift 2 ;;
    --priority) PRIORITY="$2"; shift 2 ;;
    --config)   CONFIG_PATH="$2"; shift 2 ;;
    --help)     show_help; exit 0 ;;
    *)          echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
  esac
done

# --- Validate ---
errors=()
[ -z "$ISSUE" ] && errors+=("--issue is required")
[ -z "$PRIORITY" ] && errors+=("--priority is required")

if [ -n "$PRIORITY" ]; then
  case "$PRIORITY" in
    p0|p1|p2) ;;
    *) errors+=("Invalid --priority: $PRIORITY (must be p0|p1|p2)") ;;
  esac
fi

if [ ${#errors[@]} -gt 0 ]; then
  for err in "${errors[@]}"; do
    echo "ERROR: $err" >&2
  done
  exit 1
fi

# --- Read config ---
CONFIG=$(find_config)
REPO=$(jq -r '.repo' "$CONFIG")
PROJECT_NUMBER=$(jq -r '.project_number' "$CONFIG")
OWNER=$(jq -r '.owner' "$CONFIG")
PROJECT_ID=$(jq -r '.project_id' "$CONFIG")
PRIORITY_FIELD_ID=$(jq -r '.priority_field_id' "$CONFIG")
PRIORITY_OPTION_ID=$(jq -r --arg p "$PRIORITY" '.priorities[$p]' "$CONFIG")

# --- Detect current priority label ---
CURRENT_LABELS=$(gh issue view "$ISSUE" --repo "$REPO" --json labels --jq '.labels[].name' 2>&1) || {
  echo "ERROR: Failed to fetch issue #$ISSUE" >&2
  echo "$CURRENT_LABELS" >&2
  exit 2
}

FROM_PRIORITY_LABEL=""
for label in $CURRENT_LABELS; do
  if [[ "$label" == priority:* ]]; then
    FROM_PRIORITY_LABEL="$label"
    break
  fi
done

# --- Update label ---
LABEL_ARGS=()
if [ -n "$FROM_PRIORITY_LABEL" ] && [ "$FROM_PRIORITY_LABEL" != "priority:$PRIORITY" ]; then
  LABEL_ARGS+=(--remove-label "$FROM_PRIORITY_LABEL")
fi
LABEL_ARGS+=(--add-label "priority:$PRIORITY")

gh issue edit "$ISSUE" --repo "$REPO" "${LABEL_ARGS[@]}" >/dev/null 2>&1 || {
  echo "ERROR: Failed to update issue labels" >&2
  exit 2
}

echo "Labels updated: ${FROM_PRIORITY_LABEL:-none} → priority:$PRIORITY" >&2

# --- Update board priority field ---
ITEM_ID=$(gh project item-list "$PROJECT_NUMBER" --owner "$OWNER" --format json \
  | jq -r --argjson num "$ISSUE" '.items[] | select(.content.number == $num) | .id') || {
  echo "ERROR: Failed to query project board items" >&2
  exit 2
}

if [ -z "$ITEM_ID" ]; then
  echo "ERROR: Issue #$ISSUE not found on project board — labels updated but board priority unchanged" >&2
  exit 2
fi

gh project item-edit --id "$ITEM_ID" \
  --project-id "$PROJECT_ID" \
  --field-id "$PRIORITY_FIELD_ID" \
  --single-select-option-id "$PRIORITY_OPTION_ID" || {
  echo "ERROR: Failed to update board priority for issue #$ISSUE" >&2
  exit 2
}
echo "Board updated: priority=$PRIORITY" >&2

# --- JSON output ---
jq -n \
  --argjson issue "$ISSUE" \
  --arg from "${FROM_PRIORITY_LABEL:-none}" \
  --arg to "priority:$PRIORITY" \
  --arg priority "$PRIORITY" \
  '{issue: $issue, from_label: $from, to_label: $to, priority: $priority}'
