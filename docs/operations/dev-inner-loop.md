# The Developer Inner Loop — Fast Local Feedback

Rapid iteration depends on a **tight inner loop**: the smaller the gap between writing a line and learning it's wrong, the faster (and safer) you move. The kit defines **three feedback tiers**, fastest first. Stack-neutral; the per-stack tool is a profile choice.

## Three tiers (fastest → slowest)
| Tier | Fires on | Runs (seconds-fast) | Purpose | Bypassable? |
|------|----------|---------------------|---------|-------------|
| **Pre-commit** | every `git commit` | format · lint · type-check (changed files) · the **affected/fast test subset** | catch the trivial stuff *before* it's even committed | yes (`--no-verify`) — it's a convenience, not a control |
| **Pre-push** | before every `git push` | the **agent guard** (`hooks/pre-push`) · plus `sparkwright prepush` — CI's cheap face, run by hand | safety speed-bump (force-push/push-to-main/destructive) · and: find the red here, not on a runner | yes (`--no-verify` for the hook; the lane is a command you choose to run) |
| **CI** | every PR | the full §14 gate set (lint · types · **full** tests+coverage · build · secret-scan · SBOM · provenance) | the authoritative gate — **not** bypassable | no |

**Keep them layered, not redundant.** Pre-commit runs *fast* checks on *changed* files only (sub-10s is the target) — if it gets slow, people disable it. The *full* suite, coverage gate, and supply-chain gates live in CI where slowness is acceptable. The pre-push *hook* is the guard, not a test runner — the parity lane below is a separate, deliberate command (minutes, not seconds), run once before the branch's one push rather than on every commit.

## The before-push tier — `sparkwright prepush`

One command, no arguments, before the branch's one push:

```sh
sparkwright prepush            # = sh conformance/prepush-lane.sh
```

**What it runs is not a hand-curated list — it is derived from `ci.yml` at run time.** The lane parses
`.github/workflows/ci.yml` through a closed grammar (a step is derivable only if it is a plain
`sh conformance/<check>.sh` invocation with a bounded argv; anything else — a conditional step, a
`matrix`, a `container`, a shell fragment inside a block scalar — is *context* and is named, not
guessed at), and runs what it derived **serially**, **under `dash`** (CI's `/bin/sh`, resolved through
a PATH shim so children that re-invoke `sh` get dash too) and in a **scrubbed environment** (no
`GH_*`/`GIT_*`/`KIT_*`, an empty `HOME`, `LC_ALL=C`) inside one temp work root. It writes nothing in
the repo. A hand-curated battery is always an incomplete subset of `ci.yml`; this one cannot be,
because a second lock — a tokenizer-independent **census** (`sparkwright prepush --census`) — reds when
a `conformance/` mention in `ci.yml` is neither derived nor explained by a row in
`conformance/prepush-twins.tsv`.

**What the default runs, and what it leaves to `--warranted` and CI** (PREPUSH-CORE-DEFAULT, 2026-09-30). The default
proves the change's *own surface*, not CI parity:
- scoped lint: `shellcheck.sh --listed` on the listing's shell files (the full shellcheck lock stays in CI and `--warranted`);
- the touched selftests (`selftest-hermetic.sh --touched`);
- the board gates, when `BACKLOG.md` is touched;
- the twins.

The ~81-86 CI-derived `core-live` checks no longer run by default; one note line says how many, and that
`--warranted` and CI run them.

**The recipe is one command: run `sparkwright prepush` (the default, core) once on the final head, push once, and CI is
the net** (`D-241003-2`). Core already covers the scoped `shellcheck` on your touched shell files, the touched files'
own selftests (`selftest-hermetic.sh --touched`), the `review-lane --pre-push` and `loop-state --head` twins, and the
board gates (including `backlog-current`) when `BACKLOG.md` is touched, so do not re-run those by hand. It runs under
`dash` on your machine; BSD-versus-GNU divergence (macOS vs Linux) is CI's to catch. If CI goes red and the cause is
understood, fix and push again.

**`--warranted` stays available and is optional.** Recommended only when a CI red is expensive to redo: CI takes longer
than ~30 min, or the change edits a shared library many checks read (for example `conformance/backlog-lib.sh`,
`conformance/version-helpers.sh`, `.claude/hooks/guard-core.sh`). When in doubt, don't, but a change to the guard or secret-scan is never a case for doubt: run `--warranted`. The measurement behind this
(Architect, 2026-10-03, every `--warranted` line in the 2026-09-27 to 2026-10-02 review records):

