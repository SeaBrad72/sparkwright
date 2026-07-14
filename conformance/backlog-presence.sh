#!/bin/sh
# backlog-presence.sh — KW6-A2 board-presence merge-gate.
# Asserts that a gated-change-class PR's number appears in the `PR` cell of some board row. Reuses
# backlog-lib.sh's board parser (single source of truth) rather than re-deriving "a row". The real
# run takes the PR number + change-set listing BY ARGUMENT (never the environment — an env target lets
# a decoy redirect a control-plane check). Surfaces:
#   sh conformance/backlog-presence.sh --selftest                     # fixtures (the non-vacuity oracle)
#   sh conformance/backlog-presence.sh --dir <d> --pr <n> --changed <listing>   # the CI real run
# check_pr is NOT dead code: selftest() drives it BY ARGUMENT (KW27's root cause was a selftest that
# could reach only the leaf beneath the real function) and the ci.yml PR-time job calls it live. There
# is no `backlog-presence-run` verify.sh companion — the real run needs a PR number, which exists only
# in PR context, so the tagless-clone dry-run structurally cannot exercise it (spec §5).
# What it changes: read-only — inspects a project's BACKLOG.md + two shipped classifier seams; mutates
#   nothing.
# Guardrails: read-only; no network, no writes; targets by argument, never env — the two classifier
#   seams are invoked with KIT_ADAPTERS_DIR / KIT_GUARD_CORE / CI SCRUBBED so a decoy env cannot
#   redirect a control-plane check onto empty adapters (spec §7). jq (agent-boundary's union tool) is
#   a fail-CLOSED dependency: absent jq -> every change-set gated. The CI runner ships jq, so the gate
#   runs at full resolution there; on a jq-less machine it is conservative, never permissive. HONEST
#   CEILING: a green run proves a `PR` cell bears this number as a whole token — NOT that the row
#   describes the work, that its state is accurate, or that a human put it there. The reviewer reading
#   the board diff is the adversary with standing to say no; the gate only makes the binding a legible
#   diff.
set -eu
cd "$(dirname "$0")/.."
. conformance/backlog-lib.sh

# gate_class <changed-file> -> prints `gated` for a control-plane OR sensitive change-set, else
# `ordinary`. Two shipped seams, consulted in order (mirrors the ratification job's reconciliation,
# ci.yml:444-449):
#   - agent-boundary.sh --state : the UNION-AWARE authority on control-plane-ness. It catches
#     adapter-declared paths (e.g. AGENTS.md) that the guard-core-only --class UNDER-DETECTS as ordinary.
#   - promotion-readiness.sh --class : supplies `sensitive` (auth/, secrets, migrations, ...).
# FAIL-SAFE, and it must NEVER fail open: an unreadable change-set or a crashed seam routes to `gated`.
# The ratification job writes `|| echo NONE`, which FAILS OPEN — a crashed seam then yields NONE, read as
# "no control-plane change". That is safe THERE because that job's verdict comes from rc, not the label;
# here the verdict IS the label, so copying the idiom would INVERT the fail-safe. We branch on rc.
gate_class() {
  _changed="$1"
  [ -f "$_changed" ] || { echo gated; return 0; }          # unreadable change-set -> fail-safe gated
  # jq is the tool agent-boundary.sh's UNION detection needs to read adapters/*/adapter.json. If it is
  # absent, the union collapses to empty and AGENTS.md-class control-plane paths go undetected. A missing
  # tool must NEVER widen what passes, so fail CLOSED: no jq -> every change-set is gated. On a machine
  # without jq this gate is maximally conservative by design (the CI runner ships jq; see the header).
  command -v jq >/dev/null 2>&1 || { echo gated; return 0; }
  # Both seam calls SCRUB the classifier-config environment: KIT_ADAPTERS_DIR / KIT_GUARD_CORE (and CI)
  # come from arguments/constants, never the caller's env (spec §7). Otherwise a decoy pointing
  # KIT_ADAPTERS_DIR at an empty dir would empty the union and fail this control-plane check open.
  # --state is exit-0-by-contract; a NON-zero rc means the seam itself broke -> fail-safe gated.
  if ! _state=$(env -u KIT_ADAPTERS_DIR -u KIT_GUARD_CORE CI= sh conformance/agent-boundary.sh --changed "$_changed" --state 2>/dev/null); then
    echo gated; return 0
  fi
  if [ "$_state" != NONE ]; then echo gated; return 0; fi   # union-aware control-plane -> gated
  if ! _cls=$(env -u KIT_ADAPTERS_DIR -u KIT_GUARD_CORE CI= sh conformance/promotion-readiness.sh --class --no-verify --changed "$_changed" 2>/dev/null); then
    echo gated; return 0
  fi
  case "$_cls" in ordinary) echo ordinary ;; *) echo gated ;; esac  # sensitive|unexpected -> gated
}

