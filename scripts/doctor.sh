#!/bin/sh
# doctor.sh — adopter-facing POSTURE report. Composes existing conformance checks into one
# "am I conformant + have I drifted?" summary. Automates the *mechanizable* half of
# docs/operations/drift-self-check.md (axes D claim-integrity + E git ground-truth).
#
# Four posture dimensions:
#   conformance [GATING]   — sh conformance/verify.sh
#   claims      [GATING]   — sh conformance/claims-registry.sh (kit-self: N/A on an adopter tree, see below)
#   git         [ADVISORY] — branch, dirty-tree, tag alignment (WARN-only; never hard-fails alone)
#   kit-update  [ADVISORY] — is the kit you ADOPTED behind the current release? (conformance/kit-current.sh)
#
# WHY kit-update IS HERE (P1.2/T7). The kit's own recurring failure — its board calls it KW21 — is a
# capability that is built, conformance-checked, and INVISIBLE IN PRACTICE. P1.2 built an updater; an
# updater nobody is ever PROMPTED to run IS that failure. doctor is the adopter's decision point: the
# moment they are already asking "what is my posture?". So the answer to "you are three releases behind,
# and here is what it would cost to move" belongs HERE and nowhere else.
# It is ADVISORY on purpose, and both halves matter: BEING BEHIND IS NOT A DEFECT (a pinned project is a
# legitimate choice, so this can never fail a build — a gate that cried wolf on the happy path would be
# ignored within a month), and an UP-TO-DATE ADOPTER IS NEVER NAGGED (one quiet OK line).
#
# Exit policy (mirrors verify.sh):
#   exit 1  — a GATING dimension FAILs, or UNVERIFIED when --require/CI
#   exit 0  — PASS or WARN (git advisory warnings do not cause exit 1)
#
# Usage: sh scripts/doctor.sh [--require] [--full] | --as agent | --selftest
#   --as agent  the forge-identity check ONLY (SWAS-124): exit 1 when the login gh resolves holds admin or maintain on origin's
#               repo, or when that cannot be read (fail-closed) or gh is missing; 0 on push; 2 on a usage error or when the check cannot
#               be run (no forge adapter, a push URL naming another repo, a 403 App/CI token: UNVERIFIED, never 1). The default run adds one advisory `forge identity:` line, never a verdict; for an admin or maintain login that line adds one warn only where a ratification seat is declared in .kit/ratification-seats.conf, and is an INFO line (no warn) otherwise.
# POSIX sh; dash-clean.
# What it changes: Read-only — composes conformance + claims checks into a posture report; mutates nothing.
# Network (measured, SWAS-117 D5): doctor already reaches the network once, in the kit-update dimension (conformance/kit-current.sh
# runs `git ls-remote --tags` against the release source). It now also makes up to TWO bounded reads of the tracker (the
# identity and the permissions of the credential, each one attempt, 5s connect, 10s max) when a Jira credential is present.
# Those reads SEND THE CREDENTIAL to the conf's base_url (S-L3); doctor does not compare that host to any pin.
# Forge identity (SWAS-124): a default run makes two `gh api` reads (user, then the repository's permissions) and `--as agent` a third
# (`-i user`, for the token-expiry header), to github.com only (host-gated on origin's literal host, so an SSH host alias reports no
# adapter), sending gh's credential. Doctor sets no timeout of its own on them; gh's own network timeouts apply.
# Guardrails: exit 1 when a GATING dimension FAILs or is UNVERIFIED under --require/CI; the git dimension is advisory (WARN-only, never hard-fails alone).
set -eu
cd "$(dirname "$0")/.."

