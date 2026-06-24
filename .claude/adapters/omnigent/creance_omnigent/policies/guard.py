"""Omnigent [guard] / [edit guard] policy port.

This is the **Omnigent adapter** implementation of the runtime-neutral `[guard]` rules
specified in `.claude/workflow/README.md` -> "The [guard] rules". The active adapter for
this repo is still Claude Code (`.claude/hooks/guard.sh`); this module is the Omnigent
binding, unit-tested here and wired live on a real driver at T620.

Interface (grounded in Omnigent `docs/POLICIES.md`, verified 2026-06-23):

    def policy(event) -> {"result": "ALLOW"|"DENY"|"ASK", "reason": str} | None

A policy receives an ``event`` dict and returns a response dict, or ``None`` to abstain.
``event`` carries ``type`` (phase, e.g. ``"tool_call"``), ``target`` (tool name), and
``data`` -> ``{"name", "arguments"}``. Policies become discoverable by exporting
``POLICY_REGISTRY`` (see ``creance_omnigent.registry``) and listing the module under
``policy_modules:`` in the server config. The registered handlers below use Omnigent's
**factory** kind (a configured callable), so the base branch, model table, and edit-tool
checker map are all swappable without touching this code.

Fail-open contract (`workflow/README.md` -> "The [guard] rules": *"fails open: any
uncertainty -> allow"*). Omnigent's `docs/POLICIES.md` does **not** document whether a
policy that raises is treated as fail-open or fail-closed, so this port does not rely on
the framework default: every entry point wraps its logic in ``try/except`` and returns
``None`` (abstain) on **any** exception or uncertainty. ``test_guard.py`` asserts this.

The guard only ever returns ``DENY`` or abstains (``None``); it never force-``ALLOW``s.
Abstaining lets the rest of the policy chain (and the ``[permission allowlist]`` role)
decide, which is exactly the neutral "allow everything else" posture.

UNVERIFIED upstream facts (pinned on the live driver at T620, never assumed) are flagged
inline with ``UNVERIFIED:`` and surfaced in ``adapters/omnigent/README.md``.
"""

from __future__ import annotations

import fnmatch
import os
import re
import shutil
import subprocess
import tempfile

# Response result strings — the only valid values per docs/POLICIES.md.
DENY = "DENY"
ALLOW = "ALLOW"
ASK = "ASK"

# Confirmed OS tool target names (docs/POLICIES.md, verified 2026-06-23).
EDIT_TOOLS = ("sys_os_edit", "sys_os_write")
SHELL_TOOLS = ("sys_os_shell",)

# UNVERIFIED: the sub-agent dispatch tool name (README binds it to `sys_session_send`) and
# the argument keys that carry the dispatched reviewer's identity / model. Parameterised on
# the factory so T620 can pin them on the live driver without a code change.
DEFAULT_DISPATCH_TOOLS = ("sys_session_send",)
DEFAULT_REVIEWER_KEYS = (
    "agent", "subagent", "subagent_type", "reviewer", "to", "target_agent", "purpose",
)
# The strong-floored reviewers (workflow/README.md rule 5): substring needles identifying a
# constitution- or spec-quality-reviewer dispatch. `spec-quality` (NOT `spec`) so the
# acceptance reviewer `spec-auditor` is left un-floored — mirrors guard.sh's exact-match
# control case (issue #147).
DEFAULT_REVIEWER_MATCH = ("constitution", "spec-quality")
DEFAULT_MODEL_KEYS = ("model",)
# UNVERIFIED: the argument key carrying an edit's target path.
DEFAULT_EDIT_PATH_KEYS = (
    "path", "file_path", "file", "target_file", "filename", "filepath",
)
# UNVERIFIED: the event phase(s) on which an edit's RESULT is observable on disk (a
# post-write firing). docs/POLICIES.md documents `tool_call` (pre-write) and `request`
# only — no post-write phase — so the real name is pinned on the live driver at T620. The
# [edit guard] fires ONLY on these phases and abstains on every other (notably the pre-write
# `tool_call`): a delta measured before the write reflects the file's pre-edit state, not
# the edit (see the [edit guard] PHASE NOTE and make_edit_guard).
DEFAULT_RESULT_PHASES = ("tool_result",)

