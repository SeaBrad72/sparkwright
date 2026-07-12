#!/bin/sh
# backlog-adapters.sh — drift lock for the named backlog backends (slice 7d).
#
# The named set must agree across THREE surfaces, or "named ≠ supported" drift
# creeps back in:
#   1. scripts/incept.sh           — the BACKLOG_BACKENDS set (short tokens)
#   2. DEVELOPMENT-PROCESS.md §6    — the backend table (display names)
#   3. docs/work-tracking/adapters.md — one section heading per tracker
# Fail-closed: exit 1 if any surface is missing a named tracker. Stack-neutral,
# zero-dependency. Run at the Review gate (DEVELOPMENT-PROCESS.md §7).
set -eu

INCEPT="scripts/incept.sh"
PROC="DEVELOPMENT-PROCESS.md"
GUIDE="docs/work-tracking/adapters.md"

for f in "$INCEPT" "$PROC" "$GUIDE"; do
  [ -f "$f" ] || { echo "FAIL: missing $f" >&2; exit 1; }
done

# incept's canonical set (just the space-separated tokens inside the quotes)
backends=$(grep -E '^BACKLOG_BACKENDS=' "$INCEPT" | head -1 | sed 's/.*="//; s/".*//')
# the §6 backend-table region only (avoid false matches elsewhere in the doc)
proc6=$(awk '/^## 6\. Work Items/{f=1} f{print} /^## 7\./{f=0}' "$PROC")

fail=0
# token | display-name pattern (display used in §6 + guide headings)
while IFS='|' read -r token pat; do
  [ -n "$token" ] || continue
  # space-bounded match so a future substring token (e.g. 'ad' vs 'ado') can't false-match
  case " $backends " in
    *" $token "*) : ;;
    *) echo "FAIL: $INCEPT BACKLOG_BACKENDS missing '$token'"; fail=1 ;;
  esac
  printf '%s\n' "$proc6" | grep -q "$pat" || { echo "FAIL: $PROC §6 backend table missing '$pat'"; fail=1; }
  grep -qE "^## .*$pat" "$GUIDE" || { echo "FAIL: $GUIDE missing a section heading for '$pat'"; fail=1; }
done <<'EOF'
md|BACKLOG\.md
github|GitHub
jira|Jira
ado|Azure DevOps
linear|Linear
gitlab|GitLab
EOF

if [ "$fail" -ne 0 ]; then
  echo "backlog-adapters: FAIL — the named set drifted across surfaces" >&2
  exit 1
fi
echo "backlog-adapters: OK (incept set, §6 table, and the adapter guide name the same six backends)"
