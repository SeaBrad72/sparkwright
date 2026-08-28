# Runtime Guards — Portability Reference

How the kit's destructive-action deny-matrix protects **more than the Claude Code runtime**. One matrix (`/.claude/hooks/guard-core.sh`), four surfaces. The executable half of `DEVELOPMENT-PROCESS.md` §13 for non-Claude runtimes and humans.

> **Principle — one matrix, many surfaces; still a speed bump.** The deny-matrix is the single source of truth; each surface reuses it. None of them is a security boundary — `--no-verify`, a runtime that never calls `kit-guard`, or an interpreter still bypasses it. The real boundary is platform-owned (`../enterprise/platform-safety-boundary.md`).

## The one matrix
`/.claude/hooks/guard-core.sh` exposes five pure functions — each prints a `13: …` reason and returns 1 on deny, 0 on allow:
- `guard_check_command "<cmd>"` — the destructive-command matrix (rm, dd, SQL/DDL, migration resets, cloud/cluster destruction, prod-context, exfil, control-plane) **plus the secret-in-context read deny (H3a): a content-read verb (`cat`/`grep`/`diff`/`source`/…) targeting secret material (`.env*`/`.pem`/`.key`/`id_rsa`/`secrets/`) is human-gated** — reading a secret into the agent's context is the read half of exfil. **As of S6 the matrix also denies `gh pr merge --admin`/`--administrator`** — the branch-protection *bypass* (it overrides `control-plane-ratification` and the required-review SoD). This is a **speed-bump, not the boundary** (see *Honesty boundary* below): the sanctioned agent path is a **normal** merge on a recorded, authenticated GO (`scripts/promotion-verify.sh actuate`); solo, `--admin` stays the human's one act (the kill-switch).
- `guard_check_path "<file>"` — secret-material + control-plane **write** protection. **As of 3.17.0, the secret-WRITE deny enumerates the same `.env.<suffix>` set as `guard_check_read`** — `.env*`, `.pem`, `.key`, `id_rsa`, `secrets/` — with the same template allow-list (`.env.example`/`.sample`/`.template`/`.dist`). This closes the read/write parity gap for secret-material enumeration (previously `guard_check_path` enumerated only `.env.local`/`.env.production`/`.env.development`). Note: the control-plane **read ⊊ write asymmetry** (H3a) is unchanged — `guard_check_read` does NOT deny control-plane reads; this parity is specifically about secret-material enumeration.
- `guard_check_read "<file>"` — the **Read-tool** secret deny (H3a). Symmetric with the secret-write deny but **narrower: it does NOT deny control-plane reads** (reading the guard/CI to understand it is legitimate); `.env.example`/`.sample`/`.template`/`.dist` are allowed. Wired via the `Read` matcher in `settings.json`.
- `guard_check_push <remote-ref> <local-sha> <remote-sha>` — force-push / push-to-main, from real refs.
- **Content-search tools — `Grep`/`Glob` (C5 GUARD-TOOL-COVERAGE-GREP-GLOB).** The adapter's `Grep|Glob` `case` arm routes **both** `.tool_input.path` **and** `.tool_input.glob` through `guard_check_read`, so a **LITERAL secret-suffix** path/glob spelling is denied as `Read` is: `Grep{path:".env"}`, `Grep{glob:"*.env"}`, `Glob{path:".env"}` → **DENY**; an ordinary path/glob (`Grep{path:"README.md"}`, `Grep{glob:"*.py"}`, `Glob{pattern:"*"}`) → **ALLOW**. **`guard_check_read` matches the glob string against the literal secret patterns**, so a NON-literal glob that still targets a secret (`*.env*`, `*.{env,pem}`, `*.[ep]*`, `*env`) is **NOT** denied — it joins the disclosed residual below. Glob targeting is not exhaustively closable at this input layer (the same structural limit as the sweep), so it is handed to the boundary rather than chased with fragile pattern-matching. `MultiEdit` is folded into the `Write|Edit|NotebookEdit` arm (single `.file_path`, `guard_check_path` covers it fully). **★ Named boundary handoff — the load-bearing residual (read before trusting the coverage).** The guard is an **input-side** control: it sees the tool call (`path`/`glob`), never Grep's *output*. It therefore denies secret-*targeting* spellings but **cannot** scrub a secret line out of an **untargeted directory/cwd content-sweep** (`Grep{path:".",output_mode:"content"}`, or no `path`) **nor out of a non-literal secret-targeting glob** (`*.env*`) — at dispatch time it does not know which files the read will return. Those cases are **ALLOW by design** (blanket-denying directory content-search would deny the agent's primary code-search tool, disproportionate and inconsistent with "speed bump not boundary"; in practice ripgrep respects `.gitignore`, so a gitignored `.env` is not searched — **but that mitigation does not survive a hardlink**: a benign-named in-repo hardlink onto a gitignored `.env` is not itself gitignored, so the sweep reads the secret's bytes while the alias is never path-checked, boarded as `GUARD-HL-SWEEP-GITIGNORE-MITIGATED-NO-MORE`, see *Hardlink aliases* below). So Grep/Glob guard-coverage is honestly **`residual-family`** in `conformance/sanctioned-commands.tsv`, **not `full`** — the targeting spellings are denied, the sweep is a **disclosed residual**. **Secret-content *exfiltration* is bounded where the kit bounds every exfil vector: the platform boundary** — `../enterprise/platform-safety-boundary.md` **control #1** (network-egress allowlist — "the only real exfiltration defense") and **control #3** (sandboxed / read-only filesystem), which the kit verifies are **declared + attested** via `conformance/egress-policy.sh` and `conformance/containment-ready.sh`. The guard denies the default-harm route cheaply; the boundary that binds a *non-cooperating* agent is platform-owned, not this hook. (`Glob` returns filenames, not content, so guarding its `path` is defense-in-depth, not a content-exfil fix.) **`Task` is not content-guarded at runtime** — it carries no file target; its content risk is the spawned subagent, guarded only if that session wires the hook. This is **declared-uncovered by absence** from `conformance/sanctioned-commands.tsv` — `Task` is not on the shipped allow surface, so C3's reconcile lock forces no row; if it were ever allow-listed, C3 forces a row and the family lock (`tool-coverage.sh`) reds it at `guard-backstop=none` until wired or declared. Not claimed away.
- `guard_check_mcp "<tool>" "<allowlist>" "<overrides>"` — the MCP capability gate (Slice 11a): classifies an `mcp__<server>__<action>` tool by its action verb and denies un-allowlisted destructive/egress capabilities (fail-closed). Pure — the adapter loads `.claude/mcp-policy.json` and passes it in.

