# Release tagging

`v<VERSION>` is tagged on the release commit by `scripts/release-tag.sh` — a coherence-guarded, idempotent FLOOR helper.

## How a release is tagged

`v<VERSION>` is tagged on the release commit coherently (the tag always equals the VERSION file on that commit) and idempotently (a re-run with the tag already present is a safe no-op). The portable FLOOR that does it is `scripts/release-tag.sh`:

1. Read `VERSION`.
2. Assert coherence inline — `conformance/version-tag-coherent.sh . --require` — refusing to proceed if VERSION is already behind a reachable tag.
3. Tag `v<VERSION>` if absent.
4. Push the tag; on push failure, roll back the local tag.

## The AGENT must not wait on CI. The TOOL may. (P1-CI)

These are different things, and conflating them is what cost us ~10 minutes a release.

**FORBIDDEN — the agent idly watching CI.** Do not `gh run watch` the post-merge `main` run, do not poll
it, do not hold the session open waiting for a green tick before running `release-tag.sh`. This was never
a written rule; it was an unexamined *habit*, which is precisely why it went unquestioned. Just run the
tag script.

**LEGITIMATE — `release-tag.sh`'s own CI gate.** The script itself performs a **bounded** poll
(`RELEASE_TAG_CI_TIMEOUT`, default 600s) and **refuses to tag a red commit**, degrading **open** on
no-signal or timeout. That is not the habit; it is a guard buying a real guarantee — *a release tag never
points at a broken commit* — and it is worth its cost:

- It is **bounded and automated**: no human or agent attention is spent.
- It **degrades open**, so a missing signal never blocks a release.
- It is now **~3 minutes, not ~10**, because P1-CI cut CI wall-clock from ~600s to ~185s. Making CI fast
  is what makes this gate cheap enough to keep.

*(An earlier draft of this section said "tag immediately, never wait" — full stop. That was wrong: it
contradicted a safety gate already in `release-tag.sh` and would have traded "never tag a red commit" for
three minutes. Corrected here rather than quietly dropped.)*

**Why the agent's wait re-buys nothing (and the script's does):** the PR already ran the identical suite
on the identical tree, so a human watching `main` re-runs a question already answered. The *script*, by
contrast, isn't re-asking — it is refusing to act on a definitively red answer, which is a different and
useful thing.

**Honest ceiling:** `main` can differ from the PR head if another PR merged in between and branch
protection did not require up-to-date branches. That is the one case where the post-merge run is
genuinely informative — and the right fix is to **require branches be up to date before merging** (which
tests the merged tree *pre*-merge), not to have a human watch CI afterwards.

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

## Published tags are immutable (P1.2-pre-b)

A tag in the **dev** repo names a commit for us. A tag on the **public mirror** is what an adopter
**pins to** — and until v3.135.0 `publish-public.sh` **force-pushed** it (`git push --force origin
refs/tags/$TAG`) while pushing `main` **non**-force. The commit history was protected from rewrite;
the one ref adopters actually depend on was not.

**Two layers now, and they protect against different actors:**

1. **The tool refuses.** `publish-public.sh` will not re-publish a tag that is already on the mirror
   *when the tree differs* — that would silently move a released tag, and every adopter pinned to it
   would receive a tree they never audited. (A tag whose tree is **identical** is still a benign
   no-op: the gate must not fire on the happy path.) The `--force` flags are gone, so `git` itself
   rejects a tag push that would **move** a ref — the layer that still holds if a concurrent publish
   lands the tag between our clone and our push.
2. **The forge refuses.** A **tag ruleset** on the public repo:

   > Settings → Rules → Rulesets → **New tag ruleset**
   > · Target: `refs/tags/v*` · Enforcement: **Active**
   > · Block **force pushes** (`non_fast_forward`) · Block **deletions**

   Verified by `conformance/mirror-tag-protection.sh` (weekly, in `drift-watch`).

**Why both.** Layer 1 binds the **tool**, the accident, and the agent. It cannot bind a **human with
push rights**, who can `git push --force` a tag by hand — no client-side check ever could. Only the
forge rule binds every actor.

**The ceiling, stated:** a repository **admin can lift the ruleset**. Immutability here is
**enforced by the forge and merely attested by us**. We claim tamper-**evident and deliberate** —
never tamper-proof. `mirror-tag-protection.sh` returns **exit 2 (UNVERIFIED)** without admin creds,
because an absent credential must never read as a green. A further ceiling: the refusal keys on the
tag's **existence** on the mirror, not on the commit it points at — a tag published at a different
commit whose *tree* happens to match is treated as an idempotent no-op.

**`--dry-run` surfaces the refusal.** The immutability decision is evaluated *before* the dry-run
branch, so `publish-public.sh --dry-run` on an already-published-with-different-tree release exits
non-zero with the refusal — a preview that correctly reports it would be blocked, rather than
printing a plan it could never carry out.

## Honest ceiling

The FLOOR proves the *decision* logic via `--selftest`; the `git push` is live and requires real push credentials. The FLOOR does not choose the version value — that is the responsibility of the slice's **version finishing** (which bumps `VERSION`, `CHANGELOG.md`, and the `README` badge in the slice's own commits, before the commit that the tag will land on). `release-coherence.yml` remains the tag-push backstop that catches any mismatch between the tag and the published release.
