# sparkwright doctor — reference

**`sparkwright doctor` is an adopter-facing POSTURE command** that composes the kit's mechanizable
conformance and drift-detection checks into one sweep. It automates the mechanizable drift axes
(D claim-integrity, E git ground-truth) from [`drift-self-check.md`](./drift-self-check.md) — the
semantic axes (intent/scope, plan alignment, overclaim judgment) remain agent/human judgment.

## What it composes

```
sparkwright doctor
  ├─ conformance/verify.sh       [GATING]    every registered conformance check
  ├─ conformance/claims-registry.sh [GATING] every headline claim's verifier (kit-self; N/A on an adopter tree)
  ├─ git ground-truth            [ADVISORY]  branch, dirty-tree, tag alignment
  └─ conformance/kit-current.sh  [ADVISORY]  is the kit you ADOPTED behind the current release?
```

Run via `sh scripts/sparkwright doctor` (or directly: `sh scripts/doctor.sh`).

## Posture (gating) vs metrics (informational)

The split is intentional and the naming is exact.

**POSTURE** — the default output. Four dimensions:

| Dimension    | Role    | What it runs                                       |
|--------------|---------|----------------------------------------------------|
| `conformance`| GATING  | `conformance/verify.sh` (all checks)               |
| `claims`     | GATING (kit-self) | `conformance/claims-registry.sh`; `N/A (kit-self…)` on an adopter tree |
| `git`        | ADVISORY| branch · dirty-tree · tag alignment                |
| `kit-update` | ADVISORY| `conformance/kit-current.sh` — adopted kit vs current release |

A FAIL or UNVERIFIED on either gating dimension sets exit 1. The git dimension is ADVISORY only
(WARN-level, never hard-fails alone) — it re-establishes ground truth (axis E from
`drift-self-check.md`) without blocking a green posture on working-branch commits.

### The `kit-update` dimension — the surfacing

A recurring failure is a capability that is built,
conformance-checked, and **invisible in practice**. *An updater nobody is ever
prompted to run **is** that failure.* So the surfacing is not a nicety bolted onto `kit-update` — it is
the half that makes it exist. `doctor` is the adopter's **decision point**: the moment they are already
asking "what is my posture?". That is where they are told.

`conformance/kit-current.sh` compares the version this project **adopted** (`kit-base:VERSION`, a fact
recorded at inception) against the newest release **tag** at the kit source (`git ls-remote` — the git
protocol, **no forge API**). It renders as one row:

| Check's exit | Row | Meaning |
|---|---|---|
| `0` | `kit-update  OK` | up to date (or ahead). **One quiet line — an up-to-date adopter is never nagged.** |
| `1` | `kit-update  WARN` | **BEHIND** — names `v<OLD>` → `v<NEW>` and the exact `kit-update` command to see the delta. |
| `2` | `kit-update  N/A` | UNVERIFIED — the source is unreachable (offline). Staleness is **unknown**, and is *not* assumed OK. |
| `3` | `kit-update  N/A` | Not an adopted tree (no `kit-base`) — e.g. the kit's own repo. Decided with **no network at all**. |

**Why ADVISORY and never a gate.** *Being behind is not a defect.* A project pinned to last month's kit
is making a legitimate choice — often the right one. A PR gate that reddened on it would fire on the
happy path of every adopter, every week, and people would learn to ignore it; then it is worth nothing
when it fires for real. It can never fail a build. (Same call as the kit's own mirror-currency cron, which stays kit-only — a staleness check
belongs in `doctor`/drift-watch, not in `verify.sh`.) The two halves are equally load-bearing: the
adopter **must** be told when they are behind, and **must not** be nagged when they are not.

**Honest ceiling.** It compares *versions*, not *trees*: `OK` means "no newer release is tagged at that
source" — it does not mean your tree is unmodified, and it does not compute the delta. Computing the
delta is `kit-update`'s job, and it is the thing this row tells you to go and run.

**METRICS** (`--full` only) — appended after the posture summary, clearly labelled
*"METRICS (informational — does not affect exit)"*. Runs `scripts/dora.sh`.

**Why metrics never gate:** DORA is a *measurement tool*, not a pass/fail gate.
DORA measures deployment frequency, lead time, change failure rate, and restore time — the kit's
principle is that metrics measure, they don't gate. A missed DORA collection is an observation gap,
not a posture failure. Collapsing measurement and gating mixes signal and noise, and makes `--full` produce false
CI failures on untracked repos or fresh clones. The two concerns are deliberately separate.

## Flags