if [ "${1:-}" = "--selftest" ]; then
  # Verify the render contract using LIGHTWEIGHT STUBS — no real conformance/
  # claims scripts are invoked. 'true' always exits 0 (PASS); 'false' always
  # exits 1 (FAIL). Both are POSIX built-ins, so the selftest is fast and
  # deterministic regardless of repo state.
  sfail=0

  # — render contract (6 required sections/labels) ——————————————————————————
  out=$(DOCTOR_VERIFY_CMD=true DOCTOR_CLAIMS_CMD=true sh "$0" --selftest-e2e 2>&1) || true
  printf '%s\n' "$out" | grep -q "POSTURE"             || { echo "doctor --selftest: FAIL (no POSTURE section)"; sfail=1; }
  printf '%s\n' "$out" | grep -q "conformance"         || { echo "doctor --selftest: FAIL (no conformance dimension)"; sfail=1; }
  printf '%s\n' "$out" | grep -q "claims"              || { echo "doctor --selftest: FAIL (no claims dimension)"; sfail=1; }
  printf '%s\n' "$out" | grep -qE 'git[[:space:]]+(OK|WARN)' || { echo "doctor --selftest: FAIL (no git dimension row)"; sfail=1; }
  printf '%s\n' "$out" | grep -qE 'kit-update[[:space:]]+(OK|WARN|N/A)' || { echo "doctor --selftest: FAIL (no kit-update dimension row)"; sfail=1; }
  printf '%s\n' "$out" | grep -q "Overall:"            || { echo "doctor --selftest: FAIL (no Overall verdict)"; sfail=1; }
  printf '%s\n' "$out" | grep -q "drift-self-check.md" || { echo "doctor --selftest: FAIL (no drift-self-check.md footer)"; sfail=1; }

  # — T7 SURFACING: the kit-update dimension, driven by STUBS (no network, no fixtures — the real
  #   behaviour is proven in conformance/kit-current.sh --selftest; what is proven HERE is that doctor
  #   RENDERS each of its answers, and renders them DIFFERENTLY). Each stub exits with the rc the real
  #   check would, and prints the line it would print.
  #
  #   THE STUBS ARE FILES, not `sh -c '...'` strings. DOCTOR_*_CMD is invoked UNQUOTED (deliberately — it
  #   is how `true`/`false` above work), so the shell WORD-SPLITS it and quoting inside the string is not
  #   honoured: an `sh -c 'echo "a b"; exit 1'` stub arrives shredded into words and never runs. A stub
  #   file invoked as `sh <path>` is two words, so it survives the split intact. (Found the hard way.)
  stubd=$(mktemp -d)
  mkstub() {  # <name> <rc> <first-line>
    printf '#!/bin/sh\necho "%s"\nexit %s\n' "$3" "$2" > "$stubd/$1"
  }
  mkstub behind 1 "kit-current: BEHIND — your kit-base is v1.0.0; the current release is v2.0.0."
  mkstub uptodate 0 "kit-current: OK — up to date (kit-base v2.0.0 == the current release v2.0.0)."
  mkstub na 3 "kit-current: N/A — not an adopted tree (no kit-base branch)."
  mkstub unver 2 "kit-current: UNVERIFIED — could not read a release tag from the kit source."

  #   1. BEHIND -> the adopter is TOLD, and told WHAT TO RUN. This is the whole slice. A doctor that
  #      swallowed a BEHIND would be the KW21 failure recurring inside the very fix for it.
  behind_stub="sh $stubd/behind"
  bout=$(DOCTOR_VERIFY_CMD=true DOCTOR_CLAIMS_CMD=true DOCTOR_KITCURRENT_CMD="$behind_stub" sh "$0" --selftest-e2e 2>&1) || true
  printf '%s\n' "$bout" | grep -qE 'kit-update[[:space:]]+WARN' || { echo "doctor --selftest: FAIL (a BEHIND kit did not surface as a kit-update WARN)"; sfail=1; }
  printf '%s\n' "$bout" | grep -q 'v1.0.0'          || { echo "doctor --selftest: FAIL (BEHIND row does not name the adopted version)"; sfail=1; }
  printf '%s\n' "$bout" | grep -q 'kit-update.sh'   || { echo "doctor --selftest: FAIL (BEHIND row does not name the command to run)"; sfail=1; }
  #   ...and it must NOT fail their build. Being behind is a choice, not a defect.
  brc=0
  DOCTOR_VERIFY_CMD=true DOCTOR_CLAIMS_CMD=true DOCTOR_KITCURRENT_CMD="$behind_stub" sh "$0" --selftest-e2e >/dev/null 2>&1 || brc=$?
  [ "$brc" = "0" ] || { echo "doctor --selftest: FAIL (a BEHIND kit set exit $brc — the dimension is ADVISORY and must never gate)"; sfail=1; }

  #   2. NO FALSE ALARM — equally load-bearing. An up-to-date adopter gets OK, and the word 'BEHIND'
  #      appears NOWHERE. A tool that cries wolf destroys the trust it exists to create.
  ok_stub="sh $stubd/uptodate"
  oout=$(DOCTOR_VERIFY_CMD=true DOCTOR_CLAIMS_CMD=true DOCTOR_KITCURRENT_CMD="$ok_stub" sh "$0" --selftest-e2e 2>&1) || true
  printf '%s\n' "$oout" | grep -qE 'kit-update[[:space:]]+OK' || { echo "doctor --selftest: FAIL (an up-to-date kit did not render OK)"; sfail=1; }
  printf '%s\n' "$oout" | grep -qi 'BEHIND' && { echo "doctor --selftest: FAIL (an up-to-date adopter was told it was BEHIND — doctor cries wolf)"; sfail=1; } || true

  #   3. N/A WITH A REASON, never a silent skip and never a false OK. rc 3 (not an adopted tree) must
  #      render N/A — and must NOT inflate the verdict (an inapplicable check is not a warning).
  na_stub="sh $stubd/na"
  nout=$(DOCTOR_VERIFY_CMD=true DOCTOR_CLAIMS_CMD=true DOCTOR_KITCURRENT_CMD="$na_stub" sh "$0" --selftest-e2e 2>&1) || true
  printf '%s\n' "$nout" | grep -qE 'kit-update[[:space:]]+N/A' || { echo "doctor --selftest: FAIL (rc 3 did not render an N/A row)"; sfail=1; }
  printf '%s\n' "$nout" | grep -q 'no kit-base'  || { echo "doctor --selftest: FAIL (the N/A row does not carry the check's REASON — a silent skip)"; sfail=1; }
  printf '%s\n' "$nout" | grep -qE 'kit-update[[:space:]]+OK' && { echo "doctor --selftest: FAIL (an N/A tree was rendered as OK — a false green)"; sfail=1; } || true
  #   ...and a genuine N/A must NOT nag: no WARN row, and no "go run kit-update" advice line. NB this is
  #   asserted on the ROW, deliberately, and NOT on 'Overall:' — the git dimension warns independently
  #   (dirty tree, detached HEAD in CI), so an Overall assertion would be brittle AND, worse, VACUOUS
  #   whenever git had already saturated the verdict to WARN. The row is the observable contract.
  printf '%s\n' "$nout" | grep -qE 'kit-update[[:space:]]+WARN' && { echo "doctor --selftest: FAIL (an INAPPLICABLE check raised a WARN — the wolf-crying this avoids)"; sfail=1; } || true
  printf '%s\n' "$nout" | grep -q 'see the delta' && { echo "doctor --selftest: FAIL (an N/A tree was told to run kit-update)"; sfail=1; } || true

  #   4. UNVERIFIED (offline) must NEVER read as up-to-date. It is an unknown, and it is surfaced as one.
  un_stub="sh $stubd/unver"
  uout=$(DOCTOR_VERIFY_CMD=true DOCTOR_CLAIMS_CMD=true DOCTOR_KITCURRENT_CMD="$un_stub" sh "$0" --selftest-e2e 2>&1) || true
  printf '%s\n' "$uout" | grep -qE 'kit-update[[:space:]]+N/A' || { echo "doctor --selftest: FAIL (UNVERIFIED did not render an N/A row)"; sfail=1; }
  printf '%s\n' "$uout" | grep -qE 'kit-update[[:space:]]+OK' && { echo "doctor --selftest: FAIL (an UNREACHABLE source rendered as OK — absence of evidence read as currency)"; sfail=1; } || true
  rm -rf "$stubd" 2>/dev/null || true

  # — exit logic: all-pass stubs → exit 0 ——————————————————————————————————
  DOCTOR_VERIFY_CMD=true DOCTOR_CLAIMS_CMD=true sh "$0" --selftest-e2e >/dev/null 2>&1
  _pass_rc=$?
  [ "$_pass_rc" = "0" ] || {
    echo "doctor --selftest: FAIL (all-pass stubs produced exit $_pass_rc, expected 0)"
    sfail=1
  }

  # — exit logic: verify FAIL stub → gate triggers → exit 1 ————————————————
  _fail_rc=0
  DOCTOR_VERIFY_CMD=false DOCTOR_CLAIMS_CMD=true sh "$0" --selftest-e2e >/dev/null 2>&1 || _fail_rc=$?
  [ "$_fail_rc" = "1" ] || {
    echo "doctor --selftest: FAIL (verify-fail stub produced exit $_fail_rc, expected 1)"
    sfail=1
  }

  # — T2a: --full output contains METRICS heading and non-gating label ———————
  full_out=$(DOCTOR_VERIFY_CMD=true DOCTOR_CLAIMS_CMD=true DOCTOR_NONVACUITY_CMD=true sh "$0" --selftest-e2e --full 2>&1) || true
  printf '%s\n' "$full_out" | grep -q "METRICS"              || { echo "doctor --selftest: FAIL (--full: no METRICS section)"; sfail=1; }
  printf '%s\n' "$full_out" | grep -q "does not affect exit" || { echo "doctor --selftest: FAIL (--full: no 'does not affect exit' label)"; sfail=1; }

  # — T2b: forced-failing metrics must NOT change the exit code —————————————
  posture_rc=0
  DOCTOR_VERIFY_CMD=true DOCTOR_CLAIMS_CMD=true sh "$0" --selftest-e2e >/dev/null 2>&1 || posture_rc=$?
  forced_rc=0
  DOCTOR_VERIFY_CMD=true DOCTOR_CLAIMS_CMD=true DOCTOR_DORA_CMD=false DOCTOR_SCORECARD_CMD=false DOCTOR_META_CONTROL_CMD=false DOCTOR_NONVACUITY_CMD=false sh "$0" --selftest-e2e --full >/dev/null 2>&1 || forced_rc=$?
  [ "$forced_rc" = "$posture_rc" ] || {
    echo "doctor --selftest: FAIL (non-gating invariant broken: forced-failing metrics changed exit from $posture_rc to $forced_rc)"
    sfail=1
  }

  # — FLAG-NOT-ENV: a REAL run (no seam flag) IGNORES an ambient DOCTOR_*_CMD ————————————————
  # The DOCTOR_*_CMD injection seams are honored ONLY under the internal --selftest-e2e flag that THIS
  # selftest's child invocations pass. In an adopter's real `doctor` run the ambient environment must not
  # be able to redirect a check: `DOCTOR_KITCURRENT_CMD=true doctor` would otherwise render a clean OK
  # without ever running kit-current.sh — the KW21 failure recurring inside its own fix. A check the
  # environment can redirect is not a check. Marker technique (mirrors preflight's PREFLIGHT_GIT_VERSION_CMD
  # proof): point the seam at a command that touches a marker; in a REAL run the marker must NOT appear.
  # A SINGLE real invocation (no --selftest-e2e flag) with all three ambient seams pointed at distinct
  # markers: none may appear. The invocation targets an ISOLATED COPY of this script in a bare temp tree
  # with no conformance/ siblings — a faithful real run (SEAMS=0, no seam flag) that exercises the exact
  # seam-gating path, but whose dimensions fall to their cheap "not present" branch. That isolation is
  # load-bearing: a real doctor run in THIS tree invokes conformance/verify.sh, which runs doctor-wired.sh,
  # which runs `doctor --selftest` — so a marker run against the in-tree script would recurse without end.
  # Pre-fix the seams are honored (cheap `touch` stubs run); post-fix they are ignored. Either way: fast,
  # deterministic, no recursion.
  # HOME is redirected into the empty temp tree so the real ~/.claude/settings.json is NEVER read by this
  # marker run (the accretion reader resolves its user-global path under $HOME; hermeticity, design §5).
  _sd=$(mktemp -d); _rd=$(mktemp -d); mkdir -p "$_rd/scripts"; cp "$0" "$_rd/scripts/doctor.sh"
  HOME="$_rd" DOCTOR_KITCURRENT_CMD="touch $_sd/kc" DOCTOR_VERIFY_CMD="touch $_sd/vf" DOCTOR_CLAIMS_CMD="touch $_sd/cl" \
    sh "$_rd/scripts/doctor.sh" >/dev/null 2>&1 || true
  [ -e "$_sd/kc" ] && { echo "doctor --selftest: FAIL (an AMBIENT DOCTOR_KITCURRENT_CMD was honored in a real run — env, not flag)"; sfail=1; } || true
  [ -e "$_sd/vf" ] && { echo "doctor --selftest: FAIL (an AMBIENT DOCTOR_VERIFY_CMD was honored in a real run — env, not flag)"; sfail=1; } || true
  [ -e "$_sd/cl" ] && { echo "doctor --selftest: FAIL (an AMBIENT DOCTOR_CLAIMS_CMD was honored in a real run — env, not flag)"; sfail=1; } || true
  rm -rf "$_sd" "$_rd" 2>/dev/null || true

  # — SWAS-168 silent-battery legs: the real conformance + claims calls announce themselves on STDERR
  #   (before the result row, never on stdout); the seam paths stay silent (keeps the e2e check non-vacuous).
  #   Same isolated-copy technique as above (no --selftest-e2e flag), with stub verify/claims that exit 0.
  _rd=$(mktemp -d); mkdir -p "$_rd/scripts" "$_rd/conformance"; cp "$0" "$_rd/scripts/doctor.sh"
  printf 'exit 0\n' > "$_rd/conformance/verify.sh"; printf 'exit 0\n' > "$_rd/conformance/claims-registry.sh"
  _bl='doctor: running the conformance battery (conformance/verify.sh)'
  _cl='doctor: checking the claims registry (conformance/claims-registry.sh)'
  printf 'exit 0\n' > "$_rd/conformance/non-vacuity.sh"
  # SWAS-199: claims is kit-self, so this leg plants a kit marker to keep testing the kit-tree path.
  mkdir -p "$_rd/docs"; : > "$_rd/docs/ROADMAP-KIT.md"
  _sout=$(cd "$_rd" && HOME="$_rd" GIT_CEILING_DIRECTORIES="$_rd" sh "$_rd/scripts/doctor.sh" 2>"$_rd/err" || true)
  _fout=$(cd "$_rd" && HOME="$_rd" GIT_CEILING_DIRECTORIES="$_rd" sh "$_rd/scripts/doctor.sh" --full 2>"$_rd/err2" || true)
  _both=$(cd "$_rd" && HOME="$_rd" GIT_CEILING_DIRECTORIES="$_rd" sh "$_rd/scripts/doctor.sh" 2>&1 || true)
  _bn=$(printf '%s\n' "$_both" | grep -n "$_bl" | head -1 | cut -d: -f1)
  _cn=$(printf '%s\n' "$_both" | grep -n "$_cl" | head -1 | cut -d: -f1)
  _rn=$(printf '%s\n' "$_both" | grep -nE '^  conformance[[:space:]]' | head -1 | cut -d: -f1)
  _kn=$(printf '%s\n' "$_both" | grep -nE '^  claims[[:space:]]' | head -1 | cut -d: -f1)
  { grep -qF "$_bl" "$_rd/err" && ! printf '%s\n' "$_sout" | grep -qF "$_bl" \
    && [ -n "$_bn" ] && [ -n "$_rn" ] && [ "$_bn" -lt "$_rn" ]; } \
    || { echo "doctor --selftest: FAIL (the conformance-battery progress line is missing, on stdout, or not before the conformance row)"; sfail=1; }
  { grep -qF "$_cl" "$_rd/err" && ! printf '%s\n' "$_sout" | grep -qF "$_cl" \
    && [ -n "$_cn" ] && [ -n "$_kn" ] && [ "$_cn" -lt "$_kn" ]; } \
    || { echo "doctor --selftest: FAIL (the claims-registry progress line is missing, on stdout, or not before the claims row)"; sfail=1; }
  _nl='doctor: running the non-vacuity sweep (conformance/non-vacuity.sh)'
  { grep -qF "$_nl" "$_rd/err2" && ! printf '%s\n' "$_fout" | grep -qF "$_nl"; } \
    || { echo "doctor --selftest: FAIL (the --full non-vacuity progress line is missing from stderr or leaked onto stdout)"; sfail=1; }
  _seam=$(cd "$_rd" && HOME="$_rd" GIT_CEILING_DIRECTORIES="$_rd" DOCTOR_VERIFY_CMD=true DOCTOR_CLAIMS_CMD=true sh "$_rd/scripts/doctor.sh" --selftest-e2e 2>&1 || true)
  printf '%s\n' "$_seam" | grep -qE 'doctor: (running the conformance|checking the claims)' \
    && { echo "doctor --selftest: FAIL (a seam run printed a progress line; the seam paths must stay silent)"; sfail=1; } || true
  rm -rf "$_rd" 2>/dev/null || true

  # — SWAS-199 claims is kit-self (rows A-D). Isolated copy, HOME redirected, no --selftest-e2e, stub registry
  #   that exits 1 and leaves a sentinel. A = unmarked tree stands down; B = the kit tree still FAILs (the
  #   load-bearing negative); C = one marker (golden-path.yml) is enough; D = a passing kit claim is PASS.
  _kt_run() { # $1 = tree  $2 = extra doctor args ; sets _kt_out (stdout) and _kt_rc
    _kt_rc=0
    # shellcheck disable=SC2086
    _kt_out=$(cd "$1" && HOME="$1" GIT_CEILING_DIRECTORIES="$1" sh "$1/scripts/doctor.sh" $2 2>"$1/err") || _kt_rc=$?
  }
  _kt_tree() { # $1 = registry exit code ; echoes a fresh tree path
    _kd=$(mktemp -d); mkdir -p "$_kd/scripts" "$_kd/conformance"; cp "$0" "$_kd/scripts/doctor.sh"
    printf 'exit 0\n' > "$_kd/conformance/verify.sh"
    printf 'touch "%s/ran"\nexit %s\n' "$_kd" "$1" > "$_kd/conformance/claims-registry.sh"
    echo "$_kd"
  }
  _ktD=$(_kt_tree 0); mkdir -p "$_ktD/docs"; : > "$_ktD/docs/ROADMAP-KIT.md"
  _kt_run "$_ktD" ""
  _dover=$(printf '%s\n' "$_kt_out" | grep -E '^Overall:' | head -1)
  printf '%s\n' "$_kt_out" | grep -qE '^  claims[[:space:]]+PASS$' \
    || { echo "doctor --selftest: FAIL (row D: a passing claim on a kit-marked tree did not render PASS)"; sfail=1; }
  _ktA=$(_kt_tree 1)
  for _kx in "" "--require"; do
    _kt_run "$_ktA" "$_kx"
    printf '%s\n' "$_kt_out" | grep -E '^  claims[[:space:]]' | grep -q "N/A (kit-self.*this project's own claims are not graded here)\$" \
      || { echo "doctor --selftest: FAIL (row A: an unmarked tree did not render claims N/A (kit-self) [args: $_kx])"; sfail=1; }
    [ ! -e "$_ktA/ran" ] || { echo "doctor --selftest: FAIL (row A: the claims registry ran on an unmarked tree [args: $_kx])"; sfail=1; }
    ! grep -q 'checking the claims registry' "$_ktA/err" \
      || { echo "doctor --selftest: FAIL (row A: a claims progress line appeared on an unmarked tree [args: $_kx])"; sfail=1; }
    [ "$(printf '%s\n' "$_kt_out" | grep -E '^Overall:' | head -1)" = "$_dover" ] \
      || { echo "doctor --selftest: FAIL (row A: the claims N/A changed the Overall line vs the passing-claim baseline [args: $_kx])"; sfail=1; }
    [ "$_kx" != "--require" ] || [ "$_kt_rc" -ne 1 ] \
      || { echo "doctor --selftest: FAIL (row A: claims N/A made --require exit 1)"; sfail=1; }
  done
  _ktB=$(_kt_tree 1); mkdir -p "$_ktB/docs"; : > "$_ktB/docs/ROADMAP-KIT.md"
  _kt_run "$_ktB" ""
  { printf '%s\n' "$_kt_out" | grep -qE '^  claims[[:space:]]+FAIL$' && printf '%s\n' "$_kt_out" | grep -q '^Overall: FAIL' && [ "$_kt_rc" -eq 1 ]; } \
    || { echo "doctor --selftest: FAIL (row B: a failing claim on the kit tree did not render claims FAIL / Overall: FAIL / exit 1)"; sfail=1; }
  _ktC=$(_kt_tree 1); mkdir -p "$_ktC/.github/workflows"; : > "$_ktC/.github/workflows/golden-path.yml"
  _kt_run "$_ktC" ""
  printf '%s\n' "$_kt_out" | grep -qE '^  claims[[:space:]]+FAIL$' \
    || { echo "doctor --selftest: FAIL (row C: golden-path.yml alone did not arm the claims dimension)"; sfail=1; }
  rm -rf "$_ktA" "$_ktB" "$_ktC" "$_ktD" 2>/dev/null || true

  # — permission-local-accretion legs (HERMETIC mktemp fixtures ONLY — the reader is pointed at throwaway
  #   JSON via the DOCTOR_ACCRETION_* seams; the owner's real ~/.claude/settings.json and
  #   .claude/settings.local.json are NEVER read here, design §5 / substrate-g FIXTURE-HERMETICITY). ————
  accd=$(mktemp -d)
  acctsv="$accd/tsv"
  {
    printf 'command-pattern\tdisposition\tsurface\n'
    printf 'Read\tallow\tshipped\n'
    printf 'Bash(git status:*)\tallow\tshipped\n'
    printf 'Bash(gh pr merge:*)\tallow\truling-only\n'
    printf 'Bash(sh scripts/publish-public.sh*)\tallow\truling-only\n'
    printf 'Bash(rm -rf:*)\tdeny\tshipped\n'
    printf 'Bash(npm publish:*)\tdeny\tshipped\n'
    printf 'Write(.env)\tdeny\tshipped\n'
    printf 'gh pr merge --admin\tdeliberately-absent\truling-only\n'
  } > "$acctsv"

  # run doctor (default posture) with LOCAL pointed at a fixture and the user-global half absent.
  _accd_run() { # $1 = local fixture path ; echoes default-posture output
    DOCTOR_VERIFY_CMD=true DOCTOR_CLAIMS_CMD=true DOCTOR_KITCURRENT_CMD=true \
      DOCTOR_ACCRETION_LOCAL="$1" DOCTOR_ACCRETION_USER="$accd/absent-user" \
      DOCTOR_ACCRETION_TSV="$acctsv" DOCTOR_ACCRETION_JQ="jq" \
      sh "$0" --selftest-e2e 2>&1 || true
  }
  _acc_warn() { # $1 label  $2 json — the loud class MUST fire (permissions WARN)
    printf '%s\n' "$2" > "$accd/f.json"
    _o=$(_accd_run "$accd/f.json")
    printf '%s\n' "$_o" | grep -qE 'permissions[[:space:]]+WARN' \
      || { echo "doctor --selftest: FAIL (accretion loud '$1' did NOT fire a permissions WARN)"; sfail=1; }
  }
  _acc_ok() {   # $1 label  $2 json — the carve-out must stay quiet (permissions OK, no WARN)
    printf '%s\n' "$2" > "$accd/f.json"
    _o=$(_accd_run "$accd/f.json")
    printf '%s\n' "$_o" | grep -qE 'permissions[[:space:]]+OK' \
      || { echo "doctor --selftest: FAIL (accretion carve-out '$1' did NOT render permissions OK)"; sfail=1; }
    printf '%s\n' "$_o" | grep -qE 'permissions[[:space:]]+WARN' \
      && { echo "doctor --selftest: FAIL (accretion carve-out '$1' wrongly fired a permissions WARN — wolf-crying)"; sfail=1; } || true
  }

  # 1. clean fixture → quiet OK, and the --full count is 0.
  _clean='{"permissions":{"allow":["Read","Bash(git status:*)","Bash(gh pr merge:*)","Bash(sh scripts/publish-public.sh*)"]}}'
  _acc_ok "clean" "$_clean"
  printf '%s\n' "$_clean" > "$accd/f.json"
  _o=$(DOCTOR_VERIFY_CMD=true DOCTOR_CLAIMS_CMD=true DOCTOR_KITCURRENT_CMD=true \
       DOCTOR_DORA_CMD=true DOCTOR_SCORECARD_CMD=true DOCTOR_NONVACUITY_CMD=true DOCTOR_META_CONTROL_CMD=true \
       DOCTOR_ACCRETION_LOCAL="$accd/f.json" \
       DOCTOR_ACCRETION_USER="$accd/absent-user" DOCTOR_ACCRETION_TSV="$acctsv" \
       sh "$0" --selftest-e2e --full 2>&1) || true
  printf '%s\n' "$_o" | grep -q 'permission-local-accretion: 0 local' \
    || { echo "doctor --selftest: FAIL (clean fixture did not report a 0 accretion count under --full)"; sfail=1; }

  # 2. accretion planted → the --full count is >= 1 (a count, never the pattern).
  printf '%s\n' '{"permissions":{"allow":["Bash(git status:*)","Bash(some-unsanctioned-tool:*)"]}}' > "$accd/f.json"
  _o=$(DOCTOR_VERIFY_CMD=true DOCTOR_CLAIMS_CMD=true DOCTOR_KITCURRENT_CMD=true \
       DOCTOR_DORA_CMD=true DOCTOR_SCORECARD_CMD=true DOCTOR_NONVACUITY_CMD=true DOCTOR_META_CONTROL_CMD=true \
       DOCTOR_ACCRETION_LOCAL="$accd/f.json" \
       DOCTOR_ACCRETION_USER="$accd/absent-user" DOCTOR_ACCRETION_TSV="$acctsv" \
       sh "$0" --selftest-e2e --full 2>&1) || true
  printf '%s\n' "$_o" | grep -qE 'permission-local-accretion: [1-9][0-9]* local' \
    || { echo "doctor --selftest: FAIL (a planted accretion did not raise the count >= 1)"; sfail=1; }
  printf '%s\n' "$_o" | grep -q 'some-unsanctioned-tool' \
    && { echo "doctor --selftest: FAIL (the accretion metric LEAKED a local allow string — §5 privacy: counts only)"; sfail=1; } || true

  # 3. laundering — each engine-honored EVASION must fire (design §3 F1 evasion fixtures).
  _acc_warn "double-space --admin"   '{"permissions":{"allow":["Bash(gh pr merge  --admin:*)"]}}'
  _acc_warn "flag-reorder --admin"   '{"permissions":{"allow":["Bash(gh pr merge --squash --admin:*)"]}}'
  _acc_warn "--admin=true"           '{"permissions":{"allow":["Bash(gh pr merge --admin=true:*)"]}}'
  _acc_warn "rm -fr"                 '{"permissions":{"allow":["Bash(rm -fr:*)"]}}'
  _acc_warn "rm --recursive --force" '{"permissions":{"allow":["Bash(rm --recursive --force:*)"]}}'
  _acc_warn "rm -Rf (uppercase -R)"  '{"permissions":{"allow":["Bash(rm -Rf:*)"]}}'
  _acc_warn "rm -R -f (split -R)"    '{"permissions":{"allow":["Bash(rm -R -f:*)"]}}'
  _acc_warn "Bash(gh:*) superset"    '{"permissions":{"allow":["Bash(gh:*)"]}}'
  _acc_warn "Bash(rm:*) superset"    '{"permissions":{"allow":["Bash(rm:*)"]}}'
  _acc_warn "Write(.env.local)"      '{"permissions":{"allow":["Write(.env.local)"]}}'

  # 4. laundering — the carve-outs must NOT fire.
  _acc_ok "plain gh pr merge"   '{"permissions":{"allow":["Bash(gh pr merge:*)"]}}'
  _acc_ok "publish-public.sh"   '{"permissions":{"allow":["Bash(sh scripts/publish-public.sh*)"]}}'
  _acc_ok "Write(.env.example)" '{"permissions":{"allow":["Write(.env.example)"]}}'

  # 5. hook-tamper / escalation — each key fires (design §3.3 F6).
  _acc_warn "disableAllHooks true"   '{"disableAllHooks":true,"permissions":{"allow":[]}}'
  _acc_warn "disableAllHooks \"1\""  '{"disableAllHooks":"1","permissions":{"allow":[]}}'
  _acc_warn "env KIT_GUARD_SELFEDIT" '{"env":{"KIT_GUARD_SELFEDIT":"1"},"permissions":{"allow":[]}}'
  _acc_warn "env NODE_OPTIONS"       '{"env":{"NODE_OPTIONS":"--require /tmp/x.js"},"permissions":{"allow":[]}}'
  _acc_warn "env PATH"               '{"env":{"PATH":"/tmp/evil:/usr/bin"},"permissions":{"allow":[]}}'
  _acc_ok   "env MY_APP_URL benign"  '{"env":{"MY_APP_URL":"https://example.test"},"permissions":{"allow":[]}}'
  _acc_warn "defaultMode bypass"     '{"permissions":{"defaultMode":"bypassPermissions","allow":[]}}'
  _acc_warn "hooks.PreToolUse"       '{"hooks":{"PreToolUse":[{"matcher":"Bash"}]},"permissions":{"allow":[]}}'
  _acc_warn "hooks.PostToolUse"      '{"hooks":{"PostToolUse":[]},"permissions":{"allow":[]}}'

  # 6. FAIL-SAFE (design §3 F4) — absent / malformed / jq-absent → N/A-with-reason, NEVER a false OK.
  _o=$(DOCTOR_VERIFY_CMD=true DOCTOR_CLAIMS_CMD=true DOCTOR_KITCURRENT_CMD=true DOCTOR_ACCRETION_LOCAL="$accd/none-l" \
       DOCTOR_ACCRETION_USER="$accd/none-u" DOCTOR_ACCRETION_TSV="$acctsv" \
       sh "$0" --selftest-e2e 2>&1) || true
  printf '%s\n' "$_o" | grep -qE 'permissions[[:space:]]+N/A' \
    || { echo "doctor --selftest: FAIL (both files absent did not render a permissions N/A)"; sfail=1; }

  printf '%s\n' '{bad json not valid,,,' > "$accd/bad.json"
  _o=$(_accd_run "$accd/bad.json")
  printf '%s\n' "$_o" | grep -qE 'permissions[[:space:]]+N/A' \
    || { echo "doctor --selftest: FAIL (malformed JSON did not render a permissions N/A)"; sfail=1; }
  printf '%s\n' "$_o" | grep -qE 'permissions[[:space:]]+OK' \
    && { echo "doctor --selftest: FAIL (malformed JSON rendered a permissions OK — a FALSE all-clear on a parse failure)"; sfail=1; } || true

  printf '%s\n' "$_clean" > "$accd/f.json"
  _o=$(DOCTOR_VERIFY_CMD=true DOCTOR_CLAIMS_CMD=true DOCTOR_KITCURRENT_CMD=true DOCTOR_ACCRETION_LOCAL="$accd/f.json" \
       DOCTOR_ACCRETION_USER="$accd/absent-user" DOCTOR_ACCRETION_TSV="$acctsv" \
       DOCTOR_ACCRETION_JQ="$accd/no-such-jq-binary" sh "$0" --selftest-e2e 2>&1) || true
  printf '%s\n' "$_o" | grep -qE 'permissions[[:space:]]+N/A' \
    || { echo "doctor --selftest: FAIL (jq-absent did not render a permissions N/A)"; sfail=1; }
  printf '%s\n' "$_o" | grep -qE 'permissions[[:space:]]+OK' \
    && { echo "doctor --selftest: FAIL (jq-absent rendered a permissions OK — a FALSE all-clear)"; sfail=1; } || true

  # 7. NON-GATING, COMBINED leg (design §3 F5) — ONE invocation on a loud-firing fixture: the loud word
  #    IS present AND doctor's exit is unchanged (0). Separate legs would let an impl fake non-gating by
  #    suppressing the signal.
  printf '%s\n' '{"permissions":{"allow":["Bash(rm -fr:*)"]}}' > "$accd/f.json"
  _ng_rc=0
  _o=$(DOCTOR_VERIFY_CMD=true DOCTOR_CLAIMS_CMD=true DOCTOR_KITCURRENT_CMD=true DOCTOR_ACCRETION_LOCAL="$accd/f.json" \
       DOCTOR_ACCRETION_USER="$accd/absent-user" DOCTOR_ACCRETION_TSV="$acctsv" \
       sh "$0" --selftest-e2e 2>&1) || _ng_rc=$?
  printf '%s\n' "$_o" | grep -qE 'permissions[[:space:]]+WARN' \
    || { echo "doctor --selftest: FAIL (combined non-gating leg: the loud class did not fire)"; sfail=1; }
  [ "$_ng_rc" = "0" ] \
    || { echo "doctor --selftest: FAIL (combined non-gating leg: a loud-firing advisory changed doctor's exit to $_ng_rc — the metric GATED)"; sfail=1; }

  # 8. FLAG-NOT-ENV pin for the file-path seams (F-5) — an ambient DOCTOR_ACCRETION_LOCAL must be IGNORED
  #    in a REAL run (no --selftest-e2e; SEAMS=0 hardcodes the real path). Isolated tree whose real local
  #    surface is ABSENT but whose enumeration IS present; the ambient seam points at a laundering DECOY.
  #    Honored → the decoy would raise a permissions WARN; a faithful real run ignores it and falls to N/A
  #    (real local + user-global both absent). HOME→empty tree so no owner file is read (privacy).
  _fd=$(mktemp -d); _fh=$(mktemp -d)
  mkdir -p "$_fd/scripts" "$_fd/conformance"
  cp "$0" "$_fd/scripts/doctor.sh"
  cp "$acctsv" "$_fd/conformance/sanctioned-commands.tsv"
  printf '%s\n' '{"permissions":{"allow":["Bash(rm -fr:*)"]}}' > "$accd/decoy.json"
  _o=$(HOME="$_fh" DOCTOR_ACCRETION_LOCAL="$accd/decoy.json" sh "$_fd/scripts/doctor.sh" 2>&1) || true
  printf '%s\n' "$_o" | grep -qE 'permissions[[:space:]]+WARN' \
    && { echo "doctor --selftest: FAIL (an AMBIENT DOCTOR_ACCRETION_LOCAL decoy was HONORED in a real run — env, not flag)"; sfail=1; } || true
  printf '%s\n' "$_o" | grep -qE 'permissions[[:space:]]+N/A' \
    || { echo "doctor --selftest: FAIL (FLAG-NOT-ENV pin: real run did not fall to N/A with the real local surface absent — the seam may have leaked)"; sfail=1; }
  rm -rf "$_fd" "$_fh" 2>/dev/null || true

  rm -rf "$accd" 2>/dev/null || true

  # — tracker credential line (SWAS-101, design D3). HERMETIC: a fixture conf and a stub store (the DOCTOR_* seams,
  #   honored only under --selftest-e2e); the real conf and the real Keychain are never read here. The environment
  #   is cleared per child by exporting the four names empty (an empty value counts as unset).
  _tcd=$(mktemp -d)
  printf 'version=1\nbackend=jira\nbase_url=https://ex.atlassian.net\nproject=AB\n' > "$_tcd/tracker.conf"
  _tcd_mk() {  # <name> <rc>: a stub store, an account line when asked for attributes, a marker token when asked with -w
    {
      printf '#!/bin/sh\nrc=%s\nd=%s\n' "$2" "$_tcd"
      cat <<'TSTUB'
printf '%s\n' "$*" >> "$d/log"
if [ "$rc" = 0 ]; then
  case "$*" in
    *" -w "*) printf 'DOCTOKMARK-77\n' ;;
    *) printf '    "acct"\074blob\076="stored@example.com"\n' ;;
  esac
