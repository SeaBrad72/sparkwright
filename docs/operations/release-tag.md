# Release tagging

`v<VERSION>` is tagged on the release commit by `scripts/release-tag.sh` — a coherence-guarded, idempotent FLOOR helper.

## How a release is tagged

`v<VERSION>` is tagged on the release commit coherently (the tag always equals the VERSION file on that commit) and idempotently (a re-run with the tag already present is a safe no-op). The portable FLOOR that does it is `scripts/release-tag.sh`:

1. Read `VERSION`.
2. Assert coherence inline — `conformance/version-tag-coherent.sh . --require` — refusing to proceed if VERSION is already behind a reachable tag.
3. Tag `v<VERSION>` if absent.
4. Push the tag; on push failure, roll back the local tag.

## Default: guarded-manual (what the kit does)

After a merge to `main`, run:

```sh
sh scripts/release-tag.sh
```

This is the *foolproof* form of `git tag`:

- A mistimed run (tag already present) is a safe no-op.
- A VERSION behind a reachable tag is refused before any tag is written.
- The tag always matches VERSION — coherence is guaranteed, not assumed.

The human keeps the release decision. This is consistent with the kit's separation-of-duties and ratification posture: agents propose, humans ratify; automation assists, humans approve the cut.

## Opt-in: auto-tag-on-merge

Adopters who want zero-touch tagging copy a reference binding into their CI:

- **GitHub** — `docs/operations/release-tag.github.yml` → copy to `.github/workflows/release-tag.yml` and enable.
- **GitLab** — `docs/operations/release-tag.gitlab-ci.yml` → incorporate into your pipeline definition.
- **Generic** — call `sh scripts/release-tag.sh` in a post-merge `main` pipeline with push credentials.

**The kit does not ship this active** — it is opt-in. The reference files are provided so adopters can enable automation without writing the binding from scratch.

## Trade-offs of auto-tag-on-merge

Auto-tag-on-merge couples "merge to `main`" with "cut a release". This is a good fit for:

- Continuous-delivery / one-slice-one-version flows where every merge is a shippable increment.
- Teams that want to eliminate manual release steps entirely.

It is a poor fit for:

- **Batched releases** — multiple merges before a release tag; the auto binding fires on every merge.
- **Release branches** — the push trigger on `main` doesn't capture branches like `release/v2`.
- **Pre-releases and QA gates** — auto-tag fires before QA approval; the guarded-manual default keeps the human in the loop.
- **Release governance / audit requirements** — a standing `contents: write` workflow is a larger permission surface; a human-initiated tag provides a clearer audit trail.

Tags are hard to un-ring (especially if adopters have pulled them). Prefer the guarded-manual default when in doubt; opt into auto-tag only when the deployment model genuinely calls for it.

## Honest ceiling

The FLOOR proves the *decision* logic via `--selftest`; the `git push` is live and requires real push credentials. The FLOOR does not choose the version value — that is the responsibility of `apply.py` version-finishing (which bumps `VERSION`, `CHANGELOG.md`, and the `README` badge before the commit that the tag will land on). `release-coherence.yml` remains the tag-push backstop that catches any mismatch between the tag and the published release.
