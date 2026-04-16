# Review Checklist

Step-by-step review process. Work through each section in order during Phase 3.

## 1. PR Description Quality

- [ ] `Closes #N` present — links PR to issue for auto-close on merge
- [ ] Summary section — what changed and why (2-3 sentences)
- [ ] Changes section — bulleted list of key changes
- [ ] Testing section — what tests verify
- [ ] Grounding section — which documentation sources were consulted
- [ ] Follow-up section — any new issues filed, or "None"
- [ ] Description is self-contained — a reader with zero context can understand

Missing or vague sections are a **non-blocking** finding. The PR should be
self-contained because the review agent (you) has no shared context with the
dev-agent that wrote it.

## 2. Diff Review — Systematic Reading

### Reading order

1. **File list first** — `gh pr view <PR> --json files --jq '.files[].path'`
   to understand scope before diving into code
2. **Tests** — read test files first to understand intent and expected behavior
3. **Core logic** — the main implementation changes
4. **Config / infrastructure** — build files, CI, dependencies
5. **Documentation** — README, architecture docs, inline comments

### Per-file checks

Focus on **changed lines only**. Do not flag pre-existing issues.

- [ ] File is relevant to the issue scope
- [ ] Follows project conventions from the project conventions file
- [ ] No logic errors or off-by-one bugs
- [ ] Error handling is appropriate (not excessive, not missing)
- [ ] No commented-out code left behind
- [ ] No unexplained TODO/FIXME added (if added, should reference an issue)
- [ ] No debug print/log statements left in
- [ ] Variable and function names are clear and consistent

### What NOT to flag

These are false positives — skip them:

- Pre-existing issues in unchanged lines
- Style preferences not in the project conventions file (the project's conventions win)
- Things that linters or type checkers will catch (they run separately)
- Pedantic nitpicks that don't affect correctness or readability
- Code on unmodified lines, even if adjacent to changes
- Patterns that look unusual but are clearly intentional
- Issues that have lint-ignore comments with explanations

## 3. Test Verification

- [ ] New behavior has corresponding tests
- [ ] Tests are meaningful — not trivial assertions (`assert True`)
- [ ] Multiple inputs per behavior (prevents hardcoded returns)
- [ ] Mocks are justified — only external dependencies (APIs, databases, I/O)
- [ ] Test names are descriptive — convey what behavior they verify
- [ ] Full test suite passes (not just new tests)
- [ ] Edge cases from the issue spec are covered
- [ ] No tests-after-code smell (tests that mirror implementation rather than spec)

Test failures are always **blocking** findings.

## 4. Security Review

- [ ] No secrets, API keys, tokens, or credentials in the diff
- [ ] No hardcoded passwords or connection strings
- [ ] No SQL injection patterns (string concatenation in queries)
- [ ] No XSS patterns (unsanitized user input in HTML/templates)
- [ ] No command injection (unsanitized input in shell commands)
- [ ] No path traversal (user input in file paths without sanitization)
- [ ] Dependencies are from trusted sources
- [ ] No overly permissive permissions, roles, or CORS settings
- [ ] Auth/authz changes are correct and don't widen access

### Routing

- Clear vulnerability with known fix → **blocking** (request changes)
- Architectural security concern → **blocking** (escalate to human)
- Potential issue but uncertain → **advisory** (note in escalation)

## 5. Code Quality

- [ ] Lint passes (`ruff check .`, `eslint`, etc.)
- [ ] Format passes (`ruff format --check .`, `prettier`, etc.)
- [ ] Type check passes (`ty`, `mypy`, `pyright`, `tsc`, etc.)
- [ ] No unused imports or dead code introduced
- [ ] Functions are reasonably sized (not doing too many things)
- [ ] Naming is clear and consistent with project conventions
- [ ] No unnecessary code duplication introduced
- [ ] No unnecessary abstractions for one-time operations

Lint/format/type failures are **blocking** findings.

## 6. Scope Verification

- [ ] Changes address the issue requirements
- [ ] No unrelated changes (unless noted as discovered work in PR description,
      following the discovered work rules from `/github-kanban`)
- [ ] Scope is proportional to the size label
- [ ] Architecture docs updated if implementation details changed
- [ ] No feature creep beyond what the issue specified

Scope mismatch is a **blocking** finding if it introduces unreviewed changes.
Small discovered-work fixes noted in the PR are acceptable.

## 7. Grounding Verification

- [ ] Identify domains touched in the diff (GCP, ADK, specific libraries, UI)
- [ ] Check PR Grounding section for appropriate source citations
- [ ] Spot-check 1-2 key API usages if the grounding source is available:
  - Is the API current (not deprecated)?
  - Are parameters correct?
  - Any known pitfalls or gotchas?
- [ ] Flag deprecated API usage discovered during spot-checks
- [ ] Note domains where grounding sources were unavailable

Grounding findings are **advisory** — they inform the decision but do not
automatically trigger request-changes. Correct code with missing citations
is different from code using a deprecated API.

## 8. Compiling Findings

Sort every finding into one of three categories:

| Category | Meaning | Examples |
|----------|---------|---------|
| **Blocking** | Must be fixed before merge | Test failures, security vulns, logic bugs, missing tests |
| **Non-blocking** | Should address, review agent may fix directly | Typos, missing imports, small style fixes, 1-2 line corrections |
| **Advisory** | Notes for context | Missing grounding citations, suggestions for future improvement |

This categorization drives the Phase 7 decision:
- Any **blocking** findings → request changes or escalate
- Only **non-blocking** findings → fix directly (Phase 5), then proceed to merge decision
- Only **advisory** findings → proceed to merge decision, include in review comment
