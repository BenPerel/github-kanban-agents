#!/usr/bin/env bash
# Archive old Done items from the project board, keeping the N most recent.
#
# Usage: archive-done.sh [OPTIONS]
#
# Options:
#   --keep N            Number of Done items to keep (default: 10)
#   --dry-run           Show what would be archived without doing it
#   --config PATH       Path to .kanban-config.json (default: auto-detect)
#   --help              Show this help
#
# Exit codes:
#   0  Archival complete (or nothing to archive)
#   2  GitHub API error

set -euo pipefail

# --- Help ---
show_help() {
  sed -n '2,/^$/{ s/^# \?//; p }' "$0"
  echo ""
  echo "Examples:"
  echo "  archive-done.sh"
  echo "  archive-done.sh --keep 5"
  echo "  archive-done.sh --dry-run"
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
KEEP=10
DRY_RUN=false
CONFIG_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep)    KEEP="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --config)  CONFIG_PATH="$2"; shift 2 ;;
    --help)    show_help; exit 0 ;;
    *)         echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
  esac
done

# --- Read config ---
CONFIG=$(find_config)
PROJECT_NUMBER=$(jq -r '.project_number' "$CONFIG")
OWNER=$(jq -r '.owner' "$CONFIG")

# --- Get Done items, sorted by issue number descending ---
ITEMS_JSON=$(gh project item-list "$PROJECT_NUMBER" --owner "$OWNER" --format json 2>&1) || {
  echo "ERROR: Failed to list project items" >&2
  echo "$ITEMS_JSON" >&2
  exit 2
}

# Get IDs of Done items to archive (skip the N most recent)
ARCHIVE_IDS=$(echo "$ITEMS_JSON" | jq -r --argjson keep "$KEEP" \
  '[.items[] | select(.status == "Done" and .content.number != null)]
   | sort_by(-.content.number)
   | .[$keep:]
   | .[].id')

if [ -z "$ARCHIVE_IDS" ]; then
  echo "Nothing to archive — Done items are within the keep limit ($KEEP)" >&2
  jq -n --argjson keep "$KEEP" '{archived: 0, kept: $keep}'
  exit 0
fi

COUNT=$(echo "$ARCHIVE_IDS" | wc -l)

if [ "$DRY_RUN" = true ]; then
  echo "DRY RUN: Would archive $COUNT Done items (keeping $KEEP most recent)" >&2

  # Show what would be archived
  echo "$ITEMS_JSON" | jq -r --argjson keep "$KEEP" \
    '[.items[] | select(.status == "Done" and .content.number != null)]
     | sort_by(-.content.number)
     | .[$keep:]
     | .[] | "  #\(.content.number) — \(.content.title // "untitled")"'

  jq -n --argjson count "$COUNT" --argjson keep "$KEEP" \
    '{dry_run: true, would_archive: $count, kept: $keep}'
  exit 0
fi

echo "Archiving $COUNT Done items (keeping $KEEP most recent)..." >&2

ARCHIVED=0
FAILED=0
for ITEM_ID in $ARCHIVE_IDS; do
  if gh project item-archive "$PROJECT_NUMBER" --owner "$OWNER" --id "$ITEM_ID" >/dev/null 2>&1; then
    ARCHIVED=$((ARCHIVED + 1))
  else
    FAILED=$((FAILED + 1))
    echo "WARNING: Failed to archive item $ITEM_ID" >&2
  fi
done

echo "Archived $ARCHIVED items ($FAILED failed)" >&2

jq -n \
  --argjson archived "$ARCHIVED" \
  --argjson failed "$FAILED" \
  --argjson keep "$KEEP" \
  '{archived: $archived, failed: $failed, kept: $keep}'
