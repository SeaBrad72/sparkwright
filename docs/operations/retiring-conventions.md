# Retiring a doc, template, or claim — safely

The kit grows by appending; it must also be able to **retire** without breaking itself or quietly
dropping capability. This is the discipline the T3c consolidation arc exercised (v3.48.1–v3.48.5).
It is a *convention*, not an automated gate — retirement is judgment work; the steps below keep it
honest and reversible.

> **Note.** There is no "retirement mechanism" to build — the T3a right-weighting assessment found
> **zero conformance checks/claims** needed retiring (the enforcement surface earned its keep). Real
> retirements are docs/templates, handled by ordinary edits + the discipline here.

## 1. Decide whether to retire at all — the design-intent KEEP-default lens

Default to **KEEP**. "Low usage / few inbound references" is **not** a retire reason in a kit whose
philosophy is *front-load rigor + conditional obligations* (rare ≠ dead), *harness-neutral fallbacks*,
*persona coverage*, and *compliance crosswalks*. Before retiring, ask: *does this exist for a deliberate
design / compliance / persona / process / harness-neutral reason that low usage doesn't capture?* If
yes → keep. Retire only when the artifact is genuinely:

- **Redundant** — its content is duplicated by, or can migrate losslessly into, another artifact; or
- **Dead** — a completed build artifact whose rationale lives on in `CHANGELOG.md` + the live code.

(This is the same lens the meta-control panel applies — see `docs/operations/meta-control.md`. In T3a it
reversed several aggressive-cut proposals, e.g. JIRA-SETUP's server-enforced tier and the profiles'
"pin at adoption" floating action refs.)

## 2. Find every inbound reference

```sh
git grep -nE "<artifact-name>" -- '*.md' '*.sh'
```

Classify each hit:
- **Markdown links** (square-bracket text followed by a parenthesized target) — these break
  `conformance/check-links.sh` on deletion. **Repoint or remove** every one. (`check-links.sh` scans
  *tracked* files only and only parenthesized link targets — it does **not** parse backtick code-spans,
  and it does **not** scan gitignored files.)
- **Backtick code-spans / prose mentions** — a backtick mention of a *filename* (e.g. `` `frame.md` ``)
  is safe, **but** a span that *quotes literal link syntax* (bracket-then-paren) is **not**: check-links
  greps raw text regardless of backticks, so it matches link-shaped content inside a code span too —
  the **code-span gotcha** (banked to T4; it bit this very arc three times). When you must show link
  syntax in prose, describe it in words. Repoint *live* filename mentions (an active doc/template
  pointing adopters at the deleted thing); **leave historical records** (CHANGELOG entries, dated
  assessment/ledger docs) — rewriting history is dishonest.

## 3. Prove nothing live depends on it

A deletion that breaks a gate is the worst case. Confirm **no `conformance/*.sh`, `scripts/*`,
`.github/workflows/*`, or `adapters/*`** references the artifact as wiring (not just prose). If a gate
guards it, the gate changes **atomically with** the deletion (below).

## 4. Migrate distinct value first (content-preserving)

If the artifact carries unique value, absorb it into the surviving artifact **before** deleting —
verbatim where practical — so the consolidation loses nothing (e.g. SPEC → an optional *Extended spec*
section of FEATURE-REQUEST; CODE-REVIEW-CHECKLIST → a rubric block in REVIEW-RECORD).

## 5. Control-plane refs go through ratification

If a reference lives in a control-plane file (`CLAUDE.md`, `DEVELOPMENT-PROCESS.md`,
`DEVELOPMENT-STANDARDS.md`, `conformance/`, `scripts/incept.sh`, …), the agent does **not** edit it in
the live repo. Build it in a **dev-clone** — `git clone . /private/tmp/<name>` (a literal path) — where the
guard relaxes the control-plane deny **while staying armed on the real repo**, then push the branch and
open a PR. See [`runtime-guards.md`](./runtime-guards.md) *"Doing control-plane work — the sanctioned
route"*.

> **Superseded:** this step used to prescribe the `apply.py` AMBER hand-off (author to `/tmp` scratch, a
> human runs an idempotent apply). **CP-8c (v3.124.0) abolished that** — it was *"the last mandatory
> [hand-off] for guard work."* The dev-clone replaces it: you review a **diff** (already CI-green) instead
> of a **script** whose writes you must predict, and no interpreter ever writes to your tree. Do not
> reintroduce `apply.py` out of habit. **Never** reach for `KIT_GUARD_SELFEDIT=1` for this — it is a
> *global* kill switch (destructive-op and secret-read denies included), not a control-plane permit.

