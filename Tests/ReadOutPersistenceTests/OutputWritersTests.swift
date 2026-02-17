import Foundation
import Testing
@testable import ReadOutPersistence
@testable import ReadOutCore

private func tempFileURL(_ name: String) -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("readout-output-tests-\(UUID().uuidString)", isDirectory: true)
    return dir.appendingPathComponent(name)
}

@Test
func multimeterCsvLoggerWritesHeaderOnce() async throws {
    let logger = CsvLogger()
    let fileURL = tempFileURL("multimeter.csv")

    let measurement = DeviceMeasurement(
        device: .multimeter,
        mode: .dcVoltage,
        modeString: "VOLT:DC",
        primaryValue: 12.3,
        primaryUnit: "V DC",
        timestamp: Date(timeIntervalSince1970: 0)
    )

    try await logger.logMultimeter(to: fileURL.path, measurement: measurement, formattedValue: "12.300")
    try await logger.logMultimeter(to: fileURL.path, measurement: measurement, formattedValue: "12.300")

    let content = try String(contentsOf: fileURL, encoding: .utf8)
    let lines = content.split(separator: "\n").map(String.init)
    #expect(lines.count == 3)
    #expect(lines[0] == "timestamp,mode,raw_value,formatted_value,unit")
}

@Test
func usbCCsvLoggerWritesExpectedColumns() async throws {
    let logger = CsvLogger()
    let fileURL = tempFileURL("usbc.csv")

    let measurement = DeviceMeasurement(
        device: .usbC,
        mode: .dcVoltage,
        modeString: "USB-C Power",
        primaryValue: 5.0,
        primaryUnit: "V DC",
        secondaryValue: 1.5,
        secondaryUnit: "A DC",
        powerWatts: 7.5,
        energyMWh: 12.0,
        energyMAh: 3.0,
        timestamp: Date(timeIntervalSince1970: 0)
    )

    try await logger.logUsbC(to: fileURL.path, measurement: measurement)
    let content = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(content.contains("timestamp,voltage,current,power,energy_mwh,energy_mah"))
    #expect(content.contains(",5.0,1.5,7.5,12.0,3.0"))
}

@Test
func obsWriterAppliesModesAndTemplates() async throws {
    let writer = ObsOutputWriter()
    let mmURL = tempFileURL("mm.txt")
    let usbcURL = tempFileURL("usbc.txt")

    try await writer.writeMultimeter(
        to: mmURL.path,
        mode: .customTemplate,
        displayText: "SHORT",
        displayUnit: "(0.4Ω)",
        modeText: "Continuity",
        label: "Probe",
        customTemplate: "[{label}] {mode}: {value} {unit}"
    )

    let mmContent = try String(contentsOf: mmURL, encoding: .utf8)
    #expect(mmContent == "[Probe] Continuity: SHORT (0.4Ω)")

    try await writer.writeUsbC(
        to: usbcURL.path,
        mode: .valueAndUnit,
        voltage: 9.1234,
        current: 1.23456,
        power: 11.2623,
        label: "",
        customTemplate: ""
    )
    let usbcContent = try String(contentsOf: usbcURL, encoding: .utf8)
    #expect(usbcContent == "9.123V 1.2346A 11.262W")
}
