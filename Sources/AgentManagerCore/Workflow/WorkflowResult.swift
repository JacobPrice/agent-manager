import Foundation

// MARK: - Status Enums

public enum WorkflowStatus: String, Codable {
    case pending
    case running
    case completed
    case failed
    case cancelled
}

public enum JobStatus: String, Codable {
    case pending
    case running
    case completed
    case failed
    case skipped
    case cancelled
}

// MARK: - Job Result

public struct JobResult: Codable {
    public let jobName: String
    public var status: JobStatus
    public var outputs: [String: String]
    public var startTime: Date?
    public var endTime: Date?
    public var cost: Double?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var errorMessage: String?
    public var logFile: URL?
    public var claudeOutput: String?

    public init(jobName: String) {
        self.jobName = jobName
        self.status = .pending
        self.outputs = [:]
    }

    enum CodingKeys: String, CodingKey {
        case jobName = "job_name"
        case status
        case outputs
        case startTime = "start_time"
        case endTime = "end_time"
        case cost
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case errorMessage = "error_message"
        case logFile = "log_file"
        case claudeOutput = "claude_output"
    }

    /// Duration of the job execution
    public var duration: TimeInterval? {
        guard let start = startTime, let end = endTime else { return nil }
        return end.timeIntervalSince(start)
    }

    /// Total tokens used (input + output)
    public var totalTokens: Int? {
        guard let input = inputTokens, let output = outputTokens else { return nil }
        return input + output
    }

    /// Check if the job has completed (successfully or with failure)
    public var isFinished: Bool {
        switch status {
        case .completed, .failed, .skipped, .cancelled:
            return true
        case .pending, .running:
            return false
        }
    }

    /// Check if the job was successful
    public var isSuccessful: Bool {
        status == .completed
    }

    /// Mark the job as started
    public mutating func markStarted() {
        status = .running
        startTime = Date()
    }

    /// Mark the job as completed with outputs
    public mutating func markCompleted(outputs: [String: String] = [:], claudeOutput: String? = nil) {
        status = .completed
        endTime = Date()
        self.outputs = outputs
        self.claudeOutput = claudeOutput
    }

    /// Mark the job as failed
    public mutating func markFailed(error: String) {
        status = .failed
        endTime = Date()
        errorMessage = error
    }

    /// Mark the job as skipped (due to condition not met)
    public mutating func markSkipped(reason: String? = nil) {
        status = .skipped
        endTime = Date()
        if let reason = reason {
            errorMessage = "Skipped: \(reason)"
        }
    }

    /// Mark the job as cancelled
    public mutating func markCancelled() {
        status = .cancelled
        endTime = Date()
    }

    /// Update token and cost information
    public mutating func updateStats(inputTokens: Int?, outputTokens: Int?, cost: Double?) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cost = cost
    }
}

// MARK: - Workflow Run

public struct WorkflowRun: Codable {
    public let id: String
    public let workflowName: String
    public var status: WorkflowStatus
    public var jobResults: [String: JobResult]
    public var startTime: Date
    public var endTime: Date?
    public var errorMessage: String?
    public var isDryRun: Bool

    public init(workflowName: String, jobNames: [String], isDryRun: Bool = false) {
        self.id = UUID().uuidString
        self.workflowName = workflowName
        self.status = .pending
        self.startTime = Date()
        self.isDryRun = isDryRun

        // Initialize all jobs as pending
        var results: [String: JobResult] = [:]
        for name in jobNames {
            results[name] = JobResult(jobName: name)
        }
        self.jobResults = results
    }

    enum CodingKeys: String, CodingKey {
        case id
        case workflowName = "workflow_name"
        case status
        case jobResults = "job_results"
        case startTime = "start_time"
        case endTime = "end_time"
        case errorMessage = "error_message"
        case isDryRun = "is_dry_run"
    }

    /// Total cost of all jobs in the workflow
    public var totalCost: Double {
        jobResults.values.compactMap { $0.cost }.reduce(0, +)
    }

    /// Total tokens used by all jobs
    public var totalTokens: Int {
        jobResults.values.compactMap { $0.totalTokens }.reduce(0, +)
    }

    /// Total input tokens
    public var totalInputTokens: Int {
        jobResults.values.compactMap { $0.inputTokens }.reduce(0, +)
    }

    /// Total output tokens
    public var totalOutputTokens: Int {
        jobResults.values.compactMap { $0.outputTokens }.reduce(0, +)
    }

