#!/bin/sh
# Why this gate: docs/architecture/2026-07-26-kit-adherence-entry-binding-design.md section 3
# loop-state.sh — KIT-ADHERENCE-ENFORCEMENT Slice B1: the universal refusal floor.
#
# A change must carry an Entry Declaration on the PR HEAD commit: board row, loop stage, change
# class, governing skill. The gate-checked set is Kit-Row, Kit-Stage, Kit-Class, Kit-Skill;
# Kit-Intent, Kit-Ceremony and Kit-Stop are ADVISORY and are deliberately NOT enforced here — an
# agent authoring its own empty Kit-Stop would otherwise be a self-issued autonomy grant.
#
# THIS GATE MAKES NO ORDERING CLAIM. The declaration may be --amend'ed onto the head commit after
# all the work is done. The ordering predicate was WITHDRAWN after five defeats in three
# adversarial rounds (ceremony-binding.sh:397-414). Do not build one here.
#
# HONEST CEILING (do not overclaim):
#   * GREEN proves a declaration is PRESENT and git-PARSEABLE on the named commit; that Kit-Stage
#     and Kit-Skill RESOLVE against the map (a real skill, appropriate to the stage); that Kit-Row
#     MATCHES somewhere on the board — a SUBSTRING match, which is strictly weaker than naming a
#     row (`Kit-Row: a` passes; see BOARD-ROW-IDENTIFIER); and that Kit-Class equals the class
#     derived by `promotion-readiness.sh --class`, whose scope is GUARD-CORE ONLY and which
#     under-detects adapter-declared paths (see the derive_class note below).
#   * IT PROVES NOTHING ABOUT ORDER, and nothing about whether the named skill was read or
#     followed — the same un-gateable ceiling skills/using-skills already discloses.
#   * THE ROW LEG CAN BE N/A'd BY THE CHANGE UNDER TEST. The backend field and the board are read
#     from the PR's own worktree, so flipping the backend or deleting the board in the same commit
#     skips it. Announced on every N/A branch; boarded as LOOP-STATE-NA-SELF-SERVICE.
#   * THIS GATE CAN BE SILENTLY UNBOUND. Nothing in the kit asserts WHICH contexts are in
#     required_status_checks (branch-protection.sh:57-58 checks only that the feature is
#     enabled), so removing this context leaves every kit check green. That is true of every
#     required context today and is boarded as BRANCH-PROTECTION-DECLARATION-LOCK. Never
#     describe this gate as unbypassable without that sentence attached.
#
# ⚠️ THE HEAD DECLARATION DESCRIBES THE PULL REQUEST, NOT JUST THE LAST COMMIT. Kit-Class is
# compared against the class derived from the WHOLE change-set (merge-base HEAD origin/main), so on
# a control-plane PR the head commit must declare `control-plane` even when its own files are
# ordinary — a version bump closing a control-plane slice is the common case, and it caught this
# slice's own final commit. Comparing against the head commit's OWN diff instead would be a forgery
# hole: a control-plane change could hide behind an ordinary last commit. Fail-safe by design.
#
# THE STAGE-TO-SKILL MAP IS NOT IN THIS FILE. It lives in .kit/roster.conf (design section 3.0,
# Security N1): hardcoding it would make this a 14th site enumerating the roster, and an unmapped
# pair would fall through to PASS. The valid Kit-Stage set is DERIVED from that map, so adding a
# stage later (DESIGN-AS-A-STAGE, V2) is a data change rather than a code change here.
#
# Usage:
#   sh conformance/loop-state.sh --head <sha>     (the PR head SHA — NEVER defaults to HEAD)
#   sh conformance/loop-state.sh --selftest
#
# What it changes: nothing — read-only. Reads git history, .kit/roster.conf and skills/.
# Guardrails: fails CLOSED on a missing or unreadable map, on an empty KIT_STAGES, on a map
# incomplete in any of the three drift directions, and on an unmapped stage — each fixtured.
# ⚠️ derive_class's own fail-closed arm is DISCLOSED-UNPROVEN, not fixtured: review tried to build a
# fixture and REFUTED it — promotion-readiness.sh returns `control-plane` rc 0 for a missing file, an
# empty file, a blank-lines file, a directory and /dev/null, so it never emits an unrecognised token
# and the `*) return 1` arm is unreachable through this interface. Do not invent a fixture for it;
# the arm stays as defense against a future change in that script's contract. Refuses to default to HEAD: on pull_request,
# actions/checkout checks out the ephemeral merge commit, which carries NO trailers.
set -eu
# shellcheck disable=SC1007 # `CDPATH= cd` clears CDPATH so a user's CDPATH cannot redirect the cd.
DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

# NOT environment-overridable — and this is load-bearing, not stylistic. An earlier version honoured
# KIT_ROSTER_CONF, which let a caller substitute the stage->skill AUTHORITY wholesale (measured: a
# conf adding a `YOLO` stage with every skill mapped to every stage made the gate pass). It also
# collided with the guard's own KIT_ROSTER_CONF (roster-guard-wired.sh:46), so a developer legitimately
# exporting it for the roster dial silently redirected this gate's map. The selftest sets ROSTER_CONF
# as a plain script variable, so nothing needs an env route.
ROSTER_CONF="$DIR/.kit/roster.conf"

# The repository the declaration is read from. Production is this repo; the selftest points it
# at a throwaway fixture repo IN-PROCESS. Deliberately NOT environment-overridable: the kit has
# banked "use arguments, not env" (OBLIGATION-TESTMODE-ENV-FLAG), and a plain script variable set
# inside selftest() has no external surface at all.
LS_REPO="$DIR"

# The gate-checked fields (design section 3). Kit-Intent / Kit-Ceremony / Kit-Stop are ADVISORY
# and are deliberately absent from this list.
LS_REQUIRED_KEYS="Kit-Row Kit-Stage Kit-Class Kit-Skill"

# ls_safe — strip control characters from any PR-controlled value before it reaches a log.
#
# Applied at EVERY interpolation site, not just the one that was reported. A tracked directory name
# beginning with a newline puts attacker text at the START of an Actions log line, which is enough
# for a workflow command; the sibling sites (backend token, raw Kit-Skill) cannot reach a line start
# because `head -1` truncates, but they can still emit ANSI/CR log corruption. Fixing only the
# reported site would be this repo's named failure — fixing the example, then claiming the class.
#
# ⚠️ promotion-readiness.sh's `_render_safe` is NOT reusable here: its range deliberately preserves
# TAB and LF, so the injected line-start survives it. Measured. The full C0 range plus DEL is what
# works. LC_ALL=C so the byte ranges are not locale-dependent.
ls_safe() { LC_ALL=C printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177'; }

# Read one KEY="value" from the map by PARSING, never by sourcing — sourcing would make a conf
# file executable code reachable from a gate.
conf_val() {   # $1 = key
  sed -n "s/^$1=\"\\(.*\\)\"\$/\\1/p" "$ROSTER_CONF" 2>/dev/null | head -1
}

# map_completeness — the family-completeness lock (design section 9, Security N1).
# Three FAIL directions, none of which may fall through to PASS:
#   (a) a skill on disk absent from the map
#   (b) a map entry naming no skill on disk
#   (c) a stage in KIT_STAGES with no skill set
map_completeness() {
  [ -f "$ROSTER_CONF" ] || { echo "loop-state: map not found: $ROSTER_CONF" >&2; return 1; }
  _ls_stages=$(conf_val KIT_STAGES)
  [ -n "$_ls_stages" ] || { echo "loop-state: KIT_STAGES missing or empty in $ROSTER_CONF" >&2; return 1; }

  _ls_mapped=""
  for _ls_s in $_ls_stages; do
    _ls_sk=$(conf_val "STAGE_SKILLS_$_ls_s")
    # (c) unmapped stage — FAIL, never fall through
    [ -n "$_ls_sk" ] || {
      echo "loop-state: stage '$(ls_safe "$_ls_s")' has no skill set (unmapped stage) in $ROSTER_CONF" >&2
      return 1; }
    for _ls_k in $_ls_sk; do
      # (b) map entry naming no skill on disk
      [ -f "$DIR/skills/$_ls_k/SKILL.md" ] || {
        echo "loop-state: map entry '$(ls_safe "$_ls_k")' (stage $(ls_safe "$_ls_s")) names no skill on disk — $ROSTER_CONF" >&2
        return 1; }
      _ls_mapped="$_ls_mapped $_ls_k"
    done
  done

  # (a) a skill on disk absent from the map
  for _ls_d in "$DIR"/skills/*/; do
    [ -f "$_ls_d/SKILL.md" ] || continue
    _ls_n=${_ls_d%/}; _ls_n=${_ls_n##*/}
    case " $_ls_mapped " in
      *" $_ls_n "*) ;;
      # NAME THE FILE. --kitself exempts the SELFTEST, not run_gate: map_completeness runs on every
      # PR, so an adopter who adds one project skill reds their gate. Without the path in the
      # message they have no remedy — the plan doc that explains the map is export-ignore'd.
      # SANITISE the directory name before it reaches stderr. A PR can add a tracked directory whose
      # name begins with a newline, which puts attacker text at the START of a line in the Actions
      # log — enough for a workflow command (::stop-commands::, ::add-mask::). Bounded (FAIL path
      # only, contents:read, no secrets, set-env disabled since 2020) but free to close.
      # ⚠️ Reusing promotion-readiness.sh's _render_safe was EXECUTED and REFUTED: its range
      # deliberately preserves TAB and LF, so the injected line-start survives. The full C0 range
      # plus DEL is what actually works — measured.
      *) echo "loop-state: skill '$(ls_safe "$_ls_n")' exists on disk but is absent from the map ($ROSTER_CONF)" >&2
         echo "  Add it to the STAGE_SKILLS_<stage> line(s) it governs in that file." >&2
         return 1 ;;
    esac
  done
  return 0
}

# decl_field — read ONE trailer key off ONE commit, using git's own trailer parser.
#
# NEVER `grep '^Kit-'`. Measured: GitHub's squash-merge appends a dashes separator and a
# Co-authored-by line, which ENDS the trailer paragraph and demotes every Kit-* field above it to
# prose. Zero of the last five commits on this repo's main carry a parseable Kit-* trailer even
# though the text is plainly visible in all of them. A grep implementation would pass those
# commits — including c5d72fb, the commit that shipped the entry contract itself.
decl_field() {   # $1 = sha, $2 = key
  git -C "$LS_REPO" log -1 --format="%(trailers:key=$2,valueonly)" "$1" 2>/dev/null
}

