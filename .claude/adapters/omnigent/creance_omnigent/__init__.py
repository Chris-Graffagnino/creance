"""creance_omnigent — the Omnigent adapter's importable glue package.

Omnigent loads adapter code by dotted import path: policy modules via ``policy_modules:``
(a ``POLICY_REGISTRY`` export), function tools by handler path. This package holds the
Creance-specific mechanisms that bind the runtime-neutral `[roles]` (see
``.claude/workflow/README.md`` -> "The binding contract") to Omnigent:

- ``creance_omnigent.policies.guard`` — the `[guard]` / `[edit guard]` rules (T618).
- ``creance_omnigent.registry`` — the ``POLICY_REGISTRY`` Omnigent discovers.

Reviewer sub-agents (T619), the orchestrator config and conformance probes (T620) land in
later sub-tasks. The adapter's only model-naming surface is ``adapters/omnigent/MODELS.md``;
nothing here names a model (tiers are resolved from that table at run time).
"""

__version__ = "0.1.0"
