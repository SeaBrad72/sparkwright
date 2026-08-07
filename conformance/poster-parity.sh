#!/bin/sh
# poster-parity.sh — B5: every check-run POSTER the kit ships has the one safe shape, asserted as
# PROPERTIES over comment-stripped source — NEVER byte equality (the seven posters differ by design).
#
# THE DEFECT CLASS (CHECKRUN-POSTER-PARITY): a fix landed in one poster and never reached the others —
# three measured drifts (F2 name collision, F6 unpaginated lookup, F7 silent same-repo post failure) —
# and no existing lock asserted ANY of the shape properties (S7: grep check_name|HEAD_REPO over all
# three parity locks: zero hits), so every lock was green while the ci.yml backlog-presence poster
# failed all six. This lock closes the CLASS: one property set, all seven posters.
#
# THE SEVEN POSTERS (the registry below). Registry completeness is FAIL-CLOSED, repo-wide: a
# discovery leg scans EVERY .github/workflows/*.yml and profiles/*.yml (comment-stripped) for any
# check-run posting name-field shape (-f/-F/--field/--raw-field name=, single/double-quoted, bare,
# or variable) and REDs any occurrence that does not resolve to a registered <file, name> pair —
# an unparseable name (e.g. -f name="$VAR") is itself a RED naming file:line, never a skip — so a
# new poster cannot ship uncovered in those trees. reg_names REDs the other direction (a
# REGISTERED poster whose posting call vanished):
#   P1 .github/workflows/ci.yml            backlog-presence
#   P2 .github/workflows/ci.yml            ceremony-binding
#   P3 .github/workflows/ratification.yml  control-plane-ratification
#   P4 profiles/ratification.yml           control-plane-ratification
#   P5-P7 profiles/adopter-gates.yml       backlog-presence · ceremony-binding · loop-state
#
# THE PROPERTIES (each tagged, each with a survivor-shaped selftest negative):
#   [P-lookup]              server-side `?check_name=` lookup — never a client-side select over an
#                           unpaginated list (measured: 45 runs on a head, page of 30 -> a re-run
#                           strands the previous run in_progress forever and POSTs a duplicate)
#   [P-patch-or-post]       PATCH the prior run when found, POST otherwise (no spinner litter)
#   [P-conclusion-omission] the WAITING render OMITS the conclusion field — `-f conclusion=""`
#                           COMPLETES the check-run, which renders RED (the CP-9 cry-wolf)
#   [P-discriminator]       a same-repo post failure fails the job LOUD (`exit 1`); fork PRs stay
#                           logged-and-tolerated (read-only token; the absent context still blocks)
#   [P-name-collision]      the posted context name is never a JOB KEY in the same file (two
#                           same-named runs land on one sha; B5a measured WORST-WINS, but the
#                           collision makes posters fail nondeterministically — probe #500, 3x)
#   [P-mapping]             rc routes through agent-boundary.sh --conclusion (single-sourced,
#                           selftest-able) — no inline rc->conclusion literal (success/failure/
#                           action_required; `neutral` is loop-state's owner-ruled observe dial)
#   [P-external-id]         the poster stamps external_id="sparkwright-poster:<context>" and the
#                           lookup filters to its OWN prior run by it — identity, not just
#                           pagination: a same-named JOB auto-run is Actions-stamped and PATCHing
#                           it 403s (GitHub Feb-2025 rule; measured 3x on probe #500)
#
# SCOPE GUARD: the name!=job-key property applies ONLY to POSTED names (derived from `-f name=`).
# Never point it at the job-key-supplied contexts (loop-state, conformance, bootstrap, docs-links,
# the three obligations in ci.yml) — those are supplied BY job auto-runs with no poster, and their
# job key EQUALLING the context is how they work (design S6).
#
# HONEST CEILING: this proves SHAPE against comment-stripped source, not runtime conduct — the
# runtime evidence is the probe's, point-in-time. external_id semantics are GitHub's contract; a
# future API change lands on [P-discriminator]'s fail-loud path, not fail-open.
#
#   usage: sh conformance/poster-parity.sh [--selftest]   (run from repo root)
#   exit:  0 = all seven posters carry every property (or N/A on an adopter tree) · 1 = drift · 2 = usage
set -eu
cd "$(dirname "$0")/.."

