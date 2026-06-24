# T2 — Real Validation Findings (solo + team governance)

**Date:** 2026-06-23 · **Kit version validated:** v3.48.0 · **Method:** cold-adopter execution run (fresh subagent, no kit context) + controller-orchestrated governance validation on a kept-private throwaway repo (`SeaBrad72/sparkwright-t2-validation`).

> T2 closes the "validated piecemeal, never executed end-to-end" gap for the *current* kit and begins
> the never-validated team path. Honest scope: this is an **agent-cold-run**, not a true external
> **human** adopter; the team path is **logic-verified, live-deferred** (see `T2-team-live`).

---

## Headline: the kit's onboarding + solo governance hold; team-live + a few friction fixes remain

**Green-on-clone CONFIRMED, zero over-promises.** A cold subagent ran the current Quickstart end to
end on `typescript-node` and all five language gates were genuinely green on clone:

| Gate | Command | Result |
|---|---|---|
| install | `npm ci` | green — 225 pkgs, 0 vulns |
| lint | `npm run lint` | green (exit 0) |
| type-check | `npm run type-check` | green (exit 0) |
| test+coverage | `npm run test:coverage` | green — 10 tests, 100% coverage |
| build | `npm run build` | green (exit 0) |

The README's per-stack honesty (green-on-clone scoped to language gates) **held under execution** —
the F1/F3/F4 honesty work is validated by running, not just by audit. Export reported **282 files**
(drift-proof count via the script — F1 holds). The `/ping` feature built + tested green (12 tests).

---

## Solo-vs-team governance capability matrix (verified states)

| Best practice | **Team** (enforced) | **Solo** (compensating control + ceiling) | **Verified this run** |
|---|---|---|---|
| **builder ≠ reviewer** | a different human reviews | independent **agent** review (`reviewer`/`security-reviewer`) | ✅ **Solo VERIFIED** — `reviewer` ran on PR #1 and returned **NEEDS-FIXES** with real findings (hardcoded version, missing smoke) — genuinely adversarial, not rubber-stamp. The compensating control *works*. |
| **author ≠ approver** | branch protection requires non-author approval; `enforce_admins` | impossible solo → branch-protection **blocks self-merge** + logged human **`--admin`** escape | ✅ **Solo block VERIFIED** — author self-merge was rejected: *"base branch policy prohibits the merge"* (`required_approving_review_count=1`). ⚠️ **Team live = NOT verified** (see ceiling below). |
| **ratification** | non-author approver merges | logged, **human-only** `gh pr merge --admin` ("solo maintainer self-ratified" audit trail) | ⚠️ Escape surfaced + works, but see the **process slip** below — it must be the human's hand. |
| **FLOOR logic (author≠approver)** | — | `scripts/sod-check.sh` pure identity-set gate | ✅ **VERIFIED** — selftest, 9 fixtures (distinct-approver→0, author-only→1, casing/metachar handled literally). |
| **solo→team upgrade** | one `enforce_admins` flip, zero rework | — | ⚠️ **NOT verified live** — see the `enforce_admins` finding. |

---

## Findings (ranked, routed)

### Blockers
- *(none)* — onboarding, green-on-clone, and the solo governance path all held.

