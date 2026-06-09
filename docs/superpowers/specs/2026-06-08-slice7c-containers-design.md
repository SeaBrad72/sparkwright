# Design — Slice 7c: Containers & Image Supply-Chain (pattern + reference profile)

**Date:** 2026-06-08
**Status:** Approved (design) — pending spec review
**Author:** Bradley James + agent
**Roadmap:** Third sub-slice of Slice 7. Closes audit gap G8 (container support prose-only). Plan: `~/.claude/plans/drifting-stirring-thunder.md` §7c.

---

## 1. Goal

Make containers and their **supply-chain integrity** first-class in the kit — moving from prose-only mentions to a concrete, enforced standard — **without** forcing containerization on stacks that shouldn't be containerized (libraries, IaC, batch) and **without** adding a new universally-required CI gate. This slice ships the **standard + conditional gate + conformance check + one fully-worked reference profile (`typescript-node`)** and the `_TEMPLATE` pattern; a follow-on slice rolls the proven pattern across the remaining service profiles.

## 2. Decisions

- **Conditional / service-scoped image supply-chain (MINOR → 2.15.0).** IF a project ships a deployable service container image, the image MUST carry an SBOM + build-provenance **bound to the image digest**. The universal `ci-gates.sh` REQUIRED set is **unchanged** (8 step-ids) — so this is additive, and non-service profiles are unaffected. Mirrors the existing **§13 "binding but conditional"** 15-factor pattern.
- **Provenance binds the image digest, not a tag or the language binary.** The digest is the immutable artifact an admission controller can verify at deploy time.
- **Reference profile: `typescript-node`** — the most broadly legible deployable-service stack. One profile proves the bar; roll-out is a separate ratified slice.
- **Non-service profiles excluded.** `terraform` (IaC) and library/batch-oriented profiles get no container scaffolding. The standard reads "*if you ship a deployable service image, then…*" — honestly scoped, not papered over.
- **Default registry: GHCR.** Consistent with the kit's GitHub-Actions-centric CI. The push-only provenance job gains `packages: write` (scoped to that job only).
- **Image SBOM via Syft (`anchore/sbom-action`), CycloneDX file** — chosen over `docker buildx --sbom` because it runs identically on PR and push (real scan-before-merge), matches the kit's existing CycloneDX-file SBOM convention and the audit-evidence "SBOM file + attestation" expectation, and is decoupled from registry referrers. SHA-pinned per §14.
- **Reuse the 5e two-job least-privilege OIDC structure** — the PR-running `ci` job stays `contents: read`; `id-token: write` / `attestations: write` / `packages: write` live only on the push-to-main `provenance` job.

## 3. Deliverables

| Part | Files |
|------|-------|
| Contract | `DEVELOPMENT-STANDARDS.md` §14 (Container image supply-chain subsection) + §13 (dev/prod parity reinforcement); `DEVELOPMENT-PROCESS.md` §9 (one-line promotion tie) |
| Reference profile | `profiles/typescript-node/Dockerfile`, `.dockerignore`, `compose.yaml`, `devcontainer.json`, `ci.yml` (conditional image job), `deploy/k8s/*.yaml` + `deploy/helm/*` (skeleton); `profiles/typescript-node.md` (§4/§9 filled) |
| Project docs | `templates/RUNBOOK-TEMPLATE.md` (§4 Deploy → add Kubernetes deploy guidance) |
| Conformance | `conformance/container-supply-chain.sh` (conditional, fail-closed) |
| `_TEMPLATE` pattern | `profiles/_TEMPLATE.md` (Containerization & image supply-chain section) |
| Meta | `VERSION` 2.15.0; `CHANGELOG.md`; `docs/ROADMAP-KIT.md` (7c row) |

## 4. Detailed design

### 4.1 Contract — `DEVELOPMENT-STANDARDS.md` §14
Add a subsection **"Container image supply-chain (conditional)"** after the existing supply-chain gate text:
- *Applies when* a project ships a deployable service container image (else N/A with a one-line reason, like the 15-factor gate).
- The image MUST: be **multi-stage** (build stage separate from runtime); run as a **non-root** user; use a **minimal base** (distroless or slim); declare a **healthcheck**; and on release carry **(a) an image SBOM** and **(b) a build-provenance attestation bound to the image digest** (`actions/attest-build-provenance` with `subject-digest` / `push-to-registry: true`).
- Registry default **GHCR**; the push-only provenance job holds `packages: write` + `id-token: write` + `attestations: write`; the PR job stays `contents: read`.
- Cross-reference the two-job OIDC hardening note already in §14.

