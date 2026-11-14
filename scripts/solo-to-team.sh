#!/bin/sh
# solo-to-team.sh — `sparkwright team`: move a solo project to team, or add people to a team, without re-running inception.
#   sh scripts/solo-to-team.sh <@handle> [<@handle> ...] [--owner <@handle>] [--selftest]
# A person runs it in the project's checkout, on a branch (never the default branch), on a clean tree. It reads the project's three
# declarations (the MERGE_RELATIONSHIP dial, the CLAUDE.md Governance value, the CODEOWNERS governing rule), refuses every unsafe or
# ambiguous state before it writes, makes the named edits, reads its own result back and undoes the run if it does not read as team.
# It leaves the change in the working tree for `git diff`; it never stages, commits, pushes, calls the forge or reads a credential.
# Exit: 0 ok or already team · 1 the read-back failed and the run was undone · 2 usage or a refusal (nothing was written). POSIX sh; dash-clean.
# What it changes: In the work tree it edits only: the one value token on the Governance line of CLAUDE.md (solo or the unfilled bracket becomes team); the value token of a solo MERGE_RELATIONSHIP line in .kit/dials.conf; the governing * rule of the CODEOWNERS file (the given handles are added; the file is created when there is none). It writes nothing else, in the work tree or outside it.
# Guardrails: Refuses the default branch, a detached HEAD, a dirty tree, any target that is a symlink or resolves outside the work tree, a handle that is not an @login or @org/team (checked as text, never line by line), two CODEOWNERS files, a CRLF CODEOWNERS, an ambiguous dial or Governance line, a one-owner path rule that would shut the new people out, and a result with fewer than two people; every write goes through mktemp in the resolved directory plus mv; it re-reads its result and undoes the run on any disagreement; it never runs eval, never sources a file from the repository, never calls the forge or the network and never reads a token.
set -eu
LC_ALL=C; export LC_ALL
NL='
'
WK=""; TMPF=""; WRITING=0; W_DIAL=0; W_CLAUDE=0; W_CO=none; CO_MKDIR=0
DIAL_PATH=""; DIAL_DIR=""; CL_PATH=""; CL_DIR=""; CO_PATH=""; CO_DIR=""; CO_BASE=""; CO_REL=""
F_DIR=""; F_PATH=""; RDIR=""

usage() { echo "usage: solo-to-team.sh <@handle> [<@handle> ...] [--owner <@handle>] [--selftest]" >&2; exit 2; }
die2() { printf '%s\n' "team: $1" >&2; exit 2; }
safe() {  # a value echoed back never carries a control or format character, and is cut to 60
  printf '%s' "$1" | tr -cd '[:print:]' | cut -c1-60
}
lc() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }
in_words() {  # <space-separated list> <word> -> 0 iff the word is a whole word of the list
  case " $1 " in
    *" $2 "*) return 0 ;;
  esac
  return 1
}
distinct_count() {  # <space-separated handles> -> how many distinct handles, case-folded
  _dc=" "; _dn=0
  for _dw in $1; do
    _dl=$(lc "$_dw")
    case "$_dc" in
      *" $_dl "*) continue ;;
    esac
    _dc="$_dc$_dl "; _dn=$((_dn + 1))
  done
  printf '%s' "$_dn"
}
occurrences() {  # <space-separated handles> <handle> -> how many times the handle appears, case-folded
  _ol=$(lc "$2"); _on=0
  for _ow in $1; do
    if [ "$(lc "$_ow")" = "$_ol" ]; then _on=$((_on + 1)); fi
  done
  printf '%s' "$_on"
}
has_slash() {  # 0 iff a word of the list is an @org/team handle
  for _hw in $1; do
    case "$_hw" in
      */*) return 0 ;;
    esac
  done
  return 1
}
has_dup() {  # 0 iff a handle of the list appears twice, case-folded
  _hn=0
  for _hx in $1; do _hn=$((_hn + 1)); done
  [ "$(distinct_count "$1")" -lt "$_hn" ]
}
is_email() {  # a local part, one @, then a domain with at least one dot and text on both sides of every dot
  case "$1" in
    *@*@*|@*|*@) return 1 ;;
    *@*) : ;;
    *) return 1 ;;
  esac
  _ed=${1#*@}
  case "$_ed" in
    *.*) : ;;
    *) return 1 ;;
  esac
  case ".$_ed." in
    *..*) return 1 ;;
  esac
  case "$_ed" in
    .*|*.) return 1 ;;
  esac
  return 0
}
filter_tokens() {  # <space-separated tokens> -> FT_ALL (the valid handles and emails), FT_HANDLES (the valid handles only)
  FT_ALL=""; FT_HANDLES=""
  for _fw in $1; do
    if valid_handle "$_fw"; then
      FT_ALL="$FT_ALL $_fw"; FT_HANDLES="$FT_HANDLES $_fw"
    elif is_email "$_fw"; then
      FT_ALL="$FT_ALL $_fw"
    fi
  done
}
floor_met() {  # team means two or more people; only a token that is a valid handle or an email counts; an @org/team handle counts as two or more (its members cannot be read)
  filter_tokens "$1"
  if [ "$(distinct_count "$FT_ALL")" -ge 2 ]; then return 0; fi
  has_slash "$FT_HANDLES"
}

# A handle is @login or @org/team, checked as text on the whole argument, never line by line: step one refuses every byte outside
# the allowed set (a newline, CR, space, tab, #, any non-ASCII byte and the empty argument all fail there), step two applies the shape.
valid_handle() {
  case "$1" in
    ''|*[!@A-Za-z0-9._/-]*) return 1 ;;
  esac
  case "$1" in
    @[A-Za-z0-9]*) : ;;
    *) return 1 ;;
  esac
  [ "${#1}" -le 140 ] || return 1
  case "$1" in
    *-) return 1 ;;
  esac
  _vu=${1#@}; _vu=${_vu%%/*}
  case "$_vu" in
    *[!A-Za-z0-9-]*|*-) return 1 ;;
  esac
  [ "${#_vu}" -le 39 ] || return 1
  case "$1" in
    */*)
      _vs=${1#*/}
      case "$_vs" in
        ''|*/*|*[!A-Za-z0-9._-]*|[!A-Za-z0-9]*) return 1 ;;
      esac
      ;;
  esac
  return 0
}
bad_handle() { die2 "'$(safe "$1")' is not a valid handle (write @login or @org/team: letters, digits and - in the name, at most 39 characters; no spaces)"; }
GIVEN=""; GIVENLC=" "
add_given() {  # <valid handle>: appended in the order given; a case-folded duplicate is dropped, the first spelling kept
  _al=$(lc "$1")
  case "$GIVENLC" in
    *" $_al "*) return 0 ;;
  esac
  GIVEN="$GIVEN $1"; GIVENLC="$GIVENLC$_al "   # MUT-FIRSTONLY
}

# --- the physical-path checks: nothing is written through a symlink or outside the work tree ---
in_tree() {
  case "$1/" in
    "$TOP"/*) return 0 ;;
  esac
  return 1
}
resolve_dir() {  # <dir relative to the tree> -> RDIR (physical); rc 1 outside the tree, rc 2 not a directory
  [ -d "$1" ] || return 2
  RDIR=$(CDPATH='' cd -P "$1" 2>/dev/null && pwd -P) || return 1
  if in_tree "$RDIR"; then return 0; fi   # MUT-NORESOLVE
  return 1
}
check_file() {  # <rel path> -> rc 0 a regular file inside the tree (F_DIR, F_PATH set); rc 3 absent (F_DIR set when its directory exists); refuses a symlink or an outside path
  F_DIR=""; F_PATH=""
  _cd=$(dirname "$1"); _cb=$(basename "$1")
  _crc=0; resolve_dir "$_cd" || _crc=$?
  case "$_crc" in
    1) die2 "'$1' resolves outside the work tree (a symlinked directory?): refusing to write through it" ;;
    2) return 3 ;;
  esac
  F_DIR=$RDIR; F_PATH="$RDIR/$_cb"
  if [ -L "$F_PATH" ]; then die2 "'$1' is a symlink: refusing to write through it"; fi
  if [ ! -e "$F_PATH" ]; then return 3; fi
  [ -f "$F_PATH" ] || die2 "'$1' is not a regular file"
  return 0
}

# --- the three declarations, each read by the grammar the kit's own readers use (the stricter prefix where they differ) ---
DIAL_EXPR="s#^([[:space:]]*MERGE_RELATIONSHIP[[:space:]]*=[[:space:]]*[\"']?)solo#\\1team#"   # MUT-DIAL
GOV_EXPR="s#^\\([-*+ ]*\\*\\*Governance\\*\\* (§ solo/team): \\)solo#\\1team#"   # MUT-GOVSOLO
GOV_EXPR_PH="s#^\\([-*+ ]*\\*\\*Governance\\*\\* (§ solo/team): \\)\\[solo / team\\]#\\1team#"
read_dial() {  # -> DIAL (solo | team | absent | unrecognised), DIAL_N (the MERGE_RELATIONSHIP line count). The value rules are land's: comments and quotes stripped, first word.
  DIAL=absent; DIAL_N=0
  if [ -z "$DIAL_PATH" ] || [ ! -f "$DIAL_PATH" ]; then return 0; fi
  DIAL_N=$(grep -c -E '^[[:space:]]*MERGE_RELATIONSHIP[[:space:]]*=' "$DIAL_PATH" || true)
  if [ "$DIAL_N" -lt 1 ]; then return 0; fi
  _dl=$(grep -E '^[[:space:]]*MERGE_RELATIONSHIP[[:space:]]*=' "$DIAL_PATH" | tail -n 1)
  _dv=$(printf '%s' "$_dl" | sed -E "s/^[[:space:]]*MERGE_RELATIONSHIP[[:space:]]*=[[:space:]]*//; s/#.*$//; s/[\"']//g; s/[[:space:]].*$//")
  case "$_dv" in
    solo|team) DIAL=$_dv ;;
    '') DIAL=absent ;;
    *) DIAL=unrecognised ;;
  esac
}
read_gov() {  # -> GOVV (solo | team | placeholder | other | undeclared | loose | ambiguous), _gv the first word
  GOVV=other; _gv=""
  _gn=$(grep -c -e '^[-*+ ]*\*\*Governance\*\* (§ solo/team):' "$CL_PATH" || true)
  _gl=$(grep -c -e '^[-*+[:space:]]*\*\*Governance\*\* (§ solo/team):' "$CL_PATH" || true)
  GOVN=$_gn
  if [ "$_gl" -gt "$_gn" ]; then GOVV=loose; return 0; fi
  if [ "$_gn" -eq 0 ]; then GOVV=undeclared; return 0; fi
  if [ "$_gn" -gt 1 ]; then GOVV=ambiguous; return 0; fi
  _gv=$(sed -n 's#^[-*+ ]*\*\*Governance\*\* (§ solo/team): \([^ ]*\).*$#\1#p' "$CL_PATH")
  _gt=$(sed -n 's#^[-*+ ]*\*\*Governance\*\* (§ solo/team): \(.*\)$#\1#p' "$CL_PATH")
  case "$_gv" in
    solo) GOVV=solo ;;
    team) GOVV=team ;;
    *)
      case "$_gt" in
        "[solo / team]"*) GOVV=placeholder ;;
      esac
      ;;
  esac
}
# CODEOWNERS is last-match-wins: the governing rule is the last active * rule. -> CO_STATE (ok | nogov), GOV_LN, GOVH (its handles, each led by a space),
# CO_INS (the line after which a new rule goes: the end of the leading comment block), PATHREC (each active rule after the governing one, one per line).
read_rule() {  # <CODEOWNERS path>
  CO_STATE=nogov; GOV_LN=0; GOVH=""; CO_INS=0; PATHREC=""
  _rr=$(awk '
{ l = $0; sub(/^[ \t]+/, "", l) }
stop == 0 { if (substr(l, 1, 1) == "#") ci = NR; else stop = 1 }
l == "" || substr(l, 1, 1) == "#" { next }
{
  n = split(l, f, /[ \t]+/); hs = ""
  for (i = 2; i <= n; i++) { if (substr(f[i], 1, 1) == "#") break; hs = hs " " f[i] }
  rn++; rl[rn] = NR; rp[rn] = f[1]; rh[rn] = hs
  if (f[1] == "*") g = rn   # MUT-FIRST
}
END {
  if (g == 0) {
    print "NOGOV " (ci + 0)
    for (j = 1; j <= rn; j++) print "PATH " rl[j] " " rp[j] " |" rh[j]
    exit
  }
  print "GOV " rl[g] rh[g]
  for (j = g + 1; j <= rn; j++) print "PATH " rl[j] " " rp[j] " |" rh[j]
}' "$1") || return 1
  printf '%s\n' "$_rr" > "$WK/rule.lst" || return 1
  while IFS= read -r _rl; do
    [ -n "$_rl" ] || continue
    case "$_rl" in
      "GOV "*) CO_STATE=ok; _g=${_rl#GOV }; GOV_LN=${_g%% *}; GOVH=${_g#"$GOV_LN"} ;;
      "NOGOV "*) CO_INS=${_rl#NOGOV } ;;
      "PATH "*) PATHREC="$PATHREC${_rl#PATH }$NL" ;;
    esac
  done < "$WK/rule.lst"
  return 0
}