# row_bears_pr <board> <pr> -> rc0 iff some row's `PR` cell bears `#<pr>` as a whole token.
# Sections without a `PR` column are skipped (only `In Review` carries one in the shipped schema) —
# the SCHEMA locates the PR, so this function never reads a state. Uses the SAME parser sequence as
# backlog-current.sh's check_section (section_rows -> header line -> col_index by name, header row 1
# skipped as data), so the two gates cannot drift over what "a row" or "the PR column" means.
# PRECONDITION: <board> must exist. Callers guard with `[ -f "$board" ]` (check_pr does) because
# `set -eu` + section_rows' awk on a MISSING file (rc 2) would abort the whole script.
# ── BRANCH-NAME BINDING (P1-CI 2/2) ────────────────────────────────────────────────────────────
# A row may be bound by the PR number `#123` OR by the BRANCH NAME. Both are accepted; either satisfies
# the gate.
#
# WHY. The PR number CANNOT EXIST before the PR is opened. So a gate that only accepts `#<pr>` makes it
# physically impossible to bind the row in the PR-opening commit — every gated PR is FORCED into a second
# push, and therefore a second full CI run. Forever. That is not an oversight anyone made; it is designed
# in, and it taxed every slice identically until this change. The branch name, by contrast, exists BEFORE
# the PR does, so the row can land in the very first commit.
#
# IS IT WEAKER? No. This gate's ceiling was always "a `PR` cell bears this token — NOT that the row
# describes the work, that its state is accurate, or that a human put it there" (see the header). A branch
# name is exactly as strong an assertion as a number: both are a token an author wrote into the cell. The
# gate proves REPRESENTATION ON THE BOARD, and it proves precisely that either way.
#
# esc_ere <s> : escape ERE metacharacters, so a branch containing `.` or `+` matches literally and can
# never be read as a pattern. A branch name is attacker-influenceable (anyone can open a PR from a
# branch), so it is untrusted input to a regex — never interpolate it raw.
esc_ere() { printf '%s' "$1" | sed 's/[][\.^$*+?(){}|\\/]/\\&/g'; }

# BRANCH_CHARS: the boundary class for a whole-token branch match. Any char legal INSIDE a git ref must
# be a NON-boundary, or `fix/p1-ci` would spuriously match a cell bearing `fix/p1-ci-path-scope`.
BRANCH_CHARS='A-Za-z0-9._/-'

