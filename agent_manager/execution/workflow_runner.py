"""Workflow runner - orchestrates job execution with DAG-based parallelism."""

from __future__ import annotations

import asyncio
from collections.abc import Callable
from typing import TYPE_CHECKING

from agent_manager.execution.job_runner import JobRunner, get_job_runner
from agent_manager.expressions.evaluator import ExpressionContext
from agent_manager.models.result import JobStatus, WorkflowRun, WorkflowStatus
from agent_manager.models.workflow import Workflow
from agent_manager.store.workflow_store import WorkflowStore, get_workflow_store

if TYPE_CHECKING:
    from pathlib import Path

# Type for status callback
StatusCallback = Callable[[str, JobStatus], None]


class WorkflowRunner:
    """Main entry point for executing workflows."""

    def __init__(
        self,
        store: WorkflowStore | None = None,
        job_runner: JobRunner | None = None,
        max_concurrent_jobs: int = 4,
    ):
        """Initialize the workflow runner.

        Args:
            store: Workflow store (defaults to singleton)
            job_runner: Job runner (defaults to singleton)
            max_concurrent_jobs: Maximum jobs to run in parallel
        """
        self.store = store or get_workflow_store()
        self.job_runner = job_runner or get_job_runner()
        self.max_concurrent_jobs = max_concurrent_jobs

    async def run(
        self,
        workflow: Workflow,
        dry_run: bool = False,
        single_job: str | None = None,
        status_callback: StatusCallback | None = None,
    ) -> WorkflowRun:
        """Run a workflow.

        Args:
            workflow: The workflow to execute
            dry_run: If true, don't actually execute Claude
            single_job: If set, only run this specific job
            status_callback: Optional callback for job status updates

        Returns:
            The workflow run result
        """
        # Create run
        job_names = [single_job] if single_job else list(workflow.jobs.keys())
        run = WorkflowRun.create(
            workflow_name=workflow.name,
            job_names=job_names,
            is_dry_run=dry_run,
        )
        run.mark_started()

        # Save initial state
        self.store.save_run(run)

        try:
            if single_job:
                run = await self._run_single_job(
                    workflow, run, single_job, dry_run, status_callback
                )
            else:
                run = await self._run_dag(
                    workflow, run, dry_run, status_callback
                )

            # Determine final status
            if run.failed_job_count > 0:
                run.mark_failed(f"{run.failed_job_count} job(s) failed")
            else:
                run.mark_completed()

        except Exception as e:
            run.mark_failed(str(e))

        # Save final state
        self.store.save_run(run)

        # Prune old runs
        self.store.prune_runs(workflow.name)

        return run

    async def _run_single_job(
        self,
        workflow: Workflow,
        run: WorkflowRun,
        job_name: str,
        dry_run: bool,
        status_callback: StatusCallback | None,
    ) -> WorkflowRun:
        """Run a single job from a workflow."""
        job = workflow.jobs.get(job_name)
        if not job:
            result = run.job_results[job_name]
            result.mark_failed(f"Job '{job_name}' not found")
            run.update_job_result(result)
            return run

        # Warn about dependencies
        if job.needs:
            print(f"Warning: Job '{job_name}' has dependencies: {job.needs}")
            print("Running without dependency outputs - conditionals may fail.")

        # Run the job
        context = ExpressionContext()
        log_dir = self.store.run_log_directory(workflow.name, run.id)

        if status_callback:
            status_callback(job_name, JobStatus.RUNNING)

        result = await self.job_runner.run(
            job_name=job_name,
            job=job,
            workflow=workflow,
            context=context,
            log_directory=log_dir,
            dry_run=dry_run,
            run_id=run.id,
            session_ids=None,  # No session continuation for single job runs
        )

        run.update_job_result(result)

        if status_callback:
            status_callback(job_name, result.status)

        return run

    async def _run_dag(
        self,
        workflow: Workflow,
        run: WorkflowRun,
        dry_run: bool,
        status_callback: StatusCallback | None,
    ) -> WorkflowRun:
        """Run all jobs respecting dependencies with parallelism."""
        context = ExpressionContext()
        log_dir = self.store.run_log_directory(workflow.name, run.id)

        pending = set(workflow.jobs.keys())
        running_tasks: dict[str, asyncio.Task[tuple[str, JobStatus]]] = {}
        semaphore = asyncio.Semaphore(self.max_concurrent_jobs)

        # Track session IDs for session continuation
        session_ids: dict[str, str] = {}

        async def run_job(job_name: str) -> tuple[str, JobStatus]:
            """Run a single job and return its name and status."""
            async with semaphore:
                job = workflow.jobs[job_name]

                if status_callback:
                    status_callback(job_name, JobStatus.RUNNING)

                result = await self.job_runner.run(
                    job_name=job_name,
                    job=job,
                    workflow=workflow,
                    context=context,
                    log_directory=log_dir,
                    dry_run=dry_run,
                    run_id=run.id,
                    session_ids=session_ids,
                )

                # Update context with outputs
                context.set_outputs(job_name, result.outputs)
                context.set_status(job_name, result.status.value)

                # Track session ID for continuation
                if result.session_id:
                    session_ids[job_name] = result.session_id

                run.update_job_result(result)
                self.store.save_run(run)

                if status_callback:
                    status_callback(job_name, result.status)

                return job_name, result.status

        # Process jobs until all are done
        while pending or running_tasks:
            # Find ready jobs
            ready = [
                name for name in pending
                if self._job_is_ready(name, workflow, run)
            ]

            # Start ready jobs
            for job_name in ready:
                pending.remove(job_name)
                task = asyncio.create_task(run_job(job_name))
                running_tasks[job_name] = task

            if not running_tasks and pending:
                # Deadlock - skip remaining jobs
                for job_name in pending:
                    result = run.job_results[job_name]
                    result.mark_skipped("Dependencies not satisfied")
                    run.update_job_result(result)
                break

            # Wait for at least one job to complete
            if running_tasks:
                done, _ = await asyncio.wait(
                    running_tasks.values(), return_when=asyncio.FIRST_COMPLETED
                )

                for task in done:
                    job_name, status = task.result()
                    del running_tasks[job_name]

                    # If job failed, skip dependents
                    if status == JobStatus.FAILED:
                        self._skip_dependents(job_name, workflow, run, pending)

        return run

    def _job_is_ready(
        self,
        job_name: str,
        workflow: Workflow,
        run: WorkflowRun,
    ) -> bool:
        """Check if a job is ready to run (all dependencies completed)."""
        job = workflow.jobs.get(job_name)
        if not job:
            return False

        if not job.needs:
            return True

        for dep in job.needs:
            dep_result = run.job_results.get(dep)
            if not dep_result:
                return False
            if dep_result.status not in (JobStatus.COMPLETED, JobStatus.SKIPPED):
                return False

        return True

    def _skip_dependents(
        self,
        failed_job: str,
        workflow: Workflow,
        run: WorkflowRun,
        pending: set[str],
    ) -> None:
        """Skip jobs that depend on a failed job."""
        dependents = workflow.dependents(failed_job)

        for dep in dependents:
            if dep in pending:
                result = run.job_results[dep]
                result.mark_skipped(f"Dependency '{failed_job}' failed")
                run.update_job_result(result)
                pending.discard(dep)

                # Recursively skip dependents
                self._skip_dependents(dep, workflow, run, pending)

    def run_sync(
        self,
        workflow: Workflow,
        dry_run: bool = False,
        single_job: str | None = None,
        status_callback: StatusCallback | None = None,
    ) -> WorkflowRun:
        """Synchronous version of run."""
        return asyncio.run(
            self.run(workflow, dry_run, single_job, status_callback)
        )

    async def run_by_name(
        self,
        name: str,
        dry_run: bool = False,
        single_job: str | None = None,
        status_callback: StatusCallback | None = None,
    ) -> WorkflowRun:
        """Run a workflow by name."""
        workflow = self.store.load(name)
        return await self.run(workflow, dry_run, single_job, status_callback)

    def run_by_name_sync(
        self,
        name: str,
        dry_run: bool = False,
        single_job: str | None = None,
        status_callback: StatusCallback | None = None,
    ) -> WorkflowRun:
        """Synchronous version of run_by_name."""
        return asyncio.run(
            self.run_by_name(name, dry_run, single_job, status_callback)
        )

    def dry_run_report(self, workflow: Workflow) -> str:
        """Generate a dry run report showing what would be executed."""
        lines = [
            f"Workflow: {workflow.name}",
        ]

        if workflow.description:
            lines.append(f"Description: {workflow.description}")

        lines.append("")
        lines.append(f"Jobs ({len(workflow.jobs)} total):")
        lines.append("")

        # Get topological order
        order = workflow.topological_sort()

        for i, job_name in enumerate(order, 1):
            job = workflow.jobs[job_name]

            lines.append(f"{i}. {job_name}")

            if job.agent:
                lines.append(f"   Agent: {job.agent}")
            elif job.prompt:
                truncated = job.prompt[:50] + "..." if len(job.prompt) > 50 else job.prompt
                lines.append(f"   Prompt: {truncated}")

            if job.needs:
                lines.append(f"   Depends on: {', '.join(job.needs)}")

            if job.if_condition:
                lines.append(f"   Condition: {job.if_condition}")

            if job.outputs:
                lines.append(f"   Outputs: {', '.join(job.outputs)}")

            lines.append(f"   Max budget: ${workflow.max_budget(job_name):.2f}")
            lines.append(f"   Max turns: {workflow.max_turns(job_name)}")
            lines.append("")

        # Show execution plan
        lines.append("Execution Plan:")
        lines.append(f"  Root jobs (can start immediately): {', '.join(workflow.root_jobs())}")

        if workflow.max_cost_usd:
            lines.append(f"  Maximum workflow cost: ${workflow.max_cost_usd:.2f}")

        return "\n".join(lines)


# Default instance
_runner: WorkflowRunner | None = None


def get_workflow_runner() -> WorkflowRunner:
    """Get the default workflow runner instance."""
    global _runner
    if _runner is None:
        _runner = WorkflowRunner()
    return _runner
