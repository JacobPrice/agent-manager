import Foundation

public struct LogManager {
    public static let shared = LogManager()

    private let store = AgentStore.shared
    private let dateFormatter: DateFormatter

    public init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
    }

    /// Get the log directory for an agent
    public func logDirectory(agentName: String) -> URL {
        store.logDirectory(agentName: agentName)
    }

    /// Create a new log file for a run
    public func createLogFile(agentName: String) throws -> URL {
        let logDir = logDirectory(agentName: agentName)
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        let timestamp = dateFormatter.string(from: Date())
        let logFile = logDir.appendingPathComponent("\(timestamp).log")

        // Create empty file
        FileManager.default.createFile(atPath: logFile.path, contents: nil)

        return logFile
    }

    /// Append content to a log file
    public func append(to logFile: URL, content: String) throws {
        let handle = try FileHandle(forWritingTo: logFile)
        defer { try? handle.close() }

        handle.seekToEndOfFile()
        if let data = content.data(using: .utf8) {
            handle.write(data)
        }
    }

    /// List all log files for an agent
    public func listLogs(agentName: String) throws -> [LogEntry] {
        let logDir = logDirectory(agentName: agentName)

        guard FileManager.default.fileExists(atPath: logDir.path) else {
            return []
        }

        let files = try FileManager.default.contentsOfDirectory(at: logDir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])

        return files
            .filter { $0.pathExtension == "log" }
            .compactMap { url -> LogEntry? in
                let filename = url.deletingPathExtension().lastPathComponent
                guard let date = dateFormatter.date(from: filename) else { return nil }

                let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                let size = attrs?[.size] as? Int ?? 0

                return LogEntry(url: url, date: date, size: size)
            }
            .sorted { $0.date > $1.date } // Most recent first
    }

    /// Get the most recent log file for an agent
    public func latestLog(agentName: String) throws -> LogEntry? {
        try listLogs(agentName: agentName).first
    }

    /// Get the date of the last run
    public func lastRunDate(agentName: String) throws -> Date? {
        try latestLog(agentName: agentName)?.date
    }

    /// Read contents of a log file
    public func readLog(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    /// Read the last N lines of a log file
    public func tailLog(at url: URL, lines: Int) throws -> String {
        let content = try readLog(at: url)
        let allLines = content.components(separatedBy: .newlines)

        if allLines.count <= lines {
            return content
        }

        return allLines.suffix(lines).joined(separator: "\n")
    }

    /// Read and follow a log file (returns an AsyncSequence)
    public func followLog(at url: URL) throws -> LogFollower {
        LogFollower(url: url)
    }

    /// Delete old logs for an agent, keeping the most recent N
    public func pruneOldLogs(agentName: String, keepCount: Int = 10) throws {
        let logs = try listLogs(agentName: agentName)

        guard logs.count > keepCount else { return }

        let logsToDelete = logs.suffix(from: keepCount)
        for log in logsToDelete {
            try FileManager.default.removeItem(at: log.url)
        }
    }

    /// Delete all logs for an agent
    public func deleteAllLogs(agentName: String) throws {
        let logDir = logDirectory(agentName: agentName)
        if FileManager.default.fileExists(atPath: logDir.path) {
            try FileManager.default.removeItem(at: logDir)
        }
    }
}

// MARK: - LogEntry

public struct LogEntry {
    public let url: URL
    public let date: Date
    public let size: Int

    public var filename: String {
        url.lastPathComponent
    }

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

// MARK: - LogFollower

public class LogFollower {
    private let url: URL
    private var fileHandle: FileHandle?
    private var source: DispatchSourceFileSystemObject?
    private var lastPosition: UInt64 = 0
    private var continuation: AsyncStream<String>.Continuation?

    public init(url: URL) {
        self.url = url
    }

    public func lines() -> AsyncStream<String> {
        AsyncStream { continuation in
            self.continuation = continuation

            do {
                // Read existing content first
                if let existing = try? String(contentsOf: url, encoding: .utf8) {
                    for line in existing.components(separatedBy: .newlines) {
                        continuation.yield(line)
                    }
                }

                // Open file for monitoring
                fileHandle = try FileHandle(forReadingFrom: url)
                lastPosition = fileHandle?.seekToEndOfFile() ?? 0

                // Set up file system monitoring
                let fd = fileHandle!.fileDescriptor
                source = DispatchSource.makeFileSystemObjectSource(
                    fileDescriptor: fd,
                    eventMask: [.write, .extend],
                    queue: .global()
                )

                source?.setEventHandler { [weak self] in
                    self?.readNewContent()
                }

                source?.setCancelHandler { [weak self] in
                    try? self?.fileHandle?.close()
                    self?.fileHandle = nil
                }

                source?.resume()

            } catch {
                continuation.finish()
            }

            continuation.onTermination = { [weak self] _ in
                self?.stop()
            }
        }
    }

    private func readNewContent() {
        guard let handle = fileHandle else { return }

        handle.seek(toFileOffset: lastPosition)
        let newData = handle.readDataToEndOfFile()
        lastPosition = handle.offsetInFile

        if let str = String(data: newData, encoding: .utf8) {
            for line in str.components(separatedBy: .newlines) {
                continuation?.yield(line)
            }
        }
    }

    public func stop() {
        source?.cancel()
        source = nil
        continuation?.finish()
    }
}
