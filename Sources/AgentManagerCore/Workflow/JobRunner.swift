import Foundation

/// Runs a single job within a workflow
public struct JobRunner {
    public static let shared = JobRunner()

    private let agentRunner = AgentRunner.shared
    private let agentStore = AgentStore.shared
    private let outputExtractor = OutputExtractor()
    private let expressionEvaluator = ExpressionEvaluator()

    public init() {}

    /// Run a single job
    /// - Parameters:
    ///   - jobName: The name of the job
    ///   - job: The job definition
    ///   - workflow: The parent workflow
    ///   - context: The expression evaluation context (with outputs from previous jobs)
    ///   - logDirectory: Directory to store job logs
    ///   - dryRun: If true, don't actually execute Claude
    /// - Returns: The job result with outputs
    public func run(
        jobName: String,
        job: Job,
        workflow: Workflow,
        context: ExpressionEvaluator.Context,
        logDirectory: URL,
        dryRun: Bool = false
    ) throws -> JobResult {
        var result = JobResult(jobName: jobName)
        result.markStarted()

        // Evaluate conditional if present
        if let condition = job.if {
            do {
                let shouldRun = try expressionEvaluator.evaluate(condition, context: context)
                if !shouldRun {
                    result.markSkipped(reason: "Condition '\(condition)' evaluated to false")
                    return result
                }
            } catch {
                result.markFailed(error: "Failed to evaluate condition: \(error.localizedDescription)")
                return result
            }
        }

        // Get the prompt (either from agent reference or inline)
        let prompt: String
        let allowedTools: [String]
        let maxTurns: Int
        let maxBudget: Double
        let workingDirectory: String
        var contextScript: String?

        if let agentName = job.agent {
            // Load the referenced agent template
            do {
                let agent = try agentStore.load(name: agentName)
                prompt = agent.prompt
                allowedTools = job.allowedTools ?? agent.allowedTools
                maxTurns = job.maxTurns ?? agent.maxTurns
                maxBudget = job.maxBudgetUSD ?? agent.maxBudgetUSD
                workingDirectory = job.workingDirectory ?? agent.workingDirectory
                contextScript = job.contextScript ?? agent.contextScript
            } catch {
                result.markFailed(error: "Failed to load agent '\(agentName)': \(error.localizedDescription)")
                return result
            }
        } else if let inlinePrompt = job.prompt {
            prompt = inlinePrompt
            allowedTools = workflow.allowedTools(for: jobName)
            maxTurns = workflow.maxTurns(for: jobName)
            maxBudget = workflow.maxBudget(for: jobName)
            workingDirectory = workflow.workingDirectory(for: jobName)
            contextScript = job.contextScript
        } else {
            result.markFailed(error: "Job has neither 'agent' nor 'prompt' defined")
            return result
        }

        // Interpolate expressions in the prompt
        let interpolatedPrompt: String
        do {
            interpolatedPrompt = try expressionEvaluator.interpolate(prompt, context: context)
        } catch {
            result.markFailed(error: "Failed to interpolate prompt: \(error.localizedDescription)")
            return result
        }

        // Add output instructions if outputs are declared
        let finalPrompt: String
        if let outputs = job.outputs, !outputs.isEmpty {
            finalPrompt = interpolatedPrompt + OutputExtractor.outputInstructions(for: outputs)
        } else {
            finalPrompt = interpolatedPrompt
        }

        // Create a temporary agent for execution
        let tempAgent = Agent(
            name: "\(workflow.name).\(jobName)",
            description: "Job '\(jobName)' in workflow '\(workflow.name)'",
            trigger: Trigger(type: .manual),
            workingDirectory: workingDirectory,
            contextScript: contextScript,
            prompt: finalPrompt,
            allowedTools: allowedTools,
            maxTurns: maxTurns,
            maxBudgetUSD: maxBudget
        )

        // Ensure log directory exists
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)

        // Execute the job
        do {
            let runResult = try agentRunner.run(agent: tempAgent, dryRun: dryRun)

            result.logFile = runResult.logFile
            result.updateStats(
                inputTokens: runResult.inputTokens,
                outputTokens: runResult.outputTokens,
                cost: runResult.cost
            )

            // Extract outputs from the response
            if let claudeOutput = runResult.claudeOutput {
                result.claudeOutput = claudeOutput

                if let declaredOutputs = job.outputs {
                    let extractedOutputs = outputExtractor.extract(from: claudeOutput, declaredOutputs: declaredOutputs)
                    result.markCompleted(outputs: extractedOutputs, claudeOutput: claudeOutput)
                } else {
                    result.markCompleted(claudeOutput: claudeOutput)
                }
            } else {
                result.markCompleted()
            }

            return result
        } catch {
            result.markFailed(error: error.localizedDescription)
            return result
        }
    }

    /// Run a job synchronously with context from a workflow run
    public func run(
        jobName: String,
        workflow: Workflow,
        workflowRun: WorkflowRun,
        logDirectory: URL,
        dryRun: Bool = false
    ) throws -> JobResult {
        guard let job = workflow.jobs[jobName] else {
            var result = JobResult(jobName: jobName)
            result.markFailed(error: "Job '\(jobName)' not found in workflow")
            return result
        }

        // Build context from completed jobs
        var context = ExpressionEvaluator.Context()
        for (name, jobResult) in workflowRun.jobResults {
            context.setOutputs(job: name, outputs: jobResult.outputs)
            context.setStatus(job: name, status: jobResult.status.rawValue)
        }

        return try run(
            jobName: jobName,
            job: job,
            workflow: workflow,
            context: context,
            logDirectory: logDirectory,
            dryRun: dryRun
        )
    }
}

// MARK: - Job Runner Errors

public enum JobRunnerError: Error, LocalizedError {
    case jobNotFound(String)
    case agentNotFound(String)
    case conditionEvaluationFailed(String)
    case executionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .jobNotFound(let name):
            return "Job '\(name)' not found"
        case .agentNotFound(let name):
            return "Agent '\(name)' not found"
        case .conditionEvaluationFailed(let message):
            return "Condition evaluation failed: \(message)"
        case .executionFailed(let message):
            return "Job execution failed: \(message)"
        }
    }
}
