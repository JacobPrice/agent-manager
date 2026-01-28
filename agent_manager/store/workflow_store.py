"""Workflow storage and management."""

from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from agent_manager.models.result import WorkflowRun, WorkflowStats, WorkflowStatus
from agent_manager.models.workflow import Workflow


class WorkflowStoreError(Exception):
    """Base exception for workflow store errors."""

    pass


class WorkflowNotFoundError(WorkflowStoreError):
    """Workflow not found."""

    def __init__(self, name: str):
        self.name = name
        super().__init__(f"Workflow '{name}' not found")


class WorkflowAlreadyExistsError(WorkflowStoreError):
    """Workflow already exists."""

    def __init__(self, name: str):
        self.name = name
        super().__init__(f"Workflow '{name}' already exists")


class RunNotFoundError(WorkflowStoreError):
    """Workflow run not found."""

    def __init__(self, run_id: str):
        self.run_id = run_id
        super().__init__(f"Workflow run '{run_id}' not found")


@dataclass
class WorkflowInfo:
    """Summary information about a workflow."""

    name: str
    description: str | None
    job_count: int
    has_schedule: bool
    is_enabled: bool
    last_run_status: WorkflowStatus | None = None
    last_run_date: datetime | None = None
    stats: WorkflowStats | None = None

    @property
    def status_indicator(self) -> str:
        """Status indicator character."""
        return "●" if self.is_enabled else "○"

    @property
    def last_run_status_icon(self) -> str | None:
        """Icon for last run status."""
        if self.last_run_status is None:
            return None
        icons = {
            WorkflowStatus.COMPLETED: "✓",
            WorkflowStatus.FAILED: "✗",
            WorkflowStatus.RUNNING: "◐",
            WorkflowStatus.CANCELLED: "◌",
            WorkflowStatus.PENDING: "○",
        }
        return icons.get(self.last_run_status)


