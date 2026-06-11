# RAI-3 — AI-Governance Crosswalk + Agentic-Threat Lens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the Responsible-AI arc with the US-first **AI-governance crosswalk** (maps kit controls + the RAI artifacts to NIST AI RMF / ISO 42001 / US state law / COPPA / OWASP-MITRE; EU AI Act optional) and an **agentic-threat (ASI01–10) lens** on the threat-model template.

**Architecture:** Documentation only. `docs/enterprise/ai-governance-crosswalk.md` is a sibling of `compliance-crosswalk.md` (same honest `Responsibility` column: Kit-enforced / Kit-assisted / Org-owned). The agentic lens is a subsection appended to `templates/THREAT-MODEL-TEMPLATE.md`. **No new conformance script → no CI step.**

**Tech Stack:** Markdown only. Verification via `check-links.sh`, `doc-budget.sh`, `verify.sh` (unchanged at 6 doc-checks).

**Release:** `VERSION` → 2.50.0; MINOR (additive docs; no gate/script).

**Honesty invariant:** the crosswalk shows its own edges — the agentic-threat coverage is reported truthfully (**5 of 10 fully covered, 3 partial, 2 genuine gaps** the platform owns), and ISO 42001 *certification* + state-law *legal determination* are **Org-owned**, not kit-provided. US-first: EU AI Act is a clearly-fenced optional overlay; no EU-only obligation in any baseline.

**Doc-budget:** only core-doc edit is a +0/+1 STANDARDS pointer (310→≤311). PROCESS/CLAUDE untouched. The crosswalk + lens are non-core docs. Run `doc-budget.sh` after the STANDARDS edit.

**Governance:** branch `feature/responsible-ai-rai3-crosswalk` (created) → PR → **Bradley merges**. The crosswalk + STANDARDS edit are governing/compliance-facing → **security-owner lens**. Generic/anonymized ([[kit-anonymization]]) — children's-data references stay as a regulated-archetype illustration.

---

## File Structure

- Create: `docs/enterprise/ai-governance-crosswalk.md` (Task 1).
- Modify: `templates/THREAT-MODEL-TEMPLATE.md` — agentic-AI lens subsection (Task 2).
- Modify: `docs/enterprise/README.md` (index row), `DEVELOPMENT-STANDARDS.md` (pointer), `conformance/README.md` + `conformance/audit-evidence-checklist.md` (reference) (Task 3).
- Modify: `VERSION`, `CHANGELOG.md`, `README.md` badge (Task 4).

---

## Task 1: AI-governance crosswalk

**Files:**
- Create: `docs/enterprise/ai-governance-crosswalk.md`

- [ ] **Step 1: Write the crosswalk** (mirror `compliance-crosswalk.md` tone + the honest `Responsibility` column)

