#!/bin/sh
# guard-core.sh — runtime-agnostic deny-matrix (the SINGLE SOURCE OF TRUTH).
# Pure: no stdin parsing, no runtime-specific emit. Each check prints the "13: …"
# reason to STDOUT and returns 1 (deny); returns 0 (allow) with no output.
# Consumed by: .claude/hooks/guard.sh (Claude PreToolUse), hooks/pre-push (git),
# scripts/kit-guard (CLI). See docs/operations/runtime-guards.md.
# A SPEED BUMP, not a boundary — the real control is platform-owned
# (docs/enterprise/platform-safety-boundary.md). POSIX sh; no `local` (dash-clean).

selfedit_allowed() { [ "${KIT_GUARD_SELFEDIT:-0}" = "1" ]; }

# control-plane paths an agent must never silently modify (guard integrity + gates).
# scanner-config allowlists/ignores — an edit here can silently narrow a required gate (KW10):
# .gitleaks.toml / .gitleaksignore / .semgrepignore / .trivyignore / .checkov.yaml|.yml are
# enumerated in the case below (both bare + */-prefixed forms). Honest ceiling: this covers
# DEDICATED scanner-config files (path-matchable). Coverage thresholds embedded in SHARED
# multi-purpose files (pyproject.toml, .golangci.yml) are NOT path-matchable without blocking the
# whole file — that is a content-level problem, out of scope here.
is_control_plane_path() {
  case "$1" in
    *.claude/hooks/guard.sh|*.claude/hooks/guard-core.sh|\
    *.claude/settings.json|*.claude/settings.local.json|\
    *.claude/mcp-policy.json|.claude/mcp-policy.json|\
    *.claude/agents/*|.claude/agents/*|\
    docs/governance/.meta-control-last|*/docs/governance/.meta-control-last|\
    docs/governance/meta-control-log.md|*/docs/governance/meta-control-log.md|\
    */hooks/pre-push|hooks/pre-push|*/scripts/kit-guard|scripts/kit-guard|\
    */.github/workflows/*|.github/workflows/*|*/CODEOWNERS|CODEOWNERS|*/.git/*|.git/*|\
    .gitleaks.toml|*/.gitleaks.toml|.gitleaksignore|*/.gitleaksignore|\
    .semgrepignore|*/.semgrepignore|.trivyignore|*/.trivyignore|\
    .checkov.yaml|*/.checkov.yaml|.checkov.yml|*/.checkov.yml|\
    conformance/*|*/conformance/*|adapters/*|*/adapters/*|\
    skills/*|*/skills/*|\
    scripts/fixtures/*|*/scripts/fixtures/*|\
    scripts/incept.sh|*/scripts/incept.sh|scripts/dora.sh|*/scripts/dora.sh|\
    scripts/agent-scorecard.sh|*/scripts/agent-scorecard.sh|\
    scripts/agent-trace.sh|*/scripts/agent-trace.sh|\
    scripts/escalate.sh|*/scripts/escalate.sh|\
    scripts/coverage-ratchet.sh|*/scripts/coverage-ratchet.sh|\
    scripts/license-check.sh|*/scripts/license-check.sh|\
    scripts/preflight.sh|*/scripts/preflight.sh|\
    scripts/new-adapter.sh|*/scripts/new-adapter.sh|\
    scripts/new-profile.sh|*/scripts/new-profile.sh|\
    scripts/doctor.sh|*/scripts/doctor.sh|\
    scripts/postmortem.sh|*/scripts/postmortem.sh|\
    scripts/tier-advice.sh|*/scripts/tier-advice.sh|\
    scripts/sparkwright|*/scripts/sparkwright|\
    scripts/containment-audit.sh|*/scripts/containment-audit.sh|\
    scripts/sod-check.sh|*/scripts/sod-check.sh|\
    .kit/budget.conf|*/.kit/budget.conf|\
    .kit/roster.conf|*/.kit/roster.conf|\
    .kit/model-tiers.conf|*/.kit/model-tiers.conf|\
    .kit/model-map.conf|*/.kit/model-map.conf|\
    scripts/model-tier.sh|*/scripts/model-tier.sh|\
    scripts/runaway-guard.sh|*/scripts/runaway-guard.sh|\
    scripts/orchestrator-run.sh|*/scripts/orchestrator-run.sh|\
    scripts/release-tag.sh|*/scripts/release-tag.sh|\
    scripts/promotion-verify.sh|*/scripts/promotion-verify.sh|\
    agents/*.agent.md|*/agents/*.agent.md|\
    DEVELOPMENT-STANDARDS.md|*/DEVELOPMENT-STANDARDS.md|\
    DEVELOPMENT-PROCESS.md|*/DEVELOPMENT-PROCESS.md|\
    CLAUDE.md|*/CLAUDE.md)
      return 0 ;;
  esac
  return 1
}

# --- CP-8c: dev-clone affordance ----------------------------------------------------
# _resolve_physical "<path>": echo the physical (symlink-resolved) absolute path. Resolves the
# DEEPEST EXISTING ancestor with `cd … && pwd -P` (collapsing `..`, symlinks, the macOS
# /tmp->/private/tmp landmine) and re-appends the not-yet-existing tail. `pwd -P` is the one
# sanctioned subprocess (CP-4 uses it).
_resolve_physical() {
  _rp=$1
  case "$_rp" in /*) : ;; *) _rp="$(pwd)/$_rp" ;; esac
  [ "$_rp" = / ] && { printf '/'; return 0; }   # degenerate root; avoids a `//` result
  _rpd=$(dirname "$_rp"); _rpb=$(basename "$_rp"); _rps=$_rpb
  while [ ! -d "$_rpd" ]; do
    _rpb=$(basename "$_rpd"); _rpd=$(dirname "$_rpd"); _rps="$_rpb/$_rps"
    [ "$_rpd" = "/" ] && break
  done
  _rpp=$(CDPATH='' cd "$_rpd" 2>/dev/null && pwd -P) || return 1
  if [ "$_rpp" = / ]; then printf '/%s' "$_rps"; else printf '%s/%s' "$_rpp" "$_rps"; fi
}

# _under_temp "<physical_path>": 0 iff the path is under a HARDCODED temp root. The set is FIXED
# and never read from $TMPDIR — reading an env var to WIDEN "disposable temp" is the fail-open
# direction (a poisoned TMPDIR=$HOME would relax ~/.claude). Covers Linux /tmp, macOS
# /private/tmp, and the macOS per-user temp (resolved: /private/var/folders/*/T/).
_under_temp() {
  case "$1/" in
    /tmp/*|/private/tmp/*|/var/folders/*/T/*|/private/var/folders/*/T/*) return 0 ;;
  esac
  return 1
}

# guard_dev_clone_relaxable "<path>" "<protected_root>": return 0 IFF a control-plane edit to
# <path> is safe to relax. THREE conditions, all physically resolved:
#   1. <path> is UNDER a (hardcoded) temp root, AND
#   2. <path> is OUTSIDE the protected repo root, AND
#   3. the protected root is NOT itself under temp.
# Condition 3 is load-bearing: when the protected tree is itself disposable (the mktemp'd export,
# a CI checkout), a path escaping the root lands as a temp-SIBLING that satisfies 1+2 — condition 3
# disables the affordance there, where there is no live control plane to protect anyway. A real
# repo (~/Development/…) is never under temp, so the dev-clone case is unaffected.
# Empty protected_root => 1 (fail-safe). A surviving `..` in the resolved path => 1 (an unresolved
# tail that could escape back into root). Only the CALLER (guard_check_path) uses this, only to skip
# the control-plane deny — never the secret or destructive denies.
guard_dev_clone_relaxable() {
  _dp=$1; _droot=$2
  [ -n "$_droot" ] || return 1
  _dphys=$(_resolve_physical "$_dp") || return 1
  _drootp=$(_resolve_physical "$_droot") || return 1
  [ -n "$_dphys" ] && [ -n "$_drootp" ] || return 1
  case "/$_dphys/" in *"/../"*) return 1 ;; esac
  _under_temp "$_drootp" && return 1          # condition 3: disposable root => affordance off
  case "$_dphys/" in "$_drootp"/*) return 1 ;; esac  # condition 2: must be outside root
  _under_temp "$_dphys" && return 0           # condition 1: target under temp
  return 1
}

# guard_check_read "<file>": deny reading SECRET material into the agent's context (the read half of
# exfil, A8 family 6) — the secret then reaches the model provider / logs / a PR. Symmetric with the
# secret-WRITE deny in guard_check_path but NARROWER: it does NOT deny control-plane reads (reading the
# guard/CI to understand it is legitimate). Template env files (.env.example/.sample/.template/.dist)
# are allowed; a single file_path means `*.env.*` is safe here (no multi-arg form to abuse). Honest
# ceilings: an interpreter (python -c open()) bypasses the shell path, and jq-absent leaves Read allowed.
guard_check_read() {
  fp=$1
  base=$(basename "$fp" 2>/dev/null || printf '%s' "$fp")
  case "$base" in
    .env.example|.env.sample|.env.template|.env.dist) return 0 ;;
  esac
  if ! selfedit_allowed; then
    case "$fp" in
      *.env|*/.env|*.env.*|*.pem|*.key|*id_rsa*|*/secrets/*|*/secret/*|secrets/*|secret/*)
        printf '13: reading secret material (%s) into context is the read half of exfil (-> model/logs/PR) - human-gated. Use .env.example / a secrets manager / redact; KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.' "$base"; return 1 ;;
    esac
  fi
  return 0
}

# --- CP-8a: leading-verb discipline -------------------------------------------------
# A segment's LEADING VERB decides whether its arguments are CODE or DATA. These two
# commands contain identical bytes; only the verb tells them apart:
#     bash -c "rm -rf /"          <- the argument is CODE   (a weapon)   -> must DENY
#     grep -rn "rm -rf" scripts/  <- the argument is DATA   (a search)   -> must ALLOW
# guard_read_only_command returns 0 ONLY for a command that is provably a SINGLE read-only
# invocation; for everything else the destructive matrix below runs UNCHANGED on the RAW
# command. It never rewrites or splits the command (see the closing note).
#
# INVARIANT (load-bearing): a verdict may only move DENY -> ALLOW when a safe lead is
# POSITIVELY RECOGNIZED. An unknown lead strips nothing, so behaviour is byte-for-byte
# today's. A bug here therefore fails CLOSED (over-denies), never OPEN.
#
# There is NO splitting: a shell metacharacter (; | & < > $ ( ) or backtick) ANYWHERE makes
# the whole command non-exempt outright. That is why a quoted separator cannot trick the
# exemption — it never parses the command into segments at all. Fail-closed.
#
# A segment is exempt ONLY if ALL of these hold:
#   1. it contains no < > $ ( ) or backtick — a redirect can truncate a file even under a
#      read verb (`echo -n > ci.yml`), and a command substitution smuggles code past it
#      (`grep foo $(rm -rf /)`). Unparseable => never exempt.
#   2. its first token carries no env-assignment (`GIT_EXTERNAL_DIFF=rm git diff`) and is not
#      a wrapper — the lead must be the verb itself, plainly.
#   3. that verb is in the STRICT set below: tools that write ONLY to stdout.
# The set deliberately EXCLUDES every tool with a write/exec escape, exactly as the WS1 note
# at guard_check_command already established — this is that vetted list, not a fresh one:
#   sed  (`s///e` EXECUTES the pattern space; `w file` writes one)
#   awk  (`system()`, `print > "file"`)
#   find (`-exec` / `-delete`)
#   sort (`-o file`)  ·  uniq (`uniq in out`)  ·  less/more (`!cmd`)  ·  xxd (`-r` writes)
# Admitting any of them would hand the guard an arbitrary-execution primitive to save a
# keystroke. `sed -n` stays denied; `head`/`tail` do the same job with no escape.
# `git` is admitted only on subcommands that cannot destroy (NOT push/reset/clean/checkout);
# `kit-guard` only on its read-only subcommands, so a guard slice can probe the guard.
# Returns 0 (exempt) ONLY for a command that is provably a SINGLE read-only invocation.
# It never REWRITES the command: on the non-exempt path the destructive matrix receives the
# raw string byte-for-byte, so not one of its ~40 rules has its assumptions perturbed. (An
# earlier draft split the command into segments and rejoined them with ';' — that destroyed
# the pipe `curl x | sh` detects and the end-of-string `--admin` anchors on, silently turning
# two DENY rules into ALLOW. Do not reintroduce rewriting.)
guard_read_only_command() {
  _c=$1
  # 1. ANY separator, redirect, substitution, expansion or backtick => not a simple, single
  #    invocation => never exempt. This is what makes the exemption safe rather than clever:
  #    `grep foo && rm -rf /`, `grep foo $(rm -rf /)`, `echo -n > ci.yml` all fail here.
  printf '%s' "$_c" | grep -q '[;|&<>$()`]' && return 1
  # 2. the leading verb, plainly: strip only whitespace and a leading backslash. An
  #    env-assignment prefix (`GIT_EXTERNAL_DIFF=rm git diff`) is not plainly a verb.
  _lead=$(printf '%s' "$_c" | sed -E 's/^[[:space:]]*\\?[[:space:]]*//; s/[[:space:]].*$//')
  _arg1=$(printf '%s' "$_c" | sed -E 's/^[[:space:]]*//; s/^[^[:space:]]+[[:space:]]+//; s/[[:space:]].*$//')
  case "$_lead" in
    *=*) return 1 ;;
    # 3. STRICT set: tools that write ONLY to stdout. Deliberately EXCLUDES every tool with a
    #    write/exec escape — exactly as the WS1 note below already established. This is that
    #    vetted list, not a fresh one:
    #      sed  (`s///e` EXECUTES the pattern space; `w file` writes one)
    #      awk  (`system()`, `print > "file"`)   ·  find (`-exec` / `-delete`)
    #      sort (`-o file`)  ·  uniq (`uniq in out`)  ·  less/more (`!cmd`)  ·  xxd (`-r`)
    #    Admitting any of them would hand the guard an arbitrary-execution primitive to save a
    #    keystroke. `sed -n` therefore stays denied; head/tail do the job with no escape.
    grep|egrep|fgrep|rg|ls|cat|head|tail|wc|diff|stat|du|cut|tr|nl|od|hexdump|column|tac|comm|cmp|basename|dirname|realpath|readlink|echo|printf|which|type)
      return 0 ;;
    git)
      # only subcommands that cannot destroy — NOT push/reset/clean/checkout.
      case "$_arg1" in
        # NOT diff|log|show — they honor --output=<file>, an arbitrary file WRITE via the
        # diff machinery (see the git --output deny in guard_check_command). commit|status|
        # blame|describe carry no such write flag.
        commit|status|blame|describe) return 0 ;;
      esac ;;
    kit-guard|*/kit-guard)
      # the guard's own read-only CLI, so a guard slice can probe the guard.
      case "$_arg1" in
        cmd|path|mcp) return 0 ;;
      esac ;;
  esac
  return 1
}

