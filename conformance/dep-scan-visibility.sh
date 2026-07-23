#!/bin/sh
# dep-scan-visibility.sh — a dev-excluding dependency-audit GATE must be paired with a
# report-only full-tree audit, so dev/build-time advisories stay VISIBLE (CP7R5-K4).
#
# THE INVARIANT — for every emitted profiles/*/ci.yml and profiles/*/ci.gitlab-ci.yml:
# IF the dependency-scan gate narrows scope with a dev-excluding flag (--omit=dev,
# --omit dev, --prod, --production), THEN the SAME file must ALSO carry a DISTINCT
# full-tree audit invocation (--audit-level, no dev-excluding flag) marked non-blocking
# (continue-on-error: true | allow_failure: true | || true). If the gate already scans the
# full tree (antecedent false), no report step is required and the file passes.
#
# Usage: sh conformance/dep-scan-visibility.sh [--selftest]
# Exit:  0 = every profile CI satisfies the invariant · 1 = a violation · 2 = bad usage.
#
# Stack-neutral by construction: only a gate that EXCLUDES dev deps triggers the obligation,
# so the 9 full-scope-audit profiles (uvx pip-audit, cargo audit, …) stay green with no
# report step. Comments are stripped first (sed 's/#.*//'), so a token inside a `#` comment
# can never satisfy — or trip — the lock.
#
# MEASURED CEILING (static grep, no YAML parser — matching ci-gates.sh's zero-dependency
# constraint). Stated here, in the artifact, because a reader of a green run is entitled to
# know the shape of that green:
#   - FILE SCOPE: the non-blocking marker is matched anywhere in the file, NOT proven to be
#     attached to the same job/step as the full-tree audit line. A file that carries an
#     unrelated `allow_failure: true` on some other job would satisfy the marker clause. The
#     load-bearing catch is the K4 defect — a --omit=dev gate with NO full-tree audit line
#     anywhere — which no marker placement can mask. Pair with the pipeline actually running.
#   - COMMENT STRIP: `sed 's/#.*//'` truncates at ANY `#`, including one inside a quoted YAML
#     scalar. Fail-open, accepted under the no-parser constraint (same as ci-gates.sh).
#   - TOOL IDENTITY: "same audit tool" is not re-verified token-for-token; a full-tree
#     `--audit-level` line lacking a dev-excluding flag is accepted as the report. In
#     practice a profile emits one audit tool, so this is not a live hole.
# What it changes: nothing — read-only conformance check over emitted profile CI.
# Guardrails: static grep, no YAML parser, no network, no writes.
set -eu

DEV_EXCL='--omit=dev|--omit[[:space:]]+dev|--prod|--production'
MARKER='continue-on-error:[[:space:]]*true|allow_failure:[[:space:]]*true|[|][|][[:space:]]*true'

# check_file <file> -> 0 satisfies the invariant · 1 violates it (prints the offending file).
# Comments are stripped up front so nothing in a `#` comment can satisfy or trip the lock.
check_file() {
  _f=$1
  _s=$(sed 's/#.*//' "$_f")
  # Every audit invocation line (npm/pnpm/pip-audit/cargo audit all contain the word "audit").
  _audit=$(printf '%s\n' "$_s" | grep -E 'audit' || true)
  [ -n "$_audit" ] || return 0                      # no audit invocation -> nothing to require
  # antecedent: some audit line narrows scope with a dev-excluding flag.
  _excl=$(printf '%s\n' "$_audit" | grep -E -- "$DEV_EXCL" || true)
  [ -n "$_excl" ] || return 0                       # full-scope gate -> antecedent false -> pass
  # consequent 1: a DISTINCT full-tree audit line — has --audit-level, lacks any dev-excluding flag.
  _full=$(printf '%s\n' "$_audit" | grep -E -- '--audit-level' | grep -Ev -- "$DEV_EXCL" || true)
  # consequent 2: a non-blocking marker somewhere in the file.
  if printf '%s\n' "$_s" | grep -Eq "$MARKER"; then _mark=y; else _mark=n; fi
  if [ -n "$_full" ] && [ "$_mark" = y ]; then return 0; fi
  echo "FAIL: $_f — the dependency-scan gate excludes dev deps (--omit=dev/--prod) but the file" >&2
  echo "  carries no report-only full-tree audit (--audit-level, no dev-excluding flag, marked" >&2
  echo "  non-blocking: continue-on-error/allow_failure/|| true). Dev & build-time advisories are" >&2
  echo "  silently dropped from CI. Add a report-only step. See CP7R5-K4." >&2
  return 1
}

