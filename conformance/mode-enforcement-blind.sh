#!/bin/sh
# mode-enforcement-blind.sh — lock that the S1 process-weight mode (incept --mode) is SURFACING-ONLY,
# never an ENFORCEMENT input. Asserts that NO gate across the enforcement surface — conformance checks,
# the gating scripts (preflight/doctor/tier-advice/…), CI workflows, and the pre-push hook — reads the
# stamped `Process mode` field / `INCEPT_PROCESS_MODE` env (scripts/incept.sh, the legitimate producer,
# and this lock are excluded by exact basename). This is the durable guard for the P2 resolution:
# enforcement keys on detected triggers (Dockerfile, evals/, data surface, classification), never on
# the declared mode — so a mode can NEVER weaken an applicable control. The moment someone makes a gate
# key on the mode, CI fails here. (Floor-invariance across modes is NOT checked here: it is a structural
# property of incept's design — the floor stamping runs unconditionally and curate_for_mode is purely
# additive — and running incept inside a conformance check would need the full kit tree in CWD; the
# enforcement-surface grep below is the load-bearing invariant.)
#   sh conformance/mode-enforcement-blind.sh [--selftest]
# Exit: 0 = mode-blind · 1 = a gate reads the mode (regression) · 2 = setup. POSIX sh; dash-clean.
set -eu
cd "$(dirname "$0")/.."
ROOT="${MODE_BLIND_ROOT:-.}"

run() {
  rc=0
  # Scan the whole ENFORCEMENT SURFACE — conformance checks, the gating scripts (preflight/doctor/
  # tier-advice/…), every CI workflow, and the pre-push hook — for any READ of the stamped process
  # mode (`Process mode` in a project CLAUDE.md, or the `INCEPT_PROCESS_MODE` env). A gate that keys
  # on the mode is the forbidden weakening dial. Exclude, by EXACT BASENAME: scripts/incept.sh (the
  # legitimate PRODUCER that stamps the mode) and this lock itself (it names the mode in its asserts).
  # The `--mode` FLAG is intentionally NOT forbidden — incept and any CI step that runs incept use it
  # legitimately; the forbidden thing is a gate CONSUMING the stamped value.
  # Exclude, by EXACT RELATIVE PATH, the two legitimate files: the producer scripts/incept.sh (which
  # stamps the mode) and this lock itself (which names the mode in its asserts). Full-path anchoring
  # (not basename) means an `incept.sh` planted in ANY OTHER dir — e.g. conformance/incept.sh reading
  # the mode — is still caught. `|| true` keeps set -e happy when the inner grep finds nothing or
  # everything is excluded.
  _hits=$(grep -REl "Process mode|INCEPT_PROCESS_MODE" \
            "$ROOT/conformance" "$ROOT/scripts" "$ROOT/.github/workflows" "$ROOT/hooks" 2>/dev/null \
          | grep -vE '(^|/)scripts/incept\.sh$|(^|/)conformance/mode-enforcement-blind\.sh$' || true)
  if [ -n "$_hits" ]; then
    echo "FAIL: a gate reads the process mode (enforcement must be mode-blind):"
    printf '%s\n' "$_hits" | sed 's/^/  /'
    rc=1
  fi
  [ "$rc" -eq 0 ] && echo "PASS: process mode is enforcement-blind (no gate / script / workflow / hook reads it)"
  return $rc
}

if [ "${1:-}" = "--selftest" ]; then
  sfail=0
  run >/dev/null 2>&1 || { echo "mode-enforcement-blind --selftest: FAIL (real tree not green)"; sfail=1; }
  # negative: a conformance dir containing a mode-reading check must FAIL the lock.
  _n=$(mktemp -d); mkdir -p "$_n/conformance" "$_n/.github/workflows"
  printf '#!/bin/sh\ncase "$mode" in prototype) exit 0;; esac\n# Process mode\n' > "$_n/conformance/bad.sh"
  : > "$_n/.github/workflows/ci.yml"
  # Direct rebind of $ROOT (NOT `MODE_BLIND_ROOT=$_n run` — an env-prefix does not rebind the
  # already-captured $ROOT; the S2/S3 lesson). Save/restore so the positive run above is unaffected.
  _saved_root="$ROOT"; ROOT="$_n"
  if run >/dev/null 2>&1; then echo "mode-enforcement-blind --selftest: FAIL (mode-reading check passed)"; sfail=1; fi
  ROOT="$_saved_root"
  rm -rf "$_n"
  [ "$sfail" -eq 0 ] && { echo "mode-enforcement-blind --selftest: OK"; exit 0; } || exit 1
fi

run
