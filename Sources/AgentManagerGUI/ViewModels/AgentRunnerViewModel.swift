import Foundation
import Combine
import AgentManagerCore

@MainActor
class AgentRunnerViewModel: ObservableObject {
    @Published var isRunning = false
    @Published var isDryRun = false
    @Published var outputLines: [String] = []
    @Published var runResult: RunResult?
    @Published var errorMessage: String?

    private var runTask: Task<Void, Never>?
    private var logFollower: LogFollower?

    func run(agent: Agent) {
        guard !isRunning else { return }

        isRunning = true
        outputLines = []
        runResult = nil
        errorMessage = nil

        runTask = Task {
            do {
                let result = try AgentRunner.shared.run(agent: agent, dryRun: isDryRun)

                await MainActor.run {
                    self.runResult = result
                    self.isRunning = false
                }

                // Read the final log content
                if let content = try? LogManager.shared.readLog(at: result.logFile) {
                    await MainActor.run {
                        self.outputLines = content.components(separatedBy: .newlines)
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Run failed: \(error.localizedDescription)"
                    self.isRunning = false
                }
            }
        }
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
        logFollower?.stop()
        logFollower = nil
        isRunning = false
    }

    func clear() {
        outputLines = []
        runResult = nil
        errorMessage = nil
    }
}
