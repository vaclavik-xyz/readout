import Foundation
import Testing
@testable import ReadOutIO
@testable import ReadOutCore

private actor MockSCPITransport: SCPITransport {
    private var queryResponses: [String?]
    private var readResponses: [String?]
    private(set) var queries: [String] = []
    private(set) var openCount = 0
    private(set) var closeCount = 0

    init(queryResponses: [String?], readResponses: [String?]) {
        self.queryResponses = queryResponses
        self.readResponses = readResponses
    }

    func open() async throws {
        openCount += 1
    }

    func close() async {
        closeCount += 1
    }

    func readFrame() async throws -> String? {
        if readResponses.isEmpty {
            return nil
        }
        return readResponses.removeFirst()
    }

    func query(_ command: String) async throws -> String? {
        queries.append(command)
        if queryResponses.isEmpty {
            return nil
        }
        return queryResponses.removeFirst()
    }

    func snapshot() -> (open: Int, close: Int, queries: [String]) {
        (openCount, closeCount, queries)
    }
}

private actor MockFrameTransport: DeviceTransport {
    private var frames: [String?]
    private(set) var openCount = 0
    private(set) var closeCount = 0

    init(frames: [String?]) {
        self.frames = frames
    }

    func open() async throws {
        openCount += 1
    }

    func close() async {
        closeCount += 1
    }

    func readFrame() async throws -> String? {
        if frames.isEmpty {
            return nil
        }
        return frames.removeFirst()
    }
}

@Test
func multimeterDriverReadsParsedMeasurement() async throws {
    let transport = MockSCPITransport(
        queryResponses: ["VOLT:DC"],
        readResponses: ["12.3000"]
    )
    let pipeline = MultimeterMeasurementPipeline(modeRefreshInterval: 1)
    let driver = MultimeterDeviceDriver(transport: transport, pipeline: pipeline)

    try await driver.connect()
    let measurement = try #require(await driver.readMeasurement())

    #expect(measurement.device == .multimeter)
    #expect(measurement.mode == .dcVoltage)
    #expect(measurement.primaryValue == 12.3)
    #expect(measurement.primaryUnit == "V DC")

    let snapshot = await transport.snapshot()
    #expect(snapshot.open == 1)
    #expect(snapshot.queries == ["FUNC?"])
}

@Test
func multimeterDriverBeeperVerification() async throws {
    let transport = MockSCPITransport(
        queryResponses: ["", "1"],
        readResponses: []
    )
    let driver = MultimeterDeviceDriver(transport: transport)
    try await driver.connect()

    let ok = try await driver.setBeeperEnabled(true)
    #expect(ok == true)

    let snapshot = await transport.snapshot()
    #expect(snapshot.queries == ["SYST:BEEP:STAT ON", "SYST:BEEP:STAT?"])
}

@Test
func usbcDriverReadsFrameAndResetsEnergy() async throws {
    let t0 = Date(timeIntervalSince1970: 0)
    let t1 = Date(timeIntervalSince1970: 3600)
    let transport = MockFrameTransport(frames: ["03E80BB8", "03E80BB8", "03E80BB8"])
    let driver = UsbCDeviceDriver(transport: transport)
    try await driver.connect()

    _ = try #require(await driver.readMeasurement(at: t0))
    let later = try #require(await driver.readMeasurement(at: t1))
    #expect(later.energyMWh == 1_875.0)

    await driver.resetEnergy()
    let reset = try #require(await driver.readMeasurement(at: t1))
    #expect(reset.energyMWh == 0)
    #expect(reset.energyMAh == 0)
}
