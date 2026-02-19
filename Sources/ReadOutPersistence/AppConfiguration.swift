import Foundation

public struct AppConfiguration: Sendable, Equatable, Codable {
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

    public struct PopoutWindowFrame: Sendable, Equatable, Codable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    public struct PopoutLayoutProfile: Sendable, Equatable, Codable {
        public var name: String
        public var multimeterMode: PopoutDisplayMode
        public var usbcMode: PopoutDisplayMode
        public var multimeterFrame: PopoutWindowFrame?
        public var usbcFrame: PopoutWindowFrame?

        public init(
            name: String,
            multimeterMode: PopoutDisplayMode,
            usbcMode: PopoutDisplayMode,
            multimeterFrame: PopoutWindowFrame?,
            usbcFrame: PopoutWindowFrame?
        ) {
            self.name = name
            self.multimeterMode = multimeterMode
            self.usbcMode = usbcMode
            self.multimeterFrame = multimeterFrame
            self.usbcFrame = usbcFrame
        }

        private enum CodingKeys: String, CodingKey {
            case name
            case multimeterMode = "multimeter_mode"
            case usbcMode = "usbc_mode"
            case multimeterX = "multimeter_x"
            case multimeterY = "multimeter_y"
            case multimeterWidth = "multimeter_width"
            case multimeterHeight = "multimeter_height"
            case usbcX = "usbc_x"
            case usbcY = "usbc_y"
            case usbcWidth = "usbc_width"
            case usbcHeight = "usbc_height"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)

            let rawName = ((try? c.decodeIfPresent(String.self, forKey: .name)) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            name = String(rawName.prefix(48))

            if let raw = try? c.decodeIfPresent(String.self, forKey: .multimeterMode) {
                multimeterMode = PopoutDisplayMode(rawValue: raw.lowercased()) ?? .detailed
            } else {
                multimeterMode = .detailed
            }

            if let raw = try? c.decodeIfPresent(String.self, forKey: .usbcMode) {
                usbcMode = PopoutDisplayMode(rawValue: raw.lowercased()) ?? .detailed
            } else {
                usbcMode = .detailed
            }

            multimeterFrame = Self.decodeFlatFrame(
                from: c, xKey: .multimeterX, yKey: .multimeterY,
                widthKey: .multimeterWidth, heightKey: .multimeterHeight
            )
            usbcFrame = Self.decodeFlatFrame(
                from: c, xKey: .usbcX, yKey: .usbcY,
                widthKey: .usbcWidth, heightKey: .usbcHeight
            )
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(name, forKey: .name)
            try c.encode(multimeterMode, forKey: .multimeterMode)
            try c.encode(usbcMode, forKey: .usbcMode)

            if let frame = multimeterFrame {
                try c.encode(frame.x, forKey: .multimeterX)
                try c.encode(frame.y, forKey: .multimeterY)
                try c.encode(frame.width, forKey: .multimeterWidth)
                try c.encode(frame.height, forKey: .multimeterHeight)
            }
            if let frame = usbcFrame {
                try c.encode(frame.x, forKey: .usbcX)
                try c.encode(frame.y, forKey: .usbcY)
                try c.encode(frame.width, forKey: .usbcWidth)
                try c.encode(frame.height, forKey: .usbcHeight)
            }
        }

        private static func decodeFlatFrame(
            from c: KeyedDecodingContainer<CodingKeys>,
            xKey: CodingKeys, yKey: CodingKeys,
            widthKey: CodingKeys, heightKey: CodingKeys
        ) -> PopoutWindowFrame? {
            guard
                let x = try? c.decodeIfPresent(Double.self, forKey: xKey),
                let y = try? c.decodeIfPresent(Double.self, forKey: yKey),
                let width = try? c.decodeIfPresent(Double.self, forKey: widthKey),
                let height = try? c.decodeIfPresent(Double.self, forKey: heightKey),
                width >= 120, height >= 90
            else {
                return nil
            }
            return PopoutWindowFrame(x: x, y: y, width: width, height: height)
        }
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
    public var multimeterPopoutFrame: PopoutWindowFrame?
    public var usbcPopoutFrame: PopoutWindowFrame?
    public var popoutAlarmEmphasisEnabled: Bool = false
    public var popoutLayoutProfiles: [PopoutLayoutProfile] = []
    public var activePopoutLayoutProfileName: String = ""

