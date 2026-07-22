# Sparkwright

*The agentic SDLC kit — guardrails that let anyone build production-grade software with AI agents, from an idea to operating software.*

`v3.172.0` · Apache-2.0 · [Releases](https://github.com/SeaBrad72/sparkwright/releases)

Sparkwright turns a new repo into a project that ships production-grade software through a **guided, agent-driven lifecycle**. You bring the idea and the decisions; the kit brings the process, the guardrails, and a working pipeline to build on. It is opinionated about *how* to build well with agents, and neutral about *what* you build with — **your stack, environment, and deploy target are chosen and built as you engage the kit, not picked for you.**

## Get started

You'll create a new project *from* the kit, then let the kit guide you through setting it up.

```sh
# 1 · Download the kit (a throwaway copy — used only to create your project)
git clone --depth 1 https://github.com/SeaBrad72/sparkwright /tmp/sparkwright

# 2 · Create your new project from it — name it whatever you like
sh /tmp/sparkwright/scripts/adopter-export.sh ./my-app

# 3 · Go into your new project
cd my-app
```

Now **open your new project in your AI coding tool** (Claude Code, or any `AGENTS.md`-aware agent) and tell it:

> *"Walk me through START-HERE."*

— or open **[`START-HERE.md`](START-HERE.md)** and follow it yourself.

From there the kit **guides you through Inception**: it helps you **choose your stack**, scaffolds a runnable starter with a **green pipeline on the first run** (so you build on working software, not an empty repo), and sets your project up. Then you enter the build loop. Your stack, environment, and deploy target are all decisions the kit walks you through — **nothing is pre-selected.**

> **New to this, or not a terminal person?** Start at **[ONBOARDING.md](ONBOARDING.md)** — it meets you at your experience level and routes you back here.
> **Evaluating as an engineering leader?** → **[EXEC-BRIEF](docs/enterprise/EXEC-BRIEF.md)** — what it is, why now, risk posture, ROI.
> **Adopting into an existing codebase?** → **[brownfield adoption](docs/adoption/brownfield.md)** — merge into a repo you already have.

*(Why `adopter-export.sh` instead of a plain `git clone` or `cp`: it makes a clean, CI-ready copy of the kit — pruning its own scratch files, test fixtures, and maintainer-internal surface — so your project starts tidy. It keeps every stack profile, so your stack stays an Inception decision. New to the terms here? See [GLOSSARY.md](GLOSSARY.md).)*

## Who it's for

Any team — humans, agents, or both — starting a new project who wants production-grade discipline without inventing a process from scratch. Adopt it as-is, or hand it to a team and tailor it.

## What you get

- A **guided lifecycle** from idea → released, operating software: **Inception → Discover → Plan → Build → Review → Release → Operate ↺**.
- **Guardrails built in** — a control-plane guard, CI quality gates, a Definition of Done, and separation-of-duties on risky changes.
- **Stack-neutral standards + a swappable profile** for your chosen stack (10 shipped, or generate your own for *any* stack).
- **Harness-neutral** — Claude Code is the reference; any `AGENTS.md`-reading agent works.

## How you actually use it

**Sparkwright is the execution engine** — it takes you from a *Ready* backlog to operating, monitored software, with the guardrails built in. Each item flows through the loop (**Discover → Plan → Build → Review → Release → Operate**), and you, the human, sit on the gates: approve the design, make the go/no-go at release, accept the increment. The agents do the building between the gates.

If you already have product + design figured out, drop it in and build. If you're starting from raw signals, an optional upstream **discovery loop** (FRAME → SHAPE → Ready) turns them into a Ready backlog — see **[docs/discovery/discovery-loop.md](docs/discovery/discovery-loop.md)**. Skip it if you already have one.

## Staying current with the kit

Adopting is a fork, so the kit you adopted from keeps moving. `incept` vendors the **pristine tree you adopted from** into your own repo (the `kit-base` branch — [docs](docs/operations/kit-base.md)), and `sh scripts/kit-update.sh --from <kit>` uses it as a merge base to show you what a newer release would change: **offered** (kit-changed, you never touched it) · **CONFLICT** (changed on both sides — yours to decide) · **untouched** (yours). It **presents; it does not apply** — nothing of yours is written, and it moves you to *latest* only, never to an intermediate version. Full behaviour and its honest ceiling: **[docs/operations/kit-update.md](docs/operations/kit-update.md)**.

## Maturity

Sparkwright is at the **`release-candidate`** stage — hardened, dogfooded, and ready to adopt. **The kit is built with its own loop** — it holds itself to the same Definition of Done it gives you, on every change. Validation ledger and enforcement details by harness: **[MATURITY.md](MATURITY.md)**.

## Harness-neutral

Claude Code is the default and the reference adapter, but any harness that reads `AGENTS.md` (Codex, Cursor, Copilot…) is supported via the `generic` adapter, and you can bring your own with `sh scripts/new-adapter.sh <harness>`. Named `codex`, `cursor`, and `gemini` adapters ship as curated, conformance-locked starting points. The enforcement floor — the `kit-guard` CLI, the `pre-push` hook, and the `agent-boundary` CI gate — is **maintainer-verified to block destructive and control-plane actions regardless of harness** ([evidence](docs/operations/harness-enforcement-evidence.md)), and every adapter is held to the [boundary contract](docs/operations/harness-adapters.md).

## What's inside

| File | What it is |
|------|-----------|
| **`START-HERE.md`** | Run first — walks you through Inception, including choosing your stack. |
| **`ONBOARDING.md`** | The experience-aware front door — meets developers from vibe-coder to principal/architect, then hands to START-HERE. |
| **`CLAUDE.md`** | Principles + Definition of Done. Authoritative. |
| **`DEVELOPMENT-PROCESS.md`** | The agentic SDLC: Inception → Discover → Plan → Build → Review → Release → Done → Operate ↺. |
| **`DEVELOPMENT-STANDARDS.md`** | The universal, stack-neutral quality bar. |
| **`WALKTHROUGH.md`** | A narrative of the kit in motion — one feature from idea to operating software. |
| **`MAINTAINING.md`** | How the kit is built, versioned, and contributed back to. |
| **`profiles/`** | Per-stack specifics. `typescript-node.md` reference profile + `_TEMPLATE.md` to generate your own for *any* stack. |
| **`adapters/`** | Per-harness adapters: `claude-code` (reference) + `codex`/`cursor`/`gemini` + `generic` + `_TEMPLATE`/`new-adapter.sh` to BYO. |
| **`templates/`** | Project + intake/ops templates: `PROJECT-CLAUDE`, `BACKLOG`, `RUNBOOK`, `FEATURE-REQUEST`, `POSTMORTEM`, `BIA`, … (~24 in all). |
| **`docs/`** | `enterprise/` (compliance addendum), `work-tracking/` (backlog adapters), `adoption/` (brownfield · deploy targets), `operations/` (progressive delivery · resilience · DORA), `continuity/` (DR drill · BIA). |

## Generate your own profile (any stack)

The kit ships **10 reference profiles** — five first-class (**TypeScript/Node, Python, Go, ML, Terraform**) and five experimental (**Java/Spring, Kotlin, C#/.NET, Rust, Data Engineering** — provided as starting points, less exercised; see the [maturity tiers](docs/STACK-SELECTION.md)) — but it is **never limited to them**. For any other stack:

1. `sh scripts/new-profile.sh <stack>` — scaffolds `profiles/<stack>.md` + a stub `profiles/<stack>/ci.yml` whose 8 quality-gate ids already satisfy `conformance/ci-gates.sh`.
2. Fill the 11 profile sections and replace each `run:` command with your stack's tooling.
3. `sh conformance/profile-completeness.sh` validates it to the same bar as the shipped profiles.

Then select it at Inception and record it as ADR-000. A generated profile is held to the identical conformance bar — so "unsupported stack" is a guided, validated path, not a dead end.

## How the kit is built

Every capability ships as three parts (full detail in `MAINTAINING.md`):

- **Contract** — the binding, stack-neutral requirement (in the standards/process docs).
- **Reference implementation** — a working artifact you copy and adapt (in a profile or the repo). You own it.
- **Conformance check** — proof the implementation still satisfies the contract (in `conformance/`).

So the kit **dictates the contract and offers the implementation**: rewrite the reference freely as long as the conformance check still passes. The kit is itself a versioned product built with the very loop it prescribes — improvements adopters find flow back upstream as PRs.

## The core ideas

- **Governing lens:** rituals that *manage human effort* die; rituals that *clarify intent or improve quality* get stronger. Agent effort is cheap; human attention and integration risk are the scarce resources.
- **Flow, not sprints:** WIP-limited kanban; humans are the pacing metronome at the gates.
- **Closed loop:** production feeds the next idea; every retro exits into an artifact (the "adjust" step).
- **Agent governance:** autonomy tiers by risk × reversibility; irreversible actions are human-gated; autonomy is earned by metrics.
- **Universal + profile:** standards stay stack-neutral; the one stack-specific layer is a swappable profile.

## Where `.claude/` lives (scoping)

The kit ships a project-level **`.claude/`** (the `guard.sh` PreToolUse hook + `settings.json`). It is **scoped to this repo only** — it governs Claude Code within this repository's tree and does **not** touch your global `~/.claude/` or your machine.

- `.claude/settings.json` — committed **team policy** (registers the guard; permission allow/ask/deny).
- `.claude/settings.local.json` — **gitignored** personal per-developer overrides; never committed.

Adopting into an **existing** repo that already has its own `.claude/`? Follow `docs/adoption/brownfield.md` — **merge**, never overwrite, and verify with `sh conformance/guard-wired.sh`.

## Adapting it

Everything is meant to be tailored. Stack-specific → a profile. Project-specific → the project's own `CLAUDE.md`. Org-specific (stakeholder cadence, spend thresholds, SLO gating) → the configuration hooks the docs call out. Keep the universal files universal.

## License

Apache-2.0 — see [`LICENSE`](LICENSE).
