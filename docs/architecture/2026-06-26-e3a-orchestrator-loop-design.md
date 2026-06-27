# E3a — The thin 4-seat orchestrator loop (architecture / design)

**Date:** 2026-06-26
**Epic / slice:** E3 → **E3a** (slice 3 of the ratified 5-slice E3 spine; see `docs/ROADMAP-KIT.md` item 5 + `docs/architecture/2026-06-26-meta-control-4.md` §5)
**Status:** Design converged (brainstorm, owner-ratified 2026-06-26). Ready for the implementation plan.
**Tracked here** (not `docs/superpowers/specs/`) because later E3 slices depend on it and it must be resumable cold by a fresh instance — same rationale as `2026-06-22-e3-agentic-orchestration-design.md`.

**Reads-first for a cold resume:** the E3 frame (`2026-06-22-e3-agentic-orchestration-design.md`), the panel-#4 ratified order + conditions A1–A5 (`2026-06-26-meta-control-4.md`), and the E5-thin trace contract this slice emits into (`scripts/otel-trace.sh`, `scripts/otel-to-scorecard.sh`, `scripts/orchestrator-trace-demo.sh`).

---

## 1. What E3a is

E3a ships the **thin 4-seat orchestrator loop** — **Orchestrator + Engineer×N + Reviewer + Security** — as fresh-authored, harness-neutral, conformance-held capability that *we also self-host*. The Orchestrator decomposes a tiny real task into non-overlapping slices, fans out Engineer×2 (each in an isolated worktree, each metered by `runaway-guard.sh`), integrates their compatible diffs, runs Reviewer + Security on the merged result, and emits the OTel trace the **unchanged** scorecard reads.

It discharges the three E3a obligations panel #4 fixed:
1. **Replace the E5-thin stand-in** (`scripts/orchestrator-trace-demo.sh`) with a *real* mechanical loop emitting the same span tree — byte-for-byte compatible with `otel-to-scorecard.sh`.
2. **Wire `runaway-guard.sh step`** as the loop's first live call-site (condition **A2** — the kill-switch has zero callers today).
3. **Resolve the neutral agent-definition format** (design §5 open item).

It is **slice 3**: it enters Build only on its own affirmative per-epic meta-control verdict (condition **A5**), and the light 5-lens panel runs before it ships (the freshness marker is at `3.49.1`, approaching N=5).

## 2. Strategic commitment — self-hosting (owner-ratified 2026-06-26)

The kit ships its **own** harness-neutral superpowers-equivalent (a fresh-authored skill spine + agent roster), and **we use it to build the kit** — progressively dropping the external superpowers dependency.

- **Adopters are never required to install superpowers** — the kit provides the equivalent.
- **Authored fresh**, not forked — forced by harness-neutrality, and cleaner.
- **Incremental, not big-bang.** E3a is brick one (Orchestrator + Engineer roster + the loop). Later E3 slices fresh-author more of the spine; we shift our own usage onto each piece as it lands.
- **The E10 capstone is the acceptance test:** *build a real slice of the kit using only the kit's own roster — zero superpowers.* If that run feels worse than superpowers, the roster isn't done.

This sharpens E3a's bar: the Orchestrator + Engineer defs must be good enough that **the maintainer would choose them over superpowers on the next build**, not merely serve as adopter reference.

## 3. The roster & the neutral agent-definition format (design §5, resolved)

**FLOOR + NATIVE applied to agents:**
- **FLOOR (neutral def):** each role authored once, harness-neutrally — *role · responsibilities · stance · Task-Context-Contract (I/O) · tools-needed · success criteria*. The source of truth.
- **NATIVE (binding):** each harness binds the neutral def to its native agent mechanism. On Claude that is the rich subagent shape already shipped (`.claude/agents/reviewer.md`). The existing "lying-native" guard rejects unproven `native` claims.

**Resolved format (owner-ratified): neutral def files + adapter binding.**

```
agents/                       # FLOOR — neutral, fresh-authored (NEW dir, not flat templates/)
  orchestrator.agent.md
  engineer.agent.md
  reviewer.agent.md           # neutral contract behind the existing native def
  security.agent.md
.claude/agents/               # NATIVE — Claude binding (exists today; references the FLOOR)
  reviewer.md  security-reviewer.md  (+ orchestrator/engineer bindings added)
```

