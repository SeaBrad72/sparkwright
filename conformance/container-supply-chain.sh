#!/bin/sh
# container-supply-chain.sh — conditional, fail-closed image supply-chain check.
#
# For each profile directory: IF a Dockerfile is present, the image MUST be
# multi-stage and run as a non-root final USER, AND its sibling ci.yml MUST declare
# gate-image-sbom + gate-image-provenance with a digest-bound attestation. Profiles
# WITHOUT a Dockerfile are N/A (skipped), never failed — this keeps the standard
# conditional (DEVELOPMENT-STANDARDS.md §14) so non-service stacks aren't forced to
# containerize. Checks contract identifiers, not stack tools — stack-neutral.
# Run at the Review gate (DEVELOPMENT-PROCESS.md §7).
set -eu

ROOT="${1:-profiles}"
fail=0
checked=0

for dir in "$ROOT"/*/; do
  df="${dir}Dockerfile"
  name="${dir%/}"
  if [ ! -f "$df" ]; then
    echo "N/A (no Dockerfile): $name"
    continue
  fi
  checked=$((checked + 1))
  ci="${dir}ci.yml"
  pfail=0

  # 1. multi-stage: at least two FROM stages
  froms=$(grep -cE '^[[:space:]]*FROM[[:space:]]' "$df" || true)
  if [ "$froms" -lt 2 ]; then
    echo "FAIL $name: Dockerfile not multi-stage (need >=2 FROM, found $froms)"
    pfail=1
  fi

  # 2. non-root: the FINAL USER directive governs the runtime. Normalize before matching —
  #    strip an optional `:group` and lowercase — then reject root/0/empty. Also reject a
  #    build-time variable (USER $X / ${X}): it resolves at build, so it can't be statically
  #    attested as non-root. (Docker allows `USER uid:gid`, so a bare `case root|0` is bypassable.)
  last_user=$(grep -E '^[[:space:]]*USER[[:space:]]' "$df" | tail -1 | awk '{print $2}')
  uid=${last_user%%:*}
  uid=$(printf '%s' "$uid" | tr '[:upper:]' '[:lower:]')
  case "$uid" in
    "" | root | 0)
      echo "FAIL $name: final USER is root or unset ('$last_user')"
      pfail=1
      ;;
    *\$*)
      echo "FAIL $name: final USER is a build-time variable ('$last_user') — cannot be statically attested non-root"
      pfail=1
      ;;
  esac

  # 3. sibling ci.yml declares both conditional image gate-ids. Anchored regex (reused from
  #    ci-gates.sh) so a mention in a comment or quoted value can't satisfy the gate.
  if [ ! -f "$ci" ]; then
    echo "FAIL $name: Dockerfile present but no sibling ci.yml"
    pfail=1
  else
    for id in gate-image-sbom gate-image-provenance gate-image-vuln; do
      grep -Eq "^[[:space:]]*(-[[:space:]]+)?id:[[:space:]]*[\"']?${id}[\"']?[[:space:]]*(#.*)?\$" "$ci" \
        || { echo "FAIL $name: ci.yml missing $id"; pfail=1; }
    done
    # 4. provenance binds the image DIGEST: require `subject-digest:` as a YAML key. That is
    #    the binding; push-to-registry only controls where the attestation is stored.
    grep -Eq "^[[:space:]]*subject-digest:" "$ci" || {
      echo "FAIL $name: image provenance not digest-bound (need a subject-digest: key)"
      pfail=1
    }
  fi

  if [ "$pfail" -eq 0 ]; then
    echo "OK $name: container supply-chain present (multi-stage, non-root, image SBOM + digest provenance)"
  else
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "container-supply-chain: FAIL" >&2
  exit 1
fi
echo "container-supply-chain: OK ($checked profile(s) with a Dockerfile checked; others N/A)"
