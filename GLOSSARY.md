# Glossary

The load-bearing terms of this kit, each with a one-line definition and a link to its authoritative home. New here? Read [`START-HERE.md`](START-HERE.md).

**Inception (Phase 0)** — The one-time gate that turns an empty repo into a loop-ready project: choose a stack, stamp the templates, set up the guard and CI. ([`START-HERE.md`](START-HERE.md), [`DEVELOPMENT-PROCESS.md`](DEVELOPMENT-PROCESS.md) §3)

**The loop** — The recurring delivery cycle every feature runs through: Discover → Plan → Build → Review → Release → Done. ([`DEVELOPMENT-PROCESS.md`](DEVELOPMENT-PROCESS.md) §4)

**Discovery loop** — the optional upstream front-end (FRAME → SHAPE → Ready) that turns a raw signal into a Ready backlog the Sparkwright engine consumes. Opt-in; skip it if you already have a Ready backlog. See `docs/discovery/discovery-loop.md`.

**FRAME / SHAPE** — the two discovery stages this kit adds: FRAME (Product-owned) frames a raw signal into an evidenced problem (gate: Frame approved); SHAPE (Design-owned) explores it into a chosen direction (gate: Direction chosen). Stages 3–6 of the loop (PLAN/BUILD/SHIP/OBSERVE) are the existing engine.

**Contract → reference → conformance** — The kit's enforcement spine: a stated contract (what must hold), a reference implementation (one way to satisfy it), and an executable check (proof it holds). ([`MAINTAINING.md`](MAINTAINING.md), [`conformance/README.md`](conformance/README.md))

**Conformance check** — An executable script that proves a control actually holds, rather than asserting it in prose. ([`conformance/README.md`](conformance/README.md))

**Ratification** — Agents propose, humans approve. Agents never self-merge the standards, process, or control-plane files that govern them. ([`docs/enterprise/ratification-rbac.md`](docs/enterprise/ratification-rbac.md))

**Autonomy tiers (L1/L2/L3)** — How much an agent may do without human sign-off, from suggest-only to act-then-report. ([`DEVELOPMENT-PROCESS.md`](DEVELOPMENT-PROCESS.md) §13)

**The guard** — The PreToolUse deny-matrix that blocks dangerous commands. A speed-bump that surfaces intent, not a security boundary. ([`.claude/hooks/guard.sh`](.claude/hooks/guard.sh), [`docs/operations/runtime-guards.md`](docs/operations/runtime-guards.md))

**The 7 CI gates** — The required pipeline checks: lint, type-check, test+coverage, build, secret-scan, dep-scan, and supply-chain (SBOM+provenance). ([`DEVELOPMENT-STANDARDS.md`](DEVELOPMENT-STANDARDS.md) §14)

**Waiver** — A tracked, time-boxed, ratified exception to a gate, used to adopt the kit on an existing (brownfield) repo without faking green. ([`templates/WAIVER-REGISTER.md`](templates/WAIVER-REGISTER.md))

**Stage 1–4** — The maturity progression that tightens conformance as a project or org scales, from solo/lite up to full enterprise enforcement. ([`docs/enterprise/ORG-ROLLOUT.md`](docs/enterprise/ORG-ROLLOUT.md))

**Operator fluency** — A project's declared signal of the human operator's enterprise-SDLC experience (Novice / Adjacent / Practitioner), set in `CLAUDE.md` §3. The agent adapts how it communicates to match (see [`docs/operations/operator-fluency.md`](docs/operations/operator-fluency.md)); it never changes what the agent is permitted to do.

**Profile** — The per-stack concrete config, commands, and examples you select at Inception; keeps the rest of the kit stack-neutral. ([`profiles/`](profiles/))

**Control-plane** — The kit's own integrity files (guard, settings, CI, CODEOWNERS) that an agent may not silently edit; changes here require ratification. ([`docs/operations/runtime-guards.md`](docs/operations/runtime-guards.md))

**Green ≠ verified** — A passing check proves only what it actually tests, never more. Treat green as evidence of a specific control, not blanket correctness. ([`conformance/README.md`](conformance/README.md))
