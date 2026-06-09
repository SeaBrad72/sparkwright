# Slice 8c — DR / backup-restore drill + BIA-at-Inception — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make DR provable: a restore-drill reference, a BIA template + Inception step, and a conditional DR-readiness conformance pair (`dr-readiness.md` checklist + escalate-only `dr-ready.sh`) anchored to the Definition of Done for data services.

**Architecture:** Docs + one POSIX-sh conformance script, conditional on a persistent-data surface and fail-closed, mirroring `deployable-ready.sh`. The script is **escalate-only**: its `N/A` is self-incriminating (a miss never exempts a data project), and its success output self-discloses scope (documented + recorded ≠ tested). A `--selftest` battery regression-locks the paths in kit CI. The checklist is the gate of record; the DoD anchor makes a passed check part of "done" for data services.

**Tech Stack:** POSIX `sh` (sh + dash), Markdown, GitHub Actions YAML, `git`.

**Spec:** `docs/superpowers/specs/2026-06-09-slice8c-dr-backup-restore-design.md`

---

## File structure

| File | Responsibility | Change |
|------|----------------|--------|
| `conformance/dr-ready.sh` | Escalate-only DR-readiness auto-check + `--selftest` | **Create** |
| `conformance/dr-readiness.md` | DR-readiness checklist (Manual + Auto rows) | **Create** |
| `docs/continuity/backup-restore-drill.md` | The restore-drill how-to (reference) | **Create** |
| `templates/BIA-TEMPLATE.md` | Business Impact Analysis template | **Create** |
| `DEVELOPMENT-STANDARDS.md` §10 | Tiered RTO/RPO + BIA/drill refs | Modify (1 bullet) |
| `templates/RUNBOOK-TEMPLATE.md` §6 | Per-tier RTO/RPO option | Modify |
| `START-HERE.md` §6 + Inception-Done | BIA step + conditional gate line | Modify (2 inserts) |
| `DEVELOPMENT-PROCESS.md` §15 + §7 | drill ref + DR-readiness gate + sentence | Modify (3 edits) |
| `CLAUDE.md` DoD Production line | "DR proven for data services" anchor | Modify (1 line) |
| `conformance/README.md` + `audit-evidence-checklist.md` | Index + audit row | Modify (3 rows) |
| `.github/workflows/ci.yml` | present + N/A + selftest | Modify (3 steps) |
| `VERSION` / `CHANGELOG.md` / `docs/ROADMAP-KIT.md` | Release meta | Modify |

---

### Task 1: Create `conformance/dr-ready.sh`

**Files:**
- Create: `conformance/dr-ready.sh`

- [ ] **Step 1: Confirm the kit root is N/A (pre-check)**

Run:
```bash
ls .env.example 2>&1 | head -1
ls -d prisma migrations db/migrate alembic 2>/dev/null || echo "(no migrations dirs)"
ls compose.yaml compose.yml docker-compose.yml docker-compose.yaml 2>/dev/null || echo "(no root compose)"
```
Expected: no root `.env.example`, no migrations dirs, no root compose. (If any exist, STOP and report — the kit-root N/A assumption is wrong.)

- [ ] **Step 2: Write the script**

Create `conformance/dr-ready.sh` with EXACTLY this content:

