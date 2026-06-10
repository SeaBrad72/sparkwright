# Slice 9d-b — Runtime-Guard Portability (design)

**Date:** 2026-06-09 · **Arc:** Slice 9, Tier 1 (R4 continued) · **Version target:** MINOR → **v2.29.0**
**Input:** the review's convergent finding #2 + portability lens R4 — the destructive-action guard only protects the **Claude Code** runtime. A human at a shell, or a different agent runtime (Cursor, Aider, Continue, a CI bot), inherits **none** of the red-teamed deny-matrix. 9d shipped CI-platform portability; 9d-b ships **runtime portability** for the guard.

## Scope (split from 9d)

9d-b was split from 9d because it **edits the control-plane `guard.sh`** and is therefore human-gated at the terminal (`KIT_GUARD_SELFEDIT=1`). It is a **security surface** and earns its own design pass. Decisions ratified at brainstorm:
1. **Ambition:** core + both consumers — a sourceable `guard-core.sh` (single source of truth) **and** a universal git pre-push hook **and** a `kit-guard` CLI + documented runtime wiring.
2. **Pre-push posture:** **block** a denied push (exit 1), with `git push --no-verify` as the honest, documented escape (the git-native analog of `KIT_GUARD_SELFEDIT`).
3. **Install:** **default-on, brownfield-safe** — `incept.sh` installs the pre-push hook by default; never overwrites an existing one (warn + how-to).

## Problem

`.claude/hooks/guard.sh` (268 lines) couples three things in one file: (a) Claude-Code-specific I/O — read tool-call JSON on stdin, `jq` out `.tool_input.command` / `.file_path`, emit a PreToolUse decision; (b) the runtime-agnostic **deny-matrix** — ~30 `printf | grep -Eq` rules over a *command string* or a *file path*, each with a `"13: …"` reason; (c) the 9b control-plane self-protection. Only (a) is Claude-specific. Because (b) is welded to (a), no other runtime — and no human — can reuse the matrix the kit spent two slices red-teaming to ~91%.

## Design — extract once, consume three ways

### Architecture

```
.claude/hooks/
  guard-core.sh   NEW. The deny-matrix as runtime-agnostic functions (sourceable):
                    guard_check_command "<cmd>"  → prints "13: …" + returns 1 (deny), else 0
                    guard_check_path    "<path>" → same, for Write/Edit targets
                    guard_check_push <remote-ref> <local-sha> <remote-sha>
                                                 → push policy from real refs (see below)
                    is_control_plane_path / selfedit_allowed (9b) — moved here intact
  guard.sh        SLIMMED. Claude-Code PreToolUse adapter only: stdin JSON → jq fields →
                    source guard-core.sh → call functions → emit_deny (Claude decision JSON)
hooks/
  pre-push        NEW. Git hook (any runtime + humans). Parses pushed refs on stdin,
                    calls guard_check_push, blocks (exit 1) on deny. --no-verify bypasses.
scripts/
  kit-guard       NEW. CLI: `kit-guard cmd "<command>"` / `kit-guard path "<file>"`
                    / `--selftest`. Sources guard-core.sh; exit 0 allow / 1 deny+reason.
```

**Move, don't rewrite.** The red-teamed regex logic relocates **verbatim** into `guard-core.sh`. The only change to each rule: it `return`s a deny (with the reason on a known channel) instead of calling the Claude-specific `emit_deny`/`exit`, so each adapter decides how to surface it (Claude decision JSON · git-hook exit code · CLI exit code).

**Why functions, not a data table.** The matrix has compound rules (e.g. `rm` is denied only when the target is a glob / data-file extension / absolute path / dotfile-of-record — an AND/OR of sub-patterns). A flat `(pattern, message)` table cannot express that without losing the scalpel precision that keeps false-positives low. `guard-core.sh` keeps the imperative `if grep … → deny` chain behind two functions.

### Pre-push intent reconstruction (`guard_check_push`)

