import Foundation
import Testing
@testable import ReadOutIO
@testable import ReadOutCore

@Test
func simulatedSCPITransportProducesParsableMeasurements() async throws {
    let transport = SimulatedSCPITransport(sampleRateHz: 200)
    try await transport.open()

    let mode = try #require(await transport.query("FUNC?"))
    let frame = try #require(await transport.readFrame())

    let parsed = MultimeterParser.parse(response: frame, modeString: mode)
    #expect(parsed != nil)

    _ = try await transport.query("SYST:BEEP:STAT ON")
    let beeper = try #require(await transport.query("SYST:BEEP:STAT?"))
    #expect(beeper == "1")

    await transport.close()
}

@Test
func simulatedStreamingTransportProducesValidUsbCFrames() async throws {
    let transport = SimulatedStreamingTransport(sampleRateHz: 200)
    try await transport.open()

    let frame = try #require(await transport.readFrame())
    #expect(UsbCFrameParser.isValidFrame(frame))

    let parsed = try #require(UsbCFrameParser.parse(frame))
    #expect(parsed.voltage > 0)
    #expect(parsed.current >= 0)

    await transport.close()
}