fi
exit "$rc"
TSTUB
    } > "$_tcd/$1"
    chmod +x "$_tcd/$1"
  }
  _tcd_mk present 0
  _tcd_mk absent 44
  _tcd_mk locked 36
  _tcd_run() {  # <stub> <conf> [user] [token]: one default-posture doctor run, output on stdout
    : > "$_tcd/log"
    KIT_TRACKER_USER="${3:-}" KIT_TRACKER_TOKEN="${4:-}" JIRA_EMAIL='' JIRA_TOKEN='' \
      DOCTOR_VERIFY_CMD=true DOCTOR_CLAIMS_CMD=true DOCTOR_KITCURRENT_CMD=true \
      DOCTOR_TRACKER_CONF="$2" DOCTOR_SECURITY_BIN="$1" sh "$0" --selftest-e2e 2>&1 || true
  }
  _o=$(_tcd_run "$_tcd/present" "$_tcd/tracker.conf")
  printf '%s\n' "$_o" | grep -qxF 'tracker credential: keychain (item present; not read)' \
    || { echo "doctor --selftest: FAIL (a stored item did not render the keychain (item present; not read) line)"; sfail=1; }
  [ "$(wc -l < "$_tcd/log" | tr -d ' ')" = "1" ] && ! grep -qF -- '-w' "$_tcd/log" \
    || { echo "doctor --selftest: FAIL (doctor made other than ONE attribute-only store call: $(cat "$_tcd/log"))"; sfail=1; }
  # LOAD-BEARING NEGATIVE: the marker token the stub would return with -w never reaches doctor output. It kills a
  # mutant that reads the secret (adds -w) and prints it, and one that prints any store output.
  printf '%s\n' "$_o" | grep -qF 'DOCTOKMARK-77' \
    && { echo "doctor --selftest: FAIL (a store value reached doctor output)"; sfail=1; } || true
  _o=$(_tcd_run "$_tcd/absent" "$_tcd/tracker.conf")
  printf '%s\n' "$_o" | grep -qxF 'tracker credential: none - store a token once: JIRA-SETUP-TEMPLATE §5b' \
    || { echo "doctor --selftest: FAIL (an absent item did not render the none - store a token once line)"; sfail=1; }
  _o=$(_tcd_run "$_tcd/locked" "$_tcd/tracker.conf")
  printf '%s\n' "$_o" | grep -qxF 'tracker credential: keychain: the Keychain is locked' \
    || { echo "doctor --selftest: FAIL (a locked Keychain did not render its failure sentence)"; sfail=1; }
  _o=$(_tcd_run "$_tcd/present" "$_tcd/tracker.conf" env-user@example.com env-token)
  printf '%s\n' "$_o" | grep -qxF 'tracker credential: env' \
    || { echo "doctor --selftest: FAIL (an environment credential did not render the env line)"; sfail=1; }
  [ ! -s "$_tcd/log" ] \
    || { echo "doctor --selftest: FAIL (the store was consulted although the environment held a credential)"; sfail=1; }
  printf 'version=1\nbackend=jira\nbase_url=https://ex.atlassian.net:8443\nproject=AB\n' > "$_tcd/port.conf"
  _o=$(_tcd_run "$_tcd/present" "$_tcd/port.conf")
  printf '%s\n' "$_o" | grep -qxF 'tracker credential: none: the tracker base url has no host usable for a Keychain lookup' \
    || { echo "doctor --selftest: FAIL (an unusable base url did not render the none: reason line)"; sfail=1; }
  _o=$(_tcd_run "$_tcd/present" "")
  printf '%s\n' "$_o" | grep -qF 'tracker credential' \
    && { echo "doctor --selftest: FAIL (a tree with no tracker.conf printed a tracker credential line)"; sfail=1; } || true

  # — SWAS-117 D5: the identity and the agent bound. HERMETIC: DOCTOR_TRACKER_WHOAMI_CMD names a stub standing in for
  #   `sh scripts/tracker-jira.sh` (honored only under --selftest-e2e). The stub logs its argv and answers by mode.
  {
    printf '#!/bin/sh\nd=%s\n' "$_tcd"
    cat <<'WSTUB'
printf '%s\n' "$*" >> "$d/alog"
mode=$(cat "$d/mode")
case "$4" in
  whoami)
    case "$mode" in
      ok|admin|clean|unread) printf 'account-id\t712020:abc-00000042\ndisplay-name\tAgentFixture\n' ;;
      hostile) printf 'account-id\t712020:abc-00000042\ndisplay-name\tZQ"HOSTILE$(id)\nemail\tDOCEMAIL-MARK@example.com\n' ;;
      rejected) exit 6 ;;
      refused) exit 1 ;;
      *) exit 2 ;;
    esac ;;
  perms)
    case "$mode" in
      admin) printf 'BROWSE_PROJECTS\tyes\nADMINISTER_PROJECTS\tno\nADMINISTER\tyes\nSYSTEM_ADMIN\tno\nDELETE_ISSUES\tyes\n' ;;
      unread) printf 'BROWSE_PROJECTS\tyes\nADMINISTER_PROJECTS\tno\nADMINISTER\tunknown\nSYSTEM_ADMIN\tunknown\nDELETE_ISSUES\tunknown\n' ;;
      *) printf 'BROWSE_PROJECTS\tyes\nADMINISTER_PROJECTS\tno\nADMINISTER\tno\nSYSTEM_ADMIN\tno\nDELETE_ISSUES\tno\n' ;;
    esac ;;
esac
exit 0
WSTUB
  } > "$_tcd/adapter"
  _tcd_who() {  # <stub-store> <conf> <mode> [user] [token]: one default-posture run with the adapter stand-in; output on stdout
    : > "$_tcd/log"; : > "$_tcd/alog"; printf '%s' "$3" > "$_tcd/mode"
    KIT_TRACKER_USER="${4:-}" KIT_TRACKER_TOKEN="${5:-}" JIRA_EMAIL='' JIRA_TOKEN='' \
      DOCTOR_VERIFY_CMD=true DOCTOR_CLAIMS_CMD=true DOCTOR_KITCURRENT_CMD=true \
      DOCTOR_TRACKER_WHOAMI_CMD="sh $_tcd/adapter" \
      DOCTOR_TRACKER_CONF="$2" DOCTOR_SECURITY_BIN="$1" sh "$0" --selftest-e2e 2>&1 || true
  }
  _o=$(_tcd_who "$_tcd/present" "$_tcd/tracker.conf" clean)
  printf '%s\n' "$_o" | grep -qxF 'tracker credential: keychain (read for the identity check) - runs as AgentFixture (712020:abc-00000042)' \
    || { echo "doctor --selftest: FAIL (identity: a stored credential did not render the runs-as line with the read-for-the-identity-check source)"; sfail=1; }
  grep -qxF 'contract-read https://ex.atlassian.net cloud whoami --short' "$_tcd/alog" \
    && grep -qxF 'contract-read https://ex.atlassian.net cloud perms AB --short' "$_tcd/alog" \
    || { echo "doctor --selftest: FAIL (identity: doctor did not call whoami and perms with --short: $(cat "$_tcd/alog"))"; sfail=1; }
  [ "$(wc -l < "$_tcd/alog" | tr -d ' ')" = 2 ] \
    || { echo "doctor --selftest: FAIL (identity: doctor made other than TWO adapter reads)"; sfail=1; }
  printf '%s\n' "$_o" | grep -qF 'HOLDS' \
    && { echo "doctor --selftest: FAIL (identity: a non-admin credential was told it HOLDS admin permissions - wolf crying)"; sfail=1; } || true
  [ "$(wc -l < "$_tcd/log" | tr -d ' ')" = "1" ] && ! grep -qF -- '-w' "$_tcd/log" \
    || { echo "doctor --selftest: FAIL (identity: doctor's own store call was other than ONE attribute-only call)"; sfail=1; }
  _o=$(_tcd_who "$_tcd/present" "$_tcd/tracker.conf" clean env-user@example.com env-token)
  printf '%s\n' "$_o" | grep -qxF 'tracker credential: env - runs as AgentFixture (712020:abc-00000042)' \
    || { echo "doctor --selftest: FAIL (identity: an environment credential did not render the runs-as line)"; sfail=1; }
  # LOAD-BEARING (the agent bound): a credential that holds ADMINISTER or DELETE_ISSUES says so, names the cure, raises ONE doctor
  # warn (Overall: WARN) and never fails the build (rc 0). Kills a mutant that drops the HOLDS suffix or the warn, or gates.
  _wrc=0
  _o=$(_tcd_who "$_tcd/present" "$_tcd/tracker.conf" admin env-user@example.com env-token)
  printf '%s\n' "$_o" | grep -qxF 'tracker credential: env - runs as AgentFixture (712020:abc-00000042) - HOLDS ADMINISTER, DELETE_ISSUES: lanes must run as a non-admin agent account, run --preflight --as agent' \
    || { echo "doctor --selftest: FAIL (agent bound: an admin credential did not render the HOLDS line)"; sfail=1; }
  printf '%s\n' "$_o" | grep -q '^Overall: WARN' \
    || { echo "doctor --selftest: FAIL (agent bound: an admin credential did not raise the doctor warn)"; sfail=1; }
  KIT_TRACKER_USER=env-user@example.com KIT_TRACKER_TOKEN=env-token JIRA_EMAIL='' JIRA_TOKEN='' \
    DOCTOR_VERIFY_CMD=true DOCTOR_CLAIMS_CMD=true DOCTOR_KITCURRENT_CMD=true DOCTOR_TRACKER_WHOAMI_CMD="sh $_tcd/adapter" \
    DOCTOR_TRACKER_CONF="$_tcd/tracker.conf" DOCTOR_SECURITY_BIN="$_tcd/present" sh "$0" --selftest-e2e >/dev/null 2>&1 || _wrc=$?
  [ "$_wrc" = 0 ] \
    || { echo "doctor --selftest: FAIL (agent bound: an admin credential changed doctor's exit to $_wrc - the line must stay advisory, never gate_fail)"; sfail=1; }
  _o=$(_tcd_who "$_tcd/present" "$_tcd/tracker.conf" rejected env-user@example.com env-token)
  printf '%s\n' "$_o" | grep -qxF 'tracker credential: env - Jira did not accept it' \
    || { echo "doctor --selftest: FAIL (identity: a rejected credential (rc 6) did not render 'Jira did not accept it')"; sfail=1; }
  grep -qF ' perms ' "$_tcd/alog" \
    && { echo "doctor --selftest: FAIL (identity: the perms read was made after the whoami read was rejected)"; sfail=1; } || true
  _o=$(_tcd_who "$_tcd/present" "$_tcd/tracker.conf" down env-user@example.com env-token)
  printf '%s\n' "$_o" | grep -qxF 'tracker credential: env - not reachable' \
    || { echo "doctor --selftest: FAIL (identity: an unreachable site did not render 'not reachable')"; sfail=1; }
  _o=$(_tcd_who "$_tcd/present" "$_tcd/tracker.conf" refused)
  printf '%s\n' "$_o" | grep -qF 'tracker credential: keychain (read for the identity check) - not read (the Keychain did not answer; an item made in Keychain Access.app prompts on every read' \
    || { echo "doctor --selftest: FAIL (identity: a Keychain read that failed did not say the Keychain did not answer)"; sfail=1; }
  # M-1: the stub answers as the REAL adapter now does: rc 1 is a refusal before any request. From the Keychain that is the
  # Keychain sentence (above); from the environment (or any other source) it is a configuration refusal, never "not reachable".
  _o=$(_tcd_who "$_tcd/present" "$_tcd/tracker.conf" refused env-user@example.com env-token)
  printf '%s\n' "$_o" | grep -qxF 'tracker credential: env - the adapter refused (configuration)' \
    || { echo "doctor --selftest: FAIL (identity: a refusal from an environment credential did not render the configuration text)"; sfail=1; }
  printf '%s\n' "$_o" | grep -F 'tracker credential:' | grep -qiF -e 'Keychain' -e 'not reachable' \
    && { echo "doctor --selftest: FAIL (identity: a configuration refusal blamed the Keychain or the network)"; sfail=1; } || true
  # S-L1: nothing held but the admin keys unanswered says so, and does not warn
  _o=$(_tcd_who "$_tcd/present" "$_tcd/tracker.conf" unread env-user@example.com env-token)
  printf '%s\n' "$_o" | grep -qxF 'tracker credential: env - runs as AgentFixture (712020:abc-00000042) - admin keys unreadable' \
    || { echo "doctor --selftest: FAIL (identity: unanswered admin keys did not render 'admin keys unreadable')"; sfail=1; }
  printf '%s\n' "$_o" | grep -qF 'HOLDS' \
    && { echo "doctor --selftest: FAIL (identity: unanswered admin keys were reported as HELD)"; sfail=1; } || true
  # LOAD-BEARING (the hostile name): the line shows the reason, never the value, and never the email.
  _o=$(_tcd_who "$_tcd/present" "$_tcd/tracker.conf" hostile env-user@example.com env-token)
  printf '%s\n' "$_o" | grep -qxF 'tracker credential: env - runs as ? (outside the printable set) (712020:abc-00000042)' \
    || { echo "doctor --selftest: FAIL (identity: a hostile display name was not rendered as ? (outside the printable set))"; sfail=1; }
  printf '%s\n' "$_o" | grep -qF -e 'ZQ' -e 'DOCEMAIL-MARK' \
    && { echo "doctor --selftest: FAIL (identity: a hostile name or the email reached doctor output)"; sfail=1; } || true
  # no conf, or no credential: the seam is never called (count 0)
  _o=$(_tcd_who "$_tcd/present" "" clean env-user@example.com env-token)
  [ ! -s "$_tcd/alog" ] \
    || { echo "doctor --selftest: FAIL (identity: an adapter read was made in a tree with no tracker.conf)"; sfail=1; }
  _o=$(_tcd_who "$_tcd/absent" "$_tcd/tracker.conf" clean)
  [ ! -s "$_tcd/alog" ] \
    || { echo "doctor --selftest: FAIL (identity: an adapter read was made with no credential at all)"; sfail=1; }
  printf '%s\n' "$_o" | grep -qxF 'tracker credential: none - store a token once: JIRA-SETUP-TEMPLATE §5b' \
    || { echo "doctor --selftest: FAIL (identity: no credential did not keep the none - store a token once line)"; sfail=1; }
  # a non-jira conf is not asked either
  printf 'version=1\nbackend=md\nbase_url=https://ex.atlassian.net\nproject=AB\n' > "$_tcd/md.conf"
  _o=$(_tcd_who "$_tcd/present" "$_tcd/md.conf" clean env-user@example.com env-token)
  [ ! -s "$_tcd/alog" ] \
    || { echo "doctor --selftest: FAIL (identity: an adapter read was made for a non-jira backend)"; sfail=1; }
  # FLAG-NOT-ENV: an AMBIENT DOCTOR_TRACKER_WHOAMI_CMD is ignored in a real run. An isolated tree with a jira conf, an
  # environment credential and an adapter stub that only records that the REAL path reached it (rc 2): the ambient seam's
  # marker must stay absent, and the adapter marker must be present (otherwise the run never got that far and proves nothing).
  _wd=$(mktemp -d); _wh=$(mktemp -d); _wm=$(mktemp -d)
  mkdir -p "$_wd/scripts" "$_wd/.kit"
  cp "$0" "$_wd/scripts/doctor.sh"
  cp scripts/tracker-cred.sh scripts/tracker-conf.sh "$_wd/scripts/"
  cp "$_tcd/tracker.conf" "$_wd/.kit/tracker.conf"
  printf '#!/bin/sh\necho reached >> "%s/adapter"\nexit 2\n' "$_wm" > "$_wd/scripts/tracker-jira.sh"
  HOME="$_wh" KIT_TRACKER_USER=env-user@example.com KIT_TRACKER_TOKEN=env-token DOCTOR_TRACKER_WHOAMI_CMD="touch $_wm/seam" \
    sh "$_wd/scripts/doctor.sh" >/dev/null 2>&1 || true
  [ -e "$_wm/seam" ] \
    && { echo "doctor --selftest: FAIL (an AMBIENT DOCTOR_TRACKER_WHOAMI_CMD was honored in a real run - env, not flag)"; sfail=1; } || true
  [ -e "$_wm/adapter" ] \
    || { echo "doctor --selftest: FAIL (the ambient-seam leg never reached the real adapter path: vacuous)"; sfail=1; }
  rm -rf "$_wd" "$_wh" "$_wm" 2>/dev/null || true
  rm -rf "$_tcd" 2>/dev/null || true

  # — SWAS-124: the forge identity line and `--as agent`. HERMETIC: DOCTOR_FORGE_CMD names a stub standing in for `gh`,
  #   DOCTOR_FORGE_ORIGIN for `git remote get-url origin` (both honored only under --selftest-e2e). The stub logs its argv and
  #   answers by mode. Every fixture identity is a role name; no real login or email appears here.
  _fgd=$(mktemp -d)
  {
    printf '#!/bin/sh\nd=%s\n' "$_fgd"
    cat <<'FSTUB'
printf '%s\n' "$*" >> "$d/flog"
mode=$(cat "$d/fmode")
case "$1 $2" in
  "api user")
    case "$mode" in
      ci) echo "gh: Resource not accessible by integration (HTTP 403)" >&2; exit 1 ;;
      unauth) echo "You are not logged into any GitHub hosts. To log in, run: gh auth login" >&2; exit 4 ;;
      *) printf 'agent-fixture\nUser\n' ;;
    esac ;;
  "api -i")
    printf 'HTTP/2.0 200 OK\r\nContent-Type: application/json\r\n'
    [ ! -s "$d/fexp" ] || printf 'Github-Authentication-Token-Expiration: %s\r\n' "$(cat "$d/fexp")"
    printf '\r\n{"login":"agent-fixture"}\n' ;;
  "api repos/"*)
    case "$mode" in
      admin) echo '{"admin":true,"maintain":true,"push":true,"triage":true,"pull":true}' ;;
      maintain) echo '{"admin":false,"maintain":true,"push":true,"triage":true,"pull":true}' ;;
      pull) echo '{"admin":false,"maintain":false,"push":false,"triage":false,"pull":true}' ;;
      unreadable) echo "null" ;;
      *) echo '{"admin":false,"maintain":false,"push":true,"triage":true,"pull":true}' ;;
    esac ;;
