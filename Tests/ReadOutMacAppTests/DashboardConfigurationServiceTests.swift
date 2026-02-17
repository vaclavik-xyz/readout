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

@Test
func probePortsPrefersProfileSpecificCandidates() {
    let service = DashboardConfigurationService()
    let ports = [
        SimulatedPort.multimeter,
        SimulatedPort.usbC,
        "/dev/cu.Bluetooth-Incoming-Port",
        "/dev/cu.usbserial-1410",
        "/dev/cu.usbmodem211"
    ]

    let probe = service.probePorts(ports)

    #expect(probe.recommendedMultimeterPort == "/dev/cu.usbserial-1410")
    #expect(probe.recommendedUsbCPort == "/dev/cu.usbmodem211")
    #expect(probe.multimeterCandidates.isEmpty == false)
    #expect(probe.usbcCandidates.isEmpty == false)
}

@Test
func probePortsHandlesNoHardwareScenario() {
    let service = DashboardConfigurationService()
    let probe = service.probePorts([SimulatedPort.multimeter, SimulatedPort.usbC])

    #expect(probe.recommendedMultimeterPort == nil)
    #expect(probe.recommendedUsbCPort == nil)
    #expect(probe.multimeterCandidates.isEmpty)
    #expect(probe.usbcCandidates.isEmpty)
}

@Test
func initialWizardConfigurationFallsBackToSimulatorWithoutHardwarePorts() {
    let service = DashboardConfigurationService()
    let config = service.initialWizardConfiguration(
        availablePorts: [SimulatedPort.multimeter, SimulatedPort.usbC]
    )

    #expect(config.useSimulator)
    #expect(config.multimeterPort == SimulatedPort.multimeter)
    #expect(config.usbcPort == SimulatedPort.usbC)
    #expect(config.multimeterEnabled)
    #expect(config.usbcEnabled)
}

@Test
func connectBlockingIssuesHandlePartialAndUnknownPorts() {
    let service = DashboardConfigurationService()
    let available = [
        SimulatedPort.multimeter,
        SimulatedPort.usbC,
        "/dev/cu.usbserial-1410"
    ]

    var config = AppConfiguration()
    config.useSimulator = false
    config.multimeterEnabled = true
    config.usbcEnabled = true
    config.multimeterPort = "/dev/cu.usbserial-1410"
    config.usbcPort = ""

    let partialIssues = service.connectBlockingIssues(configuration: config, availablePorts: available)
    #expect(partialIssues.contains("USB-C meter port is empty."))

    config.usbcPort = "/dev/cu.unknown"
    let unknownIssues = service.connectBlockingIssues(configuration: config, availablePorts: available)
    #expect(unknownIssues.contains("USB-C meter port is not detected: /dev/cu.unknown"))
}
