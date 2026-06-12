# Slice 9e — Exec Brief + Org Rollout + ROI Model (design)

**Date:** 2026-06-10 · **Arc:** Slice 9, Tier 1 (R5) · **Version target:** MINOR → **v2.30.0**
**Input:** the review's eng-leader finding (persona scored 7) — *"credible audit substance, but every front door is engineer-level: no exec brief, no business case/ROI, no org-wide rollout/fleet-upgrade playbook"* — plus the dangling "Stage 1–4 tighten-at-scale" reference. Preceded by the **A5 competitive benchmark** (recorded as part of this slice), which supplies the brief's differentiation and the ROI's risk baseline.

## Scope

Three leadership-facing documents in `docs/enterprise/` (the auditor/leadership home), the A5 benchmark recorded as a traceable analysis, cross-links so leadership has a front door, and the dangling-ref fix. **Docs-only, additive → MINOR.** No new conformance script (an exec brief / ROI model is not a verifiable control; a grep-presence check would be the enforcement theatre the kit rejects — these are `[doc]` artifacts, verified by `check-links.sh` + human review).

Ratified at brainstorm: **brief + rollout + ROI** (full R5); ROI as a **parameterized worksheet + one labeled worked example** (no fabricated figures).

**Anonymization (kit-wide principle, applied here):** all deliverables are **generic and adoptable by any org** — no enterprise / public-media framing, no named sector, no personal-name references. The example archetype is "a regulated, privacy-sensitive mid-to-large enterprise." The *only* necessary identity reference is the real GitHub repo URL in release links. This slice also scrubs the two remaining shippable references: `docs/ROADMAP-SLICE9.md` ("enterprise-scale, children's-data" goal line and "Owner: Bradley") → generic.

## A5 — competitive benchmark (the differentiation spine)

Recorded at `docs/superpowers/reviews/2026-06-10-competitive-benchmark.md`. Findings (grounded in 2026 sources):
- The field converges on the kit's operating model (agents first-pass, humans own architecture) from two incomplete directions: **IDPs / golden paths** (Backstage 1.43, Harness, Spacelift) retrofitting agent governance — but "golden paths built for portal UIs don't translate to agent invocation"; and **ADLC governance frameworks** (Cycode, EPAM, IBM, Forrester) that describe norms but ship as methodology, not executable conformance.
- **Differentiation:** the rare offering that is both **agent-native** and **enforcement-native** (contract→reference→conformance, CI-verified, agent-runnable); **intellectual honesty as a feature** ("green ≠ verified"); **portable, vendor-neutral, no lock-in** — adopt *alongside* an IDP/CI, not instead of.
- **Business-case stat (sourced, not invented):** the field's own data shows AI adoption on weak governance drove **+30% change-failure rate and +23.5% incidents per PR** — the kit is the guardrails-first answer to exactly that.
- **Honest positioning:** the kit is **not** a platform (no UI, no catalog, no token broker) — it is the *governance & assurance layer*. The brief states this plainly.

## Documents

### 1. `docs/enterprise/EXEC-BRIEF.md` (≤ 2 pages)
The VP-Eng/CTO entry point. Sections:
- **What it is** — a portable, *executable* governance & assurance layer for agentic development; a methodology + conformance harness you own, not a platform you buy.
- **Why now** — agents run first-pass SDLC; the +30% / +23.5% field data is the risk; this is the guardrails-first answer.
- **What leadership gets** — relative assurance agents/humans can't cause irreversible damage; audit-ready evidence (compliance crosswalk + audit-evidence checklist + ratification RBAC + tested guard); vendor-neutral, no lock-in.
- **Differentiation** (from A5) — agent-native *and* enforcement-native; honesty as a feature; complements your IDP/CI.
- **Honest boundaries** — speed-bump-not-boundary; the real boundary (egress allowlist, prod credential separation, sandbox, scoped tokens) is **Org-owned** (`platform-safety-boundary.md`). Stated up front — a regulated buyer trusts the vendor that discloses limits.
- **Compliance at a glance** — one short table: SOC 2 / ISO 27001:2022 control families the kit *assures* vs *Org-owned* (pointer to `compliance-crosswalk.md`, not a re-derivation).
- **Where to go next** — a pointer table into the engineer/auditor docs (START-HERE, RUNBOOK, conformance/README, enterprise/).

