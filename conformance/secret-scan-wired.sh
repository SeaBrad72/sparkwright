#!/bin/sh
# secret-scan-wired.sh — the kit's OWN CI runs a real secret-scan gate (recovery slice A8 / T1-09),
# and that scan covers HISTORY, not just the working tree at HEAD (SECRET-SCAN-HISTORY-NOT-SCANNED).
# This check closes both gaps in four independent ways:
#   (default)      LIVE WIRING + PARITY — assert .github/workflows/ci.yml carries the pinned
#                  `gitleaks git` secret-scan step (the invocation + `id: gate-secret-scan` + the
#                  pinned version), AND that every parity site (profiles/*/ci.yml, the fixture
#                  ci.ymls, conformance/incept-manifests/*.txt, scripts/new-profile.sh) has been
#                  swapped from `gitleaks dir` (working-tree-only) to `gitleaks git` (full history)
#                  — a byte lock, so a partial swap or a regression back to `dir` is caught.
#                  Gitleaks-INDEPENDENT (pure grep), so it is portable and runs in the offline
#                  aggregate (conformance/verify.sh --require) and the non-vacuity sweep.
#   --selftest     the WIRING checker's OWN logic over runtime fixtures (POS + load-bearing NEG).
#                  Gitleaks-INDEPENDENT — this is the arm the non-vacuity mutation sweep exercises,
#                  so a neutered FAIL path in check_wired() is KILLED by a surviving NEG fixture.
#   --scan-selftest  the SCANNER-LIVENESS proof: plant a SYNTHETIC private key (random body, generated
#                  at runtime — never a real or realistic credential) into a throwaway git repo, run the
#                  SAME `gitleaks git` invocation, and assert a finding (rc!=0); a clean repo is the
#                  positive anchor (rc 0 / no finding). Requires gitleaks; FAILS CLOSED (rc 2
#                  UNVERIFIED) when gitleaks is absent — never a silent pass.
#   --live         the HISTORY-COVERAGE non-vacuity anchor (SECRET-SCAN-HISTORY-NOT-SCANNED): plants a
#                  synthetic secret, commits it, then REMOVES it in a second commit (secret only in
#                  history, not at HEAD) — `gitleaks dir` (the old invocation) misses it; `gitleaks git`
#                  with the shipped .gitleaks.toml still catches it. Also proves the promotion-note
#                  `approval-token: "…"` grammar is allowlisted while an identical secret OUTSIDE that
#                  grammar still reds, and that a mutant config with the `[extend]` stanza dropped would
#                  wrongly pass the history-secret case (proving `[extend] useDefault = true` is
#                  load-bearing, not decorative). Leg 5 proves the allowlist regex is LINE-ANCHORED,
#                  not a bare substring match: a real secret with `approval-token: "…"` appended on the
#                  SAME line must still red (a well-formed note line, on its own, still passes).
#                  Requires gitleaks; FAILS CLOSED (rc 2) if absent.
#
# Usage: sh conformance/secret-scan-wired.sh                # live wiring + parity check
#        sh conformance/secret-scan-wired.sh --selftest     # wiring-checker fixtures (gitleaks-free)
#        sh conformance/secret-scan-wired.sh --scan-selftest# planted-secret liveness (needs gitleaks)
#        sh conformance/secret-scan-wired.sh --live         # history-coverage liveness (needs gitleaks)
# Exit:  0 = pass · 1 = fail (missing/weak wiring, or fixture expectation unmet) · 2 = usage / UNVERIFIED.
#
# HONEST CEILING: gitleaks catches KNOWN secret patterns; it is not a proof of no secrets — a
# novel-format credential, or one outside its rules, passes. The `.gitleaks.toml` allowlist anchors on
# the exact emitted grammar via a LINE-ANCHORED regex (`^...(- )?approval-token: "[^"]*"...$`,
# scripts/promotion-verify.sh:593) — a secret inside the quotes of a well-formed note line is masked
# by design (docs/architecture/2026-09-09-control-plane-coverage-design.md §7, R-5); a secret sharing
# a line with, but outside, that grammar still reds (leg 5 below). --scan-selftest / --live prove the
# scanner RUNS and CAN red, not that the kit's tree is secret-free. The wiring check proves the STEP
# is present, not that any given CI run scanned.
#
# What it changes: read-only — greps workflow/manifest files; --scan-selftest / --live write ONLY
#   inside a mktemp -d they remove on exit (synthetic, runtime-random fixtures). Mutates nothing tracked.
# Guardrails: read-only on the repo; no network; trap-cleans its temp dirs; never emits or commits a
#   real secret (planted bodies are /dev/urandom base64); fails closed (rc 2) if gitleaks is unavailable.
set -eu

