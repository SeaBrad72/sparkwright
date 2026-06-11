# RAI-2 — Fairness Eval + AI-Output Transparency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the two genuine content gaps to the Responsible-AI arc — a **fairness/bias eval dimension** and an **AI-output transparency sign-off** — plus the good-citizen **AI-incident feedback** extension. Template-only; no new conformance script.

**Architecture:** All additive templates + light wiring. The fairness dimension extends the existing `EVAL-PLAN-TEMPLATE.md` (which already has Safety/red-team) and rides the existing eval wiring. `AI-TRANSPARENCY-SIGNOFF-TEMPLATE.md` mirrors `A11Y-SIGNOFF-TEMPLATE.md` and is referenced from the AI System Card + the existing `responsible-ai-readiness.md` transparency row (no new §7 gate row — folds into the AI System Card gate, avoiding gate proliferation). The AI-incident extension is a one-line addition to `POSTMORTEM-TEMPLATE.md`.

**Tech Stack:** Markdown only. Verification via `check-links.sh`, `doc-budget.sh`, `verify.sh` (unchanged at 6 doc-checks — no new script).

**Release:** `VERSION` → 2.49.0; MINOR (additive templates; no new gate/script).

**No control-plane edit this slice:** RAI-2 adds no new conformance script → no CI selftest step → nothing to apply to `.github/workflows/ci.yml`. (Per the fold-in convention, CI edits only arise when a slice adds a new check; this slice doesn't.)

**Honesty invariant:** the fairness + transparency items are **Manual** (owner-verified) — the kit records that the dimension is *declared/considered*, never that the AI is *actually fair* or the disclosure *actually shipped*. US-anchored (EEOC · NYC LL144 · CO/CA · CA SB 942/AB 2013 · COPPA/FTC); EU Art. 10/50 are optional overlays, not baseline.

**Doc-budget:** core-3 headroom — `CLAUDE.md` 111/120, `DEVELOPMENT-PROCESS.md` 466/470, `DEVELOPMENT-STANDARDS.md` 310/320. The only core-doc edits are +0 appends (CLAUDE templates list) + 1 STANDARDS bullet (→311). PROCESS untouched. Run `doc-budget.sh` after edits.

**Governance:** branch `feature/responsible-ai-rai2-fairness-transparency` (created) → PR → **Bradley merges**. STANDARDS edit → security-owner lens. Generic/anonymized ([[kit-anonymization]]).

---

## File Structure

- Modify: `templates/EVAL-PLAN-TEMPLATE.md` — add Fairness/bias section (Task 1).
- Modify: `conformance/eval-readiness.md` — add a Manual fairness row (Task 1).
- Create: `templates/AI-TRANSPARENCY-SIGNOFF-TEMPLATE.md` (Task 2).
- Modify: `templates/AI-SYSTEM-CARD-TEMPLATE.md` (transparency link), `conformance/responsible-ai-readiness.md` (row 6 pointer), `CLAUDE.md` (templates list), `DEVELOPMENT-STANDARDS.md` (AI-security pointer) — Task 2.
- Modify: `templates/POSTMORTEM-TEMPLATE.md` — AI-incident feedback line (Task 3).
- Modify: `VERSION`, `CHANGELOG.md`, `README.md` badge (Task 4).

---

## Task 1: Fairness / bias eval dimension

**Files:**
- Modify: `templates/EVAL-PLAN-TEMPLATE.md` (after the `## Safety / red-team (Manual)` section, currently ends line 24)
- Modify: `conformance/eval-readiness.md` (add a Manual fairness row)

- [ ] **Step 1: Add the Fairness section to EVAL-PLAN-TEMPLATE.md**

After the Safety/red-team block:
```
## Safety / red-team (Manual)
- [ ] Adversarial prompts / jailbreaks tested before shipping
- [ ] Harmful-output checks run
- [ ] Judge is independent of the system under test (no self-grading)
```
insert:
```
## Fairness / bias (Manual)
*US drivers: EEOC · NYC Local Law 144 · CO/CA consequential-decision · FTC. Mark **N/A — no human-subject dimension** when the feature does not affect people (e.g. a code helper).*
- [ ] Protected dimensions evaluated (e.g. by group: gender / race / age) — or **N/A with reason**
- [ ] Fairness metric + threshold recorded (e.g. disparate-impact / four-fifths ratio ≥ 0.8)
- [ ] Result reviewed by the owner before shipping (a fairness regression is tech debt)
```

- [ ] **Step 2: Add the Manual fairness row to eval-readiness.md**

After row 7 (judge-independent), add:
```
| 8 | Fairness / disparate-impact tested where the feature affects people (or N/A) *(verified)* | | | Manual |
```

- [ ] **Step 3: Links + commit**

Run: `sh conformance/check-links.sh` → OK.
```bash
git add templates/EVAL-PLAN-TEMPLATE.md conformance/eval-readiness.md
git commit -m "feat(templates): EVAL-PLAN fairness/bias dimension + eval-readiness Manual row (RAI-2)"
```

---

## Task 2: AI-output transparency sign-off

**Files:**
- Create: `templates/AI-TRANSPARENCY-SIGNOFF-TEMPLATE.md`
- Modify: `templates/AI-SYSTEM-CARD-TEMPLATE.md`, `conformance/responsible-ai-readiness.md`, `CLAUDE.md`, `DEVELOPMENT-STANDARDS.md`

- [ ] **Step 1: Write the transparency sign-off template** (mirrors `A11Y-SIGNOFF-TEMPLATE.md`)

```markdown
# AI Transparency Sign-off

> **Template.** Delete the guidance; fill the table. The auditable evidence that an AI feature's outputs are honestly disclosed to users — the transparency record for an AI feature (referenced from the AI System Card). US drivers: CA SB 942 / AB 2013 (AI transparency + provenance), state chatbot-disclosure laws, FTC deception, COPPA (children's audiences). EU AI Act Art. 50 is an optional overlay. The security/compliance or product owner signs at Review. Attach to the PR or store under `docs/sign-offs/`.

| Field | Value |
|-------|-------|
| Gate | AI output transparency |
| Feature / story | <link> |
| AI interaction disclosed to users (esp. chatbots) | pass / fail / N/A |
| AI-generated / synthetic content labeled | pass / fail / N/A |
| Provenance / content credentials (C2PA) where applicable | pass / fail / N/A |
| Children's-audience disclosure (age-appropriate) | pass / fail / N/A |
| Decision | **pass** / fail |
| Signer (role) | <name> |
| Date | YYYY-MM-DD |
| Notes | |
```

- [ ] **Step 2: Reference it from the AI System Card** (`templates/AI-SYSTEM-CARD-TEMPLATE.md`, Guardrails section)

Change:
```
- **Eval / quality bar:** [link the EVAL-PLAN + §7 eval gate]
```
to add a transparency line after it:
```
- **Eval / quality bar:** [link the EVAL-PLAN + §7 eval gate]
- **Transparency** *(user-facing AI)*: [AI interaction disclosed + synthetic content labeled — `templates/AI-TRANSPARENCY-SIGNOFF-TEMPLATE.md`]
```

- [ ] **Step 3: Point the readiness transparency row at the template** (`conformance/responsible-ai-readiness.md`, row 6)

Change row 6:
```
| 6 | User-facing AI disclosure + content labeling shipped where applicable *(verified)* | | | Manual |
```
to:
```
| 6 | User-facing AI disclosure + content labeling shipped where applicable (`templates/AI-TRANSPARENCY-SIGNOFF-TEMPLATE.md`) *(verified)* | | | Manual |
```

- [ ] **Step 4: CLAUDE.md templates list (+0 append)** — add `AI-TRANSPARENCY-SIGNOFF` to the comma list.

- [ ] **Step 5: DEVELOPMENT-STANDARDS.md AI-security pointer (+1 bullet)**

After the AI System Card bullet (added in RAI-1), add:
```
- **AI transparency + incidents** *(AI features)* — disclose AI interaction + label synthetic content (`templates/AI-TRANSPARENCY-SIGNOFF-TEMPLATE.md`); AI incidents (harmful output, jailbreak, bias) feed back to the eval red-team set.
```

- [ ] **Step 6: Links + budget + commit**

Run: `sh conformance/check-links.sh && sh conformance/doc-budget.sh` → both OK (STANDARDS → 311).
```bash
git add templates/AI-TRANSPARENCY-SIGNOFF-TEMPLATE.md templates/AI-SYSTEM-CARD-TEMPLATE.md conformance/responsible-ai-readiness.md CLAUDE.md DEVELOPMENT-STANDARDS.md
git commit -m "feat(templates): AI Transparency sign-off + wire into System Card/readiness/STANDARDS (RAI-2)"
```

---

## Task 3: AI-incident feedback (good-citizen)

**Files:**
- Modify: `templates/POSTMORTEM-TEMPLATE.md`

Extend the existing postmortem to name AI incidents with a feedback loop to evals (CA SB 53 incident-report principle · FTC). One-line addition; no new artifact.

- [ ] **Step 1: Add the AI-incident note to the Action items section** (`## 7. Action items`)

After the section-7 heading/guidance, add a line:
```
> **AI incident** (harmful output · jailbreak / prompt-injection · bias): add the failing case to the feature's EVAL-PLAN **red-team set** as an action item — closing the eval loop so it can't regress.
```

- [ ] **Step 2: Links + commit**

Run: `sh conformance/check-links.sh` → OK.
```bash
git add templates/POSTMORTEM-TEMPLATE.md
git commit -m "feat(templates): POSTMORTEM names AI incidents + feeds them back to the eval red-team set (RAI-2)"
```

---

## Task 4: Release v2.49.0 + verification + PR

**Files:**
- Modify: `VERSION` → `2.49.0`; `CHANGELOG.md`; `README.md` badge.

- [ ] **Step 1: Bump VERSION** to `2.49.0`.

- [ ] **Step 2: CHANGELOG entry** under `## [2.49.0] - <date>` (match the 2.48.0 shape). Cover: fairness/bias eval dimension, AI Transparency sign-off, AI-incident feedback; US-anchored; all Manual (declared, not proven); template-only, no new gate/script. Note RAI-2 of the Responsible-AI arc.

- [ ] **Step 3: README badge** → `v2.49.0`; `sh conformance/badge-version.sh` → OK.

- [ ] **Step 4: Full verification**

```bash
sh conformance/check-links.sh && echo "links OK"
sh conformance/doc-budget.sh && echo "doc-budget OK"
sh conformance/badge-version.sh && echo "badge OK"
sh conformance/verify.sh 2>&1 | tail -4    # still 6 doc-checks (no new script)
```
Expected: links OK; doc-budget OK (CLAUDE ≤120, PROCESS 466, STANDARDS 311); badge OK; `verify.sh` RESULT: OK (6 doc-checks unchanged).

- [ ] **Step 5: Commit the release**

```bash
git add VERSION CHANGELOG.md README.md
git commit -m "chore(release): 2.49.0 — RAI-2 fairness eval + AI-output transparency (Responsible-AI arc)"
```

- [ ] **Step 6: Independent review (builder ≠ sole reviewer) — security-owner lens**

Dispatch an independent review over the branch diff: honesty (fairness/transparency are Manual — no "proven fair/disclosed" overclaim); US-first (no EU-only baseline; EU Art. 10/50 marked optional); no-friction (all additive, N/A-able, no new gate/script); links + doc-budget; templates consistent (transparency sign-off referenced from card + readiness; fairness section consistent with eval-readiness row; postmortem feedback loop points at the real EVAL-PLAN red-team set). Fold Critical/High/Medium.

- [ ] **Step 7: Push + open PR (Bradley merges)**

```bash
git push -u origin feature/responsible-ai-rai2-fairness-transparency
gh pr create --base main --head feature/responsible-ai-rai2-fairness-transparency \
  --title "RAI-2 — fairness eval + AI-output transparency (v2.49.0)" --body "<summary + verification>"
```
Report the PR number + merge command. **No control-plane step this slice.** Do not self-merge.

---

## Verification (whole slice)

- `check-links`, `doc-budget` (core-3 within caps), `badge-version` green; `verify.sh` RESULT: OK at **6 doc-checks** (no new script).
- All additions Manual / N/A-able — no new gate, no new fail-closed check, zero added friction; non-AI and no-human-subject features mark fairness N/A.
- US-first: EU Art. 10/50 are optional overlays; no EU-only baseline.
- Templates internally consistent: transparency sign-off ↔ System Card link ↔ readiness row 6; fairness section ↔ eval-readiness row 8; postmortem ↔ EVAL-PLAN red-team set.

## Out of scope (this slice)
- AI-governance crosswalk + agentic-threat lens (RAI-3).
- Ephemeral environments + cross-stack test-data (after the arc).