> **Secret-in-context ceiling (H3a, honest).** The two read denies stop the agent's **default** exfil-read paths (shell `cat .env`, the Read tool) but are a speed bump, not containment: an **interpreter** (`python -c "open('.env')"`), an uncommon content-emitter not in the verb list, or an exotic `.env.<custom-suffix>` on the *shell* path can still read a secret; `jq`-absent leaves the Read tool allowed; non-Claude harnesses get the shell deny via `kit-guard cmd` (no Read tool). The real boundary is the platform egress allowlist + sandboxed FS (`../enterprise/platform-safety-boundary.md`).

`conformance/guard-core-sourced.sh` asserts every consumer sources this file (no forked matrix).

## The four surfaces
| Surface | File | Covers | Cooperation |
|---------|------|--------|-------------|
| Claude Code | `.claude/hooks/guard.sh` (PreToolUse) | command + path + MCP-tool (`mcp__.*`) | automatic in Claude Code |
| Any git client | `hooks/pre-push` → `.git/hooks/pre-push` (or the config pointing at the tracked `hooks/`) | git-history (force-push, push-to-main) | none — every runtime + humans |
| Any other runtime | `scripts/kit-guard` CLI | full command + path matrix | runtime pipes commands through it |
| CI (any harness) | `conformance/agent-boundary.sh` + `control-plane-ratification` job | control-plane-diff ratification | automatic on every PR — the harness-independent floor |

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

## The edit-time phase gate — PARKED 2026-08-19, not shipped

A section here used to document `conformance/phase-gate.sh`, an edit-time decision answering *may this
tool write this path right now, given what this branch has recorded?* **It never had a caller.** The
policy was built and tested under `[S1a-i]`; the `guard.sh` binding (`[S1a-ii]`) was never built, so the
gate denied nothing in practice for its entire shipped life — only its own selftest ran. On 2026-08-19
it was **parked** to the history branch `history/phase-gate-s1a-i` (`D-240819-3`, amending `D-240804-1`);
see `docs/operations/retiring-conventions.md` for the tombstone and what re-wiring would take.

**Nothing replaced it, and nothing here should be read as implying otherwise.** The deny-matrix surfaces
documented above are the whole of this page's enforcement. Acceptance stays at merge
(`docs/governance/promotion-contract.md`).

