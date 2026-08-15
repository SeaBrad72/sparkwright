#!/bin/sh
# tool-coverage.sh — the CONTENT-TOOL family lock (C5 GUARD-TOOL-COVERAGE-GREP-GLOB, design
# 2026-08-14). It does NOT enumerate a hardcoded content-tool list; it enforces a PROPERTY over
# whatever the checked enumeration (conformance/sanctioned-commands.tsv) already contains, so a
# NEWLY-ADDED content tool reds a family lock rather than requiring another enumeration to be edited.
# Builds on C3's sanctioned-commands.tsv `guard-backstop` column (corrected in this slice), not a new
# list (design §2 Part C; the AC: "a newly-added content tool reds a family lock, not another
# enumeration").
#
# WHAT IT LOCKS (design §2 Part C):
#   1. ROW DOMAIN — tool-name rows only: a bare CamelCase token (starts uppercase, no `(`, no embedded
#      space). This EXCLUDES command-pattern rows (Bash(...), gh pr merge, sh scripts/...) which are
#      C3's domain, not a tool-content question (vet F2).
#   2. ACCEPTED SET — for each tool-name row with disposition allow/ask, guard-backstop MUST be in
#      {full, residual-family, declared-uncovered}; a value of `none` REDS (naming the row). The set
#      INCLUDES residual-family (a sanctioned TSV value already used by Grep/Glob/Write(.env)) — a red
#      must NOT be resolved by reclassifying a legitimate row.
#   3. CROSS-CHECK (belt) — each full- or residual-family-marked tool-name row MUST have a matching
#      .claude/hooks/guard.sh `case` arm, so the TSV cannot claim a backstop the adapter doesn't
#      implement (a claimed-but-absent backstop reds).
#
# WHY DETECTION NOT ENUMERATION: C3's reconcile lock (permission-surface-audit.sh `_onlyset`) already
# FORCES every settings.json allow into the TSV, so a newly allow-listed content tool gets a forced
# row — which reds THIS lock (`none` default) unless a human wires its guard (full/residual-family) or
# explicitly declares it uncovered with a reason. The lock never names the four tools; it enforces the
# property.
#
# HONEST CEILING (design §2 Part C.4 / §4): this judges the TRACKED surface (settings.json → TSV). It
# does NOT reach the untracked .claude/settings.local.json — a content tool allow-listed only there
# gets no forced TSV row and, at runtime under the broad matcher, a new tool with no guard.sh arm hits
# `*) allow`. Same CI-can't-read-untracked ceiling C3 disclosed. And a residual-family row is honest
# that its backstop is PARTIAL (Grep's directory/cwd content search is a disclosed residual handed to
# the platform egress/FS boundary — docs/operations/runtime-guards.md), not that content-exfil is
# closed at the guard.
#
# SCOPE — KIT-TREE ONLY. conformance/sanctioned-commands.tsv is export-ignored, so an adopter tree
# carries no enumeration and the lock renders N/A — keyed on the same un-spoofable kit-marker set the
# other kit-self checks use (docs/ROADMAP-KIT.md / .github/workflows/golden-path.yml, both
# export-ignored): N/A only when NEITHER is present, i.e. FAIL-CLOSED on the kit. Registered
# `--kitself` in verify.sh.
#
# Usage: sh conformance/tool-coverage.sh [--selftest]
# Exit: 0 = every content tool-name row covered (or N/A off the kit tree) · 1 = an uncovered/claimed-
# but-absent backstop or missing artifact · 2 = bad usage. POSIX sh; dash-clean.
set -eu

TAB=$(printf '\t')
ENUM="conformance/sanctioned-commands.tsv"
GUARD=".claude/hooks/guard.sh"

# tc_is_tool_name_row <command-pattern> — 0 iff it is a bare CamelCase tool token (starts uppercase,
# no `(`, no embedded space). Command-pattern rows (Bash(...), gh pr merge, sh scripts/...) return 1.
tc_is_tool_name_row() {
  case "$1" in
    *'('*|*' '*|*"$TAB"*) return 1 ;;   # a paren, a space or a tab => a command-pattern row, not a tool
  esac
  case "$1" in
    [A-Z]*) : ;;                          # CamelCase: starts uppercase
    *) return 1 ;;
    # ASSUMPTION (build-review L2): Claude built-in content tools are CamelCase (Grep/Glob/Read/…);
    # a lowercase-first tool is either an mcp__* capability (handled by guard.sh's mcp__* arm +
    # guard_check_mcp, not this lock) or a hypothetical future non-mcp tool. If such a lowercase
    # non-mcp content tool ever ships, extend this predicate — today it would be skipped here.
  esac
  # the remainder must be a bare identifier (letters/digits/underscore only)
  case "$1" in
    *[!A-Za-z0-9_]*) return 1 ;;
  esac
  return 0
}

