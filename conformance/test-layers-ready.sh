#!/bin/sh
# test-layers-ready.sh — conditional, stack-neutral test-LAYER presence check (E1-thin).
#
# For a project with a SERVICE SURFACE (Dockerfile / compose service) it asserts the integration and
# e2e test layers are DEMONSTRATED — detected by broad cross-stack filename convention (a test path
# whose name contains 'integration' / 'e2e', case-insensitive: integration.test.ts, test_integration.py,
# integration_test.go, e2e/, *.e2e.test.ts all match). Projects with no service surface are N/A.
#
# SCOPE — a green run proves the layers are PRESENT by convention, NOT that the tests are meaningful,
# and the layers are behaviourally PROVEN only on the ts-node reference (golden-path runs them); for
# other stacks this is a presence gate until those profiles are built out (E1-full). Necessary, not sufficient.
#
# Usage:
#   sh conformance/test-layers-ready.sh [project-dir]   (default: .)
#   sh conformance/test-layers-ready.sh --selftest
set -eu

# Service surface? (a deployable HTTP/service shape — same spirit as dr-ready/test-data-ready signals)
has_service_surface() {
  _d="$1"
  [ -f "$_d/Dockerfile" ] && return 0
  for _cf in "$_d/compose.yaml" "$_d/compose.yml" "$_d/docker-compose.yml" "$_d/docker-compose.yaml"; do
    [ -f "$_cf" ] && grep -Eiq '^[[:space:]]*services:' "$_cf" && return 0
  done
  return 1
}

# Is a test layer present? $2 = keyword (integration|e2e). Stack-neutral: any non-vendored file
# whose FULL PATH contains the keyword — so both 'integration.test.ts' (keyword in filename) and
# 'e2e/journey_test.go' (keyword in directory) match. NOTE: a non-test file whose path contains the
# keyword (e.g. src/integrationService.ts, src/e2e_config.json) also satisfies this gate — accepted
# E1-thin scope (a presence gate, not a quality gate; see SCOPE note above). Tighter test-context
# scoping is deferred to E1-full. (Prune node_modules/.git/dist/build/coverage to avoid vendored hits.)
has_layer() {
  _d="$1"; _kw="$2"
  find "$_d" \( -name node_modules -o -name .git -o -name dist -o -name build -o -name coverage \) -prune \
    -o -type f -print 2>/dev/null | grep -qFi "${_kw}"
}

check_dir() {
  dir="$1"
  if ! has_service_surface "$dir"; then
    echo "N/A: $dir has no service surface (no Dockerfile / compose service) — integration/e2e layers not applicable"
    return 0
  fi
  miss=""
  has_layer "$dir" integration || miss="$miss integration"
  has_layer "$dir" e2e         || miss="$miss e2e"
  if [ -n "$miss" ]; then
    echo "FAIL: $dir has a service surface but is missing test layer(s):$miss — add a test file whose name contains the layer keyword (e.g. integration.test.* / e2e.test.*). See docs/operations/test-layers.md"
    return 1
  fi
  echo "test-layers-ready: OK — integration + e2e layers present. NOTE: presence-by-convention only (not test quality); behaviourally proven on the ts-node reference (golden-path), a presence gate elsewhere."
  return 0
}

selftest() {
  st=0; base=$(mktemp -d)
  # no service surface -> N/A
  d="$base/cli"; mkdir -p "$d"; printf '# a stateless CLI\n' > "$d/README.md"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest PASS: no-surface -> N/A"; else echo "selftest FAIL: no-surface should be N/A"; st=1; fi
  # service + both layers (ts shape) -> PASS
  d="$base/ts"; mkdir -p "$d/test"; printf 'FROM node\n' > "$d/Dockerfile"
  : > "$d/test/integration.test.ts"; : > "$d/test/e2e.test.ts"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest PASS: ts service+both -> PASS"; else echo "selftest FAIL: ts both should PASS"; st=1; fi
  # service + missing e2e -> FAIL
  d="$base/missing"; mkdir -p "$d/test"; printf 'FROM node\n' > "$d/Dockerfile"; : > "$d/test/integration.test.ts"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest FAIL: missing e2e should FAIL"; st=1; else echo "selftest PASS: missing e2e -> FAIL"; fi
  # STACK-NEUTRAL: a non-ts shape (python + go naming) with a compose service -> PASS (proves detection isn't ts-only)
  d="$base/poly"; mkdir -p "$d/tests" "$d/e2e"
  printf 'services:\n  app:\n    image: x\n' > "$d/compose.yaml"
  : > "$d/tests/test_integration.py"; : > "$d/e2e/journey_test.go"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest PASS: non-ts (py+go) service+both -> PASS (stack-neutral)"; else echo "selftest FAIL: stack-neutral detection broke"; st=1; fi
  # compose WITHOUT services: key -> not a surface -> N/A
  d="$base/nocompose"; mkdir -p "$d"; printf 'version: "3"\n' > "$d/compose.yaml"; printf '# lib\n' > "$d/README.md"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest PASS: compose-without-services -> N/A"; else echo "selftest FAIL: no-services compose should be N/A"; st=1; fi
  if [ "$st" -ne 0 ]; then echo "test-layers-ready --selftest: FAIL" >&2; return 1; fi
  echo "test-layers-ready --selftest: OK (fixtures left in $base)"
  return 0
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  *)          check_dir "${1:-.}"; exit $? ;;
esac
