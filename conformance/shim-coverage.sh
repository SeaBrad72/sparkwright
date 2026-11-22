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
  # SWAS-944: record --gate design now refuses a basis the approved commit does not carry,
  # so c1 commits the design file that --basis names below.
  (
    cd "$repo" && git init -q && git config user.email fixture@example.invalid \
      && git config user.name Fixture && git config commit.gpgsign false \
      && mkdir -p docs/architecture \
      && printf '# x design\n\nThe design of the shim-probe fixture.\n' > docs/architecture/x-design.md \
      && printf 'x\n' > f.txt && git add f.txt docs/architecture/x-design.md && git commit -qm c1
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
           --approved-by Fixture --gate design --rung integration --class control-plane \
           --scope branch/b2fix-shim-probe --token "GO" \
           --basis docs/architecture/x-design.md 2>&1 ); pvrc=$?
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
# ⚠️ AND THE RELEASE PUSH IS ASSERTED (SWAS-842): it carries `--force-with-lease`, which the guard's
# force-push rule refused under shims until it learned to admit this one compare-and-swap delete.
# The case asserts the release succeeds, so a regression in the admission reds here.
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
  # THE RELEASE PUSH (SWAS-842, F4): the compare-and-swap delete (`--force-with-lease=<ref>:<sha> :<ref>`) is admitted under install-shims in
  # its one grammar-exact form, by the claims sentinel. This used to be a printed measurement (the force-push rule refused it, 2026-09-16, and
  # the verb wrote a compensating `-FAILED` log entry); it is an assertion now. Three things must hold: the verb's rc is 0, the claim ref is gone
  # on the bare remote, and the LAST `refs/claims-log/ROW-SHIM` entry is not a `-FAILED` one. Under the Claude hook the release always worked
  # (the guard grades `sh scripts/board-claim.sh ...`, not its child git); this is the shimmed runtime's half.
  # The release resolves its remote to a URL for the log push and the throwaway-dir reads (`git remote get-url` expands `insteadOf`), and a plain-path
  # remote (and a `.git`-suffixed one) trips the guard's path rule under the shims before the delete is ever reached (SWAS-841). So the release is given
  # the origin shape real use has: an https-shaped URL named by BOARD_CLAIM_REMOTE, mapped to the bare directory by a global `insteadOf` in a config file
  # that only this call reads. The claim above used the plain `origin` name, which the guard sees as a name.
  relurl="https://example.invalid/owner-login/repo-a.git"
  printf '[url "%s"]\n\tinsteadOf = %s\n' "$cremote" "$relurl" > "$work/claim-gitcfg"
  set +e
  relout=$( cd "$cwork" && PATH="$shim_dir:$PATH" GIT_CONFIG_GLOBAL="$work/claim-gitcfg" BOARD_CLAIM_REMOTE="$relurl" \
              KIT_CLAIM_FORCE_RELEASE='shim coverage measurement' sh "$bc" release ROW-SHIM --stale 2>&1 ); relrc=$?
  set -e
  relgone=1; git --git-dir="$cremote" rev-parse --verify -q refs/claims/ROW-SHIM >/dev/null 2>&1 && relgone=0
  rellast=$(git --git-dir="$cremote" cat-file blob refs/claims-log/ROW-SHIM:LOG 2>/dev/null || true)
  relfailed=0; printf '%s\n' "$rellast" | grep -q '^proof: .*-FAILED$' && relfailed=1
  if [ "$relrc" = 0 ] && [ "$relgone" = 1 ] && [ "$relfailed" = 0 ]; then
    echo "PASS: the release push (--force-with-lease) is admitted under install-shims: rc 0, the claim ref is gone, the last log entry is not -FAILED (SWAS-842)"
  else
    echo "FAIL: the release push is not admitted under install-shims (rc=$relrc, claim ref gone=$relgone, last log entry -FAILED=$relfailed) [$(printf '%s' "$relout" | tr '\n' ' ' | cut -c1-160)]"; exit 1
  fi
