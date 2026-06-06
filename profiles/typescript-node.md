# Stack Profile — TypeScript / Node.js

> Reference profile. The concrete *how* for the universal `DEVELOPMENT-STANDARDS.md` on a TypeScript/Node stack. Copy/adapt per project; record selection as ADR-000.

**Stack:** TypeScript (strict) · Node.js · Express or Next.js · PostgreSQL + Prisma · Vitest · hosted (Vercel/Railway/container)
**Status:** reference

---

## 1. Toolchain
- **Runtime:** Node.js 24 LTS · **Language:** TypeScript (strict mode)
- **Package manager:** npm (lockfile committed; exact versions for production apps)
- **Format/lint/types:** Prettier · ESLint (`@typescript-eslint`) · `tsc --noEmit`
- **Tests:** Vitest (+ v8 coverage) · Playwright for e2e
- **Build:** `tsc` (services) or `next build` (Next.js apps)

## 2. Project scaffold
```
src/{models,services,controllers,routes,middleware,lib,types}/
tests/{unit,integration,e2e}/
docs/architecture/            # ADRs (incl. ADR-000)
.github/workflows/ci.yml
.env.example · .gitignore · tsconfig.json · .eslintrc.json · .prettierrc · vitest.config.ts
```
Baselines: `tsconfig` with `"strict": true`; ESLint extends `eslint:recommended` + `plugin:@typescript-eslint/recommended` with `no-console: warn`, `@typescript-eslint/no-explicit-any: error`; Vitest coverage thresholds set to 80.

## 3. Standard commands
```
install:       npm ci
dev:           npm run dev
test:          vitest
test:coverage: vitest --coverage
lint:          eslint "src/**/*.{ts,tsx}"
type-check:    tsc --noEmit
build:         tsc            # or: next build
start:         node dist/server.js   # or: next start
```

## 4. CI/CD pipeline
Implements the 7 required gates of `DEVELOPMENT-STANDARDS.md` §14. Drop-in reference files live in **`profiles/typescript-node/`**:
- **`ci.yml`** → copy to `.github/workflows/ci.yml`. GitHub Actions on push/PR to `main`: `npm ci` → lint → type-check → test+coverage(≥80) → build → secret-scan (gitleaks) → dependency scan (`npm audit --audit-level=high`) → SBOM (CycloneDX) → build provenance (`actions/attest-build-provenance`). All green required to merge.
- **`CODEOWNERS`** → copy to `.github/CODEOWNERS`; routes review so builder ≠ sole reviewer.
- **`BRANCH-PROTECTION.md`** → how to protect `main` (required check, required review).

Conformance: `sh conformance/ci-gates.sh profiles/typescript-node/ci.yml` asserts every gate is present.

## 5. Security implementation
- **Env/secrets:** `process.env.X` with a fail-fast check; never hardcode. `.env.local` gitignored.
- **Validation:** **Zod** schemas at every boundary (`Schema.parse(input)`); validate on create *and* update.
- **Injection-safe data:** **Prisma** (or parameterized `$1` queries). Never template-string SQL.
- **AuthN/Z:** **bcrypt** (≥12 rounds) for passwords; **jsonwebtoken** with minimal claims + short expiry; verify on protected routes.
- **HTTP headers / XSS / CSRF:** **helmet**; React auto-escapes (use `textContent`, not `innerHTML`, in vanilla); CSRF tokens for cookie-auth forms.
- **Rate limiting:** `express-rate-limit` (skip in test mode).

## 6. Testing
- **Convention:** `*.test.ts` next to source or under `tests/`. Arrange-Act-Assert. `describe` behavior, not implementation.
- **Integration:** `supertest` against the app; assert status + body + DB state.
- **E2E:** Playwright against the dev server.
- **AI evals:** a `evals/` dir with JSONL datasets; an eval runner that scores against a rubric (LLM-as-judge via the Anthropic SDK, pinned judge model) and throws below threshold in CI.

## 7. Resilience & observability
- **Retry/backoff:** small helper or `p-retry`; **circuit breaker:** `opossum` for flaky upstreams.
- **Logging:** **pino** or **winston**, JSON in prod. **Error tracking:** Sentry (`@sentry/node`), source maps uploaded.

## 8. Data & migrations
- **Prisma migrate** (`migrate dev` locally, `migrate deploy` in CI/CD). Expand-contract: add column/table → backfill (batched) → switch reads → drop old in a later migration. Every migration reversible; no manual prod DDL.

## 9. Release & deploy
- **Deploy:** Vercel (apps) / Railway or container (services); merge to `main` → auto-deploy.
- **Feature flags:** a flag service or env-backed flags; flag-off = fastest rollback.
- **Rollout:** staging → production; **rollback:** redeploy previous deployment (Vercel/Railway one-click) or revert + redeploy.

## 10. Recommended libraries
Zod (validation) · Prisma (ORM) · bcrypt + jsonwebtoken (auth) · helmet + express-rate-limit (HTTP security) · pino/winston (logging) · Sentry (errors) · Vitest + Playwright + supertest (testing) · Anthropic SDK (`@anthropic-ai/sdk`) for AI features. Default Claude models: `claude-sonnet-4-6` (workhorse), escalate to Opus for hard reasoning.

## 11. Stack-specific gotchas
- Audit every non-null assertion (`!`) — prefer a runtime guard.
- `npm ci` (not `install`) in CI for reproducible installs.
- Prisma client must be regenerated after schema changes (`prisma generate`).
- Keep `tsconfig` strict; don't silence errors with `any` (lint blocks it).

---

**Last Updated:** 2026-06-04