    public init() {}

    // MARK: - CodingKeys

    private enum CodingKeys: String, CodingKey {
        case multimeterPort = "multimeter_port"
        case usbcPort = "usbc_port"
        case multimeterEnabled = "multimeter_enabled"
        case usbcEnabled = "usbc_enabled"
        case multimeterAutoReconnect = "multimeter_auto_reconnect"
        case usbcAutoReconnect = "usbc_auto_reconnect"
        case useSimulator = "use_simulator"

        case sampleRateHz = "sample_rate_hz"
        case graphHistorySeconds = "graph_history_seconds"
        case outputQueueCapacity = "output_queue_capacity"
        case outputQueueMaxRetryAttempts = "output_queue_max_retry_attempts"

        case shortThreshold = "short_threshold"
        case beepOnShortMeter = "beep_on_short_meter"
        case beepOnShortPC = "beep_on_short_pc"
        case pcBeepVolume = "pc_beep_volume"

        case dcvHighAlarmEnabled = "dcv_high_alarm_enabled"
        case dcvHighAlarmValue = "dcv_high_alarm_value"
        case dcvLowAlarmEnabled = "dcv_low_alarm_enabled"
        case dcvLowAlarmValue = "dcv_low_alarm_value"
        case beepOnAlarm = "beep_on_alarm"

        case multimeterOutputFile = "multimeter_output_file"
        case usbcOutputFile = "usbc_output_file"
        case multimeterObsOutputMode = "multimeter_obs_output_mode"
        case usbcObsOutputMode = "usbc_obs_output_mode"
        case multimeterObsCustomTemplate = "multimeter_obs_custom_template"
        case usbcObsCustomTemplate = "usbc_obs_custom_template"
        case multimeterValueLabel = "multimeter_value_label"
        case usbcValueLabel = "usbc_value_label"

        case multimeterCsvLoggingEnabled = "multimeter_csv_logging_enabled"
        case usbcCsvLoggingEnabled = "usbc_csv_logging_enabled"
        case multimeterCsvLogFilePath = "multimeter_csv_log_file_path"
        case usbcCsvLogFilePath = "usbc_csv_log_file_path"

        case dashboardDeviceVisibility = "dashboard_device_visibility"
        case dashboardTheme = "dashboard_theme"
        case runtimeLogPanelVisible = "runtime_log_panel_visible"
        case runtimeLogCaptureEnabled = "runtime_log_capture_enabled"
        case dashboardBeepMasterEnabled = "dashboard_beep_master_enabled"
        case pcBeepSoundPreset = "pc_beep_sound_preset"
        case multimeterPopoutMode = "multimeter_popout_mode"
        case usbcPopoutMode = "usbc_popout_mode"
        case popoutAlarmEmphasisEnabled = "popout_alarm_emphasis_enabled"
        case popoutLayoutProfiles = "popout_layout_profiles"
        case activePopoutLayoutProfileName = "active_popout_layout_profile"

        // Flat frame keys for top-level popout window positions.
        case multimeterPopoutX = "multimeter_popout_x"
        case multimeterPopoutY = "multimeter_popout_y"
        case multimeterPopoutWidth = "multimeter_popout_width"
        case multimeterPopoutHeight = "multimeter_popout_height"
        case usbcPopoutX = "usbc_popout_x"
        case usbcPopoutY = "usbc_popout_y"
        case usbcPopoutWidth = "usbc_popout_width"
        case usbcPopoutHeight = "usbc_popout_height"
    }