## Honesty boundary
Each surface is a speed bump for honest mistakes, not containment of a hostile process. It is bypassable by design and does **not** claim to block every write/exfil path. **Local git only:** the git surfaces here (`pre-push`, `guard_check_push`) act *locally*, before the network round-trip. A **server-side `gh pr merge --admin`** is a GitHub API call — a different transport entirely — and is outside the guard's reach. **The S6 `--admin` deny is a local speed-bump, not this boundary:** it makes the bypass loud in the guard's own reasons and stops the honest-mistake local invocation, but a token with admin scope can still call the API directly (or a non-Claude runtime can). **The real boundary is credential-side — never issuing the agent an admin-scoped token** (`../enterprise/platform-safety-boundary.md`); a `gh` with only normal-merge scope simply *cannot* bypass. The boundary on *who merges* is GitHub branch protection + the agent's sanctioned path — a **normal** (non-`--admin`) merge on a recorded, authenticated GO via `scripts/promotion-verify.sh actuate` (team), or preparing the PR and handing the human the `--admin` kill-switch merge (solo) — see [`review-lane.md`](./review-lane.md), **not** the guard. Known bypass classes (all within this ceiling, not regressions): `--no-verify`; an uncooperative runtime; a language interpreter (`python -c`, `node -e`); a redirect/printf that writes a file without invoking a denied verb; an upload via `curl --data @file` / interpreter; and history-application like `git am` / `git apply`. The boundary that actually contains these is platform-owned — adopt the guard **with** the network-egress allowlist, separate prod credentials, sandboxed FS, and scoped tokens (`../enterprise/platform-safety-boundary.md`).

## Doing control-plane work — the sanctioned route (READ THIS BEFORE REACHING FOR THE KILL SWITCH)

The guard **correctly** denies an agent editing `conformance/`, `.github/workflows/`, `.claude/`,
`scripts/kit-guard`, `CODEOWNERS`, … — that is its job, not a bug. But real control-plane work still has
to happen (a CI gate needs fixing, a conformance check needs writing). **There is a sanctioned way to do
it with the guard fully armed, and it is NOT `KIT_GUARD_SELFEDIT`.**

### The dev-clone affordance (CP-8c, v3.124.0) — the default

`guard_dev_clone_relaxable` relaxes the control-plane deny **iff** the target is **under a hardcoded temp
root**, **outside the protected repo root**, and **the root is not itself under temp** — and, since
v3.196.0, iff the path **as you typed it** also satisfies the first two, not merely the path it resolves to.
So:

```sh
git clone . /private/tmp/kit-work      # a LITERAL path — a variable target is denied (fail-closed)
```

The agent then edits `conformance/`, `.github/workflows/`, anything — **inside the clone**. Meanwhile the
guard stays **armed and effective on the real repo**: the identical edit to `~/…/your-repo/conformance/x.sh`
is still **DENIED**. Build there, run the checks there, push the branch, open the PR.

#### What changed in v3.196.0 (`GUARD-PATH-ALIAS-BYPASS`, P0)

The guard used to decide on the path **string** and never on the target it reached, so any alias with a
benign name defeated it — measured, a write through an aliased path landed inside the real repository
while the guard reported ALLOW, and a renamed symlink returned a real `.env`'s contents through the Read
tool. Four user-visible consequences:

1. **The affordance now takes the literal path into account too.** A control-plane file that *sits inside*
   your repo but symlinks out to temp no longer relaxes. Neither does a dev-clone reached through a
   symlink from outside temp — e.g. `~/work/clone -> /private/tmp/kit-work`, addressed by that absolute
   spelling. **Workaround: use the real (`pwd -P`) path.** Working relative from inside the clone also
   relaxes, but only when your *session* is rooted there, so do not rely on it.
2. **A path that cannot be resolved is now DENIED**, not allowed — e.g. a file beneath a directory you
   cannot search, or a symlink cycle. It carries its own reason so it is not mistaken for a
   control-plane violation.
3. **A new false positive on control-plane names, accepted deliberately:** an ordinary file whose
   *resolved* path runs through **any directory the control-plane classifier matches** — `skills/`,
   `conformance/`, `adapters/`, `.git/`, `.github/workflows/`, and others — is now denied on write. If
   you keep notes at `~/notes -> ~/Documents/skills/notes`, that is why. The deny names the resolved
   path so the reason is legible.
4. **A new false positive on secret names, same trade, on BOTH read and write:** an ordinary file whose
   resolved path traverses a `secret/` or `secrets/` directory is now denied. (An earlier draft of this
   note scoped it to reads only; the write path gained it too.)
