#!/bin/sh
# whitespace-clean.sh — conformance gate (K12 Cause A): the tracked source ships ZERO
# git-whitespace errors (trailing whitespace, a blank line at EOF, a space-before-tab).
# The oracle is git's OWN whitespace detector, run over committed HEAD via
#   git diff --check <empty-tree> HEAD
# so the verdict is exactly what a reviewer's `git diff --check` would surface — no bespoke
# regex to drift. Any finding FAILs and is printed verbatim (path:line: reason), so the fix
# is unambiguous. There are no intentional Markdown hard-breaks in this tree, so trailing
# whitespace is always accidental and always a violation.
#   sh conformance/whitespace-clean.sh            # scan committed HEAD (the real run)
#   sh conformance/whitespace-clean.sh --selftest # mutation-proof it has teeth
# HONEST CEILING: proves the COMMITTED tree is git-whitespace-clean at scan time — NOT that a
# later uncommitted edit is clean (that is the author's / pre-commit's job), and NOT any style
# beyond git's three whitespace classes.
# What it changes: nothing — read-only; asserts the tracked source ships zero git-whitespace errors.
# Guardrails: read-only; operates on committed HEAD via `git diff --check` against the empty tree; no writes, no network.
# Exit: 0 = clean · 1 = a git-whitespace error in tracked source · 2 = usage. POSIX sh; dash-clean.
set -eu
cd "$(dirname "$0")/.." 2>/dev/null || true

# The empty tree object — diffing HEAD against it makes EVERY committed line an "added" line,
# so git's whitespace detector inspects the whole tree, not just an incremental diff.
EMPTY=$(git hash-object -t tree /dev/null)

# check_repo <dir> : run git's whitespace detector over <dir>'s content. rc0 = clean;
# rc1 = at least one finding (printed verbatim to stderr). The _rc accumulator is the
# load-bearing FAIL idiom the --selftest kills (neutering it -> a dirty tree passes -> RED).
# On a BORN HEAD it diffs committed HEAD against the empty tree (the real run). On an UNBORN
# HEAD — a freshly-incepted adopter tree, pre-first-commit, which the CI artifact-gate scans via
# verify.sh — it stages the worktree into a THROWAWAY index (never the real one) and checks the
# would-be-committed content, so the check KEEPS ITS TEETH on the incepted artifact instead of
# N/A-ing out. `git add -A` respects the shipped .gitignore, so scratch/node_modules are excluded.
check_repo() {
  _dir=$1
  _rc=0
  _out=$( cd "$_dir" && {
    if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
      git diff --check "$EMPTY" HEAD -- . 2>&1 || true
    else
      # THROWAWAY index: git rejects a pre-existing empty file as a corrupt index ("index file
      # smaller than expected"), so point GIT_INDEX_FILE at a NONEXISTENT path inside a temp dir
      # (git creates it) — not `mktemp`'s zero-byte file.
      _idxd=$(mktemp -d) || { echo "FAIL: mktemp for throwaway index"; exit 0; }
      _idx="$_idxd/idx"
      GIT_INDEX_FILE="$_idx" git add -A 2>/dev/null || true
      GIT_INDEX_FILE="$_idx" git diff --cached --check "$EMPTY" 2>&1 || true
      rm -rf "$_idxd"
    fi
  } )
  if [ -n "$_out" ]; then
    echo "FAIL: git-whitespace errors in tracked source:" >&2
    printf '%s\n' "$_out" >&2
    _rc=1
  fi
  return $_rc
}

run() {
  if check_repo .; then
    echo "OK: tracked source is git-whitespace-clean"
    return 0
  fi
  return 1
}

