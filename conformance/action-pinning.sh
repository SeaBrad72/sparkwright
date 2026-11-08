#!/bin/sh
# action-pinning.sh — assert every `uses:` is SHA-pinned across the kit's OWN workflows AND the
# WHOLE profile fleet (Slice 9j; broadened in H4b to the kit's own .github/workflows/; broadened
# in CP-7/K14 to every profiles/<stack>/ci.yml — not just typescript-node). K14 proved a
# single-profile check was a mask: the emitted SAST scans all 10 shipped ci.yml files, so an
# unpinned non-typescript profile reddened the adopter's first CI while this gate stayed green.
# Fail-closed: an empty fleet enumeration (no profiles found) is a FAIL, never a vacuous pass.
#   sh conformance/action-pinning.sh [--selftest]
# Exit: 0 = all SHA-pinned · 1 = a tag/branch-pinned uses: · 2 = bad usage. POSIX sh; dash-clean.
# INVARIANT: every profiles/<dir> is a pinnable profile shipping a ci.yml — a subdir without one FAILs
# by design (forces a new profile to ship a pinned CI). Shared/helper files live at profiles/<file>,
# NOT profiles/<dir>/ (e.g. profiles/ratification.yml, profiles/_TEMPLATE.md).
set -eu

REF_RATIFICATION="profiles/ratification.yml"  # CP-9 §13 gate; RATIFY-PARITY: the single stack-neutral source
REF_ADOPTER_GATES="profiles/adopter-gates.yml"  # B6 board/loop gates; the single stack-neutral source
REF_ADOPTER_TRACKER_GATES="profiles/adopter-tracker-gates.yml"  # TBG-TRUSTED-JOB; pull_request_target, contents: read
KIT_WORKFLOWS=".github/workflows"                         # the workflows the kit itself runs

# has_uses <workflow>: 0 if uses_scan counts a `uses` key outside block bodies (plain form or one of the refused spellings it lists), 1 if none, 2 if the scan itself failed (S6).
has_uses() { _hs=$(uses_scan "$1") || return 2; _hu=$(printf '%s\n' "$_hs" | sed -n 's/^C //p'); [ "${_hu#* }" -gt 0 ]; }

# check_pinned <workflow>: print PASS/FAIL per `uses:`; return 1 if any is not a 40-hex SHA.
# Extraction is comment-safe: only plain-form `uses:` lines are read as refs (uses_scan skips comments and block bodies), so a guidance COMMENT is never an action ref; a `uses` key it counts in any other spelling is a FAIL.
# uses_scan (SWAS-554, below) reads a body to the measured key column, as check_yaml_forms does in ci-gates.sh.
# Trailing `# vX` comments are stripped before reading the ref. SWAS-554: a `uses` in a form the plain reader cannot see (flow-style, quoted key, space before the colon) is a FAIL, not a skipped line.
check_pinned() {
  wf=$1; f=0
  if [ ! -f "$wf" ]; then echo "FAIL: missing $wf"; return 1; fi
  _us=$(uses_scan "$wf") || { echo "FAIL: $wf: the uses scan did not run (an unreadable file or a broken awk is not 'no actions to pin')"; return 1; }; refs=$(printf '%s\n' "$_us" | sed -n 's/^R //p'); _uc=$(printf '%s\n' "$_us" | sed -n 's/^C //p'); if [ "${_uc% *}" != "${_uc#* }" ]; then echo "FAIL: $wf: a uses: is written in a form this check cannot read (flow-style, quoted key or a space before the colon); write it as a plain block key"; return 1; fi
  if [ -z "$refs" ]; then echo "FAIL: no uses: found in $wf"; return 1; fi
  for r in $refs; do
    case "$r" in
      *@*) : ;;
      *) echo "FAIL: $r has no @ref"; f=1; continue ;;
    esac
    sha=${r#*@}
    case "$sha" in
      *[!0123456789abcdef]*) echo "FAIL: $r is not SHA-pinned (tag/branch)"; f=1 ;;
      *) if [ "${#sha}" -eq 40 ]; then echo "PASS: $r"; else echo "FAIL: $r is not a 40-char SHA"; f=1; fi ;;
    esac
  done
  return $f
}

