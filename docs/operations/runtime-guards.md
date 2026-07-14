# Runtime Guards — Portability Reference

How the kit's destructive-action deny-matrix protects **more than the Claude Code runtime**. One matrix (`/.claude/hooks/guard-core.sh`), four surfaces. The executable half of `DEVELOPMENT-PROCESS.md` §13 for non-Claude runtimes and humans.

> **Principle — one matrix, many surfaces; still a speed bump.** The deny-matrix is the single source of truth; each surface reuses it. None of them is a security boundary — `--no-verify`, a runtime that never calls `kit-guard`, or an interpreter still bypasses it. The real boundary is platform-owned (`../enterprise/platform-safety-boundary.md`).

## The one matrix
`/.claude/hooks/guard-core.sh` exposes five pure functions — each prints a `13: …` reason and returns 1 on deny, 0 on allow:
- `guard_check_command "<cmd>"` — the destructive-command matrix (rm, dd, SQL/DDL, migration resets, cloud/cluster destruction, prod-context, exfil, control-plane) **plus the secret-in-context read deny (H3a): a content-read verb (`cat`/`grep`/`diff`/`source`/…) targeting secret material (`.env*`/`.pem`/`.key`/`id_rsa`/`secrets/`) is human-gated** — reading a secret into the agent's context is the read half of exfil. **As of S6 the matrix also denies `gh pr merge --admin`/`--administrator`** — the branch-protection *bypass* (it overrides `control-plane-ratification` and the required-review SoD). This is a **speed-bump, not the boundary** (see *Honesty boundary* below): the sanctioned agent path is a **normal** merge on a recorded, authenticated GO (`scripts/promotion-verify.sh actuate`); solo, `--admin` stays the human's one act (the kill-switch).
- `guard_check_path "<file>"` — secret-material + control-plane **write** protection. **As of 3.17.0, the secret-WRITE deny enumerates the same `.env.<suffix>` set as `guard_check_read`** — `.env*`, `.pem`, `.key`, `id_rsa`, `secrets/` — with the same template allow-list (`.env.example`/`.sample`/`.template`/`.dist`). This closes the read/write parity gap for secret-material enumeration (previously `guard_check_path` enumerated only `.env.local`/`.env.production`/`.env.development`). Note: the control-plane **read ⊊ write asymmetry** (H3a) is unchanged — `guard_check_read` does NOT deny control-plane reads; this parity is specifically about secret-material enumeration.
- `guard_check_read "<file>"` — the **Read-tool** secret deny (H3a). Symmetric with the secret-write deny but **narrower: it does NOT deny control-plane reads** (reading the guard/CI to understand it is legitimate); `.env.example`/`.sample`/`.template`/`.dist` are allowed. Wired via the `Read` matcher in `settings.json`.
- `guard_check_push <remote-ref> <local-sha> <remote-sha>` — force-push / push-to-main, from real refs.
- `guard_check_mcp "<tool>" "<allowlist>" "<overrides>"` — the MCP capability gate (Slice 11a): classifies an `mcp__<server>__<action>` tool by its action verb and denies un-allowlisted destructive/egress capabilities (fail-closed). Pure — the adapter loads `.claude/mcp-policy.json` and passes it in.

> **Secret-in-context ceiling (H3a, honest).** The two read denies stop the agent's **default** exfil-read paths (shell `cat .env`, the Read tool) but are a speed bump, not containment: an **interpreter** (`python -c "open('.env')"`), an uncommon content-emitter not in the verb list, or an exotic `.env.<custom-suffix>` on the *shell* path can still read a secret; `jq`-absent leaves the Read tool allowed; non-Claude harnesses get the shell deny via `kit-guard cmd` (no Read tool). The real boundary is the platform egress allowlist + sandboxed FS (`../enterprise/platform-safety-boundary.md`).

`conformance/guard-core-sourced.sh` asserts every consumer sources this file (no forked matrix).

## The four surfaces
| Surface | File | Covers | Cooperation |
|---------|------|--------|-------------|
| Claude Code | `.claude/hooks/guard.sh` (PreToolUse) | command + path + MCP-tool (`mcp__.*`) | automatic in Claude Code |
| Any git client | `hooks/pre-push` → `.git/hooks/pre-push` | git-history (force-push, push-to-main) | none — every runtime + humans |
| Any other runtime | `scripts/kit-guard` CLI | full command + path matrix | runtime pipes commands through it |
| CI (any harness) | `conformance/agent-boundary.sh` + `gate-agent-boundary` job | control-plane-diff ratification | automatic on every PR — the harness-independent floor |

