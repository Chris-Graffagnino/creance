"""``POLICY_REGISTRY`` — how Omnigent discovers the Creance guard policies.

Per ``docs/POLICIES.md``, a module listed under ``policy_modules:`` in the server config
exports ``POLICY_REGISTRY``: a list of policy descriptors, each naming a ``handler`` (a
dotted import path), a ``kind`` (``"factory"`` here — a configured callable), a display
``name`` / ``description``, and a ``params_schema`` (JSON Schema for the factory's params).

Wiring (lands at T620 with the orchestrator ``config.yaml``):

    policy_modules:
      - creance_omnigent.registry

Both policies **fail open** and the model table is resolved at enforcement time, so the
factory params (base branch, model-table path, edit-tool checker map, the UNVERIFIED
dispatch/edit argument keys) are all swappable without touching ``guard.py``.
"""

POLICY_REGISTRY = [
    {
        "handler": "creance_omnigent.policies.guard.make_guard_tool_call",
        "kind": "factory",
        "name": "Creance guard (tool_call)",
        "description": (
            "Deterministic, fail-open tool_call guard: blocks base-branch edits, "
            "bulk staging (git add .), commit/push to the base branch, pushes whose "
            "refspec targets it, a constitution reviewer dispatched below the strong "
            "tier, and self-colliding in-place substitutions "
            "(.claude/workflow/README.md -> 'The [guard] rules')."
        ),
        "params_schema": {
            "type": "object",
            "properties": {
                "base_branch": {"type": "string", "default": "main"},
                "models_file": {
                    "type": "string",
                    "description": "Path to the adapter MODELS.md; default resolves it "
                                   "relative to this package.",
                },
                "dispatch_tools": {
                    "type": "array", "items": {"type": "string"},
                    "description": "Sub-agent dispatch tool names (UNVERIFIED — pin at T620).",
                },
                "reviewer_keys": {"type": "array", "items": {"type": "string"}},
                "reviewer_match": {"type": "string", "default": "constitution"},
                "model_keys": {"type": "array", "items": {"type": "string"}},
                "edit_path_keys": {"type": "array", "items": {"type": "string"}},
            },
            "additionalProperties": False,
        },
    },
    {
        "handler": "creance_omnigent.policies.guard.make_edit_guard",
        "kind": "factory",
        "name": "Creance edit guard (tool_result)",
        "description": (
            "Delta-based fix-forward lint reject: reruns the profile's configured "
            "checker on a touched file and DENYs only when the edit raises diagnostics "
            "above the file's committed baseline. Fails open when no checker maps to the "
            "type. Phase-tolerant — see guard.py PHASE NOTE (tool_result phase UNVERIFIED "
            "upstream; pinned at T620)."
        ),
        "params_schema": {
            "type": "object",
            "properties": {
                "checkers": {
                    "type": "object",
                    "description": "Optional {glob: checker} map; default reads the "
                                   "profile's 'Edit-time checks' map.",
                },
                "edit_path_keys": {"type": "array", "items": {"type": "string"}},
            },
            "additionalProperties": False,
        },
    },
]
