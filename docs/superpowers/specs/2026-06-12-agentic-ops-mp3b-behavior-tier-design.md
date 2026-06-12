# Agentic-Ops MP-3b — Behavior-Conformance → Autonomy-Tier Loop — Design

**Status:** approved (brainstorm), ready for implementation planning
**Arc:** Modern Practices, Slice MP-3b — the capstone of agentic-ops. Depends on MP-3a (trace contract, #73) and MP-3a.2 (`scripts/agent-trace.sh` emitter, #74). Closes the arc.

---

## 1. Framing — operationalize what §13 already promises

`DEVELOPMENT-PROCESS.md` §13 already states the mechanism: *"Track per agent... rework rate · review-rejection rate · escalation rate · retro-action quality... use to adjust autonomy. **Reliability earns autonomy; regressions revoke it**,"* and the tier table notes *"a project raises an action's tier as the agent-quality metrics earn it."* But those metrics are **named, not computed** — nothing measures them, there is no rubric/window, and nothing links them to the trace MP-3a.2 now produces.

MP-3b **computes** them and closes the sensor→actuator loop. It is not a new governance concept; it is the missing measurement + the asymmetric feedback that §13 leaves aspirational.

## 2. The model — asymmetric tier authority

The actuator is **asymmetric**, because §13 says tier *raises* are **Security-owner-ratified** while *"regressions revoke it"* (the safe direction is automatable):

- **Regression → fail-safe auto-downgrade *directive*.** A sustained regression past threshold emits a machine- + human-readable downgrade directive (agent, offending metrics, recommend tier `L_n → L_{n-1}`). Tightening a leash is safe to automate.
- **Earned → raise *recommendation*.** A sustained earned improvement emits a raise recommendation routed to the Security owner for ratification (§13). Loosening always passes a human.

**The kit emits directives; it does not actuate.** The kit does not own the adopter's enforcement plane, and the guard blocks agents from editing `.claude/`. So MP-3b **never mutates live autonomy config** (`.claude/settings.json`, the guard, or any tier store). It emits the directive/recommendation; the adopter wires it into *their* enforcement (a CI policy gate, a settings generator, a review checklist). This is the kit's standing "the real boundary is platform-owned" stance (§13 enforcement note).

## 3. The scorecard tool

`scripts/agent-scorecard.sh` (`#!/bin/sh`, sh + jq, dash-clean), mirroring `scripts/agent-trace.sh` / `dora.sh`:

- **Input:** a directory of trace JSON files (default `traces/`, the sink `agent-trace.sh` writes), or `--traces <dir>`.
- **Grouping:** by `agent.id`.
- **Window:** the last **N** runs per agent (default `N=20`, `--window N`, per-project configurable). Last-N-runs (not last-T-days) — deterministic and gap-insensitive.
- **Per-agent output:** a scorecard JSON — the computed metrics (§4), a classification `regressed | steady | earned`, and (when not `steady`) the directive/recommendation (§2).
- **Modes:** default writes `scorecards/<agent-id>.json`; `--stdout`; `--selftest`.

Boundary discipline (as `dora.sh`/`agent-trace.sh`): **jq computes/shapes; sh orchestrates.** No JSON hand-parsed in sh.

## 4. Metrics — trace-derivable set (v1) + referenced slots

Computed over the window from `agent-trace.sh` traces:

| Metric | Derivation |
|---|---|
| gate-skip rate | `gates.skipped` non-empty share (see §5 honesty) |
| guard-denial rate | share of tool-steps with `outcome == "denied"` |
| retry rate | mean `retries` per run / per tool-step |
| review-rejection proxy | mean `review.rounds` (higher = more rework at review) |
| blocked/error rate | share of runs with `outcome` in {`blocked`,`error`} |
| cost / token trend | slope of `tokens.out` (+ `cost` when present) across the window |

**Referenced-but-not-computed (documented scorecard slots, `unknown` in v1):** `rework_rate` (needs git churn / revert correlation), `retro_action_quality` (needs human judgment). They appear in the scorecard JSON as `"unknown"` so the shape is forward-compatible.

## 5. Honesty — `unknown` is missing, never zero (load-bearing)

- A trace field of `"unknown"` (the MP-3a.2 sentinel) is treated as **missing data, excluded from the metric**, never coerced to `0`/`false`. An agent is **never downgraded on absent data**.
- **`gates.skipped` is `"unknown"` for every MP-3a.2 trace** (a non-run isn't observable from a transcript), so the *gate-skip-rate* metric is, in practice, `unknown` until a future enrichment populates it — the scorecard shows it `unknown` and excludes it from the v1 regression trigger. Stated plainly, not hidden: v1's regression signal leans on the *measured* metrics (guard-denial, error/blocked rate, retry, review-rounds, cost trend).
- **Insufficient data → `steady` (no action).** If an agent has fewer than a minimum number of runs in the window (`--min-runs`, default 5) with measured metrics, classification is `steady` and **no directive is emitted** — the loop fails safe toward *not* moving a tier on thin evidence.
- A green `--selftest` proves the scorecard **computes correctly on a fixture**, never that any real agent is well-behaved. It is a tool, not a gate; it fails no PR.

## 6. Thresholds — calibrated on real traces

Defaults are **per-project-configurable** (flags / a small config block) with starting values **calibrated empirically** against the kit's own corpus: a build-time step runs `agent-trace.sh` over a sample of the kit's session transcripts, feeds the resulting traces to `agent-scorecard.sh`, and the observed distributions set defensible v1 defaults. The classification mechanism is symmetric around a **trailing baseline** (the agent's own earlier-window metrics) with a configurable margin: a risk metric (guard-denial / error-blocked / retry / review-rounds) **worse** than baseline by the margin → `regressed`; **all** risk metrics **better** than baseline by the margin, sustained, → `earned`; otherwise `steady`. (Cost/token trend informs `earned` but never alone triggers a downgrade — spend is a §2 concern, not a safety regression.) The spec fixes this mechanism; the calibration run sets the numeric margin and records it in the doc.

**Relative-to-self, calibrated locally, no data collection.** The baseline is always the *agent's own* recent history — a **relative** signal ("worse than this agent has recently been"), never a universal absolute ("worse than a number we baked in"). So the system auto-tunes to each adopter's own normal without the kit defining their normal. Two layers: the kit ships universal **sensitivity defaults** (the margin / window / min-runs, calibrated once on the kit's corpus); each adopter's **trailing baseline self-updates every window** from their **local** traces — no manual recalibration. The scorecard runs entirely locally; **the kit never phones home, pools, or aggregates any adopter's agent-behavior data** (a central "learn from all users" model would be a privacy/governance violation — deliberately not done). Maintainers revisit only the shipped defaults, and only when the kit's own corpus or the trace shape changes.

## 7. Governance & conformance wiring

- **`docs/operations/agentic-ops.md`** — flesh out the (already-stubbed) MP-3b section: the scorecard, the asymmetric directive model, the metric set, the `unknown`-is-missing rule, the calibration method.
- **`DEVELOPMENT-PROCESS.md` §13** — a **≤2-line, budget-safe** pointer (PROCESS is at 468/470): agent-quality metrics (§13's named set) are computed by `scripts/agent-scorecard.sh` over a window and feed tier moves **asymmetrically** (auto-downgrade directive / security-owner-ratified raise). Prefer a `+0` append to the existing "Agent-quality metrics" subsection line; fall back to the `docs/operations` reference if budget can't take it.
- **`conformance/agentic-ops-readiness.md`** — fill the existing **row 6** ("*(MP-3b, when present)* behavior window + autonomy-tier linkage recorded and drives tier moves") from a placeholder into a real Auto/Manual pairing: Auto = the scorecard discipline is declared; Manual = directives actually drive tier moves in the adopter's plane.
- **`scripts/agent-scorecard.sh --selftest`** over a committed multi-trace fixture, wired into kit CI as a smoke step (control-plane hand-apply, mirroring the `agent-trace` smoke).
- The existing `agentops-ready.sh` is unchanged (it already covers the declared discipline); MP-3b adds the scorecard tool + readiness row, not a new `*-ready.sh`.

## 8. Out of scope
- **No auto-*raise*** (security-owner-ratified only); **no mutation of live autonomy config** (`.claude/`, guard, any tier store) — directives are emitted, not actuated.
- **No git-churn / retro-quality computation** — referenced slots, `unknown` in v1.
- **No dashboards / aggregation UI** — one trace-dir → per-agent scorecard JSON.
- **No runtime/product-agent scoring** — this scores the dev-time building agent from `agent-trace.sh` traces (the product-agent path reuses the same scorecard once a runtime emitter exists, but isn't built here).
- **No new blocking gate** — fails no PR; enforcement is the tier, via the adopter's plane.

## 9. Definition of Done
- `scripts/agent-scorecard.sh` (sh+jq, dash-clean): trace-dir → per-agent scorecard JSON with the §4 metrics, `regressed|steady|earned` classification, asymmetric directive/recommendation, `unknown`-is-missing handling, `--min-runs`/`--window` safe-defaults.
- `scripts/fixtures/agent-scorecard-*.jsonl` (or a fixtures dir) + `--selftest` asserting: a synthetic "clean" agent → `steady`/`earned`; a synthetic "regressed" agent (high denial/error) → `regressed` + downgrade directive; an agent with `< min-runs` → `steady`/no-directive; `unknown` fields excluded (not zeroed). Fixtures left in place (7e guard).
- Threshold calibration run performed; chosen defaults recorded in `agentic-ops.md`.
- `agentic-ops.md` MP-3b section + the §13 pointer (budget-verified) + `agentic-ops-readiness.md` row 6 filled.
- Kit-CI smoke step prepared as a control-plane hand-apply.
- Independent review (builder ≠ sole reviewer) → SHIP; PR ratified by Bradley.
- **Arc close:** a 2.56.0 release covering MP-3a / MP-3a.2 / MP-3b.
