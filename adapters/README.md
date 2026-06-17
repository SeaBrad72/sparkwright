# adapters/

One subdirectory per harness. Each holds:
- `adapter.json` — the declarative manifest (schema in [`docs/operations/harness-adapters.md`](../docs/operations/harness-adapters.md))
- `README.md` — harness-specific notes

## What an adapter is

An adapter is a thin, harness-native binding that *references* the repo's universal governance layer. It declares which dimensions the harness covers natively, which stay at the floor, and where conformance checks live. It does **not** copy or fork any policy or process.

## Adapters

| Adapter | Description |
|---------|-------------|
| `adapters/claude-code/` | Reference adapter — Claude Code with native hooks, MCP policy, and subagents. |
| `adapters/generic/` | Floor-only adapter for any AGENTS.md-reading harness with no inline guard (Codex, Cursor, Copilot, …). |

`incept --harness <list>` (default `claude-code`) selects which adapter(s) a project targets and runs the conformance check for each.

## Reference adapter

`adapters/claude-code/` is the reference adapter. It references the live `.claude/` governance layer in this repo — the files there are **not** duplicated here.

## BYO — adding a new harness

Any harness is supported. Run:

```sh
sh scripts/new-adapter.sh <harness-name>
```

This scaffolds `adapters/<harness>/{adapter.json,README.md}` from the `adapters/_TEMPLATE/` skeleton — floor-only, conforms immediately. Customize `controlPlanePaths` for the harness's namespace and upgrade any dimension to `"native"` with a `proof` when the harness supports inline interception. Validate with:

```sh
sh conformance/harness-adapter.sh adapters/<harness>
```

This is the same guided, validated workflow that `scripts/new-profile.sh` provides for stacks.

## Contract

The adapter boundary contract — the 5-dimension table, manifest schema, and conformance rules — is in `docs/operations/harness-adapters.md`.
