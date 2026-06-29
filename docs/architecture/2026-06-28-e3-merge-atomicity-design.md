# E3-merge-atomicity — integration is all-or-nothing

**Date:** 2026-06-28
**Status:** Approved (owner-ratified design gate)
**Slice role:** the **E10 zero-superpowers acceptance** vehicle — a real, banked hardening slice built end-to-end using *only* the kit's own roster + skills (design → plan → tdd → verification → review), zero superpowers. See [[self-hosting-commitment]], [[reprioritized-backlog]].

## Problem

`scripts/orchestrator-run.sh` integrates built slices one merge at a time (the merge-floor loop). On a merge-floor failure it runs `git merge --abort` and exits 1 — but `git merge --abort` only unwinds the *single* in-progress failed merge. It restores the branch to `base + already-merged-slices`, **not** to `base`. So when the floor trips on slice N, slices 1…N-1 remain committed on the branch.

The run prints *"refusing, tree clean"*, but "clean working tree" ≠ "branch at the cut-point". The earlier merges are a **partial-integration residual** — off-contract: integration is supposed to be all-or-nothing (the conflict-safe floor either integrates the whole disjoint set or refuses and leaves the repo untouched).

This residual was banked from the E3b panel #7 (`E3-merge-atomicity`). The detection-refuse path is already residual-free (no merge is attempted; HEAD stays at `base` — proven by the existing dueling-rename assertion). Only the **merge-floor** path has the gap.

## Fix

On the merge-floor failure path, after `git merge --abort`, reset the branch to the run cut-point `base` (captured at the top of `run()`):

```sh
git reset --hard -q "$base" 2>/dev/null || echo "orchestrator-run: WARNING reset to base failed - manual cleanup may be needed" >&2
```

- **Best-effort but not silent** (folded from security review Low-2): on the pathological reset failure it WARNS to stderr rather than `|| true`-swallowing, so the rare non-atomic outcome is observable; the trusted `kit.conflict` span and the refusal (exit 1) still fire regardless. `base` is a commit we held seconds earlier, so a reset failure is pathological, not expected.
- **Honest blast-radius (folded from security review Low-1):** `git reset --hard` also discards any uncommitted *tracked* working changes — but per the loop's clean-committed-base contract there are none at integration time; the inline comment states this so a reader at the call site sees the full ceiling without cross-referencing this doc.
- **Only the merge-floor path** gets the reset. The detection-refuse path attempts no merge, so HEAD is already `base` — adding a reset there would be a no-op (right-weight: don't).

## Test (load-bearing red→green)

The existing `--selftest` never exercises the merge floor with *disjoint* file sets, because every conflict fixture is caught earlier by the detection phase. The new case reaches the floor via a **directory/file clash**, using an inline custom `ROLE_RUNNER` (same pattern as the anti-spoof env-probe case — keeps the test artifact out of the shipped `engineer-fixture.sh`):

- slice `clashF` creates path `clash` as a **file**; slice `clashD` creates `clash/child` (a file under directory `clash`).
- Changed-file name-only sets `{clash}` vs `{clash/child}` are **disjoint** → detection passes → merge floor runs: merge `clashF` lands `clash`; merge `clashD` **fails** (cannot create a directory where a file exists) → floor trips.
- **Load-bearing NEGATIVE assertion:** after the refusal, `git rev-parse HEAD == base` **and** `[ ! -e clash ]`. The current code **fails** this (HEAD advanced by `clashF`'s merge); the fix makes it pass.
- **POSITIVE liveness anchor:** a disjoint clean run in the same own-repo harness asserts `HEAD != base` **and** both built files present — so a buggy *"reset always"* would break the clean integration path.

Both cases run in a self-built temp repo (not the `_isolated` helper, which removes the repo before assertions can inspect it).

## Kit design disciplines

- **Honest ceiling.** `git reset --hard "$base"` discards the integration commits made by *this run*; it assumes the run began at a committed `base` (already the loop's standing contract — `base=$(git rev-parse HEAD)`). It does not (and cannot) recover pre-run uncommitted working changes; the orchestrator integration contract starts from a clean committed base.
- **Non-vacuity.** Positive (disjoint integrates: HEAD advances, files present) + load-bearing negative (floor trip: HEAD==base, no residual). Neither a dead loop nor an always-reset loop passes both.
- **Right-weight / anti-ceremony.** Extends the existing `--selftest` and reuses the existing `kit.conflict` span. **No new gate, no new claim, no conformance change.** Reset added only where a residual exists.
- **Control-plane completeness.** `orchestrator-run.sh` is guard-protected → ships via an **AMBER `apply.py`** (the human applies it). No new control-plane path is introduced, so the three guard matchers and the agent-autonomy fixtures are unchanged.

## Scope & impact

- **Files changed:** `scripts/orchestrator-run.sh` (the reset line + the new selftest case + the `--selftest` summary string).
- **Version finishing folded into apply.py** (per [[release-finishing-in-apply-py]]): `VERSION` 3.68.0 → **3.69.0** (minor — new integration behaviour), `CHANGELOG.md` entry.
- **Conformance:** `conformance/orchestrator-loop-wired.sh` `check_loop` greps only static markers (`runaway-guard.sh step`, `kit.denied`, `kit.conflict`, `git diff --name-only`) — all preserved → the lock stays green. The live `orchestrator-run.sh --selftest` runs via the golden-path/verify harness; the new case rides along.

## Acceptance lens (E10)

This slice is the instrument; the measurement is the meta-observation recorded at the end: **did the kit's own design → plan → tdd → verification → review spine carry this slice as well as superpowers would have?** Measured against the FLOOR convention's honest ceiling (consult the keystone, reach skills by reading — not NATIVE auto-injection). The verdict + per-slice meta-control panel close the run.
