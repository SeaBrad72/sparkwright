# adapters/claude-code/

This adapter declares Claude Code's binding to the universal governance layer. It points at the live `.claude/` directory in this repo — nothing is duplicated here.

## What lives where

| Source | What it provides |
|--------|-----------------|
| `.claude/hooks/guard.sh` | PreToolUse hook — inline command + path + MCP interception |
| `.claude/hooks/guard-core.sh` | The one deny-matrix (consumed by all surfaces) |
| `.claude/settings.json` | Claude Code context-binding rules + control-plane config |
| `.claude/mcp-policy.json` | MCP capability allowlist |
| `.claude/agents/reviewer.md` | Native reviewer subagent |
| `.claude/agents/security-reviewer.md` | Native security-reviewer subagent |

## Dimension coverage

| Dimension | Level | Why |
|-----------|-------|-----|
| `context-binding` | **native** | `CLAUDE.md` + `.claude/settings.json` bind context directly in the Claude Code runtime |
| `command-guard` | **native** | `PreToolUse` hook (`guard.sh`) intercepts every tool call before execution |
| `history-protection` | **floor** | Universal `pre-push` hook covers this; Claude Code has no git-push surface to add to |
| `review-roles` | **native** | Dedicated subagents (`reviewer.md`, `security-reviewer.md`) enforce builder ≠ reviewer |
| `mcp-gate` | **native** | `guard_check_mcp` + `mcp-policy.json` gate MCP tool calls inline |

## See also

- `../../.claude/README.md` — the governance layer this adapter points at
- `../../docs/operations/harness-adapters.md` — the boundary contract (5-dimension table, manifest schema, conformance rules)
