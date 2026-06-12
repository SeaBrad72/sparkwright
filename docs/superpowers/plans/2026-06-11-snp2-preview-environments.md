# SNP-2 — Ephemeral / Preview Environments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-PR **ephemeral preview environments** to the env model + a light conditional `preview-env-ready` check — Slice 2 of the Safe Non-Prod arc, closing it (and the deferred list). Seeds from SNP-1 test data.

**Architecture:** `preview-env-ready.sh` mirrors `observability-ready.sh` exactly (deploy-surface trigger + N/A·OK·FAIL·`--selftest`, **colon-adjacent record** per the SNP-1 fix). `docs/operations/preview-environments.md` is a stack-neutral guidance doc. `preview-environments-readiness.md` mirrors `observability-readiness.md`. PROCESS §9 gains a tight preview-env contract line.

**Tech Stack:** POSIX sh (dash-clean; `set -eu`), Markdown, GitHub Actions YAML (CI step folds in — **bundled with the deferred SNP-1 test-data step**; one manual YAML edit on this branch).

**Release:** `VERSION` → 2.52.0; MINOR.

**Honesty invariant:** a green `preview-env-ready` proves the preview-env approach is **recorded**, never that envs *actually* spin up / tear down / isolate / exclude prod data. Those are Manual operator rows.

**Doc-budget (tight):** `DEVELOPMENT-PROCESS.md` 466/470 — **only ~4 lines headroom.** The §9 preview-env addition must be ≤2 lines. `DEVELOPMENT-STANDARDS.md` 313/320. Run `doc-budget.sh` after the PROCESS edit; if it would breach, compress to a single line.

**Governance:** branch `feature/safe-nonprod-snp2-preview-envs` (created; this plan lives here) → PR → **Bradley merges**. PROCESS edit → security-owner lens. **CI step bundles the SNP-1 + SNP-2 selftests into one manual YAML edit on this branch** (proper manual-edit instructions, not a shell block). Generic/anonymized ([[kit-anonymization]]).

---

## File Structure
- Create: `docs/operations/preview-environments.md` (Task 1).
- Modify: `DEVELOPMENT-PROCESS.md` §9 — preview-env contract (Task 2).
- Modify: `templates/RUNBOOK-TEMPLATE.md` — `Preview environments:` record line, §4 (Task 2).
- Create: `conformance/preview-env-ready.sh` (Task 3), `conformance/preview-environments-readiness.md` (Task 4).
- Modify: `conformance/verify.sh`, `conformance/README.md`, `conformance/audit-evidence-checklist.md` (Task 5).
- Modify (control-plane, Bradley applies on branch): `.github/workflows/ci.yml` — bundle SNP-1 + SNP-2 steps (Task 6).
- Modify: `VERSION`, `CHANGELOG.md`, `README.md` (Task 7).

---

## Task 1: Preview-environments guidance doc

**Files:** Create `docs/operations/preview-environments.md`

- [ ] **Step 1: Write it**

```markdown
# Ephemeral / Preview Environments

A **per-PR throwaway environment** so reviewers exercise a change *running*, not just read the diff — accelerating Review/Acceptance. Stack-neutral; the tool (Vercel/Netlify previews · Argo/Helm-per-PR · Heroku review apps · a namespace-per-PR) is a project choice. Pairs with the env model (`DEVELOPMENT-PROCESS.md` §9).

## Lifecycle
1. **Open PR** → deploy an isolated environment (namespace / DB / URL per PR).
2. **Reviewers exercise it** → the running change, with safe data.
3. **Merge / close** → **auto-teardown** (no orphaned environments).

## Security guardrails (the kit's value-add)
- **Safe data only** — seed with synthetic/masked test data (`test-data-management.md`); **never prod data** in a preview.
- **Scoped, short-lived credentials** — per-PR, least-privilege, auto-expiring (ties to containment / scoped tokens); **no prod secrets** in a preview.
- **TTL + auto-teardown** — a preview that outlives its PR is forgotten attack surface; enforce a TTL and tear down on merge/close.
- **Isolation** — one PR's preview cannot reach another's data or prod.

## What the readiness check proves — and doesn't
`conformance/preview-env-ready.sh` confirms a deployable project **records** its preview-env approach (RUNBOOK §4). It does **not** verify envs actually spin up, tear down, isolate, or exclude prod data — those are **Manual** operator rows (`preview-environments-readiness.md`). Necessary, not sufficient. Recommended, not required — a tiny tool may mark it N/A-with-reason.
```

