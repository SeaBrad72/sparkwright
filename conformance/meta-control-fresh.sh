#!/bin/sh
# meta-control-fresh.sh — M2 freshness gate: the cadenced meta-control circuit-breaker.
#
# The meta-control panel (docs/kit-internals/meta-control.md; the shipped operator procedure is
# docs/enterprise/meta-control.md) is the kit's institutional, adversarial
# go/no-go — the control that catches direction / proportion / over-claim drift. M1 productized it;
# M2 ENFORCES its cadence so it can't be "designed but never run". This check answers, mechanically:
# "is a meta-control panel OVERDUE?" — DUE once more than N release tags have landed since the last
# addressed run (a real run OR a logged, dated deferral).
#
# APPLICABILITY is keyed on a DETECTED TRIGGER, never on a declared mode (conformance/
# mode-enforcement-blind.sh forbids any gate reading the process mode — a mode may NEVER weaken an
# applicable control). The control applies when a project actually PRACTICES the cadence — its
# verdict log / state marker exist — or when this is the kit's own repo. Absent both → N/A (not
# applicable; not weakened). So a solo/vibe-coder who never adopted the cadence is never nagged, while
# an agentic squad that keeps the log is held to it at full strength — one gate, posture-proportionate
# via applicability.
#
# Enforcement placement: this runs in the WEEKLY drift-watch (a non-zero fails that job — the loud
# circuit-breaker) and as an ADVISORY doctor metric. Per-PR CI runs only `--selftest` (mechanism +
# sync), NOT the live freshness verdict — so an overdue kit never blocks unrelated PRs; it surfaces
# weekly until a human runs the panel or logs a deferral.
#
# TIERS (H1, PHASE-B-HYGIENE): OVERDUE (N < count <= 2N) is the advisory grace band — weekly-loud,
# never tag-blocking. ESCALATED (count > 2N) is the tier the release flow cannot silently pass:
# scripts/release-tag.sh's cadence_gate refuses the tag until a panel run or a dated human-ratified
# DEFERRED row advances the marker. Consumers key on the ^OVERDUE:/^ESCALATED: verdict-token prefix;
# rc is 1 for both (same failure class).
#
#   sh conformance/meta-control-fresh.sh [--selftest]
#   env: META_CONTROL_N (default 5) · META_CONTROL_ROOT (default .) · META_CONTROL_TAGS (test hook)
# Exit: 0 = FRESH or N/A · 1 = OVERDUE / ESCALATED / invalid-state / desync · 2 = usage. POSIX sh; dash-clean.
set -eu
_here=$(CDPATH='' cd "$(dirname "$0")" && pwd)
. "$_here/version-helpers.sh"
. "$_here/backlog-lib.sh"
cd "$_here/.."
ROOT="${META_CONTROL_ROOT:-.}"
N="${META_CONTROL_N:-5}"
LOG="docs/governance/meta-control-log.md"
MARKER="docs/governance/.meta-control-last"

MVER=""; MVERDICT=""   # set by validate_state

# is_kit — DETECTED trigger (un-spoofable: golden-path.yml is control-plane + export-ignored). Mirrors
# the OR-of-markers kit-self detector in adopter-export-wired.sh. NOT a declared-mode read.
is_kit() {
  [ -f "$ROOT/docs/ROADMAP-KIT.md" ] || [ -f "$ROOT/.github/workflows/golden-path.yml" ]
}

# tags_list — normalized (v-stripped) X.Y.Z release tags, one per line. META_CONTROL_TAGS overrides
# for the selftest (so freshness logic is testable without a fixture git repo).
tags_list() {
  if [ -n "${META_CONTROL_TAGS:-}" ]; then printf '%s\n' "$META_CONTROL_TAGS" | tr ' ' '\n'; return; fi
  ( cd "$ROOT" && git tag -l 2>/dev/null ) | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | sed 's/^v//'
}

# count_newer <marker_ver> — number of release tags strictly greater (semver) than the marker version.
count_newer() {
  _m=$1; _c=0
  for _t in $(tags_list); do
    [ -z "$_t" ] && continue
    [ "$_t" = "$_m" ] && continue
    if ver_gt "$_t" "$_m"; then
      _c=$((_c + 1))
    fi
  done
  printf '%s' "$_c"
}

# header_row — the log's header row text (the `| Date | Version | ... |` line), or empty if absent.
# Used as the column-count REFERENCE for trailing_deferred's fail-closed arity check (M-1).
header_row() {
  awk -F'|' '
    /^[ \t]*\|/ {
      t=$2; gsub(/^[ \t]+|[ \t]+$/,"",t)
      if (t=="Date") { print; exit }
    }
  ' "$ROOT/$LOG" 2>/dev/null
}

