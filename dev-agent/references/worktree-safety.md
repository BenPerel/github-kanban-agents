# Worktree Safety Guide

Git worktrees enable multiple agents to work on separate issues simultaneously
without branch conflicts. Each worktree is a full checkout in its own directory
with its own branch. The main checkout stays on `main`.

## Creating a Worktree

### Prerequisites

- The issue must already be claimed (`stage:in-progress`) before creating
  the worktree. Never create a worktree for an unclaimed issue — you risk
  orphaned worktrees if claiming fails later.

### Git Version Compatibility

`enter-worktree.sh` works with any modern Git version. The `--relative-paths`
flag (Git 2.48+) is not used because some embedded git libraries do not support
the `extensions.relativeWorktrees` repository format extension it enables.
Worktrees use absolute paths instead, which is the default Git behavior.
If the repo already has `extensions.relativeWorktrees` set (e.g., from a
prior `git worktree add --relative-paths`), the scripts auto-remove it.

### Procedure

1. Run the portable worktree script:
   ```bash
   WORKTREE=$(bash .agents/skills/dev-agent/scripts/enter-worktree.sh "<type>+<issue#>-<short-desc>")
   cd "$WORKTREE"
   ```
   - Example: `feat+15-auth-flow`, `fix+22-null-check`, `docs+8-api-guide`
   - The `+` is significant: the script translates it to `/` in the branch name
   - So `feat+15-auth-flow` creates branch `feat/15-auth-flow`
2. Your cwd is now inside the worktree
3. The worktree is based on HEAD of the current branch (usually `main`),
   so you start with the latest code
4. The script automatically resolves to the canonical repo root, even if
   called from inside an existing worktree (nested worktree safety)
5. Stale worktree metadata is pruned automatically before creation

### If Creation Fails

- Un-claim the issue: move it back to `stage:ready` via `/github-kanban`
- Report the error and stop
- Common failures: directory already exists (stale worktree), branch name
  collision, disk space

## Working Inside a Worktree

