#!/bin/sh
# readiness.sh — the TABLE-DRIVEN conditional readiness checker (CONFORMANCE-DOC-FAMILIES-MERGE,
# D-240828-4).
#
# WHAT IT REPLACES. Nine conditional `*-ready.sh` checks (agentops, dr, eval, observability,
# preview-env, privacy, resilience, responsible-ai, test-data) each implemented ONE shape: detect a
# surface; if absent render N/A; if present require a record line and require its template
# placeholder to be gone. Nine copies of that shape and its fixture choreography, five trigger
# predicates duplicated thirteen times, nothing forcing the copies to agree. The shape is here, the
# triggers in conformance/surface-lib.sh, the POLICY (record lines, placeholder tokens, FAIL
# sentences) in conformance/readiness.tsv.
#
# THE CONTRACT IS UNCHANGED, and that is the claim the fold has to earn. N/A = no surface, the check
# declined and said so (rc 0; verify.sh renders N-A) · OK = the record is present and not a
# placeholder (rc 0) · FAIL = artifact missing, record line missing, or the placeholder still there,
# named (rc 1). rc 2 is USAGE only, so a mistyped case can never read as a pass.
# HONEST CEILING (unchanged by the fold): a green run proves a posture was RECORDED — not that the
# restore worked, the SLO is met, the evals pass or the processing is lawful. Those are the Manual
# rows of the matching conformance/*-readiness.md, and each case's ceiling is verbatim in its `ok`
# cell. The triggers ESCALATE and never EXEMPT (conformance/surface-lib.sh).
#
# Usage: sh conformance/readiness.sh <case> [project-dir] | --selftest [case] | <case> --selftest
# Exit: 0 = OK or N/A · 1 = FAIL · 2 = usage. POSIX sh; dash-clean.
set -eu

HERE=$(CDPATH='' cd "$(dirname "$0")" && pwd)
# Absolutise the project-dir arg against THE CALLER'S cwd, BEFORE the cd below: the retired checks
# never cd'd, so `readiness.sh dr-ready ../other-repo` resolves where the operator stood, and re-resolving it
# after the cd would silently point elsewhere. A nonexistent dir is USAGE (rc 2), never an N/A — a
# typo must not read as "no surface here". `.` stays literal, so existing call sites' wording holds.
RD_DIR=.
if [ "${1:-}" != "--selftest" ] && [ -n "${2:-}" ] && [ "${2#-}" = "$2" ]; then
  [ -d "$2" ] || { echo "usage: readiness.sh <case> [project-dir] — no such directory: $2" >&2; exit 2; }
  case "$2" in .) : ;; *) RD_DIR=$(CDPATH='' cd "$2" && pwd) ;; esac
fi
cd "$HERE/.." 2>/dev/null || true
TSV="$HERE/readiness.tsv"
TAB=$(printf '\t')
RD_LINT_FAIL=0
# shellcheck disable=SC1091 # sourced sibling libraries (wf_is_deploy; the trigger predicates)
. "$HERE/wf-helpers.sh"
# shellcheck disable=SC1091
. "$HERE/surface-lib.sh"

# EXPECTED ROW COUNT PER CASE (see doc-markers.sh's DM_EXPECT for the reasoning): a row silently
# lost used to change only a log number; pinned here it changes the VERDICT. A case absent from this
# list is itself a FAIL, so a new case cannot land without its count.
RD_EXPECT='agentops-ready:3 dr-ready:8 eval-ready:4 observability-ready:4 preview-env-ready:3 privacy-ready:4 resilience-ready:4 responsible-ai-ready:4 test-data-ready:3'

