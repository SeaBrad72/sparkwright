# Meta-control — the cadenced adversarial go/no-go + retro

**The institutional, adversarial counterpart to [`drift-self-check.md`](./drift-self-check.md).**
The self-check is the agent correcting *itself* during a build (no artifact, no gate). Meta-control is
an **independent adversarial panel**, run at cadence boundaries, that **produces a verdict artifact +
two ledgers** and **routes findings into the backlog**. It catches **direction / proportion /
over-claim** drift — the failure class testing and CI cannot see, because the failure is not
correctness but *whether we are building the right thing, at the right size, honestly, in the right
order.*

It exists because a kit can *declare* meta-controls and never *run* them. That is exactly what
happened here: the go/no-go, the drift-self-check, and the retros were designed but nothing triggered
them except a human noticing — so locally-good slices drifted globally. The 2026-06-23 consolidation
audit (run by hand) was this panel's prototype.

> **Why this one can be gated when the self-check cannot.** `drift-self-check.md` ships no gate
> because it produces no per-project artifact — gating "did you self-check?" would be unverifiable
> self-attestation. Meta-control produces a **committed verdict artifact**, so "is there a *fresh*
> verdict?" *is* verifiable. That gate is **M2** (the staleness gate + verdict ledger). Until M2
> ships, the trigger below is discipline, not enforcement.

## When to run it (the cadence)

