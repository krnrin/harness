"""
Progress Tracking
=================

Adapted from anthropics/claude-quickstarts/autonomous-coding/progress.py

Tracks progress via feature_list.json — the single source of truth
for what needs to be built and what's been verified.
"""

import json
from pathlib import Path


def count_passing_tests(project_dir: Path) -> tuple[int, int]:
    """Count passing and total tests in feature_list.json."""
    tests_file = project_dir / "feature_list.json"
    if not tests_file.exists():
        return 0, 0
    try:
        with open(tests_file, "r", encoding="utf-8") as f:
            tests = json.load(f)
        total = len(tests)
        passing = sum(1 for t in tests if t.get("passes", False))
        return passing, total
    except (json.JSONDecodeError, IOError):
        return 0, 0


def print_progress_summary(project_dir: Path):
    """Print current progress."""
    passing, total = count_passing_tests(project_dir)
    if total > 0:
        pct = (passing / total) * 100
        print(f"\nProgress: {passing}/{total} features passing ({pct:.1f}%)")
    else:
        print("\nProgress: feature_list.json not yet created")