# rd_lint: the table is well-formed, or the check FAILS LOUDLY. A parser that skips what it cannot
# understand turns a malformed row into an UNENFORCED attestation and reports nothing. Four rules:
# exactly 12 fields; no record-file cell with `..` or rooted at `/`; no `line` row whose
# fail-missing, placeholder and require cells are ALL `-` (it asserts nothing and yields no mutant —
# a dead row that reads as coverage); every case's row count declared in RD_EXPECT.
rd_lint() {
  awk -F'\t' -v t="$TSV" -v x="$RD_EXPECT" '
    /^#/ || /^[[:space:]]*$/ { next }
    NF!=12 { printf "FAIL: readiness — malformed row %s:%d (%d fields, expected 12)\n", t, NR, NF; e=1; next }
    $2=="file" { split($4, p, " "); for (i in p) if (p[i] ~ /\.\./ || p[i] ~ /^\//)
                 { printf "FAIL: readiness — unsafe record-file cell %s:%d (%s)\n", t, NR, p[i]; e=1 } }
    $2=="line" && $8=="-" && $6=="-" && $7=="-" {
      printf "FAIL: readiness — inert line row %s:%d (case %s): fail-missing, placeholder and require are all `-`, so it asserts nothing and yields no mutant\n", t, NR, $1; e=1 }
    { n[$1]++ }
    END { for (c in n) { if (index(x, c ":" n[c] " ") == 0 && x !~ c ":" n[c] "$")
            { printf "FAIL: readiness — case %s has %d row(s); RD_EXPECT does not declare that count\n", c, n[c]; e=1 } }
          exit e }' "$TSV"
}

# rd_rows <case> [kind]: emit this case's rows (optionally only one kind), fields 2..12.
rd_rows() {
  awk -F'\t' -v c="$1" -v k="${2:-}" 'BEGIN{OFS="\t"}
    /^#/{next} NF!=12{next} $1!=c{next} k!="" && $2!=k {next}
    { print $2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12 }' "$TSV"
}

# rd_cases: emit each case name once, in table order.
rd_cases() { awk -F'\t' '/^#/{next} NF!=12{next} !seen[$1]++ {print $1}' "$TSV"; }

# rd_say <value> <text>: print <text> with the single `{}` token replaced by <value>.
rd_say() {
  case "$2" in
    *'{}'*) printf '%s%s%s\n' "${2%%'{}'*}" "$1" "${2#*'{}'}" ;;
    *)      printf '%s\n' "$2" ;;
  esac
}

# rd_resolve <dir> <space-separated candidates>: print the first candidate that exists, else empty.
rd_resolve() {
  _rd=$1; shift
  for _cand in $1; do
    if [ -f "$_rd/$_cand" ]; then printf '%s' "$_rd/$_cand"; return 0; fi
  done
  return 1
}

# rd_trigger <dir> <pred[:arg]>: run a surface-lib predicate. An unknown predicate is fail-CLOSED —
# it must never read as "no surface", which would silently exempt every project of that case.
rd_trigger() {
  _td=$1; _tp=${2%%:*}; _ta=${2#*:}
  if [ "$_ta" = "$2" ]; then _ta=''; fi
  case "$_tp" in
    has_data_surface|has_deploy_surface|has_service_surface|is_agentic|declares_sensitive)
      "$_tp" "$_td" ;;
    has_ai_surface) has_ai_surface "$_td" "$_ta" ;;
    # fail-CLOSED, and STICKY: proceed to the assertions rather than granting an N/A, AND latch a
    # failure so the run cannot still exit 0 — a shout on stderr that leaves rc 0 is a green run.
    *) echo "FAIL: readiness — unknown trigger predicate '$_tp' (conformance/readiness.tsv)" >&2
       RD_LINT_FAIL=1; return 0 ;;
  esac
}

run() {  # run <case> <dir> — the three-state verdict for <case> against the project tree at <dir>
  _c=$1; _dir=${2:-.}
  rd_lint >&2 || return 1
  _meta=$(rd_rows "$_c" case)
  if [ -z "$_meta" ]; then
    echo "FAIL: readiness — no table rows for case '$_c' (conformance/readiness.tsv)"; return 1
  fi
  _trig=$(printf '%s\n' "$_meta" | cut -f3)
  _na=$(printf '%s\n' "$_meta" | cut -f4)
  _ok=$(printf '%s\n' "$_meta" | cut -f5)

  if ! rd_trigger "$_dir" "$_trig" && [ "$RD_LINT_FAIL" = 0 ]; then
    # The N/A text may carry a literal `\n` for a continuation line (dr-ready's escalation warning).
    # Expanded with awk, NOT `printf %b`: %b also interprets `\c`, which TRUNCATES the rest of the
    # line — a cell carrying one would have cut the verdict short and flipped verify.sh's N-A
    # rendering to PASS (is_self_skip needs the whole `N/A:` line). awk's gsub touches only `\n`.
    rd_say "$_dir" "$_na" | awk '{ gsub(/\\n/, "\n"); print }'
    return 0
  fi

  # Surface present -> the assertions bind. A missing artifact is reported once and its dependent
  # line rows are skipped, so one absent RUNBOOK does not fan out into five sub-failures.
  if rd_assert "$_c" "$_dir" && [ "$RD_LINT_FAIL" = 0 ]; then
    printf '%s\n' "$_ok"
    return 0
  fi
  return 1
}

