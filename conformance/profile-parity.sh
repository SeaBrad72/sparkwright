#!/bin/sh
# profile-parity.sh — assert full DoD-capability PARITY across the app-stack profiles.
#
# The kit's Definition of Done mandates a capability set (feature flags + provider seam, smoke test,
# DR drill for data-backed stacks, app observability, a test pyramid, a health check, deploy/rollback
# + container). A profile that ships a compose.yaml is a deployable SERVICE stack and must fill that
# whole set. This gate fences the profiles into three NAMED sets and holds the FILLED set to the bar:
#   FILLED  — must ship the FULL capability set; any missing capability -> FAIL.
#   PENDING — a known, BOARD-LINKED gap; printed as a tracked (non-failing) hole; a PENDING entry
#             with no board reference -> FAIL (an untracked gap is not allowed).
#   EXEMPT  — a non-app profile (no service surface); printed with its reason; non-failing.
# A FAMILY-COMPLETENESS LOCK enumerates the service-shaped profiles ON DISK and FAILs any that is in
# no named set ("born outside the fence") — so a new profile cannot be auto-admitted the way a
# `profiles/*` glob would silently admit it (that glob is the vacuity this gate replaces).
#
# HONEST CEILING (read before trusting a green):
#   - This proves the PRESENCE + SHAPE of each mandated capability per FILLED service profile (and
#     that every remaining gap is tracked or exempt, never silent). It does NOT execute the drills
#     (running smoke/DR/observability on a real starter is CI's golden-path job), it does NOT prove a
#     live flag provider is wired per profile, and it does NOT prove adopter runtime behaviour.
#   - v1-green for STACK-PARITY = the PENDING set is EMPTY (every service profile has become FILLED).
#
#   usage: sh conformance/profile-parity.sh [--selftest]   (run from repo root)
#   exit:  0 = every FILLED profile fills the capability set, all gaps tracked/exempt · 1 = a FILLED
#          profile is missing a mandated capability, a PENDING gap is untracked, a named member is
#          missing, or a service profile is outside the fence · 2 = usage
set -eu
cd "$(dirname "$0")/.."

# The scan is parameterised by PROFILES_ROOT so the --selftest can drive the audit/lock functions
# against a fixture tree (mktemp) instead of the real profiles/. It is set INTERNALLY by selftest()
# only and is deliberately NOT env-readable: this gate is a control-plane oracle, and the kit's
# security posture rejects letting the environment redirect a control-plane check (a decoy tree must
# never be reachable from outside the script). cf. conformance/governing-docs-current.sh, which
# likewise drives its scan from an internal root, not an ambient env var.
PROFILES_ROOT=profiles

# ---- the named parity sets (LITERAL, never globbed — a glob can shrink to zero and pass vacuously) --

# FILLED: one profile name per line. Must ship the full capability set.
filled_set() {
  cat <<'SET'
typescript-node
python
SET
}

# PENDING: "<name> <board-reference>". The reference (everything after the name) is MANDATORY —
# a PENDING entry with no reference is an untracked gap and FAILs below.
pending_set() {
  cat <<'SET'
go P1.5 fan-out (STACK-PARITY follow-on)
rust P1.5 fan-out (STACK-PARITY follow-on)
java-spring P1.5 fan-out (STACK-PARITY follow-on)
kotlin P1.5 fan-out (STACK-PARITY follow-on)
dotnet P1.5 fan-out (STACK-PARITY follow-on)
SET
}

# EXEMPT: "<name> <reason>". Non-app profiles (no service surface); printed with the reason.
exempt_set() {
  cat <<'SET'
ml evals harness (ships its own DoD obligation)
data-engineering pipeline + data-quality obligations (own design, boarded)
terraform plan/validate/policy obligations (own design, boarded)
SET
}

# ---- helpers -----------------------------------------------------------------------------------

# A named profile is realised on disk as either profiles/<name>.md or a profiles/<name>/ directory.
profile_exists() {
  [ -f "$PROFILES_ROOT/$1.md" ] || [ -d "$PROFILES_ROOT/$1" ]
}