5. **One widening, in the other direction.** `_under_temp` gained a case-folded second arm, so any
   spelling containing at least one uppercase character whose lowercased form matches a temp root — e.g.
   `/private/TMP/…`, `/VAR/folders/…/T/…` — now counts as temp. That **widens** the affordance's relax
   side, so it is a DENY→ALLOW rather than a new denial. On a case-insensitive macOS filesystem
   `/private/TMP` *is* `/private/tmp`, and on a case-sensitive one creating such a path needs write
   access to `/` or `/var`. It is disclosed rather than omitted because the alternative — folding the
   subject against a pattern list that carries a literal uppercase `T` — would have silently killed the
   affordance for every `mktemp -d` clone on macOS while Linux CI stayed green.

**What this does NOT close** — stated because a green here is narrower than it looks. It covers **symlink**
aliases on the `Edit`/`Write`/`Read` route, and only where the terminal component is the target's own
directory entry. Beyond that it leaves open the **shell write routes** (`tee`/`cp`/`mv` remain
alias-blind — `GUARD-ALIAS-SHELL-ROUTE`), **alias-creation primitives** (`ln -s` at a literal
control-plane target is denied, but interpreters and archive extractors are not —
`GUARD-ALIAS-PRIMITIVES`), and **races** between the guard's decision and the write. **Hardlink**
aliases were a fourth item on this list until v3.217.0; they are now judged on the tool routes — the
section immediately below states precisely what that green does, and does not, mean.

#### Hardlink aliases — what IS covered (`GUARD-CP-HARDLINK-ALIAS`, v3.217.0)

A **hardlink** is a second directory entry for one inode. There is no link to follow, so a benign-named
hardlink's *resolved* path **is** the benign name, and every string matcher passes it. Since v3.217.0 the
two tool-route deciders judge the **inode** as well as the string.

**Covered.** An `Edit`/`Write` whose path is a hardlink to a **control-plane or secret** file, and a
`Read`/`Grep`/`Glob` whose path is a hardlink to a **secret** file, are refused exactly as if they had
named the target directly — including the cloak (an `.env.example` hardlinked onto a real `.env`), which
is judged *before* the template allow-list. Reads of *control-plane* files stay legitimate (reading the
guard to understand it is not exfil). Mechanism: an `nlink>1` pre-filter, then a repo-scoped,
watchdog-bounded `find -inum`, then the **existing** classifiers over every other name sharing that inode
— so the reach inherits the control-plane derivation and cannot drift from it. The control-plane half is
subordinate to the dev-clone affordance above; the secret half deliberately is not, because it mirrors
the direct secret deny.

**Fail-safe behaviours — these DENY, and they now say why.** When the link count cannot be read, no repo
root can be derived, the root sits at or above `$HOME`, or the `find` errors or exceeds its time budget,
the guard denies rather than silently opening the alias route. The deny reason carries a remedy clause —
*"Remedy: usually an unreadable directory under the repo root, or a find that exceeded its time budget -
make that directory searchable, or raise KIT_HL_FIND_BUDGET (seconds)"* — because the commonest real
cause is a directory under your repo root that the guard cannot search, and an unsignposted deny is a
dead end. **`KIT_HL_FIND_BUDGET`** (seconds, default 10) is the operator lever for the watchdog. Read
this as an **availability ceiling**: one unreadable directory can turn every access to an `nlink>1` file
into a deny. The global kill switch is deliberately *not* the escape here — the secret arm is ungated by
design — so the fix is to make the directory searchable or to raise the budget.

**Residuals — stated, not implied closed.**

- **Out-of-repo targets are NOT reached.** The `find` is repo-scoped (that scoping is what stops a
  home-wide walk), so a hardlink whose control-plane/secret sibling lives *outside* the repo root
  (`~/.ssh/id_rsa`, `~/.claude/*`, a home `.env`) is allowed where the equivalent **symlink** denies.
  Boarded as **`GUARD-HARDLINK-OUT-OF-REPO`**.
- **Hardlink *creation* on the command route is only partly blocked.** `ln <control-plane-file> benign`
  trips the path scan, but **`cp -l`** / `cp --link` is destination-bound and evades it, as do
  `install`-link forms and any indirection through a shell variable or a file. Creating the link is not
  reliably refused; *editing or reading through* it afterwards is.
- **Pruned subtrees.** For cost, the inode scan prunes `.git/objects`, `.git/lfs` and `node_modules`. A
  hardlink whose only control-plane/secret sibling lives inside one of those is out of scope. The rest of
  `.git` — `config`, `hooks`, refs — stays in scope deliberately, because it is control-plane.
- **The detection gate is blind to the untracked secret.** `conformance/hardlink-integrity.sh` reds when a
  **tracked** control-plane or secret file has `nlink>1`, backstopping the command route on the one axis a
  commit-time gate can see. A `.env` is normally gitignored, so it is untracked and never stat-ed there;
  the persistent secret cloak's only defense is the runtime check above. Do not read a green gate as "no
  secret cloak present." Submodule files are likewise outside `git ls-files` scope.
