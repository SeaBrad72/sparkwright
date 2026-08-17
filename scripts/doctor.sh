#!/bin/sh
# doctor.sh — adopter-facing POSTURE report. Composes existing conformance checks into one
# "am I conformant + have I drifted?" summary. Automates the *mechanizable* half of
# docs/operations/drift-self-check.md (axes D claim-integrity + E git ground-truth).
#
# Four posture dimensions:
#   conformance [GATING]   — sh conformance/verify.sh
#   claims      [GATING]   — sh conformance/claims-registry.sh
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
# Usage: sh scripts/doctor.sh [--require] | --selftest
# POSIX sh; dash-clean.
# What it changes: Read-only — composes conformance + claims checks into a posture report; mutates nothing.
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

  [ "$sfail" -eq 0 ] && { echo "doctor --selftest: OK"; exit 0; } || exit 1
fi

REQUIRE=0
FULL=0
SEAMS=0
[ -n "${CI:-}" ] && REQUIRE=1
for _arg in "$@"; do
  case "$_arg" in
    --require) REQUIRE=1 ;;
    --full)    FULL=1    ;;
    # --selftest-e2e: INTERNAL. Turns the DOCTOR_*_CMD injection seams live so `--selftest`'s battery can
    # feed pass/fail fixtures through the REAL body. Deliberately absent from any usage line: the flag IS
    # the authorization. Mirrors preflight.sh's --selftest-e2e / PREFLIGHT_GIT_VERSION_CMD gating.
    --selftest-e2e) SEAMS=1 ;;
  esac
done

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
elif [ -f "conformance/claims-registry.sh" ]; then
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
