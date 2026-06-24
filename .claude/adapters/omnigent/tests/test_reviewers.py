#!/usr/bin/env python3
"""Deterministic check for the Omnigent cross-vendor read-only [reviewer] sub-agents
(T619, #139; #119 AC3).

Encodes #119 AC3 — the three ``reviewers/*.yaml`` are ``purpose: review`` sub-agents that:
  (1) CROSS-VENDOR  — each ``executor.harness`` resolves to a vendor DIFFERENT from the
      implementer/orchestrator's (``claude-sdk``), via the ``Harness -> vendor`` map in
      ``MODELS.md`` (Omnigent's "review is ALWAYS a different vendor than the implementer"
      rule made STRUCTURAL, not prompt-enforced);
  (2) READ-ONLY     — no file-mutation capability (empty sandbox ``write_paths``, no
      ``os_env`` write/inherit grant, no ``sys_os_*`` OS-capability tool), so each is handed
      only the diff + its contract, never the worktree;
  (3) the constitution reviewer's ``executor.model`` is PINNED to the ``[frontier tier]``
      role, so its ``[strong tier]`` floor is satisfied structurally by rounding up.

The structured fields are read with an INDENTATION-SCOPED parser (``_tree``): ``harness`` and
``model`` are read at the ``executor.*`` path and ``write_paths`` at ``sandbox.*`` — a
top-level decoy ``harness:`` / ``write_paths:`` can NOT mask the real nested field, so the
maker≠checker oracle grades the field it actually claims to (the High craft finding on PR
#141). ``executor.model`` is validated against the DECLARED tier-role set parsed from
``MODELS.md`` (a bogus ``[nonsense tier]`` is rejected, not just any bracketed token), and
the read-only check denies the whole ``sys_os_*`` OS-capability namespace (a new mutation
verb like ``sys_os_delete`` can not slip past a fixed denylist) — the Medium finding. The
precise positive read-only capability allowlist is refined once the live driver pins the tool
taxonomy (T620).

PAIRED, the "machinery proves it is live" discipline shared with ``guard.test.sh`` /
``reviewer-roster.test.sh`` / ``omnigent-neutral-core.test.sh``: the REAL tree PASSES, while
planted violations FAIL — a same-vendor reviewer (and a top-level harness decoy) fails
cross-vendor, a writable reviewer (and a top-level write_paths decoy) fails read-only, an
undeclared tier role and a non-frontier constitution model fail their pins. Every plant
re-runs the SAME production predicate the real tree passes (``is_cross_vendor`` /
``is_read_only`` / ``is_pinned_to_frontier`` / the declared-role set), so no plant merely
re-states its own mutation. Sanity guards forbid a vacuous pass.

Hermetic: stdlib only (no PyYAML, no Omnigent install, no network). The harness->vendor map,
the implementer harness, AND the tier-role set are read FROM ``MODELS.md`` at run time
(self-syncing; no vendor/model vocabulary is hardcoded here, so the ``#119`` AC4 confinement
check stays green and the test follows a one-row MODELS.md edit with no change).

Run directly (the CI ``verify`` step does, via the ``tests/test_*.py`` glob):

    python3 .claude/adapters/omnigent/tests/test_reviewers.py
"""

import os
import re
import subprocess
import unittest

ADAPTER_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REVIEWERS_DIR = os.path.join(ADAPTER_ROOT, "reviewers")
MODELS_MD = os.path.join(ADAPTER_ROOT, "MODELS.md")

# reviewer-file stem -> the runtime-neutral spec it must bind via instructions:.
REVIEWERS = {
    "spec": "spec-auditor",
    "constitution": "constitution-auditor",
    "contract": "contract-auditor",
}
FRONTIER_ROLE = "[frontier tier]"
WRITE_OS_ENV = ("inherit", "write", "rw", "readwrite")
# A read-only reviewer is handed only the diff + its contract, never the worktree, so it must
# hold NO OS-capability tool. Deny the whole ``sys_os_*`` namespace (the documented
# sys_os_edit / sys_os_write / sys_os_shell mutators AND any unverified verb such as
# sys_os_delete) rather than a fixed denylist a new verb could slip past. The precise
# positive read-only allowlist is pinned against the live driver taxonomy at T620.
OS_TOOL_RE = re.compile(r"\bsys_os_\w+\b")


