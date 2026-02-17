import Foundation
import Testing
@testable import ReadOutMacApp
@testable import ReadOutPersistence

private func uniqueDiagnosticsTempDirectoryURL(_ suffix: String) -> URL {
    let id = UUID().uuidString
    return FileManager.default.temporaryDirectory
        .appendingPathComponent("readout-diagnostics-tests-\(id)-\(suffix)", isDirectory: true)
}

private func runCommand(_ executablePath: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = arguments

    let stdout = Pipe()
    process.standardOutput = stdout
    process.standardError = stdout

    try process.run()
    process.waitUntilExit()

    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    return (process.terminationStatus, output)
}

@Test
func redactedConfigurationDataMasksPortsAndPaths() throws {
    let service = DiagnosticsBundleService()

    var config = AppConfiguration()
    config.multimeterPort = "/dev/cu.usbserial-VERY-PRIVATE"
    config.usbcPort = "SIM_USBC"
    config.multimeterOutputFile = "/Users/alice/private/multimeter_output.txt"
    config.usbcCsvLogFilePath = "/Users/alice/private/usbc.csv"

    let data = try service.redactedConfigurationData(for: config)
    let text = String(decoding: data, as: UTF8.self)

    #expect(text.contains("<redacted-port>"))
    #expect(text.contains("\"SIM_USBC\""))
    #expect(text.contains("<redacted-path:multimeter_output.txt>"))
    #expect(text.contains("<redacted-path:usbc.csv>"))
    #expect(text.contains("usbserial-VERY-PRIVATE") == false)
    #expect(text.contains("/Users/alice/private/multimeter_output.txt") == false)
}

@Test
func exportBundleCreatesZipWithManifestAndDeterministicFiles() throws {
    let service = DiagnosticsBundleService()
    var config = AppConfiguration()
    config.useSimulator = true

    let destination = uniqueDiagnosticsTempDirectoryURL("export")
        .appendingPathComponent("diagnostics.zip")

    let input = DiagnosticsBundleInput(
        exportedAt: Date(timeIntervalSince1970: 1_000),
        configuration: config,
        runtimeLogs: [
            RuntimeLogEntry(timestamp: Date(timeIntervalSince1970: 900), level: .info, message: "ready")
        ],
        healthSnapshots: [
            RuntimeHealthSnapshot(
                timestamp: Date(timeIntervalSince1970: 901),
                reason: "test",
                isRuntimeActive: false,
                multimeterStatus: .disconnected,
                usbcStatus: .disconnected,
                reconnectCount: 0,
                runtimeErrorCount: 0,
                parseErrorCount: 0,
                outputDropWarningCount: 0,
                runtimeLogCount: 1,
                statusMessage: "Ready"
            )
        ],
        connectionTimeline: [
            ConnectionTimelineEntry(
                timestamp: Date(timeIntervalSince1970: 899),
                device: "multimeter",
                state: .disconnected,
                message: "Disconnected"
            )
        ],
        multimeterStatus: .disconnected,
        usbcStatus: .disconnected,
        isRuntimeActive: false,
        statusMessage: "Disconnected"
    )

    try service.exportBundle(to: destination, input: input)
    #expect(FileManager.default.fileExists(atPath: destination.path))

    let listing = try runCommand("/usr/bin/unzip", ["-Z1", destination.path])
    #expect(listing.status == 0)
    #expect(listing.output.contains("manifest.json"))
    #expect(listing.output.contains("configuration_sanitized.json"))
    #expect(listing.output.contains("runtime_logs.log"))
    #expect(listing.output.contains("connection_timeline.json"))
    #expect(listing.output.contains("health_snapshots.json"))

    let manifestOutput = try runCommand("/usr/bin/unzip", ["-p", destination.path, "manifest.json"])
    #expect(manifestOutput.status == 0)

    let manifestData = Data(manifestOutput.output.utf8)
    let manifestObject = try #require(
        JSONSerialization.jsonObject(with: manifestData, options: []) as? [String: Any]
    )

    #expect(manifestObject["runtimeActive"] as? Bool == false)
    #expect(manifestObject["multimeterStatus"] as? String == "disconnected")
    #expect(manifestObject["usbcStatus"] as? String == "disconnected")
}