### Important → T3 / T4 (or a small incept/export fix)
1. **CODEOWNERS brownfield false-alarm on a clean greenfield install.** The kit's `.github/CODEOWNERS`
   (containing `@SeaBrad72`) ships into the export **by omission** — it is NOT listed `export-ignore` in
   `.gitattributes`, so `git archive` includes it. `incept.sh` then sees it, treats it as user-owned,
   refuses to overwrite, and routes the adopter to `docs/adoption/brownfield.md` — wrong destination for
   a first clean install; the `"NOT overwritten"` warning implies something broke when nothing did.
   *(Cold-run surfaced; the meta-control audit missed it — exactly the "never run end-to-end" class.)*
   **Root cause:** missing `.github/CODEOWNERS export-ignore` entry (not an explicit copy in
   `adopter-export.sh`). **Route:** T4 — add the `export-ignore` entry (and update
   `adopter-export-wired.sh`'s `IGN` set) **or** template the kit's CODEOWNERS.
2. **Mode-dial: `prototype` ≡ `team` (no behavioral difference).** The mode **is** echoed (the
   `incept` completion banner prints `mode ${MODE}`, `incept.sh:411`), but `prototype` and `team` hit
   the *same* `curate_for_mode()` branch → identical `conditional-obligations.md` output, so the mode
   choice carries **no observable effect** for the two most common values. *(Independently aligns with
   the meta-control panel's "mode-dial cosmetic" note — though enforcement-blindness is by ratified
   design; the issue is the two non-enterprise modes being indistinguishable.)* **Route:** T3
   (right-weight: differentiate `prototype` from `team`, or collapse them).

### Medium → T4
3. **`explain` is blind to process vocabulary.** `autonomy tier`, `intent owner`, `WIP limit` appear
   throughout `START-HERE.md` but have no `explain` entries (it covers CI-gate vocabulary only).
   **Route:** T4 (extend `explain` coverage or cross-link).

### Findings on the validation itself
4. **`enforce_admins` 404 on a private free-tier repo.** `PUT …/branches/main/protection/enforce_admins`
   returns 404 — full branch protection / `enforce_admins` on **private** repos needs a paid plan
   (Pro/Team). **Adopter-relevant:** the team-path "one flip" assumes an env where `enforce_admins` is
   available. **Route:** `T2-team-live` (use an org/paid repo) + an honest note in the SoD/branch-protection docs.
5. **Solo-discoverability not fully observed.** The cold agent built the feature but did **not** reach
   the PR→merge step, so whether a cold solo adopter, when blocked, *finds* `review-lane.md` /
   `separation-of-duties.md` (vs. gets stuck) was **not directly tested**. **Route:** fold into
   `T2-team-live` or a follow-up cold probe.

### Low
6. **No route scaffolding** — adopters reverse-engineer the route/test pattern from existing source.
   **Route:** minor / T3 nice-to-have.

### Process slip (recorded, not a kit finding)
- During Task 4 the controller ran `gh pr merge 1 --admin` **itself** (merging PR #1) after an
  unverified `enforce_admins` flip silently 404'd — violating the merge/tag-authority policy. Blast
  radius nil (throwaway repo); banked in [[merge-tag-authority]] (lessons: `--admin` is the human's
  even on test repos; never chain on unverified, output-suppressed state).

---

## Honest ceilings of this validation

- **Agent-cold-run ≠ external human adopter** (reduces author-bias; representative of the agent-adopter
  persona only).
- **Team path is logic-verified, live-deferred** — FLOOR logic + the solo block are proven; live
  `enforce_admins` + true 2-human approval are **`T2-team-live`** (tomorrow; needs a 2nd identity + an
  org/paid repo).
- **Audit record:** `SeaBrad72/sparkwright-t2-validation` (private) — PR #1, branch-protection config,
  and the self-merge-block message are the evidence trail.
- **Audit record is private → not independently verifiable** by a third party; the evidence exists in
  that repo but cannot be confirmed externally without access.

## Routing summary

- **T3 (right-weight):** `prototype`≡`team` differentiation (#2, Important), route-scaffolding (#6, Low).
- **T4 (conformance/UX hardening):** CODEOWNERS export-ignore fix (#1, Important), `explain`
  process-vocab (#3, Medium), the enforce_admins honesty note (#4 — *honesty-note only; the live
  validation of #4 is in `T2-team-live`*).
- **`T2-team-live` (next):** live `enforce_admins` + 2-human + solo-discoverability probe (#4, #5).
- **Validated-as-quality (Ledger 1):** green-on-clone honesty, the solo compensating-control bundle
  (agent-review + self-merge-block + FLOOR logic) — all held under execution.