The merge is unchanged: `control-plane-ratification` requires a **non-author** approval, and the recorded
GO is the control, not the keystroke. A **gate-logic** change additionally gets a **security-review of the
diff** — verify the updated gate isn't *weaker* (can't pass when the guarded thing is absent: the
green-while-dark check), with a load-bearing RED selftest fixture proving it.

## 6. Keep the gate and the deletion in one change

When a gate guards the artifact, update the gate in the **same** slice as the deletion. Otherwise the
branch is transiently broken (old gate red on the deleted file) or — worse — green-while-dark.

## 7. Verify before done

`conformance/check-links.sh` · `conformance/verify.sh --require` · the changed gate's `--selftest` ·
`conformance/badge-version.sh` (after any VERSION bump) · `sparkwright doctor`. Then independent review
(builder ≠ reviewer), and the human merge + tag.

## 8. Tombstones — what was parked, and how to get it back

Retirement is reversible only if the record survives. Park to a **history branch** rather than deleting,
and record the ref here.

> **Two tombstone variants.** A **PARK** removes the artifact from the working tree, so its entry must
> carry a history ref and a recovery command. A **FREEZE** leaves every byte in the tree and removes
> only the *maintenance obligation* and the *shipped-value claim* — so it needs **no history branch and
> no recovery command** (nothing was taken away; `git log` is the only history it can need). A freeze
> entry instead records **what froze, when, and the return condition** — the concrete event that would
> make the artifact worth maintaining again. Un-freezing is an ordinary edit: delete the banner, update
> this entry. A freeze is honesty, not enforcement: nothing reds if a later edit silently un-freezes,
> which is why the return condition must be written down rather than remembered.

### `conformance/phase-gate.sh` — the edit-time phase gate (parked 2026-08-19)

- **History ref:** `history/phase-gate-s1a-i` at `99e04f9a` — the full 6,201-line script and every one of
  its live references, exactly as they stood at the park.
