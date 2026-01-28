import Foundation

/// Executes workflow jobs as a directed acyclic graph with parallel execution
public actor DAGExecutor {
    private let workflow: Workflow
    private var workflowRun: WorkflowRun
    private let jobRunner: JobRunner
    private let store: WorkflowStore
    private var guardrails: Guardrails
    private let dryRun: Bool

    /// Callback for job status updates
    public typealias StatusCallback = @Sendable (String, JobStatus) async -> Void
    private var statusCallback: StatusCallback?

    public init(
        workflow: Workflow,
        guardrails: Guardrails? = nil,
        dryRun: Bool = false
    ) {
        self.workflow = workflow
        self.workflowRun = WorkflowRun(
            workflowName: workflow.name,
            jobNames: Array(workflow.jobs.keys),
            isDryRun: dryRun
        )
        self.jobRunner = JobRunner.shared
        self.store = WorkflowStore.shared
        self.dryRun = dryRun

        // Initialize guardrails with workflow-level cost limit
        var g = guardrails ?? Guardrails()
        if g.maxCostUSD == nil {
            g.maxCostUSD = workflow.maxCostUSD
        }
        self.guardrails = g
    }

    /// Set callback for job status updates
    public func setStatusCallback(_ callback: @escaping StatusCallback) {
        self.statusCallback = callback
    }

    /// Get the current workflow run state
    public func getCurrentRun() -> WorkflowRun {
        workflowRun
    }

    /// Execute all jobs in the workflow
    public func execute() async throws -> WorkflowRun {
        workflowRun.markStarted()

        // Save initial state
        try? store.saveRun(workflowRun)

        do {
            // Execute jobs in dependency order with parallelism
            try await executeJobs()

            // Check final status
            if workflowRun.failedJobCount > 0 {
                workflowRun.markFailed(error: "\(workflowRun.failedJobCount) job(s) failed")
            } else {
                workflowRun.markCompleted()
            }
        } catch {
            workflowRun.markFailed(error: error.localizedDescription)
        }

        // Save final state
        try? store.saveRun(workflowRun)

        return workflowRun
    }

    /// Execute jobs respecting dependencies
    private func executeJobs() async throws {
        // Use a task group for parallel execution
        try await withThrowingTaskGroup(of: (String, JobResult).self) { group in
            var pendingJobs = Set(workflow.jobs.keys)
            var runningJobs = Set<String>()

            while !pendingJobs.isEmpty || !runningJobs.isEmpty {
                // Find jobs that are ready to run
                let readyJobs = pendingJobs.filter { jobName in
                    guard let job = workflow.jobs[jobName] else { return false }

                    // Check dependencies are satisfied
                    if let needs = job.needs {
                        for dependency in needs {
                            guard let depResult = workflowRun.jobResults[dependency] else { return false }
                            // Dependency must be completed or skipped
                            guard depResult.status == .completed || depResult.status == .skipped else {
                                return false
                            }
                        }
                    }

                    return true
                }

                // Start ready jobs (up to concurrency limit)
                for jobName in readyJobs {
                    // Check guardrails
                    let canStart = guardrails.canStartJob()
                    guard canStart.isAllowed else {
                        var result = JobResult(jobName: jobName)
                        result.markFailed(error: canStart.reason ?? "Guardrail check failed")
                        workflowRun.updateJobResult(result)
                        pendingJobs.remove(jobName)
                        continue
                    }

                    // Check concurrency limit
                    if runningJobs.count >= guardrails.maxConcurrentJobs {
                        break
                    }

                    pendingJobs.remove(jobName)
                    runningJobs.insert(jobName)

                    // Update status
                    if var result = workflowRun.jobResults[jobName] {
                        result.markStarted()
                        workflowRun.updateJobResult(result)
                    }

                    await statusCallback?(jobName, .running)

                    // Launch job in task group
                    let runCopy = workflowRun
                    let wfCopy = workflow
                    let logDir = store.runLogDirectory(workflowName: workflow.name, runId: workflowRun.id)
                    let isDry = dryRun

                    group.addTask {
                        let result = try self.jobRunner.run(
                            jobName: jobName,
                            workflow: wfCopy,
                            workflowRun: runCopy,
                            logDirectory: logDir,
                            dryRun: isDry
                        )
                        return (jobName, result)
                    }
                }

                // Wait for at least one job to complete
                if !runningJobs.isEmpty {
                    if let (jobName, result) = try await group.next() {
                        runningJobs.remove(jobName)

                        // Record cost
                        if let cost = result.cost {
                            guardrails.recordCost(cost, jobName: jobName)
                        }

                        // Update workflow run
                        workflowRun.updateJobResult(result)
                        try? store.saveRun(workflowRun)

                        await statusCallback?(jobName, result.status)

                        // If job failed, mark dependent jobs as skipped
                        if result.status == .failed {
                            skipDependentJobs(of: jobName, from: &pendingJobs)
                        }
                    }
                }

                // Break if no progress is being made (deadlock prevention)
                if readyJobs.isEmpty && runningJobs.isEmpty && !pendingJobs.isEmpty {
                    // This shouldn't happen if validation passed, but handle it
                    for jobName in pendingJobs {
                        var result = JobResult(jobName: jobName)
                        result.markSkipped(reason: "Dependencies not satisfied")
                        workflowRun.updateJobResult(result)
                    }
                    break
                }
            }
        }
    }

    /// Skip jobs that depend on a failed job
    private func skipDependentJobs(of failedJob: String, from pendingJobs: inout Set<String>) {
        let dependents = workflow.dependents(of: failedJob)

        for dependent in dependents {
            if pendingJobs.contains(dependent) {
                var result = JobResult(jobName: dependent)
                result.markSkipped(reason: "Dependency '\(failedJob)' failed")
                workflowRun.updateJobResult(result)
                pendingJobs.remove(dependent)

                // Recursively skip jobs that depend on this one
                skipDependentJobs(of: dependent, from: &pendingJobs)
            }
        }
    }

    /// Cancel the workflow execution
    public func cancel() {
        workflowRun.markCancelled()

        // Mark all pending jobs as cancelled
        for (_, result) in workflowRun.jobResults where result.status == .pending {
            var updated = result
            updated.markCancelled()
            workflowRun.updateJobResult(updated)
        }

        try? store.saveRun(workflowRun)
    }
}

// MARK: - Synchronous Wrapper

public extension DAGExecutor {
    /// Execute workflow synchronously (for CLI use)
    nonisolated func executeSync() throws -> WorkflowRun {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<WorkflowRun, Error>?

        Task {
            do {
                let run = try await self.execute()
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
            throw DAGExecutorError.executionFailed("Unknown error")
        }
    }
}

// MARK: - DAG Executor Errors

public enum DAGExecutorError: Error, LocalizedError {
    case executionFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .executionFailed(let message):
            return "Workflow execution failed: \(message)"
        case .cancelled:
            return "Workflow execution was cancelled"
        }
    }
}