**§13 (15-factor):** reinforce **dev/prod parity** — local dev (devcontainer/compose) SHOULD mirror the production image; the container is the unit of parity.

**`DEVELOPMENT-PROCESS.md` §9 (Operate / Environments & promotion):** one line — promotion deploys the **attested image by digest**; k8s/Helm is the reference orchestration; rollback is a prior-digest redeploy.

### 4.2 Reference profile — `profiles/typescript-node/`
- **`Dockerfile`** — multi-stage: `builder` (install + build) → `runtime` on a distroless/slim Node base; `USER node` (non-root); `HEALTHCHECK`; only production deps copied. Comments mark the stack-specific lines a project edits.
- **`.dockerignore`** — excludes `node_modules`, `.git`, `.env`, build caches.
- **`compose.yaml`** — app service (built from the Dockerfile) + a sample dependency (PostgreSQL, matching the profile's Prisma stack); env via `.env`; for local dev mirroring prod.
- **`devcontainer.json`** — references the compose/Dockerfile for a reproducible dev environment.
- **`ci.yml`** — extend the existing pipeline:
  - In the `ci` job (PR + push), add `gate-image-sbom` — build the image and generate an **image SBOM** with **Syft (`anchore/sbom-action`, SHA-pinned) in CycloneDX** form, emitting an `image-sbom.json` **file** uploaded as an artifact. This matches the kit's existing `gate-sbom` file convention and runs **identically on PR and push** (real scan-before-merge), unlike a buildx in-registry SBOM attestation that would only materialize on push. On PR this builds-and-scans but does not push.
  - In the push-only `provenance` job, add `packages: write`; build/push the image to **GHCR** on `main`; add `gate-image-provenance` — `actions/attest-build-provenance` with `subject-name` = the GHCR image and `subject-digest` = the pushed digest (`push-to-registry: true`).
  - The existing 8 universal gate-ids remain intact and unmodified. The two new ids (`gate-image-sbom`, `gate-image-provenance`) are **profile-local**, asserted by the new conditional conformance check, NOT added to `ci-gates.sh`'s REQUIRED set.
- **`deploy/k8s/`** — `deployment.yaml` + `service.yaml`: liveness/readiness probes, resource `requests`/`limits`, `securityContext` (non-root, read-only root FS, drop capabilities), `RollingUpdate` strategy, image referenced **by digest** placeholder.
- **`deploy/helm/`** — minimal chart skeleton (`Chart.yaml`, `values.yaml`, templated deployment/service) wrapping the same.
- **`profiles/typescript-node.md`** — fill **§4 CI/CD** (note the conditional image gate) and **§9 Release & deploy** (point at the Dockerfile/compose/deploy refs; keep the existing Vercel/Railway options as alternatives for non-container deploys).

### 4.3 Project docs — `templates/RUNBOOK-TEMPLATE.md`
Extend **§4 Deploy** with a "Container / Kubernetes deploy" block: build→push→attest→promote-by-digest flow, probes, resource limits, rollout/rollback (redeploy prior digest). Keep it conditional ("if you deploy as a container image…").

### 4.4 Conformance — `conformance/container-supply-chain.sh`
A new POSIX `sh` check, **conditional and fail-closed**, in the style of `ci-gates.sh`:
- For each `profiles/*/` directory: IF it contains a `Dockerfile`, THEN assert:
  1. The Dockerfile is **multi-stage** (≥2 `FROM` lines) and **non-root** (a `USER` line that isn't `root`/`0`).
  2. The sibling `ci.yml` declares both `gate-image-sbom` and `gate-image-provenance` step-ids.
  3. The provenance step **binds the image** (references `subject-digest` or `push-to-registry`), not only `subject-path`.
- Profiles with no `Dockerfile` are **skipped** (printed as `N/A`), never failed — this is what keeps the gate conditional and the slice MINOR.
- Exit 0 when all present-Dockerfile profiles pass (or none exist); exit 1 on any violation. Informational, stack-neutral (checks contract ids, not tools).
- **Not** wired into `ci-gates.sh`'s universal REQUIRED set; runnable standalone and listed in the audit-evidence checklist as a conditional Auto row.

### 4.5 `_TEMPLATE` pattern — `profiles/_TEMPLATE.md`
Add a **"Containerization & image supply-chain (if a deployable service)"** subsection under §9 (or §4) describing the standard and pointing at `profiles/typescript-node/` as the worked example, so any generated/custom profile expresses it.

## 5. Validation / testing
- `sh conformance/check-links.sh` → 0 (new files/links resolve).
- `sh conformance/ci-gates.sh profiles/typescript-node/ci.yml` → 0 (the **8 universal gate-ids still intact** after adding the image steps — the regression lock proving we didn't disturb the contract).
- `for p in profiles/*/ci.yml; do sh conformance/ci-gates.sh "$p"; done` → all 0 (no other profile touched).
- `sh conformance/container-supply-chain.sh` → 0 (typescript-node passes the conditional check; all non-Dockerfile profiles report N/A and are skipped).
- `sh conformance/profile-completeness.sh` → 0 (typescript-node still complete).
- `sh conformance/agent-autonomy.sh` → 0 (guard untouched — no regression).
- Manual: a `docker build` of the reference Dockerfile produces a non-root, multi-stage image; `hadolint`-style review (best-effort) shows no obvious anti-patterns.
- Kit CI (`conformance`/`bootstrap`/`docs-links`) green.

## 6. Risks & mitigations
- **MAJOR/MINOR mis-classification.** Mitigation: the universal REQUIRED set is provably unchanged (the `ci-gates.sh` regression check); the new ids are profile-local + conditional → MINOR, by the kit's own semver rule.
- **Provenance binds the wrong subject** (tag/binary instead of digest). Mitigation: spec mandates `subject-digest`/`push-to-registry`; the conformance check asserts the binding form.
- **OIDC privilege creep.** Mitigation: `packages: write` is added **only** to the push-only `provenance` job; the PR `ci` job stays `contents: read`. The conformance/standard keep the two-job split.
- **Scope creep into a container platform.** Mitigation: one reference profile + standard + conditional gate + `_TEMPLATE` pattern only; roll-out to other profiles is a separate ratified slice.
- **Forcing containers where they don't belong.** Mitigation: conditional-on-Dockerfile; non-service profiles excluded; the standard is explicitly "if you ship a service image."

## 7. Out of scope
- Rolling container files across the other ~8 service profiles (the follow-on slice).
- Container scaffolding for non-service profiles (`terraform`, library/batch).
- A specific cloud's k8s flavor (EKS/GKE/AKS specifics) — the reference is vanilla k8s + a Helm skeleton.
- Admission-control policy code (Kyverno/Sigstore policy) — the standard *enables* digest verification; wiring a cluster policy is the adopter's platform concern (Org-owned), noted but not shipped.
- Image signing (cosign) as a separate required step — provenance attestation is the baseline; signing can layer on later.

## 8. Definition of Done
- §14 container image supply-chain subsection added (conditional); §13 dev/prod parity reinforced; §9 promotion tie added.
- `profiles/typescript-node/` ships Dockerfile + .dockerignore + compose + devcontainer + extended ci.yml + deploy/k8s + deploy/helm; `typescript-node.md` §4/§9 filled.
- `templates/RUNBOOK-TEMPLATE.md` §4 gains conditional Kubernetes deploy guidance.
- `conformance/container-supply-chain.sh` present, conditional, fail-closed; typescript-node passes; non-Dockerfile profiles skipped.
- `profiles/_TEMPLATE.md` containerization section added.
- **All universal conformance green; the 8 `ci-gates.sh` ids intact on the reference profile (regression lock); `VERSION` 2.15.0; CHANGELOG + ROADMAP (7c).**
- Feature branch → PR → **human ratification** (governing-doc change → Security-Owner lens). Agent never self-merges.
