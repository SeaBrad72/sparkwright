# Sparkwright

*The agentic SDLC kit — guardrails that let anyone build production-grade software, from intent to operating software.*

`v3.43.0` · Apache-2.0 · [CHANGELOG](CHANGELOG.md) · [how the kit is maintained](MAINTAINING.md)

A complete, **stack-agnostic** software development lifecycle designed for teams working with AI agents — from idea through released, operating software. Drop it into a new project, choose your stack, and run `incept` — for a service stack it scaffolds a runnable starter whose **language CI pipeline is green on clone**; the `Dockerfile` + `compose.yaml` are **COPY-&-ADAPT references** you adapt when you containerize (the image-build gates skip until you do). So you start from a working language pipeline, not an empty repo. (Green-on-clone scope is honest per stack — see the Quickstart.)

It is opinionated about *how to build well with agents* and deliberately neutral about *what you build it with* — both the **stack** and the **AI harness**.

**Harness-neutral.** Claude Code is the default and the reference adapter, but any harness that reads `AGENTS.md` (Codex, Cursor, Copilot…) is supported via the `generic` adapter, and you can BYO with `sh scripts/new-adapter.sh <harness>`. Named `codex`, `cursor`, and `gemini` adapters ship as curated, conformance-locked starting points. The enforcement floor — the `kit-guard` CLI, the `pre-push` hook, and the `agent-boundary` CI gate — is **maintainer-verified to block destructive and control-plane actions regardless of harness** ([docs/operations/harness-enforcement-evidence.md](docs/operations/harness-enforcement-evidence.md)), and every adapter is held to the boundary contract ([docs/operations/harness-adapters.md](docs/operations/harness-adapters.md)). Driving a specific third-party agent through it is the recommended first real-world validation — not a claim we make for you.

