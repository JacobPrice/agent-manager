import Foundation
import Yams

public enum TriggerType: String, Codable {
    case schedule
    case manual
    case fileWatch = "file-watch"
}

public struct Trigger: Codable {
    public let type: TriggerType
    public let hour: Int?
    public let minute: Int?
    public let watchPath: String?

    public init(type: TriggerType, hour: Int? = nil, minute: Int? = nil, watchPath: String? = nil) {
        self.type = type
        self.hour = hour
        self.minute = minute
        self.watchPath = watchPath
    }

    enum CodingKeys: String, CodingKey {
        case type
        case hour
        case minute
        case watchPath = "watch_path"
    }
}

public struct Agent: Codable {
    public let name: String
    public let description: String
    public let trigger: Trigger
    public let workingDirectory: String
    public let contextScript: String?
    public let prompt: String
    public let allowedTools: [String]
    public let maxTurns: Int
    public let maxBudgetUSD: Double

    public init(
        name: String,
        description: String,
        trigger: Trigger,
        workingDirectory: String,
        contextScript: String? = nil,
        prompt: String,
        allowedTools: [String],
        maxTurns: Int = 10,
        maxBudgetUSD: Double = 1.0
    ) {
        self.name = name
        self.description = description
        self.trigger = trigger
        self.workingDirectory = workingDirectory
        self.contextScript = contextScript
        self.prompt = prompt
        self.allowedTools = allowedTools
        self.maxTurns = maxTurns
        self.maxBudgetUSD = maxBudgetUSD
    }

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case trigger
        case workingDirectory = "working_directory"
        case contextScript = "context_script"
        case prompt
        case allowedTools = "allowed_tools"
        case maxTurns = "max_turns"
        case maxBudgetUSD = "max_budget_usd"
    }

    /// Expand ~ in working directory to full path
    public var expandedWorkingDirectory: String {
        if workingDirectory.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser.path + String(workingDirectory.dropFirst())
        }
        return workingDirectory
    }
}

// MARK: - YAML Parsing

public extension Agent {
    static func load(from data: Data) throws -> Agent {
        let decoder = YAMLDecoder()
        return try decoder.decode(Agent.self, from: data)
    }

    static func load(fromFile path: String) throws -> Agent {
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

public extension Agent {
    static func template(name: String) -> Agent {
        Agent(
            name: name,
            description: "Description of what this agent does",
            trigger: Trigger(type: .manual),
            workingDirectory: "~/",
            contextScript: """
                # Gather context for the agent
                echo "Current directory: $(pwd)"
                echo "Date: $(date)"
                """,
            prompt: """
                You are an automated agent. Your task is to...

                Please analyze the context provided and take appropriate action.
                """,
            allowedTools: ["Read", "Edit", "Write", "Bash(git *)"],
            maxTurns: 10,
            maxBudgetUSD: 1.0
        )
    }
}
