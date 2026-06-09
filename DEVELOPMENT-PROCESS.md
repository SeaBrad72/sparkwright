# Development Process — Agentic SDLC

**Purpose:** Define *how work flows and improves over time* — from a project's first day through released, operating software.

**Applies to:** All projects, all contributors (human and AI), solo or multi-agent.

**Status:** MANDATORY — exceptions require explicit approval.

**Relationship to other docs:** This is the **process** companion to `DEVELOPMENT-STANDARDS.md` (the universal quality bar) and `CLAUDE.md` (authoritative principles + Definition of Done). This doc owns *flow, cadence, and improvement*; the standards doc owns *what good looks like* (with stack specifics in your chosen `profiles/<stack>.md`). When they overlap, `CLAUDE.md` is authoritative.

**Last Updated:** June 4, 2026

---

## 1. Governing Lens

One principle decides what belongs in this process and what doesn't:

> **Rituals that manage or forecast human effort die or transform. Rituals that clarify intent or improve quality get stronger.**

Agent effort is fast and cheap; the scarce resources are **human attention** and **integration risk**. So estimation, velocity, sprint commitment, and standups lose their reason to exist — while intent-clarifying and quality practices (Definition of Ready, acceptance criteria, demo/acceptance, retrospectives, adversarial review) get *more* powerful, because agents can run them more often and in parallel than a human team ever could.

A second pattern runs throughout: **define the rich model, ship a sensible default, make it per-project configurable, and let maturity/metrics raise the bar.** The backlog backend, autonomy tiers, error budgets, and scale stages all obey this — nothing heavy is imposed before it earns its place.

---

## 2. Roles (functions, not titles)

Roles are **functions, each mappable to a human or an agent** — not job titles. On a small team one person or agent holds several; the rule is that every function is *covered* and a few separations are *enforced*.

| Role | Owns | Typically |
|------|------|-----------|
| **Intent owner** (product) | The *why*, acceptance criteria, accepting increments | Human |
| **Lead / integrator** | The board, WIP limits, integration, ratifying retro/doc/governance changes, setting autonomy tiers | Human or lead agent |
| **Builder** | Implementing increments per standards | Agent or human |
| **Reviewer** | Independent review (quality, security lens) | Agent or human |
| **On-call / operator** | Watching production, triaging incidents | Human + agent-assist |
| **Security owner** | Threat modeling, the security/compliance gate | Human or specialized agent |

**Enforced separations:** the **Builder is never the sole Reviewer** of their own work; **ratification of governance/standards/doc changes is always human** (agents propose, humans ratify).

### Personas (who holds which function)

The functions above are authoritative. **Personas are lenses on them** — an enterprise puts named roles around the loop; this maps each to the function it holds, where it plugs in, and its entry/exit artifact. One person or agent may hold several (as above).

| Persona | Holds function(s) | Plugs in at | Entry → exit artifact |
|---------|-------------------|-------------|-----------------------|
| **Product Owner / BA** | Intent owner | Discover → Plan; accepts increments | `FEATURE-REQUEST` in → accepted increment out |
| **Designer** | *informs Intent owner (advisory — no standalone §2 function)* | Discover (UX input) → Review (a11y sign-off) | design assets / UX handoff in → accessibility sign-off |
| **Engineer** | Builder (often also Reviewer / Lead) | Plan → Build → Review | spec in → reviewed PR out |
| **QA Engineer** | Reviewer (test lens) + acceptance | Review + UAT acceptance gate (§9 — "Environments & promotion") | test strategy/cases in → UAT sign-off out |
| **DevOps / SRE** | On-call / operator | Release → Operate (promotion, deploy, rollback, monitoring) | promotion run in → operated service out |
| **Security owner** | Security owner | the security / ratification gate (§7, §13) | threat model in → gate pass / governed exception |
| **Lead / Agent** | Lead / integrator, Builder | the whole loop | the board in → integrated, ratified work out |

QA's UAT acceptance ties to the Dev→QA→UAT→Prod model (§9); Designer's a11y sign-off ties to the Definition-of-Done accessibility item.

---

## 3. Project Inception (Phase 0)

Before the steady-state loop can run, a greenfield project passes **once** through Inception. The loop assumes a project already exists; Phase 0 is how it comes to exist. It is a gate, not a stage you revisit.

```
INCEPTION (one-time) ──▶ [ Discover → Plan → Build → Review → Release → Done → Operate ↺ ]
```

