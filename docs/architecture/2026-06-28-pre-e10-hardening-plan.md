# Implementation plan — pre-E10 hardening (guard symmetry + tag-time CI gate)

**Planned by dogfooding `skills/plan/SKILL.md`** (11th self-host). Source design: `docs/architecture/2026-06-28-pre-e10-hardening-design.md` (owner-approved 2026-06-28; `conformance/` + `adapters/`; bounded-poll + degrade-open).

## Goal
Ship one combined AMBER slice: (A) close the guard's redirect-form shell gap for `conformance/` + `adapters/` (two-matcher symmetry), and (B) add a forge-neutral, bounded-poll, degrade-open tag-time CI gate to `release-tag.sh` — proven non-vacuous, VERSION → 3.68.0.

## Architecture
Part A edits two regexes in `guard-core.sh` (`:82` mention + `:85` redirect) to list `conformance/[^[:space:]]*` and `adapters/[^[:space:]]*`, mirroring `skills/[^[:space:]]*`; proven by new `conformance/agent-autonomy.sh` deny/allow cases. Part B adds an injectable `ci_probe()` + a bounded-poll `ci_gate()` to `release-tag.sh`, called in `run()` after the `--dry-run` early-return and before `git tag`; proven by 4 new `--selftest` cases (probe injected via env, no network). The existing `release-tag-wired.sh` lock runs `release-tag.sh --selftest`, so the new cases are exercised for free.

## Tech stack
POSIX sh (guard, release-tag, fixtures), Python3 (`apply.py`), no new deps. `gh --jq` for the default CI probe (overridable, so tests need no gh).

## Global constraints (verbatim from the design + standing process)
- **Two-matcher symmetry** — add `conformance/` + `adapters/` to BOTH `guard-core.sh:82` (mention) and `:85` (redirect). Mirror the `skills/[^[:space:]]*` form exactly.
- **Degrade-open, forge-neutral** — the tag-gate refuses ONLY on a definitively-failed CI; on no-gh / non-GitHub / no-run / poll-timeout it warns + proceeds. Pure-git path unchanged when gh absent.
- **Injectable probe** — `RELEASE_TAG_CI_PROBE` overrides the default gh lookup; `RELEASE_TAG_CI_TIMEOUT` (default 600) + `RELEASE_TAG_CI_INTERVAL` (default 15) bound the poll. Selftest injects a stub → no network.
- **Non-vacuity** — guard: the new redirect-deny case must FAIL against the pre-fix guard; tag-gate: the CI-failure case must refuse (rc 1) — a no-op gate fails it.
- **No new gate/claim/seat** — extend `agent-autonomy.sh` (run by `verify.sh`) + `release-tag.sh --selftest` (run by `release-tag-wired.sh`). FLOOR.
- **AMBER** — author under `scratchpad/hardening/`, idempotent `apply.py`, clone dry-run. Agent never applies/commits/pushes/merges/tags.
- **Version finishing in apply.py** — VERSION 3.67.0 → **3.68.0**, README badge, CHANGELOG.
- **Honest ceilings** — guard = speed-bump (closes the shell redirect form, not interpreter bypass); tag-gate = backstop that degrades open. State both.

## Build model
**AMBER** — authored in `scratchpad/hardening/`; deliverable is `scratchpad/hardening/apply.py` + clone log.

## File map
| Path | Change | Responsibility |
|------|--------|----------------|
| `.claude/hooks/guard-core.sh` | modify | Add `conformance/` + `adapters/` to the `:82` mention regex and `:85` redirect regex. |
| `conformance/agent-autonomy.sh` | modify | New block: deny redirect + `sed -i` to `conformance/*` and `adapters/*`; allow read. |
| `scripts/release-tag.sh` | modify | Add `ci_probe()` + `ci_gate()`; call `ci_gate` in `run()` before `git tag`; 4 new `--selftest` cases. |
| `VERSION`, `README.md`, `CHANGELOG.md` | modify | Version finishing 3.67.0 → 3.68.0. |

## Tasks

### Task 1 — Guard regex (Part A)
In `guard-core.sh`, line 82 mention regex: add `|conformance/[^[:space:]]*|adapters/[^[:space:]]*` before the closing `)`. Line 85 redirect regex: add the same two alternatives before its closing `)`. (Both currently end with `skills/[^[:space:]]*)`.) Idempotent anchor: replace `skills/[^[:space:]]*)` → `skills/[^[:space:]]*|conformance/[^[:space:]]*|adapters/[^[:space:]]*)` — but that token appears on BOTH lines 82 and 85, so apply to both occurrences.

