# Ephemeral / Preview Environments

A **per-PR throwaway environment** so reviewers exercise a change *running*, not just read the diff — accelerating Review/Acceptance. Stack-neutral; the tool (Vercel/Netlify previews · Argo/Helm-per-PR · Heroku review apps · a namespace-per-PR) is a project choice. Pairs with the env model (`DEVELOPMENT-PROCESS.md` §9).

## Lifecycle
1. **Open PR** → deploy an isolated environment (namespace / DB / URL per PR).
2. **Reviewers exercise it** → the running change, with safe data.
3. **Merge / close** → **auto-teardown** (no orphaned environments).

## Security guardrails (the kit's value-add)
- **Safe data only** — seed with synthetic/masked test data (`test-data-management.md`); **never prod data** in a preview.
- **Scoped, short-lived credentials** — per-PR, least-privilege, auto-expiring (ties to containment / scoped tokens); **no prod secrets** in a preview.
- **TTL + auto-teardown** — a preview that outlives its PR is forgotten attack surface; enforce a TTL and tear down on merge/close.
- **Isolation** — one PR's preview cannot reach another's data or prod.

## What the readiness check proves — and doesn't
`conformance/preview-env-ready.sh` confirms a deployable project **records** its preview-env approach (RUNBOOK §4). It does **not** verify envs actually spin up, tear down, isolate, or exclude prod data — those are **Manual** operator rows (`preview-environments-readiness.md`). Necessary, not sufficient. Recommended, not required — a tiny tool may mark it N/A-with-reason.
