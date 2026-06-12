# Exec Brief + Org Rollout + ROI Model (Slice 9e) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give engineering leaders a front door to the kit — a ≤2-page exec brief, an org-rollout playbook (with the canonical Stage 1–4 "tighten at scale" model that fixes the dangling ref), and an honest ROI worksheet + worked example — all generic and adoptable by any org.

**Architecture:** Three new leadership docs in `docs/enterprise/`, the A5 competitive benchmark recorded as a traceable analysis, leadership cross-links from `README.md`/`START-HERE.md`, and a repoint of two dangling "Stage 1–4" references. Docs-only, additive → MINOR v2.30.0. No new conformance script (an exec brief is not a verifiable control; `check-links.sh` + human review are the gates).

**Tech Stack:** Markdown only. Verification via `conformance/check-links.sh` and `grep` (anonymization + dangling-ref sweeps).

---

## Execution notes

- **All files here are agent-editable** — none are control-plane (no `.claude/`, `.github/workflows/`, `CODEOWNERS`, `guard*`, `kit-guard`, `pre-push`). No `cp` handoffs.
- **Anonymization is a hard requirement on every deliverable** ([[kit-anonymization]]): no "enterprise"/public-media framing, no named sector, no personal names. Archetype = "a regulated, privacy-sensitive mid-to-large enterprise (~200 engineers)." Each task ends with an anonymization grep.
- **Branch:** `feature/slice-9e-exec-brief` (already created). Spec: `docs/superpowers/specs/2026-06-10-slice9e-exec-brief-design.md`.

## File structure

| File | Responsibility |
|------|----------------|
| `docs/superpowers/reviews/2026-06-10-competitive-benchmark.md` (new) | A5 record — landscape + differentiation + the business-case stat, with sources |
| `docs/enterprise/EXEC-BRIEF.md` (new) | ≤2pp VP/CTO entry point |
| `docs/enterprise/ORG-ROLLOUT.md` (new) | Pilot→Expand→Fleet + canonical Stage 1–4 model + fleet upgrade |
| `docs/enterprise/ROI-MODEL.md` (new) | Parameterized worksheet + one labeled worked example |
| `README.md`, `START-HERE.md`, `docs/enterprise/README.md` (modify) | Leadership cross-links |
| `DEVELOPMENT-PROCESS.md`, `docs/operations/dora-metrics.md` (modify) | Repoint the Stage 1–4 dangling ref |
| `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-SLICE9.md` (modify) | 2.30.0; 9e row → shipped |

---

## Task 1: A5 competitive benchmark record

**Files:** Create `docs/superpowers/reviews/2026-06-10-competitive-benchmark.md`

- [ ] **Step 1: Write the benchmark record.** Must contain these substantive findings (grounded in the 2026 web research already done):
  - **Landscape:** the field converges on the kit's operating model (agents first-pass, humans own architecture) from two incomplete directions — (a) **IDPs / golden paths** (Backstage 1.43 with experimental MCP token support + Scaffolder actions exposed to Claude/Cursor; Harness Knowledge Agent; Spacelift) retrofitting agent governance, with the community's own caveat that *"golden paths built for portal UIs, forms, and wizards don't translate to agent invocation"*; (b) **ADLC governance frameworks** (Cycode "Securing the ADLC", EPAM, IBM, Forrester, recent arXiv "governance norms → enforceable controls") that describe the operating model as **norms/methodology, not executable conformance**.
  - **Differentiation:** the rare offering that is both **agent-native** and **enforcement-native** (contract→reference→conformance, CI-verified, agent-runnable); **intellectual honesty as a feature** ("green ≠ verified", three-state conformance, speed-bump-not-boundary); **portable, vendor-neutral, no lock-in** — adopt *alongside* an IDP/CI, not instead of.
  - **Business-case stat (sourced):** the field's own data shows AI adoption on weak governance/catalog hygiene drove **+30% change-failure rate and +23.5% incidents per PR** — the kit is the guardrails-first answer.
  - **Honest positioning:** the kit is **not** a platform (no UI, no catalog, no token broker) — it is the *governance & assurance layer*.
  - **Sources** section with the URLs (cio.com, forrester.com, cycode.com, epam.com, ibm.com, platformengineering.com Backstage 1.43, the arXiv governance/knowledge-activation papers).
  - **Anonymization:** generic throughout; no named adopter, no person.

