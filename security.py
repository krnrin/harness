"""
Security Hooks for Autonomous Coding Agent
==========================================

Adapted from anthropics/claude-quickstarts/autonomous-coding/security.py

Pre-tool-use hooks that validate bash commands using an allowlist.
Only explicitly permitted commands can run.
"""

import os
import re
import shlex


# Allowed commands — minimal set for development tasks
ALLOWED_COMMANDS = {
    # File inspection
    "ls", "cat", "head", "tail", "wc", "grep", "find",
    # File operations
    "cp", "mkdir", "chmod",
    # Directory
    "pwd", "cd",
    # Node.js development
    "npm", "npx", "node",
    # Python development
    "python", "pip", "uvicorn",
    # Version control
    "git",
    # Process management
    "ps", "lsof", "sleep", "pkill",
    # Windows compatibility
    "where", "dir",
    # Script execution
    "init.sh",
}

COMMANDS_NEEDING_EXTRA_VALIDATION = {"pkill", "chmod", "init.sh"}


def extract_commands(command_string: str) -> list[str]:
    """Extract command names from a shell command string."""
    commands = []
    segments = re.split(r'(?<!["\'])\s*;\s*(?!["\'])', command_string)

    for segment in segments:
        segment = segment.strip()
        if not segment:
            continue
        try:
            tokens = shlex.split(segment)
        except ValueError:
            return []
        if not tokens:
            continue

        expect_command = True
        for token in tokens:
            if token in ("|", "||", "&&", "&"):
                expect_command = True
                continue
            if token.startswith("-"):
                continue
            if "=" in token and not token.startswith("="):
                continue
            if expect_command:
                cmd = os.path.basename(token)
                commands.append(cmd)
                expect_command = False

    return commands


def validate_pkill_command(command_string: str) -> tuple[bool, str]:
    """Only allow killing dev-related processes."""
    allowed_processes = {"node", "npm", "npx", "vite", "next", "uvicorn", "python"}
    try:
        tokens = shlex.split(command_string)
    except ValueError:
        return False, "Could not parse pkill command"

    args = [t for t in tokens[1:] if not t.startswith("-")]
    if not args:
        return False, "pkill requires a process name"

    target = args[-1].split()[0] if " " in args[-1] else args[-1]
    if target in allowed_processes:
        return True, ""
    return False, f"pkill only allowed for: {allowed_processes}"


async def bash_security_hook(input_data, tool_use_id=None, context=None):
    """
    Pre-tool-use hook that validates bash commands.
    Returns {} to allow, or {"decision": "block", "reason": "..."} to block.
    """
    if input_data.get("tool_name") != "Bash":
        return {}

    command = input_data.get("tool_input", {}).get("command", "")
    if not command:
        return {}

    commands = extract_commands(command)
    if not commands:
        return {
            "decision": "block",
            "reason": f"Could not parse command: {command}",
        }

    for cmd in commands:
        if cmd not in ALLOWED_COMMANDS:
            return {
                "decision": "block",
                "reason": f"Command '{cmd}' not in allowlist",
            }
        if cmd == "pkill":
            allowed, reason = validate_pkill_command(command)
            if not allowed:
                return {"decision": "block", "reason": reason}

    return {}
