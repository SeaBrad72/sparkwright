# `kit-base` — the tree you adopted from

When you ran `incept`, the kit recorded the **pristine export you adopted from** as an orphan git branch
called **`kit-base`**, in your own repository. Each time you take a kit update you advance it, so it is a
**chain of the releases you took**: the adoption commit, then one commit per `--advance-base`.

```
your repo
  main       ← your work
  kit-base   ← the pristine Sparkwright exports you took (orphan chain: adoption, then one commit per advance)
```

Every commit carries the trailers `Kit-Source: <vendor commit sha>` and `Kit-Version: <VERSION>`; an advance
commit also carries `Kit-Behind: <N>` (see *What an advance records*). A commit for a **fully taken** release has one
tag: **`kit-base/v<VERSION>+<sha12>`**. (An export from an older kit has no vendor commit to record; its
commit has no trailers and its tag is the legacy `kit-base/v<VERSION>`.)

**Do not delete it.** It is the *merge base* a kit update needs.

---

## Why it exists

To carry a kit improvement into your project, a tool has to answer one question:

> *Which files here did the kit give me, and which did I write?*

Without an answer, an update can only guess — and a guess that goes the wrong way either **clobbers your
work** or **silently refuses to update the kit's own files forever**. `kit-base` answers it by *recording*
rather than *inferring*: it is exactly what the kit shipped you, so anything else in your tree is yours.

It also means the update is computed **locally**. Your project does not depend on the kit's public mirror
carrying a tag for the version you happen to be on — it only needs the *current* release to compare against.

---

## What it contains

Exactly the paths listed in **`.kit-manifest`** — the file list the exporter wrote at export time — and
nothing else. In particular it contains **none of your own files**, even if you adopted the kit into an
existing repository. That is deliberate: if one of your files were in the base, a later comparison would
read it as *"the kit deleted this"*, and an update could propose **deleting your own work**.

It is the tree **before** inception — the raw export, not the incepted result. That keeps a kit-to-kit
comparison free of your project's stamps and renames.

---

## Inspecting it

```sh
git log --oneline kit-base            # the chain: the export you adopted from, then each release you took
git tag -l 'kit-base/*'               # one tag per fully taken release in the chain
git ls-tree -r --name-only kit-base   # every file the kit gave you
git show kit-base:.kit-manifest       # the same list, as the exporter recorded it
git diff kit-base main -- conformance # what you have changed in a kit-owned area
```

---

## Taking an update

```sh
sh scripts/kit-update.sh --from <source>                  # report + patch; writes nothing
git apply <the patch>                                     # review it, commit it, open the PR, merge it
git pull                                                  # so HEAD carries the merge
sh scripts/kit-update.sh --advance-base --from <source>   # THE AGENT runs this: records what HEAD took, publishes it
```

The patch carries the new `.kit-source`, so once the PR merges your `HEAD` records which vendor commit you took.
`--advance-base` then adds that release to the `kit-base` chain. The step is mechanical: the agent runs it after
the merge is pulled, with no human keystroke; `--from` never does it for you. It refuses unless `HEAD` is reachable
from `refs/remotes/<remote>/HEAD` (merge and pull first; `--no-push` skips that check).

**The next `--from` refuses until you do this.** A stale base yields a wrong delta, which is worse than none, so
`kit-update` stops and prints the one command to run.

### What an advance records

One commit, parent = the current tip, whose tree is the raw export of the release. The advance tests each path the
release changed: **taken** (your `HEAD` has the release's content, or git's 3-way says the release's hunks are already
in your file) or **behind**. The message gains one line per behind path, before the trailers:

```
behind <40-hex chain commit> <path>
```

The chain commit named is the one whose content stays the base for that path. A trailer **`Kit-Behind: <N>`** is always
present (0 when complete).

- **`Kit-Behind: 0`:** the release is fully taken; the tag `kit-base/v<VER>+<sha12>` is created (create-only, never
  moved).
