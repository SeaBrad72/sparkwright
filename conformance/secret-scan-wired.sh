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
#   inside a mktemp -d they remove on exit (synthetic fixtures). Mutates nothing tracked.
# Guardrails: read-only; no network; trap-cleans its temp dirs; never emits or commits a real secret
#   (random PEM bodies; legs 3 and 6 plant fixed values); fails closed (rc 2) if gitleaks is unavailable.
set -eu

# The pinned scanner the profiles ship (parity is the point — neutrality). Kept in lockstep with
# profiles/*/ci.yml and the kit's own secret-scan job; drift between them is a routed maintenance item.
GL_VER="8.24.3"
CI_FILE="${KIT_CI_FILE:-.github/workflows/ci.yml}"
GL_TOML="${KIT_GITLEAKS_TOML:-.gitleaks.toml}"
GI_NAME=".gitleaksignore"
GI_FILE="${KIT_GITLEAKSIGNORE:-$GI_NAME}"
DRIFT_FILE="${KIT_DRIFT_FILE:-.github/workflows/drift-watch.yml}"

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

# _job_block <body-text> <job-name> -> prints the job's own block (its 2-space `<job>:` header to the next
# 2-space job header, or EOF). _step_block <body-text> -> prints the `id: gate-secret-scan` step (from its
# id line to the next step or job header). Both take COMMENT-STRIPPED text.
_job_block() {
  printf '%s\n' "$1" | awk -v j="$2" '$0=="  " j ":"{f=1;next} f&&/^  [A-Za-z0-9_-]+:[ \t]*$/{exit} f{print}'
}
_step_block() {
  printf '%s\n' "$1" | awk '/id:[ \t]*gate-secret-scan/{f=1;next} f&&(/^      - /||/^  [A-Za-z0-9_-]+:[ \t]*$/){exit} f{print}'
}

# _scope_shape_ok <block-text> <label> -> 0 iff the secret-scan block carries the SWAS-175 scope shape,
# else prints one FAIL per gap and returns 1: `--log-opts="$GL_SCOPE"`, all THREE scope arms, the
# fail-closed PR-range refusal (design A1: with it deleted and empty shas the scope is `..`, which git
# reads as HEAD..HEAD -- zero commits, a silent pass), and event fields only through `env:` (A8).
_scope_shape_ok() {
  _sb=$1; _sl=$2; _sr=0
  printf '%s\n' "$_sb" | grep -Fq -e '--log-opts="$GL_SCOPE"' \
    || { echo "FAIL: $_sl does not scope the scan with --log-opts=\"\$GL_SCOPE\" (an unscoped 'gitleaks git' runs 'git log --all': one branch's finding reds every PR)"; _sr=1; }
  printf '%s\n' "$_sb" | grep -Eq 'pull_request\)[[:space:]]+GL_SCOPE="\$BASE_SHA\.\.HEAD"' \
    || { echo "FAIL: $_sl is missing the 'pull_request) GL_SCOPE=\"\$BASE_SHA..HEAD\"' scope arm"; _sr=1; }
  printf '%s\n' "$_sb" | grep -Eq 'push\)[[:space:]]+GL_SCOPE="HEAD"' \
    || { echo "FAIL: $_sl is missing the 'push) GL_SCOPE=\"HEAD\"' scope arm"; _sr=1; }
  printf '%s\n' "$_sb" | grep -Eq '\*\)[[:space:]]+GL_SCOPE="--full-history --all"' \
    || { echo "FAIL: $_sl is missing the '*) GL_SCOPE=\"--full-history --all\"' scope arm"; _sr=1; }
  # The base refusal (A9): BASE_SHA hex-checked and resolved with `git rev-parse -q --verify` (NOT cat-file or
  # merge-base: the tracker-secret pairing lock taints those), then the EXACT `|| { echo ...; exit 1; }` line.
  _hx="grep -Eqx '[0-9a-f]{40}([0-9a-f]{24})?'"
  if ! printf '%s\n' "$_sb" | grep -Fq -e "echo \"\$BASE_SHA\" | $_hx" \
    || ! printf '%s\n' "$_sb" | grep -Fq -e 'git rev-parse -q --verify "$BASE_SHA^{commit}" >/dev/null' \
    || ! printf '%s\n' "$_sb" | grep -Fq -e '|| { echo "secret-scan: PR range not resolvable in this checkout; refusing to guess a range"; exit 1; }'; then
    echo "FAIL: $_sl is missing the exact fail-closed PR-base refusal (BASE_SHA hex check AND 'git rev-parse -q --verify', then the '|| { echo \"secret-scan: PR range not resolvable ...\"; exit 1; }' line)"; _sr=1
  fi
  # The empty-range refusal: a wrong checkout (HEAD on the base) would scan zero PR commits and pass.
  if ! printf '%s\n' "$_sb" | grep -Fq -e '[ -n "$(git rev-list -n 1 "$BASE_SHA..HEAD")" ]' \
    || ! printf '%s\n' "$_sb" | grep -Fq -e '|| { echo "secret-scan: PR range is empty; refusing to report a scan of nothing"; exit 1; }'; then
    echo "FAIL: $_sl is missing the exact empty-range refusal (a PR range of zero commits must exit 1 naming 'PR range is empty')"; _sr=1
  fi
  # ${{ }} is allowed ONLY as `NAME: ${{ expr }}` inside the step's env: mapping (judged by indentation);
  # from the `run:` line onward (its body, or a one-line `run: ${{ ... }}`) any ${{ is a violation. A fake
  # `env:` line inside a run body cannot reopen the exemption: the run body is consumed first.
  printf '%s\n' "$_sb" | awk '
    /^[ \t]*$/ { next }
    { match($0, /^ */); ind = RLENGTH }
    inrun && ind > rind { if (index($0, "${{")) bad = 1; next }
    { inrun = 0 }
    $0 ~ /^ *(- )?run:/ { rind = ind; inrun = 1; if (index($0, "${{")) bad = 1; next }
    $0 ~ /^ *env:[ \t]*$/ { eind = ind; inenv = 1; next }
    inenv && ind > eind { if (index($0, "${{") && $0 !~ /^ +[A-Za-z_][A-Za-z0-9_]*: +[$][{][{][^}]*[}][}] *$/) bad = 1; next }
    { inenv = 0; if (index($0, "${{")) bad = 1 }
    END { exit bad }' \
    || { echo "FAIL: $_sl interpolates \${{ }} outside the step's env: mapping (event fields must enter only through env:, never in or after the run: line)"; _sr=1; }
  return "$_sr"
}

