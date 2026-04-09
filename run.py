#!/usr/bin/env python3
"""
Harness — Multi-Agent Autonomous Coding System
===============================================

Main entry point. Accepts a short prompt and orchestrates
Planner → Generator → Evaluator to build a complete application.

Usage:
    python run.py "Build a kanban board with drag-and-drop"
    python run.py "Build a DAW in the browser" --max-rounds 5
    python run.py "Build a retro game maker" --model claude-opus-4-20250514
"""

import argparse
import asyncio
import os
import sys
from pathlib import Path

from orchestrator import run_harness

DEFAULT_MODEL = "claude-sonnet-4-20250514"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Harness: Multi-agent autonomous coding system",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "prompt",
        type=str,
        help="Short description of the app to build (1-4 sentences)",
    )
    parser.add_argument(
        "--project-dir",
        type=Path,
        default=None,
        help="Output directory (default: ./output/<sanitized_prompt>)",
    )
    parser.add_argument(
        "--max-rounds",
        type=int,
        default=None,
        help="Override max Generator↔Evaluator rounds (default from config.yaml)",
    )
    parser.add_argument(
        "--model",
        type=str,
        default=None,
        help=f"Override model for all agents (default: {DEFAULT_MODEL})",
    )
    parser.add_argument(
        "--skip-planner",
        action="store_true",
        help="Skip Planner and use an existing spec in the project dir",
    )
    return parser.parse_args()


def main():
    args = parse_args()

    if not os.environ.get("ANTHROPIC_API_KEY"):
        print("Error: ANTHROPIC_API_KEY environment variable not set")
        print("\nSet it with:")
        print('  set ANTHROPIC_API_KEY=your-api-key-here')
        sys.exit(1)

    try:
        asyncio.run(
            run_harness(
                user_prompt=args.prompt,
                project_dir=args.project_dir,
                max_rounds=args.max_rounds,
                model_override=args.model,
                skip_planner=args.skip_planner,
            )
        )
    except KeyboardInterrupt:
        print("\n\nInterrupted. To resume, run with --skip-planner on the same --project-dir.")
    except Exception as e:
        print(f"\nFatal error: {e}")
        raise


if __name__ == "__main__":
    main()
