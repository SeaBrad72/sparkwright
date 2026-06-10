# Brownfield Adoption — Bringing the Kit into an Existing Repo

Greenfield adoption (starting a new repo *from* the kit) is covered by `../../START-HERE.md`. This guide is for **brownfield**: layering the kit onto an existing repo that already has code, history, and possibly its own `.claude/`.

## ⚠️ Read this first — the risk

The kit's runtime safety is the **`.claude/` PreToolUse guard** (`.claude/hooks/guard.sh`, registered in `.claude/settings.json`). It blocks destructive/irreversible agent actions (`../../DEVELOPMENT-PROCESS.md` §13).

Brownfield **inverts the kit's risk gradient.** A greenfield repo starts empty and safe; a legacy repo already has `.env` files, cloud credentials, and kube contexts wired up. If you adopt the kit's *process* but skip the `.claude/` **merge** — so the guard isn't actually registered — you get **agents operating on a live system with real production reach and no runtime protection**, while believing you have the kit's safety. That is worse than not adopting the kit.

**Before any agent runs in this repo, verify the guard is live:**

```sh
sh conformance/guard-wired.sh
```

It must print `guard-wired: OK`. If it FAILs, the guard is not wired — fix the merge below first. (The Inception gate, `conformance/inception-done.sh`, also enforces this.)

## When to use this guide

- **Greenfield** (new/empty repo): start from the kit, run `sh scripts/incept.sh`. Use `../../START-HERE.md`.
- **Brownfield** (existing repo with code): follow this guide. You **copy the kit in** and **merge** `.claude/` rather than starting from the kit.

## 1. Copy the kit in