# The pinned scanner the profiles ship (parity is the point — neutrality). Kept in lockstep with
# profiles/*/ci.yml and the kit's own secret-scan job; drift between them is a routed maintenance item.
GL_VER="8.24.3"
CI_FILE="${KIT_CI_FILE:-.github/workflows/ci.yml}"
GL_TOML="${KIT_GITLEAKS_TOML:-.gitleaks.toml}"

# The parity surface (design §3 / plan Task 2): every site that must run `gitleaks git .`, never
# `gitleaks dir .`. Two buckets — files carrying the LITERAL invocation, and the incept manifests
# that carry it as an `assert:` regex string instead.
_PARITY_INVOCATION_FILES="
.github/workflows/ci.yml
profiles/data-engineering/ci.yml
profiles/dotnet/ci.yml
profiles/go/ci.yml
profiles/java-spring/ci.yml
profiles/kotlin/ci.yml
profiles/ml/ci.yml
profiles/python/ci.yml
profiles/rust/ci.yml
profiles/terraform/ci.yml
profiles/typescript-node/ci.yml
conformance/fixtures/bad-agent-trace/ci.yml
conformance/fixtures/bad-db-postgres/ci.yml
conformance/fixtures/bad-provenance-ungated/ci.yml
conformance/fixtures/bad-sast-narrowed/ci.yml
conformance/fixtures/bad-secret-gitignore/ci.yml
conformance/fixtures/good-nodb/ci.yml
conformance/fixtures/good/ci.yml
scripts/new-profile.sh
"
_PARITY_MANIFEST_FILES="
conformance/incept-manifests/data-engineering.txt
conformance/incept-manifests/dotnet.txt
conformance/incept-manifests/go.txt
conformance/incept-manifests/java-spring.txt
conformance/incept-manifests/kotlin.txt
conformance/incept-manifests/ml.txt
conformance/incept-manifests/python.txt
conformance/incept-manifests/rust.txt
conformance/incept-manifests/terraform.txt
conformance/incept-manifests/typescript-node.txt
"

# _job_block_has_fetch_depth_0 <body-text> <job-name> -> 0 iff the <job-name> job's OWN block (from
# its 2-space `<job>:` header to the next 2-space job header, or EOF) carries `fetch-depth: 0`, else 1
# (including "job not found"). Mirrors _agg_job_step_count's job-block extraction
# (conformance/ci-gates.sh:447-452) — a file-wide grep is too coarse: ci.yml carries 22 fetch-depth
# occurrences across its jobs, so a DIFFERENT job's `fetch-depth: 0` would satisfy a whole-file check
# while the secret-scan job's own checkout stayed shallow (security review, 2026-09-10).
_job_block_has_fetch_depth_0() {
  _jb_body=$1; _jb_job=$2
  _jb_start=$(printf '%s\n' "$_jb_body" | grep -n "^  ${_jb_job}:\$" | head -1 | cut -d: -f1)
  [ -n "$_jb_start" ] || return 1
  _jb_end=$(printf '%s\n' "$_jb_body" | awk -v s="$_jb_start" 'NR>s && /^  [A-Za-z0-9_-]+:$/{print NR; exit}')
  if [ -n "$_jb_end" ]; then
    printf '%s\n' "$_jb_body" | sed -n "${_jb_start},$((_jb_end - 1))p" | grep -Eq 'fetch-depth:[[:space:]]*0'
  else
    printf '%s\n' "$_jb_body" | sed -n "${_jb_start},\$p" | grep -Eq 'fetch-depth:[[:space:]]*0'
  fi
}

# check_wired <workflow-file> -> 0 if it carries the pinned gitleaks HISTORY secret-scan step, else 1.
# Comment-stripped first, so a token that appears only in a COMMENT never satisfies the wiring.
# The `_fail=1` accumulator is the mutation-sweep's target: neuter it and a NEG fixture wrongly passes.
check_wired() {
  _wf=$1; _fail=0
  if [ ! -f "$_wf" ]; then
    echo "FAIL: secret-scan wiring — workflow file not found: $_wf"
    return 1
  fi
  _body=$(sed 's/#.*//' "$_wf")
  printf '%s\n' "$_body" | grep -Eq 'gitleaks[[:space:]]+git[[:space:]]+\.' \
    || { echo "FAIL: $_wf has no 'gitleaks git .' secret-scan invocation (history mode)"; _fail=1; }
  printf '%s\n' "$_body" | grep -Eq 'id:[[:space:]]*gate-secret-scan' \
    || { echo "FAIL: $_wf has no 'id: gate-secret-scan' step"; _fail=1; }
  printf '%s\n' "$_body" | grep -Fq "$GL_VER" \
    || { echo "FAIL: $_wf does not pin gitleaks to $GL_VER (profile parity)"; _fail=1; }
  # Job-scoped (not file-wide): the secret-scan job's OWN checkout must carry fetch-depth: 0, not
  # merely SOME job in the file. See _job_block_has_fetch_depth_0 above.
  _job_block_has_fetch_depth_0 "$_body" "secret-scan" \
    || { echo "FAIL: $_wf's 'secret-scan' job does not carry 'fetch-depth: 0' on its own checkout (job-scoped; a different job's fetch-depth: 0 does not satisfy this)"; _fail=1; }
  if [ "$_fail" = 0 ]; then
    echo "OK: $_wf carries the pinned (v$GL_VER) 'gitleaks git' (history) secret-scan step (id: gate-secret-scan)"
    return 0
  fi
  return 1
}

