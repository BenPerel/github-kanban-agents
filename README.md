# github-kanban-agents

Autonomous AI agent skills for the full software development lifecycle — powered by a GitHub Projects kanban board. Agents pick up issues, implement with TDD, review PRs, merge, and verify deployment. Includes dev-agent, review-agent, diagnose, simplify, and github-kanban skills. Works with Gemini, Claude, and 40+ agents.

## Installation

> **Note**: The helper scripts bundled with these skills use standard Linux utilities and GNU-specific extensions (like `grep -oP`). They are designed for Linux and may fail on macOS unless `gnu-grep` is installed.

### Quick install (recommended)

```bash
npx skills add BenPerel/github-kanban-agents -y --skill "*" --scope local
```

This installs all 5 skills to your detected agents (Claude Code, Antigravity, Gemini CLI, Cursor, Codex, and [40+ more](https://github.com/vercel-labs/skills#available-agents)).

### Gemini CLI

```bash
gemini skills install https://github.com/BenPerel/github-kanban-agents.git
```

### Manual

```bash
git clone https://github.com/BenPerel/github-kanban-agents.git
ln -s /path/to/github-kanban-agents/dev-agent .gemini/skills/dev-agent
ln -s /path/to/github-kanban-agents/review-agent .gemini/skills/review-agent
ln -s /path/to/github-kanban-agents/simplify .gemini/skills/simplify
ln -s /path/to/github-kanban-agents/diagnose .gemini/skills/diagnose
# github-kanban requires setup — see below
```

## Kanban Board Setup

The `github-kanban` skill generates a configuration specific to your repository. It maps your board's column and field IDs into an actionable SKILL file. After installing, run the setup script:

> **Prerequisites**: Your repository must have at least one commit pushed to GitHub before running setup (the script uses `gh repo view` which requires a remote). You also need `gh` (GitHub CLI), `jq`, and `git` installed.

### Method 1: Create a brand new perfectly styled board (Recommended)
This clones the official "Golden Template" which comes pre-configured with Backlog, Priority boards, and visual UI badges exactly as the agent expects.

```bash
# From your target repo root (or wherever the skill was installed):
./github-kanban/scripts/setup.sh new "My Awesome Board" <OWNER>
```

### Method 2: Link an existing empty project board
If you already created a board manually and added the Priority and Size fields yourself:

```bash
./github-kanban/scripts/setup.sh <PROJECT_NUMBER> <OWNER>
```

This script will:
1. (If using `new`) Clone the officially styled Kanban template and copy all Views and tabs.
2. Fetch all project field IDs and option IDs via the GitHub API.
3. Generate the project-specific `SKILL.md` with all IDs filled in.
4. Generate `.kanban-config.json` at the repo root (used by helper scripts).
5. Create required labels (`stage:*`, `priority:*`, `size:*`) idempotently.

The setup script is **idempotent** — safe to re-run at any time to regenerate your config.

## Skills

### github-kanban

Board operations skill — manages issue lifecycle, stage transitions, WIP limits, and label taxonomy.

**Covers:**
- **Issue creation** — correct labels (`stage:*`, type, `priority:*`, `size:*`), project assignment, dependency tracking (`Blocked by #N`), parent issue linking (`--parent`)
- **Stage transitions** — WIP limit checks, dual updates (label + board status), size label enforcement at Ready
- **Duplicate handling** — close with `not planned`, strip all workflow labels, add `duplicate` label
- **Work prioritization** — P0-first, unblock blockers, respect WIP limits, backlog fallback
- **Two Human Review stages** — mid-dev (agent is uncertain) vs post-review (formal sign-off)
- **Discovered work** — guidance for handling bugs found while working on something else
- **Fast-track transitions** — shortcuts for trivial fixes and resolved-without-implementation
- **`Closes #N` auto-close** — avoids redundant `gh issue close` when PRs auto-close issues
- **GitHub Actions workflows** — auto-move to In Review on PR open, WIP limit enforcement
- **Auth fallback** — graceful handling when `project` OAuth scope is missing

**Helper scripts** (in `github-kanban/scripts/`):
- `create-issue.sh` — create issues with labels + board status in one call
- `move-issue.sh` — move issues between stages (WIP check, label swap, board update)
- `check-wip.sh` — check WIP limits for a stage
- `archive-done.sh` — archive old Done items from the board

### dev-agent

Autonomous developer agent that picks up GitHub issues and implements them end-to-end. Works in isolated git worktrees for multi-agent parallelism.

**Flow:** issue selection → worktree → TDD → implementation → validation → PR → in-review

**Covers:**
- **Issue selection** — two-tier: Ready first (by priority), then Backlog fallback (evaluate promotability)
- **Race condition handling** — kanban board as coordination layer for multi-agent setups
- **Worktree lifecycle** — creation, work isolation, cleanup on success and failure
- **Test-Driven Development** — Red-Green-Refactor with anti-gaming rules for AI agents
- **Domain grounding** — routes to appropriate MCP servers and skills based on issue domain (GCP, ADK, libraries, frontend)
- **SDLC checklist** — pre-implementation through post-PR, with escalation triggers
- **Failure handling** — escalation to Human Review (mid-dev) with explanatory comments

### review-agent

Autonomous review agent that picks up PRs from In Review, performs systematic code review, fixes trivial issues, simplifies code, and decides whether to merge, request changes, or escalate to human review. Creates follow-up issues as actionable prompts for other agents.

**Flow:** issue in-review → claim → review → fix easy issues → simplify → merge/escalate/request-changes → follow-up issues

**Covers:**
- **Issue selection** — priority-sorted from `stage:in-review`, with PR existence verification
- **Systematic review** — diff reading, test execution, security scan, scope verification, grounding checks
- **Easy fixes** — trivial issues (typos, 1-2 line fixes) fixed directly on the PR branch
- **Code simplification** — invokes `/simplify` on changed files before merge
- **Three-way decision** — merge (size:xs/s, all clear), escalate (size:m+, security, uncertainty), request changes (clear problems)
- **Solo dev handling** — graceful skip of `gh pr review --approve` when self-review fails
- **Human re-review** — picks up issues returned to `stage:in-review` after human feedback
- **Follow-up issues as prompts** — discovered improvements filed with full context for agent pickup
- **Duplicate PR detection** — handles race condition edge case of multiple PRs per issue

### diagnose

Structured diagnostic methodology for bugs and failures with unclear root cause. Used by dev-agent (bug issues) and review-agent (test/deployment failures).

**Flow:** build feedback loop → reproduce → hypothesize (3-5 ranked) → instrument one variable at a time → fix + regression test → cleanup + post-mortem

**Covers:**
- **10-method feedback loop hierarchy** — from failing test (fastest) down to human-in-the-loop (last resort)
- **Hypothesis-driven debugging** — prevents tunnel-vision on first plausible explanation
- **Tagged instrumentation** — `[DEBUG-xxxx]` tags for single-grep cleanup
- **Regression test integration** — flows naturally into the TDD cycle
- **Escalation criteria** — when to stop diagnosing and escalate to human review

### simplify

Code review and cleanup skill — reviews changed code for reuse, quality, and efficiency, then fixes issues found.

**Flow:** identify changes → three parallel reviews (reuse, quality, efficiency) → fix issues

## GitHub Actions (optional, free)

The setup script will offer to install these automatically. To install manually:

```bash
mkdir -p .github/workflows
cp github-kanban/templates/auto-in-review.yml .github/workflows/
cp github-kanban/templates/wip-limit-check.yml .github/workflows/

# Create a PAT (classic) with repo + project scopes at
# https://github.com/settings/tokens, then:
gh secret set PROJECT_PAT --repo <OWNER>/<REPO>
```

Update placeholder values in the workflow files with your project IDs, then commit and push.

Also enable the free built-in project automations (must be done in the UI):
1. Go to your project's Settings → Workflows
2. Enable "Item closed → Done" and "Pull request merged → Done"

## Guardrails & Customization

The kanban skill is designed for safety and controlled autonomy. It ships with a sensible default workflow (Backlog → Ready → In Progress → In Review → Done). You can easily configure the installed skills in your local project to set your own boundaries:

- **Size-based Autonomy Gates** — By default, the `review-agent` automatically merges `XS` and `S` sized PRs if tests pass. Anything sized `M` or larger is automatically escalated to `Human Review`. This prevents agents from unilaterally YOLOing large, complex changes. (You can adjust this threshold safely inside the installed `review-agent` SKILL.md).
- **Hard WIP Limits** — Prevent agent runaway loops by capping concurrent work. Agents respect strict Kanban WIP limits (defaults: Backlog 10, In Progress 3, In Review 5), configurable in `.kanban-config.json`. Agents finish what they start instead of endlessly pulling new tickets.
- **Kanban columns** — add, remove, or rename stages.
- **Label taxonomy** — change label prefixes or add new label types (e.g. adapt priorities, add P3/P4, or resize labels).

## Worktree Configuration (Optional)

The dev-agent and review-agent skills use git worktrees for multi-agent isolation.
Worktrees are placed in a **sibling directory** (`../{repo-name}-worktrees/`) rather
than inside the repo, preventing tool interference (pytest conftest leakage, ESLint
config bleed, file watcher loops, Docker context bloat).

Two optional config files control how worktrees behave:

- **`.worktreeinclude`** — List gitignored files to copy into new worktrees (uses .gitignore syntax).
  Useful for `.env` files, local configs, or secrets that aren't in git but are needed to run/test.

- **`.worktreelinks`** — List directories to symlink instead of duplicate.
  Prevents disk bloat from large directories like `node_modules/`.

Example `.worktreeinclude`:
```
.env
config/secrets/*.yaml
```

Example `.worktreelinks`:
```
node_modules
.venv
```

## Known Limitations

### Git 2.48+ `extensions.relativeWorktrees`

Some tools embed git libraries that do not support `extensions.relativeWorktrees` (introduced in Git 2.48). If your repo has `extensions.relativeWorktrees = true` in `.git/config`, these tools may crash when opening the repository.

The worktree scripts automatically detect and fix this by removing the extension and resetting `core.repositoryformatversion` to `0`. If you need a manual fix:

```bash
git config --unset extensions.relativeWorktrees
git config core.repositoryformatversion 0
```

Worktrees continue to function normally — the only difference is absolute vs relative paths in worktree metadata, which has no functional impact.

## License

This project is licensed under the [Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International (CC BY-NC-SA 4.0)](LICENSE) license.
