import Foundation

public struct AgentRunner {
    public static let shared = AgentRunner()

    public init() {}

    /// Execute an agent
    public func run(agent: Agent, dryRun: Bool = false) throws -> RunResult {
        let startTime = Date()
        let logManager = LogManager.shared

        // Create log file
        let logFile = try logManager.createLogFile(agentName: agent.name)

        // Log header
        let header = """
            ================================================================================
            Agent: \(agent.name)
            Started: \(ISO8601DateFormatter().string(from: startTime))
            Working Directory: \(agent.expandedWorkingDirectory)
            Dry Run: \(dryRun)
            ================================================================================

            """
        try logManager.append(to: logFile, content: header)
        print(header, terminator: "")

        // Run context script if present
        var contextOutput = ""
        if let contextScript = agent.contextScript, !contextScript.isEmpty {
            let contextHeader = "--- Context Script Output ---\n"
            try logManager.append(to: logFile, content: contextHeader)
            print(contextHeader, terminator: "")

            do {
                contextOutput = try runContextScript(
                    contextScript,
                    workingDirectory: agent.expandedWorkingDirectory
                )
                try logManager.append(to: logFile, content: contextOutput + "\n")
                print(contextOutput)
            } catch {
                let errorMsg = "Context script failed: \(error.localizedDescription)\n"
                try logManager.append(to: logFile, content: errorMsg)
                print(errorMsg)
            }

            let contextFooter = "--- End Context Script ---\n\n"
            try logManager.append(to: logFile, content: contextFooter)
            print(contextFooter, terminator: "")
        }

        // Build the full prompt with context
        let fullPrompt = buildPrompt(agent: agent, contextOutput: contextOutput)

        if dryRun {
            let dryRunOutput = """
                --- DRY RUN ---
                Would execute claude with:
                  Working Directory: \(agent.expandedWorkingDirectory)
                  Max Turns: \(agent.maxTurns)
                  Max Budget: $\(String(format: "%.2f", agent.maxBudgetUSD))
                  Allowed Tools: \(agent.allowedTools.joined(separator: ", "))

                Full Prompt:
                \(fullPrompt)
                --- END DRY RUN ---

                """
            try logManager.append(to: logFile, content: dryRunOutput)
            print(dryRunOutput, terminator: "")

            let endTime = Date()
            return RunResult(
                success: true,
                startTime: startTime,
                endTime: endTime,
                logFile: logFile,
                dryRun: true
            )
        }

        // Execute claude
        let claudeHeader = "--- Claude Output ---\n"
        try logManager.append(to: logFile, content: claudeHeader)
        print(claudeHeader, terminator: "")

        let claudeOutput = try executeClaude(
            prompt: fullPrompt,
            workingDirectory: agent.expandedWorkingDirectory,
            allowedTools: agent.allowedTools,
            maxTurns: agent.maxTurns,
            maxBudget: agent.maxBudgetUSD,
            logFile: logFile
        )

        // Parse JSON response
        var resultText = claudeOutput
        var inputTokens: Int?
        var outputTokens: Int?
        var cost: Double?

        if let jsonData = claudeOutput.data(using: .utf8) {
            do {
                let response = try JSONDecoder().decode(ClaudeResponse.self, from: jsonData)
                resultText = response.result ?? claudeOutput
                inputTokens = response.inputTokens
                outputTokens = response.outputTokens
                cost = response.totalCostUsd

                // Log the parsed result nicely
                let totalTokens = (inputTokens ?? 0) + (outputTokens ?? 0)
                let parsedOutput = """

                    --- Parsed Result ---
                    \(resultText)
                    --- End Parsed Result ---

                    Tokens: \(totalTokens) total (\(inputTokens ?? 0) input, \(outputTokens ?? 0) output)
                    Cost: $\(String(format: "%.4f", cost ?? 0))

                    """
                try logManager.append(to: logFile, content: parsedOutput)
                print(parsedOutput, terminator: "")
            } catch {
                // JSON parsing failed, use raw output
                print("Note: Could not parse JSON response: \(error.localizedDescription)")
            }
        }

        let claudeFooter = "\n--- End Claude Output ---\n"
        try logManager.append(to: logFile, content: claudeFooter)
        print(claudeFooter, terminator: "")

        let endTime = Date()

        // Log footer
        let footer = """

            ================================================================================
            Completed: \(ISO8601DateFormatter().string(from: endTime))
            Duration: \(String(format: "%.1f", endTime.timeIntervalSince(startTime)))s
            ================================================================================

            """
        try logManager.append(to: logFile, content: footer)
        print(footer, terminator: "")

        // Record token usage if we got it
        if let input = inputTokens, let output = outputTokens {
            try? StatsManager.shared.recordRun(
                agentName: agent.name,
                inputTokens: input,
                outputTokens: output,
                cost: cost
            )
        }

        return RunResult(
            success: true,
            startTime: startTime,
            endTime: endTime,
            logFile: logFile,
            dryRun: false,
            claudeOutput: resultText,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cost: cost
        )
    }

