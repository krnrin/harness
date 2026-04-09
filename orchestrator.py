"""
Harness Orchestrator
====================

Three-agent loop: Planner → [Generator ↔ Evaluator] → Deliverable

Evolution from reference (anthropics/claude-quickstarts/autonomous-coding):
- Reference: Initializer creates feature_list.json → Coding agent iterates
- This: Planner creates spec + feature_list → Generator builds → Evaluator grades

Key patterns carried over from reference:
- Context resets between sessions (fresh client each round)
- feature_list.json as source of truth for progress
- Git commits for persistence
- Security hooks for bash commands
- Progress tracking via passing/total test count

Key patterns added from article:
- Planner agent (short prompt → full spec)
- Evaluator agent (separate from Generator, Playwright MCP)
- Sprint contracts (Generator ↔ Evaluator negotiate before coding)
- Multi-dimensional grading with thresholds
"""

import json
import time
import yaml
import logging
from pathlib import Path
from datetime import datetime
from typing import Optional

from agents.planner import PlannerAgent
from agents.generator import GeneratorAgent
from agents.evaluator import EvaluatorAgent
from progress import print_progress_summary

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    handlers=[logging.StreamHandler()],
)
logger = logging.getLogger("orchestrator")


def load_config(path: str = "config.yaml") -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def ensure_dirs(config: dict):
    for d in [
        config["orchestrator"]["artifact_dir"],
        config["orchestrator"]["log_dir"],
        "artifacts/spec",
        "artifacts/contracts",
        "artifacts/evaluations",
    ]:
        Path(d).mkdir(parents=True, exist_ok=True)


def save_artifact(category: str, name: str, data):
    path = Path(f"artifacts/{category}/{name}")
    path.parent.mkdir(parents=True, exist_ok=True)
    if isinstance(data, (dict, list)):
        path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
    else:
        path.write_text(str(data), encoding="utf-8")
    logger.info(f"Artifact saved: {path}")


def sanitize_dirname(prompt: str) -> str:
    """Create a safe directory name from user prompt."""
    safe = "".join(c if c.isalnum() or c in " -_" else "" for c in prompt)
    return safe.strip().replace(" ", "_")[:50]