_BACKTICK = re.compile(r"`([^`]+)`")


# --------------------------------------------------------------------------------------
# Response + event helpers
# --------------------------------------------------------------------------------------

def _deny(rule, message):
    """A DENY response, schema-faithful (only ``result`` + ``reason``)."""
    return {"result": DENY, "reason": "[{}] {}".format(rule, message)}


def _args(event):
    data = event.get("data") if isinstance(event, dict) else None
    if isinstance(data, dict):
        a = data.get("arguments")
        if isinstance(a, dict):
            return a
    return {}


def _data_name(event):
    data = event.get("data") if isinstance(event, dict) else None
    if isinstance(data, dict):
        return data.get("name")
    return None


def _target(event):
    return event.get("target") or _data_name(event)


def _command(event):
    c = _args(event).get("command")
    return c if isinstance(c, str) else ""


def _event_cwd(event):
    """The directory git rules resolve against. Explicit-context first (an event-carried
    cwd), falling back to the policy process cwd (the worktree, on a live driver)."""
    ctx = event.get("context") if isinstance(event, dict) else None
    if isinstance(ctx, dict):
        c = ctx.get("cwd") or ctx.get("working_dir")
        if isinstance(c, str) and c:
            return c
    return os.getcwd()


def _edit_path(event, keys=DEFAULT_EDIT_PATH_KEYS):
    args = _args(event)
    for k in keys:
        v = args.get(k)
        if isinstance(v, str) and v:
            return v
    return None


# --------------------------------------------------------------------------------------
# git helpers (git is the harness's universal VCS substrate — constitution principle 1
# exempts it from the runtime-neutral ban; it may be named directly).
# --------------------------------------------------------------------------------------

def _git(args, cwd):
    """Run git in ``cwd``; return stdout on success, ``None`` on any failure (fail open)."""
    try:
        r = subprocess.run(
            ["git", *args], cwd=cwd, capture_output=True, text=True, timeout=10,
        )
    except Exception:
        return None
    if r.returncode != 0:
        return None
    return r.stdout


def _branch(cwd):
    out = _git(["branch", "--show-current"], cwd)
    return out.strip() if out is not None else None


def _repo_root(cwd):
    out = _git(["rev-parse", "--show-toplevel"], cwd)
    return out.strip() if out else None


def _in_repo(file_path, cwd):
    """Tri-state: True if ``file_path`` is confirmed inside the repo, False if confirmed
    outside, None if undeterminable (caller fails open). Out-of-repo writes (e.g. the
    triage inbox) are allowed — only a confirmed in-repo target is blockable."""
    root = _repo_root(cwd)
    if not root or not file_path:
        return None
    root = os.path.realpath(root)
    fp = file_path if os.path.isabs(file_path) else os.path.join(cwd, file_path)
    fp = os.path.realpath(fp)
    try:
        return os.path.commonpath([root, fp]) == root
    except ValueError:  # different drives / relative-vs-absolute mismatch
        return None


# --------------------------------------------------------------------------------------
# Rule 1 — file edit while on the base branch (in-repo target)
# --------------------------------------------------------------------------------------

def _rule_edit_on_base(event, base, cwd, path_keys=DEFAULT_EDIT_PATH_KEYS):
    fp = _edit_path(event, path_keys)
    if not fp:
        return None  # no determinable target -> fail open
    if _branch(cwd) != base:
        return None  # not on base (or branch undeterminable) -> fail open
    if _in_repo(fp, cwd) is True:
        return _deny(
            "edit-on-base",
            "file edit on the base branch '{}' (target: {}). Create a feature branch "
            "first; never edit on the base branch.".format(base, fp),
        )
    return None


# --------------------------------------------------------------------------------------
# Rules 2/3/4/6 — shell-command rules (ported from guard.sh, operating on the command
# string). Each takes a uniform (command, base, cwd) signature; unused args are ignored.
# --------------------------------------------------------------------------------------

