# =============================================================================
# run-automation.ps1 - Windows Automated Task Loop (-p mode)
# =============================================================================
# Usage: powershell -ExecutionPolicy Bypass -File run-automation.ps1 38
# Param: Total rounds (default 38 = total tasks in task.json)
# Prerequisites:
#   1. Junction: cmd /c mklink /J D:\harness-project "D:\<your-chinese-path>"
#   2. Valid token selected in cloud-code interactive mode
# =============================================================================

param(
    [int]$TotalRuns = 38
)

$ProjectDir = "D:\harness-project"
$ClaudeCodeDir = "C:\Users\lyvee\source\cloud-code"
$BunExe = "C:\Users\lyvee\.bun\bin\bun.exe"

# Log directory (absolute path)
$LogDir = Join-Path $ProjectDir "automation-logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir "automation-$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-Log {
    param([string]$Level, [string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logLine = "$timestamp [$Level] $Message"
    Add-Content -Path $LogFile -Value $logLine
    switch ($Level) {
        "INFO"     { Write-Host "[INFO] $Message" -ForegroundColor Blue }
        "SUCCESS"  { Write-Host "[SUCCESS] $Message" -ForegroundColor Green }
        "WARNING"  { Write-Host "[WARNING] $Message" -ForegroundColor Yellow }
        "ERROR"    { Write-Host "[ERROR] $Message" -ForegroundColor Red }
        "PROGRESS" { Write-Host "[PROGRESS] $Message" -ForegroundColor Cyan }
    }
}

function Get-PendingTaskCount {
    $taskFile = Join-Path $ProjectDir "task.json"
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

# Check junction exists
if (-not (Test-Path $ProjectDir)) {
    Write-Log "ERROR" "$ProjectDir not found! Create junction first:"
    Write-Log "ERROR" '  cmd /c mklink /J D:\harness-project "D:\<your-path>"'
    exit 1
}

# Check required files
foreach ($file in @("task.json", "CLAUDE.md", "app_spec.md")) {
    $fullPath = Join-Path $ProjectDir $file
    if (-not (Test-Path $fullPath)) {
        Write-Log "ERROR" "$file not found in $ProjectDir!"
        exit 1
    }
}

New-Item -ItemType Directory -Force -Path (Join-Path $ProjectDir "test-screenshots") | Out-Null

$InitialTasks = Get-PendingTaskCount
Write-Log "INFO" "Starting automation, planned $TotalRuns rounds"
Write-Log "INFO" "Project dir: $ProjectDir"
Write-Log "INFO" "Remaining tasks: $InitialTasks"
Write-Log "INFO" "Log file: $LogFile"

# Prompt for -p mode
$Prompt = @"
cd $ProjectDir
Read CLAUDE.md and task.json. Find the next pending task with status "pending" (respect depends_on, pick smallest id that has all deps done). Implement it fully:
- Backend: create models, routes, services as specified
- Frontend: create pages, components as specified
- Test: pytest for backend, build check for frontend
- Update progress.txt with what you did
- Update task.json: set this task status to "done"
- Git commit ALL changes in a single commit
Complete exactly ONE task then exit.
Do NOT ask questions. Do NOT wait for confirmation. Just do it.
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

    Write-Log "INFO" "Tasks remaining: $remaining"
    $runStart = Get-Date
    $runLog = Join-Path $LogDir "run-$run-$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

    Write-Log "INFO" "Starting Claude Code -p mode..."

    try {
        Push-Location $ClaudeCodeDir
        & $BunExe run dev -- -p $Prompt `
            --dangerously-skip-permissions `
            --add-dir $ProjectDir `
            --allowed-tools "Bash Edit Read Write Glob Grep Task WebSearch WebFetch mcp__playwright__*" `
            2>&1 | Tee-Object -FilePath $runLog
    }
    catch {
        Write-Log "WARNING" "Round $run exception: $_"
    }
    finally {
        Pop-Location
    }

    $duration = ((Get-Date) - $runStart).TotalSeconds
    $remainingAfter = Get-PendingTaskCount
    $completed = $remaining - $remainingAfter

    if ($completed -gt 0) {
        Write-Log "SUCCESS" "Round $run: $completed task(s) done (${duration}s)"
    } else {
        Write-Log "WARNING" "Round $run: 0 tasks done (${duration}s) - may need attention"
    }

    Write-Log "INFO" "Remaining tasks: $remainingAfter"

    if ($run -lt $TotalRuns -and $remainingAfter -gt 0) {
        Write-Log "INFO" "Waiting 3 seconds..."
        Start-Sleep -Seconds 3
    }
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Log "SUCCESS" "Automation finished!"
Write-Host "========================================" -ForegroundColor Green

$finalRemaining = Get-PendingTaskCount
$totalCompleted = $InitialTasks - $finalRemaining
Write-Log "INFO" "Completed: $totalCompleted | Remaining: $finalRemaining"
Write-Log "INFO" "Log: $LogFile"
