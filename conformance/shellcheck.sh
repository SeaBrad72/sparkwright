#!/bin/sh
# Kit shell regression-lock: lint the kit's MAINTAINER-EDITABLE shell code (dogfooding quality).
# Scope: scripts/*.sh, scripts/kit-guard, conformance/*.sh, hooks/pre-push. The control-plane
# guard under .claude/hooks/ is DELIBERATELY excluded — see collect() for why.
# Floor: error + warning (POSIX -s sh). This shell is currently shellcheck-clean; this keeps it
# that way (dash -n only checks syntax, not lint). CONDITIONAL on shellcheck being installed:
# SKIP-pass if absent (a dev may not have it) — the kit CI installs it and runs it for real, so
# drift IN THE LINTED SCOPE is caught in CI. (The excluded .claude/hooks/ guard core is linted
# NOWHERE — by design; it is regression-locked behaviorally instead, see collect() below.)
#   sh conformance/shellcheck.sh [--selftest]
# Exit: 0 = clean or SKIP · 1 = a finding · 2 = bad usage. POSIX sh; dash-clean.
set -eu

# collect existing kit shell files into the positional params.
# DELIBERATELY excludes .claude/hooks/guard.sh + guard-core.sh — the §13 autonomy-guard core,
# the single most security-sensitive shell in the kit. guard.sh is clean; guard-core.sh carries
# only 3 benign shellcheck warnings (2 redundant-but-still-denying case patterns + 1 cls=read
# false positive — no behavior
# change); silencing those in-place means cosmetic edits to the most sensitive file, so instead
# they're regression-locked BEHAVIORALLY by their own dedicated conformance — agent-autonomy.sh
# (deny-corpus), guard-wired.sh, guard-core-sourced.sh, kit-guard --selftest — not by this lint
# floor. NB: the OTHER control-plane shell (scripts/kit-guard, hooks/pre-push) IS included below —
# it was cleanable with justified disables, so it stays in the lock for maximal coverage. The
# discriminator is cleanable-vs-benign-warnings, not control-plane-ness.
collect() {
  set --
  for f in scripts/*.sh conformance/*.sh; do [ -f "$f" ] && set -- "$@" "$f"; done
  # CP-3: the scripts the kit SHIPS are held to the same bar as the scripts the kit IS. incept copies
  # profiles/<stack>/scaffold/scripts/* into the adopter's scripts/, where this very check scopes them
  # — so a scaffold script that fails shellcheck reddens EVERY adopter's `verify.sh --require` while
  # the kit's own CI never sees it. Linting only our own scripts/ is precisely how that shipped.
  for f in profiles/*/scaffold/scripts/*.sh; do [ -f "$f" ] && set -- "$@" "$f"; done
  [ -f scripts/kit-guard ] && set -- "$@" scripts/kit-guard
  [ -f hooks/pre-push ]    && set -- "$@" hooks/pre-push
  printf '%s\n' "$@"
}

run() {
  command -v shellcheck >/dev/null 2>&1 || { echo "SKIP: shellcheck not installed (kit CI runs it for real)"; return 0; }
  # shellcheck disable=SC2046  # word-splitting the file list is intended here
  set -- $(collect)
  [ "$#" -gt 0 ] || { echo "shellcheck: no kit shell files found"; return 1; }
  if shellcheck -s sh -S warning "$@"; then
    echo "shellcheck: OK ($# kit shell file(s) clean at the error/warning floor)"
    return 0
  fi
  echo "shellcheck: FAIL (findings above) — fix or justify with a '# shellcheck disable=SCnnnn' + reason"
  return 1
}

selftest() {
  command -v shellcheck >/dev/null 2>&1 || { echo "shellcheck --selftest: SKIP (shellcheck not installed)"; return 0; }
  d=$(mktemp -d)
  printf '#!/bin/sh\nx="hello"\nprintf "%%s\\n" "$x"\n' > "$d/clean.sh"
  printf '#!/bin/sh\nx=$1\nif [ "$x" == "bad" ]; then echo bad; fi\n' > "$d/dirty.sh"  # SC3014 (== in POSIX sh)
  shellcheck -s sh -S warning "$d/clean.sh" >/dev/null 2>&1 || { echo "selftest FAIL: clean fixture flagged"; return 1; }
  if shellcheck -s sh -S warning "$d/dirty.sh" >/dev/null 2>&1; then
    echo "selftest FAIL: dirty fixture not flagged"; return 1
  fi
  # fail-closed: run() must FAIL on a tree containing a dirty shell file — proves run()'s own `return 1` is
  # load-bearing, not just that the shellcheck tool works. Runs in a temp cwd so collect() globs the fixture.
  # The `return 1` below is INSIDE selftest() (oracle region) so non-vacuity never neuters it (non-circular).
  dd=$(mktemp -d); mkdir -p "$dd/conformance"
  printf '#!/bin/sh\nx=$1\nif [ "$x" == "bad" ]; then echo bad; fi\n' > "$dd/conformance/dirty.sh"  # SC3014
  # if/else (not `(...); _rrc=$?`) so the subshell's expected non-zero exit doesn't trip this
  # script's own `set -eu` before the exit code can be captured.
  if ( cd "$dd" && run >/dev/null 2>&1 ); then _rrc=0; else _rrc=$?; fi
  [ "$_rrc" != 0 ] || { echo "selftest FAIL: run() did not fail on a dirty tree (fail-closed broken)"; return 1; }
  echo "shellcheck --selftest: OK (clean passes, dirty fails; fixtures left in $d)"
  return 0
}

case "${1:-}" in
  --selftest) selftest ;;
  "")         run ;;
  *)          echo "usage: shellcheck.sh [--selftest]" >&2; exit 2 ;;
esac
exit $?