# is_adopter_tree: 0 (true) iff the cwd is NOT the kit's own tree. This gate audits the KIT's OWN
# reference profiles/; wired into the portable verify.sh it must N/A on any adopter tree (returning
# exit 0, NEVER exit 2 — an adopter's `verify.sh --require` must not fail on a kit-self check).
#
# The adopter signal is TWO export-ignored kit-dev markers, absent on EVERY adopter (both are
# `.gitattributes` export-ignore, so `git archive`/adopter-export strips them): docs/ROADMAP-KIT.md
# AND .github/workflows/golden-path.yml. This is the SAME pair feature-flags-wired.sh uses — chosen
# over "profiles/ absent" DELIBERATELY: profiles/ is NOT export-ignored, so it SHIPS to adopters, and
# adopter-export.sh --profile PRUNES it to the one chosen stack. Keying N/A on profiles/ presence would
# therefore MISS a single-profile adopter export (profiles/ present, but the named FILLED member
# typescript-node pruned away) and redden check_named_present on a tree that is simply not the kit.
# FAIL-CLOSED on the kit: BOTH markers are present in the kit, so the audit RUNS; delete profiles/ and
# check_named_present still FAILs (never N/A). Deleting ONE marker by accident still runs (the AND).
is_adopter_tree() {
  [ ! -f docs/ROADMAP-KIT.md ] && [ ! -f .github/workflows/golden-path.yml ]
}

# Is a name in FILLED or in PENDING (i.e. an ADMITTED service profile)?
in_service_set() {
  if filled_set | grep -qxF "$1"; then return 0; fi
  if pending_set | awk '{print $1}' | grep -qxF "$1"; then return 0; fi
  return 1
}

# Data-backed iff the scaffold declares .db-backed OR the compose.yaml names a database engine.
is_data_backed() {
  [ -f "$PROFILES_ROOT/$1/scaffold/.db-backed" ] && return 0
  grep -Eiq 'postgres|mysql|mariadb' "$PROFILES_ROOT/$1/compose.yaml" 2>/dev/null && return 0
  return 1
}

# Is a test LAYER present under a scaffold test dir? Stack-neutral: any non-vendored file whose full
# path contains the keyword (integration.test.ts, test_integration.py, e2e/journey_test.go all match).
# Mirrors conformance/test-layers-ready.sh's has_layer (presence-by-convention, not test quality).
has_layer() {
  _dir="$1"; _kw="$2"
  [ -d "$_dir" ] || return 1
  find "$_dir" \( -name node_modules -o -name .git -o -name dist -o -name build -o -name coverage \) -prune \
    -o -type f -print 2>/dev/null | grep -qFi "$_kw"
}

