import ArgumentParser
import AgentManagerCore
import Foundation

struct WorkflowDisableCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "disable",
        abstract: "Disable scheduled workflow execution"
    )

    @Argument(help: "Name of the workflow to disable")
    var name: String

    func run() throws {
        let store = WorkflowStore.shared
        let launchAgent = WorkflowLaunchAgentManager.shared

        // Check workflow exists
        guard store.exists(name: name) else {
            throw ValidationError("Workflow '\(name)' not found.")
        }

        // Check if currently enabled
        guard launchAgent.isInstalled(workflowName: name) else {
            print("Workflow '\(name)' is not currently enabled.")
            return
        }

        // Uninstall LaunchAgent
        print("Removing LaunchAgent for workflow '\(name)'...")
        try launchAgent.uninstall(workflowName: name)

        print("Workflow '\(name)' disabled.")
        print("")
        print("Re-enable with: agentctl enable \(name)")
    }
}
