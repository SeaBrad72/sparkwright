# Slice 5e: CI Hardening — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden every profile's reference CI pipeline so the kit models secure-by-default CI — eliminate the workflow-level OIDC-token exfiltration vector across all 10 `profiles/*/ci.yml`, pin the one unpinned tool, strengthen hardening guidance, and codify the posture in `DEVELOPMENT-STANDARDS.md` §14.

**Architecture:** Each pipeline splits into two jobs — a `ci` job (all gates, runs on PR + push, `permissions: contents: read`) and a push-main-only `provenance` job (`needs: ci`, holds `id-token`/`attestations: write`) that downloads the build artifact uploaded by `ci` and attests it. The provenance job is **identical across all 10 profiles** (`subject-path: build-artifact/**`); the only per-profile variable is the upload `path:`. No new gate, no `conformance/` change, no gate id removed.

**Tech Stack:** GitHub Actions YAML · `conformance/ci-gates.sh` (POSIX sh) · `actionlint` (if available) · Markdown.

**Source reference (spec):** `docs/superpowers/specs/2026-06-06-slice5e-ci-hardening-design.md`

---

## Canonical building blocks (used by Tasks 2–6)

### Block A — strengthened HARDENING comment

Replace whatever `# HARDENING...` line/block each file currently has (preserve the profile-identifying first lines and any profile-specific notes like java's "compile = type-check" or ml/data-eng/terraform's gate notes) with **exactly**:

```yaml
# HARDENING (do before production):
#  - Pin every `uses:` to a full 40-char commit SHA (e.g. actions/checkout@<sha>  # v4.x).
#  - Pin tool installs to exact versions.
#  - OIDC is least-privilege here: id-token:write lives only on the push-only `provenance`
#    job, so PR-triggered steps cannot mint a token. Your cloud trust policy MUST restrict
#    `sub` to `repo:<org>/<repo>:ref:refs/heads/main` (never `pull_request`).
```

### Block B — top-level permissions

The workflow-level `permissions:` block (with `id-token`/`attestations`) becomes exactly:

```yaml
permissions:
  contents: read
```

### Block C — `ci` job permissions

Immediately under the `ci` job's `runs-on: ubuntu-latest`, add:

```yaml
    permissions:
      contents: read
```

(For `data-engineering`, this sits between `runs-on:` and the existing `services:` block.)

### Block D — build-artifact upload step

The `ci` job's **last step is no longer the provenance step**. After the existing `Upload SBOM` step, append this upload step (the provenance step is REMOVED from the `ci` job — it moves to Block E). `<UPLOAD_PATH>` is per-profile (see each task):

```yaml
      - name: Upload build artifact (for provenance)
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        uses: actions/upload-artifact@v4
        with:
          name: build-artifact
          path: <UPLOAD_PATH>
          if-no-files-found: error
```

### Block E — the `provenance` job (IDENTICAL for all 10 profiles)

Append as a second job, a sibling of `ci` (same indentation as `ci:`):

```yaml
  provenance:
    needs: ci
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write       # scoped to this push-only job (build-provenance attestation)
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
          subject-path: build-artifact/**
```

### Per-profile `<UPLOAD_PATH>` table

| Profile | `<UPLOAD_PATH>` | Note to keep on the `path:` line |
|---------|-----------------|----------------------------------|
| python | `dist/**` | `# the published build output (wheel/sdist)` |
| typescript-node | `sbom.json` | `# placeholder — set to your real artifact (e.g. dist/** or the published package/image)` |
| java-spring | `target/*.jar` | `# the built jar` |
| dotnet | `./publish/**` | `# dotnet publish output` |
| go | `./<app>` | `# TODO: path to the built binary` |
| rust | `target/release/<app>` | `# TODO: path to the built binary` |
| kotlin | `build/libs/*.jar` | `# the built jar` |
| ml | `dist/**` | `# the build artifact (and/or registered model artifact)` |
| data-engineering | `target/manifest.json` | `# the compiled dbt package` |
| terraform | `tfplan` | `# the Terraform plan (the IaC artifact)` |

### Verification recipe (run after each ci.yml edit)

