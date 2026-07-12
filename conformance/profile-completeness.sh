#!/bin/sh
# profile-completeness.sh — verify every stack profile fills the _TEMPLATE.md contract.
# For each profiles/*.md except _TEMPLATE.md: all 11 section headings present, no leftover
# [...] placeholder, and (if a companion profiles/<stack>/ci.yml exists) it passes ci-gates.sh.
# Usage: sh conformance/profile-completeness.sh   (run from repo root)
set -eu

HERE=$(dirname "$0")
fail=0

for prof in profiles/*.md; do
  base=$(basename "$prof")
  [ "$base" = "_TEMPLATE.md" ] && continue
  name="${base%.md}"

  miss=""
  i=1
  while [ "$i" -le 11 ]; do
    grep -Eq "^## ${i}\. " "$prof" || miss="$miss §${i}"
    i=$((i + 1))
  done
  if [ -n "$miss" ]; then echo "FAIL $base: missing section(s):$miss"; fail=1; else echo "PASS $base: 11 sections"; fi

  if grep -Fq '[...]' "$prof"; then echo "FAIL $base: leftover [...] placeholder(s)"; fail=1; fi

  if [ -f "profiles/${name}/ci.yml" ]; then
    if sh "${HERE}/ci-gates.sh" "profiles/${name}/ci.yml" >/dev/null 2>&1; then
      echo "PASS $base: companion ci.yml satisfies §14"
    else
      echo "FAIL $base: companion ci.yml missing required gates"; fail=1
    fi
  fi

  # A profile that ships a compose.yaml is a deployable SERVICE stack — it must also ship a
  # starter scaffold/, so `incept` can deliver a runnable, CI-green starter for it. Non-service
  # stacks (ml/data-engineering/terraform — no compose.yaml) are exempt by design. (go/no-go B2.)
  if [ -f "profiles/${name}/compose.yaml" ] && [ ! -d "profiles/${name}/scaffold" ]; then
    echo "FAIL $base: ships compose.yaml (service stack) but no scaffold/ — incept can't deliver a runnable starter"; fail=1
  fi

  # CLI archetype reference: typescript-node ships a non-service CLI scaffold so the kit proves
  # its CI contract holds for a CLI shape, not just /healthz services. Assert it exists, is a CLI
  # (package.json declares a bin), carries a test, and is NOT a service (no server/compose).
  if [ "$name" = "typescript-node" ]; then
    cliscaf="profiles/typescript-node/scaffold-cli"; cfail=0
    [ -d "$cliscaf" ] || { echo "FAIL $base: missing CLI archetype reference scaffold-cli/"; cfail=1; }
    if [ "$cfail" = "0" ]; then
      { [ -f "$cliscaf/package.json" ] && grep -Eq '"bin"[[:space:]]*:' "$cliscaf/package.json"; } \
        || { echo "FAIL $base: scaffold-cli/ package.json missing or declares no bin (not a CLI)"; cfail=1; }
      ls "$cliscaf"/test/*.test.ts >/dev/null 2>&1 \
        || { echo "FAIL $base: scaffold-cli/ has no test"; cfail=1; }
      if [ -e "$cliscaf/compose.yaml" ] || ls "$cliscaf"/src/server.* >/dev/null 2>&1; then
        echo "FAIL $base: scaffold-cli/ ships a service (server/compose) — must be a non-service CLI"; cfail=1
      fi
    fi
    if [ "$cfail" = "0" ]; then
      echo "PASS $base: CLI archetype reference (scaffold-cli/) is contract-shaped + non-service"
    else
      fail=1
    fi
  fi
done

if [ "$fail" -ne 0 ]; then echo "FAIL: profile-completeness"; exit 1; fi
echo "OK: all profiles complete and conformant"
exit 0