# ── Minimal indentation-scoped YAML reads (the reviewer files are flat block style) ───

def _unquote(v):
    v = v.strip()
    if len(v) >= 2 and v[0] in "\"'" and v[-1] == v[0]:
        return v[1:-1]
    return v


def _decomment(text):
    """The de-commented text (whole-line + inline ``# ...`` comments dropped; field values
    carry no ``#``). Used for the namespace tool scan, so a documentation comment that
    mentions a tool token never trips it."""
    out = []
    for line in text.splitlines():
        line = line.split("#", 1)[0]
        if line.strip():
            out.append(line)
    return "\n".join(out)


def _tree(text):
    """Parse the controlled block-style reviewer YAML into nested dicts of scalar strings.
    Indentation-scoped: each key attaches to the nearest shallower mapping, so a top-level
    DECOY key can NOT mask the real nested ``executor.*`` / ``sandbox.*`` field. Comments and
    blank lines are dropped; block-list items (``- x``) and flow values (``[]`` / ``["."]``)
    are kept as raw scalar strings. Stdlib-only — the reviewer files use no anchors/multiline
    scalars (``TestSanity.test_reviewer_files_parse_structurally`` guards that assumption)."""
    root = {}
    stack = [(-1, root)]  # (indent, mapping-open-at-that-indent)
    for raw in text.splitlines():
        body = raw.split("#", 1)[0]
        if not body.strip():
            continue
        indent = len(body) - len(body.lstrip())
        m = re.match(r"^([^:\s][^:]*?):\s*(.*)$", body.strip())
        if not m:
            continue  # a list item or other non-mapping line — nothing to bind
        key, val = m.group(1).strip(), m.group(2).strip()
        while indent <= stack[-1][0]:
            stack.pop()
        parent = stack[-1][1]
        if val == "":
            child = {}
            parent[key] = child
            stack.append((indent, child))
        else:
            parent[key] = _unquote(val)
    return root


def _at(tree, *path):
    """The scalar at a nested key path, or None (None too if the path lands on a mapping)."""
    node = tree
    for k in path:
        if not isinstance(node, dict):
            return None
        node = node.get(k)
    return None if isinstance(node, dict) else node


def _all_scalars(tree, key):
    """Every scalar bound to ``key`` at ANY depth — used for fail-closed scans (os_env): a
    write grant anywhere trips read-only, so it can not be hidden at an unexpected level."""
    out = []

    def walk(node):
        if isinstance(node, dict):
            for k, v in node.items():
                if k == key and not isinstance(v, dict):
                    out.append(v)
                walk(v)

    walk(tree)
    return out


def purpose_of(text):
    return _at(_tree(text), "purpose")


def harness_of(text):
    return _at(_tree(text), "executor", "harness")


def model_of(text):
    return _at(_tree(text), "executor", "model")


def instructions_of(text):
    return _at(_tree(text), "instructions")


def is_read_only(text):
    """No file-mutation capability: empty ``sandbox.write_paths``, no ``os_env`` write/inherit
    grant (at any level), and no ``sys_os_*`` OS-capability tool. (AC3: handed only the diff +
    its contract, never the worktree.)"""
    tree = _tree(text)
    wp = _at(tree, "sandbox", "write_paths")
    if wp is None or wp.replace(" ", "") != "[]":
        return False
    if any(v.strip().lower() in WRITE_OS_ENV for v in _all_scalars(tree, "os_env")):
        return False
    if OS_TOOL_RE.search(_decomment(text)):
        return False
    return True


def is_cross_vendor(text, vmap, orch_vendor):
    """The reviewer's ``executor.harness`` resolves to a KNOWN vendor that differs from the
    implementer's. An unknown harness is not provably cross-vendor -> False (a FAIL)."""
    v = vmap.get(harness_of(text))
    return v is not None and v != orch_vendor


def is_pinned_to_frontier(text):
    """The constitution reviewer's ``executor.model`` is the ``[frontier tier]`` role (its
    ``[strong]`` floor satisfied by rounding up — #119 AC3). The production predicate that
    BOTH the real-tree assertion and the plant-FAIL re-run, so neither restates a mutation."""
    return model_of(text) == FRONTIER_ROLE


