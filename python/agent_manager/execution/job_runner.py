"""Job runner - executes a single job within a workflow."""

from __future__ import annotations

import asyncio
import subprocess
from pathlib import Path

from agent_manager.expressions.evaluator import ExpressionContext, ExpressionEvaluator
from agent_manager.expressions.extractor import OutputExtractor
from agent_manager.models.result import JobResult
from agent_manager.models.workflow import Job, Workflow
from agent_manager.providers.base import LLMProvider, ProviderConfig
from agent_manager.providers.claude_cli import get_claude_cli_provider
from agent_manager.store.agent_store import get_agent_store


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
    ) -> JobResult:
        """Run a single job.

        Args:
            job_name: The name of the job
            job: The job definition
            workflow: The parent workflow
            context: The expression evaluation context
            log_directory: Directory to store job logs
            dry_run: If true, don't actually execute

        Returns:
            The job result with outputs
        """
        result = JobResult(job_name=job_name)
        result.mark_started()

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
            return await self._run_goals(job_name, job, workflow, context, log_directory, dry_run, result)

        # Handle single-prompt jobs (agent or inline prompt)
        return await self._run_single_prompt(job_name, job, workflow, context, log_directory, dry_run, result)

    async def _run_single_prompt(
        self,
        job_name: str,
        job: Job,
        workflow: Workflow,
        context: ExpressionContext,
        log_directory: Path,
        dry_run: bool,
        result: JobResult,
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

        response = await self.provider.execute(prompt, config, log_file)

        if not response.success:
            result.mark_failed(response.error or "Unknown error")
            return result

        # Update stats
        result.update_stats(
            input_tokens=response.input_tokens,
            output_tokens=response.output_tokens,
            cost=response.cost,
        )
        result.log_file = str(log_file)

        # Extract outputs
        if job.outputs:
            extracted = self.output_extractor.extract(response.result, job.outputs)
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
                context_results = {name: f"[DRY RUN] Would run: {cmd}" for name, cmd in job.context.items()}
            else:
                context_results = await self._gather_context_parallel(job.context, working_dir)

        # Step 2: Build prompt from context + goals
        prompt = self._build_goals_prompt(job, context_results)

        # Add output instructions if report fields are declared
        outputs = job.all_outputs
        if outputs:
            prompt += OutputExtractor.output_instructions(outputs)

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

        response = await self.provider.execute(prompt, config, log_file)

        if not response.success:
            result.mark_failed(response.error or "Unknown error")
            return result

        # Update stats
        result.update_stats(
            input_tokens=response.input_tokens,
            output_tokens=response.output_tokens,
            cost=response.cost,
        )
        result.log_file = str(log_file)

        # Step 4: Extract report outputs
        if outputs:
            extracted = self.output_extractor.extract(response.result, outputs)
            result.mark_completed(outputs=extracted, claude_output=response.result)
        else:
            result.mark_completed(claude_output=response.result)

        return result

    def _build_goals_prompt(self, job: Job, context_results: dict[str, str]) -> str:
        """Build a prompt from goals and gathered context."""
        parts: list[str] = []

        # Add context section if any context was gathered
        if context_results:
            parts.append("## Current Context\n")
            for name, output in context_results.items():
                parts.append(f"### {name}\n```\n{output}\n```\n")

        # Add goals section
        parts.append("## Goals\n")
        parts.append("Accomplish the following goals:\n")
        for i, goal in enumerate(job.goals or [], 1):
            parts.append(f"{i}. {goal}\n")

        parts.append("\nUse your judgment on how best to achieve these goals. ")
        parts.append("You have full autonomy to determine the approach.\n")

        return "\n".join(parts)

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
    ) -> JobResult:
        """Synchronous version of run."""
        return asyncio.run(
            self.run(job_name, job, workflow, context, log_directory, dry_run)
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
        if job.agent:
            agent = self.agent_store.load(job.agent)
            base_prompt = agent.prompt
            allowed_tools = job.allowed_tools or agent.allowed_tools
            max_turns = job.max_turns or agent.max_turns
            max_budget = job.max_budget_usd or agent.max_budget_usd
            working_dir = job.working_directory or agent.working_directory
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