# The registry: <file> <posted-context>, one poster per line. Registered order P1..P7.
REGISTRY=".github/workflows/ci.yml backlog-presence
.github/workflows/ci.yml ceremony-binding
.github/workflows/ratification.yml control-plane-ratification
profiles/ratification.yml control-plane-ratification
profiles/adopter-gates.yml backlog-presence
profiles/adopter-gates.yml ceremony-binding
profiles/adopter-gates.yml loop-state"

# is_adopter_tree: 0 (true) iff NOT the kit's own tree. Same TWO export-ignored kit-dev markers
# ratification-parity.sh / adopter-gates-parity.sh use. This lock audits the KIT's OWN reference
# posters; wired into verify.sh it must N/A on any adopter tree (exit 0, NEVER 2).
is_adopter_tree() {
  [ ! -f docs/ROADMAP-KIT.md ] && [ ! -f .github/workflows/golden-path.yml ]
}

# code_join <file>: comment-stripped source with backslash-continued lines JOINED, so a multi-line
# `gh api` call greps as ONE logical line. Every property reads THIS, never raw file text — these
# workflows discuss the wrong shapes at length in comments (same rule proportional-gate-wired.sh's
# code_only records: a lock must not constrain what the documentation is allowed to say).
code_join() {
  grep -v '^[[:space:]]*#' "$1" | awk '
    /\\$/ { sub(/\\$/, ""); buf = buf $0 " "; next }
    { print buf $0; buf = "" }
    END { if (buf != "") print buf }'
}

# poster_step <file> <context>: the poster STEP region from code_join output — from the step's own
# `- name:` line to the next step / next 2-indent job key / EOF. Located by the `?check_name=<ctx>`
# lookup; falls back to the first `-f name='<ctx>'` posting call so a poster with NO lookup (the
# pristine-P1 shape) still yields a region for the other properties to name honestly.
poster_step() {
  code_join "$1" | awk -v ctx="$2" '
    { lines[NR] = $0
      if (!hit && index($0, "/check-runs?check_name=" ctx "\"")) hit = NR
      if (!fb  && index($0, "-f name=" q ctx q)) fb = NR
    }
    BEGIN { q = sprintf("%c", 39) }   # a single-quote, without quoting gymnastics
    END {
      if (!hit) hit = fb
      if (!hit) exit 0
      start = 1
      for (i = hit; i >= 1; i--) if (lines[i] ~ /^[[:space:]]+- name:/) { start = i; break }
      end = NR
      for (i = hit + 1; i <= NR; i++)
        if (lines[i] ~ /^[[:space:]]+- (name|uses):/ || lines[i] ~ /^  [A-Za-z0-9_-]+:[[:space:]]*$/) { end = i - 1; break }
      for (i = start; i <= end; i++) print lines[i]
    }'
}