# --- CP-8b: bind a verb/flag to its TARGET ------------------------------------------
# The block this replaces matched the CO-OCCURRENCE of a mutation verb and a control-plane path
# anywhere in the flat command string, and never asked whether the verb's TARGET was that path. Two
# symmetric faces of that one missing relation:
#   over-DENY : `cp conformance/x /tmp/b` (copying OUT) - both tokens present, so denied.
#   over-ALLOW: `git archive -o conformance/x` (a real write) - `git archive` is not a mutation verb,
#               and `mv conformance /tmp` (the BARE directory) - the path patterns all require a
#               trailing slash, so they match a file INSIDE the dir and never the dir ITSELF.
# See docs/architecture/2026-07-12-cp8-guard-ergonomics-design.md sections 7-13.
#
# INVARIANT (load-bearing, inherited from CP-8a): a verdict may move DENY -> ALLOW only where a safe
# shape is POSITIVELY RECOGNIZED. Every relaxation below is an allow-back from the existing deny floor;
# anything unrecognized keeps today's behavior. A bug here therefore fails CLOSED, never OPEN.

# bare control-plane DIRECTORY names, for TARGET matching only. is_control_plane_path is deliberately
# NOT widened: it also drives the Write/Edit path (guard_check_path), and this slice adds no blast
# radius there. `mv conformance/ /tmp` was already denied; `mv conformance /tmp` was not - and that one
# command relocates every gate in the repo.
is_control_plane_target() {
  is_control_plane_path "$1" && return 0
  _ct=${1%/}; _ct=${_ct#./}
  case "$_ct" in
    conformance|skills|adapters|agents|scripts|hooks|.claude|.github|.git|.kit|\
    */conformance|*/skills|*/adapters|*/agents|*/scripts|*/hooks|*/.claude|*/.github|*/.git|*/.kit)
      return 0 ;;
  esac
  return 1
}

# _cp8b_joinlines: collapse backslash-newline CONTINUATIONS to a space. A continuation is NOT a command
# separator, and grep is LINE-oriented: `git push \<nl> origin main` puts `push` and `main` on different
# lines, so the flat push rule's regex matches neither (a pre-existing hole). Join first, split second.
_cp8b_joinlines() {
  printf '%s\n' "$1" | sed -e :a -e '/\\$/N; s/\\\n/ /; ta'
}

# _cp8b_segments "<cmd>": print one segment per line (split on ; && || | & and newline).
# Used ONLY by the CP-8b logic below. It is NEVER fed back into the destructive matrix, which keeps
# seeing the raw, unsplit string. (CP-8a: an earlier draft split the command and REJOINED it with ';',
# which destroyed the pipe `curl x | sh` detects and the end-of-string `--admin` anchors on, silently
# turning two DENY rules into ALLOW. Nothing is rejoined here.)
# A separator inside a quoted string over-splits into a bogus segment whose lead is unrecognized ->
# scan-and-deny. Over-DENY, fail-closed - and identical to today's verdict.
_cp8b_segments() {
  _cp8b_joinlines "$1" \
    | sed -e 's/&&/;/g' -e 's/||/;/g' -e 's/|/;/g' -e 's/&/;/g' \
    | tr ';\n' '\n\n'
}

# _cp8b_unparseable "<seg>": 0 iff the segment carries a construct the guard CANNOT resolve to the bytes
# the shell will actually execute: $VAR, $(...), `...`, <(...). The guard reads PRE-shell-parse bytes;
# the tool acts POST-parse. Such a segment is NEVER relaxed - and, for a git WRITE subcommand, is denied
# OUTRIGHT (see _cp8b_git_write_denied). That is the attack this closes:
#     git archive -o $(echo conformance/verify.sh) HEAD
# would otherwise slip BOTH the target-bind (target unresolvable) AND the co-occurrence floor
# (`git archive` is not a mutation verb). A bare '(' is NOT unparseable - a subshell's lead token is
# unrecognized and already fails closed - so conventional-commit subjects like "fix(guard): ..." parse.
_cp8b_unparseable() {
  printf '%s' "$1" | grep -q '[$`]' && return 0
  printf '%s' "$1" | grep -q '<(' && return 0
  return 1
}

# _cp8b_lead "<seg>": the leading verb, plainly. An env-assignment prefix (`GIT_EXTERNAL_DIFF=rm git
# diff`) yields a token containing '=', which matches no verb set -> unknown -> fail closed.
_cp8b_lead() {
  printf '%s' "$1" | sed -E 's/^[[:space:]]*\\?[[:space:]]*//; s/[[:space:]].*$//'
}

# _cp8b_dequote "<tok>": strip quote/escape bytes; for --flag=value / of=value forms, yield the VALUE.
# Safe in THIS DIRECTION ONLY: stripping normalizes TOWARD the real path, so --output="conformance/x"
# -> conformance/x -> matches -> DENY. It is NOT general shell parsing; $VAR and $(...) are
# unrecoverable, which is exactly why _cp8b_unparseable REFUSES them rather than parsing them badly.
# (CP-8a's review broke a target-parse whose failure direction was OPEN. Here unparseability is caught
# first and routed to deny, so what remains is a byte-match on a de-quoted literal whose worst case is
# an over-match -> over-DENY -> closed.)
_cp8b_dequote() {
  printf '%s' "$1" | sed -e "s/'//g" -e 's/"//g' -e 's/\\//g'
}

