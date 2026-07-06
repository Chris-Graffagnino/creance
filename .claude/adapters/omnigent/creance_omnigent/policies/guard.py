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
import shlex
import shutil
import stat
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

# Leading git GLOBAL-option run (issue #138): rules 2/3/4 must see through a run of
# global options between `git` and the subcommand (`git -C <path> add --all`,
# `git -c k=v commit`, `git --git-dir=… push`), which standard git accepts and which
# would otherwise slip the subcommand anchor. CONSERVATIVE: only well-known globals
# match, so an UNRECOGNIZED leading token ends the run — the rule then sees the
# original token and may abstain (fail-open, the narrowly-scoped DW3 posture). Path
# operands stop at shell separators and a quote. Mirrors guard.sh's `gitg`/`grun`.
_GOPT = (
    r'-C\s+[^\s;&|"]+|-c\s+[^\s;&|"]+'
    r'|--git-dir=[^\s;&|"]*|--git-dir\s+[^\s;&|"]+'
    r'|--work-tree=[^\s;&|"]*|--work-tree\s+[^\s;&|"]+'
    r'|--namespace\s+[^\s;&|"]+'
    r'|--paginate|--no-pager|--bare|--literal-pathspecs|--no-optional-locks|-p'
)
_GRUN = r"(?:\s+(?:" + _GOPT + r"))*"
# The `git <globals> commit|push` invocation's prefix — the repo-locating globals are
# read from the SAME invocation rule 3 matched (issue #138 / PR #173 Codex P2), not the
# first `git` in the line, so `git -C <other> status && git commit` does not borrow <other>.
# The trailing boundary lookahead mirrors _RE_COMMIT_PUSH so the locator latches onto the
# EXACT invocation rule 3 matched (not a `git commitx` decoy that shares the prefix).
_RE_COMMIT_PUSH_RUN = re.compile(r"git" + _GRUN + r"\s+(?:commit|push)(?=\s|;|&|\||\"|$)")
_RE_CD = re.compile(r"^\s*cd\s+([^\s;&|\"]+)")
_RE_C_OPT = re.compile(r"-C\s+([^\s;&|\"]+)")
_RE_GITDIR_OPT = re.compile(r"--git-dir(?:=|\s+)([^\s;&|\"]+)")


def _effective_git_args(command, run_re=_RE_COMMIT_PUSH_RUN):
    """Git globals locating the repo for the matched invocation, replayable from cwd."""
    m = _RE_CD.match(command)
    cddir = m.group(1) if m else None
    copt = gdir = None
    run = run_re.search(command)
    if run:
        seg = run.group(0)
        cs = list(_RE_C_OPT.finditer(seg))
        if cs:
            copt = cs[-1].group(1)  # ONLY from the global run, so `git commit -C HEAD` is safe
        gs = list(_RE_GITDIR_OPT.finditer(seg))
        if gs:
            gdir = gs[-1].group(1)
    gargs = []
    if cddir:
        gargs += ["-C", cddir]
    if copt:
        gargs += ["-C", copt]
    if gdir:
        gargs += ["--git-dir", gdir]
    return gargs


def _effective_branch(command, cwd):
    """Branch of the repo ``command`` acts on. The repo-locating globals (`-C`,
    `--git-dir`) are read from the SAME `git … commit|push` invocation rule 3 matched
    (issue #138 / PR #173 Codex P2) — so an unrelated leading `git -C <other> status`
    cannot lend its `-C` — and `--git-dir` is honored alongside `-C` (PR #173 craft H1).
    They are replayed against `git … branch --show-current` run from the EVENT cwd, so a
    relative path resolves against the event cwd, not the policy process cwd (PR #173 craft
    H2; git applies repeated `-C` cumulatively, so `cd <a> && git -C <b>` nests for free).
    Best-effort + fail-open: an unreadable target (bad path, non-repo, detached HEAD)
    falls back to the event-cwd branch, so the change only ADDS DENY coverage and never
    weakens the existing event-cwd check (e.g. `cd <gone> && git commit` on base DENYs)."""
    gargs = _effective_git_args(command)
    if gargs:
        out = _git(gargs + ["branch", "--show-current"], cwd)  # cwd = EVENT cwd (craft H2)
        if out is not None and out.strip():
            return out.strip()
    return _branch(cwd)


# Rule 2 — staging the entire tree at once. The leading-global run (#138 DW1) and the
# trailing `\./?` dot-operand variant (#138 DW4) fold into the same pattern.
_RE_ADD_ALL = re.compile(r"git" + _GRUN + r"\s+add\s+(?:--all|-A|\./?)(?:\s|;|&|\||\"|$)")


def _rule_bulk_staging(command, base=None, cwd=None):
    if _RE_ADD_ALL.search(command):
        return _deny(
            "git-add-all",
            "`git add .` / -A / --all stages the whole tree. Stage specific files: "
            "`git add <path1> <path2>`.",
        )
    return None


# Rule 3 — commit / push while on the base branch. Allows a leading global run (#138
# DW1) and resolves the EFFECTIVE repo (a -C / cd && target), not only the event cwd
# (#138 DW2).
_RE_COMMIT_PUSH = re.compile(r"git" + _GRUN + r"\s+(?:commit|push)(?:\s|;|&|\||\"|$)")


def _rule_commit_push_base(command, base, cwd):
    if _RE_COMMIT_PUSH.search(command) and _effective_branch(command, cwd) == base:
        return _deny(
            "commit-push-on-base",
            "never commit or push while on the base branch '{}'. Work on a feature "
            "branch and open a PR.".format(base),
        )
    return None


# Rule 7 — a pending `git commit` whose message carries [T<nnn>] while that task's
# live tasks-file box is still unchecked. The unchecked-box definition is read from
# lib-tasks-drift.sh's `tasks_drift_unchecked_ids` so Omnigent tracks the same shared
# workflow definition without sourcing bash in the adapter runtime.
_RE_TASK_ID = re.compile(r"\[(T[0-9]+)\]")
_SHELL_SEPARATORS = {";", "&&", "||", "|", "&", "(", ")", "{", "}", "\n"}
_SHELL_SEPARATOR_CHARS = set(";&|(){}\n")
_SHELL_REDIRECT_OPS = ("<<<", "<<-", "<<", "<>", ">>", ">|", "<&", ">&", "<", ">")
_GIT_GLOBALS_WITH_ARG = {"-C", "-c", "--git-dir", "--work-tree", "--namespace"}
_GIT_GLOBALS_NO_ARG = {
    "--paginate", "--no-pager", "--bare", "--literal-pathspecs", "--no-optional-locks", "-p",
}
_SHELL_COMMAND_PREFIXES = {"if", "then", "do", "while", "until", "else", "elif", "time", "!"}
_SHELL_UNSUPPORTED_CONTROL_FLOW = {
    "case", "do", "done", "elif", "else", "esac", "fi", "for", "if", "then", "until", "while",
}
_SHELL_UNSUPPORTED_FLOW_END = {
    "case": "esac",
    "for": "done",
    "if": "fi",
    "until": "done",
    "while": "done",
}
_SHELL_COMMAND_WRAPPERS = {"command", "exec", "env", "sudo"}
_SHELL_C_WRAPPERS = {"bash", "sh", "zsh"}
_ENV_OPTIONS_WITH_ARG = {
    "-C", "-P", "-S", "-u", "--argv0", "--chdir", "--path", "--split-string", "--unset",
}
_SHELL_C_OPTIONS_WITH_ARG = {"-o", "-O", "--init-file", "--rcfile"}
_SUDO_OPTIONS_WITH_ARG = {
    "-C", "-D", "-g", "-h", "-p", "-r", "-t", "-T", "-u",
    "--chdir", "--close-from", "--group", "--host", "--login-class", "--prompt",
    "--role", "--type", "--user",
}
_COMMIT_MESSAGE_OPTS = {"-m", "--message", "--trailer"}
_COMMIT_MESSAGE_FILE_OPTS = {"-F", "--file"}
_COMMIT_REUSE_MESSAGE_OPTS = {"-C", "-c", "--reuse-message", "--reedit-message"}
_COMMIT_GENERATED_MESSAGE_OPTS = {"--fixup", "--squash"}
_COMMIT_VALUE_OPTS = {
    "-m", "--message", "-F", "--file", "-C", "-c", "--reuse-message", "--reedit-message",
    "--author", "--date", "--template", "--cleanup", "--fixup", "--squash",
    "--pathspec-from-file", "--trailer",
}
_COMMIT_VALUE_PREFIXES = tuple(opt + "=" for opt in (
    "--message", "--file", "--reuse-message", "--reedit-message", "--author", "--date",
    "--template", "--cleanup", "--fixup", "--squash", "--pathspec-from-file", "--trailer",
))
_COMMIT_STATUS_DRY_RUN_OPTS = {"--porcelain", "--short", "--long"}
_COMMIT_STATUS_DRY_RUN_NEGATED_OPTS = {"--no-porcelain", "--no-short", "--no-long"}
_COMMIT_TASKS_HEAD = "head"
_COMMIT_TASKS_INDEX = "index"
_COMMIT_TASKS_WORKTREE = "worktree"
_MAX_GUARD_FILE_READ_BYTES = 1024 * 1024


