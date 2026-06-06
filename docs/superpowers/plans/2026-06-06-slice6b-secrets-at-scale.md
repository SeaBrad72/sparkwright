# Slice 6b: Secrets at Scale — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Pillar 2 of the enterprise addendum — a stack-neutral **secrets-at-scale contract** (managed store beyond `.env`) in `DEVELOPMENT-STANDARDS.md` §2, a reference doc `docs/enterprise/secrets-at-scale.md` (patterns + a secret-manager-client-by-stack table), and a one-line pointer in `profiles/_TEMPLATE.md` so future/BYO profiles route correctly.

**Architecture:** Documentation/contract only — no new gate, no code, no edits to the 10 existing profiles. Stack-neutral contract + stack-aware reference table (the kit's "universal contract, specific reference" idiom). Ties the CI-injection pattern to the Slice 5e push-only provenance/OIDC job.

**Tech Stack:** Markdown · `conformance/check-links.sh`.

**Design source:** `docs/superpowers/specs/2026-06-06-slice6-enterprise-umbrella-design.md` §4b.

---

## Task 1: §2 "Secrets at scale" subsection (the contract)

**Files:**
- Modify: `DEVELOPMENT-STANDARDS.md` (insert after the `### Secrets management` subsection, before `### Input validation & sanitization`)

- [ ] **Step 1: Insert the subsection.** After this existing block:
```markdown
### Secrets management
Never commit secrets (API keys, DB credentials, signing keys, passwords, tokens). Load from environment; fail fast if a required secret is missing. Keep real values in an untracked local env file; commit a `.env.example` with placeholders.
```
add a blank line and then exactly:
```markdown
### Secrets at scale
`.env` is the floor (local dev). For shared, staging, and production environments — and any regulated data — secrets belong in a **managed secret store** (HashiCorp Vault or a cloud KMS + secrets manager), never in env files baked into images or in committed state. Requirements: a central store with **least-privilege access policies**; **rotation** — prefer **short-lived / dynamic** secrets issued per-workload over long-lived static ones; **no plaintext secrets in state, logs, or images**; CI **fetches secrets at run time** (e.g. OIDC → cloud role, reusing the §14 push-only attestation pattern), never storing them in the workflow; **break-glass** access is time-boxed and audited. → `docs/enterprise/secrets-at-scale.md` for patterns and the per-stack client.
```

- [ ] **Step 2: Verify.**
Run: `grep -n "### Secrets at scale" DEVELOPMENT-STANDARDS.md` → one match, between `### Secrets management` and `### Input validation`.
Run: `sh conformance/check-links.sh ; echo "exit=$?"` → `exit=0`.

- [ ] **Step 3: Commit.**
```bash
git add DEVELOPMENT-STANDARDS.md
git commit -m "$(printf 'docs(standards): §2 secrets-at-scale contract (managed store, rotation, dynamic)\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

## Task 2: `docs/enterprise/secrets-at-scale.md` (the reference)

**Files:**
- Create: `docs/enterprise/secrets-at-scale.md`

- [ ] **Step 1: (verify libraries current)** Spot-check via WebSearch that the secret-manager client libraries in the table below are real and current (especially the less-common ones: `vaultrs` for Rust, `VaultSharp` for .NET, `hvac` for Python, `node-vault`, Spring Cloud Vault). Correct any that have changed; keep them marked "reference, not endorsement".

- [ ] **Step 2: Write the file** with exactly this content (apply any library corrections from Step 1):

```markdown
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
Define an audited, time-boxed emergency-access path for when the automated path fails — who may invoke it, how it's logged, and the post-use review. This is itself an auditable control (ties to `audit-evidence-checklist.md`, Slice 6d).

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
```

- [ ] **Step 3: Verify.**
Run: `sh conformance/check-links.sh ; echo "exit=$?"` → `exit=0` (links to `README.md` resolve; the `audit-evidence-checklist.md` mention is plain text, not a link, since 6d hasn't created it — keep it plain text).
Run: `ls docs/enterprise/secrets-at-scale.md`.

- [ ] **Step 4: Commit.**
```bash
git add docs/enterprise/secrets-at-scale.md
git commit -m "$(printf 'docs(enterprise): secrets-at-scale patterns + secret-manager-by-stack table (6b)\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

## Task 3: Wiring — `_TEMPLATE.md` pointer + README live link

**Files:**
- Modify: `profiles/_TEMPLATE.md` (§5 Security)
- Modify: `docs/enterprise/README.md` (Contents table)

- [ ] **Step 1: `profiles/_TEMPLATE.md`** — in §5 "Security implementation", change the line:
```markdown
- Secrets / env loading: [...]
```
to:
```markdown
- Secrets / env loading: [...]
- Secrets at scale (shared/regulated envs): use a managed store (Vault/KMS) — see [secrets-at-scale.md](../docs/enterprise/secrets-at-scale.md)
```
(The relative path from `profiles/_TEMPLATE.md` resolves to `docs/enterprise/secrets-at-scale.md`.)

- [ ] **Step 2: `docs/enterprise/README.md`** — in the Contents table, change the plain-text row:
```markdown
| secrets-at-scale.md *(Slice 6b)* | Managed-secret-store contract (Vault/KMS) + secret-manager client by stack. |
```
to a live link (drop the "Slice 6b" tag now that it exists):
```markdown
| [secrets-at-scale.md](secrets-at-scale.md) | Managed-secret-store contract (Vault/KMS) + secret-manager client by stack. |
```

- [ ] **Step 3: Verify.**
Run: `sh conformance/check-links.sh ; echo "exit=$?"` → `exit=0` (both new links resolve).
Run: `sh conformance/profile-completeness.sh ; echo "exit=$?"` → `exit=0` (the `_TEMPLATE.md` is excluded from the no-`[...]` rule, and the 10 real profiles are untouched — confirm still green).

- [ ] **Step 4: Commit.**
```bash
git add profiles/_TEMPLATE.md docs/enterprise/README.md
git commit -m "$(printf 'docs(enterprise): route _TEMPLATE + README to secrets-at-scale (6b)\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

## Task 4: VERSION, CHANGELOG, ROADMAP

**Files:**
- Modify: `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-KIT.md`

- [ ] **Step 1: VERSION** → exactly:
```
2.10.0
```

- [ ] **Step 2: CHANGELOG** — insert above `## [2.9.0] - 2026-06-06`:
```markdown
## [2.10.0] - 2026-06-06

Slice 6b — Enterprise addendum, pillar 2: secrets at scale. Second of four sub-slices.

### Added
- `DEVELOPMENT-STANDARDS.md` §2 **"Secrets at scale"** subsection — the contract: managed store (Vault/KMS) beyond `.env`, least-privilege, rotation (prefer dynamic/short-lived), no plaintext in state/logs/images, CI fetches at run time via OIDC, audited break-glass.
- `docs/enterprise/secrets-at-scale.md` — patterns (static vs dynamic, CI injection reusing the §14 OIDC/provenance pattern, rotation, envelope encryption, break-glass) + a **secret-manager-client-by-stack** table covering all 10 stacks in one place.
- `profiles/_TEMPLATE.md` Security section now points to the secrets-at-scale doc, so future/BYO profiles route correctly.

### Note
Stack-neutral contract + stack-aware reference — **no edit to the 10 existing profiles**. No new gate, no code. The CI-injection pattern ties to the Slice 5e push-only OIDC job.
```

- [ ] **Step 3: ROADMAP** — insert after the `6a ✅` row:
```markdown
| 6b ✅ | **Secrets at scale** *(shipped v2.10.0)* | standards §2 | `docs/enterprise/secrets-at-scale.md` + §2 contract + `_TEMPLATE.md` pointer | `check-links.sh` |
```

- [ ] **Step 4: Verify.**
```bash
cat VERSION   # 2.10.0
grep -n "2.10.0" CHANGELOG.md docs/ROADMAP-KIT.md
sh conformance/check-links.sh ; echo "links exit=$?"
```

- [ ] **Step 5: Commit.**
```bash
git add VERSION CHANGELOG.md docs/ROADMAP-KIT.md
git commit -m "$(printf 'chore(release): 2.10.0 — enterprise addendum pillar 2 (secrets at scale)\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

## Task 5: Final 6b validation

**Files:** none (verification only; fix-forward if needed).

- [ ] **Step 1: Links + structure.**
```bash
sh conformance/check-links.sh ; echo "links exit=$?"
ls -1 docs/enterprise/   # README.md, compliance-crosswalk.md, secrets-at-scale.md
```

- [ ] **Step 2: Contract ↔ reference consistency.**
```bash
grep -q "### Secrets at scale" DEVELOPMENT-STANDARDS.md && echo "contract present"
grep -q "secret-manager" docs/enterprise/secrets-at-scale.md || grep -qi "secret-manager client by stack" docs/enterprise/secrets-at-scale.md && echo "table present"
grep -q "secrets-at-scale.md" profiles/_TEMPLATE.md && echo "template pointer present"
grep -q "\[secrets-at-scale.md\](secrets-at-scale.md)" docs/enterprise/README.md && echo "readme link live"
```
Expected: all four print.

- [ ] **Step 3: No regression (doc/contract-only slice).**
```bash
sh conformance/profile-completeness.sh ; echo "completeness exit=$?"   # 0
for p in profiles/*/ci.yml; do sh conformance/ci-gates.sh "$p" >/dev/null 2>&1 || echo "FAIL $p"; done; echo "ci-gates checked"
```
Expected: completeness exit=0; no FAIL.

No commit unless a defect is found; fix-forward and re-run.

---

## Self-review (author)

- **Spec coverage (umbrella §4b):** §2 contract → Task 1; secrets-at-scale.md patterns + client-by-stack table → Task 2; `_TEMPLATE.md` pointer (+ README live link) → Task 3; version/changelog/roadmap → Task 4; validation → Task 5.
- **No placeholders:** full content inline; library table marked "reference, not endorsement" with a Step-1 currency check.
- **Bounded scope honored:** no edit to the 10 existing profiles; only `_TEMPLATE.md` gains a pointer; no new gate/code.
- **Governing-doc change (§2):** Task 1 is the highest-ratification item — committed separately so the diff is clean for review.
