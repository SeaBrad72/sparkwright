#!/bin/sh
# kit-update.sh — bring an adopted project up to a newer Sparkwright release.
#
#   sh scripts/kit-update.sh --from <git-url|local-path> [--repo <path>]   # the update: report + patch
#   sh scripts/kit-update.sh --reconstruct-base <dir>    [--repo <path>]   # just BASE (the merge base)
#   sh scripts/kit-update.sh --advance-base --from <src> [--at <sha>] [--repo <path>] [--remote <name>] [--no-push]
#                                                                        # record what HEAD took, then publish it
#
# It REPORTS. It does not APPLY: it prints what a new release would change, writes a patch to a scratch
# path, and leaves every decision — and every write — to you. The ONE job that writes to the adopter's repo
# is --advance-base (below): it moves `refs/heads/kit-base` and, when the release is FULLY taken, adds ONE tag,
# and nothing else; then it publishes those refs to the remote (one atomic, never-forced push).
#
# ── THE FLOW (KIT-UPDATE-PARTIAL-ADOPTION) ────────────────────────────────────────────────────────────
#   `--from <src>` (report + patch) -> you apply what you want, open the PR -> the PR merges and is pulled ->
#   THE AGENT runs `--advance-base --from <src>` (mechanical; no human keystroke; `--from` never writes) ->
#   the next `--from` is computed against what HEAD actually took.
# `--advance-base` records PER PATH what HEAD took: a path is TAKEN when HEAD has the release's content (or
# git's own 3-way says the release's hunks are already in HEAD's file); any other path the release changed is
# BEHIND. The new chain commit carries `behind <chain commit> <path>` lines and a `Kit-Behind: <N>` trailer
# (always present). A partial advance (N > 0) moves `kit-base` alone and creates NO tag — a tag always names a
# release fully taken; `--from` then rebuilds BASE from the effective base (each behind path from the chain
# commit it names), so the remainder is offered (or CONFLICT), never hidden. Re-run `--advance-base` at the
# same release to finish it: it records what you have taken since, and tags when N reaches 0.
#
# ── kit-base IS A CHAIN (KIT-UPDATE-BASE-ADVANCES) ─────────────────────────────────────────────────────
# `kit-base` used to be written once, at inception. After an update merged, every file it applied differed
# from BASE on the adopter's side too, so it read "changed BOTH" (CONFLICT) forever and its newer upstream
# content was never offered. Now `kit-base` is a CHAIN of the releases the adopter TOOK, one commit each,
# newest at the tip, each commit carrying `Kit-Source: <vendor sha>` / `Kit-Version: <VER>` trailers (VERSION
# alone cannot tell two pre-release commits apart; the export's `.kit-source` names the commit). The vendor
# sha HEAD took is RECORDED in `HEAD:.kit-source` — the update's own patch carries it — so
#   * `--from` REFUSES a STALE base (HEAD:.kit-source is not the tip's Kit-Source) and prints the one
#     `--advance-base` command that fixes it: a stale base yields a WRONG delta, worse than none;
#   * `--advance-base` appends the release HEAD took (parent = the old tip; kit-base is a compare-and-swap;
#     the tag `kit-base/v<VER>+<sha12>` is create-only). For a LEGACY tree with no `.kit-source` the sha comes
#     from `--at <sha>`, and is announced ASSERTED — not recorded;
#   * a path is kit-PRISTINE when its content equals the incepted blob at ANY chain commit (not only the
#     latest). Pristine + changed upstream => OFFERED (including a hunk the adopter declined last time —
#     declining is not permanent: edit the file to keep it; a kit file you DELETED after taking it is offered
#     again too — absent == absent at an older release — so keep declining that hunk, the patch is only a
#     suggestion). Equal to THEIRS => CURRENT. Not pristine, changed
#     on both sides => CONFLICT. The patch is OURS -> THEIRS on the offered paths.
#
# ── THE IDEA (read this before changing anything below) ───────────────────────────────────────────────
# An adopter's tree is NOT a copy of the kit export. It is `incept(export)` — a TRANSFORMATION. incept
# RENAMES CLAUDE.md -> ENGINEERING-PRINCIPLES.md, rewrites cross-references in six more kit files,
# RE-CREATES CLAUDE.md as an adopter-owned project doc from a template, and wires the stack's CI +
# scaffold. So `kit-base` (the pristine export, vendored on an orphan branch at inception) and the
# adopter's worktree live in DIFFERENT COORDINATE SYSTEMS.
#
# Diffing them directly is meaningless: it reports a conflict on every file incept touched, and it
# proposes restoring the KIT's CLAUDE.md over the ADOPTER's project doc — at the same path. That is not
# a merge, it is data loss with a progress bar.
#
# We do not reverse the transformation and we do not RE-DESCRIBE it. We RE-APPLY it, so it cancels:
#
#   BASE   = incept(kit-base)                 <- run with KIT-BASE'S OWN scripts/incept.sh
#   OURS   = the adopter's HEAD               <- untouched
#   THEIRS = incept(export(new release))      <- run with the NEW RELEASE'S OWN scripts
#
# Each side runs through the incept that BELONGS to it, with the SAME recorded stamps and the SAME pinned
# --date, so the transformation CANCELS and only genuine kit changes survive. NEVER hand-maintain a
# rename/ownership table and NEVER re-implement the export/prune: either would be a second source of truth
# about incept's behavior and would rot the first time incept changed. Re-running the real scripts IS the
# design.
#
# THE PROOF THAT THIS IS RIGHT — the IDENTITY PROPERTY (conformance/kit-update-identity.sh):
#   for an adopter who changed NOTHING, incept_old(kit-base) == their HEAD, EXACTLY (empty diff).
# A missed rename, an unpinned date, a wrong prune or a missing stamp all fail it LOUDLY. And it cannot
# be satisfied by a dead code path: an updater that does nothing produces an EMPTY tree, not an EQUAL
# one. That asymmetry is what makes the green non-vacuous.
#
# ── READ THE FACT; REFUSE, NEVER GUESS ───────────────────────────────────────────────────────────────
# A WRONG base silently produces a WRONG delta — strictly worse than no delta at all, because the adopter
# would trust it. So EVERY input this needs is RECORDED: incept stamps all of them into CLAUDE.md §3, and
# this reads them. Nothing is defaulted. In particular an absent adoption date must NEVER become "today" —
# that is the exact fail-open `incept --date` was built to prevent (it exits 2 on an empty value; we rely
# on that rather than working around it).
#
# INFERENCE IS THE FALLBACK, NOT THE DESIGN. Two inputs (the CI platform, the DB archetype) were stamped
# only from T3b onward, so a tree incepted before that carries no record and evidence is all there is. For
# those — and ONLY those — we derive from the two trees, and we SAY SO in the output: an inference is
# announced as an inference, never printed as a fact. Where it cannot decide, it refuses.
#
# ── THE HONEST CEILING (it is PRINTED on every --from run, not just written here — see the tail) ──────
# LATEST ONLY · IT PRESENTS, IT DOES NOT APPLY · IT NEEDS AN INTACT kit-base · AND `--from` IS UNTRUSTED
# INPUT WHOSE CODE THIS TOOL EXECUTES. The last one is not a footnote: building THEIRS means running the
# new release's OWN adopter-export.sh and incept.sh. That is inherent to the design (and to adoption —
# running a kit's incept is the normal path), but the user deserves to be told at the moment they aim it.
#
# Exit: 0 ok · 1 runtime/refusal · 2 usage · 3 (--advance-base only) the local write stands but the publish
# failed. POSIX sh; dash-clean.
# What it changes: --from and --reconstruct-base: nothing in the adopter's repo — they write ONLY the <dir>
#                  you name (--reconstruct-base, which must be empty/absent and OUTSIDE any git repo), temp
#                  dirs they remove, and a patch file at a scratch path they print. --advance-base writes
#                  EXACTLY: `refs/heads/kit-base` (compare-and-swap on the old tip), ONE new tag
#                  `kit-base/v<VER>+<sha12>` ONLY when the release is fully taken (create-only, never moved),
#                  and the objects behind that commit (the tree + the commit land in the adopter's object
#                  store — that is how a commit is made). No worktree, index, HEAD or config write. Undo:
#                  `git update-ref refs/heads/kit-base <old tip>` (the old tip is printed) and, when a tag
#                  was made, `git tag -d <tag>`. PUBLISH: after the local write it runs ONE `git push
#                  --atomic` (never --force, no '+' refspec) of refs/heads/kit-base -> the remote's NON-BRANCH
#                  ref refs/kit/base (not refs/heads/kit-base: the kit's pre-push hook grades every branch
#                  push, and a base commit has no Kit-Row), + the local kit-base/* tags that point into the
#                  chain, to --remote (default origin), through YOUR git credentials and config. No such
#                  remote: it says "kit-base stays local", rc 0. Rejected (the remote's refs/kit/base moved):
#                  the local write STANDS, rc 3, the cause and the reconcile hint are printed, nothing is
#                  forced. --no-push keeps it all local (and skips the "HEAD is on the shared line" refusal).
#                  An undo of a PUBLISHED base is an explicit `git push <remote> +<old tip>:refs/kit/base`
#                  that a human runs.
#                  KIT-BASE-SHARED — --from AND --advance-base ALSO IMPORT the remote's refs/kit/base (default
#                  remote origin, --remote <name>), and that is the one write --from makes: when this clone has
#                  no kit-base, or the remote's chain extends yours, `sync_base` fetches refs/kit/base through a
#                  temporary refs/kit-import/base (fsck'd, deleted at once), VERIFIES every commit it would
#                  import (verify_chain_commit) and only then writes `refs/heads/kit-base` (create-only, or a
#                  compare-and-swap fast-forward) + the chain's own create-only `kit-base/*` tags in ONE
#                  `update-ref --stdin` transaction, printing the undo. Anyone with push access to the remote
#                  can write refs/kit/base, so a chain that fails verification, or is diverged, is NOT imported:
#                  with a local base the run WARNS and continues on it (rc unchanged); with none it ends, rc 1.
#                  Objects and FETCH_HEAD land in the adopter's repo as with any fetch. `--publish-base
#                  [--remote <name>]` pushes the base you hold (the advance's one atomic, never-forced push) and
#                  writes nothing locally.
# Guardrails: --from / --reconstruct-base read the adopter via `git archive`/`git
#             fetch` into a THROWAWAY workbench repo; apart from the verified base import above they never write
#             their worktree, index, refs, objects or config. The merge is
#             `git merge-tree --write-tree` (no checkout at all) where the git can do it, and otherwise
#             plain `git merge` in a temporary worktree OF THE WORKBENCH — non-mutating either way, and
#             the tool PRINTS which one ran. The choice is a runtime CAPABILITY PROBE, not a version
#             parse. Refuses (loudly, naming the missing thing) rather than defaulting. An EMPTY
#             computation — including an empty merged tree — is a hard failure, never a quiet "0 changes".
set -eu
# comm/join/sort compare in the CALLER's locale: every list here is sorted under LC_ALL=C, and GNU comm aborts
# ("file 1 is not in sorted order") under e.g. en_US.UTF-8 on C-sorted kit paths. Pin it for the whole run.
# Nothing user-facing depends on the locale (git messages we match are English; paths print byte-for-byte).
LC_ALL=C; export LC_ALL
# KIT-BASE-SHARED (security G4): no `refs/replace/*` ref may substitute the content of a chain commit this tool verifies, archives
# or walks. Every git below inherits this (the scrubbed wrappers `env -u` only the names they list). Not a switch: the greppable
# line `GIT_NO_REPLACE_OBJECTS=1; export …` is replaced by an `unset` in a COPY by conformance/kit-base-shared.sh (M3) to prove its leg needs it (git treats =0 as SET, so 0 would not do).
GIT_NO_REPLACE_OBJECTS=1; export GIT_NO_REPLACE_OBJECTS

USAGE='usage: kit-update.sh --from <git-url|local-path> [--repo <path>] [--merge-impl auto|merge-tree|worktree]
       kit-update.sh --reconstruct-base <dir> [--repo <path>]
       kit-update.sh --advance-base --from <git-url|local-path> [--at <sha>] [--repo <path>] [--remote <name>] [--no-push]
       kit-update.sh --publish-base [--repo <path>] [--remote <name>]
       (--from and --advance-base also take --remote <name>: the remote whose refs/kit/base they import, verified)'
usage() { echo "$USAGE" >&2; exit 2; }

die() { echo "kit-update: $*" >&2; exit 1; }

# THE PRISTINE-CHAIN WALK DEPTH. `all` = a path is kit-pristine if it equals the incepted blob at ANY kit-base
# chain commit (tip -> root, each older base built lazily, only while some path is still undecided); `tip`
# would check only the latest. This is the ONE greppable line conformance/kit-update-advance.sh (leg A10)
# flips to `tip` in a COPY to prove the declined/stranded legs (A5, A6) genuinely need the walk. Keep it a
# bare top-level assignment on its own line.
_KU_CHAIN_WALK=all

# THE PER-PATH PROVENANCE SWITCH. `on` = --advance-base records which paths HEAD did NOT take (the `behind`
# block + `Kit-Behind: N`). `off` = it records 0 behind — what it did before KIT-UPDATE-PARTIAL-ADOPTION: a
# partly taken release is written down as taken whole, and the remainder is hidden. The ONE greppable line
# conformance/kit-update-advance.sh flips to `off` in a COPY to prove A15 and A17 genuinely need the
# provenance. Keep it a bare top-level assignment on its own line.
_KU_BEHIND=on

# THE STRICT-PARSE SWITCH. `on` = read_behind insists every `behind <sha> <path>` line names a commit that is an
# OLDER member of the kit-base chain. `off` drops that one check (the A21 mutant, in a COPY): a forged sha is then
# taken on trust, so conformance/kit-update-advance.sh proves A21 genuinely needs it. Keep it a bare top-level
# assignment on its own line.
_KU_BEHIND_STRICT=on

# THE IMPORT-VERIFICATION SWITCH (KIT-BASE-SHARED). `on` = a kit-base chain commit fetched from the remote is written
# only after verify_chain_commit has checked its TREE against the exports that its Kit-Source's OWN exporter produces
# (every entry must be one of them; no symlink, no submodule). `off` skips that tree check (the M1 mutant, in a COPY):
# a forged scripts/incept.sh in a pushed chain commit is then imported — and RUN by the next --from — so
# conformance/kit-base-shared.sh proves S5 genuinely needs the control. Keep it a bare top-level assignment on its own line.
_KU_VERIFY_IMPORT=on

# THE ANCHOR SWITCH (KIT-BASE-SHARED, H2). `on` = an imported chain commit's Kit-Source must be a release this project's OWN
# history recorded in .kit-source. `off` (the M2 mutant, in a COPY) drops that one check: a chain claiming a genuine release
# the project never took is then imported, so conformance/kit-base-shared.sh proves the anchor test needs it. Keep it bare.
_KU_ANCHOR=on

# ── selftest_sanitizer_bash_unset : the BASH-AS-/bin/sh regression lock for _ku_git
# (SANITIZER-UNSET-RESTORES-EXPORTED), the twin of the legs in conformance/inception-done.sh (b10)
# and conformance/guard-wired.sh. It extracts the SHIPPED sanitizer from this very file (so it grades
# the deployed text, not a copy) and runs it under `bash` with the hermetic lane's face-(a) triad
# EXPORTED and a forged `core.hooksPath` applied as a TEMPORARY PREFIX on a function call. In
# bash-as-/bin/sh, `unset` of a variable that carried a prefix assignment over an ALREADY-EXPORTED one
# RESTORES the exported value instead of removing it, so an `unset`-based sanitizer lets the forged
# GIT_CONFIG_KEY_0 through and the probe prints `hooks`.
# ⚠️ Under `dash` this leg is TAUTOLOGICAL (dash's unset removes the variable outright); it is run
# under `bash` EXPLICITLY because macOS /bin/sh IS bash 3.2.
# ⚠️ HONEST CEILING — WHY THE FLAG IS `--sanitizer-selftest` AND NOT THE KIT'S USUAL SPELLING: this
# tool ships no self-test mode, and conformance/ci-selftest-coverage.sh makes any script that HANDLES
# the usual flag owe a step in .github/workflows/ci.yml. Wiring one is outside this slice's declared
# file scope, so the leg is runnable (`sh scripts/kit-update.sh --sanitizer-selftest`) but NOT yet run
# by any gate: the enforced twins are the two conformance files above, which cover the same class.
# Not advertised in USAGE — it is a maintainer probe, not an adopter-facing mode.
selftest_sanitizer_bash_unset() {
  if ! command -v bash >/dev/null 2>&1; then
    echo "kit-update --sanitizer-selftest: SKIP (no bash on PATH — the regression it locks is bash-only)"
    return 0
  fi
  _sbu_d=$(mktemp -d) || { echo "kit-update --sanitizer-selftest: FAIL (no tmpdir)" >&2; return 1; }
  git -C "$_sbu_d" init -q >/dev/null 2>&1 || true
  # anchor on the OPENING of the function definition (security L2): `/^_ku_git/` alone would start the
  # extraction at the first column-0 line merely BEGINNING with the name.
  _sbu_src=$(awk '/^_ku_git\(\) \{/,/^}$/' "$0")
  # TWO VECTORS (review I-1): the config-injection triad AND the LOCATOR pair — GIT_DIR/GIT_WORK_TREE
  # at a DONOR repo whose own config carries core.hooksPath — each ambient-exported and re-applied as
  # the temporary prefix that `unset` restores. Either leak prints a value.
  _sbu_dn=$_sbu_d/donor; { git init -q "$_sbu_dn" && git -C "$_sbu_dn" config core.hooksPath DONOR; } >/dev/null 2>&1 || true
  _sbu_out=$( cd "$_sbu_d" && HOME="$_sbu_d" XDG_CONFIG_HOME="$_sbu_d" \
      GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.useConfigOnly GIT_CONFIG_VALUE_0=true \
      GIT_DIR="$_sbu_dn/.git" GIT_WORK_TREE="$_sbu_dn" \
      bash -c "$_sbu_src
_sbu_probe() { _ku_git config --get core.hooksPath; }
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=hooks _sbu_probe
GIT_DIR='$_sbu_dn/.git' GIT_WORK_TREE='$_sbu_dn' _sbu_probe" 2>&1 ) || true
  rm -rf "$_sbu_d" 2>/dev/null || true
  if [ -z "$_sbu_out" ]; then
    echo "kit-update --sanitizer-selftest: OK (_ku_git neutralizes a forged prefix-over-exported GIT_CONFIG triad AND GIT_DIR/GIT_WORK_TREE locator pair; bash-as-/bin/sh, tautological under dash)"
    return 0
  fi
  echo "kit-update --sanitizer-selftest: FAIL (_ku_git let a forged core.hooksPath through under bash-as-/bin/sh -> [$_sbu_out])" >&2
  return 1
}

# ── selftest_proxy_passthrough : KIT-UPDATE-GIT-PROXY-PASSTHROUGH. Extracts the SHIPPED wrappers from this file (the
# deployed text, not a copy), puts a shim `git` first on PATH that RECORDS the command-scope config it was started
# with (`git config --show-scope --list`, run by the shim under the wrapper's scrubbed environment), and drives each
# wrapper under an ambient GIT_CONFIG_PARAMETERS that carries the proxy's two entries plus hostile ones. The ambient
# value is produced by git itself (a `-c` alias echoing it), never assembled in shell. Legs:
#   1 only the proxy's two entries reach adv_push and ku_net; adv_git and _ku_git see none (the load-bearing negative)
#   2 no proxy variable: nothing is forwarded     3 a scope mismatch (port, scheme) forwards no helper
#   3b positive anchors: userinfo+path, a default port and https_proxy-over-HTTPS_PROXY still match
#   4 a newline in a selected value: nothing forwarded and the call is still made
# The guard-verdict leg (the printed remedy is ALLOWED, the old raw push DENIED) lives with the guard's other verdict
# cells in conformance/agent-autonomy.sh (KUGP-1, KUGP-2): a guard verdict needs the hook, which this file must not load.
selftest_proxy_passthrough() {
  _pp_tag="kit-update --sanitizer-selftest (proxy passthrough)"
  _pp_d=$(mktemp -d) || { echo "$_pp_tag: FAIL (no tmpdir)" >&2; return 1; }
  _pp_real=$(command -v git) || { rm -rf "$_pp_d"; echo "$_pp_tag: FAIL (no git on PATH)" >&2; return 1; }
  _pp_fail=0; _pp_t=$(printf '\t')
  mkdir -p "$_pp_d/bin" "$_pp_d/wt"
  env -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT -u GIT_DIR -u GIT_WORK_TREE HOME="$_pp_d" "$_pp_real" init -q "$_pp_d/repo" >/dev/null 2>&1 || _pp_bad "could not init the scratch repo"
  cat > "$_pp_d/bin/git" <<'KUEOF'
#!/bin/sh
if [ "$1" = config ]; then exec "$KU_REAL_GIT" "$@"; fi
{ echo called; echo "count=${GIT_CONFIG_COUNT-unset}"; echo "keys=$(env | sed -n 's/^\(GIT_CONFIG_KEY_[0-9]*\)=.*$/\1/p' | tr '\n' ' ')"; "$KU_REAL_GIT" config --show-scope --list 2>/dev/null | grep '^command'; } > "$KU_REC"
exit 0
KUEOF
  chmod +x "$_pp_d/bin/git"
  cat > "$_pp_d/drv.sh" <<'KUEOF'
. "$KU_D/defs.sh"
REPO=$KU_D/repo; REMOTE=origin; ADV_GD=$KU_D/repo/.git; ADV_IDX=$KU_D/idx; ADV_WT=$KU_D/wt
PATH=$KU_D/bin:$PATH; export PATH
cd "$KU_D/repo"
KU_REC=$KU_D/rec.adv_git; export KU_REC; adv_git status
KU_REC=$KU_D/rec._ku_git; export KU_REC; _ku_git status
KU_REC=$KU_D/rec.adv_push; export KU_REC; adv_push refs/heads/x
KU_REC=$KU_D/rec.ku_net; export KU_REC; ku_net ls-remote origin
KUEOF
  awk '/^(_ku_proxy_cfg|_ku_proxy_refused|adv_git|adv_push|_ku_git|ku_net)\(\) \{/,/^}$/' "$0" > "$_pp_d/defs.sh"
  [ "$(grep -c '() {' "$_pp_d/defs.sh")" = 6 ] || _pp_bad "the extraction did not find the six shipped functions"
  _pp_amb=$( cd "$_pp_d" && env -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT HOME="$_pp_d" "$_pp_real" \
      -c http.proxyAuthMethod=basic -c 'credential.http://localhost:61999.helper=!proxyhelper' \
      -c 'credential.https://github.com.helper=!evil1' -c 'credential.http://other:1.helper=!evil2' \
      -c 'url.https://evil.example/.insteadOf=https://github.com/' -c core.hooksPath=/evil -c core.sshCommand=evil \
      -c http.extraHeader=X:evil -c 'alias.kuenv=!printf %s "$GIT_CONFIG_PARAMETERS"' kuenv ) || _pp_amb=''
  [ -n "$_pp_amb" ] || _pp_bad "could not capture the ambient GIT_CONFIG_PARAMETERS from git"
  _pp_nl=$(printf 'a\nb')

  # leg 1 — the proxy's two entries, and only them, on the two network wrappers
  _pp_run "$_pp_amb" HTTPS_PROXY=http://localhost:61999
  _pp_net_ok "leg 1"
  _pp_local_none "leg 1"
  # leg 2 — no proxy variable: nothing forwarded, the call is still made
  _pp_run "$_pp_amb"
  _pp_net_none "leg 2 (no proxy variable)"
  _pp_local_none "leg 2"
  # leg 3 — a scope mismatch forwards no helper (a different port; a different scheme)
  _pp_run "$_pp_amb" HTTPS_PROXY=http://localhost:62000
  _pp_net_nocred "leg 3 (different port)"
  _pp_run "$_pp_amb" HTTPS_PROXY=https://localhost:61999
  _pp_net_nocred "leg 3 (different scheme)"
  # leg 3b — the positive anchors: userinfo and a path are stripped; lowercase https_proxy wins over HTTPS_PROXY
  _pp_run "$_pp_amb" HTTPS_PROXY=http://user:pw@localhost:61999/some/path
  _pp_net_ok "leg 3b (userinfo + path)"
  _pp_run "$_pp_amb" https_proxy=http://localhost:61999 HTTPS_PROXY=http://localhost:1
  _pp_net_ok "leg 3b (https_proxy over HTTPS_PROXY)"
  # leg 4 — a newline in a selected value: fail closed to the plain scrub, and the call is still made
  # The newline must be IN the selected value (git -c cannot carry one into the capture), so the ambient config is the
  # GIT_CONFIG_COUNT/KEY/VALUE form, which keeps it intact. PRECONDITION: git itself must report a newline inside that
  # value (key NL, then a value holding a second NL = 2 newlines in the -z output); if not, this leg would pass
  # vacuously, so it FAILS instead.
  _pp_nlout=$( env -u GIT_CONFIG_PARAMETERS HOME="$_pp_d" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.http://localhost:61999.helper \
      "GIT_CONFIG_VALUE_0=!a$_pp_nl" "$_pp_real" config --show-scope -z --get-regexp '^credential' | tr '\000' 'X' | tr -d -c '\n' | wc -c | tr -d ' ' ) || _pp_nlout=0
  [ "${_pp_nlout:-0}" -ge 2 ] || _pp_bad "leg 4 is vacuous: git did not report a newline inside the helper value"
  _pp_run "" HTTPS_PROXY=http://localhost:61999 GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.http://localhost:61999.helper "GIT_CONFIG_VALUE_0=!a$_pp_nl"
  _pp_net_none "leg 4 (newline in a value)"
  _pp_local_none "leg 4"
  # leg 5 — a RS byte (0x1e) inside a REPO-LOCAL helper value must not forge a command-scope record. The value is on the
  # matched key, so git prints it; the helper reads in the repo that is the driver's cwd. PRECONDITION: git must hand the
  # RS bytes back, else the leg is vacuous and FAILS. No command-scope proxy entries exist, so the right answer is COUNT=0.
  _pp_forge=$(printf 'x\036command\036credential.http://localhost:61999.helper\n!evil')
  env -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT HOME="$_pp_d" "$_pp_real" -C "$_pp_d/repo" config --local \
      'credential.http://localhost:61999.helper' "$_pp_forge" >/dev/null 2>&1 || _pp_bad "leg 5: could not set the forged local value"
  _pp_rs=$( env -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT HOME="$_pp_d" "$_pp_real" -C "$_pp_d/repo" config --local -z --get-regexp '^credential' \
      | tr -d -c '\036' | wc -c | tr -d ' ' ) || _pp_rs=0
  [ "${_pp_rs:-0}" -ge 2 ] || _pp_bad "leg 5 is vacuous: git did not return the RS bytes from the local value"
  _pp_run "" HTTPS_PROXY=http://localhost:61999
  _pp_net_none "leg 5 (RS forgery in a local value)"
  _pp_local_none "leg 5"
  # leg 6 — _ku_proxy_refused: the proxy's refusal is recognised, a rejection or a sha holding 407 is not (stdin closed)
  printf "fatal: unable to access 'https://x/r.git/': Proxy CONNECT aborted\n" > "$_pp_d/log.a"
  printf 'fatal: unable to access: Received HTTP code 407 from proxy after CONNECT\n' > "$_pp_d/log.b"
  printf ' ! [rejected]        refs/kit/base -> refs/kit/base (non-fast-forward)\n' > "$_pp_d/log.c"
  printf '   a407bcd..9f4071e  kit-base -> kit-base\n' > "$_pp_d/log.d"
  for _pp_l in a b; do
    ( . "$_pp_d/defs.sh"; _ku_proxy_refused "$_pp_d/log.$_pp_l" ) </dev/null || _pp_bad "leg 6: log.$_pp_l was not recognised as a proxy refusal"
  done
  for _pp_l in c d; do
    if ( . "$_pp_d/defs.sh"; _ku_proxy_refused "$_pp_d/log.$_pp_l" ) </dev/null; then _pp_bad "leg 6: log.$_pp_l was taken for a proxy refusal"; fi
  done

  rm -rf "$_pp_d" 2>/dev/null || true
  if [ "$_pp_fail" = 0 ]; then
    echo "$_pp_tag: OK (adv_push and ku_net forward only http.proxyAuthMethod + the helper scoped to the effective proxy origin; adv_git and _ku_git forward nothing; no proxy / a scope mismatch / a newline value forward nothing)"
    return 0
  fi
  return 1
}
_pp_bad() { echo "$_pp_tag: FAIL ($1)" >&2; _pp_fail=1; }
# _pp_run <ambient GIT_CONFIG_PARAMETERS> [VAR=val ...] — drive the four wrappers under that ambient config, a clean proxy env + the VARs.
_pp_run() {
  _ppr_amb=$1; shift
  rm -f "$_pp_d"/rec.*
  env -u https_proxy -u HTTPS_PROXY -u GIT_CONFIG_COUNT -u GIT_CONFIG_PARAMETERS HOME="$_pp_d" KU_D="$_pp_d" KU_REAL_GIT="$_pp_real" \
      GIT_CONFIG_PARAMETERS="$_ppr_amb" "$@" sh "$_pp_d/drv.sh" >/dev/null 2>&1 || _pp_bad "the driver failed to run"
}
# _pp_cmd <wrapper> — the command-scope lines the shim recorded for that wrapper.
_pp_cmd() { grep '^command' "$_pp_d/rec.$1" 2>/dev/null || :; }
_pp_called() { grep -qx called "$_pp_d/rec.$1" 2>/dev/null || _pp_bad "$2: $1 never reached git"; }
_pp_has() { _pp_cmd "$1" | grep -qxF -- "command${_pp_t}$3" || _pp_bad "$2: $1 did not forward $3"; }
_pp_count() { [ "$(_pp_cmd "$1" | wc -l | tr -d ' ')" = "$3" ] || _pp_bad "$2: $1 saw $(_pp_cmd "$1" | wc -l | tr -d ' ') command-scope entries, wanted $3"; }
_pp_net_ok() {
  for _ppn_w in adv_push ku_net; do
    _pp_called "$_ppn_w" "$1"; _pp_count "$_ppn_w" "$1" 2
    _pp_has "$_ppn_w" "$1" 'http.proxyauthmethod=basic'
    _pp_has "$_ppn_w" "$1" 'credential.http://localhost:61999.helper=!proxyhelper'
  done
}
# _pp_rawcount <wrapper> <label> <n> — the RAW GIT_CONFIG_COUNT the wrapper handed to git (not git's parsed view, which
# hides a half-built config that git rejects): a second assertion beside _pp_count.
_pp_rawcount() { grep -qx "count=$3" "$_pp_d/rec.$1" 2>/dev/null || _pp_bad "$2: $1 handed git GIT_CONFIG_COUNT other than $3 (raw: $(grep '^count=' "$_pp_d/rec.$1" 2>/dev/null))"; }
_pp_net_none() { for _ppn_w in adv_push ku_net; do _pp_called "$_ppn_w" "$1"; _pp_count "$_ppn_w" "$1" 0; _pp_rawcount "$_ppn_w" "$1" 0; done; }
_pp_net_nocred() {
  for _ppn_w in adv_push ku_net; do
    _pp_called "$_ppn_w" "$1"
    if _pp_cmd "$_ppn_w" | grep -q 'credential'; then _pp_bad "$1: $_ppn_w forwarded a credential helper"; fi
    if _pp_cmd "$_ppn_w" | grep -q 'evil'; then _pp_bad "$1: $_ppn_w forwarded a hostile entry"; fi
  done
}
_pp_local_none() { for _ppn_w in adv_git _ku_git; do _pp_called "$_ppn_w" "$1"; _pp_count "$_ppn_w" "$1" 0; _pp_rawcount "$_ppn_w" "$1" 0; done; }

case "${1:-}" in
  --sanitizer-selftest) _st=0; selftest_sanitizer_bash_unset || _st=1; selftest_proxy_passthrough || _st=1; exit "$_st" ;;
