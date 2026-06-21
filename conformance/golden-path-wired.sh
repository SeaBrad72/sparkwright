#!/bin/sh
# golden-path-wired.sh — regression-lock for the G2 golden-path harness: assert the workflow
# exists and still carries its load-bearing steps + triggers, so it can't silently rot.
# Usage: sh conformance/golden-path-wired.sh [--selftest]
set -eu
WF="${GOLDEN_PATH_WF:-.github/workflows/golden-path.yml}"

check_wired() {  # <file>
  f=$1; miss=0
  for tok in \
    'name: golden-path' \
    'profiles/typescript-node' \
    'workflow_dispatch' \
    'schedule' \
    'npm ci' \
    'npm run build' \
    'cp profiles/typescript-node/Dockerfile' \
    'docker build' \
    '/healthz'; do
    grep -qF -- "$tok" "$f" || { echo "FAIL: golden-path workflow missing: $tok"; miss=1; }
  done
  return $miss
}

if [ "${1:-}" = "--selftest" ]; then
  d=$(mktemp -d)
  printf 'name: golden-path\nprofiles/typescript-node\nworkflow_dispatch\nschedule\nnpm ci\nnpm run build\ncp profiles/typescript-node/Dockerfile\ndocker build\n/healthz\n' > "$d/ok.yml"
  printf 'name: golden-path\nprofiles/typescript-node\nworkflow_dispatch\nschedule\nnpm ci\nnpm run build\ncp profiles/typescript-node/Dockerfile\n/healthz\n' > "$d/bad.yml"
  if check_wired "$d/ok.yml" >/dev/null 2>&1; then echo "PASS: selftest complete fixture wired"; else echo "FAIL: selftest complete fixture wrongly failed"; exit 1; fi
  if check_wired "$d/bad.yml" >/dev/null 2>&1; then echo "FAIL: selftest missing-step not detected"; exit 1; else echo "PASS: selftest missing-step detected"; fi
  echo "OK: golden-path-wired selftest"; exit 0
fi

[ -f "$WF" ] || { echo "FAIL: golden-path workflow not found: $WF"; exit 1; }
if check_wired "$WF"; then echo "OK: golden-path harness wired"; exit 0; else echo "FAIL: golden-path harness under-wired"; exit 1; fi
