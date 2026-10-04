#!/bin/sh
# shell-parse-lint.sh — the shared structural lint (SEMGREP-BASH-PARSE-KIT-WIDE T1): keeps
# semgrep's bundled tree-sitter-bash parsing kit shell scripts by refusing the shapes measured
# as parse-breaking. Rule (a) originated in TRACKER-JIRA-HYGIENE (#707), moved here from
# scripts/tracker-jira.sh's _tj_lint_file; rule (b) was re-measured and re-ruled on 2026-09-28
# (a security ruling superseding both the builder's original byte-set and the follow-up
# ruling's "any bracket holding a backslash", each measured wrong — see the ruling for the
# 354-shape table):
#   (a) a one-line `case … in … esac` (all three keywords on one line);
#   (b) a case-pattern bracket expression `[…]` whose content is a backslash as the FIRST byte
#       of the bracket (`[\…`, e.g. `*[\"\\]*)`), or that holds a backslash-blank (`\ ` or
#       `\<TAB>`) anywhere in the bracket (even negated, e.g. `*[!\ ]*)`) — measured identical
#       on semgrep 1.157 and 1.178: `[a\"]`, `[a-z\-]`, `[!\"]`, `[^\"]` parse CLEAN; a bare `$(`
#       in a case pattern parses clean too (this rule makes no claim about `$(`). The
#       line-prefix (leading whitespace already stripped) before THAT `[`, with blanks around
#       any `|` first collapsed, must hold no remaining whitespace and no trailing `\` (an
#       escaped literal `\[`, not a real bracket-open) — a regex character class inside a
#       quoted sed/grep/awk script is excluded this way; AND the word immediately after the
#       closing `]` (up to the next whitespace/`;`) must reach a `)` — a `[ … ]` test command
#       never does. UNLINTED, backstopped by CI's per-file semgrep `.errors`-empty step: a
#       literal blank or paren inside a bracket (`[! ]`, `[()]`, `[^()]`), a backslash-blank
#       OUTSIDE a bracket (`*\ *)`), a nested `[[\"]]`, and a pattern whose prefix carries a
#       blank not adjacent to `|`. One accepted false positive: a bracket inside quotes within
#       a pattern (`*"[\"]"*)`);
#   (c) a heredoc delimiter word carrying a digit (quoted, blank-leading, tab-strip,
#       backslash-leading or double-quoted) — skipped when the `<<` is preceded on its line by
#       an ODD number of `'` (it sits inside a single-quoted string, not a real heredoc opener).
#   (d) a `${…}` parameter expansion whose content holds an UNQUOTED `<<`, `&` or `;` byte (a
#       single-quoted occurrence, e.g. `${1%%'<<'*}`, is safe and not flagged);
#   (e) a `case … in <pattern>)` whose `case`, `in` and the FIRST pattern all share one line
#       (even when `esac` is on a later line, so rule (a) alone does not catch it).
# Fed by a repo-relative FILE LIST (default conformance/sast-parse-files.txt, one path per
# line, `#`-comments allowed) so every caller (this script, CI's semgrep step, an adapter's own
# --selftest) reads the SAME set — the list grows monotonically as later slices append files;
# it is never edited to shrink a scope silently.
#   sh conformance/shell-parse-lint.sh                    # lints the default list
#   sh conformance/shell-parse-lint.sh --list <file>       # lints an explicit list file
#   sh conformance/shell-parse-lint.sh <file> [<file>...]  # lints explicit files (bypasses the list)
#   sh conformance/shell-parse-lint.sh --selftest          # fixtures, RC-verified
# Output: one line per finding, "<file>:<line>: <rule>". SECURITY ruling (c5, 2026-09-28
# design review): an EMPTY or unreadable list is a red, never a vacuous pass; a listed file
# that does not exist or cannot be read is ALSO a red — it is never silently skipped.
# Exit: 0 = clean · 1 = one or more findings · 2 = usage / an empty or unreadable list or file.
# What it changes: read-only — inspects the listed/named files; mutates nothing.
# Guardrails: read-only; no network, no writes; fails closed (never a silent skip) on an
# empty/unreadable list or a listed file that is missing/unreadable.
set -eu

HERE=$(CDPATH='' cd "$(dirname "$0")" && pwd)
ROOT=$(CDPATH='' cd "$HERE/.." && pwd)
DEFAULT_LIST="$HERE/sast-parse-files.txt"

