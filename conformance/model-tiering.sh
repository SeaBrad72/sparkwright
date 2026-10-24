#!/bin/sh
# model-tiering.sh — KW20(b) claim verifier: the model-tier resolver enforces pins + floors +
# fail-closed, and the policy/resolver are agent-immutable (control-plane).
#
# SCOPE — a green run proves the resolver's DECISION LOGIC is correct + non-vacuous and the guard
# lock is PRESENT. It does NOT prove any harness binds the abstract tier to a real model call
# (that is the per-harness adapter's job, Slice 2 / NATIVE). Necessary, not sufficient.
#
# Usage: sh conformance/model-tiering.sh [--require] | --selftest
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
MODEL_TIERS_CONFIG="$ROOT/.kit/model-tiers.conf"; export MODEL_TIERS_CONFIG
fail=0
FXL="$ROOT/conformance/fixtures/model-vendor-lock"

# ---- the vendor lock (SWAS-303a, docs/architecture/2026-10-18-model-per-seat-design.md section 7) ---------
# Keeps vendor model names OUT of every kit-shipped seat-binding surface. The one sanctioned place for a model
# name is the project's own .kit/model-map.conf.
# SCOPE CEILING, stated plainly. The lock reads ONLY: .kit/*.conf other than the map, agents/*.agent.md,
# skills/*/SKILL.md, templates/* (two levels), START-HERE.md and AGENTS.md for vendor tokens, and the front matter
# of .claude/agents/*.md and adapters/*/(agents/*.md|*.agent.md) for a model: key. It does NOT read agent BODIES,
# CLAUDE.md, DEVELOPMENT-*.md, profiles/, docs/, or nested .claude/agents/**, and prose that names a provider as a
# HARNESS fit dimension (docs/operations/harness-adapters.md) is the neutrality recipe working, not a seat binding.
# A token list catches the names it knows: a brand-new vendor model name that is neither in the project's own map
# nor in conformance/model-vendor-tokens.txt passes (claude3, o3, grok and qwen, for example, are not listed), and a
# map value with a character outside [A-Za-z0-9._-] is not added to the token set. The coverage is left as designed.
# The export leg reads .gitattributes directly (last-match-wins overrides are not modelled).
# THE ONE-RELEASE EPOCH (owner ruling Q3 a, MINOR: nothing reds on upgrade). On a tree whose map has no decision=
# line (an adopter's pre-303a map, or no map) a finding on legs 1-2 is a WARN, rc 0; a decided tree FAILs. The next
# release turns the WARN into a FAIL and gets its own semver call. Leg 3 (the kit's export) is kit-only and strict.
# A read that cannot be completed (an unreadable file, a malformed token fragment, no family list beside a bound
# map) is UNVERIFIED, never PASS.

# vendor_tokens ROOT — an ERE alternation: (i) every non-unset value of the project's own map keys, which is
# self-maintaining as models change, plus (ii) the family list. Empty output means the token set is empty.
vendor_tokens() {
  _vt=""
  if [ -f "$1/.kit/model-map.conf" ]; then
    while IFS= read -r _v; do
      case "$_v" in unset|''|*[!A-Za-z0-9._-]*) continue ;; esac
      _vt="$_vt|$(printf '%s' "$_v" | sed 's/\./\\./g')"
    done <<EOF_VT
$(grep -E '^(apex|deep|fast|light|profile\.[a-z]+)=' "$1/.kit/model-map.conf" | sed 's/^[^=]*=//; s/[[:space:]#].*//')
EOF_VT
  fi
  if [ -f "$1/conformance/model-vendor-tokens.txt" ]; then
    while IFS= read -r _l; do
      case "$_l" in ''|'#'*) continue ;; esac
      _vt="$_vt|$_l"
    done < "$1/conformance/model-vendor-tokens.txt"
  fi
  printf '%s' "${_vt#|}"
}

# map_bound ROOT — does any canonical tier key carry a real (non-unset) value?
map_bound() {
  grep -E '^(apex|deep|fast|light|profile\.[a-z]+)=' "$1/.kit/model-map.conf" 2>/dev/null | sed 's/^[^=]*=//; s/[[:space:]#].*//' | grep -q -v -e '^unset$' -e '^$'
}

