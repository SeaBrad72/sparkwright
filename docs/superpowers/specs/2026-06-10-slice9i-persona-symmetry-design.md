# Slice 9i — Persona Symmetry (design)

**Date:** 2026-06-10 · **Arc:** Slice 9, Tier 2 (R9) · **Version target:** MINOR → **v2.33.0**
**Input:** review SDLC-personas finding (scored **6/10**): *"Eng + PO/BA complete; QA and Designer named with '→ exit artifact' promises that dissolve — QA ('own acceptance') has no test-plan template and no sign-off home; Designer ('own a11y sign-off') is absent from the authoritative DoD. Sign-offs are prose, not auditable artifacts."* The §2 persona table already has an "Entry → exit artifact" column; the QA/Designer exit artifacts just don't exist yet.

## Scope (ratified at brainstorm)
Three per-gate templates (TEST-PLAN + UAT-SIGNOFF + A11Y-SIGNOFF), an honest persona-table annotation (dedicated-artifact vs works-through-another), a DoD tie-in naming the new sign-offs as evidence, and a completeness drift-guard. Docs/templates + one completeness check. No loop-machinery change.

## Components

### 1. `templates/TEST-PLAN-TEMPLATE.md` (new — QA's dedicated artifact)
The missing "test strategy/cases in." Guidance-blockquote `_TEMPLATE` style. Sections: scope & risk areas · test levels (unit / integration / e2e) and coverage per level · **cases mapped to the feature's acceptance criteria** (traceability tying QA to the PO `FEATURE-REQUEST`) · environments (Dev/QA per §9) · entry/exit criteria · out-of-scope · links (spec, PR).

### 2. `templates/UAT-SIGNOFF-TEMPLATE.md` (new — auditable QA/PO acceptance)
A small structured record, not prose: **gate: UAT · signer · role · date · acceptance-criteria verdict (met / not met) · test-plan reference · evidence link · decision (accept / reject) · notes**. Ties to the §9 Dev→QA→**UAT** promotion gate (UAT exit = "acceptance sign-off (PO/QA)").

### 3. `templates/A11Y-SIGNOFF-TEMPLATE.md` (new — auditable Designer a11y sign-off)
**gate: a11y · signer · date · WCAG 2.1 AA checklist** (keyboard-navigable · screen-reader · contrast ≥ 4.5:1 · visible focus · `prefers-reduced-motion`) · **tool evidence** (axe / Lighthouse run link + score) · decision (pass / fail) · notes. This is the auditable record the DoD accessibility item currently lacks.

Both sign-offs share a signer/date/gate/evidence/decision skeleton but carry **different evidence** (acceptance-criteria traceability vs the WCAG checklist + axe/Lighthouse), which is why they are separate templates, not one generic.

### 4. Persona-table annotation (`DEVELOPMENT-PROCESS.md` §2)
Update the "Entry → exit artifact" column to reference the real templates and add a **dedicated vs shared** distinction:
- **PO/BA** — `FEATURE-REQUEST` (dedicated) → accepted increment.
- **Designer** — design assets → **`A11Y-SIGNOFF`** (dedicated; promoted from prose/advisory).
- **QA** — **`TEST-PLAN`** (dedicated) → **`UAT-SIGNOFF`** (dedicated).
- **DevOps/SRE** — **works through** the `RUNBOOK` + promotion run (shared — no persona-specific template), annotated honestly.
A one-line legend defines "dedicated artifact" (a template this persona owns) vs "works through another's." Closes the over-promised-symmetry finding by being explicit about which is which.

### 5. Evidence tie-ins (where each sign-off is named)
Two minimal edits naming the artifacts as the auditable evidence for obligations that **already exist** — no new requirements, no new gates:
- **`CLAUDE.md` DoD → Accessibility line** (authoritative principles file; careful governing-surface edit, ratified by human merge): the existing "keyboard-navigable · screen-reader/contrast checks pass" item names **`A11Y-SIGNOFF`** as its auditable evidence. Closes "Designer absent from the authoritative DoD."
- **`DEVELOPMENT-PROCESS.md` §9 UAT gate** (NOT the DoD's Production line — UAT acceptance lives in §9's Dev→QA→UAT→Prod promotion model): the existing "UAT green + acceptance sign-off (PO/QA)" names **`UAT-SIGNOFF`** as that record.
Both name an artifact for a bar that was always there; neither rewrites the DoD or adds a requirement.

### 6. `conformance/persona-artifacts.sh` (new — completeness drift-guard)
Like `stack-selection.sh`: asserts (a) `templates/TEST-PLAN-TEMPLATE.md`, `templates/UAT-SIGNOFF-TEMPLATE.md`, `templates/A11Y-SIGNOFF-TEMPLATE.md` all exist; (b) the §2 persona table in `DEVELOPMENT-PROCESS.md` names each of `TEST-PLAN`, `UAT-SIGNOFF`, `A11Y-SIGNOFF`. `--selftest` with a two-tree fixture (no `rm`). Completeness, not content-equality. Wired into kit CI (**one control-plane `cp`**).

## Files

| File | Change | Owner |
|------|--------|-------|
| `templates/TEST-PLAN-TEMPLATE.md` | **New** | agent |
| `templates/UAT-SIGNOFF-TEMPLATE.md` | **New** | agent |
| `templates/A11Y-SIGNOFF-TEMPLATE.md` | **New** | agent |
| `DEVELOPMENT-PROCESS.md` | §2 persona-table annotation (dedicated vs shared + real template refs); §9 UAT gate → UAT-SIGNOFF; §5 Designer lens → A11Y-SIGNOFF | agent |
| `CLAUDE.md` | DoD Accessibility line → A11Y-SIGNOFF evidence (only) | agent |
| `conformance/persona-artifacts.sh` | **New** — completeness + `--selftest` | agent |
| `conformance/README.md` | index row | agent |
| `START-HERE.md` | QA/Designer role rows link their templates | agent |
| `.github/workflows/ci.yml` | `persona-artifacts.sh` step | **human `cp`** |
| `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-SLICE9.md` | 2.33.0; 9i row → shipped | agent |

## Verification
- `sh conformance/persona-artifacts.sh` → PASS (3 templates present + named in §2); `--selftest` detects a synthesized gap.
- `dash -n conformance/persona-artifacts.sh` clean.
- `sh conformance/check-links.sh` green (new template links + §2/§9/§5/START-HERE refs resolve).
- `sh conformance/verify.sh` OK; existing checks unaffected.
- The DoD edit is minimal and names the artifacts without weakening any existing requirement (diff-reviewed).
- Anonymization: generic ([[kit-anonymization]]).
- Governance: feature branch → PR → human ratification; **`CLAUDE.md` is a governing surface** → the DoD wording gets the security-owner lens in review; the `.github/workflows` step via human `cp`.

## Out of scope / deferred
- A `sign-off-valid.sh` field-validator (sign-offs are per-feature/ephemeral; the completeness guard + the structured templates deliver "auditable" without per-record machinery — revisit only if an adopter wants enforced sign-off records).
- New §2 *functions* for QA/Designer (they remain lenses on Reviewer/Intent-owner; 9i gives them artifacts, not new authoritative functions).
- DevOps/SRE and Security getting dedicated templates (they work through RUNBOOK/conformance; annotated as shared, not expanded here).

## Known implications
- The persona table now makes an honest *asymmetry* explicit (PO/QA/Designer have dedicated artifacts; DevOps/SRE works through shared ones) rather than implying every persona has a first-class exit artifact. That honesty is the point of R9.
- A future persona artifact must be added to the §2 table + (if a template) pass the completeness guard.
