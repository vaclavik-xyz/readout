import Testing
@testable import ReadOutPersistence

@Test
func defaultConfigurationHasNoErrors() {
    let config = AppConfiguration()
    let result = AppConfigurationValidator.validate(config)

    #expect(result.hasErrors == false)
}

@Test
func missingPortsWarnWhenHardwareModeIsEnabled() {
    var config = AppConfiguration()
    config.multimeterEnabled = true
    config.usbcEnabled = true
    config.useSimulator = false
    config.multimeterPort = ""
    config.usbcPort = ""

    let result = AppConfigurationValidator.validate(config)

    #expect(result.hasErrors == false)
    #expect(result.issues.contains(where: { $0.code == "multimeter.port.empty" }))
    #expect(result.issues.contains(where: { $0.code == "usbc.port.empty" }))
}

@Test
func simulatorModeAllowsEmptyPorts() {
    var config = AppConfiguration()
    config.multimeterEnabled = true
    config.usbcEnabled = true
    config.useSimulator = true
    config.multimeterPort = ""
    config.usbcPort = ""

    let result = AppConfigurationValidator.validate(config)

    #expect(result.hasErrors == false)
}

@Test
func csvLoggingRequiresPath() {
    var config = AppConfiguration()
    config.multimeterCsvLoggingEnabled = true
    config.multimeterCsvLogFilePath = ""

    let result = AppConfigurationValidator.validate(config)

    #expect(result.hasErrors == true)
    #expect(result.issues.contains(where: { $0.code == "multimeter.csv_path.empty" }))
}

@Test
func dcvAlarmRangeMustBeOrdered() {
    var config = AppConfiguration()
    config.dcvHighAlarmEnabled = true
    config.dcvLowAlarmEnabled = true
    config.dcvHighAlarmValue = 10.0
    config.dcvLowAlarmValue = 11.0

    let result = AppConfigurationValidator.validate(config)

    #expect(result.hasErrors == true)
    #expect(result.issues.contains(where: { $0.code == "dcv_alarm.invalid_range" }))
}
