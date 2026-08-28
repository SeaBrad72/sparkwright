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

**The panel obligation binds at boundaries, not per-slice** (`D-240819-5`, owner-ruled 2026-08-19):

- **At an epic / release / major boundary** → the **full (11-dim)** profile. This is the standing
  obligation.
- **On demand** when a direction feels off — the cheapest place to catch drift is before the next big
  build, not after (the banked meta-lesson: *re-question the plan, don't just execute it*).
- **When the freshness gate reads OVERDUE between boundaries** → run **the light 5-lens panel**. This is
  the **backstop procedure the freshness gate prescribes**: `conformance/meta-control-fresh.sh`'s OVERDUE
  cure text says *"Run the light 5-lens panel per docs/operations/meta-control.md"* verbatim, and the
  named procedure it sends you to is [*The light 5-lens panel*](#the-light-5-lens-panel-the-5-lenses)
  below. `scripts/release-tag.sh` prescribes the same procedure one band later, on **ESCALATED** — where
  it *refuses to tag* until a log row lands; its OVERDUE arm only warns and lets the tag proceed. Run
  the panel, or record a dated human-ratified `DEFERRED` row.

> **What changed, and why.** Running the light profile *"every N slices"* used to be a standing
> obligation in its own right, and it over-fired: panel exhaust peaked at **31 panels in one week**
> (late June 2026) before self-correcting to roughly one a week. `D-240819-5` moved the obligation to
> boundaries + on-demand and kept the light panel as the gate's backstop. **The enforcement constant is
> untouched:** `conformance/meta-control-fresh.sh` still reads **N=5** (see *The freshness gate* below),
> so the relax cannot become "never" — the gate goes OVERDUE and prescribes the light panel. What moved
> is what the *doc obligates*, not what the *gate enforces*.

## Two profiles (both are kept — one is the obligation, one is the backstop)

| Trigger | Profile | What it probes |
|---|---|---|
| **epic / release / major boundary**, + on demand | **full = 11-dim** | *breadth* release sweep (most surfaces already covered continuously by CI/conformance) — **the standing obligation** |
| **the freshness gate reads OVERDUE** between boundaries | **light = 5-lens** | *depth* on direction / proportion / honesty — the drift catcher; **the backstop, no longer a standing per-N-slices obligation** |

### The light 5-lens panel (the 5 lenses)

**This is the named procedure the freshness gate's OVERDUE cure text prescribes** — the exact phrase in
`conformance/meta-control-fresh.sh` is *"Run the light 5-lens panel per docs/operations/meta-control.md"*,
and this section is where it lands. `scripts/release-tag.sh` prescribes the same procedure on its
**ESCALATED** branch (where it refuses to tag); its OVERDUE arm is advisory and only warns. It is a
**backstop**, not a standing per-N-slices obligation (`D-240819-5`).

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
- **Two standing questions, every panel** (adopted `D-240811-2.4`, panel #39): *(a)* **"which
  shipped permission-surface allows would we not re-ratify today?"** — the enforcement surfaces a
  ruling depends on (allowlists, guard arms, hook copies) are audited as delivered-or-not, not
  assumed (the B8/B9-measured permission-surface class); *(b)* **scope-coherence** — does each
  slice's declared scope, diff, and design agree, and did any mechanism's reach silently widen?
- **Third-carry auto-escalation** (adopted `D-240811-2.4`, panel #39): a finding carried to its
  **third consecutive panel** escalates one severity and must leave that panel with a ruling, a
  funded unit, or a dated deferral — a carry is a signal the routing failed, not a status quo.
  (First application: `BOARD-DOR-FIELDS`, funded at the #39 sitting.)

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
- **Ledger-2** items become backlog entries (ranked) — **`BACKLOG.md` is the one routing
  destination, epic-scale items included** (`D-240813-4.5`, panel #40, recording four consecutive
  panels of actual practice; the former roadmap file was superseded in place, `D-240815-1`).
- **Ledger-1** is recorded (the confidence set).
- Any **guardrail / standards / process** change is proposed as a **human-ratified PR** — agents
  propose, humans ratify (`DEVELOPMENT-PROCESS.md`). Never silently re-plan or weaken a guardrail.

## The verdict log

Each run appends one row to the kit's verdict log (`docs/governance/meta-control-log.md`):

`date · version · trigger · profile · verdict · verdict-artifact · one-line ledger summary`

This is the kit's own run history; **adopters keep their own log** (start fresh).

## Recording the panel's GO (the governance lane)

A panel PR is a **governance-record change**: its artifact is the sitting record itself, so it has no
design document of its own and never will. Record its GO on the **governance gate**, not the design
gate — `conformance/ceremony-binding.sh` accepts `gate: governance` as a first-class value and judges
it by the same chain as a design GO, with the **basis** being the panel artifact:

`--scope` takes either `branch/<the-panel-branch>` or `PR-<n>`; the branch key binds *before* the PR
exists, so it is the one to write. Every line below ends in a continuation — no inline comments, so
the block survives a copy-paste intact:

```sh
sh scripts/promotion-verify.sh record \
  --gate governance \
  --scope branch/<the-panel-branch> \
  --approved-sha <the commit that touches the panel artifact> \
  --approved-by "<the human who gave the GO>" \
  --rung integration --class control-plane \
  --basis docs/architecture/<date>-meta-control-<n>.md \
  --token "<the owner's explicit GO, in their words>"
```

Then publish it — the gate reads the *published* ledger, so an unpublished record leaves the check
yellow:

```sh
git push origin refs/notes/promotions
```

Two rules make this lane honest, and both are enforced, not advisory:

1. **The basis must be the meta-control artifact** (`docs/architecture/*-meta-control-*.md`). Pointing
   a governance GO at a design document is the workaround this lane replaces.
2. **The PR must be a PURE governance-record change.** The gate derives the change-set and refuses
   (rc 2, naming the escaping paths) anything outside: `BACKLOG.md` · the meta-control artifact ·
   `docs/governance/DECISIONS.md` · `docs/governance/.meta-control-last` ·
   `docs/governance/meta-control-log.md` · `docs/operations/meta-control.md` · `skills/*/SKILL.md` ·
   `docs/architecture/*-design.md`. **Routed cures do not ride along** — the panel's own charter routes
   findings to boarded rows, so a cure the sitting decided on becomes its own slice with its own
   design GO. A mixed PR still needs a design basis for its payload; that is the gate being right.

Do NOT record a **design** GO for a panel PR. Historically three PRs did (naming a design doc the
commit happened to amend, disclosed in the token) — a workaround for a gate defect, retired here.
Those records remain in the ledger, adjudicated defective, as the evidence of the gap.

## The freshness gate (M2 — the cadence circuit-breaker)

`conformance/meta-control-fresh.sh` enforces the cadence so the panel can't be *designed but never
run*. It is **DUE** once more than **N=5** release tags have landed since the last addressed run, read
from a one-line machine marker `docs/governance/.meta-control-last` (`VERSION VERDICT`, e.g.
`3.48.0 GO-WITH-CONDITIONS`) that the check keeps in lockstep with the log's last row.
**`D-240819-5` left this gate and its N untouched, deliberately.** Once the panel obligation moved to
boundaries, N=5 stopped being an obligation restated in code and became purely a **backstop clock**: it
is what stops "at boundaries" from decaying into "never" when boundaries are far apart. Its cure is the
light 5-lens panel (above) or a dated `DEFERRED` row. N stays env-overridable, and that override stays a
**human** act: `scripts/release-tag.sh` detects a caller-set `META_CONTROL_*` / `RELEASE_TAG_CADENCE` and
says so unmissably on **every** invocation, disclosing that the enforce-at-birth guarantee does not apply
to that run. It **warns rather than refuses** — env-hardening is unwinnable against a caller who owns the
environment, so the control is that an override can never be *silent* (`D-240807-1` posture D3′).
**During a ruled release-batching period (a `D-240813-6`-class ruling with no per-slice tags), N
counts *merged slices*, not tags** — otherwise batching starves the clock and a long phase runs dark
while the gate reads FRESH (panel #41 finding 2-M2; owner-ruled 2026-08-15, `D-240815-2`).

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

> **M2-S5 hardening (ratification integrity).** The marker + verdict log are **control-plane** —
> agent writes are denied at the default (path-named) route: Edit/Write *and* the path-named shell
> forms (`KIT_GUARD_SELFEDIT=1` or a human commit is required; see the defense-in-depth ceiling
> below), so a verdict is a human-ratified act, not something the governed agent can self-issue.
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
| **meta-control (this)** | **at epic / release / major boundaries + on demand** (`D-240819-5`); the light 5-lens panel is the backstop when M2 reads OVERDUE | **direction / proportion / over-claim** — adversarial, produces a verdict artifact, **gated by M2** |