- **The Grep/Glob content-sweep mitigation weakens here.** The disclosed sweep residual at the top of this
  page leans on ripgrep honouring `.gitignore`; a benign-named in-repo hardlink onto a gitignored `.env`
  is itself **not** gitignored, so an untargeted content sweep can read the secret's bytes while the alias
  is never path-checked. Boarded as **`GUARD-HL-SWEEP-GITIGNORE-MITIGATED-NO-MORE`**.
- **Watchdog PID reuse.** The portable watchdog disarms via a flag file before reaping, but the
  kill-by-pid idiom retains a narrow theoretical reuse window. Boarded as
  **`GUARD-HL-WATCHDOG-PID-REUSE-RACE`**.
- **Directories, and legacy HFS+.** A directory subject exits the check immediately: every directory has
  `st_nlink >= 2`, so the cheap pre-filter would never fire for one, and on the supported filesystems
  (ext*/xfs/btrfs/APFS) `link()` on a directory is refused — a directory can never be the hardlink alias
  of a file. **Legacy HFS+ *did* allow directory hardlinks** (Time Machine used them); on such a volume
  that early exit is a real, disclosed gap. A directory named at a control-plane path is still denied by
  the string matchers, which run outside this check.
- **TOCTOU** — a link swapped between the guard's decision and the write defeats any check-time test,
  exactly as it does for symlinks.

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

