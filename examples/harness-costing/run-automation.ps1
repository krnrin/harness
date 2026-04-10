# =============================================================================
# run-automation.ps1 - Windows Automated Task Loop (Interactive Mode)
# =============================================================================
# Usage: powershell -ExecutionPolicy Bypass -File run-automation.ps1 38
# Param: Total rounds (default 38 = total tasks in task.json)
# =============================================================================

param(
    [int]$TotalRuns = 38
)

# Project directory = where this script is run from (absolute)
$ProjectDir = (Get-Location).Path

# Log directory (absolute path)
$LogDir = Join-Path $ProjectDir "automation-logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir "automation-$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Claude Code source directory (where bun run dev works)
$ClaudeCodeDir = "C:\Users\lyvee\source\cloud-code"

function Write-Log {
    param([string]$Level, [string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logLine = "$timestamp [$Level] $Message"
    Add-Content -Path $script:LogFile -Value $logLine
    
    switch ($Level) {
        "INFO"     { Write-Host "[INFO] $Message" -ForegroundColor Blue }
        "SUCCESS"  { Write-Host "[SUCCESS] $Message" -ForegroundColor Green }
        "WARNING"  { Write-Host "[WARNING] $Message" -ForegroundColor Yellow }
        "ERROR"    { Write-Host "[ERROR] $Message" -ForegroundColor Red }
        "PROGRESS" { Write-Host "[PROGRESS] $Message" -ForegroundColor Cyan }
    }
}

function Get-PendingTaskCount {
    $taskFile = Join-Path $script:ProjectDir "task.json"
    if (Test-Path $taskFile) {
        $content = Get-Content $taskFile -Raw
        return ([regex]::Matches($content, '"status":\s*"pending"')).Count
    }
    return 0
}

# Banner
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Harness Costing Engine - Auto Dev Loop" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check required files
foreach ($file in @("task.json", "CLAUDE.md", "app_spec.md")) {
    $fullPath = Join-Path $ProjectDir $file
    if (-not (Test-Path $fullPath)) {
        Write-Log "ERROR" "$file not found! Make sure you run from project root."
        exit 1
    }
}

# Create test-screenshots dir
New-Item -ItemType Directory -Force -Path (Join-Path $ProjectDir "test-screenshots") | Out-Null

$InitialTasks = Get-PendingTaskCount
Write-Log "INFO" "Starting automation, planned $TotalRuns rounds"
Write-Log "INFO" "Project dir: $ProjectDir"
Write-Log "INFO" "Claude Code dir: $ClaudeCodeDir"
Write-Log "INFO" "Remaining tasks: $InitialTasks"
Write-Log "INFO" "Log file: $LogFile"

# Prompt - will be piped via stdin (no -p flag, uses interactive auth)
$Prompt = @"
cd $ProjectDir

Read CLAUDE.md and task.json. Find the next pending task with status "pending" (respect depends_on, pick smallest id that has all deps done). Implement it fully:
- Backend: create models, routes, services as specified in scope
- Frontend: create pages, components as specified in scope
- Test: pytest for backend, build check for frontend
- Update progress.txt with what you did
- Update task.json: set this task's status to "done"
- Git commit ALL changes in a single commit

Complete exactly ONE task, then type /exit to quit.
Do NOT ask questions. Do NOT wait for confirmation. Just do it and exit.
"@

# Main loop
for ($run = 1; $run -le $TotalRuns; $run++) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Log "PROGRESS" "Round $run / $TotalRuns"
    Write-Host "========================================" -ForegroundColor Cyan
    
    $remaining = Get-PendingTaskCount
    
    if ($remaining -eq 0) {
        Write-Log "SUCCESS" "All tasks completed!"
        break
    }
    
    Write-Log "INFO" "Tasks remaining before this round: $remaining"
    
    $runStart = Get-Date
    $runLog = Join-Path $LogDir "run-$run-$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    
    Write-Log "INFO" "Starting Claude Code session (interactive mode via stdin)..."
    
    # Use stdin pipe instead of -p flag to avoid auth issues with GPT fork
    # When stdin closes, the process should exit
    try {
        Push-Location $ClaudeCodeDir
        $Prompt | & "C:\Users\lyvee\.bun\bin\bun.exe" run dev -- `
            --dangerously-skip-permissions `
            --add-dir "$ProjectDir" `
            --allowed-tools "Bash Edit Read Write Glob Grep Task WebSearch WebFetch mcp__playwright__*" `
            2>&1 | Tee-Object -FilePath $runLog
    }
    catch {
        Write-Log "WARNING" "Round $run exited abnormally: $_"
    }
    finally {
        Pop-Location
    }
    
    $runEnd = Get-Date
    $duration = ($runEnd - $runStart).TotalSeconds
    
    $remainingAfter = Get-PendingTaskCount
    $completed = $remaining - $remainingAfter
    
    if ($completed -gt 0) {
        Write-Log "SUCCESS" "Round $run completed $completed task(s) (${duration}s)"
    } else {
        Write-Log "WARNING" "Round $run completed 0 tasks (${duration}s)"
    }
    
    Write-Log "INFO" "Remaining tasks: $remainingAfter"
    
    # Wait between rounds
    if ($run -lt $TotalRuns -and $remainingAfter -gt 0) {
        Write-Log "INFO" "Waiting 5 seconds before next round..."
        Start-Sleep -Seconds 5
    }
}

# Final summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Log "SUCCESS" "Automation run finished!"
Write-Host "========================================" -ForegroundColor Green

$finalRemaining = Get-PendingTaskCount
$totalCompleted = $InitialTasks - $finalRemaining

Write-Log "INFO" "Summary:"
Write-Log "INFO" "  Total rounds: $TotalRuns"
Write-Log "INFO" "  Tasks completed: $totalCompleted"
Write-Log "INFO" "  Tasks remaining: $finalRemaining"
Write-Log "INFO" "  Log file: $LogFile"

if ($finalRemaining -eq 0) {
    Write-Log "SUCCESS" "All tasks completed!"
} else {
    Write-Log "WARNING" "$finalRemaining task(s) remain. May need more rounds or manual intervention."
}