esac
exit 0
FSTUB
  } > "$_fgd/fstub"
  : > "$_fgd/fexp"
  # the ratification-seat declaration the forge line reads: a fixture with one SEAT= line (a role name), and one with none
  printf '# fixture: a declared ratification seat\nSEAT=seat-role\n' > "$_fgd/seat.conf"
  printf '# fixture: no seat declared\n' > "$_fgd/noseat.conf"
  _fg_run() {  # <mode> <origin> [flags]: one run through the REAL body with the stand-in; output in _o, rc in _frc (no subshell)
    : > "$_fgd/flog"; printf '%s' "$1" > "$_fgd/fmode"
    _frc=0
    # shellcheck disable=SC2086  # deliberate word-split of the flags
    # ORDER MATTERS: the three empty token assignments come LAST, just before the command word. secret-scan's generic-api-key rule
    # reads the assignment that follows a `TOKEN=''` as the key's value, and a clean run must not flag a plain env prefix.
    _o=$(DOCTOR_VERIFY_CMD=true DOCTOR_CLAIMS_CMD=true DOCTOR_KITCURRENT_CMD=true \
      DOCTOR_FORGE_CMD="sh $_fgd/fstub" DOCTOR_FORGE_ORIGIN="$2" DOCTOR_FORGE_TODAY=2026-10-12 \
      DOCTOR_FORGE_PUSHURL="${_fg_pu:-}" DOCTOR_FORGE_HELPER="${_fg_hp:-}" DOCTOR_FORGE_SEATCONF="${_fg_sc:-$_fgd/seat.conf}" \
      GH_TOKEN='' GITHUB_TOKEN='' GITHUB_PERSONAL_ACCESS_TOKEN='' \
      sh "$0" --selftest-e2e ${3:-} 2>&1) || _frc=$?
  }
  _gh_o='https://github.com/acme/widgets.git'
  # default mode: the exact lines
  _fg_run push "$_gh_o"
  printf '%s\n' "$_o" | grep -qxF 'forge identity: agent-fixture (User) — push on acme/widgets' \
    || { echo "doctor --selftest: FAIL (forge: a push login did not render the exact identity line)"; sfail=1; }
  printf '%s\n' "$_o" | grep -qF 'HOLDS' \
    && { echo "doctor --selftest: FAIL (forge: a push-only login was told it HOLDS ADMIN - wolf crying)"; sfail=1; } || true
  _push_rc=$_frc
  printf '%s\n' "$_o" | grep -qxF 'SELFTEST forge warn counted: 0' \
    || { echo "doctor --selftest: FAIL (forge-seat-warn: a push login counted a forge warn, or the counter line is missing)"; sfail=1; }
  # forge-seat-warn: admin WITH a declared seat keeps the exact HOLDS ADMIN line AND counts one warn
  _fg_run admin "$_gh_o"
  printf '%s\n' "$_o" | grep -qxF 'SELFTEST forge warn counted: 1' \
    || { echo "doctor --selftest: FAIL (forge-seat-warn: an admin login with a declared seat did not count its one warn)"; sfail=1; }
  # forge-solo-info: admin with NO seat declared reads the exact INFO line and adds no warn
  _fg_sc="$_fgd/noseat.conf"; _fg_run admin "$_gh_o"
  printf '%s\n' "$_o" | grep -qxF 'forge identity: agent-fixture (User) — admin on acme/widgets — INFO: a push-only machine user for agent sessions is the recommended posture once a separate identity reviews; see docs/operations/forge-identity-switch.md' \
    || { echo "doctor --selftest: FAIL (forge-solo-info: an admin login with no declared seat did not render the exact INFO line)"; sfail=1; }
  printf '%s\n' "$_o" | grep -qF 'HOLDS' \
    && { echo "doctor --selftest: FAIL (forge-solo-info: an admin login with no declared seat was told it HOLDS ADMIN)"; sfail=1; } || true
  printf '%s\n' "$_o" | grep -qxF 'SELFTEST forge warn counted: 0' \
    || { echo "doctor --selftest: FAIL (forge-solo-info: an admin login with no declared seat counted a forge warn)"; sfail=1; }
  _fg_run maintain "$_gh_o"
  printf '%s\n' "$_o" | grep -qF 'maintain on acme/widgets — INFO: a push-only machine user' \
    || { echo "doctor --selftest: FAIL (forge-solo-info: a maintain login with no declared seat did not render the INFO line)"; sfail=1; }
  # an absent conf is the same as no seat; the seat VALUE is never printed
  _fg_sc="$_fgd/absent.conf"; _fg_run admin "$_gh_o"
  printf '%s\n' "$_o" | grep -qF 'admin on acme/widgets — INFO:' \
    || { echo "doctor --selftest: FAIL (forge-solo-info: an absent seat conf did not read as no seat)"; sfail=1; }
  _fg_sc=''; _fg_run admin "$_gh_o"
  printf '%s\n' "$_o" | grep -qF 'seat-role' \
    && { echo "doctor --selftest: FAIL (forge-seat-warn: the seat value reached doctor output)"; sfail=1; } || true
  # forge-seat-unreadable: a conf that exists but cannot be read counts as declared (fail toward the warning)
  printf '# fixture: unreadable\n' > "$_fgd/unread.conf"; chmod 000 "$_fgd/unread.conf" 2>/dev/null || true
  if [ -r "$_fgd/unread.conf" ]; then
    echo "doctor --selftest: SKIP forge-seat-unreadable (the fixture stayed readable, as when running as root)"
  else
    _fg_sc="$_fgd/unread.conf"; _fg_run admin "$_gh_o"
    printf '%s\n' "$_o" | grep -qxF 'SELFTEST forge warn counted: 1' \
      || { echo "doctor --selftest: FAIL (forge-seat-unreadable: an unreadable seat conf did not count the warn)"; sfail=1; }
  fi
  chmod 600 "$_fgd/unread.conf" 2>/dev/null || true
  # forge-agent-noseat: --as agent is the explicit gate; with NO seat declared an admin login still exits 1 and reads HOLDS ADMIN
  _fg_sc="$_fgd/noseat.conf"; _fg_run admin "$_gh_o" '--as agent'
  [ "$_frc" = 1 ] || { echo "doctor --selftest: FAIL (forge-agent-noseat: --as agent on admin with no seat exited $_frc, expected 1)"; sfail=1; }
  printf '%s\n' "$_o" | grep -qF 'admin on acme/widgets — HOLDS ADMIN:' \
    || { echo "doctor --selftest: FAIL (forge-agent-noseat: --as agent on admin with no seat did not print the HOLDS ADMIN line)"; sfail=1; }
  _fg_sc=''
  _fg_run admin "$_gh_o"
  printf '%s\n' "$_o" | grep -qxF "forge identity: agent-fixture (User) — admin on acme/widgets — HOLDS ADMIN: agent sessions must run as the push-only machine user; run 'sparkwright doctor --as agent'" \
    || { echo "doctor --selftest: FAIL (forge: an admin login did not render the exact HOLDS ADMIN line)"; sfail=1; }
  # LOAD-BEARING (advisory): an admin login leaves doctor's exit code exactly what a push login leaves. Kills a mutant that gates default mode.
  [ "$_frc" = "$_push_rc" ] \
    || { echo "doctor --selftest: FAIL (forge: an admin login changed the default exit from $_push_rc to $_frc - the line must stay advisory)"; sfail=1; }
  _fg_run maintain "$_gh_o"
  printf '%s\n' "$_o" | grep -qxF "forge identity: agent-fixture (User) — maintain on acme/widgets — HOLDS ADMIN: agent sessions must run as the push-only machine user; run 'sparkwright doctor --as agent'" \
    || { echo "doctor --selftest: FAIL (forge: a maintain login did not render the HOLDS ADMIN line)"; sfail=1; }
  _fg_run unreadable "$_gh_o"
  printf '%s\n' "$_o" | grep -qxF 'forge identity: agent-fixture (User) — permission on acme/widgets unreadable' \
    || { echo "doctor --selftest: FAIL (forge: an unreadable permission did not render its line)"; sfail=1; }
  # CI's GITHUB_TOKEN: gh api user is 403 -> N/A, not a WARN, and the advisory stays quiet although GITHUB_TOKEN is set
  : > "$_fgd/flog"; printf '%s' ci > "$_fgd/fmode"; _frc=0
  _o=$(GITHUB_TOKEN=CIMARK-1 DOCTOR_VERIFY_CMD=true DOCTOR_CLAIMS_CMD=true DOCTOR_KITCURRENT_CMD=true DOCTOR_FORGE_CMD="sh $_fgd/fstub" \
    DOCTOR_FORGE_ORIGIN="$_gh_o" sh "$0" --selftest-e2e 2>&1) || _frc=$?
  printf '%s\n' "$_o" | grep -qxF "forge identity: N/A — this credential cannot read its own identity (HTTP 403, as under CI's GITHUB_TOKEN)" \
    || { echo "doctor --selftest: FAIL (forge: CI's 403 did not render N/A)"; sfail=1; }
  printf '%s\n' "$_o" | grep -qF -e 'forge credential' -e 'CIMARK' \
    && { echo "doctor --selftest: FAIL (forge: the advisory fired under CI's own GITHUB_TOKEN, or a value leaked)"; sfail=1; } || true
  [ "$_frc" = "$_push_rc" ] \
    || { echo "doctor --selftest: FAIL (forge: CI's 403 changed doctor's exit from $_push_rc to $_frc)"; sfail=1; }
  # a non-GitHub origin: N/A with the adapter named, and the forge is never asked (no credential sent to a host we have no adapter for)
  _fg_run push 'https://gitlab.example.com/acme/widgets.git'
  printf '%s\n' "$_o" | grep -qxF 'forge identity: N/A — no forge adapter for gitlab.example.com' \
    || { echo "doctor --selftest: FAIL (forge: a non-GitHub origin did not render N/A naming the missing adapter)"; sfail=1; }
  [ ! -s "$_fgd/flog" ] \
    || { echo "doctor --selftest: FAIL (forge: the forge was asked about a non-GitHub origin)"; sfail=1; }
  # the seam is inert by default: with no stand-in named, a --selftest-e2e child prints no forge line at all
  _o=$(DOCTOR_VERIFY_CMD=true DOCTOR_CLAIMS_CMD=true DOCTOR_KITCURRENT_CMD=true DOCTOR_FORGE_ORIGIN="$_gh_o" sh "$0" --selftest-e2e 2>&1) || true
  printf '%s\n' "$_o" | grep -qF 'forge ' \
    && { echo "doctor --selftest: FAIL (forge: a --selftest-e2e child with no stand-in printed a forge line)"; sfail=1; } || true
  # names-only advisory, and the origin credential never printed
  # The empty token assignments come LAST, just before `sh`: a value-shaped word after an empty-string token
  # assignment is what generic-api-key captured as a credential (SWAS-124 / PR #825).
  _o=$(GH_TOKEN=SECRETMARK-9 DOCTOR_VERIFY_CMD=true DOCTOR_CLAIMS_CMD=true DOCTOR_KITCURRENT_CMD=true \
    DOCTOR_FORGE_CMD="sh $_fgd/fstub" DOCTOR_FORGE_ORIGIN="https://x-access:ORIGMARK-3@github.com/acme/widgets.git" GITHUB_TOKEN='' GITHUB_PERSONAL_ACCESS_TOKEN='' sh "$0" --selftest-e2e 2>&1) || true
  printf '%s\n' "$_o" | grep -qxF 'forge credential: GH_TOKEN set in the environment (it decides which credential gh uses; doctor does not read it)' \
    || { echo "doctor --selftest: FAIL (forge: a set GH_TOKEN did not render the names-only advisory)"; sfail=1; }
  printf '%s\n' "$_o" | grep -qF -e 'SECRETMARK' -e 'ORIGMARK' \
    && { echo "doctor --selftest: FAIL (forge: a token value or an origin credential reached doctor output)"; sfail=1; } || true
  grep -qxF 'api repos/acme/widgets --jq .permissions' "$_fgd/flog" \
    || { echo "doctor --selftest: FAIL (forge: a credentialed origin did not resolve to acme/widgets: $(cat "$_fgd/flog"))"; sfail=1; }
  _fg_run push 'git@github.com:acme/widgets.git'
  printf '%s\n' "$_o" | grep -qxF "forge credential: origin is SSH (git push uses the SSH key, not gh's login; doctor cannot see whose key it is)" \
    || { echo "doctor --selftest: FAIL (forge: an SSH origin did not render the SSH advisory)"; sfail=1; }
  printf '%s\n' "$_o" | grep -qxF 'forge identity: agent-fixture (User) — push on acme/widgets' \
    || { echo "doctor --selftest: FAIL (forge: an scp-style SSH origin did not resolve to acme/widgets)"; sfail=1; }

  # --as agent: the gate
  _fg_run admin "$_gh_o" '--as agent'
  [ "$_frc" = 1 ] || { echo "doctor --selftest: FAIL (forge: --as agent on an ADMIN login exited $_frc, expected 1)"; sfail=1; }
  printf '%s\n' "$_o" | grep -qF 'holds admin on acme/widgets' \
    || { echo "doctor --selftest: FAIL (forge: --as agent on admin did not say it holds admin)"; sfail=1; }
  _fg_run maintain "$_gh_o" '--as agent'
  [ "$_frc" = 1 ] || { echo "doctor --selftest: FAIL (forge: --as agent on a MAINTAIN login exited $_frc, expected 1)"; sfail=1; }
  printf '%s\n' "$_o" | grep -qF 'holds maintain on acme/widgets' \
    || { echo "doctor --selftest: FAIL (forge: --as agent on maintain did not say it holds maintain)"; sfail=1; }
  _fg_run unreadable "$_gh_o" '--as agent'
  [ "$_frc" = 1 ] || { echo "doctor --selftest: FAIL (forge: --as agent on an UNREADABLE permission exited $_frc, expected 1 - fail-closed)"; sfail=1; }
  _fg_run unauth "$_gh_o" '--as agent'
  [ "$_frc" = 1 ] || { echo "doctor --selftest: FAIL (forge: --as agent when gh is unauthenticated exited $_frc, expected 1)"; sfail=1; }
  _fg_run pull "$_gh_o" '--as agent'
  [ "$_frc" = 1 ] || { echo "doctor --selftest: FAIL (forge: --as agent on a pull-only login exited $_frc, expected 1: a lane cannot push)"; sfail=1; }
  _fg_run push "$_gh_o" '--as agent'
  [ "$_frc" = 0 ] || { echo "doctor --selftest: FAIL (forge: --as agent on a push login exited $_frc, expected 0)"; sfail=1; }
  printf '%s\n' "$_o" | grep -qxF 'forge identity: agent-fixture (User) — push on acme/widgets' \
    || { echo "doctor --selftest: FAIL (forge: --as agent on push did not name the login with push)"; sfail=1; }
  printf '%s\n' "$_o" | grep -qF 'POSTURE' \
    && { echo "doctor --selftest: FAIL (forge: --as agent ran the full posture, not the identity check only)"; sfail=1; } || true
  # LOAD-BEARING NEGATIVE (neutrality): a non-GitHub host is UNVERIFIED rc 2 naming the adapter, never FAIL rc 1
  _fg_run admin 'https://gitlab.example.com/acme/widgets.git' '--as agent'
  [ "$_frc" = 2 ] || { echo "doctor --selftest: FAIL (forge: --as agent on a non-GitHub origin exited $_frc, expected 2 UNVERIFIED, never 1)"; sfail=1; }
  printf '%s\n' "$_o" | grep -qF 'UNVERIFIED — the kit has no forge adapter for gitlab.example.com' \
    || { echo "doctor --selftest: FAIL (forge: --as agent on a non-GitHub origin did not name the missing adapter)"; sfail=1; }
  # the usage parser: rc 2, and an unknown argument is never ignored
  for _fa in '--as' '--as human' '--as=' '--bogus' '--as agent --full' '--as agent extra'; do
    _fg_run push "$_gh_o" "$_fa"
    [ "$_frc" = 2 ] || { echo "doctor --selftest: FAIL (forge: 'doctor $_fa' exited $_frc, expected 2 usage)"; sfail=1; }
    printf '%s\n' "$_o" | grep -qF 'usage: sparkwright doctor' \
      || { echo "doctor --selftest: FAIL (forge: 'doctor $_fa' did not print the usage line)"; sfail=1; }
  done
  # the token-expiry warning: only when the header is readable AND <= 30 days away; silence otherwise, and never a gate
  printf '2026-10-30 10:00:00 UTC' > "$_fgd/fexp"
  _fg_run push "$_gh_o" '--as agent'
  printf '%s\n' "$_o" | grep -qF 'token expiry: 2026-10-30 (18 days) — WARN: renew' \
    || { echo "doctor --selftest: FAIL (forge: an expiry 18 days away did not warn)"; sfail=1; }
  [ "$_frc" = 0 ] || { echo "doctor --selftest: FAIL (forge: the expiry warning changed the exit to $_frc; it is a warning only)"; sfail=1; }
  printf '2027-10-12 10:00:00 UTC' > "$_fgd/fexp"
  _fg_run push "$_gh_o" '--as agent'
  printf '%s\n' "$_o" | grep -qF 'token expiry' \
    && { echo "doctor --selftest: FAIL (forge: an expiry a year away warned - wolf crying)"; sfail=1; } || true
  : > "$_fgd/fexp"
  _fg_run push "$_gh_o" '--as agent'
  printf '%s\n' "$_o" | grep -qF 'token expiry' \
    && { echo "doctor --selftest: FAIL (forge: an absent expiry header printed an expiry line - a guess)"; sfail=1; } || true
  # — the review round: push URL (M1), HTTPS helper (M2), seams-active marker (M3), URL parsing (L4), App/CI token (I1)
  # M3: an --as agent run under the seam flag says so on its first line; a default run carries no such marker
  _fg_run push "$_gh_o" '--as agent'
  [ "$(printf '%s\n' "$_o" | sed -n '1p')" = 'SELFTEST SEAMS ACTIVE — not a verdict' ] \
    || { echo "doctor --selftest: FAIL (forge: an --as agent run under --selftest-e2e did not open with the SELFTEST SEAMS ACTIVE marker)"; sfail=1; }
  _fg_run push "$_gh_o"
  printf '%s\n' "$_o" | grep -qF 'SELFTEST SEAMS ACTIVE' \
    && { echo "doctor --selftest: FAIL (forge: a default run carried the --as agent seams marker)"; sfail=1; } || true
  # M2: an HTTPS origin names git's credential helper (config, not a secret) and says doctor does not verify its identity
  _fg_hp='osxkeychain'
  _fg_run push "$_gh_o" '--as agent'
  printf '%s\n' "$_o" | grep -qxF "forge credential: git push over HTTPS uses git's credential helper (osxkeychain); doctor does not verify its identity" \
    || { echo "doctor --selftest: FAIL (forge: an HTTPS origin did not render the credential-helper line)"; sfail=1; }
  printf '%s\n' "$_o" | grep -qxF "agent identity: PASS — gh's login agent-fixture holds push only on acme/widgets" \
    || { echo "doctor --selftest: FAIL (forge: the PASS line did not say it is gh's login that holds push)"; sfail=1; }
  _fg_hp=''
  _fg_run push "$_gh_o" '--as agent'
  printf '%s\n' "$_o" | grep -qxF "forge credential: git push over HTTPS uses git's credential helper (none set); doctor does not verify its identity" \
    || { echo "doctor --selftest: FAIL (forge: an HTTPS origin with no helper did not render 'none set')"; sfail=1; }
  _fg_hp='!f() { echo password=HELPERSECRET; }; f'
  _fg_run push "$_gh_o" '--as agent'
  printf '%s\n' "$_o" | grep -qF 'HELPERSECRET' \
    && { echo "doctor --selftest: FAIL (forge: an inline credential helper's body reached doctor output)"; sfail=1; } || true
  _fg_hp=''
  # a helper given as an absolute path prints its basename only: the path can carry a local username
  _fg_hp='/Users/someone/bin/git-credential-foo'
  _fg_run push "$_gh_o" '--as agent'
  printf '%s\n' "$_o" | grep -qxF "forge credential: git push over HTTPS uses git's credential helper (git-credential-foo); doctor does not verify its identity" \
    || { echo "doctor --selftest: FAIL (forge: an absolute-path helper did not render as its basename)"; sfail=1; }
  printf '%s\n' "$_o" | grep -qF '/Users' \
    && { echo "doctor --selftest: FAIL (forge: a helper path prefix reached doctor output)"; sfail=1; } || true
  _fg_hp=''
  # a helper scoped to github.com alone (credential.https://github.com.helper) is seen by the REAL git read, not the seam: an isolated
  # git tree, HOME and system config redirected, a fake gh that fails (the helper line prints on every readable-or-failed identity)
  _sd2=$(mktemp -d); _sh2=$(mktemp -d); _sb2=$(mktemp -d)
  git -C "$_sd2" init -q && git -C "$_sd2" remote add origin "$_gh_o"
  git -C "$_sd2" config 'credential.https://github.com.helper' scopedhelper
  mkdir -p "$_sd2/scripts"; cp "$0" "$_sd2/scripts/doctor.sh"
  printf '#!/bin/sh\nexit 1\n' > "$_sb2/gh"; chmod +x "$_sb2/gh"
  _o=$(HOME="$_sh2" GIT_CONFIG_NOSYSTEM=1 PATH="$_sb2:$PATH" sh "$_sd2/scripts/doctor.sh" 2>&1) || true
  printf '%s\n' "$_o" | grep -qxF "forge credential: git push over HTTPS uses git's credential helper (scopedhelper); doctor does not verify its identity" \
    || { echo "doctor --selftest: FAIL (forge: a URL-scoped credential helper was not named)"; sfail=1; }
  rm -rf "$_sd2" "$_sh2" "$_sb2" 2>/dev/null || true
  # M1 (LOAD-BEARING NEGATIVE): a push URL naming another repository, host or an unparseable remote is rc 2, never 0, and gh is never asked
  for _pu in 'https://github.com/acme/other.git' 'https://gitlab.example.com/acme/widgets.git' 'not a url' "https://github.com/acme/widgets.git
