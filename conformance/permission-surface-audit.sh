#!/bin/sh
# permission-surface-audit.sh — the CI lock that reconciles the kit's RULINGS about which commands an
# agent may run, its GUARD front-door allows, and its SHIPPED permission surface (.claude/settings.json)
# against the checked enumeration conformance/sanctioned-commands.tsv (C3 PERMISSION-SURFACE-DELIVERY-
# AUDIT, design 2026-08-13; rulings D-240811-2.5, D-240813-4).
#
# WHAT IT LOCKS (CI-VISIBLE surfaces only — design §2/§3B):
#   1. every settings.json allow/ask/deny entry appears in the enumeration with the same disposition
#      (no silent shipped allow; a dropped deny reds too — design Q4-add);
#   2. every enumeration row whose surface is `shipped` is present in settings.json with that
#      disposition (a ruling says allow X but the shipped surface omits/denies X → RED: the B8 face);
#   3. the PreToolUse guard hook stays wired in settings.json (Q4-add) — the runtime backstop for
#      every residual family; the DEEP matcher validation is guard-wired.sh (cited, not duplicated);
#   4. every `ruling-only`/`deliberately-absent` row's ruling-ref BINDS to its command in
#      docs/governance/DECISIONS.md (anti-laundering, design Q3, security-seat STRONG cure): the ref
#      must name a real ruling HEADER **and** that ruling's block must contain the row's bind-token
#      (the command's distinctive stem). Ref-existence alone is NOT enough — a real-but-irrelevant
#      ruling that merely appears in the file does not green the lock; the ref↔command mis-binding
#      REDs. The ref is matched backtick-delimited, so a prefix collision (D-240813-4 vs D-240813-41)
#      cannot resolve the wrong block.
#
# WHAT IT DELIBERATELY DOES NOT REACH: the UNTRACKED .claude/settings.local.json (148 Bash( allows,
# per-machine + gitignored + absent from every CI checkout). A CI gate CANNOT read an untracked file
# (design §2); its control is owner-run disposition + the pre-push advisory, never this lock. Claiming
# otherwise would be the declared-vs-real dishonesty the kit exists to kill.
#
# SCOPE — KIT-TREE ONLY (design condition 7). conformance/sanctioned-commands.tsv is `export-ignore`d,
# so an adopter tree carries no enumeration and the lock renders N/A — keyed on the same un-spoofable
# kit-marker set the other kit-self checks use (docs/ROADMAP-KIT.md / .github/workflows/golden-path.yml,
# both export-ignored): N/A only when NEITHER is present, i.e. FAIL-CLOSED on the kit, where deleting
# one marker cannot switch the lock off. Registered `--kitself` in verify.sh.
#
# HONEST CEILING: this proves AGREEMENT (ruling ↔ shipped ↔ enumeration), not that any allow is WISE
# (owner judgment at disposition time) and not the untracked local surface. It reds a COMMITTED
# disagreement only.
#
# Usage: sh conformance/permission-surface-audit.sh [--selftest]
# Exit: 0 = reconciled (or N/A off the kit tree) · 1 = a disagreement/missing artifact · 2 = bad usage.
# POSIX sh; dash-clean.
set -eu

TAB=$(printf '\t')
ENUM="conformance/sanctioned-commands.tsv"
SET=".claude/settings.json"
DEC="docs/governance/DECISIONS.md"

# psa_settings_entries <settings.json> — emit one "disposition<TAB>pattern" line per allow/ask/deny
# entry. A small state machine over the JSON: enter a section on its key line, leave it on the array
# close `]`, and extract the first quoted string on every line in between. Never enters the "hooks"
# block, so the matcher/command strings there are not mistaken for permission entries.
psa_settings_entries() {
  awk '
    BEGIN { sec="" }
    /"allow"[[:space:]]*:/ { sec="allow"; next }
    /"ask"[[:space:]]*:/   { sec="ask";   next }
    /"deny"[[:space:]]*:/  { sec="deny";  next }
    /"hooks"[[:space:]]*:/ { sec=""; next }
    /\]/ { sec=""; next }
    {
      if (sec != "" && match($0, /"[^"]*"/)) {
        s = substr($0, RSTART + 1, RLENGTH - 2)
        printf "%s\t%s\n", sec, s
      }
    }
  ' "$1"
}

