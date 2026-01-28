import ArgumentParser
import AgentManagerCore
import Foundation

struct WorkflowCreateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new workflow"
    )

    @Argument(help: "Name for the new workflow")
    var name: String

    @Option(name: .shortAndLong, help: "Workflow description")
    var description: String?

    @Flag(name: .long, help: "Open in editor after creating")
    var edit = false

    @Flag(name: .long, help: "Create multi-job template with dependencies")
    var multiJob = false

    @Flag(name: .shortAndLong, help: "Create from template without opening editor")
    var template = false

    func run() throws {
        let store = WorkflowStore.shared

        // Validate name
        guard isValidName(name) else {
            throw ValidationError("Invalid workflow name: '\(name)'. Use only letters, numbers, and hyphens.")
        }

        // Check if workflow already exists
        guard !store.exists(name: name) else {
            throw ValidationError("Workflow '\(name)' already exists. Use 'agentctl workflow edit \(name)' to modify it.")
        }

        // Create template workflow
        var workflow: Workflow
        if multiJob {
            workflow = Workflow.multiJobTemplate(name: name)
        } else {
            workflow = Workflow.template(name: name)
        }

        // Apply description if provided
        if let desc = description {
            workflow = Workflow(
                name: workflow.name,
                description: desc,
                on: workflow.on,
                defaults: workflow.defaults,
                jobs: workflow.jobs,
                maxCostUSD: workflow.maxCostUSD
            )
        }

        // Save the workflow
        try store.save(workflow)

        let workflowPath = store.workflowPath(name: name)
        print("Created workflow '\(name)' at: \(workflowPath.path)")

        if edit || !template {
            print("Opening in editor...")
            try openInEditor(path: workflowPath.path)

            // Validate after editing
            do {
                let edited = try store.load(name: name)
                try edited.validate()
                print("Workflow '\(name)' saved successfully.")
            } catch {
                print("Warning: Workflow may be invalid: \(error.localizedDescription)")
            }
        } else {
            print("Edit with: agentctl workflow edit \(name)")
        }
    }

    private func isValidName(_ name: String) -> Bool {
        let pattern = "^[a-zA-Z][a-zA-Z0-9-]*$"
        return name.range(of: pattern, options: .regularExpression) != nil
    }

    private func openInEditor(path: String) throws {
        let editor = ProcessInfo.processInfo.environment["EDITOR"] ?? "vim"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [editor, path]

        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        try process.run()
        process.waitUntilExit()
    }
}
