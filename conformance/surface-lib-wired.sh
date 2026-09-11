#!/bin/sh
# surface-lib-wired.sh — regression-lock for the two K13 arms added to conformance/surface-lib.sh's
# has_deploy_surface (GATE-SUBJECT-IS-THE-ADOPTERS-SYSTEM, Slice 1: detection). surface-lib.sh itself
# ships with NO --selftest by design (aggregate-exclusions.txt) — its predicates were graded solely
# through readiness.sh's TSV-driven fixture-maker, which plants exactly ONE fixture per predicate
# name (a Dockerfile for has_deploy_surface) and so cannot exercise a SECOND or THIRD arm of the same
# predicate independently. This file is has_deploy_surface's `-wired.sh` companion, the same
# convention promotion-readiness-wired.sh etc. use for their own subject: it sources surface-lib.sh
# directly and proves each new arm RED-before / green-after, plus a stays-green (no over-trigger) leg,
# so a future refactor cannot silently kill either arm without a test noticing.
#
# What it changes: nothing — read-only fixtures under mktemp, sourced against the real surface-lib.sh.
# Usage: sh conformance/surface-lib-wired.sh [--selftest]
# Exit: 0 = ok · 1 = a leg failed · 2 = usage. POSIX sh; dash-clean.
set -eu

SURFACE_LIB="${KIT_SURFACE_LIB:-$(dirname "$0")/surface-lib.sh}"
[ -f "$SURFACE_LIB" ] || { echo "FAIL: surface-lib-wired — missing $SURFACE_LIB"; exit 1; }
# shellcheck source=/dev/null  # resolved at runtime from $0, not statically followable
. "$SURFACE_LIB"
# wf_is_deploy is consulted by the workflow arm; surface-lib.sh does not source it, its callers do
# (see surface-lib.sh's own header). A no-op stub is enough here: none of this file's fixtures carry
# a .github/workflows/*.yml, so the real implementation is never reached and a stub cannot mask it.
wf_is_deploy() { return 1; }

