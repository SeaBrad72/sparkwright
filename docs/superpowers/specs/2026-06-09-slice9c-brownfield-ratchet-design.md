# Slice 9c — Brownfield Ratchet & Waiver (design)

**Date:** 2026-06-09 · **Arc:** Slice 9, Tier 1 (adoption reach) · **Version target:** MINOR → **v2.27.0**
**Input:** the review's brownfield persona P0 ([2026-06-09-independent-multiagent-review.md](../reviews/2026-06-09-independent-multiagent-review.md)) — a real legacy repo already fails coverage / dep-vuln / SBOM / branch-protection on day one, and `docs/adoption/brownfield.md` has no ratchet/waiver/baseline path, forcing adopters to either abandon the kit or silently weaken its gates.

## Problem

The DoD requires 80% coverage + 7 blocking gates on every PR (`DEVELOPMENT-STANDARDS.md` §14). A brownfield repo arrives below that. With no sanctioned incremental path, the honest adopter is pushed to fake green (disable a gate) — the exact failure the kit exists to prevent. The kit already has a **governed-exception** concept (time-boxed, security-owner-ratified gate waivers — `docs/enterprise/ratification-rbac.md`, the audit-evidence exception register), but it is not operationalized for adoption and has no concrete template or check.

## Design — make "not yet, here's the plan" a tracked, expiring, owned artifact

Replace binary "comply or fake it" with a recorded exception that is **visible, time-boxed, owned, and machine-validated**. Four pieces.

### 1. `templates/WAIVER-REGISTER.md`

A per-project register operationalizing the existing governed-exception process. One row per active waiver with required fields:

`Gate | Reason | Owner | Opened (YYYY-MM-DD) | Expires (YYYY-MM-DD) | Remediation plan | Ratified-by`

Header states:
- **Non-negotiable gates (NEVER waivable, even at adoption):** `secret-scan` (never ship secrets) and `branch-protection` (segregation of duties). A waiver naming either is invalid.
- **Waivable during the adoption window:** coverage, SBOM/provenance, dependency-vulnerability, a11y, container-image — each with an owner, a remediation plan, and an expiry.
- **Max lifetime: 90 days.** A waiver's `Expires − Opened` may not exceed 90 days; renewal requires re-ratification (a new row).
- A worked example row + an empty template row.

### 2. `conformance/waivers-valid.sh`

Executable validation (the 9a lesson — make the honesty enforceable). Given a project's `WAIVER-REGISTER.md`:
- **FAIL** if any waiver is **expired** (`Expires` < today).
- **FAIL** if any waiver targets a **non-negotiable gate** (`secret-scan`, `branch-protection`).
- **FAIL** if any active waiver is missing a required field (owner / expiry / remediation / ratified-by).
- **FAIL** if `Expires − Opened > 90` days.
- **N/A-pass** when no `WAIVER-REGISTER.md` exists (greenfield needs none) — conditional, like the other adoption-conditional checks.
- `--selftest` with deterministic fixtures (expired=2020-01-01, valid=2099-01-01, a non-negotiable-gate waiver, an over-90-day span, a missing-field row).
- Portable: POSIX sh; a `to_epoch` helper tries GNU `date -d` then BSD `date -j -f` (the kit ships to both). Today via `date +%Y-%m-%d`; expiry compare via lexicographic `YYYY-MM-DD` string order (no arithmetic) for the expired check; epoch only for the 90-day span.
- Takes an optional path arg (default: `./WAIVER-REGISTER.md`), mirroring the other conformance scripts.

### 3. `scripts/coverage-ratchet.sh`

Stack-neutral "no-regression-below-baseline" for the coverage gate during adoption:
- Usage: `sh scripts/coverage-ratchet.sh <current-percent> [baseline-file]` (default baseline file `.coverage-baseline`).
- Adopter extracts their current coverage number per their stack (the script is stack-agnostic — it only compares numbers) and pipes it in.
- **PASS** if `current >= baseline` (ratchet holds or improves); on improvement, prints the new floor so the adopter can bump the baseline.
- **FAIL** if `current < baseline` (regression) — coverage may not drop during the ramp.
- If no baseline file: seeds it from `current` (first run records the floor) and passes, printing guidance.
- Integer/decimal-tolerant compare (awk); POSIX sh; `--selftest`.
- This lets a 40%-coverage legacy repo adopt with a 40 floor and ratchet up, instead of hitting an absolute-80 wall — while the absolute-80 DoD remains the target the waiver's remediation plan drives toward.