# --- what the run prints ---
team_handles() {  # -> TEAMH: the distinct @org/team handles among the ones given, the rule's own and the owner
  TEAMH=""; _seen=" "
  for _th in $GIVEN $GOVH $OWNER; do
    case "$_th" in
      @*/*) : ;;
      *) continue ;;
    esac
    _tl=$(lc "$_th")
    case "$_seen" in
      *" $_tl "*) continue ;;
    esac
    _seen="$_seen$_tl "; TEAMH="$TEAMH $_th"
  done
}
print_team_notice() {
  for _t in $TEAMH; do
    printf '%s\n' "$(safe "$_t") is a team handle. The verb cannot read its members (it never reads the forge); confirm that it has two or more people before you rely on it for review."   # MUT-NOTICE
  done
}
forge_github() {  # 0 unless the project is plainly on another forge (a .gitlab-ci.yml, a .gitlab CODEOWNERS, an origin that is not github.com); local reads only
  if [ -e .gitlab-ci.yml ]; then return 1; fi
  case "$CO_REL" in
    .gitlab/*) return 1 ;;
  esac
  _ou=$(git config --get remote.origin.url 2>/dev/null || true)
  case "$_ou" in
    '') return 0 ;;
    *github.com*) return 0 ;;
  esac
  return 1
}
print_next_steps() {
  printf '%s\n' "Next steps:"
  _lead="1."
  if [ -n "$NEWH" ]; then
    for _nh in $NEWH; do
      printf '%s Invite %s to the repository with write access, and wait until they accept.\n' "$_lead" "$(safe "$_nh")"
      _lead=" "
    done
    if [ "$ALREADY" = 0 ] && ! floor_met "$GOVH0"; then
      printf '%s\n' "   Until at least one of them accepts, nobody can approve your PRs once this merges."
    fi
  else
    printf '%s\n' "1. Check that everyone named on the CODEOWNERS rule has write access to the repository and has accepted."
  fi
  if [ "$LANDREL" = solo ]; then
    printf '%s\n' "2. Read the change (git diff), commit it on this branch and open a PR. It is judged by the solo bar you are leaving: record your GO on its head (promotion-verify.sh record), and land it as you land today."
  else
    printf '%s\n' "2. Read the change (git diff), commit it on this branch and open a PR, then merge it the way you merge your PRs today."
  fi
  if [ "$ALREADY" = 1 ]; then return 0; fi
  printf '%s\n' "3. If the agent works under your account today, give it its own limited forge account (docs/operations/forge-identity-switch.md) and check it with sh scripts/sparkwright doctor --as agent. Team means it has one."
  if forge_github; then
    printf '%s\n' "4. After it merges, an admin runs sh scripts/branch-protection-apply.sh --replace --team (it asks you to type REPLACE). Then sh conformance/branch-protection.sh reads \"settings: enforce_admins=true code_owner_reviews=true ...\", and it reds while either is off."
  else
    printf '%s\n' "4. After it merges, turn on required approvals and code-owner approval in your forge's settings. The kit has no live check for that forge."
  fi
}

# --- the writes: a mktemp file in the resolved directory, then mv; every edited file is kept in one mktemp -d outside the tree for the undo ---
atomic_put() {  # <new content file> <resolved dir> <name> <file to copy the mode from, or empty>
  TMPF=$(mktemp "$2/.$3.XXXXXX") || return 1   # TMPF is global, so undo_all and the EXIT trap can remove it after a signal
  if [ -n "$4" ] && [ -f "$4" ]; then
    cp -p "$4" "$TMPF" || { rm -f "$TMPF"; return 1; }
  else
    chmod 644 "$TMPF" || { rm -f "$TMPF"; return 1; }
  fi
  cat "$1" > "$TMPF" || { rm -f "$TMPF"; return 1; }
  mv -f "$TMPF" "$2/$3" || { rm -f "$TMPF"; return 1; }
  TMPF=""
}
restore_one() {  # <backup> <resolved dir> <name>
  TMPF=$(mktemp "$2/.$3.XXXXXX") || return 1
  cp -p "$1" "$TMPF" || { rm -f "$TMPF"; return 1; }
  mv -f "$TMPF" "$2/$3" || { rm -f "$TMPF"; return 1; }
  TMPF=""
}
undo_all() {  # <cause>
  trap '' INT TERM HUP
  WRITING=0
  if [ -n "$TMPF" ]; then rm -f "$TMPF"; TMPF=""; fi
  _bad=""
  if [ "$W_DIAL" -eq 1 ]; then restore_one "$WK/dial" "$DIAL_DIR" dials.conf || _bad="$_bad .kit/dials.conf"; fi
  if [ "$W_CLAUDE" -eq 1 ]; then restore_one "$WK/claude" "$CL_DIR" CLAUDE.md || _bad="$_bad CLAUDE.md"; fi
  if [ "$W_CO" = edited ]; then
    restore_one "$WK/co" "$CO_DIR" "$CO_BASE" || _bad="$_bad $CO_REL"
  elif [ "$W_CO" = created ]; then
    rm -f "$CO_DIR/$CO_BASE" || _bad="$_bad $CO_REL"
    if [ "$CO_MKDIR" -eq 1 ] && [ -d "$CO_DIR" ]; then rmdir "$CO_DIR" || _bad="$_bad $(dirname "$CO_REL")/"; fi
  fi
  if [ -n "$WK" ]; then rm -rf "$WK"; fi
  printf 'team: %s; the run was undone.\n' "$1" >&2
  if [ -n "$_bad" ]; then printf 'team: could not restore:%s (check git status, then git checkout -- <path>)\n' "$_bad" >&2; fi
}
fail_write() { undo_all "could not write $1"; exit 1; }
readback() {  # -> 0 iff the three files now read as team; RB_WHY says which did not
  RB_WHY=""
  read_dial
  if [ "$DIAL" = solo ]; then RB_WHY=".kit/dials.conf still reads solo"; return 1; fi
  read_gov
  if [ "$GOVV" != team ]; then RB_WHY="CLAUDE.md does not read as team (it reads $GOVV)"; return 1; fi
  if ! read_rule "$CO_PATH"; then RB_WHY="$CO_REL could not be read back"; return 1; fi
  if [ "$CO_STATE" != ok ]; then RB_WHY="$CO_REL has no active * rule"; return 1; fi
  for _rh in $GIVEN $OWNER; do
    if [ "$(occurrences "$GOVH" "$_rh")" -ne 1 ]; then RB_WHY="$CO_REL does not name $(safe "$_rh") exactly once"; return 1; fi
  done
  if ! floor_met "$GOVH"; then RB_WHY="$CO_REL names fewer than two people"; return 1; fi
  return 0
}
check_path_rules() {  # an active rule after the governing one that names fewer than two people shuts everyone else out of those paths; two or more is a notice. Runs on every run that writes.
  PATHNOTE=""
  printf '%s\n' "$PATHREC" > "$WK/paths.lst" || return 1
  while IFS= read -r _pr; do
    [ -n "$_pr" ] || continue
    _pn=${_pr%% *}; _pq=${_pr#* }; _pat=${_pq%% *}; _hs=${_pr#* |}
    filter_tokens "$_hs"; _hsv=$FT_HANDLES
    _pc=$(distinct_count "$FT_ALL")
    if [ "$_pc" -le 1 ] && ! has_slash "$_hsv"; then
      _what="one person"; if [ "$_pc" -eq 0 ]; then _what="no one"; fi
      if [ -n "$NEWH" ]; then
        _who="so$(safe "$NEWH") could not approve those paths"
      elif [ "$_pc" -eq 0 ]; then
        _who="so those paths have no reviewer"
      else
        _who="so nobody besides$(safe "$_hs") can approve those paths"
      fi
      die2 "line $_pn of $CO_REL ('$(safe "$_pat")' owned by$(safe "$_hs")) names $_what, $_who: add people to that rule by hand or remove it, then rerun"
    fi
    if [ -n "$NEWH" ] && { [ "$_pc" -ge 2 ] || has_slash "$_hsv"; }; then
      PATHNOTE="${PATHNOTE}Notice: line $_pn of $CO_REL ('$(safe "$_pat")') already names two or more people; the new handles are not on it, and it was left alone.$NL"
    fi
  done < "$WK/paths.lst"
}
do_writes() {
  CHANGED=""
  WRITING=1
  trap 'undo_all "interrupted"; exit 1' INT TERM HUP
  if [ "$DIAL" = solo ]; then
    cp -p "$DIAL_PATH" "$WK/dial" || fail_write ".kit/dials.conf"
    W_DIAL=1
    sed -E "$DIAL_EXPR" "$DIAL_PATH" > "$WK/dial.new" || fail_write ".kit/dials.conf"
    atomic_put "$WK/dial.new" "$DIAL_DIR" dials.conf "$DIAL_PATH" || fail_write ".kit/dials.conf"
    CHANGED="$CHANGED  .kit/dials.conf: MERGE_RELATIONSHIP solo -> team$NL"
  fi
  if [ "$GOVV" = solo ] || [ "$GOVV" = placeholder ]; then
    cp -p "$CL_PATH" "$WK/claude" || fail_write "CLAUDE.md"
    W_CLAUDE=1
    if [ "$GOVV" = solo ]; then sed "$GOV_EXPR" "$CL_PATH" > "$WK/claude.new" || fail_write "CLAUDE.md"; fi
    if [ "$GOVV" = placeholder ]; then sed "$GOV_EXPR_PH" "$CL_PATH" > "$WK/claude.new" || fail_write "CLAUDE.md"; fi
    atomic_put "$WK/claude.new" "$CL_DIR" CLAUDE.md "$CL_PATH" || fail_write "CLAUDE.md"
    _was=$GOVV
    if [ "$GOVV" = placeholder ]; then _was="[solo / team]"; fi
    CHANGED="$CHANGED  CLAUDE.md: the Governance value $_was -> team$NL"
  fi
  if [ -n "$NEWH" ] || [ "$CO_STATE" != ok ]; then write_codeowners; fi
}
write_codeowners() {
  _add=$NEWH
  if [ "$CO_STATE" = ok ]; then
    cp -p "$CO_PATH" "$WK/co" || fail_write "$CO_REL"
    W_CO=edited
    awk -v gl="$GOV_LN" -v add="$_add" '
NR == gl {
  line = $0
  p = match(line, /[ \t]#/)
  if (p > 0) { head = substr(line, 1, p - 1); tail = substr(line, p + 1) } else { head = line; tail = "" }
  sub(/[ \t]+$/, "", head)
  if (tail == "") print head add; else print head add " " tail
  next
}
{ print }' "$CO_PATH" > "$WK/co.new" || fail_write "$CO_REL"
    atomic_put "$WK/co.new" "$CO_DIR" "$CO_BASE" "$CO_PATH" || fail_write "$CO_REL"
    CHANGED="$CHANGED  $CO_REL: added$(safe "$_add") to the governing * rule$NL"
    return 0
  fi
  _rule="*  $OWNER$_add"
  if [ "$CO_STATE" = nogov ]; then
    cp -p "$CO_PATH" "$WK/co" || fail_write "$CO_REL"
    W_CO=edited
    awk -v ia="$CO_INS" -v rule="$_rule" '
BEGIN { if (ia == 0) print rule }
{ print }
NR == ia { print rule }' "$CO_PATH" > "$WK/co.new" || fail_write "$CO_REL"
    atomic_put "$WK/co.new" "$CO_DIR" "$CO_BASE" "$CO_PATH" || fail_write "$CO_REL"
    CHANGED="$CHANGED  $CO_REL: a new * rule naming $OWNER$_add$NL"
    return 0
  fi
  W_CO=created
  if [ "$CO_MKDIR" -eq 1 ]; then
    mkdir "$CO_DIR" || fail_write "$CO_REL"
  fi
  { printf '%s\n' "# CODEOWNERS (created by sparkwright team). The last matching rule wins." "# Each path below needs a review from one of the people on its rule."; printf '%s\n' "$_rule"; } > "$WK/co.new" || fail_write "$CO_REL"
  atomic_put "$WK/co.new" "$CO_DIR" "$CO_BASE" "" || fail_write "$CO_REL"
  CHANGED="$CHANGED  $CO_REL: created, with a * rule naming $OWNER$_add$NL"
}

# --- the selftest: cells T1-T13 and eighteen mutants ---
SELFTEST_BAD=0; SELFTEST_QUIET=0; SEQ=0
chk() {  # <0 ok | 1 bad> <message>
  if [ "$1" -eq 0 ]; then
    if [ "$SELFTEST_QUIET" -eq 1 ]; then return 0; fi
    echo "PASS: $2"
  else
    SELFTEST_BAD=$((SELFTEST_BAD + 1))
    if [ "$SELFTEST_QUIET" -eq 1 ]; then return 0; fi
    echo "FAIL: $2"
  fi
}
has() {
  case "$OUT" in
    *"$1"*) chk 0 "$2" ;;
    *) chk 1 "$2 (missing: $1)" ;;
  esac
}
hasnt() {
  case "$OUT" in
    *"$1"*) chk 1 "$2 (found: $1)" ;;
    *) chk 0 "$2" ;;
  esac
}
show_out() {
  if [ "$SELFTEST_QUIET" -eq 1 ]; then return 0; fi
  printf '%s\n' "$OUT" | head -n 15 | tr -d '\000-\010\013-\037\177' | sed 's/^/    | /'
}
rc_is() { if [ "$RC" -eq "$1" ]; then chk 0 "$2"; else chk 1 "$2 (rc $RC, wanted $1)"; show_out; fi; }
g() { git -c user.name=team-selftest -c user.email=team-selftest@invalid -c commit.gpgsign=false -c init.defaultBranch=main -c core.hooksPath=/dev/null "$@"; }   # every selftest git call sets its own identity and config
vrun() {  # <repo> args... -> OUT, RC: the verb under test, run in the repo, in a scrubbed environment (no ambient git config, no token)
  _vr=$1; shift
  # shellcheck disable=SC2086
  OUT=$( cd "$_vr" && env -i PATH="${VPATH:-$PATH}" HOME="$W/home" TMPDIR="$W/tmp" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null $VENV sh "$SUT" "$@" 2>&1 ) && RC=0 || RC=$?
}
mk_claude() {  # <Governance value text, or NONE | TWO | TAB>
  case "$1" in
    NONE) printf '%s\n' "# Fixture project" "Notes: solo work is fine; the label (§ solo/team) stays." ;;
    TWO) printf '%s\n' "# Fixture project" "**Governance** (§ solo/team): solo - a." "- **Governance** (§ solo/team): solo - b." ;;
    TAB) printf '%s\n' "# Fixture project"; printf '\t**Governance** (§ solo/team): team - prose.\n' ;;
    *) printf '%s\n' "# Fixture project" "**Governance** (§ solo/team): $1 - prose stays." "Notes: solo work is fine; the label (§ solo/team) stays." ;;
  esac
}
mk_repo() {  # <Governance value | NONE | TWO | TAB> <dial line | -> <CODEOWNERS body in printf %b form | -> -> REPO: committed, clean, on branch feature/x
  SEQ=$((SEQ + 1)); REPO="$W/r$SEQ"; mkdir -p "$REPO"
  mk_claude "$1" > "$REPO/CLAUDE.md"
  if [ "$2" != - ]; then mkdir -p "$REPO/.kit"; printf '%s\n' "$2" > "$REPO/.kit/dials.conf"; fi
  if [ "$3" != - ]; then mkdir -p "$REPO/.github"; printf '%b' "$3" > "$REPO/.github/CODEOWNERS"; fi
  ( g -C "$REPO" init -q && g -C "$REPO" add -A && g -C "$REPO" commit -q -m base && g -C "$REPO" checkout -q -b feature/x ) >/dev/null 2>&1 || { echo "FAIL: a fixture repo could not be built" >&2; exit 1; }
}
commit_all() { g -C "$REPO" add -A && g -C "$REPO" commit -q -m step; }
tree_is() {  # <expected git status --porcelain text in printf %b form> <message>
  printf '%b' "$1" > "$W/exp.st"
  g -C "$REPO" status --porcelain --untracked-files=all > "$W/got.st"
  if cmp -s "$W/exp.st" "$W/got.st"; then chk 0 "$2"; else chk 1 "$2 (tree is: $(tr '\n' ' ' < "$W/got.st"))"; fi
}
file_is() {  # <path> <expected bytes in printf %b form> <message>
  printf '%b' "$2" > "$W/exp"
  if cmp -s "$W/exp" "$1"; then chk 0 "$3"; else chk 1 "$3 (bytes differ in $1)"; fi
}
claude_is() {  # <repo> <Governance value> <message>: CLAUDE.md is the fixture with exactly that value
  mk_claude "$2" > "$W/exp"
  if cmp -s "$W/exp" "$1/CLAUDE.md"; then chk 0 "$3"; else chk 1 "$3 (CLAUDE.md differs)"; fi
}
CO1='* @owner-placeholder\n'
CO2='* @owner-placeholder @second-placeholder\n'

cell_t1() {  # each solo state reaches team; only the named bytes change
  mk_repo solo 'MERGE_RELATIONSHIP=solo' "$CO1"
  vrun "$REPO" @second-placeholder
  rc_is 0 "T1a a solo dial with a solo Governance exits 0"
  has "Each handle must be a person, not the agent's own forge account: the agent never ratifies." "T1a the agent-account rule is printed"
  has "Invite @second-placeholder to the repository with write access" "T1a the invitation is step 1"
  has "Until at least one of them accepts" "T1a the stall warning is printed on a move from solo"
  has "judged by the solo bar you are leaving" "T1a land reads solo, so step 2 names the solo bar"
  has "branch-protection-apply.sh --replace --team" "T1a the protection step is printed"
  tree_is ' M .github/CODEOWNERS\n M .kit/dials.conf\n M CLAUDE.md\n' "T1a exactly the three named files changed"
  file_is "$REPO/.kit/dials.conf" 'MERGE_RELATIONSHIP=team\n' "T1a the dial's value token is the only change"
  claude_is "$REPO" team "T1a CLAUDE.md differs only in the Governance value token"
  file_is "$REPO/.github/CODEOWNERS" '* @owner-placeholder @second-placeholder\n' "T1a the handle is added after the owner"
  mk_repo solo - "$CO1"
  vrun "$REPO" @second-placeholder
  rc_is 0 "T1b an absent dial with a solo Governance exits 0"
  has "the way you merge your PRs today" "T1b land reads team, so step 2 is the plain merge line"
  hasnt "solo bar" "T1b no solo-bar text"
  tree_is ' M .github/CODEOWNERS\n M CLAUDE.md\n' "T1b no dial is written"
  claude_is "$REPO" team "T1b CLAUDE.md differs only in the value token"
  mk_repo solo 'MERGE_RELATIONSHIP = "solo" # x' "$CO1"
  vrun "$REPO" @second-placeholder
  rc_is 0 "T1c a quoted, spaced, commented dial exits 0"
  file_is "$REPO/.kit/dials.conf" 'MERGE_RELATIONSHIP = "team" # x\n' "T1c spacing, quotes and the comment are kept"
  mk_repo '[solo / team]' - "$CO1"
  vrun "$REPO" @second-placeholder
  rc_is 0 "T1d the unfilled placeholder exits 0"
  claude_is "$REPO" team "T1d the whole bracket becomes team, no bracket left"
}
cell_t2() {  # a re-run on the committed result writes nothing
  mk_repo solo 'MERGE_RELATIONSHIP=solo' "$CO1"
  vrun "$REPO" @second-placeholder
  commit_all
  vrun "$REPO" @second-placeholder
  rc_is 0 "T2 a re-run exits 0"
  has "already team: CLAUDE.md declares team, .kit/dials.conf declares no solo, and CODEOWNERS already names every handle given (@second-placeholder); nothing to do." "T2 the no-op line is printed"
  tree_is '' "T2 a re-run writes nothing"
}
cell_t3() {  # an already-team repository is a no-op
  mk_repo team - "$CO2"
  vrun "$REPO" @second-placeholder
  rc_is 0 "T3 Governance team, dial absent, handle on the rule: exits 0"
  has "already team:" "T3 the no-op line is printed"
  tree_is '' "T3 the tree is unchanged"
  mk_repo team 'MERGE_RELATIONSHIP=bogus' "$CO2"
  vrun "$REPO" @second-placeholder
  rc_is 0 "T3 an unrecognised dial with Governance team: exits 0"
  has "already team:" "T3 the no-op line is printed for the unrecognised dial"
  tree_is '' "T3 the unrecognised dial is left alone"
}
cell_t3b() {  # an undeclared or ambiguous Governance is never read as team
  mk_repo NONE - "$CO2"
  vrun "$REPO" @second-placeholder
  rc_is 2 "T3b no Governance field line exits 2"
  has "this verb never adds one" "T3b the refusal says it never adds the line"
  has "**Governance** (§ solo/team): team" "T3b the refusal prints the exact line to add"
  tree_is '' "T3b nothing was written (no field line)"
  mk_repo TWO - "$CO2"
  vrun "$REPO" @second-placeholder
  rc_is 2 "T3b two field lines exit 2"
  has "more than one Governance field line" "T3b the refusal names the ambiguity"
  tree_is '' "T3b nothing was written (two field lines)"
  mk_repo TAB - "$CO2"
  vrun "$REPO" @second-placeholder
  rc_is 2 "T3b a tab-indented field line exits 2"
  has "other than spaces" "T3b the refusal names the indent"
  tree_is '' "T3b nothing was written (tab-indented)"
}
cell_t3c() {  # step 2 follows what land reads: Governance team with a solo dial is team
  mk_repo team 'MERGE_RELATIONSHIP=solo' "$CO1"
  vrun "$REPO" @second-placeholder
  rc_is 0 "T3c Governance team with a solo dial exits 0"
  has "the way you merge your PRs today" "T3c land reads team, so step 2 is the plain merge line"
  hasnt "solo bar" "T3c the solo-bar line is never printed"
  tree_is ' M .github/CODEOWNERS\n M .kit/dials.conf\n' "T3c the dial flips and CLAUDE.md is left alone"
  file_is "$REPO/.kit/dials.conf" 'MERGE_RELATIONSHIP=team\n' "T3c the dial reads team"
}
cell_t4() {  # CODEOWNERS: the governing rule, path rules, the file
  mk_repo solo - '* @owner-placeholder # the owner\n'
  vrun "$REPO" @second-placeholder
  rc_is 0 "T4a an active rule with an inline comment exits 0"
  file_is "$REPO/.github/CODEOWNERS" '* @owner-placeholder @second-placeholder # the owner\n' "T4a the handle goes before the inline comment"
  mk_repo solo - '# only a comment\n'
  vrun "$REPO" @second-placeholder
  rc_is 2 "T4b no active rule and no --owner exits 2"
  has "pass --owner" "T4b the refusal names the flag"
  tree_is '' "T4b nothing was written (no --owner)"
  vrun "$REPO" @second-placeholder --owner @owner-placeholder
  rc_is 0 "T4b no active rule with --owner exits 0"
  file_is "$REPO/.github/CODEOWNERS" '# only a comment\n*  @owner-placeholder @second-placeholder\n' "T4b one rule is added after the comment block"
  mk_repo solo - -
  vrun "$REPO" @second-placeholder --owner @owner-placeholder
  rc_is 0 "T4c no file exits 0"
  file_is "$REPO/.github/CODEOWNERS" '# CODEOWNERS (created by sparkwright team). The last matching rule wins.\n# Each path below needs a review from one of the people on its rule.\n*  @owner-placeholder @second-placeholder\n' "T4c the file is created with two comment lines and the rule"
  mk_repo solo - '* @old-placeholder\n* @owner-placeholder\n'
  vrun "$REPO" @second-placeholder
  rc_is 0 "T4d a later * rule exits 0"
  file_is "$REPO/.github/CODEOWNERS" '* @old-placeholder\n* @owner-placeholder @second-placeholder\n' "T4d the last * rule is the one edited"
  mk_repo solo - '* @owner-placeholder\n/docs/ @owner-placeholder\n'
  vrun "$REPO" @second-placeholder
  rc_is 2 "T4e a one-owner path rule after the * rule exits 2"
  has "names one person" "T4e the refusal names the rule"
  has "@second-placeholder" "T4e the refusal names the handle it lacks"
  tree_is '' "T4e nothing was written (one-owner path rule)"
  mk_repo solo - '* @owner-placeholder @second-placeholder\n/x/ @owner-placeholder\n'
  vrun "$REPO" @second-placeholder
  rc_is 2 "T4k a flip with no new handle and a one-owner path rule exits 2"
  has "names one person" "T4k the refusal names the rule"
  has "nobody besides @owner-placeholder" "T4k the refusal says who is the only reviewer"
  tree_is '' "T4k nothing was written (one-owner path rule, no new handle)"
  mk_repo solo - '* @owner-placeholder @second-placeholder\n/x/ @owner-placeholder bogus\n'
  vrun "$REPO" @second-placeholder
  rc_is 2 "T4m a path rule with one person and a bogus token exits 2"
  has "names one person" "T4m the bogus token does not count as a person"
  tree_is '' "T4m nothing was written (bogus token on a path rule)"
  mk_repo solo - '* @owner-placeholder\n/x/\n'
  vrun "$REPO" @second-placeholder
  rc_is 2 "T4l a path rule with no handle exits 2"
  has "names no one" "T4l the refusal names the empty rule"
  tree_is '' "T4l nothing was written (empty path rule)"
  mk_repo solo - '* @owner-placeholder\n/docs/ @owner-placeholder @docs-placeholder\n'
  vrun "$REPO" @second-placeholder
  rc_is 0 "T4f a two-owner path rule after the * rule exits 0"
  has "already names two or more people" "T4f the two-owner rule is listed as a notice"
  file_is "$REPO/.github/CODEOWNERS" '* @owner-placeholder @second-placeholder\n/docs/ @owner-placeholder @docs-placeholder\n' "T4f the path rule is left alone"
  mk_repo solo - '/docs/ @owner-placeholder\n* @owner-placeholder\n'
  vrun "$REPO" @second-placeholder
  rc_is 0 "T4g a path rule above the * rule exits 0"
  file_is "$REPO/.github/CODEOWNERS" '/docs/ @owner-placeholder\n* @owner-placeholder @second-placeholder\n' "T4g the path rule above is left alone"
  mk_repo solo - '* @owner-placeholder @third-placeholder\n'
  vrun "$REPO" @second-placeholder
  rc_is 0 "T4h a rule already naming two people exits 0"
  file_is "$REPO/.github/CODEOWNERS" '* @owner-placeholder @third-placeholder @second-placeholder\n' "T4h the new handle is added beside them"
  mk_repo solo - '* @owner-placeholder\r\n'
  vrun "$REPO" @second-placeholder
  rc_is 2 "T4i a CRLF CODEOWNERS exits 2"
  has "carriage returns" "T4i the refusal names CRLF"
  tree_is '' "T4i nothing was written (CRLF)"
  mk_repo NONE - "$CO1"
  vrun "$REPO" @second-placeholder
  rc_is 2 "T4j no Governance line exits 2"
  has "**Governance** (§ solo/team): team" "T4j the refusal prints the line to add"
}
cell_t5() {  # never on the default branch, never on a dirty tree
  mk_repo solo - "$CO1"
  g -C "$REPO" checkout -q main
  vrun "$REPO" @second-placeholder
  rc_is 2 "T5 on main exits 2"
  has "default branch" "T5 the refusal names the default branch"
  tree_is '' "T5 nothing was written on main"
  g -C "$REPO" checkout -q -b master
  vrun "$REPO" @second-placeholder
  rc_is 2 "T5 on master with origin/HEAD unset exits 2"
  has "default branch" "T5 master is named as the default branch"
  g -C "$REPO" checkout -q -b develop2
  g -C "$REPO" config init.defaultBranch develop2
  vrun "$REPO" @second-placeholder
  rc_is 2 "T5 on the init.defaultBranch name exits 2"
  has "default branch" "T5 the init.defaultBranch name is refused"
  g -C "$REPO" config --unset init.defaultBranch
  g -C "$REPO" checkout -q -b rel1
  g -C "$REPO" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/rel1
  vrun "$REPO" @second-placeholder
  rc_is 2 "T5 on the branch origin/HEAD names exits 2"
  has "default branch" "T5 the origin/HEAD branch is refused"
  g -C "$REPO" checkout -q --detach
  vrun "$REPO" @second-placeholder
  rc_is 2 "T5 a detached HEAD exits 2"
  has "detached HEAD" "T5 the refusal names the detached HEAD"
  mk_repo solo - "$CO1"
  : > "$REPO/stray.txt"
  vrun "$REPO" @second-placeholder
  rc_is 2 "T5 an untracked file exits 2"
  has "not clean" "T5 the refusal says the tree is not clean"
  has "stray.txt" "T5 the refusal names the first path"
  mk_repo solo - "$CO1"
  printf 'x\n' >> "$REPO/CLAUDE.md"
  vrun "$REPO" @second-placeholder
  rc_is 2 "T5 a modified file exits 2"
  has "not clean" "T5 the refusal says the tree is not clean (modified)"
}
cell_t6() {  # a handle cannot inject
  mk_repo solo - "$CO1"
  _t6() {  # <label> <arg>
    vrun "$REPO" "$2"
    rc_is 2 "T6 $1 exits 2"
    has "is not a valid handle" "T6 $1 names its own refusal"
    tree_is '' "T6 $1 wrote nothing"
  }
  _nlc=$(printf '\nx'); _nlc=${_nlc%x}
  _crc=$(printf '\r')
  _bd=$(printf '\342\200\256'); _zw=$(printf '\342\200\213')
  _t6 "an embedded newline plus a rule" "@ok-placeholder${_nlc}* @evil-placeholder"
  _t6 "a carriage return" "@ok-placeholder${_crc}"
  _t6 "a space" "@ok placeholder"
  _t6 "a #" "@ok-placeholder#x"
  _t6 "a bidi override" "@ok-placeholder${_bd}x"
  _t6 "a zero-width space" "@ok-placeholder${_zw}x"
  _t6 "an overlong name" "@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  _t6 "a bare word" "owner-placeholder"
  _t6 "a trailing dash" "@ok-placeholder-"
  _t6 "an empty slug" "@org-placeholder/"
  _t6 "a login ending in a dash before a slash" "@abc-/team"
  _t6 "a slug starting with a dot" "@org-placeholder/.x"
  _t6 "a slug of two dots" "@org-placeholder/.."
  _t6 "a slug starting with a dash" "@org-placeholder/-x"
  _t6 "a slug starting with an underscore" "@org-placeholder/_x"
  _t6 "an empty argument" ""
  vrun "$REPO" "@ok-placeholder${_bd}x"
  case "$OUT" in
    *"$_bd"*) chk 1 "T6 a refused bidi handle is echoed raw" ;;
    *) chk 0 "T6 a refused bidi handle is echoed with the format character stripped" ;;
  esac
  vrun "$REPO" @second-placeholder --owner "@bad handle"
  rc_is 2 "T6 a bad --owner exits 2"
  has "is not a valid handle" "T6 a bad --owner names its own refusal"
  vrun "$REPO" @OWNER-Placeholder
  rc_is 2 "T6 the owner alone, in another case, exits 2"
  has "team means two or more people" "T6 the owner alone fails the floor"
  tree_is '' "T6 the owner alone wrote nothing"
}
cell_t7() {  # never through a symlink, never outside the tree; ambiguity refuses
  mk_repo solo - -
  mkdir -p "$REPO/.github"; printf '* @owner-placeholder\n' > "$REPO/real-co"
  ln -s ../real-co "$REPO/.github/CODEOWNERS"
  commit_all
  vrun "$REPO" @second-placeholder
  rc_is 2 "T7a a symlinked CODEOWNERS exits 2"
  has "is a symlink" "T7a the refusal names the symlink"
  file_is "$REPO/real-co" '* @owner-placeholder\n' "T7a the link target is untouched"
  mk_repo solo - -
  _o7="$W/out$SEQ"; mkdir -p "$_o7"; printf '* @owner-placeholder\n' > "$_o7/CODEOWNERS"
  ln -s "$_o7" "$REPO/.github"
  commit_all
  vrun "$REPO" @second-placeholder
  rc_is 2 "T7b a symlinked .github pointing outside the tree exits 2"
  has "outside the work tree" "T7b the refusal says the path resolves outside"
  file_is "$_o7/CODEOWNERS" '* @owner-placeholder\n' "T7b the file outside the tree is untouched"
  if [ "$(ls -A "$_o7")" = "CODEOWNERS" ]; then chk 0 "T7b nothing was created outside the tree"; else chk 1 "T7b nothing was created outside the tree"; fi
  mk_repo solo - "$CO1"
  _o7="$W/outk$SEQ"; mkdir -p "$_o7"; printf 'MERGE_RELATIONSHIP=solo\n' > "$_o7/dials.conf"
  ln -s "$_o7" "$REPO/.kit"
  commit_all
  vrun "$REPO" @second-placeholder
  rc_is 2 "T7c a symlinked .kit pointing outside the tree exits 2"
  has "outside the work tree" "T7c the refusal says the dial path resolves outside"
  file_is "$_o7/dials.conf" 'MERGE_RELATIONSHIP=solo\n' "T7c the dial outside the tree is untouched"
  mk_repo solo - "$CO1"
  mkdir -p "$REPO/docs"; printf '* @owner-placeholder\n' > "$REPO/docs/CODEOWNERS"
  commit_all
  vrun "$REPO" @second-placeholder
  rc_is 2 "T7d two CODEOWNERS files exit 2"
  has "two CODEOWNERS files" "T7d the refusal names the ambiguity"
  tree_is '' "T7d nothing was written (two files)"
  mk_repo solo 'MERGE_RELATIONSHIP=solo' "$CO1"
  printf 'MERGE_RELATIONSHIP=team\n' >> "$REPO/.kit/dials.conf"
  commit_all
  vrun "$REPO" @second-placeholder
  rc_is 2 "T7e two MERGE_RELATIONSHIP lines exit 2"
  has "more than one MERGE_RELATIONSHIP" "T7e the refusal names the ambiguity"
  tree_is '' "T7e nothing was written (two dial lines)"
}
cell_t8() {  # never touches the forge or a credential
  mk_repo solo 'MERGE_RELATIONSHIP=solo' "$CO1"
  mkdir -p "$W/shim"
  printf '#!/bin/sh\necho called >> "%s/calls"\nexit 1\n' "$W" > "$W/shim/gh"
  cp "$W/shim/gh" "$W/shim/curl"; chmod +x "$W/shim/gh" "$W/shim/curl"
  rm -f "$W/calls"
  VPATH="$W/shim:$PATH"; VENV="GH_TOKEN=ghp_placeholder_not_a_token"
  vrun "$REPO" @second-placeholder
  VPATH=""; VENV=""
  rc_is 0 "T8 the run succeeds with a failing gh and curl on PATH"
  if [ -e "$W/calls" ]; then chk 1 "T8 gh or curl was called"; else chk 0 "T8 neither gh nor curl was called"; fi
  hasnt "ghp_placeholder_not_a_token" "T8 the token placeholder is never printed"
}
mk_fault() {  # -> FSUT: a copy of the script under test whose Governance writer writes teem
  SEQ=$((SEQ + 1)); FSUT="$W/fault$SEQ.sh"
  sed '/# MUT-GOVSOLO$/s|1team#|1teem#|' "$SUT" > "$FSUT"
  if cmp -s "$SUT" "$FSUT"; then chk 1 "T9 the fault was injected (the sed script matched nothing)"; fi
}
cell_t9() {  # a write that does not read back as team is undone, created files and directories included
  mk_repo solo 'MERGE_RELATIONSHIP=solo' "$CO1"
  mk_fault
  _t9sut=$SUT; SUT=$FSUT
  vrun "$REPO" @second-placeholder
  SUT=$_t9sut
  rc_is 1 "T9a a write that reads back wrong exits 1"
  has "the run was undone" "T9a the run says it was undone"
  has "does not read as team" "T9a the cause is named"
  tree_is '' "T9a the tree equals its starting state"
  if [ -z "$(ls -A "$W/tmp")" ]; then chk 0 "T9a no temp dir is left"; else chk 1 "T9a no temp dir is left"; fi
  mk_repo solo - -
  _t9sut=$SUT; SUT=$FSUT
  vrun "$REPO" @second-placeholder --owner @owner-placeholder
  SUT=$_t9sut
  rc_is 1 "T9b a faulty run that creates CODEOWNERS exits 1"
  tree_is '' "T9b the tree, untracked files included, equals its starting state"
  if [ -d "$REPO/.github" ]; then chk 1 "T9b the created directory was removed"; else chk 0 "T9b the created directory was removed"; fi
  if [ -z "$(ls -A "$W/tmp")" ]; then chk 0 "T9b no temp dir is left"; else chk 1 "T9b no temp dir is left"; fi
}
cell_t10() {  # several handles at once
  mk_repo solo 'MERGE_RELATIONSHIP=solo' "$CO1"
  vrun "$REPO" @second-placeholder @third-placeholder @Second-Placeholder
  rc_is 0 "T10 two new people and a case-folded repeat exit 0"
  file_is "$REPO/.github/CODEOWNERS" '* @owner-placeholder @second-placeholder @third-placeholder\n' "T10 the rule names the owner and both, in order, each once"
  file_is "$REPO/.kit/dials.conf" 'MERGE_RELATIONSHIP=team\n' "T10 the dial flips"
  claude_is "$REPO" team "T10 the Governance value flips"
  has "Invite @second-placeholder" "T10 the first invitation is printed"
  has "Invite @third-placeholder" "T10 the second invitation is printed"
  hasnt "Invite @Second-Placeholder" "T10 the repeat is not invited twice"
}
cell_t11() {  # a team can grow
  mk_repo team 'MERGE_RELATIONSHIP=team' '* @owner-placeholder @second-placeholder @third-placeholder\n'
  vrun "$REPO" @fourth-placeholder
  rc_is 0 "T11 a new handle on an already-team repository exits 0"
  tree_is ' M .github/CODEOWNERS\n' "T11 only CODEOWNERS changed"
  file_is "$REPO/.github/CODEOWNERS" '* @owner-placeholder @second-placeholder @third-placeholder @fourth-placeholder\n' "T11 the handle is appended"
  has "Invite @fourth-placeholder" "T11 step 1 is printed"
  has "the way you merge your PRs today" "T11 step 2 is printed"
  hasnt "own limited forge account" "T11 the agent-account step is not printed on an already-team repository"
  hasnt "branch-protection-apply" "T11 the protection step is not printed on an already-team repository"
}
cell_t12() {  # mixed already-present and new handles; the floor of two
  _r12='* @owner-placeholder @second-placeholder @third-placeholder\n'
  mk_repo team 'MERGE_RELATIONSHIP=team' "$_r12"
  vrun "$REPO" @second-placeholder @fifth-placeholder
  rc_is 0 "T12a a present and a new handle exit 0"
  file_is "$REPO/.github/CODEOWNERS" '* @owner-placeholder @second-placeholder @third-placeholder @fifth-placeholder\n' "T12a only the new handle is added"
  has "Already on the CODEOWNERS rule, so not added again: @second-placeholder" "T12a the present handle is reported"
  hasnt "Invite @second-placeholder" "T12a the present handle is not invited"
  has "Invite @fifth-placeholder" "T12a the new handle is invited"
  mk_repo team 'MERGE_RELATIONSHIP=team' "$_r12"
  vrun "$REPO" @SECOND-placeholder
  rc_is 0 "T12b a handle in another case exits 0"
  has "already team:" "T12b it is a no-op, compared case-folded"
  tree_is '' "T12b the tree is unchanged"
  vrun "$REPO" @owner-placeholder @second-placeholder
  rc_is 0 "T12c the owner listed with a present handle exits 0"
  has "already team:" "T12c it is a no-op"
  mk_repo solo 'MERGE_RELATIONSHIP=solo' "$CO1"
  vrun "$REPO" @owner-placeholder
  rc_is 2 "T12d the owner alone on a one-owner rule exits 2"
  has "team means two or more people: name at least one person besides @owner-placeholder." "T12d the floor message is printed"
  tree_is '' "T12d nothing was written (the floor)"
  mk_repo team - '* @owner-placeholder @second-placeholder\n/docs/ @owner-placeholder\n'
  vrun "$REPO" @fifth-placeholder
  rc_is 2 "T12e a one-owner path rule refuses"
  has "names one person" "T12e the refusal names the rule"
  has "@fifth-placeholder" "T12e the refusal names the handle"
  tree_is '' "T12e nothing was written (path rule)"
  mk_repo solo - '* @owner-placeholder @OWNER-placeholder\n'
  vrun "$REPO" @second-placeholder
  rc_is 2 "T12f a rule naming one person twice, case-folded, exits 2 before any write"
  has "names the same person twice" "T12f the refusal says so"
  tree_is '' "T12f nothing was written (repeat on the rule)"
  mk_repo solo - '* @owner-placeholder bogus\n'
  vrun "$REPO" @owner-placeholder
  rc_is 2 "T12g a rule token that is not a handle does not count toward the floor"
  has "team means two or more people" "T12g the floor message is printed"
  tree_is '' "T12g nothing was written (bogus token)"
  for _em in 'x@.' '@a.b' 'a@b.'; do
    mk_repo solo - "* @owner-placeholder $_em\\n"
    vrun "$REPO" @owner-placeholder
    rc_is 2 "T12g the token $_em is not an email and does not count toward the floor"
    has "team means two or more people" "T12g the floor message is printed for $_em"
    tree_is '' "T12g nothing was written for $_em"
  done
}
cell_t13() {  # the @org/team notice
  mk_repo solo 'MERGE_RELATIONSHIP=solo' "$CO1"
  vrun "$REPO" @org-placeholder/reviewers
  rc_is 0 "T13a a team handle on a solo repository exits 0"
  has "@org-placeholder/reviewers is a team handle. The verb cannot read its members (it never reads the forge); confirm that it has two or more people before you rely on it for review." "T13a the notice names the given handle"
  file_is "$REPO/.github/CODEOWNERS" '* @owner-placeholder @org-placeholder/reviewers\n' "T13a the team handle is on the rule"
  mk_repo solo 'MERGE_RELATIONSHIP=solo' '* @owner-placeholder @org-placeholder/maintainers\n'
  vrun "$REPO" @second-placeholder
  rc_is 0 "T13b a person added beside an existing team handle exits 0"
  has "@org-placeholder/maintainers is a team handle." "T13b the notice names the existing handle"
  mk_repo solo 'MERGE_RELATIONSHIP=solo' "$CO1"
  vrun "$REPO" @second-placeholder
  hasnt "is a team handle" "T13c no team handle, no notice"
  mk_repo team - '* @owner-placeholder @org-placeholder/maintainers\n'
  vrun "$REPO" @org-placeholder/maintainers
  rc_is 0 "T13d a no-op run exits 0"
  has "already team:" "T13d it is a no-op"
  has "@org-placeholder/maintainers is a team handle." "T13d the notice is printed on a no-op run"
}

mutant() {  # <label> <sed script> <cell>...: applied to a COPY of this script; every named cell must go red
  _ml=$1; _msd=$2; shift 2
  SEQ=$((SEQ + 1)); _mf="$W/mut$SEQ.sh"
  printf '%s\n' "$_msd" > "$W/mut.sed"
  sed -f "$W/mut.sed" "$SELF" > "$_mf"
  if cmp -s "$SELF" "$_mf"; then chk 1 "mutant $_ml applied (the sed script matched nothing)"; return 0; fi
  if ! sh -n "$_mf" 2>/dev/null; then chk 1 "mutant $_ml parses (a mutant that cannot run would read as killed)"; return 0; fi
  for _mc in "$@"; do
    _sv=$SELFTEST_BAD; SELFTEST_BAD=0; SELFTEST_QUIET=1
    SUT=$_mf; "$_mc"; SUT=$SELF
    _red=$SELFTEST_BAD; SELFTEST_BAD=$_sv; SELFTEST_QUIET=0
    if [ "$_red" -gt 0 ]; then chk 0 "mutant $_ml reds ${_mc#cell_}"; else chk 1 "mutant $_ml survived ${_mc#cell_} (the cell did not red)"; fi
    rm -rf "$W"/r[0-9]* "$W"/out[0-9]* "$W"/outk[0-9]* "$W"/fault[0-9]*
  done
}

selftest() {
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GH_TOKEN GITHUB_TOKEN
  GIT_AUTHOR_NAME=selftest; GIT_AUTHOR_EMAIL=selftest@kit; GIT_COMMITTER_NAME=selftest; GIT_COMMITTER_EMAIL=selftest@kit
  export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
  W=$(mktemp -d) || { echo "FAIL: no temp dir"; return 1; }
  trap 'rm -rf "$W"' EXIT
  trap 'rm -rf "$W"; exit 130' INT
  trap 'rm -rf "$W"; exit 143' TERM
  trap 'rm -rf "$W"; exit 129' HUP
  mkdir -p "$W/home" "$W/tmp"
  SELF=$(CDPATH='' cd "$(dirname "$0")" && pwd -P)/$(basename "$0")
  SUT=$SELF; VPATH=""; VENV=""
  for _c in cell_t1 cell_t2 cell_t3 cell_t3b cell_t3c cell_t4 cell_t5 cell_t6 cell_t7 cell_t8 cell_t9 cell_t10 cell_t11 cell_t12 cell_t13; do
    "$_c"
    rm -rf "$W"/r[0-9]* "$W"/out[0-9]* "$W"/outk[0-9]* "$W"/fault[0-9]*
  done
  # Mutants: each must red the cell it names.
  mutant "label-edited-not-the-value" '/# MUT-GOVSOLO$/s|.*|GOV_EXPR="s#solo/team#team/team#"   # MUT-GOVSOLO|' cell_t1
  mutant "another-claude-line-touched" '/# MUT-GOVSOLO$/s|team#"|team#;1s#^#X#"|' cell_t1
  mutant "solo-maps-to-solo" '/# MUT-DIAL$/s|1team#|1solo#|' cell_t1
  mutant "no-op-removed" '/# MUT-NOOP$/s|.*|if false; then   # MUT-NOOP|' cell_t2 cell_t3
  mutant "undeclared-reads-as-team" '/# MUT-UNDECL$/s|.*|  undeclared) GOVV=team ;;   # MUT-UNDECL|' cell_t3b
  mutant "first-star-rule-edited" '/# MUT-FIRST$/s|.*|  if (f[1] == "*") if (g == 0) g = rn   # MUT-FIRST|' cell_t4
  mutant "default-branch-allowed" '/# MUT-DEFAULT$/s|.*|:   # MUT-DEFAULT|' cell_t5
  mutant "handle-validation-skipped" '/# MUT-VALID$/s|valid_handle "$1"|true|' cell_t6
  mutant "handle-checked-line-by-line" '/# MUT-VALID$/s#valid_handle "$1"#printf %s "$1" | grep -Eq "^@[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?(/[A-Za-z0-9][A-Za-z0-9._-]*)?$"#' cell_t6
  mutant "containment-check-skipped" '/# MUT-NORESOLVE$/s|.*|  return 0   # MUT-NORESOLVE|' cell_t7
  mutant "read-back-skipped" '/# MUT-READBACK$/s|.*|if false; then   # MUT-READBACK|' cell_t9
  mutant "only-the-first-handle-taken" '/# MUT-FIRSTONLY$/s|GIVEN="$GIVEN $1"|GIVEN="${GIVEN:-$1}"|' cell_t10
  mutant "refuse-when-already-team" '/# MUT-ALREADY$/s|.*|if [ "$DIAL" != solo ]; then if [ "$GOVV" = team ]; then die2 "already team: refused"; fi; fi   # MUT-ALREADY|' cell_t11
  mutant "present-handles-re-added" '/# MUT-READD$/s|.*|  if false; then   # MUT-READD|' cell_t12
  mutant "case-sensitive-compare" '/# MUT-CASE$/s|.*|  _hl=$_h   # MUT-CASE|' cell_t12
  mutant "floor-dropped" '/# MUT-FLOOR$/s|.*|:   # MUT-FLOOR|' cell_t12
  mutant "step-2-text-from-the-dial-alone" '/# MUT-LANDREL$/s|"$GOVV" != team|"$DIAL" = solo|' cell_t3c
  mutant "team-notice-dropped" '/# MUT-NOTICE$/s|.*|    :   # MUT-NOTICE|' cell_t13
  if [ "$SELFTEST_BAD" -eq 0 ]; then echo "solo-to-team --selftest: OK"; return 0; fi
  echo "solo-to-team --selftest: FAIL ($SELFTEST_BAD)" >&2; return 1
}

# --- main ---
if [ "${1:-}" = "--selftest" ]; then selftest; exit $?; fi

set -f
OWNER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --owner)
      [ $# -ge 2 ] || die2 "--owner requires a value"
      valid_handle "$2" || bad_handle "$2"
      OWNER=$2; shift 2 ;;
    -h|--help) usage ;;
    -*) die2 "unknown flag '$(safe "$1")'" ;;
    *)
      valid_handle "$1" || bad_handle "$1"   # MUT-VALID
      add_given "$1"; shift ;;
  esac
done
[ -n "$GIVEN" ] || usage

# 1. a git work tree, on a branch, never the default branch (compared by name, locally; no network read)
TOP=$(git rev-parse --show-toplevel 2>/dev/null) || die2 "run this inside your project's git work tree"
TOP=$(CDPATH='' cd -P "$TOP" 2>/dev/null && pwd -P) || die2 "cannot resolve the work tree"
cd "$TOP"
BR=$(git symbolic-ref -q --short HEAD 2>/dev/null) || die2 "detached HEAD: check out a branch first (git switch -c <name>), then rerun"
is_default_branch() {  # <branch> -> 0 iff it is the default branch by name
  _oh=$(git symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null || true)
  if [ -n "$_oh" ]; then
    [ "$1" = "${_oh#refs/remotes/origin/}" ]
    return
  fi
  case "$1" in
    main|master|trunk) return 0 ;;
  esac
  _id=$(git config --get init.defaultBranch 2>/dev/null || true)
  if [ -z "$_id" ]; then return 1; fi
  [ "$1" = "$_id" ]
}
if is_default_branch "$BR"; then die2 "refusing to run on the default branch '$(safe "$BR")': make a branch first (git switch -c <name>), then rerun"; fi   # MUT-DEFAULT
# 2. a clean tree, untracked files included
DIRTY=$(git status --porcelain --untracked-files=all 2>/dev/null | head -n 1)
[ -z "$DIRTY" ] || die2 "the working tree is not clean (first: '$(safe "${DIRTY#???}")'): commit or stash it, then rerun"
# 3. every path it may write resolves inside the work tree
_rc=0; check_file CLAUDE.md || _rc=$?
[ "$_rc" -eq 0 ] || die2 "no CLAUDE.md in the work tree: this verb edits an incepted project's own file"
CL_PATH=$F_PATH; CL_DIR=$F_DIR
_rc=0; check_file .kit/dials.conf || _rc=$?
if [ "$_rc" -eq 0 ]; then DIAL_PATH=$F_PATH; DIAL_DIR=$F_DIR; fi
# 5. each handle is a person, not the agent's account: the verb cannot know that (no forge read), so it says so
printf '%s\n' "Each handle must be a person, not the agent's own forge account: the agent never ratifies."
# The one temp directory (outside the tree): the rule and path listings, then the backups for the undo. The EXIT trap is set before it exists and removes it on every exit.
trap 'if [ "$WRITING" -eq 1 ]; then undo_all "stopped unexpectedly"; fi; if [ -n "$TMPF" ]; then rm -f "$TMPF"; fi; if [ -n "$WK" ]; then rm -rf "$WK"; fi' EXIT
trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP
WK=$(mktemp -d) || die2 "cannot make a temp directory"
# 6. CODEOWNERS: the file, the governing rule, the owner
CO_N=0; CO_LIST=""
for _cc in .github/CODEOWNERS .gitlab/CODEOWNERS CODEOWNERS docs/CODEOWNERS; do
  if [ -e "$_cc" ] || [ -L "$_cc" ]; then CO_N=$((CO_N + 1)); CO_REL=$_cc; CO_LIST="$CO_LIST $_cc"; fi
done
[ "$CO_N" -le 1 ] || die2 "two CODEOWNERS files exist ($CO_LIST ): remove or merge one, then rerun"
if [ "$CO_N" -eq 0 ]; then
  CO_REL=.github/CODEOWNERS
  if [ -e .gitlab-ci.yml ]; then CO_REL=.gitlab/CODEOWNERS; fi
fi
CO_BASE=$(basename "$CO_REL")
_rc=0; check_file "$CO_REL" || _rc=$?
CO_FILE=1
if [ "$_rc" -ne 0 ]; then
  CO_FILE=0
  if [ -n "$F_DIR" ]; then
    CO_DIR=$F_DIR
  else
    _cdir=$(dirname "$CO_REL")
    if [ -e "$_cdir" ] || [ -L "$_cdir" ]; then die2 "'$_cdir' exists but is not a usable directory"; fi
    CO_DIR="$TOP/$_cdir"; CO_MKDIR=1
  fi
else
  CO_DIR=$F_DIR
fi
CO_PATH="$CO_DIR/$CO_BASE"
if [ "$CO_FILE" -eq 1 ]; then
  CR=$(printf '\r')
  if grep -q "$CR" "$CO_PATH"; then die2 "$CO_REL has carriage returns (CRLF): this verb does not edit it"; fi
  read_rule "$CO_PATH" || die2 "could not read $CO_REL"
else
  CO_STATE=create; GOVH=""; PATHREC=""
fi
if [ "$CO_STATE" = ok ]; then
  [ -n "$GOVH" ] || die2 "the active * rule in $CO_REL names no one: add the owner to it by hand, then rerun"
  if has_dup "$GOVH"; then die2 "the active * rule in $CO_REL names the same person twice (case-folded:$(safe "$GOVH")): remove the repeat by hand, then rerun"; fi
  _o=${GOVH# }
  if [ -z "$OWNER" ]; then
    OWNER=${_o%% *}
  elif ! in_words "$(lc "$GOVH")" "$(lc "$OWNER")"; then
    die2 "--owner '$(safe "$OWNER")' is not on the active * rule ($(safe "$GOVH")): the file already says who owns it"
  fi
else
  [ -n "$OWNER" ] || die2 "$CO_REL has no active * rule: pass --owner <@handle> to name the project owner"
  GOVH=" $OWNER"
fi
GOVH0=$GOVH; GOVLC=$(lc "$GOVH")
NEWH=""; PRESENT=""
for _h in $GIVEN; do
  _hl=$(lc "$_h")   # MUT-CASE
  if in_words "$GOVLC" "$_hl"; then   # MUT-READD
    PRESENT="$PRESENT $_h"
  else
    NEWH="$NEWH $_h"
  fi
done
# 4 (the floor). team means two or more people
if ! floor_met "$GOVH$NEWH"; then die2 "team means two or more people: name at least one person besides $(safe "$OWNER")."; fi   # MUT-FLOOR
team_handles
# 7. the two relationship declarations
read_dial
[ "$DIAL_N" -le 1 ] || die2 "more than one MERGE_RELATIONSHIP line in .kit/dials.conf: edit it by hand, then rerun"
read_gov
case "$GOVV" in
  undeclared) die2 "CLAUDE.md has no '**Governance** (§ solo/team):' line and this verb never adds one: add the line  **Governance** (§ solo/team): team  by hand, then rerun" ;;   # MUT-UNDECL
  loose) die2 "a Governance line in CLAUDE.md is indented with something other than spaces: start it at the margin or after spaces, then rerun" ;;
  ambiguous) die2 "CLAUDE.md has more than one Governance field line ($GOVN): keep one, then rerun" ;;
  other) die2 "the Governance value '$(safe "$_gv")' is not solo, team or the unfilled [solo / team]: edit CLAUDE.md by hand, then rerun" ;;
esac
NEEDCO=0
if [ "$CO_STATE" != ok ]; then NEEDCO=1; fi
# 8. the no-op: nothing to flip and every handle already named
if [ "$DIAL" != solo ] && [ "$GOVV" = team ] && [ -z "$NEWH" ] && [ "$NEEDCO" = 0 ]; then   # MUT-NOOP
  printf '%s\n' "already team: CLAUDE.md declares team, .kit/dials.conf declares no solo, and CODEOWNERS already names every handle given ($(safe "${GIVEN# }")); nothing to do."
  print_team_notice
  exit 0
fi
ALREADY=0
if [ "$DIAL" != solo ] && [ "$GOVV" = team ]; then ALREADY=1; fi   # MUT-ALREADY
LANDREL=team
if [ "$DIAL" = solo ] && [ "$GOVV" != team ]; then LANDREL=solo; fi   # MUT-LANDREL
check_path_rules
do_writes
if ! readback; then   # MUT-READBACK
  undo_all "$RB_WHY"
  exit 1
fi
trap - INT TERM HUP
WRITING=0
rm -rf "$WK"; WK=""
if [ -n "$PRESENT" ]; then printf '%s\n' "Already on the CODEOWNERS rule, so not added again:$(safe "$PRESENT")"; fi
printf '%s\n' "Changed (nothing is staged or committed; read it with git diff):"
printf '%s' "$CHANGED"
print_team_notice
printf '%s' "$PATHNOTE"
print_next_steps
