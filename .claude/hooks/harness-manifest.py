#!/usr/bin/env python3
# Generated harness manifest — generator + staleness check (T637, issue #233).
#
# `.claude/HARNESS.lock.json` is a GENERATED, committed lock artifact compiling the
# harness contract's active facts — profile routing facts, the reviewer roster, the
# review-pass set, the [guard] rules, the edit-time checker map, autonomy opt-in, the
# model-tier table, the adapter role bindings, the constitution's principle set — from
# their existing source-of-truth files, so a human reviewer can inspect the distributed
# contract in one place and CI can verify the snapshot never drifts from the sources.
#
# SOURCE-OF-TRUTH PRECEDENCE (constitution P5 — the manifest observes, never decides):
# the manifest is COMPILED EVIDENCE, NEVER AUTHORITY. On any disagreement the source
# docs win; a mismatch means the lock is stale and CI requires regeneration
# (`python3 .claude/hooks/harness-manifest.py --write`) — never trusting the lock over
# the sources. No gate / tier / guard / selection / autonomy code path may read the
# lock file; `.claude/hooks/harness-manifest-fence.sh` enforces that deterministically
# (the maker-eval-fence.sh pattern).
#
# DETERMINISM (constitution P3): a pure, offline function of the source files — stdlib
# only, no model API, no git, no network, no timestamps, no nondeterministic ordering
# (fixed source list, sorted sets, stable JSON rendering). Two runs on a clean tree are
# byte-identical. Anchored extraction FAILS LOUD when an anchor stops matching (the
# compact-packet-drift.sh posture) — never a silently empty field. Fragile prose is
# content-hashed (`generated_from`, the adapter table hash, the maker-eval declaration)
# rather than mis-parsed. The literal maker-eval channel path is deliberately WITHHELD
# (hash only): the channel token is P5-fenced (`maker-eval-fence.sh`), and this
# generator and its lock stay outside that fence's allowlist by never naming it.
#
# Like task-index.py (the generated-artifact sibling), this tool is BOTH the generator
# (`--write`) and the deterministic staleness gate (`--check`): `--check` regenerates
# in memory, compares per top-level field, and FAILs naming the drifted field(s) plus
# the regeneration command. Resolves paths relative to CWD (the repo-root CWD contract
# the other repo checks use; the tests drive it against fixture trees by cd-ing in).
#
# Run: python3 .claude/hooks/harness-manifest.py --check   # staleness gate (CI verify)
#      python3 .claude/hooks/harness-manifest.py --write   # regenerate the lock file
import hashlib
import json
import re
import sys

LOCK_PATH = ".claude/HARNESS.lock.json"
REGEN = "python3 .claude/hooks/harness-manifest.py --write"

PROFILE = ".claude/PROJECT.md"
MODELS = ".claude/MODELS.md"
ADAPTER = ".claude/README.md"
WORKFLOW = ".claude/workflow/README.md"
GATE_LOOP = ".claude/workflow/gate-loop.md"
CONSTITUTION = "memory/constitution.md"
SOURCES = (PROFILE, MODELS, ADAPTER, WORKFLOW, GATE_LOOP, CONSTITUTION)


def die(field, source, detail):
    raise SystemExit(
        "FAIL: could not extract '%s' from %s — %s (the extraction anchor no longer "
        "matches; fix the anchor here or the source line — the source is the "
        "authority, never this manifest)" % (field, source, detail)
    )


def read(path):
    try:
        return open(path, encoding="utf-8").read()
    except OSError as e:
        raise SystemExit(
            "FAIL: cannot read source %s (%s) — run from the repo root; every "
            "manifest source must exist" % (path, e)
        )


