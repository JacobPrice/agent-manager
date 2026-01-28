import ArgumentParser
import AgentManagerCore

struct WorkflowCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "workflow",
        abstract: "Manage workflow orchestrations",
        subcommands: [
            WorkflowListCommand.self,
            WorkflowShowCommand.self,
            WorkflowCreateCommand.self,
            WorkflowEditCommand.self,
            WorkflowDeleteCommand.self,
        ],
        defaultSubcommand: WorkflowListCommand.self
    )
}
