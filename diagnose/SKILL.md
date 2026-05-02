---
name: diagnose
description: >
  Structured diagnostic methodology for bugs and failures with unclear root
  cause. Builds a fast feedback loop, generates hypotheses before testing,
  instruments one variable at a time, and produces a regression test + fix.
  Invocable by dev-agent (bug issues) and review-agent (test/deployment failures).
  TRIGGER on: "diagnose", "debug this", "root cause", "investigate failure",
  "why is this failing", "/diagnose", "/diagnose #15".
  Use this skill ANY TIME a failure's root cause is not immediately obvious
  from the error message or stack trace.
compatibility: "Requires git."
---

# Diagnose

A structured methodology for finding root causes. Use this when a failure's
cause is not immediately obvious — do not guess-and-check your way to a fix.

## Phase 1: Build a Feedback Loop

Construct a fast, deterministic signal that reproduces the failure. Pick the
highest method on this list that works for your situation:

| # | Method | When to use |
|---|--------|-------------|
| 1 | **Failing test** | You can write a test that triggers the bug |
| 2 | **curl / httpie** | Bug is in an HTTP endpoint |
| 3 | **CLI invocation** | Bug is in a CLI tool or script |
| 4 | **Headless browser** | Bug requires browser interaction (use playwright) |
| 5 | **Replay trace/log** | You have a log or trace that shows the failure |
| 6 | **Throwaway harness** | Write a minimal script that triggers the bug in isolation |
| 7 | **Fuzz inputs** | Bug is input-dependent but you don't know which input |
| 8 | **Git bisect** | Bug appeared recently, unclear which commit introduced it |
| 9 | **Differential test** | Compare known-good version against broken version |
| 10 | **Human-in-the-loop** | Cannot reproduce programmatically — escalate |

**The goal**: a single command you can run repeatedly that returns pass/fail
in seconds, not minutes. If your feedback loop takes longer than 30 seconds,
find a way to narrow it (smaller dataset, isolated component, cached setup).

### Iterate on the Loop

Treat the feedback loop as a product. Once you have *a* loop, ask:

- Can I make it **faster**? (Cache setup, skip unrelated init, narrow the test scope.)
- Can I make the signal **sharper**? (Assert on the specific symptom, not "didn't crash".)
- Can I make it more **deterministic**? (Pin time, seed RNG, isolate filesystem, freeze network.)

A 30-second flaky loop is barely better than no loop. A 2-second deterministic
loop is a debugging superpower.

### Non-deterministic Bugs

The goal is not a clean repro but a **higher reproduction rate**. Loop the
trigger 100×, parallelise, add stress, narrow timing windows, inject sleeps.
A 50%-flake bug is debuggable; 1% is not — keep raising the rate until it's
debuggable.

## Phase 2: Reproduce

Run your feedback loop and confirm it produces the failure described in the
issue (or error report).

**Critical check**: Verify this is the bug the *issue* describes, not a
different nearby failure. Symptoms can cluster — a timeout might mask a
permissions error, a crash might hide a data corruption bug. Compare your
reproduction output against the issue's specific error message or behavior.

If you cannot reproduce:
- Check environment differences (versions, config, data)
- Try the exact steps from the issue, in order
- Ask whether the bug is intermittent (race condition, resource exhaustion)
- If still not reproducible after 3 attempts, note this in the issue and
  escalate to human review

## Phase 3: Hypothesize

**Before touching any code**, generate 3-5 ranked hypotheses about the root
cause. Each hypothesis must be:

- **Specific**: "The OAuth token refresh logic uses the old endpoint after
  the provider migration" — not "something is wrong with auth"
- **Falsifiable**: You can describe a test or observation that would rule it
  out
- **Ranked**: Most likely first, based on the evidence you have

Write them down. This prevents tunnel-vision on the first plausible
explanation — AI agents are especially prone to latching onto hypothesis #1
and ignoring contradictory evidence.

## Phase 4: Instrument

Test hypotheses one at a time, starting with the most likely.

**Rules**:
1. **One variable per experiment**. Change one thing, observe the result.
   If you change two things and the bug disappears, you don't know which
   change fixed it.
2. **Tagged debug output**: Use `[DEBUG-xxxx]` tags (where `xxxx` is a
   4-character random ID) so cleanup is a single `grep -r "DEBUG-xxxx"`.
3. **Preference order**: debugger > targeted log statements > never "log
   everything and grep"
4. **Record results**: For each hypothesis, note: tested how, result,
   confirmed/refuted.

When a hypothesis is refuted, move to the next one. When confirmed, proceed
to Phase 5.

If all hypotheses are refuted:
- Re-examine the evidence — did you miss something?
- Generate 2-3 new hypotheses based on what you learned
- If still stuck after exhausting the second round, escalate to human review
  with your findings documented (hypotheses tested, results, remaining
  unknowns)

## Phase 5: Fix + Regression Test

1. **Write a regression test first** that captures the exact failure mode
   from Phase 2. This test should fail before the fix and pass after.
   - Follow the project's TDD guide (`references/tdd-guide.md`) for test
     structure
   - The regression test becomes the first "Red" in the TDD cycle
2. **Implement the minimal fix** that makes the regression test pass
3. **Verify the original feedback loop** from Phase 1 now passes
4. **Run the full test suite** to check for regressions

If no correct test seam exists for the regression test (e.g., the bug is in
infrastructure glue, CI config, or a third-party integration), that itself
is a finding. Note it and file a follow-up issue for improving testability
in that area.

## Phase 6: Cleanup + Post-mortem

Before committing, run through this checklist:

- [ ] Original feedback loop from Phase 1 passes
- [ ] `grep -r "DEBUG-"` returns zero hits (all debug instrumentation removed)
- [ ] Any throwaway harness scripts are deleted
- [ ] Root cause is stated clearly in the commit message or PR description
- [ ] Regression test is included in the commit

**Root cause statement**: Write one sentence explaining *why* the bug
happened, not just *what* was wrong. "The retry logic used `>=` instead of
`>` for the max-attempts check, causing one extra retry that exceeded the
rate limit" — not "fixed the retry logic."

If the root cause reveals a systemic issue (missing validation layer,
untested error path, architectural gap), file a follow-up issue via
`/github-kanban` rather than expanding the current fix's scope.

## Escalation

Escalate to human review when:
- You cannot reproduce the bug after 3 attempts
- All hypotheses from Phase 3 (both rounds) have been refuted
- The root cause involves infrastructure, secrets, or permissions you
  cannot inspect
- The fix requires changes outside the current repository's scope

When escalating: comment on the issue with your findings (hypotheses tested,
results, remaining unknowns), move to human review, and stop.
