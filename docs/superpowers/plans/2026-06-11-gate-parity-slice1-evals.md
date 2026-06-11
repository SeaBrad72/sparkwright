# Gate Parity — Slice 1: Eval-driven development Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the AI-feature **Eval gate** the kit's declared-artifact + conformance treatment — an `EVAL-PLAN` template, an `eval-readiness.md` checklist, a conditional `eval-ready.sh` check, and the §14/verify.sh/CI wiring.

**Architecture:** Mirror the `resilience-ready` family. `eval-ready.sh` is conditional + fail-closed: it **binds** when the repo signals an AI feature (an `evals/` dir, an `EVAL-PLAN.md`, or a RUNBOOK/`CLAUDE.md` `AI feature: yes` marker) and asserts the eval *discipline is declared* (plan present · regression threshold recorded · harness/gate located) — **not** that evals pass (that stays the §7 Eval gate running in CI). N/A for non-AI projects.

**Tech Stack:** POSIX `sh` (dash-clean) + markdown. No new runtime deps.

**Spec:** `docs/superpowers/specs/2026-06-11-gate-parity-design.md` (Slice 1).

**Honesty invariant:** `eval-ready.sh` verifies the discipline is **declared/recorded**, never that evals *pass* — that is the §7 Eval gate (CI runs the suite). Same "necessary, not sufficient" framing as `resilience-ready`.

---

## File structure

| File | Change | Responsibility |
|------|--------|----------------|
| `templates/EVAL-PLAN-TEMPLATE.md` | CREATE | the AI-feature eval artifact (dataset/rubric · threshold · red-team · judge · harness · model-upgrade trigger) |
| `conformance/eval-ready.sh` | CREATE | conditional check (AI-feature trigger; declared-discipline assertions) + `--selftest` |
| `conformance/eval-readiness.md` | CREATE | Auto-vs-Manual checklist |
| `conformance/README.md` · `conformance/audit-evidence-checklist.md` | MODIFY | index row · audit-evidence row |
| `conformance/verify.sh` | MODIFY | `check doc eval-ready` |
| `DEVELOPMENT-STANDARDS.md` · `CLAUDE.md` | MODIFY | §14 Eval-gate readiness pointer + AI-Eval section pointer · templates list |
| `.github/workflows/ci.yml` | MODIFY (control-plane `cp`) | `eval-ready.sh --selftest` step |
| `VERSION` · `README.md` · `CHANGELOG.md` | MODIFY | release v2.46.0 |

Branch: `feature/gate-parity-evals` (created off main; spec committed on it).

---

## Task 1: `templates/EVAL-PLAN-TEMPLATE.md`

**Files:** Create `templates/EVAL-PLAN-TEMPLATE.md`

- [ ] **Step 1: Create the file** with exactly this content:

```markdown
# Eval Plan — TEMPLATE

> **Template.** The dev-time quality bar for an **AI feature** (any behaviour that depends on a model or prompt) — *evals are the test suite* (`DEVELOPMENT-STANDARDS.md` §AI Evaluations). Produced at **Plan**, enforced at the **§7 Eval gate** (the suite runs in CI; a drop below threshold fails the build), and grown from production misses + retros. Its *presence* makes a project an AI feature for `conformance/eval-ready.sh`. Stack-specific harness → your `profiles/<stack>.md` (e.g. the `ml` profile ships `evals/run.py`).

> **What the readiness check proves — and doesn't.** `eval-ready.sh` confirms this plan is *declared*: a recorded regression threshold and a located harness/gate. It does **not** run the evals or prove they pass — that is the §7 Eval gate in CI, and the red-team/judge-independence items below are **Manual**. A green readiness check is necessary, not sufficient.

## Feature
- **AI feature:** yes
- **What the model/prompt does:** [one line]

## Task-quality evals (the dataset + rubric)
- **Dataset:** [path / size / how curated — golden set, versioned with the code]
- **Scoring:** [exact-match | graded rubric | LLM-as-judge]
- **Pinned judge + model version:** [e.g. claude-sonnet-4-6 as judge; system-under-test model + version]

## Regression bar (the §7 gate)
- **Regression threshold:** [threshold]   <!-- e.g. "score >= 0.85; no metric drops > 2pts vs baseline" — the bar the CI Eval gate enforces. Replace [threshold] with a real value. -->
- **Harness:** [harness]   <!-- where the suite lives + how the gate runs it, e.g. "evals/run.py, pytest-driven, run in CI on any prompt/model/param change". Replace [harness]. -->
- **Model-upgrade regression:** on any model / prompt / parameter change, the suite re-runs before merge (the gate's trigger).

## Safety / red-team (Manual)
- [ ] Adversarial prompts / jailbreaks tested before shipping
- [ ] Harmful-output checks run
- [ ] Judge is independent of the system under test (no self-grading)

## Quality tracking
- **Eval score trend:** [where tracked] — a decline is tech debt, surfaced at retro.
```

