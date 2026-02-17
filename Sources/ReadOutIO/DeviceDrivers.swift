import Foundation
import ReadOutCore

public protocol SCPITransport: DeviceTransport {
    func query(_ command: String) async throws -> String?
}

extension SCPIPollingTransport: SCPITransport {}

public actor MultimeterDeviceDriver {
    private let transport: any SCPITransport
    private let pipeline: MultimeterMeasurementPipeline
    private var isConnected = false

    public init(
        transport: any SCPITransport,
        pipeline: MultimeterMeasurementPipeline = MultimeterMeasurementPipeline()
    ) {
        self.transport = transport
        self.pipeline = pipeline
    }

    public func connect() async throws {
        try await transport.open()
        isConnected = true
    }

    public func disconnect() async {
        isConnected = false
        await transport.close()
    }

    public func connected() -> Bool {
        isConnected
    }

    public func readMeasurement(at timestamp: Date = Date()) async throws -> DeviceMeasurement? {
        guard isConnected else {
            return nil
        }

        if await pipeline.shouldRefreshMode() {
            let mode = try await transport.query("FUNC?")
            await pipeline.updateMode(mode)
        }

        let response = try await transport.readFrame()
        return await pipeline.decodeMeasurementResponse(response, at: timestamp)
    }

    public func setBeeperEnabled(_ enabled: Bool) async throws -> Bool {
        guard isConnected else {
            return false
        }

        let command = enabled ? "SYST:BEEP:STAT ON" : "SYST:BEEP:STAT OFF"
        _ = try await transport.query(command)
        let verification = try await transport.query("SYST:BEEP:STAT?")?.uppercased()

        let expectedNumeric = enabled ? "1" : "0"
        let expectedNamed = enabled ? "ON" : "OFF"
        return verification == expectedNumeric || verification == expectedNamed
    }
}

public actor UsbCDeviceDriver {
    private let transport: any DeviceTransport
    private let pipeline: UsbCMeasurementPipeline
    private var isConnected = false

    public init(
        transport: any DeviceTransport,
        pipeline: UsbCMeasurementPipeline = UsbCMeasurementPipeline()
    ) {
        self.transport = transport
        self.pipeline = pipeline
    }

    public func connect() async throws {
        try await transport.open()
        isConnected = true
    }

    public func disconnect() async {
        isConnected = false
        await transport.close()
    }

    public func connected() -> Bool {
        isConnected
    }

    public func resetEnergy() async {
        await pipeline.resetEnergy()
    }

    public func readMeasurement(at timestamp: Date = Date()) async throws -> DeviceMeasurement? {
        guard isConnected else {
            return nil
        }

        guard let frame = try await transport.readFrame() else {
            return nil
        }
        return await pipeline.decodeFrame(frame, at: timestamp)
    }
}
