#!/bin/sh
# go-toolchain-coherent.sh — the Go profile's toolchain pins move as ONE set, and the set is not near end of life.
# SWAS-202 (GO-PROFILE-BASELINE-CI-RED). DESIGN: docs/architecture/2026-10-16-go-profile-baseline-ci-design.md.
#
# `go.mod` is the single source of the Go minor (X.Y). CI reads it (setup-go `go-version-file`); the Dockerfile
# tag, the linter and the docs repeat it. A field run found the profile's first push red because one pin
# (Go 1.22, past end of life) and another (a linter built with an older Go) had drifted apart in silence.
#   sh conformance/go-toolchain-coherent.sh [--eol] [--selftest]
#
# IN THE KIT (profiles/go/ exists) every rule FAILs, naming the file and both values:
#   G1  the go directive is `go X.Y` — no patch, and no `toolchain` line (a patch makes setup-go install that
#       exact old patch and brings the stdlib advisories back)
#   G2  the setup-go step uses `go-version-file: go.mod` and `check-latest: true`, with no literal `go-version:`
#   G3  the Dockerfile builder `FROM golang:<tag>` starts with `X.Y-` or equals `X.Y`
#   G4  the lint step's `version:` is v2.*, its action pin comment is `# v7` or later, and .golangci.yml says
#       `version: "2"`. LIMIT: the action's major is read from the `# vN` comment beside the sha, and a comment
#       can lie; the sha itself is bound by G6 and action-pinning.sh, and go-first-push RUNNING the action is
#       what proves it works.
#   G5  the prose agrees: profiles/go.md says `Go X.Y+` and `golang:X.Y`, scaffold/README.md says `go X.Y`
#   G6  the golangci-lint-action sha in golden-path.yml equals the one in profiles/go/ci.yml
# IN AN INCEPTED GO TREE (root go.mod, .golangci.yml, .github/workflows/ci.yml, an optional Dockerfile) the
# toolchain is the adopter's to own, so every rule is ADVISORY: a WARN with a one-line fix, rc 0, never a red
# `verify --require`. G5 and G6 read kit-only inputs and are N/A there. Off a Go tree the whole cell is N/A.
#
# --eol (drift-watch only, never per PR) compares today with an OFFLINE schedule. Go 1.N ships in year
# 2013 + floor(N/2), in February when N is even and August when N is odd (anchored on the 1st; true from 1.20),
# and 1.N is supported until 1.(N+2) ships. It WARNs from 60 days before that and goes red AT end of life.
# Deterministic and offline, so drift-watch's "red = true drift" contract holds.
# TEST SEAMS (a trusted local shell, not a security boundary): GO_TC_ROOT=<dir> in place of the repo root,
# GO_EOL_TODAY=YYYY-MM-DD in place of today.
# Exit: 0 = coherent / advisory-only / N/A · 1 = a kit rule is false, or Go is at end of life · 2 = usage.
# POSIX sh; dash-clean.
set -eu

GTC_SELF="$0"
GTC_FAILS=0
GTC_WARNS=0
GTC_SEV=FAIL

gtc_pass() { echo "PASS: $1 $2"; }
gtc_na() { echo "N/A: $1 $2"; }
gtc_bad() {  # <rule> <message> — a FAIL in the kit, a WARN in an incepted tree
  echo "$GTC_SEV: $1 $2"
  if [ "$GTC_SEV" = FAIL ]; then GTC_FAILS=$((GTC_FAILS + 1)); else GTC_WARNS=$((GTC_WARNS + 1)); fi
}

# gtc_missing <rule> <message>: a step the rule grades is absent. The KIT's profile must have it (FAIL); an
# incepted tree's pipeline is the adopter's to own (N/A).
gtc_missing() {
  if [ "$GTC_SEV" = FAIL ]; then gtc_bad "$1" "$2"; else gtc_na "$1" "$2"; fi
}

# gtc_live <file>: the file with whole-line and whitespace-anchored trailing comments removed.
gtc_live() { sed -e 's/^[[:space:]]*#.*//' -e 's/[[:space:]]#.*//' "$1"; }

# gtc_step <file> <uses-text>: the YAML step block whose `uses:` line contains <uses-text>. The block ends at
# the next list item shallower than the step's own keys.
gtc_step() {
  awk -v pat="$2" '
    { match($0, /^[ \t]*/); ind = RLENGTH }
    inb && $0 ~ /^[ \t]*- / && ind < uind { inb = 0 }
    !inb && index($0, pat) > 0 { inb = 1; uind = ind; if ($0 ~ /^[ \t]*- +uses:/) uind = ind + 2 }
    inb { print }
  ' "$1"
}