- [ ] **Step 2: Links + commit.** `sh conformance/check-links.sh` → OK.
```bash
git add docs/operations/preview-environments.md
git commit -m "docs(operations): preview-environments — per-PR isolated env lifecycle + security guardrails (SNP-2)"
```

---

## Task 2: PROCESS §9 contract + RUNBOOK record line

**Files:** Modify `DEVELOPMENT-PROCESS.md` (§9 Environments & promotion), `templates/RUNBOOK-TEMPLATE.md` (§4 Deploy)

- [ ] **Step 1: PROCESS §9** — after the "collapse tiers" paragraph (currently ~line 253), add a **single tight line** (budget: ≤2 lines):
```
**Ephemeral preview environments** *(recommended for deployable services)* — a per-PR isolated environment seeded with **safe test data** (§9 / `docs/operations/test-data-management.md`), **scoped short-lived credentials**, a **TTL/auto-teardown** on merge/close, and **never prod data or secrets**; it accelerates Review/Acceptance. Declared in RUNBOOK §4 (`conformance/preview-environments-readiness.md`); reference `docs/operations/preview-environments.md`.
```
Run `sh conformance/doc-budget.sh` immediately — if PROCESS would exceed 470, compress the line (drop the parenthetical examples). Confirm ≤470.

- [ ] **Step 2: RUNBOOK §4 Deploy** — add a **colon-adjacent** record line (the SNP-1 lesson — keyword then colon, parenthetical after the value):
```
- **Preview environments:** [approach] *(deployable services — per-PR isolated, safe test data, scoped creds, auto-teardown; see `docs/operations/preview-environments.md`)*
```

- [ ] **Step 3:** `sh conformance/check-links.sh && sh conformance/doc-budget.sh` → OK. Commit:
```bash
git add DEVELOPMENT-PROCESS.md templates/RUNBOOK-TEMPLATE.md
git commit -m "feat(process+templates): preview-environments §9 contract + RUNBOOK §4 record (SNP-2)"
```

---

## Task 3: `preview-env-ready.sh`

**Files:** Create `conformance/preview-env-ready.sh` (mirror `observability-ready.sh`)

- [ ] **Step 1: Write the script**

