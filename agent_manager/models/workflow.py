"""Workflow model - executable orchestration with jobs."""

from __future__ import annotations

from pathlib import Path

import yaml
from typing_extensions import Self
from pydantic import BaseModel, Field, model_validator


# Custom YAML loader that doesn't convert on/off/yes/no to booleans
class SafeLineLoader(yaml.SafeLoader):
    """YAML loader that keeps 'on', 'off', 'yes', 'no' as strings."""
    pass


# Remove boolean constructors for problematic strings
SafeLineLoader.add_constructor(
    "tag:yaml.org,2002:bool",
    lambda loader, node: loader.construct_yaml_str(node)
    if node.value.lower() in ("on", "off", "yes", "no")
    else loader.construct_yaml_bool(node),
)


def safe_yaml_load(content: str) -> dict:
    """Load YAML without converting on/off/yes/no to booleans."""
    return yaml.load(content, Loader=SafeLineLoader)


class ScheduleConfig(BaseModel):
    """Cron schedule configuration."""

    cron: str


class WorkflowTriggers(BaseModel):
    """Trigger configuration for a workflow."""

    schedule: list[ScheduleConfig] | None = None
    manual: bool | None = None

    @property
    def is_manual_enabled(self) -> bool:
        """Check if manual trigger is enabled (defaults to True)."""
        return self.manual if self.manual is not None else True

    @property
    def has_schedule(self) -> bool:
        """Check if workflow has any schedule triggers."""
        return bool(self.schedule)


class WorkflowDefaults(BaseModel):
    """Default settings for jobs in a workflow."""

    working_directory: str | None = Field(default=None, alias="working_directory")
    max_budget_usd: float | None = Field(default=None, alias="max_budget_usd")
    max_turns: int | None = Field(default=None, alias="max_turns")
    allowed_tools: list[str] | None = Field(default=None, alias="allowed_tools")
    permission_mode: str | None = Field(default=None, alias="permission_mode")
    model: str | None = Field(default=None, alias="model")  # "opus", "sonnet", "haiku"

    model_config = {"populate_by_name": True}


class Job(BaseModel):
    """A single execution unit within a workflow.

    Jobs can be defined in three ways:
    1. Goals-based: Specify goals and let Claude figure out how to achieve them
    2. Prompt-based: Provide a direct prompt
    3. Agent-based: Reference a reusable agent template
    """

    # Goals-based execution (recommended)
    goals: list[str] | None = None
    context: dict[str, str] | None = None  # name -> shell command to gather context

    # Direct prompt (alternative to goals)
    prompt: str | None = None

    # Reference to reusable agent (alternative to goals/prompt)
    agent: str | None = None

    # Dependencies and conditionals
    needs: list[str] | None = None
    if_condition: str | None = Field(default=None, alias="if")

    # Structured outputs to extract from response
    report: list[str] | None = None

    # Legacy field for backwards compatibility
    outputs: list[str] | None = None

    # Per-job overrides
    working_directory: str | None = Field(default=None, alias="working_directory")
    allowed_tools: list[str] | None = Field(default=None, alias="allowed_tools")
    max_turns: int | None = Field(default=None, alias="max_turns")
    max_budget_usd: float | None = Field(default=None, alias="max_budget_usd")
    permission_mode: str | None = Field(default=None, alias="permission_mode")
    model: str | None = Field(default=None, alias="model")  # "opus", "sonnet", "haiku"

    model_config = {"populate_by_name": True}

    @property
    def has_goals(self) -> bool:
        """Check if this job uses goals-based execution."""
        return self.goals is not None and len(self.goals) > 0

    @property
    def all_outputs(self) -> list[str]:
        """Get all outputs from job."""
        return self.report or self.outputs or []

    @property
    def has_dependencies(self) -> bool:
        """Check if this job has any dependencies."""
        return bool(self.needs)

    @property
    def uses_agent(self) -> bool:
        """Check if this job references an external agent."""
        return self.agent is not None

    @property
    def has_inline_prompt(self) -> bool:
        """Check if this job has an inline prompt."""
        return self.prompt is not None


