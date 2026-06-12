# Slice 5c: ML Stack Profile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a first-class **ML** stack profile (`profiles/ml/`) whose CI carries a real `gate-eval` step (the §7 eval-as-TDD gate), alongside MLflow/DVC/pandera/notebook-hygiene and the standard 8 §14 gates.

**Architecture:** Profile slice on branch `feature/slice-5c-ml-profile`, mirroring the Slice 5/5b pattern. `profiles/ml.md` (11 sections) + `profiles/ml/ci.yml` (8 standard `gate-*` ids **+ an extra `gate-eval`**) + companions derived from the Python reference. Validated by the existing `conformance/ci-gates.sh` (8 ids; gate-eval is an allowed extra) and `conformance/profile-completeness.sh` — no new conformance logic. Kit CI checks declaration + completeness (it does not execute the ML pipeline).

**Tech Stack:** Markdown, GitHub Actions YAML, POSIX `sh`. Profile toolchain: Python 3.12 · uv · ruff · mypy · pytest · MLflow · DVC · pandera · nbstripout/jupytext/nbqa/nbmake · Anthropic SDK (pinned eval judge). Spec: `docs/superpowers/specs/2026-06-06-slice5c-ml-profile-design.md`.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `profiles/ml.md` (new) | ML profile, 11 sections |
| `profiles/ml/ci.yml` (new) | Reference CI (8 gates + `gate-eval`) |
| `profiles/ml/CODEOWNERS` (new) | Review routing (derived from Python ref) |
| `profiles/ml/BRANCH-PROTECTION.md` (new) | Branch protection (derived from Python ref) |
| `VERSION` `CHANGELOG.md` `docs/ROADMAP-KIT.md` (edit) | 2.5.0; changelog; roadmap note |

**Precondition:** on branch `feature/slice-5c-ml-profile`. The committed `profiles/python/CODEOWNERS` + `profiles/python/BRANCH-PROTECTION.md` are the source for the derived companions.

---

### Task 1: profiles/ml.md

**Files:** Create `profiles/ml.md`

- [ ] **Step 1: Write the profile** — create `profiles/ml.md` with exactly this content (write LITERAL triple-backtick fences where the scaffold + commands blocks are shown):

