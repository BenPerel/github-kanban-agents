#!/usr/bin/env bash
# Remove stale git worktrees after their PRs have been merged.
#
# Usage: cleanup-worktrees.sh [--dry-run]
#
# For dev worktrees (feat+N-*, fix+N-*, etc.): removes if the branch has
#   a merged PR (checked via gh pr list --state merged --head <branch>).
# For review worktrees (review+N): always removes — they are temporary
#   review checkouts with no associated open PR.
# Dirty worktrees (uncommitted changes) are always skipped with a warning.
#
# Exit codes:
#   0  Cleanup complete (or nothing to clean)
#   1  Usage error
#   2  git or GitHub API error

set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
elif [[ "${1:-}" == "--help" ]]; then
  sed -n '2,/^$/{ s/^# \?//; p }' "$0"
  exit 0
elif [[ -n "${1:-}" ]]; then
  echo "ERROR: Unknown option: $1" >&2
  echo "Usage: cleanup-worktrees.sh [--dry-run]" >&2
  exit 1
fi

# --- Resolve to main repo root (works from inside a worktree too) ---
REPO_ROOT="$(git rev-parse --show-toplevel)"
if [[ -f "${REPO_ROOT}/.git" ]]; then
  REAL_GIT_DIR="$(sed 's/^gitdir: //' "${REPO_ROOT}/.git")"
  REPO_ROOT="$(cd "${REPO_ROOT}" && cd "$(dirname "$(dirname "$(dirname "${REAL_GIT_DIR}")")")" && pwd)"
fi

# --- Fix compatibility with git libraries that reject extensions.relativeWorktrees ---
if git -C "${REPO_ROOT}" config --get extensions.relativeWorktrees &>/dev/null; then
  echo "WARNING: Detected extensions.relativeWorktrees — removing for embedded git library compatibility" >&2
  git -C "${REPO_ROOT}" config --unset extensions.relativeWorktrees 2>/dev/null || true
  FMT_VER=$(git -C "${REPO_ROOT}" config --get core.repositoryformatversion 2>/dev/null || echo "0")
  if [[ "$FMT_VER" == "1" ]]; then
    git -C "${REPO_ROOT}" config core.repositoryformatversion 0
    echo "WARNING: Reset core.repositoryformatversion from 1 to 0" >&2
  fi
fi

REPO_NAME="$(basename "${REPO_ROOT}")"
WORKTREE_DIR="$(dirname "${REPO_ROOT}")/${REPO_NAME}-worktrees"

if [[ ! -d "${WORKTREE_DIR}" ]]; then
  echo "No worktree directory at ${WORKTREE_DIR} — nothing to clean" >&2
  jq -n '{removed: 0, kept: 0, skipped: 0}'
  exit 0
fi

# --- Derive remote repo for gh pr queries ---
REMOTE_REPO=$(git -C "${REPO_ROOT}" remote get-url origin 2>/dev/null \
  | sed 's|.*github\.com[:/]||;s|\.git$||') || ""

if [[ -z "$REMOTE_REPO" ]]; then
  echo "ERROR: Cannot determine remote repo from origin URL" >&2
  exit 2
fi

# --- Enumerate worktrees ---
REMOVED=0
KEPT=0
SKIPPED=0

while IFS= read -r wt_line; do
  WT_PATH="${wt_line#worktree }"

  # Skip the main repo worktree
  [[ "$WT_PATH" == "$REPO_ROOT" ]] && continue

  # Only process worktrees in our managed directory
  [[ "$WT_PATH" == "${WORKTREE_DIR}/"* ]] || continue

  WT_NAME="$(basename "$WT_PATH")"
  BRANCH_NAME="${WT_NAME//+//}"

  # --- Determine if removable ---
  REMOVABLE=false

  if [[ "$WT_NAME" == review+* ]]; then
    REMOVABLE=true
    echo "  ${WT_NAME}: review worktree — removable" >&2
  else
    MERGED=$(gh pr list --state merged --head "$BRANCH_NAME" \
      --repo "$REMOTE_REPO" --json number --jq 'length' 2>/dev/null || echo "")

    if [[ -z "$MERGED" ]]; then
      echo "  ${WT_NAME}: could not check PR status — skipping" >&2
      SKIPPED=$((SKIPPED + 1))
      continue
    elif [[ "$MERGED" -gt 0 ]]; then
      REMOVABLE=true
      echo "  ${WT_NAME}: PR merged — removable" >&2
    else
      echo "  ${WT_NAME}: no merged PR — keeping" >&2
      KEPT=$((KEPT + 1))
      continue
    fi
  fi

  # --- Safety: skip dirty worktrees ---
  if [[ -d "$WT_PATH" ]]; then
    CHANGES=$(git -C "$WT_PATH" status --porcelain 2>/dev/null | wc -l || echo "0")
    if [[ "$CHANGES" -gt 0 ]]; then
      echo "  WARNING: ${WT_NAME} has ${CHANGES} uncommitted changes — skipping" >&2
      SKIPPED=$((SKIPPED + 1))
      continue
    fi
  fi

  # --- Remove ---
  if [[ "$REMOVABLE" == true ]]; then
    if [[ "$DRY_RUN" == true ]]; then
      echo "  DRY RUN: would remove ${WT_NAME} (branch: ${BRANCH_NAME})" >&2
      REMOVED=$((REMOVED + 1))
    else
      LOCKFILE="${WORKTREE_DIR}/.worktree.lock"
      (
        flock -w 30 9 || { echo "ERROR: Timed out waiting for worktree lock" >&2; exit 1; }
        git -C "${REPO_ROOT}" worktree remove --force "$WT_PATH" 2>/dev/null || true
        sleep 0.1
        git -C "${REPO_ROOT}" branch -D "$BRANCH_NAME" 2>/dev/null || true
      ) 9>"${LOCKFILE}"
      echo "  Removed ${WT_NAME}" >&2
      REMOVED=$((REMOVED + 1))
    fi
  fi

done < <(git -C "${REPO_ROOT}" worktree list --porcelain | grep '^worktree ')

# --- Final prune ---
if [[ "$DRY_RUN" == false ]]; then
  git -C "${REPO_ROOT}" worktree prune 2>/dev/null || true
fi

echo "Cleanup complete: ${REMOVED} removed, ${KEPT} kept, ${SKIPPED} skipped" >&2

jq -n \
  --argjson removed "$REMOVED" \
  --argjson kept "$KEPT" \
  --argjson skipped "$SKIPPED" \
  '{removed: $removed, kept: $kept, skipped: $skipped}'
