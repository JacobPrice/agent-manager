"""LaunchAgent management for macOS scheduling."""

from __future__ import annotations

import plistlib
import subprocess
from dataclasses import dataclass
from pathlib import Path


@dataclass
class ScheduleInfo:
    """Information about a workflow's schedule."""

    workflow_name: str
    is_enabled: bool
    plist_path: Path | None
    cron_schedules: list[str]
    next_run: str | None = None


class LaunchAgentManager:
    """Manages macOS LaunchAgents for scheduled workflow execution."""

    PLIST_PREFIX = "com.agentmanager.workflow"

    def __init__(
        self,
        launch_agents_dir: Path | None = None,
        agentctl_path: str | None = None,
    ):
        """Initialize the manager.

        Args:
            launch_agents_dir: Directory for LaunchAgent plists (default: ~/Library/LaunchAgents)
            agentctl_path: Path to agentctl executable (default: find in PATH)
        """
        self.launch_agents_dir = launch_agents_dir or (
            Path.home() / "Library" / "LaunchAgents"
        )
        self.agentctl_path = agentctl_path or self._find_agentctl()

    def _find_agentctl(self) -> str:
        """Find the agentctl executable."""
        # Try to find in PATH
        result = subprocess.run(
            ["which", "agentctl"],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0:
            return result.stdout.strip()

        # Fall back to common locations
        common_paths = [
            Path.home() / ".local" / "bin" / "agentctl",
            Path("/usr/local/bin/agentctl"),
            Path.home() / "repos" / "agent-manager" / "python" / ".venv" / "bin" / "agentctl",
        ]
        for path in common_paths:
            if path.exists():
                return str(path)

        return "agentctl"  # Hope it's in PATH at runtime

    def plist_name(self, workflow_name: str) -> str:
        """Get the plist filename for a workflow."""
        return f"{self.PLIST_PREFIX}.{workflow_name}.plist"

    def plist_path(self, workflow_name: str) -> Path:
        """Get the full path to a workflow's plist file."""
        return self.launch_agents_dir / self.plist_name(workflow_name)

    def label(self, workflow_name: str) -> str:
        """Get the LaunchAgent label for a workflow."""
        return f"{self.PLIST_PREFIX}.{workflow_name}"

    def is_enabled(self, workflow_name: str) -> bool:
        """Check if a workflow is currently enabled."""
        plist = self.plist_path(workflow_name)
        if not plist.exists():
            return False

        # Check if loaded in launchd
        result = subprocess.run(
            ["launchctl", "list", self.label(workflow_name)],
            capture_output=True,
            text=True,
        )
        return result.returncode == 0

    def get_schedule_info(self, workflow_name: str, cron_schedules: list[str]) -> ScheduleInfo:
        """Get scheduling information for a workflow."""
        plist = self.plist_path(workflow_name)
        return ScheduleInfo(
            workflow_name=workflow_name,
            is_enabled=self.is_enabled(workflow_name),
            plist_path=plist if plist.exists() else None,
            cron_schedules=cron_schedules,
        )

    def enable(
        self,
        workflow_name: str,
        cron_schedules: list[str],
        log_path: Path | None = None,
    ) -> Path:
        """Enable scheduled execution for a workflow.

        Args:
            workflow_name: Name of the workflow
            cron_schedules: List of cron expressions (e.g., "0 9 * * *")
            log_path: Path for stdout/stderr logs

        Returns:
            Path to the created plist file
        """
        # Ensure directory exists
        self.launch_agents_dir.mkdir(parents=True, exist_ok=True)

        # Parse cron expressions into calendar intervals
        calendar_intervals = []
        for cron in cron_schedules:
            interval = self._cron_to_calendar_interval(cron)
            if interval:
                calendar_intervals.append(interval)

        if not calendar_intervals:
            raise ValueError("No valid cron schedules provided")

        # Default log path
        if log_path is None:
            log_path = Path.home() / ".agent-manager" / "logs" / f"{workflow_name}-scheduled.log"

        log_path.parent.mkdir(parents=True, exist_ok=True)

        # Build plist
        plist_data = {
            "Label": self.label(workflow_name),
            "ProgramArguments": [
                self.agentctl_path,
                "run",
                workflow_name,
            ],
            "StartCalendarInterval": calendar_intervals if len(calendar_intervals) > 1 else calendar_intervals[0],
            "StandardOutPath": str(log_path),
            "StandardErrorPath": str(log_path),
            "RunAtLoad": False,
            "EnvironmentVariables": {
                "PATH": "/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin",
                "HOME": str(Path.home()),
            },
        }

        # Write plist
        plist_path = self.plist_path(workflow_name)
        with plist_path.open("wb") as f:
            plistlib.dump(plist_data, f)

        # Load into launchd
        subprocess.run(
            ["launchctl", "load", str(plist_path)],
            check=True,
        )

        return plist_path

    def disable(self, workflow_name: str) -> bool:
        """Disable scheduled execution for a workflow.

        Returns:
            True if was enabled and is now disabled, False if wasn't enabled
        """
        plist_path = self.plist_path(workflow_name)

        if not plist_path.exists():
            return False

        # Unload from launchd (ignore errors if not loaded)
        subprocess.run(
            ["launchctl", "unload", str(plist_path)],
            capture_output=True,
        )

        # Remove plist file
        plist_path.unlink(missing_ok=True)

        return True

    def _cron_to_calendar_interval(self, cron: str) -> dict | None:
        """Convert a cron expression to a launchd CalendarInterval dict.

        Supports standard 5-field cron: minute hour day month weekday
        """
        parts = cron.split()
        if len(parts) != 5:
            return None

        minute, hour, day, month, weekday = parts

        interval: dict = {}

        # Minute (0-59)
        if minute != "*":
            try:
                interval["Minute"] = int(minute)
            except ValueError:
                pass

        # Hour (0-23)
        if hour != "*":
            try:
                interval["Hour"] = int(hour)
            except ValueError:
                pass

        # Day of month (1-31)
        if day != "*":
            try:
                interval["Day"] = int(day)
            except ValueError:
                pass

        # Month (1-12)
        if month != "*":
            try:
                interval["Month"] = int(month)
            except ValueError:
                pass

        # Day of week (0-6, Sunday = 0)
        if weekday != "*":
            try:
                interval["Weekday"] = int(weekday)
            except ValueError:
                pass

        # Return empty dict for "every minute" (all wildcards)
        # Return None only for invalid cron expressions
        return interval

    def list_enabled(self) -> list[str]:
        """List all enabled workflow schedules."""
        if not self.launch_agents_dir.exists():
            return []

        enabled = []
        for plist in self.launch_agents_dir.glob(f"{self.PLIST_PREFIX}.*.plist"):
            # Extract workflow name from filename
            name = plist.stem.replace(f"{self.PLIST_PREFIX}.", "")
            if self.is_enabled(name):
                enabled.append(name)

        return sorted(enabled)


# Singleton instance
_manager: LaunchAgentManager | None = None


def get_launch_agent_manager() -> LaunchAgentManager:
    """Get the singleton LaunchAgent manager instance."""
    global _manager
    if _manager is None:
        _manager = LaunchAgentManager()
    return _manager
