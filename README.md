# Harness — Multi-Agent Autonomous Coding System

A three-agent harness for long-running autonomous application development,
inspired by [Anthropic's Harness Design](https://www.anthropic.com/engineering/harness-design-long-running-apps)
and built on top of [claude-quickstarts/autonomous-coding](https://github.com/anthropics/claude-quickstarts/tree/main/autonomous-coding)
with practical learnings from [SamuelQZQ/auto-coding-agent-demo](https://github.com/SamuelQZQ/auto-coding-agent-demo).

## Architecture

```
User Prompt (1-4 sentences)
        │
        ▼
┌─────────────┐
│   Planner   │  Expands prompt → full Product Spec
│ (Claude API)│  Outputs: spec.md, feature_list.json
└──────┬──────┘
       │
       ▼
┌─────────────┐     ┌──────────────┐
│  Generator  │◄───►│  Evaluator   │  Sprint contract negotiation
│(Claude Code)│     │(Playwright)  │  Build → QA → Feedback loop
└──────┬──────┘     └──────┬───────┘
       │                   │
       ▼                   ▼
   Code + Git          Scores + Bug Report
       │                   │
       └───────┬───────────┘
               ▼
         PASS → Deliver
         FAIL → Next Round
```

### What evolved from each reference

| Source | What we took |
|---|---|
| Anthropic article | Three-agent architecture, sprint contracts, 5-dimension grading, evaluator separation |
| anthropics/claude-quickstarts | ClaudeSDKClient, security hooks, feature_list.json tracking, context reset pattern |
| SamuelQZQ/auto-coding-agent-demo | CLAUDE.md convention, blocking protocol, Bash automation loop, three running modes |

## Prerequisites

```bash
# Claude Code CLI (latest)
npm install -g @anthropic-ai/claude-code

# Python dependencies
pip install -r requirements.txt

# Playwright (for Evaluator)
npx playwright install chromium
```

## Environment Variables

```bash
set ANTHROPIC_API_KEY=your-api-key-here
```

## Three Running Modes

### Mode 1: Full Orchestrator (Python — most capable)

Three-agent loop with Planner, Generator, and Evaluator.
Best for complex projects where you want autonomous quality control.

```bash
# Build a complete app from a short prompt
python run.py "Build a project management dashboard with kanban boards"

# Limit rounds for testing
python run.py "Build a todo app" --max-rounds 2

# Use a specific model
python run.py "Build a blog" --model claude-sonnet-4-20250514

# Skip planner (reuse existing spec)
python run.py "Build a blog" --skip-planner --project-dir ./output/blog
```

### Mode 2: Semi-Automatic (Claude Code — main workhorse)

Direct Claude Code with `CLAUDE.md` as the system prompt.
Best for iterating quickly with human oversight.

```bash
cd output/project

# Interactive mode (safest — you confirm each action)
claude

# Skip permissions (faster — no confirmations)
claude -p --dangerously-skip-permissions
```

Claude Code automatically reads `CLAUDE.md` in the project root,
which contains the full workflow, testing requirements, and blocking protocol.

### Mode 3: Bash Automation Loop (unattended — most dangerous)

Runs Claude Code N times in a loop. Each session picks the next task.
Best for overnight runs when you trust the setup.

```bash
# Run 10 sessions on the project
./run-automation.sh 10 ./output/project

# Run 5 sessions in current dir
cd output/project
../../run-automation.sh 5
```

**⚠️ Warning**: Full-auto mode can waste resources if tasks are blocked.
Always review `claude-progress.txt` and git log after unattended runs.

### When to use which mode

| Scenario | Mode | Why |
|---|---|---|
| New project from scratch | Mode 1 (Python) | Planner generates spec, Evaluator ensures quality |
| Iterating on existing project | Mode 2 (Claude Code) | Fast, human-in-the-loop |
| Grinding through many tasks | Mode 3 (Bash loop) | Unattended, picks up tasks sequentially |
| Debugging a specific issue | Mode 2 (interactive) | Full control, see each step |

## Project Structure

```
harness/
├── run.py                    # Mode 1: Python orchestrator entry point
├── run-automation.sh          # Mode 3: Bash automation loop
├── config.yaml               # Model, thresholds, cost limits
├── orchestrator.py            # Three-agent orchestration loop
├── agents/
│   ├── planner.py             # Prompt → Spec (Claude API)
│   ├── generator.py           # Spec → Code (Claude Code SDK)
│   ├── evaluator.py           # Code → Scores (Playwright MCP)
│   └── client.py              # Claude Code SDK client factory
├── security.py                # Bash command allowlist (from reference)
├── progress.py                # feature_list.json tracking
├── templates/
│   └── CLAUDE.md              # Template copied into project dir
├── prompts/
│   ├── planner_system.md      # Planner system prompt
│   ├── generator_system.md    # Generator system prompt
│   ├── evaluator_system.md    # Evaluator system prompt
│   ├── coding_prompt.md       # Per-session coding prompt
│   └── initializer_prompt.md  # First-session setup prompt
├── criteria/
│   └── fullstack.yaml         # 5-dimension grading criteria
├── artifacts/                 # Specs, contracts, evaluations
├── output/                    # Generated project code
└── logs/                      # Structured run logs
```

## Grading Criteria (Evaluator)

| Dimension | Weight | Threshold | What it measures |
|-----------|--------|-----------|------------------|
| Functionality | 30% | ≥7/10 | Features work end-to-end |
| Design Quality | 25% | ≥6/10 | Visual coherence, mood, identity |
| Code Quality | 20% | ≥6/10 | Structure, error handling, types |
| Product Depth | 15% | ≥5/10 | UX flows, edge cases, guidance |
| Originality | 10% | ≥5/10 | Custom decisions vs template defaults |

Any dimension below threshold → FAIL → feedback to Generator.

## Blocking Protocol

When a task cannot be completed (missing API keys, external service down, etc.),
the agent follows a strict protocol:

1. **DO NOT** commit or mark the task as passing
2. **DO** write the blocking reason to `claude-progress.txt`
3. **DO** output a clear `🚫 BLOCKED` message explaining what human needs to do
4. **DO** stop and wait for human intervention

This prevents wasted runs in automation mode and keeps the codebase honest.

## feature_list.json Format

```json
[
  {
    "id": 1,
    "title": "User authentication — login page",
    "category": "functional",
    "description": "Implement login page with email/password",
    "steps": [
      "Create login page component",
      "Implement form validation",
      "Connect to auth API",
      "Redirect on success"
    ],
    "passes": false
  }
]
```

Every task has a sequential `id` and human-readable `title` for easy tracking.
Tasks can only be marked as passing — never removed, edited, or reordered.

## License

MIT
