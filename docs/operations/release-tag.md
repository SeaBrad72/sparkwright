# Auto-tag-on-merge

Removes the human from release tagging: after every merge to `main`, `v<VERSION>` is tagged and pushed automatically.

## What it does

After a PR is merged to `main`, the pipeline reads the `VERSION` file on that merge commit and creates + pushes the tag `v<VERSION>` — coherently and idempotently.

**Coherent by construction.** The script tags `v<VERSION>` on the commit whose `VERSION` file contains that value. It asserts this inline via `conformance/version-tag-coherent.sh . --require` before tagging. A premature or incoherent tag — tagging before `VERSION` is bumped, or tagging a commit whose `VERSION` lags behind an existing reachable tag — is structurally impossible: the coherence check would fail and the workflow would exit non-zero without creating any tag.

**Idempotent.** If `v<VERSION>` already exists (remotely or locally), the script is a no-op. Re-running on the same commit produces no duplicate tag and no error.

**Human removal.** The recurring failure pattern — manually tagging before `apply.py` finishes bumping `VERSION`, producing incoherent tags that had to be deleted — is eliminated. `apply.py` bumps `VERSION`, the PR merges, the workflow tags. No manual `git tag` step required.

## The FLOOR — `scripts/release-tag.sh`

Pure POSIX `sh`, forge-neutral. No forge SDK, no GitHub Actions context. Works anywhere `git` is available with a push-capable remote.

Decision logic:

1. Read `VERSION`. Validate it is semver (`X.Y.Z`). Exit 2 if not.
2. Assert coherence inline: `sh conformance/version-tag-coherent.sh . --require`. Exit 1 if `VERSION` lags a reachable tag.
3. Check whether `v<VERSION>` already exists on the remote (`git ls-remote`) or locally (`git tag -l`). If yes, print `NOOP` and exit 0.
4. `git tag v<VERSION>` + `git push <remote> v<VERSION>`. Default remote is `origin`; override with `RELEASE_TAG_REMOTE`.

Modes:

- `sh scripts/release-tag.sh` — normal CI mode: decide + tag + push.
- `sh scripts/release-tag.sh --dry-run` — prints the decision (`would create + push vX.Y.Z` or `NOOP`); never writes.
- `sh scripts/release-tag.sh --selftest` — builds temporary git fixtures, exercises all decision branches, returns 0 if all pass.

## Bindings

**GitHub (live):** `.github/workflows/release-tag.yml`. Triggers on `push` to `main` and `workflow_dispatch`. Requires `permissions: contents: write` (push tags). Uses `actions/checkout` with `fetch-depth: 0` (full history for coherence check). Body: `sh scripts/release-tag.sh`.

**GitLab (reference):** Copy `docs/operations/release-tag.gitlab-ci.yml` into your `.gitlab-ci.yml`. Requires a push-capable token (a Project Access Token or protected CI/CD variable) — `CI_JOB_TOKEN` cannot push tags by default. Configure the push-capable remote before calling the script (see the comment in the file).

**Generic forge:** In your post-merge pipeline on `main`, with a push-capable remote configured, call `sh scripts/release-tag.sh`. That is the complete integration.

## Honest ceiling

The conformance lock (`conformance/release-tag-wired.sh`) proves:

- The decision logic is correct via `--selftest` (all branches exercised in isolated git fixtures).
- The GitHub workflow file is present, invokes `release-tag.sh`, carries `contents: write`, and is triggered on `push` to `main`.
- The GitLab reference file and this doc ship with the kit.

What it does NOT prove: the live `git push` (forge auth is the binding's concern, not the FLOOR's). The `--selftest` exercises the decision, not the network call. Manual `git tag` still works — the workflow is idempotent and will no-op if the tag is already present.

## Composition

`release-coherence.yml` (triggers on `v*` tag push → runs `conformance/version-tag-coherent.sh --require`) is unchanged. It serves as the backstop for any tag — manual or automated. Auto-tags produced by this workflow satisfy it by construction (coherence is asserted inline before tagging), and they also validate it as a side-effect. The two workflows are complementary, not redundant.
