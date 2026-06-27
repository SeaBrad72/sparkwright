# Auto-tag-on-merge — release tagging without a human in the loop (design)

**Date:** 2026-06-27
**Slice:** process fix (release mechanics). Standalone; built before the next feature slice.
**Status:** Design converged (brainstorm, owner-approved 2026-06-27).
**Tracked here** (not `docs/superpowers/specs/`) because it's control-plane release mechanics and must be resumable cold.

---

## 1. Problem

The premature-tag fumble has hit **three releases in a row** (v3.49.0-class through v3.52.0): a human runs `git tag … && git push` *before* the merge has landed, so the tag pins to the old `main` (old `VERSION`) → `release-coherence` goes RED → delete + re-tag toil + a spurious "PR Failed" notice. The root cause is structural: **hand-tagging is a manual step whose correctness depends on timing the human can't see.** The cure is the same shape as folding version-finishing into `apply.py` — **remove the manual step entirely.**

## 2. Goal

After a merge to `main`, a tag `v<VERSION>` is created **on the merge commit, coherently, automatically** — so the human's ship steps shrink to `commit → push → PR → merge` and never include `git tag`. The kit (on GitHub) uses this to fix its own recurring fumble; adopters on any forge get the same guarantee.

## 3. Architecture — FLOOR + NATIVE (forge-neutral)

The *value* (coherent auto-tagging) is forge-neutral; only the *binding* (which CI event fires it, which token pushes) is forge-specific. So:

### FLOOR — `scripts/release-tag.sh` (portable, pure git)
The decision + git operations, host-agnostic:
1. Read `VERSION` (the repo root file); require semver, else N/A.
2. **Coherence precondition:** run `version-tag-coherent.sh --require` (the backstop moves *inline* — approach A). Abort the tag if it fails.
3. **Idempotency:** if `v<VERSION>` already exists (`git ls-remote --tags origin "v<VERSION>"`, falling back to local `git tag -l`), **no-op** (VERSION wasn't bumped, or already tagged).
4. Otherwise `git tag "v<VERSION>"` on `HEAD` and `git push origin "v<VERSION>"`.

Coherent **by construction**: it tags `v<VERSION>` on the commit whose `VERSION` file says that value — premature/incoherent tagging is structurally impossible because there is no hand-tag step to mis-order.

`--selftest` covers the **decision** (should-tag vs no-op, given VERSION vs existing tags, and the coherence-abort path) in throwaway repos. The actual `git push origin` is exercised **live** by the binding — the same honest ceiling the kit uses everywhere (prove the logic; the live push is the adopter's/kit's pipeline).

### NATIVE — per-forge trigger bindings
- **GitHub (shipped + used by the kit):** `.github/workflows/release-tag.yml` — `on: push` to `main`, `permissions: contents: write`, checkout with `fetch-depth: 0` + `fetch tags`, then `sh scripts/release-tag.sh`. Pushes via `GITHUB_TOKEN`. (A `GITHUB_TOKEN`-pushed tag doesn't re-trigger `release-coherence.yml` — fine, because step 2 already ran the coherence check inline.)
- **GitLab (reference, copy-and-enable):** `docs/operations/release-tag.gitlab-ci.yml` — a `release-tag` job snippet (`rules: $CI_COMMIT_BRANCH == "main"`, a project/deploy token to push, `sh scripts/release-tag.sh`). Mirrors `docs/operations/sod-gate.github.yml` — a reference file, not auto-run on the kit.
- **Generic / other forge:** one documented paragraph — "call `scripts/release-tag.sh` in your post-merge `main` pipeline with push credentials."

## 4. Conformance

`conformance/release-tag-wired.sh` (claim `release-tag-on-merge`), mirroring `author-not-approver-wired.sh`:
- runs `scripts/release-tag.sh --selftest` (the FLOOR logic),
- static-locks the GitHub binding (trigger = push/main, `permissions: contents: write`, calls `scripts/release-tag.sh`),
- actionlint-parses the GitHub workflow,
- asserts the GitLab reference binding exists.
Wired into `verify.sh` / CI / drift-watch / doctor; `scripts/release-tag.sh` added to the guard `is_control_plane_path` set (release mechanics are control-plane). Carve from the adopter export only if it reads an export-ignored path (it doesn't — no carve expected).

## 5. Composition with the existing gate

`release-coherence.yml` (on `v*` tag push → `version-tag-coherent.sh --require`) **stays unchanged** as the backstop for any manual/edge-case tag. Auto-tags satisfy it by construction (and validate it inline before tagging). Manual `git tag` still *works* (the workflow no-ops if the tag exists) — it's just no longer *necessary*.

## 6. Honest ceiling / out of scope (YAGNI)

- GitHub Releases, changelog extraction, release notes — **not** built. Just the tag.
- The FLOOR proves the **decision** logic; the **push** is live (no remote in `--selftest`).
- Forge auth (the push token) is the NATIVE binding's concern + documented; the script assumes an authenticated remote.
- This does not choose or validate the version *value* — that's `apply.py`'s version-finishing (already folded). This only tags whatever `VERSION` declares, when it's new.

## 7. Build

Control-plane → AMBER `scratchpad/auto-tag/apply.py` (agent prepares + dry-runs on a clone; **Bradley applies + commits + merges** per [[merge-tag-authority]]). Version finishing folded into apply.py. Dual review (reviewer + security-reviewer — the security lens matters: a workflow with `contents: write` that pushes tags). **This is the last release Bradley hand-tags** — once it lands, tagging is automatic.

## 8. Convergence record (owner-approved 2026-06-27)

FLOOR+NATIVE forge-neutral shape (Bradley's neutrality catch) · approach A (coherence backstop inline in the FLOOR script, `GITHUB_TOKEN`, no PAT) · GitHub binding live + GitLab reference + generic doc · conformance mirrors author-not-approver-wired · existing release-coherence gate unchanged · YAGNI on releases/notes. **Next: writing-plans.**
