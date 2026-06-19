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
  └─ git ground-truth            [ADVISORY]  branch, dirty-tree, tag alignment
```

Run via `sh scripts/sparkwright doctor` (or directly: `sh scripts/doctor.sh`).

## Posture (gating) vs metrics (informational)

The split is intentional and the naming is exact.

**POSTURE** — the default output. Three dimensions:

| Dimension    | Role    | What it runs                         |
|--------------|---------|--------------------------------------|
| `conformance`| GATING  | `conformance/verify.sh` (all checks) |
| `claims`     | GATING  | `conformance/claims-registry.sh`     |
| `git`        | ADVISORY| branch · dirty-tree · tag alignment  |

A FAIL or UNVERIFIED on either gating dimension sets exit 1. The git dimension is ADVISORY only
(WARN-level, never hard-fails alone) — it re-establishes ground truth (axis E from
`drift-self-check.md`) without blocking a green posture on working-branch commits.

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