```bash
sh conformance/ci-gates.sh profiles/<profile>/ci.yml ; echo "exit=$?"
# Expected: exit=0
grep -c 'id: gate-' profiles/<profile>/ci.yml   # standard 8 + any domain gate
command -v actionlint >/dev/null && actionlint profiles/<profile>/ci.yml || echo "actionlint not installed — skip"
```

---

## Task 1: §14 CI security hardening note

**Files:**
- Modify: `DEVELOPMENT-STANDARDS.md` (after the "Conformance:" paragraph at line 218, before the `>` blockquote at line 220)

- [ ] **Step 1: Insert the hardening note**

After this existing paragraph (line 218):
```markdown
**Conformance:** a project's pipeline is verified by `conformance/ci-gates.sh <workflow>`, which asserts every required gate is declared (the Definition-of-Done "CI/CD" check, `CLAUDE.md`).
```
add a blank line and then exactly:
```markdown
**CI security hardening (required posture, not a gate).** The provenance/attestation step requires `id-token: write`; grant it via a **separate job that runs only on push-to-main**, keeping the main gate job at `contents: read` so PR-triggered steps cannot mint an OIDC token a poisoned dependency could exfiltrate. Pin third-party actions to a full commit SHA in production. The cloud OIDC trust policy **MUST** restrict `sub` to the main-branch ref (`refs/heads/main`), never `pull_request`. The profile reference pipelines model this two-job split.
```

- [ ] **Step 2: Verify links + render**

Run: `sh conformance/check-links.sh ; echo "exit=$?"`
Expected: `exit=0` (the note adds no new links).
Run: `grep -n "CI security hardening" DEVELOPMENT-STANDARDS.md`
Expected: one match between the Conformance paragraph and the blockquote.

- [ ] **Step 3: Commit**

```bash
git add DEVELOPMENT-STANDARDS.md
git commit -m "docs(standards): §14 CI security hardening note (least-privilege OIDC)"
```

---

## Task 2: python/ci.yml — canonical two-job restructure

**Files:**
- Modify: `profiles/python/ci.yml`

- [ ] **Step 1: Replace the file with the hardened two-job version**

Write `profiles/python/ci.yml` to exactly:

```yaml
# Reference CI pipeline for the Python profile.
# COPY & ADAPT: copy to your project's .github/workflows/ci.yml. Inert here in the kit.
# Each quality gate carries a standardized `id: gate-*` that conformance/ci-gates.sh asserts.
# Satisfies DEVELOPMENT-STANDARDS.md §14.
#
# HARDENING (do before production):
#  - Pin every `uses:` to a full 40-char commit SHA (e.g. actions/checkout@<sha>  # v4.x).
#  - Pin tool installs to exact versions.
#  - OIDC is least-privilege here: id-token:write lives only on the push-only `provenance`
#    job, so PR-triggered steps cannot mint a token. Your cloud trust policy MUST restrict
#    `sub` to `repo:<org>/<repo>:ref:refs/heads/main` (never `pull_request`).
name: CI

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read

jobs:
  ci:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0   # full history for secret scanning

      - uses: astral-sh/setup-uv@v5
        with:
          enable-cache: true
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Install dependencies
        id: gate-install
        run: uv sync --frozen

      - name: Lint
        id: gate-lint
        run: uv run ruff check .

      - name: Type-check
        id: gate-type-check
        run: uv run mypy .

      - name: Test + coverage (>=80%)
        id: gate-test
        run: uv run pytest --cov --cov-fail-under=80

      - name: Build
        id: gate-build
        run: uv build

      - name: Secret scan
        id: gate-secret-scan
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          # Organization-owned repos additionally require:
          # GITLEAKS_LICENSE: ${{ secrets.GITLEAKS_LICENSE }}

      - name: Dependency vulnerability scan
        id: gate-dep-scan
        run: uvx pip-audit

      - name: Generate SBOM (CycloneDX)
        id: gate-sbom
        run: uvx cyclonedx-py environment --output-format JSON --outfile sbom.json

      - name: Upload SBOM
        uses: actions/upload-artifact@v4
        with:
          name: sbom
          path: sbom.json

      - name: Upload build artifact (for provenance)
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        uses: actions/upload-artifact@v4
        with:
          name: build-artifact
          path: dist/**          # the published build output (wheel/sdist)
          if-no-files-found: error

  provenance:
    needs: ci
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write       # scoped to this push-only job (build-provenance attestation)
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
          subject-path: build-artifact/**
```