# _job_with_scan <body-text> -> the job block holding the `id: gate-secret-scan` step (comment-stripped text).
# _checkout_ref_ok <job-text> <label> -> FAIL if an actions/checkout step in the job carries a `ref:` key
# (A9: HEAD must be what the event checked out; an override could leave HEAD on the base, scanning nothing).
_job_with_scan() {
  printf '%s\n' "$1" | awk '/^  [A-Za-z0-9_-]+:[ \t]*$/ { if (hit) { printf "%s", buf; hit = 0; exit } buf = "" } { buf = buf $0 "\n" } /id:[ \t]*gate-secret-scan/ { hit = 1 } END { if (hit) printf "%s", buf }'
}
_checkout_ref_ok() {
  # Each step is read as a whole (key order is irrelevant); a `ref` key in block, flow (`{ ref: x }`) or quoted
  # (`"ref":`) form fails. A word test, not a YAML parser.
  printf '%s\n' "$1" | awk 'function flush() { if (co && rf) bad = 1; co = 0; rf = 0 }
    /^      - / { flush() }
    /actions\/checkout/ { co = 1 }
    /(^|[ \t{,])["\047]?ref["\047]?[ \t]*:/ { rf = 1 }
    END { flush(); exit bad }' \
    || { echo "FAIL: $2 has an actions/checkout step with a ref: key (HEAD would no longer be the event's own checkout)"; return 1; }
}

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
  _scope_shape_ok "$(_job_block "$_body" secret-scan)" "$_wf's 'secret-scan' job" || _fail=1
  _checkout_ref_ok "$(_job_block "$_body" secret-scan)" "$_wf's 'secret-scan' job" || _fail=1
  if [ "$_fail" = 0 ]; then
    echo "OK: $_wf carries the pinned (v$GL_VER) 'gitleaks git' (history) secret-scan step (id: gate-secret-scan), PR-scoped via --log-opts"
    return 0
  fi
  return 1
}

# check_parity -> 0 if every parity site has been swapped to `gitleaks git` (never `gitleaks dir`),
# else 1. Gitleaks-independent (pure grep); this is the byte lock the design demands across the
# ~30-file parity surface, not just the one CI_FILE that check_wired covers.
check_parity() {
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
  _parity_run
}

# _parity_run -> the parity sweep over $_PARITY_INVOCATION_FILES / $_PARITY_MANIFEST_FILES, with NO kit-marker
# latch. check_parity latches it to the kit tree; the selftest NEGs call it directly on fixtures they build
# in their own temp dir, so they bite on ANY tree (an exported or incepted tree included).
_parity_run() {
  _pfail=0
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
    # SWAS-175: the same scope shape in EVERY site's gate-secret-scan step (comment-stripped).
    _pb=$(_step_block "$(sed 's/#.*//' "$_f")")
    [ -n "$_pb" ] || { echo "FAIL: $_f has no 'id: gate-secret-scan' step to scope-check"; _pfail=1; continue; }
    _scope_shape_ok "$_pb" "$_f's gate-secret-scan step" || _pfail=1
    _checkout_ref_ok "$(_job_with_scan "$(sed 's/#.*//' "$_f")")" "$_f" || _pfail=1
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
    if ! grep -Eq 'assert:[[:space:]]*present[[:space:]]+--log-opts=' "$_f"; then
      echo "FAIL: $_f has no 'assert: present --log-opts=' line (the scan scope is unasserted)"
      _pfail=1
    fi
  done
  if [ "$_pfail" = 0 ]; then
    echo "OK: profile parity — every secret-scan site runs 'gitleaks git' (history mode), scoped with --log-opts"
    return 0
  fi
  return 1
}

# _is_kit_tree -> 0 on the kit's own tree (either twin marker present), 1 on an adopter export.
_is_kit_tree() { [ -f docs/ROADMAP-KIT.md ] || [ -f .github/workflows/golden-path.yml ]; }

# check_sweep [file] -> 0 iff drift-watch.yml carries the weekly all-refs `secret-scan-sweep` job (SWAS-175 §4):
# its own fetch-depth: 0, id: gate-secret-scan and the all-refs --log-opts. Kit-self (N/A on an adopter export).
check_sweep() {
  _sw=${1:-$DRIFT_FILE}
  if [ -z "${1:-}" ] && ! _is_kit_tree; then echo "N/A: the all-refs sweep is a kit-self check (drift-watch.yml)"; return 0; fi
  [ -f "$_sw" ] || { echo "FAIL: $_sw not found (the weekly all-refs secret sweep lives there)"; return 1; }
  _swb=$(sed 's/#.*//' "$_sw")
  _swj=$(_job_block "$_swb" secret-scan-sweep)
  if [ -n "$_swj" ] && printf '%s\n' "$_swj" | grep -Eq 'fetch-depth:[[:space:]]*0' \
    && printf '%s\n' "$_swj" | grep -Eq 'id:[[:space:]]*gate-secret-scan' \
    && printf '%s\n' "$_swj" | grep -Fq -e "GL_VER=$GL_VER" \
    && printf '%s\n' "$_swj" | grep -Fq -e 'sha256sum -c' \
    && printf '%s\n' "$_swj" | grep -Fq -e 'gitleaks git . --no-banner --redact --log-opts="--full-history --all"'; then
    echo "OK: $_sw carries the weekly all-refs 'secret-scan-sweep' job (fetch-depth: 0, id: gate-secret-scan, --full-history --all)"
    return 0
  fi
  echo "FAIL: $_sw has no 'secret-scan-sweep' job with fetch-depth: 0, id: gate-secret-scan, the pinned GL_VER=$GL_VER, its sha256sum -c line and the all-refs invocation -- branches without a PR would go unscanned"
  return 1
}

# check_ignore_not_shipped [repo-dir] -> 0 iff the gitleaks ignore file is NOT in `git archive HEAD` (what an
# adopter receives: its entries fingerprint kit commits that do not exist in an adopter's history; D-241013-1
# item 1). Asks the archive listing, never `git check-attr`. Kit-self; N/A outside a git work tree.
check_ignore_not_shipped() {
  _id=${1:-.}
  if [ "$_id" = . ] && ! _is_kit_tree; then echo "N/A: the not-shipped lock is a kit-self check"; return 0; fi
  git -C "$_id" rev-parse --git-dir >/dev/null 2>&1 || { echo "N/A: not a git work tree -- no archive listing to read"; return 0; }
  # Fail CLOSED: an archive/tar error or an empty listing proves nothing, so it is a FAIL, never an OK.
  _ta=$(mktemp -d)
  if ! git -C "$_id" archive HEAD > "$_ta/a.tar" 2> "$_ta/err" || ! tar -tf "$_ta/a.tar" > "$_ta/list" 2>> "$_ta/err" || [ ! -s "$_ta/list" ]; then
    echo "FAIL: could not read the 'git archive HEAD' listing ($(head -n 1 "$_ta/err" 2>/dev/null)) -- an unread listing cannot show $GI_NAME is export-ignored"
    rm -rf "$_ta"; return 1
  fi
  if grep -Fxq -e "$GI_NAME" "$_ta/list"; then
    rm -rf "$_ta"
    echo "FAIL: $GI_NAME is in the 'git archive HEAD' listing -- it must stay export-ignored (its fingerprints name kit commits)"
    return 1
  fi
  rm -rf "$_ta"
  echo "OK: $GI_NAME is absent from the git archive listing (export-ignored)"
  return 0
}

