# M2-Ratification-Hardening (+ Release-Coherence) · Design

**Date:** 2026-06-26
**Status:** Approved (brainstorm) — ready for implementation plan
**Slice:** `M2-ratification-hardening` (security-reviewer follow-on from M2-S5) + a folded-in release-coherence gate (item e), discovered by the v3.49.0 finishing-edits incident.
**Classification:** Control-plane change → AMBER `apply.py` + dual review (reviewer + security-reviewer).

---

## Framing (why the weighting matters)

The M2-S5 security review attached four follow-on conditions. They were a **finding list, not a ratified design** — and on critical reassessment their *real* marginal value varies widely. The primary defense for the meta-control verdict state is already in place: the marker (`docs/governance/.meta-control-last`) and verdict log (`docs/governance/meta-control-log.md`) are **control-plane** (guard-denied in both matchers, confirmed in M2-S5). So items hardening that surface are defense-in-depth on an already-closed gap.

The center of gravity is therefore **(e)** — a *new* check closing an *open* gap (a tagged release whose `VERSION` was never bumped passed all gates today). The rest are small hygiene fixes. Two of the original four are trimmed/dropped (see Decisions).

| Item | Real value | Disposition |
|------|-----------|-------------|
| (e) VERSION↔tag coherence | **High** — closes an open gap | Build (the prize) |
| (b) verdict enum normalization | Medium — correctness | Build as-is |
| (d) shared version-compare helper | Medium — DRY + single test surface; enables (a)/(e) | Build (own lib) |
| (a) future-pin clause | Low — marginal defense-in-depth | Build **trimmed** |
| (c) CODEOWNERS on docs/governance | ~Zero enforcement (catch-all already covers it) | **Dropped** |

---

## Item (e) — VERSION↔tag release-coherence (the prize)

**Problem (observed):** the v3.49.0 release ran `apply.py` but skipped the VERSION finishing edits — `VERSION` stayed `3.48.18` while the commit and the pushed `v3.49.0` tag claimed 3.49.0. **Every gate stayed green**, because no conformance check couples `VERSION` to the git tag (`badge-version` only checks README↔VERSION *internal* consistency). The incoherent release was caught by a human hunch, not CI.

**New check `conformance/version-tag-coherent.sh`** asserting two invariants:

1. **`VERSION ≥ highest reachable semver tag`** — VERSION is never *behind* a released tag. (Weekly/per-PR safety net.)
2. **Tagged-HEAD ⇒ `VERSION == that tag`** — if the current commit is tagged with a semver tag, `VERSION` must equal it (sans leading `v`). **This is the load-bearing invariant** — it fires at the moment a release tag lands on a commit whose VERSION wasn't bumped.

**Three-state:** `0` PASS (incl. N/A when no semver tags exist yet — a fresh adopter), `1` FAIL (incoherent), `2` UNVERIFIED (e.g. `git` unavailable) escalating under CI/`--require`. Offline-only (`git tag` / `git describe`, no network) to preserve the gate's offline-determinism. Reuses the (d) helper.

**Threat model — distinct from (a):** (e) catches **human mistakes** (skipped bump), not agent attacks, so local tags are an acceptable basis. The honest ceiling: it does not prove the *right* version was chosen, only that VERSION, the tag, and the release point agree.

