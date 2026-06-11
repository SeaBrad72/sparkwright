# Platform Safety Boundary (Org-owned)

**Status:** Org-owned — the kit documents these controls; your platform/security team implements them. They are the REAL boundary. The agent guard (`.claude/hooks/guard.sh`) is a best-effort speed bump in front of them, **not** a substitute.

## Why this exists

The agent guard is a shell-command deny-list. A deny-list over a Turing-complete shell cannot contain a determined or compromised agent: novel tools, language interpreters (`python -c`, `node -e`), and obfuscation defeat pattern-matching, and data exfiltration has no reliable command signature. The same interpreters can even **defeat the guard's own self-protection** (delete or rewrite `guard.sh`), so that protection is best-effort, not absolute. The controls below are where *"agents (or humans) cannot cause damage"* is actually enforced.

This is not a hypothetical. An adversarial red-team of the guard (2026-06-09) confirmed that, before hardening, ~16% of irreversible/exfiltration payloads were caught; even hardened, a deny-list has a permanent bypass tail. Treat the guard as accident-prevention and these four controls as the boundary.

## The four controls

1. **Network-egress allowlist — the only real exfiltration defense.** Default-deny outbound network from agent and developer environments; allow only known package registries and required APIs. Without this, any interpreter can exfiltrate secrets or data regardless of what the guard blocks.
2. **Separate production credentials.** Agents and developer sessions never hold production write credentials. Production access is brokered through an approval / break-glass workflow with audit logging. A leaked dev token must not be able to touch prod.
3. **Read-only / sandboxed filesystem.** Agent workspaces are scoped to the project working tree and cannot read host secrets, other projects, `~/.aws`, or `~/.ssh`. Prefer ephemeral containers with read-only mounts for everything outside the working tree.
4. **Scoped, short-lived tokens.** Least-privilege, time-boxed credentials for every integration; no long-lived broad-scope tokens within agent reach.

## Relationship to the guard

| Layer | What it is | What it catches |
|-------|-----------|-----------------|
| Agent guard (`.claude/hooks/guard.sh`) | Best-effort speed bump | Honest accidental destructive commands; common irreversible verbs; protects its own integrity · un-allowlisted destructive/egress MCP tool calls (by name — see `../operations/runtime-guards.md`) |
| **Platform boundary (this doc)** | The real control | A determined / compromised agent, exfiltration, prod blast radius, lateral access |

Adopt both. The guard reduces accidents cheaply and immediately; the platform boundary is what you certify to an auditor. Neither replaces the other.

## Human and other-runtime coverage

The guard's PreToolUse hook governs the Claude Code runtime. Its deny-matrix is **reused across runtimes** (`../operations/runtime-guards.md`): a universal git `pre-push` hook covers force-push / push-to-main for **any** git client and humans, and a `kit-guard` CLI lets any other runtime check a proposed command against the same matrix. These widen the speed bump — they are **not** a boundary: `--no-verify`, an uncooperative runtime, or a language interpreter still bypasses them, which is why the boundary must live at the platform. See the runtime-coverage note in [README.md](README.md) and the §13 enforcement model in `DEVELOPMENT-PROCESS.md`.
