#!/bin/sh
# repo-ownership.sh — CP-4 conformance lock.
#
# The invariant: every script that mutates the adopter's tree, or reports on their environment, must
# prove that THIS DIRECTORY IS THE ROOT OF ITS OWN GIT REPOSITORY — and must fail BEFORE any file,
# hook, or directory is touched when it is not.
#
# `git rev-parse --is-inside-work-tree` answers a DIFFERENT question ("is there a repo above me?").
# The two answers diverge only when nested — which is why every non-nested test agrees, and why this
# bug survived a bookend, two security reviews and a re-review.
#
# Honest ceiling: this proves OWNERSHIP. It does NOT cover GIT_DIR / GIT_WORK_TREE env redirection,
# submodules, or `git worktree add` trees. See CP-11.
set -u

KIT_ROOT=$(CDPATH='' cd "$(dirname "$0")/.." && pwd -P)
while [ $# -gt 0 ]; do
  case "$1" in
    --kit-root) [ -n "${2:-}" ] || { echo "repo-ownership: --kit-root requires a non-empty directory path" >&2; exit 2; }
                KIT_ROOT=$(CDPATH='' cd "$2" 2>/dev/null && pwd -P) || true
                # A bad --kit-root must fail LOUD, not silently yield empty -> lay_kit globbing "/*"
                # -> a filesystem-wide copy. Guard the arg at the boundary (empty AND unresolvable).
                [ -n "$KIT_ROOT" ] && [ -d "$KIT_ROOT" ] || { echo "repo-ownership: --kit-root '$2' is not a readable directory" >&2; exit 2; }
                shift 2 ;;
    --selftest) shift ;;                       # fixtures ARE the selftest; accepted for idiom parity
    *) echo "repo-ownership: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

fail=0
pass() { echo "PASS: $1"; }
bad()  { echo "FAIL: $1"; fail=1; }

T=$(mktemp -d) || exit 1
cleanup() { chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT INT TERM

git_q() { git -c user.email=t@kit -c user.name=t -c init.defaultBranch=main "$@" >/dev/null 2>&1; }

# Lay down a kit tree (content only, NO .git) at $1 — exactly what an adopter's export looks like.
#
# Deliberately a COPY, not `git archive HEAD`: this lock is REQUIRED, so it also runs inside the
# exported artifact (artifact-gate's `verify.sh --require`) — and a freshly incepted adopter HAS NO
# COMMIT (incept git-inits; it does not commit). `git archive HEAD` would seed NOTHING there and every
# assertion below would pass vacuously. That is precisely the CP-5 defect, one layer down.
# `tar --exclude` is not portable (BSD vs GNU) — walk the entries instead.
lay_kit() {  # <dir>
  # Belt-and-braces: never glob an empty/invalid KIT_ROOT (that is "$KIT_ROOT"/* -> "/*" -> a copy of
  # the whole root filesystem). The --kit-root handler already guards the CLI path; this covers the
  # default assignment too.
  [ -n "$KIT_ROOT" ] && [ -d "$KIT_ROOT" ] || { bad "lay_kit: KIT_ROOT unset or not a directory ('$KIT_ROOT')"; return 1; }
  mkdir -p "$1" || return 1
  for _f in "$KIT_ROOT"/* "$KIT_ROOT"/.[!.]*; do
    [ -e "$_f" ] || continue
    case "${_f##*/}" in .git|node_modules|.worktrees|coverage) continue ;; esac
    cp -Rp "$_f" "$1/" || return 1
  done
  # Liveness anchor on the FIXTURE ITSELF — a seeding step that silently produced nothing must not
  # leave every assertion below trivially green. (An empty fixture is not a pass.)
  [ -f "$1/scripts/incept.sh" ] && [ -f "$1/scripts/preflight.sh" ] && return 0
  bad "fixture seeding — $1 has no scripts/incept.sh (cannot test; refusing to pass vacuously)"
  return 1
}

# A parent repo with a github origin, and an UNTRACKED child inside it. The probe's exact shape.
make_parent() {  # <dir>
  mkdir -p "$1" && ( cd "$1" && git_q init && git_q remote add origin https://github.com/someone/not-yours.git \
    && : > .keep && git_q add .keep && git_q commit -m base )
}

INCEPT_ARGS="--noninteractive --name OwnTest --intent-owner CI --stack typescript-node --backlog md --harness generic --no-db"

# Fingerprint a directory's contents (names + bytes) so we can prove NOTHING was written.
fp() { ( cd "$1" 2>/dev/null && find . -type f -exec cksum {} + 2>/dev/null | sort ) | cksum; }