row_bears_pr() {
  _bl="$1"; _pr="$2"; _br="${3:-}"; _rows_f=$(mktemp)
  [ -n "$_br" ] && _bre=$(esc_ere "$_br") || _bre=""
  for _sec in "Ready" "In Progress" "In Review" "Blocked" "Released" "Done"; do
    # NO `section_rows … | while read` — POSIX runs a pipeline's while-body in a SUBSHELL, so a
    # success-return inside it would exit only the subshell and this function would fall through to
    # its final failure path — a check that can NEVER find anything. Redirect from a temp file instead.
    section_rows "$_bl" "$_sec" > "$_rows_f"
    [ -s "$_rows_f" ] || continue
    _hdr=$(head -1 "$_rows_f")                 # the section's header row (same use as check_section)
    _idx=$(col_index "$_hdr" "PR")             # 1-based index of the `PR` column, resolved BY NAME
    [ -n "$_idx" ] || continue                 # section has no `PR` column -> skip it
    _n=0
    while IFS= read -r _row; do
      _n=$((_n + 1))
      [ "$_n" -eq 1 ] && continue              # row 1 is the section header, not data (parity w/ check_section)
      is_sep_row "$_row" && continue
      _c=$(cell "$_row" "$_idx")
      # whole-token match: kills the #28 substring AND the #2800 superstring collision.
      if printf '%s' "$_c" | grep -Eq "(^|[^0-9])#${_pr}([^0-9]|$)"; then
        rm -f "$_rows_f"; return 0
      fi
      # ...OR the BRANCH NAME as a whole token. Same boundary discipline as the number: `fix/p1-ci` must
      # NOT match a cell bearing `fix/p1-ci-path-scope`, so every char legal in a git ref is a non-boundary.
      if [ -n "$_bre" ] && printf '%s' "$_c" | grep -Eq "(^|[^${BRANCH_CHARS}])${_bre}([^${BRANCH_CHARS}]|\$)"; then
        rm -f "$_rows_f"; return 0
      fi
    done < "$_rows_f"
  done
  rm -f "$_rows_f"; return 1
}

# check_pr <project-dir> <pr-number> <changed-file> -> the REAL run. Emits a verdict STRING (N/A / OK /
# FAIL) and returns rc0 on pass/N-A, rc1 on a real FAIL. Targets by ARGUMENT, never the environment.
# The `[ -f "$_bl" ]` guard below is the load-bearing hard precondition for row_bears_pr (see its note):
# without it a declared-md board that is absent would abort under `set -eu`; with it the absence becomes
# the honest FAIL this dark-gate detector exists to raise.
check_pr() {
  _dir="$1"; _pr="$2"; _cf="$3"; _br="${4:-}"
  [ "$(gate_class "$_cf")" = gated ] || { echo "N/A: ordinary change-class; board row not required"; return 0; }
  _tok=$(resolve_backend "$_dir")
  [ -n "$_tok" ] || { echo "N/A: no backlog backend declared"; return 0; }
  # A fat-fingered backend (`markdow`, `TBD`) is signalled `unrecognized:<token>` by resolve_backend so
  # it does NOT fail open. FAIL on it (never collapse into the generic non-md N/A below) — this is the
  # dark-gate class the slice closes, and it mirrors backlog-current.sh:255-261 so the two gates reading
  # one resolve_backend speak with one voice about what an unrecognized backend means.
  case "$_tok" in
    unrecognized:*)
      _bad=${_tok#unrecognized:}
      echo "FAIL: unrecognized backlog backend '$_bad' (known: md github jira ado linear gitlab)"
      return 1 ;;
  esac
  [ "$_tok" = md ] || { echo "N/A: backend '$_tok' is not BACKLOG.md"; return 0; }
  _bl="$_dir/BACKLOG.md"
  [ -f "$_bl" ] || { echo "FAIL: declares an md backend but has no BACKLOG.md"; return 1; }
  if is_pure_template "$_bl"; then echo "N/A: board not yet in use (pristine template)"; return 0; fi
  # The verdict STRINGS are a contract (the selftest asserts them verbatim, and humans read them in CI
  # logs). When no --branch is supplied the message is byte-for-byte what it always was — branch binding
  # is ADDITIVE and must not perturb the existing surface. The branch is named only when it is in play.
  if row_bears_pr "$_bl" "$_pr" "$_br"; then
    if [ -n "$_br" ]; then
      echo "OK: backlog-presence — PR #$_pr (or branch '$_br') is bound to a board row (PR column)"
    else
      echo "OK: backlog-presence — PR #$_pr is bound to a board row (PR column)"
    fi
    return 0
  fi
  if [ -n "$_br" ]; then
    echo "FAIL: backlog-presence — no board row bears PR #$_pr or branch '$_br' in its PR cell (gated change-class)"
  else
    echo "FAIL: backlog-presence — no board row bears PR #$_pr in its PR cell (gated change-class)"
  fi
  return 1
}

