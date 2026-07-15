# `kit-update` — bringing a newer kit release into your project

Your project is not a copy of the kit. It is **`incept(export)`** — a transformation of it. So "update
the kit" cannot mean "copy the new files over the old ones": that would restore the kit's `CLAUDE.md`
over *your* project doc, at the same path, and call it a merge.

`scripts/kit-update.sh` is the tool that answers the update question honestly:

> *Which of my files did the kit change since I adopted, and which of those have I changed too?*

It **presents a delta**. It does not apply one.

```sh
sh scripts/kit-update.sh --from https://github.com/SeaBrad72/sparkwright     # the update: report + patch
sh scripts/kit-update.sh --reconstruct-base /tmp/base                        # just the merge base
```

---

## How it works (one paragraph, because you should not trust a tool you cannot picture)

Three trees, all in **your** coordinates:

```
BASE   = incept_old(kit-base)                      run with KIT-BASE's OWN scripts/incept.sh
OURS   = your HEAD                                 untouched, read-only
THEIRS = incept_new(adopter-export(--from))        run with the NEW RELEASE's OWN scripts,
                                                   pruned to the SHAPE your .kit-manifest records
```

THEIRS is pruned to **the shape you actually received** — read from your `.kit-manifest` (the file list
the exporter recorded, vendored in `kit-base`), never guessed. If you pruned to a single profile, THEIRS
is pruned to it; if you kept every profile (a multi-stack adopter), THEIRS keeps them all. That is what
stops an unchanged multi-stack adopter from being handed a patch that *deletes* the profiles they kept.

Each side is run through **the `incept` that belongs to it**, with the **same recorded stamps** and the
**same pinned adoption date**. The transformation therefore *cancels*, and only genuine kit changes
survive. The three trees are 3-way merged in a throwaway repo, and the result is read back and reported.

The proof that the reconstruction is right is an **identity**: for an adopter who changed nothing,
`incept_old(kit-base)` **equals** their `HEAD`, exactly (`conformance/kit-update-identity.sh`).

---

## What it needs from you (it refuses rather than guesses)

| Requirement | Why | If it's missing |
|---|---|---|
| the **`kit-base`** branch (`docs/operations/kit-base.md`) | it *is* the merge base | **refuses**, by name — a guessed base yields a wrong delta, which is worse than none |
| the **inception stamps** in `CLAUDE.md` §3 (project, intent owner, created date, stack, backlog, mode, governance, harness) | they are the inputs it replays `incept` with | **refuses**, listing each missing stamp |

Two stamps — **CI platform** and **DB archetype** — were only added later. A project incepted before
them carries no record, so the tool **infers** them from the tree and **says so, in the output, as an
inference**. Record them in `CLAUDE.md` §3 and the notice goes away.

The adoption date is never defaulted to *today*. Your tree carries your adoption date; a
reconstruction stamped with today's date would fabricate a conflict in files nobody touched.

---

## The report: three categories

| Category | Meaning | What to do |
|---|---|---|
| **offered** | the kit changed it; **you never touched it** | it applies cleanly — this is what the patch contains |
| **CONFLICT** | changed **upstream and by you** | **yours to decide.** Nothing is resolved silently |
| **untouched** | yours; the kit proposes nothing for it | nothing — it is named so that silence is never mistaken for a promise |

**CONFLICT is deliberately wider than git's own conflict list.** Git will happily auto-merge two edits
to different hunks of the same file. `kit-update` will not present that as settled: if you touched a
file and the kit touched it, you decide.

A patch containing **only the offered paths** is written to a scratch path (printed at the end of the
run). Review it, then apply it with your own tools:

```sh
git apply /tmp/…/kit-update-v3.136.0.patch
```

---

## Expect `CLAUDE.md` every release

`incept` **stamps the kit version into your project doc**. So the kit's side of `CLAUDE.md` changes on
**every release**: it shows up as **offered** while you have not edited the doc, and as a **CONFLICT**
the moment you have (which, for a project doc you own, is soon and permanent).

**This is the design working, not a fault.** `CLAUDE.md` is *your* document. Usually the only line you
want from the kit's side is:

```
**Kit version adopted:** vX.Y.Z
```

Take that line; leave the rest of your doc alone.

---

## The two merge engines

The 3-way merge has **two implementations behind one contract**, and the tool **prints which one ran**:

