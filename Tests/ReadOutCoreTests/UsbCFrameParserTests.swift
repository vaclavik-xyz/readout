import Foundation
import Testing
@testable import ReadOutCore

@Test
func parsesValidUsbCFrame() throws {
    let parsed = try #require(UsbCFrameParser.parse("03E80BB8"))
    #expect(parsed.voltage == 9.375)
    #expect(parsed.current == 0.2)
}

@Test
func clampsNegativeCurrentToZero() throws {
    // 0xFFFF -> -1 signed; current would be -0.0002 before clamping.
    let parsed = try #require(UsbCFrameParser.parse("FFFF0BB8"))
    #expect(parsed.current == 0)
}

@Test
func rejectsInvalidFrames() {
    #expect(UsbCFrameParser.isValidFrame("ABC") == false)
    #expect(UsbCFrameParser.isValidFrame("ZZZZZZZZ") == false)
    #expect(UsbCFrameParser.parse("ABC") == nil)
    #expect(UsbCFrameParser.parse("ZZZZZZZZ") == nil)
}

@Test
func energyAccumulatorMatchesLegacyMath() {
    var accumulator = EnergyAccumulator()
    let t0 = Date(timeIntervalSince1970: 0)
    let t1 = Date(timeIntervalSince1970: 3600)

    _ = accumulator.update(voltage: 5.0, current: 2.0, at: t0)
    let snapshot = accumulator.update(voltage: 5.0, current: 2.0, at: t1)

    #expect(snapshot.powerWatts == 10.0)
    #expect(snapshot.energyMWh == 10_000.0)
    #expect(snapshot.energyMAh == 2_000.0)
}
