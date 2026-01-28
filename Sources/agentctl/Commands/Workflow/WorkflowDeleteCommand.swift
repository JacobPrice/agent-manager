import ArgumentParser
import AgentManagerCore
import Foundation

struct WorkflowDeleteCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Remove a workflow"
    )

    @Argument(help: "Name of the workflow to delete")
    var name: String

    @Flag(name: .shortAndLong, help: "Skip confirmation prompt")
    var force = false

    @Flag(name: .long, help: "Also delete all run history")
    var deleteRuns = false

    func run() throws {
        let store = WorkflowStore.shared
        let launchAgent = WorkflowLaunchAgentManager.shared

        // Check if workflow exists
        guard store.exists(name: name) else {
            throw ValidationError("Workflow '\(name)' not found.")
        }

        // Confirm deletion
        if !force {
            print("This will delete workflow '\(name)' and disable any scheduled runs.")
            if deleteRuns {
                print("All run history will also be deleted.")
            }
            print("Are you sure? [y/N] ", terminator: "")

            guard let response = readLine()?.lowercased(), response == "y" || response == "yes" else {
                print("Cancelled.")
                return
            }
        }

        // Disable LaunchAgent if enabled
        if launchAgent.isInstalled(workflowName: name) {
            print("Removing scheduled runs...")
            try launchAgent.uninstall(workflowName: name)
        }

        // Delete run history if requested
        if deleteRuns {
            print("Deleting run history...")
            let runDir = store.runDirectory(workflowName: name)
            try? FileManager.default.removeItem(at: runDir)
            try? store.deleteWorkflowStats(name: name)
        }

        // Delete workflow
        print("Deleting workflow configuration...")
        try store.delete(name: name)

        print("Workflow '\(name)' deleted.")
    }
}
