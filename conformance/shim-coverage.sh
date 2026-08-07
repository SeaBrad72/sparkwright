#!/bin/sh
# shim-coverage.sh — proves `kit-guard install-shims` generates working, transparent,
# NON-RECURSIVE single-invocation shims. The corpus IS the test: install real shims, put a
# fake "real" binary behind them on PATH, and assert deny / allow / passthrough / no-recursion.
#   sh conformance/shim-coverage.sh
# Exit: 0 = all behaviors correct · 1 = a failure · 2 = bad usage. POSIX sh; dash-clean.
set -eu

KG="${KIT_GUARD:-scripts/kit-guard}"
[ -f "$KG" ] || { echo "FAIL: kit-guard not found ($KG)"; exit 1; }

case "${1:-}" in
  ""|--selftest) : ;;
  *) echo "usage: shim-coverage.sh [--selftest]" >&2; exit 2 ;;
esac

work=$(mktemp -d)
shim_dir="$work/shims"
real_dir="$work/realbin"
mkdir -p "$real_dir"

# Fake "real" git: records that it ran (proves deny=not-run / allow=run) + a distinctive exit
# code and stdout (proves transparent passthrough). `ran` absent => the real binary never executed.
cat > "$real_dir/git" <<EOF
#!/bin/sh
echo "REAL-GIT ran: \$*"
: > "$work/ran"
exit 7
EOF
chmod +x "$real_dir/git"

# Install the real shims.
sh "$KG" install-shims --dir "$shim_dir" >/dev/null 2>&1 || { echo "FAIL: install-shims errored"; exit 1; }
[ -x "$shim_dir/git" ] || { echo "FAIL: no git shim generated"; exit 1; }
for b in rm dd dropdb git npm kubectl psql; do
  [ -x "$shim_dir/$b" ] || { echo "FAIL: missing curated shim '$b'"; exit 1; }
done
echo "PASS: shims generated for the curated set"

# Shim dir FIRST, then the fake real bin — but SCOPED to the test invocations only (via a PATH=
# prefix), so the harness's own rm/mktemp/[ keep using the real tools (the shim'd rm would, correctly,
# deny this harness's absolute-path cleanup).
testpath="$shim_dir:$real_dir:$PATH"

# 1) DENIED single-invocation: the guard denies 'git push origin main' -> shim blocks, real NOT run.
rm -f "$work/ran"
if PATH="$testpath" git push origin main >/dev/null 2>&1; then echo "FAIL: denied 'git push origin main' was allowed"; exit 1; fi
[ -f "$work/ran" ] && { echo "FAIL: real git executed despite deny"; exit 1; }
echo "PASS: denied single-invocation blocked; real binary not executed"

# 2) ALLOWED: 'git status' -> shim execs the real git (no recursion), exit code + stdout pass through.
rm -f "$work/ran"
set +e
out=$(PATH="$testpath" git status 2>/dev/null); rc=$?
set -e
[ -f "$work/ran" ] || { echo "FAIL: allowed 'git status' never reached the real binary"; exit 1; }
[ "$rc" = 7 ] || { echo "FAIL: exit code not passed through (got '$rc', want 7)"; exit 1; }
case "$out" in *"REAL-GIT ran: status"*) : ;; *) echo "FAIL: stdout not passed through (got '$out')"; exit 1 ;; esac
echo "PASS: allowed call reached real binary; exit code + stdout passed through (no recursion)"

# 3) RECURSION HARDENING: reach the shim dir through a SYMLINKED spelling (the case logical-pwd
# canonicalization missed). The -ef inode test must still skip the shim and resolve the real
# binary. Bounded by the in-shim depth circuit-breaker, so a regression ABORTS (exit 70), never
# fork-bombs CI.
ln -s "$shim_dir" "$work/shimlink"
rm -f "$work/ran"
set +e
out=$(PATH="$work/shimlink:$real_dir:$PATH" "$work/shimlink/git" status 2>/dev/null); rc=$?
set -e
[ -f "$work/ran" ] || { echo "FAIL: symlinked shim-dir spelling did not reach real binary (recursion/skip bug)"; exit 1; }
[ "$rc" = 7 ] || { echo "FAIL: symlinked spelling broke passthrough (got '$rc', want 7)"; exit 1; }
echo "PASS: symlinked shim-dir spelling resolves the real binary (inode skip; no recursion)"

# 4) THE CEREMONIAL FRONT DOOR MUST NOT DEADLOCK UNDER SHIMS [B2 security H1]. The Δ4(i) guard arm
# denies raw `git notes` writes to refs/notes/promotions. Under install-shims EVERY git invocation
# is routed through that arm — including scripts/promotion-verify.sh's OWN single note write — so
# the arm blocked the exact door its own deny message points the operator at: the ledger became
# unwritable by any route, which is not a speed bump, it is a brick. The fix is a sentinel that
# promotion-verify.sh exports around that one write and guard-core honours (stated honestly in the
# arm's ceiling as AGENT-FORGEABLE — Δ4(i)′'s whole posture is drift control, not prevention).
# This case proves BOTH halves end to end: the front door records, and the raw back door through
# the same shim is still denied. Real git resolves from the ambient PATH here (NOT $real_dir's
# stub), so the record is a genuine one — in a throwaway repo, never this repository's ledger.
# shellcheck disable=SC1007 # `CDPATH= cd` clears CDPATH for this one command so a user's CDPATH
# cannot redirect it; the empty assignment is intentional, not a mistyped value (same idiom and
# same justification as conformance/ceremony-binding.sh:82).
pv="$(CDPATH= cd -- "$(dirname -- "$KG")" && pwd)/promotion-verify.sh"
if [ -f "$pv" ]; then
  repo="$work/pvrepo"; mkdir -p "$repo"
  (
    cd "$repo" && git init -q && git config user.email fixture@example.invalid \
      && git config user.name Fixture && git config commit.gpgsign false \
      && printf 'x\n' > f.txt && git add f.txt && git commit -qm c1
  ) >/dev/null 2>&1
  sha=$( cd "$repo" && git rev-parse HEAD )
  set +e
  out=$( cd "$repo" && PATH="$shim_dir:$PATH" sh "$pv" record --approved-sha "$sha" \
           --approved-by Fixture --gate design --rung Design --class control-plane \
           --scope branch/b2fix-shim-probe --token "GO" 2>&1 ); pvrc=$?
  set -e
  if [ "$pvrc" = 0 ] && ( cd "$repo" && git notes --ref=promotions show "$sha" >/dev/null 2>&1 ); then
    echo "PASS: the ceremonial front door still records under install-shims (no guard deadlock)"
  else
    echo "FAIL: the front door DEADLOCKED under install-shims (rc=$pvrc): $out"; exit 1
  fi
  set +e
  ( cd "$repo" && PATH="$shim_dir:$PATH" git notes --ref=promotions add -f -m forged "$sha" ) >/dev/null 2>&1
  rawrc=$?
  set -e
  if [ "$rawrc" = 0 ]; then
    echo "FAIL: a RAW ledger write was allowed through the shim — the sentinel widened the arm into a hole"; exit 1
  fi
  echo "PASS: the raw back door stays denied through the same shim (the sentinel is not a hole in the arm)"
else
  echo "N/A: scripts/promotion-verify.sh not present next to kit-guard — front-door shim case skipped"
fi

echo "OK: shim-coverage — generated + deny + allow + passthrough + symlink-no-recursion + front-door all proven"
exit 0