### Wiring a non-Claude runtime
Pipe each proposed shell command through the CLI before running it:
```sh
kit-guard cmd "$PROPOSED_COMMAND" || { echo "blocked by kit guard"; exit 1; }
```
**Treat any non-zero exit as block** — `1` = denied, `2` = core not found / usage error. The `||` form above does this correctly; do **not** key only on `-eq 1`, or a missing core (exit 2) would be mis-read as "not denied." `kit-guard` resolves the core relative to itself, or via `KIT_GUARD_CORE=/path/to/guard-core.sh`. Examples:
- **Cursor / Aider / Continue:** they already inherit the universal `pre-push` hook; for command coverage, wire `kit-guard cmd` (full-string) into the runtime's pre-command step where one exists, or `kit-guard install-shims` (single-invocation PATH-shims; see *Coverage depth* below) where none does. A first-party plugin per runtime is intentionally not shipped (build on demand).
- **CI bots / scripts:** call `kit-guard cmd …` before executing a templated command.

### Git pre-push
Installed by `incept.sh` by default (brownfield-safe; never clobbers an existing hook). Blocks force-push and push-to-main locally, before the network round-trip — complementing remote branch protection, and covering remotes that have none. Deliberate override: `git push --no-verify`.

## Windows
The hooks are POSIX `sh`. On Windows, run them under **WSL or Git-Bash**, where they work unchanged. The matrix is **not** ported to PowerShell/cmd — a second implementation would fork the single source of truth and double the red-team burden.

## MCP capability gate (the mcp-policy contract)

The guard sees MCP tool calls too (Claude PreToolUse matcher `mcp__.*`). `guard_check_mcp` (in `guard-core.sh`) classifies each `mcp__<server>__<action>` by **tokenizing the action** (camelCase→snake, lowercased) and matching whole tokens against verb sets — then **denies un-allowlisted destructive/egress capabilities by default** (fail-closed):
- first token is a **read-only** verb (`read/get/list/search/query/fetch/describe/show/view/find/count`) → allow;
- **any** token is a **destructive/egress** verb (`delete/drop/create/update/write/upload/publish/deploy/send/post/email/apply/merge/push/revoke/rotate/export/download…`) → deny, naming the class. This wins over a read prefix, so `get_and_delete` and `fetchAndExport` deny, while legit read compounds stay allowed because the noun is not the verb (`list_deployments`≠`deploy`, `get_updates`≠`update`);
- **secret-material reads** are deny-by-default even when a read verb leads (A8 family 6 — the read half of exfil): an action naming a secret (`secret/credential/password/api_key/private_key/access_token…`) **or** a known secret-store server (`vault/1password/secretsmanager/keyvault/doppler…`) on a read → deny;
- anything else (no read-verb lead, no destructive token — including non-verb lookalikes like `getter`/`counter`) → **deny (fail-closed)**.

**Policy** (`.claude/mcp-policy.json`, control-plane-protected): `{ "allow": ["mcp__server__action" | "mcp__server__*"], "classOverride": { "mcp__x__export": "read" } }`. Shipped empty — a project allowlists what it needs. **Prefer exact-tool allows over `mcp__server__*` wildcards** — a wildcard admits *every* tool on that server, destructive ones included, bypassing classification. **Portable:** any runtime calls `kit-guard mcp "<tool>" [policy]` to apply the same gate. `conformance/mcp-policy.sh` is the classification corpus **and** asserts the matcher is wired (no green-while-dark).

**Honest ceiling:** this gates *what the tool name reveals*. A deliberately renamed action (a `get_data` that exfiltrates), a **secret read via a generic-named server/action** (`mcp__storage__read_blob` holding a credential), a server wildcard you granted, or a server hiding capability behind a read-looking name is **not** caught; and the egress class is a **name-match speed bump, not egress containment** — real exfiltration defense is the platform network-egress allowlist + the sandboxed filesystem (`../enterprise/platform-safety-boundary.md`, `containment.md`). Conversely, the secret-store **name** match errs toward deny: a benign server/action that merely *contains* a secret keyword (`mcp__datavault__query`, `list_secret_scanning_alerts`) is denied by default — allowlist it (or `classOverride` to `read`) to recover. Deny-by-default favours safety.

## Coverage depth (honest ceiling)
The `pre-push` hook enforces only the git-history denials (all a git hook can see). `kit-guard cmd` covers the full matrix on the **full command string** — the strongest off-Claude path — but needs the runtime to call it from a pre-command hook. For runtimes with **no** command hook, `kit-guard install-shims` installs PATH-shims that wrap the curated dangerous binaries and call `kit-guard` before `exec` — automatic, no per-command integration, but with a real and specific ceiling:

- **Single-invocation only.** A shim sees **one binary's argv, *after* the shell has parsed the line**, so it catches direct destructive calls (`rm -rf`, `git push origin main`, `dropdb`, `dd of=/dev/sda`) but is **blind to everything the shell composes** — pipes/redirects/chaining (`curl | sh`, `> <control-plane-path>`, `find -exec rm`, `a && rm -rf`). This is *not* full-matrix coverage; the full-string check is `kit-guard cmd`.
- **Absolute-path & interpreter bypass.** `/bin/rm` (or `./rm`) skips PATH lookup, so the shim never runs; `python -c`/`node -e` are the interpreter channel. Interpreters and `find`/`xargs`/`sed`/`cp`/`mv` are deliberately **not** shimmed (composition/read-only escapes, or breakage > value).
- **Integrity is platform-owned.** A shim is only as trustworthy as its directory is unwritable — an agent on a writable shim dir can rewrite a shim to a no-op. Install onto a **read-only mount** (`containment.md`); `install-shims` warns when the target looks writable.

Net: shims raise the floor for non-Claude runtimes on the **common direct-call mistake**, while the full-string `kit-guard cmd` hook and the platform boundary (`../enterprise/platform-safety-boundary.md`) remain the stronger controls.

### Installing the shims
`kit-guard install-shims [--dir <d>] [--force]` writes a shim per curated binary (`rm dd truncate shred wipefs blkdiscard mkfs dropdb psql mysql mariadb sqlite3 mongosh pg_restore redis-cli git npm yarn pnpm kubectl rsync` — the single-invocation rules), prints the `export PATH="<dir>:$PATH"` line, and warns on a writable target. Each shim reconstructs its argv, runs `kit-guard cmd`, and on allow execs the **real** binary (resolved as the first PATH entry that is not the shim dir — so it never recurses). `conformance/shim-coverage.sh` proves the generated shims deny + allow + pass through (exit code/stdio) + don't recurse.

## Honesty boundary
Each surface is a speed bump for honest mistakes, not containment of a hostile process. It is bypassable by design and does **not** claim to block every write/exfil path. **Local git only:** the git surfaces here (`pre-push`, `guard_check_push`) act *locally*, before the network round-trip. A **server-side `gh pr merge --admin`** is a GitHub API call — a different transport entirely — and is outside the guard's reach. **The S6 `--admin` deny is a local speed-bump, not this boundary:** it makes the bypass loud in the guard's own reasons and stops the honest-mistake local invocation, but a token with admin scope can still call the API directly (or a non-Claude runtime can). **The real boundary is credential-side — never issuing the agent an admin-scoped token** (`../enterprise/platform-safety-boundary.md`); a `gh` with only normal-merge scope simply *cannot* bypass. The boundary on *who merges* is GitHub branch protection + the agent's sanctioned path — a **normal** (non-`--admin`) merge on a recorded, authenticated GO via `scripts/promotion-verify.sh actuate` (team), or preparing the PR and handing the human the `--admin` kill-switch merge (solo) — see [`review-lane.md`](./review-lane.md), **not** the guard. Known bypass classes (all within this ceiling, not regressions): `--no-verify`; an uncooperative runtime; a language interpreter (`python -c`, `node -e`); a redirect/printf that writes a file without invoking a denied verb; an upload via `curl --data @file` / interpreter; and history-application like `git am` / `git apply`. The boundary that actually contains these is platform-owned — adopt the guard **with** the network-egress allowlist, separate prod credentials, sandboxed FS, and scoped tokens (`../enterprise/platform-safety-boundary.md`).

## Doing control-plane work — the sanctioned route (READ THIS BEFORE REACHING FOR THE KILL SWITCH)

The guard **correctly** denies an agent editing `conformance/`, `.github/workflows/`, `.claude/`,
`scripts/kit-guard`, `CODEOWNERS`, … — that is its job, not a bug. But real control-plane work still has
to happen (a CI gate needs fixing, a conformance check needs writing). **There is a sanctioned way to do
it with the guard fully armed, and it is NOT `KIT_GUARD_SELFEDIT`.**

### The dev-clone affordance (CP-8c, v3.124.0) — the default

`guard_dev_clone_relaxable` relaxes the control-plane deny **iff** the target is physically **under a
hardcoded temp root**, **outside the protected repo root**, and **the root is not itself under temp**. So:

```sh
git clone . /private/tmp/kit-work      # a LITERAL path — a variable target is denied (fail-closed)
```

The agent then edits `conformance/`, `.github/workflows/`, anything — **inside the clone**. Meanwhile the
guard stays **armed and effective on the real repo**: the identical edit to `~/…/your-repo/conformance/x.sh`
is still **DENIED**. Build there, run the checks there, push the branch, open the PR.

