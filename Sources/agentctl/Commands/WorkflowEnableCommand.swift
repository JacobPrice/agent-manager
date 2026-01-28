import ArgumentParser
import AgentManagerCore
import Foundation

struct WorkflowEnableCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "enable",
        abstract: "Enable scheduled workflow execution"
    )

    @Argument(help: "Name of the workflow to enable")
    var name: String

    func run() throws {
        let store = WorkflowStore.shared
        let launchAgent = WorkflowLaunchAgentManager.shared

        // Load and validate workflow
        let workflow = try store.load(name: name)
        try workflow.validate()

        // Check if workflow has schedule triggers
        guard workflow.on.hasSchedule else {
            throw ValidationError("Workflow '\(name)' has no schedule triggers configured.")
        }

        // Check if already enabled
        if launchAgent.isInstalled(workflowName: name) {
            print("Workflow '\(name)' is already enabled.")
            return
        }

        // Install LaunchAgent
        print("Installing LaunchAgent for workflow '\(name)'...")
        try launchAgent.install(workflow: workflow)

        print("Workflow '\(name)' enabled.")
        print("")
        print("Schedule:")
        for schedule in workflow.on.schedule ?? [] {
            print("  - \(schedule.cron)")
        }

        print("")
        print("Disable with: agentctl disable \(name)")
    }
}