# lint_file <file>: the three-rule structural lint. Prints "<file>:<line>: <rule>" per
# violation, returns 1 if any, else 0. Skips lines whose first non-blank byte is `#`.
# Self-match trap: every keyword this function searches FOR is assembled from pieces, never
# spelled out literally in a pattern, so this file's own source — which only ever writes a
# real multi-line construct (case-on-its-own-line / esac-on-its-own-line) — cannot trip it.
lint_file() {
  _lf_file=$1
  _lf_bad=0
  _lf_bs_sp='\ '     # backslash + space
  _lf_k1=ca; _lf_k1="${_lf_k1}se"
  _lf_k2=i; _lf_k2="${_lf_k2}n"
  _lf_k3=es; _lf_k3="${_lf_k3}ac"
  _lf_tab=$(printf '\t')
  _lf_bs_tab="\\${_lf_tab}"  # backslash + tab
  _lf_n=0
  while IFS= read -r _lf_line; do
    _lf_n=$((_lf_n + 1))
    _lf_t=$_lf_line
    while :; do
      case "$_lf_t" in
        ' '*|"$_lf_tab"*) _lf_t=${_lf_t#?} ;;
        *) break ;;
      esac
    done
    case "$_lf_t" in
      '#'*) continue ;;
    esac
    # (a) a one-line case: the words case/in/esac all on this one line, in that order.
    case "$_lf_line" in
      *"$_lf_k1"*)
        _lf_after1=${_lf_line#*"$_lf_k1"}
        case "$_lf_after1" in
          *"$_lf_k2"*)
            _lf_after2=${_lf_after1#*"$_lf_k2"}
            case "$_lf_after2" in
              *"$_lf_k3"*)
                echo "${_lf_file}:${_lf_n}: a one-line case statement (semgrep's bundled tree-sitter-bash cannot parse it)"
                _lf_bad=1
                ;;
            esac
            ;;
        esac
        ;;
    esac
    # (b) a case-pattern bracket expression `[…]` that carries a backslash. Walks every
    # `[`…`]` span on the STRIPPED line (there may be more than one, e.g. `[\'\"]*|*[\'\"])`);
    # flags on the first span whose content is a backslash as the FIRST byte of the bracket
    # (`[\…`), or that holds a backslash-blank (`\ ` / `\<TAB>`) anywhere — measured on semgrep
    # 1.157 and 1.178 (identical): `[a\"]`, `[a-z\-]`, `[!\"]`, `[^\"]` parse CLEAN; a bare `$(`
    # in a case pattern parses clean too. UNLINTED (backstopped by CI's per-file semgrep
    # `.errors`-empty step): a literal blank or paren inside a bracket (`[! ]`, `[()]`,
    # `[^()]`), a backslash-blank OUTSIDE a bracket (`*\ *)`), a nested `[[\"]]`, and a pattern
    # whose prefix carries a blank not adjacent to `|`. ONE accepted false positive: a bracket
    # inside quotes within a pattern (`*"[\"]"*)`). The line-prefix test first collapses blanks
    # around a `|` (a `x | *[\"]*)` alternation is a real case pattern), then excludes when the
    # collapsed prefix still holds a blank (a quoted sed/grep/awk script) or ends in `\` (an
    # escaped literal `\[`, not a real bracket-open) — the `=` exclusion is dropped, it protected
    # nothing the whitespace test does not already catch.
    _lf_brem=$_lf_t
    _lf_bpre=''
    while :; do
      case "$_lf_brem" in
        *'['*) : ;;
        *) break ;;
      esac
      _lf_bseg=${_lf_brem%%'['*}
      _lf_bpre="${_lf_bpre}${_lf_bseg}"
      _lf_brem=${_lf_brem#*'['}
      case "$_lf_brem" in
        *']'*)
          _lf_bracket=${_lf_brem%%']'*}
          _lf_brem=${_lf_brem#*']'}
          _lf_bhit=0
          case "$_lf_bracket" in
            '\'*|*"$_lf_bs_sp"*|*"$_lf_bs_tab"*) _lf_bhit=1 ;;
          esac
          # Collapse blanks around `|` in the prefix first (pure parameter expansion, no
          # subprocess) so `x | *[\"]*)` reads as a real alternation prefix, not a "quoted
          # script" false negative.
          _lf_bpn=$_lf_bpre
          while :; do
            case "$_lf_bpn" in
              *' |'*)          _lf_bpn="${_lf_bpn%% |*}|${_lf_bpn#* |}" ;;
              *"$_lf_tab|"*)   _lf_bpn="${_lf_bpn%%"$_lf_tab|"*}|${_lf_bpn#*"$_lf_tab|"}" ;;
              *'| '*)          _lf_bpn="${_lf_bpn%%| *}|${_lf_bpn#*| }" ;;
              *"|$_lf_tab"*)   _lf_bpn="${_lf_bpn%%|"$_lf_tab"*}|${_lf_bpn#*|"$_lf_tab"}" ;;
              *) break ;;
            esac
          done
          case "$_lf_bhit" in
            1)
              case "$_lf_bpn" in
                *' '*|*"$_lf_tab"*|*'\') : ;;  # quoted script / escaped `[`
                *)
                  _lf_bword=''
                  _lf_bafter=$_lf_brem
                  while :; do
                    case "$_lf_bafter" in
                      ''|' '*|"$_lf_tab"*|';'*) break ;;
                      *)
                        _lf_bc=${_lf_bafter%"${_lf_bafter#?}"}
                        _lf_bword="${_lf_bword}${_lf_bc}"
                        _lf_bafter=${_lf_bafter#?}
                        ;;
                    esac
                  done
                  case "$_lf_bword" in
                    *')'*)
                      echo "${_lf_file}:${_lf_n}: a case pattern bracket expression carries a backslash (semgrep's bundled tree-sitter-bash cannot parse it)"
                      _lf_bad=1
                      break
                      ;;
                  esac
                  ;;
              esac
              ;;
          esac
          _lf_bpre="${_lf_bpre}[${_lf_bracket}]"
          ;;
        *) break ;;
      esac
    done
    # (d) a `${…}` expansion whose content holds an unquoted `<<`, `&` or `;` — a single-quoted
    # occurrence (e.g. `${1%%'<<'*}`) is safe. Walks every `${`…`}` span on the stripped line;
    # within each span's content, text inside a `'…'` run is stripped before the check.
    _lf_drem=$_lf_t
    while :; do
      case "$_lf_drem" in
        *'${'*) : ;;
        *) break ;;
      esac
      _lf_drem=${_lf_drem#*'${'}
      case "$_lf_drem" in
        *'}'*)
          _lf_dcont=${_lf_drem%%'}'*}
          _lf_drem=${_lf_drem#*'}'}
          _lf_dsafe=''
          _lf_dwalk=$_lf_dcont
          _lf_dinq=0
          while :; do
            case "$_lf_dwalk" in
              *"'"*)
                _lf_dseg=${_lf_dwalk%%"'"*}
                _lf_dwalk=${_lf_dwalk#*"'"}
                [ "$_lf_dinq" -eq 0 ] && _lf_dsafe="${_lf_dsafe}${_lf_dseg}"
                case "$_lf_dinq" in
                  0) _lf_dinq=1 ;;
                  *) _lf_dinq=0 ;;
                esac
                ;;
              *)
                [ "$_lf_dinq" -eq 0 ] && _lf_dsafe="${_lf_dsafe}${_lf_dwalk}"
                break
                ;;
            esac
          done
          case "$_lf_dsafe" in
            *'<<'*|*'&'*|*';'*)
              echo "${_lf_file}:${_lf_n}: a \${...} expansion holds an unquoted <<, & or ; (semgrep's bundled tree-sitter-bash cannot parse it)"
              _lf_bad=1
              ;;
          esac
          ;;
        *) break ;;
      esac
    done
    # (e) `case … in <pattern>)` sharing one line — a case/in whose FIRST pattern is inlined,
    # even when `esac` sits on a later line (so rule (a) alone would miss it).
    case "$_lf_line" in
      *"$_lf_k1"*)
        _lf_eaf=${_lf_line#*"$_lf_k1"}
        case "$_lf_eaf" in
          *" $_lf_k2 "*)
            _lf_epat=${_lf_eaf#*" $_lf_k2 "}
            case "$_lf_epat" in
              *')'*)
                echo "${_lf_file}:${_lf_n}: a case/in and its first pattern share one line (semgrep's bundled tree-sitter-bash cannot parse it)"
                _lf_bad=1
                ;;
            esac
            ;;
        esac
        ;;
    esac
    # (c) a heredoc whose delimiter word carries a digit — unless the `<<` is preceded on its
    # line by an ODD number of `'` (it sits inside a single-quoted string, not a real opener).
    case "$_lf_line" in
      *'<<'*)
        _lf_qpre=${_lf_line%%'<<'*}
        _lf_qcount=0
        _lf_qrem=$_lf_qpre
        while :; do
          case "$_lf_qrem" in
            *"'"*) _lf_qcount=$((_lf_qcount + 1)); _lf_qrem=${_lf_qrem#*"'"} ;;
            *) break ;;
          esac
        done
        case $((_lf_qcount % 2)) in
          1) : ;;  # odd -> the << sits inside a single-quoted string; skip
          *)
            _lf_hd=${_lf_line#*'<<'}
            case "$_lf_hd" in
              '-'*) _lf_hd=${_lf_hd#'-'} ;;
            esac
            while :; do
              case "$_lf_hd" in
                ' '*|"$_lf_tab"*) _lf_hd=${_lf_hd#?} ;;
                *) break ;;
              esac
            done
            case "$_lf_hd" in
              '\'*) _lf_hd=${_lf_hd#'\'} ;;
            esac
            case "$_lf_hd" in
              "'"*) _lf_hd=${_lf_hd#\'}; _lf_hd=${_lf_hd%%\'*} ;;
              '"'*) _lf_hd=${_lf_hd#\"}; _lf_hd=${_lf_hd%%\"*} ;;
              *) _lf_hd=${_lf_hd%%[!A-Za-z0-9_]*} ;;
            esac
            case "$_lf_hd" in
              *[0-9]*)
                echo "${_lf_file}:${_lf_n}: a heredoc delimiter carries a digit (semgrep's bundled tree-sitter-bash mis-lexes the body as shell)"
                _lf_bad=1
                ;;
            esac
            ;;
        esac
        ;;
    esac
  done < "$_lf_file"
  return "$_lf_bad"
}

