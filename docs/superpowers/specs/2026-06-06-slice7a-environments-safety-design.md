# Design — Slice 7a: Environments & Production Safety

**Date:** 2026-06-06
**Status:** Approved (umbrella plan) — pending spec review
**Author:** Bradley James + agent
**Roadmap:** First sub-slice of Slice 7 (Adoption, Personas, Environments & Safety). Do-no-harm first. Plan: `~/.claude/plans/drifting-stirring-thunder.md`.

---

## 1. Goal

Close the two top safety gaps the audit found: (G1) the kit has no **Dev → QA → UAT → Prod** environment model with gated promotion, and (G2/G3/G4) the agent guard is **environment-blind**, misses many destructive tools, and prod-deploy/branch protection are documented but not enforced or verified. This slice makes the kit's "does no harm" promise real for an environment-segmented enterprise — **without weakening any existing guardrail**.

## 2. Decisions

- **Environment model:** ship **Dev → QA → UAT → Prod** as the default reference (configurable per project), with **gated promotion** and **production always human-gated**. Express it as contract in `DEVELOPMENT-PROCESS.md` + `DEVELOPMENT-STANDARDS.md` §14, and as a per-project config point in `PROJECT-CLAUDE-TEMPLATE.md`.
- **Guard is environment-aware *additively* (THE central decision):** the existing blanket bans are **kept and never loosened** (an agent never runs `DROP`/`dropdb`/`rm -rf`/force-push/etc. in *any* environment). On top of them we (a) **expand destructive-tool coverage** (the G2 list) as more blanket bans, and (b) add a **prod-context catch-all** layer that denies mutating commands carrying explicit prod markers (`--context …prod`, `*_ENV=prod…`, `--env production`). We do **NOT** introduce "allow this destructive op if it looks local" exceptions for the catastrophic set — that is exactly where weakening creeps in. Net effect: strictly more is denied; the 35 existing conformance cases still pass.
- **Enforcement, not just prose:** add `conformance/branch-protection.sh` (assert `main` is actually protected via `gh api`) and a **reference prod-deploy workflow** using GitHub `environment:` protection + required reviewers. Wire `incept.sh` to **apply-or-hard-remind** branch protection.
- **Honest boundary:** state explicitly that the guard governs the **Claude Code runtime only** — humans at a shell and other agent runtimes are **Org-owned** (platform controls: DB IAM, separate prod accounts, deploy approvals).
- **Version:** **2.13.0** (MINOR — additive; no new *required CI gate*; the env-aware guard and new conformance are additive enforcement). `branch-protection.sh` is a new conformance *check*, not a new §14 gate.

## 3. Deliverables

| Part | Files |
|------|-------|
| Env model (contract) | `DEVELOPMENT-PROCESS.md` (new "Environments & promotion" subsection), `DEVELOPMENT-STANDARDS.md` §14 (deploy/promotion gate), `templates/PROJECT-CLAUDE-TEMPLATE.md` (env config), `RUNBOOK-TEMPLATE.md` (promotion/rollback) |
| Env-aware guard | `.claude/hooks/guard.sh` (expanded bans + prod catch-all), `.claude/README.md` (coverage + Org-owned boundary) |
| Conformance | `conformance/agent-autonomy.sh` (new deny + false-positive-allow cases), new `conformance/branch-protection.sh`, `conformance/README.md` (index row), `conformance/audit-evidence-checklist.md` (new Auto rows) |
| Incept | `scripts/incept.sh` (branch-protection apply-or-remind) |
| Prod-deploy reference | a documented reference deploy workflow with `environment:` protection (in `DEVELOPMENT-STANDARDS.md` §14 and/or a profile companion) |
| Boundary | `docs/enterprise/README.md` (human/other-runtime Org-owned note) |
| Meta | `VERSION` 2.13.0; `CHANGELOG.md`; `docs/ROADMAP-KIT.md` (7a row) |

## 4. Detailed design

