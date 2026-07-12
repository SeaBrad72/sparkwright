# Harness Enforcement Evidence

**The maintainer-verified half of the harness-neutrality claim.**

The kit asserts that the destructive-action deny-matrix enforces equally for any harness — Claude Code, Codex, Cursor, Aider, or a CI bot — because the enforcement surfaces are **caller-agnostic**. This doc names the proof: three deterministic selftests, all run in CI on every push, each exercising a distinct surface through its public interface.

> **What this proves vs. doesn't — read first.** The three selftests prove the surfaces deny regardless of caller (agent or human, Claude or not). They do NOT prove a specific third-party agent was driven through them end-to-end. That is the **live cross-harness demo** — the recommended **first real-world validation** when you adopt the kit with a second harness: drop it into a repo, run `incept --harness <name>`, drive the agent, and watch the floor block a bad command. The surfaces already block; the live run is confirmatory. See `runtime-guards.md` for the coverage ceiling per surface, and `docs/enterprise/platform-safety-boundary.md` for what the platform must own.

---

## Thesis

The floor blocks for any harness because every surface operates on **the invoking shell call** — not on which runtime issued it. A command piped through `kit-guard`, a push from any git client, and a PR diff in any CI system all hit the same deny-matrix (`guard-core.sh`) through the same interface. No runtime-specific wiring is required for the floor to hold.

This is the maintainer-verified half of the split bar:
- **Maintainer-verified (this doc):** the three surfaces deny, deterministically, for any caller — proven by CI-locked selftests. The named `codex`, `cursor`, and `gemini` adapters' **floor-conformance** is additionally maintainer-verified via `conformance/named-adapters.sh` (claims registry → 15): each adapter declares its own control surface (`.cursor/rules/`, `GEMINI.md`/`.gemini/`) so the `agent-boundary` gate protects the union across all harnesses in a shared repo.
- **Adopter-verified (live demo):** a specific third-party harness was driven through the surfaces end-to-end and the floor blocked as expected — proven by running the harness in a real repo. **This half stays adopter-owned — it is not a future maintainer-verified target.** No third-party harness has a native inline guard, so the kit cannot maintainer-claim a live cross-harness session; the live "this harness blocked a bad command" demo is the adopter's confirmatory run, folded into the pre-release living-reference-project validation.

---

## The proof — three CI-locked selftests

All three are wired in `.github/workflows/ci.yml` and run on every push. Each exits `0` on pass, non-zero on any failure.

### 1. `sh scripts/kit-guard --selftest` — the CLI surface

The entry point any non-Claude runtime pipes proposed commands through. The selftest drives the full deny battery through the CLI:

| Category | Cases exercised |
|----------|----------------|
| Command deny | `rm -rf` (recursive rm), `git push --force`, `git push origin main`, `dropdb`, `kubectl delete deployment`, `curl … \| sh`, `sed -i` on a control-plane path |
| Command allow | `git commit`, `git push origin feature/foo`, `npm test` |
| Path deny | writes to `.env`, writes to `.claude/hooks/guard-core.sh` |
| Path allow | writes to `src/app.ts`, writes to `.env.example` |
| MCP deny | `mcp__filesystem__delete_file` (destructive verb) |
| MCP allow | `mcp__postgres__query` (read-only verb) |

All denies must block; all allows must pass. Any single failure makes the selftest exit non-zero and fail CI.

### 2. `sh hooks/pre-push --selftest` — the git-history surface

The universal git pre-push hook — installed by `incept.sh` for every git client and humans. The selftest builds a hermetic two-commit repo (no ambient history dependency; works in shallow CI clones) and drives five ref-pair cases:

| Case | Expected |
|------|----------|
| Push to `refs/heads/main` (new branch) | deny |
| Delete `refs/heads/main` | deny |
| New feature branch | allow |
| Fast-forward push to a feature branch | allow |
| Force (non-fast-forward) push to a feature branch | deny |

### 3. `sh conformance/agent-boundary.sh --selftest` — the CI-gate surface

The harness-independent control-plane ratification gate. A PR diff that touches a control-plane path (`.github/workflows/`, `CODEOWNERS`, `conformance/`, `.claude/hooks/`, the named `scripts/`, `adapters/`, and the governing docs `DEVELOPMENT-STANDARDS.md` / `DEVELOPMENT-PROCESS.md` / `CLAUDE.md` — see `guard-core.sh::is_control_plane_path`) must carry a **non-author approval** or the gate fails — regardless of which harness opened the PR. (The self-appliable `ratified-control-plane` label was **removed in H1.3** as agent-forgeable; solo maintainers ratify via a logged `enforce_admins: false` admin-merge.) The selftest exercises both the `boundary_decide` logic in-process and the CLI end-to-end:

| Case | Expected |
|------|----------|
| Ordinary diff (no control-plane paths), unratified | pass |
| Workflow change (`.github/workflows/ci.yml`), unratified | fail (exit 1) |
| Workflow change, ratified | pass |
| `CODEOWNERS` change, unratified | fail (exit 1) |
| `conformance/` script change, unratified (H1.1) | fail (exit 1) |
| `DEVELOPMENT-STANDARDS.md` / `CLAUDE.md` change, unratified (H1.1) | fail (exit 1) |
| `adapters/*/adapter.json` change, unratified (H1.1) | fail (exit 1) |
| Adopter's own `scripts/deploy.sh` (not kit machinery) | pass |
| Empty diff | pass |
| No `--changed` listing supplied, local (non-CI) | exit 2 (UNVERIFIED — not a pass) |
| No `--changed` listing, `CI=true` | exit 1 (escalated — gate must be runnable) |
| CLI: control-plane listing, unratified | exit 1 |
| CLI: control-plane listing, ratified | exit 0 |
| CLI: clean listing, unratified | exit 0 |

**Dogfooded (H1.4 + D4):** the kit's own `.github/workflows/ci.yml` runs the real `gate-agent-boundary` job on every PR. **D4** presents the result as a **merge-gate**: the job exits 0 and posts a distinct `control-plane-ratification` check-run — `action_required` (unratified) / `success` (ratified) / `failure` (only a genuine gate error) — required in branch protection, so an unratified control-plane change is blocked pre-merge **without a red ❌ or a "run failed" email.**

**Live evidence (PR #114, 2026-06-18 — the D4 experiment, verified directly on GitHub):** an unratified control-plane PR produced `control-plane-ratification` = **`ACTION_REQUIRED`** (amber, *not* a red ❌); the workflow run completed **`success`** (so **no "run failed" email**); and with the check **required** in branch protection, the PR's merge state was **`BLOCKED`** until ratified. You clear it with a non-author approval (the check flips to `success`/green) or, solo, a logged `enforce_admins:false` admin-merge — so red ❌ / failure emails are reserved for *genuine* failures. (We also found the prior `gate-agent-boundary` was never a *required* check — it rendered red + emailed but didn't actually block; D4 replaced noise-without-enforcement with enforcement-without-noise.) Adopters: add `control-plane-ratification` to your `main` required status checks.

---

## Reproduce locally

Run any or all three:

```sh
sh scripts/kit-guard --selftest
sh hooks/pre-push --selftest
sh conformance/agent-boundary.sh --selftest
```

Each prints its case results and exits `0` on full pass, `1` on any failure. To run all three and confirm the chain:

```sh
sh scripts/kit-guard --selftest >/dev/null 2>&1 \
  && sh hooks/pre-push --selftest >/dev/null 2>&1 \
  && sh conformance/agent-boundary.sh --selftest >/dev/null 2>&1 \
  && echo "3 surface selftests: PASS"
```

---

## Honest ceiling

This evidence proves the surfaces deny regardless of caller. It does not prove:

- A **specific third-party agent** (Codex, Cursor, Aider, etc.) was driven through the surfaces in a real session. That is the live cross-harness demo — the recommended first real-world validation when adopting with a second harness. The surfaces already block; the live run is confirmatory.
- That the surfaces **cannot be bypassed.** `--no-verify`, a runtime that never calls `kit-guard`, or a language interpreter (`python -c`) bypasses the CLI and hook surfaces. Each surface is a speed bump for honest mistakes, not containment of a hostile process.
- That the **platform controls are in place.** The real boundary — network-egress allowlist, separate production credentials, sandboxed filesystem, scoped tokens — is platform-owned and platform-enforced. See `docs/enterprise/platform-safety-boundary.md`.

The selftests are deterministic because they run the surfaces through their public interfaces against a fixed adversarial corpus. They cannot falsely pass: any regression in the deny-matrix propagates immediately to a CI failure on the next push.

---

## See also

- `docs/operations/runtime-guards.md` — the full coverage ceiling for each surface; how to wire a non-Claude runtime; MCP capability gate details.
- `docs/enterprise/platform-safety-boundary.md` — the real boundary (platform-owned); what the kit speed bump is not.
- `conformance/agent-autonomy.sh` — the red-team adversarial corpus.
- `DEVELOPMENT-PROCESS.md` §13 — the autonomy matrix and the rationale for the split bar.
