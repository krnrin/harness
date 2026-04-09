#!/bin/bash

# =============================================================================
# run-automation.sh — Lightweight Bash Outer Loop
# =============================================================================
# Alternative to the Python orchestrator (run.py) for simpler workflows.
# Runs Claude Code in a loop, each session picks the next task from
# feature_list.json and implements it.
#
# Usage:
#   ./run-automation.sh <number_of_runs> [project_dir]
#
# Examples:
#   ./run-automation.sh 5 ./output/project    # Run 5 sessions
#   ./run-automation.sh 10                     # Run 10 sessions in current dir
#
# Modes:
#   Manual:     claude (interactive, safest)
#   Semi-auto:  claude -p --dangerously-skip-permissions (main workhorse)
#   Full-auto:  ./run-automation.sh N (unattended, most dangerous)
#
# Based on: SamuelQZQ/auto-coding-agent-demo/run-automation.sh
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Log setup
LOG_DIR="./logs/automation"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/run-$(date +%Y%m%d_%H%M%S).log"

log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" >> "$LOG_FILE"

    case $level in
        INFO)     echo -e "${BLUE}[INFO]${NC} ${message}" ;;
        SUCCESS)  echo -e "${GREEN}[SUCCESS]${NC} ${message}" ;;
        WARNING)  echo -e "${YELLOW}[WARNING]${NC} ${message}" ;;
        ERROR)    echo -e "${RED}[ERROR]${NC} ${message}" ;;
        PROGRESS) echo -e "${CYAN}[PROGRESS]${NC} ${message}" ;;
    esac
}

count_remaining() {
    if [ -f "feature_list.json" ]; then
        grep -c '"passes": false' feature_list.json 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Validate args
if [ -z "$1" ]; then
    echo "Usage: $0 <number_of_runs> [project_dir]"
    echo ""
    echo "Modes:"
    echo "  Manual:     cd <project_dir> && claude"
    echo "  Semi-auto:  cd <project_dir> && claude -p --dangerously-skip-permissions"
    echo "  Full-auto:  $0 <N> [project_dir]"
    exit 1
fi

if ! [[ "$1" =~ ^[0-9]+$ ]]; then
    echo "Error: First argument must be a positive integer"
    exit 1
fi

TOTAL_RUNS=$1
PROJECT_DIR=${2:-.}

# Banner
echo ""
echo "========================================"
echo "  Harness Automation Runner"
echo "========================================"
echo ""

log "INFO" "Starting automation: $TOTAL_RUNS runs in $PROJECT_DIR"
log "INFO" "Log file: $LOG_FILE"

# Validate project
if [ ! -f "$PROJECT_DIR/feature_list.json" ] && [ ! -f "$PROJECT_DIR/app_spec.md" ]; then
    log "ERROR" "No feature_list.json or app_spec.md found in $PROJECT_DIR"
    log "ERROR" "Run 'python run.py' first to generate the project, or create feature_list.json manually."
    exit 1
fi

cd "$PROJECT_DIR"

INITIAL_REMAINING=$(count_remaining)
log "INFO" "Tasks remaining at start: $INITIAL_REMAINING"

# Main loop
for ((run=1; run<=TOTAL_RUNS; run++)); do
    echo ""
    echo "========================================"
    log "PROGRESS" "Run $run of $TOTAL_RUNS"
    echo "========================================"

    REMAINING=$(count_remaining)

    if [ "$REMAINING" -eq 0 ]; then
        log "SUCCESS" "All tasks completed! Stopping early after $((run-1)) runs."
        break
    fi

    log "INFO" "Tasks remaining: $REMAINING"

    RUN_START=$(date +%s)
    RUN_LOG="$LOG_DIR/session-${run}-$(date +%Y%m%d_%H%M%S).log"

    # Create prompt for this session
    PROMPT_FILE=$(mktemp)
    cat > "$PROMPT_FILE" << 'PROMPT_EOF'
Please follow the workflow in CLAUDE.md:
1. Run init.sh to set up the environment
2. Read feature_list.json and select the next task with passes: false
3. Implement the task following all steps
4. Test thoroughly (lint, build, browser testing for UI changes)
5. Update claude-progress.txt with your work
6. Commit all changes including feature_list.json update in a single commit

Start by reading feature_list.json to find your next task.
Complete only ONE task in this session, then stop.
If you encounter an unresolvable issue, follow the Blocking Protocol in CLAUDE.md.
PROMPT_EOF

    log "INFO" "Starting Claude Code session..."

    # Run Claude Code with skip-permissions
    if claude -p \
        --dangerously-skip-permissions \
        --allowed-tools "Bash Edit Read Write Glob Grep mcp__playwright__*" \
        < "$PROMPT_FILE" 2>&1 | tee "$RUN_LOG"; then
        RUN_END=$(date +%s)
        log "SUCCESS" "Run $run completed in $((RUN_END - RUN_START))s"
    else
        RUN_END=$(date +%s)
        log "WARNING" "Run $run exited with code $? after $((RUN_END - RUN_START))s"
    fi

    rm -f "$PROMPT_FILE"

    # Check progress
    REMAINING_AFTER=$(count_remaining)
    COMPLETED=$((REMAINING - REMAINING_AFTER))

    if [ "$COMPLETED" -gt 0 ]; then
        log "SUCCESS" "Tasks completed this run: $COMPLETED"
    else
        log "WARNING" "No tasks completed this run (may be blocked)"
    fi

    log "INFO" "Tasks remaining: $REMAINING_AFTER"

    # Delay between runs
    if [ $run -lt $TOTAL_RUNS ] && [ "$REMAINING_AFTER" -gt 0 ]; then
        log "INFO" "Waiting 3s before next run..."
        sleep 3
    fi
done

# Summary
echo ""
echo "========================================"
log "SUCCESS" "Automation complete!"
echo "========================================"

FINAL_REMAINING=$(count_remaining)
TOTAL_COMPLETED=$((INITIAL_REMAINING - FINAL_REMAINING))

log "INFO" "Summary:"
log "INFO" "  Total runs: $TOTAL_RUNS"
log "INFO" "  Tasks completed: $TOTAL_COMPLETED"
log "INFO" "  Tasks remaining: $FINAL_REMAINING"
log "INFO" "  Full log: $LOG_FILE"

if [ "$FINAL_REMAINING" -eq 0 ]; then
    log "SUCCESS" "🎉 All tasks have been completed!"
else
    log "WARNING" "Some tasks remain. Run again or check for blocking issues."
fi
