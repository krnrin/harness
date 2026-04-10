# =============================================================================
# run-loop.ps1 - Auto loop: poll task.json, kill process on completion, repeat
# =============================================================================
# Usage: powershell -ExecutionPolicy Bypass -File run-loop.ps1 37
# =============================================================================

param(
    [int]$TotalRuns = 37
)

$ProjectDir = "D:\harness-project"
$ClaudeCodeDir = "C:\Users\lyvee\source\cloud-code"
$BunExe = "C:\Users\lyvee\.bun\bin\bun.exe"
$TaskFile = Join-Path $ProjectDir "task.json"
$HardTimeoutMin = 45
$PollSec = 30

$LogDir = Join-Path $ProjectDir "automation-logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Get-TaskCount([string]$status) {
    if (Test-Path $TaskFile) {
        $c = Get-Content $TaskFile -Raw
        return ([regex]::Matches($c, ('"status":\s*"' + $status + '"'))).Count
    }
    return 0
}

function Get-HeadCommit {
    $r = git -C $ProjectDir rev-parse HEAD 2>$null
    if ($LASTEXITCODE -eq 0) { return $r } else { return "none" }
}

$Prompt = "You are in $ProjectDir. Read CLAUDE.md for project rules, then read task.json. Find the next pending task (respect depends_on, pick smallest id with all deps done). Implement it fully including backend and frontend code, run tests, update progress.txt, mark task done in task.json, and git commit all changes. Complete ONE task then exit."

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Harness Costing - Smart Auto Loop" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "[INFO] Pending: $(Get-TaskCount 'pending') | Done: $(Get-TaskCount 'done')" -ForegroundColor Blue
Write-Host ""

for ($round = 1; $round -le $TotalRuns; $round++) {
    $pending = Get-TaskCount "pending"
    $done = Get-TaskCount "done"

    if ($pending -eq 0) {
        Write-Host "[DONE] All tasks completed! ($done done)" -ForegroundColor Green
        break
    }

    Write-Host "== Round $round / $TotalRuns == Pending: $pending | Done: $done ==" -ForegroundColor Cyan

    $commitBefore = Get-HeadCommit
    $roundStart = Get-Date

    # Start bun as a Job so we can kill it cleanly without blocking
    $job = Start-Job -ScriptBlock {
        param($BunExe, $ClaudeCodeDir, $Prompt, $ProjectDir)
        Set-Location $ClaudeCodeDir
        & $BunExe run dev -- -p $Prompt --dangerously-skip-permissions --add-dir $ProjectDir --allowed-tools "Bash Edit Read Write Glob Grep Task WebSearch WebFetch mcp__playwright__*" 2>&1
    } -ArgumentList $BunExe, $ClaudeCodeDir, $Prompt, $ProjectDir

    Write-Host "[INFO] Job started (Id: $($job.Id))" -ForegroundColor Blue

    # Poll until task completed or timeout
    $completed = $false
    $stableHits = 0

    while ($true) {
        Start-Sleep -Seconds $PollSec

        $elapsed = [math]::Round(((Get-Date) - $roundStart).TotalMinutes, 1)

        # Hard timeout
        if ($elapsed -gt $HardTimeoutMin) {
            Write-Host "[TIMEOUT] $HardTimeoutMin min reached, moving on." -ForegroundColor Yellow
            break
        }

        # Check job state - if it already finished on its own, great
        if ($job.State -eq "Completed" -or $job.State -eq "Failed") {
            Write-Host "[INFO] Process exited on its own ($($job.State))." -ForegroundColor Blue
            $completed = $true
            break
        }

        # Poll task.json and git
        $nowPending = Get-TaskCount "pending"
        $nowDone = Get-TaskCount "done"
        $nowCommit = Get-HeadCommit

        $changed = ($nowPending -lt $pending) -or ($nowDone -gt $done) -or ($nowCommit -ne $commitBefore)

        if ($changed) {
            $stableHits++
        } else {
            $stableHits = 0
        }

        $shortCommit = if ($nowCommit.Length -gt 8) { $nowCommit.Substring(0, 8) } else { $nowCommit }
        Write-Host "[POLL $elapsed min] P:$nowPending D:$nowDone Commit:$shortCommit Hits:$stableHits" -ForegroundColor DarkGray

        # 2 consecutive hits = confirmed done
        if ($stableHits -ge 2) {
            Write-Host "[DETECTED] Task completed!" -ForegroundColor Green
            $completed = $true
            Start-Sleep -Seconds 10  # Let git commit finish
            break
        }
    }

    # Clean up the job
    Write-Host "[INFO] Stopping job..." -ForegroundColor Blue
    Stop-Job -Job $job -ErrorAction SilentlyContinue
    $output = Receive-Job -Job $job -ErrorAction SilentlyContinue
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue

    # Also kill any leftover bun child processes from the job
    # Only kill bun processes whose command line contains our prompt (safe)
    Get-CimInstance Win32_Process -Filter "Name = 'bun.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match "dangerously-skip-permissions" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

    # Save output to log
    $logFile = Join-Path $LogDir ("round-" + $round + ".log")
    if ($output) { $output | Out-File -FilePath $logFile -Encoding UTF8 }

    $secs = [math]::Round(((Get-Date) - $roundStart).TotalSeconds)
    $afterDone = Get-TaskCount "done"
    $tasksDone = $afterDone - $done

    Write-Host "[RESULT] Round $round: +$tasksDone task(s) in $secs s | Total done: $afterDone" -ForegroundColor $(if ($tasksDone -gt 0) { "Green" } else { "Yellow" })
    Write-Host ""

    # Brief pause
    Start-Sleep -Seconds 5
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  ALL DONE" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "[FINAL] Done: $(Get-TaskCount 'done') | Pending: $(Get-TaskCount 'pending')" -ForegroundColor Green
git -C $ProjectDir log --oneline -15
