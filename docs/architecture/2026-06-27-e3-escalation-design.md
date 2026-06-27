# E3-escalation — human-in-the-loop / escalation seam (architecture / design)

**Date:** 2026-06-27
**Epic / slice:** E3 → **E3-escalation** (ex-E14; slice 4 of the ratified 5-slice E3 spine, positioned **early** — ahead of E3b mechanics; see `docs/ROADMAP-KIT.md` item 5 + `docs/architecture/2026-06-26-meta-control-4.md` §5, condition A4).
**Status:** Design converged (brainstorm, owner-ratified 2026-06-27). Ready for the implementation plan.
**Tracked here** (not `docs/superpowers/specs/`) because later E3 slices and `T2-team-live` depend on it and it must be resumable cold by a fresh instance — same rationale as `2026-06-26-e3a-orchestrator-loop-design.md`.

**Reads-first for a cold resume:** the E3a loop this plugs into (`2026-06-26-e3a-orchestrator-loop-design.md` + `scripts/orchestrator-run.sh` + `docs/operations/orchestration.md`), the runaway kill-switch it triggers off (`scripts/runaway-guard.sh` + `docs/operations/runaway-killswitch.md`), the ratifier-role source of truth (`docs/enterprise/ratification-rbac.md`), and the panel-#4 condition A4 that positioned this slice (`2026-06-26-meta-control-4.md`).

---

## 1. What E3-escalation is

E3-escalation ships the **human-in-the-loop seam** for the orchestration loop: the structured *stop → surface in plain language → human ratifies → resume* mechanism that turns the E3a loop's only-pause-at-ship autonomy into a governed collaboration. It is the owner's **collaboration headline** — *when and how a human is pulled into the loop, and how a non-engineer ratifies without reading shell* — and it **gates `T2-team-live`** (which needs a real human-ratifiable approval seam).

