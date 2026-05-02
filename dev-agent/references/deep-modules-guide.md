# Deep Modules Guide

Design modules that hide complexity behind simple interfaces. A module that
absorbs complexity is worth its weight; a module that merely shuffles it around
is overhead. This guide gives you the vocabulary and rules to tell the difference.

## Core Vocabulary

- **Module** — anything with an interface and an implementation: function, class,
  package, slice. Scale-agnostic.
- **Interface** — everything a caller must know: types, invariants, error modes,
  ordering, config. Not just the type signature.
- **Implementation** — the code inside.
- **Depth** — leverage at the interface. Deep = lots of behavior behind a small
  interface. Shallow = interface nearly as complex as the implementation.
- **Seam** — where an interface lives; a place behavior can be altered without
  editing in place.
- **Adapter** — a concrete thing satisfying an interface at a seam.
- **Leverage** — what callers get from depth.
- **Locality** — what maintainers get from depth: change, bugs, knowledge
  concentrated in one place.

## Key Principles

1. **Deletion test**: imagine deleting the module. If complexity vanishes, it was
   a pass-through. If complexity reappears across N callers, it was earning its
   keep.
2. **The interface is the test surface.** Callers and tests cross the same seam.
3. **One adapter = hypothetical seam. Two adapters = real seam.** Don't introduce
   a seam unless something actually varies across it.
4. **Depth is a property of the interface, not the implementation.** A deep module
   can be internally composed of small parts — they just aren't part of the
   interface.

## Deep vs Shallow Module Diagrams

```
Deep module (GOOD):              Shallow module (AVOID):
┌─────────────────────┐          ┌─────────────────────────────────┐
│   Small Interface   │          │       Large Interface           │
├─────────────────────┤          ├─────────────────────────────────┤
│                     │          │  Thin Implementation            │
│  Deep Implementation│          └─────────────────────────────────┘
│                     │
└─────────────────────┘
```

## Interface Design for Testability

1. **Accept dependencies, don't create them** (dependency injection)
2. **Return results, don't produce side effects**
3. **Small surface area** — fewer methods = fewer tests needed
