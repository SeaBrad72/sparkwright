# Stack Profile — [Stack Name]

> **What this is.** The concrete *how* for one technology stack — the specifics the universal `DEVELOPMENT-STANDARDS.md` defers here (every **→ profile** pointer). Pick a ready profile or generate one from this template at Inception (`DEVELOPMENT-PROCESS.md` §3, recorded as ADR-000).
>
> **How to generate a custom profile:** copy this file to `profiles/<your-stack>.md` and fill every section. Each maps to a universal standard — you're not inventing standards, you're expressing them in your stack. Leave a section's universal requirement intact even if your stack makes it trivial; note *how* it's met.

**Stack:** [language(s) · framework(s) · datastore · hosting]
**Status:** [reference | project-generated]

---

## 1. Toolchain
- **Language / runtime + version:** [...]
- **Package/dependency manager:** [...]
- **Formatter · linter · type-checker:** [...] · **Complexity/duplication** (recommended `gate-lint` config): [stack complexity tool] + [duplication tool] — `docs/operations/code-quality.md`
- **Test runner + coverage tool:** [...]
- **Test quality:** [property-based lib] + [mutation tool, critical paths/nightly] — `docs/operations/test-quality.md` (for IaC/data stacks, the policy/data-quality gate IS the test-quality bar)
- **Inner loop:** [pre-commit / lint-staged + format + lint + fast/affected test subset] — `docs/operations/dev-inner-loop.md`
- **Build tool:** [...]

## 2. Project scaffold
Standard directory layout and the config files a new project starts with (and their baseline contents): [...]

## 3. Standard commands
> These back the universal Definition of Done and CI. Keep names stable across projects in this stack.
```
install:      [...]
dev:          [...]
test:         [...]
test:coverage:[...]
lint:         [...]
type-check:   [...]
build:        [...]
start:        [...]
```

## 4. CI/CD pipeline
The concrete pipeline that enforces the gates (install → lint → type-check → test → build, + coverage upload): [...]

## 5. Security implementation
How each universal security requirement is met in this stack — recommended libraries + a short snippet each:
- Secrets / env loading: [...]
- Secrets at scale (shared/regulated envs): use a managed store (Vault/KMS) — see [secrets-at-scale.md](../docs/enterprise/secrets-at-scale.md)
- Input validation / schema: [...]
- Injection-safe data access (ORM / parameterized): [...]
- AuthN/Z (hashing, tokens): [...]
- HTTP security headers / XSS / CSRF: [...]
- **Static analysis & licenses (conditional gates — `docs/operations/security-scanning.md`):** SAST via **[stack SAST tool]** (`gate-sast`); license policy via `scripts/license-check.sh` over the CycloneDX SBOM (`gate-license`, stack-neutral default — upgrade per the ladder if needed).

## 6. Testing
- Test file convention & layout: [...]
- A representative unit, integration, and (if applicable) e2e example: [...]
- AI eval harness (if AI features): [...]

## 7. Resilience & observability
Idioms/libraries for retry/backoff, circuit breaking, structured logging, error tracking, metrics: [...]

## 8. Data & migrations
ORM/migration tool; how expand-contract / zero-downtime migrations are done here: [...]

## 9. Release & deploy
Build artifact, deploy target, feature-flag system, rollout mechanism, rollback command: [...]

**Containerization & image supply-chain (if this stack ships a deployable service image):** describe the multi-stage non-root Dockerfile, the local dev mirror (compose/devcontainer), and how CI generates an image SBOM + a **digest-bound** provenance attestation (`DEVELOPMENT-STANDARDS.md` §14). See `profiles/typescript-node/` for the worked reference. If this stack does **not** ship a service image (library, CLI, batch, IaC), state **N/A + reason** here — the conditional check (`conformance/container-supply-chain.sh`) skips profiles with no `Dockerfile`.

## 10. Recommended libraries
Vetted defaults (with the *why*) so teams don't re-litigate every choice: [...]

## 11. Stack-specific gotchas
Non-obvious traps for agents/engineers new to this stack: [...]

---

**Last Updated:** [date]
