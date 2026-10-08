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
sh scripts/kit-update.sh --from <source>                  # report + patch; imports a published kit-base (verified) if you have none
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

`sh scripts/kit-update.sh --publish-base [--remote <name>]` runs the same publish on its own (no `--from`), for a base
that was never advanced: incept's next steps name it after the first push. No remote exits rc 1.

A fresh clone or a teammate **imports** the published base on its next `kit-update --from` (or `--advance-base`) with
no manual step: see *Share it*. A hand `git fetch origin refs/kit/base:refs/heads/kit-base` is not needed, and the
agent guard denies it (it would skip the verification).

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

> **Who can write `refs/kit/base`, and what runs because of it.** `refs/kit/base` has **no forge protection**: the
> kit's pre-push hook grades only `refs/heads/*`, and the ref sits outside branch protection, so **anyone with push
> access to the repository can write it**. Every `--from` rebuilds BASE by running the chain commits' own
> `scripts/incept.sh`, so a chain commit someone else wrote is code your teammates would run. **The control is the
> import verification below**, not the ref. Whether a forge ruleset can protect `refs/kit/*` is **unmeasured**: GitHub's ruleset API lists only `branch`, `tag` and `push` targets and does not say a non-branch namespace can be matched, and no ruleset has been tried (row `KIT-BASE-REF-RULESET-MEASURE`). Treat the ref as unprotected.

