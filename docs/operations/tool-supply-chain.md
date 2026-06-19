# Tool supply chain — the kit's own trust root

**How the kit pins and verifies the external tools its gates depend on — without pretending it secures
what it cannot.** The conformance/CI layer shells out to third-party tools (GitHub Actions, syft,
cosign, gitleaks, plus runner-provided `jq`/`gh`/`shellcheck`/`git`). A compromised tool could make a
gate **falsely pass**, so the toolchain is the trust root beneath every other control. This is the
honest map of what is pinned, what is verified, and where the ceiling is.

## The three tool classes

### 1. GitHub Actions — SHA-pinned + *enforced*
Every `uses:` in the kit's own `.github/workflows/*.yml` **and** the canonical profile reference
(`profiles/typescript-node/ci.yml`) is pinned to a full 40-char commit SHA (a tag like `@v4` is
mutable; a SHA is not). `conformance/action-pinning.sh` enforces this across **both** the kit's own
workflows and the profile reference (previously only the profile) — an unpinned `uses:` fails CI.
Dependabot keeps the SHAs current.

### 2. Profile download-tools (syft · cosign · gitleaks) — version-pinned + checksum-verified
The GitLab profile (`profiles/typescript-node/ci.gitlab-ci.yml`) installs these by download (GitLab has
no SHA-pinned-action equivalent). Each install now: pins the version (`variables:`), downloads the
release artifact **and** the release's published `*_checksums.txt`, and runs `sha256sum -c` before exec
— failing closed (`test -s`) if the artifact's checksum line is absent. This replaced the prior
`curl … | sh` from the syft install script on `main` (an unpinned, unverified script piped to a shell)
and the no-checksum binary downloads. `conformance/supply-chain-verify.sh` locks the hardening: it fails
CI if a `curl … | sh` pipe returns or a `sha256sum -c` verify goes missing.

> The GitHub profile (`ci.yml`) runs the same tools via **SHA-pinned actions**
> (`anchore/sbom-action`, `actions/attest-build-provenance`, `gitleaks-action`), so the action pin is
> its verification — class 1 covers it. Class 2 is the GitLab path, which installs by hand.

### 3. Runner-provided tools (`jq` · `gh` · `shellcheck` · `git` · POSIX text tools)
The kit's own gates run on `ubuntu-latest` and rely on its preinstalled tools (`jq` is a hard
dependency of `agent-autonomy.sh`; `gh` drives the ratification gate; `shellcheck` lints; `git`/`grep`/
`sed`/`awk` are used throughout). These are **not** version-pinned: pinning an apt package across
`ubuntu-latest` image revisions is brittle, and the tools' integrity ultimately roots in the **base
runner image**, which is **platform-owned** (GitHub-hosted runners) — outside what the kit can verify.

## The honest ceiling

A green `action-pinning.sh` + `supply-chain-verify.sh` proves: the kit's own and profile Actions are
SHA-pinned, and the profile's download-tools are checksum-verified against their pinned version's
published manifest. It does **not** prove:

- **Upstream-release integrity** — if an upstream release were fully compromised (binary *and* its
  published checksums swapped at the source), checksum verification would still pass. The next tier is
  **upstream signing**: keyless `cosign verify-blob` of the checksums `.sig` against the release's
  Sigstore certificate. Documented here as the residual, not silently assumed away.
- **Runner base-image integrity** — class-3 tools trust the platform-owned base image. This is the
  same "enforcement is platform-owned" boundary as `containment.md` (the host enforces the sandbox) and
  `cost-governance.md` (the platform enforces the spend cap). The kit pins what it controls and names
  what it does not.
- **The lock is a regression-lock, not a proof** — `supply-chain-verify.sh` is a grep-based guard on
  the *known* install shape: it counts `sha256sum -c` verifies and flags the `curl … | sh`
  pipe-to-shell. It does **not** prove every install verifies — a *new* tool added via a different
  unverified shape (e.g. a blind `curl -O … && ./tool`, or a pipe it doesn't match: `| bash`,
  `sh <(curl …)`, `eval "$(curl …)"`, `wget … | sh`) would pass the lock. The verification itself is
  enforced by the install code (above) + ratified review; the lock catches the common *regression*, not
  every conceivable one. Likewise `action-pinning.sh` scans top-level `.github/workflows/*.yml|*.yaml`
  only — a composite action under `.github/actions/*/action.yml` would be out of its scope (none today).

Ties to `../../DEVELOPMENT-STANDARDS.md` §14 (pin third-party actions to a SHA) and `../../SECURITY.md`
(the reference pipelines are inert references; adopters inherit whatever the profile ships — which is
why the profile, not just the kit, is hardened here).
