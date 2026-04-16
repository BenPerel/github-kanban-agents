#!/usr/bin/env bash
# Create a GitHub issue with correct labels and board status.
#
# Usage: create-issue.sh [OPTIONS]
#
# Options:
#   --title TEXT        Issue title (required)
#   --body TEXT         Issue body (required)
#   --stage STAGE       Target stage (default: ready)
#   --type TYPE         Issue type: bug|enhancement|documentation (required)
#   --priority PRIORITY Priority: p0|p1|p2 (default: p2)
#   --size SIZE         Size: xs|s|m|l|xl (required if stage is ready+)
#   --blocked-by N      Issue number this is blocked by (repeatable)
#   --config PATH       Path to .kanban-config.json (default: auto-detect)
#   --help              Show this help
#
# Exit codes:
#   0  Issue created successfully
#   1  Invalid arguments or missing required labels
#   2  GitHub API error

set -euo pipefail

# --- Help ---
show_help() {
  sed -n '2,/^$/{ s/^# \?//; p }' "$0"
  echo ""
  echo "Examples:"
  echo "  create-issue.sh --title 'Fix login bug' --body 'The login page crashes' --type bug --size s"
  echo "  create-issue.sh --title 'Add dark mode' --body 'Users want dark mode' --type enhancement --priority p1 --size m"
  echo "  create-issue.sh --title 'Blocked task' --body 'Depends on auth' --type enhancement --stage backlog --blocked-by 42"
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

# --- Parse arguments ---
TITLE=""
BODY=""
STAGE="ready"
TYPE=""
PRIORITY="p2"
SIZE=""
BLOCKED_BY=()
CONFIG_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)    TITLE="$2"; shift 2 ;;
    --body)     BODY="$2"; shift 2 ;;
    --stage)    STAGE="$2"; shift 2 ;;
    --type)     TYPE="$2"; shift 2 ;;
    --priority) PRIORITY="$2"; shift 2 ;;
    --size)     SIZE="$2"; shift 2 ;;
    --blocked-by) BLOCKED_BY+=("$2"); shift 2 ;;
    --config)   CONFIG_PATH="$2"; shift 2 ;;
    --help)     show_help; exit 0 ;;
    *)          echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
  esac
done

# --- Validate required args ---
errors=()
[ -z "$TITLE" ] && errors+=("--title is required")
[ -z "$BODY" ] && errors+=("--body is required")
[ -z "$TYPE" ] && errors+=("--type is required")

# Validate enums
case "$TYPE" in
  bug|enhancement|documentation) ;;
  "") ;;  # already caught above
  *) errors+=("Invalid --type: $TYPE (must be bug|enhancement|documentation)") ;;
esac

case "$PRIORITY" in
  p0|p1|p2) ;;
  *) errors+=("Invalid --priority: $PRIORITY (must be p0|p1|p2)") ;;
esac

case "$STAGE" in
  backlog|ready|in-progress|in-review|done) ;;
  *) errors+=("Invalid --stage: $STAGE (must be backlog|ready|in-progress|in-review|done)") ;;
esac

# Size is required for ready+ stages
if [[ "$STAGE" != "backlog" ]] && [ -z "$SIZE" ]; then
  errors+=("--size is required for stage '$STAGE' (must be xs|s|m|l|xl)")
fi

if [ -n "$SIZE" ]; then
  case "$SIZE" in
    xs|s|m|l|xl) ;;
    *) errors+=("Invalid --size: $SIZE (must be xs|s|m|l|xl)") ;;
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
STATUS_FIELD_ID=$(jq -r '.status_field_id' "$CONFIG")
PRIORITY_FIELD_ID=$(jq -r '.priority_field_id' "$CONFIG")
SIZE_FIELD_ID=$(jq -r '.size_field_id' "$CONFIG")

