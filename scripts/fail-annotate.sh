#!/bin/sh
# fail-annotate.sh - one sourced function, kit_annot_init, and its problem matcher scripts/fail-annotate.json (SWAS-945 PR 2; erratum E3 rev 3,
# docs/architecture/2026-11-19-sandbox-profile-945-errata.md).
#
# THE PROBLEM. A red kit check in CI shows only "Process completed with exit code N." as its annotation; the `FAIL:` line that names the cause is in the log
# (measured on four red runs, E2 M-A1). A GitHub problem matcher makes the runner turn each matching output line into an error annotation.
#
# WHAT THIS DOES. Each entry point defines a no-op stand-in, sources this file by a path relative to its own location, and calls kit_annot_init as its first
# statement (before any cd). Only if GITHUB_ACTIONS=true AND SW_ANNOTATE=1, init prints `::remove-matcher owner=sparkwright-fail::` and then
# `::add-matcher::<absolute path of scripts/fail-annotate.json>`; in EVERY case it then runs `unset SW_ANNOTATE`, so a child process, a nested entry point or a
# fixture below never prints its own add line. The path is resolved fail-soft: any fault (an unresolvable root, an unreadable JSON, a path holding a newline, a CR or
# `::`) means no matcher, return 0, rc unchanged. Nothing is printed at exit and no FAIL, exit or trap site of the caller is touched; the matcher lasts for the rest
# of the job (accepted, E3 Scope). The variable changes OUTPUT only. The matcher matches a column-0 line that starts `FAIL:` or `FAIL ` (not only the kit's).
#
# POSIX sh, dash-clean, no `local`, no heredoc in a function. Sourcing loads ONLY kit_annot_init; the selftest is defined after the direct-run test.
# Run `sh scripts/fail-annotate.sh --selftest`.
#
# What it changes: when opted in (GITHUB_ACTIONS=true and SW_ANNOTATE=1), two stdout lines that register a problem matcher; otherwise nothing.
# Guardrails: opt-in only, and SW_ANNOTATE is unset in every case; no network; no file written; no rc change; any fault returns 0 with no matcher.
# Read-only contract (E4): conformance/verify.sh reads the unexported flag _ka_on (0 or 1, assigned by every init) to gate its column-0 summary; keep its name and meaning.

_FA_ENVNAME=SW_ANNOTATE   # FA-ENVNAME

kit_annot_init() {
  _ka_on=0
  if [ "${GITHUB_ACTIONS-}" = true ] && [ "${SW_ANNOTATE-}" = 1 ]; then _ka_on=1; fi   # FA-GATE
  unset SW_ANNOTATE   # FA-UNSET
  [ "$_ka_on" = 1 ] || return 0
  _ka_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." 2>/dev/null && pwd -P) || return 0   # FA-CD
  _ka_json=$_ka_root/scripts/fail-annotate.json   # FA-PATH
  [ -r "$_ka_json" ] || return 0
  _ka_nl=$(printf '\nx'); _ka_nl=${_ka_nl%x}; _ka_cr=$(printf '\r')
  case "$_ka_json" in *'::'*|*'%'*|*"$_ka_nl"*|*"$_ka_cr"*) return 0 ;; esac
  printf '%s\n' "::remove-matcher owner=sparkwright-fail::" || return 0   # FA-RM
  printf '%s\n' "::add-matcher::$_ka_json" || return 0   # FA-ADD
  return 0
}

# ---- everything below loads ONLY on a direct run (`sh scripts/fail-annotate.sh --selftest`); a sourcing caller stops here -------------------------------------------
case "${0##*/}" in
  fail-annotate.sh) : ;;   # FA-DIRECT
  *) return 0 2>/dev/null || exit 0 ;;
esac

# FA_T/r is a fixture tree: conformance/ent.sh (stand-in, own-location source, init, FAIL prints, optional nested inner.sh, exit $FA_RC) beside scripts/fail-annotate.sh
# and .json. A cell takes the library COPY ($1) and the JSON ($2) to judge, returns 0 when its expectation holds; a mutant is a sed edit of the library, the JSON or the
# entry fixture, proven to apply and to parse, which must make the cell fail.
fa_ok() { echo "PASS: $1"; FA_N=$((FA_N + 1)); }
fa_no() { echo "FAIL: $1"; FA_N=$((FA_N + 1)); FA_FAIL=1; }