# ---- family-completeness lock: a service profile on disk that is in NO named set is a FAIL --------
# Enumerate the service-shaped profiles ON DISK (they ship a compose.yaml) and FAIL any that is not
# admitted to FILLED or PENDING. Named for anti-vacuity; family-locked so a new profile cannot be
# born outside the fence. (ml/data-engineering/terraform ship no compose.yaml -> non-service ->
# handled by the EXEMPT set, not here.)
check_family_complete() {
  _gap=0
  for _cf in "$PROFILES_ROOT"/*/compose.yaml; do
    [ -f "$_cf" ] || continue                       # unexpanded glob when no service profile exists
    _name=$(basename "$(dirname "$_cf")")
    if ! in_service_set "$_name"; then
      echo "FAIL family-lock: $_name ships compose.yaml (service stack) but is in NO parity set — born outside the fence; add it to FILLED or PENDING"
      _gap=1
    fi
  done
  return "$_gap"
}

# ---- named-member presence: a named member missing on disk is a FAIL, never a silent skip --------
# The sets are NAMED (not globbed); the cost of naming is staleness, so a named member that has been
# renamed/removed must FAIL rather than quietly drop out of the audit.
check_named_present() {
  _gap=0
  for _n in $(filled_set); do
    profile_exists "$_n" || { echo "FAIL: named FILLED profile '$_n' is MISSING on disk (renamed? removed?)"; _gap=1; }
  done
  while IFS=' ' read -r _n _ref; do
    [ -n "$_n" ] || continue
    profile_exists "$_n" || { echo "FAIL: named PENDING profile '$_n' is MISSING on disk (renamed? removed?)"; _gap=1; }
  done <<EOF
$(pending_set)
EOF
  while IFS=' ' read -r _n _reason; do
    [ -n "$_n" ] || continue
    profile_exists "$_n" || { echo "FAIL: named EXEMPT profile '$_n' is MISSING on disk (renamed? removed?)"; _gap=1; }
  done <<EOF
$(exempt_set)
EOF
  return "$_gap"
}

# ---- PENDING board-ref: every PENDING entry must carry a reference (no untracked gaps) ------------
# Reads the PENDING lines on STDIN (the real run pipes `pending_set`; the selftest pipes a crafted
# line) so the check is drivable against a fixture without touching the LITERAL default set.
check_pending_tracked() {
  _gap=0
  while IFS=' ' read -r _n _ref; do
    [ -n "$_n" ] || continue
    if [ -z "$_ref" ]; then
      echo "FAIL: PENDING profile '$_n' has NO board reference — an untracked gap is not allowed (add a board ref)"
      _gap=1
    fi
  done
  return "$_gap"
}

# ---- anti-vacuity floor: a NAMED parity set must not be empty -------------------------------------
# Reads the set on STDIN and counts non-blank lines. A zero-length set would let the whole audit pass
# vacuously (an empty `for` loop reports no gaps), so an empty set is a FAIL, never a green. Applied
# to the FILLED set only — an empty PENDING set is the v1-green GOAL, not a fault.
check_nonempty() {
  _label=$1
  _count=$(grep -c '[^[:space:]]' 2>/dev/null || true)
  [ -n "$_count" ] || _count=0
  if [ "$_count" -eq 0 ]; then
    echo "FAIL: named $_label set is EMPTY — a zero-length parity set passes vacuously; refusing to green"
    return 1
  fi
  return 0
}

# ---- the capability audit for one FILLED profile -------------------------------------------------
# Increments the global `gaps` per missing capability and sets the global `fail`. Called directly
# (never in a subshell/pipe) so the global mutations propagate.
audit_filled() {
  _n=$1
  _pd="$PROFILES_ROOT/$_n"
  _sc="$_pd/scaffold"

  # per-profile path mapping — kept explicit and readable, not clever.
  case "$_n" in
    typescript-node) _flags="$_sc/src/flags.ts";     _health="$_sc/src/health.ts";     _testdir="$_sc/test" ;;
    python)          _flags="$_sc/src/app/flags.py"; _health="$_sc/src/app/health.py"; _testdir="$_sc/tests" ;;
    *) echo "FAIL $_n: FILLED profile has no capability path mapping — add one before admitting it to FILLED"; fail=1; gaps=$((gaps + 1)); return 0 ;;  # M1: return 0 (clean-FAIL via the global `fail`), never `return 1` — a bare `return 1` under `set -e` aborts the scan mid-loop and swallows the summary.
  esac

  # cap 1 — feature flags + PROVIDER SEAM (a flags module that names a FlagProvider and an env provider).
  # Comment-strip the source first (both // and # styles, so the probe is stack-neutral across ts/py):
  # a commented-out declaration must NOT satisfy the oracle vacuously — the seam must be LIVE code.
  _flags_code=$(sed -e 's|//.*||' -e 's/#.*//' "$_flags" 2>/dev/null || true)
  if [ -f "$_flags" ] \
     && printf '%s\n' "$_flags_code" | grep -q 'FlagProvider' \
     && printf '%s\n' "$_flags_code" | grep -Eq 'envProvider|env_provider'; then
    echo "PASS $_n: cap1 feature flags + provider seam"
  else
    echo "FAIL $_n: mandates feature-flags provider seam — missing (need $_flags declaring FlagProvider + an env provider)"
    fail=1; gaps=$((gaps + 1))
  fi

  # cap 2 — smoke test.
  if [ -f "$_sc/scripts/smoke.sh" ]; then
    echo "PASS $_n: cap2 smoke test"
  else
    echo "FAIL $_n: mandates a smoke test — missing ($_sc/scripts/smoke.sh)"
    fail=1; gaps=$((gaps + 1))
  fi

  # cap 3 — DR drill, ONLY iff data-backed (a stateless service has no DR obligation -> N/A, not a gap).
  if is_data_backed "$_n"; then
    if [ -f "$_sc/scripts/dr-drill.sh" ] && [ -f "$_sc/.db-backed" ]; then
      echo "PASS $_n: cap3 DR drill (data-backed)"
    else
      echo "FAIL $_n: data-backed but mandates a DR drill — missing ($_sc/scripts/dr-drill.sh + $_sc/.db-backed)"
      fail=1; gaps=$((gaps + 1))
    fi
  else
    echo "N/A  $_n: cap3 DR drill — not data-backed (no gap)"
  fi

  # cap 4 — app observability (otel collector config lives under observability/).
  if [ -d "$_sc/observability" ]; then
    echo "PASS $_n: cap4 app observability"
  else
    echo "FAIL $_n: mandates app observability — missing ($_sc/observability/)"
    fail=1; gaps=$((gaps + 1))
  fi

  # cap 5 — test pyramid: integration + e2e layers present (presence-by-convention; unit is the base).
  if has_layer "$_testdir" integration && has_layer "$_testdir" e2e; then
    echo "PASS $_n: cap5 test pyramid (integration + e2e)"
  else
    echo "FAIL $_n: mandates a test pyramid — integration and/or e2e layer missing under $_testdir"
    fail=1; gaps=$((gaps + 1))
  fi

  # cap 6 — health check (LOCKED — already 7/7; assert so a profile can't silently drop it).
  if [ -f "$_health" ]; then
    echo "PASS $_n: cap6 health check (locked)"
  else
    echo "FAIL $_n: mandates a health check — missing ($_health)"
    fail=1; gaps=$((gaps + 1))
  fi

  # cap 7 — deploy/rollback + container (LOCKED — assert Dockerfile + compose + deploy/ can't regress).
  if [ -f "$_pd/Dockerfile" ] && [ -f "$_pd/compose.yaml" ] && [ -d "$_pd/deploy" ]; then
    echo "PASS $_n: cap7 deploy/rollback + container (locked)"
  else
    echo "FAIL $_n: mandates deploy/rollback + container — missing (need $_pd/Dockerfile + $_pd/compose.yaml + $_pd/deploy/)"
    fail=1; gaps=$((gaps + 1))
  fi
}

