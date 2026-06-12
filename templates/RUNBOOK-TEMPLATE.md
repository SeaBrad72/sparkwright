# [Project Name] — RUNBOOK

> **Template.** Created at Inception; grow it at each release. Must enable a **cold resume** by another engineer or agent (DEVELOPMENT-STANDARDS.md §11). Fill every `[...]`.

**Project:** [Project Name]
**Last Updated:** [date]

---

## 1. Local setup
- Prerequisites: [runtime + version, package manager, Docker/devcontainer]
- Install: `[install command]`
- Configure env: copy `.env.example` → `.env.local`, fill values (see §3)
- Run locally: `[dev command]`

## 2. Test / build
- Test: `[test command]` · Coverage: `[coverage command]` (≥80%, 100% critical)
- Lint / type-check: `[commands]`
- Build: `[build command]`
- **Test data:** [approach] *(data-handling projects — synthetic/masked/never-raw-prod; see `docs/operations/test-data-management.md`)*

## 3. Environment variables
Documented in `.env.example` (committed, placeholders only). Required:
- `[VAR]` — [purpose] — [where to obtain]

## 4. Deploy
- Target: [Vercel / Railway / container / …]
- Promotion: Dev → QA → UAT → Prod (prod is human-gated — see `DEVELOPMENT-PROCESS.md` "Environments & promotion")
- **Preview environments:** [approach] *(deployable services — per-PR isolated, safe test data, scoped creds, auto-teardown; see `docs/operations/preview-environments.md`)*
- Trigger: [per-tier deploy trigger; e.g. CI green on PR → Dev; human approval → Prod]
- Steps: `[deploy command(s)]`
- Smoke test: after each deploy run the post-deploy smoke test (`[smoke test command]`) and record the result before declaring the release live — gates the **Definition of Deployable** (`conformance/definition-of-deployable.md`).
- Network egress: default-deny via [k8s NetworkPolicy | cloud egress firewall | forward proxy] — enforced: [date]  <!-- The only reliable exfiltration defense (`docs/operations/egress-control.md`); verified declared+attested by `conformance/egress-policy.sh`. If no outbound network, replace this entire line with: N/A — [reason] -->
- Sandbox FS: read-only work-tree mounts ([mechanism]) — enforced: [date]  <!-- Agent FS scoped to the work tree (host secrets unreachable); see docs/operations/containment.md; verified declared+attested by conformance/containment-ready.sh. If not applicable: replace with N/A — [reason] -->
- Scoped tokens: OIDC->role, short TTL ([mechanism]) — enforced: [date]  <!-- Least-privilege, time-boxed credentials -->
- Prod credentials: separate + break-glass ([mechanism]) — enforced: [date]  <!-- Agents never hold prod write creds; SoD -->

**Container / Kubernetes deploy (if applicable):**
- Image: built multi-stage & non-root in CI; pushed to GHCR on merge to `main` with a **digest-bound provenance attestation**.
- Promote the **attested digest** (never a mutable tag) Dev → QA → UAT → Prod; production promotion is human-gated.
- Apply `deploy/k8s/` (or `helm upgrade --install` with `deploy/helm/`); verify liveness/readiness probes pass.
- Rollback: redeploy the previous digest (`kubectl rollout undo deployment/<name>` or re-apply the prior digest).

## 5. Rollback
- Fastest path: [feature-flag off / redeploy previous / revert+redeploy]
- Command: `[rollback command]`
- Every release declares its rollback path before shipping (DEVELOPMENT-PROCESS.md §10).

## 6. Disaster recovery
- **RPO:** [< 24h default] · **RTO:** [< 4h default] — always fill these headline targets (replace the placeholders); for multi-criticality systems also fill the per-tier table below.
- **Per-tier targets (multi-criticality systems, from the BIA — `docs/continuity/BIA.md`):**

  | Tier | RTO | RPO |
  |------|-----|-----|
  | [Critical] | [1h] | [15m] |
  | [Standard] | [4h] | [24h] |

- Backups: [cadence, location] · Restore verified: [date] (recurring-maintenance item — see `docs/continuity/backup-restore-drill.md`)

## 7. Test accounts & credentials
- [account/role] — [location of credentials, e.g. secrets manager path] (never commit secrets)

## 8. Monitoring & alerting
- Error tracking: [tool/link] · Health check: [endpoint] · Alerts: [what fires, to whom]
- **Resilience verification** *(deployable services — see `docs/operations/resilience-verification.md`)*: Load/soak tested: [date] · Fault-injection drill: [date]
- **Observability** *(deployable services — Factor 14 / §3; verified by `conformance/observability-ready.sh`)*: SLOs: [target] · Telemetry wired: [signals]

## 9. Known issues / technical debt
- [issue] — [impact] — [tracking link]

---

**Resume check:** could another engineer or agent take this project cold using only this file + README + the kit docs? If not, fill the gaps.