```sh
#!/bin/sh
# dr-ready.sh — conditional, fail-closed, ESCALATE-ONLY DR-readiness DOC check.
#
# Companion to conformance/dr-readiness.md (the DR-readiness gate; DEVELOPMENT-PROCESS.md
# §7 + the Definition of Done for data services). For a project that HANDLES PERSISTENT
# DATA it asserts DR is DOCUMENTED and a restore drill is RECORDED: a BIA artifact exists
# (docs/continuity/BIA.md), the RUNBOOK Disaster-recovery section has RPO/RTO filled (not
# the template placeholder), and a restore-drill date is recorded. No data surface -> N/A.
#
# DIRECTIONAL SAFETY — this check ESCALATES, it never EXEMPTS. Detection is deliberately
# conservative (so stateless tools are not nagged), so a MISS is possible. Therefore the
# N/A path is SELF-INCRIMINATING: if the project handles durable data, an N/A is WRONG and
# the human must apply conformance/dr-readiness.md regardless. The script can only ADD a
# requirement, never remove one. The BIA-at-Inception (a human criticality call) is primary.
#
# SCOPE — a green run proves DR is DOCUMENTED and a drill was RECORDED, NOT that the restore
# succeeded or met RTO/RPO. Those are Manual rows in dr-readiness.md (on-call/operator evidence).
#
# Usage:
#   sh conformance/dr-ready.sh [project-dir]   (default: .)
#   sh conformance/dr-ready.sh --selftest
#
# Run at the DR-readiness gate (DEVELOPMENT-PROCESS.md §7) and as recurring maintenance (§15).
set -eu

# Does $1 (a project dir) handle persistent data? Conservative; a MISS escalates, never exempts.
has_data_surface() {
  _d="$1"
  if [ -f "$_d/.env.example" ] && grep -Eiq 'DATABASE_URL|DB_URL|POSTGRES|MYSQL|MARIADB|MONGO|REDIS_URL|CONNECTION_STRING' "$_d/.env.example"; then
    return 0
  fi
  for _md in prisma migrations db/migrate alembic; do
    if [ -d "$_d/$_md" ]; then return 0; fi
  done
  for _cf in "$_d/compose.yaml" "$_d/compose.yml" "$_d/docker-compose.yml" "$_d/docker-compose.yaml"; do
    [ -f "$_cf" ] || continue
    if grep -Eiq 'image:[[:space:]]*"?(postgres|mysql|mariadb|mongo|redis)' "$_cf"; then return 0; fi
  done
  return 1
}

check_dir() {
  dir="$1"
  fail=0

  if ! has_data_surface "$dir"; then
    echo "N/A: $dir has no persistent-data surface (no DB url in .env.example / migrations dir / compose db) — skipping."
    echo "     WARNING: detection is conservative. If this project handles durable data, this N/A is WRONG —"
    echo "     apply conformance/dr-readiness.md manually. This check escalates (detect -> require); it never exempts."
    return 0
  fi

  rb="$dir/RUNBOOK.md"
  bia="$dir/docs/continuity/BIA.md"

  if [ ! -f "$bia" ]; then
    echo "FAIL: data project has no BIA at docs/continuity/BIA.md (run templates/BIA-TEMPLATE.md) — see conformance/dr-readiness.md"
    fail=1
  fi
  if [ ! -f "$rb" ]; then
    echo "FAIL: data project has no RUNBOOK.md (need a Disaster recovery section with RPO/RTO + a recorded drill)"
    return 1
  fi
  if ! grep -Eiq '^#{1,6}[[:space:]].*disaster recovery' "$rb"; then
    echo "FAIL: RUNBOOK.md has no Disaster recovery section"
    fail=1
  fi
  if grep -Fq '[< 24h default]' "$rb" || grep -Fq '[< 4h default]' "$rb"; then
    echo "FAIL: RUNBOOK RPO/RTO still hold the template placeholder ([< 24h default] / [< 4h default]) — set real targets"
    fail=1
  fi
  if ! grep -Eiq 'restore verified:' "$rb"; then
    echo "FAIL: RUNBOOK has no 'Restore verified:' line — record a restore-drill date"
    fail=1
  elif grep -Fiq 'restore verified: [date]' "$rb"; then
    echo "FAIL: 'Restore verified:' still holds the [date] placeholder — run a restore drill and record the date"
    fail=1
  fi

  if [ "$fail" -ne 0 ]; then return 1; fi
  echo "dr-ready: OK — DR is DOCUMENTED and a restore drill is RECORDED. NOTE: this does NOT verify the restore succeeded or met RTO/RPO — those are Manual rows in dr-readiness.md requiring on-call/operator evidence."
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
    echo "selftest PASS: stateless -> N/A (not over-triggered)"
  else
    echo "selftest FAIL: stateless should be N/A"; st_fail=1
  fi

  d3="$base/ok"; mkdir -p "$d3/docs/continuity"
  printf 'DATABASE_URL=postgres://localhost/app\n' > "$d3/.env.example"
  printf '# BIA\ncritical tier: RTO 1h / RPO 15m\n' > "$d3/docs/continuity/BIA.md"
  printf '# RUNBOOK\n\n## Disaster recovery\n- RPO: 1h RTO: 2h\n- Restore verified: 2026-06-01 (passed)\n' > "$d3/RUNBOOK.md"
  if check_dir "$d3" >/dev/null 2>&1; then
    echo "selftest PASS: complete data project -> OK"
  else
    echo "selftest FAIL: complete data project should pass"; st_fail=1
  fi

  d4="$base/placeholder"; mkdir -p "$d4/docs/continuity"
  printf 'DATABASE_URL=postgres://localhost/app\n' > "$d4/.env.example"
  printf '# BIA\n' > "$d4/docs/continuity/BIA.md"
  printf '# RUNBOOK\n\n## Disaster recovery\n- RPO: 1h RTO: 2h\n- Restore verified: [date]\n' > "$d4/RUNBOOK.md"
  if check_dir "$d4" >/dev/null 2>&1; then
    echo "selftest FAIL: [date] placeholder should FAIL"; st_fail=1
  else
    echo "selftest PASS: [date] placeholder -> FAIL as expected"
  fi

  d5="$base/nobia"; mkdir -p "$d5"
  printf 'DATABASE_URL=postgres://localhost/app\n' > "$d5/.env.example"
  printf '# RUNBOOK\n\n## Disaster recovery\n- RPO: 1h RTO: 2h\n- Restore verified: 2026-06-01\n' > "$d5/RUNBOOK.md"
  if check_dir "$d5" >/dev/null 2>&1; then
    echo "selftest FAIL: no-BIA should FAIL"; st_fail=1
  else
    echo "selftest PASS: no-BIA -> FAIL as expected"
  fi

  if [ "$st_fail" -ne 0 ]; then
    echo "dr-ready --selftest: FAIL" >&2
    return 1
  fi
  echo "dr-ready --selftest: OK (na/stateless/ok/placeholder/no-bia all behaved; fixtures left in $base)"
  return 0
}

case "${1:-}" in
  --selftest) selftest ;;
  *)          check_dir "${1:-.}" ;;
esac
exit $?
```

- [ ] **Step 3: Run the self-test**

Run: `sh conformance/dr-ready.sh --selftest; echo "exit=$?"`
Expected: five `selftest PASS:` lines, final `dr-ready --selftest: OK …`, `exit=0`.

- [ ] **Step 4: Run at the kit root (must be N/A, escalate-only warning shown)**

Run: `sh conformance/dr-ready.sh; echo "exit=$?"`
Expected: `N/A: . has no persistent-data surface …` followed by the `WARNING: … this N/A is WRONG …` lines; `exit=0`.

- [ ] **Step 5: Verify the directional-safety + scope wording is present**

Run:
```bash
grep -c "if this project handles durable data, this N/A is WRONG" conformance/dr-ready.sh
grep -c "does NOT verify the restore succeeded or met RTO/RPO" conformance/dr-ready.sh
```
Expected: both `1`.