def sha256(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def section(text, prefix):
    """The lines under the first heading line starting with `prefix`, up to (not
    including) the next heading — the compact-packet-drift.sh `section` semantics."""
    out, inblk = [], False
    for line in text.splitlines():
        if inblk and line.startswith("#"):
            break
        if inblk:
            out.append(line)
        elif line.startswith(prefix):
            inblk = True
    return "\n".join(out)


def tokens(text):
    """Every `backticked` token, in order, backticks stripped."""
    return re.findall(r"`([^`]*)`", text)


def squeeze(text):
    return re.sub(r"\s+", " ", text).strip()


# --- profile (PROJECT.md) ------------------------------------------------------


def scalar(text, pattern, field):
    m = re.search(pattern, text, re.M)
    if not m:
        die(field, PROFILE, "no line matches %r" % pattern)
    return m.group(1).strip()


def profile_paths(paths_sec):
    spec_paths = sorted(
        t for t in tokens(paths_sec) if re.match(r"^specs/[0-9][0-9a-z-]*/spec\.md$", t)
    )
    tasks_paths = sorted(
        t for t in tokens(paths_sec) if re.match(r"^specs/[0-9][0-9a-z-]*/tasks\.md$", t)
    )
    if not spec_paths or not tasks_paths:
        die("spec-paths/tasks-paths", PROFILE, "no specs/*/spec.md or specs/*/tasks.md tokens under '## Paths'")
    return spec_paths, tasks_paths


def paths_bullet(paths_sec, bullet_prefix, field):
    """One '- **<name>:**' bullet's full text (with its indented continuations)."""
    out, inb = [], False
    for line in paths_sec.splitlines():
        if inb and (line.startswith("- ") or not line.strip()):
            break
        if inb:
            out.append(line)
        elif line.startswith(bullet_prefix):
            inb = True
            out.append(line)
    if not out:
        die(field, PROFILE, "no bullet starts with %r under '## Paths'" % bullet_prefix)
    return "\n".join(out)


def parse_profile(text):
    paths_sec = section(text, "## Paths")
    conv_sec = section(text, "## Task & branch conventions")
    spec_paths, tasks_paths = profile_paths(paths_sec)

    con_line = next((l for l in paths_sec.splitlines() if "Constitution" in l), "")
    con_toks = tokens(con_line)
    if not con_toks:
        die("constitution-path", PROFILE, "no backticked token on the Constitution bullet")

    idx = [t for t in tokens(paths_sec) if re.match(r"^specs/TASK_INDEX\.md$", t)]
    tel = [t for t in tokens(paths_sec) if t.endswith("telemetry.jsonl")]
    if not idx or not tel:
        die("task-index/telemetry path", PROFILE, "missing the TASK_INDEX.md or *telemetry.jsonl token under '## Paths'")

    titles = sorted(t for t in tokens(conv_sec) if t.startswith("<type>: "))
    branches = sorted(t for t in tokens(conv_sec) if t.startswith("<type>/"))
    tid = re.search(r"`T` \+ [0-9].*?[0-9] digits", conv_sec)
    tiers = sorted(
        {t for t in tokens(conv_sec) if re.match(r"^\[(frontier|strong|cheap)\]$", t)}
    )
    lifecycle = sorted(
        (["create-on-demand"] if "create-on-demand" in conv_sec else [])
        + [t for t in tokens(conv_sec) if t == "Closes #<n>"]
    )
    if not titles or not branches or not tid or not tiers or len(lifecycle) != 2:
        die("conventions", PROFILE, "title/branch/task-id/tier-tag/lifecycle anchors under '## Task & branch conventions' incomplete")

    check_line = next(
        (l for l in text.splitlines() if l.startswith("- **Required check:**")), ""
    )
    check_toks = tokens(check_line)
    if not check_toks:
        die("required-check", PROFILE, "no backticked token on the Required-check bullet")

    return {
        "base_branch": scalar(text, r"^- \*\*Base branch:\*\* *(\S+)", "base-branch"),
        "required_check": check_toks[0],
        "merge_gate": scalar(text, r"^- \*\*Merge-gate ruleset:\*\* *([A-Za-z]+)", "merge-gate"),
        "repo_model": scalar(text, r"^- \*\*Repo model:\*\* *([A-Za-z]+)", "repo-model"),
        "constitution_path": con_toks[0],
        "spec_paths": spec_paths,
        "tasks_paths": tasks_paths,
        "task_index_path": idx[0],
        "conventions": {
            "titles": titles,
            "branch": branches,
            "task_id_format": tid.group(0),
            "tier_tags": tiers,
            "issue_lifecycle": lifecycle,
        },
    }


def parse_review_passes(text):
    rows = []
    for line in section(text, "## Review passes").splitlines():
        if not line.startswith("| `"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 4:
            die("review-passes", PROFILE, "a data row has fewer than 4 cells: %r" % line)
        toks = tokens(cells[0])
        if not toks:
            die("review-passes", PROFILE, "a data row's role cell has no backticked token: %r" % line)
        rows.append(
            {"role": toks[0], "enabled": cells[1], "condition": cells[2], "applies_to": cells[3]}
        )
    if not rows:
        die("review-passes", PROFILE, "no data rows under '## Review passes'")
    return rows


def parse_edit_time_checks(text):
    rows = []
    for line in section(text, "## Edit-time checks").splitlines():
        if not line.startswith("- `"):
            continue
        toks = tokens(line)
        if len(toks) < 2:
            die("edit-time-checks", PROFILE, "a map row carries fewer than 2 backticked tokens: %r" % line)
        rows.append({"glob": toks[0], "checker": toks[1]})
    if not rows:
        die("edit-time-checks", PROFILE, "no '- `<glob>` → `<checker>`' rows under '## Edit-time checks'")
    return rows


def parse_autonomy(text):
    """The autonomy-mode.sh code-span grammar: comment lines dropped, exactly one
    genuine `autonomy-opt-in: <value>` declaration expected — ambiguity fails loud
    here exactly as the activation check fails closed."""
    declarations = []
    for line in text.splitlines():
        if re.match(r"^\s*#", line) or "<!--" in line:
            continue
        declarations += re.findall(r"`autonomy-opt-in:\s*([A-Za-z]+)`", line)
    if len(declarations) != 1:
        die(
            "autonomy-opt-in",
            PROFILE,
            "%d code-span declarations (exactly 1 expected; the activation check would fail closed)"
            % len(declarations),
        )
    return {"opt_in": declarations[0], "source": PROFILE + " § Autonomy"}


# --- reviewer roster (workflow/gate-loop.md) ------------------------------------


def parse_roster(text):
    rows = []
    for line in section(text, "## The reviewer roster").splitlines():
        if not line.startswith("| `"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 3:
            die("reviewer-roster", GATE_LOOP, "a roster row has fewer than 3 cells: %r" % line)
        spec_toks = tokens(cells[0])
        cond_toks = tokens(cells[2])
        if not spec_toks or not cond_toks:
            die("reviewer-roster", GATE_LOOP, "a roster row lacks its backticked spec or condition token: %r" % line)
        label = re.search(r"\(([^)]*)\)\s*$", cells[0])
        rows.append(
            {
                "spec": spec_toks[0],
                "label": label.group(1) if label else "",
                "tier": cells[1],
                "dispatch_condition": cond_toks[0],
            }
        )
    if not rows:
        die("reviewer-roster", GATE_LOOP, "no data rows under '## The reviewer roster'")
    return rows


# --- guard rules (workflow/README.md) -------------------------------------------


def parse_guard_rules(text):
    sec = section(text, "### The [guard] rules")
    if not sec.strip():
        die("guard-rules", WORKFLOW, "no '### The [guard] rules' section")
    rules, current = [], None
    for line in sec.splitlines():
        m = re.match(r"^(\d+)\.\s+(.*)$", line)
        if m:
            if current:
                rules.append(current)
            current = {"n": int(m.group(1)), "text": m.group(2)}
        elif current is not None and re.match(r"^\s+\S", line):
            current["text"] += " " + line.strip()
        elif current is not None:
            rules.append(current)
            current = None
    if current:
        rules.append(current)
    if not rules:
        die("guard-rules", WORKFLOW, "no numbered rules under '### The [guard] rules'")
    return {
        "source": WORKFLOW + " § The [guard] rules",
        "count": len(rules),
        "fails_open": "It **fails open**" in sec,
        "rules": [{"n": r["n"], "text": squeeze(r["text"])} for r in rules],
        "section_sha256": sha256(sec),
    }


# --- model tiers (MODELS.md) -----------------------------------------------------


def parse_model_tiers(text):
    tiers, judge = [], None
    for line in text.splitlines():
        m = re.match(r"^\| \*\*\[(frontier|strong|cheap) tier\]\*\*", line)
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if m and len(cells) >= 3:
            tiers.append(
                {"tier": m.group(1), "models": tokens(cells[1]), "effort": cells[2]}
            )
        elif line.startswith("| **maker-eval judge**") and len(cells) >= 3:
            judge = {"models": tokens(cells[1]), "effort": cells[2]}
    if len(tiers) != 3 or any(not t["models"] for t in tiers):
        die("model-tiers", MODELS, "expected exactly 3 tier rows each carrying a backticked model")
    if judge is None or not judge["models"]:
        die("pinned-judge", MODELS, "no '| **maker-eval judge** …' row carrying a backticked model")
    return {"source": MODELS, "tiers": tiers, "pinned_judge": judge}


# --- adapter bindings (.claude/README.md) ----------------------------------------


def parse_adapter_bindings(text):
    sec = section(text, "## The shipped adapter")
    rows = [l for l in sec.splitlines() if l.startswith("| **[")]
    roles = []
    for line in rows:
        m = re.search(r"\[([^\]]+)\]", line)
        if not m:
            die("adapter-bindings", ADAPTER, "a mapping row carries no [role] token: %r" % line[:60])
        roles.append("[%s]" % m.group(1))
    if not roles:
        die("adapter-bindings", ADAPTER, "no '| **[role]** | …' rows under '## The shipped adapter'")
    return {
        "source": ADAPTER + " § The shipped adapter: Claude Code",
        "roles": roles,
        "table_sha256": sha256("\n".join(rows)),
    }


# --- constitution ----------------------------------------------------------------


def parse_constitution(text, path):
    principles = re.findall(r"^### (\d+\. .+?)\s*$", text, re.M)
    if not principles:
        die("constitution-principles", path, "no '### <n>. <title>' principle headings")
    return {"path": path, "principles": principles, "sha256": sha256(text)}


# --- assembly ---------------------------------------------------------------------


def build_manifest():
    texts = {p: read(p) for p in SOURCES}
    profile_text = texts[PROFILE]
    paths_sec = section(profile_text, "## Paths")
    telemetry = [t for t in tokens(paths_sec) if t.endswith("telemetry.jsonl")][0:1]
    maker_eval_decl = paths_bullet(paths_sec, "- **Maker-eval records:**", "maker-eval-declaration")
    return {
        "schema_version": 1,
        "authority": (
            "GENERATED by .claude/hooks/harness-manifest.py — compiled evidence, never "
            "authority (constitution P5). On any disagreement the source docs win: a "
            "mismatch means this lock is stale and CI requires regeneration (" + REGEN + "), "
            "never trusting this file over the sources. No gate/tier/guard/selection/"
            "autonomy path may read this file (deterministic fence: "
            ".claude/hooks/harness-manifest-fence.sh)."
        ),
        "generated_from": {p: "sha256:" + sha256(texts[p]) for p in sorted(SOURCES)},
        "profile": parse_profile(profile_text),
        "constitution": parse_constitution(texts[CONSTITUTION], CONSTITUTION),
        "reviewer_roster": parse_roster(texts[GATE_LOOP]),
        "review_passes": parse_review_passes(profile_text),
        "guard_rules": parse_guard_rules(texts[WORKFLOW]),
        "edit_time_checks": parse_edit_time_checks(profile_text),
        "autonomy": parse_autonomy(profile_text),
        "model_tiers": parse_model_tiers(texts[MODELS]),
        "adapter_bindings": parse_adapter_bindings(texts[ADAPTER]),
        "observe_only_channels": {
            "telemetry": {"path": telemetry[0] if telemetry else ""},
            "maker_eval": {
                "declaration_sha256": sha256(maker_eval_decl),
                "note": (
                    "literal channel path deliberately withheld — the channel token is "
                    "P5-fenced (maker-eval-fence.sh); read " + PROFILE + " § Paths → "
                    "'Maker-eval records' (the source of truth) for the declaration"
                ),
            },
        },
    }


def render(manifest):
    return json.dumps(manifest, indent=2, ensure_ascii=False) + "\n"


def diff_fields(expected, actual):
    """The drifted TOP-LEVEL fields between two manifest objects, each with a short
    sub-detail where the field is a dict — the per-surface diagnostics the planted-drift
    tests assert on (a drifted roster names 'reviewer_roster', never a generic hash)."""
    problems = []
    keys = sorted(set(expected) | set(actual))
    for k in keys:
        e, a = expected.get(k), actual.get(k)
        if e == a:
            continue
        detail = ""
        if isinstance(e, dict) and isinstance(a, dict):
            sub = sorted(
                set(sk for sk in set(e) | set(a) if e.get(sk) != a.get(sk))
            )
            detail = " (drifted: %s)" % ", ".join(sub)
        problems.append("field '%s' drifted from its source%s" % (k, detail))
    return problems


def cmd_write():
    open(LOCK_PATH, "w", encoding="utf-8").write(render(build_manifest()))
    print("harness manifest: wrote %s" % LOCK_PATH)
    return 0


def cmd_check():
    expected_text = render(build_manifest())
    try:
        actual_text = open(LOCK_PATH, encoding="utf-8").read()
    except FileNotFoundError:
        print(
            "FAIL: %s not found — the committed harness manifest is missing\n"
            "      (repair: %s, then commit %s)" % (LOCK_PATH, REGEN, LOCK_PATH),
            file=sys.stderr,
        )
        return 1
    if actual_text == expected_text:
        print("harness manifest: OK (%s matches its sources)" % LOCK_PATH)
        return 0
    try:
        actual = json.loads(actual_text)
    except ValueError:
        actual = {}
    problems = diff_fields(json.loads(expected_text), actual) or [
        "formatting/ordering drifted from the generator output"
    ]
    print(
        "FAIL: %s is stale relative to its source-of-truth docs (the sources win):"
        % LOCK_PATH,
        file=sys.stderr,
    )
    for p in problems:
        print("  - %s" % p, file=sys.stderr)
    print("      (repair: %s, then commit %s)" % (REGEN, LOCK_PATH), file=sys.stderr)
    return 1


def main(argv):
    mode = argv[1] if len(argv) > 1 else "--check"
    if len(argv) > 2 or mode not in ("--check", "--write"):
        print("usage: python3 .claude/hooks/harness-manifest.py [--check|--write]", file=sys.stderr)
        return 2
    return cmd_write() if mode == "--write" else cmd_check()


if __name__ == "__main__":
    sys.exit(main(sys.argv))