# rd_assert <case> <dir>: print every FAIL line for <case> and RETURN the verdict (0 clean, 1 failed).
rd_assert() {
  _ac=$1; _ad=$2; _af=0
  _rows=$(rd_rows "$_ac")
  while IFS="$TAB" read -r _kind _id _a _b _c6 _d _fmiss _frej _freq _sg _sb; do
    [ -n "$_kind" ] || continue
    case "$_kind" in
      case) continue ;;
      file)
        if ! rd_resolve "$_ad" "$_a" >/dev/null 2>&1; then
          rd_say "$_ad" "$_fmiss"; _af=1
        fi
        ;;
      line|absent)
        _path=$(rd_file_of "$_ac" "$_ad" "$_id") || continue   # artifact absent: already reported
        if [ "$_kind" = "absent" ]; then
          if grep -Eiq "$_b" "$_path" 2>/dev/null; then rd_say "$_path" "$_frej"; _af=1; fi
          continue
        fi
        if ! grep -Eiq "$_b" "$_path" 2>/dev/null; then
          if [ "$_fmiss" != "-" ]; then rd_say "$_path" "$_fmiss"; _af=1; fi
          continue
        fi
        if [ "$_c6" != "-" ] && grep -Eiq "$_c6" "$_path" 2>/dev/null; then
          rd_say "$_path" "$_frej"; _af=1; continue
        fi
        if [ "$_d" != "-" ] && ! grep -Eiq "$_d" "$_path" 2>/dev/null; then
          rd_say "$_path" "$_freq"; _af=1
        fi
        ;;
    esac
  done <<RD_ASSERT_EOF
$_rows
RD_ASSERT_EOF
  return $_af
}

# rd_file_of <case> <dir> <id>: resolve the artifact a line/absent row refers to.
rd_file_of() {
  _fc=$1; _fd=$2; _fi=$3
  _cands=$(rd_rows "$_fc" file | awk -F'\t' -v i="$_fi" '$2==i {print $3; exit}')
  [ -n "$_cands" ] || return 1
  rd_resolve "$_fd" "$_cands"
}