run() {
  _root=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
  _fail=0; _n=0
  for _f in "$_root"/profiles/*/ci.yml "$_root"/profiles/*/ci.gitlab-ci.yml; do
    [ -f "$_f" ] || continue
    _n=$((_n+1))
    check_file "$_f" || _fail=1
  done
  # A scan that inspected NOTHING must never PASS — a mis-aimed glob is not a clean bill.
  if [ "$_n" = 0 ]; then
    echo "FAIL: dep-scan-visibility evaluated nothing — no profile CI files found." >&2
    return 1
  fi
  if [ "$_fail" = 0 ]; then
    echo "OK: dep-scan-visibility — every profile CI pairs a dev-excluding audit gate with a full-tree report ($_n files)"
    return 0
  fi
  echo "FAIL: dep-scan-visibility — one or more profile CI files hide dev-dependency advisories (see above)." >&2
  return 1
}

selftest() {
  sf=0; d=$(mktemp -d); trap 'rm -rf "$d"' EXIT INT TERM

  # POS anchor: a --omit=dev hard gate PLUS a distinct non-blocking full-tree audit -> PASS.
  printf 'jobs:\n  ci:\n    steps:\n      - id: gate-dep-scan\n        run: npm audit --omit=dev --audit-level=high\n      - name: full-tree report\n        continue-on-error: true\n        run: npm audit --audit-level=high\n' > "$d/pos.yml"
  if check_file "$d/pos.yml" >/dev/null 2>&1; then
    echo "selftest PASS: --omit=dev gate + non-blocking full-tree report -> PASS"
  else echo "selftest FAIL: valid pair wrongly failed"; sf=1; fi

  # NEG 1 (the K4 defect): a --omit=dev gate with NO report line -> FAIL, message names the file.
  printf 'jobs:\n  ci:\n    steps:\n      - id: gate-dep-scan\n        run: npm audit --omit=dev --audit-level=high\n' > "$d/neg1.yml"
  if _o1=$(check_file "$d/neg1.yml" 2>&1); then _r1=0; else _r1=$?; fi
  if [ "$_r1" -ne 0 ] && printf '%s' "$_o1" | grep -qF "$d/neg1.yml"; then
    echo "selftest PASS: dev-excluding gate with no report -> FAIL (names the file)"
  else echo "selftest FAIL: K4 defect not caught (rc=$_r1): $_o1"; sf=1; fi

  # NEG 2 (liveness / no false-positive): a full-scope gate (cargo audit, no dev-excluding flag)
  # with NO report line -> PASS. Antecedent false ⇒ report not required. This is why the 9
  # non-npm stacks stay green.
  printf 'jobs:\n  ci:\n    steps:\n      - id: gate-dep-scan\n        run: cargo audit\n' > "$d/neg2.yml"
  if check_file "$d/neg2.yml" >/dev/null 2>&1; then
    echo "selftest PASS: full-scope gate needs no report -> PASS (antecedent false)"
  else echo "selftest FAIL: full-scope gate wrongly required a report"; sf=1; fi

  # NEG 3 (consequent-1 isolation): a --omit=dev gate PLUS a stray non-blocking marker
  # (continue-on-error on an unrelated step) but NO distinct full-tree --audit-level audit line
  # -> FAIL. Isolates the full-tree-line requirement from the marker clause: a mutant that keeps
  # only the marker check and drops [ -n "$_full" ] would wrongly PASS this fixture, so this leg
  # is what makes the full-tree-line requirement load-bearing on its own.
  printf 'jobs:\n  ci:\n    steps:\n      - id: gate-dep-scan\n        run: npm audit --omit=dev --audit-level=high\n      - name: unrelated flaky step\n        continue-on-error: true\n        run: echo build\n' > "$d/neg3.yml"
  if _o3=$(check_file "$d/neg3.yml" 2>&1); then _r3=0; else _r3=$?; fi
  if [ "$_r3" -ne 0 ] && printf '%s' "$_o3" | grep -qF "$d/neg3.yml"; then
    echo "selftest PASS: --omit=dev gate + stray marker but no full-tree audit line -> FAIL (consequent-1 load-bearing)"
  else echo "selftest FAIL: consequent-1 not isolated (rc=$_r3): $_o3"; sf=1; fi

  if [ "$sf" -eq 0 ]; then echo "OK: dep-scan-visibility selftest"; exit 0; else echo "FAIL: dep-scan-visibility selftest"; exit 1; fi
}

# --selftest dispatch — BEFORE the usage check, or `--selftest` is read as a stray argument.
case "${1:-}" in --selftest) selftest; exit $? ;; esac

case "${1:-}" in
  "")  run; exit $? ;;
  *)   echo "usage: dep-scan-visibility.sh [--selftest]" >&2; exit 2 ;;
esac
