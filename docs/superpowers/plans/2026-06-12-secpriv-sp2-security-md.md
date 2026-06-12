# SP-2 — SECURITY.md / Vulnerability-Disclosure Policy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every governed project ships a `SECURITY.md` (coordinated-disclosure policy + a real security contact). Adds `templates/SECURITY-TEMPLATE.md`, an `incept.sh` scaffold, a `conformance/security-policy.sh` presence/non-placeholder check, the kit's **own** dogfooded `SECURITY.md`, and a one-line DoD contract in `CLAUDE.md`.

**Architecture:** The readiness-check family pattern (mirror `conformance/observability-ready.sh`): a conditional, three-state, fail-closed check + `--selftest` with mktemp fixtures. **Trigger = `CLAUDE.md` present** (a real governed repo) → `SECURITY.md` is required-and-filled; a bare scratch dir (no `CLAUDE.md`) is N/A. The kit has a `CLAUDE.md`, so it dogfoods — ships its own `SECURITY.md` (GitHub private vulnerability reporting, anonymization-safe) and the check **verifies** it.

**Tech Stack:** `sh` (dash-clean), Markdown. Spec: `docs/superpowers/specs/2026-06-12-security-privacy-completeness-arc-design.md` §3 SP-2. Branch: `feature/secpriv-sp2`. **Doc-budget:** PROCESS is at the cap (470/470) — **SP-2 must not touch PROCESS/STANDARDS**; the one contract line goes in `CLAUDE.md` (111/120, has room).

---

