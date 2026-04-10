# =============================================================================
# run-loop.ps1 - Auto loop with task.json monitoring + process timeout
# =============================================================================
# Usage: powershell -ExecutionPolicy Bypass -File run-loop.ps1 37
#
# How it works:
# 1. Records pending task count before starting
# 2. Launches bun -p mode as a background process
# 3. Polls task.json every 30s for changes
# 4. When pending count decreases OR git has new commits -> task done, kill & next
# 5. Hard timeout (45 min) as safety net
# =============================================================================

param(
    [int]$TotalRuns = 37
)

$ProjectDir = "D:\harness-project"
$ClaudeCodeDir = "C:\Users\lyvee\source\cloud-code"
$BunExe = "C:\Users\lyvee\.bun\bin\bun.exe"
$TaskFile = Join-Path $ProjectDir "task.json"
$ProgressFile = Join-Path $ProjectDir "progress.txt"
$HardTimeoutMin = 45
$PollIntervalSec = 30

$LogDir = Join-Path $ProjectDir "automation-logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Get-PendingCount {
    if (Test-Path $TaskFile) {
        return ([regex]::Matches((Get-Content $TaskFile -Raw), '"status":\s*"pending"')).Count
    }
    return 0
}

function Get-DoneCount {
    if (Test-Path $TaskFile) {
        return ([regex]::Matches((Get-Content $TaskFile -Raw), '"status":\s*"done"')).Count
    }
    return 0
}

function Get-LastCommit {
    try {
        return (git -C $ProjectDir log --oneline -1 2>$null)
    } catch {
        return ""
    }
}

$InitPending = Get-PendingCount
$InitDone = Get-DoneCount

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Harness Costing - Smart Auto Loop" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "[INFO] Pending: $InitPending | Done: $InitDone | Rounds: $TotalRuns" -ForegroundColor Blue
Write-Host "[INFO] Hard timeout: $HardTimeoutMin min | Poll: every $PollIntervalSec s" -ForegroundColor Blue
Write-Host ""

$Prompt = "You are in $ProjectDir. Read CLAUDE.md for project rules, then read task.json. Find the next pending task (respect depends_on, pick smallest id with all deps done). Implement it fully including backend and frontend code, run tests, update progress.txt, mark task done in task.json, and git commit all changes. Complete ONE task then exit."

for ($round = 1; $round -le $TotalRuns; $round++) {
    $pending = Get-PendingCount
    $done = Get-DoneCount

    if ($pending -eq 0) {
        Write-Host "[SUCCESS] All tasks completed! ($done done)" -ForegroundColor Green
        break
    }

    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "[Round $round / $TotalRuns] Pending: $pending | Done: $done" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    $lastCommit = Get-LastCommit
    $roundStart = Get-Date
    $runLog = Join-Path $LogDir ("round-" + $round + "-" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".log")

    # Launch bun as background process
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $BunExe
    $psi.Arguments = "run dev -- -p `"$Prompt`" --dangerously-skip-permissions --add-dir `"$ProjectDir`" --allowed-tools `"Bash Edit Read Write Glob Grep Task WebSearch WebFetch mcp__playwright__*`""
    $psi.WorkingDirectory = $ClaudeCodeDir
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $false
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    Write-Host "[INFO] Launching GPT-5.4..." -ForegroundColor Blue
    $process = [System.Diagnostics.Process]::Start($psi)
    $processId = $process.Id
    Write-Host "[INFO] Process PID: $processId" -ForegroundColor Blue

    # Poll loop: check task.json + git log for changes
    $taskCompleted = $false
    $timedOut = $false
    $stableCount = 0
    $requiredStable = 2  # Need 2 consecutive checks showing change (60s stability)

    while (-not $process.HasExited) {
        Start-Sleep -Seconds $PollIntervalSec

        $elapsed = [math]::Round(((Get-Date) - $roundStart).TotalMinutes, 1)

        # Hard timeout
        if ($elapsed -gt $HardTimeoutMin) {
            Write-Host "[WARNING] Hard timeout ($HardTimeoutMin min). Killing process..." -ForegroundColor Yellow
            $timedOut = $true
            break
        }

        # Check if task completed
        $currentPending = Get-PendingCount
        $currentDone = Get-DoneCount
        $currentCommit = Get-LastCommit

        Write-Host "[POLL $elapsed min] Pending: $currentPending | Done: $currentDone | Commit: $($currentCommit.Substring(0, [Math]::Min(20, $currentCommit.Length)))" -ForegroundColor DarkGray

        # Detect completion: pending decreased OR done increased OR new commit
        if ($currentPending -lt $pending -or $currentDone -gt $done -or $currentCommit -ne $lastCommit) {
            $stableCount++
            Write-Host "[DETECT] Change detected ($stableCount / $requiredStable)..." -ForegroundColor Yellow

            if ($stableCount -ge $requiredStable) {
                Write-Host "[SUCCESS] Task completed! Pending: $currentPending | Done: $currentDone" -ForegroundColor Green
                $taskCompleted = $true
                # Wait a bit more for git commit to finish
                Start-Sleep -Seconds 10
                break
            }
        } else {
            $stableCount = 0
        }
    }

    # Kill process if still running
    if (-not $process.HasExited) {
        try {
            # Kill the process tree
            Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
            # Also kill any child bun processes
            Get-Process -Name "bun" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        } catch {}
        Write-Host "[INFO] Process killed." -ForegroundColor Blue
    }

    # Capture any output
    try {
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        ($stdout + "`n" + $stderr) | Set-Content -Path $runLog -Encoding UTF8
    } catch {}

    try { $process.Dispose() } catch {}

    $secs = [math]::Round(((Get-Date) - $roundStart).TotalSeconds)
    $finalPending = Get-PendingCount
    $finalDone = Get-DoneCount
    $tasksThisRound = $done - $finalDone
    $tasksThisRound = $finalDone - $done
    if ($tasksThisRound -lt 0) { $tasksThisRound = 0 }

    if ($taskCompleted) {
        Write-Host "[SUCCESS] Round $round done: $tasksThisRound task(s) in $secs s" -ForegroundColor Green
    } elseif ($timedOut) {
        Write-Host "[WARNING] Round $round timed out after $secs s" -ForegroundColor Yellow
    } elseif ($process.HasExited) {
        Write-Host "[INFO] Round $round: process exited in $secs s (tasks completed: $tasksThisRound)" -ForegroundColor Blue
    }

    Write-Host "[INFO] Total progress: $finalDone done, $finalPending pending" -ForegroundColor Blue
    Write-Host ""

    if ($finalPending -eq 0) {
        Write-Host "[SUCCESS] All tasks completed!" -ForegroundColor Green
        break
    }

    # Brief pause before next round
    Write-Host "[INFO] Starting next round in 5s..." -ForegroundColor Blue
    Start-Sleep -Seconds 5
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Automation Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
$finalDone = Get-DoneCount
$finalPending = Get-PendingCount
Write-Host "[RESULT] Done: $finalDone | Pending: $finalPending" -ForegroundColor Green
Write-Host "[RESULT] Git log:" -ForegroundColor Green
git -C $ProjectDir log --oneline -10