- [ ] **Step 2: Link check + commit.**

Run: `sh conformance/check-links.sh 2>&1 | tail -1` → `OK: all relative Markdown links resolve`.

```bash
git add templates/EVAL-PLAN-TEMPLATE.md
git commit -m "feat(templates): EVAL-PLAN template — the AI-feature eval artifact (dataset/rubric, threshold, red-team, judge, harness)"
```

---

## Task 2: `conformance/eval-ready.sh`

**Files:** Create `conformance/eval-ready.sh`

- [ ] **Step 1: Write the full script.**

```sh
#!/bin/sh
# eval-ready.sh — conditional, fail-closed eval-discipline-declared check (gate parity, Slice 1).
#
# Companion to conformance/eval-readiness.md (the §7 Eval gate readiness; DEVELOPMENT-PROCESS.md §7).
# For an AI FEATURE it asserts the eval discipline is DECLARED: an EVAL-PLAN with a recorded
# regression threshold and a located harness/gate (not the [threshold]/[harness] placeholders).
# Non-AI projects (no model/prompt) are N/A (skip-pass).
#
# SCOPE — a green run proves the eval discipline is DECLARED, NOT that the evals PASS. The actual
# pass/regression is the §7 Eval gate (the suite runs in CI). Red-team + judge-independence are
# Manual rows in eval-readiness.md. A green run is necessary, not sufficient.
#
# Usage:
#   sh conformance/eval-ready.sh [project-dir]   (default: .)
#   sh conformance/eval-ready.sh --selftest
# Exit: 0 = OK or N/A · 1 = FAIL (AI feature with the discipline undeclared). POSIX sh; dash-clean.
set -eu

# Is $1 an AI feature? (any of: an evals/ dir, an EVAL-PLAN, or a RUNBOOK/CLAUDE 'AI feature: yes')
is_ai_feature() {
  _d="$1"
  [ -d "$_d/evals" ] && return 0
  for p in "$_d/EVAL-PLAN.md" "$_d/docs/EVAL-PLAN.md" "$_d/evals/EVAL-PLAN.md"; do
    [ -f "$p" ] && return 0
  done
  for m in "$_d/RUNBOOK.md" "$_d/CLAUDE.md"; do
    [ -f "$m" ] && grep -Eiq 'ai feature:[[:space:]]*(yes|true)' "$m" && return 0
  done
  return 1
}

# Echo the EVAL-PLAN path if one exists, else empty.
find_plan() {
  for p in "$1/EVAL-PLAN.md" "$1/docs/EVAL-PLAN.md" "$1/evals/EVAL-PLAN.md"; do
    [ -f "$p" ] && { printf '%s' "$p"; return 0; }
  done
  return 1
}

check_dir() {
  dir="$1"
  if ! is_ai_feature "$dir"; then
    echo "N/A: $dir is not an AI feature (no evals/ dir, no EVAL-PLAN, no 'AI feature: yes' marker) — no eval gate to declare"
    return 0
  fi
  fail=0
  plan=$(find_plan "$dir" || true)
  if [ -z "$plan" ]; then
    echo "FAIL: $dir is an AI feature but has no EVAL-PLAN.md — create one from templates/EVAL-PLAN-TEMPLATE.md"
    return 1
  fi
  # Record strings below must stay in sync with templates/EVAL-PLAN-TEMPLATE.md.
  # Placeholder detection keys on the literal [threshold]/[harness] tokens (robust to the
  # template's **bold** keys, which put `**` between the colon and the value).
  if ! grep -Eiq 'regression threshold:' "$plan"; then
    echo "FAIL: $plan has no 'Regression threshold:' — record the §7 Eval gate bar"; fail=1
  elif grep -Eiq 'regression threshold:.*\[threshold\]' "$plan"; then
    echo "FAIL: 'Regression threshold:' still holds the [threshold] placeholder — record a real bar"; fail=1
  fi
  if ! grep -Eiq 'harness:' "$plan"; then
    echo "FAIL: $plan has no 'Harness:' — locate the eval suite + how the gate runs it"; fail=1
  elif grep -Eiq 'harness:.*\[harness\]' "$plan"; then
    echo "FAIL: 'Harness:' still holds the [harness] placeholder — locate the real harness/gate"; fail=1
  fi
  if [ "$fail" -ne 0 ]; then return 1; fi
  echo "eval-ready: OK — eval discipline is DECLARED (EVAL-PLAN present, threshold + harness recorded). NOTE: does NOT run the evals or prove they pass — that is the §7 Eval gate in CI; red-team/judge-independence are Manual (eval-readiness.md)."
  return 0
}

# mktemp fixtures; assert each outcome. Fixtures LEFT in place (no rm -rf; 7e guard).
selftest() {
  st=0
  base=$(mktemp -d)
  PLAN_OK='# Eval Plan\n- **Regression threshold:** score >= 0.85, no metric drops > 2pts\n- **Harness:** evals/run.py, pytest-driven, run in CI on model/prompt change\n'

  d="$base/not-ai"; mkdir -p "$d"; printf '# a CLI tool\n' > "$d/README.md"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest PASS: non-AI -> N/A"; else echo "selftest FAIL: non-AI should be N/A"; st=1; fi

  d="$base/ai-evalsdir-noplan"; mkdir -p "$d/evals"; printf 'x\n' > "$d/evals/run.py"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest FAIL: AI(evals/) + no plan should FAIL"; st=1; else echo "selftest PASS: AI(evals/) + no plan -> FAIL"; fi

  d="$base/ai-marker-complete"; mkdir -p "$d"
  printf '# RUNBOOK\nAI feature: yes\n' > "$d/RUNBOOK.md"
  printf '%b' "$PLAN_OK" > "$d/EVAL-PLAN.md"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest PASS: AI(marker) + complete plan -> OK"; else echo "selftest FAIL: complete plan should pass"; st=1; fi

  d="$base/ai-plan-threshold-placeholder"; mkdir -p "$d"
  printf '# Eval Plan\n- **Regression threshold:** [threshold]\n- **Harness:** evals/run.py\n' > "$d/EVAL-PLAN.md"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest FAIL: [threshold] placeholder should FAIL"; st=1; else echo "selftest PASS: [threshold] placeholder -> FAIL"; fi

  d="$base/ai-plan-harness-placeholder"; mkdir -p "$d"
  printf '# Eval Plan\n- **Regression threshold:** score >= 0.9\n- **Harness:** [harness]\n' > "$d/EVAL-PLAN.md"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest FAIL: [harness] placeholder should FAIL"; st=1; else echo "selftest PASS: [harness] placeholder -> FAIL"; fi

  if [ "$st" -ne 0 ]; then echo "eval-ready --selftest: FAIL" >&2; return 1; fi
  echo "eval-ready --selftest: OK (non-ai/no-plan/complete/threshold-placeholder/harness-placeholder all behaved; fixtures left in $base)"
  return 0
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  *)          check_dir "${1:-.}"; exit $? ;;
esac
```

