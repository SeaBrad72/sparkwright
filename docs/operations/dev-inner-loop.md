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

What it runs is derived from `ci.yml` at run time, not hand-curated: the lane runs what it derived serially, under `dash` (CI's `/bin/sh`), in a scrubbed environment (`GH_*`/`GIT_*`/`KIT_*` unset, an empty `HOME`, `LC_ALL=C`), and writes nothing in the repo. A tokenizer-independent census (`sparkwright prepush --census`) reds when a `conformance/` mention in `ci.yml` is neither derived nor explained by a row in `conformance/prepush-twins.tsv`.

**What the default runs.** The default proves the change's *own surface*, not CI parity:
- scoped lint: `shellcheck.sh --listed` on the listing's shell files (the full shellcheck lock stays in CI and `--warranted`);
- the secret scan of the branch's range (`core-secretscan`, the scan CI runs); a missing `gitleaks` is UNVERIFIED and blocks, never a skip;
- the touched selftests (`selftest-hermetic.sh --touched`);
- the board gates, when `BACKLOG.md` is touched;
- the scoped parse-lint arm (`core-parselint`);
- the twins, among them `review-lane --pre-push` and `loop-state --head`;
- the touched-readers arm: it fills a time budget with the CI-derived checks, red-history checks first and then by measured time (they are not selected by your change), and prints the rest as a `CI-ONLY (paste into the PR):` block with each line's red cost.

The rest of the ~81-86 CI-derived `core-live` checks no longer run by default; one note line says how many, and that `--warranted` and CI run them.

**The recipe is one command: run `sparkwright prepush` (the default) once on the final head, push once, and CI is the net**. Do not re-run by hand what the default already covers. It runs under `dash` on your machine; BSD-versus-GNU divergence (macOS vs Linux) is CI's to catch. If CI goes red and the cause is understood, fix and push again.

**`--warranted` is optional.** Recommended only when a CI red is expensive to redo: CI takes longer than ~30 min, or the change edits a shared library many checks read (for example `conformance/backlog-lib.sh`, `conformance/version-helpers.sh`, `.claude/hooks/guard-core.sh`). When in doubt, don't, but a change to the guard or secret-scan is never a case for doubt: run `--warranted`. The measurement behind this (2026-10-03, every `--warranted` line in the preceding week's review records): about 15 slices at 45-75 min per run; 2 real catches (a mass-budget overrun; a green-on-clone red plus mass budget and backlog presence), both also red in CI; one run wasted 78 min with no verdict; a CI round is about 25-40 min, plus re-binding review and GO records to the new SHA. On that evidence `--warranted` breaks even at best.

**What it recommends.** The expensive arms (`--green-on-clone`, `--exports`, `--non-vacuity <check>`, `--slow`) never run without a flag. The default ends with a recommendation block that names the arms this delta warrants and never runs one; a docs-only delta warrants nothing.

**Heavy work is serialised.** A second run on the same machine waits for the heavy-arm lock; if it cannot take the lock, its heavy units are UNVERIFIED, never OK, and the memory floor is re-read after a wait. The holder note beside the lock is display only. The `--warranted` pass cache is a local convenience, never evidence, and CI never reads it. The board-gate arm closes the board-gate gap only, not general `verify.sh` parity.

**The verdict is the last line**, always, and never imitates `verify.sh`'s `RESULT:`:
`PARITY-CORE: OK` · `PARITY-CORE: FAIL` · `PARITY-CORE: UNVERIFIED (<reason>)`. A bare `OK` means `--warranted` with everything executed; the default run prints `PARITY-CORE: OK (own surface — N CI-derived core-live check(s) not run; --warranted and CI run them)`; `--warranted` with cache skips prints `PARITY-CORE: OK (K arm(s) from cache, not executed this run)`; on a hosted-tracker tree each `loop-state` / `backlog-presence` twin whose only failure is NOT ENFORCED reads `N/A` and the OK gains the clause `TN board-bound twin(s) NOT ENFORCED locally — CI binds them`. Strict is the default (`--require` is the explicit spelling of it); `--best-effort` moves the exit code to 0 and leaves the verdict line reading what it reads.

**When CI is red.** CI must be green to merge. A failure does not by itself stop the run; once its root cause is understood, stopping the run, fixing, and re-running is the operator's judgment — until CI succeeds.

**The honest ceiling, in one sentence:** a `--warranted` green with no cache skips proves that *what the lane derived from `ci.yml` ran green under `dash`, scrubbed, on this machine*; the default run's green (`PARITY-CORE: OK (own surface — …)`) covers the change's own surface only; an arm served from cache was not executed this run — not parity with the runner's kernel, CPU count or timing, not the untouched selftests, not the heavy arms you skipped, and never a skipped reviewer.

The mechanics (the lock, the cache keys, the board arm, the touched-readers budget) are in the header of `conformance/prepush-lane.sh` and its `--help`.

## Why it matters for agentic work
An agent's inner loop is the same loop. A fast pre-commit means an agent (or human) gets format/lint/type errors back in seconds instead of waiting on a CI round-trip — **more iterations per minute, fewer broken commits, less wasted CI**. It also keeps the commit history clean (no "fix lint" follow-up commits).

## Per-stack tools → your profile
- **Hook manager:** `pre-commit` (the framework, language-agnostic) · or `husky` + `lint-staged` (JS/TS) · or native `.git/hooks` / `core.hooksPath`.
- **Fast test subset:** run only affected tests — e.g. `vitest related` / `jest --onlyChanged` (JS/TS), `pytest-testmon` (Python), `go test ./<changed-pkg>` (Go), Nx/Turborepo `affected` (monorepos).
- **Format/lint:** the stack's formatter + linter on staged files only (`ruff` / `prettier`+`eslint` / `gofmt`+`golangci-lint` / `rustfmt`+`clippy`).

## What this is — and isn't
Pre-commit is a **recommended accelerator, not a gate** (it's `--no-verify`-able by design — gating on it would just train people to bypass it). The authoritative enforcement stays in CI (§14) and the guard (pre-push). `sparkwright prepush` is the same kind of thing — a command you choose to run, whose rc no gate consumes today; it buys iterations, not authority. This tier exists purely to make the fast path *fast*.