- **Original merge:** `d347fd4` (PR #457, 2026-07-29, v3.193.0), `[S1a-i]`.
- **Ruling:** `D-240819-3` (amending `D-240804-1`'s DELETE to PARK), under the `D-240819-2` cut program.
- **Why:** it answered *may this tool write this path right now?* at edit time — and **no caller was ever
  wired**. `[S1a-ii]`, the `guard.sh` binding, was never built, so the gate denied nothing for its entire
  shipped life. Its only cost was real: two `check control` rows, a CI selftest step, a claims row, and
  the largest single file in the mutation sweep's corpus.
- **What was removed with it:** the two `verify.sh` rows, the `conformance-selftests` CI step, the
  `phase-gate` row in `conformance/claims.tsv`, the `edit-gate-prevention` marker and its negative in
  `conformance/promotion-contract-documented.sh`, item 7 of `docs/governance/promotion-contract.md`, and
  the section in `docs/operations/runtime-guards.md`. The `acceptance stays at merge` marker **survived**
  — the property it locks was never about this gate.
- **What re-wiring would take**, if the edit-time decision is ever wanted again: restore the script from
  the history ref; **relativise `file_path`** first (Claude Code's Edit/Write pass *absolute* paths by
  tool contract, and `pg_validate_path` refuses absolute paths rc 2 = fail-open, so naive wiring is
  silently inert — this was the original blocker); re-add the two `verify.sh` rows **and** the CI step in
  one change (`conformance/ci-selftest-coverage.sh` reds if they separate); re-add the claims row; and
  budget for latency measured at roughly 2× the per-Edit budget. Read `D-240804-1` before starting — its
  evidence against wiring this gate was never refuted, only re-dispositioned from delete to park.

### `docs/architecture/**` + `docs/plans/**` dated history — the archaeology archive (2026-08-19)

- **History ref:** `history/archaeology-2026-08` at HEAD of `chore/cut-archaeology-archive` — holds every
  archived file exactly as it stood before the cut (the branch is cut at the pre-deletion tree, so every
  dated doc is present on it).
- **What it contains:** **356 dated design/plan docs** (`docs/architecture/*.md` +
  `docs/plans/*.md`, dated `YYYY-MM-DD-` or `brief-` names), **~59,089 lines** of closed maintainer-internal
  history accumulated 2026-06 → 2026-08. The current slice's own design
  (`docs/architecture/2026-08-19-cut-archaeology-archive-design.md`) was **kept live** and is not in the archive.
- **Ruling:** `D-240819-2` Track 1 (evidence-free cut: *"archive closed design-doc history to a history
  branch"*); deletion mechanic `D-240819-4` (the mass `git rm` is an **owner** keystroke — control-plane
  mass-deletion is human-actuated even though these ordinary-class files are agent-editable).
- **Why:** the dated corpus is closed history — GO-basis notes assert tree-SHA equality and never open the
  basis file, `citation-live.sh` tests the dated-target predicate on the citation string before resolution
  (a removed dated file becomes an EXEMPT count, never UNRESOLVABLE), and `docs/architecture/**` +
  `docs/plans/**` are already `export-ignore`d, so adopters never received them. The only live gate that
  blocked was `check-links.sh`; the 35 inbound markdown links from docs that stay (`BACKLOG.md`,
  `docs/governance/meta-control-log.md`, `docs/architecture/README-v1-initiative.md`) were converted to
  backticked non-link path text first, so the cut leaves no broken link.
- **What stays:** the `docs/architecture/` and `docs/plans/` directories (each with a `README.md` index
  naming this history ref), `README-v1-initiative.md`, and the ceremony-binding convention — **new dated
  designs still land in these directories.**
- **How to recover** any archived doc. **Use the `origin/` spelling** — the bare ref name resolves only if
  you have created a local branch of it, and nobody does; measured, `git show history/…` is `fatal:
  invalid object name` on a normal clone. Fetch first if your clone predates the archive:

  ```
  git fetch origin history/archaeology-2026-08          # only if origin/history/… is missing
  git show origin/history/archaeology-2026-08:docs/architecture/<file>.md
  git restore --source origin/history/archaeology-2026-08 -- docs/plans/<file>.md
  ```

### `docs/enterprise/ROI-MODEL.md` + the `ORG-ROLLOUT.md` rollout playbook — **FROZEN** pre-adoption (2026-08-19)

- **Variant:** **FREEZE, not park.** Both files stay in the tree, fully readable, and every inbound link
  keeps resolving. **No history branch is needed or created** — nothing was removed. What was removed is
  the *maintenance obligation* and the *shipped-value claim*.
- **What froze:** all of `docs/enterprise/ROI-MODEL.md`, and in `docs/enterprise/ORG-ROLLOUT.md` the
  **rollout playbook only** — the Pilot → Expand → Fleet staging and the fleet-upgrade sequence.
- **What did NOT freeze — explicitly exempt:** ORG-ROLLOUT's **Stage 1–4 maturity model** section. It is
  the canonical home of that model and four living docs resolve their Stage references into it
  (`START-HERE.md`, `GLOSSARY.md`, `DEVELOPMENT-PROCESS.md`, `docs/operations/dora-metrics.md`). It stays
  canonical, live, and maintained; freezing it would re-open a defect a prior slice closed *by pointing
  here*. `docs/enterprise/EXEC-BRIEF.md` is likewise unaffected.
- **When:** 2026-08-19, under the `D-240819-2` Track-1 cut program (row `CUT-COLLATERAL-FREEZE`).
- **Why:** both documents were authored **ahead of any adopter**. The ROI model is arithmetic over inputs
  the kit has never observed; the rollout playbook's entry/exit criteria are reasoned, not measured.
  Presenting them as live kit value over-claims, and maintaining pre-adoption speculation costs review
  attention the cut program exists to reclaim. Freezing (rather than parking) keeps them cheap to
  resume and keeps every inbound link green.
- **RETURN CONDITION — the first real adopter.** When a first adopter runs a genuine rollout, they supply
  what these documents lack: measured baselines and real inputs for the ROI model, and observed evidence
  of which rollout stages and entry/exit criteria actually hold. At that point remove the freeze banner
  from the affected file, delete or amend this entry, and resume maintaining it against that evidence.
- **How to change one meanwhile:** ordinary edit. A freeze is a stated intent, not a gate — there is no
  check that reds on an edit to a frozen file. If you edit one substantively, either honour the return
  condition and un-freeze it, or say in the commit why the freeze still holds.

See also: `MAINTAINING.md` (versioning + §3a, authoring a control-plane change in a dev-clone),
`docs/operations/meta-control.md` (the
design-intent verify lens), `conformance/check-links.sh` (the link-scope rules above).
