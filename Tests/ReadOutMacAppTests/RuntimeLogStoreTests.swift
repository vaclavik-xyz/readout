import Foundation
import Testing
@testable import ReadOutMacApp

private func uniqueTempDirectoryURL(_ suffix: String) -> URL {
    let id = UUID().uuidString
    return FileManager.default.temporaryDirectory
        .appendingPathComponent("readout-runtime-log-tests-\(id)-\(suffix)", isDirectory: true)
}

private func makeMessage(index: Int, payloadSize: Int = 120) -> String {
    "entry-\(index)-" + String(repeating: "x", count: payloadSize)
}

private func makeEntry(index: Int, level: RuntimeLogLevel = .info) -> RuntimeLogEntry {
    RuntimeLogEntry(
        timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
        level: level,
        message: makeMessage(index: index)
    )
}

@Test
func loadRecentReturnsNewestEntriesInOrder() async throws {
    let logDirectoryURL = uniqueTempDirectoryURL("load-recent")
    let store = RuntimeLogStore(logDirectoryURL: logDirectoryURL, maxFileSizeBytes: 512, maxFiles: 4)

    for index in 0..<20 {
        try await store.append(makeEntry(index: index))
    }

    let recent = try await store.loadRecent(limit: 5)
    #expect(recent.count == 5)
    #expect(recent.map(\.message) == (15..<20).map { makeMessage(index: $0) })
}

@Test
func appendRotatesFilesWhenFileLimitIsReached() async throws {
    let logDirectoryURL = uniqueTempDirectoryURL("rotation")
    let store = RuntimeLogStore(logDirectoryURL: logDirectoryURL, maxFileSizeBytes: 350, maxFiles: 3)

    for index in 0..<40 {
        try await store.append(makeEntry(index: index))
    }

    let fileURLs = try FileManager.default.contentsOfDirectory(
        at: logDirectoryURL,
        includingPropertiesForKeys: nil
    )
    let runtimeFiles = fileURLs
        .map(\.lastPathComponent)
        .filter { $0.hasPrefix("runtime") && $0.hasSuffix(".log") }

    #expect(runtimeFiles.contains("runtime.log"))
    #expect(runtimeFiles.count <= 3)

    let newest = try await store.loadRecent(limit: 1)
    #expect(newest.first?.message == makeMessage(index: 39))
}

@Test
func exportAllWritesMetadataAndEntries() async throws {
    let logDirectoryURL = uniqueTempDirectoryURL("export")
    let store = RuntimeLogStore(logDirectoryURL: logDirectoryURL, maxFileSizeBytes: 512, maxFiles: 3)

    try await store.append(makeEntry(index: 1, level: .warning))
    try await store.append(makeEntry(index: 2, level: .error))

    let exportURL = uniqueTempDirectoryURL("export-out").appendingPathComponent("runtime-export.log")
    try await store.exportAll(
        to: exportURL,
        metadataLines: [
            "Environment: Tests",
            "Mode: Simulator"
        ]
    )

    let output = try String(contentsOf: exportURL, encoding: .utf8)
    #expect(output.contains("# readOut runtime log export"))
    #expect(output.contains("# Environment: Tests"))
    #expect(output.contains("[WARN] \(makeMessage(index: 1))"))
    #expect(output.contains("[ERROR] \(makeMessage(index: 2))"))
}

@Test
func clearAllRemovesPersistedLogs() async throws {
    let logDirectoryURL = uniqueTempDirectoryURL("clear")
    let store = RuntimeLogStore(logDirectoryURL: logDirectoryURL, maxFileSizeBytes: 512, maxFiles: 3)

    for index in 0..<8 {
        try await store.append(makeEntry(index: index))
    }

    try await store.clearAll()
    let remaining = try await store.loadRecent(limit: 100)
    #expect(remaining.isEmpty)
}