- [ ] **Step 6: Syntax lint (sh + dash)**

Run: `sh -n conformance/dr-ready.sh && echo "sh OK"` then `command -v dash >/dev/null && dash -n conformance/dr-ready.sh && echo "dash OK" || echo "dash not installed — skipped"`
Expected: `sh OK` (and `dash OK` or skip).

- [ ] **Step 7: Commit**

```bash
chmod +x conformance/dr-ready.sh
git add conformance/dr-ready.sh
git commit -m "feat(conformance): add dr-ready.sh — escalate-only DR-readiness check

Conditional on a persistent-data surface; asserts a BIA artifact, a
filled RUNBOOK DR section, and a recorded restore-drill date. N/A is
self-incriminating (detect -> require, never exempt). Success output
self-discloses scope (recorded != tested). --selftest battery.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Create `conformance/dr-readiness.md`

**Files:**
- Create: `conformance/dr-readiness.md`

- [ ] **Step 1: Create the checklist**

Create `conformance/dr-readiness.md` with EXACTLY this content:

```markdown
# Conformance Check — DR Readiness

Proves **disaster recovery is real**: data classified by criticality (BIA), RTO/RPO tiered, and a restore drill actually run. **Checklist-type**, run at the **DR-readiness gate** (`DEVELOPMENT-PROCESS.md` §7), as **recurring maintenance** (§15), and as part of the **Definition of Done for data services** (`CLAUDE.md`). **Conditional:** projects with no durable data (stateless service, CLI, library) mark the whole check **N/A — no persistent data to recover**. Aligns with NIST SP 800-34 (contingency planning) and the Data Management contract (`DEVELOPMENT-STANDARDS.md` §10).

> **What the Auto rows prove — and don't.** `dr-ready.sh` confirms DR is *written down* (a BIA exists, RUNBOOK RTO/RPO are set, a restore-drill date is recorded). It does **not** verify the restore *succeeded* or *met RTO/RPO* — those are the **Manual** rows, signed off by the on-call/operator with evidence. **A green script is necessary, not sufficient.**

> **The script's `N/A` is advisory only.** Detection of a "persistent-data surface" is deliberately conservative and can miss a data project. **If this project handles durable data, this checklist applies regardless of what `dr-ready.sh` prints.** The script escalates (detect → require); it never exempts. The human-applied checklist is the gate of record.

## How to use
Copy this file into your project (or your DR record). For each item: mark **Applies? (Y / N+reason)** and give **Evidence**. Items tagged *(documented)* are auto-checkable via `sh conformance/dr-ready.sh`; items tagged *(verified)* require the on-call/operator's evidence from an actual drill. The reviewer signs off only when every applicable item has evidence.

## Checklist (blank)

| # | Item | Applies? | Evidence (where/how) | Check |
|---|------|----------|----------------------|-------|
| 1 | BIA done — data/services classified by criticality (`docs/continuity/BIA.md`) *(documented)* | | | **Auto:** `dr-ready.sh` |
| 2 | Per-tier RTO/RPO defined from the BIA (RUNBOOK §6, not placeholder) *(documented)* | | | **Auto:** `dr-ready.sh` |
| 3 | Automated backups configured for production data *(verified)* | | | Manual |
| 4 | Restore drill **run** — date recorded in RUNBOOK §6 *(documented)* | | | **Auto:** `dr-ready.sh` |
| 5 | Restore drill **succeeded** — data actually restored, integrity verified *(verified)* | | | Manual |
| 6 | RTO/RPO **actuals met** the tier targets in the last drill *(verified)* | | | Manual |
| 7 | Backups stored durably + access-controlled (off-host / off-region) *(verified)* | | | Manual |
| 8 | Drill scheduled as recurring maintenance (§15) *(documented)* | | | Manual |

## Worked example — a deployable HTTP service with a Postgres database

| # | Item | Applies? | Evidence | Check |
|---|------|----------|----------|-------|
| 1 | BIA done *(documented)* | Y | `docs/continuity/BIA.md` — 3 tiers, customer data = Critical | Auto ✅ |
| 2 | Per-tier RTO/RPO *(documented)* | Y | RUNBOOK §6: Critical RTO 1h/RPO 15m; Standard RTO 4h/RPO 24h | Auto ✅ |
| 3 | Automated backups *(verified)* | Y | managed Postgres PITR + nightly snapshot (infra console) | Manual ✅ |
| 4 | Drill run — date recorded *(documented)* | Y | RUNBOOK §6 "Restore verified: 2026-06-01" | Auto ✅ |
| 5 | Drill succeeded *(verified)* | Y | restored to isolated env; row-count + checksum match (drill log) | Manual ✅ |
| 6 | RTO/RPO actuals met *(verified)* | Y | restore took 38m (< 1h target); data loss 4m (< 15m) | Manual ✅ |
| 7 | Durable + access-controlled *(verified)* | Y | backups in separate region bucket, IAM-restricted | Manual ✅ |
| 8 | Drill scheduled *(documented)* | Y | quarterly recurring board item (§15) | Manual ✅ |

