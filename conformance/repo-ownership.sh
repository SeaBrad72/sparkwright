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
# CP-11 closes the git-dir-CONTAINMENT gap: GIT_DIR/GIT_WORK_TREE env redirects are hard-refused, and
# submodule / `git worktree add` trees are refused unless gated behind --allow-nested. Residual (named,
# not absorbed): core.hooksPath, GIT_OBJECT_DIRECTORY, insteadOf — the git dir stays inside the cwd, so
# containment passes; out of CP-11 scope. See CP-11 design §6.
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
  # INCEPT-CONTAIN: a real adopter export STRIPS the export-ignored kit-internal markers, and incept now
  # REFUSES a tree carrying them (conformance/incept-containment.sh). lay_kit is a raw copy (not `git
  # archive`), so it must strip the SAME set to stay a faithful export shape — otherwise incept's
  # containment guard refuses these (legitimately export-shaped) greenfield/brownfield fixtures. Single
  # source of truth: incept.sh's KIT_INTERNAL_MARKERS line (markers are glob-free, [A-Za-z0-9._/-] only).
  _kit_markers=$(sed -n "s/^KIT_INTERNAL_MARKERS='\(.*\)'.*/\1/p" "$KIT_ROOT/scripts/incept.sh")
  for _m in $_kit_markers; do [ -n "$_m" ] && rm -rf "${1:?}/$_m"; done
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

# =============================================================================================
# CP-11 — GIT_DIR / GIT_WORK_TREE env redirection + worktree/submodule nesting.
#   CP-4 proves --show-toplevel == pwd. Under an env redirect that still holds, but git-common-dir
#   (and thus the hook path / archive HEAD) points at ANOTHER repo. E1/E2/E3/W1/S1 are RED against
#   the current scripts — they go green in T2-T4. N-sym/P2/P3 lock behavior after the fix.
# =============================================================================================

# E1 — incept with ambient GIT_DIR/GIT_WORK_TREE pointing at a STRANGER repo. Today CP-4's toplevel==pwd
#      check PASSES (measured) and the hook lands in the stranger's .git/hooks/. Must refuse HARD (no flag).
make_parent "$T/e1-stranger"
lay_kit "$T/e1-victim"
before=$(fp "$T/e1-stranger/.git/hooks")
# shellcheck disable=SC2086
out=$( cd "$T/e1-victim" && GIT_DIR="$T/e1-stranger/.git" GIT_WORK_TREE="$T/e1-victim" \
       sh scripts/incept.sh $INCEPT_ARGS 2>&1 ); rc=$?
after=$(fp "$T/e1-stranger/.git/hooks")
if [ "$before" != "$after" ]; then
  bad "E1 incept env-redirect — WROTE A HOOK INTO A STRANGER'S .git/hooks/ (GIT_DIR redirect)"
elif [ "$rc" -eq 0 ]; then
  bad "E1 incept env-redirect — exit 0 (must refuse before any mutation)"
elif ! printf '%s' "$out" | grep -q 'GIT_DIR'; then
  bad "E1 incept env-redirect — refused but message does not name GIT_DIR/GIT_WORK_TREE + the unset escape"
else
  pass "E1 incept env-redirect — refused, stranger untouched, named the env vars"
fi

# E2 — preflight with ambient GIT_DIR redirect reports the STRANGER as the adopter environment.
make_parent "$T/e2-stranger"
lay_kit "$T/e2-victim"
out=$( cd "$T/e2-victim" && GIT_DIR="$T/e2-stranger/.git" GIT_WORK_TREE="$T/e2-victim" \
       sh scripts/preflight.sh 2>&1 ); rc=$?
if [ "$rc" -eq 0 ]; then
  bad "E2 preflight env-redirect — exit 0 (must refuse: env points git at a repo it does not own)"
elif ! printf '%s' "$out" | grep -q 'GIT_DIR'; then
  bad "E2 preflight env-redirect — refused but did not name GIT_DIR/GIT_WORK_TREE"