# map_malformed ROOT — print the first line that is neither a comment, blank, nor canonical key=value (S3). A line
# such as " deep=opus" or "deep =opus" must never be read as an unbound map.
map_malformed() {
  grep -n -v -E '^([[:space:]]*#.*|[[:space:]]*|[a-z][a-z0-9.-]*=[^[:space:]]*([[:space:]]+#.*)?)$' "$1/.kit/model-map.conf" 2>/dev/null | head -1
}

# lock_check ROOT KITTREE(1|0) — 0 PASS, 1 FAIL, 2 UNVERIFIED. KITTREE=1 arms the export leg (the kit's own tree).
lock_check() {
  _r=$1; _kit=$2; _bad=0; _warn=0; _unv=0; _n=0
  # the epoch keys on a RECORDED decision (decision=D-...); the shipped template's decision=none records nothing
  _epoch=1; if grep -q -E '^decision=D-' "$_r/.kit/model-map.conf" 2>/dev/null; then _epoch=0; fi
  _tok=$(vendor_tokens "$_r")
  if [ -z "$_tok" ]; then
    echo "UNVERIFIED: vendor lock - the token set is empty (no bound map value, no family list); an empty set proves nothing"
    return 2
  fi
  if map_bound "$_r" && [ ! -f "$_r/conformance/model-vendor-tokens.txt" ]; then
    echo "UNVERIFIED: vendor lock - the map binds a model but conformance/model-vendor-tokens.txt is missing; the token set is only the map's own"
    return 2
  fi
  _re="(^|[^A-Za-z0-9])($_tok)([^A-Za-z]|\$)"
  _pg=0; printf 'x\n' | grep -E "$_re" >/dev/null 2>&1 || _pg=$?
  if [ "$_pg" -ge 2 ]; then
    echo "UNVERIFIED: vendor lock - the token set is not a valid pattern (a malformed fragment in conformance/model-vendor-tokens.txt)"
    return 2
  fi
  # a finding is a FAIL on a decided tree and a one-release WARN on a tree whose map has no decision= line
  _finding() { if [ "$_epoch" = 1 ]; then echo "WARN: $1 (a failure from the next release; record your mapping)"; _warn=1; else echo "FAIL: $1"; _bad=1; fi; }
  # 1. every .kit/*.conf except the map, then the agent/skill/template/entry surfaces: no vendor token
  for _f in "$_r"/.kit/*.conf "$_r"/agents/*.agent.md "$_r"/skills/*/SKILL.md "$_r"/templates/* "$_r"/templates/*/* \
            "$_r/START-HERE.md" "$_r/AGENTS.md"; do
    [ -f "$_f" ] || continue
    case "$_f" in */.kit/model-map.conf) continue ;; esac
    _n=$((_n + 1))
    if [ ! -r "$_f" ]; then echo "UNVERIFIED: ${_f#"$_r"/} is not readable"; _unv=1; continue; fi
    _g=0; grep -n -i -E "$_re" "$_f" >/dev/null 2>&1 || _g=$?
    if [ "$_g" = 0 ]; then
      _finding "vendor model name in a seat-binding surface: ${_f#"$_r"/}: $(grep -n -i -E "$_re" "$_f" | head -1 | cut -c1-120)"
    elif [ "$_g" -ge 2 ]; then   # not load-bearing alone: the pattern pre-check above already catches a bad pattern; kept as defence in depth
      echo "UNVERIFIED: ${_f#"$_r"/} could not be read by grep (rc $_g)"; _unv=1
    fi
  done
  # 2. agent-definition front matter: a model: key is allowed only as `inherit` (SD4: bound at dispatch, via the map)
  for _f in "$_r"/.claude/agents/*.md "$_r"/adapters/*/agents/*.md "$_r"/adapters/*/*.agent.md; do
    [ -f "$_f" ] || continue
    _n=$((_n + 1))
    if [ ! -r "$_f" ]; then echo "UNVERIFIED: ${_f#"$_r"/} is not readable"; _unv=1; continue; fi
    _mv=$(awk 'NR==1 && $0!="---" {exit} NR>1 && $0=="---" {exit} NR>1 {print}' "$_f" | grep -i -E '^model[[:space:]]*:' | head -1 | sed 's/^[^:]*:[[:space:]]*//; s/[[:space:]]*$//')
    if [ -n "$_mv" ] && [ "$_mv" != inherit ]; then
      _finding "${_f#"$_r"/} binds a model in its front matter (model: $_mv); only 'inherit' is allowed - the model is bound at dispatch through the map"
    fi
  done
  # 3. the kit's own tree only: its map is export-ignored (an adopter's tree has no such line to keep)
  if [ "$_kit" = 1 ]; then
    _n=$((_n + 1))
    if ! grep -E '^\.kit/model-map\.conf[[:space:]]+export-ignore([[:space:]]|$)' "$_r/.gitattributes" >/dev/null 2>&1; then
      echo "FAIL: .gitattributes does not export-ignore .kit/model-map.conf (the kit's own mapping would ship to every adopter)"
      _bad=1
    fi
  fi
  if [ "$_bad" = 1 ]; then return 1; fi
  if [ "$_unv" = 1 ]; then echo "UNVERIFIED: vendor lock - at least one surface could not be read"; return 2; fi
  if [ "$_warn" = 1 ]; then echo "WARN: vendor lock - $_n surfaces read; findings above are warnings until the map records a decision="; return 0; fi
  echo "PASS: vendor lock - $_n surfaces read, none names a vendor model outside the map"; return 0
}