# Rule 2 — staging the entire tree at once.
_RE_ADD_ALL = re.compile(r"git\s+add\s+(?:--all|-A|\.)(?:\s|;|&|\||\"|$)")


def _rule_bulk_staging(command, base=None, cwd=None):
    if _RE_ADD_ALL.search(command):
        return _deny(
            "git-add-all",
            "`git add .` / -A / --all stages the whole tree. Stage specific files: "
            "`git add <path1> <path2>`.",
        )
    return None


# Rule 3 — commit / push while on the base branch.
_RE_COMMIT_PUSH = re.compile(r"git\s+(?:commit|push)(?:\s|;|&|\||\"|$)")


def _rule_commit_push_base(command, base, cwd):
    if _RE_COMMIT_PUSH.search(command) and _branch(cwd) == base:
        return _deny(
            "commit-push-on-base",
            "never commit or push while on the base branch '{}'. Work on a feature "
            "branch and open a PR.".format(base),
        )
    return None


# Rule 4 — a push whose refspec targets the base branch, from ANY current branch.
# `[^";&|]*` confines the match to a single command (so `git push <branch> && gh ...`
# is untouched); the destination ref is matched after a ':' or whitespace.
def _rule_push_refspec_base(command, base, cwd=None):
    pat = (
        r"git\s+push[^\";&|]*(?::|\s)(?:refs/heads/)?"
        + re.escape(base)
        + r"(?:[^A-Za-z0-9_./-]|$)"
    )
    if re.search(pat, command):
        return _deny(
            "push-refspec-base",
            "this push targets the base branch '{}' (refspec). Push the feature branch "
            "and open a PR instead.".format(base),
        )
    return None


# Rule 6 — a self-colliding in-place text substitution: the delimiter ('/' or '#') also
# appears in the URL operand, ending the expression early and silently blanking output
# (the PR-body-blank class). Per-delimiter, scoped to one command, fail open on anything
# ambiguous — a direct port of guard.sh rule 6.
_SED_PRE = r"(?:^|[^A-Za-z0-9_])sed[^;&|]*[^A-Za-z_]"
_RE_SED_SLASH = re.compile(_SED_PRE + r"s/[^/'\" ]*/https?://")
_RE_SED_HASH = re.compile(_SED_PRE + r"s#[^#'\";]*#[^#'\";]*http[^#'\";]*#[^#'\";]*#")


def _rule_sed_collision(command, base=None, cwd=None):
    if _RE_SED_SLASH.search(command) or _RE_SED_HASH.search(command):
        return _deny(
            "sed-url-delimiter-collision",
            "this in-place sed substitution's delimiter ('/' or '#') also occurs in the "
            "URL it substitutes, which can silently blank the output. Use a delimiter "
            "absent from the URL (e.g. 's@...@...@' or 's|...|...|') and compose bodies "
            "via a file, then verify the result is non-empty.",
        )
    return None


_SHELL_RULES = (
    _rule_bulk_staging,
    _rule_commit_push_base,
    _rule_push_refspec_base,
    _rule_sed_collision,
)


# --------------------------------------------------------------------------------------
# Rule 5 — constitution [reviewer] dispatched below the [strong tier] floor.
# The model table is the ONLY model-naming surface; tiers are resolved from it at
# enforcement time, never hardcoded here (the one-line-model-swap property).
# --------------------------------------------------------------------------------------

def _default_models_file():
    env = os.environ.get("CREANCE_OMNIGENT_MODELS_FILE")
    if env:
        return env
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.normpath(os.path.join(here, "..", "..", "MODELS.md"))


def _tier_models(models_file, tier):
    """Version-bearing model ids (a hyphen AND a digit — the same shape the neutral-core
    check extracts) from the FIRST row labelled ``**[<tier> tier]**``. Excludes harness
    names like ``claude-sdk`` (hyphen, no digit). [] on any error -> caller fails open."""
    try:
        with open(models_file, encoding="utf-8") as f:
            label = re.compile(r"\*\*\[" + re.escape(tier) + r"\s+tier\]\*\*", re.I)
            for line in f:
                if label.search(line):
                    toks = _BACKTICK.findall(line)
                    return [t for t in toks if "-" in t and any(c.isdigit() for c in t)]
    except Exception:
        return []
    return []