# read_list <listfile> -> echoes one repo-relative path per non-comment/non-blank line.
# Returns 2 if the list is empty or unreadable (c5: never a vacuous pass).
read_list() {
  _rl_list=$1
  if [ ! -r "$_rl_list" ]; then
    echo "shell-parse-lint: list file is missing or unreadable: $_rl_list" >&2
    return 2
  fi
  _rl_n=0
  while IFS= read -r _rl_line || [ -n "$_rl_line" ]; do
    case "$_rl_line" in
      ''|'#'*) continue ;;
    esac
    _rl_n=$((_rl_n + 1))
    printf '%s\n' "$_rl_line"
  done < "$_rl_list"
  if [ "$_rl_n" -eq 0 ]; then
    echo "shell-parse-lint: list file names zero files: $_rl_list" >&2
    return 2
  fi
  return 0
}

# lint_paths <path>... -> lints each path (repo-relative or absolute), resolved against ROOT.
# A missing/unreadable path is itself a red (rc 2), never skipped.
lint_paths() {
  _lp_rc=0
  for _lp_p in "$@"; do
    case "$_lp_p" in
      /*) _lp_abs=$_lp_p ;;
      *)  _lp_abs="$ROOT/$_lp_p" ;;
    esac
    if [ ! -r "$_lp_abs" ]; then
      echo "shell-parse-lint: listed file is missing or unreadable: $_lp_p" >&2
      _lp_rc=2
      continue
    fi
    if ! lint_file "$_lp_abs" >"$_lp_out_tmp" 2>&1; then
      # Prefix-strip via parameter expansion, not sed's regex `s|^…|…|` — a path carrying a
      # `|` (a valid filename byte) would otherwise break the substitution's delimiter.
      while IFS= read -r _lp_ln || [ -n "$_lp_ln" ]; do
        case "$_lp_ln" in
          "${_lp_abs}:"*) printf '%s\n' "${_lp_p}:${_lp_ln#"${_lp_abs}:"}" ;;
          *) printf '%s\n' "$_lp_ln" ;;
        esac
      done < "$_lp_out_tmp"
      [ "$_lp_rc" -lt 1 ] && _lp_rc=1
    fi
  done
  return "$_lp_rc"
}

run() {  # <path>... — wraps lint_paths with its scratch output file
  _lp_out_tmp=$(mktemp)
  _r_rc=0
  lint_paths "$@" || _r_rc=$?
  rm -f "$_lp_out_tmp"
  return "$_r_rc"
}

run_list() {  # <listfile> -> resolves the list, then run()s it. rc 2 on an empty/unreadable list.
  _rlist_files=$(read_list "$1") || return $?
  # Word-splitting is the intent (one path per line -> argv), but NOT glob-expansion: a listed
  # path carrying a glob char (`*`, `?`, `[`) must reach run() as that literal path, never
  # expanded against the cwd. set -f suspends pathname expansion for the unquoted split; set +f
  # restores it unconditionally right after (a `return $?` inside the guard would leak -f).
  set -f
  # shellcheck disable=SC2086  # word-splitting is the intent: one path per line -> argv
  run $_rlist_files
  _rlist_rc=$?
  set +f
  return "$_rlist_rc"
}

usage() { echo "usage: shell-parse-lint.sh [--list <file>] [<file>...] | --selftest" >&2; exit 2; }

selftest() {
  st=0
  sd=$(mktemp -d)
  trap 'rm -rf "$sd"' EXIT

  # Assembled from pieces (never spelled out literally on one source line) — the same
  # self-match trap lint_file itself guards against, so this selftest's own source stays clean.
  k1=ca; k1="${k1}se"; k2=i; k2="${k2}n"; k3=es; k3="${k3}ac"

  # leg 1: a clean file -> rc 0, no output. Written across several printf calls (never one
  # source line carrying case/in/esac together) so this selftest's OWN source stays lint-clean.
  {
    printf '#!/bin/sh\n'
    printf 'f() {\n'
    printf '  %s "$1" %s\n' "$k1" "$k2"
    printf '    a) echo hi ;;\n'
    printf '  %s\n' "$k3"
    printf '}\n'
  } > "$sd/clean.sh"
  _rc=0; _out=$(run "$sd/clean.sh") || _rc=$?
  if [ "$_rc" -eq 0 ] && [ -z "$_out" ]; then
    echo "PASS: selftest — a clean file returns rc 0 with no findings"
  else
    echo "FAIL: selftest — a clean file did not return rc 0/empty (rc=$_rc out='$_out')"; st=1
  fi

  # leg 2: rule (a) — a planted one-line case, assembled from pieces (self-match trap).
  printf '#!/bin/sh\nf() { %s "$1" %s x) echo hi ;; %s; }\n' "$k1" "$k2" "$k3" > "$sd/onecase.sh"
  _rc=0; _out=$(run "$sd/onecase.sh") || _rc=$?
  if [ "$_rc" -eq 1 ] && printf '%s\n' "$_out" | grep -q "onecase.sh:2: a one-line case statement"; then
    echo "PASS: selftest — a planted one-line case is caught, named by file:line and rule (a)"
  else
    echo "FAIL: selftest — the planted one-line case was not caught (rc=$_rc out='$_out')"; st=1
  fi

  # leg 3: rule (b) — a case-pattern bracket expression carrying a backslash, assembled from
  # pieces (self-match trap): plants `*[\"\\]*)` verbatim (a measured true-positive shape).
  lb='['; rb=']'; bs='\'; dq='"'
  {
    printf '#!/bin/sh\n'
    printf 'f() {\n'
    printf '  %s "$1" %s\n' "$k1" "$k2"
    printf '    *%s%s%s%s%s%s*) echo hi ;;\n' "$lb" "$bs" "$dq" "$bs" "$bs" "$rb"
    printf '  %s\n' "$k3"
    printf '}\n'
  } > "$sd/bracketbs.sh"
  _rc=0; _out=$(run "$sd/bracketbs.sh") || _rc=$?
  if [ "$_rc" -eq 1 ] && printf '%s\n' "$_out" | grep -q "bracketbs.sh:4: a case pattern bracket expression carries a backslash"; then
    echo "PASS: selftest — a planted bracket-expression backslash is caught, rule (b)"
  else
    echo "FAIL: selftest — the planted bracket-expression backslash was not caught (rc=$_rc out='$_out')"; st=1
  fi

  # leg 3b: rule (b) FALSE POSITIVE — a bare \$( in a case arm BODY (no bracket) must NOT be
  # flagged (measured 2026-09-28: a bare \$( in a case pattern parses CLEAN under semgrep).
  dp='$('
  {
    printf '#!/bin/sh\n'
    printf 'f() {\n'
    printf '  %s "$1" %s\n' "$k1" "$k2"
    printf '    x) v=%sprintf hi%s ;;\n' "$dp" ')'
    printf '  %s\n' "$k3"
    printf '}\n'
  } > "$sd/dollarparen.sh"
  _rc=0; _out=$(run "$sd/dollarparen.sh") || _rc=$?
  if [ "$_rc" -eq 0 ] && [ -z "$_out" ]; then
    echo "PASS: selftest — a bare \$( in a case arm body is NOT flagged (rule (b) FP fixed)"
  else
    echo "FAIL: selftest — a bare \$( in a case arm body was wrongly flagged (rc=$_rc out='$_out')"; st=1
  fi

  # leg 4 (S-7, table-driven; re-homed from #707's T2 L8): rule (c) — a digit-bearing heredoc
  # delimiter, planted in a SCRATCH COPY per FORM: quoted (<<'X9EOF'), blank-quoted
  # (<< 'X9EOF'), tab-strip (<<-X9EOF), leading-backslash (<<\X9EOF), double-quoted
  # (<<"X9EOF"). A single-form test (as this leg used to be) stays rc 0 if any one of the
  # tab-strip / leading-blank-skip / backslash-strip / double-quote arms in lint_file's heredoc
  # branch is neutered while the others still catch the quoted form — table-driving all five
  # forms is what proves each arm still pulls its own weight. Each opener is assembled from
  # pieces (never spelled out literally) — the same self-match trap lint_file itself guards.
  lt='<'; op="${lt}${lt}"; sq="'"; dq='"'; bs='\'
  l4allok=1
  for l4form in quoted blank-quoted tab-strip backslash double-quoted; do
    case "$l4form" in
      quoted)        l4opener="${op}${sq}X9EOF${sq}" ;;
      blank-quoted)  l4opener="${op} ${sq}X9EOF${sq}" ;;
      tab-strip)     l4opener="${op}-X9EOF" ;;
      backslash)     l4opener="${op}${bs}X9EOF" ;;
      double-quoted) l4opener="${op}${dq}X9EOF${dq}" ;;
    esac
    {
      printf '#!/bin/sh\n'
      printf 'f() {\n'
      printf '  cat %s\n' "$l4opener"
      printf '  body\n'
      printf 'X9EOF\n'
      printf '}\n'
    } > "$sd/digitheredoc-${l4form}.sh"
    _rc=0; _out=$(run "$sd/digitheredoc-${l4form}.sh") || _rc=$?
    if [ "$_rc" -eq 1 ] && printf '%s\n' "$_out" | grep -q "digitheredoc-${l4form}.sh:3: a heredoc delimiter carries a digit"; then
      :
    else
      echo "FAIL: selftest — the structural lint did not catch the planted ${l4form} digit heredoc delimiter (rc=$_rc out='$_out')"; st=1; l4allok=0
    fi
  done
  if [ "$l4allok" -eq 1 ]; then
    echo "PASS: selftest — a planted digit-bearing heredoc delimiter is caught across all five rule-(c) forms: quoted, blank-quoted, tab-strip, backslash, double-quoted"
  fi

  # leg 4b (re-homed from #707's T2 L9): negative form — a digit-bearing heredoc delimiter
  # carrying a leading BLANK before the (quoted) delimiter word, `<<  'X9EOF'` (two spaces) —
  # the spaced form the leading-blank-skip loop must strip past before reaching the quote arm.
  {
    printf '#!/bin/sh\n'
    printf 'f() {\n'
    printf "  cat %s  %sX9EOF%s\n" "$op" "$sq" "$sq"
    printf '  body\n'
    printf 'X9EOF\n'
    printf '}\n'
  } > "$sd/digitheredoc-spaced.sh"
  _rc=0; _out=$(run "$sd/digitheredoc-spaced.sh") || _rc=$?
  if [ "$_rc" -eq 1 ] && printf '%s\n' "$_out" | grep -q "digitheredoc-spaced.sh:3: a heredoc delimiter carries a digit"; then
    echo "PASS: selftest — a planted SPACED digit-bearing heredoc delimiter is caught"
  else
    echo "FAIL: selftest — the planted spaced digit heredoc delimiter was not caught (rc=$_rc out='$_out')"; st=1
  fi

  # leg 4c (follow-up ruling, condition 6): rule (b) REFINE false positive — a `[ … ]` TEST
  # command whose content carries a backslash-space (the real semgrep trigger) is NOT flagged,
  # because the word right after its `]` never reaches a `)` before whitespace/`;` (mirrors a
  # measured tracker-jira.sh shape). Assembled from pieces (self-match trap n/a: no case/in/esac).
  lb='['; rb=']'; bsl='\'
  {
    printf '#!/bin/sh\n'
    printf 'f() {\n'
    printf '  %s -n "a%s b" %s && printf hi\n' "$lb" "$bsl" "$rb"
    printf '}\n'
  } > "$sd/testcmdbs.sh"
  _rc=0; _out=$(run "$sd/testcmdbs.sh") || _rc=$?
  if [ "$_rc" -eq 0 ] && [ -z "$_out" ]; then
    echo "PASS: selftest — a [ … ] test command carrying a backslash-space is NOT flagged (rule (b) refine FP fixed)"
  else
    echo "FAIL: selftest — a [ … ] test command was wrongly flagged (rc=$_rc out='$_out')"; st=1
  fi

  # leg 4d: rule (d) true positive — a \${…} expansion holding an UNQUOTED << (assembled).
  lt='<'; op2="${lt}${lt}"
  {
    printf '#!/bin/sh\n'
    printf 'f() {\n'
    printf '  x=${1%%%%%s*}\n' "$op2"
    printf '}\n'
  } > "$sd/dollarhd.sh"
  _rc=0; _out=$(run "$sd/dollarhd.sh") || _rc=$?
  if [ "$_rc" -eq 1 ] && printf '%s\n' "$_out" | grep -q "dollarhd.sh:3: a \${...} expansion holds an unquoted"; then
    echo "PASS: selftest — a \${...} expansion holding an unquoted << is caught, rule (d)"
  else
    echo "FAIL: selftest — the planted unquoted-<< expansion was not caught (rc=$_rc out='$_out')"; st=1
  fi

  # leg 4e: rule (d) false positive — the same shape with the << single-quoted is safe.
  {
    printf '#!/bin/sh\n'
    printf 'f() {\n'
    printf "  x=\${1%%%%'%s'*}\n" "$op2"
    printf '}\n'
  } > "$sd/dollarhdq.sh"
  _rc=0; _out=$(run "$sd/dollarhdq.sh") || _rc=$?
  if [ "$_rc" -eq 0 ] && [ -z "$_out" ]; then
    echo "PASS: selftest — a \${...} expansion holding a QUOTED << is NOT flagged, rule (d)"
  else
    echo "FAIL: selftest — a quoted-<< expansion was wrongly flagged (rc=$_rc out='$_out')"; st=1
  fi

  # leg 4f: rule (e) true positive — case/in and the first pattern share one line, esac later.
  {
    printf '#!/bin/sh\n'
    printf 'f() {\n'
    printf '  %s "$1" %s *[A-Za-z]*)\n' "$k1" "$k2"
    printf '    echo hi ;;\n'
    printf '  %s\n' "$k3"
    printf '}\n'
  } > "$sd/caseinline.sh"
  _rc=0; _out=$(run "$sd/caseinline.sh") || _rc=$?
  if [ "$_rc" -eq 1 ] && printf '%s\n' "$_out" | grep -q "caseinline.sh:3: a case/in and its first pattern share one line"; then
    echo "PASS: selftest — a case/in sharing one line with its first pattern is caught, rule (e)"
  else
    echo "FAIL: selftest — the planted inline case/in+pattern was not caught (rc=$_rc out='$_out')"; st=1
  fi

  # leg 4g: rule (e) false positive — case/in on its own line, pattern on the next, is clean.
  {
    printf '#!/bin/sh\n'
    printf 'f() {\n'
    printf '  %s "$1" %s\n' "$k1" "$k2"
    printf '    *[A-Za-z]*) echo hi ;;\n'
    printf '  %s\n' "$k3"
    printf '}\n'
  } > "$sd/casesplit.sh"
  _rc=0; _out=$(run "$sd/casesplit.sh") || _rc=$?
  if [ "$_rc" -eq 0 ] && [ -z "$_out" ]; then
    echo "PASS: selftest — case/in on its own line, pattern on the next, is NOT flagged, rule (e)"
  else
    echo "FAIL: selftest — a properly split case/in was wrongly flagged (rc=$_rc out='$_out')"; st=1
  fi

  # leg 9 (security ruling on I2, 2026-09-28): the ruling's 14-fixture set, table-driven, run
  # through THIS selftest — CI never runs the ruling's scratch fixtures.py harness, so without
  # this leg a regression in rule (b) would pass --selftest silently (the exact gap I2 flagged).
  # T1-T7 must be flagged (rule (b)); F1-F7 must not. Every planted shape is assembled from
  # PIECES (self-match trap): a literal bracket char never appears paired with a later bracket
  # char on any one line of THIS source, so building these fixtures cannot itself trip rule (b)
  # on the lint's own source (leg 8 stays clean). Pieces are variable REFERENCES (`${l9lb}` etc),
  # never a literal `[`/`]` written twice on one line.
  l9lb='['; l9rb=']'; l9bs='\'; l9dq='"'; l9sq="'"; l9dl='$'; l9amp='&'; l9bang='!'; l9pipe='|'
  l9allok=1
  for l9case in T1 T2 T3 T4 T5 T6 T7 F1 F2 F3 F4 F7; do
    case "$l9case" in
      T1) l9pat="*${l9lb}${l9bs}${l9dq}${l9bs}${l9bs}${l9rb}*"; l9exp=flag ;;
      T2) l9pat="${l9lb}${l9bs}${l9sq}${l9bs}${l9dq}${l9rb}*${l9pipe}*${l9lb}${l9bs}${l9sq}${l9bs}${l9dq}${l9rb}"; l9exp=flag ;;
      T3) l9pat="*${l9lb}${l9bs}${l9bs}${l9rb}*"; l9exp=flag ;;
      T4) l9pat="*${l9lb}${l9bs}${l9dl}${l9rb}*"; l9exp=flag ;;
      T5) l9pat="*${l9lb}${l9bs}${l9amp}${l9rb}*"; l9exp=flag ;;
      T6) l9pat="x ${l9pipe} *${l9lb}${l9bs}${l9dq}${l9rb}*"; l9exp=flag ;;
      T7) l9pat="*${l9lb}${l9bang}${l9bs} ${l9rb}*"; l9exp=flag ;;
      F1) l9pat="*${l9sq}${l9dl}(${l9sq}*"; l9exp=clean ;;
      F2) l9pat="*${l9lb}${l9lb}:space:${l9rb}${l9rb}*"; l9exp=clean ;;
      F3) l9pat="*${l9lb}${l9bang}A-Za-z0-9:/?${l9bs}${l9amp}=._%,-${l9rb}*"; l9exp=clean ;;
      F4) l9pat="${l9lb}a-z${l9bs}-${l9rb}*"; l9exp=clean ;;
      F7) l9pat="*labels${l9bs}${l9lb}${l9bs}${l9rb}${l9bs}?*"; l9exp=clean ;;
    esac
    {
      printf '#!/bin/sh\n'
      printf 'f() {\n'
      printf '  %s "$1" %s\n' "$k1" "$k2"
      printf '    %s) echo hi ;;\n' "$l9pat"
      printf '  %s\n' "$k3"
      printf '}\n'
    } > "$sd/l9-${l9case}.sh"
    _rc=0; _out=$(run "$sd/l9-${l9case}.sh") || _rc=$?
    case "$l9exp" in
      flag)
        case "$_rc:$_out" in
          1:*"a case pattern bracket expression carries a backslash"*) : ;;
          *) echo "FAIL: selftest — leg9 $l9case was not flagged, rule (b) (rc=$_rc out='$_out')"; st=1; l9allok=0 ;;
        esac
        ;;
      clean)
        if [ "$_rc" -eq 0 ] && [ -z "$_out" ]; then :
        else echo "FAIL: selftest — leg9 $l9case was wrongly flagged (rc=$_rc out='$_out')"; st=1; l9allok=0; fi
        ;;
    esac
  done
  # F5/F6 (raw, non-case lines) — built via variable-reference concatenation, same self-match
  # discipline: the assembling lines carry no literal bracket char paired with another.
  l9f5="${l9lb} -n \"a${l9bs} b\" ${l9rb} && printf hi"
  printf '#!/bin/sh\nf() {\n  %s\n}\n' "$l9f5" > "$sd/l9-F5.sh"
  _rc=0; _out=$(run "$sd/l9-F5.sh") || _rc=$?
  if [ "$_rc" -eq 0 ] && [ -z "$_out" ]; then :
  else echo "FAIL: selftest — leg9 F5 was wrongly flagged (rc=$_rc out='$_out')"; st=1; l9allok=0; fi

  l9f6="x=\$(printf '%s' \"\$1\" | sed 's/${l9lb}${l9bs}${l9dq}${l9rb}//g')"
  printf '#!/bin/sh\nf() {\n  %s\n}\n' "$l9f6" > "$sd/l9-F6.sh"
  _rc=0; _out=$(run "$sd/l9-F6.sh") || _rc=$?
  if [ "$_rc" -eq 0 ] && [ -z "$_out" ]; then :
  else echo "FAIL: selftest — leg9 F6 was wrongly flagged (rc=$_rc out='$_out')"; st=1; l9allok=0; fi

  if [ "$l9allok" -eq 1 ]; then
    echo "PASS: selftest — the ruling's 14-fixture set (T1-T7 flag, F1-F7 clean) all check out, rule (b)"
  fi

  # leg 5: an empty list -> rc 2, never a vacuous pass.
  : > "$sd/empty-list.txt"
  _rc=0; run_list "$sd/empty-list.txt" >/dev/null 2>"$sd/empty.err" || _rc=$?
  if [ "$_rc" -eq 2 ] && grep -q "zero files" "$sd/empty.err"; then
    echo "PASS: selftest — an empty list file reds rc 2 (c5: never a vacuous pass)"
  else
    echo "FAIL: selftest — an empty list did not red rc 2 (rc=$_rc err='$(cat "$sd/empty.err")')"; st=1
  fi

  # leg 6: a list naming a missing file -> red (rc 2), never silently skipped.
  printf '%s\n' "does/not/exist-$$.sh" > "$sd/missing-list.txt"
  _rc=0; run_list "$sd/missing-list.txt" >/dev/null 2>"$sd/missing.err" || _rc=$?
  if [ "$_rc" -eq 2 ] && grep -q "missing or unreadable" "$sd/missing.err"; then
    echo "PASS: selftest — a list naming a missing file reds rc 2, never skipped"
  else
    echo "FAIL: selftest — a missing listed file did not red (rc=$_rc err='$(cat "$sd/missing.err")')"; st=1
  fi

  # leg 7: list-driven — an explicit --list of one clean file resolves it and returns rc 0.
  printf '%s\n' "$sd/clean.sh" > "$sd/one-list.txt"
  _rc=0; run_list "$sd/one-list.txt" >/dev/null 2>&1 || _rc=$?
  if [ "$_rc" -eq 0 ]; then
    echo "PASS: selftest — --list resolves a listed file and lints it (rc 0 on clean)"
  else
    echo "FAIL: selftest — --list did not resolve/lint the named file (rc=$_rc)"; st=1
  fi

  # leg 8: the lint lints ITSELF clean — its own source must not trip its own rules.
  _rc=0; _out=$(run "$HERE/shell-parse-lint.sh") || _rc=$?
  if [ "$_rc" -eq 0 ] && [ -z "$_out" ]; then
    echo "PASS: selftest — the lint lints its own source clean (rc 0, no findings)"
  else
    echo "FAIL: selftest — the lint's own source trips its own rules (rc=$_rc out='$_out')"; st=1
  fi

  if [ "$st" -eq 0 ]; then echo "OK: shell-parse-lint selftest"; return 0; else echo "FAIL: shell-parse-lint selftest"; return 1; fi
}

main() {
  case "${1:-}" in
    --selftest) selftest; exit $? ;;
    -h|--help) usage ;;
  esac

  if [ "${1:-}" = "--list" ]; then
    [ $# -eq 2 ] || usage
    run_list "$2"
    exit $?
  fi

  if [ $# -eq 0 ]; then
    run_list "$DEFAULT_LIST"
    exit $?
  fi

  run "$@"
  exit $?
}

main "$@"
