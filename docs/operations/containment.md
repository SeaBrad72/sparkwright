# Agent containment (sandbox FS · scoped tokens · separate prod creds) — reference

How to make platform-safety-boundary controls #2/#3/#4 real. Where the egress allowlist (`egress-control.md`) closes the exfiltration *channel*, these close **what is reachable to exfiltrate in the first place** — directly defanging the MCP `secret.read` class and the interpreter exfil tail at the source.

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

**Shipped in this kit (copy & adapt).** The `typescript-node` profile carries both, so you start from a working reference, not prose:
- **Headless agent sandbox** — the `agent` service in [`profiles/typescript-node/compose.yaml`](../../profiles/typescript-node/compose.yaml): `read_only` root, `tmpfs` scratch, **work-tree-only** mount, `cap_drop: [ALL]`, `no-new-privileges`, and `network_mode: none`. Opt-in (`docker compose --profile agent run --rm agent`); a plain `docker compose up` never starts it, so the verified app path is untouched. This is the **strong** reference — genuinely host-isolated and no-network.
- **IDE sandbox** — [`profiles/typescript-node/.devcontainer/devcontainer.sandbox.json`](../../profiles/typescript-node/.devcontainer/devcontainer.sandbox.json): the same `--read-only`/`--tmpfs`/`--cap-drop` hardening for a Dev-Containers workflow.

**Honest ceiling on the IDE variant.** An IDE-attached container is **inherently weaker** than the headless `agent` service: the editor injects a server that needs a writable area (the `tmpfs` here) and network for extensions — so the devcontainer is read-only-root and host-isolated but **not** no-egress. For the network layer, pair *either* artifact with the egress allowlist (`egress-control.md`); FS-sandbox and egress are separate controls and neither substitutes for the other.

**Proven, not just shipped (E4a).** [`scripts/containment-audit.sh`](../../scripts/containment-audit.sh) *boots* the `agent` service and *probes* it — write-outside-`/work` fails (read-only root), outbound connect fails (`network_mode: none`), a CAP-gated op fails (`cap_drop: [ALL]`), each negative probe paired with a positive control so a dead container cannot pass vacuously. The kit runs it in CI (the `containment-audit` job in `golden-path.yml`) so this reference is **behaviourally** verified, not asserted — and you can run it against your own compose: `sh scripts/containment-audit.sh .`. It proves the *shipped artifact* contains (FS-scope/egress/caps); it does **not** replace the RUNBOOK attestation below, which records that *your deployment* wired it (the kit can't boot your environment). Scoped-tokens/prod-SoD stay attestation-only here — they are cloud-IAM owned, not container-bootable.

## 2. Scoped, short-lived tokens
**The principle:** prefer **OIDC→role federation** over long-lived secrets — CI mints a short-lived token per run and exchanges it for a cloud role; no static cloud keys ever live in the repo, CI secrets, or agent env. Keep `id-token: write` on **only** the job that needs it (never workflow-wide), and pin the trust to a specific repo **and** ref/environment so a fork or another branch cannot assume the role.

All three patterns below are zero-static-secret and copy-pasteable. Replace the `OWNER/REPO`, IDs, and resource names; keep the `sub` pinned tightest your flow allows (a branch or a GitHub Environment, not `*`).

**AWS** — one-time IAM OIDC provider + a role whose trust policy pins the repo+branch:
```json
// IAM role trust policy (least-privilege: this repo, main branch only)
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
      "StringLike":   { "token.actions.githubusercontent.com:sub": "repo:OWNER/REPO:ref:refs/heads/main" }
    }
  }]
}
```
```yaml
# GitHub Actions: assume the role per run — no AWS keys in the repo
permissions: { id-token: write, contents: read }   # scope to THIS job only
steps:
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: arn:aws:iam::<ACCOUNT_ID>:role/<ROLE_NAME>
      aws-region: <REGION>
      # credentials auto-expire at job end (default 1h session); attach a least-privilege policy
```

**GCP** — Workload Identity Federation (pool + provider pinned to the repo), assume a service account:
```bash
# one-time setup (pin the attribute condition to your repo)
gcloud iam workload-identity-pools create gh --location=global
gcloud iam workload-identity-pools providers create-oidc gh-provider \
  --location=global --workload-identity-pool=gh \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --attribute-condition="assertion.repository=='OWNER/REPO'"
```
```yaml
permissions: { id-token: write, contents: read }
steps:
  - uses: google-github-actions/auth@v2
    with:
      workload_identity_provider: projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/gh/providers/gh-provider
      service_account: <SA_NAME>@<PROJECT_ID>.iam.gserviceaccount.com   # least-privilege SA
```

**Azure** — an app registration with a **Federated Identity Credential** (no client secret):
```bash
# one-time: federate the app to this repo+branch (audience is fixed by Azure)
az ad app federated-credential create --id <APP_OBJECT_ID> --parameters '{
  "name": "gh-main",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:OWNER/REPO:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"]
}'
```
```yaml
permissions: { id-token: write, contents: read }
steps:
  - uses: azure/login@v2
    with:
      client-id: <APP_CLIENT_ID>
      tenant-id: <TENANT_ID>
      subscription-id: <SUBSCRIPTION_ID>   # assign least-privilege RBAC to the app, not Owner
```

The kit ships an instance of the **GitHub→GitHub** form already — the push-only `provenance` / `image-provenance` jobs in `../../profiles/typescript-node/ci.yml` hold `id-token: write` scoped to just those jobs. The snippets above extend the same model to cloud providers; enforcement (the actual role/SA/RBAC scoping and TTL) is platform-owned.

**Statically gated (E4a′).** `../../conformance/token-scope.sh` machine-checks this discipline on the shipped workflows: `id-token: write` must be **job-scoped** (never granted in the workflow-level `permissions:` block), and **no long-lived cloud static keys** (AWS/Azure/GCP) may appear — OIDC federation only. It is a structural check on the YAML the kit ships; it does **not** prove the adopter's cloud IAM actually scopes the token (that, and the deployment-specific prod-cred SoD, stay platform-owned + RUNBOOK-attested above).

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