else
  pass "E2 preflight env-redirect — refused, named the env vars"
fi

# E3 — adopter-export with ambient GIT_DIR redirect: `git archive HEAD` resolves to the STRANGER's HEAD.
make_parent "$T/e3-stranger"
lay_kit "$T/e3-kit" && ( cd "$T/e3-kit" && git_q init && git_q add -A && git_q commit -m base )
out=$( cd "$T/e3-kit" && GIT_DIR="$T/e3-stranger/.git" GIT_WORK_TREE="$T/e3-kit" \
       sh scripts/adopter-export.sh "$T/e3-out" 2>&1 ); rc=$?
if [ "$rc" -eq 0 ]; then
  bad "E3 export env-redirect — exit 0 (would archive the STRANGER's HEAD, not the kit)"
elif [ -e "$T/e3-out" ]; then
  bad "E3 export env-redirect — refused but LEFT a destination behind ($T/e3-out)"
elif ! printf '%s' "$out" | grep -q 'GIT_DIR'; then
  bad "E3 export env-redirect — refused but did not name GIT_DIR/GIT_WORK_TREE"
else
  pass "E3 export env-redirect — refused, named the env vars"
fi

# W1 — incept inside a `git worktree add` tree (env CLEAN). git-common-dir is main/.git (measured);
#      the hook would land in MAIN's shared .git/hooks/. Must refuse unless --allow-nested.
lay_kit "$T/w1-main" && ( cd "$T/w1-main" && git_q init && git_q add -A && git_q commit -m base )
( cd "$T/w1-main" && git_q worktree add ../w1-linked )
[ -f "$T/w1-linked/scripts/incept.sh" ] || bad "W1 setup — linked worktree has no scripts/incept.sh"
before=$(fp "$T/w1-main/.git/hooks")
# shellcheck disable=SC2086
out=$( cd "$T/w1-linked" && sh scripts/incept.sh $INCEPT_ARGS 2>&1 ); rc=$?
after=$(fp "$T/w1-main/.git/hooks")
if [ "$before" != "$after" ]; then
  bad "W1 incept in a linked worktree — WROTE into MAIN's shared .git/hooks/ (git-common-dir outside cwd)"
elif [ "$rc" -eq 0 ]; then
  bad "W1 incept in a linked worktree — exit 0 (must refuse unless --allow-nested)"
elif ! printf '%s' "$out" | grep -q 'allow-nested'; then
  bad "W1 incept in a linked worktree — refused but did not signpost --allow-nested"
else
  pass "W1 incept in a linked worktree — refused, main's hooks untouched, signposted --allow-nested"
fi

# S1 — incept inside a submodule (env CLEAN). git-common-dir is super/.git/modules/... (measured).
#      Must refuse unless --allow-nested; the module's hooks must be byte-identical on refusal.
lay_kit "$T/s1-suborigin" && ( cd "$T/s1-suborigin" && git_q init && git_q add -A && git_q commit -m lib )
mkdir -p "$T/s1-super" && ( cd "$T/s1-super" && git_q init && git_q commit --allow-empty -m top \
  && git_q -c protocol.file.allow=always submodule add "$T/s1-suborigin" vendor/lib && git_q commit -m addsub )
lay_kit "$T/s1-super/vendor/lib"
_modhooks="$T/s1-super/.git/modules/vendor/lib/hooks"
before=$(fp "$_modhooks")
# shellcheck disable=SC2086
out=$( cd "$T/s1-super/vendor/lib" && sh scripts/incept.sh $INCEPT_ARGS 2>&1 ); rc=$?
after=$(fp "$_modhooks")
if [ "$before" != "$after" ]; then
  bad "S1 incept in a submodule — WROTE into super/.git/modules/.../hooks/"
