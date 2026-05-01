#!/usr/bin/env bash
# Setup script for github-kanban skill.
# Run this from the root of your target repository.
#
# Usage:
#   bash path/to/setup.sh <PROJECT_NUMBER> <OWNER>
#
# What this script does:
#   1. Checks prerequisites (gh CLI, jq, authentication)
#   2. Fetches your project field IDs and option IDs via GitHub API
#   3. Generates a project-specific SKILL.md with all IDs filled in
#   4. Installs it to .claude/skills/github-kanban.md (and/or .gemini/skills/)
#   5. Creates required labels if they don't exist (idempotent)
#   6. Optionally copies GitHub Actions workflow templates
#
# This script is idempotent — safe to re-run. It will overwrite the
# generated SKILL.md but will not delete existing labels, workflows,
# or project board configuration.

set -euo pipefail

# --- Help ---
if [[ "${1:-}" == "--help" ]]; then
  cat <<'HELP'
Usage: setup.sh <PROJECT_NUMBER|new> [BOARD_NAME] <OWNER>

Arguments:
  PROJECT_NUMBER   Existing project board number, or "new" to create one
  BOARD_NAME       Name for the new board (required when using "new")
  OWNER            GitHub user or organization that owns the project

Examples:
  setup.sh new "My Kanban Board" myorg
  setup.sh 42 myorg

Prerequisites: gh (GitHub CLI), jq, git
HELP
  exit 0
fi

# --- Pre-flight checks ---
echo "=== Pre-flight Checks ==="

if ! command -v gh &>/dev/null; then
  echo "ERROR: gh CLI is not installed."
  echo "Install it from: https://cli.github.com/"
  exit 1
fi
echo "✓ gh CLI found"

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is not installed."
  echo "Install it from: https://jqlang.github.io/jq/download/"
  exit 1
fi
echo "✓ jq found"

if ! gh auth status &>/dev/null; then
  echo "ERROR: gh CLI is not authenticated."
  echo "Run: gh auth login"
  exit 1
fi
echo "✓ gh CLI authenticated"

if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  echo "ERROR: Not inside a git repository."
  echo "Run this script from the root of your target repository."
  exit 1
fi
echo "✓ Inside a git repository"

echo ""