**Inception checklist:**

1. **Charter** — the problem, the vision, success metrics, scope boundaries, and the named **intent owner**. (Project-altitude Discovery; see §5 for the per-item version.)
2. **Tech selection** — choose the stack via a **spike**, and record the choice and its alternatives as **ADR-000**. This is where "we haven't picked technologies yet" is formally resolved. Until done, downstream standards can't be specialized.
3. **Repo & environment** — repo created; branch protection on `main`; `.gitignore`; `.env.example`; reproducible local env (Docker / devcontainer); secrets management wired.
4. **Tooling & CI/CD baseline** — formatter, linter, test runner, and a CI pipeline with quality gates, appropriate to the chosen stack. Green pipeline on an empty project before feature work starts.
5. **Instantiate project artifacts** — create the project's `CLAUDE.md` (from `templates/PROJECT-CLAUDE-TEMPLATE.md`), `RUNBOOK.md`, the backlog (`BACKLOG.md` from `templates/BACKLOG-TEMPLATE.md`, or chosen backend), and a seed roadmap.
6. **Per-project configuration** — declare in the project `CLAUDE.md`: backlog backend (§6), autonomy-tier defaults (§13), SLO/error-budget posture (§9), review routing (§12), WIP limits, and environments (Dev/QA/UAT/Prod — see Environments & promotion).
7. **Assign roles** — fill each function in §2 with a human or agent for this project.
8. **Exit gate — "Inception Done"** — charter approved, stack decided (ADR-000), CI green, project `CLAUDE.md`/`RUNBOOK`/backlog in place, config declared, roles assigned. **Only then does the project enter the loop at Discover.**

Inception is itself subject to the standards (the empty repo already meets the structural bar) and produces its first artifacts per §15.

---

## 4. The Loop

Work flows continuously through stages — pulled, not pushed, the moment capacity frees. There is no timebox; **humans are the pacing metronome** via the checkpoints, and **WIP limits** protect review bandwidth and integration safety. The loop does not end at release — it closes through **Operate**, whose signals feed back into **Discover**.

```
        ┌─────────── L3 · PROCESS RETRO (periodic) → edits THESE docs ──────────────┐
        │  ┌──────── L2 · MILESTONE RETRO → adjust roadmap, backlog, docs, memory ──┐│
  ┌─────┼──┼─────────────────────────────────────────────────────────────────────┐ ││
  │     ▼  ▼                                                                       │ ││
DISCOVER → PLAN →│spec│→ BUILD → REVIEW →│merge│→ RELEASE →│accept│→ DONE → L1 RETRO │ ││
 (intake, (slice,  gate          ▲         gate  (deploy,    gate    │   (agent note)│ ││
  validate, DoR,                 │L0 loop        flags,             ▼               │ ││
  innovate) threat-model)        │               rollout,    durable learnings→memory│ ││
  ▲                              │               smoke,                              │ ││
  │   EVENT RETRO ◀──────────────┴─ any stage ─▶ CHANGELOG)                          │ ││
  │   (bug·red CI·blocker)                          │                                │ ││
  │                                                 ▼                                │ ││
  └──────────────── OPERATE & SUPPORT ◀── monitor · triage · resolve ◀───────────────┘ ││
        production signals (errors, tickets, usage, telemetry) feed Discover ─────────┘│
                                                                                        │
        adjust always exits into an artifact (PR · memory · backlog · docs) ────────────┘
```

| Stage | What happens | Exit |
|-------|--------------|------|
| **Discover** | Intake, **product validation** (§5), triage, innovation lens. | Validated candidate item |
| **Plan** | Slice into small vertical increments; acceptance criteria; spec for non-trivial work; **threat-model** sensitive features. Must reach **Definition of Ready**. | Spec gate (human) |
| **Build** | TDD per `DEVELOPMENT-STANDARDS.md`. L0 reflection-in-action runs continuously. | Self-verified, tests green |
| **Review** | "Did we build it *right*?" — code + adversarial/multi-lens + **security lens**, routed per ownership. | Merge gate (human) |
| **Release** | "Done → Live": deploy, feature flags, staged rollout, smoke test, CHANGELOG, rollback ready — see **Safe Change Delivery (§10)**; verified against `conformance/definition-of-deployable.md`. Breaking changes need explicit approval. | Live in production |
| **Done** | **Acceptance** ("right thing?"), Definition of Done met, **L1 retro** written. | Closed |
| **Operate** | Monitor, triage, resolve; **feed signals back to Discover** (§9). | Continuous |

