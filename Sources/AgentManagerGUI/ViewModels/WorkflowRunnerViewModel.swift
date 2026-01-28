import SwiftUI
import AgentManagerCore

@MainActor
class WorkflowRunnerViewModel: ObservableObject {
    @Published var isRunning = false
    @Published var isDryRun = false
    @Published var workflowRun: WorkflowRun?
    @Published var outputLines: [String] = []
    @Published var errorMessage: String?
    @Published var jobStatuses: [String: JobStatus] = [:]

    private var runTask: Task<Void, Never>?

    func run(workflow: Workflow) {
        guard !isRunning else { return }

        isRunning = true
        errorMessage = nil
        outputLines = []
        workflowRun = nil

        // Initialize job statuses
        jobStatuses = [:]
        for jobName in workflow.jobs.keys {
            jobStatuses[jobName] = .pending
        }

        runTask = Task {
            do {
                outputLines.append("Starting workflow: \(workflow.name)")
                if isDryRun {
                    outputLines.append("(dry run mode)")
                }
                outputLines.append("")

                // Show execution order
                let order = try workflow.topologicalSort()
                outputLines.append("Execution order:")
                for (i, jobName) in order.enumerated() {
                    let job = workflow.jobs[jobName]!
                    let deps = job.needs?.joined(separator: ", ") ?? "none"
                    outputLines.append("  \(i + 1). \(jobName) (depends on: \(deps))")
                }
                outputLines.append("")

                // Run workflow
                let result = try await WorkflowRunner.shared.run(
                    workflow: workflow,
                    dryRun: isDryRun,
                    statusCallback: { [weak self] jobName, status in
                        await MainActor.run {
                            self?.jobStatuses[jobName] = status
                            self?.outputLines.append("Job '\(jobName)': \(status.rawValue)")
                        }
                    }
                )

                workflowRun = result
                outputLines.append("")
                outputLines.append(result.summary())

                if result.status == .failed {
                    errorMessage = result.errorMessage
                }

            } catch {
                errorMessage = error.localizedDescription
                outputLines.append("Error: \(error.localizedDescription)")
            }

            isRunning = false
        }
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
        isRunning = false
        outputLines.append("Workflow cancelled by user")
    }

    func clear() {
        outputLines = []
        workflowRun = nil
        errorMessage = nil
        jobStatuses = [:]
    }
}