`incept` does **not** push the base. Whoever holds it runs `sh scripts/kit-update.sh --publish-base` once (after the
first push; incept's next steps say so), and `--advance-base` re-publishes after every advance. A teammate's fresh
clone then needs nothing by hand: `kit-update --from` (and `--advance-base`) run `sync_base`, which fetches
`refs/kit/base` through a temporary `refs/kit-import/base` (fsck'd, deleted at once, and by the exit trap), compares it
with the local `kit-base`, and:

- **no local base:** imports the whole chain;
- **the local tip is on the remote's chain:** fast-forwards (imports only the newer commits), so a teammate's advance
  no longer strands you;
- **equal, or the remote is behind:** nothing to do;
- **diverged:** prints both tips and the verified route, **warns and writes nothing; the run CONTINUES on your local
  base** (rc unchanged; with no local base it ends rc 1). This tool never forces.

**Honest ceiling of the next check:** it is a HEURISTIC that catches the remote-branch DWIM route only. Removing the tracking
config, a forged chain under another remote branch name, or checkout-then-history-move are not caught; a LOCAL `kit-base`
is otherwise trusted as your own history. Verifying the local chain when this machine did not write its tip is the
follow-up row `KIT-BASE-LOCAL-CHAIN-VERIFY`.

A local `kit-base` that **came from a remote branch** (`git checkout kit-base` of `origin/kit-base`, which configures
`branch.kit-base.remote`, or a branch equal to a remote-tracking `kit-base`) was never verified, so `kit-update` refuses
to use it ("UNVERIFIED", before anything is built or run); set it aside (`git branch -m kit-base kit-base-unverified`, a
human step) and re-run `--from`. A base you pushed yourself as a branch is refused the same way while its tracking
setting or the remote `kit-base` branch exists: publish it with `--publish-base` (which works from such a clone), then
remove the tracking setting or the remote branch by hand. Every git `kit-update` runs ignores `refs/replace/*` (`GIT_NO_REPLACE_OBJECTS=1`), so a replace ref
cannot swap a chain commit's content.

**Every commit it would import is verified first** (`verify_chain_commit`): exactly one parent; a `Kit-Source` that
**your own history recorded** in `.kit-source` (so a chain cannot claim a genuine release this project never took; a
legacy tree with no `.kit-source` in its history falls back, with a printed warning, to "in `--from`'s history") and
that resolves in `--from` and is in its history; the chain runs oldest to newest (each `Kit-Source` equals or is an
ancestor of its child's); each commit's `behind`/`Kit-Behind` record passes the same strict parse the run applies to a
local base; no symlink, submodule or control-byte path; **every tree entry (mode, blob, path) is an entry of one of the
two exports** (un-pruned, `--profile <stack>`) **that `Kit-Source`'s own exporter makes**; and the tree's **path set
equals one export's** (nothing added, nothing dropped). A forged `scripts/incept.sh` is not in those exports, so the
commit is refused, naming it, before anything is written or run. One bad commit refuses the whole import. The remote
is fetched through a temporary `refs/kit-import/base` (fsck'd, deleted at once), so nothing is referenced until the
chain has passed. Only then does one `update-ref` transaction write
`refs/heads/kit-base` (create-only when absent, otherwise compare-and-swap) plus the chain's own `kit-base/v<VER>+<sha12>`
tags (create-only; an existing local tag is never moved; lookalike tags are not imported). The run prints what it wrote
and the one-line undo. Cost: two exports per imported commit (about 2 s each), once.

**The import fails closed; the run does not.** When this clone has a valid local base and the remote's chain is diverged
or fails verification, `--from` prints a loud WARNING (what, why, nothing written) and continues on the local base,
exactly as before, rc unchanged. With no local base there is nothing to continue on: rc 1, nothing written. To take a
diverged remote's chain, set yours aside (`git branch -m kit-base kit-base-mine`, a human step) and re-run `--from`,
which imports through the verification. A chain with no `Kit-Source` (written before the trailer, or not by
`kit-update`) cannot be verified and is never imported; its publisher re-publishes from a tree that records
`.kit-source` (`--advance-base`, then `--publish-base`). **No message prints a raw `git fetch`/`update-ref`/`branch`
import command**: that route skips the verification. Offline or no remote: the run says so and uses the local base, as
before. No local base and none on the remote: the refusal gains one line, `whoever holds the base: kit-update
--publish-base`; and when the remote lacks a base this clone has, `--from` ends with the same pointer.

Verification binds the *tree* and the *release*, not the story: an attacker who can write the ref can still choose *which
of the releases your history recorded* a chain commit claims (in an order that is plausible), or write a misleading
message (`Kit-Version`). Each yields a wrong **presented** delta; none runs code your trusted `--from` source did not
ship. The agent guard also denies any raw creation or move of `kit-base`, `kit-base/*` or `refs/kit/*`, whatever the
verb (the full list, and what remains, is `docs/operations/runtime-guards.md` R22). It is a narrowing, not a seal.

---

## A base that is not this export's (foreign base)

Running `incept` a second time over a directory that already holds a `kit-base` used to keep that base without
comment, even when it came from another stack's trial (a typescript-node trial, then a python export in the same
directory). `incept` now compares, **before it changes anything**: it builds the tree it would record from this export
(scoped by `.kit-manifest`, pruned to `--stack`) and compares it with the tree of the `kit-base` already there. The test
is **tree identity**, not a list of paths, so a base from an older release of the same stack, with the same file list
and different bytes, is just as foreign.

- **Identical** (the same export again): it proceeds, says the base is identical, and records nothing new.
- **Different, no flag**: exit 1, nothing written. The first line says that moving to a newer kit is
  `kit-update --from <new kit>`, not a second `incept`. Then come the existing base's profiles against your `--stack`,
  counts of what would differ, and the two exits. Which exit to take is the **owner's** decision; an agent reports the
  refusal and does not pick one.
- **`--kit-base-keep`**: keep the existing base (today's behaviour, now explicit). `kit-update` refuses the
  project with `FOREIGN BASE` (naming the base's profiles and your stamped stack, before it runs the base's own `incept`) only when the
  kept base came from another stack; a kept older or different export of the same stack is used as the base.
- **`--kit-base-replace`**: record this export as the base. The old branch is **renamed aside** to
  `kit-base-replaced-<sha12>` and every `kit-base/*` tag that points into it to `kit-base-replaced/<name>`; nothing is
  deleted. The agent guard treats this flag as human-gated, like `gh pr merge --admin`.
- Both flags together are a usage error (exit 2).

If a `kit-base-replaced/<name>` tag already exists and blocks moving a `kit-base/<name>` tag, the replace is **undone and
fails** (naming the tag); the previous base is never left half-moved.

**Honest ceiling of the guard gate.** The agent guard reads the command's text. It denies `--kit-base-replace` in every
spelling it can read (quote, backslash, escape, brace and parameter forms next to the `--kit-base-` prefix, a reader such as
`echo` wrapped around a substitution, a copy of the script, a glob for its name). It cannot see: a flag built with no
`kit-base-` text at all, a script the agent writes first and runs in a later call, or a copy of the script run with a built
flag. Two more routes are also invisible to it. Write-then-run in the SAME call through repo state, for example committing
the flag as message text and then `sh -c "$(git log -1 --format=%B)"`, hides the flag from the command text. A git or gh
alias configured by an earlier call (`git x -m ...`) hides what the command runs. The control that binds those is the owner reading the diff and the `kit-base-replaced-*` branch, not the text guard.

Out of scope: a foreign base that was already **published** to `refs/kit/base`. `--publish-base` never forces, so it would
be rejected, and recovering a published base is a human step on the remote.

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
- It is published by `--publish-base` or `--advance-base` to the remote's `refs/kit/base`, not by `incept`, and a clone
  imports it, verified, on `--from`. **`refs/kit/base` has no forge protection** (anyone with push access can write
  it); import verification is the control, and its residuals are in *Share it*. Hosts other than GitHub are
  **unmeasured** for a non-branch `refs/kit/*` ref. Whether a forge ruleset can protect `refs/kit/*` is
  unmeasured (row `KIT-BASE-REF-RULESET-MEASURE`). Verification needs the `Kit-Source` release in `--from`'s history: an adopter who incepted
  from a dev tag and updates from the public mirror gets "not in the history of `--from`" and must point `--from` at
  the source they adopted from. A base hand-fetched before this shipped is not verified after the fact: delete it and
  let `--from` import it.
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
- It records nothing about **merging**. Computing and presenting a delta is a separate mechanism. The only
  parts of `kit-update` that write a ref are `--advance-base` and `--from`'s verified import of a published base;
  `--advance-base` and `--publish-base` are the only parts that push.
