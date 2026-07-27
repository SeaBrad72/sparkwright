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

This scaffolds `adapters/<harness>/{adapter.json,README.md}` from the `adapters/_TEMPLATE/` skeleton — floor-only, conforms immediately. Customize `controlPlanePaths` for the harness's namespace, point `contextFile` at the document that harness actually auto-loads (the scaffold ships `AGENTS.md`), and upgrade any dimension to `"native"` with a `proof` when the harness supports inline interception. Validate with:

```sh
sh conformance/harness-adapter.sh adapters/<harness>
```

This is the same guided, validated workflow that `scripts/new-profile.sh` provides for stacks.

## Contract

The adapter boundary contract — the 7-dimension table, manifest schema, and conformance rules — is in `docs/operations/harness-adapters.md`. The dimension set is **closed**: a manifest key outside the seven is a FAIL, because the Kit enforces no floor for it.

`contextFile` is a **required** top-level field naming the document that harness auto-loads (`claude-code` → `CLAUDE.md`; the rest → `AGENTS.md`). An **absent** `contextFile` is a FAIL, never a default — a default would silently rebind every future adapter to a file its harness may never read. The value is boundary-validated: bare relative path; no empty, `.` or `.git` component; no symlink; a regular file; and tracked wherever the repo has a populated index (git absent or no repo is UNVERIFIED, never a pass). The entry contract (§1) must be **byte-identical in every adapter's declared `contextFile`** — enforced by `conformance/agents-brief.sh`, which compares the first `## ` section of every declared document byte for byte (a marker-grep would be satisfied by keeping the heading and appending underneath it). The invariant is per-adapter and the set is derived from the manifests, so adding a harness costs exactly: declare `contextFile`, put §1 in it, and add nothing between §1 and the next `## `. Full rules + the `cursor` / `gemini` residuals: `docs/operations/harness-adapters.md`.
