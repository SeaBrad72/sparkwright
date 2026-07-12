"""Tests for the health surface."""

from app.health import health


def test_health_returns_ok() -> None:
    assert health() == {"status": "ok"}