**Wiring (coverage requires both):**
- Into `conformance/verify.sh` → per-PR + `drift-watch` + `doctor` (catches invariant 1; catches invariant 2 on any run where HEAD is tagged).
- Into a dedicated **`.github/workflows/release-coherence.yml`** triggered on `push: tags: ['v*']` → this is where invariant 2 catches a premature/mismatched tag *at push time* (today's exact failure mode). Per-PR CI cannot see a future tag; the tag-push job is the real catch. **[Updated at implementation: a dedicated workflow was chosen rather than wiring into `golden-path.yml`, because golden-path triggers on `paths:`/`schedule`, not robustly on tag pushes — a `tags:`-only workflow is unambiguous.]**
- Register: `conformance/claims.tsv` row `version-tag-coherent`, add to `REQUIRED_IDS`, index in `conformance/README.md`.

**Selftest fixtures:** VERSION==tag PASS · VERSION ahead of latest tag, HEAD untagged (ship-seam) PASS · HEAD tagged but VERSION≠tag FAIL (today's bug) · VERSION behind latest tag FAIL · no tags N/A → 0 · git absent → 2.

---

## Item (b) — verdict enum normalization

In `conformance/meta-control-fresh.sh`, the verdict field is parsed case-sensitively (`awk ... if (rows[i]=="DEFERRED")`), so a lowercase `deferred` silently evades the serial-DEFERRED cap.

**Fix (normalization-only — see update note):** uppercase-normalize the verdict on parse in `trailing_deferred` (`toupper(v)`) and on the marker/log verdicts before the desync compare (`norm_verdict`), so a lowercase/mixed-case `deferred` still counts toward the serial-DEFERRED cap.

> **[Updated at implementation — the enum was dropped.]** The original design here proposed *also* validating the verdict against a fixed allowed set `GO | NO-GO | DEFERRED`. The clone dry-run proved that wrong: the real verdict vocabulary is **open-ended** — the kit's own log uses `GO-WITH-CONDITIONS` and `KEEP-BIASED`, and the marker stores `GO-WITH-CONDITIONS`. A fixed enum rejected the kit's own state. The only integrity-relevant verdict is `DEFERRED` (for the serial cap); any non-DEFERRED value legitimately means "an addressed run" and correctly breaks the streak. So (b) is **normalization-only, no enum restriction**. The in-code comment records this rationale.

**Fixtures:** `deferred`/`Deferred` now count toward the cap (→ OVERDUE at ≥2); `GO-WITH-CONDITIONS`/`KEEP-BIASED` accepted (no enum). (The original "garbage verdict rejected" fixture was removed with the enum.)

---

## Item (d) — shared version-compare helper

The `sort -V` comparison idiom is duplicated inline in `meta-control-fresh.sh` (count-newer + future-pin) and will be needed by (a) and (e).

**Fix:** a small dedicated `conformance/version-helpers.sh` exposing `ver_ge A B` (true iff A ≥ B) and `ver_gt A B`, each a thin wrapper over `sort -V`, plus a `ver_norm` (strip leading `v`). Sourced by `meta-control-fresh.sh` and `version-tag-coherent.sh`. Not folded into `wf-helpers.sh` (that file's responsibility is workflow detection; version comparison is a separate concern). Has its own `--selftest`.

---

## Item (a) — future-pin clause (trimmed)

**Current:** `conformance/meta-control-fresh.sh` rejects a marker whose version is `> VERSION` (anchored on the agent-writable `VERSION`).

**Trim rationale:** the security-reviewer's proposed `marker ≤ max(VERSION, highest tag)` anchor only matters when a tag is *ahead* of VERSION — precisely the incoherent state item (e) eliminates. Once (e) holds, `max(VERSION, maxtag) == VERSION`, so the extra term is dead complexity. The genuinely useful tightening is the **clause**, not the anchor.

**Change:** keep the `≤ VERSION` upper bound; **add** the requirement that the marker version be **either a real existing semver tag OR exactly `== VERSION`** (the unreleased ship-seam). This rejects a fabricated in-between marker (e.g. `3.48.0` when it was never tagged and VERSION is `3.49.0`) that the bare `≤ VERSION` bound would have accepted. Reuses the (d) helper.

**Honest ceiling (documented in the script comment + `docs/operations/meta-control.md`):** this is **defense-in-depth, not a boundary**. The actual guarantee is the marker's **control-plane status** (the guard denies agent writes). An offline, file-based gate cannot resist an attacker who can already write the marker — they can co-bump VERSION and set `marker == VERSION`, and local `git tag` is fabricable. We state this plainly rather than implying the gate is tamper-proof. Deviates from the literal M2-S5 condition (`max(...)`); the deviation achieves the same intent (reject fabricated future markers) more simply, and is flagged for the security re-review.

**Fixtures:** marker == a real old tag PASS · marker == VERSION (ship-seam) PASS · marker is a non-tag value `< VERSION` and `≠ VERSION` FAIL (the new tightening) · marker `> VERSION` FAIL (unchanged).

---

## Item (c) — DROPPED

Adding `/docs/governance/ @SeaBrad72` to `.github/CODEOWNERS` changes nothing: the existing catch-all `*  @SeaBrad72` already routes that path to the only owner. For a solo maintainer it is a no-op for enforcement; presenting it as hardening would be cargo-cult. If an "explicit CODEOWNERS areas" convention is ever wanted, it is a separate cosmetic chore, not a security item. Recorded here as a deliberate non-action.

---

## Testing & process

- Each item ships `--selftest` fixtures; (e) regression-locks the exact v3.49.0 failure; (a)/(b) regression-lock their evasions.
- Full control-plane slice (`conformance/*`, `verify.sh`, `claims-registry.sh`, `ci.yml`, the golden-path workflow) → **AMBER `apply.py` in scratch**, security-reviewed, **dry-run on a throwaway clone** (full `verify --require` green; (e) fixtures pass) → **Bradley applies** on the real tree + PR + merge + tag (the ratified AMBER convention; agent does not apply control-plane to the real tree).
- This time the VERSION finishing edits are protected by (e) itself: after this slice lands, a future skipped bump fails the tag-push job.

## Honest-ceiling summary

- **(e) guarantees:** VERSION, the latest tag, and a tagged release point are mutually coherent — a skipped bump becomes red CI. **Does not guarantee** the *correct* version was chosen.
- **(a) guarantees:** a marker must correspond to a real tag or the current VERSION — modest defense-in-depth. **Does not guarantee** tamper-resistance against an attacker who can already write the marker (the control-plane closure is that defense).
- **(b)/(d):** correctness + DRY; no security claim.
