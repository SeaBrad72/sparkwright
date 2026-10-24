#!/bin/sh
# model-tier.sh — KW20(b) harness-neutral MODEL-tier resolver (deep>fast>light).
#
# Resolves a teammate's effective MODEL tier from role + task signals, enforcing the
# control-plane policy in .kit/model-tiers.conf: pinned judgment/verification seats always
# resolve `deep` and refuse a dispatch-time override; a change-class floor applies ONLY if the policy lists one
# (the kit's shipped policy lists none since D-241018-2; --critical-path still forces `deep` until 303b); variable
# seats (engineer/explorer) may run a requested tier within their allowed set, defaulting to the seat's
# DEFAULT_<role> when unspecified or when a valid-but-disallowed tier is requested. Fail-closed (exit 2) on any
# ambiguity — an unknown role never slips past the pins.
#
# SWAS-303a (D-241018-2): the shipped policy no longer carries a change-class floor, so control-plane and
# sensitive work resolves to the seat's own tier. KNOWN ISSUE until 303b: this resolver still keeps a top tier
# (TOP), still forces --critical-path to it, and still reads an unknown change-class as top. Those are the same
# ranking assumption the floor made and leave with the seat/profile resolver.
# NOTE: "tier" = MODEL tier, NOT the autonomy/promotion tier (scripts/tier-advice.sh, DEV-PROCESS §13).
# The kit cannot INVOKE a model — this emits an abstract tier; a per-harness adapter binds tier->model
# (.kit/model-map.conf, Slice 2). FLOOR: tier resolved + pins/floors enforced here in neutral shell.
#
# Usage:  model-tier.sh resolve --role R [--requested T] [--change-class C] [--critical-path] [--config F]
#         model-tier.sh --selftest
#         (--config F overrides the policy path; MODEL_TIERS_CONFIG env does the same — runaway-guard precedent.)
# Exit:   0 resolved (effective tier on stdout) | 2 UNVERIFIED (bad config/role/tier — fail-closed).
# What it changes: read-only — reads .kit/model-tiers.conf and prints the resolved abstract tier; mutates nothing.
# Guardrails: fail-closed (exit 2) on a missing/bad config, unknown role, or unknown requested tier; the policy
#   config (.kit/model-tiers.conf) is control-plane (agent-immutable); pins + any floors the policy lists can only
#   hold or RAISE a tier, never downgrade a pinned seat or a floored task (--critical-path, and any change-class the
#   policy lists; the kit's shipped policy lists none).
set -eu

CONFIG="${MODEL_TIERS_CONFIG:-.kit/model-tiers.conf}"
TOP=deep

die2() { printf '%s\n' "$*" >&2; exit 2; }

cfg() {  # cfg KEY -> first KEY=VALUE value (comment/space-stripped); empty if absent
  [ -f "$CONFIG" ] || return 1
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\([^#[:space:]]*\).*/\1/p" "$CONFIG" | head -1
}

in_csv() { case ",${2}," in *",${1},"*) return 0 ;; *) return 1 ;; esac; }

