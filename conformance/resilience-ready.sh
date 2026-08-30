#!/bin/sh
# resilience-ready.sh — COMPATIBILITY SHIM (CONFORMANCE-DOC-FAMILIES-MERGE, D-240828-4). The check is the
# `resilience-ready` row set of conformance/readiness.tsv, run by conformance/readiness.sh: same verdict, same
# wording, same rc, arguments forwarded. Why this path still exists and what deletes it:
# conformance/mass-acks.txt, the 2026-08-29 `files` line.
set -eu
exec sh "$(dirname "$0")/readiness.sh" resilience-ready "$@"
