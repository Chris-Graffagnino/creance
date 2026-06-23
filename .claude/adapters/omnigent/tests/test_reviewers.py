#!/usr/bin/env python3
"""Deterministic check for the Omnigent cross-vendor read-only [reviewer] sub-agents
(T619, #139; #119 AC3).

Encodes #119 AC3 — the three ``reviewers/*.yaml`` are ``purpose: review`` sub-agents that:
  (1) CROSS-VENDOR  — each ``executor.harness`` resolves to a vendor DIFFERENT from the
      implementer/orchestrator's (``claude-sdk``), via the ``Harness -> vendor`` map in
      ``MODELS.md`` (Omnigent's "review is ALWAYS a different vendor than the implementer"
      rule made STRUCTURAL, not prompt-enforced);
  (2) READ-ONLY     — no file-mutation capability (empty sandbox ``write_paths``, no
      ``os_env`` write/inherit grant, no ``sys_os_edit`` / ``sys_os_write`` /
      ``sys_os_shell`` tool), so each is handed only the diff + its contract, never the
      worktree;
  (3) the constitution reviewer's ``executor.model`` is PINNED to the ``[frontier tier]``
      role, so its ``[strong tier]`` floor is satisfied structurally by rounding up.

PAIRED, the "machinery proves it is live" discipline shared with ``guard.test.sh`` /
``reviewer-roster.test.sh`` / ``omnigent-neutral-core.test.sh``: the REAL tree PASSES, while
a planted SAME-VENDOR reviewer FAILS the cross-vendor assertion, a planted WRITABLE reviewer
FAILS the read-only assertion, and a planted NON-FRONTIER constitution reviewer FAILS the
pin assertion. Sanity guards forbid a vacuous pass.

Hermetic: stdlib only (no PyYAML, no Omnigent install, no network). The harness->vendor map
AND the implementer harness are read FROM ``MODELS.md`` at run time (self-syncing; no vendor
vocabulary is hardcoded here, so the ``#119`` AC4 confinement check stays green and the test
follows a one-row MODELS.md edit with no change). No concrete model id ever appears in this
file (the confinement check scans it).

Run directly (the CI ``verify`` step does, via the ``tests/test_*.py`` glob):

    python3 .claude/adapters/omnigent/tests/test_reviewers.py
"""

import os
import re
import subprocess
import sys
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
WRITE_TOOL_TOKENS = ("sys_os_edit", "sys_os_write", "sys_os_shell")
WRITE_OS_ENV = ("inherit", "write", "rw", "readwrite")


# ── Minimal YAML field reads (the reviewer files are flat + controlled) ───────────────

def _decomment(text):
    """Drop comment lines and inline ``# ...`` comments (field values carry no ``#``), so a
    documentation comment that mentions a banned token never trips a content scan."""
    out = []
    for line in text.splitlines():
        line = line.split("#", 1)[0]
        if line.strip():
            out.append(line)
    return "\n".join(out)


def _scalar(text, key):
    """First ``key: value`` scalar (surrounding quotes stripped), or None. ``text`` is
    expected already de-commented. Keys used here (purpose/harness/model/write_paths/os_env)
    are unique within a reviewer file, so a flat per-key search is unambiguous."""
    m = re.search(r"(?m)^\s*%s:\s*(.+?)\s*$" % re.escape(key), text)
    if not m:
        return None
    v = m.group(1).strip()
    if len(v) >= 2 and v[0] in "\"'" and v[-1] == v[0]:
        v = v[1:-1]
    return v


def purpose_of(text):
    return _scalar(_decomment(text), "purpose")


def harness_of(text):
    return _scalar(_decomment(text), "harness")


def model_of(text):
    return _scalar(_decomment(text), "model")


def instructions_of(text):
    return _scalar(_decomment(text), "instructions")


def is_read_only(text):
    """No file-mutation capability: empty sandbox write_paths, no os_env write/inherit
    grant, and no file-mutation tool. (AC3: handed only diff + contract, never the
    worktree.)"""
    t = _decomment(text)
    wp = _scalar(t, "write_paths")
    if wp is None or wp.replace(" ", "") != "[]":
        return False
    os_env = _scalar(t, "os_env")
    if os_env is not None and os_env.strip().lower() in WRITE_OS_ENV:
        return False
    if any(re.search(r"\b%s\b" % re.escape(tok), t) for tok in WRITE_TOOL_TOKENS):
        return False
    return True