# ── MODELS.md: single source for implementer harness, harness->vendor, tier-role set ──

def _models_text():
    with open(MODELS_MD, encoding="utf-8") as f:
        return f.read()


def implementer_harness(models_text):
    m = re.search(
        r"(?im)^\*\*Implementer / orchestrator harness:\*\*\s*`([^`]+)`", models_text
    )
    return m.group(1) if m else None


def harness_vendor_map(models_text):
    """Parse the ``| Harness | Vendor |`` table into {harness: vendor}. Reads only rows of
    that two-column table (located by its header), so the 4-column cross-vendor reviewer
    table above it is never mistaken for it."""
    mp = {}
    in_table = False
    for line in models_text.splitlines():
        s = line.strip()
        if re.match(r"^\|\s*Harness\s*\|\s*Vendor\s*\|\s*$", s):
            in_table = True
            continue
        if in_table:
            if not s.startswith("|"):
                break
            if set(s) <= set("|-: "):  # the |---|---| delimiter row
                continue
            cells = [c.strip() for c in s.strip("|").split("|")]
            if len(cells) >= 2:
                hm = re.match(r"^`([^`]+)`$", cells[0])
                if hm:
                    mp[hm.group(1)] = cells[1].strip("`").strip()
    return mp


def tier_roles(models_text):
    """The DECLARED tier-role set — the first column of the primary ``| Tier ... | Model | ...``
    table in MODELS.md (the single source). An ``executor.model`` must be one of these roles;
    a bogus ``[nonsense tier]`` is not, so the model check validates membership rather than
    accepting any bracketed token."""
    roles = set()
    in_table = False
    for line in models_text.splitlines():
        s = line.strip()
        if re.match(r"^\|\s*Tier\b.*\|\s*Model\s*\|", s):
            in_table = True
            continue
        if in_table:
            if not s.startswith("|"):
                break
            if set(s) <= set("|-: "):
                continue
            first = s.strip("|").split("|")[0]
            m = re.search(r"\[[^\]]*tier\]", first)
            if m:
                roles.add(m.group(0))
    return roles


def _read(stem):
    with open(os.path.join(REVIEWERS_DIR, "%s.yaml" % stem), encoding="utf-8") as f:
        return f.read()


class ReviewersTestBase(unittest.TestCase):
    def setUp(self):
        self.models = _models_text()
        self.vmap = harness_vendor_map(self.models)
        self.orch_harness = implementer_harness(self.models)
        self.orch_vendor = self.vmap.get(self.orch_harness)
        self.roles = tier_roles(self.models)


# ── Sanity: the check cannot pass vacuously ──────────────────────────────────────────

class TestSanity(ReviewersTestBase):
    def test_harness_vendor_map_nonempty(self):
        self.assertTrue(self.vmap, "Harness -> vendor map is empty (MODELS.md table missing?)")

    def test_implementer_harness_resolves(self):
        self.assertIsNotNone(self.orch_harness, "no 'Implementer / orchestrator harness:' anchor in MODELS.md")
        self.assertIn(self.orch_harness, self.vmap, "implementer harness not in the harness->vendor map")
        self.assertIsNotNone(self.orch_vendor)

    def test_tier_roles_declared(self):
        self.assertIn(FRONTIER_ROLE, self.roles,
                      "MODELS.md declares no [frontier tier] row (tier-role set: %s)" % sorted(self.roles))

    def test_all_three_reviewers_present(self):
        for stem in REVIEWERS:
            p = os.path.join(REVIEWERS_DIR, "%s.yaml" % stem)
            self.assertTrue(os.path.isfile(p), "missing reviewer sub-agent %s" % p)

    def test_reviewer_files_parse_structurally(self):
        # The minimal parser's assumption: each reviewer file is flat block YAML carrying
        # executor:/sandbox: mappings (no flow-style, anchors, or multiline scalars). If a
        # file is reformatted so a nested field stops being reachable, the structured reads
        # would silently return None — catch that HERE with a clear message.
        for stem in REVIEWERS:
            tree = _tree(_read(stem))
            self.assertIsInstance(tree.get("executor"), dict,
                                  "%s.yaml has no executor: mapping (parser assumption broke)" % stem)
            self.assertIsInstance(tree.get("sandbox"), dict,
                                  "%s.yaml has no sandbox: mapping (parser assumption broke)" % stem)