# tc_guard_has_arm <tool> — 0 iff guard.sh has a `case` arm whose label list contains <tool>. The arm
# label lines look like `  Read)` or `  Grep|Glob)` or `  Write|Edit|NotebookEdit|MultiEdit)`; the
# token must sit as a whole alternative (preceded by start-of-label or `|`, followed by `|` or `)`),
# anchored at the start of the label so a comment mentioning the token cannot satisfy it.
tc_guard_has_arm() {
  grep -Eq "^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*\|)*$1(\||\))" "$GUARD"
}

run() {
  rc=0
  # KIT-SELF scope: N/A only when NEITHER kit marker is present (fail-closed on the kit tree).
  if [ ! -f docs/ROADMAP-KIT.md ] && [ ! -f .github/workflows/golden-path.yml ]; then
    echo "tool-coverage: N/A — kit-self check (conformance/sanctioned-commands.tsv is export-ignored; an adopter tree carries no enumeration and this lock enforces only on the kit's own tree. To opt in, populate your own enumeration.)"
    return 0
  fi
  # SYMLINK REFUSED BEFORE ANYTHING IS READ ([ -f ]/[ -r ] follow links — a link would parse clean
  # here while the rows that decide the audit live off-tree, outside the reviewed diff).
  if [ -L "$ENUM" ]; then
    echo "FAIL: $ENUM is a SYMLINK — the enumeration must be a regular tracked file. Restore it: git checkout HEAD -- $ENUM"
    return 1
  fi
  if [ ! -f "$ENUM" ] || [ ! -r "$ENUM" ]; then
    echo "FAIL: $ENUM is missing or unreadable on the kit tree — no content-tool enumeration to lock. Restore it: git checkout HEAD -- $ENUM"
    return 1
  fi
  if [ ! -f "$GUARD" ]; then
    echo "FAIL: $GUARD is missing — no PreToolUse adapter to cross-check backstops against."
    return 1
  fi

  _seen=0
  # Read via a file redirect (NOT a pipe) so the loop runs in THIS shell and its rc assignment survives.
  while IFS="$TAB" read -r _pat _disp _surf _backstop _mode _reason _ref _tok; do
    case "$_pat" in ''|'#'*|command-pattern) continue ;; esac
    # ROW DOMAIN: tool-name rows only (bare CamelCase token) — command-pattern rows are C3's domain.
    tc_is_tool_name_row "$_pat" || continue
    # only allow/ask tool rows need a backstop — a denied tool needs none.
    case "$_disp" in allow|ask) : ;; *) continue ;; esac
    _seen=$((_seen + 1))
    # ACCEPTED SET: a tool-name allow/ask row must carry a recorded backstop, never `none`.
    case "$_backstop" in
      full|residual-family|declared-uncovered) : ;;
      *)
        echo "FAIL: content tool-name row '$_pat' ($_disp) has guard-backstop '$_backstop' — a shipped allow/ask content tool must be backstopped by the PreToolUse guard (full/residual-family) or HONESTLY declared uncovered (declared-uncovered, a recorded decision), never left at 'none' (a silent uncovered content tool — the exact gap C5 closes). Wire a guard.sh arm, or declare-uncovered with a reason."
        rc=1
        continue ;;
    esac
    # CROSS-CHECK: a claimed backstop (full/residual-family) must be implemented by a guard.sh arm.
    case "$_backstop" in
      full|residual-family)
        if ! tc_guard_has_arm "$_pat"; then
          echo "FAIL: content tool-name row '$_pat' claims guard-backstop '$_backstop' but $GUARD has NO 'case' arm for it — a claimed-but-absent backstop (the TSV cannot promise a route the adapter doesn't implement). Add a $_pat arm to $GUARD, or mark the row declared-uncovered."
          rc=1
        fi ;;
    esac
  done < "$ENUM"

  # A tree whose enumeration contains ZERO content tool-name rows would pass vacuously — the whole
  # surface this lock exists for would be silently empty. Fail-closed on an empty content family.
  if [ "$_seen" -eq 0 ]; then
    echo "FAIL: $ENUM contains ZERO content tool-name allow/ask rows — refusing to pass vacuously (Read/Grep/Glob are the shipped content-tool surface this lock keys on; their absence means the enumeration was gutted)."
    rc=1
  fi

  [ "$rc" -eq 0 ] && echo "tool-coverage: OK (every content tool-name allow/ask row carries a recorded guard-backstop — full/residual-family/declared-uncovered, never a silent 'none' — and every claimed backstop has a matching guard.sh case arm; command-pattern rows are C3's domain, the untracked settings.local.json surface is out of reach by design)"
  return $rc
}

