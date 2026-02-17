import Foundation
import Testing
@testable import ReadOutPersistence

private func uniqueTempURL(_ suffix: String) -> URL {
    let base = FileManager.default.temporaryDirectory
    let id = UUID().uuidString
    return base.appendingPathComponent("readout-tests-\(id)-\(suffix)")
}

@Test
func loadMissingFileReturnsDefaults() async throws {
    let configURL = uniqueTempURL("config.json")
    let store = ConfigurationStore(configFileURL: configURL)

    let config = try await store.load()
    #expect(config.multimeterEnabled == true)
    #expect(config.usbcEnabled == false)
    #expect(config.sampleRateHz == 10)
}

@Test
func saveAndLoadRoundTrip() async throws {
    let configURL = uniqueTempURL("nested/config.json")
    let store = ConfigurationStore(configFileURL: configURL)

    var config = AppConfiguration()
    config.multimeterPort = "/dev/cu.usbserial-12345"
    config.usbcPort = "/dev/cu.usbmodem-42"
    config.multimeterOutputFile = "/tmp/mm.txt"
    config.usbcOutputFile = "/tmp/usbc.txt"
    config.shortThreshold = 1.2
    config.multimeterCsvLoggingEnabled = true
    config.multimeterCsvLogFilePath = "/tmp/mm.csv"

    try await store.save(config)
    let loaded = try await store.load()
    #expect(loaded == config)
}

@Test
func legacyKeysAreMigrated() throws {
    let legacy: [String: Any] = [
        "port": "/dev/cu.usbserial-legacy",
        "output_file": "/tmp/legacy_output.txt",
        "obs_custom_template": "VAL={value}",
        "value_label": "Legacy Label",
        "csv_logging_enabled": true,
        "csv_log_file_path": "/tmp/legacy.csv"
    ]

    let migrated = AppConfiguration.fromDictionary(legacy)
    #expect(migrated.multimeterPort == "/dev/cu.usbserial-legacy")
    #expect(migrated.multimeterOutputFile == "/tmp/legacy_output.txt")
    #expect(migrated.multimeterObsCustomTemplate == "VAL={value}")
    #expect(migrated.multimeterValueLabel == "Legacy Label")
    #expect(migrated.multimeterCsvLoggingEnabled == true)
    #expect(migrated.multimeterCsvLogFilePath == "/tmp/legacy.csv")
}

@Test
func numericValuesAreClampedOnLoad() throws {
    let raw: [String: Any] = [
        "sample_rate_hz": 0,
        "graph_history_seconds": 10_000,
        "short_threshold": -20.0,
        "pc_beep_volume": 4.0
    ]

    let migrated = AppConfiguration.fromDictionary(raw)
    #expect(migrated.sampleRateHz == 1)
    #expect(migrated.graphHistorySeconds == 600)
    #expect(migrated.shortThreshold == 0.1)
    #expect(migrated.pcBeepVolume == 1.0)
}
