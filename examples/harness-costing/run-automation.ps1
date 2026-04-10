# =============================================================================
# run-automation.ps1 - Windows 自动化任务循环
# =============================================================================
# 用法：powershell -ExecutionPolicy Bypass -File run-automation.ps1 38
# 参数：总运行轮数（默认 38，即 task.json 中的任务总数）
# =============================================================================

param(
    [int]$TotalRuns = 38
)

# 日志目录
$LogDir = ".\automation-logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = "$LogDir\automation-$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

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
    if (Test-Path "task.json") {
        $content = Get-Content "task.json" -Raw
        return ([regex]::Matches($content, '"status":\s*"pending"')).Count
    }
    return 0
}

# Banner
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  高压线束精算引擎 — 自动化开发循环" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 检查必要文件
foreach ($file in @("task.json", "CLAUDE.md", "app_spec.md")) {
    if (-not (Test-Path $file)) {
        Write-Log "ERROR" "$file 未找到！请确保在项目根目录运行。"
        exit 1
    }
}

# 创建 test-screenshots 目录
New-Item -ItemType Directory -Force -Path ".\test-screenshots" | Out-Null

$InitialTasks = Get-PendingTaskCount
Write-Log "INFO" "开始自动化，计划运行 $TotalRuns 轮"
Write-Log "INFO" "剩余任务: $InitialTasks"
Write-Log "INFO" "日志文件: $LogFile"

# Prompt 模板
$Prompt = @"
Please follow the workflow in CLAUDE.md:
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

# 主循环
for ($run = 1; $run -le $TotalRuns; $run++) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Log "PROGRESS" "第 $run / $TotalRuns 轮"
    Write-Host "========================================" -ForegroundColor Cyan
    
    $remaining = Get-PendingTaskCount
    
    if ($remaining -eq 0) {
        Write-Log "SUCCESS" "所有任务已完成！"
        break
    }
    
    Write-Log "INFO" "本轮开始前剩余任务: $remaining"
    
    $runStart = Get-Date
    $runLog = "$LogDir\run-$run-$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    
    Write-Log "INFO" "启动 Claude Code session..."
    
    # 用 -p 模式运行（非交互，执行完自动退出）
    # 注意：根据你的 Claude Code 版本，可能需要调整命令
    try {
        $Prompt | & "C:\Users\lyvee\.bun\bin\bun.exe" run dev -- -p `
            --dangerously-skip-permissions `
            --allowed-tools "Bash Edit Read Write Glob Grep Task WebSearch WebFetch mcp__playwright__*" `
            2>&1 | Tee-Object -FilePath $runLog
    }
    catch {
        Write-Log "WARNING" "第 $run 轮异常退出: $_"
    }
    
    $runEnd = Get-Date
    $duration = ($runEnd - $runStart).TotalSeconds
    
    $remainingAfter = Get-PendingTaskCount
    $completed = $remaining - $remainingAfter
    
    if ($completed -gt 0) {
        Write-Log "SUCCESS" "第 $run 轮完成 $completed 个任务 (耗时 ${duration}s)"
    } else {
        Write-Log "WARNING" "第 $run 轮未完成任何任务 (耗时 ${duration}s)"
    }
    
    Write-Log "INFO" "剩余任务: $remainingAfter"
    
    # 轮间等待
    if ($run -lt $TotalRuns -and $remainingAfter -gt 0) {
        Write-Log "INFO" "等待 3 秒后开始下一轮..."
        Start-Sleep -Seconds 3
    }
}

# 最终汇总
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Log "SUCCESS" "自动化运行结束！"
Write-Host "========================================" -ForegroundColor Green

$finalRemaining = Get-PendingTaskCount
$totalCompleted = $InitialTasks - $finalRemaining

Write-Log "INFO" "汇总:"
Write-Log "INFO" "  总轮数: $TotalRuns"
Write-Log "INFO" "  完成任务: $totalCompleted"
Write-Log "INFO" "  剩余任务: $finalRemaining"
Write-Log "INFO" "  日志文件: $LogFile"

if ($finalRemaining -eq 0) {
    Write-Log "SUCCESS" "所有任务已完成！🎉"
} else {
    Write-Log "WARNING" "仍有 $finalRemaining 个任务未完成，可能需要更多轮次或人工介入。"
}
