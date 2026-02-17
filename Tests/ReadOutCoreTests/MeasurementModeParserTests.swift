import Testing
@testable import ReadOutCore

@Test
func parsesKnownModesFromLegacyStrings() {
    #expect(MeasurementModeParser.parse("VOLT:DC") == .dcVoltage)
    #expect(MeasurementModeParser.parse("VOLT:AC") == .acVoltage)
    #expect(MeasurementModeParser.parse("CURR:DC") == .dcCurrent)
    #expect(MeasurementModeParser.parse("CURR:AC") == .acCurrent)
    #expect(MeasurementModeParser.parse("RES") == .resistance)
    #expect(MeasurementModeParser.parse("FRES") == .resistance)
    #expect(MeasurementModeParser.parse("CONT") == .continuity)
    #expect(MeasurementModeParser.parse("DIOD") == .diode)
    #expect(MeasurementModeParser.parse("CAP") == .capacitance)
    #expect(MeasurementModeParser.parse("FREQ") == .frequency)
    #expect(MeasurementModeParser.parse("PER") == .period)
    #expect(MeasurementModeParser.parse("TEMP") == .temperature)
}

@Test
func unknownOrEmptyModeFallsBackToUnknown() {
    #expect(MeasurementModeParser.parse(nil) == .unknown)
    #expect(MeasurementModeParser.parse("") == .unknown)
    #expect(MeasurementModeParser.parse("   ") == .unknown)
    #expect(MeasurementModeParser.parse("XYZ") == .unknown)
}
