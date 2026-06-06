# Design — Slice 2: Agent Governance Layer (.claude/ reference + conformance)

**Date:** 2026-06-06
**Status:** Approved (brainstorming) — pending spec review
**Author:** Bradley James + agent
**Roadmap:** `docs/ROADMAP-KIT.md` Slice 2. Follows Slice 1 (CI/CD, v2.0.0).

---

## 1. Goal

Make the §13 autonomy tiers and §12 separations **mechanically enforced** for agents working in a repo — not just described. Ship a Claude Code `.claude/` governance layer (permissions + a PreToolUse guard hook + reviewer/security subagents) that blocks irreversible/high-blast actions, plus an executable conformance check proving a tier breach is actually denied. This converts "agent governance" from policy into a running guardrail.

## 2. Decisions (from brainstorming)

- **Enforcement:** `settings.json` deny/ask/allow permission globs **+ a `PreToolUse` hook** (`guard.sh`) for pattern logic the globs can't express (e.g. distinguishing `git push --force` from a normal push). The hook is what conformance exercises.
- **Default policy:** **deny** the §13 irreversible/high-blast set · **ask** medium reversible-but-notable · **allow** safe read/analyze/normal-git. Conservative default the team loosens as agents earn autonomy (§13).
- **Placement:** one committed `.claude/` at the kit root serves as **both** the kit's own dogfooding governance **and** the adopter reference (the layer is stack-independent but Claude-Code-specific). Adopters copy the directory and adapt.
- **jq dependency:** `guard.sh` uses `jq` to extract the relevant input field so it matches the *command/path*, not the whole payload (avoids false-positives like blocking a doc that merely mentions `rm -rf`). jq is a documented prerequisite (like gitleaks in Slice 1); if absent the guard denies *mutating* tools (Bash/Write/Edit) with an install message and allows read-only — fail-safe toward caution.
- **Version:** **2.1.0** (MINOR) — additive reference + conformance; the binding contract (§13) already existed, so this is not a MAJOR per `MAINTAINING.md` §2.

## 3. Deliverables

| Part | Files |
|------|-------|
| **Contract** (light edit) | `DEVELOPMENT-PROCESS.md` §13 — "Enforcement reference" note → `.claude/` + `conformance/agent-autonomy.sh` |
| **Reference / kit-own** | `.claude/settings.json`, `.claude/hooks/guard.sh`, `.claude/agents/reviewer.md`, `.claude/agents/security-reviewer.md`, `.claude/README.md` |
| **Conformance** | `conformance/agent-autonomy.sh`; index row in `conformance/README.md`; new step in `.github/workflows/ci.yml` |
| **Hygiene** | `.gitignore` adds `.claude/settings.local.json` |
| **Meta** | `VERSION` → `2.1.0`; `CHANGELOG.md` 2.1.0 entry; `docs/ROADMAP-KIT.md` Slice 2 done |

## 4. Detailed design

### 4.1 `.claude/settings.json`

JSON with a `permissions` object and a `hooks` object. Headed (in `.claude/README.md`, since JSON has no comments) as the reference + kit-own governance.

- **`permissions.allow`** (L1–L3 safe/reversible): `Read`, `Grep`, `Glob`, `Bash(git status:*)`, `Bash(git diff:*)`, `Bash(git add:*)`, `Bash(git commit:*)`, `Bash(git push origin feature/*:*)`, `Bash(npm test:*)`, `Bash(npm run test:*)`, `Bash(sh conformance/*:*)`.
- **`permissions.ask`** (medium): `Bash(npm install:*)`, `Bash(npm ci:*)`, `Bash(brew install:*)`, `Write(/*)` (absolute paths = outside repo), `WebFetch`.
- **`permissions.deny`** (clear-cut irreversible expressible as globs): `Bash(rm -rf:*)`, `Bash(npm publish:*)`, `Write(.env)`. (The nuanced secret-file set — `.env.local`, `*.pem`, `*.key`, `**/secrets/**`, while still allowing `.env.example` — is handled in `guard.sh`, since a single deny glob like `Write(.env.*)` would wrongly also match `.env.example`.)
- **`hooks.PreToolUse`**: one matcher (`Bash|Write|Edit`) running `sh .claude/hooks/guard.sh`.

### 4.2 `.claude/hooks/guard.sh` (the PreToolUse guard)

POSIX `sh`. Protocol: reads the tool-call JSON on stdin; emits a Claude Code decision on stdout and exits 0.

- Extract `tool_name` and the relevant field with `jq`:
  - `Bash` → `.tool_input.command`
  - `Write`/`Edit` → `.tool_input.file_path`
- **jq-missing fallback:** if `jq` is not on PATH, print a stderr warning and deny only mutating tools (`Bash`/`Write`/`Edit`) with reason "agent-guard: jq required to evaluate tool safety — install jq"; allow others. Fail-safe toward caution; never bricks read-only diagnosis.
- **Deny patterns** (matched against the extracted field only):
  - command: `rm -rf` / `rm -fr`; `git push` with `--force`/`-f`/`+`; `git push` to `main`/`master`; `git reset --hard`; `git commit --amend` (history rewrite); `DROP TABLE`/`TRUNCATE`/`DELETE FROM` (no WHERE); `npm publish`/`yarn publish`; `curl`/`wget` piped to `sh`/`bash`; prod-deploy markers (`--prod`, `deploy production`); secret rotation markers.
  - file_path: writes to `.env` (not `.env.example`), `*.pem`, `*.key`, `id_rsa`, `**/secrets/**`.
