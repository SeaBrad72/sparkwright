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
`DEVELOPMENT-STANDARDS.md`, `conformance/`, `scripts/incept.sh`, …), the agent does **not** edit it
directly: build the change in `/tmp` scratch and have a human run an idempotent `apply.py`
(`MAINTAINING.md` AMBER mechanic). A **gate-logic** change additionally gets a **security-review of the
scratch** — verify the updated gate isn't *weaker* (can't pass when the guarded thing is absent: the
green-while-dark check), with a load-bearing RED selftest fixture proving it.

## 6. Keep the gate and the deletion in one change

When a gate guards the artifact, update the gate in the **same** slice as the deletion. Otherwise the
branch is transiently broken (old gate red on the deleted file) or — worse — green-while-dark.

## 7. Verify before done

`conformance/check-links.sh` · `conformance/verify.sh --require` · the changed gate's `--selftest` ·
`conformance/badge-version.sh` (after any VERSION bump) · `sparkwright doctor`. Then independent review
(builder ≠ reviewer), and the human merge + tag.

See also: `MAINTAINING.md` (versioning + the apply.py mechanic), `docs/operations/meta-control.md` (the
design-intent verify lens), `conformance/check-links.sh` (the link-scope rules above).