    // MARK: - Decoding

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // Strings
        multimeterPort = (try? c.decodeIfPresent(String.self, forKey: .multimeterPort)) ?? ""
        usbcPort = (try? c.decodeIfPresent(String.self, forKey: .usbcPort)) ?? ""
        multimeterOutputFile = (try? c.decodeIfPresent(String.self, forKey: .multimeterOutputFile)) ?? ""
        usbcOutputFile = (try? c.decodeIfPresent(String.self, forKey: .usbcOutputFile)) ?? ""
        multimeterObsCustomTemplate = (try? c.decodeIfPresent(String.self, forKey: .multimeterObsCustomTemplate)) ?? "{value} {unit}"
        usbcObsCustomTemplate = (try? c.decodeIfPresent(String.self, forKey: .usbcObsCustomTemplate)) ?? "{voltage} {current} {power}"
        multimeterValueLabel = (try? c.decodeIfPresent(String.self, forKey: .multimeterValueLabel)) ?? ""
        usbcValueLabel = (try? c.decodeIfPresent(String.self, forKey: .usbcValueLabel)) ?? ""
        multimeterCsvLogFilePath = (try? c.decodeIfPresent(String.self, forKey: .multimeterCsvLogFilePath)) ?? ""
        usbcCsvLogFilePath = (try? c.decodeIfPresent(String.self, forKey: .usbcCsvLogFilePath)) ?? ""