| | |
|---|---|
| runs measured | ~15 slices; 45-75 min per run |
| real catches | 2 (a mass-budget overrun, #711; a green-on-clone red plus mass budget and backlog presence, #727), both reproduced by CI |
| wasted | #714: 78 min and no verdict |
| a CI round | ~25-40 min, plus re-binding review and GO records to the new SHA |

On that evidence `--warranted` breaks even at best. After an arm passes, `--warranted` records it under `$HOME/.local/state/sparkwright/prepush/<root-commit>/`; a
later `--warranted` on an unchanged tree prints `SKIP … passed at <sha> on this tree`. There are two keys: the
`core-live` arms are keyed on the **full tree** (several grade `BACKLOG.md`, `CHANGELOG.md` and `docs/`, so a bookkeeping
commit re-runs them); the heavy arms (claims, non-vacuity, green-on-clone) exclude bookkeeping paths (`BACKLOG.md`,
`CHANGELOG.md`, `docs/reviews/`, `docs/plans/`, `docs/architecture/`), and their SKIP line says
`(bookkeeping paths not compared; CI grades them)`. Any uncommitted change, untracked files included, means no cache
that run. A FAIL is never recorded, nor is a tool-absent `SKIP`; the board gates are never cached;
`PREPUSH_NO_CACHE=1` disables it. The cache is a local convenience, never evidence, and CI never reads it.

Measured on macOS, on this slice's own diff (12 files, M): the default took **268 s (4.5 min)**, was 12.5 min
(core-shellcheck 5 s, touched selftests 153 s for 3 targets, board gates ~90 s, twins ~17 s). The board gate
(`backlog-current.sh .`, 350 rows) fell from 320 s to 75-81 s; the design's 30 s board target was not met (the Done
pass forks per row; boarded as `BOARD-GATE-DONE-PASS-BATCH`).

**What it recommends, and the one flag that runs it.** The expensive faces are **Tier 2**:
`--green-on-clone`, `--exports`, `--non-vacuity <check>` and `--slow`, each behind a free-memory floor. With no
flag the lane never runs one. It ends with a *recommendation block*:
- a `warranted:` line for each arm this delta can red: `claims`, `non-vacuity <check>.sh` for each edited
  registered check, and `green-on-clone`;
- a `skipped: <arm> — <why> (expected ~<t>)` line for every other arm;
- today's `--exports`/`--slow`/container lines.

**`--warranted`** (PREPUSH-BATTERY-CHANGE-SCOPED; security C11 amended to *one flag per invocation*) runs
exactly the warranted set, serially:
- it re-reads the memory floor before each arm;
- it refuses an arm while another kit heavy arm is running on the machine (an enclosing one counts);
- `--exports`/`--slow` stay single-arm flags and are never in the warranted set.

A docs-only delta runs the core and warrants nothing.

**The board-gate arm** (PREPUSH-BOARD-GATES-PARITY): when the push's listing contains `BACKLOG.md`, the core also
runs the live board gates CI reaches only through `verify.sh --require` (the `backlog-*`/`board-*`/`roadmap-current` `check control`
rows without `--selftest`, derived from `conformance/verify.sh`) as `core-board` rows, and a red one fails
`PARITY-CORE`; otherwise it prints `skipped: board gates — BACKLOG.md not in the diff`. It closes the board-gate gap
only, not general `verify.sh` parity.

**The verdict is the last line**, always, and never imitates `verify.sh`'s `RESULT:`:
`PARITY-CORE: OK` · `PARITY-CORE: FAIL` · `PARITY-CORE: UNVERIFIED (<reason>)`. A bare `OK` means `--warranted` with everything executed; the default run prints `PARITY-CORE: OK (own surface — N CI-derived core-live check(s) not run; --warranted and CI run them)`; `--warranted` with cache skips prints `PARITY-CORE: OK (K arm(s) from cache, not executed this run)`. Strict is the default
(`--require` is the explicit spelling of it); `--best-effort` moves the exit code to 0 and leaves the
verdict line reading what it reads.

**When CI is red (owner rule, 2026-09-30).** CI must be green to merge. A failure does not by itself stop the run;
once its root cause is understood, stopping the run, fixing, and re-running is the operator's judgment — until CI
succeeds.

**The honest ceiling, in one sentence:** a `--warranted` green with no cache skips proves that *what the lane derived
from `ci.yml` ran green under `dash`, scrubbed, on this machine*; the default run's green (`PARITY-CORE: OK (own
surface — …)`) covers the change's own surface only; an arm served from cache was not executed this run — not parity with the runner's kernel, CPU count or
timing, not the untouched selftests, not the heavy arms you skipped, and never a skipped reviewer.

## Why it matters for agentic work
An agent's inner loop is the same loop. A fast pre-commit means an agent (or human) gets format/lint/type errors back in seconds instead of waiting on a CI round-trip — **more iterations per minute, fewer broken commits, less wasted CI**. It also keeps the commit history clean (no "fix lint" follow-up commits).

## Per-stack tools → your profile
- **Hook manager:** `pre-commit` (the framework, language-agnostic) · or `husky` + `lint-staged` (JS/TS) · or native `.git/hooks` / `core.hooksPath`.
- **Fast test subset:** run only affected tests — e.g. `vitest related` / `jest --onlyChanged` (JS/TS), `pytest-testmon` (Python), `go test ./<changed-pkg>` (Go), Nx/Turborepo `affected` (monorepos).
- **Format/lint:** the stack's formatter + linter on staged files only (`ruff` / `prettier`+`eslint` / `gofmt`+`golangci-lint` / `rustfmt`+`clippy`).

## What this is — and isn't
Pre-commit is a **recommended accelerator, not a gate** (it's `--no-verify`-able by design — gating on it would just train people to bypass it). The authoritative enforcement stays in CI (§14) and the guard (pre-push). `sparkwright prepush` is the same kind of thing — a command you choose to run, whose rc no gate consumes today; it buys iterations, not authority. This tier exists purely to make the fast path *fast*.
