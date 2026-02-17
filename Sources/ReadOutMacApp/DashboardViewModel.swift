import Foundation
import ReadOutCore
import ReadOutIO
import ReadOutPersistence
#if canImport(AppKit)
import AppKit
#endif

struct ChartSample: Identifiable {
    let id = UUID()
    let timestamp: Date
    let value: Double
}

enum DeviceUIState: String, Sendable {
    case disconnected
    case connecting
    case connected
    case error
}

enum RuntimeEvent: Sendable {
    case multimeterStatus(DeviceUIState, String?)
    case usbcStatus(DeviceUIState, String?)
    case multimeterMeasurement(DeviceMeasurement)
    case usbcMeasurement(DeviceMeasurement)
    case runtimeError(String)
}

final class PcBeepController {
    private var task: Task<Void, Never>?
    private let intervalSeconds: TimeInterval

    init(intervalSeconds: TimeInterval = 0.7) {
        self.intervalSeconds = intervalSeconds
    }

    deinit {
        stop()
    }

    func setBeeping(_ enabled: Bool) {
        if enabled {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard task == nil else {
            return
        }

        let interval = intervalSeconds
        task = Task {
            while !Task.isCancelled {
                #if canImport(AppKit)
                await MainActor.run {
                    NSSound.beep()
                }
                #endif

                let nanos = UInt64(max(0, interval) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
            }
        }
    }

    private func stop() {
        task?.cancel()
        task = nil
    }
}

actor ReadOutRuntime {
    private let onEvent: @Sendable (RuntimeEvent) -> Void

    private var multimeterTask: Task<Void, Never>?
    private var usbcTask: Task<Void, Never>?

    init(onEvent: @escaping @Sendable (RuntimeEvent) -> Void) {
        self.onEvent = onEvent
    }

    func start(with configuration: AppConfiguration) async {
        await stop()

        if configuration.multimeterEnabled {
            if !configuration.useSimulator && configuration.multimeterPort.isEmpty {
                onEvent(.multimeterStatus(.error, "Multimeter port is empty"))
            } else {
                multimeterTask = Task { [configuration, onEvent] in
                    await Self.runMultimeterLoop(configuration: configuration, onEvent: onEvent)
                }
            }
        } else {
            onEvent(.multimeterStatus(.disconnected, nil))
        }

        if configuration.usbcEnabled {
            if !configuration.useSimulator && configuration.usbcPort.isEmpty {
                onEvent(.usbcStatus(.error, "USB-C port is empty"))
            } else {
                usbcTask = Task { [configuration, onEvent] in
                    await Self.runUsbCLoop(configuration: configuration, onEvent: onEvent)
                }
            }
        } else {
            onEvent(.usbcStatus(.disconnected, nil))
        }
    }

    func stop() async {
        let mmTask = multimeterTask
        let ucTask = usbcTask

        multimeterTask = nil
        usbcTask = nil

        mmTask?.cancel()
        ucTask?.cancel()

        _ = await mmTask?.result
        _ = await ucTask?.result

        onEvent(.multimeterStatus(.disconnected, nil))
        onEvent(.usbcStatus(.disconnected, nil))
    }

    private static func runMultimeterLoop(
        configuration: AppConfiguration,
        onEvent: @escaping @Sendable (RuntimeEvent) -> Void
    ) async {
        let reconnectEnabled = configuration.multimeterAutoReconnect
        let sampleIntervalSeconds = 1.0 / Double(max(1, configuration.sampleRateHz))
        let alertConfiguration = configuration.alertConfiguration

        let csvLogger = CsvLogger()
        let obsWriter = ObsOutputWriter()
        var reconnectAttempt = 0

        while !Task.isCancelled {
            onEvent(.multimeterStatus(.connecting, nil))

            let transport: any SCPITransport
            if configuration.useSimulator {
                transport = SimulatedSCPITransport(sampleRateHz: configuration.sampleRateHz)
            } else {
                let lineIO = POSIXSerialPort(
                    configuration: SerialPortConfiguration(
                        path: configuration.multimeterPort,
                        baudRate: 115_200,
                        readTimeoutSeconds: 0.15,
                        writeTimeoutSeconds: 0.15
                    )
                )
                transport = SCPIPollingTransport(lineIO: lineIO)
            }
            let driver = MultimeterDeviceDriver(transport: transport)

            do {
                try await driver.connect()
                reconnectAttempt = 0
                let source = configuration.useSimulator ? "simulator" : configuration.multimeterPort
                onEvent(.multimeterStatus(.connected, "Multimeter connected (\(source))"))

                do {
                    _ = try await driver.setBeeperEnabled(configuration.beepOnShortMeter)
                } catch {
                    onEvent(.runtimeError("Failed to set multimeter beeper: \(error.localizedDescription)"))
                }

                while !Task.isCancelled {
                    if let rawMeasurement = try await driver.readMeasurement(at: Date()) {
                        let measurement = MeasurementAlertEvaluator.enrichMultimeter(
                            measurement: rawMeasurement,
                            configuration: alertConfiguration
                        )

                        do {
                            try await handleMultimeterOutputs(
                                measurement,
                                configuration: configuration,
                                csvLogger: csvLogger,
                                obsWriter: obsWriter
                            )
                        } catch {
                            onEvent(.runtimeError("Multimeter output write failed: \(error.localizedDescription)"))
                        }

                        onEvent(.multimeterMeasurement(measurement))
                    }

                    await sleep(seconds: sampleIntervalSeconds)
                }
            } catch {
                onEvent(.multimeterStatus(.error, "Multimeter error: \(error.localizedDescription)"))
            }

            await driver.disconnect()

            if Task.isCancelled || !reconnectEnabled {
                break
            }

            reconnectAttempt += 1
            let delay = reconnectDelay(forAttempt: reconnectAttempt)
            onEvent(.multimeterStatus(.connecting, "Retrying multimeter in \(String(format: "%.1f", delay))s"))
            await sleep(seconds: delay)
        }

        onEvent(.multimeterStatus(.disconnected, nil))
    }

    private static func runUsbCLoop(
        configuration: AppConfiguration,
        onEvent: @escaping @Sendable (RuntimeEvent) -> Void
    ) async {
        let reconnectEnabled = configuration.usbcAutoReconnect

        let csvLogger = CsvLogger()
        let obsWriter = ObsOutputWriter()
        var reconnectAttempt = 0

        while !Task.isCancelled {
            onEvent(.usbcStatus(.connecting, nil))

            let transport: any DeviceTransport
            if configuration.useSimulator {
                transport = SimulatedStreamingTransport(sampleRateHz: configuration.sampleRateHz)
            } else {
                let lineIO = POSIXSerialPort(
                    configuration: SerialPortConfiguration(
                        path: configuration.usbcPort,
                        baudRate: 9_600,
                        readTimeoutSeconds: 0.5,
                        writeTimeoutSeconds: 0.5
                    )
                )
                transport = StreamingSerialTransport(lineIO: lineIO)
            }
            let driver = UsbCDeviceDriver(transport: transport)

            do {
                try await driver.connect()
                reconnectAttempt = 0
                let source = configuration.useSimulator ? "simulator" : configuration.usbcPort
                onEvent(.usbcStatus(.connected, "USB-C meter connected (\(source))"))

                while !Task.isCancelled {
                    if let measurement = try await driver.readMeasurement(at: Date()) {
                        do {
                            try await handleUsbCOutputs(
                                measurement,
                                configuration: configuration,
                                csvLogger: csvLogger,
                                obsWriter: obsWriter
                            )
                        } catch {
                            onEvent(.runtimeError("USB-C output write failed: \(error.localizedDescription)"))
                        }

                        onEvent(.usbcMeasurement(measurement))
                    }
                }
            } catch {
                onEvent(.usbcStatus(.error, "USB-C error: \(error.localizedDescription)"))
            }

            await driver.disconnect()

            if Task.isCancelled || !reconnectEnabled {
                break
            }

            reconnectAttempt += 1
            let delay = reconnectDelay(forAttempt: reconnectAttempt)
            onEvent(.usbcStatus(.connecting, "Retrying USB-C meter in \(String(format: "%.1f", delay))s"))
            await sleep(seconds: delay)
        }

        onEvent(.usbcStatus(.disconnected, nil))
    }

    private static func reconnectDelay(forAttempt attempt: Int) -> TimeInterval {
        let initial = 0.5
        let raw = initial * pow(2.0, Double(max(0, attempt - 1)))
        return min(5.0, raw)
    }

    private static func sleep(seconds: TimeInterval) async {
        let clamped = max(0, seconds)
        let nanos = UInt64(clamped * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanos)
    }

    private static func handleMultimeterOutputs(
        _ measurement: DeviceMeasurement,
        configuration: AppConfiguration,
        csvLogger: CsvLogger,
        obsWriter: ObsOutputWriter
    ) async throws {
        let display = MeasurementDisplayFormatter.multimeterPrimary(measurement)

        if configuration.multimeterCsvLoggingEnabled {
            try await csvLogger.logMultimeter(
                to: configuration.multimeterCsvLogFilePath,
                measurement: measurement,
                formattedValue: display
            )
        }

        try await obsWriter.writeMultimeter(
            to: configuration.multimeterOutputFile,
            mode: configuration.multimeterObsOutputMode,
            displayText: display,
            displayUnit: measurement.primaryUnit,
            modeText: MeasurementDisplayFormatter.multimeterModeTitle(measurement),
            label: configuration.multimeterValueLabel,
            customTemplate: configuration.multimeterObsCustomTemplate
        )
    }

    private static func handleUsbCOutputs(
        _ measurement: DeviceMeasurement,
        configuration: AppConfiguration,
        csvLogger: CsvLogger,
        obsWriter: ObsOutputWriter
    ) async throws {
        if configuration.usbcCsvLoggingEnabled {
            try await csvLogger.logUsbC(
                to: configuration.usbcCsvLogFilePath,
                measurement: measurement
            )
        }

        guard
            let voltage = measurement.primaryValue,
            let current = measurement.secondaryValue,
            let power = measurement.powerWatts
        else {
            return
        }

        try await obsWriter.writeUsbC(
            to: configuration.usbcOutputFile,
            mode: configuration.usbcObsOutputMode,
            voltage: voltage,
            current: current,
            power: power,
            label: configuration.usbcValueLabel,
            customTemplate: configuration.usbcObsCustomTemplate
        )
    }
}

enum MeasurementDisplayFormatter {
    static func multimeterPrimary(_ measurement: DeviceMeasurement) -> String {
        if measurement.isOpen {
            return "OPEN"
        }
        if measurement.isShort {
            return "SHORT"
        }
        if measurement.isOverload {
            return "OVERLOAD"
        }
        guard let value = measurement.primaryValue else {
            return "---"
        }
        return String(format: "%.4f", value)
    }

    static func multimeterSecondary(_ measurement: DeviceMeasurement) -> String {
        measurement.primaryUnit
    }

    static func multimeterModeTitle(_ measurement: DeviceMeasurement) -> String {
        switch measurement.mode {
        case .dcVoltage: return "DC Voltage"
        case .acVoltage: return "AC Voltage"
        case .resistance: return "Resistance"
        case .continuity: return "Continuity"
        case .diode: return "Diode"
        case .dcCurrent: return "DC Current"
        case .acCurrent: return "AC Current"
        case .capacitance: return "Capacitance"
        case .frequency: return "Frequency"
        case .period: return "Period"
        case .temperature: return "Temperature"
        case .unknown:
            return measurement.modeString.isEmpty ? "Unknown" : measurement.modeString
        }
    }
}

private extension AppConfiguration {
    var alertConfiguration: MeasurementAlertConfiguration {
        MeasurementAlertConfiguration(
            shortThreshold: shortThreshold,
            dcvHighAlarmEnabled: dcvHighAlarmEnabled,
            dcvHighAlarmValue: dcvHighAlarmValue,
            dcvLowAlarmEnabled: dcvLowAlarmEnabled,
            dcvLowAlarmValue: dcvLowAlarmValue
        )
    }
}

private func alertText(_ alert: MeasurementAlertState) -> String {
    switch alert {
    case .none:
        return "OK"
    case .short:
        return "SHORT"
    case .open:
        return "OPEN"
    case .highAlarm:
        return "HIGH ALARM"
    case .lowAlarm:
        return "LOW ALARM"
    }
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var multimeterStatus: DeviceUIState = .disconnected
    @Published var usbcStatus: DeviceUIState = .disconnected

    @Published var multimeterPrimary: String = "---"
    @Published var multimeterSecondary: String = ""
    @Published var multimeterMode: String = "No Signal"
    @Published var multimeterAlert: String = "OK"

    @Published var usbcVoltage: String = "---"
    @Published var usbcCurrent: String = "---"
    @Published var usbcPower: String = "Power: ---"
    @Published var usbcEnergy: String = "Energy: --- mWh | --- mAh"

    @Published var multimeterSamples: [ChartSample] = []
    @Published var usbcSamples: [ChartSample] = []

    @Published var configuration: AppConfiguration = .init()
    @Published var editableConfiguration: AppConfiguration = .init()
    @Published var availablePorts: [String] = []
    @Published var statusMessage: String = "Ready"
    @Published var isSettingsPresented: Bool = false
    @Published var isRuntimeActive: Bool = false

    private let configurationStore: ConfigurationStore
    private let pcBeepController = PcBeepController()

    private lazy var runtime = ReadOutRuntime { [weak self] event in
        Task { @MainActor [weak self] in
            self?.handleRuntimeEvent(event)
        }
    }

    init() {
        let configURL = Self.resolveConfigURL()
        configurationStore = ConfigurationStore(configFileURL: configURL)
        statusMessage = "Config: \(configURL.path)"

        Task {
            await bootstrap()
        }
    }

    func connectAll() {
        Task {
            await runtime.start(with: configuration)
            await MainActor.run {
                isRuntimeActive = true
                statusMessage = configuration.useSimulator
                    ? "Connecting simulator devices..."
                    : "Connecting devices..."
            }
        }
    }

    func disconnectAll() {
        Task {
            await runtime.stop()
            await MainActor.run {
                isRuntimeActive = false
                statusMessage = "Disconnected"
                multimeterAlert = "OK"
                pcBeepController.setBeeping(false)
            }
        }
    }

    func refreshPorts() {
        var discovered = SerialPortDiscovery.listPorts()
        let simulatedPorts = [SimulatedPort.multimeter, SimulatedPort.usbC]
        for port in simulatedPorts where !discovered.contains(port) {
            discovered.append(port)
        }
        availablePorts = discovered

        if configuration.useSimulator {
            configuration.multimeterPort = SimulatedPort.multimeter
            configuration.usbcPort = SimulatedPort.usbC
        } else {
            if configuration.multimeterPort.isEmpty,
               let firstReal = discovered.first(where: { $0 != SimulatedPort.multimeter && $0 != SimulatedPort.usbC }) {
                configuration.multimeterPort = firstReal
            }
            if configuration.usbcPort.isEmpty,
               let firstReal = discovered.first(where: { $0 != SimulatedPort.multimeter && $0 != SimulatedPort.usbC }) {
                configuration.usbcPort = firstReal
            }
        }
    }

    func openSettings() {
        editableConfiguration = configuration
        isSettingsPresented = true
    }

    func cancelSettings() {
        isSettingsPresented = false
    }

    func saveSettings() {
        let newConfig = normalizedConfiguration(editableConfiguration)
        configuration = newConfig
        isSettingsPresented = false

        Task {
            do {
                try await configurationStore.save(newConfig)
                await MainActor.run {
                    statusMessage = "Settings saved"
                }

                if isRuntimeActive {
                    await runtime.start(with: newConfig)
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Failed to save settings: \(error.localizedDescription)"
                }
            }
        }
    }

    private func bootstrap() async {
        refreshPorts()

        do {
            let loaded = normalizedConfiguration(try await configurationStore.load())
            configuration = loaded
            editableConfiguration = loaded
            statusMessage = "Configuration loaded"
        } catch {
            statusMessage = "Failed to load config: \(error.localizedDescription)"
        }
    }

    private func handleRuntimeEvent(_ event: RuntimeEvent) {
        switch event {
        case .multimeterStatus(let state, let message):
            multimeterStatus = state
            if state == .disconnected || state == .error {
                pcBeepController.setBeeping(false)
            }
            if let message {
                statusMessage = message
            }

        case .usbcStatus(let state, let message):
            usbcStatus = state
            if let message {
                statusMessage = message
            }

        case .runtimeError(let message):
            statusMessage = message

        case .multimeterMeasurement(let measurement):
            multimeterPrimary = MeasurementDisplayFormatter.multimeterPrimary(measurement)
            multimeterSecondary = MeasurementDisplayFormatter.multimeterSecondary(measurement)
            multimeterMode = MeasurementDisplayFormatter.multimeterModeTitle(measurement)
            let alert = MeasurementAlertEvaluator.evaluateMultimeter(
                measurement: measurement,
                configuration: configuration.alertConfiguration
            )
            multimeterAlert = alertText(alert)
            if alert == .highAlarm {
                statusMessage = "DC voltage above high alarm threshold"
            } else if alert == .lowAlarm {
                statusMessage = "DC voltage below low alarm threshold"
            } else if alert == .short {
                statusMessage = "SHORT condition detected"
            }

            let shortBeepActive = configuration.beepOnShortPC && alert == .short
            let voltageAlarmActive = configuration.beepOnAlarm && (alert == .highAlarm || alert == .lowAlarm)
            pcBeepController.setBeeping(shortBeepActive || voltageAlarmActive)

            if let value = measurement.primaryValue {
                multimeterSamples.append(ChartSample(timestamp: measurement.timestamp, value: value))
                trimChartsIfNeeded()
            }

        case .usbcMeasurement(let measurement):
            if let voltage = measurement.primaryValue {
                usbcVoltage = String(format: "%.3f V", voltage)
            } else {
                usbcVoltage = "---"
            }

            if let current = measurement.secondaryValue {
                usbcCurrent = String(format: "%.4f A", current)
            } else {
                usbcCurrent = "---"
            }

            if let power = measurement.powerWatts {
                usbcPower = String(format: "Power: %.3f W", power)
                usbcSamples.append(ChartSample(timestamp: measurement.timestamp, value: power))
                trimChartsIfNeeded()
            } else {
                usbcPower = "Power: ---"
            }

            let energyMWh = measurement.energyMWh.map { String(format: "%.1f", $0) } ?? "---"
            let energyMAh = measurement.energyMAh.map { String(format: "%.1f", $0) } ?? "---"
            usbcEnergy = "Energy: \(energyMWh) mWh | \(energyMAh) mAh"
        }

        refreshRuntimeStateFlag()
    }

    private func refreshRuntimeStateFlag() {
        let activeStates: Set<DeviceUIState> = [.connecting, .connected]
        isRuntimeActive = activeStates.contains(multimeterStatus) || activeStates.contains(usbcStatus)
    }

    private func trimChartsIfNeeded() {
        let maxSamples = max(20, configuration.graphHistorySeconds * max(1, configuration.sampleRateHz))

        if multimeterSamples.count > maxSamples {
            multimeterSamples.removeFirst(multimeterSamples.count - maxSamples)
        }

        if usbcSamples.count > maxSamples {
            usbcSamples.removeFirst(usbcSamples.count - maxSamples)
        }
    }

    private func normalizedConfiguration(_ raw: AppConfiguration) -> AppConfiguration {
        var config = raw

        config.sampleRateHz = max(1, min(50, config.sampleRateHz))
        config.graphHistorySeconds = max(5, min(600, config.graphHistorySeconds))
        config.shortThreshold = max(0.1, config.shortThreshold)

        if config.useSimulator {
            config.multimeterPort = SimulatedPort.multimeter
            config.usbcPort = SimulatedPort.usbC
        } else {
            let realPorts = availablePorts.filter { $0 != SimulatedPort.multimeter && $0 != SimulatedPort.usbC }
            if config.multimeterPort.isEmpty, let first = realPorts.first {
                config.multimeterPort = first
            }
            if config.usbcPort.isEmpty, let first = realPorts.first {
                config.usbcPort = first
            }
        }

        return config
    }

    private static func resolveConfigURL() -> URL {
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
}
