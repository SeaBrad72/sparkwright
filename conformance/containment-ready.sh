#!/bin/sh
# containment-ready.sh — conditional, three-state agent-containment posture check (Slice 11c).
#
# Closes what is reachable to exfiltrate AT THE SOURCE (A8 controls #2/#3/#4): a sandboxed/
# read-only FS, scoped short-lived tokens, and separate production credentials. The kit cannot
# make a host FS read-only or expire a token, so this does NOT enforce — it ships a reference
# (docs/operations/containment.md) and verifies the posture is DECLARED + ATTESTED-wired.
#
# Three sub-aspects, each keyed on a RUNBOOK line; OVERALL = WEAKEST aspect:
#   Sandbox FS:       read-only work-tree mounts (host secrets unreachable)
#   Scoped tokens:    OIDC->role, short TTL, least-privilege
#   Prod credentials: separate + break-glass (SoD)
#
# THREE-STATE (mirrors egress-policy.sh / branch-protection.sh):
#   exit 0 — PASS (every aspect declared+attested, or N/A) OR N/A (no integration/deploy surface)
#   exit 1 — FAIL (an applicable aspect is undeclared)
#   exit 2 — UNVERIFIED (an aspect declared but not attested) — NOT a pass.
# Escalation: under CI (CI env set) or --require, UNVERIFIED becomes exit 1.
#
# Per-aspect: DECLARED = the RUNBOOK line names a mechanism (and, for Sandbox FS only, an in-repo
# read-only-mount config also counts); ATTESTED = the line records `enforced: <ISO date>` (not the
# [date] placeholder). N/A = the line records `N/A — <reason>`.
#
# SCOPE — a green run proves the posture is DECLARED + ATTESTED, NOT that the FS is actually
# read-only, tokens actually expire, or prod creds are actually unreachable (Manual rows in
# containment-readiness.md). A green run is necessary, not sufficient.
#
# Usage:
#   sh conformance/containment-ready.sh [project-dir] [--require]   (default dir: .)
#   sh conformance/containment-ready.sh --selftest
set -eu

REQUIRE="${REQUIRE:-0}"
[ -n "${CI:-}" ] && REQUIRE=1
DIR=.
for a in "$@"; do
  case "$a" in
    --require)  REQUIRE=1 ;;
    --selftest) ;;  # dispatched below
    -*) echo "usage: containment-ready.sh [project-dir] [--require] | --selftest" >&2; exit 2 ;;
    *)  DIR="$a" ;;
  esac
done

