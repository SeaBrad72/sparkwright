#!/bin/sh
# new.sh — `sparkwright new`: one command, five questions, from a kit checkout to an incepted project.
#   sh scripts/new.sh <dest-dir> [--stack S] [--team solo|team] [--board md|jira] [--harness H[,H...]] [--name N] [--noninteractive] [--selftest]
# It wraps adopter-export and incept and never forks them: export, toolchain check, incept, preflight, in that order. Interactive by default
# (it asks only what the flags left open); with --noninteractive all five flags are required. Exit: 0 ok · 1 a step failed (its stop line is
# printed) · 2 usage or a refused answer (nothing was written). POSIX sh; dash-clean.
# What it changes: Creates <dest-dir> through adopter-export.sh, then incepts it in place through incept.sh; appends an "Owed from Inception" section to <dest-dir>/CLAUDE.md; never writes inside the kit checkout, never writes a dial (.kit/dials.conf), never asks for, reads or stores a tracker token.
# Guardrails: Every answer is checked against the registries incept uses (profiles/, adapters/, the board and team sets) before any step; each answer is passed to a step as one quoted argument (never a command string, never eval); never passes --allow-nested; a failed step prints its stop line and no later step runs; each step's own output is shown in full, never filtered.
set -eu

ROOT=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)

usage() { echo "usage: new.sh <dest-dir> [--stack S] [--team solo|team] [--board md|jira] [--harness H[,H...]] [--name N] [--noninteractive] [--selftest]" >&2; exit 2; }
die2() { printf '%s\n' "new: $1" >&2; exit 2; }
reqval() { [ "$1" -ge 2 ] || die2 "$2 requires a value"; }
safe() {  # an answer echoed back never carries a control, bidi or zero-width character
  if has_format_char "$1"; then printf '%s' "(an answer with bidi or zero-width characters)"; return 0; fi
  printf '%s' "$1" | tr -d '[:cntrl:]' | cut -c1-60
}

