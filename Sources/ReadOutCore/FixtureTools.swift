import Foundation

public struct MultimeterFixtureExpected: Codable, Equatable, Sendable {
    public let mode: String
    public let value: Double?
    public let unit: String
    public let isOverload: Bool
    public let isOpen: Bool

    public init(mode: String, value: Double?, unit: String, isOverload: Bool, isOpen: Bool) {
        self.mode = mode
        self.value = value
        self.unit = unit
        self.isOverload = isOverload
        self.isOpen = isOpen
    }
}

public struct MultimeterFixtureCase: Codable, Equatable, Sendable {
    public let response: String
    public let mode: String
    public let expected: MultimeterFixtureExpected

    public init(response: String, mode: String, expected: MultimeterFixtureExpected) {
        self.response = response
        self.mode = mode
        self.expected = expected
    }
}

public struct UsbCFrameFixtureCase: Codable, Equatable, Sendable {
    public let frame: String
    public let valid: Bool
    public let expectedVoltage: Double?
    public let expectedCurrent: Double?

    public init(frame: String, valid: Bool, expectedVoltage: Double?, expectedCurrent: Double?) {
        self.frame = frame
        self.valid = valid
        self.expectedVoltage = expectedVoltage
        self.expectedCurrent = expectedCurrent
    }
}

public enum FixtureFieldSeparator: String, Sendable {
    case tab
    case comma
    case pipe

    fileprivate var value: Character {
        switch self {
        case .tab: return "\t"
        case .comma: return ","
        case .pipe: return "|"
        }
    }
}

public enum FixtureImporter {
    public static func importMultimeterCapture(
        lines: [String],
        separator: FixtureFieldSeparator? = nil
    ) -> [MultimeterFixtureCase] {
        var fixtures: [MultimeterFixtureCase] = []

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }

            guard let (mode, response) = splitModeAndResponse(line, separator: separator) else {
                continue
            }

            guard let parsed = MultimeterParser.parse(response: response, modeString: mode) else {
                continue
            }

            fixtures.append(
                MultimeterFixtureCase(
                    response: response,
                    mode: mode,
                    expected: MultimeterFixtureExpected(
                        mode: stringifiedMode(parsed.mode),
                        value: parsed.value,
                        unit: parsed.unit,
                        isOverload: parsed.isOverload,
                        isOpen: parsed.isOpen
                    )
                )
            )
        }

        return fixtures
    }

    public static func importUsbCCapture(lines: [String]) -> [UsbCFrameFixtureCase] {
        var fixtures: [UsbCFrameFixtureCase] = []

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            let frame = firstToken(in: trimmed)
            let valid = UsbCFrameParser.isValidFrame(frame)
            let parsed = UsbCFrameParser.parse(frame)

            fixtures.append(
                UsbCFrameFixtureCase(
                    frame: frame,
                    valid: valid,
                    expectedVoltage: parsed?.voltage,
                    expectedCurrent: parsed?.current
                )
            )
        }

        return fixtures
    }

    private static func splitModeAndResponse(
        _ line: String,
        separator: FixtureFieldSeparator?
    ) -> (String, String)? {
        if let separator {
            return splitOnce(line, separator: separator.value)
        }

        for separator in ["\t", "|", ","] {
            if let pair = splitOnce(line, separator: Character(separator)) {
                return pair
            }
        }
        return nil
    }

    private static func splitOnce(
        _ line: String,
        separator: Character
    ) -> (String, String)? {
        guard let index = line.firstIndex(of: separator) else {
            return nil
        }
        let left = String(line[..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
        let right = String(line[line.index(after: index)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !left.isEmpty, !right.isEmpty else {
            return nil
        }
        return (left, right)
    }

    private static func firstToken(in line: String) -> String {
        line.split { $0 == " " || $0 == "," || $0 == "\t" }.first.map(String.init) ?? line
    }

    private static func stringifiedMode(_ mode: MeasurementMode) -> String {
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
}

public enum FixtureSchemaValidator {
    public static func validate(multimeter fixtures: [MultimeterFixtureCase]) -> [String] {
        var issues: [String] = []

        if fixtures.isEmpty {
            issues.append("multimeter.fixtures.empty")
            return issues
        }

        for (index, fixture) in fixtures.enumerated() {
            if fixture.mode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("multimeter[\(index)].mode.empty")
            }
            if fixture.response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("multimeter[\(index)].response.empty")
            }
            if fixture.expected.mode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("multimeter[\(index)].expected.mode.empty")
            }
        }

        return issues
    }

    public static func validate(usbC fixtures: [UsbCFrameFixtureCase]) -> [String] {
        var issues: [String] = []

        if fixtures.isEmpty {
            issues.append("usbc.fixtures.empty")
            return issues
        }

        for (index, fixture) in fixtures.enumerated() {
            if fixture.frame.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("usbc[\(index)].frame.empty")
            }

            if fixture.valid {
                if fixture.expectedVoltage == nil || fixture.expectedCurrent == nil {
                    issues.append("usbc[\(index)].expected.missing_for_valid_frame")
                }
            } else {
                if fixture.expectedVoltage != nil || fixture.expectedCurrent != nil {
                    issues.append("usbc[\(index)].expected.present_for_invalid_frame")
                }
            }
        }

        return issues
    }
}

