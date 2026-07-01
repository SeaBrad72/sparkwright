# Non-vacuity continuous gate — automatic mutation testing of conformance checks

**Date:** 2026-07-01
**Status:** Owner-approved (design gate passed 2026-07-01)
**Roadmap:** `docs/ROADMAP-KIT.md` banked follow-on `non-vacuity-continuous-gate` (owner-flagged highest-value testing hardening). Freshly motivated: Promotion-Contract S3 and S4 both nearly shipped a *vacuous* conformance check, caught only by manual flip-testing (panel #34: "third instance of 'a passing selftest is not a load-bearing selftest'").
**Change-class:** Control-plane (new conformance harness + CI workflow + doctor) → human-ratified; built AMBER.

---

## Problem

The kit's non-vacuity law — *every check's `--selftest` must FAIL when the check mechanism is neutered* — is enforced today as a **per-slice manual discipline** (author + reviewer mutate each check by hand). Nothing re-checks that a **shipped** check *stays* load-bearing, so an innocent later edit can silently gut a check while its selftest stays green. `verify.sh --selftest` asserts only that **≥1** `[control]` PASSes globally — not that any given check bites. This is a standing integrity gap, and S3/S4 are concrete evidence it recurs.

## Solution — mutation testing, applied to the checks

This is **mutation testing** (the mature discipline behind PIT / Stryker / mutmut), applied with the *conformance check* as the code-under-test and its *`--selftest`* as the oracle: **mutate the check's logic; run its `--selftest`; a surviving mutant (selftest still passes) = a vacuous check.**

**Why automatic/generic, not author-declared** (the ratified design decision): generic mutation is **author-independent** — it doesn't ask the same author whose vacuity we're catching to name the weakness (declared-kill is circular and only *attests*; generic *proves*, adversarially). It also carries **zero per-check authoring burden** and grows coverage for free as checks are added. This is the truest automation of the kit's non-vacuity law and pure "proven, not prescribed."

---

## Design

### The harness — `conformance/non-vacuity.sh`
For each targeted check `C` with a `--selftest`:
1. **Locate the selftest region** — the `selftest()` function body OR the `--selftest` case/if arm (the two kit conventions). Mutation is applied to the **check-logic region only** (everything outside the selftest region), so the oracle's fixtures/assertions are never corrupted.
2. **Apply the mutation operator(s)** to a temp copy (never the real file).
3. **Run the mutated copy's `--selftest`.** The mutant is **KILLED** iff the selftest now exits non-zero; it **SURVIVES** iff the selftest still exits 0.
4. **Survivor ⇒ vacuity** — the check is flagged (named, with the surviving operator), and the gate fails.

### Mutation operator (MVP — one high-value, syntax-safe operator)
The empirically-observed vacuity mode (S3/S4) is *"the check can no longer emit FAIL."* So the MVP operator **neuters the check's FAIL path** — the primary verdict-emission idioms, applied in the check-logic region:
- `return 1` → `return 0`, `exit 1` → `exit 0`
- FAIL-accumulator assignments `fail=1` / `st=1` / `rc=1` → `…=0`

This single operator is **syntax-preserving** (no crash-kills) and captures the core question: *"if I make your check incapable of failing, does your selftest notice?"* A non-vacuous selftest **must** have a negative fixture expecting FAIL; neutering the FAIL path flips that fixture to PASS, and the selftest catches it. Additional operators (`grep -q`→`true`, condition negation) are a **banked follow-on**, not MVP — a small high-value set beats a kitchen sink.

### Kill semantics + crash safety
A mutant that dies from a **syntax/parse error** is a false "kill" (it proves nothing about the selftest) and is the dangerous direction (it could hide a survivor). The MVP operator is chosen to be syntax-preserving specifically to avoid this. The harness additionally **sanity-runs the un-mutated `--selftest` first** (must pass) so a pre-broken check isn't misread.

### The harness's OWN non-vacuity (self-teeth)
A `--selftest` on `non-vacuity.sh` itself with two fixtures: (a) a **genuinely load-bearing** check → its FAIL-path mutant is KILLED (harness reports PASS); (b) a **deliberately vacuous** check (a selftest whose negative fixture doesn't actually depend on the mechanism) → its mutant **SURVIVES** (harness reports FLAGGED). If (b) isn't flagged, the harness itself is vacuous.

### No silent skips (honest coverage)
A check the harness **cannot mutate** (no FAIL-path idiom found in its check region, or an unrecognized structure) is **reported as `UNCOVERED`**, never silently passed — the "no silent caps" discipline. Uncovered count is surfaced; driving it down is future work, not a hidden gap.

### Placement (mirrors `meta-control-fresh.sh` exactly)
- **drift-watch (weekly)** — a new job runs the **full live sweep** over the targeted set (the enforcement point; a survivor fails the job — the loud circuit-breaker). Not per-PR: mutating + re-running dozens of selftests is too slow for every push.
- **doctor (advisory)** — a `scripts/doctor.sh` metric surfaces the current vacuity/uncovered count.
- **per-PR CI** — runs only `non-vacuity.sh --selftest` (the *mechanism* self-check + the self-teeth), **not** the live sweep — so an unrelated PR is never gated by the sweep, and the harness's own correctness is proven every PR.

### Scope — engine generic, wiring validated on the control set first
The engine is generic (any `--selftest` check is a candidate). The **initial targeted set = the curated `verify.sh` control checks** — the checks whose vacuity is most dangerous — to validate the operator + region-detection on real checks before it scales. Sampling (N-per-run) is available if drift-watch cost grows, but a weekly sweep of ~38 checks × one operator is cheap.

---

## Honest ceiling (stated up front)
- The gate proves each targeted selftest **catches the FAIL-path-neuter operator class** — *not* every conceivable weakness. Equivalent mutants and un-modelled failure modes are out of reach (the standing mutation-testing limit). It is a strong **automated floor**, not a completeness proof. Stated plainly in the harness header + CHANGELOG.
- **UNCOVERED checks are surfaced, not silently passed** — coverage is honest and grows over time.
- It runs **weekly**, so a vacuity introduced mid-week surfaces at the next sweep, not instantly (acceptable — the per-slice manual discipline remains the first line; this is the standing backstop).

## Files touched (all control-plane → AMBER)
- `conformance/non-vacuity.sh` — **new** harness (mutation engine + region detection + live sweep + `--selftest` with self-teeth).
- `.github/workflows/drift-watch.yml` — new `non-vacuity` job (weekly live sweep).
- `scripts/doctor.sh` — advisory metric (mirror the `meta-control-fresh` block).
- `conformance/claims.tsv` + `conformance/claims-registry.sh` `REQUIRED_IDS` — new claim `non-vacuity-gate` (verifier = `non-vacuity.sh --selftest`, the per-PR mechanism check; the live sweep is drift-watch's job — mirrors how the drift-watch gates register).
- Per-PR CI wiring for `non-vacuity.sh --selftest` (wherever `meta-control-fresh.sh --selftest` runs per-PR).
- `VERSION` · `README.md` · `CHANGELOG.md` — version finishing (3.83.0 → 3.84.0), folded into apply.py.

**Explicitly NOT:** no change to any existing check's *logic*; no `guard-core.sh` change; no per-check declared-kill headers (author-independent by design).

## Build & review plan
- **Build:** subagent-driven (engineer) — it's a real harness + control-plane wiring; different mind builds vs. reviews. Dogfood `plan`. AMBER apply.py, clone-proven — including a **live-sweep dry run over the real control set** (prove it flags a deliberately-vacuified real check and passes the rest).
- **Review:** dual — `reviewer` (mutation/kill logic correctness; region detection; no false-kill from crashes; idempotent wiring) + `security-reviewer` (can the harness be gamed to hide a survivor? does mutating a temp copy ever touch the real tree? does the sweep run untrusted code — no, it runs the kit's own checks).
- **Meta-control:** panel #35; governance close separate.
- **Ship:** standard flow.

## Acceptance criteria
1. `conformance/non-vacuity.sh` mutates the FAIL-path of a targeted check's logic region (not its selftest region), runs the selftest, and reports KILLED/SURVIVED/UNCOVERED per check.
2. Its `--selftest` is **non-vacuous**: the load-bearing-check fixture's mutant is KILLED and the deliberately-vacuous fixture's mutant SURVIVES (flagged); breaking the harness's kill-detection flips the selftest to FAIL.
3. A **live-sweep dry run** over the real control set: all currently-shipped control checks are KILLED (or honestly UNCOVERED), and a temporarily-vacuified real check is FLAGGED — proving the sweep bites on the real tree.
4. Wired into drift-watch (weekly job) + doctor (advisory) + per-PR `--selftest`; new claim `non-vacuity-gate` registered (claims.tsv + REQUIRED_IDS).
5. Fresh-clone `verify --require` green; version finishing coherent; `guard-core.sh` and all existing check *logic* untouched.

## Honest ceilings (recap)
1. Proves the FAIL-path operator class is caught, not total non-vacuity (mutation-testing limit).
2. Weekly cadence — a standing backstop, not an instant per-PR gate.
3. UNCOVERED checks are surfaced honestly, coverage grows over time.
