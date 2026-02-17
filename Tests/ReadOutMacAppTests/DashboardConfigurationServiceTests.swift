import Testing
@testable import ReadOutMacApp
@testable import ReadOutPersistence
@testable import ReadOutIO

@Test
func normalizedClampsSamplingAndShortThreshold() {
    let service = DashboardConfigurationService()

    var config = AppConfiguration()
    config.sampleRateHz = 0
    config.graphHistorySeconds = 10_000
    config.outputQueueCapacity = 1
    config.outputQueueMaxRetryAttempts = 50
    config.shortThreshold = 0.01

    let normalized = service.normalized(config, availablePorts: ["/dev/cu.usbserial-123"])

    #expect(normalized.sampleRateHz == 1)
    #expect(normalized.graphHistorySeconds == 600)
    #expect(normalized.outputQueueCapacity == 8)
    #expect(normalized.outputQueueMaxRetryAttempts == 10)
    #expect(normalized.shortThreshold == 0.1)
}

@Test
func normalizedUsesSimulatorPortsWhenEnabled() {
    let service = DashboardConfigurationService()

    var config = AppConfiguration()
    config.useSimulator = true
    config.multimeterPort = ""
    config.usbcPort = ""

    let normalized = service.normalized(config, availablePorts: ["/dev/cu.usbserial-123"])

    #expect(normalized.multimeterPort == SimulatedPort.multimeter)
    #expect(normalized.usbcPort == SimulatedPort.usbC)
}

@Test
func normalizedAssignsFirstHardwarePortWhenEmpty() {
    let service = DashboardConfigurationService()

    var config = AppConfiguration()
    config.useSimulator = false
    config.multimeterPort = ""
    config.usbcPort = ""

    let normalized = service.normalized(
        config,
        availablePorts: [SimulatedPort.multimeter, SimulatedPort.usbC, "/dev/cu.usbmodem-1"]
    )

    #expect(normalized.multimeterPort == "/dev/cu.usbmodem-1")
    #expect(normalized.usbcPort == "/dev/cu.usbmodem-1")
}