- [ ] **Step 2: Make executable, dash-check, selftest, kit-root N/A.**

Run: `chmod +x conformance/eval-ready.sh && dash -n conformance/eval-ready.sh && echo "syntax OK"` → `syntax OK`.
Run: `sh conformance/eval-ready.sh --selftest` → 5 `selftest PASS` lines then `eval-ready --selftest: OK ...`, exit 0.
Run: `sh conformance/eval-ready.sh; echo "exit=$?"` → at the kit root, expect `N/A: . is not an AI feature ...` and `exit=0` (the kit is a framework, not an AI feature).

- [ ] **Step 3: Commit.**

```bash
git add conformance/eval-ready.sh
git commit -m "feat(conformance): eval-ready.sh — conditional eval-discipline-declared check (AI-feature trigger; threshold + harness recorded)"
```

---

## Task 3: `conformance/eval-readiness.md` + README + audit-evidence

**Files:** Create `conformance/eval-readiness.md`; Modify `conformance/README.md`, `conformance/audit-evidence-checklist.md`

- [ ] **Step 1: Write the checklist** (mirrors `resilience-readiness.md`):

```markdown
# Conformance Check — Eval Readiness

Proves an **AI feature** holds a dev-time quality bar: outputs are scored against a versioned dataset + rubric, a **regression threshold** gates CI, and safety/red-team checks run before shipping. **Checklist-type**, run at the **§7 Eval gate** (`DEVELOPMENT-PROCESS.md` §7) and as **recurring maintenance** (§15). **Conditional:** a project with no model/prompt marks the whole check **N/A — not an AI feature**. Verifies the discipline asserted in `DEVELOPMENT-STANDARDS.md` (AI Evaluations / eval-driven development).

> **What the Auto rows prove — and don't.** `eval-ready.sh` confirms the eval discipline is *declared* (an EVAL-PLAN with a recorded regression threshold and a located harness/gate). It does **not** run the evals, prove they pass, or run the red-team — that is the §7 Eval gate in CI plus the **Manual** rows below. **A green script is necessary, not sufficient.**

## How to use
Produce an `EVAL-PLAN.md` from `templates/EVAL-PLAN-TEMPLATE.md`. Items tagged *(documented)* are auto-checkable via `sh conformance/eval-ready.sh`; items tagged *(verified)* require the actual eval/red-team run.

## Checklist (blank)

| # | Item | Applies? | Evidence (where/how) | Check |
|---|------|----------|----------------------|-------|
| 1 | `EVAL-PLAN.md` present *(documented)* | | | **Auto:** `eval-ready.sh` |
| 2 | Regression threshold recorded (the §7 gate bar) *(documented)* | | | **Auto:** `eval-ready.sh` |
| 3 | Harness/gate located (suite + how CI runs it) *(documented)* | | | **Auto:** `eval-ready.sh` |
| 4 | Eval suite **passes** at/above threshold in CI *(verified)* | | | Manual / §7 Eval gate |
| 5 | Regression checked on the latest model/prompt/param change *(verified)* | | | Manual / §7 Eval gate |
| 6 | Safety / red-team set **run** (jailbreaks, harmful-output) *(verified)* | | | Manual |
| 7 | Judge independent of the system under test (no self-grading) *(verified)* | | | Manual |

> A non-AI project (CLI, library, batch job with no model) marks the whole check **N/A — not an AI feature**; `eval-ready.sh` skip-passes it automatically.
```

