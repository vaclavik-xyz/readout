import Foundation
import Testing
@testable import ReadOutCore

@Test
func shortDetectionMatchesContinuityThreshold() {
    let config = MeasurementAlertConfiguration(shortThreshold: 2.0)
    let measurement = DeviceMeasurement(
        device: .multimeter,
        mode: .continuity,
        modeString: "CONT",
        primaryValue: 0.4,
        primaryUnit: "Ω"
    )

    let alert = MeasurementAlertEvaluator.evaluateMultimeter(measurement: measurement, configuration: config)
    #expect(alert == .short)

    let enriched = MeasurementAlertEvaluator.enrichMultimeter(measurement: measurement, configuration: config)
    #expect(enriched.isShort == true)
}

@Test
func overloadIsClassifiedAsOpenBeforeThresholdChecks() {
    let config = MeasurementAlertConfiguration(
        shortThreshold: 2.0,
        dcvHighAlarmEnabled: true,
        dcvHighAlarmValue: 5.0
    )

    let measurement = DeviceMeasurement(
        device: .multimeter,
        mode: .dcVoltage,
        modeString: "VOLT:DC",
        primaryValue: nil,
        primaryUnit: "V DC",
        isOverload: true,
        isOpen: true
    )

    let alert = MeasurementAlertEvaluator.evaluateMultimeter(measurement: measurement, configuration: config)
    #expect(alert == .open)
}

@Test
func dcvHighAndLowAlarmsTriggerAsExpected() {
    let config = MeasurementAlertConfiguration(
        shortThreshold: 2.0,
        dcvHighAlarmEnabled: true,
        dcvHighAlarmValue: 12.0,
        dcvLowAlarmEnabled: true,
        dcvLowAlarmValue: 10.0
    )

    let high = DeviceMeasurement(
        device: .multimeter,
        mode: .dcVoltage,
        modeString: "VOLT:DC",
        primaryValue: 12.6,
        primaryUnit: "V DC"
    )
    let low = DeviceMeasurement(
        device: .multimeter,
        mode: .dcVoltage,
        modeString: "VOLT:DC",
        primaryValue: 9.8,
        primaryUnit: "V DC"
    )
    let nominal = DeviceMeasurement(
        device: .multimeter,
        mode: .dcVoltage,
        modeString: "VOLT:DC",
        primaryValue: 11.2,
        primaryUnit: "V DC"
    )

    #expect(MeasurementAlertEvaluator.evaluateMultimeter(measurement: high, configuration: config) == .highAlarm)
    #expect(MeasurementAlertEvaluator.evaluateMultimeter(measurement: low, configuration: config) == .lowAlarm)
    #expect(MeasurementAlertEvaluator.evaluateMultimeter(measurement: nominal, configuration: config) == .none)
}
