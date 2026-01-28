"""Claude CLI provider - executes prompts via the claude CLI tool."""

from __future__ import annotations

import asyncio
import json
import subprocess
from pathlib import Path
from typing import Any

from agent_manager.providers.base import LLMProvider, LLMResponse, ProviderConfig


class ClaudeCLIProvider(LLMProvider):
    """Provider that shells out to the claude CLI tool.

    This uses your Claude Code subscription for token accounting.
    """

    def __init__(self, claude_path: str = "claude"):
        """Initialize the provider.

        Args:
            claude_path: Path to the claude executable (default: use PATH)
        """
        self.claude_path = claude_path

    @property
    def name(self) -> str:
        return "claude-cli"

    async def execute(
        self,
        prompt: str,
        config: ProviderConfig,
        log_file: Path | None = None,
        session_id: str | None = None,
    ) -> LLMResponse:
        """Execute a prompt via the claude CLI."""
        # Run in thread pool to not block event loop
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(
            None, self.execute_sync, prompt, config, log_file, session_id
        )

    def execute_sync(
        self,
        prompt: str,
        config: ProviderConfig,
        log_file: Path | None = None,
        session_id: str | None = None,
    ) -> LLMResponse:
        """Execute a prompt synchronously via the claude CLI.

        Args:
            prompt: The prompt to send
            config: Provider configuration
            log_file: Optional log file
            session_id: If provided, continue this session instead of starting new
        """
        # Build command
        cmd = [
            self.claude_path,
            "--print",
            "--output-format", "json",
        ]

        # Continue existing session or start new
        if session_id:
            cmd.extend(["--resume", session_id])

        # Add the prompt
        cmd.append(prompt)

        # Add allowed tools
        for tool in config.allowed_tools:
            cmd.extend(["--allowedTools", tool])

        # Add permission mode if specified
        if config.permission_mode:
            cmd.extend(["--permission-mode", config.permission_mode])

        # Add model if specified
        if config.model:
            cmd.extend(["--model", config.model])

        # Add budget limit
        cmd.extend(["--max-budget-usd", f"{config.max_budget_usd:.2f}"])

        # Add max turns
        cmd.extend(["--max-turns", str(config.max_turns)])

        # Set up environment
        import os

        env = os.environ.copy()
        env["HOME"] = str(Path.home())

        try:
            # Run the command
            result = subprocess.run(
                cmd,
                cwd=str(config.working_directory),
                env=env,
                capture_output=True,
                text=True,
            )

            # Log output if requested
            if log_file:
                log_file.parent.mkdir(parents=True, exist_ok=True)
                with log_file.open("a") as f:
                    f.write(f"Command: {' '.join(cmd)}\n")
                    f.write(f"Exit code: {result.returncode}\n")
                    f.write(f"Stdout:\n{result.stdout}\n")
                    if result.stderr:
                        f.write(f"Stderr:\n{result.stderr}\n")

            if result.returncode != 0:
                return LLMResponse(
                    success=False,
                    result="",
                    error=f"Claude CLI exited with code {result.returncode}: {result.stderr}",
                    raw_output=result.stdout,
                )

            # Parse JSON response
            return self._parse_response(result.stdout)

        except FileNotFoundError:
            return LLMResponse(
                success=False,
                result="",
                error=f"Claude CLI not found at '{self.claude_path}'. Is it installed?",
            )
        except Exception as e:
            return LLMResponse(
                success=False,
                result="",
                error=f"Failed to execute Claude CLI: {e}",
            )

    def _parse_response(self, output: str) -> LLMResponse:
        """Parse the JSON response from claude CLI."""
        try:
            data = json.loads(output)
            return LLMResponse(
                success=True,
                result=data.get("result", ""),
                input_tokens=self._extract_input_tokens(data),
                output_tokens=data.get("usage", {}).get("output_tokens"),
                cost=data.get("total_cost_usd"),
                raw_output=output,
                session_id=data.get("session_id"),
                metadata={
                    "duration_ms": data.get("duration_ms"),
                    "num_turns": data.get("num_turns"),
                },
            )
        except json.JSONDecodeError:
            # If not JSON, return raw output as result
            return LLMResponse(
                success=True,
                result=output.strip(),
                raw_output=output,
            )

    def _extract_input_tokens(self, data: dict[str, Any]) -> int | None:
        """Extract total input tokens from response."""
        usage = data.get("usage", {})
        if not usage:
            return None

        # Sum all input token types
        input_tokens = usage.get("input_tokens", 0)
        cache_creation = usage.get("cache_creation_input_tokens", 0)
        cache_read = usage.get("cache_read_input_tokens", 0)

        return input_tokens + cache_creation + cache_read


# Default provider instance
_default_provider: ClaudeCLIProvider | None = None


def get_claude_cli_provider() -> ClaudeCLIProvider:
    """Get the default Claude CLI provider instance."""
    global _default_provider
    if _default_provider is None:
        _default_provider = ClaudeCLIProvider()
    return _default_provider
