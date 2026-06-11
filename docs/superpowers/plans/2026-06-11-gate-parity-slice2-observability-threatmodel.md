# Gate Parity Slice 2 — Observability/SLO + Threat-model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the observability/SLO gate and the threat-model gate the kit's signature *declared-artifact + (where honest) executable-conformance* treatment — closing the last two of the three "named-in-prose-but-no-artifact" gaps (Slice 1 closed eval).

**Architecture:** Two independent sub-features off one approved arc spec. **B. Observability/SLO** mirrors the `resilience-ready` family exactly: a deploy-surface-triggered, fail-closed `observability-ready.sh` (N/A · OK · FAIL + `--selftest`) that asserts the RUNBOOK *records* SLOs + telemetry, paired with an `observability-readiness.md` Auto-vs-Manual checklist. **C. Threat-model** mirrors the `A11Y-SIGNOFF` template: a `THREAT-MODEL-TEMPLATE.md` (STRIDE/LINDDUN-lite, security-owner sign-off) wired into the §7 security gate — **no script** (threat modeling is human-ratified; presence ≠ quality, "sensitive" is not honestly auto-detectable).

**Tech Stack:** POSIX sh (dash-clean; `set -eu`; no `local`/`[[`/`==`), Markdown templates in the kit's guidance-blockquote style, GitHub Actions YAML (CI selftest step via control-plane `cp` — Bradley applies).

**Release:** `VERSION` → 2.47.0; MINOR (one conditional check + two templates; no new *universal* gate). Closes the gate-parity arc.

**Honesty invariant (whole slice):** each new check verifies the discipline is **declared / recorded**, never that it **works** — the signals actually emit in prod, alerts actually fire, the SLO/error-budget is actually tracked, the threat model is *good*. Those stay **Manual** operator/security-owner rows. No green check overclaims — same "necessary, not sufficient" framing as `resilience-ready`.

**Doc-budget (hard constraint):** core-3 headroom at plan time — `CLAUDE.md` 111/120, `DEVELOPMENT-PROCESS.md` 464/470, `DEVELOPMENT-STANDARDS.md` 309/320. **Prefer append-to-existing-line edits (+0 lines).** `doc-budget.sh` must stay green; verify after every core-doc edit.

**Governance:** feature branch `feature/gate-parity-observability-threatmodel` → PR → **Bradley merges** (`gh pr merge <n> --squash --admin --delete-branch`; agent never self-merges). PROCESS/STANDARDS edits are governing-doc changes → **security-owner lens** at review (esp. the threat-model §7 wiring). The `ci.yml` selftest step lands via the control-plane `cp` (Bradley applies; the agent cannot edit `.github/workflows/`). Kit stays generic/anonymized ([[kit-anonymization]]).

---

## File Structure

**B. Observability/SLO**
- Create: `conformance/observability-ready.sh` — conditional fail-closed check (mirror of `resilience-ready.sh`).
- Create: `conformance/observability-readiness.md` — Auto-vs-Manual checklist (mirror of `resilience-readiness.md`).
- Modify: `templates/RUNBOOK-TEMPLATE.md:63` area — add the SLO + telemetry record bullet (terse, comment-free, mirrors the resilience-verification bullet).
- Modify: `conformance/verify.sh:59` area — add `check doc observability-ready` row.
- Modify: `conformance/README.md` — add the `observability-ready.sh` table row + name it in the documentation/evidence bullet.
- Modify: `conformance/audit-evidence-checklist.md:43` area — add the observability evidence row.
- Modify: `DEVELOPMENT-STANDARDS.md` Factor 14 / §202 telemetry-depth line — append the readiness pointer (+0).
- Modify (control-plane `cp`, Bradley applies): `.github/workflows/ci.yml` — add `observability-ready.sh --selftest` step after the eval-ready step.

**C. Threat-model**
- Create: `templates/THREAT-MODEL-TEMPLATE.md` — STRIDE/LINDDUN-lite, security-owner sign-off (mirror of `A11Y-SIGNOFF-TEMPLATE.md` style).
- Modify: `DEVELOPMENT-PROCESS.md:107` and `:178` — append the template pointer to the existing threat-model gate rows (+0).
- Modify: `CLAUDE.md:17` (templates list) and `:73` (DoR threat-model flag) — add `THREAT-MODEL` + template pointer (+0 appends).
- Modify: `DEVELOPMENT-STANDARDS.md` §2 security section — one-line threat-model template pointer (append to an existing line where possible).

