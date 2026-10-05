# `kit-update` — bringing a newer kit release into your project

Your project is not a copy of the kit. It is **`incept(export)`** — a transformation of it. So "update
the kit" cannot mean "copy the new files over the old ones": that would restore the kit's `CLAUDE.md`
over *your* project doc, at the same path, and call it a merge.

`scripts/kit-update.sh` is the tool that answers the update question honestly:

> *Which of my files did the kit change since I adopted, and which of those have I changed too?*

It **presents a delta**. It does not apply one.

**Ceiling.** This path is proven on fixture trees by `conformance/kit-update-identity.sh` and
`conformance/kit-update-merge.sh` — it has never yet been run by an external adopter against a real,
divergently-edited project, and it carries no row in `conformance/claims.tsv` (tracked, unrefined, as
`KIT-UPDATE-CLAIM-ROW`). Treat the tool's output as a delta to review, not a merge you can trust blind.

```sh
sh scripts/kit-update.sh --from https://github.com/SeaBrad72/sparkwright     # the update: report + patch
sh scripts/kit-update.sh --reconstruct-base /tmp/base                        # just the merge base
sh scripts/kit-update.sh --advance-base --from <same source>                 # after the PR merges and is pulled: record what you took, publish it
```

### The flow, as one sequence

1. `--from <source>`: the report and a patch at a scratch path. Writes nothing. It ends with a `NEXT` line (below).
2. Apply the patch (all of it, or the parts you want), commit, open the PR, merge it.
3. Pull, so your `HEAD` carries the merge.
4. **The agent runs `--advance-base --from <same source>`**. It is a mechanical step: no human keystroke, and `--from`
   never does it for you. It records, **per path**, what your `HEAD` took, and then publishes `kit-base` (see
   *Recording what you took* below).
5. The next `--from` is computed against what you actually took.

### Your first update: the order

The verbs an update brings (`board create --parent`, the `create.<field>` map) arrive *with* the update, and the
conf they need is one an agent cannot edit in place. So the first update goes in this order:

1. Make the update's row with the verbs your tree has **now**: the existing `board create` without `--parent`, or by
   hand in the tracker. Claim it.
2. Run `--from`, apply, and open the PR. It is control-plane, so it costs what `START-HERE.md`'s solo track says.
3. **The owner merges.**
4. Pull, and the agent runs `--advance-base`.
5. **Only then** use the verbs the update brought. Any `.kit/tracker.conf` line the new release asks for is a
   dev-clone edit (`templates/JIRA-SETUP-TEMPLATE.md` §4).

(cold test 2, items 34 and 38)

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
| a **current** `kit-base` — its tip's `Kit-Source` equals your `HEAD`'s `.kit-source` | a base that is not the release you took yields a wrong delta | **refuses as STALE** and prints the one `--advance-base` command that fixes it |
| the **inception stamps** in `CLAUDE.md` §3 (project, intent owner, created date, stack, backlog, mode, governance, harness) | they are the inputs it replays `incept` with | **refuses**, listing each missing stamp |

Two stamps — **CI platform** and **DB archetype** — were only added later. A project incepted before
them carries no record, so the tool **infers** them from the tree and **says so, in the output, as an
inference**. Record them in `CLAUDE.md` §3 and the notice goes away.

The adoption date is never defaulted to *today*. Your tree carries your adoption date; a
reconstruction stamped with today's date would fabricate a conflict in files nobody touched.

---

## The report: four categories

| Category | Meaning | What to do |
|---|---|---|
| **offered** | your file equals the kit's content at **some release your `kit-base` chain records**, and the new release differs | it applies cleanly — this is what the patch contains |
| **current** | already equal to the new release | nothing |
| **CONFLICT** | changed **upstream and by you**, and the file is **not the kit's content at any release you took** | **yours to decide.** Nothing is resolved silently |
| **untouched** | yours; the kit proposes nothing for it | nothing — it is named so that silence is never mistaken for a promise |

"Pristine" therefore means *equal to a release your chain records*, not *never edited*. A hunk you declined
last time is still the kit's content, so it is **offered again**; to keep a file as yours, edit it. A path
offered because it is pristine only at an **older** release is marked `(pristine at <sha12> …)`, and a file
absent from your tree (you deleted it, or never took it) is marked `(re-add)`.

