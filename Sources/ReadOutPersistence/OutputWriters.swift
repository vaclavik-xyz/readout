import Foundation
import ReadOutCore

public actor CsvLogger {
    public init() {}

    public func logMultimeter(
        to filePath: String,
        measurement: DeviceMeasurement,
        formattedValue: String
    ) throws {
        guard !filePath.isEmpty else { return }

        let row = [
            isoTimestamp(measurement.timestamp),
            measurement.modeString,
            numberString(measurement.primaryValue),
            formattedValue,
            measurement.primaryUnit
        ]
        try appendRow(
            to: filePath,
            header: ["timestamp", "mode", "raw_value", "formatted_value", "unit"],
            row: row
        )
    }

    public func logUsbC(
        to filePath: String,
        measurement: DeviceMeasurement
    ) throws {
        guard !filePath.isEmpty else { return }

        let row = [
            isoTimestamp(measurement.timestamp),
            numberString(measurement.primaryValue),
            numberString(measurement.secondaryValue),
            numberString(measurement.powerWatts),
            numberString(measurement.energyMWh),
            numberString(measurement.energyMAh)
        ]

        try appendRow(
            to: filePath,
            header: ["timestamp", "voltage", "current", "power", "energy_mwh", "energy_mah"],
            row: row
        )
    }

    private func appendRow(to filePath: String, header: [String], row: [String]) throws {
        let url = URL(fileURLWithPath: filePath)
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let exists = fm.fileExists(atPath: filePath)
        if !exists {
            fm.createFile(atPath: filePath, contents: nil)
            try appendLine(header, to: url)
        }
        try appendLine(row, to: url)
    }

    private func appendLine(_ fields: [String], to url: URL) throws {
        guard let handle = try? FileHandle(forWritingTo: url) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { try? handle.close() }

        try handle.seekToEnd()
        let line = fields.map(escapeCSV).joined(separator: ",") + "\n"
        guard let data = line.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }

    private func escapeCSV(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    private func isoTimestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func numberString(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(value)
    }
}

public actor ObsOutputWriter {
    public init() {}

    public func writeMultimeter(
        to filePath: String,
        mode: AppConfiguration.ObsOutputMode,
        displayText: String,
        displayUnit: String,
        modeText: String,
        label: String,
        customTemplate: String
    ) throws {
        guard !filePath.isEmpty else { return }

        let output: String
        switch mode {
        case .valueOnly:
            output = displayText
        case .valueAndUnit:
            output = displayUnit.isEmpty ? displayText : "\(displayText) \(displayUnit)"
        case .customTemplate:
            output = customTemplate
                .replacingOccurrences(of: "{value}", with: displayText)
                .replacingOccurrences(of: "{unit}", with: displayUnit)
                .replacingOccurrences(of: "{mode}", with: modeText)
                .replacingOccurrences(of: "{label}", with: label)
        }

        try writeText(output, to: filePath)
    }

    public func writeUsbC(
        to filePath: String,
        mode: AppConfiguration.ObsOutputMode,
        voltage: Double,
        current: Double,
        power: Double,
        label: String,
        customTemplate: String
    ) throws {
        guard !filePath.isEmpty else { return }

        let output: String
        switch mode {
        case .valueOnly:
            output = String(format: "%.3f", voltage)
        case .valueAndUnit:
            output = String(format: "%.3fV %.4fA %.3fW", voltage, current, power)
        case .customTemplate:
            output = customTemplate
                .replacingOccurrences(of: "{voltage}", with: String(format: "%.3fV", voltage))
                .replacingOccurrences(of: "{current}", with: String(format: "%.4fA", current))
                .replacingOccurrences(of: "{power}", with: String(format: "%.3fW", power))
                .replacingOccurrences(of: "{label}", with: label)
        }

        try writeText(output, to: filePath)
    }

    private func writeText(_ text: String, to filePath: String) throws {
        let url = URL(fileURLWithPath: filePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