def _default_tasks_drift_lib():
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.normpath(os.path.join(here, "..", "..", "..", "..", "hooks", "lib-tasks-drift.sh"))


_TASKS_DRIFT_LIB = _default_tasks_drift_lib()


def _strip_shell_comments(command):
    out = []
    single = double = False
    i = 0
    while i < len(command):
        ch = command[i]
        if ch == "\\" and not single:
            out.append(command[i:i + 2])
            i += 2
            continue
        if ch == "'" and not double:
            single = not single
            out.append(ch)
            i += 1
            continue
        if ch == '"' and not single:
            double = not double
            out.append(ch)
            i += 1
            continue
        if not single and not double and _is_shell_comment_start(command, i):
            newline = command.find("\n", i)
            if newline < 0:
                break
            out.append("\n")
            i = newline + 1
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def _expand_unquoted_tilde_words(command):
    out = []
    single = double = False
    word_start = True
    i = 0
    while i < len(command):
        ch = command[i]
        if ch == "\\" and not single:
            out.append(command[i:i + 2])
            i += 2
            word_start = False
            continue
        if ch == "'" and not double:
            single = not single
            out.append(ch)
            i += 1
            word_start = False
            continue
        if ch == '"' and not single:
            double = not double
            out.append(ch)
            i += 1
            word_start = False
            continue
        if not single and not double and word_start and ch == "~":
            j = i + 1
            while j < len(command) and command[j] not in "/ \t\r\n;&|(){}<>":
                j += 1
            prefix = command[i:j]
            expanded = os.path.expanduser(prefix)
            if expanded != prefix:
                out.append(expanded)
                i = j
                word_start = False
                continue
        out.append(ch)
        if not single and not double and ch in " \t\r\n;&|(){}<>":
            word_start = True
        else:
            word_start = False
        i += 1
    return "".join(out)


def _shell_tokens(command):
    try:
        command = _strip_shell_comments(command).replace("\\\n", " ")
        command = _expand_unquoted_tilde_words(command)
        lex = shlex.shlex(command, posix=True, punctuation_chars=";&|(){}\n")
        lex.whitespace_split = True
        lex.whitespace = " \t\r"
        lex.commenters = ""
        return list(lex)
    except Exception:
        return None


def _read_backtick_substitution(command, start):
    i = start
    while i < len(command):
        if command[i] == "\\":
            i += 2
            continue
        if command[i] == "`":
            return command[start:i], i
        i += 1
    return None, None


def _read_dollar_substitution(command, start):
    depth = 1
    single = double = False
    i = start
    while i < len(command):
        ch = command[i]
        if ch == "\\" and not single:
            i += 2
            continue
        if ch == "'" and not double:
            single = not single
            i += 1
            continue
        if ch == '"' and not single:
            double = not double
            i += 1
            continue
        if single:
            i += 1
            continue
        if not double and command.startswith("$(", i):
            depth += 1
            i += 2
            continue
        if not double and ch == "(":
            depth += 1
            i += 1
            continue
        if not double and ch == ")":
            depth -= 1
            if depth == 0:
                return command[start:i], i
            i += 1
            continue
        i += 1
    return None, None


def _apply_shell_status(status, invert):
    if status is None:
        return None
    return not status if invert else status


def _shell_cwd_status_after_segment(shell_cwd, segment):
    tokens = _shell_tokens(segment)
    if not tokens:
        return shell_cwd, None
    i = 0
    invert = False
    while i < len(tokens) and (
        tokens[i] in _SHELL_COMMAND_PREFIXES or _is_shell_assignment(tokens[i])
    ):
        if tokens[i] == "!":
            invert = not invert
        i += 1
    if i < len(tokens) and tokens[i] == "cd":
        if i + 1 < len(tokens) and not _is_shell_separator(tokens[i + 1]):
            new_cwd = _resolve_existing_shell_cd(shell_cwd, tokens[i + 1])
            status = new_cwd != shell_cwd or os.path.isdir(_resolve_shell_cd(shell_cwd, tokens[i + 1]))
            return new_cwd, _apply_shell_status(status, invert)
    if i < len(tokens):
        return shell_cwd, _apply_shell_status(_known_shell_status(tokens[i]), invert)
    return shell_cwd, None


def _first_shell_command_name(segment):
    tokens = _shell_tokens(segment)
    if not tokens:
        return None
    i = 0
    while i < len(tokens):
        tok = tokens[i]
        name = _shell_command_name(tok)
        if _is_shell_redirection(tok):
            i += 2 if _redirection_consumes_next(tok) else 1
            continue
        if name in _SHELL_UNSUPPORTED_CONTROL_FLOW:
            return name
        if _is_shell_assignment(tok) or name in _SHELL_COMMAND_PREFIXES:
            i += 1
            continue
        return name
    return None


def _is_shell_comment_start(command, index):
    if command[index] != "#":
        return False
    return index == 0 or command[index - 1] in " \t\r\n;&|(){}"


def _heredoc_prefix_feeds_shell(command, index):
    line_start = command.rfind("\n", 0, index) + 1
    segment = re.split(r"[;&|]", command[line_start:index])[-1]
    tokens = _shell_tokens(segment)
    if not tokens:
        return True
    i = 0
    while i < len(tokens):
        tok = tokens[i]
        name = _shell_command_name(tok)
        if _is_shell_redirection(tok):
            i += 2 if _redirection_consumes_next(tok) else 1
            continue
        if _is_shell_assignment(tok) or name in ("env", "command", "exec", "time"):
            i += 1
            continue
        if tok.startswith("-") and i > 0:
            i += 1
            continue
        return name in _SHELL_C_WRAPPERS
    return True


def _raw_heredoc_spec(command, index):
    if not command.startswith("<<", index):
        return None
    strip_tabs = command.startswith("<<-", index)
    i = index + (3 if strip_tabs else 2)
    while i < len(command) and command[i] in " \t":
        i += 1
    if i >= len(command) or command[i] in "\r\n;&|(){}":
        return None
    quoted = False
    delim = []
    while i < len(command) and command[i] not in " \t\r\n;&|(){}":
        ch = command[i]
        if ch in ("'", '"'):
            quoted = True
            quote = ch
            i += 1
            while i < len(command) and command[i] != quote:
                delim.append(command[i])
                i += 1
            if i < len(command):
                i += 1
            continue
        if ch == "\\":
            quoted = True
            i += 1
            if i < len(command):
                delim.append(command[i])
                i += 1
            continue
        delim.append(ch)
        i += 1
    if not delim:
        return None
    return "".join(delim), quoted, strip_tabs, i


def _blank_quoted_data_heredoc_bodies(command):
    chars = list(command)
    pending = []
    single = double = False
    i = 0
    while i < len(command):
        ch = command[i]
        if ch == "\\" and not single:
            i += 2
            continue
        if ch == "'" and not double:
            single = not single
            i += 1
            continue
        if ch == '"' and not single:
            double = not double
            i += 1
            continue
        if not single and not double and command.startswith("<<", i):
            spec = _raw_heredoc_spec(command, i)
            if spec is not None:
                delim, quoted, strip_tabs, next_i = spec
                if quoted and not _heredoc_prefix_feeds_shell(command, i):
                    pending.append((delim, strip_tabs))
                i = next_i
                continue
        if ch == "\n" and pending:
            i += 1
            for delim, strip_tabs in pending:
                body_start = i
                while i < len(command):
                    line_end = command.find("\n", i)
                    if line_end < 0:
                        line_end = len(command)
                    line = command[i:line_end]
                    compare = line.lstrip("\t") if strip_tabs else line
                    if compare == delim:
                        for j in range(body_start, i):
                            if chars[j] != "\n":
                                chars[j] = " "
                        i = line_end
                        break
                    i = line_end + 1 if line_end < len(command) else len(command)
            pending = []
            continue
        i += 1
    return "".join(chars)


def _blank_shell_function_bodies(command):
    chars = list(command)
    single = double = False
    i = 0

    def command_start(index):
        return index == 0 or command[index - 1] in " \t\r\n;&|"

    def matching_brace(index):
        depth = 1
        single = double = False
        index += 1
        while index < len(command):
            ch = command[index]
            if ch == "\\" and not single:
                index += 2
                continue
            if ch == "'" and not double:
                single = not single
                index += 1
                continue
            if ch == '"' and not single:
                double = not double
                index += 1
                continue
            if single:
                index += 1
                continue
            if not double and ch == "{":
                depth += 1
            elif not double and ch == "}":
                depth -= 1
                if depth == 0:
                    return index
            index += 1
        return None

    while i < len(command):
        ch = command[i]
        if ch == "\\" and not single:
            i += 2
            continue
        if ch == "'" and not double:
            single = not single
            i += 1
            continue
        if ch == '"' and not single:
            double = not double
            i += 1
            continue
        if not single and not double and command_start(i):
            tail = command[i:]
            match = (
                re.match(r"function\s+[A-Za-z_][A-Za-z0-9_]*\s*(?:\(\)\s*)?\{", tail)
                or re.match(r"[A-Za-z_][A-Za-z0-9_]*\s*\(\)\s*\{", tail)
            )
            if match:
                open_brace = i + match.end() - 1
                close_brace = matching_brace(open_brace)
                if close_brace is None:
                    return "".join(chars)
                for j in range(open_brace + 1, close_brace):
                    if chars[j] != "\n":
                        chars[j] = " "
                i = close_brace + 1
                continue
        i += 1
    return "".join(chars)