> A stateless service, CLI, or library marks the whole check **N/A — no persistent data to recover**; `dr-ready.sh` skip-passes such a project automatically. **If your only "data" is an ephemeral cache (e.g. a cache-only `REDIS_URL`), mark N/A — there is no durable data to recover.**
```

- [ ] **Step 2: Verify callout, advisory note, and labels**

Run:
```bash
grep -c "A green script is necessary, not sufficient" conformance/dr-readiness.md
grep -c "this checklist applies regardless of what" conformance/dr-readiness.md
grep -c "(documented)" conformance/dr-readiness.md
grep -c "(verified)" conformance/dr-readiness.md
```
Expected: first `1`; second `1`; third ≥ 4; fourth ≥ 4.

- [ ] **Step 3: Link check**

Run: `sh conformance/check-links.sh; echo "exit=$?"`
Expected: `exit=0`.

- [ ] **Step 4: Commit**

```bash
git add conformance/dr-readiness.md
git commit -m "feat(conformance): add DR-readiness checklist

Conditional checklist (Manual + Auto rows) with a 'necessary not
sufficient' callout and an explicit 'N/A is advisory; checklist applies
regardless' note. NIST 800-34 anchor.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Create `docs/continuity/backup-restore-drill.md`

**Files:**
- Create: `docs/continuity/backup-restore-drill.md`

- [ ] **Step 1: Create the reference**

Create `docs/continuity/backup-restore-drill.md` with EXACTLY this content:

```markdown
# Backup-Restore Drill — Reference

How to **prove** disaster recovery works by actually restoring a backup. Stack-neutral; tooling is a project/Org choice. Aligns with **NIST SP 800-34** (contingency planning). This is the "how" behind the recurring-maintenance item "Backup-restore verification" (`DEVELOPMENT-PROCESS.md` §15) and the DR-readiness check (`conformance/dr-readiness.md`).

> **Do no harm — never drill against production.** A restore drill restores **into an isolated environment** (a scratch database/instance), never over live data. Restoring onto production can destroy the very data you are trying to protect.

## Before you drill — the inputs
- A **BIA** (`templates/BIA-TEMPLATE.md` → `docs/continuity/BIA.md`) that classifies data/services by criticality and sets **per-tier RTO/RPO**.
- A known-good **backup** (snapshot, PITR, dump) for the tier you are drilling.

## The drill, step by step
1. **Pick a tier** from the BIA (drill the most critical tier most often).
2. **Identify the backup** to restore (note its timestamp — this sets the data-loss window).
3. **Restore into an isolated environment** — a fresh DB/instance with no production access.
4. **Verify integrity** — row counts vs. expectation, checksums/hashes, a smoke query on critical tables, referential integrity.
5. **Measure the actuals** — **RTO actual** = wall-clock from "start restore" to "service usable"; **RPO actual** = gap between the backup timestamp and the incident point.
6. **Compare to the tier targets** — actuals must be within the BIA's RTO/RPO for that tier.
7. **Record** — write the date and result in RUNBOOK §6 ("Restore verified: YYYY-MM-DD (passed/failed, RTO/RPO actuals)") and close the recurring board item (§15).

## What "passed" means
- Data restored **and** integrity verified **and** RTO/RPO actuals within the tier targets.
- Recording a date is the **floor**; a *passed* drill (the Manual rows in `conformance/dr-readiness.md`) is the **bar**. A recorded date alone does not prove DR works.

## Cadence
- At least **once per project**, then **on schedule** (recurring maintenance, §15) — quarterly is a sensible default; the most critical tier more often.
- **Pre-launch** for any new data service, and after any change to the backup/restore path.

## Tooling (Org-owned)
Backup mechanism, snapshot scheduling, and the isolated restore environment are platform choices (managed-DB PITR, object-store snapshots, IaC to stand up the scratch env). The kit standardizes the **practice and the proof**, not the tool.
```

- [ ] **Step 2: Link check**

Run: `sh conformance/check-links.sh; echo "exit=$?"`
Expected: `exit=0`.

- [ ] **Step 3: Commit**

```bash
git add docs/continuity/backup-restore-drill.md
git commit -m "docs(continuity): add backup-restore drill reference

Stack-neutral restore-drill how-to: isolated-env do-no-harm rule, the
6-step drill, RTO/RPO actuals, recorded != passed. NIST 800-34 anchor.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Create `templates/BIA-TEMPLATE.md`

**Files:**
- Create: `templates/BIA-TEMPLATE.md`

- [ ] **Step 1: Create the template**

Create `templates/BIA-TEMPLATE.md` with EXACTLY this content:

```markdown
# [Project] — Business Impact Analysis (BIA)

> **Template.** Classifies the project's data and services by criticality and sets recovery targets (RTO/RPO) per tier. Produced at **Inception** for any project that handles durable data (`START-HERE.md` §6); the filled copy lives at `docs/continuity/BIA.md` and feeds RUNBOOK §6 and the DR-readiness check (`conformance/dr-readiness.md`). Aligns with **NIST SP 800-34**.

**Owner:** [name / role] · **Date:** [date] · **Review cadence:** [e.g. annually + on major change]

## How to use
- Fill every section in plain language. Revisit when the data model or dependencies change.
- The tiers and targets you set here are the contract the restore drill (`docs/continuity/backup-restore-drill.md`) is measured against.

---

## 1. Data & service inventory
> What data and services exist, and what each holds.

| Data / service | What it holds | Owner |
|----------------|---------------|-------|
| [e.g. customer DB] | [PII, orders] | [team] |

## 2. Criticality classification
> Classify each by impact of loss/unavailability. Suggested tiers: Critical · Important · Deferrable.

| Data / service | Tier | Impact if lost or unavailable |
|----------------|------|-------------------------------|
| [customer DB] | [Critical] | [regulatory + revenue + trust] |

## 3. Recovery targets (RTO / RPO) per tier
> RTO = how fast you must be back. RPO = how much data loss is tolerable.