def _model_in(model, names):
    return any(n and n in model for n in names)


def _rank_below_strong(model, models_file):
    """'deny' if ``model`` is below the strong floor, 'ok' if at/above, None if the table
    is unreadable or the model is unrankable (both fail open, per the neutral rule)."""
    strong = _tier_models(models_file, "strong")
    if not strong:
        return None
    if _model_in(model, strong) or _model_in(model, _tier_models(models_file, "frontier")):
        return "ok"
    if _model_in(model, _tier_models(models_file, "cheap")):
        return "deny"
    return None


def _is_strong_floored_dispatch(args, reviewer_keys, reviewer_match):
    needles = (reviewer_match,) if isinstance(reviewer_match, str) else tuple(reviewer_match)
    needles = [n.lower() for n in needles if n]
    for k in reviewer_keys:
        v = args.get(k)
        if isinstance(v, str):
            vlow = v.lower()
            if any(needle in vlow for needle in needles):
                return True
    return False


def _extract_model(args, model_keys):
    for k in model_keys:
        v = args.get(k)
        if isinstance(v, str) and v:
            return v
    ex = args.get("executor")
    if isinstance(ex, dict):
        for k in model_keys:
            v = ex.get(k)
            if isinstance(v, str) and v:
                return v
    return None


def _rule_strong_floor(event, models_file, reviewer_keys, reviewer_match, model_keys):
    args = _args(event)
    if not _is_strong_floored_dispatch(args, reviewer_keys, reviewer_match):
        return None
    model = _extract_model(args, model_keys)
    if not model:
        return _deny(
            "strong-floor-no-model",
            "a strong-floored reviewer dispatched without a model — it would inherit the "
            "session model and can silently break the [strong tier] floor. Pass the "
            "strong-tier (or above) model from MODELS.md explicitly.",
        )
    if _rank_below_strong(model, models_file) == "deny":
        return _deny(
            "strong-floor-below",
            "a strong-floored reviewer dispatched below the [strong tier] floor "
            "(model: '{}'). It never downgrades — pass a model at-or-above the "
            "strong-tier row of MODELS.md.".format(model),
        )
    return None


# --------------------------------------------------------------------------------------
# [edit guard] (rule 7) — delta-based fix-forward lint reject.
#
# PHASE NOTE (UNVERIFIED firing phase -> pinned at T620): this check compares the touched
# file's CURRENT on-disk diagnostics against its committed (HEAD) baseline, so it is only
# correct on a POST-WRITE firing — one where the on-disk file already reflects the edit.
# `docs/POLICIES.md` documents `tool_call` (pre-write) and `request` only — no post-write
# phase — so the real one is pinned on the live driver at T620 (DEFAULT_RESULT_PHASES).
#
# Why it must NOT also run pre-write: before the write, the on-disk file is the PRE-edit
# content. If that content already carries diagnostics above HEAD (a file left dirty by a
# prior edit, a manual change, or a failed-open write), the pre-write delta is already
# positive and the guard would DENY the very edit meant to FIX it — a false reject, the
# opposite of fix-forward (PR #137 review: Codex P2 / craft H1). The reference `guard.sh`
# avoids this structurally by running PostToolUse only (guard.sh:199). So make_edit_guard
# fires ONLY on DEFAULT_RESULT_PHASES and abstains (fail-open) on every pre-write phase.
# Until T620 pins the real post-write phase, the guard abstains on all *documented* phases
# — inert-but-correct, never a false reject; the delta logic is exercised in tests via a
# post-write (`tool_result`) event.
# --------------------------------------------------------------------------------------