```sh
#!/bin/sh
# preview-env-ready.sh — conditional, fail-closed preview-environment-record check (Safe Non-Prod, SNP-2).
#
# Companion to conformance/preview-environments-readiness.md. For a project with a DEPLOY SURFACE it
# asserts the preview-environment approach is RECORDED: the RUNBOOK §4 has a "Preview environments:"
# line (not the [approach] placeholder). Non-deployable projects are N/A (skip-pass).
#
# SCOPE — a green run proves the approach is RECORDED, NOT that previews actually spin up, tear down,
# isolate, or exclude prod data. Those are Manual operator rows in preview-environments-readiness.md.
# Recommended, not required — a tiny tool may record "N/A — Dev->Prod" and still pass (it records an
# approach). Necessary, not sufficient.
#
# Usage:
#   sh conformance/preview-env-ready.sh [project-dir]   (default: .)
#   sh conformance/preview-env-ready.sh --selftest
set -eu

# Does $1 (a workflow file) indicate a deploy surface? (same signals as observability-ready.sh)
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
    echo "N/A: $dir has no deploy surface (no Dockerfile / deploy workflow) — no preview environments to declare"
    return 0
  fi

  rb="$dir/RUNBOOK.md"
  if [ ! -f "$rb" ]; then
    echo "FAIL: $dir is deployable but has no RUNBOOK.md (need a Preview-environments record) — see conformance/preview-environments-readiness.md"
    return 1
  fi
  # Record string must stay in sync with templates/RUNBOOK-TEMPLATE.md §4.
  if ! grep -Eiq 'preview environments:' "$rb"; then
    echo "FAIL: RUNBOOK has no 'Preview environments:' record — declare the per-PR approach (or 'N/A — <reason>')"
    fail=1
  elif grep -Eiq 'preview environments:.*\[approach\]' "$rb"; then
    echo "FAIL: 'Preview environments:' still holds the [approach] placeholder — record a real approach"
    fail=1
  fi
  if [ "$fail" -ne 0 ]; then return 1; fi
  echo "preview-env-ready: OK — preview-environment approach is RECORDED. NOTE: does NOT verify previews actually spin up / tear down / isolate / exclude prod data — those are Manual rows (preview-environments-readiness.md)."
  return 0
}

# mktemp fixtures; outcomes asserted. Fixtures LEFT in place (no rm -rf; 7e guard).
selftest() {
  st=0
  base=$(mktemp -d)

  d="$base/na"; mkdir -p "$d"; printf '# a library\n' > "$d/README.md"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest PASS: no-deploy-surface -> N/A"; else echo "selftest FAIL: no-surface should be N/A"; st=1; fi

  # recorded fixture mirrors the real RUNBOOK template shape (bold key + parenthetical), filled
  d="$base/ok"; mkdir -p "$d"
  printf 'FROM scratch\n' > "$d/Dockerfile"
  printf '# RUNBOOK\n\n## 4. Deploy\n- **Preview environments:** namespace-per-PR via Helm, synthetic data, auto-teardown on close *(scoped creds)*\n' > "$d/RUNBOOK.md"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest PASS: deployable + recorded -> OK"; else echo "selftest FAIL: recorded should pass"; st=1; fi

  d="$base/placeholder"; mkdir -p "$d"
  printf 'FROM scratch\n' > "$d/Dockerfile"
  printf '# RUNBOOK\n- **Preview environments:** [approach] *(deployable services — see docs/operations/preview-environments.md)*\n' > "$d/RUNBOOK.md"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest FAIL: [approach] placeholder should FAIL"; st=1; else echo "selftest PASS: [approach] placeholder -> FAIL"; fi

  d="$base/missing"; mkdir -p "$d"
  printf 'FROM scratch\n' > "$d/Dockerfile"
  printf '# RUNBOOK\n\n## 4. Deploy\n- deploy: kubectl apply\n' > "$d/RUNBOOK.md"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest FAIL: missing preview record should FAIL"; st=1; else echo "selftest PASS: missing record -> FAIL"; fi

  if [ "$st" -ne 0 ]; then echo "preview-env-ready --selftest: FAIL" >&2; return 1; fi
  echo "preview-env-ready --selftest: OK (na/recorded/placeholder/missing all behaved; fixtures left in $base)"
  return 0
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  *)          check_dir "${1:-.}"; exit $? ;;
esac
```

- [ ] **Step 2: chmod + syntax + selftest + kit-root + coupling (BOTH paths — the SNP-1 lesson)**
```bash
chmod +x conformance/preview-env-ready.sh
dash -n conformance/preview-env-ready.sh && echo "dash OK"
sh conformance/preview-env-ready.sh --selftest
sh conformance/preview-env-ready.sh; echo "kit-root exit=$?"   # kit root: no Dockerfile/deploy wf at root -> N/A exit 0
# coupling: fresh template (deploy fixture) -> FAIL; FILLED -> OK
t=$(mktemp -d); printf 'FROM scratch\n' > "$t/Dockerfile"; cp templates/RUNBOOK-TEMPLATE.md "$t/RUNBOOK.md"
sh conformance/preview-env-ready.sh "$t" >/dev/null 2>&1; echo "fresh exit=$? (expect 1)"
sed 's/\*\*Preview environments:\*\* \[approach\]/**Preview environments:** namespace-per-PR, synthetic data, auto-teardown/' templates/RUNBOOK-TEMPLATE.md > "$t/RUNBOOK.md"
sh conformance/preview-env-ready.sh "$t"; echo "filled exit=$? (expect 0)"
```
Expected: dash OK; 4/4 selftest; kit-root N/A exit 0; fresh→FAIL(1); **filled→OK(0)**.
> **Kit-root note:** the kit root has profile Dockerfiles under `profiles/*/`, not a root `Dockerfile`, and `.github/workflows/ci.yml` is not a deploy workflow (no `environment:` / `deploy*:` job) — so the root is N/A. Confirm; if it binds, that is a real signal.

