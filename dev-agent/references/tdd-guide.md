# TDD Guide for AI Agents

Test-Driven Development is the primary methodology for this workflow. The issue
body is your specification — tests encode those requirements into executable
assertions before any implementation exists.

TDD matters more for AI agents than for human developers because AI agents are
prone to writing tests that validate their own implementation rather than the
actual requirements. This guide exists to prevent that.

> Examples in this guide use Python — adapt syntax for your project's language.

## Anti-Pattern: Horizontal Slicing

**DO NOT write all tests first, then all implementation.** This treats RED as
"write all tests" and GREEN as "write all code." It produces tests that validate
imagined behavior rather than actual behavior.

```
WRONG (horizontal):
  RED:   test1, test2, test3, test4, test5
  GREEN: impl1, impl2, impl3, impl4, impl5

RIGHT (vertical):
  RED→GREEN: test1→impl1
  RED→GREEN: test2→impl2
  RED→GREEN: test3→impl3
  ...
```

Each test responds to what you learned from the previous cycle. Because you just
wrote the code, you know exactly what behavior matters and how to verify it.

## The Red-Green-Refactor Cycle

Every feature or behavior follows this exact sequence:

### 1. Red — Write a Failing Test

- Read a requirement from the issue specification
- Write a test that asserts the expected behavior
- **Run the test and verify it fails** — this is not optional
  - If the test passes without implementation, it's either trivial, testing
    the wrong thing, or the behavior already exists
  - A test that was never red is not a meaningful test

**Start with a tracer bullet**: Your first Red-Green cycle should prove one
complete behavior end-to-end. This validates the integration path works before
you add more tests. Pick the most representative requirement — not the simplest,
not the hardest — and make it pass.

### 2. Green — Write Minimal Implementation

- Write the simplest code that makes the failing test pass
- "Simplest" means: no optimization, no abstractions, no edge case handling
  beyond what the test requires
- Resist the urge to write production-quality code in this phase — that
  comes next

### 3. Refactor — Clean Up While Green

- Improve code quality while all tests remain passing
- Extract common patterns, improve naming, remove duplication
- If a refactor breaks a test, you've changed behavior — revert and
  investigate
- This is where the code becomes production-quality

### 4. Repeat

Move to the next requirement from the issue. Write a new failing test.

## Anti-Gaming Rules

AI agents frequently "game" TDD in ways that produce tests that pass but
don't actually validate anything useful. These patterns defeat the purpose
of testing entirely.

### No Hardcoded Returns

**The problem**: You write a test that expects `calculate(5) == 25`, then
implement `def calculate(x): return 25`. The test passes but the function
is useless.

**The rule**: After writing a test with one input, immediately write a
second test with different inputs. This forces the implementation to
actually compute the result.

```python
# Multiple inputs force real implementation
def test_square_positive():
    assert square(5) == 25

def test_square_negative():
    assert square(-3) == 9

def test_square_zero():
    assert square(0) == 0
```

### Test Behavior, Not Implementation

**The problem**: Tests that assert on internal method calls, private state,
or execution order break whenever the implementation is refactored, even if
the behavior is correct.

**The rule**: Tests should describe WHAT the code does (inputs → outputs,
side effects), not HOW it does it internally.

```python
# Tests observable behavior, not internal method calls
def test_user_creation():
    service = UserService()
    service.create_user("alice")
    user = service.get_user("alice")
    assert user is not None
    assert user.name == "alice"
```

### Multiple Inputs Per Behavior

**The problem**: A single test case can always be satisfied by hardcoding.

**The rule**: Every distinct behavior needs at least 2 test cases with
different input data. For functions with well-defined domains, consider
property-based tests.

### Mock at System Boundaries Only

**The problem**: Over-mocking creates tests that verify mock configuration
rather than actual behavior. When everything is mocked, you're testing nothing.

**The rule**: Only mock at system boundaries — external APIs, databases, file
systems, network calls, time/randomness. Never mock your own classes, internal
collaborators, or anything you control.

**Do mock**: External HTTP APIs, third-party SDKs, payment gateways, email
services, system clock, random number generators.

**Don't mock**: Your own modules, internal function calls, anything where you
can use the real implementation in a test.

```python
# System boundary — mock is appropriate
@patch("myapp.client.requests.get")
def test_fetch_weather(mock_get):
    mock_get.return_value.json.return_value = {"temp": 72}
    result = fetch_weather("NYC")
    assert result.temperature == 72
```

### No Tests-After-Code

**The problem**: When you write implementation first, then tests, the tests
inevitably mirror the implementation rather than the specification. They
test "does the code do what it does" rather than "does the code do what
it should."

**The rule**: The test must exist and fail before the implementation. If
you catch yourself writing implementation first, stop, delete it, write
the test, verify it fails, then rewrite the implementation.

### Edge Cases Are Requirements

**The problem**: Edge case tests added for coverage metrics rather than
from the specification (e.g., "what if input is None?" when the API
never receives None).

**The rule**: Edge cases should come from the issue specification or from
realistic usage scenarios. Ask: "Can this input actually happen in
production?" If yes, test it. If no, don't add a test just for coverage.

### Prioritize Test Coverage

**You can't test everything.** Focus testing effort on critical paths and
complex logic. Simple getter/setter behavior or straightforward delegation
can be validated by integration-level tests rather than exhaustive unit tests.
Ask: "If this behavior breaks silently in production, how bad is it?" Test
the high-consequence paths thoroughly; test the trivial paths lightly or
through broader integration coverage.

### Property-Based Tests Where Applicable

For functions with well-defined properties, use property-based tests — the
infinite input domain makes hardcoding impossible.

```python
from hypothesis import given, strategies as st

@given(st.integers())
def test_square_always_non_negative(n):
    assert square(n) >= 0
```

## Test Quality Checklist

Before committing, verify:

- [ ] Every test has a descriptive name expressing the requirement it validates
- [ ] Each test was verified to fail before its implementation existed (Red)
- [ ] No hardcoded return values in the implementation
- [ ] Each behavior has at least 2 test cases with different inputs
- [ ] Mocks are used only at system boundaries (external APIs, databases, network)
- [ ] Edge cases come from the spec or realistic scenarios, not coverage padding
- [ ] Tests are independent — no shared mutable state between tests
- [ ] Running the full test suite passes, not just the new tests

## When TDD Doesn't Apply

Some changes don't benefit from TDD:

- **Documentation-only changes**: No behavior to test
- **Configuration changes**: `.env`, `pyproject.toml` — verify by running the app
- **Pure UI/styling changes**: Use `/playwright-cli` for visual verification instead
- **Dependency updates**: Run existing tests to verify compatibility

For these, skip the TDD cycle but still run the full test suite in Phase 7.
