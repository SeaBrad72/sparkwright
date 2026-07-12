#!/bin/sh
# Why this gate: sparkwright explain evals
# gate-eval-secrets-ready.sh -- kit-self doc-coherence lock for the gate-eval secret-handling
# reference (E6-d / C5). Asserts docs/operations/secrets-for-ai.md documents how the eval CI job
# obtains its live credential SAFELY -- a short-lived OIDC-minted token, never an embedded key --
# and points at the existing (non-waivable) secret-scan gate for committed-key enforcement.
#
# SCOPE -- a green run proves the REFERENCE is present + carries its load-bearing guidance; it does
# NOT prove any adopter's live OIDC/secrets-manager setup is secure (that is the adopter's infra),
# nor does it scan for secrets (the required, non-waivable `secret-scan` gate does that). Honest
# ceiling: reference provided + structurally proven; live secret-infra security is the adopter's.
# Kit-self check: N/A outside the kit repo (no docs/ROADMAP-KIT.md and no secrets-for-ai.md).
#
# Usage:
#   sh conformance/gate-eval-secrets-ready.sh            (main-path: check the real kit doc)
#   sh conformance/gate-eval-secrets-ready.sh --selftest (fixture anchor + load-bearing negatives)
# Exit: 0 = OK or N/A -- 1 = FAIL (reference missing/under-specified). POSIX sh; dash-clean.
set -eu

DOC="${GATE_EVAL_DOC:-docs/operations/secrets-for-ai.md}"

# The gate-eval reference's load-bearing markers (a generic secrets doc lacks these). One per line;
# the section that lost any of them would silently regress to "just use a static embedded secret".
MARKERS='gate-eval secret handling
OIDC
short-lived
never embedded
secret-scan'

check_doc() {
  d=$1; miss=0
  [ -f "$d" ] || { echo "FAIL: missing gate-eval secret reference $d"; return 1; }
  # Newline-delimited so a marker may contain spaces; each must be present verbatim.
  # `IFS= read` is command-scoped -- never a global IFS assignment (semgrep: ifs-tampering).
  # Heredoc-fed, NOT piped: the loop stays in this shell, so `miss` survives it.
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    # case-insensitive: a heading naturally capitalises "Gate-eval", but the marker is the phrase.
    grep -qiF -- "$m" "$d" || { echo "FAIL: $d gate-eval reference missing '$m' (weak/absent secret-handling guidance)"; miss=1; }
  done <<MARKERS_EOF
$MARKERS
MARKERS_EOF
  return $miss
}

if [ "${1:-}" = "--selftest" ]; then
  d=$(mktemp -d "${TMPDIR:-/tmp}/gate-eval-secrets.XXXXXX"); trap 'rm -rf "$d"' EXIT INT TERM
  st=0

  build_fixture() {  # a conformant secrets-for-ai.md; ONE marker per line so each negative isolates
    cat > "$1" <<'MD'
# Secrets for AI Features

## Gate-eval secret handling (C5)
The eval CI job mints its live-model credential via OIDC (federated identity).
That credential is short-lived, minted per run and scoped to push-to-main.
The key is never embedded in the repo, image, runner, plan, or logs.
The non-waivable secret-scan gate catches any key committed to eval artifacts.
MD
  }

  run_fixture() { rc=0; GATE_EVAL_DOC="$1" sh "$0" >/dev/null 2>&1 || rc=$?; echo "$rc"; }
  expect() { got=$(run_fixture "$d/doc.md"); if [ "$got" = "$2" ]; then echo "selftest PASS: $1"; else echo "selftest FAIL: $1 (expected $2, got $got)"; st=1; fi; }
  fresh() { build_fixture "$d/doc.md"; }

  # liveness anchor: fully conformant -> exit 0
  fresh; expect "conformant gate-eval reference -> exit 0" 0

  # one load-bearing negative per marker (drop the line carrying it -> FAIL)
  for m in "gate-eval secret handling" "OIDC" "short-lived" "never embedded" "secret-scan"; do
    fresh; grep -viF -- "$m" "$d/doc.md" > "$d/doc.md.t" && mv "$d/doc.md.t" "$d/doc.md"
    expect "reference missing '$m' -> exit 1" 1
  done

  if [ "$st" -ne 0 ]; then echo "gate-eval-secrets-ready --selftest: FAIL" >&2; exit 1; fi
  echo "gate-eval-secrets-ready --selftest: OK (anchor + 5 load-bearing negatives: gate-eval-heading/OIDC/short-lived/never-embedded/secret-scan)"
  exit 0
fi

case "${1:-}" in "") : ;; *) echo "usage: gate-eval-secrets-ready.sh [--selftest]" >&2; exit 2 ;; esac

# Kit-self scope: N/A outside the kit repo.
if [ ! -f "docs/ROADMAP-KIT.md" ] && [ ! -f "$DOC" ]; then
  echo "gate-eval-secrets: N/A -- kit-self check (the gate-eval secret reference is the kit's own doc; not applicable outside the kit repo)"
  exit 0
fi

if check_doc "$DOC"; then
  echo "gate-eval-secrets: OK -- gate-eval secret-handling reference present (short-lived OIDC credential, never embedded, secret-scan enforcement). NOTE: does NOT scan for secrets (that is the non-waivable secret-scan gate) or prove an adopter's live secret-infra is secure."
  exit 0
fi
echo "FAIL: gate-eval secret reference under-specified (see reasons above)"
exit 1
