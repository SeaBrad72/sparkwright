#!/bin/sh
# inception-done.sh — verify the Inception-Done gate (START-HERE.md / DEVELOPMENT-PROCESS.md §3)
# in a project directory. Usage: sh conformance/inception-done.sh [dir]   (default: .)
# NOTE: expected to FAIL at the kit root (the kit is the template source, not an
# instantiated project). It passes only in a project that has completed Inception.
set -eu

DIR="${1:-.}"
cd "$DIR"
fail=0

need() { if [ -e "$1" ]; then echo "PASS present: $1"; else echo "FAIL missing: $1"; fail=1; fi; }

need ENGINEERING-PRINCIPLES.md
need CLAUDE.md
need RUNBOOK.md
need .env.example
need .claude

# CI pipeline — platform-aware: accept the GitHub OR GitLab path (incept writes one per --ci),
# so a GitLab adopter doesn't dead-end at this gate (it hard-required the GitHub path before).
if [ -f .github/workflows/ci.yml ] || [ -f .gitlab-ci.yml ]; then
  echo "PASS present: CI pipeline (.github/workflows/ci.yml or .gitlab-ci.yml)"
else
  echo "FAIL missing: a CI pipeline (.github/workflows/ci.yml or .gitlab-ci.yml)"; fail=1
fi

# the guard must be WIRED, not just present (slice 7e; docs/adoption/brownfield.md).
# guard-wired is three-state: 0 wired · 1 dark · 2 UNVERIFIED (jq absent). UNVERIFIED is
# fail-closed here — the guard hook itself needs jq, so jq-absent means it can't run anyway.
if [ -f conformance/guard-wired.sh ]; then
  if sh conformance/guard-wired.sh . >/dev/null 2>&1; then gw=0; else gw=$?; fi
  if [ "$gw" -eq 0 ]; then
    echo "PASS: runtime guard wired (PreToolUse → guard.sh, matcher admits mutating tools)"
  elif [ "$gw" -eq 2 ]; then
    echo "FAIL: runtime guard wiring UNVERIFIED — install jq (the guard hook needs it too), then: sh conformance/guard-wired.sh"; fail=1
  else
    echo "FAIL: runtime guard not wired — run: sh conformance/guard-wired.sh"; fail=1
  fi
else
  echo "FAIL: conformance/guard-wired.sh missing"; fail=1
fi

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
