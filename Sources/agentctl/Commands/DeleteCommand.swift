import ArgumentParser
import AgentManagerCore
import Foundation

struct DeleteCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Remove an agent and its schedule"
    )

    @Argument(help: "Name of the agent to delete")
    var name: String

    @Flag(name: .shortAndLong, help: "Skip confirmation prompt")
    var force = false

    @Flag(name: .long, help: "Also delete all log files")
    var deleteLogs = false

    func run() throws {
        let store = AgentStore.shared
        let launchAgent = LaunchAgentManager.shared
        let logManager = LogManager.shared

        // Check if agent exists
        guard store.exists(name: name) else {
            throw ValidationError("Agent '\(name)' not found.")
        }

        // Confirm deletion
        if !force {
            print("This will delete agent '\(name)' and remove any scheduled runs.")
            if deleteLogs {
                print("All log files will also be deleted.")
            }
            print("Are you sure? [y/N] ", terminator: "")

            guard let response = readLine()?.lowercased(), response == "y" || response == "yes" else {
                print("Cancelled.")
                return
            }
        }

        // Disable LaunchAgent if enabled
        if launchAgent.isInstalled(agentName: name) {
            print("Removing scheduled runs...")
            try launchAgent.uninstall(agentName: name)
        }

        // Delete logs if requested
        if deleteLogs {
            print("Deleting log files...")
            try logManager.deleteAllLogs(agentName: name)
        }

        // Delete agent
        print("Deleting agent configuration...")
        try store.delete(name: name)

        print("Agent '\(name)' deleted.")
    }
}