- [ ] **Step 2: `conformance/README.md` index row.** After the `resilience-ready.sh` row (`grep -n 'resilience-ready.sh' conformance/README.md`), add:

```markdown
| `eval-ready.sh` | script | gate parity — the AI-feature **eval discipline is declared** (EVAL-PLAN + regression threshold + harness/gate recorded); conditional (N/A for non-AI). Does NOT run evals — that is the §7 Eval gate. Pairs with `eval-readiness.md` | Review / CI (conditional on an AI feature) |
```

- [ ] **Step 3: `audit-evidence-checklist.md` row.** After the `Container image supply-chain` row (`grep -n 'Container image supply-chain' conformance/audit-evidence-checklist.md`), add:

```markdown
| AI-feature eval discipline (if AI feature) | CC8.1 / A.8.29 / PW.7 | EVAL-PLAN (threshold + harness) + the §7 Eval gate run | **Auto (conditional):** `sh conformance/eval-ready.sh` (+ the CI Eval gate for execution) | |
```

- [ ] **Step 4: Link-check + commit.**

Run: `sh conformance/check-links.sh 2>&1 | tail -1`.

```bash
git add conformance/eval-readiness.md conformance/README.md conformance/audit-evidence-checklist.md
git commit -m "docs(conformance): eval-readiness checklist (Auto vs Manual) + README + audit-evidence rows"
```

---

## Task 4: Wiring — `verify.sh` + `DEVELOPMENT-STANDARDS.md` + `CLAUDE.md`

**Files:** Modify `conformance/verify.sh`, `DEVELOPMENT-STANDARDS.md`, `CLAUDE.md`

- [ ] **Step 1: `verify.sh` — add eval-ready as a doc check.** Find the `check doc resilience-ready …` line (`grep -n 'check doc' conformance/verify.sh`) and add after it:

```sh
check doc     eval-ready       sh conformance/eval-ready.sh
```

- [ ] **Step 2: `DEVELOPMENT-STANDARDS.md` — point the Eval gate at the readiness checklist.** Find the conditional-gates `**Eval**` line:

```markdown
- **Eval** *(AI features)* — model/prompt output meets the eval bar and does not regress; `DEVELOPMENT-PROCESS.md` §7.
```
Replace with (adds the readiness pointer, matching the Load line; no new line):
```markdown
- **Eval** *(AI features)* — model/prompt output meets the eval bar and does not regress; `DEVELOPMENT-PROCESS.md` §7; readiness `conformance/eval-readiness.md`, plan `templates/EVAL-PLAN-TEMPLATE.md`.
```

- [ ] **Step 3: `DEVELOPMENT-STANDARDS.md` — point the AI-Evaluations section at the template.** Find the AI-Evaluations `**Discipline**` bullet (it ends `**→ profile** for the eval harness.`) and append to that bullet: ` Plan it with `templates/EVAL-PLAN-TEMPLATE.md`; readiness `conformance/eval-ready.sh`.`

- [ ] **Step 4: `CLAUDE.md` — add to the templates list (line 17).** Insert `EVAL-PLAN` into the `templates/` comma list (no new line):

Find: `..., \`SPEC\`, \`TASK-CONTEXT-CONTRACT\`, \`POSTMORTEM\`, \`BIA\`.`
Replace: `..., \`SPEC\`, \`TASK-CONTEXT-CONTRACT\`, \`EVAL-PLAN\`, \`POSTMORTEM\`, \`BIA\`.`

- [ ] **Step 5: Verify budget + links + verify.sh.**

Run: `sh conformance/doc-budget.sh; echo "exit=$?"` → PASS, exit 0 (STANDARDS edits are ≤ existing-line appends; if over budget, STOP and report — do not trim).
Run: `sh conformance/check-links.sh 2>&1 | tail -1` → OK.
Run: `sh conformance/verify.sh 2>&1 | tail -1` → `RESULT: OK` (eval-ready joins as a doc check; N/A at kit root).

- [ ] **Step 6: Commit.**

```bash
git add conformance/verify.sh DEVELOPMENT-STANDARDS.md CLAUDE.md
git commit -m "docs(standards): wire eval readiness — §14 Eval gate pointer + AI-Eval section + verify.sh doc check + templates list"
```

---

## Task 5: CI wiring (control-plane `cp`)

**Files:** Modify `.github/workflows/ci.yml` (control-plane — human `cp`)

- [ ] **Step 1: Build the CI candidate.** Read `.github/workflows/ci.yml`; with Read/Write tools (NOT a shell command naming `ci.yml`) write `/tmp/ci.yml.evals` = the live file with one step added in the `conformance` job immediately after the `Assurance-tiers drift-guard self-test …` step:

```yaml
      - name: Eval-ready self-test (AI-feature eval discipline)
        run: sh conformance/eval-ready.sh --selftest
```

Validate: `diff .github/workflows/ci.yml /tmp/ci.yml.evals` → only the two added lines; `python3 -c 'import yaml;print(",".join(yaml.safe_load(open("/tmp/ci.yml.evals"))["jobs"].keys()))' 2>/dev/null || grep -E '^  [a-z-]+:$' /tmp/ci.yml.evals` → `conformance,bootstrap,docs-links`.

- [ ] **Step 2: Hand Bradley the control-plane `cp`.** Present exactly:

```bash
cd /Users/bradleyjames/Development/agentic-sdlc-kit && KIT_GUARD_SELFEDIT=1 sh -c '
  cp /tmp/ci.yml.evals .github/workflows/ci.yml &&
  git add .github/workflows/ci.yml &&
  git commit -m "ci(gate-parity): run eval-ready.sh --selftest in the conformance job"
'
```
Wait for confirmation before continuing.

---

## Task 6: Release (VERSION / CHANGELOG / badge)

**Files:** Modify `VERSION`, `README.md`, `CHANGELOG.md`

- [ ] **Step 1: `VERSION`** → `2.46.0`: `printf '2.46.0\n' > VERSION`.
- [ ] **Step 2: Badge.** `sh conformance/badge-version.sh --fix && sh conformance/badge-version.sh; echo "exit=$?"` → PASS, exit 0.
- [ ] **Step 3: CHANGELOG** — insert above `## [2.45.0] - …` (no `[2.46.0]:` link-def):