if [ $# -lt 2 ]; then
  echo "Usage: $0 <PROJECT_IDENTIFIER> <OWNER>"
  echo "  PROJECT_IDENTIFIER: Use 'new \"My Project\"' to clone the official template, or provide an existing project number."
  echo "  OWNER: GitHub username or org that owns the project"
  echo ""
  echo "Examples:"
  echo "  $0 new \"My Awesome Board\" BenPerel"
  echo "  $0 4 BenPerel"
  exit 1
fi

if [ "$1" = "new" ]; then
  if [ $# -lt 3 ]; then
    echo "ERROR: When using 'new', you must provide a title and owner."
    echo "Usage: $0 new \"Project Title\" <OWNER>"
    exit 1
  fi
  TITLE="$2"
  OWNER="$3"
  TEMPLATE_OWNER="BenPerel"
  TEMPLATE_NUMBER="3"
  
  echo "=== Cloning Official Kanban Template ==="
  echo "Cloning from $TEMPLATE_OWNER/#$TEMPLATE_NUMBER to $OWNER..."
  PROJECT_JSON=$(gh project copy "$TEMPLATE_NUMBER" \
    --source-owner "$TEMPLATE_OWNER" \
    --target-owner "$OWNER" \
    --title "$TITLE" \
    --format json) || {
    echo "ERROR: Failed to clone template project. Ensure you have the 'project' scope in gh auth."
    exit 2
  }
  
  PROJECT_NUMBER=$(echo "$PROJECT_JSON" | jq -r '.number')
  echo "✓ Successfully created Project #$PROJECT_NUMBER: \"$TITLE\""
  echo ""
else
  PROJECT_NUMBER="$1"
  OWNER="$2"
fi

# --- Link project to repository ---
REPO_FOR_LINK=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || true)
if [ -n "$REPO_FOR_LINK" ]; then
  echo ""
  echo "--- Linking Project to Repository ---"
  gh project link "$PROJECT_NUMBER" --owner "$OWNER" --repo "$REPO_FOR_LINK" 2>/dev/null \
    && echo "✓ Linked project #$PROJECT_NUMBER to $REPO_FOR_LINK" \
    || echo "⚠ Could not link project to repo (may already be linked or need manual linking)"
fi

REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
PROJECT_NAME=$(gh project view "$PROJECT_NUMBER" --owner "$OWNER" --format json | jq -r '.title')

echo "=== GitHub Kanban Setup ==="
echo "Repo:    $REPO"
echo "Project: \"$PROJECT_NAME\" (#$PROJECT_NUMBER, owner: $OWNER)"
echo ""

# --- Resolve the SKILL.md template ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$(cd "$SCRIPT_DIR/.." && pwd)/SKILL.md"

if [ ! -f "$TEMPLATE" ]; then
  echo "ERROR: SKILL.md template not found at $TEMPLATE"
  exit 1
fi
echo "✓ Template found: $TEMPLATE"

# --- Fetch project IDs ---
echo ""
echo "--- Fetching Project IDs ---"

PROJECT_ID=$(gh project view "$PROJECT_NUMBER" --owner "$OWNER" --format json | jq -r '.id')
echo "Project ID: $PROJECT_ID"

FIELDS=$(gh project field-list "$PROJECT_NUMBER" --owner "$OWNER" --format json)

# Extract field IDs
STATUS_FIELD_ID=$(echo "$FIELDS" | jq -r '.fields[] | select(.name == "Status") | .id')
PRIORITY_FIELD_ID=$(echo "$FIELDS" | jq -r '.fields[] | select(.name == "Priority") | .id')
SIZE_FIELD_ID=$(echo "$FIELDS" | jq -r '.fields[] | select(.name == "Size") | .id')

echo "Status field:   $STATUS_FIELD_ID"
echo "Priority field: $PRIORITY_FIELD_ID"
echo "Size field:     $SIZE_FIELD_ID"

# Extract status option IDs
get_option_id() {
  local field_name="$1"
  local option_name="$2"
  echo "$FIELDS" | jq -r --arg field "$field_name" --arg opt "$option_name" \
    '.fields[] | select(.name == $field) | .options[] | select(.name == $opt) | .id'
}

BACKLOG_OPTION_ID=$(get_option_id "Status" "Backlog")
READY_OPTION_ID=$(get_option_id "Status" "Ready")
IN_PROGRESS_OPTION_ID=$(get_option_id "Status" "In progress")
IN_REVIEW_OPTION_ID=$(get_option_id "Status" "In review")
DONE_OPTION_ID=$(get_option_id "Status" "Done")

# Human Review has two columns — mid-dev and post-review
# They share the same label but have different board option IDs.
# We need both IDs. The project should have two "Human Review" options
# or variations like "Human Review (mid-dev)" and "Human Review (post-review)".
HUMAN_REVIEW_IDS=$(echo "$FIELDS" | jq -r '.fields[] | select(.name == "Status") | .options[] | select(.name | test("Human Review"; "i")) | .id')
HUMAN_REVIEW_COUNT=$(echo "$HUMAN_REVIEW_IDS" | wc -l)

if [ "$HUMAN_REVIEW_COUNT" -ge 2 ]; then
  HUMAN_REVIEW_MID_DEV_OPTION_ID=$(echo "$HUMAN_REVIEW_IDS" | sed -n '1p')
  HUMAN_REVIEW_POST_REVIEW_OPTION_ID=$(echo "$HUMAN_REVIEW_IDS" | sed -n '2p')
elif [ "$HUMAN_REVIEW_COUNT" -eq 1 ]; then
  HUMAN_REVIEW_MID_DEV_OPTION_ID=$(echo "$HUMAN_REVIEW_IDS" | head -1)
  HUMAN_REVIEW_POST_REVIEW_OPTION_ID="$HUMAN_REVIEW_MID_DEV_OPTION_ID"
  echo "WARNING: Only one Human Review option found. Using same ID for both mid-dev and post-review."
else
  HUMAN_REVIEW_MID_DEV_OPTION_ID="MISSING"
  HUMAN_REVIEW_POST_REVIEW_OPTION_ID="MISSING"
  echo "WARNING: No Human Review options found. You'll need to create them in your project board."
fi

# Priority option IDs
P0_OPTION_ID=$(get_option_id "Priority" "P0")
P1_OPTION_ID=$(get_option_id "Priority" "P1")
P2_OPTION_ID=$(get_option_id "Priority" "P2")

# Size option IDs
XS_OPTION_ID=$(get_option_id "Size" "XS")
S_OPTION_ID=$(get_option_id "Size" "S")
M_OPTION_ID=$(get_option_id "Size" "M")
L_OPTION_ID=$(get_option_id "Size" "L")
XL_OPTION_ID=$(get_option_id "Size" "XL")

echo ""
echo "--- Status Options ---"
echo "  Backlog:                    $BACKLOG_OPTION_ID"
echo "  Ready:                      $READY_OPTION_ID"
echo "  In progress:                $IN_PROGRESS_OPTION_ID"
echo "  Human Review (mid-dev):     $HUMAN_REVIEW_MID_DEV_OPTION_ID"
echo "  In review:                  $IN_REVIEW_OPTION_ID"
echo "  Human Review (post-review): $HUMAN_REVIEW_POST_REVIEW_OPTION_ID"
echo "  Done:                       $DONE_OPTION_ID"
echo ""
echo "--- Priority Options ---"
echo "  P0: $P0_OPTION_ID"
echo "  P1: $P1_OPTION_ID"
echo "  P2: $P2_OPTION_ID"
echo ""
echo "--- Size Options ---"
echo "  XS: $XS_OPTION_ID  S: $S_OPTION_ID  M: $M_OPTION_ID  L: $L_OPTION_ID  XL: $XL_OPTION_ID"

# --- Generate SKILL.md with IDs injected ---
echo ""
echo "--- Generating SKILL.md ---"

OUTPUT_DIR_CLAUDE=".claude/skills"
OUTPUT_DIR_GEMINI=".gemini/skills"
OUTPUT_DIR_AGENTS=".agents/skills/github-kanban"
OUTPUT_FILE_CLAUDE="$OUTPUT_DIR_CLAUDE/github-kanban.md"
OUTPUT_FILE_GEMINI="$OUTPUT_DIR_GEMINI/github-kanban.md"
OUTPUT_FILE_AGENTS="$OUTPUT_DIR_AGENTS/SKILL.md"
mkdir -p "$OUTPUT_DIR_AGENTS"

# Generate the canonical SKILL.md in the agents directory
# Write to a temp file first to avoid clobbering when $TEMPLATE and
# $OUTPUT_FILE_AGENTS resolve to the same path (e.g. npx install puts
# the template at .agents/skills/github-kanban/SKILL.md).
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT
sed \
  -e "s|<REPO>|$REPO|g" \
  -e "s|<PROJECT_NAME>|$PROJECT_NAME|g" \
  -e "s|<PROJECT_NUMBER>|$PROJECT_NUMBER|g" \
  -e "s|<OWNER>|$OWNER|g" \
  -e "s|<PROJECT_ID>|$PROJECT_ID|g" \
  -e "s|<STATUS_FIELD_ID>|$STATUS_FIELD_ID|g" \
  -e "s|<PRIORITY_FIELD_ID>|$PRIORITY_FIELD_ID|g" \
  -e "s|<SIZE_FIELD_ID>|$SIZE_FIELD_ID|g" \
  -e "s|<BACKLOG_OPTION_ID>|$BACKLOG_OPTION_ID|g" \
  -e "s|<READY_OPTION_ID>|$READY_OPTION_ID|g" \
  -e "s|<IN_PROGRESS_OPTION_ID>|$IN_PROGRESS_OPTION_ID|g" \
  -e "s|<HUMAN_REVIEW_MID_DEV_OPTION_ID>|$HUMAN_REVIEW_MID_DEV_OPTION_ID|g" \
  -e "s|<IN_REVIEW_OPTION_ID>|$IN_REVIEW_OPTION_ID|g" \
  -e "s|<HUMAN_REVIEW_POST_REVIEW_OPTION_ID>|$HUMAN_REVIEW_POST_REVIEW_OPTION_ID|g" \
  -e "s|<DONE_OPTION_ID>|$DONE_OPTION_ID|g" \
  -e "s|<P0_OPTION_ID>|$P0_OPTION_ID|g" \
  -e "s|<P1_OPTION_ID>|$P1_OPTION_ID|g" \
  -e "s|<P2_OPTION_ID>|$P2_OPTION_ID|g" \
  -e "s|<XS_OPTION_ID>|$XS_OPTION_ID|g" \
  -e "s|<S_OPTION_ID>|$S_OPTION_ID|g" \
  -e "s|<M_OPTION_ID>|$M_OPTION_ID|g" \
  -e "s|<L_OPTION_ID>|$L_OPTION_ID|g" \
  -e "s|<XL_OPTION_ID>|$XL_OPTION_ID|g" \
  "$TEMPLATE" > "$TMPFILE"
mv "$TMPFILE" "$OUTPUT_FILE_AGENTS"

# Copy to Claude skills — skip if npx skills already created a symlink
# (the symlink points to .agents/skills/github-kanban/ which we already updated)
CLAUDE_SYMLINK_PATH=".claude/skills/github-kanban"
if [[ -L "$CLAUDE_SYMLINK_PATH" ]]; then
  echo "✓ Claude skill symlink exists — skipping .md file (symlink resolves to updated SKILL.md)"
else
  mkdir -p "$OUTPUT_DIR_CLAUDE"
  cp "$OUTPUT_FILE_AGENTS" "$OUTPUT_FILE_CLAUDE"
  echo "✓ Generated: $OUTPUT_FILE_CLAUDE"
fi

# Copy to Gemini skills directory
mkdir -p "$OUTPUT_DIR_GEMINI"
cp "$OUTPUT_FILE_AGENTS" "$OUTPUT_FILE_GEMINI"

echo "✓ Generated: $OUTPUT_FILE_AGENTS and $OUTPUT_FILE_GEMINI"

# Check for any remaining real template placeholders
# Only match config placeholders (ALL_CAPS_WITH_UNDERSCORES), not documentation examples like <NUMBER> or <PR>
REMAINING=$(grep -oP '<[A-Z][A-Z_]{3,}_[A-Z]+>' "$OUTPUT_FILE_AGENTS" 2>/dev/null | wc -l || true)
if [ "$REMAINING" -gt 0 ]; then
  echo "WARNING: $REMAINING unfilled placeholders remain. Check the output file."
  grep -nP '<[A-Z][A-Z_]{3,}_[A-Z]+>' "$OUTPUT_FILE_AGENTS" || true
fi

# --- Generate .kanban-config.json ---
echo ""
echo "--- Generating .kanban-config.json ---"

CONFIG_FILE=".kanban-config.json"
jq -n \
  --arg repo "$REPO" \
  --argjson project_number "$PROJECT_NUMBER" \
  --arg owner "$OWNER" \
  --arg project_id "$PROJECT_ID" \
  --arg status_field_id "$STATUS_FIELD_ID" \
  --arg priority_field_id "$PRIORITY_FIELD_ID" \
  --arg size_field_id "$SIZE_FIELD_ID" \
  --arg backlog_id "$BACKLOG_OPTION_ID" \
  --arg ready_id "$READY_OPTION_ID" \
  --arg in_progress_id "$IN_PROGRESS_OPTION_ID" \
  --arg human_review_mid_id "$HUMAN_REVIEW_MID_DEV_OPTION_ID" \
  --arg in_review_id "$IN_REVIEW_OPTION_ID" \
  --arg human_review_post_id "$HUMAN_REVIEW_POST_REVIEW_OPTION_ID" \
  --arg done_id "$DONE_OPTION_ID" \
  --arg p0_id "$P0_OPTION_ID" \
  --arg p1_id "$P1_OPTION_ID" \
  --arg p2_id "$P2_OPTION_ID" \
  --arg xs_id "$XS_OPTION_ID" \
  --arg s_id "$S_OPTION_ID" \
  --arg m_id "$M_OPTION_ID" \
  --arg l_id "$L_OPTION_ID" \
  --arg xl_id "$XL_OPTION_ID" \
  '{
    repo: $repo,
    project_number: $project_number,
    owner: $owner,
    project_id: $project_id,
    status_field_id: $status_field_id,
    priority_field_id: $priority_field_id,
    size_field_id: $size_field_id,
    stages: {
      backlog:            { label: "stage:backlog",       option_id: $backlog_id },
      ready:              { label: "stage:ready",         option_id: $ready_id },
      "in-progress":      { label: "stage:in-progress",   option_id: $in_progress_id },
      "human-review-mid": { label: "stage:human-review",  option_id: $human_review_mid_id },
      "in-review":        { label: "stage:in-review",     option_id: $in_review_id },
      "human-review-post":{ label: "stage:human-review",  option_id: $human_review_post_id },
      done:               { label: "stage:done",          option_id: $done_id }
    },
    priorities: {
      p0: $p0_id,
      p1: $p1_id,
      p2: $p2_id
    },
    sizes: {
      xs: $xs_id,
      s: $s_id,
      m: $m_id,
      l: $l_id,
      xl: $xl_id
    },
    wip_limits: {
      backlog: 10,
      "in-progress": 3,
      "in-review": 5
    }
  }' > "$CONFIG_FILE"

