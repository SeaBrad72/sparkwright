#!/bin/sh
# inception-done.sh — verify the Inception-Done gate (START-HERE.md / DEVELOPMENT-PROCESS.md §3)
# in a project directory. Usage: sh conformance/inception-done.sh [dir]   (default: .)
set -eu

DIR="${1:-.}"
cd "$DIR"
fail=0

need() { if [ -e "$1" ]; then echo "PASS present: $1"; else echo "FAIL missing: $1"; fail=1; fi; }

need ENGINEERING-PRINCIPLES.md
need CLAUDE.md
need RUNBOOK.md
need .claude
need .github/workflows/ci.yml

if ls docs/architecture/ADR-000*.md >/dev/null 2>&1; then
  echo "PASS present: docs/architecture/ADR-000*.md"
else
  echo "FAIL missing: docs/architecture/ADR-000*.md"; fail=1
fi

if [ -f BACKLOG.md ] || grep -q "Backlog backend" CLAUDE.md 2>/dev/null; then
  echo "PASS present: backlog (BACKLOG.md or declared backend)"
else
  echo "FAIL missing: BACKLOG.md or a declared backlog backend"; fail=1
fi

# project CLAUDE.md key header fields must be filled (no leftover placeholders)
if grep -Eq '\*\*Project:\*\* \[name\]|\*\*Intent owner:\*\* \[who owns' CLAUDE.md 2>/dev/null; then
  echo "FAIL: project CLAUDE.md key fields not filled (Project / Intent owner)"; fail=1
else
  echo "PASS: project CLAUDE.md key header fields filled"
fi

if [ "$fail" -ne 0 ]; then echo "FAIL: Inception-Done gate not satisfied in '$DIR'"; exit 1; fi
echo "OK: Inception-Done gate satisfied in '$DIR'"
exit 0