        // Bools
        multimeterEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .multimeterEnabled)) ?? true
        usbcEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .usbcEnabled)) ?? false
        multimeterAutoReconnect = (try? c.decodeIfPresent(Bool.self, forKey: .multimeterAutoReconnect)) ?? true
        usbcAutoReconnect = (try? c.decodeIfPresent(Bool.self, forKey: .usbcAutoReconnect)) ?? true
        useSimulator = (try? c.decodeIfPresent(Bool.self, forKey: .useSimulator)) ?? false
        beepOnShortMeter = (try? c.decodeIfPresent(Bool.self, forKey: .beepOnShortMeter)) ?? false
        beepOnShortPC = (try? c.decodeIfPresent(Bool.self, forKey: .beepOnShortPC)) ?? false
        dcvHighAlarmEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .dcvHighAlarmEnabled)) ?? false
        dcvLowAlarmEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .dcvLowAlarmEnabled)) ?? false
        beepOnAlarm = (try? c.decodeIfPresent(Bool.self, forKey: .beepOnAlarm)) ?? false
        multimeterCsvLoggingEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .multimeterCsvLoggingEnabled)) ?? false
        usbcCsvLoggingEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .usbcCsvLoggingEnabled)) ?? false
        runtimeLogPanelVisible = (try? c.decodeIfPresent(Bool.self, forKey: .runtimeLogPanelVisible)) ?? true
        runtimeLogCaptureEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .runtimeLogCaptureEnabled)) ?? true
        dashboardBeepMasterEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .dashboardBeepMasterEnabled)) ?? true
        popoutAlarmEmphasisEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .popoutAlarmEmphasisEnabled)) ?? false

        // Ints
        sampleRateHz = (try? c.decodeIfPresent(Int.self, forKey: .sampleRateHz)) ?? 10
        graphHistorySeconds = (try? c.decodeIfPresent(Int.self, forKey: .graphHistorySeconds)) ?? 30
        outputQueueCapacity = (try? c.decodeIfPresent(Int.self, forKey: .outputQueueCapacity)) ?? 256
        outputQueueMaxRetryAttempts = (try? c.decodeIfPresent(Int.self, forKey: .outputQueueMaxRetryAttempts)) ?? 3

        // Doubles
        shortThreshold = (try? c.decodeIfPresent(Double.self, forKey: .shortThreshold)) ?? 2.0
        pcBeepVolume = (try? c.decodeIfPresent(Double.self, forKey: .pcBeepVolume)) ?? 0.5
        dcvHighAlarmValue = (try? c.decodeIfPresent(Double.self, forKey: .dcvHighAlarmValue)) ?? 12.0
        dcvLowAlarmValue = (try? c.decodeIfPresent(Double.self, forKey: .dcvLowAlarmValue)) ?? 0.0

        // Enums (case-insensitive via string decode + normalize)
        multimeterObsOutputMode = Self.decodeObsMode(from: c, forKey: .multimeterObsOutputMode) ?? .valueAndUnit
        usbcObsOutputMode = Self.decodeObsMode(from: c, forKey: .usbcObsOutputMode) ?? .valueAndUnit
        dashboardDeviceVisibility = Self.decodeLowercaseEnum(from: c, forKey: .dashboardDeviceVisibility) ?? .both
        dashboardTheme = Self.decodeLowercaseEnum(from: c, forKey: .dashboardTheme) ?? .system
        pcBeepSoundPreset = Self.decodeLowercaseEnum(from: c, forKey: .pcBeepSoundPreset) ?? .system
        multimeterPopoutMode = Self.decodeLowercaseEnum(from: c, forKey: .multimeterPopoutMode) ?? .detailed
        usbcPopoutMode = Self.decodeLowercaseEnum(from: c, forKey: .usbcPopoutMode) ?? .detailed

        // Flat frame keys
        multimeterPopoutFrame = Self.decodeFlatFrame(
            from: c, xKey: .multimeterPopoutX, yKey: .multimeterPopoutY,
            widthKey: .multimeterPopoutWidth, heightKey: .multimeterPopoutHeight
        )
        usbcPopoutFrame = Self.decodeFlatFrame(
            from: c, xKey: .usbcPopoutX, yKey: .usbcPopoutY,
            widthKey: .usbcPopoutWidth, heightKey: .usbcPopoutHeight
        )

        // Profiles (tolerant of malformed entries)
        if let rawProfiles = try? c.decodeIfPresent([PopoutLayoutProfile].self, forKey: .popoutLayoutProfiles) {
            var parsed: [PopoutLayoutProfile] = []
            parsed.reserveCapacity(rawProfiles.count)
            for profile in rawProfiles {
                guard !profile.name.isEmpty else { continue }
                if let existing = parsed.firstIndex(where: { $0.name == profile.name }) {
                    parsed[existing] = profile
                } else {
                    parsed.append(profile)
                }
            }
            popoutLayoutProfiles = parsed
        } else {
            popoutLayoutProfiles = []
        }

        // Active profile validation
        let rawActiveProfile = ((try? c.decodeIfPresent(String.self, forKey: .activePopoutLayoutProfileName)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if popoutLayoutProfiles.contains(where: { $0.name == rawActiveProfile }) {
            activePopoutLayoutProfileName = rawActiveProfile
        } else {
            activePopoutLayoutProfileName = ""
        }

        clampValues()
    }

    // MARK: - Encoding

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        // Strings
        try c.encode(multimeterPort, forKey: .multimeterPort)
        try c.encode(usbcPort, forKey: .usbcPort)
        try c.encode(multimeterOutputFile, forKey: .multimeterOutputFile)
        try c.encode(usbcOutputFile, forKey: .usbcOutputFile)
        try c.encode(multimeterObsCustomTemplate, forKey: .multimeterObsCustomTemplate)
        try c.encode(usbcObsCustomTemplate, forKey: .usbcObsCustomTemplate)
        try c.encode(multimeterValueLabel, forKey: .multimeterValueLabel)
        try c.encode(usbcValueLabel, forKey: .usbcValueLabel)
        try c.encode(multimeterCsvLogFilePath, forKey: .multimeterCsvLogFilePath)
        try c.encode(usbcCsvLogFilePath, forKey: .usbcCsvLogFilePath)

        // Bools
        try c.encode(multimeterEnabled, forKey: .multimeterEnabled)
        try c.encode(usbcEnabled, forKey: .usbcEnabled)
        try c.encode(multimeterAutoReconnect, forKey: .multimeterAutoReconnect)
        try c.encode(usbcAutoReconnect, forKey: .usbcAutoReconnect)
        try c.encode(useSimulator, forKey: .useSimulator)
        try c.encode(beepOnShortMeter, forKey: .beepOnShortMeter)
        try c.encode(beepOnShortPC, forKey: .beepOnShortPC)
        try c.encode(dcvHighAlarmEnabled, forKey: .dcvHighAlarmEnabled)
        try c.encode(dcvLowAlarmEnabled, forKey: .dcvLowAlarmEnabled)
        try c.encode(beepOnAlarm, forKey: .beepOnAlarm)
        try c.encode(multimeterCsvLoggingEnabled, forKey: .multimeterCsvLoggingEnabled)
        try c.encode(usbcCsvLoggingEnabled, forKey: .usbcCsvLoggingEnabled)
        try c.encode(runtimeLogPanelVisible, forKey: .runtimeLogPanelVisible)
        try c.encode(runtimeLogCaptureEnabled, forKey: .runtimeLogCaptureEnabled)
        try c.encode(dashboardBeepMasterEnabled, forKey: .dashboardBeepMasterEnabled)
        try c.encode(popoutAlarmEmphasisEnabled, forKey: .popoutAlarmEmphasisEnabled)

        // Ints
        try c.encode(sampleRateHz, forKey: .sampleRateHz)
        try c.encode(graphHistorySeconds, forKey: .graphHistorySeconds)
        try c.encode(outputQueueCapacity, forKey: .outputQueueCapacity)
        try c.encode(outputQueueMaxRetryAttempts, forKey: .outputQueueMaxRetryAttempts)

        // Doubles
        try c.encode(shortThreshold, forKey: .shortThreshold)
        try c.encode(pcBeepVolume, forKey: .pcBeepVolume)
        try c.encode(dcvHighAlarmValue, forKey: .dcvHighAlarmValue)
        try c.encode(dcvLowAlarmValue, forKey: .dcvLowAlarmValue)

        // Enums
        try c.encode(multimeterObsOutputMode, forKey: .multimeterObsOutputMode)
        try c.encode(usbcObsOutputMode, forKey: .usbcObsOutputMode)
        try c.encode(dashboardDeviceVisibility, forKey: .dashboardDeviceVisibility)
        try c.encode(dashboardTheme, forKey: .dashboardTheme)
        try c.encode(pcBeepSoundPreset, forKey: .pcBeepSoundPreset)
        try c.encode(multimeterPopoutMode, forKey: .multimeterPopoutMode)
        try c.encode(usbcPopoutMode, forKey: .usbcPopoutMode)

        // Flat frame keys (only present when frame is set)
        if let frame = multimeterPopoutFrame {
            try c.encode(frame.x, forKey: .multimeterPopoutX)
            try c.encode(frame.y, forKey: .multimeterPopoutY)
            try c.encode(frame.width, forKey: .multimeterPopoutWidth)
            try c.encode(frame.height, forKey: .multimeterPopoutHeight)
        }
        if let frame = usbcPopoutFrame {
            try c.encode(frame.x, forKey: .usbcPopoutX)
            try c.encode(frame.y, forKey: .usbcPopoutY)
            try c.encode(frame.width, forKey: .usbcPopoutWidth)
            try c.encode(frame.height, forKey: .usbcPopoutHeight)
        }

        // Profiles
        if !popoutLayoutProfiles.isEmpty {
            try c.encode(popoutLayoutProfiles, forKey: .popoutLayoutProfiles)
        }

        try c.encode(activePopoutLayoutProfileName, forKey: .activePopoutLayoutProfileName)
    }

    // MARK: - Value Clamping

    private mutating func clampValues() {
        sampleRateHz = max(1, min(50, sampleRateHz))
        graphHistorySeconds = max(5, min(600, graphHistorySeconds))
        outputQueueCapacity = max(8, min(2048, outputQueueCapacity))
        outputQueueMaxRetryAttempts = max(0, min(10, outputQueueMaxRetryAttempts))
        shortThreshold = max(0.1, shortThreshold)
        pcBeepVolume = max(0, min(1, pcBeepVolume))
    }

    // MARK: - Decode Helpers

    private static func decodeObsMode(
        from c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys
    ) -> ObsOutputMode? {
        guard let raw = try? c.decodeIfPresent(String.self, forKey: key) else { return nil }
        return ObsOutputMode(rawValue: raw.uppercased())
    }

    private static func decodeLowercaseEnum<E: RawRepresentable>(
        from c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys
    ) -> E? where E.RawValue == String {
        guard let raw = try? c.decodeIfPresent(String.self, forKey: key) else { return nil }
        return E(rawValue: raw.lowercased())
    }

    private static func decodeFlatFrame(
        from c: KeyedDecodingContainer<CodingKeys>,
        xKey: CodingKeys, yKey: CodingKeys,
        widthKey: CodingKeys, heightKey: CodingKeys
    ) -> PopoutWindowFrame? {
        guard
            let x = try? c.decodeIfPresent(Double.self, forKey: xKey),
            let y = try? c.decodeIfPresent(Double.self, forKey: yKey),
            let width = try? c.decodeIfPresent(Double.self, forKey: widthKey),
            let height = try? c.decodeIfPresent(Double.self, forKey: heightKey),
            width >= 120, height >= 90
        else {
            return nil
        }
        return PopoutWindowFrame(x: x, y: y, width: width, height: height)
    }
}

public enum ConfigurationStoreError: Error {
    case invalidFormat
}
