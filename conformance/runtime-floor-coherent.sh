#!/bin/sh
# runtime-floor-coherent.sh — fleet runtime-coherence gate: for EVERY profiles/<stack>/, assert the
# declared manifest runtime FLOOR equals the CI-tested runtime AND the container base — floor == CI ==
# container (owner-ratified 2026-07-19, CP-7/K7). A floor BELOW the only tested runtime is an
# unverified promise: ts-node's engines.node >=20 admits Node 20.10, which crashes the locked
# Vitest-4/Rolldown toolchain (needs util.styleText, added in 20.12) while CI/base ship Node 24;
# python has the same latent bug (requires-python >=3.11, but CI + base are 3.12). This gate locks
# that class fleet-wide. Where a profile declares NO manifest floor (or a non-numeric / moving
# surface — e.g. rust ships edition-only), that leg is N/A-WITH-REASON (printed + named), never a
# forced number or a silent skip. N/A must be EARNED: a manifest present-but-unparseable is a FAIL,
# not a green skip. Fail-closed: an empty profiles/*/ enumeration is a FAIL, never a vacuous pass.
#   sh conformance/runtime-floor-coherent.sh            # real scan of the profile fleet
#   sh conformance/runtime-floor-coherent.sh --selftest # fixtures (coherent passes, incoherent fails)
# Exit: 0 = every profile coherent (or earned-N/A) · 1 = a divergence / unparseable / fail-closed · 2 = usage.
# What it changes: read-only — parses profile manifests / ci.yml / Dockerfile; mutates nothing (selftest
#   writes only to its own mktemp fixtures and trap-cleans them).
# Guardrails: read-only; no network, no repo writes; additive lint — never weakens a gate; POSIX sh, dash-clean.
set -eu

# ── numeric helpers ────────────────────────────────────────────────────────────────────────────
# mm <raw> — normalize to major.minor (missing minor -> .0). Strips everything but [0-9.]. Prints the
# normalized value and returns 0; returns 1 (unparseable) when no numeric major can be recovered.
# NOTE: only a single lower-bound token is supported. A dual-bound range like ">=3.11,<3.13" strips to
# "3.113.13" and normalizes to a garbled "3.113" — fail-closed (a false FAIL, never a false PASS), so a
# maintainer adding an upper bound gets a legible RED. No current profile declares one.
mm() {
  _raw=$(printf '%s' "$1" | sed 's/[^0-9.]//g')
  _maj=$(printf '%s' "$_raw" | cut -d. -f1)
  case "$_maj" in ''|*[!0-9]*) return 1 ;; esac
  _min=$(printf '%s' "$_raw" | cut -s -d. -f2)
  case "$_min" in ''|*[!0-9]*) _min=0 ;; esac
  printf '%s.%s' "$_maj" "$_min"
}

# disp <major.minor> — human display: drop a trailing .0 (so 20.0 -> 20, 3.12 stays 3.12).
disp() { case "$1" in *.0) printf '%s' "${1%.0}" ;; *) printf '%s' "$1" ;; esac }