# psa_ruling_block <ruling-ref> <DECISIONS.md> — emit the ruling's block: from its `**`<ref>`` header
# (matched as a FIXED string anchored at column 1, so it is backtick-delimited — a prefix collision
# like D-240813-4 vs D-240813-41 cannot match) to the line before the NEXT `**`D-…` ruling header or
# a `---` rule. Empty output ⇒ no such header ⇒ the ref does not resolve. index()/fixed-string, never
# a regex, so a ref carrying a regex-special char (e.g. a dotted sub-ruling id) cannot mis-anchor.
psa_ruling_block() {
  awk -v hdr="**\`$1\`" '
    BEGIN { started = 0 }
    {
      is_header = (index($0, "**`D-") == 1)
      if (is_header) {
        if (started) exit
        if (index($0, hdr) == 1) { started = 1; print; next }
        next
      }
      if ($0 == "---") { if (started) exit; else next }
      if (started) print
    }
  ' "$2"
}

run() {
  rc=0
  # KIT-SELF scope: N/A only when NEITHER kit marker is present (fail-closed on the kit tree).
  if [ ! -f docs/ROADMAP-KIT.md ] && [ ! -f .github/workflows/golden-path.yml ]; then
    echo "permission-surface-audit: N/A — kit-self check (conformance/sanctioned-commands.tsv is export-ignored; an adopter tree carries no enumeration and this lock enforces only on the kit's own tree, design condition 7. To opt in, populate your own enumeration.)"
    return 0
  fi
  # SYMLINK REFUSED BEFORE ANYTHING IS READ ([ -f ]/[ -r ] follow links — a link would parse clean
  # here while the rows that decide the audit live off-tree, outside the reviewed diff).
  if [ -L "$ENUM" ]; then
    echo "FAIL: $ENUM is a SYMLINK — the enumeration must be a regular tracked file. Restore it: git checkout HEAD -- $ENUM"
    return 1
  fi
  if [ ! -f "$ENUM" ] || [ ! -r "$ENUM" ]; then
    echo "FAIL: $ENUM is missing or unreadable on the kit tree — the sanctioned-command enumeration was dropped, so no shipped allow can be reconciled against a ruling. Restore it: git checkout HEAD -- $ENUM"
    return 1
  fi
  if [ ! -f "$SET" ]; then
    echo "FAIL: $SET is missing — no shipped permission surface to reconcile"
    return 1
  fi

  _A=$(mktemp); _B=$(mktemp)
  # A = the shipped surface: settings.json allow/ask/deny as "disp<TAB>pattern".
  psa_settings_entries "$SET" | LC_ALL=C sort -u > "$_A"
  # B = the enumeration's shipped rows, built in the SAME pass that resolves ruling-refs. Read via a
  # file redirect (NOT a pipe) so the loop runs in THIS shell and its rc assignment survives.
  : > "$_B"
  while IFS="$TAB" read -r _pat _disp _surf _backstop _mode _reason _ref _tok; do
    case "$_pat" in ''|'#'*|command-pattern) continue ;; esac
    # MODE-DEPENDENCE column (5) is now CI-ratcheted (ASK-TIER-MODE-RATCHET, 2026-08-16, reviewer I-2 of
    # the XS honesty batch). Two monotone checks — before it, the column was unvalidated prose and a
    # revert/typo reded nothing (the design's MED-1 ceiling). (a) VOCABULARY: the value must be one of
    # the three the column's own header doc names; a typo (`interactive`) or empty value reds. (b) THE
    # ASK INVARIANT: an `ask` command is an approval surface ONLY under interactive mode, so it may not
    # be marked `none` — that is the exact false-safe the honesty batch fixed; a revert to `none` reds.
    case "$_mode" in
      none|interactive-only|autonomous-wall) : ;;
      *)
        echo "FAIL: '$_pat' carries an out-of-vocabulary mode-dependence '$_mode' — must be one of none|interactive-only|autonomous-wall (column 5; ASK-TIER-MODE-RATCHET vocabulary check)"
        rc=1 ;;
    esac
    if [ "$_disp" = ask ] && [ "$_mode" = none ]; then
      echo "FAIL: '$_pat' is disposition 'ask' but mode-dependence 'none' — an ask command is an approval surface ONLY in interactive mode; marking it 'none' is the false-safe the XS honesty batch fixed. Set mode-dependence to interactive-only (ASK-TIER-MODE-RATCHET invariant)"
      rc=1
    fi
    if [ "$_surf" = shipped ]; then
      printf '%s\t%s\n' "$_disp" "$_pat" >> "$_B"
    fi
    if [ "$_surf" = ruling-only ] || [ "$_disp" = deliberately-absent ]; then
      # STRONG bind (security-seat cure): the ref must name a real ruling header AND that ruling's
      # block must contain the command's bind-token. Existence-in-file is NOT enough.
      _blk=$(psa_ruling_block "$_ref" "$DEC")
      if [ -z "$_blk" ]; then
        echo "FAIL: ruling-ref '$_ref' for '$_pat' ($_disp/$_surf) does NOT resolve to a ruling header block in $DEC — a deliberately-absent or ruling-only sanction must cite a live ruling header (anti-laundering, design Q3)"
        rc=1
      elif [ -z "$_tok" ] || [ "$_tok" = "-" ]; then
        echo "FAIL: '$_pat' ($_disp/$_surf) carries no bind-token — a ruling-only/deliberately-absent row must name the command stem that binds it to ruling '$_ref' (anti-laundering)"
        rc=1
      elif ! printf '%s' "$_blk" | grep -Fq -- "$_tok"; then
        echo "FAIL: ruling-ref '$_ref' for '$_pat' RESOLVES but its ruling block does NOT mention the command token '$_tok' — the citation does not BIND to the command (ref↔command mis-binding); a real-but-irrelevant ruling cannot launder a sanction"
        rc=1
      fi
    fi
  done < "$ENUM"
  LC_ALL=C sort -u "$_B" -o "$_B"

  # Symmetric reconcile: every settings entry ↔ every shipped enumeration row.
  _onlyset=$(LC_ALL=C comm -23 "$_A" "$_B")
  _onlyenum=$(LC_ALL=C comm -13 "$_A" "$_B")
  if [ -n "$_onlyset" ]; then
    printf '%s\n' "$_onlyset" | while IFS="$TAB" read -r _d _p; do
      echo "FAIL: settings.json $_d entry '$_p' has NO matching shipped enumeration row — a silent shipped $_d with no recorded disposition/reason (or a ruling-vs-surface disagreement). Add it to $ENUM or reconcile the disposition."
    done
    rc=1
  fi
  if [ -n "$_onlyenum" ]; then
    printf '%s\n' "$_onlyenum" | while IFS="$TAB" read -r _d _p; do
      echo "FAIL: enumeration shipped row '$_p' ($_d) is ABSENT from settings.json — a ruling says $_d X but the shipped surface omits/denies it (the B8 delivery-gap face), or the shipped $_d was dropped."
    done
    rc=1
  fi
  rm -f "$_A" "$_B"

  # The PreToolUse guard hook must stay wired (design Q4-add). Presence is reconciled HERE; the DEEP
  # structural check (matcher admits the mutating tools) is guard-wired.sh (claim: guard-wired) —
  # CITED, not duplicated. A permission-surface audit that greened while the guard was unwired would
  # be a lie: the guard is the runtime backstop for every residual family the enumeration discloses.
  if ! grep -q 'PreToolUse' "$SET" || ! grep -q 'guard\.sh' "$SET"; then
    echo "FAIL: $SET does not wire the PreToolUse guard hook (need a PreToolUse block whose command runs guard.sh) — an unwired guard makes this audit vacuous. Deep matcher validation: conformance/guard-wired.sh."
    rc=1
  fi

  [ "$rc" -eq 0 ] && echo "permission-surface-audit: OK (settings.json allow/ask/deny reconciles with the shipped enumeration rows both ways; every ruling-only/deliberately-absent row's ruling-ref BINDS to its command — the cited ruling's block contains the command token, not merely the ref string somewhere in the file; the PreToolUse guard hook is wired — the untracked settings.local.json is owner-run/advisory by design, NOT covered here)"
  return $rc
}

