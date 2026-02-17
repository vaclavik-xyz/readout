import Foundation
import ReadOutCore

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