A git pre-push hook receives no command string — it gets, on stdin, lines of
`<local-ref> <local-sha> <remote-ref> <remote-sha>` (remote name/URL as args). `guard_check_push` works from real refs, which is **more precise than regex**:
- **push-to-main/master** → `<remote-ref>` equals `refs/heads/main` or `refs/heads/master`.
- **true force-push (non-fast-forward)** → `<remote-sha>` is **not** an ancestor of `<local-sha>` (`git merge-base --is-ancestor <remote-sha> <local-sha>` is non-zero). This catches a rewrite even when `--force` is not literally typed (e.g. reset-then-push).
- **new branch** → `<remote-sha>` all-zero ⇒ allow. **branch deletion** → `<local-sha>` all-zero ⇒ deny on a protected ref.

The git-push **string** rules (`git push --force`, `git push … main`) stay in `guard_check_command` for the Claude/CLI path where an agent literally runs the command. Same **policy**, two **input types**, **one file**; identical `"13: …"` messages. `guard-core-sourced.sh` (below) prevents the two from forking across files.

### `kit-guard` CLI contract

```
kit-guard cmd "<command-string>"   → exit 0 allow · exit 1 deny (reason → stderr)
kit-guard path "<file-path>"       → exit 0 allow · exit 1 deny (reason → stderr)
kit-guard --selftest               → run the deny battery through the CLI (exit 0/1)
kit-guard --help
```
The portable entry point any non-Claude runtime pipes a proposed command through:
`kit-guard cmd "$PROPOSED" || refuse`.

## Refactor safety & conformance

A control isn't real until it's regression-locked. The refactor is the highest-risk change in the kit, so:

1. **Behavior-identity proof (Claude path).** `conformance/agent-autonomy.sh` is the existing red-team regression battery (green today). The refactor is correct **iff that battery's pass/fail set is unchanged**: capture baseline → extract core + slim `guard.sh` → re-run `agent-autonomy.sh`; **every case must classify identically**. One flip = behavior drift, fixed before anything else. This makes "move, don't rewrite" executable.
2. **`conformance/guard-core-sourced.sh` (NEW)** — asserts `guard.sh`, `hooks/pre-push`, and `scripts/kit-guard` all source the **same** `guard-core.sh` (no duplicated/forked matrix). Keeps single-source-of-truth true over time: a divergence becomes a CI failure, not a code-review hope.
3. **`kit-guard --selftest`** — runs the adversarial deny battery **through the CLI** (different entry point, same corpus), proving the core denies identically regardless of adapter.
4. **`hooks/pre-push` selftest harness** — feeds simulated push tuples (force-push / push-to-main / normal feature-branch push / new branch / deletion) and asserts block/allow. The selftest IS the attack corpus (9b/9c lesson).
5. **Control-plane self-protection extends to the new files.** `guard-core.sh`, `hooks/pre-push`, and `scripts/kit-guard` are added to `is_control_plane_path` — an agent must not edit the matrix or neuter the hook (same `KIT_GUARD_SELFEDIT` human escape). The existing `core.hooksPath` denial already blocks an agent from redirecting git hooks to escape the new pre-push guard.

## incept install (default-on, brownfield-safe)

After scaffolding, when inside a git work tree:
- `.git/hooks/pre-push` **absent** → copy the reference, `chmod +x`.
- `.git/hooks/pre-push` **present** → **never overwrite**; warn and print the chain-or-rename how-to (same never-clobber discipline as the `.claude/` brownfield path).
- A next-steps line notes the local guard and the `--no-verify` escape.
- Pre-slice repos: a one-line documented manual install (`cp hooks/pre-push .git/hooks/ && chmod +x .git/hooks/pre-push`).

`incept.sh` is `scripts/` — agent-editable.

## Honesty boundary (restated per consumer)

Still a **speed bump, not a boundary**. `--no-verify` bypasses the git hook; a runtime that does not call `kit-guard` is not protected; the real boundary stays platform-owned (network-egress allowlist, separate prod credentials, sandboxed FS, scoped tokens — `docs/enterprise/platform-safety-boundary.md`). Each new surface states this. 9d-b **widens the speed bump to more runtimes and to humans**; it does not change what the speed bump is.

## Files

