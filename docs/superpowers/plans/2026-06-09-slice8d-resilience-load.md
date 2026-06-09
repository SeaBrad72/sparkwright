# Slice 8d — Resilience + load/soak verification — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Verify §4 resilience principles + §6 load/soak — a verification reference, a conditional resilience-readiness checklist (judgment rows), and a thin record-script (`resilience-ready.sh`) proving the fault-injection + load/soak drills were recorded.

**Architecture:** Docs + one POSIX-sh conformance script modeled on the proven `deployable-ready.sh` (same deploy-surface detection, fail-closed accumulator, `--selftest`). The script checks a *dated record* (stack-neutral), not load-test tooling. Deployable-style conditional N/A (proportionate — reliability, not data loss); no DoD anchor. Anti-false-assurance: recorded ≠ resilient.

**Tech Stack:** POSIX `sh` (sh + dash), Markdown, GitHub Actions YAML, `git`.

**Spec:** `docs/superpowers/specs/2026-06-09-slice8d-resilience-load-design.md`

---

## File structure

| File | Responsibility | Change |
|------|----------------|--------|
| `conformance/resilience-ready.sh` | Record-script (deploy-surface conditional) + `--selftest` | **Create** |
| `conformance/resilience-readiness.md` | Resilience checklist (Manual + Auto rows) | **Create** |
| `docs/operations/resilience-verification.md` | Fault-injection + load/soak how-to | **Create** |
| `templates/RUNBOOK-TEMPLATE.md` §8 | Resilience-record lines | Modify |
| `DEVELOPMENT-STANDARDS.md` §4 + §6 | Reference the verification doc | Modify (2 edits) |
| `DEVELOPMENT-PROCESS.md` §7 | Resilience-readiness gate + sentence | Modify (2 edits) |
| `conformance/README.md` + `audit-evidence-checklist.md` | Index + audit row | Modify (3 rows) |
| `.github/workflows/ci.yml` | present + N/A + selftest | Modify (3 steps) |
| `VERSION` / `CHANGELOG.md` / `docs/ROADMAP-KIT.md` | Release meta | Modify |

---

### Task 1: Create `conformance/resilience-ready.sh`

**Files:**
- Create: `conformance/resilience-ready.sh`

- [ ] **Step 1: Confirm the kit root is N/A (pre-check)**

