#!/bin/sh
# start.sh — the ONE-COMMAND loop entry: classify (act 1), claim (act 3), print the Entry Declaration
# trailer block + the ceremony-budget line (acts 4-5). A THIN SEQUENCER over two tools that already
# exist and are already governed — `conformance/promotion-readiness.sh --class` and
# `scripts/board-claim.sh claim` — so it invents NO new policy, NO write path, and NO env dial of its
# own (SPARKWRIGHT-START-VERB, design 2026-09-16 D1/D2).
#
#   sh scripts/start.sh <ROW-ID> [--branch <name>] [--changed <listing>]
#   sh scripts/start.sh --selftest
#
# What it changes:
#   NOTHING of its own. The only writes are board-claim.sh's — the `refs/claims/<ROW>` ref on the
#   remote and the board-row edit — and start.sh CALLs board-claim (never `exec`s, so acts 4-5 can
#   still print) and prints nothing until board-claim has returned 0.
# Guardrails: (the C8 disclosure)
#   * writes nothing itself; every write is board-claim's, behind board-claim's own guard/grammars;
#   * inherits board-claim's BOARD_CLAIM_REMOTE / BOARD_CLAIM_BOARD reach UNCHANGED;
#   * sets no env dial of its own, and NEVER exports KIT_CLAIM_FRONT_DOOR (that front-door sentinel
#     belongs to board-claim's own pushes — exporting it here would be the interpreter-wrapper
#     residual the guard arm names);
#   * the class it prints is PROVISIONAL. loop-state.sh RE-DERIVES the authoritative class at
#     promotion from its own scrubbed classifier spawn over merge-base..HEAD (D2, verified), and
#     nothing downstream trusts a declared class — so a printed class is a convenience, never a
#     source of truth. A stale `--changed` degrades to "the printed class was provisional", never
#     "the gate was misled".
#
# Exit: board-claim's rc, propagated UNCHANGED — 0 (claimed) · 2 (usage / bad row / not Ready) ·
#   3 (already claimed). No trailer block is printed on ANY non-zero path. start's own precondition
#   failures (bad option, unreadable --changed listing) are rc 2. POSIX sh; dash-clean. Run the
#   classifier from the kit root — this resolves it by $0's directory, never $PWD.
set -eu

here=$(dirname "$0")

# THE CLASSIFIER IS A PLAIN SCRIPT VARIABLE, NOT AN ENV ROUTE (the loop-state.sh:168-171 precedent).
# selftest() re-points it at an in-process stub so the unrecognised-token arm can be fixtured; nothing
# OUTSIDE this file can reach it, so `start` gains no env dial by having a testable seam. Resolved by
# $0's directory (a sibling-of-parent), so a call from any $PWD reaches the real classifier.
ST_CLASSIFIER="$here/../conformance/promotion-readiness.sh"

st_usage() {
  echo "usage: sparkwright start <ROW-ID> [--branch <name>] [--changed <listing>]" >&2
  echo "       sparkwright start --selftest" >&2
}

# st_besteffort <cmd...> — run a step that MUST NOT change the exit code. THE B2 EXIT-TRAP LESSON:
# under `kit-guard install-shims` a shimmed `rm -rf` is guard-BLOCKED ("recursive rm is irreversible
# - human-gated"), and in dash a command that FAILS inside an EXIT trap OVERRIDES the script's own
# `exit 0`. Every destructive cleanup step goes through here so a blocked step can never report a
# successful selftest as failed.
st_besteffort() { "$@" 2>/dev/null || true; }

# st_cleanup — the EXIT-trap body. A no-op unless selftest() set $st_base (the same guard board-claim
# uses to keep its trap inert for the verbs). Best-effort by construction (see st_besteffort).
st_cleanup() {
  { [ -n "${st_base:-}" ] && st_besteffort rm -rf "$st_base"; } || true
  { [ -n "${st_stub:-}" ] && st_besteffort rm -rf "$st_stub"; } || true
  return 0
}
trap 'st_cleanup' EXIT INT TERM