- **`Kit-Behind: N > 0`:** a partly taken release. `kit-base` moves, **no tag is created**, and the next `--from`
  shows the report header `PARTIAL — N file(s) behind` and offers (or lists as CONFLICT) exactly those paths. Take the
  remainder, merge, pull, and run the same `--advance-base` again: it writes a child commit with fewer behind lines
  and tags it when the count reaches 0.

It moves only `refs/heads/kit-base` (compare-and-swap) and creates the tag when complete; it never touches your
worktree, index, or `HEAD`.

### Publishing

After the local write the advance runs one atomic, **non-forced** push to `--remote` (default `origin`): local
`refs/heads/kit-base` to the remote's **`refs/kit/base`**, plus the chain's `kit-base/*` tags. It is a non-branch ref,
because the kit's pre-push hook grades every `refs/heads/*` push and a base commit has no `Kit-Row`. `--no-push` keeps
everything local; no such remote prints `kit-base stays local` (rc 0); a rejected push exits **rc 3** with the local
write standing (see `docs/operations/kit-update.md`, *Publishing*).

A fresh clone gets the base back with:

```sh
git fetch origin refs/kit/base:refs/heads/kit-base
git fetch origin 'refs/tags/kit-base/*:refs/tags/kit-base/*'
```

Fetching it automatically is row `KIT-BASE-SHARED`; it is **not built** yet.

### Undoing an advance

Locally (the old tip is printed): `git update-ref refs/heads/kit-base <old tip>`, and `git tag -d <tag>` **when a tag
was made** (a partial advance made none). A **published** base is undone only by a human's explicit force-push, for
example `git push <remote> +<old tip>:refs/kit/base` (and deleting the remote tag if one was pushed). The tool never
forces.

### My base over-claims

An advance made **before** this change recorded a whole release as taken even when your `HEAD` took only part of it:
files you never took read as "upstream did not change it" and are classed untouched, so the update offers nothing
and hides the remainder. **The tool cannot detect this**: such a commit carries no `Kit-Behind` trailer, and it is
indistinguishable from a complete advance. If a release you know you only partly took is not being offered, repair it:

1. Undo to the previous chain commit: `git update-ref refs/heads/kit-base <previous chain commit>`.
2. Delete the over-claiming commit's tag: `git tag -d 'kit-base/v<VER>+<sha12>'`.
3. Run `--from`: it refuses as STALE and prints the cure.
4. Run `--advance-base --from <source>`: it now records what `HEAD` actually took, per path, with the rest behind.

If that over-claiming base was already published, step 1 needs a human force-push to take effect on the remote.

Why a chain: a file counts as *pristine* when it equals the kit's version at **any** release you took, not only
the first. That is how a later update offers what an earlier one left behind (a hunk you declined stays offered;
to keep a file as yours, edit it), and how it avoids calling a file the update itself applied a conflict. The
report classes paths as **offered**, **current** (already equal to upstream), **CONFLICT** (you and the kit both
changed it), or **untouched**.

---

## Older trees (no `.kit-source`)

A tree adopted or updated before this mechanism has no `.kit-source`, so `HEAD` cannot say which release you
took. When `kit-update --from` sees the signs of this (a path both sides changed but that already equals
upstream), it prints a **STALE-BASE** notice pointing here. Tell it which releases you applied, **oldest first**,
one `--at` per release:

```sh
sh scripts/kit-update.sh --advance-base --from <source> --at <sha of the oldest release you applied>
sh scripts/kit-update.sh --advance-base --from <source> --at <sha of the next one>
```

`--at` is accepted only while `HEAD` has no `.kit-source`, and the commit is recorded as **ASSERTED**, not read
from your tree: a wrong sha can misclassify files, but it cannot delete any without your apply, because the patch is only a
suggestion. Once a tree has taken an update that carries `.kit-source`, plain `--advance-base` is all it needs.

---

## Share it

