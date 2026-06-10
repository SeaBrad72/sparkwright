# Conformance Checks

A **conformance check** proves that a reference implementation still satisfies its binding **contract** (see `../MAINTAINING.md` §1). Checks are how the kit — and every project that adopts it — enforces the contracts instead of merely describing them.

## Two kinds of check

- **Checklist** — a human/agent-completed list with explicit evidence per item. Used when judgment is required (e.g. architecture conformance). Gates at a human checkpoint.
- **Script** — an automated assertion runnable in CI. Used when the check is mechanical (e.g. "the CI pipeline runs a secret-scan step"). Gates in the pipeline.

## Where checks run

- **In the kit's own CI** (`.github/workflows/ci.yml`) — the kit proves it satisfies its own contracts.
- **In an adopting project** — at the gate named by the contract (Review, Definition of Done, etc., per `../DEVELOPMENT-PROCESS.md` §7).

## What a green run means — and doesn't

Conformance checks fall into two honesty classes. Run **`sh conformance/verify.sh`** for an aggregate that labels each one:

- **control** — proves a *working* control holds: the agent guard denies the destructive battery (`agent-autonomy.sh`), CI declares the required gate ids (`ci-gates.sh`), the guard is wired (`guard-wired.sh`), `main` is protected on the remote (`branch-protection.sh`), links resolve (`check-links.sh`), named backlog backends agree (`backlog-adapters.sh`), and — conditionally — the image supply-chain is wired (`container-supply-chain.sh`, only when a Dockerfile is present, so it is not in `verify.sh`'s unconditional aggregate). Green here is load-bearing.
- **documentation / evidence** — proves a procedure is *written down* and (for readiness) a drill **date is recorded** — NOT that the rollback, restore, or fault-injection was actually tested: `deployable-ready.sh`, `dr-ready.sh`, `resilience-ready.sh`, and the paired `*-readiness.md` / `definition-of-deployable.md` checklists. The "did it actually work" half lives in the checklist's Manual rows, requiring release-manager / on-call evidence.

**`UNVERIFIED` is not a pass.** A check that cannot run — e.g. `branch-protection.sh` with no `gh`/remote — exits **2** and is reported `UNVERIFIED`, distinct from PASS; in CI or under `--require` it escalates to a **FAIL**. A green dashboard hiding an unseen UNVERIFIED is the false assurance this layer exists to prevent.

In short: **green proves controls hold and safety is documented; it does not prove the documented procedures were tested.**

## Index

| Check | Type | Contract it proves | Gate |
|-------|------|--------------------|------|
| `15-factor-checklist.md` | checklist | `DEVELOPMENT-STANDARDS.md` §13 (15-Factor Architecture) | Review (conditional) |
| `definition-of-deployable.md` | checklist | `DEVELOPMENT-PROCESS.md` §10 / §4 (release readiness) | Release (conditional) |
| `deployable-ready.sh` | script | `DEVELOPMENT-PROCESS.md` §10 — documented release-safety (RUNBOOK deploy/rollback + smoke); pairs with the checklist | Release / CI (conditional on a deploy surface) |
| `dr-readiness.md` | checklist | `DEVELOPMENT-STANDARDS.md` §10 / NIST 800-34 (DR is provable) | Review / recurring / DoD (conditional) |
| `dr-ready.sh` | script | `DEVELOPMENT-STANDARDS.md` §10 — documented DR (BIA + RUNBOOK §6 + recorded drill); escalate-only; pairs with the checklist | Review / CI (conditional on a data surface) |
| `resilience-readiness.md` | checklist | `DEVELOPMENT-STANDARDS.md` §4 / §6 (resilience + load/soak) | Review / recurring (conditional) |
| `resilience-ready.sh` | script | `DEVELOPMENT-STANDARDS.md` §4 / §6 — recorded resilience drills (RUNBOOK §8); pairs with the checklist | Review / CI (conditional on a deploy surface) |
| `ci-gates.sh` | script | `DEVELOPMENT-STANDARDS.md` §14 (CI/CD Pipeline) — recognizes GitHub `id: gate-X` steps **and** GitLab `gate-X:` job keys; the contract is the gate-ids, the platform is open (`../docs/operations/ci-platforms.md`) | CI / Definition of Done |
| `check-links.sh` | script | Docs link integrity (`DEVELOPMENT-STANDARDS.md` §11) | CI |
| `agent-autonomy.sh` | script | `DEVELOPMENT-PROCESS.md` §13 (autonomy tiers) — guard denies a tier breach | PreToolUse hook / CI |
| `guard-core-sourced.sh` | script | `DEVELOPMENT-PROCESS.md` §13 — all guard consumers source one deny-matrix core (anti-fork); pairs with `agent-autonomy.sh` (`../docs/operations/runtime-guards.md`) | CI |
| `../scripts/preflight.sh` | script | beginner on-ramp (Slice 9f) — prerequisite check (jq/git/toolchain); `--selftest` regression-locks the detector | CI / pre-Inception |
| `inception-done.sh` | script | `DEVELOPMENT-PROCESS.md` §3 / `START-HERE.md` (the Inception gate) | CI (bootstrap-into-temp) |
| `profile-completeness.sh` | script | `profiles/_TEMPLATE.md` (every profile fills all 11 sections; companion ci.yml conformant) | CI |
| `stack-selection.sh` | script | Slice 9g / R7 — the stack-decision aid is complete (guide + per-profile Best-for/Avoid-when + a matrix row per profile); drift-guard | CI |
| `branch-protection.sh` | script | `DEVELOPMENT-STANDARDS.md` §14 / `DEVELOPMENT-PROCESS.md` §12 — `main` is actually protected | CI (where gh can reach the API) |
| `audit-evidence-checklist.md` | checklist | enterprise addendum (`../docs/enterprise/`) — per-control audit evidence | Review / pre-audit |
| `container-supply-chain.sh` | script | `DEVELOPMENT-STANDARDS.md` §14 (conditional container image supply-chain) | Review (conditional on a Dockerfile) |
| `backlog-adapters.sh` | script | `DEVELOPMENT-PROCESS.md` §6 (named backends agree across incept / §6 / the adapter guide) | CI / Review |
| `guard-wired.sh` | script | `DEVELOPMENT-PROCESS.md` §13 — the `.claude/` runtime guard is actually wired (fail-closed; gates Inception) | CI / Inception |
| `waivers-valid.sh` | script | `DEVELOPMENT-PROCESS.md` §13 / `DEVELOPMENT-STANDARDS.md` §14 — brownfield `WAIVER-REGISTER.md` is well-formed (no expired / non-negotiable / over-90d / missing-field waivers); N/A without a register | Review / CI (adoption-conditional) |
| `verify.sh` | script | the honest **aggregate** — runs the checks, labels each **control** vs **documentation**, gates on control failures; prints what a green run does and does not prove | CI (`--selftest`) / Review |

> The enterprise addendum (`../docs/enterprise/`) adds the compliance crosswalk and this audit-evidence checklist.

> **Note on `inception-done.sh` at the kit root:** this gate is *expected to FAIL* when run against the kit's own repository — the kit is the reference/template **source**, not an instantiated project (it has no `ADR-000`, `RUNBOOK.md`, etc.). It passes only inside a project that has completed Inception. Do not "fix" the kit root to satisfy it.

> **Progressive delivery (reference, no separate check):** `definition-of-deployable.md`'s progressive-delivery + smoke-gate rows pair with [`../docs/operations/progressive-delivery.md`](../docs/operations/progressive-delivery.md) for the *how* (canary/blue-green + smoke gates at every promotion boundary). The checklist is the conformance; the reference completes the triad.

> **DORA metrics (measurement-enablement, no gate):** §14's DORA four + agentic signals are *collected*, not gated — `../scripts/dora.sh` (GitHub-derivable subset; CI-smoked via `--selftest`) + [`../docs/operations/dora-metrics.md`](../docs/operations/dora-metrics.md) (derivation + the maturity-gating path). Value-gating is a §9 maturity step, not a baseline check.

> **Conditional checks — N/A semantics differ by blast radius.** `deployable-ready.sh` and `resilience-ready.sh` **skip-pass** cleanly when a project has no deploy surface — a miss is acceptable (it isn't a deployable service). `dr-ready.sh` is **escalate-only**: its `N/A` is *self-incriminating* (data detection is conservative, and a missed data project is a false negative with data-loss stakes), so `dr-readiness.md` applies regardless of what the script prints. The N/A weight matches the blast radius.
