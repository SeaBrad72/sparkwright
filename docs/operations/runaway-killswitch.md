# Runaway kill-switch — reference

How to halt a runaway orchestrated flow before it exhausts tokens, spirals through endless steps, or
fan-outs into unbounded agent spawns. Like the cost-governance reference (`cost-governance.md`),
this ships an **executable checker** and points at the **platform control** that is the hard
ceiling — because the kit cannot *measure* tokens itself (that is the harness/LLM-API's job), but
it *can* enforce a ceiling on *reported* usage and halt the loop.

`scripts/runaway-guard.sh` is the checker. The platform LLM-API cap is the hard ceiling above it.

**The budget is per slice.** One slice is one board **row**; every metered step names its row, each
row is graded alone against its own ceiling, and a new row starts at zero. A second slice's normal
work never trips the first one's ceiling (design: `docs/architecture/2026-09-28-runaway-ceiling-per-slice-design.md`
and its `-confirming-design.md`).

## The story in three controls

| Control | Concern | How |
|---------|---------|-----|
| **H3b cost-governance** (`cost-governance.md`) | A budget posture is *declared + attested* | `conformance/cost-governance-ready.sh` verifies attestation |
| **E4d (this)** | *Resource-exhaustion* runaway — executable enforcement at the orchestration seam | `scripts/runaway-guard.sh step --row <ROW>` called once per step |
| **E2 feature-flags** (`feature-flags.md`) | Soft *release* kill-switch | Flag default-OFF; instant-off at restart |

**Declare the ceiling (H3b) → enforce it at runtime (E4d) → toggle features off instantly (E2).**

## The seam E4d guards

The orchestration seam — the between-step / before-spawn boundary — is the one boundary the kit
can actually control. The checker is called *once per step* by the orchestrator harness, after the
step completes and the harness has the numbers. On breach it returns non-zero and the orchestrator
halts and escalates. This is harness-neutral by design: the kit ships the checker; the harness
supplies the numbers. The checker never touches the LLM API and never measures tokens itself.

## The dimensions

Each dimension has its own ceiling; **setting a ceiling to 0 disables that dimension**.

| Dimension | What it counts | Why it matters |
|-----------|---------------|----------------|
| **Tokens** (`MAX_TOKENS`) | `tokens_in + tokens_out` summed across the row's steps | The primary cost driver; cost derived via `COST_PER_1K_USD` |
| **Agent-spawn count** (`MAX_AGENTS`) | Total sub-agents spawned for the row | Catches the multi-agent fan-out ("fork-bomb") pattern |
| **Step count** (`MAX_STEPS`) | Loop iterations | **Disabled by default (`0`)**: a step count is not a per-slice signal |

A shared warn-threshold (`WARN_PCT`, default 80%) emits a `WARN` to stderr on all dimensions
approaching their ceilings, so the operator can intervene before a hard stop.

## The checker — `scripts/runaway-guard.sh`

```
runaway-guard.sh step  --row ROW --tokens N --agents N   # record this step against ROW, grade ROW alone
runaway-guard.sh check --row ROW               # ROW's verdict (same rc as `step`), writes nothing
runaway-guard.sh check                         # list every row of this repo; flags never-claimed rows
runaway-guard.sh meter --row ROW               # was ROW ever metered, and what has it spent? read-only
runaway-guard.sh reset                         # RETIRED: rc 2
runaway-guard.sh wip   --count N               # is another slice already in flight? (MAX_WIP)
```

- **`step --row ROW`** — `--row` is **required and has no environment fallback** (a missing or
  malformed row is rc 2). `ROW` is `[A-Z0-9][A-Z0-9-]*`, at most 64 characters. Every step prints a
  `metered: ROW tokens(n/N) agents(n/N)` line on stderr (plus ` steps(n/N)` when the effective `MAX_STEPS` is above 0), so the operator sees which row was charged
  and how far it is from its own ceiling, on WARN and STOP too.
