#!/bin/sh
# preflight.sh — prerequisite check for Sparkwright (the agentic SDLC kit). Fails fast with
# install hints so a missing tool surfaces HERE, not as a cryptic guard/conformance
# failure later (jq is hard-required by the guard + conformance). Universal check
# always; optional per-stack toolchain via --stack.
#   sh scripts/preflight.sh [--stack <name>] [--selftest]
# Exit: 0 = all present · 1 = a required tool missing · 2 = bad usage.
# POSIX sh; dash-clean. New stack? add a row to stack_tools() (unknown degrades gracefully).
# What it changes: Read-only — checks for required/recommended tools; mutates nothing.
# Guardrails: exit 1 if a required tool is missing (recommended tools only warn); an unknown --stack degrades gracefully.
set -eu

miss=0; rec=0
need() {  # need <tool> <install-hint>
  if command -v "$1" >/dev/null 2>&1; then
    echo "  ok   $1"
  else
    echo "  MISS $1 — $2"
    miss=1
  fi
}
recommend() {  # recommend <tool> <why+hint> — warns, never fails the run
  if command -v "$1" >/dev/null 2>&1; then
    echo "  ok   $1"
  else
    echo "  warn $1 — $2"
    rec=1
  fi
}

# --- T2: git version floor for `git merge-tree --write-tree` -------------------------------
# kit-update prefers `git merge-tree --write-tree` — a NON-mutating 3-way merge (the adopter's
# worktree is never touched). That subcommand landed in git 2.38 (2022); Ubuntu 20.04 still ships
# git 2.25. DETECT AND DEGRADE: below the floor we warn and NAME the escape (the temporary-worktree
# fallback, which is also non-mutating) — we never hard-fail, and we never silently fail open.
GIT_FLOOR_MAJOR=2
GIT_FLOOR_MINOR=38

git_version_parts() {  # <version line> -> "MAJOR MINOR" on stdout; rc 1 when unparseable
  # Takes the first whitespace-separated token starting with a digit, so it survives every real
  # shape: "git version 2.39.5 (Apple Git-154)", "git version 2.25.1", "git version 2.41.0.windows.3".
  #
  # `set -f` around the split: unquoted $1 does word-splitting (which we WANT) *and* pathname expansion
  # (which we do not). A '*' anywhere in the line would glob against the CWD, so a file named '9.9.9'
  # would BE the version — the floor reading the filesystem instead of git. Quoting $1 is not the fix
  # (it would collapse the line to a single word and parse nothing); disabling globbing is. No `return`
  # inside the window, so globbing is always restored.
  _tok=""
  set -f
  for _w in $1; do
    case "$_w" in [0-9]*) _tok=$_w; break ;; esac
  done
  set +f
  [ -n "$_tok" ] || return 1
  _maj=${_tok%%.*}
  case "$_tok" in *.*) _rest=${_tok#*.} ;; *) _rest=0 ;; esac
  _min=${_rest%%.*}
  _min=${_min%%[!0-9]*}   # tolerate a pre-release tail (2.39-rc1 -> 39)
  case "$_maj" in ''|*[!0-9]*) return 1 ;; esac
  case "$_min" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s %s\n' "$_maj" "$_min"
}

git_meets_floor() {  # <major> <minor> -> 0 iff >= the floor. NUMERIC compare, deliberately:
  # `[ ]`'s -gt/-ge are integer operators, so 9 -lt 38 is TRUE. A lexical compare would say
  # "2.9" > "2.38" and wave an ancient git through — a decorative floor. This is that bug's lock.
  if [ "$1" -ne "$GIT_FLOOR_MAJOR" ]; then [ "$1" -gt "$GIT_FLOOR_MAJOR" ]; return $?; fi
  [ "$2" -ge "$GIT_FLOOR_MINOR" ]
}

