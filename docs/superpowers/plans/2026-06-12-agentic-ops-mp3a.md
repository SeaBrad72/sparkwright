# Agentic-Ops MP-3a — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the agent-run observability *contract* — a stack/harness-neutral trace schema, a `docs/operations/agentic-ops.md` reference, and the `agentops-ready.sh` conformance trio + declaration wiring — so a project can declare its agent-ops discipline and have it conformance-checked. (The working Claude Code emitter is the separate fast-follow MP-3a.2; the behavior→tier loop is MP-3b.)

**Architecture:** Mirror the proven "readiness-check trio" (e.g. `observability-ready.sh`): a POSIX-sh conditional, fail-closed, three-state check + a `*-readiness.md` checklist (Auto vs Manual rows) + a colon-adjacent record line in the RUNBOOK template + a per-project `CLAUDE.md` config line. The reference doc carries the trace schema (sensor) and the sensor→§13-tier model (actuator). Honesty invariant: green = posture **declared**, not that traces exist or the agent behaved.

**Tech Stack:** POSIX `sh` (dash-clean), Markdown. No new runtime deps. Conventions reused: `conformance/observability-ready.sh` (sibling structure), `conformance/verify.sh` (doc-check rows), `templates/RUNBOOK-TEMPLATE.md` §8, `conformance/audit-evidence-checklist.md`.

**Branch:** `feature/agentic-ops-mp3a` (already created; the design spec `docs/superpowers/specs/2026-06-12-agentic-ops-design.md` is committed on it).

---

## Conventions every task obeys

- **Three-state exit:** `0` = OK or N/A (skip-pass); `1` = FAIL (triggered + posture absent/placeholder); the aggregate maps `2` = UNVERIFIED but this check has no remote dependency, so it only emits 0/1.
- **Colon-adjacent record line (SNP-1 lesson):** the RUNBOOK record MUST be `**Agent-ops:** [value]` — the colon directly after the key — so a filled value is matched by `grep -i 'agent-ops:'`. A parenthetical before the colon would make a filled value never match → false FAIL. **Coupling-test BOTH directions: fresh template → FAIL, filled value → OK.**
- **`--selftest` leaves fixtures in place** (7e guard: no `rm -rf` of mktemp dirs).
- **Honesty:** every "OK" message states what is proven (declared) and what is NOT (traces emit / agent behaved → Manual rows).
- **Doc budget:** after any core-doc edit run `sh conformance/doc-budget.sh`. PROCESS is at 468/470; the core-doc pointer goes on **STANDARDS Factor 14** (4 lines headroom) as a +1, not PROCESS.
- **Commit after each task.** Conventional Commits.

---

## File Structure

- **Create** `conformance/agentops-ready.sh` — the conditional, fail-closed, three-state check + `--selftest`.
- **Create** `conformance/agentic-ops-readiness.md` — the checklist companion (Auto rows = declared; Manual rows = operator evidence).
- **Create** `docs/operations/agentic-ops.md` — the reference: trace schema (required core + recommended), sensor→§13-tier model, multi-agent principle, emitter patterns (dev-time transcript / runtime OTel), honesty boundary.
- **Modify** `templates/RUNBOOK-TEMPLATE.md` §8 — add the `**Agent-ops:** [trace]` colon-adjacent record line.
- **Modify** `templates/PROJECT-CLAUDE-TEMPLATE.md` — add a one-line agent-ops posture config entry.
- **Modify** `DEVELOPMENT-STANDARDS.md` Factor 14 readiness bullet — append a one-line pointer to agentic-ops (budget-checked).
- **Modify** `conformance/verify.sh` — add `check doc agentops-ready sh conformance/agentops-ready.sh`.
- **Modify** `conformance/README.md` — add `agentops-ready.sh` to the line-20 "documentation / evidence" bucket list **and** the checks table (the canonical check registry; the top-level `README.md` does not enumerate checks).
- **Modify** `conformance/audit-evidence-checklist.md` — add the Auto + Manual rows.
- **Hand-apply (control-plane, Bradley):** `.github/workflows/ci.yml` — add the `agentops-ready.sh --selftest` step. (The agent prepares the exact diff; the guard blocks the agent from staging `.github/workflows/`.)