# gtc_tokens <file> <ERE>: every distinct match of the pattern, one per line.
gtc_tokens() { grep -oE -- "$2" "$1" | sort -u || true; }

# gtc_agree <label-for-messages> <file> <ERE> <expected>: 0 when the file has the token and no other value of it.
gtc_agree() {
  _found=$(gtc_tokens "$2" "$3")
  [ -n "$_found" ] && [ "$_found" = "$4" ]
}

gtc_g1() {  # <go.mod> <label>
  _val=$(awk '$1 == "go" { print $2; exit }' "$1")
  if [ -z "$_val" ]; then gtc_bad G1 "$2 has no go directive"; return; fi
  if ! printf '%s\n' "$_val" | grep -Eq '^[0-9]+\.[0-9]+$'; then
    if [ "$GTC_SEV" = FAIL ]; then
      gtc_bad G1 "$2 pins go $_val — setup-go would install exactly that patch and miss later stdlib fixes; write 'go $GTC_XY'"
    else
      GTC_WARNS=$((GTC_WARNS + 1))
      echo "WARN: $2 pins go $_val — setup-go will install exactly that patch and miss later stdlib fixes; write 'go $GTC_XY' (and drop the toolchain line) unless you mean to pin."
    fi
    return
  fi
  if awk '$1 == "toolchain" { f = 1 } END { exit f ? 0 : 1 }' "$1"; then
    gtc_bad G1 "$2 carries a toolchain line — it overrides go-version-file; drop it and keep 'go $GTC_XY'"
    return
  fi
  gtc_pass G1 "$2 declares go $GTC_XY (minor only, no toolchain line)"
}

gtc_g2() {  # <ci.yml>
  _blk=$(gtc_step "$1" 'uses: actions/setup-go@')
  if [ -z "$_blk" ]; then gtc_missing G2 "no actions/setup-go step in $1"; return; fi
  _live=$(printf '%s\n' "$_blk" | sed -e 's/^[[:space:]]*#.*//' -e 's/[[:space:]]#.*//')
  _why=""
  printf '%s\n' "$_live" | grep -Eq '^[[:space:]]*go-version-file:[[:space:]]*go\.mod[[:space:]]*$' \
    || _why="$_why no 'go-version-file: go.mod';"
  printf '%s\n' "$_live" | grep -Eq '^[[:space:]]*check-latest:[[:space:]]*true[[:space:]]*$' \
    || _why="$_why no 'check-latest: true' (setup-go would take the runner's cached, possibly old, patch);"
  if printf '%s\n' "$_live" | grep -Eq '^[[:space:]]*go-version:'; then _why="$_why a literal 'go-version:' is set;"; fi
  if [ -n "$_why" ]; then gtc_bad G2 "setup-go in $1:$_why"; return; fi
  gtc_pass G2 "setup-go in $1 reads go.mod and checks for the latest patch"
}

gtc_g3() {  # <Dockerfile> <label>
  _from=$(awk '$1 == "FROM" && $2 ~ /^golang:/ { print $2; exit }' "$1")
  if [ -z "$_from" ]; then gtc_bad G3 "$2 has no 'FROM golang:' builder stage"; return; fi
  _tag=${_from#golang:}
  case "$_tag" in
    "$GTC_XY" | "$GTC_XY"-*) gtc_pass G3 "$2 builds on golang:$_tag (go $GTC_XY)" ;;
    *) gtc_bad G3 "$2 builds on golang:$_tag but go.mod says go $GTC_XY; write golang:$GTC_XY-bookworm" ;;
  esac
}