# ── --selftest — the NON-VACUITY heart, GENERATED from the table. Per case: a no-surface fixture
#    (must render N/A), a filled fixture (must render OK), and one mutant per assertion row — delete
#    the artifact, delete the record line, or plant the placeholder — each required to go RED WITH
#    THAT ROW'S OWN TEXT. Asserting the message, not just the exit code, is the Slice-3 scar: a
#    usage error or a broken fixture must never be able to fake a kill.
#
#    ORACLE-REGION DISCIPLINE (non-vacuity.sh / MARK): the meta-sweep mutates only lines BEFORE the
#    `selftest()` marker and emits everything at/after it VERBATIM, so the kill assertions MUST live
#    at/after it — every fixture helper (`_surface`, `_build`, `_expect_*`) is defined BELOW
#    selftest() (POSIX resolves the calls at dispatch time). Above the marker, the sweep neutered
#    their own `return 1` and the selftest went vacuous. ──
selftest() {
  st=0
  if ! rd_lint >&2; then echo "SELFTEST FAIL: readiness — the table is malformed (see above)"; return 1; fi
  SELFBASE=$(mktemp -d) || { echo "SELFTEST FAIL: mktemp -d failed"; return 1; }
  # shellcheck disable=SC2064 # expand SELFBASE now — fixed for the life of the process (no disk leak)
  trap "rm -rf '$SELFBASE'" EXIT INT TERM

  _cases=${1:-}
  [ -n "$_cases" ] || _cases=$(rd_cases)
  _tot=0
  for _case in $_cases; do
    _meta=$(rd_rows "$_case" case)
    if [ -z "$_meta" ]; then
      echo "SELFTEST FAIL: unknown case '$_case' (no rows in $TSV)"; st=1; continue
    fi

    # ⚠️ EVERY variable in this loop carries the `s_` prefix, and that is load-bearing rather than
    #    style. POSIX sh has no function-local scope: the helpers this loop calls (run -> rd_assert,
    #    and the surface-lib predicates) walk the SAME table with read-loops of their own, so an
    #    unprefixed `_id` / `_sb` / `_d` here is overwritten mid-iteration by the callee — measured:
    #    every mutant fixture collapsed to the repo root and the sweep ran vacuous while printing
    #    PASS on its first line. The prefix is the isolation.

    # (0) row-count lock — the table still carries every row this case is supposed to have.
    s_have=$(rd_rows "$_case" | grep -c '')
    s_want=$(printf '%s' " $RD_EXPECT " | tr ' ' '\n' | awk -F: -v c="$_case" '$1==c {print $2}')
    if [ "$s_have" = "$s_want" ]; then
      echo "SELFTEST PASS: $_case row count $s_have == RD_EXPECT"
    else
      echo "SELFTEST FAIL: $_case has $s_have row(s), RD_EXPECT declares '${s_want:-none}'"; st=1
    fi

    # (1) no surface -> N/A
    s_fx="$SELFBASE/$_case/nosurface"; mkdir -p "$s_fx"
    printf '# a plain library with no surfaces\n' > "$s_fx/README.md"
    _expect_na "$_case" "$s_fx" || st=1
    _tot=$((_tot+1))

    # (2) surface + every record filled -> OK
    s_fx="$SELFBASE/$_case/filled"
    _build "$_case" "$s_fx" "" "" || { echo "SELFTEST FAIL: $_case — could not build the filled fixture"; st=1; continue; }
    _expect_ok "$_case" "$s_fx" || st=1
    _tot=$((_tot+1))

    # (3) one mutant per assertion row, driven by the table
    s_n=0
    # shellcheck disable=SC2034 # the read consumes the WHOLE row; not every column is used here
    while IFS="$TAB" read -r s_kind s_id s_a s_b s_c6 s_d6 s_fmiss s_frej s_freq s_sg s_sb; do
      [ -n "$s_kind" ] || continue
      if [ "$s_kind" = "case" ]; then continue; fi
      s_n=$((s_n+1)); s_made=0
      case "$s_kind" in
        file)
          s_fx="$SELFBASE/$_case/mut${s_n}_nofile"
          _build "$_case" "$s_fx" "drop-file:$s_id" "" || { echo "SELFTEST FAIL: $_case mutant $s_n — staging"; st=1; continue; }
          _expect_fail "$_case/$s_n missing artifact '$s_id'" "$_case" "$s_fx" "$(rd_say "$s_fx" "$s_fmiss")" || st=1
          _tot=$((_tot+1)); s_made=$((s_made+1))
          ;;
        line)
          if [ "$s_fmiss" != "-" ]; then
            s_fx="$SELFBASE/$_case/mut${s_n}_noline"
            _build "$_case" "$s_fx" "drop-line" "" "$s_sg" ||{ echo "SELFTEST FAIL: $_case mutant $s_n — staging"; st=1; continue; }
            s_path=$(rd_file_of "$_case" "$s_fx" "$s_id" || true)
            _expect_fail "$_case/$s_n missing record line" "$_case" "$s_fx" "$(rd_say "$s_path" "$s_fmiss")" || st=1
            _tot=$((_tot+1)); s_made=$((s_made+1))
          fi
          if [ "$s_sb" != "-" ]; then
            s_fx="$SELFBASE/$_case/mut${s_n}_bad"
            _build "$_case" "$s_fx" "swap-line" "$s_sb" "$s_sg" ||{ echo "SELFTEST FAIL: $_case mutant $s_n — staging"; st=1; continue; }
            s_path=$(rd_file_of "$_case" "$s_fx" "$s_id" || true)
            s_want=$s_frej
            if [ "$s_want" = "-" ]; then s_want=$s_freq; fi
            _expect_fail "$_case/$s_n planted '$s_sb'" "$_case" "$s_fx" "$(rd_say "$s_path" "$s_want")" || st=1
            _tot=$((_tot+1)); s_made=$((s_made+1))
          fi
          ;;
        absent)
          s_fx="$SELFBASE/$_case/mut${s_n}_planted"
          _build "$_case" "$s_fx" "append:$s_id" "$s_sb" || { echo "SELFTEST FAIL: $_case mutant $s_n — staging"; st=1; continue; }
          s_path=$(rd_file_of "$_case" "$s_fx" "$s_id" || true)
          _expect_fail "$_case/$s_n planted forbidden '$s_sb'" "$_case" "$s_fx" "$(rd_say "$s_path" "$s_frej")" || st=1
          _tot=$((_tot+1)); s_made=$((s_made+1))
          ;;
      esac
      # EVERY assertion row must have produced at least one mutant. Without this the mutant gating
      # above (`!= "-"` on fail-missing / sample-bad) silently yields ZERO kills for a row whose
      # cells are unpopulated, and the sweep still prints OK — coverage that reads as real and is not.
      if [ "$s_made" = 0 ]; then
        echo "SELFTEST FAIL: $_case row $s_n ($s_kind) generated NO mutant — it is not actually enforced"; st=1
      fi
    done <<RD_SELF_EOF
