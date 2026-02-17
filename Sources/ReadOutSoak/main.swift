import Foundation
import ReadOutIO

struct SoakCLIOptions {
    var preset: SoakPreset = .smoke
    var seed: UInt64 = 42
    var outputPath: String?
    var targetFramesOverride: Int?
    var timeoutOverrideSeconds: Double?
}

@main
struct ReadOutSoakMain {
    static func main() async {
        do {
            let options = try parseOptions(arguments: CommandLine.arguments)
            var configuration = options.preset.configuration(seed: options.seed)
            if let frames = options.targetFramesOverride {
                configuration.targetFrames = max(1, frames)
                configuration.thresholds = SoakThresholds(
                    maxTransportErrors: configuration.thresholds.maxTransportErrors,
                    maxReconnectAttempts: configuration.thresholds.maxReconnectAttempts,
                    minFramesCaptured: max(1, frames)
                )
            }
            if let timeout = options.timeoutOverrideSeconds {
                configuration.timeoutSeconds = max(1, timeout)
            }

            let summary = await SoakRunner.runStreamingSimulation(configuration: configuration)

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(summary)

            if let outputPath = options.outputPath, !outputPath.isEmpty {
                let url = URL(fileURLWithPath: outputPath)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: url, options: .atomic)
                print("Soak summary written to \(url.path)")
            } else {
                if let text = String(data: data, encoding: .utf8) {
                    print(text)
                }
            }

            if summary.passed {
                exit(EXIT_SUCCESS)
            } else {
                exit(2)
            }
        } catch {
            fputs("ReadOutSoak failed: \(error.localizedDescription)\n", stderr)
            fputs(usage(), stderr)
            exit(1)
        }
    }
}

private func parseOptions(arguments: [String]) throws -> SoakCLIOptions {
    var options = SoakCLIOptions()
    var idx = 1

    while idx < arguments.count {
        let arg = arguments[idx]
        switch arg {
        case "--preset":
            idx += 1
            guard idx < arguments.count else { throw ParseError.missingValue("--preset") }
            guard let preset = SoakPreset(rawValue: arguments[idx]) else {
                throw ParseError.invalidPreset(arguments[idx])
            }
            options.preset = preset

        case "--seed":
            idx += 1
            guard idx < arguments.count else { throw ParseError.missingValue("--seed") }
            guard let seed = UInt64(arguments[idx]) else {
                throw ParseError.invalidNumber("--seed", arguments[idx])
            }
            options.seed = seed

        case "--output":
            idx += 1
            guard idx < arguments.count else { throw ParseError.missingValue("--output") }
            options.outputPath = arguments[idx]

        case "--target-frames":
            idx += 1
            guard idx < arguments.count else { throw ParseError.missingValue("--target-frames") }
            guard let frames = Int(arguments[idx]) else {
                throw ParseError.invalidNumber("--target-frames", arguments[idx])
            }
            options.targetFramesOverride = frames

        case "--timeout-seconds":
            idx += 1
            guard idx < arguments.count else { throw ParseError.missingValue("--timeout-seconds") }
            guard let timeout = Double(arguments[idx]) else {
                throw ParseError.invalidNumber("--timeout-seconds", arguments[idx])
            }
            options.timeoutOverrideSeconds = timeout

        case "--help", "-h":
            print(usage())
            exit(0)

        default:
            throw ParseError.unknownOption(arg)
        }

        idx += 1
    }

    return options
}

private enum ParseError: LocalizedError {
    case missingValue(String)
    case invalidPreset(String)
    case invalidNumber(String, String)
    case unknownOption(String)

    var errorDescription: String? {
        switch self {
        case .missingValue(let option):
            return "Missing value for \(option)."
        case .invalidPreset(let value):
            return "Invalid preset '\(value)'. Allowed: \(SoakPreset.allCases.map(\.rawValue).joined(separator: ", "))."
        case .invalidNumber(let option, let value):
            return "Invalid numeric value '\(value)' for \(option)."
        case .unknownOption(let option):
            return "Unknown option '\(option)'."
        }
    }
}

private func usage() -> String {
    """
    Usage: swift run ReadOutSoak [options]

    Options:
      --preset <smoke|30m|2h|24h>   Soak preset (default: smoke)
      --seed <uint64>               Deterministic seed (default: 42)
      --output <path>               Write JSON summary to file
      --target-frames <int>         Override preset target frame count
      --timeout-seconds <double>    Override timeout
      --help                        Show this help
    """
}
