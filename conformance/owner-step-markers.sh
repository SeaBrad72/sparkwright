#!/bin/sh
# owner-step-markers.sh — stale open-step markers must not outlive the steps they describe
# (PHASE-B-HYGIENE R1 / OWNER-STEP-MARKER-SWEEP; meta-control panel #38 finding 2-M1).
#
# THE CLASS: an artifact asserts `OWNER STEP OPEN` (or "not yet bound live") at write time, the
# step later closes, and the marker survives — panel #38 measured FOUR artifacts asserting open
# steps that guard-wired.sh/branch-protection.sh proved closed, and the R1 truth-fix found a FIFTH
# the panel's own sweep missed. A stale open-marker is a standing false claim in exactly the
# artifacts a cold session trusts first.
#
# MECHANISM: scan tracked *.md for the two marker-shaped, LOW-CARDINALITY phrases (exactly these —
# widening the pattern set is a deliberate edit here, never config):
#     `OWNER STEP OPEN`   ·   `not yet bound live`
# A hit line PASSES only when it carries the correct-in-place convention — a DATED ✅/DONE
# correction ON THE SAME LINE (a `20XX-XX-XX` date AND one of ✅/DONE). Files that legitimately
# carry the phrases (the defining board row, panel/log records, this mechanism's own design) are
# ALLOWLISTED BELOW, each with its reason — the aggregate-exclusions precedent: a reasonless or
# unlisted carrier FAILS, because an unreasoned exclusion is a silent widening.
#
# Runs per-PR (strictly stronger than the row's per-release ask — there is no release-finishing
# host to hang it on; measured substrate). HONEST CEILING: line-scoped — a correction recorded on
# a NEIGHBOURING line does not satisfy the convention (REQUIRED-CHECKS.md is the measured example
# and is allowlisted with that reason); and this asserts the CONVENTION is carried, never that the
# correction is TRUE.
#
# Usage: sh conformance/owner-step-markers.sh [--selftest]   (run from repo root)
# Exit: 0 = no stale marker · 1 = a stale marker / an unlisted carrier · 2 = usage. POSIX sh.
set -eu

TAB=$(printf '\t')

