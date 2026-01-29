"""agentctl - CLI for managing AI agent workflows."""

from __future__ import annotations

from typing import Optional

import typer

from agentctl.commands import agent, workflow

app = typer.Typer(
    name="agentctl",
    help="Manage automated Claude Code agents and workflows",
    no_args_is_help=True,
)

# Add subcommand groups
app.add_typer(agent.app, name="agent", help="Manage reusable agent templates")
app.add_typer(workflow.app, name="workflow", help="Manage workflow orchestrations")


# Top-level commands for common operations
@app.command()
def run(
    name: str = typer.Argument(..., help="Name of the workflow to run"),
    dry_run: bool = typer.Option(False, "--dry-run", help="Show what would be executed"),
    job: Optional[str] = typer.Option(None, "--job", help="Run only a specific job"),
) -> None:
    """Execute a workflow."""
    from rich.console import Console

    from agent_manager.execution.workflow_runner import get_workflow_runner
    from agent_manager.store.workflow_store import get_workflow_store

    console = Console()
    store = get_workflow_store()
    runner = get_workflow_runner()

    # Load workflow
    try:
        wf = store.load(name)
    except Exception as e:
        console.print(f"[red]Error:[/red] {e}")
        raise typer.Exit(1)

    console.print(f"Running workflow: [bold]{wf.name}[/bold]")
    if dry_run:
        console.print("[yellow](dry run mode)[/yellow]")
    if job:
        console.print(f"[yellow](single job: {job})[/yellow]")
    console.print()

    # Show execution plan
    console.print("Execution plan:")
    order = wf.topological_sort()
    for i, job_name in enumerate(order, 1):
        j = wf.jobs[job_name]
        deps = ", ".join(j.needs) if j.needs else "none"
        console.print(f"  {i}. {job_name} (depends on: {deps})")
    console.print()

    # Run with status callback
    def status_callback(job_name: str, status: "JobStatus") -> None:
        from agent_manager.models.result import JobStatus

        icons = {
            JobStatus.PENDING: "○",
            JobStatus.RUNNING: "◐",
            JobStatus.COMPLETED: "●",
            JobStatus.FAILED: "✗",
            JobStatus.SKIPPED: "⊘",
            JobStatus.CANCELLED: "◌",
        }
        console.print(f"  {icons.get(status, '?')} {job_name}: {status.value}")

    result = runner.run_sync(wf, dry_run=dry_run, single_job=job, status_callback=status_callback)

    console.print()
    console.print(result.summary())
    console.print()

    # Show job outputs if any were captured
    has_outputs = any(r.outputs for r in result.job_results.values())
    if has_outputs:
        console.print("[bold]Outputs:[/bold]")
        console.print()
        for job_name, job_result in sorted(result.job_results.items()):
            if not job_result.outputs:
                continue
            console.print(f"  [bold cyan]{job_name}:[/bold cyan]")
            for key, value in job_result.outputs.items():
                # Wrap long values
                if len(value) > 120:
                    console.print(f"    [bold]{key}:[/bold]")
                    # Indent wrapped text
                    for line in value.split("\n"):
                        console.print(f"      {line}")
                else:
                    console.print(f"    [bold]{key}:[/bold] {value}")
            console.print()

    if result.status.value == "failed":
        raise typer.Exit(1)


@app.command()
def status(
    name: str = typer.Argument(..., help="Name of the workflow"),
    limit: int = typer.Option(5, "--limit", "-n", help="Number of recent runs to show"),
    run_id: Optional[str] = typer.Option(None, "--run-id", help="Show details for specific run"),
) -> None:
    """Show recent workflow runs."""
    from rich.console import Console
    from rich.table import Table

    from agent_manager.store.workflow_store import get_workflow_store

    console = Console()
    store = get_workflow_store()

    if not store.exists(name):
        console.print(f"[red]Error:[/red] Workflow '{name}' not found")
        raise typer.Exit(1)

    if run_id:
        # Show specific run
        try:
            run = store.load_run(name, run_id)
            console.print(run.summary())
        except Exception as e:
            console.print(f"[red]Error:[/red] {e}")
            raise typer.Exit(1)
    else:
        # List recent runs
        runs = store.list_runs(name, limit=limit)

        if not runs:
            console.print(f"No runs found for workflow '{name}'")
            console.print(f"Run with: agentctl run {name}")
            return

        table = Table(title=f"Recent runs for '{name}'")
        table.add_column("ID")
        table.add_column("Status")
        table.add_column("Started")
        table.add_column("Duration")
        table.add_column("Cost")
        table.add_column("Jobs")

        for run in runs:
            status_color = {
                "completed": "green",
                "failed": "red",
                "running": "yellow",
                "cancelled": "dim",
            }.get(run.status.value, "")

            duration = f"{run.duration:.1f}s" if run.duration else "running"
            jobs = f"{run.completed_job_count}/{len(run.job_results)}"

            table.add_row(
                run.id[:8],
                f"[{status_color}]{run.status.value}[/{status_color}]",
                run.start_time.strftime("%Y-%m-%d %H:%M"),
                duration,
                f"${run.total_cost:.4f}",
                jobs,
            )

        console.print(table)
        console.print()
        console.print(f"Show details: agentctl status {name} --run-id <id>")


