import Testing
@testable import ReadOutCore

@Test
func importMultimeterCaptureBuildsExpectedFixtures() {
    let lines = [
        "# comment",
        "VOLT:DC\t1.2300E+01 V",
        "RES|OL",
        "CURR:AC,0.1234,0,0",
        "bad-line-without-separator"
    ]

    let fixtures = FixtureImporter.importMultimeterCapture(lines: lines)
    #expect(fixtures.count == 3)
    #expect(fixtures[0].mode == "VOLT:DC")
    #expect(fixtures[0].expected.mode == "dcVoltage")
    #expect(fixtures[1].expected.isOverload == true)
    #expect(fixtures[1].expected.isOpen == true)
    #expect(fixtures[2].expected.mode == "acCurrent")
}

@Test
func importUsbCCaptureMarksValidityAndExpectedValues() {
    let lines = [
        "03E80BB8",
        "ZZZZZZZZ",
        "# ignore",
        "FFFF0BB8,metadata"
    ]

    let fixtures = FixtureImporter.importUsbCCapture(lines: lines)
    #expect(fixtures.count == 3)
    #expect(fixtures[0].valid == true)
    #expect(fixtures[0].expectedVoltage != nil)
    #expect(fixtures[1].valid == false)
    #expect(fixtures[1].expectedVoltage == nil)
}

@Test
func driftAnalyzerDetectsModeAndTokenDrift() {
    let baselineMultimeter = [
        MultimeterFixtureCase(
            response: "OL",
            mode: "RES",
            expected: .init(mode: "resistance", value: nil, unit: "Ω", isOverload: true, isOpen: true)
        )
    ]
    let baselineUsbC = [
        UsbCFrameFixtureCase(frame: "03E80BB8", valid: true, expectedVoltage: 9.375, expectedCurrent: 0.2),
        UsbCFrameFixtureCase(frame: "ZZZZZZZZ", valid: false, expectedVoltage: nil, expectedCurrent: nil)
    ]

    let candidateMultimeter = [
        MultimeterFixtureCase(
            response: "OVER_RANGE",
            mode: "MODE:NEW",
            expected: .init(mode: "unknown", value: nil, unit: "", isOverload: true, isOpen: false)
        )
    ]
    let candidateUsbC = [
        UsbCFrameFixtureCase(frame: "03E80BB8", valid: true, expectedVoltage: 9.375, expectedCurrent: 0.2),
        UsbCFrameFixtureCase(frame: "BAD", valid: false, expectedVoltage: nil, expectedCurrent: nil),
        UsbCFrameFixtureCase(frame: "NOPE", valid: false, expectedVoltage: nil, expectedCurrent: nil)
    ]

    let report = ParserDriftAnalyzer.analyze(
        candidateMultimeter: candidateMultimeter,
        candidateUsbC: candidateUsbC,
        baselineMultimeter: baselineMultimeter,
        baselineUsbC: baselineUsbC,
        thresholds: ParserDriftThresholds(
            maxNewUnknownModeStrings: 0,
            maxNewOverloadTokens: 0,
            maxInvalidFrameRatioDelta: 0
        )
    )

    #expect(report.passed == false)
    #expect(report.newUnknownModeStrings.contains("MODE:NEW"))
    #expect(report.newOverloadTokens.contains("OVER_RANGE"))
    #expect(report.thresholdFailures.contains("new_unknown_mode_strings_exceeded"))
    #expect(report.thresholdFailures.contains("new_overload_tokens_exceeded"))
    #expect(report.thresholdFailures.contains("invalid_frame_ratio_delta_exceeded"))
}
