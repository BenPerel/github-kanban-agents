#!/usr/bin/env bash
# Move an issue between kanban stages.
#
# Usage: move-issue.sh [OPTIONS]
#
# Options:
#   --issue NUMBER      Issue number (required)
#   --to STAGE          Target stage name (required)
#   --skip-pipeline-check "REASON"
#                       Skip CI check when moving to in-review
#   --config PATH       Path to .kanban-config.json (default: auto-detect)
#   --help              Show this help
#
# Exit codes:
#   0  Issue moved successfully
#   1  Invalid stage, WIP limit exceeded, or missing required labels
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
  echo "  move-issue.sh --issue 15 --to in-progress"
  echo "  move-issue.sh --issue 15 --to in-review"
  echo "  move-issue.sh --issue 15 --to done"
}

if [[ "${1:-}" == "--help" ]]; then
  show_help
  exit 0
fi

# --- Parse arguments ---
ISSUE=""
TO_STAGE=""
CONFIG_PATH=""
SKIP_PIPELINE_CHECK=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue)  ISSUE="$2"; shift 2 ;;
    --to)     TO_STAGE="$2"; shift 2 ;;
    --skip-pipeline-check) SKIP_PIPELINE_CHECK="$2"; shift 2 ;;
    --config) CONFIG_PATH="$2"; shift 2 ;;
    --help)   show_help; exit 0 ;;
    *)        echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
  esac
done

# --- Validate ---
errors=()
[ -z "$ISSUE" ] && errors+=("--issue is required")
[ -z "$TO_STAGE" ] && errors+=("--to is required")

VALID_STAGES="backlog ready in-progress human-review-mid in-review human-review-post done"
if [ -n "$TO_STAGE" ] && ! echo "$VALID_STAGES" | grep -qw "$TO_STAGE"; then
  errors+=("Invalid --to stage: $TO_STAGE (must be one of: $VALID_STAGES)")
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

TO_STAGE_LABEL=$(jq -r --arg s "$TO_STAGE" '.stages[$s].label' "$CONFIG")
TO_OPTION_ID=$(jq -r --arg s "$TO_STAGE" '.stages[$s].option_id' "$CONFIG")

# --- Detect current stage label ---
CURRENT_LABELS=$(gh issue view "$ISSUE" --repo "$REPO" --json labels --jq '.labels[].name' 2>&1) || {
  echo "ERROR: Failed to fetch issue #$ISSUE" >&2
  echo "$CURRENT_LABELS" >&2
  exit 2
}

FROM_STAGE_LABEL=""
for label in $CURRENT_LABELS; do
  if [[ "$label" == stage:* ]]; then
    FROM_STAGE_LABEL="$label"
    break
  fi
done

if [ -z "$FROM_STAGE_LABEL" ]; then
  echo "WARNING: Issue #$ISSUE has no stage label — will only add the target label" >&2
fi

# --- Check WIP limit ---
# Map stage name to the label used for counting
WIP_LABEL="$TO_STAGE_LABEL"

# Determine the WIP limit key (human-review stages don't have WIP limits)
WIP_KEY=""
case "$TO_STAGE" in
  backlog)     WIP_KEY="backlog" ;;
  in-progress) WIP_KEY="in-progress" ;;
  in-review)   WIP_KEY="in-review" ;;
esac

LIMIT=$(get_wip_limit "$WIP_KEY" "$CONFIG")
if [ -n "$WIP_KEY" ] && [ -n "$LIMIT" ]; then
  COUNT=$(gh issue list --repo "$REPO" --label "$WIP_LABEL" --state open --json number --jq 'length' 2>/dev/null || echo "0")

  if [ "$COUNT" -ge "$LIMIT" ]; then
    echo "ERROR: WIP limit exceeded for $TO_STAGE — $COUNT/$LIMIT items (limit: $LIMIT)" >&2
    exit 1
  fi
  echo "WIP check: $TO_STAGE has $COUNT/$LIMIT items" >&2
fi

