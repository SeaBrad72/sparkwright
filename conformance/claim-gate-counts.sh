#!/bin/sh
# claim-gate-counts.sh — semantic-drift check over DEVELOPMENT-STANDARDS.md §14's OWN
# enumeration. Three independent legs, each load-bearing:
#
#   DERIVE  — count the §14 required-gate table rows and the conditional-gate bullets
#             from §14 itself, then check the PROSE count-words/numerals AGREE with what
#             was derived. An honest reword to a new TRUE count passes; a prose-vs-
#             enumeration disagreement reds. This replaces the hard-coded numeral+word
#             pins this check used to carry, which redded an honestly-reworded eight-gate
#             tree (measured, and disclosed in the header as a deliberate trade).
#   FLOOR   — required-gate rows >= REQUIRED_FLOOR and conditional bullets >=
#             CONDITIONAL_FLOOR. Shrinking the enumeration reds EVEN WHEN the prose is
#             honestly reworded down with it, so erosion cannot be laundered into a green
#             by editing two words. Derivation alone passes that fixture — measured.
#   ANCHORS — fixed-string per-gate NAME anchors over the §14 SLICE ONLY (the seven
#             required-gate row names, incl. `Secret scan` and `Supply-chain integrity`,
#             and the five conditional bullet names), mirroring the shape
#             conformance/conditional-gates.sh uses for the process doc's gate rows. A
#             gate renamed or swapped while the count holds reds AND is named.
#             Derivation alone passes that fixture too — measured. The anchors run over
#             the SAME awk range-slice count_required derives from, never the whole file:
#             a whole-file grep is satisfied by the literal living ANYWHERE, so deleting
#             `| **Secret scan** |` from the table and re-planting it in an HTML comment
#             or a "Legacy gates" table elsewhere in the document scored rc 0 — two green
#             attacks, both demonstrated at review.
#
#   sh conformance/claim-gate-counts.sh [--selftest]
# Exit: 0 = the claims match the enumeration · 1 = drift · 2 = usage. POSIX sh; dash-clean.
#
# HONEST CEILING: this reads ONE enumeration (§14's) plus one numeral site in the
# principles doc. A gate-count claim phrased in a document this check does not read is
# out of scope — that residual is the PROSE-LOCK-BRITTLENESS row's remit. The floor is a
# RATCHET, not a proof that the named gates are wired; conformance/ci-gates.sh owns that.
# And it reads gate NAMES and COUNTS only: a gate's DISPOSITION TEXT is unchecked, so
# rewriting a row's Requirement cell to "now advisory" or "recommended where practical"
# keeps every anchor present, the count intact and this check green. Hollowing a gate out
# in place is invisible here by construction — the review gate owns that reading.
set -eu

STD="${KIT_STANDARDS:-DEVELOPMENT-STANDARDS.md}"
PRIN="${KIT_PRINCIPLES:-CLAUDE.md}"

# The floors. Raising either is a deliberate ratchet; lowering one is the erosion this
# leg exists to refuse, and must be argued at a design gate, not edited in passing.
REQUIRED_FLOOR=7
CONDITIONAL_FLOOR=5

# num2word <n> : the English count-word for a small integer, empty beyond the table.
num2word() {
  case $1 in
    1) echo one ;;    2) echo two ;;     3) echo three ;;   4) echo four ;;
    5) echo five ;;   6) echo six ;;     7) echo seven ;;   8) echo eight ;;
    9) echo nine ;;   10) echo ten ;;    11) echo eleven ;; 12) echo twelve ;;
    13) echo thirteen ;; 14) echo fourteen ;; 15) echo fifteen ;; 16) echo sixteen ;;
    *) echo "" ;;
  esac
}