**Milestones** are the planning/retro horizon, not the execution cadence.

---

## 5. Discovery & Intake

Discovery turns a raw idea into a **validated candidate** before it earns a place on the board. Lightweight — a handful of prompts, not a PRD:

- **Problem & user** — what problem, for whom? What's the current pain?
- **Evidence** — what tells us this is real (signal, request volume, telemetry, support tickets)? Not "we assume."
- **Success metric / hypothesis** — how will we know it worked? State it as a measurable hypothesis.
- **Rough scope & risk** — small enough to slice? Any obvious risk/complexity/compliance flags?
- **Innovation lens** — could AI materially improve this? Is there a reusable or product angle? (The surviving spirit of the archived innovation pipeline, as a prompt — not a separate doc.)
- **UX & accessibility lens** — is there a user-experience or visual surface? If so, the Designer informs the candidate here; capture rough flows/assets and flag the WCAG 2.1 AA accessibility obligation that the Definition of Done will check.

**Output:** a candidate item with intent + a validation note, ready for Plan. Items that fail validation go to the roadmap parking lot, not the board.

---

## 6. Work Items & Backlog (Pluggable)

The backlog is an **abstraction** so the storage backend swaps per project without changing the loop, gates, or retros. For multi-agent use it is also the **atomic work-distribution queue**.

**Work-item model (backend-agnostic):**
- **States:** `Backlog → Ready → In Progress → In Review → Released → Done` (+ `Blocked`).
- **Required fields:** title · intent (why) · acceptance criteria · size (one-flow small) · risk/complexity tag · owner (human or agent) · links (spec, PR, milestone).
- **Claiming:** entering `In Progress` is an **atomic** ownership change — no two agents grab the same item.

**Backend adapters — chosen per project (at Inception), declared in the project's `CLAUDE.md`:**

| Backend | When |
|---------|------|
| **`BACKLOG.md`** (repo-native) | **Default.** Zero setup, travels with the repo, directly agent-readable. Created at Inception/Plan. |
| GitHub (Issues + Projects) | GitHub-centric teams |
| Jira (Atlassian) | Enterprise / Jira shops |
| Azure DevOps (Boards) | Microsoft / .NET shops |
| Linear | Teams already in Linear |
| GitLab (Issues / Boards) | GitLab shops; self-hosted / regulated |

The loop, gates, and retros are identical regardless of backend — only storage swaps. An adapter must satisfy the contract: the states above, the required fields, and atomic claiming. **Per-tracker mappings** (state map · field map · atomic claim · fit notes) for each named backend, plus a "bring your own tracker" recipe, are in `docs/work-tracking/adapters.md`. General PM tools (Asana/Monday/ClickUp) are intentionally not named here — they lack a race-safe atomic-claim primitive; use the bring-your-own recipe with its caveats.

### Two altitudes: roadmap vs. board
- **Roadmap** (strategic) — vision, phases, parking lot, success metrics. Seeded at Inception; feeds **Discover**; reviewed at milestone retros.
- **Flow board** (tactical) — the work-item queue running the loop.

The roadmap answers *what should we build and why*; the board answers *what is in flight now*. Roadmap items decompose into board items at Plan.

### Prioritization & work types

Validation (§5) decides whether an item is *worth doing*; prioritization decides *what's next*. The backlog is **ordered, not a pile**:

- **Ordering signal:** value × urgency ÷ effort-risk. The **intent owner** ranks by value; the **lead** breaks ties on risk/dependencies. No story points — the risk/complexity tag plus slice-size discipline replace estimation.
- **Work types share one board** and are prioritized *against each other*, not in silos: **feature · bug · tech-debt · spike · recurring/maintenance** (§15).
- **Tech debt is first-class** — not just "captured" at Done. It enters the backlog as tagged items, is prioritized alongside features, and gets a standing **paydown allocation** (a fixed share of capacity per cycle) so it's serviced continuously rather than deferred until it bites. Debt the team chooses *not* to pay is recorded with that decision.

---

## 7. Gates & Checkpoints

Humans gate only where judgment matters; agents flow at machine speed between gates. **Gates are also the autonomy boundaries** (§13) — an agent's autonomy level is how far it proceeds before a gate.