# decision_check ROOT — a map that binds any tier cites a decision= that resolves to a ledger entry (section 6.1).
# An existing adopter map with NO decision= line WARNs (rc 0) for one release, then fails; the CHANGELOG lists
# "record your model mapping" as the upgrade act. A decision= line that does not resolve fails at once.
decision_check() {
  _map="$1/.kit/model-map.conf"
  if [ ! -f "$_map" ]; then echo "PASS: no .kit/model-map.conf - single-model, nothing decided"; return 0; fi
  _has=0; if grep -q -E '^decision=' "$_map"; then _has=1; fi
  # S3: a line that is not a comment or canonical key=value is malformed, never read as an unbound map
  _bad_line=$(map_malformed "$1")
  if [ -n "$_bad_line" ]; then
    if [ "$_has" = 0 ]; then
      echo "WARN: .kit/model-map.conf has a malformed line ($_bad_line) and no decision= line. This warns for one release and then fails: write keys as key=value at the start of the line."
      return 0
    fi
    echo "FAIL: .kit/model-map.conf has a malformed line ($_bad_line); write keys as key=value at the start of the line"; return 1
  fi
  if ! map_bound "$1"; then
    echo "PASS: every value in .kit/model-map.conf is unset - single-model, nothing decided"; return 0
  fi
  if [ "$_has" = 0 ]; then
    echo "WARN: .kit/model-map.conf binds a model but has no decision= line. This warns for one release and then fails: record the mapping in docs/governance/DECISIONS.md and add decision=, recorded= and revisit-by= to the map."
    return 0
  fi
  _id=$(grep -E '^decision=' "$_map" | head -1 | sed 's/^decision=//; s/[[:space:]#].*//')
  # S1: exactly D-dddddd-n, matched as a FIXED string at the start of a ledger entry; no pattern syntax ever reaches grep
  if ! printf '%s\n' "$_id" | grep -q -E '^D-[0-9]{6}-[0-9]+$'; then
    echo "FAIL: .kit/model-map.conf binds a model but decision='$_id' is not a DECISIONS entry id (exactly D-YYMMDD-N)"; return 1
  fi
  if awk -v id="\`$_id\`" 'BEGIN { n = length(id) }
       substr($0, 1, n) == id || substr($0, 1, n + 2) == "**" id { f = 1 }
       /^#+ / { s = $0; sub(/^#+ /, "", s); if (substr(s, 1, n) == id) f = 1 }
       END { exit f ? 0 : 1 }' "$1/docs/governance/DECISIONS.md" 2>/dev/null; then
    echo "PASS: .kit/model-map.conf cites $_id, which resolves to a DECISIONS entry"; return 0
  fi
  echo "FAIL: .kit/model-map.conf cites $_id, which resolves to no entry in docs/governance/DECISIONS.md"; return 1
}

