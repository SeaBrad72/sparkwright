#!/bin/sh
# secret-scan-wired.sh — the kit's OWN CI runs a real secret-scan gate (recovery slice A8 / T1-09).
# The kit's DoD names secret-scan a required, non-negotiable, unwaivable gate, yet the kit's own
# meta-CI (.github/workflows/ci.yml) ran none — the sharpest declared>=enforced gap, on the kit itself.
# This check closes it in two independent ways:
#   (default)      LIVE WIRING — assert .github/workflows/ci.yml carries the pinned `gitleaks dir`
#                  secret-scan step (the invocation + `id: gate-secret-scan` + the pinned version).
#                  Gitleaks-INDEPENDENT (pure grep), so it is portable and runs in the offline
#                  aggregate (conformance/verify.sh --require) and the non-vacuity sweep.
#   --selftest     the WIRING checker's OWN logic over runtime fixtures (POS + load-bearing NEG).
#                  Gitleaks-INDEPENDENT — this is the arm the non-vacuity mutation sweep exercises,
#                  so a neutered FAIL path in check_wired() is KILLED by a surviving NEG fixture.
#   --scan-selftest  the SCANNER-LIVENESS proof: plant a SYNTHETIC private key (random body, generated
#                  at runtime — never a real or realistic credential) into a mktemp -d, run the SAME
#                  `gitleaks dir` invocation, and assert a finding (rc!=0); a CLEAN temp dir is the
#                  positive anchor (rc 0 / no finding). Requires gitleaks; FAILS CLOSED (rc 2
#                  UNVERIFIED) when gitleaks is absent — never a silent pass. Lives under its OWN flag
#                  (not --selftest) precisely because it is gitleaks-DEPENDENT: it runs in the dedicated
#                  `secret-scan` CI job (which downloads the pinned binary), NOT in the gitleaks-free
#                  offline aggregate or mutation sweep, where an absent binary would be an UNVERIFIED red.
#
# Usage: sh conformance/secret-scan-wired.sh                # live wiring check on the real ci.yml
#        sh conformance/secret-scan-wired.sh --selftest     # wiring-checker fixtures (gitleaks-free)
#        sh conformance/secret-scan-wired.sh --scan-selftest# planted-secret liveness (needs gitleaks)
# Exit:  0 = pass · 1 = fail (missing/weak wiring, or fixture expectation unmet) · 2 = usage / UNVERIFIED.
#
# HONEST CEILING: gitleaks catches KNOWN secret patterns; it is not a proof of no secrets — a
# novel-format credential, or one outside its rules, passes. --scan-selftest proves the scanner RUNS
# and CAN red, not that the kit's tree is secret-free. This is the same ceiling every scanner carries,
# and the profiles say so. The wiring check proves the STEP is present, not that any given CI run scanned.
#
# What it changes: read-only — greps a workflow file; --scan-selftest writes ONLY inside a mktemp -d
#   it removes on exit (a synthetic, runtime-random fixture). Mutates nothing tracked.
# Guardrails: read-only on the repo; no network; trap-cleans its temp dir; never emits or commits a
#   real secret (planted body is /dev/urandom base64); fails closed (rc 2) if gitleaks is unavailable.
set -eu

# The pinned scanner the profiles ship (parity is the point — neutrality). Kept in lockstep with
# profiles/*/ci.yml and the kit's own secret-scan job; drift between them is a routed maintenance item.
GL_VER="8.24.3"
CI_FILE="${KIT_CI_FILE:-.github/workflows/ci.yml}"

# check_wired <workflow-file> -> 0 if it carries the pinned gitleaks secret-scan step, else 1.
# Comment-stripped first, so a token that appears only in a COMMENT never satisfies the wiring.
# The `_fail=1` accumulator is the mutation-sweep's target: neuter it and a NEG fixture wrongly passes.
check_wired() {
  _wf=$1; _fail=0
  if [ ! -f "$_wf" ]; then
    echo "FAIL: secret-scan wiring — workflow file not found: $_wf"
    return 1
  fi
  _body=$(sed 's/#.*//' "$_wf")
  printf '%s\n' "$_body" | grep -Eq 'gitleaks[[:space:]]+dir[[:space:]]+\.' \
    || { echo "FAIL: $_wf has no 'gitleaks dir .' secret-scan invocation"; _fail=1; }
  printf '%s\n' "$_body" | grep -Eq 'id:[[:space:]]*gate-secret-scan' \
    || { echo "FAIL: $_wf has no 'id: gate-secret-scan' step"; _fail=1; }
  printf '%s\n' "$_body" | grep -Fq "$GL_VER" \
    || { echo "FAIL: $_wf does not pin gitleaks to $GL_VER (profile parity)"; _fail=1; }
  if [ "$_fail" = 0 ]; then
    echo "OK: $_wf carries the pinned (v$GL_VER) 'gitleaks dir' secret-scan step (id: gate-secret-scan)"
    return 0
  fi
  return 1
}