https://github.com/acme/other.git"; do
    _fg_pu=$_pu
    _fg_run push "$_gh_o" '--as agent'
    [ "$_frc" = 2 ] || { echo "doctor --selftest: FAIL (forge: a push URL that differs from the fetch URL exited $_frc, expected 2 UNVERIFIED, never 0)"; sfail=1; }
    printf '%s\n' "$_o" | grep -qF "origin's push URL differs from its fetch URL" \
      || { echo "doctor --selftest: FAIL (forge: a differing push URL did not name the mismatch)"; sfail=1; }
    [ ! -s "$_fgd/flog" ] || { echo "doctor --selftest: FAIL (forge: the forge was asked although the push URL differed)"; sfail=1; }
  done
  _fg_pu='git@github.com:acme/widgets.git'
  _fg_run push "$_gh_o" '--as agent'
  [ "$_frc" = 0 ] || { echo "doctor --selftest: FAIL (forge: a push URL naming the same repository over SSH exited $_frc, expected 0)"; sfail=1; }
  printf '%s\n' "$_o" | grep -qF 'forge credential: origin is SSH' \
    || { echo "doctor --selftest: FAIL (forge: an SSH push URL did not raise the SSH advisory)"; sfail=1; }
  _fg_pu=''
  # L4: a URL whose authority disagrees with a URL parser, or a dot-segment owner, never yields a github.com repository
  for _bad in 'https://evil.example#@github.com/a/b' 'https://evil.example?@github.com/a/b' 'https://github.com/../x' 'https://github.com/a/..'; do
    _fg_run push "$_bad"
    printf '%s\n' "$_o" | grep -qxF 'forge identity: N/A — no forge adapter for an unrecognised origin' \
      || { echo "doctor --selftest: FAIL (forge: origin '$_bad' was not refused as an unrecognised origin)"; sfail=1; }
    [ ! -s "$_fgd/flog" ] || { echo "doctor --selftest: FAIL (forge: the forge was asked for origin '$_bad')"; sfail=1; }
  done
  # I1 (LOAD-BEARING NEGATIVE): a token that cannot read its own identity (an App installation or CI token) is UNVERIFIED rc 2, not FAIL
  _fg_run ci "$_gh_o" '--as agent'
  [ "$_frc" = 2 ] || { echo "doctor --selftest: FAIL (forge: --as agent under a 403 identity read exited $_frc, expected 2 UNVERIFIED)"; sfail=1; }
  printf '%s\n' "$_o" | grep -qF 'confirm on the App'"'"'s settings that it holds no Administration permission' \
    || { echo "doctor --selftest: FAIL (forge: a 403 identity read did not point at the App's Administration permission)"; sfail=1; }
  # a non-403 failure is unreadable-and-fail-closed with its own sentence
  _fg_run unauth "$_gh_o"
  printf '%s\n' "$_o" | grep -qxF "forge identity: not readable — could not read the login (gh is unauthenticated or the forge is unreachable; run 'gh auth status')" \
    || { echo "doctor --selftest: FAIL (forge: an unauthenticated read did not render its sentence)"; sfail=1; }
  # no origin at all: UNVERIFIED rc 2 under --as agent
  _fg_run push '' '--as agent'
  [ "$_frc" = 2 ] || { echo "doctor --selftest: FAIL (forge: --as agent with no origin exited $_frc, expected 2)"; sfail=1; }
  # an expired token warns (and stays a warning)
  printf '2026-10-01 10:00:00 UTC' > "$_fgd/fexp"
  _fg_run push "$_gh_o" '--as agent'
  printf '%s\n' "$_o" | grep -qF 'token expiry: 2026-10-01 (expired) — WARN: renew' \
    || { echo "doctor --selftest: FAIL (forge: an expired token did not warn)"; sfail=1; }
  [ "$_frc" = 0 ] || { echo "doctor --selftest: FAIL (forge: the expired-token warning changed the exit to $_frc)"; sfail=1; }
  : > "$_fgd/fexp"
  # FLAG-NOT-ENV: an ambient DOCTOR_FORGE_CMD is ignored in a real run. An isolated git tree whose origin is on github.com, a fake
  # `gh` on PATH that records it was reached and fails: the ambient seam's marker must stay absent and the fake gh's must be present.
  _fd=$(mktemp -d); _fh=$(mktemp -d); _fm=$(mktemp -d); _fb=$(mktemp -d)
  mkdir -p "$_fd/scripts"; cp "$0" "$_fd/scripts/doctor.sh"
  git -C "$_fd" init -q && git -C "$_fd" remote add origin "$_gh_o"
  printf '#!/bin/sh\necho reached >> "%s/gh"\nexit 1\n' "$_fm" > "$_fb/gh"; chmod +x "$_fb/gh"
  HOME="$_fh" PATH="$_fb:$PATH" DOCTOR_FORGE_CMD="touch $_fm/seam" DOCTOR_FORGE_ORIGIN='https://gitlab.example.com/a/b' \
    sh "$_fd/scripts/doctor.sh" >/dev/null 2>&1 || true
  [ -e "$_fm/seam" ] \
    && { echo "doctor --selftest: FAIL (an AMBIENT DOCTOR_FORGE_CMD was honored in a real run - env, not flag)"; sfail=1; } || true
  [ -e "$_fm/gh" ] \
    || { echo "doctor --selftest: FAIL (the ambient forge-seam leg never reached the real gh path: vacuous)"; sfail=1; }
  rm -rf "$_fd" "$_fh" "$_fm" "$_fb" "$_fgd" 2>/dev/null || true

  [ "$sfail" -eq 0 ] && { echo "doctor --selftest: OK"; exit 0; } || exit 1
fi

REQUIRE=0
FULL=0
SEAMS=0
[ -n "${CI:-}" ] && REQUIRE=1
AS_ROLE=""
AS_SET=0
_doctor_usage() {
  echo "usage: sparkwright doctor [--require] [--full] | --as agent" >&2
  echo "  --as agent  check ONLY the forge identity: exit 1 if this session's login holds admin or maintain (or cannot be read), 0 on push, 2 if unverifiable" >&2
  exit 2
}
# A real parser (SWAS-124): an unknown argument is a usage error (rc 2), not silently ignored, because `--as agent` is a
# security check and a typo such as `--as=agnet` or `--agent` must never read as a clean run.
while [ "$#" -gt 0 ]; do
  case "$1" in
    --require) REQUIRE=1 ;;
    --full)    FULL=1    ;;
    # --selftest-e2e: INTERNAL. Turns the DOCTOR_*_CMD injection seams live so `--selftest`'s battery can
    # feed pass/fail fixtures through the REAL body. Deliberately absent from any usage line: the flag IS
    # the authorization. Mirrors preflight.sh's --selftest-e2e / PREFLIGHT_GIT_VERSION_CMD gating.
    --selftest-e2e) SEAMS=1 ;;
    --as)
      [ "$#" -ge 2 ] || _doctor_usage
      AS_SET=1; AS_ROLE=$2; shift ;;
    --as=*) AS_SET=1; AS_ROLE=${1#--as=} ;;
    *) _doctor_usage ;;
  esac
  shift
done
if [ "$AS_SET" -eq 1 ]; then
  [ "$AS_ROLE" = agent ] || _doctor_usage
  # the identity check is the whole run: refuse flags that imply the full posture rather than ignore them silently
  [ "$FULL" -eq 0 ] || _doctor_usage
fi

# Variable-indirected gating + metrics commands — override in tests/selftest to inject pass/fail without
# touching the real scripts. FLAG-NOT-ENV: the seams are honored ONLY when the internal --selftest-e2e
# flag authorized them (SEAMS=1). In a real adopter run (SEAMS=0) every seam is forced empty, so the
# ambient environment cannot redirect ANY dimension — `DOCTOR_KITCURRENT_CMD=true doctor` can no longer
# fake a clean kit-update OK without running kit-current.sh. A check the environment can redirect is not a
# check (the same rule preflight's PREFLIGHT_GIT_VERSION_CMD and `incept --date` honor). The [ -f ] guard
# downstream is applied only on the default path; an overridden command is invoked directly.
if [ "$SEAMS" -eq 1 ]; then
  DOCTOR_VERIFY_CMD="${DOCTOR_VERIFY_CMD:-}"
  DOCTOR_CLAIMS_CMD="${DOCTOR_CLAIMS_CMD:-}"
  DOCTOR_DORA_CMD="${DOCTOR_DORA_CMD:-}"
  DOCTOR_SCORECARD_CMD="${DOCTOR_SCORECARD_CMD:-}"
  DOCTOR_META_CONTROL_CMD="${DOCTOR_META_CONTROL_CMD:-}"
  DOCTOR_NONVACUITY_CMD="${DOCTOR_NONVACUITY_CMD:-}"
  DOCTOR_KITCURRENT_CMD="${DOCTOR_KITCURRENT_CMD:-}"
  # permission-local-accretion FILE-PATH seams (honored ONLY under --selftest-e2e): the selftest points
  # the reader at hermetic mktemp fixtures. The LOCAL/USER paths default to EMPTY (→ absent → N/A) under
  # the seam flag on purpose — a --selftest-e2e child must NEVER read the owner's real per-machine files
  # (privacy, design §5); only an explicit fixture override makes them readable. The real surfaces are
  # read solely on the SEAMS=0 adopter path below.
  DOCTOR_ACCRETION_LOCAL="${DOCTOR_ACCRETION_LOCAL:-}"
  DOCTOR_ACCRETION_USER="${DOCTOR_ACCRETION_USER:-}"
  DOCTOR_ACCRETION_TSV="${DOCTOR_ACCRETION_TSV:-conformance/sanctioned-commands.tsv}"
  DOCTOR_ACCRETION_JQ="${DOCTOR_ACCRETION_JQ:-jq}"
  # tracker-credential line seams (honored ONLY under --selftest-e2e): the conf path defaults to EMPTY (no line)
  # and the store binary to none, so a --selftest-e2e child never reads the real conf or the real Keychain.
  DOCTOR_TRACKER_CONF="${DOCTOR_TRACKER_CONF:-}"
  DOCTOR_SECURITY_BIN="${DOCTOR_SECURITY_BIN:-/nonexistent/security}"
  # SWAS-117 D5: a stand-in for `sh scripts/tracker-jira.sh` (the identity and permission reads); empty = no read at all under
  # the seam flag, so a --selftest-e2e child never reaches the network. Honored ONLY here, never in a real run.
  DOCTOR_TRACKER_WHOAMI_CMD="${DOCTOR_TRACKER_WHOAMI_CMD:-}"
  # SWAS-124: forge-identity seams (honored ONLY under --selftest-e2e). DOCTOR_FORGE_CMD stands in for `gh` and defaults to EMPTY,
  # which under the seam flag means NO forge read at all (no line), so every older --selftest-e2e child stays offline and its
  # output unchanged. DOCTOR_FORGE_ORIGIN stands in for `git remote get-url origin`; DOCTOR_FORGE_TODAY pins the date (YYYY-MM-DD)
  # for the token-expiry arithmetic.
  DOCTOR_FORGE_CMD="${DOCTOR_FORGE_CMD:-}"
  DOCTOR_FORGE_ORIGIN="${DOCTOR_FORGE_ORIGIN:-}"
  DOCTOR_FORGE_TODAY="${DOCTOR_FORGE_TODAY:-}"
  DOCTOR_FORGE_PUSHURL="${DOCTOR_FORGE_PUSHURL:-}"
  DOCTOR_FORGE_HELPER="${DOCTOR_FORGE_HELPER:-}"
  # the ratification-seat declaration the forge line reads; under the seam a fixture conf stands in
  DOCTOR_FORGE_SEATCONF="${DOCTOR_FORGE_SEATCONF:-.kit/ratification-seats.conf}"