check_git_capability() {  # advisory: does the installed git support `merge-tree --write-tree`?
  # FLAG-NOT-ENV: the PREFLIGHT_GIT_VERSION_CMD injection seam is honored ONLY when a seam flag was
  # passed (--selftest, or --selftest-e2e for the wired end-to-end proof). In a real adopter run the
  # ambient environment cannot tell preflight what version of git they have. Advisory-only, so no
  # privilege boundary is crossed — but a check the environment can redirect is not a check, and this
  # is the same rule `incept --date` honors (a flag, never an ambient INCEPT_DATE).
  _vcmd="git --version"
  [ "${SEAMS:-0}" -eq 1 ] && _vcmd="${PREFLIGHT_GIT_VERSION_CMD:-git --version}"
  # shellcheck disable=SC2086  # deliberate word-split: the seam supplies a command line, not one word
  _ver=$(${_vcmd} 2>/dev/null) || _ver=""
  if [ -z "$_ver" ]; then
    echo "  skip git version — could not run 'git --version' (cannot detect merge-tree support)"; return 0
  fi
  if ! _parts=$(git_version_parts "$_ver"); then
    echo "  skip git version — unrecognised version string: $_ver"; return 0
  fi
  _gmaj=${_parts% *}; _gmin=${_parts#* }
  if git_meets_floor "$_gmaj" "$_gmin"; then
    echo "  ok   git $_gmaj.$_gmin — 'git merge-tree --write-tree' available (floor $GIT_FLOOR_MAJOR.$GIT_FLOOR_MINOR)"
  else
    echo "  warn git $_gmaj.$_gmin is below the $GIT_FLOOR_MAJOR.$GIT_FLOOR_MINOR floor — 'git merge-tree --write-tree' is unavailable."
    echo "       kit-update will use its temporary-worktree fallback instead of merge-tree. The fallback is"
    echo "       still non-mutating (your worktree is never touched); upgrading git only makes it faster."
    rec=1
  fi
}

stack_tools() {  # print "tool|hint" lines for a stack; return 1 if unknown
  case "$1" in
    typescript-node) printf 'node|nodejs.org or nvm\nnpm|ships with Node\n' ;;
    python|ml|data-engineering) printf 'python3|python.org or pyenv\npip3|ships with Python\n' ;;
    go) printf 'go|go.dev/dl\n' ;;
    dotnet) printf 'dotnet|dotnet.microsoft.com/download\n' ;;
    rust) printf 'cargo|rustup.rs\n' ;;
    java-spring) printf 'java|adoptium.net\nmvn|maven.apache.org\n' ;;
    kotlin) printf 'java|adoptium.net\n' ;;
    terraform) printf 'terraform|developer.hashicorp.com/terraform/install\n' ;;
    *) return 1 ;;
  esac
}

is_github_repo() {  # 0 iff inside a work tree whose origin is a github.com remote
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  _origin=$(git remote get-url origin 2>/dev/null) || return 1
  case "$_origin" in *github.com*) return 0 ;; *) return 1 ;; esac
}

# --- CP-4: repository ownership is a hard precondition -------------------------------------
# `git rev-parse --is-inside-work-tree` answers "is there a repo ABOVE me?" — not "is THIS dir the
# root of its own repo?". The two diverge only when nested, which is why every non-nested test
# agrees and why the kit once wrote a pre-push hook into a stranger's repository.
#
# BOTH sides of the compare must be PHYSICAL paths: `--show-toplevel` is symlink-resolved, `$PWD`
# is not. On macOS /tmp -> /private/tmp, so a logical compare FALSE-REFUSES under /tmp while
# passing on Linux CI. Normalizing both sides is the only compare that cannot drift.
#
# CP-11 closes the git-dir-CONTAINMENT gap: GIT_DIR/GIT_WORK_TREE env redirects are hard-refused, and
# submodule / `git worktree add` trees are refused unless gated behind --allow-nested. Residual (named,
# not absorbed): core.hooksPath, GIT_OBJECT_DIRECTORY, insteadOf — the git dir stays inside the cwd, so
# containment passes; out of CP-11 scope. See CP-11 design §6.
owning_repo_root() {  # <dir> -> stdout: physical toplevel, or empty when <dir> is in no repo
  ( CDPATH='' cd "$1" 2>/dev/null || exit 0
    _t=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
    CDPATH='' cd "$_t" 2>/dev/null && pwd -P )
}
owns_itself() {  # <dir> -> 0 iff <dir> is its own repo root, or is in no repo at all
  # "Cannot determine" must REFUSE, never proceed (the kit's default). Compute the physical cwd FIRST:
  # a dir we cannot even cd into is not "in no repo -> fine", it is unknown -> refuse. Unreachable from
  # today's call sites (all pass "$PWD"/"$ROOT"), but the wrong default is worth closing.
  _phys=$( CDPATH='' cd "$1" 2>/dev/null && pwd -P ) || return 1
  [ -n "$_phys" ] || return 1
  _own=$(owning_repo_root "$1")
  [ -n "$_own" ] || return 0
  [ "$_own" = "$_phys" ]
}