    /// Build the full prompt including context
    private func buildPrompt(agent: Agent, contextOutput: String) -> String {
        var parts: [String] = []

        if !contextOutput.isEmpty {
            parts.append("<context>")
            parts.append(contextOutput.trimmingCharacters(in: .whitespacesAndNewlines))
            parts.append("</context>")
            parts.append("")
        }

        parts.append(agent.prompt)

        return parts.joined(separator: "\n")
    }

    /// Run the context script and capture output
    private func runContextScript(_ script: String, workingDirectory: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        // Set up environment with user's shell environment
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Execute claude CLI and return result with parsed stats
    private func executeClaude(
        prompt: String,
        workingDirectory: String,
        allowedTools: [String],
        maxTurns: Int,
        maxBudget: Double,
        logFile: URL
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")

        var args = ["claude", "--print", "--output-format", "json", prompt]

        // Add allowed tools
        for tool in allowedTools {
            args.append("--allowedTools")
            args.append(tool)
        }

        // Add budget limit
        args.append("--max-budget-usd")
        args.append(String(format: "%.2f", maxBudget))

        // Add max turns
        args.append("--max-turns")
        args.append(String(maxTurns))

        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        // Set up environment
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        process.environment = env

        // Capture output
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        // Log stderr if any
        if !errorData.isEmpty, let errorStr = String(data: errorData, encoding: .utf8) {
            try? LogManager.shared.append(to: logFile, content: "STDERR: \(errorStr)\n")
            print("STDERR: \(errorStr)")
        }

        if process.terminationStatus != 0 {
            throw AgentRunnerError.claudeExecutionFailed(Int(process.terminationStatus))
        }

        let outputString = String(data: outputData, encoding: .utf8) ?? ""

        // Log the raw output for debugging
        try? LogManager.shared.append(to: logFile, content: outputString)
        print(outputString)

        return outputString
    }
}

// MARK: - Claude JSON Response

struct ClaudeResponse: Codable {
    let result: String?
    let totalCostUsd: Double?
    let usage: ClaudeUsage?
    let durationMs: Int?
    let durationApiMs: Int?
    let numTurns: Int?

    enum CodingKeys: String, CodingKey {
        case result
        case totalCostUsd = "total_cost_usd"
        case usage
        case durationMs = "duration_ms"
        case durationApiMs = "duration_api_ms"
        case numTurns = "num_turns"
    }

    var inputTokens: Int? {
        guard let usage = usage else { return nil }
        // Sum all input token types
        return (usage.inputTokens ?? 0) +
               (usage.cacheCreationInputTokens ?? 0) +
               (usage.cacheReadInputTokens ?? 0)
    }

    var outputTokens: Int? {
        usage?.outputTokens
    }
}

struct ClaudeUsage: Codable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
    }
}

// MARK: - RunResult

public struct RunResult {
    public let success: Bool
    public let startTime: Date
    public let endTime: Date
    public let logFile: URL
    public let dryRun: Bool
    public var claudeOutput: String?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var cost: Double?

    public var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    public var totalTokens: Int? {
        guard let input = inputTokens, let output = outputTokens else { return nil }
        return input + output
    }
}

// MARK: - Errors

public enum AgentRunnerError: Error, LocalizedError {
    case claudeExecutionFailed(Int)
    case contextScriptFailed(String)

    public var errorDescription: String? {
        switch self {
        case .claudeExecutionFailed(let code):
            return "Claude execution failed with exit code \(code)"
        case .contextScriptFailed(let message):
            return "Context script failed: \(message)"
        }
    }
}