- An agent definition is a **prose contract** (responsibilities, stance, success criteria) → markdown, not JSON config. `adapter.json` stays the **binding/proof** layer, not the content layer. Content (md) and binding (adapter) stay distinct.
- The neutral defs live in a **new top-level `agents/` dir** — not the flat `templates/` (which finding C2 already wants partitioned).
- Conformance reuses the existing adapter machinery: `adapter.json` gains a **new `orchestration` dimension** (distinct from today's `review-roles`, which stays scoped to Reviewer/Security — Orchestrator/Engineer are conduct/build roles, not review roles, so overloading `review-roles` would muddy it), `conformance/harness-adapter.sh` requires it in the boundary contract, and `conformance/named-adapters.sh` composes it across codex/cursor/gemini. The lying-native guard makes a `native` claim back its proof (the bound files exist + the role is invocable).

## 4. The convening / lifecycle model

**One standing conductor, ephemeral specialists.** The Orchestrator is *standing* — it is the session (the adopter's primary agent, or the maintainer's). Every other seat is an **ephemeral subagent**: dispatched fresh with a Task-Context-Contract, runs to completion, returns one artifact, context discarded. "Spin down" = *returned its artifact, context gone.*

Two consequences are load-bearing:
1. **An agent's span = its lifetime.** Spin-up is the span start; the returned artifact is the span end. This *is* the carry-forward "bracket real start/end" — convening boundaries are the timestamps, not bolted-on timing.
2. **Statelessness is why agent-memory (ex-E12) is deferred to LAST.** Ephemeral subagents are *sufficient* for E3a: each engineer gets everything in its TCC and returns a diff. Persistent named-agent memory is depth, not foundation.

### E3a's 4 seats — skills + spin points

| Seat | Representative skills (fresh-authored spine; embedded in defs for E3a) | Spun **UP** at | Spun **DOWN** at | Lifetime |
|---|---|---|---|---|
| **Orchestrator** | epic-slicing (INVEST), fan-out planning, worktree mechanics, integration / conflict-resolution, release-conductor (E2 flags, later) | run start — *standing* | run end | whole run |
| **Engineer ×N** | TDD (red→green), implement, self-verify/debug | fan-out, after slicing — one per slice, parallel, each in its own worktree | returns its diff (before integration) | one slice's build |
| **Reviewer** | code-review (correctness, standards, §14 gates) | after integration — on the merged result | on verdict (APPROVE / NEEDS-FIXES) | one review pass |
| **Security** | threat-model (Shape/Plan) **+** security-review (Ship) | per hat — see §4.1 | on verdict | one review pass |

### The loop as a timeline of spin points

```
t0  Orchestrator convenes ─────────────────────────────────── standing ──┐
t1   slice epic → A, B                                  [LLM judgment]    │
t2   ┌ spin UP Engineer#1 → worktree A ┐ parallel fan-out  ← spans start  │
     └ spin UP Engineer#2 → worktree B ┘                                  │
       │ each: runaway-guard.sh step --agents 1   (A2 — per-agent meter)  │
t3   Engineer#1 returns diff → spin DOWN  ← span end                      │
     Engineer#2 returns diff → spin DOWN                                  │
t4   Orchestrator integrates A+B → branch   [mechanics]                   │
       └ on guard breach → emit kit.denied span  [TRUSTED layer sets it]  │
t5   ┌ spin UP Reviewer ┐ parallel review panel  ← spans start           │
     └ spin UP Security ┘                                                 │
t6   verdicts → spin DOWN  ← spans end                                    │
t7   gates pass → Orchestrator emits root span → scorecard → done ────────┘
       (NEEDS-FIXES → loop back to t2: re-spin a fresh Engineer)
```

- **`builder ≠ reviewer` is enforced by the spin model** — Reviewer/Security are spun *fresh* at t5, never a reused engineer. The lifecycle is the control.
- **The guard fires per spin** (t2) — the per-agent metering that makes A2's wiring meaningful.
- **The fix-loop is a re-spin** (t7→t2): a new ephemeral engineer with the reviewer's findings in its TCC. No state carried, no memory needed.

### 4.1 The threat-model timing flag (deliberate def shape)

Security has **two hats with different summon points**, and the thin loop only exercises one:
- **threat-model** → a *Shape/Plan* activity, summoned *early* when the work is risky (it shapes what gets built);
- **security-review** → a *Ship* activity, summoned *after* the code, on the diff.

E3a's thin loop convenes Security only at integration (review) — honest, because the micro-build task is trivial and non-sensitive. But the **Security def is authored with both hats and distinct summon triggers** (threat-model @ Shape-when-risky, security-review @ Ship-always), so the kit's "threat-model early" discipline isn't silently lost the moment an adopter uses the roster on something sensitive. E3a exercises only the review hat; the spec records that explicitly.

### 4.2 Coverage — the kit's core expertise has a home (no dead-ends)

E3a covers a deliberate subset; every other core expertise maps to a named later seat/slice (nothing orphaned): Discovery/stories → **Product** (later); architecture/planning/ADRs → **Architect** (later); perf lens · a11y → **Reviewer** lens / **Design** if UI (conditional); AI-native evals/prompt-injection/output-validation → Engineer+Security hats in **E6**; observability trace→scorecard→tier-advice → **Kit-Steward**/**Ops** (sensor shipped E5-thin, seat later); release/flags/progressive-delivery → Orchestrator **release-conductor** + Ops (E2 flags exist); conformance/drift/meta-control → **Kit-Steward** (read-only today); deploy/smoke/on-call/SLA → **Ops/SRE** if live (E5-full).

## 5. The loop: who drives, what's mechanical

**The LLM orchestrator drives; shell provides the mechanics.** A shell script cannot summon a subagent mid-session (dispatch is the harness's job), so the loop is *not* "shell calls a role-runner." Instead:

- **`agents/orchestrator.agent.md`** encodes the loop as instructions the orchestrator-agent follows (the way the maintainer follows `dispatching-parallel-agents` today). The LLM makes the judgment calls — slice the epic, set fan-out width, resolve conflicts — and dispatches **real** engineer subagents.
- **Harness-neutral mechanics scripts** are the composable substrate the orchestrator calls: worktree-per-agent setup, the `runaway-guard.sh step` meter+trace call, and the integration/merge step. These run anywhere.

Concrete loop:

```
Orchestrator-agent (LLM, follows orchestrator.agent.md)
  ├ slice epic → 2 non-overlapping slices                 [LLM judgment]
  ├ for each slice:
  │    <worktree mechanic> add <slice>                     [real git worktree]
  │    dispatch engineer subagent into worktree            [harness: real LLM work]
  │    <loop mechanic> step --tokens N --agents 1
  │         → runaway-guard.sh step  (A2, halts on breach)
  │         → emit child span, REAL bracketed start/end, agent.id=engineer
  ├ integrate worktrees → branch                           [mechanic]
  │    on guard denial → emit kit.denied span              [TRUSTED layer; never agent-supplied]
  ├ dispatch Reviewer + Security subagents                 [existing defs]
  └ emit root span → trace → unchanged scorecard → real denial_rate
```

## 6. The trace contract (carry-forward, must hold byte-compatible)

The emitted NDJSON must keep working through the **unchanged** `otel-to-scorecard.sh` → `agent-scorecard.sh`:
- One **root** span (parent null) `orchestrator-run`, `agent.id=orchestrator`; **N child** spans (parent = root), one per agent run → one scorecard record each.
- A guard-denied gate span carries **`kit.denied=true`** → scorecard outcome `denied` (the non-vacuous `denial_rate` signal). **`kit.denied` is set only by the trusted orchestrator/guard layer — never copied from agent-supplied attributes** (it is an autonomy-tier input → spoofable otherwise).
- **Bracket real start/end** (the stand-in emits zero-duration spans). `start_unix_nano`/`end_unix_nano` stay **numeric 19-digit** so the scorecard's lexical `sort_by(.start)` equals numeric sort.
- When trace files are named by `run.id`, **slug the path** (`tr -c 'A-Za-z0-9._-' '_'`, mirroring `agent-trace.sh`).

## 7. The deterministic proof + the §10 containment status table

"Replace the stand-in" = the golden-path runs the **real mechanical loop** — real `git worktree`, real guard calls, real integration, real bracketed spans — driven by a **fixture engineer** (a tiny deterministic script that makes a checkable file edit), so the *plumbing* is gated in CI with **no LLM**. The same `orchestrator.agent.md` loop runs live with real engineer subagents.

The fixture engineer is a **null-LLM actor on real rails.** The golden-path proves: two worktrees genuinely isolate, the guard genuinely meters and can **halt** (a breach fixture → STOP), integration genuinely merges two diffs, and the trace genuinely flows through the unchanged `otel-to-scorecard.sh` to a real `denial_rate`. It does **not** prove an LLM writes good code — not a gate-able property (same honesty line as E4a: prove the sandbox holds, not that the app is bug-free). Non-vacuity discipline: a positive liveness anchor (a clean run produces the expected child records) **plus** the denial negative (the breach fixture must STOP and surface the `kit.denied` span) — a dead loop cannot pass.

### §10 containment-contract status table (condition A1)

| §10 item | E3a status | Owner |
|---|---|---|
| 1. Per-agent FS scope (worktree) | **used, not enforced** — real worktrees, isolation-as-convention | E3b mechanic / E4 enforces |
| 5. Cost ceiling + kill-switch | **proven** — `runaway-guard.sh` wired at the loop (A2) | E3a |
| 6. Conflict-safe parallel writes | **avoided** — clean non-overlapping slices only | E3b |
| 7. Guard at fleet scale | **out of scope** — 2 agents, not a fleet | E4 |
| 2. Egress control | **inherited** — E4a (ts-node, behavioural) | done |
| 3. Scoped tokens | **inherited** — E4a′ (static-structural) | done |
| 4. Prod-cred SoD | **inherited** — E4e (FLOOR logic) | done |

## 8. Conformance, claim, binding proof

- **New behaviour claim** (claims.tsv) — `orchestrator-loop`: "the 4-seat orchestration loop runs end-to-end (fan-out → contain → integrate → trace) — proven by golden-path on a fixture engineer." Honest qualifier: *reference loop; LLM agent work exercised live, substituted in CI.*
- **`conformance/orchestrator-loop-wired.sh`** (the lock) — static-locks: the neutral defs exist and are bound in `adapter.json`; the mechanics scripts exist; the golden-path job asserts the loop. Wired into `verify.sh` / CI / `drift-watch` / `doctor` (mirrors `agentops-sensor` / `containment-audit`).
- **Golden-path job `orchestrator-loop`** in `golden-path.yml` — runs the real loop with the fixture engineer; asserts: 2 worktrees created, guard `step` called, a breach fixture **halts**, integration merged both diffs, root+children trace emitted, `kit.denied` span present on denial, scorecard derives a real `denial_rate`.
- **Roster binding** — add the `orchestration` dimension (§3) to `adapter.json` across all adapters (claude-code = `native`, proving via `agents/*.agent.md` + `.claude/agents/` bindings; codex/cursor/gemini/generic = `floor`); the boundary contract requires it; `named-adapters.sh` composes it.
- **Export-carve discipline** (recurring lesson): any new lock whose verifier reads an export-ignored path (`golden-path.yml`) **must** be carved from the adopter export in both `adopter-export.sh` carve loops — verified at the committed HEAD by `adopter-export-wired`.

## 9. Honest ceiling & out of scope (named, not built)

- **Enforced** worktree isolation, conflict-safe parallel writes, guard-at-fleet-scale → **E3b / E4** (see §7 table). E3a uses worktrees + clean slices so the thin loop is real without those guarantees.
- The **standalone skill library** (brainstorming, writing-plans, etc. as separately-invokable harness-neutral skills) → later E3 slices toward the E10 self-host test. E3a embeds skills in the defs.
- **Product / Architect / Design / Ops / Kit-Steward** seats, AI-native evals, a11y → later seats/slices (§4.2).
- Security **threat-model hat** authored but **exercised** only at review in E3a (§4.1).

## 10. Build approach

- **Control-plane** (guard `is_control_plane_path` for the new defs/mechanics/conformance, `adapter.json`, claims.tsv) → built **AMBER**: agent prepares `scratchpad/e3a/apply.py`, dry-runs it on a clone (including `conformance/shellcheck.sh`), dual review (reviewer + security-reviewer), human applies. **Version finishing folded into apply.py** (durable fix — VERSION + README badge + CHANGELOG + ROADMAP) so the bump can't be skipped.
- **Meta-control:** run the **light 5-lens panel before E3a ships** (freshness marker `3.49.1`, approaching N=5; condition A5 — E3a enters Build on an affirmative verdict).
- **Release:** the guarded merge+tag block (merge first → VERSION-guarded tag); the human does merge+tag (`--admin` needed; `control-plane-ratification` is red by design solo).

## 11. Convergence record (owner-ratified 2026-06-26)

The thin 4-seat real micro-build as E3a's vertical · self-host + fresh-author + the E10 self-host acceptance test · neutral def files + adapter binding for the FLOOR (new `agents/` dir) · LLM-drives + shell-mechanics loop ownership · fixture-engineer deterministic proof + the §10 status table · the convening/lifecycle model (standing Orchestrator + ephemeral specialists, span = lifetime, builder≠reviewer via the spin model) · Security authored with both hats, review-hat-only in E3a · skills embedded in defs for E3a (extracted later). **Next: the implementation plan (writing-plans).**
