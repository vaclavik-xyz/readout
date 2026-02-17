import Foundation
import ReadOutCore

struct RuntimeSessionCaptureFile: Codable, Sendable, Equatable {
    let version: Int
    let createdAt: Date
    let events: [RuntimeSessionCaptureRecord]
}

struct RuntimeSessionCaptureRecord: Codable, Sendable, Equatable {
    struct MeasurementRecord: Codable, Sendable, Equatable {
        let device: String
        let mode: String
        let modeString: String
        let primaryValue: Double?
        let primaryUnit: String
        let secondaryValue: Double?
        let secondaryUnit: String
        let powerWatts: Double?
        let energyMWh: Double?
        let energyMAh: Double?
        let isOverload: Bool
        let isOpen: Bool
        let isShort: Bool
        let timestamp: Date
    }

    let offsetMilliseconds: Int
    let eventType: String
    let state: String?
    let level: String?
    let message: String?
    let measurement: MeasurementRecord?
}

enum RuntimeSessionCaptureService {
    static func makeRecord(event: RuntimeEvent, offsetMilliseconds: Int) -> RuntimeSessionCaptureRecord {
        switch event {
        case .multimeterStatus(let state, let message):
            return RuntimeSessionCaptureRecord(
                offsetMilliseconds: offsetMilliseconds,
                eventType: "multimeter_status",
                state: state.rawValue,
                level: nil,
                message: message,
                measurement: nil
            )
        case .usbcStatus(let state, let message):
            return RuntimeSessionCaptureRecord(
                offsetMilliseconds: offsetMilliseconds,
                eventType: "usbc_status",
                state: state.rawValue,
                level: nil,
                message: message,
                measurement: nil
            )
        case .runtimeError(let message):
            return RuntimeSessionCaptureRecord(
                offsetMilliseconds: offsetMilliseconds,
                eventType: "runtime_error",
                state: nil,
                level: nil,
                message: message,
                measurement: nil
            )
        case .runtimeLog(let level, let message):
            return RuntimeSessionCaptureRecord(
                offsetMilliseconds: offsetMilliseconds,
                eventType: "runtime_log",
                state: nil,
                level: level.rawValue,
                message: message,
                measurement: nil
            )
        case .multimeterMeasurement(let measurement):
            return RuntimeSessionCaptureRecord(
                offsetMilliseconds: offsetMilliseconds,
                eventType: "multimeter_measurement",
                state: nil,
                level: nil,
                message: nil,
                measurement: makeMeasurementRecord(measurement)
            )
        case .usbcMeasurement(let measurement):
            return RuntimeSessionCaptureRecord(
                offsetMilliseconds: offsetMilliseconds,
                eventType: "usbc_measurement",
                state: nil,
                level: nil,
                message: nil,
                measurement: makeMeasurementRecord(measurement)
            )
        }
    }

    static func runtimeEvent(from record: RuntimeSessionCaptureRecord) -> RuntimeEvent? {
        switch record.eventType {
        case "multimeter_status":
            guard let rawState = record.state, let state = DeviceUIState(rawValue: rawState) else {
                return nil
            }
            return .multimeterStatus(state, record.message)
        case "usbc_status":
            guard let rawState = record.state, let state = DeviceUIState(rawValue: rawState) else {
                return nil
            }
            return .usbcStatus(state, record.message)
        case "runtime_error":
            guard let message = record.message else {
                return nil
            }
            return .runtimeError(message)
        case "runtime_log":
            guard let rawLevel = record.level, let level = RuntimeLogLevel(rawValue: rawLevel), let message = record.message else {
                return nil
            }
            return .runtimeLog(level, message)
        case "multimeter_measurement":
            guard let measurement = record.measurement.flatMap(makeMeasurement) else {
                return nil
            }
            return .multimeterMeasurement(measurement)
        case "usbc_measurement":
            guard let measurement = record.measurement.flatMap(makeMeasurement) else {
                return nil
            }
            return .usbcMeasurement(measurement)
        default:
            return nil
        }
    }

    static func writeCapture(
        createdAt: Date,
        records: [RuntimeSessionCaptureRecord],
        to destinationURL: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let capture = RuntimeSessionCaptureFile(version: 1, createdAt: createdAt, events: records)
        let data = try encoder.encode(capture)
        let directory = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: destinationURL, options: .atomic)
    }

    static func readCapture(from sourceURL: URL) throws -> RuntimeSessionCaptureFile {
        let data = try Data(contentsOf: sourceURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RuntimeSessionCaptureFile.self, from: data)
    }

    private static func makeMeasurementRecord(_ measurement: DeviceMeasurement) -> RuntimeSessionCaptureRecord.MeasurementRecord {
        RuntimeSessionCaptureRecord.MeasurementRecord(
            device: measurement.device.rawValue,
            mode: serializeMeasurementMode(measurement.mode),
            modeString: measurement.modeString,
            primaryValue: measurement.primaryValue,
            primaryUnit: measurement.primaryUnit,
            secondaryValue: measurement.secondaryValue,
            secondaryUnit: measurement.secondaryUnit,
            powerWatts: measurement.powerWatts,
            energyMWh: measurement.energyMWh,
            energyMAh: measurement.energyMAh,
            isOverload: measurement.isOverload,
            isOpen: measurement.isOpen,
            isShort: measurement.isShort,
            timestamp: measurement.timestamp
        )
    }

    private static func makeMeasurement(_ record: RuntimeSessionCaptureRecord.MeasurementRecord) -> DeviceMeasurement? {
        guard let device = DeviceKind(rawValue: record.device) else {
            return nil
        }
        let mode = deserializeMeasurementMode(record.mode)
        return DeviceMeasurement(
            device: device,
            mode: mode,
            modeString: record.modeString,
            primaryValue: record.primaryValue,
            primaryUnit: record.primaryUnit,
            secondaryValue: record.secondaryValue,
            secondaryUnit: record.secondaryUnit,
            powerWatts: record.powerWatts,
            energyMWh: record.energyMWh,
            energyMAh: record.energyMAh,
            isOverload: record.isOverload,
            isOpen: record.isOpen,
            isShort: record.isShort,
            timestamp: record.timestamp
        )
    }

    private static func serializeMeasurementMode(_ mode: MeasurementMode) -> String {
        switch mode {
        case .dcVoltage:
            return "dc_voltage"
        case .acVoltage:
            return "ac_voltage"
        case .resistance:
            return "resistance"
        case .continuity:
            return "continuity"
        case .diode:
            return "diode"
        case .dcCurrent:
            return "dc_current"
        case .acCurrent:
            return "ac_current"
        case .capacitance:
            return "capacitance"
        case .frequency:
            return "frequency"
        case .period:
            return "period"
        case .temperature:
            return "temperature"
        case .unknown:
            return "unknown"
        }
    }

    private static func deserializeMeasurementMode(_ rawValue: String) -> MeasurementMode {
        switch rawValue {
        case "dc_voltage":
            return .dcVoltage
        case "ac_voltage":
            return .acVoltage
        case "resistance":
            return .resistance
        case "continuity":
            return .continuity
        case "diode":
            return .diode
        case "dc_current":
            return .dcCurrent
        case "ac_current":
            return .acCurrent
        case "capacitance":
            return .capacitance
        case "frequency":
            return .frequency
        case "period":
            return .period
        case "temperature":
            return .temperature
        default:
            return .unknown
        }
    }
}
