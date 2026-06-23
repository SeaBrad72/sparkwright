# E-series consolidation audit — pivot from "build E3" to "consolidate first"

**Date:** 2026-06-23 · **Status:** ratified (owner) → executing Tier 1
**Trigger:** owner challenge ("are we making poor design decisions? when do we go back and refactor?") after catching two reactive-not-proactive misses (E4f flaw, "opinion only when asked"). Decision: a **targeted adversarial design-audit before committing to E3** (the biggest new surface).

## Method
Four independent, adversarial auditors (opus, read-only, mandated to *hunt* and default-to-critical), one per dimension: (1) scope & coherence, (2) conformance architecture & debt, (3) E-series decisions, (4) adoptability & honesty. Full per-dimension findings: `scratchpad/audit/dim{1..4}-*.md` (gitignored). The most concrete claims were **independently verified** before acceptance (below).

## Verdict — convergent: CONSOLIDATE before E3
All four said do **not** dive into E3; even the mildest (conformance) said "fix criticals + narrow consolidation first." The errors are at the **portfolio** level, not the craft level — individual slices were well-built (TDD, builder≠reviewer, security-review caught a real bug nearly every slice). The pattern: **the kit accreted rigor faster than it validated fit or retired ceremony**, and was about to stack the biggest surface (E3) on top.

## Findings

### Confirmed (verified directly, not just asserted)
- **F1 — Over-promise on Quickstart step 1.** README says "**242 files** … down from **392**"; reality: `adopter-export.sh --profile typescript-node` produces **277**, and HEAD tracks **416**. `conformance/adopter-export-wired.sh` checks prune+link-safety but **never asserts the count**, so it drifted green as E2/E4 files were added since S3 (v3.33.0 set 242). The integrity backbone missed the most adopter-visible falsehood.
- **F2 — Push CI is diagnostically blind.** On push, all 29 claims are verified **only** via `conformance/claims-registry.sh` (ci.yml:242) running each verifier as `sh -c "$v" >/dev/null 2>&1`; the rich three-state `verify.sh --require` is **not** run on push (deferred to the drift-watch timer). It is fail-*closed* (exit-2 UNVERIFIED collapses to FAIL), but swallows all diagnostics and erases the three-state signal.

### High-confidence (audit, consistent with known state)
- **F3 — Never externally adopted** (n=2 synthetic dogfoods, same author) — and the candid maturity caveat lives in `ROADMAP-KIT.md`, which is **export-ignored**, i.e. *stripped from the package adopters receive*, while README/EXEC-BRIEF promise "anyone … production-grade."
- **F4 — "PROVEN" over-claimed at headline/CHANGELOG/badge altitude** — containment proven on 1 of 7 profiles; runtime-security = 4 header greps on a 3-route toy server; SoD = a pure-logic selftest. In-*doc* honesty boundaries are genuinely good; the headline verbs don't carry them.
- **F5 — Build-ahead-of-need (the sequencing error).** Of E3 §10's 7-item containment contract that *sized E4*, only ~1–2 are cleanly proven; the **fleet-specific** controls that actually matter for E3 — per-agent FS isolation (#1), conflict-safe writes (#6), runaway kill-switch (#5), fleet-scale guard (#7) — are exactly the ones deferred/unbuilt. E4 hardened the perimeter of an empty building and proved one room of seven.
- **F6 — The kit grows by appending, never retiring.** 238-line ROADMAP accretion log; a one-way conditional-obligations ratchet (never an N/A retired); `doc-budget` guards 3 of ~140 docs; 9 of 10 profiles unproven end-to-end. The kit's own "rituals that lose their rationale die" lens has never been turned on itself.
- **F7 — Conformance debt.** ~70–88% boilerplate across ~69 conformance files (selftest harness + arg-parsing duplicated); the registry is the declared SPOF; `*-wired` checks verify that a golden-path job is *named*, not that it *runs and gates* (declaration-of-behaviour — link 1 of a 3-link chain).

## Consolidation slate (replaces "build E3 now")
- **Tier 1 — Honesty (cheap, high trust-ROI) — IN PROGRESS.** ✅ **F1 (v3.47.1):** README no longer hardcodes the drifting file count (defers to the export script) + `adopter-export-wired.sh` locks against a hardcoded count reappearing. Remaining: README maturity-disclosure shipped to adopters (F3); surface the never-adopted caveat in *exported* docs (F3); down-grade over-claimed "PROVEN" verbs to single-reference reality (F4).
- **Tier 2 — Real validation (the actual gap-closer).** A real external adopter, or a from-scratch maintainer run of the *current* Quickstart (would have caught F1 + the R3 doctor drift). Closes the n=2-synthetic gap (F3).
- **Tier 3 — Right-weight (the E10 lens).** Turn the kit's ceremony-vs-leverage lens on the 14 epics / 12 gates / 25 templates / ~140 docs / the ratchet (F6); retire and merge; decide the release line.
- **Tier 4 — Conformance hardening (F2, F7).** Real `verify` on push (restore diagnostics + three-state); extract the selftest harness into `wf-helpers.sh` (the honest refactor target — *not* the per-check verdict logic); the deferred conformance-carve.
- **Then reassess E3** — it may shrink or change shape after right-weighting.

## Meta-lesson (banked)
The reactive-not-proactive gap (flagged in memory for *security*) also applies at *strategy*: default mode was "execute the ratified plan," not "continuously re-question whether the plan is right." The owner had to prompt the reconsideration twice. Standing correction: run an adversarial design-audit at epic boundaries *before* committing to the next big build, not after.