async def run_harness(
    user_prompt: str,
    project_dir: Optional[Path] = None,
    max_rounds: Optional[int] = None,
    model_override: Optional[str] = None,
    skip_planner: bool = False,
):
    """
    Main harness entry point.

    Phase 1: Planner expands prompt into spec + feature_list.json
    Phase 2: Generator builds code in sprints
    Phase 3: Evaluator grades via Playwright + criteria
    Phase 2-3 loop until PASS or max_rounds.
    """
    config = load_config()
    ensure_dirs(config)

    # Apply overrides
    if model_override:
        for key in config["model"]:
            config["model"][key] = model_override
    if max_rounds:
        config["orchestrator"]["max_rounds"] = max_rounds

    # Determine project directory
    if project_dir is None:
        project_dir = Path(config["orchestrator"]["output_dir"]) / sanitize_dirname(user_prompt)
    project_dir.mkdir(parents=True, exist_ok=True)

    max_r = config["orchestrator"]["max_rounds"]
    delay = config["orchestrator"]["auto_continue_delay_sec"]
    run_id = datetime.now().strftime("%Y%m%d_%H%M%S")

    run_log = {
        "run_id": run_id,
        "user_prompt": user_prompt,
        "project_dir": str(project_dir),
        "start_time": datetime.now().isoformat(),
        "rounds": [],
    }

    logger.info(f"=== Harness Run {run_id} ===")
    logger.info(f"Prompt: {user_prompt}")
    logger.info(f"Project dir: {project_dir}")
    logger.info(f"Max rounds: {max_r}")

    # ── Phase 1: Planning ──────────────────────────────────────────
    if not skip_planner:
        logger.info("\n" + "=" * 60)
        logger.info("  PHASE 1: PLANNER")
        logger.info("=" * 60)

        planner = PlannerAgent(config)
        spec = await planner.generate_spec(user_prompt)
        save_artifact("spec", f"{run_id}_spec.md", spec)

        # Write spec and feature_list into project dir (like reference copies app_spec.txt)
        (project_dir / "app_spec.md").write_text(spec, encoding="utf-8")
        logger.info("Spec written to project dir.")
    else:
        logger.info("Skipping Planner (--skip-planner). Reading existing spec...")
        spec_path = project_dir / "app_spec.md"
        if spec_path.exists():
            spec = spec_path.read_text(encoding="utf-8")
        else:
            raise FileNotFoundError(f"No spec found at {spec_path}. Run without --skip-planner first.")

    # ── Phase 2-3: Build-Evaluate Loop ─────────────────────────────
    generator = GeneratorAgent(config, project_dir)
    evaluator = EvaluatorAgent(config)
    last_feedback = None

    for round_num in range(1, max_r + 1):
        round_start = time.time()
        logger.info(f"\n{'=' * 60}")
        logger.info(f"  ROUND {round_num}/{max_r}")
        logger.info(f"{'=' * 60}")

        # ── Sprint Contract Negotiation ────────────────────────────
        # (Article pattern: Generator proposes, Evaluator reviews)
        logger.info("Negotiating sprint contract...")
        contract = await generator.propose_contract(spec, round_num, last_feedback)
        contract = await evaluator.review_contract(contract, spec)
        save_artifact("contracts", f"{run_id}_r{round_num}_contract.json", contract)

        # ── Generator: Build ───────────────────────────────────────
        # (Reference pattern: fresh client per session = context reset)
        logger.info("Generator building...")
        is_first = round_num == 1 and not (project_dir / "feature_list.json").exists()
        await generator.build(spec, contract, feedback=last_feedback, is_first_session=is_first)

        print_progress_summary(project_dir)

        # ── Evaluator: Grade ───────────────────────────────────────
        logger.info("Evaluator grading...")
        frontend_port = config["generator"]["dev_server"]["frontend_port"]
        eval_result = await evaluator.evaluate(
            app_url=f"http://localhost:{frontend_port}",
            spec=spec,
            contract=contract,
            project_dir=project_dir,
        )
        save_artifact("evaluations", f"{run_id}_r{round_num}_eval.json", eval_result)

        round_time = time.time() - round_start
        run_log["rounds"].append({
            "round": round_num,
            "duration_sec": round_time,
            "passed": eval_result.get("passed", False),
            "scores": eval_result.get("scores", {}),
            "summary": eval_result.get("summary", ""),
        })

        if eval_result.get("passed"):
            logger.info(f"✅ Round {round_num} PASSED!")
            generator.git_commit(f"Round {round_num}: PASSED - all criteria met")
            break
        else:
            logger.warning(f"❌ Round {round_num} FAILED: {eval_result.get('summary', '')}")
            generator.git_commit(f"Round {round_num}: FAIL - {eval_result.get('summary', '')[:80]}")
            last_feedback = eval_result.get("feedback", "")

            if round_num < max_r:
                logger.info(f"Continuing in {delay}s...")
                time.sleep(delay)
    else:
        logger.warning(f"⚠️ Max rounds ({max_r}) reached.")

    # ── Finalize ───────────────────────────────────────────────────
    run_log["end_time"] = datetime.now().isoformat()
    run_log["final_status"] = "PASSED" if any(r["passed"] for r in run_log["rounds"]) else "FAILED"
    save_artifact("evaluations", f"{run_id}_run_log.json", run_log)

    logger.info(f"\n{'=' * 60}")
    logger.info(f"  RUN COMPLETE: {run_log['final_status']}")
    logger.info(f"{'=' * 60}")
    logger.info(f"Project: {project_dir.resolve()}")
    print_progress_summary(project_dir)