# decl_count — occurrences of one key. Uses `grep -c .`, NEVER `wc -l`: the --format output
# appends a trailing newline, so wc -l reports 2 for a single occurrence and would false-RED
# every valid commit (design section 3.2.1B, measured).
decl_count() {   # $1 = sha, $2 = key
  decl_field "$1" "$2" | grep -c . || true
}

# valid_stage — DERIVED from the map, never a hardcoded list. This is what keeps adding a stage
# (DESIGN-AS-A-STAGE, V2) a data change rather than a code change.
valid_stage() {   # $1 = stage
  case " $(conf_val KIT_STAGES) " in
    *" $1 "*) return 0 ;;
    *)        return 1 ;;
  esac
}

# check_declaration — leg P: presence + parseability + stage resolvability on ONE named commit.
# Base-independent by construction: it reads the SHA it is given and NEVER walks to a parent. A
# declaration present only on an ancestor must FAIL, which is the negative that makes head-only
# scope safe (design section 3.1; the any-ancestor-satisfies defect ceremony-binding closed).
check_declaration() {   # $1 = sha
  _ls_rc=0
  for _ls_k in $LS_REQUIRED_KEYS; do
    # EXACTLY ONE occurrence. More than one is a FAIL, never "take the first" — a commit carrying
    # both `Kit-Class: control-plane` and `Kit-Class: ordinary` yields both lines, and head -1 /
    # tail -1 reach opposite verdicts (design section 3.2, measured decoy).
    _ls_n=$(decl_count "$1" "$_ls_k")
    if [ "$_ls_n" -eq 0 ]; then
      echo "loop-state: $1 carries no parseable '$_ls_k' trailer" >&2
      _ls_rc=1
      continue
    fi
    if [ "$_ls_n" -ne 1 ]; then
      echo "loop-state: $1 carries $_ls_n occurrences of '$_ls_k' — exactly one is required" >&2
      _ls_rc=1
      continue
    fi
    # CHARSET, REJECT BY DEFAULT, PER FIELD. Trailer values are attacker-influenceable (anyone
    # may open a PR with any trailer) and Kit-Row flows into a board grep — the identical path
    # that forced the refusal at ceremony-binding.sh:124-136, where a newline in the pattern
    # turned grep -F into an unconditional OR.
    # `#` is included deliberately: it is the canonical row id for the `github` backend that
    # check_row explicitly N/As, and it is what backlog-presence.sh already matches. Without it an
    # adopter on GitHub Issues cannot declare their row in its native form (`#123`) — measured as a
    # day-one break by review. It is inert for `grep -F`, which is the only sink this value reaches.
    case "$(decl_field "$1" "$_ls_k")" in
      ''|*[!A-Za-z0-9_.:/#-]*)
        echo "loop-state: '$_ls_k' must be non-empty and may contain only [A-Za-z0-9_.:/#-]" >&2
        echo "  — got a value with a disallowed character (refused at the boundary)." >&2
        _ls_rc=1 ;;
    esac
  done
  [ "$_ls_rc" -eq 0 ] || return 1

  _ls_stage=$(decl_field "$1" Kit-Stage | head -1)
  valid_stage "$_ls_stage" || {
    echo "loop-state: Kit-Stage '$_ls_stage' is not a stage in the map ($ROSTER_CONF)" >&2
    return 1; }
  return 0
}

# derive_class — the class comes from the same authority `ceremony-binding` uses, never re-derived
# here.
#
# ⚠️ SCOPE OF THAT AUTHORITY, STATED HONESTLY (do not call it "the single authority"). §1 of the
# contract this gate enforces says of `promotion-readiness.sh --class`: *"That classifier is
# guard-core-only and under-detects adapter-declared paths, so run the union-aware check too:
# agent-boundary.sh --changed <listing> --ratified 0"*. MEASURED divergence: `AGENTS.md`,
# `GEMINI.md`, `.gemini/config.yaml` and `.cursor/rules/*` each derive `ordinary` here while
# `agent-boundary` returns rc 1 (control-plane). So a PR touching only `AGENTS.md` can truthfully
# declare `ordinary` and pass THIS gate.
#
# That is NOT a bypass, and the bounding matters: the divergence is repo-wide and pre-existing
# (`ceremony-binding.sh:93-95` uses the identical derivation), and the union-aware check runs live
# at `.github/workflows/ratification.yml`, which still refuses the merge. What this gate must not do
# is overstate: it verifies the declared class against the guard-core classifier, not against the
# adapter union. Closing the gap needs a listing file, and this gate deliberately has no flag that
# accepts one — see LOOP-STATE-CLASS-ADAPTER-UNION on the board.
# Re-implementing the derivation would make a SIXTH derivation site and duplicate the
# control-plane path contract with nothing locking the two together (the CP7R5-KEPTSET-LOCK
# failure). Fails CLOSED: any non-zero exit, empty output or unrecognised token is a DERIVE
# FAILURE, never an implicit `ordinary` — which would be fail-OPEN on the decision this gate
# exists to protect.
#
# $1 is an OPTIONAL fixture listing, and it is reachable ONLY as a function argument from
# selftest(). There is deliberately NO --changed command-line flag — and since A4 removed
# ceremony-binding's (with its env enabler KIT_CB_TEST), NEITHER merge-time gate implements an
# author-facing fixture flag. A gate that never implements the flag cannot accept an
# author-supplied one.
derive_class() {   # [$1 = fixture listing path]
  _ls_out=""
  if [ -n "${1:-}" ]; then
    _ls_out="$(sh "$DIR/conformance/promotion-readiness.sh" --changed "$1" --class 2>/dev/null | tail -1)" || _ls_out=""
  else
    _ls_out="$(sh "$DIR/conformance/promotion-readiness.sh" --class 2>/dev/null | tail -1)" || _ls_out=""
  fi
  case "$_ls_out" in
    ordinary|sensitive|control-plane) printf '%s\n' "$_ls_out"; return 0 ;;
    *) return 1 ;;
  esac
}

# check_class — ANTI-SELF-ASSERTION. Kit-Class must EQUAL the derived class. Not ">=": an
# over-declaration is still a declaration that does not match what the diff says, and the design
# closed class forgery on equality WITHIN the guard-core set. Security review could not forge a
# class downward inside that set; it DID measure that adapter-declared paths fall outside it — see
# the derive_class note and LOOP-STATE-CLASS-ADAPTER-UNION. Do not restate this as "class forgery
# is closed" unqualified.
check_class() {   # $1 = sha, [$2 = fixture listing]
  _ls_declared=$(decl_field "$1" Kit-Class | head -1)
  if ! _ls_derived=$(derive_class "${2:-}"); then
    echo "loop-state: change-class derivation FAILED — refusing to assume a class (fail-closed)" >&2
    return 1
  fi
  if [ "$_ls_declared" != "$_ls_derived" ]; then
    echo "loop-state: Kit-Class '$_ls_declared' does not equal the derived class '$_ls_derived'." >&2
    echo "  Class is DERIVED, never self-asserted. Update the trailer to match the diff." >&2
    return 1
  fi
  return 0
}

# Board-parser primitives, SOURCED not re-derived. backlog-lib.sh exists precisely so
# backlog-current.sh and backlog-presence.sh consume ONE definition of "the board"; deriving a
# fifth is the trap design section 10.2 names explicitly.
# shellcheck disable=SC1091 # resolved at runtime from $DIR
. "$DIR/conformance/backlog-lib.sh"

# The project root the BOARD is resolved in. Production is this repo; the N/A legs point it at a
# tree with no CLAUDE.md and no board, which is exactly an adopter's first PR.
LS_BOARDROOT="$DIR"

# check_row — Kit-Row resolves to a real board row, WHERE A BOARD APPLIES.
#
# N/A ROUTES (design section 10.2). .gitattributes marks BACKLOG.md export-ignore, so a fresh
# adopter export has NO board and their import commit carries no trailer. A flatly-required row
# check would RED their first PR — the exact failure green-on-clone.sh exists to prevent. Only
# the ROW EXISTENCE leg is N/A'd; Kit-Class and Kit-Skill still apply universally.
# LS_ROW_STATE records what the row leg actually DID, so the success line cannot claim a leg that
# never ran. An N/A that is silent is how a gate ends up asserting more than it verified.
LS_ROW_STATE="unknown"

check_row() {   # $1 = sha
  _ls_row=$(decl_field "$1" Kit-Row | head -1)
  _ls_backend=$(resolve_backend "$LS_BOARDROOT")

  # ⚠️ SELF-SERVICE N/A — DISCLOSED, NOT CLOSED. The backend field and the board are read from the
  # PR's OWN worktree, so a change can grant itself an N/A in the same commit: flip the backend to
  # `GitHub Issues`, or delete BACKLOG.md, and the row leg stops checking. Reading them from the
  # merge base would close it but would break the base-independence `verify.sh` relies on to
  # register the selftest. Announced on every N/A branch below so the escape is at least LOUD, and
  # boarded as LOOP-STATE-NA-SELF-SERVICE.
  case "$_ls_backend" in
    unrecognized:*)
      # FAIL-CLOSED. A mistyped backend must not silently lose the gate — that is the dark-gate
      # class backlog-lib.sh:49-55 closed deliberately, and inheriting its signal keeps one voice.
      echo "loop-state: backlog backend '$(ls_safe "${_ls_backend#unrecognized:}")' is not recognised — refusing" >&2
      LS_ROW_STATE="refused"
      return 1 ;;
    github|jira|ado|linear|gitlab)
      LS_ROW_STATE="N/A (backend '$_ls_backend' — the row lives in an external tracker)"
      echo "loop-state: row check $LS_ROW_STATE"
      return 0 ;;
  esac

  # md, or undeclared. Undeclared plus a real in-use board still gets checked — an adopter must
  # not be able to skip row-binding by deleting a field.
  _ls_board="$LS_BOARDROOT/BACKLOG.md"
  if [ ! -f "$_ls_board" ]; then
    LS_ROW_STATE="N/A (no BACKLOG.md — fresh adopter export)"
    echo "loop-state: row check $LS_ROW_STATE"
    return 0
  fi
  if is_pure_template "$_ls_board"; then
    LS_ROW_STATE="N/A (board is still the pristine template)"
    echo "loop-state: row check $LS_ROW_STATE"
    return 0
  fi

  # -F: the value is a literal, never a pattern. T3's charset already refuses metacharacters;
  # this is the second half of the same defense.
  # ⚠️ THIS IS A WHOLE-FILE SUBSTRING MATCH, NOT A ROW LOOKUP — and that is a KNOWN WEAKNESS, not
  # an oversight. Any byte sequence occurring anywhere in the board satisfies it: `Kit-Row: a`
  # passes, as does a filename that appears only in a Links cell (both reproduced by security
  # review). The board carries no machine-resolvable row identifier, so a stricter binding was
  # tried and REFUTED twice: whole-cell equality on the Item column rejects every real row (the
  # cells are prose titles), and Item-column binding plus a word boundary still accepts single
  # letters. Fixing it properly needs a stable row-ID column on the board — an owner decision,
  # boarded as BOARD-ROW-IDENTIFIER.
  # Because of that, this leg is reported as `matched` and NEVER as `resolved`: it establishes that
  # the value occurs on the board, which is weaker than establishing that it names a row.
  if ! grep -Fq -- "$_ls_row" "$_ls_board"; then
    echo "loop-state: Kit-Row '$_ls_row' matches no row in $_ls_board" >&2
    LS_ROW_STATE="refused"
    return 1
  fi
  LS_ROW_STATE="matched (substring — see BOARD-ROW-IDENTIFIER for the ceiling)"
  return 0
}