# st_classify <ABSOLUTE-listing> -> echoes ordinary|sensitive|control-plane, or EMPTY for unknown.
# Mirrors loop-state.sh derive_class's EXACT shape (C3): the child's environment is SCRUBBED of
# KIT_ADAPTERS_DIR / KIT_UNION_LIB (an ambient value there would move a governing path out of the
# control-plane set), `--class` ONLY (it prints one token, never paths), stderr discarded, `tail -1`.
# Any token that is not one of the three -> unknown (empty). start NEVER echoes the listing's
# contents, and the caller has already absolutized + validated the path (C4).
st_classify() {
  _c=$(env -u KIT_ADAPTERS_DIR -u KIT_UNION_LIB sh "$ST_CLASSIFIER" --changed "$1" --class 2>/dev/null | tail -1) || _c=""
  case "$_c" in
    ordinary|sensitive|control-plane) printf '%s\n' "$_c" ;;
    *)                                printf '' ;;
  esac
}

# st_budget <class> — act 5, one line derived from the class (the promotion-contract dispositions in
# brief). For an underived class it names the strictest posture until the gate re-derives.
st_budget() {
  case "$1" in
    ordinary)      echo "Ceremony budget (act 5): ordinary — automated gates + self-review; the lightweight GO." ;;
    sensitive)     echo "Ceremony budget (act 5): sensitive — full dual review + human GO (threat/privacy re-check if flagged)." ;;
    control-plane) echo "Ceremony budget (act 5): control-plane — dev-clone authoring; human ratify + meta-control." ;;
    *)             echo "Ceremony budget (act 5): class not derived — assume the STRICTEST budget until the gate re-derives (run the derive command above)." ;;
  esac
}

# st_emit <row> <class> — acts 2, 4 and 5 on stdout, printed ONLY after a claim returned 0.
#   * class = ordinary            -> the reduced TWO-key block (Kit-Row + Kit-Class), per the
#                                    class-proportional required set (loop-state.sh:161-166).
#   * class = sensitive|control-plane -> the FULL four-key block carrying the REAL derived class;
#                                    Kit-Stage / Kit-Skill are placeholders you fill (start removes
#                                    friction, not judgment — the honest ceiling).
#   * class = "" (unknown, or --changed omitted) -> the FULL four-key block [C3] (degradation
#                                    ESCALATES the requirement, per loop-state.sh:158-160), with the
#                                    class rendered as the paste-FAILING placeholder `<derived class>`
#                                    [C5]: the angle brackets are outside loop-state's Kit-Class
#                                    charset, so a verbatim paste fails LOUDLY at the charset leg
#                                    rather than smuggling an unverified class through. The derive
#                                    command prints on its own line above it.
st_emit() {
  _r=$1; _cls=$2
  echo "act 2 — read the governing skill for this surface before you code: skills/<name>/SKILL.md"
  echo ""
  echo "The Entry Declaration — paste it as the LAST paragraph of the commit message, and contiguous"
  echo "(a blank line inside it truncates it; git keeps only the paragraph after the blank)."
  echo "Never self-assert the class — loop-state.sh re-derives it at promotion; the class here is provisional."
  echo ""
  case "$_cls" in
    ordinary)
      printf 'Kit-Row: %s\n' "$_r"
      echo   "Kit-Class: ordinary"
      ;;
    sensitive|control-plane)
      printf 'Kit-Row: %s\n' "$_r"
      printf 'Kit-Class: %s\n' "$_cls"
      echo   "Kit-Stage: <stage>"
      echo   "Kit-Skill: skills/<name>"
      ;;
    *)
      echo   "# derive the class, then replace the placeholder below (do not self-assert it):"
      echo   "#   sh conformance/promotion-readiness.sh --class --changed <listing>"
      printf 'Kit-Row: %s\n' "$_r"
      echo   "Kit-Class: <derived class>"
      echo   "Kit-Stage: <stage>"
      echo   "Kit-Skill: skills/<name>"
      ;;
  esac
  echo ""
  st_budget "$_cls"
}

