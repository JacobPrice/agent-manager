# Agent Manager

A macOS CLI tool for creating and managing automated Claude Code agents.

## Installation

```bash
# Clone and build
cd ~/repos/agent-manager
swift build -c release

# Install to ~/.local/bin
mkdir -p ~/.local/bin
cp .build/release/agentctl ~/.local/bin/

# Ensure ~/.local/bin is in your PATH
```

## Quick Start

```bash
# Create a new agent
agentctl create my-agent

# List all agents
agentctl list

# Run an agent manually
agentctl run my-agent

# Enable scheduled runs (for schedule-type agents)
agentctl enable my-agent
```

## Commands

| Command | Description |
|---------|-------------|
| `agentctl list` | List all agents with status |
| `agentctl show <name>` | Display agent configuration |
| `agentctl create <name>` | Create new agent interactively |
| `agentctl edit <name>` | Open agent YAML in $EDITOR |
| `agentctl delete <name>` | Remove agent and its schedule |
| `agentctl run <name> [--dry-run]` | Execute agent manually |
| `agentctl enable <name>` | Install LaunchAgent (activate schedule) |
| `agentctl disable <name>` | Remove LaunchAgent (deactivate) |
| `agentctl logs <name> [-f] [-n N]` | View agent run logs |

## Agent Definition Format

Agents are defined as YAML files in `~/.agent-manager/agents/`:

```yaml
name: dotfiles-sync
description: Sync and document dotfiles changes

trigger:
  type: schedule  # schedule | manual
  hour: 9
  minute: 0

working_directory: ~/repos/.dotfiles

context_script: |
  echo "Current state:"
  git status
  git diff --stat

prompt: |
  You are a dotfiles agent. Analyze the changes and...

allowed_tools:
  - Read
  - Edit
  - Write
  - "Bash(git *)"

max_turns: 10
max_budget_usd: 1.00
```

### Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Unique identifier for the agent |
| `description` | Yes | Brief description of what the agent does |
| `trigger.type` | Yes | `schedule` or `manual` |
| `trigger.hour` | For schedule | Hour to run (0-23) |
| `trigger.minute` | For schedule | Minute to run (0-59) |
| `working_directory` | Yes | Directory where the agent runs |
| `context_script` | No | Shell script to gather context before running |
| `prompt` | Yes | The prompt sent to Claude |
| `allowed_tools` | Yes | List of Claude Code tools the agent can use |
| `max_turns` | No | Maximum agentic turns (default: 10) |
| `max_budget_usd` | No | Maximum cost per run (default: 1.00) |

### Allowed Tools Examples

```yaml
allowed_tools:
  - Read                    # Read any file
  - Edit                    # Edit any file
  - Write                   # Write any file
  - "Bash(git *)"          # Git commands only
  - "Bash(npm test)"       # Specific command
  - "Bash(chezmoi *)"      # Chezmoi commands
```

## Directory Structure

```
~/.agent-manager/
├── agents/                    # Agent YAML definitions
│   ├── dotfiles-sync.yaml
│   └── weekly-review.yaml
├── logs/                      # Run logs organized by agent
│   └── dotfiles-sync/
│       ├── 2026-01-25-090000.log
│       └── 2026-01-26-090000.log
└── config.yaml                # Global settings (optional)
```

## Scheduling with LaunchAgent

When you run `agentctl enable <name>`, a LaunchAgent plist is installed to `~/Library/LaunchAgents/` that runs the agent at the scheduled time.

```bash
# Enable scheduling
agentctl enable dotfiles-sync

# Verify it's loaded
launchctl list | grep agentmanager

# Disable scheduling
agentctl disable dotfiles-sync
```

## Examples

### Daily Code Review Agent

```yaml
name: daily-review
description: Review uncommitted changes each morning

trigger:
  type: schedule
  hour: 8
  minute: 30

working_directory: ~/repos/my-project

context_script: |
  echo "=== Uncommitted Changes ==="
  git diff
  echo ""
  echo "=== Untracked Files ==="
  git status --porcelain | grep "^??"

prompt: |
  Review the uncommitted changes shown above. For each change:
  1. Check for potential bugs or issues
  2. Suggest improvements if any
  3. Note if anything looks incomplete

  If everything looks good, just say so briefly.

allowed_tools:
  - Read

max_turns: 5
max_budget_usd: 0.50
```

### Weekly Dependency Update Agent

```yaml
name: deps-update
description: Check and update dependencies weekly

trigger:
  type: schedule
  hour: 10
  minute: 0

working_directory: ~/repos/my-project

context_script: |
  echo "=== Outdated Packages ==="
  npm outdated 2>/dev/null || true
  echo ""
  echo "=== Security Audit ==="
  npm audit 2>/dev/null || true

prompt: |
  Review the outdated packages and security audit above.

  For minor/patch updates with no security issues, update them.
  For major updates or security issues, document them but don't update.

  After making changes, run tests to verify nothing broke.

allowed_tools:
  - Read
  - Edit
  - Write
  - "Bash(npm *)"
  - "Bash(git *)"

max_turns: 15
max_budget_usd: 2.00
```

### Manual Documentation Agent

```yaml
name: update-docs
description: Update documentation based on code changes

trigger:
  type: manual

working_directory: ~/repos/my-project

context_script: |
  echo "=== Recent Commits ==="
  git log --oneline -10
  echo ""
  echo "=== Changed Files ==="
  git diff --name-only HEAD~10

prompt: |
  Review the recent changes and update the documentation accordingly.
  Focus on:
  - README.md for user-facing changes
  - Code comments for complex logic
  - API docs for interface changes

allowed_tools:
  - Read
  - Edit
  - Write
  - "Bash(git diff *)"

max_turns: 10
max_budget_usd: 1.00
```

## Viewing Logs

```bash
# View latest log
agentctl logs my-agent

# List all logs
agentctl logs my-agent --list

# View specific log by index (1 = most recent)
agentctl logs my-agent --index 2

# Show only last N lines
agentctl logs my-agent -n 50

# Follow log output (like tail -f)
agentctl logs my-agent -f
```

## Development

```bash
# Build debug version
swift build

# Run directly
.build/debug/agentctl list

# Run tests
swift test

# Build release
swift build -c release
```

## License

MIT
