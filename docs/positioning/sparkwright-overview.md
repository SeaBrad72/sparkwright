# Sparkwright — the complete source document (for description, marketing & support materials)

> **What this is.** The single, comprehensive, factual source-of-truth for Sparkwright — broad **and** deep
> across the entirety of the kit. It re-states the substance of the README, the process and standards docs, the
> enterprise addendum, the operations and adoption guides, the templates, and the conformance surface in one
> place, so you (and a co-work agent) can draft the website, marketing copy, and support docs from here without
> cross-referencing.
>
> **Tone: factual and methodical, not salesy.** Every capability is stated at its true strength —
> **enforced** (a live gate blocks it), **advisory** (a nudge that doesn't block), or **declared** (an
> attestation the kit can't observe at runtime). That candor is the differentiator; do not inflate it.
>
> **Frame.** Sparkwright is a **software-development methodology first** — real engineering principles, a
> lifecycle loop, quality gates, and ceremonies — and an **agentic execution engine second**. Parts I–III are
> the methodology and the quality bar; Part IV is the agent machinery that executes it; Parts V–VI are
> portability, trust, and governance. Lead with the discipline; the agents are *how* it's carried out.

**Contents.** I. What it is & who it's for · II. The methodology (the working model) · III. The quality bar
(the standards) · IV. The agentic execution engine · V. Portability, environments & adoption · VI. Trust,
rigor & governance.

---

# PART I — WHAT IT IS & WHO IT'S FOR

## 1. What it is

Sparkwright is an **agentic SDLC kit**: a complete, opinionated software-development methodology — its
principles, its lifecycle loop, its quality gates, and its ceremonies — packaged so that **AI agents execute
the discipline** and humans hold the judgment gates. You bring the idea and the decisions; the kit brings the
process, the guardrails, and a working pipeline to build on.

It is opinionated about *how* to build well and neutral about *what* you build with — your stack, harness,
model, environment, and deploy target are chosen and built as you engage the kit, not picked for you. It is
**production-grade from day one** (no demos, no throwaway prototypes), and it is **portable by design**: the
universal standards are stack-neutral; the one stack-specific layer is a swappable profile.

Adoption is one command: export a clean, CI-ready copy into a new project, open it in your AI coding tool, and
run `START-HERE` — Inception then walks you through choosing your stack, scaffolds a runnable starter with a
**green pipeline on the first run**, and wires the project, before handing you into the build loop. Brownfield
adoption into an existing repo is supported. Maturity is a **stage, not a version**: the kit is at
`release-candidate` today, reaching `adopted` when an external team ships real software through it. The kit
versions its own releases on its own cadence (currently `v3.218.0`); adoption is a maturity stage, not a
version reset. The kit is built with its own loop and held to its own Definition of Done — it dogfoods every
principle and gate it gives you.

## 2. Who it's for — the audience spectrum

Any team — humans, agents, or both — starting or running a project who wants production-grade discipline
without inventing a process from scratch. The kit meets people at their level (`ONBOARDING.md` is an
experience-aware front door that routes from vibe-coder to principal/architect):

- **Solo builders / vibe-coders** — a lean default keeps ceremony light; you get guardrails and a working
  pipeline without an enterprise process.
- **Product teams** — the loop, the gates, and the discovery front-end turn raw signals into shipped,
  operated software.
- **Engineering / platform orgs** — hand it to a team and tailor it; the enterprise addendum (compliance
  crosswalks, RBAC, secrets-at-scale, an EXEC-BRIEF) is there when you need it. Its **ROI model and
  org-rollout playbook were written ahead of any adopter and are frozen pre-adoption (2026-08-19)** —
  read them as reasoning to adapt, not as shipped, evidenced kit value.

The design pattern throughout: **define the rich model, ship a sensible default, make it per-project
configurable, and let maturity/metrics raise the bar.** Nothing heavy is imposed before it earns its place.

## 3. The foundation — principles that don't bend

The non-negotiables the whole kit is built on. Enforced, not aspirational (`CLAUDE.md` is authoritative):

- **Production-grade from day one.** Everything is shippable; Inception scaffolds a runnable project with a
  green pipeline, so you build on working software, never an empty repo.
- **Test-driven.** Tests — and, for AI features, **evals** — are written *with* the code, not after. Quality
  is built in, not inspected in.
- **Architecture before implementation.** Design and trade-offs are settled before code — including the
  **15-Factor** architectural contract for deployable services (§9).
- **Security & governance are foundational.** Built into every line from the start, not bolted on.
- **The governing lens** *(the idea that shapes every ceremony)*: Sparkwright keeps or kills a ritual by one
  test —
  > **Rituals that manage or forecast human effort die or transform. Rituals that clarify intent or improve
  > quality get stronger.**
  Agent effort is fast and cheap; the scarce resources are **human attention** and **integration risk**. So
  estimation, velocity, sprint commitment, and standups lose their reason to exist — while Definition of Ready,
  acceptance criteria, demo/acceptance, retrospectives, and adversarial review get *more* powerful, because
  agents can run them more often and in parallel than a human team ever could.

---

# PART II — THE METHODOLOGY (THE WORKING MODEL)

## 4. The loop

Sparkwright runs as a continuous, WIP-limited loop — **pulled, not pushed**; humans are the **pacing
metronome** at the checkpoints. It does not end at release: it closes through **Operate**, whose production
signals feed back into **Discover**.

```
INCEPTION (one-time) ──▶ [ Discover → Plan → Build → Review → Release → Done → Operate ↺ ]
```

| Stage | What happens | Exit |
|---|---|---|
| **Inception** *(Phase 0, once)* | Charter + stack/harness/deploy decisions (fit-driven, ratified, recorded as ADR-000); scaffold a runnable starter with a green first-run pipeline. | Project exists |
| **Discover** | Intake, **product validation**, triage, innovation lens. | Validated candidate |
| **Plan** | Slice into small **vertical increments**; acceptance criteria; a spec for non-trivial work; **threat-model** sensitive features. Must reach the **Definition of Ready**. | Spec gate (human) |
| **Build** | **TDD** per the standards; continuous reflection-in-action; a fast inner loop. | Self-verified, tests green |
| **Review** | *"Did we build it right?"* — code + adversarial/multi-lens + **security** + **code-quality** review, routed by ownership. | Merge gate (human) |
| **Release** | *"Done → Live"* — deploy, feature flags, staged rollout, smoke test, CHANGELOG, rollback ready. | Live in production |
| **Done** | **Acceptance** (*"the right thing?"*), Definition of Done met, **L1 retro** written. | Closed |
| **Operate** | Monitor, triage, resolve; **feed signals back to Discover**. | Continuous |

**Roles are functions, not titles** — each mappable to a human or an agent; one may hold several: Intent
owner (the *why* + acceptance), Lead/integrator (the board, WIP, integration, ratifying governance), Builder,
Reviewer, On-call/operator, Security owner. Two separations are **enforced**: the **Builder is never the sole
Reviewer**, and **governance/standards/doc changes are always human-ratified** (agents propose, humans
ratify). Enterprise personas are *lenses* on these functions, not new roles.

## 5. The gates — where humans hold judgment

The loop is punctuated by explicit gates. Most are always-on; several are **conditional** — they fire only
when their trigger applies, else marked **N/A-with-reason** (never silently skipped):

> **Ready** (Definition of Ready) · **[threat-model]** *(sensitive/regulated data)* · **Spec** · **Review**
> (+ security + code-quality) · **[eval]** *(AI features)* · **[compliance]** *(regulated domain)* ·
> **[15-Factor]** *(deployable services)* · **[deployable]** · **[DR]** *(data services)* · **[resilience]** ·
> **Accept** · **Done**.

The gates are where the human's load-bearing act — a recorded, informed, **proportional** GO/NO-GO — lives.
Rigor scales to *rung × change-class × autonomy*: trivial low-blast changes get a light touch; the dangerous
minority gets full scrutiny plus a demonstrable-increment check. Over-gating manufactures rubber-stamping, so
the attention is selective by design.

## 6. Ceremonies & the improvement engine

The governing lens (§3) applied:

- **Dropped** (they only managed/forecast effort): estimation, story points, velocity, sprint commitment,
  daily standups.
- **Kept and strengthened** (they clarify intent or improve quality): Definition of Ready, acceptance
  criteria, demo/acceptance, **retrospectives**, **adversarial/independent review**.

**The nested retrospective engine — a continuous-improvement loop, not an end-of-sprint event:**

- **L0 · reflection-in-action** — continuous, inside Build.
- **L1 · per-item retro** — written at Done; durable learnings captured to **cross-session memory**.
- **L2 · milestone retro** — adjusts the roadmap, backlog, docs, and memory.
- **L3 · process retro** *(periodic)* — edits the governing docs **themselves**: the kit improves its own rules.
- **Event retro** — triggered from *any* stage by a bug, a red CI, or a blocker.

The rule that makes it a closed loop, not a talking shop: **every "adjust" exits into an artifact** — a PR, a
memory entry, a backlog item, or a doc change. Production signals feed Discover; retros feed the roadmap and
the rules. Nothing is "learned" without landing somewhere durable. A periodic **meta-control** cadence (a
Kit-Steward review) runs an adversarial go/no-go + retro at epic/release boundaries and routes findings back.

## 7. Discovery — from signals to a Ready backlog

Upstream of the build loop, an optional **discovery loop** (**FRAME → SHAPE → Ready**) turns raw signals —
production telemetry, tickets, usage, ideas — into a Ready backlog of INVEST-sliced increments with acceptance
criteria and a success hypothesis. Skip it if you already have a Ready backlog; drop straight into Build if
product and design are settled. Intake is structured (`FEATURE-REQUEST`, `OPPORTUNITY-BRIEF`, `SHAPING-DOC`
templates), and the **Definition of Ready** is the entry gate that keeps half-formed work out of Build.

---

# PART III — THE QUALITY BAR (THE STANDARDS)

*The universal, stack-neutral bar (`DEVELOPMENT-STANDARDS.md`); the stack-specific "how" lives in your profile.
Most items below carry a conformance check and/or a Definition-of-Done line.*

## 8. Testing strategy — TDD, the pyramid, and test *quality*

Tests are the regression suite. **Mock at boundaries, not internals. Test behavior, not implementation.**

- **Coverage:** 80% line coverage is the floor; **100% on critical paths** (auth, payments/orders, money math,
  anything irreversible).
- **Test quality, not just coverage:** coverage measures *execution*, not assertion strength — a suite can hit
  80% and assert nothing (a common failure when tests are AI-generated). The kit calls for **mutation testing**
  (a mutation score on critical paths) and **property-based testing** to broaden inputs — recommended,
  especially on critical paths / nightly, not a universal PR gate (mutation runs are too slow to gate every
  push).
- **Test data:** non-prod uses synthetic or anonymized data; **never raw production data** (PII / children's →
  masked or synthetic, COPPA-grade); recorded in the RUNBOOK.
- **The testing pyramid** (prioritized top-down, each added when its trigger arrives): **unit ·
  property-based · integration · API/contract · e2e · smoke · load/stress · security · AI evals.**

TDD is a first-class skill in the Build stage; the pyramid is the standard, and per-stack test tooling/examples
live in the profile.

## 9. Architecture & code — 15-Factor, code quality, database & performance

- **15-Factor architecture** *(deployable services)* — the binding-but-conditional architectural contract,
  after Hoffman's *Beyond the Twelve-Factor App* (the twelve Heroku factors plus API-first, Telemetry, Auth):
  one codebase, explicit dependencies with a committed lockfile, config in the environment, backing services
  reached by config, dev/prod parity, disposability (SIGTERM drain + idempotency), stateless share-nothing
  processes, logs as streams, and the rest. Non-applicable factors are marked **N/A with a one-line reason** at
  the architecture review; it has its own conformance check (`conformance/15-factor-checklist.md`) enforced at
  the **Review gate**. For a containerized service, the **image is the unit of dev/prod parity** — local dev
  builds from the same Dockerfile that ships.
- **Code quality** — functions small (< 20 lines target, extract beyond ~50) and single-purpose; early returns
  over deep nesting; meaningful names; comments explain *why* (kept true or deleted); no dead code, no committed
  debug output, no hardcoded config; **money in exact decimal types, never floats**. Every human-run script
  carries a **self-disclosure header** (what it does · what it changes · guardrails), enforced by
  `conformance/script-disclosure.sh`.
- **Database & performance** — indexes on queried columns, pagination, no N+1; **schema changes via versioned
  migrations only** (expand-contract, zero-downtime discipline in the process doc); performance/SLA targets
  (API < 200ms p95 standard / < 500ms complex; page TTI < 3s; no unindexed query > 100ms without justification);
  Core Web Vitals "Good" for user-facing web; **load- and soak-test before any public launch**.

## 10. Security & guardrails

Security is foundational (§3), and the standard is concrete: secrets never committed (env vars + a committed
`.env.example`; a `SECURITY.md` with a real disclosure contact, verified by conformance); input validated and
sanitized at every boundary; parameterized queries / ORM — never string-interpolated untrusted input; strong
adaptive password hashing; least-privilege, short-expiry tokens; PII never sent to third parties without
consent, redacted in logs, deletable on request; an immutable audit trail for critical operations. For AI
features, **runtime guards** (output validation, prompt-injection defense) **and** dev-time evals. The concrete
libraries/config live in your profile; the boundary itself (guard → git → CI) is described in §19 and §26.

## 11. AI-native / eval-driven development

A headline capability: the kit treats **a prompt as production logic**, held to the same bar as code, with
**eval-driven development** as the discipline (`DEVELOPMENT-STANDARDS.md §7`, the Eval gate):

- **Task quality** — outputs scored against a curated dataset + rubric (exact-match, graded criteria, or
  LLM-as-judge with a **pinned judge** + rubric).
- **Regression** — the eval suite runs in CI on any prompt/model/parameter change; a drop below threshold
  **fails the build** (an enforced gate).
- **Safety / red-team** — adversarial prompts, jailbreaks, harmful-output checks before shipping.
- **Discipline & artifacts** — the eval set is versioned with the code and grows from production misses and
  retros; evals *complement* runtime guards; eval scores are tracked as a quality metric (decline = tech debt).
  Planned with `EVAL-PLAN-TEMPLATE.md`; an **AI System Card**, **AI Policy**, **AI Transparency sign-off**, and
  **AI Artifact Lineage** templates carry the governance; readiness is conformance-checked (`eval-ready.sh`,
  `responsible-ai-ready.sh`). Governance maps to **NIST AI RMF · ISO 42001 · OWASP** (§26).
- **Honest ceiling** — running the *live* eval against a provider is a human/CI step by policy: the agent
  authors and wires the evals but does not run the live provider key (the guard blocks reading a live key into
  context as a speed bump, not a hard boundary).

## 12. Accessibility

For user-facing UI: **WCAG 2.1 AA.** Semantic elements (never style a `div` as a control), full keyboard
operability with visible focus, alt text and labelled inputs, **4.5:1 contrast** (3:1 for large text), respect
`prefers-reduced-motion`, and an **automated a11y audit before shipping**, recorded in an A11Y sign-off
(`A11Y-SIGNOFF-TEMPLATE.md`). It is a Definition-of-Done category and a Review-gate obligation for user-facing
surfaces.

## 13. Observability

**Structured logging** (machine-parseable in prod, human-readable in dev) — every entry carries timestamp,
level, message, request/correlation ID, service; log levels used correctly (ERROR/WARN/INFO/DEBUG, DEBUG off in
prod); **never log** secrets, tokens, card numbers, or unneeded PII. **Error tracking** and **performance
monitoring** wired for production, alerting on error spikes and health-check failures. Distributed **tracing**,
a **metrics endpoint**, and an **OTLP backend** are wired capabilities (conformance-checked); the agentic loop
itself emits an OTel run-trace the agent-ops and cost/value tooling read.

## 14. Resilience, data management, DR & continuity

- **Resilience & error handling** — structured errors with codes (not bare strings); **idempotency** for
  retryable operations; **retry with exponential backoff** for transient failures; **circuit breakers** around
  unreliable dependencies; **graceful degradation**. And the discipline: **verify these under failure, don't
  just assert them** (`docs/operations/resilience-verification.md`).
- **Data management & backup** — automated production backups with a **verified restore** (at least once per
  project); **RPO/RTO** in the RUNBOOK (defaults RPO < 24h, RTO < 4h; tiered by data criticality from a
  Business Impact Analysis for multi-criticality systems); versioned, reversible migrations.
- **DR & continuity** — a recorded **backup-restore drill** is the floor, a *passed* drill is the bar
  (`docs/continuity/`, `BIA-TEMPLATE.md`); DR readiness is conformance-surfaced for data services.

## 15. Incident response & postmortems

How a production incident is declared, commanded, resolved, and learned from — aligned with **NIST SP 800-61**
and SRE practice. A **P0–P3 severity ladder** (P0 critical: outage/data-loss/breach → all-hands, declare
immediately; through P3 minor → scheduled), the same ladder the Operate triage step routes on. **Roles as
functions:** an **Incident Commander** (a human commands; agents assist — detect, correlate, summarize, draft
the timeline, propose mitigations; irreversible production actions are human-authorized), a **Comms lead**, and
a **Scribe**. A **postmortem** is required for P0/P1 (`POSTMORTEM-TEMPLATE.md`), and **break-glass** procedures
are documented (`docs/operations/break-glass.md`). Incident *tooling* (paging, on-call rotation, status page)
is org-owned — named and wired to your platform, not reinvented.

## 16. Release & change management

- **Feature flags** are the lever that **decouples merge from release** — dark-launch risky/incomplete work
  behind an OFF flag, and separate the *engineering* deployability decision from the *business/product* release
  decision (market timing, launch comms, coordinated dependencies).
- **Progressive delivery** — staged rollout, canary, tested rollback, post-deploy smoke (§23).
- **API design & compatibility** — **versioned from day one** (e.g. `/v1`); **additive changes only** within a
  version (never remove/rename response fields silently); **breaking changes ship as a new version** with a
  deprecation window; **deprecation** is announced, the old surface maintained for a stated minimum, then
  removed only on a MAJOR bump with a documented migration path.
- **Changelog** — a curated, user-facing CHANGELOG entry per release (and, for the kit itself, a public
  release note that gates the publish).

## 17. CI/CD & supply-chain

Every change runs a **required gate battery**: lint · type-check · test · build · secret-scan · dependency-scan
· **SBOM + provenance** (supply-chain, mapping to **SLSA**). Plus the conditional gates of §5. An **artifact
gate** runs the adopter's *own* conformance on the **real emitted artifact** (export → incept → run), so the
kit is qualified by what it ships, not just its source; a golden-path job boots the **service** stack profiles
in real containers (the non-app profiles — terraform, ml, data-engineering — have no service image to boot). Dependencies are pinned with committed lockfiles; the kit SHA-pins its own CI action fleet; tool
supply-chain and egress control are documented operating concerns. No known high/critical vulnerabilities in
production/runtime dependencies is a Definition-of-Done line.

---

# PART IV — THE AGENTIC EXECUTION ENGINE

*How the methodology above is carried out — the machinery, not a replacement for the discipline.*

## 18. The agent team & their hats

A small **standing team of agents** — *few agents, many skills, by design* (a standing seat is earned only by
a distinct skill **and** distinct tools or a must-run-in-parallel need; everything else is a skill a seat
invokes):

- **Orchestrator** — lead/EM: slices an epic, assigns each task its model tier + fan-out, spawns engineers in
  isolated git worktrees, integrates through a serial merge queue, convenes the reviewers, emits the run trace;
  metered by a runaway kill-switch.
- **Engineer** — builds one assigned slice via **TDD** inside its own worktree; never touches another slice's
  files; returns a diff + a self-verify report.
- **Reviewer** — independent correctness/standards/CI-gate review.
- **Security** — the security lens on any trust/data/AI boundary.

The **design, plan, verification, TDD, evals, discovery, operating, debugging** roles are **skills** the
orchestrator or a seat invokes, each mapped to a stage/gate of the loop — not standing agents. The orchestrator
*assigns*; it never reviews or ratifies its own output.

## 19. Separation of duties & the promotion model

- **Builder ≠ reviewer ≠ ratifier.**
- **Control-plane ratification** — a change to the kit's own control plane (guard, CI, conformance, governance)
  requires an **independent ratifier**; the merge is blocked until a non-author approval is recorded (a required
  check on GitHub; an auditable N/A where a platform can't express it).
- **The judgment is the control, not the keystroke** — the human's act is a recorded, informed, proportional
  **GO/NO-GO**; on that GO the **agent actuates** the mechanics (merge/tag/promote) **bound to the reviewed
  SHA**, and re-verifies *what shipped == what was approved* by **tree equality** — a stronger guarantee than a
  keystroke, which never checked the merge target was the reviewed commit.
- **Honest labels** — solo single-party judgment with delegated mechanics is never relabeled as dual control.
- **Role, not tier** — the separation structure (builder ≠ reviewer ≠ ratifier), the gates, and the recorded GOs bind by **role**, independent of which model tier (§20) runs any seat; a cheaper or stronger model changes cost, never who ratifies.

## 20. Model tiering & fan-out economics

The kit reasons in **abstract model tiers** — `apex > deep > fast > light` — never concrete model names in its
core:

- **Policy** — judgment/verification seats **pinned** to the top proven tier (reviewer, security, orchestrator,
  verification always `deep`); builders **may run cheaper** where the task allows; high-stakes work **floored**
  (control-plane/sensitive/critical-path forced to `deep`, never escalated to the expensive `apex` tier).
  `apex` (a frontier model, used sparingly for cost) is **opt-in per task**, reachable only by the engineer and
  design/analysis seats, on ordinary-class work, only when explicitly requested and ratified at plan approval.
- **Binding** — you map the abstract tiers to your provider's models in one adopter-owned file
  (`.kit/model-map.conf`); the reference binds `deep=opus`/`fast=sonnet`/`light=haiku`/`apex=<frontier>`; a
  Codex/Gemini/Cursor adopter maps the same tiers to their own ladder. Opinionated about *structure*, neutral
  about *which model*.
- **Economics, measured** — a value-analysis model prices each run in *relative tier-weight units*
  ("deep-equivalents"), splitting the builder tier-discount from the orchestrator's reassembly tax so cheaper
  fan-out only counts as a win *net of* integration cost. In one recorded experiment the mixed-tier run was
  **~52% cheaper** than an all-top-tier run for a small wall-clock cost — **directional only, not a
  benchmark**: a single mixed-vs-baseline run-pair across 4 disjoint slices, noisy wall-clock, relative units
  not dollars, conservative weights (so 52% is if anything understated). It shows the *shape* of the trade-off,
  not a repeatable number.
- **Honest ceiling** — the kit *declares* the tier + intended model; whether a harness actually runs a subagent
  on that model is **native to the harness and un-gateable**. On a single-model harness, tiering degrades to
  advisory. *Declared ≠ obeyed ≠ bound.*

## 21. Orchestration at scale

The orchestrator fans engineers into **isolated git worktrees** (no cross-slice contention), runs each under
independent review, integrates through a serial merge queue, and **meters the run with a runaway kill-switch**
(token/step/agent ceilings; raising one is a ratified act), emitting an OTel run trace. Scaling further —
parallel epics, a worker pool, a merge queue at scale — is the roadmap's V2/Axis-B work; today's orchestration
is proven at **task-level fan-out**, and the conductor (the serial review/integrate tail) is the *measured*
bottleneck it will attack.

---

# PART V — PORTABILITY, ENVIRONMENTS & ADOPTION

## 22. Neutral on three axes — stack · harness · model

Every point where a project becomes concrete is a swappable axis, chosen by fit and disclosed honestly — a
standing principle (*neutrality by construction*): no axis defaults silently to "the proven/rich path"; the
agent recommends the best-fit option, states fit *and* maturity, and you ratify the trade-off.

- **Stack** — stack-neutral standards + a per-stack profile (10 reference profiles — TypeScript/Node, Python,
  Go, ML, Terraform, Java/Spring, Kotlin, C#/.NET, Rust, Data Engineering — as copy-and-adapt starting points on
  one conformance bar; generate your own for any stack against the same bar).
- **Harness** — Claude Code is the reference; any `AGENTS.md`-reading agent (Codex, Cursor, Copilot, Gemini)
  works via the `generic` adapter; bring your own. The enforcement floor holds **regardless of which harness
  issued the action**; inline interception is asymmetric and honestly disclosed (Claude Code stops actions at
  the keystroke; others at push/PR).
- **Model** — the abstract tiers of §20, bound per provider.

## 23. Environments & progressive delivery

A **Local → Staging → Production** environment strategy (config via environment, never conditionals in code;
never real production data outside prod without sanitization). **Ephemeral / preview environments** for
per-change validation, and a **bring-your-own deploy target** (`docs/adoption/DEPLOYMENT-ENVIRONMENT.md` — the
deploy platform is a chosen, disclosed axis, not a hard-wired dependency). Release rides **progressive
delivery**: staged rollout, canary, tested rollback, post-deploy smoke, with **DORA metrics** and a
definition-of-deployable gate.

## 24. Adoption paths & staying current

- **Greenfield** — export → `START-HERE` → Inception → the loop.
- **Brownfield** — merge into an existing repo (`docs/adoption/brownfield.md`), never overwrite; `.claude/`
  hygiene preserved.
- **Bring-your-own** — git host (`docs/adoption/vc-hosts.md`), deploy target, and work-tracker backend
  (`docs/work-tracking/adapters.md`) are all swappable.
- **Stay current — pull with a nudge, no telemetry.** Your adopted kit is a fork you own; nothing phones home.
  Releases are announced via GitHub Releases (Watch the repo); an advisory `doctor` check tells you when your
  vendored kit-base is behind; `kit-update.sh --from <kit>` shows what a newer release would change
  (offered / conflict / untouched) and **writes nothing** — you decide. Public releases are **milestone-gated**,
  so the nudge fires on a real release, not on every upstream commit.

---

# PART VI — TRUST, RIGOR & GOVERNANCE

## 25. Rigor you can verify — contract → reference → conformance → non-vacuity

Every capability ships as a **contract** (the binding requirement), a **reference implementation** (you own it,
rewrite freely), and a **conformance check** (executable proof it still satisfies the contract). What's rarer,
and load-bearing: **the conformance checks are themselves mutation-tested.** A "non-vacuity" sweep neuters a
check's failure path and proves it goes red — so a gate that *cannot fail* (a green that can never turn red) is
caught and fixed rather than shipped (with an honest `UNCOVERED` bucket for checks that are structurally
un-mutation-testable in place). Most tooling ships green checks nobody has proven can fail; Sparkwright treats a
check that can't fail as a defect — this is how the principles (Part I) and gates (Part II) are kept real rather
than decorative. The kit runs the full conformance suite enumerated in `conformance/verify.sh` (its `Summary:` line reports the live count) and **dogfoods every gate it gives you.**

## 26. Enterprise-grade security & governance

The enterprise addendum (`docs/enterprise/`) maps the foundational controls to recognized frameworks and adds
the scale concerns:

- **The safety boundary, honestly drawn** — the inline guard is a **speed bump**; the **git and CI chokepoints
  are the real, harness-equal boundary**. Stated plainly (`platform-safety-boundary.md`).
- **Compliance crosswalk** — SOC 2 · ISO 27001:2022 · NIST SSDF · SLSA.
- **AI-governance crosswalk** — NIST AI RMF · ISO 42001 · OWASP.
- **At scale** — secrets-at-scale, data governance + right-to-erasure, **ratification RBAC**, an audit-evidence
  trail (SHA-bound promotion records), and an **EXEC-BRIEF**. The **ROI model** and the **org-rollout**
  guide ship too, but both are **frozen pre-adoption (2026-08-19)** — written ahead of any adopter and
  carrying no shipped-value claim until real rollout evidence exists (ORG-ROLLOUT's Stage 1–4 maturity
  model is exempt from the freeze and stays canonical).
- **Operational security controls** (`docs/operations/`) — secrets-for-AI, egress control, break-glass.

## 27. The document set & templates

Sparkwright is a **document product** as much as a tooling one — the tangible artifacts an adopter fills in:

- **Governing docs** — `CLAUDE.md` (principles + Definition of Done), `DEVELOPMENT-PROCESS.md` (the loop,
  gates, ceremonies), `DEVELOPMENT-STANDARDS.md` (the quality bar), `START-HERE.md`, `ONBOARDING.md`,
  `MAINTAINING.md`, `RUNBOOK`.
- **~26 templates** — intake (`FEATURE-REQUEST`, `OPPORTUNITY-BRIEF`, `SHAPING-DOC`), execution
  (`TASK-CONTEXT-CONTRACT`, `TEST-PLAN`, `REVIEW-RECORD`), security & AI (`THREAT-MODEL`, `PRIVACY-REVIEW`,
  `SECURITY`, `EVAL-PLAN`, `AI-SYSTEM-CARD`, `AI-POLICY`, `AI-TRANSPARENCY-SIGNOFF`, `AI-ARTIFACT-LINEAGE`),
  sign-offs (`UAT-SIGNOFF`, `A11Y-SIGNOFF`), continuity/ops (`BIA`, `POSTMORTEM`, `WAIVER-REGISTER`), and setup
  (`PROJECT-CLAUDE`, `BACKLOG`, `TRACKER-SETUP`, `JIRA-SETUP`).
- **Conformance suite** — the executable checks registered in `conformance/verify.sh` (its `Summary:` line
  reports the live count) that prove the reference implementations still satisfy their contracts.

## 28. Honest ceilings & the maturity model

The single most differentiating property: the kit states, per capability, how strong its guarantee is —
**enforced** (a live gate blocks it), **advisory** (a nudge that doesn't block), or **declared** (an
attestation it can't observe at runtime). In the kit's own words: the guard is a speed bump (enforced boundary
= git/CI); model tiering is declared-not-obeyed; the operate-loop-in-anger is not-yet-proven on a live
production deploy; a green conformance run proves controls hold **and** that DR/resilience safety is
*documented* — **not that those procedures were tested** (the aggregate's own footer says so). **Maturity is a
stage, not a version:** `pre-adoption → release-candidate → adopted`; the `adopted` stage is reached when an
external team ships through the loop. The kit versions its own releases on its own cadence (currently
`v3.218.0`), so adoption is a maturity stage, not a version reset. Named non-reference harnesses carry an
honest maximum (a harness with no inline
interception is "floor-verified," never overclaimed). A kit that tells you exactly what's enforced versus
advisory versus declared is more trustworthy than one that claims magic.

## 29. How the kit is built & maintained

Sparkwright is a **versioned product built with the very loop it prescribes.** Every capability follows the
**contract → reference → conformance** convention (§25); improvements adopters find flow back upstream as PRs;
the kit holds itself to its own Definition of Done on every change, with the same separation-of-duties,
control-plane ratification, and mutation-tested gates it gives adopters. Releases are cut privately per slice
and **published to the public mirror at milestones** (not per-slice), so adopters track a stable line.
`MAINTAINING.md` documents the full build/versioning/contribution contract.

---

*This document is the canonical source for the public site and support materials. Keep it factual and
foundation-first; when a capability's strength changes, update its "enforced / advisory / declared" framing
here first, then the downstream materials.*
