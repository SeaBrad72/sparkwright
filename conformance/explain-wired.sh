#!/bin/sh
# explain-wired.sh — regression-lock for the S4 why-layer. Adds no enforcement of its own beyond
# keeping the teaching layer honest. Asserts: explain.sh + sparkwright + why-gates.md exist;
# explain --selftest exits 0; the dispatcher routes 'sparkwright explain --list'; every repo-path
# 'Enforced by:' in why-gates.md exists (no orphan rationale); and every S1-checklist enforcer is
# taught (present in BOTH incept.sh's conditional-obligations heredoc AND why-gates.md) — so a gate
# can never be added/renamed without its 'why', nor a 'why' point at a deleted check.
#   sh conformance/explain-wired.sh [--selftest]
# Exit: 0 = contract holds · 1 = a regression · 2 = usage. POSIX sh; dash-clean.
set -eu

KIT_EXPLAIN_SCRIPTS="${KIT_EXPLAIN_SCRIPTS:-scripts}"
KIT_EXPLAIN_DOC="${KIT_EXPLAIN_DOC:-docs/why-gates.md}"
KIT_EXPLAIN_INCEPT="${KIT_EXPLAIN_INCEPT:-scripts/incept.sh}"

# The S1 conditional-obligations enforcers that MUST be taught. Single list, used by both the
# teaching-completeness check and its selftest fixtures.
CHECKLIST_ENFORCERS="conformance/privacy-ready.sh conformance/eval-ready.sh conformance/agentops-ready.sh conformance/dr-ready.sh conformance/resilience-ready.sh conformance/deployable-ready.sh conformance/container-supply-chain.sh"

# Floor/always-on topics taught in why-gates.md that have NO S1-checklist enforcer binding
# (their gate is a §14 floor gate, not a conditional obligation), so they are not covered by the
# enforcer-path teaching check below. Protect their blocks from silent deletion so the doc's
# advertised topic set can't quietly shrink below what the CHANGELOG/ROADMAP promise. A new floor
# topic added to why-gates.md must be registered here (a deliberate drift-lock coupling).
FLOOR_TOPICS="a11y secret-scan sbom-provenance builder-not-reviewer"

check() {  # $1=scriptsdir $2=doc $3=inceptfile
  _s=$1; _doc=$2; _inc=$3; _fail=0

  for _f in "$_s/explain.sh" "$_s/sparkwright" "$_doc"; do
    if [ -f "$_f" ]; then echo "PASS: $_f exists"
    else echo "FAIL: $_f missing"; _fail=1; fi
  done
  [ "$_fail" = "0" ] || return 1

  if sh "$_s/explain.sh" --selftest >/dev/null 2>&1; then echo "PASS: explain.sh --selftest exits 0"
  else echo "FAIL: explain.sh --selftest non-zero"; _fail=1; fi

  if sh "$_s/sparkwright" explain --list >/dev/null 2>&1; then echo "PASS: sparkwright explain routes"
  else echo "FAIL: sparkwright explain did not route"; _fail=1; fi

  # (2) no orphan rationale: every repo-path 'Enforced by:' value exists.
  _orphan=0
  # Extract repo-path enforcers; reject any with a '..' component so a doc edit can't smuggle a
  # false-passing citation that escapes the kit tree (e.g. conformance/../../tmp/evil.sh).
  for _p in $(grep -E '^Enforced by:' "$_doc" | sed 's/^Enforced by:[[:space:]]*//' \
              | grep -oE '(conformance|scripts)/[A-Za-z0-9_./-]+\.sh' | grep -v '\.\.' | sort -u); do
    if [ -f "$_p" ]; then echo "PASS: enforcer exists: $_p"
    else echo "FAIL: orphan rationale — why-gates.md cites missing $_p"; _orphan=1; fi
  done
  [ "$_orphan" = "0" ] || _fail=1

  # (3) teaching-completeness: each checklist enforcer is in BOTH incept's heredoc AND the doc.
  # The incept checklist may name a gate by full path (conformance/eval-ready.sh) OR by bare
  # basename (the combined "deployable-ready, resilience-ready, dr-ready" row), so the incept
  # side matches on basename-sans-extension — the stable identifier present in both formats —
  # while the doc side stays strict (full path, the format why-gates.md uses).
  for _e in $CHECKLIST_ENFORCERS; do
    _eb=$(basename "$_e" .sh)
    if grep -Fq "$_eb" "$_inc"; then :
    else echo "FAIL: checklist obligation dropped from incept.sh heredoc: $_eb"; _fail=1; fi
    # Match the structured 'Enforced by:' line, not a stray mention anywhere in the doc.
    if grep -Fq "Enforced by: $_e" "$_doc"; then echo "PASS: taught: $_e"
    else echo "FAIL: untaught gate — no why-gates.md block for $_e"; _fail=1; fi
  done

  # (3b) floor topics: each advertised floor topic still has a block, so the doc's topic set
  # can't silently shrink below what the CHANGELOG/ROADMAP promise (these have no enforcer-path
  # binding above to protect them).
  for _t in $FLOOR_TOPICS; do
    if grep -Fq "## $_t" "$_doc"; then echo "PASS: floor topic taught: $_t"
    else echo "FAIL: floor topic block missing from why-gates.md: $_t"; _fail=1; fi
  done

  return $_fail
}

