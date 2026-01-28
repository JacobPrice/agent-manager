import Foundation
import Yams

public struct WorkflowStore {
    public static let shared = WorkflowStore()

    public let baseDirectory: URL
    public let workflowsDirectory: URL
    public let runsDirectory: URL

    public init(baseDirectory: URL? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.baseDirectory = baseDirectory ?? home.appendingPathComponent(".agent-manager")
        self.workflowsDirectory = self.baseDirectory.appendingPathComponent("workflows")
        self.runsDirectory = self.baseDirectory.appendingPathComponent("runs")
    }

    /// Ensure all required directories exist
    public func ensureDirectoriesExist() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: workflowsDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: runsDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Workflow Path Helpers

    /// Get path to workflow YAML file
    public func workflowPath(name: String) -> URL {
        workflowsDirectory.appendingPathComponent("\(name).yaml")
    }

    /// Get path to workflow's run directory
    public func runDirectory(workflowName: String) -> URL {
        runsDirectory.appendingPathComponent(workflowName)
    }

    /// Get path to a specific run file
    public func runPath(workflowName: String, runId: String) -> URL {
        runDirectory(workflowName: workflowName)
            .appendingPathComponent("\(runId).json")
    }

    /// Get path to run's log directory
    public func runLogDirectory(workflowName: String, runId: String) -> URL {
        runDirectory(workflowName: workflowName)
            .appendingPathComponent(runId)
    }

    // MARK: - Workflow CRUD Operations

    /// List all workflow names
    public func listWorkflowNames() throws -> [String] {
        let fm = FileManager.default

        guard fm.fileExists(atPath: workflowsDirectory.path) else {
            return []
        }

        let files = try fm.contentsOfDirectory(at: workflowsDirectory, includingPropertiesForKeys: nil)
        return files
            .filter { $0.pathExtension == "yaml" || $0.pathExtension == "yml" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    /// Load all workflows
    public func listWorkflows() throws -> [Workflow] {
        let names = try listWorkflowNames()
        return names.compactMap { name in
            try? load(name: name)
        }
    }

    /// Load a specific workflow by name
    public func load(name: String) throws -> Workflow {
        let path = workflowPath(name: name)

        guard FileManager.default.fileExists(atPath: path.path) else {
            throw WorkflowStoreError.workflowNotFound(name)
        }

        return try Workflow.load(fromFile: path.path)
    }

    /// Check if a workflow exists
    public func exists(name: String) -> Bool {
        FileManager.default.fileExists(atPath: workflowPath(name: name).path)
    }

    /// Save a workflow
    public func save(_ workflow: Workflow) throws {
        try ensureDirectoriesExist()

        // Validate before saving
        try workflow.validate()

        let path = workflowPath(name: workflow.name)
        try workflow.save(toFile: path.path)
    }

    /// Delete a workflow
    public func delete(name: String) throws {
        let path = workflowPath(name: name)

        guard FileManager.default.fileExists(atPath: path.path) else {
            throw WorkflowStoreError.workflowNotFound(name)
        }

        try FileManager.default.removeItem(at: path)
    }

    /// Get workflow info for display
    public func getWorkflowInfo(name: String) throws -> WorkflowInfo {
        let workflow = try load(name: name)
        let isEnabled = WorkflowLaunchAgentManager.shared.isInstalled(workflowName: name)
        let stats = try? loadWorkflowStats(name: name)
        let lastRun = try? loadLastRun(workflowName: name)

        return WorkflowInfo(
            name: workflow.name,
            description: workflow.description,
            jobCount: workflow.jobs.count,
            hasSchedule: workflow.on.hasSchedule,
            isEnabled: isEnabled,
            lastRunStatus: lastRun?.status,
            lastRunDate: lastRun?.endTime ?? lastRun?.startTime,
            stats: stats
        )
    }

    /// Get info for all workflows
    public func listWorkflowInfo() throws -> [WorkflowInfo] {
        let names = try listWorkflowNames()
        return names.compactMap { name in
            try? getWorkflowInfo(name: name)
        }
    }

    // MARK: - Run Operations

    /// Save a workflow run
    public func saveRun(_ run: WorkflowRun) throws {
        try ensureDirectoriesExist()

        let runDir = runDirectory(workflowName: run.workflowName)
        try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)

        let runPath = self.runPath(workflowName: run.workflowName, runId: run.id)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(run)
        try data.write(to: runPath)

        // Update workflow stats
        try updateWorkflowStats(name: run.workflowName, run: run)
    }

    /// Load a specific run
    public func loadRun(workflowName: String, runId: String) throws -> WorkflowRun {
        let path = runPath(workflowName: workflowName, runId: runId)

        guard FileManager.default.fileExists(atPath: path.path) else {
            throw WorkflowStoreError.runNotFound(runId)
        }

        let data = try Data(contentsOf: path)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WorkflowRun.self, from: data)
    }

