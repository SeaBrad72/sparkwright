# Platform Safety Boundary (Org-owned)

**Status:** Org-owned — the kit documents these controls; your platform/security team implements them. They are the REAL boundary. The agent guard (`.claude/hooks/guard.sh`) is a best-effort speed bump in front of them, **not** a substitute.

## Why this exists

The agent guard is a shell-command deny-list. A deny-list over a Turing-complete shell cannot contain a determined or compromised agent: novel tools, language interpreters (`python -c`, `node -e`), and obfuscation defeat pattern-matching, and data exfiltration has no reliable command signature. The same interpreters can even **defeat the guard's own self-protection** (delete or rewrite `guard.sh`), so that protection is best-effort, not absolute. The controls below are where *"agents (or humans) cannot cause damage"* is actually enforced.

This is not a hypothetical. An adversarial red-team of the guard (2026-06-09) confirmed that, before hardening, ~16% of irreversible/exfiltration payloads were caught; even hardened, a deny-list has a permanent bypass tail. Treat the guard as accident-prevention and these four controls as the boundary.

## The four controls

1. **Network-egress allowlist — the only real exfiltration defense.** Default-deny outbound network from agent and developer environments; allow only known package registries and required APIs. Without this, any interpreter can exfiltrate secrets or data regardless of what the guard blocks. The kit now ships a default-deny reference (docs/operations/egress-control.md) and verifies it is declared + attested (conformance/egress-policy.sh) — enforcement remains platform-owned.
2. **Separate production credentials.** Agents and developer sessions never hold production write credentials. Production access is brokered through an approval / break-glass workflow with audit logging. A leaked dev token must not be able to touch prod. The kit now ships a reference (docs/operations/containment.md) and verifies this is declared + attested (conformance/containment-ready.sh) — enforcement remains platform-owned.
3. **Read-only / sandboxed filesystem.** Agent workspaces are scoped to the project working tree and cannot read host secrets, other projects, `~/.aws`, or `~/.ssh`. Prefer ephemeral containers with read-only mounts for everything outside the working tree. The kit now ships a reference (docs/operations/containment.md) and verifies this is declared + attested (conformance/containment-ready.sh) — enforcement remains platform-owned.
4. **Scoped, short-lived tokens.** Least-privilege, time-boxed credentials for every integration; no long-lived broad-scope tokens within agent reach. The kit now ships a reference (docs/operations/containment.md) and verifies this is declared + attested (conformance/containment-ready.sh) — enforcement remains platform-owned.

## What the kit now provides (Slices 11a–11c)

