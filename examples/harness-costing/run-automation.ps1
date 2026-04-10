# =============================================================================
# run-automation.ps1 - Windows Automated Task Loop
# =============================================================================
# Usage: powershell -ExecutionPolicy Bypass -File run-automation.ps1 38
# Param: Total rounds (default 38 = total tasks in task.json)
# =============================================================================

param(
    [int]$TotalRuns = 38
)

# Project directory = where this script is run from (absolute)
$ProjectDir = (Get-Location).Path

# Log directory (absolute path so Push-Location won't break it)
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

# Prompt template - includes cd to project dir so Claude works there
$Prompt = @"
First, run: cd $ProjectDir

Then follow the workflow in CLAUDE.md:
1. Run .\init.ps1 to initialize the environment
2. Read task.json and select the next task with status: "pending" (respect depends_on)
3. Implement the task following all steps in scope
4. Test thoroughly (pytest for backend, Playwright MCP for frontend)
5. Update progress.txt with your work
6. Update task.json status to "done" and commit all changes in a single commit

Start by reading CLAUDE.md, then task.json to find your task.
Please complete only ONE task in this session, then stop.
Do NOT ask if you should continue. Just finish and exit.
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
    
    Write-Log "INFO" "Starting Claude Code session..."
    
    # Switch to Claude Code dir so bun finds the dev script,
    # then Claude will cd to project dir via the prompt
    try {
        Push-Location $ClaudeCodeDir
        & "C:\Users\lyvee\.bun\bin\bun.exe" run dev -- `
            -p "$Prompt" `
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
        Write-Log "INFO" "Waiting 3 seconds before next round..."
        Start-Sleep -Seconds 3
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