# check_poster <file> <context> -> rc0 iff the poster carries every property; every miss is a tagged
# FAIL line. Targets by ARGUMENT so the selftest drives it against fixtures (control-plane oracle:
# never env-redirectable).
check_poster() {
  _f="$1"; _ctx="$2"; _p=0
  [ -f "$_f" ] || { echo "FAIL [P-lookup] $_f poster '$_ctx': file missing — no poster to verify"; return 1; }
  _step=$(poster_step "$_f" "$_ctx")
  if [ -z "$_step" ]; then
    echo "FAIL [P-lookup] $_f poster '$_ctx': no poster step found (no ?check_name= lookup and no -f name='$_ctx' posting call)"
    return 1
  fi

  # [P-lookup] server-side ?check_name= filter present; the client-side select-over-a-page form gone.
  printf '%s\n' "$_step" | grep -qF "/check-runs?check_name=${_ctx}\"" || {
    echo "FAIL [P-lookup] $_f poster '$_ctx': the prior-run lookup is not a server-side ?check_name= filter — an unpaginated list hides the match after ~30 runs, stranding the previous run in_progress and POSTing a duplicate"; _p=1; }
  printf '%s\n' "$_step" | grep -qF 'select(.name==' && {
    echo "FAIL [P-lookup] $_f poster '$_ctx': the lookup still selects client-side on .name over a paged list — the exact F6 form the server-side filter replaces"; _p=1; }

  # [P-patch-or-post]
  { printf '%s\n' "$_step" | grep -qF 'method=PATCH' && printf '%s\n' "$_step" | grep -qF 'method=POST'; } || {
    echo "FAIL [P-patch-or-post] $_f poster '$_ctx': no PATCH-or-POST branch (method=PATCH + method=POST) — every re-run POSTs a fresh check-run and strands the previous one at in_progress forever"; _p=1; }

  # [P-conclusion-omission] among the posting calls (gh api -X ... -f name='ctx'), at least one
  # carries -f conclusion= and at least one OMITS it (the waiting render).
  _posts=$(printf '%s\n' "$_step" | grep -F 'gh api -X' | grep -F -- "-f name='${_ctx}'" || true)
  _total=$(printf '%s\n' "$_posts" | grep -c 'gh api -X' || true)
  _with=$(printf '%s\n' "$_posts" | grep -cF -- '-f conclusion=' || true)
  if [ "$_total" -lt 2 ] || [ "$_with" -lt 1 ] || [ "$_with" -ge "$_total" ]; then
    echo "FAIL [P-conclusion-omission] $_f poster '$_ctx': the poster does not have BOTH a with-conclusion call and a conclusion-OMITTING call (found $_total posting call(s), $_with with a conclusion) — a waiting render that sends any conclusion (even \"\") COMPLETES the check-run, which renders RED"; _p=1
  fi

  # [P-discriminator] same-repo post failure is LOUD: the HEAD_REPO/THIS_REPO comparison followed by
  # exit 1 within its block.
  printf '%s\n' "$_step" | awk '
    /\[ "\$HEAD_REPO" = "\$THIS_REPO" \]/ { cmp = NR }
    /exit 1/ && cmp && NR > cmp && NR <= cmp + 6 { ok = 1 }
    END { exit ok ? 0 : 1 }' || {
    echo "FAIL [P-discriminator] $_f poster '$_ctx': no same-repo post-failure discriminator failing loud ([ \"\$HEAD_REPO\" = \"\$THIS_REPO\" ] ... exit 1) — a same-repo post/PATCH failure would leave a stale or absent verdict standing with only a log line nobody reads (F7)"; _p=1; }

  # [P-name-collision] the posted context must not be a JOB KEY in the same file. POSTED names only —
  # job-key-supplied contexts are out of this property's domain by construction (S6).
  grep -v '^[[:space:]]*#' "$_f" | grep -qE "^  ${_ctx}:[[:space:]]*$" && {
    echo "FAIL [P-name-collision] $_f poster '$_ctx': a JOB is keyed '${_ctx}' in the same file that posts a check-run of that name — two same-named runs land on one sha and posters fail nondeterministically (probe #500). Rename the job (gate-* convention); the required CONTEXT keeps the posted name"; _p=1; }

  # [P-mapping] rc routes through the shared mapping; no inline rc->conclusion literal. `neutral`
  # is exempt: loop-state's observe dial posts it by owner ruling (B6-D1), not from an rc case.
  # Domain: LITERAL assignments only — indirection (concl="$VAR" with the literal one hop away) is
  # outside this leg's reach; the shape-not-conduct ceiling in the header applies.
  printf '%s\n' "$_step" | grep -qF 'agent-boundary.sh --conclusion "$rc"' || {
    echo "FAIL [P-mapping] $_f poster '$_ctx': rc is not routed through agent-boundary.sh --conclusion — the rc->(status,conclusion) mapping must stay single-sourced and selftest-able, not inline YAML"; _p=1; }
  printf '%s\n' "$_step" | grep -qE "(concl|conclusion)=[\"']?(success|failure|action_required)" && {
    echo "FAIL [P-mapping] $_f poster '$_ctx': an inline conclusion literal (success/failure/action_required) bypasses the shared mapping — the hardcoded action_required class rendered a healthy WAITING gate as a red build failure"; _p=1; }

  # [P-external-id] stamped on the posting calls, filtered on the lookup.
  printf '%s\n' "$_step" | grep -qF -- "-f external_id=\"sparkwright-poster:${_ctx}\"" || {
    echo "FAIL [P-external-id] $_f poster '$_ctx': the poster does not stamp external_id=\"sparkwright-poster:${_ctx}\" — without an identity stamp its runs are indistinguishable from a same-named job auto-run or another workflow's poster"; _p=1; }
  printf '%s\n' "$_step" | grep -qF "select(.external_id==\"sparkwright-poster:${_ctx}\")" || {
    echo "FAIL [P-external-id] $_f poster '$_ctx': the lookup does not filter to the poster's OWN prior run by external_id — PATCHing a same-named Actions job auto-run 403s (Feb-2025 rule, measured 3x on probe #500), and PATCHing another poster's run cross-patches workflows"; _p=1; }

  return "$_p"
}