# check_gitleaksignore [file] -> 0 iff every entry of the ignore file is locked to ONE commit and reviewable
# (SWAS-175 §2.3): a four-field `<40-hex>:<path>:<rule>:<line>` (a three-field entry is a GLOBAL fingerprint
# in gitleaks 8.24.3: that path, rule and line in every commit); directly under a comment block whose first
# line is `# YYYY-MM-DD <reason>` and whose text names the rule; and a `# entries: N` line equal to the entry
# count once any non-grandfathered entry exists. The one entry that predates the lock is grandfathered here
# (§2.5 a), exempt only from the date rule, so nobody edits the guard-denied file.
_GI_GRANDFATHER="d3255a90895c517f82fc1e91e11c9fdc708d8e9c:scripts/doctor.sh:generic-api-key:534"
check_gitleaksignore() {
  _gf=${1:-$GI_FILE}
  [ -f "$_gf" ] || { echo "N/A: $_gf absent -- no suppression channel to lock"; return 0; }
  _gr=0; _gc=0; _gn=0; _gdecl=""; _gb1=""; _gb=""
  while IFS= read -r _gln || [ -n "$_gln" ]; do
    case "$_gln" in
      '') _gb1=""; _gb="" ;;
      '#'*)
        if [ -z "$_gb1" ]; then _gb1=$_gln; fi
        _gb="$_gb $_gln"
        case "$_gln" in '# entries: '*) _gdecl=${_gln#'# entries: '} ;; esac ;;
      *)
        _gc=$((_gc + 1))
        if ! printf '%s\n' "$_gln" | grep -Eq '^[0-9a-f]{40}:[^:]+:[a-z0-9-]+:[0-9]+$'; then
          echo "FAIL: $_gf entry '$_gln' is not a four-field <40-hex commit>:<path>:<rule>:<line> fingerprint (a three-field entry suppresses that path, rule and line in EVERY commit)"; _gr=1
        elif [ "$_gln" != "$_GI_GRANDFATHER" ]; then
          _gn=$((_gn + 1)); _grule=$(printf '%s' "$_gln" | awk -F: '{print $3}')
          printf '%s\n' "$_gb1" | grep -Eq '^# [0-9]{4}-[0-9]{2}-[0-9]{2} .' \
            || { echo "FAIL: $_gf entry '$_gln' is not directly under a comment block whose first line is '# YYYY-MM-DD <reason>'"; _gr=1; }
          case "$_gb" in *"$_grule"*) ;; *) echo "FAIL: $_gf entry '$_gln' has a reason that does not name its rule '$_grule'"; _gr=1 ;; esac
        fi
        _gb1=""; _gb="" ;;
    esac
  done < "$_gf"
  if [ "$_gn" -gt 0 ] && [ -z "$_gdecl" ]; then echo "FAIL: $_gf holds $_gn non-grandfathered entr(y/ies) but no '# entries: N' line"; _gr=1; fi
  if [ -n "$_gdecl" ] && [ "$_gdecl" != "$_gc" ]; then echo "FAIL: $_gf declares '# entries: $_gdecl' but holds $_gc entries"; _gr=1; fi
  [ "$_gr" = 0 ] || return 1
  echo "OK: $_gf shape lock holds ($_gc entr$([ "$_gc" = 1 ] && echo y || echo ies), $((_gc - _gn)) grandfathered)"
  return 0
}

