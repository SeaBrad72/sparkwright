# Meta-control panel #19 — pre-E10 hardening (guard two-matcher symmetry + tag-time CI gate)

**Date:** 2026-06-28
**Trigger:** per-slice M verdict (condition A5) for the pre-E10 hardening slice (v3.68.0) — closes two banked items from panels #16–#18, ahead of E10.
**Profile:** light (5-lens).
**Verdict:** **GO** — 0 blockers, 0 unaddressed highs; all 3 dual-review findings folded in-slice or confirmed intentional.

One combined control-plane slice: **(A)** add `conformance/` + `adapters/` to the two `guard-core.sh` shell-command matchers (`:82` mention + `:85` redirect), closing the redirect-form gap with two-matcher symmetry; **(B)** a forge-neutral, bounded-poll, degrade-open tag-time CI gate in `release-tag.sh` that refuses to tag a definitively-failed main CI (the brick-#8 hole). Designed + planned by dogfooding the kit's design/plan skills (11th self-host). Built AMBER; dual-reviewed (reviewer APPROVE + security PASS — both independently reproduced the gap); proven on a fresh clone.

## The 5 lenses

| Lens | Verdict | Evidence |
|------|---------|----------|
| Scope-coherence & proportion | GREEN | 6 files, no new gate/claim/seat. Both fixes extend EXISTING locks (`agent-autonomy.sh` via `verify.sh`; `release-tag.sh --selftest` via `release-tag-wired.sh`). One combined slice was right — two small control-plane hardening items, one ship. Guard diff is provably ADD-ONLY (security confirmed byte-identical pre-existing alternatives; only appends before the closing `)`). |
| Honesty & over-claim | GREEN | Both honest ceilings stated: guard = speed-bump (interpreter `python -c` bypass unchanged); tag-gate = backstop that **degrades open** by design (a CI slower than the poll, or a non-GitHub forge, is not blocked — the hard control stays branch-protection + human). The reviewer-flagged unanchored-match semantic (matches `src/adapters/` etc.) is now disclosed in the CHANGELOG as intentional fail-safe symmetry with the existing route, not a new bypass. |
| Enforcement integrity (green-while-dark) | GREEN | **Non-vacuity PROVEN for both parts:** the guard redirect was ALLOWED pre-fix (rc 0 = the real gap) and DENIED post-fix (rc 1); a no-op `ci_gate` makes selftest case E fail (so the failure→refuse teeth are load-bearing). Both reviewers independently reproduced the gap and exercised every gate branch (only the 4 definitive-failure conclusions refuse; garbage/empty/in-progress/neutral all degrade open). Clone-proven: kit shellcheck gate clean, `release-tag.sh --selftest` 8/8, `agent-autonomy.sh` pass, `verify --require` 31/0, idempotent. |
| Direction & sequencing | GREEN | Closes the brick-#8 tag-on-red hole MECHANICALLY (not just the "verify conformance green before --admin" process discipline) + the two-matcher class for `conformance/`+`adapters/`. The "conformance-pending-looked-stuck" UX from the brick-#10 ship reinforced the need. Pre-E10 hardening is now DONE → **E10 next** (no resequencing). |
| Right-weighting & adoptability | GREEN | Forge-neutral: the tag-gate self-disables (degrades open) when `gh` is absent / remote isn't GitHub, so non-GitHub adopters are unaffected and the FLOOR stays pure-git. The guard change only ADDS deny coverage. Invoke-by-nothing — zero adopter burden. |

Standing "integration-capability / no-dead-ends" lens: **N/A** — guard + release-script hardening.

## Findings

- **0 blockers · 0 unaddressed highs.** All three dual-review items resolved:
  - **(Reviewer Minor — FOLDED)** `ci_gate` could busy-loop on `RELEASE_TAG_CI_INTERVAL=0` with a positive timeout → floored the interval at 1 (`if [ "$_interval" -lt 1 ]; then _interval=1; fi`), re-proven clone-green.
  - **(Security Low — FOLDED)** `RELEASE_TAG_CI_PROBE` is `sh -c`-eval'd → added a header comment: set it only from trusted CI config, never repo/PR-controlled input. (Not a real vector — the caller already has equivalent capability; the default path never sets it; mirrors the existing `RELEASE_TAG_COHERENCE` seam.)
  - **(Reviewer Minor — DISCLOSED)** unanchored `conformance/`/`adapters/` substring match is intentional, fail-safe, and symmetric with the existing `skills/` token + the Write/Edit path route → one-line honest-ceiling note added to the CHANGELOG (behavior unchanged; root-scoping would be a separate cross-route decision).

## Two ledgers

**Ledger 1 — verified-as-quality (ship with confidence):** guard diff ADD-ONLY (no matcher weakened); both non-vacuity negatives proven (pre-fix allow / post-fix deny; no-op ci_gate fails case E); both reviewers independently reproduced the gap + every gate branch; degrade-open provably never hard-blocks a legit release (only 4 definitive-failure conclusions refuse); forge-neutrality preserved (pure-git path unchanged when gh absent); reads still allowed (WS1 allow-back intact); kit shellcheck clean; `release-tag.sh --selftest` 8/8 wired into CI; `agent-autonomy.sh` pass; `verify --require` 31/0; idempotent (8 skips); exactly 6 files; no new gate/claim/seat; both honest ceilings stated; the 3 review findings folded/disclosed.

**Ledger 2 — fix-forward (ranked):**
1. **Optional anchoring decision** (deferred, both reviewers) — if root-scoping the control-plane path tokens is ever wanted, anchor BOTH the shell matchers and the `is_control_plane_path` route consistently (e.g. `(^|[[:space:]>])(conformance|adapters|skills)/`). Out of scope here; current fail-safe over-block is intentional and symmetric.
2. **Optional conformance grep** (banked from panels #17/#18) banning a hardcoded LIVE spine-count in non-historical prose, so the count-drift class self-closes.

## Retro

- **Fold cheap review findings in-slice when the file is already open.** Two of three findings (interval-floor, probe doc note) were trivial and lived in files the slice already edited — folding them cost one re-prove cycle and shipped a tighter artifact than deferring to a follow-on. The third (unanchored match) was correctly *disclosed* rather than changed, because changing it would have spanned the existing path route (out of scope) — the honest move is a ceiling note, not a silent scope-creep.
- **An empty surface filled is worth hardening; an empty surface still empty is not.** The tag-gate sat banked-and-skeptical until the brick-#8 incident actually tagged a red commit — then it was promoted-to-build. Building it before a near-miss would have been speculative; building it after is closing a proven hole. The kit's own "is the provable thing meaningful?" lens applied to slice *selection*.

**Next: E10 — zero-superpowers acceptance** (build a real slice using only the kit's own roster + skills, against the now-complete Phase-2 spine + the now-hardened control plane). Pre-E10 hardening is complete.
