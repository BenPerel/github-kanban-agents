# SDLC Checklist

Use this checklist during implementation. Work through each section in order.
Mark items as you complete them — skipping a step often creates rework later.

## Pre-Implementation

- [ ] Read the full issue body, all comments, and any linked issues
- [ ] Read the project conventions file (e.g., CLAUDE.md or Antigravity's instructions) from the repo root — conventions, dev commands, tooling
- [ ] Read architecture docs (e.g., `docs/architecture.md`) if editing core modules
- [ ] Detect the issue's domain(s) — see `references/grounding-guide.md`
- [ ] Load grounding docs for each detected domain (MCP queries, skills)
- [ ] Plan the approach:
  - Which files need modification?
  - Are new files needed?
  - Which tests need to be written?
  - Does this affect any shared interfaces or APIs?
  - Does this create or modify a module? If so, review `references/deep-modules-guide.md`:
    - Aim for deep modules (small interface, rich implementation)
    - Apply the deletion test to any new abstraction
    - Only introduce seams where behavior actually varies
- [ ] If the plan affects architecture significantly, consider escalating to
      Human Review (mid-dev) before investing implementation time

## TDD Cycle

- [ ] Identify requirements from the issue spec
- [ ] For each requirement:
  - [ ] Write a failing test (Red)
  - [ ] Verify the test fails
  - [ ] Write minimal code to pass (Green)
  - [ ] Refactor while tests stay green
- [ ] Review tests against `references/tdd-guide.md` quality checklist
- [ ] Verify anti-gaming: no hardcoded returns, multiple inputs, justified mocks

## Implementation Quality

- [ ] Follow project coding conventions from the project conventions file
  - Indentation, line length, quote style, naming conventions
- [ ] Use project-standard tools (e.g., `uv` not `pip`, `ruff` not `pylint`)
- [ ] Make changes incrementally — commit after each logical unit of work
- [ ] Stay within the issue scope — if something unrelated needs fixing:
  - Trivial: fix in current branch, note in PR
  - Non-trivial: file a new issue via `/github-kanban`
- [ ] Update `docs/architecture.md` if implementation details changed
- [ ] No secrets, credentials, or `.env` files in the codebase

## Validation

- [ ] **Lint**: Run the project's linter and fix all warnings/errors
  - Python: `ruff check .`
  - JS/TS: project-specific (check the project conventions file or `package.json` scripts)
- [ ] **Format**: Run the formatter check
  - Python: `ruff format --check .`
- [ ] **Type check**: Run the type checker
  - Python: `ty` (or `mypy` / `pyright` per project)
  - TS: `tsc --noEmit`
- [ ] **Test suite**: Run the FULL test suite, not just new tests
  - Python: `uv run pytest` (or project-specific command from the project conventions file)
  - JS/TS: `npm test` or equivalent
- [ ] **Security review**:
  - No secrets or API keys in code
  - No SQL injection, XSS, or command injection vulnerabilities
  - No hardcoded credentials
  - Dependencies are from trusted sources
- [ ] **UI verification** (if applicable): Use `/playwright-cli` to screenshot
      and verify visual changes
- [ ] **Import verification**: `python -c "import <module>"` for changed modules

If any check fails, fix and re-run. If you cannot fix confidently, escalate
to Human Review (mid-dev) with details on what's failing and why.

## Commit Standards

- **Stage specific files**: `git add <file1> <file2>` — never `git add -A`
- **Conventional messages**: `<type>(<scope>): <description>`
  - `feat(auth): add JWT token validation`
  - `fix(api): handle empty response from weather service`
  - `docs(readme): update deployment instructions`
  - `refactor(db): extract connection pool into separate module`
  - `test(auth): add integration tests for login flow`
  - `chore(deps): update fastapi to 0.115.0`
- **Atomic commits**: One logical change per commit — not "implement everything"
- **Pre-commit hooks**: Let them run. Fix any failures they surface.

## PR Creation

- [ ] Push branch: `git push -u origin <branch-name>`
- [ ] Create PR with `gh pr create --base <default-branch>` (resolve via `git symbolic-ref refs/remotes/origin/HEAD`):
  - Title: `<type>(<scope>): <short description>` (under 70 chars)
  - Body contains `Closes #<issue-number>` for auto-close on merge
  - Body is **self-contained** — the review agent has zero shared context
  - Include: Summary, Changes, Testing, Grounding sources, Follow-ups
- [ ] **Wait for remote CI checks**:
  - Run `gh pr checks --watch`.
  - If checks fail: Read logs (`gh run view --log-failed`), fix, commit, `git push`, and loop back to `gh pr checks --watch` until green.
  - Do NOT exit the worktree or move the issue to `stage:in-review` until CI is green.
- [ ] Move issue to `stage:in-review` via `/github-kanban` (only after CI is green)
  - If the project has `auto-in-review.yml` GitHub Action, skip manual move
- [ ] **NEVER merge. NEVER approve own PR.**

## Post-PR

- [ ] File follow-up issues via `/github-kanban` for discovered work
  - Ready if actionable, Backlog if blocked
- [ ] Update the project conventions file if a new doc file was created (add to docs table)
- [ ] Exit worktree: `cd "$(bash .agents/skills/dev-agent/scripts/exit-worktree.sh keep)"`
- [ ] Report summary: issue #, PR link, changes, tests, follow-ups

## Escalation Triggers

Move to Human Review (mid-dev) and **STOP** if any of these are true:

- [ ] Requirements are ambiguous after reading all available context
- [ ] Multiple valid approaches with significant tradeoffs
- [ ] Security, auth, or payment flows are affected
- [ ] Tests are failing with an unclear cause you cannot resolve
- [ ] Scope is larger than the issue's size label suggests
- [ ] Unrelated bugs block your progress
- [ ] Auth/credential errors require workarounds
- [ ] Implementation drifts significantly from the issue spec
- [ ] You find yourself guessing rather than knowing

When escalating:
1. Comment on the issue: what you did, what's blocking, what needs human input
2. Exit worktree: `cd "$(bash .agents/skills/dev-agent/scripts/exit-worktree.sh keep)"` (preserve partial work)
3. Stop — do not continue guessing
