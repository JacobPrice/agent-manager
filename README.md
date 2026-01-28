# Agent Manager

Workflow orchestration system for local AI agents - like GitHub Actions for AI.

## Installation

```bash
pip install -e .
```

## Quick Start

```bash
# List workflows
agentctl workflow list

# Create a new workflow
agentctl workflow create my-workflow

# Run a workflow
agentctl run my-workflow

# View run status
agentctl status my-workflow
```

## Concepts

- **Agent**: Reusable prompt template with default settings
- **Workflow**: Executable orchestration with multiple jobs
- **Job**: Single execution unit within a workflow
- **Run**: A specific execution of a workflow

## Commands

| Command | Description |
|---------|-------------|
| `agentctl workflow list` | List all workflows |
| `agentctl workflow create <name>` | Create a new workflow |
| `agentctl workflow show <name>` | Show workflow details |
| `agentctl workflow delete <name>` | Delete a workflow |
| `agentctl run <name>` | Execute a workflow |
| `agentctl status <name>` | View run status |
| `agentctl agent list` | List all agents |
| `agentctl agent create <name>` | Create a new agent |
| `agentctl agent show <name>` | Show agent details |
| `agentctl agent delete <name>` | Delete an agent |

## Configuration

Workflows and agents are stored in `~/.agent-manager/`:

```
~/.agent-manager/
├── agents/       # Reusable agent templates
├── workflows/    # Workflow definitions
└── runs/         # Execution history
```

## Development

```bash
# Install in development mode
pip install -e ".[dev]"

# Run tests
pytest

# Lint
ruff check .

# Type check
mypy .
```

## Legacy

The original Swift implementation (CLI + SwiftUI GUI) is preserved on the `legacy/swift` branch.

## License

MIT
