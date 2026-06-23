#!/usr/bin/env python3
"""Unit tests for the Omnigent [guard] / [edit guard] policy port (T618, #136).

Encodes #119 AC2: the guard rules normatively listed in
``.claude/workflow/README.md`` -> "The [guard] rules" are deterministic, **fail-open**
``tool_call`` / ``tool_result`` policies; bulk staging (``git add .`` / ``-A``),
commit/push-to-base, and base-branch edits return DENY; a passing control (explicit-file
staging ALLOWED) plus adversarial variants (not the literal banned strings); and any
internal exception fails OPEN.

Run directly (the CI ``verify`` step does, via a fail-closed glob):

    python3 .claude/adapters/omnigent/tests/test_guard.py

Hermetic: stdlib + ``git`` only; no Omnigent install, no network. Rule-5 model fixtures
use synthetic model ids so no real model vocabulary lands in the adapter subtree (the
T617 neutral-core confinement check stays green).
"""

import os
import subprocess
import sys
import tempfile
import unittest

# Make `creance_omnigent` importable without an install: the adapter root is this file's
# grandparent (.../adapters/omnigent/tests/ -> .../adapters/omnigent/).
ADAPTER_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ADAPTER_ROOT)

from creance_omnigent.policies import guard  # noqa: E402


def _git(args, cwd):
    subprocess.run(["git", *args], cwd=cwd, check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _make_repo(base="main"):
    """A throwaway git repo on branch ``base`` with one committed file. Returns its path."""
    d = tempfile.mkdtemp(prefix="omni-guard-test-")
    _git(["init", "-q"], d)
    _git(["checkout", "-q", "-b", base], d)
    _git(["config", "user.email", "t@example.com"], d)
    _git(["config", "user.name", "Test"], d)
    with open(os.path.join(d, "seed.txt"), "w") as f:
        f.write("seed\n")
    _git(["add", "seed.txt"], d)
    _git(["commit", "-q", "-m", "seed"], d)
    return d


def _event(target, command=None, path=None, cwd=None, args=None, type_="tool_call"):
    a = dict(args or {})
    if command is not None:
        a["command"] = command
    if path is not None:
        a["path"] = path
    ev = {"type": type_, "target": target, "data": {"name": target, "arguments": a}}
    if cwd is not None:
        ev["context"] = {"cwd": cwd}
    return ev


class GuardTestBase(unittest.TestCase):
    def setUp(self):
        self._dirs = []

    def tearDown(self):
        import shutil
        for d in self._dirs:
            shutil.rmtree(d, ignore_errors=True)

    def repo(self, base="main"):
        d = _make_repo(base)
        self._dirs.append(d)
        return d

    def tmpdir(self):
        d = tempfile.mkdtemp(prefix="omni-guard-test-")
        self._dirs.append(d)
        return d

    def assertDeny(self, resp, rule_substr=None):
        self.assertIsInstance(resp, dict, "expected a DENY response, got %r" % (resp,))
        self.assertEqual(resp.get("result"), guard.DENY)
        self.assertIn("reason", resp)
        if rule_substr:
            self.assertIn(rule_substr, resp["reason"])

    def assertAllow(self, resp):
        # The guard DENYs or abstains (None); abstaining IS "allowed".
        self.assertIsNone(resp, "expected abstain/allow (None), got %r" % (resp,))


# ── Rule 2 — bulk staging ────────────────────────────────────────────────────────────

class TestBulkStaging(GuardTestBase):
    def setUp(self):
        super().setUp()
        self.pol = guard.make_guard_tool_call(base_branch="main")
        self.cwd = self.repo("feature/x")  # branch is irrelevant to rule 2

    def test_add_dot_denied(self):
        self.assertDeny(self.pol(_event("sys_os_shell", "git add .", cwd=self.cwd)),
                        "git-add-all")

    def test_add_A_denied(self):
        self.assertDeny(self.pol(_event("sys_os_shell", "git add -A", cwd=self.cwd)))

    def test_add_all_denied(self):
        self.assertDeny(self.pol(_event("sys_os_shell", "git add --all", cwd=self.cwd)))

    def test_adversarial_extra_spacing(self):
        self.assertDeny(self.pol(_event("sys_os_shell", "git   add    .", cwd=self.cwd)))

    def test_adversarial_compound_command(self):
        self.assertDeny(self.pol(
            _event("sys_os_shell", "cd sub && git add . && echo done", cwd=self.cwd)))

    def test_control_explicit_path_allowed(self):
        self.assertAllow(self.pol(
            _event("sys_os_shell", "git add path/to/file.py", cwd=self.cwd)))

    def test_control_multiple_explicit_paths_allowed(self):
        self.assertAllow(self.pol(
            _event("sys_os_shell", "git add a.txt b.txt", cwd=self.cwd)))

    def test_control_unrelated_command_allowed(self):
        self.assertAllow(self.pol(_event("sys_os_shell", "git status", cwd=self.cwd)))

    def test_default_factory_also_denies(self):
        # The module-level default-configured callable is wired the same.
        self.assertDeny(guard.guard_tool_call(_event("sys_os_shell", "git add .", cwd=self.cwd)))


# ── Rule 3 — commit / push on the base branch ────────────────────────────────────────

class TestCommitPushOnBase(GuardTestBase):
    def setUp(self):
        super().setUp()
        self.pol = guard.make_guard_tool_call(base_branch="main")

    def test_commit_on_base_denied(self):
        cwd = self.repo("main")
        self.assertDeny(self.pol(_event("sys_os_shell", "git commit -m x", cwd=cwd)),
                        "commit-push-on-base")

    def test_push_on_base_denied(self):
        cwd = self.repo("main")
        self.assertDeny(self.pol(_event("sys_os_shell", "git push", cwd=cwd)))

    def test_commit_on_feature_allowed(self):
        cwd = self.repo("feature/x")
        self.assertAllow(self.pol(_event("sys_os_shell", "git commit -m x", cwd=cwd)))

    def test_push_on_feature_allowed(self):
        cwd = self.repo("feature/x")
        self.assertAllow(self.pol(_event("sys_os_shell", "git push origin feature/x", cwd=cwd)))


# ── Rule 4 — push whose refspec targets the base branch (any current branch) ──────────

class TestPushRefspecBase(GuardTestBase):
    def setUp(self):
        super().setUp()
        self.pol = guard.make_guard_tool_call(base_branch="main")
        self.cwd = self.repo("feature/x")  # NOT on base — rule 4 is branch-independent

    def test_head_colon_main_denied(self):
        self.assertDeny(self.pol(
            _event("sys_os_shell", "git push origin HEAD:main", cwd=self.cwd)),
            "push-refspec-base")

    def test_delete_main_denied(self):
        self.assertDeny(self.pol(
            _event("sys_os_shell", "git push origin :main", cwd=self.cwd)))

    def test_plain_main_destination_denied(self):
        self.assertDeny(self.pol(
            _event("sys_os_shell", "git push origin main", cwd=self.cwd)))

    def test_refs_heads_main_denied(self):
        self.assertDeny(self.pol(
            _event("sys_os_shell", "git push origin HEAD:refs/heads/main", cwd=self.cwd)))

    def test_control_push_feature_allowed(self):
        self.assertAllow(self.pol(
            _event("sys_os_shell", "git push origin HEAD:feature/x", cwd=self.cwd)))

    def test_control_push_main_lookalike_allowed(self):
        # 'maintenance' must not match 'main'.
        self.assertAllow(self.pol(
            _event("sys_os_shell", "git push origin HEAD:maintenance", cwd=self.cwd)))


# ── Rule 1 — file edit while on the base branch ──────────────────────────────────────

class TestEditOnBase(GuardTestBase):
    def setUp(self):
        super().setUp()
        self.pol = guard.make_guard_tool_call(base_branch="main")

    def test_edit_in_repo_on_base_denied(self):
        cwd = self.repo("main")
        p = os.path.join(cwd, "seed.txt")
        self.assertDeny(self.pol(_event("sys_os_edit", path=p, cwd=cwd)), "edit-on-base")

    def test_write_in_repo_on_base_denied(self):
        cwd = self.repo("main")
        p = os.path.join(cwd, "new.txt")
        self.assertDeny(self.pol(_event("sys_os_write", path=p, cwd=cwd)))

    def test_edit_in_repo_on_feature_allowed(self):
        cwd = self.repo("feature/x")
        p = os.path.join(cwd, "seed.txt")
        self.assertAllow(self.pol(_event("sys_os_edit", path=p, cwd=cwd)))

    def test_edit_out_of_repo_on_base_allowed(self):
        cwd = self.repo("main")
        outside = os.path.join(self.tmpdir(), "inbox.md")  # a different temp dir
        self.assertAllow(self.pol(_event("sys_os_edit", path=outside, cwd=cwd)))


# ── Rule 5 — constitution reviewer below the strong tier ─────────────────────────────

class TestConstitutionFloor(GuardTestBase):
    def setUp(self):
        super().setUp()
        # Synthetic MODELS.md — fake ids (hyphen+digit so they're extracted; the harness
        # token has no digit, mirroring claude-sdk). No real model vocabulary here.
        d = self.tmpdir()
        self.models = os.path.join(d, "MODELS.md")
        with open(self.models, "w") as f:
            f.write(
                "| Tier | Model | Harness | Effort |\n"
                "|---|---|---|---|\n"
                "| **[frontier tier]** | `frontier-9-9` | `some-harness` | high |\n"
                "| **[strong tier]** | `strong-7-7` | `some-harness` | — |\n"
                "| **[cheap tier]** | `cheap-3-3` | `some-harness` | — |\n"
            )
        self.pol = guard.make_guard_tool_call(models_file=self.models)

    def _dispatch(self, model=None, reviewer="constitution-auditor"):
        args = {"subagent": reviewer}
        if model is not None:
            args["model"] = model
        return _event("sys_session_send", args=args)

    def test_absent_model_denied(self):
        self.assertDeny(self.pol(self._dispatch(model=None)), "strong-floor-no-model")

    def test_below_strong_denied(self):
        self.assertDeny(self.pol(self._dispatch(model="cheap-3-3")), "strong-floor-below")

    def test_strong_allowed(self):
        self.assertAllow(self.pol(self._dispatch(model="strong-7-7")))

    def test_frontier_allowed(self):
        self.assertAllow(self.pol(self._dispatch(model="frontier-9-9")))

    def test_unrankable_model_fails_open(self):
        self.assertAllow(self.pol(self._dispatch(model="mystery-1-0")))

    def test_non_constitution_dispatch_ignored(self):
        self.assertAllow(self.pol(self._dispatch(model="cheap-3-3", reviewer="spec-auditor")))

    def test_model_in_nested_executor(self):
        ev = _event("sys_session_send",
                    args={"subagent": "constitution-auditor", "executor": {"model": "cheap-3-3"}})
        self.assertDeny(self.pol(ev), "strong-floor-below")


# ── Rule 6 — self-colliding in-place substitution ────────────────────────────────────

class TestSedCollision(GuardTestBase):
    def setUp(self):
        super().setUp()
        self.pol = guard.make_guard_tool_call(base_branch="main")
        self.cwd = self.repo("feature/x")

    def _sh(self, command):
        return self.pol(_event("sys_os_shell", command, cwd=self.cwd))

    def test_slash_scheme_collision_denied(self):
        self.assertDeny(self._sh("sed -i 's/__T__/https://x/' body.md"),
                        "sed-url-delimiter-collision")

    def test_hash_fragment_collision_denied(self):
        self.assertDeny(self._sh("sed -i 's#x#https://h/p#frag#' body.md"))

    def test_addressed_form_denied(self):
        self.assertDeny(self._sh("sed -i '1s/__T__/https://x/' body.md"))

    def test_safe_at_delimiter_allowed(self):
        self.assertAllow(self._sh("sed -i 's@__T__@https://x@' body.md"))

    def test_safe_pipe_delimiter_allowed(self):
        self.assertAllow(self._sh("sed -i 's|__T__|https://x|' body.md"))

    def test_hash_without_fragment_allowed(self):
        # Exactly three '#', URL has no '#' fragment -> safe.
        self.assertAllow(self._sh("sed -i 's#a#https://h/p#g' body.md"))

    def test_no_url_allowed(self):
        self.assertAllow(self._sh("sed -i 's/foo/bar/' body.md"))


# ── [edit guard] (rule 7) — delta-based fix-forward lint reject ──────────────────────

class TestEditGuard(GuardTestBase):
    def setUp(self):
        super().setUp()
        # Synthetic checker: one diagnostic line per 'BANG' occurrence.
        cdir = self.tmpdir()
        self.checker = os.path.join(cdir, "bang-lint.sh")
        with open(self.checker, "w") as f:
            f.write("#!/usr/bin/env bash\ngrep -o 'BANG' \"$1\" 2>/dev/null || true\n")
        self.checkers = {"*.txt": self.checker}
        self.pol = guard.make_edit_guard(checkers=self.checkers)

    def _commit(self, cwd, name, content):
        p = os.path.join(cwd, name)
        with open(p, "w") as f:
            f.write(content)
        _git(["add", name], cwd)
        _git(["commit", "-q", "-m", name], cwd)
        return p

    def _write(self, p, content):
        with open(p, "w") as f:
            f.write(content)

    def test_new_diagnostic_denied(self):
        cwd = self.repo("feature/x")
        p = self._commit(cwd, "f.txt", "clean\n")       # baseline 0 BANG
        self._write(p, "clean\nBANG\n")                 # edit adds 1
        self.assertDeny(self.pol(_event("sys_os_edit", path=p, cwd=cwd)),
                        "edit-lint-regression")

    def test_no_new_diagnostic_allowed(self):
        cwd = self.repo("feature/x")
        p = self._commit(cwd, "f.txt", "clean\n")
        self._write(p, "still clean\n")
        self.assertAllow(self.pol(_event("sys_os_edit", path=p, cwd=cwd)))

    def test_preexisting_diagnostic_not_blocking(self):
        # Baseline already has a BANG; an edit that keeps the count is allowed.
        cwd = self.repo("feature/x")
        p = self._commit(cwd, "f.txt", "BANG\nold\n")   # baseline 1
        self._write(p, "BANG\nnew line\n")              # still 1
        self.assertAllow(self.pol(_event("sys_os_edit", path=p, cwd=cwd)))

    def test_out_of_repo_fails_open(self):
        cwd = self.repo("feature/x")
        outside = os.path.join(self.tmpdir(), "x.txt")
        self._write(outside, "BANG\nBANG\n")
        self.assertAllow(self.pol(_event("sys_os_edit", path=outside, cwd=cwd)))

    def test_no_checker_for_type_fails_open(self):
        cwd = self.repo("feature/x")
        p = self._commit(cwd, "f.md", "clean\n")        # *.md not in self.checkers
        self._write(p, "BANG\n")
        self.assertAllow(self.pol(_event("sys_os_edit", path=p, cwd=cwd)))

    def test_non_edit_tool_ignored(self):
        cwd = self.repo("feature/x")
        self.assertAllow(self.pol(_event("sys_os_shell", command="echo hi", cwd=cwd)))

    def test_default_checkers_resolve_project_map(self):
        # The None-default reads the profile's "Edit-time checks" map; *.sh must resolve.
        root = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=os.path.dirname(os.path.abspath(__file__)),
            capture_output=True, text=True,
        ).stdout.strip()
        resolved = guard._resolve_checker("anything.sh", None, root)
        self.assertTrue(resolved and resolved.endswith("shell-lint.sh"),
                        "default checker map did not resolve *.sh -> shell-lint.sh (%r)" % resolved)


