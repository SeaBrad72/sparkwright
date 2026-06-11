# Runtime Guards — Portability Reference

How the kit's destructive-action deny-matrix protects **more than the Claude Code runtime**. One matrix (`/.claude/hooks/guard-core.sh`), three surfaces. The executable half of `DEVELOPMENT-PROCESS.md` §13 for non-Claude runtimes and humans.

> **Principle — one matrix, many surfaces; still a speed bump.** The deny-matrix is the single source of truth; each surface reuses it. None of them is a security boundary — `--no-verify`, a runtime that never calls `kit-guard`, or an interpreter still bypasses it. The real boundary is platform-owned (`../enterprise/platform-safety-boundary.md`).

## The one matrix
`/.claude/hooks/guard-core.sh` exposes three pure functions — each prints a `13: …` reason and returns 1 on deny, 0 on allow:
- `guard_check_command "<cmd>"` — the destructive-command matrix (rm, dd, SQL/DDL, migration resets, cloud/cluster destruction, prod-context, exfil, control-plane).
- `guard_check_path "<file>"` — secret-material + control-plane write protection.
- `guard_check_push <remote-ref> <local-sha> <remote-sha>` — force-push / push-to-main, from real refs.
- `guard_check_mcp "<tool>" "<allowlist>" "<overrides>"` — the MCP capability gate (Slice 11a): classifies an `mcp__<server>__<action>` tool by its action verb and denies un-allowlisted destructive/egress capabilities (fail-closed). Pure — the adapter loads `.claude/mcp-policy.json` and passes it in.

`conformance/guard-core-sourced.sh` asserts every consumer sources this file (no forked matrix).

## The three surfaces
| Surface | File | Covers | Cooperation |
|---------|------|--------|-------------|
| Claude Code | `.claude/hooks/guard.sh` (PreToolUse) | command + path + MCP-tool (`mcp__.*`) | automatic in Claude Code |
| Any git client | `hooks/pre-push` → `.git/hooks/pre-push` | git-history (force-push, push-to-main) | none — every runtime + humans |
| Any other runtime | `scripts/kit-guard` CLI | full command + path matrix | runtime pipes commands through it |

### Wiring a non-Claude runtime
Pipe each proposed shell command through the CLI before running it:
```sh
kit-guard cmd "$PROPOSED_COMMAND" || { echo "blocked by kit guard"; exit 1; }
```
**Treat any non-zero exit as block** — `1` = denied, `2` = core not found / usage error. The `||` form above does this correctly; do **not** key only on `-eq 1`, or a missing core (exit 2) would be mis-read as "not denied." `kit-guard` resolves the core relative to itself, or via `KIT_GUARD_CORE=/path/to/guard-core.sh`. Examples:
- **Cursor / Aider / Continue:** they already inherit the universal `pre-push` hook; for command coverage, wire `kit-guard` into the runtime's pre-command step where one exists. A first-party plugin per runtime is intentionally not shipped (build on demand).
- **CI bots / scripts:** call `kit-guard cmd …` before executing a templated command.

### Git pre-push
Installed by `incept.sh` by default (brownfield-safe; never clobbers an existing hook). Blocks force-push and push-to-main locally, before the network round-trip — complementing remote branch protection, and covering remotes that have none. Deliberate override: `git push --no-verify`.

## Windows
The hooks are POSIX `sh`. On Windows, run them under **WSL or Git-Bash**, where they work unchanged. The matrix is **not** ported to PowerShell/cmd — a second implementation would fork the single source of truth and double the red-team burden.

## MCP capability gate (the mcp-policy contract)

The guard sees MCP tool calls too (Claude PreToolUse matcher `mcp__.*`). `guard_check_mcp` (in `guard-core.sh`) classifies each `mcp__<server>__<action>` by **tokenizing the action** (camelCase→snake, lowercased) and matching whole tokens against verb sets — then **denies un-allowlisted destructive/egress capabilities by default** (fail-closed):
- first token is a **read-only** verb (`read/get/list/search/query/fetch/describe/show/view/find/count`) → allow;
- **any** token is a **destructive/egress** verb (`delete/drop/create/update/write/upload/publish/deploy/send/post/email/apply/merge/push/revoke/rotate/export/download…`) → deny, naming the class. This wins over a read prefix, so `get_and_delete` and `fetchAndExport` deny, while legit read compounds stay allowed because the noun is not the verb (`list_deployments`≠`deploy`, `get_updates`≠`update`);
- anything else (no read-verb lead, no destructive token — including non-verb lookalikes like `getter`/`counter`) → **deny (fail-closed)**.

**Policy** (`.claude/mcp-policy.json`, control-plane-protected): `{ "allow": ["mcp__server__action" | "mcp__server__*"], "classOverride": { "mcp__x__export": "read" } }`. Shipped empty — a project allowlists what it needs. **Prefer exact-tool allows over `mcp__server__*` wildcards** — a wildcard admits *every* tool on that server, destructive ones included, bypassing classification. **Portable:** any runtime calls `kit-guard mcp "<tool>" [policy]` to apply the same gate. `conformance/mcp-policy.sh` is the classification corpus **and** asserts the matcher is wired (no green-while-dark).

**Honest ceiling:** this gates *what the tool name reveals*. A deliberately renamed action (a `get_data` that exfiltrates), a server wildcard you granted, or a server hiding capability behind a read-looking name is **not** caught; and the egress class is a **name-match speed bump, not egress containment** — real exfiltration defense is the platform network-egress allowlist (`../enterprise/platform-safety-boundary.md`).

## Coverage depth (honest ceiling)
The `pre-push` hook enforces only the git-history denials (all a git hook can see); `kit-guard` covers the full matrix but needs the runtime to call it. The future upgrade for *automatic* full-matrix coverage off-Claude — any runtime and humans, no integration — is a `kit-guard install-shims` mode (PATH-shims that wrap the dangerous binaries and call `kit-guard` before `exec`). It is just another consumer of the same core, but invasive enough to earn its own opt-in slice. Named here so the ceiling is honest.

## Honesty boundary
Each surface is a speed bump for honest mistakes, not containment of a hostile process. `--no-verify`, an uncooperative runtime, or a language interpreter (`python -c`) bypasses it. Adopt it **with** the platform boundary (network-egress allowlist, separate prod credentials, sandboxed FS, scoped tokens) — `../enterprise/platform-safety-boundary.md`.

## See also
- `DEVELOPMENT-PROCESS.md` §13 (autonomy matrix) · `conformance/agent-autonomy.sh` (the red-team corpus).
- `docs/operations/ci-platforms.md` — the analogous "one contract, many platforms" pattern for CI.