# --- selftest (the NON-VACUITY oracle; everything at/after this marker is emitted verbatim by
#     the mutation harness, so its st=1 accumulator can never be neutered). Builds two throwaway
#     git repos — one clean, one whose final line is blank / carries a trailing space — and
#     asserts check_repo() reports clean vs. dirty. Neutering the check's _rc=1 flips the dirty
#     legs GREEN and this selftest goes RED (KILLED). ---
selftest() {
  st=0

  _git() { git -c user.email=t@example.com -c user.name=tester -c commit.gpgsign=false "$@"; }

  # commit_tree <dir> <file-content-printf-arg> : init a repo, write one file, commit it.
  commit_tree() {
    _t=$1
    git init -q "$_t"
    printf '%b' "$2" > "$_t/f.txt"
    ( cd "$_t" && git add -A && _git commit -qm init )
  }

  # Positive anchor — a genuinely clean tree: check_repo must report clean (rc0).
  _cdir=$(mktemp -d)
  commit_tree "$_cdir" 'hello\nworld\n'
  if check_repo "$_cdir" >/dev/null 2>&1; then
    echo "selftest PASS: clean tree -> check_repo reports clean"
  else
    echo "selftest FAIL: clean tree wrongly flagged dirty (false positive)"; st=1
  fi

  # Load-bearing negative A — a trailing BLANK LINE at EOF: check_repo MUST report dirty (rc!=0).
  _bdir=$(mktemp -d)
  commit_tree "$_bdir" 'hello\nworld\n\n'
  if check_repo "$_bdir" >/dev/null 2>&1; then
    echo "selftest FAIL: trailing blank line at EOF NOT flagged (VACUOUS — the check has no teeth)"; st=1
  else
    echo "selftest PASS: trailing blank line at EOF flagged dirty"
  fi

  # Load-bearing negative B — a TRAILING SPACE on a content line: check_repo MUST report dirty.
  _sdir=$(mktemp -d)
  commit_tree "$_sdir" 'hello \nworld\n'
  if check_repo "$_sdir" >/dev/null 2>&1; then
    echo "selftest FAIL: trailing whitespace NOT flagged (VACUOUS — the check has no teeth)"; st=1
  else
    echo "selftest PASS: trailing whitespace flagged dirty"
  fi

  # init_tree <dir> <content> : init a repo, write one file, but DO NOT commit — leaves HEAD UNBORN.
  init_tree() {
    _t=$1
    git init -q "$_t"
    printf '%b' "$2" > "$_t/f.txt"
  }

  # Load-bearing negative C (C1 unborn-HEAD path) — a freshly-incepted adopter tree has an UNBORN
  # HEAD; check_repo must still catch a trailing blank via its throwaway-index leg. MUST report dirty.
  _udir=$(mktemp -d)
  init_tree "$_udir" 'hello\nworld\n\n'
  if check_repo "$_udir" >/dev/null 2>&1; then
    echo "selftest FAIL: unborn-HEAD trailing blank NOT flagged (VACUOUS — no teeth on incepted tree)"; st=1
  else
    echo "selftest PASS: unborn-HEAD trailing blank flagged dirty"
  fi

  # Positive anchor for the unborn-HEAD path — a clean, uncommitted tree must report clean (rc0):
  # the throwaway-index leg must not false-FAIL the artifact-gate on a legitimately clean adopter tree.
  _uclean=$(mktemp -d)
  init_tree "$_uclean" 'hello\nworld\n'
  if check_repo "$_uclean" >/dev/null 2>&1; then
    echo "selftest PASS: unborn-HEAD clean tree -> check_repo reports clean"
  else
    echo "selftest FAIL: unborn-HEAD clean tree wrongly flagged dirty (false positive)"; st=1
  fi

  if [ "$st" = 0 ]; then
    echo "OK: whitespace-clean selftest — clean passes (born + unborn HEAD); a trailing blank line AND a trailing space are both caught, on committed HEAD AND on an unborn-HEAD worktree"
    return 0
  fi
  echo "FAIL: whitespace-clean selftest"
  return 1
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  "")         run; exit $? ;;
  *)          echo "usage: whitespace-clean.sh [--selftest]" >&2; exit 2 ;;
esac
