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
    try await logger.flush()

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
    try await logger.flush()
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

// MARK: - Batch buffer tests

@Test
func csvLoggerBatchesRowsAndFlushesCorrectly() async throws {
    let logger = CsvLogger()
    let fileURL = tempFileURL("batch.csv")

    let measurement = DeviceMeasurement(
        device: .multimeter,
        mode: .dcVoltage,
        modeString: "VOLT:DC",
        primaryValue: 1.0,
        primaryUnit: "V DC",
        timestamp: Date(timeIntervalSince1970: 0)
    )

    // Write 3 rows without flushing — file should not yet have all content
    for _ in 0..<3 {
        try await logger.logMultimeter(to: fileURL.path, measurement: measurement, formattedValue: "1.0000")
    }

    // After close, everything should be flushed
    await logger.close()

    let content = try String(contentsOf: fileURL, encoding: .utf8)
    let lines = content.split(separator: "\n").map(String.init)
    #expect(lines.count == 4) // 1 header + 3 data rows
    #expect(lines[0] == "timestamp,mode,raw_value,formatted_value,unit")
}

@Test
func csvLoggerCloseFlushesAllPendingData() async throws {
    let logger = CsvLogger()
    let fileURL = tempFileURL("close-flush.csv")

    let measurement = DeviceMeasurement(
        device: .usbC,
        mode: .dcVoltage,
        modeString: "USB-C",
        primaryValue: 5.1,
        primaryUnit: "V",
        secondaryValue: 2.0,
        powerWatts: 10.2,
        energyMWh: 1.0,
        energyMAh: 0.5,
        timestamp: Date(timeIntervalSince1970: 100)
    )

    try await logger.logUsbC(to: fileURL.path, measurement: measurement)
    await logger.close()

    let content = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(content.contains("5.1"))
    #expect(content.contains("timestamp,voltage"))
}

// MARK: - OBS deduplication tests

@Test
func obsWriterSkipsSameValue() async throws {
    let writer = ObsOutputWriter()
    let fileURL = tempFileURL("obs-dedup.txt")

    // First write should go through
    try await writer.writeMultimeter(
        to: fileURL.path,
        mode: .valueOnly,
        displayText: "12.3456",
        displayUnit: "V DC",
        modeText: "DC Voltage",
        label: "",
        customTemplate: ""
    )
    let content1 = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(content1 == "12.3456")

    // Get modification date after first write
    let attrs1 = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    let mod1 = attrs1[.modificationDate] as? Date

    // Small delay to ensure timestamp difference if file were rewritten
    try await Task.sleep(nanoseconds: 50_000_000) // 50ms

    // Second write with same text should be skipped (no disk I/O)
    try await writer.writeMultimeter(
        to: fileURL.path,
        mode: .valueOnly,
        displayText: "12.3456",
        displayUnit: "V DC",
        modeText: "DC Voltage",
        label: "",
        customTemplate: ""
    )

    let attrs2 = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    let mod2 = attrs2[.modificationDate] as? Date
    #expect(mod1 == mod2, "File should not be rewritten when text is the same")
}

@Test
func obsWriterWritesOnValueChange() async throws {
    let writer = ObsOutputWriter()
    let fileURL = tempFileURL("obs-change.txt")

    try await writer.writeMultimeter(
        to: fileURL.path,
        mode: .valueOnly,
        displayText: "1.0000",
        displayUnit: "V DC",
        modeText: "DC Voltage",
        label: "",
        customTemplate: ""
    )

    let content1 = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(content1 == "1.0000")

    // Write with different value
    try await writer.writeMultimeter(
        to: fileURL.path,
        mode: .valueOnly,
        displayText: "2.0000",
        displayUnit: "V DC",
        modeText: "DC Voltage",
        label: "",
        customTemplate: ""
    )

    let content2 = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(content2 == "2.0000")
}

@Test
func csvLoggerReusesFileHandleAcrossWrites() async throws {
    let logger = CsvLogger()
    let fileURL = tempFileURL("reuse-handle.csv")

    // Multiple writes to same path should reuse handle
    for i in 0..<10 {
        let m = DeviceMeasurement(
            device: .multimeter,
            mode: .dcVoltage,
            modeString: "VOLT:DC",
            primaryValue: Double(i),
            primaryUnit: "V DC",
            timestamp: Date(timeIntervalSince1970: Double(i))
        )
        try await logger.logMultimeter(to: fileURL.path, measurement: m, formattedValue: "\(i).0000")
    }

    await logger.close()

    let content = try String(contentsOf: fileURL, encoding: .utf8)
    let lines = content.split(separator: "\n").map(String.init)
    #expect(lines.count == 11) // 1 header + 10 rows
}
