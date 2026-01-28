import Foundation

/// Manages cost and turn limits for workflow execution
public struct Guardrails {
    /// Maximum total cost for a workflow run (USD)
    public var maxCostUSD: Double?

    /// Maximum turns per job
    public var maxTurnsPerJob: Int

    /// Maximum concurrent jobs
    public var maxConcurrentJobs: Int

    /// Require human approval above this cost threshold
    public var approvalThresholdUSD: Double?

    /// Current accumulated cost
    private(set) public var currentCost: Double = 0

    /// Current turn count per job
    private(set) public var turnCounts: [String: Int] = [:]

    public init(
        maxCostUSD: Double? = nil,
        maxTurnsPerJob: Int = 10,
        maxConcurrentJobs: Int = 4,
        approvalThresholdUSD: Double? = nil
    ) {
        self.maxCostUSD = maxCostUSD
        self.maxTurnsPerJob = maxTurnsPerJob
        self.maxConcurrentJobs = maxConcurrentJobs
        self.approvalThresholdUSD = approvalThresholdUSD
    }

    /// Check if we can start a new job based on cost limits
    public func canStartJob(estimatedCost: Double = 0) -> GuardrailResult {
        if let maxCost = maxCostUSD {
            if currentCost + estimatedCost > maxCost {
                return .denied(reason: "Would exceed maximum workflow cost of $\(String(format: "%.2f", maxCost))")
            }
        }

        return .allowed
    }

    /// Check if a job can continue based on turn limits
    public func canContinue(jobName: String) -> GuardrailResult {
        let currentTurns = turnCounts[jobName] ?? 0
        if currentTurns >= maxTurnsPerJob {
            return .denied(reason: "Job '\(jobName)' has reached maximum turns (\(maxTurnsPerJob))")
        }
        return .allowed
    }

    /// Record cost from a completed job
    public mutating func recordCost(_ cost: Double, jobName: String) {
        currentCost += cost
    }

    /// Record a turn for a job
    public mutating func recordTurn(jobName: String) {
        turnCounts[jobName, default: 0] += 1
    }

    /// Check if human approval is required for current cost level
    public func requiresApproval() -> Bool {
        guard let threshold = approvalThresholdUSD else { return false }
        return currentCost >= threshold
    }

    /// Get remaining budget
    public var remainingBudget: Double? {
        guard let maxCost = maxCostUSD else { return nil }
        return max(0, maxCost - currentCost)
    }

    /// Get budget utilization percentage
    public var budgetUtilization: Double? {
        guard let maxCost = maxCostUSD, maxCost > 0 else { return nil }
        return (currentCost / maxCost) * 100
    }

    /// Reset guardrails for a new run
    public mutating func reset() {
        currentCost = 0
        turnCounts = [:]
    }
}

// MARK: - Guardrail Result

public enum GuardrailResult {
    case allowed
    case denied(reason: String)
    case requiresApproval(reason: String)

    public var isAllowed: Bool {
        if case .allowed = self { return true }
        return false
    }

    public var reason: String? {
        switch self {
        case .allowed:
            return nil
        case .denied(let reason), .requiresApproval(let reason):
            return reason
        }
    }
}

// MARK: - Guardrails Errors

public enum GuardrailError: Error, LocalizedError {
    case costLimitExceeded(current: Double, limit: Double)
    case turnLimitExceeded(jobName: String, turns: Int, limit: Int)
    case approvalRequired(reason: String)

    public var errorDescription: String? {
        switch self {
        case .costLimitExceeded(let current, let limit):
            return "Cost limit exceeded: $\(String(format: "%.4f", current)) > $\(String(format: "%.2f", limit))"
        case .turnLimitExceeded(let jobName, let turns, let limit):
            return "Turn limit exceeded for job '\(jobName)': \(turns) >= \(limit)"
        case .approvalRequired(let reason):
            return "Human approval required: \(reason)"
        }
    }
}
