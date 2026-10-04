#!/bin/sh
# Kit shell regression-lock: lint the kit's MAINTAINER-EDITABLE shell code (dogfooding quality).
# Scope: scripts/*.sh, scripts/kit-guard, conformance/*.sh, hooks/pre-push. The control-plane
# guard under .claude/hooks/ is DELIBERATELY excluded — see collect() for why.
# Floor: error + warning (POSIX -s sh). This shell is currently shellcheck-clean; this keeps it
# that way (dash -n only checks syntax, not lint). CONDITIONAL on shellcheck being installed:
# SKIP-pass if absent (a dev may not have it) — the kit CI installs it and runs it for real, so
# drift IN THE LINTED SCOPE is caught in CI. (The excluded .claude/hooks/ guard core is linted
# NOWHERE — by design; it is regression-locked behaviorally instead, see collect() below.)
#   sh conformance/shellcheck.sh [--selftest | --listed <listing-file>]
# --listed (PREPUSH-CORE-DEFAULT): lint only the files that are BOTH in collect()'s scope AND named, one
#   repo-relative path per line, in <listing-file> — the pre-push lane's default arm lints the change's
#   own shell, CI keeps the full lock. Same scope, same flags (one source: collect() + lint_set()).
# Exit: 0 = clean or SKIP · 1 = a finding · 2 = bad usage (incl. a missing/unreadable listing). POSIX sh; dash-clean.
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

# lint_set <files…> — THE one shellcheck invocation (flags + messages), shared by run() and run_listed().
lint_set() {
  if shellcheck -s sh -S warning "$@"; then
    echo "shellcheck: OK ($# kit shell file(s) clean at the error/warning floor)"
    return 0
  fi
  echo "shellcheck: FAIL (findings above) — fix or justify with a '# shellcheck disable=SCnnnn' + reason"
  return 1
}

run() {
  command -v shellcheck >/dev/null 2>&1 || { echo "SKIP: shellcheck not installed (kit CI runs it for real)"; return 0; }
  # shellcheck disable=SC2046  # word-splitting the file list is intended here
  set -- $(collect)
  [ "$#" -gt 0 ] || { echo "shellcheck: no kit shell files found"; return 1; }
  lint_set "$@"
}

# run_listed <listing-file> — collect()'s scope INTERSECTED with the listing (exact whole-line match).
# The listing is validated BEFORE the SKIP test: a bad operand is rc 2 whether or not shellcheck is here.
run_listed() {
  [ -f "$1" ] && [ -r "$1" ] || { echo "shellcheck: --listed needs a readable listing file: $1" >&2; return 2; }
  command -v shellcheck >/dev/null 2>&1 || { echo "SKIP: shellcheck not installed (kit CI runs it for real)"; return 0; }
  _rl_sel=$(collect | while IFS= read -r _rl_f; do
    if grep -qxF -- "$_rl_f" "$1"; then printf '%s\n' "$_rl_f"; fi
  done)
  [ -n "$_rl_sel" ] || { echo "shellcheck: OK (no listed kit shell file)"; return 0; }
  # shellcheck disable=SC2086  # word-splitting the intersected list is intended, as in run()
  set -- $_rl_sel
  lint_set "$@"
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
  # --listed (PREPUSH-CORE-DEFAULT): lints a LISTED dirty file, ignores an UNLISTED dirty one, and is rc 2
  # on a missing listing. Same temp-cwd pattern; every `return 1` is INSIDE selftest() (non-circular).
  printf '#!/bin/sh\nx="hello"\nprintf "%%s\\n" "$x"\n' > "$dd/conformance/clean.sh"
  printf '#!/bin/sh\nx=$1\nif [ "$x" == "bad" ]; then echo bad; fi\n' > "$dd/conformance/dirty2.sh"  # SC3014
  printf 'conformance/dirty.sh\n' > "$dd/list-dirty"; printf 'conformance/clean.sh\n' > "$dd/list-clean"
  printf 'README.md\n' > "$dd/list-none"
  if ( cd "$dd" && run_listed "$dd/list-dirty" >/dev/null 2>&1 ); then _rc=0; else _rc=$?; fi
  [ "$_rc" = 1 ] || { echo "selftest FAIL: --listed did not FAIL on a listed dirty file (rc $_rc)"; return 1; }
  if _lo=$( cd "$dd" && run_listed "$dd/list-clean" 2>&1 ); then _rc=0; else _rc=$?; fi
  [ "$_rc" = 0 ] || { echo "selftest FAIL: --listed linted an UNLISTED dirty file (rc $_rc)"; return 1; }
  case $_lo in *"OK (1 kit shell file(s)"*) ;; *) echo "selftest FAIL: --listed did not lint exactly the one listed clean file: $_lo"; return 1 ;; esac
  if _lo=$( cd "$dd" && run_listed "$dd/list-none" 2>&1 ); then _rc=0; else _rc=$?; fi
  [ "$_rc" = 0 ] || { echo "selftest FAIL: --listed with no in-scope file was not rc 0 (rc $_rc)"; return 1; }
  case $_lo in *"no listed kit shell file"*) ;; *) echo "selftest FAIL: --listed zero-intersection message missing: $_lo"; return 1 ;; esac
  if ( cd "$dd" && run_listed "$dd/nope" >/dev/null 2>&1 ); then _rc=0; else _rc=$?; fi
  [ "$_rc" = 2 ] || { echo "selftest FAIL: --listed on a missing listing was not rc 2 (rc $_rc)"; return 1; }
  echo "shellcheck --selftest: OK (clean passes, dirty fails, --listed scopes; fixtures left in $d)"
  return 0
}

case "${1:-}" in
  --selftest) selftest ;;
  --listed)   [ "$#" -eq 2 ] || { echo "usage: shellcheck.sh --listed <listing-file>" >&2; exit 2; }
              run_listed "$2" ;;
  "")         run ;;
  *)          echo "usage: shellcheck.sh [--selftest | --listed <listing-file>]" >&2; exit 2 ;;
esac
exit $?