# count_required <std> : rows in the §14 required-gates table — `| N | **Gate** | …`.
count_required() {
  awk '/^## 14\./{s=1;next} s&&/^## /{exit} s&&/^\| [0-9]+ \| \*\*/{n++} END{print n+0}' "$1"
}
# count_conditional <std> : `- **…**` bullets in the conditional-gates subsection. The
# subsection is anchored on a COUNT-FREE phrase on purpose: keying the scope on the
# count-word ("Five further gates") would make the derivation unfindable the moment the
# count it is meant to derive changes.
count_conditional() {
  awk '/\*\*Conditional gates \(/{s=1;next} s&&/deliberately/{exit} s&&/^- \*\*/{n++} END{print n+0}' "$1"
}
# claimed_word <file> <noun-phrase> : the count-word immediately preceding the phrase,
# lowercased; empty when the phrase is absent.
claimed_word() {
  grep -oE "[A-Za-z]+ $2" "$1" 2>/dev/null | head -1 | awk '{print tolower($1)}' || true
}
# claimed_numeral <file> <noun-phrase> : the numeral immediately preceding the phrase.
claimed_numeral() {
  grep -oE "[0-9]+ $2" "$1" 2>/dev/null | head -1 | awk '{print $1}' || true
}

# section_14 <std> : print the §14 slice — the SAME range count_required derives over.
# The anchors are scoped to it deliberately: a whole-file match is satisfied by the
# literal living anywhere in the document, so a gate deleted from the table and
# re-planted in an HTML comment, a quoted example or a "Legacy gates" table scores a
# green. Scope the proof to the enumeration it is a proof ABOUT.
section_14() {
  awk '/^## 14\./{s=1} s&&/^## /&&!/^## 14\./{exit} s{print}' "$1"
}

# check_anchors <std> : every §14 gate NAME must still be present as a fixed string ON A
# LINE OF THE ENUMERATION THAT CARRIES IT — a required-gate name on a table row of the
# shape count_required counts, a conditional-gate name on a bullet of the shape
# count_conditional counts. Matched with grep -F so the literal '*' and '|' are not globs.
#
# Section scoping alone is NOT enough, and the difference is a measured attack: delete
# `| 5 | **Secret scan** | … |` from the table and re-plant the literal inside §14's OWN
# blockquote prose ("> Historical note: the row `| **Secret scan** |` used to sit above")
# and a section-scoped PRESENCE test scores rc 0. Binding each anchor to the LINE SHAPE
# the count is derived from closes it: a gate name only answers for itself where it is
# actually enumerated.
check_anchors() {
  _d=$1; _af=0
  _slice=$(section_14 "$_d")
  # required-gate names — only a `| N | **Gate** | …` table row answers.
  _rows=$(printf '%s\n' "$_slice" | grep -E '^\| [0-9]+ \| \*\*' || true)
  while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    if printf '%s\n' "$_rows" | grep -qF -- "$pat"; then :; else
      echo "FAIL: gate-name anchor missing from the §14 required-gate TABLE in $_d — $pat (the gate was renamed, replaced or removed; the count alone cannot see this, and a copy of the literal in prose, a blockquote or elsewhere in the file does not answer it)"; _af=1
    fi
  done <<'EOF'
| **Lint** |
| **Type-check** |
| **Test + coverage** |
| **Build** |
| **Secret scan** |
| **Dependency scan** |
| **Supply-chain integrity** |
EOF
  # conditional-gate names — only a `- **Gate**` bullet of the subsection answers.
  _buls=$(printf '%s\n' "$_slice" | grep -E '^- \*\*' || true)
  while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    if printf '%s\n' "$_buls" | grep -qF -- "$pat"; then :; else
      echo "FAIL: gate-name anchor missing from the §14 conditional-gate BULLETS in $_d — $pat (the gate was renamed, replaced or removed; a copy of the literal in prose does not answer it)"; _af=1
    fi
  done <<'EOF'
- **Accessibility**
- **Load / soak**
- **Eval**
- **SAST**
- **License compliance**
EOF
  return $_af
}

