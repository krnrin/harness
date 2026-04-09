"""
Claude Code SDK Client Factory
==============================

Adapted from anthropics/claude-quickstarts/autonomous-coding/client.py

Creates a configured ClaudeSDKClient with:
- Security sandbox (OS-level bash isolation)
- Filesystem restrictions (project dir only)
- Bash command allowlist (security hooks)
- Playwright MCP for browser automation

Changes from reference:
- Playwright MCP instead of Puppeteer MCP
- Windows-compatible paths
"""

import json
import os
from pathlib import Path

# NOTE: Uncomment when claude-code-sdk is installed
# from claude_code_sdk import ClaudeCodeOptions, ClaudeSDKClient
# from claude_code_sdk.types import HookMatcher
# from security import bash_security_hook


# Playwright MCP tools for browser automation
PLAYWRIGHT_TOOLS = [
    "mcp__playwright__navigate",
    "mcp__playwright__screenshot",
    "mcp__playwright__click",
    "mcp__playwright__fill",
    "mcp__playwright__select",
    "mcp__playwright__hover",
    "mcp__playwright__evaluate",
]

# Built-in Claude Code tools
BUILTIN_TOOLS = [
    "Read",
    "Write",
    "Edit",
    "Glob",
    "Grep",
    "Bash",
]


def create_client(project_dir: Path, model: str):
    """
    Create a Claude Code SDK client with security layers.

    Security model (defense in depth, from reference):
    1. Sandbox — OS-level bash isolation
    2. Permissions — file ops restricted to project_dir
    3. Security hooks — bash commands validated against allowlist
    """
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        raise ValueError("ANTHROPIC_API_KEY not set.")

    security_settings = {
        "sandbox": {"enabled": True, "autoAllowBashIfSandboxed": True},
        "permissions": {
            "defaultMode": "acceptEdits",
            "allow": [
                "Read(./**)",
                "Write(./**)",
                "Edit(./**)",
                "Glob(./**)",
                "Grep(./**)",
                "Bash(*)",
                *PLAYWRIGHT_TOOLS,
            ],
        },
    }

    project_dir.mkdir(parents=True, exist_ok=True)
    settings_file = project_dir / ".claude_settings.json"
    settings_file.write_text(json.dumps(security_settings, indent=2))

    print(f"Security settings: {settings_file}")
    print(f"  Sandbox: enabled")
    print(f"  Filesystem: {project_dir.resolve()}")
    print(f"  Bash: allowlist (see security.py)")
    print(f"  MCP: Playwright")

    # NOTE: Uncomment when claude-code-sdk is installed
    # return ClaudeSDKClient(
    #     options=ClaudeCodeOptions(
    #         model=model,
    #         system_prompt="You are an expert full-stack developer.",
    #         allowed_tools=[*BUILTIN_TOOLS, *PLAYWRIGHT_TOOLS],
    #         mcp_servers={
    #             "playwright": {
    #                 "command": "npx",
    #                 "args": ["@anthropic-ai/playwright-mcp-server"]
    #             }
    #         },
    #         hooks={
    #             "PreToolUse": [
    #                 HookMatcher(matcher="Bash", hooks=[bash_security_hook]),
    #             ],
    #         },
    #         max_turns=1000,
    #         cwd=str(project_dir.resolve()),
    #         settings=str(settings_file.resolve()),
    #     )
    # )

    raise NotImplementedError(
        "Install claude-code-sdk and uncomment the client creation code above.\n"
        "  npm install -g @anthropic-ai/claude-code\n"
        "  pip install claude-code-sdk"
    )
