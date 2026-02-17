import Foundation

public struct AppConfiguration: Sendable, Equatable {
    public enum ObsOutputMode: String, Sendable, Equatable, Codable {
        case valueOnly = "VALUE_ONLY"
        case valueAndUnit = "VALUE_AND_UNIT"
        case customTemplate = "CUSTOM_TEMPLATE"
    }

    public enum DashboardDeviceVisibility: String, Sendable, Equatable, Codable, CaseIterable {
        case both = "both"
        case multimeter = "multimeter"
        case usbc = "usbc"
    }

    public enum DashboardTheme: String, Sendable, Equatable, Codable, CaseIterable {
        case system = "system"
        case light = "light"
        case dark = "dark"
    }

    public enum MacAlertSoundPreset: String, Sendable, Equatable, Codable, CaseIterable {
        case system = "system"
        case glass = "glass"
        case sosumi = "sosumi"
        case funk = "funk"
    }

    public enum PopoutDisplayMode: String, Sendable, Equatable, Codable, CaseIterable {
        case mini = "mini"
        case compact = "compact"
        case detailed = "detailed"
    }

    public var multimeterPort: String = ""
    public var usbcPort: String = ""
    public var multimeterEnabled: Bool = true
    public var usbcEnabled: Bool = false
    public var multimeterAutoReconnect: Bool = true
    public var usbcAutoReconnect: Bool = true
    public var useSimulator: Bool = false

    public var sampleRateHz: Int = 10
    public var graphHistorySeconds: Int = 30
    public var outputQueueCapacity: Int = 256
    public var outputQueueMaxRetryAttempts: Int = 3

    public var shortThreshold: Double = 2.0
    public var beepOnShortMeter: Bool = false
    public var beepOnShortPC: Bool = false
    public var pcBeepVolume: Double = 0.5

    public var dcvHighAlarmEnabled: Bool = false
    public var dcvHighAlarmValue: Double = 12.0
    public var dcvLowAlarmEnabled: Bool = false
    public var dcvLowAlarmValue: Double = 0.0
    public var beepOnAlarm: Bool = false

    public var multimeterOutputFile: String = ""
    public var usbcOutputFile: String = ""
    public var multimeterObsOutputMode: ObsOutputMode = .valueAndUnit
    public var usbcObsOutputMode: ObsOutputMode = .valueAndUnit
    public var multimeterObsCustomTemplate: String = "{value} {unit}"
    public var usbcObsCustomTemplate: String = "{voltage} {current} {power}"
    public var multimeterValueLabel: String = ""
    public var usbcValueLabel: String = ""

    public var multimeterCsvLoggingEnabled: Bool = false
    public var usbcCsvLoggingEnabled: Bool = false
    public var multimeterCsvLogFilePath: String = ""
    public var usbcCsvLogFilePath: String = ""

    public var dashboardDeviceVisibility: DashboardDeviceVisibility = .both
    public var dashboardTheme: DashboardTheme = .system
    public var runtimeLogPanelVisible: Bool = true
    public var runtimeLogCaptureEnabled: Bool = true
    public var dashboardBeepMasterEnabled: Bool = true
    public var pcBeepSoundPreset: MacAlertSoundPreset = .system
    public var multimeterPopoutMode: PopoutDisplayMode = .detailed
    public var usbcPopoutMode: PopoutDisplayMode = .detailed

    public init() {}

    public static func fromJSONData(_ data: Data) throws -> AppConfiguration {
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = object as? [String: Any] else {
            throw ConfigurationStoreError.invalidFormat
        }
        return fromDictionary(dictionary)
    }

