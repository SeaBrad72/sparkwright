# Agentic-Ops (MP-3) — Design

**Status:** approved (brainstorm), ready for implementation planning
**Arc:** Modern Practices, Slice MP-3
**Scope of this doc:** the full agentic-ops arc — the unified trace contract (the spine), MP-3a (agent-run observability), and the shape of MP-3b (behavior→tier loop). MP-3a is fully specified here and built first; MP-3b is sketched and finalized against real 3a traces.

---

## 1. Problem & framing

The kit already touches agents in three places, but none of them *observes the agent's own work*:

- **§13 governance / the runtime guard** — *prevents* harm (capability boundaries, autonomy tiers). Prevention, not observation.
- **§7 evals** (`eval-ready.sh`, EVAL-PLAN, AI System Card) — judge an AI *feature's* output quality. Product quality, not process.
- **§2 cost governance** — tracks agent *spend*. A number, not a trace.

Genuinely absent: **observing and evaluating an agent's own execution** — the trace (which tools it called, retries, latency, cost-per-task, gates hit/skipped) and whether its *behavior* conforms to the SDLC over time.

**The tension to resolve:** enable continuous, rapid development across many agents *while* maintaining guardrails, observability, and process adherence.

## 2. The model — sensor → actuator

Agent-ops is a **sensor** (a stack-neutral trace of how each agent worked) feeding an **actuator** (per-agent §13 autonomy tiers). Three layers, mapped to where harm actually lives:

1. **Prevention stays fail-closed, unchanged.** Harm (the §13 guard), broken code (CI gates), unreviewed merges (branch protection) are *already* gated regardless of human-vs-agent actor. Agent-ops adds **no new blocking gate** here — re-gating these would be redundant, and gating the *soft* signals (spec-first, red-green-refactor) produces false-fails and trains gaming (an anti-pattern the kit names repeatedly).
2. **The trace is the new layer — pure observation.** Every agent-run emits a structured record. Zero blocking. This is what preserves *rapid* development: agents keep flowing at machine speed between the existing gates, and you gain a flight recorder.
3. **Behavior-eval is trend-scored, not run-gated.** Behavior is evaluated **in aggregate over a window**, per agent. A crossed threshold does **not** block a PR — it **moves the agent's autonomy tier**: sustained good conformance *earns* a higher tier (flows through more gates unattended → faster); degrading conformance *drops* the tier (stops at more gates / more human ratification → safer).

**The payoff:** the speed/safety tradeoff becomes *data-driven and self-adjusting per agent*, instead of a fixed heavy gate imposed on everyone. You don't gate the work on behavior — you let observed behavior set the leash length.

## 3. Multi-agent principle (load-bearing)

Agent-ops must be multi-agent-native or it would quietly throttle parallelism (a core kit capability — PROCESS §2/§6/§13):

- **Identity-keyed traces** — every run is keyed by `(agent.id, run.id, work_item.id, parent.run.id)`. Concurrent agents' traces never collide; `parent.run.id` builds the sub-agent spawn tree; `work_item.id` links the atomic backlog claim (§6).
- **Per-agent tiers, never a global tier** — if conformance drift dropped a *shared* tier, one misbehaving agent would rein in all of them, killing parallelism. Per-agent tiers mean a trustworthy agent keeps flowing fast while a drifting sibling alone gets a shorter leash.

Done this way, agent-ops **enables** safe parallelism — you can finally see and govern N concurrent agents individually — rather than limiting it. This is stated explicitly in the contract.

## 4. The trace schema (the frozen contract — the spine)

Anchored on **OpenTelemetry GenAI semantic conventions** (`gen_ai.*`) as a neutral subset — not Langfuse-locked. The contract specifies **fields and meaning, not transport**.

### Required core — every agent-run trace MUST carry

| Field | Why required |
|---|---|
| `agent.id` · `run.id` · `work_item.id` · `parent.run.id` (nullable) | Multi-agent identity keying; spawn tree; atomic backlog-claim linkage (§6) |
| `start` · `end` · `tokens.in` · `tokens.out` · `cost` | Per-run timing + spend — makes §2 cost governance *per-task* |
| `outcome` (completed / blocked / handoff / error) · `pr.ref` · `review.rounds` | The result + a mergeable-PR signal |
| `gates.hit[]` · `gates.skipped[]` · `tests.written` | The process-conformance signals MP-3b scores |
| tool-step list: `tool.name` · `tool.outcome` (ok / error / **denied**) · `retries` | The execution trace; `denied` captures §13-guard blocks — a first-class safety signal |

### Recommended (not required)