| File | Change | Built / applied by |
|------|--------|--------------------|
| `.claude/hooks/guard-core.sh` | **New** — sourceable deny-matrix (moved verbatim) + `guard_check_push` | build in `/tmp`, **Bradley `cp`** (under `.claude/`, `KIT_GUARD_SELFEDIT=1`) |
| `.claude/hooks/guard.sh` | Slimmed to a Claude PreToolUse adapter sourcing the core | build in `/tmp`, **Bradley `cp`** |
| `hooks/pre-push` | **New** — git hook; `guard_check_push`; block + `--no-verify` | agent |
| `scripts/kit-guard` | **New** — CLI over the core; `--selftest` | agent |
| `conformance/guard-core-sourced.sh` | **New** — all consumers source one core | agent |
| `scripts/incept.sh` | Default-on brownfield-safe pre-push install + next-steps line | agent |
| `docs/operations/runtime-guards.md` | **New** — one matrix, three surfaces; runtime wiring; honesty note | agent |
| `docs/enterprise/platform-safety-boundary.md` | Cross-link runtime-guards; restate human/other-runtime coverage | agent |
| `conformance/README.md` | Index rows: `guard-core-sourced.sh`; note kit-guard selftest | agent |
| `.github/workflows/ci.yml` | Wire `guard-core-sourced.sh` + `kit-guard --selftest` + pre-push selftest | build, **Bradley `cp`** (control-plane) |
| `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-SLICE9.md` | 2.29.0; 9d-b row → shipped | agent |

## Verification

- `conformance/agent-autonomy.sh` → **identical** pass/fail set before vs after the extraction (behavior-identity proof). The existing 31+ cases still pass; none weakened.
- `kit-guard --selftest`, `hooks/pre-push` selftest, `guard-core-sourced.sh` → all green; wired into kit CI.
- `dash -n` clean on `guard-core.sh`, `guard.sh`, `hooks/pre-push`, `scripts/kit-guard`.
- `incept.sh` in a temp git repo installs `.git/hooks/pre-push` when absent; warns + does not overwrite when present; default-on without a flag.
- Manual push fixtures: a simulated force-push and push-to-main are blocked; a normal feature-branch push and a new-branch push pass; `--no-verify` bypasses (documented).
- `check-links.sh` green; kit CI (`conformance`/`bootstrap`/`docs-links`) green.
- Governance: feature branch → PR → **human ratification** (Bradley merges); builder ≠ sole reviewer; the guard refactor (governing/security surface) gets the security-owner lens before the PR.

## Out of scope / deferred

- **PATH-shims — the named coverage-depth upgrade.** The pre-push hook enforces only the git-history denials (all a git hook can see); the `kit-guard` CLI covers the full matrix but needs the runtime to call it. The way to get *automatic* full-matrix coverage off-Claude — for any runtime AND humans, with **no** runtime integration — is a future `kit-guard install-shims` mode: drop tiny wrappers for the dangerous binaries (`rm`, `dropdb`, `kubectl`, …) into a dir prepended to `PATH`, each running `kit-guard cmd "…" || exit` then `exec`-ing the real binary. It is just another consumer of the same core, so 9d-b's architecture makes it a small addition — but it is **invasive with sharp edges** (non-interactive shells, absolute-path bypass, `PATH` ordering, perf) and earns its own opt-in slice. Named here so the coverage ceiling is honest.
- **Windows-native (non-POSIX) guard — deliberately NOT done.** A PowerShell/cmd port would be a **second implementation** of the red-teamed matrix, forking single-source-of-truth and doubling the red-team burden. The hooks are POSIX `sh`; Windows adopters run them under **WSL / Git-Bash**, where they work unchanged. The docs state this positively (use WSL/Git-Bash; do not fork the matrix).
- **Per-runtime first-party plugins** (a Cursor extension, an Aider plugin). Those runtimes already inherit the universal pre-push hook and can wire `kit-guard`; a packaged per-runtime plugin couples to that runtime's internals for marginal gain. **Demand-driven** — build only if a real adopter on that runtime requests it, not speculatively.
- Expanding the deny-matrix itself (new destructive tools). 9d-b is a **portability** slice — it moves the existing matrix without changing what it denies. Matrix growth is its own change, regression-locked separately.

## Known implications

- The pre-push hook protects against the **git-history** denials only (force-push, push-to-main) — that is all a pre-push hook can see. Full command-matrix coverage off-Claude requires a runtime to call `kit-guard`. Documented, not implied.
- `guard_check_push`'s ancestor check needs the remote sha locally; on a brand-new remote with no fetched history the check degrades to "allow new branch" (correct) rather than failing closed on a fetch error. Stated in the hook.
