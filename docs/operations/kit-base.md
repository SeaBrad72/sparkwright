# `kit-base` — the tree you adopted from

When you ran `incept`, the kit recorded the **pristine export you adopted from** as an orphan git branch
called **`kit-base`**, tagged **`kit-base/v<VERSION>`**, in your own repository.

```
your repo
  main       ← your work
  kit-base   ← the pristine Sparkwright export you started from (orphan; one commit)
```

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
git log --oneline kit-base            # one commit: the export you adopted from
git ls-tree -r --name-only kit-base   # every file the kit gave you
git show kit-base:.kit-manifest       # the same list, as the exporter recorded it
git diff kit-base main -- conformance # what you have changed in a kit-owned area
```

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

- It records the tree **as inception received it**. It cannot stop you deleting the branch later.
- It is *necessary but not sufficient* for a full update: it tells a tool which files the **exporter**
  shipped, not what **inception** then did to them (the `CLAUDE.md` → `ENGINEERING-PRINCIPLES.md` rename,
  the scaffold copies, the stamps). Handling those is the updater's job.
- Brownfield adoption is not yet exercised end-to-end. What *is* proven is that your files
  **cannot leak into the base** (`conformance/kit-base.sh`).
- It records nothing about **merging**. Computing and presenting a delta is a separate mechanism.
