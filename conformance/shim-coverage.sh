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
  # `--no-push` (RECORD-FETCHES-AND-PUSHES-LEDGER): `record` is now a fetch→write→publish transaction
  # that REFUSES to record against a ledger it cannot reach, and this throwaway repo has no remote.
  # The refusal is rc 2 with "cannot reach the ledger remote" — which this leg would otherwise read
  # as a guard DEADLOCK (measured on PR #643's first CI run). `--no-push` is the labelled fixture
  # escape; what this leg proves — the sentinel lets the ONE note write through the shim — is
  # unchanged, because the write path is identical with or without the publish step.
  set +e
  out=$( cd "$repo" && PATH="$shim_dir:$PATH" sh "$pv" record --no-push --approved-sha "$sha" \
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

# 5) claim front door under shims [B2-SESSION-IDENTITY-LEDGER, design decision 5]. Same class as
# case 4 and the same cure: the new arm denies any push whose refspec DESTINATION is
# `refs/claims/` or `refs/claims-log/`, and under install-shims EVERY child `git` is graded —
# including board-claim.sh's OWN claim, resume and release pushes. The sentinel is
# KIT_CLAIM_FRONT_DOOR=1, honoured ONLY from the guard's process environment. Both halves are
# proven here against a REAL bare remote in a throwaway tree, never this repository's refs:
#   (a) the script's own push passes through the shim'd git;
#   (b) the same sentinel typed into the COMMAND TEXT is still denied.
# ⚠️ AND THE RELEASE PUSH IS MEASURED AND DISCLOSED EITHER WAY: it carries `--force-with-lease`,
# which the guard's unrelated force-push rule may refuse under shims. Whatever the verdict is, this
# case prints it, so nobody has to guess whether the release path works in a shimmed runtime.
# shellcheck disable=SC1007 # `CDPATH= cd` clears CDPATH for this one command so a user's CDPATH
# cannot redirect it; the empty assignment is intentional (same idiom and justification as the `pv`
# resolution in case 4 above).
bc="$(CDPATH= cd -- "$(dirname -- "$KG")" && pwd)/board-claim.sh"
if [ -f "$bc" ]; then
  cremote="$work/claims.git"; cwork="$work/claimwork"
  git init -q --bare "$cremote"
  git clone -q "$cremote" "$cwork" 2>/dev/null
  (
    cd "$cwork" && git config user.email fixture@example.invalid && git config user.name Fixture \
      && git config commit.gpgsign false
  ) >/dev/null 2>&1
  cat > "$cwork/BACKLOG.md" <<'SHIM_BOARD_EOF'
# Fixture — Backlog

## Ready

| Item | Intent (why) | Acceptance criteria | Size | Risk | Type | Owner | Links | Success metric / hypothesis |
|------|--------------|---------------------|------|------|------|-------|-------|-----------------------------|
| `ROW-SHIM` — the claimable row | because | it is claimed | S | low | feature | agent | — | a claim serializes |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
SHIM_BOARD_EOF
  set +e
  cout=$( cd "$cwork" && PATH="$shim_dir:$PATH" sh "$bc" claim ROW-SHIM --branch feat/shim 2>&1 ); crc=$?
  set -e
  if [ "$crc" = 0 ] && git --git-dir="$cremote" rev-parse --verify -q refs/claims/ROW-SHIM >/dev/null; then
    echo "PASS: the claim front door still pushes under install-shims (the process-env sentinel is honoured)"
  else
    echo "FAIL: board-claim.sh DEADLOCKED under install-shims (rc=$crc): $cout"; exit 1
  fi
  # ⚠️ NOT PROBED HERE: prefixing the sentinel to a raw shell command in THIS process exports it into
  # the shim's environment, so it allows — which is the arm's own stated ceiling ("forgeable by an
  # actor who can set the guard's environment"), not a finding. (It is also destructive: the first
  # draft of this case deleted the fixture's own claim that way and made the release measurement
  # below read REFUSED for the wrong reason.) What must NOT be possible is typing the sentinel as
  # command TEXT, which is the thing an agent can actually do, and `kit-guard cmd` grades it:
  set +e
  ( PATH="$shim_dir:$PATH" sh "$KG" cmd 'KIT_CLAIM_FRONT_DOOR=1 git push origin :refs/claims/ROW-SHIM' ) >/dev/null 2>&1
  ctextrc=$?
  set -e
  if [ "$ctextrc" = 0 ]; then
    echo "FAIL: the sentinel typed in the COMMAND TEXT was honoured — an agent can type past the arm"; exit 1
  fi
  echo "PASS: the same sentinel in the command TEXT is denied (env-only, exactly like the ledger's)"
  # the disclosure half: the release push's --force-with-lease under shims, measured not assumed.
  set +e
  relout=$( cd "$cwork" && PATH="$shim_dir:$PATH" \
              KIT_CLAIM_FORCE_RELEASE='shim coverage measurement' sh "$bc" release ROW-SHIM --stale 2>&1 ); relrc=$?
  set -e
  if [ "$relrc" = 0 ]; then
    echo "MEASURED: the release push (--force-with-lease) PASSES under install-shims"
  else
    # MEASURED 2026-09-16: the refusal is the PRE-EXISTING force/mirror-push rule ("force/mirror
    # push rewrites or deletes published history - human-gated"), NOT the new claim-ref arm — the
    # sentinel is honoured, and the lease flag is what trips. Disclosed, not fixed here: under the
    # Claude hook the release works (the guard grades `sh scripts/board-claim.sh …`, not its child
    # git), and under shims the delete stays a human act, which is the direction this kit errs in.
    echo "MEASURED: the release push (--force-with-lease) is REFUSED under install-shims (rc=$relrc), by the FORCE-PUSH rule rather than the claim arm — disclosed, not fixed here: the claim ref's delete stays a human act in a shimmed runtime. [$(printf '%s' "$relout" | tr '\n' ' ' | cut -c1-120)]"
  fi
else
  echo "N/A: scripts/board-claim.sh not present next to kit-guard — claim front-door shim case skipped"
fi

echo "OK: shim-coverage — generated + deny + allow + passthrough + symlink-no-recursion + front-door + claim front door under shims all proven"
exit 0