public struct ParserDriftThresholds: Sendable, Equatable, Codable {
    public var maxNewUnknownModeStrings: Int
    public var maxNewOverloadTokens: Int
    public var maxInvalidFrameRatioDelta: Double

    public init(
        maxNewUnknownModeStrings: Int,
        maxNewOverloadTokens: Int,
        maxInvalidFrameRatioDelta: Double
    ) {
        self.maxNewUnknownModeStrings = max(0, maxNewUnknownModeStrings)
        self.maxNewOverloadTokens = max(0, maxNewOverloadTokens)
        self.maxInvalidFrameRatioDelta = max(0, maxInvalidFrameRatioDelta)
    }
}

public struct ParserDriftMetrics: Sendable, Equatable, Codable {
    public let multimeterFixtureCount: Int
    public let usbCFixtureCount: Int
    public let unknownModeStrings: [String]
    public let overloadTokens: [String]
    public let invalidUsbCFrameCount: Int
    public let invalidUsbCFrameRatio: Double
}

public struct ParserDriftReport: Sendable, Equatable, Codable {
    public let candidate: ParserDriftMetrics
    public let baseline: ParserDriftMetrics?
    public let newUnknownModeStrings: [String]
    public let newOverloadTokens: [String]
    public let invalidFrameRatioDelta: Double
    public let thresholdFailures: [String]
    public let passed: Bool
}

public enum ParserDriftAnalyzer {
    public static func analyze(
        candidateMultimeter: [MultimeterFixtureCase],
        candidateUsbC: [UsbCFrameFixtureCase],
        baselineMultimeter: [MultimeterFixtureCase] = [],
        baselineUsbC: [UsbCFrameFixtureCase] = [],
        thresholds: ParserDriftThresholds
    ) -> ParserDriftReport {
        let candidateMetrics = collectMetrics(multimeter: candidateMultimeter, usbC: candidateUsbC)
        let baselineMetrics = baselineMultimeter.isEmpty && baselineUsbC.isEmpty
            ? nil
            : collectMetrics(multimeter: baselineMultimeter, usbC: baselineUsbC)

        let baselineUnknownModes = Set(baselineMetrics?.unknownModeStrings ?? [])
        let baselineOverloadTokens = Set(baselineMetrics?.overloadTokens ?? [])

        let candidateUnknownModes = Set(candidateMetrics.unknownModeStrings)
        let candidateOverloadTokens = Set(candidateMetrics.overloadTokens)

        let newUnknownModes = candidateUnknownModes.subtracting(baselineUnknownModes).sorted()
        let newOverloadTokens = candidateOverloadTokens.subtracting(baselineOverloadTokens).sorted()

        let baselineInvalidRatio = baselineMetrics?.invalidUsbCFrameRatio ?? 0
        let invalidRatioDelta = max(0, candidateMetrics.invalidUsbCFrameRatio - baselineInvalidRatio)

        var thresholdFailures: [String] = []
        if newUnknownModes.count > thresholds.maxNewUnknownModeStrings {
            thresholdFailures.append("new_unknown_mode_strings_exceeded")
        }
        if newOverloadTokens.count > thresholds.maxNewOverloadTokens {
            thresholdFailures.append("new_overload_tokens_exceeded")
        }
        if invalidRatioDelta > thresholds.maxInvalidFrameRatioDelta {
            thresholdFailures.append("invalid_frame_ratio_delta_exceeded")
        }

        return ParserDriftReport(
            candidate: candidateMetrics,
            baseline: baselineMetrics,
            newUnknownModeStrings: newUnknownModes,
            newOverloadTokens: newOverloadTokens,
            invalidFrameRatioDelta: invalidRatioDelta,
            thresholdFailures: thresholdFailures,
            passed: thresholdFailures.isEmpty
        )
    }

    private static func collectMetrics(
        multimeter: [MultimeterFixtureCase],
        usbC: [UsbCFrameFixtureCase]
    ) -> ParserDriftMetrics {
        let unknownModeStrings = Set(
            multimeter
                .map(\.mode)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { MeasurementModeParser.parse($0) == .unknown }
        ).sorted()

        let overloadTokens = Set(
            multimeter
                .filter(\.expected.isOverload)
                .compactMap { overloadToken(from: $0.response) }
                .filter { !isNumericToken($0) }
        ).sorted()

        let invalidCount = usbC.filter { !$0.valid }.count
        let invalidRatio = usbC.isEmpty ? 0 : Double(invalidCount) / Double(usbC.count)

        return ParserDriftMetrics(
            multimeterFixtureCount: multimeter.count,
            usbCFixtureCount: usbC.count,
            unknownModeStrings: unknownModeStrings,
            overloadTokens: overloadTokens,
            invalidUsbCFrameCount: invalidCount,
            invalidUsbCFrameRatio: invalidRatio
        )
    }

    private static func overloadToken(from response: String) -> String? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let first = trimmed.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? trimmed
        return first.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isNumericToken(_ token: String) -> Bool {
        Double(token.replacingOccurrences(of: ",", with: ".")) != nil
    }
}
