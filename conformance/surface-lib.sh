#!/bin/sh
# surface-lib.sh — the SURFACE-TRIGGER predicates for the conditional readiness checks
# (CONFORMANCE-DOC-FAMILIES-MERGE, D-240828-4). SOURCED, never executed, the same pattern
# conformance/wf-helpers.sh and union-lib.sh use. No `set -eu` (the sourcing script owns shell
# options); functions only — no dispatch, no exit, no top-level side effects, no verdict. NOT a
# conformance check: linted by shellcheck.sh, declared in aggregate-exclusions.txt as a library.
# Requires wf-helpers.sh (wf_is_deploy); the sourcing script sources both.
#
# WHY IT EXISTS. Nine `*-ready.sh` checks each carried their own copy of one of five predicates
# ("does this project have a data surface / a deploy surface / an AI feature / an agent / sensitive
# data?"). Five semantics, thirteen copies, nothing forcing them to agree — a widening in one was
# invisible to the others. Each function below is the STRONGEST shipped implementation, copied
# verbatim from the file named in its header comment, so the fold lost no detection power.
#
# DIRECTIONAL SAFETY (why every detector is conservative): these predicates ESCALATE, never EXEMPT.
# A MISS means a project is not nagged; the matching conformance/*-readiness.md stays the gate of
# record and a human applies it regardless. A false negative is a missed prompt, never an exemption.

# has_data_surface <dir>: does <dir> handle persistent data? Conservative; a MISS escalates, never
# exempts. Copied verbatim from the RETIRED dr-ready check (test-data-ready carried the same body and
# said so in its comment: "same signals"). Both are now readiness.tsv cases; the retired files were
# deleted by CONFORMANCE-FAMILIES-SHIM-DELETION and their bodies are in the CHANGELOG.
has_data_surface() {
  _d="$1"
  if [ -f "$_d/.env.example" ] && grep -Eiq 'DATABASE_URL|DB_URL|POSTGRES|MYSQL|MARIADB|MONGO|REDIS_URL|CONNECTION_STRING' "$_d/.env.example"; then
    return 0
  fi
  for _md in prisma migrations db/migrate alembic; do
    if [ -d "$_d/$_md" ]; then return 0; fi
  done
  for _cf in "$_d/compose.yaml" "$_d/compose.yml" "$_d/docker-compose.yml" "$_d/docker-compose.yaml"; do
    [ -f "$_cf" ] || continue
    if grep -Eiq 'image:[[:space:]]*"?(postgres|mysql|mariadb|mongo|redis)' "$_cf"; then return 0; fi
  done
  return 1
}