# Look up option IDs
STAGE_OPTION_ID=$(jq -r --arg s "$STAGE" '.stages[$s].option_id' "$CONFIG")
STAGE_LABEL=$(jq -r --arg s "$STAGE" '.stages[$s].label' "$CONFIG")
PRIORITY_OPTION_ID=$(jq -r --arg p "$PRIORITY" '.priorities[$p]' "$CONFIG")

if [ -n "$SIZE" ]; then
  SIZE_OPTION_ID=$(jq -r --arg s "$SIZE" '.sizes[$s]' "$CONFIG")
fi

# --- Append blocked-by references to body ---
FULL_BODY="$BODY"
for blocked in "${BLOCKED_BY[@]}"; do
  FULL_BODY="$FULL_BODY

Blocked by #$blocked"
done

# --- Build labels ---
LABELS="$STAGE_LABEL,$TYPE,priority:$PRIORITY"
if [ -n "$SIZE" ]; then
  LABELS="$LABELS,size:$SIZE"
fi

# --- Create the issue ---
echo "Creating issue: $TITLE" >&2

GH_STDERR=$(mktemp)
ISSUE_URL=$(gh issue create \
  --repo "$REPO" \
  --title "$TITLE" \
  --body "$FULL_BODY" \
  --label "$LABELS" 2>"$GH_STDERR") || {
  echo "ERROR: Failed to create issue:" >&2
  cat "$GH_STDERR" >&2
  rm -f "$GH_STDERR"
  exit 2
}
rm -f "$GH_STDERR"

# gh issue create outputs the issue URL to stdout
ISSUE_URL=$(echo "$ISSUE_URL" | tail -1)
ISSUE_NUMBER=$(echo "$ISSUE_URL" | grep -oP '/issues/\K[0-9]+')

echo "Created issue #$ISSUE_NUMBER: $ISSUE_URL" >&2

# --- Get the project item ID (and add to project explicitly) ---
ITEM_JSON=$(gh project item-add "$PROJECT_NUMBER" --owner "$OWNER" \
  --url "$ISSUE_URL" --format json 2>/dev/null) || {
  echo "ERROR: Failed to add issue to project board" >&2
  exit 2
}

ITEM_ID=$(echo "$ITEM_JSON" | jq -r '.id')

if [ -z "$ITEM_ID" ]; then
  echo "WARNING: Issue not found on project board. It may need to be added manually." >&2
else
  # --- Set board status ---
  gh project item-edit --id "$ITEM_ID" \
    --project-id "$PROJECT_ID" \
    --field-id "$STATUS_FIELD_ID" \
    --single-select-option-id "$STAGE_OPTION_ID" >/dev/null 2>&1 || {
    echo "WARNING: Failed to set board status" >&2
  }

  # --- Set priority ---
  gh project item-edit --id "$ITEM_ID" \
    --project-id "$PROJECT_ID" \
    --field-id "$PRIORITY_FIELD_ID" \
    --single-select-option-id "$PRIORITY_OPTION_ID" >/dev/null 2>&1 || {
    echo "WARNING: Failed to set priority" >&2
  }

  # --- Set size (if provided) ---
  if [ -n "$SIZE" ]; then
    gh project item-edit --id "$ITEM_ID" \
      --project-id "$PROJECT_ID" \
      --field-id "$SIZE_FIELD_ID" \
      --single-select-option-id "$SIZE_OPTION_ID" >/dev/null 2>&1 || {
      echo "WARNING: Failed to set size" >&2
    }
  fi

  echo "Board updated: status=$STAGE, priority=$PRIORITY${SIZE:+, size=$SIZE}" >&2
fi

# --- JSON output ---
jq -n \
  --argjson number "$ISSUE_NUMBER" \
  --arg url "$ISSUE_URL" \
  --arg stage "$STAGE" \
  --arg priority "$PRIORITY" \
  --arg size "${SIZE:-}" \
  --arg type "$TYPE" \
  '{number: $number, url: $url, stage: $stage, priority: $priority, size: $size, type: $type}'