**CONFLICT is not git's conflict list.** Git will happily auto-merge two edits to different hunks of the
same file; `kit-update` will not present that as settled: a file you changed and the kit changed, which is
not the kit's own content at any release you took, is yours to decide. Git's textual-conflict count is
printed as information only.

The report's header reads `kit-update: v<BASE>@<sha12> (kit-base) -> v<NEW>@<sha12> (--from)`: the
`VERSION@sha` pairs name the exact vendor commits compared, because a version alone cannot tell two
pre-release commits apart.

### CI wiring

An adapted CI workflow that the release also changed reads **CONFLICT**, which hides the one line a new CI
capability may depend on. After the grouping, the report therefore carries a `== CI WIRING (<platform>) ==`
section when your workflow lacks a **kit-owned CI capability** that the release's stack profile has (today:
`changed-listing`, the step that lets an app-only pull request skip the kit's own selftests; without it
every PR runs the full battery, which is safe but slow). The section prints the same `CI-DRIFT:` notice your
CI's `verify-enforced` check prints: the capability, the release it arrived in, the profile lines to adopt
(between the `# >>> kit:owned <id>` and `# <<< kit:owned <id>` markers), and the one-line decline.

- **Workflow offered** (still the kit's own content at a release you took): one line, the patch adopts it.
- **CONFLICT, untouched, or a declined hunk:** the notice. Adopt the lines by hand, or decline with
  `# kit-ci-decline: changed-listing` in the workflow (the full battery then runs on every PR).
- **Nothing stale:** no section. **`--from` has no `--drift`:** one line says so.

The key treats these as having the capability: a `verify.sh --require --changed <arg>` line whose variable
is assigned on another line, earlier on the same line, as a YAML `env:`/`variables:` key, or whose `<arg>`
starts with `$RUNNER_TEMP/`, `$GITHUB_WORKSPACE/`, `$CI_PROJECT_DIR/` or `$CI_BUILDS_DIR/`. A wrapper script
(`make conformance`) or a `\`-continued invocation still reads as lacking: decline it with the line below.

The detection is line-based and runs the **`--from` release's own** `conformance/verify-enforced-wired.sh
--drift` on your workflow (read-only; nothing is written). It does not judge whether an adapted listing step
is safe. The first update that brings this feature prints no section, because your installed `kit-update`
predates it; your CI's own check reports the drift on that update's pull request.

### Grouped by vendor change

After the categories the report lists the reported (offered + CONFLICT) paths **grouped by the vendor
commit that changed them**. A commit that changed several reported paths is marked
`! land together — this one vendor commit changed N reported paths; take them as one change`. Paths the
exporter generates (`.kit-manifest`, `.kit-digests`, `.kit-source`) are listed on their own line. A path
that incept rewrote is **"attributed by matching lines"**: that is an **inference** from the changed lines,
not a record, and it can fail (one commit must account for all of a path's changed lines). Where it cannot
attribute, the report says so and why (a legacy chain commit with no `Kit-Source`, a vendor commit not in
`--from`'s history, or paths no single commit accounts for).

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

## Recording what you took: `--advance-base`

Run it after the update's PR has merged **and you have pulled**. The patch carries the new `.kit-source`, so your
`HEAD` names the vendor commit; `--advance-base` then appends that release to the `kit-base` chain (see
`docs/operations/kit-base.md`, *Taking an update*). **Until you do, the next `--from` refuses as STALE.** It
prints the one command that fixes it, and says the agent runs it once the PR has merged and been pulled.

**It refuses until HEAD is on the shared line.** `HEAD` must be reachable from `refs/remotes/<remote>/HEAD`
(default remote `origin`): merge, pull, then advance, so `kit-base` never records a release only your branch has. If
`refs/remotes/<remote>/HEAD` is not set it says so and names the cure (`git remote set-head <remote> -a` after a
fetch). `--no-push` skips this check, for a solo or offline clone. Nothing is written on a refusal.

### Per path, and PARTIAL

A release is not always taken whole. For each path the release changed, the advance asks whether `HEAD` **took** it:
`HEAD` has the release's content, or git's own 3-way says the release's hunks are already in your file (a hand-merge
counts as taken). A path `HEAD` did not take is recorded **behind**.

- **Every path taken:** the chain commit carries `Kit-Behind: 0`, and the release's tag is created.
- **Some path behind:** the chain commit carries `Kit-Behind: <N>` and one `behind <chain commit> <path>` line per
  path, and **no tag is created**: a tag always names a release fully taken. The `--from` report header then
  reads `kit-base: v<VER>@<sha12> PARTIAL — N file(s) behind (listed under offered/CONFLICT)`.

A behind path is never hidden. The next `--from` rebuilds BASE from the *effective* base (each behind path from the
chain commit its record names), so a behind file you have not touched is **offered**, and one you changed is
**CONFLICT**.

**Finishing a partial release:** take the remainder (apply the offered hunks, or merge them by hand), merge, pull,
and run the **same** `--advance-base --from <same source>` again. It records what you took since, and creates the
tag when the count reaches 0. It refuses (rc 1, nothing written) when the release is in the chain but not at the tip,
when the tip is already complete (`Kit-Behind: 0`), or when nothing new was taken since the last advance.

### The NEXT line

A `--from` report with something to record (a release newer than the tip's, or a tip still PARTIAL) ends with:

```
NEXT (the agent, after this update's PR merges and is pulled): sh scripts/kit-update.sh --advance-base --from '<src>'
```

When `--from` is the tip's own release and the tip is complete, there is nothing to record and it ends
`NEXT: none — kit-base is current.` On a partial tip, if a behind path in your tree already equals the tip's release
(you took it after the advance), the report adds one `NOTE` line: run `--advance-base` first to record them.

### Publishing: `--remote`, `--no-push`, rc 3

After the local write, `--advance-base` runs **one atomic, non-forced push** to `--remote` (default `origin`): your
local `refs/heads/kit-base` to the remote's **`refs/kit/base`**, plus every local `kit-base/*` tag that points into the
chain. It is a non-branch ref on purpose: the kit's pre-push hook grades every `refs/heads/*` push, and a base commit
has no `Kit-Row`. It runs through your own git credentials and configuration. A fresh clone gets the base back with
`git fetch origin refs/kit/base:refs/heads/kit-base`; doing that automatically is row `KIT-BASE-SHARED`, **not built**.

- **No such remote:** it says `kit-base stays local` and exits 0.
- **`--no-push`:** everything stays local; it prints the push line to run later.
- **Only the tool's own tags are pushed:** `kit-base/v<VER>+<sha12>` whose `<sha12>` is the first 12 characters of the
  tagged chain commit's `Kit-Source`, plus the legacy root tag `kit-base/v<VER>` at the chain root. Any other
  `kit-base/*` tag stays local. The push runs with a scrubbed git config environment (`GIT_CONFIG_*`,
  `GIT_NAMESPACE` cleared); your `HOME`, repo and user config, and credential helpers still apply.
- **Exit 3:** the push was rejected or failed. **The local write stands.** It prints git's own message and exits 3. If
  git reports a rejection (`[rejected]` / non-fast-forward) it names the rejected ref(s) and says the remote's
  `refs/kit/base` most likely moved (a teammate advanced it); any other failure says so instead. Reconcile by hand: `git fetch <remote>
  refs/kit/base`, compare `git log --oneline FETCH_HEAD` with `git log --oneline kit-base`, then publish with the
  printed push line. The tool never forces.

### Legacy trees

For a tree adopted or updated before `.kit-source` existed, `HEAD` cannot say which release you took.
Tell it with `--at <sha>`, **oldest release first**, one `--at` per release you applied; each is recorded as
**ASSERTED**, not read from your tree. A wrong `--at` can misclassify files; it cannot delete one without
your apply, because the patch is only a suggestion.

### If it refuses as STALE

`kit-base`'s tip does not record the release your `HEAD` took. The cure is the printed `--advance-base` command, once
the update's PR has merged and been pulled. If instead it reports the base is **ahead** of `HEAD` (a chain commit
already records your `HEAD`'s release but is not the tip), something moved `kit-base` past what `HEAD` took:
inspect `git log kit-base` and `git reflog kit-base` before going on.

---

## After an update: your open PRs

A branch opened before the update does not carry it. `loop-state` grades the PR's **final** commit, and a merge of
`main` into the branch puts a trailer-less merge commit last. Two ways out:

- **(a) Merge `main` in locally, then re-carry the trailer block on that merge commit before you push.** Amend its
  message so the contiguous `Kit-*` block is its last paragraph. The commit is unpublished, so this needs no force push.
- **(b) Ask a human to rebase and force-push.** The guard reserves force pushes to a human.

Do not push the merge commit and amend it afterwards: that *is* a force push. (cold test 2, item 60)

---

## What it writes

- **`--from` / `--reconstruct-base`: nothing of yours.** Your worktree, index, refs, objects and config
  are never written: your `HEAD` is read with `git fetch`/`git archive` into a throwaway workbench repo.
  They write only (a) the directory you name with `--reconstruct-base` — which must be empty and
  **outside** any git repo — (b) temp dirs they delete, and (c) the patch file, at a scratch path they print.
- **`--advance-base`: `refs/heads/kit-base`, one create-only tag when the release is fully taken, and the objects
  they need — atomically** (one ref transaction; decisions D-241002-1 and D-241003-1). Never your worktree, index,
  `HEAD` or config. After the local write it **publishes**: one atomic, non-forced push of `kit-base` to the remote's
  `refs/kit/base`, plus the chain's `kit-base/*` tags (`--no-push` skips it). It is the only part of `kit-update`
  that writes to your repository or pushes.

---

## Honest ceiling

Read this before you trust a run. The tool prints the same list at the end of every `--from` run, on
purpose — a ceiling only stated in a doc is a ceiling nobody reads.

- **LATEST ONLY.** `--from` carries whatever that source's `HEAD` is, and the public mirror carries only
  the **current** release. **This cannot move you to an intermediate version.** There is no
  `--to v3.100.0`.
- **IT PRESENTS, IT DOES NOT APPLY.** No auto-merge in v1. `--from` writes not one byte of your repo
  (only `--advance-base` writes, and only the `kit-base` ref and, for a fully taken release, a tag; it then publishes them). Every hunk is your decision; the
  patch is a suggestion at a scratch path.
- **IT REQUIRES AN INTACT `kit-base`.** The entire delta is computed against `incept_old(kit-base)`. If
  that branch is gone, the tool refuses — **a wrong base is worse than no base**, because you would
  trust its output.
- **`kit-base` IS ONLY AS GOOD AS ITS RECORD.** Skip an `--advance-base` and the next run refuses as
  STALE; on a legacy tree the `--at` shas are your assertion, not a record. The advance records per path what
  `HEAD` took and re-offers the rest (PARTIAL), but it **cannot detect** a base that an advance made *before*
  this change over-claims (it recorded a whole release); see `docs/operations/kit-base.md`, *My base over-claims*.
  Publishing is to `refs/kit/base` only; fetching it into a clone that has none, and verifying shared chain
  commits before their `incept` runs, is row `KIT-BASE-SHARED` (not built). Grouping by vendor commit is
  partly inference (see above).
- **A STALE INSTALLED HOOK IS REPORTED, NOT CURED.** The HOOK REFRESH section appears when a release changes
  `hooks/pre-push` and also when your installed hook is stale and the release did not touch it: it prints the
  adopter's own `guard-wired.sh` pre-push verdict. It never writes `.git/` or `core.hooksPath`; the one-time setting
  (or the `cp`) stays a human act, and until it happens the gate stays red. Every run prints a verdict or says it
  could not check (`hook state: not checked (<reason>)`, e.g. the gate is absent, printed no verdict, or only its
  N/A); a clean PASS stays silent. The state is read only when someone runs `kit-update` or `guard-wired.sh`.
  (cold test 2, items 101 and 102)
- **A KIT FILE YOU DELETED THAT AN OLDER RELEASE DID NOT HAVE IS OFFERED AGAIN.** A kit file you deleted
  that an *older* release you took did not have (absent == absent there) is offered again, marked
  `(re-add)`; decline by not applying that hunk. One present at every release you took reads as yours
  (CONFLICT if the kit changed it).
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

- `docs/operations/kit-base.md` — the base this all depends on, and the advance step. Do not delete it.
- `conformance/kit-update-advance.sh` — the chain legs: advance, STALE refusal, declined/stranded hunks.
- `conformance/kit-update-identity.sh` — the identity proof (unmodified adopter ⇒ empty diff).
- `conformance/kit-update-merge.sh` — the two engines, same fixture, same answer.