# ---- the run -------------------------------------------------------------------------------------
run_parity() {
  # KIT-SELF N/A carve-out (must precede any audit): this gate audits the kit's own REFERENCE profiles/.
  # An adopter tree (detected by the absence of the kit-dev markers — see is_adopter_tree) has no
  # obligation to satisfy the kit's own profile-parity, and a --profile-pruned export would otherwise
  # redden check_named_present ("named FILLED profile missing on disk"). N/A returns exit 0 — NEVER exit
  # 2 — so an adopter's `verify.sh --require` stays green. Fail-closed on the kit (see is_adopter_tree).
  if is_adopter_tree; then
    echo "profile-parity: N/A — kit-self check (audits the kit's own profiles/; not present on an adopter tree)"
    return 0
  fi

  fail=0; gaps=0

  filled_set | check_nonempty FILLED || fail=1
  check_family_complete              || fail=1
  check_named_present                || fail=1
  pending_set | check_pending_tracked || fail=1

  echo "--- FILLED profiles (must ship the full capability set) ---"
  for _n in $(filled_set); do
    audit_filled "$_n"
  done

  echo "--- PENDING profiles (tracked, non-failing gaps) ---"
  _pending_n=0
  while IFS=' ' read -r _n _ref; do
    [ -n "$_n" ] || continue
    echo "TRACKED GAP $_n: $_ref"
    _pending_n=$((_pending_n + 1))
  done <<EOF
$(pending_set)
EOF

  echo "--- EXEMPT profiles (no service surface) ---"
  while IFS=' ' read -r _n _reason; do
    [ -n "$_n" ] || continue
    echo "EXEMPT $_n: $_reason"
  done <<EOF
$(exempt_set)
EOF

  echo "---"
  if [ "$fail" -ne 0 ]; then
    echo "FAIL: profile-parity — $gaps capability gap(s) across FILLED profiles; PENDING fills remaining: $_pending_n"
    return 1
  fi
  echo "OK: profile-parity — every FILLED profile ships the full capability set; $_pending_n PENDING profile(s) tracked; all gaps fenced"
  return 0
}