# The repo the SKILL path is resolved in. Production is this repo; the path-safety legs point it
# at the throwaway fixture repo so hostile paths (a traversal, an untracked file, a tracked
# symlink) can be built without planting them in the kit's real skills/ tree.
LS_SKILLREPO="$DIR"

# check_skill — Kit-Skill names a real, tracked, non-symlink, stage-appropriate skill.
#
# PATH SAFETY (design section 3.0, Security N2). Kit-Skill is attacker-influenceable text
# interpolated into skills/<value>/SKILL.md. The /SKILL.md suffix blunts naive traversal, but
# that is luck rather than design — a tracked symlink skills/x -> /etc resolves outside the tree,
# reproduced in this repo as ceremony-binding MED-5. The confinement here is stronger than a
# blacklist: the value must be exactly `skills/<name>` where <name> contains NO slash at all, so
# traversal is unreachable rather than filtered.
check_skill() {   # $1 = sha
  # RESET THE DERIVED NAME. sh has no locals: _ls_name is a global, and leaving it set let a
  # neutered form-branch inherit the PREVIOUS invocation's name, skip the single-component case
  # entirely, and die at the file check instead — which made the form leg's fixture vacuous
  # (measured). Production impact today is nil (run_gate calls this once per process); this is test
  # integrity, and removing the stale-global hazard beats working around it.
  _ls_name=""
  _ls_raw=$(decl_field "$1" Kit-Skill | head -1)

  # FORM — exactly `skills/<name>`; anything else is refused before it touches the filesystem.
  case "$_ls_raw" in
    skills/*) _ls_name=${_ls_raw#skills/} ;;
    *) echo "loop-state: Kit-Skill '$(ls_safe "$_ls_raw")' must be of the form skills/<name>" >&2; return 1 ;;
  esac
  # NO slash in the name kills traversal outright (skills/../etc becomes name '../etc').
  # An empty name and any dot-dot are refused with it.
  case "$_ls_name" in
    ''|*/*|*..*) echo "loop-state: Kit-Skill name '$_ls_name' must be a single path component" >&2; return 1 ;;
  esac

  _ls_rel="skills/$_ls_name/SKILL.md"
  # Not a symlink in the directory component, and a regular file at the leaf.
  if [ -L "$LS_SKILLREPO/skills/$_ls_name" ]; then
    echo "loop-state: skills/$_ls_name is a symlink — refused" >&2; return 1
  fi
  if [ ! -f "$LS_SKILLREPO/$_ls_rel" ]; then
    echo "loop-state: Kit-Skill '$(ls_safe "$_ls_raw")' names no skill on disk ($(ls_safe "$_ls_rel"))" >&2; return 1
  fi
  # TRACKED — an untracked file is not part of the ratified tree.
  if ! git -C "$LS_SKILLREPO" ls-files --error-unmatch -- "$_ls_rel" >/dev/null 2>&1; then
    echo "loop-state: $_ls_rel is not tracked — refused" >&2; return 1
  fi
  # git mode 120000 is a symlink even when the working tree looks like a file.
  if [ "$(git -C "$LS_SKILLREPO" ls-files -s -- "$_ls_rel" | cut -d' ' -f1)" = "120000" ]; then
    echo "loop-state: $_ls_rel is recorded as a symlink (mode 120000) — refused" >&2; return 1
  fi

  # STAGE-APPROPRIATENESS — from the map, never a hardcoded pairing. An unmapped stage FAILs
  # rather than falling through (that fall-through is the shape this design has hit three times).
  _ls_stage=$(decl_field "$1" Kit-Stage | head -1)
  _ls_allowed=$(conf_val "STAGE_SKILLS_$_ls_stage")
  [ -n "$_ls_allowed" ] || {
    echo "loop-state: stage '$_ls_stage' has no skill set in the map — refused" >&2; return 1; }
  case " $_ls_allowed " in
    *" $_ls_name "*) return 0 ;;
    *) echo "loop-state: skills/$_ls_name does not govern stage '$_ls_stage' (allowed: $_ls_allowed)" >&2
       return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Kit-Scope — B9 (PHASE-B-SPINE slice 9), design docs/architecture/2026-08-11-b9-process-mechanized-design.md §2.
#
# The OPTIONAL fifth trailer: a space-separated set of path PREFIXES declaring what this pull
# request is allowed to touch. It joins the Kit-* family on the same head commit, is read by the
# same parser (decl_field — never a grep), and is graded against the changed set measured
# merge-base(default branch, head)..head — the same "THE HEAD DECLARATION DESCRIBES THE PULL
# REQUEST" doctrine the class leg already uses (see the header note).
#
# HONEST CEILING — do not overclaim (design §7.1). The declaration is written by the author it
# constrains and lives on an amendable commit, so what this binds is DECLARATION↔DIFF CONSISTENCY
# AT EACH PUSH, never "the declaration preceded the work": an author can widen the line to match
# whatever the diff became, or declare a scope as wide as the tree. No trailer mechanism can bind
# declaration-precedes-work (a frozen-first-commit variant is defeated by rebase). The value is
# (a) LEGIBILITY — one owner-vetoable line on the PR head, where widening it mid-flight is itself
# a visible diff of the declaration — and (b) DRIFT SURFACING: an undeclared path goes loud at the
# push where it first appears. Loud, not impossible (`D3′`: drift control, not an arms race).
#
# ⚠️ WHERE THE OBSERVE-MODE PRINT ACTUALLY LANDS. In observe mode this leg returns 0, and the
# installed pre-push hook's decl leg DISCARDS a PASSING predicate's output (`hooks/pre-push:90-92`
# captures stderr, then `return 0` without printing it). So at the PRE-PUSH surface the loud print
# is visible only when `KIT_SCOPE_MODE=enforce` makes this leg return non-zero; in CI — the bound
# gate that runs at the PR head on every push — the print is in the job log either way. Stated
# rather than assumed; no hook edit is made here (design §2, "zero hook edit").
#
# ⚠️ `Kit-Scope` (a PATH SET) is NOT `D11`'s `scope:` key (a SLICE IDENTITY, ceremony-binding.sh).
# Different objects; the name collision is disclosed so no reviewer conflates them. That whole
# surface (BRANCH-SCOPE-END-TO-END) is deliberately untouched here.

# The ref the scope basis is measured against. Empty = resolve it (production). The selftest pins it
# to a fixture ref — a PLAIN SCRIPT VARIABLE, never an env route (OBLIGATION-TESTMODE-ENV-FLAG; the
# rule LS_REPO / LS_BOARDROOT / LS_SKILLREPO already follow). Without a pinned base the fixture legs
# would resolve the fixture repo's AMBIENT default branch (init.defaultBranch is a user setting —
# `main` on one machine, `master` on another) and grade a base that varies per machine.
LS_SCOPE_BASEREF=""

# LS_SCOPE_STATE records what the scope leg actually DID, so the success line cannot claim a leg
# that never ran — the LS_ROW_STATE discipline. An N/A that is silent is how a gate ends up
# asserting more than it verified.
LS_SCOPE_STATE="unknown"

# scope_base — the merge base of the default branch and $1. Prints it; rc 1 when unresolvable.
# LOCAL READS ONLY (no `git fetch`, no `git remote show`): a merge gate must never depend on network
# reachability. Candidates, in order: the pinned fixture ref → origin/HEAD → origin/main →
# origin/master → main → master. Nothing here is environment-overridable.
scope_base() {   # $1 = sha
  if [ -n "$LS_SCOPE_BASEREF" ]; then
    git -C "$LS_REPO" merge-base "$LS_SCOPE_BASEREF" "$1" 2>/dev/null || return 1
    return 0
  fi
  _ls_dh=$(git -C "$LS_REPO" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
  for _ls_c in "$_ls_dh" origin/main origin/master main master; do
    [ -n "$_ls_c" ] || continue
    git -C "$LS_REPO" rev-parse --verify --quiet "$_ls_c^{commit}" >/dev/null 2>&1 || continue
    if _ls_mb=$(git -C "$LS_REPO" merge-base "$_ls_c" "$1" 2>/dev/null); then
      printf '%s\n' "$_ls_mb"
      return 0
    fi
  done
  return 1
}

# scope_covers — 0 when any declared prefix is a prefix of <path>. PREFIX MATCH ONLY: the pattern
# side is a QUOTED expansion, so the token is literal and never a glob — which is exactly why the
# hostile-token refusal above must run first (an unrejected `*` would arrive here as a live pattern).
scope_covers() {   # $1 = path, $2 = the declared prefixes
  for _ls_cp in $2; do
    case "$1" in
      "$_ls_cp"*) return 0 ;;
    esac
  done
  return 1
}