# do_start <args...> — parse strictly, classify, claim, then (and only then) print acts 4-5.
do_start() {
  _row=""; _branch=""; _changed=""; _have_branch=0; _have_changed=0
  # STRICT PARSER, REJECT BY DEFAULT [C2]: exactly one positional (the row); accept ONLY
  # --branch / --changed; ANY other option -> rc 2, so board-claim's --links / --dry-run /
  # --board-already-moved are UNREACHABLE through `start`. A positional beginning with `-` is an
  # option-injection shape and is refused by the `-*` arm (rc 2), the same refusal board-claim gives
  # `-ROW`. start adds NO third copy of the row/branch grammar — board-claim owns and validates it.
  while [ $# -gt 0 ]; do
    case "$1" in
      --branch)  [ $# -ge 2 ] || { echo "start: --branch needs a value" >&2; return 2; }; _branch=$2;  _have_branch=1;  shift 2 ;;
      --changed) [ $# -ge 2 ] || { echo "start: --changed needs a value" >&2; return 2; }; _changed=$2; _have_changed=1; shift 2 ;;
      -*)        echo "start: unknown option '$(printf '%s' "$1" | tr -d '[:cntrl:]')' (only --branch and --changed are accepted)" >&2; st_usage; return 2 ;;
      *)         [ -z "$_row" ] || { echo "start: one row id, not two" >&2; return 2; }; _row=$1; shift ;;
    esac
  done
  [ -n "$_row" ] || { echo "start: a row id is required" >&2; st_usage; return 2; }

  # ── act 1: classify. Only when a listing is given; otherwise the class is unknown (four-key block).
  _class=""
  if [ "$_have_changed" = 1 ]; then
    # ABSOLUTIZE [C4]: promotion-readiness.sh `cd`s to the kit root before its `-f "$CHANGED"` test, so
    # a $PWD-relative name would resolve against the WRONG directory. Resolve against $PWD here.
    case "$_changed" in
      /*) _abs=$_changed ;;
      *)  _abs="$(pwd)/$_changed" ;;
    esac
    # Refuse a listing that is not a readable REGULAR file, with a plain message. Strip control bytes
    # from the echoed path (C4) and NEVER echo its contents.
    if [ ! -f "$_abs" ] || [ ! -r "$_abs" ]; then
      echo "start: --changed listing '$(printf '%s' "$_changed" | tr -d '[:cntrl:]')' is not a readable regular file." >&2
      return 2
    fi
    _class=$(st_classify "$_abs")
  fi

  # ── act 3: claim. CALL, never `exec` [C1] — `exec` would end the process before acts 4-5 print.
  # Sibling resolved via $(dirname "$0"), never $PWD [C1]. Omit --branch iff not supplied, so
  # board-claim's own `(detached)` refusal stays in ONE place. board-claim's grammars/guard/hygiene
  # all apply UNCHANGED, and start prints nothing derived from argv (row, branch, listing) until this
  # has returned 0 — so those values have already passed board-claim's own validation.
  _rc=0
  if [ "$_have_branch" = 1 ]; then
    sh "$here/board-claim.sh" claim "$_row" --branch "$_branch" || _rc=$?
  else
    sh "$here/board-claim.sh" claim "$_row" || _rc=$?
  fi

  # ── PROPAGATE rc UNCHANGED [C1]. On non-zero: board-claim's stderr has already reached the caller
  # as-is; propagate its exact rc (never collapse 3 "already claimed" into 2) and print NO trailer.
  if [ "$_rc" -ne 0 ]; then
    return "$_rc"
  fi

  # ── acts 4-5, only now.
  st_emit "$_row" "$_class"
  return 0
}

# ── ORACLE MARKER: selftest() and everything below is the non-vacuity oracle region. ─────────────
# The mutation sweep mutates only lines BEFORE this marker; the legs below are the oracle that must
# fail when it does (conformance writing-conventions).
selftest() {
  st_fail_n=0
  st_base=$(mktemp -d)
  st_stub=$(mktemp -d)
  # HERMETIC BY CONSTRUCTION (conformance/selftest-hermetic.sh face (a)): HOME inside the workdir, no
  # global/system git config, every identity set locally per clone. Real pushes to a REAL bare remote
  # at a github-shaped path (the same fixture shape as board-claim.sh:1388-1416), so the ref
  # assertions read the FIXTURE remote, not a simulation. The classify legs are hermetic to the
  # FIXTURE, not the tree: st_classify spawns promotion-readiness.sh, which reads the kit tree
  # READ-ONLY — stated, not hidden (design D3).
  HOME="$st_base/home"; mkdir -p "$HOME"; export HOME
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null; export GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM
  unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL 2>/dev/null || true

  st_remote="$st_base/github.com/fixture-owner/fixture-repo.git"
  mkdir -p "$(dirname -- "$st_remote")"
  git init -q --bare "$st_remote"
  st_mkclone A "Session A" a@example.com
  st_mkclone B "Session B" b@example.com

  # A listing whose ONLY path classifies `ordinary`, so leg (a) proves act-1 wiring end to end:
  # a real classifier spawn returning `ordinary` -> the reduced two-key block.
  printf 'docs/example.md\n' > "$st_base/listing-ordinary"

  # ---- leg (a): siblings via $(dirname "$0"); a real claim; the ref on the FIXTURE remote; act 1 ---
  # A DECOY board-claim.sh sits in the cwd. If `start` resolved its sibling by $PWD it would run the
  # decoy (which prints DECOY-MARKER and never pushes); resolving by $0's directory it runs the REAL
  # board-claim, the claim ref appears on the bare remote, and the marker is ABSENT. Non-vacuous: a
  # cwd-relative resolver flips BOTH the marker check and the ref check.
  printf '#!/bin/sh\necho DECOY-MARKER\nexit 0\n' > "$st_base/A/board-claim.sh"
  chmod +x "$st_base/A/board-claim.sh"
  st_run "$st_base/A" ROW-1 --branch feat/a --changed "$st_base/listing-ordinary"
  st_expect_rc 0 "leg a/claim: A claims a Ready row via start -> rc 0"
  if git ls-remote "$st_remote" refs/claims/ROW-1 2>/dev/null | grep -q refs/claims/ROW-1; then
    st_pass "leg a/ref: refs/claims/ROW-1 EXISTS on the FIXTURE bare remote (ls-remote — a real push)"
  else
    st_fail "leg a/ref: refs/claims/ROW-1 absent from the fixture remote after a claimed rc 0"
  fi
  st_hasnt "leg a/siblings: the cwd decoy board-claim.sh was NOT run (sibling resolved by \$0, not \$PWD)" "DECOY-MARKER"
  st_has   "leg a/act1: the block carries the DERIVED ordinary class (act 1 wired the real classifier)" "Kit-Class: ordinary"
  st_hasnt "leg a/act1-twokey: an ordinary class prints the REDUCED two-key block (no Kit-Stage)" "Kit-Stage:"
  st_has   "leg a/trailer: the block leads with Kit-Row" "Kit-Row: ROW-1"

  # ---- leg (b): a SECOND claim of the same row -> rc 3 propagated UNCHANGED, and NO trailer -------
  st_run "$st_base/B" ROW-1 --branch feat/b
  st_expect_rc 3 "leg b/second-claim: B claims a held row via start -> rc 3 (never collapsed to 2)"
  st_has   "leg b/forwarded: board-claim's refusal reaches the caller, naming the holder" "Session A <a@example.com>"
  st_hasnt "leg b/no-trailer: NO trailer block is printed on the rc-3 path" "Kit-Row:"

  # ---- leg (c): a bad row -> board-claim rc 2 propagated, and NO trailer -------------------------
  st_run "$st_base/A" 'row 1'
  st_expect_rc 2 "leg c/bad-row: an invalid row grammar -> rc 2 (board-claim owns the grammar)"
  st_has   "leg c/forwarded: the board-claim grammar refusal reaches the caller" "must match [A-Z0-9][A-Z0-9-]*"
  st_hasnt "leg c/no-trailer: NO trailer block is printed on the rc-2 path" "Kit-Row:"

  # ---- leg (d): reject-by-default parser [C2]; a control-byte row prints NO raw ESC -------------
  st_run "$st_base/A" ROW-2 --bogus
  st_expect_rc 2 "leg d/unknown-opt: an unrecognised option -> rc 2 (reject by default)"
  st_has   "leg d/unknown-opt: start names the refused option" "unknown option '--bogus'"
  st_run "$st_base/A" ROW-2 --links x
  st_expect_rc 2 "leg d/links-unreachable: board-claim's --links is UNREACHABLE through start -> rc 2"
  # NON-VACUOUS: assert the refusal is START'S OWN parser message, not a board-claim refusal that
  # happens to be rc 2 (WIP/branch/etc). If start ACCEPTED --links, this message would be absent even
  # when board-claim then refused ROW-2 for its own reason. The claim is never reached.
  st_has   "leg d/links-unreachable: --links is refused by start's parser (never forwarded to board-claim)" "unknown option '--links'"
  if git ls-remote "$st_remote" refs/claims/ROW-2 2>/dev/null | grep -q refs/claims/ROW-2; then
    st_fail "leg d/no-push: a parser-refused start pushed a ref for ROW-2 anyway"
  else
    st_pass "leg d/no-push: a parser-refused start pushed NOTHING (rejected before the claim)"
  fi
  st_run "$st_base/A" "$(printf 'ROW\033[2K')"
  st_expect_rc 2 "leg d/control-byte: a control-byte row id -> rc 2 (offline refusal)"
  case "$st_out" in
    *"$(printf '\033')"*) st_fail "leg d/no-raw-esc: a raw ESC byte reached the output" ;;
    *)                    st_pass "leg d/no-raw-esc: the control-byte row prints NO raw ESC (stripped at the refusal)" ;;
  esac

  # ---- leg (e): the best-effort EXIT-trap wrapper SWALLOWS a failing step (the B2 lesson) ---------
  if st_besteffort sh -c 'exit 1'; then
    st_pass "leg e/trap: a failing cleanup step is swallowed by st_besteffort (exit 0 preserved)"
  else
    st_fail "leg e/trap: st_besteffort let a failing step change the exit code"
  fi

  # ---- leg (f): an unrecognised classifier token -> unknown -> the FULL four-key block [C3] ------
  # A stub classifier prints a token that is NOT one of the three; st_classify must map it to unknown
  # (empty). A second stub proves a VALID token passes through — the check is not vacuously empty.
  printf '#!/bin/sh\necho banana\n'    > "$st_stub/prcls-bad";  chmod +x "$st_stub/prcls-bad"
  printf '#!/bin/sh\necho sensitive\n' > "$st_stub/prcls-sens"; chmod +x "$st_stub/prcls-sens"
  _saved_classifier=$ST_CLASSIFIER
  ST_CLASSIFIER="$st_stub/prcls-bad"
  if [ -z "$(st_classify "$st_base/listing-ordinary")" ]; then
    st_pass "leg f/unrecognised: a token that is not ordinary|sensitive|control-plane -> unknown (empty)"
  else
    st_fail "leg f/unrecognised: an unrecognised classifier token was NOT mapped to unknown"
  fi
  ST_CLASSIFIER="$st_stub/prcls-sens"
  if [ "$(st_classify "$st_base/listing-ordinary")" = sensitive ]; then
    st_pass "leg f/valid-token: a valid classifier token passes through unchanged"
  else
    st_fail "leg f/valid-token: a valid classifier token did not pass through"
  fi
  ST_CLASSIFIER=$_saved_classifier

  # the block shapes: unknown -> four keys + paste-failing placeholder + derive command;
  # ordinary -> two keys; control-plane -> four keys with the REAL class.
  _e_unknown=$(st_emit ROW-X "")
  st_emit_has "$_e_unknown" "leg f/unknown-fourkey: unknown class emits the FULL four-key block" "Kit-Stage:"
  st_emit_has "$_e_unknown" "leg f/placeholder: unknown class emits the paste-FAILING <derived class> placeholder" "Kit-Class: <derived class>"
  st_emit_has "$_e_unknown" "leg f/derive-cmd: the derive command is printed above the placeholder" "promotion-readiness.sh --class --changed"
  _e_ord=$(st_emit ROW-Y ordinary)
  st_emit_has   "$_e_ord" "leg f/ordinary-class: ordinary emits its real class" "Kit-Class: ordinary"
  st_emit_hasnt "$_e_ord" "leg f/ordinary-twokey: ordinary is a REDUCED two-key block (no Kit-Stage)" "Kit-Stage:"
  _e_cp=$(st_emit ROW-Z control-plane)
  st_emit_has "$_e_cp" "leg f/cp-class: control-plane emits its real class" "Kit-Class: control-plane"
  st_emit_has "$_e_cp" "leg f/cp-fourkey: control-plane emits the FULL four-key block" "Kit-Stage:"

  if [ "$st_fail_n" -ne 0 ]; then
    echo "start --selftest: FAIL" >&2
    return 1
  fi
  echo "start --selftest: OK (fixtures under $st_base, removed by the best-effort EXIT trap)"
  return 0
}

# --- selftest-only helpers, BELOW the marker so the mutation harness cannot neuter the oracle ----
st_pass() { echo "selftest PASS: $1"; }
st_fail() { echo "selftest FAIL: $1"; st_fail_n=1; }

# st_mkclone <name> <user.name> <user.email> — a clone of the bare remote with a fixture board that
# carries ROW-1 and ROW-2 in Ready (so a claim has a real Ready row to enter) and a Done row.
st_mkclone() {
  git clone -q "$st_remote" "$st_base/$1" 2>/dev/null
  (
    cd "$st_base/$1"
    git config user.name "$2"
    git config user.email "$3"
    git config commit.gpgsign false
  )
  cat > "$st_base/$1/BACKLOG.md" <<'BOARD_EOF'
# Fixture — Backlog

## Ready

| Item | Intent (why) | Acceptance criteria | Size | Risk | Type | Owner | Links | Success metric / hypothesis |
|------|--------------|---------------------|------|------|------|-------|-------|-----------------------------|
| `ROW-1` — the claimable row | because | it is claimed | S | low | feature | agent | — | a claim serializes |
| `ROW-2` — a second claimable row | because | it is claimed | S | low | feature | agent | — | a claim serializes |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|

## Done

| Item | Closed | Retro/outcome |
|------|--------|---------------|
| `ROW-DONE` — already shipped | 2026-09-03 | fixture. |
BOARD_EOF
}

# st_run <clone-dir> <args...> — run THIS script inside the clone, capturing rc + merged output.
st_run() {
  _sd=$1; shift
  if st_out=$( cd "$_sd" && sh "$ST_SELF" "$@" 2>&1 ); then st_rc=0; else st_rc=$?; fi
}
st_expect_rc() { # <want> <label>
  if [ "$st_rc" -eq "$1" ]; then st_pass "$2"
  else st_fail "$2 (rc=$st_rc, wanted $1); out=[$st_out]"; fi
}
st_has() { # <label> <needle> — graded on the last st_run's output
  case "$st_out" in *"$2"*) st_pass "$1" ;; *) st_fail "$1 (output lacks '$2'); out=[$st_out]" ;; esac
}
st_hasnt() { # <label> <needle>
  case "$st_out" in *"$2"*) st_fail "$1 (output wrongly carries '$2'); out=[$st_out]" ;; *) st_pass "$1" ;; esac
}
st_emit_has() { # <captured> <label> <needle> — graded on a captured st_emit string
  case "$1" in *"$3"*) st_pass "$2" ;; *) st_fail "$2 (emit lacks '$3'); emit=[$1]" ;; esac
}
st_emit_hasnt() { # <captured> <label> <needle>
  case "$1" in *"$3"*) st_fail "$2 (emit wrongly carries '$3'); emit=[$1]" ;; *) st_pass "$2" ;; esac
}

ST_SELF=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/$(basename -- "$0")

case "${1:-}" in
  --selftest) shift; if selftest; then st_rc_main=0; else st_rc_main=$?; fi ;;
  -h|--help)  st_usage; st_rc_main=2 ;;
  "")         st_usage; st_rc_main=2 ;;
  *)          if do_start "$@"; then st_rc_main=0; else st_rc_main=$?; fi ;;
esac
exit "$st_rc_main"
