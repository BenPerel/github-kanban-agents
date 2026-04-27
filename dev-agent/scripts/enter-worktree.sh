#!/usr/bin/env bash
set -euo pipefail

# Usage: enter-worktree.sh <name>
# Creates a git worktree for multi-agent isolated development.
# Prints the worktree path to stdout. Agent should `cd` into it.
#
# Naming: use + as separator — becomes / in the branch name.
# Example: enter-worktree.sh feat+42-add-auth
#   → ../repo-name-worktrees/feat+42-add-auth (branch: feat/42-add-auth)

NAME="${1:?Usage: enter-worktree.sh <name>}"

# --- Validate name (prevent path traversal and unsafe characters) ---
if [[ "$NAME" == *..* ]] || [[ "$NAME" == /* ]] || [[ "$NAME" == *\\* ]]; then
  echo "ERROR: Invalid worktree name '${NAME}': must not contain '..', start with '/', or contain '\\'" >&2
  exit 1
fi
if [[ ${#NAME} -gt 64 ]]; then
  echo "ERROR: Worktree name too long (${#NAME} chars, max 64)" >&2
  exit 1
fi

# --- Resolve to MAIN repo root (critical for nested worktree safety) ---
# If we're already inside a worktree, git rev-parse --show-toplevel returns
# the worktree root, not the main repo. Detect this via the .git file pointer.
REPO_ROOT="$(git rev-parse --show-toplevel)"
if [[ -f "${REPO_ROOT}/.git" ]]; then
  # Inside a worktree — .git is a file (not a dir) pointing to the real git dir
  # Format: "gitdir: /path/to/main-repo/.git/worktrees/<name>"
  REAL_GIT_DIR="$(sed 's/^gitdir: //' "${REPO_ROOT}/.git")"
  # Navigate up from .git/worktrees/<name> → .git → repo root
  REPO_ROOT="$(cd "${REPO_ROOT}" && cd "$(dirname "$(dirname "$(dirname "${REAL_GIT_DIR}")")")" && pwd)"
fi

# --- Fix Antigravity/go-git incompatibility with Git 2.48+ relative worktrees ---
# go-git does not support extensions.relativeWorktrees and rejects
# repositoryformatversion=1 when this extension is present. Auto-downgrade
# to keep worktrees working under Antigravity.
if git -C "${REPO_ROOT}" config --get extensions.relativeWorktrees &>/dev/null; then
  echo "WARNING: Detected extensions.relativeWorktrees — removing for go-git compatibility" >&2
  git -C "${REPO_ROOT}" config --unset extensions.relativeWorktrees 2>/dev/null || true
  FMT_VER=$(git -C "${REPO_ROOT}" config --get core.repositoryformatversion 2>/dev/null || echo "0")
  if [[ "$FMT_VER" == "1" ]]; then
    git -C "${REPO_ROOT}" config core.repositoryformatversion 0
    echo "WARNING: Reset core.repositoryformatversion from 1 to 0" >&2
  fi
fi

REPO_NAME="$(basename "${REPO_ROOT}")"
WORKTREE_DIR="$(dirname "${REPO_ROOT}")/${REPO_NAME}-worktrees"
WORKTREE_PATH="${WORKTREE_DIR}/${NAME}"
BRANCH_NAME="${NAME//+//}"

# --- Resume existing worktree ---
if [[ -d "${WORKTREE_PATH}" ]]; then
  echo "Resuming existing worktree at: ${WORKTREE_PATH}" >&2
  echo "${WORKTREE_PATH}"
  exit 0
fi

# --- Clean stale worktree metadata before creating ---
git -C "${REPO_ROOT}" worktree prune 2>/dev/null || true

mkdir -p "${WORKTREE_DIR}"

# --- Determine the main branch ref ---
# Fetch latest and resolve origin's default branch for the worktree base.
# This ensures new branches always fork from the main integration branch,
# not from whatever HEAD happens to be checked out (which may be a stale
# feature branch — causing gh pr create to infer the wrong base).
git -C "${REPO_ROOT}" fetch origin 2>/dev/null || true
DEFAULT_BRANCH="$(git -C "${REPO_ROOT}" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/||')" || true
if [[ -z "${DEFAULT_BRANCH}" ]]; then
  # origin/HEAD not set (common after manual clone). Try common names.
  for candidate in origin/main origin/master; do
    if git -C "${REPO_ROOT}" rev-parse --verify "${candidate}" >/dev/null 2>&1; then
      DEFAULT_BRANCH="${candidate}"
      break
    fi
  done
fi
if [[ -z "${DEFAULT_BRANCH}" ]]; then
  echo "ERROR: Cannot determine default branch. Run 'git remote set-head origin -a' or ensure origin/main exists." >&2
  exit 1
fi

# --- Create worktree (serialized via flock) ---
# -B: create-or-reset branch (handles orphans from prior force-removes)
LOCKFILE="${WORKTREE_DIR}/.worktree.lock"
(
  flock -w 30 9 || { echo "ERROR: Timed out waiting for worktree lock" >&2; exit 1; }
  git -C "${REPO_ROOT}" worktree add -B "${BRANCH_NAME}" "${WORKTREE_PATH}" "${DEFAULT_BRANCH}" >&2
) 9>"${LOCKFILE}"

# --- Post-creation: copy .worktreeinclude files ---
# .worktreeinclude lists gitignored files that should be copied to worktrees
# (e.g., .env, config/secrets/local.yaml). Uses .gitignore syntax.
if [[ -f "${REPO_ROOT}/.worktreeinclude" ]]; then
  while IFS= read -r pattern || [[ -n "$pattern" ]]; do
    [[ -z "$pattern" || "$pattern" == \#* ]] && continue
    while IFS= read -r file; do
      [[ -z "$file" ]] && continue
      dest="${WORKTREE_PATH}/${file}"
      mkdir -p "$(dirname "$dest")"
      cp "${REPO_ROOT}/${file}" "$dest" 2>/dev/null || true
    done < <(cd "${REPO_ROOT}" && git ls-files --others --ignored --exclude-standard -- "$pattern" 2>/dev/null)
  done < "${REPO_ROOT}/.worktreeinclude"
  echo "Copied .worktreeinclude files" >&2
fi

# --- Post-creation: symlink large directories ---
# .worktreelinks lists directories to symlink instead of duplicate (e.g., node_modules)
if [[ -f "${REPO_ROOT}/.worktreelinks" ]]; then
  while IFS= read -r dir || [[ -n "$dir" ]]; do
    [[ -z "$dir" || "$dir" == \#* ]] && continue
    src="${REPO_ROOT}/${dir}"
    dest="${WORKTREE_PATH}/${dir}"
    if [[ -d "$src" && ! -e "$dest" ]]; then
      ln -s "$src" "$dest" 2>/dev/null && echo "Symlinked ${dir}" >&2 || true
    fi
  done < "${REPO_ROOT}/.worktreelinks"
fi

echo "Created worktree: ${WORKTREE_PATH} (branch: ${BRANCH_NAME})" >&2
echo "${WORKTREE_PATH}"
