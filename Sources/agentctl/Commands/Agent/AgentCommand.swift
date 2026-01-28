import ArgumentParser
import AgentManagerCore

struct AgentCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agent",
        abstract: "Manage reusable agent templates",
        subcommands: [
            AgentListCommand.self,
            AgentShowCommand.self,
            AgentCreateCommand.self,
            AgentEditCommand.self,
            AgentDeleteCommand.self,
        ],
        defaultSubcommand: AgentListCommand.self
    )
}