def is_cross_vendor(text, vmap, orch_vendor):
    """The reviewer's harness resolves to a KNOWN vendor that differs from the
    implementer's. An unknown harness is not provably cross-vendor -> False (a FAIL)."""
    v = vmap.get(harness_of(text))
    return v is not None and v != orch_vendor


# ── MODELS.md: the single source for the implementer harness + harness->vendor map ────

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


def _read(stem):
    with open(os.path.join(REVIEWERS_DIR, "%s.yaml" % stem), encoding="utf-8") as f:
        return f.read()


class ReviewersTestBase(unittest.TestCase):
    def setUp(self):
        self.models = _models_text()
        self.vmap = harness_vendor_map(self.models)
        self.orch_harness = implementer_harness(self.models)
        self.orch_vendor = self.vmap.get(self.orch_harness)


# ── Sanity: the check cannot pass vacuously ──────────────────────────────────────────

class TestSanity(ReviewersTestBase):
    def test_harness_vendor_map_nonempty(self):
        self.assertTrue(self.vmap, "Harness -> vendor map is empty (MODELS.md table missing?)")

    def test_implementer_harness_resolves(self):
        self.assertIsNotNone(self.orch_harness, "no 'Implementer / orchestrator harness:' anchor in MODELS.md")
        self.assertIn(self.orch_harness, self.vmap, "implementer harness not in the harness->vendor map")
        self.assertIsNotNone(self.orch_vendor)

    def test_all_three_reviewers_present(self):
        for stem in REVIEWERS:
            p = os.path.join(REVIEWERS_DIR, "%s.yaml" % stem)
            self.assertTrue(os.path.isfile(p), "missing reviewer sub-agent %s" % p)


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

    def test_each_model_is_a_tier_role_not_a_concrete_id(self):
        # Defends the confinement invariant at the YAML level: a concrete model id here would
        # also be caught by omnigent-neutral-core.test.sh, but failing it HERE names the cause.
        for stem in REVIEWERS:
            model = model_of(_read(stem))
            self.assertIsNotNone(model, "%s.yaml has no executor.model" % stem)
            self.assertRegex(model, r"^\[.*tier\]$",
                             "%s.yaml model %r is not a tier role token" % (stem, model))

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
        self.assertEqual(model_of(_read("constitution")), FRONTIER_ROLE,
                         "constitution.yaml executor.model is not pinned to %s" % FRONTIER_ROLE)


# ── Paired plant-FAILS: each property's violation must be caught (AC6 discipline) ─────

class TestPlantedViolations(ReviewersTestBase):
    def test_same_vendor_reviewer_fails_cross_vendor(self):
        # Repoint a reviewer at the implementer's OWN harness -> same vendor -> must FAIL.
        text = _read("constitution")
        same = re.sub(r"(?m)^(\s*harness:\s*).*$", r"\g<1>%s" % self.orch_harness, text)
        self.assertNotEqual(harness_of(same), harness_of(text), "mutation did not change the harness")
        self.assertFalse(is_cross_vendor(same, self.vmap, self.orch_vendor),
                         "a same-vendor reviewer was NOT caught by the cross-vendor check")

    def test_writable_write_paths_fails_read_only(self):
        text = _read("contract")
        self.assertTrue(is_read_only(text))
        writable = re.sub(r"(?m)^(\s*write_paths:\s*).*$", r'\g<1>["."]', text)
        self.assertFalse(is_read_only(writable),
                         "a non-empty write_paths was NOT caught by the read-only check")

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

    def test_non_frontier_constitution_fails_pin(self):
        text = _read("constitution")
        downgraded = re.sub(r'(?m)^(\s*model:\s*).*$', r'\g<1>"[cheap tier]"', text)
        self.assertNotEqual(model_of(downgraded), FRONTIER_ROLE,
                            "mutation did not change the model")
        # The pin assertion is "model == FRONTIER_ROLE"; the mutation must break it.
        self.assertFalse(model_of(downgraded) == FRONTIER_ROLE,
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
