# sparkwright doctor — reference

**`sparkwright doctor` is an adopter-facing POSTURE command** that composes the kit's mechanizable
conformance and drift-detection checks into one sweep. It automates the mechanizable drift axes
(D claim-integrity, E git ground-truth) from [`drift-self-check.md`](./drift-self-check.md) — the
semantic axes (intent/scope, plan alignment, overclaim judgment) remain agent/human judgment.

## What it composes

```
sparkwright doctor
  ├─ conformance/verify.sh       [GATING]    every registered conformance check
  ├─ conformance/claims-registry.sh [GATING] every headline claim's verifier (kit-self; N/A on an adopter tree)
  ├─ git ground-truth            [ADVISORY]  branch, dirty-tree, tag alignment
  └─ conformance/kit-current.sh  [ADVISORY]  is the kit you ADOPTED behind the current release?
```

Run via `sh scripts/sparkwright doctor` (or directly: `sh scripts/doctor.sh`).

## Posture (gating) vs metrics (informational)

The split is intentional and the naming is exact.

**POSTURE** — the default output. Four dimensions:

| Dimension    | Role    | What it runs                                       |
|--------------|---------|----------------------------------------------------|
| `conformance`| GATING  | `conformance/verify.sh` (all checks)               |
| `claims`     | GATING (kit-self) | `conformance/claims-registry.sh`; `N/A (kit-self…)` on an adopter tree |
| `git`        | ADVISORY| branch · dirty-tree · tag alignment                |
| `kit-update` | ADVISORY| `conformance/kit-current.sh` — adopted kit vs current release |

A FAIL or UNVERIFIED on either gating dimension sets exit 1. The git dimension is ADVISORY only
(WARN-level, never hard-fails alone) — it re-establishes ground truth (axis E from
`drift-self-check.md`) without blocking a green posture on working-branch commits.

### The `kit-update` dimension — the surfacing (P1.2/T7)

The kit's own recurring failure — the board calls it **KW21** — is a capability that is built,
conformance-checked, and **invisible in practice**. P1.2 shipped an updater; *an updater nobody is ever
prompted to run **is** that failure.* So the surfacing is not a nicety bolted onto `kit-update` — it is
the half that makes it exist. `doctor` is the adopter's **decision point**: the moment they are already
asking "what is my posture?". That is where they are told.

`conformance/kit-current.sh` compares the version this project **adopted** (`kit-base:VERSION`, a fact
recorded at inception) against the newest release **tag** at the kit source (`git ls-remote` — the git
protocol, **no forge API**). It renders as one row:

| Check's exit | Row | Meaning |
|---|---|---|
| `0` | `kit-update  OK` | up to date (or ahead). **One quiet line — an up-to-date adopter is never nagged.** |
| `1` | `kit-update  WARN` | **BEHIND** — names `v<OLD>` → `v<NEW>` and the exact `kit-update` command to see the delta. |
| `2` | `kit-update  N/A` | UNVERIFIED — the source is unreachable (offline). Staleness is **unknown**, and is *not* assumed OK. |
| `3` | `kit-update  N/A` | Not an adopted tree (no `kit-base`) — e.g. the kit's own repo. Decided with **no network at all**. |

**Why ADVISORY and never a gate.** *Being behind is not a defect.* A project pinned to last month's kit
is making a legitimate choice — often the right one. A PR gate that reddened on it would fire on the
happy path of every adopter, every week, and people would learn to ignore it; then it is worth nothing
when it fires for real. It can never fail a build. (Same call as `mirror-current.sh` — a staleness check
belongs in `doctor`/drift-watch, not in `verify.sh`.) The two halves are equally load-bearing: the
adopter **must** be told when they are behind, and **must not** be nagged when they are not.

**Honest ceiling.** It compares *versions*, not *trees*: `OK` means "no newer release is tagged at that
source" — it does not mean your tree is unmodified, and it does not compute the delta. Computing the
delta is `kit-update`'s job, and it is the thing this row tells you to go and run.

**METRICS** (`--full` only) — appended after the posture summary, clearly labelled
*"METRICS (informational — does not affect exit)"*. Runs `scripts/dora.sh` and
`scripts/agent-scorecard.sh`.

**Why metrics never gate:** DORA and agentic-ops are *measurement tools*, not pass/fail gates.
DORA measures deployment frequency, lead time, change failure rate, and restore time — the kit's
principle is that metrics measure, they don't gate. A missed DORA collection is an observation gap,
not a posture failure. Similarly, the `agent-scorecard` is a trend-score, not a run-gated verdict.
Collapsing measurement and gating mixes signal and noise, and makes `--full` produce false
CI failures on untracked repos or fresh clones. The two concerns are deliberately separate.

## Flags

| Flag        | Effect |
|-------------|--------|
| *(none)*    | Posture sweep. Exit 1 on GATING FAIL. UNVERIFIED → warn only. |
| `--require` | Strict: UNVERIFIED also exits 1. Auto-set inside CI (`$CI` env). |
| `--full`    | Posture + metrics (informational). Exit code unchanged by metrics. |
| `--quick`   | The advisory lines only: skips conformance and claims, which read `UNVERIFIED (skipped by --quick…)`. Never a pass; see below. Refused (exit 2) with `--full` and with `--as agent`. |
| `--selftest`| Built-in regression test: stubs the composed commands, verifies the render contract and exit-code logic. Wired to CI via `conformance/doctor-wired.sh`. |

## Progress, the estimate and `--quick` (SWAS-201)

