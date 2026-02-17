import Foundation

public struct MultimeterParsedMeasurement: Equatable, Sendable {
    public let mode: MeasurementMode
    public let modeString: String
    public let value: Double?
    public let unit: String
    public let isOverload: Bool
    public let isOpen: Bool

    public init(
        mode: MeasurementMode,
        modeString: String,
        value: Double?,
        unit: String,
        isOverload: Bool,
        isOpen: Bool
    ) {
        self.mode = mode
        self.modeString = modeString
        self.value = value
        self.unit = unit
        self.isOverload = isOverload
        self.isOpen = isOpen
    }
}

public enum MultimeterParser {
    private static let overloadThreshold: Double = 1e7

    private static let modeUnits: [String: String] = [
        "VOLT": "V",
        "VOLT:DC": "V DC",
        "VOLT:AC": "V AC",
        "CURR": "A",
        "CURR:DC": "A DC",
        "CURR:AC": "A AC",
        "RES": "Ω",
        "FRES": "Ω",
        "CAP": "F",
        "FREQ": "Hz",
        "PER": "s",
        "CONT": "Ω",
        "DIOD": "V",
        "TEMP": "°C"
    ]

    public static func parse(response: String?, modeString: String) -> MultimeterParsedMeasurement? {
        guard let response else {
            return nil
        }

        let trimmedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedResponse.isEmpty {
            return nil
        }

        let normalizedMode = modeString.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let mode = MeasurementModeParser.parse(normalizedMode)
        let openCandidate = isOpenCandidate(mode)

        let upperResponse = trimmedResponse.uppercased()
        let keywordOverload = upperResponse.contains("OL") || upperResponse.contains("OVER")
        if keywordOverload {
            return MultimeterParsedMeasurement(
                mode: mode,
                modeString: normalizedMode,
                value: nil,
                unit: resolvedUnit(modeString: normalizedMode, mode: mode),
                isOverload: true,
                isOpen: openCandidate
            )
        }

        let firstSegment = trimmedResponse.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? trimmedResponse
        guard let numericPrefix = extractNumericPrefix(from: firstSegment),
              let parsedValue = Double(numericPrefix.replacingOccurrences(of: ",", with: ".")) else {
            // Matches legacy behavior: parse failure => empty measurement unit/value.
            return MultimeterParsedMeasurement(
                mode: mode,
                modeString: normalizedMode,
                value: nil,
                unit: "",
                isOverload: false,
                isOpen: false
            )
        }

        if isValueOverload(parsedValue, mode: mode) {
            return MultimeterParsedMeasurement(
                mode: mode,
                modeString: normalizedMode,
                value: nil,
                unit: resolvedUnit(modeString: normalizedMode, mode: mode),
                isOverload: true,
                isOpen: openCandidate
            )
        }

        return MultimeterParsedMeasurement(
            mode: mode,
            modeString: normalizedMode,
            value: parsedValue,
            unit: resolvedUnit(modeString: normalizedMode, mode: mode),
            isOverload: false,
            isOpen: false
        )
    }

    public static func isValueOverload(_ value: Double, mode: MeasurementMode) -> Bool {
        switch mode {
        case .diode, .resistance, .continuity:
            return abs(value) >= overloadThreshold
        default:
            return abs(value) >= 1e30
        }
    }

    private static func isOpenCandidate(_ mode: MeasurementMode) -> Bool {
        switch mode {
        case .resistance, .continuity, .diode:
            return true
        default:
            return false
        }
    }

    private static func resolvedUnit(modeString: String, mode: MeasurementMode) -> String {
        if let mapped = modeUnits[modeString] {
            return mapped
        }

        switch mode {
        case .dcVoltage:
            return "V DC"
        case .acVoltage:
            return "V AC"
        case .dcCurrent:
            return "A DC"
        case .acCurrent:
            return "A AC"
        case .resistance, .continuity:
            return "Ω"
        case .diode:
            return "V"
        case .capacitance:
            return "F"
        case .frequency:
            return "Hz"
        case .temperature:
            return "°C"
        case .period:
            return "s"
        case .unknown:
            return ""
        }
    }

    private static func extractNumericPrefix(from text: String) -> String? {
        let pattern = #"^([+-]?\d+\.?\d*(?:[Ee][+-]?\d+)?)\s*(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, options: [], range: fullRange),
              match.numberOfRanges >= 2 else {
            return text
        }
        let group = match.range(at: 1)
        if group.location == NSNotFound {
            return text
        }
        return nsText.substring(with: group)
    }
}
