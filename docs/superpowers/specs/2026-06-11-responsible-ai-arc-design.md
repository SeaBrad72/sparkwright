# Responsible-AI / AI-Governance — arc design (RAI-1 · RAI-2 · RAI-3)

**Status:** design (brainstorm), pre-plan. Approved shape: a **three-slice arc**, full arc before the deferred items (ephemeral environments, cross-stack test-data).
**Jurisdiction:** **US-first.** The target adopter is a US enterprise. The arc anchors on US drivers (NIST AI RMF, state AI laws, COPPA/FTC) and treats the **EU AI Act as an optional overlay** for adopters with EU market exposure — never baseline. We deliberately do **not** impose EU-only machinery (conformity assessment, CE marking, fundamental-rights impact assessment, EU-database registration) on a US project.
**Origin:** coverage analysis of an archived v3 feature-spec set (early-2025 "Responsible ML" framing) against the kit, re-grounded to **mid-2026** US regulatory reality (sources at the end). The one substantive SDLC gap the analysis surfaced.

---

## Problem

The kit answers two of the three AI-governance questions and not the third:
- **Eval gate** (v2.46.0) — *"is the model good?"* (quality, regression, safety/red-team, drift).
- **Threat-model** (v2.47.0) — *"how can it be attacked?"* (STRIDE/LINDDUN-lite).
- **Missing:** *"is the AI feature fair, disclosed, human-overseen, risk-classified, and mappable to the AI-specific regimes that apply to a US company?"* — a distinct governance axis.

This modernizes the early-2025 "Responsible ML" paradigm for a **mid-2026 agentic kit**. Those feature docs framed it as bias/explainability/model-cards for models you *train*. But the kit governs **agents orchestrating frontier LLMs that take actions** — a different risk surface (OWASP **Agentic** Top 10, not just the LLM Top 10).

## The reframe (and why the kit is already ~60% there)

Mapping the **OWASP Top 10 for Agentic Applications (Dec 2025)** against shipped kit controls, roughly **7 of 10 are already mitigated at the runtime layer** (this map is jurisdiction-neutral — security, not law):