# ---- selftest (SWAS-303a): the vendor lock and the decision= record, graded on fixtures ----------------
# assemble FIXTURE DEST — rebuild a kit-shaped tree from a fixture. The fixture stores its files under
# undotted, non-control-plane names; this maps them to the real paths inside a mktemp tree.
assemble() {
  _s="$FXL/$1"; _d=$2
  for _m in map.conf:.kit/model-map.conf tiers.conf:.kit/model-tiers.conf budget.conf:.kit/budget.conf \
    agent-engineer.md:.claude/agents/engineer.md agent-reviewer.md:.claude/agents/reviewer.md \
    neutral-agent.md:agents/engineer.agent.md skill.md:skills/plan/SKILL.md template.md:templates/EXAMPLE-TEMPLATE.md \
    start-here.md:START-HERE.md agents-md.md:AGENTS.md tokens.txt:conformance/model-vendor-tokens.txt \
    decisions.md:docs/governance/DECISIONS.md gitattributes.txt:.gitattributes; do
    [ -f "$_s/${_m%%:*}" ] || continue
    mkdir -p "$_d/$(dirname "${_m#*:}")"
    cp "$_s/${_m%%:*}" "$_d/${_m#*:}"
  done
}

selftest() {
  st=0; base=$(mktemp -d)
  mt_cell() {  # mt_cell NAME WANT_RC CMD... — runs CMD, compares its exit code, keeps its output in LAST_OUT
    _n=$1; _w=$2; shift 2; _rc=0
    LAST_OUT=$("$@" 2>&1) || _rc=$?
    if [ "$_rc" = "$_w" ]; then echo "PASS: $_n (rc $_rc)"; else echo "FAIL: $_n - wanted rc $_w got $_rc"; st=1; fi
  }
  said() {  # said NAME PATTERN — LAST_OUT must carry PATTERN (the verdict word, not just the rc)
    case $LAST_OUT in *"$2"*) echo "PASS: $1 says $2" ;; *) echo "FAIL: $1 did not say $2 (got: $LAST_OUT)"; st=1 ;; esac
  }
  drop() { grep -v "$2" "$1" > "$1.tmp"; mv "$1.tmp" "$1"; }   # strip lines of an in-fixture file

  # --- the lock (section 7). Liveness first: a clean tree passes, an empty token set is UNVERIFIED. ---
  assemble clean "$base/clean"
  mt_cell "lock: clean fixture PASS (liveness)" 0 lock_check "$base/clean" 1
  said "lock: clean fixture" "PASS"
  assemble empty-tokens "$base/empty"
  mt_cell "lock: empty token set UNVERIFIED, never PASS" 2 lock_check "$base/empty" 1
  said "lock: empty token set" "UNVERIFIED"

  # Negative 1 (load-bearing, one per control, D-241003-2): a vendor token in a .kit/*.conf other than the map.
  # Kills the mutant "a .kit/*.conf scan that always returns clean".
  assemble clean "$base/neg1"; printf 'fast=sonnet\n' >> "$base/neg1/.kit/model-tiers.conf"
  mt_cell "lock: fast=sonnet in model-tiers.conf FAIL (load-bearing)" 1 lock_check "$base/neg1" 1
  # Negative 2: a separate read path - an agent definition's front matter may carry model: only as inherit.
  assemble clean "$base/neg2"
  sed 's/^model: inherit$/model: opus/' "$base/neg2/.claude/agents/engineer.md" > "$base/e.md"; cp "$base/e.md" "$base/neg2/.claude/agents/engineer.md"
  mt_cell "lock: model: opus in engineer.md FAIL" 1 lock_check "$base/neg2" 1
  # Negative 3: the export leg - the kit's own map must be export-ignored.
  assemble clean "$base/neg3"; drop "$base/neg3/.gitattributes" 'model-map.conf'
  mt_cell "lock: export-ignore line deleted FAIL" 1 lock_check "$base/neg3" 1
  mt_cell "lock: export leg is the kit tree only (adopter tree passes)" 0 lock_check "$base/neg3" 0
  # The token set is a UNION: a token that only the project's map supplies is still held.
  assemble clean "$base/neg4"; drop "$base/neg4/conformance/model-vendor-tokens.txt" 'sonnet'
  printf 'fast uses sonnet\n' >> "$base/neg4/templates/EXAMPLE-TEMPLATE.md"
  mt_cell "lock: a token supplied only by the map is held (union)" 1 lock_check "$base/neg4" 1
  # A harness name is not a model family.
  mt_cell "lock: a harness name (gemini) is not a model token" 0 lock_check "$base/clean" 1

  # --- the one-release epoch (owner Q3 a, MINOR: nothing reds on upgrade). A tree whose map has no decision= line
  #     (an adopter's pre-303a map, or no map) gets WARN, rc 0, where a decided tree gets FAIL. ---
  assemble clean "$base/ep1"; drop "$base/ep1/.kit/model-map.conf" '^decision='; printf 'fast=sonnet\n' >> "$base/ep1/.kit/model-tiers.conf"
  mt_cell "lock epoch: a vendor token in a .kit conf WARNs, rc 0, when the map has no decision= line" 0 lock_check "$base/ep1" 0
  said "lock epoch: .kit conf token" "WARN"
  assemble clean "$base/ep2"; drop "$base/ep2/.kit/model-map.conf" '^decision='
  sed 's/^model: inherit$/model: sonnet/' "$base/ep2/.claude/agents/engineer.md" > "$base/e.md"; cp "$base/e.md" "$base/ep2/.claude/agents/engineer.md"
  mt_cell "lock epoch: an adopter agent with model: sonnet WARNs, rc 0, when the map has no decision= line" 0 lock_check "$base/ep2" 0
  said "lock epoch: adopter agent" "WARN"
  assemble clean "$base/ep3"; rm "$base/ep3/.kit/model-map.conf"; printf 'fast uses sonnet\n' >> "$base/ep3/templates/EXAMPLE-TEMPLATE.md"
  mt_cell "lock epoch: no map at all WARNs, rc 0" 0 lock_check "$base/ep3" 0
  said "lock epoch: no map" "WARN"
  assemble clean "$base/ep4"; drop "$base/ep4/.kit/model-map.conf" '^decision='; drop "$base/ep4/.gitattributes" 'model-map.conf'
  mt_cell "lock epoch: the export leg stays strict on the kit tree" 1 lock_check "$base/ep4" 1
  # the shipped template carries decision=none (no RECORDED decision): an adopter who takes it stays in the epoch
  assemble clean "$base/ep5"; printf 'decision=none\napex=unset\ndeep=unset\nfast=unset\nlight=unset\n' > "$base/ep5/.kit/model-map.conf"
  sed 's/^model: inherit$/model: sonnet/' "$base/ep5/.claude/agents/engineer.md" > "$base/e.md"; cp "$base/e.md" "$base/ep5/.claude/agents/engineer.md"
  mt_cell "lock epoch: a decision=none template map plus an agent with model: sonnet WARNs, rc 0" 0 lock_check "$base/ep5" 0
  said "lock epoch: decision=none template" "WARN"
  # S2: a read that cannot be completed is UNVERIFIED, never a clean PASS.
  assemble clean "$base/u1"; rm "$base/u1/conformance/model-vendor-tokens.txt"
  mt_cell "lock: a bound map with no family list is UNVERIFIED" 2 lock_check "$base/u1" 1
  assemble clean "$base/u2"; printf '(\n' >> "$base/u2/conformance/model-vendor-tokens.txt"
  mt_cell "lock: a malformed token fragment is UNVERIFIED" 2 lock_check "$base/u2" 1
  if [ "$(id -u)" != 0 ]; then
    assemble clean "$base/u3"; chmod 000 "$base/u3/templates/EXAMPLE-TEMPLATE.md"
    mt_cell "lock: an unreadable surface is UNVERIFIED" 2 lock_check "$base/u3" 1
    chmod 644 "$base/u3/templates/EXAMPLE-TEMPLATE.md"
  fi

  # --- the decision= record (section 6.1) ---
  mt_cell "decision: resolving id PASS" 0 decision_check "$base/clean"
  assemble clean "$base/d1"; drop "$base/d1/.kit/model-map.conf" '^decision='
  mt_cell "decision: bound map without a decision= line WARNs for one release, rc 0" 0 decision_check "$base/d1"
  said "decision: no decision= line" "WARN"
  assemble clean "$base/d2"; sed 's/^decision=.*/decision=D-999999-9/' "$base/d2/.kit/model-map.conf" > "$base/m"; cp "$base/m" "$base/d2/.kit/model-map.conf"
  mt_cell "decision: an id that resolves to no entry FAIL" 1 decision_check "$base/d2"
  assemble clean "$base/d3"; sed 's/^decision=.*/decision=none/' "$base/d3/.kit/model-map.conf" > "$base/m"; cp "$base/m" "$base/d3/.kit/model-map.conf"
  mt_cell "decision: decision=none on a bound map FAIL" 1 decision_check "$base/d3"
  assemble clean "$base/d4"; rm "$base/d4/docs/governance/DECISIONS.md"
  mt_cell "decision: no ledger to resolve against FAIL" 1 decision_check "$base/d4"
  mt_cell "decision: an all-unset map PASS (nothing decided)" 0 decision_check "$base/empty"
  said "decision: all-unset map" "single-model"
  # S1: the id is matched as a fixed string and must be exactly D-dddddd-n; an ERE or glob tail never resolves.
  assemble clean "$base/d5"; sed 's/^decision=.*/decision=D-999999-9|./' "$base/d5/.kit/model-map.conf" > "$base/m"; cp "$base/m" "$base/d5/.kit/model-map.conf"
  mt_cell "decision: an id carrying regex syntax (D-999999-9|.) FAIL" 1 decision_check "$base/d5"
  assemble clean "$base/d6"; sed 's/^decision=.*/decision=D-241018-1x/' "$base/d6/.kit/model-map.conf" > "$base/m"; cp "$base/m" "$base/d6/.kit/model-map.conf"
  mt_cell "decision: an id with a trailing tail (D-241018-1x) FAIL" 1 decision_check "$base/d6"
  # S3: a line that is not a comment or canonical key=value is malformed, never read as unbound.
  assemble clean "$base/d7"; printf ' deep=opus\n' >> "$base/d7/.kit/model-map.conf"
  mt_cell "decision: a leading-space map line on a decided tree FAIL (malformed)" 1 decision_check "$base/d7"
  assemble clean "$base/d8"; drop "$base/d8/.kit/model-map.conf" '^decision='; printf 'deep =opus\n' >> "$base/d8/.kit/model-map.conf"
  mt_cell "decision: a malformed map line in the epoch WARNs, rc 0" 0 decision_check "$base/d8"
  said "decision: malformed in the epoch" "malformed"
  assemble clean "$base/d9"; printf 'apex=unset\n deep=opus\n' > "$base/d9/.kit/model-map.conf"
  mt_cell "decision: a malformed line is never read as an unbound map (no PASS)" 0 decision_check "$base/d9"
  said "decision: malformed line not N/A" "WARN"

  # --- the ADOPTER EXPORT shape (SWAS-303a pre-push fix round): the REAL committed files of this kit tree, minus what
  #     .gitattributes export-ignores, graded as an adopter's tree (no map, no kit marker). Fixtures cannot see a real
  #     file that only an export reaches; this cell can. Runs on the kit tree only (an adopter tree has no git history). ---
  if [ -f "$ROOT/docs/ROADMAP-KIT.md" ] && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    mkdir -p "$base/export"
    git -C "$ROOT" archive HEAD | tar -x -C "$base/export"
    mt_cell "export: the real adopter tree has no map" 1 test -e "$base/export/.kit/model-map.conf"
    mt_cell "export: the real adopter tree has no kit marker (docs/ROADMAP-KIT.md)" 1 test -e "$base/export/docs/ROADMAP-KIT.md"
    mt_cell "export: the real adopter tree passes the vendor lock (WARN is rc 0)" 0 lock_check "$base/export" 0
    mt_cell "export: the real adopter tree passes the decision record" 0 decision_check "$base/export"
    # the whole verifier, run IN the exported tree: the floor proof harness-adapter.sh runs for model-tiering (line 68)
    mt_cell "export: model-tiering.sh exits 0 in the real adopter tree (harness-adapter's floor proof)" 0 sh "$base/export/conformance/model-tiering.sh"
    # the claude-code NATIVE proof for model-tiering (adapters/claude-code/adapter.json) is model-map-binding.sh
    mt_cell "export: model-map-binding.sh exits 0 in the real adopter tree (claude-code native proof)" 0 sh "$base/export/conformance/model-map-binding.sh"
  else
    echo "SKIP: the real-export cells need the kit tree with a git history (docs/ROADMAP-KIT.md and .git); not run here"
  fi

  if [ "$st" = 0 ]; then echo "model-tiering selftest: OK (fixtures in $base)"; else echo "model-tiering selftest: FAIL"; fi
  return "$st"
}