echo "== repo-ownership: fixtures under $T (kit: $KIT_ROOT) =="

# ---------------------------------------------------------------------------------------------
# N1 — preflight nested: must NOT report the parent's remote as the adopter environment.
# ---------------------------------------------------------------------------------------------
make_parent "$T/n1"
lay_kit "$T/n1/child"
out=$( cd "$T/n1/child" && sh scripts/preflight.sh 2>&1 ); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'Adopter environment'; then
  bad "N1 preflight nested — exit 0 and reported the PARENT as the adopter environment"
elif [ "$rc" -eq 0 ]; then
  bad "N1 preflight nested — exit 0 (must refuse: it is not its own repo root)"
else
  pass "N1 preflight nested — refused (exit $rc)"
fi

# ---------------------------------------------------------------------------------------------
# N2 — incept nested: must abort BEFORE any mutation. The parent's .git/hooks/ must be BYTE-IDENTICAL.
#      Asserting only on the exit code would pass a script that writes the hook and THEN errors.
# ---------------------------------------------------------------------------------------------
make_parent "$T/n2"
lay_kit "$T/n2/child"
before=$(fp "$T/n2/.git/hooks")
# shellcheck disable=SC2086  # INCEPT_ARGS is a deliberate word list
out=$( cd "$T/n2/child" && sh scripts/incept.sh $INCEPT_ARGS 2>&1 ); rc=$?
after=$(fp "$T/n2/.git/hooks")
if [ "$before" != "$after" ]; then
  bad "N2 incept nested — MUTATED THE PARENT'S .git/hooks/ (wrote a hook into a repo it was never pointed at)"
elif [ "$rc" -eq 0 ]; then
  bad "N2 incept nested — exit 0 (must refuse before any mutation)"
else
  pass "N2 incept nested — refused, parent's .git/hooks/ byte-identical"
fi

# ---------------------------------------------------------------------------------------------
# N3 — the summary must never claim a hook path it did not write. (incept:491 HARDCODES
#      ".git/hooks/pre-push" into GUARD_STEP — the line the adopter actually reads.)
# ---------------------------------------------------------------------------------------------
if printf '%s' "$out" | grep -q 'guard installed at \.git/hooks/pre-push'; then
  bad "N3 incept nested — summary claims a LOCAL hook install that never happened (hardcoded GUARD_STEP)"
else
  pass "N3 incept nested — summary claims no hook it did not write"
fi

# ---------------------------------------------------------------------------------------------
# N4 — export from an UNTRACKED NESTED KIT: `git archive HEAD` resolves to the PARENT's HEAD and the
#      cwd prefix matches nothing -> empty archive -> "exported 0 files", exit 0. Silent success.
# ---------------------------------------------------------------------------------------------
make_parent "$T/n4"
lay_kit "$T/n4/kit"
out4=$( cd "$T/n4/kit" && sh scripts/adopter-export.sh "$T/n4-out" 2>&1 ); rc4=$?
if [ "$rc4" -eq 0 ]; then
  bad "N4 export from a nested/untracked kit — exit 0 ($(printf '%s' "$out4" | grep -o 'exported [0-9]* files' || echo 'no count'))"
else
  pass "N4 export from a nested/untracked kit — refused (exit $rc4)"
fi

# ---------------------------------------------------------------------------------------------
# N5 — a FAILED export must leave NO destination, and the retry must succeed. Today the exporter
#      extracts BEFORE the carve can fail, so a failed export leaves a non-empty dest and the retry
#      hits "refusing to clobber" -> WEDGED. The current selftest ASSERTS this ("should extract
#      before refusing") — that assertion must be INVERTED.
# ---------------------------------------------------------------------------------------------
# Force a carve failure: >1 "Backlog backend:" declaration makes the carve ambiguous (loud-fail).
#
# Append TWO, not one. In the KIT tree CLAUDE.md declares a backend (1 + 1 = ambiguous), but in the
# EXPORTED tree that declaration has already been CARVED OUT (0 + 1 = unambiguous -> the export would
# SUCCEED and this fixture would not exercise the failure path at all). Two guarantees >= 2 either way.
# The `N5 setup` assertion below is what caught this: it refuses to report a pass on a fixture that
# never exercised its path. A fixture that quietly stops testing is the vacuity we are here to kill.
lay_kit "$T/n5-kit"
( cd "$T/n5-kit" && git_q init \
  && printf '\n- **Backlog backend**: BACKLOG.md (dupA)\n- **Backlog backend**: BACKLOG.md (dupB)\n' >> CLAUDE.md \
  && git_q add -A && git_q commit -m dup )