**Release**
- Modify: `VERSION` → `2.47.0`; `CHANGELOG.md` (new entry); `README.md` badge.

---

## Task 1: Observability — RUNBOOK record line

**Files:**
- Modify: `templates/RUNBOOK-TEMPLATE.md` (after the resilience-verification bullet, currently line 63)

- [ ] **Step 1: Add the SLO + telemetry record bullet**

In `templates/RUNBOOK-TEMPLATE.md` §8 Monitoring & alerting, immediately after the existing line:

```
- **Resilience verification** *(deployable services — see `docs/operations/resilience-verification.md`)*: Load/soak tested: [date] · Fault-injection drill: [date]
```

add this new line (terse, **no HTML helper comments** — the Slice 1 L1 lesson: helper prose must never contain the placeholder token the detector greps for):

```
- **Observability** *(deployable services — Factor 14 / §9; verified by `conformance/observability-ready.sh`)*: SLOs: [target] · Telemetry wired: [signals]
```

- [ ] **Step 2: Verify doc-budget unaffected and links resolve**

Run: `sh conformance/doc-budget.sh && sh conformance/check-links.sh`
Expected: both print OK (RUNBOOK-TEMPLATE.md is not a budget-capped core doc, but confirm no regression).

- [ ] **Step 3: Commit**

```bash
git add templates/RUNBOOK-TEMPLATE.md
git commit -m "feat(templates): RUNBOOK §8 records SLOs + telemetry (observability readiness, gate parity Slice 2)"
```

---

## Task 2: Observability — `observability-ready.sh` (conditional, fail-closed)

**Files:**
- Create: `conformance/observability-ready.sh`

This is a near-exact mirror of `conformance/resilience-ready.sh`: same deploy-surface trigger (`wf_is_deploy` + Dockerfile), same N/A · OK · FAIL · `--selftest` shape, same "fixtures left in place (no `rm -rf`)" 7e-guard discipline. Only the grepped record phrases differ (`SLOs:` / `Telemetry wired:` with `[target]` / `[signals]` placeholders).

- [ ] **Step 1: Write the script**

