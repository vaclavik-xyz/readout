import Foundation

public enum AppConfigurationIssueSeverity: String, Sendable, Equatable {
    case error
    case warning
}

public struct AppConfigurationIssue: Sendable, Equatable, Identifiable {
    public let severity: AppConfigurationIssueSeverity
    public let code: String
    public let message: String

    public init(severity: AppConfigurationIssueSeverity, code: String, message: String) {
        self.severity = severity
        self.code = code
        self.message = message
    }

    public var id: String {
        "\(severity.rawValue):\(code)"
    }
}

public struct AppConfigurationValidationResult: Sendable, Equatable {
    public let issues: [AppConfigurationIssue]

    public init(issues: [AppConfigurationIssue]) {
        self.issues = issues
    }

    public var hasErrors: Bool {
        issues.contains(where: { $0.severity == .error })
    }
}

public enum AppConfigurationValidator {
    public static func validate(_ config: AppConfiguration) -> AppConfigurationValidationResult {
        var issues: [AppConfigurationIssue] = []

        if !config.multimeterEnabled && !config.usbcEnabled {
            issues.append(.init(
                severity: .warning,
                code: "devices.none_enabled",
                message: "Both devices are disabled. No measurements will be captured."
            ))
        }

        if !config.useSimulator {
            if config.multimeterEnabled && config.multimeterPort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.init(
                    severity: .warning,
                    code: "multimeter.port.empty",
                    message: "Multimeter is enabled but serial port is empty."
                ))
            }

            if config.usbcEnabled && config.usbcPort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.init(
                    severity: .warning,
                    code: "usbc.port.empty",
                    message: "USB-C meter is enabled but serial port is empty."
                ))
            }
        }

        if !(1...50).contains(config.sampleRateHz) {
            issues.append(.init(
                severity: .error,
                code: "sample_rate.out_of_range",
                message: "Sample rate must be between 1 and 50 Hz."
            ))
        }

        if !(5...600).contains(config.graphHistorySeconds) {
            issues.append(.init(
                severity: .error,
                code: "graph_history.out_of_range",
                message: "Graph history must be between 5 and 600 seconds."
            ))
        }

        if !(8...2048).contains(config.outputQueueCapacity) {
            issues.append(.init(
                severity: .error,
                code: "output_queue_capacity.out_of_range",
                message: "Output queue capacity must be between 8 and 2048."
            ))
        }

        if !(0...10).contains(config.outputQueueMaxRetryAttempts) {
            issues.append(.init(
                severity: .error,
                code: "output_queue_retries.out_of_range",
                message: "Output queue retry attempts must be between 0 and 10."
            ))
        }

        if config.shortThreshold < 0.1 {
            issues.append(.init(
                severity: .error,
                code: "short_threshold.too_low",
                message: "SHORT threshold must be at least 0.1."
            ))
        }

        if config.dcvHighAlarmEnabled && config.dcvLowAlarmEnabled && config.dcvLowAlarmValue >= config.dcvHighAlarmValue {
            issues.append(.init(
                severity: .error,
                code: "dcv_alarm.invalid_range",
                message: "DC low alarm must be lower than DC high alarm."
            ))
        }

        if config.multimeterObsOutputMode == .customTemplate && config.multimeterObsCustomTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(
                severity: .error,
                code: "multimeter.obs_template.empty",
                message: "Multimeter custom OBS template is empty."
            ))
        }

        if config.usbcObsOutputMode == .customTemplate && config.usbcObsCustomTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(
                severity: .error,
                code: "usbc.obs_template.empty",
                message: "USB-C custom OBS template is empty."
            ))
        }

        if config.multimeterCsvLoggingEnabled && config.multimeterCsvLogFilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(
                severity: .error,
                code: "multimeter.csv_path.empty",
                message: "Multimeter CSV logging is enabled but file path is empty."
            ))
        }

        if config.usbcCsvLoggingEnabled && config.usbcCsvLogFilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(
                severity: .error,
                code: "usbc.csv_path.empty",
                message: "USB-C CSV logging is enabled but file path is empty."
            ))
        }

        if config.beepOnShortMeter && !config.multimeterEnabled {
            issues.append(.init(
                severity: .warning,
                code: "beeper.multimeter_disabled",
                message: "Multimeter beeper on SHORT is enabled, but multimeter is disabled."
            ))
        }

        return AppConfigurationValidationResult(issues: issues)
    }
}
