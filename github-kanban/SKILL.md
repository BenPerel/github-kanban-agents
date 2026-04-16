---
name: github-kanban
description: >
  Manages GitHub Issues and a Projects kanban board — stage transitions,
  WIP limits, label taxonomy, and board operations.
  Use this skill whenever the user wants to create issues, move issues between stages,
  close issues, check WIP limits, triage bugs, plan work, close duplicates,
  or interact with the GitHub project board in any way.
  TRIGGER on: "create an issue", "file a bug", "move to in-progress",
  "what's in backlog", "what's ready", "close as duplicate", "what should I work on next",
  "update the board", "check WIP", "triage", "kanban", "project board",
  any mention of issue numbers (#N) combined with stage/priority/label changes,
  "start work on", "pick up", "mark as done", "submit for review",
  issue dependencies, blockers, or any discussion of issue lifecycle.
  Even if the user doesn't say "issue" explicitly — phrases like "log a bug",
  "track this work", "what's blocking us", or "close that out" should trigger this skill.
compatibility: Requires gh (GitHub CLI), jq, and git.
---

# GitHub Kanban

Repo: `<REPO>` | Project: "<PROJECT_NAME>" (Project #<PROJECT_NUMBER>, owner: <OWNER>)

**All `gh` commands must run from the git root directory.**

Before your first board operation in a session, read
`references/stage-definitions.md` — it has full stage definitions, valid
transitions, label requirements, dependency handling, agent workflows,
and issue-writing guidelines. The quick reference table below has the IDs
you need for script calls.

## Quick Reference

| Column | Label | WIP Limit | Board Option ID |
|--------|-------|-----------|-----------------| 
| Backlog | `stage:backlog` | 10 | `<BACKLOG_OPTION_ID>` |
| Ready | `stage:ready` | — | `<READY_OPTION_ID>` |
| In progress | `stage:in-progress` | 3 | `<IN_PROGRESS_OPTION_ID>` |
| Human Review (mid-dev) | `stage:human-review` | — | `<HUMAN_REVIEW_MID_DEV_OPTION_ID>` |
| In review | `stage:in-review` | 5 | `<IN_REVIEW_OPTION_ID>` |
| Human Review (post-review) | `stage:human-review` | — | `<HUMAN_REVIEW_POST_REVIEW_OPTION_ID>` |
| Done | `stage:done` | — | `<DONE_OPTION_ID>` |

The two Human Review columns share the same label but different board option IDs. Mid-dev: agent is uncertain, pause and ask. Post-review: formal sign-off after code review.

**Project IDs** (for `gh project item-edit`):
- Project: `<PROJECT_ID>`
- Status field: `<STATUS_FIELD_ID>`
- Priority field: `<PRIORITY_FIELD_ID>` — P0=`<P0_OPTION_ID>` · P1=`<P1_OPTION_ID>` · P2=`<P2_OPTION_ID>`
- Size field: `<SIZE_FIELD_ID>` — XS=`<XS_OPTION_ID>` · S=`<S_OPTION_ID>` · M=`<M_OPTION_ID>` · L=`<L_OPTION_ID>` · XL=`<XL_OPTION_ID>`

## Treating Issues as Prompts

**Crucial mindset:** Treat every GitHub issue as a prompt for the next AI agent that will pick up the task.
Whenever you create or modify an issue, always format the issue body as a clear, standalone prompt. It should contain all the necessary context, explicitly outline the goals or constraints, state where to look, and define clear acceptance criteria so that an LLM with zero prior context can easily follow the instructions and execute the task. 

## Creating Issues

Use the `bash .agents/skills/github-kanban/scripts/create-issue.sh` script to create issues with correct labels and board status in one step:

```bash
bash .agents/skills/github-kanban/scripts/create-issue.sh \
  --title "Short descriptive title" \
  --body "Description of the work." \
  --type enhancement \
  --priority p2 \
  --size m \
  --stage ready
```

Options:
- `--title TEXT` — Issue title (required)
- `--body TEXT` — Issue body (required)
- `--type bug|enhancement|documentation` — Issue type (required)
- `--priority p0|p1|p2` — Priority (default: p2)
- `--size xs|s|m|l|xl` — Size (required if stage is ready+)
- `--stage STAGE` — Target stage (default: ready)
- `--blocked-by N` — Issue number this is blocked by (repeatable)

Run `bash .agents/skills/github-kanban/scripts/create-issue.sh --help` for full usage.

## Moving Issues Between Stages

Use the `bash .agents/skills/github-kanban/scripts/move-issue.sh` script. It handles WIP limit checks, label validation, and dual label+board updates:

```bash
bash .agents/skills/github-kanban/scripts/move-issue.sh --issue 15 --to in-progress
```

Options:
- `--issue NUMBER` — Issue number (required)
- `--to STAGE` — Target stage name (required)

The script will:
1. Check WIP limits for the target stage
2. Verify required labels (e.g., `size:*` for ready+)
3. Swap the `stage:*` label
4. Update the board status

Run `bash .agents/skills/github-kanban/scripts/move-issue.sh --help` for full usage.

## Checking WIP Limits

Use `bash .agents/skills/github-kanban/scripts/check-wip.sh` to check whether a stage has room:

```bash
bash .agents/skills/github-kanban/scripts/check-wip.sh --stage in-progress
```

Exits `0` if under limit, `1` if at or over limit.

## Board Maintenance

Use `bash .agents/skills/github-kanban/scripts/archive-done.sh` to keep the board clean:

```bash
bash .agents/skills/github-kanban/scripts/archive-done.sh              # Archive old Done items (keep 10)
bash .agents/skills/github-kanban/scripts/archive-done.sh --keep 5     # Keep only 5
bash .agents/skills/github-kanban/scripts/archive-done.sh --dry-run    # Preview what would be archived
```

Run this after merging a PR (review-agent does this automatically in Phase 7c).

## Closing Issues

### Normal completion

If the PR body contains `Closes #N`, GitHub automatically closes the issue on merge. Do NOT run `gh issue close` separately — just update the stage:

```bash
bash .agents/skills/github-kanban/scripts/move-issue.sh --issue <NUMBER> --to done
```

If no PR auto-close is set up, close manually:

```bash
gh issue close <NUMBER> --comment "Completed in #<PR>"
bash .agents/skills/github-kanban/scripts/move-issue.sh --issue <NUMBER> --to done
```

### Duplicates

Close with reason "not planned". Strip all workflow labels. Add `duplicate`. Do not delete — closed duplicates serve as search redirects.

```bash
gh issue close <NUMBER> --reason "not planned" \
  --comment "Duplicate of #<CANONICAL>"
gh issue edit <NUMBER> \
  --remove-label "<CURRENT_STAGE_LABEL>,<CURRENT_PRIORITY_LABEL>,<CURRENT_SIZE_LABEL>" \
  --add-label "duplicate"
```

Adjust `--remove-label` to match whatever `stage:*`, `priority:*`, and `size:*` labels the issue actually has — strip all of them so the duplicate doesn't pollute the board.

## Auth Fallback

If any `gh project` command (item-list, item-edit, etc.) or `--project` flag fails with a permission/scope error, the `project` OAuth scope is missing. Proceed without the board operation and tell the user:

> The `project` OAuth scope is missing — I completed the issue/label changes but couldn't update the project board. Run this interactively to grant the scope, then I can retry the board update:
> ```
> gh auth refresh -s project -h github.com
> ```

For issue creation specifically, omit `--project "<PROJECT_NAME>"` so the issue still gets created. Once the user grants the scope, retry adding it to the board.