esac

# --merge-impl: which 3-way merge implementation to use. `auto` (the default) PROBES the capability and
# falls back — see merge3() below. The explicit values exist so the fallback can be exercised and compared
# ON A MODERN GIT (conformance/kit-update-merge.sh runs the same fixture through both and requires the
# same answer): a fallback nobody can run is a promise nobody can check. A FLAG, never an ambient env var —
# the environment does not get to decide how your merge is computed.
MERGE_MODE=auto
REPO=""; OUT=""; FROM=""; ADVANCE=""; AT=""; REMOTE=origin; NO_PUSH=""; REMOTE_SET=""; PUBLISH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --advance-base) ADVANCE=1; shift ;;
    --publish-base) PUBLISH=1; shift ;;
    --no-push) NO_PUSH=1; shift ;;
    --remote)
      [ $# -ge 2 ] && [ -n "$2" ] || { echo "kit-update: --remote requires a remote name" >&2; exit 2; }
      case "$2" in -*|*[!A-Za-z0-9._/-]*) echo "kit-update: --remote '$2' is not a plain remote name (letters, digits, . _ / - ; no leading '-')" >&2; exit 2 ;; esac
      REMOTE=$2; REMOTE_SET=1; shift 2 ;;
    --at) [ $# -ge 2 ] && [ -n "$2" ] || { echo "kit-update: --at requires a vendor commit sha" >&2; exit 2; }; AT=$2; shift 2 ;;
    --from) [ $# -ge 2 ] && [ -n "$2" ] || { echo "kit-update: --from requires a git url or a local path" >&2; exit 2; }; FROM=$2; shift 2 ;;
    --reconstruct-base) [ $# -ge 2 ] && [ -n "$2" ] || { echo "kit-update: --reconstruct-base requires a directory" >&2; exit 2; }; OUT=$2; shift 2 ;;
    --repo) [ $# -ge 2 ] && [ -n "$2" ] || { echo "kit-update: --repo requires a path" >&2; exit 2; }; REPO=$2; shift 2 ;;
    --merge-impl)
      [ $# -ge 2 ] && [ -n "$2" ] || { echo "kit-update: --merge-impl requires a value (auto|merge-tree|worktree)" >&2; exit 2; }
      case "$2" in
        auto|merge-tree|worktree) MERGE_MODE=$2 ;;
        *) echo "kit-update: --merge-impl must be one of: auto (probe, default) | merge-tree | worktree" >&2; exit 2 ;;
      esac
      shift 2 ;;
    -h|--help) echo "$USAGE"; exit 0 ;;
    *) echo "kit-update: unknown arg: $1" >&2; usage ;;
  esac
done
[ -n "$OUT" ] || [ -n "$FROM" ] || [ -n "$PUBLISH" ] || usage
if [ -n "$PUBLISH" ] && [ -n "$OUT$FROM$ADVANCE$AT$NO_PUSH" ]; then
  echo "kit-update: --publish-base is its own job (it pushes the base you already have; it takes only --repo and --remote) — pass it alone." >&2; exit 2
fi
[ -z "$OUT" ] || [ -z "$FROM" ] || { echo "kit-update: --from and --reconstruct-base are different jobs — pass one." >&2; exit 2; }
[ -z "$ADVANCE" ] || [ -n "$FROM" ] || { echo "kit-update: --advance-base needs --from <src> (the vendor history that contains the release HEAD took)." >&2; exit 2; }
[ -z "$ADVANCE" ] || [ -z "$OUT" ] || { echo "kit-update: --advance-base and --reconstruct-base are different jobs — pass one." >&2; exit 2; }
[ -z "$AT" ] || [ -n "$ADVANCE" ] || { echo "kit-update: --at belongs to --advance-base." >&2; exit 2; }
[ -z "$NO_PUSH" ] || [ -n "$ADVANCE" ] || { echo "kit-update: --no-push belongs to --advance-base (the job that publishes after it writes)." >&2; exit 2; }
[ -z "$REMOTE_SET" ] || [ -n "$ADVANCE$FROM$PUBLISH" ] || { echo "kit-update: --remote belongs to --from / --advance-base (the remote whose base they import) and --publish-base (where it pushes)." >&2; exit 2; }

# CP-11, for the one writer: an ambient git locator (GIT_DIR / GIT_WORK_TREE / ...) makes git read and write a repo
# OTHER than the one --repo names. --advance-base is refused at ENTRY, naming the variable, before any git runs.
if [ -n "$ADVANCE$PUBLISH" ]; then
  _ejob=--advance-base; [ -z "$PUBLISH" ] || _ejob=--publish-base
  for _eg in GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES; do
    eval "_egv=\${$_eg:-}"
    [ -z "$_egv" ] || die "$_ejob refuses with $_eg set in the environment: an ambient git locator would redirect the git that WRITES kit-base to a repo other than the one --repo names (CP-11). Unset it and re-run."
  done
fi

[ -n "$REPO" ] || REPO=$PWD
REPO=$( CDPATH='' cd "$REPO" 2>/dev/null && pwd -P ) || die "--repo: no such directory"
git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || die "'$REPO' is not a git repository. kit-update works on the adopter's OWN repo (the one incept ran in)."
REPO=$( CDPATH='' cd "$( git -C "$REPO" rev-parse --show-toplevel )" && pwd -P )

# ── the two hard preconditions, each refused BY NAME (a wrong base is worse than no base) ─────────────

# 1. THE BASE ITSELF. Absent = the adopter deleted the ref, or they incepted from a kit that predates the
#    kit-base mechanism. Either way there is NOTHING to reconstruct from and no honest fallback exists:
#    "the tree at version X" is not even unique (the public mirror ships UN-pruned; this adopter's export
#    was pruned to one profile). Say which, and what it means.
#    KIT-BASE-SHARED: for --from / --advance-base the refusal now comes AFTER the clone of --from and `sync_base`
#    (it cannot import — verified — without --from), so it is a function the run calls when the sync found nothing.
have_base() { git -C "$REPO" rev-parse --verify --quiet refs/heads/kit-base >/dev/null 2>&1; }
refuse_no_base() {
  echo "kit-update: no 'kit-base' branch in $REPO." >&2
  echo "  kit-base is the PRISTINE EXPORT this project was adopted from — the merge base every update" >&2
  echo "  needs. incept vendors it (branch 'kit-base', tag 'kit-base/v<VER>+<sha12>'). It is missing because" >&2
  echo "  either (a) it was deleted, or (b) this project was incepted from a kit that predates the" >&2
  echo "  mechanism. There is NO safe fallback: a guessed base yields a WRONG delta, which is worse" >&2
  echo "  than no delta. Recover the branch from YOUR OWN reflog (git reflog), or re-adopt." >&2
  if [ -n "$OUT" ]; then
    echo "  --from <vendor> imports a base a teammate published (verified): sh scripts/kit-update.sh --from <vendor>" >&2
  else
    echo "  whoever holds the base: kit-update --publish-base" >&2
  fi
  echo "  See docs/operations/kit-base.md." >&2
  exit 1
}
# A1 (security G1): a local kit-base that CAME FROM A REMOTE BRANCH (a `git checkout kit-base` of origin/kit-base, which sets
# branch.kit-base.remote/.merge; or a branch that equals a refs/remotes/*/kit-base) was never verified, and every `--from` /
# `--reconstruct-base` runs its own scripts/incept.sh. It is refused BEFORE anything is built or run, with the verified route.
refuse_unverified_base() {
  have_base || return 0
  _ub_why=''
  if git -C "$REPO" config --get branch.kit-base.remote >/dev/null 2>&1 || git -C "$REPO" config --get branch.kit-base.merge >/dev/null 2>&1; then
    _ub_why='it tracks a remote branch (branch.kit-base.remote/.merge is configured)'
  else
    _ub_tip=$(git -C "$REPO" rev-parse refs/heads/kit-base 2>/dev/null) || _ub_tip=''
    if [ -n "$_ub_tip" ] && git -C "$REPO" for-each-ref --format='%(objectname) %(refname)' refs/remotes/ | grep -F -e "$_ub_tip refs/remotes/" | grep -q -e '/kit-base$'; then
      _ub_why='it equals a remote-tracking branch kit-base'
    fi
  fi
  [ -n "$_ub_why" ] || return 0
  echo "kit-update: kit-base REFUSED as UNVERIFIED — it was created from a remote branch ($_ub_why). Nothing was built or run." >&2
  echo "  A kit-base that arrived by a plain git branch was never checked, and every kit-update runs its own scripts/incept.sh." >&2
  echo "  The verified route (a human step): set it aside with 'git branch -m kit-base kit-base-unverified', then re-run kit-update --from <vendor>," >&2
  echo "  which imports the published refs/kit/base through the verification (docs/operations/kit-base.md)." >&2
  exit 1
}
# --reconstruct-base has no --from, so it cannot verify and does not sync: it refuses here, as it always did.
[ -z "$OUT" ] || [ -n "$PUBLISH" ] || have_base || refuse_no_base
[ -n "$PUBLISH" ] || refuse_unverified_base

# 2. THE STAMPS. CLAUDE.md §3 is where incept recorded every inception input. (--publish-base pushes the base it
#    already has and reconstructs nothing, so it needs none of them.)
if [ -z "$PUBLISH" ]; then
CM="$REPO/CLAUDE.md"
[ -f "$CM" ] || { have_base || refuse_no_base; die "no CLAUDE.md in $REPO — the project's inception stamps (§3) live there; without them the base cannot be reconstructed."; }

# A §3 config-list stamp: "- **<Field>** (§x): <value> — <template annotation…>". incept replaced ONLY the
# bracketed choice-list, so the trailing prose survives — take the FIRST token, never the whole line.
stamp_list() {  # <sed-escaped field prefix>
  sed -n "s/^- \*\*$1\*\*[^:]*: *//p" "$CM" | sed -n '1p' | cut -d' ' -f1
}
# A header stamp: "**<Field>:** <value>" — the value IS the rest of the line (a project name has spaces).
stamp_head() {  # <field>
  sed -n "s/^\*\*$1:\*\* *//p" "$CM" | sed -n '1p' | sed 's/[[:space:]]*$//'
}
# Unfilled template slots still carry their bracketed placeholder — that is NOT a value.
filled() { case "${1:-}" in ''|\[*) return 1 ;; *) return 0 ;; esac; }

NAME=$(stamp_head 'Project')
OWNER=$(stamp_head 'Intent owner')
DATE=$(stamp_head 'Created')
STACK=$(stamp_list 'Stack profile')
BACKLOG=$(stamp_list 'Backlog backend')
MODE=$(stamp_list 'Process mode')
TEAM=$(stamp_list 'Governance')
HARNESS=$(stamp_list 'Target harness(es)')
FLUENCY=$(stamp_list 'Operator fluency')   # OPTIONAL — incept leaves it unstamped when undeclared.
# T3b: the last two inception inputs, now RECORDED. Not in the mandatory `miss` list below: a tree incepted
# BEFORE these slots existed carries no stamp, and refusing it would break every existing adopter. They get
# the announced legacy fallback instead (see below) — absent, never silently defaulted.
CIP=$(stamp_list 'CI platform')
DBA=$(stamp_list 'DB archetype')

miss=''
filled "$NAME"    || miss="$miss\n  - **Project:** — incept requires --name; without it the reconstruction cannot be stamped."
filled "$OWNER"   || miss="$miss\n  - **Intent owner:** — incept requires --intent-owner."
filled "$DATE"    || miss="$miss\n  - **Created:** — the ADOPTION DATE. It must NOT fall back to today: the reconstruction runs\n      TODAY while your tree carries your adoption date, so an unpinned stamp fabricates a conflict in\n      CLAUDE.md + ADR-000-stack.md — files nobody touched."
filled "$STACK"   || miss="$miss\n  - **Stack profile** (§2) — the profile drives the emitted CI, the scaffold, and the export prune."
filled "$BACKLOG" || miss="$miss\n  - **Backlog backend** (§6) — it decides which tracker doc incept wrote."
filled "$MODE"    || miss="$miss\n  - **Process mode** (§ ceremony) — lean vs enterprise scaffolds different governance docs."
filled "$TEAM"    || miss="$miss\n  - **Governance** (§ solo/team)."
filled "$HARNESS" || miss="$miss\n  - **Target harness(es)** (§harness-neutrality)."
if [ -n "$miss" ]; then
  echo "kit-update: CLAUDE.md is missing inception stamps needed to reconstruct the base:" >&2
  # shellcheck disable=SC2059  # $miss is our own assembled message, not user input
  printf "$miss\n" >&2
  echo "  REFUSING to guess. A wrong base silently produces a wrong delta — worse than no delta, because" >&2
  echo "  you would trust it. Restore the stamps in CLAUDE.md §3 (they are what incept wrote) and re-run." >&2
  exit 1
fi

# ── THE CI PLATFORM + THE DB ARCHETYPE: read the FACT; infer only as an announced LEGACY fallback ──────
# These are the last two inception inputs incept learned to stamp (T3b). Where the stamp is present it is
# the SOURCE OF TRUTH and nothing is derived: a stamp is what the operator actually chose, evidence is only
# what the tree looks like today — and the tree can be edited.
#
# The fallback below exists for exactly one population: adopters incepted BEFORE the stamps existed. For
# them there IS no record, so evidence is all there is. It is INFERENCE and it is ANNOUNCED as inference —
# never presented as a fact, never silent. (And it can be wrong: see the CI note.) When it cannot decide,
# it REFUSES; it never defaults.
INFERRED=''

if filled "$CIP"; then
  case "$CIP" in
    github|gitlab) CI=$CIP ;;
    *) die "CLAUDE.md §3 stamps an unknown **CI platform**: '$CIP' (incept wires one of: github, gitlab). Refusing to guess which pipeline this project was incepted with." ;;
  esac
else
  # LEGACY INFERENCE — pre-stamp tree. incept writes .github/workflows/ci.yml under --ci github and
  # .gitlab-ci.yml under --ci gitlab. But the EXPORT ships .github/workflows/ EMPTY (ci.yml is export-ignored,
  # P0-FU) — so a github-workflow FILE is not positive evidence either way, and .gitlab-ci.yml
  # (which ONLY incept --ci gitlab creates) must be tested FIRST. This is precisely why the stamp exists.
  if git -C "$REPO" cat-file -e "HEAD:.gitlab-ci.yml" 2>/dev/null; then
    CI=gitlab
  elif git -C "$REPO" cat-file -e "HEAD:.github/workflows/ci.yml" 2>/dev/null; then
    CI=github
  else
    echo "kit-update: cannot determine the CI platform this project was incepted with." >&2
    echo "  CLAUDE.md §3 has no **CI platform** stamp (this project predates it), and neither" >&2
    echo "  .gitlab-ci.yml nor .github/workflows/ci.yml is in HEAD — so there is neither a record nor" >&2
    echo "  evidence. Guessing would wire the wrong pipeline into the base and every CI file would read" >&2
    echo "  as a conflict. Add '- **CI platform** (§14): github' (or gitlab) to CLAUDE.md §3 and re-run." >&2
    exit 1
  fi
  if [ "$CI" = gitlab ]; then _why='.gitlab-ci.yml is in HEAD (only --ci gitlab creates it)'
  else _why='no .gitlab-ci.yml, and a GitHub workflow is in HEAD'; fi
  INFERRED="${INFERRED}    ci=$CI  <- INFERRED ($_why), NOT recorded
"
fi

if filled "$DBA"; then
  case "$DBA" in
    db-backed) DB_FLAG='' ;;
    no-db)     DB_FLAG='--no-db' ;;
    *) die "CLAUDE.md §3 stamps an unknown **DB archetype**: '$DBA' (incept records one of: db-backed, no-db). Refusing to guess." ;;
  esac
else
  # LEGACY INFERENCE — pre-stamp tree. incept --no-db REMOVES the scaffold's .db-backed marker. So: the
  # profile SHIPPED a marker (evidence: it is in kit-base) but the adopter's HEAD has none => they ran
  # --no-db. HONEST LIMIT: it cannot distinguish "--no-db at inception" from "the adopter deleted the
  # marker later", and for a profile that never shipped a marker it can see --no-db at all. Inference.
  DB_FLAG=''
  if git -C "$REPO" cat-file -e "kit-base:profiles/${STACK}/scaffold/.db-backed" 2>/dev/null \
     && ! git -C "$REPO" cat-file -e "HEAD:.db-backed" 2>/dev/null; then
    DB_FLAG='--no-db'
  fi
  if [ -n "$DB_FLAG" ]; then _dbw=no-db; else _dbw=db-backed; fi
  INFERRED="${INFERRED}    db=$_dbw  <- INFERRED from the .db-backed marker, NOT recorded
"
fi

if [ -n "$INFERRED" ]; then
  echo "kit-update: NOTE — this project was incepted before CLAUDE.md §3 stamped every inception input." >&2
  echo "  The values below were INFERRED from evidence in the tree. They are not facts, they are the best" >&2
  echo "  reading of what the tree looks like TODAY — and the tree can have been edited since inception:" >&2
  printf '%s' "$INFERRED" >&2
  echo "  If either is wrong, the base is wrong, and kit files nobody touched will read as CONFLICTS." >&2
  echo "  Record them once and this note goes away — add them to CLAUDE.md §3 (they are what incept now" >&2
  echo "  writes): '- **CI platform** (§14): <github|gitlab>' and '- **DB archetype** (§ archetype): <db-backed|no-db>'." >&2
