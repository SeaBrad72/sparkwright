#!/bin/sh
# actionlint-valid.sh — validate every shipped GitHub Actions workflow as a real GHA *document*,
# not merely as a set of npm steps. Catches the class where a workflow is structurally INVALID and
# fails at startup on a real push with no jobs scheduled — e.g. calling hashFiles() in a job-level
# `if:` (hashFiles is only available in STEP contexts). That defect shipped in 7 profile pipelines
# and only surfaced the first time a workflow actually ran on GitHub Actions (the dogfood root cause).
#
# Scope: document VALIDITY only. `-shellcheck=` disables actionlint's shell-style linting (the kit
# already owns shell quality via conformance/shellcheck.sh) — so this check stays focused and needs
# no shellcheck on the runner. Scans every .github/workflows/*.yml|*.yaml (the kit's own) plus every
# profiles/*/ci.yml (the GitHub reference pipelines). NOT the GitLab profile (actionlint is GitHub-
# Actions-only). Tool acquisition mirrors the H4b checksum-pinned pattern (download + sha256 verify,
# never curl|sh); honors $ACTIONLINT_BIN (test seam / pre-installed) and an on-PATH actionlint.
#   sh conformance/actionlint-valid.sh [--selftest]
#   ACTIONLINT_ROOT=<dir>  scan a tree other than .   ·  ACTIONLINT_BIN=<path>  use a specific binary
# Exit: 0 = all workflows are valid GHA documents · 1 = an invalid workflow · 2 = usage/setup error.
# POSIX sh; dash-clean.
set -eu

AL_VER=1.7.7

# Pinned per-platform asset + sha256 (from the published actionlint_<ver>_checksums.txt). Fail-closed.
al_asset_sha() {
  _p="$(uname -s)/$(uname -m)"
  case "$_p" in
    Linux/x86_64)              echo "actionlint_${AL_VER}_linux_amd64.tar.gz 023070a287cd8cccd71515fedc843f1985bf96c436b7effaecce67290e7e0757" ;;
    Linux/aarch64|Linux/arm64) echo "actionlint_${AL_VER}_linux_arm64.tar.gz 401942f9c24ed71e4fe71b76c7d638f66d8633575c4016efd2977ce7c28317d0" ;;
    Darwin/arm64)              echo "actionlint_${AL_VER}_darwin_arm64.tar.gz 2693315b9093aeacb4ebd91a993fea54fc215057bf0da2659056b4bc033873db" ;;
    Darwin/x86_64)             echo "actionlint_${AL_VER}_darwin_amd64.tar.gz 28e5de5a05fc558474f638323d736d822fff183d2d492f0aecb2b73cc44584f5" ;;
    *)                         echo "" ;;
  esac
}

# verify_sha <file> <sha256>: 0 = match · 1 = mismatch · 2 = no checksum tool available.
verify_sha() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s  %s\n' "$2" "$1" | sha256sum -c - >/dev/null 2>&1
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s  %s\n' "$2" "$1" | shasum -a 256 -c - >/dev/null 2>&1
  else
    return 2
  fi
}