gtc_g4() {  # <ci.yml> <.golangci.yml>
  _blk=$(gtc_step "$1" 'uses: golangci/golangci-lint-action@')
  if [ -z "$_blk" ]; then gtc_missing G4 "no golangci-lint-action step in $1"; return; fi
  _major=$(printf '%s\n' "$_blk" | sed -n '1s/.*#[[:space:]]*v\([0-9][0-9]*\).*/\1/p')
  _ver=$(printf '%s\n' "$_blk" | sed -e 's/^[[:space:]]*#.*//' -e 's/[[:space:]]#.*//' \
    | sed -n 's/^[[:space:]]*version:[[:space:]]*\(v[0-9][0-9.]*\).*/\1/p' | head -1)
  _why=""
  if [ -z "$_major" ] || [ "$_major" -lt 7 ]; then _why="$_why action pin comment is '# v${_major:-?}', need v7 or later (v2 linters);"; fi
  case "$_ver" in
    v2.*) : ;;
    *) _why="$_why lint version is '${_ver:-unset}', need v2.*;" ;;
  esac
  if [ ! -f "$2" ]; then
    _why="$_why $2 is missing;"
  elif ! gtc_live "$2" | grep -Eq '^version:[[:space:]]*"?2"?[[:space:]]*$'; then
    _why="$_why $2 does not declare version: \"2\" (a v1 config is rejected by a v2 linter);"
  fi
  if [ -n "$_why" ]; then gtc_bad G4 "lint step in $1:$_why"; return; fi
  gtc_pass G4 "lint is $_ver on action v$_major with a v2 $2"
}

gtc_g5() {  # <profiles/go.md> <scaffold/README.md>
  _ok=1
  gtc_agree G5 "$1" 'Go [0-9]+\.[0-9]+\+' "Go $GTC_XY+" || { gtc_bad G5 "$1 does not say 'Go $GTC_XY+' everywhere (found: $(gtc_tokens "$1" 'Go [0-9]+\.[0-9]+\+' | tr '\n' ' '))"; _ok=0; }
  gtc_agree G5 "$1" 'golang:[0-9]+\.[0-9]+' "golang:$GTC_XY" || { gtc_bad G5 "$1 does not say 'golang:$GTC_XY' everywhere (found: $(gtc_tokens "$1" 'golang:[0-9]+\.[0-9]+' | tr '\n' ' '))"; _ok=0; }
  gtc_agree G5 "$2" 'go [0-9]+\.[0-9]+' "go $GTC_XY" || { gtc_bad G5 "$2 does not say 'go $GTC_XY' everywhere (found: $(gtc_tokens "$2" 'go [0-9]+\.[0-9]+' | tr '\n' ' '))"; _ok=0; }
  if [ "$_ok" -eq 1 ]; then gtc_pass G5 "the profile doc and the scaffold README say $GTC_XY"; fi
}

gtc_g6() {  # <profiles/go/ci.yml> <golden-path.yml>
  _want=$(gtc_tokens "$1" 'golangci/golangci-lint-action@[0-9a-f]{40}')
  _got=$(gtc_tokens "$2" 'golangci/golangci-lint-action@[0-9a-f]{40}')
  if [ -z "$_want" ] || [ -z "$_got" ]; then
    gtc_bad G6 "no sha-pinned golangci-lint-action in $1 or $2 (go-first-push must run the profile's own action)"
  elif [ "$_want" != "$_got" ]; then
    gtc_bad G6 "$2 runs $(printf '%s' "$_got" | tr '\n' ' ')but $1 ships $(printf '%s' "$_want" | tr '\n' ' ')"
  else
    gtc_pass G6 "go-first-push runs the profile's own lint action sha"
  fi
}

# gtc_release <N>: the first day of the month Go 1.N ships. Year 2013 + floor(N/2); February when N is even,
# August when N is odd. (1.22 -> 2024-02, 1.26 -> 2026-02, 1.27 -> 2026-08.)
gtc_release() {
  _y=$((2013 + $1 / 2))
  if [ $(($1 % 2)) -eq 0 ]; then _m=02; else _m=08; fi
  echo "$_y-$_m-01"
}

