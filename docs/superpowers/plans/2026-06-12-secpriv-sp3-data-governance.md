# SP-3 — Data Governance (Classification + DPIA-lite) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A general data-governance capability — a 4-tier **data-classification scheme** declared per project, and a **DPIA-lite privacy review** required (and conformance-checked) when a project declares it handles **Confidential/Restricted** data.

**Architecture:** The readiness-check family (mirror `conformance/security-policy.sh`). `conformance/privacy-ready.sh` is conditional: it triggers only when a project's `Data classification:` declaration names **Confidential** or **Restricted** (real personal/sensitive data) → a `PRIVACY-REVIEW.md` must exist and be filled. Public/Internal-only, unclassified, or no-declaration → **N/A** (incl. the kit itself, which handles no personal data — N/A is honest, not a dogfood gap). General capability; COPPA is **one applicability, not a mandate** (the honesty invariant already prevents over-claiming compliance).

**Tech Stack:** `sh` (dash-clean), Markdown. Spec: `docs/superpowers/specs/2026-06-12-security-privacy-completeness-arc-design.md` §3 SP-3. Branch: `feature/secpriv-sp3`. **Doc-budget:** core-3 is at the 900 cap — the ONLY core-doc edit is a **`+0` fold** into CLAUDE.md DoR line 73; everything else is templates / `docs/enterprise/` (not capped). Do NOT touch PROCESS/STANDARDS.

---