# allowlist — <path><TAB><reason>. Path-scoped (the phrases are quotes/definitions throughout
# these files); every entry names its reason, and the reason is the claim to audit.
allowlist() {
cat <<EOF
BACKLOG.md${TAB}the defining OWNER-STEP-MARKER-SWEEP row + Done-row history quote the markers as records; the board's own truth-fix discipline governs it (export-ignored, kit-dev only)
REQUIRED-CHECKS.md${TAB}carries its ✅ correction with the date on the FOLLOWING line (measured, panel #38 2-M1); file frozen this slice (H3: do not touch REQUIRED-CHECKS.md), so the ceiling is disclosed here instead
docs/governance/meta-control-log.md${TAB}panel verdict log — agent-write-denied record; quotes findings
EOF
}

allowed_reason() { # <path> -> prints the reason, rc 0 iff allowlisted
  allowlist | awk -F"$TAB" -v p="$1" '$1==p {print $2; f=1} END{exit !f}'
}

# validate_allowlist — stdin: allowlist lines. rc 1 on an entry with no <TAB>reason (fix-round 1,
# security F5a — mirror selftest-hermetic's validate_exclusions: the reason IS the claim to audit,
# so a reasonless carrier entry is a silent widening even in a hardcoded list).
validate_allowlist() {
  while IFS= read -r _al; do
    [ -n "$_al" ] || continue
    _ar=${_al#*"$TAB"}
    if [ "$_ar" = "$_al" ] || [ -z "$_ar" ]; then
      echo "FAIL: allowlist entry '$_al' carries no <TAB>reason — an unreasoned carrier is a silent widening"
      return 1
    fi
  done
  return 0
}

# corrected_line <line> -> 0 iff EVERY marker phrase on the line is followed — same line, AFTER the
# phrase's LAST occurrence — by the dated ✅/DONE convention. Tightened in fix-round 1 (security F5b
# + reviewer 5): a leading dated correction about ANOTHER step must not mask a trailing open marker,
# and DONE must match as a whole word (ABANDONED is not DONE). Phrase set duplicated from scan() —
# both are the deliberate-edit pattern set the header names.
corrected_line() {
  _cl=$1; _cfound=1
  for _cp in 'OWNER STEP OPEN' 'not yet bound live'; do
    case $_cl in *"$_cp"*) ;; *) continue ;; esac
    _cfound=0
    _csfx=${_cl##*"$_cp"}
    printf '%s' "$_csfx" | grep -qE '20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' || return 1
    printf '%s' "$_csfx" | grep -qE '✅|(^|[^A-Za-z])DONE([^A-Za-z]|$)' || return 1
  done
  return $_cfound
}

# scan [root] — 0 clean, 1 a stale marker / a reasonless allowlist entry. Reads tracked *.md.
scan() {
  _root=${1:-.}
  allowlist | validate_allowlist || return 1
  _stale=0
  _hits=$( (cd "$_root" && git ls-files -z -- '*.md' 2>/dev/null \
      | xargs -0 grep -n -H -e 'OWNER STEP OPEN' -e 'not yet bound live' 2>/dev/null) || true )
  [ -n "$_hits" ] || { echo "owner-step-markers: OK (no open-step marker in any tracked *.md)"; return 0; }
  _seen_allow=""
  while IFS= read -r _h; do
    [ -n "$_h" ] || continue
    _f=${_h%%:*}; _rest=${_h#*:}; _ln=${_rest%%:*}; _line=${_rest#*:}
    if _reason=$(allowed_reason "$_f"); then
      case " $_seen_allow " in *" $_f "*) ;; *) _seen_allow="$_seen_allow $_f"
        printf '  ALLOWLISTED: %s — %s\n' "$_f" "$_reason" ;; esac
      continue
    fi
    if corrected_line "$_line"; then
      printf '  CORRECTED: %s:%s carries the dated ✅/DONE convention\n' "$_f" "$_ln"
      continue
    fi
    printf 'FAIL: STALE open-step marker — %s:%s: %.160s\n' "$_f" "$_ln" "$_line"
    printf '  Either the step is still open (then this red is the reminder), or it closed and the line\n'
    printf '  needs the dated correct-in-place convention (✅/DONE + date ON the line), or the file is a\n'
    printf '  legitimate record carrier and must be allowlisted here WITH its reason.\n'
    _stale=1
  done <<HITS_EOF
$_hits
HITS_EOF
  if [ "$_stale" = 0 ]; then
    echo "owner-step-markers: OK (every open-step marker is allowlisted-with-reason or carries a dated correction)"
    return 0
  fi
  echo "owner-step-markers: FAIL — a stale open-step marker outlives its step (see above)"
  return 1
}

