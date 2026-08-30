#!/bin/sh
# feedback-link-lifecycle-documented.sh — COMPATIBILITY SHIM (CONFORMANCE-DOC-FAMILIES-MERGE, D-240828-4). The check is the
# `feedback-link-lifecycle` row set of conformance/doc-markers.tsv, run by conformance/doc-markers.sh: same verdict, same
# wording, same rc, arguments forwarded. Why this path still exists and what deletes it:
# conformance/mass-acks.txt, the 2026-08-29 `files` line.
set -eu
exec sh "$(dirname "$0")/doc-markers.sh" feedback-link-lifecycle "$@"
