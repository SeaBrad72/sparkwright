# Containment-readiness checklist

**Gate:** deploy/security gate (`DEVELOPMENT-PROCESS.md` §7). **Companion:** `conformance/containment-ready.sh`.
**Reference:** `docs/operations/containment.md`.

Closes what is reachable to exfiltrate at the source (platform-safety-boundary controls #2/#3/#4). The kit cannot make a host FS read-only, expire a token, or broker prod access — so it verifies the **posture is declared + attested**, never that it is enforced. A green run is **necessary, not sufficient**.

## Auto (proven by `containment-ready.sh`, per aspect)
- [ ] **Sandbox FS** — declared (a read-only-mount compose/devcontainer config, or a RUNBOOK `Sandbox FS:` mechanism line) + attested `enforced: <date>`.
- [ ] **Scoped tokens** — RUNBOOK `Scoped tokens:` line names a mechanism (OIDC→role / short TTL / least-privilege) + attested.
- [ ] **Prod credentials** — RUNBOOK `Prod credentials:` line names a mechanism (separate / break-glass / SoD) + attested.
- [ ] **N/A is explicit** — an aspect that genuinely does not apply records `<Aspect>: N/A — <reason>`.
- [ ] **Overall = weakest aspect** — partial coverage never reads as adequate.

## Manual (the script CANNOT prove — platform/operator evidence)
- [ ] **The FS is actually read-only** — an agent process genuinely cannot read `~/.ssh`, `~/.aws`, other projects, or host secrets (test from inside the sandbox).
- [ ] **Tokens actually expire** — the issued credential is time-boxed and least-privilege in practice, not just declared.
- [ ] **Prod creds are actually unreachable** — a leaked dev/agent credential genuinely cannot touch production (break-glass is the only path).

## Honesty
PASS means the posture is **declared + attested**, never that the kit verified read-only FS / token TTL / cred separation. Enforcement is platform-owned (`docs/enterprise/platform-safety-boundary.md` controls #2/#3/#4); 11c makes it **verifiable** (Kit-assisted), not Kit-enforced.
- **Attestation dates are honor-based.** The gate verifies an `enforced: <date>` is present and well-shaped on the aspect's own line — not that the date is accurate or that the aspect isn't self-contradicted elsewhere on that line. Keep one aspect per line; the date attests *that line's* aspect.