# resolve_gitleaks -> prints the gitleaks binary path, or nothing. GITLEAKS_BIN wins (the dedicated CI
# job points it at the pinned /tmp/gitleaks it downloaded); else the PATH copy (a dev machine).
resolve_gitleaks() {
  if [ -n "${GITLEAKS_BIN:-}" ] && [ -x "${GITLEAKS_BIN}" ]; then
    printf '%s\n' "$GITLEAKS_BIN"
  else
    command -v gitleaks 2>/dev/null || true
  fi
}

selftest() {
  sf=0; d=$(mktemp -d); trap 'rm -rf "$d"' EXIT INT TERM

  # POS anchor: a workflow carrying the invocation + id + pinned version -> PASS.
  {
    printf 'jobs:\n  secret-scan:\n    steps:\n'
    printf '      - name: Secret scan\n        id: gate-secret-scan\n'
    printf '        run: |\n          GL_VER=%s\n          /tmp/gitleaks dir . --no-banner --redact\n' "$GL_VER"
  } > "$d/pos.yml"
  if check_wired "$d/pos.yml" >/dev/null 2>&1; then
    echo "selftest PASS: fully-wired workflow -> PASS"
  else echo "selftest FAIL: fully-wired workflow wrongly failed"; sf=1; fi

  # NEG 1 (load-bearing — the accumulator target): the invocation is MISSING -> FAIL.
  # A mutation that neuters check_wired's `_fail=1` makes this fixture wrongly PASS, so the mutant
  # is KILLED here. The file EXISTS (not the not-found path), isolating the invocation requirement.
  {
    printf 'jobs:\n  build:\n    steps:\n'
    printf '      - name: Secret scan\n        id: gate-secret-scan\n'
    printf '        run: |\n          GL_VER=%s\n          echo no scan here\n' "$GL_VER"
  } > "$d/neg-noinvoke.yml"
  if _o1=$(check_wired "$d/neg-noinvoke.yml" 2>&1); then _r1=0; else _r1=$?; fi
  if [ "$_r1" -ne 0 ] && printf '%s' "$_o1" | grep -qF "no 'gitleaks dir .'"; then
    echo "selftest PASS: missing invocation -> FAIL (names the gap)"
  else echo "selftest FAIL: missing invocation not caught (rc=$_r1): $_o1"; sf=1; fi

  # NEG 2 (load-bearing): the pinned VERSION is absent (drift/unpinned) -> FAIL.
  {
    printf 'jobs:\n  secret-scan:\n    steps:\n'
    printf '      - name: Secret scan\n        id: gate-secret-scan\n'
    printf '        run: |\n          gitleaks dir . --no-banner --redact\n'
  } > "$d/neg-nover.yml"
  if _o2=$(check_wired "$d/neg-nover.yml" 2>&1); then _r2=0; else _r2=$?; fi
  if [ "$_r2" -ne 0 ] && printf '%s' "$_o2" | grep -qF "does not pin gitleaks"; then
    echo "selftest PASS: unpinned version -> FAIL (names the gap)"
  else echo "selftest FAIL: unpinned version not caught (rc=$_r2): $_o2"; sf=1; fi

  # NEG 3 (load-bearing): the step id is MISSING -> FAIL (not nameable as a required context).
  {
    printf 'jobs:\n  secret-scan:\n    steps:\n'
    printf '      - name: Secret scan\n'
    printf '        run: |\n          GL_VER=%s\n          gitleaks dir . --no-banner --redact\n' "$GL_VER"
  } > "$d/neg-noid.yml"
  if _o3=$(check_wired "$d/neg-noid.yml" 2>&1); then _r3=0; else _r3=$?; fi
  if [ "$_r3" -ne 0 ] && printf '%s' "$_o3" | grep -qF "no 'id: gate-secret-scan'"; then
    echo "selftest PASS: missing step id -> FAIL (names the gap)"
  else echo "selftest FAIL: missing step id not caught (rc=$_r3): $_o3"; sf=1; fi

  # NEG 4 (comment-strip is load-bearing): the invocation appears ONLY in a comment -> must FAIL.
  {
    printf 'jobs:\n  secret-scan:\n    steps:\n'
    printf '      - name: Secret scan\n        id: gate-secret-scan\n'
    printf '        run: |\n          GL_VER=%s\n          # gitleaks dir . --no-banner --redact\n          echo ok\n' "$GL_VER"
  } > "$d/neg-comment.yml"
  if check_wired "$d/neg-comment.yml" >/dev/null 2>&1; then
    echo "selftest FAIL: commented-out invocation wrongly satisfied the wiring"; sf=1
  else echo "selftest PASS: commented-out invocation does NOT satisfy the wiring"; fi

  # NEG 5: a missing file -> FAIL (fail-closed, never a vacuous pass on an absent workflow).
  if check_wired "$d/does-not-exist.yml" >/dev/null 2>&1; then
    echo "selftest FAIL: absent workflow wrongly passed"; sf=1
  else echo "selftest PASS: absent workflow -> FAIL (fail-closed)"; fi

  if [ "$sf" -eq 0 ]; then echo "OK: secret-scan-wired selftest (wiring checker is load-bearing)"; exit 0
  else echo "FAIL: secret-scan-wired selftest"; exit 1; fi
}

