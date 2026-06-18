#!/bin/sh
# review-lane.sh — WS2 conformance: the risk-tiered solo review lane is present + wired.
# Presence-and-wiring check (the artifacts exist and reference each other). Run from the repo root.
# POSIX sh, dash-clean. `--selftest` runs the same presence check (it has no external deps to mock).
set -eu

case "${1:-}" in --selftest|'') ;; *) echo "usage: review-lane.sh [--selftest]" >&2; exit 2 ;; esac

fail=0
need()  { [ -e "$1" ] || { echo "FAIL: missing $1"; fail=1; }; }
grepq() { grep -qi "$2" "$1" 2>/dev/null || { echo "FAIL: $1 missing '$2'"; fail=1; }; }

need templates/REVIEW-RECORD-TEMPLATE.md
need docs/operations/review-lane.md
grepq docs/operations/review-lane.md 'High-risk'
grepq docs/operations/review-lane.md 'compensating'
grepq docs/operations/review-lane.md 'enforce_admins'
grepq templates/REVIEW-RECORD-TEMPLATE.md 'Acknowledgments'
grepq DEVELOPMENT-PROCESS.md 'review-lane'
grepq conformance/audit-evidence-checklist.md 'REVIEW-RECORD'

if [ "$fail" = 0 ]; then echo "OK: solo review lane present + wired (template + review-lane.md + §12 pointer + audit-evidence row)"; exit 0; fi
echo "review-lane: FAIL"; exit 1
