#!/usr/bin/env python3
# Generated task index — generator + staleness check (T1205, spec 007 US5; epic #166).
#
# `specs/TASK_INDEX.md` is a GENERATED digest of the selection-critical fields of every
# live backlog task, so /next-task selection reads ~3.5k tokens instead of every
# `specs/*/tasks.md` (~18k today), within a ~4k budget. It is generated, never
# hand-maintained: a summary kept
# by discipline alone is exactly the failure class spec 007 forbids (non-goals; the
# silently-dead-guard class, constitution P2). So this tool is BOTH the generator
# (`--write`) and the deterministic staleness gate (`--check`) — the generated-artifact
# sibling of `compact-packet-drift.sh` (T1203). `--check` regenerates in memory and
# compares to the committed file, FAILing and NAMING the drifted task entry plus the
# repair target (spec 007 US5.AC2, and US6.AC3's diagnostics rule).
#
# Selection-critical fields per task (US5.AC1): task ID, title, model tier, checkbox
# state, owning acceptance-criterion refs, spec path, and issue/PR link when known. The
# index is a SELECTION convenience — the selected task's full context still loads from the
# spec/tasks files (US5.AC3), so the title is a short digest, not the whole description.
#
# Why Python (not a `.sh` like its budget-check sibling): the source parse is genuinely
# parser-shaped — multi-line task blocks, per-file criterion-ownership tables with en-dash
# ranges, UTF-8 title segmentation — and python3 is already a hard `verify` dependency (the
# token counter). It reads only stdlib, is a PURE deterministic function of the tasks files
# (offline: no git, no network), and resolves paths relative to CWD (the same CWD contract
# the other repo checks use; CI runs it from the repo root), so the tests drive it against
# fixture trees by cd-ing in.
#
# Run: python3 .claude/hooks/task-index.py --check   # staleness gate (CI)
#      python3 .claude/hooks/task-index.py --write    # regenerate the committed index
import glob
import os
import re
import sys

TASKS_GLOB = "specs/*/tasks.md"
INDEX_PATH = "specs/TASK_INDEX.md"

# Title cap (characters): keeps the whole index within its US1.AC1 budget (task index
# <= 4k tokens) with growth headroom while leaving titles readable. The token-budget
# check (`.claude/hooks/token-budget-check.sh`, gating `active`) is the standing backstop
# if the backlog outgrows the budget — that is an owner-ratified budget-raise decision,
# never a silent cap change here.
TITLE_CAP = 72

# A task line: `- [ ] T1205 [strong] <description...>` (description wraps onto indented
# continuation lines until the next task / blank / heading).
TASK_RE = re.compile(r"^- \[([ xX])\] (T\d+)\s+\[([A-Za-z]+)\]\s+(.*)$")
CONT_RE = re.compile(r"^\s+\S")
# A criterion-ownership row: `| US5.AC1 | T1205 |` (owner cell may be a range or prose).
OWN_ROW_RE = re.compile(r"^\|\s*(US\d+\.AC\d+)\s*\|\s*(.+?)\s*\|\s*$")
# Trailing `(US5)` story tag on a task's (joined) description.
US_TAG_RE = re.compile(r"\(US(\d+)\)\s*$")
# A rendered index data row: `| T1205 | ... |` — used by --check to key rows by task ID.
INDEX_ROW_RE = re.compile(r"^\|\s*(T\d+)\s*\|")


def parse_tasks_file(path):
    """(list of (id, tier, state, desc), {taskid: set(criteria)}) for one tasks file.

    Pure text parse; `state` is 'x' (done) or ' ' (open); `desc` joins the wrapped
    continuation lines into one line."""
    lines = open(path, encoding="utf-8").read().splitlines()
    tasks = []
    ownership = {}
    in_ownership = False
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        m = TASK_RE.match(line)
        if m:
            flag, tid, tier, rest = m.groups()
            parts = [rest.strip()]
            i += 1
            # Absorb indented continuation lines (stop at a new task, a blank line, or a
            # heading — none of which are an indented continuation).
            while i < n and CONT_RE.match(lines[i]) and not TASK_RE.match(lines[i]):
                parts.append(lines[i].strip())
                i += 1
            desc = " ".join(p for p in parts if p)
            tasks.append((tid, tier, "x" if flag.lower() == "x" else " ", desc))
            continue
        if line.startswith("## Criterion ownership"):
            in_ownership = True
        elif line.startswith("## ") and in_ownership:
            in_ownership = False
        if in_ownership:
            om = OWN_ROW_RE.match(line)
            if om:
                crit, owner_cell = om.groups()
                for owner in expand_owner(owner_cell):
                    ownership.setdefault(owner, set()).add(crit)
        i += 1
    return tasks, ownership


