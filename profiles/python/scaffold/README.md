# Python profile — starter scaffold

The minimal, brownfield-safe starter copied into a new project at Inception for the
**python** profile of the Sparkwright kit. It is the smallest tree that makes the
profile's shipped CI pipeline (`profiles/python/ci.yml`) go green on an empty repo,
plus a `/healthz` -> 200 surface and its test.

## What's here

```
pyproject.toml        # project "app" (src layout), dev tooling, ruff/mypy/pytest/coverage config
src/app/__init__.py
src/app/health.py     # health() pure fn + stdlib /healthz server (server runs only under __main__)
tests/test_health.py  # asserts health() == {"status": "ok"}
.gitignore
```

The package is importable as `app` (src layout), and coverage is sourced from `app` —
so the single test exercises the package's pure logic well above the 80% gate. The
HTTP server code is guarded under `if __name__ == "__main__":` (and `# pragma: no cover`),
so importing the module for tests binds no port and doesn't drag coverage down.

## One-time lockfile step (required before the first CI run)

The pipeline installs with `uv sync --frozen`, which **requires a committed `uv.lock`**.
This scaffold ships without one (it's generated per-environment). Run once after copying:

```sh
uv lock          # resolves dependency-groups -> writes uv.lock
git add uv.lock
git commit -m "chore: add uv.lock"
```

After that, the standard profile commands apply (`profiles/python.md` §3):

```sh
uv sync --frozen                       # gate-install
uv run ruff check .                    # gate-lint
uv run mypy .                          # gate-type-check
uv run pytest --cov --cov-fail-under=80  # gate-test
uv build                               # gate-build
```

> Note: the shipped `ci.yml` also runs container-image gates (`docker build -t python-app:ci .`).
> Those need a `Dockerfile` (see `profiles/python/Dockerfile`); add it when you containerize.
> This scaffold covers the language-toolchain gates (install/lint/type-check/test/build).

## Verification status

Authored to the python `ci.yml` contract; **not executed here** (uv toolchain absent in the
authoring environment). Verify in an adopter env with:

```sh
uv lock && uv sync && uv run pytest
```
