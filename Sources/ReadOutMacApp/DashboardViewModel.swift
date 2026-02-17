import Foundation
import ReadOutCore
import ReadOutPersistence

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

    private let configurationService = DashboardConfigurationService()
    private let configurationStore: ConfigurationStore
    private let pcBeepController = PcBeepController()

    private lazy var runtime = ReadOutRuntime { [weak self] event in
        Task { @MainActor [weak self] in
            self?.handleRuntimeEvent(event)
        }
    }

    init() {
        let configURL = configurationService.resolveConfigURL()
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
        let discovered = configurationService.discoverPorts()
        availablePorts = discovered

        configuration = configurationService.normalized(configuration, availablePorts: discovered)
        editableConfiguration = configurationService.normalized(editableConfiguration, availablePorts: discovered)
    }

    func openSettings() {
        editableConfiguration = configuration
        isSettingsPresented = true
    }

    func cancelSettings() {
        isSettingsPresented = false
    }

    func saveSettings() {
        let newConfig = configurationService.normalized(editableConfiguration, availablePorts: availablePorts)
        let validation = AppConfigurationValidator.validate(newConfig)
        if validation.hasErrors {
            if let firstError = validation.issues.first(where: { $0.severity == .error }) {
                statusMessage = "Cannot save settings: \(firstError.message)"
            } else {
                statusMessage = "Cannot save settings due to invalid configuration."
            }
            return
        }

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
            let loaded = try await configurationStore.load()
            let normalized = configurationService.normalized(loaded, availablePorts: availablePorts)

            configuration = normalized
            editableConfiguration = normalized
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
            handleMultimeterMeasurement(measurement)

        case .usbcMeasurement(let measurement):
            handleUsbCMeasurement(measurement)
        }

        refreshRuntimeStateFlag()
    }

    private func handleMultimeterMeasurement(_ measurement: DeviceMeasurement) {
        multimeterPrimary = MeasurementDisplayFormatter.multimeterPrimary(measurement)
        multimeterSecondary = MeasurementDisplayFormatter.multimeterSecondary(measurement)
        multimeterMode = MeasurementDisplayFormatter.multimeterModeTitle(measurement)

        let alert = DashboardAlertService.evaluate(measurement: measurement, configuration: configuration)
        multimeterAlert = DashboardAlertService.text(for: alert)

        if let alertMessage = DashboardAlertService.statusMessage(for: alert) {
            statusMessage = alertMessage
        }

        pcBeepController.setBeeping(
            DashboardAlertService.shouldBeep(for: alert, configuration: configuration)
        )

        if let value = measurement.primaryValue {
            multimeterSamples.append(ChartSample(timestamp: measurement.timestamp, value: value))
            trimChartsIfNeeded()
        }
    }

    private func handleUsbCMeasurement(_ measurement: DeviceMeasurement) {
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
}