| Flag        | Effect |
|-------------|--------|
| *(none)*    | Posture sweep. Exit 1 on GATING FAIL. UNVERIFIED → warn only. |
| `--require` | Strict: UNVERIFIED also exits 1. Auto-set inside CI (`$CI` env). |
| `--full`    | Posture + metrics (informational). Exit code unchanged by metrics. |
| `--quick`   | The advisory lines only: skips conformance and claims, which read `UNVERIFIED (skipped by --quick…)`. Never a pass; see below. Refused (exit 2) with `--full` and with `--as agent`. |
| `--boundary`| The agent-boundary static leg: runs `scripts/doctor-boundary.sh` instead of the posture sweep. One verdict from preflight's scope reader, guard-wired's grader and the opt-out declaration on origin's default branch; exit 0, 1 (an UNDECLARED opt-out, a malformed or UNTRUSTED declaration, an unreadable declaration while a part is OFF, or a grader FAIL) or 2 UNVERIFIED (1 under `--require`/CI). `--boundary-offline` (typed on the command line, never an environment variable; anyone can pass it) turns the unreadable-declaration FAIL into a loud WARN and the verdict into UNVERIFIED (exit 2, 1 under `--require`), never PASS; it never relaxes UNTRUSTED. CI counts only with no TTY attached (CI set in a terminal is judged as a human terminal, with a WARN). Reads settings, writes nothing; refused (exit 2) with `--full`, `--quick` and `--as`. See `runtime-guards.md`, "The agent boundary: on by default". |
| `--selftest`| Built-in regression test: stubs the composed commands, verifies the render contract and exit-code logic. Run in CI as `scripts/doctor.sh --selftest`. |

### The `secrets-in-tree` and `secrets-in-env` lines

