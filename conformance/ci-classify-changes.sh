#!/bin/sh
# ci-classify-changes.sh — decide whether a change-set is DOCS-ONLY, i.e. whether it can possibly affect
# the expensive conformance proofs. CI uses the verdict to skip the heavy shards on a docs-only PR.
#
# What it changes: nothing. Reads a newline-delimited changed-file listing; prints `docs_only=true|false`.
# Guardrails: fail-safe by construction (see below). Never writes, never network.
#
# THE PREDICATE IS DELIBERATELY NARROW: *every* changed path must end in `.md`. Anything else — a `.sh`,
# `.yml`, `.tsv`, an extensionless file, a rename, a deletion of a non-.md file — makes the whole change
# set NOT docs-only.
#
# WHY AN ALLOWLIST AND NOT A DENYLIST. The question is not "does this look risky?" but "can this change
# POSSIBLY affect the expensive proofs?", and the answer must default to YES. A denylist of risky paths
# fails OPEN on every path nobody thought of — and the paths nobody thinks of are exactly where the
# defects live. An allowlist of `.md` fails CLOSED on everything new. In a governance kit a
# mis-classification must cost us CI TIME, never COVERAGE.
#
# FAIL-SAFE, in every ambiguous case -> docs_only=false (run everything):
#   - an EMPTY listing        -> false. "No files" is not "no code"; it is "we could not read the change
#                                set", which is unknown, and unknown means run the full suite.
#   - an UNREADABLE listing   -> false (same reason).
#   - a MIXED listing         -> false (one .sh among fifty .md still needs the full proof).
#   - a path with NO extension-> false.
#   - literally anything else -> false. `true` is emitted from exactly ONE code path, and only when every
#                                line was affirmatively matched as markdown.
#
# The one direction that must NEVER happen is a code change classified as docs-only: that silently skips
# the gates. So the default is `false`, and `true` must be EARNED.
#
# Usage:
#   sh scripts/ci-classify-changes.sh <listing-file>   # prints docs_only=true|false ; exit 0
#   sh scripts/ci-classify-changes.sh --selftest
set -eu

# ── classify <listing-file> : print `docs_only=true` iff the file is non-empty AND every line is a .md
#    path. Every other outcome prints `docs_only=false`. Exit is always 0 — the VERDICT is the output,
#    not the exit code, so a caller can never mistake "classified as code" for "the classifier crashed".
classify() {
  _f=${1:-}

  # Unreadable / absent / empty -> unknown -> full suite.
  if [ -z "$_f" ] || [ ! -r "$_f" ] || [ ! -s "$_f" ]; then
    echo "docs_only=false"
    return 0
  fi

  # Any line that is NOT a .md path disqualifies the whole set. `grep -qv` is the whole predicate:
  # "does there exist a line that fails to match `\.md$`?" If yes -> not docs-only.
  # Note the anchor: `\.md$` matches `docs/x.md` but NOT `x.md.sh`, `mdfile`, or a bare `md`.
  if grep -qvE '\.md$' "$_f"; then
    echo "docs_only=false"
    return 0
  fi

  # THE ONLY PATH THAT EMITS true. Reached only when the listing was readable, non-empty, and every
  # single line ended in `.md`.
  echo "docs_only=true"
  return 0
}

# ── selftest : the classifier's teeth. Every fixture below is a real mis-classification we must not make.
#    The `false` cases matter far more than the `true` case: a wrong `false` costs CI minutes; a wrong
#    `true` SKIPS THE GATES.
selftest() {
  st=0; d=$(mktemp -d)
  _want() { # _want <name> <expected> <lines...>
    _n=$1; _exp=$2; shift 2
    printf '%s\n' "$@" > "$d/$_n"
    _got=$(classify "$d/$_n")
    if [ "$_got" = "docs_only=$_exp" ]; then
      printf 'PASS: %-34s -> %s\n' "$_n" "$_got"
    else
      printf 'FAIL: %-34s -> %s (want docs_only=%s)\n' "$_n" "$_got" "$_exp"; st=1
    fi
  }

  # --- the ONE case that may be true ---
  _want all-markdown          true  'BACKLOG.md' 'docs/architecture/x.md' 'README.md'

  # --- everything else must be false ---
  _want one-shell-among-md    false 'BACKLOG.md' 'conformance/verify.sh' 'README.md'
  _want a-workflow            false '.github/workflows/ci.yml'
  _want a-tsv                 false 'conformance/claims.tsv'
  _want no-extension          false 'CODEOWNERS'
  _want a-profile-yml         false 'profiles/typescript-node/ci.yml'
  _want dotfile               false '.gitignore'
  _want md-lookalike-suffix   false 'evil.md.sh'
  _want md-substring-not-ext  false 'docs/mdnotes'
  _want bare-md-word          false 'md'
  _want uppercase-MD          false 'README.MD'

  # --- fail-safe: the unknown cases ---
  : > "$d/empty"
  _got=$(classify "$d/empty")
  if [ "$_got" = "docs_only=false" ]; then echo "PASS: EMPTY listing                    -> docs_only=false (unknown => run everything)"
  else echo "FAIL: an EMPTY listing classified as $_got — 'no files' is not 'no code'"; st=1; fi

  _got=$(classify "$d/does-not-exist")
  if [ "$_got" = "docs_only=false" ]; then echo "PASS: UNREADABLE listing               -> docs_only=false (unknown => run everything)"
  else echo "FAIL: an UNREADABLE listing classified as $_got"; st=1; fi

  _got=$(classify "")
  if [ "$_got" = "docs_only=false" ]; then echo "PASS: NO argument                      -> docs_only=false (unknown => run everything)"
  else echo "FAIL: a missing argument classified as $_got"; st=1; fi

  # --- THE LOAD-BEARING NEGATIVE: `true` must be EARNED, never the default. If a mutation neuters the
  #     disqualifying grep, EVERY fixture above collapses to true and the suite goes red. Assert directly
  #     that the code fixture cannot reach `true` — this is the assertion the non-vacuity sweep will
  #     mutate, and it must not survive.
  printf '%s\n' 'conformance/verify.sh' > "$d/code"
  if [ "$(classify "$d/code")" = "docs_only=true" ]; then
    echo "FAIL: a CODE change was classified docs-only — this silently skips the conformance gates"; st=1
  else
    echo "PASS: a CODE change can never be classified docs-only (the one direction that must never happen)"
  fi

  rm -rf "$d"
  [ "$st" = 0 ] && echo "ci-classify-changes --selftest: OK" || { echo "ci-classify-changes --selftest: FAIL" >&2; return 1; }
  return "$st"
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  "")         echo "usage: ci-classify-changes.sh <listing-file> | --selftest" >&2; exit 2 ;;
  *)          classify "$1"; exit 0 ;;
esac
