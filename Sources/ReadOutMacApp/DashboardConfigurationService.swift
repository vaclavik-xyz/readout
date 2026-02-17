import Foundation
import ReadOutIO
import ReadOutPersistence

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

        let realPorts = availablePorts.filter { $0 != SimulatedPort.multimeter && $0 != SimulatedPort.usbC }

        if config.multimeterPort.isEmpty, let first = realPorts.first {
            config.multimeterPort = first
        }
        if config.usbcPort.isEmpty, let first = realPorts.first {
            config.usbcPort = first
        }

        return config
    }
}