if [ "${1:-}" = "--selftest" ]; then
  sfail=0
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT INT TERM

  _mk_scripts() {  # $1 = dir
    mkdir -p "$1"
    cat > "$1/explain.sh" <<'EX'
#!/bin/sh
[ "${1:-}" = "--selftest" ] && { echo ok; exit 0; }
[ "${1:-}" = "--list" ] && { echo "threat-model"; exit 0; }
echo render
EX
    chmod +x "$1/explain.sh"
    cat > "$1/sparkwright" <<'SW'
#!/bin/sh
set -eu
here=$(dirname "$0")
case "${1:-}" in
  explain) shift; exec sh "$here/explain.sh" "$@" ;;
  *) echo "unknown" >&2; exit 2 ;;
esac
SW
    chmod +x "$1/sparkwright"
  }
  # an incept fixture that names ALL checklist enforcers
  _inc="$tmp/incept.sh"
  { echo '#!/bin/sh'; for _e in $CHECKLIST_ENFORCERS; do echo "# $_e"; done; } > "$_inc"

  # FIXTURE OK: doc teaches all enforcers (structured 'Enforced by:' lines) + all floor topics, no orphan
  _mk_scripts "$tmp/ok"
  _docok="$tmp/ok/why.md"
  { for _e in $CHECKLIST_ENFORCERS; do
      printf '## t-%s\nApplies IF: x\nWhy: y\nEnforced by: %s\nRead more: z\n\n' "$(basename "$_e" .sh)" "$_e"
    done
    for _t in $FLOOR_TOPICS; do
      printf '## %s\nApplies IF: x\nWhy: y\nEnforced by: DEVELOPMENT-STANDARDS.md §14\nRead more: z\n\n' "$_t"
    done; } > "$_docok"
  if KIT_EXPLAIN_SCRIPTS="$tmp/ok" KIT_EXPLAIN_DOC="$_docok" KIT_EXPLAIN_INCEPT="$_inc" sh "$0" >/dev/null 2>&1; then
    echo "PASS: selftest — complete fixture passed"
  else echo "FAIL: selftest — complete fixture wrongly failed"; sfail=1; fi

  # FIXTURE FLOOR-GAP: drop one floor topic block from the doc → must FAIL
  _docfloor="$tmp/ok/why-floor.md"
  grep -v '## a11y' "$_docok" > "$_docfloor"
  if KIT_EXPLAIN_SCRIPTS="$tmp/ok" KIT_EXPLAIN_DOC="$_docfloor" KIT_EXPLAIN_INCEPT="$_inc" sh "$0" >/dev/null 2>&1; then
    echo "FAIL: selftest — floor-topic-gap fixture wrongly passed"; sfail=1
  else echo "PASS: selftest — floor-topic-gap detected"; fi

  # FIXTURE TEACHING-GAP (doc side): drop one enforcer from the doc → must FAIL
  _docgap="$tmp/ok/why-gap.md"
  grep -v 'container-supply-chain.sh' "$_docok" > "$_docgap"
  if KIT_EXPLAIN_SCRIPTS="$tmp/ok" KIT_EXPLAIN_DOC="$_docgap" KIT_EXPLAIN_INCEPT="$_inc" sh "$0" >/dev/null 2>&1; then
    echo "FAIL: selftest — doc-side teaching-gap fixture wrongly passed"; sfail=1
  else echo "PASS: selftest — doc-side teaching-gap detected"; fi

  # FIXTURE TEACHING-GAP (incept side): drop one enforcer from the incept heredoc → must FAIL
  # (proves the BOTH requirement — the incept arm is load-bearing, not just the doc arm).
  _incgap="$tmp/incept-gap.sh"
  grep -v 'container-supply-chain' "$_inc" > "$_incgap"
  if KIT_EXPLAIN_SCRIPTS="$tmp/ok" KIT_EXPLAIN_DOC="$_docok" KIT_EXPLAIN_INCEPT="$_incgap" sh "$0" >/dev/null 2>&1; then
    echo "FAIL: selftest — incept-side teaching-gap fixture wrongly passed"; sfail=1
  else echo "PASS: selftest — incept-side teaching-gap detected"; fi

  # FIXTURE ORPHAN: add a why block citing a nonexistent conformance path → must FAIL
  _docorph="$tmp/ok/why-orphan.md"
  cp "$_docok" "$_docorph"
  printf '## orphan\nApplies IF: x\nWhy: y\nEnforced by: conformance/does-not-exist.sh\nRead more: z\n' >> "$_docorph"
  if KIT_EXPLAIN_SCRIPTS="$tmp/ok" KIT_EXPLAIN_DOC="$_docorph" KIT_EXPLAIN_INCEPT="$_inc" sh "$0" >/dev/null 2>&1; then
    echo "FAIL: selftest — orphan fixture wrongly passed"; sfail=1
  else echo "PASS: selftest — orphan rationale detected"; fi

  # FIXTURE MISSING: empty scripts dir → must FAIL
  mkdir -p "$tmp/empty"
  if KIT_EXPLAIN_SCRIPTS="$tmp/empty" KIT_EXPLAIN_DOC="$_docok" KIT_EXPLAIN_INCEPT="$_inc" sh "$0" >/dev/null 2>&1; then
    echo "FAIL: selftest — missing-files fixture wrongly passed"; sfail=1
  else echo "PASS: selftest — missing-files detected"; fi

  [ "$sfail" -eq 0 ] && { echo "OK: explain-wired selftest"; exit 0; }
  echo "FAIL: explain-wired selftest"; exit 1
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: explain-wired.sh [--selftest]" >&2; exit 2 ;;
esac

echo "Explain why-layer wiring check:"
if check "$KIT_EXPLAIN_SCRIPTS" "$KIT_EXPLAIN_DOC" "$KIT_EXPLAIN_INCEPT"; then
  echo "OK: explain why-layer wired + no orphan rationale + teaching-complete"
  exit 0
else
  echo "FAIL: explain why-layer regression (see above)"
  exit 1
fi