else
  DOCTOR_VERIFY_CMD=""
  DOCTOR_CLAIMS_CMD=""
  DOCTOR_DORA_CMD=""
  DOCTOR_SCORECARD_CMD=""
  DOCTOR_META_CONTROL_CMD=""
  DOCTOR_NONVACUITY_CMD=""
  DOCTOR_KITCURRENT_CMD=""
  # FLAG-NOT-ENV: a real adopter run FORCES the accretion reader onto the true surfaces — the ambient
  # environment cannot redirect it at a decoy fixture (a check the environment can redirect is not a check).
  DOCTOR_ACCRETION_LOCAL=".claude/settings.local.json"
  DOCTOR_ACCRETION_USER="${HOME:-}/.claude/settings.json"
  DOCTOR_ACCRETION_TSV="conformance/sanctioned-commands.tsv"
  DOCTOR_ACCRETION_JQ="jq"
  # the tracker-credential line reads the real conf and the real store binary (the library hardcodes it)
  DOCTOR_TRACKER_CONF=".kit/tracker.conf"
  DOCTOR_SECURITY_BIN=""
  DOCTOR_TRACKER_WHOAMI_CMD=""
  DOCTOR_FORGE_CMD=""
  DOCTOR_FORGE_ORIGIN=""
  DOCTOR_FORGE_TODAY=""
  DOCTOR_FORGE_PUSHURL=""
  DOCTOR_FORGE_HELPER=""
  DOCTOR_FORGE_SEATCONF=".kit/ratification-seats.conf"
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# forge identity. Posture and act sheet: docs/operations/separation-of-duties.md §Forge identity and
# docs/operations/forge-identity-switch.md.
# Who is the forge login this session runs as, and what does it hold on origin's repo? Two read-only GitHub reads:
#   gh api user --jq '.login,.type'      and      gh api repos/<owner>/<repo> --jq .permissions
# The repo comes from `origin`; only owner/repo is ever printed (an origin URL may carry a credential).
# STATED CEILING: doctor sees only the credential gh resolves. It cannot see the MCP connector, a token in another variable,
# the SSH key or git's keychain entry; docs/operations/forge-identity-switch.md proves those.
# Neutral by design: a host the kit has no forge adapter for is N/A (default) or UNVERIFIED rc 2 (--as agent), never a FAIL.
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
_fg_enabled() {  # a real run always reads; under --selftest-e2e only when the seam names a stand-in
  [ "$SEAMS" -eq 0 ] || [ -n "$DOCTOR_FORGE_CMD" ]
}
_fg_gh() {
  if [ "$SEAMS" -eq 1 ]; then
    # shellcheck disable=SC2086  # deliberate word-split of the seam command, like the other DOCTOR_*_CMD seams
    $DOCTOR_FORGE_CMD "$@"
  else
    gh "$@"
  fi
}
_fg_origin() {
  if [ "$SEAMS" -eq 1 ]; then printf '%s' "$DOCTOR_FORGE_ORIGIN"; else git remote get-url origin 2>/dev/null || true; fi
}
# every push URL of origin (one per line): git pushes to THESE, so the repository checked must be the one pushed to (M1). Empty = none set.
_fg_pushurls() {
  if [ "$SEAMS" -eq 1 ]; then printf '%s\n' "$DOCTOR_FORGE_PUSHURL"; else git remote get-url --push --all origin 2>/dev/null || true; fi
}
# the credential helper NAMES git is configured with (config, not a secret); a value outside a plain helper name is not shown.
_fg_helper() {
  # --get-urlmatch also sees a helper scoped to this host alone (credential.https://<host>.helper), which --get-all would miss
  if [ "$SEAMS" -eq 1 ]; then _fh_all=$DOCTOR_FORGE_HELPER; else _fh_all=$(git config --get-urlmatch credential.helper "https://$FG_HOST" 2>/dev/null || true); fi
  _fh_out=''
  while IFS= read -r _fh_l || [ -n "$_fh_l" ]; do
    [ -n "$_fh_l" ] || continue
    case "$_fh_l" in
      *[!A-Za-z0-9._/-]*) _fh_l='(set; not shown)' ;;
      */*) _fh_l=${_fh_l##*/}   # a path can carry a local username: print only the helper's own name
           [ -n "$_fh_l" ] || _fh_l='(set; not shown)' ;;
    esac
    [ "${#_fh_l}" -le 64 ] || _fh_l='(set; not shown)'
    _fh_out="$_fh_out${_fh_out:+, }$_fh_l"
  done <<_FG_HELPER_EOF
$_fh_all
_FG_HELPER_EOF
  if [ -n "$_fh_out" ]; then printf '%s' "$_fh_out"; else printf 'none set'; fi
}
# _fg_parse <origin-url>: sets FG_HOST (lowercased, gated), FG_OWNER, FG_REPO, FG_SSH. rc 1 when it is not a hosted remote.
_fg_parse() {
  FG_HOST=''; FG_OWNER=''; FG_REPO=''; FG_SSH=0; FG_HTTPS=0
  _fp_u=$1
  case "$_fp_u" in
    ''|-*|/*|.*) return 1 ;;
    *://*)
      case "$_fp_u" in ssh://*) FG_SSH=1 ;; http://*|https://*) FG_HTTPS=1 ;; esac
      _fp_r=${_fp_u#*://}
      _fp_auth=${_fp_r%%/*}
      _fp_path=${_fp_r#*/}
      [ "$_fp_path" != "$_fp_r" ] || return 1
      # the authority may carry userinfo, nothing else: a '#', '?', '\' or space here is how a URL parser and doctor disagree about the host
      case "$_fp_auth" in *[!A-Za-z0-9._~%:@-]*) return 1 ;; esac
      _fp_host=${_fp_auth##*@}
      _fp_host=${_fp_host%%:*}
      ;;
    *:*)
      FG_SSH=1
      _fp_host=${_fp_u%%:*}
      _fp_host=${_fp_host##*@}
      _fp_path=${_fp_u#*:}
      ;;
    *) return 1 ;;
  esac
  _fp_path=${_fp_path%/}
  _fp_path=${_fp_path%.git}
  _fp_owner=${_fp_path%%/*}
  _fp_repo=${_fp_path#*/}
  case "$_fp_host" in ''|*[!A-Za-z0-9.-]*) return 1 ;; esac
  case "$_fp_owner" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac
  case "$_fp_repo" in ''|*/*|*[!A-Za-z0-9._-]*) return 1 ;; esac
  [ "$_fp_owner" != "$_fp_path" ] || return 1
  case "$_fp_owner" in .|..) return 1 ;; esac
  case "$_fp_repo" in .|..) return 1 ;; esac
  FG_HOST=$(printf '%s' "$_fp_host" | tr '[:upper:]' '[:lower:]')
  FG_OWNER=$_fp_owner
  FG_REPO=$_fp_repo
  return 0
}
# _fg_gate <value> <charset-ok-pattern-name>: a byte doctor did not check is never printed (the Jira line's rule, S-6).
_fg_gate_login() {
  _gl_core=${1%'[bot]'}   # a GitHub App login ends in [bot]; the rest is [A-Za-z0-9-]
  case "$_gl_core" in ''|*[!A-Za-z0-9-]*) printf '?'; return 0 ;; esac
  if [ "${#1}" -le 64 ]; then printf '%s' "$1"; else printf '?'; fi
}
_fg_gate_type() {
  case "$1" in User|Bot|Organization|Mannequin) printf '%s' "$1" ;; *) printf '?' ;; esac
}
# _fg_identity: reads once. Sets FG_STATE:
#   ok          FG_LOGIN FG_TYPE FG_LEVEL (admin|maintain|push|triage|pull) FG_OWNER FG_REPO are set
#   noorigin    no origin remote                      nohost   origin is not on github.com (FG_HOST names it)
#   nogh        gh is not installed                   ci       gh api user answered 403 (CI's GITHUB_TOKEN cannot read its identity)
#   unauth      gh api user failed another way        unreadable  the login is known but its permission on the repo is not
_fg_identity() {
  FG_STATE=''; FG_LOGIN=''; FG_TYPE=''; FG_LEVEL=''; FG_HOST=''; FG_OWNER=''; FG_REPO=''; FG_SSH=0; FG_HTTPS=0
  _fi_url=$(_fg_origin)
  if [ -z "$_fi_url" ]; then FG_STATE=noorigin; return 0; fi
  if ! _fg_parse "$_fi_url"; then FG_STATE=nohost; FG_HOST='an unrecognised origin'; return 0; fi
  if [ "$FG_HOST" != github.com ]; then FG_STATE=nohost; return 0; fi
  # M1: git pushes to origin's PUSH url(s), which may name another repository than the fetch url the permission is read for.
  # Every push url must parse to the same host/owner/repo, or the check cannot say what a push would reach (no gh call is made).
  _fi_fh=$FG_HOST; _fi_fo=$FG_OWNER; _fi_fr=$FG_REPO; _fi_fs=$FG_SSH; _fi_fx=$FG_HTTPS
  _fi_pu=$(_fg_pushurls)
  while IFS= read -r _fi_l || [ -n "$_fi_l" ]; do
    [ -n "$_fi_l" ] || continue
    if ! _fg_parse "$_fi_l" || [ "$FG_HOST" != "$_fi_fh" ] || [ "$FG_OWNER" != "$_fi_fo" ] || [ "$FG_REPO" != "$_fi_fr" ]; then
      FG_STATE=pushdiff; FG_HOST=$_fi_fh; FG_OWNER=$_fi_fo; FG_REPO=$_fi_fr; FG_SSH=$_fi_fs; FG_HTTPS=$_fi_fx
      return 0
    fi
    [ "$FG_SSH" -eq 0 ] || _fi_fs=1
    [ "$FG_HTTPS" -eq 0 ] || _fi_fx=1
  done <<_FG_PUSH_EOF
$_fi_pu
_FG_PUSH_EOF
  FG_HOST=$_fi_fh; FG_OWNER=$_fi_fo; FG_REPO=$_fi_fr; FG_SSH=$_fi_fs; FG_HTTPS=$_fi_fx
  if [ "$SEAMS" -eq 0 ] && ! command -v gh >/dev/null 2>&1; then FG_STATE=nogh; return 0; fi
  # L5: a failed mktemp must not abort the default doctor (set -e): it is an unreadable identity, like any other read failure
  _fi_d=$(mktemp -d 2>/dev/null) || { FG_STATE=unauth; return 0; }
  _fi_rc=0; _fi_out=$(_fg_gh api user --jq '.login,.type' 2>"$_fi_d/err") || _fi_rc=$?
  if [ "$_fi_rc" -ne 0 ]; then
    if grep -q 'HTTP 403' "$_fi_d/err" 2>/dev/null; then FG_STATE=ci; else FG_STATE=unauth; fi
    rm -rf "$_fi_d"; return 0
  fi
  FG_LOGIN=$(_fg_gate_login "$(printf '%s\n' "$_fi_out" | sed -n '1p')")
  FG_TYPE=$(_fg_gate_type "$(printf '%s\n' "$_fi_out" | sed -n '2p')")
  _fi_rc=0; _fi_perm=$(_fg_gh api "repos/$FG_OWNER/$FG_REPO" --jq .permissions 2>/dev/null) || _fi_rc=$?
  rm -rf "$_fi_d"
  _fi_p=$(printf '%s' "$_fi_perm" | tr -d ' \n\r')
  FG_STATE=unreadable
  [ "$_fi_rc" -eq 0 ] || return 0
  # the keys the seat verified: admin, maintain, pull, push, triage. A response without admin AND push is unreadable (fail-closed).
  case "$_fi_p" in *'"admin":'*) ;; *) return 0 ;; esac
  case "$_fi_p" in *'"push":'*) ;; *) return 0 ;; esac
  FG_STATE=ok
  case "$_fi_p" in
    *'"admin":true'*) FG_LEVEL="admin" ;;
    *'"maintain":true'*) FG_LEVEL="maintain" ;;
    *'"push":true'*) FG_LEVEL="push" ;;
    *'"triage":true'*) FG_LEVEL="triage" ;;
    *) FG_LEVEL="pull" ;;
  esac
  return 0
}
# _fg_seat_declared: true when the project declares a ratification seat, i.e. .kit/ratification-seats.conf holds at least one SEAT=
# line (read with the grammar ratification.yml uses; the value is counted and NEVER printed). A project that declares a separate
# ratification identity has bought into identity separation, so an admin login undoes a declared control.
_fg_seat_declared() {
  [ -f "$DOCTOR_FORGE_SEATCONF" ] || return 1
  # a conf that exists but cannot be read is treated as declared: fail toward the warning
  [ -r "$DOCTOR_FORGE_SEATCONF" ] || return 0
  _fs_n=$(sed -n 's/^SEAT=//p' "$DOCTOR_FORGE_SEATCONF" 2>/dev/null | grep -c '' || true)
  [ "${_fs_n:-0}" -gt 0 ]
}
# _fg_line [agent]: the identity line for the current FG_STATE. Under --as agent (the explicit gate) an admin or maintain login
# always reads HOLDS ADMIN; in the default run it does so only where a ratification seat is declared, else it is an INFO line.
_fg_line() {
  case "$FG_STATE" in
    noorigin) printf 'forge identity: N/A — no origin remote\n' ;;
    nohost) printf 'forge identity: N/A — no forge adapter for %s\n' "$FG_HOST" ;;
    nogh) printf 'forge identity: N/A — gh is not installed\n' ;;
    ci) printf 'forge identity: N/A — this credential cannot read its own identity (HTTP 403, as under CI'"'"'s GITHUB_TOKEN)\n' ;;
    unauth) printf "forge identity: not readable — could not read the login (gh is unauthenticated or the forge is unreachable; run 'gh auth status')\n" ;;
    pushdiff) printf "forge identity: N/A — origin's push URL does not name the same repository as its fetch URL\n" ;;
    unreadable) printf 'forge identity: %s (%s) — permission on %s/%s unreadable\n' "$FG_LOGIN" "$FG_TYPE" "$FG_OWNER" "$FG_REPO" ;;
    ok)
      _fl_s="forge identity: $FG_LOGIN ($FG_TYPE) — $FG_LEVEL on $FG_OWNER/$FG_REPO"
      case "$FG_LEVEL" in
        admin|maintain)
          if [ "${1:-}" = agent ] || _fg_seat_declared; then
            _fl_s="$_fl_s — HOLDS ADMIN: agent sessions must run as the push-only machine user; run 'sparkwright doctor --as agent'"
          else
            _fl_s="$_fl_s — INFO: a push-only machine user for agent sessions is the recommended posture once a separate identity reviews; see docs/operations/forge-identity-switch.md"
          fi ;;
      esac
      printf '%s\n' "$_fl_s" ;;
  esac
}
# _fg_advisory: NAMES ONLY (never a value): which variables decide the credential gh uses, and whether git pushes by SSH.
_fg_advisory() {
  _fa_names=''
  for _fa_v in GH_TOKEN GITHUB_TOKEN GITHUB_PERSONAL_ACCESS_TOKEN; do
    eval "_fa_val=\${$_fa_v:-}"
    [ -z "$_fa_val" ] || _fa_names="$_fa_names${_fa_names:+, }$_fa_v"
  done
  [ -z "$_fa_names" ] || printf 'forge credential: %s set in the environment (it decides which credential gh uses; doctor does not read it)\n' "$_fa_names"
  [ "$FG_SSH" -ne 1 ] || printf 'forge credential: origin is SSH (git push uses the SSH key, not gh'"'"'s login; doctor cannot see whose key it is)\n'
  [ "$FG_HTTPS" -ne 1 ] || printf 'forge credential: git push over HTTPS uses git'"'"'s credential helper (%s); doctor does not verify its identity\n' "$(_fg_helper)"
}
# _fg_days <today> <expiry> (both YYYY-MM-DD): whole days from today to expiry; negative when past.
_fg_days() {
  awk -v a="$1" -v b="$2" '
    function d(s,   p, y, m, dd, era, yoe, doy, doe) {
      split(s, p, "-"); y = p[1] + 0; m = p[2] + 0; dd = p[3] + 0
      if (m <= 2) y--
      era = int(y / 400); yoe = y - era * 400
      doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + dd - 1
      doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
      return era * 146097 + doe
    }
    BEGIN { print d(b) - d(a) }'
}
# _fg_expiry: prints a warning line when the token-expiration response header (gh api -i user) shows <= 30 days left. Prints NOTHING
# when the header is absent (a token that does not expire, or an OAuth login) or unparseable: it never guesses an expiry.
_fg_expiry() {
  _fx_h=$(_fg_gh api -i user 2>/dev/null | tr -d '\r' | grep -i '^github-authentication-token-expiration:' | sed -n '1p') || _fx_h=''
  [ -n "$_fx_h" ] || return 0
  _fx_date=$(printf '%s\n' "$_fx_h" | sed 's/^[^:]*: *//' | cut -c1-10)
  case "$_fx_date" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;; *) return 0 ;; esac
  if [ "$SEAMS" -eq 1 ]; then _fx_today=$DOCTOR_FORGE_TODAY; else _fx_today=$(date -u +%Y-%m-%d); fi
  case "$_fx_today" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;; *) return 0 ;; esac
  _fx_n=$(_fg_days "$_fx_today" "$_fx_date")
  if [ "$_fx_n" -lt 0 ]; then
    printf 'token expiry: %s (expired) — WARN: renew the machine user'"'"'s token (docs/operations/forge-identity-switch.md step 1)\n' "$_fx_date"
  elif [ "$_fx_n" -le 30 ]; then
    printf 'token expiry: %s (%s days) — WARN: renew the machine user'"'"'s token before it lapses (docs/operations/forge-identity-switch.md step 1)\n' "$_fx_date" "$_fx_n"
  fi
}
# --as agent: the identity check ONLY. 1 admin/maintain/lacks push/unreadable/unauthenticated/gh missing (fail-closed); 0 push;
# 2 UNVERIFIED, never 1: no forge adapter for the host, no origin, a push URL naming another repository, or a token that cannot
# read its own identity (403: an App installation or CI token, whose permissions are on the App's settings page).
_fg_agent() {
  # M3: a --selftest-e2e run reads a stand-in, never the forge, so its output must not be mistakable for a verdict
  [ "$SEAMS" -eq 0 ] || echo "SELFTEST SEAMS ACTIVE — not a verdict"
  echo "sparkwright doctor --as agent"
  echo "-----------------------------"
  if ! _fg_enabled; then
    echo "agent identity: UNVERIFIED — no forge read in this run"
    return 2
  fi
  _fg_identity
  _fg_line agent
  _fg_advisory
  case "$FG_STATE" in
    noorigin) echo "agent identity: UNVERIFIED — there is no origin remote to name a forge adapter for"; return 2 ;;
    nohost) echo "agent identity: UNVERIFIED — the kit has no forge adapter for $FG_HOST; map the rule by role (docs/adoption/vc-hosts.md, docs/operations/separation-of-duties.md §Forge identity)"; return 2 ;;
    nogh) echo "agent identity: FAIL — gh is not installed, so the identity cannot be verified (fail-closed)"; return 1 ;;
    pushdiff) echo "agent identity: UNVERIFIED — origin's push URL differs from its fetch URL (a push could reach a different repository than the one checked); make them name the same repository"; return 2 ;;
    ci) echo "agent identity: UNVERIFIED — this credential cannot read its own identity (HTTP 403: an App installation or CI token); confirm on the App's settings that it holds no Administration permission"; return 2 ;;
    unauth) echo "agent identity: FAIL — could not read the login (gh is unauthenticated or the forge is unreachable; fail-closed)"; return 1 ;;
    unreadable) echo "agent identity: FAIL — the permission on $FG_OWNER/$FG_REPO is unreadable (fail-closed)"; return 1 ;;
  esac
  case "$FG_LEVEL" in
    admin) echo "agent identity: FAIL — $FG_LOGIN holds admin on $FG_OWNER/$FG_REPO; agent sessions must run as the push-only machine user (docs/operations/forge-identity-switch.md)"; return 1 ;;
    maintain) echo "agent identity: FAIL — $FG_LOGIN holds maintain on $FG_OWNER/$FG_REPO; agent sessions must run as the push-only machine user (docs/operations/forge-identity-switch.md)"; return 1 ;;
    push) ;;
    *) echo "agent identity: FAIL — $FG_LOGIN holds only $FG_LEVEL on $FG_OWNER/$FG_REPO, so a lane cannot push"; return 1 ;;
  esac
  _fg_expiry
  echo "agent identity: PASS — gh's login $FG_LOGIN holds push only on $FG_OWNER/$FG_REPO"
  return 0
}
if [ "$AS_SET" -eq 1 ]; then
  _fg_rc=0; _fg_agent || _fg_rc=$?
  exit "$_fg_rc"
fi