- **`git merge-tree --write-tree`** (preferred) — computes the merged tree in the object store with
  **no checkout at all**. It landed in **git 2.38** (2022). `scripts/preflight.sh` reports whether your
  git has it.
- **the temporary-worktree fallback** — plain `git merge` in a temporary worktree **of the throwaway
  workbench** (not your repo), for any older git. Ubuntu 20.04 still ships git 2.25, so this is a real
  path, not a theoretical one.

The choice is a **runtime capability probe** (it *runs* the subcommand), never a version-string parse.
You can force either one with `--merge-impl merge-tree|worktree`.

**They agree on the answer you act on** — which files are offered, which conflict, which are yours —
and that agreement is asserted in `conformance/kit-update-merge.sh`. They are **not byte-identical**
inside a conflicted file: the two label conflict hunks differently (`<<<<<<< <commit-oid>` vs
`<<<<<<< HEAD`), and on exotic histories — **notably a release that renames a kit file** — merge-ort
(new git) and merge-recursive (old git) can resolve differently and report a different **CONFLICT set**.
Neither writes to your repo, and neither applies anything.

---

## What it writes

**Nothing of yours.** Your worktree, index, refs, objects and config are never written: your `HEAD` is
read with `git fetch`/`git archive` into a throwaway workbench repo. It writes only (a) the directory
you name with `--reconstruct-base` — which must be empty and **outside** any git repo — (b) temp dirs
it deletes, and (c) the patch file, at a scratch path it prints.

---

## Honest ceiling

Read this before you trust a run. The tool prints the same list at the end of every `--from` run, on
purpose — a ceiling only stated in a doc is a ceiling nobody reads.

- **LATEST ONLY.** `--from` carries whatever that source's `HEAD` is, and the public mirror carries only
  the **current** release. **This cannot move you to an intermediate version.** There is no
  `--to v3.100.0`.
- **IT PRESENTS, IT DOES NOT APPLY.** No auto-merge in v1. Not one byte of your repo is written. Every
  hunk is your decision; the patch is a suggestion at a scratch path.
- **IT REQUIRES AN INTACT `kit-base`.** The entire delta is computed against `incept_old(kit-base)`. If
  that branch is gone, the tool refuses — **a wrong base is worse than no base**, because you would
  trust its output.
- **`--from` IS UNTRUSTED INPUT, AND THIS TOOL EXECUTES CODE FROM IT.** Building THEIRS means running
  **that release's own** `scripts/adopter-export.sh` and `scripts/incept.sh`. That is inherent to the
  design (re-running the real scripts is what makes `incept`'s transformation cancel) and inherent to
  adoption itself (running a kit's `incept.sh` is the normal path) — but you deserve to know it before
  you aim the tool. The warning is printed **before** the clone, while you can still stop. **Point it
  only at a source you trust as much as your own repo.**
- **`CLAUDE.md` is offered or conflicts EVERY release** (see above). Design, not fault.
- **THE TWO MERGE ENGINES ARE NOT BYTE-IDENTICAL** (see above). They agree on the answer you act on; on
  a release that **renames** a kit file, an old git's merge-recursive could report a different CONFLICT
  set than merge-ort would.
- **A clean report proves the merge is representable — not that your tests pass after applying it.**
  Offered means *"git can apply this without asking you"*, never *"this is safe for your project"*.
- **It builds THEIRS to the SHAPE your `.kit-manifest` records** — the file set you actually received,
  vendored in `kit-base` — not to a guess. A single-profile adopter's THEIRS is pruned to that profile;
  a multi-stack adopter who kept every profile gets an un-pruned THEIRS, so neither is offered a deletion
  of a profile they legitimately kept. (The stack stamp still *drives* the single-profile prune where it
  applies; the manifest is the authority on the received shape.) If the manifest is unreadable, the tool
  **refuses** rather than guessing — a wrong shape would delete files nobody touched.
- **Reconstruction fidelity is bounded by `incept`'s determinism.** Proven for the current `incept` by
  the identity check, and re-proven on every run of it — never assumed forever.

---

## Related

- `docs/operations/kit-base.md` — the base this all depends on. Do not delete it.
- `conformance/kit-update-identity.sh` — the identity proof (unmodified adopter ⇒ empty diff).
- `conformance/kit-update-merge.sh` — the two engines, same fixture, same answer.
