"""Result models for workflow and job execution."""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import TYPE_CHECKING
from uuid import uuid4

from pydantic import BaseModel, Field

if TYPE_CHECKING:
    from agent_manager.models.workflow import Workflow


class WorkflowStatus(str, Enum):
    """Status of a workflow run."""

    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class JobStatus(str, Enum):
    """Status of a job execution."""

    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    SKIPPED = "skipped"
    CANCELLED = "cancelled"


class JobResult(BaseModel):
    """Result of a single job execution."""

    job_name: str = Field(alias="job_name")
    status: JobStatus = JobStatus.PENDING
    outputs: dict[str, str] = Field(default_factory=dict)
    start_time: datetime | None = Field(default=None, alias="start_time")
    end_time: datetime | None = Field(default=None, alias="end_time")
    cost: float | None = None
    input_tokens: int | None = Field(default=None, alias="input_tokens")
    output_tokens: int | None = Field(default=None, alias="output_tokens")
    error_message: str | None = Field(default=None, alias="error_message")
    log_file: str | None = Field(default=None, alias="log_file")
    claude_output: str | None = Field(default=None, alias="claude_output")
    output_dir: str | None = Field(default=None, alias="output_dir")
    session_id: str | None = Field(default=None, alias="session_id")

    model_config = {"populate_by_name": True}

    @property
    def duration(self) -> float | None:
        """Duration of the job execution in seconds."""
        if self.start_time and self.end_time:
            return (self.end_time - self.start_time).total_seconds()
        return None

    @property
    def total_tokens(self) -> int | None:
        """Total tokens used (input + output)."""
        if self.input_tokens is not None and self.output_tokens is not None:
            return self.input_tokens + self.output_tokens
        return None

    @property
    def is_finished(self) -> bool:
        """Check if the job has completed (successfully or with failure)."""
        return self.status in (
            JobStatus.COMPLETED,
            JobStatus.FAILED,
            JobStatus.SKIPPED,
            JobStatus.CANCELLED,
        )

    @property
    def is_successful(self) -> bool:
        """Check if the job was successful."""
        return self.status == JobStatus.COMPLETED

    def mark_started(self) -> None:
        """Mark the job as started."""
        self.status = JobStatus.RUNNING
        self.start_time = datetime.now()

    def mark_completed(
        self,
        outputs: dict[str, str] | None = None,
        claude_output: str | None = None,
    ) -> None:
        """Mark the job as completed with outputs."""
        self.status = JobStatus.COMPLETED
        self.end_time = datetime.now()
        if outputs:
            self.outputs = outputs
        if claude_output:
            self.claude_output = claude_output

    def mark_failed(self, error: str) -> None:
        """Mark the job as failed."""
        self.status = JobStatus.FAILED
        self.end_time = datetime.now()
        self.error_message = error

    def mark_skipped(self, reason: str | None = None) -> None:
        """Mark the job as skipped."""
        self.status = JobStatus.SKIPPED
        self.end_time = datetime.now()
        if reason:
            self.error_message = f"Skipped: {reason}"

    def mark_cancelled(self) -> None:
        """Mark the job as cancelled."""
        self.status = JobStatus.CANCELLED
        self.end_time = datetime.now()

    def update_stats(
        self,
        input_tokens: int | None = None,
        output_tokens: int | None = None,
        cost: float | None = None,
    ) -> None:
        """Update token and cost information."""
        self.input_tokens = input_tokens
        self.output_tokens = output_tokens
        self.cost = cost