gate_fail=0
warns=0

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# permission-local-accretion — the going-forward advisory for the CI-UNREADABLE local permission
# surfaces (.claude/settings.local.json ∪ ~/.claude/settings.json). C3 shipped the CI lock over the
# TRACKED settings.json; this reads the untracked, per-machine files that a CI checkout structurally
# cannot see. Three informational sub-signals — an accretion COUNT (--full metric), a LOUD laundering
# class + a LOUD hook-tamper class (default-posture WARN) — computed ONCE here and rendered below.
# NON-GATING: nothing here ever touches gate_fail; the metric can never change doctor's exit code.
# PRIVACY (design §5): emits COUNTS and ENUMERATION target names / config key names only — NEVER the
# owner's local allow strings.
# ═══════════════════════════════════════════════════════════════════════════════════════════════════

# _normalize <raw> : set _NF (fam: bash|write|other) + _NN (normalized inner). Strip the Bash(/Write(
# wrapper and the trailing :* glob; squeeze whitespace runs to one space + trim; lowercase Write targets
# (APFS is case-insensitive). Mirrors the vet-corrected NORMALIZED TOKEN match shape (design §3 F1).
_normalize() {
  _ns=$1
  case "$_ns" in
    "Bash("*")")  _NF="bash";  _ns=${_ns#Bash(};  _ns=${_ns%)} ;;
    "Write("*")") _NF="write"; _ns=${_ns#Write(}; _ns=${_ns%)} ;;
    Bash)  _NF="bash";  _ns="" ;;
    Write) _NF="write"; _ns="" ;;
    *)     _NF="other" ;;
  esac
  _ns=${_ns%:\*}
  _ns=$(printf '%s' "$_ns" | awk '{$1=$1; print}')
  [ "$_NF" = write ] && _ns=$(printf '%s' "$_ns" | tr '[:upper:]' '[:lower:]')
  _NN=$_ns
}

# _in_sanctioned <norm> : rc0 iff <norm> equals a normalized allow/ask row of the enumeration. Iterated
# via a while-read here-doc (NOT $IFS re-split): here-doc bodies never pathname-expand, so the globs in
# $_sanct (e.g. "sh conformance/*") stay literal without relying on set -f, and no global IFS is touched.
_in_sanctioned() {
  while IFS= read -r _s || [ -n "$_s" ]; do
    [ -z "$_s" ] && continue
    [ "$_s" = "$1" ] && return 0
  done <<_ACC_SANCT_EOF
$_sanct
_ACC_SANCT_EOF
  return 1
}

# _has_sub <norm> <token-run> : rc0 iff <token-run> appears as a whole-token run in the space-normalized
# <norm> (ordered stem containment — "gh pr merge", "npm publish").
_has_sub() { case " $1 " in *" $2 "*) return 0 ;; esac; return 1; }

# _recforce <padded-tokens> : rc0 iff a recursive+force spelling is present (the closed set — design §3).
# NB uppercase -R is recursive on macOS/BSD rm (F-1): -Rf/-fR clustered + the -R+-f split, mirroring -r+-f.
_recforce() {
  case "$1" in *" -rf "*|*" -fr "*|*" -Rf "*|*" -fR "*) return 0 ;; esac
  case "$1" in *" --recursive "*) case "$1" in *" --force "*) return 0 ;; esac ;; esac
  case "$1" in *" -r "*|*" -R "*) case "$1" in *" -f "*) return 0 ;; esac ;; esac
  return 1
}

# _is_prefix <n> <t> : rc0 iff <n> is a token-prefix of <t> (empty <n> is a prefix of everything — the
# bare-Bash superset). Both are single-space normalized.
_is_prefix() {
  [ -z "$1" ] && return 0
  [ "$2" = "$1" ] && return 0
  case "$2" in "$1 "*) return 0 ;; esac
  return 1
}

# _env_target <lowercased-write-inner> : rc0 iff the Write target is .env / .env.* EXCEPT .env.example.
_env_target() {
  case "$1" in
    .env.example) return 1 ;;
    .env|.env.*|".env*") return 0 ;;
  esac
  return 1
}

# _tamper_add <reason> : append a tamper reason, de-duplicated.
_tamper_add() {
  case "
$_tamper" in
    *"
$1
"*) : ;;
    *) _tamper="$_tamper$1
" ;;
  esac
}

# _acc_analyze : populate ACC_STATUS (ok|na), ACC_NA_REASON, ACC_COUNT, ACC_LOUD (newline list of
# enumeration target names), ACC_TAMPER (newline list of reasons). FAIL-SAFE (design §3 F4): jq-absent,
# a missing enumeration, both files absent, or malformed JSON ALL render N/A-with-reason — NEVER a false
# OK (the `$(jq … || echo 0)` idiom is banned). Parser stderr is discarded, never emitted (F7).
ACC_STATUS=na; ACC_NA_REASON=""; ACC_COUNT=0; ACC_LOUD=""; ACC_TAMPER=""
_acc_analyze() {
  set -f
  ACC_STATUS=na; ACC_NA_REASON=""; ACC_COUNT=0; ACC_LOUD=""; ACC_TAMPER=""
  _JQ=$DOCTOR_ACCRETION_JQ; _TSV=$DOCTOR_ACCRETION_TSV
  _LOCAL=$DOCTOR_ACCRETION_LOCAL; _USER=$DOCTOR_ACCRETION_USER

  if ! command -v "$_JQ" >/dev/null 2>&1; then
    ACC_NA_REASON="jq not available — cannot parse the local permission surfaces"; set +f; return 0
  fi
  if [ ! -f "$_TSV" ]; then
    ACC_NA_REASON="the sanctioned enumeration (sanctioned-commands.tsv) is not present"; set +f; return 0
  fi

  _files=""
  [ -f "$_LOCAL" ] && _files="$_files$_LOCAL
"
  [ -f "$_USER" ] && _files="$_files$_USER
"
  if [ -z "$_files" ]; then
    ACC_NA_REASON="no local permission surface present (settings.local.json and ~/.claude/settings.json both absent)"
    set +f; return 0
  fi

  # FAIL-SAFE: a present-but-malformed file → N/A, never a false all-clear.
  while IFS= read -r _f || [ -n "$_f" ]; do
    [ -z "$_f" ] && continue
    if ! "$_JQ" empty "$_f" >/dev/null 2>&1; then
      ACC_NA_REASON="a local permission file is not valid JSON — refusing to render a possibly-false all-clear"
      set +f; return 0
    fi
  done <<_ACC_FILES_EOF
$_files
_ACC_FILES_EOF

  # enumeration → sanctioned set (allow/ask) + deny/deliberately-absent target records (fam|norm|enum).
  # Inline `IFS="$_TAB" read` command-prefix form (scoped to the read, no global IFS reassignment).
  _sanct=""; _deny_recs=""
  _TAB=$(printf '\t')
  while IFS="$_TAB" read -r _pat _disp _rest; do
    case "$_pat" in ''|'#'*) continue ;; esac
    _normalize "$_pat"
    case "$_disp" in
      allow|ask) _sanct="$_sanct$_NN
" ;;
      deny|deliberately-absent) _deny_recs="$_deny_recs$_NF|$_NN|$_pat
" ;;
    esac
  done < "$_TSV"

  # union of local allows across the present files.
  _allows=""
  while IFS= read -r _f || [ -n "$_f" ]; do
    [ -z "$_f" ] && continue
    _a=$("$_JQ" -r '.permissions.allow[]? // empty' "$_f" 2>/dev/null) || _a=""
    [ -n "$_a" ] && _allows="$_allows$_a
"
  done <<_ACC_FILES2_EOF
$_files
_ACC_FILES2_EOF

  # accretion count + laundering loud class. Nested while-read here-docs (NOT $IFS re-split): the outer
  # feeds the union of local allows, the inner the deny/deliberately-absent target records; both run in
  # the current shell so _count/_loud persist. Empty-line guards mirror the old `for`-loop field-skip.
  _count=0; _loud=""
  while IFS= read -r _al || [ -n "$_al" ]; do
    [ -z "$_al" ] && continue
    _normalize "$_al"; _fam=$_NF; _n=$_NN; _tok=" $_NN "
    _in_sanctioned "$_n" || _count=$((_count+1))
    [ "$_fam" = other ] && continue
    while IFS= read -r _rec || [ -n "$_rec" ]; do
      [ -z "$_rec" ] && continue
      _tfam=${_rec%%|*}; _r2=${_rec#*|}; _tnorm=${_r2%%|*}; _tenum=${_r2#*|}
      _fire=0
      if [ "$_tfam" = write ]; then
        [ "$_fam" = write ] && _env_target "$_n" && _fire=1
      elif [ "$_fam" = bash ]; then
        # kind-specific spelling-evasion containment
        case "$_tnorm" in
          *--admin*)
            if _has_sub "$_n" "gh pr merge"; then
              case "$_tok" in *" --admin "*|*" --admin="*) _fire=1 ;; esac
            fi ;;
          "rm "*|rm)
            case "$_tok" in " rm "*) _recforce "$_tok" && _fire=1 ;; esac ;;
          *)
            _has_sub "$_n" "$_tnorm" && _fire=1 ;;
        esac
        # generic unsanctioned-superset-prefix (catches Bash(gh:*), Bash(rm:*), bare Bash)
        if [ "$_fire" = 0 ] && _is_prefix "$_n" "$_tnorm"; then
          _in_sanctioned "$_n" || _fire=1
        fi
      fi
      if [ "$_fire" = 1 ]; then
        case "
$_loud" in
          *"
$_tenum
"*) : ;;
          *) _loud="$_loud$_tenum
" ;;
        esac
      fi
    done <<_ACC_DENY_EOF
$_deny_recs
_ACC_DENY_EOF
  done <<_ACC_ALLOWS_EOF
$_allows
_ACC_ALLOWS_EOF
  ACC_COUNT=$_count; ACC_LOUD=$_loud

  # hook-tamper / escalation loud class (design §3.3, vet Finding 6). Outer files loop + two sequential
  # inner key loops, all while-read here-docs (NOT $IFS re-split); _tamper persists in the current shell.
  _tamper=""
  while IFS= read -r _f || [ -n "$_f" ]; do
    [ -z "$_f" ] && continue
    _ek=$("$_JQ" -r '(.env // {}) | keys[]? // empty' "$_f" 2>/dev/null) || _ek=""
    # KIT_* (guard kill-switch dials) UNION the guard's own never-add loader/exec-env set (F-2 — a
    # settings-level env: {NODE_OPTIONS|LD_PRELOAD|…} is a code-injection channel surviving restarts).
    # Benign keys (an adopter's env: {MY_APP_URL:…}) stay QUIET — no wolf-crying. KEY NAME only, no value.
    while IFS= read -r _k || [ -n "$_k" ]; do
      [ -z "$_k" ] && continue
      case "$_k" in
        KIT_*) _tamper_add "env-block key $_k (persistent guard kill-switch)" ;;
        PATH|LD_PRELOAD|LD_LIBRARY_PATH|DYLD_INSERT_LIBRARIES|DYLD_LIBRARY_PATH|NODE_OPTIONS|BASH_ENV|ENV|PERL5OPT|PYTHONSTARTUP|RUBYOPT|GIT_SSH_COMMAND)
          _tamper_add "env-block key $_k (loader/exec-env injection channel)" ;;
      esac
    done <<_ACC_ENV_EOF
$_ek
_ACC_ENV_EOF
    _dm=$("$_JQ" -r '.permissions.defaultMode // empty' "$_f" 2>/dev/null) || _dm=""
    case "$_dm" in
      bypassPermissions|acceptEdits) _tamper_add "permissions.defaultMode=$_dm (neuters the ask tier)" ;;
    esac
    _hk=$("$_JQ" -r '(.hooks // {}) | keys[]? // empty' "$_f" 2>/dev/null) || _hk=""
    while IFS= read -r _k || [ -n "$_k" ]; do
      [ -z "$_k" ] && continue
      _tamper_add "hooks.$_k (local hook definition)"
    done <<_ACC_HOOK_EOF
$_hk
_ACC_HOOK_EOF
    _dah=$("$_JQ" -r 'if has("disableAllHooks") then (.disableAllHooks|tostring) else empty end' "$_f" 2>/dev/null) || _dah=""
    case "$_dah" in
      true|1) _tamper_add "disableAllHooks=$_dah (unwires all hooks)" ;;
    esac
  done <<_ACC_FILES3_EOF
$_files
_ACC_FILES3_EOF
  ACC_TAMPER=$_tamper

  ACC_STATUS=ok
  set +f
  return 0
}

_acc_analyze

# — HEADER ——————————————————————————————————————————————————————————————————
_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
_sha=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
_version=$(tr -d '[:space:]' < VERSION 2>/dev/null || echo "unknown")
_latest_tag=$(git tag --list 'v*' --sort=-version:refname 2>/dev/null | head -1 || echo "none")

echo "sparkwright doctor"
echo "------------------"
printf 'branch: %s  sha: %s  VERSION: %s  latest-tag: %s\n' \
  "$_branch" "$_sha" "$_version" "$_latest_tag"
echo ""

# — POSTURE ——————————————————————————————————————————————————————————————————
echo "POSTURE"
echo "-------"

# 1. conformance [GATING]
if [ -n "$DOCTOR_VERIFY_CMD" ]; then
  # overridden (selftest/test path) — invoke stub directly, no [ -f ] guard
  if _vout=$($DOCTOR_VERIFY_CMD 2>&1); then _vrc=0; else _vrc=$?; fi
  case "$_vrc" in
    0) _vstatus="PASS" ;;
    2) _vstatus="UNVERIFIED" ;;
    *) _vstatus="FAIL" ;;
  esac
  printf '  %-14s %s\n' "conformance" "$_vstatus"
  case "$_vstatus" in
    FAIL)       gate_fail=1 ;;
    UNVERIFIED) [ "$REQUIRE" = "1" ] && gate_fail=1 || true ;;
  esac
elif [ -f "conformance/verify.sh" ]; then
  _args=""
  [ "$REQUIRE" = "1" ] && _args="--require"
  echo "doctor: running the conformance battery (conformance/verify.sh); this can take several minutes on a kit tree..." >&2
  # shellcheck disable=SC2086
  if _vout=$(sh conformance/verify.sh $_args 2>&1); then _vrc=0; else _vrc=$?; fi
  case "$_vrc" in
    0) _vstatus="PASS" ;;
    2) _vstatus="UNVERIFIED" ;;
    *) _vstatus="FAIL" ;;
  esac
  printf '  %-14s %s\n' "conformance" "$_vstatus"
  case "$_vstatus" in
    FAIL)       gate_fail=1 ;;
    UNVERIFIED) [ "$REQUIRE" = "1" ] && gate_fail=1 || true ;;
  esac
else
  printf '  %-14s UNVERIFIED (not present)\n' "conformance"
  warns=$((warns+1))
  [ "$REQUIRE" = "1" ] && gate_fail=1 || true
fi

# 2. claims [GATING]
if [ -n "$DOCTOR_CLAIMS_CMD" ]; then
  # overridden (selftest/test path) — invoke stub directly, no [ -f ] guard
  if _cout=$($DOCTOR_CLAIMS_CMD 2>&1); then _crc=0; else _crc=$?; fi
  case "$_crc" in
    0) _cstatus="PASS" ;;
    *) _cstatus="FAIL" ;;
  esac
  printf '  %-14s %s\n' "claims" "$_cstatus"
  [ "$_cstatus" = "FAIL" ] && gate_fail=1 || true
elif [ ! -f "docs/ROADMAP-KIT.md" ] && [ ! -f ".github/workflows/golden-path.yml" ]; then
  # kit-self (SWAS-199): the registry grades the KIT's own headline claims. Neither kit marker (the same
  # pair verify.sh --kitself uses) means this is an exported/incepted adopter tree: the dimension stands
  # down, touching neither gate_fail nor warns, and runs nothing (so no stderr progress line either).
  printf '  %-14s N/A (kit-self: the registry grades the kit'"'"'s own headline claims; this is not the kit'"'"'s tree; this project'"'"'s own claims are not graded here)\n' "claims"
elif [ -f "conformance/claims-registry.sh" ]; then
  echo "doctor: checking the claims registry (conformance/claims-registry.sh)..." >&2
  if _cout=$(sh conformance/claims-registry.sh 2>&1); then _crc=0; else _crc=$?; fi
  case "$_crc" in
    0) _cstatus="PASS" ;;
    *) _cstatus="FAIL" ;;
  esac
  printf '  %-14s %s\n' "claims" "$_cstatus"
  [ "$_cstatus" = "FAIL" ] && gate_fail=1 || true
else
  printf '  %-14s UNVERIFIED (not present)\n' "claims"
  warns=$((warns+1))
  [ "$REQUIRE" = "1" ] && gate_fail=1 || true
fi

# 3. git [ADVISORY — WARN-only; never sets gate_fail]
_git_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
_git_dirty=$(git status --porcelain 2>/dev/null || true)
_git_tag_for_ver=$(git tag --list "v$_version" 2>/dev/null || true)

_git_warn=0
_git_notes=""

case "$_git_branch" in
  HEAD|detached)
    _git_notes="${_git_notes}WARN: detached HEAD; "
    _git_warn=1
    ;;
  *)
    _git_notes="${_git_notes}branch=${_git_branch}; "
    ;;
esac

if [ -n "$_git_dirty" ]; then
  _git_notes="${_git_notes}WARN: dirty working tree; "
  _git_warn=1
else
  _git_notes="${_git_notes}clean; "
fi

if [ -z "$_git_tag_for_ver" ]; then
  _git_notes="${_git_notes}WARN: v${_version} untagged/unreleased"
  _git_warn=1
else
  _git_notes="${_git_notes}tagged=v${_version}"
fi

if [ "$_git_warn" = "1" ]; then
  warns=$((warns+1))
  printf '  %-14s WARN  [%s]\n' "git" "$_git_notes"
else
  printf '  %-14s OK    [%s]\n' "git" "$_git_notes"
fi

# 4. kit-update [ADVISORY — WARN-only; never sets gate_fail]
# THE SURFACING (P1.2/T7). conformance/kit-current.sh answers one question — "is the kit you adopted
# behind the current release?" — and this is the moment the adopter is already looking.
#
# Its exit codes are DISTINCT on purpose, because the three not-BEHIND answers are NOT the same answer and
# collapsing them is how a check turns into a lie:
#   0 = CURRENT/AHEAD -> OK    (one quiet line; an up-to-date adopter is NEVER nagged)
#   1 = BEHIND        -> WARN  (the surfacing; advisory — it can never fail their build)
#   2 = UNVERIFIED    -> N/A   (offline / unreachable source: staleness UNKNOWN, and NOT assumed OK)
#   3 = N/A           -> N/A   (not an adopted tree — the kit's own repo; decided with NO network)
# N/A prints its REASON (the check's own first line). A silent skip would be indistinguishable from a
# check that quietly did nothing — which is the exact failure this dimension exists to kill.
if [ -n "$DOCTOR_KITCURRENT_CMD" ]; then
  if _kout=$($DOCTOR_KITCURRENT_CMD 2>&1); then _krc=0; else _krc=$?; fi
