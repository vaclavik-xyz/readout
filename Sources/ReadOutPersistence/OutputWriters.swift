import Foundation
import ReadOutCore

public actor CsvLogger {
    private var openHandle: FileHandle?
    private var openPath: String?
    private var headerWritten: Set<String> = []
    private let isoFormatter = ISO8601DateFormatter()

    private var pendingData = Data()
    private let flushThreshold = 8192
    private var rowsSinceSync = 0
    private let syncEveryN = 60

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

    public func flush() throws {
        guard !pendingData.isEmpty else { return }
        guard let handle = openHandle else { return }
        try handle.write(contentsOf: pendingData)
        try handle.synchronize()
        pendingData.removeAll(keepingCapacity: true)
        rowsSinceSync = 0
    }

    public func close() {
        try? flush()
        try? openHandle?.close()
        openHandle = nil
        openPath = nil
    }

    private func appendRow(to filePath: String, header: [String], row: [String]) throws {
        try ensureHandle(for: filePath)

        if !headerWritten.contains(filePath) {
            let headerLine = header.map(escapeCSV).joined(separator: ",") + "\n"
            if let data = headerLine.data(using: .utf8) {
                pendingData.append(data)
            }
            headerWritten.insert(filePath)
        }

        let line = row.map(escapeCSV).joined(separator: ",") + "\n"
        guard let data = line.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        pendingData.append(data)
        rowsSinceSync += 1

        if pendingData.count >= flushThreshold || rowsSinceSync >= syncEveryN {
            try flush()
        }
    }

    private func ensureHandle(for filePath: String) throws {
        if openPath == filePath, openHandle != nil {
            return
        }

        // Close previous handle if switching files
        close()

        let url = URL(fileURLWithPath: filePath)
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        if !fm.fileExists(atPath: filePath) {
            fm.createFile(atPath: filePath, contents: nil)
        }

        guard let handle = try? FileHandle(forWritingTo: url) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try handle.seekToEnd()

        // If file already has content, mark header as written
        if try handle.offset() > 0 {
            headerWritten.insert(filePath)
        }

        openHandle = handle
        openPath = filePath
    }

    private func escapeCSV(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    private func isoTimestamp(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    private func numberString(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(value)
    }
}

public actor ObsOutputWriter {
    private var lastWrittenText: [String: String] = [:]

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

    public func flush() throws {
        // Force write any pending values (no-op currently; all writes are immediate when value changes)
    }

    private func writeText(_ text: String, to filePath: String) throws {
        if lastWrittenText[filePath] == text {
            return
        }

        let url = URL(fileURLWithPath: filePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        lastWrittenText[filePath] = text
    }
}
