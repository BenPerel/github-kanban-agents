#!/usr/bin/env bash
set -euo pipefail

# Usage: exit-worktree.sh <keep|remove> [name]
# If 'name' is omitted, auto-detects from CWD.
# Prints the repo root to stdout. Agent should `cd` into it.

ACTION="${1:?Usage: exit-worktree.sh <keep|remove> [name]}"

# --- Auto-detect worktree name from CWD ---
if [[ -n "${2:-}" ]]; then
  NAME="$2"
else
  CWD="$(pwd)"
  if [[ "$CWD" == */.worktrees/* ]]; then
    NAME="${CWD#*/.worktrees/}"
    NAME="${NAME%%/*}"
  else
    echo "ERROR: Not inside a .worktrees/ directory and no name provided" >&2
    exit 1
  fi
fi

# --- Resolve to main repo root (handles being inside a worktree) ---
REPO_ROOT="$(git rev-parse --show-toplevel)"
if [[ -f "${REPO_ROOT}/.git" ]]; then
  REAL_GIT_DIR="$(sed 's/^gitdir: //' "${REPO_ROOT}/.git")"
  REPO_ROOT="$(cd "${REPO_ROOT}" && cd "$(dirname "$(dirname "$(dirname "${REAL_GIT_DIR}")")")" && pwd)"
fi

WORKTREE_PATH="${REPO_ROOT}/.worktrees/${NAME}"
BRANCH_NAME="${NAME//+//}"

case "${ACTION}" in
  keep)
    echo "Keeping worktree at: ${WORKTREE_PATH}" >&2
    echo "Branch '${BRANCH_NAME}' preserved for the PR." >&2
    echo "${REPO_ROOT}"
    ;;
  remove)
    # Safety: refuse if uncommitted changes exist
    if [[ -d "${WORKTREE_PATH}" ]]; then
      CHANGES=$(git -C "${WORKTREE_PATH}" status --porcelain 2>/dev/null | wc -l || echo "0")
      if [[ "${CHANGES}" -gt 0 ]]; then
        echo "ERROR: ${CHANGES} uncommitted changes in worktree." >&2
        echo "Commit, stash, or re-run with 'keep' instead." >&2
        git -C "${WORKTREE_PATH}" status --short >&2
        exit 1
      fi
    fi

    # Remove worktree
    git -C "${REPO_ROOT}" worktree remove --force "${WORKTREE_PATH}" 2>/dev/null || true

    # Sleep to let git release lock files (matches Claude Code behavior)
    sleep 0.1

    # Delete the branch
    git -C "${REPO_ROOT}" branch -D "${BRANCH_NAME}" 2>/dev/null || true

    # Prune stale worktree metadata
    git -C "${REPO_ROOT}" worktree prune 2>/dev/null || true

    echo "Removed worktree and branch '${BRANCH_NAME}'" >&2
    echo "${REPO_ROOT}"
    ;;
  *)
    echo "ERROR: action must be 'keep' or 'remove'" >&2
    exit 1
    ;;
esac