### Task 2 — Guard fixture (Part A teeth)
In `conformance/agent-autonomy.sh`, after the `skills/` block (ends ~line 347), add:
```
# --- pre-E10 hardening: conformance/ + adapters/ shell two-matcher symmetry (DENY redirect/sed, ALLOW read) ---
assert_deny  "redirect conformance" '{"tool_name":"Bash","tool_input":{"command":"echo x > conformance/verify.sh"}}'
assert_deny  "sed -i conformance"   '{"tool_name":"Bash","tool_input":{"command":"sed -i s/a/b/ conformance/verify.sh"}}'
assert_deny  "redirect adapters"    '{"tool_name":"Bash","tool_input":{"command":"echo x > adapters/registry.tsv"}}'
assert_deny  "sed -i adapters"      '{"tool_name":"Bash","tool_input":{"command":"sed -i s/a/b/ adapters/registry.tsv"}}'
assert_allow "read conformance"     '{"tool_name":"Bash","tool_input":{"command":"cat conformance/verify.sh"}}'
assert_allow "read adapters"        '{"tool_name":"Bash","tool_input":{"command":"cat adapters/registry.tsv"}}'
```
**Non-vacuity proof (clone):** run the fixture against the PRE-fix guard → the new `assert_deny`s FAIL (the redirect was allowed); against POST-fix → PASS.

### Task 3 — Tag-gate logic (Part B)
In `release-tag.sh`, add two functions before `run()`:
- `ci_probe()` — if `RELEASE_TAG_CI_PROBE` set, run it (prints `status<TAB>conclusion`); else default: `command -v gh` or return 0 (empty); `sha=$(git rev-parse HEAD)`; `gh run list --commit "$sha" --workflow CI --json status,conclusion --jq '.[0] | .status + "\t" + (.conclusion // "")' 2>/dev/null` (any failure → empty → degrade open).
- `ci_gate()` — bounded poll: loop `out=$(ci_probe)`; if empty/no-status → warn + `return 0`; if `status=completed` → `success` return 0, `failure|cancelled|timed_out|startup_failure` warn + `return 1`, other → warn + return 0; else (in-progress) if `elapsed >= RELEASE_TAG_CI_TIMEOUT` warn + return 0, else `sleep RELEASE_TAG_CI_INTERVAL`; `elapsed=$((elapsed+interval))`. Defaults: timeout 600, interval 15.
Call site in `run()`: after the `--dry-run` early-return block, before `git tag "$v"`: `ci_gate || return 1`.

### Task 4 — Tag-gate selftest (Part B teeth)
In `selftest()`, add 4 cases (probe injected, tiny timeout, no network):
- E (teeth): `RELEASE_TAG_CI_PROBE='printf "completed\tfailure\n"'` → `ci_gate` rc **1** ("CI failure -> refuse").
- F: `…'printf "completed\tsuccess\n"'` → rc **0** ("success -> proceed").
- G: `…'printf "in_progress\t\n"' RELEASE_TAG_CI_TIMEOUT=0` → rc **0** ("in-progress timeout -> degrade-open proceed").
- H: `RELEASE_TAG_CI_PROBE='true'` (empty) → rc **0** ("no CI signal -> degrade-open proceed").
Call `ci_gate` directly in a subshell with the env injected (it's defined in-script). Update the final selftest OK line.

### Task 5 — apply.py + version finishing
`scratchpad/hardening/apply.py` (idempotent, base64-embed the post-edit `guard-core.sh`, `agent-autonomy.sh`, `release-tag.sh` — OR surgical string edits; prefer base64 whole-file for the three since they're heavily structured): write the 3 edited control-plane files; VERSION 3.67.0→3.68.0; README badge; CHANGELOG prepend. Idempotent guards (write-if-differs; new-first edits).

### Task 6 — Clone dry-run
`git clone . <uniq>` → checkout `fix/pre-e10-hardening` → `python3 apply.py` → `shellcheck` the 3 scripts → `sh conformance/agent-autonomy.sh` (PASS) → `sh scripts/release-tag.sh --selftest` (PASS incl. E/F/G/H) → `sh conformance/release-tag-wired.sh` (PASS) → `sh conformance/verify.sh --require` (31/0) → re-run apply.py (idempotent). Plus the two load-bearing negatives: pre-fix guard fails the new conformance-redirect deny; a no-op `ci_gate` fails case E.

## Self-review (spec coverage)
Guard regex (both lines) → T1. Guard fixture + pre-fix negative → T2. Tag-gate functions + degrade-open matrix → T3. Tag-gate selftest E/F/G/H + the failure-teeth → T4. apply.py + version finishing → T5. Clone-proof incl. both non-vacuity negatives → T6. No new gate/claim/seat; forge-neutral; honest ceilings stated. ✔

## Terminal state / handoff
`scratchpad/hardening/apply.py` + the Task 6 clone log → dual review (reviewer + security) → panel #19 → human applies + ships (`git show --stat` + green-conformance discipline). **Next: E10.**