class Workflow(BaseModel):
    """Executable workflow orchestration with jobs."""

    name: str
    description: str | None = None
    on: WorkflowTriggers
    defaults: WorkflowDefaults | None = None
    jobs: dict[str, Job]
    max_cost_usd: float | None = Field(default=None, alias="max_cost_usd")

    model_config = {"populate_by_name": True}

    @model_validator(mode="after")
    def validate_workflow(self) -> Self:
        """Validate workflow structure."""
        # Check each job has at least one of: agent, prompt, or goals
        for job_name, job in self.jobs.items():
            has_agent = job.agent is not None
            has_prompt = job.prompt is not None
            has_goals = job.goals is not None and len(job.goals) > 0

            if not (has_agent or has_prompt or has_goals):
                raise ValueError(f"Job '{job_name}' must have 'agent', 'prompt', or 'goals' defined")

        # Check all dependencies exist
        for job_name, job in self.jobs.items():
            if job.needs:
                for dep in job.needs:
                    if dep not in self.jobs:
                        raise ValueError(
                            f"Job '{job_name}' depends on unknown job '{dep}'"
                        )

        # Check for cycles
        self._detect_cycles()

        return self

    def _detect_cycles(self) -> None:
        """Detect circular dependencies in the job graph."""
        visited: set[str] = set()
        rec_stack: set[str] = set()

        def dfs(job_name: str, path: list[str]) -> None:
            if job_name in rec_stack:
                cycle_path = path + [job_name]
                raise ValueError(f"Circular dependency detected: {' -> '.join(cycle_path)}")

            if job_name in visited:
                return

            visited.add(job_name)
            rec_stack.add(job_name)

            job = self.jobs.get(job_name)
            if job and job.needs:
                for dep in job.needs:
                    dfs(dep, path + [job_name])

            rec_stack.remove(job_name)

        for job_name in self.jobs:
            dfs(job_name, [])

    @property
    def job_names(self) -> list[str]:
        """Get job names sorted alphabetically."""
        return sorted(self.jobs.keys())

    def working_directory(self, job_name: str) -> str:
        """Get the effective working directory for a job."""
        job = self.jobs.get(job_name)
        if job and job.working_directory:
            return job.working_directory
        if self.defaults and self.defaults.working_directory:
            return self.defaults.working_directory
        return "~/"

    def max_budget(self, job_name: str) -> float:
        """Get the effective max budget for a job."""
        job = self.jobs.get(job_name)
        if job and job.max_budget_usd is not None:
            return job.max_budget_usd
        if self.defaults and self.defaults.max_budget_usd is not None:
            return self.defaults.max_budget_usd
        return 1.0

    def max_turns(self, job_name: str) -> int:
        """Get the effective max turns for a job."""
        job = self.jobs.get(job_name)
        if job and job.max_turns is not None:
            return job.max_turns
        if self.defaults and self.defaults.max_turns is not None:
            return self.defaults.max_turns
        return 10

    def allowed_tools(self, job_name: str) -> list[str]:
        """Get the effective allowed tools for a job."""
        job = self.jobs.get(job_name)
        if job and job.allowed_tools is not None:
            return job.allowed_tools
        if self.defaults and self.defaults.allowed_tools is not None:
            return self.defaults.allowed_tools
        return ["Read", "Grep", "Glob"]

    def permission_mode(self, job_name: str) -> str | None:
        """Get the effective permission mode for a job."""
        job = self.jobs.get(job_name)
        if job and job.permission_mode is not None:
            return job.permission_mode
        if self.defaults and self.defaults.permission_mode is not None:
            return self.defaults.permission_mode
        return None

    def model(self, job_name: str) -> str | None:
        """Get the effective model for a job."""
        job = self.jobs.get(job_name)
        if job and job.model is not None:
            return job.model
        if self.defaults and self.defaults.model is not None:
            return self.defaults.model
        return None  # Use Claude CLI default

    def topological_sort(self) -> list[str]:
        """Get jobs in topological order (respecting dependencies)."""
        result: list[str] = []
        visited: set[str] = set()
        temp_mark: set[str] = set()

        def visit(job_name: str) -> None:
            if job_name in temp_mark:
                raise ValueError(f"Circular dependency at '{job_name}'")
            if job_name in visited:
                return

            temp_mark.add(job_name)

            job = self.jobs.get(job_name)
            if job and job.needs:
                for dep in job.needs:
                    visit(dep)

            temp_mark.remove(job_name)
            visited.add(job_name)
            result.append(job_name)

        for job_name in sorted(self.jobs.keys()):
            visit(job_name)

        return result

    def root_jobs(self) -> list[str]:
        """Get jobs that have no dependencies (can start immediately)."""
        return sorted([name for name, job in self.jobs.items() if not job.has_dependencies])

    def dependents(self, job_name: str) -> list[str]:
        """Get jobs that depend on the given job."""
        return sorted([
            name for name, job in self.jobs.items()
            if job.needs and job_name in job.needs
        ])

    @classmethod
    def load(cls, path: Path | str) -> Self:
        """Load a workflow from a YAML file."""
        path = Path(path)
        data = safe_yaml_load(path.read_text())
        return cls.model_validate(data)

    @classmethod
    def from_yaml(cls, content: str) -> Self:
        """Parse a workflow from YAML string."""
        data = safe_yaml_load(content)
        return cls.model_validate(data)

    def to_yaml(self) -> str:
        """Serialize workflow to YAML string."""
        data = self.model_dump(by_alias=True, exclude_none=True)
        return yaml.dump(data, default_flow_style=False, sort_keys=False, allow_unicode=True)

    def save(self, path: Path | str) -> None:
        """Save workflow to a YAML file."""
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(self.to_yaml())

    @classmethod
    def template(cls, name: str) -> Self:
        """Create a template workflow with default values."""
        return cls(
            name=name,
            description="Description of what this workflow does",
            on=WorkflowTriggers(manual=True),
            defaults=WorkflowDefaults(
                working_directory="~/",
                max_budget_usd=0.50,
                max_turns=20,
                allowed_tools=["Read", "Grep", "Glob"],
            ),
            jobs={
                "main": Job(
                    context={
                        "files": "ls -la",
                        "git_status": "git status --short 2>/dev/null || echo '(not a git repo)'",
                    },
                    goals=[
                        "Analyze the current directory structure",
                        "Report any notable findings",
                    ],
                    report=["summary", "findings"],
                )
            },
        )

    @classmethod
    def multi_job_template(cls, name: str) -> Self:
        """Create a multi-job template for demonstration."""
        return cls(
            name=name,
            description="Multi-job workflow template with dependencies",
            on=WorkflowTriggers(manual=True),
            defaults=WorkflowDefaults(
                working_directory="~/repos/project",
                max_budget_usd=0.50,
                max_turns=20,
            ),
            jobs={
                "analyze": Job(
                    context={
                        "structure": "find . -type f -name '*.py' | head -20",
                        "readme": "cat README.md 2>/dev/null || echo '(no README)'",
                    },
                    goals=[
                        "Analyze the codebase structure and identify key components",
                        "Summarize the project purpose and architecture",
                    ],
                    report=["summary", "components"],
                    allowed_tools=["Read", "Grep", "Glob"],
                ),
                "review": Job(
                    needs=["analyze"],
                    if_condition="${{ jobs.analyze.outputs.summary != '' }}",
                    goals=[
                        "Review code quality based on the analysis: ${{ jobs.analyze.outputs.summary }}",
                        "Identify potential improvements",
                    ],
                    report=["issues", "recommendations"],
                    allowed_tools=["Read"],
                ),
                "report": Job(
                    needs=["analyze", "review"],
                    goals=[
                        "Generate a final report combining findings from analyze and review jobs",
                        "Provide actionable next steps",
                    ],
                    report=["final_report"],
                ),
            },
        )