elif [ "$rc" -eq 0 ]; then
  bad "S1 incept in a submodule — exit 0 (must refuse unless --allow-nested)"
elif ! printf '%s' "$out" | grep -q 'allow-nested'; then
  bad "S1 incept in a submodule — refused but did not signpost --allow-nested"
else
  pass "S1 incept in a submodule — refused, module hooks untouched"
fi

# E1b — incept with GIT_DIR pointing at a NOT-YET-A-REPO directory (the fail-open: git_dir_outside returns
#       "inside" because rev-parse fails, so the nested env check is skipped and incept git-inits the target
#       and writes a hook into it). git_env_redirected must be checked UNCONDITIONALLY. Target byte-identical.
mkdir -p "$T/e1b-target" "$T/e1b-victim"
lay_kit "$T/e1b-victim"
before=$(fp "$T/e1b-target")
# shellcheck disable=SC2086
out=$( cd "$T/e1b-victim" && GIT_DIR="$T/e1b-target" GIT_WORK_TREE="$T/e1b-victim" \
       sh scripts/incept.sh $INCEPT_ARGS 2>&1 ); rc=$?
after=$(fp "$T/e1b-target")
if [ "$before" != "$after" ]; then
  bad "E1b incept env-redirect to a NON-REPO dir — git-inited/wrote into GIT_DIR target (foreign write)"
elif [ "$rc" -eq 0 ]; then
  bad "E1b incept env-redirect to a non-repo dir — exit 0 (must refuse: GIT_DIR is set)"
elif ! printf '%s' "$out" | grep -q 'GIT_DIR'; then
  bad "E1b incept env-redirect to a non-repo dir — refused but did not name GIT_DIR"
else
  pass "E1b incept env-redirect to a non-repo dir — refused, target untouched, named GIT_DIR"
fi

# E1c — incept with GIT_WORK_TREE set ALONE (no GIT_DIR). Also makes rev-parse unresolvable in the victim,
#       so the same nested-skip fail-open applies. Must refuse (GIT_WORK_TREE is set).
mkdir -p "$T/e1c-victim"
lay_kit "$T/e1c-victim"
# shellcheck disable=SC2086
out=$( cd "$T/e1c-victim" && GIT_WORK_TREE="$T/e1c-victim" \
       sh scripts/incept.sh $INCEPT_ARGS 2>&1 ); rc=$?
if [ "$rc" -eq 0 ]; then
  bad "E1c incept with GIT_WORK_TREE alone — exit 0 (must refuse: GIT_WORK_TREE is set)"
elif ! printf '%s' "$out" | grep -q 'GIT_WORK_TREE'; then
  bad "E1c incept with GIT_WORK_TREE alone — refused but did not name GIT_WORK_TREE"
else
  pass "E1c incept with GIT_WORK_TREE alone — refused, named GIT_WORK_TREE"
fi

# E2b — preflight with GIT_DIR pointing at a NOT-YET-A-REPO dir. Same fail-open; preflight must refuse.
mkdir -p "$T/e2b-target" "$T/e2b-victim"
lay_kit "$T/e2b-victim"
out=$( cd "$T/e2b-victim" && GIT_DIR="$T/e2b-target" GIT_WORK_TREE="$T/e2b-victim" \
       sh scripts/preflight.sh 2>&1 ); rc=$?
if [ "$rc" -eq 0 ]; then
  bad "E2b preflight env-redirect to a non-repo dir — exit 0 (must refuse: GIT_DIR is set)"
elif ! printf '%s' "$out" | grep -q 'GIT_DIR'; then
  bad "E2b preflight env-redirect to a non-repo dir — refused but did not name GIT_DIR"
else
  pass "E2b preflight env-redirect to a non-repo dir — refused, named GIT_DIR"
fi

