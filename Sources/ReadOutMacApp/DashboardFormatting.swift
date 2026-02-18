import Foundation
import ReadOutCore
import ReadOutPersistence

enum MeasurementDisplayFormatter {
    static func multimeterPrimary(_ measurement: DeviceMeasurement) -> String {
        if measurement.isOpen {
            return "OPEN"
        }
        if measurement.isShort {
            return "SHORT"
        }
        if measurement.isOverload {
            return "OVERLOAD"
        }
        guard let value = measurement.primaryValue else {
            return "---"
        }
        return String(format: "%.4f", value)
    }

    static func multimeterSecondary(_ measurement: DeviceMeasurement) -> String {
        measurement.primaryUnit
    }

    static func multimeterModeTitle(_ measurement: DeviceMeasurement) -> String {
        switch measurement.mode {
        case .dcVoltage: return "DC Voltage"
        case .acVoltage: return "AC Voltage"
        case .resistance: return "Resistance"
        case .continuity: return "Continuity"
        case .diode: return "Diode"
        case .dcCurrent: return "DC Current"
        case .acCurrent: return "AC Current"
        case .capacitance: return "Capacitance"
        case .frequency: return "Frequency"
        case .period: return "Period"
        case .temperature: return "Temperature"
        case .unknown:
            return measurement.modeString.isEmpty ? "Unknown" : measurement.modeString
        }
    }
}

enum DashboardAlertService {
    static func evaluate(
        measurement: DeviceMeasurement,
        configuration: AppConfiguration,
        previousState: MeasurementAlertState = .none
    ) -> MeasurementAlertState {
        MeasurementAlertEvaluator.evaluateMultimeter(
            measurement: measurement,
            configuration: configuration.alertConfiguration,
            previousState: previousState
        )
    }

    static func text(for alert: MeasurementAlertState) -> String {
        switch alert {
        case .none:
            return "OK"
        case .short:
            return "SHORT"
        case .open:
            return "OPEN"
        case .highAlarm:
            return "HIGH ALARM"
        case .lowAlarm:
            return "LOW ALARM"
        }
    }

    static func statusMessage(for alert: MeasurementAlertState) -> String? {
        switch alert {
        case .highAlarm:
            return "DC voltage above high alarm threshold"
        case .lowAlarm:
            return "DC voltage below low alarm threshold"
        case .short:
            return "SHORT condition detected"
        case .none, .open:
            return nil
        }
    }

    static func shouldBeep(
        for alert: MeasurementAlertState,
        configuration: AppConfiguration,
        dashboardBeepMasterEnabled: Bool = true,
        alarmMuted: Bool = false
    ) -> Bool {
        guard dashboardBeepMasterEnabled else {
            return false
        }
        guard !alarmMuted else {
            return false
        }
        let shortBeep = configuration.beepOnShortPC && alert == .short
        let voltageAlarmBeep = configuration.beepOnAlarm && (alert == .highAlarm || alert == .lowAlarm)
        return shortBeep || voltageAlarmBeep
    }
}

extension AppConfiguration {
    var alertConfiguration: MeasurementAlertConfiguration {
        MeasurementAlertConfiguration(
            shortThreshold: shortThreshold,
            dcvHighAlarmEnabled: dcvHighAlarmEnabled,
            dcvHighAlarmValue: dcvHighAlarmValue,
            dcvLowAlarmEnabled: dcvLowAlarmEnabled,
            dcvLowAlarmValue: dcvLowAlarmValue
        )
    }
}