```markdown
# Stack Profile — ML (Python)

> Reference profile. The concrete *how* for the universal `DEVELOPMENT-STANDARDS.md` on a machine-learning stack — data → training → **evaluation** → optional serving. Copy/adapt per project; record selection as ADR-000. (Sibling of `python`; the headline addition is the **eval gate**.)

**Stack:** Python 3.12+ · uv · scikit-learn / PyTorch (+ Anthropic SDK for LLM features) · MLflow · DVC · pandera · pytest · hosted training/serving (container / K8s)
**Status:** reference

---

## 1. Toolchain
- **Runtime:** Python 3.12+ · **Deps:** `uv` (lockfile `uv.lock`; exact pins for prod)
- **Format/lint:** `ruff` (+ `nbqa ruff` for notebooks) · **Types:** `mypy`
- **Tests:** `pytest` (+ `pandera` data validation, `nbmake` notebook smoke) · **Eval:** an `evals/` harness (the §7 eval gate) · **Build:** `uv build`
- **ML ops:** MLflow (experiment tracking + model registry) · DVC (data/model versioning) · notebook hygiene (`nbstripout` + `jupytext`)

## 2. Project scaffold
\`\`\`
src/<pkg>/{data,features,models,training,eval,serving}/
evals/                        # JSONL datasets + rubric + run.py (the eval gate)
notebooks/                    # jupytext-paired; outputs stripped (nbstripout)
conf/                         # configs (hydra/yaml)
tests/{unit,integration}/
dvc.yaml · params.yaml        # DVC pipeline + tracked params
docs/architecture/            # ADRs (incl. ADR-000)
.github/workflows/ci.yml
pyproject.toml · uv.lock · .env.example · .gitignore · ruff.toml · mypy.ini
\`\`\`
Baselines: ruff + mypy config; coverage fail_under = 80; pandera schemas for datasets; `nbstripout` installed as a git filter.

## 3. Standard commands
\`\`\`
install:       uv sync --frozen
dev:           uv run jupyter lab   # or: uv run python -m <pkg>.training
test:          uv run pytest
test:coverage: uv run pytest --cov --cov-fail-under=80
eval:          uv run python -m evals.run --threshold 0.8
lint:          uv run ruff check . && uv run nbqa ruff notebooks/
type-check:    uv run mypy .
build:         uv build
pipeline:      dvc repro          # reproduce data/training pipeline
\`\`\`

## 4. CI/CD pipeline
Implements the 7 required gates of `DEVELOPMENT-STANDARDS.md` §14 **plus the §7 eval gate**. Drop-in reference files live in **`profiles/ml/`**:
- **`ci.yml`** → copy to `.github/workflows/ci.yml`. `uv sync` → ruff (+nbqa) → mypy → pytest+coverage(≥80) → **`gate-eval` (evals/run.py, fails below threshold)** → `uv build` → gitleaks → `pip-audit` → CycloneDX-py SBOM → build provenance.
- **`CODEOWNERS`**, **`BRANCH-PROTECTION.md`** → governance companions.

Conformance: `sh conformance/ci-gates.sh profiles/ml/ci.yml` (the 8 standard gates; `gate-eval` is an additional ML gate). **`gate-eval` is the headline** — the AI analog of TDD, gating like tests.

## 5. Security implementation
- **Env/secrets:** `pydantic-settings` + fail-fast; `.env` gitignored; commit `.env.example`.
- **Data & models:** **never commit data/models** — DVC remote storage; `.gitignore` data dirs. **PII**: redact in logs, support right-to-erasure on training data, document provenance/consent.
- **Validation:** **pandera** schemas on datasets at boundaries; Pydantic on serving inputs; validate on every path.
- **AI / LLM security:** prompt-injection defense (never let inputs override system instructions; treat tool outputs as untrusted); **output validation against a schema** before acting; capability boundaries for agents (`DEVELOPMENT-STANDARDS.md` §2).
- **Artifact integrity:** attest/sign model artifacts; pin training data + base-model versions.

## 6. Testing
- **Convention:** `tests/` mirrors `src/`; `test_*.py`. Arrange-Act-Assert.
- **Data validation:** **pandera** schema tests on representative data (run in `pytest`).
- **Notebook smoke:** **nbmake** executes notebooks in CI (catches rot).
- **AI evals (the dev-time bar — `evals/`):** outputs scored against a **curated dataset + rubric** — metric thresholds (exact-match / graded for classic ML) and/or **LLM-as-judge with a pinned judge model** for genAI; plus a **safety/red-team** adversarial set. The suite is versioned with the code, grows from production misses, and **fails the build below threshold** (`gate-eval`). Track eval scores as a quality metric — a decline is tech debt.

## 7. Resilience & observability
- **Serving:** retry/backoff (`tenacity`), circuit breaker (`pybreaker`).
- **Logging:** `structlog` (JSON). **Error tracking:** Sentry.
- **ML observability:** **MLflow** experiment/run tracking + model registry; **data & prediction drift monitoring** (e.g. Evidently); eval scores tracked over time; serving metrics via OpenTelemetry.

## 8. Data & models
- **DVC** versions datasets, features, and model artifacts (remote storage; data never in git). **Reproducibility:** pinned `uv.lock`, fixed seeds, params recorded in MLflow, `dvc repro` for the pipeline. **Schema versioning** via pandera. **Model registry** (MLflow Models) with stages (Staging/Production).

## 9. Release & deploy
- **Artifact:** a registered model version (MLflow) + (for serving) a container image. **Build provenance attested on the model artifact.**
- **Rollout:** shadow / canary for model changes — watch eval scores + live metrics before promoting. **Rollback:** promote the previous registered model version (fastest); flag-off for app-level changes.
- **Serving:** FastAPI / BentoML container; merge to `main` → deploy.

## 10. Recommended libraries
scikit-learn / PyTorch · MLflow · DVC · pandera · nbstripout + jupytext + nbqa + nbmake · pytest + pytest-cov · the eval harness (`evals/run.py`, pytest-driven; Anthropic SDK as the pinned LLM judge) · Evidently (drift) · FastAPI / BentoML (serving) · pydantic + pydantic-settings · structlog + Sentry · Anthropic SDK (`anthropic`). Default Claude models: `claude-sonnet-4-6` (workhorse and default pinned eval judge unless a project pins another), escalate to Opus for hard reasoning.

## 11. Stack-specific gotchas
- **Never commit data/models/secrets** — DVC remote + `.env`; gitignore data dirs.
- Install **`nbstripout`** as a git filter — strip notebook outputs (they leak secrets and bloat diffs); pair notebooks with `jupytext`.
- **Reproducibility:** pin `uv.lock` AND fix seeds; record params/metrics in MLflow.
- **Pin the LLM judge model** — a moving judge invalidates eval comparisons; the eval set is *code* (version it, grow it from prod misses).
- Evals **gate like tests** — `gate-eval` fails the build below threshold; don't treat them as advisory.
- **Conditional §14/15-factor:** a *training* pipeline is batch — port-binding, concurrency, statelessness, and disposability are **N/A (mark with a one-line reason)**. The *serving* path (if present) must satisfy them. Backing-services (warehouse, registry, DVC remote) and telemetry always apply.
\`\`\`

---

**Last Updated:** 2026-06-06
```