Run:
```bash
ls Dockerfile 2>&1 | head -1
grep -lRE '^[[:space:]]*environment:|^[[:space:]]+deploy[A-Za-z0-9_-]*:[[:space:]]*$' .github/workflows/ 2>/dev/null || echo "(no deploy workflow at root)"
```
Expected: no root `Dockerfile`; no workflow with an `environment:` key or `deploy` job. (Same basis as `deployable-ready.sh`'s kit-root N/A. If any exist, STOP and report.)

- [ ] **Step 2: Write the script**

Create `conformance/resilience-ready.sh` with EXACTLY this content:

```sh
#!/bin/sh
# resilience-ready.sh — conditional, fail-closed resilience-record check.
#
# Companion to conformance/resilience-readiness.md (the Resilience-readiness gate;
# DEVELOPMENT-PROCESS.md §7). For a project with a DEPLOY SURFACE it asserts the
# resilience drills are RECORDED: the RUNBOOK §8 has a "Load/soak tested:" date and a
# "Fault-injection drill:" date (not the template [date] placeholder). Projects with no
# deploy surface are N/A (skip-pass) — a library/CLI has no dependencies to circuit-break
# or load to soak.
#
# SCOPE — a green run proves the drills were RECORDED, NOT that the system is actually
# resilient (breaker tripped, degraded gracefully, survived soak). Those are Manual rows
# in resilience-readiness.md (on-call/operator evidence). A green run is necessary, not
# sufficient.
#
# Usage:
#   sh conformance/resilience-ready.sh [project-dir]   (default: .)
#   sh conformance/resilience-ready.sh --selftest
#
# Run at the Resilience-readiness gate (DEVELOPMENT-PROCESS.md §7); also self-tested in kit CI.
set -eu

# Does $1 (a workflow file) indicate a deploy surface? (Same structural signals as
# deployable-ready.sh: a GitHub `environment:` key or a deploy-ish job key.)
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
    echo "N/A: $dir has no deploy surface (no Dockerfile / deploy workflow) — skipping (no dependencies to circuit-break or load to soak)"
    return 0
  fi

  rb="$dir/RUNBOOK.md"
  if [ ! -f "$rb" ]; then
    echo "FAIL: $dir is deployable but has no RUNBOOK.md (need §8 resilience records) — see conformance/resilience-readiness.md"
    return 1
  fi

  # Record strings below must stay in sync with templates/RUNBOOK-TEMPLATE.md §8.
  if ! grep -Eiq 'load/soak tested:' "$rb"; then
    echo "FAIL: RUNBOOK has no 'Load/soak tested:' record — run a load/soak test and record the date (docs/operations/resilience-verification.md)"
    fail=1
  elif grep -Fiq 'load/soak tested: [date]' "$rb"; then
    echo "FAIL: 'Load/soak tested:' still holds the [date] placeholder — run the test and record the date"
    fail=1
  fi
  if ! grep -Eiq 'fault-injection drill:' "$rb"; then
    echo "FAIL: RUNBOOK has no 'Fault-injection drill:' record — run a fault-injection drill and record the date"
    fail=1
  elif grep -Fiq 'fault-injection drill: [date]' "$rb"; then
    echo "FAIL: 'Fault-injection drill:' still holds the [date] placeholder — run the drill and record the date"
    fail=1
  fi

  if [ "$fail" -ne 0 ]; then return 1; fi
  echo "resilience-ready: OK — resilience drills are RECORDED. NOTE: this does NOT verify the system is actually resilient (breaker tripped, degraded gracefully, survived soak) — those are Manual rows in resilience-readiness.md requiring on-call/operator evidence."
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
  printf '# RUNBOOK\n\n## Monitoring & alerting\n- Resilience verification: Load/soak tested: 2026-06-01 · Fault-injection drill: 2026-06-02\n' > "$d3/RUNBOOK.md"
  if check_dir "$d3" >/dev/null 2>&1; then
    echo "selftest PASS: complete deployable -> OK"
  else
    echo "selftest FAIL: complete deployable should pass"; st_fail=1
  fi

  d4="$base/placeholder"; mkdir -p "$d4"
  printf 'FROM scratch\n' > "$d4/Dockerfile"
  printf '# RUNBOOK\n\n## Monitoring & alerting\n- Load/soak tested: [date] · Fault-injection drill: 2026-06-02\n' > "$d4/RUNBOOK.md"
  if check_dir "$d4" >/dev/null 2>&1; then
    echo "selftest FAIL: [date] placeholder should FAIL"; st_fail=1
  else
    echo "selftest PASS: load/soak [date] placeholder -> FAIL as expected"
  fi

  d5="$base/missing"; mkdir -p "$d5"
  printf 'FROM scratch\n' > "$d5/Dockerfile"
  printf '# RUNBOOK\n\n## Monitoring & alerting\n- Load/soak tested: 2026-06-01\n' > "$d5/RUNBOOK.md"
  if check_dir "$d5" >/dev/null 2>&1; then
    echo "selftest FAIL: missing fault-injection record should FAIL"; st_fail=1
  else
    echo "selftest PASS: missing fault-injection record -> FAIL as expected"
  fi

  if [ "$st_fail" -ne 0 ]; then
    echo "resilience-ready --selftest: FAIL" >&2
    return 1
  fi
  echo "resilience-ready --selftest: OK (na/no-surface/ok/placeholder/missing all behaved; fixtures left in $base)"
  return 0
}

case "${1:-}" in
  --selftest) selftest ;;
  *)          check_dir "${1:-.}" ;;
esac
exit $?
```

- [ ] **Step 3: Run the self-test**

Run: `sh conformance/resilience-ready.sh --selftest; echo "exit=$?"`
Expected: five `selftest PASS:` lines, final `resilience-ready --selftest: OK …`, `exit=0`.

- [ ] **Step 4: Run at the kit root (must be N/A)**

Run: `sh conformance/resilience-ready.sh; echo "exit=$?"`
Expected: `N/A: . has no deploy surface … skipping …`, `exit=0`.

- [ ] **Step 5: Verify the scope-disclaimer wording**

Run: `grep -c "does NOT verify the system is actually resilient" conformance/resilience-ready.sh`
Expected: `1`.

- [ ] **Step 6: Syntax lint (sh + dash)**

Run: `sh -n conformance/resilience-ready.sh && echo "sh OK"` then `command -v dash >/dev/null && dash -n conformance/resilience-ready.sh && echo "dash OK" || echo "dash not installed — skipped"`
Expected: `sh OK` (and `dash OK` or skip).

- [ ] **Step 7: Commit**

```bash
chmod +x conformance/resilience-ready.sh
git add conformance/resilience-ready.sh
git commit -m "feat(conformance): add resilience-ready.sh — record check for resilience drills

Conditional on a deploy surface; asserts RUNBOOK §8 records a load/soak
date and a fault-injection date (non-placeholder); N/A skip-pass otherwise.
Self-discloses scope (recorded != actually resilient). --selftest battery.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

## Important notes
- Create ONLY `conformance/resilience-ready.sh`. Do NOT modify other files. Do NOT run `inception-done.sh`. Preserve em-dashes (—), middots (·), `->`, and `[date]` literally. Use the Write tool.

## Report Format
Report: Status, exact output of Steps 1, 3, 4, 5, 6, the commit SHA, any concerns.

---

### Task 2: Create `conformance/resilience-readiness.md`

**Files:**
- Create: `conformance/resilience-readiness.md`

- [ ] **Step 1: Create the file with EXACTLY this content**

```markdown
# Conformance Check — Resilience Readiness

Proves a service **survives failure and load**: retries back off, circuit breakers trip, the service degrades gracefully, and it holds up under load/soak. **Checklist-type**, run at the **Resilience-readiness gate** (`DEVELOPMENT-PROCESS.md` §7) and as **recurring maintenance** (§15). **Conditional:** non-deployable projects (library, CLI, batch) mark the whole check **N/A — no dependencies to circuit-break or load to soak**. Verifies the principles asserted in `DEVELOPMENT-STANDARDS.md` §4 (resilience) and §6 (load-test before launch). Aligns with chaos-engineering (Principles of Chaos) / SRE reliability practice.

> **What the Auto rows prove — and don't.** `resilience-ready.sh` confirms the drills are *recorded* (a load/soak date and a fault-injection date in RUNBOOK §8). It does **not** verify the system is *actually* resilient — that the breaker tripped, the service degraded gracefully, or it survived the soak. Those are the **Manual** rows, signed off by the on-call/operator with evidence. **A green script is necessary, not sufficient.**

## How to use
Copy this file into your project (or your reliability record). For each item: mark **Applies? (Y / N+reason)** and give **Evidence**. Items tagged *(documented)* are auto-checkable via `sh conformance/resilience-ready.sh`; items tagged *(verified)* require the on-call/operator's evidence from an actual drill. The reviewer signs off only when every applicable item has evidence. How to run the drills: `docs/operations/resilience-verification.md`.

## Checklist (blank)

| # | Item | Applies? | Evidence (where/how) | Check |
|---|------|----------|----------------------|-------|
| 1 | Retry with backoff exercised on a transient failure (§4) *(verified)* | | | Manual |
| 2 | Circuit breaker **trips** when a dependency fails (§4) *(verified)* | | | Manual |
| 3 | Graceful degradation — killed dependency → service degrades, not crashes (§4) *(verified)* | | | Manual |
| 4 | Idempotency verified for retryable operations (§4) *(verified)* | | | Manual |
| 5 | Fault-injection drill **run** — date recorded (RUNBOOK §8) *(documented)* | | | **Auto:** `resilience-ready.sh` |
| 6 | Load test **run** — latency/error within the §6 budget *(verified)* | | | Manual |
| 7 | Soak test clean — no leak / latency creep over time *(verified)* | | | Manual |
| 8 | Load/soak **run** — date recorded (RUNBOOK §8) *(documented)* | | | **Auto:** `resilience-ready.sh` |

## Worked example — a deployable HTTP service with a Postgres dependency

| # | Item | Applies? | Evidence | Check |
|---|------|----------|----------|-------|
| 1 | Retry/backoff *(verified)* | Y | injected 3 transient DB errors; client retried with backoff, no herd (drill log) | Manual ✅ |
| 2 | Breaker trips *(verified)* | Y | killed DB; breaker opened after threshold, fast-failed; recovered on restore | Manual ✅ |
| 3 | Graceful degradation *(verified)* | Y | cache down → served stale within TTL; no 5xx spike | Manual ✅ |
| 4 | Idempotency *(verified)* | Y | duplicate POST with same key → single effect (test) | Manual ✅ |
| 5 | Fault-injection recorded *(documented)* | Y | RUNBOOK §8 "Fault-injection drill: 2026-06-02" | Auto ✅ |
| 6 | Load within budget *(verified)* | Y | 500 rps, p95 180ms (< 200ms §6), error < 0.1% (k6 report) | Manual ✅ |
| 7 | Soak clean *(verified)* | Y | 4h soak, flat memory, no latency creep (Grafana) | Manual ✅ |
| 8 | Load/soak recorded *(documented)* | Y | RUNBOOK §8 "Load/soak tested: 2026-06-01" | Auto ✅ |

> A library or CLI marks the whole check **N/A — no dependencies to circuit-break or load to soak**; `resilience-ready.sh` skip-passes such a project automatically.
```

- [ ] **Step 2: Verify callout + labels**

Run:
```bash
grep -c "A green script is necessary, not sufficient" conformance/resilience-readiness.md
grep -c "(documented)" conformance/resilience-readiness.md
grep -c "(verified)" conformance/resilience-readiness.md
```
Expected: first `1`; second ≥ 4; third ≥ 4.

- [ ] **Step 3: Link check**

Run: `sh conformance/check-links.sh; echo "exit=$?"`
Expected: `exit=0`.

- [ ] **Step 4: Commit**

```bash
git add conformance/resilience-readiness.md
git commit -m "feat(conformance): add resilience-readiness checklist

Conditional checklist (Manual judgment rows + Auto record rows) with a
'necessary not sufficient' callout. Verifies §4 resilience + §6 load.
Chaos/SRE anchor.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

## Important notes
- Create ONLY `conformance/resilience-readiness.md`. Preserve special chars (—, →, ✅, §). Every `*(documented)*` row must be **Auto**; every `*(verified)*` row must be **Manual** (the load-bearing anti-false-assurance split). Do NOT run `inception-done.sh`.

## Report Format
Report: Status, exact output of Step 2 and Step 3, commit SHA, any concerns.

---

### Task 3: Create `docs/operations/resilience-verification.md`

**Files:**
- Create: `docs/operations/resilience-verification.md` (the `docs/operations/` dir does not exist — Write creates it)

- [ ] **Step 1: Create the file with EXACTLY this content**

```markdown
# Resilience Verification — Reference

How to **prove** a service survives failure and load, rather than asserting it. Stack-neutral; tooling is a project/Org choice. Verifies the principles in `DEVELOPMENT-STANDARDS.md` §4 (resilience) and §6 (load-test before launch). Aligns with chaos-engineering (Principles of Chaos) / SRE reliability practice. This is the "how" behind the Resilience-readiness check (`conformance/resilience-readiness.md`).

> **Do no harm — inject faults in staging, never production.** Fault-injection and load/soak run against an **isolated / staging environment**, never live traffic. The point is to learn how the system fails *before* users do.

## Fault-injection drill
Kill or degrade a dependency (database, cache, downstream API) in staging and observe:
1. **Retries back off** — the client retries with exponential backoff + jitter, not a thundering herd.
2. **Circuit breaker trips** — after the failure threshold the breaker opens and fast-fails, sparing the dependency; it half-opens and recovers when the dependency returns.
3. **Graceful degradation** — the service serves a fallback (cached/stale data, a reduced feature, a clear error) and **does not crash or cascade**.
Record the date and what you observed in RUNBOOK §8.

## Load / soak test
1. Drive **sustained, realistic load** (model real traffic shape, not just a flat curve).
2. Watch **latency (p95/p99), error rate, and resource trends** (CPU, memory, connections).
3. Find the **knee** — the load where latency/errors break the §6 performance budget. Know your headroom.
4. **Soak** — hold moderate load for hours to surface memory leaks, connection exhaustion, and slow latency creep.
Record the date and the actuals vs. the §6 budget in RUNBOOK §8.

## What "passed" means
- Fault-injection: breaker/retry/degradation all behaved; no crash or cascade.
- Load/soak: stayed within the §6 budget at expected load, with known headroom and no leak.
- Recording a date is the **floor**; a *passed* drill (the Manual rows in `conformance/resilience-readiness.md`) is the **bar**. A recorded date alone does not prove resilience.

## Cadence
- **Pre-launch** (§6) for any public-facing service, and after any change to a dependency or the failure-handling path.
- Periodically thereafter (recurring maintenance, §15).

## Tooling (Org-owned)
Load generators (k6, Locust, Gatling, JMeter, vegeta, artillery) and fault-injection (toxiproxy, a chaos-engineering tool, or a manual dependency-kill in staging) are platform choices. The kit standardizes the **practice and the proof**, not the tool.
```

- [ ] **Step 2: Link check**

Run: `sh conformance/check-links.sh; echo "exit=$?"`
Expected: `exit=0`.

- [ ] **Step 3: Commit**

```bash
git add docs/operations/resilience-verification.md
git commit -m "docs(operations): add resilience-verification reference

Stack-neutral how-to: fault-injection drill (breaker/retry/degradation),
load/soak test (knee + leaks), isolated-env do-no-harm rule, recorded !=
passed. Chaos/SRE anchor.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

## Important notes
- Create ONLY `docs/operations/resilience-verification.md`. Preserve special chars (—, →, §). Do NOT run `inception-done.sh`.

## Report Format
Report: Status, exact output of Step 2, commit SHA, any concerns.

---

### Task 4: RUNBOOK §8 resilience records + §4/§6 references

**Files:**
- Modify: `templates/RUNBOOK-TEMPLATE.md` (§8)
- Modify: `DEVELOPMENT-STANDARDS.md` (§4 line 75, §6 line 95)

- [ ] **Step 1: Add the resilience-record line to RUNBOOK §8**

Find this EXACT block:
```
## 8. Monitoring & alerting
- Error tracking: [tool/link] · Health check: [endpoint] · Alerts: [what fires, to whom]
```
Replace with:
```
## 8. Monitoring & alerting
- Error tracking: [tool/link] · Health check: [endpoint] · Alerts: [what fires, to whom]
- **Resilience verification** *(deployable services — see `docs/operations/resilience-verification.md`)*: Load/soak tested: [date] · Fault-injection drill: [date]
```

- [ ] **Step 2: Reference the verification doc from §4**

Find this EXACT line:
```
- **Graceful degradation** — handle the unhappy path; never assume the happy path. **→ profile** for idioms.
```
Replace with:
```
- **Graceful degradation** — handle the unhappy path; never assume the happy path. **→ profile** for idioms. **Verify these under failure — don't just assert them** (`docs/operations/resilience-verification.md`).
```

- [ ] **Step 3: Reference the verification doc from §6**

Find this EXACT line:
```
- **Core Web Vitals** "Good" for user-facing web. **Load-test** before any public launch. **→ profile** for query tooling and perf budgets.
```
Replace with:
```
- **Core Web Vitals** "Good" for user-facing web. **Load-test (and soak-test)** before any public launch (`docs/operations/resilience-verification.md`). **→ profile** for query tooling and perf budgets.
```

- [ ] **Step 4: Verify**

Run:
```bash
grep -c "Load/soak tested: \[date\]" templates/RUNBOOK-TEMPLATE.md
grep -c "Verify these under failure" DEVELOPMENT-STANDARDS.md
grep -c "Load-test (and soak-test)" DEVELOPMENT-STANDARDS.md
sh conformance/check-links.sh; echo "exit=$?"
```
Expected: first `1`; second `1`; third `1`; links `exit=0`.

- [ ] **Step 5: Commit**

```bash
git add templates/RUNBOOK-TEMPLATE.md DEVELOPMENT-STANDARDS.md
git commit -m "feat(standards): RUNBOOK §8 resilience records + §4/§6 verify refs

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

## Important notes
- ONLY those two files. KEEP the `[date]` placeholders in RUNBOOK §8 — they are the enforcement hook for resilience-ready.sh. Preserve special chars. Do NOT run `inception-done.sh`.

## Report Format
Report: Status, exact output of Step 4, commit SHA, any concerns.

---

### Task 5: §7 Resilience-readiness gate + conditional sentence

**Files:**
- Modify: `DEVELOPMENT-PROCESS.md` (§7 line 187 + line 191)

- [ ] **Step 1: Add the §7 gate row**

Find this EXACT line:
```
| **DR readiness** *(data services)* | Is DR provable — BIA done, RTO/RPO tiered, restore drill passed? (`conformance/dr-readiness.md`) | On-call / operator + reviewer |
```
Insert this row DIRECTLY AFTER it:
```
| **Resilience readiness** *(deployable services)* | Do resilience + load/soak verifications pass — breaker trips, degrades gracefully, within perf budget? (`conformance/resilience-readiness.md`) | On-call / operator + reviewer |
```

- [ ] **Step 2: Update the conditional-gates sentence**

Find this EXACT text:
```
Threat-model, eval, compliance, 15-factor, Definition-of-Deployable, and DR-readiness gates are **conditional** — they apply to sensitive / AI / regulated / deployable-service / data-handling work respectively, not every item (don't impose them where they optimize nothing).
```
Replace with:
```
Threat-model, eval, compliance, 15-factor, Definition-of-Deployable, DR-readiness, and Resilience-readiness gates are **conditional** — they apply to sensitive / AI / regulated / deployable-service / data-handling work respectively, not every item (don't impose them where they optimize nothing).
```
(The work-type list is intentionally left unchanged — "deployable-service" already covers 15-factor, Definition-of-Deployable, and Resilience-readiness; the "respectively" mapping is approximate, so no new work-type is appended.)

- [ ] **Step 3: Verify**

Run:
```bash
grep -cF "**Resilience readiness** *(deployable services)*" DEVELOPMENT-PROCESS.md
grep -c "and Resilience-readiness gates are" DEVELOPMENT-PROCESS.md
sh conformance/check-links.sh; echo "exit=$?"
```
Expected: first `1`; second `1`; links `exit=0`.

- [ ] **Step 4: Commit**

```bash
git add DEVELOPMENT-PROCESS.md
git commit -m "feat(process): Resilience-readiness conditional gate (§7)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

## Important notes
- ONLY `DEVELOPMENT-PROCESS.md`. Two edits. Preserve special chars (—, →, §). Do NOT run `inception-done.sh`.

## Report Format
Report: Status, exact output of Step 3, commit SHA, any concerns.

---

### Task 6: Index the checks (README + audit-evidence)

**Files:**
- Modify: `conformance/README.md` (after the `dr-ready.sh` row)
- Modify: `conformance/audit-evidence-checklist.md` (after the DR-drill row)

- [ ] **Step 1: Add two README index rows**

Find this EXACT row:
```
| `dr-ready.sh` | script | `DEVELOPMENT-STANDARDS.md` §10 — documented DR (BIA + RUNBOOK §6 + recorded drill); escalate-only; pairs with the checklist | Review / CI (conditional on a data surface) |
```
Insert these two rows DIRECTLY AFTER it:
```
| `resilience-readiness.md` | checklist | `DEVELOPMENT-STANDARDS.md` §4 / §6 (resilience + load/soak) | Review / recurring (conditional) |
| `resilience-ready.sh` | script | `DEVELOPMENT-STANDARDS.md` §4 / §6 — recorded resilience drills (RUNBOOK §8); pairs with the checklist | Review / CI (conditional on a deploy surface) |
```

- [ ] **Step 2: Add the audit-evidence row**

Find this EXACT row:
```
| DR drill · backup-restore | CC7.5, A1.2 / A.5.29, A.8.13, A.8.14 | BIA (`docs/continuity/BIA.md`) + RUNBOOK §6 + recorded drill date + drill log | **Auto (conditional):** `sh conformance/dr-ready.sh` | |
```
Insert this row DIRECTLY AFTER it:
```
| Resilience · load/soak + fault-injection | A1.2, A1.3 / A.8.6, A.8.16 | resilience-verification records (RUNBOOK §8) + drill/load logs | **Auto (conditional):** `sh conformance/resilience-ready.sh` | |
```

- [ ] **Step 3: Verify**

Run:
```bash
grep -c "resilience-readiness.md" conformance/README.md
grep -c "resilience-ready.sh" conformance/README.md
grep -c "Resilience · load/soak + fault-injection" conformance/audit-evidence-checklist.md
sh conformance/check-links.sh; echo "exit=$?"
```
Expected: first `1`; second `1`; third `1`; links `exit=0`.

- [ ] **Step 4: Commit**

```bash
git add conformance/README.md conformance/audit-evidence-checklist.md
git commit -m "docs(conformance): index resilience-readiness + resilience-ready; audit row

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

## Important notes
- ONLY those two files. Three inserted rows. Preserve special chars (·, —, §). Do NOT run `inception-done.sh`.

## Report Format
Report: Status, exact output of Step 3, commit SHA, any concerns.

---

### Task 7: Dogfood in kit CI

**Files:**
- Modify: `.github/workflows/ci.yml` (conformance job — after the DR-ready selftest step)

- [ ] **Step 1: Find the insertion point**

Run: `grep -n "DR-ready self-test" .github/workflows/ci.yml`
Expected: one match. Insert the new steps directly after its `run:` line (the last steps of the `conformance` job, before `bootstrap:`).

- [ ] **Step 2: Add the three steps**

After the `run: sh conformance/dr-ready.sh --selftest` line, insert (6-space `- name:`, 8-space `run:`):
```yaml
      - name: Resilience-readiness checklist present
        run: test -f conformance/resilience-readiness.md
      - name: Resilience-ready conditional (N/A at kit root)
        run: sh conformance/resilience-ready.sh
      - name: Resilience-ready self-test (na/no-surface/ok/placeholder/missing fixtures)
        run: sh conformance/resilience-ready.sh --selftest
```

- [ ] **Step 3: Verify placement + commands pass locally**

Run:
```bash
grep -n "Resilience-ready self-test" .github/workflows/ci.yml
sed -n '38,48p' .github/workflows/ci.yml
sh conformance/resilience-ready.sh; echo "na=$?"
sh conformance/resilience-ready.sh --selftest >/dev/null 2>&1; echo "selftest=$?"
test -f conformance/resilience-readiness.md && echo "checklist present"
```
Expected: the steps are the tail of the `conformance` job (before `bootstrap:`); `na=0`, `selftest=0`, "checklist present".

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: dogfood resilience-ready (present + N/A + selftest)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

## Important notes
- ONLY `.github/workflows/ci.yml`. Three steps, in the `conformance` job, before `bootstrap:`. Indentation MUST match siblings. Do NOT run `inception-done.sh`.

## Report Format
Report: Status, exact output of Step 3 (especially the sed showing placement), commit SHA, any concerns.

---

### Task 8: Version bump, CHANGELOG, ROADMAP

**Files:**
- Modify: `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-KIT.md`

- [ ] **Step 1: Bump VERSION**

Replace the contents of `VERSION` (`2.21.0`) with:
```
2.22.0
```

- [ ] **Step 2: Add the CHANGELOG entry**

Insert this entry IMMEDIATELY ABOVE the `## [2.21.0] - 2026-06-09` line:
```markdown
## [2.22.0] - 2026-06-09

Slice 8d — Resilience + load/soak verification. Fourth sub-slice of Slice 8 (continuity & safe-delivery hardening). Closes gap A3 (resilience principles + load/soak asserted but never verified). Chaos-engineering / SRE anchor.

### Added
- **`docs/operations/resilience-verification.md`** — a stack-neutral how-to: the fault-injection drill (breaker trips, retries back off, degrades gracefully) and the load/soak test (find the knee, catch leaks), with the isolated-env do-no-harm rule and "recorded ≠ passed".
- **`conformance/resilience-readiness.md`** — a conditional resilience checklist (Manual judgment rows + Auto record rows) with a "necessary, not sufficient" callout; verifies `DEVELOPMENT-STANDARDS.md` §4 + §6.
- **`conformance/resilience-ready.sh`** — a conditional, fail-closed companion: for a project with a deploy surface it asserts RUNBOOK §8 records a load/soak date and a fault-injection date (non-placeholder); otherwise N/A. Self-discloses scope (recorded ≠ actually resilient). `--selftest` battery. Stack-neutral (checks a dated record, not load-test tooling).
- **`DEVELOPMENT-PROCESS.md`** — a conditional **Resilience readiness** gate (§7).
- **`DEVELOPMENT-STANDARDS.md`** — §4 and §6 now point at the verification reference ("verify these — don't just assert them"); RUNBOOK §8 gains the resilience-record lines.
- **`audit-evidence-checklist.md`** — a resilience row (A1.2, A1.3 / A.8.6, A.8.16; Auto-conditional).

### Note
MINOR (2.22.0): additive — a conditional Review gate, a checklist, a record-script, and a reference. No new universally-required CI gate; no DoD anchor (proportionate — a resilience miss is a reliability risk caught at Review, not data loss). The 8 application gate-ids and §14 are unchanged.
```

- [ ] **Step 3: Add the ROADMAP row**

In `docs/ROADMAP-KIT.md`, insert this row IMMEDIATELY AFTER the `8c ✅` row:
```
| 8d ✅ | **Resilience + load/soak verification** *(shipped v2.22.0)* | standards §4/§6 + process §7 (chaos/SRE) | `resilience-verification.md` + `resilience-readiness.md` + `resilience-ready.sh` (conditional, --selftest) | `resilience-ready.sh --selftest` + `check-links.sh` |
```

- [ ] **Step 4: Verify**

Run:
```bash
cat VERSION
grep -c "## \[2.22.0\]" CHANGELOG.md
grep -c "8d ✅" docs/ROADMAP-KIT.md
sh conformance/check-links.sh; echo "exit=$?"
```
Expected: `2.22.0`; `1`; `1`; links `exit=0`.

- [ ] **Step 5: Commit**

```bash
git add VERSION CHANGELOG.md docs/ROADMAP-KIT.md
git commit -m "chore(release): 2.22.0 — resilience + load/soak verification (8d)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

## Important notes
- ONLY those three files. Insert-only. Preserve special chars (—, ≠, §, ✅). Do NOT run `inception-done.sh`.

## Report Format
Report: Status, exact output of Step 4, commit SHA, any concerns.

---

### Task 9: Full conformance sweep + push + PR (stop for ratification)

**Files:** none (verification + push only)

- [ ] **Step 1: Run every conformance check**

Run:
```bash
sh conformance/check-links.sh; echo "links=$?"
for p in profiles/*/ci.yml; do sh conformance/ci-gates.sh "$p" >/dev/null 2>&1 || echo "FAIL $p"; done; echo "ci-gates done"
sh conformance/profile-completeness.sh >/dev/null 2>&1; echo "profiles=$?"
sh conformance/agent-autonomy.sh >/dev/null 2>&1; echo "autonomy=$?"
sh conformance/container-supply-chain.sh >/dev/null 2>&1; echo "containers=$?"
sh conformance/backlog-adapters.sh >/dev/null 2>&1; echo "backlog=$?"
sh conformance/guard-wired.sh >/dev/null 2>&1; echo "guard=$?"
sh conformance/deployable-ready.sh --selftest >/dev/null 2>&1; echo "deployable-selftest=$?"
sh conformance/dr-ready.sh --selftest >/dev/null 2>&1; echo "dr-selftest=$?"
sh conformance/resilience-ready.sh; echo "resilience-root=$?"
sh conformance/resilience-ready.sh --selftest; echo "resilience-selftest=$?"
```
Expected: `links=0`, no `FAIL` from ci-gates, all the rest `=0`, `resilience-root=0` (N/A), `resilience-selftest=0`.

- [ ] **Step 2: Final spec-coverage greps**

Run:
```bash
ls conformance/resilience-ready.sh conformance/resilience-readiness.md docs/operations/resilience-verification.md
grep -c "does NOT verify the system is actually resilient" conformance/resilience-ready.sh   # 1
grep -c "A green script is necessary, not sufficient" conformance/resilience-readiness.md     # 1
grep -cF "**Resilience readiness** *(deployable services)*" DEVELOPMENT-PROCESS.md             # 1
cat VERSION                                                                                    # 2.22.0
```

- [ ] **Step 3: Confirm clean tree + push**

```bash
git status --short    # only the pre-existing untracked .firecrawl/
git push -u origin feature/slice-8d-resilience-load
```

- [ ] **Step 4: Open the PR (do NOT merge — human ratification gate)**

```bash
gh pr create --title "Slice 8d — Resilience + load/soak verification (v2.22.0)" \
  --body "$(cat <<'EOF'
Closes gap A3 (Slice 8 arc). Verifies §4 resilience principles + §6 load/soak — currently asserted but never checked.

## What
- **`docs/operations/resilience-verification.md`** — fault-injection + load/soak how-to (isolated-env do-no-harm rule, breaker/retry/degradation, knee + leaks, recorded != passed). Chaos/SRE anchor.
- **`conformance/resilience-readiness.md` + `resilience-ready.sh`** — conditional resilience pair (deployable services). Checklist Manual rows hold the behaviours (breaker trips, degrades gracefully, survives soak); the script auto-verifies the recorded floor (a load/soak date + a fault-injection date in RUNBOOK §8). Stack-neutral (checks a dated record, not load-test tooling).
- **§7** conditional **Resilience readiness** gate; §4/§6 reference the verification doc; RUNBOOK §8 resilience records.

## Proportionate by design
- **Deployable-style conditional N/A** (not 8c's escalate-only) and **no DoD anchor** — a resilience miss is a reliability risk caught at Review, not irreversible data loss. Enforcement weight matched to blast radius.
- Same anti-false-assurance as 8b/8c: documented + recorded != actually resilient; the on-call/operator signs the Manual rows. Wording grep-asserted in CI.

## Verification
All conformance green; `resilience-ready.sh --selftest` 5/5 in CI; `sh -n` + `dash -n` clean; **MINOR -> 2.22.0** (no new CI gate-id; §14 unchanged).

## Governance
Governing-doc surface (PROCESS §7, STANDARDS §4/§6) -> **security-owner lens**. Agent does not self-merge — this PR stops for human ratification.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 5: STOP for human ratification**

Do not merge. Report the PR URL + green conformance to Bradley (governing-doc change → security-owner lens per §13/RBAC).

---

## Self-Review

**1. Spec coverage:**
- Deliverable A (verification reference) → Task 3. ✅
- Deliverable B (checklist) → Task 2. ✅
- Deliverable C (record-script, --selftest) → Task 1. ✅
- Deliverable D (RUNBOOK §8 records) → Task 4 Step 1. ✅
- Deliverable E (§4 + §6 refs) → Task 4 Steps 2–3. ✅
- Deliverable F (§7 gate) → Task 5. ✅
- Deliverable G (README + audit) → Task 6. ✅
- Deliverable H (CI) → Task 7. ✅
- Meta → Task 8. ✅
- Anti-false-assurance (scope disclaimer + callout + grep) → Task 1 (script + grep), Task 2 (callout), Task 9 grep. ✅
- Proportionate N/A (deployable-style, not escalate-only) → Task 1 (plain N/A message). ✅

**2. Placeholder scan:** `[date]`, `[tool/link]`, `[endpoint]` are intended RUNBOOK fill-ins (house style). The script, checklist, and reference are given in full. No "TBD/implement later" in plan instructions. ✅

**3. Consistency:** `resilience-ready.sh` / `resilience-readiness.md` / `docs/operations/resilience-verification.md` names identical across all tasks, CI, README, audit row, CHANGELOG, ROADMAP. The script's record-grep strings ("Load/soak tested:" / "Fault-injection drill:") match the RUNBOOK §8 line added in Task 4 Step 1 and the selftest fixtures in Task 1. The scope string ("does NOT verify the system is actually resilient") matches Task 1 Step 5 + Task 9 grep. The deploy-surface detection (`wf_is_deploy` + Dockerfile) matches Task 1 Step 1's kit-root pre-check. The conditional-gates sentence edit (Task 5 Step 2) appends "Resilience-readiness" and a matching trailing clause. ✅

> **Self-review note (fixed inline):** Task 5 Step 2 originally appended a duplicate "deployable-service" to the work-type list. Fixed: the gate list gains "and Resilience-readiness" but the work-type list is unchanged ("deployable-service" already covers the deployable-service-conditional gates; the "respectively" mapping is approximate). The Task 5 Step 3 grep (`grep -c "and Resilience-readiness gates are"`) matches the corrected sentence.