- [ ] **Step 2: Verify conformance + structure**

Run: `sh conformance/ci-gates.sh profiles/python/ci.yml ; echo "exit=$?"`
Expected: `exit=0`.
Run: `grep -n "id-token: write" profiles/python/ci.yml`
Expected: exactly **one** match, inside the `provenance` job (not at workflow level).
Run: `command -v actionlint >/dev/null && actionlint profiles/python/ci.yml || echo "actionlint not installed"`
Expected: no errors (or "actionlint not installed").

- [ ] **Step 3: Commit**

```bash
git add profiles/python/ci.yml
git commit -m "fix(ci): python — least-privilege OIDC via push-only provenance job"
```

---

## Task 3: typescript-node, java-spring, dotnet — apply the two-job pattern

**Files:**
- Modify: `profiles/typescript-node/ci.yml`, `profiles/java-spring/ci.yml`, `profiles/dotnet/ci.yml`

Apply the **identical transform** from Task 2 to each file, preserving each profile's existing gate steps, comments, and profile-identifying header lines. The transform per file:

1. Apply **Block A** (strengthened HARDENING comment) — keep each file's first 1–5 identifying comment lines and any profile-specific note (e.g. java's "compilation IS type-checking … gate-type-check = `mvn compile`").
2. Apply **Block B** (top-level `permissions: contents: read`).
3. Apply **Block C** (`ci` job `permissions: contents: read` under `runs-on:`).
4. **Remove** the `Attest build provenance` step (`id: gate-provenance`) from the `ci` job.
5. After the existing `Upload SBOM` step, append **Block D** with the per-profile `<UPLOAD_PATH>`:
   - typescript-node: `path: sbom.json          # placeholder — set to your real artifact (e.g. dist/** or the published package/image)`
   - java-spring: `path: target/*.jar          # the built jar`
   - dotnet: `path: ./publish/**          # dotnet publish output`
6. Append **Block E** (the identical `provenance` job) as a sibling of `ci`.

Leave every other step (lint/type-check/test/build/secret-scan/dep-scan/sbom, and the `Upload SBOM` step) byte-for-byte unchanged.

- [ ] **Step 1: Edit `profiles/typescript-node/ci.yml`** per the transform (UPLOAD_PATH `sbom.json`).
- [ ] **Step 2: Edit `profiles/java-spring/ci.yml`** per the transform (UPLOAD_PATH `target/*.jar`).
- [ ] **Step 3: Edit `profiles/dotnet/ci.yml`** per the transform (UPLOAD_PATH `./publish/**`).
- [ ] **Step 4: Verify all three**

Run for each profile `p` in `typescript-node java-spring dotnet`:
```bash
for p in typescript-node java-spring dotnet; do
  echo "== $p =="
  sh conformance/ci-gates.sh "profiles/$p/ci.yml"; echo "exit=$?"
  echo -n "id-token count: "; grep -c "id-token: write" "profiles/$p/ci.yml"
done
```
Expected: each `exit=0`; each `id-token count: 1`.

- [ ] **Step 5: Commit**

```bash
git add profiles/typescript-node/ci.yml profiles/java-spring/ci.yml profiles/dotnet/ci.yml
git commit -m "fix(ci): ts-node, java-spring, dotnet — least-privilege OIDC provenance job"
```

---

## Task 4: go, rust, kotlin — apply the two-job pattern

**Files:**
- Modify: `profiles/go/ci.yml`, `profiles/rust/ci.yml`, `profiles/kotlin/ci.yml`

Apply the same transform (Blocks A–E) as Task 3. Per-profile `<UPLOAD_PATH>` (retain the TODO placeholders exactly — they are adopter-owned):
- go: `path: ./<app>          # TODO: path to the built binary`
- rust: `path: target/release/<app>          # TODO: path to the built binary`
- kotlin: `path: build/libs/*.jar          # the built jar`

Note: go's lint step uses `uses: golangci/golangci-lint-action@v6` (an action, not `run:`) — leave it unchanged; it is not provenance-related. rust's SBOM upload uses `path: "**/*.cdx.json"` — leave the `Upload SBOM` step unchanged.