# scope_leg — the whole ladder. Called ONLY through check_scope, which owns the noglob window.
scope_leg() {   # $1 = sha
  LS_SCOPE_STATE="unknown"
  _ls_sn=$(decl_count "$1" Kit-Scope)

  # ABSENT → disclosed N/A, never red. The trailer is OPTIONAL and this is first-run-green (the B6
  # precedent): whether absence should refuse for gated classes is a dial-flip-sitting question,
  # deliberately not decided here.
  # (A present-but-EMPTY value lands in this same arm — git emits an empty line and `grep -c .`
  # counts none. That is exactly equivalent to not declaring, so nothing is weakened by it.)
  if [ "$_ls_sn" -eq 0 ]; then
    LS_SCOPE_STATE="N/A (no scope declared)"
    echo "loop-state: scope check $LS_SCOPE_STATE"
    return 0
  fi
  # EXACTLY ONE occurrence, the family's rule: two Kit-Scope lines with different sets yield both,
  # and head -1 / tail -1 reach opposite verdicts. Never "take the first".
  if [ "$_ls_sn" -ne 1 ]; then
    echo "loop-state: $1 carries $_ls_sn occurrences of 'Kit-Scope' — exactly one is required" >&2
    LS_SCOPE_STATE="refused (duplicate Kit-Scope)"
    return 1
  fi
  _ls_scope=$(decl_field "$1" Kit-Scope | head -1)

  # HOSTILE INPUT FIRST — before the value can reach any matching. Each token is interpolated into
  # a `case` PATTERN below, where an unrejected `*` or `?` silently widens the declaration to match
  # anything; the trailer is attacker-influenceable (anyone may open a PR with any trailer), the
  # identical path that forced the charset refusal on Kit-Row (check_declaration above). `..` and a
  # leading `/` are refused with them: a declared prefix is a repo-relative path, never a traversal
  # and never absolute.
  for _ls_p in $_ls_scope; do
    case "$_ls_p" in
      *'*'*|*'?'*|*'['*|*..*|/*)
        echo "loop-state: Kit-Scope token '$(ls_safe "$_ls_p")' is not a plain path prefix — a glob metacharacter (* ? [), '..' or a leading '/' is refused at the boundary" >&2
        LS_SCOPE_STATE="refused (hostile scope token)"
        return 1 ;;
    esac
  done

  # FAIL-SAFE, DISCLOSED. A shallow clone or an absent default-branch ref has no basis to measure
  # against (the measured B2-Δ2 clone-shape class). A red here would break every healthy fresh
  # clone — the green-on-clone failure class — and a SILENT pass would be worse.
  if ! _ls_base=$(scope_base "$1"); then
    LS_SCOPE_STATE="N/A (scope basis unresolvable)"
    echo "loop-state: scope check $LS_SCOPE_STATE — no merge base against a default branch (shallow clone / absent ref)"
    return 0
  fi

  # --no-renames ON PURPOSE: with rename detection a move OUT of a declared prefix reports only the
  # new path, and a move INTO one hides the deletion at the old path. Both endpoints must be graded.
  # PREFIX MATCH, not a path-component match: `docs` covers `docs-old.md` too. Declare `docs/` when
  # you mean the directory — stated, so the semantics are not mistaken for globbing.
  # ⚠️ The prefix match lives in scope_covers, NOT inline here: bash 3.2 (macOS /bin/sh, which runs
  # this repo's own hooks) mis-parses a `case` ... `esac` INSIDE a `$( ... )` — "syntax error near
  # unexpected token ';;'", measured, on one line and on several. dash parses it fine, so a
  # linux-only test would never have seen it. Keeping `case` out of the substitution is the fix.
  _ls_esc=$(
    git -C "$LS_REPO" diff --name-only --no-renames "$_ls_base" "$1" 2>/dev/null |
    while IFS= read -r _ls_f; do
      [ -n "$_ls_f" ] || continue
      if scope_covers "$_ls_f" "$_ls_scope"; then continue; fi
      printf '%s\n' "$_ls_f"
    done
  )
  _ls_ec=$(printf '%s' "$_ls_esc" | grep -c . || true)
  if [ "$_ls_ec" -eq 0 ]; then
    LS_SCOPE_STATE="PASS (every changed path is under a declared prefix)"
    echo "loop-state: scope check $LS_SCOPE_STATE"
    return 0
  fi

  echo "loop-state: SCOPE LOUD — $_ls_ec changed path(s) fall outside the declared Kit-Scope '$(ls_safe "$_ls_scope")':" >&2
  printf '%s\n' "$_ls_esc" | while IFS= read -r _ls_f; do
    [ -n "$_ls_f" ] || continue
    echo "loop-state:   $(ls_safe "$_ls_f")" >&2
  done
  echo "loop-state:   remedy: widen Kit-Scope on the head commit to cover them, or take the change out of this PR." >&2
  # THE DIAL, exact-string compared — the KIT_PUSH_DECL shape (hooks/pre-push:95): anything other
  # than the literal `enforce` stays OBSERVE. Ships observe (no exception to the observe-first
  # rollout is requested here); the flip is registered as the fifth dial in PHASE-B-DIAL-FLIP.
  if [ "${KIT_SCOPE_MODE:-}" = "enforce" ]; then
    LS_SCOPE_STATE="refused ($_ls_ec path(s) outside the declared scope — KIT_SCOPE_MODE=enforce)"
    return 1
  fi
  echo "loop-state:   observe mode — rc unchanged; set KIT_SCOPE_MODE=enforce to refuse instead (tracked: PHASE-B-DIAL-FLIP)." >&2
  LS_SCOPE_STATE="observed ($_ls_ec path(s) outside the declared scope — observe mode, rc unchanged)"
  return 0
}

# check_scope — scope_leg inside a NOGLOB window, which is load-bearing, not stylistic.
# `for _ls_p in $_ls_scope` word-splits AND pathname-expands, so a `docs/*` token would EXPAND
# against the current directory before the hostile-token check ever saw it — the check would then
# grade the expansion instead of the declaration. `set -f` closes that; `set +f` restores it for
# every leg that follows (map_completeness globs skills/*/).
check_scope() {   # $1 = sha
  set -f
  _ls_scope_rc=0
  scope_leg "$1" || _ls_scope_rc=$?
  set +f
  return "$_ls_scope_rc"
}

# ---------------------------------------------------------------------------
# Fixture repo. Tiny and trap-cleaned: heavy selftests leaking full-repo temp trees filled the
# work machine twice (banked: conformance-disk-safety). This creates four commits in an empty
# repo — no clone, no checkout of this tree.
# ---------------------------------------------------------------------------
LS_FXDIR=""
ls_fx_cleanup() { [ -n "$LS_FXDIR" ] && [ -d "$LS_FXDIR" ] && rm -rf "$LS_FXDIR"; LS_FXDIR=""; }

