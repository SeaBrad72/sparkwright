#!/bin/sh
# egress-policy.sh — conditional, three-state default-deny-egress wiring check (Slice 11b).
#
# The honest W2 close. Interpreter/DNS/build-tool exfil has NO reliable command signature
# (A8 Part 2), so the kit does NOT gate egress in-process. Instead it ships a default-deny
# network-egress REFERENCE (docs/operations/egress-control.md) and this check verifies the
# PLATFORM control is DECLARED and ATTESTED-wired — it never inspects or blocks traffic.
#
# THREE-STATE (mirrors branch-protection.sh):
#   exit 0 — PASS (declared + attested enforced) OR N/A (no network surface / RUNBOOK N/A)
#   exit 1 — FAIL (networked project declares NO egress control)
#   exit 2 — UNVERIFIED (declared but not attested enforced) — NOT a pass.
# Escalation: under CI (CI env set) or --require, UNVERIFIED (declared-not-attested) becomes
# exit 1 — in a gate the control must be attested, not merely declared.
#
# DECLARED  = an in-repo egress manifest (a YAML with `kind: NetworkPolicy` + `Egress`) in a
#             conventional location, OR a RUNBOOK "Network egress:" line naming a mechanism
#             (NetworkPolicy / cloud egress firewall / forward proxy).
# ATTESTED  = the RUNBOOK "Network egress:" line records `enforced: <ISO date>` (not the
#             [date] placeholder).
#
# SCOPE — a green run proves egress is DECLARED + ATTESTED, NOT that traffic is actually
# blocked (that is a Manual row in egress-readiness.md — platform/operator evidence). A
# committed NetworkPolicy proves intent, not enforcement; the RUNBOOK attestation is the
# authoritative "wired" signal. A green run is necessary, not sufficient.
#
# Usage:
#   sh conformance/egress-policy.sh [project-dir] [--require]   (default dir: .)
#   sh conformance/egress-policy.sh --selftest
#
# Run at the deploy/security gate (DEVELOPMENT-PROCESS.md §7); also self-tested in kit CI.
set -eu

REQUIRE="${REQUIRE:-0}"
[ -n "${CI:-}" ] && REQUIRE=1
DIR=.
for a in "$@"; do
  case "$a" in
    --require)  REQUIRE=1 ;;
    --selftest) ;;  # dispatched below
    -*) echo "usage: egress-policy.sh [project-dir] [--require] | --selftest" >&2; exit 2 ;;
    *)  DIR="$a" ;;
  esac
done

# Does $1 (a workflow file) indicate a deploy surface? (Same signals as resilience-ready.sh.)
wf_is_deploy() {
  _wf="$1"
  if grep -Eq '^[[:space:]]*environment:' "$_wf"; then return 0; fi
  if grep -Eq '^[[:space:]]+deploy[A-Za-z0-9_-]*:[[:space:]]*$' "$_wf"; then return 0; fi
  return 1
}

