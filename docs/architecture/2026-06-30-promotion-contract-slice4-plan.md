# Plan — Proportional Promotion Contract Slice 4: delegable execution contract (docs + lock)

**Goal:** Make the delegable-execution rule operative — document the three-tier contract canonically, reconcile every prose surface, and extend the existing lock so the control-plane-human invariant and the after-GO precondition can't be euphemism-evaded.

**Architecture:** Pure documentation + a coherence-lock extension. The canonical rule lives in `docs/governance/promotion-contract.md` (the lock's grep target); `§13`/`AGENTS.md`/`review-lane.md`/`CLAUDE.md` reference it. `conformance/promotion-contract-documented.sh` gains presence markers + load-bearing negatives for the new rule. No mechanism, no guard change.

**Tech stack:** Markdown governing docs, POSIX sh (dash-clean) conformance.

**Global constraints (verbatim from the spec):**
- Documentation + coherence-lock ONLY — no agent-auto-execution mechanism (no live consumer; server-side merge is un-guardable). No `guard-core.sh`/`guard.sh` change. No `agent-boundary.sh` change.
- Control-plane execution stays human at every rung — the non-negotiable invariant (already locked by the matrix column; the new prose must not weaken it).
- The `gh pr merge --admin` honesty boundary (server-side, human) preserved verbatim.
- Reuse the `promotion-contract` claim (extend its lock) — no new claim.
- Honest ceiling stated: the lock proves the rule is DOCUMENTED coherently, not that an agent obeys it.

**Build model: AMBER.** Every file is control-plane (governing docs + conformance). Author under `scratchpad/promotion-contract-s4/`, one idempotent `apply.py` (version-finishing folded), clone-prove, hand to human.

---

## File map

| File | Change |
|---|---|
| `docs/governance/promotion-contract.md` | + canonical "Delegable execution — the three tiers" section (lock's grep target); build-status Slice 4 → shipped; intro note updated |
| `conformance/promotion-contract-documented.sh` | + 4 presence markers + updated `good` fixture + 2 load-bearing-negative fixtures |
| `DEVELOPMENT-PROCESS.md` §13 | flip "not yet operative — slices 3–4" → operative; add tier carve-out reference |
| `AGENTS.md` | reconcile "hand the human the merge command" → Ordinary/Sensitive delegable post-GO; control-plane + `--admin` stay human |
| `docs/operations/review-lane.md` | same reconciliation in the "Solo + agent-authored PRs" caveats |
| `CLAUDE.md` | line ~92: drop stale "enforcement lands in slices 3–4" (closes routed L1) |
| `conformance/claims.tsv` | update `promotion-contract` row description to mention delegable-execution |
| `VERSION` · `README.md` · `CHANGELOG.md` | version finishing 3.82.0 → 3.83.0 (folded into apply.py) |

All control-plane → one `apply.py`; serialize (single engineer).

---

## Task 1 — canonical rule in `docs/governance/promotion-contract.md`

**1a.** Add this section (after the existing "The promotion contract — mechanics" section; it is the lock's grep target — the exact phrases below satisfy the new markers in Task 2):

```markdown
## Delegable execution — who may run the keystroke (operative)

Execution of a promotion's keystrokes (merge, tag, release) is **delegable after an explicit recorded human GO** — the judgment is the control, not the keystroke. What is delegable depends on the change-class:

- **Tier 1 — always (build phase, within a rung):** the agent reads/drafts, writes code + tests on a feature branch, `git commit`s (reversible), pushes feature branches, opens PRs, authors the AMBER `apply.py`. No per-action gate.
- **Tier 2 — delegable only after a recorded GO (Ordinary/Sensitive):** the agent may execute a normal, branch-protection-permitted merge of an Ordinary/Sensitive PR and run the tag/release step for an Ordinary release. Never before the GO; **never unilateral at a promotion.**
- **Tier 3 — human-executed, never delegable at any rung:** rendering the GO/NO-GO judgment itself; any Control-plane promotion — **Control-plane execution stays human at every rung** (merge/tag/apply); the `gh pr merge --admin` branch-protection bypass (server-side, outside the guard — the honesty boundary; a human act); push-to-main / force-push (guard-blocked); deploy-to-prod / delete-data / rotate-secrets / incur-spend.

The decisive line is `is_control_plane_path` (change-class), not the keystroke: because the kit's own surface *is* the control-plane, Tier 2 is inapplicable to the kit's own work — the maintainer runs kit ship steps, enforced by the invariant, not merely by preference.

**Honest ceiling:** this is the documented contract. The server-side merge is un-guardable (`docs/operations/runtime-guards.md` honesty boundary); live enforcement remains the guard (push-to-main / force-push) + the `agent-boundary` CI gate (control-plane ratification at merge). No agent auto-execution mechanism is wired — there is no live consumer.
```

**1b.** Build-status table: Slice 4 row Status `planned` → the ship version (e.g. `v3.83.0`); update the closing line "the remaining enforcement slice (4)…" → all slices shipped.

**1c.** Intro note ("> What this doc does"): the phrase noting the relaxed agent-commit rule is a later slice → mark it shipped/operative.

**Verify:** the 4 new marker regexes (Task 2) each match; existing markers unaffected.

---

## Task 2 — extend `conformance/promotion-contract-documented.sh` (the teeth)

**2a.** In Part A, after the existing `require` calls (before the Part B matrix block), add:

```sh
  # Slice 4: the delegable-execution rule is documented coherently — WITH its two load-bearing
  # carve-outs (control-plane execution stays human; delegation is only AFTER a recorded GO). A doc
  # that documents delegation but drops either carve-out is a fox/henhouse gap and MUST fail.
  require 'delegable-post-go'        'delegable after.*recorded.*GO'
  require 'never-unilateral'         'never unilateral'
  require 'cp-execution-human'       'control-plane execution stays human'
  require 'admin-merge-honesty'      'gh pr merge --admin'
```

**2b.** Update the selftest `good` fixture heredoc — add these lines (so the complete fixture still passes) before the matrix table:

```
Execution is delegable after an explicit recorded human GO; never unilateral at a promotion.
Control-plane execution stays human at every rung. The gh pr merge --admin bypass is a human act.
```

**2c.** Add two load-bearing-negative fixtures (after the existing `bare-human` fixture, before the final `st` check):

```sh
  # Slice 4 load-bearing negatives: documenting delegation but DROPPING a carve-out must FAIL.
  nocp="$base/no-cp-carveout.md"
  grep -v 'Control-plane execution stays human' "$good" > "$nocp"
  if check_file "$nocp" >/dev/null 2>&1; then echo "selftest FAIL: dropped control-plane carve-out should FAIL (fox/henhouse gap!)"; st=1; else echo "selftest PASS: dropped control-plane carve-out -> FAIL"; fi

  nogo="$base/no-after-go.md"
  grep -v 'delegable after an explicit recorded human GO' "$good" > "$nogo"
  if check_file "$nogo" >/dev/null 2>&1; then echo "selftest FAIL: dropped after-GO precondition should FAIL"; st=1; else echo "selftest PASS: dropped after-GO precondition -> FAIL"; fi
```

**2d.** Update the final selftest OK line to mention the new fixtures (…"complete/missing/relaxed/prose-mask/euphemism/bare-human/no-cp-carveout/no-after-go all behaved"…).

**Non-vacuity proof (build-time):** run `--selftest` → OK; then temporarily delete the `require 'cp-execution-human'` line → the `no-cp-carveout` fixture no longer FAILs (selftest breaks), proving the marker is load-bearing; revert. Record both flips.

**Verify:** `sh conformance/promotion-contract-documented.sh --selftest` → OK (8 fixtures); `sh conformance/promotion-contract-documented.sh` (real doc) → OK.

---

## Task 3 — prose reconciliation + close L1

Each edit is additive/reconciling; preserve the `--admin`-server-side honesty boundary verbatim. Anchor phrases given; engineer produces exact idempotent old→new in apply.py.

- **`DEVELOPMENT-PROCESS.md §13`** — anchor "execution delegable post-GO; *enforcement lands in slices 3–4 — not yet operative*": change to "execution delegable post-GO — **now operative** (see the promotion contract's *Delegable execution* section: Ordinary/Sensitive delegable after a recorded GO; **control-plane execution stays human**; `gh pr merge --admin` stays human)." Respect the doc-budget ratchet (if §13 bucket is at cap, raise one bucket in the same apply.py, as Slice 1 did).
- **`AGENTS.md`** — anchor "prepare the green PR and **hand the human the merge command**": keep this for **control-plane and any `--admin` bypass**, and add: "for **Ordinary/Sensitive** changes after a recorded GO, the agent may execute the normal (non-`--admin`) merge — execution is delegable post-GO (see `docs/governance/promotion-contract.md`)." Keep "Agents propose; humans ratify" and the honesty boundary intact.
- **`docs/operations/review-lane.md`** — in the "Solo + agent-authored PRs" caveats, reconcile identically: `gh pr merge --admin` stays human (unchanged, verbatim); a normal Ordinary/Sensitive merge is delegable post-GO.
- **`CLAUDE.md` (~line 92, DoD)** — anchor "(`docs/governance/promotion-contract.md`; enforcement lands in slices 3–4)": drop the "; enforcement lands in slices 3–4" clause (both slices shipped). Closes routed **L1**.

**Verify:** no surface contradicts another; `grep -rn 'not yet operative\|slices 3–4\|slices 3-4'` across the four docs returns nothing live (only historical CHANGELOG/log entries remain, which are point-in-time and correct).

---

## Task 4 — claim description + version finishing

- **`conformance/claims.tsv`** — the `promotion-contract` row description: append "…+ the delegable-execution rule (Tier 2 Ordinary/Sensitive post-GO; Tier 3 control-plane/`--admin`/irreversible human; never unilateral)" so the registered claim reflects the extended coverage. (Same claim id; no new row.)
- **Version finishing folded into apply.py:** VERSION 3.82.0 → 3.83.0; README badge; CHANGELOG `## [3.83.0]` entry.

---

## Task 5 — assemble `apply.py` + clone-prove

Idempotent `scratchpad/promotion-contract-s4/apply.py` (Python file I/O — not shell — for control-plane paths; per-file buffer for any file with ≥2 edits; anchor on stable substrings). Clone-prove on a throwaway clone, capture REAL output:
1. `shellcheck conformance/promotion-contract-documented.sh` clean.
2. `sh conformance/promotion-contract-documented.sh --selftest` → OK (8 fixtures) + the 2 non-vacuity flips recorded (drop `cp-execution-human` marker → `no-cp-carveout` stops failing; drop `delegable-post-go` marker → `no-after-go` stops failing).
3. `sh conformance/promotion-contract-documented.sh` (real doc) → `OK — contract documented coherently`.
4. `sh conformance/claims-registry.sh` → `PASS: promotion-contract`, coverage intact.
5. `sh conformance/verify.sh --require` → `RESULT: OK`, control count **unchanged at 38** (extend, no new claim).
6. `sh conformance/check-links.sh` OK (new intra-doc references resolve).
7. `sh conformance/doc-budget.sh` OK (raise a bucket in apply.py if §13 addition trips it; note which).
8. Re-run apply.py → no-op (idempotent).
9. `grep` sweep confirms no live "not yet operative / slices 3–4" remains in the four reconciled docs.
10. `git diff --stat` lists all expected files; `guard-core.sh`/`guard.sh`/`agent-boundary.sh` NOT among them.

---

## Dual review (builder ≠ reviewer)

- **`reviewer`** (coherence): no cross-doc contradiction; L1 closed; no placeholder; the lock's new markers match the doc's exact phrases; idempotent apply; doc-budget honored.
- **`security-reviewer`** (fox/henhouse lens): can the new prose be read to permit an agent-autonomous **control-plane** or **`--admin`** merge? Is the euphemism-negative load-bearing (dropped carve-out FAILs)? Does anything weaken the existing control-plane-column teeth or the honesty boundary?

## Ship (human; standard flow)
apply.py → separate `governance-close.py` (marker `3.83.0 GO` + meta-control-log row, panel #34) → commit (`git show --stat` all files) → push → PR → green conformance → `gh pr merge --squash --admin --delete-branch` (solo control-plane PR red on `control-plane-ratification` by design) → `git checkout main && git pull && sh scripts/release-tag.sh`.

## Spec coverage
AC1 → Task 1. AC2 → Task 3. AC3 → Task 3 (CLAUDE.md). AC4 → Task 2 (+ clone-prove 2). AC5 → Task 4/5 (+ clone-prove 5, 10).