# _kit_rule_block_ok <toml> -> 0 if ONE [[rules]] block (from its header to the next table that is
# not [[rules.allowlists]]) carries all three: id = "kit-tracker-token", the keywords line, and a
# `regex =` line naming kit_tracker_token. Three greps over the whole file would be satisfied by the
# parts spread across different rules, or by a gutted regex.
_kit_rule_block_ok() {
  awk '
    function flush() { if (inb && hid && hkw && hre) ok = 1; inb = 0; hid = 0; hkw = 0; hre = 0 }
    /^\[\[rules\]\]/ { flush(); inb = 1; next }
    /^\[/ { if ($0 !~ /^\[\[rules\.allowlists\]\]/) flush(); next }
    inb && /^id[ \t]*=[ \t]*"kit-tracker-token"/ { hid = 1 }
    inb && /^keywords[ \t]*=[ \t]*\["kit_tracker_token"\]/ { hkw = 1 }
    inb && /^regex[ \t]*=.*kit_tracker_token/ { hre = 1 }
    END { flush(); exit (ok ? 0 : 1) }
  ' "$1"
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
  if ! _kit_rule_block_ok "$GL_TOML"; then
    echo "FAIL: $GL_TOML is missing the kit rule — ONE [[rules]] block must carry id = \"kit-tracker-token\", keywords = [\"kit_tracker_token\"] and a regex line naming kit_tracker_token; a credential committed under KIT_TRACKER_TOKEN would be caught only probabilistically by the default generic rule"
    return 1
  fi
  echo "OK: $GL_TOML carries [extend] useDefault = true and the kit-tracker-token rule"
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

# --- helpers for the kit-rule legs in live() (they use live()'s $d, $_gl, $_gltoml_abs and $sf) ---
# _kit_plant <name> <line> — a one-file repo at "$d/<name>" whose only commit holds <line>.
_kit_plant() {
  mkdir -p "$d/$1"
  _mk_repo "$d/$1"
  printf '%s\n' "$2" > "$d/$1/fixture.txt"
  git -C "$d/$1" add -A
  git -C "$d/$1" commit -q -m "plant $1"
}

# _kit_scan <name> [config] — history-mode scan of "$d/<name>" writing a JSON report to
# "$d/<name>.json"; sets $_ks_rc. `-f json -r <file>` is identical on gitleaks 8.24.3 and 8.30.x.
_kit_scan() {
  set +e
  "$_gl" git "$d/$1" --config "${2:-$_gltoml_abs}" --no-banner --redact -f json -r "$d/$1.json" >/dev/null 2>&1
  _ks_rc=$?
  set -e
}

# _kit_expect_red <name> <label> — rc != 0 AND the report names RuleID kit-tracker-token.
_kit_expect_red() {
  _kit_scan "$1"
  if [ ! -s "$d/$1.json" ]; then
    echo "live FAIL: $2 -> the scan wrote no report (rc=$_ks_rc) — a missing report cannot prove a finding"; sf=1
  elif [ "$_ks_rc" -ne 0 ] && grep -q '"RuleID": "kit-tracker-token"' "$d/$1.json"; then
    echo "live PASS: $2 -> reds with RuleID kit-tracker-token (rc=$_ks_rc)"
  else echo "live FAIL: $2 -> expected a kit-tracker-token finding (rc=$_ks_rc, RuleIDs: $(grep -o '"RuleID": "[^"]*"' "$d/$1.json" | sort -u | tr '\n' ' '))"; sf=1; fi
}

# _kit_expect_clean <name> <label> — rc 0 AND the report holds no finding from any rule.
_kit_expect_clean() {
  _kit_scan "$1"
  if [ ! -s "$d/$1.json" ]; then
    echo "live FAIL: $2 -> the scan wrote no report (rc=$_ks_rc) — a missing report cannot prove a clean scan"; sf=1
  elif [ "$_ks_rc" -eq 0 ] && ! grep -q '"RuleID"' "$d/$1.json"; then
    echo "live PASS: $2 -> no finding from any rule (rc 0)"
  else echo "live FAIL: $2 -> expected no finding (rc=$_ks_rc, RuleIDs: $(grep -o '"RuleID": "[^"]*"' "$d/$1.json" | sort -u | tr '\n' ' '))"; sf=1; fi
}

selftest() {
  sf=0; d=$(mktemp -d); trap 'rm -rf "$d"' EXIT INT TERM

  # POS anchor: a workflow carrying the invocation + id + pinned version + fetch-depth -> PASS.
  {
    printf 'jobs:\n  secret-scan:\n    steps:\n'
    printf '      - uses: actions/checkout@x\n        with:\n          fetch-depth: 0\n'
    printf '      - name: Secret scan\n        id: gate-secret-scan\n'
    printf '        env:\n          GL_EVENT: ${{ github.event_name }}\n          BASE_SHA: ${{ github.event.pull_request.base.sha }}\n'
    printf '        run: |\n          GL_VER=%s\n' "$GL_VER"
    printf '          case "$GL_EVENT" in\n            pull_request) GL_SCOPE="$BASE_SHA..HEAD" ;;\n            push)         GL_SCOPE="HEAD" ;;\n'
    printf '            *)            GL_SCOPE="--full-history --all" ;;\n          esac\n          if [ "$GL_EVENT" = pull_request ]; then\n'
    printf '            { echo "$BASE_SHA" | grep -Eqx %s[0-9a-f]{40}([0-9a-f]{24})?%s \\\n' "'" "'"
    printf '              && git rev-parse -q --verify "$BASE_SHA^{commit}" >/dev/null; } \\\n'
    printf '              || { echo "secret-scan: PR range not resolvable in this checkout; refusing to guess a range"; exit 1; }\n'
    printf '            [ -n "$(git rev-list -n 1 "$BASE_SHA..HEAD")" ] \\\n'
    printf '              || { echo "secret-scan: PR range is empty; refusing to report a scan of nothing"; exit 1; }\n          fi\n'
    printf '          /tmp/gitleaks git . --no-banner --redact --log-opts="$GL_SCOPE"\n'
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
  # The one leg that needs the kit's real files: latched to the kit tree (N/A, stated, on an export).
  if ! _is_kit_tree; then echo "selftest N/A: the real-fleet parity sweep needs the kit's own parity files (kit-marker latch: docs/ROADMAP-KIT.md / golden-path.yml absent -> an adopter export)"
  elif check_parity >/dev/null 2>&1; then
    echo "selftest PASS: check_parity -> PASS on the real repo's parity sites"
  else echo "selftest FAIL: check_parity wrongly failed on the real repo"; sf=1; fi

  # --- check_gitleaks_toml fixtures ---
  {
    printf 'title = "t"\n\n[extend]\nuseDefault = true\n\n'
    printf '[[rules]]\nid = "kit-tracker-token"\nregex = \x27\x27\x27(?i)kit_tracker_token=(x)\x27\x27\x27\nkeywords = ["kit_tracker_token"]\n\n'
    printf '[[rules.allowlists]]\nregexes = [\x27y\x27]\n\n'
    printf '[allowlist]\nregexTarget = "line"\nregexes = [\x27x\x27]\n'
  } > "$d/good.toml"
  GL_TOML="$d/good.toml"
  if check_gitleaks_toml >/dev/null 2>&1; then
    echo "selftest PASS: .gitleaks.toml with [extend] useDefault + the kit rule -> PASS"
  else echo "selftest FAIL: valid .gitleaks.toml wrongly failed"; sf=1; fi

  # The same valid config WITHOUT the kit rule -> FAIL, naming the rule (isolates the new assertion:
  # [extend] is present, so only the missing rule can red it).
  {
    printf 'title = "t"\n\n[extend]\nuseDefault = true\n\n[allowlist]\nregexTarget = "line"\nregexes = [\x27x\x27]\n'
  } > "$d/norule.toml"
  GL_TOML="$d/norule.toml"
  if _on=$(check_gitleaks_toml 2>&1); then _rn=0; else _rn=$?; fi
  if [ "$_rn" -ne 0 ] && printf '%s' "$_on" | grep -qF 'kit-tracker-token'; then
    echo "selftest PASS: .gitleaks.toml missing the kit rule -> FAIL (names the gap)"
  else echo "selftest FAIL: .gitleaks.toml missing the kit rule not caught (rc=$_rn): $_on"; sf=1; fi

  {
    printf 'title = "t"\n\n[[rules]]\nid = "kit-tracker-token"\nregex = \x27\x27\x27(?i)kit_tracker_token=(x)\x27\x27\x27\nkeywords = ["kit_tracker_token"]\n\n'
    printf '[allowlist]\nregexTarget = "line"\nregexes = [\x27x\x27]\n'
  } > "$d/noextend.toml"
  GL_TOML="$d/noextend.toml"
  if check_gitleaks_toml >/dev/null 2>&1; then
    echo "selftest FAIL: .gitleaks.toml missing [extend] wrongly passed"; sf=1
  else echo "selftest PASS: .gitleaks.toml missing [extend] -> FAIL (names the gap)"; fi

  # The id and the keywords are present but the rule's regex line is gutted (no kit_tracker_token):
  # the rule would never match, so this must FAIL.
  {
    printf 'title = "t"\n\n[extend]\nuseDefault = true\n\n'
    printf '[[rules]]\nid = "kit-tracker-token"\nregex = \x27\x27\x27(?i)nothing=(x)\x27\x27\x27\nkeywords = ["kit_tracker_token"]\n\n'
    printf '[allowlist]\nregexTarget = "line"\nregexes = [\x27x\x27]\n'
  } > "$d/gutted.toml"
  GL_TOML="$d/gutted.toml"
  if check_gitleaks_toml >/dev/null 2>&1; then
    echo "selftest FAIL: .gitleaks.toml with a gutted kit-rule regex wrongly passed"; sf=1
  else echo "selftest PASS: .gitleaks.toml with the id + keywords but a gutted regex -> FAIL (block-scoped)"; fi

  # The parts are all present in the FILE but split across two [[rules]] blocks (the id + regex in
  # one, the keywords in another): whole-file greps would pass, the block-scoped check must FAIL.
  {
    printf 'title = "t"\n\n[extend]\nuseDefault = true\n\n'
    printf '[[rules]]\nid = "kit-tracker-token"\nregex = \x27\x27\x27(?i)kit_tracker_token=(x)\x27\x27\x27\n\n'
    printf '[[rules]]\nid = "other"\nregex = \x27\x27\x27other\x27\x27\x27\nkeywords = ["kit_tracker_token"]\n\n'
    printf '[allowlist]\nregexTarget = "line"\nregexes = [\x27x\x27]\n'
  } > "$d/split.toml"
  GL_TOML="$d/split.toml"
  if check_gitleaks_toml >/dev/null 2>&1; then
    echo "selftest FAIL: .gitleaks.toml with the keywords in a DIFFERENT rule block wrongly passed"; sf=1
  else echo "selftest PASS: .gitleaks.toml with the keywords in a different [[rules]] block -> FAIL (block-scoped)"; fi
  GL_TOML="${KIT_GITLEAKS_TOML:-.gitleaks.toml}"

  # --- SWAS-175 scope shape (design A1, A8): each NEG is the POS fixture minus ONE piece. ---
  _sn() { # <file> <fragment> <label> -> check_wired must FAIL naming the fragment
    if _o=$(check_wired "$1" 2>&1); then _r=0; else _r=$?; fi
    if [ "$_r" -ne 0 ] && printf '%s' "$_o" | grep -qF -e "$2"; then echo "selftest PASS: $3 -> FAIL (names the gap)"
    else echo "selftest FAIL: $3 not caught (rc=$_r): $_o"; sf=1; fi
  }
  grep -vF 'pull_request) GL_SCOPE' "$d/pos.yml" > "$d/neg-noarm.yml"
  _sn "$d/neg-noarm.yml" "scope arm" "missing pull_request scope arm"
  grep -vF '*)            GL_SCOPE' "$d/pos.yml" > "$d/neg-nostar.yml"
  _sn "$d/neg-nostar.yml" "scope arm" "missing all-refs fallback arm"
  sed 's/ --log-opts="\$GL_SCOPE"//' "$d/pos.yml" > "$d/neg-nologopts.yml"
  _sn "$d/neg-nologopts.yml" "--log-opts" "missing --log-opts"
  grep -vF 'refusing to guess a range' "$d/pos.yml" > "$d/neg-norefusal.yml"
  _sn "$d/neg-norefusal.yml" "fail-closed PR-base refusal" "dropped PR-base refusal (an empty or unresolvable base would scan the wrong range)"
  { cat "$d/pos.yml"; printf '          echo ${{ github.event.pull_request.head.sha }}\n'; } > "$d/neg-inline.yml"
  _sn "$d/neg-inline.yml" "outside the step's env:" "inline \${{ }} in run:"
  { cat "$d/pos.yml"; printf '          X: ${{ github.event.pull_request.title }}\n'; } > "$d/neg-inbody.yml"
  _sn "$d/neg-inbody.yml" "outside the step's env:" "an 'X: \${{ ... }}' line inside the run body (looks like an env entry)"
  sed 's/^        run: |$/        run: ${{ github.event.pull_request.title }}/' "$d/pos.yml" > "$d/neg-oneline.yml"
  _sn "$d/neg-oneline.yml" "outside the step's env:" "a one-line 'run: \${{ ... }}'"
  sed '/not resolvable/s/exit 1; }/exit 0; }/' "$d/pos.yml" > "$d/neg-exit0.yml"
  _sn "$d/neg-exit0.yml" "exact fail-closed PR-base refusal" "base refusal exit 1 changed to exit 0"
  grep -vF 'git rev-parse -q --verify' "$d/pos.yml" > "$d/neg-nobase.yml"
  _sn "$d/neg-nobase.yml" "exact fail-closed PR-base refusal" "the BASE_SHA rev-parse --verify check dropped"
  grep -vF 'PR range is empty' "$d/pos.yml" > "$d/neg-noempty.yml"
  _sn "$d/neg-noempty.yml" "empty-range refusal" "the empty-range refusal dropped (a wrong checkout would scan nothing)"
  sed '/PR range is empty/s/exit 1; }/exit 0; }/' "$d/pos.yml" > "$d/neg-empty0.yml"
  _sn "$d/neg-empty0.yml" "empty-range refusal" "empty-range refusal exit 1 changed to exit 0"
  awk '{ print } /fetch-depth: 0/ { print "          ref: main" }' "$d/pos.yml" > "$d/neg-ref.yml"
  _sn "$d/neg-ref.yml" "checkout step with a ref: key" "a ref: key on the secret-scan job's checkout"
  sed 's/^        with:$/        with: { fetch-depth: 0, ref: main }/; /^          fetch-depth: 0$/d' "$d/pos.yml" > "$d/neg-refflow.yml"
  _sn "$d/neg-refflow.yml" "checkout step with a ref: key" "a flow-style 'with: { ..., ref: x }' on the checkout"
  sed 's/^          fetch-depth: 0$/          "ref": main/' "$d/pos.yml" > "$d/neg-refquoted.yml"
  _sn "$d/neg-refquoted.yml" "checkout step with a ref: key" "a quoted \"ref\": key on the checkout"
  { printf 'jobs:\n  secret-scan:\n    steps:\n      - with:\n          fetch-depth: 0\n          ref: main\n        uses: actions/checkout@x\n'; sed '1,6d' "$d/pos.yml"; } > "$d/neg-reforder.yml"
  _sn "$d/neg-reforder.yml" "checkout step with a ref: key" "a ref: under a with: written BEFORE uses:"
  # Parity NEGs (cause C): each builds its OWN invocation file and manifest in $d and points _parity_run (the
  # latch-free sweep) at them, so they bite on ANY tree. Only the real-fleet leg below needs the kit's files.
  _sv_inv=$_PARITY_INVOCATION_FILES; _sv_man=$_PARITY_MANIFEST_FILES
  printf 'id: x\nassert: present gitleaks git[[:space:]]+\\.\n' > "$d/neg-man.txt"
  _PARITY_INVOCATION_FILES="$d/pos.yml"; _PARITY_MANIFEST_FILES=""
  if _parity_run >/dev/null 2>&1; then echo "selftest PASS: parity accepts a scoped step"; else echo "selftest FAIL: parity rejected a scoped step"; sf=1; fi
  _PARITY_INVOCATION_FILES="$d/neg-norefusal.yml"
  if _parity_run >/dev/null 2>&1; then echo "selftest FAIL: parity accepted a step without the PR-range refusal"; sf=1; else echo "selftest PASS: parity rejects a step without the PR-range refusal"; fi
  _PARITY_INVOCATION_FILES="$d/neg-ref.yml"
  if _parity_run >/dev/null 2>&1; then echo "selftest FAIL: parity accepted a checkout with a ref: key"; sf=1; else echo "selftest PASS: parity rejects a checkout with a ref: key"; fi
  _PARITY_INVOCATION_FILES=""; _PARITY_MANIFEST_FILES="$d/neg-man.txt"
  if _parity_run >/dev/null 2>&1; then echo "selftest FAIL: parity accepted a manifest without 'present --log-opts='"; sf=1; else echo "selftest PASS: parity rejects a manifest without 'present --log-opts='"; fi
  _PARITY_INVOCATION_FILES=$_sv_inv; _PARITY_MANIFEST_FILES=$_sv_man

  # --- the weekly all-refs sweep job ---
  printf 'jobs:\n  secret-scan-sweep:\n    steps:\n      - uses: x\n        with:\n          fetch-depth: 0\n      - id: gate-secret-scan\n        run: |\n          GL_VER=%s\n          echo "sum  /tmp/gitleaks.tgz" | sha256sum -c -\n          gitleaks git . --no-banner --redact --log-opts="--full-history --all"\n' "$GL_VER" > "$d/sweep.yml"
  grep -vF 'sha256sum -c' "$d/sweep.yml" > "$d/sweep-nosum.yml"
  if check_sweep "$d/sweep-nosum.yml" >/dev/null 2>&1; then echo "selftest FAIL: sweep without its sha256sum -c line passed"; sf=1; else echo "selftest PASS: sweep without its sha256sum -c line -> FAIL"; fi
  if check_sweep "$d/sweep.yml" >/dev/null 2>&1; then echo "selftest PASS: sweep job wired -> PASS"; else echo "selftest FAIL: wired sweep job failed"; sf=1; fi
  sed 's/ --all"/"/' "$d/sweep.yml" > "$d/sweep-neg.yml"
  if check_sweep "$d/sweep-neg.yml" >/dev/null 2>&1; then echo "selftest FAIL: sweep without the all-refs scope passed"; sf=1; else echo "selftest PASS: sweep without the all-refs scope -> FAIL"; fi

  # --- the ignore-file shape lock (§2.3) and the not-shipped lock (§2.4 a) ---
  _fp=0123456789abcdef0123456789abcdef01234567; _new="$_fp:scripts/x.sh:generic-api-key:12"
  _gi() { # <ok|fail> <label> <fragment>; the file is $d/gi.txt
    if _o=$(check_gitleaksignore "$d/gi.txt" 2>&1); then _r=0; else _r=$?; fi
    if [ "$1" = ok ] && [ "$_r" -eq 0 ]; then echo "selftest PASS: ignore lock: $2 -> PASS"
    elif [ "$1" = fail ] && [ "$_r" -ne 0 ] && printf '%s' "$_o" | grep -qF -e "$3"; then echo "selftest PASS: ignore lock: $2 -> FAIL (names the gap)"
    else echo "selftest FAIL: ignore lock: $2 (rc=$_r): $_o"; sf=1; fi
  }
  printf '# old\n%s\n' "$_GI_GRANDFATHER" > "$d/gi.txt"; _gi ok "only the grandfathered entry"
  printf '# entries: 2\n\n# old, generic-api-key\n%s\n\n# 2026-10-13 generic-api-key false positive (SWAS-1)\n%s\n' "$_GI_GRANDFATHER" "$_new" > "$d/gi.txt"; _gi ok "a dated, rule-named, counted new entry"
  printf '# entries: 2\n\n%s\n\n# 2026-10-13 generic-api-key false positive\nscripts/x.sh:generic-api-key:12\n' "$_GI_GRANDFATHER" > "$d/gi.txt"; _gi fail "a three-field (global) entry" "four-field"
  printf '# entries: 2\n\n%s\n\n# generic-api-key false positive, no date\n%s\n' "$_GI_GRANDFATHER" "$_new" > "$d/gi.txt"; _gi fail "a second, undated entry" "YYYY-MM-DD"
  printf '# entries: 2\n\n%s\n\n# 2026-10-13 a reason that names nothing\n%s\n' "$_GI_GRANDFATHER" "$_new" > "$d/gi.txt"; _gi fail "a reason that does not name the rule" "does not name its rule"
  printf '# entries: 5\n\n%s\n\n# 2026-10-13 generic-api-key false positive\n%s\n' "$_GI_GRANDFATHER" "$_new" > "$d/gi.txt"; _gi fail "a count mismatch" "declares"
  printf '%s\n\n# 2026-10-13 generic-api-key false positive\n%s\n' "$_GI_GRANDFATHER" "$_new" > "$d/gi.txt"; _gi fail "a new entry with no '# entries: N'" "no '# entries: N'"
  mkdir -p "$d/ship"; _mk_repo "$d/ship"; printf 'x\n' > "$d/ship/$GI_NAME"; git -C "$d/ship" add -A; git -C "$d/ship" commit -q -m shipped
  if check_ignore_not_shipped "$d/ship" >/dev/null 2>&1; then echo "selftest FAIL: an un-export-ignored ignore file passed"; sf=1; else echo "selftest PASS: the ignore file in the archive listing -> FAIL"; fi
  mkdir -p "$d/emptyrepo"; _mk_repo "$d/emptyrepo"   # a git dir with no commit: `git archive HEAD` errors
  if check_ignore_not_shipped "$d/emptyrepo" >/dev/null 2>&1; then echo "selftest FAIL: an unreadable archive listing passed"; sf=1; else echo "selftest PASS: an unreadable archive listing -> FAIL (fail-closed)"; fi
  printf '/%s export-ignore\n' "$GI_NAME" > "$d/ship/.gitattributes"; git -C "$d/ship" add -A; git -C "$d/ship" commit -q -m ignored
  if check_ignore_not_shipped "$d/ship" >/dev/null 2>&1; then echo "selftest PASS: an export-ignored ignore file -> PASS"; else echo "selftest FAIL: an export-ignored ignore file failed"; sf=1; fi

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
  # A FIXED value, never /dev/urandom: the random plant was missed by generic-api-key 3.5% (8.24.3) /
  # 4.5% (8.30.1) of 1,000 runs (leading `/` or `+`, or a stopword); this one is caught every run on
  # both and feeds BOTH plants, so "identical" is literal. Assembled from two halves like leg 6 (SWAS-80).
  _l3v=$(printf '%s%s' 'R7vK2mQ9xL4tW8nZ' 'c3Hj6pB1sF5yD0gT')
  mkdir -p "$d/note"
  _mk_repo "$d/note"
  {
    printf 'record: promotion GO (approve->execute->log)\n'
    printf 'approved-sha: abc123\n'
    printf 'approval-token: "%s"\n' "$_l3v"
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
  printf 'token = "%s"\n' "$_l3v" > "$d/leak/fixture.txt"
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

  # --- 6) KIT RULE `kit-tracker-token` (TRACKER-TOKEN-SECRET-SCAN-RULE). DETERMINISTIC legs: fixed
  # planted values, never /dev/urandom (the cured leg-3 random-plant flake, SWAS-80). Every leg reads the
  # `-f json` report and asserts on RuleID, because when two rules match one secret gitleaks reports
  # only one finding, so an rc alone cannot say WHICH rule caught it. The planted values are
  # ASSEMBLED at runtime from two halves so the whole credential shape never appears in this source
  # (the kit's own full-history scan must stay green). Both contain the substring `admin`, a
  # stopword of the DEFAULT generic rule: that rule DROPS them, so only the kit rule can catch them
  # (the ~2.7% gap this rule closes; M1 below proves it). ---
  _kv_dc=$(printf '%s%s' 'Qx7adminC3J27' 'XDCG2LmlZGEONYlk')
  _kv_legacy=$(printf '%s%s' 'Zk3adminQ9w7' 'Lp2Xv5Rt8Ny')

  # L1 — a fixed DC-shaped value (stopword-bearing) under KIT_TRACKER_TOKEN reds with the kit rule id.
  _kit_plant l1 "$(printf 'KIT_TRACKER_TOKEN=%s' "$_kv_dc")"
  _kit_expect_red l1 "L1 fixed stopword-bearing DC-shaped value under KIT_TRACKER_TOKEN"

  # L2 — a fixed legacy 24-character value, quoted.
  _kit_plant l2 "$(printf 'KIT_TRACKER_TOKEN="%s"' "$_kv_legacy")"
  _kit_expect_red l2 "L2 fixed legacy 24-char value (quoted)"

  # L3 — the other assignment forms each red with the kit rule id.
  _kit_plant l3a "$(printf 'export KIT_TRACKER_TOKEN=%s' "$_kv_dc")"
  _kit_expect_red l3a "L3 export form"
  _kit_plant l3b "$(printf 'KIT_TRACKER_TOKEN: %s' "$_kv_dc")"
  _kit_expect_red l3b "L3 YAML ': v' form"
  _kit_plant l3c "$(printf 'KIT_TRACKER_TOKEN = %s' "$_kv_dc")"
  _kit_expect_red l3c "L3 spaced ' = ' form"
  _kit_plant l3d "$(printf '{"KIT_TRACKER_TOKEN": "%s"}' "$_kv_dc")"
  _kit_expect_red l3d "L3 JSON form"

  # L4 — a value with `YOUR` MID-STRING and the generic stopword `admin` (so the default set cannot
  # mask the result). The old substring stopword `your` dropped this real-shaped token; the anchored
  # whole-value placeholder allowlist must not (it has digits and mixed case, so it is not ENTIRELY
  # placeholder text).
  _kv_your=$(printf '%s%s' 'Qx7YOURadminC3J27' 'XDCG2LmlZGEONYlk')
  _kit_plant l4 "$(printf 'KIT_TRACKER_TOKEN=%s' "$_kv_your")"
  _kit_expect_red l4 "L4 real-shaped value with YOUR mid-string (whole-value placeholder allowlist)"

  # L5 — the Make `:=` and `?=` forms, the Ruby hash `=>` form, and the shell `:=` default (which
  # commits a literal, so it reds) each red with the kit rule id.
  _kit_plant l5a "$(printf 'KIT_TRACKER_TOKEN := %s' "$_kv_dc")"
  _kit_expect_red l5a "L5 Make ':=' form"
  _kit_plant l5b "$(printf 'KIT_TRACKER_TOKEN ?= %s' "$_kv_dc")"
  _kit_expect_red l5b "L5 Make '?=' form"
  _kit_plant l5c "$(printf '"KIT_TRACKER_TOKEN" => "%s"' "$_kv_dc")"
  _kit_expect_red l5c "L5 Ruby '=>' form"
  _kit_plant l5d "$(printf 'X=${KIT_TRACKER_TOKEN:=%s}' "$_kv_dc")"
  _kit_expect_red l5d "L5 shell \${KIT_TRACKER_TOKEN:=<literal>} form"

  # N1-N5 — the legitimate shapes produce NO finding from any rule.
  _kit_plant n1 '# KIT_TRACKER_TOKEN=replace-me'
  _kit_expect_clean n1 "N1 .env.example placeholder line"
  _kit_plant n2 'token: ${{ secrets.KIT_TRACKER_TOKEN }}'
  _kit_expect_clean n2 "N2 workflow secrets reference"
  _kit_plant n3 'KIT_TRACKER_TOKEN=your-jira-api-token-goes-here'
  _kit_expect_clean n3 "N3 long placeholder value"
  # N4: the value of a shell default starts with `-` (`:-`); the rule's value class cannot START
  # with `-`, so `${KIT_TRACKER_TOKEN:-<long literal>}` does not fire.
  _kit_plant n4 "$(printf 'T="${KIT_TRACKER_TOKEN:-%s}"' "$_kv_dc")"
  _kit_expect_clean n4 "N4 shell default \${KIT_TRACKER_TOKEN:-<long literal>}"
  # N5: code that READS the variable from the environment/settings is not a committed credential.
  _kit_plant n5a 'const KIT_TRACKER_TOKEN = process.env.KIT_TRACKER_TOKEN;'
  _kit_expect_clean n5a "N5 process.env lookup"
  _kit_plant n5b 'KIT_TRACKER_TOKEN = settings.KIT_TRACKER_TOKEN_VALUE'
  _kit_expect_clean n5b "N5 settings lookup"
  # N6: a FUNCTION CALL that returns the token is not a committed credential either. The value is
  # followed by `(`, which the rule's trailing group refuses (CI's history scan caught the design
  # doc's own example of this shape). The JS line is assembled from two halves, like the planted
  # values above, so the whole shape never appears in this source.
  _kit_plant n6a "$(printf '%s%s' 'const KIT_TRACKER_TOKEN = getTrackerToken' 'FromKeychain();')"
  _kit_expect_clean n6a "N6 JS function-call value"
  _kit_plant n6b "$(printf '%s%s' 'KIT_TRACKER_TOKEN = load_tracker_token' '_from_vault()')"
  _kit_expect_clean n6b "N6 Python function-call value"

  # R1 — the anchored approval-token note line still passes with the kit rule present (the global
  # allowlist is not shadowed), even when the quoted free text itself carries the kit variable.
  _kit_plant r1 "$(printf 'approval-token: "KIT_TRACKER_TOKEN=%s"' "$_kv_dc")"
  _kit_expect_clean r1 "R1 anchored approval-token note line (kit rule present)"

  # M1 — MUTANT: the config with the kit rule's whole [[rules]] + [[rules.allowlists]] block removed
  # must let L1's plant wrongly PASS: the default set does not catch it, so L1 is load-bearing.
  sed '/^\[\[rules\]\]/,/^\[allowlist\]/{/^\[allowlist\]/!d;}' "$_gltoml_abs" > "$d/mutant-nokit.toml"
  # The mutant must really lack the kit rule and keep the default ruleset, or M1 proves nothing.
  if grep -Eq '^id[[:space:]]*=[[:space:]]*"kit-tracker-token"' "$d/mutant-nokit.toml" || ! grep -Eq 'useDefault[[:space:]]*=[[:space:]]*true' "$d/mutant-nokit.toml"; then
    echo "live FAIL: M1 the mutant config is malformed (it must lack kit-tracker-token AND keep useDefault = true) — M1 would prove nothing"; sf=1
  else
  _kit_scan l1 "$d/mutant-nokit.toml"
  if [ "$_ks_rc" -eq 0 ]; then
    echo "live PASS: M1 dropping the kit rule makes L1's plant wrongly PASS (rc 0) — proves the kit rule, not the default set, catches it"
  else echo "live FAIL: M1 the kit-rule-drop mutant still caught L1's plant (rc=$_ks_rc) — L1 is not load-bearing"; sf=1; fi
  fi

  if [ "$sf" -eq 0 ]; then echo "OK: secret-scan-wired live (history coverage proven)"; exit 0
  else echo "FAIL: secret-scan-wired live"; exit 1; fi
}

# range_scan <sha> — the pre-push face: the SAME scan CI runs on a pull request, over <sha>..HEAD at the repo
# root (so .gitleaks.toml and the ignore file apply exactly as in CI). Committed work only. Needs gitleaks;
# FAILS CLOSED (rc 2 UNVERIFIED) when absent. rc 1 = a finding.
range_scan() {
  printf '%s\n' "$1" | grep -Eqx '[0-9a-f]{40}([0-9a-f]{24})?' \
    || { echo "usage: secret-scan-wired.sh --range <full 40/64-hex commit sha>" >&2; exit 2; }
  _gl=$(resolve_gitleaks)
  if [ -z "$_gl" ]; then
    echo "UNVERIFIED: gitleaks is not available (set GITLEAKS_BIN or install gitleaks); the range scan did not run." >&2
    exit 2
  fi
  _gv=$("$_gl" version 2>/dev/null | head -n 1 | sed 's/^v//')
  echo "secret-scan --range: gitleaks ${_gv:-unknown}, scope $1..HEAD"
  if [ "$_gv" != "$GL_VER" ]; then echo "parity: local gitleaks ${_gv:-unknown} != pinned $GL_VER (rules may differ)"; fi
  "$_gl" git . --no-banner --redact --log-opts="$1..HEAD"
}

# scope_selftest — the SWAS-175 load-bearing negative: one branch's finding must not red another branch's PR
# scope. Fixture = an origin with main (clean), a (clean), b (a synthetic key, markers assembled at runtime);
# the clone checks out `a`, so b exists only as refs/remotes/origin/b -- the fetch-depth: 0 shape. Needs
# gitleaks; FAILS CLOSED (rc 2) when absent.
_sc_scan() { # <dir> <log-opts> -> sets _sc_rc; report in $d/sc.json
  rm -f "$d/sc.json"; set +e
  "$_gl" git "$1" --no-banner --redact -f json -r "$d/sc.json" ${2:+--log-opts="$2"} >/dev/null 2>&1
  _sc_rc=$?; set -e
}
_sc_expect() { # <red|clean> <label> <dir> <log-opts>
  _sc_scan "$3" "$4"
  if [ "$1" = red ] && [ "$_sc_rc" -ne 0 ] && [ -s "$d/sc.json" ] && grep -q '"RuleID"' "$d/sc.json"; then
    echo "scope-selftest PASS: $2 -> finding (rc=$_sc_rc)"
  elif [ "$1" = clean ] && [ "$_sc_rc" -eq 0 ]; then echo "scope-selftest PASS: $2 -> clean (rc 0)"
  else echo "scope-selftest FAIL: $2 -> expected $1 (rc=$_sc_rc)"; sf=1; fi
}
scope_selftest() {
  _gl=$(resolve_gitleaks)
  if [ -z "$_gl" ]; then
    echo "UNVERIFIED: gitleaks is not available (set GITLEAKS_BIN or install gitleaks); the scope proof cannot run." >&2
    exit 2
  fi
  sf=0; d=$(mktemp -d); trap 'rm -rf "$d"' EXIT INT TERM
  git init -q -b main "$d/origin"; _mk_repo "$d/origin"
  printf 'one\n' > "$d/origin/m.txt"; git -C "$d/origin" add -A; git -C "$d/origin" commit -q -m main
  git -C "$d/origin" checkout -q -b a; printf 'two\n' > "$d/origin/a.txt"; git -C "$d/origin" add -A; git -C "$d/origin" commit -q -m a
  git -C "$d/origin" checkout -q -b b main
  { printf -- '-----BEGIN %s KEY-----\n' 'PRIVATE'; head -c 400 /dev/urandom | base64; printf -- '\n-----END %s KEY-----\n' 'PRIVATE'; } > "$d/origin/k.txt"
  git -C "$d/origin" add -A; git -C "$d/origin" commit -q -m b
  _m=$(git -C "$d/origin" rev-parse main); _a=$(git -C "$d/origin" rev-parse a); _b=$(git -C "$d/origin" rev-parse b)
  git clone -q -b a "$d/origin" "$d/clone"; git clone -q -b main "$d/origin" "$d/mainclone"
  _sc_expect clean "S1 PR scope for A ($_m..$_a) does not see B's secret" "$d/clone" "$_m..$_a"
  _sc_expect red "S2 no --log-opts (all refs), from A's checkout, reproduces the 2026-10-12 bug" "$d/clone" ""
  _sc_expect red "S3 PR scope for B still catches B's own secret" "$d/clone" "$_m..$_b"
  _sc_expect clean "S4 push shape (HEAD) on a main checkout" "$d/mainclone" "HEAD"
  _sc_expect red "S5 mutant: the README form '--all <main>..<a>' cancels the range (why --all is banned inside log-opts)" "$d/clone" "--all $_m..$_a"
  if [ "$sf" -eq 0 ]; then echo "OK: secret-scan-wired scope-selftest (a branch's finding reds only its own PR scope)"; exit 0
  else echo "FAIL: secret-scan-wired scope-selftest"; exit 1; fi
}

# --selftest / --scan-selftest / --scope-selftest / --live / --range dispatch — BEFORE the usage check, or the
# flag is read as a filename.
case "${1:-}" in
  --selftest) selftest; exit $? ;;
  --scan-selftest) scan_selftest; exit $? ;;
  --scope-selftest) scope_selftest; exit $? ;;
  --range) range_scan "${2:-}"; exit $? ;;
  --live) live; exit $? ;;
esac

case "${1:-}" in
  "")
    _rc=0
    check_wired "$CI_FILE" || _rc=1
    check_sweep || _rc=1
    check_parity || _rc=1
    check_gitleaks_toml || _rc=1
    check_gitleaksignore || _rc=1
    check_ignore_not_shipped || _rc=1
    if [ "$_rc" -eq 0 ]; then exit 0; else
      echo "See DEVELOPMENT-STANDARDS.md §14 (secret-scan is a required, unwaivable gate) and the A8 / SECRET-SCAN-HISTORY-NOT-SCANNED design." >&2
      exit 1
    fi
    ;;
  *) echo "usage: secret-scan-wired.sh [--selftest | --scan-selftest | --scope-selftest | --range <sha> | --live]" >&2; exit 2 ;;
esac