fi
fi   # (end of: no stamps for --publish-base)

stamps_line() {
  echo "    name='$NAME' owner='$OWNER' stack=$STACK team=$TEAM backlog=$BACKLOG ci=$CI mode=$MODE harness=$HARNESS date=$DATE${DB_FLAG:+ $DB_FLAG}"
}

# run_incept <dir> <whose-incept-is-this> — re-run the incept THAT DIR SHIPS, with the recorded stamps.
# BOTH sides go through this ONE function: that is what makes the transformation cancel. The date is
# PINNED (the flag exists for exactly this call). An empty stamp is passed through empty and incept exits
# 2 — a loud refusal, not a silent "today". We do not work around that.
#
# $MODE is READ AND PASSED THROUGH, never branched on: kit-update does not know or care what the process
# mode means — it reproduces the inception the adopter actually performed. (conformance/mode-enforcement-
# blind.sh asserts no script conditions on it.)
run_incept() {  # <dir> <label>
  _d=$1; _lbl=$2
  set -- --noninteractive --name "$NAME" --intent-owner "$OWNER" --stack "$STACK" \
         --team "$TEAM" --backlog "$BACKLOG" --ci "$CI" --harness "$HARNESS" --mode "$MODE" \
         --date "$DATE"
  [ -n "$DB_FLAG" ] && set -- "$@" "$DB_FLAG"
  filled "$FLUENCY" && set -- "$@" --operator-fluency "$(printf '%s' "$FLUENCY" | tr '[:upper:]' '[:lower:]')"
  _log=$(mktemp) || die "mktemp failed"
  if ! ( cd "$_d" && sh scripts/incept.sh "$@" ) >"$_log" 2>&1; then
    echo "kit-update: re-running ${_lbl}'s own incept FAILED:" >&2
    sed 's/^/    /' "$_log" >&2 || :
    rm -f "$_log"
    die "$_lbl could not be built. Without all three sides there is no merge — no delta will be computed."
  fi
  rm -f "$_log"
}

# build_base <dir> — MATERIALIZE kit-base and RE-RUN ITS OWN incept.
# `git archive` (read-only) — never `git worktree add`/`checkout`, which would write refs and admin files
# into the adopter's repo.
#
# build_base <dir> [<chain-commit>] — with no commit it is the kit-base TIP; with one it is that OLDER chain
# commit (the pristine-chain walk builds those lazily). Either way: that commit's OWN incept, same stamps.
build_base() {
  git -C "$REPO" archive "${2:-refs/heads/kit-base}" | tar -x -C "$1" \
    || die "could not materialize the kit-base tree into '$1'"
  _bb_lbl='kit-base'
  [ -z "${2:-}" ] || _bb_lbl="kit-base chain commit $(short12 "$2")"
  # KIT-BASE-MANIFEST-CONCORDANCE: a base recorded from ANOTHER stack's incept cannot be replayed with this project's
  # stamped stack, and used to fail inside its own incept with an opaque `unknown --stack`. Name it before that runs.
  # (No .kit-manifest = a legacy base: nothing to read, the old behaviour stands.)
  if [ -f "$1/.kit-manifest" ]; then
    _bb_have=$(sed -n 's#^profiles/\([^/]*\)/.*#\1#p' "$1/.kit-manifest" | LC_ALL=C sort -u)
    if ! printf '%s\n' "$_bb_have" | grep -qxF -- "$STACK"; then
      die "FOREIGN BASE: the ${_bb_lbl} carries the profile(s) $(printf '%s' "$_bb_have" | tr '\n' ' ')but this project is stamped '$STACK'. It was recorded from a different stack's incept (for example a trial run in this directory first), so it is not the tree this project was adopted from and no update can be computed from it. Rename it aside ('git branch -m kit-base kit-base-foreign'), then import a verified published base with 'kit-update --from <vendor>' if your team has one, or re-adopt the project from a fresh export."
    fi
  fi
  run_incept "$1" "$_bb_lbl"
}

n() { grep -c . < "$1" || :; }   # n <file> -> its line count

# ── THE EFFECTIVE BASE (KIT-UPDATE-PARTIAL-ADOPTION) ──────────────────────────────────────────────────────
# A kit-base commit's TREE is the raw export of the release it records. When HEAD took only PART of that
# release, the commit's message also carries `behind <chain commit> <path>` lines — one per path HEAD did NOT
# take — and a `Kit-Behind: <N>` trailer. The base is a merge base: per path, the last kit content this tree
# absorbed. So the EFFECTIVE base of a tip is incept(tip), with every behind path taken from the incept of the
# chain commit it names (or absent, when that tree lacks it).

# read_behind <chain commit> <outfile> — the commit's behind block as `<chain commit> TAB <path>` lines (sorted by
# path) in <outfile>. STRICT: this is read out of history, and a forged block must only ever make files RE-OFFER
# (toward CONFLICT, never a clobber) — so anything malformed refuses the run as a corrupt base. Each line is
# `behind <40 lowercase hex> <path>`; the named commit is an ANCESTOR of this one on the first-parent chain; the
# path has no control character, is relative, has no `.`/`..`/`.git` component, and appears once; and the
# `Kit-Behind` trailer, when present, equals the number of lines (absent == 0 lines, a pre-change commit).
behind_line_ok() {  # <whole line> <after 'behind '> <sha> <path> (reads $TMP/rb.chain: the commit's older chain)
  [ "$2" != "$1" ] && [ "$4" != "$2" ] && [ -n "$4" ] || return 1
  [ "${#3}" = 40 ] || return 1
  ! printf '%s' "$3" | grep -q '[^0-9a-f]' || return 1
  [ "$_KU_BEHIND_STRICT" = on ] && { grep -qxF -- "$3" "$TMP/rb.chain" || return 1; }
  ! printf '%s' "$4" | grep -q '[[:cntrl:]]' || return 1
  case "/$4/" in //*|*//*|*/./*|*/../*|*/.git/*) return 1 ;; esac
  return 0
}
read_behind() {
  _rb_c=$1; _rb_o=$2; : > "$_rb_o"
  git -C "$REPO" rev-list --first-parent "$_rb_c" | sed 1d > "$TMP/rb.chain"
  git -C "$REPO" log -1 --format=%B "$_rb_c" | grep '^behind' > "$TMP/rb.lines" || :
  _rb_tab=$(printf '\t')
  while IFS= read -r _rb_line; do
    _rb_rest=${_rb_line#behind }; _rb_sha=${_rb_rest%% *}; _rb_path=${_rb_rest#* }
    behind_line_ok "$_rb_line" "$_rb_rest" "$_rb_sha" "$_rb_path" \
      || die "the kit-base chain commit $(short12 "$_rb_c") carries a corrupt 'behind' record ('$(printf '%s' "$_rb_line" | tr -d '\000-\037\177' | cut -c1-100)'): each line must be 'behind <40-hex chain commit> <relative path>' naming an OLDER commit of this chain. REFUSING a forged or damaged record — a base built from it is a wrong base. Inspect 'git log -1 $_rb_c', or undo to the previous tip."
    printf '%s\t%s\n' "$_rb_sha" "$_rb_path" >> "$_rb_o"
  done < "$TMP/rb.lines"
  LC_ALL=C sort -t "$_rb_tab" -k2,2 "$_rb_o" -o "$_rb_o"
  [ "$(cut -f2 "$_rb_o" | LC_ALL=C sort -u | grep -c . || :)" = "$(n "$_rb_o")" ] \
    || die "the kit-base chain commit $(short12 "$_rb_c") names one path twice in its 'behind' record — corrupt. REFUSING."
  _rb_cnt=$(git -C "$REPO" log -1 --format='%(trailers:key=Kit-Behind,valueonly)' "$_rb_c" | sed -n '1p' | tr -d '[:space:]')
  [ -n "$_rb_cnt" ] || _rb_cnt=$(n "$_rb_o")
  case "$_rb_cnt" in *[!0-9]*) _rb_cnt=bad ;; esac
  [ "$_rb_cnt" = "$(n "$_rb_o")" ] \
    || die "the kit-base chain commit $(short12 "$_rb_c") has a 'Kit-Behind' trailer that disagrees with its 'behind' lines — corrupt. REFUSING."
}

# chain_dir <chain commit> — CD = that commit's incepted tree as a DIRECTORY, built ONCE per run (an incept is ~9 s
# and both the effective base and the pristine-chain walk want the same ones).
chain_dir() {
  CD="$TMP/cd.$1"
  [ ! -d "$CD" ] || return 0
  mkdir -p "$CD"
  build_base "$CD" "$1"
}

