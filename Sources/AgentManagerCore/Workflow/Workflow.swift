import Foundation
import Yams

// MARK: - Workflow Triggers

public struct ScheduleConfig: Codable, Equatable {
    public let cron: String

    public init(cron: String) {
        self.cron = cron
    }
}

public struct WorkflowTriggers: Codable, Equatable {
    public let schedule: [ScheduleConfig]?
    public let manual: Bool?

    public init(schedule: [ScheduleConfig]? = nil, manual: Bool? = nil) {
        self.schedule = schedule
        self.manual = manual
    }

    /// Check if manual trigger is enabled (defaults to true if not specified)
    public var isManualEnabled: Bool {
        manual ?? true
    }

    /// Check if workflow has any schedule triggers
    public var hasSchedule: Bool {
        guard let schedule = schedule else { return false }
        return !schedule.isEmpty
    }
}

// MARK: - Workflow Defaults

public struct WorkflowDefaults: Codable, Equatable {
    public let workingDirectory: String?
    public let maxBudgetUSD: Double?
    public let maxTurns: Int?
    public let allowedTools: [String]?

    public init(
        workingDirectory: String? = nil,
        maxBudgetUSD: Double? = nil,
        maxTurns: Int? = nil,
        allowedTools: [String]? = nil
    ) {
        self.workingDirectory = workingDirectory
        self.maxBudgetUSD = maxBudgetUSD
        self.maxTurns = maxTurns
        self.allowedTools = allowedTools
    }

    enum CodingKeys: String, CodingKey {
        case workingDirectory = "working_directory"
        case maxBudgetUSD = "max_budget_usd"
        case maxTurns = "max_turns"
        case allowedTools = "allowed_tools"
    }
}

// MARK: - Job

public struct Job: Codable, Equatable {
    /// Reference to a reusable agent template (mutually exclusive with prompt)
    public let agent: String?

    /// Inline prompt for this job (mutually exclusive with agent)
    public let prompt: String?

    /// List of job names this job depends on
    public let needs: [String]?

    /// Conditional expression (e.g., "${{ jobs.lint.outputs.has_errors == 'false' }}")
    public let `if`: String?

    /// List of output names this job produces
    public let outputs: [String]?

    /// Per-job working directory override
    public let workingDirectory: String?

    /// Per-job allowed tools override
    public let allowedTools: [String]?

    /// Per-job max turns override
    public let maxTurns: Int?

    /// Per-job max budget override
    public let maxBudgetUSD: Double?

    /// Context script to run before the job
    public let contextScript: String?

    public init(
        agent: String? = nil,
        prompt: String? = nil,
        needs: [String]? = nil,
        `if`: String? = nil,
        outputs: [String]? = nil,
        workingDirectory: String? = nil,
        allowedTools: [String]? = nil,
        maxTurns: Int? = nil,
        maxBudgetUSD: Double? = nil,
        contextScript: String? = nil
    ) {
        self.agent = agent
        self.prompt = prompt
        self.needs = needs
        self.`if` = `if`
        self.outputs = outputs
        self.workingDirectory = workingDirectory
        self.allowedTools = allowedTools
        self.maxTurns = maxTurns
        self.maxBudgetUSD = maxBudgetUSD
        self.contextScript = contextScript
    }

    enum CodingKeys: String, CodingKey {
        case agent
        case prompt
        case needs
        case `if`
        case outputs
        case workingDirectory = "working_directory"
        case allowedTools = "allowed_tools"
        case maxTurns = "max_turns"
        case maxBudgetUSD = "max_budget_usd"
        case contextScript = "context_script"
    }

    /// Check if this job has any dependencies
    public var hasDependencies: Bool {
        guard let needs = needs else { return false }
        return !needs.isEmpty
    }

    /// Check if this job references an external agent
    public var usesAgent: Bool {
        agent != nil
    }

    /// Check if this job has an inline prompt
    public var hasInlinePrompt: Bool {
        prompt != nil
    }
}

// MARK: - Workflow

