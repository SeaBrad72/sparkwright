# Secrets at Scale

How to manage secrets beyond local `.env` for shared, staging, production, and regulated environments. This is the reference for the `DEVELOPMENT-STANDARDS.md` §2 "Secrets at scale" contract. See also the [responsibility boundary](README.md).

## The contract (recap)

- **Managed store, not env files** — HashiCorp Vault or a cloud KMS + secrets manager for anything beyond local dev.
- **Least-privilege access** — per-workload policies; an app reads only the secrets it needs.
- **Rotation, preferably dynamic** — short-lived/dynamic secrets issued per-workload beat long-lived static ones; rotate static secrets on a schedule and on compromise.
- **No plaintext at rest in the wrong places** — never in committed state, logs, container images, or CI workflow definitions.
- **Break-glass is audited** — emergency direct access is time-boxed, logged, and reviewed.

## Patterns

### Static vs dynamic secrets
A **static** secret (a stored DB password) is fetched and reused; rotate it on a schedule. A **dynamic** secret is generated on demand for a specific workload with a short TTL (e.g. Vault database secrets engine issuing per-pod DB credentials), then auto-revoked. Prefer dynamic where the backend supports it — it shrinks the blast radius of a leak to the TTL window.

### CI injection via OIDC (reuse the §14 provenance pattern)
CI should **never** store long-lived cloud keys. Use the same workload-identity path the kit's reference pipelines already model: the job presents a short-lived **OIDC token**, the cloud trust policy (restricted to `refs/heads/main`, per the Slice 5e hardening) exchanges it for a scoped, short-lived role, and the job reads secrets from the store at run time. The secret never lands in the workflow file or the logs.

### Rotation
Automate rotation in the store (lease/TTL for dynamic; scheduled rotation for static). Applications re-read on rotation (or use a sidecar/agent that refreshes). Treat a rotation failure as an incident (alert).

### Envelope encryption (KMS)
For data the app encrypts itself, use **envelope encryption**: a KMS-held key-encryption-key (KEK) wraps a per-record data-encryption-key (DEK). The KEK never leaves the KMS; rotating it re-wraps DEKs without re-encrypting data. Maps to ISO A.8.24 (use of cryptography).

### Break-glass
Define an audited, time-boxed emergency-access path for when the automated path fails — who may invoke it, how it's logged, and the post-use review. This is itself an auditable control (ties to [audit-evidence-checklist.md](../../conformance/audit-evidence-checklist.md), Slice 6d).

## Secret-manager client by stack

Pick the row for the stack you adopted (you run one stack, not ten). **Reference, not endorsement** — verify currency for your environment.

| Stack | Vault client | Cloud secrets/KMS client |
|-------|--------------|--------------------------|
| python | `hvac` | `boto3` (AWS) · `google-cloud-secret-manager` · `azure-keyvault-secrets` |
| typescript-node | `node-vault` | `@aws-sdk/client-secrets-manager` · `@google-cloud/secret-manager` · `@azure/keyvault-secrets` |
| java-spring | Spring Cloud Vault | Spring Cloud AWS / GCP secrets · Azure Key Vault Spring Boot starter |
| dotnet | `VaultSharp` | `Azure.Security.KeyVault.Secrets` · `AWSSDK.SecretsManager` |
| go | `hashicorp/vault/api` | `aws-sdk-go-v2` (secretsmanager) · cloud SDK secret managers |
| rust | `vaultrs` | `aws-sdk-secretsmanager` · cloud SDK secret clients |
| kotlin | Spring Cloud Vault (JVM) | Spring Cloud AWS / GCP · Azure Key Vault starter |
| ml | same Python clients (`hvac` / cloud SDKs) | model/registry creds via the store, not notebooks |
| data-engineering | same Python clients | warehouse creds via the store / `env_var()`, never plaintext in `profiles.yml` |
| terraform | Vault provider | cloud KMS data sources; **never** plaintext secrets in state |

## Anti-patterns

- Committing `.tfvars`/`*.env` with real secrets, or secrets in container images / `ARG`s.
- Long-lived cloud access keys in CI secrets when OIDC workload identity is available.
- Logging secret values (redact — §2) or echoing them in CI.
- One shared "god" token with broad access instead of per-workload least privilege.