```markdown
# AI-Governance Crosswalk — US-first (NIST AI RMF · ISO 42001 · US state law · OWASP/MITRE)

Maps the **AI-governance controls this kit provides** to the frameworks a **US** AI-deploying enterprise actually answers to. Use it to show an auditor *where the AI-governance evidence lives* in a repo built with this kit. Companion to `compliance-crosswalk.md` (SOC 2 / ISO 27001).

**How to read it:** the `Responsibility` column is the honest part — **Kit-enforced** (mechanical evidence), **Kit-assisted** (kit gives the artifact/pattern; team produces evidence), **Org-owned** (the organization owns it — see [README boundary](README.md)). Rows that don't apply are marked **N/A (reason)**.

**Jurisdiction:** **US-first.** The practical US anchor is **NIST AI RMF + the Generative AI Profile (NIST-AI-600-1)** — and Texas TRAIGA grants a **safe harbor** for substantial compliance with it. **ISO/IEC 42001** (international, voluntary) pairs with SOC 2. The **EU AI Act** is a fenced **optional overlay** (last section) — only with EU market exposure; its conformity-assessment / CE / FRIA / EU-database machinery is **Org-owned and out of the US baseline**.

## AI-governance controls

| Kit control / artifact | Where in the kit | NIST AI RMF | ISO/IEC 42001 | US driver (state / federal) | Responsibility |
|---|---|---|---|---|---|
| AI System Card — risk classification + human oversight | `templates/AI-SYSTEM-CARD-TEMPLATE.md`; `conformance/responsible-ai-ready.sh` (§7 gate) | GOVERN, MAP | Clause 6 (risk + impact assessment); Annex A (impact assessment, human oversight) | CO SB 26-189 / CA ADMT (consequential-decision disclosure); NIST RMF (TX TRAIGA safe harbor) | Kit-assisted |
| AI Policy | `templates/AI-POLICY-TEMPLATE.md` | GOVERN | Clause 5.2 (AI policy) | — | Kit-assisted |
| Eval gate — quality + regression + safety/red-team | `profiles/ml.md`; `conformance/eval-ready.sh`; §7 eval gate | MEASURE, MANAGE | Annex A (AI system lifecycle, performance) | NIST RMF MEASURE | Kit-enforced (the gate) · Kit-assisted (the evals) |
| Fairness / bias eval dimension | `templates/EVAL-PLAN-TEMPLATE.md` (Fairness section) | MEASURE | Annex A (impact: fairness) | EEOC · NYC Local Law 144 · CO/CA consequential-decision | Kit-assisted (Manual) |
| AI-output transparency sign-off | `templates/AI-TRANSPARENCY-SIGNOFF-TEMPLATE.md` | GOVERN, MAP | Annex A (transparency to stakeholders) | CA SB 942 / AB 2013 · FTC deception · COPPA | Kit-assisted (Manual) |
| Human oversight — agents propose, humans ratify | `DEVELOPMENT-PROCESS.md` §13; `docs/enterprise/ratification-rbac.md` | GOVERN, MANAGE | Annex A (human oversight) | CO/CA consequential-decision | Kit-enforced (ratification) |
| Prohibited-use acknowledgment | `templates/AI-SYSTEM-CARD-TEMPLATE.md` | MAP | Annex A (impact) | TX TRAIGA · FTC UDAP | Kit-assisted (Manual) |
| Data minimization + children's-data care | AI System Card; `DEVELOPMENT-STANDARDS.md` §2 (PII) | MAP, MANAGE | Annex A (data governance) | COPPA · CA | Kit-assisted · privacy program Org-owned |
| AI incident response + feedback to evals | `templates/POSTMORTEM-TEMPLATE.md`; `DEVELOPMENT-STANDARDS.md` (incident) | MANAGE | Clause 10 (improvement); Annex A | CA SB 53 incident-report principle · FTC | Kit-assisted |
| Prompt-injection defense / output validation | `DEVELOPMENT-STANDARDS.md` §2 (AI/agent security) | MANAGE | Annex A (lifecycle security) | — | Kit-assisted |
| Agent guard · MCP policy · containment · egress | `.claude/hooks/guard-core.sh`; `conformance/mcp-policy.sh` / `containment-ready.sh` / `egress-policy.sh` | MANAGE | Annex A (third-party governance, lifecycle) | — | Kit-enforced / Kit-assisted |
| Model + data versioning · reproducibility | `profiles/ml.md` (MLflow, DVC) | MEASURE, MANAGE | Annex A (lifecycle) | — | Kit-assisted |
| ISO 42001 certification (the AIMS itself) | — | — | Clauses 4–10 (the management system) | — | Org-owned |
| Which AI laws apply (legal determination) | — | — | — | state-law applicability is a legal call | Org-owned |

## Agentic-threat coverage — OWASP Top 10 for Agentic Applications (2025) + MITRE ATLAS

Honest coverage of the agentic-AI threat surface: **5 fully covered, 3 partial, 2 platform-owned gaps.** (Threat frameworks are jurisdiction-neutral.)

| OWASP Agentic risk | Kit control | Status |
|---|---|---|
| ASI01 Agent goal hijack | prompt-injection defense (`DEVELOPMENT-STANDARDS.md` §2) | Partial |
| ASI02 Tool misuse | MCP capability policy + guard deny-matrix | **Covered** |
| ASI03 Identity & privilege abuse | scoped short-lived tokens + containment | **Covered** |
| ASI04 Agentic supply chain | SBOM + provenance gates; MCP allowlist | **Covered** |
| ASI05 Unexpected code execution | guard deny-matrix + sandboxed FS | **Covered** |
| ASI06 Memory / context poisoning | TCC declares per-step context (not a runtime control) | Gap — platform-owned |
| ASI07 Insecure inter-agent comms | — | Gap — multi-agent, platform-owned |
| ASI08 Cascading failures | resilience / circuit-breakers (`resilience-ready.sh`) | Partial |
| ASI09 Human-agent trust exploitation | agents-propose-humans-ratify + ratification RBAC | Partial |
| ASI10 Rogue agents | autonomy tiers (`agent-autonomy.sh`) + immutable audit | **Covered** |

> **MITRE ATLAS** (v5.4.0): the kit's controls map to ATLAS techniques — e.g. *Publish Poisoned AI Agent Tool* → MCP allowlist + SBOM; *Escape to Host* → sandboxed FS + containment. ATLAS is the technique catalog; OWASP Agentic is the risk-prioritization lens.

> The 2 gaps (ASI06 memory poisoning, ASI07 inter-agent comms) and the runtime depth of the partials are **platform-owned** — the kit declares + governs; the runtime enforces. This is the same honest boundary as `platform-safety-boundary.md`.

## EU AI Act — optional overlay (only with EU market exposure)

Turn this on **only** if you place AI on the EU market. The EU's *substantive* requirements are good practice the kit already embodies; its *bureaucracy* (conformity assessment, CE marking, fundamental-rights impact assessment, EU-database registration) is **Org-owned and excluded from the US baseline**.

| EU AI Act article | Good-practice substance | Kit artifact (already covers the substance) |
|---|---|---|
| Art. 9 (risk management) | iterative AI risk management | AI System Card + threat-model |
| Art. 10 (data governance) | data quality + bias examination | Fairness eval + data-minimization |
| Art. 12 (logging) | lifecycle traceability | immutable audit logging |
| Art. 13/14 (transparency / human oversight) | instructions + meaningful oversight | AI System Card + AI Transparency sign-off + ratification |
| Art. 15 (accuracy / robustness / security) | tested, robust, adversarial-resistant | eval gate + agentic-threat lens |
| Art. 50 (transparency to users) | disclose AI + label synthetic content | AI Transparency sign-off |
| Art. 72 (post-market monitoring) | monitor in production | observability + ML drift |
| Conformity assessment / CE / FRIA / EU-DB | EU-only certification machinery | **Org-owned — not in the US baseline** |
```