- [ ] **Step 2: Verify and commit**

```bash
cd ~/Development/agentic-sdlc-kit
i=1; ok=1; while [ "$i" -le 11 ]; do grep -Eq "^## ${i}\. " profiles/ml.md || { echo "missing §$i"; ok=0; }; i=$((i+1)); done; [ "$ok" -eq 1 ] && echo "11 sections OK"
grep -Fq '[...]' profiles/ml.md && echo "FAIL placeholder" || echo "no [...] placeholder"
git add profiles/ml.md
git commit -m "feat: add ML stack profile (eval-gate-centric)"
```
Expected: `11 sections OK`; `no [...] placeholder`.

---

### Task 2: profiles/ml/ (ci.yml + CODEOWNERS + BRANCH-PROTECTION)

**Files:** Create `profiles/ml/ci.yml`, `profiles/ml/CODEOWNERS`, `profiles/ml/BRANCH-PROTECTION.md`

- [ ] **Step 1: Write `profiles/ml/ci.yml`** with exactly this content:

```yaml
# Reference CI pipeline for the ML profile.
# COPY & ADAPT: copy to your project's .github/workflows/ci.yml. Inert here in the kit.
# Carries the 8 standardized gate-* ids (DEVELOPMENT-STANDARDS.md §14) PLUS gate-eval
# (the §7 eval gate). conformance/ci-gates.sh asserts the 8; gate-eval is an allowed extra.
# HARDENING: pin uses:/tool versions for production.
name: CI

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read
  id-token: write
  attestations: write

jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: astral-sh/setup-uv@v5
        with:
          enable-cache: true
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Install dependencies
        id: gate-install
        run: uv sync --frozen

      - name: Lint
        id: gate-lint
        run: |
          uv run ruff check .
          uv run nbqa ruff notebooks/

      - name: Type-check
        id: gate-type-check
        run: uv run mypy .

      - name: Test + coverage (>=80%)
        id: gate-test
        run: uv run pytest --cov --cov-fail-under=80   # includes pandera data-validation + nbmake notebook smoke

      - name: Evaluate model/prompt quality (eval gate, §7)
        id: gate-eval
        run: uv run python -m evals.run --threshold 0.8   # fails the build below the eval threshold

      - name: Build
        id: gate-build
        run: uv build

      - name: Secret scan
        id: gate-secret-scan
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          # GITLEAKS_LICENSE: ${{ secrets.GITLEAKS_LICENSE }}  # required for org repos

      - name: Dependency vulnerability scan
        id: gate-dep-scan
        run: uvx pip-audit

      - name: Generate SBOM (CycloneDX)
        id: gate-sbom
        run: uvx cyclonedx-py environment --output-format JSON --outfile sbom.json

      - name: Upload SBOM
        uses: actions/upload-artifact@v4
        with:
          name: sbom
          path: sbom.json

      - name: Attest build provenance
        id: gate-provenance
        # Attest the build artifact (and/or the registered model artifact) on the release path.
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        uses: actions/attest-build-provenance@v1
        with:
          subject-path: dist/**
```

- [ ] **Step 2: Derive the governance companions**

```bash
cd ~/Development/agentic-sdlc-kit
sed 's/Python profile/ML profile/' profiles/python/CODEOWNERS > profiles/ml/CODEOWNERS
sed 's/(Python profile)/(ML profile)/' profiles/python/BRANCH-PROTECTION.md > profiles/ml/BRANCH-PROTECTION.md
```

- [ ] **Step 3: Verify and commit**

```bash
cd ~/Development/agentic-sdlc-kit
sh conformance/ci-gates.sh profiles/ml/ci.yml; echo "exit=$?"
grep -q "id: gate-eval" profiles/ml/ci.yml && echo "gate-eval present"
ruby -ryaml -e "YAML.load_file('profiles/ml/ci.yml'); puts 'YAML OK'"
test -f profiles/ml/CODEOWNERS && grep -q "required_status_checks" profiles/ml/BRANCH-PROTECTION.md && echo "companions OK"
git add profiles/ml/ci.yml profiles/ml/CODEOWNERS profiles/ml/BRANCH-PROTECTION.md
git commit -m "feat: add ML reference CI (8 gates + gate-eval) + governance companions"
```
Expected: ci-gates `OK ... declares all required CI gates`, `exit=0`; `gate-eval present`; `YAML OK`; `companions OK`.