# safe_parents <root> <relative path> <what> <chain commit> — refuse (corrupt base, rc 1) when any PARENT directory of
# <path> under <root> is a symlink, or the deepest parent's physical path is not under this run's $TMP: a forged chain
# commit must not turn "take this one file" into a write or a read outside the throwaway tree. Runs BEFORE any rm/extract.
safe_parents() {
  _sp_acc=$1; _sp_rest=$(dirname "$2")
  while [ -n "$_sp_rest" ] && [ "$_sp_rest" != . ]; do
    _sp_c=${_sp_rest%%/*}
    [ ! -L "$_sp_acc/$_sp_c" ] \
      || die "the kit-base record is corrupt: '$2' has a symlinked parent directory ('$_sp_c') in $3 — REFUSING (chain commit $(short12 "$4")). Nothing was written."
    _sp_acc="$_sp_acc/$_sp_c"
    case "$_sp_rest" in */*) _sp_rest=${_sp_rest#*/} ;; *) _sp_rest=. ;; esac
  done
  [ -d "$_sp_acc" ] || return 0
  _sp_phys=$( CDPATH='' cd "$_sp_acc" 2>/dev/null && pwd -P ) || return 0
  _sp_tmp=$( CDPATH='' cd "$TMP" && pwd -P )
  case "$_sp_phys/" in
    "$_sp_tmp"/*) return 0 ;;
    *) die "the kit-base record is corrupt: the parent of '$2' in $3 resolves to '$_sp_phys', outside this run's temp tree — REFUSING (chain commit $(short12 "$4")). Nothing was written." ;;
  esac
}

# build_effective_base <dir> — BASE for the kit-base TIP (see above). Sets BEHIND_N; the tip's behind block is
# left in $TMP/behind.tsv (`<chain commit> TAB <path>`).
build_effective_base() {
  # the record is validated FIRST (cheap), so a corrupt one refuses before any incept is paid for
  read_behind "$(git -C "$REPO" rev-parse refs/heads/kit-base)" "$TMP/behind.tsv"
  build_base "$1"
  BEHIND_N=$(n "$TMP/behind.tsv")
  _eb_tab=$(printf '\t')
  : > "$TMP/behind.tipblob"
  while IFS="$_eb_tab" read -r _eb_c _eb_p; do
    [ -n "$_eb_p" ] || continue
    chain_dir "$_eb_c"
    safe_parents "$1" "$_eb_p" "the effective base" "$_eb_c"
    safe_parents "$CD" "$_eb_p" "the incept of chain commit $(short12 "$_eb_c")" "$_eb_c"
    # what the TIP's own incept has at this path (R-2: a behind path HEAD already equals is worth a note)
    _eb_tb=ABSENT
    if [ -L "$1/$_eb_p" ]; then _eb_tb=-; elif [ -f "$1/$_eb_p" ]; then _eb_tb=$(git hash-object -- "$1/$_eb_p"); fi
    printf '%s\t%s\n' "$_eb_p" "$_eb_tb" >> "$TMP/behind.tipblob"
    rm -rf -- "${1:?}/$_eb_p"
    if [ -e "$CD/$_eb_p" ] || [ -L "$CD/$_eb_p" ]; then
      mkdir -p "$(dirname "$1/$_eb_p")"
      ( cd "$CD" && tar -cf - -- "./$_eb_p" ) | ( cd "$1" && tar -xf - ) \
        || die "could not take '$_eb_p' from the incept of chain commit $(short12 "$_eb_c") into the effective base."
    fi
  done < "$TMP/behind.tsv"
}

# adopter_manifest — the FILE SET the adopter ACTUALLY received, as the exporter recorded it at export
# time. This is the AUTHORITY on THEIRS's shape, and it is why we do not GUESS. `adopter-export --profile`
# is OPTIONAL: a single-stack adopter prunes to one profile, but a multi-stack org (the kit's stated
# consumer) legitimately keeps ALL ten. The manifest is vendored inside kit-base (P1.2-pre-a), so the fact
# is recorded — read it. Falls back to the working-tree .kit-manifest only if kit-base carries none (an
# older base); REFUSES if neither exists, because a guessed shape produces spurious DELETIONS of files the
# adopter never touched — data loss with a progress bar, the exact failure this tool exists to prevent.
adopter_manifest() {
  if git -C "$REPO" show kit-base:.kit-manifest 2>/dev/null; then return 0; fi
  if [ -f "$REPO/.kit-manifest" ]; then cat "$REPO/.kit-manifest"; return 0; fi
  return 1
}

# ── the kit-base CHAIN — helpers shared by --advance-base and the --from stale/pristine/grouping logic ───
short12() { printf '%s' "$1" | cut -c1-12; }

# parse_kit_source <file> — STRICT read of a `.kit-source`, the same rules incept's read_kit_source applies:
# exactly two lines, `commit <40 lowercase hex>` then `version <non-empty, no whitespace>`. Sets KS_SHA/KS_VER.
# Anything else is refused: this file is ADOPTER-CONTROLLED input, and a guessed sha is a wrong base.
KS_SHA=''; KS_VER=''
parse_kit_source() {
  KS_SHA=''; KS_VER=''
  _ks_n=$(wc -l < "$1" | tr -d ' ')
  _ks_l1=$(sed -n 1p "$1"); _ks_l2=$(sed -n 2p "$1")
  _ks_s=${_ks_l1#commit }; _ks_v=${_ks_l2#version }
  [ "$_ks_n" = 2 ] && [ "$_ks_l1" != "$_ks_s" ] && [ "$_ks_l2" != "$_ks_v" ] \
    && [ "${#_ks_s}" = 40 ] && [ -n "$_ks_v" ] \
    && ! printf '%s' "$_ks_s" | grep -q '[^0-9a-f]' && ! printf '%s' "$_ks_v" | grep -q '[[:space:]]' \
    || return 1
  KS_SHA=$_ks_s; KS_VER=$_ks_v
}

# head_kit_source — read HEAD:.kit-source into KS_SHA/KS_VER. rc 0 = well-formed · 1 = ABSENT (a legacy tree,
# updated before the chain existed) · 2 = present but MALFORMED.
head_kit_source() {
  KS_SHA=''; KS_VER=''
  git -C "$REPO" cat-file -e 'HEAD:.kit-source' 2>/dev/null || return 1
  _hk=$(mktemp) || die "mktemp failed"
  git -C "$REPO" show 'HEAD:.kit-source' > "$_hk" 2>/dev/null || :
  if parse_kit_source "$_hk"; then rm -f "$_hk"; return 0; fi
  rm -f "$_hk"; return 2
}

# commit_source <commit> — the Kit-Source trailer of a kit-base chain commit (40 lowercase hex), or nothing
# (a legacy base commit, or a malformed value: both mean "no recorded vendor commit").
commit_source() {
  _cs=$(git -C "$REPO" log -1 --format='%(trailers:key=Kit-Source,valueonly)' "$1" 2>/dev/null \
    | sed -n '1p' | tr -d '[:space:]')
  case "$_cs" in *[!0-9a-f]*|'') return 0 ;; esac
  [ "${#_cs}" = 40 ] && printf '%s\n' "$_cs"
  return 0
}

# chain_commit_for <40-hex vendor sha> — the kit-base chain commit that records it (tip -> root), or rc 1.
chain_commit_for() {
  for _cc in $(git -C "$REPO" rev-list --first-parent refs/heads/kit-base); do
    if [ "$(commit_source "$_cc")" = "$1" ]; then echo "$_cc"; return 0; fi
  done
  return 1
}

# export_at_shape <src-clone> <dest> <whose> — run <src>'s OWN adopter-export into <dest>, at the SHAPE this
# adopter actually received. THEIRS (--from) and a chain commit (--advance-base) are the same act, so they
# share this one function (never two copies of the shape rule). Sets MANIFEST and THEIRS_SHAPE.
export_at_shape() {
  MANIFEST=$(adopter_manifest) || MANIFEST=''
  [ -n "$MANIFEST" ] || die "cannot read this project's .kit-manifest (neither 'kit-base:.kit-manifest' nor a working-tree .kit-manifest). It is the RECORD of which files — and which profiles — this project received, and thus the authority on the shape THEIRS must be pruned to. Without it the shape can only be GUESSED, and a wrong shape emits deletions of files nobody touched. Recover kit-base (it vendors the manifest) or restore .kit-manifest."
  # The prunable unit is a profile DIRECTORY (profiles/<name>/...). incept does not rename profiles/, so a
  # manifest path is the adopter's actual profile path. If the manifest lists ANY profile DIR beyond the
  # adopter's own stack, they kept it (an un-pruned / multi-stack adopter) -> export THEIRS with NO --profile
  # so it carries every profile they kept. Otherwise they pruned to one profile -> reproduce that exactly.
  # (profiles/*.md docs and non-profile _TEMPLATE paths are NOT dirs, so they never confuse this.)
  KEPT_OTHER=$(printf '%s\n' "$MANIFEST" | sed -n 's#^profiles/\([^/]*\)/.*#\1#p' \
    | LC_ALL=C sort -u | grep -vxF "$STACK" | grep -c . || :)
  if [ "${KEPT_OTHER:-0}" -gt 0 ]; then
    THEIRS_SHAPE="un-pruned (adopter-export, no --profile) — .kit-manifest records $KEPT_OTHER profile dir(s) beyond '$STACK', so this adopter kept them"
    sh "$1/scripts/adopter-export.sh" "$2" >"$TMP/exp.log" 2>&1 \
      || { sed 's/^/    /' "$TMP/exp.log" >&2 || :; die "$3's own adopter-export.sh failed (un-pruned, matching this adopter's manifest shape)."; }
  else
    THEIRS_SHAPE="pruned to '$STACK' (adopter-export --profile $STACK) — .kit-manifest records only that profile"
    sh "$1/scripts/adopter-export.sh" "$2" --profile "$STACK" >"$TMP/exp.log" 2>&1 \
      || { sed 's/^/    /' "$TMP/exp.log" >&2 || :; die "$3's own adopter-export.sh failed (stack '$STACK'). If that release dropped this profile, there is no honest THEIRS to build."; }
  fi
}

# warn_untrusted <headline> <what-we-run> — THE WARNING BEFORE THE ACT. The source is untrusted input and we
# are about to EXECUTE code from it: printed BEFORE the clone, naming the source, while they can still stop.
warn_untrusted() {
  echo "kit-update: $1"
  echo "  ! THIS EXECUTES CODE FROM THAT SOURCE. $2 — that is the whole design (re-running the real"
  echo "    scripts is what makes incept's transformation cancel), and it is also what adoption always was:"
  echo "    running a kit's incept.sh. But point this ONLY at a source you trust as much as your own repo."
  echo "    It also runs the incept.sh stored in YOUR kit-base chain commits (trusted as code: they are your"
  echo "    own history). Anyone with push access to the remote can write refs/kit/base, so kit-update verifies every"
  echo "    imported chain commit against this source before writing it; a base hand-fetched with raw git is NOT verified."
  echo ""
}

# adv_git <git args> — git for the ONE writer, with a SCRUBBED environment and an EXPLICIT locator triad
# (the adopter's git dir, a TEMP index, the export dir as work tree). Why not `git -C "$REPO" add`: that
# would stage into the adopter's REAL index. Identity is passed with -c by the caller (the KIT's, never the
# adopter's). `env -u` for the reason the _ku_git note below spells out.
adv_git() {
  ( GIT_CONFIG_COUNT=0; GIT_CONFIG_PARAMETERS=''
    export GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
    env -u GIT_COMMON_DIR -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_SYSTEM -u GIT_CONFIG_NOSYSTEM -u GIT_CONFIG \
        -u GIT_CEILING_DIRECTORIES -u GIT_OBJECT_DIRECTORY -u GIT_ALTERNATE_OBJECT_DIRECTORIES -u GIT_NAMESPACE \
        -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL -u GIT_AUTHOR_DATE \
        -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL -u GIT_COMMITTER_DATE \
        GIT_DIR="$ADV_GD" GIT_INDEX_FILE="$ADV_IDX" GIT_WORK_TREE="$ADV_WT" git "$@" )
}

# advance_sha — which vendor commit HEAD took. Sets ADV_SHA and ADV_HOW. THE FACT is HEAD:.kit-source; --at is
# accepted ONLY for a legacy tree that has none, and is announced as ASSERTED.
advance_sha() {
  _as_rc=0; head_kit_source || _as_rc=$?
  case "$_as_rc" in
    0)
      [ -z "$AT" ] || die "--at is only accepted when HEAD has no .kit-source (a legacy tree). HEAD RECORDS vendor commit $(short12 "$KS_SHA") — that fact is what --advance-base uses; an asserted sha beside it would only invite a wrong base."
      ADV_SHA=$KS_SHA; ADV_HOW="RECORDED in HEAD:.kit-source (version $KS_VER)" ;;
    2)
      die "HEAD:.kit-source is malformed (it must be exactly two lines: 'commit <40 lowercase hex>' and 'version <VER>'). REFUSING to guess which release this tree took — restore the file from the update that wrote it." ;;
    *)
      [ -n "$AT" ] || die "HEAD has no .kit-source (this tree took its updates before the kit-base chain existed), so the release it took is not recorded. Name it: --at <sha> (the vendor commit HEAD's kit files were taken from; it is ASSERTED, not recorded — if it is wrong the base is wrong). Advance once per release you took, oldest first."
      case "$AT" in
        *[!0-9a-f]*) die "--at '$AT' is malformed: a vendor commit sha is 7-40 lowercase hex characters." ;;
      esac
      [ "${#AT}" -ge 7 ] && [ "${#AT}" -le 40 ] || die "--at '$AT' is malformed: a vendor commit sha is 7-40 lowercase hex characters."
      ADV_SHA=$AT; ADV_HOW="ASSERTED by --at — NOT recorded in your tree; if it is wrong the base is wrong" ;;
  esac
}

# advance_shared_line — "merge the update, pull, THEN advance". When the remote exists, HEAD must already be on
# the shared line (reachable from refs/remotes/<remote>/HEAD): the base must not record a release that only
# exists on an unmerged branch of ONE clone. --no-push (a solo or offline clone) skips it; so does a repo with
# no such remote (there is no shared line to be on; the publish step says so).
advance_shared_line() {
  [ -z "$NO_PUSH" ] || return 0
  git -C "$REPO" config --get "remote.$REMOTE.url" >/dev/null 2>&1 || return 0
  _sl=$(git -C "$REPO" rev-parse --verify --quiet "refs/remotes/$REMOTE/HEAD^{commit}") \
    || die "refs/remotes/$REMOTE/HEAD is not set, so there is no shared line to check HEAD against. Run 'git remote set-head $REMOTE -a' (after a fetch) and re-run — or pass --no-push to keep the base local. (Nothing was written.)"
  git -C "$REPO" merge-base --is-ancestor HEAD "$_sl" 2>/dev/null \
    || die "HEAD is not reachable from refs/remotes/$REMOTE/HEAD: the update is not merged-and-pulled yet. Merge the update's PR, pull, THEN advance — kit-base must not record a release only your branch has. Check out the default branch and pull, then re-run. (Pass --no-push to record it locally anyway. Nothing was written.)"
}

# advance_in_chain_check — the release HEAD took may already be in the chain. Only the TIP's release, left
# PARTIAL (Kit-Behind > 0), may be advanced again: that is how it is finished. Sets READV (1 = re-advance) and
# leaves the tip's behind block in $TMP/behind.tsv.
advance_in_chain_check() {
  READV=0
  _ex=$(chain_commit_for "$FULL") || return 0
  [ "$_ex" = "$OLD" ] \
    || die "vendor commit $(short12 "$FULL") is already in the kit-base chain (chain commit $(short12 "$_ex")) but is not the tip — only the tip's release can be advanced again. Nothing to advance."
  read_behind "$OLD" "$TMP/behind.tsv"
  [ "$(n "$TMP/behind.tsv")" -gt 0 ] \
    || die "vendor commit $(short12 "$FULL") is already in the kit-base chain (chain commit $(short12 "$_ex")), recorded COMPLETE (Kit-Behind: 0) — nothing to advance."
  READV=1
}

# advance_prepare — everything BEFORE the first write: which commit, the clone, every refusal, the export, the
# per-path provenance. Writes nothing to the adopter's repo. Sets OLD (the tip), FULL (40-hex), EXP_VER, TAG,
# READV, BEHIND_NEW (the count) and $TMP/behind.new.tsv.
advance_prepare() {
  OLD=$(git -C "$REPO" rev-parse --verify --quiet 'refs/heads/kit-base^{commit}') \
    || die "refs/heads/kit-base does not resolve to a commit."
  advance_shared_line
  advance_sha
  # (the warning and the clone of --from now happen ONCE, at the entry below, before `sync_base`: verifying an imported base
  # needs the clone, and the advance reuses it.)
  FULL=$(git -C "$TMP/new" rev-parse --verify --quiet "${ADV_SHA}^{commit}" 2>/dev/null) \
    || die "vendor commit $ADV_SHA is unreachable in --from '$FROM' (not in its history, or an ambiguous short sha). REFUSING: a base built from some other commit is a wrong base."
  # reachable means IN --from's HEAD history: a local-path clone also copies dangling objects, which are not history
  git -C "$TMP/new" merge-base --is-ancestor "$FULL" HEAD 2>/dev/null \
    || die "vendor commit $(short12 "$FULL") is unreachable from --from's HEAD ('$FROM'): the object exists but is not in its history (a dangling object, or another branch). REFUSING: a base built from some other commit is a wrong base."
  advance_in_chain_check
  # ORDER: the chain is oldest-first. When the tip's recorded vendor commit is in the clone, the new one must descend from it.
  if [ "$READV" -eq 0 ] && [ -n "$TIP_SRC" ] && git -C "$TMP/new" cat-file -e "$TIP_SRC^{commit}" 2>/dev/null \
     && ! git -C "$TMP/new" merge-base --is-ancestor "$TIP_SRC" "$FULL" 2>/dev/null; then
    die "out of order — vendor commit $(short12 "$FULL") does not descend from the kit-base tip's recorded commit $(short12 "$TIP_SRC"). Record the releases you took OLDEST FIRST (a backwards .kit-source or --at would invert the chain)."
  fi
  [ -f "$TMP/new/scripts/adopter-export.sh" ] || die "'$FROM' has no scripts/adopter-export.sh — it is not a Sparkwright kit."
  git -C "$TMP/new" checkout -q --detach "$FULL" >/dev/null 2>&1 || die "could not check out $(short12 "$FULL") in the temp clone."
  [ -f "$TMP/new/scripts/adopter-export.sh" ] || die "commit $(short12 "$FULL") has no scripts/adopter-export.sh — it is not a kit release this tool can record."
  export_at_shape "$TMP/new" "$TMP/exp" "that commit"
  [ "$(find "$TMP/exp" -type f | grep -c . || :)" -gt 0 ] || die "the export of $(short12 "$FULL") came out EMPTY. Refusing to record an empty base."
  EXP_VER=$(tr -d '[:space:]' < "$TMP/exp/VERSION" 2>/dev/null) || EXP_VER=''
  [ -n "$EXP_VER" ] || EXP_VER=unknown
  if [ -f "$TMP/exp/.kit-source" ]; then
    { parse_kit_source "$TMP/exp/.kit-source" && [ "$KS_SHA" = "$FULL" ]; } \
      || die "the export of $(short12 "$FULL") records a .kit-source that is malformed or names a DIFFERENT commit. Refusing to write a base whose label disagrees with its content."
  fi
  TAG="kit-base/v${EXP_VER}+$(short12 "$FULL")"
  # the tag name comes from the vendor's VERSION: validate it BEFORE any write (a refused name must move nothing)
  git check-ref-format "refs/tags/$TAG" \
    || die "the tag '$TAG' is not a valid git ref name (the vendor's VERSION '$EXP_VER' cannot be a tag component). REFUSING. (Nothing was written.)"
  ! git -C "$REPO" rev-parse --verify --quiet "refs/tags/$TAG" >/dev/null 2>&1 \
    || die "the tag '$TAG' already exists. A kit-base tag is never moved. (Nothing was written.)"
  : > "$TMP/behind.new.tsv"; BEHIND_NEW=0
  [ "$_KU_BEHIND" = on ] || return 0   # the A15/A17 mutant: record 0 behind, as before per-path provenance
  advance_provenance
}

# ── PER-PATH PROVENANCE — what did HEAD actually TAKE of this release? (design §4.1) ──────────────────────
# Three trees, all in ADOPTER coordinates, in the throwaway workbench: E = the effective base of the tip; T =
# incept(export(R)) at the manifest shape; OURS = HEAD (fetched read-only). Only the paths whose content
# differs between E and T are candidates; every other path is already at R in the base.

# adv_candidates — $TMP/cand = the paths to test. For a re-advance at the SAME release only the tip's behind
# paths can still be behind (E already carries the rest). A quoted/odd path (a newline, a control character, a
# quote or backslash: git prints those quoted) refuses the advance: it could not be written into the record.
adv_candidates() {
  names_diff "$C_E" "$C_T" > "$TMP/cand"
  if [ "$READV" -eq 1 ]; then
    cut -f2 "$TMP/behind.tsv" | LC_ALL=C sort > "$TMP/cand.old"
    comm -12 "$TMP/cand" "$TMP/cand.old" > "$TMP/cand.next"; mv "$TMP/cand.next" "$TMP/cand"
  fi
  if grep -q '^"' "$TMP/cand" || grep -q '[[:cntrl:]]' "$TMP/cand"; then
    die "a path the release changes contains a newline, a control character, a quote or a backslash — it cannot be written into the base's 'behind' record. REFUSING; nothing was written."
  fi
}

# adv_blob <commit> <path> -> the blob oid in the workbench, or '' when the path is absent there
adv_blob() { git -C "$W" rev-parse --verify --quiet "$1:$2" 2>/dev/null || :; }

# adv_merge_noop <o-oid> <e-oid> <t-oid> — rc 0 iff git's OWN 3-way of OURS/E/T is CLEAN and its output equals
# OURS: the release's hunks are already in HEAD's file (a hand-merge, or a take-then-edit). A binary file or a
# merge-file error is rc 1 — so for those, "taken" needs byte equality, and the test fails toward BEHIND.
adv_merge_noop() {
  mkdir -p "$TMP/mf"
  git -C "$W" cat-file blob "$1" > "$TMP/mf/o" 2>/dev/null && git -C "$W" cat-file blob "$2" > "$TMP/mf/e" 2>/dev/null \
    && git -C "$W" cat-file blob "$3" > "$TMP/mf/t" 2>/dev/null || return 1
  _mn_rc=0
  git -C "$W" merge-file -p "$TMP/mf/o" "$TMP/mf/e" "$TMP/mf/t" > "$TMP/mf/out" 2>/dev/null || _mn_rc=$?
  [ "$_mn_rc" -eq 0 ] && cmp -s "$TMP/mf/out" "$TMP/mf/o"
}

# adv_taken <path> — rc 0 = HEAD TOOK the release's change to this path; rc 1 = it is BEHIND.
#   release deleted it  -> taken iff HEAD lacks it        release added it -> taken iff HEAD has it
#   release modified it -> taken iff HEAD has T's bytes, or the 3-way no-op test above holds
adv_taken() {
  _at_o=$(adv_blob "$C_O" "$1"); _at_e=$(adv_blob "$C_E" "$1"); _at_t=$(adv_blob "$C_T" "$1")
  if [ -z "$_at_t" ]; then [ -z "$_at_o" ]; return $?; fi
  if [ -z "$_at_e" ]; then [ -n "$_at_o" ]; return $?; fi
  [ -n "$_at_o" ] || return 1
  [ "$_at_o" != "$_at_t" ] || return 0
  adv_merge_noop "$_at_o" "$_at_e" "$_at_t"
}

# adv_named <path> -> the chain commit whose incepted blob stays the base for this path: the old tip's value when
# the path was ALREADY behind, otherwise the old tip itself.
adv_named() {
  _nm=$(P=$1 awk -F'\t' '$2 == ENVIRON["P"] { print $1; exit }' "$TMP/behind.tsv")
  printf '%s\n' "${_nm:-$OLD}"
}

# adv_classify — walks the candidates; $TMP/behind.new.tsv = `<named commit> TAB <path>` for each BEHIND one.
adv_classify() {
  : > "$TMP/behind.new.tsv"
  while IFS= read -r _ac_p; do
    [ -n "$_ac_p" ] || continue
    adv_taken "$_ac_p" && continue
    printf '%s\t%s\n' "$(adv_named "$_ac_p")" "$_ac_p" >> "$TMP/behind.new.tsv"
  done < "$TMP/cand"
  LC_ALL=C sort -t "$(printf '\t')" -k2,2 "$TMP/behind.new.tsv" -o "$TMP/behind.new.tsv"
  BEHIND_NEW=$(n "$TMP/behind.new.tsv")
}

# advance_provenance — build E / T / OURS in the workbench, classify, and refuse a re-advance that took nothing new.
# (On a re-advance the candidates are only the tip's behind paths, so a path still behind is carried over by the same
# rule: it names the old tip's value.) A path behind in the OLD tip but no longer a candidate (E == T there) is gone.
advance_provenance() {
  read_behind "$OLD" "$TMP/behind.tsv"   # a corrupt tip record refuses BEFORE the incepts are paid for
  mkdir -p "$TMP/t" "$TMP/base"
  ( cd "$TMP/exp" && tar -cf - . ) | ( cd "$TMP/t" && tar -xf - ) || die "could not copy the export for incept."
  run_incept "$TMP/t" 'the release HEAD took'
  build_effective_base "$TMP/base"
  ensure_workbench
  C_E=$(commit_dir "$TMP/base") || die "could not snapshot the tip's effective base"
  C_T=$(commit_dir "$TMP/t")    || die "could not snapshot the release HEAD took"
  C_O=$(fetch_commit "$REPO")   || die "could not read your HEAD (read-only) into the workbench"
  adv_candidates
  adv_classify
  if [ "$READV" -eq 1 ] && [ "$BEHIND_NEW" -ge "$(n "$TMP/behind.tsv")" ]; then
    die "vendor commit $(short12 "$FULL") is already in the kit-base chain as the tip with $(n "$TMP/behind.tsv") file(s) still behind, and nothing new was taken since — nothing to advance. Take (or merge) more of that release, pull, and re-run. (Nothing was written.)"
  fi
}

# advance_message <file> — the commit message: subject, the behind block (one paragraph), then the trailers as the
# LAST paragraph (contiguous: a blank line inside it would hide every Kit-* field above it from git).
advance_message() {
  _am_sub="the release HEAD took"
  [ "$BEHIND_NEW" -eq 0 ] || _am_sub="the release HEAD took — PARTIAL: $BEHIND_NEW file(s) behind"
  {
    printf 'kit-base: advance to v%s@%s (%s)\n\n' "$EXP_VER" "$(short12 "$FULL")" "$_am_sub"
    if [ "$BEHIND_NEW" -gt 0 ]; then
      awk -F'\t' '{ print "behind " $1 " " $2 }' "$TMP/behind.new.tsv"
      printf '\n'
    fi
    printf 'Kit-Source: %s\nKit-Version: %s\nKit-Behind: %s\n' "$FULL" "$EXP_VER" "$BEHIND_NEW"
  } > "$1"
}

# advance_write — THE WRITES: a tree + a commit (objects), the kit-base compare-and-swap, and — only when the
# release is now FULLY taken — the create-only tag.
advance_write() {
  ADV_GD=$(git -C "$REPO" rev-parse --absolute-git-dir) || die "cannot resolve the adopter's git dir."
  ADV_IDX="$TMP/adv.index"; ADV_WT="$TMP/exp"   # the temp index must NOT exist (an empty file reads as corrupt)
  adv_git -C "$TMP/exp" add -Af . >/dev/null 2>&1 || die "could not stage the export into a temporary index."
  _tree=$(adv_git write-tree) || die "could not write the base tree."
  advance_message "$TMP/adv.msg"
  _new=$(adv_git -c user.name='Sparkwright kit-base' -c user.email='kit-base@sparkwright.local' \
      -c commit.gpgsign=false commit-tree "$_tree" -p "$OLD" -F "$TMP/adv.msg") || die "could not write the kit-base commit."
  # ONE transaction: `update-ref --stdin` applies the whole batch all-or-nothing (no start/prepare/commit verbs
  # needed, so any git that has --stdin works): the kit-base compare-and-swap AND (when complete) the create-only
  # tag, or neither.
  _aw_what='kit-base'
  [ "$BEHIND_NEW" -gt 0 ] || _aw_what="kit-base and create the tag '$TAG'"
  { printf 'update refs/heads/kit-base %s %s\n' "$_new" "$OLD"
    [ "$BEHIND_NEW" -gt 0 ] || printf 'create refs/tags/%s %s\n' "$TAG" "$_new"
  } | adv_git update-ref -m "kit-update --advance-base: v$EXP_VER@$(short12 "$FULL")" --stdin \
    || die "could not move $_aw_what in one transaction (kit-base moved under this run, or the tag appeared). No ref was moved (the new objects may exist, unreferenced); re-run."
}

# advance_report — the local write, said plainly: complete, or PARTIAL with the behind paths listed.
advance_report() {
  if [ "$BEHIND_NEW" -eq 0 ]; then
    echo "kit-update: kit-base advanced — it now records the release HEAD took (complete: Kit-Behind: 0)."
    _ar_tag="tag: $TAG"; _ar_wrote="refs/tags/$TAG (create-only), "
    _ar_undo="git update-ref refs/heads/kit-base $OLD && git tag -d '$TAG'"
  else
    echo "kit-update: kit-base advanced PARTIALLY — HEAD took part of this release; $BEHIND_NEW file(s) are recorded BEHIND (Kit-Behind: $BEHIND_NEW)."
    _ar_tag="no tag (a tag names a release FULLY taken)"; _ar_wrote=''
    _ar_undo="git update-ref refs/heads/kit-base $OLD"
  fi
  echo "  vendor commit: $FULL (v$EXP_VER) — $ADV_HOW"
  echo "  kit-base:      $(short12 "$OLD") -> $(short12 "$_new")   $_ar_tag"
  echo "  tree:          that commit's OWN adopter-export, at the shape you received — $THEIRS_SHAPE"
  if [ "$BEHIND_NEW" -gt 0 ]; then
    echo "  behind:        the next --from offers each of these (or lists it CONFLICT if you changed it); finish with the same --advance-base command once they are taken:"
    awk -F'\t' '{ print "                   - " $2 "  (base stays at chain commit " substr($1, 1, 12) ")" }' "$TMP/behind.new.tsv" | strip_ctl
  fi
  echo "  wrote:         refs/heads/kit-base (compare-and-swap), ${_ar_wrote}and the objects behind that commit. Nothing else locally."
  echo "  undo (local):  $_ar_undo"
}

# ── PUBLISH (design §4.3) — one atomic, never-forced push of the base, so a teammate's clone has it too ───
# adv_publish_refs — the refspecs: the local branch kit-base to the NON-BRANCH ref refs/kit/base on the remote, plus
# every LOCAL kit-base/* tag whose commit is in the chain. WHY refs/kit/base AND NOT refs/heads/kit-base: the kit's
# pre-push hook (hooks/pre-push) grades every refs/heads/* push except main/master, and a kit-base commit carries no
# Kit-Row — the hook would refuse the publish on every adopter that has it installed. A ref outside refs/heads (and
# not a tag) is not graded, is not a branch (no PR, no CI branch run), and is still fast-forward-only on the remote.
adv_publish_refs() {
  git -C "$REPO" rev-list --first-parent refs/heads/kit-base > "$TMP/pub.chain"
  _pr_root=$(tail -n 1 "$TMP/pub.chain")
  set -- refs/heads/kit-base:refs/kit/base
  for _pr in $(git -C "$REPO" for-each-ref --format='%(refname)' 'refs/tags/kit-base/'); do
    _prc=$(git -C "$REPO" rev-parse --verify --quiet "$_pr^{commit}") || continue
    grep -qxF -- "$_prc" "$TMP/pub.chain" || continue
    adv_tag_is_ours "${_pr#refs/tags/kit-base/}" "$_prc" "$_pr_root" && set -- "$@" "$_pr:$_pr"
  done
  PUB_REFS=$*
}

# adv_tag_is_ours <tag name after kit-base/> <the commit it points at> <the chain root> — only the tags this tool and
# incept MAKE are published: `v<VER>+<sha12>` whose <sha12> is the first 12 of the tagged commit's own Kit-Source, or
# the legacy `v<VER>` at the chain ROOT. Any other `kit-base/*` tag on the chain (a teammate's note, a lookalike) stays local.
adv_tag_is_ours() {
  # K1 (security): the NAME is validated whole, because it is printed (the undo line) and used in a ref command: a version part
  # carrying a quote, `$` or `;` must never reach either. `v<VER>+<sha12>` or the legacy `v<VER>`, VER = digit then [A-Za-z0-9.-].
  printf '%s' "$1" | grep -Eq -e '^v[0-9][0-9A-Za-z.-]*\+[0-9a-f]{12}$' -e '^v[0-9][0-9A-Za-z.-]*$' || return 1
  case "$1" in
    v*+*)
      _ato_sha=${1##*+}; _ato_src=$(commit_source "$2")
      [ -n "$_ato_src" ] && [ "${#_ato_sha}" = 12 ] && [ "$(short12 "$_ato_src")" = "$_ato_sha" ] ;;
    v*) [ "$2" = "$3" ] ;;
    *) return 1 ;;
  esac
}

# _ku_proxy_cfg — run INSIDE a network wrapper's subshell, BEFORE it zeroes the ambient config. KIT-UPDATE-GIT-PROXY-
# PASSTHROUGH: a sandboxed agent's git authenticates to its egress proxy THROUGH the environment's command-scope config
# (http.proxyAuthMethod + a credential helper scoped to the proxy's own origin), which the scrub below would drop —
# git then reaches the proxy and fails its auth ("Proxy CONNECT aborted"). This reads the ambient command-scope
# entries with GIT'S OWN parser (`git config --show-scope -z --get-regexp`; the quoted GIT_CONFIG_PARAMETERS format is
# never parsed here), keeps ONLY http.proxyauthmethod and credential.<P>.helper where <P> is exactly the effective
# proxy origin (https_proxy, else HTTPS_PROXY; userinfo and path stripped, a default port normalised away on both
# sides), and EXPORTS them as GIT_CONFIG_COUNT/KEY_i/VALUE_i. Nothing else passes: no helper for another URL, no
# url.*.insteadOf, no core.*, no other http.*. No proxy variable, a read failure or a newline in a selected value =
# COUNT=0, today's plain scrub. It always ASSIGNS and exports GIT_CONFIG_COUNT (git needs it inert, not absent).
# Only adv_push and ku_net call it; adv_git and _ku_git never talk to a remote and stay plain.
_ku_proxy_cfg() {
  _kpc_n=0; _kpc_list=''
  if [ -n "${https_proxy:-${HTTPS_PROXY:-}}" ]; then
    _kpc_list=$( { git config --show-scope -z --get-regexp '^http\.proxyauthmethod$' 2>/dev/null
                   git config --show-scope -z --get-regexp '^credential\..*\.helper$' 2>/dev/null
                 } | tr '\036\000' '\001\036' \
      | KU_PROXY="${https_proxy:-${HTTPS_PROXY:-}}" awk '
        function norm(u, strict,   i, s, r, p) {
          i = index(u, "://"); if (i == 0) return ""
          s = tolower(substr(u, 1, i - 1)); r = substr(u, i + 3)
          if (s != "http" && s != "https") return ""
          if (strict) { if (r ~ /[\/?#@ ]/) return "" } else { sub(/[\/?#].*$/, "", r); sub(/^.*@/, "", r) }
          r = tolower(r); if (r == "") return ""
          p = (s == "http") ? "80" : "443"
          if (match(r, /:[0-9]+$/) && substr(r, RSTART + 1) == p) r = substr(r, 1, RSTART - 1)
          return s "://" r
        }
        BEGIN { RS = "\036" }
        { rec[NR] = $0 }
        END {
          want = norm(ENVIRON["KU_PROXY"], 0); if (want == "") exit 0
          for (i = 1; i + 1 <= NR; i += 2) {
            if (rec[i] != "command") continue
            nl = index(rec[i + 1], "\n"); if (nl == 0) continue
            key = substr(rec[i + 1], 1, nl - 1); val = substr(rec[i + 1], nl + 1)
            sel = 0
            if (key == "http.proxyauthmethod") sel = 1
            else if (substr(key, 1, 11) == "credential." && length(key) > 18 && substr(key, length(key) - 6) == ".helper") sel = (norm(substr(key, 12, length(key) - 18), 1) == want)
            if (!sel) continue
            if (index(val, "\n") > 0 || index(val, "\001") > 0) exit 0
            out = out key "\n" val "\n"
          }
          printf "%s", out
        }'
                 printf '.' )
  fi
  # the list is key NL value NL ... and a final "." (kept so the substitution cannot strip a trailing empty value)
  while :; do
    case $_kpc_list in
      *"
"*) ;;
      *) break ;;
    esac
    _kpc_k=${_kpc_list%%"
"*}; _kpc_list=${_kpc_list#*"
"}
    _kpc_v=${_kpc_list%%"
"*}; _kpc_list=${_kpc_list#*"
"}
    eval "GIT_CONFIG_KEY_$_kpc_n=\$_kpc_k; GIT_CONFIG_VALUE_$_kpc_n=\$_kpc_v"
    export "GIT_CONFIG_KEY_$_kpc_n" "GIT_CONFIG_VALUE_$_kpc_n"
    _kpc_n=$((_kpc_n + 1))
  done
  GIT_CONFIG_COUNT=$_kpc_n; export GIT_CONFIG_COUNT
}

# adv_push — the publish push with a SCRUBBED git CONFIG environment (the pattern of adv_git/_ku_git: an ambient
# GIT_CONFIG_COUNT/KEY_n/VALUE_n/PARAMETERS or a redirected global/system config must not inject config — a
# credential helper, a url rewrite, core.sshCommand — into the one command that talks to the network). Only the
# config-injection variables are scrubbed: GIT_SSH_COMMAND, GIT_SSH, GIT_ASKPASS and GIT_PROXY_COMMAND are the
# user's own transport settings and pass through. HOME and the repo/user config files stay: the adopter's own
# credentials and remotes are the point. The ONE config exception is _ku_proxy_cfg above: the proxy's own auth.
adv_push() {
  ( _ku_proxy_cfg
    GIT_CONFIG_PARAMETERS=''; export GIT_CONFIG_PARAMETERS
    env -u GIT_NAMESPACE -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_SYSTEM -u GIT_CONFIG -u GIT_CONFIG_NOSYSTEM \
        git -C "$REPO" push --atomic "$REMOTE" "$@" )
}

# _ku_proxy_refused <logfile> — true when git's output says the PROXY refused the connection (git: "Proxy CONNECT aborted";
# curl: "Received HTTP code 407 from proxy after CONNECT" / "CONNECT tunnel failed, response 407"). A bare 407 is not
# matched: it appears inside shas and ports.
_ku_proxy_refused() {
  grep -q -e 'Proxy CONNECT aborted' -e 'code 407' -e 'response 407' "$1" 2>/dev/null
}

# advance_publish — sets PUBLISH_RC (0 ok / skipped / no remote; 3 = the push failed).
PUBLISH_RC=0
advance_publish() {
  # The remedy is the tool's OWN verb: the raw `git push --atomic …` refspec is denied to an agent by the guard, so printing
  # it left an agent with only a command it may not run. The raw form stays documented for a human in docs/operations/kit-base.md.
  _pb_hint="sh scripts/kit-update.sh --publish-base"
  [ "$REMOTE" = origin ] || _pb_hint="$_pb_hint --remote $REMOTE"
  [ "$REPO" = "$(pwd -P)" ] || _pb_hint="$_pb_hint --repo \"$REPO\""
  if [ -n "$NO_PUSH" ]; then
    echo "  publish:       skipped (--no-push) — kit-base stays local. To publish later: $_pb_hint"; return 0
  fi
  if ! git -C "$REPO" config --get "remote.$REMOTE.url" >/dev/null 2>&1; then
    echo "  publish:       no remote '$REMOTE' in this repo — kit-base stays local (name one with --remote <name>, then publish it: $_pb_hint)"; return 0
  fi
  adv_publish_refs
  _pb_n=$(printf '%s\n' "$PUB_REFS" | wc -w | tr -d ' ')
  _pb_rc=0
  # shellcheck disable=SC2086  # PUB_REFS is OUR list of validated ref names (no spaces possible in a ref)
  adv_push $PUB_REFS > "$TMP/push.log" 2>&1 || _pb_rc=$?
  if [ "$_pb_rc" -eq 0 ]; then
    echo "  publish:       pushed $_pb_n ref(s) to '$REMOTE' in ONE atomic, non-forced push ($REMOTE's refs/kit/base + the kit-base tags in the chain)"
    echo "                 a teammate's clone imports it, VERIFIED, on its next 'kit-update --from' (or '--advance-base') — nothing to fetch by hand"
    echo "                 refs/kit/base has no forge protection: anyone with push access can write it; teammates' kit-update verifies every imported chain commit before running it"
    return 0
  fi
  PUBLISH_RC=3
  echo "kit-update: PUBLISH FAILED (rc $_pb_rc) — the LOCAL write stands, but '$REMOTE' did not take kit-base; nothing was forced:" >&2
  sed 's/^/    /' "$TMP/push.log" | strip_ctl >&2 || :
  if grep -q -e '\[rejected\]' -e '\[remote rejected\]' -e 'non-fast-forward' "$TMP/push.log"; then
    echo "  REJECTED ref(s):" >&2
    grep -e '\[rejected\]' -e '\[remote rejected\]' "$TMP/push.log" | sed 's/^/    /' | strip_ctl >&2 || :
    echo "  '$REMOTE' has a ref this clone does not descend from (most likely a teammate advanced refs/kit/base)." >&2
    echo "  This tool never forces. Re-run 'kit-update --from <source>': it imports the teammate's chain through the verification" >&2
    echo "  (a fast-forward of yours, or a DIVERGED report with the verified route), then publish again: $_pb_hint" >&2
  else
    echo "  The push failed for a reason that is not a rejection (see git's message above: network, credentials, a hook?)." >&2
    echo "  The local advance is intact; fix the cause and publish: $_pb_hint" >&2
    if _ku_proxy_refused "$TMP/push.log"; then
      echo "  the proxy refused the connection; if your shell reaches the remote with plain git, your proxy authenticates through git config in the environment — see docs/operations/egress-control.md" >&2
    fi
  fi
}

# advance_base — THE ONLY WRITER. See the header: it writes refs/heads/kit-base (compare-and-swap), a tag only
# when the release is complete, and the objects behind the commit — nothing else locally — then publishes.
advance_base() { advance_prepare; advance_write; advance_report; advance_publish; }

# ══ KIT-BASE-SHARED — RECEIVE the shared base from the remote, VERIFIED before it is used ═══════════════════════════
# (design: docs/architecture/2026-10-05-kit-base-shared-design.md). Before this, a clone or a teammate had no base, and
# the hand-fetch the docs offered was an UNVERIFIED code-execution channel: every `--from` re-runs the chain commits' OWN
# scripts/incept.sh, and `refs/kit/base` sits outside branch protection. Now `--from` and `--advance-base` call
# `sync_base`, which fetches the remote's `refs/kit/base` through the temporary `refs/kit-import/base` (deleted at once), classifies it
# against the local `kit-base`, VERIFIES every commit it would import (`verify_chain_commit`) and only then writes —
# create-when-absent or a compare-and-swap fast-forward, one `update-ref --stdin` transaction, plus the chain's own tags.

# _ku_git: the same env-scrubbing wrapper guard-wired.sh's _gw_git and inception-done.sh's _id_git use
# (review round 1). The consequence at hook_mode is milder than at a gate — the worst case is WRONG ADVICE
# about whether a copy needs refreshing, not a forged verdict — but the fix is three lines and the
# alternative is a third copy of the same known hole left open on purpose. The import's ref write goes through it too.
# ⚠️ `env -u`, NOT `unset` (whole-branch review I-1 / security L1, 2026-09-18): in bash-as-/bin/sh,
# `unset` of a var that carried a TEMPORARY PREFIX assignment over an ALREADY-EXPORTED one RESTORES
# the exported value instead of removing it — measured on the locator family (GIT_DIR/GIT_WORK_TREE)
# as well as the config-injection one. `env -u` removes the name from the CHILD environment whatever
# the shell's unset semantics are; not POSIX, but present in GNU coreutils, the BSDs (macOS included)
# and BusyBox. COUNT=0/PARAMETERS='' stay ASSIGNMENTS: git needs them INERT, not absent.
_ku_git() {
  ( GIT_CONFIG_COUNT=0; GIT_CONFIG_PARAMETERS=''
    export GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
    env -u GIT_DIR -u GIT_COMMON_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_CONFIG_GLOBAL \
        -u GIT_CONFIG_SYSTEM -u GIT_CONFIG_NOSYSTEM -u GIT_CONFIG -u GIT_CEILING_DIRECTORIES -u GIT_OBJECT_DIRECTORY -u GIT_ALTERNATE_OBJECT_DIRECTORIES -u GIT_NAMESPACE git "$@" )
}

# ku_net <git args> — git for the commands that talk to the REMOTE (ls-remote, fetch): the scrubbed-config pattern of
# adv_push (an ambient GIT_CONFIG_COUNT/KEY_n/VALUE_n/PARAMETERS or a redirected global/system config must not inject a
# credential helper, a url rewrite or core.sshCommand into a network command), plus the repo LOCATOR family unset so the
# fetched objects land in the repo --repo names. GIT_SSH_COMMAND/GIT_SSH/GIT_ASKPASS/GIT_PROXY_COMMAND are the user's own
# transport settings and pass through; HOME and the repo/user config stay (the adopter's credentials and remotes are the point).
ku_net() {
  ( _ku_proxy_cfg
    GIT_CONFIG_PARAMETERS=''; export GIT_CONFIG_PARAMETERS
    env -u GIT_DIR -u GIT_COMMON_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_OBJECT_DIRECTORY -u GIT_ALTERNATE_OBJECT_DIRECTORIES \
        -u GIT_CEILING_DIRECTORIES -u GIT_NAMESPACE -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_SYSTEM -u GIT_CONFIG -u GIT_CONFIG_NOSYSTEM \
        git -C "$REPO" "$@" )
}

# the longest chain one import will take (a bound on the exports verification pays for; a real chain is a handful)
KBS_MAX_IMPORT=200
KBS_VN=0

# kbs_refuse <chain commit> <reason> — the import is REFUSED: the commit, the reason, "Nothing was written", the way out.
kbs_refuse() {
  echo "kit-update: kit-base import REFUSED — chain commit $(short12 "$1") $2. Nothing was written." >&2
  echo "  Anyone with push access to '$REMOTE' can write refs/kit/base, so kit-update verifies every imported chain commit against '$FROM'; this one failed. Nothing from it was imported, and none of its code ran." >&2
  echo "  Point --from at the source you adopted from, or ask the publisher to re-publish (kit-update --advance-base, then --publish-base, from a tree that records .kit-source)." >&2
  exit 1
}
# kbs_unrecorded <chain commit> — a commit with no (valid) Kit-Source cannot be verified, and is never imported. There is
# deliberately NO hand-import line here: any raw fetch of an unverifiable chain is the channel this control closes.
kbs_unrecorded() {
  echo "kit-update: kit-base import REFUSED — chain commit $(short12 "$1") records no Kit-Source (a base written before the chain carried one, or not by kit-update), so it cannot be verified. Nothing was written." >&2
  echo "  The publisher re-publishes from a tree that records .kit-source (kit-update --advance-base, then --publish-base). Anyone with push access to '$REMOTE' can write refs/kit/base; an unverifiable chain is not imported." >&2
  exit 1
}

# ku_dir_entries <dir> <outfile> — the entries git WOULD store for <dir>, `mode SP type SP blob TAB path`, one per line, a
# NEWLINE inside a path mapped to \001 (so a path can never split an entry; verify_chain_commit refuses any control byte).
# Hashed the way advance_write hashes the export (a temp index, `add -Af`), in the throwaway workbench.
ku_dir_entries() {
  ensure_workbench
  ADV_GD="$W/.git"; ADV_IDX="$TMP/de.idx"; ADV_WT=$1; rm -f "$ADV_IDX"
  adv_git -C "$1" add -Af . >/dev/null 2>&1 || return 1
  _de_tree=$(adv_git write-tree) || return 1
  adv_git ls-tree -r -z "$_de_tree" | tr '\000\n' '\n\001' > "$2"
  [ -s "$2" ]
}

# kbs_union <Kit-Source 40-hex> <outfile> <chain commit> — <outfile> = the sorted union of the entries of the two exports
# (un-pruned, and `--profile <stack>`) that Kit-Source's OWN adopter-export.sh makes, run in a worktree of the --from clone
# detached there. A failed profile export (a release that lacks the profile) leaves the un-pruned export as the union.
kbs_union() {
  [ ! -s "$2" ] || return 0
  KBS_VN=$((KBS_VN + 1)); _ku_w="$TMP/v.$KBS_VN"
  git -C "$TMP/new" worktree add --detach -q "$_ku_w" "$1" >/dev/null 2>&1 \
    || kbs_refuse "$3" "has a Kit-Source ($(short12 "$1")) that cannot be checked out in --from"
  [ -f "$_ku_w/scripts/adopter-export.sh" ] || kbs_refuse "$3" "names a release ($(short12 "$1")) that has no scripts/adopter-export.sh"
  sh "$_ku_w/scripts/adopter-export.sh" "$TMP/vx.$KBS_VN.f" >"$TMP/exp.log" 2>&1 \
    || kbs_refuse "$3" "names a release ($(short12 "$1")) whose own adopter-export.sh failed"
  ku_dir_entries "$TMP/vx.$KBS_VN.f" "$TMP/vx.$KBS_VN.f.e" || kbs_refuse "$3" "names a release ($(short12 "$1")) whose export came out empty"
  cp "$TMP/vx.$KBS_VN.f.e" "$TMP/vx.$KBS_VN.u"
  cut -f2- "$TMP/vx.$KBS_VN.f.e" | LC_ALL=C sort > "$2.pf"      # the un-pruned export's PATH SET (completeness, L1)
  rm -f "$2.pp"
  if sh "$_ku_w/scripts/adopter-export.sh" "$TMP/vx.$KBS_VN.p" --profile "$STACK" >"$TMP/exp.log" 2>&1 \
     && ku_dir_entries "$TMP/vx.$KBS_VN.p" "$TMP/vx.$KBS_VN.p.e"; then
    cat "$TMP/vx.$KBS_VN.p.e" >> "$TMP/vx.$KBS_VN.u"
    cut -f2- "$TMP/vx.$KBS_VN.p.e" | LC_ALL=C sort > "$2.pp"   # …and the --profile export's
  fi
  LC_ALL=C sort -u "$TMP/vx.$KBS_VN.u" > "$2"
  rm -rf "$_ku_w" "$TMP/vx.$KBS_VN.f" "$TMP/vx.$KBS_VN.p" 2>/dev/null || :
}

# verify_chain_commit <chain commit> <is_root 0|1> — THE SECURITY CONTROL (design §4). A commit fetched from the remote is
# written into kit-base only if ALL hold; the first failure is a refusal that writes nothing (kbs_refuse exits 1):
#   1. exactly one parent (none only for the chain's first commit, when the whole chain is being created), and a Kit-Source
#      trailer that is 40 lowercase hex;
#   2. that Kit-Source is a release YOUR history recorded in .kit-source (the anchor; `_KU_ANCHOR`), resolves in the --from
#      clone AND is an ancestor of its HEAD. (The caller also checks the chain runs oldest to newest and that each commit's
#      `behind`/`Kit-Behind` record passes read_behind's strict rules.) STACK is the CLAUDE.md §3 stamp the run already read;
#   3. its tree has no control byte in a path, no symlink (120000) and no submodule (160000) entry, and holds
#      scripts/incept.sh and .kit-manifest;
#   4. EVERY entry (mode, blob, path) of its tree is an entry of one of the two exports that Kit-Source's OWN exporter
#      produces, and the tree's PATH SET equals one export's (nothing added, nothing dropped) — so a forged
#      scripts/incept.sh never gets in.
# `_KU_VERIFY_IMPORT=off` (the M1 mutant, in a COPY) skips 3 and 4 only.
verify_chain_commit() {
  _vc=$1
  _vc_np=$(git -C "$REPO" rev-list --parents -n 1 "$_vc" | awk '{ print NF - 1 }')
  case "$_vc_np:$2" in
    1:*|0:1) : ;;
    *) kbs_refuse "$_vc" "has $_vc_np parent(s) — a chain commit has exactly one (only the chain's first commit has none)" ;;
  esac
  _vc_src=$(commit_source "$_vc")
  [ -n "$_vc_src" ] || kbs_unrecorded "$_vc"
  # ANCHOR (H2): the Kit-Source must be a release YOUR OWN history recorded in .kit-source (the set kbs_anchors collected),
  # so a writer of refs/kit/base cannot make the chain claim a genuine release this project never took. A legacy tree whose
  # history never recorded one (empty set) falls back to the --from-history rule below, with a printed warning.
  if [ "$_KU_ANCHOR" = on ] && [ -s "$TMP/sb.anch" ] && ! grep -qxF -- "$_vc_src" "$TMP/sb.anch"; then
    kbs_refuse "$_vc" "has a Kit-Source ($(short12 "$_vc_src")) that no commit of YOUR history recorded in .kit-source — it is not a release this project took (if a teammate's update recording it has merged, pull main and re-run)"
  fi
  if git -C "$TMP/new" rev-parse --verify --quiet "$_vc_src^{commit}" >/dev/null 2>&1 \
     && git -C "$TMP/new" merge-base --is-ancestor "$_vc_src" HEAD 2>/dev/null; then :; else
    kbs_refuse "$_vc" "has a Kit-Source ($(short12 "$_vc_src")) that is not in the history of --from"
  fi
  [ "$_KU_VERIFY_IMPORT" = on ] || return 0
  git -C "$REPO" ls-tree -r -z "$_vc^{tree}" | tr '\000\n' '\n\001' > "$TMP/vc.ents"
  [ -s "$TMP/vc.ents" ] || kbs_refuse "$_vc" "has an empty tree"
  tr -d '\001-\010\013-\037\177' < "$TMP/vc.ents" | cmp -s - "$TMP/vc.ents" \
    || kbs_refuse "$_vc" "has a path with a control character (a newline, an escape ...) — the kit ships none"
  _vc_l=$(grep '^120000 ' "$TMP/vc.ents" | sed -n '1p' | cut -f2- | strip_ctl) || :
  [ -z "$_vc_l" ] || kbs_refuse "$_vc" "has a symlink entry ('$_vc_l') — the kit ships none, and a link in the base would point outside the tree materialized from it"
  _vc_l=$(grep '^160000 ' "$TMP/vc.ents" | sed -n '1p' | cut -f2- | strip_ctl) || :
  [ -z "$_vc_l" ] || kbs_refuse "$_vc" "has a submodule entry ('$_vc_l') — the kit ships none"
  for _vc_req in scripts/incept.sh .kit-manifest; do
    cut -f2- "$TMP/vc.ents" | grep -qxF -- "$_vc_req" || kbs_refuse "$_vc" "has no '$_vc_req' — it is not a kit-base tree"
  done
  kbs_union "$_vc_src" "$TMP/vu.$_vc_src" "$_vc"
  LC_ALL=C sort -u "$TMP/vc.ents" > "$TMP/vc.sorted"
  _vc_out=$(comm -23 "$TMP/vc.sorted" "$TMP/vu.$_vc_src" | sed -n '1p')
  if [ -n "$_vc_out" ]; then
    _vc_pth=$(printf '%s\n' "$_vc_out" | cut -f2- | strip_ctl)
    kbs_refuse "$_vc" "has a tree entry that no export of its Kit-Source ($(short12 "$_vc_src")) produces: '$_vc_pth' (mode $(printf '%s' "$_vc_out" | cut -d' ' -f1)) — a forged or altered base"
  fi
  # COMPLETENESS (L1): the PATH SET must equal that of one export (un-pruned or --profile <stack>); the blobs and modes may
  # come from either shape's entry at that path (the union above). A tree that drops or adds a path is not a base of it.
  cut -f2- "$TMP/vc.ents" | LC_ALL=C sort > "$TMP/vc.paths"
  if cmp -s "$TMP/vc.paths" "$TMP/vu.$_vc_src.pf" || { [ -f "$TMP/vu.$_vc_src.pp" ] && cmp -s "$TMP/vc.paths" "$TMP/vu.$_vc_src.pp"; }; then return 0; fi
  _vc_d=$( { comm -23 "$TMP/vc.paths" "$TMP/vu.$_vc_src.pf"; comm -13 "$TMP/vc.paths" "$TMP/vu.$_vc_src.pf"; } | sed -n '1p' | strip_ctl)
  kbs_refuse "$_vc" "has a path set that matches no export of its Kit-Source ($(short12 "$_vc_src")) — it adds or drops files (e.g. '$_vc_d')"
}

# kbs_anchors — $TMP/sb.anch = every release THIS project's own history recorded in .kit-source (first-parent log of HEAD,
# each version read with the same strict parse head_kit_source uses). Empty = a legacy tree: say so, fall back.
kbs_anchors() {
  : > "$TMP/sb.anch"
  for _an_c in $(git -C "$REPO" log --first-parent --format=%H -- .kit-source 2>/dev/null); do
    git -C "$REPO" show "$_an_c:.kit-source" > "$TMP/sb.ks" 2>/dev/null || continue
    if parse_kit_source "$TMP/sb.ks"; then printf '%s\n' "$KS_SHA" >> "$TMP/sb.anch"; fi
  done
  [ -s "$TMP/sb.anch" ] && return 0
  echo "kit-base: WARNING — this project's history never recorded a .kit-source (a legacy tree), so an imported chain cannot be anchored to a release you took; falling back to 'the Kit-Source is in --from's history'." >&2
}

# kbs_diverged — this clone's tip and the remote's each hold chain commits the other lacks: report both, write nothing.
kbs_diverged() {
  echo "kit-update: kit-base DIVERGED — this clone's kit-base ($(short12 "$KBS_L")) and '$REMOTE''s refs/kit/base ($(short12 "$KBS_R")) each hold chain commits the other lacks (or are more than $KBS_MAX_IMPORT commits apart). Nothing was written." >&2
  echo "  This tool never forces. To keep yours, the owner of '$REMOTE' replaces its refs/kit/base deliberately, then: sh scripts/kit-update.sh --publish-base" >&2
  echo "  To take the remote's chain VERIFIED: set yours aside (a human step: git branch -m kit-base kit-base-mine), then re-run kit-update --from — it imports through verify_chain_commit." >&2
  return 1
}

# kbs_soft_fail <why> — the import FAILED CLOSED (nothing written). With a valid LOCAL base the RUN does not: say so loudly and
# continue on the local base, exactly as before this import existed (rc unchanged). With NO local base there is nothing to
# continue on: the run ends, rc 1.
kbs_soft_fail() {
  have_base || exit 1
  echo "kit-update: WARNING — kit-base was NOT imported from '$REMOTE': $1 Nothing was written. Continuing on your LOCAL base, exactly as before the import existed (the result below is against YOUR base, not the remote's)." >&2
  return 0
}

# kbs_tag_cmds <chain root> — $TMP/sb.tagcmds = `create refs/tags/kit-base/<t> <commit>` for each of the REMOTE's kit-base/*
# tags that points at an IMPORTED commit, passes adv_tag_is_ours, is a valid ref name, and does not exist locally (an
# existing tag is never touched). Sets KBS_TAGN.
kbs_tag_cmds() {
  : > "$TMP/sb.tagcmds"; KBS_TAGN=0; KBS_TAGS=''
  # (a glob refspec cannot be fetched with no destination, so the names + shas come from the ls-remote read: an annotated
  # tag's peeled `^{}` line wins. A raced or lying sha cannot matter — a tag is created only when its sha is an IMPORTED,
  # already-verified commit.)
  awk '$2 ~ /^refs\/tags\/kit-base\// { n = $2; sub(/^refs\/tags\/kit-base\//, "", n)
         if (n ~ /\^\{\}$/) { sub(/\^\{\}$/, "", n); p[n] = $1 } else s[n] = $1 }
       END { for (k in s) print (k in p ? p[k] : s[k]), k }' "$TMP/sb.ls" > "$TMP/sb.tags"
  while read -r _tc_sha _tc_name; do
    [ -n "$_tc_name" ] || continue
    _tc_c=$(_ku_git -C "$REPO" rev-parse --verify --quiet "$_tc_sha^{commit}") || continue
    grep -qxF -- "$_tc_c" "$TMP/sb.imp" || continue
    git check-ref-format "refs/tags/kit-base/$_tc_name" >/dev/null 2>&1 || continue
    adv_tag_is_ours "$_tc_name" "$_tc_c" "$1" || continue
    ! _ku_git -C "$REPO" rev-parse --verify --quiet "refs/tags/kit-base/$_tc_name" >/dev/null 2>&1 || continue
    printf 'create refs/tags/kit-base/%s %s\n' "$_tc_name" "$_tc_c" >> "$TMP/sb.tagcmds"
    KBS_TAGN=$((KBS_TAGN + 1)); KBS_TAGS="$KBS_TAGS kit-base/$_tc_name"
  done < "$TMP/sb.tags"
}

# kbs_verify_all — verify every commit in $TMP/sb.imp, oldest first: verify_chain_commit, the `behind`/`Kit-Behind` record
# (read_behind's strict rules, against the chain as it will be after the import: a corrupt one dies), and MONOTONICITY (each
# Kit-Source equals or is an ancestor, in --from, of its child's). Runs in a subshell; any failure exits 1 there.
kbs_verify_all() {
  kbs_anchors
  echo "kit-base: verifying $_sb_n chain commit(s) from '$REMOTE' against '$FROM' (two exports each)"
  _sb_root=1; [ -z "$KBS_L" ] || _sb_root=0
  _sb_prev=''; [ -z "$KBS_L" ] || _sb_prev=$(commit_source "$KBS_L")
  while IFS= read -r _sb_c; do
    verify_chain_commit "$_sb_c" "$_sb_root"; _sb_root=0
    read_behind "$_sb_c" "$TMP/rb.imp"
    _sb_cs=$(commit_source "$_sb_c")
    if [ -n "$_sb_prev" ] && [ "$_sb_prev" != "$_sb_cs" ] && ! git -C "$TMP/new" merge-base --is-ancestor "$_sb_prev" "$_sb_cs" 2>/dev/null; then
      kbs_refuse "$_sb_c" "has a Kit-Source ($(short12 "$_sb_cs")) that is not newer than its parent's ($(short12 "$_sb_prev")) — a chain runs oldest to newest"
    fi
    _sb_prev=$_sb_cs
  done < "$TMP/sb.imp"
}

# sync_base — see the block comment. Sets REMOTE_BASE_STATE (unknown | absent | present), which feeds the tail notice.
# Needs the --from clone ($TMP/new) and the workbench helpers, so it runs from the --from / --advance-base entry below.
REMOTE_BASE_STATE=unknown
sync_base() {
  if ! _ku_git -C "$REPO" config --get "remote.$REMOTE.url" >/dev/null 2>&1; then
    echo "kit-base: no remote '$REMOTE' — using the local base only"; return 0
  fi
  if ! ku_net ls-remote "$REMOTE" refs/kit/base 'refs/tags/kit-base/*' >"$TMP/sb.ls" 2>"$TMP/sb.err"; then
    echo "kit-base: could not reach '$REMOTE' to look for a shared base — using the local base only"
    sed -n '1,3p' "$TMP/sb.err" | strip_ctl | sed 's/^/    /'
    return 0
  fi
  if ! awk '$2 == "refs/kit/base" { f = 1 } END { exit !f }' "$TMP/sb.ls"; then
    REMOTE_BASE_STATE=absent; echo "kit-base: '$REMOTE' has no refs/kit/base"; return 0
  fi
  REMOTE_BASE_STATE=present
  # FETCH into a temporary NON-branch ref in the adopter repo (refs/kit-import/base), fsck'd, read once, deleted at once — the
  # chosen route (L2) over a fetch into the throwaway workbench because the adopter's own remote config, url rewrites and
  # credentials apply only to a fetch made by the adopter repo; the objects stay unreferenced until verification has passed.
  # The sha is the one FETCHED, never the ls-remote one (the two reads could race); FETCH_HEAD is not read.
  # `--refmap=` (K2): the remote's configured `fetch` refspecs must not also map the fetched ref anywhere else. The temporary ref
  # is deleted by the EXIT/INT/TERM trap too (K3) — KBS_IMPORT_REF is set just before the fetch.
  _sb_tmp=refs/kit-import/base
  KBS_IMPORT_REF=1
  if ! ku_net -c fetch.fsckObjects=true -c transfer.fsckObjects=true fetch --refmap= --no-tags -q "$REMOTE" "+refs/kit/base:$_sb_tmp" >"$TMP/sb.out" 2>&1; then
    _ku_git -C "$REPO" update-ref -d "$_sb_tmp" >/dev/null 2>&1 || :
    echo "kit-base: could not fetch refs/kit/base from '$REMOTE' — using the local base only"
    sed -n '1,3p' "$TMP/sb.out" | strip_ctl | sed 's/^/    /'
    return 0
  fi
  KBS_R=$(_ku_git -C "$REPO" rev-parse --verify --quiet "$_sb_tmp^{commit}") || KBS_R=''
  _ku_git -C "$REPO" update-ref -d "$_sb_tmp" >/dev/null 2>&1 || :
  KBS_IMPORT_REF=''
  if [ -z "$KBS_R" ]; then
    echo "kit-update: kit-base import REFUSED — '$REMOTE''s refs/kit/base is not a commit. Nothing was written." >&2
    kbs_soft_fail "its refs/kit/base is not a commit."; return 0
  fi
  KBS_L=$(_ku_git -C "$REPO" rev-parse --verify --quiet 'refs/heads/kit-base^{commit}') || KBS_L=''
  _sb_max=$((KBS_MAX_IMPORT + 1))
  _ku_git -C "$REPO" rev-list --first-parent -n "$_sb_max" "$KBS_R" > "$TMP/sb.fpR"
  if [ -n "$KBS_L" ]; then
    _ku_git -C "$REPO" rev-list --first-parent -n "$_sb_max" "$KBS_L" > "$TMP/sb.fpL"
    if grep -qxF -- "$KBS_R" "$TMP/sb.fpL"; then
      echo "kit-base: matches '$REMOTE' (refs/kit/base is $(short12 "$KBS_R") or behind your tip) — nothing to import"; return 0
    fi
    if ! grep -qxF -- "$KBS_L" "$TMP/sb.fpR"; then
      kbs_diverged || :
      kbs_soft_fail "the base is diverged."; return 0
    fi
    awk -v l="$KBS_L" '$0 == l { exit } { print }' "$TMP/sb.fpR" > "$TMP/sb.new"
  else
    cp "$TMP/sb.fpR" "$TMP/sb.new"
  fi
  if [ "$(n "$TMP/sb.new")" -gt "$KBS_MAX_IMPORT" ]; then
    echo "kit-update: kit-base import REFUSED — '$REMOTE''s refs/kit/base is more than $KBS_MAX_IMPORT chain commits long (a real chain is a handful). Nothing was written." >&2
    kbs_soft_fail "the remote chain is implausibly long."; return 0
  fi
  awk '{ a[NR] = $0 } END { for (i = NR; i >= 1; i--) print a[i] }' "$TMP/sb.new" > "$TMP/sb.imp"
  _sb_n=$(n "$TMP/sb.imp")
  # verification runs in a SUBSHELL: a refusal (kbs_refuse exits 1) ends it, not the run; the caller decides (M1).
  if ! ( kbs_verify_all ); then
    kbs_soft_fail "the chain failed verification (above)."; return 0
  fi
  kbs_tag_cmds "$(_ku_git -C "$REPO" rev-list --first-parent "$KBS_R" | tail -n 1)"
  for _eg in GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES; do
    eval "_egv=\${$_eg:-}"
    [ -z "$_egv" ] || die "the kit-base import refuses with $_eg set in the environment: an ambient git locator would redirect the ref write to a repo other than the one --repo names (CP-11). Unset it and re-run. (Nothing was written.)"
  done
  { if [ -z "$KBS_L" ]; then printf 'create refs/heads/kit-base %s\n' "$KBS_R"
    else printf 'update refs/heads/kit-base %s %s\n' "$KBS_R" "$KBS_L"; fi
    cat "$TMP/sb.tagcmds"
  } | _ku_git -C "$REPO" update-ref -m "kit-update: import kit-base from '$REMOTE'" --stdin \
    || die "could not move kit-base in one transaction (it moved under this run, or a tag appeared). No ref was moved (the fetched objects may exist, unreferenced); re-run."
  _sb_undo="git update-ref -d refs/heads/kit-base"; _sb_how=create-only
  if [ -n "$KBS_L" ]; then _sb_undo="git update-ref refs/heads/kit-base $KBS_L"; _sb_how=compare-and-swap; fi
  for _sb_t in $KBS_TAGS; do _sb_undo="$_sb_undo && git tag -d '$_sb_t'"; done
  echo "kit-base: imported $_sb_n chain commit(s) from '$REMOTE' (refs/kit/base), each verified against '$FROM' — kit-base is now $(short12 "$KBS_R")."
  echo "  wrote:        refs/heads/kit-base ($_sb_how) and $KBS_TAGN create-only tag(s), plus the fetched objects and FETCH_HEAD. Nothing else."
  echo "  undo (local): $_sb_undo   (a HUMAN step: the agent guard denies raw ref writes to kit-base)"
  echo ""
}

# publish_base — `--publish-base`: push the base this clone HAS, the same one atomic never-forced push the advance does.
publish_base() {
  have_base || die "no 'kit-base' branch in $REPO — there is nothing to publish. See docs/operations/kit-base.md."
  git -C "$REPO" config --get "remote.$REMOTE.url" >/dev/null 2>&1 \
    || die "no remote '$REMOTE' in this repo — nothing to publish to. Add one (git remote add $REMOTE <url>), or name another with --remote <name>."
  echo "kit-update: --publish-base — publishing kit-base to '$REMOTE' (one atomic, never-forced push of refs/kit/base + the chain's own tags)"
  advance_publish
  exit "$PUBLISH_RC"
}

# ══ JOB 1 — --reconstruct-base: just BASE, for inspection and for conformance/kit-update-identity.sh ══
if [ -n "$OUT" ]; then
  # The output dir must be empty AND outside any git repo: incept's CP-4 ownership gate refuses to run
  # nested (rightly), and a dir inside the adopter's tree would be a mutation.
  if [ -e "$OUT" ] && [ -n "$(ls -A "$OUT" 2>/dev/null)" ]; then
    die "--reconstruct-base '$OUT' exists and is not empty — refusing to clobber."
  fi
  mkdir -p "$OUT" || die "could not create '$OUT'"
  OUT=$( CDPATH='' cd "$OUT" && pwd -P )
  case "$OUT/" in
    "$REPO"/*) die "--reconstruct-base '$OUT' is INSIDE the adopter repo. The reconstruction must never be written into your tree — choose a path outside it." ;;
  esac
  if _owner=$( CDPATH='' cd "$OUT" && git rev-parse --show-toplevel 2>/dev/null ); then
    [ -n "$_owner" ] && die "--reconstruct-base '$OUT' is inside the git repo at '$_owner'. incept refuses to run nested (it would install its hook into that repo). Choose a path outside any repo."
  fi
  build_base "$OUT"
  echo "reconstructed BASE at: $OUT"
  if [ -n "$INFERRED" ]; then
    echo "  incept_old(kit-base) with the stamps this project recorded — EXCEPT the inferred value(s) noted above:"
  else
    echo "  incept_old(kit-base) with the stamps this project recorded (every input is a FACT, nothing inferred):"
  fi
  stamps_line
  _rcb_n=$(git -C "$REPO" log -1 --format=%B refs/heads/kit-base | grep -c '^behind' || :)
  if [ "${_rcb_n:-0}" -gt 0 ]; then
    echo "  NOTE: the kit-base tip records $_rcb_n path(s) BEHIND (a partly taken release). This is incept(tip) ONLY — NOT the"
    echo "  effective base '--from' uses (each behind path comes from the chain commit its record names); those paths"
    echo "  differ here by design, so the identity above does not hold for them."
  fi
  echo "  For an unmodified adopter this tree is IDENTICAL to HEAD — that identity is the proof the"
  echo "  reconstruction is right (conformance/kit-update-identity.sh). Your repo was not touched."
  exit 0
fi

# ══ JOB 2 — --from: THE UPDATE. BASE + OURS + THEIRS, a 3-way merge, and a report. ═══════════════════

# ── THE STALE-BASE GATE — before THEIRS is built or any of its code is run (the --from clone and the verified import of a
#    published base have already happened at the entry below; nothing of --from's has been executed yet) ──────────────────
# The base must be the release HEAD TOOK. HEAD:.kit-source RECORDS the vendor commit HEAD took (an update's
# own patch carries it); the kit-base tip's Kit-Source trailer RECORDS what the base is. If they differ the
# base is STALE: every file the last update applied would read "changed BOTH", and its newer upstream content
# would never be offered — a WRONG delta, worse than none. So refuse, and print the one command that fixes it.
# A LEGACY tree (no HEAD:.kit-source) has no record to compare; it gets a NOTICE later, when the numbers show
# the symptom (STALE_LEGACY).
STALE_LEGACY=0
TIP_SRC=''   # the vendor commit the kit-base tip records ('' = a legacy base commit); set at the entry below, AFTER sync_base
stale_base_gate() {
  _sg_rc=0; head_kit_source || _sg_rc=$?
  case "$_sg_rc" in
    1) STALE_LEGACY=1; return 0 ;;
    2) die "HEAD:.kit-source is malformed (it must be exactly two lines: 'commit <40 lowercase hex>' and 'version <VER>'). REFUSING to guess which release this tree took — restore the file from the update that wrote it." ;;
  esac
  [ "$KS_SHA" != "$TIP_SRC" ] || return 0
  echo "kit-update: STALE BASE — refusing to compute a delta against a base that is not the release you took." >&2
  _sg_tip='nothing (a pre-chain base)'; [ -z "$TIP_SRC" ] || _sg_tip=$(short12 "$TIP_SRC")
  echo "  HEAD records vendor commit $(short12 "$KS_SHA") (HEAD:.kit-source); the kit-base tip records $_sg_tip." >&2
  echo "  A stale base yields a WRONG delta (files you already took read as CONFLICT; their newer content is" >&2
  echo "  never offered) — worse than no delta, because you would trust it." >&2
  if _sg_ex=$(chain_commit_for "$KS_SHA"); then
    echo "  The base is AHEAD of HEAD: chain commit $(short12 "$_sg_ex") already records $(short12 "$KS_SHA"), but it is not the tip." >&2
    echo "  Something moved kit-base past what HEAD took — inspect 'git log kit-base' and 'git reflog kit-base' before going on." >&2
  else
    echo "  Record the release HEAD took — THE AGENT runs this (mechanical; no human keystroke), once the update's PR has" >&2
    echo "  merged and been pulled (it writes only refs/heads/kit-base, plus one tag when the release is fully taken, and" >&2
    echo "  publishes them), then re-run:" >&2
    echo "    sh scripts/kit-update.sh --advance-base --from '$FROM'" >&2
    echo "  (--from must hold the vendor history that contains $(short12 "$KS_SHA"); see docs/operations/kit-base.md.)" >&2
  fi
  exit 1
}

TMP=$(mktemp -d) || die "mktemp failed"
KBS_IMPORT_REF=''
# K3: also drop the temporary refs/kit-import/base a killed import could leave behind (set only around that fetch).
kbs_cleanup() { if [ -n "$KBS_IMPORT_REF" ]; then _ku_git -C "$REPO" update-ref -d refs/kit-import/base >/dev/null 2>&1 || :; fi; }
# shellcheck disable=SC2064  # expand TMP now: at trap time it is exactly this run's dir
trap "rm -rf '$TMP' 2>/dev/null || true; kbs_cleanup" EXIT INT TERM

# ── THE WORKBENCH — a THROWAWAY repo. Every object we create lands HERE, never in the adopter's repo. ─
# OURS is FETCHED (read-only on their side), so it is their EXACT HEAD tree — not a re-hash. BASE and
# THEIRS are directories, so they are hashed by the same route the identity proof uses (git init + add -A
# in the dir itself, so the same .gitignore applies), then fetched in. Both jobs that compare trees (--from,
# and --advance-base's per-path provenance) use it, so its helpers sit here, above the job dispatch.
W="$TMP/w"
ensure_workbench() {
  [ -d "$W/.git" ] || git -c init.defaultBranch=main init -q "$W" >/dev/null 2>&1 || die "could not create the temp workbench"
}
fetch_commit() {  # <src-repo-or-dir> -> commit oid in the workbench
  git -C "$W" fetch --no-tags -q "$1" HEAD >/dev/null 2>&1 || return 1
  git -C "$W" rev-parse FETCH_HEAD
}
commit_dir() {  # <dir> -> commit oid in the workbench (the dir is git-init'd IN PLACE; it is our temp dir)
  ( cd "$1" && git -c init.defaultBranch=main init -q . && git add -A \
      && git -c user.email=kit-update@local -c user.name=kit-update commit -qm snapshot ) >/dev/null 2>&1 \
    || return 1
  fetch_commit "$1"
}
# names_diff <commit-a> <commit-b> -> the paths whose content differs, sorted. All in ADOPTER COORDINATES, which is
# the whole point of the reconstruction. Paths are listed UNQUOTED (core.quotepath=false) so a name survives into
# a pathspec.
names_diff() {
  git -C "$W" -c core.quotepath=false diff --name-only "$1" "$2" | LC_ALL=C sort
}
# strip_ctl — control characters (ESC, CR, ...) out of anything we print that came from a path or a commit
# subject: a hostile name must not rewrite your terminal. Keeps tab and newline.
strip_ctl() { tr -d '\000-\010\013-\037\177'; }

# ══ JOB 3 — --advance-base: the ONE writer (same preconditions as above: kit-base + stamps). It is the FIX
# for a stale base, so it must not sit behind the stale-base gate. ═════════════════════════════════════
# ══ --publish-base (KIT-BASE-SHARED): push the base this clone HAS. No --from, no clone, no stamps. ═════════
[ -z "$PUBLISH" ] || publish_base

# ══ THE ENTRY for --from and --advance-base (KIT-BASE-SHARED) ═════════════════════════════════════════════
# One order, so a base a teammate published is received BEFORE anything needs it, and VERIFIED against the source this
# run already trusts: warn -> clone --from ONCE -> sync_base -> the "no kit-base" refusal (only when the sync found
# nothing) -> the stale-base gate / the advance. --from is untrusted input whose code this tool EXECUTES: the warning is
# printed BEFORE the clone, naming the source, while they can still stop.
if [ -n "$ADVANCE" ]; then
  warn_untrusted "--advance-base --from '$FROM'" \
    "Recording the base means running THAT commit's OWN scripts/adopter-export.sh (it is checked out in a temp clone)"
  _clone_why="It must be a git repository (a URL or a local path) holding the vendor history that contains the release HEAD took."
else
  warn_untrusted "--from '$FROM'" "Building THEIRS means running the new release's OWN scripts/adopter-export.sh and scripts/incept.sh"
  _clone_why="It must be a git repository (a URL or a local path) with a committed HEAD: THEIRS is built by running THAT release's own adopter-export.sh, which archives HEAD."
fi
git clone --quiet --no-tags -- "$FROM" "$TMP/new" >/dev/null 2>&1 \
  || die "could not clone --from '$FROM'. $_clone_why"
sync_base
have_base || refuse_no_base
TIP_SRC=$(commit_source refs/heads/kit-base)

if [ -n "$ADVANCE" ]; then
  advance_base
  exit "$PUBLISH_RC"
fi

stale_base_gate

[ -f "$TMP/new/scripts/adopter-export.sh" ] && [ -f "$TMP/new/scripts/incept.sh" ] \
  || die "'$FROM' has no scripts/adopter-export.sh + scripts/incept.sh — it is not a Sparkwright kit. Refusing to diff your project against something that is not the kit it was adopted from."

NEWVER=$(cat "$TMP/new/VERSION" 2>/dev/null || echo unknown)
BASEVER=$(git -C "$REPO" show kit-base:VERSION 2>/dev/null || echo unknown)
NEWSHA=$(git -C "$TMP/new" rev-parse HEAD 2>/dev/null) || die "could not read the HEAD of --from."

# ── THE THREE SIDES ───────────────────────────────────────────────────────────────────────────────────
mkdir -p "$TMP/base"
build_effective_base "$TMP/base"

# THEIRS — the NEW RELEASE'S OWN exporter + incept, with the SAME stamps and the SAME pinned date as BASE.
# Never a re-implementation of either. The ONE thing we must not guess is the SHAPE. THEIRS must be pruned
# to the SAME shape the adopter actually received — which their .kit-manifest RECORDS — NOT blindly to
# $STACK (export_at_shape, above, reads that fact and matches it).
export_at_shape "$TMP/new" "$TMP/theirs" "the new release"
# The RAW (pre-incept) export's file list, kept for the vendor-commit grouping: which adopter paths exist in
# the raw export at the SAME path (mapped directly) and which are incept-DERIVED (attributed by lines).
( cd "$TMP/theirs" && find . -type f | sed 's#^\./##' | LC_ALL=C sort ) > "$TMP/rawlist"
run_incept "$TMP/theirs" 'the new release'

# (the workbench helpers — W, fetch_commit, commit_dir — are defined above the job dispatch)
ensure_workbench

C_BASE=$(commit_dir "$TMP/base")   || die "could not snapshot the reconstructed BASE"
C_THEIRS=$(commit_dir "$TMP/theirs") || die "could not snapshot THEIRS"
C_OURS=$(fetch_commit "$REPO")     || die "could not read your HEAD (read-only) into the workbench"

# ── NON-VACUITY, ENFORCED IN THE TOOL ITSELF ──────────────────────────────────────────────────────────
# An updater that computed NOTHING reports "0 changes" — which reads exactly like a happy no-op. So an
# empty side is a HARD FAILURE here, and the three counts are PRINTED: a run that built nothing cannot
# show its work.
n_entries() { git -C "$W" ls-tree -r --name-only "$1" | grep -c . || :; }
N_BASE=$(n_entries "$C_BASE"); N_OURS=$(n_entries "$C_OURS"); N_THEIRS=$(n_entries "$C_THEIRS")
for _pair in "BASE:$N_BASE" "OURS:$N_OURS" "THEIRS:$N_THEIRS"; do
  case "$_pair" in
    *:0|*:) die "the ${_pair%%:*} tree came out EMPTY. That is a broken computation, not an empty update — and it would have printed as '0 changes', which you would have believed. Refusing." ;;
  esac
done

# ── THE MERGE — TWO implementations behind ONE contract ───────────────────────────────────────────────
# The CONTRACT (all either implementation owes the rest of this script):
#   in:  <base> <ours> <theirs> commits, in the throwaway workbench $W
#   out: $MERGED_TREE = the merged TREE oid   ·   $TMP/conflicts = the paths git could not auto-merge
#   and, above all: NOTHING of the adopter's is written. Ever. By either path.
#
# Why two: `git merge-tree --write-tree` is the RIGHT tool — it computes the merged tree in the object
# store with NO worktree and NO checkout, so the adopter's tree cannot be touched even by accident. But it
# landed in git 2.38 (2022-10-02), and Ubuntu 20.04 still ships git 2.25. scripts/preflight.sh WARNS those
# adopters and PROMISES them "the temporary-worktree fallback", "still non-mutating". merge3_worktree() is
# that promise, kept: a real, complete second implementation, on plumbing every git has had for a decade.
wgit() { git -C "$W" -c user.email=kit-update@local -c user.name=kit-update "$@"; }

# IMPLEMENTATION 1 — merge-tree (preferred). rc 0 = clean, 1 = conflicts, >1 = error. stdout: line 1 = the
# merged tree oid; then (with --name-only) the conflicted paths, a blank line, then messages.
merge3_merge_tree() {  # <base> <ours> <theirs>
  _rc=0   # RESET, deliberately: merge3() may call this and then the fallback, and a stale _rc from a
          # previous call would be read as this call's result.
  _mt=$(git -C "$W" merge-tree --write-tree --name-only --merge-base="$1" "$2" "$3") || _rc=$?
  [ "$_rc" -le 1 ] || { echo "$_mt" | sed 's/^/    /' >&2; return 1; }
  MERGED_TREE=$(echo "$_mt" | sed -n '1p')
  echo "$_mt" | sed -n '2,/^$/p' | grep -v '^$' > "$TMP/conflicts" || :
  [ -n "$MERGED_TREE" ]
}

# IMPLEMENTATION 2 — the git<2.38 fallback: the SAME 3-way, performed by plain `git merge` in a TEMPORARY
# worktree of the THROWAWAY WORKBENCH. Read that twice: the worktree it checks out and the merge commit it
# writes are the WORKBENCH's ($TMP, deleted on exit) — never the adopter's. The adopter's repo is not even
# reachable from here: $W was populated by a read-only `git fetch` long before this runs. That is what
# makes "the fallback is still non-mutating" TRUE and not just reassuring.
#
# THE GRAFT — the one thing that is not obvious. BASE, OURS and THEIRS were fetched from three UNRELATED
# repos, so they share NO history: a plain `git merge` of them does not do the wrong 3-way, it refuses
# outright ("fatal: refusing to merge unrelated histories"). So we give OURS and THEIRS a COMMON PARENT
# whose tree IS BASE. Then git's own merge-base computation lands on exactly the base we mean, and the
# merge it performs IS the 3-way we asked for — same three trees, same three-way, no invention. (We do NOT
# reach for --allow-unrelated-histories: that would merge with an EMPTY base and report every kit file as
# a conflict — a wrong answer, delivered confidently.)
merge3_worktree() {  # <base> <ours> <theirs>
  _tb=$(wgit rev-parse "$1^{tree}")   || return 1
  _to=$(wgit rev-parse "$2^{tree}")   || return 1
  _tt=$(wgit rev-parse "$3^{tree}")   || return 1
  _gb=$(wgit commit-tree "$_tb" -m 'kit-update: BASE (graft)')       || return 1
  _go=$(wgit commit-tree "$_to" -p "$_gb" -m 'kit-update: OURS')     || return 1
  _gt=$(wgit commit-tree "$_tt" -p "$_gb" -m 'kit-update: THEIRS')   || return 1

  # Give the workbench a BORN HEAD and make the grafts REACHABLE before checking anything out. Both are
  # belt-and-braces for the platform this fallback exists for and that CI cannot run (git 2.25): a repo
  # whose HEAD is unborn is the kind of edge an old `git worktree add` can refuse, and dangling
  # commit-tree objects are exactly what a stray `gc --auto` is entitled to prune. One ref costs nothing
  # and removes both questions. (The ref is the WORKBENCH's, in $TMP — not the adopter's.)
  wgit update-ref refs/heads/main "$_go" || return 1

  _wd="$TMP/mergewt"
  wgit worktree add --detach "$_wd" "$_go" >"$TMP/wt.log" 2>&1 \
    || { sed 's/^/    /' "$TMP/wt.log" >&2 || :; return 1; }

  _rc=0
  git -C "$_wd" -c user.email=kit-update@local -c user.name=kit-update \
      merge --no-edit "$_gt" >"$TMP/merge.log" 2>&1 || _rc=$?
  [ "$_rc" -le 1 ] || { sed 's/^/    /' "$TMP/merge.log" >&2 || :; return 1; }

  if [ "$_rc" -eq 1 ]; then
    # CONFLICTS. The unmerged index stages name them; the worktree files carry the markers. `git add -A`
    # then stages exactly that content, so `write-tree` yields a tree with the conflict markers IN it —
    # which is what merge-tree --write-tree produces too, and what the contract above promises.
    git -C "$_wd" -c core.quotepath=false ls-files -u | cut -f2- | LC_ALL=C sort -u > "$TMP/conflicts"
    # rc 1 with NO unmerged path is not a conflict — it is `git merge` failing for some other reason. Do
    # not read it as "merged cleanly, no conflicts": that would be a fabricated clean answer.
    [ -s "$TMP/conflicts" ] || { sed 's/^/    /' "$TMP/merge.log" >&2 || :; return 1; }
    git -C "$_wd" add -A >/dev/null 2>&1 || return 1
    MERGED_TREE=$(git -C "$_wd" write-tree) || return 1
  else
    : > "$TMP/conflicts"
    MERGED_TREE=$(git -C "$_wd" rev-parse 'HEAD^{tree}') || return 1
  fi
  [ -n "$MERGED_TREE" ]
}

# THE PROBE — a CAPABILITY probe, never a version-string parse. preflight reports a git VERSION because a
# version is all it can see at prereq time, and its own honest ceiling says so: a backport, a distro patch,
# a wrapper or a stripped build can make version and capability disagree in BOTH directions. Here we can do
# better than a version, so we must: RUN the exact subcommand with the exact flags, on a case that is
# trivially clean (merge BASE into BASE with BASE as the base), and require a usable tree oid back. If any
# part of that is unavailable — old git, no --write-tree, no --merge-base, a wrapper that swallows it — the
# probe fails and the fallback runs. We never conclude "this git can do it" from a number.
probe_merge_tree() {  # <a commit that exists in the workbench>
  _pout=$(git -C "$W" merge-tree --write-tree --name-only --merge-base="$1" "$1" "$1" 2>/dev/null) || return 1
  _poid=$(echo "$_pout" | sed -n '1p')
  [ -n "$_poid" ] || return 1
  git -C "$W" rev-parse --verify --quiet "$_poid^{tree}" >/dev/null 2>&1
}

# THE SELECTION — and it is EMITTED (see the report): an adopter who was promised a fallback must be able
# to SEE which path actually ran. A silent selection is unfalsifiable.
MERGE_IMPL=''; MERGE_WHY=''
merge3() {  # <base> <ours> <theirs>
  case "$MERGE_MODE" in
    worktree)
      MERGE_IMPL=worktree-fallback; MERGE_WHY='forced by --merge-impl worktree'
      merge3_worktree "$@"; return $? ;;
    merge-tree)
      MERGE_IMPL=merge-tree; MERGE_WHY='forced by --merge-impl merge-tree'
      merge3_merge_tree "$@"; return $? ;;
  esac
  # auto: PROBE, then fall back ON FAILURE — including a failure AFTER a successful probe. The fallback is
  # a complete implementation, not a degraded one, so an answer computed the other way beats no answer.
  if probe_merge_tree "$1"; then
    MERGE_IMPL=merge-tree; MERGE_WHY="probed: this git CAN do 'git merge-tree --write-tree'"
    merge3_merge_tree "$@" && return 0
    echo "kit-update: 'git merge-tree --write-tree' probed OK but FAILED on the real merge — falling back" >&2
    echo "  to the temporary-worktree implementation (the same 3-way, also non-mutating)." >&2
    MERGE_WHY="probed OK but FAILED on the real merge — fell back"
  else
    MERGE_WHY="probed: this git CANNOT do 'git merge-tree --write-tree' (it landed in git 2.38)"
  fi
  MERGE_IMPL=worktree-fallback
  merge3_worktree "$@"
}

: > "$TMP/conflicts"
merge3 "$C_BASE" "$C_OURS" "$C_THEIRS" \
  || die "the 3-way merge itself failed ($MERGE_IMPL). No delta is reported: a partial answer here would be worse than none."

# NON-VACUITY, ON THE MERGE ITSELF. Everything downstream (offered/CONFLICT/untouched) is derived from the
# BASE/OURS/THEIRS diffs — so a merge that silently produced NOTHING would still print a complete, plausible
# report, and the merge would be decoration. It is not allowed to be: the merged tree must EXIST, resolve,
# and be non-empty, and its size + the count of paths git could not auto-merge are PRINTED. A merge that
# never happened cannot show them.
git -C "$W" rev-parse --verify --quiet "$MERGED_TREE^{tree}" >/dev/null 2>&1 \
  || die "the $MERGE_IMPL merge returned '$MERGED_TREE', which is not a tree. Refusing to print a report whose merge did not happen."
N_MERGED=$(git -C "$W" ls-tree -r --name-only "$MERGED_TREE" | grep -c . || :)
[ "${N_MERGED:-0}" -gt 0 ] \
  || die "the $MERGE_IMPL merge produced an EMPTY tree. That is a broken computation, not a clean merge."
N_TCONF=$(grep -c . < "$TMP/conflicts" || :)

case "$MERGE_IMPL" in
  merge-tree) MERGE_DESC="'git merge-tree --write-tree' — the merged tree is computed in the object store, with NO checkout anywhere (git >= 2.38)" ;;
  *)          MERGE_DESC="plain 'git merge' in a TEMPORARY worktree of the throwaway workbench (works on ANY git — the fallback for git < 2.38). Still nothing of YOURS is touched: that worktree is the workbench's, not your repo's" ;;
esac

# ── THE CATEGORIES — by what each file IS, against the CHAIN of releases you took ─────────────────────────
# upstream = what the kit changed since the base TIP;  mine = what I changed since the base TIP;  differ =
# where my file is not the new release's. All in ADOPTER COORDINATES, which is the whole point of the
# reconstruction (names_diff, above, lists paths UNQUOTED so a name survives into a pathspec). BASE here is
# the EFFECTIVE base of the tip: a path the tip records BEHIND already carries the blob of the chain commit it names.
names_diff "$C_BASE" "$C_THEIRS" > "$TMP/upstream"
names_diff "$C_BASE" "$C_OURS"   > "$TMP/mine"
names_diff "$C_OURS" "$C_THEIRS" > "$TMP/differ"
LC_ALL=C sort "$TMP/conflicts" -o "$TMP/conflicts"

# PRISTINE = my content equals the incepted blob at SOME release in the kit-base chain (not only the latest:
# a file taken at an older release, or a hunk I declined, is still the KIT's content and still offerable).
# Only the paths that DIFFER from THEIRS can be offered, so only those are tested. The tip is free (it is
# BASE, already built: pristine there <=> not in `mine`); each OLDER chain commit is the real incept of that
# commit, built LAZILY and ONLY while some differing path is still undecided. `_KU_CHAIN_WALK=tip` (the A10
# mutant) stops after the tip.
CHAIN_N=$(git -C "$REPO" rev-list --first-parent --count refs/heads/kit-base)
CHAIN_ROOT=$(git -C "$REPO" rev-list --first-parent refs/heads/kit-base | tail -n 1)   # the adoption export
CHAIN_BUILT=0; ROOT_EXTRA=0; C_ROOT=$C_BASE   # a chain of one: the tip IS the root
: > "$TMP/chain.log"; : > "$TMP/decided.tsv"   # decided.tsv: <path> TAB <older chain commit that decided it pristine>
chain_base_commit() {  # <older chain commit> -> CB = its incepted base, as a commit in the workbench (built ONCE: the
                       # effective base may already have incepted the same commit — see chain_dir)
  if [ -s "$TMP/cb.$1" ]; then
    CB=$(cat "$TMP/cb.$1")
  else
    chain_dir "$1"
    CB=$(commit_dir "$CD") || die "could not snapshot the older kit-base chain commit $(short12 "$1")"
    printf '%s\n' "$CB" > "$TMP/cb.$1"
  fi
  [ "$1" != "$CHAIN_ROOT" ] || C_ROOT=$CB
}
# possible_paths — the names a path could carry and STILL be pristine somewhere: present in BASE(tip), in THEIRS, or
# in the RAW tree of any chain commit (a cheap ls-tree, no incept). An ADOPTER-CREATED file is in none of them, so
# no chain base can ever equal it: it must not keep the walk (one incept each) going. Incept-derived names exist in
# the tip BASE / THEIRS, so they stay. A name only an OLDER release's incept generated (absent from the tip base,
# THEIRS and every raw chain tree) is filtered too: it then reads untouched/CONFLICT rather than offering its
# deletion — the safe direction; deliberate.
possible_paths() {
  { git -C "$W" -c core.quotepath=false ls-tree -r --name-only "$C_BASE"
    git -C "$W" -c core.quotepath=false ls-tree -r --name-only "$C_THEIRS"
    for _pp in $(git -C "$REPO" rev-list --first-parent refs/heads/kit-base); do
      git -C "$REPO" -c core.quotepath=false ls-tree -r --name-only "$_pp"
    done
  } | LC_ALL=C sort -u > "$TMP/possible"
}
pristine_chain() {
  comm -23 "$TMP/differ" "$TMP/mine" > "$TMP/pristine"    # equal to the tip's blob (absent == absent counts)
  comm -12 "$TMP/differ" "$TMP/mine" > "$TMP/undecided"
  [ "$_KU_CHAIN_WALK" = all ] || return 0
  possible_paths
  comm -12 "$TMP/undecided" "$TMP/possible" > "$TMP/undecided.f"; mv "$TMP/undecided.f" "$TMP/undecided"
  for _pc in $(git -C "$REPO" rev-list --first-parent refs/heads/kit-base | sed 1d); do
    [ -s "$TMP/undecided" ] || break
    chain_base_commit "$_pc"; CHAIN_BUILT=$((CHAIN_BUILT + 1))
    names_diff "$C_OURS" "$CB" > "$TMP/ne.chain"
    comm -23 "$TMP/undecided" "$TMP/ne.chain" > "$TMP/eq.chain"      # equal to this older release's blob
    comm -12 "$TMP/undecided" "$TMP/ne.chain" > "$TMP/undecided.next"
    mv "$TMP/undecided.next" "$TMP/undecided"
    LC_ALL=C sort -u "$TMP/pristine" "$TMP/eq.chain" -o "$TMP/pristine"
    echo "$(short12 "$_pc") $(n "$TMP/eq.chain")" >> "$TMP/chain.log"
    while IFS= read -r _dp; do [ -z "$_dp" ] || printf '%s\t%s\n' "$_dp" "$_pc" >> "$TMP/decided.tsv"; done < "$TMP/eq.chain"
  done
}
pristine_chain
# A BEHIND path HEAD still has the old content of is pristine at the chain commit its record names — the same
# "decided by an older release" fact the walk reports (the pin note, the per-path grouping range). The walk never
# sees it: the effective base already carries that blob, so the path is pristine at the tip.
seed_behind_decided() {
  [ -s "$TMP/behind.tsv" ] || return 0
  _sb_tab=$(printf '\t')
  while IFS="$_sb_tab" read -r _sb_c _sb_p; do
    [ -n "$_sb_p" ] || continue
    printf '%s\n' "$_sb_p" | comm -12 - "$TMP/pristine" | grep -q . || continue
    cut -f1 "$TMP/decided.tsv" | grep -qxF -- "$_sb_p" && continue
    printf '%s\t%s\n' "$_sb_p" "$_sb_c" >> "$TMP/decided.tsv"
  done < "$TMP/behind.tsv"
}
seed_behind_decided
# `current` needs the ADOPTION base too (what the kit's files were when you adopted): the walk may have stopped
# earlier, so build the root now if it was not reached. One more incept, only for a chain of 2+.
if [ "$CHAIN_N" -gt 1 ] && [ "$C_ROOT" = "$C_BASE" ]; then chain_base_commit "$CHAIN_ROOT"; ROOT_EXTRA=1; fi

# offered   = pristine at some release you took, and the new release differs  (it applies cleanly: OURS -> THEIRS)
cp "$TMP/pristine" "$TMP/offered"
# the rest of `differ` is NOT the kit's content at any release you took: YOURS.
comm -23 "$TMP/differ" "$TMP/pristine" > "$TMP/notpristine"
# CONFLICT  = yours AND the kit changed it since the base tip. Deliberately WIDER than git's own conflict
#             list (a subset: git auto-merges two edits to different hunks). We do NOT silently resolve the
#             adopter's edit away — a file they touched and the kit touched is THEIRS TO DECIDE, always.
comm -12 "$TMP/notpristine" "$TMP/upstream" > "$TMP/conflict"
# untouched = yours, and the kit did not change it (NAMED, so silence is never mistaken for a promise)
comm -23 "$TMP/notpristine" "$TMP/upstream" > "$TMP/untouched"
# current   = the kit changed it since you adopted (chain root -> --from, or since the tip) and you already
#             HAVE the new content (taken, or edited to equal it). Scoped to files the kit CHANGED: every other
#             file is equal too, and listing the whole tree would bury the answer.
names_diff "$C_ROOT" "$C_THEIRS" > "$TMP/sinceadopt"
LC_ALL=C sort -u "$TMP/sinceadopt" "$TMP/upstream" | comm -23 - "$TMP/differ" > "$TMP/current"

N_OFF=$(n "$TMP/offered"); N_CON=$(n "$TMP/conflict"); N_UNT=$(n "$TMP/untouched"); N_CUR=$(n "$TMP/current")

# ── THE PATCH — at a SCRATCH path, outside the repo. They apply it, with their own tools. ─────────────
PATCH=''
if [ "$N_OFF" -gt 0 ]; then
  _pd=$(mktemp -d) || die "mktemp failed"
  PATCH="$_pd/kit-update-v${NEWVER}.patch"
  # The patch is OURS->THEIRS on the offered paths: on each of them OURS is the kit's own content at some
  # release you took, so the patch applies to their working tree as-is, and it carries NOTHING that is in
  # conflict. (Where OURS == BASE this is exactly BASE->THEIRS, as before; for a file pristine at an OLDER
  # release it is the only diff that applies.)
  # `git diff` has no --pathspec-from-file, so the pathspec is built one line at a time — never by word-
  # splitting a variable, which would corrupt any path containing a space.
  diff_offered() {
    set -- --binary "$C_OURS" "$C_THEIRS" --
    while IFS= read -r _path; do
      [ -n "$_path" ] && set -- "$@" ":(literal)$_path"
    done < "$TMP/offered"
    git -C "$W" diff "$@"
  }
  diff_offered > "$PATCH" || die "could not write the patch"
fi

# ── THE REPORT ────────────────────────────────────────────────────────────────────────────────────────
# The labels carry the COMMIT: VERSION alone cannot tell two pre-release commits apart (it stays the same
# across every `main` between releases). A legacy base records no commit, and says so.
# behind_taken_note — a path the tip records BEHIND whose content in OURS now EQUALS the tip's own incepted blob was taken
# after the advance: the record is out of date by that many paths. Say so (one line); classification is not changed.
behind_taken_note() {
  [ -s "$TMP/behind.tipblob" ] || return 0
  _bt_n=0; _bt_tab=$(printf '\t')
  while IFS="$_bt_tab" read -r _bt_p _bt_b; do
    [ -n "$_bt_p" ] || continue
    _bt_o=$(git -C "$W" rev-parse --verify --quiet "$C_OURS:$_bt_p" 2>/dev/null || :)
    if [ "$_bt_b" = ABSENT ]; then
      if [ -z "$_bt_o" ]; then _bt_n=$((_bt_n + 1)); fi
    elif [ "$_bt_b" != - ] && [ "$_bt_b" = "$_bt_o" ]; then
      _bt_n=$((_bt_n + 1))
    fi
  done < "$TMP/behind.tipblob"
  if [ "$_bt_n" -gt 0 ]; then
    echo "NOTE: $_bt_n behind path(s) already equal the tip's release in your tree — run --advance-base first to record them (the classification below is unchanged)."
  fi
}
BASE_LBL='unrecorded'; [ -z "$TIP_SRC" ] || BASE_LBL=$(short12 "$TIP_SRC")
echo "kit-update: v$BASEVER@$BASE_LBL (kit-base) -> v$NEWVER@$(short12 "$NEWSHA") (--from)"
[ "$BEHIND_N" -eq 0 ] || echo "kit-base: v$BASEVER@$BASE_LBL PARTIAL — $BEHIND_N file(s) behind (listed under offered/CONFLICT)"
behind_taken_note
echo "computed: BASE=$N_BASE files, OURS=$N_OURS files, THEIRS=$N_THEIRS files"
echo "  BASE   = incept_old(kit-base), rebuilt with your recorded stamps"
stamps_line
echo "  OURS   = your HEAD, read-only"
echo "  THEIRS = incept_new(adopter-export(--from)) — that release's OWN scripts, same stamps, same pinned date"
echo "           shape: $THEIRS_SHAPE"
# WHICH MERGE RAN — said out loud. There are two implementations and the choice is made for you, at run
# time, by a capability probe; you get to see which one answered, and what it actually produced.
echo "merge: $MERGE_IMPL — $MERGE_DESC"
echo "  tree=$MERGED_TREE files=$N_MERGED textual-conflicts=$N_TCONF  (selected: $MERGE_WHY)"
# THE CHAIN, shown: how many releases kit-base records and how many older ones had to be rebuilt to decide
# "pristine" (each is a real incept, ~9 s). A tip-only walk would print 0 here.
_chain_extra=''; [ "$ROOT_EXTRA" -eq 0 ] || _chain_extra="; plus the adoption release, rebuilt for 'current'"
echo "chain: kit-base records $CHAIN_N release(s); $CHAIN_BUILT older one(s) rebuilt to decide which of your files are the kit's own$_chain_extra"
[ -s "$TMP/chain.log" ] && sed 's/^\([0-9a-f]*\) \(.*\)$/  - chain commit \1 decided \2 file(s)/' "$TMP/chain.log"
echo ""

# LEGACY STALE-BASE NOTICE. A tree with no HEAD:.kit-source cannot be CHECKED against the tip (the gate above
# has nothing to compare), but it shows the symptom: files changed on BOTH sides that already EQUAL the new
# release are files it took from some release the base does not record.
if [ "$STALE_LEGACY" -eq 1 ] && [ "$(comm -12 "$TMP/current" "$TMP/mine" | grep -c . || :)" -gt 0 ]; then
  echo "STALE-BASE? — $(comm -12 "$TMP/current" "$TMP/mine" | grep -c . || :) file(s) changed on both sides already EQUAL the release at --from, and HEAD has no .kit-source to check the base against."
  echo "  Your kit-base probably predates updates you already took, so some files may read CONFLICT or untouched"
  echo "  that are really the kit's older content. If you know the vendor commit(s) you took, record them, oldest"
  echo "  first (the sha is ASSERTED — not recorded — so be sure of it):"
  echo "    sh scripts/kit-update.sh --advance-base --from '$FROM' --at <sha of the release you took>"
  echo ""
fi

if { [ "$C_BASE" = "$C_THEIRS" ] || git -C "$W" diff --quiet "$C_BASE" "$C_THEIRS"; } && [ "$N_OFF" -eq 0 ]; then
  echo "no changes: the release at --from is identical to the one you adopted, in your coordinates."
  echo "  (BASE and THEIRS are the same $N_THEIRS-file tree — nothing to offer. This is a real no-op, not"
  echo "   an empty computation: all three trees were built, and their sizes are printed above.)"
  echo ""
fi

sect() {  # <key> <count> <caption>
  echo "== $1 ($2) — $3 =="
  [ "$2" -gt 0 ] && sed 's/^/  - /' "$TMP/$4" | strip_ctl
  echo ""
}
# offered_notes <path> <older chain commit that decided it, or ''> — the lines under an offered path that say WHY it is
# offered when that is not simply "the tip's content": pristine at an OLDER release (maybe a deliberate pin), a re-add.
offered_notes() {
  [ -n "$2" ] || return 0
  _on_src=$(commit_source "$2"); [ -n "$_on_src" ] || _on_src=$2
  echo "      (pristine at $(short12 "$_on_src") — an older release you took; check it is not a deliberate pin)"
  grep -qxF -- "$1" "$TMP/absent.ours" && echo "      (re-add — absent from your tree: you deleted it, or never took it; the patch re-creates it)"
  return 0
}
offered_section() {
  echo "== offered ($N_OFF) — the kit's own content at a release you took; the new release differs, so it applies cleanly =="
  if [ "$N_OFF" -gt 0 ]; then
    git -C "$W" -c core.quotepath=false ls-tree -r --name-only "$C_OURS" | LC_ALL=C sort > "$TMP/ours.list"
    comm -23 "$TMP/offered" "$TMP/ours.list" > "$TMP/absent.ours"
    LC_ALL=C sort -u "$TMP/decided.tsv" -o "$TMP/decided.tsv"
    _otab=$(printf '\t')
    join -t "$_otab" -a1 -e '' -o 0,2.2 "$TMP/offered" "$TMP/decided.tsv" > "$TMP/offered.dec"
    while IFS="$_otab" read -r _op _od; do
      [ -n "$_op" ] || continue
      printf '  - %s\n' "$_op" | strip_ctl
      offered_notes "$_op" "$_od" | strip_ctl
    done < "$TMP/offered.dec"
  fi
  echo ""
}
offered_section
sect current   "$N_CUR" "the kit changed these since your base and you already HAVE the new content — nothing to do" current
sect CONFLICT  "$N_CON" "changed BOTH upstream and by you — yours to decide, NEVER resolved silently" conflict
sect untouched "$N_UNT" "yours; this update proposes nothing for them" untouched

# ── GROUPED BY VENDOR CHANGE (H 66/71) — which vendor commit changed which reported path ──────────────
# Reported = offered + CONFLICT. Needs the base's Kit-Source commit in the --from clone's history; says so,
# in one line, when it cannot. A path in the RAW export maps to itself ("direct"). A path incept DERIVED
# (not in the raw export at that path — e.g. .github/workflows/ci.yml, which incept rewrites from
# profiles/<stack>/ci.yml) is ATTRIBUTED to a raw path of the commit when its changed lines (the +/- lines of
# BASE->THEIRS, context excluded) are a non-empty SUBSET of that raw path's changed lines in that commit —
# an inference, labelled as one. Everything else is "not attributable". Never a rename table.
changed_lines() { awk '/^@@/{h=1;next} h && /^[-+]/' | LC_ALL=C sort -u; }
# RANGE PER PATH (KIT-UPDATE-BASE-ADVANCES): a path is walked from the vendor commit its DECIDING chain commit
# recorded (its Kit-Source), not always from the tip's: a file pristine at an OLDER release changed upstream
# between THAT release and --from, mostly before the tip. Tip-decided and CONFLICT paths keep tip..HEAD.
reset_group_state() { : > "$TMP/g.attr"; : > "$TMP/g.touched"; : > "$TMP/g.all"; rm -rf "$TMP/g.c"; mkdir -p "$TMP/g.c"; }
group_one_commit() {  # <vendor commit> — append its lines to g.c/<commit>; record the paths it explains in g.attr
  _gc=$1
  _gp=$(git -C "$TMP/new" rev-parse -q --verify "$_gc^1" 2>/dev/null) || _gp=$(git -C "$TMP/new" hash-object -t tree /dev/null)
  git -C "$TMP/new" -c core.quotepath=false diff --name-only "$_gp" "$_gc" | LC_ALL=C sort > "$TMP/g.chg"
  comm -12 "$TMP/g.chg" "$TMP/rawlist" | comm -12 - "$GSET" > "$TMP/g.direct"
  : > "$TMP/g.blk"; _gn=0
  while IFS= read -r _gpath; do
    [ -n "$_gpath" ] || continue
    printf '      - %s (direct)\n' "$_gpath" >> "$TMP/g.blk"; printf '%s\n' "$_gpath" >> "$TMP/g.attr"; _gn=$((_gn + 1))
  done < "$TMP/g.direct"
  if [ -s "$TMP/g.derived" ] && [ -s "$TMP/g.chg" ]; then
    # the raw changed lines of every path this commit touched, numbered once
    _gj=0
    while IFS= read -r _graw; do
      _gj=$((_gj + 1))
      git -C "$TMP/new" diff -U0 "$_gp" "$_gc" -- ":(literal)$_graw" | changed_lines > "$TMP/g.rl.$_gj"
      printf '%s\n' "$_graw" > "$TMP/g.rn.$_gj"
    done < "$TMP/g.chg"
    while IFS="$(printf '\t')" read -r _gi _gpath; do
      [ -s "$TMP/g.pl.$_gi" ] || continue
      grep -Fxq -- "$_gpath" "$GSET" || continue
      _gk=1
      while [ "$_gk" -le "$_gj" ]; do
        if [ -s "$TMP/g.rl.$_gk" ] && [ -z "$(comm -23 "$TMP/g.pl.$_gi" "$TMP/g.rl.$_gk")" ]; then
          printf '      - %s (attributed by matching lines to %s)\n' "$_gpath" "$(cat "$TMP/g.rn.$_gk")" >> "$TMP/g.blk"
          printf '%s\n' "$_gpath" >> "$TMP/g.attr"; _gn=$((_gn + 1)); break
        fi
        _gk=$((_gk + 1))
      done
    done < "$TMP/g.pidx"
  fi
  [ "$_gn" -gt 0 ] || return 0
  echo "$_gc" >> "$TMP/g.touched"
  cat "$TMP/g.blk" >> "$TMP/g.c/$_gc"
}
# split the reported paths by the vendor commit their range starts at -> g.set.<start>; the rest get a reason
split_by_range() {
  LC_ALL=C sort -u "$TMP/offered" "$TMP/conflict" > "$TMP/reported"
  : > "$TMP/g.starts"; : > "$TMP/g.nosrc"; : > "$TMP/g.unreach"; : > "$TMP/g.generated"
  LC_ALL=C sort -u "$TMP/decided.tsv" -o "$TMP/decided.tsv"
  _gtab=$(printf '\t')
  join -t "$_gtab" -a1 -e '' -o 0,2.2 "$TMP/reported" "$TMP/decided.tsv" > "$TMP/g.dec"
  while IFS="$_gtab" read -r _gpath _gdec; do
    [ -n "$_gpath" ] || continue
    case "$_gpath" in .kit-manifest|.kit-digests|.kit-source) printf '%s\n' "$_gpath" >> "$TMP/g.generated"; continue ;; esac
    _gst=$TIP_SRC
    if [ -n "$_gdec" ]; then
      _gst=$(commit_source "$_gdec")
      if [ -z "$_gst" ]; then printf '%s\n' "$_gpath" >> "$TMP/g.nosrc"; continue; fi
      if ! git -C "$TMP/new" cat-file -e "$_gst^{commit}" 2>/dev/null; then printf '%s\n' "$_gpath" >> "$TMP/g.unreach"; continue; fi
    fi
    printf '%s\n' "$_gpath" >> "$TMP/g.set.$_gst"
    echo "$_gst" >> "$TMP/g.starts"
  done < "$TMP/g.dec"
  LC_ALL=C sort -u "$TMP/g.starts" -o "$TMP/g.starts"
}
# group_prepare — split the reported paths by range, and number the incept-DERIVED ones's changed lines once.
group_prepare() {
  reset_group_state
  rm -f "$TMP"/g.set.*
  split_by_range
  comm -23 "$TMP/reported" "$TMP/rawlist" > "$TMP/g.derived"
  : > "$TMP/g.pidx"; _gi=0
  while IFS= read -r _gpath; do
    [ -n "$_gpath" ] || continue
    _gi=$((_gi + 1))
    git -C "$W" -c core.quotepath=false diff -U0 "$C_BASE" "$C_THEIRS" -- ":(literal)$_gpath" | changed_lines > "$TMP/g.pl.$_gi"
    printf '%s\t%s\n' "$_gi" "$_gpath" >> "$TMP/g.pidx"
  done < "$TMP/g.derived"
}
# group_walk_starts — for each start commit: its range in --from's history, one group_one_commit per commit. Sets _grange.
group_walk_starts() {
  _grange=''
  while IFS= read -r _gst; do
    [ -n "$_gst" ] || continue
    GSET=$TMP/g.set.$_gst; LC_ALL=C sort -u "$GSET" -o "$GSET"
    git -C "$TMP/new" rev-list --first-parent --reverse "$_gst..HEAD" > "$TMP/g.walk"
    cat "$TMP/g.walk" >> "$TMP/g.all"
    if [ "$_gst" = "$TIP_SRC" ]; then _grange="$(short12 "$_gst")..$(short12 "$NEWSHA")$_grange"
    else _grange="$_grange, and $(short12 "$_gst").. for $(n "$GSET") path(s) pristine at an older release"; fi
    while IFS= read -r _gc; do group_one_commit "$_gc"; done < "$TMP/g.walk"
  done < "$TMP/g.starts"
}
# group_print_commits — one block per touched vendor commit, oldest first (subject + paths, control chars stripped).
group_print_commits() {
  [ -s "$TMP/g.touched.u" ] || return 0
  git -C "$TMP/new" rev-list --first-parent --reverse HEAD | grep -Fx -f "$TMP/g.touched.u" > "$TMP/g.order" || :
  while IFS= read -r _gc; do
    printf '  * %s %s\n' "$(printf '%s' "$_gc" | cut -c1-8)" "$(git -C "$TMP/new" log -1 --format=%s "$_gc" | strip_ctl)"
    strip_ctl < "$TMP/g.c/$_gc"
    _gn=$(grep -c '^      - ' "$TMP/g.c/$_gc" || :)
    [ "$_gn" -le 1 ] || echo "      ! land together — this one vendor commit changed $_gn reported paths; take them as one change"
  done < "$TMP/g.order"
}
# group_list <file> <caption> — a "not attributable"-style list under its caption (skipped when empty).
group_list() {
  [ -s "$1" ] || return 0
  echo "  $2 ($(n "$1")):"
  LC_ALL=C sort -u "$1" | sed 's/^/      - /' | strip_ctl
}
# group_print_rest — the paths no commit explains, each with the reason it is not attributed.
group_print_rest() {
  if [ -s "$TMP/g.generated" ]; then
    printf '  generated by the export (no commit changes them directly) (%s): %s\n' "$(n "$TMP/g.generated")" \
      "$(LC_ALL=C sort -u "$TMP/g.generated" | tr '\n' ' ' | strip_ctl)"
  fi
  group_list "$TMP/g.nosrc" "not attributable — pristine at a legacy chain commit that records no Kit-Source, so there is no starting commit"
  group_list "$TMP/g.unreach" "not attributable — the vendor commit that release recorded is not in the history of --from"
  group_list "$TMP/g.rest" "not attributable to a vendor commit — incept-owned files, or paths no one commit's lines account for"
}
grouping_section() {
  if [ -z "$TIP_SRC" ]; then
    echo "grouping by vendor change: UNAVAILABLE — the kit-base tip records no Kit-Source (a pre-chain base), so there is no 'from' commit to list changes since."
    echo ""; return 0
  fi
  if ! git -C "$TMP/new" cat-file -e "$TIP_SRC^{commit}" 2>/dev/null; then
    echo "grouping by vendor change: UNAVAILABLE — the base's vendor commit $(short12 "$TIP_SRC") is not in the history of --from (a squashed or re-rooted mirror, or a shallow clone)."
    echo ""; return 0
  fi
  group_prepare
  group_walk_starts
  LC_ALL=C sort -u "$TMP/g.all" -o "$TMP/g.all"
  LC_ALL=C sort -u "$TMP/g.touched" > "$TMP/g.touched.u"
  _gtotal=$(n "$TMP/g.all")
  LC_ALL=C sort -u "$TMP/g.attr" > "$TMP/g.attr.u"
  LC_ALL=C sort -u "$TMP/g.nosrc" "$TMP/g.unreach" "$TMP/g.generated" > "$TMP/g.excl"
  comm -23 "$TMP/reported" "$TMP/g.attr.u" | comm -23 - "$TMP/g.excl" > "$TMP/g.rest"
  echo "== grouped by vendor change ($_gtotal commit(s) walked: ${_grange#, and }) — reported = offered + CONFLICT paths =="
  group_print_commits
  _gquiet=$((_gtotal - $(n "$TMP/g.touched.u")))
  [ "$_gquiet" -le 0 ] || echo "  ($_gquiet further commit(s) changed none of the reported paths)"
  group_print_rest
  echo "  ('attributed by matching lines' is an INFERENCE from changed lines, not a record; 'direct' is the raw export path.)"
  echo ""
}
grouping_section

# ── CI WIRING (KIT-UPDATE-PROFILE-CI-DRIFT, design D7) ────────────────────────────────────────────────
# The 3-way sees the adopter's workflow like any file, but an ADAPTED one reads CONFLICT — one line among N —
# and nothing says it is the line a new CI capability depends on. This runs the NEW release's own
# `conformance/verify-enforced-wired.sh --drift` (the same function the adopter's CI leg runs, so the notice is the
# same text) on the adopter's workflow (OURS) against that release's stack profile (THEIRS), copied to scratch
# files under the real relative paths. Read-only: nothing here writes to the adopter's repo.
# Ceiling: the check is the --from release's code (already the tool's stated ceiling, below); a --from that has no
# `--drift` is said so in one line.
ci_wiring_section() {
  case "$STACK" in
    ''|*[!A-Za-z0-9_-]*) echo "CI wiring check: skipped (the stamped stack is not a plain profile name)."; echo ""; return 0 ;;
  esac
  if [ "$CI" = gitlab ]; then _cw_wf=.gitlab-ci.yml; _cw_pf=ci.gitlab-ci.yml; else _cw_wf=.github/workflows/ci.yml; _cw_pf=ci.yml; fi
  _cw_prof="profiles/$STACK/$_cw_pf"; _cw_tool=conformance/verify-enforced-wired.sh
  git -C "$W" cat-file -e "$C_OURS:$_cw_wf" 2>/dev/null || return 0      # no workflow in HEAD: nothing to compare
  git -C "$W" cat-file -e "$C_THEIRS:$_cw_prof" 2>/dev/null || return 0  # the release has no profile pipeline for it
  _cw_d="$TMP/ciw"; rm -rf "$_cw_d"; mkdir -p "$_cw_d/$(dirname "$_cw_wf")" "$_cw_d/$(dirname "$_cw_prof")" "$_cw_d/conformance"
  git -C "$W" show "$C_OURS:$_cw_wf" > "$_cw_d/$_cw_wf" 2>/dev/null || return 0
  git -C "$W" show "$C_THEIRS:$_cw_prof" > "$_cw_d/$_cw_prof" 2>/dev/null || return 0
  if ! git -C "$W" show "$C_THEIRS:$_cw_tool" > "$_cw_d/$_cw_tool" 2>/dev/null || ! grep -q -e '--drift' "$_cw_d/$_cw_tool"; then
    echo "CI wiring check: not available in the release at --from (its conformance/verify-enforced-wired.sh has no --drift)."
    echo ""; return 0
  fi
  _cw_rc=0
  _cw_out=$( cd "$_cw_d" && sh "$_cw_tool" --drift --wf="$_cw_wf" --profile="$_cw_prof" 2>&1 ) || _cw_rc=$?
  case "$_cw_rc" in
    0) return 0 ;;
    1) echo "== CI WIRING ($CI) — your workflow lacks a CI capability the release's stack profile carries =="
       if grep -qxF -- "$_cw_wf" "$TMP/offered"; then
         echo "  The offered patch on $_cw_wf adopts it (the workflow is still the kit's own content at a release you took)."
       else
         printf '%s\n' "$_cw_out" | strip_ctl
       fi
       echo "" ;;
    *) echo "CI wiring check: could not be evaluated (rc=$_cw_rc): $(printf '%s' "$_cw_out" | sed -n '1p' | strip_ctl)"
       echo "" ;;
  esac
  return 0
}
ci_wiring_section

# HOOK REFRESH — human step, not in the patch (B3, design D5). Git hooks are NOT version-controlled,
# so `hooks/pre-push` moving in offered/conflict is invisible where it matters: nothing this tool
# computes ever touches `.git/hooks/pre-push`, and a stale installed copy is exactly the fail-open
# rung guard-wired.sh's rung leg now certifies (docs/architecture/2026-08-05-b3-rung-certifier-design.md).
# Δ3 (HOOK-INSTALL-RECURS-PER-SLICE): WHICH install mode this repo runs decides whether there is a
# re-copy to nag about AT ALL. Ask git rather than assume: `git rev-parse --git-path hooks/pre-push`
# respects core.hooksPath, so when the live hook resolves inside the repo's OWN tracked hooks/ dir the
# tracked file IS the live hook — the delta computed above over hooks/pre-push IS the update, and a
# prescribed `cp` would be actively wrong (there is nothing to copy to). Every failure to resolve
# answers `installed`: the copy-mode advice is the safe default, since it is what an unset config means.
# (`_ku_git`, the env-scrubbing git wrapper this uses, is defined above the job dispatch: KIT-BASE-SHARED's
# import writes through it too.)
hook_mode() {
  _hm_top=$( _ku_git -C "$REPO" rev-parse --show-toplevel 2>/dev/null ) || { echo installed; return 0; }
  _hm_live=$( _ku_git -C "$REPO" rev-parse --git-path hooks/pre-push 2>/dev/null ) || { echo installed; return 0; }
  case "$_hm_live" in /*) : ;; *) _hm_live="$REPO/$_hm_live" ;; esac
  _hm_livedir=$( CDPATH='' cd "$( dirname "$_hm_live" )" 2>/dev/null && pwd -P ) || { echo installed; return 0; }
  _hm_wantdir=$( CDPATH='' cd "$_hm_top/hooks" 2>/dev/null && pwd -P ) || { echo installed; return 0; }
  if [ "$_hm_livedir" = "$_hm_wantdir" ]; then echo tracked; else echo installed; fi
}
HOOK_MODE=$(hook_mode)

# _hr_rung — the adopter's OWN conformance/guard-wired.sh, run once read-only, keeping its `pre-push rung` lines
# verbatim (after strip_ctl): the gate's own text, so this report and the gate cannot disagree (JIRA-ADOPTION-
# DOCS-RESIDUALS-2 / D6, cold test 2 item 101). It runs in this process; the agent's guard never sees it.
_hr_rung() {
  [ -f "$REPO/conformance/guard-wired.sh" ] \
    || { echo "hook state: not checked (conformance/guard-wired.sh absent)"; return 0; }
  # the same env scrub list _ku_git uses: an ambient GIT_DIR / GIT_CONFIG_* must not steer the gate's git reads
  _hr_out=$( cd "$REPO" && env -u GIT_DIR -u GIT_COMMON_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_CONFIG_GLOBAL \
      -u GIT_CONFIG_SYSTEM -u GIT_CONFIG_NOSYSTEM -u GIT_CONFIG -u GIT_CONFIG_COUNT -u GIT_CONFIG_PARAMETERS \
      -u GIT_CEILING_DIRECTORIES -u GIT_OBJECT_DIRECTORY -u GIT_ALTERNATE_OBJECT_DIRECTORIES -u GIT_NAMESPACE \
      sh conformance/guard-wired.sh "$REPO" 2>&1 ) || :
  _hr_lines=$( printf '%s\n' "$_hr_out" | strip_ctl | grep -F 'pre-push rung' ) || :
  [ -n "$_hr_lines" ] || { echo "hook state: not checked (conformance/guard-wired.sh printed no pre-push rung verdict)"; return 0; }
  printf '%s\n' "$_hr_lines"
}
# P1: no core.hooksPath in ANY config scope (the value is never printed). P2: no hook-manager dir at the top
# level. The same two checks brownfield.md §2 step 5 tells a human to make before typing the setting.
_hr_p1() { [ -z "$( _ku_git -C "$REPO" config --get core.hooksPath 2>/dev/null )" ]; }
# P2 also fails on a pre-commit framework config, or on any executable hook in the hooks dir other than pre-push
# and *.sample: with core.hooksPath hooks that other hook would silently go out of service.
_hr_p2() {
  for _hr_d in .husky .lefthook .githooks .pre-commit-config.yaml; do [ -e "$REPO/$_hr_d" ] && return 1; done
  _hr_hd=$( _ku_git -C "$REPO" rev-parse --git-path hooks 2>/dev/null ) || return 1
  case "$_hr_hd" in /*) : ;; *) _hr_hd="$REPO/$_hr_hd" ;; esac
  for _hr_f in "$_hr_hd"/*; do
    [ -f "$_hr_f" ] && [ -x "$_hr_f" ] || continue
    case "${_hr_f##*/}" in pre-push|*.sample) continue ;; *) return 1 ;; esac
  done
  return 0
}
# A rung with neither a PASS: nor a FAIL: line (gate absent, silent, or only an N/A) is disclosed, never silent.
_hr_note() {
  printf '%s\n' "$HR_RUNG" | grep -q '^PASS:' && return 0
  printf '%s\n' "$HR_RUNG" | grep -q '^FAIL:' && return 0
  case "$HR_RUNG" in "hook state:"*) printf '%s\n' "$HR_RUNG" ;;
    *) echo "hook state: not checked ($( printf '%s\n' "$HR_RUNG" | sed -n '1p' ))" ;; esac
}
_hr_copy_line() { echo "    cp hooks/pre-push .git/hooks/pre-push && chmod +x .git/hooks/pre-push"; }
_hr_installed_lead() {
  echo "== HOOK REFRESH — one human setting, then never again =="
  printf '%s\n' "$HR_RUNG"
  echo "  $HR_WHY"
  echo "  git config core.hooksPath hooks"
  echo "    a one-time human act: the runtime guard denies it to an agent, because it can repoint the push rung."
  echo "    Read docs/adoption/brownfield.md §2 step 5 (a) first, including its caveats."
  echo "  after it, hooks/pre-push IS the live hook — no copy exists to go stale"
  echo "  Or keep the copy (repeat this whenever hooks/pre-push moves):"
  _hr_copy_line
  echo "  sh conformance/guard-wired.sh confirms the result (present, executable, FRESH)."
}
_hr_installed_copy() {
  echo "== HOOK REFRESH — human step, not in the patch =="
  printf '%s\n' "$HR_RUNG"
  if [ -n "$HR_CHANGED" ]; then
    echo "  $HR_WHY This tool computed a delta for the TRACKED source file"
    echo "  only; it cannot refresh the INSTALLED hook at .git/hooks/ — git hooks are not version-"
  else
    echo "  $HR_WHY The INSTALLED hook at .git/hooks/ is not version-"
  fi
  echo "  controlled, and no patch this tool emits ever writes there. Refresh it yourself, the same"
  echo "  human-only way brownfield adoption does (docs/adoption/brownfield.md §2 step 5):"
  _hr_copy_line
  _hr_p1 || echo "  core.hooksPath is set (in this repo or your global config): do not repoint it — see brownfield.md §2 step 5"
  echo "  sh conformance/guard-wired.sh confirms the result (present, executable, FRESH)."
}
HR_RUNG=$(_hr_rung)
HR_WHY="the installed hook is not current (the gate line above says why)."
HR_SHOW=""; HR_CHANGED=""; HR_FAIL=""
printf '%s\n' "$HR_RUNG" | grep -q '^FAIL:' && { HR_SHOW=1; HR_FAIL=1; }
if grep -qx 'hooks/pre-push' "$TMP/offered" "$TMP/conflict" 2>/dev/null; then HR_SHOW=1; HR_CHANGED=1; HR_WHY="hooks/pre-push changed upstream."; fi