# discover [root] -> rc0 iff every check-run posting name-field occurrence under <root> (default .)
# resolves to a registered <file, name> pair. The repo-wide FAIL-CLOSED net (F1/I-1): scans every
# .github/workflows/*.yml AND profiles/*.yml — comment lines skipped, PHYSICAL line numbers kept so
# a verdict can name file:line — for any name-field shape on a posting call (-f / -F / --field /
# --raw-field name=..., single-quoted, double-quoted, or bare). An occurrence that does not resolve
# is a RED naming file:line, never a skip; an UNPARSEABLE name (a variable like -f name="$VAR", a
# mismatched quote, an empty value) REDs the same way — fail-closed, because a name the lock cannot
# read is a poster the registry cannot cover. Takes its scan root by ARGUMENT so the selftest
# drives it against fixture trees (same rule as check_poster).
discover() {
  _root="${1:-.}"; _drc=0
  for _df in "$_root"/.github/workflows/*.yml "$_root"/profiles/*.yml; do
    [ -f "$_df" ] || continue
    _rel="${_df#"$_root"/}"
    # lineno<TAB>token for every name-field occurrence on a non-comment physical line
    _hits=$(awk '
      /^[[:space:]]*#/ { next }
      {
        line = $0
        while (match(line, /(-f|-F|--field|--raw-field) name=[^[:space:]]*/)) {
          print NR "\t" substr(line, RSTART, RLENGTH)
          line = substr(line, RSTART + RLENGTH)
        }
      }' "$_df")
    [ -n "$_hits" ] || continue
    while IFS='	' read -r _ln _occ; do
      [ -n "$_ln" ] || continue
      _val="${_occ#* name=}"
      case "$_val" in
        \'*\') _nm="${_val#\'}"; _nm="${_nm%\'}" ;;
        \"*\") _nm="${_val#\"}"; _nm="${_nm%\"}" ;;
        *)     _nm="$_val" ;;
      esac
      case "$_nm" in
        ''|*[!A-Za-z0-9._-]*)
          echo "FAIL [P-registry] $_rel:$_ln: check-run posting name is not a parseable literal ($_occ) — a variable or unquotable name cannot be resolved against the poster registry; name the poster literally and register the <file, name> pair (fail-closed, never skipped)"
          _drc=1; continue ;;
      esac
      if ! printf '%s\n' "$REGISTRY" | grep -qxF "$_rel $_nm"; then
        echo "FAIL [P-registry] $_rel:$_ln: unregistered check-run poster (name '$_nm') — every posting call in .github/workflows/*.yml and profiles/*.yml must resolve to a registered <file, name> pair in poster-parity.sh's REGISTRY and carry every property"
        _drc=1
      fi
    done <<DEOF
$_hits
DEOF
  done
  return "$_drc"
}

# reg_names <file> <expected-names...> -> rc0 iff the file's posted names (from `-f name='...'` in
# comment-stripped source) are EXACTLY the expected set. Its unique contribution is the VANISH
# direction — a registered poster whose posting call disappeared; the new/rogue-poster direction
# is owned repo-wide, fail-closed, by discover() above (variable / double-quoted / mixed-case /
# unregistered-file shapes included).
reg_names() {
  _rf="$1"; shift
  _derived=$(grep -v '^[[:space:]]*#' "$_rf" | grep -oE -- "-f name='[a-z][a-z0-9-]*'" | sed "s/-f name='//; s/'//" | sort -u)
  _expected=$(printf '%s\n' "$@" | sort -u)
  if [ "$_derived" != "$_expected" ]; then
    echo "FAIL [P-registry] $_rf: posted check-run names do not match the poster registry."
    echo "  derived from -f name= : $(printf '%s' "$_derived" | tr '\n' ' ')"
    echo "  registry expects      : $(printf '%s' "$_expected" | tr '\n' ' ')"
    echo "  This leg guards the VANISH direction on the registered files (a registered poster whose posting call disappeared); rogue/new/unparseable posters are caught repo-wide by the discovery leg. A new poster must be added to poster-parity.sh's REGISTRY (and carry every property); a removed one must leave the registry in the same change."
    return 1
  fi
  return 0
}