public struct Workflow: Codable, Equatable {
    public let name: String
    public let description: String?
    public let on: WorkflowTriggers
    public let defaults: WorkflowDefaults?
    public let jobs: [String: Job]
    public let maxCostUSD: Double?

    public init(
        name: String,
        description: String? = nil,
        on: WorkflowTriggers,
        defaults: WorkflowDefaults? = nil,
        jobs: [String: Job],
        maxCostUSD: Double? = nil
    ) {
        self.name = name
        self.description = description
        self.on = on
        self.defaults = defaults
        self.jobs = jobs
        self.maxCostUSD = maxCostUSD
    }

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case on
        case defaults
        case jobs
        case maxCostUSD = "max_cost_usd"
    }

    /// Get job names sorted in a stable order
    public var jobNames: [String] {
        jobs.keys.sorted()
    }

    /// Get the effective working directory for a job
    public func workingDirectory(for jobName: String) -> String {
        guard let job = jobs[jobName] else {
            return defaults?.workingDirectory ?? "~/"
        }
        return job.workingDirectory ?? defaults?.workingDirectory ?? "~/"
    }

    /// Get the effective max budget for a job
    public func maxBudget(for jobName: String) -> Double {
        guard let job = jobs[jobName] else {
            return defaults?.maxBudgetUSD ?? 1.0
        }
        return job.maxBudgetUSD ?? defaults?.maxBudgetUSD ?? 1.0
    }

    /// Get the effective max turns for a job
    public func maxTurns(for jobName: String) -> Int {
        guard let job = jobs[jobName] else {
            return defaults?.maxTurns ?? 10
        }
        return job.maxTurns ?? defaults?.maxTurns ?? 10
    }

    /// Get the effective allowed tools for a job
    public func allowedTools(for jobName: String) -> [String] {
        guard let job = jobs[jobName] else {
            return defaults?.allowedTools ?? ["Read", "Grep", "Glob"]
        }
        return job.allowedTools ?? defaults?.allowedTools ?? ["Read", "Grep", "Glob"]
    }
}

// MARK: - YAML Parsing

public extension Workflow {
    static func load(from data: Data) throws -> Workflow {
        let decoder = YAMLDecoder()
        return try decoder.decode(Workflow.self, from: data)
    }

    static func load(fromFile path: String) throws -> Workflow {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        return try load(from: data)
    }

    func toYAML() throws -> String {
        let encoder = YAMLEncoder()
        return try encoder.encode(self)
    }

