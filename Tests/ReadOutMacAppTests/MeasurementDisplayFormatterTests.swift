import Foundation
import Testing
@testable import ReadOutMacApp
@testable import ReadOutCore

// MARK: - multimeterPrimary

@Test
func multimeterPrimaryShowsOpenWhenOpen() {
    let m = DeviceMeasurement(
        device: .multimeter, mode: .dcVoltage, modeString: "VOLT:DC",
        primaryValue: nil, primaryUnit: "V DC", isOpen: true
    )
    #expect(MeasurementDisplayFormatter.multimeterPrimary(m) == "OPEN")
}

@Test
func multimeterPrimaryShowsShortWhenShort() {
    let m = DeviceMeasurement(
        device: .multimeter, mode: .continuity, modeString: "CONT",
        primaryValue: 0.5, primaryUnit: "Ω", isShort: true
    )
    #expect(MeasurementDisplayFormatter.multimeterPrimary(m) == "SHORT")
}

@Test
func multimeterPrimaryShowsOverloadWhenOverload() {
    let m = DeviceMeasurement(
        device: .multimeter, mode: .dcVoltage, modeString: "VOLT:DC",
        primaryValue: nil, primaryUnit: "V DC", isOverload: true
    )
    #expect(MeasurementDisplayFormatter.multimeterPrimary(m) == "OVERLOAD")
}

@Test
func multimeterPrimaryShowsDashesWhenNilValue() {
    let m = DeviceMeasurement(
        device: .multimeter, mode: .dcVoltage, modeString: "VOLT:DC",
        primaryValue: nil, primaryUnit: "V DC"
    )
    #expect(MeasurementDisplayFormatter.multimeterPrimary(m) == "---")
}

@Test
func multimeterPrimaryFormatsValueToFourDecimalPlaces() {
    let m = DeviceMeasurement(
        device: .multimeter, mode: .dcVoltage, modeString: "VOLT:DC",
        primaryValue: 12.3, primaryUnit: "V DC"
    )
    #expect(MeasurementDisplayFormatter.multimeterPrimary(m) == "12.3000")
}

@Test
func multimeterPrimaryFormatsZeroValue() {
    let m = DeviceMeasurement(
        device: .multimeter, mode: .dcVoltage, modeString: "VOLT:DC",
        primaryValue: 0.0, primaryUnit: "V DC"
    )
    #expect(MeasurementDisplayFormatter.multimeterPrimary(m) == "0.0000")
}

@Test
func multimeterPrimaryFormatsNegativeValue() {
    let m = DeviceMeasurement(
        device: .multimeter, mode: .dcVoltage, modeString: "VOLT:DC",
        primaryValue: -3.14159, primaryUnit: "V DC"
    )
    #expect(MeasurementDisplayFormatter.multimeterPrimary(m) == "-3.1416")
}

// MARK: - multimeterSecondary

@Test
func multimeterSecondaryReturnsPrimaryUnit() {
    let m = DeviceMeasurement(
        device: .multimeter, mode: .dcVoltage, modeString: "VOLT:DC",
        primaryValue: 5.0, primaryUnit: "V DC"
    )
    #expect(MeasurementDisplayFormatter.multimeterSecondary(m) == "V DC")
}

@Test
func multimeterSecondaryReturnsEmptyStringWhenUnitIsEmpty() {
    let m = DeviceMeasurement(
        device: .multimeter, mode: .unknown, modeString: "",
        primaryValue: nil, primaryUnit: ""
    )
    #expect(MeasurementDisplayFormatter.multimeterSecondary(m) == "")
}

// MARK: - multimeterModeTitle

@Test
func multimeterModeTitleDCVoltage() {
    let m = DeviceMeasurement(
        device: .multimeter, mode: .dcVoltage, modeString: "VOLT:DC",
        primaryValue: nil, primaryUnit: ""
    )
    #expect(MeasurementDisplayFormatter.multimeterModeTitle(m) == "DC Voltage")
}

@Test
func multimeterModeTitleACVoltage() {
    let m = DeviceMeasurement(
        device: .multimeter, mode: .acVoltage, modeString: "VOLT:AC",
        primaryValue: nil, primaryUnit: ""
    )
    #expect(MeasurementDisplayFormatter.multimeterModeTitle(m) == "AC Voltage")
}

@Test
func multimeterModeTitleAllKnownModes() {
    let expectations: [(MeasurementMode, String)] = [
        (.dcVoltage, "DC Voltage"),
        (.acVoltage, "AC Voltage"),
        (.resistance, "Resistance"),
        (.continuity, "Continuity"),
        (.diode, "Diode"),
        (.dcCurrent, "DC Current"),
        (.acCurrent, "AC Current"),
        (.capacitance, "Capacitance"),
        (.frequency, "Frequency"),
        (.period, "Period"),
        (.temperature, "Temperature"),
    ]

    for (mode, expected) in expectations {
        let m = DeviceMeasurement(
            device: .multimeter, mode: mode, modeString: "",
            primaryValue: nil, primaryUnit: ""
        )
        #expect(
            MeasurementDisplayFormatter.multimeterModeTitle(m) == expected,
            "Expected \(expected) for mode \(mode)"
        )
    }
}

@Test
func multimeterModeTitleUnknownWithEmptyModeString() {
    let m = DeviceMeasurement(
        device: .multimeter, mode: .unknown, modeString: "",
        primaryValue: nil, primaryUnit: ""
    )
    #expect(MeasurementDisplayFormatter.multimeterModeTitle(m) == "Unknown")
}

@Test
func multimeterModeTitleUnknownWithNonEmptyModeString() {
    let m = DeviceMeasurement(
        device: .multimeter, mode: .unknown, modeString: "CUSTOM:MODE",
        primaryValue: nil, primaryUnit: ""
    )
    #expect(MeasurementDisplayFormatter.multimeterModeTitle(m) == "CUSTOM:MODE")
}
