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

    #expect(await store.hasPersistedConfiguration() == false)
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
    config.dashboardDeviceVisibility = .usbc
    config.dashboardTheme = .dark
    config.runtimeLogPanelVisible = false
    config.runtimeLogCaptureEnabled = false
    config.dashboardBeepMasterEnabled = false
    config.pcBeepSoundPreset = .sosumi
    config.multimeterPopoutMode = .mini
    config.usbcPopoutMode = .compact
    config.multimeterPopoutFrame = .init(x: 120, y: 160, width: 480, height: 260)
    config.usbcPopoutFrame = .init(x: 640, y: 200, width: 500, height: 280)

    try await store.save(config)
    #expect(await store.hasPersistedConfiguration() == true)
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
        "output_queue_capacity": 4,
        "output_queue_max_retry_attempts": 99,
        "short_threshold": -20.0,
        "pc_beep_volume": 4.0
    ]

    let migrated = AppConfiguration.fromDictionary(raw)
    #expect(migrated.sampleRateHz == 1)
    #expect(migrated.graphHistorySeconds == 600)
    #expect(migrated.outputQueueCapacity == 8)
    #expect(migrated.outputQueueMaxRetryAttempts == 10)
    #expect(migrated.shortThreshold == 0.1)
    #expect(migrated.pcBeepVolume == 1.0)
}

@Test
func unknownDashboardEnumValuesFallbackToDefaults() throws {
    let raw: [String: Any] = [
        "dashboard_device_visibility": "unknown-mode",
        "dashboard_theme": "alien",
        "pc_beep_sound_preset": "custom",
        "multimeter_popout_mode": "x-mode",
        "usbc_popout_mode": "y-mode",
        "multimeter_popout_x": 100,
        "multimeter_popout_y": 100,
        "multimeter_popout_width": -10,
        "multimeter_popout_height": 80
    ]

    let migrated = AppConfiguration.fromDictionary(raw)
    #expect(migrated.dashboardDeviceVisibility == .both)
    #expect(migrated.dashboardTheme == .system)
    #expect(migrated.pcBeepSoundPreset == .system)
    #expect(migrated.multimeterPopoutMode == .detailed)
    #expect(migrated.usbcPopoutMode == .detailed)
    #expect(migrated.multimeterPopoutFrame == nil)
    #expect(migrated.usbcPopoutFrame == nil)
}