- [ ] **Step 2: Verify + commit.**
  Run: `grep -niE "enterprise|public.media|bradley|bradleyjames" docs/superpowers/reviews/2026-06-10-competitive-benchmark.md || echo "clean"` → `clean`.
  ```bash
  git add docs/superpowers/reviews/2026-06-10-competitive-benchmark.md
  git commit -m "docs(slice-9e): A5 competitive benchmark record (differentiation + business-case stat)"
  ```

---

## Task 2: `EXEC-BRIEF.md`

**Files:** Create `docs/enterprise/EXEC-BRIEF.md`

- [ ] **Step 1: Write the brief (≤ 2 pages).** Required sections and content:
  1. **What it is** — "A portable, *executable* governance & assurance layer for agentic software development. A methodology + conformance harness you own and run in your own CI — not a platform you buy or a runtime you depend on."
  2. **Why now** — agents increasingly run first-pass SDLC; ungoverned AI adoption measurably *raised* risk (**+30% change-failure rate, +23.5% incidents/PR** — cite the A5 record). The kit is the guardrails-first answer: agents move fast *inside* enforced boundaries.
  3. **What leadership gets** — (a) relative assurance that agents *and* humans cannot trivially cause irreversible damage (the §13 guard + branch protection + destructive-action denials, now multi-runtime); (b) **audit-ready evidence** — `docs/enterprise/compliance-crosswalk.md`, `conformance/audit-evidence-checklist.md`, `docs/enterprise/ratification-rbac.md`, a tested guard; (c) vendor-neutral, stack-neutral, no lock-in.
  4. **How it's different** (from A5) — agent-native *and* enforcement-native; honesty as a feature ("green ≠ verified"); complements your IDP/CI rather than replacing it.
  5. **Honest boundaries** — the runtime guard is a *speed bump, not a boundary*; the real controls (network-egress allowlist, separate prod credentials, sandboxed FS, scoped tokens) are **Org-owned** (`platform-safety-boundary.md`). Stated up front — a regulated buyer trusts the vendor that discloses limits.
  6. **Compliance at a glance** — a one-row-per-framework summary table (SOC 2, ISO 27001:2022) with columns *"kit assures"* vs *"Org-owned"*, then "full mapping → `compliance-crosswalk.md`." Do **not** re-derive the crosswalk (avoids drift).
  7. **Where to go next** — pointer table: leaders → this brief + `ORG-ROLLOUT.md` + `ROI-MODEL.md`; engineers → `START-HERE.md`; auditors → `docs/enterprise/`; operators → `RUNBOOK` + `conformance/README.md`.
  - Keep to ~2 pages. Lead with honest scope; cite the A5 stat; no over-claim.
  - **Anonymization:** generic enterprise only; no named org/sector/person.

- [ ] **Step 2: Verify length, links, anonymization + commit.**
  Run: `wc -l docs/enterprise/EXEC-BRIEF.md` (target ≤ ~120 lines for ~2pp); `sh conformance/check-links.sh 2>&1 | tail -1` → links OK; `grep -niE "enterprise|public.media|bradley" docs/enterprise/EXEC-BRIEF.md || echo clean` → `clean`.
  ```bash
  git add docs/enterprise/EXEC-BRIEF.md
  git commit -m "docs(enterprise): 9e — EXEC-BRIEF.md, the leadership entry point"
  ```

---

## Task 3: `ORG-ROLLOUT.md` (incl. canonical Stage 1–4)

**Files:** Create `docs/enterprise/ORG-ROLLOUT.md`

