import Foundation

/// Main entry point for executing workflows
public struct WorkflowRunner {
    public static let shared = WorkflowRunner()

    private let store = WorkflowStore.shared

    public init() {}

    /// Run a workflow by name
    /// - Parameters:
    ///   - name: The workflow name
    ///   - dryRun: If true, show what would be executed without running
    ///   - singleJob: If specified, only run this single job
    ///   - statusCallback: Optional callback for status updates
    /// - Returns: The workflow run result
    public func run(
        name: String,
        dryRun: Bool = false,
        singleJob: String? = nil,
        statusCallback: DAGExecutor.StatusCallback? = nil
    ) async throws -> WorkflowRun {
        // Load workflow
        let workflow = try store.load(name: name)

        // Validate workflow
        try workflow.validate()

        // Check if running single job
        if let jobName = singleJob {
            return try await runSingleJob(jobName: jobName, workflow: workflow, dryRun: dryRun)
        }

        // Run full workflow
        return try await runWorkflow(workflow, dryRun: dryRun, statusCallback: statusCallback)
    }

    /// Run a workflow
    public func run(
        workflow: Workflow,
        dryRun: Bool = false,
        statusCallback: DAGExecutor.StatusCallback? = nil
    ) async throws -> WorkflowRun {
        try workflow.validate()
        return try await runWorkflow(workflow, dryRun: dryRun, statusCallback: statusCallback)
    }

    /// Run a workflow with full DAG execution
    private func runWorkflow(
        _ workflow: Workflow,
        dryRun: Bool,
        statusCallback: DAGExecutor.StatusCallback?
    ) async throws -> WorkflowRun {
        // Create guardrails from workflow config
        let guardrails = Guardrails(
            maxCostUSD: workflow.maxCostUSD,
            maxTurnsPerJob: workflow.defaults?.maxTurns ?? 10,
            maxConcurrentJobs: 4
        )

        // Create executor
        let executor = DAGExecutor(
            workflow: workflow,
            guardrails: guardrails,
            dryRun: dryRun
        )

        // Set status callback if provided
        if let callback = statusCallback {
            await executor.setStatusCallback(callback)
        }

        // Execute
        let run = try await executor.execute()

        // Prune old runs
        try? store.pruneRuns(workflowName: workflow.name)

        return run
    }

    /// Run a single job from a workflow (for testing/debugging)
    private func runSingleJob(
        jobName: String,
        workflow: Workflow,
        dryRun: Bool
    ) async throws -> WorkflowRun {
        guard let job = workflow.jobs[jobName] else {
            throw WorkflowRunnerError.jobNotFound(jobName)
        }

        // Check if job has dependencies that need to be run first
        if let needs = job.needs, !needs.isEmpty {
            print("Warning: Job '\(jobName)' has dependencies: \(needs.joined(separator: ", "))")
            print("Running without dependency outputs - conditionals may not evaluate correctly.")
        }

        // Create a workflow run for just this job
        var run = WorkflowRun(
            workflowName: workflow.name,
            jobNames: [jobName],
            isDryRun: dryRun
        )
        run.markStarted()

        // Run the job
        let logDir = store.runLogDirectory(workflowName: workflow.name, runId: run.id)
        let context = ExpressionEvaluator.Context()

        let result = try JobRunner.shared.run(
            jobName: jobName,
            job: job,
            workflow: workflow,
            context: context,
            logDirectory: logDir,
            dryRun: dryRun
        )

        run.updateJobResult(result)

        if result.status == .failed {
            run.markFailed(error: result.errorMessage ?? "Job failed")
        } else {
            run.markCompleted()
        }

        try? store.saveRun(run)
        return run
    }

    /// Run a workflow synchronously (for CLI use)
    public func runSync(
        name: String,
        dryRun: Bool = false,
        singleJob: String? = nil
    ) throws -> WorkflowRun {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<WorkflowRun, Error>?

        Task {
            do {
                let run = try await self.run(name: name, dryRun: dryRun, singleJob: singleJob)
                result = .success(run)
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }

        semaphore.wait()

        switch result {
        case .success(let run):
            return run
        case .failure(let error):
            throw error
        case .none:
            throw WorkflowRunnerError.executionFailed("Unknown error")
        }
    }

    /// List recent runs for a workflow
    public func listRuns(workflowName: String, limit: Int = 10) throws -> [WorkflowRun] {
        try store.listRuns(workflowName: workflowName, limit: limit)
    }

    /// Get the most recent run for a workflow
    public func lastRun(workflowName: String) throws -> WorkflowRun? {
        try store.loadLastRun(workflowName: workflowName)
    }

    /// Get a specific run by ID
    public func getRun(workflowName: String, runId: String) throws -> WorkflowRun {
        try store.loadRun(workflowName: workflowName, runId: runId)
    }
}

// MARK: - Dry Run Support

public extension WorkflowRunner {
    /// Generate a dry run report showing what would be executed
    func dryRunReport(workflowName: String) throws -> String {
        let workflow = try store.load(name: workflowName)
        try workflow.validate()

        var report: [String] = []

        report.append("Workflow: \(workflow.name)")
        if let desc = workflow.description {
            report.append("Description: \(desc)")
        }
        report.append("")
        report.append("Jobs (\(workflow.jobs.count) total):")
        report.append("")

        // Get topological order
        let order = try workflow.topologicalSort()

        for (index, jobName) in order.enumerated() {
            guard let job = workflow.jobs[jobName] else { continue }

            report.append("\(index + 1). \(jobName)")

            if let agent = job.agent {
                report.append("   Agent: \(agent)")
            } else if let prompt = job.prompt {
                let truncated = prompt.count > 50 ? String(prompt.prefix(50)) + "..." : prompt
                report.append("   Prompt: \(truncated)")
            }

            if let needs = job.needs, !needs.isEmpty {
                report.append("   Depends on: \(needs.joined(separator: ", "))")
            }

            if let condition = job.if {
                report.append("   Condition: \(condition)")
            }

            if let outputs = job.outputs, !outputs.isEmpty {
                report.append("   Outputs: \(outputs.joined(separator: ", "))")
            }

            report.append("   Max budget: $\(String(format: "%.2f", workflow.maxBudget(for: jobName)))")
            report.append("   Max turns: \(workflow.maxTurns(for: jobName))")
            report.append("")
        }

        // Show execution plan
        report.append("Execution Plan:")
        report.append("  Root jobs (can start immediately): \(workflow.rootJobs().joined(separator: ", "))")

        if let maxCost = workflow.maxCostUSD {
            report.append("  Maximum workflow cost: $\(String(format: "%.2f", maxCost))")
        }

        return report.joined(separator: "\n")
    }
}

// MARK: - Workflow Runner Errors

public enum WorkflowRunnerError: Error, LocalizedError {
    case workflowNotFound(String)
    case jobNotFound(String)
    case executionFailed(String)
    case validationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .workflowNotFound(let name):
            return "Workflow '\(name)' not found"
        case .jobNotFound(let name):
            return "Job '\(name)' not found"
        case .executionFailed(let message):
            return "Workflow execution failed: \(message)"
        case .validationFailed(let message):
            return "Workflow validation failed: \(message)"
        }
    }
}
