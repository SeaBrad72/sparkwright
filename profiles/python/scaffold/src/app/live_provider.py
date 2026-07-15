"""Reference LIVE flag provider — a file-config FlagProvider that reflects changes
WITHOUT a restart.

This is the reference implementation of the live slot in the ``flags`` seam: it
re-reads a JSON flag file on every resolution, so rewriting the file flips
behaviour in the SAME running process (a live runtime flip, not the env floor's
restart-to-toggle). A SaaS provider (OpenFeature / Unleash / LaunchDarkly) is an
adopter-pluggable alternative implementing the same ``FlagProvider`` — swap it in
via ``set_provider()`` with no change to callers of ``is_enabled()``.

TRUST BOUNDARY: ``path`` is APP-CONFIGURED (an operator-controlled deploy
artifact), NOT end-user input. The file CONTENT is still treated as untrusted (it
can be corrupted/tampered), so resolution is fully fail-safe and injection-safe:

  - fail-safe: a missing / unreadable / unparseable / oversized / deeply-nested
    file, a non-object payload (list/null/scalar), or a flag absent from the file
    all fall back to the registry default (OFF). Resolution never raises and never
    enables on ANY file content: an oversized file is rejected by a byte cap
    (``MAX_FILE_BYTES``) BEFORE it is read (bounding ``MemoryError``), and a
    deeply-nested payload's ``RecursionError`` (a ``RuntimeError``, not an
    ``OSError``/``ValueError``) is caught — a tamperer cannot turn "flip a flag"
    into "crash the resolver" (a DoS of the kill-switch).
  - no injection: ``FORBIDDEN_KEYS`` (``__proto__``/``constructor``/
    ``prototype`` and dunder-ish keys) are rejected outright; the specific flag
    key is read via an ``in``-membership check — the parsed JSON is NEVER
    spread/``dict.update``-d into anything.
  - strict coercion: only the boolean ``True`` enables (a ``"true"`` string, ``1``,
    etc. stay OFF — mirrors the env floor's strict ``== "true"``).

PERFORMANCE CAVEAT: this provider does a SYNCHRONOUS file read on EVERY
``is_enabled`` call. That is fine for a kill-switch and for the shipped default
(the env floor does no FS read at all), but a profile/adopter that wires the file
provider onto a HOT request path should add an mtime-gated cache (stat the file,
re-parse only when it changed) so resolution does not block on I/O.
"""

from __future__ import annotations

import json
import os

from app.flags import FLAGS, FlagName, FlagProvider

# Names that must never be resolved from file data (builtin-shadowing / pollution vectors).
FORBIDDEN_KEYS = frozenset({"__proto__", "constructor", "prototype"})

# Byte cap on the flag file. A flag file is tiny (a handful of booleans); 1 MiB is
# very generous. We stat-and-reject BEFORE reading so an oversized/tampered file
# can never be slurped into memory — this bounds MemoryError (a BaseException the
# handler below deliberately does NOT catch) at the source and keeps the per-call
# kill-switch cheap.
MAX_FILE_BYTES = 1024 * 1024


def _registry_default(name: FlagName) -> bool:
    """Own-key-only, strict-boolean fallback — a non-registry name resolves False."""
    return name in FLAGS and FLAGS[name] is True


def file_config_provider(path: str) -> FlagProvider:
    """Return a provider whose ``is_enabled`` re-reads ``path`` per call (live flip)."""

    class _FileConfigProvider:
        def is_enabled(self, name: FlagName) -> bool:
            fallback = _registry_default(name)
            # Reject dunder-ish / pollution keys outright — never resolved from file data.
            if name in FORBIDDEN_KEYS or (name.startswith("__") and name.endswith("__")):
                return fallback
            try:
                # Byte cap FIRST: reject an oversized/tampered file without reading
                # it, so a huge payload can never be slurped into memory. A stat
                # failure is itself fail-safe (treated like a missing file).
                if os.stat(path).st_size > MAX_FILE_BYTES:
                    return fallback
                # Re-read per call: no cache to go stale, so a rewrite is observed
                # immediately (the live flip). Stdlib-only; small operator-owned config.
                with open(path, encoding="utf-8") as handle:
                    parsed = json.load(handle)
            except (OSError, ValueError, RecursionError):
                # missing / unreadable / unparseable / deeply-nested (RecursionError
                # is a RuntimeError, NOT OSError/ValueError, so it must be named) ->
                # OFF, never raise, never enable. Together with the byte cap above
                # this makes the documented guarantee TRUE for ANY file content:
                # resolution never raises and never enables on error.
                return fallback
            # Only a JSON object can carry flags; arrays/null/scalars fall back.
            if not isinstance(parsed, dict):
                return fallback
            # Read the SPECIFIC key — never spread/update the untrusted object anywhere.
            if name not in parsed:
                return fallback
            # Strict: only boolean True enables (a "true" string, 1, etc. stay OFF).
            return parsed[name] is True

    return _FileConfigProvider()