## Conventions
- `#!/bin/sh`, `set -eu`, dash-clean. Colon-adjacent record lines (SNP-1). Coupling-test both directions.
- `--selftest` mktemp fixtures left in place (7e guard).
- CI step names colon-free (the #80 lesson).
- Commit per task. Run `doc-budget.sh` after the CLAUDE.md edit (must stay 900/900).

---

## File Structure
- **Create** `templates/PRIVACY-REVIEW-TEMPLATE.md` — the DPIA-lite template (with placeholders).
- **Create** `conformance/privacy-ready.sh` — conditional three-state check + `--selftest`.
- **Create** `docs/enterprise/data-governance.md` — the classification scheme + retention + DPIA guidance.
- **Modify** `templates/PROJECT-CLAUDE-TEMPLATE.md` §3 — a `Data classification:` declaration line.
- **Modify** `templates/RUNBOOK-TEMPLATE.md` — a `Data handling:` record (classification + retention + deletion).
- **Modify** `CLAUDE.md` line 73 — **`+0` fold** the privacy-review flag into the threat-model DoR line.
- **Modify** `conformance/verify.sh` + `conformance/README.md` + `conformance/audit-evidence-checklist.md` — doc-check + registry + audit rows.
- **Hand-apply (control-plane, Bradley):** kit-CI `privacy-ready.sh --selftest` smoke (batched with SP-2's at arc close).

---

## Task 1: `templates/PRIVACY-REVIEW-TEMPLATE.md` (DPIA-lite)

**Files:** Create `templates/PRIVACY-REVIEW-TEMPLATE.md`

- [ ] **Step 1: Write the template**

```markdown
# Privacy Review (DPIA-lite)

> **Template.** Copy to `PRIVACY-REVIEW.md` (or a per-feature `privacy/<feature>.md`) when a feature
> handles **Confidential or Restricted** personal data. Replace every `[…]`. Delete this blockquote.
> This is a lightweight Data Protection Impact Assessment — proportionate, not a legal opinion.

## 1. Purpose & data
- **Feature / purpose:** [what this does and why it needs the data]
- **Data collected:** [fields] · **Classification:** [Confidential / Restricted]
- **Data subjects:** [who — note if minors/children are in scope]

## 2. Lawful basis & consent
- **Lawful basis / basis for processing:** [consent / contract / legitimate interest / legal obligation]
- **Consent mechanism (if applicable):** [how consent is obtained + recorded; for children, the verifiable-consent path]

## 3. Minimization & retention
- **Data minimization:** [why each field is necessary; what was deliberately NOT collected]
- **Retention:** [how long, and why] · **Deletion path:** [how data is deleted on request / at end of retention]

## 4. Sharing & residual risk
- **Third-party sharing / processors:** [who, what, the safeguard — DPA/contract]
- **Residual privacy risk:** [the main residual risk after mitigations + the accepted-by]

## 5. Sign-off
- **Reviewed by:** [name/role] · **Date:** [date] · **Re-review trigger:** [scope change / new data field]
```

- [ ] **Step 2: Links + commit**

Run: `sh conformance/check-links.sh 2>&1 | tail -1`
```bash
git add templates/PRIVACY-REVIEW-TEMPLATE.md
git commit -m "feat(templates): PRIVACY-REVIEW — DPIA-lite for Confidential/Restricted data"
```

---

## Task 2: `conformance/privacy-ready.sh` + `--selftest` (TDD core)

**Files:** Create `conformance/privacy-ready.sh`

- [ ] **Step 1: Write the check**

```sh
#!/bin/sh
# privacy-ready.sh — conditional, fail-closed privacy-review check (SP-3).
#
# Trigger: a project that DECLARES it handles Confidential/Restricted personal data
# (a "Data classification:" line in CLAUDE.md or RUNBOOK.md naming Confidential or Restricted,
# not the template placeholder) MUST carry a filled PRIVACY-REVIEW.md (DPIA-lite). Projects with
# only Public/Internal data, an unfilled placeholder, or no declaration are N/A — no personal-data
# review required. A general capability; COPPA is one applicability, not a mandate.
#
# SCOPE: green = a privacy review is RECORDED for the declared sensitive data — NOT that the
# processing is lawful/compliant or that deletion actually works. Those are Manual operator rows.
#
# Usage:
#   sh conformance/privacy-ready.sh [project-dir]   (default: .)
#   sh conformance/privacy-ready.sh --selftest
set -eu

# declares_sensitive <dir>: true if a Data-classification line names Confidential/Restricted
# with a REAL value (not the [Public / Internal / Confidential / Restricted] template placeholder).
declares_sensitive() {
  _d="$1"
  for f in "$_d/CLAUDE.md" "$_d/RUNBOOK.md"; do
    [ -f "$f" ] || continue
    # the classification line, lowercased; skip if it still holds the bracketed placeholder list
    _line=$(grep -i 'data classification:' "$f" 2>/dev/null | head -1 | tr '[:upper:]' '[:lower:]') || true
    [ -n "$_line" ] || continue
    printf '%s' "$_line" | grep -q '\[' && continue   # unfilled placeholder -> not a real declaration
    printf '%s' "$_line" | grep -Eq 'confidential|restricted' && return 0
  done
  return 1
}

check_dir() {
  dir="$1"
  if ! declares_sensitive "$dir"; then
    echo "N/A: $dir declares no Confidential/Restricted data (or none classified) — skipping (no privacy review required)"
    return 0
  fi
  pr="$dir/PRIVACY-REVIEW.md"
  if [ ! -f "$pr" ]; then
    echo "FAIL: $dir handles Confidential/Restricted data but has no PRIVACY-REVIEW.md — record a DPIA-lite (templates/PRIVACY-REVIEW-TEMPLATE.md)"
    return 1
  fi
  if ! grep -Eiq 'lawful basis' "$pr"; then
    echo "FAIL: PRIVACY-REVIEW.md has no 'Lawful basis' — record the basis for processing"
    return 1
  fi
  if grep -Fiq '[lawful basis' "$pr" || grep -Fiq 'basis for processing:** [' "$pr"; then
    echo "FAIL: PRIVACY-REVIEW.md still holds the lawful-basis placeholder — fill the review"
    return 1
  fi
  echo "privacy-ready: OK — a PRIVACY-REVIEW is recorded for the declared sensitive data. NOTE: this does NOT verify the processing is lawful/compliant or that deletion works — those are Manual rows."
  return 0
}

selftest() {
  st_fail=0
  base=$(mktemp -d)

  d1="$base/na_public"; mkdir -p "$d1"; printf '# CLAUDE\n\n- **Data classification:** Internal\n' > "$d1/CLAUDE.md"
  if check_dir "$d1" >/dev/null 2>&1; then echo "selftest PASS: Internal-only -> N/A"; else echo "selftest FAIL: Internal should be N/A"; st_fail=1; fi

  d2="$base/na_placeholder"; mkdir -p "$d2"; printf '# CLAUDE\n\n- **Data classification:** [Public / Internal / Confidential / Restricted]\n' > "$d2/CLAUDE.md"
  if check_dir "$d2" >/dev/null 2>&1; then echo "selftest PASS: unfilled placeholder -> N/A"; else echo "selftest FAIL: placeholder should be N/A"; st_fail=1; fi

  d3="$base/missing"; mkdir -p "$d3"; printf '# CLAUDE\n\n- **Data classification:** Restricted\n' > "$d3/CLAUDE.md"
  if check_dir "$d3" >/dev/null 2>&1; then echo "selftest FAIL: Restricted + no review should FAIL"; st_fail=1; else echo "selftest PASS: Restricted + no review -> FAIL"; fi

  d4="$base/review_placeholder"; mkdir -p "$d4"; printf '# CLAUDE\n\n- **Data classification:** Confidential\n' > "$d4/CLAUDE.md"
  printf '# Privacy Review\n\n- **Lawful basis / basis for processing:** [consent / contract / legitimate interest / legal obligation]\n' > "$d4/PRIVACY-REVIEW.md"
  if check_dir "$d4" >/dev/null 2>&1; then echo "selftest FAIL: review placeholder should FAIL"; st_fail=1; else echo "selftest PASS: review placeholder -> FAIL"; fi

  d5="$base/ok"; mkdir -p "$d5"; printf '# CLAUDE\n\n- **Data classification:** Restricted\n' > "$d5/CLAUDE.md"
  printf '# Privacy Review\n\n- **Lawful basis / basis for processing:** verifiable parental consent (COPPA)\n' > "$d5/PRIVACY-REVIEW.md"
  if check_dir "$d5" >/dev/null 2>&1; then echo "selftest PASS: filled review -> OK"; else echo "selftest FAIL: filled review should pass"; st_fail=1; fi

  if [ "$st_fail" -ne 0 ]; then echo "privacy-ready --selftest: FAIL" >&2; return 1; fi
  echo "privacy-ready --selftest: OK (na/placeholder/missing/review-placeholder/ok all behaved; fixtures left in $base)"
  return 0
}

case "${1:-}" in
  --selftest) selftest ;;
  *)          check_dir "${1:-.}" ;;
esac
exit $?
```

- [ ] **Step 2: Run the selftest**

Run: `sh conformance/privacy-ready.sh --selftest`
Expected: five `selftest PASS` lines + `privacy-ready --selftest: OK`.

- [ ] **Step 3: Real-repo run is N/A (the kit declares no Restricted data)**

Run: `sh conformance/privacy-ready.sh; echo "exit=$?"`
Expected: `N/A: . declares no Confidential/Restricted data …` then `exit=0`. (Correct — the kit handles no personal data; N/A is honest.)

- [ ] **Step 4: dash-clean + commit**

Run: `dash -n conformance/privacy-ready.sh && echo dash-clean`
```bash
git add conformance/privacy-ready.sh
git commit -m "feat(conformance): privacy-ready.sh — DPIA when Confidential/Restricted declared"
```

---

## Task 3: `docs/enterprise/data-governance.md` (the scheme + bulk)

**Files:** Create `docs/enterprise/data-governance.md`

- [ ] **Step 1: Create the file**

```markdown
# Data Governance — Classification, Retention & Privacy Review

A general capability: classify the data a project handles, set retention/deletion per tier, and
record a **DPIA-lite privacy review** for sensitive data. Right-sized hygiene — **COPPA / children's
data is one applicability, not the point**; the kit gives you the artifact to *record* a privacy
posture, it does not assert you are "compliant" (the honesty invariant: green = recorded, not lawful).

## Classification scheme (4 tiers)

| Tier | Meaning | Handling (baseline) |
|------|---------|---------------------|
| **Public** | Intended for public release | No restriction |
| **Internal** | Non-public, low sensitivity | Access-controlled; no PII |
| **Confidential** | PII / commercially sensitive | Encrypt at rest + in transit; least-privilege; audit access; a **privacy review** |
| **Restricted** | Regulated / children's data / special-category | Confidential controls **plus** explicit lawful basis/consent, minimization, deletion path, and DPIA sign-off |

Declare the **highest tier a project handles** in the project `CLAUDE.md` §3
(`Data classification:`); record **retention + deletion** in `RUNBOOK.md` (`Data handling:`).

## Retention & deletion
- Set a retention period per dataset, justified by purpose; delete (or anonymize) at end of retention.
- Provide a **deletion-on-request** path for Confidential/Restricted (right-to-erasure where applicable).
- Record both in `RUNBOOK.md` `Data handling:`. The check confirms they are *recorded*; that deletion
  *works* is a Manual operator row.

## Privacy review (DPIA-lite)
When a feature handles **Confidential/Restricted** data, fill `templates/PRIVACY-REVIEW-TEMPLATE.md`
(purpose · data + classification · lawful basis/consent · minimization · retention · sharing · residual
risk · sign-off). Flagged at the **Definition of Ready** (alongside the threat-model flag) and verified
by `conformance/privacy-ready.sh`. For per-feature rigor, keep one review per feature touching personal data.

## Honesty boundary
`privacy-ready.sh` green proves a privacy review is **recorded** for the declared sensitive data — never
that the processing is lawful, that consent is valid, or that deletion works. Those are Manual rows
(operator/DPO evidence). Necessary, not sufficient.
```

- [ ] **Step 2: Links + commit**

Run: `sh conformance/check-links.sh 2>&1 | tail -1`
```bash
git add docs/enterprise/data-governance.md
git commit -m "docs(enterprise): data-governance — classification + retention + DPIA-lite"
```

---

## Task 4: Template declarations + the `+0` DoR fold

**Files:** Modify `templates/PROJECT-CLAUDE-TEMPLATE.md`, `templates/RUNBOOK-TEMPLATE.md`, `CLAUDE.md`

- [ ] **Step 1: `Data classification:` in PROJECT-CLAUDE-TEMPLATE §3**

In `templates/PROJECT-CLAUDE-TEMPLATE.md` §3 (after the SLO line ~50), add:
```markdown
- **Data classification** (§privacy): [Public / Internal / Confidential / Restricted] — the highest tier this project handles. Confidential/Restricted ⇒ a privacy review (`docs/enterprise/data-governance.md`; verified by `conformance/privacy-ready.sh`).
```

- [ ] **Step 2: `Data handling:` record in RUNBOOK-TEMPLATE**

In `templates/RUNBOOK-TEMPLATE.md` §2 (after the "Test data" line ~20), add (colon-adjacent):
```markdown
- **Data handling:** [classification · retention · deletion path] *(personal-data projects — `docs/enterprise/data-governance.md`)*
```

- [ ] **Step 3: `+0` fold the privacy-review flag into CLAUDE.md DoR line 73**

In `CLAUDE.md`, replace the existing threat-model conditional-flag line (line 73):
```markdown
- **Threat-model** *(if sensitive/regulated)* — flagged for the §7 security gate (`templates/THREAT-MODEL-TEMPLATE.md`).
```
with (same one line, now naming the privacy review too):
```markdown
- **Threat-model / privacy review** *(if sensitive/regulated/personal data)* — flagged for the §7 security gate; threat model + a DPIA-lite when Confidential/Restricted (`templates/THREAT-MODEL-TEMPLATE.md`, `templates/PRIVACY-REVIEW-TEMPLATE.md`; verified by `conformance/privacy-ready.sh`).
```

- [ ] **Step 4: Budget MUST hold at 900 + links**

Run: `sh conformance/doc-budget.sh && sh conformance/check-links.sh 2>&1 | tail -1`
Expected: `PASS: core-3 total 900/900` (the fold is `+0` — CLAUDE.md line count unchanged), `OK: core docs within budget`, links OK. **If core-3 shows 901, the fold added a line — recheck Step 3 replaced one line with one line.**

- [ ] **Step 5: Commit**

```bash
git add templates/PROJECT-CLAUDE-TEMPLATE.md templates/RUNBOOK-TEMPLATE.md CLAUDE.md
git commit -m "feat: data-classification declaration + RUNBOOK record + DoR privacy flag (+0)"
```

---

## Task 5: Wire into verify.sh + registry/audit rows

**Files:** Modify `conformance/verify.sh`, `conformance/README.md`, `conformance/audit-evidence-checklist.md`

- [ ] **Step 1: verify.sh doc-check row** — after the `check doc security-policy …` row:
```sh
check doc     privacy-ready   sh conformance/privacy-ready.sh
```

- [ ] **Step 2: Run the aggregate**

Run: `sh conformance/verify.sh 2>&1 | grep -E "privacy-ready|RESULT"`
Expected: `[doc] privacy-ready PASS` (kit is N/A → skip-pass → PASS) and `RESULT: OK`.

- [ ] **Step 3: Registry + audit rows** — add `privacy-ready.sh` to the `conformance/README.md` table (mirror `security-policy.sh`); add to `conformance/audit-evidence-checklist.md`:
```markdown
| Privacy review recorded (Confidential/Restricted) | `privacy-ready.sh` | Auto | PRIVACY-REVIEW.md |
| Processing lawful + deletion works | operator/DPO evidence | Manual | DPIA sign-off + erasure test |
```

- [ ] **Step 4: Links + commit**

Run: `sh conformance/check-links.sh 2>&1 | tail -1 && sh conformance/verify.sh | tail -3`
```bash
git add conformance/verify.sh conformance/README.md conformance/audit-evidence-checklist.md
git commit -m "feat(conformance): wire privacy-ready into verify.sh + registry/audit rows"
```

---

## Task 6: Prepare the control-plane CI smoke (batched with SP-2, for Bradley)

**Files:** Hand-apply (Bradley): `.github/workflows/ci.yml`

- [ ] **Step 1: Produce both arc-remaining smoke steps** (colon-free names) for ONE combined hand-apply at arc close:
```yaml
      - name: Security-policy self-test (SECURITY.md disclosure record)
        run: sh conformance/security-policy.sh --selftest
      - name: Privacy-ready self-test (DPIA-lite record)
        run: sh conformance/privacy-ready.sh --selftest
```
- [ ] **Step 2: Surface both in the PR body** (clean block, no `#` comments) with the `KIT_GUARD_SELFEDIT=1 git add … ; git commit` apply commands + a note to `gh run watch` for green. *(No repo change in this task.)*

---

## Task 7: Final verification + independent review + PR

- [ ] **Step 1: Full sweep**
```bash
sh conformance/privacy-ready.sh --selftest
sh conformance/privacy-ready.sh   # kit -> N/A
dash -n conformance/privacy-ready.sh && echo dash-clean
sh conformance/check-links.sh
sh conformance/doc-budget.sh
sh conformance/verify.sh | tail -3
```
Expected: selftest OK; kit N/A; dash-clean; links OK; **doc-budget core-3 900/900**; `verify.sh` RESULT: OK.

- [ ] **Step 2: Independent review (security-owner lens).** Focus: (a) trigger correctness — Confidential/Restricted real value triggers; Public/Internal/placeholder/none → N/A (not over-broad, not COPPA-over-rotating); (b) coupling both directions (declared-sensitive-without-review → FAIL; filled → OK; placeholder → FAIL); (c) the `+0` DoR fold genuinely kept core-3 at 900; (d) honesty wording (recorded ≠ lawful/compliant); (e) the data-governance doc frames COPPA as one applicability, not a mandate; (f) PROCESS/STANDARDS untouched.

- [ ] **Step 3: Address findings, then PR**
```bash
git push -u origin feature/secpriv-sp3
gh pr create --title "feat(security): SP-3 — data classification + DPIA-lite privacy review" --body "<summary + conditional-trigger + +0-fold + honesty + the BATCHED Task-6 control-plane snippet (SP-2 + SP-3 smokes) + 2.57.0 arc-close note + merge command>"
```
Report the PR number + `gh pr merge <n> --squash --admin --delete-branch`. **Do not self-merge.**

---

## Self-review (plan author)
- **Spec coverage (§3 SP-3):** classification scheme → Tasks 3/4; PRIVACY-REVIEW template → Task 1; DoR flag (mirrors threat-model) → Task 4 Step 3; privacy-ready.sh conditional three-state + selftest → Task 2; data-governance.md → Task 3; RUNBOOK `Data handling:` → Task 4 Step 2; verify/registry/audit → Task 5; CI smoke (batched) → Task 6. Honesty + COPPA-as-applicability → Tasks 2/3. **No gaps.**
- **Placeholder scan:** the `[…]` tokens are intentional template placeholders the checks grep for; the `[Public / Internal / Confidential / Restricted]` and lawful-basis placeholders are exactly what the trigger/coupling logic keys on. No banned patterns.
- **Consistency:** the trigger key (`Data classification:` + Confidential/Restricted), the review file (`PRIVACY-REVIEW.md`), the lawful-basis record, and the placeholder tokens are identical across Tasks 1/2/4. The DoR fold is one-line-for-one-line (`+0`). CI step names colon-free (Task 6).