---

### Task 3: VERSION + CHANGELOG + ROADMAP (2.5.0)

**Files:** Modify `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-KIT.md`

- [ ] **Step 1: Bump VERSION** — overwrite `VERSION` with exactly one line + trailing newline:

```
2.5.0
```

- [ ] **Step 2: Add the 2.5.0 CHANGELOG entry** — in `CHANGELOG.md`, find this exact line:

```
## [2.4.0] - 2026-06-06
```

Insert IMMEDIATELY BEFORE it:

```
## [2.5.0] - 2026-06-06

Slice 5c — ML stack profile. The kit's first profile with a real **eval gate** — wiring the §7 "evals = the dev-time bar / AI analog of TDD" doctrine into CI.

### Added
- `profiles/ml.md` + `profiles/ml/` (`ci.yml`, `CODEOWNERS`, `BRANCH-PROTECTION.md`) — Python ML lifecycle: uv · ruff (+nbqa) · mypy · pytest (+ pandera data-validation, nbmake notebook smoke) · MLflow (tracking/registry) · DVC (data/model versioning) · notebook hygiene (nbstripout/jupytext) · gitleaks · pip-audit · CycloneDX-py + provenance.
- A dedicated **`gate-eval`** step in the ML `ci.yml` (`python -m evals.run --threshold 0.8`) that fails the build below the eval threshold — metric thresholds and/or LLM-as-judge (pinned judge), plus a safety/red-team set. `conformance/ci-gates.sh` validates the 8 standard gates; `gate-eval` is an allowed ML extra.

### Note
The ML profile applies the **conditional 15-factor** mechanism: a training pipeline is batch, so port-binding/concurrency/stateless/disposability are N/A-with-reason; the serving path satisfies them. `incept.sh --stack ml` wires the profile's CI. The data-engineering profile follows as a separate slice.

```

- [ ] **Step 3: Add the 2.5.0 link reference** — in `CHANGELOG.md`, find:

```
[2.4.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v2.4.0
```

Replace with:

```
[2.5.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v2.5.0
[2.4.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v2.4.0
```

- [ ] **Step 4: Note the ML profile in the roadmap** — in `docs/ROADMAP-KIT.md`, find this exact line:

```
| 5 ✅ | **Enterprise profiles** *(v2.3.0; +v2.4.0)* | `profiles/_TEMPLATE.md` | Python + Java/Spring (v2.3.0); **.NET + Go + Rust + Kotlin + `scripts/new-profile.sh` BYO on-ramp (v2.4.0)** | `conformance/profile-completeness.sh` |
```

Replace with:

```
| 5 ✅ | **Enterprise profiles** *(v2.3.0 → v2.5.0)* | `profiles/_TEMPLATE.md` | Python, Java/Spring (v2.3.0); .NET, Go, Rust, Kotlin + BYO `new-profile.sh` (v2.4.0); **ML — eval-gate-centric (v2.5.0)** | `conformance/profile-completeness.sh` |
| 5c2 | **Data-engineering profile** *(next)* | `profiles/_TEMPLATE.md` | `profiles/data-engineering/` (dbt/orchestration/data-contracts; shape-different gate model) | `conformance/profile-completeness.sh` |
```

- [ ] **Step 5: Verify and commit**

```bash
cd ~/Development/agentic-sdlc-kit
cat VERSION
grep -c "## \[2.5.0\]" CHANGELOG.md
grep -c "v2.5.0" docs/ROADMAP-KIT.md
git add VERSION CHANGELOG.md docs/ROADMAP-KIT.md
git commit -m "release: 2.5.0 — Slice 5c ML profile (changelog + roadmap)"
```
Expected: `2.5.0`; `1`; `1` or more.

---

### Task 4: Final validation + PR

**Files:** none created; verification + PR only.

- [ ] **Step 1: Full conformance sweep (8 profiles incl. ml)**

```bash
cd ~/Development/agentic-sdlc-kit
sh conformance/profile-completeness.sh; echo "exit=$?"
for p in typescript-node python java-spring dotnet go rust kotlin ml; do sh conformance/ci-gates.sh "profiles/$p/ci.yml" >/dev/null && echo "ci-gates $p OK"; done
grep -q "id: gate-eval" profiles/ml/ci.yml && echo "gate-eval present in ml"
sh conformance/agent-autonomy.sh >/dev/null && echo "agent-autonomy OK"
sh conformance/check-links.sh >/dev/null && echo "check-links OK"
```
Expected: profile-completeness all PASS + `exit=0`; `ci-gates <p> OK` for all 8; `gate-eval present in ml`; agent-autonomy OK; check-links OK.