- [ ] **Step 1: Edit `profiles/go/ci.yml`** (UPLOAD_PATH `./<app>`).
- [ ] **Step 2: Edit `profiles/rust/ci.yml`** (UPLOAD_PATH `target/release/<app>`).
- [ ] **Step 3: Edit `profiles/kotlin/ci.yml`** (UPLOAD_PATH `build/libs/*.jar`).
- [ ] **Step 4: Verify all three**

```bash
for p in go rust kotlin; do
  echo "== $p =="
  sh conformance/ci-gates.sh "profiles/$p/ci.yml"; echo "exit=$?"
  echo -n "id-token count: "; grep -c "id-token: write" "profiles/$p/ci.yml"
done
```
Expected: each `exit=0`; each `id-token count: 1`.

- [ ] **Step 5: Commit**

```bash
git add profiles/go/ci.yml profiles/rust/ci.yml profiles/kotlin/ci.yml
git commit -m "fix(ci): go, rust, kotlin — least-privilege OIDC provenance job"
```

---

## Task 5: ml, data-engineering — apply the two-job pattern (with domain gates + services)

**Files:**
- Modify: `profiles/ml/ci.yml`, `profiles/data-engineering/ci.yml`

Apply the same transform (Blocks A–E). **Critical:** these profiles carry domain gates that MUST remain in the `ci` job, untouched:
- ml: keep `id: gate-eval` (the eval step) in `ci`.
- data-engineering: keep `id: gate-data-quality` in `ci`, and keep the `ci` job's `services:` (Postgres) and `env:` blocks. Block C's `permissions: contents: read` goes **between** `runs-on: ubuntu-latest` and `services:`.

Per-profile `<UPLOAD_PATH>`:
- ml: `path: dist/**          # the build artifact (and/or registered model artifact)`
- data-engineering: `path: target/manifest.json          # the compiled dbt package`

Preserve each file's domain-gate header comment (ml's "PLUS gate-eval", data-eng's "PLUS gate-data-quality … Postgres service") — only the `# HARDENING:` line is replaced by Block A.

- [ ] **Step 1: Edit `profiles/ml/ci.yml`** (UPLOAD_PATH `dist/**`; gate-eval stays in ci).
- [ ] **Step 2: Edit `profiles/data-engineering/ci.yml`** (UPLOAD_PATH `target/manifest.json`; gate-data-quality + services + env stay in ci; Block C between runs-on and services).
- [ ] **Step 3: Verify both — including domain gates survive**

```bash
for p in ml data-engineering; do
  echo "== $p =="
  sh conformance/ci-gates.sh "profiles/$p/ci.yml"; echo "exit=$?"
  echo -n "id-token count: "; grep -c "id-token: write" "profiles/$p/ci.yml"
done
echo -n "gate-eval present: "; grep -c "id: gate-eval" profiles/ml/ci.yml
echo -n "gate-data-quality present: "; grep -c "id: gate-data-quality" profiles/data-engineering/ci.yml
echo -n "postgres service present: "; grep -c "image: postgres:16" profiles/data-engineering/ci.yml
```
Expected: each `exit=0`; each `id-token count: 1`; `gate-eval present: 1`; `gate-data-quality present: 1`; `postgres service present: 1`.

- [ ] **Step 4: Commit**

```bash
git add profiles/ml/ci.yml profiles/data-engineering/ci.yml
git commit -m "fix(ci): ml, data-engineering — least-privilege OIDC, domain gates preserved"
```

---

## Task 6: terraform — two-job pattern + checkov pin + conftest note

**Files:**
- Modify: `profiles/terraform/ci.yml`

Apply the same transform (Blocks A–E), preserving the terraform-specific header comments (the §14-via-IaC-analogs block, the `gate-build`/`gate-dep-scan`/`gate-sbom` mapping notes) — only the final `# HARDENING:` line is replaced by Block A, with **one added line** for the conftest download:
```yaml
#  - The conftest binary is downloaded over HTTPS; verify its checksum for production.
```
Keep the `gate-policy` step in the `ci` job. UPLOAD_PATH: `path: tfplan          # the Terraform plan (the IaC artifact)`.

Note: terraform's `Upload SBOM` step uses `path: sbom.json` (Trivy CycloneDX output) — leave it unchanged. The Trivy steps (`gate-dep-scan`, `gate-sbom`) and `gate-policy` all stay in `ci`.

