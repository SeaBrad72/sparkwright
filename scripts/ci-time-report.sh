#!/bin/sh
# ci-time-report.sh -- the WARN on measured CI minutes (SWAS-281 slice 281b, design 2026-10-24-ci-time-budget-design.md section 3).
#
#   sh scripts/ci-time-report.sh --report <jobs-json> [<release-baseline>] [<row-times>]
#   sh scripts/ci-time-report.sh --baseline <runs.tsv> <YYYY-MM-DD>     (the release cut's append step: prints baseline lines)
#   sh scripts/ci-time-report.sh --selftest
# Exit: --report ALWAYS exits 0 (never red, by construction: see below). --baseline: 0 ok / 1 bad input. --selftest: 0 / 1.
#
# HOSTED-RUNNER TIME IS NOT A RED GATE. A +46% swing on one job across three runs was seen on unchanged inputs [attested], so a red on
# minutes would fire on the runner, not the repo. The red ratchet is on counts (conformance/conformance-mass-budget.sh: rows, cells,
# legs, jobs). This script only ANNOTATES: ::warning::, never ::error::, and it never changes a run's conclusion.
#
# NEVER RED, three layers: (1) the report body runs as `( ctr_report ) || :`, so no error, set -e, exit or arithmetic abort reaches the
# rc; (2) the ci.yml job carries `continue-on-error: true` and a timeout, which the wrapper cannot cover (a timeout, a failed checkout, a
# lost runner); (3) ci-gates.sh --aggregator-lock (TW1) holds (2) and that every run: line is `|| :`-wrapped. Any API error, malformed
# JSON, missing baseline or missing artifact prints ONE N/A line.
#
# THRESHOLDS (constants; revisit after 20 runs of reads, recorded in the design's amendment log; n = 3 behind the 50%):
#   a JOB exceeds its baseline by BOTH >= 50% AND >= 3 min;  a ROW by BOTH >= 100% AND >= 30 s.
# THE ROW HALF IS DEGRADED UNTIL S0 (per-row timing, `verify.sh --timing-file`) LANDS: with no row-times file the report prints the one
# line `row-times: not produced` and annotates no row. The jobs half works now.
# ANNOTATION TEXT IS SANITISED (job names come from the workflow, which a PR controls): a name never goes into an annotation PROPERTY
# (no file=/title=); in the MESSAGE it is percent-encoded (% CR LF : as %25 %0D %0A %3A) and stripped of other control bytes; in the job
# summary it is markdown-escaped (backslash before ` * _ [ ] < > | and a backslash). At most 25 annotations a run; the rest go to the summary.
# BASELINE: conformance/ci-time-release-baseline.txt, one TAB line per job (minutes) or row (seconds):
#   <job|row> <TAB> <name> <TAB> <value> <TAB> <n runs> <TAB> <reference run id> <TAB> <YYYY-MM-DD>     ('#' comments and blanks ignored)
# written at each publish boundary as the MEDIAN of the release commit's green runs (never one run), the reference id being the main
# push run's. Committed, not a rolling median: a rolling median climbs with the growth. Advisory: editing it changes no verdict.
# POSIX sh; needs jq and awk.
# What it changes: nothing on disk beyond appending the summary block to $GITHUB_STEP_SUMMARY when that file is set; it prints annotations
#   and a table to stdout, reads the jobs JSON and the baseline file named on its command line, and never writes the repo or the forge.
# Guardrails: read-only on the tree; no network call (the workflow fetches the jobs JSON, this script only reads a file); --report exits 0 on
#   every input (wrapped, never red); annotations are ::warning:: only with percent-encoded names; names are markdown-escaped in the summary.
set -eu

CTR_JOB_PCT=50      # percent over baseline
CTR_JOB_MIN=3       # and minutes over baseline
# shellcheck disable=SC2034  # the per-row thresholds are read by the row comparison once S0's timing artifact lands (the jobs half is live now)
CTR_ROW_PCT=100
# shellcheck disable=SC2034  # as above
CTR_ROW_SEC=30
CTR_MAX_ANN=25
CTR_REASON='WARN only: hosted-runner time is not a red gate ("The red ratchet stays with SWAS-281, on deterministic measures (cells, rows)").'
TAB=$(printf '\t')