# ---- selftest (non-vacuity: each case is WITNESSED against a fixture; the check must be RED-able) --
# Builds fixture profile trees under mktemp and drives the audit/lock functions against them via
# PROFILES_ROOT (and via STDIN for the set-based checks). Mirrors governing-docs-current.sh: assert
# the clean fixture PASSES, then plant each violation and assert it turns the scan RED. Fixtures are
# removed on EXIT. A green here attests each guard FIRES; it is the claim's tree-independent verifier.
selftest() {
  st=0
  base=$(mktemp -d)
  trap 'rm -rf "$base"' EXIT

  # A COMPLETE typescript-node service profile that ships every mandated capability, under <root>/.
  # (typescript-node reuses the real case-mapping in audit_filled, so no probe semantics change.)
  mk_clean_ts() {
    _r="$1/typescript-node"; _s="$_r/scaffold"
    mkdir -p "$_s/src" "$_s/scripts" "$_s/observability" "$_s/test" "$_r/deploy"
    printf 'export interface FlagProvider {}\nexport const envProvider = 1;\n' > "$_s/src/flags.ts"
    printf 'export const health = 1;\n'                                        > "$_s/src/health.ts"
    printf '#!/bin/sh\n'                                                       > "$_s/scripts/smoke.sh"
    printf '#!/bin/sh\n'                                                       > "$_s/scripts/dr-drill.sh"
    : > "$_s/.db-backed"
    printf 'test\n'                                                           > "$_s/test/svc.integration.test.ts"
    printf 'test\n'                                                           > "$_s/test/journey.e2e.test.ts"
    printf '# otel\n'                                                          > "$_s/observability/otel.yaml"
    printf 'FROM node\n'                                                       > "$_r/Dockerfile"
    printf 'services: {}\n'                                                    > "$_r/compose.yaml"
    printf '# deploy\n'                                                        > "$_r/deploy/README.md"
  }

  # 1. CLEAN FILLED fixture -> every capability PASS (GREEN, no gap).
  mkdir -p "$base/clean"; mk_clean_ts "$base/clean"
  _c1=$( fail=0; gaps=0; PROFILES_ROOT="$base/clean"; audit_filled typescript-node 2>&1 )
  if printf '%s\n' "$_c1" | grep -q '^FAIL'; then
    echo "FAIL: selftest case1 — a clean FILLED fixture reported a capability gap:"; printf '%s\n' "$_c1"; st=1
  else
    echo "OK: clean FILLED fixture -> every capability PASS (GREEN)"
  fi

  # 2. REMOVE ONE CAPABILITY (observability) -> RED naming that capability.
  mkdir -p "$base/nobs"; mk_clean_ts "$base/nobs"
  rm -rf "$base/nobs/typescript-node/scaffold/observability"
  _c2=$( fail=0; gaps=0; PROFILES_ROOT="$base/nobs"; audit_filled typescript-node 2>&1 )
  if printf '%s\n' "$_c2" | grep -q 'mandates app observability'; then
    echo "OK: removed observability capability -> RED (named)"
  else
    echo "FAIL: selftest case2 — removing observability did NOT redden the audit:"; printf '%s\n' "$_c2"; st=1
  fi

  # 3. PENDING entry with a NAME but NO board ref -> RED (untracked gap).
  if printf 'go\n' | check_pending_tracked >/dev/null 2>&1; then
    echo "FAIL: selftest case3 — an untracked PENDING gap (no board ref) passed"; st=1
  else
    echo "OK: PENDING entry with no board ref -> RED (untracked gap)"
  fi

  # 4. FAMILY LOCK: a service profile (ships compose.yaml) whose name is in NO named set -> RED.
  mkdir -p "$base/fam/brand-new-svc"
  printf 'services: {}\n' > "$base/fam/brand-new-svc/compose.yaml"
  PROFILES_ROOT="$base/fam"
  if check_family_complete >/dev/null 2>&1; then
    echo "FAIL: selftest case4 — a service profile outside every named set passed the family lock"; st=1
  else
    echo "OK: service profile born outside the fence -> RED (family lock)"
  fi

  # 5. MISSING NAMED MEMBER: none of the named members exist on disk -> RED (no silent skip).
  mkdir -p "$base/empty-prof"
  PROFILES_ROOT="$base/empty-prof"
  if check_named_present >/dev/null 2>&1; then
    echo "FAIL: selftest case5 — named members missing on disk passed (silent-skip vacuity)"; st=1
  else
    echo "OK: missing named member -> RED (no silent skip)"
  fi

  # 6. ANTI-VACUITY FLOOR: an EMPTY FILLED set must FAIL, never pass vacuously.
  if printf '' | check_nonempty FILLED >/dev/null 2>&1; then
    echo "FAIL: selftest case6 — an EMPTY FILLED set passed (vacuous green)"; st=1
  else
    echo "OK: empty FILLED set -> FAIL (anti-vacuity floor holds)"
  fi

  # 7. M1: an UNMAPPED FILLED profile must clean-FAIL and let the scan REACH the summary — not
  #    `return 1` under set -e and abort mid-loop. Reproduce run_parity's exact set -e loop context.
  _m1=$( { set -eu; fail=0; gaps=0
    audit_filled unmapped-x          # bare call, exactly as run_parity's loop invokes it
    echo "SUMMARY-REACHED gaps=$gaps fail=$fail"
  } 2>&1 ) || true
  if printf '%s\n' "$_m1" | grep -q 'no capability path mapping' \
     && printf '%s\n' "$_m1" | grep -q 'SUMMARY-REACHED'; then
    echo "OK: unmapped FILLED -> clean FAIL, scan continues to the summary (M1 fixed)"
  else
    echo "FAIL: selftest case7 — an unmapped FILLED aborted the scan before the summary (M1):"; printf '%s\n' "$_m1"; st=1
  fi

  # 8. KIT-SELF N/A: an ADOPTER-shaped tree (NEITHER export-ignored kit-dev marker present:
  #    no docs/ROADMAP-KIT.md, no .github/workflows/golden-path.yml) drives run_parity to N/A, exit 0 —
  #    NOT a FAIL. Driven via a REAL cwd change so the guard's cwd marker probe is genuinely exercised.
  #    LOAD-BEARING: strip the is_adopter_tree carve-out and run_parity proceeds, hits check_named_present
  #    (typescript-node absent under the fixture root) and RETURNS 1 — so this case reddens if the
  #    kit-self N/A guard is ever removed. This is the guarantee that lets the gate live in the portable
  #    verify.sh without reddening any adopter tree (incl. a single-profile --profile-pruned export).
  mkdir -p "$base/adopter"
  if _c8=$( cd "$base/adopter" && PROFILES_ROOT=profiles; run_parity 2>&1 ); then _c8rc=0; else _c8rc=$?; fi
  if [ "$_c8rc" = 0 ] && printf '%s\n' "$_c8" | grep -q 'N/A — kit-self check'; then
    echo "OK: adopter-shaped tree (no kit-dev markers) -> N/A, exit 0 (kit-self carve-out)"
  else
    echo "FAIL: selftest case8 — adopter tree did not N/A green (rc=$_c8rc):"; printf '%s\n' "$_c8"; st=1
  fi

  # 9. FAIL-CLOSED: a KIT-shaped tree (the docs/ROADMAP-KIT.md marker PRESENT) must NOT N/A — the audit
  #    RUNS. Here the marker is present but the named FILLED member is absent under the fixture root, so
  #    run_parity proceeds past the carve-out and check_named_present FAILs (exit 1). This proves the
  #    guard does not over-N/A a broken kit into a false green (the fail-closed property is_adopter_tree
  #    claims): a kit that lost its profiles/ still REDs rather than skipping the audit.
  mkdir -p "$base/kitshaped/docs"
  : > "$base/kitshaped/docs/ROADMAP-KIT.md"
  if _c9=$( cd "$base/kitshaped" && PROFILES_ROOT=profiles; run_parity 2>&1 ); then _c9rc=0; else _c9rc=$?; fi
  if [ "$_c9rc" != 0 ] && printf '%s\n' "$_c9" | grep -q 'is MISSING on disk'; then
    echo "OK: kit-marked tree with profiles absent -> audit RUNS + FAILs (fail-closed, no over-N/A)"
  else
    echo "FAIL: selftest case9 — kit-marked broken tree did not fail-closed (rc=$_c9rc):"; printf '%s\n' "$_c9"; st=1
  fi

  if [ "$st" = 0 ]; then
    echo "profile-parity --selftest: OK (all 9 cases witnessed)"
  else
    echo "profile-parity --selftest: FAIL"
  fi
  return "$st"
}

# ---- dispatch ------------------------------------------------------------------------------------
case "${1:-}" in
  --selftest) selftest ;;
  '')         run_parity ;;
  *)          echo "usage: profile-parity.sh [--selftest]" >&2; exit 2 ;;
esac