- [ ] **Step 1: Write the rollout playbook.** Required content:
  - **Adoption stages — Pilot → Expand → Fleet**, each with explicit entry/exit criteria:
    - *Pilot* — 1–2 teams, one stack; gates advisory; liberal time-boxed waivers; goal = learn the loop. Exit: one feature shipped through the full loop; conformance run understood.
    - *Expand* — several teams; coverage ratchet on (`scripts/coverage-ratchet.sh`); gates blocking on *changed* code; branch protection + CODEOWNERS + ratification RBAC on. Exit: all teams on protected main; waiver register active.
    - *Fleet* — org-wide; all 7 §14 gates blocking; central profile ownership; version-pinned; fleet-upgrade process running.
  - **Canonical Stage 1–4 "tighten at scale" model** (this is the authoritative definition the dangling refs will point to — give it an anchor heading `## Maturity stages (1–4): tightening conformance at scale`):
    - **Stage 1** (new/pilot): core gates advisory; waivers liberal; progressive-delivery basics (staged rollout); branch protection on.
    - **Stage 2**: gates blocking on changed code; coverage ratchet from a committed baseline; `secret-scan` + `branch-protection` non-negotiable.
    - **Stage 3**: all 7 §14 gates blocking; supply-chain (SBOM + provenance) enforced; waivers expiring toward zero.
    - **Stage 4** (production scale): SRE-style hard gating — error-budget / DORA freezes (`docs/operations/dora-metrics.md`); zero waivers; full attestation.
    - Note this unifies the previously-scattered maturity mentions (DORA gating, progressive-delivery's Stage-1 baseline, error-budget promotion).
  - **Fleet upgrade** — rolling a new kit *version* across many repos: adopters pin a version (`CLAUDE.md` "Kit version adopted"); upgrade = read the `CHANGELOG.md` delta → re-run `conformance/verify.sh` → absorb any new *required* gate (a MAJOR) via the 9c waiver ramp (`templates/WAIVER-REGISTER.md`) → bump the pin. **Central profile ownership**: the platform/governance team owns the org's kit copy; agents propose, humans ratify, at scale (`docs/enterprise/ratification-rbac.md`).
  - **Anonymization:** generic enterprise only.

- [ ] **Step 2: Verify + commit.**
  Run: `sh conformance/check-links.sh 2>&1 | tail -1`; `grep -niE "enterprise|public.media|bradley" docs/enterprise/ORG-ROLLOUT.md || echo clean`.
  ```bash
  git add docs/enterprise/ORG-ROLLOUT.md
  git commit -m "docs(enterprise): 9e — ORG-ROLLOUT.md with the canonical Stage 1-4 tighten-at-scale model"
  ```

---

## Task 4: `ROI-MODEL.md` (worksheet + worked example)

**Files:** Create `docs/enterprise/ROI-MODEL.md`

- [ ] **Step 1: Write the ROI model.** Required content:
  - **Bold disclaimer at the top:** "This is a *planning model parameterized by your inputs* — not a measured result, a benchmark, or a guarantee. It is consistent with the kit's honesty standard: it shows the logic and labels every assumption; it does not assert savings."
  - **Inputs (adopter supplies)** — a table: team size (N engineers), avg fully-loaded cost of a production incident, deploy frequency (per month), current audit-evidence prep (hours per audit cycle), agentic token spend (per feature or per month), loaded engineer hourly rate.
  - **Three value levers (show the formula for each):**
    1. *Risk reduction* — `incidents_avoided × avg_incident_cost`, where the *avoided downside* is baselined on the A5 field data (+30% change-failure, +23.5% incidents/PR for AI-without-governance). State it as a *reduction of an elevated baseline*, not a raw gain.
    2. *Audit-evidence time saved* — `hours_saved_per_cycle × cycles_per_year × loaded_rate` (crosswalk + audit-evidence checklist + conformance artifacts replace manual evidence-gathering).
    3. *Agentic velocity, net* — delivery speedup **minus** guardrail overhead (~24K governance tokens/feature, largely prompt-cached after first load) **minus** token cost. Explicitly *net*, not gross.
  - **Output** — low / expected / high ranges, plus a *sensitivity note* identifying the 2–3 inputs that dominate the result. Every assumption labeled inline.
  - **One worked example** — heading `## Worked example (illustration of the method — not a claim about your org)`: a fictional, **unnamed** regulated enterprise, ~200 engineers, with explicitly-stated example inputs, computed through all three levers to a 12-month range. End with: "These numbers are illustrative inputs to demonstrate the worksheet; substitute your own."
  - **Anonymization:** no named org/sector/person anywhere.

- [ ] **Step 2: Verify + commit.**
  Run: `grep -niE "enterprise|public.media|bradley" docs/enterprise/ROI-MODEL.md || echo clean`; confirm the disclaimer + the "illustration" label are present (`grep -c "planning model\|illustration of the method" docs/enterprise/ROI-MODEL.md` → ≥ 2).
  ```bash
  git add docs/enterprise/ROI-MODEL.md
  git commit -m "docs(enterprise): 9e — ROI-MODEL.md (parameterized worksheet + labeled worked example)"
  ```

---

## Task 5: Cross-links + dangling-ref fix

**Files:** Modify `README.md`, `START-HERE.md`, `docs/enterprise/README.md`, `DEVELOPMENT-PROCESS.md`, `docs/operations/dora-metrics.md`

- [ ] **Step 1: Add leadership cross-links.**
  - `README.md`: add a "**For engineering leaders →** `docs/enterprise/EXEC-BRIEF.md`" pointer near the top/intro (match existing link style).
  - `START-HERE.md`: add a line — "Leaders/evaluators: read `docs/enterprise/EXEC-BRIEF.md` first (what/why/risk/ROI); engineers continue to Inception below."
  - `docs/enterprise/README.md`: index the three new docs (EXEC-BRIEF, ORG-ROLLOUT, ROI-MODEL) with one-line descriptions.

- [ ] **Step 2: Repoint the Stage 1–4 dangling refs.** Replace, in `DEVELOPMENT-PROCESS.md` and `docs/operations/dora-metrics.md`, the phrase pointing the "Stage 1–4 scale progression" at `DEVELOPMENT-STANDARDS.md` with a pointer to the canonical model:
  - New target text: `the Stage 1–4 maturity progression in \`docs/enterprise/ORG-ROLLOUT.md\``.
  - Use the exact surrounding context from each file (locate with `grep -n "Stage 1–4" DEVELOPMENT-PROCESS.md docs/operations/dora-metrics.md`).

- [ ] **Step 3: Sweep for residual dangling refs.**
  Run: `grep -rn "Stage 1–4\|Stage 1-4\|tighten at scale" --include="*.md" . | grep -v "docs/superpowers/"`
  Expected: the only "Stage 1–4 … in DEVELOPMENT-STANDARDS.md" forms are gone; remaining hits either *define* the model (ORG-ROLLOUT.md) or point at it. No ref points at a non-existent definition.

- [ ] **Step 4: Verify + commit.**
  Run: `sh conformance/check-links.sh 2>&1 | tail -1` → links OK.
  ```bash
  git add README.md START-HERE.md docs/enterprise/README.md DEVELOPMENT-PROCESS.md docs/operations/dora-metrics.md
  git commit -m "docs(slice-9e): leadership cross-links + repoint Stage 1-4 dangling ref to ORG-ROLLOUT canonical model"
  ```

---

## Task 6: Release (VERSION / CHANGELOG / roadmap)

**Files:** Modify `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-SLICE9.md`

- [ ] **Step 1: Bump `VERSION`** to:
  ```
  2.30.0
  ```

- [ ] **Step 2: Prepend the CHANGELOG entry** above `## [2.29.0]`:
  ```markdown
  ## [2.30.0] - 2026-06-10

  Exec brief + org rollout + ROI model (Slice 9e, Tier 1 of the "Honest Assurance & Adoption Reach" arc). Closes the review's eng-leader finding — credible audit substance but no leadership front door. **MINOR** — additive docs; no new conformance gate (an exec brief is not a verifiable control).

  ### Added
  - **`docs/enterprise/EXEC-BRIEF.md`** — ≤2-page VP/CTO entry point: what/why/what-you-get, A5-grounded differentiation, honest boundaries, compliance-at-a-glance, pointers.
  - **`docs/enterprise/ORG-ROLLOUT.md`** — Pilot→Expand→Fleet adoption, the canonical **Stage 1–4 "tighten at scale"** maturity model, and the fleet version-upgrade process.
  - **`docs/enterprise/ROI-MODEL.md`** — parameterized ROI worksheet (adopter inputs + three value levers) and one labeled worked example; honest "planning model, not a result" framing.
  - **`docs/superpowers/reviews/2026-06-10-competitive-benchmark.md`** — the A5 record behind the brief's differentiation (with sources).

  ### Changed
  - Leadership cross-links from `README.md` / `START-HERE.md` / `docs/enterprise/README.md`.
  - **Fixed the dangling "Stage 1–4" reference**: `DEVELOPMENT-PROCESS.md` and `docs/operations/dora-metrics.md` now point at the canonical model in `ORG-ROLLOUT.md`.
  - **Anonymized** remaining shippable references (ROADMAP goal line + owner) to a generic regulated-enterprise archetype.
  ```

- [ ] **Step 3: Mark the roadmap 9e row shipped.** In `docs/ROADMAP-SLICE9.md`, replace the `9e` row with:
  ```markdown
  | **9e** ✅ | B | **Exec brief + org rollout + ROI** (R5) — *shipped v2.30.0.* `EXEC-BRIEF.md` (what/why/assurance/honest-boundary/compliance-at-a-glance), `ORG-ROLLOUT.md` (pilot→expand→fleet + canonical Stage 1–4 + fleet upgrade), `ROI-MODEL.md` (worksheet + labeled worked example), A5 benchmark recorded. Fixed the Stage 1–4 dangling ref; anonymized shippable refs. | P1 | MINOR ✅ |
  ```

- [ ] **Step 4: Verify + commit.**
  Run: `sh conformance/check-links.sh 2>&1 | tail -1`; `cat VERSION` → `2.30.0`.
  ```bash
  git add VERSION CHANGELOG.md docs/ROADMAP-SLICE9.md
  git commit -m "chore(release): 2.30.0 — exec brief + org rollout + ROI model (9e)"
  ```

---

## Task 7: Final verification + independent review + PR

- [ ] **Step 1: Full doc-integrity + anonymization sweep.**
  ```sh
  sh conformance/check-links.sh 2>&1 | tail -1
  sh conformance/verify.sh 2>&1 | tail -2
  grep -rniE "enterprise|public.media" --include="*.md" docs/enterprise/ README.md START-HERE.md DEVELOPMENT-PROCESS.md docs/operations/dora-metrics.md docs/ROADMAP-SLICE9.md || echo "no enterprise in shippable"
  grep -rn "Stage 1–4|Stage 1-4" --include="*.md" . | grep "DEVELOPMENT-STANDARDS" && echo "DANGLING REMAINS (fix)" || echo "no dangling Stage 1-4 ref"
  ```
  Expected: links OK; verify.sh OK; "no enterprise in shippable"; "no dangling Stage 1-4 ref".

- [ ] **Step 2: Independent review (builder ≠ sole reviewer).** Dispatch a reviewer focused on the kit's own honesty standard applied to *itself*: does the EXEC-BRIEF over-claim (vs the disclosed boundaries)? Does the ROI-MODEL assert any number as fact rather than labeled input/illustration? Is the differentiation in A5 fair (not strawmanning competitors)? Is anything non-generic (named org/sector/person)? Fix any finding.

- [ ] **Step 3: Push + open PR.**
  ```bash
  git push -u origin feature/slice-9e-exec-brief
  gh pr create --base main --head feature/slice-9e-exec-brief \
    --title "Slice 9e — Exec Brief + Org Rollout + ROI (v2.30.0)" --body-file /tmp/pr-9e-body.md
  ```
  (Write `/tmp/pr-9e-body.md` first: what ships, A5 differentiation, the honest ROI framing, the Stage 1–4 fix, anonymization.)

- [ ] **Step 4: Confirm CI green; hand to Bradley to ratify (merge).** The agent never self-merges; Bradley squash-merges under branch protection.

---

## Self-review (against the spec)

- **Spec coverage:** A5 record (Task 1) · EXEC-BRIEF (Task 2) · ORG-ROLLOUT + canonical Stage 1–4 (Task 3) · ROI worksheet + worked example (Task 4) · cross-links + dangling-ref repoint + sweep (Task 5) · MINOR 2.30.0 (Task 6) · review-for-over-claim + PR (Task 7) · anonymization enforced per task and swept in Task 7. All spec items covered.
- **Placeholder scan:** content points are concrete (differentiation, the +30%/+23.5% stat, the four Stage definitions, the three ROI levers with formulas, inputs, disclaimer). The docs' final prose is written by the implementer from these points — not placeholders.
- **Consistency:** "Stage 1–4 canonical model lives in ORG-ROLLOUT.md" is used identically in Tasks 3, 5, 6; the +30%/+23.5% stat and the "planning model / illustration" labels are consistent across Tasks 1, 2, 4; version 2.30.0 consistent across Task 6.
