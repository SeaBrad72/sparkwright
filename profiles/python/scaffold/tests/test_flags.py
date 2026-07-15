"""Tests for the feature-flag module + provider seam.

These assert OBSERVED behaviour, not mere presence: the live-flip test rewrites
the SAME file in the SAME process and asserts the transition (presence != proof).
"""

from __future__ import annotations

import json
from collections.abc import Iterator
from pathlib import Path

import pytest

from app.flags import env_name, is_enabled, reset_provider, set_provider
from app.live_provider import file_config_provider

ENV = "FEATURE_NEW_GREETING"


@pytest.fixture(autouse=True)
def _restore_seam() -> Iterator[None]:
    """Always restore the env floor so seam tests can't leak into the others."""
    yield
    reset_provider()


# --- env floor (the FLOOR provider) ---------------------------------------


def test_env_name_derivation() -> None:
    assert env_name("new_greeting") == "FEATURE_NEW_GREETING"


def test_defaults_off_when_env_unset(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv(ENV, raising=False)
    assert is_enabled("new_greeting") is False


def test_on_only_for_exact_true(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv(ENV, "true")
    assert is_enabled("new_greeting") is True


@pytest.mark.parametrize("val", ["1", "TRUE", "yes", "", "false", " true "])
def test_stays_off_for_non_true(monkeypatch: pytest.MonkeyPatch, val: str) -> None:
    monkeypatch.setenv(ENV, val)
    assert is_enabled("new_greeting") is False


@pytest.mark.parametrize("name", ["__class__", "constructor", "__proto__", "toString"])
def test_env_floor_fail_open_by_name(name: str) -> None:
    # A name NOT in the registry (incl. dunder-ish collisions) resolves False, never truthy.
    assert is_enabled(name) is False


# --- provider seam: the live flip (the non-vacuity anchor) ----------------


def test_live_flip_observed(tmp_path: Path) -> None:
    cfg = tmp_path / "flags.json"
    cfg.write_text(json.dumps({"new_greeting": False}))
    set_provider(file_config_provider(str(cfg)))
    before = is_enabled("new_greeting")

    # Rewrite the SAME file — no re-import, no new process, same running module.
    cfg.write_text(json.dumps({"new_greeting": True}))
    after = is_enabled("new_greeting")

    assert before is False
    assert after is True
    assert after != before


def test_fail_safe_missing_file() -> None:
    set_provider(file_config_provider("/no/such/flags-file.json"))
    assert is_enabled("new_greeting") is False


def test_fail_safe_malformed_json(tmp_path: Path) -> None:
    cfg = tmp_path / "flags.json"
    cfg.write_text("not json {{{")
    set_provider(file_config_provider(str(cfg)))
    assert is_enabled("new_greeting") is False


def test_fail_safe_list_payload(tmp_path: Path) -> None:
    cfg = tmp_path / "flags.json"
    cfg.write_text(json.dumps(["new_greeting"]))
    set_provider(file_config_provider(str(cfg)))
    assert is_enabled("new_greeting") is False


def test_fail_safe_absent_key(tmp_path: Path) -> None:
    cfg = tmp_path / "flags.json"
    cfg.write_text(json.dumps({"some_other_flag": True}))
    set_provider(file_config_provider(str(cfg)))
    assert is_enabled("new_greeting") is False


def test_strict_coercion_string_true_stays_off(tmp_path: Path) -> None:
    cfg = tmp_path / "flags.json"
    cfg.write_text(json.dumps({"new_greeting": "true"}))
    set_provider(file_config_provider(str(cfg)))
    assert is_enabled("new_greeting") is False


def test_strict_coercion_int_one_stays_off(tmp_path: Path) -> None:
    cfg = tmp_path / "flags.json"
    cfg.write_text(json.dumps({"new_greeting": 1}))
    set_provider(file_config_provider(str(cfg)))
    assert is_enabled("new_greeting") is False


@pytest.mark.parametrize("name", ["__class__", "constructor", "__proto__", "prototype"])
def test_file_provider_fail_open_by_name(tmp_path: Path, name: str) -> None:
    # Even a crafted file that sets the colliding key to true must resolve False.
    cfg = tmp_path / "flags.json"
    cfg.write_text(json.dumps({name: True, "new_greeting": False}))
    set_provider(file_config_provider(str(cfg)))
    assert is_enabled(name) is False


# --- provider seam: tamper DoS (RecursionError / oversized) regression -----


def test_fail_safe_deeply_nested_json(tmp_path: Path) -> None:
    # A tamperable flag file of deeply-nested JSON makes json.load raise
    # RecursionError (a RuntimeError, not OSError/ValueError). It must resolve
    # fail-safe OFF, never crash the kill-switch (DoS of every flag-gated path).
    cfg = tmp_path / "flags.json"
    depth = 100_000
    cfg.write_text("[" * depth + "]" * depth)  # ~200 KiB, under the byte cap
    set_provider(file_config_provider(str(cfg)))
    assert is_enabled("new_greeting") is False


def test_fail_safe_oversized_file(tmp_path: Path) -> None:
    # A file larger than the byte cap is rejected WITHOUT reading (bounds
    # MemoryError) and resolves fail-safe OFF. The payload is VALID JSON that
    # WOULD enable the flag if read — so this test is load-bearing: it proves
    # the cap short-circuits the read, not merely that a parse error was caught.
    cfg = tmp_path / "flags.json"
    pad = "a" * (2 * 1024 * 1024)  # push past the 1 MiB cap
    cfg.write_text(json.dumps({"new_greeting": True, "pad": pad}))
    set_provider(file_config_provider(str(cfg)))
    assert is_enabled("new_greeting") is False
