#!/bin/sh
# new-adapter.sh — scaffold a new harness adapter so an unsupported harness is a guided,
# validated path (docs/operations/harness-adapters.md). The kit is never limited to the
# claude-code / generic adapters it ships.
# Usage: sh scripts/new-adapter.sh <harness-name>
# Creates adapters/<harness>/{adapter.json,README.md} from adapters/_TEMPLATE/ (floor-only,
# conforms immediately). Customize, then validate: sh conformance/harness-adapter.sh adapters/<harness>
set -eu

HARNESS="${1:-}"
[ -n "$HARNESS" ] || { echo "usage: new-adapter.sh <harness-name>" >&2; exit 2; }
case "$HARNESS" in
  *[!a-z0-9._-]*|.*|-*) echo "error: harness name must be a simple slug — lowercase a-z, 0-9, '.', '_', '-', not starting with '.' or '-' (e.g. codex, cursor, gemini-cli)" >&2; exit 2 ;;
esac
[ -d adapters/_TEMPLATE ] || { echo "error: run from the kit repo root (adapters/_TEMPLATE not found)" >&2; exit 1; }
[ -e "adapters/${HARNESS}" ] && { echo "error: adapters/${HARNESS} already exists — choose another name" >&2; exit 1; }

# Clean up a partial scaffold if a step below fails (same discipline as new-profile.sh).
cleanup() { [ "${OK:-0}" = 1 ] || rm -rf "adapters/${HARNESS}"; }
trap cleanup EXIT

mkdir -p "adapters/${HARNESS}"
sed "s/__HARNESS__/${HARNESS}/g" adapters/_TEMPLATE/adapter.json > "adapters/${HARNESS}/adapter.json"
sed "s/__HARNESS__/${HARNESS}/g" adapters/_TEMPLATE/README.md   > "adapters/${HARNESS}/README.md"
OK=1

cat <<EOF
Scaffolded:
  adapters/${HARNESS}/adapter.json  (floor-only — conforms immediately)
  adapters/${HARNESS}/README.md

Next:
  1. Customize adapters/${HARNESS}/adapter.json — set controlPlanePaths for the harness's
     namespace; upgrade any dimension to "native" with a "proof" (a check and/or files).
  2. Validate:  sh conformance/harness-adapter.sh adapters/${HARNESS}
  3. Select it at Inception:  sh scripts/incept.sh --harness ${HARNESS}
EOF