### 4. `docs/adoption/brownfield.md` §5 + contract tie-in

New section **"§5 Adopting when you already fail the gates"**:
- The **ramp**: record a baseline → open time-boxed waivers for the gaps → tighten on a schedule → close waivers as each gap is fixed.
- The **non-negotiable vs deferrable** split (secret-scan + branch-protection are day-one; the rest are waivable).
- How to use `WAIVER-REGISTER.md`, `waivers-valid.sh`, and `coverage-ratchet.sh` together.
- A **recommended tightening schedule** (e.g. secret-scan + branch-protection day one; lint/type/build week one; coverage ratchet from baseline, +N points per sprint to 80%; SBOM/provenance + dep-vuln within the 90-day window).
- One-line tie-in in `DEVELOPMENT-PROCESS.md` (governed-exception → this register) and `DEVELOPMENT-STANDARDS.md` §14 (the gates are blocking, EXCEPT under a tracked, expiring, ratified brownfield waiver — never silently).
- `conformance/README.md`: index rows for `waivers-valid.sh` ([control] — it validates a governed-exception control) + a note; `verify.sh` does not run it unconditionally (adoption-conditional).

## Files

| File | Change |
|------|--------|
| `templates/WAIVER-REGISTER.md` | **New** — governed-exception register (fields, non-negotiable set, 90-day cap, example) |
| `conformance/waivers-valid.sh` | **New** — validate register (expired / non-negotiable / fields / 90-day); N/A-pass; `--selftest`; portable dates |
| `scripts/coverage-ratchet.sh` | **New** — stack-neutral no-regression-below-baseline; seed-on-first-run; `--selftest` |
| `docs/adoption/brownfield.md` | New §5 adoption ramp; update §4 residual-gaps to point at it |
| `DEVELOPMENT-PROCESS.md` | One-line governed-exception → brownfield-register tie-in |
| `DEVELOPMENT-STANDARDS.md` §14 | Note: gates blocking EXCEPT under a tracked/expiring/ratified waiver (never silent) |
| `conformance/README.md` | `waivers-valid.sh` index row + adoption-conditional note |
| `CHANGELOG.md`, `VERSION` | 2.27.0 |
| `docs/ROADMAP-SLICE9.md` | Mark 9c done |
| `.github/workflows/ci.yml` | (batch-closeout, human-applied) add `waivers-valid.sh --selftest` + `coverage-ratchet.sh --selftest` |

## Verification
- `sh conformance/waivers-valid.sh --selftest` → OK (expired/non-negotiable/over-90/missing-field all FAIL; valid passes; no-register N/A).
- `sh scripts/coverage-ratchet.sh --selftest` → OK (regression FAILs; hold/improve passes; seed-on-first-run).
- Run `waivers-valid.sh` against the new template itself → its example must be valid (or the template uses a far-future expiry so it doesn't rot; document that the example is illustrative).
- dash-clean both scripts; `check-links.sh` green.
- Governance: feature branch → PR → human ratification; §14/§13 contract edits get the security-owner lens (governed-exception is a governing surface).

## Out of scope
- Per-stack coverage extraction (the ratchet is deliberately number-in; the profile documents how to get the number).
- Auto-opening waivers during `incept.sh` brownfield run (could be a later enhancement; 9c ships the mechanism + the ramp doc).

## Known implications
- The non-negotiable set is policy: secret-scan + branch-protection can never be waived. If an adopter's secret-scan legitimately can't run day one, that is a hard blocker by design (ship no secrets), not a waiver.
- `waivers-valid.sh` uses real "today" for the expired check — a waiver expires on its date with no grace; renew before expiry.