ls_fx_build() {
  LS_FXDIR=$(mktemp -d) || return 1
  trap ls_fx_cleanup EXIT INT TERM
  git -C "$LS_FXDIR" init -q
  git -C "$LS_FXDIR" config user.email fixture@example.invalid
  git -C "$LS_FXDIR" config user.name "loop-state fixture"

  # A — CONFORMANT: contiguous trailer block, nothing after it but another trailer.
  : > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'conformant fixture\n\nbody\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/tdd\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_OK=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # B — BASELINE NEGATIVE: no Kit-* trailers at all.
  echo b > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'no declaration at all\n\njust a body\n' | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_NONE=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # C — ANCESTOR NEGATIVE: this child carries nothing; its PARENT (B... and A) do/does not
  # matter — what matters is that checking THIS sha must not walk back to A and pass.
  echo c > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'child of a declared commit\n\nbody\n' | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_CHILD=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # D — KILL FIXTURE: all four fields PRESENT in the message, severed from the trailer paragraph
  # by GitHub's squash separator. git parses NO Kit-* trailers here. A grep implementation passes
  # this commit; the real parser must FAIL it. This is the exact shape of every squash-merge on
  # this repo's main today.
  echo d > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'severed trailer block\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/tdd\n\n---------\n\nCo-authored-by: X <x@example.invalid>\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_SEVERED=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # E — BAD STAGE: well-formed block, but Kit-Stage is not in the map.
  echo e > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'stage outside the map\n\nKit-Row: DEMO-ROW\nKit-Stage: Wibble\nKit-Class: ordinary\nKit-Skill: skills/tdd\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_BADSTAGE=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # F — DUPLICATE KEY: two Kit-Class lines with OPPOSITE values. Measured decoy: `head -1` and
  # `tail -1` reach opposite verdicts, so "take the first" is not a safe reading. Must FAIL.
  echo f > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'duplicate key decoy\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: control-plane\nKit-Class: ordinary\nKit-Skill: skills/tdd\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_DUP=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # G — METACHARACTER Kit-Row. The value flows into a board grep (T6), the identical path that
  # forced the charset refusal at ceremony-binding.sh:124-136. Must be refused AT THE BOUNDARY,
  # not matched.
  echo g > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'regex metachar row\n\nKit-Row: DEMO.*ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/tdd\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_META=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # H — SINGLE-KEY POSITIVE for the count logic. Paired with F so an off-by-one (wc -l vs
  # grep -c .) cannot satisfy both: wc -l reports 2 for this one commit and would false-RED it.
  echo h > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'single key positive\n\nKit-Row: DEMO-ROW\nKit-Stage: Review\nKit-Class: sensitive\nKit-Skill: skills/review\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_SINGLE=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # I — STAGE-INAPPROPRIATE: skills/tdd is real, but does not govern Plan.
  echo i > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'stage-inappropriate skill\n\nKit-Row: DEMO-ROW\nKit-Stage: Plan\nKit-Class: ordinary\nKit-Skill: skills/tdd\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_WRONGSKILL=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # J — NONEXISTENT skill.
  echo j > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'nonexistent skill\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/nosuchskill\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_NOSKILL=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # K — TRAVERSAL: passes the charset (dot and slash are legal characters) so only the form and
  # single-component rules stop it.
  echo k > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'traversal skill\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/../../etc\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_TRAVERSAL=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # L — SYMLINK skill, TRACKED at git mode 120000 inside the fixture repo. Built here rather than
  # in conformance/fixtures/ so no tracked symlink is planted in the kit's real tree (and the
  # guard correctly refuses agent writes there anyway).
  # ⚠️ NON-VACUITY: these hostile skills are named `tdd` and `evals` — both STAGE-APPROPRIATE for
  # Kit-Stage: Build in the real map. If they were named arbitrarily, the stage check would reject
  # them first and these legs would pass for the wrong reason, leaving the path-safety checks
  # untested. Named this way, ONLY the symlink / untracked checks can reject them.
  mkdir -p "$LS_FXDIR/skills/build"
  printf '# fixture skill\n' > "$LS_FXDIR/skills/build/SKILL.md"
  # ⚠️ The symlink targets a directory that REALLY CONTAINS a SKILL.md. An earlier version pointed
  # it at /etc, which made the leg vacuous: it was rejected by the file-does-not-exist check, so
  # disabling symlink refusal entirely left the selftest green. Measured, then fixed.
  ln -s build "$LS_FXDIR/skills/tdd"
  mkdir -p "$LS_FXDIR/skills/evals"
  printf '# present on disk, never added to the index\n' > "$LS_FXDIR/skills/evals/SKILL.md"
  git -C "$LS_FXDIR" add skills/build skills/tdd
  git -C "$LS_FXDIR" commit -q -m "fixture skill tree"

  # L — SYMLINK skill, tracked at git mode 120000, and stage-appropriate by name.
  echo l > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'symlinked skill\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/tdd\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_SYMSKILL=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # M — UNTRACKED skill: present on disk, absent from the index, stage-appropriate by name.
  echo m > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'untracked skill\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/evals\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_UNTRACKED=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # N — POSITIVE inside the fixture repo: tracked, regular, stage-appropriate.
  echo n > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'good fixture skill\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/build\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_GOODSKILL=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # ⚠️ HERMETIC BOARD, in its own subdirectory. The row legs used to assert against the KIT's live
  # BACKLOG.md, which made the selftest depend on mutable project data: it died on an adopter tree
  # (BACKLOG.md is export-ignore'd, so the negative leg inverted and green-on-clone went RED) and it
  # would die on the kit's own CI the day KIT-ADHERENCE-ENFORCEMENT is archived to Done.
  # The board lives in $LS_FXDIR/board/ and NOT in $LS_FXDIR itself — putting it at the fixture-repo
  # root would give $LS_FXDIR a BACKLOG.md and silently break the "no board present must be N/A"
  # leg, which is how the reviewer's first attempt at this failed.
  mkdir -p "$LS_FXDIR/board"
  printf '# Fixture board\n\n## Ready\n\n| Item | Intent |\n|---|---|\n| FIXTURE-ROW-ALPHA — a fixture row | why |\n' \
    > "$LS_FXDIR/board/BACKLOG.md"

  # N/A route 2: a declared non-md backend. resolve_backend reads only <dir>/CLAUDE.md.
  # ⚠️ THIS DIR MUST ALSO CARRY A BOARD, or the leg is VACUOUS — measured: without a BACKLOG.md the
  # no-board branch satisfies it, so deleting the entire backend branch left the suite green. The
  # board's row deliberately does NOT contain the fixture's Kit-Row, so only the backend branch can
  # produce the N/A.
  mkdir -p "$LS_FXDIR/backend-github"
  printf '# Fixture charter\n\n- **Backlog backend**: GitHub Issues\n' > "$LS_FXDIR/backend-github/CLAUDE.md"
  printf '# Fixture board\n\n## Ready\n\n| Item | Intent |\n|---|---|\n| OTHER-ROW-PRESENT — not the declared row | why |\n' \
    > "$LS_FXDIR/backend-github/BACKLOG.md"

  # N/A route 3: a pristine-template board. is_pure_template wants the `| [title] |` example row
  # AND no other real data row.
  mkdir -p "$LS_FXDIR/board-pristine"
  printf '# Fixture board\n\n## Ready\n\n| Item | Intent |\n|---|---|\n| [title] | [why] |\n' \
    > "$LS_FXDIR/board-pristine/BACKLOG.md"

  # Fail-closed: a mistyped backend. backlog-lib signals this as `unrecognized:<token>` precisely
  # so it does NOT fail open to N/A.
  mkdir -p "$LS_FXDIR/backend-bogus"
  printf '# Fixture charter\n\n- **Backlog backend**: markdow\n' > "$LS_FXDIR/backend-bogus/CLAUDE.md"

  # Map-completeness drift directions (b) and (c). Plan T1 step 4 required both and neither was
  # fixtured: review measured that gutting either check left the suite GREEN. The code was correct
  # and nothing held it there.
  # (b) a map entry naming no skill on disk.
  printf 'KIT_STAGES="Discover Plan Build Review Release Done Operate"\nSTAGE_SKILLS_Discover="continuous-discovery ghost-skill using-skills"\nSTAGE_SKILLS_Plan="design plan using-skills"\nSTAGE_SKILLS_Build="build tdd debugging worktrees evals using-skills"\nSTAGE_SKILLS_Review="review verification demonstrate using-skills"\nSTAGE_SKILLS_Release="verification demonstrate operating using-skills"\nSTAGE_SKILLS_Done="verification demonstrate using-skills"\nSTAGE_SKILLS_Operate="operating debugging using-skills"\n' \
    > "$LS_FXDIR/roster-ghost-skill.conf"
  # (c) a stage declared in KIT_STAGES with no skill set.
  printf 'KIT_STAGES="Discover Plan Build Review Release Done Operate Ghost"\nSTAGE_SKILLS_Discover="continuous-discovery using-skills"\nSTAGE_SKILLS_Plan="design plan using-skills"\nSTAGE_SKILLS_Build="build tdd debugging worktrees evals using-skills"\nSTAGE_SKILLS_Review="review verification demonstrate using-skills"\nSTAGE_SKILLS_Release="verification demonstrate operating using-skills"\nSTAGE_SKILLS_Done="verification demonstrate using-skills"\nSTAGE_SKILLS_Operate="operating debugging using-skills"\n' \
    > "$LS_FXDIR/roster-unmapped-stage.conf"
  # Fail-closed: an empty KIT_STAGES. (The missing-map case needs no fixture — the legs point
  # ROSTER_CONF at a path that does not exist.)
  printf 'KIT_STAGES=""\n' > "$LS_FXDIR/roster-empty-stages.conf"

  # O — row present on the hermetic board, for the row-resolution positive.
  echo o > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'real board row\n\nKit-Row: FIXTURE-ROW-ALPHA\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/tdd\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_REALROW=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # P — FORM: a Kit-Skill with no `skills/` prefix. Needed to exercise the form rule in isolation;
  # review measured that gutting it left the suite green because the single-component rule caught
  # the traversal fixture instead.
  echo p > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'skill without the skills prefix\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: tdd\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_BADFORM=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # Q — CONTROL-PLANE POSITIVE: declared == derived == control-plane. The class axis had two
  # negatives and only an `ordinary` positive; this is the class where a false-RED costs most.
  echo q > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'control-plane positive\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: control-plane\nKit-Skill: skills/tdd\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_CPOK=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # R — CONTROL CHARACTER in a PR-controlled value, to fixture ls_safe. The trailer is the usable
  # seam: the skills-directory path has none (map_completeness scans the real tree), so this is the
  # one site where the sanitiser can be held hermetically. check_skill is called DIRECTLY by the leg,
  # which is what lets an ESC through — check_declaration's charset would refuse it first.
  echo r > "$LS_FXDIR/a"; git -C "$LS_FXDIR" add a
  printf 'ctrl char in Kit-Skill\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: bad\033[2Kevil\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_CTRL=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # --- B9 Kit-Scope fixtures --------------------------------------------------------------------
  # The scope leg grades a DIFF, so these need a base and branches off it. The base is PINNED into
  # LS_SCOPE_BASEREF by the legs (never auto-resolved) so nothing here depends on the fixture repo's
  # ambient default-branch name.
  LS_FX_SCOPEBASE=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # S1 — COVERED: the only changed path is under the single declared prefix.
  mkdir -p "$LS_FXDIR/docs"
  echo s1 > "$LS_FXDIR/docs/note.md"; git -C "$LS_FXDIR" add docs/note.md
  printf 'scope covered\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/tdd\nKit-Scope: docs/\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_SCOPE_IN=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # S2 — ESCAPING: branched off the base so its diff is exactly its own two paths, one of which is
  # outside the declared prefix. ⚠️ NON-VACUITY: it also changes a path that IS covered, so a leg
  # that merely notices "something changed" cannot pass for the wrong reason.
  git -C "$LS_FXDIR" checkout -q -b scope-out "$LS_FX_SCOPEBASE"
  mkdir -p "$LS_FXDIR/docs" "$LS_FXDIR/conformance"
  echo s2 > "$LS_FXDIR/docs/note.md"
  echo s2 > "$LS_FXDIR/conformance/stray.sh"
  git -C "$LS_FXDIR" add docs/note.md conformance/stray.sh
  printf 'scope escaped\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/tdd\nKit-Scope: docs/\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_SCOPE_OUT=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # S3/S4/S5 — HOSTILE TOKENS, one face each. ⚠️ NON-VACUITY: every one of them ALSO declares a
  # prefix that covers nothing in the diff, so if the hostile check were removed the leg would fall
  # through to the escape branch and refuse for the WRONG reason — which is exactly what the
  # reason-assertions below (with their forbidden downstream string) measure.
  echo s3 > "$LS_FXDIR/conformance/stray.sh"; git -C "$LS_FXDIR" add conformance/stray.sh
  printf 'scope traversal token\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/tdd\nKit-Scope: docs/../etc\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_SCOPE_DOTDOT=$(git -C "$LS_FXDIR" rev-parse HEAD)

  echo s4 > "$LS_FXDIR/conformance/stray.sh"; git -C "$LS_FXDIR" add conformance/stray.sh
  printf 'scope glob token\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/tdd\nKit-Scope: docs/*\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_SCOPE_GLOB=$(git -C "$LS_FXDIR" rev-parse HEAD)

  echo s5 > "$LS_FXDIR/conformance/stray.sh"; git -C "$LS_FXDIR" add conformance/stray.sh
  printf 'scope absolute token\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/tdd\nKit-Scope: /etc\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_SCOPE_ABS=$(git -C "$LS_FXDIR" rev-parse HEAD)

  # S6 — DUPLICATE Kit-Scope with OPPOSITE sets: `head -1` and `tail -1` reach opposite verdicts,
  # so "take the first" is not a safe reading here either. Must FAIL on the count, before matching.
  echo s6 > "$LS_FXDIR/conformance/stray.sh"; git -C "$LS_FXDIR" add conformance/stray.sh
  printf 'duplicate scope key\n\nKit-Row: DEMO-ROW\nKit-Stage: Build\nKit-Class: ordinary\nKit-Skill: skills/tdd\nKit-Scope: docs/\nKit-Scope: conformance/\n' \
    | git -C "$LS_FXDIR" commit -q -F -
  LS_FX_SCOPE_DUP=$(git -C "$LS_FXDIR" rev-parse HEAD)
  return 0
}