fa_tree() {   # <lib|''> <json|''> [base]: build the tree (no library or no JSON when empty); FA_ENTSED edits the entry fixture
  _ft=${3:-$FA_T/r}
  rm -rf "$_ft"; mkdir -p "$_ft/conformance" "$_ft/scripts" || return 1
  if [ -n "$1" ]; then cp "$1" "$_ft/scripts/fail-annotate.sh"; fi
  if [ -n "$2" ]; then cp "$2" "$_ft/scripts/fail-annotate.json"; fi
  printf '%s\n' '#!/bin/sh' 'set -eu' 'kit_annot_init() { return 0; }' \
    '_FA_LIB="$(dirname "$0")/../scripts/fail-annotate.sh"' \
    'if [ -f "$_FA_LIB" ]; then . "$_FA_LIB"; fi   # FA-SRC' \
    'kit_annot_init' \
    'echo "FAIL: red one"' \
    'echo "FAIL: x ::stop-commands::tok"' \
    'printf "%s\n" "FAIL: \\n::add-mask::y"' \
    'if [ "${FA_INNER-}" = 1 ]; then sh "$(dirname "$0")/inner.sh" || :; fi' \
    'exit "${FA_RC:-0}"' > "$_ft/conformance/ent.base"
  if [ -n "${FA_ENTSED-}" ]; then sed -e "$FA_ENTSED" "$_ft/conformance/ent.base" > "$_ft/conformance/ent.sh"; else cp "$_ft/conformance/ent.base" "$_ft/conformance/ent.sh"; fi
  printf '%s\n' '#!/bin/sh' 'set -eu' 'kit_annot_init() { return 0; }' \
    '_FA_LIB="$(dirname "$0")/../scripts/fail-annotate.sh"' \
    'if [ -f "$_FA_LIB" ]; then . "$_FA_LIB"; fi' \
    'kit_annot_init' 'echo "FAIL: inner fixture"' 'exit 1' > "$_ft/conformance/inner.sh"
}

# fa_run <on|noopt|nogha|off> <rc> <inner 0|1> [base]: the entry fixture in a child with the named opt-in state; stdout in $FA_T/out, its rc in FA_GOT.
fa_run() {
  case "$1" in
    on)    _fr_a='GITHUB_ACTIONS=true'; _fr_b='SW_ANNOTATE=1' ;;
    noopt) _fr_a='GITHUB_ACTIONS=true'; _fr_b='FA_NOP=1' ;;
    nogha) _fr_a='FA_NOP=1'; _fr_b='SW_ANNOTATE=1' ;;
    *)     _fr_a='FA_NOP=1'; _fr_b='FA_NOP=2' ;;
  esac
  FA_GOT=0
  env -u SW_ANNOTATE -u GITHUB_ACTIONS -u CDPATH "$_fr_a" "$_fr_b" FA_RC="$2" FA_INNER="$3" sh "${4:-$FA_T/r}/conformance/ent.sh" > "$FA_T/out" 2> "$FA_T/err" || FA_GOT=$?
}
fa_colons() { grep -c '^::' "$FA_T/out" || :; }   # the number of workflow-command lines in the last run
fa_rx() { sed -n 's/^ *"regexp": "\(.*\)",*$/\1/p' "$1" | head -n 1; }   # <json>: the matcher regex