# --- Check required labels for target stage ---
if [[ "$TO_STAGE" == "ready" || "$TO_STAGE" == "in-progress" || "$TO_STAGE" == "in-review" ]]; then
  HAS_SIZE=false
  for label in $CURRENT_LABELS; do
    if [[ "$label" == size:* ]]; then
      HAS_SIZE=true
      break
    fi
  done

  if [ "$HAS_SIZE" = false ]; then
    echo "ERROR: Issue #$ISSUE is missing a size label (required for $TO_STAGE)" >&2
    exit 1
  fi
fi

# --- CI gate (in-review transitions only) ---
if [[ "$TO_STAGE" == "in-review" ]] && [ -z "$SKIP_PIPELINE_CHECK" ]; then
  CI_ENABLED=$(jq -r '.pipeline.ci.enabled // false' "$CONFIG" 2>/dev/null)
  if [ "$CI_ENABLED" = "true" ]; then
    PR_NUMBER=$(gh pr list --repo "$REPO" --search "closes #${ISSUE}" --state open \
      --json number --jq '.[0].number' 2>/dev/null || echo "")

    if [ -z "$PR_NUMBER" ]; then
      echo "WARNING: No open PR found for issue #${ISSUE}. Skipping CI gate." >&2
    else
      FAILED=$(gh pr checks "$PR_NUMBER" --repo "$REPO" --json name,state \
        --jq '[.[] | select(.state != "SUCCESS" and .state != "SKIPPED")] | length' 2>/dev/null || echo "0")

      if [ "$FAILED" -gt 0 ]; then
        echo "WARNING: CI checks have not all passed for PR #${PR_NUMBER}." >&2
        gh pr checks "$PR_NUMBER" --repo "$REPO" --json name,state \
          --jq '[.[] | select(.state != "SUCCESS" and .state != "SKIPPED")] | .[].name' 2>/dev/null | \
          while read -r check_name; do echo "  - $check_name" >&2; done
        echo "" >&2
        echo "  Wait:  gh pr checks ${PR_NUMBER} --watch" >&2
        echo "  Skip:  --skip-pipeline-check \"reason\"" >&2
      fi
    fi
  fi
elif [[ "$TO_STAGE" == "in-review" ]] && [ -n "$SKIP_PIPELINE_CHECK" ]; then
  echo "CI gate skipped: $SKIP_PIPELINE_CHECK" >&2
fi

# --- Update label ---
LABEL_ARGS=()
if [ -n "$FROM_STAGE_LABEL" ] && [ "$FROM_STAGE_LABEL" != "$TO_STAGE_LABEL" ]; then
  LABEL_ARGS+=(--remove-label "$FROM_STAGE_LABEL")
fi
LABEL_ARGS+=(--add-label "$TO_STAGE_LABEL")

gh issue edit "$ISSUE" --repo "$REPO" "${LABEL_ARGS[@]}" >/dev/null 2>&1 || {
  echo "ERROR: Failed to update issue labels" >&2
  exit 2
}

echo "Labels updated: ${FROM_STAGE_LABEL:-none} → $TO_STAGE_LABEL" >&2

# --- Update board status ---
ITEM_ID=$(gh project item-list "$PROJECT_NUMBER" --owner "$OWNER" --format json \
  | jq -r --argjson num "$ISSUE" '.items[] | select(.content.number == $num) | .id') || {
  echo "ERROR: Failed to query project board items" >&2
  exit 2
}

if [ -z "$ITEM_ID" ]; then
  echo "ERROR: Issue #$ISSUE not found on project board — labels updated but board status unchanged" >&2
  exit 2
fi

gh project item-edit --id "$ITEM_ID" \
  --project-id "$PROJECT_ID" \
  --field-id "$STATUS_FIELD_ID" \
  --single-select-option-id "$TO_OPTION_ID" || {
  echo "ERROR: Failed to update board status for issue #$ISSUE" >&2
  exit 2
}
echo "Board updated: $TO_STAGE" >&2

# --- JSON output ---
jq -n \
  --argjson issue "$ISSUE" \
  --arg from "${FROM_STAGE_LABEL:-none}" \
  --arg to "$TO_STAGE_LABEL" \
  --arg stage "$TO_STAGE" \
  '{issue: $issue, from_label: $from, to_label: $to, stage: $stage}'
