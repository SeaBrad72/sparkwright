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
runaway-guard.sh reset                         # start a fresh run (clear THIS session's lines)
runaway-guard.sh wip   --count N               # is this machine already at its slice ceiling?
```

## One ceiling per MACHINE, not per worktree

Until `B4-CROSS-SESSION-BUDGET` the tally was `.kit-run/tally` — a path **relative to `$PWD`**, and
gitignored. Two sessions in two worktrees therefore got **two independent ceilings**: the owner
declared one budget and the machine enforced N. The tally now lives in one place per machine:

```
$HOME/.local/state/sparkwright/runaway/
    tally         # one line per step:  <epoch> <session-key> <tokens> <agents>
    lock/         # the mkdir lock; lock/pid is the holder's liveness token
```

- **Anchored on `$HOME` only.** `XDG_STATE_HOME` is deliberately *not* honoured: git ignores that
  variable, so supporting it would be a third redirection route that costs an agent nothing.
- **Keyed by machine, not by repository.** The thing the ceiling protects is *your spend on this
  laptop*, which is per account, not per checkout. Two projects with different ceilings on one
  machine each compare the **combined** usage against **their own** ceiling — the conservative
  direction.
- **Session key** = the sanitized work-tree root of `$PWD` (`git rev-parse --show-toplevel`), so one
  worktree is one session. Outside a work tree there is no key and the guard refuses (exit 2).
- `check` sums **every** key (that is the combined ceiling); `reset` rewrites the tally keeping every
  **other** session's lines, so an orchestrator's `reset` at run start cannot clear a neighbour's run.
- **Hygiene:** `umask 077`; a non-absolute `$HOME`, a symlinked `sparkwright/`, `runaway/`, tally or
  lock, or any of those owned by another uid, all refuse (exit 2) rather than write through.
- **Serialization:** every read-sum-append and every `reset` rewrite happens inside a `mkdir` lock
  (bounded 300 × 0.1 s spin — 30 s, because contenders *serialize*, so the bound has to cover a
  queue of holders rather than one; CI measured 20 parallel steps exceeding a 5 s bound on a 2-vCPU
  runner). The holder's token is `<pid> <epoch>`. A lock with no pid file, an unparseable token, or
  a token younger than 2 s counts as **live**; only a validated *dead* holder's lock that is also at
  least 2 s old is broken, by `mv lock lock.stale.$$` — and after that rename the breaker re-reads
  the token it moved and puts it back if it is not the one it judged. Both rules exist for the same
  race: a contender can read holder A's pid, A can release, B can take the lock, and the contender's
  now-stale "A is dead" would otherwise rename a **live** holder's lock away. On timeout the guard
  exits **2 and appends nothing** — a lost line would read as under-budget.
- **The tally grammar is strict and refused at read.** Any line that is not
  `<epoch> <session-key> <tokens> <agents>` (three 1–12-digit integers, key `[A-Za-z0-9._-]`), and any
  tally past 100 000 lines, fails the guard closed for **every** session on the machine until a human
  removes the file. The refusal names the path and the **line number**, never the bytes. That is the
  right trade for a shared file any local process can write: it fails toward STOP. The remedy is
  `rm -f ~/.local/state/sparkwright/runaway/tally`.
- **Overflow cannot read as under-budget:** the summed usage clamps at 10^15.
- **Old per-worktree tallies are dead state.** Any `.kit-run/tally` left in a checkout from before
  this change is no longer read by anything and can be deleted.

### Redirecting the tally or the config is a human act

`--tally`, `RUNAWAY_TALLY`, `--config` and `RUNAWAY_BUDGET_CONFIG` are **refused (exit 2)** unless the
human dial `KIT_RUNAWAY_SANDBOX=<dir>` is set *and* the path canonicalizes under that directory — and
every run under the dial banners `runaway-guard: SANDBOX override active (<dir>)` on stderr, which the
orchestration loop passes through to the operator. A second tally is a second ceiling, which is the
defect this control exists to close; the dial exists for fixtures and selftests, not for a running
session. The default config resolves from the script's own root, never from `$PWD`.

### `wip` — the work-in-progress ceiling

`MAX_WIP` in `.kit/budget.conf` caps how many slices this machine may have **claimed** at once.
`scripts/board-claim.sh claim` counts the live `refs/claims/*` on the forge (excluding the row being
claimed; an unreachable remote refuses) and passes the number to `runaway-guard.sh wip --count <n>`;
the claim refuses on any non-zero. The count comes from the forge rather than the local board because
a parallel session's In Progress row lives on *its* branch and is invisible locally — and the local
board is agent-writable besides. `MAX_WIP` absent or `0` → `N/A (MAX_WIP undeclared)`, exit 0, so a
project without this key keeps claiming normally. A **stale** claim overcounts, conservatively;
`board-claim.sh release <ROW> --stale` is the remedy — and since `B2-SESSION-IDENTITY-LEDGER` that
remedy **refuses unless it can prove the claim is stale** (a MERGED same-repo PR with no OPEN
sibling · the row in `## Done` on the default branch's board — "branch absent on origin" is
evidence only, since under one-push-per-PR that is the normal state of a healthy in-build slice), so a
ceiling breach can no longer be cleared by asserting staleness; `sparkwright status` shows which
claims are provably stale, and `refs/claims-log/*` — which the `refs/claims/*` WIP glob deliberately
does **not** match — records every release that was taken.

### A combined breach: what `raise-ceiling` does and does not clear

When the orchestrator escalates a breach and a human answers `raise-ceiling`, the loop's `reset`
clears **only this run's** lines. On a *combined* breach the other sessions' usage still sums toward
the ceiling, so the next step may breach again immediately. That is not a bug to route around: the
remedies are a **ratified raise** of `MAX_TOKENS`/`MAX_STEPS`/`MAX_AGENTS` in `.kit/budget.conf`, or
waiting for the other session to finish and reset.

Verify the kill-switch is wired and enforcing: `sh conformance/runaway-killswitch-wired.sh --selftest`

**Exit codes** (the kit's three-state convention):

- **0 = CONTINUE** — under all enabled ceilings. May emit `WARN` to stderr at ≥ `WARN_PCT`.
- **1 = STOP** — a ceiling is breached. Prints which dimension and the numbers. Orchestrator halts + escalates.
- **2 = UNVERIFIED** — config missing or malformed, a poisoned or oversized tally, a hostile state
  directory, a lock that could not be taken, or a refused redirection → fail-closed. Never a silent green.

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
MAX_WIP=2               # slices this machine may have CLAIMED at once (0/absent = disabled)
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
  a ceiling (including `MAX_WIP`) is a **ratified act** (requires PR + dual review). This is the
  immutable guarantee.
- **Machine tally** — `$HOME/.local/state/sparkwright/runaway/tally` — runtime state, never
  committed, shared by every session on this machine. `step` appends one keyed record; `check` sums
  **all** sessions; `reset` removes only the caller's own lines (append-only by convention; the
  platform cap is the backstop if the log is defeated — see Honest ceiling below).

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
- **A ceiling across MACHINES.** The tally is per machine by design. The provider's spend cap is
  the only control that spans them.
- **A tamper-proof runtime tally.** An agent with write access could truncate the tally to
  evade the step ceiling. The primary guarantee is the immutable ceiling config; the
  platform cap is the backstop if the tally is defeated. Stated precisely, post-`B4`:
  - **The session key is caller-derived.** Reset scoping protects cooperating sessions from each
    other's *accidents*, not from a hostile one: `cd <other-worktree> && sh scripts/runaway-guard.sh
    reset` is an ordinary allowed call, and sanitization can collide `/a/b` with `/a_b`.
  - **There is no script-level full clear — and none is needed to defeat it.**
    `rm -f ~/.local/state/sparkwright/runaway/tally` is one allowed call. That is the tally's
    pre-existing best-effort posture, unchanged here.
  - **`$HOME` itself is a redirection route.** It is not bannered, because redirecting `$HOME` also
    breaks `ssh` and `gh` auth in the same call — the cost that makes it a non-route in practice, not
    a control that forbids it.
  - **The sandbox dial reaches the tally in a runner file.** In the Claude harness the
    `KIT_RUNAWAY_SANDBOX=… sh scripts/runaway-guard.sh …` spelling is denied by the unvetted-prefix
    rule (measured, pinned in `conformance/agent-autonomy.sh`); a script file that sets it is inside
    the same honest ceiling as every other committed-shell route.
  - **Pid reuse, precisely.** A dead holder's pid that the OS has since reused reads as **live**,
    whoever owns the reusing process: yours answers `kill -0` directly, and another uid's answers
    **EPERM**, which proves existence and is therefore also read as live. The lock is then held until
    the spin bound expires — fail-closed, but a real weakness (a reused pid can keep a stale lock
    alive for 30 s).
  - **A future-dated epoch is never breakable.** The age gate compares the token's epoch with now, so
    a lock stamped in the future — clock skew, or a hostile same-uid writer planting one — can never
    reach the 2-second threshold, and every step on the machine then refuses at exit 2 until a human
    removes the lock directory (the refusal names that remedy). Fail-closed by construction, and a
    denial-of-service a same-uid process can already cause more directly by holding the lock.
  - **A residual duplicate-holder window.** Between a breaker's rename of a stale lock and the
    atomic `mkdir` that restores it when the token turns out not to be the one it judged, there are
    microseconds in which two processes can believe they hold the lock — reachable only if a holder
    older than 2 s releases inside that window. `record()` is an atomic append, so a duplicate costs
    nothing there; `reset`'s read-modify-write could drop a line. This is one of the reasons the
    tally is best-effort state rather than a transaction log.
  - **Same-uid TOCTOU.** The symlink/ownership checks close a *cross-uid* redirection; the window
    between the check and the append is inside the same-uid trust boundary, where a local process
    can already write the file directly.
- **A tamper-proof guard script body.** The Write/Edit tool path to `scripts/runaway-guard.sh`
  is hard-denied by the path-guard; a direct shell edit is caught by git diff + the per-PR
  conformance run — the same posture as other kit control scripts. Only the `.kit/budget.conf`
  config path carries the hard Write/Edit deny; the script body shares the tally's best-effort
  posture against committed shell tampering.
- **Wall-clock bounding.** Platform/CI job timeouts already own this. Adding it here would
  over-claim a control the kit does not hold.
- **Dollar-precise billing.** `tokens × COST_PER_1K_USD` is an estimate for informational
  STOP messages; the precise cost is the platform's ledger.
