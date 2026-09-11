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

**Verify the push landed — read the ref back, never the output.** The hook writes to stderr and so does git's own progress, so a refused push and a successful one look alike in a captured transcript, and a harness that swallows stderr shows you nothing at all. The only proof is the forge's ref: `git ls-remote --heads origin <branch>` must print the SHA that `git rev-parse HEAD` prints. If it prints a different SHA, an older one, or nothing, the push did not land — whatever the output said.

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
the tombstone and what re-wiring would take are recorded in the kit maintainers' `docs/kit-internals/retiring-conventions.md` (not in the adopter export).

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

This is annoying, not unsafe (over-deny ≠ bypass). **Workarounds, in order:** for a long **commit or PR message** (the most common trip — a multi-line body is segmented on its newlines and a fragment mentioning a control-plane path is scanned as data-mistaken-for-code), pass the body from a **FILE** rather than inline `-m`/`--body` — `git commit -F <file>` / `gh pr create --body-file <file>` (the file content is a message, never executed). **As of DRIFT-2 the deny message names this escape itself** when the command is a `git commit`/`git tag`/`gh` invocation, so you see it at the moment of friction. Otherwise: run the command via the **`!` user-shell escape** (it runs in your terminal, outside the PreToolUse hook); use the **Read tool** instead of a shell `cat`/`grep` (or `sed -n`) for reads; if you are actually doing **control-plane work**, use the **dev-clone** (see the section above — that is the route, and it keeps the guard armed). **Only as a last resort** set `KIT_GUARD_SELFEDIT=1` in the **launching** shell — and know that it disarms the guard **globally** (destructive-op and secret-read denies included), not just the control-plane check. (An **inline** `KIT_GUARD_SELFEDIT=1 <cmd>` prefix does **not** work — the PreToolUse hook runs in its own process *before* your command, so the inline var never reaches it; export it in the launching shell, or add an `env` block to `.claude/settings.json`. In the **VSCode extension** a launching-shell export does not reach the hook either — the extension spawns its own process — so the `env` block is the only route there.) The structural fix — per-segment command parsing (judge each `;`/`&&`/`|`-separated segment's leading verb against the paths in *that* segment) — is a known, deferred hardening item; it is deferred because tightening this regex risks the *unsafe* direction (a false-negative), and the real backstop for an actual control-plane change is the PR-time `control-plane-ratification` check, which diffs the files regardless of how they were edited.

### The escape card — the six shapes the guard will always refuse, and the one retry for each

**Read this once instead of re-discovering it every session.** Six read-shaped commands are
**kept-denied by standing ruling**, not by accident and not pending a fix. They were re-measured
across one week of orchestrator, seat and engineer sessions (`GUARD-DENY-LOG` design §2) and each was
re-affirmed. Every one has a **one-retry escape**. The deny messages point here.

| # | The shape that gets refused | Why it stays denied (the ruling) | The escape (one retry) |
|---|---|---|---|
| **R1** | An alternation `\|`/`|` inside a quoted pattern, in one of the three spellings that still bite: `rg -n 'a\|b' <cp>` · `git grep -n 'a\|b' -- <cp>` · a `grep`/`egrep` alternation inside a **compound whose OTHER segment leads with a verb still off the mask gate** (a `for` head, `python3 -c`, a bare `sh <script>`), e.g. `for f in conformance/*; do grep -n 'a\|b' $f; done`. ⚠️ **The `cd`-prefixed compound is no longer one of them** — `cd x && grep -n 'a\|b' <cp>` is ALLOW since `GUARD-READ-PATTERN-RELIEF` (2026-09-01), as is a `sed -n`/`awk` segment the strict read grammar accepts; see the relief list below. ⚠️ **Plain `grep -n 'a\|b' <cp>` and `egrep 'a\|b' <cp>` as the sole command are ALLOWED** — lane 2 relieved them (re-measured 2026-08-29; an earlier draft of this card wrongly listed them as denied). | Segmentation is deliberately **quote-blind**: a quote-aware split fails *open* on a real `; rm -rf`. So the `\|` splits the command, and in the compound case the fragment that carries the control-plane path no longer leads with a read verb — the read lane never gets to look at it. `rg`/`git grep` are outside the relieved lexicon lane. `D-240813-3` binds. Reopening this is an owner call at the harvest, on the log's numbers. | `grep -e A -e B <path>` — **verified ALLOW in all three failing forms**, compound and piped included — or the **Grep tool** |
| **R2** | `sed -n "${n},$((n+14))p" <cp file>` — a non-literal address | The `$` means the address is not visible to the guard, and `sed` carries write/exec escapes (`w`, `s///e`). `D-240813-2`: judge the **resolved target**, and an unresolved one cannot be judged. | literal line numbers (`sed -n 40,54p <path>`), or the **Read tool** |
| **R4** | `printf … > $SCRATCH/out` — a redirect whose target is `$`-rooted | K-R1b: with the directory inside the variable, the visible suffix does not identify itself — a scratch append and a hook overwrite look identical. The guard refuses to guess. | a literal path (`> /private/tmp/out`), a `~/`-rooted literal, or the **Write tool** |
| **R5** | `for p in profiles/*/BRANCH-PROTECTION.md; do md5 -q "$p"; done` — a loop head over a control-plane glob, read-only body | F-f: the **head** carries the deny for the whole construct. Relieving it segment-locally would allow a mass-delete body under a read-looking head. | one invocation per file, or the **Read/Grep tool** |
| **R8** | `rm /abs/path/under/scratch` — `rm` with an absolute path | The destructive matrix: an absolute `rm` is the shape with no blast radius the guard can bound, and it is irreversible. | a **relative** path from the repo root |
| **R10** | `sh -c 'grep … <cp path>'` — a control-plane path inside an interpreter's arguments | An interpreter's arguments are **code, never data**, so a control-plane path inside them can never be cleared. This is the pipe-into-interpreter class lane 2 closed. | run the program from a **file** that names no control-plane path, or use the **Read tool** |
| **R11** `cwd-unknown` | Any **write operand** issued while the guard has lost track of the directory — after `cd -`, a **bare `cd`**, `pushd`/`popd`, a quoted / flagged (`cd -P x`, `cd -- x`) / glob-bearing (`cd conf*`) / `$VAR` / `~`-rooted / **absolute** `cd`, a `cd` hidden behind a `(`/`{` group, or a **cwd inherited from a previous tool call** (including any cwd **outside the protected repo root**, e.g. a dev-clone under `/private/tmp`). ⚠️ **Three prices, all measured, none of them obvious.** (1) It fires on **ordinary files**: `cd $DIR && sed -i s/a/b/ notes.txt` is denied. (2) **An absolute target does NOT help** — `cd $DIR && sed -i s/a/b/ /abs/notes.txt` and `cd $DIR && chmod 644 /abs/notes.txt` are denied, because while lost *every* non-flag operand is disqualifying (`s/a/b/` and `644` are operands too). (3) The **git half** denies branch operations that touch no path at all: `git checkout main`, `git checkout -b feature/x`, even `git worktree list`. (4) A **`-m`/`--body` message containing `>` denies while lost** — `cd -; git commit -m "fix -> thing"` and `cd -; gh pr create --body "a > b"` are denied, because the quoted `>` still reads as a redirect. **Use `-F` / `--body-file`**, which is the same escape this card recommends for R-messages generally. Untouched: reads without a redirect (`cd -; cat notes.txt`, `cd -; echo x`), `npm test`, `git add`, `git commit -F`, and any redirect to an **absolute** path. ✅ **CLOSED by `GUARD-CLOBBER-REDIRECT-INVISIBLE`:** the `>|` **clobber** operator is now judged **exactly as `>`**, everywhere `>` is judged — from the repo root as well as while lost. It was invisible not to the redirect extractor but to the *segmenter*, which split at the `|` before any redirect arm ran; both segmenters now protect the operator and the extractor consumes its `|`. So `echo x >| conformance/verify.sh` denies, `cd -; echo x >| verify.sh` denies `cwd-unknown`, and — by the same "exactly as `>`" rule — **price (4) above extends to `>|` in a message**: `git commit -m "a >| conformance/verify.sh"` denies, with the same `-F` / `--body-file` remedy. Absolute and `~`-rooted clobber targets stay allowed; a `$VAR` clobber target now fails **closed**. | `GUARD-CWD-CONFIDENCE-UNKNOWN`, under `D-240813-3` (fail **by disqualification**, never by parse). The tracker used to return **silently** on every `cd` it could not follow, which read to the rest of the guard as "still at the repo root" — confident, and wrong; `cd conformance` in one call and `sed -i s/a/b/ verify.sh` in the next was a control-plane write with no `cd` in the judged string at all. The narrow "only control-plane-shaped basenames" form was **unbuildable** (there is no leaf table, and building one is the `D-240816-1` enumeration trap). Narrowing the *operand* test, or telling a git branch name from a pathspec, are the same trap one level down — both are **parses**, and both are the owner's call, not a build seat's. So the broad form is deliberate and every price above is pinned by its own cell in `conformance/agent-autonomy.sh`. | use the **Edit/Write tool** (which also carries the dev-clone relaxation the Bash route does not), **or** put the write in a call whose `cd` the guard **can follow** — one literal relative `cd` from the repo root, with no flags, quotes, globs, variables or `..` (`cd docs && sed -i s/a/b/ notes.txt` is **allowed**). Spelling the target absolute does **not** work; that is price (2). |

**Added by `GUARD-READ-EXEC-LANE` (2026-09-08) — three shapes ON to the card.** Each was measured
ALLOW against the live hook before the change and DENY after, and each carries its own cells in
`conformance/agent-autonomy.sh` (`K-3a-A*`, `K-3a-B*`) and a line in `scripts/kit-guard --selftest`.

| # | The shape that gets refused | Why it is now denied (the ruling) | The escape (one retry) |
|---|---|---|---|
| **R12** `read-flag` | A read-lexicon verb carrying a flag that is **not on its vetted set** — `rg --pre <cmd>`, `git grep -O <cmd>`, `grep --filter=`/`--save-config=`, `diff --to-file=`, and **any** flag at all on `column` or `file` (`column -t <cp>`, `file -C -m <cp>`). Also the **cluster** rule: `grep -rne foo <cp>` declines because a cluster must be **all** bare-set letters (`git grep -nO<cmd>` is why). **Quoting does not hide a flag**: `rg -n "--pre=/tmp/e" x <cp>`, `column "-o" <cp>` and `yq "-i" . <cp>` decline exactly as their unquoted spellings do — the quoting decides word boundaries, the dequoted word decides what the flag is. A bare `-` (stdin) is an operand, not a flag. | A lexicon is a verb list; the **exec/write flag lives in the argv**. `grep` on this box IS ugrep, and the guard cannot know its dialect — so the tier is a **positive allowlist** that declines on the unknown flag (`D-240813-3`: fail by disqualification), never a denylist of dangerous ones. The sets are the repo's **measured** usage, not a universe; the deny log is what earns each widening. | drop the flag; use a vetted spelling (`grep -e A -e B`, `rg -n`, `diff -u`, `cat` instead of `column -t`); or the **Read tool** |
| **R13** `line-poison` | Any command whose **earlier segment on the same line** can change what a later verb resolves to — `export`/`declare`/a bare `NAME=value` statement/`alias`/`hash`/`source`/`.`/`eval`/`unset`/`trap`/`read`/`mapfile`/a function definition/`printf -v` — followed by anything naming a control-plane path. Hidden leads count: `( export …; cat <cp> )`, `if …; then export …; fi; cat <cp>`, `command`/`time`/`!`/`'export'`, an assignment **prefix** in front of the poisoning verb (`X=1 export PATH=/tmp; cat <cp>`, `IFS=: read PATH …`), and a loop/condition head (`until`/`while`/`if export …; …; cat <cp>`). ⚠️ **A `case` head poisons the line outright** — the walk has no way through `case x in x) … ;; esac` to the statement inside the arm, so it declines to certify the rest of the line; that is a disclosed over-deny with the same retry. The **whole allow side** closes, not just reads: `export PATH=/tmp; sh conformance/verify.sh` denies too. **Priced over-denies:** a harmless `FOO=1; cat <cp>`, `export FOO=bar && cat <cp>`, `source .venv/bin/activate && sh <kit>`, and the pipe spelling `export FOO=bar \| cat <cp>`. | `export PATH=/tmp:$PATH; head -1 conformance/verify.sh` ALLOWed and the `head` that ran was whatever `/tmp` provided (reproduced twice, 2026-09-06). The set is of **shell constructs**, not variable names: only an in-shell construct can re-route the *same* line, so the set is closed by the grammar — enumerating the variables a reader honours as a program is the `D-240816-1` trap. `set` and `exec` are deliberately **off** the set. | run the read **as its own tool call** — environment does not persist across tool calls anyway, so the line never needed both halves. For a venv, call the **interpreter by path** (`.venv/bin/python …`) instead of activating. |
| **R14** `read-flag` (git) | A `git` **global option that can name a program**, in front of any read subcommand: `git -c <k>=<v> …` (`diff.external`, `core.pager`, `core.hooksPath`, `alias.*=!…`), `git --exec-path=<dir> …`, `git --config-env=… …`. **There is no key allowlist**, so the harmless `git -c color.ui=never log -- <cp>` declines too (priced). Separately, `git stash push -- <cp>` is no longer a read — it **reverts** the working copy. | A config value that names a program turns a read sub into an exec. A key allowlist is the same enumeration trap one level down. `git -C <dir>` and every other global are untouched. | drop the `-c` (or set the config in its own call); for `stash`, use the Edit/Write tool in a dev-clone |

**Added by `GUARD-ADMIN-ARMS` (2026-09-09) — four shapes ON to the card, all deny-side.** Each was
measured ALLOW against the live hook before the change and DENY after, each carries its cells in
`conformance/agent-autonomy.sh` (`K-3b-A*`, `K-3b-B*`, `K-3b-C*`, `K-3b-D*`) and a line in
`scripts/kit-guard --selftest`, and each names **one retry**. What they buy is **loudness on the routes
that move protection itself**: the guard is a speed bump, the durable controls are the credential
(the platform never issuing the agent an admin-scoped token) and server-side branch protection
(`D-240819-4`, `THREAT-MODEL.md` T1). Nothing here makes the guard a control.

| # | The shape that gets refused | Why it is now denied (the ruling) | The escape (one retry) |
|---|---|---|---|
| **R15** `gh-admin-verb` | The `gh` porcelain verbs that ARE a repo-root `PATCH`/`DELETE` or a credential mint: `gh repo edit` (**every** field — `--default-branch`, `--visibility`, and also `--description`, `--add-topic`, `--enable-auto-merge`), `gh repo delete`, `archive`, `unarchive`, `rename`, `gh repo deploy-key add`/`delete`, `gh ssh-key`/`gh gpg-key add`/`delete`. Every joiner spelling goes with them (`GH repo edit`, `gh re''po edit`, `--default-br""anch`), as do an assignment prefix (`GH_REPO=o/r gh repo delete`), `env`, a URL operand and an `sh -c` wrapper. An **unreadable sub-verb** (`gh repo ed$Xit`, `gh repo $V`) is not certified and denies. ⚠️ **Priced over-deny M1:** `gh repo edit --description x` and `--add-topic` are refused with the rest. | Each verb is the CLI client of an endpoint the REST judge already denies through `gh api` — the porcelain must AGREE with the REST rule or the derivation is a lie. The judge denies the repo root under `PATCH` for **any** field ("no legitimate agent traffic writes to any of these paths"), so an arm that enumerated the dangerous flags would claim a rule it does not implement, and enumerating flags is the losing move (`D-240816-1`). | the owner runs it as a keystroke (`!gh repo …`) or in the web UI. **Reads are untouched:** `gh repo view`/`list`/`fork`/`create`/`clone`/`sync`/`set-default`, `gh repo autolink create`, `gh repo deploy-key list`, `gh ssh-key list`, `gh ruleset list`/`view` |
| **R16** `gh-persist` | `gh`'s own persistent state: `gh alias set`, `gh alias import`, `gh config set`, `gh auth login`, `gh auth refresh`, `gh auth switch`. The BODY is never inspected — `gh alias set co 'pr checkout'` is refused exactly as `gh alias set mm 'pr merge --admin'` is. ⚠️ **Priced over-deny M2:** that harmless alias, and `gh config set git_protocol ssh`. | The rule keys on the **primitive that moves bytes out of the command line**, not on what the bytes say. An alias body is a command the guard never sees RUN (it is ceiling (i)'s first half, and this retires it); a config value can name a **program** (`pager`, `editor`, `browser` — the R14 `git -c core.pager=` class one tool over, and the next `gh pr view` runs it); `alias import`'s bodies are in a file. The credential is the same class one level up: `gh auth refresh -s delete_repo` widens the very token the platform-safety boundary rests on. | type the full `gh` command instead; the owner sets aliases, config and credentials by keystroke. **Untouched:** `gh alias list`/`delete`, `gh config get`/`list`, `gh auth status`/`setup-git`/`logout` |
| **R17** `http-admin` | **Any** HTTP client making a mutating request to a GitHub admin endpoint — the merge bypass, branch protection, rulesets, `git/refs`, collaborators, deploy/account keys, the repo root or transfer, the push twins, a forged status. `curl` in every method spelling (`-X PUT`, `-XPUT`, `--request=PUT`, a short cluster `-sXPUT`/`-fsSLX DELETE`), **a body with no method at all** (curl's own rule: a body makes it a POST), `wget --method=`/`--post-data`, httpie/xh's positional `http PUT …`, `/usr/bin/curl`, `command curl`, `$CURL`, `--url`, `--next`, a renamed binary, a scheme-less host, userinfo, an IPv6 literal, `:443`, a GHES `api/v3/` path. A **`..` segment** under a mutating indicator is not certified and denies (**priced M7**), because curl collapses it before sending and a substring match cannot. ⚠️ **Priced M4:** a non-GitHub host with a GitHub-shaped path (`https://example.com/repos/o/r/pulls/5/merge`) — the judge is host-agnostic on purpose. **Priced M5:** `-G` turns a body into a GET and the arm does not honour it. **Priced M3:** a message body quoting one of these (`gh pr create --body "… curl -X PUT …"`). | The client's spelling varies; the REQUEST does not. An enumeration of clients protects only the clients we happened to have, so the arm asks what is being **requested** and hands the path to the same judge `gh api` is measured against. **Judged PER SEGMENT** (security design vet, S-1): a lead-agnostic whole-string match would have re-denied the owner's own A3 read-back through a later pipe stage. | write the read instead (GET/HEAD and any request with no body still allow, **including a piped authenticated read** — `curl -s -H "Authorization: Bearer $TOKEN" …/protection \| grep -F x`); for the write, the owner's keystroke. For M3, use `--body-file`. For M7, write the path plainly. For **M8** — an admin-shaped line whose quoting the walker cannot settle (a backslash-escaped quote, a backtick, `$(…)` or `${…}`, **or a backslash-escaped `;` `\|` `&`**; a plain `$TOKEN` does **not** decline) — split the pipe into two tool calls. That last byte joined the set in fix round 2 because an escaped separator splits the *walker* where the shell does not, and it carries the same price: `curl -s …/protection \| grep -F "a\;b"` now denies, with the same retry |
| **R18** `api-endpoint` | Not a new refusal but a **narrowing and a widening of the existing one**. `gh api`'s operand is now read POSITIONALLY, so an admin path in a **header value, a body field or an `--input` filename** is no longer read as the endpoint (four measured over-denies refunded, plus a fifth). In the other direction a **fragment, a dot-segment, a percent-encoding or a case variant** in a mutating endpoint no longer walks through: `gh api -X PUT repos/o/r/pulls/5/%6Derge` and `…/merge#frag` were complete admin merges and now deny. ⚠️ **Capitals and percent-escapes in ordinary segments are NORMALISED, not refused.** The endpoint is case-folded and percent-decoded (to a fixpoint, so the double-encoded `%256Derge` is caught) and *then* judged, so `repos/SeaBrad72/sparkwright/issues/1/comments`, `repos/MyOrg/my-repo/issues`, `…/labels/Bug` and `…/labels/bug%20fix` all **allow** while `%6Derge`, `%256Derge` and `PULLS/5/MERGE` still deny. Only a `%` that does **not** decode, or a `.`/`..` segment, is refused outright — and that refusal now carries its own reason (`trigger=api-endpoint`) instead of the merge-bypass message. | A substring match over the whole command string cannot tell an endpoint from a decoy, in either direction. The read **DECLINES** on anything it cannot settle — an unknown flag, a second operand, an unreadable cluster, any `$` or backtick — and today's substring verdict then stands, so it can never LOSE a deny (`D-240813-3`, fail by disqualification). ★ A **disqualifier** is the right shape only where the guard cannot know the answer; GitHub case-folds route words and percent-decodes paths, so here it can compute the normal form and ask the ordinary question. The flag table is pinned to `gh 2.96.0`; re-measure when that moves. | for a refused endpoint, spell it plainly — no undecodable `%`, no `.`/`..` segment. A query string is truncated, not refused; capitals and `%20` in an owner, repo or label name need no change |

⚠️ **R18's second ceiling, disclosed rather than closed:** because `exact` mode anchors the WHOLE
endpoint, a few shapes `gh api` itself cannot reach now **allow** where the old substring scan denied
them — `localhost/repos/…`, `[::1]/repos/…`, `//api.github.com/repos/…`, a bare `x/repos/…`, and a
trailing segment on a real endpoint (`…/pulls/5/merge/x`). Each is a 404 from `gh` rather than a
request, but that is a fact about gh's routing, not a property the guard establishes — so **an
exact-mode ALLOW on a host or trailing segment that gh itself 404s is disclosed, not certified.**
The **encoded** spellings of the same head belong to that class and allow for the same reason: the
scheme/host, dot-first-segment and `api/v3/` strips run only on the operand as written, never on what
the percent-decode produced, so `https%3A%2F%2Fapi.github.com%2Frepos%2F…`,
`api.github.com%2Frepos/…` and `api%2Fv3%2Frepos/…` are allowed — as they are on the pre-slice core,
so nothing regressed. A second head-strip pass is deliberately not added; its only subjects would be
strings that never reach GitHub. The **tail** is the opposite case and was fixed rather than
disclosed (an encoded `/`, `?`, `#` or space *did* change a real endpoint's answer).

⚠️ **R18's own open ceiling, measured on BOTH cores and boarded rather than claimed:** `gh api -X PUT
repos/o/r/pulls/5/merge; echo done` (and `; true`, `; ls`) is **ALLOW** — the `_s6_gh_api_admin`
substring scan's family terminator is `([[:space:]/]|$)`, which a `;` is not, and the `gh api`
adjacency is lost across the tail. `&&`, `||` and a leading statement all deny, which is exactly what
makes the shape look closed. Pre-existing, not opened by this slice, and tracked as
`GUARD-GH-API-SEMICOLON-TAIL`. Face C hit the same class in its whole-view fallback and cured it there
(shell separators normalise to spaces before judging); the `gh api` arm gets its own slice because its
75 S6R cells are the regression surface.

**What fix round 1 closed on R17, and what is left.** Three of the arm's own faces were found open by
the reviewer and the security seat and are now shut, each with its cells and a mutant: **(1)** the
cheap `(repos|orgs|user)/` precheck read the RAW command, so a quote or backslash *inside the route
root* (`…/re''pos/…`, `…/rep\os/…`, `"…/repos"/o/r/…`) skipped the whole arm — it now reads the same
joined, quote-deleted bytes the segment judge reads, because a precheck is part of the matcher;
**(2)** the GET/HEAD suppressor was an unanchored substring, so `-A "-X GET"`, `--data-urlencode
"x=-X GET"`, `-H "X: --method=head"`, a second `--request GET` and even curl's *proxy* flag
(`-x get.proxy…`) each suppressed a real mutating request — it is now read as WORDS on the quote-aware
join, the flag letter is case-sensitive, a declined join honours no suppressor, and a method **and** a
GET both present denies (curl takes the last; the guard does not guess — priced **M9**); **(3)** in the
whole-view fallback a LATER stage's GET suppressed an EARLIER admin write — the fallback now never
honours a suppressor, and shell separators normalise to spaces so a `;` cannot hide the endpoint from
the family terminator. **M8 is re-priced accordingly:** the fallback is the deny-ward direction and now
provably so — an admin-shaped line whose quoting the walker cannot settle (a backslash-escaped quote,
a backtick, `$(…)` or `${…}`; a plain `$TOKEN` does **not** decline) is judged whole and denies, and the
retry is to split the pipe into two tool calls. **What remains on R17 is unchanged and is the honest
list:** absent bytes and glue (`curl -X $M …`, `$URL`, `-X PU$()T`) — there is no glue net by design;
curl **config files** (`-K cfg`), whose method and body are outside the command; and the
**interpreters** (`python3 -c "requests.put(…)"`, `node -e "fetch(…)"`), which no byte-level arm reaches.

**Honest ceilings for R15–R18, disclosed rather than closed** (each has an ALLOW cell so a later round
cannot close one silently): the **USE** of an alias (`gh mm 5`) and any alias or config that already
exists — bytes outside the command, and ceiling (i)'s surviving half; **interpreters**
(`python3 -c "requests.put(…)"`, `node -e "fetch(…)"`); **absent bytes and glue** on the HTTP arm
(`curl -X $M …`, `$URL`, `-X PU$()T`) — face C has **no** glue net by design, because a glue
disqualifier over every `curl` would deny every `-H "Authorization: Bearer $TOKEN"` read; a **curl
config file** (`-K cfg`), whose method and body are outside the command; **percent-encoded** route
words and **uppercase** route words on the HTTP arm (GitHub 404s the latter, so it is not live —
face D folds because its endpoint is one token and the fold costs nothing there); httpie's bare
`field=value` body, which carries no named indicator; `gh extension install|exec` (the supply-chain
class, boarded as `GUARD-GH-EXTENSION-IS-CODE`); **GraphQL** (`GUARD-GRAPHQL-ADMIN-SIBLING`);
`gh pr review --approve` and its REST twin (`GUARD-PR-APPROVE-IS-HUMAN`); settings that do not move
protection (Actions permissions, environments, secrets, `workflow disable` — the failure direction is
a **blocked** merge, not a bypass); `gh auth setup-git`/`logout`, `GH_CONFIG_DIR=`; the wider org
surface; and the `( … )` / `{ … }` / `x=$(…)` **wrapper** blindness, which is pre-existing on both
cores (`GUARD-QUOTED-WRAPPER-BLINDS-COMMAND-ARMS`).

⚠️ **The three rows narrow READ RECOGNITION; they do not narrow the WRITE closers.** A redirect onto a
non-literal target still denies for every laundering verb — `rg --pre <exec> x /tmp/y > $V/pre-push`,
`column -t /tmp/a > $V/pre-push`, `git stash list > $V/pre-push` — because the launder arm asks
"is this a verb that emits bytes?" off the **pre-tier** lexicon, not "is this a permitted read?".
R12/R13/R14 can only ever close a lane, never open one.

⚠️ **What is still open, and is boarded rather than closed:** a **profile file** (`~/.zshrc`,
`~/.bashrc`) that exports a poisoned `PATH` poisons every LATER tool call with no poison construct on
the line — R13 closes the same-**line** spelling only (`GUARD-PROFILE-FILE-POISON`). And a
**persistent** `git config diff.external`/`core.pager`/`core.fsmonitor`/`core.sshCommand`/`alias.*`
write still ALLOWs, re-routing every later read sub (`GUARD-GIT-CONFIG-EXEC-KEYS`). Both are the
argument-content ceiling's neighbours: the guard is a speed bump, and the boundary is pre-push + CI.

**Relieved by `GUARD-READ-PATTERN-RELIEF` (2026-09-01) — three shapes off the card.** Each was
measured DENY against the live hook before the change and ALLOW after, and each has its own cells.

- **`cd <dir> && grep 'a|b' <cp>`** (and the `;`-joined, trailing-`cd`, relative-`cd` and
  `| head` variants) now **ALLOWs**: `cd` joined the mask gate. This is the R1 compound form —
  **that row's "any compound" claim is now narrowed to compounds whose other segments are still off
  the gate** (a `for` head, `python3 -c`, a bare `sh <script>`). What `cd` buys is the mask and
  nothing else: `cd x && cp e <guard-core>`, `cd x; grep … > .claude/out` and `cd x && grep <cp> | sh`
  are all still denied.
- **`sed -n 1,5p <file>` / `awk 'NR<=5' <file>` as a segment of a chained read** now **ALLOWs**:
  a `sed`/`awk` segment counts as a gate lead when the strict read grammar already accepts it. A
  `sed -i`, a `w`/`e`/`s` script, an extra flag or a redirect still discards the mask.
- **`sed -n '/a/,/b/p' <cp>`** (and `/re/,5p`, `5,/re/p`) still **denies** — the August pricing
  stands, the retry is `grep` or the Read tool — **but its message no longer advertises
  `KIT_GUARD_SELFEDIT`.** Being told to disarm the guard globally in order to read was the harm; the
  exact-grammar tip and this escape card are what the message carries instead. Write forms (`-i`,
  `w`, `e`, `s`, and anything with a `>` byte — `2><guard-core>` truncates it) keep the sentence.

> **TIP — the one heredoc shape that still surprises.** A lone `cat > file <<'EOF'` whose *body*
> contains a second `<<` is scanned raw, so a control-plane path in that body denies. Write the body
> to a file with the Write tool instead.

**These are the *acceptable* failure direction.** `D-240813-3` (three reverted parser rounds, each
one reopening a real write hole) settled that an over-deny with a named escape beats a cleverer
parser. What this card fixes is the *cost* of that choice: it was paid once per session, by every new
agent, because the escapes were scattered across tip strings.

**Relieved in lane 3 — no escape needed any more.** The corpus these six came from had ten shapes;
three were judged *relievable* rather than kept-denied, and `GUARD-READ-LANE-3` relieved them. They
are recorded here so nobody reaches for a workaround that is no longer needed:

- **R3** — `find <cp root> … -exec <read verb> {} +` now **ALLOWs** for the read verbs on
  `_CP8B_FIND_EXEC_READ_VERBS` (`cat head tail wc nl od cksum md5 md5sum shasum sha1sum sha256sum
  stat grep`). Every other `-exec` verb, `-execdir`, `-ok`, `-delete` and `-fprint*` still deny.
  ⚠️ **The verb may carry GLUED SHORT FLAGS ONLY, and no operand of its own.** After the verb the
  grammar accepts `-`-led flag tokens and exactly one `{}`, then `+` — nothing else. So, measured:
  `-exec grep -efoo {} +` **ALLOWs** (the pattern is glued to the flag), while `-exec grep foo {} +`
  (bare operand), `-exec grep -e foo {} +` (**spaced** value — the value is a bare operand),
  `-exec grep --regexp=foo {} +` (any `=`-joined flag is refused outright), a second `{}`, and
  `\;` instead of `+` all still **deny**. The `\;` refusal is the `D-240813-3` decline set being
  absolute on the backslash byte; use `+`, which is also the faster spelling.
- **R6** — `sh conformance/branch-protection.sh --declared-only <cp path>` now **ALLOWs**: the kit's
  own read-only verification, invoked as documented, no longer refuses to read its own tree. This is
  a **declared table** (`_cp8b_kit_query_toks`), not a general rule — an unlisted check with a
  control-plane argument still denies, and each listed pair is *run* by `agent-autonomy.sh`'s Arm-A
  coupling lock and proved not to mutate the worktree.
  ⚠️ **The relief is ARGUMENT-UNCONSTRAINED, and that is deliberate.** `--declared-only <any path>`
  ALLOWs — `.claude/hooks/guard-core.sh` and `conformance/verify.sh` as readily as the `profiles/`
  one — because the check is offline and read-only *whatever* it is pointed at, so the argument is
  data. Read the lock's guarantee precisely: **it proves the SCRIPT, not the argument.** It runs the
  pair and asserts the worktree did not move; it says nothing about which paths are safe to name. If
  a listed script ever gained an argument-dependent write, the census and the lock would both stay
  green — which is why membership is a ratified deny-removal and not a convenience. Adding a pair costs one table line, one lock
  line and a green census leg. The **launcher is not constrained** either: `sh`, `bash`, `dash`,
  `zsh`, `ksh`, `./conformance/branch-protection.sh` and the bare path all ALLOW. That is the arm's
  pre-existing shape, shared by all four declared pairs — the launcher does not change what the
  script does, and the lock's guarantee is about the script.
- **R7** — a **quoted** heredoc (`<<'EOF'`) whose consumer is one of those declared kit queries now
  has its body ruled **inert**, so the entry contract's own act 1
  (`promotion-readiness.sh --class --changed /dev/stdin <<'EOF' … EOF`) runs. An *unquoted*
  delimiter, `<<-`, a shell or interpreter consumer (`sh <<'EOF'`, `python3 - <<'EOF'`), a
  control-plane redirect target, and a separator *after* the `<<` all keep today's scan —
  ⚠️ **and so does a separator ANYWHERE BEFORE the `<<`: the kit query must BE the consumer.**
  `<kit query> ; python3 /dev/stdin <<'EOF'` is refused, because the command that reads the body is
  the one after the separator, not the harmless one in front of it. (An earlier draft of this card
  said only that a shell or interpreter consumer keeps the scan; that was false as written — it read
  as though putting a recognised query in front were enough, which is exactly the shape the security
  seat found. The same rule now also refuses `cat x; python3 /dev/stdin <<'EOF'`, which was ALLOW
  before this slice.)

Everything else in the ten-shape corpus is either one of the six above or a **correct** deny
(`git reset --hard`, `git push --force-with-lease`, `git notes merge`).

### Reading the deny log

Since `GUARD-DENY-LOG` the guard **records** its denials, so "are the read lanes getting better" is a
number rather than a chat tally.

- **The file:** `<repo-root>/.kit-run/guard-denials.ndjson` — one JSON object per line. It is
  **local**: already in `.gitignore`, never committed, never exported to adopters, never pushed. It
  lives in the same run directory as the runaway killswitch's tally (`runaway-killswitch.md`).
- **The fields**, in order: `ts` (UTC ISO-8601) · `surface` (`pretooluse` | `kit-guard`) · `tool`
  (`Bash`/`Write`/… or `-`) · `arm` (the reason's numeric tag, e.g. `13`) · `trigger` (e.g. `pathhit`,
  `redir-nonliteral`, or `-`) · `segment` (the guard's own offending segment, ≤160 bytes, control
  bytes stripped) · `read_shaped` (`1` when the refused thing was a **read** — the closure metric) ·
  `session`.
- **The summary:** `sh scripts/kit-guard --denials [--since <ISO>] [--last <n>] [--file <p>] [--json]`
  — totals by arm, trigger, surface and session, plus the count and the segments of the read-shaped
  denials. No `jq` required.
- **What is recorded, stated precisely.** The `segment` field holds **the offending segment, ≤160
  bytes, redacted for common secret shapes — NOT a guarantee that no secret can appear; the offending
  segment of a one-segment command IS the command.** Redaction masks **every** assignment in the
  leading `NAME=VALUE` run, `Authorization:`/`Bearer `/`Basic `, `x-api-key:`/`api-key:` headers,
  `token=`, `api_key=`, `password=`, `secret=`, `curl -u user:pw`, a `-p`/`-p <value>` password
  argument (mysql/psql style), JSON `"token"`/`"password"`/`"secret"`/`"api_key"` values (escaped
  quotes included), and URL userinfo (`://user:pw@`). An unrecognised secret shape still lands in
  the file.
  Treat `.kit-run/` as you would any local scratch: not for sharing, not for pasting into an issue.
- **Turn it off:** `KIT_GUARD_LOG=0` in the launching shell. The log write is failure-swallowed and
  always succeeds from the caller's point of view, so **logging can never change a verdict** — a full
  disk, a read-only `.kit-run`, or a planted FIFO/symlink at the log path cannot turn a deny into an
  allow, and cannot delay one either (the decision is printed before the log is touched).
- **The number is a FLOOR, not a census.** The instrument is cooperative — `KIT_GUARD_LOG=0` disables
  it — so a count read off this file is a lower bound on what actually happened. Sanctioned uses of
  the off switch are the selftest battery (which would otherwise flood the log with ~100 synthetic
  denials per run) and a deliberate operator opt-out. Nothing detects a third use.
- **No rotation, deliberately.** The file is append-only and unbounded; nothing truncates or rolls it.
  **Delete the file to reset a measurement window** — that is the intended workflow for a harvest.
- **Planted nodes are refused.** The logger writes only when `.kit-run` is a real directory and the
  log path is absent, or a regular non-symlink file **with a link count of 1**. A FIFO there used to
  hang the hook; a symlink there used to make the logger an append primitive onto the link's target;
  a **hardlink** did the same while passing both of those tests (it is a regular, non-symlink file —
  only the link count gives it away). All three now decline silently. The file is created `0600`.
  The check is TOCTOU-imperfect by construction — it stops a planted node, not a race — and when the
  link count cannot be read at all it defaults to writing, because losing the harvest on a platform
  without `stat` would be a worse failure than the narrow primitive it guards.
- **It is an observation, never a control.** The file is agent-writable and unauthenticated; nothing
  in the kit gates on it, and nothing should (`THREAT-MODEL.md`, T5).

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
| `KIT_ANYTHING=1 sh <kit-script>` (unvetted prefix) | the vetted-name allowlist is closed on purpose; adding a name per false positive is enumeration creep | use a vetted name, or set the variable **in its own tool call** — an `export` earlier on the *same line* closes the read lane (R13) |

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