resolve() {
  role=""; requested=""; change_class=""; critical=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --role)          [ $# -ge 2 ] || die2 "2: --role requires a value"; role="$2"; shift 2 ;;
      --requested)     [ $# -ge 2 ] || die2 "2: --requested requires a value"; requested="$2"; shift 2 ;;
      --change-class)  [ $# -ge 2 ] || die2 "2: --change-class requires a value"; change_class="$2"; shift 2 ;;
      --critical-path) critical=1; shift ;;
      --config)        [ $# -ge 2 ] || die2 "2: --config requires a value"; CONFIG="$2"; shift 2 ;;
      *) die2 "2: unknown arg: $1" ;;
    esac
  done
  [ -n "$role" ] || die2 "2: --role is required (fail-closed)"
  # role charset guard (defense-in-depth): a role is a bare identifier; reject anything else fail-closed
  # (also keeps $role safe as it flows into the cfg() sed program for ALLOWED_/DEFAULT_ lookups).
  case "$role" in *[!A-Za-z0-9_-]*) die2 "2: role '$role' has invalid characters (fail-closed)" ;; esac
  [ -f "$CONFIG" ] || die2 "2: config missing: $CONFIG (fail-closed)"

  tiers=$(cfg TIERS || true); [ -n "$tiers" ] || die2 "2: TIERS unset in $CONFIG (fail-closed)"
  pin=$(cfg PIN || true)
  variable=$(cfg VARIABLE || true)
  apex_eligible=$(cfg APEX_ELIGIBLE || true)
  floor_cc=$(cfg FLOOR_CHANGE_CLASS || true)
  known_cc=$(cfg CHANGE_CLASSES || true)

  # normalize change-class: trim surrounding whitespace + lowercase, so a padded/miscased value
  # ( ' control-plane', 'Control-Plane') cannot slip past the floor. Empty stays empty (not provided).
  if [ -n "$change_class" ]; then
    change_class=$(printf '%s' "$change_class" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  fi

  # a requested tier must be a KNOWN tier (garbage -> fail-closed)
  if [ -n "$requested" ] && ! in_csv "$requested" "$tiers"; then
    die2 "2: requested tier '$requested' not in TIERS=$tiers (fail-closed)"
  fi

  # 1. FLOOR -> top. A critical-path task, or a floor change-class, forces `deep`. Crucially, a
  #    NON-EMPTY change-class that is not a recognized KNOWN class defaults HIGH (fail-safe) — a
  #    malformed/miscased/typo'd class can never DOWNGRADE a floored task (the asymmetric-fail bug:
  #    role fails closed, so change-class must too). Empty change-class = not provided -> no floor
  #    (e.g. a read-only Explorer), so the requested/default tier stands.
  #    FABLE-TIER (2026-07-23) put the floor FIRST — before apex-escalation and the pin — so a floored task could
  #    never reach `apex` (clause D1: the highest-scrutiny work stays on the most-proven model). D1 IS SUPERSEDED by
  #    D-241018-2 (SWAS-303a): the shipped policy lists no floor class, so a control-plane/sensitive engineer's explicit
  #    `--requested apex` now reaches `apex` (step 2). Only --critical-path (and the unknown-class rule) still forces
  #    `deep` here; both leave with 303b. The ordering is kept: a policy that lists a floor class still wins over apex.
  if [ "$critical" -eq 1 ]; then printf '%s\n' "$TOP"; return 0; fi
  if [ -n "$change_class" ]; then
    if in_csv "$change_class" "$floor_cc"; then printf '%s\n' "$TOP"; return 0; fi
    # non-floor: allow ONLY if explicitly a known class (e.g. ordinary); else fail-safe HIGH.
    if ! { [ -n "$known_cc" ] && in_csv "$change_class" "$known_cc"; }; then
      printf 'note: unrecognized change-class %s; treating as top-tier (fail-safe)\n' "$change_class" >&2
      printf '%s\n' "$TOP"; return 0
    fi
  fi

  # 2. APEX ESCALATION (FABLE-TIER) -> an apex-eligible seat may be RAISED to `apex` on a NON-floored task
  #    (all floors already returned above). This is an UPGRADE above the pin's `deep`, so it precedes the
  #    pin: architect/plan stay pinned against DOWNGRADES (handled in step 3) yet can reach apex here.
  #    Non-eligible seats (reviewer/security/orchestrator/verification) never match and fall through to the
  #    pin -> `deep`. apex is opt-in: it fires ONLY on an explicit `--requested apex`, never by default.
  if [ "$requested" = "apex" ] && in_csv "$role" "$apex_eligible"; then
    printf '%s\n' "apex"; return 0
  fi

  # 3. PIN -> top (request ignored, with a legibility note). A pinned seat refuses a DOWNGRADE; an apex
  #    request from a pinned-but-eligible seat already returned in step 2.
  if in_csv "$role" "$pin"; then
    if [ -n "$requested" ] && [ "$requested" != "$TOP" ]; then
      printf 'note: role %s is pinned at %s; ignoring requested %s\n' "$role" "$TOP" "$requested" >&2
    fi
    printf '%s\n' "$TOP"; return 0
  fi

  # 4. VARIABLE -> requested if allowed; else role default (default-to-higher)
  if in_csv "$role" "$variable"; then
    allowed=$(cfg "ALLOWED_$role" || true); [ -n "$allowed" ] || die2 "2: ALLOWED_$role unset (fail-closed)"
    default=$(cfg "DEFAULT_$role" || true); [ -n "$default" ] || die2 "2: DEFAULT_$role unset (fail-closed)"
    if [ -n "$requested" ]; then
      if in_csv "$requested" "$allowed"; then printf '%s\n' "$requested"; return 0; fi
      printf 'note: %s not allowed for %s (allowed: %s); using default %s\n' "$requested" "$role" "$allowed" "$default" >&2
    fi
    printf '%s\n' "$default"; return 0
  fi

  # 5. unknown role -> fail-closed (never slip past the pins)
  die2 "2: role '$role' is neither pinned nor variable in $CONFIG (fail-closed)"
}