    public static func fromDictionary(_ data: [String: Any]) -> AppConfiguration {
        var config = AppConfiguration()

        func string(_ key: String, default defaultValue: String) -> String {
            data[key] as? String ?? defaultValue
        }
        func bool(_ key: String, default defaultValue: Bool) -> Bool {
            data[key] as? Bool ?? defaultValue
        }
        func int(_ key: String, default defaultValue: Int) -> Int {
            data[key] as? Int ?? defaultValue
        }
        func double(_ key: String, default defaultValue: Double) -> Double {
            if let d = data[key] as? Double {
                return d
            }
            if let i = data[key] as? Int {
                return Double(i)
            }
            return defaultValue
        }
        func obsMode(_ key: String, default defaultValue: ObsOutputMode) -> ObsOutputMode {
            guard let raw = data[key] as? String else {
                return defaultValue
            }
            return ObsOutputMode(rawValue: raw.uppercased()) ?? defaultValue
        }
        func dashboardVisibility(_ key: String, default defaultValue: DashboardDeviceVisibility) -> DashboardDeviceVisibility {
            guard let raw = data[key] as? String else {
                return defaultValue
            }
            return DashboardDeviceVisibility(rawValue: raw.lowercased()) ?? defaultValue
        }
        func dashboardTheme(_ key: String, default defaultValue: DashboardTheme) -> DashboardTheme {
            guard let raw = data[key] as? String else {
                return defaultValue
            }
            return DashboardTheme(rawValue: raw.lowercased()) ?? defaultValue
        }
        func soundPreset(_ key: String, default defaultValue: MacAlertSoundPreset) -> MacAlertSoundPreset {
            guard let raw = data[key] as? String else {
                return defaultValue
            }
            return MacAlertSoundPreset(rawValue: raw.lowercased()) ?? defaultValue
        }
        func popoutDisplayMode(_ key: String, default defaultValue: PopoutDisplayMode) -> PopoutDisplayMode {
            guard let raw = data[key] as? String else {
                return defaultValue
            }
            return PopoutDisplayMode(rawValue: raw.lowercased()) ?? defaultValue
        }

        config.multimeterPort = string("multimeter_port", default: config.multimeterPort)
        config.usbcPort = string("usbc_port", default: config.usbcPort)
        config.multimeterEnabled = bool("multimeter_enabled", default: config.multimeterEnabled)
        config.usbcEnabled = bool("usbc_enabled", default: config.usbcEnabled)
        config.multimeterAutoReconnect = bool("multimeter_auto_reconnect", default: config.multimeterAutoReconnect)
        config.usbcAutoReconnect = bool("usbc_auto_reconnect", default: config.usbcAutoReconnect)
        config.useSimulator = bool("use_simulator", default: config.useSimulator)

        config.sampleRateHz = max(1, min(50, int("sample_rate_hz", default: config.sampleRateHz)))
        config.graphHistorySeconds = max(5, min(600, int("graph_history_seconds", default: config.graphHistorySeconds)))
        config.outputQueueCapacity = max(8, min(2048, int("output_queue_capacity", default: config.outputQueueCapacity)))
        config.outputQueueMaxRetryAttempts = max(0, min(10, int("output_queue_max_retry_attempts", default: config.outputQueueMaxRetryAttempts)))

        config.shortThreshold = max(0.1, double("short_threshold", default: config.shortThreshold))
        config.beepOnShortMeter = bool("beep_on_short_meter", default: config.beepOnShortMeter)
        config.beepOnShortPC = bool("beep_on_short_pc", default: config.beepOnShortPC)
        config.pcBeepVolume = max(0, min(1, double("pc_beep_volume", default: config.pcBeepVolume)))

        config.dcvHighAlarmEnabled = bool("dcv_high_alarm_enabled", default: config.dcvHighAlarmEnabled)
        config.dcvHighAlarmValue = double("dcv_high_alarm_value", default: config.dcvHighAlarmValue)
        config.dcvLowAlarmEnabled = bool("dcv_low_alarm_enabled", default: config.dcvLowAlarmEnabled)
        config.dcvLowAlarmValue = double("dcv_low_alarm_value", default: config.dcvLowAlarmValue)
        config.beepOnAlarm = bool("beep_on_alarm", default: config.beepOnAlarm)

        config.multimeterOutputFile = string("multimeter_output_file", default: config.multimeterOutputFile)
        config.usbcOutputFile = string("usbc_output_file", default: config.usbcOutputFile)
        config.multimeterObsOutputMode = obsMode("multimeter_obs_output_mode", default: config.multimeterObsOutputMode)
        config.usbcObsOutputMode = obsMode("usbc_obs_output_mode", default: config.usbcObsOutputMode)
        config.multimeterObsCustomTemplate = string("multimeter_obs_custom_template", default: config.multimeterObsCustomTemplate)
        config.usbcObsCustomTemplate = string("usbc_obs_custom_template", default: config.usbcObsCustomTemplate)
        config.multimeterValueLabel = string("multimeter_value_label", default: config.multimeterValueLabel)
        config.usbcValueLabel = string("usbc_value_label", default: config.usbcValueLabel)

        config.multimeterCsvLoggingEnabled = bool("multimeter_csv_logging_enabled", default: config.multimeterCsvLoggingEnabled)
        config.usbcCsvLoggingEnabled = bool("usbc_csv_logging_enabled", default: config.usbcCsvLoggingEnabled)
        config.multimeterCsvLogFilePath = string("multimeter_csv_log_file_path", default: config.multimeterCsvLogFilePath)
        config.usbcCsvLogFilePath = string("usbc_csv_log_file_path", default: config.usbcCsvLogFilePath)
        config.dashboardDeviceVisibility = dashboardVisibility("dashboard_device_visibility", default: config.dashboardDeviceVisibility)
        config.dashboardTheme = dashboardTheme("dashboard_theme", default: config.dashboardTheme)
        config.runtimeLogPanelVisible = bool("runtime_log_panel_visible", default: config.runtimeLogPanelVisible)
        config.runtimeLogCaptureEnabled = bool("runtime_log_capture_enabled", default: config.runtimeLogCaptureEnabled)
        config.dashboardBeepMasterEnabled = bool("dashboard_beep_master_enabled", default: config.dashboardBeepMasterEnabled)
        config.pcBeepSoundPreset = soundPreset("pc_beep_sound_preset", default: config.pcBeepSoundPreset)
        config.multimeterPopoutMode = popoutDisplayMode("multimeter_popout_mode", default: config.multimeterPopoutMode)
        config.usbcPopoutMode = popoutDisplayMode("usbc_popout_mode", default: config.usbcPopoutMode)

        // Legacy migrations from Python implementation.
        if config.multimeterPort.isEmpty {
            config.multimeterPort = string("port", default: "")
        }
        if config.multimeterOutputFile.isEmpty {
            config.multimeterOutputFile = string("output_file", default: "")
        }
        if config.multimeterObsCustomTemplate == "{value} {unit}" {
            let legacyTemplate = string("obs_custom_template", default: "")
            if !legacyTemplate.isEmpty {
                config.multimeterObsCustomTemplate = legacyTemplate
            }
        }
        if config.multimeterObsOutputMode == .valueAndUnit {
            config.multimeterObsOutputMode = obsMode("obs_output_mode", default: config.multimeterObsOutputMode)
        }
        if config.multimeterValueLabel.isEmpty {
            config.multimeterValueLabel = string("value_label", default: "")
        }
        if config.multimeterCsvLogFilePath.isEmpty {
            config.multimeterCsvLogFilePath = string("csv_log_file_path", default: "")
        }
        if !config.multimeterCsvLoggingEnabled {
            config.multimeterCsvLoggingEnabled = bool("csv_logging_enabled", default: false)
        }

        return config
    }