if [ -z "$HR_SHOW" ]; then
  HR_NOTE=$(_hr_note)
  [ -z "$HR_NOTE" ] || { printf '%s\n\n' "$HR_NOTE"; }
fi
if [ -n "$HR_SHOW" ]; then
  if [ "$HOOK_MODE" = tracked ]; then
    echo "== HOOK REFRESH — nothing to refresh: this repo runs TRACKED-HOOKS mode =="
    if [ -n "$HR_FAIL" ]; then printf '%s\n' "$HR_RUNG"; else _hr_note; fi
    [ -n "$HR_CHANGED" ] || HR_WHY="the live hook is not current (the gate line above says why)."
    if [ -n "$HR_CHANGED" ]; then
      echo "  $HR_WHY core.hooksPath points at this repo's own hooks/ dir, so the"
      echo "  TRACKED file IS the live hook: applying the delta above (or resolving its conflict) is the"
      echo "  whole update. There is no installed copy to keep in step, and no cp to run."
    else
      echo "  $HR_WHY core.hooksPath points at this repo's own hooks/ dir, so the"
      echo "  TRACKED file IS the live hook; the gate line above names the cure."
    fi
    echo "  sh conformance/guard-wired.sh confirms the result (live, executable, worktree matches HEAD)."
  elif _hr_p1 && _hr_p2; then
    _hr_installed_lead
  else
    _hr_installed_copy
  fi
  echo ""
