#!/bin/sh
# missing-guardrails.sh — fixture: header carries a purpose + 'What it changes:' but
# OMITS the 'Guardrails:' label (must FAIL — load-bearing negative for the guardrails label).
# What it changes: read-only — fixture; mutates nothing.
echo "fixture: missing guardrails"