- [ ] **Step 1: Pin checkov in the `gate-policy` step**

Change the gate-policy `run:` line from:
```yaml
          pipx run checkov -d . --quiet --compact
```
to (verify the exact latest stable `3.2.x` on PyPI first — see Step 2):
```yaml
          pipx run --spec 'checkov==3.2.451' checkov -d . --quiet --compact
```

- [ ] **Step 2: Verify the checkov version is real**

Run: `curl -sSf "https://pypi.org/pypi/checkov/json" | python3 -c "import sys,json; v=json.load(sys.stdin)['info']['version']; print('latest:', v)"`
Use the latest `3.2.x` returned (replace `3.2.451` in Step 1 with the actual latest patch). If PyPI is unreachable, pin to `checkov==3.2.451` (a known-published 3.2.x) and note it in the commit body.

- [ ] **Step 3: Apply Blocks A–E** to the rest of the file (two-job restructure; UPLOAD_PATH `tfplan`).

- [ ] **Step 4: Verify**

```bash
sh conformance/ci-gates.sh profiles/terraform/ci.yml; echo "exit=$?"
echo -n "id-token count: "; grep -c "id-token: write" profiles/terraform/ci.yml
echo -n "gate-policy present: "; grep -c "id: gate-policy" profiles/terraform/ci.yml
echo -n "checkov pinned: "; grep -c "checkov==3.2" profiles/terraform/ci.yml
```
Expected: `exit=0`; `id-token count: 1`; `gate-policy present: 1`; `checkov pinned: 1`.

- [ ] **Step 5: Commit**

```bash
git add profiles/terraform/ci.yml
git commit -m "fix(ci): terraform — least-privilege OIDC, pin checkov, conftest checksum note"
```

---

## Task 7: VERSION, CHANGELOG, ROADMAP

**Files:**
- Modify: `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-KIT.md`

- [ ] **Step 1: Bump VERSION**

Write `VERSION` to exactly:
```
2.8.0
```

- [ ] **Step 2: Prepend CHANGELOG entry**

Insert immediately above the `## [2.7.0] - 2026-06-06` line:
```markdown
## [2.8.0] - 2026-06-06

Slice 5e — CI security hardening across all 10 profile reference pipelines. Triggered by a push security review whose findings proved kit-wide. No new gate, no contract-breaking change.

### Changed
- **All 10 `profiles/*/ci.yml`** restructured to least-privilege OIDC: a `ci` job (all gates, PR + push, `permissions: contents: read`) plus a push-main-only `provenance` job (`needs: ci`) that holds `id-token`/`attestations: write` and attests the build artifact handed off via `upload-artifact`/`download-artifact` (`subject-path: build-artifact/**`). PR-triggered steps can no longer mint an OIDC token. PRs still run every gate.
- Strengthened the `# HARDENING:` block in every reference pipeline (SHA-pin actions · pin tool installs · cloud OIDC trust policy MUST restrict `sub` to `refs/heads/main`).
- `profiles/terraform/ci.yml`: pinned `checkov` to an exact `3.2.x` version; noted the conftest download should be checksum-verified.

### Added
- `DEVELOPMENT-STANDARDS.md` §14: a **CI security hardening** posture note (least-privilege OIDC via a push-only attestation job · SHA-pinning · trust-policy `sub` restriction). Guidance, not a new required gate — Definition of Done unchanged.

### Note
No gate id was removed from any profile; `conformance/ci-gates.sh` (job-agnostic id presence) and `profile-completeness.sh` pass unchanged across all 10. SHA-pinning the references is modeled as a documented adopter step rather than baked-in opaque hashes.
```

- [ ] **Step 3: Add ROADMAP note**

In `docs/ROADMAP-KIT.md`, add a row under the `5d ✅` row (before the Slice 6 row):
```markdown
| 5e ✅ | **CI hardening** *(shipped v2.8.0)* | standards §14 (hardening note) | all 10 `profiles/*/ci.yml` — least-privilege OIDC (push-only provenance job), checkov pin | `conformance/ci-gates.sh` + `profile-completeness.sh` |
```

- [ ] **Step 4: Verify**