# ctr_jobs <jobs-json>: stdout `raw<TAB>annotation-encoded<TAB>markdown-escaped<TAB>seconds` per non-skipped job; rc!=0 on bad JSON.
ctr_jobs() {
  jq -r '
    # PORTABLE across jq versions: no regex replacement with a capture or a backslash (jq 1.6 and 1.7 disagree on those, which put a raw
    # backtick, pipe and link into the summary on CI). The escaping walks CODEPOINTS: 13/10/9 -> space, other controls dropped, then a
    # backslash (92) before each of ` * _ [ ] < > | and the backslash itself (96 42 95 91 93 60 62 124 92).
    def clean: explode | map(select(. >= 32 and . != 127)) | implode;
    def enc: gsub("%"; "%25") | gsub("\r"; "%0D") | gsub("\n"; "%0A") | gsub(":"; "%3A") | clean;
    def md: explode
      | map(if . == 13 or . == 10 or . == 9 then 32 elif . < 32 or . == 127 then empty else . end)
      | map(if (. == 96 or . == 42 or . == 95 or . == 91 or . == 93 or . == 60 or . == 62 or . == 124 or . == 92) then [92, .] else [.] end)
      | add // [] | implode;
    .jobs[]? | select(.conclusion != "skipped" and .started_at != null and .completed_at != null)
    | [ ([.name] | @tsv), (.name | enc), (.name | md), (((.completed_at | fromdate) - (.started_at | fromdate)) | tostring) ] | join("\t")' "$1"
}