# ---------------------------------------------------------------------------- selftest
selftest() {
  sfail=0
  _self=$(CDPATH='' cd "$(dirname "$0")" && pwd)/$(basename "$0")
  W=$(mktemp -d)

  # liveness anchor: the honest reconciled tree passes — INCLUDING residual-family rows (Grep/Glob),
  # which must NOT be treated as uncovered. A lock that rejected residual-family would red here.
  tc_tree "$W/good"
  tc_expect "liveness anchor: the honest content-tool tree (full + residual-family + declared-uncovered) passes" 0 "$W/good"

  # K-1: flip Grep's backstop to `none` — an allow/ask content tool-name row at `none` REDS.
  tc_tree "$W/k1"
  tc_set_backstop "$W/k1/conformance/sanctioned-commands.tsv" Grep none
  tc_expect "K-1: a content tool-name row at guard-backstop=none reds" 1 "$W/k1"
  tc_says "K-1 names the offending tool" "'Grep'" "$W/k1"

  # K-2: inject a FICTIONAL allow tool-row with backstop=none — proves DETECTION (a tool the lock has
  # never heard of reds), not enumeration of a fixed four.
  tc_tree "$W/k2"
  printf 'FooReader\tallow\tshipped\tnone\tnone\tfictional content tool\tsettings.json:allow\t-\n' >> "$W/k2/conformance/sanctioned-commands.tsv"
  tc_expect "K-2: a NEW (fictional) allow content tool with backstop=none reds (detection, not enumeration)" 1 "$W/k2"
  tc_says "K-2 names the fictional tool" "'FooReader'" "$W/k2"

  # K-3: mark a tool `full` while guard.sh has NO arm for it — the cross-check reds (claimed-but-absent
  # backstop). Add a Task row claiming full; the fixture guard.sh has no Task arm.
  tc_tree "$W/k3"
  printf 'Task\tallow\tshipped\tfull\tnone\tclaims a backstop the adapter lacks\tsettings.json:allow\t-\n' >> "$W/k3/conformance/sanctioned-commands.tsv"
  tc_expect "K-3: a tool claiming full while guard.sh has no case arm reds (cross-check)" 1 "$W/k3"
  tc_says "K-3 says claimed-but-absent" 'NO ' "$W/k3"

  # K-4: delete the Read `case` arm from guard.sh while the TSV Read row still says full — the
  # cross-check reds (the adapter no longer implements the claimed route).
  tc_tree "$W/k4"
  tc_strip_arm "$W/k4/.claude/hooks/guard.sh" Read
  tc_expect "K-4: deleting the Read guard arm while its TSV row says full reds (cross-check)" 1 "$W/k4"
  tc_says "K-4 names Read" "'Read'" "$W/k4"

  # K-5: a COMMAND-PATTERN row (gh pr merge) with backstop=none must NOT red the tool-lock — it is
  # C3's domain, not a tool-content question (the row-domain predicate excludes command rows, vet F2).
  tc_tree "$W/k5"
  printf 'gh pr merge\tallow\truling-only\tnone\tnone\ta command-pattern row, C3 domain\tD-240813-5\tgh pr merge\n' >> "$W/k5/conformance/sanctioned-commands.tsv"
  tc_expect "K-5: a command-pattern row at backstop=none does NOT red the tool-lock (domain excludes command rows)" 0 "$W/k5"

  # a vacuous enumeration (zero content tool-name rows) must FAIL, never pass over nothing.
  tc_tree "$W/empty"
  tc_drop_tool_rows "$W/empty/conformance/sanctioned-commands.tsv"
  tc_expect "a gutted enumeration (zero content tool-name rows) reds (no vacuous pass)" 1 "$W/empty"

  # a SYMLINKED enumeration is refused BEFORE it is read.
  tc_tree "$W/link"
  mv "$W/link/conformance/sanctioned-commands.tsv" "$W/link/conformance/elsewhere.tsv"
  ln -s elsewhere.tsv "$W/link/conformance/sanctioned-commands.tsv"
  tc_expect "a SYMLINKED enumeration is refused before read" 1 "$W/link"
  tc_says "the symlink red says SYMLINK" 'is a SYMLINK' "$W/link"

  # SCOPE: an adopter-shaped tree (no kit markers, no enumeration) is N/A rc 0, disclosed.
  tc_natree "$W/adopter"
  tc_expect "an adopter-shaped tree (no kit markers) is N/A rc 0" 0 "$W/adopter"
  tc_says "the adopter N/A is disclosed as kit-self" 'N/A — kit-self check' "$W/adopter"

  # ...and the scope guard is NOT always-N/A: ONE marker present holds the tree to the lock
  # (fail-closed — deleting a marker must not switch the check off). One marker + no enumeration reds.
  mkdir -p "$W/onemarker/docs"; : > "$W/onemarker/docs/ROADMAP-KIT.md"
  tc_expect "one kit marker + no enumeration still reds (the guard is not always-N/A)" 1 "$W/onemarker"

  rm -rf "$W"
  [ "$sfail" -eq 0 ] && { echo "tool-coverage --selftest: OK (anchor incl. residual-family + K-1 none-reds + K-2 fictional-tool-detection + K-3/K-4 cross-check + K-5 command-row-excluded + vacuous + symlink + scope both ways)"; return 0; }
  echo "tool-coverage --selftest: FAIL"; return 1
}