```sh
#!/bin/sh
# observability-ready.sh — conditional, fail-closed observability-record check (gate parity, Slice 2).
#
# Companion to conformance/observability-readiness.md (the Observability/SLO readiness;
# DEVELOPMENT-PROCESS.md §7). For a project with a DEPLOY SURFACE it asserts the observability
# posture is RECORDED: the RUNBOOK §8 has an "SLOs:" target and a "Telemetry wired:" signal set
# (not the template [target]/[signals] placeholders). Projects with no deploy surface are N/A
# (skip-pass) — a library/CLI has no running service to set SLOs on or emit telemetry from.
#
# SCOPE — a green run proves the posture was RECORDED, NOT that the system is actually observable:
# that the signals actually emit in prod, the alerts actually fire, or the SLO/error-budget is
# actually tracked. Those are Manual rows in observability-readiness.md (operator evidence). A
# green run is necessary, not sufficient.
#
# Usage:
#   sh conformance/observability-ready.sh [project-dir]   (default: .)
#   sh conformance/observability-ready.sh --selftest
#
# Run at the Observability readiness gate (DEVELOPMENT-PROCESS.md §7); also self-tested in kit CI.
set -eu

# Does $1 (a workflow file) indicate a deploy surface? (Same structural signals as
# resilience-ready.sh: a GitHub `environment:` key or a deploy-ish job key.)
wf_is_deploy() {
  _wf="$1"
  if grep -Eq '^[[:space:]]*environment:' "$_wf"; then return 0; fi
  if grep -Eq '^[[:space:]]+deploy[A-Za-z0-9_-]*:[[:space:]]*$' "$_wf"; then return 0; fi
  return 1
}

check_dir() {
  dir="$1"
  fail=0

  deployable=0
  if [ -f "$dir/Dockerfile" ]; then deployable=1; fi
  if [ "$deployable" -eq 0 ] && [ -d "$dir/.github/workflows" ]; then
    for wf in "$dir"/.github/workflows/*.yml "$dir"/.github/workflows/*.yaml; do
      [ -f "$wf" ] || continue
      if wf_is_deploy "$wf"; then deployable=1; break; fi
    done
  fi

  if [ "$deployable" -eq 0 ]; then
    echo "N/A: $dir has no deploy surface (no Dockerfile / deploy workflow) — skipping (no running service to set SLOs on or emit telemetry from)"
    return 0
  fi

  rb="$dir/RUNBOOK.md"
  if [ ! -f "$rb" ]; then
    echo "FAIL: $dir is deployable but has no RUNBOOK.md (need §8 observability records) — see conformance/observability-readiness.md"
    return 1
  fi

  # Record strings below must stay in sync with templates/RUNBOOK-TEMPLATE.md §8.
  if ! grep -Eiq 'slos:' "$rb"; then
    echo "FAIL: RUNBOOK has no 'SLOs:' record — declare the service-level objective (availability/latency/error budget)"
    fail=1
  elif grep -Fiq 'slos: [target]' "$rb"; then
    echo "FAIL: 'SLOs:' still holds the [target] placeholder — record a real SLO target"
    fail=1
  fi
  if ! grep -Eiq 'telemetry wired:' "$rb"; then
    echo "FAIL: RUNBOOK has no 'Telemetry wired:' record — locate the metrics + traces + health signals (Factor 14)"
    fail=1
  elif grep -Fiq 'telemetry wired: [signals]' "$rb"; then
    echo "FAIL: 'Telemetry wired:' still holds the [signals] placeholder — record the real signal set"
    fail=1
  fi

  if [ "$fail" -ne 0 ]; then return 1; fi
  echo "observability-ready: OK — observability posture is RECORDED (SLOs declared, telemetry located). NOTE: this does NOT verify the system is actually observable (signals emit in prod, alerts fire, SLO/error-budget tracked) — those are Manual rows in observability-readiness.md requiring operator evidence."
  return 0
}

# Build mktemp fixtures and assert each outcome. Fixtures LEFT in place (no rm -rf; 7e guard).
selftest() {
  st_fail=0
  base=$(mktemp -d)

  d1="$base/na"; mkdir -p "$d1"
  if check_dir "$d1" >/dev/null 2>&1; then
    echo "selftest PASS: empty -> N/A"
  else
    echo "selftest FAIL: empty should be N/A"; st_fail=1
  fi

  d2="$base/stateless"; mkdir -p "$d2"; printf '# a stateless CLI tool\n' > "$d2/README.md"
  if check_dir "$d2" >/dev/null 2>&1; then
    echo "selftest PASS: no-deploy-surface -> N/A (not over-triggered)"
  else
    echo "selftest FAIL: no-deploy-surface should be N/A"; st_fail=1
  fi

  d3="$base/ok"; mkdir -p "$d3"
  printf 'FROM scratch\n' > "$d3/Dockerfile"
  printf '# RUNBOOK\n\n## Monitoring & alerting\n- Observability: SLOs: 99.9%% avail, p95 < 200ms · Telemetry wired: Prometheus + OTel traces + /healthz\n' > "$d3/RUNBOOK.md"
  if check_dir "$d3" >/dev/null 2>&1; then
    echo "selftest PASS: complete deployable -> OK"
  else
    echo "selftest FAIL: complete deployable should pass"; st_fail=1
  fi

  d4="$base/placeholder"; mkdir -p "$d4"
  printf 'FROM scratch\n' > "$d4/Dockerfile"
  printf '# RUNBOOK\n\n## Monitoring & alerting\n- Observability: SLOs: [target] · Telemetry wired: Prometheus + OTel\n' > "$d4/RUNBOOK.md"
  if check_dir "$d4" >/dev/null 2>&1; then
    echo "selftest FAIL: [target] placeholder should FAIL"; st_fail=1
  else
    echo "selftest PASS: SLOs [target] placeholder -> FAIL as expected"
  fi

  d5="$base/missing"; mkdir -p "$d5"
  printf 'FROM scratch\n' > "$d5/Dockerfile"
  printf '# RUNBOOK\n\n## Monitoring & alerting\n- Observability: SLOs: 99.9%% avail\n' > "$d5/RUNBOOK.md"
  if check_dir "$d5" >/dev/null 2>&1; then
    echo "selftest FAIL: missing telemetry record should FAIL"; st_fail=1
  else
    echo "selftest PASS: missing telemetry record -> FAIL as expected"
  fi

  if [ "$st_fail" -ne 0 ]; then
    echo "observability-ready --selftest: FAIL" >&2
    return 1
  fi
  echo "observability-ready --selftest: OK (na/no-surface/ok/placeholder/missing all behaved; fixtures left in $base)"
  return 0
}

case "${1:-}" in
  --selftest) selftest ;;
  *)          check_dir "${1:-.}" ;;
esac
exit $?
```

- [ ] **Step 2: Syntax + selftest**