def _command_substitution_sites(command, cwd):
    command = _blank_quoted_data_heredoc_bodies(command)
    command = _blank_shell_function_bodies(command)
    sites = []
    shell_cwd = cwd
    cwd_stack = []
    segment_start = 0
    segment_sites = []
    previous_separator = None
    last_status = True
    single = double = False
    i = 0

    def close_segment(end, next_start, separator=None):
        nonlocal segment_start, segment_sites, shell_cwd, previous_separator, last_status
        segment = command[segment_start:end]
        should_run = _shell_command_should_run(previous_separator, last_status)
        if segment.strip() and should_run:
            if _first_shell_command_name(segment) in _SHELL_UNSUPPORTED_CONTROL_FLOW:
                return True
            sites.extend(segment_sites)
            shell_cwd, last_status = _shell_cwd_status_after_segment(shell_cwd, segment)
        segment_sites = []
        previous_separator = separator
        segment_start = next_start
        return False

    def skip_group(index, opener):
        closer = ")" if opener == "(" else "}"
        stack = [closer]
        single = double = False
        index += 1
        while index < len(command):
            ch = command[index]
            if ch == "\\" and not single:
                index += 2
                continue
            if ch == "'" and not double:
                single = not single
                index += 1
                continue
            if ch == '"' and not single:
                double = not double
                index += 1
                continue
            if single:
                index += 1
                continue
            if command.startswith("$(", index):
                body, end = _read_dollar_substitution(command, index + 2)
                if body is not None:
                    index = end + 1
                    continue
            if ch == "`":
                body, end = _read_backtick_substitution(command, index + 1)
                if body is not None:
                    index = end + 1
                    continue
            if not double and ch in ("(", "{"):
                stack.append(")" if ch == "(" else "}")
                index += 1
                continue
            if not double and stack and ch == stack[-1]:
                stack.pop()
                index += 1
                if not stack:
                    return index
                continue
            index += 1
        return index

    while i < len(command):
        ch = command[i]
        if ch == "\\" and not single:
            i += 2
            continue
        if ch == "'" and not double:
            single = not single
            i += 1
            continue
        if ch == '"' and not single:
            double = not double
            i += 1
            continue
        if single:
            i += 1
            continue
        if not double and _is_shell_comment_start(command, i):
            newline = command.find("\n", i)
            if newline < 0:
                break
            i = newline
            continue
        if command.startswith("$(", i):
            body, end = _read_dollar_substitution(command, i + 2)
            if body is not None:
                segment_sites.append((body, shell_cwd))
                i = end + 1
                continue
        if not double and (command.startswith("<(", i) or command.startswith(">(", i)):
            body, end = _read_dollar_substitution(command, i + 2)
            if body is not None:
                segment_sites.append((body, shell_cwd))
                i = end + 1
                continue
        if ch == "`":
            body, end = _read_backtick_substitution(command, i + 1)
            if body is not None:
                segment_sites.append((body, shell_cwd))
                i = end + 1
                continue
        if not double and ch in (";", "&", "|", "\n"):
            j = i + 1
            while j < len(command) and command[j] == ch and ch in ("&", "|"):
                j += 1
            if close_segment(i, j, command[i:j]):
                return sites
            i = j
            continue
        if not double and ch == "(":
            if not _shell_command_should_run(previous_separator, last_status):
                segment_sites = []
                i = skip_group(i, ch)
                segment_start = i
                continue
            if close_segment(i, i + 1):
                return sites
            cwd_stack.append(shell_cwd)
            i += 1
            continue
        if not double and ch == ")":
            if close_segment(i, i + 1):
                return sites
            if cwd_stack:
                shell_cwd = cwd_stack.pop()
            i += 1
            continue
        if not double and ch in ("{", "}"):
            if ch == "{" and not _shell_command_should_run(previous_separator, last_status):
                segment_sites = []
                i = skip_group(i, ch)
                segment_start = i
                continue
            if close_segment(i, i + 1):
                return sites
            i += 1
            continue
        i += 1
    close_segment(len(command), len(command))
    return sites


def _is_shell_separator(token):
    return token in _SHELL_SEPARATORS or (
        bool(token) and all(ch in _SHELL_SEPARATOR_CHARS for ch in token)
    )


def _shell_command_name(token):
    return os.path.basename(token)


def _split_shell_redirection(token):
    if token.startswith("&>>"):
        return "&>>", token[3:]
    if token.startswith("&>"):
        return "&>", token[2:]
    body = re.sub(r"^[0-9]+", "", token)
    for op in _SHELL_REDIRECT_OPS:
        if body.startswith(op):
            return op, body[len(op):]
    return None, None


def _is_shell_redirection(token):
    op, _ = _split_shell_redirection(token)
    return op is not None


def _redirection_consumes_next(token):
    op, rest = _split_shell_redirection(token)
    return op is not None and rest == ""


def _heredoc_delimiter(tokens, index):
    op, rest = _split_shell_redirection(tokens[index])
    if op not in ("<<", "<<-"):
        return None, index
    if rest:
        return rest, index + 1
    if index + 1 < len(tokens) and not _is_shell_separator(tokens[index + 1]):
        return tokens[index + 1], index + 2
    return None, index + 1


def _render_shell_line(tokens):
    parts = []
    for tok in tokens:
        if _is_shell_separator(tok) or _is_shell_redirection(tok):
            parts.append(tok)
        else:
            parts.append(shlex.quote(tok))
    return " ".join(parts)


def _shell_tail_line(tokens, index):
    end = index
    while end < len(tokens) and not _is_shell_separator(tokens[end]):
        end += 1
    return _render_shell_line(tokens[index:end]), end


def _token_opens_shell_substitution_arg(token):
    return token in ("$", "<") or token.endswith("$") or token.endswith("<")


def _append_balanced_shell_group(tokens, index, out):
    if index >= len(tokens) or tokens[index] != "(":
        return index
    depth = 0
    while index < len(tokens):
        tok = tokens[index]
        out.append(tok)
        if tok == "(":
            depth += 1
        elif tok == ")":
            depth -= 1
            if depth == 0:
                return index + 1
        index += 1
    return index


def _skip_balanced_shell_group(tokens, index):
    return _append_balanced_shell_group(tokens, index, [])


def _skip_unsupported_shell_control_flow(tokens, index):
    end = _SHELL_UNSUPPORTED_FLOW_END.get(_shell_command_name(tokens[index]))
    if end is None:
        return None
    stack = [end]
    command_start = False
    i = index + 1
    while i < len(tokens):
        tok = tokens[i]
        name = _shell_command_name(tok)
        if _is_shell_separator(tok):
            command_start = True
            i += 1
            continue
        if command_start:
            nested_end = _SHELL_UNSUPPORTED_FLOW_END.get(name)
            if nested_end is not None:
                stack.append(nested_end)
            elif stack and name == stack[-1]:
                stack.pop()
                i += 1
                if not stack:
                    return i
                command_start = False
                continue
            command_start = False
        i += 1
    return None


def _read_heredoc_bodies(tokens, index, heredocs):
    bodies = []
    for delim, executable in heredocs:
        at_line_start = True
        line = []
        lines = []
        while index < len(tokens):
            tok = tokens[index]
            if tok == "\n":
                if executable:
                    lines.append(_render_shell_line(line) if line else "")
                    line = []
                at_line_start = True
                index += 1
                continue
            if at_line_start and tok == delim:
                index += 1
                if index < len(tokens) and tokens[index] == "\n":
                    index += 1
                break
            if executable:
                line.append(tok)
            at_line_start = False
            index += 1
        if executable:
            if line:
                lines.append(_render_shell_line(line))
            body = "\n".join(lines)
            if body.strip():
                bodies.append(body)
    return index, bodies


def _mark_pending_heredocs_executable(pending_heredocs):
    return [(delim, True) for delim, _ in pending_heredocs]


def _resolve_shell_cd(shell_cwd, target):
    if os.path.isabs(target):
        return os.path.normpath(target)
    return os.path.normpath(os.path.join(shell_cwd, target))


def _resolve_existing_shell_cd(shell_cwd, target):
    path = _resolve_shell_cd(shell_cwd, target)
    return path if os.path.isdir(path) else shell_cwd


