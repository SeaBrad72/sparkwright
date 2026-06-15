#!/bin/sh
# preflight.sh — prerequisite check for Sparkwright (the agentic SDLC kit). Fails fast with
# install hints so a missing tool surfaces HERE, not as a cryptic guard/conformance
# failure later (jq is hard-required by the guard + conformance). Universal check
# always; optional per-stack toolchain via --stack.
#   sh scripts/preflight.sh [--stack <name>] [--selftest]
# Exit: 0 = all present · 1 = a required tool missing · 2 = bad usage.
# POSIX sh; dash-clean. New stack? add a row to stack_tools() (unknown degrades gracefully).
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

STACK=""; SELFTEST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --stack) [ $# -ge 2 ] || { echo "preflight: --stack requires a value" >&2; exit 2; }; STACK=$2; shift 2 ;;
    --selftest) SELFTEST=1; shift ;;
    -h|--help) echo "usage: preflight.sh [--stack <name>] [--selftest]"; exit 0 ;;
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

if [ "$miss" -eq 0 ]; then
  echo "All prerequisites present."
  exit 0
else
  echo "Missing prerequisites above — install them, then re-run."
  exit 1
fi