( cd "$T/n5-kit" && sh scripts/adopter-export.sh "$T/n5-out" >/dev/null 2>&1 ); rc5=$?
if [ "$rc5" -eq 0 ]; then
  bad "N5 setup — the ambiguous-carve export unexpectedly SUCCEEDED (fixture is not exercising the path)"
elif [ -e "$T/n5-out" ]; then
  bad "N5 failed export — LEFT A DESTINATION behind ($(find "$T/n5-out" -type f | wc -l | tr -d ' ') files); the retry is wedged"
else
  pass "N5 failed export — left no destination"
fi

# ---------------------------------------------------------------------------------------------
# N6 — THE SYMLINK LANDMINE. `git rev-parse --show-toplevel` is symlink-RESOLVED; $PWD is not.
#      On macOS /tmp -> /private/tmp. A naive compare FALSE-REFUSES here while passing on Linux CI.
#      This fixture is what stops the fix from being unusable under /tmp on every Mac.
# ---------------------------------------------------------------------------------------------
mkdir -p "$T/n6-real"
lay_kit "$T/n6-real"
( cd "$T/n6-real" && git_q init && git_q add -A && git_q commit -m base )
ln -s "$T/n6-real" "$T/n6-link"
# shellcheck disable=SC2086
out6=$( cd "$T/n6-link" && sh scripts/incept.sh $INCEPT_ARGS 2>&1 ); rc6=$?
if [ "$rc6" -ne 0 ]; then
  bad "N6 incept via a SYMLINKED repo root — FALSE REFUSAL (exit $rc6). Compare pwd -P on BOTH sides."
  printf '     last: %s\n' "$(printf '%s' "$out6" | tail -1)"
else
  pass "N6 incept via a symlinked repo root — proceeded (no false refusal)"
fi

# ---------------------------------------------------------------------------------------------
# P1 — standalone greenfield: git init runs, the hook lands LOCALLY, the summary is true.
# ---------------------------------------------------------------------------------------------
lay_kit "$T/p1"
# shellcheck disable=SC2086
out1=$( cd "$T/p1" && sh scripts/incept.sh $INCEPT_ARGS 2>&1 ); rc1=$?
if [ "$rc1" -ne 0 ]; then
  bad "P1 standalone greenfield — incept failed (exit $rc1); this is today's supported path"
  printf '     last: %s\n' "$(printf '%s' "$out1" | tail -1)"
elif [ ! -f "$T/p1/.git/hooks/pre-push" ]; then
  bad "P1 standalone greenfield — the pre-push hook did NOT land locally"
else
  pass "P1 standalone greenfield — git init ran, hook landed locally"
fi

# ---------------------------------------------------------------------------------------------
# P2 — --allow-nested: proceeds, and the summary TRUTHFULLY names the parent hook path it wrote.
# ---------------------------------------------------------------------------------------------
make_parent "$T/p2"
lay_kit "$T/p2/child"
# shellcheck disable=SC2086
out2=$( cd "$T/p2/child" && sh scripts/incept.sh $INCEPT_ARGS --allow-nested 2>&1 ); rc2=$?
if [ "$rc2" -ne 0 ]; then
  bad "P2 --allow-nested — not accepted (exit $rc2); the monorepo adopter has no supported path"
elif [ ! -f "$T/p2/.git/hooks/pre-push" ]; then
  bad "P2 --allow-nested — proceeded but the hook did not land in the parent's .git/hooks/"
elif ! printf '%s' "$out2" | grep -q "$T/p2/.git/hooks/pre-push"; then
  bad "P2 --allow-nested — the summary does NOT name the parent hook path it actually wrote"
else
  pass "P2 --allow-nested — proceeded and named the parent hook path truthfully"
fi

# ---------------------------------------------------------------------------------------------
# P3 — brownfield AT A REAL REPO ROOT: untouched. This is a regression guard on today's behaviour.
# ---------------------------------------------------------------------------------------------
lay_kit "$T/p3"
( cd "$T/p3" && git_q init && git_q add -A && git_q commit -m base )
# shellcheck disable=SC2086
out3=$( cd "$T/p3" && sh scripts/incept.sh $INCEPT_ARGS 2>&1 ); rc3=$?
if [ "$rc3" -ne 0 ]; then
  bad "P3 brownfield at repo root — REGRESSED (exit $rc3); this path works today"
  printf '     last: %s\n' "$(printf '%s' "$out3" | tail -1)"
else
  pass "P3 brownfield at repo root — unchanged"
fi

echo
[ "$fail" -eq 0 ] && { echo "OK: repo-ownership"; exit 0; } || { echo "FAIL: repo-ownership"; exit 1; }