selftest() {
  fail=0
  t() {  # t DESC EXPECTED  resolve-args...   (command-substitution isolates die2's exit)
    _d="$1"; _exp="$2"; shift 2
    _got=$(resolve "$@" 2>/dev/null) || _got="<exit$?>"
    if [ "$_got" = "$_exp" ]; then echo "PASS: $_d ($_got)"
    else echo "FAIL: $_d — wanted $_exp got $_got"; fail=1; fi
  }
  x2() {  # x2 DESC  resolve-args...   — expects exit 2 (explicit subshell isolates the exit)
    _d="$1"; shift
    if ( resolve "$@" ) >/dev/null 2>&1; then echo "FAIL: $_d — wanted exit 2, got 0"; fail=1
    else _rc=$?; if [ "$_rc" -eq 2 ]; then echo "PASS: $_d (exit 2)"; else echo "FAIL: $_d — wanted exit 2 got $_rc"; fail=1; fi; fi
  }
  # SWAS-303a: the legs below exercise the resolver's MECHANISM (pins, floors, apex, fail-closed) on a FIXTURE
  # policy, so the kit's own policy file (which no longer carries a change-class floor) cannot fix the behaviour
  # under test. The shipped policy is graded separately, after these legs, under "shipped:".
  _shipped_config=$CONFIG
  _fixture_config=$(mktemp)
  printf '%s\n' 'TIERS=apex,deep,fast,light' 'PIN=orchestrator,reviewer,security,architect,plan,verification' \
    'APEX_ELIGIBLE=engineer,architect,plan' 'VARIABLE=engineer,explorer' 'ALLOWED_engineer=deep,fast' \
    'ALLOWED_explorer=deep,fast,light' 'DEFAULT_engineer=deep' 'DEFAULT_explorer=fast' \
    'CHANGE_CLASSES=ordinary,sensitive,control-plane' 'FLOOR_CHANGE_CLASS=control-plane,sensitive' > "$_fixture_config"
  CONFIG=$_fixture_config
  # PIN holds (load-bearing negative — a regression that downgrades a judgment seat MUST fail here)
  t  "pin: reviewer ignores downgrade"    deep  --role reviewer --requested fast
  t  "pin: security ignores downgrade"    deep  --role security --requested light
  t  "pin: orchestrator (no request)"     deep  --role orchestrator
  t  "pin: architect"                     deep  --role architect --requested fast
  t  "pin: plan"                          deep  --role plan --requested light
  t  "pin: verification"                  deep  --role verification --requested fast
  # FLOOR holds (load-bearing negative)
  t  "floor: engineer control-plane"      deep  --role engineer --requested fast --change-class control-plane
  t  "floor: engineer critical-path"      deep  --role engineer --requested fast --critical-path
  t  "floor: engineer sensitive"          deep  --role engineer --requested fast --change-class sensitive
  # FLOOR normalization + fail-safe (HIGH: a padded/miscased/typo'd class must NOT slip past the floor)
  t  "floor: leading space normalized"    deep  --role engineer --requested fast --change-class " control-plane"
  t  "floor: mixed case normalized"       deep  --role engineer --requested fast --change-class Control-Plane
  t  "floor: trailing space sensitive"    deep  --role engineer --requested fast --change-class "sensitive "
  t  "floor: typo class fails safe-high"  deep  --role engineer --requested fast --change-class controlplane
  t  "floor: unknown class fails safe"    deep  --role engineer --requested fast --change-class foobar
  # JUDGMENT LIVE (positive liveness — if these return deep, tiering is a DEAD feature)
  t  "live: engineer ordinary -> fast"    fast  --role engineer --requested fast --change-class ordinary
  t  "live: explorer -> light"            light --role explorer --requested light
  t  "live: engineer default unspecified" deep  --role engineer --change-class ordinary
  # default-to-higher: a valid-but-disallowed request clamps to the role default (NOT exit 2)
  t  "clamp: engineer requests light"     deep  --role engineer --requested light --change-class ordinary
  # FAIL-CLOSED (never a silent default)
  x2 "unknown role"                       --role gremlin
  x2 "garbage requested tier"             --role engineer --requested turbo
  x2 "missing role"                       --requested fast
  x2 "role with invalid chars"            --role "rev iewer"
  x2 "role with sed metachar"             --role "engineer/x"
  # --- FABLE-TIER: apex escalation (opt-in tier above deep; owner-ratified 2026-07-23) ---
  # positive liveness: eligible seats RAISE to apex on an ordinary/unfloored task (dead feature if not)
  t  "apex: engineer raises"                    apex  --role engineer --requested apex --change-class ordinary
  t  "apex: architect raises (pinned+eligible)" apex  --role architect --requested apex --change-class ordinary
  t  "apex: plan raises (no change-class)"      apex  --role plan --requested apex
  # LOAD-BEARING NEGATIVE — FLOOR beats apex: control-plane/sensitive/critical NEVER reach apex (D1)
  t  "apex floored: architect control-plane"    deep  --role architect --requested apex --change-class control-plane
  t  "apex floored: engineer sensitive"         deep  --role engineer --requested apex --change-class sensitive
  t  "apex floored: engineer critical-path"     deep  --role engineer --requested apex --critical-path
  # LOAD-BEARING NEGATIVE — non-eligible judgment seats IGNORE an apex request and stay deep (governance)
  t  "apex denied: reviewer stays deep"         deep  --role reviewer --requested apex
  t  "apex denied: security stays deep"         deep  --role security --requested apex
  t  "apex denied: orchestrator stays deep"     deep  --role orchestrator --requested apex
  # explorer: neither apex-eligible nor apex-in-ALLOWED -> clamps to its own default (never apex)
  t  "apex denied: explorer -> default fast"    fast  --role explorer --requested apex
  # --- SWAS-303a: the SHIPPED policy (the change-class floor is retired as a kit default; D-241018-2) ---
  CONFIG=$_shipped_config
  # These legs grade the KIT'S OWN shipped policy, so they run on the kit tree only (the docs/ROADMAP-KIT.md marker an
  # export strips). An adopter's model-tiers.conf is theirs: a pre-303a policy with a floor must not red on upgrade
  # (owner Q3 a, MINOR). The adopter-shaped cell below proves it.
  if [ -f "$(dirname "$0")/../docs/ROADMAP-KIT.md" ]; then
    # liveness: a control-plane or sensitive builder resolves to the builder default, NOT the top tier. If the
    # shipped policy floors them again, this leg reads deep and the retirement is undone.
    t  "shipped: control-plane builder -> fast"           fast  --role engineer --requested fast --change-class control-plane
    t  "shipped: control-plane builder (no request) -> fast" fast --role engineer --change-class control-plane
    t  "shipped: sensitive builder -> fast"               fast  --role engineer --requested fast --change-class sensitive
    # D-241018-2: with the floor retired, a control-plane engineer's explicit opt-in to apex now reaches it
    t  "shipped: control-plane engineer --requested apex -> apex (D1 superseded)" apex --role engineer --requested apex --change-class control-plane
    # the pin governance holds under the shipped policy: no dispatch-time request moves a judgment seat
    t  "shipped: reviewer pin holds under the shipped config" deep --role reviewer --requested fast --change-class control-plane
    # an adopter-shaped tree (no kit marker, a pre-303a policy with a floor and a deep default) must selftest green
    # The inner run sets MODEL_TIER_ADOPTER_CELL=1 and skips this cell, so a broken marker gate turns the cell RED
    # instead of recursing without a bound.
    if [ -z "${MODEL_TIER_ADOPTER_CELL:-}" ]; then
      _adopter=$(mktemp -d); mkdir -p "$_adopter/scripts" "$_adopter/.kit"
      cp "$0" "$_adopter/scripts/model-tier.sh"; cp "$_fixture_config" "$_adopter/.kit/model-tiers.conf"
      if ( cd "$_adopter" && env -u MODEL_TIERS_CONFIG MODEL_TIER_ADOPTER_CELL=1 sh scripts/model-tier.sh --selftest ) >/dev/null 2>&1; then
        echo "PASS: an adopter-shaped tree (pre-303a policy, no kit marker) selftests green"
      else
        echo "FAIL: an adopter-shaped tree (pre-303a policy, no kit marker) must not red on the kit's shipped-policy legs"; fail=1
      fi
    fi
  else
    echo "SKIP: shipped: legs grade the kit's own policy and run on the kit tree only"
  fi
  if [ "$fail" -eq 0 ]; then echo "model-tier selftest: ALL PASS"; return 0
  else echo "model-tier selftest: FAILURES"; return 1; fi
}

cmd="${1:-}"; [ $# -gt 0 ] && shift || true
case "$cmd" in
  resolve)   resolve "$@" ;;
  --selftest|selftest) selftest ;;
  *) die2 "2: usage: model-tier.sh resolve --role R [--requested T] [--change-class C] [--critical-path] | --selftest" ;;
esac
