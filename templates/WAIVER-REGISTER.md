# Waiver Register

**Governed exceptions to the CI gates — for brownfield adoption, and for a hosted-tracker backend until the tracker seam ships.** A waiver is the honest alternative to faking green: instead of disabling a gate, you record a **tracked, time-boxed, owned, ratified** exception with a remediation plan. Operationalizes the governed-exception process (`docs/enterprise/ratification-rbac.md`); validate this file with `sh conformance/waivers-valid.sh` — wire it into your own pipeline if you want it enforced, because nothing you receive runs it for you.

> **Non-negotiable gates — NEVER waivable, even at adoption:**
> - **`secret-scan`** — a repo must never ship secrets. If your secret-scan can't run day one, that is a hard blocker (fix it), not a waiver.
> - **`branch-protection`** — segregation of duties is day-one.
>
> A waiver naming either is **invalid** and fails `waivers-valid.sh`.

> **Waivable during the adoption window** (each needs an owner, a remediation plan, and an expiry): `coverage`, `sbom`, `provenance`, `dependency-vuln`, `a11y`, `container-image`, `board-governance`.
>
> **`board-governance`** is the hosted-tracker gap. The kit's board-bound gates (`backlog-presence`, `backlog-current`, `loop-state`'s row check) read `BACKLOG.md` only, so on a `github`/`jira`/`ado`/`linear`/`gitlab` backend they report **NOT ENFORCED** and go red. A ratified row here renders them green **with the notice still printed on every run** — the exception is never invisible, and the gate is still not enforced. `incept` stamps this row for you with `[owner]` and `[security-owner]` placeholders; a bracketed placeholder does **not** satisfy `sh conformance/waivers-valid.sh --active board-governance`, so a human must fill both cells. `TRACKER-BACKED-GOVERNANCE` closes the gap for real.
>
> **Max lifetime: 90 days.** `Expires − Opened` may not exceed 90 days. Renewal = a new ratified row (re-justify), not an extension.
>
> Fields are all required. `Opened`/`Expires` are `YYYY-MM-DD`. An expired waiver **fails** the check — renew before it lapses. **`Opened` may not be in the future**: a forward-dated Opened turns the 90-day maximum into a formality (`Opened 2099-01-01 · Expires 2099-03-01` is a 59-day span that never expires), so date the row when the exception was actually ratified.

## Active waivers

| Gate | Reason | Owner | Opened | Expires | Remediation plan | Ratified-by |
|------|--------|-------|--------|---------|------------------|-------------|

<!-- Add one row per active waiver above this line. Remove a row when the gap is fixed and the gate passes unwaived. -->

## Example (illustrative — delete before use; NOT validated)

| Gate | Reason | Owner | Opened | Expires | Remediation plan | Ratified-by |
|------|--------|-------|--------|---------|------------------|-------------|
| coverage | Legacy service at 41% line coverage; can't hit 80% on day one | @jdoe | 2026-06-01 | 2026-08-30 | Ratchet from 41 baseline, +10 pts/sprint to 80% (coverage-ratchet.sh) | @security-owner |
| dependency-vuln | 3 high CVEs in a transitive dep pending an upstream fix | @jdoe | 2026-06-01 | 2026-07-15 | Track upstream #1234; pin + patch when released | @security-owner |
