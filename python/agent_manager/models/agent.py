"""Agent model - reusable prompt templates."""

from __future__ import annotations

from enum import Enum
from pathlib import Path
import yaml
from typing_extensions import Self
from pydantic import BaseModel, Field


class TriggerType(str, Enum):
    """Type of trigger for an agent."""

    SCHEDULE = "schedule"
    MANUAL = "manual"
    FILE_WATCH = "file-watch"


class Trigger(BaseModel):
    """Trigger configuration for an agent."""

    type: TriggerType
    hour: int | None = None
    minute: int | None = None
    watch_path: str | None = None


class Agent(BaseModel):
    """A reusable agent template with default settings."""

    name: str
    description: str
    trigger: Trigger | None = None  # Optional - agents are templates used in workflows
    working_directory: str = Field(default="~/", alias="working_directory")
    context_script: str | None = Field(default=None, alias="context_script")
    prompt: str
    allowed_tools: list[str] = Field(alias="allowed_tools")
    max_turns: int = Field(default=10, alias="max_turns")
    max_budget_usd: float = Field(default=1.0, alias="max_budget_usd")

    model_config = {
        "populate_by_name": True,
        "extra": "forbid",
    }

    @property
    def expanded_working_directory(self) -> Path:
        """Expand ~ in working directory to full path."""
        return Path(self.working_directory).expanduser()

    @classmethod
    def load(cls, path: Path | str) -> Self:
        """Load an agent from a YAML file."""
        path = Path(path)
        with path.open() as f:
            data = yaml.safe_load(f)
        return cls.model_validate(data)

    @classmethod
    def from_yaml(cls, content: str) -> Self:
        """Parse an agent from YAML string."""
        data = yaml.safe_load(content)
        return cls.model_validate(data)

    def to_yaml(self) -> str:
        """Serialize agent to YAML string."""
        data = self.model_dump(by_alias=True, exclude_none=True)
        return yaml.dump(data, default_flow_style=False, sort_keys=False, allow_unicode=True)

    def save(self, path: Path | str) -> None:
        """Save agent to a YAML file."""
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(self.to_yaml())

    @classmethod
    def template(cls, name: str) -> Self:
        """Create a template agent with default values."""
        return cls(
            name=name,
            description="Description of what this agent does",
            trigger=Trigger(type=TriggerType.MANUAL),
            working_directory="~/",
            context_script="""\
# Gather context for the agent
echo "Current directory: $(pwd)"
echo "Date: $(date)"
""",
            prompt="""\
You are an automated agent. Your task is to...

Please analyze the context provided and take appropriate action.
""",
            allowed_tools=["Read", "Edit", "Write", "Bash(git *)"],
            max_turns=10,
            max_budget_usd=1.0,
        )