# In-repo egress manifest in a conventional location? (NetworkPolicy declaring Egress.)
# Bounded glob (not a full-tree find) — manifests elsewhere rely on the RUNBOOK attestation,
# which is the authoritative signal anyway.
has_egress_manifest() {
  _d="$1"
  for f in "$_d"/*.yaml "$_d"/*.yml \
           "$_d"/k8s/*.yaml "$_d"/k8s/*.yml \
           "$_d"/deploy/*.yaml "$_d"/deploy/*.yml \
           "$_d"/manifests/*.yaml "$_d"/manifests/*.yml; do
    [ -f "$f" ] || continue
    # require Egress as an actual policyTypes ENTRY (inline `[... Egress]` or a `- Egress`
    # list item), not a stray mention in a comment — so an Ingress-only NetworkPolicy that
    # merely says "Egress" in prose does not falsely satisfy `declared`.
    if grep -qiE 'kind:[[:space:]]*NetworkPolicy' "$f" 2>/dev/null \
       && grep -qE '(policyTypes:.*Egress|^[[:space:]]*-[[:space:]]*Egress[[:space:]]*$)' "$f" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

check_dir() {
  dir="$1"

  # 1. deploy/network surface? (no surface -> N/A skip-pass)
  deployable=0
  if [ -f "$dir/Dockerfile" ]; then deployable=1; fi
  if [ "$deployable" -eq 0 ] && [ -d "$dir/.github/workflows" ]; then
    for wf in "$dir"/.github/workflows/*.yml "$dir"/.github/workflows/*.yaml; do
      [ -f "$wf" ] || continue
      if wf_is_deploy "$wf"; then deployable=1; break; fi
    done
  fi
  if [ "$deployable" -eq 0 ]; then
    echo "N/A: $dir has no deploy/network surface (no Dockerfile / deploy workflow) — nothing to egress-gate"
    return 0
  fi

  rb="$dir/RUNBOOK.md"

  # 2. explicit N/A escape (a deployable with genuinely no outbound network).
  # Anchor N/A to a token boundary ([^[:alnum:]] is -i-safe, unlike [^a-z]) so a mechanism
  # that merely STARTS with "na" (NAT gateway, namespace-scoped policy, native mesh) is NOT
  # mis-read as N/A and short-circuited to a false green.
  if [ -f "$rb" ] && grep -Eiq 'network egress:[[:space:]]*n/?a([^[:alnum:]]|$)' "$rb"; then
    echo "N/A: $dir RUNBOOK records no outbound network (Network egress: N/A)"
    return 0
  fi

  # 3. declared? (in-repo manifest OR a RUNBOOK-named mechanism)
  declared=0
  if has_egress_manifest "$dir"; then declared=1; fi
  if [ -f "$rb" ] && grep -Eiq 'network egress:.*(networkpolicy|egress firewall|forward proxy|proxy)' "$rb"; then declared=1; fi

  if [ "$declared" -eq 0 ]; then
    echo "FAIL: $dir is networked but declares no default-deny egress control (no NetworkPolicy manifest, no RUNBOOK 'Network egress:' mechanism) — see docs/operations/egress-control.md"
    return 1
  fi

  # 4. attested-wired? (RUNBOOK 'Network egress: ... enforced: <ISO date>', not the placeholder)
  if [ -f "$rb" ] && grep -Eiq 'network egress:.*enforced:[[:space:]]*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' "$rb"; then
    echo "egress-policy: OK — default-deny egress is DECLARED and ATTESTED enforced. NOTE: this does NOT verify traffic is actually blocked (Manual row in egress-readiness.md — platform/operator evidence)."
    return 0
  fi

  # 5. declared but not attested -> UNVERIFIED (escalates to FAIL under CI/--require)
  msg="$dir declares an egress control but does not ATTEST enforcement in RUNBOOK (need 'Network egress: default-deny via <mechanism> — enforced: <date>')"
  if [ "$REQUIRE" = "1" ]; then
    echo "FAIL: $msg — and attestation is required (CI/--require)."
    return 1
  fi
  echo "UNVERIFIED: $msg — declare it in docs/operations/egress-control.md terms and attest enforcement. (NOT a pass.)"
  return 2
}

# mktemp fixtures; assert each outcome. Fixtures LEFT in place (no rm -rf; 7e guard).
selftest() {
  st_fail=0
  base=$(mktemp -d)

  # helper: run check_dir in a subshell, capture exact exit code (1 vs 2 matter)
  rc_of() { ( check_dir "$1" ) >/dev/null 2>&1 && echo 0 || echo $?; }
  # Each fixture overrides REQUIRE in its OWN subshell so the global CI-derived REQUIRE=1
  # (the kit's CI runs --selftest!) never leaks in and turns an expected UNVERIFIED(2) into
  # FAIL(1). Use the ';'-separated assignment (not the VAR=val prefix form) so REQUIRE
  # persists into the nested check_dir subshell. Only fixture 8 sets REQUIRE=1 (escalation).
  expect() { # label dir want [require]
    _lbl="$1"; _dir="$2"; _want="$3"; _req="${4:-0}"
    _got=$( REQUIRE="$_req"; rc_of "$_dir" )
    if [ "$_got" = "$_want" ]; then echo "selftest PASS: $_lbl -> exit $_got"; else echo "selftest FAIL: $_lbl want $_want got $_got"; st_fail=1; fi
  }

  # 1. no surface -> N/A (0)
  d="$base/na-nosurface"; mkdir -p "$d"; printf '# a CLI tool\n' > "$d/README.md"
  expect "no-surface -> N/A" "$d" 0

  # 2. deployable + RUNBOOK explicit N/A -> N/A (0)
  d="$base/na-explicit"; mkdir -p "$d"; printf 'FROM scratch\n' > "$d/Dockerfile"
  printf '# RUNBOOK\n## Deploy\n- Network egress: N/A — no outbound network\n' > "$d/RUNBOOK.md"
  expect "explicit N/A -> N/A" "$d" 0

  # 2b. mechanism STARTING with "na" must NOT be mis-read as N/A (regression).
  #     'NAT gateway only' names no recognized mechanism + no manifest -> FAIL, not green N/A.
  d="$base/na-prefix-not-na"; mkdir -p "$d"; printf 'FROM scratch\n' > "$d/Dockerfile"
  printf '# RUNBOOK\n## Deploy\n- Network egress: NAT gateway only, no default-deny\n' > "$d/RUNBOOK.md"
  expect "na-prefix mechanism -> FAIL (not N/A)" "$d" 1

  # 3. networked, nothing declared -> FAIL (1)
  d="$base/fail-bare"; mkdir -p "$d"; printf 'FROM scratch\n' > "$d/Dockerfile"
  printf '# RUNBOOK\n## Deploy\n- (no egress record)\n' > "$d/RUNBOOK.md"
  expect "networked-bare -> FAIL" "$d" 1

  # 4. manifest present, no attestation -> UNVERIFIED (2)
  d="$base/unv-manifest"; mkdir -p "$d/k8s"; printf 'FROM scratch\n' > "$d/Dockerfile"
  printf 'kind: NetworkPolicy\nspec:\n  policyTypes:\n    - Egress\n' > "$d/k8s/np.yaml"
  printf '# RUNBOOK\n## Deploy\n- (egress not yet attested)\n' > "$d/RUNBOOK.md"
  expect "manifest-no-attest -> UNVERIFIED" "$d" 2

  # 5. RUNBOOK names mechanism but [date] placeholder -> UNVERIFIED (2)
  d="$base/unv-placeholder"; mkdir -p "$d"; printf 'FROM scratch\n' > "$d/Dockerfile"
  printf '# RUNBOOK\n## Deploy\n- Network egress: default-deny via forward proxy — enforced: [date]\n' > "$d/RUNBOOK.md"
  expect "mechanism+placeholder -> UNVERIFIED" "$d" 2

  # 6. manifest + dated attestation -> PASS (0)
  d="$base/pass-manifest"; mkdir -p "$d/k8s"; printf 'FROM scratch\n' > "$d/Dockerfile"
  printf 'kind: NetworkPolicy\nspec:\n  policyTypes:\n    - Egress\n' > "$d/k8s/np.yaml"
  printf '# RUNBOOK\n## Deploy\n- Network egress: default-deny via k8s NetworkPolicy — enforced: 2026-06-01\n' > "$d/RUNBOOK.md"
  expect "manifest+attest -> PASS" "$d" 0

  # 7. no manifest, mechanism + dated attestation -> PASS (cloud/proxy path) (0)
  d="$base/pass-cloud"; mkdir -p "$d"; printf 'FROM scratch\n' > "$d/Dockerfile"
  printf '# RUNBOOK\n## Deploy\n- Network egress: default-deny via cloud egress firewall — enforced: 2026-06-01\n' > "$d/RUNBOOK.md"
  expect "cloud-mechanism+attest -> PASS" "$d" 0

  # 9. Ingress-only NetworkPolicy that only MENTIONS Egress in a comment -> NOT declared -> FAIL (1)
  #    (regression: a non-egress manifest must not falsely satisfy `declared`)
  d="$base/fail-ingress-only"; mkdir -p "$d/k8s"; printf 'FROM scratch\n' > "$d/Dockerfile"
  printf 'kind: NetworkPolicy\nspec:\n  # blocks all Egress in prose only\n  policyTypes:\n    - Ingress\n' > "$d/k8s/np.yaml"
  printf '# RUNBOOK\n## Deploy\n- (no egress record)\n' > "$d/RUNBOOK.md"
  expect "ingress-only-mentions-egress -> FAIL" "$d" 1

  # 10. escalation: fixture 5 under CI/--require -> FAIL (1)
  expect "declared-not-attested + require -> FAIL" "$base/unv-placeholder" 1 1

  if [ "$st_fail" -ne 0 ]; then echo "egress-policy --selftest: FAIL" >&2; return 1; fi
  echo "egress-policy --selftest: OK (na/explicit-na/bare-fail/manifest-unv/placeholder-unv/pass-manifest/pass-cloud/ingress-only-fail/escalation all behaved; fixtures left in $base)"
  return 0
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  *)          check_dir "$DIR"; exit $? ;;
esac