# _cp8b_tok_is_cp "<tok>": 0 iff the token, de-quoted and stripped of a flag= prefix, is a control-plane
# target.
_cp8b_tok_is_cp() {
  _tt=$(_cp8b_dequote "$1")
  case "$_tt" in *=*) _tt=${_tt#*=} ;; esac
  [ -n "$_tt" ] || return 1
  is_control_plane_target "$_tt"
}

# _cp8b_cp_target_in "<mode>" "<seg>": 0 iff a control-plane TARGET appears among the segment's argument
# tokens.
#   mode=all  - EVERY non-flag token is a target: rm/rmdir/shred/truncate/chmod/chown/tee/patch/dd/sed;
#               mv/rsync (whose SOURCE is destroyed too - which is what catches `mv conformance /tmp`);
#               and ln (which creates a WRITABLE ALIAS to its source - see the dispatch rationale below).
#   mode=last - only the LAST non-flag token is a target: cp/install, which copy CONTENT, so their source
#               is merely READ. This is what makes `cp conformance/verify.sh /tmp/b.sh` (copying OUT)
#               legitimate. A destination-naming flag (-t/--target-directory) is bound explicitly below,
#               in EITHER mode, because it inverts the positional heuristic.
# Globbing is disabled around the word-split so `rm *.sh` cannot expand against the real filesystem.
_cp8b_cp_target_in() {
  _m=$1
  _pg=0; case "$-" in *f*) _pg=1 ;; esac
  set -f
  # shellcheck disable=SC2086  # deliberate word-splitting; globbing disabled above
  set -- $2
  [ $# -gt 0 ] && shift          # drop the leading verb
  _hit=1; _last=''
  while [ $# -gt 0 ]; do
    case "$1" in
      # A destination-naming flag INVERTS the positional heuristic: `cp -t <dir> <src>` and
      # `--target-directory=<dir>` make <dir> the destination even though it is not the last token.
      # Bind it explicitly (any mode) - otherwise the "last token" rule checks the SOURCE and misses
      # the real write target. This is the same flag-binding as `git worktree add -b`. install/ln share
      # -t/--target-directory. A bare `-t` without a value is a malformed command -> nothing to bind.
      -t|--target-directory)
        if [ $# -ge 2 ]; then
          _dt=$(_cp8b_dequote "$2")
          [ -n "$_dt" ] && is_control_plane_target "$_dt" && { _hit=0; break; }
          shift
        fi
        shift; continue ;;
      # Joined short form (`-tconformance`) and abbreviated/`=`-joined long forms (`--target-di=…`,
      # `--target-directory=…`). GNU getopt honors a joined short-option value and any UNAMBIGUOUS long
      # prefix, so a partial match here is not paranoia - it is the exact evasion the security review
      # demonstrated. For cp/ln/install, `--target-d…` is unambiguous (no other `--target-*` option), so
      # matching the family closes the hole without a per-tool option table.
      # CAVEAT (verb-set-coupled): this `--target-d*` match is safe only because NO verb currently routed
      # here (cp/install/mv/rsync/rm/rmdir/shred/truncate/chmod/chown/tee/patch/dd/sed/ln) carries a
      # distinct `--target-d*` option. If a future verb with one is added to these groups, revisit.
      -t?*)
        _dt=$(_cp8b_dequote "${1#-t}")
        _dt=${_dt#=}
        [ -n "$_dt" ] && is_control_plane_target "$_dt" && { _hit=0; break; }
        shift; continue ;;
      --target-d*=*)
        _dt=$(_cp8b_dequote "${1#*=}")
        [ -n "$_dt" ] && is_control_plane_target "$_dt" && { _hit=0; break; }
        shift; continue ;;
      --target-d*)
        if [ $# -ge 2 ]; then
          _dt=$(_cp8b_dequote "$2")
          [ -n "$_dt" ] && is_control_plane_target "$_dt" && { _hit=0; break; }
          shift
        fi
        shift; continue ;;
      -*) shift; continue ;;     # any other flag is not a path target
    esac
    _d=$(_cp8b_dequote "$1")
    case "$_d" in *=*) _d=${_d#*=} ;; esac
    if [ -n "$_d" ]; then
      _last=$_d
      if [ "$_m" = all ] && is_control_plane_target "$_d"; then _hit=0; break; fi
    fi
    shift
  done
  if [ "$_m" = last ] && [ "$_hit" = 1 ] && [ -n "$_last" ] && is_control_plane_target "$_last"; then
    _hit=0
  fi
  [ "$_pg" = 1 ] || set +f
  return $_hit
}

# _cp8b_git_sub "<seg>": the git subcommand, after skipping GLOBAL options. Empty if unresolvable
# (an unknown global option) -> the caller fails closed. A subcommand is a token in COMMAND POSITION:
# you cannot quote your way into `git commit` actually being `git diff`, which is why binding to the
# SUBCOMMAND is sound where CP-8a's review proved binding to the TARGET was not.
_cp8b_git_sub() {
  _pg=0; case "$-" in *f*) _pg=1 ;; esac
  set -f
  # shellcheck disable=SC2086
  set -- $1
  [ $# -gt 0 ] && shift          # drop `git`
  _gs=''
  while [ $# -gt 0 ]; do
    case "$1" in
      -c|-C|--git-dir|--work-tree|--exec-path|--namespace)
        [ $# -ge 2 ] || break
        shift 2; continue ;;
      --git-dir=*|--work-tree=*|--exec-path=*|--namespace=*)
        shift; continue ;;
      -p|--paginate|--no-pager|--bare|--no-replace-objects|--literal-pathspecs|--glob-pathspecs|--noglob-pathspecs|--icase-pathspecs)
        shift; continue ;;
      -*) _gs=''; break ;;       # an unknown global option -> unresolvable -> fail closed
      *)  _gs=$1; break ;;
    esac
  done
  [ "$_pg" = 1 ] || set +f
  printf '%s' "$_gs"
}

# _cp8b_git_target_is_cp "<sub>" "<seg>": 0 iff the git WRITE subcommand's own destination is a
# control-plane target. Each subcommand names its destination differently - that is the whole point of
# target-binding, and why a flat regex could never do this.
_cp8b_git_target_is_cp() {
  _gsub=$1
  _pg=0; case "$-" in *f*) _pg=1 ;; esac
  set -f
  # shellcheck disable=SC2086
  set -- $2
  _hit=1; _seen=0
  case "$_gsub" in
    archive)
      # `git archive` writes a file ONLY via -o / --output; without it, it streams to stdout.
      # Separated (`-o x`), `=`-joined (`-o=x`, `--output=x`), and short-JOINED (`-ox`) forms all bind.
      while [ $# -gt 0 ]; do
        case "$1" in
          -o|--output)
            if [ $# -ge 2 ] && _cp8b_tok_is_cp "$2"; then _hit=0; break; fi ;;
          --output=*)
            if _cp8b_tok_is_cp "$1"; then _hit=0; break; fi ;;
          -o?*)
            _ov=$(_cp8b_dequote "${1#-o}"); _ov=${_ov#=}
            [ -n "$_ov" ] && is_control_plane_target "$_ov" && { _hit=0; break; } ;;
        esac
        shift
      done ;;
    bundle|worktree)
      # `git bundle create <file> <rev>` · `git worktree add [-b <branch>] <path> [<commit>]`.
      # Scan EVERY non-flag token after the marker, not just the first: a flag that takes a VALUE
      # (`git worktree add -b br conformance/wt`) consumes the first slot, so a "first non-flag token"
      # heuristic checks `br` and never sees the real path. Over-scanning can only ADD denies.
      # Only `create`/`add` write into a new path; bundle verify/list and worktree list/prune do not.
      # (The orchestrator uses `git worktree add /tmp/…` on every fan-out, so this MUST stay allowed
      # outside the control plane — corpus family D locks that.)
      while [ $# -gt 0 ]; do
        if [ "$_seen" = 1 ]; then
          case "$1" in
            -*) : ;;
            *) if _cp8b_tok_is_cp "$1"; then _hit=0; break; fi ;;
          esac
        fi
        case "$1" in create|add) _seen=1 ;; esac
        shift
      done ;;
    init|clone|checkout|restore)
      # init: [<dir>] · clone: <src> <dir> · checkout/restore: pathspecs (they OVERWRITE the worktree).
      # Any non-flag token naming a control-plane path is a write target. `git checkout -b fix/x` has
      # no such token -> allowed (the A4 false positive).
      [ $# -gt 0 ] && shift      # drop `git`
      [ $# -gt 0 ] && shift      # drop the subcommand
      while [ $# -gt 0 ]; do
        case "$1" in
          -*) : ;;
          *) if _cp8b_tok_is_cp "$1"; then _hit=0; break; fi ;;
        esac
        shift
      done ;;
  esac
  [ "$_pg" = 1 ] || set +f
  return $_hit
}

