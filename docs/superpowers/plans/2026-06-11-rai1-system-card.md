# RAI-1 — AI System Card + Risk Classification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give an AI feature a lightweight, US-anchored **AI System Card** (risk classification + human oversight + opt-in good-citizen lines) with a conditional, fail-closed `responsible-ai-ready` check — the first slice of the Responsible-AI arc.

**Architecture:** Mirrors the proven gate-parity pattern exactly. `responsible-ai-ready.sh` is a near-clone of `conformance/eval-ready.sh` (same `is_ai_feature` trigger, same N/A·OK·FAIL·`--selftest` shape, same L1-clean placeholder detection keyed on literal tokens). The System Card + AI Policy templates mirror the `THREAT-MODEL-TEMPLATE.md` guidance-blockquote style. `responsible-ai-readiness.md` mirrors `eval-readiness.md`. All conditional on an AI feature → **N/A (zero overhead) for non-AI projects**.

**Tech Stack:** POSIX sh (dash-clean; `set -eu`; no `local`/`[[`/`==`), Markdown templates, GitHub Actions YAML (CI selftest via control-plane `cp` — Bradley applies).

**Release:** `VERSION` → 2.48.0; MINOR (conditional check + two templates; no new universal gate).

**Honesty invariant:** a green `responsible-ai-ready` proves the AI System Card is **present + classified + oversight-named** — never that the classification is *correct*, the AI is *fair*, or it is *compliant*. Those stay Manual security/compliance-owner rows. The good-citizen lines (prohibited-use ack, data-minimization, review/appeal path) are **recommended defaults the check does NOT enforce** — guidance, never friction.

**Doc-budget (hard constraint):** core-3 headroom — `CLAUDE.md` 111/120, `DEVELOPMENT-PROCESS.md` 465/470 (**only 5 lines**), `DEVELOPMENT-STANDARDS.md` 309/320. **Prefer append-to-existing-line (+0).** The §7 gate row is +1 to PROCESS (→466/470, fits). Run `doc-budget.sh` after every core-doc edit.

**Governance:** branch `feature/responsible-ai-rai1-system-card` (already created; the arc spec + this plan live here) → PR → **Bradley merges** (agent never self-merges). PROCESS/STANDARDS edits → security-owner lens. `ci.yml` step via control-plane `cp`. Generic/anonymized ([[kit-anonymization]]).

---

## File Structure

- Create: `templates/AI-SYSTEM-CARD-TEMPLATE.md` — the declarative artifact (Task 1).
- Create: `templates/AI-POLICY-TEMPLATE.md` — one-page org AI policy (Task 2).
- Create: `conformance/responsible-ai-ready.sh` — conditional fail-closed check (Task 3).
- Create: `conformance/responsible-ai-readiness.md` — Auto-vs-Manual checklist (Task 4).
- Modify: `conformance/verify.sh` (doc-check row), `conformance/README.md` (2 rows), `conformance/audit-evidence-checklist.md` (row), `DEVELOPMENT-STANDARDS.md` (AI-security pointer, +0 append), `CLAUDE.md` (DoR flag + templates list, +0 appends), `DEVELOPMENT-PROCESS.md` (§7 gate row, +1) — Task 5.
- Modify (control-plane `cp`, Bradley applies): `.github/workflows/ci.yml` — Task 6.
- Modify: `VERSION`, `CHANGELOG.md`, `README.md` badge — Task 7.

---

## Task 1: AI System Card template

**Files:**
- Create: `templates/AI-SYSTEM-CARD-TEMPLATE.md`

