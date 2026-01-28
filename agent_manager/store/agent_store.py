"""Agent storage and management."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import TYPE_CHECKING

from agent_manager.models.agent import Agent, TriggerType

if TYPE_CHECKING:
    pass


class AgentStoreError(Exception):
    """Base exception for agent store errors."""

    pass


class AgentNotFoundError(AgentStoreError):
    """Agent not found."""

    def __init__(self, name: str):
        self.name = name
        super().__init__(f"Agent '{name}' not found")


class AgentAlreadyExistsError(AgentStoreError):
    """Agent already exists."""

    def __init__(self, name: str):
        self.name = name
        super().__init__(f"Agent '{name}' already exists")


@dataclass
class AgentInfo:
    """Summary information about an agent."""

    name: str
    description: str
    trigger_type: TriggerType
    is_enabled: bool
    last_run: datetime | None = None
    run_count: int = 0
    total_cost: float = 0.0

    @property
    def status_indicator(self) -> str:
        """Status indicator character."""
        return "●" if self.is_enabled else "○"

    @property
    def trigger_icon(self) -> str:
        """Icon for trigger type."""
        icons = {
            TriggerType.SCHEDULE: "⏰",
            TriggerType.MANUAL: "▶",
            TriggerType.FILE_WATCH: "👁",
        }
        return icons.get(self.trigger_type, "?")


class AgentStore:
    """Manages agent persistence and metadata."""

    def __init__(self, base_directory: Path | None = None):
        if base_directory is None:
            base_directory = Path.home() / ".agent-manager"

        self.base_directory = base_directory
        self.agents_directory = base_directory / "agents"
        self.logs_directory = base_directory / "logs"
        self.config_file = base_directory / "config.yaml"

    def ensure_directories_exist(self) -> None:
        """Ensure all required directories exist."""
        self.agents_directory.mkdir(parents=True, exist_ok=True)
        self.logs_directory.mkdir(parents=True, exist_ok=True)

    def agent_path(self, name: str) -> Path:
        """Get path to agent YAML file."""
        return self.agents_directory / f"{name}.yaml"

    def log_directory(self, agent_name: str) -> Path:
        """Get path to agent's log directory."""
        return self.logs_directory / agent_name

    def list_agent_names(self) -> list[str]:
        """List all agent names."""
        if not self.agents_directory.exists():
            return []

        return sorted([
            p.stem
            for p in self.agents_directory.iterdir()
            if p.suffix in (".yaml", ".yml")
        ])

    def list_agents(self) -> list[Agent]:
        """Load all agents."""
        agents = []
        for name in self.list_agent_names():
            try:
                agents.append(self.load(name))
            except Exception:
                pass  # Skip invalid agents
        return agents

    def load(self, name: str) -> Agent:
        """Load a specific agent by name."""
        path = self.agent_path(name)

        if not path.exists():
            raise AgentNotFoundError(name)

        return Agent.load(path)

    def exists(self, name: str) -> bool:
        """Check if an agent exists."""
        return self.agent_path(name).exists()

    def save(self, agent: Agent) -> None:
        """Save an agent."""
        self.ensure_directories_exist()
        path = self.agent_path(agent.name)
        agent.save(path)

    def delete(self, name: str) -> None:
        """Delete an agent."""
        path = self.agent_path(name)

        if not path.exists():
            raise AgentNotFoundError(name)

        path.unlink()

    def get_agent_info(self, name: str) -> AgentInfo:
        """Get agent status info (for list command)."""
        agent = self.load(name)
        # TODO: Check LaunchAgent status and load stats
        is_enabled = False  # Placeholder
        last_run = None  # Placeholder

        return AgentInfo(
            name=agent.name,
            description=agent.description,
            trigger_type=agent.trigger.type,
            is_enabled=is_enabled,
            last_run=last_run,
        )

    def list_agent_info(self) -> list[AgentInfo]:
        """Get info for all agents."""
        infos = []
        for name in self.list_agent_names():
            try:
                infos.append(self.get_agent_info(name))
            except Exception:
                pass
        return infos


# Singleton instance
_store: AgentStore | None = None


def get_agent_store() -> AgentStore:
    """Get the singleton agent store instance."""
    global _store
    if _store is None:
        _store = AgentStore()
    return _store