- [ ] **Step 3: Commit**
```bash
git add conformance/preview-env-ready.sh
git commit -m "feat(conformance): preview-env-ready.sh — conditional preview-env-record check (deploy-surface trigger) (SNP-2)"
```

---

## Task 4: `preview-environments-readiness.md` checklist

**Files:** Create `conformance/preview-environments-readiness.md` (mirror `observability-readiness.md`)

- [ ] **Step 1: Write it**

```markdown
# Conformance Check — Preview-Environments Readiness

Proves a **deployable project** declares how it runs **per-PR preview environments** — or records an explicit N/A. **Checklist-type**, run at Review and as recurring maintenance. **Conditional:** non-deployable projects mark the whole check **N/A — no deploy surface**. Verifies the lifecycle + guardrails in `docs/operations/preview-environments.md` and the env model in `DEVELOPMENT-PROCESS.md` §9.

> **What the Auto row proves — and doesn't.** `preview-env-ready.sh` confirms the approach is *recorded* (a RUNBOOK §4 "Preview environments:" line). It does **not** verify previews actually spin up, tear down, isolate, or exclude prod data. Those are the **Manual** operator rows. **A green script is necessary, not sufficient.**

## Checklist (blank)
| # | Item | Applies? | Evidence | Check |
|---|------|----------|----------|-------|
| 1 | Preview-env approach recorded (RUNBOOK §4) *(documented)* | | | **Auto:** `preview-env-ready.sh` |
| 2 | Previews actually spin up per PR *(verified)* | | | Manual |
| 3 | Previews **auto-tear-down** on merge/close (no orphans) *(verified)* | | | Manual |
| 4 | Seeded with safe (synthetic/masked) data — **no prod data** *(verified)* | | | Manual |
| 5 | Scoped short-lived credentials; **no prod secrets** in preview *(verified)* | | | Manual |
| 6 | Isolation — one PR's preview cannot reach another's data or prod *(verified)* | | | Manual |

> A non-deployable project (library, CLI, batch) marks the whole check **N/A — no deploy surface**; `preview-env-ready.sh` skip-passes it automatically.
```

- [ ] **Step 2:** Links + commit.
```bash
git add conformance/preview-environments-readiness.md
git commit -m "docs(conformance): preview-environments-readiness checklist (Auto: recorded; Manual: spin-up/teardown/isolation/no-prod-data) (SNP-2)"
```

---

## Task 5: Wiring (verify.sh · README · audit)

- [ ] **Step 1: verify.sh** — after the `test-data-ready` row, add:
```
check doc     preview-env-ready sh conformance/preview-env-ready.sh
```
- [ ] **Step 2: conformance/README.md** — add a row + name `preview-env-ready.sh` in the documentation/evidence bullet:
```
| `preview-env-ready.sh` | script | Safe Non-Prod — the preview-environment approach is recorded (RUNBOOK §4: per-PR isolated, safe data, auto-teardown); conditional on a deploy surface. Pairs with `preview-environments-readiness.md` / `../docs/operations/preview-environments.md` | Review / CI (conditional on a deploy surface) |
```
- [ ] **Step 3: audit-evidence-checklist.md** — add a row after the test-data row:
```
| Preview environments · per-PR safety (if deploy surface) | CC8.1, CC6.1 / A.8.31 (env separation) | RUNBOOK §4 preview-env record + teardown/isolation evidence | **Auto (conditional):** `sh conformance/preview-env-ready.sh` (+ Manual spin-up/teardown/no-prod-data) | |
```
- [ ] **Step 4: Verify** — `sh conformance/verify.sh` (doc-checks now **8**) · `doc-budget` · `check-links` → green. Commit:
```bash
git add conformance/verify.sh conformance/README.md conformance/audit-evidence-checklist.md
git commit -m "docs(conformance): wire preview-env readiness — verify.sh + README/audit rows (SNP-2)"
```