# _cp8b_git_write_denied "<seg>": PREDICATE - returns 0 (TRUE, "deny this") and prints the reason, or 1
# (allow). Note the inverted convention vs. the guard_check_* API: this is an internal predicate, named
# so at the call site.
#
# `-o` is --output (a WRITE) for `git archive` and --only (a READ) for `git commit`. That ambiguity is
# why the flat rule could not resolve it, and why `git commit -m "... --output ..."` was a false
# positive (CP-8a's recorded residual). Subcommand-binding resolves it.
_cp8b_git_write_denied() {
  _ws=$1
  [ "$(_cp8b_lead "$_ws")" = git ] || return 1
  _wsub=$(_cp8b_git_sub "$_ws")
  case "$_wsub" in
    archive|bundle|worktree|init|clone|checkout|restore) : ;;
    diff|log|show|format-patch)
      # The diff machinery honors --output=<file>: an arbitrary file WRITE/TRUNCATE with NO shell
      # redirect, which slips every redirect guard. Denied OUTRIGHT - NO target is parsed, because a
      # quoted / escaped / substituted target evades a byte match while git writes the real path (a live
      # bypass caught in CP-8a re-review). Unchanged from CP-8a; only its SCOPE narrows, from "any git"
      # to "the subcommands that actually honor the flag".
      # Match --output (space/=/joined) AND -o (space, or JOINED value `-oconformance`). This is an
      # OUTRIGHT deny with no target parsed, so a joined value cannot smuggle a write past it.
      if printf '%s' "$_ws" | grep -Eq '(^|[[:space:]])(--output([=[:space:]]|$)|-o([[:space:]]|$|[^[:space:]]))'; then
        printf '13: git %s --output/-o writes an arbitrary file via the diff machinery (defeats the shell-redirect guards) - human-gated. Redirect to a non-control-plane path instead (git diff > /tmp/x), or KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.' "$_wsub"
        return 0
      fi
      return 1 ;;
    *) return 1 ;;
  esac
  # A write subcommand. Unparseable target => we CANNOT prove it lands outside the control plane => DENY
  # OUTRIGHT (fail-closed). See _cp8b_unparseable for why this specific clause is the attack surface.
  if _cp8b_unparseable "$_ws"; then
    printf '13: git %s with an unresolvable (variable/substituted) target cannot be proven to land outside the control plane - denied (fail-closed). Use a literal path, or KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.' "$_wsub"
    return 0
  fi
  if _cp8b_git_target_is_cp "$_wsub" "$_ws"; then
    printf '13: git %s would write into the control plane (guard / CI gates / conformance) - denied (control-plane integrity). Target a path outside the control plane, or KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.' "$_wsub"
    return 0
  fi
  return 1
}

# _cp8b_scan_denied "<seg>": PREDICATE - today's CO-OCCURRENCE rule, applied to ONE segment. This is the
# fail-closed floor for every segment whose lead is an interpreter, a wrapper, or simply unrecognized.
# Extended in exactly one direction - it now also matches a BARE control-plane directory token - which
# can only ADD denies (monotone).
_cp8b_scan_denied() {
  _ss=$1
  _pathhit=1
  if printf '%s' "$_ss" | grep -Eq '(\.claude(/|[[:space:]]|$)|\.github/workflows|/CODEOWNERS|(^|[^a-zA-Z.])CODEOWNERS|\.git(/|[[:space:]]|$)|hooks/pre-push|scripts/kit-guard|docs/governance/\.meta-control-last|docs/governance/meta-control-log\.md|\.kit/budget\.conf|\.kit/roster\.conf|\.kit/model-map\.conf|\.kit/model-tiers\.conf|scripts/model-tier\.sh|scripts/orchestrator-run\.sh|agents/[^[:space:]]*\.agent\.md|scripts/release-tag\.sh|scripts/promotion-verify\.sh|scripts/escalate\.sh|skills/[^[:space:]]*|conformance/[^[:space:]]*|adapters/[^[:space:]]*|\.gitleaks\.toml|\.gitleaksignore|\.semgrepignore|\.trivyignore|\.checkov\.yaml|\.checkov\.yml)'; then
    _pathhit=0
  else
    # bare control-plane DIRECTORY token (the D1 gap): `bash -c "mv conformance /tmp"`.
    _pg=0; case "$-" in *f*) _pg=1 ;; esac
    set -f
    # shellcheck disable=SC2086
    set -- $_ss
    while [ $# -gt 0 ]; do
      if _cp8b_tok_is_cp "$1"; then _pathhit=0; break; fi
      shift
    done
    [ "$_pg" = 1 ] || set +f
  fi
  [ "$_pathhit" = 0 ] || return 1
  if printf '%s' "$_ss" | grep -Eq '(^|[^[:alnum:]_])(rm|rmdir|mv|cp|truncate|shred|chmod|chown|dd|sed|tee|ln|install|patch)[[:space:]]' \
     || printf '%s' "$_ss" | grep -Eq '(^|[^[:alnum:]_])git[[:space:]]+(checkout|restore)([[:space:]]|$)' \
     || printf '%s' "$_ss" | grep -Eq '>[[:space:]]*[^[:space:]]*(\.claude|\.github/workflows|CODEOWNERS|\.git|hooks/pre-push|scripts/kit-guard|docs/governance/\.meta-control-last|docs/governance/meta-control-log\.md|\.kit/budget\.conf|\.kit/roster\.conf|\.kit/model-map\.conf|\.kit/model-tiers\.conf|scripts/model-tier\.sh|scripts/orchestrator-run\.sh|agents/[^[:space:]]*\.agent\.md|scripts/release-tag\.sh|scripts/promotion-verify\.sh|scripts/escalate\.sh|skills/[^[:space:]]*|conformance/[^[:space:]]*|adapters/[^[:space:]]*|\.gitleaks\.toml|\.gitleaksignore|\.semgrepignore|\.trivyignore|\.checkov\.yaml|\.checkov\.yml)'; then
    return 0
  fi
  return 1
}

# _cp8b_deny_reason "<seg>": print the control-plane deny reason, NAMING the offending segment. Every
# non-git-write deny arm calls this so the block never denies with a BLANK reason (a regression the
# security + code reviews both caught: `main` always printed the `13: … KIT_GUARD_SELFEDIT=1 …` guidance,
# and an empty reason leaves a blocked agent with no explanation and no override hint - in an ERGONOMICS
# slice). The segment name closes the CP-8a section-1.2 UX gap (a denied COMPOUND gave no signal about
# WHICH part offended). Truncated so a pathological segment cannot flood the reason channel.
# _cp8b_message_tip: DRIFT-2. When the RAW command is a git/gh message-carrying invocation, a
# control-plane deny is most often a MULTILINE MESSAGE BODY being segmented on its newlines and scanned as
# code — the message DATA mis-read as a command. The guard does NOT relax the decision (a quote-aware
# segmenter would fail OPEN: it could miss a real `; rm -rf` split); instead it NAMES the safe escape, which
# passes the body from a FILE and cannot execute. This is ADDITIVE to the reason text only — it changes no
# deny/allow verdict, and it is harmless on a genuine attack (the command is still denied; the tip helps no
# bypass). Reads $_cp8b_raw, set at the top of _cp8b_control_plane_denied (its only caller of this arm).
_cp8b_message_tip() {
  case "$1" in
    *"git commit"*|*"git merge"*|*"git tag"*|*"git notes"*|*"gh pr"*|*"gh issue"*|*"gh release"*)
      printf ' TIP: a multi-line commit/PR message body is scanned as data and can trip this; pass it from a FILE instead of an inline -m/--body — `git commit -F <file>` or `gh pr create --body-file <file>` (the file content is never executed).'
      return ;;
  esac
  # DRIFT-2b: a read-oriented sed/awk/… on a control-plane path is denied because these tools carry write/exec
  # escapes (`sed s///e`/`w`, `awk system()`); NAME the escape-free paths. Detect the LEAD VERB (not a
  # substring — a message body mentioning "sed" must not trigger this). Names BOTH read and edit exits, so it
  # is accurate whether the operator meant `sed -n` (read) or `sed -i` (edit) — no program sub-parse.
  _mt_lead=$(printf '%s' "$1" | sed -E 's/^[[:space:]]*\\?[[:space:]]*//; s/[[:space:]].*$//')
  case "$_mt_lead" in
    sed|awk|sort|uniq|find|less|more|xxd)
      printf ' TIP: %s is denied on control-plane paths (write/exec escapes). For a plain READ use head/tail/cat or the Read tool; to EDIT a control-plane file use the Edit/Write tool in a dev-clone (never via shell).' "$_mt_lead" ;;
  esac
}
_cp8b_deny_reason() {
  _dr=$(printf '%s' "$1" | cut -c1-160)
  printf '13: mutating the guard / its config / CI gates via shell is denied (control-plane integrity) - offending segment: [%s].%s Set KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.' "$_dr" "$(_cp8b_message_tip "${_cp8b_raw:-}")"
}

# _cp8b_next_seg: pop the first newline-delimited segment off $_walk into $_seg, leaving the remainder in
# $_walk. Returns 0 while a segment remains, 1 when exhausted. This is PURE PARAMETER EXPANSION - it never
# touches IFS (a global IFS reassignment is the bash.lang.security.ifs-tampering finding, and it also risks
# leaking a modified IFS into the ~40 destructive-matrix rules that run AFTER this block). And it is NOT a
# `cmd | while read` pipe, which would run the body in a SUBSHELL and silently lose the caller's `return`
# (CP-1 shipped exactly that bug, green the whole time). The caller seeds $_walk from _cp8b_segments.
_cp8b_nl='
'
_cp8b_next_seg() {
  [ -n "$_walk" ] || return 1
  case "$_walk" in
    *"$_cp8b_nl"*) _seg=${_walk%%"$_cp8b_nl"*}; _walk=${_walk#*"$_cp8b_nl"} ;;
    *)             _seg=$_walk; _walk='' ;;
  esac
  return 0
}

