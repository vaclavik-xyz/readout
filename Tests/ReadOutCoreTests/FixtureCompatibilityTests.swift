import Foundation
import Testing
@testable import ReadOutCore

private struct MultimeterFixtureCase: Codable {
    struct Expected: Codable {
        let mode: String
        let value: Double?
        let unit: String
        let isOverload: Bool
        let isOpen: Bool
    }

    let response: String
    let mode: String
    let expected: Expected
}

private struct UsbCFixtureCase: Codable {
    let frame: String
    let valid: Bool
    let expectedVoltage: Double?
    let expectedCurrent: Double?
}

private enum FixtureLoadError: Error {
    case missingFile(String)
}

@Test
func multimeterParserMatchesFixtures() throws {
    let fixtures: [MultimeterFixtureCase] = try loadFixture("multimeter_fixtures")

    for fixture in fixtures {
        let result = MultimeterParser.parse(response: fixture.response, modeString: fixture.mode)
        let parsed = try #require(result, "Expected non-nil parse result for fixture mode \(fixture.mode)")

        #expect(stringifyMode(parsed.mode) == fixture.expected.mode)
        #expect(parsed.value == fixture.expected.value)
        #expect(parsed.unit == fixture.expected.unit)
        #expect(parsed.isOverload == fixture.expected.isOverload)
        #expect(parsed.isOpen == fixture.expected.isOpen)
    }
}

@Test
func usbCParserMatchesFixtures() throws {
    let fixtures: [UsbCFixtureCase] = try loadFixture("usbc_frame_fixtures")

    for fixture in fixtures {
        #expect(UsbCFrameParser.isValidFrame(fixture.frame) == fixture.valid)
        let parsed = UsbCFrameParser.parse(fixture.frame)
        if fixture.valid {
            let parsed = try #require(parsed, "Expected valid frame to parse")
            #expect(parsed.voltage == fixture.expectedVoltage)
            #expect(parsed.current == fixture.expectedCurrent)
        } else {
            #expect(parsed == nil)
        }
    }
}

private func loadFixture<T: Decodable>(_ name: String) throws -> T {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
        throw FixtureLoadError.missingFile(name)
    }
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(T.self, from: data)
}

private func stringifyMode(_ mode: MeasurementMode) -> String {
    switch mode {
    case .dcVoltage: return "dcVoltage"
    case .acVoltage: return "acVoltage"
    case .resistance: return "resistance"
    case .continuity: return "continuity"
    case .diode: return "diode"
    case .dcCurrent: return "dcCurrent"
    case .acCurrent: return "acCurrent"
    case .capacitance: return "capacitance"
    case .frequency: return "frequency"
    case .period: return "period"
    case .temperature: return "temperature"
    case .unknown: return "unknown"
    }
}
