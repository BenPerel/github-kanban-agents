---
name: prd-to-issue
description: >
  Break a plan, spec, or PRD into independently-grabbable issues on the
  GitHub project board using tracer-bullet vertical slices.
  Use when user wants to convert a plan into issues, create implementation
  tickets, or break down work into issues.
  TRIGGER on: "prd to issues", "break this down", "create issues from",
  "convert to tickets", "slice this into issues", "/prd-to-issue",
  "break down the PRD", "file the implementation issues".
compatibility: Requires gh (GitHub CLI), jq, and git.
---

# PRD to Issues

Break a plan into independently-grabbable issues using vertical slices (tracer
bullets).

Issues are published to the same GitHub project board managed by `/github-kanban`
using `create-issue.sh`. Every issue follows the "issues as prompts" philosophy
from `/github-kanban` — each issue body is a self-contained prompt for a
dev-agent with zero prior context.

## Process

### 0. Bootstrap

Invoke `/github-kanban` to load board context (project IDs, field IDs, WIP
limits). This validates that `.kanban-config.json` exists and gives you
awareness of the current board state before publishing a batch of issues.

### 1. Gather context

Work from whatever is already in the conversation context. If the user passes
an issue reference (issue number, URL, or path) as an argument, fetch it:

```bash
gh issue view <NUMBER> --json title,body,comments
```

Read its full body and comments before proceeding.

### 2. Explore the codebase (optional)

If you have not already explored the codebase, do so to understand the current
state. Issue titles and descriptions should use the project's domain vocabulary
and respect any ADRs or architecture docs (e.g., `docs/architecture.md`).

### 3. Draft vertical slices

Break the plan into **tracer bullet** issues. Each issue is a thin vertical
slice that cuts through ALL integration layers end-to-end, NOT a horizontal
slice of one layer.

Slices may be **HITL** (Human-in-the-Loop) or **AFK** (Away-from-Keyboard).
HITL slices require human interaction (architectural decision, design review).
AFK slices can be implemented and merged without human interaction. Prefer AFK
over HITL where possible.

**Vertical slice rules:**
- Each slice delivers a narrow but COMPLETE path through every layer
  (schema, API, UI, tests)
- A completed slice is demoable or verifiable on its own
- Prefer many thin slices over few thick ones

### 4. Propose breakdown (Confidence-Based Execution)

Draft the proposed breakdown as a numbered list. For each slice, show:

- **Title**: short descriptive name
- **Type**: HITL / AFK
- **Issue type**: `bug` / `enhancement` / `documentation`
- **Size**: `xs` / `s` / `m` / `l` / `xl`
- **Priority**: `p0` / `p1` / `p2` (default: `p2`)
- **Blocked by**: which other slices (if any) must complete first
- **User stories covered**: which user stories this addresses (if the source
  material has them)

**Autonomous Decision Making:**
Rely on the PRD, established context, and standard vertical slicing principles
to make confident decisions about granularity and dependencies. Do NOT
routinely quiz the user or ask for generic confirmation.

**When to Pause for Input:**
Only halt and ask for user input if you are unconfident, lack critical context,
or identify a high-risk gap. Examples:
- The PRD is actively contradictory or ambiguous regarding scope.
- You encounter a complex architectural dependency (HITL) that lacks a clear
  implementation path in the codebase.
- You are unable to break a massive feature down into thin slices without
  making wild assumptions.

If you are confident in your breakdown, present the list briefly, explicitly
state your confidence, and proceed directly to publishing.

### 5. Publish the issues

For each slice in your confident breakdown (or after the user has resolved
your specific questions), publish a new issue using the `/github-kanban`
`create-issue.sh` script.

**Publish issues in dependency order** (blockers first) so you can reference
real issue numbers in the `--blocked-by` flag.

For each issue:

```bash
bash .agents/skills/github-kanban/scripts/create-issue.sh \
  --title "<Title>" \
  --body "<Issue body — see template below>" \
  --type enhancement \
  --priority p2 \
  --size m \
  --stage ready \
  --blocked-by <BLOCKER_ISSUE_NUMBER>
```

**Stage selection:**
- `--stage ready` — if the issue has no blockers (default for actionable work)
- `--stage backlog` — if the issue is blocked by another issue (use `--blocked-by`)

**Issue body template:**

```
## Parent

#<PARENT_ISSUE_NUMBER> (if the source was an existing issue, otherwise omit)

## What to build

A concise description of this vertical slice. Describe the end-to-end behavior,
not layer-by-layer implementation. Include specific file paths, API endpoints,
or components when known.

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

## Blocked by

- #<BLOCKER_ISSUE_NUMBER> (if any)

Or "None — can start immediately" if no blockers.
```

**Critical:** Every issue body must be a self-contained prompt. Include enough
context that a dev-agent with zero prior knowledge of the PRD or plan can
understand what to build, where to look, and how to verify success.

Do NOT close or modify any parent issue.

### 6. Report summary

After publishing all issues, report:
- Total issues created (count)
- Issue numbers with titles
- Dependency graph (which issues block which)
- Any HITL issues that need human decision before work can proceed
