"""
Generator Agent
===============

Builds the application using Claude Code SDK.
Direct evolution of anthropics/claude-quickstarts/autonomous-coding.

Key patterns from reference:
- Uses ClaudeSDKClient with security hooks
- Fresh client per session (context reset)
- feature_list.json as progress tracker
- Git commits for persistence
- Puppeteer/Playwright MCP for browser testing during build

Key patterns from article:
- Sprint contracts with Evaluator before coding
- Strategic decision after feedback: REFINE or PIVOT
- Self-evaluation before QA handoff
"""

import json
import subprocess
import logging
from pathlib import Path
from typing import Optional

logger = logging.getLogger("generator")


class GeneratorAgent:
    def __init__(self, config: dict, project_dir: Path):
        self.config = config
        self.model = config["model"]["generator"]
        self.project_dir = project_dir
        self.git_enabled = config.get("generator", {}).get("git_enabled", True)
        self.max_turns = config.get("generator", {}).get("max_turns", 1000)
        self.project_dir.mkdir(parents=True, exist_ok=True)

    async def propose_contract(self, spec: str, round_num: int, feedback: Optional[str]) -> dict:
        """
        Propose a sprint contract defining what will be built and how
        success is verified. Evaluator will review this before coding starts.

        In the full implementation, this calls Claude API to generate
        the contract based on spec + feedback.
        """
        logger.info(f"Proposing sprint contract for round {round_num}")

        # Determine strategy based on feedback
        if feedback and round_num > 1:
            strategy = "refine"  # or "pivot" based on score trends
        else:
            strategy = "initial"

        # TODO: Replace with Claude API call that reads spec + feature_list.json
        # and proposes specific features to implement this round
        contract = {
            "round": round_num,
            "strategy": strategy,
            "focus_features": [],  # Will be populated by Claude
            "acceptance_criteria": [],  # Will be populated by Claude
            "feedback_from_previous": feedback,
        }
        return contract

    async def build(self, spec: str, contract: dict, feedback: Optional[str] = None,
                    is_first_session: bool = False):
        """
        Build the application using Claude Code SDK.

        Mirrors the reference implementation's agent session pattern:
        - Create fresh client (context reset)
        - Choose prompt (initializer vs coding)
        - Run agent session
        - Track progress via feature_list.json
        """
        logger.info(f"Building... (first_session={is_first_session})")

        # ─────────────────────────────────────────────────────────────
        # Full implementation:
        #
        # from agents.client import create_client
        # from prompts import load_prompt
        #
        # client = create_client(self.project_dir, self.model)
        #
        # if is_first_session:
        #     prompt = load_prompt("initializer_prompt")
        # else:
        #     prompt = load_prompt("coding_prompt")
        #
        # # Inject sprint contract and feedback into prompt
        # prompt += f"\n\n## Sprint Contract\n{json.dumps(contract, indent=2)}"
        # if feedback:
        #     prompt += f"\n\n## QA Feedback\n{feedback}"
        #     prompt += "\n\nStrategic decision: REFINE if trending well, PIVOT if not."
        #
        # async with client:
        #     status, response = await run_agent_session(client, prompt, self.project_dir)
        # ─────────────────────────────────────────────────────────────

        logger.info("[PLACEHOLDER] Generator build session would run here.")
        logger.info("To activate: install claude-code-sdk and uncomment client code.")

    def git_commit(self, message: str):
        """Commit current state to git."""
        if not self.git_enabled:
            return
        try:
            git_dir = self.project_dir / ".git"
            if not git_dir.exists():
                subprocess.run(["git", "init"], cwd=self.project_dir, capture_output=True)

            subprocess.run(["git", "add", "."], cwd=self.project_dir, capture_output=True)
            subprocess.run(
                ["git", "commit", "-m", message, "--allow-empty"],
                cwd=self.project_dir, capture_output=True,
            )
            logger.info(f"Git commit: {message}")
        except Exception as e:
            logger.warning(f"Git commit failed: {e}")
