import ArgumentParser
import AgentManagerCore

@main
struct AgentCtl: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agentctl",
        abstract: "Manage automated Claude Code agents",
        version: "0.1.0",
        subcommands: [
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
