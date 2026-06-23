"""Omnigent policy modules for the Creance adapter.

``guard`` implements the runtime-neutral `[guard]` / `[edit guard]` rules
(``.claude/workflow/README.md`` -> "The [guard] rules") as deterministic, fail-open
Omnigent policies. See ``creance_omnigent.registry`` for the ``POLICY_REGISTRY`` export
that makes them discoverable via ``policy_modules:``.
"""

from . import guard

__all__ = ["guard"]