# FM-G1: the green-run shapes (indented, embedded in a PASS line, the runner's cyan echo) never match.
fa_c_G1() {
  _g_rx=$(fa_rx "$2"); [ -n "$_g_rx" ] || return 1
  printf '%s\n' '      FAIL: indented dump' 'selftest PASS: x -> FAIL' 'PASS corp-mutant FAIL' "$(printf '\033[36;1m  echo "FAIL: x"\033[0m')" > "$FA_T/g.txt"
  [ "$(grep -Ec -e "$_g_rx" "$FA_T/g.txt" || :)" = 0 ]
}
# FM-F1: the kit's FAIL shapes match, group 1 is the whole line.
fa_c_F1() {
  _f_rx=$(fa_rx "$2"); [ -n "$_f_rx" ] || return 1
  for _f_l in 'FAIL: agent-autonomy conformance failed' 'FAIL (drift): SWAS278A-X12f a table file' 'FAIL mutant : SWAS278A-MX12f the drift leg'; do
    [ "$(printf '%s\n' "$_f_l" | sed -nE "s/$_f_rx/\\1/p")" = "$_f_l" ] || return 1
  done
}
# FM-J1: one matcher, owner, severity, message group; and init prints an absolute, readable path.
fa_c_J1() {
  command -v jq > /dev/null 2>&1 || { echo "FM-J1 needs jq to read the matcher JSON structurally" >&2; return 1; }
  jq -e '(.problemMatcher | length) == 1 and .problemMatcher[0].owner == "sparkwright-fail" and .problemMatcher[0].severity == "error" and (.problemMatcher[0].pattern | length) == 1 and .problemMatcher[0].pattern[0].message == 1 and (.problemMatcher[0].pattern[0].regexp | type) == "string"' "$2" > /dev/null 2>&1 || return 1
  fa_tree "$1" "$2"; fa_run on 0 0
  _j_p=$(sed -n 's/^::add-matcher:://p' "$FA_T/out")
  case "$_j_p" in /*) [ -r "$_j_p" ] ;; *) return 1 ;; esac
}
# FA-I1: only the two fixed literals are `::` lines, whatever the FAIL text holds.
fa_c_I1() {
  fa_tree "$1" "$2"; fa_run on 0 0
  [ "$(fa_colons)" = 2 ] && grep -Fxq '::remove-matcher owner=sparkwright-fail::' "$FA_T/out" && [ "$(grep -c '^::add-matcher::/.*fail-annotate\.json$' "$FA_T/out" || :)" = 1 ] \
    && grep -q '^FAIL: x ::stop-commands::tok$' "$FA_T/out"
}
# FA-N1: the outer entry point prints the matcher once; the inner prints none and its FAIL print is unchanged.
fa_c_N1() {
  fa_tree "$1" "$2"; fa_run on 1 1
  [ "$(grep -c '^::add-matcher::' "$FA_T/out" || :)" = 1 ] && grep -Fxq 'FAIL: inner fixture' "$FA_T/out"
}
# FA-V1: output only: the same rc, and the same stdout apart from init's two matcher lines.
fa_c_V1() {
  fa_tree "$1" "$2"; fa_run on 2 0; _v_on=$FA_GOT; cp "$FA_T/out" "$FA_T/on.out"
  fa_run noopt 2 0; _v_off=$FA_GOT
  [ "$_v_on" = 2 ] && [ "$_v_off" = 2 ] && [ "$(grep -c '^::' "$FA_T/on.out" || :)" = 2 ] && [ "$(fa_colons)" = 0 ] && grep -v '^::' "$FA_T/on.out" | cmp -s - "$FA_T/out"
}
# FA-O1: no opt-in, no GITHUB_ACTIONS or no library reads as the no-op stand-in: same bytes, same rc; a $(...) caller sees nothing.
fa_c_O1() {
  fa_tree "" ""; fa_run off 1 0; _o_rc=$FA_GOT; cp "$FA_T/out" "$FA_T/base.out"
  [ "$_o_rc" = 1 ] || return 1
  fa_tree "$1" "$2"
  fa_run noopt 1 0; [ "$FA_GOT" = "$_o_rc" ] && cmp -s "$FA_T/out" "$FA_T/base.out" || return 1
  fa_run nogha 1 0; [ "$FA_GOT" = "$_o_rc" ] && cmp -s "$FA_T/out" "$FA_T/base.out" || return 1
  fa_tree "" ""; fa_run on 1 0; [ "$FA_GOT" = "$_o_rc" ] && cmp -s "$FA_T/out" "$FA_T/base.out" || return 1
  fa_tree "$1" "$2"
  _o_x=$(env -u SW_ANNOTATE GITHUB_ACTIONS=true FA_RC=1 sh "$FA_T/r/conformance/ent.sh" || :); ! printf '%s\n' "$_o_x" | grep -q '^::'
}
# FA-R1: an unusable root, JSON or path prints nothing and leaves the rc alone under set -eu; a set CDPATH does not redirect the root.
fa_c_R1() {
  fa_tree "$1" ""; fa_run on 3 0; [ "$FA_GOT" = 3 ] && [ "$(fa_colons)" = 0 ] || return 1
  if [ "$(id -u)" != 0 ]; then
    fa_tree "$1" "$2"; chmod 000 "$FA_T/r/scripts/fail-annotate.json"; fa_run on 3 0; _r_g=$FA_GOT; chmod 644 "$FA_T/r/scripts/fail-annotate.json"
    [ "$_r_g" = 3 ] && [ "$(fa_colons)" = 0 ] || return 1
  fi
  _r_nl=$(printf '\nx'); _r_nl=${_r_nl%x}; _r_cr=$(printf '\r')
  for _r_b in "$FA_T/a::b" "$FA_T/a%b" "$FA_T/a${_r_nl}b" "$FA_T/a${_r_cr}b"; do
    fa_tree "$1" "$2" "$_r_b"; fa_run on 3 0 "$_r_b"; [ "$FA_GOT" = 3 ] && [ "$(fa_colons)" = 0 ] || return 1
  done
  fa_tree "$1" "$2"
  _r_o=$(env -u SW_ANNOTATE GITHUB_ACTIONS=true SW_ANNOTATE=1 sh -c 'set -eu; . "$1"; kit_annot_init; echo done' "$FA_T/nodir/conformance/x.sh" "$FA_T/r/scripts/fail-annotate.sh") || return 1
  [ "$_r_o" = 'done' ] || return 1
  mkdir -p "$FA_T/decoy/conformance"; _r_real=$(cd "$FA_T/r" && pwd -P)
  ( cd "$FA_T/r" && env -u SW_ANNOTATE GITHUB_ACTIONS=true SW_ANNOTATE=1 CDPATH="$FA_T/decoy" FA_RC=0 FA_INNER=0 sh conformance/ent.sh ) > "$FA_T/out" 2> "$FA_T/err" || return 1
  grep -Fxq "::add-matcher::$_r_real/scripts/fail-annotate.json" "$FA_T/out"
}
# FA-A1: two runs (two steps) print remove, add, remove, add: never two adds without a remove.
fa_c_A1() {
  fa_tree "$1" "$2"; fa_run on 0 0; cp "$FA_T/out" "$FA_T/a1.out"; fa_run on 0 0; cat "$FA_T/out" >> "$FA_T/a1.out"
  [ "$(grep '^::' "$FA_T/a1.out" | sed -n 's/^::\([a-z-]*\).*/\1/p' | tr '\n' ' ')" = 'remove-matcher add-matcher remove-matcher add-matcher ' ]
}