def _shell_command_should_run(separator, last_status):
    if separator == "&&":
        return last_status is not False
    if separator == "||":
        return last_status is not True
    return True


def _known_shell_status(name):
    if name == "true":
        return True
    if name == "false":
        return False
    return None


def _skip_shell_group(tokens, index):
    closers = {"(": ")", "{": "}"}
    stack = [closers[tokens[index]]]
    index += 1
    while index < len(tokens) and stack:
        tok = tokens[index]
        if tok in closers:
            stack.append(closers[tok])
        elif tok == stack[-1]:
            stack.pop()
        index += 1
    return index


def _shell_function_body_start(tokens, index):
    if index >= len(tokens):
        return None, None
    name = _shell_command_name(tokens[index])
    if name == "function":
        if index + 2 >= len(tokens):
            return None, None
        body = index + 2
        if tokens[body] == "()":
            body += 1
        if body < len(tokens) and "{" in tokens[body]:
            return body, "{"
        return None, None
    if index + 1 >= len(tokens):
        return None, None
    next_tok = tokens[index + 1]
    if next_tok == "()":
        body = index + 2
        if body < len(tokens) and ("{" in tokens[body] or "(" in tokens[body]):
            return body, "{" if "{" in tokens[body] else "("
    if next_tok.startswith("()") and "{" in next_tok:
        return index + 1, "{"
    return None, None


def _skip_shell_function_definition(tokens, index):
    body, opener = _shell_function_body_start(tokens, index)
    if body is None:
        return None
    closer = "}" if opener == "{" else ")"
    depth = 0
    started = False
    i = body
    while i < len(tokens):
        tok = tokens[i]
        for ch in tok:
            if ch == opener:
                depth += 1
                started = True
            elif ch == closer and started:
                depth -= 1
                if depth <= 0:
                    return i + 1
        i += 1
    return len(tokens)


def _skip_shell_command(tokens, index):
    skipped = _skip_shell_function_definition(tokens, index)
    if skipped is not None:
        return skipped
    if index < len(tokens) and tokens[index] in ("(", "{"):
        return _skip_shell_group(tokens, index)
    while index < len(tokens) and not _is_shell_separator(tokens[index]):
        index += 1
    return index