# ── Fail-open contract ───────────────────────────────────────────────────────────────

class TestFailOpen(GuardTestBase):
    def test_internal_exception_fails_open(self):
        pol = guard.make_guard_tool_call(base_branch="main")
        cwd = self.repo("main")
        ev = _event("sys_os_edit", path=os.path.join(cwd, "seed.txt"), cwd=cwd)
        # This event WOULD be denied (edit on base). Force an internal raise and assert the
        # policy still abstains — Omnigent's on-raise default is undocumented, so the port
        # must guarantee fail-open itself.
        orig = guard._branch
        guard._branch = lambda *_a, **_k: (_ for _ in ()).throw(RuntimeError("boom"))
        try:
            self.assertIsNone(pol(ev))
        finally:
            guard._branch = orig

    def test_edit_guard_internal_exception_fails_open(self):
        pol = guard.make_edit_guard(checkers={"*.txt": "/nonexistent/checker.sh"})
        cwd = self.repo("feature/x")
        p = os.path.join(cwd, "f.txt")
        with open(p, "w") as f:
            f.write("BANG\n")
        orig = guard._resolve_checker
        guard._resolve_checker = lambda *_a, **_k: (_ for _ in ()).throw(RuntimeError("boom"))
        try:
            self.assertIsNone(pol(_event("sys_os_edit", path=p, cwd=cwd)))
        finally:
            guard._resolve_checker = orig

    def test_malformed_events_abstain(self):
        pol = guard.make_guard_tool_call()
        eg = guard.make_edit_guard()
        for bad in (None, {}, {"type": "tool_call"}, {"type": "request"},
                    {"type": "tool_call", "target": "sys_os_shell", "data": {}}):
            self.assertIsNone(pol(bad))
            self.assertIsNone(eg(bad))

    def test_non_tool_call_phase_ignored_by_guard(self):
        pol = guard.make_guard_tool_call(base_branch="main")
        cwd = self.repo("main")
        # A non-tool_call phase must not trigger the tool_call rules.
        ev = _event("sys_os_shell", "git add .", cwd=cwd, type_="request")
        self.assertIsNone(pol(ev))


# ── CI wiring (machinery proves it is live — constitution P2) ────────────────────────

class TestCIWiring(unittest.TestCase):
    def test_verify_runs_these_tests(self):
        root = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=os.path.dirname(os.path.abspath(__file__)),
            capture_output=True, text=True,
        ).stdout.strip()
        ci = os.path.join(root, ".github", "workflows", "ci.yml")
        with open(ci) as f:
            text = f.read()
        # Catches the step's command drifting off this test path (the same self-wiring
        # discipline the bash machinery tests use). Removing the whole step is the known
        # shared limitation — the extraction manifest still inventories these files.
        self.assertIn(".claude/adapters/omnigent/tests/test_", text,
                      "ci.yml verify must RUN the Omnigent guard policy tests")


if __name__ == "__main__":
    unittest.main(verbosity=2)