@app.command()
def logs(
    name: str = typer.Argument(..., help="Name of the workflow"),
    run_id: Optional[str] = typer.Option(None, "--run-id", "-r", help="Show logs for specific run"),
    job: Optional[str] = typer.Option(None, "--job", "-j", help="Show logs for specific job"),
    follow: bool = typer.Option(False, "--follow", "-f", help="Follow log output"),
    lines: int = typer.Option(50, "--lines", "-n", help="Number of lines to show"),
) -> None:
    """View workflow execution logs."""
    import subprocess

    from rich.console import Console
    from rich.syntax import Syntax

    from agent_manager.store.workflow_store import get_workflow_store

    console = Console()
    store = get_workflow_store()

    if not store.exists(name):
        console.print(f"[red]Error:[/red] Workflow '{name}' not found")
        raise typer.Exit(1)

    # Determine which run to show logs for
    if run_id:
        # Use specific run ID (supports partial match)
        runs = store.list_runs(name, limit=50)
        matching = [r for r in runs if r.id.startswith(run_id)]
        if not matching:
            console.print(f"[red]Error:[/red] No run found matching '{run_id}'")
            raise typer.Exit(1)
        target_run = matching[0]
    else:
        # Use most recent run
        target_run = store.load_last_run(name)
        if not target_run:
            console.print(f"No runs found for workflow '{name}'")
            console.print(f"Run with: agentctl run {name}")
            return

    log_dir = store.run_log_directory(name, target_run.id)

    if job:
        # Show logs for specific job
        log_file = log_dir / f"{job}.log"
        if not log_file.exists():
            console.print(f"[red]Error:[/red] No log file found for job '{job}'")
            console.print(f"Available jobs: {', '.join(target_run.job_results.keys())}")
            raise typer.Exit(1)

        if follow:
            # Use tail -f for following
            subprocess.run(["tail", "-f", str(log_file)])
        else:
            content = log_file.read_text()
            log_lines = content.split("\n")
            if len(log_lines) > lines:
                log_lines = log_lines[-lines:]
            console.print(Syntax("\n".join(log_lines), "text", theme="monokai"))
    else:
        # Show logs for all jobs
        console.print(f"[bold]Run:[/bold] {target_run.id[:8]}")
        console.print(f"[bold]Status:[/bold] {target_run.status.value}")
        console.print()

        for job_name, result in sorted(target_run.job_results.items()):
            log_file = log_dir / f"{job_name}.log"

            console.print(f"[bold cyan]── {job_name} ──[/bold cyan]")
            console.print(f"Status: {result.status.value}")

            if result.claude_output:
                # Show Claude's output (truncated)
                output = result.claude_output
                if len(output) > 500:
                    output = output[:500] + "\n... (truncated)"
                console.print(output)

            if log_file.exists():
                console.print(f"[dim]Log file: {log_file}[/dim]")

            console.print()