# The registries incept validates against: profiles/ (stacks) and adapters/ (harnesses), derived from the directories, never a second list.
known_stacks() { for _d in "$ROOT"/profiles/*/; do [ -d "$_d" ] && printf '%s ' "$(basename "$_d")" || true; done; }
known_harnesses() { for _d in "$ROOT"/adapters/*/; do [ -f "${_d}adapter.json" ] && printf '%s ' "$(basename "$_d")" || true; done; }
in_list() {  # <space-separated list> <item> -> 0 iff the item is a whole word of the list (an empty or spaced item never is)
  case "$2" in ''|*[[:space:]]*) return 1 ;; esac
  case " $1 " in *" $2 "*) return 0 ;; esac
  return 1
}
# new runs from an un-incepted kit tree (the dev repo or a public-mirror checkout; the mirror carries none of incept's kit-internal markers, so those are not the test):
# the root CLAUDE.md is the principles document, no ENGINEERING-PRINCIPLES.md exists yet, and the root is a git work tree (adopter-export archives HEAD).
is_kit_source() {
  [ ! -e "$ROOT/ENGINEERING-PRINCIPLES.md" ] || return 1
  [ -f "$ROOT/CLAUDE.md" ] && grep -q "Engineering Principles & Definition of Done" "$ROOT/CLAUDE.md" 2>/dev/null || return 1
  git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1
}
# Bidi and zero-width format characters (U+200B-200F, U+202A-202E, U+2066-2069), matched as UTF-8 byte sequences built at run time.
fmt_char() {  # <1-14> -> the UTF-8 bytes of one such character (a constant format per sequence)
  case "$1" in
    1) printf '\342\200\213' ;; 2) printf '\342\200\214' ;; 3) printf '\342\200\215' ;; 4) printf '\342\200\216' ;; 5) printf '\342\200\217' ;;
    6) printf '\342\200\252' ;; 7) printf '\342\200\253' ;; 8) printf '\342\200\254' ;; 9) printf '\342\200\255' ;; 10) printf '\342\200\256' ;;
    11) printf '\342\201\246' ;; 12) printf '\342\201\247' ;; 13) printf '\342\201\250' ;; 14) printf '\342\201\251' ;;
  esac
}
has_format_char() {  # <string> -> 0 iff it holds one
  for _hi in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do
    _hb=$(fmt_char "$_hi")
    [ -n "$_hb" ] || continue   # an empty needle would match everything
    case "$1" in *"$_hb"*) return 0 ;; esac
  done
  return 1
}
# The dest is refused when it resolves, physically, to the kit checkout or under it: the deepest existing parent is resolved (symlinks, a /tmp that is /private/tmp), and a parent whose
# git work tree root is the kit root is refused too (that covers a case-folding filesystem).
dest_inside_kit() {
  _dp=$DEST
  while [ ! -d "$_dp" ]; do _dp=$(dirname "$_dp"); done
  _dreal=$(CDPATH='' cd -P "$_dp" 2>/dev/null && pwd -P) || return 0   # cannot resolve: refuse
  _kreal=$(CDPATH='' cd -P "$ROOT" 2>/dev/null && pwd -P) || return 0
  case "$_dreal/" in "$_kreal"/*) return 0 ;; esac
  _dtop=$(git -C "$_dreal" rev-parse --show-toplevel 2>/dev/null) || _dtop=""
  if [ -n "$_dtop" ]; then
    _dtop=$(CDPATH='' cd -P "$_dtop" 2>/dev/null && pwd -P) || return 0
    [ "$_dtop" != "$_kreal" ] || return 0
  fi
  return 1
}

check_stack() { in_list "$(known_stacks)" "$STACK" || die2 "unknown stack '$(safe "$STACK")' (one of: $(known_stacks))"; }
check_team() { case "$TEAM" in solo|team) : ;; *) die2 "--team is solo or team (got '$(safe "$TEAM")')" ;; esac; }
check_board() { case "$BOARD" in md|jira) : ;; *) die2 "the board is md or jira (got '$(safe "$BOARD")'); other boards stay on incept" ;; esac; }
check_harness() {
  _kh=$(known_harnesses)   # read once, before set -f: its glob must expand
  case "$HARNESS" in ''|*[[:space:]]*) die2 "the harness is a comma list, no spaces, of: $_kh" ;; esac
  _hl=$(printf '%s' "$HARNESS" | tr ',' ' '); _hn=0
  set -f
  for _h in $_hl; do
    in_list "$_kh" "$_h" || die2 "unknown harness '$(safe "$_h")' (one of: $_kh)"
    _hn=$((_hn + 1))
  done
  set +f
  [ "$_hn" -gt 0 ] || die2 "the harness is a comma list of: $_kh"
}
check_name() {
  case "$NAME" in
    *[[:cntrl:]]*) die2 "the project name has control characters (newline or control bytes)" ;;
    *[![:space:]]*) has_format_char "$NAME" && die2 "the project name has a bidi or zero-width character"; : ;;
    *) die2 "the project name is required" ;;
  esac
}
check_given() {  # every value a flag already supplied
  [ -z "$STACK" ] || check_stack
  [ -z "$TEAM" ] || check_team
  [ -z "$BOARD" ] || check_board
  [ -z "$HARNESS" ] || check_harness
  [ -z "$NAME" ] || check_name
}
require_flags() {  # --noninteractive: all five, or exit 2 naming the one that is missing
  [ -n "$STACK" ] || die2 "--noninteractive requires --stack"
  [ -n "$TEAM" ] || die2 "--noninteractive requires --team"
  [ -n "$BOARD" ] || die2 "--noninteractive requires --board"
  [ -n "$HARNESS" ] || die2 "--noninteractive requires --harness"
  [ -n "$NAME" ] || die2 "--noninteractive requires a non-empty --name"
}

# The forge-account question (docs/adoption/vc-hosts.md, Solo or team): 1 = solo, 2 or more = team. The words are accepted as typed.
team_from_answer() {  # <typed answer> -> solo|team on stdout; rc 1 when it maps to nothing
  case "$1" in
    solo|team) printf '%s' "$1" ;;
    ''|*[!0-9]*) return 1 ;;
    1) printf '%s' solo ;;   # MUT-MAP1
    [2-9]|[1-9][0-9]*) printf '%s' team ;;
    *) return 1 ;;
  esac
}
ask() {  # <question> <default> -> ANS. Prints "Question [default]: "; Enter or end of input takes the default
  if [ -n "$2" ]; then printf '%s [%s]: ' "$1" "$2"; else printf '%s: ' "$1"; fi
  ANS=""; read -r ANS || :
  [ -n "$ANS" ] || ANS=$2
}
prompt_answers() {  # exactly the five questions of the design, in order; a flag that is already set is not asked again
  if [ -z "$STACK" ]; then ask "Which stack? ($(known_stacks))" typescript-node; STACK=$ANS; check_stack; fi
  if [ -z "$TEAM" ]; then
    ask "How many forge accounts will this work run under? 1 = solo, 2 or more = team" team
    TEAM=$(team_from_answer "$ANS") || die2 "answer 1, 2 or more, solo or team (got '$(safe "$ANS")')"
  fi
  if [ -z "$BOARD" ]; then ask "Board: markdown or Jira? (md/jira)" md; BOARD=$ANS; check_board; fi
  if [ -z "$HARNESS" ]; then ask "Which harness(es)? (comma-separated, one or more of $(known_harnesses))" claude-code; HARNESS=$ANS; check_harness; fi
  [ -n "$NAME" ] || { ask "Project name?" ""; NAME=$ANS; }   # MUT-SIXTH
  check_name
}

# --- the four steps (design section 4) ---
stop_line() {  # <n> -> the one line printed when step n fails
  case "$1" in
    1) printf '%s\n' "Stopped at step 1 of 4 (export). Nothing was written to $DEST." ;;
    2) printf '%s\n' "Stopped at step 2 of 4 (toolchain). $DEST holds only the export; delete it, install what preflight lists above, then run new again." ;;
    3) printf '%s\n' "Stopped at step 3 of 4 (incept). $DEST holds the export but is not incepted. Fix the line above, then delete $DEST and run new again." ;;
    4) if [ "$OWED_APPENDED" -eq 1 ]; then printf '%s\n' "What is still owed is listed in $DEST/CLAUDE.md under \"## Owed from Inception\"."; fi
       printf '%s\n' "Stopped at step 4 of 4 (preflight). The project is incepted at $DEST. Fix what preflight lists above, then run it there again." ;;
  esac
}
run_step() {  # <n> <label> <function>: banner, run, and on failure the stop line and exit 1
  printf '%s\n' "Step $1 of 4: $2"
  if "$3"; then return 0; fi
  stop_line "$1" >&2
  exit 1   # MUT-CONTINUE
}
need_dest() { [ -d "$DEST" ] || { printf '%s\n' "new: $DEST does not exist (the earlier step wrote nothing)" >&2; return 1; }; }
run_export() { ( cd "$ROOT" && sh scripts/adopter-export.sh "$DEST" --profile "$STACK" ); }
# The pre-push guard is installed by incept, so before incept preflight may refuse on the guard alone: that is expected and does not stop new.
# Any other refusal (a MISS line for a tool, the runtime floor) stops it. The refusal is read from the output, so the output is captured and shown first.
guard_only() {  # <preflight output> -> 0 iff the only refusal is the pre-push guard's
  printf '%s\n' "$1" | grep -q '^  MISS pre-push guard' || return 1
  if printf '%s\n' "$1" | grep -v '^  MISS pre-push guard' | grep -q '^  MISS '; then return 1; fi
  if printf '%s\n' "$1" | grep -q 'ERROR: unsupported runtime'; then return 1; fi
  return 0
}
run_toolchain() {
  need_dest || return 1
  _tc_rc=0
  _tc_out=$( cd "$DEST" && sh scripts/preflight.sh --stack "$STACK" --boundary-advisory 2>&1 ) || _tc_rc=$?
  printf '%s\n' "$_tc_out"
  [ "$_tc_rc" -ne 0 ] || return 0
  if guard_only "$_tc_out"; then return 0; fi   # MUT-GUARDONLY
  return 1
}
run_incept() {
  need_dest || return 1
  ( cd "$DEST" && sh scripts/incept.sh --noninteractive --name "$NAME" --intent-owner "[owed]" --stack "$STACK" --team "$TEAM" --backlog "$BOARD" --harness "$HARNESS" )   # MUT-DIAL
}
# A boundary or egress FAIL is owed, not a stop (SWAS-881); a MISS, the runtime floor and any other refusal still exit 1.
run_final_preflight() {
  need_dest || return 1
  ( cd "$DEST" && sh scripts/preflight.sh --stack "$STACK" --boundary-advisory ) || return 1   # MUT-STEP4ADV MUT-STEP4RC
}

# --- the owed list (design section 5): printed at the end and appended to the project's CLAUDE.md ---
owed_items() {
  printf '%s\n' "- Intent owner: stamped as [owed] in README.md and CLAUDE.md (it seeds no CODEOWNERS rule); a person names the real owner."
  printf '%s\n' "- CI platform: github, the default; change it only on purpose."
  printf '%s\n' "- Mode: lean, the default (incept --mode)."   # not incept's stamped field name: this list is appended to CLAUDE.md, and only incept may name that field (mode-enforcement-blind)
  printf '%s\n' "- Operator fluency: undeclared; declare it in CLAUDE.md when you know it."   # MUT-OWED
  printf '%s\n' "- Database archetype: the stack's default; strip or keep the database to match the project."
  printf '%s\n' "- Deploy target: choose one (docs/adoption/DEPLOYMENT-ENVIRONMENT.md)."
  printf '%s\n' "- Charter: write the problem, vision, success metrics and scope in CLAUDE.md."
  printf '%s\n' "- ADR-000: record the real stack decision and its fit rationale in docs/architecture/ADR-000-stack.md."
  printf '%s\n' "- Harness fit: record why the chosen harness fits."
  printf '%s\n' "- Roles: assign them in CLAUDE.md."
  printf '%s\n' "- Autonomy tiers: declare them in CLAUDE.md."
  printf '%s\n' "- SLO: declare the SLO and error-budget posture in CLAUDE.md."
  printf '%s\n' "- SECURITY.md: add the real disclosure channel once the repository exists (there is no origin yet)."
  printf '%s\n' "- Branch protection: once the repository and its first CI run exist, run sh scripts/branch-protection-apply.sh --replace on an unprotected main."
  printf '%s\n' "- Agent forge account: give the agent its own limited forge account (docs/operations/forge-identity-switch.md)."
  printf '%s\n' "- First push: a person creates the project's repository on your forge and adds it as origin; then push main. Until then, while any agent-boundary part is off, preflight reports the declaration UNTRUSTED (no origin remote)."   # MUT-FIRSTPUSH
  printf '%s\n' "- Agent boundary: if sh scripts/preflight.sh prints any FAIL boundary or FAIL egress line, follow its Fix or Remedy line (a person acts, for example merging the user-level block into ~/.claude/settings.json, or declares an opt-out in .kit/boundary-optout.conf), then re-run it to confirm."   # MUT-BOUNDARYOWED
  if [ "$BOARD" = jira ]; then
    printf '%s\n' "- Tracker conf: set base_url and project in .kit/tracker.conf, and fill the minimum day-one rows of JIRA-SETUP.md."
    printf '%s\n' "- Tracker secrets: A person sets KIT_TRACKER_USER and KIT_TRACKER_TOKEN as repository Actions secrets (and in their own shell, if they use one). See JIRA-SETUP.md, minimum day-one rows. The agent does not set them."
    printf '%s\n' "- Waiver row: a person fills [owner] and [security-owner] on the board-governance row of WAIVER-REGISTER.md (the agent may propose the text; the guard refuses its write to that file); until a person does, the first PR is red."
    printf '%s\n' "- Required check: bind tracker-board-gates to branch protection before the first PR."
  fi
  if [ "$TEAM" = solo ]; then
    printf '%s\n' "- Declare solo: the repository reads team until this merges. (1) Open a PR that creates .kit/dials.conf with the line MERGE_RELATIONSHIP=solo. (2) Run sh scripts/promotion-verify.sh record on that PR's head sha: class control-plane, your own words in --token, your name in --go-by. (3) Merge that PR yourself, by hand: it is the last merge by hand, because once it has merged sh scripts/sparkwright doctor prints the handover line and from then on actuate and land merge on your recorded GO. See docs/adoption/vc-hosts.md, Solo or team."
  fi
}
append_owed() {  # the owed list into <dest>/CLAUDE.md; never through a symlink
  _ao="$DEST/CLAUDE.md"
  [ -f "$_ao" ] && [ ! -L "$_ao" ] || return 1
  { printf '\n## Owed from Inception\n\n'; printf '%s\n' "Written by sparkwright new: what it chose for you, and what a person still owes."; owed_items; } >> "$_ao"
}
print_owed() {
  if [ "$OWED_APPENDED" -eq 1 ]; then
    printf '\n%s\n' "Owed from Inception (also in $DEST/CLAUDE.md under \"## Owed from Inception\"):"
  else
    printf '\n%s\n' "Owed from Inception:"
  fi
  owed_items
}

# --- the selftest: cells N1-N11 of the design and their mutants ---
SELFTEST_BAD=0; SELFTEST_QUIET=0; SEQ=0
chk() {  # <0 ok | 1 bad> <message>
  if [ "$1" -eq 0 ]; then
    [ "$SELFTEST_QUIET" -eq 1 ] || echo "PASS: $2"
  else
    SELFTEST_BAD=$((SELFTEST_BAD + 1))
    [ "$SELFTEST_QUIET" -eq 1 ] || echo "FAIL: $2"
  fi
}
has() { case "$OUT" in *"$1"*) chk 0 "$2" ;; *) chk 1 "$2 (missing: $1)" ;; esac; }
hasnt() { case "$OUT" in *"$1"*) chk 1 "$2 (found: $1)" ;; *) chk 0 "$2" ;; esac; }
show_out() {  # the first 15 lines of the last run, indented, control characters stripped (kept bounded)
  [ "$SELFTEST_QUIET" -eq 1 ] || printf '%s\n' "$OUT" | head -n 15 | tr -d '\000-\010\013-\037\177' | sed 's/^/    | /'
}
rc_is() { if [ "$RC" -eq "$1" ]; then chk 0 "$2"; else chk 1 "$2 (rc $RC, wanted $1)"; show_out; fi; }
g() { git -c user.name=new-selftest -c user.email=new-selftest@invalid -c commit.gpgsign=false -c init.defaultBranch=main -c core.hooksPath=/dev/null "$@"; }   # every selftest git call sets its own identity and config
file_has() { if grep -qF -- "$2" "$1" 2>/dev/null; then chk 0 "$3"; else chk 1 "$3 (missing: $2)"; fi; }
exists() { if [ -e "$1" ]; then chk 0 "$2"; else chk 1 "$2 (absent: $1)"; fi; }
absent() { if [ -e "$1" ]; then chk 1 "$2 (present: $1)"; else chk 0 "$2"; fi; }
ordered() {  # <message> <needle>... each in OUT, on strictly rising lines (first occurrence)
  _om=$1; shift; _prev=0; _ob=0
  for _n in "$@"; do
    _l=$(printf '%s\n' "$OUT" | grep -n -F -- "$_n" | head -n 1 | cut -d: -f1)
    if [ -z "$_l" ] || [ "$_l" -le "$_prev" ]; then _ob=1; break; fi
    _prev=$_l
  done
  chk "$_ob" "$_om"
}
after_has() {  # <marker> <needle> <message>: needle appears in OUT after the marker line
  _ah=$(printf '%s\n' "$OUT" | sed -n "/$1/,\$p")
  case "$_ah" in *"$2"*) chk 0 "$3" ;; *) chk 1 "$3 (missing after '$1': $2)" ;; esac
}
mk_kit() {  # -> KITDIR: a fresh clone of the fixture kit
  SEQ=$((SEQ + 1)); KITDIR="$W/kit$SEQ"
  g clone -q "$KIT0" "$KITDIR"
}
mk_dir() { SEQ=$((SEQ + 1)); MKD="$W/d$SEQ"; mkdir -p "$MKD"; }
nrun() {  # <kit> <home> <ci|human> <stdin-file> args... -> OUT, RC. The env is the cell's: a settled HOME, CI mode or not, no tracker variable
  _nk=$1; _nh=$2; _nm=$3; _ni=$4; shift 4
  # A child's git reads no ambient config: no XDG or global file, no system file.
  if [ "$_nm" = ci ]; then
    OUT=$(env -u SANDBOX_RUNTIME -u XDG_CONFIG_HOME -u GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM=1 HOME="$_nh" CI=true PATH="${NPATH:-$PATH}" sh "$_nk/scripts/new.sh" "$@" < "$_ni" 2>&1) && RC=0 || RC=$?
  else
    OUT=$(env -u SANDBOX_RUNTIME -u CI -u GITHUB_ACTIONS -u XDG_CONFIG_HOME -u GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM=1 HOME="$_nh" PATH="${NPATH:-$PATH}" sh "$_nk/scripts/new.sh" "$@" < "$_ni" 2>&1) && RC=0 || RC=$?
  fi
}
# The cells that must reach a green preflight must not depend on the runner's toolchain: a shim dir first on PATH holds fake node (at the
# stack's declared floor) and fake npm, the two tools preflight's stack_tools lists for typescript-node. N8 builds its own below-floor node instead.
shim_on() { NPATH="$SHIM:$PATH"; }
shim_off() { NPATH=""; }

cell_n1() {  # solo / md, flags form
  mk_dir; _d=$MKD/proj
  shim_on
  nrun "$1" "$HOME_OK" ci /dev/null "$_d" --stack typescript-node --team solo --board md --harness claude-code --name "Solo One" --noninteractive
  shim_off
  rc_is 0 "N1 solo/md flags run exits 0"
  ordered "N1 steps 1-4 run in order" "Step 1 of 4" "Step 2 of 4" "Step 3 of 4" "Step 4 of 4"
  after_has "Step 4 of 4" "All prerequisites present." "N1 the final preflight is green"
  hasnt "Stopped at step" "N1 no step stopped"
  has "- Declare solo:" "N1 the declaring-PR steps are printed and owed"
  has "MERGE_RELATIONSHIP=solo" "N1 the declaring PR names the dial line"
  has "promotion-verify.sh record" "N1 the declaring PR names the GO record"
  hasnt "KIT_TRACKER" "N1 an md board prints no tracker text"
  _o=$OUT
  if grep -E 'Governance' "$_d/CLAUDE.md" 2>/dev/null | grep -Eq '\): solo( |$)'; then chk 0 "N1 incept stamped Governance: solo"; else chk 1 "N1 incept stamped Governance: solo"; fi
  absent "$_d/.kit/dials.conf" "N1 no dial was written"
  exists "$_d/BACKLOG.md" "N1 BACKLOG.md exists (md board)"
  for _lb in "- Intent owner:" "- CI platform:" "- Mode:" "- Operator fluency:" "- Database archetype:" "- Deploy target:" "- Charter:" "- ADR-000:" "- Harness fit:" "- Roles:" "- Autonomy tiers:" "- SLO:" "- SECURITY.md:" "- Branch protection:" "- Agent forge account:" "- First push:" "- Agent boundary:" "- Declare solo:"; do
    OUT=$_o; has "$_lb" "N1 printed owed item $_lb"
    file_has "$_d/CLAUDE.md" "$_lb" "N1 CLAUDE.md holds owed item $_lb"
  done
  file_has "$_d/CLAUDE.md" "## Owed from Inception" "N1 CLAUDE.md carries the Owed from Inception heading"
  OUT=$( cd "$_d" && env -u SANDBOX_RUNTIME HOME="$HOME_OK" CI=true sh conformance/inception-done.sh --surface < /dev/null 2>&1 ) || :
  has "FAIL: project CLAUDE.md key fields not filled" "N1 the check that reads the intent owner reads [owed] as unfilled"
}
cell_n2() {  # team / jira, tracker variables unset, no network
  mk_dir; _d=$MKD/proj
  shim_on
  nrun "$1" "$HOME_OK" ci /dev/null "$_d" --stack typescript-node --team team --board jira --harness claude-code --name "Team Two" --noninteractive
  shim_off
  rc_is 0 "N2 team/jira flags run exits 0 with no tracker variable set"
  ordered "N2 steps 1-4 run in order" "Step 1 of 4" "Step 2 of 4" "Step 3 of 4" "Step 4 of 4"
  after_has "Step 4 of 4" "All prerequisites present." "N2 the final preflight is green"
  has "A person sets KIT_TRACKER_USER and KIT_TRACKER_TOKEN as repository Actions secrets (and in their own shell, if they use one). See JIRA-SETUP.md, minimum day-one rows. The agent does not set them." "N2 the credential sentence is printed verbatim"
  has "- Tracker conf:" "N2 the tracker conf item is owed"
  has "- Waiver row:" "N2 the waiver-row item is owed"
  has "board-governance" "N2 the board-governance row is named"
  has "tracker-board-gates" "N2 the tracker-board-gates bind is owed"
  hasnt "- Declare solo:" "N2 a team answer owes no declaring PR"
  hasnt "Token:" "N2 no token prompt"
  if grep -E 'Governance' "$_d/CLAUDE.md" 2>/dev/null | grep -Eq '\): team( |$)'; then chk 0 "N2 incept stamped Governance: team"; else chk 1 "N2 incept stamped Governance: team"; fi
  exists "$_d/.kit/tracker.conf" "N2 tracker.conf exists"
  if find "$_d" -name JIRA-SETUP.md 2>/dev/null | grep -q .; then chk 0 "N2 JIRA-SETUP.md exists"; else chk 1 "N2 JIRA-SETUP.md exists"; fi
  absent "$_d/.kit/dials.conf" "N2 no dial was written"
}
cell_n3() {  # interactive: exactly the five questions
  mk_dir; _d=$MKD/proj; printf '\n1\n\n\nThree Name\n' > "$MKD/in"
  shim_on
  nrun "$1" "$HOME_OK" ci "$MKD/in" "$_d"
  shim_off
  rc_is 0 "N3 interactive run exits 0"
  # The prompts end without a newline and stdin is a file, so they share one line with the first banner: cut at the banner. Five prompts hold six ": ",
  # because the board prompt ("Board: markdown or Jira? (md/jira) [md]: ") carries one more; a sixth prompt makes seven.
  _pre=${OUT%%Step 1 of 4*}
  _np=$(printf '%s' "$_pre" | awk '{ n += gsub(/: /, "&") } END { print n + 0 }')
  if [ "$_np" -eq 6 ]; then chk 0 "N3 exactly five prompts"; else chk 1 "N3 exactly five prompts (saw $_np colon-spaces, wanted 6)"; fi
  case "$_pre" in *"Which stack?"*"forge accounts"*"Board"*"harness"*"Project name"*) chk 0 "N3 the prompts come in the designed order" ;; *) chk 1 "N3 the prompts come in the designed order" ;; esac
  if grep -E 'Governance' "$_d/CLAUDE.md" 2>/dev/null | grep -Eq '\): solo( |$)'; then chk 0 "N3 the answer 1 reads solo"; else chk 1 "N3 the answer 1 reads solo"; fi
  exists "$_d/BACKLOG.md" "N3 an empty board answer takes md"
}
cell_n4() {  # every bad or empty answer exits 2 before any step
  mk_dir; _w=$MKD
  _n4() {  # <label> <stdin> <dest-name> args...
    _l4=$1; _s4=$2; _x4=$3; shift 3; printf '%s' "$_s4" > "$_w/in.$_x4"
    nrun "$K4" "$HOME_OK" ci "$_w/in.$_x4" "$_w/$_x4" "$@"
    rc_is 2 "N4 $_l4 exits 2"
    hasnt "Step 1 of 4" "N4 $_l4 ran no step"
    absent "$_w/$_x4" "N4 $_l4 left no dest"
  }
  K4=$1
  _n4 "an unknown stack" "" a --stack nope --team team --board md --harness claude-code --name P --noninteractive
  _n4 "a team answer of 3 in the flags form" "" b --stack typescript-node --team 3 --board md --harness claude-code --name P --noninteractive
  _n4 "the board github" "" c --stack typescript-node --team team --board github --harness claude-code --name P --noninteractive
  _n4 "an unknown harness" "" d --stack typescript-node --team team --board md --harness nope --name P --noninteractive
  _n4 "a name with a newline" "" e --stack typescript-node --team team --board md --harness claude-code --name "$(printf 'a\nb')" --noninteractive
  _n4 "an empty name" "" f --stack typescript-node --team team --board md --harness claude-code --name "" --noninteractive
  _n4 "a missing flag (--board)" "" g --stack typescript-node --team team --harness claude-code --name P --noninteractive
  _n4 "an interactive unknown stack" "nope
" h
  _n4 "an interactive forge answer of 0" "
0
" i
  _n4 "an interactive board answer of github" "

github
" j
  _n4 "an interactive unknown harness" "


nope
" k
  _n4 "an interactive empty name (every default taken)" "



" l
  has "[md]" "N4 the board question shows its default md"
  _n4 "a name with a bidi override" "" m --stack typescript-node --team team --board md --harness claude-code --name "a$(printf '\342\200\256')b" --noninteractive
  nrun "$K4" "$HOME_OK" ci /dev/null ".//x" --stack typescript-node --team team --board md --harness claude-code --name P --noninteractive
  rc_is 2 "N4 a dest of .//x exits 2 (it is not read as /x)"
  nrun "$K4" "$HOME_OK" ci /dev/null "$_w/x/../y" --stack typescript-node --team team --board md --harness claude-code --name P --noninteractive
  rc_is 2 "N4 a dest with a .. component exits 2"
  absent "$_w/y" "N4 a dest with a .. component was not written"
  nrun "$K4" "$HOME_OK" ci /dev/null "$K4/inside" --stack typescript-node --team team --board md --harness claude-code --name P --noninteractive
  rc_is 2 "N4 a dest inside the kit checkout exits 2"
  absent "$K4/inside" "N4 a dest inside the kit checkout was not written"
  ln -s "$K4" "$_w/lnk"
  nrun "$K4" "$HOME_OK" ci /dev/null "$_w/lnk/sub/proj" --stack typescript-node --team team --board md --harness claude-code --name P --noninteractive
  rc_is 2 "N4 a dest under a symlink into the kit exits 2"
  absent "$K4/sub" "N4 nothing was written in the kit through the symlink"
  nrun "$K4" "$HOME_OK" ci /dev/null
  rc_is 2 "N4 no dest-dir exits 2"
  # A public-mirror checkout carries none of incept's kit-internal markers: new must still reach step 1 (a non-empty dest stops it there, cheaply).
  # The marker list is read from incept.sh's KIT_INTERNAL_MARKERS line, the way adopter-export.sh does; an empty list fails the cell.
  _mrks=$(sed -n "s/^KIT_INTERNAL_MARKERS='\\(.*\\)'.*/\\1/p" "$K4/scripts/incept.sh" 2>/dev/null)
  if [ -z "$_mrks" ]; then
    chk 1 "N4 the kit-internal marker list was read from incept.sh (it came back empty)"
  else
    for _mrk in $_mrks; do rm -rf "${K4:?}/$_mrk"; done
    mkdir -p "$_w/mirror"; : > "$_w/mirror/keep.txt"
    nrun "$K4" "$HOME_OK" ci /dev/null "$_w/mirror" --stack typescript-node --team team --board md --harness claude-code --name P --noninteractive
    has "Step 1 of 4: export" "N4 a tree without the kit-internal markers still reaches step 1"
    hasnt "run this from" "N4 a tree without the kit-internal markers is not refused as non-kit"
  fi
}
cell_n5() {  # a non-empty dest stops at step 1; incept never runs
  mk_dir; _d=$MKD/proj; mkdir -p "$_d"; : > "$_d/keep.txt"
  nrun "$1" "$HOME_OK" ci /dev/null "$_d" --stack typescript-node --team team --board md --harness claude-code --name P --noninteractive
  rc_is 1 "N5 a non-empty dest exits 1"
  has "Stopped at step 1 of 4 (export). Nothing was written to $_d." "N5 the step-1 stop line"
  has "refusing to clobber" "N5 adopter-export's own refusal is shown"
  hasnt "Step 2 of 4" "N5 no later step ran"
  absent "$_d/ENGINEERING-PRINCIPLES.md" "N5 incept did not run"
  exists "$_d/keep.txt" "N5 the dest's own file is untouched"
  if [ "$(ls -A "$_d")" = "keep.txt" ]; then chk 0 "N5 nothing else was written"; else chk 1 "N5 nothing else was written"; fi
}
cell_n6() {  # a dest inside a foreign git repo: step 2's preflight refuses it (nesting, preflight.sh) before incept runs; new never passes --allow-nested
  mk_dir; _f=$MKD/foreign; mkdir -p "$_f"; g -C "$_f" init -q; _d=$_f/proj
  nrun "$1" "$HOME_OK" ci /dev/null "$_d" --stack typescript-node --team team --board md --harness claude-code --name P --noninteractive
  rc_is 1 "N6 a dest inside a foreign repo exits 1"
  has "Stopped at step 2 of 4 (toolchain). $_d holds only the export; delete it, install what preflight lists above, then run new again." "N6 the step-2 stop line"
  has "ERROR: this directory" "N6 preflight's own nesting refusal is shown"
  hasnt "Step 3 of 4" "N6 incept did not run after the stop"
  absent "$_d/ENGINEERING-PRINCIPLES.md" "N6 the dest is not incepted"
}
cell_n7() {  # no user-level egress step: a boundary gap is owed, not a stop (SWAS-881)
  mk_dir; _d=$MKD/proj
  shim_on
  nrun "$1" "$HOME_NONE" human /dev/null "$_d" --stack typescript-node --team team --board md --harness claude-code --name P --noninteractive
  shim_off
  rc_is 0 "N7 a HOME without the egress step exits 0"
  hasnt "Stopped at step" "N7 no step stopped"
  has "- Agent boundary:" "N7 the boundary gap is owed"
  exists "$_d/ENGINEERING-PRINCIPLES.md" "N7 the project is incepted"
}
cell_n8() {  # a runtime below the stack's floor stops at step 2, with only the export written
  mk_dir; _d=$MKD/proj; mkdir -p "$MKD/fake"
  printf '#!/bin/sh\necho v18.0.0\n' > "$MKD/fake/node"; chmod +x "$MKD/fake/node"
  NPATH="$MKD/fake:$PATH"
  nrun "$1" "$HOME_OK" ci /dev/null "$_d" --stack typescript-node --team team --board md --harness claude-code --name P --noninteractive
  NPATH=""
  rc_is 1 "N8 a runtime below the floor exits 1"
  has "Stopped at step 2 of 4 (toolchain). $_d holds only the export; delete it, install what preflight lists above, then run new again." "N8 the step-2 stop line"
  has "unsupported runtime" "N8 preflight's own floor refusal is shown"
  hasnt "Step 3 of 4" "N8 incept did not run"
  exists "$_d/scripts/incept.sh" "N8 the dest holds the export"
  absent "$_d/ENGINEERING-PRINCIPLES.md" "N8 the dest is not incepted"
}
cell_n9() {  # a guard-only refusal before incept is not a stop; a guard plus a tool miss is
  mk_dir; _w=$MKD
  # A stub preflight for this cell's kit: its first call (new's step 2) refuses, every later call (incept's own, step 4) passes.
  printf '%s\n' '#!/bin/sh' \
    'if [ ! -e "$N9_STATE" ]; then' \
    '  : > "$N9_STATE"' \
    '  echo "  MISS pre-push guard - fixture"' \
    '  [ "${N9_MODE:-}" = both ] && echo "  MISS jq - fixture"' \
    '  exit 1' \
    'fi' \
    'echo "All prerequisites present."' \
    'exit 0' > "$1/scripts/preflight.sh"
  ( cd "$1" && g add -A && g commit -qm stub-preflight )
  shim_on   # the stub preflight needs no tools, but incept's other steps may call node or npm
  N9_STATE="$_w/s1"; N9_MODE=guard; export N9_STATE N9_MODE
  nrun "$1" "$HOME_OK" ci /dev/null "$_w/p1" --stack typescript-node --team team --board md --harness claude-code --name P --noninteractive
  rc_is 0 "N9 a guard-only refusal at step 2 lets new continue"
  has "Step 3 of 4" "N9 incept ran"
  hasnt "Stopped at step 2" "N9 the toolchain stop line is not printed"
  exists "$_w/p1/ENGINEERING-PRINCIPLES.md" "N9 the dest is incepted"
  N9_STATE="$_w/s2"; N9_MODE=both; export N9_STATE N9_MODE
  nrun "$1" "$HOME_OK" ci /dev/null "$_w/p2" --stack typescript-node --team team --board md --harness claude-code --name P --noninteractive
  rc_is 1 "N9 a guard refusal plus a missing tool stops at step 2"
  has "Stopped at step 2 of 4 (toolchain)." "N9 the toolchain stop line is printed for a tool miss"
  shim_off
  absent "$_w/p2/ENGINEERING-PRINCIPLES.md" "N9 the dest is not incepted after a tool miss"
}
cell_n10() {  # a human-mode first run with the egress block set and no origin: exits 0 and owes both acts (SWAS-881). Where every boundary part is ON, preflight reads no declaration and prints no no-origin line; where a part is OFF (a sandbox that cannot start) it prints a FAIL that --boundary-advisory keeps from stopping step 4. N7 grades the exit path.
  mk_dir; _d=$MKD/proj
  shim_on
  nrun "$1" "$HOME_OK" human /dev/null "$_d" --stack typescript-node --team team --board md --harness claude-code --name P --noninteractive
  shim_off
  rc_is 0 "N10 a human-mode first run with no origin exits 0"
  ordered "N10 steps 1-4 run in order" "Step 1 of 4" "Step 2 of 4" "Step 3 of 4" "Step 4 of 4"
  hasnt "Stopped at step" "N10 no step stopped"
  after_has "Step 4 of 4" "All prerequisites present." "N10 step 4's preflight ends green"
  has "- First push:" "N10 the first push is owed"
  has "- Agent boundary:" "N10 the boundary act is owed"
  file_has "$_d/CLAUDE.md" "- First push:" "N10 CLAUDE.md holds the first-push item"
  file_has "$_d/CLAUDE.md" "- Agent boundary:" "N10 CLAUDE.md holds the boundary item"
}
cell_n11() {  # a real step-4 refusal still stops new: the stub refuses only once incept has written ENGINEERING-PRINCIPLES.md (SWAS-881)
  mk_dir; _w=$MKD
  # A stub preflight for this cell's kit, run with the dest as its cwd: steps 2 and incept's own calls pass, step 4 is the one call that sees the file.
  printf '%s\n' '#!/bin/sh' \
    'if [ -e ENGINEERING-PRINCIPLES.md ]; then echo "  MISS jq - fixture"; exit 1; fi' \
    'echo "All prerequisites present."' \
    'exit 0' > "$1/scripts/preflight.sh"
  ( cd "$1" && g add -A && g commit -qm stub-preflight )
  _d=$_w/p1
  shim_on
  nrun "$1" "$HOME_OK" ci /dev/null "$_d" --stack typescript-node --team team --board md --harness claude-code --name P --noninteractive
  shim_off
  rc_is 1 "N11 a step-4 refusal exits 1"
  has "Stopped at step 4 of 4 (preflight). The project is incepted at $_d. Fix what preflight lists above, then run it there again." "N11 the step-4 stop line"
  has "Step 3 of 4" "N11 incept ran"
  hasnt "Stopped at step 2" "N11 the toolchain step passed"
  hasnt "Stopped at step 3" "N11 incept passed"
  exists "$_d/ENGINEERING-PRINCIPLES.md" "N11 the project is incepted"
}

