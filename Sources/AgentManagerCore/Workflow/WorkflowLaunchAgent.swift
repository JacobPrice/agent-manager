import Foundation

/// Manages LaunchAgents for scheduled workflows
public struct WorkflowLaunchAgentManager {
    public static let shared = WorkflowLaunchAgentManager()

    public let launchAgentsDirectory: URL

    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.launchAgentsDirectory = home
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
    }

    /// Get the plist filename for a workflow
    public func plistName(workflowName: String) -> String {
        "com.agent-manager.workflow.\(workflowName).plist"
    }

    /// Get the full path to the plist file
    public func plistPath(workflowName: String) -> URL {
        launchAgentsDirectory.appendingPathComponent(plistName(workflowName: workflowName))
    }

    /// Check if a LaunchAgent is installed
    public func isInstalled(workflowName: String) -> Bool {
        FileManager.default.fileExists(atPath: plistPath(workflowName: workflowName).path)
    }

    /// Check if a LaunchAgent is loaded
    public func isLoaded(workflowName: String) -> Bool {
        let label = "com.agent-manager.workflow.\(workflowName)"
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

    /// Generate plist content for a workflow
    public func generatePlist(workflow: Workflow) throws -> String {
        guard let schedules = workflow.on.schedule, !schedules.isEmpty else {
            throw WorkflowLaunchAgentError.noScheduleTrigger(workflow.name)
        }

        // Find agentctl path
        let agentctlPath = try findAgentctlPath()

        // Get log path
        let logPath = WorkflowStore.shared.runDirectory(workflowName: workflow.name)
            .appendingPathComponent("launchd.log")

        // Parse cron expressions and generate calendar intervals
        let calendarIntervals = try schedules.map { schedule -> String in
            try generateCalendarInterval(from: schedule.cron)
        }

        // Use first schedule's working directory or default
        let workingDirectory = workflow.defaults?.workingDirectory ?? "~/"
        let expandedWorkDir = expandPath(workingDirectory)

        let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.agent-manager.workflow.\(workflow.name)</string>

                <key>ProgramArguments</key>
                <array>
                    <string>\(agentctlPath)</string>
                    <string>run</string>
                    <string>\(workflow.name)</string>
                </array>

                <key>StartCalendarInterval</key>
                \(calendarIntervals.count == 1 ? calendarIntervals[0] : "<array>\n\(calendarIntervals.joined(separator: "\n"))\n</array>")

                <key>WorkingDirectory</key>
                <string>\(expandedWorkDir)</string>

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

    /// Install (enable) a LaunchAgent for a workflow
    public func install(workflow: Workflow) throws {
        // Ensure run directory exists
        let runDir = WorkflowStore.shared.runDirectory(workflowName: workflow.name)
        try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)

        // Generate plist
        let plistContent = try generatePlist(workflow: workflow)

        // Ensure LaunchAgents directory exists
        try FileManager.default.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)

        // Write plist file
        let plistURL = plistPath(workflowName: workflow.name)
        try plistContent.write(to: plistURL, atomically: true, encoding: .utf8)

        // Load the LaunchAgent
        try loadAgent(workflowName: workflow.name)
    }

    /// Uninstall (disable) a LaunchAgent
    public func uninstall(workflowName: String) throws {
        // Unload if loaded
        if isLoaded(workflowName: workflowName) {
            try unloadAgent(workflowName: workflowName)
        }

        // Remove plist file
        let plistURL = plistPath(workflowName: workflowName)
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
    }

    /// Load a LaunchAgent
    private func loadAgent(workflowName: String) throws {
        let plistURL = plistPath(workflowName: workflowName)

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
            throw WorkflowLaunchAgentError.loadFailed(workflowName, output)
        }
    }

    /// Unload a LaunchAgent
    private func unloadAgent(workflowName: String) throws {
        let plistURL = plistPath(workflowName: workflowName)

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

    /// Expand ~ in path to full path
    private func expandPath(_ path: String) -> String {
        if path.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser.path + String(path.dropFirst())
        }
        return path
    }

    /// Get status of a LaunchAgent
    public func status(workflowName: String) -> WorkflowLaunchAgentStatus {
        let installed = isInstalled(workflowName: workflowName)
        let loaded = isLoaded(workflowName: workflowName)

        if !installed {
            return .notInstalled
        } else if loaded {
            return .active
        } else {
            return .installed
        }
    }
}