# _cp8b_control_plane_denied "<cmd>": PREDICATE - the CP-8b control-plane decision. Walks the segments
# and binds each segment's LEADING VERB to that segment's OWN arguments (design section 9.4).
_cp8b_control_plane_denied() {
  _cp8b_raw=$1   # DRIFT-2: the whole command, for _cp8b_message_tip (the message-body escape hint).
  _walk=$(_cp8b_segments "$1")
  while _cp8b_next_seg; do
    [ -n "$(printf '%s' "$_seg" | tr -d '[:space:]')" ] || continue

    # 1. git write-primitives are subcommand-bound and apply REGARDLESS of a control-plane mention
    #    (`git diff --output` writes anywhere). Checked first.
    if _cp8b_git_write_denied "$_seg"; then return 0; fi

    # 2. a segment we cannot parse, or one carrying a redirect, is NEVER relaxed - it keeps today's
    #    scan-and-deny. (`echo -n > .github/workflows/ci.yml` leads with a READ verb; only the redirect
    #    check stands between it and an allow-back.)
    if _cp8b_unparseable "$_seg" || printf '%s' "$_seg" | grep -q '[<>]'; then
      if _cp8b_scan_denied "$_seg"; then _cp8b_deny_reason "$_seg"; return 0; fi
      continue
    fi

    _lv=$(_cp8b_lead "$_seg")
    case "$_lv" in
      # 3. READ TOOLS - CP-8a's strict stdout-only set, REUSED VERBATIM, not re-derived. It deliberately
      #    excludes every tool with a write/exec escape: sed (s///e executes, `w` writes), awk (system(),
      #    print >), find (-exec/-delete), sort (-o), uniq (out), less/more (!cmd), xxd (-r). Their
      #    arguments are DATA: a read command cannot mutate the path it merely mentions.
      grep|egrep|fgrep|rg|ls|cat|head|tail|wc|diff|stat|file|du|cut|tr|nl|od|hexdump|column|tac|comm|cmp|basename|dirname|realpath|readlink|echo|printf|which|type)
        : ;;
      git)
        _sub=$(_cp8b_git_sub "$_seg")
        case "$_sub" in
          # Read subcommands whose arguments are DATA — `git commit -m "… conformance/x …"` is a MESSAGE,
          # not a target. This set is CP-8a's, REUSED VERBATIM and deliberately NOT widened.
          #
          # Every other git subcommand is left to fall through to scan-and-deny below, and that is a
          # decision, not an oversight. An earlier cut of this slice also certified
          # `add|fetch|pull|rebase|merge|stash|tag|branch|config|push` as "reads" — which would have
          # handed back an arbitrary-execution primitive, because `git rebase --exec "rm -rf conformance"`
          # RUNS the string. That is CP-8a's fail-open repeating exactly: certifying a capability safe by
          # NAMING it, without enumerating every flag it carries ("git diff is a read" — false for
          # --output). None of them NEED the exemption: with no mutation verb in the segment, scan-and-deny
          # allows them anyway. Speculative exemptions are treated as guilty.
          commit|status|blame|describe)
            : ;;
          checkout|restore|archive|bundle|worktree|init|clone)
            : ;;   # already TARGET-BOUND in step 1; a clean pass there is a real ALLOW.
          *)
            if _cp8b_scan_denied "$_seg"; then _cp8b_deny_reason "$_seg"; return 0; fi ;;
        esac ;;
      # 4. MUTATION VERBS - target-bound. Two sub-classes by what the verb does to its SOURCE:
      #    - ALL path tokens are targets when the verb can WRITE THROUGH any of its arguments:
      #        mv/rsync DESTROY the source (this is what catches `mv conformance /tmp/gone`);
      #        ln creates a WRITABLE ALIAS - `ln -s conformance/x /tmp/link` then `echo … > /tmp/link`
      #        writes the control-plane file, so `ln` is NOT a content-copy and every token it names is a
      #        target (security review of CP-8b: grouping `ln` with `cp` was the family's signature
      #        error - certifying a capability safe by the name it is grouped under, not by what it does);
      #        rm/chmod/… mutate their targets in place.
      #    - Only the DESTINATION is a target for cp/install, which copy CONTENT: editing the copy cannot
      #      reach the original, so copying a control-plane file OUT (`cp conformance/x /tmp/b`) is safe.
      mv|rsync|ln|rm|rmdir|shred|truncate|chmod|chown|tee|patch|dd|sed)
        if _cp8b_cp_target_in all "$_seg"; then _cp8b_deny_reason "$_seg"; return 0; fi ;;
      cp|install)
        if _cp8b_cp_target_in last "$_seg"; then _cp8b_deny_reason "$_seg"; return 0; fi ;;
      # 5. ANYTHING ELSE - an interpreter, a wrapper, or simply unrecognized. Its arguments may be CODE.
      #    Today's behavior, byte for byte. This is the branch that makes the whole change monotone.
      *)
        if _cp8b_scan_denied "$_seg"; then _cp8b_deny_reason "$_seg"; return 0; fi ;;
    esac
  done
  return 1
}

# _cp8b_push_main_denied "<cmd>": PREDICATE - the push-to-main rule, SCOPED to a segment.
# The flat rule is the FLOOR (it denies); this may only ALLOW BACK when no single segment carries both
# the push and the main/master refspec - i.e. when the flat regex only ever matched by SPANNING a shell
# separator, which is precisely the false positive:
#     git push -u origin fix/x && gh pr create --body "... merges to main"
# This is NOT the rewriting CP-8a forbade: that was splitting the command and REJOINING it with ';',
# which perturbed the OTHER ~40 rules. Here only this ONE rule's window narrows; every other rule still
# sees the raw, unsplit string (`curl x | sh` keeps its pipe, `--admin` keeps its end-of-string anchor).
_cp8b_push_main_denied() {
  _walk=$(_cp8b_segments "$1")
  while _cp8b_next_seg; do
    if printf '%s' "$_seg" | grep -Eq 'git[[:space:]]+(-c[[:space:]]+[^[:space:]]+[[:space:]]+)*push.*[^a-zA-Z0-9_.-](main|master)([^a-zA-Z0-9_.-]|$)'; then
      return 0
    fi
  done
  return 1
}

