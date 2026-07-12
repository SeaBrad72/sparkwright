#!/bin/sh
# token-scope.sh — static OIDC-discipline gate over the shipped workflows (E4a').
#
# Two properties per workflow file:
#   1. The TOP-LEVEL (column-0) `permissions:` block must NOT grant `id-token: write` or `write-all`.
#      id-token:write is least-privilege only when scoped to the JOB that needs it (the reference's
#      provenance / image-provenance jobs); a workflow-level grant lets every job mint OIDC tokens.
#   2. NO long-lived cloud credentials (a curated list) — the OIDC-not-static-keys principle.
#
# Mirrors provenance-precondition.sh. STATIC, no docker. SCOPE: structural on shipped YAML, NOT a
# behavioural proof of the adopter's cloud IAM (that stays platform-owned + RUNBOOK-attested in
# containment-ready.sh). A green run is necessary, not sufficient.
#   sh conformance/token-scope.sh [--selftest]
# Exit: 0 = all scanned files clean (or N/A: no workflow files) · 1 = a violation · 2 = setup error.
# POSIX sh; dash-clean.
set -eu

ROOT="${TOKEN_SCOPE_ROOT:-.}"
SECRETS='AWS_SECRET_ACCESS_KEY|AWS_ACCESS_KEY_ID|AZURE_CLIENT_SECRET|GCP_SA_KEY|GOOGLE_APPLICATION_CREDENTIALS'

# check_file <workflow.yml> -> 0 clean, 1 violation (prints each finding)
check_file() {
  f=$1; rc=0

  # Property 2: long-lived cloud credentials anywhere in the file (comments excluded).
  if sed 's/#.*//' "$f" | grep -Eq "$SECRETS"; then
    echo "FAIL: $f references a long-lived cloud credential (use OIDC federation, not static keys):"
    sed 's/#.*//' "$f" | grep -nE "$SECRETS" | sed 's/^/      /'
    rc=1
  fi

  # Property 1: walk the file; the top-level permissions block is the col-0 `permissions:` line plus
  # the following INDENTED lines, until the next col-0 key. Job-level (indented) permissions blocks
  # are never entered. Inline forms on the col-0 line are caught directly.
  in_block=0
  while IFS= read -r line; do
    case "$line" in
      "permissions:"*)
        in_block=1
        case "$line" in *write-all*) echo "FAIL: $f grants workflow-level 'permissions: write-all' (scope id-token per-job)"; rc=1 ;; esac
        case "$line" in *id-token:*write*) echo "FAIL: $f grants workflow-level id-token:write inline (scope it to the job that needs it)"; rc=1 ;; esac
        continue
        ;;
      "") continue ;;                 # blank line does NOT end a YAML block — keep state
      "#"*) continue ;;               # col-0 comment does NOT end a block — keep state
      " "*|"	"*) : ;;                 # indented (space OR literal-tab) — inside the block; keep state, fall to grant-check
      *) in_block=0 ;;                # a real col-0 key ends the top-level block
    esac
    if [ "$in_block" = "1" ]; then
      case "$line" in
        *id-token:*write*) echo "FAIL: $f grants workflow-level id-token:write in the top-level permissions block (scope it per-job)"; rc=1 ;;
        *write-all*)       echo "FAIL: $f grants workflow-level write-all in the top-level permissions block"; rc=1 ;;
      esac
    fi
  done < "$f"

  [ "$rc" -eq 0 ] && echo "PASS: $f"
  return "$rc"
}