- [ ] **Step 2: Links resolve**

Run: `sh conformance/check-links.sh`
Expected: OK (all relative links — `README.md`, the template/conformance paths — resolve).

- [ ] **Step 3: Commit**

```bash
git add docs/enterprise/ai-governance-crosswalk.md
git commit -m "docs(enterprise): US-first AI-governance crosswalk (NIST AI RMF / ISO 42001 / US state law / OWASP+MITRE; EU optional) (RAI-3)"
```

---

## Task 2: Agentic-AI lens on the threat-model template

**Files:**
- Modify: `templates/THREAT-MODEL-TEMPLATE.md` (after the Privacy (LINDDUN-lite) section)

- [ ] **Step 1: Add the agentic lens** after the `## Privacy (LINDDUN-lite)` section:

```markdown
## Agentic-AI lens (if an autonomous / tool-using agent) — OWASP Agentic Top 10
*Mark **N/A — not an agent** if the AI feature does not plan/act with tools. Full coverage map: `docs/enterprise/ai-governance-crosswalk.md`.*

| Agentic risk | Considered? | Mitigation (link the control) |
|---|---|---|
| ASI01 Goal hijack (injection redirects the agent) | | prompt-injection defense; treat tool output as untrusted |
| ASI02 Tool misuse | | MCP capability policy + guard |
| ASI03 Identity / privilege abuse | | scoped short-lived tokens + containment |
| ASI05 Unexpected code execution | | guard deny-matrix + sandboxed FS |
| ASI06 Memory / context poisoning | | [platform — validate persisted context] |
| ASI09 Human-agent trust exploitation | | ratify on evidence, not a polished agent rationale |
| ASI10 Rogue agent / misalignment | | autonomy tiers + immutable audit |
```

- [ ] **Step 2: Links + commit**

Run: `sh conformance/check-links.sh` → OK.
```bash
git add templates/THREAT-MODEL-TEMPLATE.md
git commit -m "feat(templates): agentic-AI (OWASP Agentic Top 10) lens on the threat-model (RAI-3)"
```

---

## Task 3: Wiring (enterprise index · STANDARDS · conformance reference)

**Files:**
- Modify: `docs/enterprise/README.md`, `DEVELOPMENT-STANDARDS.md`, `conformance/README.md`, `conformance/audit-evidence-checklist.md`

- [ ] **Step 1: enterprise README index row**

After the `compliance-crosswalk.md` row in the Contents table, add:
```
| [ai-governance-crosswalk.md](ai-governance-crosswalk.md) | US-first AI-governance map — NIST AI RMF / ISO 42001 / US state law / OWASP+MITRE; EU AI Act optional overlay. |
```

- [ ] **Step 2: DEVELOPMENT-STANDARDS.md pointer (+0 append)**

