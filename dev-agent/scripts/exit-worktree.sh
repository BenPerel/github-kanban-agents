#!/usr/bin/env bash
set -euo pipefail

# Usage: exit-worktree.sh <keep|remove> [--dry-run] [name]
# If 'name' is omitted, auto-detects from CWD.
# Prints the repo root to stdout. Agent should `cd` into it.

ACTION="${1:?Usage: exit-worktree.sh <keep|remove> [--dry-run] [name]}"
shift

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  shift
fi

# --- Resolve to main repo root first (needed to derive WORKTREE_DIR) ---
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

# --- Auto-detect worktree name from CWD ---
if [[ -n "${1:-}" ]]; then
  NAME="$1"
else
  CWD="$(pwd)"
  if [[ "${CWD}" == "${WORKTREE_DIR}/"* ]]; then
    RELATIVE="${CWD#"${WORKTREE_DIR}/"}"
    NAME="${RELATIVE%%/*}"
  else
    echo "ERROR: Not inside a worktree directory and no name provided" >&2
    echo "  CWD:         ${CWD}" >&2
    echo "  Expected in: ${WORKTREE_DIR}/" >&2
    echo "  Try: cd \"\$(bash .agents/skills/dev-agent/scripts/exit-worktree.sh <keep|remove> \"<name>\")\"" >&2
    exit 1
  fi
fi

WORKTREE_PATH="${WORKTREE_DIR}/${NAME}"
BRANCH_NAME="${NAME//+//}"

case "${ACTION}" in
  keep)
    echo "Keeping worktree at: ${WORKTREE_PATH}" >&2
    echo "Branch '${BRANCH_NAME}' preserved for the PR." >&2
    echo "${REPO_ROOT}"
    ;;
  remove)
    if [ "$DRY_RUN" = true ]; then
      echo "DRY RUN: Would remove worktree at ${WORKTREE_PATH}" >&2
      echo "DRY RUN: Would delete branch '${BRANCH_NAME}'" >&2
      echo "${REPO_ROOT}"
      exit 0
    fi

    # Safety: refuse if uncommitted changes exist
    # Use -uno to ignore untracked files (e.g., symlinks from .worktreelinks)
    if [[ -d "${WORKTREE_PATH}" ]]; then
      CHANGES=$(git -C "${WORKTREE_PATH}" status --porcelain -uno 2>/dev/null | wc -l || echo "0")
      if [[ "${CHANGES}" -gt 0 ]]; then
        echo "ERROR: ${CHANGES} uncommitted changes in worktree." >&2
        echo "Commit, stash, or re-run with 'keep' instead." >&2
        git -C "${WORKTREE_PATH}" status --short >&2
        exit 1
      fi
    fi

    # Remove worktree (serialized via flock)
    LOCKFILE="${WORKTREE_DIR}/.worktree.lock"
    (
      flock -w 30 9 || { echo "ERROR: Timed out waiting for worktree lock" >&2; exit 1; }
      git -C "${REPO_ROOT}" worktree remove --force "${WORKTREE_PATH}" 2>/dev/null || true
      sleep 0.1
      git -C "${REPO_ROOT}" branch -D "${BRANCH_NAME}" 2>/dev/null || true
      git -C "${REPO_ROOT}" worktree prune 2>/dev/null || true
    ) 9>"${LOCKFILE}"

    echo "Removed worktree and branch '${BRANCH_NAME}'" >&2
    echo "${REPO_ROOT}"
    ;;
  *)
    echo "ERROR: action must be 'keep' or 'remove'" >&2
    exit 1
    ;;
esac