def expand_owner(cell):
    """Owning-task cell -> set of task IDs. Handles a single `T1205`, a comma/`and` list,
    and an inclusive range `T1201-T1206` (hyphen / en-dash / em-dash)."""
    ids = set()
    for start, end in re.findall(r"T(\d+)\s*[-–—]\s*T(\d+)", cell):
        lo, hi = int(start), int(end)
        if lo <= hi and hi - lo < 1000:  # sanity bound: a criterion never spans 1000 tasks
            for k in range(lo, hi + 1):
                ids.add("T%d" % k)
    for tid in re.findall(r"T\d+", cell):
        ids.add(tid)
    return ids


def compress_crits(crits):
    """{'US5.AC1','US5.AC2','US5.AC3'} -> 'US5.AC1-AC3'; multiple stories space-joined and
    ordered by story number then AC number (deterministic)."""
    by_story = {}
    for c in crits:
        story, ac = c.split(".")
        by_story.setdefault(story, []).append(int(ac[2:]))
    out = []
    for story in sorted(by_story, key=lambda s: int(s[2:])):
        nums = sorted(by_story[story])
        runs = []
        run_start = run_prev = nums[0]
        for k in nums[1:]:
            if k == run_prev + 1:
                run_prev = k
            else:
                runs.append((run_start, run_prev))
                run_start = run_prev = k
        runs.append((run_start, run_prev))
        segs = ["AC%d" % a if a == b else "AC%d-AC%d" % (a, b) for a, b in runs]
        out.append(story + "." + ",".join(segs))
    return " ".join(out)


def criteria_field(tid, ownership, desc):
    """The task's owning acceptance-criterion refs: the AC-level entries from the
    criterion-ownership table when present (multi-task stories list them there), else the
    story-level `(US#)` tag the task line carries (single-task stories); empty when the
    tasks file records neither."""
    if ownership.get(tid):
        return compress_crits(ownership[tid])
    m = US_TAG_RE.search(desc)
    return "US%s" % m.group(1) if m else ""


def cell(text):
    """Escape a value for a markdown table cell (a literal pipe would break the row)."""
    return text.replace("|", "\\|").strip()


def short_title(desc):
    """A compact, deterministic title: the description up to its first em-dash or
    semicolon (authors put the gist first), trailing `(US#)` dropped, capped at a word
    boundary. Selection-critical, not the whole task — full context loads later (US5.AC3)."""
    d = re.sub(r"\s*\(US\d+\)\s*$", "", desc).strip()
    cut = len(d)
    for sep in ("—", ";"):  # em-dash, semicolon
        p = d.find(sep)
        if p != -1:
            cut = min(cut, p)
    title = d[:cut].strip()
    if len(title) > TITLE_CAP:
        clipped = title[:TITLE_CAP].rsplit(" ", 1)[0].rstrip(" ,;:.-–—")
        title = (clipped or title[:TITLE_CAP]) + "…"  # ellipsis
    return cell(title)


def spec_path(tasks_path):
    """The spec path beside a tasks file: `specs/NNN-slug/tasks.md` -> `.../spec.md`."""
    return tasks_path[: -len("tasks.md")] + "spec.md"