class WorkflowStore:
    """Manages workflow persistence and run history."""

    def __init__(self, base_directory: Path | None = None):
        if base_directory is None:
            base_directory = Path.home() / ".agent-manager"

        self.base_directory = base_directory
        self.workflows_directory = base_directory / "workflows"
        self.runs_directory = base_directory / "runs"
        self.stats_file = base_directory / "workflow-stats.json"

    def ensure_directories_exist(self) -> None:
        """Ensure all required directories exist."""
        self.workflows_directory.mkdir(parents=True, exist_ok=True)
        self.runs_directory.mkdir(parents=True, exist_ok=True)

    # MARK: - Workflow Path Helpers

    def workflow_path(self, name: str) -> Path:
        """Get path to workflow YAML file."""
        return self.workflows_directory / f"{name}.yaml"

    def run_directory(self, workflow_name: str) -> Path:
        """Get path to workflow's run directory."""
        return self.runs_directory / workflow_name

    def run_path(self, workflow_name: str, run_id: str) -> Path:
        """Get path to a specific run file."""
        return self.run_directory(workflow_name) / f"{run_id}.json"

    def run_log_directory(self, workflow_name: str, run_id: str) -> Path:
        """Get path to run's log directory."""
        return self.run_directory(workflow_name) / run_id

    # MARK: - Workflow CRUD Operations

    def list_workflow_names(self) -> list[str]:
        """List all workflow names."""
        if not self.workflows_directory.exists():
            return []

        return sorted([
            p.stem
            for p in self.workflows_directory.iterdir()
            if p.suffix in (".yaml", ".yml")
        ])

    def list_workflows(self) -> list[Workflow]:
        """Load all workflows."""
        workflows = []
        for name in self.list_workflow_names():
            try:
                workflows.append(self.load(name))
            except Exception:
                pass  # Skip invalid workflows
        return workflows

    def load(self, name: str) -> Workflow:
        """Load a specific workflow by name."""
        path = self.workflow_path(name)

        if not path.exists():
            raise WorkflowNotFoundError(name)

        return Workflow.load(path)

    def exists(self, name: str) -> bool:
        """Check if a workflow exists."""
        return self.workflow_path(name).exists()

    def save(self, workflow: Workflow) -> None:
        """Save a workflow."""
        self.ensure_directories_exist()
        path = self.workflow_path(workflow.name)
        workflow.save(path)

    def delete(self, name: str) -> None:
        """Delete a workflow."""
        path = self.workflow_path(name)

        if not path.exists():
            raise WorkflowNotFoundError(name)

        path.unlink()

    def get_workflow_info(self, name: str) -> WorkflowInfo:
        """Get workflow info for display."""
        workflow = self.load(name)
        # TODO: Check LaunchAgent status
        is_enabled = False  # Placeholder

        stats = self.load_workflow_stats(name)
        last_run = self.load_last_run(name)

        return WorkflowInfo(
            name=workflow.name,
            description=workflow.description,
            job_count=len(workflow.jobs),
            has_schedule=workflow.on.has_schedule,
            is_enabled=is_enabled,
            last_run_status=last_run.status if last_run else None,
            last_run_date=last_run.end_time or last_run.start_time if last_run else None,
            stats=stats if stats.total_runs > 0 else None,
        )

    def list_workflow_info(self) -> list[WorkflowInfo]:
        """Get info for all workflows."""
        infos = []
        for name in self.list_workflow_names():
            try:
                infos.append(self.get_workflow_info(name))
            except Exception:
                pass
        return infos

    # MARK: - Run Operations

    def save_run(self, run: WorkflowRun) -> None:
        """Save a workflow run."""
        self.ensure_directories_exist()

        run_dir = self.run_directory(run.workflow_name)
        run_dir.mkdir(parents=True, exist_ok=True)

        run_path = self.run_path(run.workflow_name, run.id)
        run_path.write_text(run.model_dump_json(by_alias=True, indent=2))

        # Update workflow stats
        self._update_workflow_stats(run.workflow_name, run)

    def load_run(self, workflow_name: str, run_id: str) -> WorkflowRun:
        """Load a specific run."""
        path = self.run_path(workflow_name, run_id)

        if not path.exists():
            raise RunNotFoundError(run_id)

        data = json.loads(path.read_text())
        return WorkflowRun.model_validate(data)

    def list_runs(self, workflow_name: str, limit: int = 10) -> list[WorkflowRun]:
        """List runs for a workflow (most recent first)."""
        run_dir = self.run_directory(workflow_name)

        if not run_dir.exists():
            return []

        # Get JSON files sorted by modification time (newest first)
        run_files = sorted(
            [p for p in run_dir.iterdir() if p.suffix == ".json"],
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )

        runs = []
        for path in run_files[:limit]:
            try:
                data = json.loads(path.read_text())
                runs.append(WorkflowRun.model_validate(data))
            except Exception:
                pass  # Skip invalid runs

        return runs

    def load_last_run(self, workflow_name: str) -> WorkflowRun | None:
        """Get the most recent run for a workflow."""
        runs = self.list_runs(workflow_name, limit=1)
        return runs[0] if runs else None

    def prune_runs(self, workflow_name: str, keep_count: int = 50) -> None:
        """Delete old runs (keep most recent N)."""
        run_dir = self.run_directory(workflow_name)

        if not run_dir.exists():
            return

        # Get JSON files sorted by modification time (newest first)
        run_files = sorted(
            [p for p in run_dir.iterdir() if p.suffix == ".json"],
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )

        # Delete runs beyond the keep count
        for path in run_files[keep_count:]:
            path.unlink(missing_ok=True)

            # Also delete the log directory if it exists
            log_dir = path.with_suffix("")
            if log_dir.is_dir():
                import shutil

                shutil.rmtree(log_dir, ignore_errors=True)

    # MARK: - Stats Operations

    def load_all_workflow_stats(self) -> dict[str, WorkflowStats]:
        """Load all workflow stats."""
        if not self.stats_file.exists():
            return {}

        data = json.loads(self.stats_file.read_text())
        return {
            name: WorkflowStats.model_validate(stats) for name, stats in data.items()
        }

    def load_workflow_stats(self, name: str) -> WorkflowStats:
        """Load stats for a specific workflow."""
        all_stats = self.load_all_workflow_stats()
        return all_stats.get(name, WorkflowStats())

    def _save_workflow_stats(self, stats: dict[str, WorkflowStats]) -> None:
        """Save workflow stats."""
        data = {name: s.model_dump(by_alias=True) for name, s in stats.items()}
        self.stats_file.parent.mkdir(parents=True, exist_ok=True)
        self.stats_file.write_text(json.dumps(data, indent=2, default=str))

    def _update_workflow_stats(self, name: str, run: WorkflowRun) -> None:
        """Update stats for a workflow after a run."""
        all_stats = self.load_all_workflow_stats()
        stats = all_stats.get(name, WorkflowStats())
        stats.record_run(run)
        all_stats[name] = stats
        self._save_workflow_stats(all_stats)

    def delete_workflow_stats(self, name: str) -> None:
        """Delete stats for a workflow."""
        all_stats = self.load_all_workflow_stats()
        all_stats.pop(name, None)
        self._save_workflow_stats(all_stats)


# Singleton instance
_store: WorkflowStore | None = None


def get_workflow_store() -> WorkflowStore:
    """Get the singleton workflow store instance."""
    global _store
    if _store is None:
        _store = WorkflowStore()
    return _store
