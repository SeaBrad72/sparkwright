# Brownfield Adoption — Bringing the Kit into an Existing Repo

Greenfield adoption (starting a new repo *from* the kit) is covered by `../../START-HERE.md`. This guide is for **brownfield**: layering the kit onto an existing repo that already has code, history, and possibly its own `.claude/`.

## ⚠️ Read this first — the risk

The kit's runtime safety is the **`.claude/` PreToolUse guard** (`.claude/hooks/guard.sh`, registered in `.claude/settings.json`). It blocks destructive/irreversible agent actions (`../../DEVELOPMENT-PROCESS.md` §13).

Brownfield **inverts the kit's risk gradient.** A greenfield repo starts empty and safe; a legacy repo already has `.env` files, cloud credentials, and kube contexts wired up. If you adopt the kit's *process* but skip the `.claude/` **merge** — so the guard isn't actually registered — you get **agents operating on a live system with real production reach and no runtime protection**, while believing you have the kit's safety. That is worse than not adopting the kit.

**Before any agent runs in this repo, verify the guard is live:**

```sh
sh conformance/guard-wired.sh
```

It must print `guard-wired: OK`. If it FAILs, look at the wording: `guard-wired: FAIL — the runtime guard is NOT active; agents would run unprotected` means the merge below is genuinely broken — fix it. `guard-wired: FAIL — a guard rung is not wired` means only the SECOND rung (the installed `.git/hooks/pre-push` git hook, §2 step 5 below) is missing or stale — **expected at this point, before you've done §5**, not evidence the merge itself failed. (The Inception gate, `conformance/inception-done.sh`, also enforces this.)

## When to use this guide

- **Greenfield** (new/empty repo): start from the kit, run `sh scripts/incept.sh`. Use `../../START-HERE.md`.
- **Brownfield** (existing repo with code): follow this guide. You **copy the kit in** and **merge** `.claude/` rather than starting from the kit.

## 1. Copy the kit in

**Copy the entire `adopter-export.sh` output tree into your repo root, then rename the shipped `CLAUDE.md` → `ENGINEERING-PRINCIPLES.md`.** That one instruction is the durable form. The export tree is exactly what a greenfield adopter starts *from*; copying it whole cannot fall behind as the kit grows new top-level trees. An enumerated "copy these directories" list is what silently drifted out of date and dead-ended real adopters partway through Inception (missing `adapters/`, `hooks/`, `agents/`, `.kit/`, `AGENTS.md`, and the `.claude/` guard-core), so this guide names no such manifest to maintain.

Obtain the tree with `sh scripts/adopter-export.sh <dest>` (it honors `export-ignore`, so it already excludes maintainer-only scratch), then copy `<dest>/.` into your repo root — **adapt, don't blindly overwrite** your own files. What the tree contains, for orientation only (**examples, not an exhaustive manifest**): the governing docs (`DEVELOPMENT-PROCESS.md`, `DEVELOPMENT-STANDARDS.md`, `MAINTAINING.md`, and the principles doc shipped as `CLAUDE.md`); `profiles/`, `conformance/`, `templates/`, `docs/`, `scripts/`; the runtime + orchestration trees `adapters/`, `agents/`, `hooks/`, `.kit/`, `AGENTS.md`; and `.claude/` (guard + settings + role files).