run() {
  if is_adopter_tree; then
    echo "poster-parity: N/A — kit-self check (audits the kit's own reference posters; not present on an adopter tree)"
    return 0
  fi
  fail=0
  # repo-wide fail-closed discovery: every posting occurrence anywhere in .github/workflows/*.yml
  # and profiles/*.yml must resolve to a registered <file, name> pair (unparseable = RED)
  discover . || fail=1
  # completeness per file (each registry file once, with all its expected names)
  reg_names .github/workflows/ci.yml backlog-presence ceremony-binding            || fail=1
  reg_names .github/workflows/ratification.yml control-plane-ratification        || fail=1
  reg_names profiles/ratification.yml control-plane-ratification                 || fail=1
  reg_names profiles/adopter-gates.yml backlog-presence ceremony-binding loop-state || fail=1
  # the seven property sets
  while read -r _file _ctx; do
    [ -n "$_file" ] || continue
    if check_poster "$_file" "$_ctx"; then
      echo "OK: $_file poster '$_ctx' carries all seven properties"
    else
      fail=1
    fi
  done <<EOF
$REGISTRY
EOF
  if [ "$fail" -ne 0 ]; then
    echo "FAIL: poster-parity — a shipped check-run poster is missing a safety property (see the tagged lines above)"
    return 1
  fi
  echo "OK: poster-parity — all seven posters carry the property set (lookup, PATCH-or-POST, conclusion-omission, discriminator, name!=job-key, shared mapping, external_id identity), and repo-wide discovery resolves every posting call to the registry"
  return 0
}