### 2. `docs/enterprise/ORG-ROLLOUT.md`
- **Adoption stages — Pilot → Expand → Fleet**, each with entry/exit criteria (pilot: 1–2 teams, gates advisory, liberal waivers, learn the loop; expand: ratchet on, gates block changed code, branch protection + CODEOWNERS + RBAC; fleet: org-wide, all gates blocking, central profile ownership, version-pinned).
- **Canonical Stage 1–4 "tighten at scale" model** (fixes the dangling ref) — one unified conformance-strictness progression:
  - **Stage 1** (new/pilot): core gates advisory; waivers liberal; progressive-delivery basics; branch protection on.
  - **Stage 2**: gates blocking on *changed* code; coverage ratchet from baseline; `secret-scan` + `branch-protection` non-negotiable.
  - **Stage 3**: all 7 §14 gates blocking; supply-chain (SBOM + provenance) enforced; waivers expiring toward zero.
  - **Stage 4** (production scale): SRE-style hard gating (error-budget / DORA freezes); zero waivers; full attestation.
- **Fleet upgrade** — rolling a new kit *version* across many repos: adopters pin a version (`CLAUDE.md` "Kit version adopted"); upgrade = read CHANGELOG delta → re-run conformance → absorb any new *required* gate (a MAJOR) via the 9c waiver ramp → bump the pin. **Central profile ownership**: the platform/governance team owns the org's kit copy; agents propose, humans ratify, at scale.

### 3. `docs/enterprise/ROI-MODEL.md`
- **Inputs (adopter supplies):** team size, avg production-incident cost, deploy frequency, current audit-evidence prep hours/cycle, agentic token spend.
- **Three value levers (logic shown):** (1) risk reduction — incidents avoided × incident cost, downside baselined on A5's +30% / +23.5%; (2) audit-evidence time saved — hours saved × loaded rate; (3) agentic velocity **net** of guardrail overhead (~24K governance tokens/feature, prompt-cached) and token cost.
- **Output:** low/expected/high ranges + sensitivity on the 2–3 highest-impact inputs; every assumption labeled; bold disclaimer — *"a planning model parameterized by your inputs, not a measured result or guarantee."*
- **One worked example:** a fictional, unnamed regulated enterprise (~200 engineers, stated inputs), computed end-to-end, labeled *"illustration of the method, not a claim about your org."* No real org, sector, or person named.

## Cross-links & dangling-ref fix

| File | Change |
|------|--------|
| `README.md` | "For engineering leaders →" pointer to `docs/enterprise/EXEC-BRIEF.md` |
| `START-HERE.md` | leadership on-ramp line (read the brief first; engineers continue to Inception) |
| `docs/enterprise/README.md` | index the 3 new docs |
| `DEVELOPMENT-PROCESS.md` (~:235) | repoint "Stage 1–4 scale progression in `DEVELOPMENT-STANDARDS.md`" → `docs/enterprise/ORG-ROLLOUT.md` canonical model |
| `docs/operations/dora-metrics.md` (~:36) | same repoint |
| (sweep) | grep for any other "Stage 1–4" / "tighten at scale" refs and point them at the canonical model |

## Files

| File | Change |
|------|--------|
| `docs/enterprise/EXEC-BRIEF.md` | **New** |
| `docs/enterprise/ORG-ROLLOUT.md` | **New** (incl. canonical Stage 1–4 model) |
| `docs/enterprise/ROI-MODEL.md` | **New** (worksheet + worked example) |
| `docs/superpowers/reviews/2026-06-10-competitive-benchmark.md` | **New** (A5 record) |
| `README.md`, `START-HERE.md`, `docs/enterprise/README.md` | cross-links |
| `DEVELOPMENT-PROCESS.md`, `docs/operations/dora-metrics.md` | dangling-ref repoint |
| `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-SLICE9.md` | 2.30.0; 9e row → shipped |

## Verification
- `sh conformance/check-links.sh` green (all new cross-links + the repointed Stage 1–4 refs resolve).
- No "Stage 1–4 … in `DEVELOPMENT-STANDARDS.md`" reference remains dangling (grep returns only the canonical definition + resolving pointers).
- `sh conformance/verify.sh` unaffected (no control changes); kit CI (`conformance`/`bootstrap`/`docs-links`) green.
- Brief is ≤ 2 pages; ROI disclaimer present; every ROI assumption labeled; worked example labeled as illustration.
- Governance: feature branch → PR → human ratification; the brief/ROI claims get a review pass for over-claim (the kit must not violate its own honesty standard).

## Out of scope / deferred
- A quantified ROI *calculator* tool (spreadsheet/script) — the worksheet is prose + a worked example; an interactive calculator is a later option.
- Slides / a deck — the brief is a document; presentation packaging is the adopter's.
- The A3 cross-doc consistency *linter* — 9e fixes the Stage 1–4 dangling ref by hand; turning that into an automated check stays A3's job.

## Known implications
- The ROI model is deliberately un-scripted (prose + worked example). It is the one place the kit states $ value; the parameterized + labeled-illustration form is what keeps it on the honest side of the kit's own anti-false-assurance line.
