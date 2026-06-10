# START HERE — Incepting a New Project

You've dropped the Agentic SDLC Kit into a new project. This guide walks you (human or agent) through **Inception (Phase 0)** — the one-time gate that turns an empty repo into a project ready to run the loop. Full detail: `DEVELOPMENT-PROCESS.md` §3.

Work top to bottom. Don't enter the development loop until the **Inception Done** checklist at the end is fully checked.

Leaders / evaluators: read [docs/enterprise/EXEC-BRIEF.md](docs/enterprise/EXEC-BRIEF.md) first (what / why / risk / ROI); engineers continue to Inception below.

**Before anything:** run `sh scripts/preflight.sh` (add `--stack <yours>` once you've chosen) — it checks prerequisites (jq, git, your toolchain) and prints install hints. New to the terms here? See [GLOSSARY.md](GLOSSARY.md).

---

## Who are you? Start here

This guide's numbered steps are the **engineer/lead Inception path**. If you're a different role, start at your row — you generally won't need the numbered engineer steps below.

| If you are… | Start with | Then |
|-------------|-----------|------|
| **Product Owner / BA / stakeholder** | skim `CLAUDE.md` for context, then `templates/FEATURE-REQUEST-TEMPLATE.md` | hand it to the team or drop it on the board (`DEVELOPMENT-PROCESS.md` §6) — no engineering setup needed |
| **Designer** | the UX & accessibility lens in Discovery (`DEVELOPMENT-PROCESS.md` §5) + the a11y items in the Definition of Done (`CLAUDE.md`) | attach assets to the spec; own the a11y sign-off at Review |
| **QA Engineer** | the testing standards (`DEVELOPMENT-STANDARDS.md` §7) + the UAT acceptance gate (`DEVELOPMENT-PROCESS.md` §9) | own acceptance |
| **DevOps / SRE** | the environment model (`DEVELOPMENT-PROCESS.md` §9) + `RUNBOOK.md` + CI (`DEVELOPMENT-STANDARDS.md` §14) | own promotion & operate |
| **Engineer / Lead — new project** | **run `sh scripts/incept.sh`**, then work the judgment steps below | full Inception (steps 1–7) |
| **Engineer — existing repo (brownfield)** | **`docs/adoption/brownfield.md`** (copy-in + `.claude/` merge + guard verify) | then the Inception judgment steps below |

(Note: `incept` renames the kit's principles `CLAUDE.md` to `ENGINEERING-PRINCIPLES.md` and stamps a new project `CLAUDE.md` — your project guide. The glossary and START-HERE references to the *principles* file mean `ENGINEERING-PRINCIPLES.md` after Inception.)

---

## 0. Orient (5 min)
Read, in order: this file → `CLAUDE.md` (principles + Definition of Done) → `DEVELOPMENT-PROCESS.md` (the loop) → skim `DEVELOPMENT-STANDARDS.md` (the universal bar). Don't read profiles yet — you pick one below.

## 1. Charter
Write the project charter (into the project `CLAUDE.md` you'll create in step 5):
- **Problem & users** — what, for whom, current pain.
- **Vision & success metrics** — what success looks like, measurably.
- **Scope boundaries** — explicitly in / out.
- **Intent owner** — who owns the *why* and accepts increments.

## 2. Choose your stack → ADR-000  ⭐ the key step
Decide the technology stack. This is a **spike** if there's genuine uncertainty — compare options, don't guess.

Then set up your **stack profile**, two ways:

**A — Use a ready profile.** If `profiles/` has your stack (e.g. `typescript-node.md`), select it. Done.

**B — Generate a custom profile (any stack).** If your stack isn't there — Elixir, Scala, Swift, anything not already shipped. Fastest start: `sh scripts/new-profile.sh <stack>` scaffolds the profile + a conformance-passing stub `ci.yml`, then:
1. Copy `profiles/_TEMPLATE.md` → `profiles/<your-stack>.md`.
2. Fill **every** section. Each maps to a universal standard (§ pointers in `DEVELOPMENT-STANDARDS.md`) — you're expressing the standard in your stack, not inventing it. An agent can author this from the team's answers about toolchain, libraries, and commands.
3. Keep every universal requirement intact; describe *how* your stack meets it.

> The selector is a convenience; generation is first-class. The kit is never limited to pre-written stacks.

**Record the decision as `docs/architecture/ADR-000-stack.md`** (see `docs/ADR-000-EXAMPLE.md`). Your chosen profile + the universal standards = your project's effective quality bar.

## 3. Repo & environment
- Initialize the repo; protect `main` (no direct pushes, PR + green CI to merge).
- Add `.gitignore`, `.env.example` (placeholders only), and a reproducible local env (Docker / devcontainer) per your profile.
- Wire secrets management (env vars; never commit real secrets).

## 4. Tooling & CI/CD baseline
Stand up formatter, linter, type-checker, test runner, and a CI pipeline with quality gates — using the **standard commands** and **pipeline** from your profile (§3–4). **Get a green pipeline on the empty project before any feature work.**

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

Working alone? The kit assumes multiple people in places (builder ≠ sole reviewer, CODEOWNERS, ratification RBAC). Here is the sanctioned solo path:

- **builder ≠ reviewer, solo.** You still open a PR and let CI gate it, then **merge your own PR via owner admin-merge.** GitHub records the admin bypass — that log *is* your audit trail of "solo maintainer self-ratified." When a second engineer joins, the required-review rule starts enforcing real review with **zero reconfiguration.**
- **Deferrable gates at solo / Stage-1 scale.** Coverage, dependency-scan, SBOM, provenance, and a11y can ride the waiver ramp ([templates/WAIVER-REGISTER.md](templates/WAIVER-REGISTER.md)) while you grow; **`secret-scan` and `branch-protection` stay non-negotiable.** You begin at **Stage 1** of the maturity model ([docs/enterprise/ORG-ROLLOUT.md](docs/enterprise/ORG-ROLLOUT.md)).
- Everything else in this guide applies unchanged.

---

## ✅ Inception Done — gate to enter the loop
- [ ] Charter written, intent owner named
- [ ] Stack chosen; profile selected or generated; **ADR-000 recorded**
- [ ] Repo created, `main` protected, env reproducible, secrets wired
- [ ] CI pipeline green on the empty project
- [ ] Project `CLAUDE.md`, `RUNBOOK.md`, backlog, seed roadmap created
- [ ] Per-project config declared
- [ ] Roles assigned
- [ ] *(data-handling projects)* BIA done (`docs/continuity/BIA.md`); per-tier RTO/RPO set; restore drill scheduled

**All checked?** Delete this file (or keep for reference), and enter the loop at **Discover** (`DEVELOPMENT-PROCESS.md` §4). Welcome aboard.