# ── per-surface parsers ──────────────────────────────────────────────────────────────────────────
# floor_of <profile-dir> — the DECLARED manifest floor as major.minor, or "NA:<reason>" (no manifest /
# genuinely floor-less surface) or "FAIL:<reason>" (manifest present but its floor is unparseable).
# Priority: package.json(engines.node) > pyproject(requires-python) > go.mod > Cargo.toml(rust-version,
# optional) > pom.xml(java.version) > build.gradle.kts(jvmTarget) > *.csproj(TargetFramework).
# Multi-manifest surfaces (ts has scaffold + scaffold-cli; dotnet has >1 csproj) MUST agree, else FAIL.
floor_of() {
  _d=$1
  _pkgs=$(find "$_d" -maxdepth 2 -name package.json 2>/dev/null | sort)
  if [ -n "$_pkgs" ]; then
    _seen=""
    for _pj in $_pkgs; do
      _val=$(grep -o '"node"[[:space:]]*:[[:space:]]*"[^"]*"' "$_pj" | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
      _m=$(mm "$_val") || { printf 'FAIL:engines.node unparseable in %s' "$_pj"; return 0; }
      if [ -z "$_seen" ]; then _seen=$_m
      elif [ "$_seen" != "$_m" ]; then printf 'FAIL:scaffolds disagree on node floor (%s vs %s)' "$_seen" "$_m"; return 0; fi
    done
    printf '%s' "$_seen"; return 0
  fi
  _py=$(find "$_d" -maxdepth 2 -name pyproject.toml 2>/dev/null | head -1)
  if [ -n "$_py" ]; then
    _val=$(grep -E '^[[:space:]]*requires-python' "$_py" | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
    _m=$(mm "$_val") || { printf 'FAIL:requires-python unparseable in %s' "$_py"; return 0; }
    printf '%s' "$_m"; return 0
  fi
  _gm=$(find "$_d" -maxdepth 2 -name go.mod 2>/dev/null | head -1)
  if [ -n "$_gm" ]; then
    _val=$(grep -E '^go[[:space:]]+[0-9]' "$_gm" | head -1 | awk '{print $2}')
    _m=$(mm "$_val") || { printf 'FAIL:go directive unparseable in %s' "$_gm"; return 0; }
    printf '%s' "$_m"; return 0
  fi
  _ct=$(find "$_d" -maxdepth 2 -name Cargo.toml 2>/dev/null | head -1)
  if [ -n "$_ct" ]; then
    _val=$(grep -E '^[[:space:]]*rust-version' "$_ct" | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
    if [ -z "$_val" ]; then printf 'NA:no declared floor (rust ships edition-only)'; return 0; fi
    _m=$(mm "$_val") || { printf 'FAIL:rust-version unparseable in %s' "$_ct"; return 0; }
    printf '%s' "$_m"; return 0
  fi
  _pom=$(find "$_d" -maxdepth 2 -name pom.xml 2>/dev/null | head -1)
  if [ -n "$_pom" ]; then
    _val=$(grep -o '<java.version>[0-9][0-9.]*</java.version>' "$_pom" | head -1 | sed 's/<[^>]*>//g')
    _m=$(mm "$_val") || { printf 'FAIL:java.version unparseable in %s' "$_pom"; return 0; }
    printf '%s' "$_m"; return 0
  fi
  _bg=$(find "$_d" -maxdepth 2 -name build.gradle.kts 2>/dev/null | head -1)
  if [ -n "$_bg" ]; then
    # NOTE: assumes the quoted jvmTarget = "21" form used by the current kotlin profile. The enum form
    # JvmTarget.JVM_21 survives only by digit-strip; JVM_1_8 would mis-parse. Revisit if the profile changes.
    _val=$(grep -E 'jvmTarget' "$_bg" | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
    _m=$(mm "$_val") || { printf 'FAIL:jvmTarget unparseable in %s' "$_bg"; return 0; }
    printf '%s' "$_m"; return 0
  fi
  _cs=$(find "$_d" -maxdepth 4 -name '*.csproj' 2>/dev/null | sort)
  if [ -n "$_cs" ]; then
    _seen=""
    for _c in $_cs; do
      _val=$(grep -o '<TargetFramework>[^<]*</TargetFramework>' "$_c" | head -1 | sed 's/<[^>]*>//g')
      _m=$(mm "$_val") || { printf 'FAIL:TargetFramework unparseable in %s' "$_c"; return 0; }
      if [ -z "$_seen" ]; then _seen=$_m
      elif [ "$_seen" != "$_m" ]; then printf 'FAIL:csproj disagree on target (%s vs %s)' "$_seen" "$_m"; return 0; fi
    done
    printf '%s' "$_seen"; return 0
  fi
  printf 'NA:no declared floor'
}

# ci_of <profile-dir> — the CI-tested runtime as major.minor from ci.yml's version key; returns 1 when
# no recognized numeric version key is present (a moving/non-numeric toolchain, e.g. rust-toolchain).
ci_of() {
  _f="$1/ci.yml"
  [ -f "$_f" ] || return 1
  _raw=""
  # NOTE: keys are tried in fixed priority; the FIRST present *-version key binds. This assumes one
  # runtime per profile (no current profile is polyglot) — a ci.yml with two version keys would bind
  # the higher-priority one here.
  for _k in node-version python-version go-version java-version dotnet-version terraform_version; do
    _v=$(grep -E "^[[:space:]]*${_k}:" "$_f" | head -1 | sed 's/#.*//' | awk -F: '{print $2}' | tr -d " '\"")
    if [ -n "$_v" ]; then _raw=$_v; break; fi
  done
  [ -n "$_raw" ] || return 1
  mm "$_raw" || return 1
}

# container_major <profile-dir> — the builder-stage FROM runtime MAJOR, or "NA:no Dockerfile", or
# "FAIL:<reason>". Uses the FIRST FROM (builder stage carries the real runtime version); the distroless
# second stage is deliberately ignored.
container_major() {
  _d=$1; _df="$_d/Dockerfile"
  if [ ! -f "$_df" ]; then printf 'NA:no Dockerfile'; return 0; fi
  _img=$(grep -E '^FROM[[:space:]]' "$_df" | head -1 | awk '{print $2}')
  if [ -z "$_img" ]; then printf 'FAIL:no FROM in %s' "$_df"; return 0; fi
  case "$_img" in *:*) : ;; *) printf 'FAIL:FROM image has no tag (%s)' "$_img"; return 0 ;; esac
  _tag=${_img##*:}
  _tagnum=${_tag%%-*}
  _cm=$(mm "$_tagnum") || { printf 'FAIL:FROM tag unparseable (%s)' "$_tag"; return 0; }
  printf '%s' "${_cm%%.*}"
}

# ── the check ────────────────────────────────────────────────────────────────────────────────────
# eval_profile <profile-dir> — evaluate one profile; print exactly one verdict line NAMING the profile
# (liveness: a whole-fleet skip must never render as green). Returns 0 = PASS / earned-N/A · 1 = FAIL.
eval_profile() {
  _d=$1; _p=${_d##*/}
  _floor=$(floor_of "$_d")
  case "$_floor" in
    FAIL:*) echo "FAIL: $_p floor unparseable — ${_floor#FAIL:}"; return 1 ;;
    NA:*)   echo "N/A: $_p ${_floor#NA:}"; return 0 ;;
  esac
  _ci=$(ci_of "$_d") || _ci=""
  if [ -z "$_ci" ]; then
    echo "FAIL: $_p declares floor $(disp "$_floor") but has no numeric CI runtime to verify against"
    return 1
  fi
  if [ "$_floor" != "$_ci" ]; then
    echo "FAIL: $_p floor $(disp "$_floor") != CI $(disp "$_ci")"
    return 1
  fi
  _cont=$(container_major "$_d")
  case "$_cont" in
    FAIL:*) echo "FAIL: $_p container unparseable — ${_cont#FAIL:}"; return 1 ;;
    NA:*)   echo "PASS: $_p (floor $(disp "$_floor") == CI $(disp "$_ci"), container ${_cont#NA:})"; return 0 ;;
  esac
  _cimaj=${_ci%%.*}
  if [ "$_cont" != "$_cimaj" ]; then
    echo "FAIL: $_p container $_cont != CI $_cimaj"
    return 1
  fi
  enforced_floor "$_d" || return 1
  echo "PASS: $_p (floor $(disp "$_floor") == CI $(disp "$_ci"), container $_cont)"
  return 0
}