selftest() {
  st_fail=0
  # FIRST: check the checker. Eight legs below depend on ls_assert_reason, and it is structurally
  # invisible to the CI mutation sweep. If it is broken, every one of those legs is broken together
  # and silently — so it is exercised before anything relies on it.
  # ⚠️ THIS CALL IS WHERE THE REGRESS STOPS. Nothing asserts that this line still exists — deleting
  # it restores the un-covered state silently. One level of meta is the standard `verify.sh
  # --selftest` already sets, so stopping here is deliberate; do not "tidy" this call away.
  ls_assert_reason_selfcheck || st_fail=1
  _st_saved="$ROSTER_CONF"

  # POSITIVE LIVENESS ANCHOR — the real, shipped map must pass.
  # An always-FAIL implementation breaks THIS leg.
  ROSTER_CONF="$_st_saved"
  if ! map_completeness >/dev/null 2>&1; then
    echo "selftest FAIL: the shipped .kit/roster.conf map must satisfy map_completeness"
    st_fail=1
  fi

  # LOAD-BEARING NEGATIVE (a) — a skill on disk absent from the map must FAIL.
  # An always-PASS implementation breaks THIS leg.
  ROSTER_CONF="$DIR/conformance/fixtures/loop-state/roster-missing-skill.conf"
  if [ ! -f "$ROSTER_CONF" ]; then
    echo "selftest FAIL: fixture roster-missing-skill.conf is missing"; st_fail=1
  elif map_completeness >/dev/null 2>&1; then
    echo "selftest FAIL: a skill on disk absent from the map must FAIL, not pass"; st_fail=1
  fi

  ROSTER_CONF="$_st_saved"

  # --- T2: declaration read from ONE named commit -------------------------------------------
  _st_repo_saved="$LS_REPO"
  if ! ls_fx_build; then
    echo "selftest FAIL: could not build the fixture repo"; st_fail=1
  else
    LS_REPO="$LS_FXDIR"

    # POSITIVE — a conformant, contiguous declaration passes.
    check_declaration "$LS_FX_OK" >/dev/null 2>&1 \
      || { echo "selftest FAIL: a conformant declaration must PASS"; st_fail=1; }

    # BASELINE NEGATIVE — no Kit-* trailers at all. The simplest and most load-bearing negative.
    check_declaration "$LS_FX_NONE" >/dev/null 2>&1 \
      && { echo "selftest FAIL: a commit with no declaration must FAIL"; st_fail=1; }

    # ANCESTOR NEGATIVE — makes head-only scope safe. If this passes, the gate is walking to a
    # parent and ANY ancestor's trailer satisfies it (the defect ceremony-binding closed).
    check_declaration "$LS_FX_CHILD" >/dev/null 2>&1 \
      && { echo "selftest FAIL: a declaration on an ANCESTOR must not satisfy the head commit"; st_fail=1; }

    # KILL FIXTURE — all four fields present in the body but severed by the squash separator.
    # A grep implementation PASSES this. If this leg ever goes green, the gate is matching text
    # instead of parsing structure and the slice has failed.
    check_declaration "$LS_FX_SEVERED" >/dev/null 2>&1 \
      && { echo "selftest FAIL: a SEVERED trailer block must FAIL (grep would pass it)"; st_fail=1; }

    # STAGE NEGATIVE — a stage outside the map must FAIL, never fall through.
    check_declaration "$LS_FX_BADSTAGE" >/dev/null 2>&1 \
      && { echo "selftest FAIL: a Kit-Stage outside the map must FAIL"; st_fail=1; }

    # --- T3: exactly-one + charset ------------------------------------------------------------
    # SINGLE-KEY POSITIVE — pairs with the duplicate negative below. A wc -l implementation
    # reports 2 for this commit and would false-RED it; grep -c . reports 1.
    check_declaration "$LS_FX_SINGLE" >/dev/null 2>&1 \
      || { echo "selftest FAIL: a single-occurrence declaration must PASS (wc -l off-by-one?)"; st_fail=1; }

    # DUPLICATE NEGATIVE — two Kit-Class lines with opposite values must FAIL, never "take the
    # first". An off-by-one cannot satisfy both this and the single-key positive above.
    check_declaration "$LS_FX_DUP" >/dev/null 2>&1 \
      && { echo "selftest FAIL: a duplicate Kit-Class must FAIL, never take-the-first"; st_fail=1; }

    # CHARSET NEGATIVE — a regex-metacharacter Kit-Row must be refused at the boundary before it
    # ever reaches a board grep.
    check_declaration "$LS_FX_META" >/dev/null 2>&1 \
      && { echo "selftest FAIL: a metacharacter Kit-Row must be refused at the boundary"; st_fail=1; }

    # --- T4: Kit-Class must EQUAL the derived class -------------------------------------------
    _st_fxd="$DIR/conformance/fixtures/loop-state"

    # POSITIVE — declared `ordinary`, derived `ordinary`.
    check_class "$LS_FX_OK" "$_st_fxd/changed-ordinary.txt" >/dev/null 2>&1 \
      || { echo "selftest FAIL: declared class equal to derived class must PASS"; st_fail=1; }

    # THE KEY NEGATIVE — declared `ordinary`, derived `control-plane`. An agent under-declaring
    # its way past the ceremony a control-plane change owes is the forgery this leg closes.
    check_class "$LS_FX_OK" "$_st_fxd/changed-controlplane.txt" >/dev/null 2>&1 \
      && { echo "selftest FAIL: declared ordinary vs derived control-plane must FAIL"; st_fail=1; }

    # OVER-DECLARATION NEGATIVE — declared `sensitive`, derived `ordinary`. Also a FAIL: the
    # contract is equality, not ">=". A declaration that does not match the diff is not a
    # conservative choice, it is an inaccurate one.
    check_class "$LS_FX_SINGLE" "$_st_fxd/changed-ordinary.txt" >/dev/null 2>&1 \
      && { echo "selftest FAIL: over-declared class must FAIL (contract is equality)"; st_fail=1; }

    # --- T5: Kit-Skill resolution, stage-appropriateness, path safety -------------------------
    # Legs resolved against the REAL kit tree.
    check_skill "$LS_FX_OK" >/dev/null 2>&1 \
      || { echo "selftest FAIL: a real, stage-appropriate skill must PASS"; st_fail=1; }
    check_skill "$LS_FX_WRONGSKILL" >/dev/null 2>&1 \
      && { echo "selftest FAIL: skills/tdd must not govern Kit-Stage: Plan"; st_fail=1; }
    check_skill "$LS_FX_NOSKILL" >/dev/null 2>&1 \
      && { echo "selftest FAIL: a nonexistent skill must FAIL"; st_fail=1; }
    check_skill "$LS_FX_TRAVERSAL" >/dev/null 2>&1 \
      && { echo "selftest FAIL: a traversal Kit-Skill must FAIL"; st_fail=1; }

    # Path-safety legs resolved against the FIXTURE repo, where the hostile trees live.
    _st_skillrepo_saved="$LS_SKILLREPO"
    LS_SKILLREPO="$LS_FXDIR"
    check_skill "$LS_FX_GOODSKILL" >/dev/null 2>&1 \
      || { echo "selftest FAIL: a tracked regular skill in the fixture repo must PASS"; st_fail=1; }
    check_skill "$LS_FX_SYMSKILL" >/dev/null 2>&1 \
      && { echo "selftest FAIL: a tracked SYMLINK skill (mode 120000) must FAIL"; st_fail=1; }
    check_skill "$LS_FX_UNTRACKED" >/dev/null 2>&1 \
      && { echo "selftest FAIL: an UNTRACKED skill must FAIL"; st_fail=1; }
    LS_SKILLREPO="$_st_skillrepo_saved"

    # --- T6: Kit-Row resolution and the N/A routes --------------------------------------------
    # HERMETIC: every row leg runs against the fixture board, never the kit's live BACKLOG.md.
    _st_board_saved="$LS_BOARDROOT"
    LS_BOARDROOT="$LS_FXDIR/board"

    # POSITIVE — a row present on the board matches.
    check_row "$LS_FX_REALROW" >/dev/null 2>&1 \
      || { echo "selftest FAIL: a Kit-Row present on the board must match"; st_fail=1; }

    # NEGATIVE — a row that appears nowhere on the board must FAIL.
    check_row "$LS_FX_OK" >/dev/null 2>&1 \
      && { echo "selftest FAIL: Kit-Row 'DEMO-ROW' appears nowhere on the board and must FAIL"; st_fail=1; }

    # N/A ROUTE 1 — no board at all: exactly a fresh adopter export (BACKLOG.md is export-ignore'd).
    # Must be N/A, never RED. This is the green-on-clone failure class.
    LS_BOARDROOT="$LS_FXDIR"
    check_row "$LS_FX_OK" >/dev/null 2>&1 \
      || { echo "selftest FAIL: no board present must be N/A, not a RED first PR"; st_fail=1; }

    # N/A ROUTE 2 — a non-BACKLOG.md backend (design §10.2 / §11.3). Required by plan T6.2 and
    # previously unfixtured: only the no-board route was covered.
    LS_BOARDROOT="$LS_FXDIR/backend-github"
    check_row "$LS_FX_OK" >/dev/null 2>&1 \
      || { echo "selftest FAIL: a github backend must N/A the row leg"; st_fail=1; }

    # N/A ROUTE 3 — a pristine-template board (§11.3, plan T6.2). Also previously unfixtured.
    LS_BOARDROOT="$LS_FXDIR/board-pristine"
    check_row "$LS_FX_OK" >/dev/null 2>&1 \
      || { echo "selftest FAIL: a pristine-template board must N/A the row leg"; st_fail=1; }

    # FAIL-CLOSED — an unrecognised backend must REFUSE, never N/A. backlog-lib closed this
    # dark-gate class deliberately; inheriting the signal is only real if it is held here.
    LS_BOARDROOT="$LS_FXDIR/backend-bogus"
    check_row "$LS_FX_OK" >/dev/null 2>&1 \
      && { echo "selftest FAIL: an unrecognised backend must FAIL-CLOSED, not N/A"; st_fail=1; }

    # UNIVERSALITY — on an N/A'd tree the class and skill legs still refuse.
    # ⚠️ HONEST LABEL: these two legs are TAUTOLOGICAL as written, and review measured why —
    # check_class and check_skill contain ZERO references to LS_BOARDROOT, so setting it cannot
    # change their behaviour and these duplicate coverage that already exists above. Kept as a
    # REGRESSION GUARD in case a future change couples the board root into either function; they do
    # NOT establish "only the row leg is N/A'd" on their own. Do not cite them as proof of it.
    LS_BOARDROOT="$LS_FXDIR"
    check_skill "$LS_FX_NOSKILL" >/dev/null 2>&1 \
      && { echo "selftest FAIL: Kit-Skill must still apply on an N/A'd board tree"; st_fail=1; }
    check_class "$LS_FX_OK" "$_st_fxd/changed-controlplane.txt" >/dev/null 2>&1 \
      && { echo "selftest FAIL: Kit-Class must still apply on an N/A'd board tree"; st_fail=1; }

    LS_BOARDROOT="$_st_board_saved"

    # --- T7 (B9): Kit-Scope — the declared path set vs the measured changed set ----------------
    # Every leg runs against the fixture repo with the base PINNED, so none of them can be
    # satisfied (or falsified) by this tree's own branch topology.
    _st_scopebase_saved="$LS_SCOPE_BASEREF"
    LS_SCOPE_BASEREF="$LS_FX_SCOPEBASE"

    # POSITIVE — every changed path under the declared prefix passes.
    # ⚠️ rc IS NOT ENOUGH HERE, and that is measured: in observe mode (the default) an
    # always-UNCOVERED implementation also returns 0, so an rc-only positive would stay green while
    # the matcher never matched anything. The leg asserts the PASS DISCLOSURE, which only a real
    # match produces. An always-FAIL implementation breaks it from the other side.
    _st_scopeok=""
    _st_scopeok=$(check_scope "$LS_FX_SCOPE_IN" 2>&1) \
      || { echo "selftest FAIL: a change entirely inside the declared Kit-Scope must PASS"; st_fail=1; }
    case "$_st_scopeok" in
      *"PASS (every changed path is under a declared prefix)"*) ;;
      *) echo "selftest FAIL: a covered change must report the scope PASS (got: $_st_scopeok)"; st_fail=1 ;;
    esac

    # DIAL LIVENESS — the same covered change under enforce must still pass. Without this, an
    # enforce arm that refuses EVERYTHING would satisfy the negative below and be worse than useless.
    ( KIT_SCOPE_MODE=enforce; check_scope "$LS_FX_SCOPE_IN" ) >/dev/null 2>&1 \
      || { echo "selftest FAIL: a covered change must pass even under KIT_SCOPE_MODE=enforce"; st_fail=1; }

    # THE LOAD-BEARING NEGATIVE — an escaping path under the enforce dial must FAIL.
    # ⚠️ The dial is set in a SUBSHELL, never as `VAR=x check_scope ...`: a variable assignment on a
    # FUNCTION call PERSISTS after the call in dash/POSIX sh, which would silently leak `enforce`
    # into every leg below and invert the observe leg's meaning.
    ( KIT_SCOPE_MODE=enforce; check_scope "$LS_FX_SCOPE_OUT" ) >/dev/null 2>&1 \
      && { echo "selftest FAIL: an escaping path under KIT_SCOPE_MODE=enforce must FAIL"; st_fail=1; }

    # OBSERVE (the shipped default) — the SAME fixture must keep rc 0 AND name the escaping path.
    # Both halves matter: rc-only would pass for an implementation that never detected anything,
    # and print-only would pass for one that refused. This is the leg that pins observe-first.
    _st_scoperc=0
    _st_scopeout=$( ( unset KIT_SCOPE_MODE; check_scope "$LS_FX_SCOPE_OUT" ) 2>&1 >/dev/null ) || _st_scoperc=$?
    if [ "$_st_scoperc" -ne 0 ]; then
      echo "selftest FAIL: an escaping path in OBSERVE mode must not change rc (observe-first)"; st_fail=1
    fi
    case "$_st_scopeout" in
      *"conformance/stray.sh"*) ;;
      *) echo "selftest FAIL: OBSERVE mode must NAME each escaping path (got: $_st_scopeout)"; st_fail=1 ;;
    esac

    # ABSENT trailer — N/A, never red, and the N/A is ANNOUNCED. A silent N/A is how a gate ends up
    # asserting more than it verified.
    _st_scopena=""
    _st_scopena=$(check_scope "$LS_FX_OK" 2>&1) \
      || { echo "selftest FAIL: an absent Kit-Scope must be N/A, never a RED"; st_fail=1; }
    case "$_st_scopena" in
      *"N/A (no scope declared)"*) ;;
      *) echo "selftest FAIL: an absent Kit-Scope must DISCLOSE its N/A"; st_fail=1 ;;
    esac

    # UNRESOLVABLE BASIS — a base ref that does not exist yields the disclosed N/A, rc 0 (the
    # shallow-clone / fresh-adopter shape), never a red and never a silent pass.
    LS_SCOPE_BASEREF="refs/heads/no-such-base-ref"
    _st_scopena=$(check_scope "$LS_FX_SCOPE_OUT" 2>&1) \
      || { echo "selftest FAIL: an unresolvable scope basis must be N/A, never a RED"; st_fail=1; }
    case "$_st_scopena" in
      *"N/A (scope basis unresolvable)"*) ;;
      *) echo "selftest FAIL: an unresolvable scope basis must DISCLOSE its N/A"; st_fail=1 ;;
    esac
    LS_SCOPE_BASEREF="$LS_FX_SCOPEBASE"

    # HOSTILE TOKENS + the duplicate key — REASON-BOUND, not outcome-only: these must be the ONLY
    # refusals on the boundary side of the ladder, so the forbidden string is the escape-branch
    # message. MEASURED, so the claim is not overstated: with the hostile arm neutered these three
    # fixtures do not merely refuse for the wrong reason, they stop refusing at all (the escape
    # branch keeps rc 0 in observe mode) — the helper catches that as "expected a refusal, but the
    # check PASSED". The forbidden half is the guard for the day the dial flips to enforce.
    ls_assert_reason "scope token: traversal" "is not a plain path prefix" "fall outside the declared" \
      check_scope "$LS_FX_SCOPE_DOTDOT" || st_fail=1
    ls_assert_reason "scope token: glob metacharacter" "is not a plain path prefix" "fall outside the declared" \
      check_scope "$LS_FX_SCOPE_GLOB" || st_fail=1
    ls_assert_reason "scope token: absolute path" "is not a plain path prefix" "fall outside the declared" \
      check_scope "$LS_FX_SCOPE_ABS" || st_fail=1
    ls_assert_reason "scope duplicate key" "occurrences of 'Kit-Scope'" "is not a plain path prefix" \
      check_scope "$LS_FX_SCOPE_DUP" || st_fail=1

    LS_SCOPE_BASEREF="$_st_scopebase_saved"

    # --- MAP COMPLETENESS, drift directions (b) and (c) ---------------------------------------
    # Plan T1 step 4 required these and they were missing; review measured that gutting either
    # check left the suite GREEN. The code was right and nothing held it there.
    _st_conf_saved="$ROSTER_CONF"
    ROSTER_CONF="$LS_FXDIR/roster-ghost-skill.conf"
    map_completeness >/dev/null 2>&1 \
      && { echo "selftest FAIL: a map entry naming no skill on disk must FAIL"; st_fail=1; }
    ROSTER_CONF="$LS_FXDIR/roster-unmapped-stage.conf"
    map_completeness >/dev/null 2>&1 \
      && { echo "selftest FAIL: a stage in KIT_STAGES with no skill set must FAIL"; st_fail=1; }
    ROSTER_CONF="$_st_conf_saved"

    # --- REASON ASSERTIONS ---------------------------------------------------------------------
    # Review's 26-mutant single-mutation sweep measured FIVE legs passing for the WRONG reason: the
    # intended check could be neutered and a DIFFERENT check rejected the fixture, leaving the suite
    # green. An outcome-only leg structurally cannot catch that. These assert the REASON on stderr.
    # Third argument is the DOWNSTREAM reason that must NOT appear — see ls_assert_reason.
    ls_assert_reason "form rule (no skills/ prefix)" "must be of the form" "single path component" \
      check_skill "$LS_FX_BADFORM" || st_fail=1
    # ls_safe COVERAGE. The forbidden half is exactly the right instrument here: the ESC must not
    # survive into stderr. Replacing ls_safe with the identity function turns this leg RED — without
    # it the sanitiser was a security control with zero coverage.
    ls_assert_reason "form-error sanitises control chars" "must be of the form" "$(printf '\033')" \
      check_skill "$LS_FX_CTRL" || st_fail=1
    ls_assert_reason "single-component rule (traversal)" "single path component" "names no skill on disk" \
      check_skill "$LS_FX_TRAVERSAL" || st_fail=1
    ls_assert_reason "skill missing on disk" "names no skill on disk" "is not tracked" \
      check_skill "$LS_FX_NOSKILL" || st_fail=1
    ls_assert_reason "exactly-one occurrence" "occurrences of" "may contain only" \
      check_declaration "$LS_FX_DUP" || st_fail=1

    _st_skillrepo_saved2="$LS_SKILLREPO"
    LS_SKILLREPO="$LS_FXDIR"
    ls_assert_reason "symlink refusal (-L, not 'not tracked')" "is a symlink" "is not tracked" \
      check_skill "$LS_FX_SYMSKILL" || st_fail=1
    ls_assert_reason "untracked refusal" "is not tracked" "-" \
      check_skill "$LS_FX_UNTRACKED" || st_fail=1
    LS_SKILLREPO="$_st_skillrepo_saved2"

    # --- MAP FAIL-CLOSED (N2) ------------------------------------------------------------------
    # The header asserts "fails CLOSED on a missing or unreadable map" and nothing held it: review
    # measured both mutants surviving.
    # REASON-BOUND, not outcome-only. As first written these two were outcome-only and BOTH
    # survived their own mutants: neutering the empty-KIT_STAGES guard let drift-(a) reject the
    # fixture instead, and neutering the missing-map guard let the empty-KIT_STAGES guard reject it
    # — the exact "passed because a LATER check rejected the fixture" class, in legs added by the
    # same commit that introduced ls_assert_reason to close it.
    _st_conf_saved2="$ROSTER_CONF"
    ROSTER_CONF="$LS_FXDIR/roster-empty-stages.conf"
    ls_assert_reason "empty KIT_STAGES fails closed" "KIT_STAGES missing or empty" "absent from the map" \
      map_completeness || st_fail=1
    ROSTER_CONF="$LS_FXDIR/no-such-map.conf"
    ls_assert_reason "missing map fails closed" "map not found" "KIT_STAGES missing or empty" \
      map_completeness || st_fail=1
    ROSTER_CONF="$_st_conf_saved2"

    # --- CONTROL-PLANE POSITIVE ----------------------------------------------------------------
    # declared == derived == control-plane must PASS. This is the class where a false-RED is most
    # expensive and the only one of the three with no positive leg until now.
    check_class "$LS_FX_CPOK" "$_st_fxd/changed-controlplane.txt" >/dev/null 2>&1 \
      || { echo "selftest FAIL: declared control-plane == derived control-plane must PASS"; st_fail=1; }

    LS_REPO="$_st_repo_saved"
    ls_fx_cleanup
  fi

  if [ "$st_fail" -ne 0 ]; then echo "loop-state --selftest: FAIL" >&2; return 1; fi
  echo "loop-state --selftest: OK"
  echo "  map        — positive; drift (a) skill-absent, (b) entry-with-no-skill, (c) unmapped-stage;"
  echo "               fail-closed on an empty KIT_STAGES and on a missing map"
  echo "  declaration— positives: conformant, single-key; negatives: no-decl, ancestor-only,"
  echo "               severed-block, bad-stage, duplicate-key, metachar-row"
  echo "  class      — positives: ordinary, control-plane; negatives: under-declared, over-declared"
  echo "  skill      — positives: real tree, fixture tree; negatives: stage-inappropriate,"
  echo "               nonexistent, traversal, tracked-symlink, untracked"
  echo "  row        — positive; negative; N/A routes: no-board, non-md backend, pristine template;"
  echo "               fail-closed on an unrecognised backend"
  echo "  scope      — positive (covered); negatives: escaping-path under enforce, duplicate key,"
  echo "               hostile tokens (traversal, glob metachar, absolute); observe keeps rc 0 and"
  echo "               NAMES the escaping path; N/A routes: no declaration, unresolvable basis"
  echo "  reasons    — 12 legs assert the refusal REASON (and the absence of the downstream reason),"
  echo "               so a leg cannot pass because a LATER check rejected the fixture"
  echo "  meta       — the reason-assertion helper is itself checked against 5 synthetic subjects,"
  echo "               because it is structurally invisible to the CI mutation sweep"
  return 0
}

