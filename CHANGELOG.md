# Changelog

All notable changes to Sparkwright are recorded here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> Claim verbs ("proven"/"PROVEN") are scoped to the reference implementation unless an entry states broader coverage — see [MAINTAINING.md §3](MAINTAINING.md#3-releasing-platform-team).

## [3.65.0] — 2026-06-28

### Changed
- **Keystone structural self-check (hardening)** — `check_keystone` in `conformance/orchestrator-loop-wired.sh` now **enumerates every on-disk `skills/*/SKILL.md`** (excluding the `using-skills` keystone itself) and asserts the discovery keystone indexes each, instead of grepping a hardcoded path list. The keystone index can no longer drift green relative to disk: a skill present on disk but absent from the keystone is RED on a fresh clone — closing the brick-#8 H1 failure mode (the spine grew a 7th content skill but the keystone index was not updated, caught only by the meta-control panel). POSIX-sh enumeration (`for d in "$skills_dir"/*/`, `basename`, `[ -f ... ]`; dash-safe). New selftest **case 20** is the load-bearing non-vacuity proof: a fully conformant fixture plus an EXTRA on-disk skill with a novel name (`skills/zzz-probe`) that the keystone does NOT index → exit 1. A hardcoded-list check would miss `zzz-probe`; the structural enumeration catches it (verified by a hardcoded-list regression: case 20 fails under the old list). Cases 1–19 unchanged. One wording line in `skills/using-skills/SKILL.md` makes the structural enforcement literal (“…enforces it against every `skills/*` on disk…”); the `skill-spine` claim wording is tightened (same id + verifier command). Right-weighted: no new skill, seat, claim row, or gate — verifier-only hardening. The tag-time CI gate (refuse to tag a red-CI commit — the incident’s other failure mode) is explicitly a separate slice. Design: `docs/architecture/2026-06-28-keystone-structural-check-design.md`. Plan: `docs/architecture/2026-06-28-keystone-structural-check-plan.md`.

## [3.64.1] — 2026-06-28

### Fixed
- **Hotfix (brick #8 release coherence):** the v3.64.0 merge landed the verifier change that makes `check_keystone` require `skills/debugging` in the discovery keystone index, but the matching keystone edit (the `debugging` index row + the "six -> seven" / "`check_keystone` enforces it" wording) did not land in the commit — leaving `orchestrator-loop`, `conflict-safe-integration`, and `skill-spine` RED on a fresh clone. This syncs the keystone so the index is exhaustive again and the gate passes.

## [3.64.0] — 2026-06-28

### Added
- **Skill-spine brick #8 — the kit's own `debugging` skill** (`skills/debugging/SKILL.md`). The kit now ships its own harness-neutral root-cause-first debugging skill — the `systematic-debugging`-equivalent: the Iron Law (no fix without `root cause` investigation first; a symptom patch is failure; read the actual error/stack trace completely), `reproduce` the bug reliably (if not reproducible, gather data, don't guess), controlled experiments (`one hypothesis` at a time; change one thing), and bounded-then-escalate (don't thrash; raise after repeated failed hypotheses). **The distinctive kit framing**: a bug always becomes a **`regression test`** that goes red before the fix and green after — the kit's non-vacuity law applied to bug-fixing — explicitly chaining `debugging → skills/tdd/SKILL.md` (write the failing test) → `skills/verification/SKILL.md` (evidence before claiming fixed). Wired **single-seat** to the **Engineer** (the builder debugs): `agents/engineer.agent.md` + `.claude/agents/engineer.md` gain a debugging reference alongside the existing tdd + verification chain. The Orchestrator is not separately wired — its "don't trust the subagent's report" integration instinct already lives in `verification`. The skill is **not a clone**: it reframes debugging around the kit's invoke-by-read FLOOR and its own tdd + verification spine, so a generic `systematic-debugging` paraphrase fails the conformance greps (`name: systematic-debugging`, lacking the regression-test + one-hypothesis kit framing). FLOOR-only: invoke-by-read; no adapter dimension (owner-ratified). First brick of **Skill-Spine Phase 2** (debugging → evals → discovery), toward **E10 (build a real slice using only the kit's own roster + skills, zero superpowers)**. Right-weighted: no new gate — claim `skill-spine` extended (description now covers bricks #1–8) + the wiring extends `orchestrator-loop-wired.sh` (a new `check_debugging_skill` asserting the skill + the five kit-distinctive markers + the Engineer reference, with non-vacuous teeth: case 18 [marker teeth — drop `regression test`] + case 19 [reference teeth — Engineer omits the reference]). Design: `docs/architecture/2026-06-28-debugging-skill-design.md`. Plan: `docs/architecture/2026-06-28-debugging-skill-plan.md`.

## [3.63.0] — 2026-06-28

### Added
- **Skill-spine brick #7 — the kit's own `using-skills` discovery KEYSTONE** (`skills/using-skills/SKILL.md`). The kit now ships its own harness-neutral discovery meta-skill — the `using-superpowers`-equivalent: the discovery discipline (check for a relevant skill **before acting**, even a 1% chance; **invoke by reading** `skills/<name>/SKILL.md` and following it; follow rigid skills exactly; **explicit `user instructions` always win** over a skill) **and** the single index of the kit's six spine skills (`skills/design`, `skills/plan`, `skills/tdd`, `skills/review`, `skills/worktrees`, `skills/verification`) with when-to-use. Wired **single-seat** to the **Orchestrator** (the standing session / discovery driver): `agents/orchestrator.agent.md` + `.claude/agents/orchestrator.md` gain a "Discovery (start here)" reference. This **completes the kit's skill spine** — zero runtime dependency on superpowers for both content (bricks #1–6) and discovery (brick #7); the next epic is **E10 (build a real slice using only the kit's own roster + skills, zero superpowers)**. The skill is **not a clone**: it reframes discovery around the kit's **invoke-by-read FLOOR** + an index of the kit's own spine (harness-neutral, no Skill-tool dependency), so a generic `using-superpowers` paraphrase fails the conformance greps (it names none of the kit's six skills, no invoke-by-read). **Honest ceiling named**: content is fully kit-owned, but on a neutral FLOOR the entry-point is a **documented convention** the conductor follows — auto-load is harness-local, not a FLOOR guarantee (a NATIVE binding can auto-surface it). FLOOR-only: invoke-by-read; no adapter dimension (owner-ratified). Right-weighted: no new gate — claim `skill-spine` extended (description now covers bricks #1–7, content + discovery) + the wiring extends `orchestrator-loop-wired.sh` (a new `check_keystone` asserting the keystone + all-six-index + discipline markers + the Orchestrator reference, with non-vacuous teeth: case 16 [index teeth — drop one index path] + case 17 [reference teeth — Orchestrator omits the keystone]). Plan: `docs/architecture/2026-06-28-using-skills-keystone-plan.md`.

## [3.62.0] — 2026-06-28

### Added
- **Skill-spine brick #6 — the kit's own `verification` (verification-before-completion) skill** (`skills/verification/SKILL.md`). The kit now ships its own harness-neutral evidence-before-claims methodology — wired **DUAL-SEAT**: the **Engineer** invokes it as *evidence-before-claims* (run the slice's tests fresh in the turn, read the exit code, count failures before any success word) and the **Orchestrator** invokes it as *confabulation-proofing* (a subagent can report "done" for files it never wrote — verify on the diff / a clone dry-run, never the report) — toward **full replacement of (zero runtime dependency on) superpowers** `verification-before-completion`. The skill is **not a clone**: it reframes verification around the kit's own scar tissue — confabulation-proofing, the clone dry-run (the clone + `verify --require` gate is confabulation-proof), and tagless-clone fidelity (`git clone .` carries tags `actions/checkout` does not fetch; validate tag-reading checks on a tagless clone) — atop the proven Iron-Law spine, so a generic paraphrase fails the conformance greps. FLOOR-only: invoke-by-read (universal); no adapter dimension (owner-ratified). Right-weighted: no new gate — claim `skill-spine` extended (description now covers design + plan + tdd + review + worktrees + verification, bricks #1-6) + the wiring extends `orchestrator-loop-wired.sh` (a new `check_vbc_skill` asserting the skill + both seat references, with non-vacuous teeth: case 13 [verification-skill marker teeth] + case 14 [Engineer-omits-reference teeth] + case 15 [Orchestrator-omits-reference teeth]). Wires **both** the Engineer (`agents/engineer.agent.md` + `.claude/agents/engineer.md`) and the Orchestrator (`agents/orchestrator.agent.md` + `.claude/agents/orchestrator.md`). Plan: `docs/architecture/2026-06-28-verification-skill-plan.md`.

## [3.61.0] — 2026-06-28

### Added
- **Skill-spine brick #5 — the kit's own `worktrees` (isolation) skill** (`skills/worktrees/SKILL.md`). The kit now ships its own harness-neutral isolation methodology — invoked by the **Orchestrator** seat (read + follow the SKILL) to set up an isolated worktree per fanned-out Engineer — toward **full replacement of (zero runtime dependency on) superpowers** `using-git-worktrees`. The skill is **not a clone**: it reframes isolation around the kit's own disciplines — detect-existing-first (never nest; submodule guard), native-tools-first (git worktree only as a fallback; never-fight-the-harness), the kit's **disjoint-set parallel-safety rule** (two slices are parallel-safe only with disjoint file sets, no shared mutable state, and each independently testable), conflict-safe integration (`git diff --name-only --no-renames` vs the run cut-point, refuse fail-closed with a `kit.conflict` span), the Engineer's zero out-of-slice boundary, and an honest ceiling (isolation bounds blast-radius but is NOT a security sandbox; cleanup is best-effort/harness-owned) — the conformance greps for these markers so a generic paraphrase fails. FLOOR-only: invoke-by-read (universal); no adapter dimension (owner-ratified). Right-weighted: no new gate — claim `skill-spine` extended (description now covers design + plan + tdd + review + worktrees, bricks #1-5) + the wiring extends `orchestrator-loop-wired.sh` (a new `check_worktrees_skill` with non-vacuous teeth: case 11 [worktrees-skill marker teeth] + case 12 [Orchestrator-omits-reference teeth]). Wires the **Orchestrator** seat (`agents/orchestrator.agent.md` + `.claude/agents/orchestrator.md`). Plan: `docs/architecture/2026-06-28-worktrees-skill-plan.md`.

## [3.60.0] — 2026-06-28

### Added
- **Skill-spine brick #4 — the kit's own `review` skill** (`skills/review/SKILL.md`). The kit now ships its own harness-neutral code-review methodology — invoked by the **Reviewer** seat (read + follow the SKILL) and applied through a security lens by the security-reviewer — toward **full replacement of (zero runtime dependency on) superpowers** `requesting-code-review`. The skill is **not a clone**: it encodes the kit's own reviewing craft — adversarial verification of each finding (the kit's non-vacuity law at the review level), confidence-based filtering (signal over nitpicks), builder ≠ reviewer independence, behaviour-scoped diff review, and honest verdict (NEEDS-FIXES on any real Critical/Important; APPROVE means you stake the merge) — the conformance greps for these markers so a generic paraphrase fails. FLOOR-only: invoke-by-read (universal); no adapter dimension (owner-ratified). Right-weighted: no new gate — claim `skill-spine` extended (description now covers design + plan + tdd + review, bricks #1-4) + the wiring extends `orchestrator-loop-wired.sh` (a new `check_review_skill` with non-vacuous teeth: case 9 [review-skill marker teeth] + case 10 [Reviewer-omits-reference teeth]). Wires the **Reviewer** seat (gated: `agents/reviewer.agent.md` + `.claude/agents/reviewer.md`) and the **security-reviewer** (ungated consistency). Plan: `docs/superpowers/plans/2026-06-28-review-skill.md`.

## [3.59.0] — 2026-06-28

### Added
- **Skill-spine brick #3 — the kit's own `tdd` skill** (`skills/tdd/SKILL.md`). The kit now ships its own harness-neutral test-driven-development methodology — invoked by the **Engineer** (read + follow the SKILL) — toward **full replacement of (zero runtime dependency on) superpowers** `test-driven-development`. The skill is **not a clone**: it reframes red-green-refactor as the kit's own **non-vacuity law applied to code** (Verify-RED = the same load-bearing negative the kit requires of every conformance lock), bakes in coverage disciplines (80%+ floor; 100% on critical paths), the testing pyramid, and AI-eval gating — the conformance greps for these markers so a generic test-driven-development paraphrase fails. FLOOR-only: invoke-by-read (universal); no adapter dimension (owner-ratified). Right-weighted: no new gate — claim `skill-spine` extended (description now covers design + plan + tdd, bricks #1-3) + the wiring extends `orchestrator-loop-wired.sh` (a new `check_tdd_skill` with non-vacuous teeth: case 7 [tdd-skill marker teeth] + case 8 [Engineer-omits-reference teeth — closes the banked brick-#2 item]). Wires the **Engineer** seat (not the Orchestrator): `agents/engineer.agent.md` + `.claude/agents/engineer.md`. Plan: `docs/superpowers/plans/2026-06-28-tdd-skill.md`.

## [3.58.0] — 2026-06-27

### Added
- **Skill-spine brick #2 — the kit's own `plan` skill** (`skills/plan/SKILL.md`). The kit now ships its own harness-neutral planning methodology — invoked by the Orchestrator as the Architect hat (read + follow the SKILL) after the design skill — toward **full replacement of (zero runtime dependency on) superpowers** `writing-plans`. The skill is **not a clone**: it bakes in the kit's own planning disciplines (INVEST/parallel-safety rule · control-plane→AMBER apply.py · conformance-lock non-vacuity · version-finishing folded into apply.py · dual-review · honest-ceiling per task) — the conformance greps for these markers so a generic writing-plans paraphrase fails. FLOOR-only-first: invoke-by-read (universal); the formal `skills` adapter dimension stays deferred (owner-ratified). Right-weighted: no new gate — claim `skill-spine` extended (description now covers design + plan, bricks #1-2) + the wiring extends `orchestrator-loop-wired.sh` (a new `check_plan_skill` with a non-vacuous teeth case 6). Folds in (a) control-plane-completeness discipline into `skills/design/SKILL.md` (the two-matcher gap fix, recurred 3×) + (c) conformance-load-bearing comment (cosmetic). Plan: `docs/superpowers/plans/2026-06-27-plan-skill.md`.

## [3.57.0] — 2026-06-27

### Added
- **Skill-spine brick #1 — the kit's own `design` skill** (`skills/design/SKILL.md`). The kit now ships its own harness-neutral design/brainstorm methodology — invoked by the Orchestrator as the Architect hat (read + follow the SKILL) — toward **full replacement of (zero runtime dependency on) superpowers** (E10 = build a slice using only the kit's own roster + skills). The skill is **not a clone**: it bakes in the kit's own disciplines (architecture-first, the design-intent lens, "is the provable thing the meaningful thing?" / proven-not-prescribed slice-selection, the agents-vs-skills rule, honest-ceiling, non-vacuity, right-weight) — the conformance greps for these markers so a generic paraphrase fails. FLOOR-only-first: invoke-by-read (universal); the formal `skills` adapter dimension + native bindings are brick #2. Right-weighted: no new gate — claim `skill-spine` + the wiring extends `orchestrator-loop-wired.sh` (a new `check_skill` with a non-vacuous teeth case). `skills/` is guard-immutable. Design: `docs/architecture/2026-06-27-design-skill-design.md`.

## [3.56.0] — 2026-06-27

### Added
- **E3b — conflict-safe parallel writes** (§10 item 6). Before integrating parallel engineer branches, the orchestration loop now detects overlapping changed-file sets (`git diff --name-only` across the built branches vs the run's cut-point) and **refuses to integrate** — fail-closed, with a trusted-layer `kit.conflict` span (`conflict.file`/`conflict.slices`, set by the orchestrator from the computed diffs, never agent-supplied) — *before* any corrupting merge, replacing implicit detect-by-failure with proactive, observable, locked detect-by-inspection. Proven non-vacuously by extending `orchestrator-run.sh --selftest` with a conflicting-fixture overlap case (overlap → refused + `kit.conflict` + no silent integration; disjoint → clean). Conformance right-weighted: no new gate — claim `conflict-safe-integration` + the wiring locked by extending `orchestrator-loop-wired.sh`. Honest ceiling: changed-file granularity (not semantic cross-file conflicts); the no-corruption floor is git's, the mechanic makes it proactive + observable + locked; the graceful re-sync/precedence procedure is deferred. Design: `docs/architecture/2026-06-27-e3b-conflict-safe-design.md`.

## [3.55.0] — 2026-06-27

### Added
- **E3-escalation — human-in-the-loop escalation seam** (E3 spine slice 4, ex-E14, positioned early). On a runaway-guard breach the orchestration loop now raises a plain-language, role-addressed escalation record (`scripts/escalate.sh` — `raise`/`await`/`resolve`) and **pauses**, resuming only on a human-ratified verdict (`raise-ceiling`/`abort`/`amend`), **fail-closed** on none/invalid. The trusted-layer span attributes `kit.escalated`/`kit.verdict`/`kit.ratifier` are stamped only from the verdict file — never agent-supplied (same discipline as `kit.denied`); the role-runner's env is scrubbed (`OTEL_TRACE_ID`/`KIT_ESCALATION_DIR`) so an engineer can't pre-forge a verdict, and a verdict is single-use (consumed on resolve, no replay). Ratifier identity is unverified at the FLOOR — server-side WHO-may-ratify is the adopter's forge controls (honest ceiling). The record schema is **B-ready** (carries `risk`/`reversibility`/`recommendation`/`options`/`ratifier_role`) so the deferred tier-checkpoint preemptive-approval path (Option B) is a second caller, not a rebuild. Behaviour lock `conformance/escalation-wired.sh` + claim `escalation-seam`; proven by the deterministic `orchestrator-loop` golden-path (fail-closed pause + raise-ceiling resume, no LLM). Design: `docs/architecture/2026-06-27-e3-escalation-design.md`.

## [3.54.0] — 2026-06-27

### Changed
- **Release tagging: guarded-manual for the kit, opt-in for adopters** — corrects v3.53.0, which shipped the auto-tag binding LIVE in the kit's workflows, so an adopter's export received an active workflow that auto-creates release tags (an imposed release model). Now: the live binding is removed; the kit tags via the coherence-guarded FLOOR helper (`scripts/release-tag.sh`) run manually after merge — a mistimed run is a safe no-op and the tag always equals VERSION — keeping the human in the release decision. The auto-tag-on-merge binding ships as a copy-and-enable reference (`docs/operations/release-tag.github.yml` + the GitLab reference) for adopters who choose full automation — provided, not imposed. The FLOOR helper + coherence logic are unchanged.

## [3.53.0] — 2026-06-27

### Added
- **Auto-tag-on-merge** — removes the human from release tagging (the recurring premature-tag fumble). Forge-neutral FLOOR `scripts/release-tag.sh` (read VERSION -> assert coherence inline via `version-tag-coherent.sh --require` -> tag `v<VERSION>` on the merge commit if absent -> push; idempotent, coherent by construction). NATIVE bindings: a live GitHub workflow (`.github/workflows/release-tag.yml`, `on: push main`, `contents: write`), a GitLab reference (`docs/operations/release-tag.gitlab-ci.yml`), and a generic-forge doc. Behaviour lock `release-tag-on-merge`. The existing `release-coherence.yml` stays as the tag-push backstop.

### Honest ceiling
- The FLOOR proves the *decision* (`--selftest`); the `git push` is exercised live, and forge auth is the binding's concern. It does not choose the version value (that's apply.py version-finishing). Manual `git tag` still works — the workflow no-ops if the tag exists.

## [3.52.0] — 2026-06-26

### Added
- **E3a — the thin 4-seat orchestrator loop** (Orchestrator + Engineer×N + Reviewer + Security): fresh-authored harness-neutral roster (`agents/*.agent.md` FLOOR + `.claude/agents/` NATIVE bindings) + the real mechanical loop `scripts/orchestrator-run.sh` (fan-out to isolated git worktrees -> meter each step through `runaway-guard.sh step` [the kill-switch's first live call-site] -> integrate -> emit the OTel trace the **unchanged** scorecard reads). Replaces the E5-thin stand-in (`orchestrator-trace-demo.sh`, retired). Deterministic fixture engineer proves the loop in CI without an LLM (self-isolating selftest + golden-path `orchestrator-loop` job). New `orchestration` adapter dimension proves the roster binding per harness. Behaviour lock `orchestrator-loop` (claim).
- **Self-hosting commitment** (owner-ratified): the kit ships its own fresh-authored superpowers-equivalent and progressively shifts its own build onto it; E10 capstone = build a slice using only the kit's own roster.

### Honest ceiling
- E3a proves the loop's *mechanics*, not that an LLM writes good code. Enforced worktree isolation, conflict-safe parallel writes, and guard-at-fleet-scale are E3b/E4 (see the §10 status table in `docs/operations/orchestration.md`). The runaway meter is post-step/cumulative (bounds total fan-out; not per-action sandboxing). Security's threat-model hat is authored but only the review hat is exercised by the thin loop.

## [3.51.1] — 2026-06-26

**Fix — `version-tag-coherent` adopter-export N/A-skip (restores green-on-clone).**
The release-coherence gate `conformance/version-tag-coherent.sh` escalated "not a git repo" to
UNVERIFIED→FAIL under `--require` — correct for the kit's CI, but wrong for the deliberately
non-git adopter export, so `verify.sh --require` on a fresh export went RED. Broken since v3.49.1
(the gate shipped without the kit-self N/A-skip the other golden-path-coupled claims got in v3.48.18);
confirmed identical on the v3.50.0/v3.51.0 exports — not caused by E5-thin. The no-git branch now
N/A-skips when the export-ignored `docs/ROADMAP-KIT.md` anchor is absent (an adopter export /
pre-adoption tree), while the kit — where the anchor is present — still escalates to FAIL
(fail-closed; mirrors `feature-flags-wired.sh:49`). N/A-skip, not carve: the check stays live for an
adopter once they `git init`. New `--selftest` cases prove both arms (export → N/A; kit-without-git →
escalates). See `docs/architecture/2026-06-26-version-tag-coherent-export-fix.md`.

## [3.51.0] — 2026-06-26

**E5-thin — OTel-shaped agent-ops sensor → one real scorecard (the operate-loop sensor E3 consumes).**
A reference orchestrator stand-in (`scripts/orchestrator-trace-demo.sh`) now **emits** an OTel-shaped
span tree (root + engineer + reviewer + a guard-**denied** gate span) via a zero-dep emitter
(`scripts/otel-trace.sh`, one OTel-semantic span per NDJSON line, pluggable sink). A thin adapter
(`scripts/otel-to-scorecard.sh`) maps those spans into the MP-3a record shape the **unchanged**
`scripts/agent-scorecard.sh` consumes — so for the first time a real (non-fixture) run closes the
operate-loop and the scorecard's `denial_rate` is **derived from an emitted span**, proven
non-vacuously by a new golden-path `agentops-sensor` job (a dead emitter cannot produce that number).
An opt-in reference exporter (`scripts/otlp-export.sh`) renders the same trace as valid OTLP/JSON
`resourceSpans` and POSTs it to `$OTEL_EXPORTER_OTLP_ENDPOINT/v1/traces`. New behaviour lock
`conformance/agentops-sensor-wired.sh` (claim `agentops-sensor`) asserts the four selftests pass,
the scripts are executable, and the golden-path proof is wired; carved from the adopter export
(kit-self, mirrors `runtime-security`/`feature-flags-wired`).
Honest ceiling: **valid OTLP is produced and POSTed** — NOT asserted against a live vendor backend
(the adopter supplies endpoint + auth); the orchestrator is a **labelled stand-in E3a replaces**;
the golden-path proof runs the scorecard with `--min-runs 1` — so the denied agent classifies
`regressed` with an `auto-downgrade` directive (the non-vacuous signal the job asserts); this
is the **agent-ops** sensor, not app-level OTel (E5-full). `agent-scorecard.sh` is untouched
(selftest still green). The second of the two thin inputs (E1-thin ✅ / E5-thin ✅) that lead E3;
NEXT is E3a (the thin orchestrator loop, which replaces the stand-in body). See
`docs/architecture/2026-06-26-e5-thin-otel-sensor-design.md` and `docs/operations/agentic-ops.md`.

## [3.50.0] — 2026-06-26

**E1-thin — integration + e2e test layers (the E3 oracle).**
The typescript-node reference now demonstrates an **integration** layer (feature-flag → `/greeting`
wiring over real HTTP) and an **e2e** layer (full service journey: liveness → greeting → 404),
in-suite and zero-dependency (`server.listen(0)` + global `fetch`) — the runnable battery E3's
orchestrator will execute per integrated branch. New stack-neutral conditional gate
`conformance/test-layers-ready.sh` requires the integration + e2e layers when a project has a service
surface (Dockerfile / compose service), else N/A; detection is by cross-stack convention. Honest
ceiling: presence-by-convention (not test quality), behaviourally proven on the ts-node reference only
(a presence gate elsewhere until E1-full). Wiring mirrors `test-data-ready` (a `verify.sh` `check doc`
line + a CI `--selftest` step + a `conformance/README.md` row; not a §14 gate, so the gate counts are
unchanged). First slice of E1; the full battery (contract/security/a11y/property/load) fans out
post-E3. See `docs/operations/test-layers.md`.

## [3.49.1] — 2026-06-26

**Release-coherence gate + M2 ratification hardening.**
- **Release-coherence (new).** `conformance/version-tag-coherent.sh` (+ `.github/workflows/release-coherence.yml`, tag-push) asserts `VERSION` ≥ the highest reachable tag and, on a tagged commit, `VERSION == tag` — catching a skipped VERSION bump at release time (previously invisible to CI; the v3.49.0 incident). Wired into `verify.sh` / CI / drift-watch / doctor; claim `version-tag-coherent`. The check is N/A in a tagless checkout (its real catch is the `fetch-depth: 0` tag-push job).
- **M2 meta-control hardening.** Future-pin marker check also requires the marker be a real tag or the current `VERSION` (defense-in-depth; the marker's control-plane status remains the real guarantee), and is **lenient when tags are unavailable** (CI checkouts omit tags). Verdict parsing is case-normalized so a lowercase `deferred` still counts toward the serial-deferral cap; the verdict vocabulary stays open-ended (`GO-WITH-CONDITIONS`, `KEEP-BIASED`). Shared `conformance/version-helpers.sh` (`ver_ge`/`ver_gt`) dedups the semver comparison.

## [3.49.0] — 2026-06-26

**E4d — runaway kill-switch.**
An executable, harness-neutral circuit-breaker (`scripts/runaway-guard.sh`, verbs `step`/`check`/`reset`)
that halts an orchestrated flow when cumulative tokens, step count, or agent-spawn count breach a
control-plane ceiling (`.kit/budget.conf`). It enforces a ceiling on *reported* usage at the
orchestration seam; the platform LLM-API cap remains the hard backstop above it. Conformance-locked
(`conformance/runaway-killswitch-wired.sh`, wired into `verify.sh` / CI / drift-watch / doctor), and the
ceiling config is guarded against agent self-raising (Write/Edit **and** shell-redirect deny, regression-
locked in `agent-autonomy`). Honest ceiling: no hard spend cap (platform-owned), best-effort runtime
tally (`.kit-run/`, gitignored), wall-clock out of scope. Dual-reviewed (reviewer + security-reviewer
APPROVE; the security review adversarially verified the fail-closed path into drift-watch/doctor). See
`docs/operations/runaway-killswitch.md`. Delivers the cost/runaway item that E13 (FinOps) dissolved into.
No new gate ids; claim `runaway-killswitch` added.

## [3.48.18] — 2026-06-25

**Adopter-export-RED fix — restore the green-on-clone promise.**
The S4 meta-control panel found (a pre-M2 regression) that a fresh adopter export was RED on
`verify --require`: `feature-flags-wired`, `containment-audit`, and `runtime-security` hard-`FAIL`
because they require `.github/workflows/golden-path.yml`, which is export-ignored (it is the kit's own
maintainer pipeline). The export carves the matching *claims* (so `claims-registry` passed), but
`verify.sh` runs the three *scripts* directly as control-checks — and the export lock only ran
`claims-registry`, never `verify --require`, so nothing kit-side caught it until a real adopter would push.

### Fixed
- **`conformance/feature-flags-wired.sh` · `runtime-security.sh` · `containment-audit-wired.sh`** — each
  now N/A's on a non-kit tree via the OR-of-markers detector (`docs/ROADMAP-KIT.md` OR
  `.github/workflows/golden-path.yml` present ⇒ kit). On an adopter both are stripped → N/A (nothing to
  verify); on the kit they run as before. **Fail-closed**: if golden-path is deleted on the kit,
  `ROADMAP-KIT.md` still flags it → the existing `[ -f golden-path ] || FAIL` fires.

### Changed
- **`conformance/adopter-export-wired.sh`** — the export lock now runs `verify.sh --require` on the
  exported tree (the same aggregate the adopter's `ci.yml` runs), not just `claims-registry` — closing
  the gap that let this regression ship and catching any future control-check that hard-fails on the export.

## [3.48.17] — 2026-06-25

**M2-S5 — ratification integrity: the freshness circuit-breaker's headline guarantee now HOLDS.**
The S4 meta-control panel (run #3) found — and reproduced — that the gate was self-certifiable: the
verdict log + marker were ordinary docs, so an agent with Write could append a `GO` row + advance the
marker → FRESH, no panel, no human. This slice closes that gap, making *"an autonomous squad cannot
soften the circuit-breaker"* true mechanically rather than aspirationally.

### Changed
- **`.claude/hooks/guard-core.sh`** — `docs/governance/.meta-control-last` + `meta-control-log.md` are
  now control-plane in **both** matchers: `is_control_plane_path` (the Edit/Write tool path) **and** the
  `guard_check_command` regex (the shell mutation + redirect path — a redirect like `printf > marker`
  was the back door a tool-path-only fix would have left open). Writing a verdict now requires
  `KIT_GUARD_SELFEDIT=1` / a human commit.
- **`conformance/meta-control-fresh.sh`** — `validate_state` rejects a **future-pinned marker** (marker
  version must be ≤ `VERSION`; allows the legitimate ship-seam, rejects a fabricated `99.0.0`);
  `freshness` **caps serial deferral** (≥2 consecutive `DEFERRED` → OVERDUE). Three new `--selftest`
  fixtures (future-pin → FAIL, 2× DEFERRED → OVERDUE, 1× DEFERRED → FRESH) lock both.
- **`conformance/agent-autonomy.sh`** — deny cases for the marker + log on **both** the tool path
  (Edit/Write) and the shell path (`printf >` / `sed -i`), plus read-allow guards (mutation-locked).
- **`docs/operations/meta-control.md`** — documents the hardening. **`conformance/adopter-export-wired.sh`**
  — IGN += the S4 verdict artifact (the export-ignore-set sync deferred from S4).

## [3.48.16] — 2026-06-25

**M2-S3 — `.claude/agents/*` is now control-plane (the guard's Edit/Write deny-matrix).**
Closes the M1 security review's L2 finding: agent definitions — the `kit-steward`, `reviewer`, and
`security-reviewer` prompts that drive the meta-control panel and the builder≠reviewer separation —
could be silently modified via the Edit/Write tool. The shell path already caught
`.claude/` mutations; the tool path enumerated specific `.claude/` files (the guard, settings,
mcp-policy) but did not yet include agent definitions. They now live in `is_control_plane_path`, so changing an agent's
instructions is a ratified act (`KIT_GUARD_SELFEDIT=1` for deliberate human maintenance), exactly like
the guard itself and the CI gates.

### Changed
- **`.claude/hooks/guard-core.sh`** — `is_control_plane_path()` adds `*.claude/agents/*` /
  `.claude/agents/*`, grouped with the other `.claude/` control-plane patterns.

## [3.48.15] — 2026-06-25

**M2-S2 — the meta-control freshness gate: the cadenced go/no-go can no longer go stale unnoticed.**
M1 productized the adversarial meta-control panel; M2 ENFORCES its cadence. A new conformance check
flags when a panel is OVERDUE (more than N=5 release tags since the last addressed run), so the control
that catches direction / proportion / over-claim drift fires without depending on a human noticing —
the exact failure the M-series was created to fix.

### Added
- **`conformance/meta-control-fresh.sh`** — the freshness gate. DUE = >N=5 release tags since the last
  addressed run, read from a one-line marker `docs/governance/.meta-control-last` kept in lockstep with
  the verdict log's last row (sync enforced). Applicability is a DETECTED trigger (the project keeps a
  log/marker, or it's the kit) — never the declared mode (`mode-enforcement-blind.sh`), so a mode can
  never weaken it. Satisfied by a logged run OR a dated `DEFERRED` row. `--selftest` locks the mechanism
  + sync + wiring (8 fixtures incl. the strict `>N` boundary, fail-closed, desync, N/A).
- **`docs/governance/.meta-control-last`** — the machine marker (export-ignored kit-instance state).
- **claim `meta-control-fresh`** — its verifier is the `--selftest`, so per-PR CI enforces the MECHANISM
  + sync, never the live freshness verdict (an overdue kit never blocks unrelated PRs).

### Changed
- **`.github/workflows/drift-watch.yml`** — a separate `meta-control-freshness` job runs the gate
  weekly (an OVERDUE result fails that job — the loud, attributable circuit-breaker, kept distinct from
  the regression job to avoid cry-wolf).
- **`scripts/doctor.sh`** — surfaces freshness as an advisory METRICS row (never affects exit).
- **`docs/operations/meta-control.md`** — documents the gate, the marker, and the run-or-deferral
  satisfaction model. **`conformance/adopter-export-wired.sh`** + **`.gitattributes`** — export-ignore
  the marker. **`docs/governance/meta-control-log.md`** — a `DEFERRED` row (v3.48.15): the gate ships
  green and honest; the due light 5-lens panel is M2-S4.

## [3.48.14] — 2026-06-24

**M2-S1 — export-ignore the meta-control verdict-log cluster + harden the export link-safety lock.**
Prerequisite for the M2 freshness gate (the cadenced meta-control circuit-breaker). The kit's verdict
log and its two dated run artifacts are kit-instance history (like `ROADMAP-KIT.md`), so they are now
export-ignored — adopters start fresh. They are link-entangled (the log links its run artifacts; the
runbook linked the log), which exposed a latent false-positive in the export link-safety lock.

### Changed
- **`.gitattributes`** — export-ignore `docs/governance/meta-control-log.md`,
  `docs/architecture/2026-06-23-meta-control-first-run.md`, and
  `docs/architecture/2026-06-24-t3a-rightweight-assessment.md`.
- **`docs/operations/meta-control.md`** — the sole KEPT→ignored markdown link (to the verdict log)
  becomes a backtick mention, so no kept doc dangles after the export.

### Fixed
- **`conformance/adopter-export-wired.sh`** — block-(b) link-safety scanned ALL tracked `.md`, so a
  link BETWEEN two export-ignored docs (ignored→ignored) false-failed. It now excludes the IGN set
  from the scan (only a KEPT→ignored link breaks a real adopter's CI). Adds a selftest fixture locking
  that a real KEPT→ignored link still FAILs, and a fail-closed guard rejecting pathspec-hostile IGN
  entries so the `:(exclude)` scan can never error-into-a-silent-pass.

## [3.48.13] — 2026-06-24

**T4 — dedupe the Markdown link-extractor into `wf-helpers.sh` (single source of truth).**
The awk that strips fenced + inline code before extracting `](…)` links lived in two copies
(`check-links.sh` + `adopter-export-wired.sh`) — the exact duplication that bit T4 (the code-span fix
had to be applied twice; CI caught the missed twin). Extracted once; the gotcha can no longer drift.

### Changed
- **`conformance/wf-helpers.sh`** — gains `wf_extract_links()` (the code-span/fence-skipping link
  extractor), alongside the existing `wf_is_deploy()`. wf-helpers is the established shared-helper file,
  already sourced by 6 conformance checks.
- **`conformance/check-links.sh`** + **`conformance/adopter-export-wired.sh`** — drop their inline copies
  and source `wf_extract_links()`. Behavior byte-identical (dual-review verified against a 12-fixture
  battery + a real CommonMark renderer); the export still ships `wf-helpers.sh` so the extractor resolves
  inside the adopter tree too. adopter-export-wired now resolves its script dir *before* `cd` so sourcing
  is cwd-independent.
- builder ≠ reviewer + security-review-of-scratch both APPROVE (net security improvement — eliminates the
  drift risk; no silent-vacuous-pass hole; `check-links --selftest` in CI guards the shared function).

### Deferred (R capstone)
- `adopter-export-wired.sh:31`'s narrower basename-link grep (its false-positive over-flags = safe);
  the larger `*-wired.sh` selftest-harness deduplication.

## [3.48.12] — 2026-06-24

**T4 — export hygiene: stop shipping maintainer-only paths to adopters.**
Closes the T2 brownfield CODEOWNERS false-alarm. The export-ignore set now also strips three internal
design/audit docs adopters don't need. (Control-plane: `.gitattributes` + the `adopter-export-wired`
regression-lock; security-review + builder ≠ reviewer both APPROVE — link-safe, ADR-000 preserved.)

### Changed
- **`.gitattributes` + `conformance/adopter-export-wired.sh`** — added to the export-ignore set:
  - **`.github/CODEOWNERS`** — the kit's own `@SeaBrad72` owners shipped by omission, so a clean
    greenfield install saw a non-existent owner (T2 brownfield false-alarm). Adopters still get a
    working CODEOWNERS: `incept.sh` copies the profile's `CODEOWNERS` template into place.
  - **3 dated internal docs** — `2026-06-22-e3-agentic-orchestration-design.md`,
    `2026-06-23-e-series-consolidation-audit.md`, `2026-06-23-t2-real-validation-findings.md`
    (maintainer work-products, same category as the already-ignored `ROADMAP-KIT.md`).
  - **Kept:** `docs/architecture/ADR-000-stack.md` (the adopter-facing ADR example).
- *Deferred to M2:* the 2 remaining dated docs (`meta-control-first-run`, `t3a-rightweight-assessment`)
  + `docs/governance/meta-control-log.md` — they're link-entangled with the verdict log, so ignoring
  them needs the lock's intra-set link-safety fix, which lands with M2's verdict-log export-ignore.

## [3.48.11] — 2026-06-24

**T4 — two T2 honesty findings: `explain` process vocabulary + the private-repo `enforce_admins` caveat.**
Docs-only; agent-editable.

### Changed
- **`docs/why-gates.md`** — `explain` covered CI-gate vocabulary only, so `sparkwright explain
  autonomy-tier` / `intent-owner` / `wip-limit` (terms used throughout START-HERE) returned nothing.
  Added the three process-vocabulary topics (autonomy-tier is `Enforced by: conformance/agent-autonomy.sh`;
  intent-owner / wip-limit are process concepts with doc references). They surface automatically via the
  doc-driven `explain` reader; `explain-wired` stays green (orphan check validates the real enforcer).
- **`docs/operations/review-lane.md`** — added an honest caveat to the solo→team "one `enforce_admins`
  flip": on a **private free-tier** repo the `enforce_admins` API 404s (needs GitHub Pro/Team); public
  and paid-private repos are unaffected, and the solo `--admin` lane + recorded `REVIEW-RECORD` remain
  the compensating control until the plan supports the flip. (The kit verifies the SoD *logic*
  regardless of plan; only server-side *enforcement* is plan-gated.)

## [3.48.10] — 2026-06-24

**T4 — check-links: skip code spans + fenced blocks (the kit's own linter, made CommonMark-correct).**
`check-links.sh` extracted links from raw text, so any doc that *quoted* link syntax inside a backtick
span or a fenced block was false-flagged as a broken link (it bit this very arc three times). Fixed +
locked with a selftest so it can't silently return.

### Changed
- **`conformance/check-links.sh`** — link extraction now pre-processes each file (drops fenced `/~~~`
  blocks + strips inline `` `code` `` spans) before matching `](…)`. A link inside code isn't rendered
  as a link, so ignoring it is correctness, not a loophole. **No regression** — real (rendered) broken
  links are still caught, including a real link on the same line as a code span (proven against a real
  CommonMark renderer; the dropped set is a strict subset of the renderer's non-rendered set).
  Conservative by design (rare nested-fence shapes may over-extract = fail-safe false-flag, never a
  missed link). Adds a `--selftest` (code-span / fence skipping is load-bearing) wired into `ci.yml`.
- **`conformance/adopter-export-wired.sh`** — the same gotcha lived in its inline export link-check
  (CI caught it: this entry's own code-span examples tripped it); applied the identical (reviewed)
  awk code-strip. *(There are now two copies of the awk — the `wf-helpers.sh` refactor, the next T4
  item, dedupes both, incl. line 31's narrower basename grep.)*
- builder ≠ reviewer + security-review-of-scratch both APPROVE.

## [3.48.9] — 2026-06-24

**T4 — golden-path hardening: catch incept.sh breaks per-PR + quiet adopter editor false-positives.**

### Changed
- **`.github/workflows/golden-path.yml`** — (F7) the `pull_request`/`push` path-filters now include
  **`scripts/incept.sh`**: golden-path runs `sh scripts/incept.sh` in three of its jobs (it generates the
  scaffold the harness then exercises), so a break there is now caught per-PR instead of only on the
  weekly/dispatch run.
- **`.github/workflows/golden-path.yml`** — each job now declares its runtime temp-dir var at job level
  with an empty default (`env: { GP_DIR/EXPORT/CA_DIR/IV_DIR: '' }`). The value is still set at runtime
  via `$GITHUB_ENV`; the declaration only resolves the GitHub Actions VS Code extension's "Context
  access might be invalid" false-positives — adopter-experience hygiene (an adopter copying the workflow
  no longer sees confusing red squiggles). No behavior change (reviewer-confirmed: empty defaults are a
  safe fail-loud mode; path-widening is strictly additive).

## [3.48.8] — 2026-06-24

**T4 (CI-trust Blocker b) — claims-registry: surface diagnostics + preserve the three-state.**
The second CI-trust Blocker the M1 meta-control first run surfaced. Diagnostics/labels only — no
behavior change on the happy path (every claim still PASSes, exit 0); the registry stays fail-closed.

### Changed
- **`conformance/claims-registry.sh`** — each claim's verifier ran as `sh -c "$v" >/dev/null 2>&1`,
  which (a) **swallowed** the verifier's output (a failing claim showed no *why*) and (b) **collapsed**
  the three-state (any non-zero → FAIL, so an `exit 2` UNVERIFIED was mislabeled FAIL). Now mirrors
  `verify.sh`: captures output, classifies **0 = PASS · 2 = UNVERIFIED · other = FAIL**, and **prints
  the captured output (indented) on any non-pass** so a CI failure shows the reason. Both UNVERIFIED and
  FAIL still fail the registry (fail-closed). Added a verifier contract note (structural output only —
  never a secret value, since output is now surfaced) + selftest fixtures for the new three-state and
  diagnostics. builder ≠ reviewer + security-review-of-scratch both APPROVE (no net weakening: every
  outcome that failed the registry before still fails it).

## [3.48.7] — 2026-06-24

**T4 (CI-trust Blocker a) — per-PR control enforcement + a trustworthy weekly drift-watch.**
The kit's own controls now actually enforce on every PR, and the weekly detective signal is
green-when-healthy instead of perpetually red. (One of the two CI-trust Blockers the M1 meta-control
first run surfaced.)

### Added
- **`conformance/verify-enforced-wired.sh`** (claim `verify-enforced`; claims 31→32) — a durable lock
  asserting `ci.yml` runs the conformance aggregate **enforcing** (`verify.sh --require`), not
  renderer-only (`--selftest`). Rejects whole-line-comment, trailing-comment, and `|| true`-suppressed
  bypasses (selftest-proven).

### Changed
- **`conformance/verify.sh`** — the `[control]` aggregate no longer includes `branch-protection` (a
  remote-state control needing repo-admin creds the least-privilege CI token can't have); the aggregate
  is now all-offline, so `--require` runs clean in CI. `--selftest` is hardened **non-vacuous**
  (requires ≥1 `[control]` PASS — a green-while-dark all-FAIL render is rejected).
- **`.github/workflows/ci.yml`** — adds an **enforcing** `verify.sh --require` step (the missing per-PR
  control enforcement) + the new lock + its self-test.
- **`.github/workflows/drift-watch.yml`** — runs the now-offline aggregate (goes green-when-healthy
  instead of failing every week on branch-protection) + a `jq` preflight so a dropped-tool runner fails
  loud, not as an opaque UNVERIFIED.
- **`conformance/branch-protection.sh`** — honest header: NOT in the per-PR aggregate (least-privilege);
  real-path verification is maintainer/governance-gated (admin `gh`); config-as-code
  (`github_branch_protection`) + a least-privilege `administration:read` detective verifier are the **E9**
  reference.

### Security
- **No net weakening** — branch-protection had no PASS path under a least-privilege CI token (proven by
  security review: it was `--selftest`-only per-PR and red-failing weekly, i.e. never CI-verified). This
  makes that honest and lets the other 23 controls actually enforce per-PR. builder ≠ reviewer +
  security-review-of-scratch both APPROVE.

## [3.48.6] — 2026-06-24

**T3d — consolidation wrap-up: backlog reorg, release-line, and the retire-convention doc.**
Closes the T3 right-weighting arc (T3a assessment → T3c content cuts → T3d reconciliation). Docs-only;
no code or gate change.

### Added
- **`docs/operations/retiring-conventions.md`** — the safe-retirement discipline this arc exercised
  (design-intent KEEP-default lens · inbound-ref classification · prove-no-gate-depends · content-
  preserving migration · control-plane via apply.py · gate-and-deletion atomic). T3b descoped to this
  convention (the T3a assessment found zero conformance/claims to retire — no mechanism to build).
  Cross-referenced from `MAINTAINING.md` §1.

### Changed
- **`docs/ROADMAP-KIT.md`** — epic reorg (ratified): **E12 + E14 → E3** (context-engineering and
  human-in-loop are orchestration slices), **E13 → E4d + E6**, **E8 deferred**, **E9/E11 kept but
  scope-challenged**; net feature epics 10 → 6. **Release-line decided:** stay **3.x**; 1.0 gated on
  feature-complete + E10 + a real external adopter (T2 established pre-adoption). T3 marked DONE; two
  T3-banked findings logged to T4 (the `check-links.sh` code-span gotcha; the `docs/architecture/`
  ships-to-adopters export-ignore candidate). Stale "this release v1.0.0" line corrected; the
  "first-class 10 profiles unqualified" residue marked closed (v3.48.1).
- **`templates/JIRA-SETUP-TEMPLATE.md`** — adds a reciprocal **tier note** (server-enforced *Only
  Assignee* tier vs `TRACKER-SETUP`'s convention tier; deliberately distinct, per design-intent
  reversal #3 keeping both).
- **`docs/architecture/2026-06-24-t3a-rightweight-assessment.md`** — records **design-intent reversal
  #12** (AI-POLICY kept in `templates/` — it's one of the 9 incept-stamped governance templates; moving
  only it breaks set-coherence for a cosmetic gain).

## [3.48.5] — 2026-06-24

**T3c (consolidation) — frame.md + shape.md folded into discovery-loop.md as sections.**
Content-preserving: the two thin per-stage guides become `## FRAME` / `## SHAPE` sections of the loop
overview they belong to — one reader-journey instead of three files. The completeness gate is updated
in lockstep (file-presence → section-presence) and is **not weakened**: a discovery-loop that names the
stages in its overview table but lacks the actual FRAME/SHAPE guide sections still FAILS (a new
load-bearing selftest fixture proves it).

### Removed
- `docs/discovery/frame.md`, `docs/discovery/shape.md` — content migrated verbatim into discovery-loop.md.

### Changed
- **`docs/discovery/discovery-loop.md`** — gains `## FRAME` and `## SHAPE` stage-guide sections; the
  three former `[frame.md]`/`[shape.md]` links now point to those in-page sections.
- **`conformance/discovery-complete.sh`** (control-plane; applied via human-run apply.py) — asserts the
  FRAME/SHAPE **sections** exist in discovery-loop.md (`^## FRAME`/`^## SHAPE`, distinct from the
  overview `**FRAME**` token) instead of the separate files; selftest gains a green-while-dark RED
  fixture (overview-only loop, sections stripped → must fail).

## [3.48.4] — 2026-06-24

**T3c (consolidation) — CODE-REVIEW-CHECKLIST folded into REVIEW-RECORD as a rubric block.**
Content-preserving: all 10 quality dimensions kept verbatim, now co-located with the review record they
feed. Keeps the deliberate distinction — the rubric is *what to check* (a distinct block), the record is
*what was found*. Templates 24→23.

### Removed
- `templates/CODE-REVIEW-CHECKLIST.md` — its 10 dimensions migrated.

### Changed
- **`templates/REVIEW-RECORD-TEMPLATE.md`** — gains a `## Quality-lens rubric (what to check)` section
  (the 10 dimensions verbatim), placed before *Agent-review findings* so the rubric drives the findings.
- **`docs/operations/code-quality.md`** — the §7 review-lens pointer now references the REVIEW-RECORD
  quality-lens rubric.
- **`DEVELOPMENT-PROCESS.md`** — the §Review row's code-quality-lens pointer repointed likewise
  (control-plane; applied via human-run apply.py).

## [3.48.3] — 2026-06-24

**T3c (consolidation) — SPEC template consolidated into FEATURE-REQUEST (one fewer template).**
Content-preserving: no PRD capability lost. The Plan-phase spec is now an **optional** "Extended spec"
section of the intake template, keeping the harness-neutral manual-fallback framing (the manual
alternative to a brainstorming-flow spec, signed off at the §7 spec gate).

### Removed
- `templates/SPEC-TEMPLATE.md` — its distinct value (goals/non-goals, personas, numbered functional
  requirements, testable acceptance criteria, data&privacy, risks&mitigations, out-of-scope) migrated.

### Changed
- **`templates/FEATURE-REQUEST-TEMPLATE.md`** — gains an optional `## Extended spec (Plan phase)`
  section. Explicitly skippable for small/obvious slices (a vibe-coder is never forced into a PRD); the
  base sections (Problem, Success metric, UX&a11y) are not duplicated.
- **`templates/TEST-PLAN-TEMPLATE.md`** — the 2 `SPEC-TEMPLATE.md` references now point at
  FEATURE-REQUEST's *Extended spec*.
- **`README.md`** — the "What's inside" templates example list drops `SPEC` (now part of FEATURE-REQUEST).

## [3.48.2] — 2026-06-24

**T3c (consolidation) — retire 6 completed E4 build-design docs (dead artifacts).**
Subtractive right-weighting: the six E4 design docs are completed-build artifacts whose rationale lives
on in the CHANGELOG entries (E4a–E4e) + the live implementation. No live code, conformance check, or
markdown link depends on them.

### Removed
- `docs/architecture/2026-06-22-e4a-containment-audit-design.md`
- `docs/architecture/2026-06-23-e4-work-mount-fix-design.md`
- `docs/architecture/2026-06-23-e4a-prime-token-scope-design.md`
- `docs/architecture/2026-06-23-e4b-image-vuln-gate-design.md`
- `docs/architecture/2026-06-23-e4c-dast-runtime-security-design.md`
- `docs/architecture/2026-06-23-e4e-author-not-approver-sod-design.md`

### Changed
- **`docs/ROADMAP-KIT.md`** — the 6 E4-shipped entries' trailing "Design: `…`" pointers (backtick
  mentions, not links) now read "Design retired in T3c" instead of naming the deleted files.

### Notes
- **Kept** (not dead): `2026-06-22-e3-…-design.md` (E3 not built — live spec),
  `e-series-consolidation-audit`, `meta-control-first-run`, `t2-real-validation-findings`, `t3a-rightweight-assessment`.
- The ledger's "delete atomically with 5 companion plan docs or check-links breaks" rationale was
  **disproven against the mechanism**: `check-links.sh` scans only tracked `*.md` and only relative
  Markdown link targets; the plan docs are gitignored (never scanned/shipped). Correction recorded in the T3a assessment doc.
- *Open follow-up (not this slice):* `docs/architecture/` ships to adopters — whether the kit's
  internal build-design history should be export-ignored wholesale is a candidate for T3d/T4.

## [3.48.1] — 2026-06-24

**T3c (consolidation) — profile maturity relabel: honest first-class vs experimental tiers.**
Right-weighting by honesty, not subtraction — no profile removed, all still ship and `adopter-export
--profile` still prunes any. Closes the flagged residue *"first-class 10 profiles unqualified"* (only
`typescript-node` is maintainer-executed).

### Changed
- **All 10 profile `Status:` fields now carry a maturity tier** — first-class
  (`typescript-node`, `python`, `go`, `ml`, `terraform`) vs experimental (`java-spring`, `kotlin`,
  `dotnet`, `rust`, `data-engineering`). The 9 non-ts profiles remain provided-not-maintainer-executed.
- **`docs/STACK-SELECTION.md`** — comparison matrix gains a **Maturity** column + a "Maturity tiers"
  definition (first-class-verified = `typescript-node` only; first-class = actively-maintained
  references; experimental = least-exercised, expect more adaptation).
- **`README.md`** — the profile line no longer calls all 10 "first-class"; it states the honest
  5 first-class / 5 experimental split and links the maturity tiers.

### Notes
- The Group-4 SHA-pin "paired finding" (SHA-pin the 9 profiles' `ci.yml`) was **dropped** as a
  design-intent reversal — `conformance/action-pinning.sh` deliberately treats those profiles as
  "pin at adoption" templates and enforces SHA-pinning where the kit actually executes Actions.
  Recorded as reversal #11 in `docs/architecture/2026-06-24-t3a-rightweight-assessment.md`.

## [3.48.0] — 2026-06-23

**M1 — cadenced meta-control: the adversarial go/no-go + retro, productized (panel + first use).**
The kit's own meta-controls were designed but never operationalized — nothing triggered them, so
locally-good slices drifted globally (direction/proportion, which CI can't see). M1 makes the panel a
committed, harness-neutral, runnable artifact and runs it once; M2 (next) adds the staleness gate that
forces it to run.

### Added
- **`docs/operations/meta-control.md`** — the canonical, harness-neutral runbook: a tiered adversarial
  panel (5-lens *light* every-N-slices, **N=5**; 11-dim *full* at epic/release boundaries), the
  evidence standard, per-lens schema, adversarial verify pass, GO/CONDITIONS/NO-GO verdict, the two
  ledgers, retro fold-in, and routing. The institutional counterpart to `drift-self-check.md` — and,
  unlike it, gateable (it produces a verdict artifact).
- **`.claude/agents/kit-steward.md`** — the Claude-native binding (read-mostly) that runs the panel;
  the "E3 critic/steward sliver". Any harness uses the runbook directly.
- **`docs/governance/meta-control-log.md`** — the verdict log (kit instance; M2 export-ignores it).
- **First run** (`docs/architecture/2026-06-23-meta-control-first-run.md`) — the 5-lens panel run on
  the kit (verdict **GO-WITH-CONDITIONS**). It validated the consolidation pivot *by the mechanism* and
  resequenced the backlog (T2 first; E4d decoupled; E3 not default-first) — including a **new CI-trust
  Blocker the manual audit missed** (per-PR CI ran `verify.sh --selftest`, not `--require`). Ratified
  by the subsequent `ROADMAP-KIT.md` commit in this PR (agents propose, humans ratify).

### Changed
- **`docs/ROADMAP-KIT.md`** — reprioritized to the meta-control-ratified order (the runbook's "closing
  the loop" step); T1 marked complete; staleness fixed.

Harness-neutral by design: the runbook is the canonical definition; no `.claude/workflows/` script is
committed (orchestration is harness-local). No control-plane change, no new claim — the enforcement
(staleness gate + verdict ledger + lock + claim) is M2.

## [3.47.2] — 2026-06-23

**Consolidation Tier 1 / F3 + F4 — honesty closeout.** The "never externally adopted" maturity
caveat lived only in the export-ignored `ROADMAP-KIT.md` (stripped from what adopters receive), and
several release headlines used a bare "PROVEN" verb their bodies already scoped to the ts-node reference.

### Changed
- **README** — new `## Maturity & validation status` section: the kit is pre-adoption, validated
  in-house (own CI + 2 synthetic dogfoods), `typescript-node` is the maturity-verified reference path.
  Now in an **exported** doc, so adopters actually receive the caveat (F3).
- **`docs/enterprise/EXEC-BRIEF.md`** §5 — adds the pre-adoption maturity line to the honest-boundaries
  picture (F3).
- **CHANGELOG** — re-scoped four over-claimed headline verbs (E4a / E2 / E4c / E4e) to single-reference
  reality; bodies were already honest except one E4e lead sentence ("a *proven* control") similarly qualified (F4).
- **`MAINTAINING.md`** §3 + CHANGELOG header — a forward claim-verb discipline so "proven" can't
  out-claim its scope again (F4).

Docs-only; no contract, conformance, or claim change. Part of the consolidation arc
(`docs/architecture/2026-06-23-e-series-consolidation-audit.md`).

## [3.47.1] — 2026-06-23

**Consolidation Tier 1 / F1 — honest, drift-proof export file-count.** The Quickstart over-promised
"242 files (down from 392)"; the real export is 277 / HEAD 416, and the conformance lock never asserted
the count, so it drifted green as the E-series added files.

### Fixed
- **README** no longer hardcodes the drifting absolute — it defers to the export script, which already
  prints the exact count (`exported … files`). Eliminates the drift class rather than chasing the number.
- **`conformance/adopter-export-wired.sh`** now guards against a hardcoded export count reappearing
  (`down from …` / `NNN files`), with a load-bearing negative selftest. Also fixes a latent
  `VAR=val function` env-prefix leak in the existing `--selftest` (subshell-scoped now). No new claim.

Part of the consolidation arc (`docs/architecture/2026-06-23-e-series-consolidation-audit.md`):
pause net-new epics (E3 deferred), pay down confirmed over-promise/over-build first.

## [3.47.0] — 2026-06-23

**E4e — Separation of duties: author ≠ approver gate (FLOOR + NATIVE).** Closes the R2-deferred
bot-identity ratification gate — makes "author ≠ approver" a *gate* (FLOOR logic proven by selftest), not a convention,
without binding the kit to GitHub. The principle is forge-neutral; only the binding is forge-specific.

### Added
- **`scripts/sod-check.sh`** — the forge-neutral SoD FLOOR: a pure identity-set gate (PR/MR author vs
  approver-set vs commit-author-set) that PASSes only when a ratifier distinct from the author and every
  commit-author exists, and **fails closed under CI** when inputs are absent. Whole-line fixed-string
  comparison (no word-split, no glob — any metacharacter is a literal identity); proven by `--selftest`
  (9 fixtures incl. metachar/casing/anti-vacuity). What the kit *proves* — and being neutral, the proof is too.
- **`docs/operations/separation-of-duties.md`** — the neutral contract + tiers (solo/lite keeps the honest
  admin-merge convention; team/enterprise use a distinct ratifying identity) + the honest ceiling.
- **`docs/operations/sod-gate.github.yml`** — a copy-and-enable GitHub reference workflow (injection-safe;
  deliberately *not* in `.github/workflows/` so it never auto-runs on the kit) that feeds `sod-check.sh`
  from the PR event, with the bot-identity-via-App pattern documented.
- **GitLab native binding** — `gitlab-adoption.md` points to the native MR approval rules
  *"Prevent approval by author"* + *"Prevent approvals by users who added commits"*.
- **`conformance/author-not-approver-wired.sh`** (new claim `author-not-approver`, claims 28 → **29**) —
  runs the FLOOR selftest (behaviour) + static-locks the bindings + `actionlint`-parses the reference
  workflow. **Mode-blind.**
- **Guard protection** for `scripts/sod-check.sh` (`is_control_plane_path`, mirroring `containment-audit.sh`).

### Honest ceiling
- The kit proves the SoD *logic*; **server-side enforcement is the adopter's** branch-protection / forge
  approval rules (kit CI cannot run a live distinct-approver scenario — the kit is itself the solo case).
  `gh pr merge --admin` remains a human-only, audit-trailed escape hatch; an `--admin` detective audit is a
  deferred follow-up. Unattributed (unlinked-email) commits weaken the commit-author check — require linked
  or signed commits; SoD does not defend against collusion between two distinct identities.

## [3.46.0] — 2026-06-23

**E4 — Agent sandbox: hardened + writable across all container profiles.** Closes the E4a `/work`
follow-up *and* a propagation gap: the hardened agent sandbox shipped only in `typescript-node`.

### Added
- **The hardened `agent` sandbox in all 7 container profiles' `compose.yaml`** (was ts-node only):
  `read_only` root, `network_mode: none`, `cap_drop: [ALL]`, `no-new-privileges`, work-tree-only mount,
  opt-in (`profiles: [agent]`). Provided for all; behaviourally proven on the ts-node reference.

### Fixed
- **The agent sandbox can now write `/work` on Linux.** It builds as root and `cap_drop: [ALL]` strips
  DAC_OVERRIDE, so root couldn't write a host-owned bind mount (worked on Docker-Desktop/macOS via
  fakeowner). The service now runs as `${HOST_UID:-1000}:${HOST_GID:-1000}` — pass `HOST_UID=$(id -u)
  HOST_GID=$(id -g)` so the agent owns the work tree, **keeping every containment property** (running
  non-root is, if anything, stronger). `conformance/containment-audit.sh` re-promotes the `/work`
  write probe from informational back to a **gated positive** (`POS fs-work: PASS`), proven live on
  Linux in the `containment-audit` job alongside the unchanged negatives.

## [3.45.0] — 2026-06-23

**E4c — DAST / runtime-security: security-header floor proven on the reference server + documented ZAP reference.** Closes
the last named gap-assessment blind spot (no DAST / runtime security). The reference CI did only
*static* analysis (`gate-sast`, deps, image) — nothing exercised the *running* app.

### Added
- **Security headers on the reference app** (`profiles/typescript-node/scaffold/src/server.ts`,
  zero-dep, every response): `X-Content-Type-Options: nosniff` · `X-Frame-Options: DENY` ·
  `Content-Security-Policy: default-src 'none'` · `Referrer-Policy: no-referrer`.
- **`conformance/runtime-security.sh`** (claim `runtime-security`; claims **27 → 28**) — static-locks
  the reference app's headers + the golden-path runtime assertion; `--selftest`; wired into `verify.sh`
  + CI. Carved from the adopter export (reads the export-ignored `golden-path.yml`), mirroring
  `containment-audit`; the hardened `server.ts` still ships.
- **golden-path runtime-security assertion** — on the booted reference container, asserts all four
  headers are present (deterministic, non-vacuous; runs live on PR + main).
- **`docs/operations/security-scanning.md` DAST section** — the OWASP ZAP baseline pattern as a
  documented reference for adopters with real attack surface (opt-in, not a forced gate).

### Honest boundary
The kit *proves* the runtime-security header floor on its (intentionally trivial) reference; full
DAST against real routes/auth/inputs is the documented adopter pattern. HSTS is intentionally absent
(the reference terminates plain HTTP; HSTS is the TLS-terminator's responsibility).

## [3.44.0] — 2026-06-23

**E4a′ — Token-scope static gate (completes the 4-platform-controls coverage).** E4a proved three
containment controls behaviourally (FS-scope/egress/caps); the remaining two (scoped-tokens,
prod-cred SoD) are cloud-IAM-owned. E4a′ adds a *static structural* gate over the workflows the kit
ships, so the OIDC discipline the RUNBOOK attests is also machine-checked.

### Added
- **`conformance/token-scope.sh`** (claim `token-scope`; claims **26 → 27**) — over `profiles/*/ci.yml`
  + `.github/workflows/*.yml`, asserts (1) the **top-level** `permissions:` block grants no
  `id-token: write` / `write-all` (OIDC tokens must be **job-scoped**, never workflow-wide), and (2)
  **no long-lived cloud credentials** (curated AWS/Azure/GCP static-key identifiers — `secrets.GITHUB_TOKEN`
  and OIDC role ARNs are allowed). Mirrors `provenance-precondition.sh`; wired into `verify.sh` + CI.

### Changed
- **`docs/operations/containment.md` §2** — notes the static gate complements the RUNBOOK attestation.

### Honest boundary
Static-structural on the shipped workflows — **not** a behavioural proof of the adopter's cloud IAM,
and prod-cred SoD's deployment-specific separation stays RUNBOOK-attested (`containment-ready.sh`
unchanged). The gate fires only on a regression (kit + all profiles pass today).

## [3.43.0] — 2026-06-23

**E4b — Image-vuln gate: a Trivy CVE scan that actually gates (second E4 build).** Closes the
gap-assessment blind spot "the SBOM enumerates, nothing gates" — the reference CI built the image and
listed its packages (`gate-image-sbom`) but never scanned for CVEs or failed on them. E4b adds a real
image-vulnerability gate and proves, in golden-path, that it runs and discriminates.

### Added
- **`gate-image-vuln`** — a SHA-pinned `aquasecurity/trivy-action` step in all **7 Dockerfile profiles'**
  `ci.yml`, scanning the built image and failing on **fixable CRITICAL/HIGH**
  (`severity: CRITICAL,HIGH · ignore-unfixed · vuln-type: os,library · exit-code: 1`). Unfixed CVEs stay
  enumerated by the SBOM, not gated — the gate covers *actionable* risk so it stays enabled.
- **`image-vuln` job in `golden-path.yml`** — the behavioural proof: it scans the reference image (must
  PASS clean) **and** a pinned known-vulnerable fixture (must be **blocked by actual findings**, asserted
  via a `jq` vulnerability count, not merely a non-zero exit) — so the gate can't vacuously pass. Runs
  live on PR + main.

### Changed
- **`conformance/container-supply-chain.sh`** now requires `gate-image-vuln` wherever a Dockerfile ships
  (fail-closed, profile-wide — consistent with the image SBOM + provenance gates).
- **`conformance/golden-path-wired.sh`** locks the new `image-vuln` job (no new headline claim; reuses
  the `golden-path` claim — count stays 26).
- **`DEVELOPMENT-STANDARDS.md` §14** — the container image supply-chain gate now includes the image-vuln scan.

## [3.42.0] — 2026-06-22

**E4a — Containment-audit: the agent sandbox is proven to contain on the ts-node reference (first E4 build).** Closes the
gap-assessment finding that the platform containment controls were *attestation-only* — `containment-ready.sh`
read a RUNBOOK line, nothing booted the sandbox. E4a moves three of the four controls from attestation to
**behaviour**: it boots the shipped `agent` sandbox and probes that the boundary actually holds, each negative
probe paired with a positive control so a dead container cannot pass vacuously. Scoped-tokens / prod-cred-SoD
stay honestly-labelled attestation (cloud-IAM owned, not container-bootable) — slated for E4a′.

### Added
- **`scripts/containment-audit.sh`** — boots the reference `agent` service (`docker compose --profile agent
  run`) and probes **FS-scope** (write outside `/work` fails, inside succeeds), **egress**
  (`network_mode: none` blocks outbound), and **caps** (`cap_drop: [ALL]` blocks a CAP-gated op). Fail-closed:
  under CI/`--require`, docker-absent is a failure, not a skip. Adopter-runnable against their own compose.
  Added to the guard's control-plane set so the gate can't be silently weakened.
- **`conformance/containment-audit-wired.sh`** — regression lock: the runner + its `golden-path` job + the
  negative/positive probe **pairing** are wired and can't rot to a vacuous negatives-only check. Claim
  `containment-audit`; headline claims **25 → 26**.
- **`containment-audit` job in `golden-path.yml`** — runs the audit live on PR + main (real docker boot+probe)
  — the behavioural proof, the same bar `golden-path` set in G2.

### Changed
- **`docs/operations/containment.md`** — documents the audit as the runnable behavioural backing for the
  shipped reference (the kit proves its artifact; the adopter still attests their deployment).
- The `containment-audit` claim is carved from the adopter export (its verifier reads the export-ignored
  `golden-path.yml`), mirroring `feature-flags-wired`; the runner script itself ships as an adopter capability.

## [3.41.0] — 2026-06-22

**E2 — Feature flags: kill-switch floor, proven on the ts-node reference (first E-series build).** Closes the gap-assessment
finding that feature flags were *prescribed-only* — zero reference, zero conformance — despite being the
kill-switch/rollback foundation. Ships the smallest complete declaration→behaviour vertical: a
zero-dependency flag the kit *provides*, a golden-path drill that *proves* the kill-switch flips behaviour
end-to-end, and two-part conformance.

### Added
- **`profiles/typescript-node/scaffold/src/flags.ts`** — a typed, **default-OFF** feature-flag registry
  resolved from the environment with a strict `=== 'true'` parse, so an unset / unknown / malformed value
  can never silently enable a feature. Reference flag `newGreeting` → `FEATURE_NEW_GREETING`.
- **`GET /greeting`** reference endpoint whose body flips on the flag (`Hello, world!` ↔ `Hello, world! (new)`).
- **`docs/operations/feature-flags.md`** — flag lifecycle (add → dark-launch → enable → **retire**),
  kill-switch vs rollback, and the honesty note: an env flag is dark-launch + restart-to-toggle, **not** a
  live runtime flip (that needs a dynamic/managed provider). Cross-linked from `progressive-delivery.md`.
- **`conformance/feature-flags-wired.sh`** — kit-side behaviour lock (the registry + endpoint + flag-aware
  smoke + the golden-path two-boot flip are wired; comment-stripped so inert tokens can't satisfy it).
- **`conformance/feature-flags-ready.sh`** — adopter-facing conditional: a project with a feature-flag
  surface must document the kill-switch toggle + retirement ritual; N/A (skip-pass) otherwise.
  Declaration-only and fail-closed by presence.

### Changed
- **`profiles/typescript-node/scaffold/scripts/smoke.sh`** is now a runnable, flag-aware kill-switch proof
  (liveness + a two-sided `/greeting` assertion) — and the `golden-path` workflow now **runs it**, booting the
  reference image twice (flag OFF → kill-switch greeting; flag ON → new greeting) to prove the flip
  end-to-end. Closes the "smoke wired into CI" gap-item: `smoke.sh` previously never executed.
- Headline conformance claims: **23 → 25**.

## [3.40.0] — 2026-06-22

**R4 — honesty & staleness fixes (RETEST-2 fix-forward, final slice).** Three small corrections the
second cold-adopter run surfaced. Completes the RETEST-2 fix-forward arc (R1–R4).

### Fixed
- **`conformance/dr-ready.sh` no longer over-claims "RECORDED" for an unrun drill.** It only caught the
  literal `[date]` placeholder, so an honest `Restore verified: not yet executed` PASSED. It now also FAILs
  when the `Restore verified:` line says the drill is not-yet-run (not yet / pending / scheduled / tbd / todo
  / n-a / none) or records no date (a 4-digit year). New `--selftest` "unrun" fixture locks it. (Tightens a
  safety gate — the safe direction.)
- **`docs/operations/runtime-guards.md`** — the `KIT_GUARD_SELFEDIT` workaround now states the **inline**
  `KIT_GUARD_SELFEDIT=1 <cmd>` form does **not** work (the PreToolUse hook runs in its own process before the
  command); export it in the launching shell or via a `.claude/settings.json` `env` block (verified: an `env`
  block is visible to hook subprocesses).
- **`.gitignore` + `docs/adoption/brownfield.md`** — document the superpowers spec-path collision: the
  harness defaults to writing specs under the kit-`.gitignore`d `docs/superpowers/`, so a combined-framework
  adopter's `git add` silently no-ops. Guidance: keep tracked design docs under `docs/architecture/`.

## [3.39.0] — 2026-06-22

**R3 — adopter-scoped posture + committable source (RETEST-2 fix-forward).** The second cold-adopter run
found two adopter-experience bugs: the adopter-facing `doctor` reported **POSTURE: FAIL by construction**
after `incept` (two kit-*self* conformance checks fail in an adopter repo), and the shipped root
`.gitignore` ignored `/src/ /test/` so an adopter's source was **silently un-committable**.

### Fixed
- **Kit-self conformance checks self-skip outside the kit repo.** `conformance/ci-selftest-coverage.sh`
  (asserts the kit's own CI wires every checker) and `conformance/adopter-export-wired.sh` (verifies the
  kit's own export mechanism) now print `N/A` and exit 0 when run in an adopter project, so `doctor`/`verify`
  no longer show FAIL on checks with no adopter meaning. Detection is **fail-closed**: it N/A-skips only when
  *both* `docs/ROADMAP-KIT.md` **and** the control-plane-protected, export-ignored `.github/workflows/golden-path.yml`
  are absent — so deleting the (unprotected) backlog marker alone can't make the kit skip its own checks.
- **`scripts/adopter-export.sh` strips `/src/` and `/test/` from the exported `.gitignore`** (exact-line, idempotent;
  the kit's own `.gitignore` is untouched), so a generated-profile adopter can commit their source.

### Notes
- Bounded scope: only the two empirically-failing kit-self checks self-skip; the full conformance-carve
  (relocating all kit-self checks) remains deferred. A plain-`git clone` adopter (vs. `adopter-export`) still
  carries the markers and runs the checks — documented ceiling.

## [3.38.0] — 2026-06-22

**R2 — agent-boundary honesty patch (RETEST-2 fix-forward).** The second cold-adopter run found the kit's
headline "humans ratify via code-owner approval" control is, in the **single-maintainer + agent-authored-PR**
configuration the kit otherwise prescribes, both **bypassable** and **unsatisfiable** — and the docs didn't
say so. Documentation-only; the *gated* fix (a separate author identity so author ≠ approver) is deferred to
the E-series containment work (E4).

### Changed
- **`AGENTS.md`** — the agent boundary now states the guard sees only **local** git, not a server-side
  `gh pr merge --admin`; so the agent **prepares the green PR and hands the human the merge command**, and
  admin-merges only on an explicit instruction.
- **`docs/operations/runtime-guards.md`** — "Honesty boundary" now notes the git surfaces act locally; a
  server-side `gh pr merge --admin` (a GitHub API call) is outside the guard's reach — the boundary on *who
  merges* is branch protection + agent discipline, not the guard.
- **`docs/operations/review-lane.md`** — new "Solo + agent-authored PRs" caveats: (1) admin-merge is an
  audit-trailed **convention, not a kit-enforced gate**; (2) requiring code-owner review while the sole owner
  is the sole code owner is **structurally unsatisfiable** (GitHub forbids self-approval → permanent
  `BLOCKED`) — rely on required status checks + the logged admin-merge, or use a separate author identity (E4).
- **All 10 profile `BRANCH-PROTECTION.md`** — a consistent solo-track caveat so a solo adopter isn't steered
  into the code-owner trap (the team-config JSON is unchanged).

## [3.37.0] — 2026-06-22

**R1 — conformant generated profiles, behaviour-locked (RETEST-2 fix-forward).** The second cold-adopter
run (Python/FastAPI, a *generated* profile) found `scripts/new-profile.sh` emitted a stub below the kit's
own conformance bar — and it **hard-failed on the first Inception action** for any non-TypeScript stack:
it derived its CODEOWNERS/BRANCH-PROTECTION companions from `profiles/python/`, which a `--profile` export
prunes. Invisible to the kit's own CI because `profiles/python/` exists in the kit tree; it only vanishes
in the adopter's export. The generator was validated against the full tree, never executed against a real
export — the "validated piecemeal" pattern, in the generator.

### Fixed
- **`scripts/new-profile.sh` emits a *conformant* stub.** The CODEOWNERS + BRANCH-PROTECTION companions are
  now emitted **inline** (no dependency on any other `profiles/<stack>/` dir), so generation works in any
  `--profile` export. The stub `ci.yml` is conformant on creation: every `uses:` is SHA-pinned (mirroring
  the reference), secret-scan uses the checksum-verified gitleaks binary, the provenance step is now a
  separate **visibility-gated `provenance` job** (passes `provenance-precondition.sh`), the `run:` steps are
  valid-YAML block scalars, and the SBOM/dep-scan TODOs point at worked examples (incl. the Python
  `cyclonedx-bom` footgun).

### Added
- **`generator-golden-path` job in `.github/workflows/golden-path.yml`** — exports the kit
  (`--profile typescript-node`, where `profiles/python/` is absent), runs `new-profile.sh` **inside** the
  export, and asserts the generated stub is conformant (`actionlint-valid` parse · `provenance-precondition`
  · `ci-gates` · a direct per-file pin check). This *executes* the generator against a real export — the
  only test that catches the export-only class. `conformance/golden-path-wired.sh` extended to lock it.
  Honest scope: proves the generator **runs** and emits a **conformant stub**, not that a *filled* profile
  is correct.

## [3.36.1] — 2026-06-21

**S3b — adopter conformance-carve (completes the obtain fix).** After S3a, a fresh `--profile` export's
first CI push was *still* red — `claims-registry` failed on `drift-watch` + `golden-path` (their
maintainer-only workflows are export-ignored, but the claims + checks ship). Same class as S3a's fixtures
bug, newly unmasked. **And S3a's "behavioural" lock was itself piecemeal** — it checked check-links +
fixtures, not the adopter's *full* claims-registry. No new capability.

### Fixed
- **`scripts/adopter-export.sh` carves the maintainer-only claims** `drift-watch`, `golden-path`, and
  `adopter-export` from the adopter's *copy* of `conformance/claims.tsv` + `claims-registry.sh`
  (`REQUIRED_IDS`) — the kit's own registry is untouched and still requires them. (`adopter-export` is
  carved because an adopter has no reason to verify the kit's *own* export mechanism — and keeping it
  would recurse with the upgraded lock.) A fresh adopter export's `claims-registry` now passes.

### Changed
- **`conformance/adopter-export-wired.sh`** upgraded from a partial behavioural check to running the
  adopter's **full `claims-registry`** against a real export (`git init` + commit → run → assert green) —
  the "run the whole adopter CI" check that catches *any* orphaned/maintainer-only claim, not just the
  one we touched. It makes the explicit carve list self-correcting: add a maintainer-only workflow+claim
  without carving it and the kit's own CI goes red here.

## [3.36.0] — 2026-06-21

**S3a — adopter-export green (RETEST-2 fix).** A `--profile` adopter export produced a tree whose
first CI push went red, *before* Inception — caught by re-running the cold-adopter dogfood on the
shipped kit. Two real `adopter-export` defects, both the same shape: a **static** conformance check
passed in the kit's CI while the **actual exported tree** failed the adopter's CI. Fixes the defects
and upgrades the lock from static to **behavioural**. No new capability.

### Fixed
- **`--profile` prune left `docs/STACK-SELECTION.md` linking to the 9 pruned profiles** → `check-links`
  failed on the adopter's first push. `scripts/adopter-export.sh` now replaces it, on `--profile`, with
  a stub linking only to the kept selected profile (emitted via `printf '%s'` so the profile name is
  pure data — no heredoc/`sed` interpolation surface). Inbound links (README, START-HERE, the kept
  profile doc) stay valid.
- **`scripts/fixtures/` was `export-ignore`d but the adopter CI runs `tier-advice`/`agent-scorecard
  --selftest`, which need it** → those selftests failed. `.gitattributes` now ships `scripts/fixtures/`.

### Changed
- **`conformance/adopter-export-wired.sh`** strengthened from *static* link-safety to *behavioural*:
  it now runs a real `--profile` export and asserts the result is CI-green — fixtures present,
  STACK-SELECTION stubbed, and **no broken relative links in the exported tree** (an on-disk link walk;
  `check-links` needs a git repo so it can't run on a raw export). This is the E-series
  "attestation → behaviour" move applied to the export mechanism that motivated it. Claim id unchanged.

## [3.35.0] — 2026-06-21

Pre-release dogfood **S4** — the `explain` why-layer (the last S-series epic; pairs with S1). The kit
*enforces* gates well but rarely *teaches* — a newcomer learns *that* they need a threat model, not
*why*. S4 makes the rationale queryable at the moment of friction. **It adds no enforcement and waives
nothing** — the "why" is synthesized from the existing standards, single-sourced, and drift-locked.
(Backlog: `docs/ROADMAP-KIT.md` → "Strategic adoption epics".)

### Added
- **`docs/why-gates.md`** — the single source of truth for gate rationale: one browsable block per
  teachable obligation (12 topics — the S1 conditional-obligations set plus the high-value §14 floor
  gates), each naming its trigger, a 1–3 sentence *why*, the enforcing check, and a *Read more* pointer
  back to the canonical standard. Readable directly on any harness (no CLI required).
- **`scripts/explain.sh`** + the `sparkwright explain` dispatch route — a read-only, mode-blind reader
  over `why-gates.md`: `sparkwright explain <topic>` prints a block; `sparkwright explain --list`
  enumerates the topics. A missing rationale source fails cleanly (install-error, not a crash).
- **`conformance/explain-wired.sh`** — the drift-lock (claim `explain`, claims 22 → 23). Asserts the
  why-layer is wired, that **no rationale is orphaned** (every repo-path `Enforced by:` exists, and
  `..`-escaping citations are rejected), and **teaching-completeness**: every S1-checklist enforcer
  *and* every always-on floor topic is taught in `why-gates.md`. So a gate can never be added without
  its *why*, nor a *why* point at a deleted check, nor a documented topic silently vanish. Half-gated
  `--selftest` proves it fails on doc-side gaps, incept-side gaps, floor-topic gaps, orphans, and
  missing files.

### Changed
- The S1 `docs/conditional-obligations.md` checklist and the `privacy-ready` / `eval-ready` / `dr-ready`
  conformance headers now cross-link to `sparkwright explain <control>` — turning each enforced
  obligation into a launch point for understanding *why* it matters.

## [3.34.0] — 2026-06-20

Pre-release dogfood **S1** — process-weight mode (the highest-approachability-leverage S-series epic),
resolving the inverted-gradient finding for the left column. `incept --mode prototype|team|enterprise`
curates *scaffolding + surfacing* to the declared mode — **without changing a single enforced control.**
(Backlog: `docs/ROADMAP-KIT.md` → "Strategic adoption epics".)

### Added
- **`scripts/incept.sh --mode prototype|team|enterprise`** (default `team`; unknown → exit 2), recorded
  as `Process mode:` in the project `CLAUDE.md` §3. It curates scaffolding by mode: **prototype/team**
  write a trigger-named conditional-obligation checklist (`docs/conditional-obligations.md` — "threat-model
  applies IF Confidential data", never a premature `N/A`); **enterprise** proactively stamps the governance
  apparatus (`docs/governance/{THREAT-MODEL,PRIVACY-REVIEW,AI-SYSTEM-CARD,…}.md`) ready-to-fill.
- **`conformance/mode-enforcement-blind.sh`** — the keystone lock (claim `mode-blind`, claims 21 → 22):
  asserts **no gate across the enforcement surface** (conformance checks · the gating scripts · CI
  workflows · the pre-push hook) reads the stamped mode, so a mode can **never weaken an applicable
  control**. This is the durable, grep-able resolution of the standing "modular-enterprise rejected" (P2)
  tension. CI-wired.

### Notes
- **Honest scope: S1 changes NO enforcement and adds NO safety.** Every gate keys on its detected trigger
  (Dockerfile, `evals/`, data surface, classification), exactly as before — the kit's conditional-applicability
  already auto-activates each control when its trigger appears (the ratchet already existed). The mode is
  *pure friction-removal + surfacing* (what P2 prescribes); its wins are the curated newcomer experience and
  the declared mode that the S4 `--explain` layer will leverage.

## [3.33.0] — 2026-06-20

Pre-release dogfood **S3** — adopter-clean obtain / prune (second S-series epic). Gives adopters a
clean distribution via git-native `export-ignore`, instead of the vague "copy this kit" that dragged
maintainer scratch + unused stacks. Also resolves the S2-surfaced CODEOWNERS finding.
(Backlog: `docs/ROADMAP-KIT.md` → "Pre-release dogfood findings".)

### Added
- **`.gitattributes`** — marks 6 **link-safe** maintainer-only paths `export-ignore` (`docs/ROADMAP-KIT.md`,
  the two maintainer workflows `drift-watch.yml`/`golden-path.yml`, `scripts/fixtures/`, and the
  gitignored scratch dirs). Affects only `git archive` — never the kit's own tree or CI.
- **`scripts/adopter-export.sh <dest> [--profile <stack>]`** — wraps `git archive --worktree-attributes HEAD`
  (so it honors `export-ignore` and auto-excludes gitignored scratch + `node_modules`, since an archive
  is committed tracked files only) and prunes the 9 unused stack profiles. Fail-loud on archive failure
  (no silent empty-success), refuses a non-empty dest, validates `--profile` before any prune.
  A clean obtain drops **392 → 242 files** (for typescript-node).
- **`conformance/adopter-export-wired.sh`** — regression-lock (claim `adopter-export`, claims 20 → 21):
  asserts the `export-ignore` set is present, **statically link-safe** (no pruned path is a markdown-link
  target → no broken links on the adopter tree), and that the export prunes maintainer-only + unused
  profiles while keeping the adopter tree. CI-wired.

### Changed
- **`README.md`** Quickstart — honest clean-obtain flow (clone → `adopter-export.sh`), the real file
  count, and the caveat that `export-ignore` only takes effect via `git archive`/the script (a plain
  `cp -R`/clone still carries the full kit).
- **`.github/CODEOWNERS`** adapted from the `@your-org` reference template to the kit's real owner
  `@SeaBrad72` (the S2-surfaced finding). The `profiles/<stack>/CODEOWNERS` templates keep `@your-org`
  (adopter-facing; incept warns + S2 re-checks them).

### Notes
- **Deliberately deferred** (its own slice): pruning the kit-self `conformance/` suite (~75 files) — it
  would need `verify.sh` skip-missing tolerance (a safety hazard) + a 75-file triage. Three small
  maintainer docs (`MAINTAINING.md`/`CHANGELOG.md`/`WALKTHROUGH.md`) remain in the distribution because
  they are markdown-link targets from kept docs.

## [3.32.0] — 2026-06-20

Pre-release dogfood **S2** — adopter-environment preflight (the first S-series strategic epic).
Surfaces three late/cryptic GitHub-environment problems *at preflight time* so a newcomer sees them
clearly here, not as a cryptic failure later. Advisory (WARN-only) — never changes preflight's exit code.
(Backlog: `docs/ROADMAP-KIT.md` → "Pre-release dogfood findings".)

### Added
- **`scripts/preflight.sh`** gains an auto-activated "Adopter environment" section (only inside a
  `github.com` git repo) with three advisory checks: (a) **repo class** — warns when the repo is
  user-owned **private**, where the SLSA provenance gate silently skips (make it public/org for build
  attestation); (b) **CODEOWNERS** — a *standing* re-check for lingering `@your-org` placeholders
  (incept warns only once, at inception); (c) **workflow validity** — reuses
  `conformance/actionlint-valid.sh` to flag an invalid reference workflow *when an `actionlint` binary is
  already available locally* (preflight deliberately does not trigger a download at preflight time). Each
  check degrades to an honest `skip — <reason>` when `gh`/`actionlint`/network is unavailable. The accumulated advisory count is
  now displayed as a non-blocking "N advisory warning(s)" summary.
- **`conformance/adopter-preflight-wired.sh`** — a regression-lock (registered claim `adopter-preflight`,
  claims 19 → 20) asserting the section is wired and stays advisory (a warn never sets `miss`). CI-wired.

### Notes
- This is **reuse + surface + detect-actual-environment**, not three new validators: it complements the
  kit-side/one-shot checks already shipped (G1 `actionlint-valid`, G7 `provenance-precondition`, G11
  incept CODEOWNERS warning) with an adopter-side, standing, environment-aware view.

## [3.31.0] — 2026-06-20

Pre-release dogfood **G2** — golden-path end-to-end execution harness (the headline meta-fix).
Closes the G-series at **13 of 14** (G8 consciously deferred).
(Backlog: `docs/ROADMAP-KIT.md` → "Pre-release dogfood findings".)

### Added
- **`.github/workflows/golden-path.yml`** — a path-filtered/weekly/dispatch CI job that scaffolds a
  temp ts-node adopter project and **runs the reference artifacts end-to-end**: the npm pipeline
  (`npm ci` → lint → type-check → test+coverage → build), `docker build` of the reference Dockerfile
  (staged into the build context — incept leaves it COPY-&-ADAPT), and a `/healthz` liveness check
  that asserts the `{"status":"ok"}` body. This is the kit's first heavy integration job; it
  retroactively *executes* the G4/G6/G10/G12 fixes that were previously validated only piecemeal —
  closing the dogfood's one root cause ("artifacts validated piecemeal, never run end-to-end").
- **`conformance/golden-path-wired.sh`** — a regression-lock (registered claim, claims 18→19) that
  the harness stays wired (npm/docker-build/Dockerfile-stage/`/healthz` steps + path/schedule/dispatch
  triggers); `--selftest` red-greens.

### Notes
- **Honest split:** the lock proves the harness is *wired* on every PR; the harness *executes* on
  profile-change / weekly / dispatch (and on its own introducing PR). **Documented residuals:** it runs
  the workflow's *commands*, not the GHA *engine* (no `act`; `actionlint` validates the YAML statically);
  and it does not exercise registry-push SLSA provenance (no registry — logic gated by G7).

## [3.30.0] — 2026-06-20

Pre-release dogfood **G8 deferred** — documented the guard's over-deny (false-positive) ceiling.
(Backlog: `docs/ROADMAP-KIT.md` → "Pre-release dogfood findings".)

### Changed
- **`docs/operations/runtime-guards.md` now documents the over-deny (false-positive) ceiling**
  of the control-plane shell-mutation check: it matches a control-plane path + a mutation verb
  by substring over the whole command, so it over-denies when either is mentioned in *prose*
  (commit message, `--body`, heredoc, `grep` pattern) — the guard failing *safe*. Workarounds:
  the `!` user-shell escape, the Read tool, or `KIT_GUARD_SELFEDIT=1` in the launching shell.
- **G8 marked deferred** in the roadmap with full rationale: a narrow fix was built but the
  mandatory dual security-review of the scratch caught confirmed bypasses (whole-string `-b`
  negative; lost `install` wrapper coverage). Root cause = whole-command substring matching;
  the real fix is **per-segment** command parsing, a deliberate larger slice with its own
  security pass. Deferred because the FP fails safe and the real backstop is the PR
  `gate-agent-boundary`. No guard behavior changed.

## [3.29.0] — 2026-06-20

Pre-release dogfood **G11** — `incept` warns on `@your-org` CODEOWNERS placeholders.
(Backlog: `docs/ROADMAP-KIT.md` → "Pre-release dogfood findings".)

### Fixed
- **`incept` now warns when it writes a CODEOWNERS that still contains `@your-org/*`
  placeholder teams** — these block every merge once `require_code_owner_reviews` is
  enabled (the placeholder owners don't exist). The warning (to stderr, exit-0-preserving)
  names the file and points to `docs/operations/review-lane.md`. Placeholders are left
  intact as fill-me-in markers (incept's `--intent-owner` is a human name, not a GitHub
  `@org/team`, so there is no valid value to substitute — WARN is the honest fix).

## [3.28.0] — 2026-06-20

Pre-release dogfood **G13** — honesty wording + harness-parse tolerance. Two Low fixes.
(Backlog: `docs/ROADMAP-KIT.md` → "Pre-release dogfood findings".)

### Changed
- **Scaffold READMEs no longer over-promise.** "Verified green with the real npm pipeline" →
  the npm steps were **run green locally**; the workflow file is statically validated
  (`actionlint`); the full pipeline's first real run is the adopter's first push to GitHub
  (the reference `ci.yml` was never executed as a GHA document — the root of G1).

### Fixed
- **`conformance/inception-done.sh` tolerates a trailing period/space** in the stamped
  `Target harness(es)` value — `claude-code.` now resolves to `adapters/claude-code` instead
  of failing the Inception-Done gate. Each harness token is stripped of trailing
  punctuation/whitespace before the adapter lookup.

## [3.27.0] — 2026-06-20

Pre-release dogfood **G14** — secrets-for-AI playbook + the "running the live eval is a
human/CI step" boundary. Pure docs (closes the last Low-severity G-finding).
(Backlog: `docs/ROADMAP-KIT.md` → "Pre-release dogfood findings".)

### Added
- **`docs/operations/secrets-for-ai.md`** — an adopter inner-loop playbook for the secret
  friction the dogfood hit hardest: set CI secrets from a file (never hand-paste), don't
  rotate the key mid-loop, don't select the key in-editor, and `.env` is the local floor
  (→ `secrets-at-scale.md` for the managed-store story). Indexed in `START-HERE.md` + the
  `CLAUDE.md` doc table.

### Changed
- **Eval-driven-dev guidance now states the live-eval handoff.** `DEVELOPMENT-STANDARDS.md`
  §AI Evaluations and `conformance/eval-readiness.md` note that running the eval against the
  **real provider** is a human/CI step (policy) — the agent authors and wires the evals but
  the guard's secret-read deny blocks reading a live key *file* into context as a **speed
  bump, not a hard boundary** (an already-exported env var or the interpreter channel is not
  mechanically stopped; the human/CI handoff is the actual control).

## [3.26.0] — 2026-06-20

Pre-release dogfood **CI cluster G6 · G7 · G9** — control-plane fixes to the reference pipelines.
(Backlog: `docs/ROADMAP-KIT.md` → "Pre-release dogfood findings".)

### Fixed
- **G7 — SLSA provenance jobs no longer red a user-owned private repo's `main`.** GitHub's
  attestations API is unavailable on user-owned **private** repos (the most common solo-adopter config),
  so the ungated `provenance` / `image-provenance` jobs failed on first merge with no in-repo explanation.
  Each provenance job-`if:` across **all 10 profiles** is now gated on
  `github.event.repository.private == false || …owner.type == 'Organization'` — full strength on public
  or org-owned repos (attestations work there, including private org repos), skipped on user-owned private.
  A `NOTE` in the typescript-node reference explains the precondition. Locked by the new
  `conformance/provenance-precondition.sh` (asserts **each** provenance job-`if:` carries the guard —
  per-condition, so a half-gated profile can't slip through; claims registry → 18).
- **G9 — semgrep SAST gate pinned off `--config auto`.** `auto` resolves a different registry ruleset
  per environment (a flaky required gate that flagged the kit's own guard locally but not in CI); the
  ts-node profile now pins `--config p/default` (`--error` preserved, so findings still fail the gate).

### Added
- **G6 — opt-in Postgres for DB-backed integration tests** in the typescript-node `ci.yml`: a commented,
  inert `services: postgres` block (the default archetype is a DB-backed service, but the reference CI
  shipped no database). Uncomment to give integration tests a real DB; documents that `prisma generate`
  must precede type-check/build and `migrate deploy` precede the tests.

**Honest ceiling (G7):** the gate uses verified GitHub context fields, but a workflow `if:`'s runtime
skip-behavior can't be unit-tested without a real event — `provenance-precondition.sh` is a *structural*
lock; full runtime validation rides on the living-reference adopter run (and the G2 golden-path CI).

## [3.25.0] — 2026-06-20

Pre-release dogfood fixes **G4 · G5 · G10 · G12** — a batch of `profiles/` (agent-editable) reference
fixes the feedback-triage stress test surfaced. (Backlog: `docs/ROADMAP-KIT.md` → "Pre-release dogfood
findings".)

### Fixed
- **G4 — reference `Dockerfile` is now Prisma-ready** (Prisma is the profile's recommended ORM). Added a
  conditional `prisma generate` *before* `npm run build` (as an `if/then/else` so a generate **failure**
  aborts the build rather than shipping an image with no client) plus a `binaryTargets` note: the runtime
  is distroless-debian13 (trixie) while the builder is bookworm, so `schema.prisma` must declare engine
  targets covering the runtime or the image builds then crashes on first query. No-op for non-Prisma apps.
- **G5 — an incepted project no longer silently un-tracks its own app source.** A kit-obtained project can
  inherit a `.gitignore` that ignores `/src/` `/test/` (the kit's maintainer scratch), and `incept` only
  *appends* the scaffold's ignore rules — so the scaffold's `src/test` stayed ignored and never reached CI.
  The scaffold `.gitignore` now appends `!/src/` `!/test/` to force them tracked (verified: both stage
  despite an inherited ignore). *(A universal `incept`-level strip remains an optional stronger follow-up.)*
- **G10 — scaffold `vitest` bumped `^2.1.0` → `^4.0.0`** (resolves 4.1.9) across both the service and CLI
  scaffolds, clearing the known high/critical advisories. Full green-on-clone pipeline holds (lint →
  type-check → test:coverage → build, 100% coverage) and `npm audit --omit=dev --audit-level=high` is clean;
  no vitest.config migration needed.

### Added
- **G12 — runnable smoke + DR-drill stubs for the service archetype** (`profiles/typescript-node/scaffold/
  scripts/`). `smoke.sh` — post-deploy healthz + core-flow curl, `BASE_URL`-configurable, fails non-zero on
  any bad check (wired as `npm run smoke`). `dr-drill.sh` — a Postgres backup/restore drill that `pg_dump`s
  the source, restores into an **isolated** scratch DB, verifies row-count + a null-safe all-column checksum
  (`concat_ws`/`coalesce`, never bare `||`), then drops the scratch DB + scrubs the dump. **Fail-closed**:
  three guards make it impossible to drop the source or a real DB (scratch must differ from source, must not
  be a protected name, and must end `_restore_drill`); every DB name comes from a `-d` flag, never the URL.

## [3.24.0] — 2026-06-20

Pre-release dogfood fix **G3** — the kit's conformance **detectors** now fire on the kit's **own
template format**. The feedback-triage stress test found governance gates that *silently skipped*
(returned N/A) a project declaring sensitive/agentic/AI data exactly as the templates instruct — a
Confidential project bypassing its own DPIA gate, the worst kind of gap (the gate looks satisfied).
(Backlog: `docs/ROADMAP-KIT.md` → "Pre-release dogfood findings" G3.)

### Fixed
- **`privacy-ready.sh` silently skipped a Confidential declaration.** It grepped `data classification:`
  (colon-adjacent), but the PROJECT-CLAUDE template emits `**Data classification** (§privacy): Confidential`
  (colon after the parenthetical) → never matched → a Confidential project bypassed its privacy review.
  Now matches `data classification[^:]*:` and tests the **post-colon value** (so an annotation mentioning
  "confidential" on a line whose value is Internal no longer false-triggers).
- **`agentops-ready.sh` silently skipped an agentic declaration.** It anchored `^…agentic: yes`, but the
  template's marker was mid-line prose. `is_agentic` is restructured to a structured-field detector
  (field-leading, `[yes / no]` placeholder-skip, post-colon whole-word `yes` value) — fires on the new
  field and the legacy forms without over-triggering on a `no` value whose annotation contains "yes".
- **`eval-ready.sh` / `responsible-ai-ready.sh` missed `docs/sign-offs/`.** The AI-System-Card and Eval-Plan
  templates recommend storing artifacts under `docs/sign-offs/`, but the detectors only probed hardcoded
  root/`docs/`/`evals/` paths → an AI feature was reported as having no governance. `docs/sign-offs/` added
  to both the is-AI-feature detection and the artifact-locate functions.

### Changed
- **PROJECT-CLAUDE template** — the prose `Agent-ops *(if agentic)*: set \`Agentic: yes\`` instruction
  became a structured fillable field `- **Agentic** *(does this project run autonomous agents?)*: [yes / no]`,
  mirroring the Data-classification field so the detector can match a filled value (and skip the placeholder).

### Added
- **`conformance/template-detectors-aligned.sh`** — a meta-lock that stamps a fixture project using the
  templates' **own** declaration format (Confidential + agentic + an AI System Card under `docs/sign-offs/`)
  and asserts every detector **fires** (never silent-skips), plus a drift guard that the template's field
  markers still exist. Red-first on the old detectors, green after the fix. Wired into CI + registered as
  the `template-detectors-aligned` claim (claims registry → 17). Stops the kit's format drifting from its
  own regexes — the privacy/agentops analogue of `actionlint-valid`.

## [3.23.0] — 2026-06-20

Pre-release dogfood fix **G1** — the reference CI pipelines are now validated as **GitHub Actions
documents**, not just as npm steps. The feedback-triage adopter stress test surfaced that the shipped
`ci.yml` workflows were never executed end-to-end on GitHub Actions; this closes the first defect class
kit-wide. (Backlog: `docs/ROADMAP-KIT.md` → "Pre-release dogfood findings" G1.)

### Fixed
- **Invalid GHA document — `hashFiles()` in a job-level `if:`** (the `image-provenance` job) made the
  workflow fail at startup on a real push with no jobs scheduled. Fixed across **all 7 affected profiles**
  (dotnet, go, java-spring, kotlin, python, rust, typescript-node) by computing a `has_dockerfile` job
  output (a `Detect Dockerfile` step after checkout) and gating the job on
  `needs.ci.outputs.has_dockerfile == 'true'`. The legal step-context `hashFiles()` uses are unchanged.
- **Secret-scan gate (all 10 profiles)** switched from `gitleaks-action` (commit-range mode — failed with
  "Invalid revision range" on PR merge-refs and required `pull-requests: read`) to a **checksum-pinned
  `gitleaks dir .`** run step (gitleaks v8.24.3, `sha256` verified, fail-closed). Range-independent,
  scans the full committed tree, makes no API call (least-privilege: `contents: read` suffices). The
  `gate-secret-scan` id is retained (ci-gates parity). *Honest ceiling:* a working-tree scan does not
  cover secrets that existed only in removed git history — rotate on any past exposure.
- **Shell-injection — `${{ github.base_ref }}` spliced into a `run:`** (the "Compute changed files" step)
  fixed via `env: BASE_REF` indirection in `profiles/typescript-node/ci.yml` and the kit's own
  `.github/workflows/ci.yml`.

### Added
- **`conformance/actionlint-valid.sh`** — validates every shipped GHA workflow (`.github/workflows/*.yml`
  + every `profiles/*/ci.yml`) as a real GitHub Actions **document** (actionlint v1.7.7, checksum-pinned
  per-platform, document-validity only via `-shellcheck=`). Wired into the kit's conformance CI job with
  a `--selftest` (the selftest reproduces the exact `hashFiles`-in-job-`if` defect class), and registered
  as the `actionlint-valid` claim (claims registry → 16). This is the regression lock that would have
  caught the defect class before it shipped.

## [3.22.0] — 2026-06-19

### Added
- **typescript-node CLI archetype reference** (`profiles/typescript-node/scaffold-cli/`) — a verified,
  green-on-clone non-service starter (`app [--name <name>]`) proving the ts-node CI contract holds for a
  CLI shape, not just `/healthz` services. Conformance-locked via `profile-completeness.sh`. Not
  auto-incepted (a COPY-&-ADAPT reference; incept's default stays the service scaffold).

### Changed
- **Honesty fix:** `docs/STACK-SELECTION.md` no longer claims `incept` copies `compose.yaml` — it is a
  COPY-&-ADAPT reference (auto-copying would break green-on-clone). Added an archetype-coverage note.

## [3.21.0] — 2026-06-19

### Added
- **Named harness adapters** `codex`, `cursor`, `gemini` — first-class floor-only adapters beyond
  `generic`, each conformance-locked by `conformance/named-adapters.sh` (claims registry → 15) and
  declaring its own control surface (`.cursor/rules/`, `GEMINI.md`/`.gemini/`) so the agent-boundary
  gate protects the union across all harnesses in a shared repo. Floor-only by honest necessity (no
  third-party native inline guard); live cross-harness behavior is adopter-verified, not maintainer-claimed.

### Changed
- Corrected the "verified second harness" roadmap wording to the honest maintainer- vs adopter-verified split.

## [3.20.0] — 2026-06-19

### Added
- **`sparkwright tier-advice`** — a read-only autonomy-tier **decision view** (P3 operate-loop Slice 2).
  Composes `agent-scorecard.sh`'s already-emitted directives into a human-facing list of pending
  tier recommendations + the asymmetric human-ratified apply path (auto-downgrade = fail-safe, no
  ratification; raise = route to the Security owner, §13), with DORA shown as labeled delivery-health
  context (never a tier input). Emits, never actuates. Wired into the `sparkwright` dispatcher and
  the guard control-plane named-set; locked by `conformance/tier-advice-wired.sh` (claims registry → 14).

## [3.19.0] - 2026-06-19

**MINOR** — operate-loop Slice 1: `sparkwright postmortem` stub generator + action-item parser + `docs/operations/operate-loop.md` reference. Control-plane slice; additive; no control weakened.

### Added
- **`scripts/postmortem.sh`** (`sparkwright postmortem`) — two modes: `new --id --severity --title [--commander --date --out]` scaffolds a postmortem stub from incident metadata (reads `templates/POSTMORTEM-TEMPLATE.md`, substitutes header placeholders, writes `postmortems/<ID>.md`; no-clobber); `to-backlog <file>` parses the `## 7. Action items` table and emits backlog Ready-row stubs to stdout (skips header, separator, blank, and placeholder rows). `--selftest` (T1–T6): row parsing, ID presence, placeholder-skip, no-clobber, missing-file error, `&`/`/` literal preservation. POSIX sh; dash-clean; awk-based substitution avoids sed-delimiter collisions.
- **`docs/operations/operate-loop.md`** — the reference: the closed loop (incident → `sparkwright postmortem new` → human-authored analysis → `to-backlog` → human review + tracker actuation); both modes explained; known limitation (literal `|` in action cell truncates); governance ties to `DEVELOPMENT-STANDARDS.md` §15, `CLAUDE.md` principle 6, `DEVELOPMENT-PROCESS.md` §6/§15; honest ceiling stated; Slice 2 context.
- **`conformance/operate-loop-wired.sh`** — regression-lock: fails CI if `scripts/postmortem.sh` is removed or `--selftest` stops passing; verifies the dispatcher routes `sparkwright postmortem`. Registered `operate-loop` claim → **13 claims total**.

### Changed
- **`scripts/sparkwright`** (dispatcher) — gains the `postmortem` route (`sparkwright postmortem` → `postmortem.sh`).
- **`scripts/postmortem.sh`** — added to the guard's control-plane named-set; an unratified edit is denied by the guard and flagged by the `agent-boundary` CI gate.
- **CI** (`.github/workflows/ci.yml`) — wires `postmortem.sh --selftest` + `conformance/operate-loop-wired.sh` into the conformance sweep.
- **`docs/ROADMAP-KIT.md`** — "Close the operate loop" bullet split: Slice 1 marked ✅ shipped 3.19.0 with the honest scope (generate + parse the mechanizable edges; human-ratified; never-actuate); Slice 2 (DORA + scorecard → tier RECOMMENDATION, human-ratified apply) noted as remaining; "auto-postmortem stub → backlog item" wording corrected to the honest state.

### Honest ceiling
Scaffolds + parses the mechanizable edges of the postmortem lifecycle. No incident auto-detection (the kit's never-actuate principle); no live-tracker auto-creation (human reviews the emitted stubs and actuates in their tracker). The judgment work — analysis, ratification, tracker actuation — is human-owned. Closes operate-loop Slice 1 of 2. Control-plane protection resists the agent it governs; ratification required to change governance tooling. Plan: docs/superpowers/plans/2026-06-19-operate-loop-incident-postmortem-backlog.md

## [3.18.0] - 2026-06-19

**MINOR** — P3 `sparkwright doctor`: adopter-facing POSTURE command + `doctor.md` reference + H3c fold-in closed. Control-plane slice; additive; no control weakened.

### Added
- **`scripts/doctor.sh`** — the posture command. Composes `conformance/verify.sh` (GATING) + `conformance/claims-registry.sh` (GATING) + an inline git ground-truth dimension (ADVISORY/WARN-only) into one sweep. `--full` appends `dora.sh` + `agent-scorecard.sh` as an INFORMATIONAL metrics section (labelled *"does not affect exit"*; never changes exit code). `--require` / `$CI` auto-tightens UNVERIFIED to exit 1. Missing composed script → UNVERIFIED, never a false PASS. `--selftest` stubs the composed commands and verifies render contract + exit-code logic.
- **`scripts/sparkwright`** — thin dispatcher (`sparkwright doctor` → `doctor.sh`). Entry point for adopters; built for future subcommands.
- **`docs/operations/doctor.md`** — the reference: what doctor composes; the posture (gating) vs metrics (informational, never gates) split and why (DORA and agentic-ops are measurement tools — metrics measure, they don't gate); git ground-truth as an advisory dimension; graceful degradation (missing check → UNVERIFIED/N/A, never a false pass); invocation and flags; honest ceiling (automates D/E, not semantic drift; green doctor ≠ correct project); control-plane protection.
- **`conformance/doctor-wired.sh`** — regression-lock: fails CI if `scripts/doctor.sh` or `scripts/sparkwright` is removed or `--selftest` stops passing. Registered `doctor` claim → **12 claims total**.

### Changed
- **`scripts/doctor.sh` + `scripts/sparkwright`** — added to the guard's control-plane named-set; an unratified edit is denied by the guard and flagged by the `agent-boundary` CI gate.
- **`docs/operations/drift-self-check.md`** — the "folds into P3 / planned to automate" note (H3c) closed: the mechanizable axes (D claim-integrity, E git ground-truth) are now automated by `sparkwright doctor`; link added. Semantic axes (A/B/C + judgment half of D) remain agent/human.
- **`docs/ROADMAP-KIT.md`** — `sparkwright doctor` P3 bullet marked ✅ shipped 3.18.0; doctor's delivered scope described; 12-claim total recorded.

### Honest ceiling
Posture dimensions gate; metrics (DORA, agent-scorecard) are informational and never gate — the principle is "metrics measure, they don't gate." Doctor automates the mechanizable drift axes (D claim-integrity, E git ground-truth); it does NOT detect semantic drift (intent, scope, overclaim judgment) — that remains the agent/human checkpoint in `drift-self-check.md`. A green `sparkwright doctor` does not mean "the project is correct." Control-plane protection resists the agent it governs; ratification required to change governance tooling. Plan: docs/superpowers/plans/2026-06-19-p3-sparkwright-doctor.md

## [3.17.0] - 2026-06-19

**MINOR** — batched hardening follow-ups: **secret-write parity + cost-governance metered trigger.** Two tracked follow-ups from H3a and H3b shipped together. Control-plane slice; additive; no control weakened.

### Changed
- **`guard_check_path` secret-WRITE deny** (`.claude/hooks/guard-core.sh`) — broadened to mirror `guard_check_read`: now enumerates the same `.env.<suffix>` set (`.env*`, `.pem`, `.key`, `id_rsa`, `secrets/`) with the matched template allow-list (`.env.example`/`.sample`/`.template`/`.dist`), closing the read/write parity gap for secret-material enumeration. Regression cases added to `conformance/agent-autonomy.sh`.
- **`conformance/cost-governance-ready.sh`** — applicability now triggers on a metered-LLM/AI feature (an `evals/` dir, a filled AI System Card, or `Agentic: yes` in the project `CLAUDE.md`) in addition to a deploy surface (Dockerfile/workflow), so a metered LLM CLI with no deploy surface no longer silently escapes to N/A. New selftest fixtures cover the LLM-feature trigger path.
- **`docs/operations/runtime-guards.md`** · **`docs/operations/cost-governance.md`** · **`docs/ROADMAP-KIT.md`** — follow-up bullets closed; parity and applicability change documented.

### Honest ceiling
Secret-material parity is specifically about the enumeration in `guard_check_path`/`guard_check_read` — the control-plane read⊊write asymmetry (H3a: `guard_check_read` does not deny control-plane reads) is unchanged. The cost-governance N/A escape remains valid for genuinely-unmetered projects (offline computation, no LLM calls). Plan: docs/superpowers/plans/2026-06-18-batched-followups.md

## [3.16.0] - 2026-06-18

**MINOR** — H4a of the Tier-4 coverage gaps: **GitLab governance parity (honest-scope, doc-first).** Consolidates the manual wiring for GitLab branch-protection, control-plane-ratification, and DORA into a single adopter guide; locks the guide's completeness with a drift-guard conformance check. **H4 complete (H4a + H4b).** Control-plane slice; additive; no control weakened.

### Added
- **`docs/operations/gitlab-adoption.md`** — adopter guide covering three governance areas: (1) branch-protection settings (UI walkthrough for the four recommended rules), (2) control-plane-ratification keystone (MR-approval wired as the non-author-review equivalent via `CODEOWNERS` + a protected approval rule), (3) DORA (pipeline-level instrumentation pattern). Honest ceiling stated: GitLab governance is adopter-owned and UNVERIFIED by the kit's automated conformance; enforcement lives in the adopter's GitLab instance, not in the kit's CI.
- **`conformance/gitlab-adoption-complete.sh`** — drift-guard: fails if any of the three required sections disappear from `gitlab-adoption.md` or if the GitLab profile's cross-link to the guide is removed. Registered claim → 11 claims total. Selftest: a stub file missing a section fails; the real guide passes.

### Changed
- **`profiles/typescript-node/ci.gitlab-ci.yml`** (profile note) — now includes a cross-link to `docs/operations/gitlab-adoption.md` for GitLab-specific governance wiring.
- **`docs/operations/ci-platforms.md`** — cross-link added pointing to `gitlab-adoption.md` for GitLab adopters.
- **`docs/ROADMAP-KIT.md`** — H4a ✅ shipped 3.16.0; deliberate non-scope decisions recorded; **H4 complete**; next → P3.

### Honest ceiling
GitLab governance (branch-protection enforcement, MR-approval ratification, DORA metrics) is **adopter-owned / UNVERIFIED** off GitHub. The kit deliberately did NOT build an automated GitLab branch-protection API check (would require a live GitLab instance — untestable = the over-claim trap; also reverses the "out of scope, adopter-owned" decision in `ci-platforms.md`) nor an MR-approval ratification gate (same untestable-without-live-instance reason). Both remain adopter-owned. Design: `docs/superpowers/specs/2026-06-18-h4a-gitlab-governance-parity-design.md`.

## [3.15.0] - 2026-06-18

**MINOR** — H4b of the Tier-4 coverage gaps: **kit's own tool supply chain (pin + verify).** Sequenced first in H4 (the trust root: a compromised tool can make any gate falsely pass). Corrects the stale "all unpinned/unverified" claim with the verified state and closes the real gaps. **Control-plane slice; additive; no control weakened.**

### Added
- **`conformance/supply-chain-verify.sh`** — a regression-lock: fails CI if the GitLab profile's tool installs reintroduce a `curl … | sh` pipe-to-shell or drop a `sha256sum -c` verify. Selftest (a tampered `curl|sh` fixture fails; the real profile passes); registered as a `supply-chain-verify` claim (+ `REQUIRED_IDS`), CI-wired, indexed in `conformance/README.md`.
- **`docs/operations/tool-supply-chain.md`** — the kit's tool trust model across three classes (SHA-pinned Actions · checksum-verified profile downloads · runner-provided tools) + the honest ceiling.

### Changed
- **`conformance/action-pinning.sh`** — now enforces SHA-pins across the kit's **own** `.github/workflows/*.yml` in addition to the canonical profile reference (closes the D1b tracked follow-up; the kit's own 4 pins were correct-but-unenforced). The `action-pinning` claim description updated accordingly.
- **`profiles/typescript-node/ci.gitlab-ci.yml`** — the syft/cosign/gitleaks installs now download each pinned version's published `*_checksums.txt` and `sha256sum -c` before exec (fail-closed via `test -s`), replacing the prior `curl … | sh`-from-`main` (syft) and no-checksum binary downloads. HARDENING header updated to the verified state.
- **`docs/ROADMAP-KIT.md`** — H4b ✅; H4a reframed to honest-scope + verifiable subset; the stale "unpinned/unverified" H4 text corrected.

### Honest ceiling
A green `action-pinning.sh` + `supply-chain-verify.sh` proves SHA-pinned Actions (kit + profile) and checksum-verified profile downloads against each pinned version's **published manifest** — **not** upstream-release integrity (the next tier is keyless cosign verify of the checksums `.sig`) nor the runner base image (`jq`/`gh`/`shellcheck` root in `ubuntu-latest`, platform-owned, out of scope — the same "enforcement is platform-owned" boundary as containment/cost-governance). Design: `docs/superpowers/specs/2026-06-18-h4b-tool-supply-chain-design.md`.

## [3.14.0] - 2026-06-18

**MINOR** — H3c of the Tier-3 agentic-risk hardening (**H3 complete**): **long-session drift self-check.** The agent's in-loop re-check *during* a long build — before any gate sees the drift — institutionalizing the verify-before-build pass that repeatedly caught this kit's own roadmap/docs over-promising. **Scope = Hybrid:** ships the **practice** now (docs-only); the **tooling** half folds into P3's `sparkwright doctor`. **Docs-only slice; agent-editable; no control-plane, no conformance gate, no control weakened.**

### Added
- **`docs/operations/drift-self-check.md`** — the reference: five drift axes (intent/scope · plan · standards · **claim-vs-reality** · context-loss), checkpoint-triggered (before review · before release · at each long-session boundary). States why it sits where it does (D1 catches *structural* drift between commits; review-lane catches it *at the gate*; this catches it *during* the build — the agent-side complement to `agentic-ops.md`'s observation), and why it deliberately ships **no conformance gate** (gating "did you self-check?" = unverifiable self-attestation = ceremony).

### Changed
- **`docs/operations/agentic-ops.md`** · **`docs/operations/review-lane.md`** — "See also" pointers: the self-check as the agent-side complement to observation, and "run it before requesting review."
- **`docs/ROADMAP-KIT.md`** — H3c ✅ (practice, docs-only) → **H3 complete**; the mechanizable half (re-run conformance · re-check claims-registry · git ground-truth) recorded as absorbed by P3's `sparkwright doctor`.

### Honest ceiling
A PreToolUse guard sees command strings, not intent — it **cannot detect semantic drift**. So H3c is a **practice/checklist, not a mechanism** (the most advisory item in H3); the honest enforcement is the practice plus the real downstream gates (independent review, CI, scheduled drift-watch). Same honesty class as review-lane's high-risk self-review: a solo human *can* skip it. Design: `docs/superpowers/specs/2026-06-18-h3c-drift-self-check-design.md`.

## [3.13.0] - 2026-06-18

**MINOR** — H3b of the Tier-3 agentic-risk hardening: **cost/token governance.** A PreToolUse guard cannot see token counts, so this is the honest two-layer model (mirroring containment): the kit ships the **contract** and references the **platform cap** as the real enforcement. **Control-plane slice; additive; no control weakened.**

### Added
- **`docs/operations/cost-governance.md`** — the reference: a per-run **budget** (token/$ ceiling) + a **stop discipline** (approach the ceiling → stop + escalate); the **platform cap** (Anthropic API usage limits / harness budget) as the real enforcement; the existing `agent-trace.sh` `cost`/`tokens` emission as the monitor (measure → compare → stop). Honest ceiling stated: declared+attested ≠ spend actually capped.
- **`templates/TASK-CONTEXT-CONTRACT-TEMPLATE.md`** — a `Budget (STOP at)` field (per-task ceiling + stop rule).
- **`templates/RUNBOOK-TEMPLATE.md`** — a `Cost governance:` attestation line (declared+attested, N/A-escapable).
- **`conformance/cost-governance-ready.sh`** — a single-aspect three-state posture check (PASS/FAIL/UNVERIFIED/N-A; escalates under CI/`--require`), a mirror of `containment-ready.sh`; registered as a `cost-governance` claim (+ `REQUIRED_IDS`), CI-wired, indexed in `conformance/README.md`.

### Review
Independent review: **APPROVE** — *a real (honest-ceiling) control, not ceremony* (the measure→compare→stop loop is coherent, with the platform cap as backstop), and it **overclaims nothing** (no artifact implies mechanical capping). Three doc-accuracy fixes folded pre-tag: corrected the monitor attribution (`agent-trace.sh`, not `agent-scorecard.sh`), the `../enterprise/` path, and the README index row.

### Honest ceiling
The guard is blind to tokens. A green check proves the posture is *declared + attested*, never that spend was capped — the cap is platform-owned (Anthropic usage limits / harness budget). The budget is a contract (process discipline), like the high-risk self-review.
- **Tracked follow-up:** `cost-governance-ready.sh` gates on a deploy surface (Dockerfile/workflow) like `containment-ready.sh`, but spend governance's natural trigger is "metered/LLM calls" — an LLM CLI with no surface escapes to N/A; refine the applicability trigger.

## [3.12.0] - 2026-06-18

**MINOR** — H3a of the Tier-3 agentic-risk hardening: **secret-in-context read guard.** The guard already blocked *writing* secret material; it now denies the agent **reading** secret material into its context — the read half of exfil (A8 family 6), where a `.env`/key reaches the model provider, logs, or a PR. **Security + control-plane slice; deny-by-default with a `KIT_GUARD_SELFEDIT` escape; no existing control weakened.**

### Added
- **`guard_check_command` secret-read block** (`.claude/hooks/guard-core.sh`) — a content-read verb (`cat`/`less`/`head`/`tail`/`grep`/`strings`/`diff`/`awk`/`sed`/`source`/`.`/… — **not** `ls`, which is metadata) targeting secret material (`.env*` incl. common `.env.<suffix>`, `.pem`, `.key`, `id_rsa`, `secrets/`) is human-gated. Harness-independent (fires via `kit-guard cmd`).
- **`guard_check_read`** (new pure function) + the **`Read`** matcher in `.claude/settings.json` + a `Read)` case in `guard.sh` — denies the **Read tool** (the agent's *default* file-read path) on secrets, but **NOT control-plane reads** (reading the guard/CI to understand it stays allowed — the read-deny ⊊ write-deny asymmetry). `.env.example`/`.sample`/`.template`/`.dist` allowed.
- **`conformance/agent-autonomy.sh`** — the secret-read red-team corpus (shell + Read-tool deny cases, template/source/control-plane allow cases); 216 cases, CI-locked.

### Changed
- **`docs/operations/runtime-guards.md`** — documents the now-five guard functions, the secret-in-context control, and its honest ceiling.

### Security review (the WS1 lesson: review the scratch before transfer)
**Two** independent security reviews of the scratch. The first found three *common, non-interpreter* shell secret-reads slipping the net (`source .env`/`. .env`, the `cat .env*` glob, and `.env.staging`/`.env.test`) — fixed (added `source`/`.` verbs, the `*` glob boundary, enumerated common secret suffixes; **no** command-wide template exclusion, so a `cat .env.example .env` multi-arg form can't suppress the deny) and regression-locked. Re-review: **PASS, safe to transfer.**

### Honest ceilings
The two read denies stop the **default** exfil-read paths (shell + Read tool), not every path: an **interpreter** (`python -c "open('.env')"`), an uncommon content-emitter, or an exotic `.env.<custom-suffix>` on the *shell* path can still read a secret; `jq`-absent leaves the Read tool allowed; non-Claude harnesses get the shell deny only (no Read tool). Real containment is platform-owned (egress allowlist + sandboxed FS).
- **Tracked follow-up:** broaden the secret-**write** deny (`guard_check_path`) to H3a's wider `.env.<suffix>` set for read/write parity.

## [3.11.0] - 2026-06-18

**MINOR** — D1b: **scheduled drift-watch (go/no-go-lite)** — completes D1. A weekly canary re-validates the kit against the live runner toolchain and re-runs the semantic claims-registry on a timer, so drift surfaces even with **no commits** (toolchain rot, quiet-period staleness). **Control-plane slice; additive; no control weakened.**

### Added
- **`.github/workflows/drift-watch.yml`** — scheduled workflow: `cron: '0 6 * * 1'` (Mon 06:00 UTC) + `workflow_dispatch`, `contents: read` (least privilege), SHA-pinned checkout. Deterministic/offline payload: `conformance/verify.sh --require` (UNVERIFIED fails) + `conformance/claims-registry.sh` + `conformance/check-links.sh`. **Fail-the-run** surfacing — drift is a real failure, so red + GitHub's cron-failure email is the correct channel (D4-consistent: unlike "ratification required", which is an awaiting-action gate). Deterministic payload means no flaky false-alarm to erode the channel.
- **`conformance/drift-watch-wired.sh`** (CI-wired) — the drift-watcher must not itself drift: asserts the workflow exists, is scheduled (+ dispatchable), and runs the full payload; `--selftest` catches a gutted workflow.

### Changed
- **`conformance/claims.tsv` + `conformance/claims-registry.sh`** — the drift-watch is **registered as a claim** (+ a `REQUIRED_IDS` entry, no silent drop), modelling D1a's intended growth: a new control → a new registered, verified claim.
- **`.github/workflows/ci.yml`** — runs `drift-watch-wired.sh --selftest`. ROADMAP D1b done / **D1 complete**; VERSION 3.11.0, badge, CHANGELOG.

### Review
Independent review: **APPROVE.** A real drift turns the scheduled run red (no `continue-on-error`/`|| true`; `--require` fails UNVERIFIED); least-privilege + pinned; the grep-based wired-check can't be false-PASSed by the comment in its own target; self-registration loop closes. One non-blocking finding folded as a **tracked follow-up**: `action-pinning.sh` scans only the profile reference, not the kit's own `.github/workflows/` — broaden it so ci.yml + drift-watch.yml pins are mechanically enforced (its own small reviewed slice, not bolted on post-review).

### Honest ceiling
A weekly re-run of the **deterministic** suite + semantic registry; networked/semantic-heavy checks (external-link liveness, staleness) are deferred — the workflow is their future home. The grep-based wired-check is structural-not-semantic (backstopped by the real scheduled run).

## [3.10.0] - 2026-06-18

**MINOR** — D1a: **claims-registry meta-check — continuous semantic-drift detection.** Structural drift was already caught continuously (badge/links/coverage); *semantic* drift — a headline factual claim that no longer matches reality — was caught only by the periodic human go/no-go. This generalises `badge-version.sh` (one claim: badge == VERSION) to a registry of N headline claims, each paired with a verifier, failing CI on drift **or** on a silently-dropped claim. **Control-plane slice; additive; no control weakened.** (D1b — a scheduled drift-watch that runs this on a timer — is a fast-follow.)

### Added
- **`conformance/claims.tsv`** — the registry (control-plane: adding/removing/weakening a claim is a ratified act): `id | claim + where stated | verifier`. Seven seed claims — six **delegate** to existing checks (badge-version, ci-selftest-coverage, doc-budget, guard-core-sourced, action-pinning, security-policy), making the registry a single *claim → proof* pane; one is the new verifier below.
- **`conformance/claims-registry.sh`** (CI-wired) — runs every verifier; fails on a drifted verifier, a **silently-dropped** headline claim (a `REQUIRED_IDS` coverage assertion — you can't quietly delete a claim's protection without a ratified edit), a duplicate id, or an empty verifier. `--selftest` covers all four.
- **`conformance/claim-gate-counts.sh`** — the new drift verifier (proves the "a number drifts" capability beyond delegation): awk-scoped to `DEVELOPMENT-STANDARDS.md` §14, it asserts the **"seven required gates"** word == the 7 enumerated table rows and **"Five … conditional"** == the 5 enumerated bullets, cross-checked against `CLAUDE.md` — so adding/removing a gate without updating the number word fails CI. Emits a distinct "check-scope problem" message (not a phantom count) if §14 is renumbered or the anchor phrase is reworded.

### Changed
- **`.github/workflows/ci.yml`** — runs both new selftests + the real registry as the drift gate.
- **`docs/ROADMAP-KIT.md`** — D1a marked shipped; D1b (scheduled drift-watch) flagged fast-follow.

### Review
Independent review (drift-robustness lens): **APPROVE.** The silent-drop promise holds with an honestly-bounded residual (weakening a verifier is gated by *ratification*, not by this script — by design); no false-PASS / missed-drift; fragility is all in the "re-verify a reworded claim" direction. Two reviewer improvements folded in pre-transfer: the §14 anchor-not-found diagnostic, and processing a final row with no trailing newline (no silent skip).

### Honest ceiling
The registry verifies **registered** claims and guards against silent drops; it does **not** auto-detect brand-new unregistered claim-like statements in docs (heuristic/noisy — deferred). Weakening a verifier is caught by ratification, not mechanically.

## [3.9.0] - 2026-06-18

**MINOR** — H2b of the Tier-2 hardening arc: **`kit-guard install-shims` — an inline command guard for non-Claude harnesses.** Codex/Cursor/Aider adopters previously had no inline command coverage (only `pre-push` + the CI floor). `install-shims` installs PATH-shims that call `kit-guard cmd` before `exec`. **Control-plane change; no control weakened.**

### Added
- **`scripts/kit-guard install-shims [--dir <d>] [--force]`** — writes a shim per curated **single-invocation** dangerous binary (`rm dd truncate shred wipefs blkdiscard mkfs dropdb psql mysql mariadb sqlite3 mongosh pg_restore redis-cli git npm yarn pnpm kubectl rsync`). Each shim reconstructs its argv, runs `kit-guard cmd`, and on allow execs the **real** binary — resolved by **device+inode identity (`-ef`)** so a symlinked/relative/duplicated shim-dir spelling can never make it re-exec itself, with a **bounded re-entry depth** circuit-breaker as a fork-bomb fail-safe. Warns when the shim dir is agent-writable (integrity needs a read-only mount — H2a).
- **`conformance/shim-coverage.sh`** (CI-wired) — proves the generated shims **deny + allow + pass through (exit/stdio) + don't recurse** (including a symlinked shim-dir case), with a fake "real" binary behind them on PATH.

### Changed
- **`docs/operations/runtime-guards.md`** — **honesty correction:** the prior claim that shims give "automatic full-matrix coverage" was wrong. A shim sees one binary's argv *after the shell parses the line*, so coverage is **single-invocation only** — blind to shell composition (pipes/redirects/chaining), absolute-path calls (`/bin/rm`), and interpreters. The full-string path remains `kit-guard cmd`; shim integrity is platform-owned (read-only mount).
- **`conformance/containment-ready.sh`** — folded the deferred H2a tidy: `has_readonly_mount_config` now also matches `.devcontainer/devcontainer.sandbox.json`.
- **`docs/ROADMAP-KIT.md`** — H2b marked shipped.

### Security review (the WS1 lesson: review the scratch before live transfer)
An independent security review of the scratch found and **BLOCKED a fork-bomb**: the first implementation resolved the real binary via logical `pwd`, which on macOS `/bin/sh` doesn't resolve symlinks, so a symlinked spelling of the default relative shim dir defeated the self-skip and the shim `exec`d itself forever. Fixed with `-ef` inode identity + the bounded depth breaker (which makes even a hypothetical `-ef`-absent shell fail **closed**, never spin); the symlink case is now regression-locked in `shim-coverage.sh`. Re-review: **PASS, safe to transfer.**

### Honest ceiling
Single-invocation only; absolute-path/interpreter/composition calls bypass it; integrity requires an agent-unwritable mount. A speed bump for the common direct-destructive-call mistake on non-Claude runtimes — not containment (platform-owned: `docs/enterprise/platform-safety-boundary.md`).

## [3.8.0] - 2026-06-18

**MINOR** — H2a of the Tier-2 hardening arc: **containment reference — ship the boundary the guard only documents.** A verify-before-build pass found most of H2.1 already shipped (the egress-allowlist NetworkPolicy landed in 11b) and that "no-egress devcontainer" is a category error for a dev inner-loop (it needs egress for package installs). Reframed to **sandbox-FS devcontainer + egress-allowlist pairing** and closed the two real gaps. **Additive reference material; no control weakened; the verified `typescript-node` path is untouched.**

### Added
- **`profiles/typescript-node/compose.yaml`** — a host-isolated **`agent` service** so the kit *dogfoods* the read-only-FS pattern it documents (it previously shipped only prose): `read_only` root, `tmpfs` scratch, **work-tree-only** mount (no `$HOME`/`~/.aws`/`~/.ssh`/`docker.sock`), `cap_drop: [ALL]`, `no-new-privileges`, `network_mode: none`, `HOME`/`npm_config_cache`→tmpfs so it actually runs read-only. **Opt-in behind `profiles: [agent]`** — a plain `docker compose up` never starts it, so the `app`/`db` dev path is byte-unchanged.
- **`profiles/typescript-node/.devcontainer/devcontainer.sandbox.json`** — the IDE sandbox variant (`--read-only`/`--tmpfs`/`--cap-drop ALL`/`--security-opt no-new-privileges`, work-tree-only `workspaceMount`).
- **`docs/operations/containment.md` §2** — concrete, copy-pasteable **AWS / GCP / Azure OIDC-federation** snippets (was prose-only): AWS IAM role trust policy (`aud` + repo/ref-pinned `sub`) + `configure-aws-credentials`; GCP Workload Identity Pool with a repo-pinned attribute-condition + `google-github-actions/auth`; Azure Federated Credential + `azure/login` — all zero-static-secret.

### Changed
- **`docs/operations/containment.md` §1** — now points to both shipped artifacts and states the **honest ceiling**: an IDE-attached container is inherently weaker than the headless `agent` service (the editor injects a writable, networked server), so the devcontainer is host-isolated but **not** no-egress; FS-sandbox and egress are separate controls — pair either with `egress-control.md` for the network layer.
- **`docs/ROADMAP-KIT.md`** — H2 split into **H2a** (✅ this release) / **H2b** (`kit-guard install-shims`, pending); "no-egress devcontainer" reframed; **P2 marked complete** and **WS4 ✅** (the deferred 3.7.0 housekeeping).

### Honest ceilings (no overclaim)
- A green `containment-ready.sh` proves *declared + attested*, **never** that the FS is truly read-only or tokens truly expire — enforcement stays platform-owned (`docs/enterprise/platform-safety-boundary.md`).
- This does **not** give the kit a new passing CI containment signal — CI runs `containment-ready.sh --selftest` only and never scans the profile. The win is an *adoptable artifact* + self-consistency (the kit now models the pattern it documents).
- **Deferred (tracked):** `containment-ready.sh::has_readonly_mount_config` scans `.devcontainer/devcontainer.json` but not the new `.sandbox.json` filename (and not `--read-only` runArgs); the `compose.yaml` `read_only: true` already provides the match for profile adopters, so this is a future one-line heuristic tidy, not a defect.

## [3.7.0] - 2026-06-18

**MINOR** — P2/WS4 of the usability-governance milestone (the **last P2 slice**): **persona routing**. Non-engineer personas now find their entry at the front door, and interactive `incept` prompts operator-fluency. **Surface/route only — nothing deleted, no gate disabled, no applicable control weakened**; the routing copy explicitly *reinforces* gate universality ("rigor is carried, not waived").

### Added
- **`ONBOARDING.md`** — a "**Which role are you?**" section: a thin persona-routing table (Product Owner/BA · Designer · QA Engineer · Security Owner · DevOps/SRE · Engineer) mapping each to where it plugs into the loop and its entry → exit artifact, pointing to the authoritative function map (`DEVELOPMENT-PROCESS.md` §2) rather than copying it (drift-safe). A "**the rigor is carried, not waived**" note makes explicit that a non-builder is routed to *their own* additional bar (testable acceptance criteria, a11y sign-off), never *out* of an applicable control — the CI/agent-boundary gates bind to the PR regardless of author role ("routing by role changes which doc you open, never which gate applies").
- **`scripts/incept.sh`** — the interactive flow now prompts operator-fluency (the 7th field; previously flag/env-only). Empty-enter stays **non-coercive** — the existing undeclared-fluency notice fires, no silent default, no `CLAUDE.md` stamp; a typo is rejected by the existing membership validation.

### Notes
- **Security Owner in the §13 ratification role table** (a third WS4 item in the original spec) was **verified already present** — across `DEVELOPMENT-PROCESS.md` §2 Roles/Personas, the §7 threat-model/compliance gates, the §13 ratification matrix, and `docs/enterprise/ratification-rbac.md` (added during WS2/3.4.0). No edit made — editing complete, consistent governing tables would be redundant control-plane churn.
- **Deferred-with-reason (residual):** the operator-fluency membership test (`incept.sh` :118-119) uses the POSIX space-padded `case` idiom, which loose-matches a multi-token string containing a valid token (e.g. `"x novice y"`). Assessed pre-existing (reachable today via `--operator-fluency`), non-exploitable (only space-delimited words pass → no sed metacharacter can reach the `:170` `sedi`; threat model is an operator scaffolding their own repo), and out of WS4 item-3 scope. Independently re-verified by the reviewer. Tracked for a later control-plane validation-hardening ticket.

### Why
A go/no-go usability finding: the front door routed only the *experience* axis (novice → practitioner); a QA, designer, product owner, or security owner had no signposted entry, and interactive `incept` collected six fields but never fluency. WS4 closes both without weakening anything — persona routing is additive surfacing, and the fluency prompt is non-coercive.

## [3.6.0] - 2026-06-18

**MINOR** — D4-presentation: **"ratification required" is now a merge-gate, not a red failure.** The `gate-agent-boundary` job exits 0 and posts a distinct `control-plane-ratification` check-run instead of `exit 1`-ing red — so an unratified control-plane PR **blocks the merge in amber, sends no "CI failed" email**, and red ❌ / failure emails are reserved for genuine failures. Decision logic unchanged; enforcement, audit trail, and harness-independence preserved. **Live-verified on PR #114** (`ACTION_REQUIRED` · workflow `success`/no-email · merge `BLOCKED`).

### Changed
- **`.github/workflows/ci.yml` + `profiles/typescript-node/ci.yml`** — the `gate-agent-boundary` job now exits 0 and posts the `control-plane-ratification` check-run via the Checks API (needs `checks: write`); `CI=` is cleared on the `agent-boundary.sh` call so its true three-state (0 ratified/no-cp · 1 unratified-cp · 2 cannot-evaluate) maps to `success` / `action_required` / `failure`. `conformance/agent-boundary.sh` is untouched — **presentation only.**
- **Branch protection:** require the `control-plane-ratification` check so `action_required` blocks the merge (GitHub blocks any required check that isn't `success`). Keep `enforce_admins: false` solo (the logged admin-merge is the ratification); flip `enforce_admins: true` when a team forms (WS2).
- Docs updated to the verified behavior (`docs/operations/harness-enforcement-evidence.md` live evidence; `START-HERE.md` solo note).

### Why
A permanently-red, *required-less* gate emailed "CI failed" on every solo control-plane PR — training red-blindness in the PR view **and** the inbox (the alert-fatigue anti-pattern). "Ratification required" is an awaiting-action **merge-gate** (like "Review required"), not a test; presenting it as such protects the failure channel so a *real* failure still cuts through. (We also found the old gate was never a required check — noise without enforcement; now it's enforcement without noise.)

## [3.5.0] - 2026-06-18

**MINOR** — P2/WS3 of the usability-governance milestone: **progressive-disclosure front door**. Curates the first impression to a ~5-file core path with a pull-not-push map for the enterprise/operability/continuity depth — so a newcomer sees a front door, not the full file wall. **Nothing deleted, no gate disabled, no applicable control hidden**; ordering and emphasis only.

### Added
- **`START-HERE.md`** — a top-of-file "you do not need to read all of this" block: the **first 5** core path (`START-HERE.md` · `CLAUDE.md` · `DEVELOPMENT-PROCESS.md` · your `profiles/<stack>.md` · `AGENTS.md`) + a **pull-not-push** trigger map (regulated → `docs/enterprise/`; live system → `docs/operations/`; data service → `docs/continuity/`; need an artifact → `templates/`). The conditional gates already activate by trigger; the docs are now discovered the same way.
- **`ONBOARDING.md`** — a matching "you will not read all of this" note that hands to the START-HERE core-5 map.
- **`docs/enterprise/README.md`** — explicit pull-not-push framing (reached on trigger; not part of the core path; adopting nothing here weakens no floor).

### Changed
- **`conformance/onboarding-complete.sh`** — extended to assert the front-door signal (first-5 + pull-not-push map) is present in `START-HERE.md`, so the progressive-disclosure surface can't silently regress. Wired in the kit's CI.

## [3.4.0] - 2026-06-18

**MINOR** — P2/WS2 of the usability-governance milestone: **risk-tiered solo review lane**. A solo maintainer now has a recorded, audit-defensible way to satisfy `builder ≠ reviewer` — without faking it and without a second human — that upgrades to enforced two-human SoD with a single `enforce_admins: true` flip and zero rework of the recorded evidence when a teammate joins. Additive (docs/template/process + one presence conformance check); no applicable control weakened.

### Added
- **`templates/REVIEW-RECORD-TEMPLATE.md`** — the recorded-review artifact: agent-review findings + human ratification, plus (high-risk) specific acknowledgments tied to each finding (the anti-theater requirement). Carries the solo compensating-control statement + the one-flip (`enforce_admins: true`), zero-evidence-rework upgrade note.
- **`docs/operations/review-lane.md`** — the two tiers (default = recorded `reviewer`-subagent review + recorded ratification; high-risk [control-plane / security-auth / data-schema / prod / irreversible] = + a structured human self-review), the already-wired trigger (the `agent-boundary` control-plane set + the §13 autonomy tiers), the compensating-controls compliance rationale, and the solo→team upgrade (one `enforce_admins: true` flip — the second human's approval meets the existing required-review rule; the flip removes the owner `--admin` bypass — with zero rework of recorded evidence).
- **`conformance/review-lane.sh`** — presence/wiring conformance check, wired into the kit's own CI.

### Changed
- **`DEVELOPMENT-PROCESS.md` §12** — a **net-zero** solo-lane pointer (the doc is at its 470-line cap). **`conformance/audit-evidence-checklist.md`** gains an Independent-code-review / SoD evidence row mapping the bundle to the SoD control.

### Honest ceiling
- The high-risk self-review is **process discipline, not a fail-closed gate** (mechanically blocking it needs a second actor the solo case lacks) — the kit makes it the path of least resistance + audit-visible, and the `agent-boundary` CI gate still forces ratification on control-plane diffs regardless.

## [3.3.0] - 2026-06-18

**MINOR** — P2/WS1 of the usability-governance milestone: **guard false-positive fix (deny-by-default)**. The control-plane guard stops falsely blocking read-only commands that merely *mention* a control-plane path, and the path check no longer false-denies a same-named file in a non-control-plane directory — without weakening any protection (verified across four adversarial security reviews + a dual corpus).

### Changed
- **WS1 — control-plane command rule, deny-by-default.** `guard-core.sh` keeps the prior co-occurrence deny as the **floor** (no protection removed) and allows back ONLY a *provably-safe single read command*: no `;`/`&&`/`||`/`|`/`&`/redirect/command-substitution chaining, and a leading verb (after stripping a leading `\`, env-assignments, and `sudo`/`command`/`env`/`exec`/`time`/`nice`/`nohup`/`stdbuf`/`builtin`) in a strict write/exec-free read allowlist (`grep`/`cat`/`ls`/`wc`/`diff`/`cut`/`od`/… — `sed`/`awk`/`find`/`sort`/`uniq`/`less`/`xxd` are excluded as write/exec-capable). So `grep cp scripts/kit-guard`, `cat .github/workflows/ci.yml`, `ls -l scripts/kit-guard` are allowed while every real mutation — and any unrecognized leading token (wrapper, interpreter, prefix) — stays denied.
- **Path basename net narrowed + normalized (found via a real `.vscode/settings.json` report).** The bare-basename fallback fires only for a normalized path with no genuine parent directory, or one that escapes its root via `..`; `fpn` strips a leading `./`, a trailing `/`, and resolves `..` to a fixpoint. So `.vscode/settings.json` / `app/config/settings.json` are allowed while `./settings.json`, `../guard.sh`, `a/../../kit-guard`, and `.claude/settings.json/` are denied.
- Both directions are regression-locked by an expanded dual corpus in `conformance/agent-autonomy.sh`; the `.claude/README.md` over-block note is updated to the precise behavior.

### Honest ceilings
- The guard remains a speed bump: variable/`eval`/command-substitution indirection, and uncommon write-via-flag tools (`sort -o`, `xxd -r`, `perl -pi`, `ed`) are documented pre-existing gaps, backstopped by the `agent-boundary` CI gate on the diff. A compound command that merely *mentions* a control-plane path stays denied (safer than parsing compound shell) — use `KIT_GUARD_SELFEDIT=1` or split the command.

## [3.2.0] - 2026-06-17

**MINOR** — H1 of the post-3.0.0 backlog: **enforcement integrity** — the kit's own controls now resist the agent they govern. Brings the enforcement layer into the control-plane set, constrains adapter `proof.check` execution, removes an agent-forgeable ratification label, and makes the kit dogfood its own governance gate. Additive hardening; the supported `typescript-node` path stays green.

### Added
- **H1.1 — the enforcement layer is now control-plane.** `guard-core.sh::is_control_plane_path` (the single source of truth honored by the inline guard, `pre-push`, `kit-guard`, and the `agent-boundary` CI gate) now covers `conformance/`, `adapters/`, `scripts/fixtures/`, the named kit scripts (`incept`, `dora`, `agent-scorecard`, `agent-trace`, `coverage-ratchet`, `license-check`, `preflight`, `new-adapter`, `new-profile`), and the governing docs `DEVELOPMENT-STANDARDS.md` / `DEVELOPMENT-PROCESS.md` / `CLAUDE.md`. An agent can no longer weaken a gate's logic, relax the Definition of Done, or add an adapter without ratification. `scripts/` is a **named-script set, not a blanket prefix**, so an adopter's own `scripts/` code is unaffected (adopter friction = zero).
- **H1.4 — the kit dogfoods its own gate.** `.github/workflows/ci.yml` now runs the **real** `gate-agent-boundary` job on every PR (previously only `--selftest`). An unratified control-plane PR makes the job `exit 1`, which GitHub renders as a **failed (red) check** meaning *"ratification required"* — the expected human step, **not a code regression** (live-verified on PR #110). The "ratification required" semantics ride the job/step naming + docs; GitHub offers no non-failing-but-blocking state for a plain step, so a true neutral presentation is a tracked D4 follow-up.

### Changed
- **H1.2 — `proof.check` allowlist.** `conformance/harness-adapter.sh` executes an adapter's `proof.check` only if it is a bare `conformance/*.sh` path (no arguments, shell metacharacters, or `..` traversal) that exists — anything else is rejected *before execution* and cannot prove `native`. Closes arbitrary-code execution from an unratified adapter manifest; a new selftest canary proves the dangerous check never runs.
- **H1.3 — removed the self-ratifiable label.** The `agent-boundary` ratification signal is now a **non-author approval only**; the `ratified-control-plane` label (self-appliable by an agent via `gh pr edit --add-label`) is gone. Solo maintainers ratify via a logged `enforce_admins: false` admin-merge — recorded, never faked.

### Honest ceilings
- The inline guard remains a speed bump: a control-plane edit made through a language interpreter (`python -c`, a script) is **not** caught by its command-string heuristic — the `agent-boundary` CI gate is the post-hoc backstop that catches the resulting diff before merge. Command-string false-positive tuning is deferred to **P2/WS1**; GitLab gate parity to **H4**.
- The `proof.check` allowlist also rejects a **symlinked** check (`[ ! -L ]`), closing the residual where `[ -f ]` would follow a committed symlink under `conformance/` to a payload elsewhere (itself ratification-gated by H1.1 — this is belt-and-suspenders). One named-set residual remains: a newly-added kit `scripts/*.sh` is not control-plane until hand-enrolled in `is_control_plane_path` — a conformance check asserting full enrollment is a possible follow-up.

## [3.1.0] - 2026-06-17

**MINOR** — P1 of the post-3.0.0 backlog: turns the adapter `controlPlanePaths` from a declarative inventory into real enforcement (N5), plus profile parity and conformance-honesty hardening. Additive; the supported `typescript-node` path stays green.

### Added
- **N5 — `controlPlanePaths` union enforcement.** The `agent-boundary` gate now denies an unratified PR that touches any path in the **union of adapter-declared `controlPlanePaths`** (across `adapters/*/adapter.json`), in addition to the kit-standard `guard-core.sh::is_control_plane_path` floor. Entries match exactly or as a directory prefix (a value ending in `/`). So each harness's *own* control-plane surface is enforced — e.g. an unratified `AGENTS.md` edit (declared by the `generic` adapter, outside the guard-core set) is now caught. `jq`-absent or no `adapters/` degrades to the floor. `docs/operations/harness-adapters.md` updated from "future work" to "enforced."

### Fixed
- **Profile parity** — the `python` scaffold now sets `fail_under = 80` (the 80% coverage floor the profile + Definition of Done require); the GitLab `typescript-node` CI reference gains the conditional `gate-eval` the GitHub reference already had.
- **Conformance honesty** — `branch-protection.sh` adds a non-fatal advisory when `require_code_owner_reviews` is disabled (so builder ≠ sole reviewer stays visible on protected paths); `runtime-guards.md` now honestly enumerates the known guard-bypass classes (redirect/`printf` writes, `curl --data @file`, `git am`/`git apply`, interpreters) as within the speed-bump ceiling, rather than over-promising.

## [3.0.1] - 2026-06-17

**PATCH** — closes the four pre-announce conditions from the 3.0.0 go/no-go (an 11-dimension adversarial review: **GO-WITH-CONDITIONS, 0 blockers**). No new capability; makes the release safe to announce. The remaining Medium/Low findings are tracked as a 3.0.x fix-forward follow-up.

### Fixed
- **Brownfield safety (High):** `scripts/incept.sh` no longer silently overwrites an existing repo's `.github/workflows/ci.yml` or CODEOWNERS. It marker-detects the kit's *own* reference files (replacing them in a greenfield kit copy, as before) but **preserves and warns** for a genuine adopter file. (go/no-go #2)
- **Governance-doc honesty (High):** `docs/operations/harness-adapters.md` no longer claims an adapter's `controlPlanePaths` "feeds the `agent-boundary` gate's union." The gate enforces the `guard-core.sh::is_control_plane_path` set for *every* harness and does not read per-adapter manifests; the field is now described as a declarative inventory with the union-wiring named as future work. (go/no-go #3)
- **First-run DX (Medium):** `incept` now stamps a **stack-appropriate** default `PORT` into `.env.example` (3000 node, 8000 python, 8080 go/rust) instead of a hardcoded 8080 — fixing the documented `curl localhost:3000` for the default typescript-node stack. (go/no-go #4)

### Release integrity (go/no-go #1)
- The mis-pointed `v3.0.0` git tag (it pointed at an old v2.12.0-era commit) is corrected to the real 3.0.0 release commit, and the previously-untagged `2.63.0`–`2.65.0` releases are back-tagged — a release-maintenance action performed alongside this patch.

## [3.0.0] - 2026-06-17

**Harness-neutrality milestone — N4: proof, positioning, and the release.** Closes the LLM/harness-neutral arc (N1–N4): the kit is now usable with any agent harness out of the gate, with the enforcement floor **maintainer-verified to block regardless of harness**. **MAJOR as a milestone marker, NOT a breaking change** — an existing Claude Code adopter upgrades with nothing broken; everything added across N1–N4 is additive and the default experience is untouched.

### The milestone (N1–N4)
- **N1 (`2.63.0`)** — the `agent-boundary` CI gate: harness-independent control-plane ratification, so the §13 agent boundary holds on any harness (including one with no inline guard, because CI catches an unratified control-plane edit before merge).
- **N2 (`2.64.0`)** — the adapter boundary contract + `conformance/harness-adapter.sh` (the composing meta-check with the "lying-native" guard) + the `claude-code` reference adapter.
- **N3 (`2.65.0`)** — the `generic` floor-only adapter + `incept --harness` (multi-select, default `claude-code`) + Inception-Done enforcement (a project can't pass Inception unless each declared adapter conforms — greenfield **and** brownfield).
- **N4 (this release)** — see below.

### Added (N4)
- **`docs/operations/harness-enforcement-evidence.md`** — names the maintainer-verified enforcement proof: three deterministic, CI-locked surface selftests — `scripts/kit-guard --selftest` (the CLI surface any non-Claude runtime pipes through), `hooks/pre-push --selftest` (git-history), and `conformance/agent-boundary.sh --selftest` (the CI gate) — that block destructive/control-plane actions regardless of caller.
- **BYO adapters** — `adapters/_TEMPLATE/` (a floor-only skeleton that conforms immediately) + `scripts/new-adapter.sh <harness>` (mirrors `scripts/new-profile.sh`), so any harness (Cursor, Gemini, …) is a guided, validated path — parity with the stack BYO story.
- **Positioning** — the README is now explicitly **stack- AND harness-neutral**.

### Honesty / engineering notes
- **Split proof bar:** enforcement is *maintainer-verified* (the three surface selftests — deterministic, CI-locked — block any caller); process-following is *authored-to-contract*; and the **live cross-harness agent demo** (driving a real third-party agent end-to-end) is documented as the recommended **first real-world validation**, honestly *not* claimed as already-run. The floor is a maintainer-verified **speed bump, not containment** — the real boundary remains platform-owned (`docs/enterprise/platform-safety-boundary.md`).

## [2.65.0] - 2026-06-17

**Harness-neutrality — N3: the `generic` adapter + `incept --harness`.** Third slice of the LLM/harness-neutral milestone (→ `3.0.0`). The kit becomes pickup-able with a non-Claude harness out of the gate, provably enforced for greenfield **and** brownfield. **MINOR** — additive; the no-flag `incept` experience is unchanged.

### Added
- **The `generic` adapter** (`adapters/generic/adapter.json`) — an all-`floor` manifest (`mcp-gate: n-a`) that proves a harness with **no inline guard** (Codex, Cursor, Copilot reading `AGENTS.md`) clears the boundary contract entirely via the Kit-enforced floor (the git hook + CI backstop), with inline interception honestly absent.
- **`incept.sh --harness <list>`** — multi-select, comma-separated, **defaults to `claude-code`** (a no-flag run behaves exactly as before). Validates each name against the `adapters/` registry, stamps a **"Target harness(es)"** field into the project `CLAUDE.md`, and — after its transforms, on the real project — runs `conformance/harness-adapter.sh` per selected harness as a **loud, non-fatal** report (a brownfield adopter sees exactly which floor gaps remain).
- **Inception-Done enforcement** — `conformance/inception-done.sh` now reads the stamped harness field and **fails the gate** if any selected adapter doesn't conform to the boundary contract. This is the brownfield safety net: a merged repo can't pass Inception until its declared adapter(s) actually conform (greenfield passes; a non-conforming adapter blocks).

### Changed
- The kit dogfoods it: a `generic` real-run is added to the kit's `ci.yml` + `verify.sh`, and the CI bootstrap job now incepts with `--harness claude-code,generic` (exercising stamp → enforcement end-to-end).

### Honesty / engineering notes
- **Report at the action, enforce at the checkpoint:** incept reports gaps non-fatally so an adopter can finish setup and then close them; the Inception-Done gate is what blocks unsafe. Verified: incept does not rewrite `AGENTS.md` and removes no floor files, so a correctly-incepted project conforms post-transform — the enforcement is honest, not hollow. The BYO adapter `_TEMPLATE` and the live cross-harness demo are N4.

## [2.64.0] - 2026-06-17

**Harness-neutrality — N2: the adapter boundary contract.** Second slice of the LLM/harness-neutral milestone (→ `3.0.0`). **MINOR** — additive: a contract doc, the `claude-code` reference adapter, and a composing conformance check; no change to existing gates, nothing breaks.

### Added
- **Adapter boundary contract** (`docs/operations/harness-adapters.md`) — the 5 dimensions (`context-binding`, `command-guard`, `history-protection`, `review-roles`, `mcp-gate`), each with a **Kit-enforced floor** (the equal-enforcement guarantee — asserted for every harness) and an optional **Kit-assisted native** bonus, plus the JSON manifest schema.
- **`adapters/` + the `claude-code` reference adapter** (`adapters/claude-code/adapter.json`) — a declarative manifest that **references** the existing `.claude/` governance layer (not a copy): control-plane paths, binding files, and per-dimension `native`/`floor`/`n-a` with a per-dimension proof. The kit's `.claude/` stays exactly where it is.
- **`conformance/harness-adapter.sh`** — a *composing* meta-check (three-state; `--selftest`): validates the manifest, asserts the floor for **every** dimension by calling existing checks (`agents-brief.sh`, `guard-core-sourced.sh`, …), and runs each `native` dimension's declared proof so an adapter **cannot overclaim** (the "lying-native" guard — `command-guard: native` must pass `guard-wired.sh`; `mcp-gate: native` must pass `mcp-policy.sh`). It composes the existing checks, never reimplements them.

### Changed
- The kit dogfoods it: `harness-adapter.sh --selftest` plus a real-run against the `claude-code` adapter are wired into the kit's `ci.yml`, and the real-run is registered in the `verify.sh` aggregate.

### Honesty / engineering notes
- The **floor is the equal-enforcement guarantee** (asserted for every dimension regardless of declared level); `native` is an additive bonus whose claim must pass a real proof. The `generic`/AGENTS.md adapter + `incept --harness` are N3.

## [2.63.0] - 2026-06-17

**Harness-neutrality — N1: the agent-boundary CI gate.** First slice of the LLM/harness-neutral milestone (→ `3.0.0`). **MINOR** — additive: a new §13 governance gate + reference job + conformance check; the 7 required build gates are unchanged and nothing breaks. Claude Code stays the default, regression-locked.

### Added
- **`conformance/agent-boundary.sh`** — a harness-independent, three-state CI check (`0`/`1`/`2`; UNVERIFIED escalates under CI/`--require`) that fails a PR whose diff touches a control-plane path without an explicit human ratification signal (a CODEOWNER approval or the `ratified-control-plane` label — the label path was later removed in 3.2.0/H1.3 as agent-forgeable). Reuses `guard-core.sh::is_control_plane_path` (single source of truth — no forked path list); a pure decision core with an in-process `--selftest`.
- **`gate-agent-boundary`** reference job in `profiles/typescript-node/ci.yml` — computes the changed-file set + the ratification signal (label or a non-author approval, taking each reviewer's latest review) and runs the check fail-closed; a `gh` failure fails the step loudly. It is a §13 governance gate, **not** one of the 7 required build gates.
- **§13 contract clause** in `DEVELOPMENT-PROCESS.md` + a fourth surface row in `docs/operations/runtime-guards.md`: the gate makes "agents propose, humans ratify; never self-edit the control plane" hold on **every** harness — including one with no inline guard — because CI catches an unratified control-plane edit before merge.

### Changed
- The kit dogfoods the new check: `agent-boundary.sh --selftest` is wired into the kit's own `ci.yml` and registered in the `verify.sh` aggregate (so `ci-selftest-coverage` enforces it).

### Honesty / engineering notes
- **Split proof bar:** the enforcement half is deterministic and maintainer-verified (the selftest corpus + the conformance run); the live ratification shell (`gh`) runs only inside a real GitHub PR and is authored-to-contract — the gates catch deviation, the agent's compliance is not assumed.
- **Honest ceiling:** CI is post-hoc and `.github/workflows/*` is itself control-plane — the real boundary remains platform-owned (`docs/enterprise/platform-safety-boundary.md`).

## [2.62.1] - 2026-06-17

**PATCH** — closes the post-launch go/no-go backlog (per-stack reproducibility + container/config completeness). No new capability; makes 2.62.0's per-stack promises true. Several fixes Docker-verified.

### Fixed
- **go** — ship the `.golangci.yml` baseline (govet/staticcheck/errcheck/gosec) that profile §2 promised, and **pin** the `golangci-lint-action` version so green is reproducible. Refactored the scaffold to a configured `http.Server` (`newServer()`, `ReadHeaderTimeout`) to satisfy gosec G114; added its test (coverage 88.9%). *Docker-verified: lint clean + tests pass.*
- **typescript-node** — the Dockerfile `HEALTHCHECK` referenced an unbuilt `dist/healthcheck.js` **and** `node` isn't on `$PATH` in distroless. Added `src/healthcheck.ts` (coverage-excluded) and fixed the probe to `/nodejs/bin/node`. *Docker-verified: container reports `healthy`.*
- **dotnet** — added the `.editorconfig` + `Directory.Build.props` (`TreatWarningsAsErrors`, analyzers) profile §2 declared mandatory; fixed the Dockerfile to publish the app project only (not the `.sln`) and drop the non-existent root `packages.lock.json` COPY. *Docker-verified: build 0 warnings/0 errors, test passes.*
- **kotlin** — the one-time `gradle wrapper` step is now version-pinned (`--gradle-version 8.10`) so an older local Gradle can't generate an incompatible wrapper.
- **java-spring** — OWASP dep-scan now caches the NVD dataset and accepts an optional `NVD_API_KEY` secret, with a first-run caveat (keyless runs can rate-limit).
- **incept** — the scaffold-copy now skips stray build artifacts (`node_modules`, `dist`, `coverage`, `__pycache__`, `.coverage`, `target`, `bin`, `obj`, …) so a project incepted from a dirty dev tree stays clean.

## [2.62.0] - 2026-06-16

**Deliver the scaffold** — the second pre-launch go/no-go found the kit overclaimed turnkey readiness in its headline surfaces; this release makes those claims true. **MINOR** — additive (the new eval gate is conditional, not universally required); closes all seven verified Highs (H1–H7) from that review.

### Added
- **Per-stack starter scaffolds** (`profiles/<stack>/scaffold/`) for all 7 service stacks — manifest + lint/type config + a `/healthz` surface + its test, authored to each `ci.yml` gate contract. `scripts/incept.sh` copies the scaffold into an empty repo (brownfield-safe), so Inception's "green pipeline on the empty project" gate is reachable in one command. typescript-node is verified green on clone; go is clone-green by construction; the rest are authored-to-contract with a documented one-time lockfile/wrapper step (see each `scaffold/README.md`).
- **Reference eval harness** (`profiles/ml/evals/run.py` + `golden.jsonl` + `rubric.md`) — a deterministic, offline scorer runnable as `python -m evals.run --threshold 0.8`, green on clone with no API key (swap in a pinned LLM judge for production). `python` and `typescript-node` gain a **conditional `gate-eval`** that runs only when an `evals/` dir is present.
- **`.env.example`** is now created by `incept` and asserted by `conformance/inception-done.sh`; `incept` also guarantees `.env` is gitignored.
- **Stack-driven environments** — each service profile gains an "Environments this stack needs" section; `docs/STACK-SELECTION.md` gains a stack × backing-services matrix; `incept` now copies the profile's `compose.yaml`.

### Changed
- **`guard-wired.sh`** now structurally validates that the PreToolUse hook matcher admits the mutating tools (Bash/Write/Edit/NotebookEdit/`mcp__*`) — a misconfigured matcher no longer reports the guard as wired; jq-absent is UNVERIFIED (exit 2), never a silent pass. Adds `--selftest`.
- **`mcp-policy.sh`** jq-absent now exits 2 (UNVERIFIED) instead of 0 (PASS).
- **`go` + `rust`** ship a stateless (app-only) `compose.yaml` — no longer Postgres-by-default (their archetype is networked-service/CLI).
- Reworded the eval / scaffold / environment claims across README and the profiles to match what now ships (honesty invariant).

## [2.61.0] - 2026-06-15

**Discovery loop (FRAME + SHAPE)** — an **optional, opt-in** upstream front-end that turns a raw signal into a *Ready* backlog the Sparkwright engine consumes. **MINOR** — new docs + templates + one structural control; **no change to the existing process** (stages 3–6 are documented as the existing engine).

### Added
- **`docs/discovery/discovery-loop.md`** — the six-stage product loop (owner · ART=human turns · AI=tasks · gate · loop-backs); maps stages 3–6 onto Sparkwright's existing loop; states the opt-in/skip rule and the Ready seam.
- **`docs/discovery/frame.md` + `shape.md`** — the two new stage guides (FRAME = Product/Frame-approved; SHAPE = Design/Direction-chosen), each with its human-turns vs AI-tasks split.
- **`templates/OPPORTUNITY-BRIEF-TEMPLATE.md` + `SHAPING-DOC-TEMPLATE.md`** — the upstream artifacts that feed the existing FEATURE-REQUEST/SPEC at PLAN → Ready (no duplication).
- **`conformance/discovery-complete.sh`** — structural drift-guard (present + wired); wired into CI.
- Wiring: an ONBOARDING discovery door, README milestone link + What's-inside row, GLOSSARY entries.

### Honesty / engineering notes
- **Opt-in, never a turnstile** — arrive with a Ready backlog and you skip discovery entirely (the onboarding Practitioner fast-path). The default drop-in-and-build path is untouched.
- **Zero process change** — the core-3 docs are unchanged (900/900); the layer is all new files. The ART/AI split is guidance, not an automated gate (discovery is judgment work).

## [2.60.0] - 2026-06-15

**Named *Sparkwright* + execution-engine milestone.** The kit gets its real name — *Sparkwright* (`spark` + `-wright`, a maker who turns the spark into built, shipped software) — replacing the placeholder "Agentic SDLC Kit" descriptor across the prose. **MINOR** — naming + positioning only; no functional, contract, or process change (the product *name* is not logic-bearing; the repo slug stays `agentic-sdlc-kit` until a deliberate pre-launch rename).

### Changed
- **Name** — "Agentic SDLC Kit" → **Sparkwright** across README/MAINTAINING/START-HERE/templates/enterprise docs/scripts display text. "an agentic SDLC kit" is kept as the *descriptor* (clarity/SEO). Repo slug unchanged for now (renamed once, pre-launch).

### Added
- **Milestone positioning** — README now states Sparkwright is the **execution engine** (Ready backlog → operating, monitored software): drop it in and build. A **discovery front-end** (raw signal → Ready work — the FRAME/SHAPE upstream stages) is named as a **separate, optional upstream layer** on the roadmap, so the build-mode user is never forced through discovery they don't need.

## [2.59.0] - 2026-06-15

**Onboarding on-ramp** — a fluency-aware front door that meets developers across the experience spectrum (vibe-coder → principal), teaches *the system around the code* by routing to canonical sources (never duplicating the standards), and lets the agent adapt its assistance. **MINOR** — new front-door docs + a structural conformance control; no new universal-required gate.

### Added
- **`ONBOARDING.md`** — experience-axis front door: the *coding ≠ engineering* thesis + 3 self-select lanes (Novice / Adjacent / Practitioner, non-punitive to switch) + a layered Learning lane that motivates each pillar (TDD · 15-factor · security · governance · environments · observability) and routes to canonical sources + the existing kit docs. Hands off to `START-HERE.md` (role axis).
- **`docs/onboarding/first-feature-tdd.md`** — a worked red-green-refactor TDD walkthrough (reference stack), the one concrete code beat the whole-loop `WALKTHROUGH.md` lacked.
- **Operator fluency** — declared in the project-CLAUDE template (§3) and read by the agent via `docs/operations/operator-fluency.md`: adapts *communication* to the operator's level (explain + confirm-before-irreversible for Novice/Adjacent; terse for Practitioner), refined by observation, **never** changing what the agent is permitted to do. `incept.sh --operator-fluency <level>` stamps it; an undeclared run nudges (not walls) toward the on-ramp.
- **`conformance/onboarding-complete.sh`** — structural drift-guard: the on-ramp is present + wired (registered as a `verify.sh` control).

### Honesty / engineering notes
- **The on-ramp teaches; the guard + gates protect.** A bypass (the Practitioner lane / `--operator-fluency practitioner`) skips the *teaching*, never the *protection* — which is what makes "functional and not dangerous" hold even for someone who skips onboarding.
- **No duplication of the standards** — the Learning lane motivates and routes; the canonical content stays in the standards/profiles as the single source of truth (DRY).

## [2.58.0] - 2026-06-15

**Code-quality lens + CI-coverage lock** — a deliberately right-sized quality pass (pulled back from a 3-slice arc after a strategic check: the kit was already strong on `gate-lint`/type-checks/test-quality/coverage-ratchet/builder≠reviewer, so this polishes the last 20%) plus a meta-check that makes the kit's own CI enforcement self-auditing. **MINOR** — a new control check + adopter-facing review discipline; **no new universal-required gate** (the code-quality lens is review discipline, not a fail-closed gate, by design).

### Added
- **Code-quality lens** (`#85`): `docs/operations/code-quality.md` — the review dimensions a metric can't gate (readability · simplicity · function size · naming · comment quality · type/interface design · cohesion/coupling · dead code) + complexity/duplication as **recommended per-stack `gate-lint` config** (not new gates) + consistency as the through-line. `templates/CODE-REVIEW-CHECKLIST.md` for the §7 Review gate; a `+0` fold in `DEVELOPMENT-PROCESS.md` §7 naming the lens; the per-stack complexity/duplication linter line across all 10 profiles + `_TEMPLATE`.
- **Shellcheck regression-lock** (`#85`): `conformance/shellcheck.sh` lints the kit's **maintainer-editable** shell (`scripts/`, `conformance/`, `hooks/pre-push`) at the error/warning floor; conditional on shellcheck installed (SKIP-pass if absent; CI runs it for real). Kit shell made clean via justified `# shellcheck disable=SCnnnn # reason` comments.
- **CI smokes** (`#86`): `security-policy.sh` + `privacy-ready.sh` selftests and the `shellcheck.sh` real-run/selftest wired into the kit's own pipeline (closing the SP-2/SP-3/code-quality CI-wiring gap).
- **CI-coverage meta-check** (this release): `conformance/ci-selftest-coverage.sh` — flags (fail-closed) any selftest-capable kit check (`conformance/*.sh`, `scripts/*.sh`, `hooks/pre-push`) that is not wired into `ci.yml`, so a checker can't quietly ship "existing but unenforced." "Wired" means named in an execution context (comments and `name:` labels are stripped before matching, so a *mention* isn't mistaken for a *run*). **Self-excluded** (a meta-check can't non-circularly verify its own wiring — its presence in `ci.yml` is a one-time maintainer bootstrap). Registered as a `verify.sh` control; it gates the push **as its own real-run CI step** (the kit's `verify.sh --selftest` step is a renderer check and does not propagate control exit codes).

### Honesty / engineering notes
- **The shellcheck scope is honest, not maximal**: the §13 control-plane guard (`.claude/hooks/guard*.sh`) is **excluded** from the lint lock — it carries only benign warnings (redundant-but-still-denying case patterns + a `cls=read` false positive; no dead deny-rule, independently verified) and is regression-locked **behaviorally** by its own deny-corpus conformance instead. The README/header scope the claim to maintainer shell rather than overclaiming "the kit's own shell code."
- **A check "existing" ≠ "enforced"**: a `.sh` with a `--selftest` only protects against regressions once it runs in CI on every push. The coverage meta-check turns that from a thing a human must remember into a thing the kit guarantees.

## [2.57.0] - 2026-06-12

**Security & Privacy completeness arc** — closes the verified gaps from a repo-grounded gap-scan so the kit's security/privacy posture is whole before the pivot to UX/product-design. **MINOR** — new conditional gates + reference tools + readiness checks; no new *universal-required* gate. Three ratified, security-reviewed slices (#79 SP-1, #82 SP-2, #83 SP-3).

### Added
- **SP-1 — security gates** (`#79`): two **conditional** gates (the a11y/load/eval family). `gate-sast` (first-party static analysis — Semgrep default / CodeQL alt, per profile) for the injection/auth-bypass/SSRF class that `gate-dep-scan` and `gate-secret-scan` miss. `gate-license` — `scripts/license-check.sh` (sh+jq) acts on the existing CycloneDX SBOM: flags denylisted strong-copyleft (anchor spares weak-copyleft `LGPL`), evaluates every license entry + splits SPDX `AND`/`OR` expressions, and **self-flags undetermined/NOASSERTION** components, pointing to a **per-stack upgrade ladder** (`cargo-deny`, `go-licenses`, …) that keeps the same `gate-license` id. Named in §7/§14 + `conditional-gates.sh`; `docs/operations/security-scanning.md`.
- **SP-2 — disclosure policy** (`#82`): `templates/SECURITY-TEMPLATE.md` + `conformance/security-policy.sh` (conditional three-state; triggers on a governed repo via `CLAUDE.md`) + `incept.sh` scaffolding. The kit **dogfoods** its own `SECURITY.md` (GitHub private vulnerability reporting — anonymization-safe).
- **SP-3 — data governance** (`#83`): a 4-tier **classification scheme** (Public/Internal/Confidential/Restricted) + `templates/PRIVACY-REVIEW-TEMPLATE.md` (DPIA-lite) + `conformance/privacy-ready.sh` (triggers only on a declared Confidential/Restricted value → a recorded privacy review). `docs/enterprise/data-governance.md`. COPPA/children's-data framed as **one applicability, not a mandate**.

### Honesty / engineering notes
- **Conditional, not universal** — SAST/license/privacy apply on the N/A-with-reason basis; no forced friction on a CLI/IaC/Public-data repo. Green proves the scan *ran* / policy *applied* / posture *recorded* — never that code is secure, licenses legally cleared, or processing lawful (Manual operator rows).
- **License is stack-neutral but self-aware** — necessary-not-sufficient over the SBOM, with an explicit, contract-preserving upgrade path when an enterprise needs higher fidelity.
- **Guardrails held under pressure** — independent security-owner review per slice caught and fixed: 2 copyleft false-negatives + a CI-pin break (SP-1), an attempted doc-budget guardrail loosening (SP-2, reverted), and a privacy-gate fail-open (SP-3). The core-doc budget stayed at its deliberate 900 cap throughout.

## [2.56.0] - 2026-06-12

Modern Practices arc, Slice **MP-3 — agentic-ops**: observe and govern an agent's *own work*, the layer the kit lacked (the §13 guard *prevents* harm, §7 evals judge a *feature's* output, §2 tracks *spend* — none observed the **execution**). **MINOR** — new reference tools + contract + readiness rows; no new required gate (the tools are validated by their own selftests, not by failing a PR). Shipped as five ratified PRs (#73 MP-3a, #74 MP-3a.2, #75 MP-3b, #76/#77 kit-CI smokes), each independently security-reviewed (builder ≠ sole reviewer) → SHIP.

### Added
- **MP-3a — the trace contract + conformance** (`#73`): a stack/harness-neutral **agent-run trace schema** (OTel-GenAI-anchored required-core + recommended; identity-keyed `agent.id`/`run.id`/`work_item.id`/`parent.run.id` for multi-agent safety) in `docs/operations/agentic-ops.md`, the **sensor→§13-autonomy-tier** model, plus `conformance/agentops-ready.sh` (conditional, three-state, declared-discipline) + `agentic-ops-readiness.md` + RUNBOOK/CLAUDE declaration wiring.
- **MP-3a.2 — the dev-time emitter** (`#74`): `scripts/agent-trace.sh` (sh+jq+gh, the `dora.sh` idiom) derives a schema-conformant trace from a Claude Code JSONL transcript — transcript-native fields solid, `gh`/`git`-correlated fields best-effort (`unknown` when not derivable, never fabricated). The reference *adapter* in the "portable contract + thin per-harness adapter" model; turns the kit's own session transcripts into MP-3b's calibration corpus.
- **MP-3b — the behavior→tier loop** (`#75`): `scripts/agent-scorecard.sh` groups traces by agent, computes behavior metrics over a window, classifies each agent `regressed | steady | earned` against its **own trailing baseline**, and emits the **asymmetric** tier directive — fail-safe **auto-downgrade** on regression, **Security-owner-ratified raise** recommendation on earned improvement. Operationalizes the agent-quality-metrics → autonomy-adjustment §13 already names. §13 pointer (a `+0` append) + `agentic-ops-readiness.md` row 6.
- **Kit-CI smokes** (`#76`, `#77`): `agent-trace.sh` and `agent-scorecard.sh` `--selftest` run in the kit's own pipeline.

### Honesty / engineering notes
- **The kit emits directives; it never actuates** — it never mutates `.claude/`, the guard, or any tier store; the adopter wires the directive into their enforcement plane (the standing "real boundary is platform-owned" stance).
- **`unknown` = missing, never zero** — an agent is never downgraded on absent data; thin data (`< min-runs`) → `steady`/no-directive (fail-safe).
- **Relative-to-self, locally calibrated, no data pooling** — thresholds compare an agent to its own history; calibration is local to each adopter; the kit never phones home or pools agent-behavior data (a deliberate privacy property).
- **No new blocking gate** — behavior is trend-scored, not run-gated; the tools fail no PR (enforcement is the tier, via the adopter's plane). Each slice's independent review hardened it (MP-3a.2: timestamp-less-crash + path-traversal; MP-3b: two silent-drop bugs) before SHIP.

## [2.55.0] - 2026-06-12

Profile-depth: **deployable artifacts**. Closes the measured gap where only `typescript-node` shipped drop-in container/deploy companions — now **all 6 other service stacks** do, and the 3 non-service stacks document why they don't. **MINOR** — additive reference artifacts + a CI lock; the image gates were already in the contract (`conformance/container-supply-chain.sh`), so no new required gate. Shipped as four ratified PRs (#68 batch A, #69 batch B, #70 batch C, #71 kit-CI lock), each independently security-reviewed (builder ≠ sole reviewer) → SHIP.

### Added
- **Container/deploy companions for the 6 service stacks** (`go`, `rust`, `python`, `java-spring`, `kotlin`, `dotnet`): a stack-appropriate multi-stage non-root `Dockerfile` + `.dockerignore`, a `compose.yaml` (app + Postgres, §13 dev/prod parity), and a `deploy/` reference (k8s manifests + Helm chart) mirroring `profiles/typescript-node/`. Each wires the conditional container image supply-chain into `ci.yml`: `gate-image-sbom` (Syft/CycloneDX, on PR) + a push-only `image-provenance` job attesting provenance **bound to the image digest** (`gate-image-provenance`).
- **Reference-pointers for the 3 non-service stacks** — `ml` (model-serving / batch image), `data-engineering` (orchestrated job / code-location image), and `terraform` (**N/A by design** — `plan`/`apply` *is* the deploy) document the pattern in §9 instead of shipping a generic Dockerfile. Recorded as a convention in `MAINTAINING.md` §1.
- **`container-supply-chain.sh` wired into `conformance/verify.sh` (a control check) and the kit's own `.github/workflows/ci.yml`** — the new Dockerfiles are regression-guarded on every push/PR (multi-stage + non-root + both image gates; non-service profiles N/A).

### Honesty / engineering notes
- **Base images chosen for correctness, not uniformity:** python = `slim` **not distroless** (distroless-python tracks Debian's 3.11 and would silently downgrade the declared 3.12); `go` = distroless/static, `rust` = distroless/cc (glibc), JVM = distroless/java21, `dotnet` = chiseled aspnet (`USER 1654`).
- **No in-image HEALTHCHECK on distroless/chiseled** (java-spring, kotlin, dotnet) — they ship no shell/curl, so a HEALTHCHECK would be a claim that can't execute; k8s liveness/readiness probes (Actuator for Spring) are the health mechanism. Read-only root FS is paired with a writable `/tmp` emptyDir where the runtime needs it.
- **No devcontainer** for these stacks — distroless/chiseled have no shell to exec into; `compose.yaml` already delivers the §13 dev/prod-parity requirement.

## [2.54.0] - 2026-06-12

Modern Practices arc, Slice MP-2 — the developer inner loop, **with both MP-1 (test-quality) and MP-2 (inner-loop) tooling now completed across all 10 profiles + the template** (MP-1 had shipped them only to the python/typescript-node representatives). **MINOR** — guidance + per-stack profile tooling; no new gate.

### Added
- **`docs/operations/dev-inner-loop.md`** — the **three-tier feedback model**: **pre-commit** (format · lint · type-check · affected/fast test subset, seconds-fast, `--no-verify`-able) → **pre-push** (the agent guard) → **CI** (the authoritative §14 gate set). Layered, not redundant — fast checks on changed files locally; the full/slow gates in CI.
- **Per-stack test-quality + inner-loop tooling in all 10 profiles + `profiles/_TEMPLATE.md`** — mutation + property-based libs and a pre-commit inner loop, mapped to each stack (PITest/jqwik for JVM, Stryker.NET/FsCheck for .NET, cargo-mutants/proptest for Rust, go-mutesting/rapid for Go, etc.). For **data-engineering** and **terraform**, the existing `gate-data-quality` / `gate-policy` gates **are** the test-quality bar (mutation/property are N/A for SQL-dbt / HCL) — stated explicitly.
- **`MAINTAINING.md`** — a maintainer rule: cross-cutting per-stack tooling must reach **all** applicable profiles + the template, not just the representatives (recommended tooling isn't conformance-enforced, so piecemeal adds leave stacks thin).

### Honesty / agentic
- Pre-commit is a **recommended accelerator, not a gate** (gating it just trains bypass) — enforcement stays in CI + the guard. Tightens the agent's inner loop: faster feedback, fewer broken commits, less wasted CI.

## [2.53.0] - 2026-06-12

Modern Practices arc, Slice MP-1 — test quality beyond coverage. Adds the two practices the audit found genuinely absent, both especially relevant when **agents write the tests**. **MINOR** — guidance + STANDARDS principle + per-stack profile tooling; no new gate (mutation is too slow to gate every PR).

### Added
- **`docs/operations/test-quality.md`** — coverage ≠ quality. **Mutation testing** (injects bugs, checks the suite catches them; the honest test-quality signal — "green ≠ verified" applied to the suite itself; the reliable catch for an agent that gamed the coverage gate with assertion-light tests; run on critical paths / nightly, not every PR). **Property-based testing** (generative inputs find edge cases a human or agent didn't write). Per-stack tools for both.
- **`DEVELOPMENT-STANDARDS.md` §7** — a Test-quality principle (coverage = execution, not assertion strength) + a Property-based row in the testing pyramid.
- **Profile tooling** — `profiles/python.md` (`hypothesis` + `mutmut`/`cosmic-ray`), `profiles/typescript-node.md` (`fast-check` + Stryker).

### Honesty
- Both are **recommended, not fail-closed gates** — a green coverage gate stays necessary but is **not sufficient** evidence of test quality. The kit names the principle and ships the tools; the team sets the cadence + critical-path scope.

## [2.52.0] - 2026-06-11

Safe Non-Prod arc, Slice SNP-2 — ephemeral / preview environments. **Closes the Safe Non-Prod arc** (and the deferred list from the feature-coverage analysis). Seeds from SNP-1 test data. **MINOR** — guidance + conditional check + RUNBOOK record.

### Added
- **`docs/operations/preview-environments.md`** — per-PR isolated-environment lifecycle (open → exercise → auto-teardown) + the security guardrails (safe data only · scoped short-lived creds · TTL/auto-teardown · isolation; never prod data or secrets).
- **`conformance/preview-env-ready.sh`** + **`preview-environments-readiness.md`** — conditional, fail-closed check (binds on a **deploy surface**: Dockerfile or deploy workflow) asserting the RUNBOOK §4 records the preview-env approach; N/A for non-deployable. `verify.sh` now **8 doc-checks**.
- **`DEVELOPMENT-PROCESS.md`** §9 gains an ephemeral-preview-environments contract; **`templates/RUNBOOK-TEMPLATE.md`** §4 records the approach.

### Honesty
- A green check proves the approach is **recorded**, never that previews *actually* spin up / tear down / isolate / exclude prod data — those stay Manual operator rows. Conditional + proportional: non-deployable → N/A; recommended-not-required (a tiny tool may record N/A-with-reason). Records the colon-adjacent record-line lesson from SNP-1 (fresh→FAIL and filled→OK both verified).

## [2.51.0] - 2026-06-11

Safe Non-Prod arc, Slice SNP-1 — cross-stack test-data management. Closes the "never use prod data unsanitized — but *how*?" gap with a stack-neutral pattern + a light conditional check. The foundation preview environments (SNP-2) will seed from. **MINOR** — guidance + conditional check + RUNBOOK record.

### Added
- **`docs/operations/test-data-management.md`** — stack-neutral patterns: the **classify-then-handle** rule (public ok · PII/children's → synthetic or masked, never raw prod), synthetic generation, anonymization/masking (mask-on-extract), deterministic seeds, and the anti-patterns.
- **`conformance/test-data-ready.sh`** + **`test-data-readiness.md`** — conditional, fail-closed check (binds on a **data surface**: DB url in `.env.example`, a migrations/prisma/alembic dir, or a DB service in compose) asserting the RUNBOOK §2 records the test-data approach (not the placeholder); N/A for pure-compute projects. Wired into `verify.sh` (now 7 doc-checks) + CI.
- **`templates/RUNBOOK-TEMPLATE.md`** §2 records the test-data approach; **`DEVELOPMENT-STANDARDS.md`** §7 gains a test-data principle.

### Honesty
- A green check proves the approach is **recorded**, never that the data is *actually* synthetic/masked or that no prod data leaked — those stay Manual rows. Conditional + proportional: non-data projects → N/A (zero overhead). US-aware: PII / children's data → masked or synthetic (COPPA-grade).

## [2.50.0] - 2026-06-11

Responsible-AI arc, Slice RAI-3 — AI-governance crosswalk + agentic-threat lens. **Closes the Responsible-AI arc.** **US-first**; **MINOR** — documentation only, no gate/script.

### Added
- **`docs/enterprise/ai-governance-crosswalk.md`** — US-first map of the kit's AI-governance controls + the RAI artifacts to **NIST AI RMF + GenAI Profile** (the practical US anchor + TX TRAIGA safe harbor), **ISO/IEC 42001** (clauses + Annex A), **US state law / COPPA / FTC**, and **OWASP LLM + Agentic Top 10 + MITRE ATLAS**. The **EU AI Act** is a fenced optional overlay (only with EU market exposure; conformity-assessment / CE / FRIA / EU-DB are Org-owned, out of the US baseline). Sibling of `compliance-crosswalk.md` with the same honest `Responsibility` column.
- **Agentic-AI lens** on `templates/THREAT-MODEL-TEMPLATE.md` — an OWASP-Agentic-Top-10 (ASI01–10) subsection so an AI agent's threat model considers goal-hijack, tool-misuse, identity abuse, memory poisoning, human-trust exploitation, and rogue-agent behavior, each pointing at the kit control that mitigates it. N/A for non-agent features.

### Honesty
- The crosswalk **shows its own edges**: agentic-threat coverage is reported truthfully — **5 of 10 fully covered, 3 partial, 2 platform-owned gaps** (memory poisoning, inter-agent comms) — not a rounded-up number. ISO 42001 *certification* and state-law *legal determination* are **Org-owned**; the kit provides the evidence, not the compliance program.

### Arc closed
- The Responsible-AI arc (RAI-1 System Card · RAI-2 fairness + transparency · RAI-3 crosswalk + agentic lens) completes the third AI-governance axis — *is the AI fair, disclosed, human-overseen, risk-classified, and mappable to US regimes?* — alongside the existing eval gate (*is it good?*) and threat-model (*how is it attacked?*).

## [2.49.0] - 2026-06-11

Responsible-AI arc, Slice RAI-2 — fairness eval + AI-output transparency. The two genuine content gaps from the arc design, plus the good-citizen AI-incident feedback loop. **US-anchored** (EEOC / NYC LL144 / CO-CA consequential-decision; CA SB 942 / AB 2013 / COPPA-FTC; EU Art. 10/50 optional overlays). **MINOR** — additive templates; **no new gate or conformance script** (all Manual, owner-verified).

### Added
- **Fairness / bias eval dimension** — `templates/EVAL-PLAN-TEMPLATE.md` gains a Fairness/bias section (protected dimensions, disparate-impact / four-fifths metric, owner review; N/A for non-human-subject features) + a Manual row in `conformance/eval-readiness.md`. Rides the existing eval wiring.
- **`templates/AI-TRANSPARENCY-SIGNOFF-TEMPLATE.md`** — AI-output disclosure record (AI interaction disclosed · synthetic content labeled · C2PA provenance · children's-audience disclosure); referenced from the AI System Card + the responsible-ai-readiness transparency row. No separate §7 gate row — folds into the AI System Card gate (no gate proliferation).
- **AI-incident feedback** — `templates/POSTMORTEM-TEMPLATE.md` names AI incidents (harmful output, jailbreak, bias) and feeds the failing case back to the EVAL-PLAN red-team set, closing the eval loop.

### Honesty
- Fairness and transparency are **Manual** (owner-verified) — the kit records the dimension is *declared/considered*, never that the AI is *actually fair* or the disclosure *actually shipped*. All additions are N/A-able; non-AI and non-human-subject features carry zero overhead. No new fail-closed check.

## [2.48.0] - 2026-06-11

Responsible-AI arc, Slice RAI-1 — the AI System Card. Closes the substantive AI-governance gap surfaced by the feature-coverage analysis: the kit had eval (*is the model good?*) and threat-model (*how is it attacked?*) but not *is it fair, disclosed, human-overseen, and risk-classified?* **US-first** (NIST AI RMF + GenAI Profile anchor; TX TRAIGA / CO SB 26-189 / CA ADMT / COPPA-FTC the real surface; EU AI Act an optional overlay). **MINOR** — conditional check + two templates; no new universal gate.

### Added
- **`templates/AI-SYSTEM-CARD-TEMPLATE.md`** — the per-AI-feature declaration: model+version, **US risk classification** (consequential-decision / children's-data / prohibited-use triggers; optional EU overlay), intended/out-of-scope use, data flows+consent, human oversight, guardrail links, known limitations, security/compliance-owner sign-off. Doubles as the ISO/IEC 42005 impact assessment.
- **`templates/AI-POLICY-TEMPLATE.md`** — one-page org AI policy (ISO 42001 Clause 5.2).
- **`conformance/responsible-ai-ready.sh`** + **`conformance/responsible-ai-readiness.md`** — conditional check (binds on an AI feature: `evals/`, `EVAL-PLAN`, `AI-SYSTEM-CARD`, or `AI feature: yes`) asserting the card is **present + classified + oversight-named**; N/A for non-AI. Wired into `verify.sh` + CI + a §7 gate row.

### Good-citizen guardrails (opt-in, never gated)
- Distilled the *substantive* best practices from EU AI Act (Arts. 10/12/14/15/50/72) + US state law into recommended template lines — **prohibited-use acknowledgment, data-minimization, human review/appeal path** — that the fail-closed check does **not** enforce. Lean into the good practice, skip the certification bureaucracy.

### Honesty
- A green check proves the card is **declared/classified/recorded**, never that the classification is *correct*, the AI is *fair*, or it is *compliant* — those stay Manual security/compliance-owner rows. Conditional + proportional: non-AI → N/A (zero overhead); low-risk = a two-line card. US-first: no EU-only burden (conformity assessment / CE / FRIA / EU-DB) in any baseline.

## [2.47.0] - 2026-06-11

Gate parity, Slice 2 — observability/SLO and threat-model get the declared-artifact treatment, **closing the gate-parity arc**. Both were named in prose but lacked an artifact: observability had no readiness check, the threat-model gate had no template. **MINOR** — one conditional check + two templates; no new universal gate.

### Added
- **`conformance/observability-ready.sh`** + **`conformance/observability-readiness.md`** — conditional check (binds on a deploy surface: Dockerfile or deploy workflow) asserting the observability posture is **recorded** — RUNBOOK §8 declares an `SLOs:` target and a `Telemetry wired:` signal set (not placeholders); N/A for non-deployed. Wired into `verify.sh` + CI. Mirrors the `resilience-ready` family.
- **`templates/THREAT-MODEL-TEMPLATE.md`** — STRIDE + LINDDUN-lite privacy lens + security-owner sign-off. Wired into the §7 security gate, the DoR threat-model flag, the templates list, and `DEVELOPMENT-STANDARDS.md` §2. **No conformance script by decision** — a script cannot tell a real threat model from a box-ticked one, and "sensitive" is not honestly auto-detectable.
- **`templates/RUNBOOK-TEMPLATE.md`** §8 now records SLOs + telemetry (the keyed phrases `observability-ready.sh` greps).

### Honesty
- Each readiness check proves the posture is **declared/recorded**, never that it **works** — signals emitting in prod, alerts firing, the error budget being tracked, and the threat model's *quality* stay **Manual** operator/security-owner rows. Necessary, not sufficient.

## [2.46.0] - 2026-06-11

Gate parity, Slice 1 — eval-driven development gets the kit's declared-artifact + conformance treatment. The AI-feature Eval gate was named in prose but lacked a template and a readiness check; this closes that. **MINOR** — additive template + conditional check; no new universal gate.

### Added
- **`templates/EVAL-PLAN-TEMPLATE.md`** — the AI-feature eval artifact (dataset + rubric, regression threshold, safety/red-team, pinned judge + model version, harness, model-upgrade-regression trigger).
- **`conformance/eval-ready.sh`** + **`conformance/eval-readiness.md`** — conditional check (binds on an AI-feature signal: `evals/` dir, `EVAL-PLAN.md`, or `AI feature: yes`) asserting the eval discipline is **declared** (plan + threshold + harness recorded); N/A for non-AI. Wired into `verify.sh` + CI.

### Honesty
- The readiness check proves the discipline is **declared**, never that the evals **pass** — execution stays the §7 Eval gate (CI runs the suite); red-team + judge-independence are Manual rows. Necessary, not sufficient.

## [2.45.0] - 2026-06-11

Task Context Contract (TCC) — declared per-step context envelope. Applies the kit's "declare the contract, make it inspectable" discipline to the build/dispatch layer: a qualifying agent step now carries a declared Reads (constraints/inputs) · Writes · Prohibitions contract, verified by the same reviewers. **MINOR** — additive template + tool-neutral process convention; advisory (no new gate), no behaviour change.

### Added
- **`templates/TASK-CONTEXT-CONTRACT-TEMPLATE.md`** — the four-sided contract + constraints-vs-material framing, the proportionality rule (full TCC on governing-surface OR security OR multi-file; one-line default otherwise), conflict precedence, the honesty note (declared ≠ obeyed), reviewer-binding, and a worked example.
- **`DEVELOPMENT-PROCESS.md`** — §12 "Context-bound dispatch" convention (tool-neutral; reviewer receives the same contract), §13 Auditability extended to record which governing clauses bound each action, §15 artifact-flow row.

### Notes
- **Advisory in v1** — no conformance drift-guard yet (added only once the format proves out). The self-improving "recurring-violation → promote" loop is a deferred fast-follow.
- Origin: evaluation of the ICM paper (arXiv:2603.16021v2), whose declared per-stage inputs + reference-vs-working distinction surfaced the gap. No new runtime dependency; superpowers remains authoring-only.

## [2.44.0] - 2026-06-11

Arc exit gate + secret.read remediation (A9 + Slice 11e — **Containment arc CLOSED**). The exit-gate red-team (A9) confirmed W3 closed-in-kit and W2 honestly-bounded, and caught one blocker: the MCP gate allowed `secret.read` tools (A8 family 6) despite A8 designating them deny-by-default. 11e closes it. **MINOR** — additive gate coverage + the A9 findings artifact.

### Added
- **A9 arc-exit red-team** — three adversarial red-teams (MCP gate / egress+containment honesty / cross-arc ledger); verdict: arc closes honestly once `secret.read` is gated. W3 → closed-in-kit; W2 → honestly-bounded/platform-owned.
- **`secret.read` gating** (`guard_check_mcp`, Slice 11e) — secret-material reads are now deny-by-default by **name**: an action naming a secret (`secret/credential/password/api_key/private_key/access_token…`) **or** a known secret-store server (`vault/1password/secretsmanager/keyvault/doppler…`) on a read → deny, even when a read verb leads. Restores A8 family 6. Corpus cases added; allowlist/override escape hatches preserved.

### Honesty
- The gate's honest ceiling is updated: a secret read via a **generic-named** server/action (`mcp__storage__read_blob` holding a credential) is **not** caught by name — the real controls are the platform egress allowlist + the 11c sandbox.
- **Carried residual:** attestation in `egress-policy.sh` / `containment-ready.sh` is honor-based (disclosed since 2.43.0); keep the Manual-row adjacency explicit in auditor-facing packaging.

### Containment arc — closed
W2 (no interpreter-egress control) → **honestly-bounded, platform-owned** (reference shipped + wiring verified three-state; in-process tail never claimed closed). W3 (guard saw only Bash-family tools) → **closed-in-kit** (MCP capability gate, deny-by-default incl. secret.read, Kit-enforced by name, regression-locked). No green check implies containment a shell can't deliver.

## [2.43.0] - 2026-06-11

Honesty & assurance restatement (Slice 11d — Containment arc). Reconciles the kit's narrative/summary docs to the post-11a/b/c reality and regression-locks the responsibility tiers. **MINOR** — docs + one drift-guard; no behaviour change.

### Added
- **`conformance/assurance-tiers.sh`** — drift-guard asserting the compliance crosswalk states each arc control at its real tier (MCP capability gate = **Kit-enforced**; egress / sandboxed FS / scoped tokens / separate prod creds = **Kit-assisted**); `--selftest`; wired into CI and `verify.sh` (live control).
- **MCP capability gate** now recorded in the compliance crosswalk + audit-evidence checklist as **Kit-enforced** (with the honest by-name caveat: it gates MCP tool capability by name; the net.egress class is a name-match speed bump).

### Changed
- `platform-safety-boundary.md`, `EXEC-BRIEF.md`, and `DEVELOPMENT-PROCESS.md` §13 reconciled: the guard is a speed bump for shell/interpreter **and** a deny-by-default MCP capability gate (Kit-enforced); the four platform controls are kit-referenced + verify-wired (**Kit-assisted**) — enforcement remains platform-owned. No caveat removed (no overclaim).
- `containment-readiness.md`: documented that attestation dates are honor-based (the carried 11c LOW — resolved by documentation; both candidate code fixes would false-negative).

### Honesty
- The restatement only **adds qualifiers**; every honest caveat (deny-list speed bump, "these four controls are the boundary", platform-owned enforcement) is preserved. "Kit-enforced" appears only for the MCP gate, always with the by-name caveat. The drift-guard verifies the tiers are *stated*, not "true".

## [2.42.0] - 2026-06-11

Sandbox + scoped-credential references + conformance (Slice 11c — Containment arc). Formalizes platform-safety-boundary controls #2/#3/#4 (sandboxed FS · scoped tokens · separate prod creds) as a declared, verifiable posture. **MINOR** — conditional three-state check + reference docs; no new universal gate.

### Added
- **`docs/operations/containment.md`** — reference: read-only-FS compose/devcontainer snippet, OIDC→role short-TTL token pattern, separate-prod-creds/break-glass pattern + how to attest.
- **`conformance/containment-ready.sh`** — one conditional three-state check over three sub-aspects (Sandbox FS / Scoped tokens / Prod credentials), overall = weakest aspect; UNVERIFIED escalates under CI/`--require`; `--selftest` corpus; CI-wired. Pairs with `conformance/containment-readiness.md` (Auto vs Manual).
- **RUNBOOK** containment attestation lines (`templates/RUNBOOK-TEMPLATE.md`).

### Changed
- Compliance crosswalk + audit-evidence: the three agent-boundary rows (#2/#3/#4) **Org-owned → Kit-assisted** (reference shipped + wiring verified). `platform-safety-boundary.md` notes each is now reference-shipped + verify-wired.

### Honesty
- The check **verifies declaration + attestation, never enforcement** — PASS ≠ "FS actually read-only / tokens actually expire / prod creds actually unreachable" (Manual rows). UNVERIFIED is a first-class non-pass; enforcement stays platform-owned.

## [2.41.0] - 2026-06-11

Egress-allowlist reference + conformance (Slice 11b — Containment arc, the honest W2). Ships a default-deny network-egress reference and verifies the platform control is declared + attested-wired. **MINOR** — conditional three-state check + reference docs; no new universal gate.

### Added
- **`docs/operations/egress-control.md`** — default-deny network-egress reference (k8s `NetworkPolicy` paved road + cloud-egress-firewall / forward-proxy patterns + how to attest).
- **`conformance/egress-policy.sh`** — three-state check (PASS declared+attested · UNVERIFIED declared-not-attested · FAIL networked-undeclared · N/A no-surface), escalating UNVERIFIED→FAIL under CI/`--require`; `--selftest` corpus; CI-wired. Pairs with `conformance/egress-readiness.md` (Auto vs Manual).
- **RUNBOOK** egress attestation line (`templates/RUNBOOK-TEMPLATE.md`).

### Changed
- Compliance crosswalk + audit-evidence: egress row **Org-owned → Kit-assisted** (reference shipped + wiring verified). `platform-safety-boundary.md` notes egress is now reference-shipped + verify-wired.

### Honesty
- The check **never inspects traffic** — PASS = declared + attested, not "packets are dropped" (a Manual row). Interpreter/DNS/build-tool exfil is impossible to gate in-process (A8 Part 2); enforcement stays platform-owned. UNVERIFIED is a first-class non-pass.

## [2.40.0] - 2026-06-11

MCP capability gate (Slice 11a — Containment arc). Closes W3: the guard now sees MCP tool calls and denies un-allowlisted destructive/egress MCP capabilities by default. **MINOR** — additive in-kit control + a portable contract; no universal gate added.

### Added
- **`guard_check_mcp`** (in `guard-core.sh`) — classifies `mcp__<server>__<action>` by action verb; read-only allowed, destructive/egress denied, **fail-closed** on the unclassifiable. The Claude PreToolUse matcher now routes `mcp__.*`; `.claude/mcp-policy.json` (control-plane-protected, shipped empty-allow) carries the per-project allowlist + classOverride; `kit-guard mcp` exposes the same gate to any runtime (the portable mcp-policy contract).
- **`conformance/mcp-policy.sh`** — classification corpus (deny destructive, allow read, honor allowlist/override, fail-closed). CI-gated; plus `agent-autonomy.sh` MCP live-path cases.

### Honesty
- The gate is **Kit-enforced for what the tool name reveals** — a renamed/obfuscated action is not caught, and the egress class is a name-match speed bump, **not** egress containment (the platform allowlist, 11b). Documented in `runtime-guards.md` + `platform-safety-boundary.md`.

## [2.39.0] - 2026-06-10

A7 residual cleanup (Slice 10). Clears the small backlog the arc-closure re-review surfaced. **MINOR** — additive checks/docs + one guard over-block lifted; no governance bar lowered.

### Added / Changed
- **`preflight.sh`** soft-recommends `gh` + auth for GitHub flows (warns, never fails — GitLab/ADO unaffected).
- **Solo/lite track** now sets `enforce_admins: false` so the owner admin-merge self-ratification actually works (flip to `true` with a second reviewer); the reference `BRANCH-PROTECTION.md` carries a solo note. Conformance unaffected (`branch-protection.sh` never asserted `enforce_admins`).
- **`tracker-contract.sh --deep`** introspects the Jira workflow and **verifies** the Only-Assignee transition condition (the atomic claim moves from *attested* to *verified*); three-state, fixture-tested.
- **Brownfield guide** instructs adding `.claude/settings.local.json` to the adopter's own `.gitignore`.
- **Guard:** lifted the over-block on the reversible `git commit --amend` (force-push / non-fast-forward / `reset --hard` stay denied); regression-locked by an `agent-autonomy.sh` allow-case.

## [2.38.0] - 2026-06-10

Core-doc trim (Slice 9k-b, fast-follow of 9k). A measurement-first pass that **confirmed the core governing docs were already lean** (the Slice 9 arc had added only ~39 lines to the core-3, and the economics win was already banked by 9k's on-demand `AGENTS.md`), tightened the one doc with genuine cruft, and installed a ratchet so they can't silently re-bloat. **MINOR** — no governance content removed; every normative line, gate, and conformance marker preserved (proven by the full suite staying green).

### Changed
- **`DEVELOPMENT-PROCESS.md`** (466→462 lines) — removed stale metadata, a non-normative aside, and a redundant re-listing of the conditional gates (the §7 table already annotates them); no section renumbered. **`DEVELOPMENT-STANDARDS.md`** and **`CLAUDE.md`** were reviewed and left unchanged — already tight, no safe cut without losing substance.

### Added
- **`conformance/doc-budget.sh`** — a per-doc + core-3 line-budget ratchet (CLAUDE.md ≤120, DEVELOPMENT-PROCESS.md ≤470, DEVELOPMENT-STANDARDS.md ≤310, core-3 ≤890); a future PR that re-bloats a core doc fails CI. Budgets raised only by a ratified PR. `--selftest`, CI-gated.

## [2.37.0] - 2026-06-10

Hosted-tracker bootstrap (Slice 9h, Tier 2 of the "Honest Assurance & Adoption Reach" arc). Turns hosted-tracker adoption from prose into a concrete setup artifact plus a contract verifier. **MINOR** — templates + an incept arm + a three-state conformance check; no API client shipped.

### Added
- **`templates/JIRA-SETUP-TEMPLATE.md`** — `incept --backlog jira` emits a project-stamped guide: the six §6 statuses, Size/Risk fields (not Story Points), and the step-by-step **Only-Assignee transition condition** (the server-enforced single-owner claim).
- **`templates/TRACKER-SETUP-TEMPLATE.md`** — convention-tier stub for github/ado/linear/gitlab (board = the six states; claim = assign-when-empty + re-read).
- **`conformance/tracker-contract.sh`** — three-state Jira §6 verifier: live REST checks the states + Size/Risk fields, **UNVERIFIED (exit 2)** without creds, `--selftest` proves the logic in CI. The Only-Assignee condition is **attested, not auto-verified** (honest about REST's limits).

### Changed
- **`scripts/incept.sh`** now writes the matching setup artifact for the chosen backend (`md`→BACKLOG.md unchanged).
- **`docs/work-tracking/adapters.md`** (Jira) points at the bootstrap + verifier.

## [2.36.0] - 2026-06-10

Best-practice fidelity (Slice 9j, Stage V of the "Honest Assurance & Adoption Reach" arc). Declares the kit's SLSA level, adds a NIST SSDF crosswalk, formalizes a11y/load/eval as conditional gates, and makes the reference pipeline satisfy its own SHA-pinning contract. **MINOR** — the a11y/load/eval fork resolved in favor of *honest conditional gates*, not a new universal gate, so no MAJOR.

### Added
- **SLSA Build L2 declaration** (`DEVELOPMENT-STANDARDS.md` §14) — authenticated, service-generated provenance bound to the artifact/image digest; the honest L3 path documented (not claimed).
- **NIST SSDF (SP 800-218) column** in `docs/enterprise/compliance-crosswalk.md`, alongside SOC 2 + ISO 27001:2022.
- **Commit & tag signing** subsection (`DEVELOPMENT-STANDARDS.md` §2) — Sigstore `gitsign` / GPG, recommended hardening (not a gate).
- **`conformance/conditional-gates.sh`** + **`conformance/action-pinning.sh`** drift-guards (`--selftest`), CI-gated.

### Changed
- **a11y / load / eval formalized as conditional gates** (§7 + §14 + DoD): first-class but trigger-bound (UI / service / AI), N/A-with-reason otherwise — not universal. No new universal required gate.
- **`profiles/typescript-node/ci.yml`** now SHA-pins every `uses:` (with `# vX` comments; Dependabot keeps them current) — the canonical reference satisfies its own pinning contract.

## [2.35.0] - 2026-06-10

Economics & hygiene (Slice 9k, Stage V of the "Honest Assurance & Adoption Reach" arc). A load-first agent brief, one canonical home per governance concept, and a self-healing version badge. **MINOR** — additive brief + two completeness checks + label-only doc edits; no governing rule changed.

### Added
- **`AGENTS.md`** — a ≤1-page load-first operating brief (loop · gates · security · agent boundary · stack), each with a §-pointer; an index that defers to `CLAUDE.md`. Instructs agents to expand a full doc only when the task touches it — turning the standing per-feature governance load into an on-demand pull.
- **`conformance/badge-version.sh`** — asserts the README badge equals `VERSION`; `--fix` rewrites it; `--selftest`. The release flow calls `--fix`, ending the recurring badge drift (was 10 versions stale).
- **`conformance/agents-brief.sh`** — keeps `AGENTS.md` a brief: exists, points at the canonical docs, within a line-bound; `--selftest`.

### Changed
- **One canonical home per concept:** the §7 Definition-of-Done gate now points at `CLAUDE.md` (its real home); the `CLAUDE.md` security section is labeled the authoritative summary and `DEVELOPMENT-STANDARDS.md` §2 its expansion — the layering is explicit, no rule changed.
- **README version badge** synced to the current release (no longer stale).

## [2.34.0] - 2026-06-10

Definition-of-Ready robustness (Slice 9i-b, fast-follow of 9i). Promotes the DoR from a scattered parenthetical to a first-class enumerated entry gate, peer to the DoD. **MINOR** — additive block + template checklist + a completeness check; the Definition of Done is unchanged.

### Added
- **`CLAUDE.md` — `## Definition of "Ready"`** entry gate above the DoD: 4 mandatory items (acceptance criteria · INVEST-sliced · deps known · success metric/hypothesis) + 4 conditional flags that map to existing §7 gates (threat-model / UX-a11y / eval / compliance). Frames DoR (entry) vs DoD (exit).
- **`templates/FEATURE-REQUEST-TEMPLATE.md` — `## Definition of Ready`** checklist so an item is filled-to-ready at intake.
- **`conformance/dor-defined.sh`** — completeness drift-guard (DoR enumerated in `CLAUDE.md` + referenced by the gate doc + carried by the intake template); `--selftest`. CI-gated.

### Changed
- **`DEVELOPMENT-PROCESS.md` §7/§11/§4** DoR references now point at the canonical `CLAUDE.md` entry gate (no list duplication).
- **`templates/BACKLOG-TEMPLATE.md`** "Ready" column points at the enumerated DoR.

## [2.33.0] - 2026-06-10

Persona symmetry (Slice 9i, Tier 2 of the "Honest Assurance & Adoption Reach" arc). Closes the SDLC-personas finding (review 6/10): QA and Designer were named with "→ exit artifact" promises that dissolved. **MINOR** — additive templates + annotations + a completeness check; no new DoD requirement.

### Added
- **`templates/TEST-PLAN-TEMPLATE.md`** — QA's dedicated artifact (scope, levels, cases↔acceptance-criteria traceability, environments, entry/exit).
- **`templates/UAT-SIGNOFF-TEMPLATE.md`** / **`templates/A11Y-SIGNOFF-TEMPLATE.md`** — auditable per-gate sign-off records (signer/date/gate/evidence/decision; the a11y one carries the WCAG 2.1 AA checklist + axe/Lighthouse evidence).
- **`conformance/persona-artifacts.sh`** — completeness drift-guard (templates exist + named in the §2 persona table); `--selftest`. CI-gated.

### Changed
- **`DEVELOPMENT-PROCESS.md` §2 persona table annotated** dedicated-vs-shared (PO/QA/Designer own dedicated artifacts; DevOps/SRE works through the RUNBOOK) — the asymmetry is now explicit, not over-promised. §9 UAT gate and §5 Designer lens reference their sign-off records.
- **`CLAUDE.md` DoD Accessibility line** names `A11Y-SIGNOFF` as its auditable evidence (no new requirement).

## [2.32.0] - 2026-06-10

Stack-decision aid (Slice 9g, Tier 2 of the "Honest Assurance & Adoption Reach" arc). Closes the stack-undecided persona (review 5/10): the "⭐ key step" now has comparison material, and `incept` no longer silently defaults. **MINOR** — additive docs + a notice + a completeness check.

### Added
- **`docs/STACK-SELECTION.md`** — comparison matrix across all 10 profiles (Best for / Avoid when / domain), per-stack blurbs, and full-stack (SPA + API) / polyglot guidance.
- **`## Best for / Avoid when`** sections in all 10 `profiles/<stack>.md`, each pointing at the guide.
- **`conformance/stack-selection.sh`** — completeness drift-guard (guide present · every profile has the section · a matrix row per profile); `--selftest`. CI-gated.

### Changed
- **`incept` no longer silently defaults the stack** — prints a loud notice + the guide pointer when no `--stack` is given (the default still works; automation unaffected).
- `START-HERE.md` §2 and `README.md` link the decision aid; `conformance/README.md` indexes the check.

## [2.31.0] - 2026-06-10

Beginner on-ramp (Slice 9f, Tier 2 of the "Honest Assurance & Adoption Reach" arc). Closes the lowest-scoring review persona (beginner, 4/10), aimed by the A6 dogfood: the mechanical bootstrap was already fine; the friction was cognitive. **MINOR** — additive script + docs.

### Added
- **`scripts/preflight.sh`** — fail-fast prerequisite check (universal jq/git/sh always; optional `--stack <name>` toolchain) with install hints; `--selftest`. `incept` runs it at startup and aborts on a missing universal prerequisite.
- **`GLOSSARY.md`** — one-page launchpad for the ~12 load-bearing terms, each linking to its authoritative section.
- **Solo / lite track** in `START-HERE.md` — how one person satisfies builder≠reviewer (owner admin-merge as logged self-ratification) and which gates are deferrable at Stage 1.

### Changed
- **`incept` discloses the `CLAUDE.md → ENGINEERING-PRINCIPLES.md` rename** (banner) — closing A6 finding F2.
- `START-HERE.md` / `README.md` point newcomers at preflight + the glossary; `conformance/README.md` indexes the preflight selftest (CI-gated).

## [2.30.0] - 2026-06-10

Exec brief + org rollout + ROI model (Slice 9e, Tier 1 of the "Honest Assurance & Adoption Reach" arc). Closes the review's eng-leader finding — credible audit substance but no leadership front door. **MINOR** — additive docs; no new conformance gate (an exec brief is not a verifiable control).

### Added
- **`docs/enterprise/EXEC-BRIEF.md`** — ≤2-page VP/CTO entry point: what / why / what-you-get, A5-grounded differentiation, honest boundaries, compliance-at-a-glance, pointers.
- **`docs/enterprise/ORG-ROLLOUT.md`** — Pilot→Expand→Fleet adoption, the canonical **Stage 1–4 "tighten at scale"** maturity model, and the fleet version-upgrade process.
- **`docs/enterprise/ROI-MODEL.md`** — parameterized ROI worksheet (adopter inputs + three value levers) and one labeled worked example; honest "planning model, not a result" framing.
- **Competitive benchmark** — the A5 record behind the brief's differentiation (with sources).

### Changed
- Leadership cross-links from `README.md` / `START-HERE.md` / `docs/enterprise/README.md`.
- **Fixed the dangling "Stage 1–4" reference**: `DEVELOPMENT-PROCESS.md` and `docs/operations/dora-metrics.md` now point at the canonical model in `ORG-ROLLOUT.md`.
- **Anonymized** remaining shippable references (ROADMAP goal line + owner) to a generic regulated-enterprise archetype.

## [2.29.0] - 2026-06-10

Runtime-guard portability (Slice 9d-b, Tier 1 of the "Honest Assurance & Adoption Reach" arc). The destructive-action guard previously protected only the Claude Code runtime; now the red-teamed deny-matrix is a sourceable single source of truth reused by a universal git pre-push hook and a `kit-guard` CLI, so other runtimes and humans inherit the same denials. **MINOR** — additive; the Claude path is proven behavior-identical, no new universally-required CI gate.

### Added
- **`.claude/hooks/guard-core.sh`** — the deny-matrix as pure functions (`guard_check_command` / `guard_check_path` / `guard_check_push`) + the 9b control-plane helpers. Single source of truth.
- **`hooks/pre-push`** — universal git hook (any runtime + humans): blocks force-push / push-to-main from real refs, before the network round-trip; `--no-verify` is the deliberate override. `--selftest`.
- **`scripts/kit-guard`** — portable CLI (`cmd` / `path` / `--selftest`) any non-Claude runtime pipes proposed actions through.
- **`conformance/guard-core-sourced.sh`** — proves every consumer sources the one core (anti-fork).
- **`docs/operations/runtime-guards.md`** — one matrix, three surfaces; runtime wiring; Windows = WSL/Git-Bash; PATH-shims named as the coverage-depth upgrade; honesty boundary.

### Changed
- **`.claude/hooks/guard.sh`** slimmed to a thin Claude PreToolUse adapter over `guard-core.sh`; behavior proven identical via `conformance/agent-autonomy.sh`.
- **`scripts/incept.sh`** installs the pre-push hook by default (brownfield-safe; never clobbers an existing hook).
- **`conformance/agent-autonomy.sh`** denies edits to the new control-plane files (guard-core / kit-guard / pre-push); kit CI gates the three new selftests.

## [2.28.0] - 2026-06-09

CI-platform portability (Slice 9d, Tier 1 of the "Honest Assurance & Adoption Reach" arc). Closes the review's convergent finding #3: the kit assumed **GitHub Actions** — `ci-gates.sh` only recognized GitHub `id: gate-X` syntax and `incept.sh` hardcoded `.github/workflows/ci.yml`, so a GitLab or Azure-DevOps adopter had to rewrite all CI and could never pass conformance. The contract was always the gate-ids; only the matcher and the reference were GitHub-bound. **MINOR** — additive matcher branch, a new reference, a new flag, and docs (no new universally-required gate; existing GitHub workflows are unaffected). The companion **9d-b runtime-guard portability** (extracting the guard deny-matrix into a runtime-agnostic core) is split out to its own slice — it edits the control-plane `guard.sh` and is human-gated at the terminal.

### Added
- **`profiles/typescript-node/ci.gitlab-ci.yml`** — a real GitLab CI reference expressing the same 8 gate-ids as GitLab job keys (`gate-lint:`, `gate-test:`, …), using the ts-node toolchain; comments name the GitLab-native equivalents (Secret-Detection / Dependency-Scanning / CycloneDX templates). Passes `ci-gates.sh`.
- **`scripts/incept.sh --ci github|gitlab`** — wires the matching platform reference: `github` → `.github/workflows/ci.yml` (unchanged default); `gitlab` → `.gitlab-ci.yml` at the repo root plus `.gitlab/CODEOWNERS`. Validates the value before any mutation; the post-inception branch-protection hint is now platform-aware.
- **`docs/operations/ci-platforms.md`** — the portability reference: the gate-id contract as the platform-neutral interface, how to express it on GitHub / GitLab / Azure DevOps (documented mapping, with the ADO step-name identifier caveat), and the **honest coupling note** — `branch-protection.sh` and `dora.sh` use the GitHub API; the GitLab/ADO equivalent is adopter-owned and reports UNVERIFIED rather than a false pass.

### Changed
- **`conformance/ci-gates.sh`** now recognizes a gate declared **either** as a GitHub Actions `id: gate-X` step **or** a GitLab CI `gate-X:` job key (line-anchored, comment-excluded — same anti-false-positive discipline). No behavior change for existing GitHub workflows. Header updated; the contract is the gate-ids, the platform is open.
- **Tie-ins**: `DEVELOPMENT-STANDARDS.md` §14 conformance line (gates declared by id on any CI platform → `ci-platforms.md`) and the `conformance/README.md` `ci-gates.sh` index row (recognizes GitHub + GitLab).

## [2.27.0] - 2026-06-09

Brownfield ratchet & waiver (Slice 9c, Tier 1 of the "Honest Assurance & Adoption Reach" arc). Closes the brownfield persona's P0: a legacy repo that already fails the gates had no sanctioned path to adopt — it could only abandon the kit or silently disable gates. Now adoption is a tracked, time-boxed, owned **governed exception**, not "comply or fake it". **MINOR** — additive templates/scripts/docs.

### Added
- **`templates/WAIVER-REGISTER.md`** — operationalizes the governed-exception process for adoption. Per-waiver: gate · reason · owner · opened · expires · remediation plan · ratified-by. States the **non-negotiable set** (`secret-scan`, `branch-protection` — never waivable) and the **90-day max lifetime**.
- **`conformance/waivers-valid.sh`** — validates a register: FAILs on expired, non-negotiable-gate, over-90-day, or missing-field waivers; N/A-pass without a register (adoption-conditional). Portable dates (GNU/BSD); `--selftest` (7 cases).
- **`scripts/coverage-ratchet.sh`** — stack-neutral "no-regression-below-baseline": pass your current coverage number, gate on *no drop* below a committed `.coverage-baseline` (seeded on first run) instead of an absolute-80% wall on day one. `--selftest`.

### Changed
- **`docs/adoption/brownfield.md` §5 "Adopting when you already fail the gates"** — the ramp: non-negotiable-vs-deferrable gate tiers, baseline-then-tighten, the waiver register + ratchet workflow, and a recommended tightening schedule.
- **Contract tie-ins**: `DEVELOPMENT-STANDARDS.md` §14 (gates blocking EXCEPT under a tracked/expiring/ratified waiver — never silent) and `DEVELOPMENT-PROCESS.md` governed-exceptions (→ the brownfield register). `conformance/README.md` index row.

## [2.26.0] - 2026-06-09

Conformance honesty — "green ≠ verified" (Slice 9a, the other Tier-0 item of the "Honest Assurance & Adoption Reach" arc). Closes the review's convergent finding #1: conformance checks that pass on documentation/declaration, and a `branch-protection.sh` that silently passed when it could not verify. **MINOR** — additive surfacing + a check behavior change (no new universally-required CI gate).

### Added
- **`conformance/verify.sh`** — an honest aggregate runner. Classifies every check **[control]** (verifies a working/remote control) vs **[doc]** (verifies documentation / recorded evidence exists, NOT that it was tested), prints a footer stating exactly what a green run does and does not prove, and gates only on **control** failures (and on UNVERIFIED under `--require`/CI). Deterministic `--selftest`.
- **`conformance/README.md` "What a green run means — and doesn't"** section + a `verify.sh` index row — the control-vs-documentation taxonomy is now first-class.

### Changed
- **`conformance/branch-protection.sh` is now three-state** (was: silent `exit 0` "Informational" when it could not verify): `exit 0` verified-protected · `exit 1` verified-unprotected · **`exit 2` UNVERIFIED** (no `gh`/remote) — never a silent pass. In CI (`CI` env) or with `--require`, UNVERIFIED escalates to FAIL. Cleaner messaging for the "Branch not protected" (404) and "not readable" (token lacks repo-admin) cases. Adds `--selftest`.

### Note
Behavior change: adopters who ran `branch-protection.sh` in a local `&&` chain expecting `exit 0` when `gh` is absent will now get `exit 2` (UNVERIFIED). That is the fix — a silent pass was the bug.

## [2.25.0] - 2026-06-09

Runtime-safety hardening & honest reframe (Slice 9b — first slice of the "Honest Assurance & Adoption Reach" arc). An adversarial red-team of the agent guard found it **~16% effective and self-disabling** (183 payloads → 111 confirmed bypasses); this slice raises empirical effectiveness to **~91%** on the red-team battery, makes the guard protect its own integrity, and corrects the docs that oversold it. **MINOR** — additive guard coverage + new docs; no new universally-required CI gate.

### Added
- **Hardened deny-list** in `.claude/hooks/guard.sh`: non-rm destruction (`truncate`/`dd of=`/`shred`/`mkfs`/`wipefs`/`blkdiscard`/`find -delete`/`rsync --delete`/`git clean`/redirect-truncation/`mv →/dev/null`); **scalpel `rm`** (denies globs, data-file extensions, absolute paths, dotfiles-of-record while keeping plain `rm stale.txt` allowed); obfuscation-technique denial (`<decode> | sh`, `eval $(…)`, `git -c … push` indirection); **partial** exfiltration denial (`scp`/`sftp`/`curl`-upload/`wget --post-file`/`nc`/`rclone`/`mail`, honestly labelled partial); cloud/infra **capability families** (`terraform destroy`, `*-delete`/`terminate-*` across aws/gcloud/az, `helm uninstall`, `kubectl drain`, DB `drop` via clients/migration tools).
- **Best-effort self/control-plane protection** (not absolute — see residuals): no agent `Bash`/`Write`/`Edit`/`NotebookEdit` may modify `guard.sh`, `settings.json`/`.local`, `.github/workflows/`, `CODEOWNERS`, or `.git/` internals via the common verbs/paths — fixes the `NotebookEdit` `notebook_path` blind spot. Post-review hardening closed `git config core.hooksPath`, `git checkout/restore` of the guard, path-normalization tricks (`//`, `/./`, `..`, basename), and parent-directory ops (`mv .claude`, `chmod -R`, `rmdir`). Human-only `KIT_GUARD_SELFEDIT=1` maintenance escape (an agent cannot set it; the hook process env is human-controlled).
- **`docs/enterprise/platform-safety-boundary.md`** — the Org-owned *real* boundary (network-egress allowlist, separate prod credentials, sandboxed FS, scoped tokens), mapped into `compliance-crosswalk.md`.
- **Regression corpus**: `conformance/agent-autonomy.sh` extended with the red-team bypasses (deny) plus over-block guards (allow) and a self-protection block — locking the fix in CI.

### Changed
- **Honest reframe** of the guard across its header, `.claude/README.md`, and `DEVELOPMENT-PROCESS.md` §13: a **best-effort speed bump for honest mistakes, not a security boundary**. The real boundary is platform-owned.

### Known residuals (by design — the deny-list tail)
- **Interpreters** (`python3 -c`, `node -e`) are not pattern-blockable — they can both **exfiltrate** data *and* **delete/rewrite the guard itself** (self-protection is best-effort, not absolute). The control is the platform sandbox + egress allowlist (Layer 3).
- **Variable-indirection obfuscation** (`X=rm; $X -rf`) is a *deliberate* evasion; the guard targets honest mistakes — deliberate evasion is the platform boundary's job.

## [2.24.1] - 2026-06-09

Doc-coherence closeout — a holistic consistency pass after the Slice 8 arc (v2.19.0–2.24.0). Orientation-layer-only; no contract, behavior, or mechanism change. The kit's first **PATCH** release (corrections, not new capability).

### Fixed
- **README version badge** `v1.0.0` → `v2.24.0` (it had drifted from `VERSION`).
- **Doc-set tables** (`README.md`, `CLAUDE.md`) now list `docs/operations/` (progressive delivery · resilience verification · DORA) and `docs/continuity/` (backup-restore drill · BIA) — previously undiscoverable from the entry-point docs — and add the `BIA` template (shipped in 8c) to the templates list.
- **`DEVELOPMENT-PROCESS.md` §8 conditional-gates clause** — replaced the strained "respectively" 1:1 mapping (7 gates, 5 work-types) with an explicit each-applies-where-it-fits mapping.
- **`DEVELOPMENT-PROCESS.md` §16 quick-reference GATES line** — added the four Slice-8 conditional gates ([15-factor] · [deployable] · [DR] · [resilience]).
- **`conformance/definition-of-deployable.md`** row 11 — qualified the bare `§15` as `DEVELOPMENT-PROCESS.md §15` (disambiguated from the new `DEVELOPMENT-STANDARDS.md` §15 Incident Response added in 8a).
- **`conformance/README.md`** — explained the escalate-only (`dr-ready.sh`) vs plain-N/A (`deployable-ready.sh` / `resilience-ready.sh`) distinction (N/A weight matches blast radius).

### Note
PATCH (2.24.1): documentation coherence only. No `VERSION`-gated behavior, no new gate, no contract change. The continuity & safe-delivery arc (Slice 8) remains complete.

## [2.24.0] - 2026-06-09

Slice 8f — DORA metrics collection. Sixth and final sub-slice of Slice 8 (continuity & safe-delivery hardening). Closes gap C1 (DORA defined but not instrumented). **Completes Slice 8.**

### Added
- **`docs/operations/dora-metrics.md`** — a collection reference: per-metric GitHub data source + derivation (incl. the adopter-wired change-failure rate / MTTR / retro-closure), the **§9 maturity-gating path** (the home for DORA enforcement — opt-in at scale), and a dashboard pattern. DORA is a feedback instrument, not a gate.
- **`scripts/dora.sh`** — a real collector for the **GitHub-derivable subset** (release cadence, PR lead time, review latency) via `gh` (gh's built-in `--jq` for date math; no separate `jq`). **Degrades gracefully** — any `gh` failure prints "unavailable" and the script still **exits 0** (a report never fails a pipeline) — and names deploy-freq-proper / change-fail / MTTR / retro-closure as adopter-wired. A `--selftest` asserts the no-`gh` degradation path.
- **Kit CI** smokes the collector (`dora.sh --selftest`) — proves it executes + degrades, never gates on the numbers.
- **`DEVELOPMENT-PROCESS.md`** §14 references the doc + collector; §9 cross-references the DORA change-fail / MTTR maturity-gating.

### Note
MINOR (2.24.0): additive — a reference + a report script + a CI smoke. **No new conformance gate**: DORA-value-gating is deliberately a §9 maturity step, not a baseline (a presence check would be theatre; a value-gate baseline would punish early-stage projects). No new CI gate-id; §14's gate set unchanged. **This release completes Slice 8** (incident response · definition of deployable · DR/backup-restore · resilience+load · progressive delivery · DORA).

## [2.23.0] - 2026-06-09

Slice 8e — Progressive-delivery reference + smoke gates. Fifth sub-slice of Slice 8 (continuity & safe-delivery hardening). Closes gaps B2 (progressive delivery had no reference) + B3 (post-deploy smoke verification was thin). The reference leg of a triad whose contract (§10) and conformance (8b Definition of Deployable) already shipped.

### Added
- **`docs/operations/progressive-delivery.md`** — a stack-neutral reference: staged / canary / blue-green strategies; **smoke gates at every promotion boundary** (lower-env → the canary/green slice *before* widening → post-full-rollout); automated canary analysis tied to SLOs / error budget (§9); rollback. Tooling (Argo Rollouts / Flagger / flag-driven) named Org-owned.
- **`DEVELOPMENT-STANDARDS.md` §14** — the `deploy-prod` reference now shows **deploy → smoke → rollback-on-fail** (the `if: failure()` step makes it a gate, not a log).

### Changed
- **`conformance/definition-of-deployable.md`** — the smoke row is tightened from "smoke defined + result recorded" to "**post-deploy smoke gate wired (deploy → smoke → rollback-on-fail), and smoke run at each promotion boundary** incl. the canary/green slice before widening"; rows 5/6 reference the new doc. Rows stay Manual (behavioural). No script change.
- **`DEVELOPMENT-PROCESS.md` §10**, **`CLAUDE.md` DoD**, **`conformance/README.md`** reference the new doc.

### Note
MINOR (2.23.0): additive — a reference + a tightened checklist row. **No new conformance script**: a post-deploy smoke *gate* is a pipeline behaviour (step ordering + failure semantics) that a cross-stack YAML grep can't reliably detect, so it stays a Manual checklist row with a reference (honest enforcement, not theatre). No new CI gate-id; §14's gate set unchanged.

## [2.22.0] - 2026-06-09

Slice 8d — Resilience + load/soak verification. Fourth sub-slice of Slice 8 (continuity & safe-delivery hardening). Closes gap A3 (resilience principles + load/soak asserted but never verified). Chaos-engineering / SRE anchor.

### Added
- **`docs/operations/resilience-verification.md`** — a stack-neutral how-to: the fault-injection drill (breaker trips, retries back off, degrades gracefully) and the load/soak test (find the knee, catch leaks), with the isolated-env do-no-harm rule and "recorded ≠ passed".
- **`conformance/resilience-readiness.md`** — a conditional resilience checklist (Manual judgment rows + Auto record rows) with a "necessary, not sufficient" callout; verifies `DEVELOPMENT-STANDARDS.md` §4 + §6.
- **`conformance/resilience-ready.sh`** — a conditional, fail-closed companion: for a project with a deploy surface it asserts RUNBOOK §8 records a load/soak date and a fault-injection date (non-placeholder); otherwise N/A. Self-discloses scope (recorded ≠ actually resilient). `--selftest` battery. Stack-neutral (checks a dated record, not load-test tooling).
- **`DEVELOPMENT-PROCESS.md`** — a conditional **Resilience readiness** gate (§7).
- **`DEVELOPMENT-STANDARDS.md`** — §4 and §6 now point at the verification reference ("verify these — don't just assert them"); RUNBOOK §8 gains the resilience-record lines.
- **`audit-evidence-checklist.md`** — a resilience row (A1.2, A1.3 / A.8.6, A.8.16; Auto-conditional).

### Note
MINOR (2.22.0): additive — a conditional Review gate, a checklist, a record-script, and a reference. No new universally-required CI gate; no DoD anchor (proportionate — a resilience miss is a reliability risk caught at Review, not data loss). The 8 application gate-ids and §14 are unchanged.

## [2.21.0] - 2026-06-09

Slice 8c — DR / backup-restore drill + BIA-at-Inception. Third sub-slice of Slice 8 (continuity & safe-delivery hardening). Closes gap A2 (DR was prose-only — no reference, no drill proof, no criticality tiering, no BIA). NIST SP 800-34 anchor.

### Added
- **`docs/continuity/backup-restore-drill.md`** — a stack-neutral restore-drill reference: the isolated-env do-no-harm rule, the 6-step drill, RTO/RPO actuals, and "recorded ≠ passed".
- **`templates/BIA-TEMPLATE.md`** — a Business Impact Analysis (data inventory, criticality tiers, per-tier RTO/RPO, dependencies, max tolerable downtime). Produced at Inception for data-handling projects.
- **`conformance/dr-readiness.md`** — a conditional DR-readiness checklist (Manual judgment rows + Auto rows) with a "necessary, not sufficient" callout and an explicit "the script's N/A is advisory; this checklist applies regardless" note.
- **`conformance/dr-ready.sh`** — a conditional, fail-closed, **escalate-only** companion: for a project with a persistent-data surface it asserts a BIA exists, RUNBOOK RTO/RPO are filled (not placeholder), and a restore-drill date is recorded; otherwise N/A. Its `N/A` is **self-incriminating** (detection is conservative, so a miss never exempts a data project) and its success output self-discloses scope (documented + recorded ≠ tested). `--selftest` battery.
- **Tiered RTO/RPO** by data criticality — `DEVELOPMENT-STANDARDS.md` §10 + RUNBOOK §6 per-tier table.
- **BIA-at-Inception** — a `START-HERE.md` §6 step + a conditional Inception-Done line (data projects); `inception-done.sh` unchanged (a prompt, not a hard gate).
- **`DEVELOPMENT-PROCESS.md`** — a conditional **DR readiness** gate (§7); the §15 recurring item references the drill.
- **Definition of Done anchor** — "DR proven for data services" on the `CLAUDE.md` Production line, so a data service is not "done" without a passed DR-readiness check (backstops the Inception prompt).
- **`audit-evidence-checklist.md`** — a DR-drill row (CC7.5, A1.2 / A.5.29, A.8.13–14; Auto-conditional).

### Note
MINOR (2.21.0): additive — a conditional gate, a conditional DoD item (data services, like the existing AI-eval / accessibility DoD items), a template, and references. No new universally-required CI gate; the 8 application gate-ids and §14 are unchanged.

## [2.20.0] - 2026-06-09

Slice 8b — Definition of Deployable. Second sub-slice of Slice 8 (continuity & safe-delivery hardening). Closes gap B1 (release-readiness contract not enforced): converts §10's "every release declares its rollback path before it ships" into a conditional Release gate.

### Added
- **`conformance/definition-of-deployable.md`** — a conditional release-readiness checklist (Release gate, `DEVELOPMENT-PROCESS.md` §7) mixing **Manual** judgment rows (rollback tested, alerts wired, migration reversible) and **Auto** rows. Carries a "a green script is necessary, not sufficient" callout and *(documented)* / *(tested / wired)* row labels. OWASP DSOMM anchor.
- **`conformance/deployable-ready.sh`** — a conditional, fail-closed companion script: for a project with a deploy surface (Dockerfile / `environment:` workflow / deploy job) it asserts RUNBOOK has Deploy + Rollback sections and a smoke test is referenced; non-deployable projects skip-pass (N/A). Its success output self-discloses scope (documents present, **not** tested). A **`--selftest`** fixture battery (skip/OK/FAIL) regression-locks the positive path in CI.
- **`DEVELOPMENT-PROCESS.md` §7** — new conditional **Definition of Deployable** gate (deployable services; Release manager + reviewer); §4 Release and §10 rollback reference the checklist.
- **`templates/RUNBOOK-TEMPLATE.md`** — a smoke-test slot under §4 Deploy, so an incepted deployable project satisfies the new check.
- **`conformance/audit-evidence-checklist.md`** — a Release-readiness row (CC8.1 / A.8.31, A.8.32; Auto-conditional).

### Note
MINOR (2.20.0): additive — a **conditional** Release gate at a human checkpoint (like the threat-model / eval / 15-factor gates), not a new universally-required CI gate. The 8 application CI gate-ids and §14 are unchanged.

## [2.19.0] - 2026-06-09

Slice 8a — Incident Response standard + blameless postmortem template. First sub-slice of Slice 8 (continuity & safe-delivery hardening). Closes gap A1 (no incident-response standard + a dangling cross-reference).

### Added
- **`DEVELOPMENT-STANDARDS.md` §15 — Incident Response**: P0–P3 severity matrix, incident roles as functions (commander · comms · scribe; agents assist, a human commands), the detect→declare→mitigate→resolve→postmortem arc, and a blameless-postmortem requirement (P0/P1) whose action items route back into the loop. NIST SP 800-61 anchor; incident tooling named Org-owned.
- **`templates/POSTMORTEM-TEMPLATE.md`** — an eight-section blameless postmortem (summary, impact, timeline, root cause, detection, went well/didn't, action items, blameless statement).
- **`conformance/audit-evidence-checklist.md`** — an Incident-response row (CC7.3/7.4 / ISO A.5.24–A.5.28; Manual).

### Fixed
- The two **dangling cross-references** in `DEVELOPMENT-PROCESS.md` §8/§9 (lines 212, 225) that pointed at a non-existent STANDARDS incident-response section now cite `DEVELOPMENT-STANDARDS.md` §15. The artifact-flow Postmortem row links the new template.

### Note
MINOR (2.19.0): additive — a new standard section, a template, and reference fixes. No new required CI gate; no behavior change. §1–§14 of `DEVELOPMENT-STANDARDS.md` are unrenumbered (§15 appended).

## [2.18.0] - 2026-06-08

Slice 7f — Doc refresh & consistency. Final sub-slice of Slice 7 (adoption/safety hardening). Docs-only; no behavior or contract change.

### Changed
- **Ratification-role casing** normalized to the §2 "functions, not titles" convention (labels first-word-capitalized, prose lowercase) across `DEVELOPMENT-PROCESS.md` §13, `docs/enterprise/ratification-rbac.md`, and `conformance/audit-evidence-checklist.md`. (`CHANGELOG.md` history left untouched.)
- `README.md` now names all **10** shipped profiles (was 7); `README.md` "What's inside" and `CLAUDE.md` document-set tables refreshed to include the enterprise addendum and the current template/docs set.
- `conformance/README.md` describes the kit's own CI in the present tense and adds a note that `inception-done.sh` is *expected to fail at the kit root* (the kit is the template source, not an instantiated project) — also noted in the script header.

### Note
MINOR (2.18.0): documentation consistency only. **Completes Slice 7** (environments & prod safety, personas, containers, work-tracking, brownfield, doc refresh).

## [2.17.0] - 2026-06-08

Slice 7e — Brownfield adoption & `.claude/` hygiene. Fifth sub-slice of Slice 7. Makes the kit safely adoptable into an existing repo and enforces that the runtime guard is actually wired.

### Added
- **`conformance/guard-wired.sh`** — fail-closed check that the `.claude/` PreToolUse guard is actually registered and present. **Wired into `inception-done.sh`**, so no project (greenfield or brownfield) passes Inception with a dead guard.
- **`docs/adoption/brownfield.md`** — threat-model-first brownfield path: copy-in steps, the `.claude/` **merge** policy (add the guard, never overwrite; with explicit duplicate-key JSON guidance), Inception adapted, and honest residual gaps (pattern coverage + the Org-owned platform backstop).
- **`README.md` `.claude/` scoping** — project-level vs global `~/.claude/`; `settings.json` (committed) vs `settings.local.json` (gitignored). Dropping the kit affects only that repo, not the machine.

### Changed
- `conformance/inception-done.sh` now requires the guard to be **wired**, not just `.claude/` present.
- `scripts/incept.sh` **warns** (never modifies) when a `.claude/` without the kit guard is detected, pointing at the brownfield merge guide.
- `START-HERE.md` brownfield router row points at the adoption guide; `conformance/README.md` indexes `guard-wired.sh`.

### Note
MINOR (2.17.0): no new universally-required CI gate, no integration code, no breaking change. Brownfield inverts the kit's risk gradient (a legacy repo's blast radius pre-exists), so the guard-liveness check is the enforcement teeth behind the merge guidance.

## [2.16.0] - 2026-06-08

Slice 7d — Work-tracking adapter guidance. Fourth sub-slice of Slice 7. Lifts named backlog backends from "named" to "documented adapter."

### Added
- **`docs/work-tracking/adapters.md`** — contract-anchored mapping guide: per-tracker **state map · field map · atomic claim · fit notes** for `BACKLOG.md`, GitHub, Jira, **Azure DevOps**, Linear, **GitLab**, plus a "bring your own tracker" recipe. Guidance only — no integration code.
- **`conformance/backlog-adapters.sh`** — fail-closed drift lock: the named set must agree across `incept.sh --backlog`, `DEVELOPMENT-PROCESS.md` §6, and the guide.

### Changed
- `DEVELOPMENT-PROCESS.md` §6 names six backends (adds Azure DevOps + GitLab) and points at the guide; the §6 contract (states/fields/atomic-claim) is unchanged.
- `scripts/incept.sh` `--backlog` accepts `md|github|jira|ado|linear|gitlab`, validates the choice, and points non-`md` choices at the guide (still scaffolds only `BACKLOG.md`).
- `templates/PROJECT-CLAUDE-TEMPLATE.md` §3 names the six backends + the guide.
- `conformance/README.md` indexes `backlog-adapters.sh` and `container-supply-chain.sh` (the latter a 7c index omission).

### Note
MINOR (2.16.0): no new required CI gate, no integration code. General PM tools (Asana/Monday/ClickUp) are intentionally excluded from the named set — they lack a race-safe atomic-claim primitive; the bring-your-own recipe covers them with caveats.

## [2.15.0] - 2026-06-08

Slice 7c — Containers & image supply-chain (pattern + reference profile). Third sub-slice of Slice 7. Containers are first-class for services and explicitly absent for non-services.

### Added
- **Conditional container image supply-chain standard** (`DEVELOPMENT-STANDARDS.md` §14): if a project ships a deployable service image, the image must be multi-stage, non-root, minimal-base, healthchecked, and carry an image SBOM + **build provenance bound to the image digest**. Marked N/A for libraries/CLIs/batch/IaC — no new universal gate.
- **Reference profile `typescript-node`:** `Dockerfile` (multi-stage, distroless non-root), `.dockerignore`, `compose.yaml`, devcontainer, `deploy/k8s/` + `deploy/helm/` (non-root securityContext, probes, resource limits, digest-pinned image).
- **`profiles/typescript-node/ci.yml`** extended: `gate-image-sbom` (Syft/CycloneDX, scans on every PR) and a push-only `image-provenance` job — GHCR push + `actions/attest-build-provenance` digest-bound — with `packages: write` scoped to push-to-main. The 8 universal gate-ids are unchanged.
- **`conformance/container-supply-chain.sh`** — conditional, fail-closed: profiles with a `Dockerfile` must be multi-stage + non-root with image SBOM + digest-bound provenance; profiles without one are N/A (never failed).
- `_TEMPLATE.md` containerization pattern; `RUNBOOK-TEMPLATE.md` Kubernetes deploy guidance; audit-evidence conditional row.

### Changed
- `DEVELOPMENT-STANDARDS.md` §13 reinforces the image as the unit of dev/prod parity; `DEVELOPMENT-PROCESS.md` §9 ties promotion to the attested digest.

### Note
MINOR (2.15.0): no new universally-required CI gate. Image supply-chain is required only when a project ships a service image, so non-service stacks are unaffected. Rolling the pattern to other service profiles is a follow-on slice.

## [2.14.0] - 2026-06-06

Slice 7b — Multi-persona role touchpoints. Second sub-slice of Slice 7. Makes the kit legible to non-developer roles without becoming a PM/design tool.

### Added
- **Persona mapping** in `DEVELOPMENT-PROCESS.md` §2 — PO/BA · Designer · Engineer · QA · DevOps/SRE · Security · Lead/Agent mapped to the existing "functions, not titles" model (personas are lenses on functions; nothing in §2 is replaced).
- **Designer lane** — a UX & accessibility prompt in §5 Discovery and a "Design assets / UX handoff" row in the §15 artifact flow.
- `templates/FEATURE-REQUEST-TEMPLATE.md` (non-coder intake front door, mirrors the §5 Discovery prompts) and `templates/SPEC-TEMPLATE.md` (tool-neutral PRD behind the Plan gate).
- **Persona-routed onboarding** — a "Who are you? Start here" router atop `START-HERE.md` that routes each role to its minimal path and surfaces `scripts/incept.sh` as the engineer fast-path.

### Changed
- `templates/PROJECT-CLAUDE-TEMPLATE.md` §4 Roles guidance now points at the persona map.

### Note
No new required CI gate (MINOR). Docs/templates only — no enforced separation or code added; personas augment, not replace, the §2 functions.

## [2.13.0] - 2026-06-06

Slice 7a — Environments & production safety. First sub-slice of Slice 7 (adoption/safety hardening).

### Added
- **Dev → QA → UAT → Prod** environment model with gated promotion (production always human-gated) in `DEVELOPMENT-PROCESS.md` + `DEVELOPMENT-STANDARDS.md` §14 + `PROJECT-CLAUDE-TEMPLATE.md` + `RUNBOOK-TEMPLATE.md`.
- `conformance/branch-protection.sh` — verifies `main` is actually protected (PR reviews + status checks) via `gh api`; informational clean-exit where the API isn't reachable. `incept.sh` now reminds to apply branch protection.
- Env-protected reference prod-deploy workflow; explicit **human-coverage boundary** (the guard governs the Claude Code runtime only; humans/other runtimes are Org-owned platform controls).

### Changed
- **`.claude/hooks/guard.sh` is now environment-aware (additive — no existing deny weakened):** expanded destructive coverage (database drops via ORM/framework tools across Rails/Laravel/Django/Alembic/Flyway/.NET-EF, raw DB-client `DROP DATABASE`, restore-with-clean, cache flush, cluster-resource and container-volume removal, cloud storage/DB/instance deletion) plus a **production-context catch-all** (prod kube/helm context or namespace, `*_ENV=prod` prefix, `--env production` co-occurring with a destructive/deploy verb). All 35 prior conformance cases pass; 61 cases total.

### Note
No new required CI gate (MINOR). Production destructive-action prevention for humans and non-Claude-Code runtimes is Org-owned (platform IAM / account separation / deploy approvals).

## [2.12.0] - 2026-06-06

Slice 6d — Enterprise addendum, pillar 4 (capstone): the audit-evidence checklist. **Completes the enterprise addendum and the kit roadmap.** Tagged `v3.0.0` as the "enterprise layer complete" milestone (a marker, not a semver-major — no new required gate; the kit's contract version is 2.12.0, per `MAINTAINING.md`).

### Added
- `conformance/audit-evidence-checklist.md` — checklist-type conformance check mapping every control in the compliance crosswalk to **where its evidence lives** in a kit-built repo (CI gate logs, SBOM + provenance, PR approvals, the executable `conformance/*.sh`, the §6b managed-secret config, the §6c governed-exception records). Auto rows name the runnable check; Manual rows are attestation; waived controls cite a governed exception.
- Wired into `docs/enterprise/README.md`, the 6b/6c back-references, and the `conformance/README.md` index.

### Note
Documentation/checklist only — no new gate, no code. Completeness tie-off: every crosswalk control has an evidence row. With this, the enterprise addendum (6a crosswalk · 6b secrets-at-scale · 6c ratification RBAC · 6d audit evidence) is complete.

## [2.11.0] - 2026-06-06

Slice 6c — Enterprise addendum, pillar 3: ratification RBAC. Third of four sub-slices.

### Added
- `DEVELOPMENT-PROCESS.md` §13 **"Ratification roles & exceptions"** — defines which named role (Project Owner / Code Owner / Security Owner / Release Manager) may ratify what, the builder ≠ sole-ratifier rule per change, and the **governed-exception process**: required gates/posture are universally required; a Security-Owner-ratified, time-boxed record is the only way to waive (settles the Slice 5e deferred question). §12 cross-references it.
- `docs/enterprise/ratification-rbac.md` — full role model, separation-of-duties, GitHub mapping (CODEOWNERS + branch protection + the profile companions), and the exception-record template.

### Note
No new gate, no code. The agent-autonomy human-gate set is unchanged — agents propose; a human in the appropriate role ratifies. Maps onto existing CODEOWNERS / BRANCH-PROTECTION companions; 6d's audit-evidence checklist attests it.

## [2.10.0] - 2026-06-06

Slice 6b — Enterprise addendum, pillar 2: secrets at scale. Second of four sub-slices.

### Added
- `DEVELOPMENT-STANDARDS.md` §2 **"Secrets at scale"** subsection — the contract: managed store (Vault/KMS) beyond `.env`, least-privilege, rotation (prefer dynamic/short-lived), no plaintext in state/logs/images, CI fetches at run time via OIDC, audited break-glass.
- `docs/enterprise/secrets-at-scale.md` — patterns (static vs dynamic, CI injection reusing the §14 OIDC/provenance pattern, rotation, envelope encryption, break-glass) + a **secret-manager-client-by-stack** table covering all 10 stacks in one place.
- `profiles/_TEMPLATE.md` Security section now points to the secrets-at-scale doc, so future/BYO profiles route correctly.

### Note
Stack-neutral contract + stack-aware reference — **no edit to the 10 existing profiles**. No new gate, no code. The CI-injection pattern ties to the Slice 5e push-only OIDC job.

## [2.9.0] - 2026-06-06

Slice 6a — Enterprise addendum, pillar 1: the compliance crosswalk. First of four sub-slices.

### Added
- `docs/enterprise/README.md` — addendum index + an explicit **responsibility boundary** (Kit-enforced / Kit-assisted / Org-owned), naming what the kit does not cover (HR, physical, vendor risk, BCP, the privacy program).
- `docs/enterprise/compliance-crosswalk.md` — maps the controls the kit enforces/assists to **SOC 2 (Security CC + Privacy P) + ISO 27001:2022 Annex A**, with a dedicated **privacy/data-protection family** (data-subject rights, consent & age-gating, retention, third-party sharing; COPPA/GDPR-minors/CCPA named as triggers). Column-structured so NIST CSF / PCI-DSS / ISO 27701 are a cheap re-index later.

### Note
Pure documentation — no new gate, no code, no profile changes. The crosswalk *maps* controls; it does not mandate new ones. Privacy rows are N/A-with-reason for no-PII projects. Definition of Done unchanged.

## [2.8.0] - 2026-06-06

Slice 5e — CI security hardening across all 10 profile reference pipelines. Triggered by a push security review whose findings proved kit-wide. No new gate, no contract-breaking change.

### Changed
- **All 10 `profiles/*/ci.yml`** restructured to least-privilege OIDC: a `ci` job (all gates, PR + push, `permissions: contents: read`) plus a push-main-only `provenance` job (`needs: ci`) that holds `id-token`/`attestations: write` and attests the build artifact handed off via `upload-artifact`/`download-artifact` (`subject-path: build-artifact/**`). PR-triggered steps can no longer mint an OIDC token. PRs still run every gate.
- Strengthened the `# HARDENING:` block in every reference pipeline (SHA-pin actions · pin tool installs · cloud OIDC trust policy MUST restrict `sub` to `refs/heads/main`).
- `profiles/terraform/ci.yml`: pinned `checkov` to `3.2.533` (verified on PyPI); noted the conftest download should be checksum-verified.

### Added
- `DEVELOPMENT-STANDARDS.md` §14: a **CI security hardening** posture note (least-privilege OIDC via a push-only attestation job · SHA-pinning · trust-policy `sub` restriction). Guidance, not a new required gate — Definition of Done unchanged.

### Note
No gate id was removed from any profile; `conformance/ci-gates.sh` (job-agnostic id presence) and `profile-completeness.sh` pass unchanged across all 10. SHA-pinning the references is modeled as a documented adopter step rather than baked-in opaque hashes.

## [2.7.0] - 2026-06-06

Slice 5d — Terraform/IaC stack profile. Completes the profile family (10 stacks). Proves §14's 8 gates hold even for config-only IaC — via analogs, no contract change.

### Added
- `profiles/terraform.md` + `profiles/terraform/` (`ci.yml`, `CODEOWNERS`, `BRANCH-PROTECTION.md`) — Terraform ≥1.6 · tflint · `terraform validate`/`test` · Checkov + conftest/OPA · Trivy · gitleaks.
- A dedicated **`gate-policy`** step (Checkov + conftest/OPA) — the IaC headline gate (parallel to ML's `gate-eval` and data-engineering's `gate-data-quality`).

### Note
IaC has no software artifact, so §14's gates map to **analogs**, keeping the 8 intact (no `ci-gates.sh`/§14 change): `gate-build` = `terraform plan` (the plan is the artifact); `gate-dep-scan` = Trivy config scan (vulnerable/misconfigured providers & modules — tfsec is merged into Trivy); `gate-sbom` = Trivy CycloneDX (provider/module inventory). The profile applies the **conditional 15-factor** mechanism (an IaC repo isn't a running service → port-binding/concurrency/stateless/disposability N/A-with-reason). `incept.sh --stack terraform` wires the profile's CI.

## [2.6.0] - 2026-06-06

Slice 5c2 — Data-engineering stack profile. Completes the profile family (9 stacks). The data-eng analog of the ML eval gate: a data-quality gate.

### Added
- `profiles/data-engineering.md` + `profiles/data-engineering/` (`ci.yml`, `CODEOWNERS`, `BRANCH-PROTECTION.md`) — dbt-core (warehouse transforms) · Dagster (orchestration, asset checks) · Python ingestion · sqlfluff + ruff (lint) · dbt parse + mypy (validate) · dbt tests/contracts + Great Expectations + pandera + data-diff (data quality) · gitleaks · pip-audit · CycloneDX-py + provenance.
- A dedicated **`gate-data-quality`** step in the data-engineering `ci.yml` (`dbt build` + Great Expectations checkpoint, run against a CI Postgres service) that fails the build on a data-quality violation — the data-eng analog of ML's `gate-eval`. `conformance/ci-gates.sh` validates the 8 standard gates; `gate-data-quality` is an allowed extra.

### Note
`gate-type-check` = `dbt parse` + `mypy` (SQL has no compiler; parsing the model DAG is the validate analog). The profile applies the **conditional 15-factor** mechanism: an orchestrated batch pipeline marks port-binding/concurrency/stateless/disposability N/A-with-reason; the warehouse backing-service + lineage telemetry apply. `incept.sh --stack data-engineering` wires the profile's CI.

## [2.5.0] - 2026-06-06

Slice 5c — ML stack profile. The kit's first profile with a real **eval gate** — wiring the §7 "evals = the dev-time bar / AI analog of TDD" doctrine into CI.

### Added
- `profiles/ml.md` + `profiles/ml/` (`ci.yml`, `CODEOWNERS`, `BRANCH-PROTECTION.md`) — Python ML lifecycle: uv · ruff (+nbqa) · mypy · pytest (+ pandera data-validation, nbmake notebook smoke) · MLflow (tracking/registry) · DVC (data/model versioning) · notebook hygiene (nbstripout/jupytext) · gitleaks · pip-audit · CycloneDX-py + provenance.
- A dedicated **`gate-eval`** step in the ML `ci.yml` (`python -m evals.run --threshold 0.8`) that fails the build below the eval threshold — metric thresholds and/or LLM-as-judge (pinned judge), plus a safety/red-team set. `conformance/ci-gates.sh` validates the 8 standard gates; `gate-eval` is an allowed ML extra.

### Note
The ML profile applies the **conditional 15-factor** mechanism: a training pipeline is batch, so port-binding/concurrency/stateless/disposability are N/A-with-reason; the serving path satisfies them. `incept.sh --stack ml` wires the profile's CI. The data-engineering profile follows as a separate slice.

## [2.4.0] - 2026-06-06

Slice 5b — More first-class profiles + bring-your-own on-ramp. Seven shipped stacks now: TypeScript, Python, Java/Spring, C#/.NET, Go, Rust, Kotlin.

### Added
- `profiles/dotnet.md` + `profiles/dotnet/` — .NET 8 · dotnet format/analyzers · dotnet build (type-check) · xUnit+coverlet · dotnet list package --vulnerable · CycloneDX .NET · EF Core · ASP.NET Core.
- `profiles/go.md` + `profiles/go/` — Go 1.22+ · golangci-lint · go vet · go test -race -cover · govulncheck · cyclonedx-gomod · golang-migrate.
- `profiles/rust.md` + `profiles/rust/` — Rust stable · clippy · cargo check · cargo-llvm-cov · cargo-audit · cargo-cyclonedx · axum + sqlx.
- `profiles/kotlin.md` + `profiles/kotlin/` — Kotlin/JVM 21 · Gradle (Kotlin DSL) · ktlint+detekt · JUnit5/Kotest+JaCoCo · OWASP dependency-check · cyclonedx-gradle · Spring Boot + Flyway.
- `scripts/new-profile.sh` — scaffolds a new stack profile + a stub `ci.yml` that passes `ci-gates.sh` structurally, so bringing an unsupported stack is a guided, validated workflow.
- `README.md` "Generate your own profile" section; `START-HERE.md` §2B points at the scaffolder.

### Note
Each new `ci.yml` reuses the existing 8-gate `ci-gates.sh`; `profile-completeness.sh` now guards all 7 profiles. Kit CI verifies declaration + completeness; it does not execute the toolchains (adopter-side).

## [2.3.0] - 2026-06-06

Slice 5 — Enterprise profiles. Python and Java/Spring join TypeScript as ready, conformant stack profiles.

### Added
- `profiles/python.md` + `profiles/python/` (`ci.yml`, `CODEOWNERS`, `BRANCH-PROTECTION.md`) — uv · ruff · mypy · pytest+cov · gitleaks · pip-audit · CycloneDX-py + provenance; FastAPI + SQLAlchemy/Alembic reference.
- `profiles/java-spring.md` + `profiles/java-spring/` (`ci.yml`, `CODEOWNERS`, `BRANCH-PROTECTION.md`) — Maven · Spring Boot · Spotless/Checkstyle · JUnit5+JaCoCo · OWASP dependency-check · CycloneDX-maven + provenance; Flyway migrations. (`mvn compile` = type-check; `mvn package` = build.)
- `conformance/profile-completeness.sh` — every profile fills all 11 `_TEMPLATE.md` sections (no leftover `[...]`) and its companion `ci.yml` passes `ci-gates.sh`. Runs in kit CI; also regression-guards `typescript-node.md`.

### Changed
- `.github/workflows/ci.yml` — the conformance job now runs `profile-completeness.sh`.
- `docs/ROADMAP-KIT.md` — Slice 5 marked done.

### Note
`incept.sh --stack python` / `--stack java-spring` now wires the respective profile's CI. Kit CI verifies the profiles' workflows *declare* the §14 gates and the profiles are complete; it does not execute the Python/JVM pipelines (that happens in an adopting project).

## [2.2.0] - 2026-06-06

Slice 3 — Inception bootstrap. One command turns a cloned kit into a configured project. Absorbs the template work (RUNBOOK + flow-board BACKLOG); roadmap collapses 6→5.

### Added
- `scripts/incept.sh` — in-place Inception bootstrap (interactive + `--noninteractive`). At adoption it renames the principles doc `CLAUDE.md` → `ENGINEERING-PRINCIPLES.md` (freeing the project memory slot), rewrites the principles-sense references, stamps the project `CLAUDE.md`/`RUNBOOK.md`/`BACKLOG.md`/`ADR-000`, and wires the profile's CI. Prints the judgment steps it does not automate.
- `templates/RUNBOOK-TEMPLATE.md` — cold-resume runbook (setup/deploy/rollback/RPO-RTO).
- `conformance/inception-done.sh` — verifies the Inception-Done gate; kit CI bootstraps a temp project and asserts it passes.

### Changed
- `templates/BACKLOG-TEMPLATE.md` — rewritten from the stale phase/PROGRESS model to the §6 flow-board (states, work-item fields, ordering, work types, tech-debt paydown).
- `.github/workflows/ci.yml` — new `bootstrap` job (incept-into-temp → inception-done).
- `docs/ROADMAP-KIT.md` — Slice 3 done; roadmap 6→5 (template work absorbed).

### Note
The canonical kit stays **un-incepted** (principles remain in `CLAUDE.md`, which also serves as the kit's own memory). The `CLAUDE.md → ENGINEERING-PRINCIPLES.md` rename is an **adoption-time transform performed by `incept.sh`**, not a change to the kit's own layout.

## [2.1.0] - 2026-06-06

Slice 2 — Agent governance layer. The §13 autonomy matrix is now mechanically enforced for Claude Code (additive reference + conformance → MINOR per `MAINTAINING.md` §2).

### Added
- `.claude/` governance layer (kit-own + adopter reference): `settings.json` (allow/ask/deny permission globs), `hooks/guard.sh` (PreToolUse hook denying irreversible/high-blast actions, field-scoped via jq, hardened against allowlist-escape bypasses), `agents/reviewer.md` + `agents/security-reviewer.md` (the §12 separations), and `README.md`.
- `conformance/agent-autonomy.sh` — proves the guard denies a tier breach and allows safe actions, with false-positive and bypass-resistance regressions; runs in kit CI.
- `DEVELOPMENT-PROCESS.md` §13 — an "Enforcement reference" note (tool-neutral matrix → Claude Code `.claude/` reference).

### Changed
- `.github/workflows/ci.yml` — the conformance job now also runs `agent-autonomy.sh`.
- `.gitignore` — excludes `.claude/settings.local.json` (personal); `settings.json` is committed/shared.
- `docs/ROADMAP-KIT.md` — Slice 2 marked done.

## [2.0.0] - 2026-06-05

Slice 1 — CI/CD. Raises the supply-chain posture to the baseline for all projects (new required gates → MAJOR per `MAINTAINING.md` §2).

### Added
- `DEVELOPMENT-STANDARDS.md` §14 **CI/CD Pipeline** — 7 required per-PR gates (lint, type-check, test+coverage≥80%, build, secret-scan, dependency scan, SBOM+provenance) + branch protection (main protected, green-CI-to-merge, builder≠sole-merger).
- TypeScript reference pipeline in `profiles/typescript-node/`: `ci.yml`, `CODEOWNERS`, `BRANCH-PROTECTION.md`.
- `conformance/ci-gates.sh` — asserts a workflow declares every required gate; `conformance/check-links.sh` — relative-link integrity check.
- `.github/workflows/ci.yml` — the kit's own CI (conformance + docs links): the kit now dogfoods its gate.

### Changed
- `DEVELOPMENT-PROCESS.md` §10 — supply-chain integrity moves from optional configuration hook to **required CI gates**; §15 — recurring audit reframed as the deeper periodic complement to the per-PR gate.
- `profiles/typescript-node.md` §4 — points to the concrete reference files.
- `docs/ROADMAP-KIT.md` — Slice 1 marked done.

## [1.0.0] - 2026-06-05

First product release — the kit becomes a versioned, drop-in template framework.

### Added
- `LICENSE` (Apache-2.0) — the kit is now licensed for distribution.
- `VERSION` + this `CHANGELOG.md` — the kit is a semver'd product.
- `MAINTAINING.md` — the contract/reference/conformance convention, and how the kit is versioned, released, and contributed back to (the kit dogfoods its own loop).
- `conformance/` — the conformance-check pattern and `15-factor-checklist.md` (the first check, filled for the TypeScript/Node reference profile).
- `DEVELOPMENT-STANDARDS.md` §13 — **15-Factor Architecture**: a binding, conditional-by-project-type contract mapping all 15 factors to where the kit enforces them. Adds previously-uncovered factors: dependencies, disposability, backing services, dev/prod parity, statelessness, concurrency, and telemetry depth.
- `docs/ROADMAP-KIT.md` — the kit's own backlog: the six remaining contract/reference/conformance slices, sequenced.
- "Kit version adopted" field in `templates/PROJECT-CLAUDE-TEMPLATE.md` — projects record the kit version they run.

### Changed
- `DEVELOPMENT-PROCESS.md` §7 — the Review gate adds a conditional **15-Factor conformance** check; §8 — the L3 process retro now routes kit-level improvements upstream as a PR to the canonical kit.
- `README.md` — version surfaced; "How the kit is built" (the contract/reference/conformance convention) added; license declared.

[2.7.0]: https://github.com/SeaBrad72/sparkwright/releases/tag/v2.7.0
[2.6.0]: https://github.com/SeaBrad72/sparkwright/releases/tag/v2.6.0
[2.5.0]: https://github.com/SeaBrad72/sparkwright/releases/tag/v2.5.0
[2.4.0]: https://github.com/SeaBrad72/sparkwright/releases/tag/v2.4.0
[2.3.0]: https://github.com/SeaBrad72/sparkwright/releases/tag/v2.3.0
[2.2.0]: https://github.com/SeaBrad72/sparkwright/releases/tag/v2.2.0
[2.1.0]: https://github.com/SeaBrad72/sparkwright/releases/tag/v2.1.0
[2.0.0]: https://github.com/SeaBrad72/sparkwright/releases/tag/v2.0.0
[1.0.0]: https://github.com/SeaBrad72/sparkwright/releases/tag/v1.0.0
