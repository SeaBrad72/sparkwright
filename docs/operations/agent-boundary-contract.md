# Agent boundary contract (harness-neutral)

What the kit needs from whatever runs your agent, stated as outcomes, not as one harness's setting names. The command guard is a speed bump for honest mistakes; the controls below bind the agent's shell, within *What no row closes* at the end. Background: [`../enterprise/platform-safety-boundary.md`](../enterprise/platform-safety-boundary.md), [`runtime-guards.md`](runtime-guards.md).

## The requirement

- **R1** A process the agent starts cannot read the secret-path set, nor can any file tool the agent calls (on Claude Code, the `Read(...)` deny pairs; the `Edit(...)` pairs cover writes).
- **R2** A process the agent starts cannot open a connection to a host outside the allowlist.
- **R3** The session can prove R1 and R2 by running the probe from the agent's own shell. The probe tests the shell only; it does not test the tool layer.
- **R4** Turning R1 or R2 off is a committed declaration naming the loss.

The probe is the neutral verifier: it never reads a harness's settings, it tries a read and a connect. A connect counts as denied only when the error carries the sandbox proxy's own refusal signature; a DNS failure, a timeout or a TLS error reads UNVERIFIED, because an offline machine is not a boundary. The probe is not shipped yet: until it is, `sparkwright doctor --boundary` is a static read of the settings, and every line it prints is labelled `[static]` (or `[declared]` under CI, or `[static, agent-reported]` in an agent's shell), never a proof. The declaration is human-authored: `.kit/boundary-optout.conf`, read from origin's default branch, never the working tree. An opt-out without a matching entry prints `FAIL boundary: OFF and UNDECLARED [static]` (or `FAIL egress: NOT ENFORCED and UNDECLARED [static]`) and makes a terminal `sh scripts/preflight.sh` exit 1; a declared one prints a `WARN` line, `WARN boundary: OFF [static] (opted out <date>, declared in .kit/boundary-optout.conf)`, with `Lost: <text>`, and does not. A declaration that cannot be read prints `declaration UNVERIFIED`, and one refused for integrity prints `declaration UNTRUSTED`; both fail from a terminal while a part is off, each with its own `Remedy:`. `sparkwright doctor --boundary` exits 0 (judged, nothing undeclared), 1 (a failure) or 2 (UNVERIFIED; 1 under `--require`, or in CI with no terminal).

## Harness rows

Tiers: **kit-enforced** = the harness has settings that implement the outcome and the kit ships them; **UNVERIFIED** = no kit evidence that the outcome holds, and never read as ON. A mapping taken from a harness's documentation and not measured by the kit says so.

| Runtime | Reference implementation | Tier |
|---|---|---|
| Claude Code | The shipped `sandbox` block plus `permissions.deny` `Read(...)`. R1: `sandbox.filesystem.denyRead`, paired entry for entry with `Read(...)` denies (the first binds every process the shell starts; the second binds the Read, Grep and Glob tools); the `Read(...)` and `Edit(...)` pairings are docs-stated, not yet measured. R2: `sandbox.network.allowedDomains` in the project file; the hard deny of an unlisted host is `sandbox.network.strictAllowlist`, honoured only at user or managed scope, so it is the one day-one human step. Until that step is done, egress to an unlisted host rests on a prompt, OPEN in any permission mode that approves prompts without a person (auto, bypass). WebFetch is governed separately by `permissions` `WebFetch(domain:...)` rules. | kit-enforced through the harness; read statically by `sparkwright doctor --boundary`; the shell is not yet probe-verified (the probe follows in a later release) |
| Codex CLI | R2: `sandbox_mode = "workspace-write"` with `[sandbox_workspace_write]` `network_access = false`, all-or-nothing (no per-host allowlist), docs-stated. R1: its sandbox limits writes, not reads, as documented, so a read-deny on secret paths has no key there. | R1 UNVERIFIED (likely unmet), R2 UNVERIFIED until measured by the probe; the container tier is the recommended form on Codex |
| Other CLI harnesses with their own sandbox (Cursor, Gemini CLI, and the rest) | The adapter page, [`harness-adapters.md`](harness-adapters.md), maps R1 and R2 to that harness's settings. No keys are named for them here. | UNVERIFIED until the probe is run on that harness; the mapping is docs-stated per harness |
| Any harness, or none | The container tier: a dev container that mounts only the working tree (no home mounts) and routes egress through an allowlisting proxy ([`containment.md`](containment.md)) | UNVERIFIED until the probe is run against it and measured |
| A harness the kit does not know | No kit check grades it: `sparkwright doctor --boundary` reads Claude Code's settings only, so it says nothing about another harness. | UNVERIFIED |

To move a row off UNVERIFIED: map the harness's settings to R1 and R2, run the probe from that harness's own shell, and record the result here.

## Also part of the Claude Code default (not requirements of the contract)

These ship with the Claude Code mapping and are graded by its static check; they are not harness-neutral outcomes.

- Write-protection of the enforcement layer, the harness's user-level config and the deferred-execution files: `sandbox.filesystem.denyWrite` with a narrowed `allowWrite`, paired with `permissions.deny` `Edit(...)`.
- A static check that reads the effective settings across every scope Claude Code merges, not one file. It is an inference of that merge; the probe is the proof.

## What no row closes

These stay open on every harness, including a fully mapped one. They are the honest ceiling, not a todo.

- A forge comment, issue or gist made with the agent's own credential: the forge is an allowed host, and the credential is the one the agent must hold to push.
- An attacker-supplied token sent to an allowed host. A host allowlist cannot tell the agent's push from one using a token the injected text supplied; narrowing it needs path- or organisation-level egress rules, for example an allowlisting proxy in the container tier.
- The session environment: `env`, `printenv` and `/proc/*/environ` read credentials no path deny covers.
- MCP servers and browser tools: they run outside the shell sandbox, so R1 and R2 do not bind them. Harness account connectors (for example the claude.ai connectors a session inherits) reach their service from outside any local sandbox. The guard's MCP gate classifies by tool name only, so a read-named call passes it, including a secret read through a generic name or a renamed exfiltration ([`runtime-guards.md`](runtime-guards.md) §MCP capability gate). The day-one act: disable every connector the work does not need, in the harness account's connector settings; they live outside the repo, so nothing in `.claude/` or `mcp-policy.json` reaches them.
- MCP servers a project configures in `.mcp.json`: a separate case, allowlisted through `mcp-policy.json`, and outside the shell sandbox like any MCP server.
- Deferred execution: a poisoned cache or hook that a person runs later, unsandboxed.
- A secret already in the model's context, and a secret committed to git history.
- Loopback: if the local-binding rule cannot be scoped to the dev server's port, the shell reaches every loopback listener (a local proxy that bypasses the allowlist, a browser debugging port, local databases).
- Aliases: a hardlink or a case variant of a secret path may escape a path deny where the platform is measured to allow it.
- Name-based deny lists miss a secret under an innocent file name.
- The human who owns the project can turn the sandbox off by editing project settings; the declaration makes that loud, not impossible. Managed settings are the tier a project cannot loosen.

Where the sandbox cannot start (for example Linux without its sandbox runtime, or native Windows), neither R1 nor R2 holds, and the check says so.
