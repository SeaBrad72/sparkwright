# Meta-Control Panel #35 — non-vacuity continuous gate

**Slice:** automatic mutation testing of conformance checks
**Version:** 3.83.0 → 3.84.0 · **Trigger:** per-slice (banked item, reaffirmed by panel #34 RETRO) · **Profile:** light (5-lens) + global cross-check · **Date:** 2026-07-01

## VERDICT: **GO**

0 blockers · 0 unaddressed highs · 2 Low routed. Every load-bearing claim in the 3-pass build ledger was independently reproduced on a fresh clone. The accumulated fixes across v1→v2→v3 **cohere**: no later fix undermined an earlier one, and the security-critical property (no false-KILL) holds on the real tree.

---

## Independently reproduced (fresh clone, v3.83.0 → apply.py → v3.84.0)
- apply.py = 10 files, harness byte-identical, idempotent no-op re-run; `guard-core.sh`/`guard.sh` absent; version finishing coherent; control count 38 → **39**.
- `--selftest` **5/5** self-teeth PASS (incl. the two ex-exploit fixtures: stray-`}`/`fi`-in-oracle → KILLED for the right reason; sibling-sourcing → KILLED at run location).
- **Harness-flip:** force `judge`→always-KILLED → the selftest FLIPS to FAIL (exit 1) — the kill-detector is genuinely load-bearing, not a constant.
- **Live sweep:** 25 killed · 0 survived · **7 uncovered** · 0 error, exit 0 (byte-matches BUILD-REPORT).
- **THE BITE on the real tree:** vacuified `version-tag-coherent` (a sibling-sourcing check the old `$0` bug used to false-KILL; its selftest stays green) → **SURVIVED / RESULT: FAIL / exit 1**. The security-critical direction works on the real tree.
- **Temp-leak closed:** 0 `.nv-*` leftovers after a full sweep; `mode-enforcement-blind` PASS (unpoisoned).
- Wiring mirrors `meta-control-fresh` (per-PR `--selftest` only; drift-watch bare-sweep as a separate job; doctor advisory `|| true` never gates); `PASS: non-vacuity-gate`; `verify --require` 39/0; shellcheck/`dash -n` clean.

## The 5 lenses + global cross-check
1. **Scope/altitude — right-weight.** One high-value operator (FAIL-path neuter), control-set-first, one new claim, no guard change — matches the design MVP. The heavy iteration hardened *safety* (fail-safe conservatism), it did not bloat scope.
2. **Proof integrity — HELD.** Harness `--selftest` load-bearing (flip-proven); sweep fails only on a certain SURVIVED.
3. **Honest ceiling — truthful + complete.** 7/32 UNCOVERED disclosed per-check (2 no-idiom, 1 no-selftest-region, 1 context/run-location, 3 CTL-only), never spun as full coverage; the FAIL-path-operator-class + heuristic-region + weekly-cadence + equivalent-mutant limits stated consistently across header/CHANGELOG/sweep-footer.
4. **Coherence/drift — HELD.** Faithful `meta-control-fresh` mirror; claim registered in all three loci; control count 39.
5. **Ship-readiness — HELD.** Version finishing coherent; idempotent; no half-land; guard untouched; zero temp leftovers.
6. **GLOBAL CROSS-CHECK — the 3 passes cohere.** No residual false-KILL path is reachable: a KILL structurally requires the certainty guard's ctl-copy to pass at run location first, so self-scanning/context-fragile checks route to enumerated UNCOVERED, never a false verdict. The fail-safe invariant ("KILLED only when CERTAIN; every uncertainty → loud enumerated UNCOVERED; fail only on a certain SURVIVED") is enforced structurally, not by assertion. Trustworthy as the standing backstop **today**.

## Ledger 2 — fix-forward (both Low, both homed)
- **F-nv-1 (Low → ROADMAP):** widen operators (`grep -q`→`true`, condition negation, post-oracle idiom coverage) to drive 7/32 UNCOVERED down — the highest-value next increment on this harness. Not blocking: every gap is enumerated, never silent.
- **F-nv-2 (Low → banked note):** the harness cannot mutation-test itself in the live *sweep* (reports its own as CTL-only UNCOVERED); its own non-vacuity lives in `--selftest` (flip-proven, per-PR). Worth a one-line note; fold into F-nv-1.

## Retro (the adjust step)
This slice **closes the loop panels #33/#34 opened** — the third instance of "a passing selftest is not a load-bearing selftest," caught each time by manual flip-testing. The per-slice manual flip discipline now has a standing automated backstop. Two lines going forward: (a) the manual "mutation-prove every selftest / one carve-out phrase per line" discipline stays the *first* line (the gate is weekly, not per-PR-instant); (b) the gate is the *second* line. The kit's non-vacuity law is now **proven, not prescribed** — the truest expression of "proven, not provided" applied to the kit's own machinery.
