# Slice 9f — Beginner On-Ramp (design)

**Date:** 2026-06-10 · **Arc:** Slice 9, Tier 2 (R6) · **Version target:** MINOR → **v2.31.0**
**Input:** review beginner persona (scored **4/10**, lowest) + the **A6 dogfood** findings (`docs/superpowers/reviews/2026-06-10-dogfood-timing.md`). A6 proved the mechanical bootstrap is fine (~1s, clean); the friction is **cognitive/orientation** — F1 no prerequisite preflight, F2 silent `CLAUDE.md→ENGINEERING-PRINCIPLES` rename, F3 no glossary, F4 no solo track.

## Scope (ratified at brainstorm)

Four orientation fixes. Preflight depth: **universal always + optional per-stack**. No change to the loop machinery — this slice reduces *cognitive* friction only.

## Components

### 1. `scripts/preflight.sh` (new — fail fast with fixes; F1)
- **Universal check (always):** `jq` (the guard + 3 conformance scripts hard-require it — the cryptic-failure source A6 found), `git`, POSIX `sh`. Each missing tool prints a one-line install hint (`jq → brew install jq | apt-get install jq | …`). Exit non-zero if any universal prerequisite is missing; exit 0 + "all prerequisites present" otherwise.
- **Optional `--stack <name>`:** also checks that stack's primary toolchain from a bounded map: `typescript-node→node,npm`; `python|ml|data-engineering→python3,pip`; `go→go`; `dotnet→dotnet`; `rust→cargo`; `java-spring→java,mvn`; `kotlin→java`; `terraform→terraform`. Each missing tool → install hint. Unknown stack → non-fatal "no toolchain map for <x>; see its profile."
- **`--selftest`** (CI-gated): assert the detector flags a deliberately-absent tool (probe a guaranteed-missing command name) and passes for a present one (`sh` itself). Corpus inside the script.
- POSIX `sh`, dash-clean. Lives in `scripts/` → **not control-plane** (agent-editable).

### 2. Rename disclosure (F2)
- `scripts/incept.sh`: print a banner at the **top** of the next-steps output — *"Note: the kit's principles doc moved to `ENGINEERING-PRINCIPLES.md`; the new `CLAUDE.md` is YOUR project guide (charter, config, roles)."*
- `START-HERE.md`: a one-line note where it first references `CLAUDE.md`, flagging that `incept` renames it.

### 3. `GLOSSARY.md` (new — F3)
One page at repo root (most discoverable); linked from `START-HERE.md` + `README.md`. ~12 load-bearing terms, 1–2 sentences each, each linking to its authoritative section (a launchpad, not a fork): Inception (Phase 0); the loop (Discover→Plan→Build→Review→Release→Done); contract→reference→conformance; ratification (agents propose, humans ratify); autonomy tiers (L1/L2/L3); the guard (speed-bump, not boundary); the 7 CI gates; waiver (governed exception); Stage 1–4 (maturity, → `ORG-ROLLOUT.md`); profile (your stack); control-plane; green ≠ verified.

### 4. Solo / lite track (F4)
A `## Solo / lite track` section in `START-HERE.md`:
- **builder ≠ reviewer, solo:** merge your own PR via **owner admin-merge** — GitHub logs it as a bypass, which IS the audit trail of "solo maintainer self-ratified" (what this kit's own repo does). A second engineer joining flips on real review with zero reconfiguration.
- **Deferrable gates at solo / Stage-1 scale:** coverage/SBOM/provenance/a11y can ride the 9c waiver ramp (`templates/WAIVER-REGISTER.md`); `secret-scan` + `branch-protection` stay non-negotiable. You begin at **Stage 1** of the 9e maturity model.
- One place; no separate doc to drift.

## Integration & wiring
- `incept.sh` runs the **universal** preflight at startup; on failure, aborts with preflight's message (a beginner can't get past incept into cryptic guard failures). Agent-editable.
- `.github/workflows/ci.yml`: add `sh scripts/preflight.sh --selftest` to the conformance job. **Control-plane → human `cp`** (the one cp this slice).
- `conformance/README.md`: index the preflight selftest.

## Files

| File | Change | Owner |
|------|--------|-------|
| `scripts/preflight.sh` | **New** — universal + `--stack` checks + `--selftest` | agent |
| `GLOSSARY.md` | **New** — one-page term launchpad | agent |
| `scripts/incept.sh` | Rename banner + startup universal-preflight call | agent |
| `START-HERE.md` | preflight-first line · rename note · `## Solo / lite track` · GLOSSARY link | agent |
| `README.md` | GLOSSARY link | agent |
| `conformance/README.md` | preflight selftest index row | agent |
| `.github/workflows/ci.yml` | `preflight.sh --selftest` step | **human `cp`** |
| `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-SLICE9.md` | 2.31.0; 9f row → shipped | agent |

## Verification
- `sh scripts/preflight.sh` on this machine → exit 0 (jq/git/sh present); `--stack python` etc. → checks the mapped tools; a simulated missing tool (via `--selftest`) → detected, exit non-zero.
- `dash -n scripts/preflight.sh` clean.
- `incept.sh` in a temp repo still completes (preflight passes where jq/git present); aborts cleanly if the universal check fails.
- `sh conformance/inception-done.sh` still PASS; bootstrap CI unaffected (jq/git present in CI).
- `sh conformance/check-links.sh` green (GLOSSARY + START-HERE/README links resolve).
- Anonymization: generic throughout (no PBS/sector/personal names) — [[kit-anonymization]].
- Governance: feature branch → PR → human ratification; the `.github/workflows` step applied by human `cp`.

## Out of scope / deferred
- Toolchain *installation* (preflight detects + instructs; it never installs).
- A separate `QUICKSTART-LITE.md` (the solo track lives in START-HERE; a standalone quickstart risks duplicating it — revisit only if START-HERE grows unwieldy).
- 9g (stack-decision aid) — the *undecided* team is a sibling slice; 9f serves the beginner who has (or accepts the default) stack.

## Known implications
- The per-stack toolchain map is a bounded `case` over the 10 profiles; a new profile must add a row (cheap, and the unknown-stack branch degrades gracefully). Documented in the script header.