Run: `dash -n conformance/observability-ready.sh && sh conformance/observability-ready.sh --selftest`
Expected: dash clean; 5/5 selftest PASS lines + `observability-ready --selftest: OK`.

> **Note on the `%%` in fixtures:** the `printf` format strings use `99.9%%` so `printf` emits a literal `%`. Confirm the fixture RUNBOOK shows `99.9%` (not `99.9%%`) — a stray single `%` would make `printf` swallow the next char.

- [ ] **Step 3: Kit-root live run must be N/A**

Run: `sh conformance/observability-ready.sh; echo "exit=$?"`
Expected: `N/A: . has no deploy surface ...` and `exit=0` (the kit is a framework — no Dockerfile, no deploy workflow at root).

- [ ] **Step 4: Coupling check — fresh RUNBOOK template reads as placeholder → FAIL**

Run:
```bash
t=$(mktemp -d); cp templates/RUNBOOK-TEMPLATE.md "$t/RUNBOOK.md"; printf 'FROM scratch\n' > "$t/Dockerfile"
sh conformance/observability-ready.sh "$t"; echo "exit=$?"
```
Expected: FAIL on the `[target]` placeholder, `exit=1` (no false PASS on a fresh template).

- [ ] **Step 5: Commit**

```bash
git add conformance/observability-ready.sh
git commit -m "feat(conformance): observability-ready.sh — conditional observability-record check (deploy-surface trigger; SLOs + telemetry recorded)"
```

---

## Task 3: Observability — `observability-readiness.md` checklist

**Files:**
- Create: `conformance/observability-readiness.md`

Mirror `resilience-readiness.md`'s shape: a header paragraph, the "What the Auto rows prove — and don't" honesty blockquote, a How-to-use paragraph, a blank checklist, and a worked example. **Auto** rows = what `observability-ready.sh` checks (SLOs declared, telemetry recorded); **Manual** rows = the operator's prod evidence (signals emit, alerts fire, error-budget tracked, dashboards exist).

- [ ] **Step 1: Write the checklist**

```markdown
# Conformance Check — Observability Readiness

Proves a service is **observable in production**: SLOs are declared, telemetry (metrics + distributed traces + health signals — Factor 14) is wired, alerts fire on SLO breach, and the error budget is tracked. **Checklist-type**, run at the **Observability readiness gate** (`DEVELOPMENT-PROCESS.md` §7) and as **recurring maintenance** (§15). **Conditional:** non-deployable projects (library, CLI, batch) mark the whole check **N/A — no running service to set SLOs on or emit telemetry from**. Verifies the principles asserted in `DEVELOPMENT-STANDARDS.md` Factor 14 (Telemetry) and §9 (SLOs / error budgets). Aligns with Google SRE (SLOs, error budgets) and the OpenTelemetry observability model.

> **What the Auto rows prove — and don't.** `observability-ready.sh` confirms the posture is *recorded* (an SLO target and a telemetry signal set in RUNBOOK §8). It does **not** verify the system is *actually* observable — that the signals emit in prod, the alerts fire on breach, or the error budget is tracked over time. Those are the **Manual** rows, signed off by the operator with evidence. **A green script is necessary, not sufficient.**

## How to use
Copy this file into your project (or your reliability record). For each item: mark **Applies? (Y / N+reason)** and give **Evidence**. Items tagged *(documented)* are auto-checkable via `sh conformance/observability-ready.sh`; items tagged *(verified)* require the operator's evidence from the running system. The reviewer signs off only when every applicable item has evidence.

## Checklist (blank)

| # | Item | Applies? | Evidence (where/how) | Check |
|---|------|----------|----------------------|-------|
| 1 | SLOs declared — availability / latency / error budget (RUNBOOK §8) *(documented)* | | | **Auto:** `observability-ready.sh` |
| 2 | Telemetry wired — metrics + traces + health recorded (RUNBOOK §8) *(documented)* | | | **Auto:** `observability-ready.sh` |
| 3 | Metrics actually emit in prod — dashboard shows live signal *(verified)* | | | Manual |
| 4 | Distributed traces actually emit — a real request trace is viewable *(verified)* | | | Manual |
| 5 | Health/readiness endpoint live — probe returns real status *(verified)* | | | Manual |
| 6 | Alert fires on SLO breach — tested with a synthetic breach *(verified)* | | | Manual |
| 7 | Error budget tracked over time — burn-rate visible, drives decisions *(verified)* | | | Manual |

## Worked example — a deployable HTTP service

| # | Item | Applies? | Evidence | Check |
|---|------|----------|----------|-------|
| 1 | SLOs declared *(documented)* | Y | RUNBOOK §8 "SLOs: 99.9% avail, p95 < 200ms, error budget 0.1%" | Auto ✅ |
| 2 | Telemetry wired *(documented)* | Y | RUNBOOK §8 "Telemetry wired: Prometheus + OTel traces + /healthz" | Auto ✅ |
| 3 | Metrics emit *(verified)* | Y | Grafana dashboard shows live RPS/latency/error series | Manual ✅ |
| 4 | Traces emit *(verified)* | Y | a sampled request trace viewable end-to-end (Tempo/Jaeger) | Manual ✅ |
| 5 | Health endpoint live *(verified)* | Y | `/healthz` returns 200 + dependency status; probe wired | Manual ✅ |
| 6 | Alert fires on breach *(verified)* | Y | injected latency > SLO → page fired to on-call (alert log) | Manual ✅ |
| 7 | Error budget tracked *(verified)* | Y | burn-rate panel + monthly budget review drives release pace | Manual ✅ |

> A library or CLI marks the whole check **N/A — no running service to set SLOs on or emit telemetry from**; `observability-ready.sh` skip-passes such a project automatically.
```

