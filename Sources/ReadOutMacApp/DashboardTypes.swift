import Foundation
import ReadOutCore

struct ChartSample: Identifiable {
    let id = UUID()
    let timestamp: Date
    let value: Double
}

enum DeviceUIState: String, Sendable {
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
}
