import ArgumentParser
import AgentManagerCore
import Foundation

struct WorkflowRunCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Execute a workflow"
    )

    @Argument(help: "Name of the workflow to run")
    var name: String

    @Flag(name: .long, help: "Show what would be executed without running")
    var dryRun = false

    @Option(name: .long, help: "Run only a specific job from the workflow")
    var job: String?

    func run() throws {
        let store = WorkflowStore.shared
        let runner = WorkflowRunner.shared

        // Load and validate workflow
        let workflow = try store.load(name: name)
        try workflow.validate()

        print("Running workflow: \(workflow.name)")
        if dryRun {
            print("(dry run mode)")
        }
        if let jobName = job {
            print("(single job: \(jobName))")
        }
        print("")

        // Show execution plan
        print("Execution plan:")
        let order = try workflow.topologicalSort()
        for (i, jobName) in order.enumerated() {
            let job = workflow.jobs[jobName]!
            let deps = job.needs?.joined(separator: ", ") ?? "none"
            print("  \(i + 1). \(jobName) (depends on: \(deps))")
        }
        print("")

        // Execute
        let result = try runner.runSync(name: name, dryRun: dryRun, singleJob: job)

        // Print summary
        print("")
        print(result.summary())
        print("")

        // Exit with appropriate code
        if result.status == .failed {
            throw ExitCode.failure
        }
    }
}