mutant() {  # <label> <file in the kit> <sed script> <cell>...: the script is applied to a COPY in a fresh kit clone; every named cell must go red
  _ml=$1; _mfl=$2; _msd=$3; shift 3
  mk_kit; _mk=$KITDIR
  printf '%s\n' "$_msd" > "$_mk/.mut.sed"
  sed -f "$_mk/.mut.sed" "$_mk/$_mfl" > "$_mk/$_mfl.mut"
  if cmp -s "$_mk/$_mfl" "$_mk/$_mfl.mut"; then chk 1 "mutant $_ml applied (the sed script matched nothing)"; return 0; fi
  cat "$_mk/$_mfl.mut" > "$_mk/$_mfl"; rm -f "$_mk/$_mfl.mut" "$_mk/.mut.sed"
  if ! sh -n "$_mk/$_mfl" 2>/dev/null; then chk 1 "mutant $_ml parses (a mutant that cannot run would read as killed)"; return 0; fi
  ( cd "$_mk" && g add -A && g commit -qm "mutant $_ml" )
  for _mc in "$@"; do
    _sv=$SELFTEST_BAD; SELFTEST_BAD=0; SELFTEST_QUIET=1
    "$_mc" "$_mk"
    rm -rf "$W"/d[0-9]*
    _red=$SELFTEST_BAD; SELFTEST_BAD=$_sv; SELFTEST_QUIET=0
    if [ "$_red" -gt 0 ]; then chk 0 "mutant $_ml reds ${_mc#cell_}"; else chk 1 "mutant $_ml survived ${_mc#cell_} (the cell did not red)"; fi
  done
  rm -rf "$_mk"
}

