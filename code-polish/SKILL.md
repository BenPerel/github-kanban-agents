---
name: code-polish
description: >
  Review changed code for reuse, quality, efficiency, and architecture, then fix any issues
  found. Use when the user says "simplify", "clean up", "review code quality",
  or after completing implementation work. Also triggered by /code-polish or
  "polish the code".
compatibility: Requires git.
---

# Code Polish: Code Review and Cleanup

Review all changed files for reuse, quality, and efficiency. Fix any issues found.

## Phase 1: Identify Changes

Run `git diff` (or `git diff HEAD` if there are staged changes) to see what
changed. If there are no git changes, review the most recently modified files
that the user mentioned or that you edited earlier in this conversation.

## Phase 2: Four Reviews

Run four independent reviews on the diff from Phase 1. **You MUST attempt
parallel subagents first** — only fall back to sequential if the Agent tool
is unavailable in your session.

### Parallel mode (preferred)

Send **four Agent tool calls in a single message** so they run concurrently.
Each agent receives the full diff and one review checklist below. Include the
diff inline in each agent's prompt — agents inherit the working directory
and tools (Read, Bash, grep) but do not see your conversation history.

```
Agent({ description: "Code reuse review",   prompt: "<diff>\n\n<Review 1 checklist>" })
Agent({ description: "Code quality review",  prompt: "<diff>\n\n<Review 2 checklist>" })
Agent({ description: "Efficiency review",    prompt: "<diff>\n\n<Review 3 checklist>" })
Agent({ description: "Architecture review",  prompt: "<diff>\n\n<Review 4 checklist>" })
```

Replace `<diff>` with the actual `git diff` output from Phase 1, and
`<Review N checklist>` with the full text of the corresponding review
section below (e.g., everything under "### Review 1: Code Reuse").

Tell each agent: "Review the following diff for <category>. You have full
access to the codebase via tools — use grep, find, and Read to search for
existing patterns when needed. List findings as bullet points — file path,
line, what's wrong, how to fix. If the code is clean for your category,
say so in one line. Do not fix anything — just report findings."

If a subagent fails or returns an empty/garbled result, perform that
review yourself (sequential fallback) before proceeding to Phase 3.

### Sequential fallback

If the Agent tool is not available (e.g., the environment does not support
subagents), perform all four reviews yourself, one after another, in the
order listed below.

---

### Review 1: Code Reuse

For each change:

1. **Search for existing utilities and helpers** that could replace newly
   written code. Look for similar patterns elsewhere in the codebase — common
   locations are utility directories, shared modules, and files adjacent to
   the changed ones.
2. **Flag any new function that duplicates existing functionality.** Suggest
   the existing function to use instead.
3. **Flag any inline logic that could use an existing utility** — hand-rolled
   string manipulation, manual path handling, custom environment checks,
   ad-hoc type guards, and similar patterns are common candidates.

### Review 2: Code Quality

Review the same changes for hacky patterns:

1. **Redundant state**: state that duplicates existing state, cached values
   that could be derived, observers/effects that could be direct calls
2. **Parameter sprawl**: adding new parameters to a function instead of
   generalizing or restructuring existing ones
3. **Copy-paste with slight variation**: near-duplicate code blocks that
   should be unified with a shared abstraction
4. **Leaky abstractions**: exposing internal details that should be
   encapsulated, or breaking existing abstraction boundaries
5. **Stringly-typed code**: using raw strings where constants, enums
   (string unions), or branded types already exist in the codebase
6. **Unnecessary nesting**: wrapper elements/components that add no layout
   or structural value
7. **Unnecessary comments**: comments explaining WHAT the code does
   (well-named identifiers already do that), narrating the change, or
   referencing the task/caller — delete; keep only non-obvious WHY
   (hidden constraints, subtle invariants, workarounds)

### Review 3: Efficiency

Review the same changes for efficiency:

1. **Unnecessary work**: redundant computations, repeated file reads,
   duplicate network/API calls, N+1 patterns
2. **Missed concurrency**: independent operations run sequentially when
   they could run in parallel
3. **Hot-path bloat**: new blocking work added to startup or
   per-request/per-render hot paths
4. **Recurring no-op updates**: state/store updates inside polling loops,
   intervals, or event handlers that fire unconditionally — add a
   change-detection guard so downstream consumers aren't notified when
   nothing changed. Also: if a wrapper function takes an updater/reducer
   callback, verify it honors same-reference returns (or whatever the
   "no change" signal is) — otherwise callers' early-return no-ops are
   silently defeated
5. **Unnecessary existence checks**: pre-checking file/resource existence
   before operating (TOCTOU anti-pattern) — operate directly and handle
   the error
6. **Memory**: unbounded data structures, missing cleanup, event listener
   leaks
7. **Overly broad operations**: reading entire files when only a portion
   is needed, loading all items when filtering for one

### Review 4: Architecture

Review the same changes for structural depth (see `dev-agent/references/deep-modules-guide.md`):

1. **Shallow modules**: new abstractions where the interface is nearly as
   complex as the implementation — apply the deletion test. If deleting the
   module would concentrate complexity rather than spread it, the module
   is a pass-through
2. **Premature seams**: new interfaces or adapter patterns introduced where
   only one implementation exists and no variation is expected
3. **Leaking depth**: changes that push complexity from a module's
   implementation into its interface (adding parameters, exposing internals,
   requiring callers to know ordering constraints)
4. **Missing depth**: logic duplicated across multiple callers that could be
   concentrated behind a single deep interface

## Phase 3: Fix Issues

Aggregate findings from all four reviews (subagent results or your own
sequential review) and fix each issue directly. If a finding is a false
positive or not worth addressing, note it and move on — do not argue with
the finding, just skip it.

When done, briefly summarize what was fixed (or confirm the code was
already clean).
