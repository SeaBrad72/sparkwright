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
# Honest ceiling: this proves OWNERSHIP. It does NOT cover GIT_DIR / GIT_WORK_TREE redirection,
# submodules, or `git worktree add` trees. See CP-11.
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

STACK=""; SELFTEST=0; ALLOW_NESTED=0
while [ $# -gt 0 ]; do
  case "$1" in
    --stack) [ $# -ge 2 ] || { echo "preflight: --stack requires a value" >&2; exit 2; }; STACK=$2; shift 2 ;;
    --selftest) SELFTEST=1; shift ;;
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

  [ "$fail" -eq 0 ] && { echo "OK: preflight selftest"; exit 0; } || { echo "FAIL: preflight selftest"; exit 1; }
fi

echo "Sparkwright — preflight"
echo "Universal prerequisites:"
need jq  "brew install jq | apt-get install jq | dnf install jq"
need git "git-scm.com/downloads"
need sh  "any POSIX shell"

echo "Recommended (GitHub-based flows — skip on GitLab/ADO):"
recommend gh "GitHub CLI — needed for the branch-protection setup at Inception (cli.github.com)"
if command -v gh >/dev/null 2>&1; then
  # shellcheck disable=SC2034  # rec mirrors miss for recommended tools; warnings don't fail the run
  if gh auth status >/dev/null 2>&1; then echo "  ok   gh auth (logged in)"; else echo "  warn gh auth — run 'gh auth login' before the branch-protection step"; rec=1; fi
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