selftest() {
  if ! is_kit_source; then
    # Only an adopter export (it carries .kit-manifest) has no kit to run from; anywhere else, not being a kit tree is a failure of this check.
    if [ -f "$ROOT/.kit-manifest" ]; then echo "selftest n/a: $ROOT is an adopter export (new runs from the kit)"; return 0; fi
    echo "FAIL: $ROOT is not an un-incepted kit tree and not an adopter export; new --selftest cannot build its fixture"; return 1
  fi
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  unset KIT_TRACKER_USER KIT_TRACKER_TOKEN KIT_TRACKER_BASE_URL KIT_TRACKER_PROJECT JIRA_EMAIL JIRA_TOKEN   # N2 runs with no tracker credential in the environment (a fixed list, nothing is read)
  GIT_AUTHOR_NAME=selftest; GIT_AUTHOR_EMAIL=selftest@kit; GIT_COMMITTER_NAME=selftest; GIT_COMMITTER_EMAIL=selftest@kit
  export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
  W=$(mktemp -d) || { echo "FAIL: no temp dir"; return 1; }
  trap 'rm -rf "$W"' EXIT
  trap 'rm -rf "$W"; exit 130' INT
  trap 'rm -rf "$W"; exit 143' TERM
  HOME_OK="$W/home-ok"; HOME_NONE="$W/home-none"; NPATH=""
  # The shim dir: node prints the stack's declared floor as a version, npm any version; only existence and the floor are read by preflight.
  SHIM="$W/shim"; mkdir -p "$SHIM"
  _floor=$(sed -n '1p' "$ROOT/profiles/typescript-node/scaffold/.nvmrc" 2>/dev/null | tr -cd '0-9')
  [ -n "$_floor" ] || { echo "FAIL: the typescript-node floor could not be read from profiles/typescript-node/scaffold/.nvmrc"; return 1; }
  printf '#!/bin/sh\necho v%s.0.0\n' "$_floor" > "$SHIM/node"
  printf '#!/bin/sh\necho 10.0.0\n' > "$SHIM/npm"
  chmod +x "$SHIM/node" "$SHIM/npm"
  mkdir -p "$HOME_OK/.claude" "$HOME_NONE"
  printf '%s\n' '{"sandbox":{"network":{"strictAllowlist":true,"allowedDomains":[]}}}' > "$HOME_OK/.claude/settings.json"
  # The fixture kit: the tracked files of this checkout as they are now (worktree state), plus new.sh, committed in a throwaway repo.
  KIT0="$W/kit0"; mkdir -p "$KIT0"
  git -c core.quotepath=false -C "$ROOT" ls-files | while IFS= read -r _f; do if [ -f "$ROOT/$_f" ]; then printf '%s\n' "$_f"; fi; done > "$W/list"
  ( cd "$ROOT" && tar -cf - -T "$W/list" ) | ( cd "$KIT0" && tar -xf - )
  cp "$ROOT/scripts/new.sh" "$KIT0/scripts/new.sh"
  if ! ( cd "$KIT0" && g init -q && g add -A -f && g commit -qm base ) >/dev/null 2>&1; then
    echo "FAIL: the fixture kit could not be built"; return 1
  fi
  _cells="cell_n1 cell_n2 cell_n3 cell_n4 cell_n5 cell_n6 cell_n7 cell_n8 cell_n9 cell_n10 cell_n11"
  for _c in $_cells; do
    mk_kit; "$_c" "$KITDIR"
    rm -rf "$KITDIR" "$W"/d[0-9]*   # each cell's dirs go when it ends
  done
  # Mutants: each must red the cell it names.
  mutant "drop-step-2" scripts/new.sh '/# MUT-NOSTEP2$/s/.*/:/' cell_n8
  mutant "any-rc1-is-a-stop" scripts/new.sh '/# MUT-GUARDONLY$/s/guard_only "\$_tc_out"/false/' cell_n9
  mutant "drop-step-4" scripts/new.sh '/# MUT-NOSTEP4$/s/.*/:/' cell_n1
  mutant "drop-step4-advisory" scripts/new.sh '/# MUT-STEP4ADV/s/ --boundary-advisory//' cell_n7
  mutant "drop-first-push" scripts/new.sh '/# MUT-FIRSTPUSH$/d' cell_n10
  mutant "drop-boundary-owed" scripts/new.sh '/# MUT-BOUNDARYOWED$/d' cell_n7 cell_n10
  mutant "step4-rc1-reads-green" scripts/new.sh '/MUT-STEP4RC$/s/|| return 1/|| :/' cell_n11
  mutant "swap-export-and-incept" scripts/new.sh '/# MUT-S1$/s/run_export/run_incept/
/# MUT-S3$/s/run_incept/run_export/' cell_n1 cell_n5
  mutant "continue-after-a-failed-step" scripts/new.sh '/# MUT-CONTINUE$/s/exit 1/:/' cell_n5 cell_n6
  mutant "drop-one-owed-item" scripts/new.sh '/# MUT-OWED$/d' cell_n1
  mutant "sixth-prompt" scripts/new.sh 's| # MUT-SIXTH$|; ask "Anything else?" ""  # MUT-SIXTH|' cell_n3
  mutant "map-1-to-team" scripts/new.sh '/# MUT-MAP1$/s/solo/team/' cell_n3
  mutant "write-a-dial" scripts/new.sh '/# MUT-DIAL$/s|)   # MUT-DIAL$|) \&\& { mkdir -p "$DEST/.kit"; echo MERGE_RELATIONSHIP=solo > "$DEST/.kit/dials.conf"; }   # MUT-DIAL|' cell_n1
  mutant "owed-reads-as-filled-owner" conformance/inception-done.sh 's/(who owns|owed)/who owns/' cell_n1
  if [ "$SELFTEST_BAD" -eq 0 ]; then echo "new --selftest: OK"; return 0; fi
  echo "new --selftest: FAIL ($SELFTEST_BAD)" >&2; return 1
}