# log_field <awk-index> — trimmed value of a column from the log's LAST data row (skips header +
# separator). Signature is unchanged (RAW awk-split index: a[1]="" so Version=a[3], Verdict=a[6]) so
# callers don't move; internally it selects the last data row with a plain `|`-scan (that scan never
# touches cell CONTENT, only counts header/separator lines, so an escaped `\|` can't confuse it), then
# hands the row to backlog-lib.sh's cell() — the shared GFM-exact parser (BOARD-PIPE-ESCAPE T3) — which
# is 1-based over REAL columns. raw a[idx] == cell(idx-1): idx=3 (Version) -> cell 2, idx=6 (Verdict)
# -> cell 5. cell() prints nothing (rc 0, empty stdout) for an out-of-range index — a read past the
# row's real column count fails CLOSED here because callers compare the result, never trust its
# presence (see validate_state's desync check, §6.2 leg 7).
log_field() {
  _lf_last=$(awk -F'|' '
    /^[ \t]*\|/ {
      t=$2; gsub(/^[ \t]+|[ \t]+$/,"",t)
      if (t=="Date") next                       # header row
      if ($0 ~ /^[ \t]*\|[ \t:|-]+$/) next      # separator row (dashes/colons only)
      last=$0
    }
    END { print last }
  ' "$ROOT/$LOG")
  [ -n "$_lf_last" ] || return 1
  cell "$_lf_last" $(($1 - 1))
}

# applicability — 0 = applies, 3 = N/A (cadence not adopted on an adopter tree).
applicability() {
  is_kit && return 0
  { [ -f "$ROOT/$MARKER" ] || [ -f "$ROOT/$LOG" ]; } && return 0
  return 3
}

# (b) verdict normalization: uppercase-normalize so case differences between marker and log don't
# false-desync, and so a lowercase `deferred` normalizes consistently (the actual serial-cap evasion
# fix lives in trailing_deferred's toupper). The verdict VOCABULARY is OPEN-ENDED (GO-WITH-CONDITIONS,
# profile-specific verdicts like KEEP-BIASED, ...) — we deliberately do NOT restrict it to a fixed
# enum, which would reject the kit's own legitimate richer verdicts.
norm_verdict() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

# validate_state — marker+log present, marker parseable, marker == log's last row. Prints FAIL
# reason; returns 0/1. Sets MVER, MVERDICT. (Structural / time-invariant — safe for per-PR selftest.)
validate_state() {
  if [ ! -f "$ROOT/$MARKER" ]; then
    echo "FAIL: meta-control cadence is active but the state marker is missing ($MARKER). Run the panel (docs/enterprise/meta-control.md) or log a dated DEFERRED row, then write the marker."
    return 1
  fi
  if [ ! -f "$ROOT/$LOG" ]; then
    echo "FAIL: marker present but the verdict log is missing ($LOG)."
    return 1
  fi
  _mline=$(head -n 1 "$ROOT/$MARKER" 2>/dev/null || true)
  MVER=$(printf '%s' "$_mline" | awk '{print $1}')
  MVERDICT=$(printf '%s' "$_mline" | awk '{print $2}')
  MVER=$(ver_norm "$MVER")
  if ! printf '%s' "$MVER" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "FAIL: marker version unparseable ($MARKER first field = '$MVER'; expected X.Y.Z VERDICT)."
    return 1
  fi
  if [ -z "$MVERDICT" ]; then
    echo "FAIL: marker verdict missing ($MARKER must be 'VERSION VERDICT')."
    return 1
  fi
  # (a, trimmed) Two checks, both DEFENSE-IN-DEPTH only — the real guarantee is the marker's
  # control-plane status (the guard denies agent writes; see docs/kit-internals/meta-control.md).
  #  i. marker must not be AHEAD of VERSION (rejects a fabricated 99.0.0 future-pin).
  # ii. marker must correspond to a real release point: an existing semver tag OR exactly == VERSION
  #     (the unreleased ship-seam). Rejects a plausible-but-fabricated in-between marker that (i) alone
  #     would accept. Enforced only when an anchor exists (VERSION present); lenient otherwise so an
  #     adopter who versions differently is not over-constrained.
  #     The real-tag arm (ii) is ALSO skipped when no tags are visible — CI checkouts often omit tags
  #     (actions/checkout fetches none by default), and requiring them would false-FAIL a legitimate
  #     marker that IS a real released tag. Lenient-when-tagless; defense-in-depth, not a boundary.
  if [ -f "$ROOT/VERSION" ]; then
    _vraw=$(ver_norm "$(tr -d '[:space:]' < "$ROOT/VERSION" 2>/dev/null || true)")
    if printf '%s' "$_vraw" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
      if ver_gt "$MVER" "$_vraw"; then
        echo "FAIL: marker version $MVER is ahead of VERSION $_vraw — a future-pinned marker would pin the gate FRESH forever. Set the marker to a real run's version (<= VERSION)."
        return 1
      fi
      _is_tag=0
      for _t in $(tags_list); do [ "$_t" = "$MVER" ] && { _is_tag=1; break; }; done
      if [ -n "$(tags_list | head -1)" ] && [ "$_is_tag" = "0" ] && [ "$MVER" != "$_vraw" ]; then
        echo "FAIL: marker $MVER is neither a released tag nor == VERSION $_vraw — the marker must correspond to a real release point or the current ship-seam version."
        return 1
      fi
    fi
  fi
  _lver=$(log_field 3) || { echo "FAIL: cannot parse a data row from $LOG."; return 1; }
  _lverdict=$(log_field 6)
  _lver=$(ver_norm "$_lver")
  MVERDICT=$(norm_verdict "$MVERDICT"); _lverdict=$(norm_verdict "$_lverdict")
  if [ "$MVER" != "$_lver" ] || [ "$MVERDICT" != "$_lverdict" ]; then
    _lver_s=$(printf '%s' "$_lver" | tr -d '[:cntrl:]' | cut -c1-80)
    _lverdict_s=$(printf '%s' "$_lverdict" | tr -d '[:cntrl:]' | cut -c1-80)
    echo "FAIL: marker/log desync — marker='$MVER $MVERDICT' but log's last row='$_lver_s $_lverdict_s'. The two must advance together (update $MARKER whenever you append to $LOG)."
    return 1
  fi
  return 0
}

# trailing_deferred — count consecutive DEFERRED verdicts from the END of the log (the serial-defer
# cap). The row-selection scan below only counts header/separator lines by structure (never reads
# cell CONTENT), so it stays correct regardless of escaped pipes inside a row; each selected row's
# Verdict is then read via backlog-lib.sh's cell() (cell column 5 = raw awk a[6], the same mapping as
# log_field) instead of a raw `$6` split — the raw split let an earlier `\|` in a row shift $6 onto
# the wrong column, silently reading a non-DEFERRED value and evading the serial-defer cap (C7,
# BOARD-PIPE-ESCAPE §6.1 leg 6).
#
# M-1 (the leg-6 TWIN, BOARD-PIPE-ESCAPE fix round): leg 6 closed the ESCAPED-pipe vector, but an
# earlier row that is MALFORMED under the shared GFM parser — a RAW (unescaped) `|` in Trigger/Profile
# (which genuinely adds a GFM column, so cell(row,5) reads the wrong field), or a truncated short row
# (fewer real columns, column 5 empty) — was still read positionally and, on a non-DEFERRED-looking
# result, hit the `else break` and silently RESET the streak as if it were a clean addressed verdict.
# Fail CLOSED instead: a row whose real column count (gfm_nf) differs from the header's, or whose
# Verdict cell reads empty, is treated as streak-CONTINUING (DEFERRED-equivalent) rather than
# streak-resetting. Chosen over a separate "unparseable" sentinel/FAIL because freshness's only
# consumption of this count is the numeric cap comparison (`_trail -ge _defcap`) — widening the
# contract to a new token would touch freshness's message contract and every caller for a case whose
# correct remedy is identical to a real cap trip (a required panel run); counting it in is the
# minimal, most robust fix consistent with existing consumption.
trailing_deferred() {
  _td_hdr=$(header_row)
  _td_hdr_nf=$(gfm_nf "$_td_hdr")
  # Select data rows bottom-to-top by STRUCTURE only (header/separator skip — never reads cell
  # content), then walk them one per line via `while IFS= read -r` (the safe idiom; no IFS=newline
  # + set -f + word-split, which semgrep bash.lang.security.ifs-tampering flags).
  _td_c=0
  while IFS= read -r _td_row; do
    [ -n "$_td_row" ] || continue
    _td_nf=$(gfm_nf "$_td_row")
    _td_vraw=$(cell "$_td_row" 5)
    if [ "$_td_nf" != "$_td_hdr_nf" ] || [ -z "$_td_vraw" ]; then
      # malformed for this read (arity mismatch or empty Verdict cell) — fail closed: count it as
      # streak-continuing rather than trusting a positionally-misaligned non-DEFERRED read (M-1).
      _td_c=$((_td_c + 1)); continue
    fi
    _td_v=$(norm_verdict "$_td_vraw")
    if [ "$_td_v" = "DEFERRED" ]; then _td_c=$((_td_c + 1)); else break; fi
  done <<EOF
$(awk -F'|' '
    /^[ \t]*\|/ {
      t=$2; gsub(/^[ \t]+|[ \t]+$/,"",t)
      if (t=="Date") next
      if ($0 ~ /^[ \t]*\|[ \t:|-]+$/) next
      rows[++n]=$0
    }
    END { for (i=n;i>=1;i--) print rows[i] }
  ' "$ROOT/$LOG" 2>/dev/null)
EOF
  printf '%s\n' "$_td_c"
}

# freshness — prints FRESH/OVERDUE/ESCALATED; returns 0/1. Uses MVER (set by validate_state).
freshness() {
  # M2-S5: serial-deferral cap — a deferral covers ONE cadence, but >=N consecutive DEFERRED rows force
  # a real run (you cannot defer forever). Independent of the tag count.
  _defcap="${META_CONTROL_DEFER_CAP:-2}"
  _trail=$(trailing_deferred)
  _cnt=$(count_newer "$MVER")
  # H1 (PHASE-B-HYGIENE / MC-CADENCE-1): the ESCALATED tier. count > 2N means the advisory OVERDUE
  # band (N < count <= 2N) was consumed with NO recorded cadence decision — the measured third-instance
  # failure: OVERDUE fired 2026-08-03 and six releases shipped over it in four days, because the only
  # consumer was a weekly advisory job nobody reads. ESCALATED is the tier the release flow cannot
  # silently pass: scripts/release-tag.sh's cadence_gate refuses to tag while it holds. rc stays 1
  # (same failure class); the TOKEN is the contract — consumers key on the ^ESCALATED:/^OVERDUE: prefix.
  # Deliberately COUNT-keyed only, and checked BEFORE the serial-defer cap:
  #   · the cap keeps its own OVERDUE arm and never escalates by itself (its remedy differs — a REAL
  #     run; a cap-fired OVERDUE at count <= 2N stays in the advisory band), but
  #   · a count past 2N escalates REGARDLESS of the cap, else the tag gate could be held advisory
  #     forever by stale trailing deferrals whose marker never advances.
  # Pure tag arithmetic — no new state file, no time input (the detector's native clock is tags).
  if [ "$_cnt" -gt $((2 * N)) ]; then
    echo "ESCALATED: $_cnt release tags since the last addressed meta-control panel ($MVER, $MVERDICT; N=$N, grace 2N=$((2 * N)) exhausted)."
    echo "  -> The advisory OVERDUE band passed with no recorded cadence decision. Run the light 5-lens panel per"
    echo "     docs/enterprise/meta-control.md, or record a dated human-ratified DEFERRED row; either appends a row to"
    echo "     $LOG and advances $MARKER, which un-escalates by construction."
    echo "     scripts/release-tag.sh REFUSES to tag while this state holds."
    return 1
  fi
  if [ "${_trail:-0}" -ge "$_defcap" ]; then
    echo "OVERDUE: $_trail consecutive DEFERRED rows (cap $_defcap) — a real meta-control panel run is now required; serial deferral is not permitted."
    return 1
  fi
  if [ "$_cnt" -gt "$N" ]; then
    echo "OVERDUE: $_cnt release tags since the last addressed meta-control panel ($MVER, $MVERDICT; N=$N)."
    echo "  -> Run the light 5-lens panel per docs/enterprise/meta-control.md (or log a dated DEFERRED row with a reason),"
    echo "     append a row to $LOG, and set $MARKER to the current version. Greens once within $N tags of HEAD."
    return 1
  fi
  echo "FRESH: $_cnt release tags since the last meta-control panel ($MVER, $MVERDICT; threshold N=$N)."
  return 0
}

run() {
  if ! applicability; then
    echo "meta-control-fresh: N/A — cadence not adopted (no $MARKER / $LOG). The freshness gate applies once a project runs the meta-control panel and records it."
    return 0
  fi
  validate_state || return 1
  freshness
}

# --------------------------------------------------------------------------- selftest
if [ "${1:-}" = "--selftest" ]; then
  sfail=0
  _t=$(mktemp -d)
  # (the declared-process-mode prohibition is enforced by conformance/mode-enforcement-blind.sh across
  #  the whole enforcement surface — no redundant, self-matching self-grep here.)

  # real tree: structural only (applies + sync). NEVER assert the live freshness verdict here — that
  # would self-block every PR the moment the kit is legitimately overdue. Freshness is drift-watch's job.
  if applicability; then
    if validate_state >/dev/null 2>&1; then echo "PASS: real tree applies + marker/log in sync"
    else echo "meta-control-fresh --selftest: FAIL (real tree applies but state invalid/desynced)"; sfail=1; fi
  else
    echo "PASS: real tree N/A (cadence not adopted)"
  fi

  # wiring: on the KIT, the gate must be wired into the (maintainer-only, export-ignored) drift-watch
  # workflow — that is the enforcement point. An adopter tree doesn't ship drift-watch, so that
  # assertion is N/A there (gating it on is_kit keeps the claim passing on the exported tree). doctor.sh
  # ships to adopters, so its advisory-surfacing wiring is asserted on every tree.
  _wf="$ROOT/.github/workflows/drift-watch.yml"
  if is_kit; then
    if [ -f "$_wf" ] && grep -q 'conformance/meta-control-fresh.sh' "$_wf"; then echo "PASS: wired into drift-watch"
    else echo "meta-control-fresh --selftest: FAIL (kit: not wired into drift-watch.yml)"; sfail=1; fi
  else
    echo "PASS: drift-watch wiring N/A (adopter tree — maintainer-only workflow not shipped)"
  fi
  if [ -f "$ROOT/scripts/doctor.sh" ] && grep -q 'conformance/meta-control-fresh.sh' "$ROOT/scripts/doctor.sh"; then echo "PASS: surfaced by doctor"
  else echo "meta-control-fresh --selftest: FAIL (not surfaced by scripts/doctor.sh)"; sfail=1; fi

  # fixture helpers: build a ROOT with a kit marker, a marker file, and a minimal valid log.
  _mkfix() { # <dir> <marker-line> <log-version> <log-verdict> [VERSION=99.99.99]
    mkdir -p "$1/docs/governance"
    : > "$1/docs/ROADMAP-KIT.md"                       # make is_kit true (applies)
    printf '%s\n' "${5:-99.99.99}" > "$1/VERSION"     # M2-S5: satisfy the marker<=VERSION check
    printf '%s\n' "$2" > "$1/docs/governance/.meta-control-last"
    {
      printf '| Date | Version | Trigger | Profile | Verdict | Artifact | Ledger |\n'
      printf '|------|---------|---------|---------|---------|----------|--------|\n'
      printf '| 2026-01-01 | %s | t | light | %s | a | s |\n' "$3" "$4"
    } > "$1/docs/governance/meta-control-log.md"
  }
  _expect() { # <label> <expected-rc> <actual-rc>
    if [ "$2" = "$3" ]; then echo "PASS: selftest fixture — $1"
    else echo "meta-control-fresh --selftest: FAIL ($1: expected rc $2, got $3)"; sfail=1; fi
  }

  # A. adopter, no state → N/A (rc 0)
  _d="$_t/a"; mkdir -p "$_d/docs"; rc=0; ( ROOT="$_d"; META_CONTROL_TAGS="9.9.9" run ) >/dev/null 2>&1 || rc=$?; _expect "adopter no-state = N/A" 0 "$rc"
  # B. kit + marker missing → FAIL (rc 1) fail-closed
  _d="$_t/b"; mkdir -p "$_d/docs"; : > "$_d/docs/ROADMAP-KIT.md"; rc=0; ( ROOT="$_d"; run ) >/dev/null 2>&1 || rc=$?; _expect "kit + no marker = FAIL" 1 "$rc"
  # C. synced, 2 newer tags (<=N) → FRESH (rc 0)
  _d="$_t/c"; _mkfix "$_d" "1.0.0 GO" "1.0.0" "GO"; rc=0; ( ROOT="$_d"; META_CONTROL_TAGS="1.0.0 1.0.1 1.0.2" run ) >/dev/null 2>&1 || rc=$?; _expect "synced + 2 newer = FRESH" 0 "$rc"
  # D. synced, 8 newer tags (>N) → OVERDUE (rc 1)
  _d="$_t/d"; _mkfix "$_d" "1.0.0 GO" "1.0.0" "GO"; rc=0; ( ROOT="$_d"; META_CONTROL_TAGS="1.0.0 1.0.1 1.0.2 1.0.3 1.0.4 1.0.5 1.0.6 1.0.7 1.0.8" run ) >/dev/null 2>&1 || rc=$?; _expect "synced + 8 newer = OVERDUE" 1 "$rc"
  # E. desync (marker 1.0.0 GO vs log 1.0.1 GO) → FAIL (rc 1)
  _d="$_t/e"; _mkfix "$_d" "1.0.0 GO" "1.0.1" "GO"; rc=0; ( ROOT="$_d"; META_CONTROL_TAGS="1.0.0" run ) >/dev/null 2>&1 || rc=$?; _expect "desync marker!=log = FAIL" 1 "$rc"
  # F. unparseable marker → FAIL (rc 1)
  _d="$_t/f"; _mkfix "$_d" "not-a-version" "1.0.0" "GO"; rc=0; ( ROOT="$_d"; META_CONTROL_TAGS="1.0.0" run ) >/dev/null 2>&1 || rc=$?; _expect "unparseable marker = FAIL" 1 "$rc"
  # G. DEFERRED counts as addressed (synced, 0 newer) → FRESH (rc 0)
  _d="$_t/g"; _mkfix "$_d" "1.0.0 DEFERRED" "1.0.0" "DEFERRED"; rc=0; ( ROOT="$_d"; META_CONTROL_TAGS="1.0.0" run ) >/dev/null 2>&1 || rc=$?; _expect "DEFERRED synced = FRESH" 0 "$rc"
  # H. exactly N newer → FRESH (boundary: DUE is strictly > N)
  _d="$_t/h"; _mkfix "$_d" "1.0.0 GO" "1.0.0" "GO"; rc=0; ( ROOT="$_d"; META_CONTROL_TAGS="1.0.0 1.0.1 1.0.2 1.0.3 1.0.4 1.0.5" run ) >/dev/null 2>&1 || rc=$?; _expect "exactly N=5 newer = FRESH (boundary)" 0 "$rc"
  # I. REAL git-tag path (NO META_CONTROL_TAGS hook) — exercises tags_list's live
  #    `git tag -l | grep X.Y.Z | sed | sort -V` pipeline + count_newer, the path drift-watch runs.
  #    A non-semver tag must be ignored; the strict >N boundary must hold off the real list.
  _d="$_t/i"; _mkfix "$_d" "1.0.0 GO" "1.0.0" "GO"
  ( cd "$_d" && git init -q && git -c user.email=c@k -c user.name=c commit -q --allow-empty -m s >/dev/null 2>&1 \
    && for _tg in v1.0.0 v1.0.1 v1.0.2 nightly; do git tag "$_tg" >/dev/null 2>&1 || true; done )
  rc=0; ( ROOT="$_d"; run ) >/dev/null 2>&1 || rc=$?; _expect "real git-tag path: 2 newer (non-semver ignored) = FRESH" 0 "$rc"
  ( cd "$_d" && for _tg in v1.0.3 v1.0.4 v1.0.5 v1.0.6; do git tag "$_tg" >/dev/null 2>&1 || true; done )
  rc=0; ( ROOT="$_d"; run ) >/dev/null 2>&1 || rc=$?; _expect "real git-tag path: 6 newer = OVERDUE" 1 "$rc"
  # J. M2-S5 future-pinned marker (MVER 9.9.9 > VERSION 1.0.0) → FAIL
  _d="$_t/j"; _mkfix "$_d" "9.9.9 GO" "9.9.9" "GO" "1.0.0"; rc=0; ( ROOT="$_d"; META_CONTROL_TAGS="1.0.0" run ) >/dev/null 2>&1 || rc=$?; _expect "future-pinned marker (>VERSION) = FAIL" 1 "$rc"
  # K. M2-S5 two consecutive DEFERRED → OVERDUE (serial-defer cap), regardless of tag count
  _d="$_t/k"; mkdir -p "$_d/docs/governance"; : > "$_d/docs/ROADMAP-KIT.md"; printf '99.99.99\n' > "$_d/VERSION"
  printf '1.0.0 DEFERRED\n' > "$_d/docs/governance/.meta-control-last"
  { printf '| Date | Version | Trigger | Profile | Verdict | Artifact | Ledger |\n'; printf '|---|---|---|---|---|---|---|\n'; printf '| 2026-01-01 | 0.9.0 | t | l | DEFERRED | a | s |\n'; printf '| 2026-01-02 | 1.0.0 | t | l | DEFERRED | a | s |\n'; } > "$_d/docs/governance/meta-control-log.md"
  rc=0; ( ROOT="$_d"; META_CONTROL_TAGS="1.0.0" run ) >/dev/null 2>&1 || rc=$?; _expect "2 consecutive DEFERRED = OVERDUE (serial-defer cap)" 1 "$rc"
  # L. M2-S5 single trailing DEFERRED (prior row a real verdict) → still FRESH (one deferral allowed)
  _d="$_t/l"; mkdir -p "$_d/docs/governance"; : > "$_d/docs/ROADMAP-KIT.md"; printf '99.99.99\n' > "$_d/VERSION"
  printf '1.0.0 DEFERRED\n' > "$_d/docs/governance/.meta-control-last"
  { printf '| Date | Version | Trigger | Profile | Verdict | Artifact | Ledger |\n'; printf '|---|---|---|---|---|---|---|\n'; printf '| 2026-01-01 | 0.9.0 | t | l | GO | a | s |\n'; printf '| 2026-01-02 | 1.0.0 | t | l | DEFERRED | a | s |\n'; } > "$_d/docs/governance/meta-control-log.md"
  rc=0; ( ROOT="$_d"; META_CONTROL_TAGS="1.0.0" run ) >/dev/null 2>&1 || rc=$?; _expect "single trailing DEFERRED = FRESH (one deferral allowed)" 0 "$rc"

  # M. (a) marker is a non-tag value < VERSION and != VERSION → FAIL (the new clause; bare <=VERSION would pass)
  _d="$_t/m"; _mkfix "$_d" "1.0.5 GO" "1.0.5" "GO" "2.0.0"; rc=0; ( ROOT="$_d"; META_CONTROL_TAGS="1.0.0 1.0.1" run ) >/dev/null 2>&1 || rc=$?; _expect "(a) non-tag marker !=VERSION = FAIL" 1 "$rc"
  # N. (b) two consecutive lowercase `deferred` → OVERDUE (serial cap no longer evadable by case)
  _d="$_t/n"; mkdir -p "$_d/docs/governance"; : > "$_d/docs/ROADMAP-KIT.md"; printf '99.99.99\n' > "$_d/VERSION"
  printf '1.0.0 deferred\n' > "$_d/docs/governance/.meta-control-last"
  { printf '| Date | Version | Trigger | Profile | Verdict | Artifact | Ledger |\n'; printf '|---|---|---|---|---|---|---|\n'; printf '| 2026-01-01 | 0.9.0 | t | l | deferred | a | s |\n'; printf '| 2026-01-02 | 1.0.0 | t | l | deferred | a | s |\n'; } > "$_d/docs/governance/meta-control-log.md"
  rc=0; ( ROOT="$_d"; META_CONTROL_TAGS="1.0.0" run ) >/dev/null 2>&1 || rc=$?; _expect "(b) lowercase deferred x2 = OVERDUE" 1 "$rc"
  # P. (a) lenient-when-tagless — a REAL repo with NO tags, marker is a value that isn't a visible tag
  #    and != VERSION → PASS. CI checkouts omit tags (actions/checkout fetches none); the real-tag arm
  #    must not false-FAIL a legitimate marker it simply cannot see. (Regression: this FAILed before the
  #    tagless guard, which broke the kit's own per-PR CI when the marker was a real but unfetched tag.)
  _d="$_t/p"; _mkfix "$_d" "3.48.16 GO" "3.48.16" "GO" "3.49.0"
  ( cd "$_d" && git init -q && git -c user.email=c@k -c user.name=c commit -q --allow-empty -m s ) >/dev/null 2>&1
  rc=0; ( ROOT="$_d"; run ) >/dev/null 2>&1 || rc=$?; _expect "(a) tagless leniency: non-tag marker, no tags = PASS" 0 "$rc"

  # ── H1 (PHASE-B-HYGIENE): the ESCALATED tier — count-keyed, > 2N ────────────────────────────────
  # _expect_tier asserts rc AND the verdict token, because OVERDUE and ESCALATED share rc 1 — an
  # rc-only leg cannot tell the advisory band from the exhausted one, and the release gate keys on
  # the token. <label> <expected-rc> <required-token-regex> <forbidden-token-regex|-> <output> <rc>
  _expect_tier() {
    _etok_ok=1
    [ "$2" = "$6" ] || _etok_ok=0
    printf '%s\n' "$5" | grep -qE "$3" || _etok_ok=0
    if [ "$4" != "-" ] && printf '%s\n' "$5" | grep -qE "$4"; then _etok_ok=0; fi
    if [ "$_etok_ok" = 1 ]; then echo "PASS: selftest fixture — $1"
    else echo "meta-control-fresh --selftest: FAIL ($1: rc=$6 want $2; output tokens wrong)"; sfail=1; fi
  }
  # Q. 11 newer tags (> 2N=10) → ESCALATED (rc 1, verdict line starts ESCALATED:)
  _d="$_t/q"; _mkfix "$_d" "1.0.0 GO" "1.0.0" "GO"
  rc=0; out=$( ROOT="$_d"; META_CONTROL_TAGS="1.0.0 1.0.1 1.0.2 1.0.3 1.0.4 1.0.5 1.0.6 1.0.7 1.0.8 1.0.9 1.0.10 1.0.11" run 2>&1 ) || rc=$?
  _expect_tier "11 newer (>2N) = ESCALATED" 1 '^ESCALATED:' '^OVERDUE:' "$out" "$rc"
  # R. exactly 2N=10 newer → still the OVERDUE band, byte-compatible (boundary: ESCALATED is strictly > 2N)
  _d="$_t/r"; _mkfix "$_d" "1.0.0 GO" "1.0.0" "GO"
  rc=0; out=$( ROOT="$_d"; META_CONTROL_TAGS="1.0.0 1.0.1 1.0.2 1.0.3 1.0.4 1.0.5 1.0.6 1.0.7 1.0.8 1.0.9 1.0.10" run 2>&1 ) || rc=$?
  _expect_tier "exactly 2N=10 newer = OVERDUE band (boundary)" 1 '^OVERDUE:' '^ESCALATED:' "$out" "$rc"
  # S. serial-defer cap at a LOW count (0 newer) → OVERDUE, NOT ESCALATED — the cap keeps its own arm
  #    and never escalates by itself (its remedy differs: a REAL run, not just any addressed row).
  _d="$_t/s"; mkdir -p "$_d/docs/governance"; : > "$_d/docs/ROADMAP-KIT.md"; printf '99.99.99\n' > "$_d/VERSION"
  printf '1.0.0 DEFERRED\n' > "$_d/docs/governance/.meta-control-last"
  { printf '| Date | Version | Trigger | Profile | Verdict | Artifact | Ledger |\n'; printf '|---|---|---|---|---|---|---|\n'; printf '| 2026-01-01 | 0.9.0 | t | l | DEFERRED | a | s |\n'; printf '| 2026-01-02 | 1.0.0 | t | l | DEFERRED | a | s |\n'; } > "$_d/docs/governance/meta-control-log.md"
  rc=0; out=$( ROOT="$_d"; META_CONTROL_TAGS="1.0.0" run 2>&1 ) || rc=$?
  _expect_tier "serial-defer cap, count<=2N = OVERDUE not ESCALATED (cap fires regardless of count)" 1 '^OVERDUE:' '^ESCALATED:' "$out" "$rc"
  # T. serial-defer cap AND count > 2N → ESCALATED (escalation is COUNT-keyed and wins the overlap:
  #    a gate that stayed advisory because stale deferrals also capped would be satisfiable by
  #    stacking deferrals and never advancing the marker).
  _d="$_t/u"; mkdir -p "$_d/docs/governance"; : > "$_d/docs/ROADMAP-KIT.md"; printf '99.99.99\n' > "$_d/VERSION"
  printf '1.0.0 DEFERRED\n' > "$_d/docs/governance/.meta-control-last"
  { printf '| Date | Version | Trigger | Profile | Verdict | Artifact | Ledger |\n'; printf '|---|---|---|---|---|---|---|\n'; printf '| 2026-01-01 | 0.9.0 | t | l | DEFERRED | a | s |\n'; printf '| 2026-01-02 | 1.0.0 | t | l | DEFERRED | a | s |\n'; } > "$_d/docs/governance/meta-control-log.md"
  rc=0; out=$( ROOT="$_d"; META_CONTROL_TAGS="1.0.0 1.0.1 1.0.2 1.0.3 1.0.4 1.0.5 1.0.6 1.0.7 1.0.8 1.0.9 1.0.10 1.0.11" run 2>&1 ) || rc=$?
  _expect_tier "cap AND >2N = ESCALATED (count-keyed escalation wins the overlap)" 1 '^ESCALATED:' '^OVERDUE:' "$out" "$rc"

  # V. BOARD-PIPE-ESCAPE T3 leg 6 (C7 fail-open bypass): two consecutive DEFERRED rows, the EARLIER
  #    one carrying an escaped `\|` in its Trigger cell (left of Verdict). Under the OLD raw `awk -F'|'`
  #    split this shifted $6 onto the wrong column, silently read a non-DEFERRED value, `break`-reset the
  #    consecutive count, and evaded the serial-defer cap (freshness falsely greened). Must be OVERDUE.
  _d="$_t/v"; mkdir -p "$_d/docs/governance"; : > "$_d/docs/ROADMAP-KIT.md"; printf '99.99.99\n' > "$_d/VERSION"
  printf '1.0.0 DEFERRED\n' > "$_d/docs/governance/.meta-control-last"
  { printf '| Date | Version | Trigger | Profile | Verdict | Artifact | Ledger |\n'; printf '|---|---|---|---|---|---|---|\n'; printf '| 2026-01-01 | 0.9.0 | a\\| b | light | DEFERRED | a | s |\n'; printf '| 2026-01-02 | 1.0.0 | t | light | DEFERRED | a | s |\n'; } > "$_d/docs/governance/meta-control-log.md"
  rc=0; ( ROOT="$_d"; META_CONTROL_TAGS="1.0.0" run ) >/dev/null 2>&1 || rc=$?
  _expect "T3 leg 6: escaped-pipe-shifted DEFERRED row still trips the serial-defer cap = OVERDUE" 1 "$rc"

  # V2. BOARD-PIPE-ESCAPE M-1 (the leg-6 TWIN): two consecutive DEFERRED rows, the EARLIER one carrying
  #     a RAW (unescaped) `|` in its Trigger cell. Unlike leg V's escaped `\|` (which cell() correctly
  #     joins back into one column), a raw pipe genuinely adds a GFM column — gfm_nf(row) != the
  #     header's column count. The old code still read cell(row,5) positionally and got a non-DEFERRED
  #     value (or the wrong cell), `break`-reset the streak, and evaded the cap. Must stay OVERDUE.
  _d="$_t/v2"; mkdir -p "$_d/docs/governance"; : > "$_d/docs/ROADMAP-KIT.md"; printf '99.99.99\n' > "$_d/VERSION"
  printf '1.0.0 DEFERRED\n' > "$_d/docs/governance/.meta-control-last"
  { printf '| Date | Version | Trigger | Profile | Verdict | Artifact | Ledger |\n'; printf '|---|---|---|---|---|---|---|\n'; printf '| 2026-01-01 | 0.9.0 | a|b | light | DEFERRED | a | s |\n'; printf '| 2026-01-02 | 1.0.0 | t | light | DEFERRED | a | s |\n'; } > "$_d/docs/governance/meta-control-log.md"
  rc=0; ( ROOT="$_d"; META_CONTROL_TAGS="1.0.0" run ) >/dev/null 2>&1 || rc=$?
  _expect "M-1: raw-unescaped-pipe earlier row fails closed (streak-continuing) = OVERDUE" 1 "$rc"

  # V3. BOARD-PIPE-ESCAPE M-1 (the truncated-row twin): the earlier row is short — fewer real columns
  #     than the header (column 5 / Verdict reads empty under cell()). Must NOT silently `break`-reset
  #     the streak as a clean non-DEFERRED verdict; fail closed (streak-continuing) = OVERDUE.
  _d="$_t/v3"; mkdir -p "$_d/docs/governance"; : > "$_d/docs/ROADMAP-KIT.md"; printf '99.99.99\n' > "$_d/VERSION"
  printf '1.0.0 DEFERRED\n' > "$_d/docs/governance/.meta-control-last"
  { printf '| Date | Version | Trigger | Profile | Verdict | Artifact | Ledger |\n'; printf '|---|---|---|---|---|---|---|\n'; printf '| 2026-01-01 | 0.9.0 | t |\n'; printf '| 2026-01-02 | 1.0.0 | t | light | DEFERRED | a | s |\n'; } > "$_d/docs/governance/meta-control-log.md"
  rc=0; ( ROOT="$_d"; META_CONTROL_TAGS="1.0.0" run ) >/dev/null 2>&1 || rc=$?
  _expect "M-1: truncated (short) earlier row fails closed (streak-continuing) = OVERDUE" 1 "$rc"

  # W. BOARD-PIPE-ESCAPE T3 leg 7 (fail-direction, §6.2): log_field with an index past the row's real
  #    column count must return empty (fail-closed), never a silently wrong value from a shifted split.
  #    log_field 99 has no such column; the caller-side comparison in validate_state then mismatches
  #    (empty != MVER), so the FAIL path fires rather than a false pass.
  _d="$_t/w"; _mkfix "$_d" "1.0.0 GO" "1.0.0" "GO"
  _lf_out=$( ROOT="$_d"; log_field 99 )
  [ -z "$_lf_out" ]; _lf_rc=$?
  _expect "T3 leg 7: log_field past the row's column count returns empty (fail-closed)" 0 "$_lf_rc"

  rm -rf "$_t"
  [ "$sfail" -eq 0 ] && { echo "meta-control-fresh --selftest: OK"; exit 0; } || exit 1
fi

run
