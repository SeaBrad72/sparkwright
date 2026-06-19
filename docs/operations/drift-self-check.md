# Drift self-check — the agent's in-loop re-check

**How an agent catches its own drift *during* a long build — before any gate sees it.** In a long
agentic session the work can drift from the plan/standards without anyone noticing: scope creeps, a
Definition-of-Done or security non-negotiable is quietly relaxed as the change grows, or a
doc/CHANGELOG/spec claim ends up describing a control as doing more than it does. This is the
**institutionalized form of the verify-before-build pass** — the manual check that, on this kit's own
build, repeatedly caught the roadmap/docs over-promising before they shipped.

> **Read this first (honest ceiling).** A PreToolUse guard sees command strings, not intent, so it
> **cannot detect semantic drift** — this is a **practice/checklist, not a mechanism**. The honest
> enforcement is the practice itself *plus* the downstream gates (independent review, the CI gates,
> scheduled drift-watch) that catch what the self-check misses. Same honesty class as the high-risk
> self-review in [`review-lane.md`](./review-lane.md): a solo human *can* skip it; what the kit does is
> make it the cheapest, earliest place to catch the problem.

## When to run it (checkpoint-triggered — no timer)

The kit cannot fire a timer, so the trigger is **checkpoint-based discipline**, at:
1. **before requesting review**, 2. **before a release/tag**, and 3. **at each long-session boundary**
— a context compaction, or after a large multi-step chunk where in-context memory may be stale.

## The five drift axes

- **A. Intent & scope** — re-read the active spec's acceptance criteria. Does the diff satisfy them,
  and *only* them? Has anything crept in that was never specced?
- **B. Plan** — still following the agreed plan/sequence, or did the approach silently change? *(Agents
  propose, humans ratify — a silent approach-change defeats that; surface it instead.)*
- **C. Standards** — has any item silently relaxed as the work grew? A quick pass against
  [`../../CLAUDE.md`](../../CLAUDE.md)'s **Security** non-negotiables + **Definition of Done**: tests
  written alongside the code · validation on *every* mutation path · no unguarded non-null assertion ·
  no secret read into context · structured errors.
- **D. Claim vs reality** *(the recurring one)* — do the spec/CHANGELOG/doc claims still match what the
  code actually does? Any **overclaim** (a control described as doing more than it does)? Is an
  **honest ceiling** stated wherever the control can't mechanically enforce?
- **E. Context-loss** *(long-session-specific)* — after a compaction or long run, re-establish ground
  truth (`git status`, branch, `VERSION`, the active spec) rather than trusting stale in-context memory.

## Where it sits (not redundant with the other layers)

| Layer | When | What it catches |
|---|---|---|
| claims-registry / drift-watch ([`../../conformance/claims-registry.sh`](../../conformance/claims-registry.sh)) | between commits · CI/cron | **structural** drift |
| review lane ([`review-lane.md`](./review-lane.md)) | at the review **gate** | independent-reviewer findings |
| **drift self-check (this)** | **during** the build, before any gate | the agent **correcting itself** — earliest, cheapest |

It is the **agent-side complement** to [`agentic-ops.md`](./agentic-ops.md): agentic-ops *observes* the
run (trace + scorecard); the self-check is the agent *correcting itself within* the run.

## Why there is deliberately no conformance gate

The cost-governance, review-lane, and containment references each gate a per-project **attestation
artifact** (a declared budget, a recorded review, a declared sandbox posture). A self-check produces
**no per-project artifact** to verify — gating "did you self-check?" would be an **unverifiable
self-attestation**, i.e. ceremony. So this reference ships **no `*-ready.sh`** and registers **no
claim**: the honest enforcement is the practice plus the real downstream gates, not a green check that
proves nothing.

## Mechanizable axes now automated by `sparkwright doctor`

The **mechanizable** axes (E and part of D — re-run conformance, re-check the claims-registry,
re-establish git ground truth) are **now automated** by [`sparkwright doctor`](./doctor.md)
(shipped 3.18.0). Run `sh scripts/sparkwright doctor` to execute the one-command posture sweep.

The **semantic** axes (A/B intent & scope, C standards, D's overclaim judgment) remain agent/human
judgment — a script cannot read intent. Run the full checklist above before requesting review,
before a release, and at each long-session boundary. A green `sparkwright doctor` means the
mechanizable checks pass; it does not substitute for axes A, B, C, or the judgment half of D.
