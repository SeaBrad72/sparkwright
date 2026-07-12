# adapters/generic/

Floor-only adapter for any harness that reads `AGENTS.md` but provides no inline pre-exec guard — Codex, Cursor, Copilot, and similar runtimes.

## What this adapter declares

Every dimension is at the Kit-enforced **floor**; `mcp-gate` is `n-a` (no MCP surface):

| Dimension | Level | Enforced by |
|-----------|-------|-------------|
| context-binding | floor | `AGENTS.md` present + routes to canonical docs |
| command-guard | floor | `hooks/pre-push` + `scripts/kit-guard` + `conformance/agent-boundary.sh` |
| history-protection | floor | `hooks/pre-push` (force-push / push-to-main guard) |
| review-roles | floor | `conformance/agent-boundary.sh` + `conformance/branch-protection.sh` |
| mcp-gate | n-a | No MCP surface on this harness |

## What "floor-only" means

Enforcement holds entirely through the universal governance layer — the git hook and CI backstop — without any harness-native inline interception. The `pre-push` hook and `kit-guard` CLI fire regardless of which AI runtime issued the command; the CI `agent-boundary` gate backstops any local bypass.

Inline pre-exec interception (e.g. the Claude Code `PreToolUse` hook) is simply absent here. That is an honest ceiling, not a gap: the floor is the equal-enforcement guarantee every harness must clear.

## Coverage ceiling

For the full matrix of what each surface covers and where the ceiling is, see:

- [`docs/operations/harness-adapters.md`](../../docs/operations/harness-adapters.md) — boundary contract + dimension table
- [`docs/operations/runtime-guards.md`](../../docs/operations/runtime-guards.md) — per-harness guard coverage matrix