```markdown
## [2.46.0] - 2026-06-11

Gate parity, Slice 1 — eval-driven development gets the kit's declared-artifact + conformance treatment. The AI-feature Eval gate was named in prose but lacked a template and a readiness check; this closes that. **MINOR** — additive template + conditional check; no new universal gate.

### Added
- **`templates/EVAL-PLAN-TEMPLATE.md`** — the AI-feature eval artifact (dataset + rubric, regression threshold, safety/red-team, pinned judge + model version, harness, model-upgrade-regression trigger).
- **`conformance/eval-ready.sh`** + **`conformance/eval-readiness.md`** — conditional check (binds on an AI-feature signal: `evals/` dir, `EVAL-PLAN.md`, or `AI feature: yes`) asserting the eval discipline is **declared** (plan + threshold + harness recorded); N/A for non-AI. Wired into `verify.sh` + CI.

### Honesty
- The readiness check proves the discipline is **declared**, never that the evals **pass** — execution stays the §7 Eval gate (CI runs the suite); red-team + judge-independence are Manual rows. Necessary, not sufficient.
```

- [ ] **Step 4: Verify + commit.**

Run: `cat VERSION && sh conformance/check-links.sh 2>&1 | tail -1`.

```bash
git add VERSION README.md CHANGELOG.md
git commit -m "chore(release): 2.46.0 — gate parity Slice 1 (eval-driven development)"
```

---

## Task 7: Final verify + independent security-owner review + PR

- [ ] **Step 1: Full verify (post-`cp`).**

```sh
sh conformance/eval-ready.sh --selftest >/dev/null && echo "eval-ready selftest OK"
sh conformance/eval-ready.sh >/dev/null && echo "kit-root N/A OK"
sh conformance/resilience-ready.sh --selftest >/dev/null && echo "resilience selftest OK (pattern regression)"
sh conformance/check-links.sh >/dev/null && echo "links OK"
sh conformance/doc-budget.sh >/dev/null && echo "doc-budget OK"
sh conformance/badge-version.sh >/dev/null && echo "badge OK"
sh conformance/verify.sh 2>&1 | tail -1
```
Expected: all OK; `verify.sh` RESULT: OK (now includes the eval-ready doc check).

- [ ] **Step 2: Independent security-owner-lens review** (governing-doc + a new gate-readiness check). Dispatch a reviewer against `git diff main...HEAD`: confirm (a) the EVAL-PLAN template + eval-ready key-phrases are in sync (the script greps `Regression threshold:` / `Harness:` exactly as the template writes them; a fresh template reads as FAIL via the `[threshold]`/`[harness]` placeholders — verify no false PASS); (b) the AI-feature trigger doesn't over-bind (a non-AI repo is N/A) or under-bind (an `evals/` dir with no plan FAILs, not N/A); (c) the honesty framing holds (declared ≠ evals pass; the §7 gate does execution); (d) dash-clean, no fixture `rm -rf`; (e) the §14/standards edits add a pointer and weaken nothing; (f) `doc-budget`/`verify.sh` green. Fold cheap findings; carry the rest.

- [ ] **Step 3: Push + open PR** (Bradley merges).

```bash
git push -u origin feature/gate-parity-evals
gh pr create --base main --head feature/gate-parity-evals --title "Gate parity Slice 1 — eval-driven development (v2.46.0)" --body "<summary: AI-feature Eval gate gets EVAL-PLAN template + eval-ready conditional check + readiness checklist + §14/verify/CI wiring; declared ≠ evals-pass (execution stays §7 gate); conditional/N-A for non-AI; MINOR>"
```

- [ ] **Step 4: Report** PR number + merge command + note Slice 2 (observability + threat-model) is next from the same arc spec.

---

## Verification (whole slice)

- `eval-ready.sh --selftest` → 5 PASS, exit 0; kit root → N/A, exit 0.
- Fresh `EVAL-PLAN-TEMPLATE.md` (with `[threshold]`/`[harness]`) → FAIL through the check (no false PASS); a completed plan → OK.
- An `evals/` dir without a plan → FAIL (the AI feature that most needs the nudge doesn't escape). A non-AI repo → N/A.
- `verify.sh` RESULT: OK; `doc-budget`/`check-links`/`badge` green; resilience-ready regression green.
- Governance: feature branch → PR → human ratification; `ci.yml` via control-plane `cp`; security-owner lens on the standards edits.
