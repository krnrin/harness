"""
Planner Agent
=============

Expands a 1-4 sentence user prompt into:
1. A full product spec (app_spec.md)
2. A feature list with test cases (feature_list.json)

Uses raw Anthropic API (not Claude Code SDK) since Planner
only needs to generate text, not execute code.

Key design decisions (from Anthropic article):
- Be ambitious about scope
- Focus on product context, NOT granular implementation details
  (errors in detailed specs cascade downstream)
- Optionally weave AI features into specs
- Define a visual design language
"""

import json
import logging
from pathlib import Path

from anthropic import Anthropic

logger = logging.getLogger("planner")

PROMPTS_DIR = Path(__file__).parent.parent / "prompts"


def load_prompt(name: str) -> str:
    path = PROMPTS_DIR / f"{name}.md"
    return path.read_text(encoding="utf-8")


class PlannerAgent:
    def __init__(self, config: dict):
        self.config = config
        self.model = config["model"]["planner"]
        self.max_tokens = config["model"]["max_tokens"]
        self.enable_ai = config.get("planner", {}).get("enable_ai_features", True)
        self.ambition = config.get("planner", {}).get("ambition_level", "high")
        self.feature_count = config.get("planner", {}).get("feature_count", 50)
        self.client = Anthropic()

    async def generate_spec(self, user_prompt: str) -> str:
        """
        Generate a full product spec from a brief user prompt.
        Returns the spec as a markdown string.
        """
        logger.info(f"Generating spec for: {user_prompt}")
        logger.info(f"Model: {self.model}, Ambition: {self.ambition}")

        system_prompt = load_prompt("planner_system")

        user_message = self._build_prompt(user_prompt)

        response = self.client.messages.create(
            model=self.model,
            max_tokens=self.max_tokens,
            system=system_prompt,
            messages=[{"role": "user", "content": user_message}],
        )

        spec = response.content[0].text
        logger.info(f"Spec generated ({len(spec)} chars, {response.usage.output_tokens} tokens)")
        return spec

    def _build_prompt(self, user_prompt: str) -> str:
        parts = [
            f"## User Request\n{user_prompt}",
            f"\n## Ambition Level: {self.ambition}",
            f"\n## Target Feature Count: {self.feature_count}",
        ]
        if self.enable_ai:
            parts.append(
                "\n## AI Integration\n"
                "Look for opportunities to weave AI-powered features naturally "
                "into the product spec. These should enhance the user experience, "
                "not feel forced."
            )
        parts.append(
            "\n## Tech Stack\n"
            "- Frontend: React + Vite + TypeScript\n"
            "- Backend: FastAPI (Python)\n"
            "- Database: SQLite\n"
            "- Browser testing: Playwright\n"
        )
        return "\n".join(parts)