    func save(toFile path: String) throws {
        let yaml = try toYAML()
        let url = URL(fileURLWithPath: path)
        try yaml.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - Template Generation

public extension Workflow {
    static func template(name: String) -> Workflow {
        Workflow(
            name: name,
            description: "Description of what this workflow does",
            on: WorkflowTriggers(manual: true),
            defaults: WorkflowDefaults(
                workingDirectory: "~/",
                maxBudgetUSD: 0.50,
                maxTurns: 10,
                allowedTools: ["Read", "Grep", "Glob"]
            ),
            jobs: [
                "main": Job(
                    prompt: """
                        You are an automated agent. Your task is to...

                        Please analyze the context provided and take appropriate action.
                        """,
                    outputs: ["result"]
                )
            ]
        )
    }

    /// Generate a multi-job template for demonstration
    static func multiJobTemplate(name: String) -> Workflow {
        Workflow(
            name: name,
            description: "Multi-job workflow template with dependencies",
            on: WorkflowTriggers(manual: true),
            defaults: WorkflowDefaults(
                workingDirectory: "~/repos/project",
                maxBudgetUSD: 0.50
            ),
            jobs: [
                "analyze": Job(
                    prompt: "Analyze the codebase structure and identify key components.",
                    outputs: ["summary", "components"],
                    allowedTools: ["Read", "Grep", "Glob"]
                ),
                "review": Job(
                    prompt: "Review the code quality based on the analysis.",
                    needs: ["analyze"],
                    if: "${{ jobs.analyze.outputs.summary != '' }}",
                    outputs: ["issues", "recommendations"],
                    allowedTools: ["Read"]
                ),
                "report": Job(
                    prompt: "Generate a final report combining all findings.",
                    needs: ["analyze", "review"],
                    outputs: ["report"]
                )
            ]
        )
    }
}

// MARK: - Validation

public extension Workflow {
    /// Validate the workflow structure
    func validate() throws {
        // Check each job has either agent or prompt (but not both)
        for (jobName, job) in jobs {
            if job.agent == nil && job.prompt == nil {
                throw WorkflowValidationError.jobMissingPromptOrAgent(jobName)
            }
            if job.agent != nil && job.prompt != nil {
                throw WorkflowValidationError.jobHasBothPromptAndAgent(jobName)
            }
        }

        // Check that all job dependencies exist
        for (jobName, job) in jobs {
            if let needs = job.needs {
                for dependency in needs {
                    if jobs[dependency] == nil {
                        throw WorkflowValidationError.unknownDependency(jobName: jobName, dependency: dependency)
                    }
                }
            }
        }

        // Check for circular dependencies
        try detectCycles()
    }

    /// Detect circular dependencies in the job graph
    private func detectCycles() throws {
        var visited: Set<String> = []
        var recursionStack: Set<String> = []

        func dfs(_ jobName: String, path: [String]) throws {
            if recursionStack.contains(jobName) {
                let cyclePath = path + [jobName]
                throw WorkflowValidationError.cyclicDependency(path: cyclePath)
            }

            if visited.contains(jobName) {
                return
            }

            visited.insert(jobName)
            recursionStack.insert(jobName)

            if let job = jobs[jobName], let needs = job.needs {
                for dependency in needs {
                    try dfs(dependency, path: path + [jobName])
                }
            }

            recursionStack.remove(jobName)
        }

        for jobName in jobs.keys {
            try dfs(jobName, path: [])
        }
    }

    /// Get jobs in topological order (respecting dependencies)
    func topologicalSort() throws -> [String] {
        var result: [String] = []
        var visited: Set<String> = []
        var tempMark: Set<String> = []

        func visit(_ jobName: String) throws {
            if tempMark.contains(jobName) {
                throw WorkflowValidationError.cyclicDependency(path: [jobName])
            }
            if visited.contains(jobName) {
                return
            }

            tempMark.insert(jobName)

            if let job = jobs[jobName], let needs = job.needs {
                for dependency in needs {
                    try visit(dependency)
                }
            }

            tempMark.remove(jobName)
            visited.insert(jobName)
            result.append(jobName)
        }

        for jobName in jobs.keys.sorted() {
            try visit(jobName)
        }

        return result
    }

    /// Get jobs that have no dependencies (can start immediately)
    func rootJobs() -> [String] {
        jobs.filter { !$0.value.hasDependencies }.map { $0.key }.sorted()
    }

    /// Get jobs that depend on the given job
    func dependents(of jobName: String) -> [String] {
        jobs.filter { _, job in
            job.needs?.contains(jobName) ?? false
        }.map { $0.key }.sorted()
    }
}

// MARK: - Validation Errors

public enum WorkflowValidationError: Error, LocalizedError {
    case jobMissingPromptOrAgent(String)
    case jobHasBothPromptAndAgent(String)
    case unknownDependency(jobName: String, dependency: String)
    case cyclicDependency(path: [String])
    case invalidExpression(String)

    public var errorDescription: String? {
        switch self {
        case .jobMissingPromptOrAgent(let jobName):
            return "Job '\(jobName)' must have either 'agent' or 'prompt' defined"
        case .jobHasBothPromptAndAgent(let jobName):
            return "Job '\(jobName)' cannot have both 'agent' and 'prompt' defined"
        case .unknownDependency(let jobName, let dependency):
            return "Job '\(jobName)' depends on unknown job '\(dependency)'"
        case .cyclicDependency(let path):
            return "Circular dependency detected: \(path.joined(separator: " -> "))"
        case .invalidExpression(let expr):
            return "Invalid expression: \(expr)"
        }
    }
}
