# Waiver Register

**Governed exceptions to the CI gates — for brownfield adoption only.** A waiver is the honest alternative to faking green: instead of disabling a gate, you record a **tracked, time-boxed, owned, ratified** exception with a remediation plan. Operationalizes the governed-exception process (`docs/enterprise/ratification-rbac.md`); validated by `conformance/waivers-valid.sh`.

> **Non-negotiable gates — NEVER waivable, even at adoption:**
> - **`secret-scan`** — a repo must never ship secrets. If your secret-scan can't run day one, that is a hard blocker (fix it), not a waiver.
> - **`branch-protection`** — segregation of duties is day-one.
>
> A waiver naming either is **invalid** and fails `waivers-valid.sh`.

> **Waivable during the adoption window** (each needs an owner, a remediation plan, and an expiry): `coverage`, `sbom`, `provenance`, `dependency-vuln`, `a11y`, `container-image`.
>
> **Max lifetime: 90 days.** `Expires − Opened` may not exceed 90 days. Renewal = a new ratified row (re-justify), not an extension.
>
> Fields are all required. `Opened`/`Expires` are `YYYY-MM-DD`. An expired waiver **fails** the check — renew before it lapses.

## Active waivers

| Gate | Reason | Owner | Opened | Expires | Remediation plan | Ratified-by |
|------|--------|-------|--------|---------|------------------|-------------|

<!-- Add one row per active waiver above this line. Remove a row when the gap is fixed and the gate passes unwaived. -->

## Example (illustrative — delete before use; NOT validated)

| Gate | Reason | Owner | Opened | Expires | Remediation plan | Ratified-by |
|------|--------|-------|--------|---------|------------------|-------------|
| coverage | Legacy service at 41% line coverage; can't hit 80% on day one | @jdoe | 2026-06-01 | 2026-08-30 | Ratchet from 41 baseline, +10 pts/sprint to 80% (coverage-ratchet.sh) | @security-owner |
| dependency-vuln | 3 high CVEs in a transitive dep pending an upstream fix | @jdoe | 2026-06-01 | 2026-07-15 | Track upstream #1234; pin + patch when released | @security-owner |