echo "✓ Generated: $CONFIG_FILE"

# --- Pipeline Configuration (optional) ---
if [ -t 0 ]; then
  echo ""
  echo "--- Pipeline Configuration (optional) ---"

  read -rp "Enable CI gate on move to in-review? [Y/n] " ci_choice
  if [[ "${ci_choice:-Y}" =~ ^[Yy] ]]; then
    CI_ENABLED=true
  else
    CI_ENABLED=false
  fi

  CD_ENABLED=false
  CD_VERIFY_CMD=""
  CD_SUCCESS=""
  CD_PENDING=""
  CD_TIMEOUT=15
  read -rp "Enable CD verification after merge? [y/N] " cd_choice
  if [[ "${cd_choice:-N}" =~ ^[Yy] ]]; then
    CD_ENABLED=true
    read -rp "  Verify command (e.g., gcloud builds list ... --format='value(status)'): " CD_VERIFY_CMD
    read -rp "  Success value (e.g., SUCCESS): " CD_SUCCESS
    read -rp "  Pending values, comma-separated (e.g., WORKING,QUEUED): " CD_PENDING_RAW
    CD_PENDING=$(echo "$CD_PENDING_RAW" | jq -R 'split(",") | map(gsub("^\\s+|\\s+$";""))' 2>/dev/null || echo '[]')
    read -rp "  Timeout minutes [15]: " CD_TIMEOUT_INPUT
    CD_TIMEOUT="${CD_TIMEOUT_INPUT:-15}"
  fi

  # Add pipeline config to the generated config file
  jq --argjson ci_enabled "$CI_ENABLED" \
     --argjson cd_enabled "$CD_ENABLED" \
     --arg cd_cmd "${CD_VERIFY_CMD:-}" \
     --arg cd_success "${CD_SUCCESS:-}" \
     --argjson cd_pending "${CD_PENDING:-[]}" \
     --argjson cd_timeout "$CD_TIMEOUT" \
     '. + {pipeline: {
        ci: {enabled: $ci_enabled},
        cd: {enabled: $cd_enabled, verify_command: $cd_cmd, success_value: $cd_success, pending_values: $cd_pending, timeout_minutes: $cd_timeout}
      }}' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"

  echo "✓ Pipeline config added to $CONFIG_FILE"
