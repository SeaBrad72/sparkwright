# E4d — Runaway Kill-Switch · Design

**Date:** 2026-06-25
**Status:** Approved (brainstorm) — ready for implementation plan
**Slice:** E4d (cost/runaway kill-switch), decoupled from E3; absorbs E13/FinOps' cost-control focus
**Classification:** Control-plane change → AMBER `apply.py` + dual review (builder ≠ reviewer + security-reviewer)

---

## 1. Purpose & boundary

E4d ships a **harness-neutral, executable circuit-breaker** that halts a runaway orchestrated flow at the **orchestration seam** — the between-step / before-spawn boundary, which is the one boundary the kit can actually control.

The kit ships the **checker**; the harness supplies the **numbers** (tokens used this step, agents spawned). On breach the checker returns non-zero and the orchestrator halts and escalates. The platform LLM-API cap remains the hard ceiling *above* this — E4d does **not** replace it.

**Why this is honest:** the kit cannot *measure* tokens itself (that is the harness/LLM-API's job), but it *can* enforce a ceiling on *reported* usage and stop the loop. That division keeps E4d harness-neutral and keeps the kit from over-claiming.

### Relationship to existing controls (three distinct concerns)

| Control | Concern | Posture |
|---------|---------|---------|
| **H3b cost-governance** (`cost-governance-ready.sh`) | A budget posture is *declared + attested* | Attestation only |
| **E2 feature-flags** | Soft *release* kill-switch | Release control |
| **E4d (this)** | *Resource-exhaustion* runaway | Executable enforcement at the orchestration seam |

These read as one coherent story: declare it (H3b) → enforce it at runtime (E4d) → toggle features (E2). The docs cross-link all three.

---

## 2. The checker — `scripts/runaway-guard.sh` (new control-plane named script)

One script, called once per step by the orchestrator:

```
runaway-guard.sh step --tokens <n> --agents <n>   # record this step's usage, then check
runaway-guard.sh check                            # verdict only (no record)
runaway-guard.sh reset                            # start a fresh run (truncate/rotate tally)
```

**Exit codes** (mirroring the kit's three-state conformance convention):

- **0 = CONTINUE** — under all ceilings. May emit a `WARN` to stderr at ≥ warn-threshold (default 80%).
- **1 = STOP** — a ceiling breached. Prints *which* dimension breached and the numbers. Orchestrator halts + escalates.
- **2 = UNVERIFIED** — config missing/malformed → **fail-closed** under CI / `--require` (never a silent green).

**Dimensions** (each a ceiling + the shared warn-threshold):

1. **Cumulative tokens** — `tokens_in + tokens_out` summed across the run. Cost derived via a documented token→cost rate.
2. **Step count** — loop iterations / orchestration steps. Catches the cheap-but-endless loop that token caps miss.
3. **Agent-spawn count** — total sub-agents a flow may spawn. Catches the multi-agent fan-out "fork-bomb" (the E3 enabler the backlog calls out).

---

## 3. Config vs tally (the two-file split)

- **Ceiling config** — committed, **control-plane** (proposed `.kit/budget.json`; exact path settled in planning). Holds the three ceilings + warn-threshold + token→cost rate. Control-plane so an autonomous agent **cannot raise its own limit** (the M2-S5 lesson applied directly).
- **Run tally** — *runtime* state, append-only JSONL, **gitignored** (proposed `.kit-run/tally.jsonl`, overridable via env). Not committed (per-run, ephemeral). `step` appends one record; `check` sums the whole append-only log.

---

## 4. Integrity & the honest residual risk

The M2-S5 finding — *enforcement whose config is agent-writable isn't enforced* — drives the integrity model:

- **Ceiling config** → `is_control_plane_path` in **both** guard matchers: the tool path-matcher **and** the shell-redirect matcher (S5's two-matcher completeness lesson — a tool-only fix leaves the `printf > config` back door open).
- **`scripts/runaway-guard.sh`** → control-plane named script (joins `containment-audit`, `sod-check`, etc.).
- **Honest residual risk (documented, not hidden):** the *tally* cannot be fully tamper-proofed in a harness-neutral world — an agent with write access could truncate it to evade. The **primary guarantee is that the ceiling is immutable**; the **platform cap is the backstop** if the tally is defeated. This honest ceiling is stated plainly in the ops doc — no over-claim.

---

## 5. Conformance & registration (the lock)

CLAUDE.md principle #4 — *if it isn't automated, it isn't enforced* — makes the lock non-negotiable.

- **`conformance/runaway-killswitch-wired.sh`** with `--selftest` fixtures:
  - under-budget → exit 0
  - each dimension over ceiling → exit 1 (asserts the *right* dimension is named)
  - warn-threshold reached → exit 0 + warning emitted
  - missing / malformed / future / tampered config → fail-closed (exit 2 under `--require`)
  - ceiling raised without ratification → detectable
- **Register:**
  - row in `conformance/claims.tsv` — id `runaway-killswitch`
  - add `runaway-killswitch` to `REQUIRED_IDS` in `conformance/claims-registry.sh` (silent-drop prevention)
  - wire `--selftest` into `.github/workflows/ci.yml` (+ `conformance/verify.sh`)
  - auto-flows into `doctor` (runs full `verify.sh`) and `drift-watch` (weekly) — no separate wiring
  - index row in `conformance/README.md`

---

## 6. Docs & reference

- **`docs/operations/runaway-killswitch.md`** — rationale, the honest ceiling, and a **harness-neutral reference loop** (record → check → halt as a documented pattern, *not* a Claude-Code-specific workflow — consistent with M1's neutrality decision that orchestration stays harness-local). Cross-links H3b cost-governance and E2 flags.
- **TASK-CONTEXT-CONTRACT `Budget` field** connection: the contract is the human-readable declaration; `.kit/budget.json` is the machine-enforced ceiling derived from it.

---

## 7. Scope / YAGNI

**In scope:**
- The three dimensions (tokens/cost, steps, agent-spawns)
- The `runaway-guard.sh` checker (step / check / reset)
- Control-plane ceiling config + gitignored runtime tally
- The `runaway-killswitch-wired.sh` conformance lock + full registration
- One harness-neutral reference loop
- The ops doc

**Out of scope (deliberate):**
- **Wall-clock** — platform/CI job timeouts already own it; adding it would over-claim a control the kit doesn't own.
- **Dollar-precise billing** — tokens × documented rate is sufficient; precise cost is the platform's ledger.
- **Per-profile rollout to all 10 profiles** — one reference example; profiles adopt later.
- **Measuring tokens itself** — the harness's job; the kit only enforces reported numbers.

---

## 8. Process

Control-plane slice → full loop: brainstorm (this doc) → implementation plan → subagent-build → **AMBER `apply.py` in scratchpad** → **dual review** (builder ≠ reviewer + security-reviewer, who specifically probes the §4 integrity model) → stop at PR-green-reviewed-ready → Bradley merges + tags.

---

## Honest-ceiling summary (what E4d does and does not guarantee)

- **Guarantees:** a control-plane, agent-immutable ceiling on tokens/cost, steps, and agent-spawns; an executable halt at the orchestration seam; a conformance-locked, drift-watched proof that the kill-switch stays wired.
- **Does not guarantee:** a hard LLM-API spend cap (platform-owned), a tamper-proof runtime tally (best-effort; platform cap is the backstop), or wall-clock bounding (platform/CI timeouts).
