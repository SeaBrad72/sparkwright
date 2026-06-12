# Code Quality (lean) — Design

**Status:** approved (brainstorm), ready for implementation planning
**Scope:** a deliberately *right-sized* pass — make the kit's quality principles enforceable-where-honest and reviewable, and harden the kit's own code. **Explicitly pulled back** from a 3-slice arc after a strategic check: the kit is already strong on code quality (`gate-lint`, type-checks, test-quality, coverage-ratchet, builder≠reviewer), so this polishes the last 20%, it doesn't fill a hole. One lean slice → **2.58.0**, then pivot to onboarding.

---

## 1. Decisions (from brainstorm)

- **Blended model:** measurable enforcement where a number is honest, a review lens for what a metric can't see, per-stack tooling recs. **Consistency** is an explicit theme (formatters + uniform ceilings-via-linter + uniform review dimensions).
- **No new conditional gates.** Complexity + duplication are **demoted to per-stack linter-config recommendations** (the existing `gate-lint` already enforces them *when configured*) + a review-lens dimension — not two new formal gates. Rationale: the enforcement path already exists (configure `gate-lint`), gating them invites the gaming/noise the kit warns about (same reasoning that keeps test-quality recommended-not-gated), and demote preserves the option to promote later. Zero new conformance surface for ~90% of the value.
- **Kit-own hardening is a regression-lock, not a cleanup.** Verified: `shellcheck` reports **0 findings** across all 46 kit scripts (POSIX + default mode). So there is nothing to fix — the value is *keeping* it clean (today only `dash -n` syntax is checked).

## 2. The two parts (one PR)

### Part A — Kit's own code: a shellcheck regression-lock
- **`conformance/shellcheck.sh`** — runs `shellcheck` over the kit's shell code (`scripts/*.sh`, `scripts/kit-guard`, `conformance/*.sh`, `hooks/pre-push`), failing on any finding at the **error/warning** floor (POSIX `-s sh`). It is **conditional on shellcheck being installed**: if `shellcheck` is absent it prints `SKIP (shellcheck not installed)` and exits 0 (a dev may not have it) — but the **kit CI installs it**, so CI always runs it for real. A `--selftest` proves it (a) passes on a clean fixture and (b) fails on a deliberately-bad fixture (e.g. `SC2086`).
- **Kit-CI step** (control-plane hand-apply) — install shellcheck + run `conformance/shellcheck.sh`. The kit's scripts being already-clean means this goes green immediately and stays a guard against drift.
- Honesty: shellcheck-clean ≠ bug-free; it's a lint floor on the shell code, regression-guarded.

### Part B — Instilling quality (adopter-facing): the review lens + reference
- **`docs/operations/code-quality.md`** (the bulk; uncapped) — the kit's code-quality reference:
  - **The review lens** (dimensions a metric can't gate): readability · simplicity (DRY/YAGNI) · function size & single-purpose · meaningful naming · comment quality (intent not narration) · type/interface design · cohesion/coupling · no dead code.
  - **Complexity & duplication via the existing lint gate** — per-stack config to switch them on (eslint `complexity`/`jscpd`; `radon`/`ruff` for python; `gocyclo`; `clippy` cognitive-complexity; `detekt` for kotlin/JVM; `ktlint`; .NET analyzers) with sane starting ceilings, framed as **recommended `gate-lint` configuration**, not a new gate.
  - **Consistency** — formatters (already mandated) + uniform ceilings + the review lens give cross-codebase consistency; stated as the through-line.
  - Reference review *tools* (the agent patterns): `code-reviewer`, `code-simplifier`, `comment-analyzer`, `type-design-analyzer` — named as optional reference reviewers for the lens, tool-neutral.
- **`templates/CODE-REVIEW-CHECKLIST.md`** — a short, copy-able checklist of the review-lens dimensions for a reviewer (human or agent) to apply at the §7 Review gate. Mirrors the existing sign-off/checklist style (e.g. `A11Y-SIGNOFF`).
- **`DEVELOPMENT-PROCESS.md` §7 Review gate** — a **`+0` fold** naming the code-quality lens on the existing Review-gate row (point to `code-quality.md` / the checklist). PROCESS is at the 470 cap — **must be `+0`** (fold into the existing Review row text), verified by `doc-budget.sh`.
- **Per-stack tooling line** in all 10 profiles + `_TEMPLATE` (the MAINTAINING cross-cutting rule): one line naming the stack's complexity/duplication linter config + the review lens. *(If this pushes a concern, it's profile docs — uncapped — so no budget risk; only the §7 fold is budget-sensitive.)*
- **`conformance/verify.sh`** + `conformance/README.md` rows for `shellcheck.sh`. (No new readiness check for Part B — the lens is review-discipline, not an automatable gate; that is the honest classification.)

## 3. Doc-budget (the constraint, handled)
Core-3 is at 900/900. The ONLY budget-sensitive edit is the §7 review-lens **`+0` fold**; everything else is `docs/operations/`, `templates/`, `profiles/`, `conformance/` (all uncapped). Run `doc-budget.sh` after the §7 edit — it MUST still read 900/900. **No `TOTAL_BUDGET` change** (the SP-2 lesson: never loosen the guardrail to fit a change).

## 4. Honesty
- `shellcheck.sh` green = the shell code passes the lint floor (regression-guarded) — not bug-free.
- The code-quality lens is **review discipline**, explicitly NOT a fail-closed gate — quality genuinely needs judgment a metric can't give; gating it would invite gaming. Stated plainly in `code-quality.md`.
- Complexity/duplication are **recommended `gate-lint` config**, not new gates — the adopter who wants teeth turns them on; the kit shows how.

## 5. Out of scope
A complexity/duplication **conditional gate** (demoted to config rec), a maintainability-index gate (too fuzzy), architectural fitness-functions (heavier, future), and any refactor of kit code (already shellcheck-clean — nothing to fix).

## 6. Definition of Done
- `conformance/shellcheck.sh` (conditional-on-install, error/warning floor, `--selftest` clean+dirty fixtures) + kit-CI step (hand-apply) + the kit's scripts confirmed clean.
- `docs/operations/code-quality.md` (review lens + per-stack complexity/duplication-via-linter recs + consistency + reference reviewers).
- `templates/CODE-REVIEW-CHECKLIST.md`.
- §7 `+0` review-lens fold (budget 900/900 held) + per-stack tooling line across 10 profiles + `_TEMPLATE`.
- `verify.sh` + `conformance/README.md` rows; independent review → SHIP; ratified PR; **2.58.0** release.
- Then: **pivot to onboarding UX** (the next roadmap item).