# ── ORACLE MARKER: selftest() and everything below is the non-vacuity oracle region. The mutation
#    harness (conformance/non-vacuity.sh) neuters ONLY lines strictly ABOVE this line, so the
#    oracle's own st_fail accumulator can never be flipped. assert_* helpers + fixture writers live
#    BELOW here on purpose (mirrors backlog-current.sh's assert_msg at :1001).
selftest() {
  st_fail=0
  base=$(mktemp -d)

  # ===== T1 — the PR-cell presence assertion (spec §3, §7) =============================

  # a board whose In Review row bears #280 -> PRESENT (rc0). The positive liveness anchor.
  d="$base/t1_present"
  _board "$d" '| KW6-A2 | — | #280 |'
  assert_present "$d" 280 "t1/present: In Review PR cell bears #280 -> rc0 (present)"

  # substring collision: PR cell bears #28, asked for 280 -> ABSENT (rc1).
  d="$base/t1_substring"
  _board "$d" '| KW6-A2 | — | #28 |'
  assert_absent "$d" 280 "t1/substring: #28 must not satisfy #280 -> rc1 (absent)"

  # superstring collision: PR cell bears #2800, asked for 280 -> ABSENT (rc1).
  d="$base/t1_superstring"
  _board "$d" '| KW6-A2 | — | #2800 |'
  assert_absent "$d" 280 "t1/superstring: #2800 must not satisfy #280 -> rc1 (absent)"

  # #280 appears ONLY in a Notes cell, not the PR cell -> ABSENT (rc1). Binds to the column.
  d="$base/t1_notes"
  _notes_board "$d" 'supersedes #280'
  assert_absent "$d" 280 "t1/notes-cell: #280 in a Notes cell must not satisfy -> rc1 (absent)"

  # PR cell empty -> ABSENT (rc1).
  d="$base/t1_empty"
  _board "$d" '| KW6-A2 | — | |'
  assert_absent "$d" 280 "t1/empty: empty PR cell must not satisfy -> rc1 (absent)"

  # ===== T1b — BRANCH-NAME BINDING (P1-CI 2/2) ==========================================
  # The PR number cannot exist before the PR is opened, so a number-only gate FORCES a second push
  # (and a second full CI run) on every gated PR, forever. A branch name exists BEFORE the PR — so a
  # row bound by branch can land in the PR-opening commit. Both bindings are accepted.

  # a row whose PR cell bears the BRANCH NAME, with NO number yet -> PRESENT.
  d="$base/t1b_branch"
  _board "$d" '| P1-CI | — | fix/p1-ci-path-scope |'
  assert_present "$d" 999 "t1b/branch: PR cell bears the branch name (no number yet) -> rc0 (present)" "fix/p1-ci-path-scope"

  # the number still works on its own — branch binding is ADDITIVE, never a replacement.
  d="$base/t1b_number_still"
  _board "$d" '| P1-CI | — | #280 |'
  assert_present "$d" 280 "t1b/number-still-works: number binding unaffected by the branch arg" "some/other-branch"

  # NO branch supplied -> behaves exactly as before (number-only). Regression lock.
  d="$base/t1b_nobranch"
  _board "$d" '| P1-CI | — | fix/p1-ci-path-scope |'
  assert_absent "$d" 280 "t1b/no-branch-arg: a branch cell must NOT satisfy when no --branch was passed"

  # PREFIX COLLISION — the boundary discipline the number match already has. A cell bearing
  # `fix/p1-ci-path-scope` must NOT satisfy the branch `fix/p1-ci`: every char legal in a git ref is a
  # non-boundary, so the trailing `-` blocks the match. Without this, a branch could bind to any row
  # whose cell merely STARTS with its name.
  d="$base/t1b_prefix"
  _board "$d" '| P1-CI | — | fix/p1-ci-path-scope |'
  assert_absent "$d" 999 "t1b/prefix: branch 'fix/p1-ci' must NOT match cell 'fix/p1-ci-path-scope'" "fix/p1-ci"

  # a branch name in a NOTES cell must not satisfy — the binding is to the PR COLUMN, same as the number.
  d="$base/t1b_notes"
  _notes_board "$d" 'see fix/p1-ci-path-scope'
  assert_absent "$d" 999 "t1b/notes-cell: a branch in a Notes cell must not satisfy -> rc1" "fix/p1-ci-path-scope"

  # REGEX-METACHAR SAFETY — a branch name is attacker-influenceable (anyone can open a PR from a branch),
  # so it is UNTRUSTED INPUT TO A REGEX. A branch of `.*` must match literally, never as a wildcard that
  # satisfies every row on the board.
  d="$base/t1b_meta"
  _board "$d" '| P1-CI | — | #280 |'
  assert_absent "$d" 999 "t1b/metachar: a branch of '.*' must not wildcard-match any PR cell" '.*'

  # ===== T2 — change-class reconciliation: gate_class (spec §4, §7) ====================
  # gate_class takes a CHANGE-SET LISTING file (newline-delimited paths), by argument.

  # a control-plane path -> gated.
  cf="$base/cf_cp"; printf 'conformance/verify.sh\n' > "$cf"
  assert_gated "$cf" "t2/cp: control-plane path -> gated"

  # a sensitive path (auth/) -> gated. --state says NONE here; --class supplies `sensitive`.
  cf="$base/cf_sensitive"; printf 'src/auth/login.ts\n' > "$cf"
  assert_gated "$cf" "t2/sensitive: src/auth/login.ts -> gated (via --class sensitive)"

  # an ordinary path -> ordinary.
  cf="$base/cf_ordinary"; printf 'README.md\n' > "$cf"
  assert_ordinary "$cf" "t2/ordinary: README.md -> ordinary"

  # ROUTING IS LIVE, fail-safe: an unreadable/nonexistent change-set must NOT fail open.
  assert_gated "$base/cf_nonexistent" "t2/failsafe: unreadable change-set -> gated (never ordinary)"

  # THE under-detection fixture: --class says `ordinary` for AGENTS.md, --state says control-plane.
  # This fixture goes RED against a gate_class that consults only --class, and GREEN once --state is
  # consulted. It is the proof reconciliation is live rather than decorative. NEVER weaken it.
  cf="$base/cf_agents"; printf 'AGENTS.md\n' > "$cf"
  assert_gated "$cf" "t2/underdetect: --class=ordinary, --state=control-plane -> gated"

  # ===== T2 — check_pr routes, asserted by VERDICT STRING (spec §4, §5) ================
  # A gated change-set listing (control-plane) drives every non-ordinary route below.
  cfg="$base/cf_gate"; printf 'conformance/verify.sh\n' > "$cfg"
  # an ordinary change-set listing exercises the ordinary N/A route.
  cfo="$base/cf_ord"; printf 'README.md\n' > "$cfo"

  # ordinary change-class -> N/A (no board consulted at all).
  d="$base/cp_ordinary"; _proj_md_board "$d" '| KW6-A2 | — | #280 |'
  assert_msg "N/A: ordinary change-class; board row not required" \
    "cp/ordinary-class: ordinary PR -> N/A (board not required)" "$d" 280 "$cfo"

  # gated + no backend declared -> N/A.
  d="$base/cp_nobackend"; mkdir -p "$d"
  assert_msg "N/A: no backlog backend declared" \
    "cp/no-backend: undeclared backend -> N/A" "$d" 280 "$cfg"

  # gated + a non-md backend -> N/A (this gate is md-board only).
  d="$base/cp_github"; _proj_backend "$d" github
  assert_msg "N/A: backend 'github' is not BACKLOG.md" \
    "cp/non-md: github backend -> N/A" "$d" 280 "$cfg"

  # gated + declares md but has NO BACKLOG.md -> FAIL (the dark-gate detector).
  d="$base/cp_noboard"; _proj_backend "$d" md
  assert_msg "FAIL: declares an md backend but has no BACKLOG.md" \
    "cp/declared-no-board: md declared, board absent -> FAIL" "$d" 280 "$cfg"

  # gated + md + pristine template -> N/A (board not yet in use).
  d="$base/cp_template"; _proj_template "$d"
  assert_msg "N/A: board not yet in use (pristine template)" \
    "cp/pristine: untouched template -> N/A" "$d" 280 "$cfg"

  # gated + md + board bears the PR -> OK.
  d="$base/cp_present"; _proj_md_board "$d" '| KW6-A2 | — | #280 |'
  assert_msg "OK: backlog-presence — PR #280 is bound to a board row (PR column)" \
    "cp/present: gated PR bound to a row -> OK" "$d" 280 "$cfg"

  # gated + md + board does NOT bear the PR -> FAIL.
  d="$base/cp_absent"; _proj_md_board "$d" '| KW6-A2 | — | #99 |'
  assert_msg "FAIL: backlog-presence — no board row bears PR #280 in its PR cell (gated change-class)" \
    "cp/absent: gated PR with no matching row -> FAIL" "$d" 280 "$cfg"

  # ===== I-1 — the classifier-config environment must NOT redirect the seams (spec §7) =====
  # gate_class consults agent-boundary.sh, whose union-detection reads adapters/*/adapter.json.
  # A decoy that points KIT_ADAPTERS_DIR at an empty dir, OR strips jq, would make an AGENTS.md
  # change-set (genuinely control-plane) collapse to `ordinary` -> the gate silently vanishes.
  # Targets come from the repo's real adapters/, never the environment: both must stay `gated`.
  cf="$base/cf_agents_env"; printf 'AGENTS.md\n' > "$cf"

  # a hostile KIT_ADAPTERS_DIR (empty) must be scrubbed on the seam call -> still gated.
  emptydir=$(mktemp -d)
  assert_gated_env "KIT_ADAPTERS_DIR=$emptydir" "$cf" \
    "i1/env-adapters: hostile KIT_ADAPTERS_DIR=empty must not fail-open AGENTS.md -> gated"

  # jq absent from PATH must fail CLOSED (a missing tool never widens what passes) -> gated.
  assert_gated_nojq "$cf" \
    "i1/no-jq: jq absent from PATH must fail closed -> gated (never ordinary)"

  # ===== I-2 — a fat-fingered backend must FAIL, not collapse to a non-md N/A (dark gate) =====
  # resolve_backend signals a mistyped field as `unrecognized:<token>` precisely so it does NOT
  # fail open. check_pr must FAIL on it — mirroring backlog-current.sh:255-261 — not route it into
  # the generic non-md N/A. A real board binding no PR proves it is the TOKEN, not board-absence.
  d="$base/cp_typo"; _proj_backend "$d" markdow; _board "$d" '| KW6-A2 | — | #99 |'
  assert_msg "FAIL: unrecognized backlog backend 'markdow' (known: md github jira ado linear gitlab)" \
    "i2/typo-backend: 'markdow' declared + real board -> FAIL (not N/A)" "$d" 280 "$cfg"

  if [ "$st_fail" -ne 0 ]; then
    echo "backlog-presence --selftest: FAIL" >&2
    return 1
  fi
  echo "backlog-presence --selftest: OK (fixtures left in $base)"
  return 0
}