@app.command()
def enable(
    name: str = typer.Argument(..., help="Name of the workflow to enable"),
) -> None:
    """Enable scheduled execution for a workflow."""
    from rich.console import Console

    from agent_manager.scheduling import get_launch_agent_manager
    from agent_manager.store.workflow_store import get_workflow_store

    console = Console()
    store = get_workflow_store()
    manager = get_launch_agent_manager()

    # Load workflow
    try:
        wf = store.load(name)
    except Exception as e:
        console.print(f"[red]Error:[/red] {e}")
        raise typer.Exit(1)

    # Check for schedule triggers
    if not wf.on.schedule:
        console.print(f"[red]Error:[/red] Workflow '{name}' has no schedule defined")
        console.print("Add a schedule to the workflow's 'on:' section:")
        console.print("  on:")
        console.print("    schedule:")
        console.print('      - cron: "0 9 * * *"  # 9am daily')
        raise typer.Exit(1)

    # Extract cron expressions
    cron_schedules = [s.cron for s in wf.on.schedule]

    # Enable scheduling
    try:
        plist_path = manager.enable(name, cron_schedules)
        console.print(f"[green]Enabled scheduling for '{name}'[/green]")
        console.print(f"Schedule(s): {', '.join(cron_schedules)}")
        console.print(f"LaunchAgent: {plist_path}")
        console.print()
        console.print("View scheduled runs: agentctl status " + name)
        console.print("Disable with: agentctl disable " + name)
    except Exception as e:
        console.print(f"[red]Error:[/red] Failed to enable scheduling: {e}")
        raise typer.Exit(1)


@app.command()
def disable(
    name: str = typer.Argument(..., help="Name of the workflow to disable"),
) -> None:
    """Disable scheduled execution for a workflow."""
    from rich.console import Console

    from agent_manager.scheduling import get_launch_agent_manager
    from agent_manager.store.workflow_store import get_workflow_store

    console = Console()
    store = get_workflow_store()
    manager = get_launch_agent_manager()

    if not store.exists(name):
        console.print(f"[red]Error:[/red] Workflow '{name}' not found")
        raise typer.Exit(1)

    if manager.disable(name):
        console.print(f"[green]Disabled scheduling for '{name}'[/green]")
    else:
        console.print(f"Workflow '{name}' was not enabled")


@app.command()
def schedule(
    name: Optional[str] = typer.Argument(None, help="Workflow name (omit to list all)"),
) -> None:
    """Show scheduling status for workflows."""
    from rich.console import Console
    from rich.table import Table

    from agent_manager.scheduling import get_launch_agent_manager
    from agent_manager.store.workflow_store import get_workflow_store

    console = Console()
    store = get_workflow_store()
    manager = get_launch_agent_manager()

    if name:
        # Show details for specific workflow
        try:
            wf = store.load(name)
        except Exception as e:
            console.print(f"[red]Error:[/red] {e}")
            raise typer.Exit(1)

        is_enabled = manager.is_enabled(name)
        plist_path = manager.plist_path(name)

        console.print(f"[bold]Workflow:[/bold] {name}")
        console.print(f"[bold]Enabled:[/bold] {'Yes' if is_enabled else 'No'}")

        if wf.on.schedule:
            console.print(f"[bold]Schedule(s):[/bold]")
            for s in wf.on.schedule:
                console.print(f"  - {s.cron}")
        else:
            console.print("[bold]Schedule:[/bold] Not configured")

        if is_enabled:
            console.print(f"[bold]LaunchAgent:[/bold] {plist_path}")
    else:
        # List all workflows with schedule status
        workflows = store.list_workflow_names()

        if not workflows:
            console.print("No workflows found.")
            return

        table = Table(title="Workflow Schedules")
        table.add_column("Workflow", style="cyan")
        table.add_column("Schedule")
        table.add_column("Enabled")

        for wf_name in workflows:
            try:
                wf = store.load(wf_name)
                is_enabled = manager.is_enabled(wf_name)

                if wf.on.schedule:
                    schedules = ", ".join(s.cron for s in wf.on.schedule)
                else:
                    schedules = "[dim]none[/dim]"

                enabled_str = "[green]Yes[/green]" if is_enabled else "[dim]No[/dim]"

                table.add_row(wf_name, schedules, enabled_str)
            except Exception:
                table.add_row(wf_name, "[red]error[/red]", "")

        console.print(table)
        console.print()
        console.print("Enable: agentctl enable <workflow>")
        console.print("Disable: agentctl disable <workflow>")


@app.command()
def version() -> None:
    """Show version information."""
    from agent_manager import __version__

    typer.echo(f"agentctl version {__version__}")


def main() -> None:
    """Entry point for the CLI."""
    app()


if __name__ == "__main__":
    main()
