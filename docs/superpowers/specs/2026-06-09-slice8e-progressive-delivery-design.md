# Design — Slice 8e: Progressive-delivery reference + smoke gates

**Date:** 2026-06-09
**Status:** Approved (design) — pending spec review
**Author:** Bradley James + agent
**Roadmap:** Fifth sub-slice of Slice 8 (continuity & safe-delivery hardening). Arc-of-record: `docs/superpowers/ideation/2026-06-08-delivery-safety-continuity-gaps.md`. Closes gaps **B2** (progressive delivery has no reference) + **B3** (post-deploy smoke / synthetic verification is thin).

---

## 1. Goal

Ship the **reference leg** of progressive delivery. The contract exists (`DEVELOPMENT-PROCESS.md` §10: canary / blue-green / staged + automated canary analysis) and the conformance exists (8b `definition-of-deployable.md` already gates "progressive-delivery plan" and "smoke test referenced") — but there is **no reference explaining how**, and the §14 `deploy-prod` reference is a bare `echo` with no smoke gate. 8e ships the how-to + a stack-neutral smoke gate, and **tightens the one 8b checklist row** that under-specifies the smoke *gate*. Reference-only — no new script (the gate is multi-stage and behavioural; reliable enforcement is the existing checklist + reference, not a cross-stack YAML-ordering grep). MINOR → **2.23.0**.

## 2. The reframing that shaped this (multi-stage smoke)

"Post-deploy smoke gate" undersells progressive delivery. The *point* of canary/blue-green is to validate **before** full production exposure. So smoke/validation is a gate at **every promotion boundary**:
- smoke the **lower environments** (QA/UAT) before promoting (7a);
- smoke the **canary slice / green stack *before* widening or cutover** — the highest-value gate, catching a bad release while its blast radius is 1–5% of traffic;
- smoke **after full rollout** to confirm;
- with **automated canary analysis** (error rate / latency / saturation vs. SLO, §9) as the *automated* "validate-before-widening" abort.

The reference leads with this; the "post-deploy smoke gate" is that pattern applied at the prod boundary.

## 3. Decisions

