"""Workflow management commands."""

from __future__ import annotations

from typing import Annotated

import typer
from rich.console import Console
from rich.table import Table
from rich.tree import Tree

from agent_manager.store.workflow_store import get_workflow_store

app = typer.Typer(help="Manage workflow orchestrations")


@app.command("list")
def list_workflows() -> None:
    """List all workflows."""
    console = Console()
    store = get_workflow_store()

    workflows = store.list_workflow_names()

    if not workflows:
        console.print("No workflows found.")
        console.print("Create one with: agentctl workflow create <name>")
        return

    table = Table(title="Workflows")
    table.add_column("Name", style="cyan")
    table.add_column("Description")
    table.add_column("Jobs")
    table.add_column("Triggers")

    for name in workflows:
        try:
            wf = store.load(name)
            triggers = []
            if wf.on.schedule:
                triggers.append("schedule")
            if wf.on.manual:
                triggers.append("manual")

            table.add_row(
                wf.name,
                (wf.description[:35] + "...") if wf.description and len(wf.description) > 35 else (wf.description or ""),
                str(len(wf.jobs)),
                ", ".join(triggers) or "none",
            )
        except Exception as e:
            table.add_row(name, f"[red]Error: {e}[/red]", "", "")

    console.print(table)


@app.command("show")
def show_workflow(
    name: Annotated[str, typer.Argument(help="Name of the workflow to show")],
    format: Annotated[str, typer.Option("--format", "-f", help="Output format: yaml or tree")] = "yaml",
) -> None:
    """Show workflow details."""
    console = Console()
    store = get_workflow_store()

    if not store.exists(name):
        console.print(f"[red]Error:[/red] Workflow '{name}' not found")
        raise typer.Exit(1)

    if format == "tree":
        wf = store.load(name)
        _show_workflow_tree(console, wf)
    else:
        # Read and print the raw YAML
        workflow_file = store.workflows_directory / f"{name}.yaml"
        console.print(workflow_file.read_text())


def _show_workflow_tree(console: Console, wf) -> None:
    """Show workflow as a dependency tree."""
    tree = Tree(f"[bold cyan]{wf.name}[/bold cyan]")

    if wf.description:
        tree.add(f"[dim]{wf.description}[/dim]")

    # Add triggers
    triggers = tree.add("[bold]Triggers[/bold]")
    if wf.on.schedule:
        for s in wf.on.schedule:
            triggers.add(f"cron: {s.cron}")
    if wf.on.manual:
        triggers.add("manual: true")

    # Add jobs in topological order
    jobs_tree = tree.add("[bold]Jobs[/bold]")
    order = wf.topological_sort()

    for job_name in order:
        job = wf.jobs[job_name]
        job_node = jobs_tree.add(f"[green]{job_name}[/green]")

        if job.agent:
            job_node.add(f"agent: {job.agent}")
        elif job.prompt:
            truncated = job.prompt[:50].replace("\n", " ")
            job_node.add(f"prompt: {truncated}...")

        if job.needs:
            job_node.add(f"needs: {', '.join(job.needs)}")

        if job.if_condition:
            job_node.add(f"if: {job.if_condition}")

        if job.outputs:
            job_node.add(f"outputs: {', '.join(job.outputs)}")

    console.print(tree)