class WorkflowRun(BaseModel):
    """A specific execution of a workflow."""

    id: str = Field(default_factory=lambda: uuid4().hex)
    workflow_name: str = Field(alias="workflow_name")
    status: WorkflowStatus = WorkflowStatus.PENDING
    job_results: dict[str, JobResult] = Field(default_factory=dict, alias="job_results")
    start_time: datetime = Field(default_factory=datetime.now, alias="start_time")
    end_time: datetime | None = Field(default=None, alias="end_time")
    error_message: str | None = Field(default=None, alias="error_message")
    is_dry_run: bool = Field(default=False, alias="is_dry_run")

    model_config = {"populate_by_name": True}

    @classmethod
    def create(
        cls,
        workflow_name: str,
        job_names: list[str],
        is_dry_run: bool = False,
    ) -> "WorkflowRun":
        """Create a new workflow run with pending jobs."""
        job_results = {name: JobResult(job_name=name) for name in job_names}
        return cls(
            workflow_name=workflow_name,
            job_results=job_results,
            is_dry_run=is_dry_run,
        )

    @property
    def total_cost(self) -> float:
        """Total cost of all jobs in the workflow."""
        return sum(r.cost or 0 for r in self.job_results.values())

    @property
    def total_tokens(self) -> int:
        """Total tokens used by all jobs."""
        return sum(r.total_tokens or 0 for r in self.job_results.values())

    @property
    def total_input_tokens(self) -> int:
        """Total input tokens."""
        return sum(r.input_tokens or 0 for r in self.job_results.values())

    @property
    def total_output_tokens(self) -> int:
        """Total output tokens."""
        return sum(r.output_tokens or 0 for r in self.job_results.values())

    @property
    def duration(self) -> float | None:
        """Duration of the entire workflow run in seconds."""
        if self.end_time:
            return (self.end_time - self.start_time).total_seconds()
        return None

    @property
    def completed_job_count(self) -> int:
        """Number of completed jobs."""
        return sum(1 for r in self.job_results.values() if r.status == JobStatus.COMPLETED)

    @property
    def failed_job_count(self) -> int:
        """Number of failed jobs."""
        return sum(1 for r in self.job_results.values() if r.status == JobStatus.FAILED)

    @property
    def skipped_job_count(self) -> int:
        """Number of skipped jobs."""
        return sum(1 for r in self.job_results.values() if r.status == JobStatus.SKIPPED)

    @property
    def all_jobs_finished(self) -> bool:
        """Check if all jobs are finished."""
        return all(r.is_finished for r in self.job_results.values())

    @property
    def is_running(self) -> bool:
        """Check if the workflow is still running."""
        return self.status == WorkflowStatus.RUNNING

    def mark_started(self) -> None:
        """Mark the workflow as started."""
        self.status = WorkflowStatus.RUNNING
        self.start_time = datetime.now()

    def mark_completed(self) -> None:
        """Mark the workflow as completed."""
        self.status = WorkflowStatus.COMPLETED
        self.end_time = datetime.now()

    def mark_failed(self, error: str) -> None:
        """Mark the workflow as failed."""
        self.status = WorkflowStatus.FAILED
        self.end_time = datetime.now()
        self.error_message = error

    def mark_cancelled(self) -> None:
        """Mark the workflow as cancelled."""
        self.status = WorkflowStatus.CANCELLED
        self.end_time = datetime.now()

    def job_result(self, name: str) -> JobResult | None:
        """Get result for a specific job."""
        return self.job_results.get(name)

    def update_job_result(self, result: JobResult) -> None:
        """Update a job result."""
        self.job_results[result.job_name] = result

    def outputs(self, job_name: str) -> dict[str, str]:
        """Get outputs for a specific job."""
        result = self.job_results.get(job_name)
        return result.outputs if result else {}

    def output(self, job: str, key: str) -> str | None:
        """Get a specific output value."""
        result = self.job_results.get(job)
        return result.outputs.get(key) if result else None

    def ready_jobs(self, workflow: "Workflow") -> list[str]:
        """Get jobs that are ready to run (pending and all dependencies completed)."""
        ready = []
        for name, result in self.job_results.items():
            if result.status != JobStatus.PENDING:
                continue

            job = workflow.jobs.get(name)
            if not job:
                continue

            # Check if all dependencies are completed
            if job.needs:
                all_deps_done = all(
                    self.job_results.get(dep, JobResult(job_name=dep)).status
                    == JobStatus.COMPLETED
                    for dep in job.needs
                )
                if not all_deps_done:
                    continue

            ready.append(name)

        return sorted(ready)

    def summary(self) -> str:
        """Create a summary of the workflow run."""
        lines = [
            f"Workflow: {self.workflow_name}",
            f"Status: {self.status.value}",
            f"Run ID: {self.id}",
        ]

        if self.duration is not None:
            lines.append(f"Duration: {self.duration:.1f}s")

        lines.append("")
        lines.append("Jobs:")

        status_icons = {
            JobStatus.PENDING: "○",
            JobStatus.RUNNING: "◐",
            JobStatus.COMPLETED: "●",
            JobStatus.FAILED: "✗",
            JobStatus.SKIPPED: "⊘",
            JobStatus.CANCELLED: "◌",
        }

        for name, result in sorted(self.job_results.items()):
            icon = status_icons.get(result.status, "?")
            job_line = f"  {icon} {name}: {result.status.value}"

            if result.duration is not None:
                job_line += f" ({result.duration:.1f}s)"

            if result.cost is not None:
                job_line += f" ${result.cost:.4f}"

            lines.append(job_line)

            if result.status == JobStatus.FAILED and result.error_message:
                lines.append(f"      Error: {result.error_message}")

        lines.append("")
        lines.append(f"Total Cost: ${self.total_cost:.4f}")
        lines.append(
            f"Total Tokens: {self.total_tokens} "
            f"({self.total_input_tokens} input, {self.total_output_tokens} output)"
        )

        return "\n".join(lines)


class WorkflowStats(BaseModel):
    """Statistics for workflow runs."""

    total_runs: int = Field(default=0, alias="total_runs")
    successful_runs: int = Field(default=0, alias="successful_runs")
    failed_runs: int = Field(default=0, alias="failed_runs")
    total_cost: float = Field(default=0.0, alias="total_cost")
    total_tokens: int = Field(default=0, alias="total_tokens")
    last_run_date: datetime | None = Field(default=None, alias="last_run_date")
    last_run_status: WorkflowStatus | None = Field(default=None, alias="last_run_status")
    average_duration: float | None = Field(default=None, alias="average_duration")

    model_config = {"populate_by_name": True}

    @property
    def success_rate(self) -> float:
        """Success rate as a fraction (0-1)."""
        if self.total_runs == 0:
            return 0.0
        return self.successful_runs / self.total_runs

    @property
    def average_cost(self) -> float | None:
        """Average cost per run."""
        if self.total_runs == 0:
            return None
        return self.total_cost / self.total_runs

    def record_run(self, run: WorkflowRun) -> None:
        """Record statistics from a workflow run."""
        self.total_runs += 1

        if run.status == WorkflowStatus.COMPLETED:
            self.successful_runs += 1
        elif run.status == WorkflowStatus.FAILED:
            self.failed_runs += 1

        self.total_cost += run.total_cost
        self.total_tokens += run.total_tokens
        self.last_run_date = run.end_time or run.start_time
        self.last_run_status = run.status

        # Update average duration
        if run.duration is not None:
            if self.average_duration is not None:
                self.average_duration = (
                    self.average_duration * (self.total_runs - 1) + run.duration
                ) / self.total_runs
            else:
                self.average_duration = run.duration