    /// Duration of the entire workflow run
    public var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }

    /// Number of completed jobs
    public var completedJobCount: Int {
        jobResults.values.filter { $0.status == .completed }.count
    }

    /// Number of failed jobs
    public var failedJobCount: Int {
        jobResults.values.filter { $0.status == .failed }.count
    }

    /// Number of skipped jobs
    public var skippedJobCount: Int {
        jobResults.values.filter { $0.status == .skipped }.count
    }

    /// Check if all jobs are finished
    public var allJobsFinished: Bool {
        jobResults.values.allSatisfy { $0.isFinished }
    }

    /// Check if the workflow is still running
    public var isRunning: Bool {
        status == .running
    }

    /// Mark the workflow as started
    public mutating func markStarted() {
        status = .running
        startTime = Date()
    }

    /// Mark the workflow as completed
    public mutating func markCompleted() {
        status = .completed
        endTime = Date()
    }

    /// Mark the workflow as failed
    public mutating func markFailed(error: String) {
        status = .failed
        endTime = Date()
        errorMessage = error
    }

    /// Mark the workflow as cancelled
    public mutating func markCancelled() {
        status = .cancelled
        endTime = Date()
    }

    /// Get result for a specific job
    public func jobResult(for name: String) -> JobResult? {
        jobResults[name]
    }

    /// Update a job result
    public mutating func updateJobResult(_ result: JobResult) {
        jobResults[result.jobName] = result
    }

    /// Get outputs for a specific job
    public func outputs(for jobName: String) -> [String: String] {
        jobResults[jobName]?.outputs ?? [:]
    }

    /// Get a specific output value
    public func output(job: String, key: String) -> String? {
        jobResults[job]?.outputs[key]
    }

    /// Get jobs that are ready to run (pending and all dependencies completed)
    public func readyJobs(workflow: Workflow) -> [String] {
        jobResults.compactMap { name, result -> String? in
            guard result.status == .pending else { return nil }
            guard let job = workflow.jobs[name] else { return nil }

            // Check if all dependencies are completed
            if let needs = job.needs {
                for dependency in needs {
                    guard let depResult = jobResults[dependency] else { return nil }
                    guard depResult.status == .completed else { return nil }
                }
            }

            return name
        }.sorted()
    }

    /// Create a summary of the workflow run
    public func summary() -> String {
        var lines: [String] = []

        lines.append("Workflow: \(workflowName)")
        lines.append("Status: \(status.rawValue)")
        lines.append("Run ID: \(id)")

        if let duration = duration {
            lines.append("Duration: \(String(format: "%.1f", duration))s")
        }

        lines.append("")
        lines.append("Jobs:")

        for (name, result) in jobResults.sorted(by: { $0.key < $1.key }) {
            var jobLine = "  \(statusIcon(for: result.status)) \(name): \(result.status.rawValue)"

            if let duration = result.duration {
                jobLine += " (\(String(format: "%.1f", duration))s)"
            }

            if let cost = result.cost {
                jobLine += " $\(String(format: "%.4f", cost))"
            }

            lines.append(jobLine)

            if result.status == .failed, let error = result.errorMessage {
                lines.append("      Error: \(error)")
            }
        }

        lines.append("")
        lines.append("Total Cost: $\(String(format: "%.4f", totalCost))")
        lines.append("Total Tokens: \(totalTokens) (\(totalInputTokens) input, \(totalOutputTokens) output)")

        return lines.joined(separator: "\n")
    }

    private func statusIcon(for status: JobStatus) -> String {
        switch status {
        case .pending: return "○"
        case .running: return "◐"
        case .completed: return "●"
        case .failed: return "✗"
        case .skipped: return "⊘"
        case .cancelled: return "◌"
        }
    }
}

// MARK: - Workflow Run Stats

public struct WorkflowStats: Codable {
    public var totalRuns: Int
    public var successfulRuns: Int
    public var failedRuns: Int
    public var totalCost: Double
    public var totalTokens: Int
    public var lastRunDate: Date?
    public var lastRunStatus: WorkflowStatus?
    public var averageDuration: TimeInterval?

    public init() {
        self.totalRuns = 0
        self.successfulRuns = 0
        self.failedRuns = 0
        self.totalCost = 0
        self.totalTokens = 0
    }

    enum CodingKeys: String, CodingKey {
        case totalRuns = "total_runs"
        case successfulRuns = "successful_runs"
        case failedRuns = "failed_runs"
        case totalCost = "total_cost"
        case totalTokens = "total_tokens"
        case lastRunDate = "last_run_date"
        case lastRunStatus = "last_run_status"
        case averageDuration = "average_duration"
    }

    public var successRate: Double {
        guard totalRuns > 0 else { return 0 }
        return Double(successfulRuns) / Double(totalRuns)
    }

    public var averageCost: Double? {
        guard totalRuns > 0 else { return nil }
        return totalCost / Double(totalRuns)
    }

    public mutating func recordRun(_ run: WorkflowRun) {
        totalRuns += 1

        if run.status == .completed {
            successfulRuns += 1
        } else if run.status == .failed {
            failedRuns += 1
        }

        totalCost += run.totalCost
        totalTokens += run.totalTokens
        lastRunDate = run.endTime ?? run.startTime
        lastRunStatus = run.status

        // Update average duration
        if let duration = run.duration {
            if let currentAvg = averageDuration {
                averageDuration = (currentAvg * Double(totalRuns - 1) + duration) / Double(totalRuns)
            } else {
                averageDuration = duration
            }
        }
    }
}