- **Every N slices** → the **light (5-lens)** profile. **N defaults to 5** (a review is *due* once 5
  release tags have landed since the last logged run). (M2 enforces "due" via a staleness gate that
  reads the verdict log; N is the gate's input.)
- **At an epic / release / major boundary** → the **full (11-dim)** profile.
- **On demand** when a direction feels off — the cheapest place to catch drift is before the next big
  build, not after (the banked meta-lesson: *re-question the plan, don't just execute it*).

## Two profiles (tiered by trigger — both are kept)

| Trigger | Profile | What it probes |
|---|---|---|
| every N slices | **light = 5-lens** | *depth* on direction / proportion / honesty — the drift catcher |
| epic / release / major | **full = 11-dim** | *breadth* release sweep (most surfaces already covered continuously by CI/conformance) |

### The 5 lenses (light profile)

Each lens is run by an **independent adversarial agent**, **default-to-critical**, under the evidence
standard below:

1. **Scope-coherence & proportion** — is this the right *size* thing? over-build, build-ahead-of-need,
   ceremony with no leverage, a control hardened on an empty surface?
2. **Honesty & over-claim** — declaration-vs-behaviour: do headline / README / CHANGELOG / badge
   claims match what is actually *proven* (vs provided, vs prescribed)?
3. **Enforcement integrity** — the green-while-dark hunt: does each gate verify *behaviour* or merely
   *declaration*? any check drifted green as the code moved beneath it?
4. **Direction & sequencing** — is the *next* planned work still the right next thing, or has the plan
   accreted / drifted? what should be resequenced, merged, or dropped?
5. **Right-weighting & adoptability** — is it too much for the adopter span (vibe-coder → architect)?
   is progressive disclosure intact, or has rigor outrun fit?

### The 11 dimensions (full profile — the major-release breadth sweep)

functional-e2e · greenfield + brownfield adoption · persona-usability (vibe-coder / designer / PO /
QA / DevOps / senior-eng / architect) · harness-neutrality · stack-profiles + BYO · standards-adherence
(TDD / 15-factor / architecture) · security & agent-governance (red-team) · conformance &
CI-enforcement integrity (green-while-dark) · operability & continuity · honesty & internal-consistency
· AI-governance & eval-driven-dev. Run these as the breadth sweep before a major release; the 5 lenses
are a strict-focus subset-plus (they add scope-coherence and direction/sequencing, which the 11 lack).

## How to run it (harness-neutral)

The panel is, abstractly: **fan out one adversarial agent per lens → each emits structured findings
under the evidence standard → an independent *verify pass* refutes or confirms each material finding →
one *synthesis* agent emits the verdict + two ledgers.** Any harness orchestrates this with its own
agent mechanism. There is deliberately **no committed orchestration script** — the *definition* lives
here; the *orchestration* is harness-local. (Claude Code: the [`kit-steward`](../../.claude/agents/kit-steward.md)
agent drives it with subagents / the Workflow tool. Any other harness: assign the steward role to an
equivalent agent and follow this runbook.)

## The machinery (non-negotiable, both profiles)

- **Evidence standard** — every finding cites `file:line` / command-output / a repro, or it is
  **dropped**. Forces depth; kills hand-waving.
- **Structured per-lens output** — the fixed schema below, so findings compile mechanically (no
  re-reading essays).
- **Adversarial verify pass** — each *material* finding is independently re-checked / refuted before
  it counts. Kills false-positive churn.
  - **For cut/retire decisions, the verify pass MUST include a design-intent check** (banked from the
    T3a run, 2026-06-24): for each proposed retire/merge, ask *"does this exist for a deliberate
    design / compliance-crosswalk / persona / process-phase / harness-neutral reason that low-usage
    doesn't capture?"* — **default KEEP** unless genuinely *redundant* (content lives elsewhere) or
    *dead* (completed artifact captured in CHANGELOG + live code). "Few inbound references / rarely
    used" is **not** a cut reason in a front-load-rigor + conditional-obligations kit; the answer to
    "too much" is usually *de-emphasize (partition), not remove*.
- **One synthesis → verdict** — a single integrator produces the verdict and both ledgers.
- **Two ledgers, always** — regardless of verdict (below).
- **Retro fold-in** — the synthesis also answers: *what did the last N slices teach, and into which
  artifact does that learning route?* (the "adjust" step — the loop closes).

### Per-lens output schema

```
lens: <name>
findings:
  - severity: Blocker | High | Medium | Low
    title: <short>
    evidence: <file:line | command + output | repro steps>   # REQUIRED or the finding is dropped
    claim_vs_reality: <what is claimed> vs <what is true>     # for honesty/enforcement lenses
    recommendation: <concrete next action>
verify:                                                       # filled by the verify pass
  - finding: <title>
    status: confirmed | refuted | downgraded
    note: <independent re-check evidence>
```

### Verdict scale

- **GO** — 0 blockers, 0 unaddressed highs on the supported path.
- **GO-WITH-CONDITIONS** — 0 blockers; highs are fix-forward and don't break the verified path or a
  headline claim.
- **NO-GO** — ≥1 blocker.

### The two ledgers (produced every run)

- **Ledger 1 — verified-as-quality:** what was probed deeply and held (the "ship with confidence"
  set).
- **Ledger 2 — fix-forward:** ranked findings (Blocker → Low), grouped into workstreams with a
  suggested sequence.

## Routing (closing the loop)

A run that routes nothing is theater. After synthesis:
- **Ledger-2** items become `ROADMAP-KIT.md` / backlog entries (ranked).
- **Ledger-1** is recorded (the confidence set).
- Any **guardrail / standards / process** change is proposed as a **human-ratified PR** — agents
  propose, humans ratify (`DEVELOPMENT-PROCESS.md`). Never silently re-plan or weaken a guardrail.

## The verdict log

Each run appends one row to the kit's verdict log (`docs/governance/meta-control-log.md`):

`date · version · trigger · profile · verdict · verdict-artifact · one-line ledger summary`

This is the kit's own run history; **adopters keep their own log** (start fresh).

## The freshness gate (M2 — the cadence circuit-breaker)

`conformance/meta-control-fresh.sh` enforces the cadence so the panel can't be *designed but never
run*. It is **DUE** once more than **N=5** release tags have landed since the last addressed run, read
from a one-line machine marker `docs/governance/.meta-control-last` (`VERSION VERDICT`, e.g.
`3.48.0 GO-WITH-CONDITIONS`) that the check keeps in lockstep with the log's last row.

- **Where it bites** — the gate runs in the weekly `drift-watch` as its own `meta-control-freshness`
  job (an OVERDUE result fails *that* job — the loud, attributable signal) and is surfaced as an
  advisory `doctor` metric. Per-PR CI runs only the gate's `--selftest` (mechanism + marker↔log sync),
  **never** the live freshness verdict — so an overdue kit never blocks unrelated PRs; it stays visible
  weekly until addressed.
- **Applicability is a detected trigger, never a declared mode** — the gate applies when a project
  *practices* the cadence (its log/marker exist) or on the kit's own repo; otherwise **N/A** (a
  solo/vibe-coder who never adopted the cadence is never nagged). A declared mode can never weaken it
  (`conformance/mode-enforcement-blind.sh`), so an autonomous squad cannot soften the circuit-breaker.
- **What satisfies it** — a logged panel **run** *or* a dated, reasoned **`DEFERRED`** row (a
  human-ratified "not now"). Both append a log row and advance the marker. The gate enforces *that a
  conscious cadence decision was recorded*, not that a specific ritual was performed. Serial deferral
  is a visible pattern in the log for the next panel to question — not a gate it can dodge forever (the
  N-tag clock re-fires).

> Logging a run **or** a deferral means updating two files together: append the row to
> `meta-control-log.md` **and** set `.meta-control-last` to the same `VERSION VERDICT`. The gate fails
> on desync, so they cannot drift apart silently.

> **M2-S5 hardening (ratification integrity).** The marker + verdict log are **control-plane** — an
> agent cannot write them (Edit/Write *and* shell are denied; `KIT_GUARD_SELFEDIT=1` or a human commit
> is required), so a verdict is a human-ratified act, not something the governed agent can self-issue.
> The gate also **rejects a future-pinned marker** (a version ahead of `VERSION`) and **caps serial
> deferral** (≥2 consecutive `DEFERRED` → OVERDUE). Together these make *"an autonomous squad cannot
> soften the circuit-breaker"* hold mechanically, not by assertion.
>
> *The shell-mutation deny is a speed-bump like the rest of the guard (`docs/operations/runtime-guards.md`);
> the durable control is the Edit/Write-tool deny plus the human-reviewed commit that authors the verdict.*
>
> The freshness gate also rejects a marker that is future-pinned or that corresponds to no real release point (a tag or the current `VERSION`). This is **defense-in-depth, not a tamper boundary** — the actual guarantee that an agent cannot move the marker is its control-plane status (the guard denies writes); an offline file-based gate cannot resist an attacker who can already write the marker.

## Who runs it (the Kit-Steward — neutral role)

A **steward agent** owns the meta-control: it runs the panel, synthesizes the ledgers, and *produces*
the verdict artifact + log row + routed proposals — **as text the human commits**, proposing, never
ratifying or writing to the repo itself. The role is harness-neutral; the Claude-native binding is
[`../../.claude/agents/kit-steward.md`](../../.claude/agents/kit-steward.md). On any other harness,
assign the same remit to an equivalent agent.

## Where it sits (not redundant with the other layers)

| Layer | When | What it catches |
|---|---|---|
| CI / conformance / golden-path | every push | **correctness / structural** drift |
| `sparkwright doctor` | on demand / pre-release | **mechanizable posture** (conformance, claims, git) |
| drift-self-check | *during* a build | the agent **correcting itself** (no artifact, no gate) |
| **meta-control (this)** | **at cadence boundaries** | **direction / proportion / over-claim** — adversarial, produces a verdict artifact, **gated by M2** |