# ── AC3 on the real tree (every reviewer) ────────────────────────────────────────────

class TestRealReviewers(ReviewersTestBase):
    def test_each_is_purpose_review(self):
        for stem in REVIEWERS:
            self.assertEqual(purpose_of(_read(stem)), "review",
                             "%s.yaml is not purpose: review" % stem)

    def test_each_binds_its_neutral_spec(self):
        for stem, spec in REVIEWERS.items():
            instr = instructions_of(_read(stem))
            self.assertIsNotNone(instr, "%s.yaml has no instructions:" % stem)
            self.assertTrue(instr.endswith("%s.md" % spec),
                            "%s.yaml binds %r, expected the %s spec" % (stem, instr, spec))
            resolved = os.path.normpath(os.path.join(REVIEWERS_DIR, instr))
            self.assertTrue(os.path.isfile(resolved),
                            "%s.yaml instructions path does not resolve to a file: %s" % (stem, resolved))

    def test_each_model_is_a_declared_tier_role(self):
        # Defends the confinement invariant at the YAML level AND rejects an undeclared role:
        # the model must be one of MODELS.md's declared tier tokens (the single source), not
        # merely "some bracketed [* tier]" — so a bogus [nonsense tier] does not pass.
        for stem in REVIEWERS:
            model = model_of(_read(stem))
            self.assertIsNotNone(model, "%s.yaml has no executor.model" % stem)
            self.assertIn(model, self.roles,
                          "%s.yaml model %r is not a DECLARED tier role %s (MODELS.md is the single source)"
                          % (stem, model, sorted(self.roles)))

    def test_each_is_cross_vendor(self):
        for stem in REVIEWERS:
            text = _read(stem)
            self.assertIn(harness_of(text), self.vmap,
                          "%s.yaml harness is not in the harness->vendor map" % stem)
            self.assertTrue(is_cross_vendor(text, self.vmap, self.orch_vendor),
                            "%s.yaml resolves to the implementer vendor (%s) — not cross-vendor"
                            % (stem, self.orch_vendor))

    def test_each_is_read_only(self):
        for stem in REVIEWERS:
            self.assertTrue(is_read_only(_read(stem)),
                            "%s.yaml is not read-only (write_paths/os_env/write-tool)" % stem)

    def test_constitution_pinned_to_frontier(self):
        self.assertTrue(is_pinned_to_frontier(_read("constitution")),
                        "constitution.yaml executor.model is not pinned to %s" % FRONTIER_ROLE)


# ── Paired plant-FAILS: each property's violation must be caught (AC6 discipline) ─────

