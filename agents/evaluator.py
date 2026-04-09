"""
Evaluator Agent
===============

Grades the Generator's output using Playwright MCP to interact with
the live application, then scores against multi-dimensional criteria.

Key insight from article:
- Separating evaluation from generation is a "strong lever"
- Agents reliably skew positive when grading their own work
- Tuning a standalone evaluator to be skeptical is more tractable
  than making a generator critical of its own work

Key patterns from article:
- Navigate the live page (not static screenshots)
- Grade each criterion independently with hard thresholds
- Write specific, actionable bug reports
- Any dimension below threshold → FAIL
- Sprint contracts define what "done" looks like before coding
"""

import json
import yaml
import logging
from pathlib import Path
from typing import Optional

from anthropic import Anthropic

logger = logging.getLogger("evaluator")

PROMPTS_DIR = Path(__file__).parent.parent / "prompts"


def load_prompt(name: str) -> str:
    path = PROMPTS_DIR / f"{name}.md"
    return path.read_text(encoding="utf-8")


class EvaluatorAgent:
    def __init__(self, config: dict):
        self.config = config
        self.model = config["model"]["evaluator"]
        self.max_tokens = config["model"]["max_tokens"]
        self.criteria = self._load_criteria()
        self.pass_policy = config.get("evaluator", {}).get(
            "pass_policy", "all_above_threshold"
        )
        self.client = Anthropic()

    def _load_criteria(self) -> dict:
        criteria_path = self.config.get("evaluator", {}).get(
            "criteria_file", "./criteria/fullstack.yaml"
        )
        try:
            with open(criteria_path, "r", encoding="utf-8") as f:
                return yaml.safe_load(f)
        except FileNotFoundError:
            logger.warning(f"Criteria file not found: {criteria_path}")
            return {"dimensions": {}}

    async def review_contract(self, contract: dict, spec: str) -> dict:
        """
        Review and refine the Generator's proposed sprint contract.
        Ensure the contract covers testable behaviors, not just vague goals.

        From article: "Generator proposed what it would build and how success
        would be verified, and the evaluator reviewed that proposal to make
        sure the generator was building the right thing."
        """
        logger.info("Reviewing sprint contract...")

        # TODO: Call Claude API to review contract against spec and criteria
        # For now, pass through
        contract["evaluator_reviewed"] = True
        return contract

    async def evaluate(
        self,
        app_url: str,
        spec: str,
        contract: dict,
        project_dir: Optional[Path] = None,
    ) -> dict:
        """
        Evaluate the running application against spec and criteria.

        Full implementation:
        1. Launch Playwright browser
        2. Navigate the app like a real user
        3. Test each contract criterion
        4. Screenshot at each step
        5. Score each dimension 1-10
        6. Generate specific bug reports
        7. Return PASS/FAIL + feedback
        """
        logger.info(f"Evaluating app at {app_url}")

        system_prompt = load_prompt("evaluator_system")
        criteria_text = yaml.dump(self.criteria, default_flow_style=False)

        # ─────────────────────────────────────────────────────────────
        # Full implementation:
        #
        # from playwright.async_api import async_playwright
        #
        # async with async_playwright() as p:
        #     browser = await p.chromium.launch(headless=True)
        #     page = await browser.new_page()
        #     await page.goto(app_url)
        #
        #     # Take initial screenshot
        #     await page.screenshot(path=str(project_dir / "eval_screenshot.png"))
        #
        #     # Feed screenshot + spec + contract to Claude for grading
        #     response = self.client.messages.create(
        #         model=self.model,
        #         max_tokens=self.max_tokens,
        #         system=system_prompt,
        #         messages=[{
        #             "role": "user",
        #             "content": [
        #                 {"type": "image", "source": {...}},  # screenshot
        #                 {"type": "text", "text": f"Spec:\n{spec}\n\nContract:\n{json.dumps(contract)}\n\nCriteria:\n{criteria_text}"}
        #             ]
        #         }],
        #     )
        #     # Parse structured evaluation from response
        #     await browser.close()
        # ─────────────────────────────────────────────────────────────

        # Placeholder evaluation
        logger.info("[PLACEHOLDER] Evaluator would use Playwright here.")

        scores = {}
        for dim_name, dim_config in self.criteria.get("dimensions", {}).items():
            scores[dim_name] = {
                "score": 0,
                "threshold": dim_config.get("threshold", 5),
                "weight": dim_config.get("weight", 0.2),
                "feedback": "Not yet evaluated (placeholder)",
            }

        passed = self._check_pass(scores)

        return {
            "passed": passed,
            "scores": scores,
            "summary": "Placeholder evaluation — activate Playwright for real grading.",
            "feedback": "Activate the Evaluator by installing Playwright and uncommenting the evaluation code.",
            "bugs": [],
        }

    def _check_pass(self, scores: dict) -> bool:
        """Check if all dimensions meet their thresholds."""
        if self.pass_policy == "all_above_threshold":
            return all(
                s["score"] >= s["threshold"]
                for s in scores.values()
            )
        return False