// MARK: - Cron Parsing

extension WorkflowLaunchAgentManager {
    /// Parse a cron expression and generate LaunchAgent StartCalendarInterval
    /// Supports: minute hour day-of-month month day-of-week
    /// Examples:
    ///   "0 8 * * 1-5" -> Weekdays at 8:00 AM
    ///   "30 9 * * *" -> Every day at 9:30 AM
    ///   "0 */2 * * *" -> Every 2 hours (partial support)
    func generateCalendarInterval(from cron: String) throws -> String {
        let parts = cron.split(separator: " ").map(String.init)

        guard parts.count >= 5 else {
            throw WorkflowLaunchAgentError.invalidCronExpression(cron, "Expected 5 fields: minute hour day month weekday")
        }

        let minute = parts[0]
        let hour = parts[1]
        let day = parts[2]
        let month = parts[3]
        let weekday = parts[4]

        var dict: [String: Any] = [:]

        // Parse minute (0-59)
        if let min = parseField(minute, range: 0...59) {
            dict["Minute"] = min
        }

        // Parse hour (0-23)
        if let hr = parseField(hour, range: 0...23) {
            dict["Hour"] = hr
        }

        // Parse day of month (1-31)
        if let d = parseField(day, range: 1...31) {
            dict["Day"] = d
        }

        // Parse month (1-12)
        if let m = parseField(month, range: 1...12) {
            dict["Month"] = m
        }

        // Parse weekday (0-6, where 0 = Sunday)
        // Handle ranges like 1-5 (Monday-Friday)
        if let wd = parseWeekdayField(weekday) {
            // If it's a range, we need multiple calendar intervals
            if wd.count > 1 {
                return wd.map { dayNum -> String in
                    var d = dict
                    d["Weekday"] = dayNum
                    return generateDictXML(d)
                }.joined(separator: "\n")
            } else if let first = wd.first {
                dict["Weekday"] = first
            }
        }

        return generateDictXML(dict)
    }

    /// Parse a single cron field
    private func parseField(_ field: String, range: ClosedRange<Int>) -> Int? {
        // Wildcard - don't include in dict
        if field == "*" {
            return nil
        }

        // Simple number
        if let num = Int(field), range.contains(num) {
            return num
        }

        // Step values like */2 - not fully supported, use first value
        if field.hasPrefix("*/") {
            return range.lowerBound
        }

        return nil
    }

    /// Parse weekday field, handling ranges
    private func parseWeekdayField(_ field: String) -> [Int]? {
        // Wildcard
        if field == "*" {
            return nil
        }

        // Range like 1-5 (Monday-Friday)
        if field.contains("-") {
            let parts = field.split(separator: "-")
            if parts.count == 2,
               let start = Int(parts[0]),
               let end = Int(parts[1]),
               start >= 0, end <= 6, start <= end {
                return Array(start...end)
            }
        }

        // Simple number
        if let num = Int(field), (0...6).contains(num) {
            return [num]
        }

        return nil
    }

    /// Generate XML dict from dictionary
    private func generateDictXML(_ dict: [String: Any]) -> String {
        var lines: [String] = ["<dict>"]

        for (key, value) in dict.sorted(by: { $0.key < $1.key }) {
            lines.append("    <key>\(key)</key>")
            if let intVal = value as? Int {
                lines.append("    <integer>\(intVal)</integer>")
            }
        }

        lines.append("</dict>")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Status

public enum WorkflowLaunchAgentStatus {
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

public enum WorkflowLaunchAgentError: Error, LocalizedError {
    case noScheduleTrigger(String)
    case invalidCronExpression(String, String)
    case loadFailed(String, String)
    case unloadFailed(String, String)

    public var errorDescription: String? {
        switch self {
        case .noScheduleTrigger(let name):
            return "Workflow '\(name)' has no schedule trigger configured"
        case .invalidCronExpression(let cron, let reason):
            return "Invalid cron expression '\(cron)': \(reason)"
        case .loadFailed(let name, let output):
            return "Failed to load LaunchAgent for workflow '\(name)': \(output)"
        case .unloadFailed(let name, let output):
            return "Failed to unload LaunchAgent for workflow '\(name)': \(output)"
        }
    }
}
