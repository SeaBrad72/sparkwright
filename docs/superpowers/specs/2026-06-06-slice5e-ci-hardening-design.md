# Design — Slice 5e: CI Hardening Across All 10 Profile Reference Pipelines

**Date:** 2026-06-06
**Status:** Approved (approach) — pending spec review
**Author:** Bradley James + agent
**Roadmap:** Inserted before Slice 6 (Enterprise addendum). Triggered by a background security review of `profiles/terraform/ci.yml` whose findings proved to be **kit-wide patterns** present in all 10 profile reference pipelines.

---

## 1. Goal

Harden the reference CI pipeline shipped in **every** profile (`profiles/*/ci.yml`) so the kit models *secure-by-default* CI, not insecure-by-default-with-a-comment. Specifically: eliminate the workflow-level OIDC-token exfiltration vector (the one **HIGH**), pin the one unpinned tool install, and turn the existing one-line `# HARDENING:` note into explicit, actionable guidance — backed by a short contract addition in `DEVELOPMENT-STANDARDS.md` §14 so the expectation is codified, not just commented.

This is a hardening slice, not a new capability: **no new gate, no contract-breaking change.** The 8 universal gates (+ each profile's domain gate) are preserved; `conformance/` logic is unchanged.

## 2. Findings being addressed (from the push security review + scope investigation)

All three patterns exist identically in **all 10** profiles (confirmed by grep across `profiles/*/ci.yml`):

| # | Finding | Sev | Disposition |
|---|---------|-----|-------------|
| 1 | `id-token: write` + `attestations: write` at **workflow level** → any PR-triggered step (e.g. `build`, `terraform plan`) can mint an OIDC token a poisoned dependency could exfiltrate | **HIGH** | **Fix** — two-job split (see §4.1) |
| 2 | Third-party actions pinned by **mutable tag** (`@v4`, `@v5`, `@v2`, `@0.24.0`, `@v3`) | MED | **Document** — SHA-pinning a *reference* bakes in opaque, stale hashes; modeled as an explicit adopter hardening step in the comment + §14 (see §4.3) |
| 3 | terraform: `pipx run checkov` **unpinned** PyPI install | MED | **Fix** — pin to an exact `checkov==3.2.x` (see §4.2) |
| 4 | terraform: `conftest` binary downloaded over curl without checksum | LOW | **Document** — note in the terraform `# HARDENING:` comment that adopters should checksum-verify; `CONFTEST_VERSION` is already pinned |

## 3. Decisions

- **OIDC reconciliation = two-job model** (the fix you selected: "split provenance into a push-only job so the main job drops to `contents: read`"). The main `ci` job runs all gates on PR **and** push with `permissions: contents: read`. A new `provenance` job (`needs: ci`, `if: push && main`) holds `id-token: write` + `attestations: write` and attests the build artifact downloaded from `ci`. Full gate coverage on PRs is preserved (we do **not** adopt the review's "PR workflow runs validate-only" suggestion — PRs must run every gate).
- **SHA-pinning = documented adopter step, not baked in.** A reference template that adopters copy is *more* maintainable and readable with major-version tags; the cloud trust policy is the real gate. We codify the expectation in the comment + §14 rather than freezing opaque SHAs.
- **§14 gets a short "CI security hardening" note** (least-privilege OIDC via a push-only attestation job · SHA-pin recommendation · the cloud trust policy MUST restrict `sub` to `refs/heads/main`). This is contract *guidance*, no new required gate.
- **Version: 2.8.0 (MINOR).** Materially improves all reference pipelines and adds §14 guidance; no new required gate (not MAJOR), more than a bugfix (not PATCH).
- **Additive / non-destructive:** every existing profile is *edited in place* to the same secure shape; no profile is removed; no gate id is removed (all 8 + domain gates remain, `gate-provenance` simply relocates to the `provenance` job).

## 4. Detailed design

### 4.1 The two-job restructure (applied to all 10 `profiles/*/ci.yml`)

**Before** (single job, workflow-level OIDC — every profile today):
```yaml
permissions:
  contents: read
  id-token: write
  attestations: write
jobs:
  ci:
    steps:
      - ... all gates incl. gate-build ...
      - name: Attest build provenance
        id: gate-provenance
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        uses: actions/attest-build-provenance@v1
        with:
          subject-path: <artifact>
```

**After** (least-privilege, two jobs):
```yaml
permissions:
  contents: read          # workflow default — least privilege

jobs:
  ci:
    runs-on: ubuntu-latest
    permissions:
      contents: read       # no id-token here: PR-triggered steps cannot mint OIDC
    steps:
      - ... all gates incl. gate-build (unchanged) ...
      - name: Upload build artifact
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        uses: actions/upload-artifact@v4
        with:
          name: build-artifact
          path: <artifact>          # per-profile, see table
          if-no-files-found: error

  provenance:
    needs: ci
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write            # scoped to the push-only attestation job
      attestations: write
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: build-artifact
          path: build-artifact
      - name: Attest build provenance
        id: gate-provenance
        uses: actions/attest-build-provenance@v1
        with:
          subject-path: build-artifact/<glob>
```

Notes:
- `gate-provenance`'s `id:` moves verbatim into the `provenance` job — `ci-gates.sh` greps the whole file for the 8 structural `id:` keys (job-agnostic), so presence is preserved. Validation in §5 confirms.
- The SBOM upload step (`actions/upload-artifact`) stays in `ci` (it's not provenance-related).
- The `if: push && main` guard now lives on the whole `provenance` job (and the upload step), so the artifact is only produced/consumed on the release path — matching today's behavior.

**Per-profile artifact (`subject-path`) — preserved from the current files:**

| Profile | Artifact path | Note |
|---------|---------------|------|
| python | `dist/**` | wheel/sdist |
| typescript-node | `sbom.json` | placeholder; comment retained |
| java-spring | `target/*.jar` | |
| dotnet | `./publish/**` | |
| go | `./<app>` | TODO placeholder retained |
| rust | `target/release/<app>` | TODO placeholder retained |
| kotlin | `build/libs/*.jar` | |
| ml | `dist/**` | |
| data-engineering | `target/manifest.json` | compiled dbt package |
| terraform | `tfplan` | the plan is the artifact |

The upload step's `path:` and the attest `subject-path:` glob are derived from each profile's existing path. Placeholder/TODO paths are retained as-is (still illustrative; not the kit's to resolve).

### 4.2 checkov pin (terraform only)

```yaml
# before
run: pipx run checkov -d . --quiet --compact
# after
run: pipx run --spec 'checkov==3.2.x' checkov -d . --quiet --compact
```
Exact `3.2.x` patch verified against PyPI at implementation time (WebSearch — same diligence as prior SBOM-tool pins). `conftest` is already pinned via `CONFTEST_VERSION`.

### 4.3 `# HARDENING:` comment — strengthened in all 10 ci.yml

Replace the single line with an explicit block:
```yaml
# HARDENING (do before production):
#  - Pin every `uses:` to a full 40-char commit SHA (e.g. actions/checkout@<sha>  # v4.x).
#  - Pin tool installs to exact versions (this reference pins where it installs tools).
#  - OIDC is least-privilege: id-token:write lives only on the push-only `provenance` job.
#    Your cloud trust policy MUST restrict `sub` to `repo:<org>/<repo>:ref:refs/heads/main`
#    (never `pull_request`), so a PR-context token cannot assume your role.
```
(terraform additionally: a line noting the `conftest` download should be checksum-verified.)

### 4.4 `DEVELOPMENT-STANDARDS.md` §14 — short hardening note

Append a brief subsection to §14 (the CI/CD Pipeline contract) — guidance, **no new required gate**:

> **CI security hardening (required posture, not a gate).** The attestation/provenance step requires `id-token: write`; grant it via a **separate job that runs only on push-to-main**, keeping the main gate job at `contents: read` so PR-triggered steps cannot mint an OIDC token. Pin third-party actions to a full commit SHA in production. The cloud OIDC trust policy MUST restrict `sub` to the main-branch ref, never `pull_request`.

This is the contract expression of the per-file comment; agents/humans adopting any profile inherit the posture. **Touches a governing doc → ratified via this spec + the slice PR.**

### 4.5 Companions

`CODEOWNERS` / `BRANCH-PROTECTION.md` are unaffected (no OIDC/permissions content). No change.

## 5. Validation / testing

- `sh conformance/ci-gates.sh profiles/<p>/ci.yml` → exit 0 for **all 10** (8 standard ids still present; `gate-provenance` relocated to the `provenance` job; domain gates `gate-eval`/`gate-data-quality`/`gate-policy` intact).
- `sh conformance/profile-completeness.sh` → green over all 10 (it runs `ci-gates.sh` on each companion `ci.yml`).
- Every edited `ci.yml` is valid YAML; `actionlint` clean if available (two-job `needs:`/`download-artifact` wiring correct).
- **incept wiring:** `incept.sh --noninteractive --stack <p>` into a temp copy still wires `.github/workflows/ci.yml` and passes `inception-done.sh`; the wired file passes `ci-gates.sh`.
- `conformance/check-links.sh` green (the new §14 text adds no broken links).
- Kit CI green (`conformance`, `bootstrap`, `docs-links`).
- **No gate id removed** from any profile (diff check): the 8 universal ids + each domain gate present post-edit.

## 6. Risks & mitigations

- **Artifact passing breaks on profiles with placeholder paths (go/rust `<app>`, ts `sbom.json`).** Mitigation: upload `path:` mirrors the existing `subject-path:` (placeholders retained); `if-no-files-found: error` makes a misconfigured adopter path fail loudly rather than silently attesting nothing — an improvement over today.
- **ci-gates.sh assumes a single job.** Mitigation: it greps the whole file for structural `id:` keys (job-agnostic, verified in Slice 1). §5 re-validates all 10.
- **Over-restricting permissions breaks the gate job.** Mitigation: the `ci` job needs only `contents: read` (checkout); SBOM upload uses the default token. The `provenance` job carries the elevated perms. Verified by actionlint + ci-gates.
- **§14 edit drifts from `CLAUDE.md`.** Mitigation: §14 stays subordinate to `CLAUDE.md` (DoD already references the 7/8 gates); the note adds *posture*, not a gate — no DoD change needed.
- **Scope creep into full SHA-pinning.** Explicitly out of scope (§7); modeled as a documented adopter step.

## 7. Out of scope

- Full SHA-pinning of every action in the references (documented adopter step, not baked in).
- The Enterprise addendum (Slice 6) — though §14's hardening note is a natural lead-in to it.
- Changing any gate definition, adding/removing gates, or altering `conformance/` logic.
- Resolving the go/rust/ts placeholder artifact paths (adopter-owned).
- Executing any pipeline in kit CI (kit only checks gate-id presence + completeness).

## 8. Definition of Done

- All 10 `profiles/*/ci.yml` restructured to the two-job model: `ci` job at `contents: read`, push-only `provenance` job holding `id-token`/`attestations: write`, build artifact uploaded/downloaded; `gate-provenance` id preserved.
- terraform `checkov` pinned to an exact version; strengthened `# HARDENING:` block in all 10.
- `DEVELOPMENT-STANDARDS.md` §14 hardening note added.
- `conformance/ci-gates.sh` exit 0 for all 10; `profile-completeness.sh` green; `incept.sh --stack <p>` + `inception-done.sh` green in temp; `check-links.sh` green; kit CI green.
- No gate id removed from any profile (additive/non-destructive).
- `VERSION` = `2.8.0`; `CHANGELOG.md` 2.8.0 (security-hardening entry); `docs/ROADMAP-KIT.md` note.
- Feature branch → PR; **human-ratified before merge** (this slice edits a governing doc and all reference pipelines).
