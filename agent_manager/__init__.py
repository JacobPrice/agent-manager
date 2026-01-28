"""Agent Manager - Workflow orchestration for local AI agents."""

from agent_manager.models.agent import Agent, Trigger, TriggerType
from agent_manager.models.workflow import Job, Workflow, WorkflowDefaults, WorkflowTriggers
from agent_manager.models.result import JobResult, JobStatus, WorkflowRun, WorkflowStatus

__all__ = [
    "Agent",
    "Trigger",
    "TriggerType",
    "Job",
    "Workflow",
    "WorkflowDefaults",
    "WorkflowTriggers",
    "JobResult",
    "JobStatus",
    "WorkflowRun",
    "WorkflowStatus",
]

__version__ = "0.2.0"