@app.command("create")
def create_workflow(
    name: Annotated[str, typer.Argument(help="Name for the new workflow")],
    description: Annotated[str, typer.Option("--description", "-d", help="Workflow description")] = "",
    edit: Annotated[bool, typer.Option("--edit", "-e", help="Open in editor after creation")] = False,
) -> None:
    """Create a new workflow."""
    import subprocess

    console = Console()
    store = get_workflow_store()

    if store.exists(name):
        console.print(f"[red]Error:[/red] Workflow '{name}' already exists")
        raise typer.Exit(1)

    # Create template YAML
    template = f"""name: {name}
description: {description or "A multi-job workflow"}

on:
  manual: true
  # schedule:
  #   - cron: "0 9 * * 1-5"  # 9am weekdays

defaults:
  working_directory: ~/repos
  max_budget_usd: 0.50
  max_turns: 10

jobs:
  first-job:
    prompt: |
      Describe what this job should do.
    allowed_tools:
      - Read
      - Glob
    outputs:
      - result

  second-job:
    needs: [first-job]
    prompt: |
      Use the result from first-job: ${{{{ jobs.first-job.outputs.result }}}}
    allowed_tools:
      - Read
    # if: ${{{{ jobs.first-job.outputs.result != 'skip' }}}}
"""

    # Save to file
    store.workflows_directory.mkdir(parents=True, exist_ok=True)
    workflow_file = store.workflows_directory / f"{name}.yaml"
    workflow_file.write_text(template)

    console.print(f"[green]Created workflow:[/green] {workflow_file}")

    if edit:
        editor = subprocess.run(["which", "code"], capture_output=True, text=True)
        if editor.returncode == 0:
            subprocess.run(["code", str(workflow_file)])
        else:
            subprocess.run(["open", "-e", str(workflow_file)])


@app.command("edit")
def edit_workflow(
    name: Annotated[str, typer.Argument(help="Name of the workflow to edit")],
) -> None:
    """Edit a workflow in your editor."""
    import subprocess

    console = Console()
    store = get_workflow_store()

    if not store.exists(name):
        console.print(f"[red]Error:[/red] Workflow '{name}' not found")
        raise typer.Exit(1)

    workflow_file = store.workflows_directory / f"{name}.yaml"

    editor = subprocess.run(["which", "code"], capture_output=True, text=True)
    if editor.returncode == 0:
        subprocess.run(["code", str(workflow_file)])
    else:
        subprocess.run(["open", "-e", str(workflow_file)])


@app.command("delete")
def delete_workflow(
    name: Annotated[str, typer.Argument(help="Name of the workflow to delete")],
    force: Annotated[bool, typer.Option("--force", "-f", help="Skip confirmation")] = False,
) -> None:
    """Delete a workflow."""
    console = Console()
    store = get_workflow_store()

    if not store.exists(name):
        console.print(f"[red]Error:[/red] Workflow '{name}' not found")
        raise typer.Exit(1)

    if not force:
        confirm = typer.confirm(f"Delete workflow '{name}'?")
        if not confirm:
            console.print("Cancelled.")
            return

    store.delete(name)
    console.print(f"[green]Deleted workflow:[/green] {name}")


@app.command("validate")
def validate_workflow(
    name: Annotated[str, typer.Argument(help="Name of the workflow to validate")],
) -> None:
    """Validate a workflow YAML."""
    console = Console()
    store = get_workflow_store()

    if not store.exists(name):
        console.print(f"[red]Error:[/red] Workflow '{name}' not found")
        raise typer.Exit(1)

    try:
        wf = store.load(name)
        console.print(f"[green]Valid![/green] Workflow '{wf.name}' loaded successfully")
        console.print(f"  Jobs: {len(wf.jobs)}")

        # Show execution order
        order = wf.topological_sort()
        console.print(f"  Execution order: {' -> '.join(order)}")

        # Check for agents
        for job_name, job in wf.jobs.items():
            if job.agent:
                from agent_manager.store.agent_store import get_agent_store
                agent_store = get_agent_store()
                if not agent_store.exists(job.agent):
                    console.print(f"[yellow]Warning:[/yellow] Job '{job_name}' references missing agent '{job.agent}'")

    except Exception as e:
        console.print(f"[red]Invalid:[/red] {e}")
        raise typer.Exit(1)


@app.command("dry-run")
def dry_run_workflow(
    name: Annotated[str, typer.Argument(help="Name of the workflow to dry run")],
) -> None:
    """Show what would be executed without running."""
    console = Console()
    store = get_workflow_store()

    if not store.exists(name):
        console.print(f"[red]Error:[/red] Workflow '{name}' not found")
        raise typer.Exit(1)

    from agent_manager.execution.workflow_runner import get_workflow_runner

    wf = store.load(name)
    runner = get_workflow_runner()

    report = runner.dry_run_report(wf)
    console.print(report)
