"""Job runner - executes a single job within a workflow."""

from __future__ import annotations

import asyncio
import json
import subprocess
from pathlib import Path

from agent_manager.expressions.evaluator import ExpressionContext, ExpressionEvaluator
from agent_manager.expressions.extractor import OutputExtractor
from agent_manager.models.result import JobResult
from agent_manager.models.workflow import Job, Workflow
from agent_manager.providers.base import LLMProvider, ProviderConfig
from agent_manager.providers.claude_cli import get_claude_cli_provider
from agent_manager.store.agent_store import get_agent_store


def _get_scratch_base() -> Path:
    """Get the base scratch directory."""
    return Path.home() / ".agent-manager" / "scratch"


class JobRunner:
    """Runs a single job within a workflow."""

    def __init__(self, provider: LLMProvider | None = None):
        """Initialize the job runner.

        Args:
            provider: LLM provider to use (defaults to Claude CLI)
        """
        self.provider = provider or get_claude_cli_provider()
        self.agent_store = get_agent_store()
        self.output_extractor = OutputExtractor()
        self.expression_evaluator = ExpressionEvaluator()

    async def run(
        self,
        job_name: str,
        job: Job,
        workflow: Workflow,
        context: ExpressionContext,
        log_directory: Path,
        dry_run: bool = False,
        run_id: str | None = None,
        session_ids: dict[str, str] | None = None,
    ) -> JobResult:
        """Run a single job.

        Args:
            job_name: The name of the job
            job: The job definition
            workflow: The parent workflow
            context: The expression evaluation context
            log_directory: Directory to store job logs
            dry_run: If true, don't actually execute
            run_id: The workflow run ID (for scratch directory)
            session_ids: Map of job names to session IDs (for session continuation)

        Returns:
            The job result with outputs
        """
        result = JobResult(job_name=job_name)
        result.mark_started()

        # Create scratch directory for this job
        if run_id:
            output_dir = _get_scratch_base() / run_id / job_name
            output_dir.mkdir(parents=True, exist_ok=True)
            result.output_dir = str(output_dir)
            context.set_current_job(str(output_dir))
        else:
            context.clear_current_job()

        # Evaluate job-level conditional if present
        if job.if_condition:
            try:
                should_run = self.expression_evaluator.evaluate(job.if_condition, context)
                if not should_run:
                    result.mark_skipped(f"Condition '{job.if_condition}' evaluated to false")
                    return result
            except Exception as e:
                result.mark_failed(f"Failed to evaluate condition: {e}")
                return result

        # Handle goals-based jobs (recommended)
        if job.has_goals:
            return await self._run_goals(
                job_name, job, workflow, context, log_directory, dry_run, result, session_ids
            )

        # Handle single-prompt jobs (agent or inline prompt)
        return await self._run_single_prompt(
            job_name, job, workflow, context, log_directory, dry_run, result, session_ids
        )

    async def _run_single_prompt(
        self,
        job_name: str,
        job: Job,
        workflow: Workflow,
        context: ExpressionContext,
        log_directory: Path,
        dry_run: bool,
        result: JobResult,
        session_ids: dict[str, str] | None = None,
    ) -> JobResult:
        """Run a job with a single prompt (agent or inline prompt)."""
        # Get the prompt and config
        try:
            prompt, config = self._build_prompt_and_config(job_name, job, workflow, context)
        except Exception as e:
            result.mark_failed(str(e))
            return result

        # Dry run - don't execute
        if dry_run:
            result.mark_completed()
            result.claude_output = f"[DRY RUN] Would execute: {prompt[:200]}..."
            return result

        # Execute via provider
        log_directory.mkdir(parents=True, exist_ok=True)
        log_file = log_directory / f"{job_name}.log"

        # Determine session_id for continuation
        session_id = None
        if job.continue_session and session_ids:
            session_id = session_ids.get(job.continue_session)

        response = await self.provider.execute(prompt, config, log_file, session_id)

        if not response.success:
            result.mark_failed(response.error or "Unknown error")
            return result

        # Update stats and session_id
        result.update_stats(
            input_tokens=response.input_tokens,
            output_tokens=response.output_tokens,
            cost=response.cost,
        )
        result.log_file = str(log_file)
        result.session_id = response.session_id

        # Extract outputs - try file first, then regex fallback
        outputs = job.outputs or []
        if outputs:
            extracted = self._extract_outputs(response.result, outputs, result.output_dir)
            result.mark_completed(outputs=extracted, claude_output=response.result)
        else:
            result.mark_completed(claude_output=response.result)

        return result

    async def _run_goals(
        self,
        job_name: str,
        job: Job,
        workflow: Workflow,
        context: ExpressionContext,
        log_directory: Path,
        dry_run: bool,
        result: JobResult,
        session_ids: dict[str, str] | None = None,
    ) -> JobResult:
        """Run a goals-based job with context gathering.

        Goals-based execution:
        1. Run context shell commands BEFORE Claude (zero token cost)
        2. Build a single prompt from context + goals
        3. Make one Claude call
        4. Extract report outputs
        """
        working_dir = Path(workflow.working_directory(job_name)).expanduser()

        # Step 1: Gather context by running shell commands IN PARALLEL
        context_results: dict[str, str] = {}
        if job.context:
            if dry_run:
                context_results = {
                    name: f"[DRY RUN] Would run: {cmd}" for name, cmd in job.context.items()
                }
            else:
                context_results = await self._gather_context_parallel(job.context, working_dir)

        # Step 2: Build prompt from context + goals
        prompt = self._build_goals_prompt(job, context_results, result.output_dir)

        # Add output instructions if report fields are declared
        outputs = job.all_outputs
        if outputs:
            prompt += self._build_output_instructions(outputs, result.output_dir)

        # Build config
        config = ProviderConfig(
            working_directory=working_dir,
            allowed_tools=workflow.allowed_tools(job_name),
            max_turns=workflow.max_turns(job_name),
            max_budget_usd=workflow.max_budget(job_name),
            permission_mode=workflow.permission_mode(job_name),
            model=workflow.model(job_name),
        )

        # Dry run - don't execute
        if dry_run:
            result.mark_completed()
            result.claude_output = f"[DRY RUN] Would execute with context:\n{prompt[:500]}..."
            return result

        # Step 3: Execute via provider (single Claude call)
        log_directory.mkdir(parents=True, exist_ok=True)
        log_file = log_directory / f"{job_name}.log"

        # Determine session_id for continuation
        session_id = None
        if job.continue_session and session_ids:
            session_id = session_ids.get(job.continue_session)

        response = await self.provider.execute(prompt, config, log_file, session_id)

        if not response.success:
            result.mark_failed(response.error or "Unknown error")
            return result

        # Update stats and session_id
        result.update_stats(
            input_tokens=response.input_tokens,
            output_tokens=response.output_tokens,
            cost=response.cost,
        )
        result.log_file = str(log_file)
        result.session_id = response.session_id

        # Step 4: Extract report outputs - try file first, then regex fallback
        if outputs:
            extracted = self._extract_outputs(response.result, outputs, result.output_dir)
            result.mark_completed(outputs=extracted, claude_output=response.result)
        else:
            result.mark_completed(claude_output=response.result)

        return result

    def _build_goals_prompt(
        self, job: Job, context_results: dict[str, str], output_dir: str | None = None
    ) -> str:
        """Build a prompt from goals and gathered context."""
        parts: list[str] = []

        # Add context section if any context was gathered
        if context_results:
            parts.append("## Current Context\n")
            for name, output in context_results.items():
                parts.append(f"### {name}\n```\n{output}\n```\n")

        # Add output directory info if available
        if output_dir:
            parts.append("## Output Directory\n")
            parts.append(f"Your scratch directory for this job is: `{output_dir}`\n")
            parts.append("Use this directory for any files you need to create.\n\n")

        # Add goals section - interpolate ${{ job.output_dir }} in goals
        parts.append("## Goals\n")
        parts.append("Accomplish the following goals:\n")
        for i, goal in enumerate(job.goals or [], 1):
            # Replace ${{ job.output_dir }} with actual value
            interpolated_goal = goal
            if output_dir:
                interpolated_goal = goal.replace("${{ job.output_dir }}", output_dir)
            parts.append(f"{i}. {interpolated_goal}\n")

        parts.append("\nUse your judgment on how best to achieve these goals. ")
        parts.append("You have full autonomy to determine the approach.\n")

        return "\n".join(parts)

    def _build_output_instructions(self, outputs: list[str], output_dir: str | None) -> str:
        """Build instructions for structured outputs.

        If output_dir is available, instructs Claude to write outputs.json.
        Otherwise, uses the standard regex-based output format.
        """
        if output_dir:
            # File-based output instructions
            output_file = Path(output_dir) / "outputs.json"
            lines = [
                "\n## Required Outputs\n",
                "After completing the goals, write your outputs to a JSON file.\n\n",
                f"**Output file:** `{output_file}`\n\n",
                "The JSON should have these keys:\n",
            ]
            for key in outputs:
                lines.append(f"- `{key}`: (string value)\n")
            lines.append("\nExample:\n```json\n{\n")
            for i, key in enumerate(outputs):
                comma = "," if i < len(outputs) - 1 else ""
                lines.append(f'  "{key}": "your value here"{comma}\n')
            lines.append("}\n```\n")
            return "".join(lines)
        else:
            # Fall back to regex-based output instructions
            return OutputExtractor.output_instructions(outputs)

    def _extract_outputs(
        self, response: str, output_keys: list[str], output_dir: str | None
    ) -> dict[str, str]:
        """Extract outputs, trying file-based first then regex fallback."""
        if output_dir:
            output_file = Path(output_dir) / "outputs.json"
            if output_file.exists():
                try:
                    with output_file.open() as f:
                        data = json.load(f)
                    # Convert all values to strings
                    return {k: str(v) for k, v in data.items() if k in output_keys}
                except (json.JSONDecodeError, OSError):
                    pass  # Fall through to regex extraction

        # Regex fallback
        return self.output_extractor.extract(response, output_keys)

    async def _gather_context_parallel(
        self, context_commands: dict[str, str], working_dir: Path
    ) -> dict[str, str]:
        """Gather context by running shell commands in parallel."""

        async def run_command(name: str, command: str) -> tuple[str, str]:
            try:
                proc = await asyncio.create_subprocess_shell(
                    command,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    cwd=working_dir,
                )
                stdout, _ = await proc.communicate()
                output = stdout.decode("utf-8", errors="replace").strip()
                return name, output if output else "(no output)"
            except Exception as e:
                return name, f"(error: {e})"

        # Run all context commands in parallel
        tasks = [run_command(name, cmd) for name, cmd in context_commands.items()]
        results = await asyncio.gather(*tasks)

        # Preserve original order from context_commands
        return {name: dict(results)[name] for name in context_commands}

    def run_sync(
        self,
        job_name: str,
        job: Job,
        workflow: Workflow,
        context: ExpressionContext,
        log_directory: Path,
        dry_run: bool = False,
        run_id: str | None = None,
        session_ids: dict[str, str] | None = None,
    ) -> JobResult:
        """Synchronous version of run."""
        return asyncio.run(
            self.run(job_name, job, workflow, context, log_directory, dry_run, run_id, session_ids)
        )

    def _build_prompt_and_config(
        self,
        job_name: str,
        job: Job,
        workflow: Workflow,
        context: ExpressionContext,
    ) -> tuple[str, ProviderConfig]:
        """Build the prompt and provider config for a job."""
        # Get base prompt from agent or inline
        from agent_manager.models.agent import MCPServer
        mcp_servers: list[MCPServer] = []
        extra_env: dict[str, str] = {}

        if job.agent:
            agent = self.agent_store.load(job.agent)
            base_prompt = agent.prompt
            allowed_tools = job.allowed_tools or agent.allowed_tools
            max_turns = job.max_turns or agent.max_turns
            max_budget = job.max_budget_usd or agent.max_budget_usd
            working_dir = job.working_directory or agent.working_directory

            # Resolve agent integrations
            if agent.integrations:
                if agent.integrations.mcp_servers:
                    mcp_servers = agent.integrations.mcp_servers
                if agent.integrations.env:
                    for env_var in agent.integrations.env:
                        value = env_var.resolve()
                        if value is not None:
                            extra_env[env_var.name] = value
        elif job.prompt:
            base_prompt = job.prompt
            allowed_tools = workflow.allowed_tools(job_name)
            max_turns = workflow.max_turns(job_name)
            max_budget = workflow.max_budget(job_name)
            working_dir = workflow.working_directory(job_name)
        else:
            raise ValueError(f"Job '{job_name}' has neither 'agent' nor 'prompt' defined")

        # Interpolate expressions in prompt
        interpolated_prompt = self.expression_evaluator.interpolate(base_prompt, context)

        # Add output instructions if outputs are declared
        if job.outputs:
            final_prompt = interpolated_prompt + OutputExtractor.output_instructions(job.outputs)
        else:
            final_prompt = interpolated_prompt

        # Build config
        config = ProviderConfig(
            working_directory=Path(working_dir).expanduser(),
            allowed_tools=allowed_tools,
            max_turns=max_turns,
            max_budget_usd=max_budget,
            permission_mode=workflow.permission_mode(job_name),
            model=workflow.model(job_name),
            mcp_servers=mcp_servers,
            extra_env=extra_env,
        )

        return final_prompt, config


# Default instance
_runner: JobRunner | None = None


def get_job_runner() -> JobRunner:
    """Get the default job runner instance."""
    global _runner
    if _runner is None:
        _runner = JobRunner()
    return _runner
