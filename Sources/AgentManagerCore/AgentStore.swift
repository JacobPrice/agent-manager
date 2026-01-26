import Foundation

public struct AgentStore {
    public static let shared = AgentStore()

    public let baseDirectory: URL
    public let agentsDirectory: URL
    public let logsDirectory: URL
    public let configFile: URL

    public init(baseDirectory: URL? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.baseDirectory = baseDirectory ?? home.appendingPathComponent(".agent-manager")
        self.agentsDirectory = self.baseDirectory.appendingPathComponent("agents")
        self.logsDirectory = self.baseDirectory.appendingPathComponent("logs")
        self.configFile = self.baseDirectory.appendingPathComponent("config.yaml")
    }

    /// Ensure all required directories exist
    public func ensureDirectoriesExist() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: agentsDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
    }

    /// Get path to agent YAML file
    public func agentPath(name: String) -> URL {
        agentsDirectory.appendingPathComponent("\(name).yaml")
    }

    /// Get path to agent's log directory
    public func logDirectory(agentName: String) -> URL {
        logsDirectory.appendingPathComponent(agentName)
    }

    /// List all agent names
    public func listAgentNames() throws -> [String] {
        let fm = FileManager.default

        guard fm.fileExists(atPath: agentsDirectory.path) else {
            return []
        }

        let files = try fm.contentsOfDirectory(at: agentsDirectory, includingPropertiesForKeys: nil)
        return files
            .filter { $0.pathExtension == "yaml" || $0.pathExtension == "yml" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    /// Load all agents
    public func listAgents() throws -> [Agent] {
        let names = try listAgentNames()
        return try names.compactMap { name in
            try? load(name: name)
        }
    }

    /// Load a specific agent by name
    public func load(name: String) throws -> Agent {
        let path = agentPath(name: name)

        guard FileManager.default.fileExists(atPath: path.path) else {
            throw AgentStoreError.agentNotFound(name)
        }

        return try Agent.load(fromFile: path.path)
    }

    /// Check if an agent exists
    public func exists(name: String) -> Bool {
        FileManager.default.fileExists(atPath: agentPath(name: name).path)
    }

    /// Save an agent
    public func save(_ agent: Agent) throws {
        try ensureDirectoriesExist()
        let path = agentPath(name: agent.name)
        try agent.save(toFile: path.path)
    }

    /// Delete an agent
    public func delete(name: String) throws {
        let path = agentPath(name: name)

        guard FileManager.default.fileExists(atPath: path.path) else {
            throw AgentStoreError.agentNotFound(name)
        }

        try FileManager.default.removeItem(at: path)
    }

    /// Get agent status info (for list command)
    public func getAgentInfo(name: String) throws -> AgentInfo {
        let agent = try load(name: name)
        let isEnabled = LaunchAgentManager.shared.isInstalled(agentName: name)
        let lastRun = try? LogManager.shared.lastRunDate(agentName: name)
        let stats = try? StatsManager.shared.getStats(agentName: name)

        return AgentInfo(
            name: agent.name,
            description: agent.description,
            triggerType: agent.trigger.type,
            isEnabled: isEnabled,
            lastRun: lastRun,
            stats: stats
        )
    }

    /// Get info for all agents
    public func listAgentInfo() throws -> [AgentInfo] {
        let names = try listAgentNames()
        return names.compactMap { name in
            try? getAgentInfo(name: name)
        }
    }
}

// MARK: - AgentInfo

public struct AgentInfo {
    public let name: String
    public let description: String
    public let triggerType: TriggerType
    public let isEnabled: Bool
    public let lastRun: Date?
    public let stats: AgentStats?

    public init(name: String, description: String, triggerType: TriggerType, isEnabled: Bool, lastRun: Date?, stats: AgentStats? = nil) {
        self.name = name
        self.description = description
        self.triggerType = triggerType
        self.isEnabled = isEnabled
        self.lastRun = lastRun
        self.stats = stats
    }

    public var statusIndicator: String {
        isEnabled ? "●" : "○"
    }

    public var triggerIcon: String {
        switch triggerType {
        case .schedule: return "⏰"
        case .manual: return "▶"
        case .fileWatch: return "👁"
        }
    }

    public var lastRunTokensFormatted: String? {
        guard let tokens = stats?.lastRunTokens else { return nil }
        return formatTokenCount(tokens)
    }

    public var averageTokensFormatted: String? {
        guard let tokens = stats?.averageTokens else { return nil }
        return formatTokenCount(tokens)
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk", Double(count) / 1000.0)
        }
        return "\(count)"
    }
}

// MARK: - Errors

public enum AgentStoreError: Error, LocalizedError {
    case agentNotFound(String)
    case agentAlreadyExists(String)
    case invalidAgentName(String)

    public var errorDescription: String? {
        switch self {
        case .agentNotFound(let name):
            return "Agent '\(name)' not found"
        case .agentAlreadyExists(let name):
            return "Agent '\(name)' already exists"
        case .invalidAgentName(let name):
            return "Invalid agent name: '\(name)'"
        }
    }
}
