# Code Review Checklist (Quality Lens)

> Apply at the §7 Review gate, alongside the correctness + security review. A reviewer (human or agent)
> marks each dimension. This is judgment, not a gate — flag concerns, don't rubber-stamp.

- [ ] **Readability** — a new reader follows it without the author present.
- [ ] **Simplicity (DRY / YAGNI)** — no needless abstraction; no copy-paste that should be one unit.
- [ ] **Function size & single-purpose** — small; one job; early returns over deep nesting.
- [ ] **Naming** — meaningful, intention-revealing (no throwaway names except loop counters).
- [ ] **Comment quality** — explains *why* / intent, not narration; no stale/rotted comments.
- [ ] **Type / interface design** — strong invariants + encapsulation; illegal states hard to represent.
- [ ] **Cohesion / coupling** — one responsibility; internal changes don't ripple to consumers.
- [ ] **Error handling** — structured, with codes; no swallowed errors / silent fallbacks.
- [ ] **No dead code · no debug output · no hardcoded values** that belong in config.
- [ ] **Tests** — meaningful (assert behavior, not implementation); critical paths covered.

**Reviewer:** [name/role] · **Verdict:** [approve / changes requested] · see `docs/operations/code-quality.md`.