- **`check --row ROW`** — the row's verdict with the same exit code `step` would give, recording
  nothing (a mid-step audit).
- **`check`** (no row) — a **listing** of every row in this repo's tally with its totals; rc 1 if any
  row is at its ceiling. It then makes **one** `git ls-remote` of the claim namespaces
  (`refs/claims/*`, `refs/claims-log/*` on `${BOARD_CLAIM_REMOTE:-origin}`), *outside* the lock, and
  prints `never claimed: ROW` for a row that has neither a live claim nor a claims-log entry (a made-up
  row id is visible, though not impossible). The read is **bounded**: non-interactive (no terminal or
  credential prompt, ssh `BatchMode`, a connect timeout, a low-speed abort) and killed by a watchdog
  after `RG_CLAIMS_TIMEOUT` seconds (digits only, default 20). An unreachable remote or a timeout prints
  `claims UNVERIFIED` and **never changes the grading rc**. An empty tally makes no network read.
- **`meter --row ROW`** — asks whether ROW was ever metered. It prints one line on **stdout**:
  `metered: ROW tokens(n/N) agents(n/N) lines=k`, or `unmetered: ROW tokens(0/N) agents(0/N) lines=0`.
  `--row` is required (a missing or malformed row is rc 2). It is **read-only**: it never writes the tally (it may
  create the per-repo state dir and takes the transient lock, as `check` does). Exit codes: **0** metered and under its ceiling; **1** metered and at or
  past it (graded exactly as `check --row`, a scoped `RAISE ROW` included); **3** never metered (no line for
  the row, or no tally file at all); **2** every refusal `check` has (config, poisoned or oversized tally,
  shallow clone, hostile or symlinked state, lock timeout, refused redirection) plus a tally that exists but
  cannot be read. `3` is a `meter`-only code.
- **`reset`** — **retired: rc 2.** The budget is per slice, so a new row starts at zero and there is
  nothing to reset. Nothing lowers a row's total.
- **`wip --count N`** — the work-in-progress ceiling (below).

**Exit codes** (the kit's three-state convention):

- **0 = CONTINUE** — under all enabled ceilings. May emit `WARN` to stderr at ≥ `WARN_PCT`.
- **1 = STOP** — one row's ceiling is breached. The message names the **row**, the dimension and the numbers.
- **2 = UNVERIFIED** — config missing or malformed (including a malformed `RAISE` line, named by line),
  a poisoned or oversized tally, a shallow clone, a hostile state directory, a lock that could not be
  taken, a refused redirection, `reset`, or a step without a valid `--row` → fail-closed. Never a silent green.

## One tally per REPO, one ceiling per ROW

Before `B4-CROSS-SESSION-BUDGET` the tally was `.kit-run/tally`, relative to `$PWD`, so N worktrees
had N ceilings. Before this row it was one file per machine graded as a single sum, so an unrelated
slice's normal work (or a sibling session's) tripped every other slice's ceiling. Now:

```
$HOME/.local/state/sparkwright/runaway/<root-commit>/
    tally.v2      # one line per step:  <epoch> <session-key> <ROW> <tokens> <agents>
    lock/         # the mkdir lock (see The lock below)
```

- **Anchored on `$HOME` only.** `XDG_STATE_HOME` is deliberately *not* honoured: git ignores that
  variable, so supporting it would be a third redirection route that costs an agent nothing.
- **Keyed by the repo's root commit** (`git rev-list --max-parents=0 --first-parent HEAD`, 40 or 64
  lowercase hex), so every worktree and clone of the repo shares one key directory and two different
  repos never share one. **A shallow clone is refused (rc 2)** — it has no stable root; run
  `git fetch --unshallow`. A repo with no commit, or a `$PWD` outside a work tree, is also rc 2.
- **The v1 file is untouched and not read.** `runaway/tally` (the machine-wide file) and any old
  `.kit-run/tally` are dead state: nothing in this version reads or writes them, and they can be deleted.
  Worktrees not yet rebased keep stepping v1 into the old file; that tail fades as those slices land.
