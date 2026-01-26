import Foundation

public struct AgentStats: Codable {
    public var lastRunTokens: Int?
    public var lastRunInputTokens: Int?
    public var lastRunOutputTokens: Int?
    public var totalTokens: Int
    public var totalInputTokens: Int
    public var totalOutputTokens: Int
    public var runCount: Int
    public var lastRunDate: Date?
    public var lastRunCost: Double?
    public var totalCost: Double

    public init() {
        self.totalTokens = 0
        self.totalInputTokens = 0
        self.totalOutputTokens = 0
        self.runCount = 0
        self.totalCost = 0
    }

    public var averageTokens: Int? {
        guard runCount > 0 else { return nil }
        return totalTokens / runCount
    }

    public var averageCost: Double? {
        guard runCount > 0 else { return nil }
        return totalCost / Double(runCount)
    }

    public mutating func recordRun(inputTokens: Int, outputTokens: Int, cost: Double?, date: Date = Date()) {
        let totalForRun = inputTokens + outputTokens

        lastRunTokens = totalForRun
        lastRunInputTokens = inputTokens
        lastRunOutputTokens = outputTokens
        lastRunDate = date
        lastRunCost = cost

        totalTokens += totalForRun
        totalInputTokens += inputTokens
        totalOutputTokens += outputTokens
        runCount += 1

        if let cost = cost {
            totalCost += cost
        }
    }
}

public struct StatsManager {
    public static let shared = StatsManager()

    private let statsFile: URL

    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.statsFile = home
            .appendingPathComponent(".agent-manager")
            .appendingPathComponent("stats.json")
    }

    /// Load all stats
    public func loadAllStats() throws -> [String: AgentStats] {
        guard FileManager.default.fileExists(atPath: statsFile.path) else {
            return [:]
        }

        let data = try Data(contentsOf: statsFile)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([String: AgentStats].self, from: data)
    }

    /// Get stats for a specific agent
    public func getStats(agentName: String) throws -> AgentStats {
        let allStats = try loadAllStats()
        return allStats[agentName] ?? AgentStats()
    }

    /// Save stats for an agent
    public func saveStats(agentName: String, stats: AgentStats) throws {
        var allStats = (try? loadAllStats()) ?? [:]
        allStats[agentName] = stats

        // Ensure directory exists
        let dir = statsFile.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(allStats)
        try data.write(to: statsFile)
    }

    /// Record a run for an agent
    public func recordRun(agentName: String, inputTokens: Int, outputTokens: Int, cost: Double?) throws {
        var stats = (try? getStats(agentName: agentName)) ?? AgentStats()
        stats.recordRun(inputTokens: inputTokens, outputTokens: outputTokens, cost: cost)
        try saveStats(agentName: agentName, stats: stats)
    }

    /// Delete stats for an agent
    public func deleteStats(agentName: String) throws {
        var allStats = (try? loadAllStats()) ?? [:]
        allStats.removeValue(forKey: agentName)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(allStats)
        try data.write(to: statsFile)
    }

    /// Parse token usage from Claude CLI output
    /// Claude outputs lines like: "Total tokens: 1234" or similar at the end
    public static func parseTokenUsage(from output: String) -> (input: Int, output: Int, cost: Double?)? {
        // Look for token usage patterns in Claude's output
        // Common patterns:
        // - "Input tokens: X, Output tokens: Y"
        // - "Tokens used: X"
        // - Cost information

        var inputTokens: Int?
        var outputTokens: Int?
        var cost: Double?

        let lines = output.components(separatedBy: .newlines)

        for line in lines.reversed() {  // Check from end since stats are usually at the bottom
            let lowercased = line.lowercased()

            // Try to match "input tokens: X" or "input: X tokens"
            if inputTokens == nil {
                if let match = line.range(of: #"input[:\s]+(\d[\d,]*)"#, options: .regularExpression, range: nil, locale: nil) {
                    let numberStr = String(line[match]).components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                    inputTokens = Int(numberStr)
                }
            }

            // Try to match "output tokens: X" or "output: X tokens"
            if outputTokens == nil {
                if let match = line.range(of: #"output[:\s]+(\d[\d,]*)"#, options: .regularExpression, range: nil, locale: nil) {
                    let numberStr = String(line[match]).components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                    outputTokens = Int(numberStr)
                }
            }

            // Try to match cost like "$0.05" or "cost: $0.05"
            if cost == nil {
                if let match = line.range(of: #"\$(\d+\.?\d*)"#, options: .regularExpression) {
                    let costStr = String(line[match]).replacingOccurrences(of: "$", with: "")
                    cost = Double(costStr)
                }
            }

            // Also try "total tokens: X" if we don't have separate input/output
            if inputTokens == nil && outputTokens == nil {
                if lowercased.contains("total") && lowercased.contains("token") {
                    let numberStr = line.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                    if let total = Int(numberStr), total > 0 {
                        // Estimate 70% input, 30% output if we only have total
                        inputTokens = Int(Double(total) * 0.7)
                        outputTokens = total - inputTokens!
                    }
                }
            }
        }

        // Return nil if we couldn't find any token info
        guard let input = inputTokens, let output = outputTokens else {
            return nil
        }

        return (input, output, cost)
    }
}