def _default_project_file():
    env = os.environ.get("CREANCE_OMNIGENT_PROJECT_FILE")
    if env:
        return env
    here = os.path.dirname(os.path.abspath(__file__))
    # policies/ -> creance_omnigent/ -> omnigent/ -> adapters/ -> .claude/PROJECT.md
    return os.path.normpath(os.path.join(here, "..", "..", "..", "..", "PROJECT.md"))


def _project_edit_checks(project_file):
    """The profile's "Edit-time checks" map as a list of (glob, checker) pairs — the first
    two backticked tokens of each bullet under that heading. [] on any error."""
    out = []
    try:
        with open(project_file, encoding="utf-8") as f:
            in_section = False
            for line in f:
                if re.match(r"^##\s", line):
                    in_section = bool(re.match(r"^##\s+Edit-time checks", line))
                    continue
                if in_section and re.match(r"^[-*]\s", line):
                    toks = _BACKTICK.findall(line)
                    if len(toks) >= 2:
                        out.append((toks[0], toks[1]))
    except Exception:
        return []
    return out


def _abs_checker(checker, cwd):
    if os.path.isabs(checker):
        return checker if os.path.exists(checker) else None
    root = _repo_root(cwd)
    if not root:
        return None
    p = os.path.join(root, checker)
    return p if os.path.exists(p) else None


def _resolve_checker(file_path, checkers, cwd):
    base = os.path.basename(file_path)
    if checkers:
        items = checkers.items() if isinstance(checkers, dict) else checkers
        for glob, checker in items:
            if fnmatch.fnmatch(base, glob):
                return _abs_checker(checker, cwd)
        return None
    for glob, checker in _project_edit_checks(_default_project_file()):
        if fnmatch.fnmatch(base, glob):
            return _abs_checker(checker, cwd)
    return None


def _run_checker(checker, file_path):
    """Diagnostic count = non-blank stdout lines (the guard.sh convention). None on error."""
    try:
        cmd = ["bash", checker, file_path] if checker.endswith(".sh") else [checker, file_path]
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    except Exception:
        return None
    return sum(1 for ln in r.stdout.splitlines() if ln.strip())


def _baseline_diags(abspath, checker, cwd):
    """Diagnostics on the file's committed (HEAD) blob. 0 for an in-repo file untracked at
    HEAD (its diagnostics are all 'new'); None when there is no repo/HEAD (fail open)."""
    root = _repo_root(cwd)
    if not root:
        return None
    if _git(["rev-parse", "--verify", "-q", "HEAD"], root) is None:
        return None
    # realpath both sides before relpath: git reports the resolved toplevel (e.g.
    # /private/var/... on macOS) while a cwd-derived abspath keeps the symlink form
    # (/var/...), and the mismatch would yield a spurious '..'-leading rel -> fail open.
    try:
        rel = os.path.relpath(os.path.realpath(abspath), os.path.realpath(root))
    except Exception:
        return None
    if rel.startswith(".."):
        return None
    exists = _git(["cat-file", "-e", "HEAD:{}".format(rel)], root)
    if exists is None:
        return 0  # untracked at HEAD
    content = _git(["show", "HEAD:{}".format(rel)], root)
    if content is None:
        return None
    tmpd = tempfile.mkdtemp()
    try:
        bp = os.path.join(tmpd, os.path.basename(abspath))
        with open(bp, "w", encoding="utf-8") as f:
            f.write(content)
        return _run_checker(checker, bp)
    finally:
        shutil.rmtree(tmpd, ignore_errors=True)


def _edit_guard_eval(file_path, cwd, checkers, path_keys=DEFAULT_EDIT_PATH_KEYS):
    abspath = file_path if os.path.isabs(file_path) else os.path.join(cwd, file_path)
    checker = _resolve_checker(file_path, checkers, cwd)
    if not checker:
        return None  # no checker configured for the type -> fail open
    if _in_repo(abspath, cwd) is not True:
        return None  # out-of-repo / undeterminable -> fail open
    current = _run_checker(checker, abspath)
    if current is None:
        return None
    baseline = _baseline_diags(abspath, checker, cwd)
    if baseline is None:
        return None
    if current > baseline:
        return _deny(
            "edit-lint-regression",
            "this edit adds {} new diagnostic(s) to a checked file (baseline {}, now {}). "
            "Fix them forward. An edit leaving diagnostics no worse than the committed "
            "baseline is allowed; the check fails open when none is configured.".format(
                current - baseline, baseline, current,
            ),
        )
    return None