| Tier | RTO (max downtime) | RPO (max data loss) |
|------|--------------------|---------------------|
| Critical | [e.g. 1h] | [e.g. 15m] |
| Important | [e.g. 4h] | [e.g. 24h] |
| Deferrable | [e.g. 72h] | [e.g. 1 week] |

## 4. Dependencies
> Upstream/downstream systems and third parties whose failure affects recovery.

[...]

## 5. Maximum tolerable downtime & notes
> The point beyond which downtime causes unacceptable / irreversible harm; any regulatory recovery obligations.

[...]
```

- [ ] **Step 2: Link check**

Run: `sh conformance/check-links.sh; echo "exit=$?"`
Expected: `exit=0`.

- [ ] **Step 3: Commit**

```bash
git add templates/BIA-TEMPLATE.md
git commit -m "feat(templates): add BIA-TEMPLATE (criticality tiers + per-tier RTO/RPO)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Tiered RTO/RPO in STANDARDS §10 + RUNBOOK §6

**Files:**
- Modify: `DEVELOPMENT-STANDARDS.md` (§10, line 148)
- Modify: `templates/RUNBOOK-TEMPLATE.md` (§6 Disaster recovery)

- [ ] **Step 1: Update STANDARDS §10**

Find this EXACT line:
```
- **Retention & DR** — define RPO/RTO in the RUNBOOK (sensible defaults: RPO < 24h, RTO < 4h).
```
Replace with:
```
- **Retention & DR** — define RPO/RTO in the RUNBOOK (sensible defaults: RPO < 24h, RTO < 4h); **for multi-criticality systems, tier them by data criticality from the BIA** (`templates/BIA-TEMPLATE.md`). Prove restore with a drill (`docs/continuity/backup-restore-drill.md`) — a recorded drill is the floor, a passed drill is the bar.
```

- [ ] **Step 2: Update the RUNBOOK §6 Disaster recovery section**

Find this EXACT block:
```
## 6. Disaster recovery
- **RPO:** [< 24h default] · **RTO:** [< 4h default]
- Backups: [cadence, location] · Restore verified: [date] (recurring-maintenance item)
```
Replace with:
```
## 6. Disaster recovery
- **RPO:** [< 24h default] · **RTO:** [< 4h default]
- **Per-tier targets (multi-criticality systems, from the BIA — `docs/continuity/BIA.md`):**

  | Tier | RTO | RPO |
  |------|-----|-----|
  | [Critical] | [1h] | [15m] |
  | [Standard] | [4h] | [24h] |

- Backups: [cadence, location] · Restore verified: [date] (recurring-maintenance item — see `docs/continuity/backup-restore-drill.md`)
```

- [ ] **Step 3: Verify**

Run:
```bash
grep -c "tier them by data criticality from the BIA" DEVELOPMENT-STANDARDS.md
grep -c "Per-tier targets" templates/RUNBOOK-TEMPLATE.md
sh conformance/check-links.sh; echo "exit=$?"
```
Expected: first `1`; second `1`; links `exit=0`.

> Note: the RUNBOOK still contains the `[< 24h default]` and `Restore verified: [date]` placeholders — that is correct; `dr-ready.sh` FAILs a real project until those are replaced, which is the enforcement.

- [ ] **Step 4: Commit**

```bash
git add DEVELOPMENT-STANDARDS.md templates/RUNBOOK-TEMPLATE.md
git commit -m "feat(standards): tiered RTO/RPO by criticality (§10 + RUNBOOK §6)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: BIA step in START-HERE (Inception) + conditional Inception-Done line

**Files:**
- Modify: `START-HERE.md` (§6 per-project config + the Inception-Done checklist)

- [ ] **Step 1: Add the BIA bullet to §6**

Find this EXACT line (the last bullet of "## 6. Per-project configuration"):
```
- **WIP limits** and **environments** (local → staging? → prod)
```
Insert this bullet DIRECTLY AFTER it:
```
- **Business continuity** *(data-handling projects)* — run a BIA (`templates/BIA-TEMPLATE.md` → `docs/continuity/BIA.md`); set per-tier RTO/RPO in RUNBOOK §6; schedule the restore drill (`docs/continuity/backup-restore-drill.md`). Not required for stateless tools.
```

- [ ] **Step 2: Add a conditional Inception-Done line**

Find this EXACT line (in the "✅ Inception Done" checklist):
```
- [ ] Roles assigned
```
Insert this line DIRECTLY AFTER it:
```
- [ ] *(data-handling projects)* BIA done (`docs/continuity/BIA.md`); per-tier RTO/RPO set; restore drill scheduled
```

- [ ] **Step 3: Verify**

Run:
```bash
grep -c "Business continuity" START-HERE.md
grep -c "BIA done" START-HERE.md
sh conformance/check-links.sh; echo "exit=$?"
```
Expected: first `1`; second `1`; links `exit=0`.

> Note: `inception-done.sh` is intentionally NOT modified — the BIA is a prompt at Inception, enforced later by DR-readiness (the Definition of Done anchor in Task 8).

- [ ] **Step 4: Commit**

```bash
git add START-HERE.md
git commit -m "docs(inception): add BIA step + conditional Inception-Done line (data projects)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: Wire §15 recurring ref + §7 DR-readiness gate

**Files:**
- Modify: `DEVELOPMENT-PROCESS.md` (§15 line 423; §7 line 186 + line 190)

- [ ] **Step 1: Reference the drill doc from the §15 recurring item**