- [ ] **Step 2: incept wires the ML profile (end-to-end)**

```bash
cd ~/Development/agentic-sdlc-kit
tmp=$(mktemp -d); git archive HEAD | tar -x -C "$tmp"
( cd "$tmp" && sh scripts/incept.sh --noninteractive --name DemoML --intent-owner "CI" --stack ml --backlog md ) >/dev/null
sh conformance/inception-done.sh "$tmp" >/dev/null && echo "incept --stack ml -> inception-done OK"
sh conformance/ci-gates.sh "$tmp/.github/workflows/ci.yml" >/dev/null && echo "wired ml CI satisfies §14"
rm -rf "$tmp"
```
Expected: `incept --stack ml -> inception-done OK`; `wired ml CI satisfies §14`.

- [ ] **Step 3: Existing 7 profiles untouched (additive)**

```bash
cd ~/Development/agentic-sdlc-kit
git diff --stat main..HEAD -- profiles/typescript-node.md profiles/python.md profiles/java-spring.md profiles/dotnet.md profiles/go.md profiles/rust.md profiles/kotlin.md | tail -1
echo "(no line above = unchanged)"
```
Expected: no diff line (existing profiles unchanged).

- [ ] **Step 4: Push and open the PR**

```bash
cd ~/Development/agentic-sdlc-kit
git push -u origin feature/slice-5c-ml-profile
gh pr create --title "Slice 5c: ML stack profile — the kit's first eval gate (v2.5.0)" --body "$(cat <<'EOF'
## Summary
A first-class **ML** profile covering the ML lifecycle (data → train → eval → serve), and the kit's first profile with a real **eval gate**.

- **`profiles/ml.md`** + `profiles/ml/` — uv · ruff(+nbqa) · mypy · pytest(+pandera+nbmake) · MLflow · DVC · notebook hygiene · gitleaks · pip-audit · CycloneDX-py + attest.
- **`gate-eval`** in `profiles/ml/ci.yml` — `python -m evals.run --threshold 0.8`, fails the build below threshold (metric thresholds and/or LLM-as-judge with a pinned judge + safety set). Wires the §7 "evals = the dev-time bar / AI analog of TDD" doctrine into CI for the first time.
- **Conditional 15-factor:** training=batch → port-binding/concurrency/stateless N/A-with-reason; serving path satisfies them.
- **Release** 2.5.0 (MINOR). Additive — the existing 7 profiles are untouched.

## Verified
`profiles/ml/ci.yml` passes `ci-gates.sh` (8 standard ids; `gate-eval` is an allowed extra); `profile-completeness.sh` passes all 8 profiles; `incept --stack ml` wires CI + passes `inception-done.sh` + §14. Zero new conformance logic.

## Ratification
Additive profile. **Human ratification required before merge.**

Spec: `docs/superpowers/specs/2026-06-06-slice5c-ml-profile-design.md`
Plan: `docs/superpowers/plans/2026-06-06-slice5c-ml-profile.md`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
Expected: branch pushed; PR URL printed; CI starts.

- [ ] **Step 5: Report CI status, stop for ratification**

```bash
cd ~/Development/agentic-sdlc-kit
sleep 15
gh pr checks 2>&1 | head
```
Do **not** merge. Report PR URL + CI results.

---

## Self-Review (completed by plan author)

**Spec coverage:** §3 deliverables mapped — ml.md→T1, ml/ci.yml+companions→T2, VERSION/CHANGELOG/ROADMAP→T3, validation/PR→T4. Spec §4.2 `gate-eval` + 8 standard gates → T2 ci.yml (verified the 8 ids + gate-eval present). Spec §5 conditional-§14 + eval discipline → ml.md §6/§11 (T1). Spec §5 validation (ci-gates, profile-completeness over 8, incept wiring, additive) → T4.

**Placeholder scan:** no TBD/TODO in the plan. The `evals.run --threshold 0.8` invocation is a defined contract the adopter implements in `evals/` (consistent with the reference-impl philosophy; documented in ml.md §2/§6). No `[...]` in ml.md (the completeness check verifies). The SBOM upload path (`sbom.json`) matches `--outfile sbom.json` (the Slice-5b lesson applied).

**Type/name consistency:** the ML `ci.yml` declares all 8 standard `gate-*` ids `ci-gates.sh` requires, plus `gate-eval`; profile name `ml` matches the companion dir `profiles/ml/` and the `--stack ml` value (T4). Companion derivation uses the Python reference's actual header strings ("Python profile" / "(Python profile)").