# check_parity -> 0 if every parity site has been swapped to `gitleaks git` (never `gitleaks dir`),
# else 1. Gitleaks-independent (pure grep); this is the byte lock the design demands across the
# ~30-file parity surface, not just the one CI_FILE that check_wired covers.
check_parity() {
  _pfail=0
  # KIT-SELF CHECK (green-on-clone first-live-run, CONTROL-PLANE-COVERAGE 2026-09-10). Every parity
  # subject is KIT reference material: the kit's own ci.yml (export-ignored), the 10 profile
  # reference CIs (`profiles/*` — an adopter carries only their CHOSEN stack, so the others are
  # ABSENT on an adopter export), the kit's fixtures and incept-manifests. An adopter does not
  # maintain parity across the kit's profiles, so on an ADOPTER EXPORT this whole check is N/A — a
  # leg that FAILs on the pruned profiles would red every adopter's first push (measured: all ten
  # `profiles/*/ci.yml` read "parity site missing" on `adopter-export.sh --profile typescript-node`).
  # Detected by the TWIN-MARKER discriminator (adopter-census.sh:170, adopter-export-claims.sh:232):
  # BOTH kit-only export-ignored markers absent = an adopter export; a real kit tree keeps at least
  # one, so this cannot dark-gate the kit's own parity. The kit's CI selftest (markers present) still
  # runs the full check.
  if [ ! -f docs/ROADMAP-KIT.md ] && [ ! -f .github/workflows/golden-path.yml ]; then
    echo "N/A: profile parity is a kit-self check across the kit's own CI templates (ci.yml + profiles/*/ci.yml + fixtures + manifests); an adopter export does not carry the kit's profile reference set"
    return 0
  fi
  for _f in $_PARITY_INVOCATION_FILES; do
    [ -z "$_f" ] && continue
    if [ ! -f "$_f" ]; then
      echo "FAIL: parity site missing: $_f"; _pfail=1; continue
    fi
    if grep -Eq 'gitleaks[[:space:]]+dir[[:space:]]+\.' "$_f"; then
      echo "FAIL: $_f still invokes 'gitleaks dir .' (working-tree-only; history is not scanned)"
      _pfail=1
    fi
    if ! grep -Eq 'gitleaks[[:space:]]+git[[:space:]]+\.' "$_f"; then
      echo "FAIL: $_f has no 'gitleaks git .' invocation"
      _pfail=1
    fi
  done
  for _f in $_PARITY_MANIFEST_FILES; do
    [ -z "$_f" ] && continue
    if [ ! -f "$_f" ]; then
      echo "FAIL: parity manifest missing: $_f"; _pfail=1; continue
    fi
    if grep -Eq 'assert:[[:space:]]*present[[:space:]]+gitleaks[[:space:]]+dir' "$_f"; then
      echo "FAIL: $_f still asserts 'gitleaks dir' (working-tree-only)"
      _pfail=1
    fi
    if ! grep -Eq 'assert:[[:space:]]*present[[:space:]]+gitleaks[[:space:]]+git' "$_f"; then
      echo "FAIL: $_f has no 'assert: present gitleaks git' line"
      _pfail=1
    fi
  done
  if [ "$_pfail" = 0 ]; then
    echo "OK: profile parity — every secret-scan site runs 'gitleaks git' (history mode)"
    return 0
  fi
  return 1
}