# --- main ---
if [ "${1:-}" = "--selftest" ]; then selftest; exit $?; fi

DEST=""; STACK=""; TEAM=""; BOARD=""; HARNESS=""; NAME=""; NONINT=0; ANS=""; OWED_APPENDED=0
while [ $# -gt 0 ]; do
  case "$1" in
    --stack) reqval $# --stack; STACK=$2; shift 2 ;;
    --team) reqval $# --team; TEAM=$2; shift 2 ;;
    --board) reqval $# --board; BOARD=$2; shift 2 ;;
    --harness) reqval $# --harness; HARNESS=$2; shift 2 ;;
    --name) reqval $# --name; NAME=$2; shift 2 ;;
    --noninteractive) NONINT=1; shift ;;
    -h|--help) usage ;;
    -*) die2 "unknown flag '$(safe "$1")'" ;;
    *) [ -z "$DEST" ] || die2 "one <dest-dir> only"; DEST=$1; shift ;;
  esac
done

[ -n "$DEST" ] || usage
is_kit_source || die2 "run this from an un-incepted kit tree (sh scripts/sparkwright new <dest-dir>); an incepted project has nothing to export"
case "$DEST" in *[[:cntrl:]]*) die2 "the dest-dir has control characters" ;; esac
case "$DEST" in *\\*) die2 "the dest-dir has a backslash" ;; esac
case "$DEST" in ./[!/]*) DEST=${DEST#./} ;; esac   # one leading ./ is just "here": new ./proj works
case "/$DEST/" in */./*|*/../*) die2 "the dest-dir must not have a . or .. component" ;; esac
case "$DEST" in /*) : ;; *) DEST="$PWD/$DEST" ;; esac
[ "$DEST" = "/" ] || DEST=${DEST%/}
if dest_inside_kit; then die2 "the dest-dir is inside the kit checkout (resolved physically); choose a directory outside it"; fi

check_given
if [ "$NONINT" -eq 1 ]; then require_flags; else prompt_answers; fi

run_step 1 export run_export   # MUT-S1
run_step 2 toolchain run_toolchain   # MUT-NOSTEP2
run_step 3 incept run_incept   # MUT-S3
if append_owed; then OWED_APPENDED=1; else printf '%s\n' "new: could not append the owed list to $DEST/CLAUDE.md (it is not a regular file); the list below is the only copy" >&2; fi
run_step 4 preflight run_final_preflight   # MUT-NOSTEP4
print_owed