Per-step `latency`, `decision` / rationale notes, `task.intent` / `acceptance_ref`, `model` id. (The kit's "ship a sensible default, don't over-impose" pattern — these earn their place per project.)

### Reference emitters (tool-neutral)

- **Dev-time** — Claude Code already writes JSONL session transcripts containing tool calls + outcomes, so the dev-time trace is **derived from the existing transcript**, near-zero instrumentation.
- **Runtime** — OTel-GenAI spans / Langfuse for a shipped product agent.

## 5. Slices & build sequence

- **Freeze** the trace-schema contract (§4) — the shared interface. Once frozen, the two slices can build concurrently against it (separate agents), so the arc is sequential only up to the freeze.
- **MP-3a — Agent-run observability (built first, independently shippable):**
  - the trace contract (§4) written into `docs/operations/agentic-ops.md`
  - reference emitters documented (dev-time transcript-derived; runtime OTel/Langfuse)
  - `conformance/agentops-ready.sh` + `conformance/agentic-ops-readiness.md` (declared-discipline check)
  - declaration point wired (§6); core-doc pointer (§7); CI + `verify.sh` + README + audit rows (§8)
  - *Value alone:* the flight recorder — cost/latency/retry/gate-skip visibility per agent-run, even if MP-3b never shipped.
- **MP-3b — Behavior→tier loop (built after 3a; thresholds finalized against real traces):**
  - a process-conformance **rubric** over a window, per agent. Candidate dimensions (from the trace): `tests.written` with code, `gates.skipped` rate, `review.rounds` trend, guard-`denied` rate, cost/retry trend, outcome mix.
  - the **trend → §13 autonomy-tier** mechanism: sustained conformance moves the agent's tier up/down; production promotion stays human-gated regardless (PROCESS §13).
  - its own readiness rows. **Thresholds and tier-movement rules are deliberately deferred** to be set against real 3a traces — "production teaches the next iteration" (CLAUDE.md principle 6).

## 6. Declaration point

The project records its agent-ops posture where operational records already live:

- **RUNBOOK §8** (Observability — where SLOs/telemetry already sit): a record line for the agent-ops approach (trace emission: on/off + where; for MP-3b later: the conformance window + tier-linkage). **Colon-adjacent record line** (`**Key:** [placeholder]`) per the SNP-1 lesson.
- **Project `CLAUDE.md`** per-project config (PROCESS §73 already lists autonomy-tier defaults there): a one-line agent-ops posture entry alongside them.

`agentops-ready.sh` reads these.

## 7. Conformance & honesty

`conformance/agentops-ready.sh`, mirroring `observability-ready.sh`:

- **Conditional trigger** — applies when the project declares agentic work / ships an agent (e.g. an `agentic: yes` marker in CLAUDE/RUNBOOK, or an agent actor in the backlog). Non-agentic projects: **N/A (skip-pass)**, never failed.
- **Three-state** — N/A (exit 0 skip) · OK (declared) · FAIL (triggered but the posture is a placeholder/absent) · `--selftest`.
- **Honesty invariant** — a green run asserts the posture is **declared**, *not* that traces exist, are complete, or that the agent behaved. Actual trace inspection + tier moves are **operator/Manual rows** in `agentic-ops-readiness.md`. Necessary, not sufficient.

## 8. Doc placement (budget-aware)

Core-doc budget is tight: **PROCESS 468/470, STANDARDS 316/320, CLAUDE 111/120**. Therefore:

- **Bulk → `docs/operations/agentic-ops.md`** (the reference; no budget cap).
- **Core-doc pointer (minimal):** prefer a **+0 append** to an existing PROCESS §13 governance line; if §13 can't take it within budget, the single-line pointer goes on **STANDARDS Factor 14 (Telemetry)** (4 lines of headroom) instead. Decided at build time by running `doc-budget.sh`.
- `agentic-ops-readiness.md` checklist lives in `conformance/`.

## 9. Testing

- `agentops-ready.sh --selftest` with mktemp fixtures: **N/A** (non-agentic) / **declared-OK** / **placeholder-FAIL**, left in place (7e guard, no `rm -rf`).
- **Coupling-tested both directions** — fresh template → FAIL and filled value → OK (the SNP-1 colon-adjacent lesson).
- Wired into kit CI (`.github/workflows/ci.yml` — control-plane, human-applied) + `conformance/verify.sh` as a **doc-check** + README + `audit-evidence-checklist.md` rows.

## 10. What this is NOT (scope guard)

- **Not a new blocking gate.** No PR is failed on behavior. Enforcement is the per-agent tier, not the merge.
- **Not a tool mandate.** No required dependency on Langfuse/OTel/any vendor — the contract is fields + meaning; emitters are reference-only.
- **Not MP-3b's thresholds.** This doc fixes the *shape* of the behavior loop; the rubric thresholds and tier-movement rules are set in MP-3b against real traces.
- **Not a product-analytics system.** Agent-ops observes the *agent's execution*, not end-user product metrics (that's the app's own telemetry / Factor 14).

## 11. Definition of Done (MP-3a)

- `docs/operations/agentic-ops.md` ships the frozen trace contract (required core + recommended) + both reference emitters + the sensor→actuator model + the multi-agent principle.
- `conformance/agentops-ready.sh` (three-state, conditional, `--selftest`) + `conformance/agentic-ops-readiness.md` (Auto vs Manual rows).
- Declaration point wired into `templates/RUNBOOK-TEMPLATE.md` §8 + `templates/PROJECT-CLAUDE-TEMPLATE.md`.
- Minimal core-doc pointer (budget-verified) + CI selftest step + `verify.sh` doc-check + README + audit rows.
- All conformance green; independent review (builder ≠ sole reviewer); PR ratified by Bradley; MINOR release.