# ls_assert_reason — assert a check FAILS *for the stated reason*, not merely that it fails.
#
# Defined BELOW the selftest() marker on purpose: the CI non-vacuity sweep mutates only lines
# BEFORE that marker, so a kill-assertion helper defined above it could itself be neutered and the
# whole suite would go vacuously green. (Banked: writing-conformance-check-selftests.)
ls_assert_reason() {   # $1 = label, $2 = expected substring, $3 = forbidden substring (or -), $4... = cmd
  _lar_label="$1"; _lar_pat="$2"; _lar_not="$3"; shift 3
  if _lar_err=$("$@" 2>&1 >/dev/null); then
    echo "selftest FAIL: $_lar_label — expected a refusal, but the check PASSED"
    return 1
  fi
  case "$_lar_err" in
    *"$_lar_pat"*) ;;
    *) echo "selftest FAIL: $_lar_label — refused for the WRONG reason."
       echo "  wanted stderr containing: $_lar_pat"
       echo "  got: $_lar_err"
       return 1 ;;
  esac
  # THE FORBIDDEN HALF closes a measured gaming vector: keep a branch's `echo` but drop its
  # `return 1`, and the refusal comes from a LATER check while the wanted string still appears —
  # the suite goes green with the named branch inert. A correct implementation returns at its own
  # branch, so the downstream reason NEVER appears; the mutant emits both.
  # ⚠️ NOT TAUTOLOGICAL — a mutant in which the forbidden string IS present was measured before
  # this assertion was written (the DRIFT-2b trap: a green `assert_lacks` can be vacuous).
  [ "$_lar_not" = "-" ] && return 0
  case "$_lar_err" in
    *"$_lar_not"*)
      echo "selftest FAIL: $_lar_label — the named branch did not cause the refusal."
      echo "  stderr also contains the DOWNSTREAM reason: $_lar_not"
      echo "  got: $_lar_err"
      return 1 ;;
  esac
  return 0
}

