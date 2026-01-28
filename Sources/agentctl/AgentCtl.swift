import ArgumentParser
import AgentManagerCore

@main
struct AgentCtl: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agentctl",
        abstract: "Manage automated Claude Code agents and workflows",
        version: "0.2.0",
        subcommands: [
            // Primary workflow commands
            WorkflowRunCommand.self,
            StatusCommand.self,
            WorkflowLogsCommand.self,
            WorkflowEnableCommand.self,
            WorkflowDisableCommand.self,

            // Subcommand groups
            AgentCommand.self,
            WorkflowCommand.self,

            // Legacy agent commands (deprecated but kept for compatibility)
            ListCommand.self,
            ShowCommand.self,
            CreateCommand.self,
            EditCommand.self,
            DeleteCommand.self,
            RunCommand.self,
            EnableCommand.self,
            DisableCommand.self,
            LogsCommand.self,
        ],
        defaultSubcommand: ListCommand.self
    )
}