fi

# --- Create labels (idempotent — --force updates if exists) ---
echo ""
echo "--- Creating Labels ---"

# Stage labels
for LABEL in "stage:backlog" "stage:ready" "stage:in-progress" "stage:human-review" "stage:in-review" "stage:done"; do
  gh label create "$LABEL" --repo "$REPO" --color "0E8A16" --force 2>/dev/null \
    && echo "  ✓ $LABEL" \
    || echo "  ✓ $LABEL (exists)"
done

# Priority labels
gh label create "priority:p0" --repo "$REPO" --color "B60205" --description "Critical" --force 2>/dev/null && echo "  ✓ priority:p0" || echo "  ✓ priority:p0 (exists)"
gh label create "priority:p1" --repo "$REPO" --color "D93F0B" --description "High" --force 2>/dev/null && echo "  ✓ priority:p1" || echo "  ✓ priority:p1 (exists)"
gh label create "priority:p2" --repo "$REPO" --color "FBCA04" --description "Normal" --force 2>/dev/null && echo "  ✓ priority:p2" || echo "  ✓ priority:p2 (exists)"

# Size labels
for SIZE in "size:xs" "size:s" "size:m" "size:l" "size:xl"; do
  gh label create "$SIZE" --repo "$REPO" --color "C5DEF5" --force 2>/dev/null \
    && echo "  ✓ $SIZE" \
    || echo "  ✓ $SIZE (exists)"