fi

if [ -n "$PATCH" ]; then
  echo "patch: $PATCH"
  echo "  the OFFERED changes only. Review it, then apply it with your own tools:  git apply '$PATCH'"
else
  echo "patch: (none — nothing is offered)"
fi
echo ""

# ── THE HONEST CEILING — printed, every run, in the tool's own output ────────────────────────────────
echo "HONEST CEILING — what this tool does NOT do:"
echo "  * LATEST ONLY. --from carries whatever that source's HEAD is; the public mirror carries only the"
echo "    current release. This cannot move you to an intermediate version."
echo "  * IT PRESENTS, IT DOES NOT APPLY. Nothing above was written to your repo — not one byte. Every"
echo "    hunk is your decision, and the patch is a suggestion at a scratch path."
echo "  * IT REQUIRES AN INTACT kit-base. The whole delta is computed against incept_old(kit-base). Lose"
echo "    that branch and there is no honest base — and a wrong base is worse than none."
echo "  * kit-base IS ONLY AS GOOD AS ITS RECORD. After each update you merge, the agent runs --advance-base (the"
echo "    one job that writes: refs/heads/kit-base, plus one tag when the release is fully taken) or the next run"
echo "    refuses as STALE. It records PER PATH what HEAD took; a path HEAD did not take is recorded BEHIND and"
echo "    re-offered, never hidden. A legacy tree's --at sha is ASSERTED, not recorded: a wrong one misclassifies"
echo "    (it cannot delete — the patch is only a suggestion). --advance-base publishes kit-base to your remote's"
echo "    refs/kit/base (a non-branch ref) in one atomic, non-forced push (--no-push keeps it local; --publish-base"
echo "    pushes it on its own). A clone or teammate imports it on --from, every chain commit verified first; anyone"
echo "    with push access to the remote can write refs/kit/base, so a chain that fails verification is not imported."
echo "    --from never pushes; its one write is that verified import (printed, with its undo)."
echo "  * 'PRISTINE' MEANS EQUAL TO A RELEASE YOUR kit-base CHAIN RECORDS — not 'never edited'. A hunk you"
echo "    declined stays the kit's content, so it is OFFERED AGAIN next time; to keep a file, edit it. A file you"
echo "    edited until it equals an older release reads as the kit's, not yours. A kit file you DELETED after"
echo "    taking it is offered again too (absent == absent at an older release): to keep it gone, keep declining"
echo "    that hunk — the patch is only a suggestion, and nothing is applied unless you apply it."
echo "  * GROUPING BY VENDOR COMMIT IS PARTLY INFERENCE. 'direct' is the raw export path; 'attributed by"
echo "    matching lines' is a guess from changed lines (incept's rewrites can defeat it: one commit must"
echo "    account for ALL of a path's changed lines); 'not attributable' says so. It needs the base's vendor"
echo "    commit in --from's history, and says when it is not."
echo "  * --from IS UNTRUSTED INPUT AND THIS TOOL EXECUTES CODE FROM IT (that release's own"
echo "    adopter-export.sh and incept.sh, above). Point it only at a source you trust."
echo "  * CI WIRING IS A LINE-BASED CHECK, RUN WITH THE --from RELEASE'S OWN CODE. It names a kit-owned CI capability"
echo "    your workflow lacks; it cannot see one hidden behind a wrapper script, and it does not judge whether an"
echo "    adapted listing step is SAFE. The first update that brings this check prints no CI WIRING section (your"
echo "    installed kit-update predates it) — your CI's own verify-enforced check speaks on that update's PR instead."
echo "  * A CONFLICT is not a defect — it is the tool refusing to overwrite you. Nothing above was merged"
echo "    into your files; the merge was computed in a throwaway repo and read back."
echo "  * TWO MERGE ENGINES, AND THEY ARE NOT BYTE-IDENTICAL. Which one ran is printed above. They agree"
echo "    on the ANSWER you act on — which files are offered, which conflict, which are yours — and that"
echo "    is asserted in conformance. They can differ INSIDE a conflicted file: the two label conflict"
echo "    hunks differently ('<<<<<<< <commit-oid>' vs '<<<<<<< HEAD'), and on exotic histories (rename"
echo "    detection, directory/file collisions) merge-ort and merge-recursive can resolve differently."
echo "    Neither writes to your repo, and neither of them applies anything."
echo "  * EXPECT CLAUDE.md. incept STAMPS the kit version into your project doc, so a version bump changes"
echo "    it on the kit's side EVERY release: offered while you have not touched it, a CONFLICT the moment"
echo "    you have. That is the design working (it is YOUR doc), not a fault — usually you want only the"
echo "    '**Kit version adopted:**' line."
if [ "$HOOK_MODE" = tracked ]; then
  echo "  * GIT HOOKS: this repo runs TRACKED-HOOKS mode (core.hooksPath -> its own hooks/), so the live"
  echo "    hook IS the tracked hooks/pre-push and the delta above covers it in full — there is no"
  echo "    untracked copy this tool would have to leave to you. Applying the patch is the whole update;"
  echo "    sh conformance/guard-wired.sh is how you confirm it landed."
