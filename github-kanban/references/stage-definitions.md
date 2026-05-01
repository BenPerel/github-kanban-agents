# Stage Definitions

Full stage definitions, valid transitions, label requirements, dependency handling,
agent workflows, and issue-writing guidelines for the GitHub Kanban skill.

## Stage Definitions

**Backlog** — Not yet actionable. Use ONLY when the issue is blocked by another
issue (`Blocked by #N`), depends on unfinished prerequisite work, or is
intentionally deferred to a future version. Backlog is NOT a default landing
zone — if an issue has a priority and no blockers, it belongs in Ready.

**Ready** — Fully actionable: has a priority label, no open blockers, scope is
clear enough to implement. This is the **default stage for new actionable
issues**. The next available agent or developer can pick it up immediately.
Agents can promote Backlog items to Ready when they determine blockers are
resolved and scope is clear.

**In Progress** — Actively being worked on. Move here **before** any
implementation begins — not after.

**Human Review (mid-dev)** — Agent hit uncertainty and needs human input before
continuing. Requirements unclear, scope ambiguous, implementation drifting from
plan, or lacking confidence in approach.

**In Review** — A PR has been created and the work is ready for code review.
Move here only after the PR is confirmed created. A review agent picks up issues
from this stage.

**Human Review (post-review)** — The review agent determined the change is too
large or sensitive for autonomous merge and needs human sign-off before merging.

**Done** — Work is merged and complete.

## Common Transitions

| From → To | Remove | Add | Script Command |
|-----------|--------|-----|----------------|
| Backlog → Ready | `stage:backlog` | `stage:ready` | `bash scripts/move-issue.sh --issue N --to ready` |
| Ready → In progress | `stage:ready` | `stage:in-progress` | `bash scripts/move-issue.sh --issue N --to in-progress` |
| In progress → Human Review (mid-dev) | `stage:in-progress` | `stage:human-review` | `bash scripts/move-issue.sh --issue N --to human-review-mid` |
| In progress → In review | `stage:in-progress` | `stage:in-review` | `bash scripts/move-issue.sh --issue N --to in-review` |
| Human Review → In progress | `stage:human-review` | `stage:in-progress` | `bash scripts/move-issue.sh --issue N --to in-progress` |
| In review → Human Review (post-review) | `stage:in-review` | `stage:human-review` | `bash scripts/move-issue.sh --issue N --to human-review-post` |
| In review → Done | `stage:in-review` | `stage:done` | `bash scripts/move-issue.sh --issue N --to done` |

## Fast-Track Transitions

These skip intermediate stages. Use sparingly and only when appropriate:

| From → To | When | Notes |
|-----------|------|-------|
| Backlog → Ready | Blockers resolved, scope clear | Verify `size:*` label exists |
| Ready → Done | Resolved without implementation | Rare — "won't do" or "resolved itself" |
| Backlog → Done | Issue no longer relevant | Close with comment explaining why |
| In Progress → Done | Emergency P0 hotfix merged directly | Only for critical production fixes |

## Dependencies and Blockers

Note dependencies in issue bodies with `Blocked by #N`. Check before starting work:

```bash
gh issue list --search "is:open is:blocked"
gh issue list --search "is:open is:blocking"
```

### Picking Next Work

When the user asks what to work on:
1. Check for `priority:p0` issues in Ready
2. Check for issues blocking other work (`is:blocking`)
3. List `stage:ready` items by priority
4. Verify In Progress has room (< 3 items)
5. Skip blocked issues
6. Recommend the highest-priority, unblocked, ready issue

**Backlog fallback**: If no Ready issues are eligible, scan Backlog for items
whose blockers have been resolved. Promote them to Ready (verify `size:*` label)
before picking them up. If In Progress is full, surface this to the user rather
than exceeding the WIP limit.

## Automated Transitions (GitHub Actions + Built-in)

Some stage transitions happen automatically — agents should **not** duplicate these.

| Transition | How | Agent responsibility |
|------------|-----|---------------------|
| PR merged / Issue closed → **Done** | Built-in project automation (free, zero code) | None — happens automatically |
| PR opened with `Closes #N` → **In Review** | GitHub Actions workflow (`auto-in-review.yml`) | Agent creates the PR; skip manual label+board move if this Action is installed |
| WIP limit exceeded → **check fails** | GitHub Actions workflow (`wip-limit-check.yml`) | Agent should still check WIP before moving; the Action is a safety net |

**Still requires agent action (no GitHub event to trigger on):**
- Backlog/Ready → **In Progress** — only the agent knows when it's picking up work
- In Progress → **Human Review (mid-dev)** — only the agent knows when it's stuck
- Backlog → **Ready** — requires judgment about whether blockers are resolved

## Agent Workflows

For autonomous implementation of issues, use `/dev-agent`. It handles the full
lifecycle: issue selection → worktree → TDD → implementation → PR → in-review.

For autonomous PR review, use `/review-agent`. It handles: review → fix easy
issues → simplify → merge (simple fixes) or escalate to human review (complex
changes) or request changes (clear problems) → follow-up issues.

This kanban skill handles board operations that those agent skills call into.

## Discovered Work

When you find bugs or improvements while working on something else:

- **Trivial fix** (typo, one-liner, clearly correct): Fix in current branch,
  note in PR description. No new issue needed.
- **Small related fix** (same area, quick): Fix in current branch if it doesn't
  bloat the PR scope. Note in PR.
- **Larger bug or unrelated work**: Create a new issue (Ready if actionable,
  Backlog if blocked). Do NOT fix in the current branch — stay focused on the
  original issue.

## Writing Agent-Ready Issues

Every issue is a prompt for an AI agent with zero prior context. Include:

- **Parent**: Reference to parent issue or initiative (if this is part of a
  larger effort), or omit if standalone
- **What**: Precise description of what needs to change
- **Why**: What prompted this and why it matters
- **Where**: Specific file paths and line numbers
- **How** (suggested): Recommended approach
- **Acceptance criteria**: How the agent knows it's done
- **Blocked by**: `#N` references to blocking issues, or "None — can start
  immediately"
- **Prior investigation**: What's already been checked or ruled out

Never include sensitive data (secrets, credentials, PII) in issue bodies.

## Label Taxonomy

Every issue requires these labels — enforce on creation and verify on transitions:

1. **Stage** (exactly one): `stage:backlog` / `stage:ready` / `stage:in-progress`
   / `stage:human-review` / `stage:in-review` / `stage:done`
2. **Type** (at least one): `bug` / `enhancement` / `documentation`
3. **Priority** (exactly one): `priority:p0` / `priority:p1` / `priority:p2`
4. **Size** (exactly one, required once Ready): `size:xs` / `size:s` / `size:m`
   / `size:l` / `size:xl`

When the user doesn't specify priority: default to `priority:p2`. Ask about type
if ambiguous. Size can be omitted for backlog items but is required before moving
to Ready.

**Default stage**: If the issue has a priority and no `Blocked by #N` → default
to `stage:ready`. Only use `stage:backlog` when the issue is explicitly blocked,
depends on unfinished work, or is deferred.

## Worktree Maintenance

After agent crashes or force-kills, stale worktree metadata can accumulate.
The `enter-worktree.sh` script runs `git worktree prune` automatically before
creating new worktrees, but manual cleanup may also be needed:

```bash
# Clean stale worktree metadata
git worktree prune

# List all active worktrees
git worktree list

# Cross-reference with in-progress issues to find orphans
gh issue list --label "stage:in-progress" --state open
```

See `dev-agent/references/worktree-safety.md` for full orphan detection and
cleanup procedures.
