# Code Quality — Review Lens, Complexity & Consistency

The kit already enforces a lot of quality mechanically: `gate-lint` (per-stack formatter + linter),
`gate-type-check`, `coverage-ratchet` (no-regression coverage), the pre-commit inner loop
(`dev-inner-loop.md`), and **test-quality** (mutation/property — `test-quality.md`). This file adds
the two things a metric can't fully cover: a **review lens** (judgment) and a **consistency** through-line,
plus how to switch on complexity/duplication via the lint gate you already have.

## The code-quality review lens (§7 Review gate)

At the Review gate, a reviewer (human or agent) checks dimensions a gate can't honestly score —
use `templates/CODE-REVIEW-CHECKLIST.md`:

- **Readability** — a new reader follows it without the author.
- **Simplicity (DRY / YAGNI)** — no needless abstraction; no copy-paste that should be one thing.
- **Function size & single-purpose** — small, one job; prefer early returns over deep nesting.
- **Naming** — meaningful; intention-revealing; no throwaway names (except loop counters).
- **Comment quality** — comments explain *why* / intent, not narrate the code; no comment-rot.
- **Type / interface design** — strong invariants, encapsulation; the type makes illegal states unrepresentable.
- **Cohesion / coupling** — a unit does one thing; changing internals doesn't ripple.
- **No dead code, no debug output, no hardcoded values** that belong in config.

These are **review discipline, not a fail-closed gate** — quality genuinely needs judgment, and gating it
would invite gaming. Reference reviewers (tool-neutral): `code-reviewer`, `code-simplifier`,
`comment-analyzer`, `type-design-analyzer` agent patterns can apply the lens.

## Complexity & duplication — configure the lint gate you already have

These ARE measurable, but they're **recommended `gate-lint` configuration**, not new gates (the existing
`gate-lint` enforces them when switched on; gating them separately invites the gaming/noise that keeps
test-quality recommended-not-gated). Turn them on per stack with sane starting ceilings:

| Stack | Complexity | Duplication |
|-------|-----------|-------------|
| typescript-node | ESLint `complexity` (≤10) / `sonarjs/cognitive-complexity` | `jscpd` |
| python · ml · data-engineering | `ruff` `C901` (mccabe) / `radon cc` | `jscpd` / `pylint` similarities |
| go | `gocyclo` / `gocognit` (via golangci-lint) | `dupl` (golangci-lint) |
| rust | `clippy::cognitive_complexity` | `jscpd` |
| java-spring · kotlin | `detekt` ComplexMethod / Checkstyle CyclomaticComplexity | `detekt` / CPD (PMD) |
| dotnet | Roslyn analyzers / SonarAnalyzer | `jscpd` |
| terraform | tflint / Checkov (policy is the bar) | `jscpd` (HCL) |

Start at a ceiling, ratchet down — a high number flags "refactor me," not "fail the build" (tune per project).

## Consistency (the through-line)

Cross-codebase consistency comes from three things together: **formatters** (already mandated — one style,
zero debate), **uniform complexity ceilings** (the same "too complex" everywhere), and the **same review
lens** applied at every PR. Consistency is a quality property, not a separate gate — it falls out of these.

## Honesty

A green lint/complexity run proves thresholds were met, not that the code is good; the review lens proves a
reviewer *looked*, not that they were right. Necessary, not sufficient — quality is earned at review, not asserted.