# --- selftest-only helpers (defined AFTER the selftest() marker on purpose) --------------
# These live in the ORACLE region so the non-vacuity mutation harness (which mutates only lines
# BEFORE the first ^selftest() marker) cannot neuter the oracle's own failure accumulator
# (st_fail flip). The CHECK logic above the marker stays mutable, as it must.
# assert_present <dir> <pr> <label> : row_bears_pr on <dir>/BACKLOG.md must rc0.
assert_present() {
  if row_bears_pr "$1/BACKLOG.md" "$2" "${4:-}" >/dev/null 2>&1; then _r=0; else _r=$?; fi
  if [ "$_r" -eq 0 ]; then
    echo "selftest PASS: $3"
  else
    echo "selftest FAIL: $3 (row_bears_pr rc=$_r, wanted 0/present)"; st_fail=1
  fi
}
# assert_absent <dir> <pr> <label> : row_bears_pr on <dir>/BACKLOG.md must rc!=0.
assert_absent() {
  if row_bears_pr "$1/BACKLOG.md" "$2" "${4:-}" >/dev/null 2>&1; then _r=0; else _r=$?; fi
  if [ "$_r" -ne 0 ]; then
    echo "selftest PASS: $3"
  else
    echo "selftest FAIL: $3 (row_bears_pr rc=$_r, wanted !=0/absent)"; st_fail=1
  fi
}
# assert_gated <changed-file> <label> : gate_class must print exactly `gated`.
assert_gated() {
  _g=$(gate_class "$1")
  if [ "$_g" = gated ]; then
    echo "selftest PASS: $2"
  else
    echo "selftest FAIL: $2 (gate_class -> '$_g', wanted gated)"; st_fail=1
  fi
}
# assert_ordinary <changed-file> <label> : gate_class must print exactly `ordinary`.
assert_ordinary() {
  _g=$(gate_class "$1")
  if [ "$_g" = ordinary ]; then
    echo "selftest PASS: $2"
  else
    echo "selftest FAIL: $2 (gate_class -> '$_g', wanted ordinary)"; st_fail=1
  fi
}
# assert_gated_env <VAR=value> <changed-file> <label> : export a HOSTILE classifier-config env var in
# a subshell, then assert gate_class STILL prints `gated`. Proves the seam calls scrub the env rather
# than letting a decoy redirect the real-run targets (spec §7). The export is subshell-local, so it
# cannot leak into any other fixture.
assert_gated_env() {
  _g=$( eval "export $1"; gate_class "$2" )
  if [ "$_g" = gated ]; then
    echo "selftest PASS: $3"
  else
    echo "selftest FAIL: $3 (gate_class -> '$_g' with $1, wanted gated)"; st_fail=1
  fi
}
# assert_gated_nojq <changed-file> <label> : run gate_class under a PATH with EVERY binary except jq,
# then assert it prints `gated`. Proves the fail-CLOSED jq guard: a missing tool must never widen what
# passes. The stripped PATH is subshell-local. _jqless_path builds a symlink farm of the real PATH,
# omitting only jq, so all other tools the seams need remain resolvable.
assert_gated_nojq() {
  _farm=$(_jqless_path)
  _g=$( PATH="$_farm"; export PATH; gate_class "$1" )
  if [ "$_g" = gated ]; then
    echo "selftest PASS: $2"
  else
    echo "selftest FAIL: $2 (gate_class -> '$_g' under jq-less PATH, wanted gated)"; st_fail=1
  fi
}
# _jqless_path -> print a fresh dir that symlinks every executable on the current PATH EXCEPT jq, so
# `command -v jq` fails there while grep/awk/sed/sh/env/... all still resolve.
_jqless_path() {
  _d=$(mktemp -d)
  # `IFS= read` is command-scoped -- never a global IFS assignment (semgrep: ifs-tampering).
  # PATH is ':'-delimited; tr it to newlines and read line-wise.
  while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    [ -d "$_p" ] || continue
    for _b in "$_p"/*; do
      { [ -f "$_b" ] && [ -x "$_b" ]; } || continue
      _n=${_b##*/}
      [ "$_n" = jq ] && continue
      [ -e "$_d/$_n" ] || ln -s "$_b" "$_d/$_n" 2>/dev/null
    done
  done <<PATH_EOF
