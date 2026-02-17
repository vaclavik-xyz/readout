import Foundation

public enum MeasurementAlertState: Sendable, Equatable {
    case none
    case short
    case open
    case highAlarm
    case lowAlarm
}

public struct MeasurementAlertConfiguration: Sendable, Equatable {
    public var shortThreshold: Double
    public var dcvHighAlarmEnabled: Bool
    public var dcvHighAlarmValue: Double
    public var dcvLowAlarmEnabled: Bool
    public var dcvLowAlarmValue: Double

    public init(
        shortThreshold: Double = 2.0,
        dcvHighAlarmEnabled: Bool = false,
        dcvHighAlarmValue: Double = 12.0,
        dcvLowAlarmEnabled: Bool = false,
        dcvLowAlarmValue: Double = 0.0
    ) {
        self.shortThreshold = shortThreshold
        self.dcvHighAlarmEnabled = dcvHighAlarmEnabled
        self.dcvHighAlarmValue = dcvHighAlarmValue
        self.dcvLowAlarmEnabled = dcvLowAlarmEnabled
        self.dcvLowAlarmValue = dcvLowAlarmValue
    }
}

public enum MeasurementAlertEvaluator {
    public static func evaluateMultimeter(
        measurement: DeviceMeasurement,
        configuration: MeasurementAlertConfiguration
    ) -> MeasurementAlertState {
        if measurement.isOpen || measurement.isOverload {
            return .open
        }

        if isShortCondition(measurement: measurement, configuration: configuration) {
            return .short
        }

        guard measurement.mode == .dcVoltage, let value = measurement.primaryValue else {
            return .none
        }

        if configuration.dcvHighAlarmEnabled, value > configuration.dcvHighAlarmValue {
            return .highAlarm
        }

        if configuration.dcvLowAlarmEnabled, value < configuration.dcvLowAlarmValue {
            return .lowAlarm
        }

        return .none
    }

    public static func enrichMultimeter(
        measurement: DeviceMeasurement,
        configuration: MeasurementAlertConfiguration
    ) -> DeviceMeasurement {
        let isShort = isShortCondition(measurement: measurement, configuration: configuration)

        guard measurement.isShort != isShort else {
            return measurement
        }

        return DeviceMeasurement(
            device: measurement.device,
            mode: measurement.mode,
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
            isShort: isShort,
            timestamp: measurement.timestamp
        )
    }

    public static func isShortCondition(
        measurement: DeviceMeasurement,
        configuration: MeasurementAlertConfiguration
    ) -> Bool {
        guard !measurement.isOverload,
              !measurement.isOpen,
              let value = measurement.primaryValue else {
            return false
        }

        switch measurement.mode {
        case .continuity, .resistance, .diode:
            return value < configuration.shortThreshold
        default:
            return false
        }
    }
}
