# Release-tag: guarded-manual for the kit + opt-in for adopters (design)

**Date:** 2026-06-27
**Slice:** process correction (release mechanics). Standalone; a course-correction on v3.53.0.
**Status:** Design converged (brainstorm, owner-approved 2026-06-27).
**Tracked here** because it's control-plane release mechanics and must be resumable cold.

---

## 1. Why (the correction)

v3.53.0 shipped **auto-tag-on-merge** as a *live, default* GitHub workflow. Two problems surfaced on reflection:

1. **It imposes a release model on adopters.** `.github/workflows/release-tag.yml` is **not** export-ignored (only `golden-path`/`drift-watch` are), so an adopter's `git archive` distribution includes a *live* workflow that auto-creates release tags on every VERSION-bumping merge. A passive validator (`release-coherence.yml`) shipping is fine; an *active* workflow that performs an irreversible release action should not be imposed — it violates the kit's *enable-don't-impose* / human-map-agnostic / progressive-disclosure principles. Worst-affected: an unskilled adopter who accidentally cuts releases via "magic" they don't understand.
2. **It cedes the human release decision** — mildly at odds with the just-ratified [[merge-tag-authority]] rule that the human owns the ship/ratification steps (incl. tag). The premature-tag fumble it fixed was a *sequencing* problem, not a reason to remove the human.

**Owner decision (2026-06-27): Option B — guarded-manual for the kit, opt-in for adopters.** The fumble is fixed by a coherence-guarded script the human runs (it *cannot* create an incoherent tag), keeping the human in the release seat; full automation is *provided* as an opt-in reference, never imposed.

## 2. What changes

The FLOOR script `scripts/release-tag.sh` is **unchanged** — it was always the portable, coherence-guarded, idempotent logic. Only the *trigger model* changes.

1. **Delete `.github/workflows/release-tag.yml`** (the live auto trigger). The kit no longer auto-tags. No export-ignore needed — the file is gone.
2. **The kit's release flow** becomes: after a merge, the human runs `sh scripts/release-tag.sh`. Because it reads VERSION, coherence-checks inline (`version-tag-coherent.sh . --require`), and is idempotent, a mis-timed run is a safe no-op and the tag always equals VERSION — the foolproof form of the manual tag, with the human keeping the decision.
3. **Ship the auto workflow as an opt-in reference:** `docs/operations/release-tag.github.yml` — the same workflow content with a "COPY into `.github/workflows/` to enable auto-tag-on-merge" header (mirrors `docs/operations/sod-gate.github.yml`). The existing GitLab reference (`docs/operations/release-tag.gitlab-ci.yml`) stays. Adopters opt in deliberately.
4. **Update `docs/operations/release-tag.md`** — two modes: *default/recommended* guarded-manual (`sh scripts/release-tag.sh` after merge) and *opt-in* auto (copy a reference binding) — plus the release-model trade-offs (the merge=release coupling; who full-auto fits; who it doesn't).
5. **Update the lock `conformance/release-tag-wired.sh`** — assert the FLOOR `--selftest` + the **reference** bindings (`docs/operations/release-tag.github.yml` + `docs/operations/release-tag.gitlab-ci.yml`) + the doc. **Drop the live-`.github/workflows/release-tag.yml` assertion** (it's deleted) and the kit-self N/A-skip that referenced it. Mirrors `author-not-approver-wired.sh` (which asserts the `sod-gate.github.yml` reference, not a live workflow). Update its `--selftest` fixtures accordingly.

**Unchanged:** `scripts/release-tag.sh`; the two ci.yml `--selftest` wirings; the claim id `release-tag-on-merge` (low churn — its *text* updates to describe the guarded-manual default + opt-in auto); `release-coherence.yml` (the tag-push backstop, still passive, still ships — fine).

## 3. Conformance / wiring deltas

- `release-tag-wired.sh`: as §2.5. Still claim `release-tag-on-merge`, still in `verify.sh` / `REQUIRED_IDS` / ci.yml, still guard-protected FLOOR (`scripts/release-tag.sh` stays in `is_control_plane_path` + the two shell matchers).
- `claims.tsv`: update the `release-tag-on-merge` row text (the coherent-tag FLOOR + bindings ship; default guarded-manual, opt-in auto).
- No new export-ignore; no carve change (the lock greps only shipped reference paths now, so it runs the same on the kit and an adopter export — no kit-self path dependence).
- `adopter-export-wired.sh`: no change (no live workflow to assert absent).

## 4. Honest ceiling / scope (YAGNI)

- We do **not** change `ci.yml` / `release-coherence.yml` shipping to adopters — they are passive validators, not imposed actions (a separate, larger "what CI ships to adopters" question, out of scope here).
- The FLOOR still proves only the *decision* via `--selftest`; the `git push` is live (human-run for the kit, CI for an opt-in adopter).
- No GitHub Releases / notes (unchanged YAGNI).

## 5. Build + dogfood

Control-plane → AMBER `scratchpad/release-tag-guarded/apply.py` (agent prepares + dry-runs on a clone; **Bradley applies + ships** per [[merge-tag-authority]]). Version finishing → **3.54.0**. Dual review (reviewer + security). **Dogfood:** on merge there is no auto-tag — Bradley runs `sh scripts/release-tag.sh` to cut v3.54.0 (the new flow, proven on its own release; if a last-gasp auto-run from the still-present old workflow already tagged it, the script no-ops).

## 6. Convergence record (owner-approved 2026-06-27)

Option B (guarded-manual for the kit, opt-in auto for adopters) over full-auto (A) — preserves the human release decision (consistent with merge-tag-authority) while killing the fumble via the coherence-guarded script · delete the live workflow · ship a copy-and-enable GitHub reference + keep the GitLab reference · lock asserts references not a live workflow · honest CHANGELOG framing this as a v3.53.0 correction. **Next: writing-plans.**
