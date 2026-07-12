# Runaway kill-switch — reference

How to halt a runaway orchestrated flow before it exhausts tokens, spirals through endless steps, or
fan-outs into unbounded agent spawns. Like the cost-governance reference (`cost-governance.md`),
this ships an **executable checker** and points at the **platform control** that is the hard
ceiling — because the kit cannot *measure* tokens itself (that is the harness/LLM-API's job), but
it *can* enforce a ceiling on *reported* usage and halt the loop.

`scripts/runaway-guard.sh` is the checker. The platform LLM-API cap is the hard ceiling above it.

## The story in three controls

These three controls read as one coherent posture:

| Control | Concern | How |
|---------|---------|-----|
| **H3b cost-governance** (`cost-governance.md`) | A budget posture is *declared + attested* | `conformance/cost-governance-ready.sh` verifies attestation |
| **E4d (this)** | *Resource-exhaustion* runaway — executable enforcement at the orchestration seam | `scripts/runaway-guard.sh step` called once per step |
| **E2 feature-flags** (`feature-flags.md`) | Soft *release* kill-switch | Flag default-OFF; instant-off at restart |

**Declare the ceiling (H3b) → enforce it at runtime (E4d) → toggle features off instantly (E2).**

## The seam E4d guards

The orchestration seam — the between-step / before-spawn boundary — is the one boundary the kit
can actually control. The checker is called *once per step* by the orchestrator harness, after the
step completes and the harness has the numbers. On breach it returns non-zero and the orchestrator
halts and escalates.

This is harness-neutral by design: the kit ships the checker; the harness supplies the numbers.
The checker never touches the LLM API and never measures tokens itself.

## The three dimensions

Each dimension has its own ceiling; **setting a ceiling to 0 disables that dimension**.

| Dimension | What it counts | Why it matters |
|-----------|---------------|----------------|
| **Cumulative tokens** (`MAX_TOKENS`) | `tokens_in + tokens_out` summed across the run | The primary cost driver; cost derived via `COST_PER_1K_USD` |
| **Step count** (`MAX_STEPS`) | Loop iterations / orchestration steps | Catches the cheap-but-endless loop that a token cap misses |
| **Agent-spawn count** (`MAX_AGENTS`) | Total sub-agents spawned by the flow | Catches the multi-agent fan-out ("fork-bomb") pattern |

A shared warn-threshold (`WARN_PCT`, default 80%) emits a `WARN` to stderr on all dimensions
approaching their ceilings, so the operator can intervene before a hard stop.

## The checker — `scripts/runaway-guard.sh`

```
runaway-guard.sh step  --tokens N --agents N   # record this step's usage, then check all ceilings
runaway-guard.sh check                         # verdict only (no record; useful for mid-step audit)
runaway-guard.sh reset                         # start a fresh run (clear/rotate the tally)
```

Verify the kill-switch is wired and enforcing: `sh conformance/runaway-killswitch-wired.sh --selftest`

**Exit codes** (the kit's three-state convention):

- **0 = CONTINUE** — under all enabled ceilings. May emit `WARN` to stderr at ≥ `WARN_PCT`.
- **1 = STOP** — a ceiling is breached. Prints which dimension and the numbers. Orchestrator halts + escalates.
- **2 = UNVERIFIED** — config missing or malformed → fail-closed. Never a silent green.

## The config — `.kit/budget.conf`

The ceiling config is **control-plane** (committed, agent-immutable). An autonomous agent cannot
raise its own ceiling — the kit's path-guard blocks any write to `.kit/budget.conf`. This is the M2-S5 lesson
applied directly: enforcement whose config is agent-writable is not enforced.

```ini
# .kit/budget.conf — E4d runaway ceilings
# A dimension is DISABLED when its value is 0.
MAX_TOKENS=2000000      # cumulative tokens across the run (0 = disabled)
MAX_STEPS=200           # total orchestration steps (0 = disabled)
MAX_AGENTS=50           # total sub-agents spawned (0 = disabled)
WARN_PCT=80             # warn threshold as % of each ceiling (0 = no warnings)
COST_PER_1K_USD=0.003   # token→cost rate for informational cost estimate in STOP messages
```

See `docs/operations/cost-governance.md` for the budget declaration format (the `TASK-CONTEXT-CONTRACT`
`Budget` field and the RUNBOOK `Cost governance:` attestation line). The `.kit/budget.conf` is
the machine-enforced ceiling derived from that human-readable declaration.

## Harness-neutral reference loop

This is the reference pattern for any orchestrator that calls the guard. It is not
Claude-Code-specific — adopt it in whatever harness your project uses.

```sh
# Reference: orchestrator calls the guard once per step; halts + escalates on STOP.
sh scripts/runaway-guard.sh reset
while work_remains; do
  run_one_step                       # harness does the work, reports usage
  if ! sh scripts/runaway-guard.sh step --tokens "$STEP_TOKENS" --agents "$STEP_AGENTS"; then
    escalate "runaway kill-switch tripped"; break
  fi
done
```

- `reset` clears the tally at the start of each run (idempotent).
- `step --tokens N --agents N` appends one record to the tally, sums the run, then checks all
  enabled ceilings. The harness provides `STEP_TOKENS` (reported by the LLM API) and `STEP_AGENTS`
  (spawned this step).
- **Exit 1 (STOP):** the orchestrator must halt the loop and escalate — surface the reason to the
  operator, do not silently continue.
- **Exit 2 (UNVERIFIED):** treat as STOP under CI or `--require`; the config is missing or
  malformed. The checker never returns a silent green when the config is unreadable.

## The two files

- **Ceiling config** — `.kit/budget.conf` — committed, control-plane, agent-immutable. Changing
  a ceiling is a **ratified act** (requires PR + dual review). This is the immutable guarantee.
- **Run tally** — `.kit-run/tally` — runtime state, **gitignored**, ephemeral per-run.
  `reset` clears it; `step` appends one record; `check` sums the append-only log (append-only by convention; the platform cap is the backstop if the log is defeated — see Honest ceiling below).

## Conformance lock

`conformance/runaway-killswitch-wired.sh` (with `--selftest`) verifies the checker stays wired:
under-budget → exit 0; each dimension over ceiling → exit 1 (correct dimension named); warn
threshold → exit 0 + warning; missing/malformed config → fail-closed (exit 2). Registered in
`conformance/claims.tsv` and auto-run in CI via `conformance/verify.sh`.

## Honest ceiling — what E4d does and does not guarantee

**Guarantees:**
- A control-plane, agent-immutable ceiling on tokens/cost, steps, and agent-spawns.
- An executable halt at the orchestration seam on breach.
- A conformance-locked, CI-run, drift-watched proof that the kill-switch stays wired.
- Warn-before-breach at a configurable threshold.

**Does not guarantee:**
- **A hard LLM-API spend cap.** That is platform-owned. Set an API-key or workspace spend
  limit in your LLM provider's console — this is the backstop above E4d, and the only control
  that can actually stop mid-completion billing. See `docs/operations/cost-governance.md`.
- **A tamper-proof runtime tally.** An agent with write access could truncate the tally to
  evade the step ceiling. The primary guarantee is the immutable ceiling config; the
  platform cap is the backstop if the tally is defeated.
- **A tamper-proof guard script body.** The Write/Edit tool path to `scripts/runaway-guard.sh`
  is hard-denied by the path-guard; a direct shell edit is caught by git diff + the per-PR
  conformance run — the same posture as other kit control scripts. Only the `.kit/budget.conf`
  config path carries the hard Write/Edit deny; the script body shares the tally's best-effort
  posture against committed shell tampering.
- **Wall-clock bounding.** Platform/CI job timeouts already own this. Adding it here would
  over-claim a control the kit does not hold.
- **Dollar-precise billing.** `tokens × COST_PER_1K_USD` is an estimate for informational
  STOP messages; the precise cost is the platform's ledger.