The thin vertical: when `runaway-guard.sh step` breaches a ceiling mid-run, the loop — instead of dead-halting (today's behaviour) — **raises a plain-language, role-addressed escalation record and pauses**, then resumes **only on a human-ratified verdict**, fail-closed on none. The escalation primitive is **authored general** (carrying the fields a future approval checkpoint needs) but **wired to exactly one trigger** (the guard breach), so it is a thin proven slice, not an escalation subsystem.

### Why this trigger, this shape (the brainstorm decision)

Three triggers were weighed (brainstorm, 2026-06-27):

- **A — guard-breach → escalate** (chosen): taps the one event the loop **already emits** (`kit.denied`) and **already proves deterministically** (E3a's breach fixture forces a STOP with no LLM). Upgrades "halt" into "halt-and-ask." Thinnest real vertical; honest, non-vacuous proof; break-glass (raise-ceiling) is a governed human action by construction.
- **B — tier-checkpoint → approve** (deferred, see §6): classify every pending action by autonomy tier, surface an approval request *before* acting. Hits the headline most directly but adds hot-path machinery whose core — *classify correctly* — is an **LLM judgment, not a gate-able property**, so the headline would outrun the proof.
- **C — one seam, both triggers** (rejected): the architecturally-complete end state, but bundling two triggers + the primitive into one slice violates the kit's own thin-proven-slice rule (condition A5) and builds B's machinery speculatively (the F5 anti-build-ahead error this consolidation arc exists to stop).

**Ratified direction: A, with the record schema and resume protocol authored B-ready**, so Option B becomes a *second caller, not a rebuild* (§6).

## 2. The three FLOOR pieces

The seam is three harness-neutral primitives. They differ from a Claude-specific prompt in being **durable and file-based** — the established human-in-the-loop pattern (AWS Step Functions task-token callback · Temporal human-task signal · LangGraph `interrupt`/checkpoint): *durably pause → emit a structured request → resume on an external signal.* A human may answer in 10 seconds or 10 hours; the loop does not hold a live process hostage.

### 2.1 The escalation record (the artifact)

One JSON file at **`.kit-run/escalations/<run-id>.<seq>.json`** (under the existing gitignored `.kit-run/` runtime dir, alongside the tally). The path is **slugged** (`tr -c 'A-Za-z0-9._-' '_'`, mirroring `agent-trace.sh`) since `run-id` flows in.

**B-ready schema** (A populates the left; the right shows why each field is general, not breach-specific):

| field | A (`runaway-breach`) | B-ready rationale |
|---|---|---|
| `id` | `<run-id>.<seq>` | trace correlation |
| `created_unix_nano` | numeric **19-digit** | scorecard `sort_by(.start)` stays lexical==numeric |
| `trigger` | `"runaway-breach"` | B adds `"tier-exceeded"` — same seam, new value |
| `summary` | plain-language one-liner | the **non-engineer-readable headline** |
| `detail` | **empty stub** in A | B/richer callers populate a plain-language paragraph (no shell/stack) |
| `risk` | **empty stub** in A | the **autonomy-tier input B classifies on** (e.g. `medium`) |
| `reversibility` | **empty stub** in A | the autonomy-tier input B classifies on (e.g. `reversible`) |
| `recommendation` | **empty stub** in A | the agent's recommended verdict |
| `options` | `["raise-ceiling","abort","amend"]` | B: `["approve","reject","ask"]` |
| `ratifier_role` | `"security-owner"` (budget exception → RBAC) | B: per-action role from `ratification-rbac.md` |
| `context_ref` | **empty stub** in A | the **escape hatch** (trace/run path) for an engineer who *does* want shell |

> **A populates only `id`/`created_unix_nano`/`trigger`/`ratifier_role`/`summary`/`options`** — the thin runaway-breach path needs no more. The five fields marked "empty stub" are written empty by `raise()` and exist as the **B-ready seam** (a tier-checkpoint or richer caller fills them); they are not broken population. The gated affordance (§4) is therefore "a non-empty `summary` exists, distinct from the technical `detail`/`context_ref`" — not that every field is populated.

`summary`/`detail`/`recommendation`/`options`/`ratifier_role` are the **plain-language affordance**: a named ratifier reads the decision without going to the source. `context_ref` keeps the technical trail one hop away for whoever wants it.

### 2.2 The pause + resume protocol

1. **Raise.** Loop writes the record, sets state `pending`, and **stops** — returning control to the human (or, in CI, to the fixture driver). No live process is blocked.
2. **Verdict.** The human/CI writes **`.kit-run/escalations/<id>.verdict`** — `{ "option": <one of record.options>, "note": <free text>, "ratifier_id": <identity> }`.
3. **Resume.** The loop reads the verdict and **validates**: `option ∈ record.options`, `ratifier_id` present (B-ready: ratifier authorised for `ratifier_role`). On success it **consumes** the verdict (single-use; renames to `.verdict.consumed`), records the verdict on the trace (§2.3), and continues per option: `raise-ceiling` → **clear the run's usage tally** so work continues (the ceiling itself is unchanged — the guard re-escalates if the budget refills); `abort` → clean teardown; `amend` → return to re-slice. **Resuming a paused run = re-invoke with the same `OTEL_TRACE_ID`** (the escalation id derives from it; the loop is stateless/durable-file-based, so a fresh id would never match the verdict and would just pause again).
4. **Fail-closed.** No verdict · unparseable verdict · `option ∉ options` · missing ratifier → the loop **stays halted and makes no progress.** Safe default is never-proceed (the breach already halted; a missing human answer must not be read as consent).

### 2.3 Trace integration (the audit trail)

The resolved span carries **`kit.escalated=true`**, **`kit.verdict=<option>`**, **`kit.ratifier=<id>`** — so the OTel trace (and anything downstream of it) shows a human touched the run, who, and how.

> **Anti-spoof discipline (reused from E3a `kit.denied`):** `kit.escalated` / `kit.verdict` / `kit.ratifier` are set **only by the trusted orchestrator/escalation layer — never copied from agent-supplied span attributes.** They are autonomy/audit inputs; an agent that could author them could fabricate its own ratification. The golden-path proves an agent-supplied `kit.verdict` is rejected (§4).
>
> **Two further anti-spoof guarantees (added at security review):** (a) the engineer **role-runner's env is scrubbed** at dispatch — `env -u OTEL_TRACE_FILE -u OTEL_TRACE_ID -u KIT_ESCALATION_DIR -u KIT_RUN_DIR` — so an engineer cannot learn the deterministic escalation id *or* the verdict-channel directory, and therefore cannot pre-write its own verdict to self-ratify a breach (regression-locked by a role-runner env-leak selftest). (b) A verdict is **single-use** — `resolve` consumes it (renames to `.verdict.consumed`) so a one-time human approval cannot be **replayed** on a later re-run of the same (deterministic) escalation id. `kit.ratifier` is CR/LF-stripped before it is stamped onto the NDJSON trace.

## 3. Mechanics & where it plugs in

**The LLM orchestrator drives; shell provides the mechanics** — same ownership split as E3a (a shell script cannot summon a human or a subagent; it provides the composable substrate).

- **New FLOOR script `scripts/escalate.sh`** — verbs `raise` / `await` / `resolve`:
  - `raise <run-id> <trigger> <fields…>` → writes the slugged `pending` record, returns a non-zero "paused" status the loop understands.
  - `await <id>` → checks for the verdict file; absent → "still pending" (the loop stops here).
  - `resolve <id>` → validates the verdict, prints the chosen `option` for the loop to act on, exits non-zero (fail-closed) on any invalid/missing verdict.
- **`scripts/orchestrator-run.sh`** — the **one wiring change** to the proven loop: where it today bare-halts on `runaway-guard.sh step` → STOP (exit 1), it now calls `escalate.sh raise …` and pauses. This is the live call-site that makes the seam real (parallels how E3a made `runaway-guard.sh step` real with its first caller).
- **`agents/orchestrator.agent.md`** (FLOOR) + **`.claude/agents/orchestrator.md`** (NATIVE) gain an **escalation-discipline** section: when to raise, that verdicts are human-ratified and never self-issued, and — *deliberately, mirroring E3a's two-hat Security def* — that the record schema is authored **B-ready** so the proactive "ratify before a risky action" path is not silently lost the moment an adopter needs it.
- **NATIVE surfacing:** Claude's orchestrator stops and presents `summary` + `options` (optionally via the native ask affordance); a generic harness reads the record file and writes the verdict file. **Same FLOOR, harness-local presentation** — the kit's FLOOR + NATIVE rule.

### Loop with the seam (extends E3a §5)

```
Orchestrator-agent (LLM, follows orchestrator.agent.md)
  ├ slice epic → disjoint slices                          [LLM judgment]
  ├ for each slice: worktree + dispatch engineer
  │    runaway-guard.sh step --agents 1
  │      └ STOP (breach) ──► escalate.sh raise <run> runaway-breach …   [TRUSTED layer]
  │            └ write pending record (plain language) · PAUSE ─────────┐
  │                                                                     │  <human / CI writes verdict>
  │      escalate.sh resolve <id> ◄─────────────────────────────────────┘
  │            ├ raise-ceiling → bump ceiling · continue   (governed break-glass)
  │            ├ abort         → clean teardown
  │            ├ amend         → re-slice
  │            └ invalid/none → STAY HALTED          [fail-closed]
  │      emit span: kit.escalated · kit.verdict · kit.ratifier   [TRUSTED; never agent-supplied]
  ├ integrate → Reviewer + Security → root span → scorecard
```

## 4. Conformance — the honest proof

- **New behaviour claim (`claims.tsv`) — `escalation-seam`:** *"a guard breach in the orchestration loop raises a plain-language, role-addressed escalation record and pauses; the loop resumes only on a human-ratified verdict; fail-closed on no/invalid verdict — proven by golden-path on a breach fixture."* Honest qualifier: *reference seam; the record's plain-language **affordance** is gated, subjective readability is not; live human ratification is exercised live, fixture-driven in CI.*
- **`conformance/escalation-wired.sh`** (the lock) static-locks: `escalate.sh` exists with all three verbs; the record schema declares the required fields; `orchestrator-run.sh` wires escalate-on-breach; the golden-path job asserts the seam; the orchestrator agent def documents the escalation triggers. Wired into `verify.sh` / CI / `drift-watch` / `doctor` (mirrors `orchestrator-loop-wired` / `agentops-sensor`).
- **Golden-path `escalation`** — **extends the existing deterministic `orchestrator-loop` fixture job** (no LLM). On a breach fixture it asserts:
  - **positive (liveness anchor):** a `pending` record is written with **every required field populated** and a **non-empty `summary`**;
  - **fail-closed negative (load-bearing):** with **no verdict**, the loop makes **no progress** — a dead loop cannot produce this;
  - **`abort` verdict** → clean teardown; **`raise-ceiling` verdict** (fixture ratifier) → loop continues **and** the trace carries `kit.escalated`/`kit.verdict`/`kit.ratifier`;
  - **anti-spoof:** a forged/disallowed verdict, **or an agent-supplied `kit.verdict` attribute**, is rejected.

**Non-vacuity:** the positive (valid verdict → progress) **and** the fail-closed negative (no verdict → no progress) together mean *neither a dead loop nor an always-proceed loop can pass.* Same anti-vacuous structure E3a used for `kit.denied`.

- **Export-carve discipline** (recurring lesson): `escalation-wired.sh` reads the export-ignored `golden-path.yml`, so it **must** be carved from the adopter export in both `adopter-export.sh` carve loops — verified at the committed HEAD by `adopter-export-wired`.

## 5. Honest ceiling & out of scope (named, not built)

- **Subjective readability is not gated.** We prove a populated plain-language `summary` exists *separate from* technical detail (the affordance), **not** that the prose is good. Same line as E3a (prove the mechanics, not LLM output quality).
- **No async SLA / paging / timeout-escalation.** The pause is durable but there is no notification or time-boxed re-escalation; that is E5-full / an Ops seat.
- **Server-side enforcement is the adopter's.** The FLOOR proves the loop *honors* a verdict and records the ratifier; enforcing *who may ratify* (branch-protection, forge RBAC, signed identity) is the adopter's forge config — same ceiling as E4e SoD. The check proves the logic, not the org's identity controls.
- **Single trigger.** Only the runaway-breach trigger is wired; the proactive tier checkpoint is §6 (deferred).
- **Collusion / forged identity** out of scope for the FLOOR (an unauthenticated `ratifier_id` is whatever the harness supplies); linked/signed identity is the adopter's, mirroring E4e.

## 6. Out of scope / future — Option B (tier-checkpoint approval) — the deferred candidate

**B = make the autonomy-tier dial a live preemptive gate.** The Orchestrator classifies each pending action by risk × reversibility; anything above its earned tier is surfaced as an **approval request before the action runs**, ratifiable by a non-engineer. The *advisory* half already ships as **`tier-advice` (v3.20.0)** — read-only, emits-never-actuates; B is its preemptive-enforcement complement.

- **Where:** a follow-on slice **after E3b/E3d**, or folded into **E6** (AI-native autonomy depth) — B's core rides the action-planning surface E3b (mechanics) and E3d (phase→agent flow) firm up. Building it before that surface is stable is building on sand.
- **When:** gated on a **real second caller or real demand** — a concrete need for proactive approval from `T2-team-live` or a real adopter, or E3b/E3d landing. Building B next would speculatively repeat the F5 build-ahead-of-need error.
- **If (genuinely conditional):** B carries a permanent honesty tax — *classification correctness is an LLM judgment, not a gate-able property*, so a lock can only prove "a flagged action pauses," never "classified correctly." `tier-advice` + this slice's seam may together suffice. So B is a **design-intent-flagged candidate decided at a future per-epic M brainstorm** — not a committed slice.
- **B-ready guarantee:** this slice's record schema (§2.1) carries `risk` / `reversibility` / `recommendation` / `options` / `ratifier_role`, and the resume protocol validates an arbitrary `options` set, so B adds a **second `trigger` value and a classify-and-raise call-site** — not a rebuild.

**At ship, route a one-line ROADMAP candidate** under the E3 decomposition: *"(candidate, not committed) tier-checkpoint preemptive approval — completes the autonomy-metering thread (`tier-advice` is the advisory half); gate at a future per-epic M brainstorm after E3b/E3d, on real demand."*

## 7. Build approach

- **Control-plane** (new FLOOR `scripts/escalate.sh`, `conformance/escalation-wired.sh`, `claims.tsv`, `orchestrator-run.sh` + agent-def edits, `adapter.json`/export-carve touches, guard `is_control_plane_path` for the new script) → built **AMBER**: agent prepares `scratchpad/e3-escalation/apply.py`, dry-runs it on a clone (**including `conformance/shellcheck.sh`**), dual review (reviewer + security-reviewer), human applies. **Version finishing folded into `apply.py`** (VERSION + README badge + CHANGELOG + ROADMAP) so the bump can't be skipped.
- **Meta-control:** run the **light 5-lens panel before ship** (condition A5 — this slice enters Build/ship on an affirmative per-epic verdict; freshness marker `3.52.0`, the N=5 clock is not due but the per-slice verdict is required).
- **Release:** `commit → push → PR → merge → sh scripts/release-tag.sh` (the human runs the guarded helper after merge; the agent stops at hand-off per the merge/tag-authority rule).

## 8. Convergence record (owner-ratified 2026-06-27)

Trigger A (guard-breach → escalate) as the thin vertical, schema + protocol authored **B-ready** · Option B (tier-checkpoint) deferred with an explicit where/when/if home and a ROADMAP candidate at ship · durable file-based pause/resume (Step-Functions/Temporal/LangGraph pattern, harness-neutral) · the `kit.escalated`/`kit.verdict`/`kit.ratifier` trusted-layer anti-spoof discipline reused from `kit.denied` · `escalate.sh` FLOOR + the single `orchestrator-run.sh` breach call-site + B-ready agent-def discipline · golden-path proof extending the deterministic `orchestrator-loop` fixture with a fail-closed negative + an anti-spoof rejection · `security-owner` as the breach ratifier role (budget-ceiling raise = governed posture exception per RBAC). **Next: the implementation plan (writing-plans).**