# ---------------------------------------------------------------------------- selftest
selftest() {
  sfail=0
  _self=$(CDPATH='' cd "$(dirname "$0")" && pwd)/$(basename "$0")
  W=$(mktemp -d)

  # liveness anchor: the honest reconciled tree passes.
  psa_tree "$W/good"
  psa_expect "liveness anchor: the honest reconciled tree passes" 0 "$W/good"

  # mutant 1 (design AC / condition RED-a): a shipped settings ALLOW absent from the enumeration reds.
  psa_tree "$W/m1"
  psa_inject_allow "$W/m1/.claude/settings.json" 'Bash(evil:*)'
  psa_expect "mutant 1: a shipped settings allow with no enumeration row reds" 1 "$W/m1"
  psa_says "mutant 1 names the offending pattern" 'Bash(evil:*)' "$W/m1"

  # mutant 2 (condition RED-b): an enumeration allow+shipped row absent from settings reds.
  psa_tree "$W/m2"
  printf 'Bash(ghost:*)\tallow\tshipped\tnone\tnone\tghost\tsettings.json:allow\t-\n' >> "$W/m2/conformance/sanctioned-commands.tsv"
  psa_expect "mutant 2: an enumeration allow+shipped row absent from settings reds" 1 "$W/m2"
  psa_says "mutant 2 names the ghost pattern" 'Bash(ghost:*)' "$W/m2"

  # mutant 3 (condition RED-c): a seeded ruling-vs-surface disagreement — flip an enumeration row to
  # `deny` while settings still ALLOW it.
  psa_tree "$W/m3"
  sed "s/^Read${TAB}allow${TAB}shipped/Read${TAB}deny${TAB}shipped/" "$W/m3/conformance/sanctioned-commands.tsv" > "$W/m3/conformance/x" && mv "$W/m3/conformance/x" "$W/m3/conformance/sanctioned-commands.tsv"
  psa_expect "mutant 3: an enumeration disposition disagreeing with settings reds" 1 "$W/m3"

  # mutant 4 (condition RED-d): an unresolvable ruling-ref on a deliberately-absent/ruling-only row reds.
  psa_tree "$W/m4"
  sed 's/D-FIX-1/D-NOPE-9/' "$W/m4/conformance/sanctioned-commands.tsv" > "$W/m4/conformance/x" && mv "$W/m4/conformance/x" "$W/m4/conformance/sanctioned-commands.tsv"
  psa_expect "mutant 4: an unresolvable ruling-ref reds" 1 "$W/m4"
  psa_says "mutant 4 says the ref does not resolve" 'does NOT resolve' "$W/m4"

  # mutant 4b (the LAUNDERING case the security seat caught — Fix 2): a ruling-ref that RESOLVES to a
  # real header block but whose command bind-token is ABSENT from that block reds. This is the case
  # the old existence-only check missed: a real-but-irrelevant ruling would have greened the lock.
  psa_tree "$W/m4b"
  sed "s/D-FIX-1${TAB}gh pr merge --admin/D-FIX-1${TAB}totally-absent-token/" "$W/m4b/conformance/sanctioned-commands.tsv" > "$W/m4b/conformance/x" && mv "$W/m4b/conformance/x" "$W/m4b/conformance/sanctioned-commands.tsv"
  psa_expect "mutant 4b: a resolving ruling-ref whose block lacks the command token reds (the laundering case)" 1 "$W/m4b"
  psa_says "mutant 4b says the citation does not bind" 'does not BIND to the command' "$W/m4b"

  # mutant 5a (condition RED-e, deny half): a dropped shipped `deny` reds.
  psa_tree "$W/m5a"
  sed '/rm -rf/d' "$W/m5a/.claude/settings.json" > "$W/m5a/.claude/x" && mv "$W/m5a/.claude/x" "$W/m5a/.claude/settings.json"
  psa_expect "mutant 5a: a dropped shipped deny reds" 1 "$W/m5a"

  # mutant 5b (condition RED-e, hook half): an unwired PreToolUse guard hook reds.
  psa_tree "$W/m5b"
  sed '/PreToolUse/d' "$W/m5b/.claude/settings.json" > "$W/m5b/.claude/x" && mv "$W/m5b/.claude/x" "$W/m5b/.claude/settings.json"
  psa_expect "mutant 5b: an unwired PreToolUse guard hook reds" 1 "$W/m5b"
  psa_says "mutant 5b names the unwired guard hook" 'does not wire the PreToolUse guard' "$W/m5b"

  # mutant 6 (Fix 5): a SYMLINKED enumeration is refused BEFORE it is read — [ -f ]/[ -r ] follow
  # links, so a link to a ruling-looking file elsewhere would parse clean while the rows that decide
  # the audit sit off-tree, outside the reviewed diff.
  psa_tree "$W/link"
  mv "$W/link/conformance/sanctioned-commands.tsv" "$W/link/conformance/elsewhere.tsv"
  ln -s elsewhere.tsv "$W/link/conformance/sanctioned-commands.tsv"
  psa_expect "mutant 6: a SYMLINKED enumeration is refused before read" 1 "$W/link"
  psa_says "mutant 6 says SYMLINK" 'is a SYMLINK' "$W/link"

  # dropped enumeration file on a kit-marked tree reds (the artifact was removed).
  psa_tree "$W/gone"
  rm -f "$W/gone/conformance/sanctioned-commands.tsv"
  psa_expect "the enumeration DELETED on a kit tree reds (fail-closed on absence)" 1 "$W/gone"

  # SCOPE (condition 7): an adopter-shaped tree (no kit markers, no enumeration) is N/A rc 0, disclosed.
  psa_natree "$W/adopter"
  psa_expect "an adopter-shaped tree (no kit markers) is N/A rc 0" 0 "$W/adopter"
  psa_says "the adopter N/A is disclosed as kit-self" 'N/A — kit-self check' "$W/adopter"

  # ...and the scope guard is NOT always-N/A: ONE marker present holds the tree to the lock
  # (fail-closed — deleting a marker must not switch the check off). One marker + no enumeration reds.
  mkdir -p "$W/onemarker/docs"; : > "$W/onemarker/docs/ROADMAP-KIT.md"
  psa_expect "one kit marker + no enumeration still reds (the guard is not always-N/A)" 1 "$W/onemarker"

  # mutant 7 (ASK-TIER-MODE-RATCHET invariant): an `ask` row marked mode-dependence `none` reds. The
  # anchor fixture's WebFetch ask row is interactive-only; this flips it to `none` and must red.
  psa_tree "$W/askmode"
  sed "s/^WebFetch${TAB}ask${TAB}shipped${TAB}none${TAB}interactive-only/WebFetch${TAB}ask${TAB}shipped${TAB}none${TAB}none/" "$W/askmode/conformance/sanctioned-commands.tsv" > "$W/askmode/conformance/x" && mv "$W/askmode/conformance/x" "$W/askmode/conformance/sanctioned-commands.tsv"
  psa_expect "mutant 7: an ask row with mode-dependence none reds (the ratchet)" 1 "$W/askmode"
  psa_says "mutant 7 names the ask/none invariant" "'ask' but mode-dependence 'none'" "$W/askmode"

  # mutant 8 (ASK-TIER-MODE-RATCHET vocabulary): an out-of-vocabulary mode-dependence value reds (the
  # typo half of reviewer I-2's "a revert OR typo reds nothing").
  psa_tree "$W/badmode"
  sed "s/${TAB}interactive-only${TAB}fetch/${TAB}interactiv${TAB}fetch/" "$W/badmode/conformance/sanctioned-commands.tsv" > "$W/badmode/conformance/x" && mv "$W/badmode/conformance/x" "$W/badmode/conformance/sanctioned-commands.tsv"
  psa_expect "mutant 8: an out-of-vocabulary mode-dependence value reds" 1 "$W/badmode"
  psa_says "mutant 8 names the vocabulary check" 'out-of-vocabulary mode-dependence' "$W/badmode"

  rm -rf "$W"
  [ "$sfail" -eq 0 ] && { echo "permission-surface-audit --selftest: OK (anchor + shipped-allow/enum-row/disposition/ruling-ref-unresolvable/ruling-ref-mis-bind(laundering)/deny/hook/symlink mutants + dropped-enum + scope both ways + mode-dependence ask-invariant/vocabulary)"; return 0; }
  echo "permission-surface-audit --selftest: FAIL"; return 1
}