---

## Task 1: The conformance check `agentops-ready.sh` (TDD via `--selftest`)

**Files:**
- Create: `conformance/agentops-ready.sh`

The check is **conditional on the project being agentic**. Trigger signal (cheap, declarative, harness-neutral): the project's `CLAUDE.md` or `RUNBOOK.md` contains an `Agentic: yes` marker. Non-agentic projects → **N/A (skip-pass)**. When triggered, it asserts the RUNBOOK has a filled `Agent-ops:` trace record (not the `[trace]` placeholder).

- [ ] **Step 1: Write the script with its own `--selftest` as the test harness**

This check has no external dependency, so its `--selftest` (mktemp fixtures) IS the failing-test-first. Create `conformance/agentops-ready.sh`:

```sh
#!/bin/sh
# agentops-ready.sh — conditional, fail-closed agent-ops-record check (MP-3a).
#
# Companion to conformance/agentic-ops-readiness.md (the Agent-ops readiness gate;
# DEVELOPMENT-PROCESS.md §7 / §13). For an AGENTIC project it asserts the agent-ops
# posture is RECORDED: RUNBOOK §8 has an "Agent-ops:" trace record (not the template
# [trace] placeholder). Non-agentic projects are N/A (skip-pass) — no agent runs to trace.
#
# SCOPE — a green run proves the posture was RECORDED, NOT that traces actually emit, are
# complete, or that the agent behaved (process-conformance). Those are Manual rows in
# agentic-ops-readiness.md (operator evidence). Necessary, not sufficient.
#
# Usage:
#   sh conformance/agentops-ready.sh [project-dir]   (default: .)
#   sh conformance/agentops-ready.sh --selftest
set -eu

# Is $1 an agentic project? Cheap declarative marker in CLAUDE.md or RUNBOOK.md.
is_agentic() {
  _d="$1"
  for f in "$_d/CLAUDE.md" "$_d/RUNBOOK.md"; do
    [ -f "$f" ] && grep -Eiq '^[[:space:]]*[*-]*[[:space:]]*agentic:[[:space:]]*yes' "$f" && return 0
  done
  return 1
}

check_dir() {
  dir="$1"
  fail=0

  if ! is_agentic "$dir"; then
    echo "N/A: $dir is not declared agentic (no 'Agentic: yes' in CLAUDE.md/RUNBOOK.md) — skipping (no agent runs to trace)"
    return 0
  fi

  rb="$dir/RUNBOOK.md"
  if [ ! -f "$rb" ]; then
    echo "FAIL: $dir is agentic but has no RUNBOOK.md (need the §8 Agent-ops record) — see conformance/agentic-ops-readiness.md"
    return 1
  fi

  # Record string below must stay in sync with templates/RUNBOOK-TEMPLATE.md §8.
  if ! grep -Eiq 'agent-ops:' "$rb"; then
    echo "FAIL: RUNBOOK has no 'Agent-ops:' record — declare the agent-run trace discipline (schema + where emitted); see docs/operations/agentic-ops.md"
    fail=1
  elif grep -Fiq 'agent-ops: [trace]' "$rb"; then
    echo "FAIL: 'Agent-ops:' still holds the [trace] placeholder — record the real trace posture (e.g. emitter + sink)"
    fail=1
  fi

  if [ "$fail" -ne 0 ]; then return 1; fi
  echo "agentops-ready: OK — agent-ops posture is RECORDED (trace discipline declared). NOTE: this does NOT verify traces actually emit, are complete, or that the agent's behavior conforms (process-conformance) — those are Manual rows in agentic-ops-readiness.md requiring operator evidence."
  return 0
}

# Build mktemp fixtures and assert each outcome. Fixtures LEFT in place (no rm -rf; 7e guard).
selftest() {
  st_fail=0
  base=$(mktemp -d)

  d1="$base/na"; mkdir -p "$d1"; printf '# a plain library, no agents\n' > "$d1/README.md"
  if check_dir "$d1" >/dev/null 2>&1; then
    echo "selftest PASS: non-agentic -> N/A (not over-triggered)"
  else
    echo "selftest FAIL: non-agentic should be N/A"; st_fail=1
  fi

  d2="$base/ok"; mkdir -p "$d2"
  printf '# CLAUDE\n\nAgentic: yes\n' > "$d2/CLAUDE.md"
  printf '# RUNBOOK\n\n## 8. Monitoring & alerting\n- Agent-ops: trace=OTel-GenAI subset, emitter=CC-transcript, sink=traces/\n' > "$d2/RUNBOOK.md"
  if check_dir "$d2" >/dev/null 2>&1; then
    echo "selftest PASS: agentic + filled Agent-ops -> OK"
  else
    echo "selftest FAIL: agentic + filled record should pass"; st_fail=1
  fi

  d3="$base/placeholder"; mkdir -p "$d3"
  printf '# CLAUDE\n\nAgentic: yes\n' > "$d3/CLAUDE.md"
  printf '# RUNBOOK\n\n## 8. Monitoring & alerting\n- Agent-ops: [trace]\n' > "$d3/RUNBOOK.md"
  if check_dir "$d3" >/dev/null 2>&1; then
    echo "selftest FAIL: [trace] placeholder should FAIL"; st_fail=1
  else
    echo "selftest PASS: Agent-ops [trace] placeholder -> FAIL as expected"
  fi

  d4="$base/missing"; mkdir -p "$d4"
  printf '# CLAUDE\n\nAgentic: yes\n' > "$d4/CLAUDE.md"
  printf '# RUNBOOK\n\n## 8. Monitoring & alerting\n- Error tracking: Sentry\n' > "$d4/RUNBOOK.md"
  if check_dir "$d4" >/dev/null 2>&1; then
    echo "selftest FAIL: agentic + missing Agent-ops record should FAIL"; st_fail=1
  else
    echo "selftest PASS: missing Agent-ops record -> FAIL as expected"
  fi

  if [ "$st_fail" -ne 0 ]; then
    echo "agentops-ready --selftest: FAIL" >&2
    return 1
  fi
  echo "agentops-ready --selftest: OK (na/ok/placeholder/missing all behaved; fixtures left in $base)"
  return 0
}

case "${1:-}" in
  --selftest) selftest ;;
  *)          check_dir "${1:-.}" ;;
esac
exit $?
```