| OWASP Agentic risk | Kit control (already shipped) |
|---|---|
| ASI02 Tool Misuse | MCP capability policy (`mcp-policy.sh`) + guard deny-matrix |
| ASI03 Identity & Privilege Abuse | scoped tokens + containment (`containment-ready.sh`), least-privilege OIDC |
| ASI05 Unexpected Code Execution | guard deny-matrix + sandboxed FS |
| ASI04 Agentic Supply Chain | SBOM + provenance gates; MCP allowlist |
| ASI01 Agent Goal Hijack | prompt-injection defense (AI security, §2) — *partial* |
| ASI10 Rogue Agents | autonomy tiers (`agent-autonomy.sh`) + immutable audit |
| ASI09 Human-Agent Trust Exploitation | "agents propose, humans ratify" + ratification RBAC — *partial* |
| ASI06 Memory/Context Poisoning | *gap* (TCC declares context but isn't a control) |
| ASI07 Insecure Inter-Agent Comms | *gap* (multi-agent) |
| ASI08 Cascading Failures | resilience/circuit-breakers — *partial* |

**So this arc is not a heavy new burden — it is the governance/declaration skin that makes shipped controls *auditable*, plus the US AI-governance crosswalk, plus the two true content gaps (fairness eval, AI-output transparency).** The acceleration story: a regulated US enterprise converts a months-long NIST-AI-RMF / state-law / COPPA scramble into **filling one declaration the kit already ~60% backs with shipped controls.**

## Governing principles for this arc (Bradley's guidance, binding)

1. **Governance as accelerant, never friction.** The arc must let teams ship AI features *faster because the assurance is pre-wired*, not slower. No ceremony that doesn't earn its place.
2. **US-first, EU-optional.** Anchor on US drivers. Do **not** add obligations that exist only in the EU AI Act and have no US analog (conformity assessment, CE marking, FRIA, EU-DB registration). The EU AI Act ships as a clearly-marked **optional overlay** an adopter turns on only with EU market exposure.
3. **Conditional by construction.** Everything binds **only on an AI feature** (the existing `is_ai_feature` trigger from `eval-ready.sh`). Non-AI projects are **N/A → zero overhead**.
4. **Proportional to risk.** A low-risk AI feature is a **one-line declaration**; a consequential-decision or children's-data feature gets the fuller record. Weight matches blast radius (same philosophy as `dr-ready` escalate-only vs `resilience-ready` skip-pass).
5. **Greenfield + brownfield drop-in.** Docs/templates/conditional-checks only — **no code dependency, no runtime install**. Brownfield adopters get the crosswalk to map existing AI features.
6. **Honesty invariant (arc-wide).** A green check proves the governance is **declared / classified / recorded**, never that the AI is **actually fair, compliant, or safe**. Risk correctness, fairness results, disclosure-shipped, and regulatory conformity stay **human-ratified (security/compliance owner) Manual rows**. "Consequential" / "high-risk use" is **not honestly auto-detectable** — the artifact is human-declared; the check verifies presence + that the classification was made, not that it is *correct*.

## Good-citizen guardrails (opt-in best practices distilled from EU AI Act + US state law)

The substantive technical requirements of the EU AI Act (Arts. 10/12/14/15/50/72) are ~all good engineering practice the kit already embodies; the EU's *friction* is the certification bureaucracy on top. So we **lean into the good practice and skip the bureaucracy**. These are **recommended defaults, not gates** — guidance in the templates, N/A-able, **never enforced by the fail-closed `responsible-ai-ready` check** (which only verifies card-present + classification-made + oversight-named). The four genuinely-new additions are one-time declarations, not recurring work:

| Good-citizen line | US-first source | Where it lands |
|---|---|---|
| **Prohibited-use acknowledgment** (not designed for unlawful discrimination / self-harm encouragement / CSAM / deception) | TX TRAIGA · FTC UDAP | RAI-1 System Card (one-time checkbox) |
| **Data minimization + consent for AI inputs** (esp. children's data) | COPPA · CA · EU Art. 10 | RAI-1 System Card data-flows section |
| **Human review / appeal path** (when consequential-decision = yes) | CO SB 26-189 · CA ADMT · EU Art. 14 | RAI-1 System Card oversight section |
| **AI-incident naming + feedback to evals** (harmful output / jailbreak / bias incident → red-team/eval) | CA SB 53 incident-report principle · FTC | RAI-2 (extend the existing postmortem/incident process) |

Already-covered good practice (kept, not re-added): human oversight (Art. 14), user-facing AI disclosure + content labeling (Art. 50 / CA SB 942 / C2PA), fairness/disparate-impact test (EEOC / NYC LL144 / Art. 10), accuracy/robustness/adversarial testing (Art. 15 → eval gate + agentic-threat lens), lifecycle logging/traceability (Art. 12 → audit), post-deployment monitoring/drift (Art. 72 → observability + ML drift).

---

## Slice RAI-1 — AI System Card + risk classification · (vMINOR)

The core declarative artifact: a lightweight **AI System Card** (a US-anchored AI use declaration + risk classification; doubles as the ISO/IEC 42005 "AI system impact assessment" for adopters pursuing ISO 42001).

### Components
- **`templates/AI-SYSTEM-CARD-TEMPLATE.md`** (new) — guidance-blockquote style. Sections (proportional — low-risk fills only the header + classification):
  - **System summary** — what the AI feature does; the **model + version** (e.g. `claude-opus-4-8`); orchestrate-a-frontier-model vs train/fine-tune.
  - **US risk classification** (the primary scheme — three quick yes/no triggers, each pointing at its obligation):
    - **Consequential / automated decision?** (employment, credit, housing, education, healthcare, insurance, legal) → state transparency/disclosure + risk-assessment obligations (CO SB 26-189, CA ADMT).
    - **Children's data?** (under-13 / mixed-audience) → **COPPA** obligations (verifiable parental consent, retention, no monetization) + FTC scrutiny.
    - **Prohibited use?** (unlawful discrimination, self-harm encouragement, CSAM) → **hard stop** (TX TRAIGA; FTC deception/UDAP).
    - **Optional EU overlay** — EU AI Act tier (prohibited/high/limited/minimal) *only if the adopter has EU market exposure*; otherwise mark **N/A — no EU exposure**.
  - **Intended use / out-of-scope use** — and explicitly prohibited uses.
  - **Prohibited-use acknowledgment** *(good-citizen, one-time)* — a checkbox attestation that the feature is **not designed for** unlawful discrimination, self-harm encouragement, CSAM, or deception (TX TRAIGA / FTC UDAP). Not gated; recommended default.
  - **Data flows + consent** — what data reaches the model; PII / children's data; consent basis; what leaves the trust boundary (links to egress/containment). *Good-citizen line:* **data minimization** for AI inputs, esp. children's data (COPPA).
  - **Human oversight** — the override/halt mechanism; links to "agents propose, humans ratify" + ratification RBAC. *Good-citizen line (when consequential-decision = yes):* a documented **human review / appeal path** (CO SB 26-189 / CA ADMT). (Good practice + supports the consequential-decision laws; not framed as an EU mandate.)
  - **Guardrails** — links the *existing* controls (prompt-injection defense, MCP policy, egress, containment, eval gate) rather than restating them.
  - **Known limitations + failure modes.**
  - **Sign-off** — security/compliance owner (auditable; mirrors A11Y-SIGNOFF / THREAT-MODEL).
- **`conformance/responsible-ai-readiness.md`** (new) — **Auto** (card present · classification made · human-oversight named) vs **Manual** (classification is *correct* · fairness actually tested · disclosure actually shipped · COPPA/state/NIST conformity).
- **`conformance/responsible-ai-ready.sh`** (new) — conditional, fail-closed (mirrors `eval-ready.sh`'s `is_ai_feature` trigger + N/A · OK · FAIL + `--selftest`).
  - **Binds when AI feature** (reuse `is_ai_feature`). Else **N/A**.
  - **When bound, asserts (declared, not judged):** an `AI-SYSTEM-CARD.md` exists; the **US risk classification** block is filled (not the `[classification]` placeholder); a **human-oversight** mechanism is named (not placeholder). FAIL on a bound project missing any.
  - Proportionality: a low-risk card (classification = none-triggered) with the header + classification + oversight line **passes** — the check never demands the full record for low-risk AI.
  - `--selftest` fixtures: non-AI → N/A; AI + complete card → OK; AI + no card → FAIL; AI + `[classification]` placeholder → FAIL; AI + missing oversight → FAIL.
- **`templates/AI-POLICY-TEMPLATE.md`** (new, small) — one-page org-level AI policy (maps to ISO 42001 Clause 5.2 for adopters who want it; useful regardless). Optional, pointed-to from the System Card.

### Wiring
- `conformance/verify.sh` — `check doc responsible-ai-ready` row.
- `.github/workflows/ci.yml` (control-plane `cp`) — `responsible-ai-ready.sh --selftest` step.
- `CLAUDE.md` — DoR conditional flag gains an **AI-feature** obligation pointer (`AI-SYSTEM-CARD`); templates list adds `AI-SYSTEM-CARD`, `AI-POLICY`.
- `DEVELOPMENT-PROCESS.md` §7 — an **AI System Card** gate row (conditional on AI feature), mirroring the threat-model row.
- `DEVELOPMENT-STANDARDS.md` AI/agent-security + AI-Evaluations sections — one-line pointers.
- `conformance/README.md` + `audit-evidence-checklist.md` rows.

---

## Slice RAI-2 — Fairness eval + AI-output transparency · (vMINOR)

The two genuine *content* gaps — both with solid US drivers.

### A. Fairness / bias eval dimension
US drivers: **EEOC** (employment AI), **NYC Local Law 144** (hiring bias audit), **Colorado/California** consequential-decision rules, **FTC** UDAP. (Not an EU-only concept.)
- **`templates/EVAL-PLAN-TEMPLATE.md`** — add a **Fairness / bias** section (the eval template already has Safety/red-team): protected dimensions evaluated, the fairness metric + threshold (e.g. disparate-impact / four-fifths ratio), and an N/A-with-reason path when the feature has no human-subject dimension. Manual-verified (results judged by the owner; the check only confirms the *dimension is declared*).
- **`conformance/eval-readiness.md`** — add a Manual fairness row.
- No new script — extends the existing eval artifact + readiness.

### B. AI-output transparency
US drivers: **California SB 942 / AB 2013** (AI transparency + provenance), state **chatbot-disclosure** laws, **FTC** deception, **COPPA** for kids. EU Art. 50 is the *optional overlay*.
- **`templates/AI-TRANSPARENCY-SIGNOFF-TEMPLATE.md`** (new, mirrors A11Y-SIGNOFF) — discloses: is AI interaction disclosed to users (esp. chatbots)? is AI-generated/synthetic content labeled (provenance / **C2PA content credentials** where applicable)? deepfake/synthetic-media labeling? **Especially material for children's-audience content.** Security/compliance-owner sign-off. Template-only (disclosure-shipped is a human-verified fact).
- Wired into the §7 gate set (conditional on AI feature with a user-facing output surface) + the System Card's transparency link.

### C. AI-incident feedback *(good-citizen, light)*
US driver: CA SB 53 incident-report principle · FTC. Extend the existing incident/postmortem process (`templates/POSTMORTEM-TEMPLATE.md` + STANDARDS incident response) to **name AI-specific incidents** — harmful output, jailbreak/prompt-injection success, bias incident, model regression — with a **feedback loop to the eval/red-team set** (the prod-miss → eval-case loop the eval gate already encourages). A one-line addition to the postmortem template's category list + a STANDARDS pointer; no new artifact, no gate.

### Wiring
- §7 gate row (AI transparency, conditional); `DEVELOPMENT-STANDARDS.md` AI-security pointer; templates list; README/audit rows. `verify.sh`/CI unaffected by the template-only transparency piece; the fairness piece rides the existing eval wiring. The AI-incident piece is a POSTMORTEM-template + STANDARDS edit.

---

## Slice RAI-3 — AI-governance crosswalk + agentic-threat lens · (vMINOR)

The map that ties it together and proves the ~7/10 already-covered story to an auditor — **US-ordered**.

### A. AI-governance compliance crosswalk
- **`docs/enterprise/ai-governance-crosswalk.md`** (new, sibling of the existing SOC 2 / ISO 27001 crosswalk) — rows mapping kit controls + the new RAI artifacts to, **in US-priority order**:
  - **NIST AI RMF 1.0** + **GenAI Profile (NIST-AI-600-1)** + **Cyber AI Profile (IR 8596)** — the practical US anchor (and the TX TRAIGA safe harbor).
  - **US state AI laws** — Texas TRAIGA (prohibited-use + NIST safe harbor), Colorado SB 26-189 (consequential-decision disclosure, 2027), California ADMT / SB 942 / AB 2013 (transparency + provenance). A "does this apply to us?" trigger column (most are deployer-vs-developer and consequential-decision scoped).
  - **COPPA** (amended Rule) + **FTC** AI enforcement (UDAP, the Snap referral) — the children's-data + deception surface.
  - **ISO/IEC 42001** (AIMS) + **ISO/IEC 42005** (impact assessment → AI System Card) + **42006** (cert bodies) — international/voluntary; pairs with SOC 2, which US adopters already run.
  - **OWASP LLM Top 10 (2025)** + **OWASP Agentic Top 10 (ASI01–10)** + **MITRE ATLAS** — the (jurisdiction-neutral) threat side; show the 7/10 coverage + name the 3 gaps honestly.
  - **EU AI Act** — a clearly-fenced **optional overlay** section (Art. 14 oversight, Art. 50 transparency, risk tiers, the Dec 2026 CSAM prohibition), marked "applies only with EU market exposure."
- Honest "kit-provided evidence vs Org-owned" column (e.g. ISO 42001 *certification* and state-law *legal determination* are Org-owned; the kit provides the artifacts/evidence).

### B. Agentic-threat lens on the threat-model
- **`templates/THREAT-MODEL-TEMPLATE.md`** — add an **Agentic-AI lens** subsection (the ASI01–10 categories) so an AI feature's threat model explicitly considers goal-hijack, tool-misuse, identity abuse, memory poisoning, inter-agent comms, human-trust exploitation, rogue-agent behavior — pointing at the kit controls that mitigate each. A checklist lens, not a new artifact.

### Wiring
- `conformance/README.md` + `audit-evidence-checklist.md` reference the new crosswalk; `docs/enterprise/` index; `DEVELOPMENT-STANDARDS.md` AI-security pointer. No new script (crosswalk + template-lens are documentation).

---

## Cross-arc honesty & friction checks (every slice)

- **No green check overclaims** — declared/classified/recorded only; correctness + conformity are Manual security/compliance-owner rows.
- **Conditional + proportional** — N/A for non-AI projects; low-risk = one-line; verify the live check is **N/A at the kit root** (the kit is a framework, not an AI feature) and the selftest covers the proportional-pass case.
- **US-first, no EU-only burden** — EU AI Act is a fenced optional overlay; nothing EU-exclusive (conformity assessment / CE / FRIA / EU-DB) is in any baseline path or check.
- **No new runtime dependency** — docs/templates/POSIX-sh checks only; greenfield + brownfield drop-in.
- **Doc-budget** — core-3 within caps after every wiring edit (prefer append-to-existing-line).

## Governance

Each slice: feature branch → PR → **human ratification** (Bradley merges; agent never self-merges). PROCESS/STANDARDS/crosswalk edits are governing-doc changes → **security-owner lens** at review. Each `ci.yml` step via control-plane `cp`. Kit stays generic/anonymized ([[kit-anonymization]]) — the children's-data references stay as a *regulated-archetype* illustration, not a named org.

## Out of scope / deferred

- **Ephemeral / preview environments** and **cross-stack test-data management** — the two smaller items, after this arc (Bradley's order).
- Runtime AI-security *products* (model firewalls, live prompt-injection scanners, SIEM) — Org-owned; named in the crosswalk, not implemented.
- Auto-detecting risk classification or "consequential" — not honestly possible; human-declared by design.
- ISO 42001 *certification* and state-law *legal determinations* — Org-owned; the kit produces the evidence/artifacts.
- EU-only conformity machinery (conformity assessment, CE marking, FRIA, EU-database registration) — explicitly excluded for a US adopter.

---

## Regulatory grounding (mid-2026, verified — US-first)

**US federal (deregulatory posture; no preemption in force):**
- Biden EO 14110 rescinded (Jan 2025). **"Winning the AI Race: America's AI Action Plan"** (Jul 2025) — removes "red tape and onerous regulation."
- **EO 14365** (Dec 2025) "Ensuring a National Policy Framework for AI" — AI Litigation Task Force to challenge state laws; funding conditioned on absence of "onerous" state laws. **No federal statute/court has preempted any state law — state requirements remain valid and enforceable.**
- **EO** (Jun 2, 2026) "Promoting Advanced AI Innovation and Security" — voluntary federal pre-release vetting of frontier models for national-security risks (NIST CAISI).
- State-law **moratorium failed** in the NDAA 2026 → state laws are the live compliance surface.
- **NIST AI RMF 1.0 + GenAI Profile (NIST-AI-600-1)** is the de-facto US standard; **Cyber AI Profile (IR 8596, Dec 2025)**; **AI Agent Standards Initiative (Feb 2026)**. *Texas TRAIGA grants a safe harbor for substantial NIST-AI-RMF-GenAI-Profile compliance — the practical anchor.*

**US state (the real deployer surface):**
- **Texas TRAIGA (HB 149)** — effective **Jan 1, 2026**; prohibits AI for unlawful discrimination, self-harm encouragement, **CSAM**; NIST-RMF safe harbor; penalties to $200k.
- **Colorado SB 26-189** (replaced the 2024 AI Act) — consequential-decision **disclosure/notice**; obligations **Jan 1, 2027** (lighter than the repealed risk-management regime).
- **California** — **ADMT** regulations (risk assessments from Jan 2026; significant-decision obligations phasing from Apr 2027); **SB 942** (AI transparency) + **AB 2013** (training-data transparency); **SB 53** frontier-developer-only (likely N/A for a deployer).

**US children's data (the adopter's real driver):**
- **Amended COPPA Rule** (FTC, Apr 2025; compliance by **Apr 22, 2026**) — expanded PII (biometric), mixed-audience standard, separate verifiable parental consent for third-party/targeted-ad disclosure, stricter retention/security.
- **FTC** AI enforcement — Jan 2026 **Snap AI-chatbot** DOJ referral (harm to minors); 2026 COPPA-enforcement priority.

**International / vendor-neutral (apply regardless of jurisdiction):**
- **ISO/IEC 42001:2023** (AIMS; clauses 4–10 + Annex A 38 controls + SoA; mandates AI risk + AI system impact assessment) · **ISO/IEC 42005** (impact assessment) · **42006:2025** (cert bodies). Pairs with SOC 2.
- **OWASP Top 10 for LLM Applications (2025)** + **Top 10 for Agentic Applications (Dec 9, 2025, ASI01–10)** + Agentic Threats taxonomy v1.1. **MITRE ATLAS v5.4.0 (Feb 2026)** — 16 tactics / 84 techniques (agent techniques incl. "Publish Poisoned AI Agent Tool", "Escape to Host").

**EU (optional overlay — only with EU market exposure):**
- **EU AI Act** in force Aug 2024; **Digital Omnibus** (Nov 2025 / political agreement May 2026) **postponed high-risk obligations** (Annex III → Dec 2027; embedded → Aug 2028). Prohibited practices + AI-literacy since Feb 2025; GPAI + Code of Practice since Aug 2025; **AI-generated CSAM / NCII prohibition → Dec 2, 2026**. Conformity-assessment / CE / FRIA / EU-DB registration are **EU-only and excluded from the US baseline**.

**Sources:** whitehouse.gov + CFR + Paul Hastings + StateScoop (US federal EO / AI Action Plan / moratorium) · King & Spalding + Cooley + Baker Botts + Glacis tracker (state laws: TX TRAIGA, CO SB 26-189, CA ADMT/SB 942/SB 53) · FTC + Loeb + White & Case + Davis Polk (COPPA amendments + enforcement) · nist.gov (AI RMF + GenAI/Cyber profiles) · iso.org / orbit.reconn.io (ISO 42001/42005/42006) · genai.owasp.org (OWASP LLM + Agentic Top 10) · MITRE ATLAS · Gibson Dunn / Global Policy Watch (EU omnibus). Re-verify fast-moving specifics (EO actions, state effective dates, OWASP/ATLAS revisions) at build time.
