# START HERE — Incepting a New Project

You've dropped Sparkwright into a new project. This guide walks you (human or agent) through **Inception (Phase 0)** — the one-time gate that turns an empty repo into a project ready to run the loop. Full detail: `DEVELOPMENT-PROCESS.md` §3.

Work top to bottom. Don't enter the development loop until the first list of the **Inception Done** checklist at the end (*Before your first slice*) is checked. (One exception to the branch-protection box: on a free private GitHub repository, whose plan cannot enforce protection, a ratified `branch-protection-plan` row in `WAIVER-REGISTER.md` lets you enter with the gap recorded; see §3.)

Leaders / evaluators: read [docs/enterprise/EXEC-BRIEF.md](docs/enterprise/EXEC-BRIEF.md) first (what / why / risk / ROI); engineers continue to Inception below.

**Before anything:** run `sh scripts/preflight.sh` (add `--stack <yours>` once you've chosen) — it checks prerequisites (jq, git, your toolchain) and prints install hints. Run it in your project's root: on the kit checkout it says so and gives no all-clear, and in any other directory it refuses. New to the terms here? See [GLOSSARY.md](GLOSSARY.md). If you are the person approving the work, read one page: [the operator card](docs/onboarding/operator-card.md).

> **Start your agent session in the project root: not a parent folder, not a subfolder.** Run `cd <your-project> && claude` (or open your harness on that folder). Claude Code loads `.claude/settings.json`, and with it the guard, only from the directory the session starts in. `/add-dir` does not load it, and after `/cd` the kit's hook blocks every call, by design: relaunch in the root instead. **Check once per session:** `/hooks` lists a `PreToolUse` hook running `.claude/hooks/guard.sh`, and `/status` shows `Project settings` on its `Setting sources` line. **Also at every session start, and after any resume or `/remote-control`:** run plain `sh scripts/preflight.sh`. If you launched with a redirected environment (`CLAUDE_CONFIG_DIR`, `GH_CONFIG_DIR` or `GIT_CONFIG_GLOBAL`), incept printed the exact relaunch line, and preflight names any of those variables the session has lost.

> **What the guard does not stop.** The command guard stops honest mistakes. It does **not** stop a prompt-injected agent that reads a secret through an interpreter (`python -c`, `node -e`) or sends data out.
>
> **What does.** The OS sandbox's read-deny on secret paths and its egress allowlist, on by default: the `sandbox` block in the shipped `.claude/settings.json`. Egress also needs one day-one step at user level, done by a person: merge `{"sandbox":{"network":{"strictAllowlist":true,"allowedDomains":[]}}}` into `~/.claude/settings.json` (once per machine; it applies to every project on it), then add the hosts you use to `sandbox.network.allowedDomains`, adding to any list you already have, never replacing it; preflight lists the hosts this repo names, for you to review first, because they come from the repo and the list is machine-wide. Until it is done, preflight, run from a terminal, says `FAIL egress: NOT ENFORCED and UNDECLARED [static]`. If preflight says `FAIL boundary: OFF and UNDECLARED`, or `WARN boundary: OFF [static] (opted out <date>, ...)` when the opt-out is declared, you do not have these controls. Check: `sh scripts/sparkwright doctor --boundary` reads the settings across every scope and writes nothing; it is a static read, not a proof of what the shell can do, and the live probe follows in a later release.
>
> **What stays open**, and is not contained: until the user-level step is done, egress to an unlisted host rests on a prompt, OPEN in any permission mode that approves prompts without a person (auto, bypass); a forge comment or gist made with the agent's own credential; an attacker-supplied token sent to an allowed host; the session environment (`env` and `printenv` read credentials no path deny covers); MCP and browser tools, which run outside the sandbox (account-level connectors included: disable every connector the work does not need); deferred execution (a poisoned cache or hook that runs later). Contract and per-harness status: [`docs/operations/agent-boundary-contract.md`](docs/operations/agent-boundary-contract.md).

**How the kit gets into your project — do not clone this repository as your project.** From a kit checkout (a release of the public mirror, or this tree), run `sh scripts/sparkwright new <your-project-dir>`, which does the rest of this paragraph for you; or by hand, `sh scripts/adopter-export.sh <your-project-dir>`: it writes the adopter-shaped tree (the kit's own test matrix and dogfood board stay behind), and `incept` runs *inside that export*. Run `preflight` there too — run from the kit's own directory it reports on the kit, not on you. Full bootstrap order: `docs/adoption/inception-bootstrap.md`.

---

## You do not need to read all of this

**If you are the person approving the work, read one page: [the operator card](docs/onboarding/operator-card.md)**
(what you approve, what you type, what the red messages mean). The four core documents below are the agent's reading.

Sparkwright ships a lot of files because it covers the whole lifecycle — but **the agent reads four documents
in its first sitting** — this one, the principles (`CLAUDE.md`), the process (`DEVELOPMENT-PROCESS.md`),
and a skim of the standards (`DEVELOPMENT-STANDARDS.md`) — and pull everything else when a trigger
fires. Per-task reading is small and just-in-time (`AGENTS.md` is short, read when an agent acts). Here
is the whole map at a glance.

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
| You take a kit update (`sh scripts/kit-update.sh --from <source>`) | `docs/operations/kit-update.md`; after the update PR merges and is pulled, the agent runs `sh scripts/kit-update.sh --advance-base --from <same source>` to record what you took in `kit-base` and publish it (the next update refuses until it does; a partly taken release stays PARTIAL and is finished by advancing again), then see `docs/operations/kit-base.md` |
| You need an artifact (spec, RUNBOOK, threat model, review record) | `templates/` — pull the one you need |

The conditional **gates** already work this way — each activates only when its trigger applies. The
docs are discovered the same way. Nothing here is optional-to-*skip*; it is optional-to-*read-now*.

---

## New to enterprise SDLC?

**Coding is the task. Software engineering is everything that has to go *around* the code for an
enterprise** — tests, environments, security, governance, observability, release safety. Vibe coding
gets you working code; it does not get you software an enterprise can trust, operate, and not be
harmed by. **This kit is that "everything around it."** This section places you by *experience*; the
next one places you by *role*. Reading this first saves you rework later.

Pick the lane that sounds like you. Non-punitive — feels too basic? Jump up a lane.

- **Novice / Coding-first** — *"I can make code work (often with AI), but tests, environments,
  security, and governance are new to me."* → skim the pillars below, then take the Inception steps.
- **Adjacent** — *"I've worked in or around software delivery (product, PM, BA) — I know these
  practices exist but haven't done them myself."* → the pillars below (skip what you know), then Inception.
- **Practitioner** — *"I've shipped enterprise software; route me to the contract."* →
  the principles (`CLAUDE.md`), then straight to §0 Orient. Skip the pillars.
  *Senior / principal / architect:* your home is the architecture lens at the §7 review gate (ADRs,
  15-factor), the autonomy-tier model (`DEVELOPMENT-PROCESS.md` §13), and the enterprise layer
  ([docs/enterprise/](docs/enterprise/)) — `MAINTAINING.md` for the kit's convention and versions.

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
> of what you read — on a brownfield adoption the aggregate CI step is merged into your existing
> pipeline by hand, and reads N/A until it is (`docs/adoption/brownfield.md` §1). This section makes
> you *educated*; the guardrails *reduce* risk — they don't remove it.

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
| **Engineer / Lead — new project** | **from a kit checkout, run `sh scripts/sparkwright new <your-project-dir>`** (five questions, then export, toolchain check, incept and preflight in one command; it ends with the list of what is still owed, also written into the project's `CLAUDE.md`), then work the judgment steps below. The hand route is still `sh scripts/incept.sh` inside an export (it `git init`s the repo for you if you're not already in one, then installs the runtime guard) | full Inception (steps 1–7); `new` asks for `--harness <list>` too (default `claude-code`; pick `generic` for any AGENTS.md-reading harness; comma-separate for several — see `docs/operations/harness-adapters.md`) |
| **Engineer — existing repo (brownfield)** | **`docs/adoption/brownfield.md`** (copy-in + `.claude/` merge + guard verify) | then the Inception judgment steps below; if your environment carries a foreign process-skill library (e.g. superpowers), see **`docs/adoption/skill-rosters.md`** |

> **Non-builders: the rigor is carried, not waived.** You don't hand-craft tests or 15-factor config.
> When your intent becomes code, the agent builds it test-first and the CI gates enforce 15-factor,
> observability, and security on **every** PR — regardless of who filed it. Your own artifact has its
> own bar (testable acceptance criteria, an a11y sign-off); the code that realizes it gets the full
> standard. Routing by role changes *which doc you open*, never *which gate applies*.

(Note: `incept` renames the kit's principles `CLAUDE.md` to `ENGINEERING-PRINCIPLES.md` and stamps a new project `CLAUDE.md` — your project guide. The glossary and START-HERE references to the *principles* file mean `ENGINEERING-PRINCIPLES.md` after Inception.)

> **Bootstrap order:** run `sparkwright new <your-project-dir>` *first* (it wraps export, toolchain check, `incept` and preflight) — never commit before it. If you take the hand route, run `incept` first instead. See the incept-first sequence in [`docs/adoption/inception-bootstrap.md`](docs/adoption/inception-bootstrap.md) (summarized at `DEVELOPMENT-PROCESS.md` §3).

---

## 0. Orient
The person approving the work reads [the operator card](docs/onboarding/operator-card.md); the four documents below are the agent's reading. Read, in order: this file → `CLAUDE.md` (principles + Definition of Done) → `DEVELOPMENT-PROCESS.md` (the loop) → skim `DEVELOPMENT-STANDARDS.md` (the universal bar — deep-dive only on a specific quality bar, per the front-door map above). Don't read profiles yet — you pick one below (it's in your "first 5" *set*, opened here at step 2). **This is not a quick step, and no honest minute-count fits it:** read end to end those four documents run to well over a thousand lines. The honest way through is the front-door map above — read this file and `CLAUDE.md` properly, then let the map tell you which section of the other two your current task actually needs. Orienting is something you finish over your first few slices, not before them.

## 1. Charter
Write the project charter (into the project `CLAUDE.md`, through the one draft described below):
- **Problem & users** — what, for whom, current pain.
- **Vision & success metrics** — what success looks like, measurably.
- **Scope boundaries** — explicitly in / out.
- **Intent owner** — who owns the *why* and accepts increments.

**Who writes it.** The guard refuses the agent's own write to `CLAUDE.md` (Edit, Write or a shell write); later edits go through a dev clone and a PR. So the agent writes **one draft**, `docs/inception-draft/PROJECT-CLAUDE.md`, from your words: the charter (§1), the per-project config (§3: autonomy tiers, SLO, review routing, WIP, cost posture, operator fluency; steps 5 and 6 below) and the roles (§4; step 7). You paste what is right into `CLAUDE.md` in your own editor and delete `docs/inception-draft/`; that paste is the act that ratifies them. `conformance/inception-done.sh` fails while the directory exists or a ratified file still carries a draft banner. The draft's rules are in `skills/inception-from-code/SKILL.md` (§Greenfield).

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
- **Identities, before the first push: you plus one agent account.** The agent works under its own limited account on your forge and on your tracker, never your credentials (`docs/operations/separation-of-duties.md` §The minimum identity model). One agent account serves the whole team. Forge: create it and invite it with push only (`docs/operations/forge-identity-switch.md`, the day-one subset: four human acts). Tracker: the act sheet in your setup file. With its own forge account the agent is not the approving identity, so you are on **team**, the merge relationship's default; see §Solo or team below. That holds as a boundary only once no owner login is reachable from agent sessions (`forge-identity-switch.md` steps 0, 2 and 5 close those paths, and step 7 proves it). Until then the agent could approve as you, and team is a convention. Treat the identity as a lock only after those steps are done **and** `main` is protected (below, `--replace`): until protection is bound, a push-only collaborator can still push to and merge into `main`. Bind protection before agent sessions start using the machine user.
- The repo is already initialized — `incept.sh` runs `git init` for you (and installs the runtime guard into `.git/hooks/`) when you're not already inside one; if you ran incept inside an existing repo, it left it untouched. Now protect `main` (no direct pushes, PR + green CI to merge).
- **The first push.** A person creates the empty remote and adds it as `origin` (the agent's sandbox refuses `git remote add`). The agent commits the incepted baseline after your paste (step 1; the Inception exception covers a baseline that is mostly control-plane), then pushes it to `main` **once** with `git push origin main` and reads it back with `git ls-remote --heads origin main`. `-u` is not needed: the guard admits the push with or without it, and the shipped sandbox cannot write `.git/config`, so `-u` fails there. The guard's pre-push hook admits a push that creates `main` on a remote that has none, and only that; every later direct push to `main` is refused, so every later change goes through a branch and a PR. Create the GitHub repo **empty** (no README, licence or .gitignore): a repo initialised on GitHub already has a `main`, so the first push would be an update and would be refused. Protection cannot be bound before this push exists. Until it does, `sh scripts/sparkwright start <ROW>` on the BACKLOG.md backend claims the first card in your repository only; after the first push run `sh scripts/board.sh publish` once, to hand that claim to origin (the next claim or release does it too). On a tracker backend, the filled `.kit/tracker.conf` rides this push (`JIRA-SETUP.md` act-sheet rows 4-6); a team adopter loses a second reviewer on that first conf, since the bootstrap push has no PR.
  **The push needs `gh`'s `workflow` scope.** The baseline carries `.github/workflows/*`, and `gh auth login`'s default scopes do not include `workflow`, so with `gh` as git's credential helper the push is rejected with ``refusing to allow an OAuth App to create or update workflow `.github/workflows/<file>` without `workflow` scope``. Add the scope once, then push again: `gh auth refresh -h github.com -s workflow` (unset `GH_TOKEN`/`GITHUB_TOKEN` first; `gh auth refresh` refuses while either is set) (check with `gh auth status`, whose `Token scopes` line then lists `workflow`). Every later PR that edits a workflow file needs it too; a machine user's token gets it at issue (`docs/operations/forge-identity-switch.md`, step 1).
- **Protecting a new repo is `--replace`, not `--apply`.** On a `main` that has no protection yet, `sh scripts/branch-protection-apply.sh --apply` exits 2 (UNVERIFIED, not protected yet) and names `--replace`; a person runs it **in a real terminal** with an admin credential (it asks a human to type one confirmation, REPLACE, and refuses to run from an agent's shell; `docs/operations/forge-identity-switch.md` step 5, where a fine-grained token needs Administration: read and write on the repository). **Solo:** `sh scripts/branch-protection-apply.sh --replace`. **Team:** `sh scripts/branch-protection-apply.sh --replace --team`; without `--team` a team repository gets the solo profile (the run prints a WARN when the forge reads team). Every refusal or stop before the write ends with `No change was made.`; a usage or argument error prints its own error instead, and writes nothing. It needs no prior CI run: it PUTs the check names declared in `REQUIRED-CHECKS.md` (GitHub's settings page lists only names it has already seen, a UI convenience, not a prerequisite). `--apply` is the additive form for a `main` that is already protected.
  **On a private repository on GitHub Free, `--replace` is refused** (HTTP 403, "… or make this repository public to enable this feature"). On a private repository the build and image attestation steps also skip unless you declare GitHub Enterprise Cloud (attestations on a private repository need it, whoever owns the repository; each skip prints a notice naming the cause, and on an organization-owned repository the image push still runs; on a user-owned private repository the image job does not run at all). Your routes:
  - make the repository public;
  - move to a paid plan, and, if you have GitHub Enterprise Cloud, declare it by setting the `KIT_ATTEST_PRIVATE` variable to `true` (a repository variable, or an organization variable that covers the repository; Settings → Secrets and variables → Actions → Variables). `inception-done` reads it; without it the attest steps stay skipped;
  - or work at the convention tier that `sh scripts/sparkwright doctor` reports (its `--quick` form prints the `branch protection:` line in 3 s [measured on a cold adoption of v3.247.0, 2026-11-15 UTC, n = 1, on a markdown-board project with no tracker reads], plus up to about 20 s when it reads a tracker (a timeout limit, not a measurement); see [`docs/adoption/vc-hosts.md` §Solo or team](docs/adoption/vc-hosts.md#solo-or-team--pick-the-merge-relationship-declared-in-your-repo-the-default-is-team)). There, record the gap in a `branch-protection-plan` row of the `WAIVER-REGISTER.md` at the repository root (`./WAIVER-REGISTER.md`; the gate does not read the `docs/governance/` copy that `incept --mode enterprise` stamps). `incept` creates that root file from `templates/WAIVER-REGISTER.md` on every backend (on a non-md backend it also stamps the `board-governance` row). A person writes or fills the row; the agent may propose its text and may commit the file once the person has written it, and the guard refuses the agent's own write to it. With a ratified, unexpired row, strict `inception-done` reads `WAIVED: branch protection — NOT ENFORCED`, naming the owner, the expiry and the exit, and the gap is still printed on every run. It waives only this plan limit: any other branch-protection failure stays FAIL. A row proves a name and a date were written, not that a second person agreed; it lasts at most 90 days, and the date binds whenever someone re-runs `inception-done`. For the private-repository provenance gap, record the exemption in `conformance/gate-dispositions.txt`, a file you author (the kit's own copy is not shipped to adopters). It must list all eight gate ids once each, as `gate-<id><TAB>apply|na<TAB><reason>`: `apply` for the other seven and `na` for `gate-provenance`, with today's date in the reason. A file with fewer than all eight is invalid and reds `ci-gates.sh --own-tree`. Format: `docs/operations/ci-platforms.md`, section "Per-gate dispositions".
- **Tracker backends (Jira):** work through the day-one act sheet at the top of `JIRA-SETUP.md` before the first PR. **Minimum day one** is the act sheet's rows 5, 6, 9 (Free variant), 10, 12 and 15, or row 16 where row 15 cannot bind (a free-plan private repository), plus row 1 only if the site blocks API tokens: six rows and two account acts (create the agent's account; mint its token), on a Free plan with two accounts. On Free the agent account may also be the CI reader, as a writer (`JIRA-SETUP.md` §5a; the ceiling variables of row 13 matter only to a live probe): that saves a seat, it does not reduce exposure, and its three residuals are stated in `JIRA-SETUP.md` §5a. The stricter posture (rows 2, 7, 8 and 11: a separate Viewer-only reader, three accounts) needs Standard. Row 3 is optional and row 4 is the agent's draft; row 13 is optional (needed only if CI cannot reach the site: `KIT_TRACKER_RUNNER`, `JIRA-SETUP.md` §0); rows 14 and 16 are conditional and row 17 is optional. No second account? The agent has no board credential and board writes stay yours; never store your own admin token for it. Your own token as the CI reader is below the minimum and not recommended; an admin's own token stays forbidden (`JIRA-SETUP.md`, "No second account?"). Create the agent account instead. A site that rejects the extended permission keys reads `unverified` and fails. Store the trusted reader's `KIT_TRACKER_USER` / `KIT_TRACKER_TOKEN` as repository Actions secrets (`JIRA-SETUP.md` §5a); without them the `tracker-board-gates` required check cannot run. A token you export, on any OS (and always on Linux or in a devcontainer, which have no Keychain), sits in the session environment, and a session can read it with `env` (`JIRA-SETUP.md` §5b).
- Add `.gitignore`, `.env.example` (placeholders only), and a reproducible local env (Docker / devcontainer) per your profile.
- Wire secrets management (env vars; never commit real secrets).

## 4. Tooling & CI/CD baseline
Stand up formatter, linter, type-checker, test runner, and a CI pipeline with quality gates — using the **standard commands** and **pipeline** from your profile (§3–4). **Get a green pipeline on the empty project before any feature work.** How long that run takes depends on whether the kit's own selftests run (the kit's conformance aggregate, `verify.sh --require`). One app PR's whole run took 3 min 22 s [measured on a cold adoption of v3.247.0, 2026-11-15 UTC, n = 1]; on a run that includes them, the kit's selftests take most of the time. The table says when they run. Each figure is measured on a cold adoption of v3.247.0, 2026-11-15 UTC, on a TypeScript project and GitHub's `ubuntu-24.04` runner, n = 1 (one run each, as of v3.247.0; a stale figure shows its age).

| Event | The kit's selftests |
|---|---|
| the first push to the default branch | skipped (no changed-path listing): 5 min 0 s [measured on a cold adoption of v3.247.0, 2026-11-15 UTC, n = 1] |
| a later push, or a PR, into the default branch, touching a kit file | run in full: one control-plane PR took 69 min 24 s [measured on a cold adoption of v3.247.0, 2026-11-15 UTC, n = 1] |
| a later push, or a PR, into the default branch, touching no kit file | skipped (they render N-A, with a `kit selftests not re-run:` notice in the job summary): one app PR took 3 min 22 s [measured on a cold adoption of v3.247.0, 2026-11-15 UTC, n = 1] |
| a PR into another branch | skipped (no listing) |
| a push to another branch | no CI run at all (`push: branches: [main]` in every profile) |
| the weekly scheduled run | skipped (no listing) |
| the listing cannot be built: a bad sha, a failed or empty diff, a path with a newline in it, or the classifier failing | run in full (fail-safe) |

A **kit file** is any control-plane path (the governing docs such as `START-HERE.md` included), anything under `.kit/`, a `.gitattributes` or a `.shellcheckrc`. The GitLab pipeline builds no changed-file list and passes no skip flag, so every GitLab run is full; that job has never been run on GitLab. The trade: a push is compared with the push before it, so a kit change whose own run did not pass (red, cancelled, skipped, or never ran, e.g. a push made with GITHUB_TOKEN) stays ungraded until the next PR or push into the default branch that touches a kit file, or a run whose listing is refused. The weekly run does not grade it, because the weekly run skips the selftests. Re-measuring these figures is conduct, not enforced.

Choosing a deploy target? Map it to the contract first — see `docs/adoption/DEPLOYMENT-ENVIRONMENT.md` (the kit owns the questions, you bring the platform).

## 5. Instantiate project artifacts
- `CLAUDE.md` — from `templates/PROJECT-CLAUDE-TEMPLATE.md`; fill identity, stack (link ADR-000 + your profile), per-project config (step 6), roles (step 7). The agent drafts the charter, config and roles in `docs/inception-draft/PROJECT-CLAUDE.md` (step 1); a person pastes them in.
- `RUNBOOK.md` — setup/deploy/troubleshoot/rollback (start it now; grow it at each release).
- Backlog — `BACKLOG.md` from `templates/BACKLOG-TEMPLATE.md`, or your chosen backend (GitHub Issues/Projects, Linear, Jira).
- Seed the roadmap with the charter's first phase.

## 6. Per-project configuration (declare in the project `CLAUDE.md`)
The agent drafts these in `docs/inception-draft/PROJECT-CLAUDE.md` (§3) from your words, and a person pastes them into `CLAUDE.md` (step 1). `incept` has already stamped the backlog backend.
- **Backlog backend** (`DEVELOPMENT-PROCESS.md` §6)
- **Autonomy-tier defaults** for agents (§13) — start conservative
- **SLO / error-budget posture** (§9) — soft to start
- **Cost/spend posture** (§9)
- **Review routing / ownership** (§12) — remember: an agent never reviews-and-merges its own work
- **WIP limits** and **environments** (local → staging? → prod)
- **Business continuity** *(data-handling projects)* — run a BIA (`templates/BIA-TEMPLATE.md` → `docs/continuity/BIA.md`); set per-tier RTO/RPO in RUNBOOK §6; schedule the restore drill (`docs/continuity/backup-restore-drill.md`). Not required for stateless tools.

## 7. Assign roles
The agent drafts the roles in the same `docs/inception-draft/PROJECT-CLAUDE.md` (§4); a person pastes them into `CLAUDE.md` (step 1). Fill each function in `DEVELOPMENT-PROCESS.md` §2 — intent owner, lead/integrator, builder(s), reviewer(s), on-call, security owner — with a human or agent. One may hold several; enforce: builder ≠ sole reviewer; humans ratify governance/standards changes.

| Seat role | When it runs | Neutral definition | Claude Code binding |
|---|---|---|---|
| `conductor` | the session itself: slices, dispatches, integrates; prefers a builder seat, and if it builds, the Builder line says `conductor` | `agents/orchestrator.agent.md` | the main session (the `orchestrator` subagent is only the optional fan-out hat) |
| `builder` | once per plan task, fresh each time | `agents/engineer.agent.md` | `engineer` |
| `reviewer` | each task diff and the whole branch, before push | `agents/reviewer.agent.md` | `reviewer` |
| `security` | on the built diff; separate from the reviewer on Sensitive or Control-plane | `agents/security.agent.md` | `security-reviewer` |

Where the harness has a native binding for a seat, dispatch that binding. A general-purpose seat never does a builder, reviewer or security job. Only on a harness with no native subagents (the `generic` adapter) is a seat a fresh session given its definition file as the brief. The record and the check are the same either way: `review-lane` grades that the record names these roles, and cannot see that a seat ran.

## 8. Map your seats to models
Each seat (conductor, builder, reviewer, security, design, explorer) runs on the model your project judges most appropriate for what that seat does; design and explorer are model-map seats only, with no `Seat role:` line in step 7. The kit names the seats and what they need; **you** name the models, in one file, and record why. `incept` stamps `.kit/model-map.conf` with every value `unset`.
- **One model for everything?** Leave it `unset`. Every seat runs whatever model your harness is on, the tiers stay advisory, and nothing goes red.
- **Different models per seat?** Set each tier in `.kit/model-map.conf` to whatever your harness's spawn takes as its model parameter (an alias or an id; the kit never interprets it). Then (1) write `#### Model fit rationale` in your project `CLAUDE.md`, citing a real fit dimension (reasoning, long context, tool use, cost, latency, availability, a measured A/B), because the decision-integrity check reads it; (2) record a `docs/governance/DECISIONS.md` entry with the evidence and a revisit trigger (a new model release, a traced quality drop, or a date); (3) set `decision=`, `recorded=` and `revisit-by=` in the map. `conformance/model-tiering.sh` checks the `decision=` resolves and that no kit-shipped file names a model.
- **Changing it later** needs a measured A/B on real slices and a new entry that names the one it replaces. Detail: [`docs/adoption/model-tier-binding.md`](docs/adoption/model-tier-binding.md).

---

## Solo or team — decide at Inception

Two merge relationships; choose at Inception. **Team** (the default) is the minimum identity model: the agent has its own forge account, you approve its PRs, and it merges on your recorded GO. **Solo** is for a repository where the agent works under your one forge account: it merges on your recorded GO alone, and a **GO that is self-asserted by name**. Once `branch-protection-apply.sh --replace` has run on a solo-declared repository, the required check `solo-go-bound` makes the forge refuse a head with no recorded GO (the GO is self-asserted, and a note the agent records satisfies it; an admin can still edit protection); before that there is no server-side wall. Leaving solo is one act: run `branch-protection-apply.sh --replace --team` in the same step that changes the declaration. Your own act on the first, declaring PR is the one merge by hand, and from then on the agent merges on your recorded GO: its verbs print that, and your per-PR act is the GO only. What each needs (accounts, forge plan), what each guarantees and what solo gives up: [`docs/adoption/vc-hosts.md` §Solo or team](docs/adoption/vc-hosts.md#solo-or-team--pick-the-merge-relationship-declared-in-your-repo-the-default-is-team). **On a private repository on a free GitHub plan, branch protection cannot be enforced, solo or team** (it needs Pro, Team or Enterprise, or a public repository; for team, `enforce_admins` returns 404, `docs/operations/review-lane.md` caveat). There the merge rules are a convention the kit records and checks after the fact, not a server-side wall. `incept` asks how many forge accounts the work runs under (1 = solo, 2 or more = team); pressing Enter takes **team**, while a `--noninteractive` run without `--team` or `INCEPT_TEAM` still stamps `solo`. That stamp is the **branch-protection** posture. The merge relationship defaults to team, and agent merges in solo need an explicit `MERGE_RELATIONSHIP=solo`.

Flip the branch-protection posture to team with one verb, `sh scripts/branch-protection-apply.sh --replace --team` (below). **Read its confirmation first:** with `enforce_admins:true` you can no longer merge a PR you authored yourself without a second approver. PRs the agent's own account authors, which you approve, are unaffected. It writes `enforce_admins:true` **and** code-owner review together, and pins the repo to squash-only merges. The flip is proven by the verifier's output, not by a UI click: `sh conformance/branch-protection.sh` prints a `settings:` line that must read `enforce_admins=true code_owner_reviews=true … merge_methods=squash-only`, and a tree whose `CLAUDE.md` carries `**Governance** (§ solo/team): team` turns RED until it does.

Working alone? The kit assumes multiple people in places (builder ≠ sole reviewer, CODEOWNERS, ratification RBAC). Here is the sanctioned solo path (a repository that has not declared `MERGE_RELATIONSHIP=solo` yet; once it has, the agent merges on your recorded GO and this admin-merge is not asked of you again):

- **builder ≠ reviewer, one account, undeclared.** Open a PR, let CI gate it, then **merge your own PR via owner admin-merge** (`gh pr merge --admin`). At solo scale set **`enforce_admins: false`** in your branch protection so the admin-merge is permitted — GitHub records the bypass, and that log *is* your audit trail of "solo maintainer self-ratified." When a second engineer joins, run **`sh scripts/branch-protection-apply.sh --replace --team`** (an admin act, typed at a real terminal): it sets `enforce_admins` to **`true`** together with code-owner review, so the required-review rule then enforces real review (you can no longer self-merge). Invite the second person *first* — the verb WARNs when no second write collaborator exists or a CODEOWNERS login is only an unaccepted invitation, because that is the lock-out. Do not flip `enforce_admins` by hand in the UI: the verifier reds a team declaration until the settings line proves all of it.
- **Control-plane PRs show a GREEN `control-plane-ratification` check carrying a notice that reads *"awaiting a non-author approval"*, and that is normal — the merge is still blocked.** A PR touching the control plane (the guard, CI, `conformance/`, `adapters/`, the named `scripts/`, or the governing docs) cannot merge until a non-author approval lands; **what blocks it is your branch protection's "Require approvals ≥ 1"**, which is server-side, not this check's colour. The check *explains* the state instead of duplicating the block: waiting is green-with-a-notice, and it turns red only when something is actually wrong — an approval is present and the gate still does not ratify (the approver is the author, the review list was unreadable, the change-class fail-safed), or the gate could not evaluate the diff. ⚠️ **If you set `required_approving_review_count` to 0, this check goes green on an unratified control-plane PR and nothing stops the merge** — ship the review requirement and this gate together, never one alone. Undeclared solo, that's expected — your logged admin-merge above **is** the ratification; declared solo, the recorded GO plays that part. Declare `control-plane-ratification` in `REQUIRED-CHECKS.md` and run `sh scripts/branch-protection-apply.sh --apply` to require it on an already-protected `main` (the additive endpoint that script wraps; a brand-new repo needs `--replace` first — §3 above; see `profiles/<stack>/BRANCH-PROTECTION.md`).
- **What a control-plane PR costs you, solo.** Per PR: a design GO and a plan (the ceremony scales with class × size); one review and one security pass; one full CI run (one measured control-plane PR took 69 min 24 s; one app PR took 3 min 22 s; each n = 1, measured on a cold adoption of v3.247.0, 2026-11-15 UTC); your GO (declared solo; the declaring PR is the one you merge yourself in the forge, and an undeclared one-account repository merges each PR that way); then the agent's `sh scripts/board.sh release <ROW> --stale`, which moves the tracker card to Done (a forge-UI merge moves no card). In a declared solo repository `promotion-verify.sh land` merges on your recorded GO; undeclared, there is no second approver, so it is `record` plus your merge. Kit updates, tracker-conf edits and CI changes are all control-plane, so batch them where you can.
- **Deferrable gates at solo / Stage-1 scale.** Coverage, dependency-scan, SBOM, provenance, and a11y can ride the waiver ramp ([templates/WAIVER-REGISTER.md](templates/WAIVER-REGISTER.md)) while you grow; **`secret-scan` and `branch-protection` stay non-negotiable** (on a free private repository the plan cannot enforce protection, so the one waivable cause is `branch-protection-plan`: a ratified row lets strict Inception-Done read `WAIVED: branch protection — NOT ENFORCED`; see §3). You begin at **Stage 1** of the maturity model ([docs/enterprise/ORG-ROLLOUT.md](docs/enterprise/ORG-ROLLOUT.md)).
- Everything else in this guide applies unchanged.

---

## ✅ Inception Done — gate to enter the loop

Two lists, not one. The first is what the first slice needs; the second is what a first production deploy needs, and nothing in it blocks the first slice. Every line carries an `(id: …)` tag, and `conformance/inception-done.sh` names the same ids (a selftest cell locks the two together).

### Before your first slice — maturity Stage 1 ([`docs/enterprise/ORG-ROLLOUT.md`](docs/enterprise/ORG-ROLLOUT.md))
- [ ] Charter written, intent owner named (id: charter)
- [ ] Stack chosen; profile selected or generated; **ADR-000 recorded** (id: stack-adr)
- [ ] Repo created, baseline pushed to `main` once (`git push origin main` to an empty repo, §3), `main` protected **and the contexts `incept` declared in `REQUIRED-CHECKS.md` bound** (a person runs `sh scripts/branch-protection-apply.sh --replace`, or `--replace --team` for a team repository, in a terminal with an admin credential after the first CI run; `--apply` only adds to an existing protection — `inception-done` names any still unbound; on a free private repository the plan cannot enforce protection: record a ratified `branch-protection-plan` row in `WAIVER-REGISTER.md` and strict Inception-Done reads `WAIVED: branch protection — NOT ENFORCED`, which counts for this box; without the row, the box stays unchecked until the repository is public or on a paid plan, §3) (id: repo-protect)
- [ ] Reproducible local setup, secrets wired (tracker backends: the reader's secrets before the first PR) (id: env-secrets)
- [ ] CI pipeline green on the empty project (id: ci-green)
- [ ] Project `CLAUDE.md`, `RUNBOOK.md`, backlog, seed roadmap created (id: project-files)
- [ ] Per-project config declared in `CLAUDE.md`: backlog backend, autonomy-tier defaults, review routing, WIP limits, cost posture (id: config)
- [ ] Roles assigned: every function except on-call (id: roles)
- [ ] Identities: you plus one agent account on the forge and the tracker (or a stated reason for solo) (id: identities)

### Before your first production deploy — maturity Stage 3 to 4 ([`docs/enterprise/ORG-ROLLOUT.md`](docs/enterprise/ORG-ROLLOUT.md))
Not graded yet: `inception-done` prints one `OWED (first-deploy set)` line per item below (`owed`, `filled` or `N/A`) and the verdict does not read them. A later card makes them block the first production deploy. A `filled` line says only that the template placeholder is gone, so you still judge the content.
- [ ] SLO / error-budget posture declared in `CLAUDE.md` (id: slo)
- [ ] Deploy environments declared in `CLAUDE.md`, with the per-tier deploy trigger (id: envs)
- [ ] On-call / operator role assigned (id: oncall)
- [ ] *(data-handling projects)* BIA done — written from `templates/BIA-TEMPLATE.md` to `docs/continuity/BIA.md` (a file you create; it does not ship); per-tier RTO/RPO set; restore drill scheduled (id: bia)
- [ ] `RUNBOOK.md` §4 Deploy filled: the deploy command(s) (id: rb-deploy)
- [ ] `RUNBOOK.md` §5 Rollback filled: the rollback command (id: rb-rollback)
- [ ] *(data-handling projects)* `RUNBOOK.md` §6 Disaster recovery filled: RPO and RTO (id: rb-dr)
- [ ] `RUNBOOK.md` §8 Monitoring filled: error tracking, health check, alerts (id: rb-monitor)

**Your first gated slice (control-plane or sensitive).** After the owner's design GO, the agent records it from the main checkout (`sh scripts/promotion-verify.sh record --gate design`) and, in the dev clone, fetches the note with `git fetch origin refs/notes/promotions:refs/notes/promotions` (the plain form, never `+`) before `sh scripts/sparkwright prepush`; a clone has no GO ledger, so without that fetch its core shows one cause and CI's `ceremony-binding` is the gate. On the first push of a gated PR its board row is In Review with the branch in its `PR` cell, or Done with the branch or PR in its retro: `backlog-presence` reads exactly that. Detail: `skills/build/SKILL.md`.

**First list checked?** Delete this file (or keep for reference), and enter the loop at **Discover** (`DEVELOPMENT-PROCESS.md` §4). Welcome aboard. **All checked?** Then you are ready to deploy to production.