A full run on a real tree takes tens of minutes, so doctor says where it is. **Everything below is on stderr**; stdout is
byte-identical to a run without it. A `--selftest-e2e` run stays silent.

```
doctor: 7 steps; estimate 25-50 min on an adopter tree (an estimate from the 2026-10-14 field run; ...). Use --quick for the advisory lines in under a minute.
doctor [1/7] conformance battery (conformance/verify.sh) ...
doctor [1/7]   row 3/<T> agent-autonomy PASS (14m02s)
doctor [1/7] done in 41m10s (row <T>/<T> reported)
doctor [2/7] claims registry: N/A on this tree (kit-self), skipped
...
doctor: finished in 41m31s
```

- **`[k/N]`** counts the steps this run will enter, from the same predicates the dimensions use, so k ends at N on a normal
  exit. The default run has up to 7 (conformance, claims, git, kit-update, permissions, the tracker credential line when a
  `.kit/tracker.conf` exists, the forge identity line); `--full` adds four metric steps.
- **`row i/T name STATUS (elapsed)`** relays one line per result row of `verify.sh`. `T` is read at run time from the
  `^check ` lines of `conformance/verify.sh`; no count is written down anywhere. The time is elapsed, not an ETA: row times
  vary by two orders of magnitude, so an extrapolation would be wrong where it matters most.
- **The verdict never comes from that stream.** `verify.sh`'s exit status travels through a status file (POSIX `sh` has no
  `pipefail`). A status file that is missing, empty or not a number (an interrupted run, a killed child) renders
  `conformance FAIL`, never PASS.
- **The estimate is a dated sentence, not a computation.** Doctor mutates nothing, so it cannot remember an earlier run. The
  figures are 25-50 min on an adopter tree (verify alone) and 55-95 min on the kit's own tree (verify, then a claims registry
  that runs the guard battery again). **Re-measure them at each MINOR** from the `done in` lines of a real run and change the
  sentence in `scripts/doctor.sh` (`_pg_announce`) and the figures here together.

**`--quick`** skips exactly two steps, conformance and claims, and still runs git, kit-update, permissions, the tracker
credential line and the forge identity line. It prints its own estimate (`doctor: --quick: N steps; estimate under 1 min
(plus up to about 20 s of bounded tracker reads); conformance and claims are NOT run.`).

- The conformance row reads `UNVERIFIED (skipped by --quick: run doctor without --quick for this verdict)`. So does the
  claims row on a kit-marked tree. On an unmarked (adopter) tree claims stays `N/A (kit-self…)`, because the dimension does
  not apply there, skip or not.
- **Overall is never PASS under `--quick`.** Not required: `Overall: WARN  (--quick: conformance and claims were NOT run;
  this is not a pass. …)`, exit 0. Required (`--require`, or `$CI` set): `Overall: FAIL  (--quick under --require/CI: the
  gating dimensions were skipped, not failed. …)`, exit 1. A required verdict cannot be quick.
- `--quick --full` and `--quick --as agent` (either order) are usage errors, exit 2.

**The claims registry runs a repeated verifier once.** Inside one `claims-registry.sh` pass, a verifier string that already
ran reuses its recorded exit code and output (the memo is shell variables in that process, no file or flag). Every row still
prints its own PASS, UNVERIFIED or FAIL line under its own id, and a non-pass prints its diagnostics on every row it covers.
Today that is the three claims that share one orchestrator-loop wiring check.

## Graceful degradation in adopter repos

A missing composed script is **never a false PASS**:

- `conformance/verify.sh` not present → `conformance: UNVERIFIED (not present)` (WARN; exit 1 under `--require`)
- `claims` is **kit-self**: the registry grades the kit's own headline claims, so on a tree with neither kit marker (`docs/ROADMAP-KIT.md`, `.github/workflows/golden-path.yml`) — every exported or incepted project — the row reads `claims N/A (kit-self…)`, runs nothing, and adds no WARN and no failure (also under `--require`). Your project's own claims are not graded here.
- On a kit-marked tree, `conformance/claims-registry.sh` not present → `claims: UNVERIFIED (not present)` (WARN; exit 1 under `--require`)
- `scripts/dora.sh` / `scripts/agent-scorecard.sh` not present → `N/A (not present)` in the metrics section

An adopter who hasn't wired the full conformance suite yet sees honest UNVERIFIED/N/A, not a green
check that proves nothing.

## Honest ceiling

`sparkwright doctor` automates the **mechanizable** drift axes:

- **D (claim-integrity)** — re-runs every registered claim's verifier via `claims-registry.sh` (kit-self; N/A on an adopter tree).
- **E (git ground-truth)** — re-establishes branch, dirty-tree, and tag alignment without trusting stale in-context memory.

It does **not** detect **semantic drift** — intent vs accepted spec, plan alignment, or whether a
doc overclaims what a control actually does. Those are judgment calls that require reading
intent, not running a script. They remain the agent/human checkpoint in
[`drift-self-check.md`](./drift-self-check.md) (axes A/B/C and the judgment half of D).

**A green `sparkwright doctor` does not mean "the project is correct."** It means the registered
conformance checks pass, the claims are backed by passing verifiers, and git state is what you
expect. Correctness — whether the right thing was built and the docs accurately describe it — is
still agent/human territory.

## Control-plane protection

`scripts/doctor.sh` and `scripts/sparkwright` are in the guard's named control-plane set. An
unratified edit to either file is denied by the guard and flagged by the `agent-boundary` CI gate.
A governance tool that the agent it governs can silently rewrite is not a governance tool.
