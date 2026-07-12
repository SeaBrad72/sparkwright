# DORA Metrics — Collection Reference

How to **collect** the DORA four + the kit's two agentic-specific signals that `DEVELOPMENT-PROCESS.md` §14 defines. Measurement is the precondition for the soft→hard-gating maturity the kit describes (§9). Stack-neutral; tooling is a project/Org choice. Aligns with the **DORA** program (Accelerate / State of DevOps).

> **DORA is a feedback instrument, not a gate.** Collect and surface these in metrics and retros. **Value-gating** (freeze releases when change-failure / MTTR breach a threshold) is a **maturity step** (§9 error budgets, soft → hard), *opt-in at scale* — never a baseline imposed on an early-stage project.

## Per metric — GitHub data source & derivation

| Metric | DORA / agentic | Data source | Derivation |
|--------|----------------|-------------|------------|
| **Deployment frequency** | DORA | GitHub **Deployments API** (true) / **Releases** (proxy) | count of deployments (or releases) per window |
| **Lead time for changes** | DORA | PR/commit **created → merged → deployed** timestamps | median/avg of (deployed − first-commit); PR created→merged is the universal proxy |
| **Change-failure rate** | DORA | deployments + an **incident signal** (an `incident`/`postmortem` label, or the §15 record) | deployments causing an incident/revert ÷ total deployments |
| **MTTR** | DORA | incident **open → resolved** (issues with an `incident` label, or postmortem records) | avg(resolved − opened) |
| **Review latency** | agentic | PR **created → first review** | avg(first-review − created) — the human bottleneck (§14) |
| **Retro-action closure** | agentic | backlog items labelled `retro`/`adjust` (§6) | closed ÷ total retro action items |

## What `scripts/dora.sh` collects (the GitHub-derivable subset)
`scripts/dora.sh` reports, for the current repo, what is derivable from any GitHub repo with `gh`:
- **Release cadence** (deployment-frequency proxy), **PR lead time** (lead-time proxy), **Review latency**.
It **degrades gracefully** (prints "unavailable" and exits 0 if `gh`/auth/scope is missing — a report never fails a pipeline). The remaining metrics — **true deployment frequency, change-failure rate, MTTR, retro-action closure** — are **adopter-wired**: they need deployment events + an incident/retro signal your platform records.

```
sh scripts/dora.sh             # last 30 days
sh scripts/dora.sh --window 7  # last 7 days
```

## Wiring the adopter-owned metrics
- **Deployment events** — have your deploy workflow record a GitHub **Deployment** (or a deploy log/warehouse row) per environment promotion (§9 promotion).
- **Incident signal** — label incident issues `incident` and link the postmortem (standards §15 / 8a); change-failure rate and MTTR derive from these + deployment events.
- **Retro-action closure** — label retro action items `retro` on the backlog (§6); closure rate is closed ÷ total.

## The maturity-gating path (the home for DORA enforcement)
Per §9 (error budgets, soft → hard):
- **Default — surface, don't gate.** Report the metrics in dashboards and retros; let trends inform improvement.
- **Maturity step — gate.** At production scale, promote to gating: e.g. **freeze non-critical releases when change-failure rate or MTTR breaches the budget** until reliability recovers. Mirrors the §9 error-budget promotion and the Stage 1–4 maturity progression in `../enterprise/ORG-ROLLOUT.md`. This is opt-in at scale — not a baseline check.

## Dashboard pattern
Surface the metrics on a cadence/format the org sets (a configuration point, not a fixed ritual; ties to §12 stakeholder visibility):
- **DORA "Four Keys"** (the reference implementation), **Grafana** over a metrics warehouse, or a **board digest** (§12).
- Feed `scripts/dora.sh` output into the digest for the GitHub-derivable subset; wire deployment/incident sources for the rest.

## Tooling (Org-owned)
Four Keys, Grafana, a metrics warehouse, or `scripts/dora.sh` for the GitHub-derivable subset. The kit standardizes the **metric definitions and the derivation**, not the dashboard.