$(rd_rows "$_case")
RD_SELF_EOF
  done

  if [ "$st" = 0 ]; then
    echo "SELFTEST OK: readiness — $_tot generated fixture(s)/mutant(s) behaved (N/A · OK · one labelled kill per table row)"
    return 0
  fi
  echo "SELFTEST FAIL: readiness — a fixture misbehaved or a mutant survived"
  return 1
}

# _surface <trigger> <dir> — plant the minimum tree that makes <trigger> fire. One arm per predicate
# in conformance/surface-lib.sh; an unhandled trigger returns 1 so a new predicate cannot land
# untested (the filled fixture would then never reach OK and the selftest reds).
_surface() {
  case "${1%%:*}" in
    has_data_surface)   printf 'DATABASE_URL=postgres://localhost/app\n' > "$2/.env.example" ;;
    has_deploy_surface|has_service_surface) printf 'FROM scratch\n' > "$2/Dockerfile" ;;
    has_ai_surface)     printf '# RUNBOOK\nAI feature: yes\n' > "$2/RUNBOOK.md" ;;
    is_agentic)         printf '# CLAUDE\n\n- **Agentic:** yes\n' > "$2/CLAUDE.md" ;;
    declares_sensitive) printf '# CLAUDE\n\n- **Data classification:** Restricted\n' > "$2/CLAUDE.md" ;;
    *) return 1 ;;
  esac
}