> **Sparkwright is the execution engine** — it takes you from a *Ready* backlog to operating, monitored software, with the guardrails built in. If you already have product + design figured out, drop it in and build: for a service stack, `incept` gives you a runnable starter wired to CI to build on (each profile's `scaffold/README.md` carries the per-stack first-green step). (A discovery front-end — turning raw signals into Ready work — is an optional upstream layer — see **[docs/discovery/discovery-loop.md](docs/discovery/discovery-loop.md)**.)

Choosing a stack? See [docs/STACK-SELECTION.md](docs/STACK-SELECTION.md).

**For engineering leaders →** [docs/enterprise/EXEC-BRIEF.md](docs/enterprise/EXEC-BRIEF.md) — what it is, why now, risk posture, ROI.

New to the terminology? See [GLOSSARY.md](GLOSSARY.md).

**Brand new to enterprise software practices?** Start at [ONBOARDING.md](ONBOARDING.md) — it places you by experience and teaches the system around the code.

## Who it's for
Any team — humans, agents, or both — starting a new project who wants production-grade discipline without inventing a process from scratch. Adopt it as-is, or hand it to a team and let them tailor it.

## What's inside

| File | What it is |
|------|-----------|
| **`START-HERE.md`** | Run first — walks you through Inception, including choosing your stack. |
| **`ONBOARDING.md`** | The experience-aware front door — meet developers from vibe-coder to principal/architect, then hand to START-HERE. |
| **`MAINTAINING.md`** | How the kit is built, versioned, and contributed back to (the contract/reference/conformance convention). |
| **`WALKTHROUGH.md`** | A narrative of the kit in motion — one feature from idea to operating software. |
| **`docs/discovery/`** | The optional upstream **discovery loop** (FRAME → SHAPE → Ready) — turn a raw signal into a Ready backlog. Skip it if you already have one. |
| **`CLAUDE.md`** | Principles + Definition of Done. Authoritative. |
| **`DEVELOPMENT-PROCESS.md`** | The agentic SDLC: Inception → Discover → Plan → Build → Review → Release → Done → Operate ↺. |
| **`DEVELOPMENT-STANDARDS.md`** | The universal, stack-neutral quality bar. |
| **`profiles/`** | Per-stack specifics. `typescript-node.md` reference profile + `_TEMPLATE.md` to generate your own for *any* stack. |
| **`adapters/`** | Per-harness adapters: `claude-code` (reference) + `codex` / `cursor` / `gemini` (named, conformance-locked floor adapters) + `generic` (floor-only, for any `AGENTS.md` reader) + `_TEMPLATE` / `new-adapter.sh` to BYO. Boundary contract: [docs/operations/harness-adapters.md](docs/operations/harness-adapters.md). |
| **`templates/`** | Project + intake/ops templates: `PROJECT-CLAUDE`, `BACKLOG`, `RUNBOOK`, `FEATURE-REQUEST`, `SPEC`, `POSTMORTEM`, `BIA`, … (~24 in all — see [`templates/`](templates/)). |
| **`docs/`** | `ADR-000-EXAMPLE.md`; `enterprise/` (compliance addendum), `work-tracking/` (backlog adapters), `adoption/` (brownfield), `operations/` (progressive delivery · resilience · DORA), `continuity/` (DR drill · BIA). |

## Quickstart (drop-in & go)
1. **Obtain a clean copy** (use the export script — not `cp -R` or a plain clone):
   ```sh
   git clone --depth 1 <kit-url> /tmp/sparkwright-src
   sh /tmp/sparkwright-src/scripts/adopter-export.sh ./my-project --profile typescript-node
   ```
   You get **242 files** for typescript-node (the kit + your chosen stack), down from 392. The export drops the kit's own
   backlog/CI-watchers/test-fixtures and the 9 stack profiles you aren't using.
   *(Why the script: `export-ignore` only takes effect via `git archive`/this script. A plain
   `cp -R` drags gitignored scratch + `node_modules`; a plain `git clone` carries the full kit.
   The kit's conformance suite and a few maintainer docs are intentionally retained.)*
2. Open **`START-HERE.md`** and work through Inception (Phase 0).
3. At stack selection: pick a ready profile **or** generate one from `profiles/_TEMPLATE.md` for your stack — recorded as **ADR-000**.
4. Run **`scripts/incept.sh`** — for a **service stack** it scaffolds a runnable starter (a `/healthz` service + test wired to the stack's CI) and writes `.env.example`. **Green-on-clone scope, honest per stack:** `typescript-node`'s **language gates** (install → lint → type-check → test+coverage → build) are maintainer-verified green on clone; `go` and `rust` are **dependency-free** (stdlib-only scaffolds — no lockfile step); `python`, `java-spring`, `kotlin`, and `dotnet` need a **one-time lockfile/wrapper step** (see each `scaffold/README.md`). Stacks other than `typescript-node` have not been maintainer-executed. The **image-supply-chain gates are conditional** — they skip until you adapt the profile's **COPY-&-ADAPT `Dockerfile`** (and `compose.yaml`) into your repo, so a bare scaffold's first push is green on the language gates, not red on `docker build`. **`ml` / `data-engineering` / `terraform`** ship a CI contract you populate (no `/healthz` starter — first push is red until you add source).
5. Pass the **Inception Done** gate → enter the loop at **Discover**.

## Where `.claude/` lives (scoping)

The kit ships a project-level **`.claude/`** (the `guard.sh` PreToolUse hook + `settings.json`). It is **scoped to this repo only** — it governs Claude Code within this repository's tree and does **not** touch your global `~/.claude/` or your machine.

- `.claude/settings.json` — committed **team policy** (registers the guard; permission allow/ask/deny).
- `.claude/settings.local.json` — **gitignored** personal per-developer overrides; never committed.

Dropping the kit into a repo affects only that repo. Adopting into an **existing** repo that already has its own `.claude/`? Follow `docs/adoption/brownfield.md` — **merge**, never overwrite, and verify with `sh conformance/guard-wired.sh`.

## How the kit is built

Every capability ships as three parts (full detail in `MAINTAINING.md`):

- **Contract** — the binding, stack-neutral requirement (in the standards/process docs).
- **Reference implementation** — a working artifact you copy and adapt (in a profile or the repo). You own it.
- **Conformance check** — proof the implementation still satisfies the contract (in `conformance/`).

So the kit **dictates the contract and offers the implementation**: rewrite the reference freely as long as the conformance check still passes. The kit is itself a versioned product (`VERSION`, `CHANGELOG.md`) that is built with the very loop it prescribes — improvements found by adopters flow back upstream as PRs.

## The core ideas
- **Governing lens:** rituals that *manage human effort* die; rituals that *clarify intent or improve quality* get stronger. Agent effort is cheap; human attention and integration risk are the scarce resources.
- **Flow, not sprints:** WIP-limited kanban; humans are the pacing metronome at the gates.
- **Closed loop:** production feeds the next idea; every retro exits into an artifact (the "adjust" step).
- **Agent governance:** autonomy tiers by risk × reversibility; irreversible actions are human-gated; autonomy is earned by metrics.
- **Universal + profile:** standards stay stack-neutral; the one stack-specific layer is a swappable profile.

## Generate your own profile (any stack)

The kit ships first-class profiles for **TypeScript/Node, Python, Java/Spring, C#/.NET, Go, Rust, Kotlin, Data Engineering, ML, and Terraform** (10 in all) — but it is **never limited to them**. For any other stack:

1. `sh scripts/new-profile.sh <stack>` — scaffolds `profiles/<stack>.md` (from the template) + a stub `profiles/<stack>/ci.yml` whose 8 quality-gate ids already satisfy `conformance/ci-gates.sh`.
2. Fill the 11 profile sections and replace each `run:` command with your stack's tooling.
3. `sh conformance/profile-completeness.sh` validates it to the same bar as the shipped profiles.

Then select it at Inception (`incept.sh --stack <stack>`) and record it as ADR-000. A generated profile is held to the identical conformance bar — so "unsupported stack" is a guided, validated path, not a dead end.

## Adapting it
Everything is meant to be tailored. Stack-specific → a profile. Project-specific → the project's own `CLAUDE.md`. Org-specific (stakeholder cadence, spend thresholds, SLO gating) → the configuration hooks the docs call out. Keep the universal files universal.

## License
Apache-2.0 — see [`LICENSE`](LICENSE).