The two keyed lines (`Risk classification:` and `Human oversight:`) are what `responsible-ai-ready.sh` greps. **L1 discipline:** the instructional HTML comments must NOT contain the literal `[classification]` / `[mechanism]` tokens (they'd false-trigger the detector after a user fills the value) — they say "the bracketed placeholder above."

- [ ] **Step 1: Write the template**

```markdown
# AI System Card

> **Template.** Delete the guidance; fill the sections. The declarative artifact for an **AI feature** (any behaviour depending on a model or prompt) — a US-anchored AI use declaration + risk classification, verified *present* by `conformance/responsible-ai-ready.sh`. Doubles as the ISO/IEC 42005 AI system impact assessment for adopters pursuing ISO 42001. **Proportional:** a low-risk feature fills only the summary + classification + oversight; a consequential-decision or children's-data feature fills the rest. The **security/compliance owner** signs at Review. Presence is not correctness — the classification's accuracy and the fairness/compliance results are **Manual** rows in `conformance/responsible-ai-readiness.md`. Store under `docs/sign-offs/` or attach to the PR.

## System summary
- **Feature / story:** <link>
- **What it does (1–2 lines):** [summary]
- **Model + version:** [e.g. claude-opus-4-8 — orchestrated frontier model, not trained in-house]
- **Build mode:** [orchestrate a frontier model · fine-tune · train from scratch]

## Risk classification (US-first)
- **Risk classification:** [classification]
  <!-- Answer three triggers: consequential/automated decision (employment, credit, housing, education, healthcare, insurance, legal)? · children's data (under-13 / mixed-audience → COPPA)? · prohibited use (unlawful discrimination, self-harm encouragement, CSAM, deception → hard stop)? → e.g. "low-risk — none triggered" or "consequential-decision: yes (hiring screen); children's-data: no; prohibited-use: no". Replace the bracketed placeholder above. -->
- **EU AI Act overlay** *(optional — only with EU market exposure)*: [tier or "N/A — no EU exposure"]
- **Prohibited-use acknowledgment** *(good-citizen, one-time)*: this feature is **not designed for** unlawful discrimination, self-harm encouragement, CSAM, or deception. [confirm / note exception]

## Intended use
- **Intended use:** [what it is for]
- **Out-of-scope / prohibited use:** [what it must not be used for]

## Data flows + consent
- **What data reaches the model:** [inputs; PII; children's data]
- **Consent basis + what leaves the trust boundary:** [consent; third-party/provider egress — links to egress/containment]
- **Data minimization** *(good-citizen)*: [minimize inputs to what the task needs, esp. PII/children's data]

## Human oversight
- **Human oversight:** [mechanism]
  <!-- who can override/halt the AI; links to "agents propose, humans ratify" + ratification RBAC. If a consequential decision: add a documented human review / appeal path. Replace the bracketed placeholder above. -->

## Guardrails (links, not restated)
- **Runtime controls:** [prompt-injection defense · MCP policy · egress · containment — link the kit controls already in place]
- **Eval / quality bar:** [link the EVAL-PLAN + §7 eval gate]

## Known limitations + failure modes
- [what it gets wrong; degradation modes; monitoring in production]

## Sign-off

| Field | Value |
|-------|-------|
| Decision | **pass** / pass-with-conditions / fail |
| Security / compliance owner (role) | <name> |
| Date | YYYY-MM-DD |
| Conditions / follow-ups | [tracked items, links] |
```

- [ ] **Step 2: Links resolve**

Run: `sh conformance/check-links.sh`
Expected: OK.

- [ ] **Step 3: Commit**

```bash
git add templates/AI-SYSTEM-CARD-TEMPLATE.md
git commit -m "feat(templates): AI System Card — US-anchored AI use declaration + risk classification + good-citizen lines (RAI-1)"
```

---

## Task 2: AI Policy template

**Files:**
- Create: `templates/AI-POLICY-TEMPLATE.md`

A one-page org-level AI policy (ISO 42001 Clause 5.2 for adopters who want it; useful regardless). Not gated; pointed-to from the System Card.

- [ ] **Step 1: Write the template**

```markdown
# AI Policy

> **Template.** A one-page organizational commitment to responsible AI. Optional but recommended — maps to ISO/IEC 42001 Clause 5.2 (AI policy) for adopters pursuing certification, and anchors the per-feature `AI-SYSTEM-CARD`s. Ratified by leadership; reviewed at least annually. Keep it short and real.

## Scope
- **Applies to:** [which teams / systems / AI features]
- **AI we use:** [orchestrated frontier models · fine-tuned · trained in-house]

## Principles
- **Human accountability** — a named human owns every AI feature's decisions; agents propose, humans ratify.
- **Proportional governance** — assurance scales with risk; low-risk AI stays low-friction.
- **Transparency** — users are told when they interact with AI; AI-generated content is labeled where it matters.
- **Fairness** — consequential AI is tested for disparate impact before it affects people.
- **Data minimization + privacy** — collect only what the task needs; children's data gets COPPA-grade care.
- **Prohibited uses** — no unlawful discrimination, self-harm encouragement, CSAM, or deception.

## Governance
- **Standard we align to:** [NIST AI RMF + GenAI Profile · ISO/IEC 42001 (optional) · applicable US state law]
- **Per-feature artifact:** every AI feature carries an `AI-SYSTEM-CARD` (`templates/AI-SYSTEM-CARD-TEMPLATE.md`).
- **Incident response:** AI incidents (harmful output, jailbreak, bias) follow the postmortem process and feed back into evals.
- **Review cadence:** this policy is reviewed at least annually and on any material AI change.

## Sign-off
| Field | Value |
|-------|-------|
| Owner (role) | <name> |
| Approved | YYYY-MM-DD |
| Next review | YYYY-MM-DD |
```

- [ ] **Step 2: Links + commit**

Run: `sh conformance/check-links.sh` → OK.
```bash
git add templates/AI-POLICY-TEMPLATE.md
git commit -m "feat(templates): one-page AI Policy template (ISO 42001 Clause 5.2; anchors the System Cards) (RAI-1)"
```

---

## Task 3: `responsible-ai-ready.sh` (conditional, fail-closed)

**Files:**
- Create: `conformance/responsible-ai-ready.sh`

Near-clone of `conformance/eval-ready.sh`: same `is_ai_feature` trigger (extended with the AI-System-Card signal so a card-bearing project binds), N/A·OK·FAIL·`--selftest`, L1-clean placeholder detection keyed on literal tokens (robust to `**bold**` keys).

- [ ] **Step 1: Write the script**

```sh
#!/bin/sh
# responsible-ai-ready.sh — conditional, fail-closed AI-governance-declared check (RAI-1).
#
# Companion to conformance/responsible-ai-readiness.md (the §7 AI System Card gate;
# DEVELOPMENT-PROCESS.md §7). For an AI FEATURE it asserts the governance is DECLARED: an
# AI-SYSTEM-CARD with a recorded US risk classification and a named human-oversight mechanism
# (not the [classification]/[mechanism] placeholders). Non-AI projects are N/A (skip-pass).
#
# SCOPE — a green run proves the card is PRESENT + CLASSIFIED + OVERSIGHT-NAMED, NOT that the
# classification is correct, the AI is fair, or it is compliant. Those are Manual security/
# compliance-owner rows in responsible-ai-readiness.md. The good-citizen lines (prohibited-use,
# data-minimization, review/appeal path) are recommended defaults this check does NOT enforce.
# A green run is necessary, not sufficient.
#
# Usage:
#   sh conformance/responsible-ai-ready.sh [project-dir]   (default: .)
#   sh conformance/responsible-ai-ready.sh --selftest
# Exit: 0 = OK or N/A · 1 = FAIL (AI feature with the governance undeclared). POSIX sh; dash-clean.
set -eu

# Is $1 an AI feature? (evals/ dir, EVAL-PLAN, AI-SYSTEM-CARD, or RUNBOOK/CLAUDE 'AI feature: yes')
is_ai_feature() {
  _d="$1"
  [ -d "$_d/evals" ] && return 0
  for p in "$_d/EVAL-PLAN.md" "$_d/docs/EVAL-PLAN.md" "$_d/evals/EVAL-PLAN.md" \
           "$_d/AI-SYSTEM-CARD.md" "$_d/docs/AI-SYSTEM-CARD.md"; do
    [ -f "$p" ] && return 0
  done
  for m in "$_d/RUNBOOK.md" "$_d/CLAUDE.md"; do
    # tolerate markdown between key and value (e.g. '**AI feature:** yes') — bold must still bind.
    [ -f "$m" ] && grep -Eiq 'ai feature:[^[:alnum:]]*(yes|true)' "$m" && return 0
  done
  return 1
}

# Echo the AI-SYSTEM-CARD path if one exists, else empty.
find_card() {
  for p in "$1/AI-SYSTEM-CARD.md" "$1/docs/AI-SYSTEM-CARD.md"; do
    [ -f "$p" ] && { printf '%s' "$p"; return 0; }
  done
  return 1
}

check_dir() {
  dir="$1"
  if ! is_ai_feature "$dir"; then
    echo "N/A: $dir is not an AI feature (no evals/ dir, no EVAL-PLAN, no AI-SYSTEM-CARD, no 'AI feature: yes' marker) — no AI governance to declare"
    return 0
  fi
  fail=0
  card=$(find_card "$dir" || true)
  if [ -z "$card" ]; then
    echo "FAIL: $dir is an AI feature but has no AI-SYSTEM-CARD.md — create one from templates/AI-SYSTEM-CARD-TEMPLATE.md"
    return 1
  fi
  # Record strings must stay in sync with templates/AI-SYSTEM-CARD-TEMPLATE.md.
  # Placeholder detection keys on the literal [classification]/[mechanism] tokens (robust to the
  # template's **bold** keys, which put `**` between the colon and the value).
  if ! grep -Eiq 'risk classification:' "$card"; then
    echo "FAIL: $card has no 'Risk classification:' — record the US risk classification (consequential / children's / prohibited)"; fail=1
  elif grep -Eiq 'risk classification:.*\[classification\]' "$card"; then
    echo "FAIL: 'Risk classification:' still holds the [classification] placeholder — record a real classification"; fail=1
  fi
  if ! grep -Eiq 'human oversight:' "$card"; then
    echo "FAIL: $card has no 'Human oversight:' — name the override/halt mechanism"; fail=1
  elif grep -Eiq 'human oversight:.*\[mechanism\]' "$card"; then
    echo "FAIL: 'Human oversight:' still holds the [mechanism] placeholder — name a real oversight mechanism"; fail=1
  fi
  if [ "$fail" -ne 0 ]; then return 1; fi
  echo "responsible-ai-ready: OK — AI System Card is PRESENT, classified, and oversight-named. NOTE: does NOT verify the classification is correct, the AI is fair, or it is compliant — those are Manual rows (responsible-ai-readiness.md). Good-citizen lines are recommended, not enforced."
  return 0
}

# mktemp fixtures; assert each outcome. Fixtures LEFT in place (no rm -rf; 7e guard).
selftest() {
  st=0
  base=$(mktemp -d)
  CARD_OK='# AI System Card\n- **Risk classification:** low-risk — none triggered\n- **Human oversight:** lead engineer can halt; standard human review\n'

  d="$base/not-ai"; mkdir -p "$d"; printf '# a CLI tool\n' > "$d/README.md"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest PASS: non-AI -> N/A"; else echo "selftest FAIL: non-AI should be N/A"; st=1; fi

  d="$base/ai-evalsdir-nocard"; mkdir -p "$d/evals"; printf 'x\n' > "$d/evals/run.py"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest FAIL: AI(evals/) + no card should FAIL"; st=1; else echo "selftest PASS: AI(evals/) + no card -> FAIL"; fi

  d="$base/ai-card-complete"; mkdir -p "$d"
  printf '%b' "$CARD_OK" > "$d/AI-SYSTEM-CARD.md"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest PASS: AI(card) + complete -> OK"; else echo "selftest FAIL: complete card should pass"; st=1; fi

  d="$base/ai-card-classification-placeholder"; mkdir -p "$d"
  printf '# AI System Card\n- **Risk classification:** [classification]\n- **Human oversight:** lead can halt\n' > "$d/AI-SYSTEM-CARD.md"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest FAIL: [classification] placeholder should FAIL"; st=1; else echo "selftest PASS: [classification] placeholder -> FAIL"; fi

  d="$base/ai-card-oversight-placeholder"; mkdir -p "$d"
  printf '# AI System Card\n- **Risk classification:** low-risk\n- **Human oversight:** [mechanism]\n' > "$d/AI-SYSTEM-CARD.md"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest FAIL: [mechanism] placeholder should FAIL"; st=1; else echo "selftest PASS: [mechanism] placeholder -> FAIL"; fi

  # a BOLD 'AI feature' marker must bind (not slip to N/A): no card -> FAIL
  d="$base/ai-boldmarker-nocard"; mkdir -p "$d"
  printf '# RUNBOOK\n- **AI feature:** yes\n' > "$d/RUNBOOK.md"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest FAIL: bold marker should bind -> FAIL (no card)"; st=1; else echo "selftest PASS: bold marker binds -> FAIL (no card)"; fi

  if [ "$st" -ne 0 ]; then echo "responsible-ai-ready --selftest: FAIL" >&2; return 1; fi
  echo "responsible-ai-ready --selftest: OK (non-ai/no-card/complete/classification-placeholder/oversight-placeholder/bold-marker all behaved; fixtures left in $base)"
  return 0
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  *)          check_dir "${1:-.}"; exit $? ;;
esac
```

- [ ] **Step 2: chmod + syntax + selftest**

```bash
chmod +x conformance/responsible-ai-ready.sh
dash -n conformance/responsible-ai-ready.sh && echo "dash OK"
sh conformance/responsible-ai-ready.sh --selftest
```
Expected: dash OK; 6/6 selftest PASS + `responsible-ai-ready --selftest: OK`.

- [ ] **Step 3: Kit-root live run must be N/A**

Run: `sh conformance/responsible-ai-ready.sh; echo "exit=$?"`
Expected: `N/A: . is not an AI feature ...` and `exit=0`.

- [ ] **Step 4: Coupling check — fresh template copy → FAIL, then filled → OK**

```bash
t=$(mktemp -d); cp templates/AI-SYSTEM-CARD-TEMPLATE.md "$t/AI-SYSTEM-CARD.md"
sh conformance/responsible-ai-ready.sh "$t"; echo "fresh exit=$?"   # FAIL (placeholders)
sed -e 's/\*\*Risk classification:\*\* \[classification\]/**Risk classification:** low-risk — none triggered/' \
    -e 's/\*\*Human oversight:\*\* \[mechanism\]/**Human oversight:** lead can halt; standard review/' \
    templates/AI-SYSTEM-CARD-TEMPLATE.md > "$t/AI-SYSTEM-CARD.md"
sh conformance/responsible-ai-ready.sh "$t"; echo "filled exit=$?"  # OK (comment retained, value filled — L1 clean)
```
Expected: fresh → FAIL exit 1; filled (comments retained) → OK exit 0. Confirms no false PASS on a fresh template AND no L1 false-FAIL on a filled-but-comment-retained card.

- [ ] **Step 5: Commit**

```bash
git add conformance/responsible-ai-ready.sh
git commit -m "feat(conformance): responsible-ai-ready.sh — conditional AI-governance-declared check (AI-feature trigger; classification + oversight recorded) (RAI-1)"
```

---

## Task 4: `responsible-ai-readiness.md` checklist

**Files:**
- Create: `conformance/responsible-ai-readiness.md`

Mirror `eval-readiness.md`: header, "What the Auto rows prove — and don't" honesty blockquote, how-to-use, blank checklist (Auto = card present/classified/oversight-named; Manual = classification correct, fairness tested, transparency shipped, compliance).

- [ ] **Step 1: Write the checklist**

```markdown
# Conformance Check — Responsible-AI Readiness

Proves an **AI feature** carries its governance declaration: an **AI System Card** with a US risk classification and a named human-oversight mechanism. **Checklist-type**, run at the **§7 AI System Card gate** (`DEVELOPMENT-PROCESS.md` §7) and as **recurring maintenance** (§15). **Conditional:** a project with no model/prompt marks the whole check **N/A — not an AI feature**. US-anchored (NIST AI RMF + GenAI Profile · TX TRAIGA · CO/CA consequential-decision · COPPA/FTC); EU AI Act is an optional overlay. Verifies the discipline asserted in `DEVELOPMENT-STANDARDS.md` (AI / agent security) and the arc spec.

> **What the Auto rows prove — and don't.** `responsible-ai-ready.sh` confirms the AI System Card is *present, classified, and oversight-named*. It does **not** verify the classification is *correct*, the AI is *fair*, the disclosure *shipped*, or it is *compliant* — those are the **Manual** rows below, signed by the security/compliance owner. The good-citizen lines (prohibited-use ack, data-minimization, review/appeal path) are recommended defaults, **not enforced**. **A green script is necessary, not sufficient.**

## How to use
Produce an `AI-SYSTEM-CARD.md` from `templates/AI-SYSTEM-CARD-TEMPLATE.md`. Items tagged *(documented)* are auto-checkable via `sh conformance/responsible-ai-ready.sh`; items tagged *(verified)* require the owner's judgement/evidence.

## Checklist (blank)

| # | Item | Applies? | Evidence (where/how) | Check |
|---|------|----------|----------------------|-------|
| 1 | `AI-SYSTEM-CARD.md` present *(documented)* | | | **Auto:** `responsible-ai-ready.sh` |
| 2 | US risk classification recorded (consequential / children's / prohibited) *(documented)* | | | **Auto:** `responsible-ai-ready.sh` |
| 3 | Human-oversight mechanism named *(documented)* | | | **Auto:** `responsible-ai-ready.sh` |
| 4 | Classification is **correct** for the actual use *(verified)* | | | Manual |
| 5 | Fairness / disparate-impact tested where consequential (→ EVAL-PLAN) *(verified)* | | | Manual / §7 Eval gate |
| 6 | User-facing AI disclosure + content labeling shipped where applicable *(verified)* | | | Manual |
| 7 | Children's-data care (COPPA: consent, minimization, retention) where applicable *(verified)* | | | Manual |
| 8 | Security/compliance owner signed the card *(verified)* | | | Manual |

> A non-AI project (CLI, library, batch job with no model) marks the whole check **N/A — not an AI feature**; `responsible-ai-ready.sh` skip-passes it automatically.
```

- [ ] **Step 2: Links + commit**

Run: `sh conformance/check-links.sh` → OK.
```bash
git add conformance/responsible-ai-readiness.md
git commit -m "docs(conformance): responsible-ai-readiness checklist (Auto: card present+classified+oversight; Manual: correct/fair/disclosed/compliant) (RAI-1)"
```

---

## Task 5: Wiring (verify.sh · README · audit · STANDARDS · CLAUDE · PROCESS §7)

**Files:**
- Modify: `conformance/verify.sh`, `conformance/README.md`, `conformance/audit-evidence-checklist.md`, `DEVELOPMENT-STANDARDS.md`, `CLAUDE.md`, `DEVELOPMENT-PROCESS.md`

- [ ] **Step 1: verify.sh doc-check row**

After the `observability-ready` row, add:
```
check doc     responsible-ai-ready sh conformance/responsible-ai-ready.sh
```

- [ ] **Step 2: conformance/README.md — two rows + evidence bullet**

After the `observability-ready.sh` row, add (mirroring the eval-ready row style):
```
| `responsible-ai-readiness.md` | checklist | RAI arc — AI System Card present + classified + oversight (US-anchored; EU optional) | Review / §7 (conditional on an AI feature) |
| `responsible-ai-ready.sh` | script | RAI arc — the AI-governance declaration is present (AI System Card + classification + oversight); conditional (N/A for non-AI). Does NOT judge correctness/fairness/compliance. Pairs with `responsible-ai-readiness.md` | Review / CI (conditional on an AI feature) |
```
Add `responsible-ai-ready.sh` to the documentation/evidence-class bullet (the `eval-ready.sh`/`observability-ready.sh` list).

- [ ] **Step 3: audit-evidence-checklist.md — row**

After the Observability row, add:
```
| AI governance · System Card (if AI feature) | CC1.2, CC2.1 / A.5.1 / NIST AI RMF GOVERN, MAP | AI-SYSTEM-CARD + classification + sign-off | **Auto (conditional):** `sh conformance/responsible-ai-ready.sh` (+ Manual fairness/disclosure/compliance) | |
```
(Match the existing column layout exactly; use the neighboring rows' control-ID convention. NIST AI RMF functions GOVERN/MAP are the natural anchor.)

- [ ] **Step 4: DEVELOPMENT-STANDARDS.md — AI-security pointer (+0 append)**

In the AI / agent security subsection (§2, ~line 50), append a pointer to an existing line:
```
… AI features carry an AI System Card (`templates/AI-SYSTEM-CARD-TEMPLATE.md`; readiness `conformance/responsible-ai-readiness.md`).
```
(Append to an existing bullet — do NOT add a line, to protect doc-budget. If no natural host, a single new bullet is acceptable — headroom 309/320.)

- [ ] **Step 5: CLAUDE.md — DoR flag + templates list (+0 appends)**

Line 75 (Eval-criteria DoR flag) append the System Card pointer:
```
- **Eval criteria** *(if an AI feature)* — flagged for the §7 eval gate; the feature carries an AI System Card (`templates/AI-SYSTEM-CARD-TEMPLATE.md`).
```
Line 17 templates list — add `AI-SYSTEM-CARD`, `AI-POLICY` to the comma list.

- [ ] **Step 6: DEVELOPMENT-PROCESS.md — §7 gate row (+1 line)**

After the Eval-gate row (or near the Threat-model row) in the §7 table, add:
```
| **AI System Card** *(AI features)* | Is the AI governance declared — risk classified (consequential / children's / prohibited), human oversight named? (`conformance/responsible-ai-readiness.md`) | Security / compliance owner + reviewer |
```

- [ ] **Step 7: Verify wiring**

```bash
sh conformance/verify.sh 2>&1 | grep -E 'Summary|RESULT'   # doc-checks now 6
sh conformance/doc-budget.sh && echo "doc-budget OK"
sh conformance/check-links.sh && echo "links OK"
```
Expected: `verify.sh` RESULT: OK (6 doc-checks); doc-budget OK (PROCESS ≤470); links OK.

- [ ] **Step 8: Commit**

```bash
git add conformance/verify.sh conformance/README.md conformance/audit-evidence-checklist.md DEVELOPMENT-STANDARDS.md CLAUDE.md DEVELOPMENT-PROCESS.md
git commit -m "docs(conformance): wire responsible-ai readiness — verify.sh + README/audit rows + §7 gate row + STANDARDS/CLAUDE pointers (RAI-1)"
```

---

## Task 6: CI selftest step (control-plane `cp` — Bradley applies)

**Files:**
- Modify (control-plane): `.github/workflows/ci.yml`

The agent cannot edit `.github/workflows/`. Prepare the exact diff for Bradley.

- [ ] **Step 1: Prepare the step**

After the Observability-ready selftest step, add:
```yaml
      - name: Responsible-AI-ready self-test (AI System Card discipline)
        run: sh conformance/responsible-ai-ready.sh --selftest
```

- [ ] **Step 2: Hand the diff to Bradley** to apply + commit (`ci(rai-1): run responsible-ai-ready.sh --selftest`). Do NOT edit the file directly.

---

## Task 7: Release v2.48.0 + final verification + PR

**Files:**
- Modify: `VERSION` → `2.48.0`; `CHANGELOG.md`; `README.md` badge.

- [ ] **Step 1: Bump VERSION** to `2.48.0`.

- [ ] **Step 2: CHANGELOG entry** under `## [2.48.0] - <date>` (match the 2.47.0 entry shape: prose intro + `### Added` + `### Honesty`). Cover the System Card + AI Policy templates + `responsible-ai-ready` check + US-anchored classification + good-citizen lines (not enforced). Note RAI-1 of the Responsible-AI arc.

- [ ] **Step 3: README badge** → `v2.48.0`; `sh conformance/badge-version.sh` → OK.

- [ ] **Step 4: Full verification**

```bash
dash -n conformance/responsible-ai-ready.sh && echo "dash OK"
sh conformance/responsible-ai-ready.sh --selftest
sh conformance/responsible-ai-ready.sh; echo "kit-root exit=$?"   # N/A, exit 0
sh conformance/check-links.sh && echo "links OK"
sh conformance/doc-budget.sh && echo "doc-budget OK"
sh conformance/badge-version.sh && echo "badge OK"
sh conformance/verify.sh 2>&1 | tail -4
```
Expected: dash OK; selftest 6/6 + OK; kit-root N/A exit 0; links OK; doc-budget OK; badge OK; `verify.sh` RESULT: OK (6 doc-checks).

- [ ] **Step 5: Commit the release**

```bash
git add VERSION CHANGELOG.md README.md
git commit -m "chore(release): 2.48.0 — RAI-1 AI System Card + risk classification (Responsible-AI arc)"
```

- [ ] **Step 6: Independent review (builder ≠ sole reviewer) — security-owner lens**

Dispatch an independent security-owner review over the full branch diff (governing-doc + §7 gate + new conditional check). Checks: honesty/no-overclaim (green = declared, not fair/compliant); trigger correctness (non-AI → N/A, AI+no-card → FAIL, placeholder → FAIL, bold marker binds, low-risk card → OK proportional); L1 cleanliness (filled-but-comment-retained card → OK; fresh → FAIL); POSIX/dash + `set -eu`; US-first (no EU-only burden in any baseline/check); good-citizen lines NOT enforced; doc-budget; governance not weakened. Fold Critical/High/Medium; carry LOWs with rationale.

- [ ] **Step 7: Push + open PR (Bradley merges)**

```bash
git push -u origin feature/responsible-ai-rai1-system-card
gh pr create --base main --head feature/responsible-ai-rai1-system-card \
  --title "RAI-1 — AI System Card + risk classification (v2.48.0)" --body "<summary + verification + folded nits>"
```
Report the PR number + merge command (`gh pr merge <n> --squash --admin --delete-branch`). **Do not self-merge.**

---

## Verification (whole slice)

- `responsible-ai-ready.sh`: `dash -n` clean; `--selftest` 6/6; kit-root N/A (exit 0); fresh template → FAIL; filled-but-comment-retained → OK (L1 clean).
- `verify.sh` RESULT: OK with **6 doc-checks**; `check-links`, `doc-budget` (PROCESS ≤470), `badge-version` green; bootstrap-into-temp unaffected.
- Conditional + proportional: non-AI → N/A (zero overhead); low-risk card → OK; good-citizen lines never cause a FAIL.
- US-first: no EU-only obligation in any baseline path or check; EU overlay is optional-N/A in the template.
- Governance: branch → PR → Bradley merges; CI step via control-plane `cp`; security-owner lens at review.

## Out of scope (this slice)
- Fairness eval dimension + AI-output transparency sign-off (RAI-2).
- AI-governance crosswalk + agentic-threat lens (RAI-3).
- Ephemeral environments + cross-stack test-data (after the arc).
