# Stack Profile — ML (Python)

> Reference profile. The concrete *how* for the universal `DEVELOPMENT-STANDARDS.md` on a machine-learning stack — data → training → **evaluation** → optional serving. Copy/adapt per project; record selection as ADR-000. (Sibling of `python`; the headline addition is the **eval gate**.)

**Stack:** Python 3.12+ · uv · scikit-learn / PyTorch (+ Anthropic SDK for LLM features) · MLflow · DVC · pandera · pytest · hosted training/serving (container / K8s)
**Status:** reference

---

## Best for / Avoid when

**Best for:** Model training/serving, experiments, eval-driven development.
**Avoid when:** Plain web APIs with no ML component.

Choosing a stack? Compare all profiles → [../docs/STACK-SELECTION.md](../docs/STACK-SELECTION.md).

---

## 1. Toolchain
- **Runtime:** Python 3.12+ · **Deps:** `uv` (lockfile `uv.lock`; exact pins for prod)
- **Format/lint:** `ruff` (+ `nbqa ruff` for notebooks) · **Types:** `mypy`
- **Tests:** `pytest` (+ `pandera` data validation, `nbmake` notebook smoke) · **Eval:** an `evals/` harness (the §7 eval gate) · **Test quality:** Hypothesis (property-based) + mutmut (mutation — `docs/operations/test-quality.md`) · **Build:** `uv build`
- **Inner loop:** `pre-commit` (ruff/mypy + nbqa for notebooks; `pytest-testmon`) — fast feedback before CI (`docs/operations/dev-inner-loop.md`)
- **ML ops:** MLflow (experiment tracking + model registry) · DVC (data/model versioning) · notebook hygiene (`nbstripout` + `jupytext`)

## 2. Project scaffold
```
src/<pkg>/{data,features,models,training,eval,serving}/
evals/                        # JSONL datasets + rubric + run.py (the eval gate)
notebooks/                    # jupytext-paired; outputs stripped (nbstripout)
conf/                         # configs (hydra/yaml)
tests/{unit,integration}/
dvc.yaml · params.yaml        # DVC pipeline + tracked params
docs/architecture/            # ADRs (incl. ADR-000)
.github/workflows/ci.yml
pyproject.toml · uv.lock · .env.example · .gitignore · ruff.toml · mypy.ini
```
Baselines: ruff + mypy config; coverage fail_under = 80; pandera schemas for datasets; `nbstripout` installed as a git filter.

## 3. Standard commands
```
install:       uv sync --frozen
dev:           uv run jupyter lab   # or: uv run python -m <pkg>.training
test:          uv run pytest
test:coverage: uv run pytest --cov --cov-fail-under=80
eval:          uv run python -m evals.run --threshold 0.8
lint:          uv run ruff check . && uv run nbqa ruff notebooks/
type-check:    uv run mypy .
build:         uv build
pipeline:      dvc repro          # reproduce data/training pipeline
```

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

---

**Last Updated:** 2026-06-06
