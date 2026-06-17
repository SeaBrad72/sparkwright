# adapters/

One subdirectory per harness. Each holds:
- `adapter.json` — the declarative manifest (schema in [`docs/operations/harness-adapters.md`](../docs/operations/harness-adapters.md))
- `README.md` — harness-specific notes

## What an adapter is

An adapter is a thin, harness-native binding that *references* the repo's universal governance layer. It declares which dimensions the harness covers natively, which stay at the floor, and where conformance checks live. It does **not** copy or fork any policy or process.

## Reference adapter

`adapters/claude-code/` is the reference adapter. It references the live `.claude/` governance layer in this repo — the files there are **not** duplicated here.

## Contract

The adapter boundary contract — the 5-dimension table, manifest schema, and conformance rules — is in `docs/operations/harness-adapters.md`.

## Roadmap

The `generic` adapter (floor-only, any runtime) and `incept --harness` scaffolding arrive in N3.
