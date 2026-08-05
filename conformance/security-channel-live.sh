#!/bin/sh
# security-channel-live.sh — the advertised private-disclosure channel is LIVE on the forge (T0-09).
#
# Trigger (derived, fail-closed): fires ONLY when SECURITY.md advertises GitHub private
# vulnerability reporting as the security contact. Not advertised -> N/A (nothing promised).
# Advertised but no 'Channel repo:' declaration -> FAIL (the promise names no probeable repo;
# never a silent pass). Advertised + declared -> probe the forge setting:
#   {"enabled":true}  -> PASS  (the advertised channel is live)
#   {"enabled":false} -> FAIL  (the advertised primary channel is a dead letterbox — the T0-09 defect)
#   probe unavailable (no gh, no network, API error) -> UNVERIFIED rc 2 — NOT a pass;
#   verify.sh --require / CI escalates rc 2.
#
# SCOPE: a green run proves the forge SETTING is on — NOT that reports are triaged or SLAs met
# (those are operator rows; see docs/operations/security-disclosure-response.md). Sibling of
# conformance/security-policy.sh (which proves the policy is RECORDED; this proves the channel WORKS).
#
# WRONG-REPO GUARD: when the working tree's `origin` remote resolves to a GitHub <owner>/<repo>,
# the declared 'Channel repo:' must equal it — mismatch -> FAIL (otherwise the check attests a
# setting on a repo the promise does not ship from). One honored split: a declaration equal to the
# tree's own publish target (PUBLIC_REMOTE_DEFAULT parsed from scripts/publish-public.sh — derived,
# never hardcoded) is accepted ONLY when the publish target's OWNER equals the origin's OWNER —
# a dev repo may publish SECURITY.md to its own public mirror where the channel actually lives
# (the kit's own dev->public shape), but a foreign-owner tree carrying a publish script that names
# someone else's repo gets no exception. No resolvable GitHub origin (local path remote, no remote
# at all) -> the declared repo is probed as-is.
#
# PLACEMENT: verify.sh registers ONLY --selftest (offline, stub-driven) — the live probe needs
# gh+network+auth, which adopters' documented first `verify.sh --require` run does not have. The
# LIVE probe runs as a dedicated step in the kit's own ci.yml (step-scoped GH_TOKEN); adopters
# MAY wire the live run into their own pipeline the same way (no profile ships the step yet).
#
# Probe injection is ARGUMENT-borne (--probe-cmd '<cmd>'), never environment-borne, per the banked
# "arguments, not env" security ruling (see conformance/ceremony-binding.sh --scope). The selftest
# passes stub commands; the load-bearing negative runs against a STUB, never the live repo.
#
# Usage:
#   sh conformance/security-channel-live.sh [project-dir] [--probe-cmd '<cmd>']   (default: . / 'gh api')
#   sh conformance/security-channel-live.sh --selftest
# Exit: 0 = PASS or N/A · 1 = FAIL · 2 = UNVERIFIED (probe unavailable) · 3 = usage.
# What it changes: read-only — reads SECURITY.md and issues one forge GET; mutates nothing.
# Guardrails: read-only; single GET against a declared repo; no writes, no env-borne switches;
#   selftest uses mktemp fixtures with trap cleanup and stub probes only.
set -eu

PROBE_DEFAULT="gh api"

_github_repo() {  # <url> -> owner/repo on stdout iff a GitHub URL, else empty (rc always 0)
  case "${1:-}" in
    https://github.com/*|http://github.com/*|git@github.com:*|ssh://git@github.com/*) : ;;
    *) return 0 ;;
  esac
  _r=${1#*github.com}; _r=${_r#?}; _r=${_r%/}; _r=${_r%.git}
  printf '%s\n' "$_r" | grep -E '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' || true
}