- **Rename the principles doc.** The export ships it as `CLAUDE.md`; **copy it in and rename it to `ENGINEERING-PRINCIPLES.md` yourself** (the rename only happens automatically in greenfield `incept`, which you don't run here) so it doesn't collide with your project's own root `CLAUDE.md`.
- **`.claude/` is a MERGE, never a blind overwrite** if your repo already has one — see the next section. (A repo with no `.claude/` simply receives the tree's copy, guard-core and all.)
- **CI pipeline.** The export intentionally does **not** carry a `ci.yml` (it is maintainer-only, `export-ignore`d), so add `.github/workflows/ci.yml` from your chosen `profiles/<stack>/ci.yml` and **merge** it with any existing CI; don't drop your pipeline. *(If you run `incept` in a populated repo, it now **preserves** an existing `ci.yml`/CODEOWNERS — it warns and skips rather than overwriting — but you must still merge the profile's gate-ids into your pipeline by hand.)*

  **Merge the conformance aggregate step into your preserved pipeline.** Because `incept` never wrote its own pipeline over yours, your CI carries no origin marker, so `conformance/verify-enforced-wired.sh` classifies it **ADOPTER-OWNED** and returns **N/A-with-remedy** (a disclosed, unmet merge obligation — never a false failure). To actually enforce the battery, paste the profile's aggregate step — the exact YAML the N/A verdict prints — as the **first** blocking step of your CI job (it is POSIX `sh`, no toolchain, so it fails fast; `[doc]` failures exit 0 by design). On **GitHub Actions**:

  ```yaml
        - name: Conformance aggregate (required — DEVELOPMENT-STANDARDS.md §14)
          run: sh conformance/verify.sh --require
  ```

  On **GitLab CI**, add it as an early job (`profiles/<stack>/ci.gitlab-ci.yml` is the reference):

  ```yaml
        conformance-aggregate:
          stage: verify
          needs: []
          script: [sh conformance/verify.sh --require]
  ```

If your repo has its own root `CLAUDE.md`, keep it as your *project* `CLAUDE.md` and bring the kit's principles in as `ENGINEERING-PRINCIPLES.md` (the name the kit uses post-Inception).

## 2. The `.claude/` MERGE policy (do-no-harm core)

If your repo already has a `.claude/`, **do not overwrite it.** Keep your hooks and settings; **add** the kit's guard:

1. Copy **both** `.claude/hooks/guard.sh` **and** `.claude/hooks/guard-core.sh` into your `.claude/hooks/` (keep your existing hooks), then `chmod +x .claude/hooks/guard.sh .claude/hooks/guard-core.sh`. **Both are required:** the runtime guard and the pre-push hook (§3) both *source* `guard-core.sh`, and the hook is **fail-closed** — an installed hook whose core is missing **refuses every push** rather than fail open (the A5 property). Copying `guard.sh` alone leaves the core dependency unmet. *(A whole-tree §1 copy into a repo with no prior `.claude/` already brought both; this step is the merge path for a repo that already has its own `.claude/` you must not overwrite.)*
2. In your `.claude/settings.json`, **add** the kit's PreToolUse guard hook. **JSON has no duplicate keys** — how you add it depends on what's already there:

   **If your `settings.json` has no `hooks` key:** add the whole block.

   ```json
   "hooks": {
     "PreToolUse": [
       {
         "matcher": "Bash|Write|Edit|NotebookEdit|mcp__.*",
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
     "matcher": "Bash|Write|Edit|NotebookEdit|mcp__.*",
     "hooks": [
       { "type": "command", "command": "sh \"$CLAUDE_PROJECT_DIR/.claude/hooks/guard.sh\"" }
     ]
   }
   ```

   After editing, confirm the file is valid JSON (e.g. `python3 -m json.tool .claude/settings.json >/dev/null && echo valid`).

3. Leave `.claude/settings.local.json` alone — it is **gitignored** (personal, per-developer). Do not copy the kit's over yours. **Add `.claude/settings.local.json` to your repo's `.gitignore`** if it isn't already — the kit's own `.gitignore` has the line, but your existing repo's won't, and the personal overrides must never be committed.
4. **Gate — do not start a Claude Code session in this repo until this prints `guard-wired: OK`:**

   ```sh
   sh conformance/guard-wired.sh
   ```

   **Expected at this point in the walk:** if you have not yet done step 5 below, this will RED on
   the SECOND rung (`guard-wired: FAIL — a guard rung is not wired`) even when the `PreToolUse`
   merge you just did is correct — the installed `.git/hooks/pre-push` git hook doesn't exist yet.
   That is not the merge failing; it is step 5's own gate. If instead you see `guard-wired: FAIL —
   the runtime guard is NOT active`, the `.claude/` merge itself needs fixing before you continue.

> The kit does **not** script this merge: a merge bug could clobber exactly the hooks we're protecting. The merge is human-performed; `guard-wired.sh` verifies the result.

5. **Install the pre-push git hook — a HUMAN step.** `guard-wired.sh` now certifies **both** rungs — the `PreToolUse` `guard.sh` rung **and** the installed `.git/hooks/pre-push` git hook (present, executable, core-resolvable, and FRESH — byte-identical to `hooks/pre-push` as committed at HEAD; a foreign/chained hook without the kit marker is preserved unjudged); a stale or absent kit hook turns `guard-wired: OK` RED (closed: `GUARD-WIRED-BLIND-TO-GIT-HOOK-RUNG`, `STALE-INSTALLED-HOOK`; see `docs/architecture/2026-08-05-b3-rung-certifier-design.md`). The rung leg only runs on an incepted/kit-source tree, outside CI — on a fresh export or a CI runner it N/As, disclosed, never silently. Git hooks are **not** version-controlled, so the whole-tree §1 copy brought `hooks/pre-push` (the source) but **not** `.git/hooks/pre-push`. Install it yourself:

   ```sh
   cp hooks/pre-push .git/hooks/pre-push && chmod +x .git/hooks/pre-push
   ```

   **This is human-only, by design.** An agent seat **cannot** perform it: shell copy/`chmod`/move on hook paths are guard-denied and the agent's file-write tool cannot set mode `755`, so a hook an agent installs is non-executable and **silently ignored by git** (tracked as `AGENT-CANNOT-INSTALL-AN-EXECUTABLE-HOOK`). And `core.hooksPath` will **not** satisfy the Inception gate — `inception-done.sh` hard-codes the literal `.git/hooks/pre-push` path — so redirecting hooks elsewhere leaves the gate failing. Copy the file to that exact path and set the mode.

6. **The hook's two enforcement dials — you ship OBSERVE, and opt in when you're ready.** The installed hook has two legs that can refuse a push: the **entry declaration** (`KIT_PUSH_DECL` — the pushed head must carry a valid `Kit-*` trailer block) and the **design GO** (`KIT_PUSH_GO` — a Sensitive/Control-plane change-set must have a branch-scoped GO record). Both **observe** on your tree: they print and allow. That is deliberate — your first push is never red, and the kit's own dial state is `export-ignore`d so it can never arrive with the copy.

   To turn one on, create `.kit/dials.conf` at your repo root with the dial(s) you want:

   ```sh
   printf 'KIT_PUSH_DECL=enforce\n' > .kit/dials.conf
   ```

   Only the exact string `enforce` enforces; an absent file, a missing key, or any other value observes. Read it before you flip it: the value is **repo-carried**, so it applies to everyone who has installed the hook the moment it merges — no re-copy, because the hook reads the file live on every push. Precedence is **asymmetric**: an environment variable of the same name may *escalate* `observe` → `enforce` for one session, but it can never de-escalate an `enforce` set in the file (it loses, loudly) — otherwise one `export` would silently undo the decision. Roll a flip back the same way you made it: edit the file. And keep `.kit/dials.conf` under review like any other control-plane file — the kit's guard classifies it as control-plane, so an agent seat cannot flip your dials for you.

   **Honest ceiling, unchanged by any dial:** the hook is a speed bump, not a boundary — `git push --no-verify`, a never-installed hook and a stale copy all bypass it. CI is the backstop.

## 3. Inception (adapted)

`scripts/incept.sh` is the **greenfield** bootstrap — it renames the kit's root `CLAUDE.md` to `ENGINEERING-PRINCIPLES.md` and stamps fresh project artifacts, which assumes you started *from* the kit. In a brownfield repo you do the Inception **judgment** steps by hand (`../../START-HERE.md` steps 1–7): write the charter, record the stack as **ADR-000**, instantiate the project `CLAUDE.md` from `../../templates/PROJECT-CLAUDE-TEMPLATE.md`, start `RUNBOOK.md`, add a `.env.example` (the gate requires one), pick a backlog backend (`work-tracking/adapters.md`), assign roles. ⚠️ **`../../START-HERE.md` steps 1–7 are the source of truth** — this inline list is orientation, not the manifest (an enumerated list is exactly what drifts, which is why §1 says copy the whole tree).

**Stamp the entry contract — greenfield `incept` does this for you; here you must.** Copy the **§1 Entry contract** section of `ENGINEERING-PRINCIPLES.md` **byte-identical** into the top of your project `CLAUDE.md` (the harness contextFile) and into `AGENTS.md`, then fill the project header fields the template carries — `**Project:**`, `**Intent owner:**`, the backlog backend, and `- **Target harness(es)** (§harness-neutrality): …`. The context-binding checks compare these byte-for-byte, so a paraphrase does not satisfy them.

**Commit the baseline BEFORE running the gate.** The contextFile and the copied-in artifacts must be *tracked* for the gate to see them:

```sh
git add -A && git commit -m "adopt the kit (brownfield baseline)"
```

Then run the gate. Run the **surface** check now — it treats an as-yet-unprotected remote as an OUTSTANDING item rather than a hard failure, so you can pass Inception locally and protect `main` next:

```sh
sh conformance/inception-done.sh --surface
```

Once you have pushed to a remote and **protected `main`** (or, on a non-GitHub host, recorded the attestation — `vc-hosts.md`), run the strict gate (the default), which additionally requires verified branch protection:

```sh
sh conformance/inception-done.sh
```

The gate checks that the **runtime guard is wired** — the `PreToolUse` guard **and** the installed `.git/hooks/pre-push` rung from §2 (not just that `.claude/` exists) — so you cannot pass Inception with a dead guard.

## 4. Residual gaps (be honest about these)

The guard is necessary, not sufficient:

- **superpowers spec-path collision.** If you drive development with the superpowers harness, its brainstorming/writing-plans skills write specs to `docs/superpowers/specs/`, which this kit `.gitignore`s (pre-anonymization scratch). A `git add` there silently no-ops. Put tracked design docs under `docs/architecture/` (referenced by ADR-000), or un-ignore the path for your project.
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