# resolve_actionlint: echo a usable actionlint path on stdout (diagnostics to stderr). Order:
# $ACTIONLINT_BIN → on-PATH actionlint → checksum-pinned download into a per-version/platform cache.
resolve_actionlint() {
  if [ -n "${ACTIONLINT_BIN:-}" ]; then printf '%s' "$ACTIONLINT_BIN"; return 0; fi
  if command -v actionlint >/dev/null 2>&1; then command -v actionlint; return 0; fi
  # shellcheck disable=SC2046  # al_asset_sha intentionally echoes two space-split fields (asset + sha)
  set -- $(al_asset_sha)
  _asset="${1:-}"; _sha="${2:-}"
  if [ -z "$_asset" ]; then
    echo "actionlint-valid: unsupported platform $(uname -s)/$(uname -m) — set ACTIONLINT_BIN to a v$AL_VER actionlint" >&2; return 2
  fi
  _cache="${TMPDIR:-/tmp}/sparkwright-actionlint/$AL_VER/$(uname -s)-$(uname -m)"
  _bin="$_cache/actionlint"
  if [ -x "$_bin" ]; then printf '%s' "$_bin"; return 0; fi
  mkdir -p "$_cache"
  _tgz="$_cache/$_asset"
  _url="https://github.com/rhysd/actionlint/releases/download/v$AL_VER/$_asset"
  if ! curl -sSfL "$_url" -o "$_tgz"; then echo "actionlint-valid: download failed: $_url" >&2; return 2; fi
  _v=0; verify_sha "$_tgz" "$_sha" || _v=$?
  if [ "$_v" -eq 2 ]; then echo "actionlint-valid: no sha256sum/shasum on PATH — cannot verify the download" >&2; return 2; fi
  if [ "$_v" -ne 0 ]; then echo "actionlint-valid: CHECKSUM MISMATCH for $_asset — refusing to run" >&2; return 2; fi
  if ! tar -xzf "$_tgz" -C "$_cache" actionlint; then echo "actionlint-valid: extract failed for $_asset" >&2; return 2; fi
  [ -x "$_bin" ] || chmod +x "$_bin" 2>/dev/null || true
  printf '%s' "$_bin"
}

if [ "${1:-}" = "--selftest" ]; then
  _b=$(resolve_actionlint) || { echo "FAIL: selftest could not acquire actionlint"; exit 1; }
  _d=$(mktemp -d); mkdir -p "$_d/.github/workflows"
  # bad fixture: hashFiles() in a JOB-level if (the exact G1a defect class) → must be rejected.
  cat > "$_d/bad.yml" <<'YML'
name: bad
on: push
jobs:
  a:
    if: github.ref == 'refs/heads/main' && hashFiles('Dockerfile') != ''
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
YML
  # good fixture: same gate expressed legally (step-context hashFiles) → must pass.
  cat > "$_d/good.yml" <<'YML'
name: good
on: push
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - if: ${{ hashFiles('Dockerfile') != '' }}
        run: echo hi
YML
  _sf=0
  if "$_b" -no-color -shellcheck= "$_d/bad.yml" >/dev/null 2>&1; then echo "FAIL: selftest — invalid (hashFiles-in-job-if) workflow NOT caught"; _sf=1; else echo "PASS: selftest — invalid workflow caught"; fi
  if "$_b" -no-color -shellcheck= "$_d/good.yml" >/dev/null 2>&1; then echo "PASS: selftest — valid workflow passes"; else echo "FAIL: selftest — valid workflow wrongly failed"; _sf=1; fi
  [ "$_sf" -eq 0 ] && { echo "OK: actionlint-valid selftest"; exit 0; } || { echo "FAIL: actionlint-valid selftest"; exit 1; }
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: actionlint-valid.sh [--selftest]" >&2; exit 2 ;;
esac

ROOT="${ACTIONLINT_ROOT:-.}"
BIN=$(resolve_actionlint) || exit 2

targets=""
for w in "$ROOT"/.github/workflows/*.yml "$ROOT"/.github/workflows/*.yaml; do
  [ -f "$w" ] && targets="$targets $w"
done
for p in "$ROOT"/profiles/*/ci.yml; do
  [ -f "$p" ] && targets="$targets $p"
done
if [ -z "$targets" ]; then echo "actionlint-valid: no workflows found under $ROOT" >&2; exit 2; fi

echo "actionlint-valid: validating shipped GHA documents (actionlint v$AL_VER, document-validity only)"
fail=0
for t in $targets; do
  if "$BIN" -no-color -shellcheck= "$t"; then
    echo "PASS: $t"
  else
    echo "FAIL: $t is not a valid GitHub Actions document"; fail=1
  fi
done
if [ "$fail" -eq 0 ]; then
  echo "OK: every shipped workflow is a valid GHA document"
  exit 0
else
  echo "FAIL: an invalid workflow document (see above) — it would fail at startup on a real push"
  exit 1
fi