- **Session key** = the sanitized work-tree root of `$PWD` — attribution on each line only, never
  grading (a row is graded from all its lines, whichever session wrote them). Outside a work tree the
  guard refuses.
- **The tally grammar is strict and refused at read.** Any line that is not the five-field grammar
  (`<epoch> <session-key> <ROW> <tokens> <agents>`; integers of 1–12 digits, key `[A-Za-z0-9._-]`),
  and any tally past 100 000 lines, fails the guard closed until a human acts. The refusal names the
  path and the **line number**, never the bytes. At the line cap the remedy is archiving
  (`mv tally.v2 tally.v2.<date>`) — which **zeroes every row of the repo**, a far tail.
- **Overflow cannot read as under-budget:** the summed usage clamps at 10^15.
- **Hygiene:** `umask 077`; a non-absolute `$HOME`, or a symlinked or foreign-owned `sparkwright/`,
  `runaway/`, key directory, tally or lock, refuses (exit 2) rather than writing through.

### Redirecting the tally or the config is a human act

`--tally`, `RUNAWAY_TALLY`, `--config` and `RUNAWAY_BUDGET_CONFIG` are **refused (exit 2)** unless the
human dial `KIT_RUNAWAY_SANDBOX=<dir>` is set *and* the path canonicalizes under that directory — and
every run under the dial banners `runaway-guard: SANDBOX override active (<dir>)` on stderr, which the
orchestration loop passes through to the operator. A second tally is a second ceiling; the dial exists
for fixtures and selftests, not for a running session. The default config resolves from the script's
own root, never from `$PWD`.

## Raises

The base ceilings live in `.kit/budget.conf` and apply to **every row alone**. A raise for ONE row is
a config line:

```
RAISE <ROW> MAX_TOKENS=<n> MAX_AGENTS=<n> MAX_STEPS=<n>
```

- It lifts **that row only**; every other row keeps the base ceilings. Any key may be omitted (at
  least one is required); per key, the last line that names it wins. A malformed `RAISE` line
  (bad row, value not a positive integer, unknown key) is **rc 2 naming the line**.