Append to the AI transparency/incidents bullet (added in RAI-2):
```
- **AI transparency + incidents** *(AI features)* — disclose AI interaction + label synthetic content (`templates/AI-TRANSPARENCY-SIGNOFF-TEMPLATE.md`); AI incidents (harmful output, jailbreak, bias) feed back to the eval red-team set. AI-governance framework map: `docs/enterprise/ai-governance-crosswalk.md`.
```

- [ ] **Step 3: conformance/audit-evidence-checklist.md reference**

Append to the AI-governance row's evidence cell (added in RAI-1) a crosswalk pointer, OR add a one-line note under the table that the AI-governance framework mapping lives in `docs/enterprise/ai-governance-crosswalk.md`. Keep it a pointer, not a new row.

- [ ] **Step 4: Verify**

```bash
sh conformance/check-links.sh && echo "links OK"
sh conformance/doc-budget.sh && echo "doc-budget OK"   # STANDARDS ≤ 311 (the pointer is a +0 append)
sh conformance/verify.sh 2>&1 | grep -E 'Summary|RESULT'  # still 6 doc-checks
```
Expected: links OK; doc-budget OK; `verify.sh` RESULT: OK (6 doc-checks).

- [ ] **Step 5: Commit**

```bash
git add docs/enterprise/README.md DEVELOPMENT-STANDARDS.md conformance/README.md conformance/audit-evidence-checklist.md
git commit -m "docs: wire AI-governance crosswalk — enterprise index + STANDARDS + audit pointers (RAI-3)"
```

---

## Task 4: Release v2.50.0 + verification + PR

**Files:**
- Modify: `VERSION` → `2.50.0`; `CHANGELOG.md`; `README.md` badge.

- [ ] **Step 1: Bump VERSION** to `2.50.0`.

- [ ] **Step 2: CHANGELOG entry** under `## [2.50.0] - <date>` (match the 2.49.0 shape). Cover: AI-governance crosswalk (US-first), agentic-threat lens; **closes the Responsible-AI arc**; honest coverage (5/3/2); doc-only, no gate/script. Note RAI-3 + arc closure.

- [ ] **Step 3: README badge** → `v2.50.0`; `sh conformance/badge-version.sh` → OK.

- [ ] **Step 4: Full verification**

```bash
sh conformance/check-links.sh && echo "links OK"
sh conformance/doc-budget.sh && echo "doc-budget OK"
sh conformance/badge-version.sh && echo "badge OK"
sh conformance/verify.sh 2>&1 | tail -4    # 6 doc-checks unchanged
```
Expected: all green; `verify.sh` RESULT: OK (6 doc-checks).

- [ ] **Step 5: Commit the release**

```bash
git add VERSION CHANGELOG.md README.md
git commit -m "chore(release): 2.50.0 — RAI-3 AI-governance crosswalk + agentic-threat lens (Responsible-AI arc CLOSED)"
```

- [ ] **Step 6: Independent review (builder ≠ sole reviewer) — security-owner lens**

Dispatch an independent review over the branch diff: honesty (the crosswalk shows its edges — 5/3/2 agentic coverage, Org-owned rows present, no overclaim of compliance/certification); US-first (NIST/state/COPPA lead; EU fenced as optional; no EU-only baseline); accuracy (each kit-control→framework mapping is defensible; NIST AI RMF functions + ISO 42001 clauses cited correctly; OWASP ASI numbering correct); links + doc-budget; no new gate/script. Fold Critical/High/Medium.

- [ ] **Step 7: Push + open PR (Bradley merges)**

```bash
git push -u origin feature/responsible-ai-rai3-crosswalk
gh pr create --base main --head feature/responsible-ai-rai3-crosswalk \
  --title "RAI-3 — AI-governance crosswalk + agentic-threat lens (v2.50.0) — closes the Responsible-AI arc" --body "<summary + verification>"
```
Report the PR number + merge command. **No control-plane step this slice.** Do not self-merge.

---

## Verification (whole slice)

- `check-links`, `doc-budget` (STANDARDS ≤ 311), `badge-version` green; `verify.sh` RESULT: OK at 6 doc-checks (no new script).
- Honesty: agentic coverage reported truthfully (5 covered / 3 partial / 2 gaps); ISO 42001 cert + legal determination Org-owned; no compliance overclaim.
- US-first: NIST/state/COPPA lead; EU AI Act fenced as optional overlay; no EU-only baseline obligation.
- Internal consistency: crosswalk control→artifact references resolve to real files; threat-model lens points at the crosswalk; STANDARDS pointer resolves.

## Out of scope (this slice / after the arc)
- Ephemeral / preview environments; cross-stack test-data management (the two deferred items).
- ISO 42001 certification, AI runtime security products, state-law legal determinations — Org-owned.
