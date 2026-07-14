#!/bin/sh
# mirror-tag-protection.sh — P1.2-pre-b: the public mirror's released tags are protected AT THE FORGE.
#
# WHY THIS EXISTS, AND WHAT IT ADMITS. publish-public.sh now REFUSES to re-publish a released tag
# whose tree differs, and pushes tags non-force (so git itself rejects a ref move). That closes the
# TOOL. It does not close the HUMAN: anyone with push rights can still `git push --force` a tag by
# hand, and no client-side check can stop them. Only a forge-side rule binds every actor.
#
# THE CEILING, STATED — do not let a green here imply more than it proves:
#   - A GitHub tag ruleset blocks force-push AND deletion of refs/tags/v* for EVERYONE, including the
#     maintainer and any token. That is the real control.
#   - A repository ADMIN CAN LIFT THE RULESET. Immutability is therefore ENFORCED BY THE FORGE and
#     merely ATTESTED by us. We claim tamper-EVIDENT-and-deliberate, never tamper-proof.
#   - This check verifies the rule is CONFIGURED. It cannot prove no one has ever bypassed it.
#
# API SHAPE (dual review B1 — the defect this version fixes). `GET /repos/{o}/{r}/rulesets` (the LIST
# endpoint) returns ONLY {id,name,target,enforcement,...} — it carries NO `rules` array. The rules and
# the ref-name conditions live ONLY on the per-ruleset GET `/rulesets/{id}`. The prior version grepped
# the list payload for a rule type that is never there, so it could NEVER go green against the real
# API — while its selftest passed on hand-authored single-object fixtures the API never emits. So this
# version: LIST -> filter to active tag rulesets -> GET each -> evaluate that object's own rules +
# conditions. And it evaluates PER OBJECT (dual review B2): three independent greps over a merged
# array could be satisfied by three DIFFERENT rulesets (an active BRANCH ruleset + a disabled TAG one
# read as "tags protected"). jq per-object closes that.
#
#   usage: sh conformance/mirror-tag-protection.sh [--selftest]
#   exit:  0 = an active tag ruleset protects refs/tags/v* (blocks force-push AND deletion)
#          1 = reachable + authenticated, and NO such ruleset exists (a real gap)
#          2 = UNVERIFIED — no gh / no jq / not authenticated / no admin scope. NEVER a pass.
#              (branch-protection precedent: verify.sh renders 2 as UNVERIFIED; UNVERIFIED is not a
#               pass under --require / CI. An absent credential must never read as a green.)
set -eu
cd "$(dirname "$0")/.."

PUBLISH_SCRIPT="scripts/publish-public.sh"