# enforced_floor <profile-dir> — a DECLARED floor must also be ENFORCED at install time.
# CP-7 K3: the TS profile declared Node 24 in five places and enforced it in none — `npm ci` merely
# warned EBADENGINE and carried on, and the real failure surfaced far downstream as an unreadable
# bundler error. `engine-strict=true` in .npmrc is npm's hard-fail switch. This lock exists because
# without it BOTH .npmrc files could be deleted and every gate in the kit would stay green — the
# declared-but-unenforced shape the slice was written to end.
# Scope: npm-manifest scaffolds only. Other toolchains' floors are declared-not-enforced (stated in the
# adopter-visible ceiling in docs/STACK-SELECTION.md); widening this is the v1-track item.
enforced_floor() {
  _d=$1; _miss=""
  for _pj in $(find "$_d" -maxdepth 2 -name package.json 2>/dev/null | sort); do
    grep -q '"engines"' "$_pj" || continue          # no declared floor -> nothing to enforce
    _sd=$(dirname "$_pj")
    grep -qE '^[[:space:]]*engine-strict[[:space:]]*=[[:space:]]*true' "$_sd/.npmrc" 2>/dev/null \
      || _miss="$_miss $_sd"
  done
  [ -z "$_miss" ] && return 0
  echo "FAIL: declares engines but does not ENFORCE it — missing 'engine-strict=true' in .npmrc:$_miss"
  echo "A declared floor npm only warns about is the CP-7 K3 defect: green preflight, EBADENGINE warning," >&2
  echo "install proceeds, and the failure surfaces later as an unrelated-looking error." >&2
  return 1
}