# ── ORACLE MARKER: selftest() and everything below is the non-vacuity oracle region. The mutation
#    harness (conformance/non-vacuity.sh) neuters ONLY lines strictly ABOVE this line, so the
#    oracle's own accumulator and fixture writers can never be flipped.
selftest() {
  st=0
  base=$(mktemp -d)
  trap 'rm -rf "$base"' EXIT

  # ---- fixture writer: a minimal CLEAN poster file carrying every property -------------------
  # Written once; every mutant is a sed on a copy, VERIFIED-APPLIED by grepping the mutated file
  # (a zero-match sed is a silent no-op — measured twice in B6).
  mk_clean() {  # <path>
    cat > "$1" <<'FIXEOF'
jobs:
  gate-fixture:
    steps:
      - name: Post the fixture check-run
        run: |
          CI= sh conformance/agent-boundary.sh --conclusion "$rc" --for-class control-plane > /tmp/map.txt
          run_id=$(gh api "repos/x/commits/${SHA}/check-runs?check_name=backlog-presence" \
                     -q '.check_runs[] | select(.external_id=="sparkwright-poster:backlog-presence") | .id' 2>/dev/null | head -1)
          if [ -n "$run_id" ]; then
            method=PATCH; endpoint="repos/x/check-runs/${run_id}"
          else
            method=POST;  endpoint="repos/x/check-runs"
          fi
          if [ -n "$concl" ]; then
            gh api -X "$method" "$endpoint" \
              -f name='backlog-presence' \
              -f external_id="sparkwright-poster:backlog-presence" \
              -f head_sha="$SHA" \
              -f status="$status" \
              -f conclusion="$concl" \
              -f 'output[title]'="$title" \
              -f 'output[summary]'="$sum"
          else
            gh api -X "$method" "$endpoint" \
              -f name='backlog-presence' \
              -f external_id="sparkwright-poster:backlog-presence" \
              -f head_sha="$SHA" \
              -f status="$status" \
              -f 'output[title]'="$title" \
              -f 'output[summary]'="$sum_wait"
          fi
          api_rc=$?
          if [ "$api_rc" -ne 0 ]; then
            echo "could not post"
            if [ "$HEAD_REPO" = "$THIS_REPO" ]; then
              echo "same-repo post failure"
              exit 1
            fi
          fi
FIXEOF
  }

  # mutate <src> <dst> <sed-expr> <verify-grep-must-match:0|1> <verify-pattern> <label>
  # Applies the sed and PROVES it changed what it claims (grep the mutated file) before the mutant
  # is trusted to test anything.
  mutate() {
    sed "$3" "$1" > "$2"
    if [ "$4" = 1 ]; then
      grep -qF -- "$5" "$2" || { echo "selftest FAIL: $6 — mutation did NOT apply (expected '$5' present; a zero-match sed is a silent no-op)"; st=1; return 1; }
    else
      grep -qF -- "$5" "$2" && { echo "selftest FAIL: $6 — mutation did NOT apply (expected '$5' gone)"; st=1; return 1; }
    fi
    return 0
  }

  ALL_TAGS="P-lookup P-patch-or-post P-conclusion-omission P-discriminator P-name-collision P-mapping P-external-id"

  # expect_killed <fixture> <tag> <label>: check_poster must FAIL, its output must carry [<tag>]
  # and NO other property tag — each mutant dies by exactly its leg.
  expect_killed() {
    if _o=$(check_poster "$1" backlog-presence 2>&1); then
      echo "selftest FAIL: $3 — mutant SURVIVED (check_poster rc=0)"; st=1; return
    fi
    case "$_o" in
      *"[$2]"*) ;;
      *) echo "selftest FAIL: $3 — mutant died but NOT by its leg (no [$2] in: $_o)"; st=1; return ;;
    esac
    for _t in $ALL_TAGS; do
      [ "$_t" = "$2" ] && continue
      case "$_o" in
        *"[$_t]"*) echo "selftest FAIL: $3 — mutant tripped a SECOND leg [$_t] (not killed by exactly its own): $_o"; st=1; return ;;
      esac
    done
    echo "selftest PASS: $3"
  }

  # 1. CLEAN fixture -> every property PASSES (the positive liveness anchor).
  mk_clean "$base/clean.yml"
  if check_poster "$base/clean.yml" backlog-presence >/dev/null 2>&1; then
    echo "selftest PASS: clean fixture carries all seven properties (rc 0)"
  else
    echo "selftest FAIL: clean fixture reported a missing property:"; check_poster "$base/clean.yml" backlog-presence 2>&1 | sed 's/^/    /'; st=1
  fi

  # 2. [P-lookup] survivor: the lookup loses its server-side filter (bare /check-runs list).
  mutate "$base/clean.yml" "$base/m_lookup.yml" \
    's|/check-runs?check_name=backlog-presence"|/check-runs"|' \
    0 '?check_name=' "m1 lookup mutation applied" \
    && expect_killed "$base/m_lookup.yml" P-lookup "m1: unfiltered lookup -> killed by [P-lookup]"

  # 3. [P-patch-or-post] survivor: the PATCH branch is deleted (POST-only poster).
  mutate "$base/clean.yml" "$base/m_patch.yml" \
    '/method=PATCH/d' \
    0 'method=PATCH' "m2 patch mutation applied" \
    && expect_killed "$base/m_patch.yml" P-patch-or-post "m2: POST-only poster -> killed by [P-patch-or-post]"

  # 4. [P-conclusion-omission] survivor: the WAITING call gains a conclusion field (the collapsed
  #    if/else — the exact reviewer regression proportional-gate-wired records).
  mutate "$base/clean.yml" "$base/m_omit.yml" \
    's|"\$sum_wait"|"$sum_wait" -f conclusion="forced"|' \
    1 'conclusion="forced"' "m3 omission mutation applied" \
    && expect_killed "$base/m_omit.yml" P-conclusion-omission "m3: waiting call carries a conclusion -> killed by [P-conclusion-omission]"

  # 5. [P-discriminator] survivor: the same-repo failure logs but tolerates (exit 1 deleted).
  mutate "$base/clean.yml" "$base/m_disc.yml" \
    '/exit 1/d' \
    0 'exit 1' "m4 discriminator mutation applied" \
    && expect_killed "$base/m_disc.yml" P-discriminator "m4: logged-but-tolerated same-repo failure -> killed by [P-discriminator]"

  # 6. [P-name-collision] survivor: a JOB keyed like the posted context appears in the same file.
  cp "$base/clean.yml" "$base/m_coll.yml"
  printf '  backlog-presence:\n    runs-on: x\n' >> "$base/m_coll.yml"
  grep -qE '^  backlog-presence:[[:space:]]*$' "$base/m_coll.yml" \
    && expect_killed "$base/m_coll.yml" P-name-collision "m5: job key == posted name -> killed by [P-name-collision]" \
    || { echo "selftest FAIL: m5 — collision append did not apply"; st=1; }

  # 7. [P-mapping] survivor: the shared-mapping call is replaced by an inline conclusion literal.
  mutate "$base/clean.yml" "$base/m_map.yml" \
    's|.*agent-boundary.sh --conclusion.*|          concl=action_required|' \
    1 'concl=action_required' "m6 mapping mutation applied" \
    && expect_killed "$base/m_map.yml" P-mapping "m6: inline action_required, mapping call gone -> killed by [P-mapping]"

  # 8. [P-external-id] survivor: every external_id line deleted (stamp AND lookup filter gone).
  mutate "$base/clean.yml" "$base/m_eid.yml" \
    '/external_id/d' \
    0 'external_id' "m7 external-id mutation applied" \
    && expect_killed "$base/m_eid.yml" P-external-id "m7: no identity stamp/filter -> killed by [P-external-id]"

  # 9. [P-registry] both directions: the clean set passes; a rogue poster REDs; a vanished one REDs.
  if reg_names "$base/clean.yml" backlog-presence >/dev/null 2>&1; then
    echo "selftest PASS: registry — expected name set passes"
  else
    echo "selftest FAIL: registry — the clean fixture's name set was rejected"; st=1
  fi
  cp "$base/clean.yml" "$base/m_rogue.yml"
  printf "          gh api -X POST x -f name='rogue-gate' -f head_sha=y\n" >> "$base/m_rogue.yml"
  if reg_names "$base/m_rogue.yml" backlog-presence >/dev/null 2>&1; then
    echo "selftest FAIL: registry — an UNREGISTERED poster (rogue-gate) passed the completeness check"; st=1
  else
    echo "selftest PASS: registry — an unregistered poster REDs [P-registry]"
  fi
  if reg_names "$base/clean.yml" backlog-presence ceremony-binding >/dev/null 2>&1; then
    echo "selftest FAIL: registry — a registered-but-absent poster passed the completeness check"; st=1
  else
    echo "selftest PASS: registry — a registered poster with no posting call REDs [P-registry]"
  fi

  # 10. KIT-SELF N/A: an adopter-shaped tree (neither kit-dev marker) -> run() N/A, exit 0.
  #     LOAD-BEARING: strip the carve-out and run() proceeds to the missing registry files -> exit 1.
  _a="$base/adopter"; mkdir -p "$_a"
  if _c=$( cd "$_a" && run 2>&1 ); then _crc=0; else _crc=$?; fi
  if [ "$_crc" = 0 ] && printf '%s\n' "$_c" | grep -q 'N/A — kit-self check'; then
    echo "selftest PASS: adopter-shaped tree (no kit-dev markers) -> N/A, exit 0 (kit-self carve-out)"
  else
    echo "selftest FAIL: adopter tree did not N/A green (rc=$_crc): $_c"; st=1
  fi

  # 11. DISCOVERY (F1 / reviewer I-1) — the repo-wide fail-closed leg, driven against a fixture
  #     tree (discover takes its scan root by ARGUMENT, same rule as check_poster). The three rogue
  #     shapes below were each MEASURED to pass the pre-F1 lock (rc 0 — the reviewed miss); every
  #     fixture mutation is verified-applied by grep before it is trusted (the B6 silent-sed class).
  _d="$base/disc"
  mkdir -p "$_d/.github/workflows" "$_d/profiles"
  # positive anchor: registered <file, name> pairs only -> discover passes
  printf "          gh api -X POST \"repos/x/check-runs\" -f name='backlog-presence' -f head_sha=y\n" \
    > "$_d/.github/workflows/ci.yml"
  printf "          gh api -X POST \"repos/x/check-runs\" -f name='loop-state' -f head_sha=y\n" \
    > "$_d/profiles/adopter-gates.yml"
  if discover "$_d" >/dev/null 2>&1; then
    echo "selftest PASS: discovery — a fixture tree of only registered <file, name> pairs passes"
  else
    echo "selftest FAIL: discovery — registered-pair fixture tree rejected:"; discover "$_d" 2>&1 | sed 's/^/    /'; st=1
  fi

  # 11a. a DOUBLE-QUOTED rogue poster appended to a REGISTERED file -> RED naming file:line
  printf '          gh api -X POST "repos/x/check-runs" -f name="rogue-double" -f head_sha=y\n' >> "$_d/.github/workflows/ci.yml"
  if grep -qF 'name="rogue-double"' "$_d/.github/workflows/ci.yml"; then
    _ln=$(grep -nF 'name="rogue-double"' "$_d/.github/workflows/ci.yml" | cut -d: -f1 | head -1)
    if _o=$(discover "$_d" 2>&1); then
      echo "selftest FAIL: 11a — a double-quoted rogue poster in a registered file SURVIVED discovery (rc 0)"; st=1
    else
      case "$_o" in
        *".github/workflows/ci.yml:${_ln}:"*) echo "selftest PASS: 11a — double-quoted rogue poster REDs, verdict names file:line" ;;
        *) echo "selftest FAIL: 11a — rogue REDded but the verdict does not name .github/workflows/ci.yml:${_ln}: ($_o)"; st=1 ;;
      esac
    fi
  else
    echo "selftest FAIL: 11a — fixture append did NOT apply (no double-quoted rogue in the file)"; st=1
  fi

  # 11b. a VARIABLE-NAMED poster (-f name="$VAR": no parseable literal) -> RED naming file:line
  printf "          gh api -X POST \"repos/x/check-runs\" -f name='backlog-presence' -f head_sha=y\n" \
    > "$_d/.github/workflows/ci.yml"   # reset to the clean registered line
  printf '          gh api -X POST "repos/x/check-runs" -f name="$ROGUE_CTX" -f head_sha=y\n' >> "$_d/.github/workflows/ci.yml"
  if grep -qF 'name="$ROGUE_CTX"' "$_d/.github/workflows/ci.yml"; then
    _ln=$(grep -nF 'name="$ROGUE_CTX"' "$_d/.github/workflows/ci.yml" | cut -d: -f1 | head -1)
    if _o=$(discover "$_d" 2>&1); then
      echo "selftest FAIL: 11b — a variable-named poster SURVIVED discovery (rc 0) — the unparseable shape must fail closed, never skip"; st=1
    else
      case "$_o" in
        *".github/workflows/ci.yml:${_ln}:"*"not a parseable literal"*) echo "selftest PASS: 11b — variable-named poster REDs as unparseable, verdict names file:line" ;;
        *) echo "selftest FAIL: 11b — variable-named poster REDded but not as an unparseable literal at .github/workflows/ci.yml:${_ln}: ($_o)"; st=1 ;;
      esac
    fi
  else
    echo "selftest FAIL: 11b — fixture append did NOT apply (no \$ROGUE_CTX line in the file)"; st=1
  fi

  # 11c. a poster in a NEW UNREGISTERED profiles/ file (registered NAME, wrong file -> the PAIR
  #      must fail) -> RED naming file:line
  printf "          gh api -X POST \"repos/x/check-runs\" -f name='backlog-presence' -f head_sha=y\n" \
    > "$_d/.github/workflows/ci.yml"   # reset 11b's rogue away
  printf "          gh api -X POST \"repos/x/check-runs\" -f name='backlog-presence' -f head_sha=y\n" \
    > "$_d/profiles/rogue.yml"
  if grep -qF "name='backlog-presence'" "$_d/profiles/rogue.yml"; then
    if _o=$(discover "$_d" 2>&1); then
      echo "selftest FAIL: 11c — a poster in an UNREGISTERED profiles/ file SURVIVED discovery (rc 0)"; st=1
    else
      case "$_o" in
        *"profiles/rogue.yml:1:"*) echo "selftest PASS: 11c — poster in a new unregistered profiles/ file REDs, verdict names file:line" ;;
        *) echo "selftest FAIL: 11c — rogue file REDded but the verdict does not name profiles/rogue.yml:1: ($_o)"; st=1 ;;
      esac
    fi
  else
    echo "selftest FAIL: 11c — fixture write did NOT apply (profiles/rogue.yml missing the poster line)"; st=1
  fi

  if [ "$st" = 0 ]; then echo "poster-parity --selftest: OK (all mutants killed by exactly their leg)"; else echo "poster-parity --selftest: FAIL"; fi
  return "$st"
}

case "${1:-}" in
  --selftest) selftest ;;
  '')         run ;;
  *)          echo "usage: poster-parity.sh [--selftest]" >&2; exit 2 ;;
esac