case "${1:-}" in
  --selftest) selftest || fail=1 ;;
  ''|--require) ;;
  *) echo "usage: model-tiering.sh [--require] | --selftest" >&2; exit 2 ;;
esac

# 1. behavioral teeth: the resolver's own non-vacuity selftest (pins/floors/liveness/fail-closed)
if sh "$ROOT/scripts/model-tier.sh" --selftest >/dev/null 2>&1; then echo "PASS: resolver selftest"
else echo "FAIL: resolver selftest (pins/floors/liveness/fail-closed)"; fail=1; fi

# 2. structural: policy config present + declares the load-bearing keys
for k in TIERS PIN VARIABLE APEX_ELIGIBLE FLOOR_CHANGE_CLASS; do
  if grep -q "^$k=" "$ROOT/.kit/model-tiers.conf" 2>/dev/null; then echo "PASS: config has $k"
  else echo "FAIL: .kit/model-tiers.conf missing $k"; fail=1; fi
done

# 3. completeness lock: the guard actually names the config as control-plane (else Task 2 regressed)
if grep -q 'model-tiers\.conf' "$ROOT/.claude/hooks/guard-core.sh" 2>/dev/null; then echo "PASS: guard locks model-tiers.conf"
else echo "FAIL: guard-core.sh does not lock model-tiers.conf"; fail=1; fi

# 4. the vendor lock (SWAS-303a): no kit-shipped seat-binding surface names a vendor model. The kit's own tree is
#    recognised by its export-ignored marker (an adopter export strips it), which arms the export-attribute leg.
unverified=0
if [ -f "$ROOT/docs/ROADMAP-KIT.md" ]; then kit=1; else kit=0; fi
lock_rc=0; lock_out=$(lock_check "$ROOT" "$kit") || lock_rc=$?
printf '%s\n' "$lock_out"
case $lock_rc in 0) ;; 2) unverified=1 ;; *) fail=1 ;; esac

# 5. the decision record: a bound map cites a decision= that resolves (WARN for one release when the line is absent)
dec_rc=0; dec_out=$(decision_check "$ROOT") || dec_rc=$?
printf '%s\n' "$dec_out"
[ "$dec_rc" -eq 0 ] || fail=1

if [ "$fail" -ne 0 ]; then echo "model-tiering: FAILURES"; exit 1; fi
if [ "$unverified" -ne 0 ]; then echo "model-tiering: UNVERIFIED (the vendor lock could not be graded)"; exit 2; fi
echo "model-tiering: ALL PASS"; exit 0
