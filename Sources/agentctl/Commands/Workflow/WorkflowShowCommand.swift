import ArgumentParser
import AgentManagerCore
import Foundation

struct WorkflowShowCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show workflow YAML or details"
    )

    @Argument(help: "Name of the workflow to show")
    var name: String

    @Flag(name: .long, help: "Show execution plan instead of YAML")
    var plan = false

    func run() throws {
        let store = WorkflowStore.shared

        // Load workflow
        let workflow = try store.load(name: name)

        if plan {
            // Show execution plan
            let runner = WorkflowRunner.shared
            let report = try runner.dryRunReport(workflowName: name)
            print(report)
        } else {
            // Print YAML
            let yaml = try workflow.toYAML()
            print(yaml)
        }
    }
}