done

# Type labels
gh label create "bug" --repo "$REPO" --color "D73A4A" --force 2>/dev/null && echo "  ✓ bug" || echo "  ✓ bug (exists)"
gh label create "enhancement" --repo "$REPO" --color "A2EEEF" --force 2>/dev/null && echo "  ✓ enhancement" || echo "  ✓ enhancement (exists)"
gh label create "documentation" --repo "$REPO" --color "0075CA" --force 2>/dev/null && echo "  ✓ documentation" || echo "  ✓ documentation (exists)"
gh label create "duplicate" --repo "$REPO" --color "CFD3D7" --force 2>/dev/null && echo "  ✓ duplicate" || echo "  ✓ duplicate (exists)"

# --- Install GitHub Actions workflows ---
echo ""
echo "--- GitHub Actions Workflows ---"

TEMPLATES_DIR="$(cd "$SCRIPT_DIR/../templates" 2>/dev/null && pwd)" || TEMPLATES_DIR=""

if [ -n "$TEMPLATES_DIR" ] && [ -d "$TEMPLATES_DIR" ]; then
  if [ -f ".github/workflows/auto-in-review.yml" ] && [ -f ".github/workflows/wip-limit-check.yml" ]; then
    echo "Workflow files already exist in .github/workflows/ — skipping."
    echo "To update, delete them and re-run this script."
  else
    if [ -t 0 ]; then
      read -rp "Install GitHub Actions workflows into .github/workflows/? [y/N] " INSTALL_WORKFLOWS
    else
      echo "Non-interactive mode detected — skipping workflow installation."
      INSTALL_WORKFLOWS="N"
    fi
    if [[ "$INSTALL_WORKFLOWS" =~ ^[Yy]$ ]]; then
      mkdir -p .github/workflows

      # Copy and fill placeholders in auto-in-review.yml
      sed \
        -e "s|<PROJECT_NUMBER>|$PROJECT_NUMBER|g" \
        -e "s|<OWNER>|$OWNER|g" \
        -e "s|<STATUS_FIELD_ID>|$STATUS_FIELD_ID|g" \
        -e "s|<IN_REVIEW_OPTION_ID>|$IN_REVIEW_OPTION_ID|g" \
        -e "s|<PROJECT_ID>|$PROJECT_ID|g" \
        "$TEMPLATES_DIR/auto-in-review.yml" > .github/workflows/auto-in-review.yml

      # Copy and fill placeholders in wip-limit-check.yml
      sed \
        -e "s|<PROJECT_NUMBER>|$PROJECT_NUMBER|g" \
        -e "s|<OWNER>|$OWNER|g" \
        "$TEMPLATES_DIR/wip-limit-check.yml" > .github/workflows/wip-limit-check.yml

      echo "✓ Generated workflow files in .github/workflows/ (placeholders filled)"

      # Check for unfilled placeholders in workflows
      WF_REMAINING=$(cat .github/workflows/auto-in-review.yml .github/workflows/wip-limit-check.yml 2>/dev/null | grep -oP '<[A-Z][A-Z_]{3,}_[A-Z]+>' | wc -l || true)
      if [ "$WF_REMAINING" -gt 0 ]; then
        echo "WARNING: Some workflow placeholders could not be filled:"
        cat .github/workflows/auto-in-review.yml .github/workflows/wip-limit-check.yml 2>/dev/null | grep -nP '<[A-Z][A-Z_]{3,}_[A-Z]+>' || true
      fi

      # Inject a note into the generated skill markdown
      if [ -f "$OUTPUT_FILE_AGENTS" ]; then
        cat >> "$OUTPUT_FILE_AGENTS" << 'SKILL_NOTE'

