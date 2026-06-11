# Agent containment (sandbox FS · scoped tokens · separate prod creds) — reference

How to make platform-safety-boundary controls #2/#3/#4 real. Where the egress allowlist (`egress-control.md`) closes the exfiltration *channel*, these close **what is reachable to exfiltrate in the first place** — directly defanging the MCP `secret.read` class and the interpreter exfil tail at the source (`../superpowers/reviews/2026-06-10-A8-mcp-egress-attack-surface.md`).

`conformance/containment-ready.sh` verifies this posture is **declared + attested**; it does **not** verify enforcement. See `conformance/containment-readiness.md`.

## 1. Sandbox / read-only filesystem
Run the agent in a container scoped to the work tree, with the root filesystem read-only and a `tmpfs` for scratch — so `~/.aws`, `~/.ssh`, other projects, and host secrets are simply not mounted.

```yaml
# compose.yaml — an agent service that cannot read the host
services:
  agent:
    build: .
    read_only: true                 # root FS read-only
    tmpfs:
      - /tmp                        # writable scratch only
    volumes:
      - ./:/work:rw                 # ONLY the work tree, nothing from $HOME
    working_dir: /work
    # no ~/.aws, ~/.ssh, /var/run/docker.sock, or host bind mounts
```

devcontainer equivalent: set `"workspaceMount"` to the work tree only and add `"runArgs": ["--read-only", "--tmpfs", "/tmp"]`.

## 2. Scoped, short-lived tokens
- Prefer **OIDC→role federation** over long-lived secrets (CI: GitHub OIDC → a role assumed per run; no static cloud keys in the repo or agent env).
- **Short TTL** (minutes-to-hours) and **least-privilege scope** for every integration token.
- In CI, keep `id-token` at the job/step that needs it (push-only `provenance` job), never workflow-wide.

## 3. Separate production credentials (SoD)
- Agents and dev sessions **never** hold prod write credentials.
- Production access is brokered through an audited **break-glass / approval** workflow.
- A leaked dev/agent token must not be able to touch prod (segregation of duties).

## How to attest (what the check reads)
Record three lines in `RUNBOOK.md` (deploy/security section). The phrases + dates are what `containment-ready.sh` keys on:

```
Sandbox FS: read-only work-tree mounts (compose read_only + tmpfs) — enforced: 2026-06-01
Scoped tokens: OIDC->role, <=1h TTL, least-privilege — enforced: 2026-06-01
Prod credentials: separate + break-glass (SoD) — enforced: 2026-06-01
```

Any aspect that genuinely does not apply: `<Aspect>: N/A — <reason>` (e.g. `Prod credentials: N/A — no production environment`).

## The ceiling (honest)
These patterns contain anything only **if actually applied at the platform**. A repo with the compose snippet but a host/runner that ignores it is **UNVERIFIED**, by design — and a green check never proves the FS is truly read-only, the token truly expires, or prod is truly unreachable. Those are Manual rows in `../../conformance/containment-readiness.md`. Enforcement stays platform-owned (`../enterprise/platform-safety-boundary.md`).