# ctr_compare <kind> <baseline> <pct> <abs> <factor>: reads `raw<TAB>enc<TAB>md<TAB>value` (value in the kind's unit) on stdin and the
# baseline; prints `W<TAB>growth<TAB>message` for each crossing, and `S<TAB>growth<TAB>summary-line` for every compared name.
ctr_compare() {
  awk -F "$TAB" -v kind="$1" -v pct="$3" -v abs="$4" -v reason="$CTR_REASON" -v bf="$2" '
    BEGIN {
      while ((getline l < bf) > 0) {
        if (l ~ /^[ \t]*(#|$)/) continue
        n = split(l, f, "\t")
        if (n != 6 || f[1] != kind || f[3] !~ /^[0-9]+(\.[0-9]+)?$/ || f[4] !~ /^[0-9]+$/ || f[5] !~ /^[0-9]+$/ || f[6] !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) { bad++; continue }
        b[f[2]] = f[3]; ref[f[2]] = f[5]
      }
    }
    {
      raw = $1; enc = $2; md = $3; v = $4 + 0
      if (kind == "job") v = v / 60
      if (!(raw in b)) next
      g = v - b[raw]; p = (b[raw] > 0) ? 100 * g / b[raw] : 0
      unit = (kind == "job") ? "min" : "s"
      printf "S\t%.3f\t| %s | %.1f %s | %.1f %s | %+.0f%% |\n", g, md, v, unit, b[raw], unit, p
      if (p >= pct && g >= abs)
        printf "W\t%.3f\t%s %s took %.1f %s [M], baseline %.1f %s (run %s), %+.0f%%. %s\n", g, kind, enc, v, unit, b[raw], unit, ref[raw], p, reason
    }
    END { if (bad > 0) printf "B\t%d\t\n", bad }'
}

ctr_report() {  # <jobs-json> [<baseline>] [<row-times>]
  _rj=${1:-}; _rb=${2:-}; _rr=${3:-}
  if [ -z "$_rb" ] && [ "$#" -le 1 ]; then _rb="$(dirname "$0")/../conformance/ci-time-release-baseline.txt"; fi   # the committed per-release baseline, by default
  if [ -z "$_rj" ] || [ ! -r "$_rj" ]; then echo "ci-time-report: N/A (the jobs API read produced no readable file)"; return 0; fi
  _rows=$(ctr_jobs "$_rj" 2>/dev/null) || { echo "ci-time-report: N/A (the jobs API reply was not valid JSON)"; return 0; }
  if [ -z "$_rows" ]; then echo "ci-time-report: N/A (the jobs API reply held no timed job)"; return 0; fi
  if [ -z "$_rb" ] || [ ! -r "$_rb" ]; then echo "ci-time-report: N/A (no release baseline file; job times are listed only)"; _res=''
  else _res=$(printf '%s\n' "$_rows" | ctr_compare job "$_rb" "$CTR_JOB_PCT" "$CTR_JOB_MIN" 1 2>/dev/null) || _res=''
  fi
  if [ -n "$_rb" ] && [ -r "$_rb" ] && [ -z "$_res" ]; then echo "ci-time-report: N/A (the baseline has no job line matching this run)"; fi
  _warn=$(printf '%s\n' "$_res" | awk -F "$TAB" '$1 == "W"' | LC_ALL=C sort -t "$TAB" -k2,2nr)
  _nw=$(printf '%s\n' "$_warn" | grep -c . || true)
  printf '%s\n' "$_warn" | awk -F "$TAB" -v m="$CTR_MAX_ANN" 'NF >= 3 && n < m { n++; print "::warning::" $3 }'
  if [ "$_nw" -gt "$CTR_MAX_ANN" ]; then echo "ci-time-report: $_nw job(s) crossed the threshold; $CTR_MAX_ANN annotated, the rest are in the job summary"; fi
  _nbad=$(printf '%s\n' "$_res" | awk -F "$TAB" '$1 == "B" { print $2 }')
  if [ -n "$_nbad" ]; then echo "ci-time-report: N/A for $_nbad malformed baseline line(s) (ignored)"; fi
  if [ -n "$_rr" ] && [ -r "$_rr" ]; then echo "row-times: present but per-row comparison needs S0's format; no row annotated"; else echo "row-times: not produced"; fi
  ctr_summary "$_res"
  return 0
}

ctr_summary() {  # <compare output>: one block, the 10 jobs of largest growth over baseline, in the job summary (or stdout)
  _sm=$(printf '%s\n' "$1" | awk -F "$TAB" '$1 == "S"' | LC_ALL=C sort -t "$TAB" -k2,2nr | head -10 | awk -F "$TAB" '{ print $3 }')
  [ -n "$_sm" ] || return 0
  _blk=$(printf '### CI time (WARN only, measured)\n| job | now | baseline | change |\n|---|---|---|---|\n%s\n' "$_sm")
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ] && [ -w "${GITHUB_STEP_SUMMARY:-/nonexistent}" ]; then printf '%s\n' "$_blk" >> "$GITHUB_STEP_SUMMARY"
  else printf '%s\n' "$_blk"; fi
}

# ctr_baseline <runs.tsv> <date>: `<kind><TAB><run id><TAB><job><TAB><minutes>` -> baseline lines (median, n, the main PUSH run's id).
ctr_baseline() {
  [ -r "$1" ] || { echo "ci-time-report: --baseline needs a readable runs file" >&2; return 1; }
  printf '%s' "$2" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || { echo "ci-time-report: --baseline needs a YYYY-MM-DD date" >&2; return 1; }
  awk -F "$TAB" -v d="$2" '
    NF != 4 || $1 !~ /^(pr|push|dispatch)$/ || $2 !~ /^[0-9]+$/ || $4 !~ /^[0-9]+(\.[0-9]+)?$/ { bad = 1; next }
    { j = $3; n[j]++; raw[j, n[j]] = $4 + 0; if ($1 == "push") ref = $2 }
    END {
      if (bad || ref == "") { print "ci-time-report: --baseline input malformed or has no main push run" > "/dev/stderr"; exit 1 }
      for (j in n) {
        c = n[j]
        for (i = 1; i <= c; i++) v[i] = raw[j, i]
        for (i = 2; i <= c; i++) { x = v[i]; k = i - 1; while (k >= 1 && v[k] > x) { v[k + 1] = v[k]; k-- } v[k + 1] = x }
        med = (c % 2) ? v[(c + 1) / 2] : (v[c / 2] + v[c / 2 + 1]) / 2
        printf "job\t%s\t%s\t%d\t%s\t%s\n", j, med, c, ref, d
      }
    }' "$1"
}

selftest() {
  sfail=0; W=$(mktemp -d); trap 'rm -rf "$W"' EXIT INT TERM
  # Every CI runner exports GITHUB_STEP_SUMMARY, and the report then APPENDS its summary block to that file instead of printing it. The stdout
  # legs below read the summary on stdout, so they unset it (it passed locally only because nothing here had it set); the one leg that
  # sets it points it at a temp file of its own and reads that file.
  unset GITHUB_STEP_SUMMARY
  command -v jq >/dev/null 2>&1 || { echo "FAIL: ci-time-report selftest needs jq"; exit 1; }
  _t() { if [ "$1" = ok ]; then echo "PASS: ci-time-report selftest -- $2"; else echo "FAIL: ci-time-report selftest -- $2"; sfail=1; fi; }
  # a jobs reply: name, minutes
  mk() { printf '{"jobs":[{"name":"%s","conclusion":"success","started_at":"2026-10-24T10:00:00Z","completed_at":"2026-10-24T10:%02d:00Z"}]}\n' "$2" "$3" > "$1"; }
  printf 'job\tbuild\t10\t3\t777\t2026-10-01\n' > "$W/base.txt"
  # B12: +60% and +4 min -> one annotation with the quoted reason; +60% and +2 min -> none; +40% and +10 min -> none.
  mk "$W/j1.json" build 16; o=$(sh "$0" --report "$W/j1.json" "$W/base.txt")
  if [ "$(printf '%s\n' "$o" | grep -c '^::warning::')" = 1 ] && printf '%s\n' "$o" | grep -Fq 'The red ratchet stays with SWAS-281, on deterministic measures (cells, rows)' && printf '%s\n' "$o" | grep -Fq 'run 777'; then _t ok "B12 +60% and +6 min: one annotation, the quoted reason, the baseline run id"; else _t no "B12 over both thresholds did not annotate once: [$o]"; fi
  printf 'job\tbuild\t25\t3\t777\t2026-10-01\n' > "$W/b3.txt"; mk "$W/j3.json" build 35
  o=$(sh "$0" --report "$W/j3.json" "$W/b3.txt"); if printf '%s\n' "$o" | grep -q '^::warning::'; then _t no "B12 +40% and +10 min annotated: [$o]"; else _t ok "B12 +40% and +10 min: none (under the percent line)"; fi
  printf 'job\tbuild\t3\t3\t777\t2026-10-01\n' > "$W/b4.txt"; mk "$W/j4.json" build 5
  o=$(sh "$0" --report "$W/j4.json" "$W/b4.txt"); if printf '%s\n' "$o" | grep -q '^::warning::'; then _t no "B12 +67% but +2 min annotated: [$o]"; else _t ok "B12 +67% and +2 min: none (under the minutes line)"; fi
  # B10: the report never reds.
  _r=0; sh "$0" --report "$W/nonexistent.json" "$W/base.txt" > "$W/o1.txt" 2>&1 || _r=$?
  printf 'not json {' > "$W/bad.json"; _r2=0; sh "$0" --report "$W/bad.json" "$W/base.txt" > "$W/o2.txt" 2>&1 || _r2=$?
  mk "$W/huge.json" build 59; _r3=0; sh "$0" --report "$W/huge.json" "$W/missing-baseline.txt" > "$W/o3.txt" 2>&1 || _r3=$?
  printf 'garbage\nline\n' > "$W/b5.txt"; _r4=0; sh "$0" --report "$W/j1.json" "$W/b5.txt" > "$W/o4.txt" 2>&1 || _r4=$?
  _r5=0; sh "$0" --report > "$W/o5.txt" 2>&1 || _r5=$?
  if [ "$_r$_r2$_r3$_r4$_r5" = 00000 ] && grep -q 'N/A' "$W/o1.txt" && grep -q 'N/A' "$W/o2.txt" && grep -q 'N/A' "$W/o3.txt" && grep -q 'N/A' "$W/o4.txt" && grep -q 'N/A' "$W/o5.txt" && ! grep -q '::error' "$W/o1.txt" "$W/o2.txt" "$W/o3.txt" "$W/o4.txt" "$W/o5.txt"; then _t ok "B10 an API error, malformed JSON, a missing baseline, a malformed baseline and no arguments: rc 0 and an N/A line, no ::error::"; else _t no "B10 rc=$_r$_r2$_r3$_r4$_r5"; fi
  # the wrapper itself: a report body that dies (injected `exit 3`) still exits 0; the same body with the wrapper removed goes red.
  sed 's/^ctr_report() {.*/ctr_report() { exit 3/' "$0" > "$W/mut-die.sh"
  sed 's/ctr_report "\$@" ) || :/ctr_report "$@" )/' "$W/mut-die.sh" > "$W/mut-nowrap.sh"
  if cmp -s "$0" "$W/mut-die.sh" || cmp -s "$W/mut-die.sh" "$W/mut-nowrap.sh"; then _t no "B10 mutants did not apply"; else
    _rd=0; sh "$W/mut-die.sh" --report "$W/j1.json" "$W/base.txt" > /dev/null 2>&1 || _rd=$?
    _rm=0; sh "$W/mut-nowrap.sh" --report "$W/j1.json" "$W/base.txt" > /dev/null 2>&1 || _rm=$?
    if [ "$_rd" = 0 ] && [ "$_rm" != 0 ]; then _t ok "B10 a dying report body still exits 0 behind the || : wrapper; MUTANT the wrapper removed goes red (rc $_rm)"; else _t no "B10 wrapper legs: with wrapper rc=$_rd, without rc=$_rm"; fi
  fi
  # B13: a hostile name reaches no annotation property, is percent-encoded in the message, and is markdown-escaped in the summary.
  printf '{"jobs":[{"name":"x::error file=a::forged\\r\\n::error::second `|[link](x)`","conclusion":"success","started_at":"2026-10-24T10:00:00Z","completed_at":"2026-10-24T10:20:00Z"}]}\n' > "$W/j6.json"
  printf 'job\tx::error file=a::forged\\r\\n::error::second `|[link](x)`\t1\t3\t777\t2026-10-01\n' > "$W/b6.txt"
  o=$(sh "$0" --report "$W/j6.json" "$W/b6.txt"); a=$(printf '%s\n' "$o" | grep '^::warning::' || true)
  if [ "$(printf '%s\n' "$o" | grep -c '^::')" = 1 ] && printf '%s\n' "$a" | grep -Fq 'x%3A%3Aerror file=a%3A%3Aforged%0D%0A%3A%3Aerror%3A%3Asecond' && ! printf '%s\n' "$a" | sed 's/^::warning:://' | grep -Fq '::' ; then _t ok "B13 no annotation property; ':' CR LF percent-encoded, so the name forges no second workflow command"; else _t no "B13 annotation not safe: [$o]"; fi
  want=$(printf '%s' '`|[link](x)`' | sed 's/[`|]/\\&/g; s/\[/\\[/g; s/\]/\\]/g')
  case "$o" in
    *"$want"*) _t ok "B13 the summary markdown-escapes the name" ;;
    *) _t no "B13 summary not escaped (want [$want]): [$o]" ;;
  esac
  # B13s: with GITHUB_STEP_SUMMARY SET (as on every CI runner) the summary lands in THAT file, escaped, and not on stdout.
  # The exact CI condition: BOTH GITHUB_STEP_SUMMARY (a temp file) and CI=true exported, in a subshell. stdout must carry only the annotation and
  # the row-times line (no table), and the file must hold the escaped block.
  b13s() {  # <script> -> 0 iff the summary lands in the file, escaped, and stdout holds no summary block
    : > "$W/summary.md"
    _bo=$( export GITHUB_STEP_SUMMARY="$W/summary.md" CI=true; sh "$1" --report "$W/j6.json" "$W/b6.txt" ); _bs=$(cat "$W/summary.md")
    case "$_bs" in *"$want"*) : ;; *) return 1 ;; esac
    if printf '%s\n' "$_bo" | grep -Eq '^(###|\|)'; then return 1; fi
    [ "$(printf '%s\n' "$_bo" | grep -c '^::warning::')" = 1 ]
  }
  if b13s "$0"; then _t ok "B13s with GITHUB_STEP_SUMMARY set and CI=true the summary lands in the file, markdown-escaped, and stdout carries only the annotation"
  else _t no "B13s with GITHUB_STEP_SUMMARY set and CI=true the summary did not land escaped in the file, or stdout held a table"; fi
  sed 's|>> "\$GITHUB_STEP_SUMMARY"|>> /dev/null|' "$0" > "$W/mut-sum.sh"
  if cmp -s "$0" "$W/mut-sum.sh"; then _t no "B13s mutant did not apply"
  elif b13s "$W/mut-sum.sh"; then _t no "B13s MUTANT the summary-file path ignored still passes the leg, so the leg cannot see it"
  else _t ok "B13s MUTANT the summary-file path ignored reds the leg"; fi
  sed 's/gsub(":"; "%3A") | //' "$0" > "$W/mut-enc.sh"
  if cmp -s "$0" "$W/mut-enc.sh"; then _t no "B13 mutant did not apply"; else
    o2=$(sh "$W/mut-enc.sh" --report "$W/j6.json" "$W/b6.txt" 2>&1 || true)
    if printf '%s\n' "$o2" | grep '^::warning::' | sed 's/^::warning:://' | grep -Fq '::'; then _t ok "B13 MUTANT the percent-encoding dropped: a raw '::' reaches the annotation, so the check sees it"; else _t no "B13 the encoding mutant is invisible"; fi
  fi
  # B14: the baseline is the MEDIAN of the release commit's runs, with the main push run's id.
  printf 'pr\t100\tbuild\t30\ndispatch\t300\tbuild\t40\npush\t200\tbuild\t90\n' > "$W/runs.tsv"
  o=$(sh "$0" --baseline "$W/runs.tsv" 2026-10-24)
  if [ "$o" = "$(printf 'job\tbuild\t40\t3\t200\t2026-10-24')" ]; then _t ok "B14 30, 90 and 40 min give baseline 40, n=3, reference = the main push run"; else _t no "B14 [$o]"; fi
  sed 's/v\[(c + 1) \/ 2\]/raw[j, c]/' "$0" > "$W/mut-med.sh"
  if cmp -s "$0" "$W/mut-med.sh"; then _t no "B14 mutant did not apply"; else
    o2=$(sh "$W/mut-med.sh" --baseline "$W/runs.tsv" 2026-10-24 2>&1 || true)
    if [ "$o2" = "$o" ]; then _t no "B14 the newest-run mutant gives the same answer"; else _t ok "B14 MUTANT take-the-newest-run: reads $(printf '%s' "$o2" | cut -f3) not 40"; fi
  fi
  # S0 degradation, stated: no row-times file -> the one line.
  o=$(sh "$0" --report "$W/j1.json" "$W/base.txt"); if printf '%s\n' "$o" | grep -Fxq 'row-times: not produced'; then _t ok "the per-row half degrades to the line 'row-times: not produced' until S0 lands"; else _t no "row-times line missing"; fi
  [ "$sfail" -eq 0 ] && { echo "OK: ci-time-report selftest"; exit 0; } || { echo "FAIL: ci-time-report selftest"; exit 1; }
}

case "${1:-}" in
  --selftest) selftest ;;
  --report)   shift; ( ctr_report "$@" ) || :; exit 0 ;;
  --baseline) shift; [ "$#" -eq 2 ] || { echo "usage: ci-time-report.sh --baseline <runs.tsv> <YYYY-MM-DD>" >&2; exit 1; }; ctr_baseline "$1" "$2"; exit $? ;;
  *)          echo "usage: ci-time-report.sh --report <jobs-json> [<baseline>] [<row-times>] | --baseline <runs.tsv> <date> | --selftest" >&2; exit 1 ;;
esac