# check_target <workflow> <strict>: scan one workflow.
#  strict=1 (canonical reference) — a file with NO uses: is a FAIL (it MUST declare + pin actions).
#  strict=0 (a kit workflow)      — a file with NO uses: is vacuously pinned (OK, nothing to pin).
check_target() {
  _wf=$1; _strict=$2
  if [ ! -f "$_wf" ]; then echo "FAIL: missing $_wf"; return 1; fi
  _hr=0; has_uses "$_wf" || _hr=$?; if [ "$_hr" = 2 ]; then echo "FAIL: $_wf: the uses scan did not run (an unreadable file or a broken awk is not 'no actions to pin')"; return 1; fi; if [ "$_hr" != 0 ]; then
    if [ "$_strict" = 1 ]; then echo "FAIL: $_wf declares no uses: (expected the canonical reference to pin actions)"; return 1; fi
    echo "OK: $_wf (no actions to pin)"; return 0
  fi
  echo "Action-pinning ($_wf):"
  if check_pinned "$_wf"; then echo "OK: every uses: in $_wf is SHA-pinned"; return 0; fi
  echo "FAIL: a uses: in $_wf is not SHA-pinned (see above)"; return 1
}

# check_fleet <root>: enumerate every <root>/<dir>/ci.yml (each a profile) and check it strictly
# (strict=1 — every profile MUST declare + pin actions; missing/unpinned = FAIL). Fail-closed:
# if the enumeration finds ZERO profile dirs, that is itself a FAIL ("no profiles found — cannot
# verify fleet pinning"), never a silent/vacuous pass. `find`, not a glob, so this stays correct
# under `set -eu` (no nullglob) and matches the sibling gates' enumeration convention.
check_fleet() {
  _root=$1; _ffail=0
  _profiles=$(find "$_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
  if [ -z "$_profiles" ]; then
    echo "FAIL: no profiles found under $_root — cannot verify fleet pinning"
    return 1
  fi
  for _p in $_profiles; do
    check_target "$_p/ci.yml" 1 || _ffail=1
  done
  return $_ffail
}

# uses_scan <workflow> (SWAS-554): "R <ref>" per plain-form `uses:` line, then "C <plain> <any>". Block-scalar bodies (`|` or `>` under any key) are skipped: a body ends at the first
# non-blank line indented at or below the MEASURED column of its key (for `- run: |` the key's column, not the dash's), the same rule as check_yaml_forms in ci-gates.sh. Whole-line
# comments are dropped and a trailing comment is cut. plain = lines of the form `[- ]uses: <ref>`. any = plain lines plus every line that, after an optional `- `, has `uses` (any case, optionally
# quoted, optional space before the colon) at a KEY position (the line start, or right after a `{`, `[` or `,`), where a key position may be preceded by any run of `? `, tag (`!...`) and anchor (`&...`)
# prefixes; or a quoted key holding a backslash at a key position (an escape can spell uses); or a line that opens with `?`, `&`, `*` or `!`; or any `!` or `&` right after `{`, `[` or `,` (whatever follows it,
# so a verbatim tag with a comma cannot hide a key). A `${{ ... }}` expression is replaced by one letter first, so `${{ !cancelled() }}` is no tag. A quoted VALUE that merely mentions `uses:` is not at a key position and does not count (a quoted value with a brace before it still would: fails closed).
uses_scan() {
  LC_ALL=C awk '
    { l = $0; sub("\015$", "", l) }
    inb { if (l ~ /^[ \t]*$/) next; match(l, /^[ \t]*/); if (RLENGTH > bk) next; inb = 0 }
    l ~ /^[ \t]*#/ { next }
    { match(l, /^[ \t]*/); col = RLENGTH; t = substr(l, col + 1); dcol = col
      if (t ~ /^-[ \t]+/) { sub(/^-[ \t]+/, "", t); col = length(l) - length(t) }
      if (t ~ /^[|>][-+0-9]*[ \t]*(#.*)?$/) { inb = 1; bk = dcol }
      else if (t ~ /^[^ \t]+:[ \t]*[|>][-+0-9]*[ \t]*(#.*)?$/) { inb = 1; bk = col }
      c = t; sub(/[ \t]+#.*$/, "", c)
      while ((p = index(c, "${{")) > 0) { q = index(substr(c, p), "}}"); if (q == 0) { c = substr(c, 1, p - 1); break }; c = substr(c, 1, p - 1) "X" substr(c, p + q + 1) }  # an expression like ${{ !cancelled() }} is not a tag at a key position
      lc = tolower(c)
      isplain = (l ~ /^[[:space:]]*-?[[:space:]]*uses:/)
      if (isplain || lc ~ /(^|[{,[][ \t]*)([?][ \t]+|[!&][^ \t,{}]*[ \t]+)*["\047]?uses["\047]?[ \t]*:/ || c ~ /(^|[{,[][ \t]*)([?][ \t]+|[!&][^ \t,{}]*[ \t]+)*["\047][^"\047]*\\[^"\047]*["\047][ \t]*:/ || c ~ /^\?([ \t]|$)/ || c ~ /^[&*!]/ || c ~ /[{,[][ \t]*[!&]/) any++
      if (isplain) { plain++; sub(/#.*/, "", l); n = split(l, w, /[ \t]+/); while (n > 0 && w[n] == "") n--; print "R " w[n] } }
    END { print "C " plain + 0, any + 0 }' "$1"
}

# check_labels <file>...: label coherence (ACTION-PIN-COHERENCE, #803). Read every
# `uses: <action>@<40-hex>  # <label>` as a (sha, first whitespace-delimited token after `#`) pair;
# one sha carrying two different labels is a FAIL naming both file:line locations and both labels
# (a bumped SHA with a stale version comment). A label is the first token after `#` ONLY when it
# starts `v<digit>`; a line without one (no comment, or e.g. `# nosemgrep: ...`) is ignored, and a
# trailing CR is stripped first. Reading nothing is a FAIL (zero labelled pins = a vacuous leg);
# the PASS line states how many labelled pins were read.
check_labels() {
  awk '
    { sub(/\r$/, "") }
    /^[ \t]*-?[ \t]*uses:/ {
      if (!match($0, /@[0-9a-f]+[ \t]+#/)) next
      sha = substr($0, RSTART + 1); sub(/[ \t].*/, "", sha)
      if (length(sha) != 40) next
      rest = substr($0, RSTART + RLENGTH); sub(/^[ \t]+/, "", rest)
      split(rest, tok, /[ \t]+/); lab = tok[1]
      if (lab !~ /^v[0-9]/) next
      n++
      here = FILENAME ":" FNR
      if (!(sha in first)) { first[sha] = lab; where[sha] = here; next }
      if (first[sha] != lab) {
        printf "FAIL: label mismatch for %s: %s labels it %s but %s labels it %s\n", sha, where[sha], first[sha], here, lab
        bad = 1
      }
    }
    END {
      if (bad) exit 1
      if (n == 0) { print "FAIL: label-coherence read 0 labelled pins"; exit 1 }
      printf "PASS: label-coherence: %d labelled pin(s) read, every sha carries one label\n", n
    }
  ' "$@"
}

if [ "${1:-}" = "--selftest" ]; then
  sfail=0
  # gap tree: a tag-pinned uses: must be detected (incl. a guidance comment that must be ignored)
  g=$(mktemp -d)
  printf '# pin every `uses:` to a SHA\njobs:\n  x:\n    steps:\n      - uses: actions/checkout@v4\n' > "$g/wf.yml"
  if check_pinned "$g/wf.yml" >/dev/null 2>&1; then
    echo "FAIL: selftest — tag-pin not detected"; sfail=1
  else
    echo "PASS: selftest — tag-pin detected (and comment ignored)"
  fi
  # complete tree: a 40-hex SHA-pinned uses: with a trailing # vX comment must pass
  ok=$(mktemp -d)
  printf 'jobs:\n  x:\n    steps:\n      - uses: actions/checkout@1111111111111111111111111111111111111111  # v4\n' > "$ok/wf.yml"
  if check_pinned "$ok/wf.yml" >/dev/null 2>&1; then
    echo "PASS: selftest — SHA-pin passes"
  else
    echo "FAIL: selftest — SHA-pin wrongly rejected"; sfail=1
  fi
  # broadened scope (H4b): a kit workflow with NO uses: is vacuously OK (strict=0); the canonical
  # reference with no uses: is a FAIL (strict=1).
  nouse=$(mktemp -d)
  printf 'name: x\non: [push]\njobs:\n  y:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo hi\n' > "$nouse/wf.yml"
  if check_target "$nouse/wf.yml" 0 >/dev/null 2>&1; then echo "PASS: selftest — no-uses kit workflow is vacuously pinned"; else echo "FAIL: selftest — no-uses kit workflow wrongly failed"; sfail=1; fi
  if check_target "$nouse/wf.yml" 1 >/dev/null 2>&1; then echo "FAIL: selftest — strict reference with no uses not caught"; sfail=1; else echo "PASS: selftest — strict reference with no actions detected"; fi

  # (a) fleet liveness anchor: >=2 profile-shaped dirs, each ci.yml fully SHA-pinned -> PASS.
  fa=$(mktemp -d)
  mkdir -p "$fa/alpha-lang" "$fa/beta-lang"
  printf 'jobs:\n  x:\n    steps:\n      - uses: actions/checkout@1111111111111111111111111111111111111111\n' > "$fa/alpha-lang/ci.yml"
  printf 'jobs:\n  x:\n    steps:\n      - uses: actions/checkout@2222222222222222222222222222222222222222\n' > "$fa/beta-lang/ci.yml"
  if check_fleet "$fa" >/dev/null 2>&1; then
    echo "PASS: selftest — fleet (a) liveness anchor: all-pinned fleet passes"
  else
    echo "FAIL: selftest — fleet (a) liveness anchor wrongly failed"; sfail=1
  fi

  # (b) THE load-bearing negative (beyond-typescript): same-shaped fleet, with a pinned
  # "typescript-node" dir alongside a non-typescript profile ("python") that carries a tag-pin.
  # Must FAIL, and the output must name that profile (its ci.yml path), proving the enumeration
  # reaches past typescript-node — exactly the K14 mask this closes.
  fb=$(mktemp -d)
  mkdir -p "$fb/typescript-node" "$fb/python"
  printf 'jobs:\n  x:\n    steps:\n      - uses: actions/checkout@3333333333333333333333333333333333333333\n' > "$fb/typescript-node/ci.yml"
  printf 'jobs:\n  x:\n    steps:\n      - uses: actions/checkout@v4\n' > "$fb/python/ci.yml"
  fb_out=$(check_fleet "$fb" 2>&1) && fb_rc=0 || fb_rc=1
  if [ "$fb_rc" -ne 0 ] && printf '%s' "$fb_out" | grep -q "python/ci.yml"; then
    echo "PASS: selftest — fleet (b) beyond-typescript negative: non-ts tag-pin caught and named"
  else
    echo "FAIL: selftest — fleet (b) beyond-typescript negative did not fire as designed"; sfail=1
  fi

  # (c) completeness negative (fail-closed): an empty fleet dir (no profile subdirs) must FAIL
  # with a "no profiles found" style message — never a silent pass.
  fc=$(mktemp -d)
  fc_out=$(check_fleet "$fc" 2>&1) && fc_rc=0 || fc_rc=1
  if [ "$fc_rc" -ne 0 ] && printf '%s' "$fc_out" | grep -q "no profiles found"; then
    echo "PASS: selftest — fleet (c) completeness negative: empty fleet fails closed"
  else
    echo "FAIL: selftest — fleet (c) completeness negative did not fail closed"; sfail=1
  fi

  # label coherence (ACTION-PIN-COHERENCE): temp files, removed on any exit.
  lc=$(mktemp -d)
  trap 'rm -rf "$lc"' EXIT
  trap 'rm -rf "$lc"; exit 130' INT TERM
  sha_lc=3d3c42e5aac5ba805825da76410c181273ba90b1
  # (a) the #803 negative: one sha labelled v6.0.3 on one line and v7.0.1 on another MUST FAIL,
  # naming both locations and both labels.
  printf 'jobs:\n  x:\n    steps:\n      - uses: actions/checkout@%s  # v6.0.3\n      - uses: actions/checkout@%s  # v7.0.1\n' "$sha_lc" "$sha_lc" > "$lc/mismatch.yml"
  la_out=$(check_labels "$lc/mismatch.yml" 2>&1) && la_rc=0 || la_rc=1
  if [ "$la_rc" -ne 0 ] && printf '%s' "$la_out" | grep -q "mismatch.yml:4" && printf '%s' "$la_out" | grep -q "mismatch.yml:5" \
      && printf '%s' "$la_out" | grep -q "v6.0.3" && printf '%s' "$la_out" | grep -q "v7.0.1"; then
    echo "PASS: selftest — label (a) #803 negative: one sha under two labels caught, both lines and labels named"
  else
    echo "FAIL: selftest — label (a) #803 negative did not fire as designed"; sfail=1
  fi
  # (b) control: the same sha with the same label twice (across two files) PASSES, and the output
  # proves both pairs were read.
  printf 'jobs:\n  x:\n    steps:\n      - uses: actions/checkout@%s  # v7.0.1\n' "$sha_lc" > "$lc/same1.yml"
  printf 'jobs:\n  y:\n    steps:\n      - uses: actions/checkout@%s  # v7.0.1 # nosemgrep: x\n' "$sha_lc" > "$lc/same2.yml"
  lb_out=$(check_labels "$lc/same1.yml" "$lc/same2.yml" 2>&1) && lb_rc=0 || lb_rc=1
  if [ "$lb_rc" -eq 0 ] && printf '%s' "$lb_out" | grep -q "2 labelled pin"; then
    echo "PASS: selftest — label (b) control: same sha, same label passes (2 pairs read)"
  else
    echo "FAIL: selftest — label (b) control wrongly failed or read no pairs"; sfail=1
  fi
  # (c) non-vacuity: a mismatch planted in a fixture that ALSO has unlabelled lines (and a
  # different, consistent sha) still FAILs, and the unlabelled lines are not counted as pairs.
  printf 'jobs:\n  x:\n    steps:\n      - uses: actions/checkout@%s\n      - uses: actions/setup-node@2222222222222222222222222222222222222222  # v7.1.0\n      - uses: actions/checkout@%s  # v6.0.3\n      - run: echo hi\n      - uses: actions/checkout@%s  # v7.0.1\n' "$sha_lc" "$sha_lc" "$sha_lc" > "$lc/mixed.yml"
  lc_out=$(check_labels "$lc/mixed.yml" 2>&1) && lc_rc=0 || lc_rc=1
  printf 'jobs:\n  x:\n    steps:\n      - uses: actions/checkout@%s\n      - uses: actions/setup-node@2222222222222222222222222222222222222222  # v7.1.0\n' "$sha_lc" > "$lc/unlabelled.yml"
  ld_out=$(check_labels "$lc/unlabelled.yml" 2>&1) && ld_rc=0 || ld_rc=1
  if [ "$lc_rc" -ne 0 ] && printf '%s' "$lc_out" | grep -q "mixed.yml:6" && printf '%s' "$lc_out" | grep -q "mixed.yml:8" \
      && [ "$ld_rc" -eq 0 ] && printf '%s' "$ld_out" | grep -q "1 labelled pin"; then
    echo "PASS: selftest — label (c) non-vacuity: mismatch caught amid unlabelled lines, which are ignored"
  else
    echo "FAIL: selftest — label (c) non-vacuity did not fire as designed"; sfail=1
  fi

  # (d) zero reads must FAIL: uses: lines but no version labels (none, and a non-version comment).
  printf 'jobs:\n  x:\n    steps:\n      - uses: actions/checkout@%s\n      - uses: actions/checkout@%s  # nosemgrep: some.rule\n' "$sha_lc" "$sha_lc" > "$lc/nolabels.yml"
  ldz_out=$(check_labels "$lc/nolabels.yml" 2>&1) && ldz_rc=0 || ldz_rc=1
  if [ "$ldz_rc" -ne 0 ] && printf '%s' "$ldz_out" | grep -q "label-coherence read 0 labelled pins"; then
    echo "PASS: selftest — label (d) zero-read: no labelled pins fails closed"
  else
    echo "FAIL: selftest — label (d) zero-read did not fail closed"; sfail=1
  fi
  # (e) only a version label counts: v7.0.1 beside a nosemgrep-only comment on the same sha PASSES.
  printf 'jobs:\n  x:\n    steps:\n      - uses: actions/checkout@%s  # v7.0.1\n      - uses: actions/checkout@%s  # nosemgrep: some.rule\n' "$sha_lc" "$sha_lc" > "$lc/nosem.yml"
  le_out=$(check_labels "$lc/nosem.yml" 2>&1) && le_rc=0 || le_rc=1
  if [ "$le_rc" -eq 0 ] && printf '%s' "$le_out" | grep -q "1 labelled pin"; then
    echo "PASS: selftest — label (e) non-version comment ignored (1 pair read)"
  else
    echo "FAIL: selftest — label (e) non-version comment wrongly counted"; sfail=1
  fi
  # (f) CRLF: a CRLF line and an LF line with the same sha and label PASS (2 pairs read).
  printf 'jobs:\r\n  x:\r\n    steps:\r\n      - uses: actions/checkout@%s  # v7.0.1\r\n' "$sha_lc" > "$lc/crlf.yml"
  printf 'jobs:\n  x:\n    steps:\n      - uses: actions/checkout@%s  # v7.0.1\n' "$sha_lc" > "$lc/lf.yml"
  lf_out=$(check_labels "$lc/crlf.yml" "$lc/lf.yml" 2>&1) && lf_rc=0 || lf_rc=1
  if [ "$lf_rc" -eq 0 ] && printf '%s' "$lf_out" | grep -q "2 labelled pin"; then
    echo "PASS: selftest — label (f) CRLF and LF lines agree (2 pairs read)"
  else
    echo "FAIL: selftest — label (f) CRLF handling wrong"; sfail=1
  fi

  # SWAS-554 (design §7): a `uses` written as a flow mapping, a quoted key, a key with a space before the colon, or inside a flow sequence is REFUSED, not skipped.
  # Each fixture holds a pinned plain step too, so the old line reader passed it; a cell that stays green with the refusal removed is a defect.
  pin_yf=1111111111111111111111111111111111111111
  yn=0
  for ysp in '- {uses: x@main}' '- "uses": x@main' "- 'uses': x@main" '- uses : x@main' 'steps: [{uses: x@main}]'; do
    yn=$((yn + 1))
    printf 'jobs:\n  x:\n    steps:\n      - uses: actions/checkout@%s\n      %s\n' "$pin_yf" "$ysp" > "$lc/form$yn.yml"
    yo=$(check_pinned "$lc/form$yn.yml" 2>&1) && yrc=0 || yrc=1
    if [ "$yrc" -ne 0 ] && printf '%s' "$yo" | grep -q "form$yn.yml: a uses: is written in a form this check cannot read"; then
      echo "PASS: selftest — AP$yn yaml form ($ysp) refused, not skipped"
    else
      echo "FAIL: selftest — AP$yn yaml form ($ysp) was not refused"; sfail=1
    fi
  done
  # a file whose ONLY uses is flow-style is not "no actions to pin": the kit-workflow (strict=0) path must FAIL too.
  printf 'jobs:\n  x:\n    steps:\n      - {uses: x@main}\n' > "$lc/onlyflow.yml"
  if check_target "$lc/onlyflow.yml" 0 >/dev/null 2>&1; then echo "FAIL: selftest — a file with only a flow-style uses passed as no actions to pin"; sfail=1; else echo "PASS: selftest — AP6 a file with only a flow-style uses fails (not vacuously pinned)"; fi
  # the in-body positive: uses: text inside a run: | body (any depth, one flow-style line among it) is shell text, not a step; a key right after the body (column 8 of a `- run:` step) ends it
  printf 'jobs:\n  x:\n    steps:\n      - uses: actions/checkout@%s\n      - run: |\n          echo hi\n          uses: x@v4\n          - {uses: y@main}\n        shell: bash\n' "$pin_yf" > "$lc/inbody.yml"
  if check_pinned "$lc/inbody.yml" >/dev/null 2>&1; then echo "PASS: selftest — AP7 uses: text inside a run: body is skipped"; else echo "FAIL: selftest — uses: text inside a run: body wrongly read"; sfail=1; fi
  # the body-end differential: the same text AFTER the body ends (a column-8 key, then a flow-style uses at column 8) is read, and refused
  printf 'jobs:\n  x:\n    steps:\n      - uses: actions/checkout@%s\n      - run: |\n          echo hi\n        env: {uses: y@main}\n' "$pin_yf" > "$lc/afterbody.yml"
  if check_pinned "$lc/afterbody.yml" >/dev/null 2>&1; then echo "FAIL: selftest — a flow-style uses after a body ended was skipped"; sfail=1; else echo "PASS: selftest — AP8 a flow-style uses right after a body is read and refused"; fi
  # AP9-AP12 (S4, R7): spellings the first scan did not count; each fixture holds a pinned plain step too, so the old reader passed it
  yn=8
  for ysp in '- "u\x73es": evil/a@main' '- ? uses' '- *u : x' '- Uses: evil/a@main'; do
    yn=$((yn + 1))
    printf 'jobs:\n  x:\n    steps:\n      - uses: actions/checkout@%s\n      %s\n' "$pin_yf" "$ysp" > "$lc/form$yn.yml"
    case "$ysp" in '- ? uses') printf '        : evil/a@main\n' >> "$lc/form$yn.yml" ;; esac
    yo=$(check_pinned "$lc/form$yn.yml" 2>&1) && yrc=0 || yrc=1
    if [ "$yrc" -ne 0 ] && printf '%s' "$yo" | grep -q "form$yn.yml: a uses: is written in a form this check cannot read"; then
      echo "PASS: selftest — AP$yn yaml form ($ysp) refused, not skipped"
    else
      echo "FAIL: selftest — AP$yn yaml form ($ysp) was not refused"; sfail=1
    fi
  done
  # AP17-AP20 (security F2): a tag, an explicit-key marker or an anchor before the key, and a backslash-quoted key after { or ,
  yn=16
  for ysp in '- !!str uses: evil/a@main' '- {? uses: evil/a@main}' '- {"u\x73es": evil/a@main}' '- {a: b, &k uses: x}'; do
    yn=$((yn + 1))
    printf 'jobs:\n  x:\n    steps:\n      - uses: actions/checkout@%s\n      %s\n' "$pin_yf" "$ysp" > "$lc/form$yn.yml"
    yo=$(check_pinned "$lc/form$yn.yml" 2>&1) && yrc=0 || yrc=1
    if [ "$yrc" -ne 0 ] && printf '%s' "$yo" | grep -q "form$yn.yml: a uses: is written in a form this check cannot read"; then
      echo "PASS: selftest — AP$yn yaml form ($ysp) refused, not skipped"
    else
      echo "FAIL: selftest — AP$yn yaml form ($ysp) was not refused"; sfail=1
    fi
  done
  # AP21 (automated security review of 76232e02): a verbatim tag holding a comma before the key
  printf 'jobs:\n  x:\n    steps:\n      - uses: actions/checkout@%s\n      - !<tag:yaml.org,2002:str> uses: evil/a@main\n' "$pin_yf" > "$lc/form21.yml"
  yo=$(check_pinned "$lc/form21.yml" 2>&1) && yrc=0 || yrc=1
  if [ "$yrc" -ne 0 ] && printf '%s' "$yo" | grep -q "form21.yml: a uses: is written in a form this check cannot read"; then echo "PASS: selftest — AP21 a verbatim tag with a comma before uses is refused"; else echo "FAIL: selftest — AP21 a verbatim tag with a comma before uses was not refused"; sfail=1; fi
  # AP13 (R8): a quoted VALUE that mentions uses: is not a key and is not counted; AP13b: a pinned file with a mention in a comment and a name: stays clean
  printf 'jobs:\n  x:\n    steps:\n      - name: "pin uses: to a SHA"\n        uses: actions/checkout@%s\n      - run: echo "uses: x"\n' "$pin_yf" > "$lc/mention.yml"
  if check_pinned "$lc/mention.yml" >/dev/null 2>&1; then echo "PASS: selftest — AP13 a quoted value mentioning uses: is not counted"; else echo "FAIL: selftest — AP13 a quoted value mentioning uses: wrongly refused"; sfail=1; fi
  # AP14 (S6): a scan that did not run (a failing awk on the PATH) is a FAIL, never "no actions to pin", on both entry points
  mkdir -p "$lc/stub"; printf '#!/bin/sh\nexit 2\n' > "$lc/stub/awk"; chmod +x "$lc/stub/awk"
  yo=$( (PATH="$lc/stub:$PATH"; check_target "$lc/inbody.yml" 0) 2>&1) && yrc=0 || yrc=1
  yp=$( (PATH="$lc/stub:$PATH"; check_pinned "$lc/inbody.yml") 2>&1) && yprc=0 || yprc=1
  if [ "$yrc" -ne 0 ] && [ "$yprc" -ne 0 ] && printf '%s' "$yo" | grep -q "the uses scan did not run" && printf '%s' "$yp" | grep -q "the uses scan did not run"; then
    echo "PASS: selftest — AP14 a failing scan is a FAIL on check_target and check_pinned"
  else echo "FAIL: selftest — AP14 a failing scan read as clean (check_target rc=$yrc, check_pinned rc=$yprc)"; sfail=1; fi
  # AP15/AP16 (S5, S9): the main run reads dot-named kit workflows, including one named exactly .yml; a scratch tree is run through the real entry point
  self=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
  mkdir -p "$lc/tree/profiles/a" "$lc/tree/.github/workflows"
  printf 'jobs:\n  x:\n    steps:\n      - uses: actions/checkout@%s  # v4\n' "$pin_yf" > "$lc/tree/profiles/a/ci.yml"
  for rf in ratification adopter-gates adopter-tracker-gates; do cp "$lc/tree/profiles/a/ci.yml" "$lc/tree/profiles/$rf.yml"; done
  if (cd "$lc/tree" && sh "$self" >/dev/null 2>&1); then echo "PASS: selftest — AP15 control: the scratch tree with no dot-named workflow is clean"; else echo "FAIL: selftest — AP15 control: the scratch tree is not clean"; sfail=1; fi
  tn=0
  for dn in .evil.yml .yml; do
    tn=$((tn + 1)); mkdir -p "$lc/tree$tn/profiles/a" "$lc/tree$tn/.github/workflows"
    for rf in a/ci ratification adopter-gates adopter-tracker-gates; do cp "$lc/tree/profiles/a/ci.yml" "$lc/tree$tn/profiles/$rf.yml"; done
    printf 'jobs:\n  x:\n    steps:\n      - uses: actions/checkout@v4\n' > "$lc/tree$tn/.github/workflows/$dn"
    if (cd "$lc/tree$tn" && sh "$self" >"$lc/tree$tn.out" 2>&1); then echo "FAIL: selftest — AP16 an unpinned uses in .github/workflows/$dn was not read"; sfail=1
    else echo "PASS: selftest — AP16 an unpinned uses in .github/workflows/$dn reds"; fi
  done

  [ "$sfail" -eq 0 ] && { echo "OK: action-pinning selftest"; exit 0; } || { echo "FAIL: action-pinning selftest"; exit 1; }
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: action-pinning.sh [--selftest]" >&2; exit 2 ;;
esac

rc=0
# 1) the WHOLE profile fleet (K14 — strict: every profiles/<stack>/ci.yml must declare + pin
# actions; typescript-node is just one enumerated member, not special-cased). Fail-closed: zero
# profiles found is itself a FAIL (see check_fleet).
check_fleet "profiles" || rc=1
# 1b) CP-9: the ratification gate, which ships as its own workflow (it alone re-runs on
# pull_request_review). Strict: the adopter installs it verbatim, and it is the file that carries
# a `checks: write` token, so an unpinned action here is the worst place to have one.
check_target "$REF_RATIFICATION" 1 || rc=1
# 1c) B6: the board/loop merge-time gates ship as their own workflow too, and post via checks:write
# in several jobs (gate-backlog-presence, post-ceremony-binding, post-loop-state) — strict, same as 1b.
check_target "$REF_ADOPTER_GATES" 1 || rc=1
# 1d) TBG-TRUSTED-JOB: the tracker-backed trusted job, base-defined `pull_request_target` — strict,
# same reasoning as 1b/1c (it holds a tracker credential).
check_target "$REF_ADOPTER_TRACKER_GATES" 1 || rc=1
# 2) the kit's OWN workflows (broadened in H4b): every actually-run workflow pins its actions
if [ -d "$KIT_WORKFLOWS" ]; then
  for wf in "$KIT_WORKFLOWS"/*.yml "$KIT_WORKFLOWS"/*.yaml "$KIT_WORKFLOWS"/.*.yml "$KIT_WORKFLOWS"/.*.yaml "$KIT_WORKFLOWS"/.yml "$KIT_WORKFLOWS"/.yaml; do  # dot-named files too (SWAS-554 S5, S9): a plain * skips them, and .*.yml needs a name
    [ -f "$wf" ] || continue
    check_target "$wf" 0 || rc=1
  done
fi
# 3) label coherence (ACTION-PIN-COHERENCE): over the same files (the fleet ci.yml files, the three
# REF_* profiles, the kit workflows) PLUS the two shipped docs/operations bindings (scanned for
# labels only, not pin-checked; skipped if absent), one sha must carry one version label.
lf=$(find profiles -mindepth 2 -maxdepth 2 -name ci.yml 2>/dev/null | sort)
kw=$(find "$KIT_WORKFLOWS" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null | sort)
ops=""
for _op in docs/operations/release-tag.github.yml docs/operations/sod-gate.github.yml; do
  [ -f "$_op" ] && ops="$ops $_op"
done
# shellcheck disable=SC2086
check_labels "$REF_RATIFICATION" "$REF_ADOPTER_GATES" "$REF_ADOPTER_TRACKER_GATES" $lf $kw $ops || rc=1
if [ "$rc" -eq 0 ]; then
  echo "OK: every uses: in the kit's own workflows + the whole profile fleet is SHA-pinned"
  exit 0
else
  echo "FAIL: a uses: is not SHA-pinned (see above)"
  exit 1
fi