# --- selftest-only helpers (BELOW selftest() on purpose: the non-vacuity sweep mutates only lines
#     BEFORE the marker, so fixture builders and kill logic sit in the protected oracle region) ---
psa_good_settings() { # <file> — a reconciled shipped surface with a wired PreToolUse guard hook
  cat > "$1" <<'JSON'
{
  "permissions": {
    "allow": [
      "Read",
      "Bash(git status:*)"
    ],
    "ask": [
      "WebFetch"
    ],
    "deny": [
      "Bash(rm -rf:*)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash|Write|Edit", "hooks": [ { "type": "command", "command": "sh guard.sh" } ] }
    ]
  }
}
JSON
}

psa_good_enum() { # <file> — the enumeration reconciled with psa_good_settings + one BINDING row (8 cols)
  {
    printf 'command-pattern\tdisposition\tsurface\tguard-backstop\tmode-dependence\treason\truling-ref\tbind-token\n'
    printf 'Read\tallow\tshipped\tnone\tnone\tread-only\tsettings.json:allow\t-\n'
    printf 'Bash(git status:*)\tallow\tshipped\tfull\tnone\tstatus\tsettings.json:allow\t-\n'
    printf 'WebFetch\task\tshipped\tnone\tinteractive-only\tfetch\tsettings.json:ask\t-\n'
    printf 'Bash(rm -rf:*)\tdeny\tshipped\tnone\tnone\tdestructive\tsettings.json:deny\t-\n'
    printf 'gh pr merge --admin\tdeliberately-absent\truling-only\tfull\tnone\tadmin-only\tD-FIX-1\tgh pr merge --admin\n'
  } > "$1"
}