| Gate | Question | Owner |
|------|----------|-------|
| **Definition of Ready** | Safe to start? (criteria present, sliced, deps known) | Human/lead |
| **Threat model** *(sensitive/regulated features)* | What can go wrong security/privacy-wise? | Security owner |
| **Spec gate** | Is the plan sound before building? | Human |
| **Review** | Did we build it *right*? (quality, **security lens**, standards) | Different agent + human |
| **Eval gate** *(AI features)* | Do model/prompt outputs meet the eval bar — and did this change not regress evals? | Builder + reviewer |
| **Compliance gate** *(regulated domains)* | Does this meet the regulatory bar before release? | Security owner + human |
| **15-Factor conformance** *(deployable services)* | Does the architecture satisfy the applicable 15 factors? (`conformance/15-factor-checklist.md`) | Reviewer + lead |
| **Definition of Deployable** *(deployable services)* | Is the release safe to promote — rollback ready, smoke + monitoring wired? (`conformance/definition-of-deployable.md`) | Release manager + reviewer |
| **DR readiness** *(data services)* | Is DR provable — BIA done, RTO/RPO tiered, restore drill passed? (`conformance/dr-readiness.md`) | On-call / operator + reviewer |
| **Resilience readiness** *(deployable services)* | Do resilience + load/soak verifications pass — breaker trips, degrades gracefully, within perf budget? (`conformance/resilience-readiness.md`) | On-call / operator + reviewer |
| **Acceptance** | Did we build the *right thing*? (intent/need) | Intent owner |
| **Definition of Done** | Truly complete? (per `DEVELOPMENT-STANDARDS.md`) | Automated + human |