else
  echo "  * GIT HOOKS ARE NOT IN THE PATCH. hooks/pre-push is a tracked SOURCE file like any other — the"
  echo "    delta above covers it — but the INSTALLED .git/hooks/pre-push is untracked and this tool never"
  echo "    writes there. A HOOK REFRESH section above (when it appears) names the human-run command; it"
  echo "    appears when this release changes hooks/pre-push AND when the installed hook is stale anyway (the"
  echo "    gate's own pre-push rung verdict, reported on every run, even if this release did not touch the hook);"
  echo "    sh conformance/guard-wired.sh is how you confirm it landed. (The other documented install —"
  echo "    core.hooksPath pointing at the tracked hooks/ dir — has no copy to refresh: brownfield.md §2 step 5.)"
fi
echo ""
# NEXT only when there is something to record: a NEWER release than the tip's, or a tip still PARTIAL. When --from IS
# the tip's release and the tip is complete, the base is current and there is nothing for the agent to run.
if [ "$NEWSHA" != "$TIP_SRC" ] || [ "$BEHIND_N" -gt 0 ]; then
  echo "NEXT (the agent, after this update's PR merges and is pulled): sh scripts/kit-update.sh --advance-base --from '$FROM'"
else
  echo "NEXT: none — kit-base is current."
fi
if [ "$REMOTE_BASE_STATE" = absent ]; then
  echo ""
  echo "kit-base is not on '$REMOTE' — a teammate's clone cannot run kit-update. Publish it: kit-update --publish-base"
fi
