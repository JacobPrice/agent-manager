# Agent Manager

Workflow orchestration system for local AI agents - like GitHub Actions for AI.

## Installation

```bash
pip install -e .
```

## Usage

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

## Configuration

Workflows and agents are stored in `~/.agent-manager/`:

```
~/.agent-manager/
├── agents/       # Reusable agent templates
├── workflows/    # Workflow definitions
└── runs/         # Execution history
```
