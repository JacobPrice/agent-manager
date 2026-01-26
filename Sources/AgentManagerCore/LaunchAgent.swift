import Foundation

public struct LaunchAgentManager {
    public static let shared = LaunchAgentManager()

    public let launchAgentsDirectory: URL

    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.launchAgentsDirectory = home
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
    }

    /// Get the plist filename for an agent
    public func plistName(agentName: String) -> String {
        "com.agentmanager.\(agentName).plist"
    }

    /// Get the full path to the plist file
    public func plistPath(agentName: String) -> URL {
        launchAgentsDirectory.appendingPathComponent(plistName(agentName: agentName))
    }

    /// Check if a LaunchAgent is installed
    public func isInstalled(agentName: String) -> Bool {
        FileManager.default.fileExists(atPath: plistPath(agentName: agentName).path)
    }

    /// Check if a LaunchAgent is loaded
    public func isLoaded(agentName: String) -> Bool {
        let label = "com.agentmanager.\(agentName)"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["list", label]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Generate plist content for an agent
    public func generatePlist(agent: Agent) throws -> String {
        guard case .schedule = agent.trigger.type,
              let hour = agent.trigger.hour,
              let minute = agent.trigger.minute else {
            throw LaunchAgentError.notScheduledAgent(agent.name)
        }

        // Find agentctl path
        let agentctlPath = try findAgentctlPath()

        // Get log path
        let logPath = AgentStore.shared.logDirectory(agentName: agent.name)
            .appendingPathComponent("launchd.log")

        let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.agentmanager.\(agent.name)</string>

                <key>ProgramArguments</key>
                <array>
                    <string>\(agentctlPath)</string>
                    <string>run</string>
                    <string>\(agent.name)</string>
                </array>

                <key>StartCalendarInterval</key>
                <dict>
                    <key>Hour</key>
                    <integer>\(hour)</integer>
                    <key>Minute</key>
                    <integer>\(minute)</integer>
                </dict>

                <key>WorkingDirectory</key>
                <string>\(agent.expandedWorkingDirectory)</string>

                <key>StandardOutPath</key>
                <string>\(logPath.path)</string>

                <key>StandardErrorPath</key>
                <string>\(logPath.path)</string>

                <key>EnvironmentVariables</key>
                <dict>
                    <key>PATH</key>
                    <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin</string>
                </dict>

                <key>RunAtLoad</key>
                <false/>
            </dict>
            </plist>
            """

        return plist
    }

    /// Install (enable) a LaunchAgent for an agent
    public func install(agent: Agent) throws {
        // Ensure logs directory exists
        let logDir = AgentStore.shared.logDirectory(agentName: agent.name)
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        // Generate plist
        let plistContent = try generatePlist(agent: agent)

        // Ensure LaunchAgents directory exists
        try FileManager.default.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)

        // Write plist file
        let plistURL = plistPath(agentName: agent.name)
        try plistContent.write(to: plistURL, atomically: true, encoding: .utf8)

        // Load the LaunchAgent
        try loadAgent(agentName: agent.name)
    }

    /// Uninstall (disable) a LaunchAgent
    public func uninstall(agentName: String) throws {
        // Unload if loaded
        if isLoaded(agentName: agentName) {
            try unloadAgent(agentName: agentName)
        }

        // Remove plist file
        let plistURL = plistPath(agentName: agentName)
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
    }

    /// Load a LaunchAgent
    private func loadAgent(agentName: String) throws {
        let plistURL = plistPath(agentName: agentName)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", plistURL.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            throw LaunchAgentError.loadFailed(agentName, output)
        }
    }

    /// Unload a LaunchAgent
    private func unloadAgent(agentName: String) throws {
        let plistURL = plistPath(agentName: agentName)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", plistURL.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        // Don't throw on unload failure - it might not be loaded
    }

    /// Find the agentctl executable path
    private func findAgentctlPath() throws -> String {
        // Check common locations
        let possiblePaths = [
            FileManager.default.homeDirectoryForCurrentUser.path + "/.local/bin/agentctl",
            "/usr/local/bin/agentctl",
            ProcessInfo.processInfo.arguments.first ?? "",
        ]

        for path in possiblePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // If running from build directory, use that
        let currentExecutable = ProcessInfo.processInfo.arguments.first ?? ""
        if currentExecutable.contains("agentctl") && FileManager.default.fileExists(atPath: currentExecutable) {
            return currentExecutable
        }

        // Default to ~/.local/bin/agentctl
        return FileManager.default.homeDirectoryForCurrentUser.path + "/.local/bin/agentctl"
    }

    /// Get status of a LaunchAgent
    public func status(agentName: String) -> LaunchAgentStatus {
        let installed = isInstalled(agentName: agentName)
        let loaded = isLoaded(agentName: agentName)

        if !installed {
            return .notInstalled
        } else if loaded {
            return .active
        } else {
            return .installed
        }
    }
}

// MARK: - LaunchAgentStatus

public enum LaunchAgentStatus {
    case notInstalled
    case installed
    case active

    public var description: String {
        switch self {
        case .notInstalled: return "Not installed"
        case .installed: return "Installed (not loaded)"
        case .active: return "Active"
        }
    }
}

// MARK: - Errors

public enum LaunchAgentError: Error, LocalizedError {
    case notScheduledAgent(String)
    case loadFailed(String, String)
    case unloadFailed(String, String)

    public var errorDescription: String? {
        switch self {
        case .notScheduledAgent(let name):
            return "Agent '\(name)' is not a scheduled agent (trigger type must be 'schedule')"
        case .loadFailed(let name, let output):
            return "Failed to load LaunchAgent for '\(name)': \(output)"
        case .unloadFailed(let name, let output):
            return "Failed to unload LaunchAgent for '\(name)': \(output)"
        }
    }
}
