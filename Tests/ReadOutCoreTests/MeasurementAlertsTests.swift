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

// MARK: - Hysteresis tests

@Test
func highAlarmHoldsInHysteresisBand() {
    let config = MeasurementAlertConfiguration(
        dcvHighAlarmEnabled: true,
        dcvHighAlarmValue: 12.0
    )

    // Value above threshold triggers alarm
    let above = DeviceMeasurement(
        device: .multimeter, mode: .dcVoltage, modeString: "VOLT:DC",
        primaryValue: 12.1, primaryUnit: "V DC"
    )
    #expect(MeasurementAlertEvaluator.evaluateMultimeter(
        measurement: above, configuration: config, previousState: .none
    ) == .highAlarm)

    // Value in hysteresis band (11.88...12.0) holds alarm when previous was highAlarm
    let inBand = DeviceMeasurement(
        device: .multimeter, mode: .dcVoltage, modeString: "VOLT:DC",
        primaryValue: 11.95, primaryUnit: "V DC"
    )
    #expect(MeasurementAlertEvaluator.evaluateMultimeter(
        measurement: inBand, configuration: config, previousState: .highAlarm
    ) == .highAlarm)

    // Same value clears if previous was not highAlarm
    #expect(MeasurementAlertEvaluator.evaluateMultimeter(
        measurement: inBand, configuration: config, previousState: .none
    ) == .none)

    // Value below hysteresis band clears alarm
    let belowBand = DeviceMeasurement(
        device: .multimeter, mode: .dcVoltage, modeString: "VOLT:DC",
        primaryValue: 11.80, primaryUnit: "V DC"
    )
    #expect(MeasurementAlertEvaluator.evaluateMultimeter(
        measurement: belowBand, configuration: config, previousState: .highAlarm
    ) == .none)
}

@Test
func lowAlarmHoldsInHysteresisBand() {
    let config = MeasurementAlertConfiguration(
        dcvLowAlarmEnabled: true,
        dcvLowAlarmValue: 10.0
    )

    // Value below threshold triggers alarm
    let below = DeviceMeasurement(
        device: .multimeter, mode: .dcVoltage, modeString: "VOLT:DC",
        primaryValue: 9.9, primaryUnit: "V DC"
    )
    #expect(MeasurementAlertEvaluator.evaluateMultimeter(
        measurement: below, configuration: config, previousState: .none
    ) == .lowAlarm)

    // Value in hysteresis band (10.0...10.1) holds alarm when previous was lowAlarm
    let inBand = DeviceMeasurement(
        device: .multimeter, mode: .dcVoltage, modeString: "VOLT:DC",
        primaryValue: 10.05, primaryUnit: "V DC"
    )
    #expect(MeasurementAlertEvaluator.evaluateMultimeter(
        measurement: inBand, configuration: config, previousState: .lowAlarm
    ) == .lowAlarm)

    // Same value clears if previous was not lowAlarm
    #expect(MeasurementAlertEvaluator.evaluateMultimeter(
        measurement: inBand, configuration: config, previousState: .none
    ) == .none)

    // Value above hysteresis band clears alarm
    let aboveBand = DeviceMeasurement(
        device: .multimeter, mode: .dcVoltage, modeString: "VOLT:DC",
        primaryValue: 10.15, primaryUnit: "V DC"
    )
    #expect(MeasurementAlertEvaluator.evaluateMultimeter(
        measurement: aboveBand, configuration: config, previousState: .lowAlarm
    ) == .none)
}

@Test
func hysteresisDefaultPreviousStatePreservesBackwardCompatibility() {
    let config = MeasurementAlertConfiguration(
        dcvHighAlarmEnabled: true,
        dcvHighAlarmValue: 12.0,
        dcvLowAlarmEnabled: true,
        dcvLowAlarmValue: 10.0
    )

    // Without previousState parameter, behaves as before for values clearly above/below
    let high = DeviceMeasurement(
        device: .multimeter, mode: .dcVoltage, modeString: "VOLT:DC",
        primaryValue: 12.5, primaryUnit: "V DC"
    )
    let low = DeviceMeasurement(
        device: .multimeter, mode: .dcVoltage, modeString: "VOLT:DC",
        primaryValue: 9.5, primaryUnit: "V DC"
    )
    let nominal = DeviceMeasurement(
        device: .multimeter, mode: .dcVoltage, modeString: "VOLT:DC",
        primaryValue: 11.0, primaryUnit: "V DC"
    )

    #expect(MeasurementAlertEvaluator.evaluateMultimeter(measurement: high, configuration: config) == .highAlarm)
    #expect(MeasurementAlertEvaluator.evaluateMultimeter(measurement: low, configuration: config) == .lowAlarm)
    #expect(MeasurementAlertEvaluator.evaluateMultimeter(measurement: nominal, configuration: config) == .none)
}