    public func toDictionary() -> [String: Any] {
        [
            "multimeter_port": multimeterPort,
            "usbc_port": usbcPort,
            "multimeter_enabled": multimeterEnabled,
            "usbc_enabled": usbcEnabled,
            "multimeter_auto_reconnect": multimeterAutoReconnect,
            "usbc_auto_reconnect": usbcAutoReconnect,
            "use_simulator": useSimulator,
            "sample_rate_hz": sampleRateHz,
            "graph_history_seconds": graphHistorySeconds,
            "output_queue_capacity": outputQueueCapacity,
            "output_queue_max_retry_attempts": outputQueueMaxRetryAttempts,
            "short_threshold": shortThreshold,
            "beep_on_short_meter": beepOnShortMeter,
            "beep_on_short_pc": beepOnShortPC,
            "pc_beep_volume": pcBeepVolume,
            "dcv_high_alarm_enabled": dcvHighAlarmEnabled,
            "dcv_high_alarm_value": dcvHighAlarmValue,
            "dcv_low_alarm_enabled": dcvLowAlarmEnabled,
            "dcv_low_alarm_value": dcvLowAlarmValue,
            "beep_on_alarm": beepOnAlarm,
            "multimeter_output_file": multimeterOutputFile,
            "usbc_output_file": usbcOutputFile,
            "multimeter_obs_output_mode": multimeterObsOutputMode.rawValue,
            "usbc_obs_output_mode": usbcObsOutputMode.rawValue,
            "multimeter_obs_custom_template": multimeterObsCustomTemplate,
            "usbc_obs_custom_template": usbcObsCustomTemplate,
            "multimeter_value_label": multimeterValueLabel,
            "usbc_value_label": usbcValueLabel,
            "multimeter_csv_logging_enabled": multimeterCsvLoggingEnabled,
            "usbc_csv_logging_enabled": usbcCsvLoggingEnabled,
            "multimeter_csv_log_file_path": multimeterCsvLogFilePath,
            "usbc_csv_log_file_path": usbcCsvLogFilePath,
            "dashboard_device_visibility": dashboardDeviceVisibility.rawValue,
            "dashboard_theme": dashboardTheme.rawValue,
            "runtime_log_panel_visible": runtimeLogPanelVisible,
            "runtime_log_capture_enabled": runtimeLogCaptureEnabled,
            "dashboard_beep_master_enabled": dashboardBeepMasterEnabled,
            "pc_beep_sound_preset": pcBeepSoundPreset.rawValue,
            "multimeter_popout_mode": multimeterPopoutMode.rawValue,
            "usbc_popout_mode": usbcPopoutMode.rawValue,
        ]
    }
}

public enum ConfigurationStoreError: Error {
    case invalidFormat
}