selftest() {
  st=0
  d=$(mktemp -d)
  # Trap-clean: every fixture below is a throwaway tree under $d. `[ -n ]` guards the empty-var case
  # so this can never widen to an unintended path (the same idiom promotion-readiness-wired.sh uses).
  trap '[ -n "${d:-}" ] && rm -rf "$d"' EXIT

  # ---- PaaS-manifest arm ------------------------------------------------------------------------
  # RED-before (this leg's fixture is what failed on the unmodified surface-lib.sh, captured in the
  # build report): a repo-root fly.toml with NO Dockerfile and NO .github/workflows is a live PaaS
  # deploy surface and must now be detected.
  rm -rf "$d/paas"; mkdir -p "$d/paas"
  printf 'app = "demo"\n' > "$d/paas/fly.toml"
  if has_deploy_surface "$d/paas"; then echo "PASS: fly.toml-only fixture is a deploy surface"
  else echo "FAIL: fly.toml-only fixture NOT detected as a deploy surface"; st=1; fi

  # Coverage lock — every filename in the PaaS ladder independently triggers, one fixture per name,
  # so a future refactor that drops one entry from the list cannot pass silently.
  # ⚠️ app.json is NOT in this list (fix round, F1): it is the Expo/React-Native app config, not a
  # deploy manifest — a low-precision signal removed from the ladder. Its stays-green leg is below.
  for _f in railway.toml railway.json Procfile fly.toml render.yaml render.yml nixpacks.toml vercel.json netlify.toml; do
    rm -rf "$d/one"; mkdir -p "$d/one"
    : > "$d/one/$_f"
    if has_deploy_surface "$d/one"; then echo "PASS: $_f alone is a deploy surface"
    else echo "FAIL: $_f alone NOT detected as a deploy surface"; st=1; fi
  done
  rm -rf "$d/plat"; mkdir -p "$d/plat/.platform"
  if has_deploy_surface "$d/plat"; then echo "PASS: .platform/ dir alone is a deploy surface"
  else echo "FAIL: .platform/ dir alone NOT detected as a deploy surface"; st=1; fi

  # F1 STAYS-GREEN — an app.json-only tree (the Expo/RN case) is NOT a deploy surface. Non-vacuity for
  # the F1 exclusion: re-adding app.json to the ladder would RED this leg.
  rm -rf "$d/expo"; mkdir -p "$d/expo"
  printf '{ "expo": { "name": "demo" } }\n' > "$d/expo/app.json"
  if has_deploy_surface "$d/expo"; then echo "FAIL: F1 — app.json alone WAS detected as a deploy surface (the low-precision RN false-positive is back)"; st=1
  else echo "PASS: F1 — app.json alone is NOT a deploy surface (Expo/RN config is not a deploy manifest)"; fi

  # ---- live-URL / deploy-target declaration arm -------------------------------------------------
  # RED-before: a RUNBOOK.md declaring a live URL, no PaaS file, no Dockerfile.
  rm -rf "$d/decl"; mkdir -p "$d/decl"
  printf '# RUNBOOK\n\nLive URL: https://ledger.example.com\n' > "$d/decl/RUNBOOK.md"
  if has_deploy_surface "$d/decl"; then echo "PASS: RUNBOOK 'Live URL: https://…' is a deploy surface"
  else echo "FAIL: RUNBOOK 'Live URL: https://…' NOT detected as a deploy surface"; st=1; fi

  # field/marker tolerance: bold-wrapped key, list marker, and CLAUDE.md as the carrier, and a named
  # PaaS token (no literal URL) — each on its own fixture so one broken idiom cannot hide behind another.
  rm -rf "$d/bold"; mkdir -p "$d/bold"
  printf '# RUNBOOK\n\n- **Deployed at:** https://svc.example.com\n' > "$d/bold/RUNBOOK.md"
  if has_deploy_surface "$d/bold"; then echo "PASS: bold-wrapped '**Deployed at:**' declaration detected"
  else echo "FAIL: bold-wrapped '**Deployed at:**' declaration NOT detected"; st=1; fi

  rm -rf "$d/claude"; mkdir -p "$d/claude"
  printf '# CLAUDE\n\n- **Deploy target:** Railway\n' > "$d/claude/CLAUDE.md"
  if has_deploy_surface "$d/claude"; then echo "PASS: CLAUDE.md 'Deploy target: Railway' (named PaaS, no URL) detected"
  else echo "FAIL: CLAUDE.md 'Deploy target: Railway' NOT detected"; st=1; fi

  # STAYS-GREEN — the unfilled '[...]' template placeholder is NOT a declaration.
  rm -rf "$d/placeholder"; mkdir -p "$d/placeholder"
  printf '# RUNBOOK\n\nLive URL: [your production URL]\n' > "$d/placeholder/RUNBOOK.md"
  if has_deploy_surface "$d/placeholder"; then echo "FAIL: '[your production URL]' placeholder wrongly triggered a deploy surface"; st=1
  else echo "PASS: '[your production URL]' placeholder does NOT trigger (unfilled template)"; fi

  # STAYS-GREEN — a value that is neither a URL nor a named PaaS token must not over-trigger.
  rm -rf "$d/vague"; mkdir -p "$d/vague"
  printf '# RUNBOOK\n\nDeploy target: TBD\n' > "$d/vague/RUNBOOK.md"
  if has_deploy_surface "$d/vague"; then echo "FAIL: 'Deploy target: TBD' wrongly triggered a deploy surface"; st=1
  else echo "PASS: 'Deploy target: TBD' does NOT trigger (no real value)"; fi

  # ---- STAYS-GREEN GUARD — no over-trigger on a bare library/CLI tree ----------------------------
  rm -rf "$d/bare"; mkdir -p "$d/bare/src"
  printf '# demo\n' > "$d/bare/README.md"
  printf 'export const x = 1;\n' > "$d/bare/src/lib.ts"
  if has_deploy_surface "$d/bare"; then echo "FAIL: a bare library tree wrongly triggered a deploy surface"; st=1
  else echo "PASS: a bare library tree (no signal) stays N/A"; fi

  # ---- REGRESSION — the pre-existing Dockerfile arm must still fire (unaffected by the new arms) --
  rm -rf "$d/docker"; mkdir -p "$d/docker"
  : > "$d/docker/Dockerfile"
  if has_deploy_surface "$d/docker"; then echo "PASS: Dockerfile arm unaffected (still detects)"
  else echo "FAIL: Dockerfile arm regressed — no longer detects a bare Dockerfile"; st=1; fi

  if [ "$st" -eq 0 ]; then echo "OK: surface-lib-wired selftest"; else echo "FAIL: surface-lib-wired selftest"; fi
  return $st
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  "") command -v has_deploy_surface >/dev/null 2>&1 && { echo "OK: surface-lib producer present"; exit 0; } || { echo "FAIL: has_deploy_surface not defined"; exit 1; } ;;
  *) echo "usage: surface-lib-wired.sh [--selftest]" >&2; exit 2 ;;
esac
