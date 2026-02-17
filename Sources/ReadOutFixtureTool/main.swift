import Foundation
import ReadOutCore

@main
struct ReadOutFixtureToolMain {
    static func main() {
        do {
            let command = try parseCommand(arguments: CommandLine.arguments)
            try run(command)
        } catch {
            fputs("ReadOutFixtureTool failed: \(error.localizedDescription)\n", stderr)
            fputs(usage(), stderr)
            exit(1)
        }
    }

    private static func run(_ command: Command) throws {
        switch command {
        case .importMultimeter(let inputPath, let outputPath, let separator):
            let lines = try readLines(from: inputPath)
            let fixtures = FixtureImporter.importMultimeterCapture(lines: lines, separator: separator)
            try writeJSON(fixtures, to: outputPath)
            print("Imported \(fixtures.count) multimeter fixtures to \(outputPath)")

        case .importUsbC(let inputPath, let outputPath):
            let lines = try readLines(from: inputPath)
            let fixtures = FixtureImporter.importUsbCCapture(lines: lines)
            try writeJSON(fixtures, to: outputPath)
            print("Imported \(fixtures.count) USB-C fixtures to \(outputPath)")

        case .validateMultimeter(let inputPath):
            let fixtures: [MultimeterFixtureCase] = try readJSON(from: inputPath)
            let issues = FixtureSchemaValidator.validate(multimeter: fixtures)
            if issues.isEmpty {
                print("Validation passed for multimeter fixtures (\(fixtures.count) entries).")
            } else {
                for issue in issues {
                    print("ISSUE: \(issue)")
                }
                exit(2)
            }

        case .validateUsbC(let inputPath):
            let fixtures: [UsbCFrameFixtureCase] = try readJSON(from: inputPath)
            let issues = FixtureSchemaValidator.validate(usbC: fixtures)
            if issues.isEmpty {
                print("Validation passed for USB-C fixtures (\(fixtures.count) entries).")
            } else {
                for issue in issues {
                    print("ISSUE: \(issue)")
                }
                exit(2)
            }

        case let .driftReport(
            candidateMultimeterPath,
            candidateUsbCPath,
            baselineMultimeterPath,
            baselineUsbCPath,
            outputPath,
            thresholds
        ):
            let candidateMultimeter: [MultimeterFixtureCase] = try readJSON(from: candidateMultimeterPath)
            let candidateUsbC: [UsbCFrameFixtureCase] = try readJSON(from: candidateUsbCPath)
            let baselineMultimeter: [MultimeterFixtureCase] = baselineMultimeterPath == nil ? [] : try readJSON(from: baselineMultimeterPath!)
            let baselineUsbC: [UsbCFrameFixtureCase] = baselineUsbCPath == nil ? [] : try readJSON(from: baselineUsbCPath!)

            let report = ParserDriftAnalyzer.analyze(
                candidateMultimeter: candidateMultimeter,
                candidateUsbC: candidateUsbC,
                baselineMultimeter: baselineMultimeter,
                baselineUsbC: baselineUsbC,
                thresholds: thresholds
            )

            if let outputPath {
                try writeJSON(report, to: outputPath)
            } else {
                let text = try jsonString(report)
                print(text)
            }

            if !report.passed {
                exit(2)
            }
        }
    }
}

private enum Command {
    case importMultimeter(inputPath: String, outputPath: String, separator: FixtureFieldSeparator?)
    case importUsbC(inputPath: String, outputPath: String)
    case validateMultimeter(inputPath: String)
    case validateUsbC(inputPath: String)
    case driftReport(
        candidateMultimeterPath: String,
        candidateUsbCPath: String,
        baselineMultimeterPath: String?,
        baselineUsbCPath: String?,
        outputPath: String?,
        thresholds: ParserDriftThresholds
    )
}

private enum ParseError: LocalizedError {
    case missingSubcommand
    case unknownSubcommand(String)
    case missingValue(String)
    case invalidNumber(String, String)
    case invalidSeparator(String)

    var errorDescription: String? {
        switch self {
        case .missingSubcommand:
            return "Missing subcommand."
        case .unknownSubcommand(let value):
            return "Unknown subcommand '\(value)'."
        case .missingValue(let option):
            return "Missing value for option \(option)."
        case .invalidNumber(let option, let value):
            return "Invalid number '\(value)' for option \(option)."
        case .invalidSeparator(let value):
            return "Invalid separator '\(value)'. Use tab, comma, or pipe."
        }
    }
}