- [ ] **Step 2: Run the selftest to verify all four fixtures behave**

Run: `sh conformance/agentops-ready.sh --selftest`
Expected: four `selftest PASS:` lines then `agentops-ready --selftest: OK (...)`, exit 0.

- [ ] **Step 3: Verify the real-repo run is N/A (the kit root isn't a declared-agentic *product*)**

Run: `sh conformance/agentops-ready.sh; echo "exit=$?"`
Expected: `N/A: . is not declared agentic ...` then `exit=0`. (The kit governs agents but is not itself a deployed agentic product with a RUNBOOK Agent-ops record; N/A is correct and keeps the check honest.)

- [ ] **Step 4: Verify POSIX/dash cleanliness**

Run: `dash -n conformance/agentops-ready.sh && echo "dash-clean"`
Expected: `dash-clean` (no output from `-n` syntax check).

- [ ] **Step 5: Commit**

```bash
git add conformance/agentops-ready.sh
git commit -m "feat(conformance): agentops-ready.sh — conditional agent-ops record check (MP-3a)"
```

---

## Task 2: The readiness checklist `agentic-ops-readiness.md`

**Files:**
- Create: `conformance/agentic-ops-readiness.md`

Mirror `conformance/observability-readiness.md`: an intro stating what the Auto rows prove (and don't), a blank checklist, and a worked example. **Auto** rows = `agentops-ready.sh` (declared); **Manual** rows = operator evidence (traces actually emit, are complete, behavior conforms).

- [ ] **Step 1: Create the file**

```markdown
# Conformance Check — Agent-Ops Readiness

Proves an **agentic** project has its **agent-run observability** discipline in place: a trace schema is adopted, traces are emitted to a sink, and (for the MP-3b behavior loop, when present) the process-conformance window + autonomy-tier linkage are recorded. **Checklist-type**, run at the **Review / agent-ops readiness gate** (`DEVELOPMENT-PROCESS.md` §7/§13) and as **recurring maintenance** (§15). **Conditional:** non-agentic projects mark the whole check **N/A — no agent runs to trace**. Implements the trace contract in `docs/operations/agentic-ops.md`; anchored on OpenTelemetry GenAI semantic conventions.

> **What the Auto row proves — and doesn't.** `agentops-ready.sh` confirms the posture is *recorded* (an `Agent-ops:` trace record in RUNBOOK §8). It does **not** verify that traces *actually* emit, that they are *complete* (all required-core fields populated), or that the agent's *behavior conforms* over time. Those are the **Manual** rows, signed off with operator evidence. **A green script is necessary, not sufficient.**

## How to use
Copy this file into your project (or your reliability record). For each item: mark **Applies? (Y / N+reason)** and give **Evidence**. Items tagged *(documented)* are auto-checkable via `sh conformance/agentops-ready.sh`; items tagged *(verified)* require operator evidence from real agent runs. The reviewer signs off only when every applicable item has evidence.

## Checklist (blank)

| # | Item | Applies? | Evidence (where/how) | Check |
|---|------|----------|----------------------|-------|
| 1 | Trace discipline recorded — `Agent-ops:` in RUNBOOK §8 (schema + emitter + sink) *(documented)* | | | **Auto:** `agentops-ready.sh` |
| 2 | Required-core fields present in a real trace — identity keys, timing, cost, outcome, gates, tool-steps *(verified)* | | | Manual |
| 3 | Traces actually emit per agent-run — a real run's trace is viewable in the sink *(verified)* | | | Manual |
| 4 | Multi-agent keying holds — concurrent runs have distinct `(agent.id, run.id)`; `parent.run.id` builds the spawn tree *(verified)* | | | Manual |
| 5 | Guard denials captured — a `tool.outcome: denied` step appears when the §13 guard blocks an action *(verified)* | | | Manual |
| 6 | *(MP-3b, when present)* Behavior window + autonomy-tier linkage recorded and drives tier moves *(verified)* | | | Manual |

## Worked example — a project built by an agent (the kit dogfooding itself)

| # | Item | Applies? | Evidence | Check |
|---|------|----------|----------|-------|
| 1 | Trace discipline recorded *(documented)* | Y | RUNBOOK §8 "Agent-ops: trace=OTel-GenAI subset · emitter=CC-transcript · sink=`traces/`" | Auto ✅ |
| 2 | Required-core present *(verified)* | Y | a sampled `traces/<run>.json` shows agent.id/run.id/work_item.id, tokens, outcome, gates, tool-steps | Manual ✅ |
| 3 | Traces emit per run *(verified)* | Y | every merged PR's build run has a corresponding trace file | Manual ✅ |
| 4 | Multi-agent keying *(verified)* | Y | two parallel sub-agent runs show distinct run.ids + shared parent.run.id | Manual ✅ |
| 5 | Guard denials captured *(verified)* | Y | a blocked `rm -rf` shows `tool.outcome: denied` in the trace | Manual ✅ |
| 6 | Behavior loop *(verified)* | N | MP-3b not yet shipped — N/A until the behavior→tier loop lands | Manual |

> A non-agentic project (a plain library/CLI with no agent actor) marks the whole check **N/A — no agent runs to trace**; `agentops-ready.sh` skip-passes it automatically.
```

- [ ] **Step 2: Verify links resolve**

Run: `sh conformance/check-links.sh`
Expected: `OK: all relative Markdown links resolve` (the doc references `docs/operations/agentic-ops.md`, created in Task 3 — if you run this before Task 3, expect a link FAIL; re-run after Task 3).

- [ ] **Step 3: Commit**

```bash
git add conformance/agentic-ops-readiness.md
git commit -m "docs(conformance): agentic-ops readiness checklist (Auto vs Manual rows)"
```

---

## Task 3: The reference doc `docs/operations/agentic-ops.md`

**Files:**
- Create: `docs/operations/agentic-ops.md`

This is the contract + reference (the bulk; no budget cap). It carries: the sensor→§13-tier model, the trace schema (required core + recommended), the multi-agent principle, the emitter patterns (dev-time transcript / runtime OTel — documented, with MP-3a.2 noted as the working dev-time emitter), and the honesty boundary.

- [ ] **Step 1: Create the file**

```markdown
# Agentic-Ops — Agent-Run Observability & Behavior

How to observe and govern an agent's *own work* — distinct from the kit's existing layers: the §13 guard *prevents* harm, §7 evals judge a *feature's* output, §2 tracks *spend*. Agentic-ops observes the **execution**: which tools an agent called, retries, latency, cost-per-task, gates hit/skipped, and (via MP-3b) whether behavior conforms over time.

## The model — sensor → actuator

Agent-ops is a **sensor** (a stack/harness-neutral trace of how each agent worked) feeding an **actuator** (per-agent §13 autonomy tiers). Three layers:

1. **Prevention stays fail-closed, unchanged** — harm (§13 guard), broken code (CI gates), unreviewed merges (branch protection) are already gated. Agent-ops adds **no new blocking gate**; re-gating these is redundant and gating *soft* signals trains gaming.
2. **The trace is pure observation** — every agent-run emits a structured record. Zero blocking; agents flow at machine speed. This is the flight recorder.
3. **Behavior is trend-scored, not run-gated** (MP-3b) — behavior is evaluated over a window, per agent; a crossed threshold **moves the agent's autonomy tier** (earned trust → longer leash → faster; drift → shorter leash → safer), it never blocks a single PR.

The payoff: the speed/safety tradeoff becomes data-driven and **self-adjusting per agent**, not a fixed heavy gate on everyone.

## Multi-agent principle (load-bearing)

- **Identity-keyed traces** — every run is keyed by `(agent.id, run.id, work_item.id, parent.run.id)`. Concurrent agents' traces never collide; `parent.run.id` builds the sub-agent spawn tree; `work_item.id` links the atomic backlog claim (§6).
- **Per-agent tiers, never global** — a shared tier would let one drifting agent rein in all of them. Per-agent tiers keep trustworthy agents fast while a drifting sibling alone is reined in.

Done this way, agent-ops **enables** safe parallelism rather than limiting it.

## The trace schema (the contract)

Anchored on **OpenTelemetry GenAI semantic conventions** (`gen_ai.*`) as a neutral subset — not vendor-locked. The contract is **fields + meaning, not transport**.

### Required core — every agent-run trace MUST carry

| Field | Meaning |
|---|---|
| `agent.id` · `run.id` · `work_item.id` · `parent.run.id` (nullable) | Multi-agent identity; spawn tree; atomic backlog-claim linkage (§6) |
| `start` · `end` · `tokens.in` · `tokens.out` · `cost` | Per-run timing + spend (makes §2 cost governance per-task) |
| `outcome` (completed / blocked / handoff / error) · `pr.ref` · `review.rounds` | Result + mergeable-PR signal |
| `gates.hit[]` · `gates.skipped[]` · `tests.written` | The process-conformance signals MP-3b scores |
| tool-step list: `tool.name` · `tool.outcome` (ok / error / **denied**) · `retries` | The execution trace; `denied` captures §13-guard blocks (a safety signal) |

### Recommended (not required)

Per-step `latency`, `decision`/rationale notes, `task.intent` / `acceptance_ref`, `model` id. Ship the core; let these earn their place per project.

## Emitters (tool/harness-neutral)

The schema is the **portable contract**; an emitter is a **thin per-harness adapter** that maps a harness's native record to it — the same "portable contract + adapter" split as the §13 guard.

- **Dev-time (reference adapter):** Claude Code writes a JSONL session transcript (tool calls, outcomes, token usage). A transcript→trace emitter derives the schema from it. The **working reference emitter is MP-3a.2**; until then, derive traces manually or document the mapping. A Gemini-CLI / Codex / Aider shop writes its own equivalent adapter against the same schema.
- **Runtime (product agent):** emit OpenTelemetry GenAI spans (or Langfuse) directly from the running agent; the spans already carry most required-core fields.

## Declaration & conformance

Record the posture in **RUNBOOK §8** (`Agent-ops:` — schema + emitter + sink) and the project `CLAUDE.md` config (alongside autonomy-tier defaults, PROCESS §73). Verified by `conformance/agentops-ready.sh` (conditional on `Agentic: yes`); the readiness checklist is `conformance/agentic-ops-readiness.md`.

> **Honesty.** A green `agentops-ready.sh` proves the posture is **declared** — not that traces emit, are complete, or that the agent behaved. Those are Manual rows. Necessary, not sufficient.

## Roadmap

- **MP-3a (this):** the trace contract + conformance trio + declaration wiring.
- **MP-3a.2:** the working Claude Code dev-time emitter (transcript→trace) — turns the kit's own session transcripts into the corpus that calibrates MP-3b.
- **MP-3b:** the behavior-conformance rubric (scored over a window, per agent) → autonomy-tier feedback; thresholds set against real MP-3a.2 traces.
```

- [ ] **Step 2: Verify links resolve (now that both new docs exist)**

Run: `sh conformance/check-links.sh`
Expected: `OK: all relative Markdown links resolve`.

- [ ] **Step 3: Commit**

```bash
git add docs/operations/agentic-ops.md
git commit -m "docs(operations): agentic-ops reference — trace contract + sensor→tier model"
```

---

## Task 4: Declaration wiring — RUNBOOK template + PROJECT-CLAUDE template

**Files:**
- Modify: `templates/RUNBOOK-TEMPLATE.md` (§8 Monitoring & alerting)
- Modify: `templates/PROJECT-CLAUDE-TEMPLATE.md` (per-project config area)

- [ ] **Step 1: Add the colon-adjacent Agent-ops record to RUNBOOK §8**

In `templates/RUNBOOK-TEMPLATE.md`, find the §8 block (the `- **Observability** ...: SLOs: [target] · Telemetry wired: [signals]` line) and add a new line directly after it:

```markdown
- **Agent-ops** *(agentic projects — see `docs/operations/agentic-ops.md`; verified by `conformance/agentops-ready.sh`)*: Agent-ops: [trace]
```

Note the **colon-adjacent** `Agent-ops: [trace]` at the END of the line (the grep target), with the parenthetical *before* it — matching how `observability-ready.sh` matches `SLOs:`/`Telemetry wired:` even though those lines also carry a parenthetical earlier. The matched token `Agent-ops: [trace]` has the colon directly after the key.

- [ ] **Step 2: Verify the template trips FAIL (fresh) — coupling test direction 1**

Run:
```bash
tmp=$(mktemp -d); printf 'Agentic: yes\n' > "$tmp/CLAUDE.md"; cp templates/RUNBOOK-TEMPLATE.md "$tmp/RUNBOOK.md"
sh conformance/agentops-ready.sh "$tmp"; echo "exit=$?"
```
Expected: `FAIL: 'Agent-ops:' still holds the [trace] placeholder ...` then `exit=1`. (Proves a fresh template is correctly not-yet-ready.)

- [ ] **Step 3: Verify a filled value passes — coupling test direction 2**

Run:
```bash
sed 's/Agent-ops: \[trace\]/Agent-ops: OTel-GenAI subset, emitter=CC-transcript, sink=traces\//' "$tmp/RUNBOOK.md" > "$tmp/RUNBOOK.filled.md" && mv "$tmp/RUNBOOK.filled.md" "$tmp/RUNBOOK.md"
sh conformance/agentops-ready.sh "$tmp"; echo "exit=$?"
```
Expected: `agentops-ready: OK ...` then `exit=0`. (Proves a filled record is matched — guards against the SNP-1 false-FAIL.)

- [ ] **Step 4: Add the per-project config line to PROJECT-CLAUDE-TEMPLATE.md**

In `templates/PROJECT-CLAUDE-TEMPLATE.md`, in the per-project configuration / declarations area (where autonomy tiers / backlog backend are declared), add:

```markdown
- **Agent-ops** *(if agentic)*: set `Agentic: yes` and declare the agent-run trace posture in RUNBOOK §8 (`Agent-ops:`); see `docs/operations/agentic-ops.md`. Verified by `conformance/agentops-ready.sh`.
```

- [ ] **Step 5: Commit**

```bash
git add templates/RUNBOOK-TEMPLATE.md templates/PROJECT-CLAUDE-TEMPLATE.md
git commit -m "feat(templates): agent-ops declaration — RUNBOOK §8 record + project CLAUDE config"
```

---

## Task 5: Core-doc pointer (budget-checked) on STANDARDS Factor 14

**Files:**
- Modify: `DEVELOPMENT-STANDARDS.md` (the Telemetry-depth / Factor 14 readiness bullet)

PROCESS is at 468/470 (no room); STANDARDS is at 316/320 (room for +1). Put the single pointer there, beside the existing Factor-14 readiness bullet.

- [ ] **Step 1: Append the pointer bullet**

In `DEVELOPMENT-STANDARDS.md`, directly after the existing line:
`- **Telemetry depth (Factor 14)** — observability is metrics + traces + health, extending §3 beyond logs. Readiness: \`conformance/observability-readiness.md\` ...`
add:

```markdown
- **Agent-ops (agentic projects)** — observe the *agent's own execution* (trace: tool-calls, retries, cost, gates) feeding per-agent §13 autonomy tiers. Reference + trace contract: `docs/operations/agentic-ops.md`; readiness `conformance/agentic-ops-readiness.md` (verified by `conformance/agentops-ready.sh`).
```

- [ ] **Step 2: Verify the doc budget still passes**

Run: `sh conformance/doc-budget.sh`
Expected: `PASS: DEVELOPMENT-STANDARDS.md 317/320 lines` and `OK: core docs within budget`. (If it instead reports over budget, remove a word-wrapped line elsewhere is NOT allowed — instead fold the pointer into the existing Factor-14 bullet as a `+0` trailing sentence and re-run.)

- [ ] **Step 3: Verify links**

Run: `sh conformance/check-links.sh`
Expected: `OK: all relative Markdown links resolve`.

- [ ] **Step 4: Commit**

```bash
git add DEVELOPMENT-STANDARDS.md
git commit -m "docs(standards): Factor-14 pointer to agentic-ops (budget +1)"
```

---

## Task 6: Wire into `verify.sh` (the aggregate doc-check)

**Files:**
- Modify: `conformance/verify.sh`

- [ ] **Step 1: Add the doc-check row**

In `conformance/verify.sh`, in the block of `check doc ...` lines (after `check doc preview-env-ready ...`), add:

```sh
check doc     agentops-ready  sh conformance/agentops-ready.sh
```

- [ ] **Step 2: Run the aggregate and confirm the new row + green result**

Run: `sh conformance/verify.sh`
Expected: a `[doc] agentops-ready PASS` line (the kit root is N/A → skip-pass → PASS), the summary now showing **9 doc-checks**, and `RESULT: OK (controls verified; docs present)`.

- [ ] **Step 3: Commit**

```bash
git add conformance/verify.sh
git commit -m "feat(conformance): wire agentops-ready into verify.sh aggregate (doc-check)"
```

---

## Task 7: conformance/README registry + audit-evidence rows

**Files:**
- Modify: `conformance/README.md` (the canonical check registry — top-level `README.md` does NOT list individual checks)
- Modify: `conformance/audit-evidence-checklist.md`

- [ ] **Step 1: Add the check to BOTH places in `conformance/README.md`**

(a) In the **line-20 "documentation / evidence" bucket** prose list (which ends `... preview-env-ready.sh, and the paired *-readiness.md ... checklists`), insert `agentops-ready.sh` into the comma-list, e.g. after `preview-env-ready.sh`:
`..., preview-env-ready.sh, agentops-ready.sh, and the paired *-readiness.md ...`

(b) In the **checks table**, add a row matching the column format of the `observability-ready.sh` / `test-data-ready.sh` rows:

```markdown
| `agentops-ready.sh` | script | MP-3 agentic-ops — the agent-run **trace discipline is recorded** (RUNBOOK §8 `Agent-ops:`); conditional (N/A for non-agentic). Does NOT verify traces emit or behavior conforms. Pairs with `agentic-ops-readiness.md` / `../docs/operations/agentic-ops.md` | Review / CI (conditional on an agentic project) |
```

- [ ] **Step 2: Add the Auto + Manual rows to the audit-evidence checklist**

In `conformance/audit-evidence-checklist.md`, find where `observability-ready`/`preview-env-ready` rows live and add, in the same column format:

```markdown
| Agent-ops trace discipline recorded (agentic) | `agentops-ready.sh` | Auto | RUNBOOK §8 `Agent-ops:` |
| Traces actually emit / behavior conforms | operator evidence | Manual | real agent-run traces in the sink |
```

(Adjust the columns to match the file's actual header row.)

- [ ] **Step 3: Verify links + that nothing regressed**

Run: `sh conformance/check-links.sh && sh conformance/verify.sh | tail -3`
Expected: links OK; `RESULT: OK`.

- [ ] **Step 4: Commit**

```bash
git add conformance/README.md conformance/audit-evidence-checklist.md
git commit -m "docs(conformance): register agentops-ready in the check registry + audit-evidence rows"
```

---

## Task 8: Prepare the control-plane CI step (hand-apply diff for Bradley)

**Files:**
- Hand-apply (Bradley): `.github/workflows/ci.yml`

The kit's own CI must run the new check's selftest. `.github/workflows/` is control-plane — the guard blocks the agent from staging it — so this is a prepared diff Bradley applies (with `KIT_GUARD_SELFEDIT=1` for the `git add`).

- [ ] **Step 1: Produce the exact insertion text**

The step to add to the `conformance:` job, immediately after the `Preview-env-ready self-test` step:

```yaml
      - name: Agent-ops-ready self-test (agentic trace-discipline record)
        run: sh conformance/agentops-ready.sh --selftest
```

- [ ] **Step 2: Surface it to Bradley in the PR description**

Include the snippet above in the PR body under a "⚠️ One control-plane hand-apply" heading, with the apply commands:
```bash
KIT_GUARD_SELFEDIT=1 git add .github/workflows/ci.yml
git commit -m "ci(kit): run agentops-ready selftest in kit pipeline"
```
(He applies it on the PR branch before merge, or as a tiny follow-on PR like #71.)

- [ ] **Step 3: (no commit — this task produces the PR-body content, not a repo change)**

---

## Task 9: Final verification + independent review + PR

- [ ] **Step 1: Full conformance sweep**

Run:
```bash
sh conformance/agentops-ready.sh --selftest
sh conformance/check-links.sh
sh conformance/doc-budget.sh
sh conformance/verify.sh
dash -n conformance/agentops-ready.sh && echo dash-clean
```
Expected: selftest OK; links OK; doc-budget OK; `verify.sh` → `RESULT: OK` with 9 doc-checks; dash-clean.

- [ ] **Step 2: Independent review (builder ≠ sole reviewer)**

Dispatch a `security-reviewer` subagent (governing-doc/conformance change → security-owner lens) over the diff. Focus: the conditional trigger isn't over/under-broad; the colon-adjacent record line is coupling-correct (fresh→FAIL, filled→OK); the honesty wording is accurate (declared ≠ verified); no false claim that traces are validated.

- [ ] **Step 3: Address any findings, then open the PR**

```bash
git push -u origin feature/agentic-ops-mp3a
gh pr create --title "feat(agentic-ops): MP-3a — agent-run observability contract + conformance" --body "<summary + the §13/honesty framing + the Task-8 control-plane hand-apply snippet + merge command>"
```
Report the PR number + the `gh pr merge <n> --squash --admin --delete-branch` command. **Do not self-merge.**

---

## Self-review (done by the plan author)

- **Spec coverage:** §2 model → Task 3 doc. §3 multi-agent → Task 3 (principle) + Task 2 (rows 4). §4 schema → Task 3 table. §5 slices → Task 3 roadmap (MP-3a.2/MP-3b named). §6 declaration → Task 4. §7 conformance/honesty → Task 1 + Task 2 intro. §8 doc placement → Task 5 (Factor 14, budget-checked). §9 testing → Task 1 selftest + Task 4 coupling tests. §10 scope guard → reflected (no gate; emitter deferred to 3a.2). §11 DoD → Tasks 1–9. **No gaps.**
- **Placeholder scan:** the only literal `[trace]` is the intentional template placeholder the check greps for (mirrors observability's `[target]`/`[signals]`); not a plan gap.
- **Consistency:** record key `Agent-ops:` and trigger `Agentic: yes` are identical across Tasks 1, 4, 7; the schema field names match the spec §4 exactly; doc-check name `agentops-ready` matches the script filename across Tasks 1, 6, 8.
