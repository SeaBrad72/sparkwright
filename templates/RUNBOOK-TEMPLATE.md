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

## 3. Environment variables
Documented in `.env.example` (committed, placeholders only). Required:
- `[VAR]` — [purpose] — [where to obtain]

## 4. Deploy
- Target: [Vercel / Railway / container / …]
- Trigger: [merge to main → auto-deploy / manual]
- Steps: `[deploy command(s)]`

## 5. Rollback
- Fastest path: [feature-flag off / redeploy previous / revert+redeploy]
- Command: `[rollback command]`
- Every release declares its rollback path before shipping (DEVELOPMENT-PROCESS.md §10).

## 6. Disaster recovery
- **RPO:** [< 24h default] · **RTO:** [< 4h default]
- Backups: [cadence, location] · Restore verified: [date] (recurring-maintenance item)

## 7. Test accounts & credentials
- [account/role] — [location of credentials, e.g. secrets manager path] (never commit secrets)

## 8. Monitoring & alerting
- Error tracking: [tool/link] · Health check: [endpoint] · Alerts: [what fires, to whom]

## 9. Known issues / technical debt
- [issue] — [impact] — [tracking link]

---

**Resume check:** could another engineer or agent take this project cold using only this file + README + the kit docs? If not, fill the gaps.
