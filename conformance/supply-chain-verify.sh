#!/bin/sh
# supply-chain-verify.sh — regression-lock the GitLab profile's supply-chain tool installs (H4b).
# Asserts the by-download tools (syft/cosign/gitleaks) are CHECKSUM-VERIFIED before exec and that
# the `curl … | sh` pipe-to-shell anti-pattern has not returned. The GitHub profile runs the same
# tools via SHA-pinned Actions (action-pinning.sh covers that path); this guards the GitLab
# install-by-download path. Pairs with ../docs/operations/tool-supply-chain.md.
#   sh conformance/supply-chain-verify.sh [--selftest]
# Exit: 0 = verified · 1 = a regression (pipe-to-shell, or a missing checksum verify) · 2 = usage.
# POSIX sh; dash-clean.
set -eu

PROFILE="profiles/typescript-node/ci.gitlab-ci.yml"
MIN_VERIFIES=3   # one sha256sum -c per by-download tool: gitleaks, syft, cosign

# check_file <path>: print PASS/FAIL; return 1 on any regression.
#  Both assertions ignore COMMENT lines (first non-space char `#`) so prose that merely *names* the
#  anti-pattern (or the verify) is never counted — only real script lines are.
#  (1) NO `curl … | sh` pipe-to-shell. The `sh` is boundary-matched (space or end-of-line after it)
#      so `| sha256sum` is NOT a false hit; `[^|]*` keeps the match within a single command.
#  (2) at least MIN_VERIFIES `sha256sum -c` verifies present (download-then-verify, not blind exec).
check_file() {
  f=$1; rc=0
  if [ ! -f "$f" ]; then echo "FAIL: missing $f"; return 1; fi
  if grep -E 'curl[^|]*\|[[:space:]]*sh([[:space:]]|$)' "$f" | grep -qvE '^[[:space:]]*#'; then
    echo "FAIL: $f pipes a downloaded script to a shell (curl … | sh) — download + checksum-verify instead"; rc=1
  else
    echo "PASS: $f has no curl-pipe-to-shell"
  fi
  n=$(grep -E 'sha256sum[[:space:]]+-c' "$f" | grep -cvE '^[[:space:]]*#' || true)
  if [ "$n" -ge "$MIN_VERIFIES" ]; then
    echo "PASS: $f checksum-verifies its tool installs ($n x sha256sum -c)"
  else
    echo "FAIL: $f has only $n sha256sum -c verify(s); expected >= $MIN_VERIFIES (gitleaks/syft/cosign)"; rc=1
  fi
  return $rc
}

if [ "${1:-}" = "--selftest" ]; then
  sfail=0
  d=$(mktemp -d)
  # gap tree: a curl|sh pipe must be detected as a regression
  printf 'script:\n  - curl -sSfL https://example.com/install.sh | sh -s -- -b /usr/local/bin x\n' > "$d/dirty.yml"
  if check_file "$d/dirty.yml" >/dev/null 2>&1; then echo "FAIL: selftest — curl|sh not detected"; sfail=1; else echo "PASS: selftest — curl|sh regression detected"; fi
  # complete tree: MIN_VERIFIES checksum verifies, no pipe → passes
  printf 'a: sha256sum -c sha.txt\nb: sha256sum -c sha.txt\nc: sha256sum -c sha.txt\n' > "$d/clean.yml"
  if check_file "$d/clean.yml" >/dev/null 2>&1; then echo "PASS: selftest — verified install passes"; else echo "FAIL: selftest — verified install wrongly failed"; sfail=1; fi
  # boundary: `| sha256sum` must NOT be mistaken for a `| sh` pipe (false-positive guard)
  printf 'x: cat f | sha256sum -c sha.txt\ny: sha256sum -c sha.txt\nz: sha256sum -c sha.txt\n' > "$d/boundary.yml"
  if check_file "$d/boundary.yml" >/dev/null 2>&1; then echo "PASS: selftest — | sha256sum not flagged as curl|sh"; else echo "FAIL: selftest — | sha256sum wrongly flagged"; sfail=1; fi
  [ "$sfail" -eq 0 ] && { echo "OK: supply-chain-verify selftest"; exit 0; } || { echo "FAIL: supply-chain-verify selftest"; exit 1; }
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: supply-chain-verify.sh [--selftest]" >&2; exit 2 ;;
esac

echo "Supply-chain tool verification ($PROFILE):"
if check_file "$PROFILE"; then
  echo "OK: GitLab profile tool installs are checksum-verified (no pipe-to-shell)"
  exit 0
else
  echo "FAIL: a supply-chain tool install regressed (see above)"
  exit 1
fi
