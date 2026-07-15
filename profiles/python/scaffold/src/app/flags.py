"""Feature-flag registry + resolver SEAM — the kit's kill-switch.

A typed, stdlib-only flag module whose default is OFF, so an unset / unknown /
malformed value can never silently enable a feature (fail-safe). This module is a
PROVIDER SEAM (the shape the whole profile fan-out replicates):

  - the FLOOR provider (``env_provider``) is env-driven and restart-to-toggle —
    dark-launch + a real kill-switch, but NOT a live runtime flip;
  - a pluggable live slot (``set_provider``) accepts any ``FlagProvider`` — e.g.
    the reference file-config live provider (``app.live_provider``, flips WITHOUT
    a restart) or an adopter's SaaS provider (OpenFeature/Unleash/LaunchDarkly)
    implementing the same interface.

The public API stays ``is_enabled(name)`` and delegates to whichever provider is
active. Adding a flag = one entry in FLAGS (the single place to enumerate live
flags, so retiring one is a known list, not a code hunt).
"""

from __future__ import annotations

import os
from typing import Protocol

FlagName = str

# The single typed registry — the one place flags are enumerated. Default OFF.
FLAGS: dict[FlagName, bool] = {"new_greeting": False}


def env_name(name: FlagName) -> str:
    """snake_case flag -> SCREAMING_SNAKE env with a FEATURE_ prefix.

    ``new_greeting`` -> ``FEATURE_NEW_GREETING``.
    """
    return f"FEATURE_{name.upper()}"


def _registry_default(name: FlagName) -> bool:
    """Own-key-only, strict-boolean fallback.

    A name that is not a registry key (incl. dunder-ish collisions like
    ``__class__``/``constructor``) must NOT resolve truthy — fail-safe OFF, not
    open. Only a registry key whose stored value is exactly ``True`` enables.
    """
    return name in FLAGS and FLAGS[name] is True


class FlagProvider(Protocol):
    """The seam contract every provider (env floor, file-config, SaaS) implements."""

    def is_enabled(self, name: FlagName) -> bool: ...


class _EnvProvider:
    """The FLOOR provider: env-driven, restart-to-toggle, fail-safe OFF.

    True ONLY when the env var is exactly ``"true"``; otherwise the registry
    default (OFF). ``"TRUE"``/``"1"``/``"yes"`` do NOT enable (strict parse).
    """

    def is_enabled(self, name: FlagName) -> bool:
        raw = os.environ.get(env_name(name))
        if raw is None:
            return _registry_default(name)
        return raw == "true"


env_provider: FlagProvider = _EnvProvider()

# The pluggable seam. Default = the env floor; a live provider is installed by set_provider().
_active_provider: FlagProvider = env_provider


def set_provider(provider: FlagProvider) -> None:
    """Install a live provider into the seam (e.g. the file-config live provider)."""
    global _active_provider
    _active_provider = provider


def reset_provider() -> None:
    """Restore the env floor as the active provider."""
    global _active_provider
    _active_provider = env_provider


def is_enabled(name: FlagName) -> bool:
    """Public API — delegates to the active provider."""
    return _active_provider.is_enabled(name)