# FA-W1: the census. fa_w1_file <path> prints one line per violation: it names scripts/fail-annotate.sh on a non-comment line, calls kit_annot_init as a bare statement
# exactly once, as the FIRST statement (E3: only the shebang, comments, `set -eu`, the no-op stand-in, `_FA_LIB=` and the guarded source line may precede it), and calls
# no function the library no longer has (kit_annot_fail, kit_annot_flush).
fa_w1_file() {
  awk -v f="$1" '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    !ini && !pre && $0 !~ /^(set -eu|kit_annot_init\(\) \{ return 0; \}|_FA_LIB=.*|if \[ -f "\$_FA_LIB" \]; then \. "\$_FA_LIB"; fi|kit_annot_init)$/ { pre = NR }
    /fail-annotate\.sh/ { src = 1 }
    /^[[:space:]]*kit_annot_init[[:space:]]*(;.*)?$/ { ni++; if (!ini) ini = NR }
    /^[[:space:]]*cd[[:space:]]/ { if (!cdl) cdl = NR }
    /kit_annot_(fail|flush)([^A-Za-z0-9_]|$)/ { if ($0 !~ /^[[:space:]]*kit_annot_(fail|flush)\(\)/) gone = NR }
    END {
      if (!src) print "fail-annotate census: " f " does not source scripts/fail-annotate.sh on a non-comment line"
      if (ni != 1) print "fail-annotate census: " f " calls kit_annot_init " ni + 0 " times (want once)"
      if (ini && cdl && cdl < ini) print "fail-annotate census: " f " runs a cd (line " cdl ") before kit_annot_init (line " ini ")"
      if (ini && pre && pre < ini) print "fail-annotate census: " f " runs a statement (line " pre ") before kit_annot_init (line " ini "), which must be the first"
      if (gone) print "fail-annotate census: " f " line " gone " calls a function the library no longer has"
    }' "$1"
}
fa_w1_real() {   # <root>: the eight entry points
  for _fw_p in verify agent-autonomy ci-gates non-vacuity green-on-clone selftest-hermetic secret-scan-wired inception-done; do
    if [ -f "$1/conformance/$_fw_p.sh" ]; then fa_w1_file "$1/conformance/$_fw_p.sh"; else echo "fail-annotate census: conformance/$_fw_p.sh is missing"; fi
  done
}
fa_w1_fixture() {   # <path> [sed edit]
  printf '%s\n' '#!/bin/sh' 'set -eu' 'kit_annot_init() { return 0; }' \
    '_FA_LIB="$(dirname "$0")/../scripts/fail-annotate.sh"' \
    'if [ -f "$_FA_LIB" ]; then . "$_FA_LIB"; fi' \
    'kit_annot_init' 'echo "FAIL: a"' 'exit 1' > "$1.base"
  if [ -n "${2-}" ]; then sed -e "$2" "$1.base" > "$1"; else cp "$1.base" "$1"; fi
}
fa_c_W1real() { _fw_o=$(fa_w1_real "$FA_ROOT"); [ -z "$_fw_o" ] || { printf '%s\n' "$_fw_o" | sed 's/^/    /'; return 1; }; }
fa_w1_neg() {   # <sed>: the edited fixture is named by the census, the unedited one is clean
  fa_w1_fixture "$FA_T/w1.sh"; [ -z "$(fa_w1_file "$FA_T/w1.sh")" ] || return 1
  fa_w1_fixture "$FA_T/w1.sh" "$1"; _fw_n=$(fa_w1_file "$FA_T/w1.sh"); [ -n "$_fw_n" ] && printf '%s\n' "$_fw_n" | grep -Fq "$FA_T/w1.sh"
}
fa_wmut() { if fa_w1_neg "$2"; then fa_ok "$1"; else fa_no "$1"; fi; }

