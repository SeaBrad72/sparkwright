# Conformance Checks

A **conformance check** proves that a reference implementation still satisfies its binding **contract** (see `../MAINTAINING.md` §1). Checks are how the kit — and every project that adopts it — enforces the contracts instead of merely describing them.

## Two kinds of check

- **Checklist** — a human/agent-completed list with explicit evidence per item. Used when judgment is required (e.g. architecture conformance). Gates at a human checkpoint.
- **Script** — an automated assertion runnable in CI. Used when the check is mechanical (e.g. "the CI pipeline runs a secret-scan step"). Gates in the pipeline.

## Where checks run

- **In the kit's own CI** (a later slice) — the kit proves it satisfies its own contracts.
- **In an adopting project** — at the gate named by the contract (Review, Definition of Done, etc., per `../DEVELOPMENT-PROCESS.md` §7).

## Index

| Check | Type | Contract it proves | Gate |
|-------|------|--------------------|------|
| `15-factor-checklist.md` | checklist | `DEVELOPMENT-STANDARDS.md` §13 (15-Factor Architecture) | Review (conditional) |
| `ci-gates.sh` | script | `DEVELOPMENT-STANDARDS.md` §14 (CI/CD Pipeline) | CI / Definition of Done |
| `check-links.sh` | script | Docs link integrity (`DEVELOPMENT-STANDARDS.md` §11) | CI |
| `agent-autonomy.sh` | script | `DEVELOPMENT-PROCESS.md` §13 (autonomy tiers) — guard denies a tier breach | PreToolUse hook / CI |
| `inception-done.sh` | script | `DEVELOPMENT-PROCESS.md` §3 / `START-HERE.md` (the Inception gate) | CI (bootstrap-into-temp) |
| `profile-completeness.sh` | script | `profiles/_TEMPLATE.md` (every profile fills all 11 sections; companion ci.yml conformant) | CI |
| `audit-evidence-checklist.md` | checklist | enterprise addendum (`../docs/enterprise/`) — per-control audit evidence | Review / pre-audit |

> The enterprise addendum (`../docs/enterprise/`) adds the compliance crosswalk and this audit-evidence checklist.