## Conventions
- `#!/bin/sh`, `set -eu`, dash-clean. Colon-adjacent record line (SNP-1): `**Security contact:** <value>` — grep matches a FILLED value.
- `--selftest` mktemp fixtures left in place (7e guard). Coupling-test BOTH directions (fresh template → FAIL, filled → OK).
- **No YAML colons in any CI step name** (the #80 incident) — the CI smoke step name is colon-free.
- Commit per task (Conventional Commits).

---

## File Structure
- **Create** `templates/SECURITY-TEMPLATE.md` — the disclosure-policy template (with a `[security-contact]` placeholder).
- **Create** `conformance/security-policy.sh` — conditional, three-state presence/non-placeholder check + `--selftest`.
- **Create** `SECURITY.md` (kit root) — the kit's own filled disclosure policy (dogfood; GitHub advisories contact).
- **Modify** `scripts/incept.sh` — scaffold `SECURITY.md` from the template at inception.
- **Modify** `CLAUDE.md` — one DoD/Security line naming the SECURITY.md requirement (budget-safe; CLAUDE.md has room).
- **Modify** `conformance/verify.sh` — a `check doc security-policy …` row.
- **Modify** `conformance/README.md` + `conformance/audit-evidence-checklist.md` — registry + audit rows.
- **Hand-apply (control-plane, Bradley):** kit-CI `security-policy.sh --selftest` smoke step.

---

## Task 1: `templates/SECURITY-TEMPLATE.md`

**Files:** Create `templates/SECURITY-TEMPLATE.md`

- [ ] **Step 1: Write the template**

```markdown
# Security Policy

> **Template.** Copy to your project root as `SECURITY.md` (Inception scaffolds it).
> Replace the `[security-contact]` placeholder with a real reporting channel before shipping.
> Delete this blockquote once filled.

## Reporting a vulnerability

**Security contact:** [security-contact]

Please report security vulnerabilities **privately** — do not open a public issue. Preferred
channels (use whichever your org runs):
- **GitHub private vulnerability reporting** (repo → Security → "Report a vulnerability"), or
- a dedicated security mailbox (e.g. `security@your-org.example`), or
- a `.well-known/security.txt` contact for the deployed service.

## What to expect
- **Acknowledgement:** within **2 business days**.
- **Triage + severity:** within **5 business days** (we use the §-severity model in `RUNBOOK.md`).
- **Fix / mitigation:** prioritized by severity; coordinated-disclosure timeline agreed with the reporter.
- **Credit:** we credit reporters who follow coordinated disclosure (opt-out respected).

## Supported versions
| Version | Supported |
|---------|-----------|
| latest `main` / current release | ✅ |
| older releases | best-effort / per support policy |

## Scope
In scope: this project's own code + deployed surfaces. Out of scope: third-party dependencies
(report upstream; we track via `gate-dep-scan`) and findings requiring privileged local access.
```

- [ ] **Step 2: Links check + commit**

Run: `sh conformance/check-links.sh 2>&1 | tail -1`
Expected: links OK.
```bash
git add templates/SECURITY-TEMPLATE.md
git commit -m "feat(templates): SECURITY-TEMPLATE — coordinated-disclosure policy"
```

---

## Task 2: `conformance/security-policy.sh` + `--selftest` (TDD core)

**Files:** Create `conformance/security-policy.sh`

- [ ] **Step 1: Write the check (its `--selftest` is the test harness)**

```sh
#!/bin/sh
# security-policy.sh — conditional, fail-closed SECURITY.md presence/disclosure check (SP-2).
#
# Trigger: a governed repo (a CLAUDE.md is present) MUST ship a SECURITY.md with a real
# security contact (not the [security-contact] template placeholder). A bare scratch dir
# (no CLAUDE.md) is N/A — nothing to disclose against. Mirrors observability-ready.sh.
#
# SCOPE: a green run proves a disclosure policy is RECORDED with a real contact — NOT that the
# process actually works (acknowledgement SLAs met, triage happens). Those are operator rows.
#
# Usage:
#   sh conformance/security-policy.sh [project-dir]   (default: .)
#   sh conformance/security-policy.sh --selftest
set -eu

check_dir() {
  dir="$1"
  if [ ! -f "$dir/CLAUDE.md" ]; then
    echo "N/A: $dir is not a governed repo (no CLAUDE.md) — skipping (no disclosure policy required)"
    return 0
  fi
  sec="$dir/SECURITY.md"
  if [ ! -f "$sec" ]; then
    echo "FAIL: $dir has a CLAUDE.md but no SECURITY.md — ship a coordinated-disclosure policy (templates/SECURITY-TEMPLATE.md)"
    return 1
  fi
  # Record string stays in sync with templates/SECURITY-TEMPLATE.md.
  if ! grep -Eiq 'security contact:' "$sec"; then
    echo "FAIL: SECURITY.md has no 'Security contact:' line — name a real reporting channel"
    return 1
  fi
  if grep -Fiq 'security contact:** [security-contact]' "$sec" || grep -Fiq '[security-contact]' "$sec"; then
    echo "FAIL: SECURITY.md still holds the [security-contact] placeholder — record a real contact"
    return 1
  fi
  echo "security-policy: OK — SECURITY.md present with a real security contact. NOTE: this does NOT verify the disclosure process works (SLAs met, triage happens) — those are operator rows."
  return 0
}

selftest() {
  st_fail=0
  base=$(mktemp -d)

  d1="$base/na"; mkdir -p "$d1"; printf '# scratch\n' > "$d1/README.md"
  if check_dir "$d1" >/dev/null 2>&1; then echo "selftest PASS: no CLAUDE.md -> N/A"; else echo "selftest FAIL: should be N/A"; st_fail=1; fi

  d2="$base/missing"; mkdir -p "$d2"; printf '# CLAUDE\n' > "$d2/CLAUDE.md"
  if check_dir "$d2" >/dev/null 2>&1; then echo "selftest FAIL: CLAUDE.md without SECURITY.md should FAIL"; st_fail=1; else echo "selftest PASS: governed + no SECURITY.md -> FAIL"; fi

  d3="$base/placeholder"; mkdir -p "$d3"; printf '# CLAUDE\n' > "$d3/CLAUDE.md"
  printf '# Security Policy\n\n**Security contact:** [security-contact]\n' > "$d3/SECURITY.md"
  if check_dir "$d3" >/dev/null 2>&1; then echo "selftest FAIL: [security-contact] placeholder should FAIL"; st_fail=1; else echo "selftest PASS: placeholder -> FAIL"; fi

  d4="$base/ok"; mkdir -p "$d4"; printf '# CLAUDE\n' > "$d4/CLAUDE.md"
  printf '# Security Policy\n\n**Security contact:** GitHub private vulnerability reporting\n' > "$d4/SECURITY.md"
  if check_dir "$d4" >/dev/null 2>&1; then echo "selftest PASS: filled contact -> OK"; else echo "selftest FAIL: filled should pass"; st_fail=1; fi

  if [ "$st_fail" -ne 0 ]; then echo "security-policy --selftest: FAIL" >&2; return 1; fi
  echo "security-policy --selftest: OK (na/missing/placeholder/ok all behaved; fixtures left in $base)"
  return 0
}

case "${1:-}" in
  --selftest) selftest ;;
  *)          check_dir "${1:-.}" ;;
esac
exit $?
```

- [ ] **Step 2: Run the selftest**

Run: `sh conformance/security-policy.sh --selftest`
Expected: four `selftest PASS` lines + `security-policy --selftest: OK`.

- [ ] **Step 3: Real-repo run is FAIL (kit has CLAUDE.md, no SECURITY.md yet) — proves the trigger**

Run: `sh conformance/security-policy.sh; echo "exit=$?"`
Expected: `FAIL: . has a CLAUDE.md but no SECURITY.md …` then `exit=1`. (Task 3 ships the kit's SECURITY.md → this flips to OK.)

- [ ] **Step 4: dash-clean + commit**

Run: `dash -n conformance/security-policy.sh && echo dash-clean`
```bash
git add conformance/security-policy.sh
git commit -m "feat(conformance): security-policy.sh — SECURITY.md presence/disclosure check"
```

---

## Task 3: The kit's own `SECURITY.md` (dogfood)

**Files:** Create `SECURITY.md` (repo root)

- [ ] **Step 1: Write the kit's filled disclosure policy** (anonymization-safe contact — GitHub advisories, no personal email)

```markdown
# Security Policy

## Reporting a vulnerability

**Security contact:** GitHub private vulnerability reporting — this repo → **Security** → **Report a vulnerability**.

Please report privately; do not open a public issue for a suspected vulnerability.

## What to expect
- **Acknowledgement:** within 2 business days.
- **Triage + severity:** within 5 business days (severity model per `DEVELOPMENT-PROCESS.md` incident guidance).
- **Fix / mitigation:** prioritized by severity; coordinated-disclosure timeline agreed with the reporter.
- **Credit:** reporters who follow coordinated disclosure are credited (opt-out respected).

## Supported versions
The current `main` and the latest tagged release are supported. Older releases are best-effort.

## Scope
In scope: the kit's own scripts, conformance checks, templates, and docs. Out of scope: third-party
dependencies (report upstream) and the inert reference pipelines under `profiles/` (they are copy-and-adapt
templates, not a deployed surface).
```

- [ ] **Step 2: The check now passes on the kit**

Run: `sh conformance/security-policy.sh; echo "exit=$?"`
Expected: `security-policy: OK …` then `exit=0`.

- [ ] **Step 3: Links + commit**

Run: `sh conformance/check-links.sh 2>&1 | tail -1`
```bash
git add SECURITY.md
git commit -m "docs(security): the kit dogfoods its own SECURITY.md (GitHub advisories)"
```

---

## Task 4: `incept.sh` scaffold + `CLAUDE.md` DoD line

**Files:** Modify `scripts/incept.sh`, `CLAUDE.md`

- [ ] **Step 1: Scaffold SECURITY.md at inception**

In `scripts/incept.sh`, in the "RUNBOOK / BACKLOG / ADR-000" section (after the RUNBOOK line ~124), add:
```sh
[ -f SECURITY.md ] || cp templates/SECURITY-TEMPLATE.md SECURITY.md
```
(SECURITY.md has no `[Project Name]` token to substitute; a plain copy is right — the adopter fills the `[security-contact]`.)

- [ ] **Step 2: Add the DoD/Security contract line to CLAUDE.md**

In `CLAUDE.md`, in the **Security (non-negotiable)** section, add a bullet after the Secrets line:
```markdown
- **Disclosure policy:** ship a `SECURITY.md` (coordinated-disclosure process + a real security contact); verified by `conformance/security-policy.sh`.
```

- [ ] **Step 3: Budget + links**

Run: `sh conformance/doc-budget.sh && sh conformance/check-links.sh 2>&1 | tail -1`
Expected: `PASS: CLAUDE.md 112/120` (or below), core docs within budget; links OK. (CLAUDE.md has headroom; PROCESS untouched.)

- [ ] **Step 4: Commit**

```bash
git add scripts/incept.sh CLAUDE.md
git commit -m "feat(incept): scaffold SECURITY.md + name the disclosure-policy DoD"
```

---

## Task 5: Wire into verify.sh + registry/audit rows

**Files:** Modify `conformance/verify.sh`, `conformance/README.md`, `conformance/audit-evidence-checklist.md`

- [ ] **Step 1: verify.sh doc-check row**

In `conformance/verify.sh`, after the `check doc agentops-ready …` row, add:
```sh
check doc     security-policy sh conformance/security-policy.sh
```

- [ ] **Step 2: Run the aggregate**

Run: `sh conformance/verify.sh 2>&1 | grep -E "security-policy|RESULT"`
Expected: `[doc] security-policy PASS` (kit now has a filled SECURITY.md) and `RESULT: OK`.

- [ ] **Step 3: Registry + audit rows**

In `conformance/README.md`, add `security-policy.sh` to the table (mirror `observability-ready.sh` row format). In `conformance/audit-evidence-checklist.md`, add:
```markdown
| SECURITY.md present + real contact | `security-policy.sh` | Auto | repo SECURITY.md |
| Disclosure process actually works (SLAs, triage) | operator evidence | Manual | advisory response log |
```

- [ ] **Step 4: Links + commit**

Run: `sh conformance/check-links.sh 2>&1 | tail -1 && sh conformance/verify.sh | tail -3`
```bash
git add conformance/verify.sh conformance/README.md conformance/audit-evidence-checklist.md
git commit -m "feat(conformance): wire security-policy into verify.sh + registry/audit rows"
```

---

## Task 6: Prepare the control-plane CI smoke (hand-apply for Bradley)

**Files:** Hand-apply (Bradley): `.github/workflows/ci.yml`

- [ ] **Step 1: Produce the exact step** (colon-free name — the #80 lesson):
```yaml
      - name: Security-policy self-test (SECURITY.md disclosure record)
        run: sh conformance/security-policy.sh --selftest
```
- [ ] **Step 2: Surface it in the PR body** (clean block, no `#` comments), with the `KIT_GUARD_SELFEDIT=1 git add … ; git commit` apply commands, and a note to **`gh run watch` the resulting run to confirm green** (the CI-incident lesson). *(No repo change in this task.)*

---

## Task 7: Final verification + independent review + PR

- [ ] **Step 1: Full sweep**
```bash
sh conformance/security-policy.sh --selftest
sh conformance/security-policy.sh   # kit itself -> OK now
dash -n conformance/security-policy.sh && echo dash-clean
sh conformance/check-links.sh
sh conformance/doc-budget.sh
sh conformance/verify.sh | tail -3
```
Expected: selftest OK; kit run OK; dash-clean; links OK; doc-budget OK (CLAUDE.md ≤120, PROCESS untouched at 470); `verify.sh` RESULT: OK.

- [ ] **Step 2: Independent review (security-owner lens).** Focus: (a) trigger correctness (CLAUDE.md present → required; absent → N/A — not over/under-broad); (b) coupling test both directions (fresh template → FAIL, filled → OK) — verify by pointing the check at `templates/SECURITY-TEMPLATE.md`-derived fixtures; (c) the placeholder grep is robust (catches `[security-contact]` even reformatted); (d) honesty wording (recorded ≠ process-works); (e) the kit's own SECURITY.md is anonymization-safe (no personal email); (f) no PROCESS/STANDARDS budget touched.

- [ ] **Step 3: Address findings, then PR**
```bash
git push -u origin feature/secpriv-sp2
gh pr create --title "feat(security): SP-2 — SECURITY.md / disclosure policy" --body "<summary + the CLAUDE.md-trigger dogfood + honesty + Task-6 control-plane snippet (colon-free) + merge command>"
```
Report the PR number + `gh pr merge <n> --squash --admin --delete-branch`. **Do not self-merge.**

---

## Self-review (plan author)
- **Spec coverage (§3 SP-2):** SECURITY-TEMPLATE → Task 1; incept wiring → Task 4; security-policy.sh three-state + selftest → Task 2; verify/README/audit → Task 5; CI smoke → Task 6. Plus the kit dogfood (Task 3) and the DoD contract (Task 4). **No gaps.**
- **Placeholder scan:** `[security-contact]` is the intentional template placeholder the check greps for (like observability's `[target]`); not a plan gap. No banned patterns.
- **Consistency:** the trigger (`CLAUDE.md`), the record key (`Security contact:`), and the placeholder token (`[security-contact]`) are identical across Tasks 1/2/3/5. CI step name is colon-free (Task 6).