# Single source (mirrors mirror-current.sh): the mirror URL is declared once, in publish-public.sh.
# Validate it to a github https slug; a WRONG-but-plausible slug is worse than none (it would probe a
# repo nobody publishes to), so anything that is not exactly owner/repo FAILS rather than guesses.
mirror_slug() {
  _r=$(grep -E '^PUBLIC_REMOTE_DEFAULT=' "$PUBLISH_SCRIPT" 2>/dev/null | head -1 | sed "s/^[^=]*=//; s/^[\"']//; s/[\"'].*$//")
  case "$_r" in
    https://github.com/*/*) : ;;
    *) echo "FAIL: PUBLIC_REMOTE_DEFAULT in $PUBLISH_SCRIPT is missing or not a github https url ('$_r') — refusing to guess a mirror."; return 1 ;;
  esac
  _slug=$(printf '%s\n' "$_r" | sed 's|^https://github.com/||; s|\.git$||')
  case "$_slug" in
    */*[!/]) printf '%s\n' "$_slug" ;;
    *) echo "FAIL: could not derive owner/repo from '$_r'"; return 1 ;;
  esac
}

# ruleset_protects_tags <list-json> <get-fn>: TRUE iff SOME active tag ruleset, fetched via <get-fn>,
# blocks BOTH non_fast_forward and deletion AND scopes refs/tags/v* (or all tags). <get-fn> takes a
# ruleset id and echoes that ruleset's full JSON — real `gh api` in production, a fixture in selftest.
# Evaluated per object (never a merged grep), so cross-ruleset conflation cannot produce a false green.
ruleset_protects_tags() {
  _list=$1; _getfn=$2

  # Candidate ids: active rulesets whose target is "tag". (These fields DO exist on the list payload.)
  _ids=$(printf '%s' "$_list" | jq -r '.[] | select(.target=="tag" and .enforcement=="active") | .id' 2>/dev/null || true)
  [ -n "$_ids" ] || return 1

  for _id in $_ids; do
    _rs=$("$_getfn" "$_id") || continue
    # This ONE ruleset must, by itself, block force-push AND deletion...
    _has_nff=$(printf '%s' "$_rs" | jq -r 'any(.rules[]?; .type=="non_fast_forward")' 2>/dev/null || echo false)
    _has_del=$(printf '%s' "$_rs" | jq -r 'any(.rules[]?; .type=="deletion")'        2>/dev/null || echo false)
    [ "$_has_nff" = true ] && [ "$_has_del" = true ] || continue
    # ...and its ref-name condition must cover our released tags. Evaluate the WHOLE condition to ONE
    # boolean (dual review round 2): the include must match v* (explicitly, or a catch-all / empty
    # include = all tags of this tag-target ruleset), AND the exclude must NOT carve v* back out. Two
    # bugs this closes: (a) `any(...)` in an `if` emits one boolean PER include entry, so a multi-
    # pattern include like [latest, v*] produced "false\ntrue" and read as uncovered (false RED);
    # (b) exclude was never consulted, so include:~ALL + exclude:v* — every tag protected EXCEPT v* —
    # read as protected (a false GREEN in a security attestation, the exact class this slice kills).
    _covers=$(printf '%s' "$_rs" | jq -r '
      def hits_v: any(.[]?; test("refs/tags/(v\\*|\\*)$|^~ALL$"));
      (.conditions.ref_name.include // []) as $inc
      | (.conditions.ref_name.exclude // []) as $exc
      | ((($inc|length)==0) or ($inc|hits_v)) as $inc_ok
      | if ($inc_ok and (($exc|hits_v)|not)) then "true" else "false" end' 2>/dev/null || echo false)
    [ "$_covers" = true ] && return 0
  done
  return 1
}

check() {
  _slug=$(mirror_slug) || return 1
  command -v gh >/dev/null 2>&1 || { echo "UNVERIFIED: gh is not installed — cannot read the tag ruleset on $_slug. This is NOT a pass."; return 2; }
  command -v jq >/dev/null 2>&1 || { echo "UNVERIFIED: jq is not installed — cannot parse rulesets. This is NOT a pass."; return 2; }

  if ! _list=$(gh api "repos/$_slug/rulesets" 2>/dev/null); then
    echo "UNVERIFIED: could not read rulesets for $_slug (unauthenticated, or no admin scope). This is NOT a pass."
    return 2
  fi

  # The live getter: fetch one ruleset's full JSON (this is where rules[] + conditions live).
  _live_get() { gh api "repos/$_slug/rulesets/$1" 2>/dev/null; }

  if ruleset_protects_tags "$_list" _live_get; then
    echo "mirror-tag-protection: OK — an active tag ruleset protects refs/tags/v* on $_slug (force-push + deletion blocked)"
    echo "  CEILING: a repo ADMIN can lift this ruleset. Immutability is enforced by the forge, attested here."
    return 0
  fi
  echo "FAIL: no active tag ruleset on $_slug blocks BOTH force-push and deletion for refs/tags/v*."
  echo "  publish-public.sh refuses to move a released tag, but that binds only the TOOL — a human with"
  echo "  push rights can still force-push a tag by hand. Only a forge rule binds every actor."
  echo "  Settings -> Rules -> Rulesets -> New tag ruleset: target refs/tags/v*, block non_fast_forward + deletion."
  return 1
}

selftest() {
  st=0
  command -v jq >/dev/null 2>&1 || { echo "mirror-tag-protection --selftest: SKIP (jq absent)"; return 0; }

  # Fixtures are shaped like the REAL API (dual review B1): the LIST payload has NO rules[]; the
  # per-ruleset GET carries rules[] + conditions. A fixture getter serves the GET shape by id.
  _list_good='[{"id":10,"target":"branch","enforcement":"active"},{"id":20,"target":"tag","enforcement":"active"}]'
  # dual review B2 PoC: an ACTIVE BRANCH ruleset + a DISABLED TAG ruleset. The old code's merged greps
  # went green here; per-object evaluation must go RED (the tag ruleset is off; the branch one is N/A).
  _list_conflate='[{"id":30,"target":"branch","enforcement":"active"},{"id":40,"target":"tag","enforcement":"disabled"}]'
  _list_nightly='[{"id":50,"target":"tag","enforcement":"active"}]'
  _list_delonly='[{"id":60,"target":"tag","enforcement":"active"}]'
  _list_multi='[{"id":70,"target":"tag","enforcement":"active"}]'    # include [latest, v*] -> OK
  _list_carveout='[{"id":80,"target":"tag","enforcement":"active"}]' # include ~ALL, exclude v* -> FAIL
  _list_empty='[]'

  # The GET fixture: full ruleset objects keyed by id, exactly as /rulesets/{id} returns them.
  _get() {
    case "$1" in
      20) echo '{"id":20,"target":"tag","enforcement":"active","rules":[{"type":"non_fast_forward"},{"type":"deletion"}],"conditions":{"ref_name":{"include":["refs/tags/v*"],"exclude":[]}}}' ;;
      30) echo '{"id":30,"target":"branch","enforcement":"active","rules":[{"type":"non_fast_forward"},{"type":"deletion"}],"conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"]}}}' ;;
      40) echo '{"id":40,"target":"tag","enforcement":"disabled","rules":[{"type":"non_fast_forward"},{"type":"deletion"}],"conditions":{"ref_name":{"include":["refs/tags/v*"]}}}' ;;
      50) echo '{"id":50,"target":"tag","enforcement":"active","rules":[{"type":"non_fast_forward"},{"type":"deletion"}],"conditions":{"ref_name":{"include":["refs/tags/nightly-*"]}}}' ;;
      60) echo '{"id":60,"target":"tag","enforcement":"active","rules":[{"type":"deletion"}],"conditions":{"ref_name":{"include":["refs/tags/v*"]}}}' ;;
      70) echo '{"id":70,"target":"tag","enforcement":"active","rules":[{"type":"non_fast_forward"},{"type":"deletion"}],"conditions":{"ref_name":{"include":["refs/tags/latest","refs/tags/v*"],"exclude":[]}}}' ;;
      80) echo '{"id":80,"target":"tag","enforcement":"active","rules":[{"type":"non_fast_forward"},{"type":"deletion"}],"conditions":{"ref_name":{"include":["~ALL"],"exclude":["refs/tags/v*"]}}}' ;;
      *)  echo '{}' ;;
    esac
  }

  _t() {  # <want:0|1> <list-json> <label>
    if ruleset_protects_tags "$2" _get; then _got=0; else _got=1; fi
    if [ "$_got" = "$1" ]; then echo "  ok   $3"; else echo "  FAIL $3 (want $1 got $_got)"; st=1; fi
  }
  _t 0 "$_list_good"     "active tag ruleset, force-push+deletion blocked, v* scope -> OK"
  _t 1 "$_list_conflate" "active BRANCH + disabled TAG ruleset -> FAIL (B2: no cross-object green)"
  _t 1 "$_list_nightly"  "active tag ruleset scoped to nightly-* -> FAIL (does not cover v*)"
  _t 1 "$_list_delonly"  "tag ruleset blocks deletion but NOT force-push -> FAIL (wrong/partial rule)"
  _t 0 "$_list_multi"    "include [latest, v*], both rules -> OK (multi-pattern include, no false RED)"
  _t 1 "$_list_carveout" "include ~ALL but EXCLUDE v* -> FAIL (v* carved out; no false GREEN)"
  _t 1 "$_list_empty"    "no rulesets at all -> FAIL (no vacuous green)"

  # LOAD-BEARING: the good fixture must fail if force-push protection is stripped from ITS OWN object,
  # proving the check reads the per-ruleset rules and not just the list.
  _get_stripped() { case "$1" in 20) echo '{"id":20,"target":"tag","enforcement":"active","rules":[{"type":"deletion"}],"conditions":{"ref_name":{"include":["refs/tags/v*"]}}}' ;; *) echo '{}' ;; esac; }
  if ruleset_protects_tags "$_list_good" _get_stripped; then echo "  FAIL stripping non_fast_forward from the ruleset still passed"; st=1; else echo "  ok   stripping non_fast_forward from the ruleset -> FAIL (reads per-object rules)"; fi

  if [ "$st" = 0 ]; then echo "mirror-tag-protection --selftest: OK"; else echo "mirror-tag-protection --selftest: FAIL"; fi
  return "$st"
}

case "${1:-}" in
  --selftest) selftest ;;
  '')
    # KIT-ONLY (dual review finding 7): checks the KIT OWNER's mirror rulesets. N/A on an incepted tree.
    if [ -f ENGINEERING-PRINCIPLES.md ]; then
      echo "mirror-tag-protection: N/A — incepted tree (this checks the KIT's own public mirror)"; exit 0
    fi
    check ;;
  *) echo "usage: mirror-tag-protection.sh [--selftest]" >&2; exit 2 ;;
esac
