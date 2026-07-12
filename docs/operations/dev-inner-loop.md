# The Developer Inner Loop — Fast Local Feedback

Rapid iteration depends on a **tight inner loop**: the smaller the gap between writing a line and learning it's wrong, the faster (and safer) you move. The kit defines **three feedback tiers**, fastest first. Stack-neutral; the per-stack tool is a profile choice.

## Three tiers (fastest → slowest)
| Tier | Fires on | Runs (seconds-fast) | Purpose | Bypassable? |
|------|----------|---------------------|---------|-------------|
| **Pre-commit** | every `git commit` | format · lint · type-check (changed files) · the **affected/fast test subset** | catch the trivial stuff *before* it's even committed | yes (`--no-verify`) — it's a convenience, not a control |
| **Pre-push** | every `git push` | the **agent guard** (`hooks/pre-push`) | safety speed-bump (force-push/push-to-main/destructive) | yes (`--no-verify`) — backed by platform branch-protection |
| **CI** | every PR | the full §14 gate set (lint · types · **full** tests+coverage · build · secret-scan · SBOM · provenance) | the authoritative gate — **not** bypassable | no |

**Keep them layered, not redundant.** Pre-commit runs *fast* checks on *changed* files only (sub-10s is the target) — if it gets slow, people disable it. The *full* suite, coverage gate, and supply-chain gates live in CI where slowness is acceptable. Pre-push is the guard, not a test runner.

## Why it matters for agentic work
An agent's inner loop is the same loop. A fast pre-commit means an agent (or human) gets format/lint/type errors back in seconds instead of waiting on a CI round-trip — **more iterations per minute, fewer broken commits, less wasted CI**. It also keeps the commit history clean (no "fix lint" follow-up commits).

## Per-stack tools → your profile
- **Hook manager:** `pre-commit` (the framework, language-agnostic) · or `husky` + `lint-staged` (JS/TS) · or native `.git/hooks` / `core.hooksPath`.
- **Fast test subset:** run only affected tests — e.g. `vitest related` / `jest --onlyChanged` (JS/TS), `pytest-testmon` (Python), `go test ./<changed-pkg>` (Go), Nx/Turborepo `affected` (monorepos).
- **Format/lint:** the stack's formatter + linter on staged files only (`ruff` / `prettier`+`eslint` / `gofmt`+`golangci-lint` / `rustfmt`+`clippy`).

## What this is — and isn't
Pre-commit is a **recommended accelerator, not a gate** (it's `--no-verify`-able by design — gating on it would just train people to bypass it). The authoritative enforcement stays in CI (§14) and the guard (pre-push). This tier exists purely to make the fast path *fast*.