---

## Task 6: CI selftest steps — bundle SNP-1 + SNP-2 (one manual YAML edit on this branch)

The deferred SNP-1 `test-data-ready` step never landed (the prior handoff was an unrunnable shell block). Bundle **both** steps into one manual edit on this branch, so they ride in this PR.

- [ ] **Step 1:** Give Bradley a **manual-edit instruction** (not a shell block): open `.github/workflows/ci.yml`, find the line `run: sh conformance/responsible-ai-ready.sh --selftest`, and **paste these four lines immediately after it** (same indentation):
```yaml
      - name: Test-data-ready self-test (non-prod data discipline)
        run: sh conformance/test-data-ready.sh --selftest
      - name: Preview-env-ready self-test (per-PR preview discipline)
        run: sh conformance/preview-env-ready.sh --selftest
```
Then `git add .github/workflows/ci.yml && git commit -m "ci(snp): test-data + preview-env selftests" && git push` on this branch — so both ride in this one PR. The agent cannot edit `.github/workflows/`.

---

## Task 7: Release v2.52.0 + verification + PR

- [ ] **Step 1:** `VERSION` → `2.52.0`.
- [ ] **Step 2:** CHANGELOG `## [2.52.0] - <date>`: preview-environments doc + §9 contract + `preview-env-ready` check + RUNBOOK record; **closes the Safe Non-Prod arc** (+ the whole deferred list); conditional (N/A non-deployed); seeds from SNP-1.
- [ ] **Step 3:** README badge → `v2.52.0`; `badge-version.sh` → OK.
- [ ] **Step 4: Full verification**
```bash
dash -n conformance/preview-env-ready.sh && echo "dash OK"
sh conformance/preview-env-ready.sh --selftest
sh conformance/preview-env-ready.sh; echo "kit-root exit=$?"   # N/A exit 0
sh conformance/check-links.sh && sh conformance/doc-budget.sh && sh conformance/badge-version.sh && echo "aux OK"
sh conformance/verify.sh 2>&1 | tail -4   # 8 doc-checks
```
- [ ] **Step 5:** Commit release: `chore(release): 2.52.0 — SNP-2 preview environments (Safe Non-Prod arc CLOSED)`.
- [ ] **Step 6: Independent security-owner review** over the branch diff: honesty (recorded ≠ actually-isolated); trigger correctness (no-deploy → N/A, deploy+placeholder → FAIL, deploy+missing → FAIL, **fresh→FAIL AND filled→OK** — the SNP-1 lesson); POSIX/dash + set-e; the security guardrails (no prod data/secrets, teardown, scoped creds) are correctly **Manual**; doc-budget (PROCESS ≤470). Fold Critical/High/Medium.
- [ ] **Step 7:** Push + open PR (Bradley merges; the CI bundle from Task 6 should already be on the branch). Title `SNP-2 — ephemeral/preview environments (v2.52.0) — closes the Safe Non-Prod arc`. Report PR # + merge command. Do not self-merge.

---

## Verification (whole slice)
- `preview-env-ready.sh`: `dash -n` clean; `--selftest` 4/4; kit-root N/A (exit 0); **fresh→FAIL and filled→OK** (both paths — the SNP-1 lesson).
- `verify.sh` RESULT: OK at **8 doc-checks**; `check-links`/`doc-budget` (PROCESS ≤470)/`badge-version` green.
- Conditional: non-deployed → N/A. Guardrails (no prod data/secrets, teardown, isolation) are Manual.

## Out of scope (this slice)
- Running the preview infra / a specific tool — Org-owned; named as references.
- Closes the Safe Non-Prod arc and the deferred list. Next frontier (separate): the pre-story product-discovery front end.
