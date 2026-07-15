# sparkwright doctor — reference

**`sparkwright doctor` is an adopter-facing POSTURE command** that composes the kit's mechanizable
conformance and drift-detection checks into one sweep. It automates the mechanizable drift axes
(D claim-integrity, E git ground-truth) from [`drift-self-check.md`](./drift-self-check.md) — the
semantic axes (intent/scope, plan alignment, overclaim judgment) remain agent/human judgment.

## What it composes

```
sparkwright doctor
  ├─ conformance/verify.sh       [GATING]    every registered conformance check
  ├─ conformance/claims-registry.sh [GATING] every headline claim's verifier
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
| `claims`     | GATING  | `conformance/claims-registry.sh`                   |
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
| `--selftest`| Built-in regression test: stubs the composed commands, verifies the render contract and exit-code logic. Wired to CI via `conformance/doctor-wired.sh`. |

## Graceful degradation in adopter repos

A missing composed script is **never a false PASS**:

- `conformance/verify.sh` not present → `conformance: UNVERIFIED (not present)` (WARN; exit 1 under `--require`)
- `conformance/claims-registry.sh` not present → `claims: UNVERIFIED (not present)` (WARN; exit 1 under `--require`)
- `scripts/dora.sh` / `scripts/agent-scorecard.sh` not present → `N/A (not present)` in the metrics section

An adopter who hasn't wired the full conformance suite yet sees honest UNVERIFIED/N/A, not a green
check that proves nothing.

## Honest ceiling

`sparkwright doctor` automates the **mechanizable** drift axes:

- **D (claim-integrity)** — re-runs every registered claim's verifier via `claims-registry.sh`.
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
