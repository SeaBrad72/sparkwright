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

# the Target harness(es) field must be stamped AND every selected adapter must conform to the
# boundary contract — the Inception-Done enforcement of the harness floor (brownfield-critical:
# an adopter's merged repo can't pass Inception until its declared adapter(s) actually conform).
hline=$(grep -E '^\- \*\*Target harness\(es\)\*\*' CLAUDE.md 2>/dev/null || true)
if [ -z "$hline" ]; then
  echo "FAIL: project CLAUDE.md missing the Target harness(es) field"; fail=1
else
  # value after the '(§harness-neutrality): ' marker, first whitespace token (the comma-list)
  hval=$(printf '%s' "$hline" | sed 's/^.*(§harness-neutrality): *//' | cut -d' ' -f1)
  case "$hval" in
    *'['*|'') echo "FAIL: Target harness(es) not stamped (placeholder remains)"; fail=1 ;;
    *)
      for _h in $(printf '%s' "$hval" | tr ',' ' '); do
        _h=$(printf '%s' "$_h" | sed 's/[[:punct:][:space:]]*$//')  # G13: tolerate a trailing period/space in the stamped value
        [ -z "$_h" ] && continue
        if ! [ -d "adapters/$_h" ]; then
          echo "FAIL: harness adapter '$_h' directory not found — expected: adapters/$_h"; fail=1
        elif sh conformance/harness-adapter.sh "adapters/$_h" >/dev/null 2>&1; then
          echo "PASS: harness adapter '$_h' conforms to the boundary contract"
        else
          echo "FAIL: harness adapter '$_h' does not conform — run: sh conformance/harness-adapter.sh adapters/$_h"; fail=1
        fi
      done ;;
  esac
fi

if [ "$fail" -ne 0 ]; then echo "FAIL: Inception-Done gate not satisfied in '$DIR'"; exit 1; fi
echo "OK: Inception-Done gate satisfied in '$DIR'"
exit 0
