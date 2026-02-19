import Foundation
import ReadOutPersistence

struct DiagnosticsBundleInput: Sendable {
    let exportedAt: Date
    let configuration: AppConfiguration
    let runtimeLogs: [RuntimeLogEntry]
    let healthSnapshots: [RuntimeHealthSnapshot]
    let connectionTimeline: [ConnectionTimelineEntry]
    let multimeterStatus: DeviceUIState
    let usbcStatus: DeviceUIState
    let isRuntimeActive: Bool
    let statusMessage: String
}

struct DiagnosticsManifest: Codable, Sendable {
    struct Counts: Codable, Sendable {
        let runtimeLogs: Int
        let healthSnapshots: Int
        let connectionTimelineEntries: Int
    }

    let generatedAt: Date
    let runtimeActive: Bool
    let multimeterStatus: String
    let usbcStatus: String
    let statusMessage: String
    let counts: Counts
    let files: [String]
}

enum DiagnosticsBundleError: Error {
    case zipToolMissing
    case zipFailed(code: Int32)
}

struct DiagnosticsBundleService {
    private let fileManager: FileManager
    private let zipExecutablePath: String

    init(
        fileManager: FileManager = .default,
        zipExecutablePath: String = "/usr/bin/zip"
    ) {
        self.fileManager = fileManager
        self.zipExecutablePath = zipExecutablePath
    }

    func exportBundle(to destinationURL: URL, input: DiagnosticsBundleInput) throws {
        let bundleDir = fileManager.temporaryDirectory
            .appendingPathComponent("readout-diagnostics-\(UUID().uuidString)", isDirectory: true)

        let files = [
            "manifest.json",
            "configuration_sanitized.json",
            "runtime_logs.log",
            "connection_timeline.json",
            "health_snapshots.json"
        ]

        try fileManager.createDirectory(at: bundleDir, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: bundleDir)
        }

        let manifest = DiagnosticsManifest(
            generatedAt: input.exportedAt,
            runtimeActive: input.isRuntimeActive,
            multimeterStatus: input.multimeterStatus.rawValue,
            usbcStatus: input.usbcStatus.rawValue,
            statusMessage: input.statusMessage,
            counts: .init(
                runtimeLogs: input.runtimeLogs.count,
                healthSnapshots: input.healthSnapshots.count,
                connectionTimelineEntries: input.connectionTimeline.count
            ),
            files: files
        )

        try writeJSON(
            manifest,
            to: bundleDir.appendingPathComponent("manifest.json")
        )

        try redactedConfigurationData(for: input.configuration)
            .write(to: bundleDir.appendingPathComponent("configuration_sanitized.json"), options: .atomic)

        try renderRuntimeLogText(input.runtimeLogs)
            .write(to: bundleDir.appendingPathComponent("runtime_logs.log"), atomically: true, encoding: .utf8)

        try writeJSON(
            input.connectionTimeline,
            to: bundleDir.appendingPathComponent("connection_timeline.json")
        )

        try writeJSON(
            input.healthSnapshots,
            to: bundleDir.appendingPathComponent("health_snapshots.json")
        )

        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try zip(directory: bundleDir, files: files, destinationURL: destinationURL)
    }

    func redactedConfigurationData(for configuration: AppConfiguration) throws -> Data {
        let encoded = try JSONEncoder().encode(configuration)
        var dictionary = (try JSONSerialization.jsonObject(with: encoded) as? [String: Any]) ?? [:]
        let sensitivePathKeys: Set<String> = [
            "multimeter_output_file",
            "usbc_output_file",
            "multimeter_csv_log_file_path",
            "usbc_csv_log_file_path"
        ]
        let sensitivePortKeys: Set<String> = ["multimeter_port", "usbc_port"]

        for key in sensitivePortKeys {
            if let value = dictionary[key] as? String {
                dictionary[key] = redactedPort(value)
            }
        }

        for key in sensitivePathKeys {
            if let value = dictionary[key] as? String {
                dictionary[key] = redactedPath(value)
            }
        }

        return try JSONSerialization.data(withJSONObject: dictionary, options: [.prettyPrinted, .sortedKeys])
    }

    private func redactedPort(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            return ""
        }
        if value.hasPrefix("SIM_") {
            return value
        }
        return "<redacted-port>"
    }

    private func redactedPath(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            return ""
        }
        return "<redacted-path:\(URL(fileURLWithPath: value).lastPathComponent)>"
    }

    private func renderRuntimeLogText(_ entries: [RuntimeLogEntry]) -> String {
        var output = "# readOut runtime logs\n"
        let formatter = ISO8601DateFormatter()

        for entry in entries {
            let ts = formatter.string(from: entry.timestamp)
            output += "[\(ts)] [\(entry.level.rawValue)] \(entry.message)\n"
        }

        return output
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private func zip(directory: URL, files: [String], destinationURL: URL) throws {
        guard fileManager.isExecutableFile(atPath: zipExecutablePath) else {
            throw DiagnosticsBundleError.zipToolMissing
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: zipExecutablePath)
        process.currentDirectoryURL = directory
        process.arguments = ["-X", "-q", destinationURL.path] + files

        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw DiagnosticsBundleError.zipFailed(code: process.terminationStatus)
        }
    }
}
