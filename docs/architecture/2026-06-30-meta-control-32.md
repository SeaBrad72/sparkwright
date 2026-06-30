# Meta-control panel #32 — Promotion-Contract Slice 2 (change-class derivation + surfacing)

**Date:** 2026-06-30 · **Version:** 3.80.0 → 3.81.0 · **Cadence:** light (5-lens) per-slice M verdict (A5)
**Epic:** Proportional Promotion Contract (Slice 2 of ~4; Slice 1 shipped v3.76.0).
**Verdict: GO**

## Slice summary

Builds the **advisory** change-class classifier + promotion-readiness surfacing: `conformance/promotion-readiness.sh` (producer) + `conformance/promotion-readiness-wired.sh` (lock), claim `promotion-readiness`. Classifies a change-set **control-plane > sensitive > ordinary** (highest wins), **fail-safe UP** (empty/unreadable/degraded-guard → control-plane), **derived never self-asserted**. Reuses the guard's `is_control_plane_path` (sourced from `.claude/hooks/guard-core.sh`, not duplicated). Emits a 6-field surfacing; *proven-vs-attested* reuses `verify.sh`'s `[control]` vs `[doc]` split. **No enforcement** — the producer exits `0` always; proportional gates are Slice 3.

## 5-lens

| Lens | Finding |
|------|---------|
| **Direction/proportion** | On-contract: implements the ratified epic's Slice 2 exactly. Advisory-only keeps the dangerous capability (a fail-closed gate) isolated in Slice 3. `conformance/` placement avoids a `guard-core.sh` edit (the #2-watch high-risk file). Right-weighted. |
| **Correctness** | `reviewer` → **APPROVE-WITH-NITS**. Empirically verified: classifier + fail-safe, all 15 disposition cells, command-sub isolates the loop var, clone-apply idempotent. 2 Minors folded. |
| **Security** | `security-reviewer` → **PASS**. Fail-safe-UP holds under adversarial input (no downgrade vector found); no injection (data-only loop, no eval); no secret exposure; two-matcher guard coverage intact (no guard-core edit); claim honest. 1 Low folded. |
| **Non-vacuity** | Lock selftest **7 cases**, mutation-proven twice (always-ordinary classifier → cp/sens/mix + downgrade-negatives FAIL; remove fail-safe → empty/missing FAIL) + teeth on the installed artifact. |
| **Coherence** | Clone-proven green: lock selftest / claims-registry (new claim verifies) / ci-selftest-coverage (lock wired) / shellcheck / actionlint / `verify --require` (RESULT OK). Idempotent. |

## Folds applied in-slice (from the dual review)

- **(security L1)** `set -f` noglob around the aggregate loop — a `--changed` line containing `*` no longer glob-expands against cwd (the same class that bit the prior golden-path-parity slice); count/listing now consistent.
- **(correctness Minor 1)** sensitive set is now a **superset of the guard's own secret set** — added `*id_rsa*|*id_ecdsa*|*id_ed25519*|keys/*` so SSH private keys classify `sensitive`, not `ordinary` (closed a fail-*down* before Slice 3's gate consumes the seam); + an `id_rsa` lock fixture (now 7 cases).
- **(correctness Minor 2)** `--changed`/`--rung` with no value now emits a clean **exit 2** usage error instead of the non-portable `shift 2` abort.

## Routed / banked (non-blocking)

- **non-vacuity-continuous-gate** (owner-flagged this session) — automate the mutation/non-vacuity check as a continuous CI gate rather than a per-slice discipline. Banked in `docs/ROADMAP-KIT.md`.
- The classifier remains **fail-safe, not omniscient** — a novel sensitive path outside the (now superset-of-guard) heuristic classifies `ordinary` until Slice 3's reviewer-confirmation. Disclosed honest ceiling.

## Ship conditions

- Governance close (marker `3.81.0 GO` + this log row) is human-run (M2-S5).
- Solo control-plane ship: admin-merge sanctioned when `conformance` is green and the only red is `control-plane-ratification` (by-design).

## Next in the epic

**Slice 3 — proportional gates** (class×rung-conditional gate/keystroke requirements; `control-plane-ratification` emits the team/solo state label). Guard-touching, fail-closed — a strong candidate for **subagent-driven** build (different mind builds vs reviews) per the execution-mode discussion this session.
