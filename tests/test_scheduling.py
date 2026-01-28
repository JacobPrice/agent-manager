"""Tests for scheduling infrastructure."""

from pathlib import Path
from tempfile import TemporaryDirectory

import pytest

from agent_manager.scheduling.launchd import LaunchAgentManager


class TestLaunchAgentManager:
    """Tests for LaunchAgent management."""

    def test_cron_to_calendar_interval_daily(self):
        """Test converting daily cron to calendar interval."""
        manager = LaunchAgentManager()

        # 9am daily
        result = manager._cron_to_calendar_interval("0 9 * * *")
        assert result == {"Minute": 0, "Hour": 9}

    def test_cron_to_calendar_interval_weekdays(self):
        """Test converting weekday cron to calendar interval."""
        manager = LaunchAgentManager()

        # 9am on Monday (weekday 1)
        result = manager._cron_to_calendar_interval("0 9 * * 1")
        assert result == {"Minute": 0, "Hour": 9, "Weekday": 1}

    def test_cron_to_calendar_interval_monthly(self):
        """Test converting monthly cron to calendar interval."""
        manager = LaunchAgentManager()

        # First of the month at midnight
        result = manager._cron_to_calendar_interval("0 0 1 * *")
        assert result == {"Minute": 0, "Hour": 0, "Day": 1}

    def test_cron_to_calendar_interval_all_wildcards(self):
        """Test cron with all wildcards."""
        manager = LaunchAgentManager()

        result = manager._cron_to_calendar_interval("* * * * *")
        assert result == {}  # Empty dict means "every minute"

    def test_cron_to_calendar_interval_invalid(self):
        """Test invalid cron expression."""
        manager = LaunchAgentManager()

        # Invalid (only 4 fields)
        result = manager._cron_to_calendar_interval("0 9 * *")
        assert result is None

    def test_plist_name(self):
        """Test plist naming."""
        manager = LaunchAgentManager()

        assert manager.plist_name("my-workflow") == "com.agentmanager.workflow.my-workflow.plist"
        assert manager.label("my-workflow") == "com.agentmanager.workflow.my-workflow"

    def test_is_enabled_not_exists(self):
        """Test checking if workflow is enabled when plist doesn't exist."""
        with TemporaryDirectory() as tmpdir:
            manager = LaunchAgentManager(launch_agents_dir=Path(tmpdir))

            assert manager.is_enabled("nonexistent") is False

    def test_disable_not_enabled(self):
        """Test disabling a workflow that wasn't enabled."""
        with TemporaryDirectory() as tmpdir:
            manager = LaunchAgentManager(launch_agents_dir=Path(tmpdir))

            result = manager.disable("nonexistent")
            assert result is False

    def test_list_enabled_empty(self):
        """Test listing enabled workflows when none exist."""
        with TemporaryDirectory() as tmpdir:
            manager = LaunchAgentManager(launch_agents_dir=Path(tmpdir))

            assert manager.list_enabled() == []