Review and Acceptance fail *differently* and are kept distinct. Threat-model, eval, compliance, 15-factor, Definition-of-Deployable, DR-readiness, and Resilience-readiness gates are **conditional** — each applies only where it fits: threat-model to sensitive/regulated features, eval to AI features, compliance to regulated domains, 15-factor / Definition-of-Deployable / Resilience-readiness to deployable services, DR-readiness to data-handling work — not every item (don't impose them where they optimize nothing). For AI features, **evals are the dev-time quality bar** — the AI analog of TDD: written alongside the feature, run in CI, and gating like tests (see `DEVELOPMENT-STANDARDS.md`).

---

## 8. Retrospectives (Nested)

Same structure at every level (fractal); different scope and frequency. **Every retro must exit into an artifact** — that routing *is* the "adjust" step. A retro that changes nothing is theater.

| Level | Trigger | Who | Output → Destination |
|-------|---------|-----|----------------------|
| **L0 · Reflection-in-action** | Every tool result / test run | Agent, silently | Course-correction (no artifact) → immediate behavior |
| **L1 · Increment retro** | Item → Done / PR opened | Building agent | Tiny structured note → PR/item; durable learnings → memory; doc proposals → L2 |
| **L2 · Milestone retro** | Milestone close / time-fallback | Human + lead, fed by L1 notes | Pattern-level decisions → roadmap, backlog, the two docs, memory |
| **L3 · Process retro** | Periodic / when the process bites | Human | Process improvements → `DEVELOPMENT-PROCESS.md` + `DEVELOPMENT-STANDARDS.md`; **kit-level improvements → PR upstream to the canonical kit** (`MAINTAINING.md` §4; humans ratify) |
| **Event retro** | Bug · red CI · rejected review · blocker — *any stage* | Whoever hit it | Blameless triage → logged on item; prevention → backlog/docs |

**L1 increment-retro prompt (kept tiny — seconds to write):**
> Goal vs. what I actually did · friction/surprises · spec deviations & why · what future work should know · proposed adjustments.

**Two ratified defaults:**
1. **L1 is a tiny note** — heaviness kills the per-increment habit.
2. **Agents propose, humans ratify** — agents never silently edit the standards/process docs that govern them; proposed changes surface at L2.

**Event retro = impediment / bug / anomaly handler.** Handles in-flight blockers, bugs, and anomalies. *Production* incidents follow Operate & Support (§9) and the Incident Response / postmortem standard in `DEVELOPMENT-STANDARDS.md` §15.

---

## 9. Operate & Support

The loop is only closed when production teaches the next iteration. Operate is **continuous**, runs alongside the loop, and **feeds Discover**.

**The support arc:**
```
monitor → detect (alert · error spike · support ticket · user feedback · usage telemetry)
        → triage (severity P0–P3) → route → resolve → feed back to Discover
```
- **Route** decides: fix-now (Event retro → hotfix), backlog item, or spike. P0/P1 escalate to Incident Response + postmortem (`DEVELOPMENT-STANDARDS.md` §15).
- **On-call / watch** — a human is on-call; **agents assist**: detect, summarize, correlate, and *propose* remediation. Production actions obey the autonomy/reversibility rules in §13 (irreversible prod actions are human-gated).
- **Feedback edge** — production signals (errors, tickets, telemetry, user feedback) are **first-class Discover inputs**. This is the arc that turns a delivery pipeline into a closed-loop SDLC.

**SLOs & error budgets (per service, per project):**
- Define SLOs and an error budget for production services.
- **Default: soft** — surface budget burn in metrics and retros; do not hard-gate releases.
- **Maturity step: hard-gate** — a project at production scale may promote to SRE-style gating (non-critical releases freeze when the budget is burned until reliability recovers). Mirrors the Stage 1–4 scale progression in `DEVELOPMENT-STANDARDS.md`. The same soft→hard promotion applies to the DORA change-failure rate / MTTR — see `docs/operations/dora-metrics.md`.

**Cost / spend governance (per project):** track delivery and runtime cost — including agent/compute spend, which can grow fast. **Default: tracked and surfaced in metrics; a spend-gate (alert/throttle on budget burn) promotes at maturity** — same soft→gating progression as error budgets.

### Environments & promotion

Changes flow through a promotion pipeline with a gate between each tier:

| Tier | Purpose | Promotion gate into it |
|------|---------|------------------------|
| **Dev** | Active development / integration | CI green on the PR |
| **QA** | Automated + integration acceptance | Dev green + test suite/integration pass |
| **UAT** | Stakeholder / business acceptance | QA green + acceptance sign-off (PO/QA) |
| **Prod** | Live users | UAT sign-off + **human approval (release manager)** |

**Production promotion is always human-gated** regardless of agent autonomy tier (§13) — it is in the irreversible/high-blast set. Promotion is forward-only through the tiers; no skipping straight to Prod.

A project may **collapse tiers with a one-line reason** (e.g. a tiny internal tool runs Dev→Prod) — but the contract is: at least one non-prod tier, gated promotion, and a human gate on prod. Environments and per-tier deploy triggers are declared in the project `CLAUDE.md` (§3).

For containerized services, promotion moves an **attested image by digest** (not a rebuilt tag) across Dev → QA → UAT → Prod; rollback is a redeploy of the previous digest. Kubernetes + Helm is **one** reference orchestration pattern (`profiles/typescript-node/deploy/`); the principle — promote by digest, not tag — holds for any orchestrator.

### Outcome validation

Discovery (§5) commits a **success-metric hypothesis**; Operate is where it's checked. After a feature has been live long enough to read signal, validate it against its hypothesis:

- **Hit** → record the win; the item is truly Done (outcome, not just output).
- **Miss / inconclusive** → route back to **Discover** as new evidence — iterate, pivot, or retire. A shipped feature that doesn't move its metric is a discovery input, not a closed item.

This makes the loop measure *value delivered*, not just *work completed* — and is the product half of the production→Discover feedback edge.

---

## 10. Safe Change Delivery

How to change a running system without breaking it — the release-engineering mechanisms behind the **Release** stage (§4) and the L2 "merge behind flags" autonomy (§13). Most are maturity-gated: a Stage-1 project uses the basics; depth promotes with scale. (Supply-chain integrity below is the exception — it is a required baseline CI gate, `DEVELOPMENT-STANDARDS.md` §14.)

### Feature flags
- **Purpose** — decouple deploy from release: merge incomplete or risky work to trunk **behind a flag**, keeping `main` always deployable. This is what makes trunk-based development and L2 agent autonomy safe.
- **Kill-switch** — flag-off is the **fastest rollback**; prefer it to a redeploy for flag-guarded changes.
- **Lifecycle & retirement** — every flag has an owner and an expected end state. **Stale flags are tech debt**: they enter the backlog as tech-debt items (§6) and are cleared in recurring maintenance (§15). A flag with no expiry is a defect.

### Database & schema migrations
- **Expand-contract** (parallel-change) — add the new shape → migrate/backfill → switch reads → remove the old. Never a breaking change in one step.
- **Backward-compatible & reversible** — each migration runs against the *previous* app version; every migration has a tested down-path.
- **Zero-downtime by default** — no long locks; large backfills run async/batched. Migrations are versioned — never manual production DDL.

### Progressive delivery
- Release by **canary or blue-green**, not big-bang: ship to a slice, watch SLOs/error rate (§9), then widen or abort.
- **Default:** staged rollout (staging → small % → full). **Maturity step:** automated canary analysis. Same soft→gating progression as error budgets. **Reference: `docs/operations/progressive-delivery.md`** (strategies, multi-stage smoke gates, canary analysis).

### Rollback vs. forward-fix
- **Default to rollback** when production is degraded and the cause isn't obvious early in the incident — restore service first, diagnose after.
- **Forward-fix** only when rollback is riskier than the bug (e.g., an irreversible migration already applied) or the fix is trivial and verified.
- Preference order: **flag-off → redeploy previous → revert + redeploy**. Every release declares its rollback path *before* it ships (the "rollback ready" in §4) — captured in `conformance/definition-of-deployable.md`.

### Supply-chain integrity *(required CI gates)*
Pin/lock dependencies; scan dependencies for vulnerabilities; generate an **SBOM**; attest build **provenance** for released artifacts. These are **required CI gates on every PR** (`DEVELOPMENT-STANDARDS.md` §14), not optional hooks. Tooling is a project choice (**→ profile**; e.g., the wired Semgrep / Sonatype). A deeper full-tree audit also runs in recurring maintenance (§15).

### Versioning & release identity *(configuration hook)*
Tag releases with **semantic versioning**; the CHANGELOG (§15) records what each version changed. Breaking changes bump major and require explicit approval (§4).

---

## 11. Rituals We Keep, Adapted

- **Definition of Ready** — readiness gate before Build.
- **Acceptance criteria + INVEST slicing** — testable criteria, small vertical increments.
- **Acceptance checkpoint** — intent validation, distinct from code review.
- **Spike** — explicit time-boxed research/de-risk work-item type for unknowns, *before* committing a plan (used heavily at Inception for tech selection).
- **Adversarial / multi-lens review** — builder agent + critic agent, or a spec reviewed in parallel by product / architecture / test / security lenses. Parallel perspectives are nearly free agentically — use them.

## Rituals We Drop (and why)

- **Story-point estimation / planning poker** — forecasts scarce *human* effort; agent effort is cheap. Replaced by slice-size discipline + a risk/complexity tag.
- **Time-boxed sprint planning** — replaced by continuous backlog refinement + WIP pull.
- **Daily standup (as a meeting)** — the board *is* the status. Replaced by an on-demand board digest.
- **Burndown / velocity charts** — replaced by the flow + DORA metrics in §14.

---

## 12. Multi-Agent Coordination

These mechanics work for a single agent spawning sub-agents today and scale to many parallel agents.

- **Shared board = work-distribution queue.** The single source of work-truth that humans and agents read and claim from. Replaces the standup: state is queryable, not verbally synced.
- **Atomic work-claiming.** Entering `In Progress` is an atomic ownership transition; no double-claims.
- **Worktree / branch isolation.** Parallel agents work in isolated git worktrees / short-lived branches.
- **Integration cadence.** Trunk-based with frequent, small integrations — avoid big-bang merges across streams.
- **Conflict resolution.** Defined precedence and a re-sync procedure when parallel work overlaps.
- **Review routing / ownership.** CODEOWNERS-style mapping of who/which agent/lens reviews what. **An agent never reviews-and-merges its own work.** Ratification authority by role → §13 and `docs/enterprise/ratification-rbac.md`.
- **WIP limits.** Cap concurrent work to protect integration safety and human review bandwidth.
- **Stakeholder visibility.** The board is the live status; beyond it, surface progress to non-builder stakeholders via an on-demand board digest, milestone demos, and the flow/DORA metrics (§14) — on a cadence and in a format the adopting org sets. (A configuration point, not a fixed ritual.)

---

## 13. Agent Governance

The layer that makes many agents safe and accountable. Built on the same lens: rich model, sensible default, per-project, earned by metrics.

### Autonomy tiers
Autonomy is a spectrum; an agent's tier is **how far it proceeds before a human gate**. The tier for a given action is set by **risk × reversibility × blast radius** — reversibility is the master variable.

| Tier | Behavior |
|------|----------|
| **L0 · Propose-only** | Read, analyze, draft — no changes without approval |
| **L1 · Act + report** | Make reversible changes, open PRs, report after |
| **L2 · Act within bounds** | Merge behind flags / within WIP cap and defined safe lanes |
| **L3 · Autonomous** | Operate unattended in explicitly defined safe lanes |

**Default action → tier mapping (per-project configurable, set at Inception):**

| Action | Default | Rationale |
|--------|---------|-----------|
| Read / analyze / draft spec | L3 | No blast radius |
| Write code + tests, open PR | L1–L2 | Reversible, gated at merge |
| Merge to trunk | Human gate | Integration risk |
| Deploy to production | Human gate | High blast radius |
| Delete data · rotate secrets · incur spend | Human gate | Irreversible |

**Irreversible / high-blast-radius actions are always human-gated regardless of tier.** A project raises an action's tier as the agent-quality metrics earn it.

### Ratification roles & exceptions

"Humans ratify" (§12) means a **named role**, not merely "a human." Roles and what each may ratify:

| Role | May ratify |
|------|-----------|
| **Project owner** | requirements & scope, architecture (ADRs), breaking changes |
| **Code owner** (per CODEOWNERS) | code PRs in their domain — the independent reviewer (builder ≠ sole merger, §12) |
| **Security owner** | governing-doc changes (`CLAUDE.md` / STANDARDS / PROCESS), gate definitions, **supply-chain / OIDC posture exceptions**, secret-rotation policy, autonomy-tier raises |
| **Release manager** | production deploys / promotions, rollbacks |

One person may hold several roles in a small org, but **never both the builder and the sole ratifier of the same change**. Roles map to GitHub via CODEOWNERS + branch-protection required reviewers.

**Governed exceptions.** Required gates (§14 of the standards) and security posture are **universally required — never silently "conditional."** An exception is an auditable event: a **security-owner-ratified, time-boxed** record stating what is waived, why, the expiry, and the compensating control. → `docs/enterprise/ratification-rbac.md`.

### Auditability
Every agent action is **traceable**: which agent, what, when, against which work item — via commit/PR attribution, work-item ownership, and L1 retro notes. No anonymous agent changes.

### Agent-quality metrics
Track per agent (or agent type) and use to adjust autonomy: **rework rate · review-rejection rate · escalation rate · retro-action quality**. Reliability earns autonomy; regressions revoke it.

### Enforcement reference
This matrix is tool-neutral. For **Claude Code** it is enforced by the committed `.claude/` layer: `settings.json` permission globs + a `PreToolUse` guard hook (`.claude/hooks/guard.sh`) that denies the irreversible/high-blast set above and protects its own integrity, plus `reviewer`/`security-reviewer` subagents for the §12 separations. Conformance: `conformance/agent-autonomy.sh` proves a tier breach is actually denied. Other agent runtimes express the same matrix their own way.

The guard is a **best-effort speed bump for honest agent mistakes, not a security boundary** — a deny-list over a shell cannot contain a determined or compromised agent. The real boundary is platform-owned (network-egress allowlist, separate prod credentials, sandboxed filesystem, scoped tokens); see [`docs/enterprise/platform-safety-boundary.md`](docs/enterprise/platform-safety-boundary.md). Adopt both.

---

## 14. Flow Metrics

Replacing velocity/estimation, mapped to the industry-standard **DORA** four for portability:

| Our metric | DORA equivalent | Measures |
|------------|-----------------|----------|
| Cycle time (intake → Done) | Lead time for changes | Speed |
| Release cadence | Deployment frequency | Throughput |
| Rework / defect rate | Change-failure rate | Quality |
| Time-to-resolve (Operate) | MTTR | Resilience |
| **Review latency** | — | The human bottleneck (agentic-specific) |
| **Retro-action closure** | — | Does the learning loop actually close? |

The last two have no DORA equivalent and are the agentic-specific signals: review latency (the real constraint) and whether *adjust* actually lands. **Collect them:** `docs/operations/dora-metrics.md` (per-metric GitHub data source + the maturity-gating path + a dashboard pattern); `scripts/dora.sh` reports the GitHub-derivable subset (release cadence, PR lead time, review latency).

---

## 15. Artifact Flow & Recurring Work

Artifacts are created **and maintained**, not written once. Each has a producing stage, a refresh trigger, and an owner.

| Artifact | Produced at | Refreshed when | Owner |
|----------|-------------|----------------|-------|
| Project `CLAUDE.md` | Inception (from template) | config/stack change | lead |
| ADR (incl. ADR-000 stack) | Inception / Plan | decision superseded | deciding agent + human |
| Spec (design) | Plan | scope changes | author agent + human |
| Design assets / UX handoff | Discover → Plan (referenced in spec) | UX surface changes | designer (informs intent owner) |
| Code + tests | Build | every change | building agent |
| README | Build / Done | feature or setup change | building agent |
| `.env.example` | Inception / Build | any new env var | building agent |
| `RUNBOOK.md` | Inception, then Release | deploy or ops change | shipping agent |
| CHANGELOG | Release | every user-facing change | shipping agent |
| L1 retro note | Done | per increment | building agent |
| Postmortem (`templates/POSTMORTEM-TEMPLATE.md`) | Incident (P0/P1) | — | responder + human |
| Pattern library | L2 / L3 retro | new reusable pattern found | lead |

The Definition of Done *requires* several of these; this flow says *when in the loop* each appears and who keeps it current.

### Recurring & maintenance work
Cadence-triggered (not intake-triggered) work that flows through the same board as a distinct item type, with the same gates and Definition of Done:
- Dependency audits / vulnerability scans + SBOM refresh — the **deeper, full-tree** periodic audit (monthly + pre-release) complementing the per-PR dependency gate (`DEVELOPMENT-STANDARDS.md` §14)
- Security scans
- Stale feature-flag cleanup (flag debt)
- Backup-restore verification (prove DR actually works — how: `docs/continuity/backup-restore-drill.md`; gate: `conformance/dr-readiness.md`)
- Resilience drill refresh (re-run fault-injection + load/soak after any dependency or failure-path change — how: `docs/operations/resilience-verification.md`; gate: `conformance/resilience-readiness.md`)
- Documentation-freshness sweeps (RUNBOOK/README still accurate)

---

## 16. Quick Reference

```
START   Inception (Phase 0, once): charter · pick stack (ADR-000) · repo+env · CI green
        · instantiate project CLAUDE.md/RUNBOOK/backlog · set config · assign roles → enter loop
LOOP    Discover → Plan → Build → Review → Release → Done → Operate ↺ Discover
        flow-based, WIP-limited, pull when ready; Operate feeds Discover
BACKLOG ordered by value×urgency÷risk (intent-owner ranks, lead breaks ties)
        feature·bug·tech-debt·spike·recurring share one board; tech-debt = paydown allocation
ROLES   intent-owner · lead/integrator · builder · reviewer · on-call · security-owner
        (functions, human OR agent; builder ≠ reviewer; humans ratify)
GATES   Ready · [threat-model] · Spec · Review(+security) · [eval] · [compliance] · [15-factor] · [deployable] · [DR] · [resilience] · Accept · Done
RETROS  L0 in-action · L1 increment (agent) · L2 milestone (human) · L3 process · Event
        every retro exits into an artifact (PR → memory → backlog → docs) = "adjust"
SHIP    flags (kill-switch · retire stale=debt) · expand-contract migrations · canary/blue-green
        rollback > forward-fix (flag-off→redeploy→revert) · SBOM+provenance (required CI gates §14) · semver+tag
OPERATE monitor → triage → resolve → feed Discover; SLO/error-budget + cost soft→gating by maturity
OUTCOME validate shipped feature vs its success-metric hypothesis; misses → Discover (value, not output)
VISIBILITY board digest · milestone demos · DORA metrics → stakeholders (cadence set per org)
COORD   shared board claim-queue · atomic claim · worktree isolation · no self-merge · WIP
GOVERN  autonomy L0–L3 by risk×reversibility · irreversible=human-gated · audit all · earn by metrics
METRICS cycle time · review latency · rework · retro-closure  (↔ DORA: lead time/freq/CFR/MTTR)
KEEP    DoR · acceptance criteria · INVEST slicing · acceptance demo · spike · adversarial review
DROP    estimation · sprint planning · standup-meeting · velocity
RULE    manages-effort rituals die · clarifies-intent rituals get stronger
        define rich model · ship default · per-project · raise the bar by maturity/metrics
```

---

**Remember:** the loop is only real when *adjust* changes an artifact, and only *closed* when production feeds the next idea. A project earns its place in the loop by passing Inception first.
