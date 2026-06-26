# Fix — `version-tag-coherent` adopter-export N/A-skip (design)

**Status:** Design ratified (2026-06-26). Small control-plane fix (AMBER). **Target: v3.51.1 (PATCH).**

## Problem

The adopter export (a `git archive` tree, **no `.git`**) goes RED on `verify.sh --require`:

```
[control] version-tag-coherent UNVERIFIED
RESULT: FAIL (unverified under --require/CI)
```

`conformance/version-tag-coherent.sh:28` escalates "not a git repo" to `unverified` → FAIL under `--require`. That escalation is **correct for the kit** (the kit is always a git repo; missing git = broken CI environment) but **wrong for a deliberately non-git adopter export**.

**Regression window:** broken since **v3.49.1**, when the release-coherence gate shipped without the kit-self N/A-skip that the other golden-path-coupled claims (`feature-flags-wired`/`containment-audit`/`runtime-security`) received in the v3.48.18 adopter-export-RED fix. Confirmed identical on `main`'s v3.50.0 and v3.51.0 exports — it is **not** caused by E5-thin. This restores the green-on-clone promise.

## Fix

Give the no-git branch the established **kit-self N/A-skip**, anchored on the export-ignored `docs/ROADMAP-KIT.md` (mirrors `feature-flags-wired.sh:49`):

```sh
( cd "$_d" && git rev-parse --git-dir >/dev/null 2>&1 ) || {
  # Non-git tree: an adopter export (pre-adoption) is N/A; the KIT must be a git repo (ROADMAP-KIT.md present) → escalate.
  [ -f "$_d/docs/ROADMAP-KIT.md" ] || { echo "version-tag-coherent: N/A — not a git repo (adopter export / pre-adoption)"; return 0; }
  unverified "not a git repo / git unavailable ($_d)"
}
```

**Fail-closed:** in the kit, `docs/ROADMAP-KIT.md` is present, so a missing-git kit CI still escalates to FAIL. Only a non-git tree *without* the kit anchor (i.e. an adopter export) is N/A.

### N/A-skip, NOT carve

`version-tag-coherent` is a *genuinely useful adopter check* — once an adopter `git init`s their project, they should verify VERSION matches their tags. The N/A-skip keeps the check live for adopters-with-git while making it correctly inapplicable to the pre-git export. Carving (removing it from the export registry) would strip a good check from adopters — rejected.

## Tests

Update the `--selftest` no-git cases:
- **F (export):** no git + no `docs/ROADMAP-KIT.md` → **N/A (0)**, regardless of `--require` (was UNVERIFIED/FAIL).
- **G (kit, new):** no git + `docs/ROADMAP-KIT.md` present → **UNVERIFIED (2)**, escalates to **FAIL (1)** under `--require` (proves fail-closed).

## Mechanics

Control-plane (`conformance/version-tag-coherent.sh`) → **AMBER**: `apply.py` patches the script + folds in version finishing (VERSION 3.51.0 → 3.51.1, README badge, CHANGELOG, ROADMAP). No new claim, no carve, no new verify.sh line (already wired). Dry-run on a clone proves: the adopter export goes **green** on `verify --require`, and the kit still escalates (selftest G + a no-git kit probe). Dual review (builder ≠ reviewer + security-reviewer). Then human apply + merge + tag (guarded).