- **Git commands** operate on the worktree's branch automatically — `git
  status`, `git commit`, `git push` all work as expected
- **`gh` commands** operate against the same remote repo — PRs, issues,
  project boards are unaffected by which worktree you're in
- **Development commands** may need path adjustments. Some projects require
  running from the parent directory (e.g., `uv run uvicorn modeldebate.app:app`
  from the workspace root, not the repo root). Check the project conventions file for details.
- **Running tests**: Worktrees are placed in a sibling directory outside the
  repo (e.g., `../{repo-name}-worktrees/{branch}/`), so pytest's upward
  conftest discovery will not walk into the main repo. Run `pytest` normally
  from inside the worktree:
  ```bash
  uv run python -m pytest . -v
  ```
  ESLint config inheritance and file watcher scopes are similarly isolated
  by the sibling placement.
- **Stay in scope**: Only modify files related to your issue. Other agents
  may be working on other files in their own worktrees. Touching shared
  files creates merge conflicts.
- **Agent config directories** (`.claude/`, `.gemini/`, `.cursor/`, `.agents/`)
  must be symlinked from the main repo via `.worktreelinks`. Without them,
  agent permissions, skills, and script paths (`bash .agents/skills/...`)
  won't resolve. The `setup.sh` script creates `.worktreelinks` with these
  defaults automatically.

## Exiting a Worktree

### Happy Path — PR Created Successfully

```bash
cd "$(bash .agents/skills/dev-agent/scripts/exit-worktree.sh keep)"
```

The worktree directory and branch must remain on disk because the PR
references the branch. After merge, run
`bash .agents/skills/dev-agent/scripts/cleanup-worktrees.sh` to remove
stale worktrees (it detects merged PRs automatically).

**Never use `remove` after creating a PR** — it deletes the branch
and breaks the PR.

### Failure — Useful Partial Work Committed

```bash
cd "$(bash .agents/skills/dev-agent/scripts/exit-worktree.sh keep)"
```

Preserve the worktree so work can be resumed later (by you in a new session,
or by another agent, or by a human). Move the issue to Human Review (mid-dev)
with a comment explaining the state.

### Failure — No Useful Work

```bash
cd "$(bash .agents/skills/dev-agent/scripts/exit-worktree.sh remove)"
```

Clean up completely. Move the issue back to `stage:ready` so another agent
can pick it up.

## Race Condition Prevention

The kanban board is the coordination mechanism — not file locks, not branch
naming, not directory checks. Follow this sequence tightly:

```
1. Check issue is stage:ready           ← read
2. Check WIP limit for in-progress      ← read
3. Move issue to stage:in-progress      ← write (near-atomic via GitHub API)
4. Create worktree                      ← local operation
```

**Critical**: Do steps 1-3 in rapid succession with no other work between them.
The TOCTOU (time-of-check-to-time-of-use) window between checking and moving
is small because GitHub label updates are near-atomic per-issue.

### If Another Agent Claims First

If step 3 fails because the label was already changed:
- The issue is no longer in `stage:ready` — another agent claimed it
- Pick the next eligible issue from your selection list, or stop if none remain
- Do NOT force the move or work on an already-claimed issue

**Worst case**: Duplicate PRs from the TOCTOU window — the review agent
detects and resolves this. Acceptable tradeoff vs. distributed locking.

## Concurrency

Worktree lifecycle operations (`git worktree add`, `remove`, `prune`,
`branch -D`) are serialized via `flock` on a shared lockfile at
`../{repo-name}-worktrees/.worktree.lock`. Multiple agents can safely
create and destroy worktrees concurrently — the lock prevents metadata
corruption.

**Safe in parallel** (each worktree has an isolated index):
- `git add`, `git status`, `git diff` — per-worktree staging area
- File reads and writes within the worktree directory

**Must be serialized by the orchestrator** (modify shared refs in `.git/`):
- `git commit` — writes to `refs/heads/<branch>` in the shared `.git/` dir
- `git push` — concurrent pushes to the same remote branch will conflict
- `git fetch` with prune — can delete refs another agent is using
- `git rebase` — particularly dangerous; must hold exclusive access

No enforcement mechanism is implemented for agent-level git operations.
Serialization of `commit`/`push`/`fetch` is the orchestrator's responsibility.

## Orphan Detection

If a session dies unexpectedly mid-work:
- The worktree remains on disk under `../{repo-name}-worktrees/`
- The issue stays in `stage:in-progress` with no PR
- The branch exists but may have incomplete commits

### How to Detect

A human or future agent can find orphans by:
1. List worktrees: `git worktree list`
2. List in-progress issues: `gh issue list --label "stage:in-progress"`
3. Cross-reference: any in-progress issue without a recent commit on its
   branch or without an open PR is likely orphaned

### How to Clean Up

1. Check the branch for useful commits — if partial work exists, consider
   resuming rather than discarding
2. If discarding:
   ```bash
   cd "$(bash .agents/skills/dev-agent/scripts/exit-worktree.sh remove "<name>")"
   ```
3. Move the issue back to `stage:ready` via `/github-kanban`
4. Run `git worktree prune` periodically to clean stale metadata
   (the enter-worktree.sh script does this automatically before creating
   new worktrees, but manual cleanup may also be needed after crashes)

## Embedded Git Library Compatibility

Some tools embed git libraries that do not support Git 2.48+
`extensions.relativeWorktrees`. If a repository has
`extensions.relativeWorktrees = true` in its `.git/config`, these libraries
reject `core.repositoryformatversion = 1` and the tool crashes when opening
the repository.

The worktree scripts (`enter-worktree.sh`, `exit-worktree.sh`) **automatically
detect and remove** this extension, resetting `repositoryformatversion` to `0`.
No manual action is needed — the fix runs transparently on each worktree
operation.

If you see warnings about removing `relativeWorktrees`, this is expected.
Worktrees still function correctly with absolute paths (the Git default prior
to 2.48). The only trade-off is that worktree `.git` file entries use absolute
paths instead of relative ones — this has no functional impact for agent
workflows.

**Manual fix** (if needed outside of these scripts):

```bash
git config --unset extensions.relativeWorktrees
git config core.repositoryformatversion 0
```

## Never Do

- Never create a worktree before claiming the issue — risk of orphaned worktrees
- Never delete a worktree that has an open PR against its branch
- Never use `remove` when you have committed work you want to preserve
- Never work in two worktrees simultaneously in the same session
- Never modify the main checkout while worktrees exist on branches based on it
  (changes won't propagate until the worktree rebases)