- On match → print `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"§13 (DEVELOPMENT-PROCESS.md): <action> is irreversible/high-blast — human-gated. Override: a human runs it or raises the tier per the autonomy matrix."}}` and exit 0.
- No match → exit 0 silently (defers to the permission globs / normal flow). **Normal commit + feature-branch push are never denied** — protects the hook's own authors and adopters.

### 4.3 Subagents

- **`.claude/agents/reviewer.md`** — frontmatter (`name: reviewer`, `description`, `tools: Read, Grep, Glob, Bash(git diff:*)`, read-only). System prompt: independent review for correctness, project standards, and the §14 CI gates; enforces **builder ≠ reviewer** (§12). Returns findings; does not merge.
- **`.claude/agents/security-reviewer.md`** — frontmatter (`name: security-reviewer`, read-only tools). System prompt: the security-owner lens — injection, authz, secret handling, the §7 security tests, prompt-injection for AI features. The conditional security gate.

### 4.4 `.claude/README.md`

Explains the layer for adopters (esp. low-AI-experience teams): what each file does, the autonomy mapping to §13, how to adapt the deny/ask sets, the jq prerequisite, and that `settings.local.json` is personal/gitignored while `settings.json` is shared/committed.

### 4.5 `conformance/agent-autonomy.sh`

POSIX `sh`. Pipes simulated tool-call JSONs into `guard.sh` and asserts the decision:
- **Deny (assert `permissionDecision: deny`):** `rm -rf /tmp/x`; `git push --force`; `git push origin main`; `git reset --hard`; Write `.env`; `npm publish`; `DROP TABLE users`.
- **Allow (assert NOT denied):** `git commit -m x`; `git push origin feature/foo`; `npm test`; Read a file; **Write a doc whose content contains the text `rm -rf`** (file_path is a `.md`, not a secret) — the false-positive regression guard.
- Exits 0 if all assertions hold; non-zero listing the first failure. Skips gracefully (or notes) if jq absent, but CI has jq.

### 4.6 CI integration

Add to the kit's `.github/workflows/ci.yml` `conformance` job a step: `sh conformance/agent-autonomy.sh` (ubuntu has jq). The kit dogfoods the guard.

### 4.7 Contract note (§13)

Append a short "Enforcement reference" paragraph to `DEVELOPMENT-PROCESS.md` §13: the tool-neutral contract is enforced for Claude Code by the committed `.claude/` layer; conformance is `conformance/agent-autonomy.sh`. Keep §13 tool-neutral; the reference is the concrete how (analogous to a profile).

## 5. Validation / testing

- **Positive:** `agent-autonomy.sh` — all safe calls allowed, all dangerous calls denied.
- **Negative / regression:** a `Write` to `notes.md` containing `rm -rf` in its content is **allowed** (field-scoped matching, not payload grep).
- **jq-missing path:** simulate `PATH` without jq → guard denies Bash/Write/Edit with install message, allows Read.
- **Self-non-interference:** `git commit` and `git push origin feature/*` are allowed (verified in the allow battery) — the committed hook does not block this slice's own PR flow.
- **Dogfood:** kit CI `conformance` job runs `agent-autonomy.sh` green.
- **Consistency:** §13 stays tool-neutral; `.gitignore` excludes `settings.local.json`; conformance README indexed.

## 6. Risks & mitigations

- **Hook governs this very session once committed.** Mitigation: deny set is strictly irreversible/high-blast; normal commit/feature-push explicitly allowed; verified by the allow battery before the PR push. If Claude Code only loads settings at session start, the committed hook may not even bind mid-session — either way the flow is safe.
- **False positives blocking legitimate work** (e.g. editing docs about dangerous commands). Mitigation: field-scoped matching via jq (the core 4.2 decision) + an explicit regression test (4.5).
- **jq absence.** Mitigation: documented prerequisite + fail-safe degrade (deny mutating, allow read-only) + clear install message.
- **Over-blocking frustrates teams → they disable governance.** Mitigation: conservative deny-only-irreversible default; medium = ask; everything safe allowed. Tunable per §13.
- **Claude Code hook/permission schema drift.** Mitigation: `.claude/README.md` notes the schema is Claude-Code-versioned; conformance tests the guard's *logic* (stdin→decision) independent of Claude Code wiring.

## 7. Out of scope (later/again)

Non-Claude-Code agent runtimes (contract §13 is tool-neutral; this is the Claude Code reference) · Inception bootstrap auto-wiring `.claude/` (Slice 3) · per-project autonomy tuning (adopters at Inception) · agent-quality-metrics tracking automation (§13 — future).

## 8. Definition of Done (this slice)

- `.claude/{settings.json,hooks/guard.sh,agents/reviewer.md,agents/security-reviewer.md,README.md}` present.
- `guard.sh` denies the irreversible battery and allows the safe battery, incl. the doc-mentions-`rm -rf` regression — proven by `conformance/agent-autonomy.sh`.
- `.gitignore` excludes `.claude/settings.local.json`; that file is not committed.
- Conformance indexed; kit CI runs `agent-autonomy.sh` green.
- §13 enforcement-reference note added (tool-neutral preserved).
- `VERSION` = `2.1.0`; CHANGELOG 2.1.0 entry; roadmap Slice 2 done.
- Feature branch → PR; **human-ratified before merge** (edits a governing doc).
