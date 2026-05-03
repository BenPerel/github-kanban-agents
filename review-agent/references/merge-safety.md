# Merge Safety — Decision Framework

When to merge, escalate, or request changes. Read during Phase 7.

**Max auto-merge size: `size:s`** — the review agent may only merge PRs sized
`size:xs` or `size:s`. Anything larger requires escalation. To change this
threshold, update this definition — the rest of the document references it.

## Decision Flow

```
Has blocking findings?
├─ Yes → Can the review agent fix them trivially (Phase 5)?
│        ├─ Yes → Fix them, re-check → continue flow
│        └─ No → Is the fix path clear?
│                ├─ Yes → REQUEST CHANGES
│                └─ No (architectural/security) → ESCALATE
│
└─ No blocking findings
   ├─ Exceeds max auto-merge size? → ESCALATE
   ├─ Security-sensitive changes? → ESCALATE
   ├─ Architectural changes? → ESCALATE
   ├─ Uncertain about correctness? → ESCALATE
   ├─ All merge criteria met? → MERGE
   └─ Not all criteria met? → ESCALATE (default safe path)
```

## Merge Criteria

**ALL must be true** to merge:

- [ ] Size is within the max auto-merge size (see top of file)
- [ ] Full test suite passes
- [ ] Lint, format, and type checks pass
- [ ] No security-sensitive changes
- [ ] Scope matches issue requirements
- [ ] No open questions or uncertainty
- [ ] No merge conflicts
- [ ] Branch is rebased onto latest base branch (Phase 6 rebase step)
- [ ] PR description is complete and self-contained
- [ ] No blocking findings remain after Phase 5 fixes

If **any** criterion fails, do not merge — escalate or request changes.

### Merge commands

```bash
# 1. Approve (may fail in solo dev repos — see below)
gh pr review <PR> --approve --body "Review Agent — Approved. All checks pass."

# 2. Merge
gh pr merge <PR> --merge --delete-branch

# 3. Move to Done via /github-kanban (label + board)
#    Note: Closes #N auto-closes the issue — don't run gh issue close
```

## Escalation Criteria

**ANY one triggers escalation:**

- Exceeds the max auto-merge size (see top of file)
- Security-related changes (auth, permissions, encryption, tokens — even if
  they look correct)
- Architectural changes (shared interfaces, database schemas, API contracts,
  core abstractions)
- Uncertainty about correctness — if you're not confident the code is right
- Domain-specific code where the grounding source was unavailable
- Merge conflicts — rebase failed during Phase 6 freshness check, or
  conflicts detected at merge time
- Multiple valid approaches with significant tradeoffs
- Incomplete review (couldn't run tests, missing dependencies, env issues)

### Escalation uses the post-review Human Review column

Always use the **post-review** board option ID (see `/github-kanban` Quick
Reference for the two Human Review columns).

### After escalation

Human reviews in GitHub UI, moves issue back to `stage:in-review` when ready.
Review-agent picks it up as a re-review via normal Phase 2 flow.

## Request Changes Criteria

**ANY one triggers request-changes** (when the issue is clearly fixable by the
dev-agent):

- Test failures
- Lint, format, or type check errors not trivially fixable
- Clear security vulnerability with a known fix path
- Obvious logic bugs
- Missing tests for new behavior
- Convention violations from the project conventions file
- Scope mismatch — changes don't address the issue or include significant
  unrelated changes

### Request-changes comment format

Write the issue comment as a **prompt for the dev-agent** — it has zero context:

- List specific findings with file paths and line numbers
- Explain what's wrong and how to fix it
- Include any investigation you already did so the dev-agent doesn't repeat it
- Be actionable: the dev-agent should be able to address each finding without
  asking questions

### Stage transition

Move the issue from `stage:in-review` to `stage:ready` and set priority to
`p0`. The dev-agent only queries `stage:ready` for work — moving to
`stage:in-progress` would strand the issue since no agent polls that stage.
Priority `p0` ensures the fix is picked up before lower-priority work.

## Easy Fix Criteria

Issues the review agent fixes directly in Phase 5 instead of requesting changes:

| Fix | Example |
|-----|---------|
| Typos | Misspelled variable name, string typo |
| Missing imports | Unused import removed, needed import missing |
| Style fixes | Naming convention, formatting |
| 1-2 line corrections | Off-by-one, wrong constant, missing return |
| Debug cleanup | Leftover print statements, commented-out code |

### Guardrails

- Must not change behavior or public interfaces
- Must not require new or modified tests
- Must be within the scope of the PR
- Must be something you are certain about — if unsure, request changes instead
- Re-run tests after fixing to verify nothing broke

## Solo Dev Handling

In solo dev repos, `gh pr review --approve` fails because GitHub doesn't allow
self-approving your own PRs. This is expected, not an error.

### How to handle

1. Attempt `gh pr review --approve`
2. If it fails with a self-review error message, **skip the approve step**
3. Proceed directly to `gh pr merge --merge --delete-branch`
4. All other merge criteria still apply — don't lower the bar just because
   approve was skipped

## Duplicate PR Detection

Two agents may have created PRs for the same issue (race condition edge case).

### Detection

```bash
gh pr list --search "closes #<ISSUE>" --state open --json number,url,author,createdAt
```

### Resolution

1. Compare the PRs: completeness, test coverage, code quality
2. Review the **more complete** PR through the normal flow
3. Comment on the other PR explaining the situation and suggesting it be closed
4. Do NOT close the duplicate yourself — let the PR author or a human decide

If both PRs are equally good, prefer the older one (first-come-first-served).
