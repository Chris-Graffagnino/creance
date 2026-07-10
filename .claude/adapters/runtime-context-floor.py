#!/usr/bin/env python3
"""Measure a normalized Claude Code runtime-context inventory without emitting it."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

FORMAT = "claude-code-runtime-context/v1"
BASELINE_NAME = "claude-code-fresh-session-runtime-floor"
COUNTER = "tiktoken/o200k_base"
CATEGORIES = ("mcp_servers", "skills", "tools", "deferred_tools", "system_reminders")


class UnrecognizedShape(Exception):
    """The version-dependent runtime inventory no longer matches this adapter."""


def load_inventory(path: Path) -> dict[str, Any]:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise UnrecognizedShape(str(error)) from error
    if not isinstance(document, dict) or document.get("format") != FORMAT:
        raise UnrecognizedShape("unsupported or missing format marker")
    runtime_context = document.get("runtime_context")
    if not isinstance(runtime_context, dict):
        raise UnrecognizedShape("runtime_context must be an object")
    for category in CATEGORIES:
        value = runtime_context.get(category, [])
        if not isinstance(value, list):
            raise UnrecognizedShape(f"{category} must be a list when present")
    tools = runtime_context.get("tools", [])
    if any(not isinstance(tool, dict) for tool in tools):
        raise UnrecognizedShape("tools entries must be objects")
    if any(type(tool.get("deferred")) is not bool for tool in tools):
        raise UnrecognizedShape("every tool deferred marker must be boolean")
    return runtime_context


def token_count(runtime_context: dict[str, Any]) -> int:
    import tiktoken

    encoded = json.dumps(
        runtime_context, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    )
    return len(tiktoken.get_encoding("o200k_base").encode(encoded))


def aggregate(runtime_context: dict[str, Any]) -> dict[str, int]:
    tools = runtime_context.get("tools", [])
    return {
        "mcp_servers": len(runtime_context.get("mcp_servers", [])),
        "enabled_skills": len(runtime_context.get("skills", [])),
        "non_deferred_tools": sum(tool.get("deferred") is False for tool in tools),
        "deferred_tools": len(runtime_context.get("deferred_tools", [])),
        "runtime_tokens": token_count(runtime_context),
    }


def write_baseline(path: Path, counts: dict[str, int], runtime_version: str) -> None:
    baseline: dict[str, Any] = {
        "name": BASELINE_NAME,
        "counter": COUNTER,
        "gating": "none",
        "runtime_floor_tokens": counts["runtime_tokens"],
        "counts": {key: value for key, value in counts.items() if key != "runtime_tokens"},
        "generated_by": ".claude/adapters/runtime-context-floor.py measure",
    }
    if runtime_version:
        baseline["runtime_version"] = runtime_version
    path.write_text(json.dumps(baseline, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def measure(args: argparse.Namespace) -> int:
    try:
        counts = aggregate(load_inventory(args.inventory))
    except (UnrecognizedShape, ImportError, ValueError) as error:
        print(
            f"WARN: unrecognized Claude Code runtime context shape — not measured; "
            f"continuing fail-open ({error}).",
            file=sys.stderr,
        )
        return 0
    print(json.dumps(counts, sort_keys=True, separators=(",", ":")))
    if args.write_baseline:
        write_baseline(args.write_baseline, counts, args.runtime_version)
    return 0


def report(args: argparse.Namespace) -> int:
    baseline = json.loads(args.baseline.read_text(encoding="utf-8"))
    floor = baseline["runtime_floor_tokens"]
    print(f"authored surface = {args.authored_tokens} tokens")
    print(f"runtime floor = {floor} tokens")
    print(f"real resident = {args.authored_tokens + floor} tokens")
    return 0


def parser() -> argparse.ArgumentParser:
    command = argparse.ArgumentParser(description=__doc__)
    subcommands = command.add_subparsers(dest="command", required=True)
    measure_parser = subcommands.add_parser("measure")
    measure_parser.add_argument("inventory", type=Path)
    measure_parser.add_argument("--write-baseline", type=Path)
    measure_parser.add_argument("--runtime-version", default="")
    measure_parser.set_defaults(handler=measure)
    report_parser = subcommands.add_parser("report")
    report_parser.add_argument("--authored-tokens", type=int, required=True)
    report_parser.add_argument("--baseline", type=Path, required=True)
    report_parser.set_defaults(handler=report)
    return command


def main() -> int:
    args = parser().parse_args()
    return args.handler(args)


if __name__ == "__main__":
    raise SystemExit(main())