def build_index():
    """The pure generator: the full `TASK_INDEX.md` text for the CWD's tasks files.
    Sectioned by spec (the spec path is each section's heading — every task's spec path,
    given once per spec rather than repeated per row, which keeps the index within budget).
    Deterministic (sorted files, in-file task order). Fails loud on an empty backlog — an
    empty index would let the staleness gate pass vacuously."""
    files = sorted(glob.glob(TASKS_GLOB))
    sections = []
    total = 0
    for path in files:
        tasks, ownership = parse_tasks_file(path)
        if not tasks:
            continue
        rows = [
            (tid, tier, state, criteria_field(tid, ownership, desc), short_title(desc))
            for tid, tier, state, desc in tasks
        ]
        total += len(rows)
        sections.append((spec_path(path), rows))
    if total == 0:
        raise SystemExit(
            "FAIL: no tasks parsed from %s in %s — refusing to write an empty index "
            "(repair: run from the repo root; check the tasks files exist and match the "
            "`- [ ] T<nnn> [<tier>] ...` line format)" % (TASKS_GLOB, os.getcwd())
        )
    lines = [
        "# Task index — GENERATED; do not edit by hand",
        "",
        "<!-- Generated by .claude/hooks/task-index.py from specs/*/tasks.md (spec 007 US5).",
        "     Regenerate:  python3 .claude/hooks/task-index.py --write",
        "     Staleness gate (CI verify):  python3 .claude/hooks/task-index.py --check",
        "     Selection-critical fields per task; the spec path is each section's heading, and",
        "     the selected task's full context lives in its spec/tasks files (US5.AC3). Issue/PR",
        "     links are created on-demand per task on the tracker, not recorded in the tasks",
        "     files, so that column stays blank until a tasks file carries one (US5.AC1). -->",
    ]
    for sp, rows in sections:
        lines += [
            "",
            "## %s" % sp,
            "",
            "| Task | Tier | State | Criteria | Issue/PR | Title |",
            "|---|---|---|---|---|---|",
        ]
        for tid, tier, state, crits, title in rows:
            lines.append("| %s | %s | [%s] | %s |  | %s |" % (tid, tier, state, crits, title))
    return "\n".join(lines) + "\n"


def index_rows(text):
    """{task ID: full row line} for the data rows of an index text (for --check diagnostics)."""
    out = {}
    for line in text.splitlines():
        m = INDEX_ROW_RE.match(line)
        if m:
            out[m.group(1)] = line
    return out


def cmd_write():
    open(INDEX_PATH, "w", encoding="utf-8").write(build_index())
    print("task index: wrote %s" % INDEX_PATH)
    return 0


def cmd_check():
    expected = build_index()
    try:
        actual = open(INDEX_PATH, encoding="utf-8").read()
    except FileNotFoundError:
        print(
            "FAIL: %s not found in %s — the generated index is missing "
            "(repair: python3 .claude/hooks/task-index.py --write, then commit it)"
            % (INDEX_PATH, os.getcwd()),
            file=sys.stderr,
        )
        return 1
    if actual == expected:
        n = len(index_rows(expected))
        print("task index: OK (%s matches %s across %d task(s))" % (INDEX_PATH, TASKS_GLOB, n))
        return 0

    want = index_rows(expected)
    have = index_rows(actual)
    problems = []
    for tid in sorted(set(have) - set(want), key=_task_key):
        problems.append("stale entry %s: in the index but no longer in the tasks files" % tid)
    for tid in sorted(set(want) - set(have), key=_task_key):
        problems.append("missing entry %s: in the tasks files but absent from the index" % tid)
    for tid in sorted(set(want) & set(have), key=_task_key):
        if want[tid] != have[tid]:
            problems.append(
                "stale entry %s: the index row disagrees with the tasks files\n"
                "        index: %s\n        fresh: %s" % (tid, have[tid], want[tid])
            )
    if not problems:
        # Rows all agree but the text still differs — a header/format/ordering drift.
        problems.append(
            "index header, ordering, or formatting drifted from the generator output"
        )
    print("FAIL: %s is stale relative to %s:" % (INDEX_PATH, TASKS_GLOB), file=sys.stderr)
    for p in problems:
        print("  - %s" % p, file=sys.stderr)
    print(
        "      (repair: python3 .claude/hooks/task-index.py --write, then commit %s)"
        % INDEX_PATH,
        file=sys.stderr,
    )
    return 1


def _task_key(tid):
    return int(tid[1:])


def main(argv):
    mode = argv[1] if len(argv) > 1 else "--check"
    if len(argv) > 2 or mode not in ("--check", "--write"):
        print(
            "usage: python3 .claude/hooks/task-index.py [--check|--write]", file=sys.stderr
        )
        return 2
    return cmd_write() if mode == "--write" else cmd_check()


if __name__ == "__main__":
    sys.exit(main(sys.argv))