Run: `cat VERSION` → `2.8.0`.
Run: `grep -n "2.8.0" CHANGELOG.md docs/ROADMAP-KIT.md` → matches in both.
Run: `sh conformance/check-links.sh ; echo "exit=$?"` → `exit=0`.

- [ ] **Step 5: Commit**

```bash
git add VERSION CHANGELOG.md docs/ROADMAP-KIT.md
git commit -m "chore(release): 2.8.0 — CI hardening slice (5e)"
```

---

## Task 8: Final full-slice validation

**Files:** none modified (verification only; fix-forward if anything fails).

- [ ] **Step 1: Conformance across all 10 profiles**

```bash
for p in profiles/*/ci.yml; do printf "%-40s " "$p"; sh conformance/ci-gates.sh "$p" >/dev/null 2>&1 && echo OK || echo FAIL; done
sh conformance/profile-completeness.sh ; echo "completeness exit=$?"
```
Expected: every profile `OK`; `completeness exit=0`.

- [ ] **Step 2: OIDC posture assertion (the security goal)**

```bash
echo "Profiles with workflow-level id-token (should be ZERO):"
for p in profiles/*/ci.yml; do
  # id-token before the first 'jobs:' line == workflow-level (bad)
  awk '/^jobs:/{exit} /id-token: write/{print FILENAME}' "$p"
done
echo "Each profile must have exactly one id-token (in provenance job):"
for p in profiles/*/ci.yml; do printf "%-40s " "$p"; grep -c "id-token: write" "$p"; done
```
Expected: the first list is **empty**; every profile prints `1`.

- [ ] **Step 3: No gate id regressed**

```bash
for p in profiles/*/ci.yml; do printf "%-40s gates: " "$p"; grep -c "id: gate-" "$p"; done
```
Expected: each profile shows its pre-slice gate count (8 standard + gate-install where present; ml/data-engineering/terraform show one extra domain gate). No profile shows fewer than before.

- [ ] **Step 4: incept wiring still works (sample two stacks, incl. a domain-gate one)**

```bash
TMP=$(mktemp -d)
cp -R . "$TMP/kit"
cd "$TMP/kit"
sh scripts/incept.sh --noninteractive --stack python >/dev/null 2>&1 || sh scripts/incept.sh --stack python --noninteractive >/dev/null 2>&1
sh conformance/ci-gates.sh .github/workflows/ci.yml ; echo "python wired exit=$?"
cd - >/dev/null
rm -rf "$TMP"
```
Expected: `python wired exit=0`. (If the incept flag order differs, consult `scripts/incept.sh --help`; the prior slices used `--noninteractive --stack <p>`.) Repeat for `terraform` to confirm a domain-gate profile wires its `gate-policy`-carrying CI.

- [ ] **Step 5: actionlint (if available) across all 10**

```bash
command -v actionlint >/dev/null && { for p in profiles/*/ci.yml; do echo "== $p =="; actionlint "$p" || true; done; } || echo "actionlint not installed — rely on ci-gates + YAML validity"
```
Expected: no errors from actionlint where installed.

- [ ] **Step 6: Links + kit CI dry signal**

```bash
sh conformance/check-links.sh ; echo "links exit=$?"
```
Expected: `links exit=0`.

This task makes no commits unless it finds a defect; if it does, fix-forward in the relevant profile and re-run Steps 1–3.

---

## Self-review notes (author)

- **Spec coverage:** §4.1 two-job model → Tasks 2–6; §4.2 checkov → Task 6; §4.3 HARDENING block → Block A (Tasks 2–6); §4.4 §14 note → Task 1; §4.5 companions unchanged → no task (correct). Version/CHANGELOG/ROADMAP → Task 7. Validation (§5) → Task 8.
- **Non-destructive guarantee:** Task 8 Step 3 asserts no gate id regressed; every ci.yml task verifies `ci-gates.sh exit=0` + `id-token count: 1`. No profile file is created or deleted; all edits are in-place.
- **Type/shape consistency:** the `provenance` job (Block E) is byte-identical across Tasks 2–6 (`subject-path: build-artifact/**`); the only per-profile variable is Block D's `<UPLOAD_PATH>`, enumerated once in the table and echoed in each task.
- **Uniform verification:** every ci.yml task runs the same `ci-gates.sh` + `id-token count` check; Task 8 adds the workflow-level-id-token=zero assertion that is the security goal of the slice.
