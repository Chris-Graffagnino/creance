## 0. Preconditions (stop if any fail)
- You're in the canonical repo working tree — `git rev-parse --show-toplevel` succeeds and is
  the project you intend to build (not a stray or cloud-synced duplicate). If not, stop.
- `git status` is clean and you are on an up-to-date base branch. If not, resolve first.
- The issue-tracker interface named by the active adapter's **[environment block]** is
  authenticated using that block's concrete check. If not, ask the user to authenticate
  the named interface before tracker-dependent steps.
- **Usage headroom:** if you're deep into a usage window, do ONE task and stop. An
  interrupted task is recoverable (commit + PR + the resume protocol), so never start work
  you can't checkpoint before the limit hits.

## 0.5 Run mode — review (default) or isolated autonomous
Decide the run's mode once, at the start, from the **[autonomy activation]** check — never from
model memory. It is deterministic and **fails closed to review** (the inverse of the [guard]).
- **Review mode (default).** Run exactly as written below: edit in the main working tree on the
  task branch (§4), open the PR, and **stop** for a human merge.
- **Isolated autonomous mode** — engaged only by an explicit in-session authorization or the
  profile opt-in. The task runs inside an **[isolated workspace]**: **enter** it in place of the
  plain branch (§4) and **tear it down** at the end; work happens there, never in the main tree.
  If entry fails, **abort the run** — never fall back to editing the main tree on the base branch
  (a silent fallback would run un-isolated autonomous work, the one thing isolation prevents).

The §7 gate now reads the workspace diff and the promote/discard path is wired (the gate-in-place
step). On a gate **PASS** the work is **promoted** — opened as a PR through this same §7-gated
path (§8); on a gate **FAIL** the **[isolated workspace]** is **discarded** and nothing is opened.
Promotion is always the §7 gate's PASS, **never a direct write from the workspace** to the base
branch (`workflow/README.md` → "[isolated workspace]"); a FAIL leaves the base branch untouched.
Crucially, **promotion is a PR, not a merge** — merging still requires session-explicit
authorization (§8), so an engaged autonomous run still ends at a PR, not on the base branch. A
deterministic falsification proof that an un-gated change cannot reach the base branch through the
lifecycle — plus a live probe that the isolation tier fires on a real driver — now backs this
property (the enforcing checks are named in the profile's invariant checklist).

Next: [§1 Select the task](02-select-task.md)
