#!/bin/sh
# tier-advice-wired.sh — regression-lock: the tier-advice decision view is wired and HONEST.
# Asserts scripts/tier-advice.sh + scripts/sparkwright exist; tier-advice --selftest exits 0;
# the dispatcher routes 'sparkwright tier-advice'; and the locked governance framing literals
# are present in the source — DORA-is-not-a-tier-input, and the ASYMMETRIC apply path
# (auto-downgrade = fail-safe/no-ratification vs Security-owner-ratified raise). Weakening any
# of those is a ratified act, caught here.
# Paths overridable via KIT_TA_DIR (default: scripts) so --selftest can use fixtures.
#   sh conformance/tier-advice-wired.sh [--selftest]
# Exit: 0 = contract holds . 1 = a regression . 2 = usage. POSIX sh; dash-clean.
set -eu

KIT_TA_DIR="${KIT_TA_DIR:-scripts}"

# The three locked literals — must appear verbatim in tier-advice.sh.
LOCK_DORA="NOT an input to the tier recommendation"
LOCK_DOWNGRADE="NO ratification required"
LOCK_RAISE="Security owner"

check_wired() {
  _dir=$1; _fail=0

  if [ -f "$_dir/tier-advice.sh" ]; then echo "PASS: $_dir/tier-advice.sh exists"
  else echo "FAIL: $_dir/tier-advice.sh missing"; _fail=1; fi
  if [ -f "$_dir/sparkwright" ]; then echo "PASS: $_dir/sparkwright exists"
  else echo "FAIL: $_dir/sparkwright missing"; _fail=1; fi
  [ "$_fail" = "0" ] || return 1

  if sh "$_dir/tier-advice.sh" --selftest >/dev/null 2>&1; then
    echo "PASS: tier-advice.sh --selftest exits 0"
  else echo "FAIL: tier-advice.sh --selftest returned non-zero"; _fail=1; fi

  if sh "$_dir/sparkwright" tier-advice --selftest >/dev/null 2>&1; then
    echo "PASS: sparkwright tier-advice routes (--selftest exits 0)"
  else echo "FAIL: sparkwright tier-advice did not route"; _fail=1; fi

  for _lit in "$LOCK_DORA" "$LOCK_DOWNGRADE" "$LOCK_RAISE"; do
    if grep -Fq "$_lit" "$_dir/tier-advice.sh"; then
      echo "PASS: locked governance literal present: \"$_lit\""
    else echo "FAIL: locked governance literal MISSING: \"$_lit\""; _fail=1; fi
  done

  return $_fail
}

if [ "${1:-}" = "--selftest" ]; then
  sfail=0
  tmp=$(mktemp -d)

  # FIXTURE OK: handles --selftest, contains all 3 literals; sparkwright routes
  mkdir -p "$tmp/ok"
  cat > "$tmp/ok/tier-advice.sh" <<'TA_EOF'
#!/bin/sh
# locks: NOT an input to the tier recommendation / NO ratification required / Security owner
[ "${1:-}" = "--selftest" ] && { echo "tier-advice --selftest: OK"; exit 0; }
echo "render"
TA_EOF
  chmod +x "$tmp/ok/tier-advice.sh"
  cat > "$tmp/ok/sparkwright" <<'SW_EOF'
#!/bin/sh
set -eu
here=$(dirname "$0")
case "${1:-}" in
  tier-advice) shift; exec sh "$here/tier-advice.sh" "$@" ;;
  ""|-h|--help) echo "usage: sparkwright <command>; commands: tier-advice" >&2; exit 2 ;;
  *) echo "sparkwright: unknown command '$1'" >&2; exit 2 ;;
esac
SW_EOF
  chmod +x "$tmp/ok/sparkwright"
  if KIT_TA_DIR="$tmp/ok" sh "$0" >/dev/null 2>&1; then
    echo "PASS: selftest — complete+honest fixture correctly passed"
  else echo "FAIL: selftest — complete fixture wrongly failed"; sfail=1; fi

  # FIXTURE GAP: tier-advice.sh MISSING the 'Security owner' literal -> must FAIL
  mkdir -p "$tmp/gap"
  cat > "$tmp/gap/tier-advice.sh" <<'TA_EOF'
#!/bin/sh
# locks: NOT an input to the tier recommendation / NO ratification required
[ "${1:-}" = "--selftest" ] && { echo "ok"; exit 0; }
echo "render"
TA_EOF
  chmod +x "$tmp/gap/tier-advice.sh"
  cp "$tmp/ok/sparkwright" "$tmp/gap/sparkwright"
  if KIT_TA_DIR="$tmp/gap" sh "$0" >/dev/null 2>&1; then
    echo "FAIL: selftest — gap fixture (missing 'Security owner' literal) wrongly passed"; sfail=1
  else echo "PASS: selftest — gap fixture correctly detected (honesty literal stripped)"; fi

  # FIXTURE MISSING: empty dir -> must FAIL
  mkdir -p "$tmp/empty"
  if KIT_TA_DIR="$tmp/empty" sh "$0" >/dev/null 2>&1; then
    echo "FAIL: selftest — missing-files fixture wrongly passed"; sfail=1
  else echo "PASS: selftest — missing-files fixture correctly detected"; fi

  if [ "$sfail" -eq 0 ]; then echo "OK: tier-advice-wired selftest"; exit 0; else echo "FAIL: tier-advice-wired selftest"; exit 1; fi
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: tier-advice-wired.sh [--selftest]" >&2; exit 2 ;;
esac

echo "Tier-advice wiring check (dir: $KIT_TA_DIR):"
if check_wired "$KIT_TA_DIR"; then
  echo "OK: tier-advice decision view is wired + honest (dispatcher routes; framing literals locked; --selftest green)"
  exit 0
else
  echo "FAIL: tier-advice wiring/honesty regression (see above)"
  exit 1
fi
