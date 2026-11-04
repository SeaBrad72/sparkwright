# Harness Enforcement Evidence

**The maintainer-verified half of the harness-neutrality claim.**

The kit asserts that the destructive-action deny-matrix enforces equally for any harness — Claude Code, Codex, Cursor, Aider, or a CI bot — because the enforcement surfaces are **caller-agnostic**. This doc names the proof: three deterministic selftests, all run in CI on every push, each exercising a distinct surface through its public interface.

> **What this proves vs. doesn't — read first.** The three selftests prove the surfaces deny regardless of caller (agent or human, Claude or not). They do NOT prove a specific third-party agent was driven through them end-to-end. That is the **live cross-harness demo** — the recommended **first real-world validation** when you adopt the kit with a second harness: drop it into a repo, run `incept --harness <name>`, drive the agent, and watch the floor block a bad command. The surfaces already block; the live run is confirmatory. See `runtime-guards.md` for the coverage ceiling per surface, and `docs/enterprise/platform-safety-boundary.md` for what the platform must own.

---

## Thesis

The floor blocks for any harness because every surface operates on **the invoking shell call** — not on which runtime issued it. A command piped through `kit-guard`, a push from any git client, and a PR diff in any CI system all hit the same deny-matrix (`guard-core.sh`) through the same interface. No runtime-specific wiring is required for the floor to hold.

This is the maintainer-verified half of the split bar:
- **Maintainer-verified (this doc):** the three surfaces deny, deterministically, for any caller — proven by CI-locked selftests in the kit's own CI. The named `codex`, `cursor`, and `gemini` adapters' **floor-conformance** is additionally maintainer-verified via `conformance/named-adapters.sh`: each adapter declares its own control surface (`.cursor/rules/`, `GEMINI.md`/`.gemini/`) so the `agent-boundary` gate protects the union across all harnesses in a shared repo.
- **Adopter-verified (live demo):** a specific third-party harness was driven through the surfaces end-to-end and the floor blocked as expected — proven by running the harness in a real repo. **This half stays adopter-owned — it is not a future maintainer-verified target.** No third-party harness has a native inline guard, so the kit cannot maintainer-claim a live cross-harness session; the live "this harness blocked a bad command" demo is the adopter's confirmatory run, folded into the pre-release living-reference-project validation.

> **`codex` is the one named adapter whose floor is *exercised* end-to-end, not merely declared.** In an operator-run cold field test on kit 3.173.0, with no Claude assistance, Codex drove the surfaces live: the emitted `pre-push` guard refused a genuine six-commit `git push origin HEAD:main` (exit 1, `origin/main` unchanged), the caller-agnostic `control-plane-ratification` gate held a real control-plane PR blocked while GitHub rejected author self-approval, and the emitted required `ci` path was green on first run yet reddened and blocked a disposable negative PR. All five acceptance criteria passed non-vacuously; the criterion-by-criterion record is kept in the maintainers' internal design docs, which do not ship. This promoted `codex` from `experimental` to **floor-verified** in the maturity surface. It remains floor-verified, not first-class: Codex has no inline `PreToolUse`-equivalent interception, and the first acceptance criterion is the test that it discloses so.

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

The universal git pre-push hook — installed by `incept.sh` for every git client and humans. The selftest builds a hermetic two-commit repo (no ambient history dependency; works in shallow CI clones) and drives six ref-pair cases (plus the same pair for `master`):

| Case | Expected |
|------|----------|
| Push that creates `refs/heads/main` on an empty remote, the first push (cell "create main on an empty remote") | allow |
| Push to `refs/heads/main` that updates an existing main (cell "update an existing main") | deny |
| Delete `refs/heads/main` | deny |
| New feature branch | allow |
| Fast-forward push to a feature branch | allow |
| Force (non-fast-forward) push to a feature branch | deny |

### 3. `sh conformance/agent-boundary.sh --selftest` — the CI-gate surface

The harness-independent control-plane ratification gate. A PR diff that touches a control-plane path (`.github/workflows/`, `CODEOWNERS`, `conformance/`, `.claude/hooks/`, the named `scripts/`, `adapters/`, and the governing docs `DEVELOPMENT-STANDARDS.md` / `DEVELOPMENT-PROCESS.md` / `CLAUDE.md` — see `guard-core.sh::is_control_plane_path`) must carry a **non-author approval** or the gate **waits** (blocking, and rendered red; see below) — regardless of which harness opened the PR. (There is no self-appliable `ratified-control-plane` label, because an agent could forge it; solo maintainers ratify via a logged `enforce_admins: false` admin-merge.) The selftest exercises both the `boundary_decide` logic in-process and the CLI end-to-end:

| Case | Expected |
|------|----------|
| Ordinary diff (no control-plane paths), unratified | pass |
| Workflow change (`.github/workflows/ci.yml`), unratified | fail (exit 1) |
| Workflow change, ratified | pass |
| `CODEOWNERS` change, unratified | fail (exit 1) |
| `conformance/` script change, unratified | fail (exit 1) |
| `DEVELOPMENT-STANDARDS.md` / `CLAUDE.md` change, unratified | fail (exit 1) |
| `adapters/*/adapter.json` change, unratified | fail (exit 1) |
| Adopter's own `scripts/deploy.sh` (not kit machinery) | pass |
| Empty diff | pass |
| No `--changed` listing supplied, local (non-CI) | exit 2 (UNVERIFIED — not a pass) |
| No `--changed` listing, `CI=true` | exit 1 (escalated — gate must be runnable) |
| CLI: control-plane listing, unratified | exit 1 |
| CLI: control-plane listing, ratified | exit 0 |
| CLI: clean listing, unratified | exit 0 |

**Dogfooded:** the kit's own `.github/workflows/ratification.yml` runs the real `control-plane-ratification` job on every PR **and on every review** (an approval re-evaluates the gate, and only the gate — which is why it has its own workflow file). The **job key is the required status context**, and the **job's own conclusion is the verdict**: green when ratified or when there is nothing to ratify, red when unratified (WAITING) and red when the gate could not evaluate. Required in branch protection, so an unratified control-plane change is blocked pre-merge.

**Why a waiting gate reads as a red check.** The job's own conclusion is the verdict, and a job cannot be yellow, so **a waiting gate reads as a red check and does send a failure email**. The compensation is prose, not colour: the check's title says "Awaiting ratification — a human must approve…" and its summary says no test failed and names the remedy. A merge gate that can be satisfied reliably is worth more than one that renders kindly. Two things were tried and do not hold:
- A check-run posted through the API and left at `status: in_progress` blocks the merge, but branch protection can stop matching such posted runs to the required context name. PRs then sit at "Expected — waiting for status to be reported" with every gate green, cleared only by an admin merge. That is why the verdict lives on the job's conclusion, where there is nothing to match.
- `action_required` is **not** amber: GitHub renders it with the **same red ✗ as a failure**, and headlines the PR "Some checks were not successful". Asserting a rendering from the API value rather than the rendered pixels certified the opposite of what reviewers saw.

**A green check attests that the test ran, never that the claim is true.** Honest ceiling: the kit controls the status it posts, not how the forge renders or matches it. A required check that is not `success` leaves the PR `BLOCKED` (measured once on GitHub, 2026-07-13, a point-in-time reading), and it becomes mergeable when the gate passes. Adopters: add `control-plane-ratification` to your `main` required status checks; the job key already carries that exact name.

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

## The harness `cwd` contract — what was measured, and what was NOT

The guard reads a **top-level `cwd`** field from
PreToolUse stdin (a sibling of `tool_name`, not a member of `tool_input` — which is precisely why it
is trustworthy: the model authors `tool_input`, the harness authors `cwd`). Two things follow, and
they are recorded separately because only one of them is measured.

**MEASURED, in a sub-agent thread, 2026-09-02.** Two consecutive Bash tool calls:

```
call 1:  cd /private/tmp/kit-s38c/conformance && pwd   ->  /private/tmp/kit-s38c/conformance
call 2:  pwd                                           ->  <repo-root>
```

In a **sub-agent thread the cwd is reset between calls**. The cross-call hole the `cwd` read closes is
therefore a **main-agent** property, and a sub-agent seat cannot exhibit it. That matches the
guard's design assumption that sub-agent threads reset cwd per call, and is stated here as a
measurement rather than inherited as an assumption.

**NOT MEASURED, and named rather than assumed.** Whether the harness's `cwd` field *tracks the main
agent's persisted Bash cwd* — as opposed to reporting the session root on every call — was **not**
established. Doing so requires capturing PreToolUse stdin from the **live** hook, which is a
control-plane edit to the running repository and outside the scope any build seat may take. Until
that capture is made by an operator, the honest statement is:

- If the field tracks the persisted cwd, the `cwd` read closes the cross-call route.
- If it always reports the session root, the `cwd` read is **inert** on that route and costs nothing — the
  absent/root case is plain behaviour byte for byte — while the in-string `cd`
  spellings are unaffected either way and are what the fixture battery proves.

**The measurement an operator should make**, once, and record here: install a stdin-tee alongside the
PreToolUse hook, issue `cd conformance` in one call and `pwd` in the next, and read the `cwd` value
on the *second* call's captured stdin.

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