check() {
  _std=$1; _prin=$2; f=0
  [ -f "$_std" ]  || { echo "FAIL: missing $_std"; return 1; }
  [ -f "$_prin" ] || { echo "FAIL: missing $_prin"; return 1; }
  _rq=$(count_required "$_std"); _cd=$(count_conditional "$_std")

  # ---- required gates: scope, floor, derivation-vs-prose ----------------------------
  if [ "$_rq" -eq 0 ]; then
    echo "FAIL: required gates — §14 table not found (the '## 14.' anchor or table shape changed; this is a CHECK-SCOPE problem, not a gate-count drift — update claim-gate-counts.sh)"; f=1
  else
    if [ "$_rq" -lt "$REQUIRED_FLOOR" ]; then
      echo "FAIL: required gates — enumerated=$_rq is BELOW the floor of $REQUIRED_FLOOR; the required-gate set may be added to, never eroded (rewording the prose down does not license removing a gate)"; f=1
    fi
    _want=$(num2word "$_rq"); _got=$(claimed_word "$_std" "required gates")
    _num=$(claimed_numeral "$_prin" "required gates")
    if [ -z "$_got" ]; then
      echo "FAIL: required gates — $_std states no '<word> required gates' claim to check the enumeration against"; f=1
    elif [ "$_got" != "$_want" ]; then
      echo "FAIL: required gates — enumerated=$_rq so $_std should read '$_want required gates'; it reads '$_got required gates'"; f=1
    fi
    if [ -z "$_num" ]; then
      echo "FAIL: required gates — $_prin states no '<N> required gates' claim to check the enumeration against"; f=1
    elif [ "$_num" != "$_rq" ]; then
      echo "FAIL: required gates — enumerated=$_rq but $_prin claims '$_num required gates'"; f=1
    fi
    [ "$f" -eq 0 ] && echo "PASS: required gates — $_rq enumerated == '$_want' ($_std) / '$_num' ($_prin), floor $REQUIRED_FLOOR held"
  fi

  # ---- conditional gates: scope, floor, derivation-vs-prose -------------------------
  _cf=0
  if [ "$_cd" -eq 0 ]; then
    echo "FAIL: conditional gates — the '**Conditional gates (' subsection was not found (anchor/phrase changed; CHECK-SCOPE problem, not a drift — update claim-gate-counts.sh)"; f=1; _cf=1
  else
    if [ "$_cd" -lt "$CONDITIONAL_FLOOR" ]; then
      echo "FAIL: conditional gates — enumerated=$_cd is BELOW the floor of $CONDITIONAL_FLOOR; a conditional gate may be added, never eroded"; f=1; _cf=1
    fi
    _cwant=$(num2word "$_cd"); _cgot=$(claimed_word "$_std" "further gates")
    if [ -z "$_cgot" ]; then
      echo "FAIL: conditional gates — $_std states no '<word> further gates' claim to check the enumeration against"; f=1; _cf=1
    elif [ "$_cgot" != "$_cwant" ]; then
      echo "FAIL: conditional gates — enumerated=$_cd so $_std should read '$_cwant further gates'; it reads '$_cgot further gates'"; f=1; _cf=1
    fi
    [ "$_cf" -eq 0 ] && echo "PASS: conditional gates — $_cd enumerated == '$_cgot' claimed, floor $CONDITIONAL_FLOOR held"
  fi

  # ---- the gate NAMES themselves ----------------------------------------------------
  if check_anchors "$_std"; then
    echo "PASS: gate-name anchors — all 12 §14 gate names present, each on the enumeration line that carries it (7 table rows + 5 bullets)"
  else
    f=1
  fi
  return $f
}

