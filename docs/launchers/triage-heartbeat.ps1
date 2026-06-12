# triage-heartbeat.ps1 — Windows Task Scheduler launcher template for the /triage
# dead-man switch (PowerShell 5.1 compatible).
#
# Implements the launcher contract in .claude/workflow/triage.md §6. The contract,
# not this script, is normative — every rewrite must honor it:
#   1. One line per attempt, appended to a run log next to the inbox; inbox + run-log
#      paths passed IN THE PROMPT TEXT (the explicit-context rule), env vars as
#      redundant hints only.
#   2. The line is UNCONDITIONAL (try/finally) — even a crash writes exit=1.
#   3. Appended AFTER the agent exits, so the last line always describes a completed
#      attempt.
#   4. Nonzero exit propagates to the scheduler.
#
# Register (daily 07:30):
#   Register-ScheduledTask -TaskName "<Project>-TriageHeartbeat" `
#     -Action (New-ScheduledTaskAction -Execute "powershell.exe" `
#       -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\path\to\triage-heartbeat.ps1") `
#     -Trigger (New-ScheduledTaskTrigger -Daily -At 07:30)

# ── Configure these for your machine (absolute paths — never rely on cwd) ──────
$RepoRoot  = "C:\dev\<your-repo>"
$Inbox     = "C:\dev\<out-of-repo-inbox-dir>\triage-inbox.md"   # OUT of the repo by design
$Model     = "<cheap-tier row of .claude/MODELS.md>"
$TokenFile = "$env:USERPROFILE\.claude\.oauth-token"             # see docs/headless-auth.md
$ClaudeBin = "claude"                                            # fall back to the absolute
                                                                 # install path if not on PATH
# ────────────────────────────────────────────────────────────────────────────────

$RunLog = Join-Path (Split-Path $Inbox -Parent) ((Split-Path $RepoRoot -Leaf) + "-heartbeat.log")
$start  = Get-Date
$code   = 1
$note   = "launcher died before invoking the agent"

try {
    # Skip if today's attempt already succeeded (re-fired schedulers stay idempotent).
    if ((Test-Path $RunLog) -and
        ((Get-Content $RunLog -Tail 1) -match ("^" + (Get-Date -Format yyyy-MM-dd) + ".*exit=0"))) {
        $code = 0; $note = "skip: already ran today"
        return
    }

    if (-not (Test-Path $TokenFile)) {
        $note = "auth: .oauth-token missing"
        return
    }
    $env:CLAUDE_CODE_OAUTH_TOKEN = (Get-Content $TokenFile -Raw).Trim()

    # Contract rule 1 / explicit-context rule: every value the run must honor goes in
    # the PROMPT TEXT. Env vars below are redundant hints only — never the only carrier.
    $env:TRIAGE_INBOX  = $Inbox
    $env:TRIAGE_RUNLOG = $RunLog
    $Prompt = "/triage run log: $RunLog. inbox: $Inbox. repo root: $RepoRoot."

    Set-Location $RepoRoot

    # --dangerously-skip-permissions: deliberate for unattended runs (a permission
    # prompt would hang forever). Compensating controls: the deterministic guard hook +
    # /triage's read-only contract. See docs/headless-auth.md before enabling.
    & $ClaudeBin -p $Prompt --model $Model --dangerously-skip-permissions
    $code = $LASTEXITCODE
    $note = if ($code -eq 0) { "ok" } else { "agent exited nonzero" }
}
catch {
    $code = 1
    $note = "launcher exception: " + $_.Exception.Message
}
finally {
    # Contract rules 2+3: unconditional, written after the agent exits.
    $dur  = [int]((Get-Date) - $start).TotalSeconds
    $line = "{0} exit={1} duration={2}s note={3}" -f `
        (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"), $code, $dur, $note
    $line | Out-File -FilePath $RunLog -Append -Encoding utf8
    exit $code   # rule 4: the scheduler's "last result" stays truthful
}