> **Only push or share a `kit-base` you trust.** Every `--from` rebuilds BASE by running the chain commits'
> own `scripts/incept.sh`, so the chain is executed code. A `kit-base` fetched from someone else is a
> code-execution channel: **shared chain commits become code-execution input to your teammates.** Verifying chain
> commits before running them is follow-up work under `KIT-BASE-SHARED`; until it ships, fetch only a base you trust.

`--advance-base` publishes the base for you (see *Publishing* above). **`incept` does not push it**, so a fresh
clone of a freshly incepted project has no base until an advance has published one and the clone fetches it
(`git fetch origin refs/kit/base:refs/heads/kit-base`). Making the base shared and fetched by default is a known
gap (row `KIT-BASE-SHARED`).

---

## If you don't have one

Older exports predate this mechanism. `incept` says so plainly rather than guessing:

```
notice: no .kit-manifest — this export predates the kit-base mechanism.
        NOT recording a base. 'kit-update' will be UNAVAILABLE for this project.
```

Re-export from a current kit to get one.

---

## The upstream operand — how `kit-update` handles a profile-pruned adopter

*(The contract P1.2-pre-b fixes so that P1.2 has a defined operand. Stated here; implemented by the updater.)*

An update needs **two** trees: **yours** (`kit-base` — what you received) and **upstream** (the current
release on the public mirror). But *"the kit at version X"* is **not a single tree**:

- `scripts/publish-public.sh` publishes the **un-pruned** kit — every profile.
- `adopter-export --profile python` gives an adopter a tree with the **other profiles pruned away**.

So a naive `diff(kit-base, upstream)` would tell a `python` adopter that *"the kit added `profiles/go`,
`profiles/rust`, `profiles/kotlin`…"* — and propose re-adding exactly what they deliberately dropped. An
update pipe that fights the adopter's own choices on every run is one they will stop running.

**The resolution — the adopter's `.kit-manifest` is the authority.** The manifest is a flat list of the
files the exporter **actually shipped to *you*** (589 on an un-pruned export). A pruned adopter's manifest
simply **omits** the profiles they pruned. It is therefore the authoritative record of *what shape this
adopter received* — and it is the only artifact that knows, because the shape is chosen at export time and
nothing downstream can infer it.

**The contract:** `kit-update` **derives the adopter's shape from `.kit-manifest` and re-prunes the upstream
release to that shape *before* diffing.** A profile-pruned adopter is therefore never offered profiles they
pruned, and never told the kit "added" something they chose not to take.

> **Not built here, deliberately.** P1.2-pre-b establishes the *contract*; the updater implements it.
> Building the updater's engine inside its own prerequisite is build-ahead — infrastructure for a need that
> does not exist yet.

---

## Honest ceiling

- It records the trees **as you took them**: the adoption export and each release you advanced to. It cannot
  stop you deleting the branch later, and it is only as complete as your `--advance-base` runs (skip one and the
  next `--from` refuses; on an older tree the `--at` shas are your assertion, not a record).
- It is published by `--advance-base` to the remote's `refs/kit/base`, not by `incept`, and a clone must fetch it by
  hand until `KIT-BASE-SHARED` is built.
- It cannot detect a base that over-claims because it was advanced before per-path recording (see *My base
  over-claims*).
- It is *necessary but not sufficient* for a full update: it tells a tool which files the **exporter**
  shipped, not what **inception** then did to them (the `CLAUDE.md` → `ENGINEERING-PRINCIPLES.md` rename,
  the scaffold copies, the stamps). Handling those is the updater's job.
- Brownfield adoption is not yet exercised end-to-end. What *is* proven is that your files
  **cannot leak into the base** (`conformance/kit-base.sh`).
- A kit file you deleted that an *older* release you took did not have (absent == absent there) is offered
  again, marked `(re-add)`; decline by not applying that hunk. One present at every release you took reads
  as yours (CONFLICT if the kit changed it).
- It records nothing about **merging**. Computing and presenting a delta is a separate mechanism, and
  `--advance-base` is the only part of `kit-update` that writes to your repository or pushes.