# ls_assert_reason_selfcheck — COVERAGE FOR THE COVERAGE MECHANISM.
#
# EIGHT legs depend on ls_assert_reason. Measured: it can be broken three ways and the entire suite
# still goes GREEN — make it always return 0, drop the forbidden half, or change `2>&1 >/dev/null`
# to `2>&1` so stdout is silently credited. That is a single point of failure with ZERO coverage,
# and the cause is structural: the helper sits below the selftest() marker so `non-vacuity.sh` will
# not neuter it — which also means the CI sweep cannot CHECK it.
#
# So the helper is exercised against synthetic commands whose behaviour is known. This passes on the
# as-shipped helper (every one of the five behaviours verified correct today) — it is a REGRESSION
# guard, not a fix for a live defect.
ls_assert_reason_selfcheck() {
  _lsc_fail=0
  # Synthetic subjects. Deliberately trivial so the only thing under test is the helper.
  # shellcheck disable=SC2329 # invoked indirectly — passed to ls_assert_reason and run as "$@"
  _sc_right()    { echo "the wanted reason" >&2; return 1; }
  # shellcheck disable=SC2329
  _sc_norefuse() { echo "the wanted reason" >&2; return 0; }
  # shellcheck disable=SC2329
  _sc_wrong()    { echo "some other reason" >&2; return 1; }
  # shellcheck disable=SC2329
  _sc_forbidden(){ echo "the wanted reason" >&2; echo "the downstream reason" >&2; return 1; }
  # shellcheck disable=SC2329
  _sc_stdout()   { echo "the wanted reason";     return 1; }

  ls_assert_reason "meta/right" "the wanted reason" "the downstream reason" _sc_right >/dev/null 2>&1 \
    || { echo "selftest FAIL: meta — a correct refusal must PASS the helper"; _lsc_fail=1; }
  ls_assert_reason "meta/norefuse" "the wanted reason" "-" _sc_norefuse >/dev/null 2>&1 \
    && { echo "selftest FAIL: meta — rc=0 must FAIL the helper (helper always-pass?)"; _lsc_fail=1; }
  ls_assert_reason "meta/wrong" "the wanted reason" "-" _sc_wrong >/dev/null 2>&1 \
    && { echo "selftest FAIL: meta — a WRONG reason must FAIL the helper"; _lsc_fail=1; }
  ls_assert_reason "meta/forbidden" "the wanted reason" "the downstream reason" _sc_forbidden >/dev/null 2>&1 \
    && { echo "selftest FAIL: meta — a present FORBIDDEN reason must FAIL (forbidden half dropped?)"; _lsc_fail=1; }
  # The subtle one: if the redirect order is flipped, stdout gets credited as a reason.
  ls_assert_reason "meta/stdout" "the wanted reason" "-" _sc_stdout >/dev/null 2>&1 \
    && { echo "selftest FAIL: meta — a reason on STDOUT must NOT be credited (2>&1 >/dev/null flipped?)"; _lsc_fail=1; }
  return "$_lsc_fail"
}

# run_gate — the whole floor against ONE commit. Every leg runs so the author sees every problem
# in one CI round rather than peeling them off one per push.
run_gate() {   # $1 = sha
  _ls_bad=0
  git -C "$LS_REPO" cat-file -e "$1^{commit}" 2>/dev/null || {
    echo "loop-state: '$1' is not a commit in this repository" >&2; return 2; }
  map_completeness   || _ls_bad=1
  check_declaration "$1" || _ls_bad=1
  check_class       "$1" || _ls_bad=1
  check_skill       "$1" || _ls_bad=1
  check_row         "$1" || _ls_bad=1
  # B9: the scope leg. It runs inside the existing --head path, so the installed pre-push hook and
  # CI's bound gate both get it with ZERO wiring edits. It cannot change the rc of any commit that
  # carries no Kit-Scope trailer (the N/A arm), which is every PR shape that is green today.
  check_scope       "$1" || _ls_bad=1
  if [ "$_ls_bad" -ne 0 ]; then
    echo "loop-state: FAIL — $1 does not carry a valid Entry Declaration." >&2
    echo "  The contract is CLAUDE.md section 1. Trailers must be the LAST paragraph of the commit" >&2
    echo "  message and CONTIGUOUS: a blank line before Co-Authored-By silently drops every Kit-* field." >&2
    return 1
  fi
  # The success line states EXACTLY what each leg established — never "all resolve". Security review
  # blocked an earlier version for printing "row, stage, class, skill all resolve" on a change whose
  # row was a single letter, or whose row leg never ran at all. A merge-blocking control that
  # overstates its own result is the failure this whole slice exists to prevent.
  echo "OK: loop-state — $1 carries a valid Entry Declaration."
  echo "  stage + skill: resolved against the map · class: equals promotion-readiness --class"
  echo "                 (guard-core scope; the adapter union is enforced by ratification.yml)"
  echo "  row:           $LS_ROW_STATE"
  echo "  scope:         $LS_SCOPE_STATE"
  echo "                 (declaration<->diff consistency at THIS push; no ordering claim)"
  return 0
}

# --- dispatch ---
case "${1:-}" in
  --selftest) selftest; exit $? ;;
  # NEVER defaults to HEAD. On pull_request, actions/checkout checks out refs/pull/N/merge —
  # GitHub's ephemeral merge commit, whose message carries NO trailers. A gate built on HEAD would
  # either false-RED every PR or get "fixed" into walking back until a trailer is found, at which
  # point ANY ancestor satisfies it (design section 3.1, Security C2 — CRITICAL).
  --head)     [ $# -ge 2 ] || { echo "loop-state: --head needs a SHA" >&2; exit 2; }
              run_gate "$2"; exit $? ;;
  *)          echo "loop-state: --head <sha> or --selftest required (never defaults to HEAD)" >&2
              exit 2 ;;
esac