# check_gitleaks_toml -> 0 if the shipped .gitleaks.toml carries the mandatory [extend] useDefault
# stanza (without it, gitleaks REPLACES the default ruleset with nothing but the allowlist, and every
# parity site greens on zero rules — design §3 S-5a), else 1.
check_gitleaks_toml() {
  if [ ! -f "$GL_TOML" ]; then
    echo "FAIL: $GL_TOML not found (required — the allowlist config the parity sites rely on)"
    return 1
  fi
  if ! grep -Eq '^\[extend\]' "$GL_TOML" || ! grep -Eq 'useDefault[[:space:]]*=[[:space:]]*true' "$GL_TOML"; then
    echo "FAIL: $GL_TOML is missing '[extend]' / 'useDefault = true' — it would replace the default ruleset with zero rules"
    return 1
  fi
  if grep -Eq '^\[\[allowlist\.paths?\]\]|^paths[[:space:]]*=' "$GL_TOML"; then
    echo "FAIL: $GL_TOML carries a paths-based allowlist — must be a line-targeted regex, never a path exclusion"
    return 1
  fi
  echo "OK: $GL_TOML carries [extend] useDefault = true"
  return 0
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

# _mk_repo <dir> — git-init a throwaway repo at a literal dir with a committer identity, no remote.
_mk_repo() {
  git -C "$1" init -q
  git -C "$1" config user.email "conformance@localhost"
  git -C "$1" config user.name "conformance"
}

selftest() {
  sf=0; d=$(mktemp -d); trap 'rm -rf "$d"' EXIT INT TERM

  # POS anchor: a workflow carrying the invocation + id + pinned version + fetch-depth -> PASS.
  {
    printf 'jobs:\n  secret-scan:\n    steps:\n'
    printf '      - uses: actions/checkout@x\n        with:\n          fetch-depth: 0\n'
    printf '      - name: Secret scan\n        id: gate-secret-scan\n'
    printf '        run: |\n          GL_VER=%s\n          /tmp/gitleaks git . --no-banner --redact\n' "$GL_VER"
  } > "$d/pos.yml"
  if check_wired "$d/pos.yml" >/dev/null 2>&1; then
    echo "selftest PASS: fully-wired workflow -> PASS"
  else echo "selftest FAIL: fully-wired workflow wrongly failed"; sf=1; fi

  # NEG 1 (load-bearing — the accumulator target): the invocation is MISSING -> FAIL.
  # A mutation that neuters check_wired's `_fail=1` makes this fixture wrongly PASS, so the mutant
  # is KILLED here. The file EXISTS (not the not-found path), isolating the invocation requirement.
  {
    printf 'jobs:\n  build:\n    steps:\n'
    printf '      - uses: actions/checkout@x\n        with:\n          fetch-depth: 0\n'
    printf '      - name: Secret scan\n        id: gate-secret-scan\n'
    printf '        run: |\n          GL_VER=%s\n          echo no scan here\n' "$GL_VER"
  } > "$d/neg-noinvoke.yml"
  if _o1=$(check_wired "$d/neg-noinvoke.yml" 2>&1); then _r1=0; else _r1=$?; fi
  if [ "$_r1" -ne 0 ] && printf '%s' "$_o1" | grep -qF "no 'gitleaks git .'"; then
    echo "selftest PASS: missing invocation -> FAIL (names the gap)"
  else echo "selftest FAIL: missing invocation not caught (rc=$_r1): $_o1"; sf=1; fi

  # NEG 1b (load-bearing — history regression): the invocation is the OLD `dir` (working-tree-only)
  # mode -> FAIL. Proves check_wired rejects a regression back to the pre-fix invocation.
  {
    printf 'jobs:\n  secret-scan:\n    steps:\n'
    printf '      - uses: actions/checkout@x\n        with:\n          fetch-depth: 0\n'
    printf '      - name: Secret scan\n        id: gate-secret-scan\n'
    printf '        run: |\n          GL_VER=%s\n          /tmp/gitleaks dir . --no-banner --redact\n' "$GL_VER"
  } > "$d/neg-dirmode.yml"
  if _o1b=$(check_wired "$d/neg-dirmode.yml" 2>&1); then _r1b=0; else _r1b=$?; fi
  if [ "$_r1b" -ne 0 ] && printf '%s' "$_o1b" | grep -qF "no 'gitleaks git .'"; then
    echo "selftest PASS: 'gitleaks dir' regression -> FAIL (names the gap)"
  else echo "selftest FAIL: 'gitleaks dir' regression not caught (rc=$_r1b): $_o1b"; sf=1; fi

  # NEG 2 (load-bearing): the pinned VERSION is absent (drift/unpinned) -> FAIL.
  {
    printf 'jobs:\n  secret-scan:\n    steps:\n'
    printf '      - uses: actions/checkout@x\n        with:\n          fetch-depth: 0\n'
    printf '      - name: Secret scan\n        id: gate-secret-scan\n'
    printf '        run: |\n          gitleaks git . --no-banner --redact\n'
  } > "$d/neg-nover.yml"
  if _o2=$(check_wired "$d/neg-nover.yml" 2>&1); then _r2=0; else _r2=$?; fi
  if [ "$_r2" -ne 0 ] && printf '%s' "$_o2" | grep -qF "does not pin gitleaks"; then
    echo "selftest PASS: unpinned version -> FAIL (names the gap)"
  else echo "selftest FAIL: unpinned version not caught (rc=$_r2): $_o2"; sf=1; fi

  # NEG 3 (load-bearing): the step id is MISSING -> FAIL (not nameable as a required context).
  {
    printf 'jobs:\n  secret-scan:\n    steps:\n'
    printf '      - uses: actions/checkout@x\n        with:\n          fetch-depth: 0\n'
    printf '      - name: Secret scan\n'
    printf '        run: |\n          GL_VER=%s\n          gitleaks git . --no-banner --redact\n' "$GL_VER"
  } > "$d/neg-noid.yml"
  if _o3=$(check_wired "$d/neg-noid.yml" 2>&1); then _r3=0; else _r3=$?; fi
  if [ "$_r3" -ne 0 ] && printf '%s' "$_o3" | grep -qF "no 'id: gate-secret-scan'"; then
    echo "selftest PASS: missing step id -> FAIL (names the gap)"
  else echo "selftest FAIL: missing step id not caught (rc=$_r3): $_o3"; sf=1; fi

  # NEG 4 (comment-strip is load-bearing): the invocation appears ONLY in a comment -> must FAIL.
  {
    printf 'jobs:\n  secret-scan:\n    steps:\n'
    printf '      - uses: actions/checkout@x\n        with:\n          fetch-depth: 0\n'
    printf '      - name: Secret scan\n        id: gate-secret-scan\n'
    printf '        run: |\n          GL_VER=%s\n          # gitleaks git . --no-banner --redact\n          echo ok\n' "$GL_VER"
  } > "$d/neg-comment.yml"
  if check_wired "$d/neg-comment.yml" >/dev/null 2>&1; then
    echo "selftest FAIL: commented-out invocation wrongly satisfied the wiring"; sf=1
  else echo "selftest PASS: commented-out invocation does NOT satisfy the wiring"; fi

  # NEG 5: a missing file -> FAIL (fail-closed, never a vacuous pass on an absent workflow).
  if check_wired "$d/does-not-exist.yml" >/dev/null 2>&1; then
    echo "selftest FAIL: absent workflow wrongly passed"; sf=1
  else echo "selftest PASS: absent workflow -> FAIL (fail-closed)"; fi

  # NEG 6 (load-bearing): fetch-depth: 0 is MISSING -> FAIL (a shallow checkout under `git` mode
  # scans one commit and reports green — the byte lock design §3 S-5c demands).
  {
    printf 'jobs:\n  secret-scan:\n    steps:\n'
    printf '      - uses: actions/checkout@x\n'
    printf '      - name: Secret scan\n        id: gate-secret-scan\n'
    printf '        run: |\n          GL_VER=%s\n          gitleaks git . --no-banner --redact\n' "$GL_VER"
  } > "$d/neg-nodepth.yml"
  if _o6=$(check_wired "$d/neg-nodepth.yml" 2>&1); then _r6=0; else _r6=$?; fi
  if [ "$_r6" -ne 0 ] && printf '%s' "$_o6" | grep -qF "fetch-depth: 0"; then
    echo "selftest PASS: missing fetch-depth: 0 -> FAIL (names the gap)"
  else echo "selftest FAIL: missing fetch-depth: 0 not caught (rc=$_r6): $_o6"; sf=1; fi

  # NEG 7 (load-bearing — job-scoping, security review 2026-09-10): fetch-depth: 0 is present
  # ELSEWHERE in the file (a different job, both BEFORE and AFTER the secret-scan job header), but
  # the secret-scan job's OWN checkout is fetch-depth: 1 (shallow) -> must still FAIL. A file-wide
  # grep would wrongly PASS this (ci.yml carries 22 fetch-depth occurrences); the job-scoped check
  # must not be fooled by a sibling job's correct setting.
  {
    printf 'jobs:\n  other-job:\n    steps:\n'
    printf '      - uses: actions/checkout@x\n        with:\n          fetch-depth: 0\n'
    printf '  secret-scan:\n    steps:\n'
    printf '      - uses: actions/checkout@x\n        with:\n          fetch-depth: 1\n'
    printf '      - name: Secret scan\n        id: gate-secret-scan\n'
    printf '        run: |\n          GL_VER=%s\n          gitleaks git . --no-banner --redact\n' "$GL_VER"
    printf '  trailing-job:\n    steps:\n'
    printf '      - uses: actions/checkout@x\n        with:\n          fetch-depth: 0\n'
  } > "$d/neg-wrongjobdepth.yml"
  if _o7=$(check_wired "$d/neg-wrongjobdepth.yml" 2>&1); then _r7=0; else _r7=$?; fi
  if [ "$_r7" -ne 0 ] && printf '%s' "$_o7" | grep -qF "job-scoped"; then
    echo "selftest PASS: sibling job's fetch-depth: 0 does NOT satisfy the secret-scan job's own shallow checkout -> FAIL (job-scoped, names the gap)"
  else echo "selftest FAIL: job-scoping not enforced — a sibling job's fetch-depth: 0 wrongly satisfied the check (rc=$_r7): $_o7"; sf=1; fi

  # --- check_parity fixtures (gitleaks-independent) ---
  # POS: every real parity site in the repo today has already been swapped -> PASS.
  if check_parity >/dev/null 2>&1; then
    echo "selftest PASS: check_parity -> PASS on the real repo's parity sites"
  else echo "selftest FAIL: check_parity wrongly failed on the real repo"; sf=1; fi

  # --- check_gitleaks_toml fixtures ---
  {
    printf 'title = "t"\n\n[extend]\nuseDefault = true\n\n[allowlist]\nregexTarget = "line"\nregexes = [\x27x\x27]\n'
  } > "$d/good.toml"
  GL_TOML="$d/good.toml"
  if check_gitleaks_toml >/dev/null 2>&1; then
    echo "selftest PASS: .gitleaks.toml with [extend] useDefault -> PASS"
  else echo "selftest FAIL: valid .gitleaks.toml wrongly failed"; sf=1; fi

  {
    printf 'title = "t"\n\n[allowlist]\nregexTarget = "line"\nregexes = [\x27x\x27]\n'
  } > "$d/noextend.toml"
  GL_TOML="$d/noextend.toml"
  if check_gitleaks_toml >/dev/null 2>&1; then
    echo "selftest FAIL: .gitleaks.toml missing [extend] wrongly passed"; sf=1
  else echo "selftest PASS: .gitleaks.toml missing [extend] -> FAIL (names the gap)"; fi
  GL_TOML="${KIT_GITLEAKS_TOML:-.gitleaks.toml}"

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

  # POSITIVE ANCHOR: a CLEAN repo must yield NO finding (rc 0). If a clean repo reddened, the
  # negative below would be meaningless (always-red), so this anchor is what makes it discriminating.
  mkdir -p "$d/clean"
  _mk_repo "$d/clean"
  printf 'hello\n' > "$d/clean/readme.md"
  git -C "$d/clean" add -A
  git -C "$d/clean" commit -q -m init
  set +e
  "$_gl" git "$d/clean" --no-banner --redact >/dev/null 2>&1
  _clean_rc=$?
  set -e
  if [ "$_clean_rc" -eq 0 ]; then
    echo "scan-selftest PASS: clean repo -> no finding (rc 0)"
  else echo "scan-selftest FAIL: clean repo unexpectedly reddened (rc=$_clean_rc)"; sf=1; fi

  # LOAD-BEARING NEGATIVE: plant a SYNTHETIC private key (random body, runtime-generated — NEVER a
  # real credential), commit it, and assert the SAME invocation reds (rc != 0 / a finding).
  # ⚠️ The PEM header/footer markers are ASSEMBLED at runtime (`%s`-substituted) so the marker string
  # never appears WHOLE anywhere in this committed source — NOT in this comment either. gitleaks'
  # private-key rule matches the BEGIN marker alone, so any whole occurrence (even in a comment) would
  # flag THIS file and red the kit's own secret-scan job on every run, defeating the slice's purpose.
  mkdir -p "$d/planted"
  _mk_repo "$d/planted"
  {
    printf -- '-----BEGIN %s KEY-----\n' 'PRIVATE'
    head -c 400 /dev/urandom | base64
    printf -- '\n-----END %s KEY-----\n' 'PRIVATE'
  } > "$d/planted/fixture.txt"
  git -C "$d/planted" add -A
  git -C "$d/planted" commit -q -m "planted"
  set +e
  "$_gl" git "$d/planted" --no-banner --redact >/dev/null 2>&1
  _planted_rc=$?
  set -e
  if [ "$_planted_rc" -ne 0 ]; then
    echo "scan-selftest PASS: planted synthetic secret -> finding (rc=$_planted_rc, scanner reddened)"
  else echo "scan-selftest FAIL: planted secret NOT caught (rc 0) — the scanner is vacuous"; sf=1; fi

  if [ "$sf" -eq 0 ]; then echo "OK: secret-scan-wired scan-selftest (scanner runs and can red)"; exit 0
  else echo "FAIL: secret-scan-wired scan-selftest"; exit 1; fi
}

# live — the HISTORY-COVERAGE non-vacuity anchor (SECRET-SCAN-HISTORY-NOT-SCANNED). Needs gitleaks
# AND the shipped $GL_TOML; FAILS CLOSED (rc 2) if either is absent.
live() {
  _gl=$(resolve_gitleaks)
  if [ -z "$_gl" ]; then
    echo "UNVERIFIED: gitleaks is not available (set GITLEAKS_BIN or install gitleaks)." >&2
    echo "The history-coverage liveness proof cannot run; refusing to report a pass it did not earn." >&2
    exit 2
  fi
  if [ ! -f "$GL_TOML" ]; then
    echo "UNVERIFIED: $GL_TOML not found — the live check needs the shipped allowlist config." >&2
    exit 2
  fi
  _gltoml_abs=$(cd "$(dirname "$GL_TOML")" && pwd)/$(basename "$GL_TOML")
  sf=0; d=$(mktemp -d); trap 'rm -rf "$d"' EXIT INT TERM

  # --- 1) LIVENESS ANCHOR: a clean repo passes under `git` mode + the shipped config. ---
  mkdir -p "$d/clean"
  _mk_repo "$d/clean"
  printf 'hello\n' > "$d/clean/readme.md"
  git -C "$d/clean" add -A
  git -C "$d/clean" commit -q -m init
  set +e
  "$_gl" git "$d/clean" --config "$_gltoml_abs" --no-banner --redact >/dev/null 2>&1
  _r_clean=$?
  set -e
  if [ "$_r_clean" -eq 0 ]; then
    echo "live PASS: clean repo -> no finding (rc 0)"
  else echo "live FAIL: clean repo unexpectedly reddened (rc=$_r_clean)"; sf=1; fi

  # --- 2) LOAD-BEARING NEGATIVE: a synthetic secret committed, THEN REMOVED (only in history, not
  # at HEAD). The OLD invocation (`gitleaks dir`, working-tree-only) MISSES this — that is the hole
  # this row closes. The NEW invocation (`gitleaks git`, history mode) + shipped config MUST catch it. ---
  mkdir -p "$d/hist"
  _mk_repo "$d/hist"
  {
    printf -- '-----BEGIN %s KEY-----\n' 'PRIVATE'
    head -c 400 /dev/urandom | base64
    printf -- '\n-----END %s KEY-----\n' 'PRIVATE'
  } > "$d/hist/fixture.txt"
  git -C "$d/hist" add -A
  git -C "$d/hist" commit -q -m "oops secret"
  git -C "$d/hist" rm -q fixture.txt
  git -C "$d/hist" commit -q -m "remove secret"

  set +e
  "$_gl" dir "$d/hist" --no-banner --redact >/dev/null 2>&1
  _r_dir=$?
  set -e
  if [ "$_r_dir" -eq 0 ]; then
    echo "live PASS (documents the hole): 'gitleaks dir' (working-tree-only) misses the removed history secret (rc 0)"
  else echo "live NOTE: 'gitleaks dir' unexpectedly caught the removed secret (rc=$_r_dir) — hole not reproduced"; fi

  set +e
  "$_gl" git "$d/hist" --config "$_gltoml_abs" --no-banner --redact >/dev/null 2>&1
  _r_git=$?
  set -e
  if [ "$_r_git" -ne 0 ]; then
    echo "live PASS: 'gitleaks git' (history mode) + shipped config catches the removed secret (rc=$_r_git)"
  else echo "live FAIL: history-mode scan did NOT catch a secret committed-then-removed — the gap is still open"; sf=1; fi

  # --- 3) The promotion-note `approval-token: "…"` grammar is allowlisted; an identical secret
  # OUTSIDE that grammar still reds (proves the allowlist is line-targeted, not blanket). ---
  mkdir -p "$d/note"
  _mk_repo "$d/note"
  {
    printf 'record: promotion GO (approve->execute->log)\n'
    printf 'approved-sha: abc123\n'
    printf 'approval-token: "%s"\n' "$(head -c 40 /dev/urandom | base64 | tr -d '\n')"
    printf 'basis: none\n'
  } > "$d/note/promotion-log.md"
  git -C "$d/note" add -A
  git -C "$d/note" commit -q -m "promotion note"
  set +e
  "$_gl" git "$d/note" --config "$_gltoml_abs" --no-banner --redact >/dev/null 2>&1
  _r_note=$?
  set -e
  if [ "$_r_note" -eq 0 ]; then
    echo "live PASS: promotion-note approval-token field is allowlisted (rc 0)"
  else echo "live FAIL: promotion-note approval-token field was NOT allowlisted (rc=$_r_note)"; sf=1; fi

  mkdir -p "$d/leak"
  _mk_repo "$d/leak"
  printf 'token = "%s"\n' "$(head -c 40 /dev/urandom | base64 | tr -d '\n')" > "$d/leak/fixture.txt"
  git -C "$d/leak" add -A
  git -C "$d/leak" commit -q -m "leak"
  set +e
  "$_gl" git "$d/leak" --config "$_gltoml_abs" --no-banner --redact >/dev/null 2>&1
  _r_leak=$?
  set -e
  if [ "$_r_leak" -ne 0 ]; then
    echo "live PASS: an identical secret OUTSIDE the approval-token grammar still reds (rc=$_r_leak)"
  else echo "live FAIL: the allowlist over-masked — a secret outside the promotion-note grammar wrongly passed"; sf=1; fi

  # --- 4) MUTANT: a config with the `[extend]` stanza dropped must wrongly PASS the history-secret
  # case (proving useDefault=true is load-bearing, not decorative — design §3 S-5a). ---
  {
    grep -v '^\[extend\]' "$_gltoml_abs" | grep -v 'useDefault[[:space:]]*=[[:space:]]*true'
  } > "$d/mutant-noextend.toml"
  set +e
  "$_gl" git "$d/hist" --config "$d/mutant-noextend.toml" --no-banner --redact >/dev/null 2>&1
  _r_mutant=$?
  set -e
  if [ "$_r_mutant" -eq 0 ]; then
    echo "live PASS: dropping [extend] from the config makes the history-secret case wrongly PASS (rc 0) — proves [extend] useDefault=true is necessary"
  else echo "live FAIL: the [extend]-drop mutant still caught the secret (rc=$_r_mutant) — the necessity proof did not fire"; sf=1; fi

  # --- 5) LINE-ANCHOR proof (security review, 2026-09-10): the allowlist regex must be ANCHORED to a
  # well-formed note line, not a bare substring match. `regexTarget = "line"` checks the WHOLE line, so
  # an unanchored `approval-token: "[^"]*"` matches if that text appears ANYWHERE on the line —
  # including a real secret on the SAME line with the note grammar appended after it. Plant a
  # synthetic private key with `approval-token: ""` appended on the SAME line: the shipped (anchored)
  # config must still red. The marker is assembled at runtime (see the comment on the leg-2 plant
  # above) so it never appears whole in this source. ---
  mkdir -p "$d/sameline"
  _mk_repo "$d/sameline"
  {
    printf -- '-----BEGIN %s KEY----- # approval-token: ""\n' 'PRIVATE'
    head -c 400 /dev/urandom | base64
    printf -- '\n-----END %s KEY-----\n' 'PRIVATE'
  } > "$d/sameline/fixture.txt"
  git -C "$d/sameline" add -A
  git -C "$d/sameline" commit -q -m "secret with approval-token appended on the same line"
  set +e
  "$_gl" git "$d/sameline" --config "$_gltoml_abs" --no-banner --redact >/dev/null 2>&1
  _r_sameline=$?
  set -e
  if [ "$_r_sameline" -ne 0 ]; then
    echo "live PASS: a secret with approval-token appended on the SAME line still reds (rc=$_r_sameline) — the allowlist is line-anchored, not a bare substring match"
  else echo "live FAIL: the allowlist masked a secret sharing its line with the note grammar (rc 0) — the allowlist regex is not anchored"; sf=1; fi

  if [ "$sf" -eq 0 ]; then echo "OK: secret-scan-wired live (history coverage proven)"; exit 0
  else echo "FAIL: secret-scan-wired live"; exit 1; fi
}

# --selftest / --scan-selftest / --live dispatch — BEFORE the usage check, or the flag is read as a
# filename.
case "${1:-}" in
  --selftest) selftest; exit $? ;;
  --scan-selftest) scan_selftest; exit $? ;;
  --live) live; exit $? ;;
esac

case "${1:-}" in
  "")
    _rc=0
    check_wired "$CI_FILE" || _rc=1
    check_parity || _rc=1
    check_gitleaks_toml || _rc=1
    if [ "$_rc" -eq 0 ]; then exit 0; else
      echo "See DEVELOPMENT-STANDARDS.md §14 (secret-scan is a required, unwaivable gate) and the A8 / SECRET-SCAN-HISTORY-NOT-SCANNED design." >&2
      exit 1
    fi
    ;;
  *) echo "usage: secret-scan-wired.sh [--selftest | --scan-selftest | --live]" >&2; exit 2 ;;
esac