$(printf '%s\n' "$PATH" | tr ':' '\n')
PATH_EOF
  printf '%s\n' "$_d"
}
# assert_msg <expected-substring> <label> <dir> <pr> <changed-file> : drive check_pr BY ARGUMENT and
# assert its VERDICT STRING (not a bare rc — a dead check and a live one are identical on rc alone).
assert_msg() {
  _out=$(check_pr "$3" "$4" "$5" 2>&1) || true
  case "$_out" in
    *"$1"*) echo "selftest PASS: $2" ;;
    *) echo "selftest FAIL: $2 (check_pr -> '$_out', wanted to contain '$1')"; st_fail=1 ;;
  esac
}

# --- fixture writers --------------------------------------------------------------------
# _board <dir> <in-review-row> : write a valid in-use board whose In Review section carries the
# given `| Item | Reviewer | PR |` row. Only In Review carries a PR column (shipped schema).
_board() {
  mkdir -p "$1"
  cat > "$1/BACKLOG.md" <<EOF
# Proj — Backlog

## In Review

| Item | Reviewer | PR |
|------|----------|----|
$2
EOF
}
# _notes_board <dir> <notes-cell> : a board whose In Review row has a real PR (#99) in the PR cell
# and the given text in a trailing Notes cell — so a number appearing only in Notes never satisfies.
_notes_board() {
  mkdir -p "$1"
  cat > "$1/BACKLOG.md" <<EOF
# Proj — Backlog

## In Review

| Item | Reviewer | PR | Notes |
|------|----------|----|-------|
| KW6-A2 | — | #99 | $2 |
EOF
}
# _proj_backend <dir> <token> : a project dir declaring only a Backlog backend field (no board).
_proj_backend() {
  mkdir -p "$1"
  cat > "$1/CLAUDE.md" <<EOF
# Proj

- **Backlog backend** (§6): $2
EOF
}
# _proj_md_board <dir> <in-review-row> : a project dir declaring an md backend AND carrying a real
# in-use board with the given In Review row.
_proj_md_board() {
  _proj_backend "$1" md
  _board "$1" "$2"
}
# _proj_template <dir> : a project dir declaring an md backend whose board is the PRISTINE template
# (carries the `| [title] |` example row and no other real data row) -> is_pure_template rc0 -> N/A.
_proj_template() {
  _proj_backend "$1" md
  cat > "$1/BACKLOG.md" <<EOF
# Proj — Backlog

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| [title] | — | — |
EOF
}