Find this EXACT line:
```
- Backup-restore verification (prove DR actually works)
```
Replace with:
```
- Backup-restore verification (prove DR actually works — how: `docs/continuity/backup-restore-drill.md`; gate: `conformance/dr-readiness.md`)
```

- [ ] **Step 2: Add the §7 DR-readiness gate row**

Find this EXACT line:
```
| **Definition of Deployable** *(deployable services)* | Is the release safe to promote — rollback ready, smoke + monitoring wired? (`conformance/definition-of-deployable.md`) | Release manager + reviewer |
```
Insert this row DIRECTLY AFTER it:
```
| **DR readiness** *(data services)* | Is DR provable — BIA done, RTO/RPO tiered, restore drill passed? (`conformance/dr-readiness.md`) | On-call / operator + reviewer |
```

- [ ] **Step 3: Update the conditional-gates sentence**

Find this EXACT text:
```
Threat-model, eval, compliance, 15-factor, and Definition-of-Deployable gates are **conditional** — they apply to sensitive / AI / regulated / deployable-service work respectively, not every item (don't impose them where they optimize nothing).
```
Replace with:
```
Threat-model, eval, compliance, 15-factor, Definition-of-Deployable, and DR-readiness gates are **conditional** — they apply to sensitive / AI / regulated / deployable-service / data-handling work respectively, not every item (don't impose them where they optimize nothing).
```

- [ ] **Step 4: Verify**

Run:
```bash
grep -c "docs/continuity/backup-restore-drill.md" DEVELOPMENT-PROCESS.md
grep -cF "**DR readiness** *(data services)*" DEVELOPMENT-PROCESS.md
grep -c "and DR-readiness gates are" DEVELOPMENT-PROCESS.md
sh conformance/check-links.sh; echo "exit=$?"
```
Expected: first ≥ 1; second `1` (fixed-string match on the gate row); third `1`; links `exit=0`.

- [ ] **Step 5: Commit**

```bash
git add DEVELOPMENT-PROCESS.md
git commit -m "feat(process): DR-readiness conditional gate (§7) + drill ref (§15)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: Anchor DR-readiness in the Definition of Done

**Files:**
- Modify: `CLAUDE.md` (DoD Production line, line 70)

- [ ] **Step 1: Append the DR anchor to the DoD Production line**

Find this EXACT line:
```
**Production** — deployed · smoke-tested · no errors in logs · rollback path ready · monitoring/alerting on critical paths.
```
Replace with:
```
**Production** — deployed · smoke-tested · no errors in logs · rollback path ready · monitoring/alerting on critical paths · **DR proven for data services** (`conformance/dr-readiness.md`).
```

- [ ] **Step 2: Verify**

Run:
```bash
grep -c "DR proven for data services" CLAUDE.md
sh conformance/check-links.sh; echo "exit=$?"
```
Expected: first `1`; links `exit=0`.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "feat(dod): DR proven for data services in the Definition of Done

Anchors the DR-readiness gate to a checkpoint nothing ships past —
backstops the BIA-as-Inception-prompt (a data service is not 'done'
without a passed DR-readiness check).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 9: Index the checks (README + audit-evidence)

**Files:**
- Modify: `conformance/README.md` (index, after the deployable rows)
- Modify: `conformance/audit-evidence-checklist.md` (after the RUNBOOK DR/rollback row)

- [ ] **Step 1: Add two README index rows**

Find this EXACT row:
```
| `deployable-ready.sh` | script | `DEVELOPMENT-PROCESS.md` §10 — documented release-safety (RUNBOOK deploy/rollback + smoke); pairs with the checklist | Release / CI (conditional on a deploy surface) |
```
Insert these two rows DIRECTLY AFTER it:
```
| `dr-readiness.md` | checklist | `DEVELOPMENT-STANDARDS.md` §10 / NIST 800-34 (DR is provable) | Review / recurring / DoD (conditional) |
| `dr-ready.sh` | script | `DEVELOPMENT-STANDARDS.md` §10 — documented DR (BIA + RUNBOOK §6 + recorded drill); escalate-only; pairs with the checklist | Review / CI (conditional on a data surface) |
```

- [ ] **Step 2: Add the audit-evidence row**

Find this EXACT row:
```
| RUNBOOK · DR / rollback | CC7.4, CC7.5 / A.5.29, A.8.13 | RUNBOOK | Manual (file present) | |
```
Insert this row DIRECTLY AFTER it:
```
| DR drill · backup-restore | CC7.5, A1.2 / A.5.29, A.8.13, A.8.14 | BIA (`docs/continuity/BIA.md`) + RUNBOOK §6 + recorded drill date + drill log | **Auto (conditional):** `sh conformance/dr-ready.sh` | |
```

- [ ] **Step 3: Verify**

Run:
```bash
grep -c "dr-readiness.md" conformance/README.md
grep -c "dr-ready.sh" conformance/README.md
grep -c "DR drill · backup-restore" conformance/audit-evidence-checklist.md
sh conformance/check-links.sh; echo "exit=$?"
```
Expected: first `1`; second `1`; third `1`; links `exit=0`.

- [ ] **Step 4: Commit**

```bash
git add conformance/README.md conformance/audit-evidence-checklist.md
git commit -m "docs(conformance): index dr-readiness + dr-ready; DR-drill audit row

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 10: Dogfood in kit CI

**Files:**
- Modify: `.github/workflows/ci.yml` (conformance job — after the deployable-ready selftest step)

- [ ] **Step 1: Find the insertion point**

Run: `grep -n "Deployable-ready self-test" .github/workflows/ci.yml`
Expected: one match. Insert the new steps directly after its `run:` line (the last steps of the `conformance` job, before `bootstrap:`).

