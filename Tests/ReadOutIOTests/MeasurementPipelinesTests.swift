import Foundation
import Testing
@testable import ReadOutIO
@testable import ReadOutCore

@Test
func multimeterPipelineUsesCachedModeAndParsesMeasurement() async throws {
    let pipeline = MultimeterMeasurementPipeline(modeRefreshInterval: 3)

    #expect(await pipeline.shouldRefreshMode() == true)
    await pipeline.updateMode("VOLT:DC")

    let measurement = try #require(await pipeline.decodeMeasurementResponse("12.345"))
    #expect(measurement.device == .multimeter)
    #expect(measurement.mode == .dcVoltage)
    #expect(measurement.primaryValue == 12.345)
    #expect(measurement.primaryUnit == "V DC")
    #expect(measurement.isOverload == false)
}

@Test
func multimeterPipelineOverloadIsPreserved() async throws {
    let pipeline = MultimeterMeasurementPipeline()
    await pipeline.updateMode("RES")

    let measurement = try #require(await pipeline.decodeMeasurementResponse("OL"))
    #expect(measurement.isOverload == true)
    #expect(measurement.isOpen == true)
    #expect(measurement.primaryValue == nil)
}

@Test
func usbcPipelineAccumulatesEnergyAndResets() async throws {
    let pipeline = UsbCMeasurementPipeline()
    let t0 = Date(timeIntervalSince1970: 0)
    let t1 = Date(timeIntervalSince1970: 3600)

    _ = try #require(await pipeline.decodeFrame("03E80BB8", at: t0))
    let later = try #require(await pipeline.decodeFrame("03E80BB8", at: t1))

    #expect(later.device == .usbC)
    #expect(later.primaryValue == 9.375)
    #expect(later.secondaryValue == 0.2)
    #expect(later.powerWatts == 1.875)
    #expect(later.energyMWh == 1_875.0)
    #expect(later.energyMAh == 200.0)

    await pipeline.resetEnergy()
    let reset = try #require(await pipeline.decodeFrame("03E80BB8", at: t1))
    #expect(reset.energyMWh == 0)
    #expect(reset.energyMAh == 0)
}
