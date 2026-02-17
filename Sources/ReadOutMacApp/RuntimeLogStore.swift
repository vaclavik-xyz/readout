import Foundation

actor RuntimeLogStore {
    private struct PersistentLogLine: Codable {
        let timestamp: TimeInterval
        let level: String
        let message: String
    }

    private let logDirectoryURL: URL
    private let maxFileSizeBytes: Int
    private let maxFiles: Int
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        logDirectoryURL: URL,
        maxFileSizeBytes: Int = 128 * 1024,
        maxFiles: Int = 5,
        fileManager: FileManager = .default
    ) {
        self.logDirectoryURL = logDirectoryURL
        self.maxFileSizeBytes = max(1, maxFileSizeBytes)
        self.maxFiles = max(2, maxFiles)
        self.fileManager = fileManager
    }

    func append(_ entry: RuntimeLogEntry) throws {
        try ensureLogDirectory()

        let line = PersistentLogLine(
            timestamp: entry.timestamp.timeIntervalSince1970,
            level: entry.level.rawValue,
            message: entry.message
        )

        var encoded = try encoder.encode(line)
        encoded.append(0x0A)

        let currentURL = currentLogFileURL()
        let projectedSize = try currentFileSize(at: currentURL) + encoded.count
        if projectedSize > maxFileSizeBytes {
            try rotateFiles()
        }

        if !fileManager.fileExists(atPath: currentURL.path) {
            fileManager.createFile(atPath: currentURL.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: currentURL)
        defer { try? handle.close() }

        try handle.seekToEnd()
        try handle.write(contentsOf: encoded)
        try handle.synchronize()
    }

    func loadRecent(limit: Int) throws -> [RuntimeLogEntry] {
        let entries = try loadAllEntries()
        let safeLimit = max(0, limit)
        if entries.count <= safeLimit {
            return entries
        }
        return Array(entries.suffix(safeLimit))
    }

    func exportAll(to destinationURL: URL, metadataLines: [String]) throws {
        let entries = try loadAllEntries()

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var output = "# readOut runtime log export\n"
        for line in metadataLines {
            output += "# \(line)\n"
        }
        output += "\n"

        let formatter = ISO8601DateFormatter()
        for entry in entries {
            let ts = formatter.string(from: entry.timestamp)
            output += "[\(ts)] [\(entry.level.rawValue)] \(entry.message)\n"
        }

        try output.write(to: destinationURL, atomically: true, encoding: .utf8)
    }

    func clearAll() throws {
        let urls = try existingLogFileURLs()
        for url in urls {
            try fileManager.removeItem(at: url)
        }
    }

    private func currentLogFileURL() -> URL {
        logDirectoryURL.appendingPathComponent("runtime.log")
    }

    private func rotatedLogFileURL(index: Int) -> URL {
        logDirectoryURL.appendingPathComponent("runtime.\(index).log")
    }

    private func ensureLogDirectory() throws {
        try fileManager.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)
    }

    private func currentFileSize(at url: URL) throws -> Int {
        guard fileManager.fileExists(atPath: url.path) else {
            return 0
        }

        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return values.fileSize ?? 0
    }

    private func rotateFiles() throws {
        let oldest = rotatedLogFileURL(index: maxFiles - 1)
        if fileManager.fileExists(atPath: oldest.path) {
            try? fileManager.removeItem(at: oldest)
        }

        if maxFiles > 2 {
            for index in stride(from: maxFiles - 2, through: 1, by: -1) {
                let source = rotatedLogFileURL(index: index)
                let destination = rotatedLogFileURL(index: index + 1)

                if fileManager.fileExists(atPath: source.path) {
                    if fileManager.fileExists(atPath: destination.path) {
                        try? fileManager.removeItem(at: destination)
                    }
                    try fileManager.moveItem(at: source, to: destination)
                }
            }
        }

        let current = currentLogFileURL()
        let firstRotated = rotatedLogFileURL(index: 1)
        if fileManager.fileExists(atPath: current.path) {
            if fileManager.fileExists(atPath: firstRotated.path) {
                try? fileManager.removeItem(at: firstRotated)
            }
            try fileManager.moveItem(at: current, to: firstRotated)
        }
    }

    private func existingLogFileURLs() throws -> [URL] {
        try ensureLogDirectory()

        var urls: [URL] = []

        for index in stride(from: maxFiles - 1, through: 1, by: -1) {
            let candidate = rotatedLogFileURL(index: index)
            if fileManager.fileExists(atPath: candidate.path) {
                urls.append(candidate)
            }
        }

        let current = currentLogFileURL()
        if fileManager.fileExists(atPath: current.path) {
            urls.append(current)
        }

        return urls
    }

    private func loadAllEntries() throws -> [RuntimeLogEntry] {
        var entries: [RuntimeLogEntry] = []

        for url in try existingLogFileURLs() {
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else {
                continue
            }

            for line in text.split(separator: "\n") {
                guard let lineData = line.data(using: .utf8) else {
                    continue
                }

                guard let decoded = try? decoder.decode(PersistentLogLine.self, from: lineData) else {
                    continue
                }

                guard let level = RuntimeLogLevel(rawValue: decoded.level) else {
                    continue
                }

                entries.append(
                    RuntimeLogEntry(
                        timestamp: Date(timeIntervalSince1970: decoded.timestamp),
                        level: level,
                        message: decoded.message
                    )
                )
            }
        }

        return entries.sorted { $0.timestamp < $1.timestamp }
    }
}