# N-sym — a NORMAL repo reached via a SYMLINK. The containment compare must use pwd -P on BOTH sides or it
#         false-refuses under /tmp on macOS. (CP-4's N6, for CP-11.)
mkdir -p "$T/nsym-real" && lay_kit "$T/nsym-real"
( cd "$T/nsym-real" && git_q init && git_q add -A && git_q commit -m base )
ln -s "$T/nsym-real" "$T/nsym-link"
# shellcheck disable=SC2086
out=$( cd "$T/nsym-link" && sh scripts/incept.sh $INCEPT_ARGS 2>&1 ); rc=$?
if [ "$rc" -ne 0 ]; then
  bad "N-sym incept via a symlinked repo root — FALSE REFUSAL (exit $rc). Compare pwd -P on BOTH sides."
else
  pass "N-sym incept via a symlinked repo root — proceeded (git-common-dir compare is physical)"
fi

# P2 — --allow-nested in a linked worktree: proceeds, and the summary names the REAL shared hook path.
lay_kit "$T/p2w-main" && ( cd "$T/p2w-main" && git_q init && git_q add -A && git_q commit -m base )
( cd "$T/p2w-main" && git_q worktree add ../p2w-linked )
# shellcheck disable=SC2086
out=$( cd "$T/p2w-linked" && sh scripts/incept.sh $INCEPT_ARGS --allow-nested 2>&1 ); rc=$?
if [ "$rc" -ne 0 ]; then
  bad "P2 --allow-nested in a worktree — not accepted (exit $rc)"
elif ! printf '%s' "$out" | grep -q "$T/p2w-main/.git/hooks/pre-push"; then
  bad "P2 --allow-nested in a worktree — summary does not name the real shared hook path"
else
  pass "P2 --allow-nested in a worktree — proceeded, named the real shared hook path"
fi

# P3 — adopter-export from a linked worktree (env CLEAN, NO flag): the git-dir gates must NOT refuse it
#      (env-only scope for export — the load-bearing don't-over-refuse-the-maintainer positive).
#      ASSERT ON THE GIT-DIR REFUSAL, not overall exit status: this fixture's "kit" is itself an
#      already-EXPORTED tree on the artifact leg (--kit-root <export>), whose CLAUDE.md has had its
#      backlog-backend declaration CARVED OUT — so re-exporting it legitimately fails the 'Backlog backend'
#      carve, which runs AFTER owns_itself + git_env_redirected in do_export and is orthogonal to CP-11.
#      Reaching the export body (carve) — or a full rc0 export on the source leg — proves the worktree was
#      NOT refused by a git-dir gate. A structural refusal would exit BEFORE the body -> caught by the else.
lay_kit "$T/p3-main" && ( cd "$T/p3-main" && git_q init && git_q add -A && git_q commit -m base )
( cd "$T/p3-main" && git_q worktree add ../p3-linked )
out=$( cd "$T/p3-linked" && sh scripts/adopter-export.sh "$T/p3-out" 2>&1 ); rc=$?
if printf '%s' "$out" | grep -qE 'redirects git away|not the root of its own git repository|git dir lives outside'; then
  bad "P3 export from a linked worktree — a git-dir gate REFUSED a structural worktree (env-only scope broken)"
elif [ "$rc" -eq 0 ]; then
  if [ -f "$T/p3-out/scripts/incept.sh" ]; then
    pass "P3 export from a linked worktree — full export succeeded (git-dir gates allowed the worktree)"
  else
    bad "P3 export from a linked worktree — exit 0 but produced no files (silent success)"
  fi
elif printf '%s' "$out" | grep -q 'Backlog backend'; then
  pass "P3 export from a linked worktree — git-dir gates allowed it (reached the export body; the re-export carve failure is orthogonal to CP-11)"
else
  bad "P3 export from a linked worktree — unexpected failure (exit $rc): $(printf '%s' "$out" | tail -1)"
fi

echo
[ "$fail" -eq 0 ] && { echo "OK: repo-ownership"; exit 0; } || { echo "FAIL: repo-ownership"; exit 1; }