- **Reference-only + tighten the existing 8b row** (the chosen option). 8b's checklist is the conformance; 8e gives its progressive-delivery + smoke rows a reference and sharpens the smoke row to require the *gate* (deploy → smoke → rollback-on-fail), not just a mention.
- **No new conformance script.** A post-deploy smoke *gate* is defined by step **ordering + failure semantics** in a deploy workflow — unreliable to detect across stacks (the 8d load-test-tooling lesson: a check that can't reliably detect what it gates is theater). The uncovered thing ("the gate is actually wired, and smoke ran on the canary before widening") is a pipeline **behaviour** → judgment → a tightened **Manual** checklist row + a reference, not a brittle grep.
- **Stack-neutral, tooling named Org-owned** (the chosen option). The reference describes strategies and shows an inert smoke-gate workflow; Argo Rollouts / Flagger / flag-driven rollout are named as Org-owned choices (consistent with 8d keeping load-test tooling Org-owned). No tool-coupled profile manifests.
- **No new checklist, no new gate.** The §7 gate set is unchanged; 8b's Definition of Deployable already gates this at Release.

## 4. Deliverables

| # | File | Change |
|---|------|--------|
| A | `docs/operations/progressive-delivery.md` (new) | The reference: strategies, multi-stage smoke gates, canary analysis, rollback |
| B | `DEVELOPMENT-STANDARDS.md` §14 (`deploy-prod` reference) | Replace the bare `echo` with a stack-neutral **deploy → smoke → rollback-on-fail** pattern |
| C | `conformance/definition-of-deployable.md` (rows 5 + 6, blank + worked) | Tighten the smoke row to the *gate* + multi-stage; reference the new doc |
| D | `DEVELOPMENT-PROCESS.md` §10 (progressive-delivery subsection) | Reference the new doc |
| E | `CLAUDE.md` DoD Production line | "smoke-tested" → reference the gate pattern (`docs/operations/progressive-delivery.md`) |
| F | `conformance/README.md` | A note that the deployable checklist pairs with this reference (no new check) |
| Meta | `VERSION` 2.23.0 · `CHANGELOG.md` · `docs/ROADMAP-KIT.md` (8e row) |

## 5. Detailed design — `docs/operations/progressive-delivery.md`

Stack-neutral reference (joins `docs/operations/resilience-verification.md`). Sections:
- **Purpose** + the principle: *reduce blast radius — validate on a slice before full exposure.*
- **Strategies:**
  - **Staged rollout** — staging → small % → full (the §10 default; the Stage-1 baseline).
  - **Canary** — deploy to a small production slice, **smoke it + run canary analysis** (watch error rate / latency / saturation vs. SLO, §9), then **widen or abort**. The cheapest rollback is "don't widen."
  - **Blue-green** — deploy to the idle green stack, **smoke green at zero live traffic**, then cut over; keep blue warm for instant rollback.
- **Smoke / validation gates — at every boundary** (the §2 framing): lower-env (QA/UAT) → **canary/green before widening** → post-full-rollout. Each boundary: a smoke/synthetic check that **gates** promotion (fail → don't promote / roll back).
- **Automated canary analysis** — define abort thresholds (error-rate, p95/p99 latency, saturation) against the SLO/error budget (§9); the analysis is the automated "validate-before-widening" gate. Soft → gating maturity progression (mirrors §9 error budgets).
- **Rollback** — per §10 preference order (flag-off → redeploy previous → revert). In canary/blue-green, rollback at the slice/green stage is "don't widen / don't cut over" — the lowest-blast-radius rollback.
- **Tooling (Org-owned)** — Argo Rollouts, Flagger, a service-mesh canary, or a flag-driven staged rollout (§10 feature flags). The kit standardizes the **practice**, not the tool.

## 6. Detailed design — §14 `deploy-prod` smoke gate

Replace the current reference block's single step with the **deploy → smoke → rollback-on-fail** pattern (inert; adopters wire real commands):
```yaml
deploy-prod:
  needs: ci
  if: github.event_name == 'push' && github.ref == 'refs/heads/main'
  environment: production   # set required reviewers on this environment in repo settings
  runs-on: ubuntu-latest
  steps:
    - run: echo "promote the verified artifact to production (canary/blue-green — see docs/operations/progressive-delivery.md)"
    - name: smoke
      run: echo "run post-deploy smoke tests against the new release (and the canary slice before widening)"
    - name: rollback-on-smoke-failure
      if: failure()
      run: echo "smoke failed — roll back (flag-off / redeploy previous) per DEVELOPMENT-PROCESS.md §10"
```
The `if: failure()` rollback step is what makes it a **gate** (a failed smoke aborts/rolls back, not just logs). Surrounding prose notes that the same smoke gate fires at the canary/green boundary *before* widening — the reference doc has the full multi-stage picture.

## 7. Detailed design — tighten the 8b checklist (rows 5 + 6)

In `conformance/definition-of-deployable.md`:
- **Row 5 (blank)** — append a reference: "Progressive-delivery plan — canary / blue-green / staged (§10; `docs/operations/progressive-delivery.md`); N/A at Stage 1 with reason *(wired)*".
- **Row 6 (blank)** — tighten from "Smoke test **defined** and post-deploy result recorded" to: "**Post-deploy smoke gate wired (deploy → smoke → rollback-on-fail), and smoke run at each promotion boundary** incl. the canary/green slice before widening (`docs/operations/progressive-delivery.md`); result recorded *(tested)*".
- **Row 6 (worked example)** — update the evidence to reflect the gate: "smoke gate in `deploy-prod` (rollback-on-fail); canary smoked before widening; run #1423 green".

The Auto/Manual split is unchanged (row 5 + 6 stay **Manual** — they are behaviours a human verifies). No script change.

## 8. Wiring detail

- **`DEVELOPMENT-PROCESS.md` §10** — append to the "automated canary analysis" line: "(reference: `docs/operations/progressive-delivery.md`)".
- **`CLAUDE.md` DoD Production line** — "smoke-tested" → "smoke-tested (post-deploy gate; `docs/operations/progressive-delivery.md`)".
- **`conformance/README.md`** — add a one-line note under the index (or in the deployable rows) that `definition-of-deployable.md` pairs with `docs/operations/progressive-delivery.md` for the *how* (no new check; the reference completes the contract→reference→conformance triad).
- **No `audit-evidence-checklist.md` change** — the existing "Release readiness · Definition of Deployable" row already covers it.
- **No `.github/workflows/ci.yml` change** — no new script to dogfood; `check-links.sh` already runs and covers the new doc's links.

## 9. Validation / testing

- `sh conformance/check-links.sh` → 0 (the new doc's references resolve; the §10/§14/DoD/README/checklist references to `docs/operations/progressive-delivery.md` are backtick paths or valid links).
- `sh conformance/ci-gates.sh profiles/*/ci.yml` (all 10) → green (no gate-id change; the §14 edit is a doc snippet, not a profile workflow).
- `sh conformance/deployable-ready.sh --selftest` → green (unchanged; the row tightening is prose in the checklist, not a script change).
- All other conformance green (no regression).
- `grep` confirms: §14 deploy-prod block has a `smoke` + `rollback-on-smoke-failure` step; row 6 contains "rollback-on-fail"; the new doc exists and is referenced from §10, §14, DoD, the checklist.

## 10. Risks & mitigations

- **Over-claiming the smoke gate is enforced** — the tightened row 6 is **Manual**; the script (`deployable-ready.sh`) still only greps "smoke referenced." Mitigation: the row stays Manual (a human verifies the gate is wired); the reference makes "what good looks like" explicit; we do **not** add a grep that would falsely imply automated verification of the gate.
- **§14 snippet drift** — the smoke-gate snippet is inert/illustrative. Mitigation: it is clearly marked "(inert here; adopters wire it)" in the surrounding prose (already the §14 convention).
- **Doc-only slice feels light vs. 8b–8d** — intentional: 8e is the *reference* leg of a triad whose contract + conformance already shipped. Adding a script would duplicate 8b. Honest YAGNI.

## 11. Out of scope

- A new conformance script / checklist (8b's Definition of Deployable already gates this).
- Tool-coupled canary manifests in the profile (Org-owned).
- DORA metrics — **8f** (the arc's final slice).
- Any change to the 8 application CI gate-ids or §14's gate set (the `deploy-prod` reference is not one of the gates).

## 12. Definition of Done

- `docs/operations/progressive-delivery.md` created (strategies, multi-stage smoke gates, canary analysis tied to §9, rollback, Org-owned tooling).
- §14 `deploy-prod` reference shows deploy → smoke → rollback-on-fail.
- `definition-of-deployable.md` rows 5 + 6 tightened (gate + multi-stage smoke; reference the doc); row 6 worked-example evidence updated.
- §10 + DoD + `conformance/README.md` reference the new doc.
- All conformance green; `check-links.sh` 0; no §14/gate-id change; no new script.
- `VERSION` 2.23.0; CHANGELOG 2.23.0 entry; ROADMAP 8e row.
- Feature branch → PR → **human ratification** (governing-doc surface → **security-owner lens**). Agent never self-merges.
