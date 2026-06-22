#!/bin/sh
# feature-flags-ready.sh — conditional, fail-closed feature-flag DOC check (adopter-facing).
#
# If a project HAS a feature-flag surface (a flags module, or a FEATURE_ env convention in source),
# it asserts the flag DISCIPLINE is documented: the kill-switch toggle (how to disable) AND flag
# retirement (don't let flags rot). Projects with NO flag surface are N/A (skip-pass) — flags are
# not forced on every project.
#
# SCOPE — read before trusting a green run: this verifies the discipline is WRITTEN DOWN, NOT that a
# flag was ever flipped or that a kill-switch was drilled. A green run is necessary, not sufficient.
# It is an honest floor, not a cage: a project that renames its flag surface to dodge detection is
# caught by review, not this grep. See docs/operations/feature-flags.md.
#
# Usage:
#   sh conformance/feature-flags-ready.sh [project-dir]   (default: .)
#   sh conformance/feature-flags-ready.sh --selftest
#
# NOTE (applied fix): the grep surface-detection in the brief passed "$dir/src" and "$dir/app"
# unconditionally. When one of those directories does not exist, grep (ugrep on macOS) exits 2
# even when it found matches in the other directory, causing surface=0 to be reported incorrectly.
# The fix: build grep_dirs from only the directories that exist before invoking grep. This preserves
# the brief's intent exactly while guarding against the set -eu abort / false-negative hazard.
set -eu

check_dir() {
  dir="$1"; fail=0

  # Detect a flag surface: a flags module, or a FEATURE_<UPPER> token in tracked-ish source.
  surface=0
  for f in "$dir"/src/flags.* "$dir"/app/flags.* "$dir"/src/*/flags.*; do
    [ -f "$f" ] && { surface=1; break; }
  done
  if [ "$surface" -eq 0 ]; then
    # Build grep target list from only directories that exist (guard against missing src/app).
    grep_dirs=""
    [ -d "$dir/src" ] && grep_dirs="${grep_dirs:+$grep_dirs }$dir/src"
    [ -d "$dir/app" ] && grep_dirs="${grep_dirs:+$grep_dirs }$dir/app"
    # shellcheck disable=SC2086  # intentional word-split: pass each existing dir as a separate grep arg
    if [ -n "$grep_dirs" ] && grep -rIlE 'FEATURE_[A-Z][A-Z0-9_]+' $grep_dirs >/dev/null 2>&1; then
      surface=1
    fi
  fi

  if [ "$surface" -eq 0 ]; then
    echo "N/A: $dir has no feature-flag surface (no flags module / FEATURE_ env convention) — skipping"
    return 0
  fi

  # Collect candidate doc text: RUNBOOK.md + any docs/*.md.
  docs="$dir/RUNBOOK.md"
  for m in "$dir"/docs/*.md "$dir"/docs/**/*.md; do [ -f "$m" ] && docs="$docs $m"; done

  has_killswitch=0; has_retire=0
  for m in $docs; do
    [ -f "$m" ] || continue
    grep -Eiq 'kill[- ]switch|disable the flag|flag[- ]off|toggle (it )?off' "$m" && has_killswitch=1
    grep -Eiq 'retir(e|ing|ement)|remove the flag|stale flag|clean ?up the flag' "$m" && has_retire=1
  done

  if [ "$has_killswitch" -eq 0 ]; then
    echo "FAIL: $dir has a flag surface but no documented kill-switch/disable procedure (RUNBOOK.md or docs/) — see docs/operations/feature-flags.md"; fail=1
  fi
  if [ "$has_retire" -eq 0 ]; then
    echo "FAIL: $dir has a flag surface but no documented flag-retirement ritual (RUNBOOK.md or docs/) — see docs/operations/feature-flags.md"; fail=1
  fi

  if [ "$fail" -ne 0 ]; then return 1; fi
  echo "feature-flags-ready: OK — flag discipline (kill-switch + retirement) documented. NOTE: verifies documentation only, NOT that a flag was flipped or a kill-switch drilled."
  return 0
}

selftest() {
  st_fail=0; base=$(mktemp -d)

  # d1: no surface -> N/A skip
  d1="$base/none"; mkdir -p "$d1/src"; printf 'export const x = 1;\n' > "$d1/src/index.ts"
  if check_dir "$d1" >/dev/null 2>&1; then echo "selftest PASS: no surface -> N/A"; else echo "selftest FAIL: no surface should skip-pass"; st_fail=1; fi

  # d2: flag surface (module) + full docs -> OK
  d2="$base/ok"; mkdir -p "$d2/src" "$d2/docs"; printf 'export const FLAGS = {};\n' > "$d2/src/flags.ts"
  printf '# Ops\nKill-switch: set FEATURE_X=false and restart.\nRetire the flag once permanent.\n' > "$d2/docs/feature-flags.md"
  if check_dir "$d2" >/dev/null 2>&1; then echo "selftest PASS: surface+docs -> OK"; else echo "selftest FAIL: surface+docs should pass"; st_fail=1; fi

  # d3: flag surface but docs missing retirement -> FAIL
  d3="$base/fail"; mkdir -p "$d3/src"; printf 'const f = process.env.FEATURE_NEW_THING;\n' > "$d3/src/app.ts"
  printf '# RUNBOOK\nKill-switch: toggle it off.\n' > "$d3/RUNBOOK.md"
  if check_dir "$d3" >/dev/null 2>&1; then echo "selftest FAIL: missing-retirement should FAIL"; st_fail=1; else echo "selftest PASS: missing-retirement -> FAIL"; fi

  # d4: FEATURE_ env surface + full docs in RUNBOOK -> OK (detection via env token, docs via RUNBOOK)
  d4="$base/envok"; mkdir -p "$d4/src"; printf 'const f = process.env.FEATURE_NEW_THING;\n' > "$d4/src/app.ts"
  printf '# RUNBOOK\nKill-switch: flag-off and restart.\nRetire stale flags promptly.\n' > "$d4/RUNBOOK.md"
  if check_dir "$d4" >/dev/null 2>&1; then echo "selftest PASS: env-surface+docs -> OK"; else echo "selftest FAIL: env-surface+docs should pass"; st_fail=1; fi

  if [ "$st_fail" -ne 0 ]; then echo "feature-flags-ready --selftest: FAIL" >&2; return 1; fi
  echo "feature-flags-ready --selftest: OK (skip/OK/FAIL/env-surface all behaved; fixtures left in $base)"
  return 0
}

case "${1:-}" in
  --selftest) selftest ;;
  *)          check_dir "${1:-.}" ;;
esac
exit $?