# scan_selftest — the SCANNER-LIVENESS proof. Needs gitleaks; FAILS CLOSED (rc 2) if it is absent.
scan_selftest() {
  _gl=$(resolve_gitleaks)
  if [ -z "$_gl" ]; then
    echo "UNVERIFIED: gitleaks is not available (set GITLEAKS_BIN or install gitleaks)." >&2
    echo "The planted-secret liveness proof cannot run; refusing to report a pass it did not earn." >&2
    exit 2
  fi
  sf=0; d=$(mktemp -d); trap 'rm -rf "$d"' EXIT INT TERM

  # POSITIVE ANCHOR: a CLEAN temp dir must yield NO finding (rc 0). If a clean dir reddened, the
  # negative below would be meaningless (always-red), so this anchor is what makes it discriminating.
  set +e
  "$_gl" dir "$d" --no-banner --redact >/dev/null 2>&1
  _clean_rc=$?
  set -e
  if [ "$_clean_rc" -eq 0 ]; then
    echo "scan-selftest PASS: clean dir -> no finding (rc 0)"
  else echo "scan-selftest FAIL: clean dir unexpectedly reddened (rc=$_clean_rc)"; sf=1; fi

  # LOAD-BEARING NEGATIVE: plant a SYNTHETIC private key (random body, runtime-generated — NEVER a
  # real credential) and assert the SAME invocation reds (rc != 0 / a finding).
  # ⚠️ The PEM header/footer markers are ASSEMBLED at runtime (`%s`-substituted) so the marker string
  # never appears WHOLE anywhere in this committed source — NOT in this comment either. gitleaks'
  # private-key rule matches the BEGIN marker alone, so any whole occurrence (even in a comment) would
  # flag THIS file and red the kit's own secret-scan job on every run, defeating the slice's purpose
  # (review Critical 1, and its own recurrence in the first fix's comment). Keeps the design's
  # "real tree scans clean, no allowlist needed" premise true.
  {
    printf -- '-----BEGIN %s KEY-----\n' 'PRIVATE'
    head -c 400 /dev/urandom | base64
    printf -- '\n-----END %s KEY-----\n' 'PRIVATE'
  } > "$d/planted.key"
  set +e
  "$_gl" dir "$d" --no-banner --redact >/dev/null 2>&1
  _planted_rc=$?
  set -e
  if [ "$_planted_rc" -ne 0 ]; then
    echo "scan-selftest PASS: planted synthetic secret -> finding (rc=$_planted_rc, scanner reddened)"
  else echo "scan-selftest FAIL: planted secret NOT caught (rc 0) — the scanner is vacuous"; sf=1; fi

  if [ "$sf" -eq 0 ]; then echo "OK: secret-scan-wired scan-selftest (scanner runs and can red)"; exit 0
  else echo "FAIL: secret-scan-wired scan-selftest"; exit 1; fi
}

# --selftest / --scan-selftest dispatch — BEFORE the usage check, or the flag is read as a filename.
case "${1:-}" in
  --selftest) selftest; exit $? ;;
  --scan-selftest) scan_selftest; exit $? ;;
esac

case "${1:-}" in
  "")
    if check_wired "$CI_FILE"; then exit 0; else
      echo "See DEVELOPMENT-STANDARDS.md §14 (secret-scan is a required, unwaivable gate) and the A8 design." >&2
      exit 1
    fi
    ;;
  *) echo "usage: secret-scan-wired.sh [--selftest | --scan-selftest]" >&2; exit 2 ;;
esac