if [ "${1:-}" = "--selftest" ]; then
  d=$(mktemp -d); sf=0
  # clean: top-level contents:read, a JOB-scoped id-token, no static keys -> PASS
  printf 'permissions:\n  contents: read\non: push\njobs:\n  prov:\n    permissions:\n      contents: read\n      id-token: write\n    steps:\n      - run: echo hi\n' > "$d/clean.yml"
  if check_file "$d/clean.yml" >/dev/null 2>&1; then echo "selftest PASS: clean (job-scoped id-token) -> PASS"; else echo "selftest FAIL: clean wrongly failed"; sf=1; fi
  # top-level id-token:write -> FAIL
  printf 'permissions:\n  contents: read\n  id-token: write\non: push\njobs:\n  x:\n    steps:\n      - run: echo hi\n' > "$d/toplevel.yml"
  if check_file "$d/toplevel.yml" >/dev/null 2>&1; then echo "selftest FAIL: top-level id-token NOT caught"; sf=1; else echo "selftest PASS: top-level id-token -> FAIL"; fi
  # top-level write-all -> FAIL
  printf 'permissions: write-all\non: push\njobs:\n  x:\n    steps:\n      - run: echo hi\n' > "$d/writeall.yml"
  if check_file "$d/writeall.yml" >/dev/null 2>&1; then echo "selftest FAIL: write-all NOT caught"; sf=1; else echo "selftest PASS: write-all -> FAIL"; fi
  # static cloud secret -> FAIL
  printf 'on: push\njobs:\n  x:\n    steps:\n      - run: deploy\n        env:\n          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}\n' > "$d/secret.yml"
  if check_file "$d/secret.yml" >/dev/null 2>&1; then echo "selftest FAIL: static cloud secret NOT caught"; sf=1; else echo "selftest PASS: static cloud secret -> FAIL"; fi
  # OIDC role ARN as a secret is allowed (not a long-lived credential) -> PASS
  printf 'permissions:\n  contents: read\non: push\njobs:\n  x:\n    permissions:\n      id-token: write\n    steps:\n      - uses: aws-actions/configure-aws-credentials@v4\n        with:\n          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}\n' > "$d/roleok.yml"
  if check_file "$d/roleok.yml" >/dev/null 2>&1; then echo "selftest PASS: OIDC role ARN allowed -> PASS"; else echo "selftest FAIL: role ARN wrongly failed"; sf=1; fi
  # blank-line-in-block: blank line inside top-level permissions block must NOT end the block -> FAIL
  printf 'permissions:\n  contents: read\n\n  id-token: write\non: push\njobs:\n  x:\n    steps:\n      - run: echo\n' > "$d/blankline.yml"
  if check_file "$d/blankline.yml" >/dev/null 2>&1; then echo "selftest FAIL: blank-line-in-block evasion NOT caught"; sf=1; else echo "selftest PASS: blank-line-in-block -> FAIL"; fi
  # tab-indent: tab-indented id-token:write inside top-level block -> FAIL
  printf 'permissions:\n\tid-token: write\non: push\njobs:\n  x:\n    steps:\n      - run: echo\n' > "$d/tabindent.yml"
  if check_file "$d/tabindent.yml" >/dev/null 2>&1; then echo "selftest FAIL: tab-indent evasion NOT caught"; sf=1; else echo "selftest PASS: tab-indent -> FAIL"; fi
  # col0-comment-then-grant: col-0 comment inside top-level block must NOT end the block -> FAIL
  printf 'permissions:\n  contents: read\n# note\n  id-token: write\non: push\njobs:\n  x:\n    steps:\n      - run: echo\n' > "$d/col0comment.yml"
  if check_file "$d/col0comment.yml" >/dev/null 2>&1; then echo "selftest FAIL: col0-comment-then-grant evasion NOT caught"; sf=1; else echo "selftest PASS: col0-comment-then-grant -> FAIL"; fi
  # comment-only-secret: comment mentioning a secret name must NOT trigger Property 2 -> PASS
  printf 'on: push\njobs:\n  x:\n    steps:\n      - run: echo  # never hardcode AWS_SECRET_ACCESS_KEY here\n' > "$d/commentonly.yml"
  if check_file "$d/commentonly.yml" >/dev/null 2>&1; then echo "selftest PASS: comment-only-secret -> PASS"; else echo "selftest FAIL: comment-only-secret wrongly failed"; sf=1; fi
  [ "$sf" -eq 0 ] && { echo "OK: token-scope selftest"; exit 0; } || { echo "FAIL: token-scope selftest"; exit 1; }
fi

case "${1:-}" in "") : ;; *) echo "usage: token-scope.sh [--selftest]" >&2; exit 2 ;; esac

fail=0; found=0
for f in "$ROOT"/profiles/*/ci.yml "$ROOT"/.github/workflows/*.yml "$ROOT"/.github/workflows/*.yaml; do
  [ -f "$f" ] || continue
  found=1
  check_file "$f" || fail=1
done
[ "$found" -eq 1 ] || { echo "token-scope: N/A — no workflow files under $ROOT"; exit 0; }
if [ "$fail" -eq 0 ]; then echo "OK: every scanned workflow scopes id-token per-job + ships no AWS/Azure/GCP static keys (curated list)"; exit 0; fi
echo "FAIL: a workflow over-grants OIDC tokens or ships static cloud credentials (see above)"; exit 1