    /// List runs for a workflow (most recent first)
    public func listRuns(workflowName: String, limit: Int = 10) throws -> [WorkflowRun] {
        let runDir = runDirectory(workflowName: workflowName)

        guard FileManager.default.fileExists(atPath: runDir.path) else {
            return []
        }

        let files = try FileManager.default.contentsOfDirectory(at: runDir, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.pathExtension == "json" }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return date1 > date2
            }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return files.prefix(limit).compactMap { url -> WorkflowRun? in
            guard let data = try? Data(contentsOf: url),
                  let run = try? decoder.decode(WorkflowRun.self, from: data) else {
                return nil
            }
            return run
        }
    }

    /// Get the most recent run for a workflow
    public func loadLastRun(workflowName: String) throws -> WorkflowRun? {
        let runs = try listRuns(workflowName: workflowName, limit: 1)
        return runs.first
    }

    /// Delete old runs (keep most recent N)
    public func pruneRuns(workflowName: String, keepCount: Int = 50) throws {
        let runDir = runDirectory(workflowName: workflowName)

        guard FileManager.default.fileExists(atPath: runDir.path) else {
            return
        }

        let files = try FileManager.default.contentsOfDirectory(at: runDir, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.pathExtension == "json" }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return date1 > date2
            }

        // Delete runs beyond the keep count
        for url in files.dropFirst(keepCount) {
            try? FileManager.default.removeItem(at: url)

            // Also delete the log directory if it exists
            let logDir = url.deletingPathExtension()
            if FileManager.default.fileExists(atPath: logDir.path) {
                try? FileManager.default.removeItem(at: logDir)
            }
        }
    }

    // MARK: - Stats Operations

    private var statsFile: URL {
        baseDirectory.appendingPathComponent("workflow-stats.json")
    }

    /// Load all workflow stats
    public func loadAllWorkflowStats() throws -> [String: WorkflowStats] {
        guard FileManager.default.fileExists(atPath: statsFile.path) else {
            return [:]
        }

        let data = try Data(contentsOf: statsFile)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([String: WorkflowStats].self, from: data)
    }

    /// Load stats for a specific workflow
    public func loadWorkflowStats(name: String) throws -> WorkflowStats {
        let allStats = try loadAllWorkflowStats()
        return allStats[name] ?? WorkflowStats()
    }

    /// Save workflow stats
    private func saveWorkflowStats(_ stats: [String: WorkflowStats]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(stats)
        try data.write(to: statsFile)
    }

    /// Update stats for a workflow after a run
    private func updateWorkflowStats(name: String, run: WorkflowRun) throws {
        var allStats = (try? loadAllWorkflowStats()) ?? [:]
        var stats = allStats[name] ?? WorkflowStats()
        stats.recordRun(run)
        allStats[name] = stats
        try saveWorkflowStats(allStats)
    }

    /// Delete stats for a workflow
    public func deleteWorkflowStats(name: String) throws {
        var allStats = (try? loadAllWorkflowStats()) ?? [:]
        allStats.removeValue(forKey: name)
        try saveWorkflowStats(allStats)
    }
}

// MARK: - WorkflowInfo

public struct WorkflowInfo {
    public let name: String
    public let description: String?
    public let jobCount: Int
    public let hasSchedule: Bool
    public let isEnabled: Bool
    public let lastRunStatus: WorkflowStatus?
    public let lastRunDate: Date?
    public let stats: WorkflowStats?

    public init(
        name: String,
        description: String?,
        jobCount: Int,
        hasSchedule: Bool,
        isEnabled: Bool,
        lastRunStatus: WorkflowStatus?,
        lastRunDate: Date?,
        stats: WorkflowStats?
    ) {
        self.name = name
        self.description = description
        self.jobCount = jobCount
        self.hasSchedule = hasSchedule
        self.isEnabled = isEnabled
        self.lastRunStatus = lastRunStatus
        self.lastRunDate = lastRunDate
        self.stats = stats
    }

    public var statusIndicator: String {
        if isEnabled {
            return "●"
        } else {
            return "○"
        }
    }

    public var lastRunStatusIcon: String? {
        guard let status = lastRunStatus else { return nil }
        switch status {
        case .completed: return "✓"
        case .failed: return "✗"
        case .running: return "◐"
        case .cancelled: return "◌"
        case .pending: return "○"
        }
    }
}

// MARK: - Errors

public enum WorkflowStoreError: Error, LocalizedError {
    case workflowNotFound(String)
    case workflowAlreadyExists(String)
    case invalidWorkflowName(String)
    case runNotFound(String)
    case noScheduleTrigger(String)
    case agentNotFound(workflowName: String, agentName: String)

    public var errorDescription: String? {
        switch self {
        case .workflowNotFound(let name):
            return "Workflow '\(name)' not found"
        case .workflowAlreadyExists(let name):
            return "Workflow '\(name)' already exists"
        case .invalidWorkflowName(let name):
            return "Invalid workflow name: '\(name)'"
        case .runNotFound(let id):
            return "Workflow run '\(id)' not found"
        case .noScheduleTrigger(let name):
            return "Workflow '\(name)' has no schedule trigger configured"
        case .agentNotFound(let workflowName, let agentName):
            return "Workflow '\(workflowName)' references unknown agent '\(agentName)'"
        }
    }
}