The boundary above stays **platform-owned and platform-enforced** — but the kit no longer only *documents* it:
- **Kit-enforced (one surface):** the agent guard now gates **MCP tool capabilities** in-process — `guard_check_mcp` denies un-allowlisted destructive/egress MCP calls deny-by-default (Slice 11a). This is real enforcement *for MCP tool names*; it does **not** contain a renamed action, an interpreter, or in-server egress — the `net.egress` class is a name-match speed bump.
- **Kit-assisted (the four controls):** for the network-egress allowlist (#1), sandboxed filesystem (#3), scoped tokens (#4), and separate prod credentials (#2), the kit now ships a copy-pasteable reference and a three-state conformance check that the control is **declared + attested-wired** (`conformance/egress-policy.sh`, `conformance/containment-ready.sh`). The **host still enforces** — the kit verifies the posture is wired, not that a packet is dropped or a mount is read-only.

Net: the shell/interpreter deny-list is still a **speed bump**; one narrow surface (MCP capability) is now Kit-enforced; the four platform controls moved Org-owned → **Kit-assisted**. Per-row detail: [compliance-crosswalk.md](compliance-crosswalk.md); verified by `conformance/assurance-tiers.sh`.

## Relationship to the guard

| Layer | What it is | What it catches |
|-------|-----------|-----------------|
| Agent guard (`.claude/hooks/guard.sh`) | Best-effort speed bump | Honest accidental destructive commands; common irreversible verbs; protects its own integrity · un-allowlisted destructive/egress MCP tool calls (by name — see `../operations/runtime-guards.md`) |
| **Platform boundary (this doc)** | The real control | A determined / compromised agent, exfiltration, prod blast radius, lateral access |

Adopt both. The guard reduces accidents cheaply and immediately; the platform boundary is what you certify to an auditor. Neither replaces the other.

## The agent's OS sandbox, and the managed-settings tier

Claude Code's OS sandbox is **off** in the shipped `.claude/settings.json`; it is an opt-in **strict profile** (`GUARD-CP-READONLY-SANDBOX`, shipped as `templates/sandbox-strict.settings.local.json`; detail in [`../operations/runtime-guards.md`](../operations/runtime-guards.md), "Below the text layer: the strict profile (opt-in)"). Under the strict profile it keeps the agent's own enforcement layer (`.claude/`, `hooks/`, `.kit/`, the git hook and config files, the global git config and shell rc files) read-only to the agent's shell, at the cost of one terminal git command per update that changes a guard file. The shipped file carries no `sandbox` key. **The full loss in the default:** the agent's Bash, limited only by the text guard, can write the repo enforcement layer (`.claude/` including `settings.local.json`, `hooks/`, `.kit/`, `.git/hooks`, `.git/config`, `.mcp.json`), the home git config and shell startup files (`~/.gitconfig`, `~/.config/git`, `~/.zshrc`, `~/.zshenv`, `~/.zprofile`, `~/.bashrc`, `~/.bash_profile`, `~/.profile`), Claude Code's user-level config under `~/.claude`, any user-writable path outside the project and temp roots, and any unix socket. Files outside the tracked tree never reach a PR; code planted in them runs later as the human, with the human's forge credentials. The forge controls (branch protection with admin enforcement, a non-author Approve, a GO bound to a commit, CI) bind identities, not that code; this is the kit's position before v3.234.0. The editor-tool denies cover the Edit and Write tools only. For unattended or enterprise use, run the strict profile or the managed-settings tier below. The strict profile is **kit-enforced for Claude Code only**, it leaves the network open, and a human who owns the project can edit project-scoped settings, so it does not replace control #3 (a sandboxed filesystem, platform-owned) or control #1 (egress).

**The hardening tier (org-owned).** Claude Code reads *managed settings* that an administrator installs on the machine (a root-owned file such as `/Library/Application Support/ClaudeCode/managed-settings.json` on macOS or `/etc/claude-code/managed-settings.json` on Linux), and a project's settings cannot loosen them. Put the same `sandbox` block there, with `allowUnsandboxedCommands: false` and `failIfUnavailable: true` if you want a machine where the sandbox cannot start to refuse to run an agent at all, and the protection no longer depends on the project's own file. This is per machine and needs root, so the kit documents it and does not ship it.

## Human and other-runtime coverage

The guard's PreToolUse hook governs the Claude Code runtime. Its deny-matrix is **reused across runtimes** (`../operations/runtime-guards.md`): a universal git `pre-push` hook covers force-push / push-to-main for **any** git client and humans, and a `kit-guard` CLI lets any other runtime check a proposed command against the same matrix. These widen the speed bump — they are **not** a boundary: `--no-verify`, an uncooperative runtime, or a language interpreter still bypasses them, which is why the boundary must live at the platform. And a hook that was never installed in *this* working copy is not a reduced speed bump — it is none at all: `git clone` copies neither `.git/hooks/` nor `.git/config`, so every fresh clone starts in that state, and `scripts/preflight.sh` refuses on it rather than letting it pass silently. See the runtime-coverage note in [README.md](README.md) and the §13 enforcement model in `DEVELOPMENT-PROCESS.md`.

## The kit's own development environment — a declared residual (2026-08-15)

Control #1 scopes itself to *agent and developer environments*, and the kit's own development
environment is the maximally open case of that scope: the maintainer's machine runs the agent with
machine-global network allows (`curl`, web fetch/search) under an autonomous permission mode — no
egress allowlist binds it. The kit's honesty tiers demand this be **declared**, not quiet:

- **The residual:** agent-reachable outbound network on the maintainer machine is unconstrained by
  any platform control. The guard's input-side matchers deny secret-*targeting* reads, and the
  directory-sweep residual of its content tools is already disclosed; neither is an egress control.
- **Compensating controls (the first owner-attested, the rest checkable):** no production
  credentials sit within agent reach on that machine (an attestation, not an agent-checkable
  fact); secret material is never committed — `.gitignore` carries the secret patterns (added
  2026-08-15, when a review measured this very sentence's earlier claim as false) and the publish
  pipeline's **fail-closed gitleaks gate** gates what actually ships (its own honest ceiling: a
  scan, plus the non-optional human diff review — never a proof); secret-*targeting* reads
  are guard-denied; and the blast-radius controls (#2 prod isolation, #4 scoped credentials) bind
  at the platforms that hold real data, not on the dev box. (#3 sandboxed FS likewise does not
  bind on the dev box; the guard's read-side matchers are its only stand-in there.)
- **Why this is a statement and not a doctor advisory, on purpose:** the doctor cannot observe
  network enforcement, so a permanent advisory would be a declared-tier claim wearing an
  advisory-tier costume — and a warning that is yellow on every happy-path run is ignored within a
  month (the doctor's own anti-wolf-crying doctrine). A declaration you can read beats an alarm you
  learn to ignore. Ruled at `D-240815-2` (g); basis: the 2026-08-15 first-principles review.
