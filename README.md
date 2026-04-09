# Harness — Multi-Agent Autonomous Coding System

A three-agent harness for long-running autonomous application development,
inspired by [Anthropic's Harness Design](https://www.anthropic.com/engineering/harness-design-long-running-apps)
and built on top of [claude-quickstarts/autonomous-coding](https://github.com/anthropics/claude-quickstarts/tree/main/autonomous-coding).

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

### What evolved from the reference implementation

| Reference (autonomous-coding) | This Harness |
|---|----- |
| 2 agents: Initializer + Coding | 3 agents: Planner + Generator + Evaluator |
| Manual app_spec.txt | Planner auto-generates spec from short prompt |
| Self-evaluation only | Separate Evaluator with Playwright MCP |
| Puppeteer MCP | Playwright MCP (article recommendation) |
| feature_list.json (200 tests) | feature_list.json + sprint contracts + grading criteria |
| No grading dimensions | 5-dimension scoring with thresholds |

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

## Quick Start

```bash
# Build a complete app from a short prompt
python run.py "Build a project management dashboard with kanban boards and analytics"

# Limit rounds for testing
python run.py "Build a todo app" --max-rounds 2

# Use a specific model
python run.py "Build a blog" --model claude-sonnet-4-20250514
```

## Project Structure

```
harness/
├── run.py                    # Main entry point
├── config.yaml               # Model, thresholds, cost limits
├── orchestrator.py            # Three-agent orchestration loop
├── agents/
│   ├── planner.py             # Prompt → Spec (Claude API)
│   ├── generator.py           # Spec → Code (Claude Code SDK)
│   ├── evaluator.py           # Code → Scores (Playwright MCP)
│   └── client.py              # Claude Code SDK client factory
├── security.py                # Bash command allowlist (from reference)
├── progress.py                # feature_list.json tracking
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

## Grading Criteria

| Dimension | Weight | Threshold | What it measures |
|-----------|--------|-----------|------------------|
| Functionality | 30% | ≥7/10 | Features work end-to-end |
| Design Quality | 25% | ≥6/10 | Visual coherence, mood, identity |
| Code Quality | 20% | ≥6/10 | Structure, error handling, types |
| Product Depth | 15% | ≥5/10 | UX flows, edge cases, guidance |
| Originality | 10% | ≥5/10 | Custom decisions vs template defaults |

Any dimension below threshold → FAIL → feedback to Generator.

## License

MIT