check_channel() {  # <dir> <probe-cmd> -> 0 PASS/N-A · 1 FAIL · 2 UNVERIFIED
  dir=$1; probe=$2
  sec="$dir/SECURITY.md"
  if [ ! -f "$sec" ]; then
    echo "N/A: $dir has no SECURITY.md — nothing advertised to verify (SECURITY.md presence is security-policy.sh's row)"
    return 0
  fi
  if ! grep -Eiq 'security contact:.*private vulnerability reporting' "$sec"; then
    echo "N/A: SECURITY.md does not advertise GitHub private vulnerability reporting as the security contact — no live-channel promise to verify"
    return 0
  fi
  # head -n 1 terminates the pipeline with rc 0 even when grep matches nothing (set -e-safe).
  chan=$(grep -Ei 'channel repo:' "$sec" | head -n 1)
  if [ -z "$chan" ]; then
    echo "FAIL: SECURITY.md advertises GitHub private vulnerability reporting but declares no 'Channel repo:' line,"
    echo "  so the check cannot know WHICH repo carries the promise. Remedy: add"
    echo "  '**Channel repo:** \`<owner>/<repo>\`' under the '**Security contact:**' line."
    return 1
  fi
  # M1: the line-match above is case-insensitive, so the strip must be too (POSIX sed has no -i flag).
  repo=$(printf '%s\n' "$chan" | sed -E 's/^.*[Cc][Hh][Aa][Nn][Nn][Ee][Ll][[:space:]]+[Rr][Ee][Pp][Oo]:[^A-Za-z0-9]*//' | grep -Eo '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' | head -n 1)
  if [ -z "$repo" ]; then
    echo "FAIL: SECURITY.md's 'Channel repo:' line does not parse as <owner>/<repo> — got: $chan"
    echo "  Remedy: declare it as '**Channel repo:** \`<owner>/<repo>\`'."
    return 1
  fi
  # C2 — wrong-repo attestation guard: when this working tree's `origin` resolves to a GitHub
  # <owner>/<repo>, the declaration must be BOUND to it — otherwise this check would attest a
  # setting on a repo the promise does not ship from. One honored split: a declaration equal to
  # the tree's own publish target (PUBLIC_REMOTE_DEFAULT in scripts/publish-public.sh, parsed —
  # never hardcoded) is accepted, because a dev repo may publish SECURITY.md to a public mirror
  # where the channel actually lives. No resolvable GitHub origin -> probe the declared repo as-is.
  origin_repo=$(_github_repo "$(git -C "$dir" remote get-url origin 2>/dev/null || true)")
  if [ -n "$origin_repo" ]; then
    if [ "$repo" = "$origin_repo" ]; then
      echo "  binding: the declared channel repo equals this tree's origin ($origin_repo)"
    else
      publish_repo=""
      if [ -f "$dir/scripts/publish-public.sh" ]; then
        publish_repo=$(_github_repo "$(grep -E '^PUBLIC_REMOTE_DEFAULT=' "$dir/scripts/publish-public.sh" | head -n 1 | sed -E 's/^PUBLIC_REMOTE_DEFAULT="([^"]*)".*/\1/')")
      fi
      # I-1 — owner-matched split: the publish-target exception holds only when the publish
      # target's OWNER equals the origin's OWNER (the same party owns both halves of the
      # dev->public pair). Otherwise any tree could attest a setting on someone else's repo
      # merely by shipping a publish-public.sh that names it.
      if [ -n "$publish_repo" ] && [ "$repo" = "$publish_repo" ] \
         && [ "${publish_repo%%/*}" = "${origin_repo%%/*}" ]; then
        echo "  binding: the declared channel repo ($repo) is not origin ($origin_repo) but IS the publish target"
        echo "  parsed from scripts/publish-public.sh, under the SAME owner — dev->public mirror split honored"
        echo "  (the promise ships there)."
      else
        echo "FAIL: SECURITY.md declares $repo but this repo is $origin_repo — declare YOUR channel repo and"
        echo "  enable PVR there, or change the security contact. (A dev->public split is honored only when the"
        echo "  declaration equals PUBLIC_REMOTE_DEFAULT in this tree's scripts/publish-public.sh AND that"
        echo "  target's owner equals the origin's owner.)"
        return 1
      fi
    fi
  fi
  # M2: set -f brackets the unquoted expansion so a glob in the operator-supplied probe string
  # reaches the probe literally instead of expanding against the current directory.
  set -f
  # shellcheck disable=SC2086  # $probe is an argument-borne command string; word-splitting is the contract
  if out=$($probe "repos/$repo/private-vulnerability-reporting" 2>&1); then rc=0; else rc=$?; fi
  set +f
  if [ "$rc" -ne 0 ]; then
    echo "UNVERIFIED: the probe ('$probe') could not reach the forge (rc $rc) — cannot confirm the advertised channel is live."
    printf '%s\n' "$out" | sed 's/^/  /'
    echo "  NOT a pass: verify.sh --require / CI escalates rc 2. Ensure gh + network + auth, or pass --probe-cmd."
    return 2
  fi
  if printf '%s\n' "$out" | grep -Eq '"enabled"[[:space:]]*:[[:space:]]*true'; then
    echo "security-channel-live: OK — private-vulnerability-reporting is ENABLED on $repo; the advertised channel is live."
    echo "  NOTE: proves the forge SETTING only — not that reports are triaged (operator rows own the SLAs)."
    return 0
  fi
  if printf '%s\n' "$out" | grep -Eq '"enabled"[[:space:]]*:[[:space:]]*false'; then
    echo "FAIL: SECURITY.md advertises GitHub private vulnerability reporting, but the forge says it is DISABLED on $repo —"
    echo "  the advertised primary channel is a dead letterbox (the T0-09 defect). Remedy: repo Settings →"
    echo "  enable 'Private vulnerability reporting', or change the advertised security contact in SECURITY.md."
    return 1
  fi
  echo "UNVERIFIED: the probe returned neither \"enabled\":true nor \"enabled\":false — API error or unexpected shape:"
  printf '%s\n' "$out" | sed 's/^/  /'
  echo "  NOT a pass: verify.sh --require / CI escalates rc 2."
  return 2
}

selftest() {
  st=0
  base=$(mktemp -d)
  trap 'rm -rf "$base"' EXIT INT TERM

  # ── stub probes (argument-borne; the negative leg is a STUB, never the live repo) ──
  cat > "$base/probe-true.sh" <<'EOF'
#!/bin/sh
echo '{"enabled":true}'
EOF
  cat > "$base/probe-false.sh" <<'EOF'
#!/bin/sh
echo '{"enabled":false}'
EOF
  cat > "$base/probe-down.sh" <<'EOF'
#!/bin/sh
echo 'stub: could not resolve host api.github.com' >&2
exit 12
EOF
  cat > "$base/probe-garbage.sh" <<'EOF'
#!/bin/sh
echo '<html>502 Bad Gateway</html>'
EOF

  # ── SECURITY.md fixtures ──
  mkdir -p "$base/ok" "$base/noadv" "$base/nochan" "$base/empty"
  cat > "$base/ok/SECURITY.md" <<'EOF'
# Security Policy

**Security contact:** GitHub private vulnerability reporting — this repo → **Security** → **Report a vulnerability**.

**Channel repo:** `Example-Owner/example-repo` — verified live by `conformance/security-channel-live.sh`.
EOF
  cat > "$base/noadv/SECURITY.md" <<'EOF'
# Security Policy

**Security contact:** security@example.org
EOF
  cat > "$base/nochan/SECURITY.md" <<'EOF'
# Security Policy

**Security contact:** GitHub private vulnerability reporting — this repo → **Security** → **Report a vulnerability**.
EOF

  # ── C2 fixtures: git working trees with a GitHub origin (remote-binding legs) ──
  mkdir -p "$base/gitmatch" "$base/gitmis" "$base/gitpub/scripts" "$base/gitforeign/scripts" "$base/okcaps"
  for _d in gitmatch gitmis gitpub gitforeign; do
    cp "$base/ok/SECURITY.md" "$base/$_d/SECURITY.md"
    git -c init.defaultBranch=main init -q "$base/$_d"
  done
  git -C "$base/gitmatch" remote add origin "https://github.com/Example-Owner/example-repo.git"
  git -C "$base/gitmis"   remote add origin "git@github.com:Other-Owner/other-repo.git"
  git -C "$base/gitpub"   remote add origin "https://github.com/Example-Owner/example-repo-dev.git"
  # gitpub: mismatched origin REPO under the SAME owner, and the declaration equals the tree's own
  # publish target — the owner-matched dev->public mirror split (the kit's own shape:
  # <owner>/kit-dev publishing to <owner>/kit), derived from the fixture's publish script.
  cat > "$base/gitpub/scripts/publish-public.sh" <<'EOF'
#!/bin/sh
PUBLIC_REMOTE_DEFAULT="https://github.com/Example-Owner/example-repo.git"
EOF
  # gitforeign: a FOREIGN-owner origin whose tree happens to carry a publish-public.sh naming the
  # kit-style target — the split must NOT be honored across owners (I-1: otherwise any adopter
  # tree could attest a setting on someone else's repo by shipping a publish script).
  git -C "$base/gitforeign" remote set-url origin "https://github.com/Some-Adopter/their-app.git" 2>/dev/null \
    || git -C "$base/gitforeign" remote add origin "https://github.com/Some-Adopter/their-app.git"
  cat > "$base/gitforeign/scripts/publish-public.sh" <<'EOF'
#!/bin/sh
PUBLIC_REMOTE_DEFAULT="https://github.com/Example-Owner/example-repo.git"
EOF
  # M1 fixture: an all-caps 'CHANNEL REPO:' declaration must still parse.
  cat > "$base/okcaps/SECURITY.md" <<'EOF'
# Security Policy

**Security contact:** GitHub private vulnerability reporting — this repo → **Security** → **Report a vulnerability**.

**CHANNEL REPO:** `Example-Owner/example-repo`
EOF
  # M2 stub: PASSes only if the glob in the probe string arrived UNEXPANDED.
  cat > "$base/probe-argcheck.sh" <<'EOF'
#!/bin/sh
if [ "$1" = "*" ]; then echo '{"enabled":true}'; else echo '{"enabled":false}'; fi
EOF

  _leg 0 "ENABLED"       "stubbed {\"enabled\":true} -> PASS (liveness anchor)"                       "$base/ok"     "sh $base/probe-true.sh"
  _leg 1 "DISABLED"      "stubbed {\"enabled\":false} -> FAIL (load-bearing negative, stub not live)" "$base/ok"     "sh $base/probe-false.sh"
  _leg 2 "UNVERIFIED"    "probe exits nonzero -> UNVERIFIED rc 2 (not a pass)"                        "$base/ok"     "sh $base/probe-down.sh"
  _leg 2 "UNVERIFIED"    "probe returns unparseable body -> UNVERIFIED rc 2"                          "$base/ok"     "sh $base/probe-garbage.sh"
  _leg 0 "N/A"           "PVR not advertised -> N/A with reason"                                      "$base/noadv"  "sh $base/probe-true.sh"
  _leg 0 "N/A"           "no SECURITY.md at all -> N/A (presence is security-policy.sh's row)"        "$base/empty"  "sh $base/probe-true.sh"
  _leg 1 "Channel repo"  "advertised without 'Channel repo:' -> FAIL with named remedy"               "$base/nochan" "sh $base/probe-true.sh"
  # C2 — remote-binding: the declaration must be BOUND to the tree it runs in.
  _leg 0 "equals this tree's origin" "C2: origin matches the declaration -> PASS, binding stated"     "$base/gitmatch" "sh $base/probe-true.sh"
  _leg 1 "Other-Owner/other-repo"    "C2: origin MISMATCHES the declaration -> FAIL (wrong-repo attestation — the load-bearing negative)" "$base/gitmis" "sh $base/probe-true.sh"
  _leg 0 "publish target"            "C2: mismatched origin but declaration = publish target -> PASS (dev->public split)" "$base/gitpub" "sh $base/probe-true.sh"
  _leg 1 "Some-Adopter/their-app"    "I-1: FOREIGN-owner origin + publish script naming the kit-style target -> FAIL (split is owner-matched, load-bearing negative)" "$base/gitforeign" "sh $base/probe-true.sh"
  # M1 — case-insensitive declaration strip.
  _leg 0 "ENABLED"       "M1: all-caps 'CHANNEL REPO:' still parses -> PASS"                          "$base/okcaps" "sh $base/probe-true.sh"
  # M2 — a glob in the operator-supplied probe string must reach the probe UNEXPANDED (set -f
  # bracket). Run from $base — a dir guaranteed to contain files — so an unguarded expansion fires.
  if _out=$( cd "$base" && check_channel "$base/ok" "sh $base/probe-argcheck.sh *" 2>&1 ); then _rc=0; else _rc=$?; fi
  if [ "$_rc" = 0 ] && printf '%s\n' "$_out" | grep -q "ENABLED"; then
    echo "PASS: selftest — M2: probe glob arrives unexpanded (set -f bracket) (rc $_rc)"
  else
    echo "FAIL: selftest — M2: probe glob was expanded before the probe ran: expected rc 0 + /ENABLED/; got rc $_rc; out=[$_out]"; st=1
  fi

  if [ "$st" -ne 0 ]; then echo "security-channel-live --selftest: FAIL"; return 1; fi
  echo "security-channel-live --selftest: OK (true/false/down/garbage/noadv/nofile/nochan + remote-binding match/mismatch/publish-target/foreign-owner + caps-parse + glob-suppression all behaved; fixtures cleaned by trap)"
  return 0
}

# ── selftest oracle (below the selftest() marker — never mutated by the non-vacuity sweep) ──
_leg() {  # <expected-rc> <output-needle> <label> <dir> <probe-cmd>
  if _out=$(check_channel "$4" "$5" 2>&1); then _rc=0; else _rc=$?; fi
  if [ "$_rc" = "$1" ] && printf '%s\n' "$_out" | grep -q "$2"; then
    echo "PASS: selftest — $3 (rc $_rc)"
  else
    echo "FAIL: selftest — $3: expected rc $1 + /$2/; got rc $_rc; out=[$_out]"; st=1
  fi
}

DIR=.
PROBE=$PROBE_DEFAULT
case "${1:-}" in
  --selftest) selftest; exit $? ;;
esac
while [ $# -gt 0 ]; do
  case "$1" in
    --probe-cmd)
      [ $# -ge 2 ] || { echo "usage: security-channel-live.sh [project-dir] [--probe-cmd '<cmd>'] | --selftest" >&2; exit 3; }
      PROBE=$2; shift 2 ;;
    -*) echo "usage: security-channel-live.sh [project-dir] [--probe-cmd '<cmd>'] | --selftest" >&2; exit 3 ;;
    *)  DIR=$1; shift ;;
  esac
done
if check_channel "$DIR" "$PROBE"; then exit 0; else exit $?; fi