**Why this is the right default:**

| | Guard on your tree | What you review before saying GO |
|---|---|---|
| **dev-clone** | **armed + effective** | **a diff** — a PR, with CI already green on it |
| `apply.py` hand-off | armed but *defeated* during the write (an interpreter is a documented bypass class — see *Honesty boundary*) | **a script** — you must reason about bytes it *will* write |
| `KIT_GUARD_SELFEDIT=1` | **fully disarmed** | — |

The `apply.py` hand-off ("author to scratch, a human runs an idempotent apply") was the **mandatory**
pattern before CP-8c. **CP-8c abolished it** — it was *"built via the AMBER hand-off it abolishes, the last
mandatory one for guard work."* Do not reintroduce it out of habit.

The merge is still gated: `control-plane-ratification` demands a **non-author** approval, and the recorded
GO — not the keystroke — is the control (`docs/governance/promotion-contract.md`). **Agents propose,
humans ratify.** The clone changes *where the bytes are written*; it changes nothing about *who decides*.

### `KIT_GUARD_SELFEDIT=1` — last resort, and understand what it actually does

It is **not** a control-plane-edit permit. It is a **global kill switch**: it disables the destructive-op
denies and the secret-read denies **too**, for the whole session, not just the edits you wanted. Reach for
it only when you genuinely need the *entire* guard down for deliberate human maintenance (e.g. surgery on
the guard's own deny-matrix, where a clone cannot help because the guard under test *is* the artifact).

Using it to edit a handful of files is **over-broad** — that is what the dev-clone is for. If you do use
it, remove it the moment the work lands.

## Over-deny (false-positive) ceiling — the other direction
The control-plane shell-mutation check matches a control-plane path **and** a mutation verb by **substring over the whole command string** — it cannot tell *code* from *prose*. So it sometimes **over-denies** (a false positive, the guard failing *safe*): a commit message, a `gh pr create --body`, a heredoc body, or a `grep` pattern that merely *mentions* a control-plane path (`CODEOWNERS`, `.github/workflows`, `.claude/`) alongside a verb-looking word (`cp`, `sed`, `install`) is denied even though it mutates nothing. `git checkout -b <branch>` co-occurring with such a mention trips it too.

This is annoying, not unsafe (over-deny ≠ bypass). **Workarounds, in order:** for a long **commit or PR message** (the most common trip — a multi-line body is segmented on its newlines and a fragment mentioning a control-plane path is scanned as data-mistaken-for-code), pass the body from a **FILE** rather than inline `-m`/`--body` — `git commit -F <file>` / `gh pr create --body-file <file>` (the file content is a message, never executed). **As of DRIFT-2 the deny message names this escape itself** when the command is a `git commit`/`git tag`/`gh` invocation, so you see it at the moment of friction. Otherwise: run the command via the **`!` user-shell escape** (it runs in your terminal, outside the PreToolUse hook); use the **Read tool** instead of a shell `cat`/`grep` (or `sed -n`) for reads; if you are actually doing **control-plane work**, use the **dev-clone** (see the section above — that is the route, and it keeps the guard armed). **Only as a last resort** set `KIT_GUARD_SELFEDIT=1` in the **launching** shell — and know that it disarms the guard **globally** (destructive-op and secret-read denies included), not just the control-plane check. (An **inline** `KIT_GUARD_SELFEDIT=1 <cmd>` prefix does **not** work — the PreToolUse hook runs in its own process *before* your command, so the inline var never reaches it; export it in the launching shell, or add an `env` block to `.claude/settings.json`. In the **VSCode extension** a launching-shell export does not reach the hook either — the extension spawns its own process — so the `env` block is the only route there.) The structural fix — per-segment command parsing (judge each `;`/`&&`/`|`-separated segment's leading verb against the paths in *that* segment) — is tracked as **G8** in `../ROADMAP-KIT.md`; it is deferred because tightening this regex risks the *unsafe* direction (a false-negative), and the real backstop for an actual control-plane change is the PR-time `gate-agent-boundary` check, which diffs the files regardless of how they were edited.

## See also
- `DEVELOPMENT-PROCESS.md` §13 (autonomy matrix) · `conformance/agent-autonomy.sh` (the red-team corpus).
- `docs/operations/ci-platforms.md` — the analogous "one contract, many platforms" pattern for CI.
- `docs/operations/harness-adapters.md` — the harness-adapter boundary contract (the "one contract, many harnesses" pattern this guard plugs into).
- `docs/operations/harness-enforcement-evidence.md` — the maintainer-verified proof that the floor blocks for non-Claude harnesses (the three CI-locked surface selftests).