# --- CP-11: git-dir redirection is a hard precondition (closes CP-4 §6) --------------------
# CP-4 proves toplevel==pwd, but `--show-toplevel` reports the cwd even when GIT_DIR/GIT_WORK_TREE, a
# submodule, or a `git worktree add` tree redirect the git dir ELSEWHERE (measured). The hook then lands
# in a repo the operator does not own (env) or a shared/other .git (structural). Invariant: the git dir
# that will receive the write lives INSIDE the tree I own. BOTH sides physical (the /tmp symlink landmine).
git_env_redirected() { [ -n "${GIT_DIR:-}" ] || [ -n "${GIT_WORK_TREE:-}" ]; }
git_dir_outside() {  # <dir> -> 0 (true) iff the physical git-common-dir is NOT inside <dir>
  _cwd=$( CDPATH='' cd "$1" 2>/dev/null && pwd -P ) || return 0
  _gcd=$( CDPATH='' cd "$1" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null ) || return 1
  [ -n "$_gcd" ] || return 1
  _gcd_phys=$( CDPATH='' cd "$1" 2>/dev/null && CDPATH='' cd "$_gcd" 2>/dev/null && pwd -P ) || return 0
  case "$_gcd_phys/" in "$_cwd"/*) return 1 ;; *) return 0 ;; esac
}

check_repo_class() {  # warn when the repo is user-owned PRIVATE (SLSA provenance gate skips there)
  if [ -z "${PREFLIGHT_GH_CMD:-}" ] && ! command -v gh >/dev/null 2>&1; then
    echo "  skip repo-class — gh not installed (cannot detect repo visibility)"; return 0
  fi
  _json=$(${PREFLIGHT_GH_CMD:-gh repo view --json isPrivate,isInOrganization} 2>/dev/null) || _json=""
  if [ -z "$_json" ]; then
    echo "  skip repo-class — gh unavailable/unauthenticated/offline (run 'gh auth login')"; return 0
  fi
  _priv=$(printf '%s' "$_json" | jq -r '.isPrivate' 2>/dev/null || echo "")
  _org=$(printf '%s' "$_json"  | jq -r '.isInOrganization' 2>/dev/null || echo "")  # isInOrganization is gh's proxy for the gate's owner.type == 'Organization'
  if [ "$_priv" = "true" ] && [ "$_org" = "false" ]; then
    echo "  warn repo is user-owned PRIVATE — SLSA provenance gate will SKIP (make it public or move to an org for build attestation)"
    rec=1
  elif [ "$_priv" = "true" ] || [ "$_priv" = "false" ]; then
    echo "  ok   repo class supports the provenance gate (public or org-owned)"
  else
    echo "  skip repo-class — could not parse repo metadata"
  fi
}

check_workflows_valid() {  # surface workflow validity via the existing conformance check (reuse, never reimplement)
  _cmd="${ACTIONLINT_VALID_CMD:-}"
  if [ "$_cmd" = "__skip__" ]; then
    echo "  skip workflows — actionlint-valid.sh / actionlint not available"; return 0
  fi
  if [ -z "$_cmd" ]; then
    if [ ! -f conformance/actionlint-valid.sh ]; then
      echo "  skip workflows — conformance/actionlint-valid.sh not present (pruned?)"; return 0
    fi
    if [ -z "${ACTIONLINT_BIN:-}" ] && ! command -v actionlint >/dev/null 2>&1; then
      echo "  skip workflows — actionlint not installed (set ACTIONLINT_BIN or install actionlint)"; return 0
    fi
    _cmd="sh conformance/actionlint-valid.sh"
  fi
  if $_cmd >/dev/null 2>&1; then
    echo "  ok   workflows valid (actionlint via conformance/actionlint-valid.sh)"
  else
    echo "  warn an invalid GitHub Actions workflow — run 'sh conformance/actionlint-valid.sh' for details"
    rec=1
  fi
}

check_codeowners_placeholders() {  # standing re-check of @your-org placeholders (incept warns once; this re-warns any time)
  _paths="${CODEOWNERS_PATHS:-.github/CODEOWNERS .gitlab/CODEOWNERS}"
  _found=""
  _any=0
  for _co in $_paths; do
    [ -f "$_co" ] || continue
    _any=1
    if grep -q '@your-org' "$_co" 2>/dev/null; then _found="$_found $_co"; fi
  done
  [ "$_any" -eq 0 ] && return 0   # N/A — no CODEOWNERS yet (pre-inception): print nothing
  if [ -n "$_found" ]; then
    echo "  warn$_found still has @your-org/* placeholders — replace with real teams before enabling owner review"
    rec=1
  else
    echo "  ok   CODEOWNERS has no @your-org placeholders"
  fi
}

# SEAMS: are the test injection seams (PREFLIGHT_GIT_VERSION_CMD) live? Only an explicit FLAG turns them
# on — never the ambient environment. Default 0 = a real adopter run reports on the real machine.
STACK=""; SELFTEST=0; ALLOW_NESTED=0; SEAMS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --stack) [ $# -ge 2 ] || { echo "preflight: --stack requires a value" >&2; exit 2; }; STACK=$2; shift 2 ;;
    --selftest) SELFTEST=1; SEAMS=1; shift ;;
    # --selftest-e2e: internal. Runs the REAL body with the injection seams live, so --selftest can prove
    # the git-floor check is WIRED end-to-end (a defined-but-uncalled check is decorative) without an
    # ambient env var being able to do the same thing in an adopter's shell. Not in --help: it is a test
    # seam, not a user-facing option, and the flag IS the authorization.
    --selftest-e2e) SEAMS=1; shift ;;
    --allow-nested) ALLOW_NESTED=1; shift ;;
    -h|--help) echo "usage: preflight.sh [--stack <name>] [--selftest] [--allow-nested]"; exit 0 ;;
    *) echo "preflight: unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ "$SELFTEST" -eq 1 ]; then
  fail=0
  if command -v kit_definitely_absent_tool_xyz >/dev/null 2>&1; then
    echo "FAIL: sentinel tool unexpectedly exists"; fail=1
  else
    echo "PASS: absent tool detected as missing"
  fi
  if command -v sh >/dev/null 2>&1; then echo "PASS: present tool (sh) detected"; else echo "FAIL: sh not detected"; fail=1; fi
  if stack_tools __nope__ >/dev/null 2>&1; then echo "FAIL: unknown stack not handled"; fail=1; else echo "PASS: unknown stack handled gracefully"; fi
  if stack_tools python >/dev/null 2>&1; then echo "PASS: known stack mapped"; else echo "FAIL: known stack not mapped"; fail=1; fi
  miss=0; recommend kit_definitely_absent_tool_xyz "x" >/dev/null 2>&1
  if [ "$miss" -eq 0 ]; then echo "PASS: recommend warns without failing (miss untouched)"; else echo "FAIL: recommend set miss"; fail=1; fi

  # — S2: repo-class check (PREFLIGHT_GH_CMD seam) ————————————————————————————
  out=$(PREFLIGHT_GH_CMD='printf {"isPrivate":true,"isInOrganization":false}' check_repo_class 2>&1)
  case "$out" in *warn*PRIVATE*) echo "PASS: user-private repo warns (provenance skip)";; *) echo "FAIL: user-private repo did not warn ($out)"; fail=1;; esac

  out=$(PREFLIGHT_GH_CMD='printf {"isPrivate":false,"isInOrganization":false}' check_repo_class 2>&1)
  case "$out" in *ok*) echo "PASS: public repo ok, no warn";; *) echo "FAIL: public repo not ok ($out)"; fail=1;; esac

  out=$(PREFLIGHT_GH_CMD='printf {"isPrivate":true,"isInOrganization":true}' check_repo_class 2>&1)
  case "$out" in *ok*) echo "PASS: org-owned private ok (provenance runs via org)";; *) echo "FAIL: org repo not ok ($out)"; fail=1;; esac

  out=$(PREFLIGHT_GH_CMD='false' check_repo_class 2>&1)
  case "$out" in *skip*) echo "PASS: gh-failure degrades to skip";; *) echo "FAIL: gh-failure not skipped ($out)"; fail=1;; esac

  # WARN-only invariant: a warning must NOT set miss
  miss=0; PREFLIGHT_GH_CMD='printf {"isPrivate":true,"isInOrganization":false}' check_repo_class >/dev/null 2>&1
  if [ "$miss" -eq 0 ]; then echo "PASS: repo-class warn leaves miss untouched"; else echo "FAIL: repo-class warn set miss"; fail=1; fi

  # — S2: CODEOWNERS placeholder check ————————————————————————————————————————
  _t=$(mktemp -d)
  printf '* @your-org/team\n' > "$_t/CODEOWNERS"
  out=$(CODEOWNERS_PATHS="$_t/CODEOWNERS" check_codeowners_placeholders 2>&1)
  case "$out" in *warn*your-org*) echo "PASS: @your-org placeholder warns";; *) echo "FAIL: placeholder not warned ($out)"; fail=1;; esac
  printf '* @real-team\n' > "$_t/CODEOWNERS"
  out=$(CODEOWNERS_PATHS="$_t/CODEOWNERS" check_codeowners_placeholders 2>&1)
  case "$out" in *ok*) echo "PASS: clean CODEOWNERS ok";; *) echo "FAIL: clean CODEOWNERS not ok ($out)"; fail=1;; esac
  out=$(CODEOWNERS_PATHS="$_t/none" check_codeowners_placeholders 2>&1)
  if [ -z "$out" ]; then echo "PASS: absent CODEOWNERS is N/A (no line)"; else echo "FAIL: absent CODEOWNERS printed ($out)"; fail=1; fi
  miss=0; printf '* @your-org/team\n' > "$_t/CODEOWNERS"; CODEOWNERS_PATHS="$_t/CODEOWNERS" check_codeowners_placeholders >/dev/null 2>&1
  if [ "$miss" -eq 0 ]; then echo "PASS: codeowners warn leaves miss untouched"; else echo "FAIL: codeowners warn set miss"; fail=1; fi
  rm -rf "$_t"

  # — S2: workflow-validity check (delegates to actionlint-valid.sh) ——————————
  out=$(ACTIONLINT_VALID_CMD='true' check_workflows_valid 2>&1)
  case "$out" in *ok*workflows*) echo "PASS: valid workflows ok";; *) echo "FAIL: valid workflows not ok ($out)"; fail=1;; esac
  out=$(ACTIONLINT_VALID_CMD='false' check_workflows_valid 2>&1)
  case "$out" in *warn*workflow*) echo "PASS: invalid workflow warns (pointer to actionlint-valid)";; *) echo "FAIL: invalid workflow not warned ($out)"; fail=1;; esac
  out=$(ACTIONLINT_VALID_CMD='__skip__' check_workflows_valid 2>&1)
  case "$out" in *skip*) echo "PASS: unavailable check degrades to skip";; *) echo "FAIL: unavailable check not skipped ($out)"; fail=1;; esac
  miss=0; ACTIONLINT_VALID_CMD='false' check_workflows_valid >/dev/null 2>&1
  if [ "$miss" -eq 0 ]; then echo "PASS: workflow warn leaves miss untouched"; else echo "FAIL: workflow warn set miss"; fail=1; fi

  # — T2: git version floor + `git merge-tree --write-tree` capability ————————————————
  # The floor exists because kit-update prefers `git merge-tree --write-tree` (git >= 2.38, 2022).
  # Ubuntu 20.04 ships git 2.25. DETECT AND DEGRADE: warn (never hard-fail) and NAME the escape.

  # THE NUMERIC-COMPARE PROOF (the whole reason this task exists): as strings "2.9" > "2.38".
  # Numerically 2.9 < 2.38. A string-naive floor would wave 2.9 through and be decorative.
  if git_meets_floor 2 38 2>/dev/null; then echo "PASS: 2.38 meets the 2.38 floor (boundary, inclusive)"; else echo "FAIL: 2.38 rejected by its own floor"; fail=1; fi
  if git_meets_floor 2 9 2>/dev/null; then echo "FAIL: 2.9 accepted — STRING-NAIVE compare ('2.9' > '2.38' lexically)"; fail=1; else echo "PASS: 2.9 rejected (numeric compare: 9 < 38)"; fi
  if git_meets_floor 2 39 2>/dev/null; then echo "PASS: 2.39 meets the floor"; else echo "FAIL: 2.39 rejected"; fail=1; fi
  if git_meets_floor 1 99 2>/dev/null; then echo "FAIL: 1.99 accepted (major below floor)"; fail=1; else echo "PASS: 1.99 rejected (major 1 < 2)"; fi
  if git_meets_floor 3 0 2>/dev/null; then echo "PASS: 3.0 meets the floor (major above)"; else echo "FAIL: 3.0 rejected (major above floor)"; fail=1; fi

  # the parser: real-world `git --version` shapes -> "MAJOR MINOR"
  out=$(git_version_parts "git version 2.39.5 (Apple Git-154)" 2>&1) || out="<git_version_parts absent/errored>"
  case "$out" in "2 39") echo "PASS: parses 'git version 2.39.5 (Apple Git-154)' -> 2 39";; *) echo "FAIL: Apple git line parsed as '$out'"; fail=1;; esac
  out=$(git_version_parts "git version 2.25.1" 2>&1) || out="<absent>"
  case "$out" in "2 25") echo "PASS: parses 'git version 2.25.1' -> 2 25";; *) echo "FAIL: 2.25.1 parsed as '$out'"; fail=1;; esac
  out=$(git_version_parts "git version 2.9.5" 2>&1) || out="<absent>"
  case "$out" in "2 9") echo "PASS: parses 'git version 2.9.5' -> 2 9";; *) echo "FAIL: 2.9.5 parsed as '$out'"; fail=1;; esac
  out=$(git_version_parts "git version 2.41.0.windows.3" 2>&1) || out="<absent>"
  case "$out" in "2 41") echo "PASS: parses the Windows build string -> 2 41";; *) echo "FAIL: windows line parsed as '$out'"; fail=1;; esac
  if git_version_parts "git version banana" >/dev/null 2>&1; then echo "FAIL: unparseable version accepted"; fail=1; else echo "PASS: unparseable version rejected (rc 1)"; fi

  # the check: below the floor -> WARN naming the version AND the fallback (the escape)
  out=$(PREFLIGHT_GIT_VERSION_CMD='echo git version 2.25.1' check_git_capability 2>&1) || out="<check_git_capability absent/errored>"
  case "$out" in *warn*2.25*) echo "PASS: old git warns and names the version found";; *) echo "FAIL: old git did not warn with its version ($out)"; fail=1;; esac
  case "$out" in *fallback*) echo "PASS: old-git warning names the temporary-worktree fallback (the escape)";; *) echo "FAIL: warning does not name the fallback ($out)"; fail=1;; esac
  case "$out" in *non-mutating*) echo "PASS: old-git warning states the fallback is still non-mutating";; *) echo "FAIL: warning does not state non-mutating ($out)"; fail=1;; esac

  # 2.9 is the trap case end-to-end, not just in the comparator
  out=$(PREFLIGHT_GIT_VERSION_CMD='echo git version 2.9.5' check_git_capability 2>&1) || out="<absent>"
  case "$out" in *warn*2.9*fallback*) echo "PASS: git 2.9.5 warns (a string compare would have passed it)";; *) echo "FAIL: git 2.9.5 not warned ($out)"; fail=1;; esac

  # at/above the floor -> ok, no warning
  out=$(PREFLIGHT_GIT_VERSION_CMD='echo git version 2.38.0' check_git_capability 2>&1) || out="<absent>"
  case "$out" in *ok*2.38*) echo "PASS: git 2.38.0 ok (boundary)";; *) echo "FAIL: git 2.38.0 not ok ($out)"; fail=1;; esac
  out=$(PREFLIGHT_GIT_VERSION_CMD='echo git version 2.48.1' check_git_capability 2>&1) || out="<absent>"
  case "$out" in *ok*merge-tree*) echo "PASS: modern git ok and names merge-tree";; *) echo "FAIL: modern git not ok ($out)"; fail=1;; esac

  # degrade, never crash: unparseable / absent git -> skip
  out=$(PREFLIGHT_GIT_VERSION_CMD='echo git version banana' check_git_capability 2>&1) || out="<absent>"
  case "$out" in *skip*) echo "PASS: unparseable git version degrades to skip";; *) echo "FAIL: unparseable version not skipped ($out)"; fail=1;; esac
  out=$(PREFLIGHT_GIT_VERSION_CMD='false' check_git_capability 2>&1) || out="<absent>"
  case "$out" in *skip*) echo "PASS: unavailable git degrades to skip";; *) echo "FAIL: absent git not skipped ($out)"; fail=1;; esac

  # WARN-only invariant: the floor is advisory — it must NEVER set miss (i.e. never fail the run)
  miss=0; PREFLIGHT_GIT_VERSION_CMD='echo git version 2.25.1' check_git_capability >/dev/null 2>&1 || true
  if [ "$miss" -eq 0 ]; then echo "PASS: git-floor warn leaves miss untouched"; else echo "FAIL: git-floor warn set miss (hard-failed old git)"; fail=1; fi
  miss=0

  # NO AMBIENT SPOOF (flag-not-env): in a REAL run — no --selftest, no --selftest-e2e — an ambient
  # PREFLIGHT_GIT_VERSION_CMD must be IGNORED. The seam exists for the tests; if the environment alone
  # can redirect it, a stale/hostile export in an adopter's shell rewrites what preflight reports about
  # their machine. Advisory-only, so no privilege boundary is crossed — but it is the same flag-not-env
  # rule --date honors (an ambient INCEPT_DATE was rejected for exactly this reason), and a check that
  # can be told what to see is not a check.
  #
  # MARKER, NOT VERSION-STRING: the seam command TOUCHES a file, and we assert the file was not created.
  # Keying on the OUTPUT instead (`case "$spoof" in *"git 2.25"*)`) reads the HOST's git: a machine whose
  # real git is 2.25.x — Ubuntu 20.04, the exact platform this floor was written for — legitimately prints
  # `warn git 2.25 ...`, and the assertion would call its own honest report an attack. CI (git 2.4x) would
  # never see it. A false-RED generator is the same defect class as a vacuous green, inverted. So assert
  # the CLAIM ("did the seam command RUN?") rather than a proxy the environment is allowed to satisfy.
  _sd=$(mktemp -d); _marker="$_sd/ran"
  printf '#!/bin/sh\ntouch "%s"\necho git version 2.25.1\n' "$_marker" > "$_sd/fakegit"
  chmod +x "$_sd/fakegit"
  PREFLIGHT_GIT_VERSION_CMD="$_sd/fakegit" PREFLIGHT_GH_CMD='false' ACTIONLINT_VALID_CMD='__skip__' sh "$0" >/dev/null 2>&1 || true
  if [ -e "$_marker" ]; then
    echo "FAIL: an AMBIENT PREFLIGHT_GIT_VERSION_CMD was honored in a real run (env, not flag)"; fail=1
  else
    echo "PASS: a real run IGNORES an ambient PREFLIGHT_GIT_VERSION_CMD (the seam needs an explicit flag)"
  fi
  rm -rf "$_sd"

  # NO GLOB: the version line is word-SPLIT, never pathname-expanded. `for _w in $1` unquoted splits AND
  # globs; a '*' in the string would expand against the CWD, so a file named e.g. '9.9.9' sitting in the
  # working directory becomes the "version" — a floor that reads the filesystem instead of git. (Quoting
  # $1 is not the fix: it would collapse the line to one word and parse nothing. Disabling globbing is.)
  _gt=$(mktemp -d)
  : > "$_gt/9.9.9"
  out=$( cd "$_gt" && git_version_parts "git version * 2.25.1" 2>&1 ) || out="<absent>"
  case "$out" in
    "2 25") echo "PASS: a '*' in the version line does NOT glob against the cwd (2 25, not the filename)" ;;
    *) echo "FAIL: the version line was GLOB-expanded — parsed '$out' from the filesystem"; fail=1 ;;
  esac
  rm -rf "$_gt"

  # WIRED end-to-end: a REAL preflight run (not just the unit seam) must name the git version and,
  # below the floor, the fallback — and must not change the run's verdict. A defined-but-uncalled check
  # is decorative. `--selftest-e2e` runs the REAL body with the injection seams live (the flag IS the
  # authorization — see the no-ambient-spoof assert above).
  e2e_rc=0
  e2e=$(PREFLIGHT_GIT_VERSION_CMD='echo git version 2.25.1' PREFLIGHT_GH_CMD='false' ACTIONLINT_VALID_CMD='__skip__' sh "$0" --selftest-e2e 2>&1) || e2e_rc=$?
  case "$e2e" in *warn*2.25*fallback*) echo "PASS: real preflight run names the git version + the fallback";; *) echo "FAIL: real run did not surface the git floor (rc=$e2e_rc)"; fail=1;; esac
  # DIFFERENTIAL, not absolute: `[ "$e2e_rc" -eq 0 ]` would assert a whole preflight run exits 0, which
  # folds in the AMBIENT environment (the CP-4 non-root refusal, a missing jq) — it reddens for reasons
  # that have nothing to do with the git floor. A false-RED generator is the same defect class as a
  # vacuous green, inverted. The claim is "the floor is ADVISORY", so assert exactly that: an old git
  # does not CHANGE preflight's exit code, whatever that code is in this environment.
  new_rc=0
  PREFLIGHT_GIT_VERSION_CMD='echo git version 2.48.1' PREFLIGHT_GH_CMD='false' ACTIONLINT_VALID_CMD='__skip__' sh "$0" --selftest-e2e >/dev/null 2>&1 || new_rc=$?
  if [ "$e2e_rc" -eq "$new_rc" ]; then echo "PASS: the git floor does not change preflight's exit code (advisory, not blocking)"; else echo "FAIL: old git CHANGED the exit code (old=$e2e_rc modern=$new_rc)"; fail=1; fi

  [ "$fail" -eq 0 ] && { echo "OK: preflight selftest"; exit 0; } || { echo "FAIL: preflight selftest"; exit 1; }
fi

echo "Sparkwright — preflight"
echo "Universal prerequisites:"
need jq  "brew install jq | apt-get install jq | dnf install jq"
need git "git-scm.com/downloads"
need sh  "any POSIX shell"
check_git_capability

echo "Recommended (GitHub-based flows — skip on GitLab/ADO):"
recommend gh "GitHub CLI — needed for the branch-protection setup at Inception (cli.github.com)"
if command -v gh >/dev/null 2>&1; then
  # shellcheck disable=SC2034  # rec mirrors miss for recommended tools; warnings don't fail the run
  if gh auth status >/dev/null 2>&1; then echo "  ok   gh auth (logged in)"; else echo "  warn gh auth — run 'gh auth login' before the branch-protection step"; rec=1; fi
fi

if git_env_redirected; then
  echo "" >&2
  echo "ERROR: your git environment redirects git away from this directory." >&2
  [ -n "${GIT_DIR:-}" ]       && echo "  GIT_DIR=$GIT_DIR" >&2
  [ -n "${GIT_WORK_TREE:-}" ] && echo "  GIT_WORK_TREE=$GIT_WORK_TREE" >&2
  echo "  preflight would report on that repository instead of your product." >&2
  echo "  Nothing has been written. Clear the redirect and re-run:" >&2
  echo "    env -u GIT_DIR -u GIT_WORK_TREE sh scripts/preflight.sh ..." >&2
  exit 1
elif git_dir_outside "$PWD" && [ "${ALLOW_NESTED:-0}" -eq 0 ]; then
  _gcd_raw=$( git rev-parse --git-common-dir 2>/dev/null )
  _gcd_show=$( CDPATH='' cd "${_gcd_raw:-.}" 2>/dev/null && pwd -P )
  [ -n "$_gcd_show" ] || _gcd_show=$_gcd_raw
  echo "" >&2
  echo "ERROR: this directory's git dir lives outside it (nested dir, submodule, or linked worktree)." >&2
  echo "  git dir: $_gcd_show  — the pre-push hook would land in that shared/other repo." >&2
  echo "  If this is intentional, re-run with:  sh scripts/preflight.sh --allow-nested ..." >&2
  exit 1
fi

# CP-4: refuse before reporting on a repository we do not own. Nested in a foreign worktree,
# every line below would describe the PARENT's repo — a wrong answer stated confidently.
if ! owns_itself "$PWD" && [ "$ALLOW_NESTED" -eq 0 ]; then
  _parent=$(owning_repo_root "$PWD")
  echo "" >&2
  echo "ERROR: this directory is not the root of its own git repository." >&2
  echo "  cwd:      $(pwd -P)" >&2
  echo "  owned by: $_parent  (git toplevel)" >&2
  echo "" >&2
  echo "Everything preflight reports below — remote, repo class, CODEOWNERS, workflows — would" >&2
  echo "describe THAT repository, not your product. Run preflight from the root of its own repo." >&2
  echo "If this nesting is intentional (e.g. a monorepo package), re-run with --allow-nested." >&2
  exit 1
fi

if is_github_repo; then
  echo "Adopter environment (GitHub repo detected):"
  check_repo_class
  check_codeowners_placeholders
  check_workflows_valid
fi

if [ -n "$STACK" ]; then
  echo "Stack toolchain ($STACK):"
  if tools=$(stack_tools "$STACK"); then
    # Split "tool|hint" lines with IFS local to `read` (no global IFS mutation), fed via a
    # here-doc — a here-doc is a redirection, not a pipe, so the loop runs in THIS shell and
    # the `miss` accumulator propagates (a `| while` pipe would lose it in a subshell).
    while IFS='|' read -r t hint; do
      [ -n "$t" ] || continue
      need "$t" "$hint"
    done <<EOF
$tools
EOF
  else
    echo "  (no toolchain map for '$STACK' — see profiles/$STACK.md)"
  fi
fi

if [ "$rec" -gt 0 ]; then
  echo ""
  echo "$rec advisory warning(s) above — non-blocking (they do not affect this check's result)."
fi

if [ "$miss" -eq 0 ]; then
  echo "All prerequisites present."
  exit 0
else
  echo "Missing prerequisites above — install them, then re-run."
  exit 1
fi