Bring these into your repo root (adapt, don't blindly overwrite):

- Governing docs: `ENGINEERING-PRINCIPLES.md` (the kit's principles `CLAUDE.md`, renamed), `DEVELOPMENT-PROCESS.md`, `DEVELOPMENT-STANDARDS.md`, `MAINTAINING.md`.
- `profiles/`, `conformance/`, `templates/`, `docs/`, `scripts/`.
- `.github/workflows/ci.yml` (from your chosen `profiles/<stack>/ci.yml`) — **merge** with any existing CI; don't drop your pipeline.
- `.claude/` — **merge, never overwrite** (next section).

If your repo has its own root `CLAUDE.md`, keep it as your *project* `CLAUDE.md` and bring the kit's principles in as `ENGINEERING-PRINCIPLES.md` (the name the kit uses post-Inception).

## 2. The `.claude/` MERGE policy (do-no-harm core)

If your repo already has a `.claude/`, **do not overwrite it.** Keep your hooks and settings; **add** the kit's guard:

1. Copy `.claude/hooks/guard.sh` into your `.claude/hooks/` (keep your existing hooks), then `chmod +x .claude/hooks/guard.sh`.
2. In your `.claude/settings.json`, **add** the kit's PreToolUse guard hook. **JSON has no duplicate keys** — how you add it depends on what's already there:

   **If your `settings.json` has no `hooks` key:** add the whole block.

   ```json
   "hooks": {
     "PreToolUse": [
       {
         "matcher": "Bash|Write|Edit|NotebookEdit",
         "hooks": [
           { "type": "command", "command": "sh \"$CLAUDE_PROJECT_DIR/.claude/hooks/guard.sh\"" }
         ]
       }
     ]
   }
   ```

   **If `hooks.PreToolUse` already exists:** do **not** paste a second `hooks` block (that makes invalid duplicate-key JSON and your guard or your existing hooks may silently vanish). Add only this **array element** as a new entry inside your existing `PreToolUse` list (it is a fragment, not a whole file — don't paste the surrounding `//` line):

   ```jsonc
   // ↓ add this object as an element of your existing "PreToolUse": [ ... ] array
   {
     "matcher": "Bash|Write|Edit|NotebookEdit",
     "hooks": [
       { "type": "command", "command": "sh \"$CLAUDE_PROJECT_DIR/.claude/hooks/guard.sh\"" }
     ]
   }
   ```

   After editing, confirm the file is valid JSON (e.g. `python3 -m json.tool .claude/settings.json >/dev/null && echo valid`).

3. Leave `.claude/settings.local.json` alone — it is **gitignored** (personal, per-developer). Do not copy the kit's over yours.
4. **Gate — do not start a Claude Code session in this repo until this prints `guard-wired: OK`:**

   ```sh
   sh conformance/guard-wired.sh
   ```

> The kit does **not** script this merge: a merge bug could clobber exactly the hooks we're protecting. The merge is human-performed; `guard-wired.sh` verifies the result.

## 3. Inception (adapted)

`scripts/incept.sh` is the **greenfield** bootstrap — it renames the kit's root `CLAUDE.md` to `ENGINEERING-PRINCIPLES.md` and stamps fresh project artifacts, which assumes you started *from* the kit. In a brownfield repo you do the Inception **judgment** steps by hand (`../../START-HERE.md` steps 1–7): write the charter, record the stack as **ADR-000**, instantiate the project `CLAUDE.md` from `../../templates/PROJECT-CLAUDE-TEMPLATE.md`, start `RUNBOOK.md`, pick a backlog backend (`work-tracking/adapters.md`), assign roles.

Then run the gate:

```sh
sh conformance/inception-done.sh
```

It now checks that the **runtime guard is wired** (not just that `.claude/` exists), so you cannot pass Inception with a dead guard.

## 4. Residual gaps (be honest about these)

The guard is necessary, not sufficient:

- **Pattern coverage.** `guard.sh` matches *common* destructive verbs. Your legacy repo may have **bespoke destructive tooling** (`make nuke-db`, a homegrown deploy/migration script) the patterns don't recognize. Extend `.claude/hooks/guard.sh` with your repo's destructive commands. Then **add a deny case for each new pattern to `conformance/agent-autonomy.sh`** and re-run it: that suite is a **regression guard, not a coverage oracle** — running it as-is only confirms the *existing* cases still pass; it does not validate your new patterns unless you add cases for them.
- **Runtime scope.** The guard covers only the **Claude Code runtime**. Humans at a shell and other agent runtimes are **not** covered — and a legacy system is more likely to have other automation/people holding prod access. The **platform backstop is Org-owned** and matters *more* here because the blast radius pre-exists: production IAM, separate prod accounts/credentials, and deploy approvals (`../enterprise/README.md` — the human-coverage boundary). The kit's guard reduces agent risk; it does not replace platform controls.

## 5. Adopting when you already fail the gates

A real legacy repo arrives **below 80% coverage, with vulnerable deps, no SBOM, and an unprotected `main`**. The DoD's seven gates are blocking on every PR (`../../DEVELOPMENT-STANDARDS.md` §14), so your *first* PR after adoption can't merge. The wrong fix is to disable a gate — that fakes green and discards the kit's whole point. The right fix is a **governed exception**: a tracked, time-boxed, owned, ratified waiver with a remediation plan. *Don't hide the gap — declare it, own it, and put it on a clock.*

### Day-one non-negotiables vs. deferrable gates

| Tier | Gates | Posture |
|------|-------|---------|
| **Non-negotiable (never waivable)** | `secret-scan`, `branch-protection` | Must pass on day one. A repo never ships secrets, and segregation-of-duties is not optional. If secret-scan can't run, that is a blocker to fix, not a waiver. |
| **Day-one quick wins** | lint · type-check · build | Usually green or near-green; fix these first (hours, not sprints). |
| **Deferrable (time-boxed waiver)** | coverage · SBOM · provenance · dependency-vuln · a11y · container-image | Open a waiver with an owner, expiry (≤ 90 days), and remediation plan; tighten on a schedule. |

### The ramp

1. **Wire the non-negotiables first.** Protect `main` (`conformance/branch-protection.sh` must pass) and make secret-scan green. These have no waiver path.
2. **Record a coverage baseline and ratchet up.** Don't gate on absolute 80% on day one — gate on *no regression below your current floor*:
   ```sh
   sh scripts/coverage-ratchet.sh <your-current-coverage-%>   # seeds .coverage-baseline on first run
   ```
   Commit `.coverage-baseline`. Each sprint, raise it as you add tests; the absolute-80% DoD is the target your coverage waiver's remediation plan drives toward.
3. **Open waivers for the rest.** Copy `templates/WAIVER-REGISTER.md` to your repo root as `WAIVER-REGISTER.md`. Add one ratified row per gap (gate · reason · owner · opened · expires ≤ 90d · remediation plan · ratified-by). Validate it:
   ```sh
   sh conformance/waivers-valid.sh        # FAILs on expired / non-negotiable / over-90d / missing-field
   ```
4. **Tighten on a schedule, close waivers as you go.** A suggested cadence:

   | When | Close out |
   |------|-----------|
   | Day one | secret-scan + branch-protection green (non-negotiable) |
   | Week one | lint · type-check · build green |
   | Each sprint | coverage ratchet +N points toward 80% |
   | Within 90 days | SBOM + provenance wired; high/critical deps patched or pinned; a11y audited |

5. **The register is the honest dashboard.** An expired waiver fails `waivers-valid.sh` — it forces a renew-or-fix decision instead of letting the gap rot silently. When every gap is closed, delete `WAIVER-REGISTER.md`; the check goes back to N/A and the full gate set is blocking unwaived.

> **What the check does and doesn't prove.** `waivers-valid.sh` attests **register hygiene** — every active waiver is on a waivable gate (default-deny: `secret-scan`/`branch-protection` and any unknown name are rejected), owned, in-date, within 90 days, and complete. It validates the `Ratified-by` field is *filled*, not *who* filled it — true security-owner ratification is enforced where it actually lives: a **branch-protected review of the register change** (`../enterprise/ratification-rbac.md`), not by this script. And a green register does **not** prove the waived gate is still running in CI — keep the gate wired and observed; the waiver records that you accept its current failure, not that you removed it. This operationalizes the governed-exception process for adoption; it does not replace the human ratification it records.