# guard_check_command "<cmd>": print reason + return 1 if denied, else return 0.
guard_check_command() {
  cmd=$1
  # --- control-plane shell mutation (moved from guard.sh:81-93, + new files) ---
  if ! selfedit_allowed && printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+config[[:space:]]+([^;&|]*[[:space:]])?core\.hooksPath'; then
    printf '%s' '13: git config core.hooksPath would disable the agent guard - human-gated. Set KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.'; return 1
  fi
  # CP-8b: the CO-OCCURRENCE block that used to live here matched a mutation verb and a control-plane
  # path ANYWHERE in the flat string, and never asked whether the verb's TARGET was that path — which
  # is both why `cp conformance/x /tmp/b` (copying OUT) was denied and why `git archive -o conformance/x`
  # (a real write) was allowed. It is replaced by a SEGMENT WALK that binds each segment's leading verb
  # to that segment's OWN arguments, plus subcommand-bound git write-primitives (which also absorb
  # CP-8a's `git … --output` deny, narrowing its scope from "any git" to the subcommands that honor it).
  # Monotone: every relaxation inside the predicate is an allow-back gated on POSITIVE recognition, so a
  # bug there over-denies and cannot over-allow.
  if ! selfedit_allowed; then
    if _cp8b_reason=$(_cp8b_control_plane_denied "$cmd"); then
      # Belt-and-suspenders: every deny arm inside the predicate already prints a reason via
      # _cp8b_deny_reason / _cp8b_git_write_denied, but a blank reason must NEVER reach the adapter (it
      # would surface as an empty permissionDecisionReason - a blocked agent with no guidance). Default it.
      [ -n "$_cp8b_reason" ] || _cp8b_reason='13: mutating the guard / its config / CI gates via shell is denied (control-plane integrity). Set KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.'
      printf '%s' "$_cp8b_reason"; return 1
    fi
  fi
  # H3a: secret-in-context (shell) — a content-read verb (cat/grep/strings/diff/awk/...; also
  # source/. which load a .env into the environment) targeting secret material pulls it into the
  # agent's context: the read half of exfil. Human-gate it, symmetric with the secret-WRITE deny in
  # guard_check_path. ls (metadata) is excluded; template env files (.env.example/.sample/.template/
  # .dist) are NOT in the secret-suffix list so they stay allowed (no command-wide exclusion, which
  # a `cat .env.example .env` multi-arg form could abuse). Honest ceiling: an interpreter
  # (python -c open()) or an uncommon content-emitter not in the verb list bypasses — the robust
  # path is the Read-tool deny (guard_check_read) + platform containment. Asymmetry by design: the
  # shell path enumerates common .env.<suffix> files, while the Read tool's `*.env.*` glob catches
  # any suffix (e.g. `.env.foo` / `.env.local.bak` slip the shell path but the Read equivalent denies).
  if ! selfedit_allowed \
     && printf '%s' "$cmd" | grep -Eq '(^|[;&|]|[[:space:]])[[:space:]]*(cat|less|more|head|tail|grep|egrep|fgrep|rg|strings|xxd|od|hexdump|base64|nl|tac|diff|cmp|comm|awk|sed|sort|uniq|cut|paste|fold|jq|yq|rev|source|\.)[[:space:]]' \
     && printf '%s' "$cmd" | grep -Eq '\.env(\.(local|production|development|staging|test|prod|dev|stage|qa|preview|ci|bak|old))?([[:space:];|&*]|$)|\.(pem|key)([[:space:];|&*]|$)|id_rsa|(^|[[:space:]/;|&])secrets?/'; then
    printf '%s' '13: reading secret material into context (the read half of exfil -> model/logs/PR) is human-gated. Use .env.example / a secrets manager / redact; KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.'; return 1
  fi
  # --- destructive matrix: moved VERBATIM from guard.sh:96-242 ---
  # CP-8a: the leading verb decides whether the ARGUMENTS are code or data. These carry
  # identical bytes and only the verb tells them apart:
  #     bash -c "rm -rf /"          <- the argument is CODE (a weapon) -> must DENY
  #     grep -rn "rm -rf" scripts/  <- the argument is DATA (a search) -> must ALLOW
  # A provably read-only SINGLE invocation therefore skips the matrix. Everything else
  # falls through with the command UNCHANGED, so no rule below has its input perturbed.
  # CP-8a (security re-review of #297): git's diff machinery (diff/log/show) honors
  # --output=<file> — an arbitrary file WRITE/TRUNCATE with NO shell redirect, so it slips both
  # the control-plane block above and (as a read verb) the exemption below.
  # `git diff --output=.github/workflows/ci.yml HEAD` zeroes the workflow on a clean tree.
  # Do NOT parse the --output TARGET: the guard sees PRE-shell-parse bytes, so any quoting /
  # escaping / substitution of the target (`--output="conformance/x"`, `--output=$(...)`) evades a
  # path match while git still writes the real path (a live bypass caught in re-review). Deny
  # `git ... --output` OUTRIGHT — fail-closed, no target to parse. The legitimate residual is a
  # plain redirect to a non-control-plane path (`git diff > /tmp/x`, which the guard allows) or
  # KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.
  # CP-8b: CP-8a's blanket `git … --output` deny lived here. It is now SUBCOMMAND-BOUND inside
  # _cp8b_git_write_denied (called above): still an OUTRIGHT deny with no target parsed, but scoped to
  # the subcommands that actually honor the flag (diff/log/show/format-patch/archive). That removes the
  # residual CP-8a recorded — `git commit -m "… --output …"`, where a commit message merely *mentions*
  # the flag and `-o` means `--only` — without weakening the deny for any subcommand that can write.
  if guard_read_only_command "$cmd"; then return 0; fi
  # recursive rm in any flag arrangement (-rf, -fr, -r -f, --recursive), bounded so
  # 'confirm'/'npm' are not matched, but quoted forms (bash -c "rm -rf") are.
  if printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_])rm[[:space:]]+([^;&|]*[[:space:]])?(-[[:alnum:]]*[rR]|--recursive)'; then
    { printf '%s' '13: recursive rm is irreversible - human-gated.'; return 1; }
  fi
  # 9b: non-recursive rm of a DANGEROUS target — a glob, a data/critical file extension,
  # an absolute path, or a dotfile of record. Anchored to command position so a commit
  # message mentioning rm is not matched. Plain relative single files (rm stale.txt,
  # rm dist/bundle.js) remain ALLOWED to avoid over-blocking normal dev work.
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?rm[[:space:]]'; then
    if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?rm[[:space:]]+([^;&|]*[[:space:]])?(--[[:space:]]+)?[^;&|[:space:]]*[*?[][^;&|[:space:]]*([[:space:]]|$)' \
       || printf '%s' "$cmd" | grep -Eiq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?rm[[:space:]][^;&|]*\.(db|sqlite|sqlite3|sql|dump|pgdump|bak|rdb|mdb)([[:space:]]|$)' \
       || printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?rm[[:space:]]+([^;&|]*[[:space:]])?/[^[:space:]]' \
       || printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?rm[[:space:]][^;&|]*(\.env|/\.git)([[:space:]]|$|/)' \
       || printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?rm[[:space:]]+([^;&|]*[[:space:]])?\.env([[:space:]]|$)'; then
      { printf '%s' '13: rm of a glob, data file, absolute path, or dotfile-of-record can be irreversible - human-gated.'; return 1; }
    fi
  fi
  # 9b: non-rm destruction primitives. Binaries are anchored to COMMAND POSITION
  # (start, or after a ; && || | separator, optional sudo) so a word like "truncate"
  # inside a commit message is NOT matched — only an actually-invoked command is.
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?(truncate|shred|wipefs|blkdiscard|mkfs(\.[a-z0-9]+)?)([[:space:]]|$)'; then
    { printf '%s' '13: in-place file/device destruction (truncate/shred/wipefs/blkdiscard/mkfs) is irreversible - human-gated.'; return 1; }
  fi
  # dd is a scalpel like rm: deny only when of= targets a device or a data-file extension
  # (dd of=test-fixture.img stays allowed; dd of=/dev/sda and dd of=db.sqlite are denied).
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?dd[[:space:]]' \
     && printf '%s' "$cmd" | grep -Eiq 'of=(/dev/|[^[:space:]]*\.(db|sqlite|sqlite3|sql|dump|pgdump|bak|rdb|mdb)([[:space:]]|$))'; then
    { printf '%s' '13: dd of= a device or data file overwrites it irreversibly - human-gated.'; return 1; }
  fi
  # redirection/empty-source truncation of an existing target. GENERIC by target: the
  # patterns below match ANY destination ([^[:space:]&|;]+), so truncating a scanner-config
  # (e.g. `: > .gitleaks.toml`) is already covered here — no path enumeration needed (KW10).
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*):[[:space:]]*>[[:space:]]*[^[:space:]&|;]+' \
     || printf '%s' "$cmd" | grep -Eq '/dev/null[[:space:]]*>[[:space:]]*[^[:space:]&|;]+' \
     || printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(cat|cp)[[:space:]]+/dev/null[[:space:]]+[>]?[[:space:]]*[^[:space:]&|;]+' \
     || printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)echo[[:space:]]+-n[[:space:]]*>[[:space:]]*[^[:space:]&|;]+'; then
    { printf '%s' '13: redirection/empty-source truncation zeroes a file irreversibly - human-gated. TIP: to create or replace a file, use the Write tool (a shell >/: truncation is denied because it can irreversibly zero an existing file).'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?find[[:space:]]+[^|]*-delete([[:space:]]|$)' \
     || printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?find[[:space:]]+[^|]*-exec[[:space:]]+(rm|shred|truncate)([[:space:]]|$)' \
     || printf '%s' "$cmd" | grep -Eq '\|[[:space:]]*(sudo[[:space:]]+)?xargs[[:space:]]+([^|]*[[:space:]])?(rm|shred|truncate|unlink|wipefs)([[:space:]]|$)'; then
    { printf '%s' '13: bulk irreversible deletion (find -delete / -exec rm / pipe to xargs rm) - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?rsync[[:space:]]+[^|]*--delete([[:space:]]|$|[^a-z])'; then
    { printf '%s' '13: rsync --delete mirrors a source and removes destination files irreversibly - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)git[[:space:]]+clean[[:space:]]+[^|]*-[a-z]*[fdx]'; then
    { printf '%s' '13: git clean -f/-d/-x force-deletes untracked/ignored files irreversibly - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?mv[[:space:]]+[^;&|]*[[:space:]]/dev/null([[:space:]]|$)'; then
    { printf '%s' '13: moving a file onto /dev/null destroys its contents - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+reset[[:space:]]+.*--hard'; then
    { printf '%s' '13: git reset --hard discards work irreversibly - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq '(npm|yarn|pnpm)[[:space:]]+publish'; then
    { printf '%s' '13: publishing a package is externally irreversible - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+(-c[[:space:]]+[^[:space:]]+[[:space:]]+)*push.*(--force|--force-with-lease|--mirror|[[:space:]]-f([[:space:]]|$)|[[:space:]+]\+[^[:space:]]*[[:space:]]*$)'; then
    { printf '%s' '13: force/mirror push rewrites or deletes published history - human-gated.'; return 1; }
  fi
  # push to main/master in any refspec form: 'main', '+main', 'HEAD:main', 'x:master', "main" (incl. git -c … push)
  # CP-8b: SCOPED to a segment. The identical regex now runs per-segment instead of over the flat string,
  # so it can no longer match by SPANNING a shell separator — which is the whole false positive:
  #     git push -u origin fix/x && gh pr create --body "… merges to main"
  # (`git push` in segment 1, the word "main" in segment 2's PR body). A real push to main keeps both on
  # ONE segment and still denies. Only THIS rule's window narrows; every other matrix rule below still
  # sees the raw, unsplit command (`curl … | sh` keeps its pipe; `--admin` keeps its end-of-string anchor).
  # The segmenter also JOINS backslash-newline continuations first, which closes a pre-existing hole:
  # grep is line-oriented, so `git push \<newline> origin main` put `push` and `main` on different lines
  # and the flat regex matched NEITHER.
  if _cp8b_push_main_denied "$cmd"; then
    { printf '%s' '13: pushing directly to main/master bypasses review - open a PR (human-gated).'; return 1; }
  fi
  # S6: gh pr merge --admin/--administrator BYPASSES branch protection (incl. the control-plane-
  # ratification / required-review gate) — the fox opening its own henhouse. A SPEED BUMP (string
  # match): the real boundary is the platform never issuing the agent an admin credential
  # (docs/enterprise/platform-safety-boundary.md). The agent's sanctioned path is a NORMAL merge on
  # a recorded authenticated GO (scripts/promotion-verify.sh actuate); --admin is the SOLO kill-switch.
  if printf '%s' "$cmd" | grep -Eq 'gh[[:space:]]+pr[[:space:]]+merge' \
     && printf '%s' "$cmd" | grep -Eq '(--admin|--administrator)([[:space:]]|=|$)'; then
    { printf '%s' '13: gh pr merge --admin bypasses branch protection (incl. control-plane-ratification) - human-gated. The agent actuates via a NORMAL merge on a recorded authenticated GO (scripts/promotion-verify.sh actuate); the --admin bypass is the solo kill-switch. See docs/operations/runtime-guards.md.'; return 1; }
  fi
  # destructive SQL via a DB client
  if printf '%s' "$cmd" | grep -Eiq '(psql|mysql|mariadb|sqlite3|mongosh?).*(drop[[:space:]]+(table|database)|truncate|delete[[:space:]]+from)'; then
    { printf '%s' '13: destructive SQL (DROP/TRUNCATE/DELETE via a DB client) - human-gated.'; return 1; }
  fi
  # destructive DB resets via migration runners
  if printf '%s' "$cmd" | grep -Eiq '(prisma[[:space:]]+migrate[[:space:]]+reset|prisma[[:space:]]+db[[:space:]]+push[^|]*--force-reset|sequelize[^|]*db:migrate:undo:all|knex[^|]*migrate:rollback[^|]*--all|drizzle-kit[[:space:]]+push)'; then
    { printf '%s' '13: destructive DB reset via a migration runner - human-gated.'; return 1; }
  fi
  # dropdb as an invoked command (start or after a shell separator), not when merely
  # mentioned in prose (e.g. a commit message "fix dropdb bug").
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)dropdb([[:space:]]|$)'; then
    { printf '%s' '13: dropdb destroys a database irreversibly - human-gated.'; return 1; }
  fi
  # ORM / framework DB destruction (drop/reset/wipe/fresh) across stacks
  if printf '%s' "$cmd" | grep -Eiq '(rails|rake)[[:space:]]+db:(drop|reset|migrate:reset|purge)|artisan[[:space:]]+(migrate:fresh|migrate:reset|db:wipe)|manage\.py[[:space:]]+(flush|reset_db|sqlflush)|alembic[[:space:]]+downgrade[[:space:]]+base|flyway[[:space:]]+clean|dotnet[[:space:]]+ef[[:space:]]+database[[:space:]]+(drop|update[[:space:]]+0)'; then
    { printf '%s' '13: destructive DB drop/reset via an ORM/framework tool - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq 'pg_restore[^|]*(--clean|[[:space:]]-c([[:space:]]|$))'; then
    { printf '%s' '13: pg_restore --clean drops objects irreversibly - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eiq 'redis-cli[^|]*(flushall|flushdb)'; then
    { printf '%s' '13: redis FLUSHALL/FLUSHDB wipes the datastore - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq 'kubectl[[:space:]]+([^|]*[[:space:]])?delete([[:space:]]|$)'; then
    { printf '%s' '13: kubectl delete removes cluster resources - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq 'docker[[:space:]]+(volume[[:space:]]+(rm|prune)|system[[:space:]]+prune[^|]*(-a|--all))'; then
    { printf '%s' '13: docker volume/system prune destroys persistent state - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq 'aws[[:space:]]+s3[[:space:]]+rm[^|]*--recursive|aws[[:space:]]+s3[[:space:]]+rb|aws[[:space:]]+rds[[:space:]]+delete-db-instance|aws[[:space:]]+dynamodb[[:space:]]+delete-table|gcloud[[:space:]]+sql[[:space:]]+instances[[:space:]]+delete|az[[:space:]]+group[[:space:]]+delete|az[[:space:]]+sql[^|]*[[:space:]]delete'; then
    { printf '%s' '13: cloud resource deletion (storage/DB/instance) is irreversible - human-gated.'; return 1; }
  fi
  # 9b: cloud/infra destruction as capability families (verb-agnostic across vendors)
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)terraform[[:space:]]+(destroy|apply)([[:space:]]|$)'; then
    { printf '%s' '13: terraform destroy/apply changes real infrastructure - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eiq '(^[[:space:]]*|[;&|][[:space:]]*)(aws|gcloud|az)[[:space:]][^|]*[[:space:]](delete|delete-[a-z-]+|terminate-[a-z-]+|remove|rb|destroy)([[:space:]]|$)'; then
    { printf '%s' '13: cloud resource deletion/termination is irreversible - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)helm[[:space:]]+(uninstall|delete)([[:space:]]|$)' \
     || printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)kubectl[[:space:]]+(drain|cordon)([[:space:]]|$)'; then
    { printf '%s' '13: helm uninstall / kubectl drain disrupts running workloads - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eiq '(mongosh?|cockroach|psql|mysql)[^|]*(dropDatabase|drop[[:space:]]+database)' \
     || printf '%s' "$cmd" | grep -Eiq '(^[[:space:]]*|[;&|][[:space:]]*)(liquibase[[:space:]]+dropAll|flyway[[:space:]]+undo)'; then
    { printf '%s' '13: database drop via a client/migration tool is irreversible - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq '(curl|wget|base64[[:space:]]+(-d|--decode)|xxd[[:space:]]+-r)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(sh|bash|zsh|dash|python[0-9.]*|node|perl|ruby|php)([[:space:]]|$)'; then
    { printf '%s' '13: piping a fetched/decoded payload into a shell is high-blast-radius - human-gated.'; return 1; }
  fi
  # 9b: data-exfiltration channels (PARTIAL — binary-name denial only; interpreters
  # (python -c, node -e) remain channels. The real control is the platform network-egress
  # allowlist — see docs/enterprise/platform-safety-boundary.md. This is a speed bump.)
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?(scp|sftp)[[:space:]]' \
     || printf '%s' "$cmd" | grep -Eq '(curl|wget)[[:space:]][^|]*(-T[[:space:]]|--upload-file|-F[[:space:]]*[^[:space:]&|;]*@|--data-binary[[:space:]]*@|--post-file)' \
     || printf '%s' "$cmd" | grep -Eq '\|[[:space:]]*(nc|ncat|netcat)[[:space:]]+[^[:space:]]' \
     || printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)rclone[[:space:]]+(copy|sync|move)[[:space:]][^|]*[a-zA-Z0-9_-]+:' \
     || printf '%s' "$cmd" | grep -Eq '\|[[:space:]]*mail[[:space:]]'; then
    { printf '%s' '13: possible data exfiltration (scp/sftp/curl-upload/nc/rclone/mail). Partial guard - the boundary is the platform egress allowlist - human-gated.'; return 1; }
  fi
  # 9b: eval of a command substitution hides the real command from inspection.
  # Anchored to command position so "eval $(...)" inside a commit message is NOT matched.
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)(sudo[[:space:]]+)?eval[[:space:]]+[^;&|]*(\$\(|`)'; then
    { printf '%s' '13: eval of a command substitution obscures the executed command - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eiq '(vercel[[:space:]]+(deploy[[:space:]]+)?--prod|railway[[:space:]]+up|fly[[:space:]]+deploy|terraform[[:space:]]+apply|kubectl[[:space:]]+apply|helm[[:space:]]+(install|upgrade))'; then
    { printf '%s' '13: production deploy / infra apply is high-blast-radius - human-gated.'; return 1; }
  fi
  # prod-context catch-all: a mutating kube/helm op against a production context or namespace.
  # Patterns are intentionally `.`-prefixed (not leading `--`) so GNU grep does not parse them
  # as options; the leading `.` matches the space that always precedes the flag in real commands.
  if printf '%s' "$cmd" | grep -Eiq '.(-(kube-)?context[[:space:]=][^[:space:]]*prod)|[[:space:]]-n[[:space:]]+[^[:space:]]*prod' \
     && printf '%s' "$cmd" | grep -Eiq '(kubectl|helm)[[:space:]]([^|]*[[:space:]])?(apply|delete|create|replace|patch|scale|rollout|upgrade|install|uninstall|destroy)'; then
    { printf '%s' '13: mutating operation against a production context - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eq '(^[[:space:]]*|[;&|][[:space:]]*)([A-Z_]*ENV)=prod[a-z]*[[:space:]]' \
     && printf '%s' "$cmd" | grep -Eiq '(migrate|deploy|apply|reset|drop|delete|destroy|publish|flush|truncate|prune)'; then
    { printf '%s' '13: destructive/deploy command in a production environment - human-gated.'; return 1; }
  fi
  if printf '%s' "$cmd" | grep -Eiq '.(--(env|environment)[[:space:]=]prod)' \
     && printf '%s' "$cmd" | grep -Eiq '(migrate|deploy|apply|reset|drop|delete|destroy|publish|flush|truncate|prune)'; then
    { printf '%s' '13: destructive/deploy command targeting production - human-gated.'; return 1; }
  fi
  return 0
}

# guard_check_mcp "<tool>" "<allowlist>" "<overrides>": ALLOW (return 0) / DENY (return 1 + reason).
# Pure: the adapter loads the policy and passes it in (the core never reads a file).
#   <tool>      a Claude MCP tool name, mcp__<server>__<action> (action = segment after the last __)
#   <allowlist> newline list of exact mcp__server__action OR mcp__server__* wildcards (explicit permit)
#   <overrides> newline list of "mcp__server__action=class" (reclassify; class 'read'/'data.read' => allow)
# Decision: allowlist > override-class > tokenized action-verb heuristic > fail-closed deny.
#   The heuristic tokenizes the action (camelCase->snake, lowercased): the first token must be a
#   read verb to allow, and ANY destructive verb token downgrades to deny (so get_and_delete /
#   fetchAndExport deny; list_deployments / get_updates stay read - the noun is not the verb).
# secret.read (A8 family 6) is deny-by-default by NAME: an action naming secret material, or a
# known secret-store server on a read, is denied even when a read verb leads.
# Honest ceiling: classifies by what the NAME reveals; a renamed action (get_data that exfiltrates),
# a secret read via a generic-named server/action (mcp__storage__read_blob), a server wildcard that
# admits a destructive tool, and real egress are NOT caught here — the platform egress allowlist +
# the 11c sandbox are the real controls (docs/enterprise/platform-safety-boundary.md).
guard_check_mcp() {
  t=$1; al=$2; ov=$3
  # 1. explicit allowlist: exact tool, or its server wildcard (mcp__server__*)
  if printf '%s\n' "$al" | grep -qxF -- "$t" 2>/dev/null; then return 0; fi
  if printf '%s\n' "$al" | grep -qxF -- "${t%__*}__*" 2>/dev/null; then return 0; fi
  # 2. class: a per-tool override wins; else heuristic on the action segment.
  act=${t##*__}
  _rest=${t#mcp__}; srv=$(printf '%s' "${_rest%%__*}" | tr 'A-Z' 'a-z')  # server segment, lowercased
  cls=$(printf '%s\n' "$ov" | while IFS='=' read -r k v; do [ "$k" = "$t" ] && { printf '%s' "$v"; break; }; done || true)
  if [ -z "$cls" ]; then
    # Tokenize the action: split camelCase to snake, lowercase, turn _/- into spaces.
    # Whole-token verb matching keeps legit compounds read (list_deployments, get_updates -
    # 'deployments'/'updates' are not the verbs 'deploy'/'update') while downgrading a read-
    # prefixed action that carries a destructive verb token (get_and_delete, fetchAndExport).
    rverbs=' read get list search query fetch describe show view find count '
    dverbs=' delete drop destroy remove truncate reset write update create insert upsert patch put set upload publish deploy send post email notify apply merge push revoke rotate export download '
    norm=$(printf '%s' "$act" | sed 's/\([a-zA-Z0-9]\)\([A-Z]\)/\1_\2/g' | tr 'A-Z_-' 'a-z  ')
    first=${norm%% *}
    cls=unknown
    case "$rverbs" in *" $first "*) cls=read ;; esac
    for tok in $norm; do
      case "$dverbs" in *" $tok "*) cls=destructive; break ;; esac
    done
    # secret-material READ is deny-by-default even when a read verb leads (A8 family 6 - the read
    # half of exfil). Catch it by NAME: (a) the action names secret material, or (b) the server is
    # a known secret store on a read. Ceiling: a secret read via a generic-named server/action
    # (e.g. mcp__storage__read_blob holding a secret) is NOT caught - that is the 11c sandbox's job.
    if [ "$cls" = "read" ] && printf '%s' "$act" | grep -Eiq 'secret|credential|passphrase|password|api[_-]?key|private[_-]?key|access[_-]?key|secret[_-]?key|auth[_-]?token|access[_-]?token'; then
      cls=secret.read
    fi
    if [ "$cls" = "read" ] && printf '%s' "$srv" | grep -Eiq 'vault|1password|onepassword|secretsmanager|secrets[_-]?manager|secret[_-]?manager|keyvault|key[_-]?vault|credstash|doppler|infisical|akeyless'; then
      cls=secret.read
    fi
  fi
  case "$cls" in
    read|data.read) return 0 ;;
    secret.read) printf '13: MCP tool %s reads secret/credential material - deny-by-default (the read half of exfil; A8 family 6). Allowlist it in .claude/mcp-policy.json if intended.' "$t"; return 1 ;;
    unknown) printf '13: MCP tool %s is not classifiable as read-only - denied (fail-closed). Allowlist it in .claude/mcp-policy.json if safe.' "$t"; return 1 ;;
    *) printf '13: MCP tool %s is a destructive/egress capability (%s) - human-gated. Allowlist it in .claude/mcp-policy.json if intended.' "$t" "$cls"; return 1 ;;
  esac
}

# guard_check_path "<path>": print reason + return 1 if denied, else 0.
# Moved from guard.sh:245-265 (drop the jq line — caller passes the path).
guard_check_path() {
  fp=$1
  # CP-8c: an adapter that can prove the protected repo root passes it as $2. When the target is a
  # dev clone (guard_dev_clone_relaxable), the CONTROL-PLANE denies below relax — the secret-write
  # deny does NOT. No root passed (kit-guard CLI, older adapters) => _cp8c_relax=0 => today's
  # behavior (fail-safe).
  _cp8c_root=${2:-}
  _cp8c_relax=0
  if [ -n "$_cp8c_root" ] && guard_dev_clone_relaxable "$fp" "$_cp8c_root"; then _cp8c_relax=1; fi
  fpn=$(printf '%s' "$fp" | sed -e 's#//*#/#g' -e 's#/\./#/#g' -e 's#^\./##' -e 's#/*$##' -e ':a' -e 's#[^/]*/\.\./##' -e 'ta')
  base=$(basename "$fp" 2>/dev/null || printf '%s' "$fp")
  if ! selfedit_allowed && [ "$_cp8c_relax" = 0 ] && { is_control_plane_path "$fp" || is_control_plane_path "$fpn"; }; then
    printf '%s' '13: modifying the guard / its config / CI gates is denied (control-plane integrity). Set KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.'; return 1
  fi
  # WS1: validate by basename when the NORMALIZED path has no real parent directory — either it is a
  # bare name, OR it still ESCAPES its root (a leading/unresolved `..` the fixpoint could not consume),
  # which cannot be trusted by directory. A path with a genuine parent dir (`.vscode/settings.json`) is
  # matched precisely by is_control_plane_path above, so the net is skipped only there. This closes the
  # `./settings.json`, `a/../guard.sh`, multi-`..`, trailing-slash, AND leading-`../name` bypasses while
  # still allowing an innocent `.vscode/settings.json` / `app/config/settings.json`.
  if ! selfedit_allowed && [ "$_cp8c_relax" = 0 ]; then
    _bare=1
    case "$fpn" in
      ..|../*|*/../*) _bare=1 ;;
      */*)           _bare=0 ;;
    esac
    if [ "$_bare" = 1 ]; then
      case "$base" in
        guard.sh|guard-core.sh|kit-guard|pre-push|settings.json|settings.local.json|mcp-policy.json|CODEOWNERS|.meta-control-last|meta-control-log.md|\
        .gitleaks.toml|.gitleaksignore|.semgrepignore|.trivyignore|.checkov.yaml|.checkov.yml)
          printf '13: modifying a control-plane file (%s) is denied (control-plane integrity). Set KIT_GUARD_SELFEDIT=1 for deliberate human maintenance.' "$base"; return 1 ;;
      esac
    fi
  fi
  case "$base" in
    .env.example|.env.sample|.env.template|.env.dist) return 0 ;;
  esac
  case "$fp" in
    *.env|*/.env|*.env.*|*.pem|*.key|*id_rsa*|*/secrets/*|*/secret/*|secrets/*|secret/*)
      printf '13: writing secret material (%s) - human-gated (use .env.example + a secrets manager).' "$base"; return 1 ;;
  esac
  return 0
}

# guard_check_push <remote-ref> <local-sha> <remote-sha>: print reason + return 1 if denied.
# Ref-based (more precise than the command-string git rules): real non-fast-forward detection.
guard_check_push() {
  remote_ref=$1; local_sha=$2; remote_sha=$3
  zero=0000000000000000000000000000000000000000
  case "$remote_ref" in
    refs/heads/main|refs/heads/master)
      if [ "$local_sha" = "$zero" ]; then
        printf '%s' '13: deleting main/master is destructive and bypasses review - human-gated.'; return 1
      fi
      printf '%s' '13: pushing directly to main/master bypasses review - open a PR (human-gated).'; return 1 ;;
  esac
  # force-push / non-fast-forward to ANY branch: remote tip not an ancestor of the new tip.
  if [ "$remote_sha" != "$zero" ] && [ "$local_sha" != "$zero" ]; then
    if ! git merge-base --is-ancestor "$remote_sha" "$local_sha" 2>/dev/null; then
      printf '%s' '13: non-fast-forward (force) push rewrites published history - human-gated.'; return 1
    fi
  fi
  return 0
}

# shellcheck shell=sh
# =============================================================================
# guard-core.additions.sh (Slice B) — the EXACT snippet apply.py appends to
# .claude/hooks/guard-core.sh (after guard_check_push, before EOF). Not a
# standalone script: a function fragment sourced with the rest of the core.
# =============================================================================

# guard_check_skill "<skill_name>": the roster-authority dial (Slice B, opt-in, ships OFF).
# Prints a verdict TOKEN on line 1 (allow|ask|deny) and, for ask/deny, a reason on line 2+;
# ALWAYS returns 0 — the adapter (guard.sh) maps the token to a permission decision.
#
# Dial source: KIT_ROSTER_GUARD (per-session override) wins; else MODE= in .kit/roster.conf
# (repo-root-relative; path overridable via KIT_ROSTER_CONF for tests, mirroring
# RUNAWAY_BUDGET_CONFIG). The config file is itself control-plane, so an agent cannot flip the
# dial (see is_control_plane_path + the command/redirect matchers).
#
# FAIL-SAFE toward OFF (the load-bearing invariant): any unreadable/absent/garbage config, or a
# MODE that is not exactly ask|deny, routes to `allow`. A config error must NEVER wedge the
# session — the roster-authority FLOOR contract (CLAUDE.md/AGENTS.md) still steers by preference.
#
# Namespace match resists spoofing: the namespace is the part before the FIRST ':' (no colon =>
# the whole string), trimmed and lowercased, then whole-token matched against BLOCKLIST. So
# `Superpowers:x` (capitalized) and bare `superpowers` are BOTH caught, while `x::superpowers`
# (namespace `x`) and any non-blocklisted namespace (figma/vercel/LSPs) are allowed.
guard_check_skill() {
  _sk=$1
  _conf="${KIT_ROSTER_CONF:-.kit/roster.conf}"

  # 1. mode: session override wins; else MODE= from config; else empty (=> off). Unreadable => off.
  _mode="${KIT_ROSTER_GUARD:-}"
  if [ -z "$_mode" ] && [ -r "$_conf" ]; then
    _mode=$(grep -E '^[[:space:]]*MODE[[:space:]]*=' "$_conf" 2>/dev/null | tail -n1 \
      | sed -E 's/^[[:space:]]*MODE[[:space:]]*=[[:space:]]*//; s/#.*$//; s/["'"'"']//g; s/[[:space:]].*$//')
  fi
  _mode=$(printf '%s' "$_mode" | tr 'A-Z' 'a-z')
  # 2. fail-safe: only ask|deny are active; off / empty / garbage => allow.
  case "$_mode" in
    ask|deny) : ;;
    *) printf 'allow\n'; return 0 ;;
  esac

  # 3. namespace = part before the first ':'; trim ws; lowercase (spoof-resistant).
  _ns=${_sk%%:*}
  _ns=$(printf '%s' "$_ns" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | tr 'A-Z' 'a-z')
  [ -n "$_ns" ] || { printf 'allow\n'; return 0; }

  # 4. blocklist (fail-safe empty if unreadable): whole-token membership, never substring.
  _bl=''
  if [ -r "$_conf" ]; then
    _bl=$(grep -E '^[[:space:]]*BLOCKLIST[[:space:]]*=' "$_conf" 2>/dev/null | tail -n1 \
      | sed -E 's/^[[:space:]]*BLOCKLIST[[:space:]]*=[[:space:]]*//; s/#.*$//; s/["'"'"']//g' | tr 'A-Z' 'a-z')
  fi
  case " $_bl " in
    *" $_ns "*) : ;;
    *) printf 'allow\n'; return 0 ;;
  esac

  # 5. blocklisted namespace under an active mode => emit the mode + a MODE-APPROPRIATE reason.
  #    ask: the user is prompted and just approves to proceed (a soft nudge, not a block).
  #    deny: hard-blocked; the only escape is the per-session KIT_ROSTER_GUARD=off override.
  printf '%s\n' "$_mode"
  if [ "$_mode" = ask ]; then
    printf 'kit prefers its own roster (skills/; see skills/using-skills/SKILL.md for the foreign->kit equivalent). Approve this prompt to use `%s` anyway.\n' "$_sk"
  else
    printf 'kit prefers its own roster (skills/; see skills/using-skills/SKILL.md for the foreign->kit equivalent). To use `%s` anyway, set KIT_ROSTER_GUARD=off for this session.\n' "$_sk"
  fi
  return 0
}
