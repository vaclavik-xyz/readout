import Testing
@testable import ReadOutCore

@Test
func parsesScientificNotationMeasurement() throws {
    let parsed = try #require(MultimeterParser.parse(response: "1.2300E+01 V", modeString: "VOLT:DC"))
    #expect(parsed.mode == .dcVoltage)
    #expect(parsed.value == 12.3)
    #expect(parsed.unit == "V DC")
    #expect(parsed.isOverload == false)
}

@Test
func overloadByKeywordMarksOpenForResistanceFamily() throws {
    let parsed = try #require(MultimeterParser.parse(response: "OL", modeString: "RES"))
    #expect(parsed.value == nil)
    #expect(parsed.isOverload == true)
    #expect(parsed.isOpen == true)
    #expect(parsed.unit == "Ω")
}

@Test
func overloadByThresholdMatchesLegacyRules() throws {
    let parsed = try #require(MultimeterParser.parse(response: "10000000", modeString: "RES"))
    #expect(parsed.value == nil)
    #expect(parsed.isOverload == true)
    #expect(parsed.isOpen == true)
}

@Test
func responseWithCommaPayloadUsesFirstSegment() throws {
    let parsed = try #require(MultimeterParser.parse(response: "0.1234,0,0", modeString: "CURR:AC"))
    #expect(parsed.mode == .acCurrent)
    #expect(parsed.value == 0.1234)
    #expect(parsed.unit == "A AC")
}

@Test
func invalidNumericPayloadProducesEmptyMeasurement() throws {
    let parsed = try #require(MultimeterParser.parse(response: "NOT_A_NUMBER", modeString: "TEMP"))
    #expect(parsed.value == nil)
    #expect(parsed.unit == "")
    #expect(parsed.isOverload == false)
}