class TestPlantedViolations(ReviewersTestBase):
    def test_same_vendor_reviewer_fails_cross_vendor(self):
        # Repoint a reviewer at the implementer's OWN (nested) harness -> same vendor -> FAIL.
        text = _read("constitution")
        same = re.sub(r"(?m)^(\s+harness:\s*).*$", r"\g<1>%s" % self.orch_harness, text)
        self.assertNotEqual(harness_of(same), harness_of(text), "mutation did not change the harness")
        self.assertFalse(is_cross_vendor(same, self.vmap, self.orch_vendor),
                         "a same-vendor reviewer was NOT caught by the cross-vendor check")

    def test_top_level_harness_decoy_does_not_mask_nested(self):
        # High finding: a flat "first harness: anywhere" parser reads a top-level decoy and
        # wrongly PASSES. Set the REAL nested executor.harness to the implementer's (same
        # vendor) and prepend a cross-vendor top-level decoy — the nested field must win.
        text = _read("constitution")
        same = re.sub(r"(?m)^(\s+harness:\s*).*$", r"\g<1>%s" % self.orch_harness, text)
        cross = next(h for h, v in self.vmap.items() if v != self.orch_vendor)
        decoyed = "harness: %s\n" % cross + same
        self.assertEqual(harness_of(decoyed), self.orch_harness,
                         "nested executor.harness must win over a top-level decoy")
        self.assertFalse(is_cross_vendor(decoyed, self.vmap, self.orch_vendor),
                         "a top-level harness decoy masked a same-vendor nested executor.harness")

    def test_writable_write_paths_fails_read_only(self):
        text = _read("contract")
        self.assertTrue(is_read_only(text))
        writable = re.sub(r"(?m)^(\s+write_paths:\s*).*$", r'\g<1>["."]', text)
        self.assertFalse(is_read_only(writable),
                         "a non-empty write_paths was NOT caught by the read-only check")

    def test_top_level_write_paths_decoy_does_not_mask_nested(self):
        # High finding (read-only side): a top-level decoy empty write_paths must not mask a
        # writable nested sandbox.write_paths.
        text = _read("contract")
        writable = re.sub(r"(?m)^(\s+write_paths:\s*).*$", r'\g<1>["."]', text)
        decoyed = "write_paths: []\n" + writable
        self.assertEqual(_at(_tree(decoyed), "sandbox", "write_paths").replace(" ", ""), '["."]',
                         "nested sandbox.write_paths must win over a top-level decoy")
        self.assertFalse(is_read_only(decoyed),
                         "a top-level write_paths decoy masked a writable nested sandbox")

    def test_os_env_inherit_fails_read_only(self):
        text = _read("spec")
        self.assertTrue(is_read_only(text))
        leaky = text + "\nos_env: inherit\n"
        self.assertFalse(is_read_only(leaky),
                         "an os_env: inherit grant was NOT caught by the read-only check")

    def test_write_tool_fails_read_only(self):
        text = _read("spec")
        self.assertTrue(is_read_only(text))
        leaky = text + "\ntools:\n  - sys_os_edit\n"
        self.assertFalse(is_read_only(leaky),
                         "a granted file-mutation tool was NOT caught by the read-only check")

    def test_unknown_os_tool_fails_read_only(self):
        # Medium finding: a mutation verb OUTSIDE the documented three (e.g. sys_os_delete)
        # must still FAIL read-only — the check denies the whole sys_os_* namespace, so a new
        # verb can not slip past a fixed denylist (positive allowlist refined at T620).
        text = _read("spec")
        self.assertTrue(is_read_only(text))
        leaky = text + "\ntools:\n  - sys_os_delete\n"
        self.assertFalse(is_read_only(leaky),
                         "an unknown sys_os_* mutation tool was treated as read-only")

    def test_undeclared_tier_role_is_rejected(self):
        # Medium finding: the model check validates against the DECLARED set, so a bracketed
        # token that is NOT a real tier ([nonsense tier]) is rejected — a bare r'\[.*tier\]'
        # regex would have accepted it.
        bogus = re.sub(r'(?m)^(\s+model:\s*).*$', r'\g<1>"[nonsense tier]"', _read("contract"))
        self.assertEqual(model_of(bogus), "[nonsense tier]", "mutation did not change the model")
        self.assertNotIn(model_of(bogus), self.roles,
                         "an undeclared tier role was accepted by the declared-set check")

    def test_non_frontier_constitution_fails_pin(self):
        text = _read("constitution")
        downgraded = re.sub(r'(?m)^(\s+model:\s*).*$', r'\g<1>"[cheap tier]"', text)
        self.assertNotEqual(model_of(downgraded), FRONTIER_ROLE, "mutation did not change the model")
        # Re-run the production pin predicate against the mutated input (symmetric with the
        # cross-vendor / read-only plants — not a restatement of the mutation).
        self.assertFalse(is_pinned_to_frontier(downgraded),
                         "a non-frontier constitution reviewer was NOT caught by the pin check")


# ── CI wiring (machinery proves it is live — constitution P2) ─────────────────────────

class TestCIWiring(unittest.TestCase):
    def test_verify_runs_these_tests(self):
        root = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=os.path.dirname(os.path.abspath(__file__)),
            capture_output=True, text=True,
        ).stdout.strip()
        with open(os.path.join(root, ".github", "workflows", "ci.yml"), encoding="utf-8") as f:
            text = f.read()
        # The glob `.claude/adapters/omnigent/tests/test_*.py` runs this file; assert the
        # step still targets that path (the same self-wiring discipline as test_guard.py).
        self.assertIn(".claude/adapters/omnigent/tests/test_", text,
                      "ci.yml verify must RUN the Omnigent adapter tests (this file included)")


if __name__ == "__main__":
    unittest.main(verbosity=2)
