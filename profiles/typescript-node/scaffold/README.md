# app — TypeScript/Node starter scaffold

A minimal service that satisfies the TypeScript/Node profile's CI language pipeline
(`profiles/typescript-node/ci.yml`) on an empty repo, plus a `/healthz` → 200 surface and
its test.

> Incept-copied starter — **brownfield-safe**: `incept` copies these files into a fresh repo
> only (never over existing source).

## Lockfile ships — clone-green

`gate-install` runs `npm ci`, which requires a committed `package-lock.json`. This scaffold
**ships one**, so the pipeline is green on clone with no extra step. Refresh it with `npm install`
when you change dependencies.

## Layout

| File                | Role                                                                |
|---------------------|---------------------------------------------------------------------|
| `package.json`      | scripts: `lint` · `type-check` · `test:coverage` · `build` (+`eval`).|
| `tsconfig.json`     | strict type-check config (src + test).                              |
| `tsconfig.build.json`| emit config for `build` (src only).                                |
| `eslint.config.js`  | ESLint 9 flat config (JS + typescript-eslint recommended).          |
| `vitest.config.ts`  | v8 coverage, ≥80% thresholds; excludes `src/server.ts`.             |
| `src/health.ts`     | pure `health()` — the unit-tested logic.                            |
| `src/server.ts`     | node:http server exposing `/healthz` (main-guarded; coverage-excluded).|
| `test/health.test.ts`| vitest test on `health()`.                                         |

## See it run

```sh
npm ci
npm run dev            # starts the server on :3000 (tsx)
# in another terminal:
curl localhost:3000/healthz     # -> {"status":"ok"}
```
Or the built artifact: `npm run build && npm start`.

## Commands (match `profiles/typescript-node/ci.yml`)

```sh
npm ci               # gate-install
npm run lint         # gate-lint   (eslint)
npm run type-check   # gate-type-check (tsc --noEmit)
npm run test:coverage# gate-test   (vitest, >=80% coverage)
npm run build        # gate-build  (tsc)
```

## Verification status

> **Authored to the `profiles/typescript-node/ci.yml` contract; its npm steps (install → lint →
> type-check → test+coverage → build) were run green locally** before shipping. The workflow file
> itself is statically validated (`actionlint`); the full pipeline runs end-to-end on your first
> push to GitHub.

On first push the scaffold also passes the other unconditional gates — **secret-scan** (gitleaks),
**dep-scan** (`npm audit --omit=dev`), **SBOM** (CycloneDX), **SAST** (semgrep), and **license** —
not just the five language gates. **Only** the container-image gates (`docker build`, image
SBOM/provenance) wait: they're conditional on a `Dockerfile` (the profile's `Dockerfile` is a
COPY-&-ADAPT reference) and skip until you adapt one in.
