# Progressive Delivery — Reference

How to roll out a release **without big-bang risk**: validate on a slice before full exposure, and gate every promotion with a smoke/synthetic check. Stack-neutral; tooling is a project/Org choice. The executable half of `DEVELOPMENT-PROCESS.md` §10 (Safe Change Delivery). Pairs with the Release gate `conformance/definition-of-deployable.md`.

> **Principle — reduce blast radius.** Never expose 100% of users to an unverified release. Ship to a slice, prove it, then widen. The cheapest rollback is the one you make before you widen.

## Strategies
- **Staged rollout** — staging → small % → full. The §10 default and the Stage-1 baseline; no special tooling needed.
- **Canary** — deploy to a small **production** slice (e.g. 1–5% of traffic), **smoke it and run canary analysis** (watch error rate / latency / saturation vs. the SLO, §9), then **widen or abort**. A failed canary never reaches most users.
- **Blue-green** — deploy to the idle **green** stack, **smoke green at zero live traffic**, then cut traffic over; keep **blue** warm for instant rollback.

## Smoke / validation gates — at every promotion boundary
Smoke is not just a post-deploy afterthought. Gate **each** boundary; a failed check **stops promotion / rolls back**, it does not just log:
1. **Lower environments (QA/UAT)** — smoke/acceptance before promoting toward prod (`DEVELOPMENT-PROCESS.md` "Environments & promotion").
2. **Canary slice / green stack — before widening or cutover** *(highest-value gate)* — smoke the slice while its blast radius is still 1–5% (canary) or zero live traffic (green). This is the validation that happens **before** the rollout reaches production at large.
3. **After full rollout** — a final smoke to confirm the fully-promoted release.

## Automated canary analysis
Define **abort thresholds** against the SLO / error budget (§9): error rate, p95/p99 latency, saturation (CPU/memory/connections). The analysis is the **automated "validate-before-widening" gate** — it widens on green, aborts and rolls back on breach. Follows the same **soft → gating** maturity progression as error budgets (§9): start by watching, promote to auto-abort at scale.

## Rollback
Per §10 preference order: **flag-off → redeploy previous → revert + redeploy**. In canary/blue-green, the lowest-blast-radius rollback is structural: **don't widen** (canary) or **don't cut over** (green) — the bad release never reaches full traffic. Every release declares its rollback path before it ships (§10).

## Tooling (Org-owned)
Argo Rollouts, Flagger, a service-mesh canary, or a **flag-driven** staged rollout (§10 feature flags) are platform choices. The kit standardizes the **practice** — slice → smoke → analyze → widen-or-abort — not the tool.

> **Reference + lifecycle:** see [feature-flags.md](feature-flags.md) for the kill-switch flag the kit ships (registry, env toggle, retire ritual) and what it does/doesn't claim.