- [ ] **Step 2: Links resolve**

Run: `sh conformance/check-links.sh`
Expected: OK.

- [ ] **Step 3: Commit**

```bash
git add conformance/observability-readiness.md
git commit -m "docs(conformance): observability-readiness checklist (Auto: SLOs + telemetry declared; Manual: emit/alert/budget verified)"
```

---

## Task 4: Observability — wiring (verify.sh · README · audit-evidence · STANDARDS)

**Files:**
- Modify: `conformance/verify.sh` (after the `eval-ready` doc row, line 59)
- Modify: `conformance/README.md` (table row + documentation/evidence bullet)
- Modify: `conformance/audit-evidence-checklist.md` (after the resilience row, line 43)
- Modify: `DEVELOPMENT-STANDARDS.md` (Factor 14 telemetry-depth line, ~202)

- [ ] **Step 1: verify.sh doc-check row**

In `conformance/verify.sh`, after:
```
check doc     eval-ready       sh conformance/eval-ready.sh
```
add:
```
check doc     observability-ready sh conformance/observability-ready.sh
```

- [ ] **Step 2: conformance/README.md — table row + evidence bullet**

Add a table row mirroring the `resilience-ready.sh` row (currently line 36):
```
| `observability-ready.sh` | script | `DEVELOPMENT-STANDARDS.md` Factor 14 / §9 — recorded observability posture (RUNBOOK §8 SLOs + telemetry); pairs with the checklist | Review / CI (conditional on a deploy surface) |
```
And add `observability-ready.sh` to the names listed in the documentation/evidence bullet (line 20, the `deployable-ready.sh, dr-ready.sh, resilience-ready.sh` list) and the conditional-checks N/A blockquote (line 74) if it enumerates skip-pass scripts — observability skip-passes cleanly like resilience (a non-deployed project legitimately has no SLOs).

- [ ] **Step 3: audit-evidence-checklist.md — evidence row**