- A raise is **uncommitted and owner-ratified**: the operator adds the line to a working tree's
  config with the owner's word. "Owner-ratified" is a convention until `RUNAWAY-RAISE-ROUTE` ships
  (see *Honest ceiling*: the guard reads the config beside its own script, and only the guarded
  checkout's path-guard protects that file). **A committed `RAISE` line is a defect** — a raise that outlives its
  row is exactly what `BUDGET-CEILING-RESET` was written to end.
- **An unscoped raise.** If `.kit/budget.conf` differs (byte-wise) from its committed copy in `HEAD` and a
  base `MAX_*` value changed, the edit is **honoured, but WARNs on every `step` and `check`**
  (`WARN: unscoped raise: …`, naming the value, `HEAD`'s value and the row being charged): it lifts
  every row. Scope a raise with a `RAISE <ROW>` line instead.
- The full route — a recorded-GO raise with an expiry — is boarded as `RUNAWAY-RAISE-ROUTE`; today a
  raise is a config edit that the owner ratifies by convention, not by a recorded control.

### The operator route after a STOP

When a step STOPs (rc 1), the loop halts and escalates a `runaway-breach` record. The route:

1. The owner rules on the escalation (the `raise-ceiling` verdict is the record of that ruling).
2. **The live route is to add `RAISE <ROW> …` for that row to the config, then re-run** the loop (or
   the step). The `raise-ceiling` verdict **no longer wipes anything**: `scripts/orchestrator-run.sh`
   never resets the tally; it re-checks the row (`check --row`), and the ruling only counts if a
   sufficient `RAISE <ROW>` line is in effect. A verdict with no sufficient raise halts with a message
   naming the line to add, for the breached dimension (`MAX_TOKENS`, `MAX_AGENTS` or `MAX_STEPS`).
   The loop also **refuses to integrate a slice that touches a control-plane path** (`.kit/`,
   `scripts/`, `conformance/`, `hooks/`, `.github/`, `.claude/`, `skills/`, `agents/`, `adapters/`,
   `docs/governance/`, `profiles/`, `CLAUDE.md`, `AGENTS.md`, `DEVELOPMENT-*.md`, `.gitattributes`, `.gitmodules`,
   `CODEOWNERS`, the scanner-ignore files): rc 1, no merge. The match is ASCII case-folded, runs on the raw
   (`git diff -z`) names, and refuses any name with a control byte **or any byte at or above 0x80**: a
   case-insensitive filesystem such as APFS folds far more than ASCII (Kelvin sign to `k`, long-s to `s`,
   NFD equal to NFC), so the loop does not mimic that fold and refuses every non-ASCII path instead. This
   over-denies (an accented filename anywhere is refused), by design. This is **a subset of the guard's
   control-plane set**, covering the runaway actuation surface; `.claude/hooks/guard-core.sh::is_control_plane_path`
   is the authority for the harness guard. The orchestrator also runs its own git actuation with hooks disabled
   (`core.hooksPath` pointed at an empty directory, `core.fsmonitor` and `diff.external` emptied, all through
   git's environment config, so git 2.31 or newer). **This closes the diff/merge channel only.** The engineer
   role runner is NOT sandboxed: it runs under the same uid in a worktree that shares the main `.git`, so it can
   write the main checkout's files directly or plant config; `filter.*` smudge and process drivers, set through
   shared config or attributes, stay covered by that same disclosure, not by this code. The platform usage cap stays the hard ceiling.
3. **A resume with the `RAISE` already in place proceeds without consuming a verdict** — the re-run
   simply does not breach. A stale verdict can never lift a ceiling: it is keyed by the old trace id,
   and the ceiling is lifted only by the config line.

(Design correction I1, from the T3 review: the earlier two-run seam could not reach the raise-ceiling
arm, because a RAISE placed before run 2 means run 2 never breaches. See the design's §9 amendment log.)

## The landing gate — `land` / `actuate` consult the meter

`scripts/promotion-verify.sh` `land` and `actuate` call `meter --row <ROW>` behind the `RUNAWAY_METERING_GATE` dial
(`RUNAWAY-METERING-LANDING-GATE`), **after** the separation-of-duties check and **before** anything is written or merged: a
refusal on `land` writes no note, and a refusal on either verb attempts no merge. The row is the approved commit's
`Kit-Row` trailer on `land` and the GO note's own `kit-row:` on `actuate`; no new note key exists.

- **The dial** is read from the **approved tree**: `git show <approved-sha>:.kit/dials.conf`, only when that entry is a
  regular file (mode 100644/100755; a symlink reads `observe` with a loud line naming it), and never from the working tree
  or a remote ref. A de-escalation is therefore a committed control-plane diff inside the approved PR, visible to the
  owner at GO. The environment variable `RUNAWAY_METERING_GATE=enforce` may **escalate**; it can never de-escalate (an
  `=observe` in the environment prints a line saying the tree wins). An unrecognized **conf** value reads as observe
  with a `WARN`; an unrecognized **environment** value is ignored with a `WARN` (the tree's value applies). Each `WARN`
  names which side it came from. The dial is read with the repository root as the anchor (`git -C <root> ls-tree
  --full-tree`), so the invoking directory does not matter, and with `GIT_NO_REPLACE_OBJECTS=1`, so a `refs/replace/*`
  ref cannot redirect the approved sha to another tree. An approved sha that does not resolve cannot have its dial read, so
  the gate refuses ("the approved sha does not resolve — cannot read the metering dial") on every path except one: `land`
  with the environment not at `enforce` stays silent, because `land`'s own record step refuses the sha before any note or
  merge. `actuate` always refuses (a clone that fetched only the notes ref holds the GO note but not the commit). **Absent is silent**: an adopter export carries no
  dial file and sees nothing. This repo ships `enforce`: the kit's own CI (`conformance/dial-state.sh`, flip and drop mutants) reds a committed disarm on this repo; an adopter tree has no dials file unless it opts in.
  A branch cut before the key merged carries no key, so it reads observe at its head until it merges main.
- **The meter is called with the redirection env scrubbed** (`KIT_RUNAWAY_SANDBOX`, `RUNAWAY_TALLY`,
  `RUNAWAY_BUDGET_CONFIG` are unset for that one call), so a caller cannot point the gate at a tally it wrote.
- **Verdicts.** rc 0 (metered): print the meter line, proceed. rc 3 (never metered): enforce refuses, observe prints
  `unmetered: <ROW> (observe — not gating)` and proceeds. rc 2 (the guard failed closed) and any other rc, including
  127 (guard script missing): enforce refuses naming it, observe prints one line. **rc 1 (metered, at or past the
  ceiling): proceed in both modes**, with `STOP: <ROW> tokens(n/N) … — ceiling breached (landed anyway: approved)` on
  stderr and repeated in the landing report. This is the owner's ruling (F3 "Option A"): `step` already stopped the work
  when the ceiling was crossed, so a refusal after Approve would only force an owner keystroke; surfacing a breach
  *before* Approve belongs to `RUNAWAY-METERING-REVIEW-LEG`. **No row** (no trailer, `(none)`): enforce refuses
  ("cannot meter an unnamed row"), observe prints one line.
- **The enforce refusal names the remedy:** record the slice's **actual summed dispatch usage** with
  `sh scripts/runaway-guard.sh step --row <ROW> --tokens N --agents N`; if the usage is unknown, stop and ask the owner,
  **never estimate**; or the owner ratifies a dial change on the default branch. There is no per-call bypass flag.
- **Docs-only exemption, derived not declared.** The base is the **remote's** `main` (`git ls-remote origin
  refs/heads/main`, which must also exist locally), never the local `origin/main` ref an agent can move; the listing is
  `git diff --name-only --no-renames $(git merge-base <remote-main> <sha>) <sha>`, classified with `conformance/ci-classify-changes.sh` (reused, not
  re-implemented, from the working tree: working-tree scripts are trusted inputs, as for the verb itself); an all-`.md`
  change prints `N/A: docs-only change` and proceeds in both modes. An unreachable remote, a base missing locally, an
  empty listing, or an absent or failing classifier means **not** docs-only, and a `.sh` -> `.md` rename lists both
  paths, so it is not exempt. When the base is the reason, one line says so in both modes (`docs-only exemption unavailable:
  cannot read origin's main`, or `… origin/main tip not fetched — git fetch origin`). Docs is the class that ran away most recently (#710); exempting it is the owner's ruling.
- **Honest ceiling.** The gate proves a row was metered **ever**, not **honestly**: `step --row R --tokens 1 --agents 1`
  passes it. It does not own row identity: a trailer naming any metered row passes (the row-to-branch binding belongs to
  `loop-state` / `backlog-presence`). The tally is **per machine**, so a row metered on another machine reads as
  unmetered here. Both the STOP line and "metered" ride on that self-reported, uid-writable, per-machine tally (and on
  `$HOME`): whoever can write it can suppress them, which is inside the "ever, not honestly" ceiling. On `actuate` the
  GO note already exists (`record` is a separate verb), so a refusal leaves a recorded-but-unmerged GO; the recordless-merge backstop is unaffected. Like the rest of `promotion-verify.sh` it is
  verb-scoped: a raw `gh pr merge` never consults it. `git remote set-url origin` is a local config write that would redirect the docs-only base exactly as it already redirects `record`'s publish/confirm: the same trust tier as the ledger's trust in `origin`, not new to this gate. The docs-only base is read with `git ls-remote origin`; local transport config (`core.sshCommand`, `GIT_SSH_COMMAND`) held by the operator can spoof that answer — the CI recordless-merge backstop is the net, not this gate.

## `wip` — the work-in-progress ceiling

`MAX_WIP` in `.kit/budget.conf` caps how many slices this repo may have **claimed** at once.
`scripts/board-claim.sh claim` counts the live `refs/claims/*` on the forge (excluding the row being
claimed; an unreachable remote refuses) and passes the number to `runaway-guard.sh wip --count <n>`;
the claim refuses on any non-zero. The count comes from the forge rather than the local board because
a parallel session's In Progress row lives on *its* branch and is invisible locally — and the local
board is agent-writable besides. `MAX_WIP` absent or `0` → `N/A (MAX_WIP undeclared)`, exit 0, so a
project without this key keeps claiming normally. A **stale** claim overcounts, conservatively;
`board-claim.sh release <ROW> --stale` is the remedy, and it **refuses unless it can prove the claim is
stale** (a MERGED same-repo PR with no OPEN sibling · the row in `## Done` on the default branch's board —
"branch absent on origin" is evidence only). `sparkwright status` shows which claims are provably stale,
and `refs/claims-log/*` records every release that was taken.

## The lock

Every read-sum-append happens inside a `mkdir` lock beside the tally (bounded 300 × 0.1 s spin — 30 s,
because contenders *serialize*). On timeout the guard exits **2 and appends nothing**. The protocol
(a security-reviewed control; `conformance/runaway-killswitch-wired.sh` legs L1–L6, A7–A9, N1, M1, M4):

- **The lock directory is never moved, except by its own holder at release.** A breaker never renames
  it away and never restores it — the rename-then-restore design allowed a double hold.
- **Tokens are published with an atomic `ln`.** The holder's token is `<pid> <epoch>`; a contender
  publishes one only if the directory it just made (or is taking over) has none.
- **A dead holder's token is taken over in place.** Only a validated *dead* pid whose token is also at
  least 2 s old (`RG_LOCK_MIN_AGE`; a future-dated epoch is never breakable) is broken: the token file is
  `mv`d to `pid.dead.<breaker-pid>` and the breaker publishes its own token into the same directory — or puts
  the moved token back atomically if it turns out not to be the one it judged. EPERM (another uid's
  pid) reads as *alive*.
- **A7 — an abandoned takeover** (a breaker killed after moving the token out): a pid-less directory
  holding only dead `pid.dead.*` tokens (every suffix *and* token content a dead pid) is adopted by an
  atomic `mv` of the lowest one; any live, EPERM, malformed or unreadable file leaves it live.
- **A8 — orphan reaping** (a taker killed between `mkdir` and `ln`): an empty lock directory is
  `rmdir`ed once it is older than `RG_LOCK_ORPHAN_AGE` seconds. The age is read with `find -mmin`, so
  the effective age is whole minutes with a **floor of one minute**.
- **A9 — release** is the holder moving its own directory away and deleting it, so a breaker's later
  `ln` fails instead of publishing into a directory that is being deleted. **N1:** the held flag is
  cleared *before* that move, so a TERM re-entering the release can never move a new holder's lock.
- **The rare fail-closed wedge.** If a lock cannot be taken within 30 s the guard refuses with rc 2 and
  names the remedy: **remove that directory** (`rm -rf` the `lock` directory named in the message,
  after confirming no `runaway-guard.sh` is running). Every new failure mode of this protocol is
  fail-closed, except the accepted M3 residual (see Honest ceiling), which needs a taker stalled ≥ 1 minute.

## Conformance lock

`conformance/runaway-killswitch-wired.sh` (with `--selftest`) verifies the checker stays wired:
under-budget → exit 0; each dimension over ceiling → exit 1 (correct row and dimension named); warn
threshold → exit 0 + warning; missing/malformed config → fail-closed (exit 2); and the v2 file, per-row
grading, RAISE, bounded claims read, locale pin, lock protocol, watchdog and identity legs (selftests
never WRITE to the real `$HOME`). Registered in `conformance/claims.tsv` and auto-run in CI via
`conformance/verify.sh`. Verify: `sh conformance/runaway-killswitch-wired.sh --selftest`

## The config — `.kit/budget.conf`

The ceiling config is **control-plane** (committed). In the guarded checkout, an autonomous agent cannot
raise its own ceiling — the kit's path-guard blocks any write to `.kit/budget.conf`. This is the M2-S5
lesson applied directly: enforcement whose config is agent-writable is not enforced.

```ini
# .kit/budget.conf — E4d runaway ceilings, PER SLICE (row)
# A dimension is DISABLED when its value is 0.
MAX_TOKENS=10000000     # tokens per ROW (0 = disabled) — a runaway DETECTOR, not a budget:
                        #   an M control-plane slice under the build-loop caps measures ~3-5M, so this is a 2-3x margin
MAX_STEPS=0             # steps (0 = disabled; off by default — not a per-slice signal)
MAX_AGENTS=40           # sub-agents spawned per ROW (0 = disabled)
MAX_WIP=2               # slices this repo may have CLAIMED at once (0/absent = disabled)
WARN_PCT=80             # warn threshold as % of each ceiling (0 = no warnings)
COST_PER_1K_USD=0.003   # token→cost rate for informational cost estimate in STOP messages
# RAISE <ROW> MAX_TOKENS=<n> MAX_AGENTS=<n> MAX_STEPS=<n>   # one uncommitted line per raised row; a committed one is a defect
```

See `docs/operations/cost-governance.md` for the budget declaration format. `.kit/budget.conf` is
the machine-enforced ceiling derived from that human-readable declaration. Changing a base ceiling
(including `MAX_WIP`) is a **ratified act** (PR + dual review).

## Harness-neutral reference loop

The reference pattern for any orchestrator that calls the guard; not Claude-Code-specific.

```sh
# Reference: the orchestrator calls the guard once per step for ONE row; halts + escalates on STOP.
ROW=MY-ROW-ID                        # the board row this run serves
while work_remains; do
  run_one_step                       # harness does the work, reports usage
  if ! sh scripts/runaway-guard.sh step --row "$ROW" --tokens "$STEP_TOKENS" --agents "$STEP_AGENTS"; then
    escalate "runaway kill-switch tripped"; break
  fi
done
```

- There is no `reset` at the start of a run: a row that has been stepped before keeps its total, and
  a new row starts at zero.
- `step --row ROW --tokens N --agents N` appends one record, sums **that row**, then checks its
  enabled ceilings. The harness provides `STEP_TOKENS` (reported by the LLM API) and `STEP_AGENTS`.
- **Exit 1 (STOP):** halt the loop and escalate — surface the reason to the operator, do not silently continue.
- **Exit 2 (UNVERIFIED):** treat as STOP under CI or `--require`; the checker never returns a silent green.

## The two files

- **Ceiling config** — `.kit/budget.conf` — committed, control-plane, agent-immutable in the guarded checkout.
- **Repo tally** — `$HOME/.local/state/sparkwright/runaway/<root-commit>/tally.v2` — runtime state,
  never committed, shared by every session and worktree of this repo (append-only by convention; the
  platform cap is the backstop if the log is defeated — see below).

## Honest ceiling — what E4d does and does not guarantee

**Guarantees:**
- A control-plane ceiling (agent-immutable in the guarded checkout) on tokens/cost and agent-spawns, graded **per slice**.
- An executable halt at the orchestration seam on breach, naming the row.
- A conformance-locked, CI-run, drift-watched proof that the kill-switch stays wired.
- Warn-before-breach at a configurable threshold.

**Does not guarantee:**
- **A hard LLM-API spend cap.** That is platform-owned. Set an API-key or workspace spend
  limit in your LLM provider's console — this is the backstop above E4d, and the only control
  that can actually stop mid-completion billing. See `docs/operations/cost-governance.md`.
- **The count is self-reported.** The harness supplies the numbers; the platform usage cap is the hard stop.
- **Mandatory metering, only at landing, only where the dial says so.** A session that never steps is invisible
  while it works; `land`/`actuate` refuse an unmetered row only in a repo whose approved tree carries
  `RUNAWAY_METERING_GATE=enforce` (this repo does; an adopter export ships none), and the gate proves "ever metered",
  not "honestly metered" (see *The landing gate*).
- **A new row id gets a fresh budget.** `check`'s never-claimed flag makes a made-up row visible, not impossible.
- **A ceiling across MACHINES.** The tally is per machine (and per repo): a slice built on two machines
  has two tallies. The provider's spend cap is the only control that spans them.
- **Where the raise is protected.** The guard reads the budget config beside its own script. A dev-clone's
  (or any unguarded clone's) config is agent-writable, so "owner-ratified" is a convention until
  `RUNAWAY-RAISE-ROUTE` ships a recorded-GO raise. The engineer role runner is NOT sandboxed (same uid, shared
  `.git`), and the orchestrator's integration refusal closes the diff/merge channel only (see *The operator
  route after a STOP*).
- **An unscoped raise is loud, not refused.** An edited base `MAX_*` is honoured and WARNs on every step.
  The full route is `RUNAWAY-RAISE-ROUTE`.
- **A tamper-proof runtime tally.** An agent with write access could truncate the tally to evade the
  ceiling. The primary guarantee is the ceiling config (immutable in the guarded checkout); the platform cap is the backstop.
  Stated precisely:
  - **The session key is caller-derived** (attribution only; it has no grading effect).
  - **A6 — non-ASCII paths.** With the `LC_ALL=C` locale pin, a worktree path containing non-ASCII bytes
    sanitizes to a different session key than before the pin. The key is attribution only, so this
    changes no grade.
  - **`rm -f` of the tally is one allowed call** — the tally's best-effort posture, unchanged.
  - **`$HOME` itself is a redirection route,** not bannered, because redirecting it also breaks `ssh`
    and `gh` auth in the same call.
  - **The sandbox dial reaches the tally in a runner file.** In the Claude harness the
    `KIT_RUNAWAY_SANDBOX=… sh scripts/runaway-guard.sh …` spelling is denied by the unvetted-prefix
    rule (pinned in `conformance/agent-autonomy.sh`); a script file that sets it is inside the same
    honest ceiling as every other committed-shell route.
  - **Pid reuse.** A dead holder's pid that the OS has reused reads as **live** (yours answers
    `kill -0`; another uid's answers EPERM): the lock is held until the spin bound expires —
    fail-closed, but a real weakness.
  - **A future-dated epoch is never breakable,** so a lock stamped in the future refuses every step
    (exit 2) until a human removes the lock directory (the refusal names it).
  - **The accepted M3 residual.** A taker **stalled for a minute or more** (e.g. under `SIGSTOP`)
    inside its `mkdir` → `ln` window can, after an orphan reap, publish into a live holder's
    set-aside window and cause a double hold. It needs a stall of at least `RG_LOCK_ORPHAN_AGE`
    (floor one minute); it is noted in the review record and not closed. `record()` is one atomic
    append, so a duplicate holder costs nothing there. **SEC-3, same family:** a TERM landing after a
    failed `ln` publish but before the held flag is cleared makes the trap's release move whatever
    directory is at the lock path; that directory is foreign only after an orphan reap plus a stall of
    at least a minute. Accepted and documented; the optional closure (remember our token, compare it at
    unlock) is a possible future hardening.
  - **Same-uid TOCTOU.** The symlink/ownership checks close a *cross-uid* redirection; the window
    between the check and the append is inside the same-uid trust boundary.
- **A tamper-proof guard script body.** In the guarded checkout, the Write/Edit path to `scripts/runaway-guard.sh` is
  hard-denied by the path-guard; a direct shell edit is caught by git diff + the per-PR conformance run.
- **Wall-clock bounding.** Platform/CI job timeouts already own this.
- **Dollar-precise billing.** `tokens × COST_PER_1K_USD` is an estimate; the precise cost is the platform's ledger.
