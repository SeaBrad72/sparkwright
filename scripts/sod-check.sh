#!/bin/sh
# sod-check.sh — neutral separation-of-duties gate (the FLOOR; forge-agnostic).
# PASS iff at least one approver identity is distinct from the PR/MR author AND from
# every commit-author — i.e. a ratifier exists who did not author the work. Pure
# identity-set comparison; NO forge-specific code. A per-forge adapter (e.g.
# docs/operations/sod-gate.github.yml, or GitLab native approval rules) supplies inputs.
#   Inputs (env; identities space/newline-separated; normalized: trimmed + case-folded;
#           each token is ONE identity — embedded spaces are reinterpreted as separators):
#     SOD_AUTHOR          the PR/MR author identity (required)
#     SOD_APPROVERS       approving-reviewer identities
#     SOD_COMMIT_AUTHORS  commit-author identities on the branch
#   exit 0 — PASS (a distinct ratifier exists)
#   exit 1 — FAIL (no distinct ratifier) OR unverifiable under CI/--require (fail-closed)
#   exit 2 — UNVERIFIED (inputs absent) when NOT under CI/--require — NOT a pass.
# Honest ceiling: this proves the IDENTITY logic. Server-side enforcement is the adopter's
# branch-protection / forge approval rules; the ratifying identity must be one the building
# agent cannot assume. See docs/operations/separation-of-duties.md.
#   usage: sh scripts/sod-check.sh [--require] | --selftest
set -eu

REQUIRE="${REQUIRE:-0}"
[ -n "${CI:-}" ] && REQUIRE=1
for a in "$@"; do
  case "$a" in
    --require) REQUIRE=1 ;;
    --selftest) ;;  # dispatched below
    -*) echo "usage: sod-check.sh [--require] | --selftest" >&2; exit 2 ;;
  esac
done

# normalize a blob of identities -> one lowercased, trimmed, de-duped identity per line.
norm() {
  printf '%s' "$1" | tr ' \t' '\n' | tr '[:upper:]' '[:lower:]' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' | sort -u || true
}

# decide: prints the verdict and EXITS with the status (mirrors branch-protection.sh's
# classify() — exit-in-function so the run path terminates; selftest calls it in a subshell).
decide() {
  author=$(norm "${SOD_AUTHOR:-}")
  approvers=$(norm "${SOD_APPROVERS:-}")
  commit_authors=$(norm "${SOD_COMMIT_AUTHORS:-}")
  if [ -z "$author" ] || [ -z "$approvers" ]; then
    if [ "$REQUIRE" = "1" ]; then
      echo "FAIL: separation-of-duties unverifiable (missing author or approvers) and verification is required (CI/--require)."
      exit 1
    fi
    echo "UNVERIFIED: supply SOD_AUTHOR + SOD_APPROVERS. (NOT a pass.)"
    exit 2
  fi
  # excluded = the author plus everyone who committed (a code author cannot be the sole ratifier).
  excluded=$(printf '%s\n%s\n' "$author" "$commit_authors" | grep -v '^$' | sort -u || true)
  # A distinct ratifier = an approver in NONE of the excluded identities. Compared with grep -x -F
  # (whole-line, FIXED strings): identities match LITERALLY — never as a glob or regex, never
  # word-split — so a token like '*' or 'a.b' is a literal identity and the verdict can NEVER depend
  # on the working directory. -F takes the newline-separated excluded set as multiple fixed patterns.
  ratifier=$(printf '%s\n' "$approvers" | grep -vxF -- "$excluded" | head -n 1 || true)
  if [ -n "$ratifier" ]; then
    echo "OK: separation-of-duties satisfied — '$ratifier' ratified work it did not author."
    exit 0
  fi
  echo "FAIL: no approver is distinct from the author and all commit-authors — author cannot ratify own work."
  exit 1
}

selftest() {
  st=0
  chk() {  # expect author approvers commit_authors require label
    e=$1; a=$2; ap=$3; ca=$4; req=$5; lbl=$6
    ( SOD_AUTHOR="$a"; SOD_APPROVERS="$ap"; SOD_COMMIT_AUTHORS="$ca"; REQUIRE="$req"; decide ) >/dev/null 2>&1 && g=0 || g=$?
    if [ "$g" = "$e" ]; then echo "selftest PASS: $lbl -> exit $g"; else echo "selftest FAIL: $lbl want $e got $g"; st=1; fi
  }
  chk 0 'agent-bot' 'alice'             'agent-bot'      0 "distinct approver"
  chk 1 'alice'     'alice'             'alice'          0 "author-only approves"
  chk 1 'agent-bot' 'bob'               'agent-bot bob'  0 "approver also committed"
  chk 2 'agent-bot' ''                  'agent-bot'      0 "no approvals (no CI) -> UNVERIFIED"
  chk 1 'agent-bot' ''                  'agent-bot'      1 "no approvals + require -> FAIL"
  chk 0 'agent-bot' 'agent-bot alice'   'agent-bot'      0 "distinct + author also approved"
  chk 1 'Agent-Bot' 'agent-bot'         'Agent-Bot'      0 "casing normalized -> same identity FAIL"
  chk 1 '*'         '*'                 ''               0 "metachar identity compared literally (no glob)"
  chk 0 'a.ice'     'alice'             ''               0 "regex metachar in author is literal (grep -F), not a pattern"
  [ "$st" = "0" ] && echo "sod-check --selftest: OK"
  return "$st"
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  *) decide ;;
esac
