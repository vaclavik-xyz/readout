import Foundation
import Testing
@testable import ReadOutMacApp
@testable import ReadOutCore
@testable import ReadOutPersistence

@Test
func alertServiceDetectsHighAndLowVoltageAlarms() {
    var config = AppConfiguration()
    config.dcvHighAlarmEnabled = true
    config.dcvHighAlarmValue = 12.0
    config.dcvLowAlarmEnabled = true
    config.dcvLowAlarmValue = 10.0

    let high = DeviceMeasurement(
        device: .multimeter,
        mode: .dcVoltage,
        modeString: "VOLT:DC",
        primaryValue: 12.4,
        primaryUnit: "V DC"
    )
    let low = DeviceMeasurement(
        device: .multimeter,
        mode: .dcVoltage,
        modeString: "VOLT:DC",
        primaryValue: 9.7,
        primaryUnit: "V DC"
    )

    #expect(DashboardAlertService.evaluate(measurement: high, configuration: config) == .highAlarm)
    #expect(DashboardAlertService.evaluate(measurement: low, configuration: config) == .lowAlarm)
}

@Test
func alertServiceDetectsShortAndBeepRules() {
    var config = AppConfiguration()
    config.shortThreshold = 2.0
    config.beepOnShortPC = true

    let short = DeviceMeasurement(
        device: .multimeter,
        mode: .continuity,
        modeString: "CONT",
        primaryValue: 0.5,
        primaryUnit: "Ω"
    )

    let alert = DashboardAlertService.evaluate(measurement: short, configuration: config)

    #expect(alert == .short)
    #expect(DashboardAlertService.text(for: alert) == "SHORT")
    #expect(DashboardAlertService.shouldBeep(for: alert, configuration: config) == true)
    #expect(DashboardAlertService.statusMessage(for: alert) == "SHORT condition detected")
}

@Test
func alertServiceOpenHasNoStatusMessage() {
    let config = AppConfiguration()
    let open = DeviceMeasurement(
        device: .multimeter,
        mode: .resistance,
        modeString: "RES",
        primaryValue: nil,
        primaryUnit: "Ω",
        isOverload: true,
        isOpen: true
    )

    let alert = DashboardAlertService.evaluate(measurement: open, configuration: config)
    #expect(alert == .open)
    #expect(DashboardAlertService.text(for: alert) == "OPEN")
    #expect(DashboardAlertService.statusMessage(for: alert) == nil)
}