case "${1:-}" in
  --selftest)
    selftest; exit $?
    ;;
  --dir|--pr|--changed|--branch)
    # --branch is OPTIONAL and, like every other target here, comes BY ARGUMENT — never the environment.
    # (An env-supplied target lets a decoy redirect a control-plane check; that pattern was rejected once
    # already and is not coming back.) Absent --branch, the gate behaves exactly as before: PR-number only.
    _dir=""; _pr=""; _cf=""; _br=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --dir)     [ $# -ge 2 ] || { echo "usage: --dir needs a value" >&2; exit 2; }; _dir=$2; shift 2 ;;
        --pr)      [ $# -ge 2 ] || { echo "usage: --pr needs a value" >&2; exit 2; }; _pr=$2; shift 2 ;;
        --changed) [ $# -ge 2 ] || { echo "usage: --changed needs a value" >&2; exit 2; }; _cf=$2; shift 2 ;;
        --branch)  [ $# -ge 2 ] || { echo "usage: --branch needs a value" >&2; exit 2; }; _br=$2; shift 2 ;;
        *) echo "usage: backlog-presence.sh --dir <d> --pr <n> --changed <listing> [--branch <name>]" >&2; exit 2 ;;
      esac
    done
    { [ -n "$_dir" ] && [ -n "$_pr" ] && [ -n "$_cf" ]; } || {
      echo "usage: backlog-presence.sh --dir <d> --pr <n> --changed <listing> [--branch <name>]" >&2; exit 2; }
    check_pr "$_dir" "$_pr" "$_cf" "$_br"; exit $?
    ;;
  *)
    echo "usage: backlog-presence.sh --selftest | --dir <d> --pr <n> --changed <listing> [--branch <name>]" >&2
    exit 2
    ;;
esac