if [ "${1:-}" = "--selftest" ]; then
  sfail=0
  d=$(mktemp -d)
  trap 'rm -rf "$d"' EXIT INT TERM
  # Fixture builder: an eight-gate §14 whose prose is HONESTLY reworded to match, with
  # every real gate name present. `rows` is the required-gate table; `word` is the prose
  # count-word; `prin` is the principles numeral.
  _std_fixture() {
    _rows=$1; _word=$2; _dst=$3
    {
      echo "## 14. CI/CD Pipeline"
      echo "Every project's CI must run, on every pull request, $_word required gates before code can merge."
      echo ""
      echo "| # | Gate | Requirement |"
      echo "|---|------|-------------|"
      echo "| 1 | **Lint** | Style/correctness linter passes. |"
      echo "| 2 | **Type-check** | Static type analysis passes. |"
      echo "| 3 | **Test + coverage** | Test suite passes; coverage floor met. |"
      echo "| 4 | **Build** | A production build succeeds. |"
      echo "| 5 | **Secret scan** | The diff/history is scanned for committed secrets. |"
      echo "| 6 | **Dependency scan** | Dependencies are scanned for known vulnerabilities. |"
      [ "$_rows" -ge 7 ] && echo "| 7 | **Supply-chain integrity** | An SBOM is generated and provenance attested. |"
      [ "$_rows" -ge 8 ] && echo "| 8 | **Container scan** | The image is scanned before release. |"
      echo ""
      echo "**Conditional gates (a11y / load / eval / SAST / license).** Five further gates are first-class but conditional:"
      echo "- **Accessibility** *(user-facing UI)* — WCAG 2.1 AA."
      echo "- **Load / soak** *(deployable services)* — resilience verification."
      echo "- **Eval** *(AI features)* — the eval bar holds."
      echo "- **SAST** *(first-party code)* — static analysis."
      echo "- **License compliance** *(when an SBOM is produced)* — over the SBOM."
      echo ""
      echo "They are deliberately not universal required gates."
      echo "## 15. Next"
    } > "$_dst"
  }
  _prin_fixture() { printf 'the %s required gates pass\n' "$1" > "$2"; }

  # (i) POSITIVE — eight gates with honestly-reworded prose must PASS. This is the whole
  #     point of the reshape: the old pins redded exactly this tree.
  _std_fixture 8 eight "$d/good-std.md"; _prin_fixture 8 "$d/good-prin.md"
  if check "$d/good-std.md" "$d/good-prin.md" >/dev/null 2>&1; then
    echo "PASS: selftest (i) — an 8-gate tree with honestly-reworded prose verifies"
  else
    echo "FAIL: selftest (i) — an honestly-reworded 8-gate tree was wrongly rejected"; sfail=1
  fi

  # (ii) NEGATIVE — the enumeration says eight, the prose still says seven -> FAIL.
  sed 's/eight required gates/seven required gates/' "$d/good-std.md" > "$d/mismatch-std.md"
  if check "$d/mismatch-std.md" "$d/good-prin.md" >/dev/null 2>&1; then
    echo "FAIL: selftest (ii) — a prose/enumeration mismatch was not caught"; sfail=1
  else
    echo "PASS: selftest (ii) — prose/enumeration mismatch detected"
  fi

  # (iii) NEGATIVE, THE EROSION LEG — a gate row DELETED and the prose honestly reworded
  #       down with it (7 -> 6, "six"). Derivation alone passes this; only the floor reds
  #       it, which is what makes the floor load-bearing rather than decoration.
  _std_fixture 6 six "$d/erosion-std.md"; _prin_fixture 6 "$d/erosion-prin.md"
  if check "$d/erosion-std.md" "$d/erosion-prin.md" >/dev/null 2>&1; then
    echo "FAIL: selftest (iii) — an honestly-reworded EROSION below the floor was not caught"; sfail=1
  else
    if check "$d/erosion-std.md" "$d/erosion-prin.md" 2>&1 | grep -q 'BELOW the floor'; then
      echo "PASS: selftest (iii) — erosion caught ON THE FLOOR, not on a prose mismatch"
    else
      echo "FAIL: selftest (iii) — erosion rejected, but not by the floor leg"; sfail=1
    fi
  fi

  # (iv) NEGATIVE — a gate NAME renamed while the count and the prose stay honest. Only
  #      the anchors can see this; derivation alone passes it.
  sed 's/\*\*Secret scan\*\*/**Secrets scanning**/' "$d/good-std.md" > "$d/anchor-std.md"
  if check "$d/anchor-std.md" "$d/good-prin.md" >/dev/null 2>&1; then
    echo "FAIL: selftest (iv) — a renamed gate NAME was not caught"; sfail=1
  else
    if check "$d/anchor-std.md" "$d/good-prin.md" 2>&1 | grep -q 'gate-name anchor missing'; then
      echo "PASS: selftest (iv) — renamed gate name caught by the anchor leg, and named"
    else
      echo "FAIL: selftest (iv) — renamed gate rejected, but not by the anchor leg"; sfail=1
    fi
  fi

  # (v) NEGATIVE — the cross-doc numeral claim absent from the principles doc -> FAIL.
  printf 'no claim here\n' > "$d/bad-prin.md"
  if check "$d/good-std.md" "$d/bad-prin.md" >/dev/null 2>&1; then
    echo "FAIL: selftest (v) — a missing principles claim was not caught"; sfail=1
  else
    echo "PASS: selftest (v) — cross-doc claim absence detected"
  fi

  # (vi) NEGATIVE, THE OUT-OF-RANGE REPLANT — a gate row DELETED from the §14 table and
  #      the literal RE-PLANTED outside the §14 range (an HTML comment plus a "Legacy
  #      gates" table under §16). The count and the prose are honestly reworded down to
  #      seven so nothing else can red: only the scoped anchor can see this. A whole-file
  #      grep scored rc 0 on exactly this shape — measured at review.
  sed '/| 5 | \*\*Secret scan\*\* |/d' "$d/good-std.md" \
    | sed 's/eight required gates/seven required gates/' > "$d/replant-std.md"
  {
    echo "<!-- historical: | **Secret scan** | was retired here -->"
    echo "## 16. Legacy gates (retained for reference)"
    echo "| # | Gate | Requirement |"
    echo "|---|------|-------------|"
    echo "| 1 | **Secret scan** | The diff/history is scanned for committed secrets. |"
  } >> "$d/replant-std.md"
  _prin_fixture 7 "$d/replant-prin.md"
  if check "$d/replant-std.md" "$d/replant-prin.md" >/dev/null 2>&1; then
    echo "FAIL: selftest (vi) — a gate deleted from §14 and re-planted OUTSIDE the range was not caught"; sfail=1
  else
    if check "$d/replant-std.md" "$d/replant-prin.md" 2>&1 | grep -q 'gate-name anchor missing from the §14'; then
      echo "PASS: selftest (vi) — out-of-range replant caught by the SCOPED anchor leg, and named"
    else
      echo "FAIL: selftest (vi) — replant rejected, but not by the scoped anchor leg"; sfail=1
    fi
  fi

  # (vii) NEGATIVE, THE IN-SECTION PROSE REPLANT — the sharper shape, and the one section
  #       scoping alone does NOT stop: the row is deleted from the table and the literal
  #       re-planted inside §14's OWN blockquote prose, so it lives in the slice. Only
  #       binding the anchor to the LINE SHAPE the count derives from can see it. The
  #       section-scoped-but-presence-only check scored rc 0 here — measured at review.
  sed '/| 5 | \*\*Secret scan\*\* |/d' "$d/good-std.md" \
    | sed 's/eight required gates/seven required gates/' \
    | sed 's/^\*\*Conditional gates (/> Historical note: the row `| **Secret scan** |` used to sit above.\n\n**Conditional gates (/' > "$d/prose-std.md"
  if check "$d/prose-std.md" "$d/replant-prin.md" >/dev/null 2>&1; then
    echo "FAIL: selftest (vii) — a gate re-planted in §14's OWN prose was not caught"; sfail=1
  else
    if check "$d/prose-std.md" "$d/replant-prin.md" 2>&1 | grep -q 'required-gate TABLE'; then
      echo "PASS: selftest (vii) — in-section prose replant caught by the TABLE-SHAPE anchor, and named"
    else
      echo "FAIL: selftest (vii) — prose replant rejected, but not by the table-shape anchor"; sfail=1
    fi
  fi

  [ "$sfail" -eq 0 ] && { echo "OK: claim-gate-counts selftest"; exit 0; } || { echo "FAIL: claim-gate-counts selftest"; exit 1; }
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: claim-gate-counts.sh [--selftest]" >&2; exit 2 ;;
esac

echo "Gate-count claim consistency (derived from §14's own enumeration):"
if check "$STD" "$PRIN"; then echo "OK: gate-count claims match the enumeration"; exit 0; else echo "FAIL: gate-count claim drift (see above)"; exit 1; fi
