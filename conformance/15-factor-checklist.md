# Conformance Check — 15-Factor Architecture

Proves a service satisfies the applicable factors of `DEVELOPMENT-STANDARDS.md` §13. **Checklist-type**, run at the **Review gate** (`DEVELOPMENT-PROCESS.md` §7). Conditional: deployment-architecture factors are marked **N/A with a one-line reason** for non-service projects (CLI, batch, library).

## How to use
Copy this file into your project (or your review record). For each factor: mark **Applies? (Y / N+reason)** and give **Evidence** (where/how it's met). The reviewer signs off only when every applicable factor has evidence.

## Checklist (blank)

| # | Factor | Applies? | Evidence (where/how met) |
|---|--------|----------|--------------------------|
| 1 | Codebase — one app, version-controlled, one repo | | |
| 2 | API-first — contract defined before implementation | | |
| 3 | Dependencies — declared & isolated; lockfile committed; pinned for prod | | |
| 4 | Build, release, run — strictly separated stages | | |
| 5 | Config — in the environment; code/config/credentials separated | | |
| 6 | Logs — emitted as event streams, not managed files | | |
| 7 | Disposability — fast startup, graceful shutdown | | |
| 8 | Backing services — attached resources, swappable by config | | |
| 9 | Dev/prod parity — environments kept as similar as possible | | |
| 10 | Admin processes — one-off/admin tasks run as first-class processes | | |
| 11 | Port binding — service is self-contained, exports via a port | | |
| 12 | Stateless processes — no sticky local state between requests | | |
| 13 | Concurrency — scale out via the process model | | |
| 14 | Telemetry — metrics, traces, and health, not just logs | | |
| 15 | AuthN/Z — identity and least-privilege authorization enforced | | |

## Worked example — TypeScript/Node reference profile (a deployable HTTP service)

| # | Factor | Applies? | Evidence |
|---|--------|----------|----------|
| 1 | Codebase | Y | one Git repo per service; `main` protected |
| 2 | API-first | Y | OpenAPI/Zod-typed route contracts defined before handlers |
| 3 | Dependencies | Y | `package-lock.json` committed; exact versions for prod (profile §1) |
| 4 | Build/release/run | Y | `tsc`/`next build` → deploy → `start`; CI separates them (profile §3–4) |
| 5 | Config | Y | `process.env` + fail-fast; `.env.local` gitignored; `.env.example` committed (profile §5) |
| 6 | Logs | Y | pino/winston JSON to stdout (profile §7) |
| 7 | Disposability | Y | handle SIGTERM; drain in-flight; idempotent retries (standards §4) |
| 8 | Backing services | Y | Postgres via `DATABASE_URL`; swappable without code change (profile §8) |
| 9 | Dev/prod parity | Y | Docker/devcontainer mirrors prod; same Postgres engine |
| 10 | Admin processes | Y | Prisma `migrate deploy`; one-off scripts via `node` (profile §8) |
| 11 | Port binding | Y | Express/Next binds `process.env.PORT` |
| 12 | Stateless | Y | no in-memory session; state in Postgres/Redis |
| 13 | Concurrency | Y | horizontal scale on the host; stateless processes permit it |
| 14 | Telemetry | Y | Sentry errors + health endpoint; metrics/traces wired (standards §3) |
| 15 | AuthN/Z | Y | bcrypt + JWT least-privilege; server-side authz on protected routes (profile §5) |

> A CLI tool would mark 11, 12, 13 **N/A — not a long-running networked service**, and still satisfy 1–10, 14, 15.
