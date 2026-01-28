import ArgumentParser
import AgentManagerCore
import Foundation

struct WorkflowEditCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "edit",
        abstract: "Open workflow YAML in editor"
    )

    @Argument(help: "Name of the workflow to edit")
    var name: String

    func run() throws {
        let store = WorkflowStore.shared

        // Check if workflow exists
        guard store.exists(name: name) else {
            throw ValidationError("Workflow '\(name)' not found. Create it with: agentctl workflow create \(name)")
        }

        let workflowPath = store.workflowPath(name: name)

        let editor = ProcessInfo.processInfo.environment["EDITOR"] ?? "vim"
        print("Opening \(workflowPath.path) in \(editor)...")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [editor, workflowPath.path]

        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        try process.run()
        process.waitUntilExit()

        // Validate the edited YAML
        do {
            let workflow = try store.load(name: name)
            try workflow.validate()
            print("Workflow '\(name)' updated successfully.")
        } catch {
            print("Warning: Workflow YAML may be invalid: \(error.localizedDescription)")
            print("Run 'agentctl workflow show \(name)' to check for errors.")
        }
    }
}