# FA-L1: the shipped env name never matches the pre-push lane's sens() oracle (read from conformance/prepush-lane.sh), in the library constant and at every ci.yml and
# profile site that names an *ANNOTATE* env key. fa_sens <name>: rc 0 = not sensitive, 1 = sensitive, 2 = the oracle could not be read.
fa_sens() {
  _fs_fn=$(sed -n '/^function sens(n,  u)/,/PREPUSH_)\/) }$/p' "$FA_ROOT/conformance/prepush-lane.sh")
  [ -n "$_fs_fn" ] || return 2
  awk -v n="$1" "$_fs_fn"' BEGIN { exit (sens(n) ? 1 : 0) }'
}
fa_c_L1() {
  _fl_n=$(sed -n 's/^_FA_ENVNAME=\([A-Za-z0-9_]*\).*/\1/p' "$1")
  [ -n "$_fl_n" ] || return 1
  fa_sens KIT_ANNOTATE; [ $? = 1 ] || return 1
  fa_sens "$_fl_n" || return 1
  for _fl_f in "$FA_ROOT/.github/workflows/ci.yml" "$FA_ROOT"/profiles/*/ci.yml; do
    [ -f "$_fl_f" ] || continue
    for _fl_k in $(grep -o '[A-Za-z0-9_]*ANNOTATE[A-Za-z0-9_]*:' "$_fl_f" | tr -d ':' | sort -u); do
      fa_sens "$_fl_k" || return 1
    done
  done
  return 0
}

# FA-W2: the ci.yml census. fa_ci_file <workflow> prints one line per violation: SW_ANNOTATE appears only as a step env (a key at 10 spaces) or an `SW_ANNOTATE=1 sh conformance/`
# prefix, never as a job-level or workflow-level env; a step with the env runs at most one entry point; a step with several prefixes holds a `case` (exclusive arms);
# a prefix never sits in a block whose every line is a bare `sh conformance/<x>.sh` (it would break the pre-push lane grammar, conformance/prepush-lane.sh:286).
fa_ci_file() {
  awk -v f="$1" '
    function flush() {
      if (st) {
        if (env && cmds > 1) print "fail-annotate ci census: " f ": a step with SW_ANNOTATE runs " cmds " entry points (line " sl ")"
        if (pre > 1 && !cs) print "fail-annotate ci census: " f ": a step has " pre " marked prefixes outside a case (line " sl ")"
        if (pre && blk > 0 && nonconf == 0) print "fail-annotate ci census: " f ": a prefix sits in a block whose every line is a bare sh conformance/<x>.sh (line " sl ")"
        if ((env || pre) && cmds == 0) print "fail-annotate ci census: " f ": a marked step runs no entry point (line " sl ")"
      }
      env = 0; cmds = 0; pre = 0; cs = 0; blk = 0; nonconf = 0; inrun = 0; k8 = ""
    }
    /^[[:space:]]*#/ { next }
    /^      - / { flush(); st = 1; sl = NR }
    /^[^ ]/ || /^  [A-Za-z0-9_-]+:/ { flush(); st = 0 }
    { match($0, /^ */); ind = RLENGTH }
    ind == 8 && $0 ~ /^ +[A-Za-z_-]+:/ { k8 = $0; sub(/^ +/, "", k8); sub(/:.*/, "", k8) }
    inrun && ind <= 8 && $0 !~ /^[[:space:]]*$/ { inrun = 0 }
    inrun && $0 !~ /^[[:space:]]*$/ { blk++; if ($0 !~ /^ +(SW_ANNOTATE=1 )?sh conformance\/[a-z0-9-]+\.sh/) nonconf++ }
    /^ +run: *\|/ { inrun = 1 }
    /^ +case / { cs = 1 }
    { c = $0; cmds += gsub(/sh conformance\/(verify|agent-autonomy|ci-gates|non-vacuity|green-on-clone|selftest-hermetic|secret-scan-wired|inception-done)\.sh/, "", c) }
    /SW_ANNOTATE/ {
      if ($0 ~ /^ *SW_ANNOTATE: .1.$/) { env = 1; if (ind != 10 || k8 != "env") print "fail-annotate ci census: " f ": SW_ANNOTATE at indent " ind " under key [" k8 "] is not a step env (line " NR ")" }
      else if ($0 ~ /SW_ANNOTATE=1 sh conformance\//) pre++
      else print "fail-annotate ci census: " f ": unrecognised SW_ANNOTATE shape (line " NR ")"
    }
    END { flush() }' "$1"
}
fa_ci_fix() {   # <file> <good|wf|job|two|blk>
  case "$2" in wf) printf '%s\n' 'env:' "  SW_ANNOTATE: '1'" > "$1" ;; *) : > "$1" ;; esac
  printf '%s\n' 'jobs:' '  a:' '    runs-on: x' >> "$1"
  if [ "$2" = job ]; then printf '%s\n' '    env:' "      SW_ANNOTATE: '1'" >> "$1"; fi
  printf '%s\n' '    steps:' '      - name: s' >> "$1"
  case "$2" in
    blk) printf '%s\n' '        run: |' '          SW_ANNOTATE=1 sh conformance/verify.sh --require' >> "$1" ;;
    with) printf '%s\n' '        with:' "          SW_ANNOTATE: '1'" '        run: sh conformance/verify.sh --require' >> "$1" ;;
    noent) printf '%s\n' '        env:' "          SW_ANNOTATE: '1'" '        run: echo hello' >> "$1" ;;
    odd) printf '%s\n' '        env:' "          SW_ANNOTATE: 'yes'" '        run: sh conformance/verify.sh --require' >> "$1" ;;
    two) printf '%s\n' '        env:' "          SW_ANNOTATE: '1'" '        run: sh conformance/verify.sh --require && sh conformance/ci-gates.sh' >> "$1" ;;
    *) printf '%s\n' '        env:' "          SW_ANNOTATE: '1'" '        run: sh conformance/verify.sh --require' >> "$1" ;;
  esac
}
fa_c_W2() {   # the real ci.yml is clean
  _w2=$(for _w2f in "$FA_ROOT/.github/workflows/ci.yml" "$FA_ROOT"/profiles/*/ci.yml; do [ -f "$_w2f" ] && fa_ci_file "$_w2f"; done)
  [ -z "$_w2" ] || { printf '%s\n' "$_w2" | sed 's/^/    /'; return 1; }
}
fa_w2_neg() {   # <variant>: the good fixture is clean, the variant is named
  fa_ci_fix "$FA_T/ci.yml" good; [ -z "$(fa_ci_file "$FA_T/ci.yml")" ] || return 1
  fa_ci_fix "$FA_T/ci.yml" "$1"; [ -n "$(fa_ci_file "$FA_T/ci.yml")" ]
}
fa_w2mut() { if fa_w2_neg "$2"; then fa_ok "$1"; else fa_no "$1"; fi; }

# FA-S1 (mi3, N4): a fixture COPY of conformance/secret-scan-wired.sh, run with a stub scanner that finds nothing (so the --live legs, 3 included, print FAIL),
# prints no column-0 `FAIL` line holding leg 3's planted value (assembled from two halves, as the script does). FA_SSED is an optional sed edit of the copy (the mutant).
fa_c_S1() {   # also leg 6's two fixed values (assembled from halves); the copy sits at $FA_T/t/conformance/ssw.sh so its init cannot source a shared-temp file
  _s_v=$(printf '%s%s' 'R7vK2mQ9xL4tW8nZ' 'c3Hj6pB1sF5yD0gT')
  _s_v2=$(printf '%s%s' 'Qx7adminC3J27' 'XDCG2LmlZGEONYlk')
  _s_v3=$(printf '%s%s' 'Zk3adminQ9w7' 'Lp2Xv5Rt8Ny')
  printf '%s\n' '#!/bin/sh' 'exit 0' > "$FA_T/gl"; chmod 755 "$FA_T/gl"
  mkdir -p "$FA_T/t/conformance"
  if [ -n "${FA_SSED-}" ]; then sed -e "$FA_SSED" "$FA_ROOT/conformance/secret-scan-wired.sh" > "$FA_T/t/conformance/ssw.sh"; else cp "$FA_ROOT/conformance/secret-scan-wired.sh" "$FA_T/t/conformance/ssw.sh"; fi
  ( cd "$FA_ROOT" && env GITLEAKS_BIN="$FA_T/gl" sh "$FA_T/t/conformance/ssw.sh" --live ) > "$FA_T/ssw.out" 2>&1 || :
  grep -q 'live FAIL' "$FA_T/ssw.out" || return 1
  ! grep -E '^FAIL[: ]' "$FA_T/ssw.out" | grep -qF -e "$_s_v" -e "$_s_v2" -e "$_s_v3"
}

fa_cell() { if "$2" "$FA_T/good.sh" "$FA_JSON"; then fa_ok "$1"; else fa_no "$1"; fi; }
fa_chk() {   # <label> <original> <mutant>: the mutant applied and parses
  if cmp -s "$2" "$3"; then fa_no "$1 (the mutation matched nothing; the leg is unbound)"; return 1; fi
  return 0
}
fa_mut() {   # <label> <sed on the library> <cell>
  sed -e "$2" "$FA_SELF" > "$FA_T/mut.sh"
  fa_chk "$1" "$FA_SELF" "$FA_T/mut.sh" || return 0
  if ! sh -n "$FA_T/mut.sh" 2>/dev/null; then fa_no "$1 (the mutant does not parse)"; return 0; fi
  if "$3" "$FA_T/mut.sh" "$FA_JSON"; then fa_no "$1 (the mutant still passes the cell)"; else fa_ok "$1"; fi
}
fa_mutj() {   # <label> <sed on the JSON> <cell>
  sed -e "$2" "$FA_JSON" > "$FA_T/mut.json"
  fa_chk "$1" "$FA_JSON" "$FA_T/mut.json" || return 0
  if "$3" "$FA_T/good.sh" "$FA_T/mut.json"; then fa_no "$1 (the mutant still passes the cell)"; else fa_ok "$1"; fi
}
fa_mute() {   # <label> <sed on the entry fixture> <cell>
  FA_ENTSED=$2; fa_tree "" ""; sed -e "$2" "$FA_T/r/conformance/ent.base" > "$FA_T/ent.mut"
  fa_chk "$1" "$FA_T/r/conformance/ent.base" "$FA_T/ent.mut" || { FA_ENTSED=''; return 0; }
  if ! sh -n "$FA_T/ent.mut" 2>/dev/null; then fa_no "$1 (the mutant does not parse)"; FA_ENTSED=''; return 0; fi
  if "$3" "$FA_T/good.sh" "$FA_JSON"; then fa_no "$1 (the mutant still passes the cell)"; else fa_ok "$1"; fi
  FA_ENTSED=''
}

_fa_selftest() {
  FA_SELF=$1; FA_N=0; FA_FAIL=0; FA_ENTSED=''
  FA_T=$(mktemp -d "${TMPDIR:-/tmp}/fa-st.XXXXXX") || { echo "FAIL: fail-annotate: mktemp failed"; return 1; }
  trap 'rm -rf "$FA_T"' EXIT
  trap 'exit 130' INT TERM
  FA_ROOT=$(CDPATH='' cd -- "$(dirname -- "$FA_SELF")/.." && pwd) || { echo "FAIL: fail-annotate: no tree root"; return 1; }
  FA_JSON=$FA_ROOT/scripts/fail-annotate.json
  [ -r "$FA_JSON" ] || { echo "FAIL: fail-annotate: scripts/fail-annotate.json is not readable"; return 1; }
  cp "$FA_SELF" "$FA_T/good.sh"

  fa_cell "FM-G1 the green-run shapes (indented, embedded in PASS, the cyan echo) never match" fa_c_G1
  fa_mutj "FM-G1 mutant: the regex unanchored" 's|"^(FAIL|"(FAIL|' fa_c_G1
  fa_cell "FM-F1 FAIL:, FAIL (drift): and FAIL mutant : match; group 1 is the whole line" fa_c_F1
  fa_mutj "FM-F1 mutant: ^FAIL: only" 's|FAIL\[: \]|FAIL:|' fa_c_F1
  fa_cell "FM-J1 one matcher, owner, severity error, message group 1; init prints an absolute readable path" fa_c_J1
  fa_mutj "FM-J1 mutant: severity warning" 's|"severity": "error"|"severity": "warning"|' fa_c_J1
  fa_mut "FM-J1 mutant: a path relative to the cwd" '/# FA-PATH$/s|^.*$|  _ka_json=scripts/fail-annotate.json   # FA-PATH|' fa_c_J1
  fa_cell "FA-I1 only the two fixed literals are :: lines, whatever the FAIL text holds" fa_c_I1
  fa_mut "FA-I1 mutant: the library prints a line built from outside text" '/# FA-ADD$/s|^.*$|  printf "%s\\n" "::add-matcher::$_ka_json"; printf "%s\\n" "::stop-commands::tok"   # FA-ADD|' fa_c_I1
  fa_cell "FA-N1 a nested entry point prints no matcher" fa_c_N1
  fa_mut "FA-N1 mutant: export in place of unset" '/# FA-UNSET$/s|^.*$|  export SW_ANNOTATE   # FA-UNSET|' fa_c_N1
  fa_mute "FA-N1 mutant: init not first (after the nested run)" '/^kit_annot_init$/d;s|^exit |kit_annot_init; exit |' fa_c_N1
  fa_cell "FA-V1 output only: same rc, same stdout apart from the two matcher lines" fa_c_V1
  fa_mut "FA-V1 mutant: init changes the rc" '/# FA-ADD$/s|^.*$|  exit 9   # FA-ADD|' fa_c_V1
  fa_cell "FA-O1 no opt-in, no GITHUB_ACTIONS or no library reads as the stand-in; a \$(...) caller sees nothing" fa_c_O1
  fa_mut "FA-O1 mutant: print without the opt-in" '/# FA-GATE$/s|^.*$|  _ka_on=1   # FA-GATE|' fa_c_O1
  fa_mute "FA-O1 mutant: fail when the library is absent" '/# FA-SRC$/s|^.*$|. "$_FA_LIB"|' fa_c_O1
  fa_cell "FA-R1 an unusable root, JSON or path prints nothing and keeps the rc under set -eu; CDPATH does not redirect the root" fa_c_R1
  fa_mut "FA-R1 mutant: the fail-soft return dropped" '/# FA-CD$/s/ || return 0//' fa_c_R1
  fa_mut "FA-R1 mutant: CDPATH='' dropped" "/# FA-CD\$/s/CDPATH='' cd/cd/" fa_c_R1
  fa_cell "FA-A1 two runs print remove, add, remove, add" fa_c_A1
  fa_mut "FA-A1 mutant: add before remove" '/# FA-RM$/{h;d;};/# FA-ADD$/G' fa_c_A1
  if fa_c_W1real; then fa_ok "FA-W1 the eight entry points source the library and call init once, before any cd (real tree)"; else fa_no "FA-W1 the eight entry points source the library and call init once, before any cd (real tree)"; fi
  fa_wmut "FA-W1 mutant: the source line deleted -> the file is named" '/fail-annotate\.sh/d'
  fa_wmut "FA-W1 mutant: the init call deleted -> the file is named" '/^kit_annot_init$/d'
  fa_wmut "FA-W1 mutant: a cd before init -> the file is named" 's|^set -eu$|cd /|'
  fa_wmut "FA-W1 mutant: any statement (echo x) before init -> the file is named" 's|^set -eu$|set -eu; echo x|'
  fa_wmut "FA-W1 mutant: a removed function is called -> the file is named" 's|^echo "FAIL: a"$|kit_annot_fail "a"|'
  if fa_c_W2; then fa_ok "FA-W2 ci.yml: SW_ANNOTATE only as a step env or an entry-line prefix, one entry point per step outside case arms (real tree)"; else fa_no "FA-W2 ci.yml: SW_ANNOTATE only as a step env or an entry-line prefix, one entry point per step outside case arms (real tree)"; fi
  fa_w2mut "FA-W2 mutant: a workflow-level env is named" wf
  fa_w2mut "FA-W2 mutant: a job-level env is named" job
  fa_w2mut "FA-W2 mutant: two marked entry points in one step are named" two
  fa_w2mut "FA-W2 mutant: a prefix inside a fully bare block is named" blk
  fa_w2mut "FA-W2 mutant: SW_ANNOTATE under with: is named" with
  fa_w2mut "FA-W2 mutant: a marked step that runs no entry point is named" noent
  fa_w2mut "FA-W2 mutant: an unrecognised SW_ANNOTATE shape is named" odd
  FA_SSED=''
  if fa_c_S1; then fa_ok "FA-S1 secret-scan-wired --live with legs forced red prints no column-0 FAIL line holding leg 3's planted value"; else fa_no "FA-S1 secret-scan-wired --live with legs forced red prints no column-0 FAIL line holding leg 3's planted value"; fi
  FA_SSED='s|echo "live FAIL: the allowlist over-masked[^"]*"|echo "FAIL: $_l3v"|'
  if fa_c_S1; then fa_no "FA-S1 mutant: a copy whose FAIL line echoes the value (the cell must see it) - still passes"; else fa_ok "FA-S1 mutant: a copy whose FAIL line echoes the value (the cell must see it)"; fi
  FA_SSED='s|echo "live FAIL: $2 -> the scan wrote no report (rc=$_ks_rc) [^"]*finding"|echo "FAIL: $_kv_dc"|'
  if fa_c_S1; then fa_no "FA-S1 mutant: leg 6's FAIL line echoes its value - still passes"; else fa_ok "FA-S1 mutant: leg 6's FAIL line echoes its value (the cell must see it)"; fi
  FA_SSED=''
  fa_mut "FA-R1 mutant: the % guard dropped" "s/\\*'%'\\*|//" fa_c_R1
  fa_cell "FA-L1 the shipped env name never matches the lane's sens() oracle (library constant, ci.yml and profile sites)" fa_c_L1
  fa_mut "FA-L1 mutant: the name renamed KIT_ANNOTATE" '/# FA-ENVNAME$/s|=SW_ANNOTATE|=KIT_ANNOTATE|' fa_c_L1
  rm -rf "$FA_T"
  if [ "$FA_FAIL" = 0 ]; then echo "OK: fail-annotate selftest passed ($FA_N cells)"; return 0; fi
  echo "FAIL: fail-annotate selftest failed"; return 1
}

_fa_main() {
  case "${1-}" in
    --selftest) _fa_selftest "$0"; exit $? ;;
    *) echo "usage: sh scripts/fail-annotate.sh --selftest   (the file is meant to be sourced: . scripts/fail-annotate.sh; kit_annot_init)" >&2; exit 2 ;;
  esac
}

_fa_main "$@"
