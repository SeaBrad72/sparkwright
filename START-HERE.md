# START HERE — Incepting a New Project

You've dropped Sparkwright into a new project. This guide walks you (human or agent) through **Inception (Phase 0)** — the one-time gate that turns an empty repo into a project ready to run the loop. Full detail: `DEVELOPMENT-PROCESS.md` §3.

Work top to bottom. Don't enter the development loop until the **Inception Done** checklist at the end is fully checked.

Leaders / evaluators: read [docs/enterprise/EXEC-BRIEF.md](docs/enterprise/EXEC-BRIEF.md) first (what / why / risk / ROI); engineers continue to Inception below.

**Before anything:** run `sh scripts/preflight.sh` (add `--stack <yours>` once you've chosen) — it checks prerequisites (jq, git, your toolchain) and prints install hints. New to the terms here? See [GLOSSARY.md](GLOSSARY.md).

---

## You do not need to read all of this

Sparkwright ships a lot of files because it covers the whole lifecycle — but **you read almost none of
it up front.** Per-task reading is small and just-in-time (`AGENTS.md` is short, read when an agent
acts). Here is the whole map at a glance.

**Your first 5 (the core path):**
1. **`START-HERE.md`** (this file) — Inception.
2. **`CLAUDE.md`** — principles + the Definition of Done (the bar).
3. **`DEVELOPMENT-PROCESS.md`** — the loop (Discover → Plan → Build → Review → Release → Operate).
4. **`profiles/<your-stack>.md`** — the concrete *how* for your stack (chosen at Inception).
5. **`AGENTS.md`** — the 1-page agent brief (if you drive with an agent).

*This is the **set**; §0 Orient below is the reading **order** for your first sitting — you read 1–3, **skim** `DEVELOPMENT-STANDARDS.md`, and open your profile when you pick it at Inception step 2.*

**Everything else is pull-not-push** — you reach for it *when a trigger fires*, never before:

| When this is true… | …pull this |
|--------------------|-----------|
| You hit a specific quality bar (security pattern, retry/backoff, CI config) | `DEVELOPMENT-STANDARDS.md` + your `profiles/<stack>.md` |
| Regulated / sensitive / audited domain | `docs/enterprise/` (compliance crosswalk · secrets-at-scale · audit-evidence) |
| Live system — deploy, resilience, metrics | `docs/operations/` (progressive delivery · resilience · DORA · review-lane) |
| Building an AI feature — handling its API key + the eval boundary | `docs/operations/secrets-for-ai.md` |
| Data service — backup/restore, DR | `docs/continuity/` |
| You need an artifact (spec, RUNBOOK, threat model, review record) | `templates/` — pull the one you need |

The conditional **gates** already work this way — each activates only when its trigger applies. The
docs are discovered the same way. Nothing here is optional-to-*skip*; it is optional-to-*read-now*.

---

## New to enterprise SDLC?

**Coding is the task. Software engineering is everything that has to go *around* the code for an
enterprise** — tests, environments, security, governance, observability, release safety. Vibe coding
gets you working code; it does not get you software an enterprise can trust, operate, and not be
harmed by. **This kit is that "everything around it."** This section places you by *experience*; the
next one places you by *role*. Two minutes here saves you hours later.

Pick the lane that sounds like you. Non-punitive — feels too basic? Jump up a lane.

- **Novice / Coding-first** — *"I can make code work (often with AI), but tests, environments,
  security, and governance are new to me."* → skim the pillars below, then take the Inception steps.
- **Adjacent** — *"I've worked in or around software delivery (product, PM, BA) — I know these
  practices exist but haven't done them myself."* → the pillars below (skip what you know), then Inception.
- **Practitioner** — *"I've shipped enterprise software; route me to the contract."* →
  the principles (`CLAUDE.md`), then straight to §0 Orient. Skip the pillars.
  *Senior / principal / architect:* your home is the architecture lens at the §7 review gate (ADRs,
  15-factor), the autonomy-tier model (`DEVELOPMENT-PROCESS.md` §13), and the enterprise layer
  ([docs/enterprise/](docs/enterprise/)) — `MAINTAINING.md` if you'll extend the kit itself.

> **Don't have the product or design figured out yet?** Most of this kit assumes you arrive with a
> *Ready* backlog. If you're upstream of that — raw idea, no validated problem yet — start with the
> optional **[discovery loop](docs/discovery/discovery-loop.md)** (FRAME → SHAPE → Ready), then come back.

**The pillars (Novice + Adjacent).** You don't need to learn all of this before you start — you need
to know it *exists* and *why*, then learn each piece as you hit it: **why an enterprise needs it →
learn it for real → where the kit applies it.**

| Pillar | Why an enterprise needs it | Learn it (canonical) | Where the kit applies it |
|--------|----------------------------|----------------------|--------------------------|
| **Test-Driven Development** | Change without fear; tests are the safety net that lets agents move fast | [Martin Fowler — TDD](https://martinfowler.com/bliki/TestDrivenDevelopment.html) + the worked demo: [docs/onboarding/first-feature-tdd.md](docs/onboarding/first-feature-tdd.md) | `DEVELOPMENT-STANDARDS.md` §7 + your `profiles/<stack>.md` |
| **15-Factor architecture** | Apps that run the same everywhere, scale, and don't lose data | [12factor.net](https://12factor.net) (+ the 3 modern factors) | `DEVELOPMENT-STANDARDS.md` §13 + `conformance/15-factor-checklist.md` |
| **Security & privacy** | Enterprises hold real user data; a breach is existential | [OWASP Top 10](https://owasp.org/www-project-top-ten/) | `DEVELOPMENT-STANDARDS.md` §2 + `SECURITY.md` + `docs/enterprise/data-governance.md` |
| **Governance & autonomy** | Agents (and humans) must not be able to cause irreversible harm | *kit-defined — learn it in the kit doc →* | `DEVELOPMENT-PROCESS.md` §12–13 + `.claude/` guard |
| **Environments & scale** | Prod is not your laptop; promotion is gated; production is human-gated | [12factor.net](https://12factor.net) (dev/prod parity) | `DEVELOPMENT-PROCESS.md` "Environments & promotion" |
| **Observability** | If you can't see it in prod, you can't operate it | [the three pillars](https://opentelemetry.io/docs/concepts/observability-primer/) | `DEVELOPMENT-STANDARDS.md` Factor 14 + `docs/operations/` |

> **You can't break things by reading the wrong lane.** The kit's runtime guard is a **best-effort
> speed bump, not a security boundary** (it raises friction on many irreversible actions but does not
> stop a determined bypass — see [`docs/operations/runtime-guards.md`](docs/operations/runtime-guards.md));
> the real safety net is the platform controls your org owns. CI gates run on every project regardless
> of what you read. This section makes you *educated*; the guardrails *reduce* risk — they don't remove it.

---

## Who are you? Start here

This guide's numbered steps are the **engineer/lead Inception path**. If you're a different role, start at your row — you generally won't need the numbered engineer steps below. The lane above is about *how much SDLC you know*; this is about *which function you hold* — the two are independent, and the authoritative function map is [`DEVELOPMENT-PROCESS.md` §2](DEVELOPMENT-PROCESS.md).

| If you are… | Start with | Then |
|-------------|-----------|------|
| **Product Owner / BA / stakeholder** | skim `CLAUDE.md` for context, then `templates/FEATURE-REQUEST-TEMPLATE.md` | hand it to the team or drop it on the board (`DEVELOPMENT-PROCESS.md` §6) — no engineering setup needed |
| **Designer** | the UX & accessibility lens in Discovery (`DEVELOPMENT-PROCESS.md` §5) + the a11y items in the Definition of Done (`CLAUDE.md`) | attach assets to the spec; sign the a11y check (`templates/A11Y-SIGNOFF-TEMPLATE.md`) at Review |
| **QA Engineer** | the testing standards (`DEVELOPMENT-STANDARDS.md` §7) + the UAT acceptance gate (`DEVELOPMENT-PROCESS.md` §9) | own the test plan (`templates/TEST-PLAN-TEMPLATE.md`) and the UAT sign-off (`templates/UAT-SIGNOFF-TEMPLATE.md`) |
| **DevOps / SRE** | the environment model (`DEVELOPMENT-PROCESS.md` §9) + `RUNBOOK.md` + CI (`DEVELOPMENT-STANDARDS.md` §14) | own promotion & operate |
| **Security Owner** | the §7 security gate + ratification (`DEVELOPMENT-PROCESS.md` §12–13) | own the threat model (`templates/THREAT-MODEL-TEMPLATE.md`) and the privacy review where the data classification demands it |
| **Engineering leader / evaluator** | `docs/enterprise/EXEC-BRIEF.md` (the case, the ROI frame, the rollout shape) | come back here when a team is ready to run Inception |
| **Engineer / Lead — new project** | **run `sh scripts/incept.sh`** (it `git init`s the repo for you if you're not already in one, then installs the runtime guard), then work the judgment steps below | full Inception (steps 1–7); use `--harness <list>` (default `claude-code`; pick `generic` for any AGENTS.md-reading harness; comma-separate for several — see `docs/operations/harness-adapters.md`) |
| **Engineer — existing repo (brownfield)** | **`docs/adoption/brownfield.md`** (copy-in + `.claude/` merge + guard verify) | then the Inception judgment steps below; if your environment carries a foreign process-skill library (e.g. superpowers), see **`docs/adoption/skill-rosters.md`** |

> **Non-builders: the rigor is carried, not waived.** You don't hand-craft tests or 15-factor config.
> When your intent becomes code, the agent builds it test-first and the CI gates enforce 15-factor,
> observability, and security on **every** PR — regardless of who filed it. Your own artifact has its
> own bar (testable acceptance criteria, an a11y sign-off); the code that realizes it gets the full
> standard. Routing by role changes *which doc you open*, never *which gate applies*.

(Note: `incept` renames the kit's principles `CLAUDE.md` to `ENGINEERING-PRINCIPLES.md` and stamps a new project `CLAUDE.md` — your project guide. The glossary and START-HERE references to the *principles* file mean `ENGINEERING-PRINCIPLES.md` after Inception.)

> **Bootstrap order:** run `incept` *first* — never commit before it. See the incept-first sequence in [`docs/adoption/inception-bootstrap.md`](docs/adoption/inception-bootstrap.md) (summarized at `DEVELOPMENT-PROCESS.md` §3).

---

## 0. Orient
Read, in order: this file → `CLAUDE.md` (principles + Definition of Done) → `DEVELOPMENT-PROCESS.md` (the loop) → skim `DEVELOPMENT-STANDARDS.md` (the universal bar — deep-dive only on a specific quality bar, per the front-door map above). Don't read profiles yet — you pick one below (it's in your "first 5" *set*, opened here at step 2). **This is not a quick step, and no honest minute-count fits it:** read end to end those four documents run to well over a thousand lines. The honest way through is the front-door map above — read this file and `CLAUDE.md` properly, then let the map tell you which section of the other two your current task actually needs. Orienting is something you finish over your first few slices, not before them.

## 1. Charter
Write the project charter (into the project `CLAUDE.md` you'll create in step 5):
- **Problem & users** — what, for whom, current pain.
- **Vision & success metrics** — what success looks like, measurably.
- **Scope boundaries** — explicitly in / out.
- **Intent owner** — who owns the *why* and accepts increments.

## 2. Choose your stack → ADR-000  ⭐ the key step
Decide the technology stack. This is a **spike** if there's genuine uncertainty — compare options, don't guess.

**Compare the shipped stacks:** [docs/STACK-SELECTION.md](docs/STACK-SELECTION.md) — a matrix of "Best for / Avoid when" plus full-stack (SPA + API) guidance. (Don't see your stack? Generate one — option B below.)

**Derive, don't default.** Pick from the *shape of the work*, not from familiarity — use the [derivation rubric + steer-away table](docs/STACK-SELECTION.md#how-to-derive-the-recommendation) (workload · ecosystem · team · deploy · data/ML · compliance).

**Cite fit, not familiarity (a required step).** When an agent recommends a stack it must state the fit recommendation and record the fit reason in ADR-000 (`## Fit rationale`) — enforced by `conformance/stack-decision-integrity.sh`. Stack profiles carry **no maturity tier** (all ten are copy-and-adapt references held to one conformance bar), so there is no maturity ranking to disclose here — unlike the harness and deploy axes, one axis over.

**Choosing a deploy target?** Derive from fit, not familiarity — [docs/adoption/DEPLOYMENT-ENVIRONMENT.md](docs/adoption/DEPLOYMENT-ENVIRONMENT.md) (topology cards + rubric); record fit + maturity in RUNBOOK §4 (linted by `conformance/deploy-decision-integrity.sh`). The same neutrality pattern as the stack choice, one axis over.

Then set up your **stack profile**, two ways:

**A — Use a ready profile.** If `profiles/` has your stack (e.g. `typescript-node.md`), select it. Done.

**B — Generate a custom profile (any stack).** If your stack isn't there — Elixir, Scala, Swift, anything not already shipped. Fastest start: `sh scripts/new-profile.sh <stack>` scaffolds the profile + a conformance-passing stub `ci.yml`, then:
1. Copy `profiles/_TEMPLATE.md` → `profiles/<your-stack>.md`.
2. Fill **every** section. Each maps to a universal standard (§ pointers in `DEVELOPMENT-STANDARDS.md`) — you're expressing the standard in your stack, not inventing it. An agent can author this from the team's answers about toolchain, libraries, and commands.
3. Keep every universal requirement intact; describe *how* your stack meets it.

> The selector is a convenience; generation is first-class. The kit is never limited to pre-written stacks.

**Record the decision as `docs/architecture/ADR-000-stack.md`** (see `docs/ADR-000-EXAMPLE.md`). Your chosen profile + the universal standards = your project's effective quality bar.

## 3. Repo & environment
- The repo is already initialized — `incept.sh` runs `git init` for you (and installs the runtime guard into `.git/hooks/`) when you're not already inside one; if you ran incept inside an existing repo, it left it untouched. Now protect `main` (no direct pushes, PR + green CI to merge).
- Add `.gitignore`, `.env.example` (placeholders only), and a reproducible local env (Docker / devcontainer) per your profile.
- Wire secrets management (env vars; never commit real secrets).

## 4. Tooling & CI/CD baseline
Stand up formatter, linter, type-checker, test runner, and a CI pipeline with quality gates — using the **standard commands** and **pipeline** from your profile (§3–4). **Get a green pipeline on the empty project before any feature work.**

Choosing a deploy target? Map it to the contract first — see `docs/adoption/DEPLOYMENT-ENVIRONMENT.md` (the kit owns the questions, you bring the platform).

## 5. Instantiate project artifacts
- `CLAUDE.md` — from `templates/PROJECT-CLAUDE-TEMPLATE.md`; fill identity, stack (link ADR-000 + your profile), per-project config (step 6), roles (step 7).
- `RUNBOOK.md` — setup/deploy/troubleshoot/rollback (start it now; grow it at each release).
- Backlog — `BACKLOG.md` from `templates/BACKLOG-TEMPLATE.md`, or your chosen backend (GitHub Issues/Projects, Linear, Jira).
- Seed the roadmap with the charter's first phase.

## 6. Per-project configuration (declare in the project `CLAUDE.md`)
- **Backlog backend** (`DEVELOPMENT-PROCESS.md` §6)
- **Autonomy-tier defaults** for agents (§13) — start conservative
- **SLO / error-budget posture** (§9) — soft to start
- **Cost/spend posture** (§9)
- **Review routing / ownership** (§12) — remember: an agent never reviews-and-merges its own work
- **WIP limits** and **environments** (local → staging? → prod)
- **Business continuity** *(data-handling projects)* — run a BIA (`templates/BIA-TEMPLATE.md` → `docs/continuity/BIA.md`); set per-tier RTO/RPO in RUNBOOK §6; schedule the restore drill (`docs/continuity/backup-restore-drill.md`). Not required for stateless tools.

## 7. Assign roles
Fill each function in `DEVELOPMENT-PROCESS.md` §2 — intent owner, lead/integrator, builder(s), reviewer(s), on-call, security owner — with a human or agent. One may hold several; enforce: builder ≠ sole reviewer; humans ratify governance/standards changes.

---

## Solo / lite track

**Solo or team? Decide at Inception** (`incept.sh` surfaces it) — default solo; flip to team by setting `enforce_admins:true` (below).

Working alone? The kit assumes multiple people in places (builder ≠ sole reviewer, CODEOWNERS, ratification RBAC). Here is the sanctioned solo path:

- **builder ≠ reviewer, solo.** Open a PR, let CI gate it, then **merge your own PR via owner admin-merge** (`gh pr merge --admin`). At solo scale set **`enforce_admins: false`** in your branch protection so the admin-merge is permitted — GitHub records the bypass, and that log *is* your audit trail of "solo maintainer self-ratified." When a second engineer joins, flip `enforce_admins` back to **`true`**: the required-review rule then enforces real review (you can no longer self-merge), with no other reconfiguration.
- **Control-plane PRs show a GREEN `control-plane-ratification` check carrying a notice that reads *"awaiting a non-author approval"*, and that is normal — the merge is still blocked.** A PR touching the control plane (the guard, CI, `conformance/`, `adapters/`, the named `scripts/`, or the governing docs) cannot merge until a non-author approval lands; **what blocks it is your branch protection's "Require approvals ≥ 1"**, which is server-side, not this check's colour. The check *explains* the state instead of duplicating the block: waiting is green-with-a-notice, and it turns red only when something is actually wrong — an approval is present and the gate still does not ratify (the approver is the author, the review list was unreadable, the change-class fail-safed), or the gate could not evaluate the diff. ⚠️ **If you set `required_approving_review_count` to 0, this check goes green on an unratified control-plane PR and nothing stops the merge** — ship the review requirement and this gate together, never one alone. (History, in case you inherit an older copy: the waiting state was a *yellow* posted check-run until 2026-08-27 — deleted because branch protection stopped matching API-posted runs — then briefly RED, until 2026-08-28 made it green-with-a-notice.) Solo, that's expected — your logged admin-merge above **is** the ratification. Declare `control-plane-ratification` in `REQUIRED-CHECKS.md` and run `sh scripts/branch-protection-apply.sh --apply` to require it (the additive endpoint that script wraps; see `profiles/<stack>/BRANCH-PROTECTION.md`).
- **Deferrable gates at solo / Stage-1 scale.** Coverage, dependency-scan, SBOM, provenance, and a11y can ride the waiver ramp ([templates/WAIVER-REGISTER.md](templates/WAIVER-REGISTER.md)) while you grow; **`secret-scan` and `branch-protection` stay non-negotiable.** You begin at **Stage 1** of the maturity model ([docs/enterprise/ORG-ROLLOUT.md](docs/enterprise/ORG-ROLLOUT.md)).
- Everything else in this guide applies unchanged.

---

## ✅ Inception Done — gate to enter the loop
- [ ] Charter written, intent owner named
- [ ] Stack chosen; profile selected or generated; **ADR-000 recorded**
- [ ] Repo created, `main` protected **and the four contexts `incept` declared in `REQUIRED-CHECKS.md` bound** (`sh scripts/branch-protection-apply.sh --apply` after the first CI run — `inception-done` names any still unbound), env reproducible, secrets wired
- [ ] CI pipeline green on the empty project
- [ ] Project `CLAUDE.md`, `RUNBOOK.md`, backlog, seed roadmap created
- [ ] Per-project config declared
- [ ] Roles assigned
- [ ] *(data-handling projects)* BIA done — written from `templates/BIA-TEMPLATE.md` to `docs/continuity/BIA.md` (a file you create; it does not ship); per-tier RTO/RPO set; restore drill scheduled

**All checked?** Delete this file (or keep for reference), and enter the loop at **Discover** (`DEVELOPMENT-PROCESS.md` §4). Welcome aboard.