# --- selftest-only helpers (BELOW selftest() on purpose: the non-vacuity sweep mutates only lines
#     BEFORE the marker, so fixture builders and kill logic sit in the protected oracle region) ---

tc_good_guard() { # <file> — a minimal guard.sh with the content/write case arms the cross-check greps
  cat > "$1" <<'SH'
#!/bin/sh
# fixture guard.sh — only the case-arm labels matter for tool-coverage's cross-check.
case "$TOOL" in
  Bash) : ;;
  Write|Edit|NotebookEdit|MultiEdit) : ;;
  Read) : ;;
  Grep|Glob) : ;;
  mcp__*) : ;;
  Skill) : ;;
  *) : ;;
esac
SH
}

tc_good_enum() { # <file> — a content-tool enumeration reconciled with tc_good_guard: Read/MultiEdit
  #                 covered full, Grep/Glob residual-family, WebFetch declared-uncovered, plus a
  #                 command-pattern row that MUST be ignored by the tool-lock.
  {
    printf 'command-pattern\tdisposition\tsurface\tguard-backstop\tmode-dependence\treason\truling-ref\tbind-token\n'
    printf 'Read\tallow\tshipped\tfull\tnone\tread-only file access\tsettings.json:allow\t-\n'
    printf 'Grep\tallow\tshipped\tresidual-family\tnone\tcontent search; disclosed residual\tsettings.json:allow\t-\n'
    printf 'Glob\tallow\tshipped\tresidual-family\tnone\tpath glob; defense-in-depth\tsettings.json:allow\t-\n'
    printf 'WebFetch\task\tshipped\tdeclared-uncovered\tnone\tnetwork fetch; no file target\tsettings.json:ask\t-\n'
    printf 'Bash(git status:*)\tallow\tshipped\tfull\tnone\tstatus; a command-pattern row\tsettings.json:allow\t-\n'
  } > "$1"
}

tc_tree() { # <dir> — a KIT-MARKED tree carrying a reconciled enum + guard.sh
  mkdir -p "$1/.claude/hooks" "$1/conformance" "$1/docs"
  : > "$1/docs/ROADMAP-KIT.md"   # un-spoofable kit marker
  tc_good_guard "$1/.claude/hooks/guard.sh"
  tc_good_enum "$1/conformance/sanctioned-commands.tsv"
}

tc_natree() { # <dir> — an adopter-shaped tree: no kit markers, no enumeration
  mkdir -p "$1"
}

tc_set_backstop() { # <enum-file> <tool> <value> — set the guard-backstop (col 4) of a tool row
  awk -v t="$2" -v v="$3" 'BEGIN{FS=OFS="\t"} $1==t{$4=v} {print}' "$1" > "$1.new" && mv "$1.new" "$1"
}

tc_strip_arm() { # <guard-file> <tool> — remove the case-arm line whose label starts with <tool>
  grep -Ev "^[[:space:]]*$2(\||\))" "$1" > "$1.new" && mv "$1.new" "$1"
}

tc_drop_tool_rows() { # <enum-file> — drop every CamelCase tool-name row, leaving only command rows
  awk 'BEGIN{FS="\t"} /^#/{print;next} NR==1{print;next} $1 ~ /^[A-Z][A-Za-z0-9_]*$/{next} {print}' "$1" > "$1.new" && mv "$1.new" "$1"
}

tc_expect() { # <label> <want-rc> <dir>
  _rc=0; _out=$( cd "$3" && sh "$_self" 2>&1 ) || _rc=$?
  if [ "$_rc" = "$2" ]; then echo "PASS: selftest — $1"
  else echo "FAIL: selftest — $1 (want rc $2, got $_rc)"; echo "  got: $_out"; sfail=1; fi
}

tc_says() { # <label> <needle> <dir>
  _out=$( cd "$3" && sh "$_self" 2>&1 ) || :
  if printf '%s' "$_out" | grep -qF -- "$2"; then echo "PASS: selftest — $1"
  else echo "FAIL: selftest — $1 (missing '$2')"; echo "  got: $_out"; sfail=1; fi
}

# ---------------------------------------------------------------------------- dispatch
case "${1:-}" in
  --selftest) selftest; exit $? ;;
  "") run; exit $? ;;
  *) echo "usage: tool-coverage.sh [--selftest]" >&2; exit 2 ;;
esac