else
  echo "N/A: scripts/board-claim.sh not present next to kit-guard — claim front-door shim case skipped"
fi

# 6) THE LAND LEASE UNDER SHIMS (SWAS-842, F5, F6). Same class as case 5: checkout-lease.sh's land lease is a ref on origin that the verb creates with a
# plain push and returns with the compare-and-swap delete (`push -q --force-with-lease=refs/leases/land:<sha> <url> :refs/leases/land`), and under
# install-shims every child `git` is graded, so the delete met the force-push rule and the lease stayed held after every land (measured in SWAS-839).
# The sentinel is KIT_LEASE_FRONT_DOOR=1 from the guard's process environment. This case acquires, releases and acquires again through the shims on a
# bare origin in a throwaway tree, with the origin shape real use has (an https-shaped URL mapped to the bare directory by `url.<dir>.insteadOf`, because a
# plain-path origin trips the guard's path rule under the shims). The CI holder form is used (`--run`, `--expect-base`): it is the form that needs no
# opted-in checkout. F6, the regression anchor: the same three steps with no shim on PATH (the hook adapter's runtime) are rc 0 too.
# shellcheck disable=SC1007 # `CDPATH= cd` clears CDPATH for this one command (same idiom and justification as case 4's `pv`).
cl="$(CDPATH= cd -- "$(dirname -- "$KG")" && pwd)/checkout-lease.sh"
if [ -f "$cl" ]; then
  lremote="$work/lease-origin"; lwork="$work/leasework"; lurl="https://example.invalid/owner-login/repo-a.git"
  git init -q --bare "$lremote"; git -C "$lremote" symbolic-ref HEAD refs/heads/main
  git init -q "$lwork" >/dev/null 2>&1
  (
    cd "$lwork" && git symbolic-ref HEAD refs/heads/main && git config user.email fixture@example.invalid && git config user.name Fixture \
      && git config commit.gpgsign false && printf 'x\n' > f.txt && git add f.txt && git commit -qm c1 \
      && git config "url.$lremote.insteadOf" "$lurl" && git remote add origin "$lurl" && git push -q origin main
  ) >/dev/null 2>&1
  lbase=$(git --git-dir="$lremote" rev-parse --verify -q refs/heads/main || true)
  # lease_leg <label> <PATH prefix or empty>: acquire, release, acquire again; every step rc 0, the ref gone after the release, present after the second acquire
  lease_leg() {
    _lp=$2; _lsh=''
    [ -z "$_lp" ] || _lsh="$_lp:"
    set +e
    _lo=$( cd "$lwork" && PATH="$_lsh$PATH" sh "$cl" acquire --lease land --holder lane-a --purpose land --run 1/1 --expect-base "$lbase" 2>&1 ); _lr1=$?
    _lt=$(printf '%s\n' "$_lo" | sed -n 's/^lease-token: //p' | head -1)
    _lo2=$( cd "$lwork" && PATH="$_lsh$PATH" sh "$cl" release --lease land --lease-token "$_lt" 2>&1 ); _lr2=$?
    _lgone=1; git --git-dir="$lremote" rev-parse --verify -q refs/leases/land >/dev/null 2>&1 && _lgone=0
    _lfailed=0; git --git-dir="$lremote" cat-file blob refs/leases-log/land:LOG 2>/dev/null | grep -q '^proof: release-FAILED$' && _lfailed=1
    _lo3=$( cd "$lwork" && PATH="$_lsh$PATH" sh "$cl" acquire --lease land --holder lane-a --purpose land --run 1/1 --expect-base "$lbase" 2>&1 ); _lr3=$?
    set -e
    if [ "$_lr1" = 0 ] && [ -n "$_lt" ] && [ "$_lr2" = 0 ] && [ "$_lgone" = 1 ] && [ "$_lfailed" = 0 ] && [ "$_lr3" = 0 ]; then
      echo "PASS: $1: the land lease is acquired, released (rc 0, the ref gone, no -FAILED entry) and acquired again, so the next land is not blocked"
    else
      echo "FAIL: $1: the land lease cycle broke (acquire rc=$_lr1, release rc=$_lr2, ref gone=$_lgone, -FAILED entry=$_lfailed, second acquire rc=$_lr3) [$(printf '%s %s %s' "$_lo" "$_lo2" "$_lo3" | tr '\n' ' ' | cut -c1-240)]"; exit 1
    fi
    git --git-dir="$lremote" update-ref -d refs/leases/land >/dev/null 2>&1 || true
    git --git-dir="$lremote" update-ref -d refs/leases-log/land >/dev/null 2>&1 || true
  }
  lease_leg "under install-shims (F5)" "$shim_dir"
  lease_leg "with no shim on PATH, the hook adapter's runtime (F6)" ""
  # N8, N9 (SWAS-842), measured through the real shims with the lease sentinel in the environment. The lease is held, so any push or delete that git
  # actually performs shows as a change in the refs. N8b: an EMPTY argv element joins into a double space; the guard must refuse it (the shim says "blocked") and the
  # real git must never run. N8a: an element that HOLDS a space reads to the guard as two tokens; the verdict is recorded and git must reject the call.
  # N9: the admitted form against a remote with `remote.<name>.mirror=true`, and one with `remote.<name>.push` set: git refuses, or deletes only the named ref.
  set +e
  n8o=$( cd "$lwork" && PATH="$shim_dir:$PATH" sh "$cl" acquire --lease land --holder lane-a --purpose land --run 1/1 --expect-base "$lbase" 2>&1 )
  n8t=$(printf '%s\n' "$n8o" | sed -n 's/^lease-token: //p' | head -1)
  n8before=$(git --git-dir="$lremote" for-each-ref --format='%(refname) %(objectname)')
  n8a="--force-with-lease=refs/leases/land:$n8t"
  n8x1=$( cd "$lwork" && PATH="$shim_dir:$PATH" KIT_LEASE_FRONT_DOOR=1 git -C "" push -q "$n8a" "$lurl" :refs/leases/land 2>&1 ); n8r1=$?
  n8x2=$( cd "$lwork" && PATH="$shim_dir:$PATH" KIT_LEASE_FRONT_DOOR=1 git push -q "$n8a" "$lurl" "" :refs/leases/land 2>&1 ); n8r2=$?
  n8x3=$( cd "$lwork" && PATH="$shim_dir:$PATH" KIT_LEASE_FRONT_DOOR=1 git push -q "" "$n8a" "$lurl" :refs/leases/land 2>&1 ); n8r3=$?
  n8x4=$( cd "$lwork" && PATH="$shim_dir:$PATH" KIT_LEASE_FRONT_DOOR=1 git push -q "$n8a" "$lurl :refs/leases/land" 2>&1 ); n8r4=$?
  n8after=$(git --git-dir="$lremote" for-each-ref --format='%(refname) %(objectname)')
  set -e
  n8ok=1
  for n8p in "$n8r1:$n8x1" "$n8r2:$n8x2" "$n8r3:$n8x3"; do
    case "$n8p" in 0:*) n8ok=0 ;; esac
    case "$n8p" in *"blocked single-invocation"*) : ;; *) n8ok=0 ;; esac
  done
  if [ "$n8ok" = 1 ] && [ "$n8before" = "$n8after" ] && [ -n "$n8t" ]; then
    echo "PASS: N8b an empty argv element (three placements) is refused by the guard through the shims, and the real git never ran; origin's refs are unchanged"
  else
    echo "FAIL: N8b an empty argv element was not refused, or origin changed (rc $n8r1/$n8r2/$n8r3) [$n8x1 $n8x2 $n8x3]"; exit 1
  fi
  case "$n8x4" in *"blocked single-invocation"*) n8v=REFUSED-BY-GUARD ;; *) n8v=ADMITTED-BY-GUARD ;; esac
  if [ "$n8r4" != 0 ] && [ "$n8before" = "$n8after" ]; then
    echo "PASS: N8a an element holding a space ($n8v): git rejected the call (rc $n8r4) and origin's refs are unchanged"
  else
    echo "FAIL: N8a an element holding a space was performed by git (rc $n8r4) or origin changed"; exit 1
  fi
  # N8c (the second placement): the LEASE option joined to the remote in one argv element, which the guard reads as two tokens. git must reject the call (the
  # joined element is no option and no remote it can use), and the lease ref must still be on the bare remote. The guard's verdict and git's rc are recorded.
  set +e
  n8x5=$( cd "$lwork" && PATH="$shim_dir:$PATH" KIT_LEASE_FRONT_DOOR=1 git push -q "$n8a $lurl" :refs/leases/land 2>&1 ); n8r5=$?
  set -e
  n8after5=$(git --git-dir="$lremote" for-each-ref --format='%(refname) %(objectname)')
  case "$n8x5" in *"blocked single-invocation"*) n8v5=REFUSED-BY-GUARD ;; *) n8v5=ADMITTED-BY-GUARD ;; esac
  n8held=0; git --git-dir="$lremote" rev-parse --verify -q refs/leases/land >/dev/null 2>&1 && n8held=1
  if [ "$n8held" = 1 ] && [ "$n8before" = "$n8after5" ]; then
    echo "PASS: N8c the lease option joined to the remote ($n8v5): the lease ref is NOT deleted on the bare remote (git rc $n8r5), origin's refs are unchanged"
  else
    echo "FAIL: N8c the lease option joined to the remote deleted the lease ref or changed origin (git rc $n8r5, ref held=$n8held) [$n8x5]"; exit 1
  fi
  # N9: a mirror remote and a push-configured remote, each beside the explicit refspec
  git -C "$lwork" remote add mirrorr "$lurl"; git -C "$lwork" config remote.mirrorr.mirror true
  git -C "$lwork" remote add pushr "$lurl"; git -C "$lwork" config remote.pushr.push 'refs/heads/main:refs/heads/main'
  for n9r in mirrorr pushr; do
    set +e
    n9o=$( cd "$lwork" && PATH="$shim_dir:$PATH" KIT_LEASE_FRONT_DOOR=1 git push -q "$n8a" "$n9r" :refs/leases/land 2>&1 ); n9rc=$?
    set -e
    n9others=$(git --git-dir="$lremote" for-each-ref --format='%(refname) %(objectname)' | grep -v 'refs/leases/land' || true)
    n9want=$(printf '%s\n' "$n8before" | grep -v 'refs/leases/land' || true)
    if [ "$n9others" = "$n9want" ]; then
      echo "PASS: N9 remote $n9r: git refused (rc $n9rc) or deleted only the named ref; no other ref on origin changed"
    else
      echo "FAIL: N9 remote $n9r changed another ref on origin (rc $n9rc) [$n9o]"; exit 1
    fi
    git --git-dir="$lremote" rev-parse --verify -q refs/leases/land >/dev/null 2>&1 || { git --git-dir="$lremote" update-ref refs/leases/land "$n8t" >/dev/null 2>&1 || true; }
  done
  git --git-dir="$lremote" update-ref -d refs/leases/land >/dev/null 2>&1 || true
  git --git-dir="$lremote" update-ref -d refs/leases-log/land >/dev/null 2>&1 || true
else
  echo "N/A: scripts/checkout-lease.sh not present next to kit-guard — land lease shim case skipped"
fi

echo "OK: shim-coverage — generated + deny + allow + passthrough + symlink-no-recursion + front-door + claim front door + land lease under shims all proven"
exit 0