- [ ] **Step 2: Add the three steps**

After the `run: sh conformance/deployable-ready.sh --selftest` line, insert (6-space `- name:`, 8-space `run:`):
```yaml
      - name: DR-readiness checklist present
        run: test -f conformance/dr-readiness.md
      - name: DR-ready conditional (N/A at kit root)
        run: sh conformance/dr-ready.sh
      - name: DR-ready self-test (na/stateless/ok/placeholder/no-bia fixtures)
        run: sh conformance/dr-ready.sh --selftest
```

- [ ] **Step 3: Verify placement + commands pass locally**

Run:
```bash
grep -n "DR-ready self-test" .github/workflows/ci.yml
sed -n '26,40p' .github/workflows/ci.yml
sh conformance/dr-ready.sh; echo "na=$?"
sh conformance/dr-ready.sh --selftest; echo "selftest=$?"
test -f conformance/dr-readiness.md && echo "checklist present"
```
Expected: the steps are the tail of the `conformance` job (before `bootstrap:`); `na=0`, `selftest=0`, "checklist present".

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: dogfood dr-ready (present + N/A + selftest)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 11: Version bump, CHANGELOG, ROADMAP

**Files:**
- Modify: `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-KIT.md`

- [ ] **Step 1: Bump VERSION**

Replace the contents of `VERSION` (`2.20.0`) with:
```
2.21.0
```

- [ ] **Step 2: Add the CHANGELOG entry**

Insert this entry IMMEDIATELY ABOVE the `## [2.20.0] - 2026-06-09` line:
```markdown
## [2.21.0] - 2026-06-09

Slice 8c — DR / backup-restore drill + BIA-at-Inception. Third sub-slice of Slice 8 (continuity & safe-delivery hardening). Closes gap A2 (DR was prose-only — no reference, no drill proof, no criticality tiering, no BIA). NIST SP 800-34 anchor.

### Added
- **`docs/continuity/backup-restore-drill.md`** — a stack-neutral restore-drill reference: the isolated-env do-no-harm rule, the 6-step drill, RTO/RPO actuals, and "recorded ≠ passed".
- **`templates/BIA-TEMPLATE.md`** — a Business Impact Analysis (data inventory, criticality tiers, per-tier RTO/RPO, dependencies, max tolerable downtime). Produced at Inception for data-handling projects.
- **`conformance/dr-readiness.md`** — a conditional DR-readiness checklist (Manual judgment rows + Auto rows) with a "necessary, not sufficient" callout and an explicit "the script's N/A is advisory; this checklist applies regardless" note.
- **`conformance/dr-ready.sh`** — a conditional, fail-closed, **escalate-only** companion: for a project with a persistent-data surface it asserts a BIA exists, RUNBOOK RTO/RPO are filled (not placeholder), and a restore-drill date is recorded; otherwise N/A. Its `N/A` is **self-incriminating** (detection is conservative, so a miss never exempts a data project) and its success output self-discloses scope (documented + recorded ≠ tested). `--selftest` battery.
- **Tiered RTO/RPO** by data criticality — `DEVELOPMENT-STANDARDS.md` §10 + RUNBOOK §6 per-tier table.
- **BIA-at-Inception** — a `START-HERE.md` §6 step + a conditional Inception-Done line (data projects); `inception-done.sh` unchanged (a prompt, not a hard gate).
- **`DEVELOPMENT-PROCESS.md`** — a conditional **DR readiness** gate (§7); the §15 recurring item references the drill.
- **Definition of Done anchor** — "DR proven for data services" on the `CLAUDE.md` Production line, so a data service is not "done" without a passed DR-readiness check (backstops the Inception prompt).
- **`audit-evidence-checklist.md`** — a DR-drill row (CC7.5, A1.2 / A.5.29, A.8.13–14; Auto-conditional).

### Note
MINOR (2.21.0): additive — a conditional gate, a conditional DoD item (data services, like the existing AI-eval / accessibility DoD items), a template, and references. No new universally-required CI gate; the 8 application gate-ids and §14 are unchanged.
```

- [ ] **Step 3: Add the ROADMAP row**

In `docs/ROADMAP-KIT.md`, insert this row IMMEDIATELY AFTER the `8b ✅` row:
```
| 8c ✅ | **DR / backup-restore + BIA** *(shipped v2.21.0)* | standards §10 + process §7/§15 + DoD (NIST 800-34) | drill reference + `BIA-TEMPLATE` + `dr-readiness.md` + `dr-ready.sh` (escalate-only) | `dr-ready.sh --selftest` + `check-links.sh` |
```

- [ ] **Step 4: Verify**

Run:
```bash
cat VERSION
grep -c "## \[2.21.0\]" CHANGELOG.md
grep -c "8c ✅" docs/ROADMAP-KIT.md
sh conformance/check-links.sh; echo "exit=$?"
```
Expected: `2.21.0`; `1`; `1`; links `exit=0`.

- [ ] **Step 5: Commit**

```bash
git add VERSION CHANGELOG.md docs/ROADMAP-KIT.md
git commit -m "chore(release): 2.21.0 — DR / backup-restore + BIA (8c)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 12: Full conformance sweep + push + PR (stop for ratification)

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
sh conformance/dr-ready.sh; echo "dr-root=$?"
sh conformance/dr-ready.sh --selftest; echo "dr-selftest=$?"
```
Expected: `links=0`, no `FAIL` from ci-gates, `profiles=0`, `autonomy=0`, `containers=0`, `backlog=0`, `guard=0`, `deployable-selftest=0`, `dr-root=0` (N/A), `dr-selftest=0`.

