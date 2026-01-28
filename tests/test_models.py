"""Tests for data models."""

from __future__ import annotations

import pytest

from agent_manager.models.workflow import (
    Job,
    ScheduleConfig,
    Workflow,
    WorkflowDefaults,
    WorkflowTriggers,
)
from agent_manager.models.result import JobResult, JobStatus, WorkflowRun, WorkflowStatus


class TestWorkflow:
    """Tests for Workflow model."""

    def test_simple_workflow(self) -> None:
        """Test creating a simple workflow."""
        wf = Workflow(
            name="test",
            on=WorkflowTriggers(manual=True),
            jobs={
                "main": Job(prompt="Do something"),
            },
        )
        assert wf.name == "test"
        assert len(wf.jobs) == 1
        assert wf.on.is_manual_enabled

    def test_workflow_with_dependencies(self) -> None:
        """Test workflow with job dependencies."""
        wf = Workflow(
            name="test",
            on=WorkflowTriggers(manual=True),
            jobs={
                "first": Job(prompt="First task"),
                "second": Job(prompt="Second task", needs=["first"]),
            },
        )
        assert wf.topological_sort() == ["first", "second"]

    def test_workflow_cycle_detection(self) -> None:
        """Test that circular dependencies are detected."""
        with pytest.raises(ValueError, match="Circular dependency"):
            Workflow(
                name="test",
                on=WorkflowTriggers(manual=True),
                jobs={
                    "a": Job(prompt="A", needs=["b"]),
                    "b": Job(prompt="B", needs=["a"]),
                },
            )

    def test_workflow_missing_dependency(self) -> None:
        """Test that missing dependencies are detected."""
        with pytest.raises(ValueError, match="unknown job"):
            Workflow(
                name="test",
                on=WorkflowTriggers(manual=True),
                jobs={
                    "a": Job(prompt="A", needs=["nonexistent"]),
                },
            )

    def test_workflow_yaml_roundtrip(self) -> None:
        """Test YAML serialization and parsing."""
        original = Workflow(
            name="test",
            description="A test workflow",
            on=WorkflowTriggers(manual=True),
            defaults=WorkflowDefaults(
                working_directory="~/repos",
                max_budget_usd=0.50,
            ),
            jobs={
                "main": Job(
                    prompt="Do something",
                    outputs=["result"],
                ),
            },
        )

        yaml_str = original.to_yaml()
        restored = Workflow.from_yaml(yaml_str)

        assert restored.name == original.name
        assert restored.description == original.description
        assert len(restored.jobs) == len(original.jobs)

    def test_workflow_from_yaml_with_on(self) -> None:
        """Test that YAML with 'on:' key is parsed correctly."""
        yaml_content = """
name: test
on:
  manual: true
jobs:
  main:
    prompt: Do something
"""
        wf = Workflow.from_yaml(yaml_content)
        assert wf.name == "test"
        assert wf.on.is_manual_enabled


class TestJobResult:
    """Tests for JobResult model."""

    def test_job_result_lifecycle(self) -> None:
        """Test job result state transitions."""
        result = JobResult(job_name="test")
        assert result.status == JobStatus.PENDING

        result.mark_started()
        assert result.status == JobStatus.RUNNING
        assert result.start_time is not None

        result.mark_completed(outputs={"key": "value"})
        assert result.status == JobStatus.COMPLETED
        assert result.end_time is not None
        assert result.outputs == {"key": "value"}

    def test_job_result_failure(self) -> None:
        """Test job failure state."""
        result = JobResult(job_name="test")
        result.mark_started()
        result.mark_failed("Something went wrong")

        assert result.status == JobStatus.FAILED
        assert result.error_message == "Something went wrong"


class TestWorkflowRun:
    """Tests for WorkflowRun model."""

    def test_workflow_run_creation(self) -> None:
        """Test creating a workflow run."""
        run = WorkflowRun.create(
            workflow_name="test",
            job_names=["a", "b"],
        )

        assert run.workflow_name == "test"
        assert run.status == WorkflowStatus.PENDING
        assert len(run.job_results) == 2
        assert "a" in run.job_results
        assert "b" in run.job_results

    def test_workflow_run_stats(self) -> None:
        """Test workflow run statistics."""
        run = WorkflowRun.create(
            workflow_name="test",
            job_names=["a", "b", "c"],
        )
        run.mark_started()

        # Complete one job
        run.job_results["a"].mark_started()
        run.job_results["a"].mark_completed()

        # Fail one job
        run.job_results["b"].mark_started()
        run.job_results["b"].mark_failed("error")

        # Leave one pending

        assert run.completed_job_count == 1
        assert run.failed_job_count == 1