# _build <case> <dir> <mutation> <payload> <target-line> — stage a fixture that triggers <case> and
# carries every record. Mutations: drop-file:<id> · drop-line · swap-line (payload) · append:<id>.
# ⚠️ drop-line/swap-line key on the RECORD LINE ITSELF (<target-line>), never on a row index: several
# rows legitimately judge ONE shared record line (dr-ready's `Restore verified:` is judged by three).
# Keying on the index left the shared line written by a sibling row, and the mutant survived while
# the sweep reported PASS on the rows either side of it.
_build() {
  _bc=$1; _bd=$2; _bm=$3; _bp=$4; _bg=${5:-}
  rm -rf "$_bd" 2>/dev/null || true
  mkdir -p "$_bd" || return 1
  _bt=$(rd_rows "$_bc" case | cut -f3)
  _surface "$_bt" "$_bd" || return 1

  # artifacts first (the first candidate path wins, as the real resolver does).
  # `b_` prefix throughout, for the same no-local-scope reason the selftest loop uses `s_`.
  b_n=0
  # shellcheck disable=SC2034 # the read consumes the WHOLE row; not every column is used here
  while IFS="$TAB" read -r b_k b_i b_a b_b b_c b_d b_fm b_fr b_fq b_sg b_sb; do
    [ -n "$b_k" ] || continue
    if [ "$b_k" = "case" ]; then continue; fi
    b_n=$((b_n+1))
    [ "$b_k" = "file" ] || continue
    if [ "$_bm" = "drop-file:$b_i" ]; then continue; fi
    b_first=${b_a%% *}
    mkdir -p "$_bd/$(dirname "$b_first")" || return 1
    printf '%b\n' "$b_sg" > "$_bd/$b_first" || return 1
  done <<RD_BUILD_FILES
$(rd_rows "$_bc")
RD_BUILD_FILES

  # then the record lines (deduplicated: several rows may judge one shared record line)
  b_n=0
  # shellcheck disable=SC2034 # the read consumes the WHOLE row; not every column is used here
  while IFS="$TAB" read -r b_k b_i b_a b_b b_c b_d b_fm b_fr b_fq b_sg b_sb; do
    [ -n "$b_k" ] || continue
    if [ "$b_k" = "case" ]; then continue; fi
    b_n=$((b_n+1))
    b_tgt=$(rd_file_of "$_bc" "$_bd" "$b_i" 2>/dev/null) || continue
    if [ "$b_k" = "absent" ]; then
      if [ "$_bm" = "append:$b_i" ]; then printf '%s\n' "$_bp" >> "$b_tgt"; fi
      continue
    fi
    [ "$b_k" = "line" ] || continue
    if [ -n "$_bg" ] && [ "$b_sg" = "$_bg" ]; then
      if [ "$_bm" = "drop-line" ]; then continue; fi
      if [ "$_bm" = "swap-line" ]; then
        grep -qxF "$_bp" "$b_tgt" 2>/dev/null || printf '%s\n' "$_bp" >> "$b_tgt"
        continue
      fi
    fi
    if [ "$b_sg" = "-" ]; then continue; fi
    grep -qxF "$b_sg" "$b_tgt" 2>/dev/null || printf '%s\n' "$b_sg" >> "$b_tgt"
  done <<RD_BUILD_LINES
$(rd_rows "$_bc")
RD_BUILD_LINES
  return 0
}

_expect_na() {  # <case> <dir>
  if _o=$(run "$1" "$2" 2>&1); then
    if printf '%s\n' "$_o" | grep -q '^N/A:'; then
      echo "SELFTEST PASS: $1 — no surface -> N/A (not over-triggered)"; return 0
    fi
    echo "SELFTEST FAIL: $1 — no surface returned rc 0 but did NOT render N/A: $_o"; return 1
  fi
  echo "SELFTEST FAIL: $1 — no surface should be N/A, went RED: $_o"; return 1
}

_expect_ok() {  # <case> <dir>
  if _o=$(run "$1" "$2" 2>&1); then
    if printf '%s\n' "$_o" | grep -q "^$1: OK"; then
      echo "SELFTEST PASS: $1 — surface + every record filled -> OK"; return 0
    fi
    echo "SELFTEST FAIL: $1 — filled fixture rc 0 but no OK verdict line: $_o"; return 1
  fi
  echo "SELFTEST FAIL: $1 — filled fixture should PASS, went RED: $_o"; return 1
}

_expect_fail() {  # <label> <case> <dir> <expected-FAIL-text>
  if _o=$(run "$2" "$3" 2>&1); then
    echo "SELFTEST FAIL: $1 — check still PASSED (VACUOUS): $_o"; return 1
  fi
  if printf '%s\n' "$_o" | grep -qF "$4"; then
    echo "SELFTEST PASS: $1 -> RED via its own text"; return 0
  fi
  echo "SELFTEST FAIL: $1 — went RED but WITHOUT '$4': $_o"; return 1
}

[ -f "$TSV" ] || { echo "FAIL: readiness — the attestation table is missing ($TSV)" >&2; exit 1; }

_usage() { echo "usage: readiness.sh <case> [project-dir] | --selftest [case] | <case> --selftest" >&2; exit 2; }

# BOTH ARGUMENT ORDERS, and every other flag is USAGE. `readiness.sh dr-ready --selftest` used to
# fall through to the real path with `--selftest` as the project-dir: no such dir, no surface, so it
# printed an N/A and exited 0 — a selftest that never ran, rendering as a pass.
case "${1:-}" in
  --selftest) selftest "${2:-}"; exit $? ;;
  ""|-*)      _usage ;;
  *)          case "${2:-}" in
                --selftest) selftest "$1"; exit $? ;;
                -*)         _usage ;;
                *)          run "$1" "$RD_DIR"; exit $? ;;
              esac ;;
esac
