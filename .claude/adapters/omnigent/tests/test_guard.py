#!/usr/bin/env python3
"""Unit tests for the Omnigent [guard] / [edit guard] policy port (T618, #136).

Encodes #119 AC2: the guard rules normatively listed in
``.claude/workflow/README.md`` -> "The [guard] rules" are deterministic, **fail-open**
``tool_call`` / ``tool_result`` policies; bulk staging (``git add .`` / ``-A``),
commit/push-to-base, base-branch edits, and pending-commit tasks drift return DENY;
passing controls plus adversarial variants prove the matchers are not literal-string
shortcuts; and any internal exception fails OPEN.

Run directly (the CI ``verify`` step does, via a fail-closed glob):

    python3 .claude/adapters/omnigent/tests/test_guard.py

Hermetic: stdlib + ``git`` only; no Omnigent install, no network. Rule-5 model fixtures
use synthetic model ids so no real model vocabulary lands in the adapter subtree (the
T617 neutral-core confinement check stays green).
"""

import importlib
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


# -- Rule 7 -- pending-commit tasks drift ---------------------------------------------

class TestPendingCommitTasksDrift(GuardTestBase):
    def setUp(self):
        super().setUp()
        self.pol = guard.make_guard_tool_call(base_branch="main")

    def _seed_tasks(self, cwd, text):
        tasks_dir = os.path.join(cwd, "specs", "010-fixture")
        os.makedirs(tasks_dir)
        path = os.path.join(tasks_dir, "tasks.md")
        with open(path, "w") as f:
            f.write(text)
        _git(["add", "specs/010-fixture/tasks.md"], cwd)
        _git(["commit", "-q", "-m", "seed fixture tasks file"], cwd)
        return path

    def _commit_seed_change(self, cwd, subject, suffix):
        with open(os.path.join(cwd, "seed.txt"), "a") as f:
            f.write(suffix)
        _git(["add", "seed.txt"], cwd)
        _git(["commit", "-q", "-m", subject], cwd)
        return subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=cwd,
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()

    def test_pending_commit_id_with_unchecked_task_denied(self):
        # No reachable commit mentions T987; the id exists only in the imminent command.
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")

        self.assertDeny(
            self.pol(_event("sys_os_shell", 'git commit -m "feat: [T987] do the thing"', cwd=cwd)),
            "commit-tasks-drift",
        )

    def test_pending_commit_id_with_checked_task_allowed(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [x] T987 fixture task\n")

        self.assertAllow(
            self.pol(_event("sys_os_shell", 'git commit -m "feat: [T987] do the thing"', cwd=cwd))
        )

    def test_pending_commit_id_without_tasks_files_fails_open(self):
        cwd = self.repo("feature/x")

        self.assertAllow(
            self.pol(_event("sys_os_shell", 'git commit -m "feat: [T987] do the thing"', cwd=cwd))
        )

    def test_unchecked_definition_comes_from_shared_drift_lib(self):
        lib_dir = self.tmpdir()
        lib_path = os.path.join(lib_dir, "lib-tasks-drift.sh")
        with open(lib_path, "w") as f:
            f.write(
                "tasks_drift_unchecked_ids() {\n"
                "  grep -hoE '^TODO T[0-9]+' specs/*/tasks.md 2>/dev/null "
                "| grep -oE 'T[0-9]+' | sort -u\n"
                "}\n"
            )
        old_lib = guard._TASKS_DRIFT_LIB
        guard._TASKS_DRIFT_LIB = lib_path
        try:
            markdown_box = self.repo("feature/markdown")
            self._seed_tasks(markdown_box, "- [ ] T987 fixture task\n")
            self.assertAllow(
                self.pol(_event(
                    "sys_os_shell",
                    'git commit -m "feat: [T987] do the thing"',
                    cwd=markdown_box,
                ))
            )

            shared_shape = self.repo("feature/shared")
            self._seed_tasks(shared_shape, "TODO T987 fixture task\n")
            self.assertDeny(
                self.pol(_event(
                    "sys_os_shell",
                    'git commit -m "feat: [T987] do the thing"',
                    cwd=shared_shape,
                )),
                "commit-tasks-drift",
            )
        finally:
            guard._TASKS_DRIFT_LIB = old_lib

    def test_plain_commit_reads_staged_tasks_view(self):
        cwd = self.repo("feature/x")
        path = self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        with open(path, "w") as f:
            f.write("- [x] T987 fixture task\n")

        self.assertDeny(
            self.pol(_event("sys_os_shell", 'git commit -m "feat: [T987] do the thing"', cwd=cwd)),
            "commit-tasks-drift",
        )

    def test_plain_commit_from_subdir_reads_root_tasks_index(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        subdir = os.path.join(cwd, "src")
        os.mkdir(subdir)
        with open(os.path.join(subdir, "feature.txt"), "w") as f:
            f.write("changed\n")
        _git(["add", "src/feature.txt"], cwd)

        self.assertDeny(
            self.pol(_event(
                "sys_os_shell",
                'git commit -m "feat: [T987] do the thing"',
                cwd=subdir,
            )),
            "commit-tasks-drift",
        )

    def test_commit_all_reads_worktree_tasks_view(self):
        cwd = self.repo("feature/x")
        path = self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        with open(path, "w") as f:
            f.write("- [x] T987 fixture task\n")

        self.assertAllow(
            self.pol(_event("sys_os_shell", 'git commit -am "feat: [T987] do the thing"', cwd=cwd))
        )

    def test_no_all_after_all_reads_staged_tasks_view(self):
        cwd = self.repo("feature/x")
        path = self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        with open(path, "w") as f:
            f.write("- [x] T987 fixture task\n")

        for command in (
            'git commit --all --no-all -m "feat: [T987] do the thing"',
            'git commit -a --no-all -m "feat: [T987] do the thing"',
        ):
            with self.subTest(command=command):
                self.assertDeny(
                    self.pol(_event("sys_os_shell", command, cwd=cwd)),
                    "commit-tasks-drift",
                )

        self.assertAllow(
            self.pol(_event(
                "sys_os_shell",
                'git commit --no-all --all -m "feat: [T987] do the thing"',
                cwd=cwd,
            ))
        )

    def test_interactive_patch_commit_modes_fail_open(self):
        cwd = self.repo("feature/x")
        path = self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        with open(path, "w") as f:
            f.write("- [x] T987 fixture task\n")

        for command in (
            'git commit -p -m "feat: [T987] do the thing"',
            'git commit --patch -m "feat: [T987] do the thing"',
            'git commit --interactive -m "feat: [T987] do the thing"',
        ):
            with self.subTest(command=command):
                self.assertAllow(self.pol(_event("sys_os_shell", command, cwd=cwd)))

    def test_reused_commit_message_task_ids_are_detected(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        source_sha = self._commit_seed_change(cwd, "feat: [T987] previous work", "source\n")
        with open(os.path.join(cwd, "seed.txt"), "a") as f:
            f.write("pending\n")
        _git(["add", "seed.txt"], cwd)

        for command in (
            "git commit --fixup=%s" % source_sha,
            "git commit --fixup=amend:%s" % source_sha,
            "git commit --squash=%s" % source_sha,
            "git commit -C %s" % source_sha,
            "git commit --reuse-message=%s" % source_sha,
        ):
            with self.subTest(command=command):
                self.assertDeny(
                    self.pol(_event("sys_os_shell", command, cwd=cwd)),
                    "commit-tasks-drift",
                )

        other_cwd = self.repo("feature/other")
        self.assertDeny(
            self.pol(_event(
                "sys_os_shell",
                "git -C %s commit --fixup=%s" % (cwd, source_sha),
                cwd=other_cwd,
            )),
            "commit-tasks-drift",
        )

    def test_no_edit_amend_reuses_head_message_task_ids(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        self._commit_seed_change(cwd, "feat: [T987] previous work", "source\n")
        with open(os.path.join(cwd, "seed.txt"), "a") as f:
            f.write("pending\n")
        _git(["add", "seed.txt"], cwd)

        self.assertDeny(
            self.pol(_event("sys_os_shell", "git commit --amend --no-edit", cwd=cwd)),
            "commit-tasks-drift",
        )

    def test_no_edit_amend_with_trailer_reuses_head_message_task_ids(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        self._commit_seed_change(cwd, "feat: [T987] previous work", "source\n")
        with open(os.path.join(cwd, "seed.txt"), "a") as f:
            f.write("pending\n")
        _git(["add", "seed.txt"], cwd)

        self.assertDeny(
            self.pol(_event(
                "sys_os_shell",
                'git commit --amend --no-edit --trailer "Reviewed-by=Me"',
                cwd=cwd,
            )),
            "commit-tasks-drift",
        )

    def test_oversize_message_file_fails_open(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        msg = os.path.join(cwd, "message.txt")
        with open(msg, "w") as f:
            f.write("feat: [T987] do the thing\n")

        old_limit = guard._MAX_GUARD_FILE_READ_BYTES
        guard._MAX_GUARD_FILE_READ_BYTES = 8
        try:
            self.assertAllow(self.pol(_event("sys_os_shell", "git commit -F message.txt", cwd=cwd)))
        finally:
            guard._MAX_GUARD_FILE_READ_BYTES = old_limit

    def test_negated_status_format_modes_are_real_commits(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")

        for command in (
            'git commit --porcelain --no-porcelain -m "feat: [T987] do the thing"',
            'git commit --short --no-short -m "feat: [T987] do the thing"',
            'git commit --long --no-long -m "feat: [T987] do the thing"',
        ):
            with self.subTest(command=command):
                self.assertDeny(
                    self.pol(_event("sys_os_shell", command, cwd=cwd)),
                    "commit-tasks-drift",
                )

    def test_no_path_only_commit_reads_head_tasks_view(self):
        cwd = self.repo("feature/x")
        path = self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        source_sha = self._commit_seed_change(cwd, "feat: [T987] previous work", "source\n")
        with open(path, "w") as f:
            f.write("- [x] T987 fixture task\n")
        _git(["add", "specs/010-fixture/tasks.md"], cwd)

        for command in (
            'git commit --allow-empty --only -m "feat: [T987] do the thing"',
            "git commit --fixup=reword:%s --no-edit" % source_sha,
        ):
            with self.subTest(command=command):
                self.assertDeny(
                    self.pol(_event("sys_os_shell", command, cwd=cwd)),
                    "commit-tasks-drift",
                )

    def test_include_non_tasks_path_reads_staged_tasks_view(self):
        cwd = self.repo("feature/x")
        path = self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        with open(path, "w") as f:
            f.write("- [x] T987 fixture task\n")

        self.assertDeny(
            self.pol(_event(
                "sys_os_shell",
                'git commit --include seed.txt -m "feat: [T987] do the thing"',
                cwd=cwd,
            )),
            "commit-tasks-drift",
        )

    def test_include_non_tasks_path_lands_staged_tasks_view(self):
        cwd = self.repo("feature/x")
        path = self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        with open(path, "w") as f:
            f.write("- [x] T987 fixture task\n")
        _git(["add", "specs/010-fixture/tasks.md"], cwd)
        with open(os.path.join(cwd, "seed.txt"), "a") as f:
            f.write("changed\n")

        for command in (
            'git commit --include seed.txt -m "feat: [T987] do the thing"',
            'git commit seed.txt --include -m "feat: [T987] do the thing"',
            'git commit -i seed.txt -m "feat: [T987] do the thing"',
        ):
            with self.subTest(command=command):
                self.assertAllow(self.pol(_event("sys_os_shell", command, cwd=cwd)))

    def test_no_include_after_include_reads_pathspec_tasks_view(self):
        cwd = self.repo("feature/x")
        path = self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        with open(path, "w") as f:
            f.write("- [x] T987 fixture task\n")
        _git(["add", "specs/010-fixture/tasks.md"], cwd)
        with open(os.path.join(cwd, "seed.txt"), "a") as f:
            f.write("changed\n")

        self.assertDeny(
            self.pol(_event(
                "sys_os_shell",
                'git commit --include --no-include seed.txt -m "feat: [T987] do the thing"',
                cwd=cwd,
            )),
            "commit-tasks-drift",
        )

    def test_no_only_after_only_reads_staged_tasks_view(self):
        cwd = self.repo("feature/x")
        path = self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        with open(path, "w") as f:
            f.write("- [x] T987 fixture task\n")
        _git(["add", "specs/010-fixture/tasks.md"], cwd)

        self.assertAllow(
            self.pol(_event(
                "sys_os_shell",
                'git commit --only --no-only -m "feat: [T987] do the thing"',
                cwd=cwd,
            ))
        )

    def test_include_tasks_path_reads_worktree_tasks_view(self):
        cwd = self.repo("feature/x")
        path = self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        with open(path, "w") as f:
            f.write("- [x] T987 fixture task\n")

        for command in (
            'git commit --include specs/010-fixture/tasks.md -m "feat: [T987] do the thing"',
            'git commit --include=specs/010-fixture/tasks.md -m "feat: [T987] do the thing"',
        ):
            with self.subTest(command=command):
                self.assertAllow(self.pol(_event("sys_os_shell", command, cwd=cwd)))

    def test_pathspec_from_file_tasks_path_reads_worktree_tasks_view(self):
        cwd = self.repo("feature/x")
        path = self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        pathspecs = os.path.join(cwd, "paths.txt")
        with open(pathspecs, "w") as f:
            f.write("specs/010-fixture/tasks.md\n")
        with open(path, "w") as f:
            f.write("- [x] T987 fixture task\n")

        self.assertAllow(
            self.pol(_event(
                "sys_os_shell",
                'git commit --pathspec-from-file=paths.txt -m "feat: [T987] do the thing"',
                cwd=cwd,
            ))
        )

        _git(["add", "specs/010-fixture/tasks.md"], cwd)
        with open(path, "w") as f:
            f.write("- [ ] T987 fixture task\n")

        self.assertDeny(
            self.pol(_event(
                "sys_os_shell",
                'git commit --pathspec-from-file paths.txt -m "feat: [T987] do the thing"',
                cwd=cwd,
            )),
            "commit-tasks-drift",
        )

    def test_oversize_pathspec_file_fails_open(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        pathspecs = os.path.join(cwd, "paths.txt")
        with open(pathspecs, "w") as f:
            f.write("specs/010-fixture/tasks.md\nspecs/010-fixture/tasks.md\n")

        old_limit = guard._MAX_GUARD_FILE_READ_BYTES
        guard._MAX_GUARD_FILE_READ_BYTES = 16
        try:
            self.assertAllow(
                self.pol(_event(
                    "sys_os_shell",
                    'git commit --pathspec-from-file paths.txt -m "feat: [T987] do the thing"',
                    cwd=cwd,
                ))
            )
        finally:
            guard._MAX_GUARD_FILE_READ_BYTES = old_limit

    def test_pathspec_commit_of_staged_tasks_deletion_does_not_read_head(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        _git(["rm", "-q", "specs/010-fixture/tasks.md"], cwd)

        self.assertAllow(
            self.pol(_event(
                "sys_os_shell",
                'git commit specs/010-fixture/tasks.md -m "feat: [T987] delete task file"',
                cwd=cwd,
            ))
        )

    def test_broad_pathspec_commit_of_tasks_deletion_does_not_read_head(self):
        for command in (
            'git commit . -m "feat: [T987] delete task file"',
            'git commit specs -m "feat: [T987] delete task file"',
            'git commit specs/010-fixture -m "feat: [T987] delete task file"',
        ):
            with self.subTest(command=command):
                cwd = self.repo("feature/x")
                self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
                _git(["rm", "-q", "specs/010-fixture/tasks.md"], cwd)

                self.assertAllow(self.pol(_event("sys_os_shell", command, cwd=cwd)))

    def test_subdirectory_broad_pathspec_commit_of_tasks_deletion_does_not_read_head(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        subdir = os.path.join(cwd, "subdir")
        os.makedirs(subdir)
        _git(["rm", "-q", "specs/010-fixture/tasks.md"], cwd)

        self.assertAllow(
            self.pol(_event(
                "sys_os_shell",
                'git commit .. -m "feat: [T987] delete task file"',
                cwd=subdir,
            ))
        )

    def test_target_repo_pathspec_deletion_uses_invoked_cwd(self):
        clean = self.repo("feature/clean")
        drifted = self.repo("feature/drifted")
        self._seed_tasks(drifted, "- [ ] T987 fixture task\n")
        _git(["rm", "-q", "specs/010-fixture/tasks.md"], drifted)

        for command in (
            'git -C %s commit specs/010-fixture/tasks.md '
            '-m "feat: [T987] delete task file"' % drifted,
            'env -C %s git commit specs/010-fixture/tasks.md '
            '-m "feat: [T987] delete task file"' % drifted,
        ):
            with self.subTest(command=command):
                self.assertAllow(self.pol(_event("sys_os_shell", command, cwd=clean)))

    def test_unmatched_pathspec_fails_open(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")

        self.assertAllow(
            self.pol(_event(
                "sys_os_shell",
                'git commit no/such -m "feat: [T987] typo"',
                cwd=cwd,
            ))
        )

    def test_unmatched_negative_pathspec_excludes_nothing(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        with open(os.path.join(cwd, "seed.txt"), "a") as f:
            f.write("changed\n")

        for command in (
            'git commit . :!no/such -m "feat: [T987] do the thing"',
            'git commit . ":(exclude)no/such" -m "feat: [T987] do the thing"',
        ):
            with self.subTest(command=command):
                self.assertDeny(
                    self.pol(_event("sys_os_shell", command, cwd=cwd)),
                    "commit-tasks-drift",
                )

    def test_pathspec_commit_excluding_tasks_reads_head_tasks_view(self):
        cwd = self.repo("feature/x")
        path = self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        with open(path, "w") as f:
            f.write("- [x] T987 fixture task\n")
        _git(["add", "specs/010-fixture/tasks.md"], cwd)
        with open(os.path.join(cwd, "seed.txt"), "a") as f:
            f.write("changed\n")

        self.assertDeny(
            self.pol(_event(
                "sys_os_shell",
                'git commit seed.txt -m "feat: [T987] change seed"',
                cwd=cwd,
            )),
            "commit-tasks-drift",
        )

    def test_deleted_non_tasks_pathspec_reads_head_tasks_view(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        docs_dir = os.path.join(cwd, "docs")
        os.makedirs(docs_dir)
        docs_path = os.path.join(docs_dir, "x.md")
        with open(docs_path, "w") as f:
            f.write("x\n")
        _git(["add", "docs/x.md"], cwd)
        _git(["commit", "-q", "-m", "seed docs file"], cwd)
        _git(["rm", "-q", "docs/x.md"], cwd)

        self.assertDeny(
            self.pol(_event(
                "sys_os_shell",
                'git commit docs/x.md -m "feat: [T987] delete docs"',
                cwd=cwd,
            )),
            "commit-tasks-drift",
        )

    def test_negated_status_condition_scans_possible_commit(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")

        for command in (
            '! false && git commit -m "feat: [T987] do the thing"',
            '! true || git commit -m "feat: [T987] do the thing"',
        ):
            with self.subTest(command=command):
                self.assertDeny(
                    self.pol(_event("sys_os_shell", command, cwd=cwd)),
                    "commit-tasks-drift",
                )

        for command in (
            '! true && git commit -m "feat: [T987] do the thing"',
            '! false || git commit -m "feat: [T987] do the thing"',
        ):
            with self.subTest(command=command):
                self.assertAllow(self.pol(_event("sys_os_shell", command, cwd=cwd)))

    def test_unsupported_shell_control_flow_fails_open(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")

        for command in (
            'if true; then echo ok; else git commit -m "feat: [T987] no"; fi',
            'if false; then git commit -m "feat: [T987] no"; fi',
            'while false; do git commit -m "feat: [T987] no"; done',
        ):
            with self.subTest(command=command):
                self.assertAllow(self.pol(_event("sys_os_shell", command, cwd=cwd)))

    def test_unsupported_shell_control_flow_command_substitution_fails_open(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")

        for command in (
            'if false; then echo "$(git commit -m \'feat: [T987] no\')"; fi',
            'case x in y) echo "$(git commit -m \'feat: [T987] no\')";; esac',
        ):
            with self.subTest(command=command):
                self.assertAllow(self.pol(_event("sys_os_shell", command, cwd=cwd)))

    def test_unsupported_shell_control_flow_preserves_prior_commit_scan(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")

        self.assertDeny(
            self.pol(_event(
                "sys_os_shell",
                'git commit -m "feat: [T987] do the thing"; if true; then echo ok; fi',
                cwd=cwd,
            )),
            "commit-tasks-drift",
        )

    def test_pathspec_magic_exclude_removes_tasks_from_worktree_selection(self):
        cwd = self.repo("feature/x")
        path = self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        with open(path, "w") as f:
            f.write("- [x] T987 fixture task\n")
        _git(["add", "specs/010-fixture/tasks.md"], cwd)
        with open(os.path.join(cwd, "seed.txt"), "a") as f:
            f.write("changed\n")

        self.assertDeny(
            self.pol(_event(
                "sys_os_shell",
                'git commit . ":(exclude)specs/010-fixture/tasks.md" '
                '-m "feat: [T987] change seed"',
                cwd=cwd,
            )),
            "commit-tasks-drift",
        )

    def test_top_magic_exclude_from_subdir_removes_tasks_from_worktree_selection(self):
        cwd = self.repo("feature/x")
        path = self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        subdir = os.path.join(cwd, "subdir")
        os.makedirs(subdir)
        with open(path, "w") as f:
            f.write("- [x] T987 fixture task\n")
        _git(["add", "specs/010-fixture/tasks.md"], cwd)
        with open(os.path.join(cwd, "seed.txt"), "a") as f:
            f.write("changed\n")

        self.assertDeny(
            self.pol(_event(
                "sys_os_shell",
                'git commit .. ":(top,exclude)specs/010-fixture/tasks.md" '
                '-m "feat: [T987] change seed"',
                cwd=subdir,
            )),
            "commit-tasks-drift",
        )

    def test_exclude_only_pathspec_can_still_land_tasks_view(self):
        cwd = self.repo("feature/x")
        path = self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        with open(path, "w") as f:
            f.write("- [x] T987 fixture task\n")
        with open(os.path.join(cwd, "seed.txt"), "a") as f:
            f.write("changed\n")

        self.assertAllow(
            self.pol(_event(
                "sys_os_shell",
                'git commit ":(exclude)seed.txt" -m "feat: [T987] update task"',
                cwd=cwd,
            ))
        )

    def test_exclude_only_pathspec_from_subdir_can_still_land_tasks_view(self):
        cwd = self.repo("feature/x")
        path = self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        subdir = os.path.join(cwd, "subdir")
        os.makedirs(subdir)
        with open(os.path.join(subdir, "other.txt"), "w") as f:
            f.write("changed\n")
        with open(path, "w") as f:
            f.write("- [x] T987 fixture task\n")

        self.assertAllow(
            self.pol(_event(
                "sys_os_shell",
                'git commit ":(exclude)seed.txt" -m "feat: [T987] update task"',
                cwd=subdir,
            ))
        )

    def test_pathspec_from_file_magic_exclude_removes_tasks_from_worktree_selection(self):
        cwd = self.repo("feature/x")
        path = self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        pathspecs = os.path.join(cwd, "paths.txt")
        with open(pathspecs, "w") as f:
            f.write(".\n:(exclude)specs/010-fixture/tasks.md\n")
        with open(path, "w") as f:
            f.write("- [x] T987 fixture task\n")
        with open(os.path.join(cwd, "seed.txt"), "a") as f:
            f.write("changed\n")

        self.assertDeny(
            self.pol(_event(
                "sys_os_shell",
                'git commit --pathspec-from-file=paths.txt -m "feat: [T987] change seed"',
                cwd=cwd,
            )),
            "commit-tasks-drift",
        )

    def test_pathspec_other_tasks_file_does_not_cover_referenced_task_file(self):
        cwd = self.repo("feature/x")
        path = self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        other_dir = os.path.join(cwd, "specs", "020-other")
        os.makedirs(other_dir)
        other_path = os.path.join(other_dir, "tasks.md")
        with open(other_path, "w") as f:
            f.write("- [x] T100 other task\n")
        _git(["add", "specs/020-other/tasks.md"], cwd)
        _git(["commit", "-q", "-m", "seed other tasks file"], cwd)

        with open(path, "w") as f:
            f.write("- [x] T987 fixture task\n")
        with open(other_path, "w") as f:
            f.write("- [x] T100 other task changed\n")

        self.assertDeny(
            self.pol(_event(
                "sys_os_shell",
                'git commit specs/020-other/tasks.md -m "feat: [T987] do the thing"',
                cwd=cwd,
            )),
            "commit-tasks-drift",
        )

    def test_amend_only_without_pathspec_reads_head_tasks_view(self):
        cwd = self.repo("feature/x")
        path = self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        with open(path, "w") as f:
            f.write("- [x] T987 fixture task\n")
        _git(["add", "specs/010-fixture/tasks.md"], cwd)

        self.assertDeny(
            self.pol(_event(
                "sys_os_shell",
                'git commit --amend --only -m "feat: [T987] do the thing"',
                cwd=cwd,
            )),
            "commit-tasks-drift",
        )

    def test_relative_tasks_pathspec_from_subdir_reads_worktree_tasks_view(self):
        cwd = self.repo("feature/x")
        path = self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        subdir = os.path.join(cwd, "sub")
        os.makedirs(subdir)
        with open(path, "w") as f:
            f.write("- [x] T987 fixture task\n")

        self.assertAllow(
            self.pol(_event(
                "sys_os_shell",
                'git commit ../specs/010-fixture/tasks.md -m "feat: [T987] do the thing"',
                cwd=subdir,
            ))
        )

    def test_pathspec_from_file_in_subdir_reads_worktree_tasks_view(self):
        cwd = self.repo("feature/x")
        path = self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        subdir = os.path.join(cwd, "sub")
        os.makedirs(subdir)
        with open(path, "w") as f:
            f.write("- [x] T987 fixture task\n")
        _git(["add", "specs/010-fixture/tasks.md"], cwd)
        with open(path, "w") as f:
            f.write("- [ ] T987 fixture task\n")
        with open(os.path.join(subdir, "paths.txt"), "w") as f:
            f.write("../specs/010-fixture/tasks.md\n")

        self.assertDeny(
            self.pol(_event(
                "sys_os_shell",
                'git commit --pathspec-from-file=paths.txt -m "feat: [T987] do the thing"',
                cwd=subdir,
            )),
            "commit-tasks-drift",
        )

    def test_absolute_tasks_path_reads_worktree_tasks_view(self):
        cwd = self.repo("feature/x")
        path = self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        with open(path, "w") as f:
            f.write("- [x] T987 fixture task\n")

        self.assertAllow(
            self.pol(_event(
                "sys_os_shell",
                'git commit %s -m "feat: [T987] do the thing"' % path,
                cwd=cwd,
            ))
        )

    def test_redirection_targets_do_not_switch_to_worktree_tasks_view(self):
        cwd = self.repo("feature/x")
        path = self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        with open(path, "w") as f:
            f.write("- [x] T987 fixture task\n")

        for command in (
            'git commit -m "feat: [T987] do the thing" < specs/010-fixture/tasks.md',
            'git commit -m "feat: [T987] do the thing" > specs/010-fixture/tasks.md',
            'git commit -m "feat: [T987] do the thing" 2> specs/010-fixture/tasks.md',
        ):
            with self.subTest(command=command):
                self.assertDeny(
                    self.pol(_event("sys_os_shell", command, cwd=cwd)),
                    "commit-tasks-drift",
                )

    def test_template_options_do_not_switch_to_head_tasks_view(self):
        cwd = self.repo("feature/x")
        path = self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        with open(path, "w") as f:
            f.write("- [x] T987 fixture task\n")
        _git(["add", "specs/010-fixture/tasks.md"], cwd)
        with open(os.path.join(cwd, "commit-template.txt"), "w") as f:
            f.write("template body\n")

        for command in (
            'git commit -t commit-template.txt -m "feat: [T987] do the thing"',
            'git commit --template commit-template.txt -m "feat: [T987] do the thing"',
        ):
            with self.subTest(command=command):
                self.assertAllow(self.pol(_event("sys_os_shell", command, cwd=cwd)))

    def test_attached_commit_all_reads_worktree_tasks_view(self):
        cwd = self.repo("feature/x")
        path = self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        with open(path, "w") as f:
            f.write("- [x] T987 fixture task\n")

        self.assertAllow(
            self.pol(_event("sys_os_shell", 'git commit -am"feat: [T987] do the thing"', cwd=cwd))
        )

    def test_untracked_files_short_option_does_not_read_worktree_tasks_view(self):
        cwd = self.repo("feature/x")
        path = self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        with open(path, "w") as f:
            f.write("- [x] T987 fixture task\n")
        with open(os.path.join(cwd, "seed.txt"), "a") as f:
            f.write("changed\n")
        _git(["add", "seed.txt"], cwd)

        self.assertDeny(
            self.pol(_event("sys_os_shell", 'git commit -uall -m "feat: [T987] do the thing"', cwd=cwd)),
            "commit-tasks-drift",
        )

    def test_attached_gpg_sign_key_does_not_read_worktree_tasks_view(self):
        cwd = self.repo("feature/x")
        path = self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        with open(path, "w") as f:
            f.write("- [x] T987 fixture task\n")

        self.assertDeny(
            self.pol(_event("sys_os_shell", 'git commit -Sdeadbeef -m "feat: [T987] do the thing"', cwd=cwd)),
            "commit-tasks-drift",
        )

    def test_commit_all_ignores_untracked_worktree_tasks_file(self):
        cwd = self.repo("feature/x")
        tasks_dir = os.path.join(cwd, "specs", "010-fixture")
        os.makedirs(tasks_dir)
        with open(os.path.join(tasks_dir, "tasks.md"), "w") as f:
            f.write("- [ ] T987 fixture task\n")
        with open(os.path.join(cwd, "seed.txt"), "a") as f:
            f.write("changed\n")

        self.assertAllow(
            self.pol(_event("sys_os_shell", 'git commit -am "feat: [T987] do the thing"', cwd=cwd))
        )

    def test_unchecked_task_matcher_uses_shared_spacing(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "-  [ ] T987 fixture task\n")

        self.assertAllow(
            self.pol(_event("sys_os_shell", 'git commit -m "feat: [T987] do the thing"', cwd=cwd))
        )

    def test_attached_plain_message_reads_staged_tasks_view(self):
        cwd = self.repo("feature/x")
        path = self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        with open(path, "w") as f:
            f.write("- [x] T987 fixture task\n")

        self.assertDeny(
            self.pol(_event("sys_os_shell", 'git commit -m"feat: [T987] do the thing"', cwd=cwd)),
            "commit-tasks-drift",
        )

    def test_git_C_commit_reads_target_repo_tasks(self):
        clean = self.repo("feature/clean")
        drifted = self.repo("feature/drifted")
        self._seed_tasks(drifted, "- [ ] T987 fixture task\n")

        self.assertDeny(
            self.pol(_event(
                "sys_os_shell",
                'git -C %s commit -m "feat: [T987] do the thing"' % drifted,
                cwd=clean,
            )),
            "commit-tasks-drift",
        )

    def test_git_dir_commit_reads_target_repo_tasks(self):
        clean = self.repo("feature/clean")
        drifted = self.repo("feature/drifted")
        self._seed_tasks(drifted, "- [ ] T987 fixture task\n")

        self.assertDeny(
            self.pol(_event(
                "sys_os_shell",
                'git --git-dir=%s/.git commit -m "feat: [T987] do the thing"' % drifted,
                cwd=clean,
            )),
            "commit-tasks-drift",
        )

    def test_separate_git_dir_work_tree_commit_reads_target_index(self):
        clean = self.repo("feature/clean")
        drifted = self.repo("feature/drifted")
        self._seed_tasks(drifted, "- [ ] T987 fixture task\n")
        base = self.tmpdir()
        git_dir = os.path.join(base, "repo.git")
        work_tree = os.path.join(base, "wt")
        os.mkdir(work_tree)
        _git(["clone", "--bare", drifted, git_dir], base)
        repo_args = ["--git-dir", git_dir, "--work-tree", work_tree]
        _git(repo_args + ["checkout", "-f", "feature/drifted"], base)
        _git(repo_args + ["config", "user.email", "t@example.com"], base)
        _git(repo_args + ["config", "user.name", "Test"], base)
        with open(os.path.join(work_tree, "seed.txt"), "a") as f:
            f.write("changed\n")
        _git(repo_args + ["add", "seed.txt"], base)

        self.assertDeny(
            self.pol(_event(
                "sys_os_shell",
                'git --git-dir=%s --work-tree=%s commit -m "feat: [T987] do the thing"'
                % (git_dir, work_tree),
                cwd=clean,
            )),
            "commit-tasks-drift",
        )

    def test_shell_c_wrapped_commit_is_detected(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")

        for command in (
            'bash -c \'git commit -m "feat: [T987] do the thing"\'',
            'sh -c \'git commit -m "feat: [T987] do the thing"\'',
            '/bin/bash -c \'git commit -m "feat: [T987] do the thing"\'',
            '/bin/zsh -c \'git commit -m "feat: [T987] do the thing"\'',
            'bash -o pipefail -c \'git commit -m "feat: [T987] do the thing"\'',
            'env -S \'git commit -m "feat: [T987] do the thing"\'',
        ):
            with self.subTest(command=command):
                self.assertDeny(
                    self.pol(_event("sys_os_shell", command, cwd=cwd)),
                    "commit-tasks-drift",
                )

    def test_heredoc_body_is_not_scanned_as_commit(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")

        command = 'cat <<\'EOF\'\ngit commit -m "feat: [T987] do the thing"\nEOF'
        self.assertAllow(self.pol(_event("sys_os_shell", command, cwd=cwd)))

        command = "cat <<'EOF'\n$(git commit -m 'feat: [T987] do the thing')\nEOF"
        self.assertAllow(self.pol(_event("sys_os_shell", command, cwd=cwd)))

    def test_shell_fed_heredoc_body_is_detected(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")

        command = 'bash <<\'EOF\'\ngit commit -m "feat: [T987] do the thing"\nEOF'
        self.assertDeny(
            self.pol(_event("sys_os_shell", command, cwd=cwd)),
            "commit-tasks-drift",
        )

        command = "bash <<'EOF'\n$(git commit -m 'feat: [T987] do the thing')\nEOF"
        self.assertDeny(
            self.pol(_event("sys_os_shell", command, cwd=cwd)),
            "commit-tasks-drift",
        )

    def test_leading_redirection_before_commit_is_detected(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")

        for command in (
            '>/tmp/out git commit -m "feat: [T987] do the thing"',
            '> /tmp/out git commit -m "feat: [T987] do the thing"',
        ):
            with self.subTest(command=command):
                self.assertDeny(
                    self.pol(_event("sys_os_shell", command, cwd=cwd)),
                    "commit-tasks-drift",
                )

    def test_redirection_between_git_and_commit_is_detected(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")

        for command in (
            'git >/tmp/out commit -m "feat: [T987] do the thing"',
            'git 2>/tmp/err commit -m "feat: [T987] do the thing"',
        ):
            with self.subTest(command=command):
                self.assertDeny(
                    self.pol(_event("sys_os_shell", command, cwd=cwd)),
                    "commit-tasks-drift",
                )

    def test_command_prefix_options_before_commit_are_detected(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")

        for command in (
            'command -p git commit -m "feat: [T987] do the thing"',
            'time -p git commit -m "feat: [T987] do the thing"',
            'sudo git commit -m "feat: [T987] do the thing"',
            'sudo -E -u root git commit -m "feat: [T987] do the thing"',
        ):
            with self.subTest(command=command):
                self.assertDeny(
                    self.pol(_event("sys_os_shell", command, cwd=cwd)),
                    "commit-tasks-drift",
                )

    def test_compound_command_scopes_task_id_to_matching_commit(self):
        clean = self.repo("feature/clean")
        drifted = self.repo("feature/drifted")
        self._seed_tasks(drifted, "- [ ] T987 fixture task\n")

        self.assertDeny(
            self.pol(_event(
                "sys_os_shell",
                'git -C %s commit -m "chore: no task" && '
                'git -C %s commit -m "feat: [T987] do the thing"' % (clean, drifted),
                cwd=clean,
            )),
            "commit-tasks-drift",
        )

    def test_newline_command_scopes_task_id_to_matching_commit(self):
        clean = self.repo("feature/clean")
        drifted = self.repo("feature/drifted")
        self._seed_tasks(drifted, "- [ ] T987 fixture task\n")

        self.assertDeny(
            self.pol(_event(
                "sys_os_shell",
                'git commit -m "chore: no task"\n'
                'git -C %s commit -m "feat: [T987] do the thing"' % drifted,
                cwd=clean,
            )),
            "commit-tasks-drift",
        )

    def test_operator_newline_scopes_task_id_to_matching_commit(self):
        clean = self.repo("feature/clean")
        drifted = self.repo("feature/drifted")
        self._seed_tasks(drifted, "- [ ] T987 fixture task\n")

        self.assertDeny(
            self.pol(_event(
                "sys_os_shell",
                'git -C %s commit -m "chore: no task" &&\n'
                'git -C %s commit -m "feat: [T987] do the thing"' % (clean, drifted),
                cwd=clean,
            )),
            "commit-tasks-drift",
        )
        self.assertAllow(
            self.pol(_event(
                "sys_os_shell",
                'git -C %s commit -m "chore: no task" &&\n'
                'git -C %s commit -m "feat: [T987] do the thing"' % (drifted, clean),
                cwd=drifted,
            ))
        )

    def test_multiple_cd_tracks_commit_cwd(self):
        clean = self.repo("feature/clean")
        drifted = self.repo("feature/drifted")
        self._seed_tasks(drifted, "- [ ] T987 fixture task\n")
        parent = os.path.dirname(clean)

        self.assertDeny(
            self.pol(_event(
                "sys_os_shell",
                'cd %s; cd %s; git commit -m "feat: [T987] do the thing"' % (clean, drifted),
                cwd=parent,
            )),
            "commit-tasks-drift",
        )
        self.assertAllow(
            self.pol(_event(
                "sys_os_shell",
                'cd %s; cd %s; git commit -m "feat: [T987] do the thing"' % (drifted, clean),
                cwd=parent,
            ))
        )

    def test_skipped_conditional_cd_does_not_change_commit_cwd(self):
        clean = self.repo("feature/clean")
        drifted = self.repo("feature/drifted")
        self._seed_tasks(drifted, "- [ ] T987 fixture task\n")

        for command in (
            'false && cd %s; git commit -m "feat: [T987] do the thing"' % clean,
            'true || cd %s; git commit -m "feat: [T987] do the thing"' % clean,
        ):
            with self.subTest(command=command):
                self.assertDeny(
                    self.pol(_event("sys_os_shell", command, cwd=drifted)),
                    "commit-tasks-drift",
                )

        for command in (
            'false || cd %s; git commit -m "feat: [T987] do the thing"' % clean,
            'true && cd %s; git commit -m "feat: [T987] do the thing"' % clean,
        ):
            with self.subTest(command=command):
                self.assertAllow(self.pol(_event("sys_os_shell", command, cwd=drifted)))

    def test_tilde_repo_locators_follow_shell_expansion(self):
        home = self.tmpdir()
        clean = self.repo("feature/clean")
        drifted = self.repo("feature/drifted")
        self._seed_tasks(drifted, "- [ ] T987 fixture task\n")
        os.symlink(clean, os.path.join(home, "clean"))
        os.symlink(drifted, os.path.join(home, "drifted"))
        old_home = os.environ.get("HOME")
        os.environ["HOME"] = home
        try:
            for command in (
                'cd ~/drifted; git commit -m "feat: [T987] do the thing"',
                'git -C ~/drifted commit -m "feat: [T987] do the thing"',
                'git --git-dir ~/drifted/.git --work-tree ~/drifted '
                'commit -m "feat: [T987] do the thing"',
            ):
                with self.subTest(command=command):
                    self.assertDeny(
                        self.pol(_event("sys_os_shell", command, cwd=clean)),
                        "commit-tasks-drift",
                    )

            for command in (
                'cd ~/clean; git commit -m "feat: [T987] do the thing"',
                'git -C ~/clean commit -m "feat: [T987] do the thing"',
                'git -C "~/drifted" commit -m "feat: [T987] do the thing"',
            ):
                with self.subTest(command=command):
                    self.assertAllow(self.pol(_event("sys_os_shell", command, cwd=drifted)))

            self.assertDeny(
                self.pol(_event(
                    "sys_os_shell",
                    'cd "~/clean"; git commit -m "feat: [T987] do the thing"',
                    cwd=drifted,
                )),
                "commit-tasks-drift",
            )
        finally:
            if old_home is None:
                os.environ.pop("HOME", None)
            else:
                os.environ["HOME"] = old_home

    def test_grouped_commit_invocations_are_detected(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")

        for command in (
            '(git commit -m "feat: [T987] do the thing")',
            'echo $(git commit -m "feat: [T987] do the thing")',
            'cat <(git commit -m "feat: [T987] do the thing")',
        ):
            with self.subTest(command=command):
                self.assertDeny(
                    self.pol(_event("sys_os_shell", command, cwd=cwd)),
                    "commit-tasks-drift",
                )

    def test_skipped_compound_group_commit_invocations_are_not_scanned(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")

        for command in (
            'false && (echo ok; git commit -m "feat: [T987] no")',
            'true || { echo ok; git commit -m "feat: [T987] no"; }',
            'false && (echo "$(git commit -m \'feat: [T987] no\')")',
            'true || { echo "$(git commit -m \'feat: [T987] no\')"; }',
        ):
            with self.subTest(command=command):
                self.assertAllow(self.pol(_event("sys_os_shell", command, cwd=cwd)))

        for command in (
            'false || (echo ok; git commit -m "feat: [T987] do the thing")',
            'true && { echo ok; git commit -m "feat: [T987] do the thing"; }',
        ):
            with self.subTest(command=command):
                self.assertDeny(
                    self.pol(_event("sys_os_shell", command, cwd=cwd)),
                    "commit-tasks-drift",
                )

    def test_quoted_command_substitution_invocations_are_detected(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")

        for command in (
            'echo "$(git commit -m \'feat: [T987] do the thing\')"',
            'echo "`git commit -m \'feat: [T987] do the thing\'`"',
        ):
            with self.subTest(command=command):
                self.assertDeny(
                    self.pol(_event("sys_os_shell", command, cwd=cwd)),
                    "commit-tasks-drift",
                )

        for command in (
            "echo '$(git commit -m \"feat: [T987] do the thing\")'",
            "echo '`git commit -m \"feat: [T987] do the thing\"`'",
            'echo hi # $(git commit -m "feat: [T987] do the thing")',
        ):
            with self.subTest(command=command):
                self.assertAllow(self.pol(_event("sys_os_shell", command, cwd=cwd)))

    def test_quoted_command_substitution_inherits_shell_cwd(self):
        clean = self.repo("feature/clean")
        drifted = self.repo("feature/drifted")
        self._seed_tasks(drifted, "- [ ] T987 fixture task\n")

        self.assertDeny(
            self.pol(_event(
                "sys_os_shell",
                'cd %s; echo "$(git commit -m \'feat: [T987] do the thing\')"' % drifted,
                cwd=clean,
            )),
            "commit-tasks-drift",
        )

    def test_quoted_command_substitution_respects_skipped_conditional_cd(self):
        clean = self.repo("feature/clean")
        drifted = self.repo("feature/drifted")
        self._seed_tasks(drifted, "- [ ] T987 fixture task\n")

        for command in (
            'false && cd %s; echo "$(git commit -m \'feat: [T987] do the thing\')"' % clean,
            'true || cd %s; echo "$(git commit -m \'feat: [T987] do the thing\')"' % clean,
        ):
            with self.subTest(command=command):
                self.assertDeny(
                    self.pol(_event("sys_os_shell", command, cwd=drifted)),
                    "commit-tasks-drift",
                )

        for command in (
            'false || cd %s; echo "$(git commit -m \'feat: [T987] do the thing\')"' % clean,
            'true && cd %s; echo "$(git commit -m \'feat: [T987] do the thing\')"' % clean,
        ):
            with self.subTest(command=command):
                self.assertAllow(self.pol(_event("sys_os_shell", command, cwd=drifted)))

    def test_skipped_condition_command_substitution_is_not_scanned(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")

        for command in (
            'true || echo "$(git commit -m \'feat: [T987] do the thing\')"',
            'false && echo "$(git commit -m \'feat: [T987] do the thing\')"',
            'true || out=$(git commit -m "feat: [T987] do the thing")',
            'false && out=$(git commit -m "feat: [T987] do the thing")',
        ):
            with self.subTest(command=command):
                self.assertAllow(self.pol(_event("sys_os_shell", command, cwd=cwd)))

        for command in (
            'false || echo "$(git commit -m \'feat: [T987] do the thing\')"',
            'true && echo "$(git commit -m \'feat: [T987] do the thing\')"',
        ):
            with self.subTest(command=command):
                self.assertDeny(
                    self.pol(_event("sys_os_shell", command, cwd=cwd)),
                    "commit-tasks-drift",
                )

    def test_env_option_wrapped_commit_is_detected(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")

        for command in (
            'env -i git commit -m "feat: [T987] do the thing"',
            'env -u PATH git commit -m "feat: [T987] do the thing"',
            'env -- git commit -m "feat: [T987] do the thing"',
        ):
            with self.subTest(command=command):
                self.assertDeny(
                    self.pol(_event("sys_os_shell", command, cwd=cwd)),
                    "commit-tasks-drift",
                )

    def test_env_chdir_wrapped_commit_reads_target_repo_tasks(self):
        clean = self.repo("feature/clean")
        drifted = self.repo("feature/drifted")
        self._seed_tasks(drifted, "- [ ] T987 fixture task\n")

        self.assertDeny(
            self.pol(_event(
                "sys_os_shell",
                'env -C %s git commit -m "feat: [T987] do the thing"' % drifted,
                cwd=clean,
            )),
            "commit-tasks-drift",
        )
        self.assertAllow(
            self.pol(_event(
                "sys_os_shell",
                'env -C %s git commit -m "feat: [T987] do the thing"' % clean,
                cwd=drifted,
            ))
        )

    def test_env_chdir_does_not_persist_after_wrapped_command(self):
        clean = self.repo("feature/clean")
        drifted = self.repo("feature/drifted")
        self._seed_tasks(drifted, "- [ ] T987 fixture task\n")

        self.assertDeny(
            self.pol(_event(
                "sys_os_shell",
                'env -C %s true; git commit -m "feat: [T987] do the thing"' % clean,
                cwd=drifted,
            )),
            "commit-tasks-drift",
        )
        self.assertAllow(
            self.pol(_event(
                "sys_os_shell",
                'env -C %s true; git commit -m "feat: [T987] do the thing"' % drifted,
                cwd=clean,
            ))
        )

    def test_env_split_string_preserves_following_argv(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")

        for command in (
            "env -S 'git commit' -m 'feat: [T987] do the thing'",
            "env --split-string='git commit' -m 'feat: [T987] do the thing'",
            "env -S 'git' commit -m 'feat: [T987] do the thing'",
        ):
            with self.subTest(command=command):
                self.assertDeny(
                    self.pol(_event("sys_os_shell", command, cwd=cwd)),
                    "commit-tasks-drift",
                )

    def test_line_continuation_keeps_commit_args(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")

        self.assertDeny(
            self.pol(_event(
                "sys_os_shell",
                'git commit \\\n  -m "feat: [T987] do the thing"',
                cwd=cwd,
            )),
            "commit-tasks-drift",
        )

    def test_task_id_outside_commit_message_fails_open(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")

        self.assertAllow(
            self.pol(_event("sys_os_shell", 'git commit -m "chore: no task" && echo "[T987]"', cwd=cwd))
        )

    def test_git_token_as_argument_fails_open(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")

        self.assertAllow(
            self.pol(_event("sys_os_shell", 'echo git commit -m "feat: [T987] do the thing"', cwd=cwd))
        )

    def test_dry_run_commit_fails_open(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")

        for command in (
            'git commit --dry-run -m "feat: [T987] do the thing"',
            'git commit -m "feat: [T987] do the thing" --dry-run',
            'git commit --no-dry-run --dry-run -m "feat: [T987] do the thing"',
        ):
            with self.subTest(command=command):
                self.assertAllow(self.pol(_event("sys_os_shell", command, cwd=cwd)))

    def test_status_format_commit_modes_fail_open(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")

        for command in (
            'git commit --porcelain -m "feat: [T987] do the thing"',
            'git commit --short -m "feat: [T987] do the thing"',
            'git commit --long -m "feat: [T987] do the thing"',
            'git commit --porcelain --no-dry-run -m "feat: [T987] do the thing"',
        ):
            with self.subTest(command=command):
                self.assertAllow(self.pol(_event("sys_os_shell", command, cwd=cwd)))

    def test_dry_run_like_message_and_override_are_real_commits(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")

        for command in (
            'git commit -m "feat: [T987] do the thing" -m --dry-run',
            'git commit --dry-run --no-dry-run -m "feat: [T987] do the thing"',
            'git commit -am --dry-run -m "feat: [T987] do the thing"',
        ):
            with self.subTest(command=command):
                self.assertDeny(
                    self.pol(_event("sys_os_shell", command, cwd=cwd)),
                    "commit-tasks-drift",
                )

    def test_commit_trailer_task_id_denied(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")

        for command in (
            'git commit -m "feat" --trailer "Task=[T987]"',
            'git commit -m "feat" --trailer=Task=[T987]',
        ):
            with self.subTest(command=command):
                self.assertDeny(
                    self.pol(_event("sys_os_shell", command, cwd=cwd)),
                    "commit-tasks-drift",
                )

    def test_commit_message_file_task_id_denied(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        with open(os.path.join(cwd, "message.txt"), "w") as f:
            f.write("feat: [T987] do the thing\n")

        for command in (
            "git commit -F message.txt",
            "git commit --file=message.txt",
        ):
            with self.subTest(command=command):
                self.assertDeny(
                    self.pol(_event("sys_os_shell", command, cwd=cwd)),
                    "commit-tasks-drift",
                )

    def test_failed_cd_fallback_commit_uses_original_cwd(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")

        self.assertDeny(
            self.pol(_event(
                "sys_os_shell",
                'cd /no/such || git commit -m "feat: [T987] do the thing"',
                cwd=cwd,
            )),
            "commit-tasks-drift",
        )

    def test_unknown_status_condition_scans_possible_commit(self):
        cwd = self.repo("feature/x")
        self._seed_tasks(cwd, "- [ ] T987 fixture task\n")

        for command in (
            'test -f /no/such || git commit -m "feat: [T987] do the thing"',
            'git commit -m "chore: no task" || git commit -m "feat: [T987] do the thing"',
        ):
            with self.subTest(command=command):
                self.assertDeny(
                    self.pol(_event("sys_os_shell", command, cwd=cwd)),
                    "commit-tasks-drift",
                )

    def test_tasks_md_in_message_does_not_switch_to_worktree_view(self):
        cwd = self.repo("feature/x")
        path = self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        with open(path, "w") as f:
            f.write("- [x] T987 fixture task\n")
        _git(["add", "specs/010-fixture/tasks.md"], cwd)
        with open(path, "w") as f:
            f.write("- [ ] T987 fixture task\n")

        self.assertAllow(
            self.pol(_event("sys_os_shell", 'git commit -m "feat: [T987] update tasks.md"', cwd=cwd))
        )

    def test_non_live_tasks_pathspec_reads_head_tasks_view(self):
        cwd = self.repo("feature/x")
        path = self._seed_tasks(cwd, "- [ ] T987 fixture task\n")
        docs_dir = os.path.join(cwd, "docs", "examples", "fixture")
        os.makedirs(docs_dir)
        docs_path = os.path.join(docs_dir, "tasks.md")
        with open(docs_path, "w") as f:
            f.write("example tasks\n")
        _git(["add", "docs/examples/fixture/tasks.md"], cwd)
        _git(["commit", "-q", "-m", "seed example tasks"], cwd)

        with open(path, "w") as f:
            f.write("- [x] T987 fixture task\n")
        _git(["add", "specs/010-fixture/tasks.md"], cwd)
        with open(docs_path, "w") as f:
            f.write("example tasks changed\n")

        self.assertDeny(
            self.pol(_event(
                "sys_os_shell",
                'git commit docs/examples/fixture/tasks.md -m "feat: [T987] update docs tasks"',
                cwd=cwd,
            )),
            "commit-tasks-drift",
        )

    def test_nested_tasks_file_is_not_live_tasks_state(self):
        cwd = self.repo("feature/x")
        nested_dir = os.path.join(cwd, "specs", "010-fixture", "nested")
        os.makedirs(nested_dir)
        with open(os.path.join(nested_dir, "tasks.md"), "w") as f:
            f.write("- [ ] T987 nested fixture task\n")
        _git(["add", "specs/010-fixture/nested/tasks.md"], cwd)
        _git(["commit", "-q", "-m", "seed nested tasks file"], cwd)

        self.assertAllow(
            self.pol(_event("sys_os_shell", 'git commit -m "feat: [T987] do the thing"', cwd=cwd))
        )


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


# ── #138 (T621) — global-option / cwd evasions of rules 2/3/4 ─────────────────────────

class TestGlobalOptionAndCwdEvasions(GuardTestBase):
    """Parity with guard.test.sh's "#138 (T621)" block — same DW1–DW4 behavior."""

    def setUp(self):
        super().setUp()
        self.pol = guard.make_guard_tool_call(base_branch="main")

    # DW1 — a leading git global option no longer slips the bulk-staging / commit-push
    # matchers (the bare-subcommand form already DENYs).
    def test_dw1_dash_C_add_all_denied(self):
        cwd = self.repo("feature/x")
        self.assertDeny(self.pol(_event("sys_os_shell",
            "git -C %s add --all" % cwd, cwd=cwd)), "git-add-all")

    def test_dw1_dash_c_config_add_all_denied(self):
        cwd = self.repo("feature/x")
        self.assertDeny(self.pol(_event("sys_os_shell",
            "git -c user.email=t@t.test add --all", cwd=cwd)))

    def test_dw1_dash_C_add_dot_denied(self):
        cwd = self.repo("feature/x")
        self.assertDeny(self.pol(_event("sys_os_shell",
            "git -C %s add ." % cwd, cwd=cwd)))

    def test_dw1_git_dir_commit_on_base_denied(self):
        cwd = self.repo("main")
        self.assertDeny(self.pol(_event("sys_os_shell",
            "git --git-dir=%s/.git commit -m x" % cwd, cwd=cwd)), "commit-push-on-base")

    def test_dw1_dash_c_commit_on_base_denied(self):
        cwd = self.repo("main")
        self.assertDeny(self.pol(_event("sys_os_shell",
            "git -c user.name=t commit -m x", cwd=cwd)))

    def test_dw1_dash_C_push_refspec_main_denied(self):
        cwd = self.repo("feature/x")
        self.assertDeny(self.pol(_event("sys_os_shell",
            "git -C %s push origin HEAD:main" % cwd, cwd=cwd)), "push-refspec-base")

    # DW1 control (penalizes over-block): a -C-prefixed single-file add is still ALLOWED —
    # a "deny anything containing -C" shortcut would fail here.
    def test_dw1_control_dash_C_single_file_allowed(self):
        cwd = self.repo("feature/x")
        self.assertAllow(self.pol(_event("sys_os_shell",
            "git -C %s add src/one.py" % cwd, cwd=cwd)))

    # DW2 — rule 3 resolves the EFFECTIVE repo (the -C / cd && target), not only the event
    # cwd. Paired (both directions) so neither "always deny" nor "always allow" passes.
    def test_dw2_dash_C_target_on_base_denied(self):
        feature = self.repo("feature/x")
        base = self.repo("main")
        self.assertDeny(self.pol(_event("sys_os_shell",
            "git -C %s commit -m x" % base, cwd=feature)), "commit-push-on-base")

    def test_dw2_cd_target_on_base_denied(self):
        feature = self.repo("feature/x")
        base = self.repo("main")
        self.assertDeny(self.pol(_event("sys_os_shell",
            "cd %s && git commit -m x" % base, cwd=feature)))

    def test_dw2_dash_C_target_off_base_allowed(self):
        base = self.repo("main")
        feature = self.repo("feature/x")
        self.assertAllow(self.pol(_event("sys_os_shell",
            "git -C %s commit -m x" % feature, cwd=base)))

    # DW2 fallback preserves strength: an unreadable `cd <gone>` target falls back to the
    # event-cwd branch (base) -> still DENY (no new false-ALLOW).
    def test_dw2_cd_nonexistent_falls_back_to_event_cwd(self):
        base = self.repo("main")
        gone = os.path.join(self.tmpdir(), "does-not-exist")
        self.assertDeny(self.pol(_event("sys_os_shell",
            "cd %s && git commit -m x" % gone, cwd=base)))

    # DW3 — a genuinely parse-ambiguous form (an unrecognized leading option that ends the
    # global run) still abstains (ALLOW), while the DW1/DW2 forms above still DENY — so the
    # "classify everything as ambiguous -> ALLOW" shortcut fails DW1/DW2.
    def test_dw3_unknown_leading_option_add_abstains(self):
        cwd = self.repo("feature/x")
        self.assertAllow(self.pol(_event("sys_os_shell",
            "git --unknown-flag add --all", cwd=cwd)))

    def test_dw3_unknown_leading_option_commit_abstains(self):
        cwd = self.repo("main")
        self.assertAllow(self.pol(_event("sys_os_shell",
            "git --unknown-flag commit -m x", cwd=cwd)))

    # DW4 — the trailing-slash `git add ./` dot-operand variant DENYs; `git add ./path`
    # (a specific file) stays ALLOWED.
    def test_dw4_add_dot_slash_denied(self):
        cwd = self.repo("feature/x")
        self.assertDeny(self.pol(_event("sys_os_shell", "git add ./", cwd=cwd)))

    def test_dw4_add_dot_slash_path_allowed(self):
        cwd = self.repo("feature/x")
        self.assertAllow(self.pol(_event("sys_os_shell", "git add ./src/a.py", cwd=cwd)))

    # P2 (PR #173, Codex) — the repo-locating -C is read from the SAME `git … commit`
    # invocation, NOT an unrelated leading `git -C <other> …`. Paired both directions:
    # event cwd on base + a leading -C at the feature repo -> the commit lands on base.
    def test_p2_unrelated_leading_dash_C_ignored_denied(self):
        base = self.repo("main")
        feature = self.repo("feature/x")
        self.assertDeny(self.pol(_event("sys_os_shell",
            "git -C %s status && git commit -m x" % feature, cwd=base)),
            "commit-push-on-base")

    def test_p2_unrelated_leading_dash_C_commit_on_feature_allowed(self):
        # event cwd on feature + a leading -C at the base repo -> the commit still acts on
        # the feature repo -> ALLOW (an old "first -C in the line" reader would over-block).
        feature = self.repo("feature/x")
        base = self.repo("main")
        self.assertAllow(self.pol(_event("sys_os_shell",
            "git -C %s status && git commit -m x" % base, cwd=feature)))

    def test_p2_commit_reuse_message_dash_C_not_misread(self):
        # A non-global reuse-message `git commit -C HEAD` is not misread as a repo dir: the
        # -C is after the subcommand, outside the global run, so it never flips the read.
        cwd = self.repo("feature/x")
        self.assertAllow(self.pol(_event("sys_os_shell", "git commit -C HEAD", cwd=cwd)))

    def test_p2_decoy_commit_prefix_does_not_capture_locator(self):
        # A `git commitx` decoy sharing the `commit` prefix must NOT capture the locator: the
        # real `git -C <base> commit` still resolves to base -> DENY. (A boundary-less locator
        # would latch onto the decoy, find no -C, and fall back to the feature event cwd.)
        feature = self.repo("feature/x")
        base = self.repo("main")
        self.assertDeny(self.pol(_event("sys_os_shell",
            "git commitx && git -C %s commit -m x" % base, cwd=feature)),
            "commit-push-on-base")

    # H1 (PR #173, craft) — rule 3 resolves --git-dir for the branch, not only -C / cd.
    # Paired both directions, so it proves resolution rather than a "deny anything with
    # --git-dir" shortcut: event cwd on feature but --git-dir targets the base repo -> DENY.
    def test_h1_git_dir_target_on_base_denied(self):
        feature = self.repo("feature/x")
        base = self.repo("main")
        self.assertDeny(self.pol(_event("sys_os_shell",
            "git --git-dir=%s/.git --work-tree=%s commit -m x" % (base, base), cwd=feature)),
            "commit-push-on-base")

    def test_h1_git_dir_target_off_base_allowed(self):
        # event cwd on base but --git-dir targets the feature repo -> ALLOW.
        base = self.repo("main")
        feature = self.repo("feature/x")
        self.assertAllow(self.pol(_event("sys_os_shell",
            "git --git-dir=%s/.git commit -m x" % feature, cwd=base)))

    # H2 (PR #173, craft) — a RELATIVE -C must resolve against the EVENT cwd, not the policy
    # process cwd. The -C is relative to the feature event cwd; the process runs from a
    # NESTED neutral dir (not a sibling of the temp repos), so the relative `../<base>` does
    # NOT accidentally resolve from the process cwd — only an event-cwd resolution finds the
    # base repo. (Resolving against the process cwd, the old bug, abstains -> ALLOW.)
    def test_h2_relative_dash_C_resolves_against_event_cwd(self):
        feature = self.repo("feature/x")
        base = self.repo("main")
        rel = os.path.relpath(base, feature)
        neutral = os.path.join(self.tmpdir(), "deep")
        os.makedirs(neutral)
        old = os.getcwd()
        os.chdir(neutral)
        try:
            self.assertDeny(self.pol(_event("sys_os_shell",
                "git -C %s commit -m x" % rel, cwd=feature)), "commit-push-on-base")
        finally:
            os.chdir(old)


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


# ── Rule 5 — strong-floored reviewers below the strong tier ──────────────────────────

class TestStrongFloor(GuardTestBase):
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

    # The spec-quality reviewer is floored too (issue #147) — same arms as the
    # constitution reviewer, mirroring guard.sh's generalized rule 5.
    def test_spec_quality_absent_model_denied(self):
        self.assertDeny(
            self.pol(self._dispatch(model=None, reviewer="spec-quality-auditor")),
            "strong-floor-no-model",
        )

    def test_spec_quality_below_strong_denied(self):
        self.assertDeny(
            self.pol(self._dispatch(model="cheap-3-3", reviewer="spec-quality-auditor")),
            "strong-floor-below",
        )

    def test_spec_quality_strong_allowed(self):
        self.assertAllow(self.pol(self._dispatch(model="strong-7-7", reviewer="spec-quality-auditor")))

    def test_acceptance_reviewer_not_floored(self):
        # The `spec-quality` needle must NOT collide with the acceptance reviewer
        # `spec-auditor` — the control proving substring matching stays precise.
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


# ── [edit guard] — delta-based fix-forward lint reject ───────────────────────────────

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

    def _result(self, target, **kw):
        # The edit guard fires only on a POST-WRITE phase (DEFAULT_RESULT_PHASES); the test
        # writes the file first, then delivers the result-phase event (the on-disk file
        # reflects the edit). A pre-write `tool_call` is covered by its own abstain test.
        return _event(target, type_="tool_result", **kw)

    def test_new_diagnostic_denied(self):
        cwd = self.repo("feature/x")
        p = self._commit(cwd, "f.txt", "clean\n")       # baseline 0 BANG
        self._write(p, "clean\nBANG\n")                 # edit adds 1
        self.assertDeny(self.pol(self._result("sys_os_edit", path=p, cwd=cwd)),
                        "edit-lint-regression")

    def test_no_new_diagnostic_allowed(self):
        cwd = self.repo("feature/x")
        p = self._commit(cwd, "f.txt", "clean\n")
        self._write(p, "still clean\n")
        self.assertAllow(self.pol(self._result("sys_os_edit", path=p, cwd=cwd)))

    def test_preexisting_diagnostic_not_blocking(self):
        # Baseline already has a BANG; an edit that keeps the count is allowed.
        cwd = self.repo("feature/x")
        p = self._commit(cwd, "f.txt", "BANG\nold\n")   # baseline 1
        self._write(p, "BANG\nnew line\n")              # still 1
        self.assertAllow(self.pol(self._result("sys_os_edit", path=p, cwd=cwd)))

    def test_pre_write_tool_call_abstains_on_dirty_file(self):
        # Regression (PR #137: Codex P2 / craft H1). A file already dirty ABOVE its HEAD
        # baseline, edited again to fix it: on the PRE-write `tool_call` phase the on-disk
        # file is still the dirty pre-edit content, so a delta check would DENY the fix
        # before it runs. The guard must abstain on every pre-write phase.
        cwd = self.repo("feature/x")
        p = self._commit(cwd, "f.txt", "clean\n")       # baseline 0 BANG
        self._write(p, "BANG\nBANG\n")                  # dirty: 2 BANG, above baseline
        # tool_call (pre-write) must NOT block, even though current(2) > baseline(0).
        self.assertAllow(self.pol(_event("sys_os_edit", path=p, cwd=cwd, type_="tool_call")))
        # request (the other documented, non-post-write phase) must also abstain.
        self.assertAllow(self.pol(_event("sys_os_edit", path=p, cwd=cwd, type_="request")))

    def test_result_phase_param_override(self):
        # T620 pins the real post-write phase via result_phases; the guard fires on it.
        pol = guard.make_edit_guard(checkers=self.checkers, result_phases=("on_write_done",))
        cwd = self.repo("feature/x")
        p = self._commit(cwd, "f.txt", "clean\n")
        self._write(p, "clean\nBANG\n")
        self.assertDeny(pol(_event("sys_os_edit", path=p, cwd=cwd, type_="on_write_done")),
                        "edit-lint-regression")
        # …and abstains on the default tool_result once reconfigured away from it.
        self.assertAllow(pol(_event("sys_os_edit", path=p, cwd=cwd, type_="tool_result")))

    def test_out_of_repo_fails_open(self):
        cwd = self.repo("feature/x")
        outside = os.path.join(self.tmpdir(), "x.txt")
        self._write(outside, "BANG\nBANG\n")
        self.assertAllow(self.pol(self._result("sys_os_edit", path=outside, cwd=cwd)))

    def test_no_checker_for_type_fails_open(self):
        cwd = self.repo("feature/x")
        p = self._commit(cwd, "f.md", "clean\n")        # *.md not in self.checkers
        self._write(p, "BANG\n")
        self.assertAllow(self.pol(self._result("sys_os_edit", path=p, cwd=cwd)))

    def test_non_edit_tool_ignored(self):
        cwd = self.repo("feature/x")
        self.assertAllow(self.pol(self._result("sys_os_shell", command="echo hi", cwd=cwd)))

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
            # A post-write phase so the policy reaches the (monkeypatched-to-raise) checker
            # resolution; the try/except must still abstain.
            self.assertIsNone(pol(_event("sys_os_edit", path=p, cwd=cwd, type_="tool_result")))
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


# ── Registry discovery surface (the declared extension contract) ─────────────────────

class TestRegistry(GuardTestBase):
    """Pin ``registry.POLICY_REGISTRY`` (PR #137: craft L3). Every other test imports the
    factories directly, but Omnigent discovers them through the registry, so a handler
    typo / rename / kind drift there would pass the rest of the suite untouched. These load
    each descriptor exactly as Omnigent would — resolve the dotted handler, instantiate the
    factory, drive one event through the resulting policy."""

    @staticmethod
    def _resolve(dotted):
        """Import a 'pkg.mod.attr' handler the way a policy loader does (raises on drift)."""
        mod, _, attr = dotted.rpartition(".")
        return getattr(importlib.import_module(mod), attr)

    def test_every_handler_resolves_and_instantiates(self):
        from creance_omnigent import registry
        self.assertTrue(registry.POLICY_REGISTRY, "POLICY_REGISTRY is empty")
        for d in registry.POLICY_REGISTRY:
            for key in ("handler", "kind", "name", "description", "params_schema"):
                self.assertIn(key, d, "registry entry missing %r: %r" % (key, d))
            self.assertEqual(d["kind"], "factory", "unexpected kind: %r" % (d,))
            factory = self._resolve(d["handler"])           # raises if the path is wrong
            self.assertTrue(callable(factory), "handler not callable: %s" % d["handler"])
            policy = factory()                              # instantiate with declared defaults
            self.assertTrue(callable(policy),
                            "factory returned no policy: %s" % d["handler"])
            # Closed object schema — no unbounded factory-config surface.
            self.assertEqual(d["params_schema"].get("additionalProperties"), False,
                             "params_schema not closed: %s" % d["handler"])

    def test_registered_policy_denies_a_banned_action(self):
        # Exercise one event through every registry-resolved policy (no hardcoded handler
        # name): a banned action must be caught by the discovery path, not just by a direct
        # import elsewhere in this file.
        from creance_omnigent import registry
        cwd = self.repo("feature/x")
        ev = _event("sys_os_shell", "git add .", cwd=cwd)
        responses = [self._resolve(d["handler"])()(ev) for d in registry.POLICY_REGISTRY]
        denies = [r for r in responses
                  if isinstance(r, dict) and r.get("result") == guard.DENY]
        self.assertTrue(denies, "no registered policy DENYed `git add .` via the registry")
        self.assertIn("git-add-all", denies[0]["reason"])


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