# gtc_days <YYYY-MM-DD>: days since 1970-01-01 (proleptic Gregorian, civil-from-days arithmetic).
gtc_days() {
  _dy=${1%%-*}; _dr=${1#*-}; _dm=${_dr%%-*}; _dd=${_dr#*-}
  _dm=${_dm#0}; _dd=${_dd#0}
  if [ "$_dm" -le 2 ]; then _dy=$((_dy - 1)); fi
  _era=$((_dy / 400)); _yoe=$((_dy - _era * 400))
  if [ "$_dm" -ge 3 ]; then _mp=$((_dm - 3)); else _mp=$((_dm + 9)); fi   # March = month 0
  _t=$((153 * _mp + 2))
  _doy=$((_t / 5 + _dd - 1))
  _doe=$((_yoe * 365 + _yoe / 4 - _yoe / 100 + _doy))
  echo $((_era * 146097 + _doe - 719468))
}

gtc_valid_date() {  # <YYYY-MM-DD> — shape and ranges
  printf '%s\n' "$1" | grep -Eq '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$'
}

gtc_gomod_of() {  # prints the go.mod (relative to the cwd, the tree root) this tree is graded on, empty when none
  if [ -f .github/workflows/golden-path.yml ] && [ -f profiles/go/scaffold/go.mod ]; then
    echo profiles/go/scaffold/go.mod
  elif [ -f go.mod ]; then
    echo go.mod
  fi
}

gtc_xy_of() {  # <go.mod> — X.Y from the directive, empty when unreadable
  awk '$1 == "go" { print $2; exit }' "$1" | grep -Eo '^[0-9]+\.[0-9]+' || true
}

gtc_eol() {  # <root> <today>
  if ! gtc_valid_date "$2"; then echo "go-toolchain-coherent: invalid date '$2' (want YYYY-MM-DD)" >&2; return 2; fi
  cd "$1" || return 2
  _gm=$(gtc_gomod_of)
  if [ -z "$_gm" ]; then echo "N/A: not a Go tree (no profiles/go/ in the kit, no root go.mod) — no end-of-life to grade"; return 0; fi
  GTC_XY=$(gtc_xy_of "$_gm")
  _minor=${GTC_XY#1.}
  if ! printf '%s\n' "$GTC_XY" | grep -Eq '^1\.[0-9]+$' || [ "$_minor" -lt 20 ]; then
    echo "FAIL: eol cannot read a Go 1.20+ minor from $_gm (found '${GTC_XY:-nothing}')"; return 1
  fi
  _eol=$(gtc_release $((_minor + 2)))
  _left=$(($(gtc_days "$_eol") - $(gtc_days "$2")))
  if [ "$_left" -le 0 ]; then
    echo "FAIL: eol Go $GTC_XY reached end of life on $_eol (${_left#-} day(s) ago); bump go.mod, the Dockerfile tag and the linter as one set"
    return 1
  fi
  if [ "$_left" -le 60 ]; then
    echo "WARN: eol Go $GTC_XY reaches end of life on $_eol (in $_left day(s)); bump go.mod, the Dockerfile tag and the linter as one set"
    return 0
  fi
  echo "PASS: eol Go $GTC_XY is supported until $_eol ($_left day(s) left)"
}

gtc_kit_rules() {  # runs in the tree root
  gtc_g1 profiles/go/scaffold/go.mod profiles/go/scaffold/go.mod
  gtc_g2 profiles/go/ci.yml
  gtc_g3 profiles/go/Dockerfile profiles/go/Dockerfile
  gtc_g4 profiles/go/ci.yml profiles/go/scaffold/.golangci.yml
  gtc_g5 profiles/go.md profiles/go/scaffold/README.md
  gtc_g6 profiles/go/ci.yml .github/workflows/golden-path.yml
}

gtc_adopter_rules() {  # runs in the tree root
  gtc_g1 go.mod go.mod
  if [ -f .github/workflows/ci.yml ]; then
    gtc_g2 .github/workflows/ci.yml
    gtc_g4 .github/workflows/ci.yml .golangci.yml
  else
    gtc_na G2 "no .github/workflows/ci.yml (the emitted pipeline is the adopter's to own)"
    gtc_na G4 "no .github/workflows/ci.yml (the emitted pipeline is the adopter's to own)"
  fi
  if [ -f Dockerfile ]; then
    gtc_g3 Dockerfile Dockerfile
  else
    gtc_na G3 "no root Dockerfile (profiles/go/Dockerfile is COPY-&-ADAPT)"
  fi
  gtc_na G5 "kit-only input (the profile doc is pruned from an adopter)"
  gtc_na G6 "kit-only input (the kit's golden-path.yml is not exported)"
}

gtc_main() {  # <root> <mode: "" | --eol> <today>
  if [ "$2" = "--eol" ]; then gtc_eol "$1" "$3"; return $?; fi
  cd "$1" || return 2
  _gm=$(gtc_gomod_of)
  if [ -z "$_gm" ]; then
    echo "N/A: not a Go tree (no profiles/go/ in the kit, no root go.mod) — nothing to grade"
    return 0
  fi
  GTC_XY=$(gtc_xy_of "$_gm")
  if [ -z "$GTC_XY" ]; then
    echo "FAIL: $_gm has no readable go directive"
    return 1
  fi
  if [ "$_gm" = go.mod ]; then
    GTC_SEV=WARN
    gtc_adopter_rules
    echo "OK: go-toolchain-coherent (incepted tree, advisory only) — $GTC_WARNS warning(s) for go $GTC_XY"
    return 0
  fi
  gtc_kit_rules
  if [ "$GTC_FAILS" -gt 0 ]; then
    echo "FAIL: go-toolchain-coherent — $GTC_FAILS rule(s) false; the Go pins must move as one set (go.mod, setup-go, Dockerfile, linter)"
    return 1
  fi
  echo "OK: go-toolchain-coherent — G1-G6 hold for go $GTC_XY"
}

# ------------------------------------------------------------------------------------------------ selftest
# Everything from this line to the end of the file is the ORACLE region (conformance/non-vacuity.sh mutates
# only the lines above the first `selftest()`). The fixtures and the verdict accumulator below must stay
# under it: a verdict-flag flip in gtc_expect, if mutable, would let the selftest pass whatever the check does.
selftest() { gtc_selftest; }

gtc_good_kit() {  # <dir> — a minimal coherent kit tree
  mkdir -p "$1/profiles/go/scaffold" "$1/.github/workflows"
  printf 'module example.com/app\n\ngo 1.27\n' > "$1/profiles/go/scaffold/go.mod"
  {
    echo "jobs:"
    echo "  ci:"
    echo "    steps:"
    echo "      - uses: actions/setup-go@40f1582b2485089dde7abd97c1529aa768e1baff  # v5"
    echo "        with:"
    echo "          go-version-file: go.mod"
    echo "          check-latest: true"
    echo "      - name: Lint"
    echo "        id: gate-lint"
    echo "        uses: golangci/golangci-lint-action@ba0d7d2ec06a0ea1cb5fa41b2e4a3ab91d21278a  # v9.3.0"
    echo "        with:"
    echo "          version: v2.14.0   # pin the linter"
    echo "      - name: Type-check"
    echo "        run: go vet ./..."
  } > "$1/profiles/go/ci.yml"
  printf 'version: "2"\nlinters:\n  enable:\n    - govet\n' > "$1/profiles/go/scaffold/.golangci.yml"
  printf '# syntax=docker/dockerfile:1\nFROM golang:1.27-bookworm AS builder\nFROM gcr.io/distroless/static-debian12:nonroot AS runtime\n' > "$1/profiles/go/Dockerfile"
  printf '**Stack:** Go 1.27+ · net/http\n- container: add a devcontainer against `golang:1.27` if desired\n' > "$1/profiles/go.md"
  printf '| `go.mod` | `module example.com/app`, `go 1.27`, stdlib-only |\n' > "$1/profiles/go/scaffold/README.md"
  {
    echo "jobs:"
    echo "  go-first-push:"
    echo "    steps:"
    echo "      - uses: golangci/golangci-lint-action@ba0d7d2ec06a0ea1cb5fa41b2e4a3ab91d21278a  # v9.3.0"
  } > "$1/.github/workflows/golden-path.yml"
}

gtc_good_adopter() {  # <dir> — an incepted Go tree, coherent, no root Dockerfile
  mkdir -p "$1/.github/workflows"
  printf 'module example.com/app\n\ngo 1.27\n' > "$1/go.mod"
  cp "$2/profiles/go/ci.yml" "$1/.github/workflows/ci.yml"
  cp "$2/profiles/go/scaffold/.golangci.yml" "$1/.golangci.yml"
}

gtc_mut() {  # <dir> <relfile> <sed-expr> — rewrite one fixture file in place
  sed -e "$3" "$1/$2" > "$1/$2.new" && mv "$1/$2.new" "$1/$2"
}

gtc_ins() {  # <dir> <relfile> <after-text> <new-line> — insert one line after the first line containing the text
  env GTC_M="$3" GTC_L="$4" awk '{ print } !d && index($0, ENVIRON["GTC_M"]) > 0 { print ENVIRON["GTC_L"]; d = 1 }' "$1/$2" > "$1/$2.new" \
    && mv "$1/$2.new" "$1/$2"
}

gtc_expect() {  # <label> <want-rc> <want-regex> <output> <rc> — one selftest verdict
  _l=$1; _wr=$2; _wx=$3; _o=$4; _r=$5
  if [ "$_r" = "$_wr" ] && printf '%s\n' "$_o" | grep -Eq -- "$_wx"; then
    echo "PASS: selftest — $_l"
  else
    echo "FAIL: selftest — $_l (rc $_r, wanted rc $_wr matching: $_wx)"
    printf '%s\n' "$_o" | sed 's/^/    | /'
    GTC_ST_BAD=1
  fi
}

gtc_run_case() {  # <label> <want-rc> <want-regex> <root> <mode> <today>
  if _out=$(gtc_main "$4" "$5" "$6" 2>&1); then _rc=0; else _rc=$?; fi
  gtc_expect "$1" "$2" "$3" "$_out" "$_rc"
}

gtc_selftest() {
  GTC_ST_BAD=0
  T=$(mktemp -d "${TMPDIR:-/tmp}/gtc.XXXXXX")
  trap 'rm -rf "$T"' EXIT INT TERM
  K="$T/kit"; gtc_good_kit "$K"

  # --- the kit face: one good fixture, one load-bearing negative per rule
  gtc_run_case "kit good tree is coherent" 0 '^OK: go-toolchain-coherent' "$K" "" ""
  for _n in G1 G2 G3 G4 G5 G6; do
    gtc_run_case "kit good tree passes $_n" 0 "^PASS: $_n " "$K" "" ""
  done

  W="$T/g1a"; cp -R "$K" "$W"; gtc_mut "$W" profiles/go/scaffold/go.mod 's/^go 1.27$/go 1.27.3/'
  gtc_run_case "G1 patch-pinned directive FAILs naming file and value" 1 'FAIL: G1 .*scaffold/go\.mod.*1\.27\.3' "$W" "" ""
  W="$T/g1b"; cp -R "$K" "$W"; echo "toolchain go1.27.3" >> "$W/profiles/go/scaffold/go.mod"
  gtc_run_case "G1 toolchain line FAILs" 1 'FAIL: G1 .*toolchain' "$W" "" ""
  W="$T/g2a"; cp -R "$K" "$W"; gtc_mut "$W" profiles/go/ci.yml "s/go-version-file: go.mod/go-version: '1.27'/"
  gtc_run_case "G2 literal go-version FAILs" 1 'FAIL: G2 ' "$W" "" ""
  W="$T/g2b"; cp -R "$K" "$W"; gtc_mut "$W" profiles/go/ci.yml '/check-latest/d'
  gtc_run_case "G2 missing check-latest FAILs" 1 'FAIL: G2 .*check-latest' "$W" "" ""
  W="$T/g2c"; cp -R "$K" "$W"; gtc_ins "$W" profiles/go/ci.yml 'go-version-file:' "          go-version: '1.22'"
  gtc_run_case "G2 a literal go-version beside go-version-file FAILs" 1 'FAIL: G2 .*literal' "$W" "" ""
  W="$T/g2d"; cp -R "$K" "$W"; gtc_mut "$W" profiles/go/ci.yml 's/check-latest: true/check-latest: false/'
  gtc_run_case "G2 check-latest: false FAILs" 1 'FAIL: G2 .*check-latest' "$W" "" ""
  W="$T/g2e"; cp -R "$K" "$W"; gtc_mut "$W" profiles/go/ci.yml 's/go-version-file: go.mod/go-version-file: .go-version/'
  gtc_run_case "G2 go-version-file pointing elsewhere FAILs" 1 'FAIL: G2 .*go-version-file' "$W" "" ""
  W="$T/g2f"; cp -R "$K" "$W"; gtc_mut "$W" profiles/go/ci.yml '/actions\/setup-go/,/check-latest/d'
  gtc_run_case "G2 a kit profile with no setup-go step FAILs (N/A is for incepted trees only)" 1 'FAIL: G2 .*no actions/setup-go' "$W" "" ""
  W="$T/g3b"; cp -R "$K" "$W"; printf 'FROM scratch\n' > "$W/profiles/go/Dockerfile"
  gtc_run_case "G3 no FROM golang builder stage FAILs" 1 'FAIL: G3 .*FROM golang' "$W" "" ""
  W="$T/g3"; cp -R "$K" "$W"; gtc_mut "$W" profiles/go/Dockerfile 's/golang:1.27-bookworm/golang:1.26-bookworm/'
  gtc_run_case "G3 mismatched builder tag FAILs naming both values" 1 'FAIL: G3 .*1\.26.*1\.27' "$W" "" ""
  W="$T/g4a"; cp -R "$K" "$W"; gtc_mut "$W" profiles/go/ci.yml 's/version: v2.14.0/version: v1.62.2/'
  gtc_run_case "G4 v1 linter version FAILs" 1 'FAIL: G4 .*v1\.62\.2' "$W" "" ""
  W="$T/g4b"; cp -R "$K" "$W"; gtc_mut "$W" profiles/go/ci.yml 's/# v9.3.0/# v6/'
  gtc_run_case "G4 old action major FAILs" 1 'FAIL: G4 .*v6' "$W" "" ""
  W="$T/g4c"; cp -R "$K" "$W"; gtc_mut "$W" profiles/go/scaffold/.golangci.yml '/^version:/d'
  gtc_run_case "G4 v1 golangci config FAILs" 1 'FAIL: G4 .*golangci\.yml' "$W" "" ""
  W="$T/g5a"; cp -R "$K" "$W"; gtc_mut "$W" profiles/go.md 's/Go 1.27+/Go 1.22+/'
  gtc_run_case "G5 stale profile doc FAILs" 1 'FAIL: G5 .*go\.md' "$W" "" ""
  W="$T/g5b"; cp -R "$K" "$W"; gtc_mut "$W" profiles/go/scaffold/README.md 's/go 1.27/go 1.22/'
  gtc_run_case "G5 stale scaffold README FAILs" 1 'FAIL: G5 .*README' "$W" "" ""
  W="$T/g6a"; cp -R "$K" "$W"; gtc_mut "$W" .github/workflows/golden-path.yml 's/ba0d7d2ec06a0ea1cb5fa41b2e4a3ab91d21278a/55c2c1448f86e01eaae002a5a3a9624417608d84/'
  gtc_run_case "G6 sha mismatch FAILs" 1 'FAIL: G6 ' "$W" "" ""
  W="$T/g6b"; cp -R "$K" "$W"; gtc_mut "$W" .github/workflows/golden-path.yml '/golangci-lint-action/d'
  gtc_run_case "G6 go-first-push without the lint action FAILs" 1 'FAIL: G6 ' "$W" "" ""
  W="$T/g6c"; cp -R "$K" "$W"; gtc_mut "$W" .github/workflows/golden-path.yml '/golangci-lint-action/d'; gtc_mut "$W" profiles/go/ci.yml '/golangci-lint-action/d'
  gtc_run_case "G6 no pinned lint action on either side FAILs (empty is not equal)" 1 'FAIL: G6 ' "$W" "" ""

  # --- the adopter face: every rule advisory
  A="$T/adopter"; gtc_good_adopter "$A" "$K"
  gtc_run_case "adopter good tree: OK, root Dockerfile absent is N/A" 0 '^N/A: G3 .*no root Dockerfile' "$A" "" ""
  W="$T/a1"; cp -R "$A" "$W"; gtc_mut "$W" go.mod 's/^go 1.27$/go 1.27.3/'
  gtc_run_case "adopter patch directive WARNs, rc 0, with the fix" 0 "WARN: go.mod pins go 1\\.27\\.3 .*write 'go 1\\.27'" "$W" "" ""
  W="$T/a1b"; cp -R "$A" "$W"; echo "toolchain go1.27.3" >> "$W/go.mod"
  gtc_run_case "adopter toolchain line WARNs, rc 0" 0 'WARN: G1 .*toolchain' "$W" "" ""
  W="$T/a1c"; cp -R "$A" "$W"; gtc_mut "$W" .github/workflows/ci.yml '/actions\/setup-go/,/check-latest/d'
  gtc_run_case "adopter without setup-go stays N/A, rc 0" 0 '^N/A: G2 ' "$W" "" ""
  W="$T/a2"; cp -R "$A" "$W"; printf 'FROM golang:1.26-bookworm\n' > "$W/Dockerfile"
  gtc_run_case "adopter Dockerfile mismatch WARNs, rc 0" 0 'WARN: G3 ' "$W" "" ""
  W="$T/a3"; cp -R "$A" "$W"; gtc_mut "$W" .github/workflows/ci.yml 's/version: v2.14.0/version: v1.62.2/'
  gtc_run_case "adopter v1 linter WARNs, rc 0" 0 'WARN: G4 ' "$W" "" ""
  W="$T/a4"; cp -R "$A" "$W"; gtc_mut "$W" .github/workflows/ci.yml '/check-latest/d'
  gtc_run_case "adopter missing check-latest WARNs, rc 0" 0 'WARN: G2 ' "$W" "" ""
  gtc_run_case "adopter good tree reads G5 and G6 as N/A" 0 '^N/A: G5 ' "$A" "" ""
  W="$T/off"; mkdir -p "$W"
  gtc_run_case "off a Go tree the whole cell is N/A" 0 '^N/A: ' "$W" "" ""

  # --- --eol: the offline schedule, fixed dates
  # The regression witness for the lens read's must-fix 1: the old formula (2014 + N/2 style) gave 2014 for both.
  gtc_expect "formula: release(1.26) is 2026-02-01, release(1.27) is 2026-08-01, release(1.22) is 2024-02-01" 0 \
    '^2026-02-01 2026-08-01 2024-02-01$' "$(printf '%s %s %s' "$(gtc_release 26)" "$(gtc_release 27)" "$(gtc_release 22)")" 0
  gtc_run_case "eol go 1.27, 61 days before: PASS" 0 '^PASS: eol ' "$K" --eol 2027-06-01
  gtc_run_case "eol go 1.27, exactly 60 days before: WARN" 0 '^WARN: eol ' "$K" --eol 2027-06-02
  gtc_run_case "eol go 1.27, 31 days before: WARN, rc 0" 0 '^WARN: eol .*2027-08-01' "$K" --eol 2027-07-01
  gtc_run_case "eol go 1.27, the day before: WARN" 0 '^WARN: eol ' "$K" --eol 2027-07-31
  gtc_run_case "eol go 1.27, on end of life: FAIL" 1 '^FAIL: eol .*2027-08-01' "$K" --eol 2027-08-01
  W="$T/old"; cp -R "$K" "$W"; gtc_mut "$W" profiles/go/scaffold/go.mod 's/^go 1.27$/go 1.22/'
  gtc_run_case "eol the field: go 1.22 at 2026-10-14 FAILs" 1 '^FAIL: eol .*2025-02-01' "$W" --eol 2026-10-14
  gtc_run_case "eol reads an adopter tree's root go.mod" 0 '^PASS: eol ' "$A" --eol 2027-01-01
  gtc_run_case "eol off a Go tree is N/A" 0 '^N/A: ' "$T/off" --eol 2027-01-01
  gtc_run_case "eol refuses a malformed date" 2 'invalid date' "$K" --eol "2027-13-45"
  if _out=$(env GO_TC_ROOT="$K" GO_EOL_TODAY=2027-08-01 sh "$GTC_SELF" --eol 2>&1); then _rc=0; else _rc=$?; fi
  gtc_expect "eol takes the date from GO_EOL_TODAY and the root from GO_TC_ROOT" 1 '^FAIL: eol ' "$_out" "$_rc"

  # --- end to end through the script's REAL exit path (a subprocess, not a helper's return code): a known-bad
  # fixture must exit non-zero AND print the FAIL line; the good one must exit 0.
  W="$T/e2e"; cp -R "$K" "$W"; gtc_mut "$W" profiles/go/Dockerfile 's/golang:1.27-bookworm/golang:1.26-bookworm/'
  if _out=$(env GO_TC_ROOT="$W" sh "$GTC_SELF" 2>&1); then _rc=0; else _rc=$?; fi
  gtc_expect "e2e: the script process exits 1 and prints the FAIL line on a bad tree" 1 '^FAIL: go-toolchain-coherent' "$_out" "$_rc"
  if _out=$(env GO_TC_ROOT="$K" sh "$GTC_SELF" 2>&1); then _rc=0; else _rc=$?; fi
  gtc_expect "e2e: the script process exits 0 and prints OK on the good tree" 0 '^OK: go-toolchain-coherent' "$_out" "$_rc"

  if [ "$GTC_ST_BAD" -eq 0 ]; then echo "OK: go-toolchain-coherent selftest"; return 0; fi
  echo "FAIL: go-toolchain-coherent selftest"; return 1
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  "") GTC_MODE="" ;;
  --eol) GTC_MODE="--eol" ;;
  *) echo "usage: go-toolchain-coherent.sh [--eol] [--selftest]" >&2; exit 2 ;;
esac
GTC_ROOT=${GO_TC_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
GTC_TODAY=${GO_EOL_TODAY:-$(date -u +%Y-%m-%d)}
gtc_main "$GTC_ROOT" "$GTC_MODE" "$GTC_TODAY"