psa_tree() { # <dir> — a KIT-MARKED tree carrying a reconciled settings/enum/decisions triple. The
  #             fixture DECISIONS carries a real `**`D-FIX-1`` header block whose text CONTAINS the
  #             deliberately-absent row's bind-token, so the strong ref↔command bind is satisfied.
  mkdir -p "$1/.claude" "$1/conformance" "$1/docs/governance"
  : > "$1/docs/ROADMAP-KIT.md"   # un-spoofable kit marker
  psa_good_settings "$1/.claude/settings.json"
  psa_good_enum "$1/conformance/sanctioned-commands.tsv"
  {
    printf '**`D-FIX-1` · ruling · the admin merge is human-only.\n'
    printf 'The gh pr merge --admin bypass is denied to agents (Tier 3, human-forever).\n'
    printf -- '---\n'
  } > "$1/docs/governance/DECISIONS.md"
}

psa_natree() { # <dir> — an adopter-shaped tree: no kit markers, no enumeration
  mkdir -p "$1"
}

psa_inject_allow() { # <settings-file> <pattern> — add an extra allow entry not in the enumeration
  sed "s#\"allow\": \[#\"allow\": [\n      \"$2\",#" "$1" > "$1.new" && mv "$1.new" "$1"
}

psa_expect() { # <label> <want-rc> <dir>
  _rc=0; _out=$( cd "$3" && sh "$_self" 2>&1 ) || _rc=$?
  if [ "$_rc" = "$2" ]; then echo "PASS: selftest — $1"
  else echo "FAIL: selftest — $1 (want rc $2, got $_rc)"; echo "  got: $_out"; sfail=1; fi
}

psa_says() { # <label> <needle> <dir>
  _out=$( cd "$3" && sh "$_self" 2>&1 ) || :
  if printf '%s' "$_out" | grep -qF -- "$2"; then echo "PASS: selftest — $1"
  else echo "FAIL: selftest — $1 (missing '$2')"; echo "  got: $_out"; sfail=1; fi
}

# ---------------------------------------------------------------------------- dispatch
case "${1:-}" in
  --selftest) selftest; exit $? ;;
  "") run; exit $? ;;
  *) echo "usage: permission-surface-audit.sh [--selftest]" >&2; exit 2 ;;
esac
