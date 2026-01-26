import Foundation
import Combine
import AgentManagerCore

@MainActor
class LogBrowserViewModel: ObservableObject {
    @Published var logs: [LogEntry] = []
    @Published var selectedLog: LogEntry?
    @Published var logContent: String = ""
    @Published var isFollowing = false
    @Published var errorMessage: String?

    private var logFollower: LogFollower?
    private var followTask: Task<Void, Never>?
    private let logManager = LogManager.shared

    var agentName: String = "" {
        didSet {
            loadLogs()
        }
    }

    func loadLogs() {
        guard !agentName.isEmpty else {
            logs = []
            return
        }

        do {
            logs = try logManager.listLogs(agentName: agentName)
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load logs: \(error.localizedDescription)"
            logs = []
        }
    }

    func selectLog(_ entry: LogEntry) {
        stopFollowing()
        selectedLog = entry

        do {
            logContent = try logManager.readLog(at: entry.url)
            errorMessage = nil
        } catch {
            errorMessage = "Failed to read log: \(error.localizedDescription)"
            logContent = ""
        }
    }

    func startFollowing() {
        guard let log = selectedLog else { return }

        stopFollowing()
        isFollowing = true

        do {
            logFollower = try logManager.followLog(at: log.url)

            followTask = Task {
                var lines: [String] = []

                for await line in logFollower!.lines() {
                    if Task.isCancelled { break }
                    lines.append(line)

                    await MainActor.run {
                        self.logContent = lines.joined(separator: "\n")
                    }
                }
            }
        } catch {
            errorMessage = "Failed to follow log: \(error.localizedDescription)"
            isFollowing = false
        }
    }

    func stopFollowing() {
        followTask?.cancel()
        followTask = nil
        logFollower?.stop()
        logFollower = nil
        isFollowing = false
    }

    func deleteLog(_ entry: LogEntry) {
        do {
            try FileManager.default.removeItem(at: entry.url)

            if selectedLog?.url == entry.url {
                selectedLog = nil
                logContent = ""
            }

            loadLogs()
        } catch {
            errorMessage = "Failed to delete log: \(error.localizedDescription)"
        }
    }

    func deleteAllLogs() {
        do {
            try logManager.deleteAllLogs(agentName: agentName)
            selectedLog = nil
            logContent = ""
            loadLogs()
        } catch {
            errorMessage = "Failed to delete logs: \(error.localizedDescription)"
        }
    }
}
