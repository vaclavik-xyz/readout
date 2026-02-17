import Foundation
import ReadOutCore
import ReadOutPersistence

protocol ChartTimedMarker: Identifiable {
    var timestamp: Date { get }
}

struct ChartSample: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let value: Double
}

enum DeviceUIState: String, Sendable, Codable {
    case disconnected
    case connecting
    case connected
    case error
}

enum RuntimeEvent: Sendable {
    case multimeterStatus(DeviceUIState, String?)
    case usbcStatus(DeviceUIState, String?)
    case multimeterMeasurement(DeviceMeasurement)
    case usbcMeasurement(DeviceMeasurement)
    case runtimeError(String)
    case runtimeLog(RuntimeLogLevel, String)
}

enum RuntimeLogLevel: String, Sendable, Codable {
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

struct RuntimeLogEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let level: RuntimeLogLevel
    let message: String
}

struct ConnectionTimelineEntry: Identifiable, Sendable, Codable {
    let id: UUID
    let timestamp: Date
    let device: String
    let state: DeviceUIState
    let message: String?

    init(
        id: UUID = UUID(),
        timestamp: Date,
        device: String,
        state: DeviceUIState,
        message: String?
    ) {
        self.id = id
        self.timestamp = timestamp
        self.device = device
        self.state = state
        self.message = message
    }
}

struct RuntimeHealthSnapshot: Identifiable, Sendable, Codable {
    let id: UUID
    let timestamp: Date
    let reason: String
    let isRuntimeActive: Bool
    let multimeterStatus: DeviceUIState
    let usbcStatus: DeviceUIState
    let reconnectCount: Int
    let runtimeErrorCount: Int
    let parseErrorCount: Int
    let outputDropWarningCount: Int
    let runtimeLogCount: Int
    let statusMessage: String

    init(
        id: UUID = UUID(),
        timestamp: Date,
        reason: String,
        isRuntimeActive: Bool,
        multimeterStatus: DeviceUIState,
        usbcStatus: DeviceUIState,
        reconnectCount: Int,
        runtimeErrorCount: Int,
        parseErrorCount: Int,
        outputDropWarningCount: Int,
        runtimeLogCount: Int,
        statusMessage: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.reason = reason
        self.isRuntimeActive = isRuntimeActive
        self.multimeterStatus = multimeterStatus
        self.usbcStatus = usbcStatus
        self.reconnectCount = reconnectCount
        self.runtimeErrorCount = runtimeErrorCount
        self.parseErrorCount = parseErrorCount
        self.outputDropWarningCount = outputDropWarningCount
        self.runtimeLogCount = runtimeLogCount
        self.statusMessage = statusMessage
    }
}

struct AlarmTimelineMarker: ChartTimedMarker, Sendable {
    let id = UUID()
    let timestamp: Date
    let state: MeasurementAlertState
    let message: String
}

enum ConnectionOverlayState: String, Sendable {
    case reconnecting
    case error
    case restored
}

struct ConnectionOverlayMarker: ChartTimedMarker, Sendable {
    let id = UUID()
    let timestamp: Date
    let state: ConnectionOverlayState
    let message: String
}

enum DashboardDeviceVisibility: String, Sendable, CaseIterable, Identifiable {
    case both
    case multimeter
    case usbc

    var id: String { rawValue }

    var title: String {
        switch self {
        case .both:
            return "Both"
        case .multimeter:
            return "Multimeter"
        case .usbc:
            return "USB-C"
        }
    }

    init(configurationValue: AppConfiguration.DashboardDeviceVisibility) {
        switch configurationValue {
        case .both:
            self = .both
        case .multimeter:
            self = .multimeter
        case .usbc:
            self = .usbc
        }
    }

    var configurationValue: AppConfiguration.DashboardDeviceVisibility {
        switch self {
        case .both:
            return .both
        case .multimeter:
            return .multimeter
        case .usbc:
            return .usbc
        }
    }
}

enum DashboardTheme: String, Sendable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    init(configurationValue: AppConfiguration.DashboardTheme) {
        switch configurationValue {
        case .system:
            self = .system
        case .light:
            self = .light
        case .dark:
            self = .dark
        }
    }

    var configurationValue: AppConfiguration.DashboardTheme {
        switch self {
        case .system:
            return .system
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

enum MacAlertSoundPreset: String, Sendable, CaseIterable, Identifiable {
    case system
    case glass
    case sosumi
    case funk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "System Beep"
        case .glass:
            return "Glass"
        case .sosumi:
            return "Sosumi"
        case .funk:
            return "Funk"
        }
    }

    init(configurationValue: AppConfiguration.MacAlertSoundPreset) {
        switch configurationValue {
        case .system:
            self = .system
        case .glass:
            self = .glass
        case .sosumi:
            self = .sosumi
        case .funk:
            self = .funk
        }
    }

    var configurationValue: AppConfiguration.MacAlertSoundPreset {
        switch self {
        case .system:
            return .system
        case .glass:
            return .glass
        case .sosumi:
            return .sosumi
        case .funk:
            return .funk
        }
    }
}

enum RuntimeHealthSeverity: String, Sendable, Equatable {
    case good
    case warning
    case critical
}

struct RuntimeHealthBadge: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let value: String
    let severity: RuntimeHealthSeverity
}

enum AlarmSilencePreset: String, Sendable, CaseIterable, Identifiable {
    case oneMinute
    case fiveMinutes
    case fifteenMinutes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneMinute:
            return "Silence 1m"
        case .fiveMinutes:
            return "Silence 5m"
        case .fifteenMinutes:
            return "Silence 15m"
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .oneMinute:
            return 60
        case .fiveMinutes:
            return 5 * 60
        case .fifteenMinutes:
            return 15 * 60
        }
    }
}

enum DevicePopoutDisplayMode: String, Sendable, CaseIterable, Identifiable {
    case mini
    case compact
    case detailed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mini:
            return "Mini"
        case .compact:
            return "Compact"
        case .detailed:
            return "Detailed"
        }
    }

    init(configurationValue: AppConfiguration.PopoutDisplayMode) {
        switch configurationValue {
        case .mini:
            self = .mini
        case .compact:
            self = .compact
        case .detailed:
            self = .detailed
        }
    }

    var configurationValue: AppConfiguration.PopoutDisplayMode {
        switch self {
        case .mini:
            return .mini
        case .compact:
            return .compact
        case .detailed:
            return .detailed
        }
    }
}
