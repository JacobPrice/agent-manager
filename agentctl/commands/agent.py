"""Agent template management commands."""

from __future__ import annotations

from typing import Annotated

import typer
from rich.console import Console
from rich.table import Table

from agent_manager.store.agent_store import get_agent_store

app = typer.Typer(help="Manage reusable agent templates")


@app.command("list")
def list_agents() -> None:
    """List all agent templates."""
    console = Console()
    store = get_agent_store()

    agents = store.list_agent_names()

    if not agents:
        console.print("No agents found.")
        console.print("Create one with: agentctl agent create <name>")
        return

    table = Table(title="Agent Templates")
    table.add_column("Name", style="cyan")
    table.add_column("Description")
    table.add_column("Working Dir")
    table.add_column("Max Budget")
    table.add_column("Max Turns")

    for name in agents:
        try:
            agent = store.load(name)
            table.add_row(
                agent.name,
                agent.description[:40] + "..." if len(agent.description) > 40 else agent.description,
                agent.working_directory,
                f"${agent.max_budget_usd:.2f}",
                str(agent.max_turns),
            )
        except Exception as e:
            table.add_row(name, f"[red]Error: {e}[/red]", "", "", "")

    console.print(table)


@app.command("show")
def show_agent(
    name: Annotated[str, typer.Argument(help="Name of the agent to show")],
) -> None:
    """Show agent template details."""
    console = Console()
    store = get_agent_store()

    if not store.exists(name):
        console.print(f"[red]Error:[/red] Agent '{name}' not found")
        raise typer.Exit(1)

    # Read and print the raw YAML
    agent_file = store.agents_directory / f"{name}.yaml"
    console.print(agent_file.read_text())


@app.command("create")
def create_agent(
    name: Annotated[str, typer.Argument(help="Name for the new agent")],
    description: Annotated[str, typer.Option("--description", "-d", help="Agent description")] = "A reusable agent template",
    working_dir: Annotated[str, typer.Option("--working-dir", "-w", help="Working directory")] = "~/repos",
    max_budget: Annotated[float, typer.Option("--max-budget", "-b", help="Maximum budget in USD")] = 0.50,
    max_turns: Annotated[int, typer.Option("--max-turns", "-t", help="Maximum turns")] = 10,
    edit: Annotated[bool, typer.Option("--edit", "-e", help="Open in editor after creation")] = False,
) -> None:
    """Create a new agent template."""
    import subprocess

    console = Console()
    store = get_agent_store()

    if store.exists(name):
        console.print(f"[red]Error:[/red] Agent '{name}' already exists")
        raise typer.Exit(1)

    # Create template YAML
    template = f"""name: {name}
description: {description}

prompt: |
  Your task instructions go here.
  Be specific about what the agent should do.

working_directory: {working_dir}
allowed_tools:
  - Read
  - Glob
  - Grep

max_turns: {max_turns}
max_budget_usd: {max_budget}
"""

    # Save to file
    store.agents_directory.mkdir(parents=True, exist_ok=True)
    agent_file = store.agents_directory / f"{name}.yaml"
    agent_file.write_text(template)

    console.print(f"[green]Created agent template:[/green] {agent_file}")

    if edit:
        editor = subprocess.run(["which", "code"], capture_output=True, text=True)
        if editor.returncode == 0:
            subprocess.run(["code", str(agent_file)])
        else:
            subprocess.run(["open", "-e", str(agent_file)])


@app.command("edit")
def edit_agent(
    name: Annotated[str, typer.Argument(help="Name of the agent to edit")],
) -> None:
    """Edit an agent template in your editor."""
    import subprocess

    console = Console()
    store = get_agent_store()

    if not store.exists(name):
        console.print(f"[red]Error:[/red] Agent '{name}' not found")
        raise typer.Exit(1)

    agent_file = store.agents_directory / f"{name}.yaml"

    editor = subprocess.run(["which", "code"], capture_output=True, text=True)
    if editor.returncode == 0:
        subprocess.run(["code", str(agent_file)])
    else:
        subprocess.run(["open", "-e", str(agent_file)])


@app.command("delete")
def delete_agent(
    name: Annotated[str, typer.Argument(help="Name of the agent to delete")],
    force: Annotated[bool, typer.Option("--force", "-f", help="Skip confirmation")] = False,
) -> None:
    """Delete an agent template."""
    console = Console()
    store = get_agent_store()

    if not store.exists(name):
        console.print(f"[red]Error:[/red] Agent '{name}' not found")
        raise typer.Exit(1)

    if not force:
        confirm = typer.confirm(f"Delete agent '{name}'?")
        if not confirm:
            console.print("Cancelled.")
            return

    store.delete(name)
    console.print(f"[green]Deleted agent:[/green] {name}")


@app.command("validate")
def validate_agent(
    name: Annotated[str, typer.Argument(help="Name of the agent to validate")],
) -> None:
    """Validate an agent template YAML."""
    console = Console()
    store = get_agent_store()

    if not store.exists(name):
        console.print(f"[red]Error:[/red] Agent '{name}' not found")
        raise typer.Exit(1)

    try:
        agent = store.load(name)
        console.print(f"[green]Valid![/green] Agent '{agent.name}' loaded successfully")
        console.print(f"  Description: {agent.description}")
        console.print(f"  Working dir: {agent.working_directory}")
        console.print(f"  Max budget: ${agent.max_budget_usd:.2f}")
        console.print(f"  Max turns: {agent.max_turns}")
        console.print(f"  Allowed tools: {', '.join(agent.allowed_tools)}")
    except Exception as e:
        console.print(f"[red]Invalid:[/red] {e}")
        raise typer.Exit(1)