# run_fleet <root> — enumerate every <root>/<dir>/ and evaluate each. Fail-closed: ZERO profile dirs is
# itself a FAIL (mirrors conformance/action-pinning.sh), never a silent/vacuous pass. `find`, not a glob,
# so this stays correct under `set -eu` (no nullglob).
run_fleet() {
  _root=$1; _rc=0
  _profiles=$(find "$_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
  if [ -z "$_profiles" ]; then
    echo "FAIL: no profiles found under $_root — cannot verify runtime-floor coherence"
    return 1
  fi
  for _p in $_profiles; do
    eval_profile "$_p" || _rc=1
  done
  return $_rc
}

# ── selftest (non-vacuity teeth: every exit-code assertion is paired with a discriminating message) ──
# A scaffold that DECLARES engines must also ENFORCE them (enforced_floor), so the conformant fixture
# ships .npmrc too. Pass a 3rd arg 'no-npmrc' to build the non-enforcing shape for the negative case.
_sf_mkpkg()   { mkdir -p "$1"; printf '{\n  "name": "fix",\n  "engines": { "node": "%s" }\n}\n' "$2" > "$1/package.json"
                [ "${3:-}" = "no-npmrc" ] || printf 'engine-strict=true\n' > "$1/.npmrc"; }
_sf_mkci()    { mkdir -p "$1"; printf 'jobs:\n  x:\n    with:\n      %s: %s\n' "$2" "$3" > "$1/ci.yml"; }
_sf_mkdocker(){ mkdir -p "$1"; printf 'FROM %s AS builder\nRUN echo hi\n' "$2" > "$1/Dockerfile"; }

selftest() {
  _sf=0
  _base=$(mktemp -d)
  trap 'rm -rf "$_base"' EXIT INT TERM

  # ── (0) ENFORCEMENT leg (K2, v3.173.0) — a floor that is COHERENTLY DECLARED but NEVER ENFORCED is
  # exactly the CP-7 run-5 defect: preflight has refused a below-floor runtime since v3.169.0, and
  # `incept` never invoked it, so the refusal was UNREACHABLE on the documented path. Declaration and
  # enforcement therefore belong in ONE check — coherence alone was green while the floor did nothing.
  #
  # BEHAVIOURAL, never a grep for `--stack` in incept.sh: presence is not effect. This exports a real
  # adopter tree, plants an UNMEETABLE floor, and runs the real `incept`, asserting on its exit status.
  _sf_root=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
  _sf_veh="$_base/enforce"
  if sh "$_sf_root/scripts/adopter-export.sh" "$_sf_veh" >/dev/null 2>&1; then
    printf '999\n' > "$_sf_veh/profiles/typescript-node/scaffold/.nvmrc"
    ( cd "$_sf_veh" && git init -q . ) >/dev/null 2>&1
    _sf_args="--name f --intent-owner o --stack typescript-node --team solo --backlog md --ci github --harness claude-code --operator-fluency practitioner --mode lean --no-db --noninteractive"
    # (0a) load-bearing negative — an unmeetable floor must be SURFACED. Under --noninteractive the
    # contract is WARN-AND-PROCEED (scaffold-and-inspect automation is legitimate; the kit's own CI does
    # it constantly), so the assertion is on the WARNING, not on the exit status. A silent proceed — the
    # pre-v3.173.0 behaviour — fails here.
    _sf_out=$( cd "$_sf_veh" && sh scripts/incept.sh $_sf_args 2>&1 ) && _sf_rc=0 || _sf_rc=$?
    if printf '%s' "$_sf_out" | grep -q 'does not meet its declared floor'; then
      echo "PASS: selftest — (0a) incept SURFACES an unmeetable runtime floor (warn-and-proceed under --noninteractive)"
    else
      echo "FAIL: selftest — (0a) incept was SILENT about an unmeetable runtime floor (declared but NOT enforced — this is K2)"; _sf=1
    fi
    # (0a2) and it must still COMPLETE — scaffolding is safe on a below-floor runtime; only BUILDING is
    # not. A refusal here would redden every fixture-incepting job in CI, which is exactly what the
    # first version of this fix did.
    if [ "${_sf_rc:-1}" = 0 ]; then
      echo "PASS: selftest — (0a2) --noninteractive incept still completes (scaffold-and-inspect is not blocked)"
    else
      echo "FAIL: selftest — (0a2) --noninteractive incept REFUSED — this breaks every fixture-incepting CI job"; _sf=1
    fi
    # (0b) the escape must actually UNBLOCK the command that offers it. An escape naming a flag that
    # only makes PREFLIGHT pass is a dead end: the operator follows it and is refused identically.
    _sf_veh2="$_base/enforce-waived"
    if sh "$_sf_root/scripts/adopter-export.sh" "$_sf_veh2" >/dev/null 2>&1; then
      printf '999\n' > "$_sf_veh2/profiles/typescript-node/scaffold/.nvmrc"
      ( cd "$_sf_veh2" && git init -q . ) >/dev/null 2>&1
      if ( cd "$_sf_veh2" && sh scripts/incept.sh $_sf_args --allow-runtime-mismatch ) >/dev/null 2>&1; then
        echo "PASS: selftest — (0b) --allow-runtime-mismatch unblocks incept itself (the escape is not a dead end)"
      else
        echo "FAIL: selftest — (0b) the documented escape did NOT unblock incept (a signpost pointing at a wall)"; _sf=1
      fi
    fi
  else
    echo "PASS: selftest — (0) enforcement leg SKIPPED (adopter-export unavailable here); coherence legs still run"
  fi

  # (1) positive anchor — coherent profile (floor >=20, CI 20, container 20) -> PASS, rc 0.
  _sf_mkpkg "$_base/pos/scaffold" '>=20'; _sf_mkci "$_base/pos" 'node-version' '20'; _sf_mkdocker "$_base/pos" 'node:20-bookworm-slim'
  if _o=$(eval_profile "$_base/pos" 2>&1); then _r=0; else _r=$?; fi
  if [ "$_r" = 0 ] && printf '%s' "$_o" | grep -q '^PASS:'; then
    echo "PASS: selftest — (1) positive anchor: coherent profile passes (rc 0, 'PASS' printed)"
  else
    echo "FAIL: selftest — (1) positive anchor: rc=$_r out=[$_o]"; _sf=1
  fi

  # (2) LOAD-BEARING negative — floor >=20 vs CI 24 -> rc 1 AND '!= CI' (assert BOTH: a bare exit-code
  #     check can be faked by a usage-2 or an unrelated error).
  _sf_mkpkg "$_base/neg/scaffold" '>=20'; _sf_mkci "$_base/neg" 'node-version' '24'; _sf_mkdocker "$_base/neg" 'node:24-bookworm-slim'
  if _o=$(eval_profile "$_base/neg" 2>&1); then _r=0; else _r=$?; fi
  if [ "$_r" = 1 ] && printf '%s' "$_o" | grep -q '!= CI'; then
    echo "PASS: selftest — (2) load-bearing negative: diverging floor fails (rc 1, '!= CI' printed)"
  else
    echo "FAIL: selftest — (2) load-bearing negative: rc=$_r out=[$_o]"; _sf=1
  fi

  # (2b) LOAD-BEARING container negative — floor >=20 == CI 20 BUT the container base is node:22 -> rc 1
  #      AND 'container .* != CI'. This is the discriminating guard for the THIRD equality leg (== container):
  #      without it a broken container check (e.g. `if false`) passes the selftest, because every real
  #      container currently matches CI. Asserts BOTH (a bare exit-code check can be faked by an unrelated
  #      failure) and holds floor==CI so ONLY the container comparison can produce the FAIL.
  _sf_mkpkg "$_base/cont/scaffold" '>=20'; _sf_mkci "$_base/cont" 'node-version' '20'; _sf_mkdocker "$_base/cont" 'node:22-bookworm-slim'
  if _o=$(eval_profile "$_base/cont" 2>&1); then _r=0; else _r=$?; fi
  if [ "$_r" = 1 ] && printf '%s' "$_o" | grep -q 'container .* != CI'; then
    echo "PASS: selftest — (2b) container negative: floor==CI but divergent container fails (rc 1, 'container != CI' printed)"
  else
    echo "FAIL: selftest — (2b) container negative: rc=$_r out=[$_o]"; _sf=1
  fi

  # (3a) N/A-EARNED — no manifest at all -> N/A + reason, rc 0 (never a forced number).
  _sf_mkci "$_base/na" 'python-version' '3.12'
  if _o=$(eval_profile "$_base/na" 2>&1); then _r=0; else _r=$?; fi
  if [ "$_r" = 0 ] && printf '%s' "$_o" | grep -q '^N/A:.*no declared floor'; then
    echo "PASS: selftest — (3a) N/A earned: absent floor key prints N/A + reason (rc 0)"
  else
    echo "FAIL: selftest — (3a) N/A earned: rc=$_r out=[$_o]"; _sf=1
  fi

  # (3b) N/A must be EARNED — a manifest present-but-unparseable is a FAIL, not a green N/A.
  _sf_mkpkg "$_base/garbled/scaffold" 'garbage-not-a-version'; _sf_mkci "$_base/garbled" 'node-version' '20'
  if _o=$(eval_profile "$_base/garbled" 2>&1); then _r=0; else _r=$?; fi
  if [ "$_r" = 1 ] && printf '%s' "$_o" | grep -qi 'unparseable' && ! printf '%s' "$_o" | grep -q '^N/A:'; then
    echo "PASS: selftest — (3b) garbled manifest FAILs (unparseable), not a green N/A (rc 1)"
  else
    echo "FAIL: selftest — (3b) garbled manifest: rc=$_r out=[$_o]"; _sf=1
  fi

  # (4) fail-closed — an empty fleet root -> run_fleet rc 1 with 'no profiles found' (never vacuous pass).
  _empty=$(mktemp -d)
  if _o=$(run_fleet "$_empty" 2>&1); then _r=0; else _r=$?; fi
  rm -rf "$_empty"
  if [ "$_r" = 1 ] && printf '%s' "$_o" | grep -q 'no profiles found'; then
    echo "PASS: selftest — (4) fail-closed: empty fleet root fails (rc 1, 'no profiles found')"
  else
    echo "FAIL: selftest — (4) fail-closed empty fleet: rc=$_r out=[$_o]"; _sf=1
  fi

  # (5) ENFORCEMENT negative (CP-7 K3) — a scaffold that DECLARES engines.node but ships no
  # engine-strict .npmrc must FAIL, even when floor == CI == container. Without this leg the
  # enforcement rule is inert: both real .npmrc files could be deleted and every gate stay green,
  # which is precisely the declared-but-unenforced shape the rule exists to end.
  _sf_mkpkg "$_base/noenf/scaffold" '>=20' no-npmrc
  _sf_mkci "$_base/noenf" 'node-version' '20'; _sf_mkdocker "$_base/noenf" 'node:20-bookworm-slim'
  if _o=$(eval_profile "$_base/noenf" 2>&1); then _r=0; else _r=$?; fi
  if [ "$_r" = 1 ] && printf '%s' "$_o" | grep -q 'does not ENFORCE it'; then
    echo "PASS: selftest — (5) declared-but-unenforced floor FAILs (rc 1, 'does not ENFORCE it')"
  else
    echo "FAIL: selftest — (5) missing engine-strict NOT caught: rc=$_r out=[$_o]"; _sf=1
  fi

  rm -rf "$_base"; trap - EXIT INT TERM
  if [ "$_sf" = 0 ]; then
    echo "runtime-floor-coherent --selftest: OK"; return 0
  fi
  echo "runtime-floor-coherent --selftest: FAIL"; return 1
}

# ── entrypoint ───────────────────────────────────────────────────────────────────────────────────
case "${1:-}" in
  --selftest) selftest; exit $? ;;
  "") : ;;
  *) echo "usage: runtime-floor-coherent.sh [--selftest]" >&2; exit 2 ;;
esac

if run_fleet "profiles"; then
  echo "OK: every profile's declared runtime floor == CI == container (or earned-N/A)"
  exit 0
else
  echo "FAIL: a profile's runtime floor diverges from its CI / container (see above)"
  exit 1
fi