### 4.1 Environment model (Dev → QA → UAT → Prod)
- New subsection in `DEVELOPMENT-PROCESS.md` (near §3 Inception config / §9 Operate): define the four tiers, what each is for, and **gated promotion** — a change moves Dev → QA → UAT → Prod, each promotion gated (CI green + the tier's acceptance). **Production promotion is always human-gated** (ties to §13 + ratification RBAC Release Manager). QA = automated/integration acceptance; UAT = stakeholder/business acceptance (this is also where the **QA persona** in 7b plugs in).
- Configurable per project: a project may collapse tiers (e.g. Dev→Prod for a tiny internal tool) **with a one-line reason** (the kit's N/A-with-reason idiom), but the *contract* is separation + gated promotion + prod human-gate.
- `PROJECT-CLAUDE-TEMPLATE.md`: replace the `local → [staging?] → production` line with the Dev/QA/UAT/Prod model + per-tier deploy trigger + which tiers this project uses.
- `DEVELOPMENT-STANDARDS.md` §14: add a promotion/deploy gate row (prod deploy requires human approval + green pipeline) and align §13 factor 9 (dev/prod parity → "parity across all tiers").

### 4.2 Env-aware guard (`.claude/hooks/guard.sh`) — additive
**(a) Expand the destructive blanket bans** — add deny patterns (matched on `.command`, over-block on quoting, same idiom as today) for:
- `DROP DATABASE` (extend the existing DB-client SQL pattern to include `drop[[:space:]]+database`).
- ORM/framework DB destruction: Rails (`rails db:drop`, `rails db:reset`, `rake db:drop`, `db:migrate:reset`), Laravel (`artisan migrate:fresh`, `artisan migrate:reset`, `artisan db:wipe`), Django (`manage.py flush`, `manage.py reset_db`, `manage.py sqlflush`), Alembic (`alembic downgrade base`), Flyway (`flyway clean`), .NET EF (`dotnet ef database drop`, `ef database update 0`).
- `pg_restore` with `--clean`/`-c`.
- `redis-cli … FLUSHALL|FLUSHDB`.
- Container/cluster state destruction: `kubectl delete`, `docker volume rm`, `docker volume prune`, `docker system prune … -a`.
- Cloud resource deletion: `aws s3 rm … --recursive`, `aws s3 rb`, `aws rds delete-db-instance`, `aws dynamodb delete-table`, `gcloud sql instances delete`, `az group delete`, `az sql … delete`.

**(b) Add a prod-context catch-all** — deny a mutating command that carries an explicit production marker, regardless of the specific verb:
- kube/helm prod context: `--context[ =][^[:space:]]*prod`, `kubectl … -n[ ]*prod*` combined with a mutating verb.
- env-prefixed mutating command: `(NODE_ENV|RAILS_ENV|APP_ENV|DJANGO_ENV|ENV|ENVIRONMENT)=prod[a-z]*[[:space:]]+…` before a destructive/deploy verb.
- explicit flags: `--env[ =]prod`, `--environment[ =]production`.
The catch-all is **scoped to co-occur with a mutating/destructive/deploy verb** so a commit message or a read command mentioning "production" is NOT denied (preserves the existing false-positive guarantees; field-scoping to `.command` already helps).

**No existing deny is removed or narrowed.** The `.env.production` write-deny stays. The deploy/apply line stays.

### 4.3 `conformance/agent-autonomy.sh` — new cases (regression-lock)
Add, matching the existing `assert_deny`/`assert_allow` format:
- **deny:** `DROP DATABASE`, `rails db:drop`, `rake db:drop`, `artisan migrate:fresh`, `manage.py flush`, `alembic downgrade base`, `flyway clean`, `dotnet ef database drop`, `pg_restore --clean`, `redis-cli FLUSHALL`, `kubectl delete`, `docker volume rm`, `aws s3 rm --recursive`, `gcloud sql instances delete`; **prod catch-all:** `kubectl --context prod-cluster apply -f x`, `NODE_ENV=production npx prisma migrate reset`, `helm --kube-context prod upgrade`.
- **allow (false-positive guards):** a commit message mentioning "flush the cache" / "drop database migration plan"; `kubectl get pods` (read); `docker build`; `aws s3 ls`; a dev-context command `kubectl --context dev delete pod x` — **NOTE:** this one is a design call — `kubectl delete` is a *blanket* ban, so it is denied even in dev (safe-by-over-block). Document that in the test comment rather than allowing it. (If dev-ergonomics demand it later, that's a separate, explicit decision.)
- Confirm all 35 existing cases remain and still pass.

### 4.4 `conformance/branch-protection.sh` + incept wiring
- New script: given a repo (default `origin`), assert via `gh api repos/{owner}/{repo}/branches/main/protection` that protection exists with: required PR review (≥1, `require_code_owner_reviews` where the plan allows), required status checks, and `enforce_admins`/no-bypass as configured. **Checklist-aware:** if `gh` is unauthenticated or the repo is local-only, exit with a clear "cannot verify — run in CI / authenticate" message (informational, like `inception-done.sh` needing a bootstrapped project) — do not hard-fail the kit's own CI where it can't reach the API.
- `incept.sh`: after copying CODEOWNERS, **attempt** to apply branch protection via `gh api` if `gh` is available + authenticated; otherwise print a **hard reminder** (not a soft note) with the exact command. Never silently skip.
- `conformance/audit-evidence-checklist.md`: flip "Branch protection · builder ≠ sole merger" toward **Auto** (cite `branch-protection.sh`).

### 4.5 Reference prod-deploy workflow
- A documented reference (in `DEVELOPMENT-STANDARDS.md` §14 deploy section, and/or a profile companion `deploy.yml`) using GitHub `environment: production` with **required reviewers** + the promotion gate, so prod deploy is human-gated by the platform, not just prose. Inert in the kit (like the profile `ci.yml`s); adopters wire it.

### 4.6 Human-coverage boundary (honesty)
- `.claude/README.md` + `docs/enterprise/README.md`: state that the guard governs the **Claude Code agent runtime only**; humans at a shell and other agent runtimes are **Org-owned** — production safety also requires platform controls (DB IAM, separate prod credentials/accounts, deploy approvals). This is the honest edge the audit demanded.

## 5. Validation / testing
- `sh conformance/agent-autonomy.sh` → exit 0 with ALL 35 prior cases + the new deny/allow cases passing (prove no weakening + new coverage).
- `sh conformance/branch-protection.sh` → behaves correctly: verifies protection when `gh` can reach the API; clean informational exit when it can't (doesn't break kit CI).
- `sh conformance/check-links.sh`, `profile-completeness.sh`, `ci-gates.sh` (×10) → green (no regression).
- incept-into-temp: branch-protection apply-or-remind path runs; `inception-done.sh` still passes.
- Manual guard spot-checks for the prod catch-all false-positive guards (a "production" mention in a non-mutating command is allowed).
- Kit CI green (`conformance`/`bootstrap`/`docs-links`).

## 6. Risks & mitigations
- **Weakening the guard (the #1 risk).** Mitigation: env-awareness is purely additive; the 35 existing cases are the regression lock; the spec forbids local-allow exceptions on the catastrophic set.
- **Prod catch-all false positives** (a benign command mentioning "prod"). Mitigation: catch-all requires a prod marker **co-occurring with a mutating/deploy verb**; field-scoped to `.command`; explicit allow-cases added.
- **`branch-protection.sh` can't reach the API in local/CI.** Mitigation: informational clean-exit path (mirror `inception-done.sh`'s "needs a bootstrapped project" behavior); never hard-fail where it can't verify.
- **dash portability.** New regexes use POSIX `grep -E` only (no bashisms); verified like prior guard work.
- **Over-blocking dev ergonomics** (`kubectl delete` denied even in dev). Mitigation: documented as intentional safe-by-over-block; a future explicit decision can add dev-scoped allowances if needed.

## 7. Out of scope
- Per-profile container/k8s deploy *artifacts* (that's 7c). 7a's prod-deploy piece is the *gate/reference*, not full container deploy.
- The QA/UAT *persona* wiring (7b) — 7a defines the env tiers; 7b puts the roles on them.
- Platform-side human controls (DB IAM, account separation) — stated as Org-owned, not built.

## 8. Definition of Done
- Dev→QA→UAT→Prod model in PROCESS + STANDARDS §14 + PROJECT-CLAUDE-TEMPLATE (+ RUNBOOK promotion/rollback); prod always human-gated.
- `guard.sh` expanded coverage + prod catch-all; **no existing deny weakened**.
- `agent-autonomy.sh`: all 35 prior cases pass + new deny/allow cases; `branch-protection.sh` added + indexed; incept apply-or-hard-remind; audit-evidence Auto row updated.
- Reference prod-deploy workflow (env-protected) documented; human-coverage Org-owned boundary stated.
- All conformance green; kit CI green; `VERSION` 2.13.0; CHANGELOG + ROADMAP (7a).
- Feature branch → PR → **human ratification** (governing-doc + guard change → Security-Owner lens).