private func parseCommand(arguments: [String]) throws -> Command {
    guard arguments.count >= 2 else {
        throw ParseError.missingSubcommand
    }

    let subcommand = arguments[1]
    let options = try parseOptions(arguments: Array(arguments.dropFirst(2)))

    switch subcommand {
    case "import-multimeter":
        let input = try requiredOption("--input", from: options)
        let output = try requiredOption("--output", from: options)
        let separator: FixtureFieldSeparator?
        if let raw = options["--separator"] {
            guard let parsed = FixtureFieldSeparator(rawValue: raw) else {
                throw ParseError.invalidSeparator(raw)
            }
            separator = parsed
        } else {
            separator = nil
        }
        return .importMultimeter(inputPath: input, outputPath: output, separator: separator)

    case "import-usbc":
        let input = try requiredOption("--input", from: options)
        let output = try requiredOption("--output", from: options)
        return .importUsbC(inputPath: input, outputPath: output)

    case "validate-multimeter":
        let input = try requiredOption("--input", from: options)
        return .validateMultimeter(inputPath: input)

    case "validate-usbc":
        let input = try requiredOption("--input", from: options)
        return .validateUsbC(inputPath: input)

    case "drift-report":
        let candidateMultimeter = try requiredOption("--candidate-multimeter", from: options)
        let candidateUsbC = try requiredOption("--candidate-usbc", from: options)
        let baselineMultimeter = options["--baseline-multimeter"]
        let baselineUsbC = options["--baseline-usbc"]
        let outputPath = options["--output"]

        let maxUnknown = try intOption("--max-new-unknown-modes", from: options, defaultValue: 0)
        let maxOverload = try intOption("--max-new-overload-tokens", from: options, defaultValue: 0)
        let maxInvalidDelta = try doubleOption("--max-invalid-frame-ratio-delta", from: options, defaultValue: 0.0)

        return .driftReport(
            candidateMultimeterPath: candidateMultimeter,
            candidateUsbCPath: candidateUsbC,
            baselineMultimeterPath: baselineMultimeter,
            baselineUsbCPath: baselineUsbC,
            outputPath: outputPath,
            thresholds: ParserDriftThresholds(
                maxNewUnknownModeStrings: maxUnknown,
                maxNewOverloadTokens: maxOverload,
                maxInvalidFrameRatioDelta: maxInvalidDelta
            )
        )

    default:
        throw ParseError.unknownSubcommand(subcommand)
    }
}

private func parseOptions(arguments: [String]) throws -> [String: String] {
    var options: [String: String] = [:]
    var index = 0
    while index < arguments.count {
        let key = arguments[index]
        guard key.hasPrefix("--") else {
            throw ParseError.unknownSubcommand(key)
        }

        index += 1
        guard index < arguments.count else {
            throw ParseError.missingValue(key)
        }
        options[key] = arguments[index]
        index += 1
    }
    return options
}

private func requiredOption(_ name: String, from options: [String: String]) throws -> String {
    guard let value = options[name], !value.isEmpty else {
        throw ParseError.missingValue(name)
    }
    return value
}

private func intOption(_ name: String, from options: [String: String], defaultValue: Int) throws -> Int {
    guard let raw = options[name] else {
        return defaultValue
    }
    guard let value = Int(raw) else {
        throw ParseError.invalidNumber(name, raw)
    }
    return value
}

private func doubleOption(_ name: String, from options: [String: String], defaultValue: Double) throws -> Double {
    guard let raw = options[name] else {
        return defaultValue
    }
    guard let value = Double(raw) else {
        throw ParseError.invalidNumber(name, raw)
    }
    return value
}

private func readLines(from path: String) throws -> [String] {
    let url = URL(fileURLWithPath: path)
    let text = try String(contentsOf: url, encoding: .utf8)
    return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
}

private func readJSON<T: Decodable>(from path: String) throws -> T {
    let url = URL(fileURLWithPath: path)
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(T.self, from: data)
}

private func writeJSON<T: Encodable>(_ value: T, to path: String) throws {
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    try data.write(to: url, options: .atomic)
}

private func jsonString<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    return String(decoding: data, as: UTF8.self)
}

private func usage() -> String {
    """
    Usage: swift run ReadOutFixtureTool <subcommand> [options]

    Subcommands:
      import-multimeter --input <capture.txt> --output <fixtures.json> [--separator tab|comma|pipe]
      import-usbc --input <capture.txt> --output <fixtures.json>
      validate-multimeter --input <fixtures.json>
      validate-usbc --input <fixtures.json>
      drift-report --candidate-multimeter <fixtures.json> --candidate-usbc <fixtures.json> [--baseline-multimeter <fixtures.json>] [--baseline-usbc <fixtures.json>] [--output <report.json>] [--max-new-unknown-modes <int>] [--max-new-overload-tokens <int>] [--max-invalid-frame-ratio-delta <double>]
    """
}