Two advisory lines, printed after the forge lines, **names only** (never a file's content or a variable's value). `secrets-in-tree` lists secret-named files in the working tree (the guard's name set, templates excluded, `.git` and `node_modules` skipped, at most 20 shown with a count); WARN, or FAIL under `--require`. `secrets-in-env` lists secret-looking variable names in the session's environment; WARN. A name check misses a secret under an innocent name, and listing removes nothing. Names alone may be sensitive (a customer name in a path, for example) and they appear in CI logs. A subtree the walk cannot read is named on the line, never read as OK. See [`secrets-for-ai.md`](secrets-for-ai.md).

### The `checkout-git` row

One advisory row, printed **first**, before the conformance battery, from `sh scripts/preflight.sh --git-plants-only` (which you can run alone: it prints the same report and nothing else). It reads git's redirect and config files in this checkout (a nested `.git` entry, `.git/commondir`, a worktree or submodule entry that points elsewhere, an exec key in a git config, a bare layout, a pending rebase `exec` line, a `core.hooksPath` inside the checkout, and a link to a directory that holds a `.git`). It reduces blind spots and certifies nothing.

| Row | Meaning |
|---|---|
| `OK` | Nothing found among the keys it knows (**known keys only**: the list of exec keys is written from memory of git's documented keys, so a key it does not name is not reported). |
| `WARN` | One or more findings, each printed under the row, names only, never a file's content or a config value. Doctor's next checks run git: stop here and read this first. |
| `N/A UNVERIFIED` | The checkout was not cleared, for one of three causes, named on the row. (1) `./.git` is a gitfile (or a git environment variable redirects git): this session is a linked worktree or a submodule, or a plant, and this check cannot tell which; it ran no git and read no config, and the dirty check is off. (2) A nested `.git` file names one of this repository's worktree entries: a linked worktree or a plant; the dirty check runs anyway, and the overall line reads `Overall: WARN`, never PASS. (3) A nested `.git` file names a recursive submodule's git directory; the dirty check is off. |
| `N/A` | No `./.git` here (not a repository root, or run from a subfolder), or no `scripts/preflight.sh`. |

- **It runs no git in a nested directory, and no index read after an exec-key finding.** The batteries after it (the conformance battery, the claims registry) DO run git: a planted `core.fsmonitor` or a filter driver fires from them. Doctor does not stop on a finding and no exit moves: the row is a warning, never a gate, under `--require` too. A finding is the moment to stop and inspect without running git.
- **The skip rule.** The dirty check (`git status`) runs only when a fresh read of the report, taken immediately before it, reads `OK`. Any finding, or an unreadable report, leaves the dirty check `UNVERIFIED`, except two exempt lines (see "The dirty check rule" below): a `core.hooksPath` set in the repository's own config, and a worktree-shaped nested gitfile. Those are still printed and never called fine. If the two reports differ, the git row says so.
- **A nested worktree reads `N/A UNVERIFIED`, and the dirty check runs.** A nested `.git` file that names `./.git/worktrees/<one name>` (judged by that shape, never by the path it sits under: an agent can write under `.claude/worktrees` too) is a linked worktree or a plant, and this check cannot tell which, because the records git keeps for a worktree are files an agent can forge. The check prints an `info` line naming the path and an `unverified` line; the row reads `N/A UNVERIFIED`, never `OK`, names this cause and says the check is uncertain and that the dirty check runs anyway (its own row gives the result). A nested worktree reads `Overall: WARN`, never PASS. It does so because `status` runs on `./.git` with `--work-tree=.` and does not enter the nested directory (proved with a canary in the selftest: a plain `git status` inside the nested directory fires a planted `core.fsmonitor`, alias and hook; doctor's form does not). A nested gitfile that names a **recursive submodule's** git directory also reads `N/A UNVERIFIED` (its parent submodule's index is not read), but there the dirty check stays off.
- **The dirty check rule.** It runs only when a fresh read of the report holds no `warn` and no `unverified` line other than the two exempt ones: a `core.hooksPath` set in `./.git/config` or `config.worktree` (inside the checkout or under a temp directory, where a sandboxed agent can write; `status` runs with `-c core.hooksPath=/dev/null`), and the worktree-shaped nested gitfile's `unverified` line. It stays off for any other `warn`, for a config git cannot parse, for a worktree entry whose `HEAD` is not a regular file or a symlink, for a submodule whose index name is quoted (not classified), and whenever no git was run or the report could not be read. An exempt finding still prints, and the row is never `OK`.
- **What the row cannot see.** Keys it does not know (the allow-list is from memory, not git's source); a tracked `.git` that `status` does not show; an absolute `core.hooksPath` that reaches the checkout through a symlink or a differently cased path (a plain prefix test: a value with `..`, `//`, `/./` or under `/proc` counts as inside, nothing else is resolved); a worktree's own records (forgeable, so not read); a recursive submodule's parent index; and git run before doctor. It reduces blind spots and certifies nothing.
- **The ceilings.** It reports after the fact (git run before doctor, Claude Code's own start-up git included, may already have run a plant). An agent can edit `scripts/preflight.sh` before you run it. The walks are unbounded, and a file can change between the check and the read. A same-user agent can race the window between the fresh read and git's start.
- **Inside GitHub Actions the row reads `WARN`.** `actions/checkout` sets its own `includeIf` keys in `./.git/config`, so `checkout-git` reads WARN there and the dirty check is off; no exit moves. A key prints as `section.*.variable` (for example `includeif.*.path`, `url.*.insteadof`): the subsection is withheld because it can hold a credential, and a found path shaped like a credential (a colon, then an `@`) is withheld too. Names only.

### The `merge relationship:` line and the `kit-update` row read origin from outside the checkout

Doctor asks origin for `.kit/dials.conf` and `CLAUDE.md` on its default branch, and `conformance/kit-current.sh` (the `kit-update` row) asks the release source for its tags, **from `/`, outside any repository**. This checkout's own `.git/config` therefore does not apply to those two questions: a planted `core.sshCommand`, `url.*.insteadOf`, `credential.helper`, `protocol.ext.allow` or `remote.origin.uploadpack` cannot run a program or send them to a decoy. Your global git config, ssh-agent, keychain and the environment (including `GIT_SSH_COMMAND`, `GIT_CONFIG_COUNT` and the sandbox's proxy login) still apply.

**It authenticates nothing.** A rule in your global config, an edited `kit-base` or `scripts/publish-public.sh`, or an origin an agent repointed can still forge the answer, and a green `kit-update OK` still means "no newer tag at that source", not "this source is the kit". The verbs (`land`, `actuate`, `kit-update`) still read origin with the checkout's config; doctor does not, so the two can differ, and the rows say so.

**While the `checkout-git` row has a finding, or could not clear the checkout, doctor makes no network read for the merge line.** (The skip is on any finding, because a git without the `GIT_NO_LAZY_FETCH` belt would let a planted partial clone fetch from doctor's later local reads; Apple git 2.39.5 honours the variable [M], and which releases lack it is unmeasured, so the skip does not rest on the variable being absent. Two findings do not skip it: a `core.hooksPath` in the repository's own config, and a worktree-shaped nested gitfile; there the read goes ahead, from outside the checkout.) The line then reads, by cause:

| Row | Cause |
|---|---|
| `not read - the checkout-git row above has a finding` | clear the finding, or read `.kit/dials.conf` on your forge. **GitHub Actions lands here**: `actions/checkout` sets `includeIf` keys, so the row reads WARN (above), and a CI user cannot clear that; read the file on your forge |
| `not read - checkout-git could not clear this checkout` | no clearing report: `./.git` is a gitfile (a linked worktree, a submodule), a recursive submodule's nested gitfile, no `./.git` at all, a git variable redirecting git, or an unreadable report. Run doctor from the main checkout, or fix what the `checkout-git` row names |
| `not read - scripts/preflight.sh is not here` | restore it |
| `not read - git status failed in this checkout` | fix what the `git` row reports |
| `unknown - could not read origin's default branch` | offline, no access, or a network setting (`http.proxy`, `http.sslCAInfo`, a per-repository SSH key or URL rule) kept only in this checkout, which this read does not use |
| `unknown - could not read .kit/dials.conf at origin's tip here` | the tip is not fetched (`git fetch origin`), or the file is not a regular file |
| `unknown - origin is not a network URL (https or ssh)` | a local path, `file://`, or a helper form. A network URL here is `https://`, `http://`, `ssh://`, `git://` or scp-like `host:path` |

All are INFO: no warn, no exit moves. **Who loses the line:** people who keep SSH keys or URL rules per repository (until they clear the finding), every linked-worktree session, GitHub Actions runs, people with a global `includeIf` split or a repo-only proxy, who may get no warning naming why, and a genuine `blob:none` partial clone whose `kit-base` blob is absent, whose `kit-update` row reads UNVERIFIED where a plain read would fetch the blob. The line also carries the prompt to declare a merge relationship, so an undeclared adopter in any of these setups is not prompted until doctor runs somewhere clean. **How many people this is: unknown** (there is no adopter census). If `merge relationship: unknown` sits beside `checkout-git: OK` and an origin you can reach, the read itself may be broken: report it.

Two more limits. A credential embedded in origin's URL is on the command line of these reads, visible to `ps` while they run (the verbs' own calls pass the name `origin`, so git reads the URL itself; here the URL is an argument, which is more exposed). And if `/` is itself a git repository, `git -C /` reads that repository's config; neither script guards against it. **The adopted version read:** `kit-current` reads `kit-base:VERSION` locally from the branch (not a tag of the same name), with no network transport and no lazy fetch, because a git without the `GIT_NO_LAZY_FETCH` variable would let a planted partial clone fetch over the checkout's own config (Apple 2.39.5 honours it [M]; which releases lack it is unmeasured). kit-current's selftest tests that protection with a stand-in git that drops the variable, and with `/usr/bin/git` as a second row when it is a separate runnable git (gated on its own measured control); doctor's own partial-clone cell does the same. With `GIT_ALLOW_PROTOCOL=none` a real 2.39.5 read gave canary 0 for `uploadpack`, ssh, `ext::`, `include.path` and `remote.*.vcs` [M].

A repo-only rule that sent the public kit URL to a mirror no longer applies to `kit-update`: it reads the public URL, and reads `N/A` (UNVERIFIED) with a warn if that is blocked. Move the rule to your global config, or run `sh conformance/kit-current.sh --from <mirror>` yourself (doctor cannot pass `--from`). `kit-current` classifies a `--from` first (`scripts/preflight.sh --url-kind`): a helper form (`ext::`), an option-shaped value or a missing `preflight.sh` is UNVERIFIED (exit 2), never BEHIND. Not covered here: `board-claim.sh`'s read, the `kit-update` wrappers, doctor's FIFO read, `release-tag.sh` and `doctor --boundary`.

## Progress, the estimate and `--quick`

A full run on a real tree takes tens of minutes, so doctor says where it is. **Everything below is on stderr**; stdout is
byte-identical to a run without it. A `--selftest-e2e` run stays silent.

```
doctor: 7 steps; estimate 25-50 min on an adopter tree (an estimate from the 2026-10-14 field run; ...). Use --quick for the advisory lines in under a minute.
doctor [1/7] conformance battery (conformance/verify.sh) ...
doctor [1/7]   row 3/<T> agent-autonomy PASS (14m02s)
doctor [1/7] done in 41m10s (row <T>/<T> reported)
doctor [2/7] claims registry: N/A on this tree (kit-self), skipped
...
doctor: finished in 41m31s
```

- **`[k/N]`** counts the steps this run will enter, from the same predicates the dimensions use, so k ends at N on a normal
  exit. The default run has up to 7 (conformance, claims, git, kit-update, permissions, the tracker credential line when a
  `.kit/tracker.conf` exists, the forge identity line); `--full` adds three metric steps.
- **`row i/T name STATUS (elapsed)`** relays one line per result row of `verify.sh`. `T` is read at run time from the
  `^check ` lines of `conformance/verify.sh`; no count is written down anywhere. The time is elapsed, not an ETA: row times
  vary by two orders of magnitude, so an extrapolation would be wrong where it matters most.
- **The verdict never comes from that stream.** `verify.sh`'s exit status travels through a status file (POSIX `sh` has no
  `pipefail`). A status file that is missing, empty or not a number (an interrupted run, a killed child) renders
  `conformance FAIL`, never PASS.
- **The estimate is a dated sentence, not a computation.** Doctor mutates nothing, so it cannot remember an earlier run. The
  figures are 25-50 min on an adopter tree (verify alone) and 55-95 min on the kit's own tree (verify, then a claims registry
  that runs the guard battery again). **Re-measure them at each MINOR** from the `done in` lines of a real run and change the
  sentence in `scripts/doctor.sh` (`_pg_announce`) and the figures here together.

**`--quick`** skips exactly two steps, conformance and claims, and still runs git, kit-update, permissions, the tracker
credential line and the forge identity line. It prints its own estimate (`doctor: --quick: N steps; estimate under 1 min
(plus up to about 20 s of bounded tracker reads); conformance and claims are NOT run.`).

- The conformance row reads `UNVERIFIED (skipped by --quick: run doctor without --quick for this verdict)`. So does the
  claims row on a kit-marked tree. On an unmarked (adopter) tree claims stays `N/A (kit-self…)`, because the dimension does
  not apply there, skip or not.
- **Overall is never PASS under `--quick`.** Not required: `Overall: WARN  (--quick: conformance and claims were NOT run;
  this is not a pass. …)`, exit 0. Required (`--require`, or `$CI` set): `Overall: FAIL  (--quick under --require/CI: the
  gating dimensions were skipped, not failed. …)`, exit 1. A required verdict cannot be quick.
- `--quick --full` and `--quick --as agent` (either order) are usage errors, exit 2.

**The claims registry runs a repeated verifier once.** Inside one `claims-registry.sh` pass, a verifier string that already
ran reuses its recorded exit code and output (the memo is shell variables in that process, no file or flag). Every row still
prints its own PASS, UNVERIFIED or FAIL line under its own id, and a non-pass prints its diagnostics on every row it covers.
Today that is the three claims that share one orchestrator-loop wiring check.

## Graceful degradation in adopter repos

A missing composed script is **never a false PASS**:

- `conformance/verify.sh` not present → `conformance: UNVERIFIED (not present)` (WARN; exit 1 under `--require`)
- `claims` is **kit-self**: the registry grades the kit's own headline claims, so on a tree with neither kit marker (`docs/ROADMAP-KIT.md`, `.github/workflows/golden-path.yml`) — every exported or incepted project — the row reads `claims N/A (kit-self…)`, runs nothing, and adds no WARN and no failure (also under `--require`). Your project's own claims are not graded here.
- On a kit-marked tree, `conformance/claims-registry.sh` not present → `claims: UNVERIFIED (not present)` (WARN; exit 1 under `--require`)
- `scripts/dora.sh` not present → `N/A (not present)` in the metrics section

An adopter who hasn't wired the full conformance suite yet sees honest UNVERIFIED/N/A, not a green
check that proves nothing.

## Honest ceiling

`sparkwright doctor` automates the **mechanizable** drift axes:

- **D (claim-integrity)** — re-runs every registered claim's verifier via `claims-registry.sh` (kit-self; N/A on an adopter tree).
- **E (git ground-truth)** — re-establishes branch, dirty-tree, and tag alignment without trusting stale in-context memory.

It does **not** detect **semantic drift** — intent vs accepted spec, plan alignment, or whether a
doc overclaims what a control actually does. Those are judgment calls that require reading
intent, not running a script. They remain the agent/human checkpoint in
[`drift-self-check.md`](./drift-self-check.md) (axes A/B/C and the judgment half of D).

**A green `sparkwright doctor` does not mean "the project is correct."** It means the registered
conformance checks pass, the claims are backed by passing verifiers, and git state is what you
expect. Correctness — whether the right thing was built and the docs accurately describe it — is
still agent/human territory.

## Control-plane protection

`scripts/doctor.sh` and `scripts/sparkwright` are in the guard's named control-plane set. An
unratified edit to either file is denied by the guard and flagged by the `agent-boundary` CI gate.
A governance tool that the agent it governs can silently rewrite is not a governance tool.
