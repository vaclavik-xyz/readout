import Foundation
import ReadOutIO
import ReadOutPersistence

struct PortProbeCandidate: Identifiable, Equatable {
    let port: String
    let score: Int
    let matchedHints: [String]

    var id: String { port }
}

struct PortProbeResult: Equatable {
    let multimeterCandidates: [PortProbeCandidate]
    let usbcCandidates: [PortProbeCandidate]
    let recommendedMultimeterPort: String?
    let recommendedUsbCPort: String?

    static let empty = PortProbeResult(
        multimeterCandidates: [],
        usbcCandidates: [],
        recommendedMultimeterPort: nil,
        recommendedUsbCPort: nil
    )
}

struct DashboardConfigurationService {
    func resolveConfigURL() -> URL {
        let fm = FileManager.default

        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support", isDirectory: true)

        let readOutConfig = appSupport
            .appendingPathComponent("readOut", isDirectory: true)
            .appendingPathComponent("config.json")

        let legacyConfig = appSupport
            .appendingPathComponent("Multimeter", isDirectory: true)
            .appendingPathComponent("config.json")

        if !fm.fileExists(atPath: readOutConfig.path), fm.fileExists(atPath: legacyConfig.path) {
            return legacyConfig
        }

        return readOutConfig
    }

    func resolveRuntimeLogDirectoryURL() -> URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support", isDirectory: true)

        return appSupport
            .appendingPathComponent("readOut", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
    }

    func discoverPorts() -> [String] {
        var discovered = SerialPortDiscovery.listPorts()
        for port in [SimulatedPort.multimeter, SimulatedPort.usbC] where !discovered.contains(port) {
            discovered.append(port)
        }
        return discovered
    }

    func probePorts(_ availablePorts: [String]) -> PortProbeResult {
        let realPorts = availablePorts.filter { isHardwarePort($0) }
        guard !realPorts.isEmpty else {
            return .empty
        }

        let multimeterCandidates = scoredCandidates(
            for: .multimeter,
            ports: realPorts,
            excluding: []
        )

        let recommendedMultimeterPort = multimeterCandidates.first?.port

        let usbcCandidates = scoredCandidates(
            for: .usbc,
            ports: realPorts,
            excluding: Set([recommendedMultimeterPort].compactMap { $0 })
        )

        return PortProbeResult(
            multimeterCandidates: multimeterCandidates,
            usbcCandidates: usbcCandidates,
            recommendedMultimeterPort: recommendedMultimeterPort,
            recommendedUsbCPort: usbcCandidates.first?.port
        )
    }

    func initialWizardConfiguration(availablePorts: [String]) -> AppConfiguration {
        var config = AppConfiguration()
        let probeResult = probePorts(availablePorts)

        if let multimeterPort = probeResult.recommendedMultimeterPort {
            config.useSimulator = false
            config.multimeterEnabled = true
            config.usbcEnabled = probeResult.recommendedUsbCPort != nil
            config.multimeterPort = multimeterPort
            config.usbcPort = probeResult.recommendedUsbCPort ?? ""
        } else {
            config.useSimulator = true
            config.multimeterEnabled = true
            config.usbcEnabled = true
            config.multimeterPort = SimulatedPort.multimeter
            config.usbcPort = SimulatedPort.usbC
        }

        return normalized(config, availablePorts: availablePorts)
    }

    func connectBlockingIssues(configuration: AppConfiguration, availablePorts: [String]) -> [String] {
        guard !configuration.useSimulator else {
            return []
        }

        let realPorts = Set(availablePorts.filter { isHardwarePort($0) })
        var issues: [String] = []

        if configuration.multimeterEnabled {
            let port = configuration.multimeterPort.trimmingCharacters(in: .whitespacesAndNewlines)
            if port.isEmpty {
                issues.append("Multimeter port is empty.")
            } else if !realPorts.contains(port) {
                issues.append("Multimeter port is not detected: \(port)")
            }
        }

        if configuration.usbcEnabled {
            let port = configuration.usbcPort.trimmingCharacters(in: .whitespacesAndNewlines)
            if port.isEmpty {
                issues.append("USB-C meter port is empty.")
            } else if !realPorts.contains(port) {
                issues.append("USB-C meter port is not detected: \(port)")
            }
        }

        return issues
    }

    func normalized(_ raw: AppConfiguration, availablePorts: [String]) -> AppConfiguration {
        var config = raw

        config.sampleRateHz = max(1, min(50, config.sampleRateHz))
        config.graphHistorySeconds = max(5, min(600, config.graphHistorySeconds))
        config.outputQueueCapacity = max(8, min(2048, config.outputQueueCapacity))
        config.outputQueueMaxRetryAttempts = max(0, min(10, config.outputQueueMaxRetryAttempts))
        config.shortThreshold = max(0.1, config.shortThreshold)

        if config.useSimulator {
            config.multimeterPort = SimulatedPort.multimeter
            config.usbcPort = SimulatedPort.usbC
            return config
        }

        let realPorts = availablePorts.filter { isHardwarePort($0) }

        if config.multimeterPort.isEmpty, let first = realPorts.first {
            config.multimeterPort = first
        }
        if config.usbcPort.isEmpty, let first = realPorts.first {
            config.usbcPort = first
        }

        return config
    }

    private func isHardwarePort(_ port: String) -> Bool {
        port != SimulatedPort.multimeter && port != SimulatedPort.usbC
    }

    private func scoredCandidates(
        for profile: DeviceProfile,
        ports: [String],
        excluding: Set<String>
    ) -> [PortProbeCandidate] {
        ports
            .filter { !excluding.contains($0) }
            .map { port in
                let hints = profile.matchedHints(in: port)
                var score = profile.baseScore(for: port)
                score += hints.count * 25
                if port.lowercased().contains("usb") {
                    score += 4
                }
                return PortProbeCandidate(port: port, score: score, matchedHints: hints)
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.port < rhs.port
                }
                return lhs.score > rhs.score
            }
    }
}

private enum DeviceProfile {
    case multimeter
    case usbc

    func matchedHints(in port: String) -> [String] {
        let value = port.lowercased()
        return hints.filter { value.contains($0) }
    }

    func baseScore(for port: String) -> Int {
        let value = port.lowercased()
        var score = 0
        if value.contains("bluetooth") {
            score -= 8
        }
        if value.contains("modem"), self == .usbc {
            score += 8
        }
        if value.contains("serial"), self == .multimeter {
            score += 8
        }
        return score
    }

    private var hints: [String] {
        switch self {
        case .multimeter:
            return [
                "multimeter",
                "meter",
                "usbserial",
                "wchusbserial",
                "cp210",
                "ch34",
                "ftdi",
                "dmm"
            ]
        case .usbc:
            return [
                "usbc",
                "usb-c",
                "power",
                "meter",
                "usbmodem",
                "ttyacm",
                "cyp"
            ]
        }
    }
}