def _is_shell_assignment(token):
    return bool(re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", token))


def _skip_env_wrapper(tokens, index, shell_cwd):
    index += 1
    while index < len(tokens) and not _is_shell_separator(tokens[index]):
        tok = tokens[index]
        if tok == "--":
            return index + 1, shell_cwd
        if _is_shell_assignment(tok):
            index += 1
            continue
        if tok in ("-C", "--chdir"):
            if index + 1 >= len(tokens):
                return len(tokens), shell_cwd
            shell_cwd = _resolve_shell_cd(shell_cwd, tokens[index + 1])
            index += 2
            continue
        if tok.startswith("--chdir="):
            shell_cwd = _resolve_shell_cd(shell_cwd, tok.split("=", 1)[1])
            index += 1
            continue
        if tok in _ENV_OPTIONS_WITH_ARG:
            index += 2
            continue
        if any(tok.startswith(opt + "=") for opt in _ENV_OPTIONS_WITH_ARG if opt.startswith("--")):
            index += 1
            continue
        if tok.startswith("-") and tok != "-":
            index += 1
            continue
        break
    return index, shell_cwd


def _env_split_string(tokens, index, shell_cwd):
    index += 1
    while index < len(tokens) and not _is_shell_separator(tokens[index]):
        tok = tokens[index]
        if tok == "--":
            return None, shell_cwd, index + 1
        if _is_shell_assignment(tok):
            index += 1
            continue
        if tok in ("-C", "--chdir"):
            if index + 1 >= len(tokens):
                return None, shell_cwd, len(tokens)
            shell_cwd = _resolve_shell_cd(shell_cwd, tokens[index + 1])
            index += 2
            continue
        if tok.startswith("--chdir="):
            shell_cwd = _resolve_shell_cd(shell_cwd, tok.split("=", 1)[1])
            index += 1
            continue
        if tok in ("-S", "--split-string"):
            if index + 1 >= len(tokens):
                return None, shell_cwd, len(tokens)
            tail, end = _shell_tail_line(tokens, index + 2)
            body = tokens[index + 1] + (" " + tail if tail else "")
            return body, shell_cwd, end
        if tok.startswith("--split-string="):
            tail, end = _shell_tail_line(tokens, index + 1)
            body = tok.split("=", 1)[1] + (" " + tail if tail else "")
            return body, shell_cwd, end
        if tok in _ENV_OPTIONS_WITH_ARG:
            index += 2
            continue
        if any(tok.startswith(opt + "=") for opt in _ENV_OPTIONS_WITH_ARG if opt.startswith("--")):
            index += 1
            continue
        if tok.startswith("-") and tok != "-":
            index += 1
            continue
        break
    return None, shell_cwd, index


def _shell_c_string(tokens, index):
    index += 1
    while index < len(tokens) and not _is_shell_separator(tokens[index]):
        tok = tokens[index]
        if tok == "-c" or (tok.startswith("-") and not tok.startswith("--") and "c" in tok[1:]):
            if index + 1 >= len(tokens) or _is_shell_separator(tokens[index + 1]):
                return None, len(tokens)
            return tokens[index + 1], index + 2
        if tok in _SHELL_C_OPTIONS_WITH_ARG:
            if index + 1 >= len(tokens) or _is_shell_separator(tokens[index + 1]):
                return None, len(tokens)
            index += 2
            continue
        if any(tok.startswith(opt + "=") for opt in _SHELL_C_OPTIONS_WITH_ARG if opt.startswith("--")):
            index += 1
            continue
        if tok == "--":
            index += 1
            continue
        if tok.startswith("-") and tok != "-":
            index += 1
            continue
        break
    return None, index


def _skip_command_wrapper(tokens, index):
    name = _shell_command_name(tokens[index])
    index += 1
    while index < len(tokens) and not _is_shell_separator(tokens[index]):
        tok = tokens[index]
        if tok == "--":
            return index + 1
        if name == "command":
            if tok == "-p":
                index += 1
                continue
            break
        if name == "exec":
            if tok == "-a":
                if index + 1 >= len(tokens) or _is_shell_separator(tokens[index + 1]):
                    return len(tokens)
                index += 2
                continue
            if tok in ("-c", "-l"):
                index += 1
                continue
            break
        if name == "sudo":
            if tok in _SUDO_OPTIONS_WITH_ARG:
                if index + 1 >= len(tokens) or _is_shell_separator(tokens[index + 1]):
                    return len(tokens)
                index += 2
                continue
            if any(
                tok.startswith(opt + "=")
                for opt in _SUDO_OPTIONS_WITH_ARG
                if opt.startswith("--")
            ):
                index += 1
                continue
            if tok.startswith("-") and tok != "-":
                index += 1
                continue
            break
        break
    return index


def _skip_command_prefix(tokens, index):
    name = _shell_command_name(tokens[index])
    index += 1
    if name != "time":
        return index
    while index < len(tokens) and not _is_shell_separator(tokens[index]):
        tok = tokens[index]
        if tok == "--":
            return index + 1
        if tok == "-p":
            index += 1
            continue
        if tok == "-o":
            if index + 1 >= len(tokens) or _is_shell_separator(tokens[index + 1]):
                return len(tokens)
            index += 2
            continue
        break
    return index


def _split_commit_invocations(command, cwd):
    nested = []
    for body, body_cwd in _command_substitution_sites(command, cwd):
        invocations = _split_commit_invocations(body, body_cwd)
        if invocations:
            nested.extend(invocations)
    tokens = _shell_tokens(command)
    if tokens is None:
        return nested or None
    out = []
    shell_cwd = cwd
    cwd_stack = []
    pending_heredocs = []
    command_start = True
    current_command = None
    previous_separator = None
    last_status = True
    scoped_command_cwd = None
    invert_next_status = False
    i = 0
    while i < len(tokens):
        tok = tokens[i]
        tok_name = _shell_command_name(tok)
        if (
            command_start
            and (tok in ("(", "{") or not _is_shell_separator(tok))
            and not _shell_command_should_run(previous_separator, last_status)
        ):
            i = _skip_shell_command(tokens, i)
            command_start = False
            scoped_command_cwd = None
            invert_next_status = False
            continue
        if command_start:
            skipped_function = _skip_shell_function_definition(tokens, i)
            if skipped_function is not None:
                i = skipped_function
                command_start = True
                current_command = None
                previous_separator = None
                scoped_command_cwd = None
                last_status = _apply_shell_status(True, invert_next_status)
                invert_next_status = False
                continue
        if tok == "(":
            cwd_stack.append(shell_cwd)
            command_start = True
            current_command = None
            i += 1
            continue
        if tok == ")":
            if cwd_stack:
                shell_cwd = cwd_stack.pop()
            command_start = False
            i += 1
            continue
        if tok in ("{", "}"):
            command_start = tok == "{"
            current_command = None if command_start else current_command
            i += 1
            continue
        if tok == "\n" and pending_heredocs:
            i, bodies = _read_heredoc_bodies(tokens, i + 1, pending_heredocs)
            for body in bodies:
                invocations = _split_commit_invocations(body, shell_cwd)
                if invocations:
                    nested.extend(invocations)
            pending_heredocs = []
            command_start = True
            current_command = None
            continue
        if _is_shell_separator(tok):
            command_start = True
            current_command = None
            previous_separator = tok
            scoped_command_cwd = None
            i += 1
            continue
        heredoc, next_i = _heredoc_delimiter(tokens, i)
        if heredoc is not None:
            pending_heredocs.append((heredoc, current_command in _SHELL_C_WRAPPERS))
            i = next_i
            continue
        if _is_shell_redirection(tok):
            i += 2 if _redirection_consumes_next(tok) else 1
            continue
        command_cwd = scoped_command_cwd or shell_cwd
        if command_start and tok_name == "!":
            invert_next_status = not invert_next_status
            i += 1
            continue
        if command_start and tok_name in _SHELL_UNSUPPORTED_CONTROL_FLOW:
            skipped = _skip_unsupported_shell_control_flow(tokens, i)
            if skipped is None:
                return out + nested or None
            i = skipped
            command_start = True
            current_command = None
            previous_separator = None
            scoped_command_cwd = None
            last_status = _apply_shell_status(None, invert_next_status)
            invert_next_status = False
            continue
        if command_start and scoped_command_cwd is None and tok_name == "cd":
            if i + 1 < len(tokens) and not _is_shell_separator(tokens[i + 1]):
                new_cwd = _resolve_existing_shell_cd(shell_cwd, tokens[i + 1])
                status = new_cwd != shell_cwd or os.path.isdir(_resolve_shell_cd(shell_cwd, tokens[i + 1]))
                last_status = _apply_shell_status(status, invert_next_status)
                shell_cwd = new_cwd
                i += 2
                command_start = False
                current_command = tok_name
                previous_separator = None
                invert_next_status = False
                continue
        if command_start and tok_name == "env":
            body, body_cwd, next_i = _env_split_string(tokens, i, command_cwd)
            if body is not None:
                invocations = _split_commit_invocations(body, body_cwd)
                if invocations:
                    nested.extend(invocations)
                i = next_i
                command_start = False
                previous_separator = None
                scoped_command_cwd = None
                last_status = _apply_shell_status(None, invert_next_status)
                invert_next_status = False
                continue
            i, scoped_command_cwd = _skip_env_wrapper(tokens, i, command_cwd)
            if i >= len(tokens) or _is_shell_separator(tokens[i]):
                command_start = False
                previous_separator = None
                scoped_command_cwd = None
                invert_next_status = False
            continue
        if command_start and tok_name in _SHELL_C_WRAPPERS:
            body, next_i = _shell_c_string(tokens, i)
            if body is not None:
                invocations = _split_commit_invocations(body, command_cwd)
                if invocations:
                    nested.extend(invocations)
                i = next_i
                command_start = False
                previous_separator = None
                scoped_command_cwd = None
                last_status = _apply_shell_status(None, invert_next_status)
                invert_next_status = False
                continue
        if command_start and (
            tok_name in _SHELL_COMMAND_WRAPPERS
        ):
            i = _skip_command_wrapper(tokens, i)
            continue
        if command_start and tok_name in _SHELL_COMMAND_PREFIXES:
            i = _skip_command_prefix(tokens, i)
            continue
        if command_start and _is_shell_assignment(tok):
            i += 1
            continue
        if command_start:
            current_command = tok_name
            if current_command in _SHELL_C_WRAPPERS:
                pending_heredocs = _mark_pending_heredocs_executable(pending_heredocs)
        if tok_name != "git" or not command_start:
            if command_start:
                last_status = _apply_shell_status(_known_shell_status(tok_name), invert_next_status)
                invert_next_status = False
            command_start = False
            previous_separator = None
            scoped_command_cwd = None
            i += 1
            continue
        j = i + 1
        gargs = ["-C", command_cwd] if command_cwd else []
        git_cwd = command_cwd
        while j < len(tokens) and not _is_shell_separator(tokens[j]):
            tok = tokens[j]
            if _is_shell_redirection(tok):
                j += 2 if _redirection_consumes_next(tok) else 1
                continue
            if tok in _GIT_GLOBALS_WITH_ARG:
                if j + 1 >= len(tokens):
                    break
                if tok in ("-C", "--git-dir", "--work-tree"):
                    gargs += [tok, tokens[j + 1]]
                if tok == "-C":
                    git_cwd = _resolve_shell_cd(git_cwd, tokens[j + 1])
                j += 2
                continue
            if tok.startswith("--git-dir="):
                gargs += ["--git-dir", tok.split("=", 1)[1]]
                j += 1
                continue
            if tok.startswith("--work-tree="):
                gargs += ["--work-tree", tok.split("=", 1)[1]]
                j += 1
                continue
            if tok in _GIT_GLOBALS_NO_ARG:
                j += 1
                continue
            break
        if j < len(tokens) and tokens[j] == "commit":
            k = j + 1
            args = []
            while k < len(tokens):
                if _is_shell_separator(tokens[k]):
                    if tokens[k] == "(" and args and _token_opens_shell_substitution_arg(args[-1]):
                        k = _append_balanced_shell_group(tokens, k, args)
                        continue
                    break
                args.append(tokens[k])
                k += 1
            stdin_text = None
            pending_commit_heredocs = []
            scan = 0
            while scan < len(args):
                heredoc, next_scan = _heredoc_delimiter(args, scan)
                if heredoc is not None:
                    pending_commit_heredocs.append((heredoc, True))
                    scan = next_scan
                    continue
                scan += 1
            if pending_commit_heredocs and k < len(tokens) and tokens[k] == "\n":
                _, bodies = _read_heredoc_bodies(tokens, k + 1, pending_commit_heredocs)
                if bodies:
                    stdin_text = "\n".join(bodies)
            out.append({"git_args": gargs, "args": args, "cwd": git_cwd})
            if stdin_text is not None:
                out[-1]["stdin"] = stdin_text
            i = k
            command_start = False
            last_status = _apply_shell_status(None, invert_next_status)
            previous_separator = None
            scoped_command_cwd = None
            invert_next_status = False
            continue
        command_start = False
        last_status = _apply_shell_status(None, invert_next_status)
        previous_separator = None
        scoped_command_cwd = None
        invert_next_status = False
        i = max(j + 1, i + 1)
    return out + nested


def _commit_invocation_root(invocation, cwd):
    gargs = invocation["git_args"]
    if gargs:
        has_git_dir = "--git-dir" in gargs
        has_work_tree = "--work-tree" in gargs
        if has_git_dir and not has_work_tree:
            configured_work_tree = _git(gargs + ["config", "--path", "--get", "core.worktree"], cwd)
            if configured_work_tree is not None and configured_work_tree.strip():
                out = _git(gargs + ["rev-parse", "--show-toplevel"], cwd)
                if out is not None and out.strip():
                    return out.strip()
            out = _git(gargs + ["rev-parse", "--absolute-git-dir"], cwd)
            if out is not None and out.strip():
                git_dir = os.path.normpath(out.strip())
                if os.path.basename(git_dir) == ".git":
                    return os.path.dirname(git_dir)
            return None
        out = _git(gargs + ["rev-parse", "--show-toplevel"], cwd)
        if out is not None and out.strip():
            return out.strip()
    return _repo_root(cwd)


def _read_regular_file(path, cwd):
    if not path or path == "-":
        return None
    fp = path if os.path.isabs(path) else os.path.join(cwd or os.getcwd(), path)
    fd = None
    try:
        fd = os.open(fp, os.O_RDONLY | getattr(os, "O_NONBLOCK", 0))
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_size > _MAX_GUARD_FILE_READ_BYTES:
            return None
        chunks = []
        remaining = _MAX_GUARD_FILE_READ_BYTES + 1
        while remaining > 0:
            chunk = os.read(fd, remaining)
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
    except Exception:
        return None
    finally:
        if fd is not None:
            try:
                os.close(fd)
            except Exception:
                pass
    raw = b"".join(chunks)
    if len(raw) > _MAX_GUARD_FILE_READ_BYTES:
        return None
    return raw


def _task_ids_from_commit_message_file(path, cwd):
    if not path or path == "-":
        return set()
    raw = _read_regular_file(path, cwd)
    if raw is None:
        return set()
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        text = raw.decode("utf-8", "surrogateescape")
    return set(_RE_TASK_ID.findall(text))


def _task_ids_from_commit_ref(ref, fmt, cwd=None, git_args=None):
    if not ref:
        return set()
    message = _git((git_args or []) + ["show", "-s", "--format=" + fmt, ref], cwd or os.getcwd())
    if message is None:
        return set()
    return set(_RE_TASK_ID.findall(message))


def _task_ids_from_commit_subject_ref(ref, cwd=None, git_args=None):
    return _task_ids_from_commit_ref(ref, "%s", cwd, git_args)


def _task_ids_from_commit_message_ref(ref, cwd=None, git_args=None):
    return _task_ids_from_commit_ref(ref, "%B", cwd, git_args)


def _fixup_source_ref(value):
    if not value:
        return None
    for prefix in ("amend:", "reword:"):
        if value.startswith(prefix):
            return value[len(prefix):] or None
    return value


def _commit_reuses_head_subject(args):
    amend = False
    no_edit = False
    i = 0
    while i < len(args):
        tok = args[i]
        if _is_shell_redirection(tok):
            i += 2 if _redirection_consumes_next(tok) else 1
            continue
        if tok == "--":
            break
        if tok == "--amend":
            amend = True
            i += 1
            continue
        if tok == "--no-edit":
            no_edit = True
            i += 1
            continue
        if tok == "--edit":
            no_edit = False
            i += 1
            continue
        if tok in _COMMIT_VALUE_OPTS:
            i += 2
            continue
        if any(tok.startswith(prefix) for prefix in _COMMIT_VALUE_PREFIXES):
            i += 1
            continue
        if tok.startswith("-") and not tok.startswith("--"):
            _, consumes_next = _short_option_flags_before_value(tok)
            i += 2 if consumes_next else 1
            continue
        i += 1
    return amend and no_edit


def _task_ids_from_commit_stdin(args, stdin_text=None, cwd=None):
    if stdin_text:
        return set(_RE_TASK_ID.findall(stdin_text))
    i = 0
    while i < len(args):
        op, rest = _split_shell_redirection(args[i])
        if op == "<<<":
            text = rest
            if not text and i + 1 < len(args):
                text = args[i + 1]
            return set(_RE_TASK_ID.findall(text or ""))
        if op in ("<", "<>"):
            path = rest
            if not path and i + 1 < len(args):
                path = args[i + 1]
            return _task_ids_from_commit_message_file(path, cwd)
        if op is not None:
            i += 2 if rest == "" else 1
            continue
        i += 1
    return set()


def _task_ids_from_shell_expansion_tokens(args, index, value=None):
    text = args[index] if value is None and index < len(args) else (value or "")
    out = set(_RE_TASK_ID.findall(text))
    if text in ("$", "<") and index + 1 < len(args) and args[index + 1] == "(":
        depth = 1
        j = index + 2
        body = []
        while j < len(args):
            tok = args[j]
            if tok == "(":
                depth += 1
            elif tok == ")":
                depth -= 1
                if depth == 0:
                    break
            body.append(tok)
            j += 1
        if depth == 0:
            out.update(_RE_TASK_ID.findall(" ".join(body)))
    return out


def _task_ids_from_commit_message_arg(args, index, value=None):
    return _task_ids_from_shell_expansion_tokens(args, index, value)


def _task_ids_from_commit_file_arg(args, index, value, cwd=None, stdin_text=None):
    if value == "-":
        return _task_ids_from_commit_stdin(args, stdin_text, cwd)
    if _token_opens_shell_substitution_arg(value):
        expanded = _task_ids_from_shell_expansion_tokens(args, index, value)
        if expanded:
            return expanded
    return _task_ids_from_commit_message_file(value, cwd)


def _task_ids_from_commit_message(args, cwd=None, git_args=None, stdin_text=None):
    out = set()
    replaces_message = False
    i = 0
    while i < len(args):
        tok = args[i]
        if tok == "--":
            break
        if tok in _COMMIT_MESSAGE_OPTS:
            if tok != "--trailer":
                replaces_message = True
            if i + 1 < len(args):
                out.update(_task_ids_from_commit_message_arg(args, i + 1))
            i += 2
            continue
        if tok in _COMMIT_MESSAGE_FILE_OPTS:
            replaces_message = True
            if i + 1 < len(args):
                out.update(_task_ids_from_commit_file_arg(args, i + 1, args[i + 1], cwd, stdin_text))
            i += 2
            continue
        if tok in _COMMIT_REUSE_MESSAGE_OPTS:
            replaces_message = True
            if i + 1 < len(args):
                out.update(_task_ids_from_commit_message_ref(args[i + 1], cwd, git_args))
            i += 2
            continue
        if tok in _COMMIT_GENERATED_MESSAGE_OPTS:
            replaces_message = True
            if i + 1 < len(args):
                ref = _fixup_source_ref(args[i + 1]) if tok == "--fixup" else args[i + 1]
                out.update(_task_ids_from_commit_subject_ref(ref, cwd, git_args))
            i += 2
            continue
        if tok.startswith("--message="):
            replaces_message = True
            out.update(_task_ids_from_commit_message_arg(args, i, tok.split("=", 1)[1]))
            i += 1
            continue
        if tok.startswith("--trailer="):
            out.update(_RE_TASK_ID.findall(tok.split("=", 1)[1]))
            i += 1
            continue
        if tok.startswith("--file="):
            replaces_message = True
            msg_file = tok.split("=", 1)[1]
            out.update(_task_ids_from_commit_file_arg(args, i, msg_file, cwd, stdin_text))
            i += 1
            continue
        if tok.startswith("--reuse-message=") or tok.startswith("--reedit-message="):
            replaces_message = True
            out.update(_task_ids_from_commit_message_ref(tok.split("=", 1)[1], cwd, git_args))
            i += 1
            continue
        if tok.startswith("--fixup="):
            replaces_message = True
            ref = _fixup_source_ref(tok.split("=", 1)[1])
            out.update(_task_ids_from_commit_subject_ref(ref, cwd, git_args))
            i += 1
            continue
        if tok.startswith("--squash="):
            replaces_message = True
            out.update(_task_ids_from_commit_subject_ref(tok.split("=", 1)[1], cwd, git_args))
            i += 1
            continue
        if tok.startswith("-") and not tok.startswith("--"):
            body = tok[1:]
            if "m" in body:
                replaces_message = True
                msg = body.split("m", 1)[1]
                if msg:
                    out.update(_task_ids_from_commit_message_arg(args, i, msg))
                    i += 1
                else:
                    if i + 1 < len(args):
                        out.update(_task_ids_from_commit_message_arg(args, i + 1))
                    i += 2
                continue
            if "F" in body:
                replaces_message = True
                msg_file = body.split("F", 1)[1]
                if msg_file:
                    out.update(_task_ids_from_commit_file_arg(args, i, msg_file, cwd, stdin_text))
                    i += 1
                else:
                    if i + 1 < len(args):
                        out.update(
                            _task_ids_from_commit_file_arg(
                                args, i + 1, args[i + 1], cwd, stdin_text
                            )
                        )
                    i += 2
                continue
            if "C" in body or "c" in body:
                replaces_message = True
                opt = "C" if "C" in body else "c"
                ref = body.split(opt, 1)[1]
                if ref:
                    out.update(_task_ids_from_commit_message_ref(ref, cwd, git_args))
                    i += 1
                else:
                    if i + 1 < len(args):
                        out.update(_task_ids_from_commit_message_ref(args[i + 1], cwd, git_args))
                    i += 2
                continue
        i += 1
    if not replaces_message and _commit_reuses_head_subject(args):
        out.update(_task_ids_from_commit_message_ref("HEAD", cwd, git_args))
    return sorted(out)


def _is_live_tasks_pathspec(token, root=None):
    path = token.replace("\\", "/")
    if os.path.isabs(path):
        if not root:
            return False
        try:
            path = os.path.relpath(os.path.realpath(path), os.path.realpath(root)).replace("\\", "/")
        except ValueError:
            return False
    while path.startswith("./"):
        path = path[2:]
    parts = path.split("/")
    return (
        len(parts) == 3
        and parts[0] == "specs"
        and bool(parts[1])
        and parts[1] not in (".", "..")
        and parts[2] == "tasks.md"
    )


def _root_relative_git_path(path, root, cwd):
    path = path.replace("\\", "/")
    if os.path.isabs(path):
        abspath = path
    else:
        abspath = os.path.join(cwd or root, path)
    try:
        rel = os.path.relpath(
            os.path.realpath(abspath),
            os.path.realpath(root),
        ).replace("\\", "/")
    except ValueError:
        return None
    if rel == ".":
        return rel
    if rel.startswith("../") or rel == "..":
        return None
    return rel


def _head_live_tasks_paths_for_pathspec(pathspec, git_args, cwd):
    root = _git(git_args + ["rev-parse", "--show-toplevel"], cwd)
    if root is None or not root.strip():
        return None, False
    root = root.strip()
    query = pathspec
    query_cwd = cwd or root
    if not pathspec.startswith(":") and not any(ch in pathspec for ch in "*?["):
        query = _root_relative_git_path(pathspec, root, query_cwd)
        if query is None:
            return set(), False
        query_cwd = root
    out = _git(git_args + ["-C", query_cwd, "ls-tree", "-r", "--name-only", "HEAD", "--", query], cwd)
    if out is None:
        return None, False
    matched = False
    paths = set()
    for rel in out.splitlines():
        if not rel:
            continue
        matched = True
        normalized = _root_relative_git_path(rel, root, query_cwd)
        if normalized and _is_live_tasks_pathspec(normalized):
            paths.add(normalized)
    return paths, matched


def _pathspec_live_tasks_paths(pathspec, git_args, cwd, allow_unmatched=False):
    out = _git(git_args + ["ls-files", "--full-name", "--", pathspec], cwd)
    if out is None:
        return None
    matched_index = False
    paths = set()
    for rel in out.splitlines():
        if rel:
            matched_index = True
        if rel and _is_live_tasks_pathspec(rel):
            paths.add(rel.replace("\\", "/"))
    head_paths, matched_head = _head_live_tasks_paths_for_pathspec(pathspec, git_args, cwd)
    if head_paths is None:
        return None
    paths.update(head_paths)
    exact = _exact_live_tasks_pathspec(pathspec, git_args, cwd)
    if exact is not None:
        paths.add(exact)
    if not matched_index and not matched_head and not paths:
        return set() if allow_unmatched else None
    return paths


def _exact_live_tasks_pathspec(pathspec, git_args, cwd):
    if pathspec.startswith(":") or any(ch in pathspec for ch in "*?["):
        return None
    root = _git(git_args + ["rev-parse", "--show-toplevel"], cwd)
    if root is None or not root.strip():
        return None
    root = os.path.realpath(root.strip())
    path = pathspec
    if not os.path.isabs(path):
        path = os.path.join(cwd, path)
    try:
        rel = os.path.relpath(os.path.realpath(path), root).replace("\\", "/")
    except ValueError:
        return None
    if rel.startswith("../") or rel == ".." or not _is_live_tasks_pathspec(rel):
        return None
    if _git(git_args + ["cat-file", "-e", "HEAD:{}".format(rel)], cwd) is None:
        return None
    return rel


def _exclude_pathspec_payload(pathspec):
    if pathspec.startswith(":!") or pathspec.startswith(":^"):
        return pathspec[2:] or "."
    if not pathspec.startswith(":("):
        return None
    end = pathspec.find(")")
    if end < 0:
        return None
    magic = [part.strip() for part in pathspec[2:end].split(",")]
    if "exclude" not in magic and "!" not in magic and "^" not in magic:
        return None
    kept = [part for part in magic if part not in ("exclude", "!", "^")]
    payload = pathspec[end + 1:] or "."
    if kept:
        return ":({}){}".format(",".join(kept), payload)
    return payload


def _short_option_flags_before_value(token):
    if not token.startswith("-") or token.startswith("--"):
        return None, False
    body = token[1:]
    value_options = []
    for opt in "mFCct":
        pos = body.find(opt)
        if pos >= 0:
            value_options.append((pos, True))
    for opt in "uS":
        pos = body.find(opt)
        if pos >= 0:
            value_options.append((pos, False))
    if not value_options:
        return body, False
    first, requires_next = min(value_options, key=lambda item: item[0])
    return body[:first], requires_next and body[first + 1:] == ""


def _pathspec_file_entries(pathspec_file, pathspec_cwd, nul=False):
    if not pathspec_cwd:
        return None
    raw = _read_regular_file(pathspec_file, pathspec_cwd)
    if raw is None:
        return None
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        text = raw.decode("utf-8", "surrogateescape")
    entries = text.split("\0") if nul else text.splitlines()
    out = []
    for entry in entries:
        entry = entry.strip()
        if not entry:
            continue
        out.append(entry)
    return out


def _commit_pathspec_mode(args):
    include_mode = False
    only_mode = False
    i = 0
    while i < len(args):
        tok = args[i]
        if _is_shell_redirection(tok):
            i += 2 if _redirection_consumes_next(tok) else 1
            continue
        if tok == "--":
            break
        if tok == "--include":
            include_mode = True
            only_mode = False
            i += 1
            continue
        if tok == "--no-include":
            include_mode = False
            i += 1
            continue
        if tok == "--only":
            include_mode = False
            only_mode = True
            i += 1
            continue
        if tok == "--no-only":
            only_mode = False
            i += 1
            continue
        if (
            tok.startswith("--include=")
            or tok.startswith("--only=")
            or tok.startswith("--no-include=")
            or tok.startswith("--no-only=")
        ):
            i += 1
            continue
        if tok in _COMMIT_VALUE_OPTS:
            i += 2
            continue
        if any(tok.startswith(prefix) for prefix in _COMMIT_VALUE_PREFIXES):
            i += 1
            continue
        if tok.startswith("-") and not tok.startswith("--"):
            flags, consumes_next = _short_option_flags_before_value(tok)
            if flags:
                for flag in flags:
                    if flag == "i":
                        include_mode = True
                        only_mode = False
                    elif flag == "o":
                        include_mode = False
                        only_mode = True
            i += 2 if consumes_next else 1
            continue
        i += 1
    return include_mode, only_mode


def _commit_has_reword_fixup(args):
    i = 0
    while i < len(args):
        tok = args[i]
        if _is_shell_redirection(tok):
            i += 2 if _redirection_consumes_next(tok) else 1
            continue
        if tok == "--":
            break
        if tok == "--fixup":
            if i + 1 < len(args) and args[i + 1].startswith("reword:"):
                return True
            i += 2
            continue
        if tok.startswith("--fixup="):
            return tok.split("=", 1)[1].startswith("reword:")
        if tok in _COMMIT_VALUE_OPTS:
            i += 2
            continue
        if any(tok.startswith(prefix) for prefix in _COMMIT_VALUE_PREFIXES):
            i += 1
            continue
        if tok.startswith("-") and not tok.startswith("--"):
            _, consumes_next = _short_option_flags_before_value(tok)
            i += 2 if consumes_next else 1
            continue
        i += 1
    return False


def _commit_tasks_selection(args, root=None, pathspec_cwd=None, git_args=None, cwd=None):
    i = 0
    after_double_dash = False
    pathspec_file_nul = "--pathspec-file-nul" in args
    explicit_pathspec = False
    all_mode = False
    include_mode, only_mode = _commit_pathspec_mode(args)
    only_mode = only_mode or _commit_has_reword_fixup(args)
    worktree_paths = set()
    excluded_worktree_paths = set()
    positive_pathspec = False
    git_args = git_args or []
    cwd = cwd or pathspec_cwd or root

    def add_pathspec(pathspec, includes_index):
        nonlocal explicit_pathspec, positive_pathspec
        exclude_payload = _exclude_pathspec_payload(pathspec)
        live_paths = _pathspec_live_tasks_paths(
            exclude_payload if exclude_payload is not None else pathspec, git_args, cwd,
            allow_unmatched=exclude_payload is not None,
        )
        if live_paths is None:
            return False
        if exclude_payload is not None:
            excluded_worktree_paths.update(live_paths)
            worktree_paths.difference_update(live_paths)
        else:
            positive_pathspec = True
            worktree_paths.update(live_paths - excluded_worktree_paths)
        if not includes_index:
            explicit_pathspec = True
        return True

    def add_pathspec_file(pathspec_file, includes_index):
        entries = _pathspec_file_entries(pathspec_file, pathspec_cwd, pathspec_file_nul)
        if entries is None:
            return False
        for entry in entries:
            if not add_pathspec(entry, includes_index):
                return False
        return True

    while i < len(args):
        tok = args[i]
        if _is_shell_redirection(tok):
            i += 2 if _redirection_consumes_next(tok) else 1
            continue
        if tok == "(":
            i = _skip_balanced_shell_group(args, i)
            continue
        if after_double_dash:
            if not add_pathspec(tok, include_mode):
                return None
            i += 1
            continue
        if tok == "--":
            after_double_dash = True
            i += 1
            continue
        if tok == "--pathspec-from-file":
            if i + 1 >= len(args):
                return None
            if not add_pathspec_file(args[i + 1], include_mode):
                return None
            i += 2
            continue
        if tok.startswith("--pathspec-from-file="):
            if not add_pathspec_file(tok.split("=", 1)[1], include_mode):
                return None
            i += 1
            continue
        if tok == "--all":
            all_mode = True
            i += 1
            continue
        if tok == "--no-all":
            all_mode = False
            i += 1
            continue
        if tok.startswith("--all="):
            return None
        if tok in {"--patch", "--interactive"}:
            return None
        if tok in {"--include", "--no-include", "--only", "--no-only"}:
            i += 1
            continue
        if (
            tok.startswith("--include=")
            or tok.startswith("--only=")
            or tok.startswith("--no-include=")
            or tok.startswith("--no-only=")
        ):
            return None
        if tok in _COMMIT_VALUE_OPTS:
            i += 2
            continue
        if any(tok.startswith(prefix) for prefix in _COMMIT_VALUE_PREFIXES):
            i += 1
            continue
        if tok.startswith("-") and not tok.startswith("--"):
            flags, consumes_next = _short_option_flags_before_value(tok)
            if flags is not None and "p" in flags:
                return None
            if flags is not None and "a" in flags:
                all_mode = True
            if consumes_next:
                i += 2
                continue
            i += 1
            continue
        if not tok.startswith("-"):
            if not add_pathspec(tok, include_mode):
                return None
        i += 1
    if explicit_pathspec and not positive_pathspec:
        live_paths = _pathspec_live_tasks_paths(".", git_args, root or cwd)
        if live_paths is None:
            return None
        worktree_paths.update(live_paths - excluded_worktree_paths)
    if all_mode and not only_mode:
        return {"base": _COMMIT_TASKS_WORKTREE, "worktree_paths": set()}
    return {
        "base": (
            _COMMIT_TASKS_HEAD
            if explicit_pathspec or only_mode
            else _COMMIT_TASKS_INDEX
        ),
        "worktree_paths": worktree_paths,
    }


def _commit_is_dry_run(args):
    dry_run = False
    status_dry_run = False
    nul_status_dry_run = False
    i = 0
    while i < len(args):
        tok = args[i]
        if _is_shell_redirection(tok):
            i += 2 if _redirection_consumes_next(tok) else 1
            continue
        if tok == "--":
            break
        if tok in _COMMIT_VALUE_OPTS:
            i += 2
            continue
        if any(tok.startswith(prefix) for prefix in _COMMIT_VALUE_PREFIXES):
            i += 1
            continue
        if tok.startswith("-") and not tok.startswith("--"):
            flags, consumes_next = _short_option_flags_before_value(tok)
            if flags and "z" in flags:
                nul_status_dry_run = True
            i += 2 if consumes_next else 1
            continue
        if tok == "--dry-run":
            dry_run = True
        elif tok == "--no-dry-run":
            dry_run = False
        elif tok in _COMMIT_STATUS_DRY_RUN_OPTS:
            status_dry_run = True
        elif tok in _COMMIT_STATUS_DRY_RUN_NEGATED_OPTS:
            status_dry_run = False
        i += 1
    return dry_run or status_dry_run or nul_status_dry_run


def _shared_unchecked_task_patterns():
    try:
        with open(_TASKS_DRIFT_LIB, encoding="utf-8") as f:
            body = f.read()
    except Exception:
        return None
    m = re.search(r"tasks_drift_unchecked_ids\(\)\s*\{(?P<body>.*?)\n\}", body, re.S)
    if not m:
        return None
    fn = m.group("body")
    line_pattern = re.search(r"grep\s+-hoE\s+(['\"])(?P<pat>.*?)\1\s+specs/\*/tasks\.md", fn, re.S)
    id_pattern = re.search(r"\|\s*grep\s+-oE\s+(['\"])(?P<pat>.*?)\1", fn, re.S)
    if not line_pattern or not id_pattern:
        return None
    try:
        return re.compile(line_pattern.group("pat")), re.compile(id_pattern.group("pat"))
    except re.error:
        return None


def _unchecked_ids_from_text(text):
    patterns = _shared_unchecked_task_patterns()
    if patterns is None:
        return None
    line_re, id_re = patterns
    out = set()
    for line in text.splitlines():
        m = line_re.search(line)
        if not m:
            continue
        id_match = id_re.search(m.group(0))
        if id_match:
            out.add(id_match.group(0))
    return out


def _live_tasks_paths_in_worktree(root, git_args=None, cwd=None):
    tracked = _git(
        (git_args or []) + ["-C", root, "ls-files", "--full-name", "--", "specs"],
        cwd or root,
    )
    if tracked is None:
        return None
    paths = set()
    for rel in tracked.splitlines():
        rel = rel.replace("\\", "/")
        if rel and _is_live_tasks_pathspec(rel) and os.path.isfile(os.path.join(root, rel)):
            paths.add(rel)
    return paths if paths else None


def _live_tasks_paths_in_index(root, git_args=None, cwd=None):
    tracked = _git(
        (git_args or []) + ["-C", root, "ls-files", "--full-name", "--", "specs"],
        cwd or root,
    )
    if tracked is None:
        return None
    paths = {
        rel.replace("\\", "/")
        for rel in tracked.splitlines()
        if rel and _is_live_tasks_pathspec(rel)
    }
    return paths if paths else None


def _live_tasks_paths_in_head(root, git_args=None, cwd=None):
    tracked = _git(
        (git_args or []) + [
            "-C", root, "ls-tree", "-r", "--name-only", "HEAD", "--", "specs",
        ],
        cwd or root,
    )
    if tracked is None:
        return None
    paths = {
        rel.replace("\\", "/")
        for rel in tracked.splitlines()
        if rel and _is_live_tasks_pathspec(rel)
    }
    return paths if paths else None


def _live_tasks_paths(root, view, git_args=None, cwd=None):
    if view == _COMMIT_TASKS_WORKTREE:
        return _live_tasks_paths_in_worktree(root, git_args, cwd)
    if view == _COMMIT_TASKS_HEAD:
        return _live_tasks_paths_in_head(root, git_args, cwd)
    return _live_tasks_paths_in_index(root, git_args, cwd)


def _tasks_text_in_view(root, view, rel, git_args=None, cwd=None):
    if view == _COMMIT_TASKS_WORKTREE:
        path = os.path.join(root, rel)
        try:
            if not os.path.isfile(path):
                return None
            with open(path, encoding="utf-8") as f:
                return f.read()
        except Exception:
            return None
    if view == _COMMIT_TASKS_HEAD:
        return _git((git_args or []) + ["show", "HEAD:{}".format(rel)], cwd or root)
    return _git((git_args or []) + ["show", ":{}".format(rel)], cwd or root)


def _unchecked_task_ids_in_commit_view(root, base_view, worktree_paths=None, git_args=None, cwd=None):
    worktree_paths = set(worktree_paths or ())
    base_paths = _live_tasks_paths(root, base_view, git_args, cwd)
    if base_paths is None:
        if not worktree_paths:
            return None
        base_paths = set()
    ids = set()
    seen = False
    for rel in sorted(base_paths | worktree_paths):
        view = _COMMIT_TASKS_WORKTREE if rel in worktree_paths else base_view
        content = _tasks_text_in_view(root, view, rel, git_args, cwd)
        if content is None:
            continue
        unchecked = _unchecked_ids_from_text(content)
        if unchecked is None:
            return None
        seen = True
        ids.update(unchecked)
    return ids if seen else None


def _unchecked_task_ids_in_worktree(root):
    return _unchecked_task_ids_in_commit_view(root, _COMMIT_TASKS_WORKTREE)


def _unchecked_task_ids_in_index(root):
    return _unchecked_task_ids_in_commit_view(root, _COMMIT_TASKS_INDEX)


def _unchecked_task_ids_in_head(root):
    return _unchecked_task_ids_in_commit_view(root, _COMMIT_TASKS_HEAD)


def _rule_commit_tasks_drift(command, base, cwd):
    invocations = _split_commit_invocations(command, cwd)
    if not invocations:
        return None
    for invocation in invocations:
        if _commit_is_dry_run(invocation["args"]):
            continue
        pending = _task_ids_from_commit_message(
            invocation["args"],
            invocation.get("cwd") or cwd,
            invocation["git_args"],
            invocation.get("stdin"),
        )
        if not pending:
            continue
        root = _commit_invocation_root(invocation, cwd)
        if not root:
            continue
        commit_cwd = invocation.get("cwd") or cwd
        selection = _commit_tasks_selection(
            invocation["args"], root, commit_cwd, invocation["git_args"], commit_cwd,
        )
        if selection is None:
            continue
        unchecked = _unchecked_task_ids_in_commit_view(
            root,
            selection["base"],
            selection.get("worktree_paths"),
            invocation["git_args"],
            invocation.get("cwd") or cwd,
        )
        if unchecked is None:
            continue
        drifted = [task_id for task_id in pending if task_id in unchecked]
        if drifted:
            refs = " ".join("[{}]".format(task_id) for task_id in drifted)
            return _deny(
                "commit-tasks-drift",
                "this commit's message references {} but that task's box in specs/*/tasks.md "
                "is still '- [ ]' in what this commit will land. Tick the box and stage it in "
                "this commit, or drop the id if the work is not that task's.".format(refs),
            )
    return None


# Rule 4 — a push whose refspec targets the base branch, from ANY current branch.
# `[^";&|]*` confines the match to a single command (so `git push <branch> && gh ...`
# is untouched); the destination ref is matched after a ':' or whitespace.
def _rule_push_refspec_base(command, base, cwd=None):
    pat = (
        r"git" + _GRUN + r"\s+push[^\";&|]*(?::|\s)(?:refs/heads/)?"
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
    _rule_commit_tasks_drift,
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
# [edit guard] — delta-based fix-forward lint reject.
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
    """The `tool_call`-phase guard policy: rules 1-7. Returns a configured evaluator."""
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
