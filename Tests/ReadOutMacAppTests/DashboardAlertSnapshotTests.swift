import Foundation
import Testing
@testable import ReadOutMacApp
@testable import ReadOutCore
@testable import ReadOutPersistence

private func makeMeasurement(
    mode: MeasurementMode,
    value: Double?,
    unit: String = "V",
    isOpen: Bool = false,
    isOverload: Bool = false
) -> DeviceMeasurement {
    DeviceMeasurement(
        device: .multimeter,
        mode: mode,
        modeString: "snapshot",
        primaryValue: value,
        primaryUnit: unit,
        isOverload: isOverload,
        isOpen: isOpen,
        isShort: false,
        timestamp: Date(timeIntervalSince1970: 1_000)
    )
}

private func alertSnapshot(
    measurement: DeviceMeasurement,
    configuration: AppConfiguration
) -> String {
    let alert = DashboardAlertService.evaluate(measurement: measurement, configuration: configuration)
    let status = DashboardAlertService.statusMessage(for: alert) ?? "-"
    return """
    primary: \(MeasurementDisplayFormatter.multimeterPrimary(measurement))
    secondary: \(MeasurementDisplayFormatter.multimeterSecondary(measurement))
    mode: \(MeasurementDisplayFormatter.multimeterModeTitle(measurement))
    alert: \(DashboardAlertService.text(for: alert))
    status: \(status)
    """
}

@Test
func snapshotHighAlarmState() {
    var config = AppConfiguration()
    config.dcvHighAlarmEnabled = true
    config.dcvHighAlarmValue = 12.0

    let measurement = makeMeasurement(mode: .dcVoltage, value: 12.8)
    let snapshot = alertSnapshot(measurement: measurement, configuration: config)

    #expect(
        snapshot == """
        primary: 12.8000
        secondary: V
        mode: DC Voltage
        alert: HIGH ALARM
        status: DC voltage above high alarm threshold
        """
    )
}

@Test
func snapshotLowAlarmState() {
    var config = AppConfiguration()
    config.dcvLowAlarmEnabled = true
    config.dcvLowAlarmValue = 3.3

    let measurement = makeMeasurement(mode: .dcVoltage, value: 2.7)
    let snapshot = alertSnapshot(measurement: measurement, configuration: config)

    #expect(
        snapshot == """
        primary: 2.7000
        secondary: V
        mode: DC Voltage
        alert: LOW ALARM
        status: DC voltage below low alarm threshold
        """
    )
}

@Test
func snapshotShortState() {
    var config = AppConfiguration()
    config.shortThreshold = 2.0

    let measurement = makeMeasurement(mode: .continuity, value: 0.4, unit: "ohm")
    let enriched = MeasurementAlertEvaluator.enrichMultimeter(
        measurement: measurement,
        configuration: config.alertConfiguration
    )
    let snapshot = alertSnapshot(measurement: enriched, configuration: config)

    #expect(
        snapshot == """
        primary: SHORT
        secondary: ohm
        mode: Continuity
        alert: SHORT
        status: SHORT condition detected
        """
    )
}

@Test
func snapshotOpenState() {
    let config = AppConfiguration()
    let measurement = makeMeasurement(mode: .resistance, value: nil, unit: "ohm", isOpen: true)
    let snapshot = alertSnapshot(measurement: measurement, configuration: config)

    #expect(
        snapshot == """
        primary: OPEN
        secondary: ohm
        mode: Resistance
        alert: OPEN
        status: -
        """
    )
}