- [ ] **Step 2: Final spec-coverage greps**

Run:
```bash
ls conformance/dr-ready.sh conformance/dr-readiness.md docs/continuity/backup-restore-drill.md templates/BIA-TEMPLATE.md
grep -c "if this project handles durable data, this N/A is WRONG" conformance/dr-ready.sh   # 1
grep -c "DR proven for data services" CLAUDE.md                                            # 1
grep -c "this checklist applies regardless of what" conformance/dr-readiness.md            # 1
cat VERSION                                                                                 # 2.21.0
```

- [ ] **Step 3: Confirm clean tree + push**

```bash
git status --short    # only the pre-existing untracked .firecrawl/
git push -u origin feature/slice-8c-dr-backup-restore
```

- [ ] **Step 4: Open the PR (do NOT merge — human ratification gate)**

```bash
gh pr create --title "Slice 8c — DR / backup-restore drill + BIA-at-Inception (v2.21.0)" \
  --body "$(cat <<'EOF'
Closes gap A2 (Slice 8 arc) — the continuity centerpiece. Turns DR from an unverified claim into a provable capability.

## What
- **`docs/continuity/backup-restore-drill.md`** — restore-drill reference (isolated-env do-no-harm rule, 6-step drill, RTO/RPO actuals, recorded != passed). NIST 800-34.
- **`templates/BIA-TEMPLATE.md`** — Business Impact Analysis (criticality tiers + per-tier RTO/RPO), produced at Inception.
- **`conformance/dr-readiness.md` + `dr-ready.sh`** — conditional DR-readiness pair (data services). Checklist Manual rows hold the judgment (drill *succeeded*, RTO *met*); the script auto-verifies the documented floor (BIA present, RUNBOOK §6 filled, drill date recorded).
- **Tiered RTO/RPO** (§10 + RUNBOOK §6); **BIA-at-Inception** step (`START-HERE` §6 + conditional Inception-Done line); **DR-readiness** §7 gate; §15 references the drill.

## Directional safety (raised + remedied at design review)
A continuity gate's dangerous error is a **false negative** (a data project missed -> ships with unproven DR). So:
- **`dr-ready.sh` is escalate-only**: its `N/A` is *self-incriminating* ("if you handle durable data this N/A is WRONG — apply the checklist"); the script can require, never exempt.
- **DR-readiness is anchored to the Definition of Done** ("DR proven for data services", `CLAUDE.md`), so the BIA-as-Inception-prompt is backstopped by a gate nothing ships past.
- Same anti-false-assurance as 8b: documented + recorded != tested; the on-call/operator signs the Manual rows. Wording grep-asserted in CI.

## Verification
All conformance green; `dr-ready.sh --selftest` 5/5 in CI; `sh -n` + `dash -n` clean; **MINOR -> 2.21.0** (conditional gate + conditional DoD item; no new CI gate-id; §14 unchanged).

## Governance
Governing-doc surface (PROCESS §7/§15, STANDARDS §10, CLAUDE.md DoD) -> **security-owner lens**. Agent does not self-merge — this PR stops for human ratification.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 5: STOP for human ratification**

Do not merge. Report the PR URL + green conformance to Bradley (governing-doc change → security-owner lens per §13/RBAC).

---

## Self-Review

**1. Spec coverage:**
- Deliverable A (drill reference) → Task 3. ✅
- Deliverable B (BIA template) → Task 4. ✅
- Deliverable C (checklist) → Task 2. ✅
- Deliverable D (script, escalate-only, --selftest) → Task 1. ✅
- Deliverable E (§10 tiered) → Task 5 Step 1. ✅
- Deliverable F (RUNBOOK §6) → Task 5 Step 2. ✅
- Deliverable G (START-HERE BIA step + Inception-Done line) → Task 6. ✅
- Deliverable H (§15 ref + §7 gate) → Task 7. ✅
- Deliverable I (README + audit) → Task 9. ✅
- Deliverable J (CI) → Task 10. ✅
- Deliverable K (DoD anchor) → Task 8. ✅
- Meta → Task 11. ✅
- Escalate-only N/A + self-incriminating wording (§2/§6) → Task 1 (script + grep), Task 12 grep. ✅
- N/A-is-advisory checklist note (§6) → Task 2 (note + grep). ✅
- DoD anchor (§2) → Task 8 + grep. ✅

**2. Placeholder scan:** `[...]`, `[date]`, `[< 24h default]`, `[Critical]` are intended template/RUNBOOK fill-ins (house style), not plan placeholders. The script, checklist, reference, and BIA template are given in full. No "TBD/implement later" in plan instructions. ✅

**3. Consistency:** `dr-ready.sh`, `dr-readiness.md`, `docs/continuity/BIA.md`, `docs/continuity/backup-restore-drill.md`, `templates/BIA-TEMPLATE.md` names are identical across every task, CI, README, audit row, DoD, CHANGELOG, ROADMAP. The self-incriminating string in Task 1 Step 2 ("if this project handles durable data, this N/A is WRONG") matches the greps in Task 1 Step 5 and Task 12 Step 2. The scope string ("does NOT verify the restore succeeded or met RTO/RPO") matches Task 1 Step 5. The BIA artifact path `docs/continuity/BIA.md` is consistent between `dr-ready.sh` (Task 1), the checklist (Task 2), the BIA template (Task 4), START-HERE (Task 6), and §10 (Task 5). The selftest fixtures' RUNBOOK content (Deploy/DR headings, "Restore verified" with real vs `[date]`) matches the checks in `check_dir`. ✅