After the resilience row (line 43), add:
```
| Observability · SLOs + telemetry | A1.2 / A.8.16, A.8.15 / PW.6 | observability records (RUNBOOK §8 SLOs + telemetry) + live dashboards/alerts | **Auto (conditional):** `sh conformance/observability-ready.sh` (+ Manual prod evidence) | |
```
(Match the existing column layout exactly; confirm the SOC 2 / ISO / SSDF control IDs align with the surrounding rows' style — observability maps naturally to availability monitoring CC7.2 / A.8.16 logging-and-monitoring. Use the same control-ID convention the neighboring rows use; do not invent new columns.)

- [ ] **Step 4: STANDARDS Factor 14 pointer (append, +0 lines)**

In `DEVELOPMENT-STANDARDS.md`, append a readiness pointer to the existing telemetry-depth line (~202):
```
- **Telemetry depth (Factor 14)** — observability is metrics + traces + health, extending §3 beyond logs. Readiness: `conformance/observability-readiness.md`; recorded in RUNBOOK §8.
```
(Append to the existing bullet — do NOT add a new line, to protect doc-budget.)

- [ ] **Step 5: Verify the full wiring**

Run:
```bash
sh conformance/verify.sh 2>&1 | tail -4
sh conformance/doc-budget.sh && sh conformance/check-links.sh
```
Expected: `verify.sh` RESULT: OK with the doc-check count incremented to 5; doc-budget OK; links OK.

- [ ] **Step 6: Commit**

```bash
git add conformance/verify.sh conformance/README.md conformance/audit-evidence-checklist.md DEVELOPMENT-STANDARDS.md
git commit -m "docs(conformance): wire observability readiness — verify.sh doc-check + README/audit rows + STANDARDS Factor 14 pointer"
```

---

## Task 5: Threat-model — `THREAT-MODEL-TEMPLATE.md`

**Files:**
- Create: `templates/THREAT-MODEL-TEMPLATE.md`

Guidance-blockquote style (mirror `A11Y-SIGNOFF-TEMPLATE.md`): a `> **Template.**` header that says delete-the-guidance-and-fill, then structured sections. STRIDE for security threats + a LINDDUN-lite privacy row (the kit's adopter profile is privacy-sensitive, regulated). Ends with a security-owner sign-off block (the auditable evidence for the §7 security gate and the DoR threat-model flag).

- [ ] **Step 1: Write the template**

```markdown
# Threat Model

> **Template.** Delete the guidance; fill the sections. The auditable evidence for the **§7 security gate** (`DEVELOPMENT-PROCESS.md`) and the Definition-of-Ready **threat-model flag** (`CLAUDE.md`), required for **sensitive / regulated** features. STRIDE for security threats + a LINDDUN-lite privacy lens (the kit's adopter profile handles customer + affiliate data, children's-audience content). The **security owner** signs at Review. Keep it a structured record, not prose — presence is not quality; the value is the threats you find and mitigate. Attach to the PR or store under `docs/sign-offs/` (or your security record).

## System & assets
- **Feature / story:** <link>
- **What it does (1–2 lines):** [summary]
- **Assets at risk:** [data, credentials, money, availability, safety]
- **Data classification:** [public / internal / confidential / PII / children's data] — [why]
- **Entry points / actors:** [users, agents, services, admins]

## Trust boundaries
- [boundary 1 — e.g. internet → app; what crosses it; what is validated]
- [boundary 2 — e.g. app → datastore; least-privilege creds]
- [boundary 3 — e.g. app → third-party / AI provider; what data leaves, consent]

## Threats (STRIDE) + mitigations

| STRIDE category | Threat (this system) | Likelihood × Impact | Mitigation / control | Status |
|-----------------|----------------------|---------------------|----------------------|--------|
| **S**poofing (identity) | [threat] | [L×I] | [auth, MFA, token validation] | [planned/done] |
| **T**ampering (integrity) | [threat] | [L×I] | [input validation, signing, parameterized queries] | |
| **R**epudiation (audit) | [threat] | [L×I] | [immutable audit log] | |
| **I**nformation disclosure | [threat] | [L×I] | [encryption at rest/in transit, least privilege, log redaction] | |
| **D**enial of service | [threat] | [L×I] | [rate limiting, quotas, circuit breakers] | |
| **E**levation of privilege | [threat] | [L×I] | [authz checks, least-privilege roles] | |

## Privacy (LINDDUN-lite)
- **Linkability / identifiability:** [can records be linked / re-identified? minimization?]
- **PII handling:** [what PII, consent basis, retention, right-to-erasure path]
- **Third-party / AI data flow:** [what leaves the boundary; consent; redaction] — N/A if none
- **Prompt-injection / AI abuse** *(if an AI feature)*: [untrusted-input → model guardrails, output validation] — N/A if no model

## Residual risk
- [risk accepted, why, compensating control, expiry/review date — ties to the governed-exception register if a gate is waived]

## Sign-off

| Field | Value |
|-------|-------|
| Decision | **pass** / pass-with-conditions / fail |
| Security owner (role) | <name> (Security owner) |
| Date | YYYY-MM-DD |
| Conditions / follow-ups | [tracked items, links] |
```

- [ ] **Step 2: Links resolve**

Run: `sh conformance/check-links.sh`
Expected: OK.

- [ ] **Step 3: Commit**

```bash
git add templates/THREAT-MODEL-TEMPLATE.md
git commit -m "feat(templates): THREAT-MODEL template — STRIDE/LINDDUN-lite + security-owner sign-off (gate parity Slice 2)"
```

---

## Task 6: Threat-model — wiring (PROCESS §7 · CLAUDE.md DoR + templates list · STANDARDS §2)

**Files:**
- Modify: `DEVELOPMENT-PROCESS.md` (lines 107 and 178 — existing threat-model gate rows; +0 appends)
- Modify: `CLAUDE.md` (line 17 templates list; line 73 DoR threat-model flag; +0 appends)
- Modify: `DEVELOPMENT-STANDARDS.md` §2 security section (one-line pointer)

**Doc-budget discipline:** every edit here must be append-to-existing-line (+0). Run `doc-budget.sh` after each file.

- [ ] **Step 1: PROCESS §7 — append template pointer to the two threat-model rows**

In `DEVELOPMENT-PROCESS.md` line 107 (the **Plan** row: "...**threat-model** sensitive features.") append the pointer inline, e.g. `…threat-model sensitive features (→ \`templates/THREAT-MODEL-TEMPLATE.md\`).`
In line 178 (the **Threat model** gate row: "What can go wrong security/privacy-wise? | Security owner") append to the question cell or the row, e.g. `…security/privacy-wise? (\`templates/THREAT-MODEL-TEMPLATE.md\`) | Security owner |`.
Keep both as in-line appends — do not add rows or lines.

- [ ] **Step 2: CLAUDE.md — templates list + DoR flag**

Line 17 templates list — add `THREAT-MODEL` to the comma list (it currently ends `… EVAL-PLAN, POSTMORTEM, BIA.`): make it `… EVAL-PLAN, THREAT-MODEL, POSTMORTEM, BIA.`
Line 73 DoR threat-model flag — append the template pointer: `- **Threat-model** *(if sensitive/regulated)* — flagged for the §7 security gate (`templates/THREAT-MODEL-TEMPLATE.md`).`

- [ ] **Step 3: STANDARDS §2 — one-line threat-model template pointer**

In `DEVELOPMENT-STANDARDS.md` §2 (Security, Governance & Guardrails, starts line 25), add a pointer to the threat-model template where threat modeling is referenced. Prefer appending to an existing sentence; if no natural host exists, a single new bullet is acceptable (headroom 309/320). Example append target — the §2 intro or the AI/agent-security subsection: `… threat model the feature first (`templates/THREAT-MODEL-TEMPLATE.md`).`

- [ ] **Step 4: Verify doc-budget + links after all three files**

Run: `sh conformance/doc-budget.sh && sh conformance/check-links.sh`
Expected: both OK. If doc-budget FAILs, convert the offending edit to an append-to-existing-line.

- [ ] **Step 5: Commit**

```bash
git add DEVELOPMENT-PROCESS.md CLAUDE.md DEVELOPMENT-STANDARDS.md
git commit -m "docs(process): wire THREAT-MODEL template — §7 security gate + DoR flag + templates list + STANDARDS §2 pointer"
```

---

## Task 7: CI selftest step (control-plane `cp` — Bradley applies)

**Files:**
- Modify (control-plane): `.github/workflows/ci.yml` — add an `observability-ready.sh --selftest` step after the eval-ready step (line 104-105).

The agent **cannot** edit `.github/workflows/` (guard control-plane protection). Prepare the exact diff and hand it to Bradley to apply via `cp` (the established pattern from Slice 1's `2ac6526`).

- [ ] **Step 1: Prepare the step text**

After the existing:
```yaml
      - name: Eval-ready self-test (AI-feature eval discipline)
        run: sh conformance/eval-ready.sh --selftest
```
add:
```yaml
      - name: Observability-ready self-test (SLOs + telemetry recorded)
        run: sh conformance/observability-ready.sh --selftest
```

- [ ] **Step 2: Hand the diff to Bradley**

Present the exact two-line addition + its anchor. Bradley applies it to `.github/workflows/ci.yml` with `KIT_GUARD_SELFEDIT=1` `cp` (or direct edit), then commits as `ci(gate-parity): run observability-ready.sh --selftest`. Do NOT attempt to edit the file directly.

---

## Task 8: Release v2.47.0 + final verification + PR

**Files:**
- Modify: `VERSION` → `2.47.0`
- Modify: `CHANGELOG.md` (new entry)
- Modify: `README.md` (badge)

- [ ] **Step 1: Bump VERSION**

Set `VERSION` to `2.47.0`.

- [ ] **Step 2: CHANGELOG entry**

Add under a new `## [2.47.0] - 2026-06-11` heading (Keep-a-Changelog style, matching the 2.46.0 entry's shape):
```markdown
## [2.47.0] - 2026-06-11

### Added — Gate parity Slice 2 (observability/SLO + threat-model)
- `conformance/observability-ready.sh` — conditional, fail-closed observability-record check (deploy-surface trigger; asserts RUNBOOK §8 records SLOs + telemetry, not placeholders; N/A · OK · FAIL + `--selftest`).
- `conformance/observability-readiness.md` — Auto (SLOs + telemetry declared) vs Manual (signals emit · alerts fire · error budget tracked) checklist.
- `templates/THREAT-MODEL-TEMPLATE.md` — STRIDE/LINDDUN-lite threat model with security-owner sign-off; wired into the §7 security gate, the DoR threat-model flag, and the templates list (no script — threat modeling is human-ratified).
- RUNBOOK §8 now records SLOs + telemetry; wired into `verify.sh` (doc-check), CI (`--selftest`), `conformance/README.md`, `audit-evidence-checklist.md`, and `DEVELOPMENT-STANDARDS.md` Factor 14.

### Honesty
- Each new check proves the posture is **declared/recorded**, not that it **works** — signals emitting, alerts firing, the threat model's quality stay **Manual** operator/security-owner rows. Closes the gate-parity arc.
```
(Confirm the CHANGELOG has a matching link-def section if the file uses one; match the 2.46.0 entry's convention exactly.)

- [ ] **Step 3: Sync README badge**

Update the version badge in `README.md` to `2.47.0`. Run: `sh conformance/badge-version.sh` → OK.

- [ ] **Step 4: Full verification suite**

Run:
```bash
dash -n conformance/observability-ready.sh && echo "dash OK"
sh conformance/observability-ready.sh --selftest
sh conformance/observability-ready.sh; echo "kit-root exit=$?"   # must be N/A, exit 0
sh conformance/check-links.sh && echo "links OK"
sh conformance/doc-budget.sh && echo "doc-budget OK"
sh conformance/badge-version.sh && echo "badge OK"
sh conformance/verify.sh 2>&1 | tail -4
```
Expected: dash OK; selftest 5/5 + OK; kit-root N/A exit 0; links OK; doc-budget OK; badge OK; `verify.sh` RESULT: OK (5 doc-checks now).

- [ ] **Step 5: Commit the release**

```bash
git add VERSION CHANGELOG.md README.md
git commit -m "chore(release): 2.47.0 — gate parity Slice 2 (observability/SLO + threat-model)"
```

- [ ] **Step 6: Independent review (builder ≠ sole reviewer) — security-owner lens**

Dispatch an independent review subagent over the full branch diff with the **security-owner lens** (governing-doc changes to PROCESS/STANDARDS + the §7 threat-model wiring). The reviewer checks: honesty/no-overclaim (no green check implies the system is actually observable / the threat model is good); trigger correctness (non-deployed → N/A, deployed+placeholder → FAIL); POSIX/dash + `set -eu`; doc-budget not breached; governance not weakened. Fold any Critical/High/Medium; carry LOWs with rationale.

- [ ] **Step 7: Push + open PR (Bradley merges)**

```bash
git push -u origin feature/gate-parity-observability-threatmodel
gh pr create --base main --head feature/gate-parity-observability-threatmodel \
  --title "Gate parity Slice 2 — observability/SLO + threat-model (v2.47.0)" --body "<summary + verification + folded nits>"
```
Then report the PR number + merge command (`gh pr merge <n> --squash --admin --delete-branch`) to Bradley for ratification. **Do not self-merge.**

---

## Verification (whole slice)

- `observability-ready.sh`: `dash -n` clean; `--selftest` 5/5 green; live run N/A at kit root (exit 0); fresh RUNBOOK template → FAIL (no false PASS).
- `verify.sh` RESULT: OK with **5 doc-checks**; `check-links.sh`, `doc-budget.sh`, `badge-version.sh` green; bootstrap-into-temp unaffected.
- Threat-model: template links resolve; §7/DoR/templates-list/STANDARDS pointers all present and link-valid; no script added (by decision).
- Doc-budget: core-3 still within caps after all wiring (CLAUDE.md ≤120, PROCESS ≤470, STANDARDS ≤320).
- Governance: feature branch → PR → Bradley merges; CI selftest step via control-plane `cp`; security-owner lens applied at review.

## Out of scope / deferred
- No `threat-model` conformance script (template-only, by decision — presence ≠ quality, "sensitive" not honestly auto-detectable).
- Container/k8s observability tooling specifics live in profiles, not here.
- Pre-story **product-discovery front end** is the next, separate frontier (Bradley's stated direction after the gate-parity arc).