## Installed Workflows

The following GitHub Actions workflows are installed in this repo:

- **auto-in-review.yml** — automatically moves linked issues to `stage:in-review`
  when a PR is opened with `Closes #N`. Agents do NOT need to manually move
  issues to in-review after creating a PR — the workflow handles it.
- **wip-limit-check.yml** — fails the check when WIP limits are exceeded.
SKILL_NOTE
        # Copy the updated file to Gemini and Claude (if not symlinked)
        cp "$OUTPUT_FILE_AGENTS" "$OUTPUT_FILE_GEMINI"
        if [[ ! -L "$CLAUDE_SYMLINK_PATH" ]]; then
          cp "$OUTPUT_FILE_AGENTS" "$OUTPUT_FILE_CLAUDE"
        fi
        echo "✓ Added workflow note to generated skill files"
      fi

      echo ""
      echo "  You need a PAT (classic) with repo + project scopes:"
      echo "    1. Create at: https://github.com/settings/tokens"
      echo "    2. Add as secret: gh secret set PROJECT_PAT --repo $REPO"
    else
      echo "Skipped."
    fi
  fi
else
  echo "Template files not found. Skipping workflow installation."
fi

echo ""
echo "--- Built-in Project Automations ---"
echo "GitHub Projects v2 has built-in automations that cannot be toggled via gh CLI."
echo "Enable these manually in your project settings:"
echo ""
echo "  1. Go to: https://github.com/users/$OWNER/projects/$PROJECT_NUMBER/settings"
echo "     (or https://github.com/orgs/$OWNER/projects/$PROJECT_NUMBER/settings for orgs)"
echo "  2. Click 'Workflows' in the sidebar"
echo "  3. Enable these workflows:"
echo "     - 'Item closed' → Set status to 'Done'"
echo "     - 'Pull request merged' → Set status to 'Done'"
echo "     - (Optional) 'Item reopened' → Set status to 'In progress'"

echo ""
echo "=== Setup Complete ==="
echo "Skill installed to: $OUTPUT_FILE_AGENTS and $OUTPUT_FILE_GEMINI"
echo "Config generated: $CONFIG_FILE"
echo "Re-run this script at any time to regenerate with latest template."