# Integration/deploy surface? (Dockerfile or any GitHub workflow — CI implies tokens to scope.)
has_surface() {
  _d="$1"
  [ -f "$_d/Dockerfile" ] && return 0
  if [ -d "$_d/.github/workflows" ]; then
    for wf in "$_d"/.github/workflows/*.yml "$_d"/.github/workflows/*.yaml; do
      [ -f "$wf" ] && return 0
    done
  fi
  return 1
}

# In-repo read-only-mount config (compose/devcontainer)? Sandbox-FS extra declaration only.
# Heuristic: can only bump an aspect FAIL->UNVERIFIED (never to PASS — PASS needs the RUNBOOK
# attestation), so a loose match here is low-risk.
has_readonly_mount_config() {
  _d="$1"
  for f in "$_d"/compose.yaml "$_d"/compose.yml "$_d"/docker-compose.yaml "$_d"/docker-compose.yml \
           "$_d"/.devcontainer/devcontainer.json "$_d"/.devcontainer/compose.yaml; do
    [ -f "$f" ] || continue
    if grep -Eiq 'read_only:[[:space:]]*true|"readOnly"[[:space:]]*:[[:space:]]*true|,readonly|readonly,' "$f" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

# classify one aspect -> echoes PASS | UNVERIFIED | FAIL | NA
#   $1 RUNBOOK path · $2 line-key (lowercase, e.g. 'sandbox fs') · $3 extra-declared (1/0)
classify_aspect() {
  _rb="$1"; _key="$2"; _extra="$3"
  _present=0; _is_na=0; _attested=0
  # Anchor the key to the START of a (optionally bulleted) line so a substring heading like
  # 'Non-prod credentials:' does not satisfy 'prod credentials:', and a prose mention mid-line
  # does not count as a declaration. Keeps '- Sandbox FS:', '* Sandbox FS:', 'Sandbox FS:'.
  _pre="^[[:space:]]*[-*]?[[:space:]]*$_key:"
  if [ -f "$_rb" ]; then
    # N/A token-anchored ([^[:alnum:]] is -i-safe) so 'NAS'/'native' don't read as N/A
    if grep -Eiq "${_pre}[[:space:]]*n/?a([^[:alnum:]]|\$)" "$_rb"; then _is_na=1; fi
    if grep -Eiq "$_pre" "$_rb"; then _present=1; fi
    if grep -Eiq "$_pre.*enforced:[[:space:]]*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]" "$_rb"; then _attested=1; fi
  fi
  if [ "$_is_na" = "1" ]; then echo NA; return 0; fi
  if [ "$_present" = "0" ] && [ "$_extra" = "0" ]; then echo FAIL; return 0; fi
  if [ "$_attested" = "1" ]; then echo PASS; return 0; fi
  echo UNVERIFIED
}

check_dir() {
  dir="$1"

  if ! has_surface "$dir"; then
    echo "N/A: $dir has no integration/deploy surface (no Dockerfile / GitHub workflow) — no agent-reachable secrets or prod to contain"
    return 0
  fi

  rb="$dir/RUNBOOK.md"
  fs_extra=0
  if has_readonly_mount_config "$dir"; then fs_extra=1; fi

  s_fs=$(classify_aspect "$rb" "sandbox fs" "$fs_extra")
  s_tok=$(classify_aspect "$rb" "scoped tokens" 0)
  s_cred=$(classify_aspect "$rb" "prod credentials" 0)

  echo "  Sandbox FS:       $s_fs"
  echo "  Scoped tokens:    $s_tok"
  echo "  Prod credentials: $s_cred"

  # overall = weakest aspect: FAIL > UNVERIFIED > {PASS, NA}
  worst=PASS
  for s in "$s_fs" "$s_tok" "$s_cred"; do
    if [ "$s" = "FAIL" ]; then worst=FAIL; fi
  done
  if [ "$worst" != "FAIL" ]; then
    for s in "$s_fs" "$s_tok" "$s_cred"; do
      if [ "$s" = "UNVERIFIED" ]; then worst=UNVERIFIED; fi
    done
  fi

  case "$worst" in
    FAIL)
      echo "FAIL: $dir containment posture incomplete — an applicable aspect is undeclared. Declare all three (or N/A with reason) per docs/operations/containment.md"
      return 1 ;;
    UNVERIFIED)
      msg="$dir declares a containment aspect but does not ATTEST enforcement (need 'enforced: <date>' on each declared aspect line)"
      if [ "$REQUIRE" = "1" ]; then
        echo "FAIL: $msg — and attestation is required (CI/--require)."
        return 1
      fi
      echo "UNVERIFIED: $msg — attest enforcement in RUNBOOK. (NOT a pass.)"
      return 2 ;;
    PASS)
      echo "containment-ready: OK — Sandbox FS / Scoped tokens / Prod credentials all DECLARED + ATTESTED (or N/A). NOTE: does NOT verify the FS is actually read-only, tokens actually expire, or prod creds are actually unreachable (Manual rows in containment-readiness.md)."
      return 0 ;;
  esac
}

# mktemp fixtures; assert each outcome. Fixtures LEFT in place (no rm -rf; 7e guard).
selftest() {
  st_fail=0
  base=$(mktemp -d)

  rc_of() { ( check_dir "$1" ) >/dev/null 2>&1 && echo 0 || echo $?; }
  # Each fixture overrides REQUIRE in its OWN subshell so the global CI-derived REQUIRE=1
  # (the kit's CI runs --selftest!) never leaks in and turns an expected UNVERIFIED(2) into
  # FAIL(1). ';'-separated assignment (not VAR=val prefix) so it persists into the nested
  # check_dir subshell. Only the escalation fixture sets REQUIRE=1.
  expect() { # label dir want [require]
    _lbl="$1"; _dir="$2"; _want="$3"; _req="${4:-0}"
    _got=$( REQUIRE="$_req"; rc_of "$_dir" )
    if [ "$_got" = "$_want" ]; then echo "selftest PASS: $_lbl -> exit $_got"; else echo "selftest FAIL: $_lbl want $_want got $_got"; st_fail=1; fi
  }
  # the three dated attestation lines, reused across fixtures
  L_FS='- Sandbox FS: read-only work-tree mounts (compose read_only) — enforced: 2026-06-01'
  L_TOK='- Scoped tokens: OIDC->role, short TTL — enforced: 2026-06-01'
  L_CRED='- Prod credentials: separate + break-glass — enforced: 2026-06-01'

  # 1. no surface -> N/A (0)
  d="$base/na-nosurface"; mkdir -p "$d"; printf '# a CLI tool\n' > "$d/README.md"
  expect "no-surface -> N/A" "$d" 0

  # 2. surface, no containment section -> FAIL (1)
  d="$base/fail-bare"; mkdir -p "$d"; printf 'FROM scratch\n' > "$d/Dockerfile"
  printf '# RUNBOOK\n## Deploy\n- (no containment records)\n' > "$d/RUNBOOK.md"
  expect "surface, nothing declared -> FAIL" "$d" 1

  # 3. all three declared + dated -> PASS (0)
  d="$base/pass-all"; mkdir -p "$d"; printf 'FROM scratch\n' > "$d/Dockerfile"
  printf '# RUNBOOK\n## Deploy\n%s\n%s\n%s\n' "$L_FS" "$L_TOK" "$L_CRED" > "$d/RUNBOOK.md"
  expect "all three dated -> PASS" "$d" 0

  # 4. one aspect [date] placeholder -> UNVERIFIED (2)
  d="$base/unv-placeholder"; mkdir -p "$d"; printf 'FROM scratch\n' > "$d/Dockerfile"
  printf '# RUNBOOK\n## Deploy\n- Sandbox FS: read-only mounts — enforced: [date]\n%s\n%s\n' "$L_TOK" "$L_CRED" > "$d/RUNBOOK.md"
  expect "one placeholder -> UNVERIFIED" "$d" 2

  # 5. Sandbox FS declared ONLY by read-only compose config (no FS RUNBOOK line),
  #    tokens+creds dated -> FS is declared-but-unattested -> UNVERIFIED (2). Isolates the config path.
  d="$base/unv-configonly"; mkdir -p "$d"; printf 'FROM scratch\n' > "$d/Dockerfile"
  printf 'services:\n  agent:\n    read_only: true\n' > "$d/compose.yaml"
  printf '# RUNBOOK\n## Deploy\n%s\n%s\n' "$L_TOK" "$L_CRED" > "$d/RUNBOOK.md"
  expect "config-only FS (unattested) -> UNVERIFIED" "$d" 2

  # 6. read-only config + dated FS line + tokens/creds dated -> PASS (0) (config + attestation)
  d="$base/pass-config"; mkdir -p "$d"; printf 'FROM scratch\n' > "$d/Dockerfile"
  printf 'services:\n  agent:\n    read_only: true\n' > "$d/compose.yaml"
  printf '# RUNBOOK\n## Deploy\n%s\n%s\n%s\n' "$L_FS" "$L_TOK" "$L_CRED" > "$d/RUNBOOK.md"
  expect "config + dated -> PASS" "$d" 0

  # 7. prod creds N/A + FS/tokens dated -> PASS (0) (per-aspect N/A)
  d="$base/pass-na-cred"; mkdir -p "$d"; printf 'FROM scratch\n' > "$d/Dockerfile"
  printf '# RUNBOOK\n## Deploy\n%s\n%s\n- Prod credentials: N/A — no production environment\n' "$L_FS" "$L_TOK" > "$d/RUNBOOK.md"
  expect "prod-creds N/A -> PASS" "$d" 0

  # 7b. a substring heading ('Non-prod credentials:') must NOT satisfy 'Prod credentials:'
  #     (regression: keys are anchored to line/list-item start). FS/tokens dated, no real
  #     Prod credentials line -> creds aspect FAIL -> overall FAIL (1).
  d="$base/fail-substring-key"; mkdir -p "$d"; printf 'FROM scratch\n' > "$d/Dockerfile"
  printf '# RUNBOOK\n## Deploy\n%s\n%s\n- Non-prod credentials: shared dev key — enforced: 2026-06-01\n' "$L_FS" "$L_TOK" > "$d/RUNBOOK.md"
  expect "substring 'Non-prod credentials' not a match -> FAIL" "$d" 1

  # 8. only two of three lines present (creds absent, no config) -> FAIL (1)
  d="$base/fail-missing-one"; mkdir -p "$d"; printf 'FROM scratch\n' > "$d/Dockerfile"
  printf '# RUNBOOK\n## Deploy\n%s\n%s\n' "$L_FS" "$L_TOK" > "$d/RUNBOOK.md"
  expect "two-of-three -> FAIL (weakest absent)" "$d" 1

  # 9. escalation: the placeholder fixture under CI/--require -> FAIL (1)
  expect "declared-not-attested + require -> FAIL" "$base/unv-placeholder" 1 1

  if [ "$st_fail" -ne 0 ]; then echo "containment-ready --selftest: FAIL" >&2; return 1; fi
  echo "containment-ready --selftest: OK (na/bare-fail/pass-all/placeholder-unv/config-only-unv/config-pass/na-cred-pass/missing-one-fail/escalation all behaved; fixtures left in $base)"
  return 0
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  *)          check_dir "$DIR"; exit $? ;;
esac
