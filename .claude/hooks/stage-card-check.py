#!/usr/bin/env python3
"""Validate indexed stage cards against the frozen pre-split obligation inventory."""

from __future__ import annotations

import argparse
from collections import Counter
import hashlib
from pathlib import Path
import re
import sys


CARD_LINK = re.compile(r"\]\(next-task/([^)/]+\.md)\)")
NEXT_LINK = re.compile(r"^Next: \[[^]]+\]\(([^)/]+\.md)\)$", re.MULTILINE)
BLOCK_START = re.compile(r"^(?:#{1,6} |[-*] |[0-9]+\. |\|)")
SECTION_HEADING = re.compile(r"^##\s+(\d+(?:\.\d+)?)\b", re.MULTILINE)
SECTION_REFERENCE = re.compile(r"§(\d+(?:\.\d+)?)")
OTHER_DOCUMENT = re.compile(r"`[^`\n]*\.[A-Za-z0-9]+`")
SENTENCE_BOUNDARY = re.compile(r"[.!?](?:\s|$)")
REFERENCE_SUFFIXES = {".js", ".md", ".py", ".sh", ".yaml", ".yml"}


def blocks(text: str) -> list[str]:
    """Return logical Markdown obligations with whitespace normalized."""
    found: list[str] = []
    current: list[str] = []

    def flush() -> None:
        if current:
            found.append(" ".join("\n".join(current).split()))
            current.clear()

    for line in text.splitlines():
        if not line.strip():
            flush()
            continue
        if BLOCK_START.match(line) and not (line.startswith("|") and current and current[0].startswith("|")):
            flush()
        current.append(line)
    flush()
    return found


def digest(block: str) -> str:
    return hashlib.sha256(block.encode("utf-8")).hexdigest()


def load_inventory(path: Path) -> list[tuple[str, int, str]]:
    inventory: list[tuple[str, int, str]] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t", 2)
        if len(parts) != 3 or len(parts[0]) != 64 or not parts[1].isdigit():
            raise ValueError(f"{path}:{line_number}: expected <sha256><tab><count><tab><label>")
        inventory.append((parts[0], int(parts[1]), parts[2]))
    if not inventory:
        raise ValueError(f"{path}: obligation inventory is empty")
    return inventory


def validate_index(index: Path, cards_dir: Path) -> tuple[list[str], list[str]]:
    indexed = CARD_LINK.findall(index.read_text(encoding="utf-8"))
    errors: list[str] = []
    duplicate_links = sorted(name for name, count in Counter(indexed).items() if count != 1)
    if duplicate_links:
        errors.append(f"card index repeats: {', '.join(duplicate_links)}")

    present = sorted(path.name for path in cards_dir.glob("*.md"))
    missing = sorted(set(indexed) - set(present))
    unindexed = sorted(set(present) - set(indexed))
    if missing:
        errors.append(f"indexed card missing: {', '.join(missing)}")
    if unindexed:
        errors.append(f"unindexed card: {', '.join(unindexed)}")
    errors.extend(validate_transitions(indexed, cards_dir))
    return indexed, errors


def validate_transitions(indexed: list[str], cards_dir: Path) -> list[str]:
    errors: list[str] = []
    for position, name in enumerate(indexed):
        path = cards_dir / name
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        links = NEXT_LINK.findall(text)
        if position + 1 < len(indexed):
            expected = indexed[position + 1]
            if links != [expected]:
                errors.append(f"{name}: next-card transition must target {expected}, found {links}")
        elif links or "Next: stop." not in text:
            errors.append(f"{name}: final card must contain 'Next: stop.' and no next-card link")
    return errors


def count_card_blocks(indexed: list[str], cards_dir: Path) -> Counter[str]:
    hashes: Counter[str] = Counter()
    for name in indexed:
        path = cards_dir / name
        if path.is_file():
            hashes.update(digest(block) for block in blocks(path.read_text(encoding="utf-8")))
    return hashes


def validate_inventory(
    inventory: list[tuple[str, int, str]], card_hashes: Counter[str]
) -> list[str]:
    errors: list[str] = []
    inventory_hashes = [item[0] for item in inventory]
    repeated = sorted(key for key, count in Counter(inventory_hashes).items() if count != 1)
    if repeated:
        errors.append(f"inventory repeats hash row(s): {', '.join(repeated)}")
    for expected_hash, expected_count, label in inventory:
        actual_count = card_hashes[expected_hash]
        if actual_count != expected_count:
            errors.append(
                f"obligation {label!r}: expected {expected_count} occurrence, found {actual_count}"
            )
    return errors


def validate_references(root: Path, cards_dir: Path) -> list[str]:
    """Reject numeric next-task section references that no stage card defines.

    The association scan is deliberately conservative: ambiguous matches are skipped,
    so punctuation such as abbreviations can produce false negatives.
    """
    sections: set[str] = set()
    for card in cards_dir.glob("*.md"):
        sections.update(SECTION_HEADING.findall(card.read_text(encoding="utf-8")))

    errors: list[str] = []
    for path in sorted(root.rglob("*")):
        if (
            not path.is_file()
            or ".git" in path.parts
            or path.suffix not in REFERENCE_SUFFIXES
        ):
            continue
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except UnicodeDecodeError:
            continue
        paragraphs: list[tuple[int, str]] = []
        paragraph: list[str] = []
        start = 1
        for line_number, line in enumerate([*lines, ""], 1):
            if line.strip():
                if not paragraph:
                    start = line_number
                paragraph.append(line)
                continue
            if paragraph:
                paragraphs.append((start, "\n".join(paragraph)))
                paragraph.clear()

        for paragraph_start, text in paragraphs:
            if "next-task.md" not in text or "stage-card-reference-fixture" in text:
                continue
            for token in SECTION_REFERENCE.finditer(text):
                mention = text.rfind("next-task.md", 0, token.start())
                if mention < 0:
                    continue
                between = text[mention + len("next-task.md") : token.start()]
                if (
                    ";" in between
                    or OTHER_DOCUMENT.search(between)
                    or SENTENCE_BOUNDARY.search(between)
                ):
                    continue
                section = token.group(1)
                if section not in sections:
                    relative = path.relative_to(root)
                    reference_line = paragraph_start + text[: token.start()].count("\n")
                    errors.append(
                        f"{relative}:{reference_line}: unresolved next-task.md §{section}"
                    )
    return errors


def check(root: Path) -> list[str]:
    workflow = root / ".claude" / "workflow"
    index = workflow / "next-task.md"
    cards_dir = workflow / "next-task"
    inventory_path = workflow / "next-task-obligations.tsv"
    for required in (index, cards_dir, inventory_path):
        if not required.exists():
            return [f"missing required stage-card artifact: {required.relative_to(root)}"]

    indexed, errors = validate_index(index, cards_dir)
    errors.extend(validate_references(root, cards_dir))
    card_hashes = count_card_blocks(indexed, cards_dir)

    try:
        inventory = load_inventory(inventory_path)
    except (OSError, ValueError) as error:
        errors.append(str(error))
        return errors

    errors.extend(validate_inventory(inventory, card_hashes))
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path.cwd())
    args = parser.parse_args()
    errors = check(args.root.resolve())
    if errors:
        for error in errors:
            print(f"FAIL: {error}", file=sys.stderr)
        return 1
    print("stage-card completeness: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
