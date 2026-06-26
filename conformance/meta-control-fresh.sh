#!/bin/sh
# meta-control-fresh.sh — M2 freshness gate: the cadenced meta-control circuit-breaker.
#
# The meta-control panel (docs/operations/meta-control.md) is the kit's institutional, adversarial
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
#   sh conformance/meta-control-fresh.sh [--selftest]
#   env: META_CONTROL_N (default 5) · META_CONTROL_ROOT (default .) · META_CONTROL_TAGS (test hook)
# Exit: 0 = FRESH or N/A · 1 = OVERDUE / invalid-state / desync · 2 = usage. POSIX sh; dash-clean.
set -eu
_here=$(CDPATH='' cd "$(dirname "$0")" && pwd)
. "$_here/version-helpers.sh"
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

# log_field <awk-index> — trimmed value of a column from the log's LAST data row (skips header +
# separator). awk split on "|" yields a[1]="" so Version=a[3], Verdict=a[6]. Exit 1 if no data row.
log_field() {
  awk -F'|' -v idx="$1" '
    /^[ \t]*\|/ {
      t=$2; gsub(/^[ \t]+|[ \t]+$/,"",t)
      if (t=="Date") next                       # header row
      if ($0 ~ /^[ \t]*\|[ \t:|-]+$/) next      # separator row (dashes/colons only)
      last=$0
    }
    END { if (last=="") exit 1; split(last,a,"|"); v=a[idx]; gsub(/^[ \t]+|[ \t]+$/,"",v); print v }
  ' "$ROOT/$LOG"
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
    echo "FAIL: meta-control cadence is active but the state marker is missing ($MARKER). Run the panel (docs/operations/meta-control.md) or log a dated DEFERRED row, then write the marker."
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
  # control-plane status (the guard denies agent writes; see docs/operations/meta-control.md).
  #  i. marker must not be AHEAD of VERSION (rejects a fabricated 99.0.0 future-pin).
  # ii. marker must correspond to a real release point: an existing semver tag OR exactly == VERSION
  #     (the unreleased ship-seam). Rejects a plausible-but-fabricated in-between marker that (i) alone
  #     would accept. Enforced only when an anchor exists (VERSION present); lenient otherwise so an
  #     adopter who versions differently is not over-constrained.
  if [ -f "$ROOT/VERSION" ]; then
    _vraw=$(ver_norm "$(tr -d '[:space:]' < "$ROOT/VERSION" 2>/dev/null || true)")
    if printf '%s' "$_vraw" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
      if ver_gt "$MVER" "$_vraw"; then
        echo "FAIL: marker version $MVER is ahead of VERSION $_vraw — a future-pinned marker would pin the gate FRESH forever. Set the marker to a real run's version (<= VERSION)."
        return 1
      fi
      _is_tag=0
      for _t in $(tags_list); do [ "$_t" = "$MVER" ] && { _is_tag=1; break; }; done
      if [ "$_is_tag" = "0" ] && [ "$MVER" != "$_vraw" ]; then
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
    echo "FAIL: marker/log desync — marker='$MVER $MVERDICT' but log's last row='$_lver $_lverdict'. The two must advance together (update $MARKER whenever you append to $LOG)."
    return 1
  fi
  return 0
}

# trailing_deferred — count consecutive DEFERRED verdicts from the END of the log (the serial-defer cap).
trailing_deferred() {
  awk -F'|' '
    /^[ \t]*\|/ {
      t=$2; gsub(/^[ \t]+|[ \t]+$/,"",t)
      if (t=="Date") next
      if ($0 ~ /^[ \t]*\|[ \t:|-]+$/) next
      v=$6; gsub(/^[ \t]+|[ \t]+$/,"",v); rows[++n]=toupper(v)
    }
    END { c=0; for (i=n;i>=1;i--){ if(rows[i]=="DEFERRED") c++; else break } print c+0 }
  ' "$ROOT/$LOG" 2>/dev/null
}

# freshness — prints FRESH/OVERDUE; returns 0/1. Uses MVER (set by validate_state).
freshness() {
  # M2-S5: serial-deferral cap — a deferral covers ONE cadence, but >=N consecutive DEFERRED rows force
  # a real run (you cannot defer forever). Independent of the tag count.
  _defcap="${META_CONTROL_DEFER_CAP:-2}"
  _trail=$(trailing_deferred)
  if [ "${_trail:-0}" -ge "$_defcap" ]; then
    echo "OVERDUE: $_trail consecutive DEFERRED rows (cap $_defcap) — a real meta-control panel run is now required; serial deferral is not permitted."
    return 1
  fi
  _cnt=$(count_newer "$MVER")
  if [ "$_cnt" -gt "$N" ]; then
    echo "OVERDUE: $_cnt release tags since the last addressed meta-control panel ($MVER, $MVERDICT; N=$N)."
    echo "  -> Run the light 5-lens panel per docs/operations/meta-control.md (or log a dated DEFERRED row with a reason),"
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

  rm -rf "$_t"
  [ "$sfail" -eq 0 ] && { echo "meta-control-fresh --selftest: OK"; exit 0; } || exit 1
fi

run