# has_deploy_surface <dir>: does <dir> deploy a running service? A Dockerfile, a repo-root PaaS
# descriptor, a workflow whose STRUCTURE says deploy (wf_is_deploy — a GitHub `environment:` key or a
# deploy-ish job KEY, never a free-text step name), or a RUNBOOK/CLAUDE declaration of a live service.
# The Dockerfile + workflow arms were copied verbatim from the RETIRED observability-ready check,
# which carried the same body as preview-env-ready and resilience-ready (all three now readiness.tsv
# cases). GATE-SUBJECT-IS-THE-ADOPTERS-SYSTEM (K13) added the two arms below: a PaaS-deployed service
# (Railway/Fly/Render/…) carries none of the three original signals and read N/A — a live service
# graded "not a service." Both new arms are ESCALATE-ONLY, the same directional-safety doctrine as
# the rest of this file (see header): a MISS still leaves the *-ready.md checklist as the gate of
# record, never an exemption.
has_deploy_surface() {
  _d="$1"
  if [ -f "$_d/Dockerfile" ]; then return 0; fi
  # PaaS-manifest arm (K13) — a repo-root descriptor naming a managed deploy platform. A fixed,
  # conservative filename set (not claimed exhaustive — see the declaration arm below for the
  # portable escape on an unlisted vendor, so this predicate does not merely re-fork on the next PaaS).
  # ⚠️ app.json is DELIBERATELY EXCLUDED (fix round, F1): it is the entire Expo/React-Native
  # ecosystem's app config, not a deploy manifest — a low-precision signal that would fire on every RN
  # project. Heroku's real signal is the Procfile (kept above); an unlisted-vendor adopter still has
  # the declaration arm below as the portable escape.
  for _paas in railway.toml railway.json Procfile fly.toml render.yaml render.yml nixpacks.toml vercel.json netlify.toml; do
    [ -f "$_d/$_paas" ] && return 0
  done
  [ -d "$_d/.platform" ] && return 0
  if [ -d "$_d/.github/workflows" ]; then
    for _wfx in "$_d"/.github/workflows/*.yml "$_d"/.github/workflows/*.yaml; do
      [ -f "$_wfx" ] || continue
      if wf_is_deploy "$_wfx"; then return 0; fi
    done
  fi
  # Live-URL / deploy-target declaration arm (K13) — the PORTABLE ESCAPE, so an adopter on an
  # unlisted PaaS is never stranded. Reuses this file's own declaration idiom (declares_sensitive /
  # is_agentic below): a field-leading RUNBOOK.md/CLAUDE.md line ('Live URL:' / 'Deploy target:' /
  # 'Deployed at:', tolerant of list/bold markers, the colon binding the field) whose value is a real
  # `https?://…` URL or a named PaaS token — never the unfilled `[...]` template placeholder.
  for _dmf in "$_d/RUNBOOK.md" "$_d/CLAUDE.md"; do
    [ -f "$_dmf" ] || continue
    _dline=$(grep -Ei '^[-*[:space:]]*(live url|deploy target|deployed at)[^:]*:' "$_dmf" 2>/dev/null | head -1) || true
    [ -n "$_dline" ] || continue
    _dval=${_dline#*:}
    # strip leading list/bold/italic markup + surrounding whitespace so the placeholder test below
    # sees the TRUE value, not '** [...]' — mirrors is_agentic's tolerance of a bold-wrapped key.
    _dval=$(printf '%s' "$_dval" | sed -E 's/^[[:space:]*_-]+//; s/[[:space:]]+$//')
    case "$_dval" in
      \[*\]) continue ;;   # unfilled '[...]' template placeholder — not a declaration
    esac
    printf '%s' "$_dval" | grep -Eiq 'https?://|railway|render\.com|fly\.io|vercel|netlify|heroku|nixpacks|platform\.sh' && return 0
  done
  return 1
}

# has_service_surface <dir>: the same question under the name the design used. It is an ALIAS, not a
# second semantics — three checks called this predicate "deployable" and the design called it a
# service surface; one implementation answers both so the names cannot drift apart.
has_service_surface() { has_deploy_surface "$1"; }

# has_ai_surface <dir> [card]: is <dir> an AI feature? Copied verbatim from the RETIRED
# responsible-ai-ready check (the stronger of the two shipped bodies) with the ONE
# difference between it and the retired eval-ready check's promoted to an explicit argument rather than
# silently merged: responsible-ai also treats a bare AI-SYSTEM-CARD as evidence of an AI feature,
# eval-ready does not. Passing `card` selects the wider set. Merging them would have WIDENED
# eval-ready (a card-only project would newly owe an EVAL-PLAN) — a real behaviour change, and this
# slice is a fold, not a policy change. Board it separately if the widening is wanted.
has_ai_surface() {
  _d="$1"; _mode="${2:-}"
  [ -d "$_d/evals" ] && return 0
  for _p in "$_d/EVAL-PLAN.md" "$_d/docs/EVAL-PLAN.md" "$_d/docs/sign-offs/EVAL-PLAN.md" "$_d/evals/EVAL-PLAN.md"; do
    [ -f "$_p" ] && return 0
  done
  if [ "$_mode" = "card" ]; then
    for _p in "$_d/AI-SYSTEM-CARD.md" "$_d/docs/AI-SYSTEM-CARD.md" "$_d/docs/sign-offs/AI-SYSTEM-CARD.md"; do
      [ -f "$_p" ] && return 0
    done
  fi
  for _m in "$_d/RUNBOOK.md" "$_d/CLAUDE.md"; do
    # tolerate markdown between key and value (e.g. '**AI feature:** yes') — bold must still bind.
    [ -f "$_m" ] && grep -Eiq 'ai feature:[^[:alnum:]]*(yes|true)' "$_m" && return 0
  done
  return 1
}

# is_agentic <dir>: does <dir> declare that it runs autonomous agents? Copied verbatim from the
# RETIRED agentops-ready check — the structured 'Agentic:' field, field-leading, tolerating
# list/bold markers, a bold-wrapped key with the colon outside the bold, and an italic annotation
# before the colon. The unfilled [yes / no] placeholder is skipped; only 'yes' triggers.
is_agentic() {
  _d="$1"
  for _f in "$_d/CLAUDE.md" "$_d/RUNBOOK.md"; do
    [ -f "$_f" ] || continue
    _line=$(grep -Ei '^[-*[:space:]]*agentic[^:]*:' "$_f" 2>/dev/null | head -1 | tr '[:upper:]' '[:lower:]') || true
    [ -n "$_line" ] || continue
    printf '%s' "$_line" | grep -Eq '\[[^]]*yes[^]]*/[^]]*\]' && continue
    _val=${_line#*:}; printf '%s' "$_val" | grep -Eqw 'yes' && return 0
  done
  return 1
}

# declares_sensitive <dir>: does a Data-classification line name Confidential/Restricted with a REAL
# value (not the [Public / Internal / Confidential / Restricted] template placeholder)? Copied
# verbatim from the RETIRED privacy-ready check. A real value with an unrelated bracket annotation
# (e.g. "restricted [phi/hipaa]") must NOT be skipped — that would fail-open and drop a sensitive
# project out of the gate.
declares_sensitive() {
  _d="$1"
  for _f in "$_d/CLAUDE.md" "$_d/RUNBOOK.md"; do
    [ -f "$_f" ] || continue
    _line=$(grep -Ei 'data classification[^:]*:' "$_f" 2>/dev/null | head -1 | tr '[:upper:]' '[:lower:]') || true
    [ -n "$_line" ] || continue
    printf '%s' "$_line" | grep -Eq '\[[^]]*(public|internal|confidential|restricted)[^]]*/[^]]*\]' && continue
    _val=${_line#*:}; printf '%s' "$_val" | grep -Eq 'confidential|restricted' && return 0
  done
  return 1
}