# --------------------------------------------------------------------------------------
# Registered policy factories (Omnigent "kind": "factory" — a configured callable).
#
# TELEMETRY (deferred to T620; PR #137 review: craft M2). `workflow/telemetry.md` makes the
# [guard] the emitter of `block` records (one per DENY) and the per-gate `evaluation`
# liveness record (the strong-floor path that fires on every gate run). This port emits
# neither: emission needs the live telemetry-stream path (PROJECT.md -> Paths -> Telemetry)
# and a real dispatch context, and the `evaluation` signal is only meaningful once the guard
# is wired to a driver and a gate actually runs — both T620 ("real-driver liveness"). Per
# telemetry.md's governing law ("telemetry observes; it never decides"), a silent stream
# changes no DENY/abstain decision here, so deferring emission is behaviour-preserving; T620
# owns wiring it (and the README degradations table records the deferral).
# --------------------------------------------------------------------------------------

def make_guard_tool_call(
    base_branch="main",
    models_file=None,
    dispatch_tools=DEFAULT_DISPATCH_TOOLS,
    reviewer_keys=DEFAULT_REVIEWER_KEYS,
    reviewer_match=DEFAULT_REVIEWER_MATCH,
    model_keys=DEFAULT_MODEL_KEYS,
    edit_path_keys=DEFAULT_EDIT_PATH_KEYS,
):
    """The `tool_call`-phase guard policy: rules 1-6. Returns a configured evaluator."""
    mfile = models_file or _default_models_file()
    disp = tuple(dispatch_tools)

    def policy(event):
        try:
            if not isinstance(event, dict) or event.get("type") != "tool_call":
                return None
            target = _target(event)
            if target in EDIT_TOOLS:
                return _rule_edit_on_base(event, base_branch, _event_cwd(event), edit_path_keys)
            if target in SHELL_TOOLS:
                command = _command(event)
                cwd = _event_cwd(event)
                for rule in _SHELL_RULES:
                    resp = rule(command, base_branch, cwd)
                    if resp is not None:
                        return resp
                return None
            if target in disp:
                return _rule_strong_floor(
                    event, mfile, reviewer_keys, reviewer_match, model_keys,
                )
            return None
        except Exception:
            return None  # FAIL OPEN — any uncertainty allows (workflow/README.md)

    return policy


def make_edit_guard(
    checkers=None, edit_path_keys=DEFAULT_EDIT_PATH_KEYS, result_phases=DEFAULT_RESULT_PHASES,
):
    """The [edit guard] policy. ``checkers`` is an optional {glob: checker} map override;
    when None the profile's "Edit-time checks" map is read. ``result_phases`` are the event
    phases on which the touched file's on-disk state reflects the edit (a post-write firing);
    the policy fires only on those and abstains on every pre-write phase (see PHASE NOTE) so
    it can never DENY a fix-forward edit before it runs. The default is UNVERIFIED upstream
    and pinned on the live driver at T620."""
    phases = frozenset(result_phases)

    def policy(event):
        try:
            if not isinstance(event, dict):
                return None
            if event.get("type") not in phases:
                return None  # pre-write / unknown phase -> abstain (never a false reject)
            if _target(event) not in EDIT_TOOLS:
                return None
            fp = _edit_path(event, edit_path_keys)
            if not fp:
                return None
            return _edit_guard_eval(fp, _event_cwd(event), checkers, edit_path_keys)
        except Exception:
            return None  # FAIL OPEN

    return policy


# Default-configured module-level callables (base branch 'main', adapter MODELS.md /
# PROJECT.md) for direct use; the factories above are the configurable entry points.
guard_tool_call = make_guard_tool_call()
edit_guard = make_edit_guard()