# ---------------------------------------------------------------------------- selftest
selftest() {
  sfail=0
  t=$(mktemp -d); trap 'rm -rf "$t"' EXIT INT TERM

  # fixture repo (hermetic: inline identity; git ls-files needs tracked files)
  st_mkrepo "$t/r"
  # 1. planted STALE marker -> RED
  printf 'work pending\ncarried as an OWNER STEP OPEN on the board row\n' > "$t/r/a.md"
  st_track "$t/r"
  rc=0; out=$(scan "$t/r" 2>&1) || rc=$?
  st_expect "planted stale marker REDs" 1 "$rc"
  printf '%s\n' "$out" | grep -q 'a.md:2' || { echo "FAIL: selftest — the stale hit did not name file:line"; sfail=1; }
  # 2. corrected marker (dated ✅ on the line) -> PASSES
  printf 'work done\n~~OWNER STEP OPEN~~ ✅ DONE 2026-08-07: the step closed; original retained\n' > "$t/r/a.md"
  st_track "$t/r"
  rc=0; scan "$t/r" >/dev/null 2>&1 || rc=$?
  st_expect "dated ✅/DONE correction passes" 0 "$rc"
  # 3. the OTHER phrase, stale -> RED (both patterns load-bearing)
  printf 'the gate is not yet bound live on main\n' > "$t/r/b.md"
  st_track "$t/r"
  rc=0; scan "$t/r" >/dev/null 2>&1 || rc=$?
  st_expect "stale 'not yet bound live' REDs" 1 "$rc"
  # 4. undated ✅ does NOT satisfy the convention (date is load-bearing)
  printf 'the gate is not yet bound live — ✅ fixed at some point\n' > "$t/r/b.md"
  st_track "$t/r"
  rc=0; scan "$t/r" >/dev/null 2>&1 || rc=$?
  st_expect "undated ✅ still REDs (date required on the line)" 1 "$rc"
  # 5. allowlisted carrier passes with its reason printed
  rm -f "$t/r/b.md"
  printf 'panel record quoting OWNER STEP OPEN as evidence\n' > "$t/r/BACKLOG.md"
  st_track "$t/r"
  rc=0; out=$(scan "$t/r" 2>&1) || rc=$?
  st_expect "allowlisted carrier passes" 0 "$rc"
  printf '%s\n' "$out" | grep -q 'ALLOWLISTED: BACKLOG.md' || { echo "FAIL: selftest — allowlist disposition not printed"; sfail=1; }
  # 6. liveness: a clean tree answers OK
  st_mkrepo "$t/c"; printf 'nothing to see\n' > "$t/c/x.md"; st_track "$t/c"
  rc=0; scan "$t/c" >/dev/null 2>&1 || rc=$?
  st_expect "clean tree passes" 0 "$rc"
  # 7. allowlist hygiene, both directions (fix-round 1, F5a)
  rc=0; allowlist | validate_allowlist >/dev/null 2>&1 || rc=$?
  st_expect "the shipped allowlist entries all carry reasons" 0 "$rc"
  rc=0; printf 'X.md\n' | validate_allowlist >/dev/null 2>&1 || rc=$?
  st_expect "a reasonless allowlist entry FAILS" 1 "$rc"
  # 8. reviewer attack fixture: a leading dated correction about ANOTHER step must not mask a
  #    trailing open marker (the convention must follow the phrase on the line).
  printf 'hook install DONE 2026-08-01 ✅ — but the admin flip is still an OWNER STEP OPEN item\n' > "$t/c/x.md"
  st_track "$t/c"
  rc=0; scan "$t/c" >/dev/null 2>&1 || rc=$?
  st_expect "leading unrelated correction does not mask a trailing marker" 1 "$rc"
  # 9. reviewer attack fixture: ABANDONED must not satisfy the DONE token (whole-word match).
  printf 'plan ABANDONED 2026-08-07 — OWNER STEP OPEN forever\n' > "$t/c/x.md"
  st_track "$t/c"
  rc=0; scan "$t/c" >/dev/null 2>&1 || rc=$?
  st_expect "ABANDONED does not satisfy the DONE token (whole word)" 1 "$rc"
  # 10. correction AFTER the marker still passes under the tightened matcher (liveness for the fix)
  printf 'step was carried as an OWNER STEP OPEN item — ✅ DONE 2026-08-07: closed in place\n' > "$t/c/x.md"
  st_track "$t/c"
  rc=0; scan "$t/c" >/dev/null 2>&1 || rc=$?
  st_expect "trailing dated correction still passes (tightening did not over-red)" 0 "$rc"

  [ "$sfail" -eq 0 ] && { echo "owner-step-markers --selftest: OK"; return 0; }
  echo "owner-step-markers --selftest: FAIL"; return 1
}

# --- selftest-only helpers BELOW selftest() (the non-vacuity sweep mutates only pre-marker lines;
#     fixture builders and kill assertions live in the protected oracle region) ---
st_mkrepo() { mkdir -p "$1"; (cd "$1" && git init -q) >/dev/null 2>&1; }
st_track()  { (cd "$1" && git add -A && git -c user.email=t@kit -c user.name=kit commit -q -m f --allow-empty) >/dev/null 2>&1; }
st_expect() { if [ "$2" = "$3" ]; then echo "PASS: selftest — $1"; else echo "FAIL: selftest — $1 (want rc $2, got $3)"; sfail=1; fi; }

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  "")         scan .; exit $? ;;
  *)          echo "usage: owner-step-markers.sh [--selftest]" >&2; exit 2 ;;
esac