elif [ -f "conformance/kit-current.sh" ]; then
  if _kout=$(sh conformance/kit-current.sh 2>&1); then _krc=0; else _krc=$?; fi
else
  _kout="kit-current: N/A — conformance/kit-current.sh is not present in this tree."
  _krc=3
fi
# The check's own first line IS the note — doctor never re-states its verdict in its own words (that
# would be a second source of truth about staleness, free to drift from the check that computed it).
_knote=$(printf '%s\n' "$_kout" | sed -n '1p' | sed 's/^kit-current: *//')
#
# WHICH STATES RAISE A WARN, AND WHY THE SPLIT IS NOT PEDANTRY:
#   BEHIND (1)     -> WARN. A fact was ESTABLISHED. This is the one thing this dimension has earned the
#                    right to make noise about.
#   UNVERIFIED (2) -> N/A row + WARN. A check that COULD NOT RUN is an unknown, and doctor already treats
#                    every unknown that way. Silence here would let a permanently-unreachable source
#                    masquerade as "fine".
#   N/A (3)        -> N/A row, NO warn. It genuinely DOES NOT APPLY (the kit's own repo is not an adopter).
#                    Warning about an inapplicable check is exactly the wolf-crying this dimension is
#                    built to avoid — and it would leave the kit's own doctor permanently yellow.
case "$_krc" in
  1)
    warns=$((warns+1))
    printf '  %-14s WARN  [%s]\n' "kit-update" "$_knote"
    printf '  %-14s       -> see the delta before deciding: sh scripts/kit-update.sh --from <kit source>  (it REPORTS; it writes nothing)\n' ""
    ;;
  0) printf '  %-14s OK    [%s]\n' "kit-update" "$_knote" ;;
  2)
    warns=$((warns+1))
    printf '  %-14s N/A   [%s]\n' "kit-update" "$_knote"
    ;;
  *) printf '  %-14s N/A   [%s]\n' "kit-update" "$_knote" ;;
esac

# 5. permissions [ADVISORY — WARN-only; never sets gate_fail]
# The going-forward signal for the CI-unreadable LOCAL permission surfaces. The LOUD class — a local
# allow re-granting a deny/deliberately-absent capability (laundering), or a hook-tamper/escalation key —
# renders HERE in the default posture (a laundering line buried behind --full is a quiet signal; vet
# condition D). The routine accretion COUNT stays a --full metric below. Anti-wolf-crying: absent surface
# / jq-absent / malformed JSON → N/A-with-reason, NEVER a false OK. Non-gating: never sets gate_fail.
#
# RECORDED PRE-PUSH REJECTION (design Q5): the sibling pre-push carrier is REJECTED, on measured grounds —
# a pre-push line parses these two files on EVERY push (the hot path) and jq is NOT guaranteed present
# (the codebase already probes `command -v jq`); accretion is a slow hygiene concern whose natural cadence
# is the on-demand doctor run, which carries zero per-push tax. Recorded here per Q5, not dropped.
if [ "$ACC_STATUS" = "na" ]; then
  printf '  %-14s N/A   [%s]\n' "permissions" "$ACC_NA_REASON"
elif [ -n "$ACC_LOUD" ] || [ -n "$ACC_TAMPER" ]; then
  warns=$((warns+1))
  _pl=$(printf '%s' "$ACC_LOUD" | awk 'NF{a=a s $0; s=", "} END{print a}')
  _pt=$(printf '%s' "$ACC_TAMPER" | awk 'NF{a=a s $0; s="; "} END{print a}')
  printf '  %-14s WARN  [local permission surface — review the following]\n' "permissions"
  [ -n "$_pl" ] && printf '  %-14s       -> laundering (a local allow re-grants a denied/deliberately-absent capability): %s\n' "" "$_pl"
  [ -n "$_pt" ] && printf '  %-14s       -> hook-tampering / escalation key(s): %s\n' "" "$_pt"
  printf '  %-14s       -> NB deny-beats-allow: a local allow that merely DUPLICATES a tracked deny is likely engine-ineffective, but is a real intent canary; equivalent-spelling evasions and the tamper keys ARE live. Advisory only — this never blocks you.\n' ""
else
  printf '  %-14s OK    [no laundering or hook-tampering in the local permission surfaces]\n' "permissions"
fi

# 6. tracker credential [ADVISORY — one line, never a verdict, never sets gate_fail]
# SECRETS-INJECTION-AT-LAUNCH (SWAS-101, design D3): which source would the tracker adapter use? It asks the
# presence question first: the environment, or the attribute-only Keychain lookup (no -w), so a value is never
# printed. A tree with no .kit/tracker.conf prints nothing.
# TRACKER-CREDENTIAL-IDENTITY-MODEL (SWAS-117 D5): when a credential is present and the conf is Jira, doctor also asks the
# ADAPTER (which alone reads the secret) who the credential is, with two bounded reads (`whoami --short`, `perms <KEY> --short`:
# one attempt each, 5s connect, 10s max, so offline adds at most about 20s). The line then names the account, and a credential
# that holds an admin or delete permission raises ONE doctor warn (advisory, never gate_fail): lanes must not run as it.
# NOTE (S-L3): the identity read SENDS THE CREDENTIAL to the conf's base_url (the adapter authenticates its requests to that
# host), exactly as `board` and the reader do. Doctor never checks that host against anything else, so a conf whose base_url an
# attacker changed would receive the credential on a real run; the pin comparison (S-2) is the reader's control, not doctor's.
# Honest about the Keychain: the read happens, so the source text says `(read for the identity check)`.
# _dt_id_gate / _dt_name_gate: the account id [A-Za-z0-9:_-]{1,128} and display name [A-Za-z0-9 ._'-]{1,64} are re-gated
# here (S-6: doctor never trusts a byte it did not check); anything else is `?`. The email is never read.
_dt_id_gate() {
  _dt_set='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789:_-'
  case "$1" in
    ''|*[!$_dt_set]*) printf '?'; return 0 ;;
  esac
  if [ "${#1}" -le 128 ]; then printf '%s' "$1"; else printf '?'; fi
}
_dt_name_gate() {
  _dt_nset="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 ._'-"
  case "$1" in
    ''|*[!$_dt_nset]*) printf '? (outside the printable set)'; return 0 ;;
  esac
  if [ "${#1}" -le 64 ]; then printf '%s' "$1"; else printf '? (outside the printable set)'; fi
}
# _dt_adapter <args…>: the adapter, or the --selftest-e2e seam standing in for `sh scripts/tracker-jira.sh` (the seam is
# word-split on purpose, like the other DOCTOR_*_CMD seams, so a stub is `sh <file>`).
_dt_adapter() {
  if [ -n "$DOCTOR_TRACKER_WHOAMI_CMD" ]; then
    # shellcheck disable=SC2086  # deliberate word-split of the seam command
    $DOCTOR_TRACKER_WHOAMI_CMD "$@"
  else
    sh scripts/tracker-jira.sh "$@"
  fi
}
# _dt_held <perms-output>: the comma-joined admin or delete keys the credential holds (ADMINISTER, SYSTEM_ADMIN,
# ADMINISTER_PROJECTS, DELETE_ISSUES), in that order; empty when none.
_dt_held() {
  _dh_out=''
  for _dh_k in ADMINISTER SYSTEM_ADMIN ADMINISTER_PROJECTS DELETE_ISSUES; do
    if printf '%s\n' "$1" | awk -F'\t' -v k="$_dh_k" '$1 == k && $2 == "yes" { f = 1 } END { exit !f }'; then
      _dh_out="$_dh_out${_dh_out:+, }$_dh_k"
    fi
  done
  printf '%s' "$_dh_out"
}
# _dt_unread <perms-output>: prints a word when any of ADMINISTER, SYSTEM_ADMIN, DELETE_ISSUES is not answered yes or no.
_dt_unread() {
  for _du_k in ADMINISTER SYSTEM_ADMIN DELETE_ISSUES; do
    if ! printf '%s\n' "$1" | awk -F'\t' -v k="$_du_k" '$1 == k && ($2 == "yes" || $2 == "no") { f = 1 } END { exit !f }'; then
      printf 'unread'; return 0
    fi
  done
}
if [ -n "$DOCTOR_TRACKER_CONF" ] && [ -f "$DOCTOR_TRACKER_CONF" ] && [ -f scripts/tracker-cred.sh ] && [ -f scripts/tracker-conf.sh ]; then
  . ./scripts/tracker-cred.sh
  tracker_cred_bind_root "$PWD"  # SWAS-196: doctor has already changed to its root (line 40); that root governs as.agent
  [ -z "$DOCTOR_SECURITY_BIN" ] || _TCR_SEC_BIN="$DOCTOR_SECURITY_BIN"
  _tcl_base=$(sh scripts/tracker-conf.sh get base_url "$DOCTOR_TRACKER_CONF" 2>/dev/null || true)
  _tcl_suffix=""
  if tracker_cred_available "$_tcl_base"; then
    _tcl_src=$TRACKER_CRED_SOURCE
    # does this run ask who the credential is? A real run does (when the adapter is present and the backend is jira); under
    # --selftest-e2e only when the seam names a stand-in, so every older leg stays hermetic and its text unchanged.
    _tcl_read=0
    if [ "$(sh scripts/tracker-conf.sh get backend "$DOCTOR_TRACKER_CONF" 2>/dev/null || true)" = jira ]; then
      if [ "$SEAMS" -eq 1 ]; then
        [ -z "$DOCTOR_TRACKER_WHOAMI_CMD" ] || _tcl_read=1
      elif [ -f scripts/tracker-jira.sh ]; then
        _tcl_read=1
      fi
    fi
    case "$_tcl_src" in
      env) _tcl_text="env" ;;
      *) if [ "$_tcl_read" -eq 1 ]; then _tcl_text="keychain (read for the identity check)"; else _tcl_text="keychain (item present; not read)"; fi ;;
    esac
    if [ "$_tcl_read" -eq 1 ]; then
      _tcl_flav=$(sh scripts/tracker-conf.sh get flavour "$DOCTOR_TRACKER_CONF" 2>/dev/null || echo cloud)
      [ -n "$_tcl_flav" ] || _tcl_flav=cloud
      _tcl_proj=$(sh scripts/tracker-conf.sh get project "$DOCTOR_TRACKER_CONF" 2>/dev/null || true)
      _tcl_rc=0; _tcl_who=$(_dt_adapter contract-read "$_tcl_base" "$_tcl_flav" whoami --short 2>/dev/null) || _tcl_rc=$?
      if [ "$_tcl_rc" -eq 0 ]; then
        _tcl_id=$(_dt_id_gate "$(printf '%s\n' "$_tcl_who" | awk -F'\t' '$1 == "account-id" { print $2; exit }')")
        _tcl_nm=$(_dt_name_gate "$(printf '%s\n' "$_tcl_who" | awk -F'\t' '$1 == "display-name" { print $2; exit }')")
        _tcl_suffix=" - runs as $_tcl_nm ($_tcl_id)"
        _tcl_pm=''; _tcl_prc=0
        _tcl_pm=$(_dt_adapter contract-read "$_tcl_base" "$_tcl_flav" perms "$_tcl_proj" --short 2>/dev/null) || _tcl_prc=$?
        if [ "$_tcl_prc" -eq 0 ]; then
          _tcl_held=$(_dt_held "$_tcl_pm")
          if [ -n "$_tcl_held" ]; then
            warns=$((warns+1))
            _tcl_suffix="$_tcl_suffix - HOLDS $_tcl_held: lanes must run as a non-admin agent account, run --preflight --as agent"
          elif [ -n "$(_dt_unread "$_tcl_pm")" ]; then
            # S-L1: nothing held, but one of the admin keys was not answered (the site rejected the extended key set): say so
            # instead of implying a clean bill
            _tcl_suffix="$_tcl_suffix - admin keys unreadable"
          fi
        fi
      elif [ "$_tcl_rc" -eq 6 ]; then
        _tcl_suffix=" - Jira did not accept it"
      elif [ "$_tcl_rc" -eq 1 ] && [ "$_tcl_src" = keychain ]; then
        # the adapter refused BEFORE any request (rc 1) and the credential came from the Keychain: the read failed or timed
        # out. An item made in Keychain Access.app prompts on every read (JIRA-SETUP-TEMPLATE §5b), so say so.
        _tcl_suffix=" - not read (the Keychain did not answer; an item made in Keychain Access.app prompts on every read, JIRA-SETUP-TEMPLATE §5b)"
      elif [ "$_tcl_rc" -eq 1 ]; then
        # a refusal that is not the Keychain's (a bad flavour or base url, a missing jq): neither "Keychain" nor "not reachable"
        _tcl_suffix=" - the adapter refused (configuration)"
      else
        _tcl_suffix=" - not reachable"
      fi
    fi
  else
    case "$TRACKER_CRED_SOURCE" in
      keychain) _tcl_text="keychain: $TRACKER_CRED_WHY" ;;
      env) _tcl_text="env: $TRACKER_CRED_WHY" ;;
      *)
        case "$TRACKER_CRED_WHY" in
          ''|"no token stored for "*) _tcl_text="none - store a token once: JIRA-SETUP-TEMPLATE §5b" ;;
          *) _tcl_text="none: $TRACKER_CRED_WHY" ;;
        esac ;;
    esac
  fi
  printf 'tracker credential: %s%s\n' "$_tcl_text" "$_tcl_suffix"
fi

# 7. forge identity [ADVISORY — one line, never a verdict, never sets gate_fail] (SWAS-124)
# Who this session is on the forge and what it holds on origin's repo (the functions above). A login that holds admin or maintain
# raises ONE doctor warn (Overall: WARN) only where a ratification seat is declared (.kit/ratification-seats.conf holds a SEAT=
# line); on a one-account tree the line is INFO and adds no warn. It is never a verdict and never changes the exit code;
# `sparkwright doctor --as agent` is the gate. Under CI's GITHUB_TOKEN the identity read is 403: N/A, not a warn. The names-only
# advisory is skipped on every N/A state (CI always sets GITHUB_TOKEN; advising there would be wolf-crying). Under --selftest-e2e
# it is silent unless the seam names a stand-in, and then also prints whether it counted a warn (the Overall line cannot say,
# because the git dimension warns on a dirty tree).
if _fg_enabled; then
  _fg_identity
  _fg_line
  case "$FG_STATE" in
    ok|unreadable|unauth) _fg_advisory ;;
  esac
  _fg_w=0
  if [ "$FG_STATE" = ok ]; then
    case "$FG_LEVEL" in
      admin|maintain) ! _fg_seat_declared || _fg_w=1 ;;
    esac
  fi
  warns=$((warns+_fg_w))
  [ "$SEAMS" -eq 0 ] || echo "SELFTEST forge warn counted: $_fg_w"
fi

# — VERDICT ——————————————————————————————————————————————————————————————————
echo ""
if [ "$gate_fail" = "1" ]; then
  echo "Overall: FAIL  (a gating dimension failed — fix conformance/claims before shipping)"
elif [ "$warns" != "0" ]; then
  echo "Overall: WARN  (review above — gating dimension(s) unverified or git advisory warnings present)"
else
  echo "Overall: PASS"
fi

# — FOOTER (honest ceiling) ——————————————————————————————————————————————————
echo ""
echo "Note: doctor automates the mechanizable drift axes (D claim-integrity, E git ground-truth"
echo "from docs/operations/drift-self-check.md) but does NOT detect semantic drift (intent,"
echo "scope, or overclaim) — that remains an agent/human judgment check."

# — METRICS (informational — does not affect exit) ————————————————————————————
if [ "$FULL" = "1" ]; then
  echo ""
  echo "METRICS (informational — does not affect exit)"
  echo "-----------------------------------------------"

  # dora
  if [ -n "$DOCTOR_DORA_CMD" ]; then
    # overridden (test path) — run directly, discard rc
    _dora_out=$($DOCTOR_DORA_CMD 2>&1) || true
    printf '%s\n' "$_dora_out"
  elif [ -f "scripts/dora.sh" ]; then
    _dora_out=$(sh scripts/dora.sh 2>&1) || true
    printf '%s\n' "$_dora_out"
  else
    echo "  dora:           N/A (not present)"
  fi

  # agent-scorecard
  if [ -n "$DOCTOR_SCORECARD_CMD" ]; then
    # overridden (test path) — run directly, discard rc
    _sc_out=$($DOCTOR_SCORECARD_CMD 2>&1) || true
    printf '%s\n' "$_sc_out"
  elif [ -f "scripts/agent-scorecard.sh" ]; then
    _sc_out=$(sh scripts/agent-scorecard.sh 2>&1) || true
    printf '%s\n' "$_sc_out"
  else
    echo "  agent-scorecard: N/A (not present)"
  fi

  # non-vacuity (advisory surfacing of the mutation-testing backstop; NEVER gates doctor).
  # Variable-indirected like the other metrics so the selftest stubs it (the real live sweep is
  # slow — it belongs in weekly drift-watch, not in every doctor --full / per-PR selftest run).
  if [ -n "$DOCTOR_NONVACUITY_CMD" ]; then
    _nv_out=$($DOCTOR_NONVACUITY_CMD 2>&1) || true
    printf '%s\n' "$_nv_out" | tail -1
  elif [ -f "conformance/non-vacuity.sh" ]; then
    echo "doctor: running the non-vacuity sweep (conformance/non-vacuity.sh); this can take several minutes..." >&2
    _nv_out=$(sh conformance/non-vacuity.sh 2>&1) || true
    printf '%s\n' "$_nv_out" | tail -1
  else
    echo "  non-vacuity: N/A (not present)"
  fi

  # permission-local-accretion (C3 going-forward signal; COUNT ONLY — never the list, §5 privacy).
  # Reuses the union analysis computed once above; the LOUD laundering/tamper class renders in the
  # default POSTURE section, not here. Informational — never affects exit.
  if [ "$ACC_STATUS" = "na" ]; then
    printf '  permission-local-accretion: N/A (%s)\n' "$ACC_NA_REASON"
  else
    printf '  permission-local-accretion: %s local allow(s) outside the sanctioned enumeration\n' "$ACC_COUNT"
  fi

  # meta-control freshness (M2 — advisory surfacing of the cadence circuit-breaker; NEVER gates doctor)
  if [ -n "$DOCTOR_META_CONTROL_CMD" ]; then
    _mc_out=$($DOCTOR_META_CONTROL_CMD 2>&1) || true
    printf '%s\n' "$_mc_out"
  elif [ -f "conformance/meta-control-fresh.sh" ]; then
    _mc_out=$(sh conformance/meta-control-fresh.sh 2>&1) || true
    printf '%s\n' "$_mc_out"
  else
    echo "  meta-control-fresh: N/A (not present)"
  fi
fi

[ "$gate_fail" = "1" ] && exit 1 || exit 0
