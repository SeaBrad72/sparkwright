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

echo "OK: shim-coverage — generated + deny + allow + passthrough + symlink-no-recursion all proven"
exit 0