This is annoying, not unsafe (over-deny ≠ bypass). **Workarounds, in order:** for a long **commit or PR message** (the most common trip — a multi-line body is segmented on its newlines and a fragment mentioning a control-plane path is scanned as data-mistaken-for-code), pass the body from a **FILE** rather than inline `-m`/`--body` — `git commit -F <file>` / `gh pr create --body-file <file>` (the file content is a message, never executed). **As of DRIFT-2 the deny message names this escape itself** when the command is a `git commit`/`git tag`/`gh` invocation, so you see it at the moment of friction. Otherwise: run the command via the **`!` user-shell escape** (it runs in your terminal, outside the PreToolUse hook); use the **Read tool** instead of a shell `cat`/`grep` (or `sed -n`) for reads; if you are actually doing **control-plane work**, use the **dev-clone** (see the section above — that is the route, and it keeps the guard armed). **Only as a last resort** set `KIT_GUARD_SELFEDIT=1` in the **launching** shell — and know that it disarms the guard **globally** (destructive-op and secret-read denies included), not just the control-plane check. (An **inline** `KIT_GUARD_SELFEDIT=1 <cmd>` prefix does **not** work — the PreToolUse hook runs in its own process *before* your command, so the inline var never reaches it; export it in the launching shell, or add an `env` block to `.claude/settings.json`. In the **VSCode extension** a launching-shell export does not reach the hook either — the extension spawns its own process — so the `env` block is the only route there.) The structural fix — per-segment command parsing (judge each `;`/`&&`/`|`-separated segment's leading verb against the paths in *that* segment) — is tracked as **G8** in `../ROADMAP-KIT.md`; it is deferred because tightening this regex risks the *unsafe* direction (a false-negative), and the real backstop for an actual control-plane change is the PR-time `control-plane-ratification` check, which diffs the files regardless of how they were edited.

### What `GUARD-READONLY-FP-RELIEF` changed (v3.218.0) — five relieved shapes, one *tightened* one

Five read-only shapes that used to be denied are now allowed, each by a **declared** recognizer that
declines on anything it does not positively recognize (so a bug in one over-denies, never over-allows):

| Now allowed | Why it is safe |
|---|---|
| `sh scripts/kit-guard path\|cmd\|mcp <cp-path>`, `promotion-readiness.sh --class --changed <listing>`, `agent-boundary.sh --changed <listing> --ratified 0` | A **declared table** of `(script, query-token)` pairs — unknown script, unknown flag, any redirect, any `$`/backtick, or any `..` in the script token all decline. The pairs are *run* against a fixture control-plane path by `conformance/agent-autonomy.sh`, which asserts each script exists and that the worktree is unchanged, so a pair that ever gains a write path — or that outlives its script — goes RED. |
| `test -f <cp>` · `[ -f <cp> ]` | `test`/`[` read metadata and cannot write. `if`/`elif` are **not** in the lead set — they run a *command*. |
| a **quoted** heredoc body (`<<'EOF'`) naming a control-plane path | A quoted delimiter makes the body inert by shell semantics. Any terminator ambiguity (`<<-`, an unquoted delimiter, two heredocs, no exact terminator line) declines and the body stays scanned. |
| `git config --get\|--get-all\|--get-regexp\|--get-urlmatch\|--list <key>` | Recognized **per occurrence** and **default-deny**: no query flag, an extra value token, an unknown option, or a `-c`/`--file` carrier all still deny. `git config core.hooksPath <value>` — the guard-disable vector — stays DENY, held by **two** independent guards (a query flag must be present **and** the operand count is bounded), so no single-guard slip opens it; `--get … && git config core.hooksPath /tmp/e` still denies on the write segment; and a trailing `# git commit …` **comment** does not steal the message-carrier exemption (that exemption anchors on the leading token pair, not a substring). |
| a redirect to a `~/`-rooted **literal** target (`printf x >> ~/notes.txt`) | A `~` target shows every byte after the home root literally, so it is checkable — and it is checked. A `~` suffix carrying `..`, a glob, any control-plane segment, **or a home-root dotfile** (`~/.gitconfig`, `~/.config/git/config` — where `core.hooksPath` also lives — `~/.zshrc`, `~/.ssh/authorized_keys`) still denies; only non-dotfile scratch suffixes (`~/notes.txt`, `~/scratch/out.txt`, `~/logs/verify.log`) are relieved. |

**`$VAR` redirect targets are still refused, deliberately.** `printf x >> $SCRATCH/notes.txt` denies:
with the directory inside the variable, the visible suffix (`pre-push`, `settings.json`) does not
identify itself, so the guard cannot tell a scratch append from a hook overwrite. **Spell the target
literally**, use a `~/`-rooted path, or use the Write tool — the deny message now says so.

**One thing got *stricter*.** `_cp8b_redir_launder_denied` only recognized a laundering verb when the
verb led the segment, so a brace group or subshell moved the redirect into a `}`/`)`-led segment it
did not recognize: `{ printf evil ; } > $VAR/pre-push` and `( printf evil ) > $VAR/pre-push` were
**measured ALLOW** before this slice — a two-byte bypass of the `GUARD-CP-WRITE-ROUTES` Cure-2
closure. Group tokens are now peeled and recognition re-tested, and a segment that is only a group
*close* (or a verbless `> $VAR/x` truncate) denies. **Disclosed over-deny, priced deliberately:** the
scope is the segment's *shape*, not what the group contains (that lives in another segment), so
`{ make ; } > $OUT` now denies while the bare `make > $OUT` still allows. Drop the braces, or spell
the target literally.

### Kept-denied on purpose — and each one now names its escape

Segmentation is deliberately **quote-blind by default**: a quote-aware splitter fails *open* (it can
miss a real `; rm -rf`). `GUARD-READ-LANE-2` bought back the quoted-alternation face **only** behind a
gate that keeps the fail-open direction shut (see the read-lane table below); the three faces here are
still not relieved, and they pay their friction with a named escape in the deny message instead.

| Denied shape | Why it stays denied | What the message now tells you |
|---|---|---|
| `for f in <cp-paths>; do … ; done` | the loop **head** carries the whole deny — relieving it segment-locally would allow a mass-delete body (`do rm $f` allows as a standalone segment, measured) | the Read/Grep tool, or one invocation per file |
| `bash -c "…"`, `python3 -c "…"`, `source` | an interpreter's arguments are code, not data | use the Read tool, or run a file that names no control-plane path |
| `KIT_ANYTHING=1 sh <kit-script>` (unvetted prefix) | the vetted-name allowlist is closed on purpose; adding a name per false positive is enumeration creep | `export` the variable as a separate statement, or use a vetted name |

**Quoted alternation moved OUT of this table.** `grep -n "A\|B" <cp>` and `grep -E "a|b" <cp>` are now
**allowed** — face F-a below. The relief is a *masking* recogniser with a declared decline set, so the
shapes it will not read are still denied, exactly as before: a **backslash immediately before `"`, `'`
or `\`** · a **`$`** anywhere · a **backtick** anywhere · a **`<<` heredoc operator** · a **newline or
CR** after joining · **unbalanced quotes, or a walk that ends inside an open span** · and — the
load-bearing one — **any segment whose lead verb is not on the gate lexicon**, which discards the mask
and restores today's verdict for the whole command.

### What `GUARD-READ-LANE-2` changed — the read lane, face by face

Six read faces, each a **declared recogniser that declines** (a bug in one over-denies, never
over-allows). The cell labels in the last column are the fixtures in `conformance/agent-autonomy.sh`
that pin each claim; every statement here is a cell, not a description.

| Face | Now allowed | Declines on (still denies) | The named escape when it declines | Cells |
|---|---|---|---|---|
| **F-a** — quoted-separator mask | a quoted `\|`, `&&`, `>` or `->` inside a pattern or a banner: `grep -E "a\|b" <cp>`, `grep -nE 'a b\|c' <cp>`, `echo "=== (before -> after) ==="`, a masked pattern followed by a **real** pipe into another gate verb (`git log \| grep -E "a\|b"`), and the single-quoted BRE twin `'a\\\|b'` | the decline set above; **and the gate**: every segment's *de-quoted* lead must be on `_CP8B_MASK_GATE_VERBS` (`grep egrep fgrep ls cat head tail wc stat du cut tr nl od hexdump tac comm cmp basename dirname realpath readlink echo printf which type shellcheck jq shasum md5 cksum yamllint git`, with `git` admitted only through `status blame describe diff log show ls-files`). `sh`, `xargs`, `tee`, `cp`, a kit script or an empty lead → mask discarded → today's verdict | drop the alternation, one pattern per invocation, or the Grep tool | `F-a …` (16 allow / 13 deny, incl. the `xargs rm`, `tee`, quoted-`sh` and unbalanced-quote declines) |
| **F-b — `sed -n`** | `sed -n 1,120p <cp>` — exactly `-n`, **one** script token matching a numeric range (`N`, `N,M`, `N,$`) after stripping one matching quote pair, ≥1 non-flag path operands | `-i`, `-e`, `-f`, `-E`, `-s`, `--expression=`, a second script, a `w`/`e`/`r` command, a `/re/p` address, a redirect, a pathful `/usr/bin/sed` lead | `grep`, `head`/`tail`, or the Read tool | `F-b …` (`W6`, `W8`, `W8b` are the write cousins, pinned DENY) |
| **F-b — `awk`** | `awk 'NR>=5' <cp>`, `awk 'NR==12' <cp>`, `awk '{print}' <cp>` — one program token matching the anchored `NR`-comparison or bare-`{print}` grammar, optional single `-F<sep>` | `-v`, `-f`, `-e`, `--source`, `system()`, `getline`, a bare `>` in the program, a second program, a program token carrying whitespace (`awk 'NR>=5 && NR<=9'`, `awk '{ print }'` — a *token*-delivery gap, see below) | drop the spaces (`NR<=9` alone, `'{print}'`), or the Read tool | `F-b …`, `F-a T6-carried …` |
| **F-e — `find`** | `find <dir> -name '*.sh' -type f -print` — every token a path or a primary on the **declared allowlist** with its arity operand | `-exec`, `-execdir`, `-ok`, `-okdir`, `-delete`, `-fprint*`, `-fls`, `-ls`, `-printf`, an unknown primary, a **quoted** primary (`'-delete'`), a primary smuggled into an arity slot, a `{a,b}` brace or a leading glob operand, a pathful `/usr/bin/find` lead | name the primary in a row on this table (a one-line ratified add), or use the Glob tool | `F-e …`, `F-e/T7r2 …` |
| **F-g — `.claude/projects/*`, `.claude/plans/*`** | already relieved — a read of a project/plan file (`cat`, `head`, `grep -n`, and now `sed -n` via F-b) allows | unchanged: `sed -i`, `tee`, `python3 -c open(...,'w')` and any `..` traversal onto a nested `hooks/` still deny (owner ruling **C1**, classifier-only relief) | — | `F-g …` (9 cells, pinned) |
| **F-h** — the kill-switch sentence | *(message tier, not a verdict)* a denial whose whole offending segment is **read-shaped** no longer advertises `KIT_GUARD_SELFEDIT=1`; it names the read escape instead | any redirect, a write verb or write flag in any token position, a prefixed or orphan-led write, a destructive loop body, `echo`/`printf` (emitters, never read-shaped) → the sentence stays | — | `F-h …` (57 cells, `assert_reason_lacks` / `assert_reason_has` pairs) |

**F-g is "already relieved; pinned", not a new mechanism.** The design's mask for it measured as a
no-op: a read-verb segment leaves the read arm before it can reach the pathhit, and that arm's only
control-plane test was *already* relieved for `.claude/projects|plans` — more widely than the design's
regex. The `sed -n` face closes through F-b's grammar instead. **Consequently the C1 ruling extension
the design offered for ratification was never exercised: no write-side and no pathhit change shipped.**

**Priced over-denies, deliberately not refunded** (each has a one-retry escape): a flagless
`rg` / `diff` / `column` / `git grep` quoted-alternation read — those four verbs carry an exec or write
flag (`rg --pre`, `git grep -O`, `diff --to-file=`, `column -o`) and are **off** the mask gate; retry
with `grep -E`. Also `\;` outside quotes, `find -ls`, `file -i <cp>` (keeps the kill-switch sentence),
a pathful `/usr/bin/sed` or `/usr/bin/find` lead, and `cat <cp> | sh -n` (retry: `sh -n <file>`).

#### The deny side of the same slice

| Now denied (was ALLOW) | Why | Cells |
|---|---|---|
| `sh -c 'gh pr merge 5 --admin'`, `bash -lc …`, `xargs -0 sh -c …`, `CMD='gh pr merge 5 --admin'; sh -c "$CMD"`, a line continuation inside `gh \`⏎`pr merge` | the rider: the porcelain arm now runs over a quote- and continuation-normalised view, and the lead token is case-folded, so a **same-command** wrapper no longer blinds it. `gh -R o/r pr merge 5 --admin` was ALLOW since the arm was written (`gh` hoists `-R`) — the arm now tests token **order**, not adjacency | `R …`, `T2R2 …`, `T2R3 …` |
| `echo "cp e <cp>" \| sh`, `cat <<'EOF' \| sh`, `sh <<'EOF'`, `\| bash`, `\| python3`, `\| xargs sh -c`, `ls conformance \| sh` | the pipe-into-interpreter rule: if any segment's lead is an interpreter and it is **fed by a pipe**, every upstream segment is scanned **raw** — no read-verb data exemption, no F-a mask, no heredoc-body exclusion. A quoted heredoc body is excluded only when the consumer is the **whole** start line | `H …` (171 cells, incl. `/bin/sh`, `env -i sh`, `sudo sh`, `nohup sh`, versioned `bash5`/`python3.11`) |
| `sed -n 1p {-i,<cp>}`, `awk … {-v,<cp>}`, `find … {-exec,cp}`, a leading `*` glob operand | brace expansion synthesised a flag *after* the guard had judged one inert token. An operand carrying `{ } ,` or a leading glob byte is now **never a path**, in the shared read-lane helper (`_cp8b_seg_path_ok`), so every read lane **that has a path-operand grammar** inherits it — the sed, awk and find faces, its three measured call sites. The **lexicon** lanes are NOT reached: `grep x {-r,<cp>}`, `rg x {--pre,./e.sh,<cp>}` and `git grep {-O,vim,x} <cp>` still ALLOW, exactly as their plain spellings do (boarded, `GUARD-READ-LEXICON-EXEC-FLAGS`) | `F-e/T7r2 …` |
| `'grep' x > .claude/hooks/gu*` | a **quoted** read lead dodged the redirect-launder arm; the lead is now de-quoted before the arm looks | `F-4 …` |

**Ceiling, stated plainly.** These are byte-level rules. A wrapper whose bytes are **absent** from the
command — an exported `$VAR`, `$(cat f)`, a `gh alias set` — is still invisible, and an unrecognised
interpreter binary name (`busybox sh`, `./sh`, a renamed shell) still walks past the pipe rule. Four
data-lexicon verbs carry exec/write flags that reach a control-plane path today and are **ALLOW**,
pinned as measured-uncovered cells (`F-1 …`) and boarded as `GUARD-READ-LEXICON-EXEC-FLAGS`.

**Zero-widening is measured, not asserted.** `conformance/agent-autonomy.sh --delta <pristine-core>`
replays every Bash cell against both cores and fails on any verdict change outside a declared expected
list. At this slice's head that reads **205/0 against `4b3debc3` (247,504 b), cell-bounded** — 205
changed, 205 expected, 0 unexpected. *Cell-bounded* is the honest qualifier: the replay covers Bash
`assert_deny`/`assert_allow` cells only, never the reason-text helpers, the fixture-driven legs, or the
Write/Edit/Read entry points.

A fifth ergonomic fix rides along: the escape hints used to key on the **raw** command's lead verb, so
`cd x && sed -n … <cp>` lost its `head/tail` hint — the tip vanished exactly when a compound made the
deny hardest to read. They now key on the **offending segment's** lead.

## See also
- `DEVELOPMENT-PROCESS.md` §13 (autonomy matrix) · `conformance/agent-autonomy.sh` (the red-team corpus).
- `docs/operations/ci-platforms.md` — the analogous "one contract, many platforms" pattern for CI.
- `docs/operations/harness-adapters.md` — the harness-adapter boundary contract (the "one contract, many harnesses" pattern this guard plugs into).
- `docs/operations/harness-enforcement-evidence.md` — the maintainer-verified proof that the floor blocks for non-Claude harnesses (the three CI-locked surface selftests).
