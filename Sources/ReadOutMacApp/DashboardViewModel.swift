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
    @Published var multimeterAlertState: MeasurementAlertState = .none

    @Published var usbcVoltage: String = "---"
    @Published var usbcCurrent: String = "---"
    @Published var usbcPower: String = "Power: ---"
    @Published var usbcEnergy: String = "Energy: --- mWh | --- mAh"

    @Published var multimeterSamples: [ChartSample] = []
    @Published var usbcSamples: [ChartSample] = []
    @Published var alarmMarkers: [AlarmTimelineMarker] = []
    @Published var selectedChartRange: ChartRangePreset = .twoMinutes

    @Published var configuration: AppConfiguration = .init()
    @Published var editableConfiguration: AppConfiguration = .init()
    @Published var availablePorts: [String] = []
    @Published var statusMessage: String = "Ready"
    @Published var runtimeLogs: [RuntimeLogEntry] = []
    @Published var isSettingsPresented: Bool = false
    @Published var isRuntimeActive: Bool = false
    @Published var isRecoveryInProgress: Bool = false

    private let configurationService = DashboardConfigurationService()
    private let configurationStore: ConfigurationStore
    private let runtimeLogStore: RuntimeLogStore
    private let diagnosticsBundleService = DiagnosticsBundleService()
    private let pcBeepController = PcBeepController()
    private var recoveryTask: Task<Void, Never>?
    private var connectionTimeline: [ConnectionTimelineEntry] = []
    private var healthSnapshots: [RuntimeHealthSnapshot] = []
    private var reconnectCount = 0
    private var runtimeErrorCount = 0
    private var parseErrorCount = 0
    private var outputDropWarningCount = 0

    private lazy var runtime = ReadOutRuntime { [weak self] event in
        Task { @MainActor [weak self] in
            self?.handleRuntimeEvent(event)
        }
    }

    init() {
        let configURL = configurationService.resolveConfigURL()
        let runtimeLogDirectoryURL = configurationService.resolveRuntimeLogDirectoryURL()
        configurationStore = ConfigurationStore(configFileURL: configURL)
        runtimeLogStore = RuntimeLogStore(logDirectoryURL: runtimeLogDirectoryURL)
        setStatusMessage("Config: \(configURL.path)")

        Task {
            await bootstrap()
        }
    }

    func connectAll() {
        guard !isRecoveryInProgress else {
            setStatusMessage("Recovery in progress. Connect skipped.", level: .warning)
            return
        }

        Task {
            await runtime.start(with: configuration)
            await MainActor.run {
                isRuntimeActive = true
                setStatusMessage(configuration.useSimulator
                    ? "Connecting simulator devices..."
                    : "Connecting devices...")
            }
        }
    }

    func disconnectAll() {
        guard !isRecoveryInProgress else {
            setStatusMessage("Recovery in progress. Disconnect skipped.", level: .warning)
            return
        }

        Task {
            await runtime.stop()
            await MainActor.run {
                isRuntimeActive = false
                setStatusMessage("Disconnected")
                multimeterAlert = "OK"
                multimeterAlertState = .none
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

    func clearCharts() {
        multimeterSamples.removeAll(keepingCapacity: true)
        usbcSamples.removeAll(keepingCapacity: true)
        alarmMarkers.removeAll(keepingCapacity: true)
        setStatusMessage("Charts cleared")
    }

    func setChartRange(_ range: ChartRangePreset) {
        selectedChartRange = range
    }

    func resetVisualState() {
        multimeterAlert = "OK"
        multimeterAlertState = .none
        setStatusMessage("Visual state reset")
    }

    func restartRuntime() {
        guard recoveryTask == nil else {
            setStatusMessage("Recovery already in progress.", level: .warning)
            return
        }

        recoveryTask = Task { @MainActor [weak self] in
            await self?.runRecoverySequence()
        }
    }

    func clearRuntimeLogs() {
        runtimeLogs.removeAll(keepingCapacity: true)
        statusMessage = "Runtime logs cleared"
        appendRuntimeLog("Runtime logs cleared", level: .info, persist: false)

        Task { [runtimeLogStore] in
            do {
                try await runtimeLogStore.clearAll()
            } catch {
                await MainActor.run {
                    reportRuntimeLogPersistenceIssue("Failed to clear persisted logs: \(error.localizedDescription)")
                }
            }
        }
    }

    func exportRuntimeLogs(to destinationURL: URL) {
        let metadataLines = runtimeLogExportMetadata()

        Task { [runtimeLogStore] in
            do {
                try await runtimeLogStore.exportAll(to: destinationURL, metadataLines: metadataLines)
                await MainActor.run {
                    setStatusMessage("Runtime logs exported to \(destinationURL.path)")
                }
            } catch {
                await MainActor.run {
                    setStatusMessage("Failed to export runtime logs: \(error.localizedDescription)", level: .error)
                }
            }
        }
    }

    func exportDiagnosticsBundle(to destinationURL: URL) {
        let input = makeDiagnosticsBundleInput()

        Task { [diagnosticsBundleService] in
            do {
                try diagnosticsBundleService.exportBundle(to: destinationURL, input: input)
                await MainActor.run {
                    setStatusMessage("Diagnostics bundle exported to \(destinationURL.path)")
                }
            } catch {
                await MainActor.run {
                    setStatusMessage("Failed to export diagnostics bundle: \(error.localizedDescription)", level: .error)
                }
            }
        }
    }

    func saveSettings() {
        let newConfig = configurationService.normalized(editableConfiguration, availablePorts: availablePorts)
        let validation = AppConfigurationValidator.validate(newConfig)
        if validation.hasErrors {
            if let firstError = validation.issues.first(where: { $0.severity == .error }) {
                setStatusMessage("Cannot save settings: \(firstError.message)", level: .error)
            } else {
                setStatusMessage("Cannot save settings due to invalid configuration.", level: .error)
            }
            return
        }

        configuration = newConfig
        isSettingsPresented = false

        Task {
            do {
                try await configurationStore.save(newConfig)
                await MainActor.run {
                    setStatusMessage("Settings saved")
                }

                if isRuntimeActive {
                    await runtime.start(with: newConfig)
                }
            } catch {
                await MainActor.run {
                    setStatusMessage("Failed to save settings: \(error.localizedDescription)", level: .error)
                }
            }
        }
    }

    private func bootstrap() async {
        await restorePersistedRuntimeLogs()
        refreshPorts()

        do {
            let loaded = try await configurationStore.load()
            let normalized = configurationService.normalized(loaded, availablePorts: availablePorts)

            configuration = normalized
            editableConfiguration = normalized
            setStatusMessage("Configuration loaded")
            appendHealthSnapshot(reason: "bootstrap_loaded")
        } catch {
            setStatusMessage("Failed to load config: \(error.localizedDescription)", level: .error)
            appendHealthSnapshot(reason: "bootstrap_load_failed")
        }
    }

    private func handleRuntimeEvent(_ event: RuntimeEvent) {
        switch event {
        case .multimeterStatus(let state, let message):
            multimeterStatus = state
            recordConnectionTimeline(device: "multimeter", state: state, message: message)
            if state == .disconnected || state == .error {
                pcBeepController.setBeeping(false)
            }
            if let message {
                let level: RuntimeLogLevel = state == .error ? .error : .info
                setStatusMessage(message, level: level)
            }

        case .usbcStatus(let state, let message):
            usbcStatus = state
            recordConnectionTimeline(device: "usbc", state: state, message: message)
            if let message {
                let level: RuntimeLogLevel = state == .error ? .error : .info
                setStatusMessage(message, level: level)
            }

        case .runtimeError(let message):
            runtimeErrorCount += 1
            if message.lowercased().contains("parse") {
                parseErrorCount += 1
            }
            setStatusMessage(message, level: .error)
            appendHealthSnapshot(reason: "runtime_error")

        case .runtimeLog(let level, let message):
            recordRuntimeLogHealth(level: level, message: message)
            if level == .warning || level == .error {
                statusMessage = message
            }
            appendRuntimeLog(message, level: level, persist: true)
            appendHealthSnapshot(reason: "runtime_log")

        case .multimeterMeasurement(let measurement):
            handleMultimeterMeasurement(measurement)

        case .usbcMeasurement(let measurement):
            handleUsbCMeasurement(measurement)
        }

        refreshRuntimeStateFlag()
    }

    private func handleMultimeterMeasurement(_ measurement: DeviceMeasurement) {
        let previousAlert = multimeterAlertState
        multimeterPrimary = MeasurementDisplayFormatter.multimeterPrimary(measurement)
        multimeterSecondary = MeasurementDisplayFormatter.multimeterSecondary(measurement)
        multimeterMode = MeasurementDisplayFormatter.multimeterModeTitle(measurement)

        let alert = DashboardAlertService.evaluate(measurement: measurement, configuration: configuration)
        multimeterAlert = DashboardAlertService.text(for: alert)
        multimeterAlertState = alert
        appendAlarmMarkerIfNeeded(
            previousAlert: previousAlert,
            currentAlert: alert,
            timestamp: measurement.timestamp
        )

        if let alertMessage = DashboardAlertService.statusMessage(for: alert) {
            setStatusMessage(alertMessage, level: .warning)
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

    var displayedMultimeterSamples: [ChartSample] {
        downsampleForDisplay(multimeterSamples)
    }

    var displayedUsbCSamples: [ChartSample] {
        downsampleForDisplay(usbcSamples)
    }

    var displayedAlarmMarkers: [AlarmTimelineMarker] {
        guard let duration = selectedChartRange.durationSeconds else {
            return alarmMarkers
        }
        let threshold = Date().addingTimeInterval(-duration)
        return alarmMarkers.filter { $0.timestamp >= threshold }
    }

    private func runRecoverySequence() async {
        defer {
            isRecoveryInProgress = false
            recoveryTask = nil
        }

        let configSnapshot = configuration

        isRecoveryInProgress = true
        setStatusMessage("Recovery: stopping runtime...", level: .warning)
        pcBeepController.setBeeping(false)

        await runtime.stop()

        multimeterAlert = "OK"
        multimeterAlertState = .none
        setStatusMessage("Recovery: restarting runtime...", level: .warning)

        await runtime.start(with: configSnapshot)
        isRuntimeActive = true
        setStatusMessage("Recovery: reconnecting devices...", level: .warning)

        let ready = await waitForRecoveryReady(timeoutSeconds: 8.0)
        if ready {
            setStatusMessage("Recovery: ready")
        } else {
            setStatusMessage("Recovery: timeout waiting for stable state.", level: .warning)
        }
    }

    private func waitForRecoveryReady(timeoutSeconds: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(max(0, timeoutSeconds))

        while Date() < deadline {
            let multimeterReady = !configuration.multimeterEnabled || multimeterStatus != .connecting
            let usbCReady = !configuration.usbcEnabled || usbcStatus != .connecting
            if multimeterReady && usbCReady {
                return true
            }

            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        return false
    }

    private func setStatusMessage(_ message: String, level: RuntimeLogLevel = .info) {
        statusMessage = message
        appendRuntimeLog(message, level: level, persist: true)
    }

    private func appendRuntimeLog(_ message: String, level: RuntimeLogLevel, persist: Bool) {
        if let last = runtimeLogs.last, last.message == message, last.level == level {
            return
        }

        let entry = RuntimeLogEntry(
            timestamp: Date(),
            level: level,
            message: message
        )
        runtimeLogs.append(entry)

        if runtimeLogs.count > 200 {
            runtimeLogs.removeFirst(runtimeLogs.count - 200)
        }

        if persist {
            persistRuntimeLog(entry)
        }
    }

    private func restorePersistedRuntimeLogs() async {
        do {
            let restoredLogs = try await runtimeLogStore.loadRecent(limit: 200)
            guard !restoredLogs.isEmpty else {
                return
            }

            runtimeLogs = Array((restoredLogs + runtimeLogs).suffix(200))
        } catch {
            reportRuntimeLogPersistenceIssue("Failed to load runtime logs: \(error.localizedDescription)")
        }
    }

    private func persistRuntimeLog(_ entry: RuntimeLogEntry) {
        Task { [runtimeLogStore] in
            do {
                try await runtimeLogStore.append(entry)
            } catch {
                await MainActor.run {
                    reportRuntimeLogPersistenceIssue("Failed to persist runtime log: \(error.localizedDescription)")
                }
            }
        }
    }

    private func reportRuntimeLogPersistenceIssue(_ message: String) {
        statusMessage = message
        appendRuntimeLog(message, level: .warning, persist: false)
    }

    private func runtimeLogExportMetadata() -> [String] {
        let formatter = ISO8601DateFormatter()
        let multimeterPort = configuration.multimeterPort.isEmpty ? "-" : configuration.multimeterPort
        let usbcPort = configuration.usbcPort.isEmpty ? "-" : configuration.usbcPort
        return [
            "Generated: \(formatter.string(from: Date()))",
            "Mode: \(configuration.useSimulator ? "Simulator" : "Hardware")",
            "Multimeter Port: \(multimeterPort)",
            "USB-C Port: \(usbcPort)"
        ]
    }

    private func downsampleForDisplay(_ samples: [ChartSample]) -> [ChartSample] {
        let filtered = ChartSamplingService.filtered(
            samples: samples,
            range: selectedChartRange,
            now: Date()
        )
        return ChartSamplingService.downsampleMinMax(
            samples: filtered,
            maxPoints: 280
        )
    }

    private func appendAlarmMarkerIfNeeded(
        previousAlert: MeasurementAlertState,
        currentAlert: MeasurementAlertState,
        timestamp: Date
    ) {
        guard previousAlert != currentAlert else {
            return
        }
        guard currentAlert != .none else {
            return
        }

        alarmMarkers.append(
            AlarmTimelineMarker(
                timestamp: timestamp,
                state: currentAlert,
                message: DashboardAlertService.text(for: currentAlert)
            )
        )
        if alarmMarkers.count > 120 {
            alarmMarkers.removeFirst(alarmMarkers.count - 120)
        }
    }

    private func makeDiagnosticsBundleInput() -> DiagnosticsBundleInput {
        DiagnosticsBundleInput(
            exportedAt: Date(),
            configuration: configuration,
            runtimeLogs: Array(runtimeLogs.suffix(500)),
            healthSnapshots: Array(healthSnapshots.suffix(500)),
            connectionTimeline: Array(connectionTimeline.suffix(500)),
            multimeterStatus: multimeterStatus,
            usbcStatus: usbcStatus,
            isRuntimeActive: isRuntimeActive,
            statusMessage: statusMessage
        )
    }

    private func recordConnectionTimeline(device: String, state: DeviceUIState, message: String?) {
        if let message, message.contains("Retrying") {
            reconnectCount += 1
        }

        connectionTimeline.append(
            ConnectionTimelineEntry(
                timestamp: Date(),
                device: device,
                state: state,
                message: message
            )
        )
        if connectionTimeline.count > 500 {
            connectionTimeline.removeFirst(connectionTimeline.count - 500)
        }

        appendHealthSnapshot(reason: "\(device)_status")
    }

    private func recordRuntimeLogHealth(level: RuntimeLogLevel, message: String) {
        let lowered = message.lowercased()
        if lowered.contains("output queue"), lowered.contains("dropped"), level == .warning {
            outputDropWarningCount += 1
        }
        if lowered.contains("parse"), (level == .warning || level == .error) {
            parseErrorCount += 1
        }
    }

    private func appendHealthSnapshot(reason: String) {
        healthSnapshots.append(
            RuntimeHealthSnapshot(
                timestamp: Date(),
                reason: reason,
                isRuntimeActive: isRuntimeActive,
                multimeterStatus: multimeterStatus,
                usbcStatus: usbcStatus,
                reconnectCount: reconnectCount,
                runtimeErrorCount: runtimeErrorCount,
                parseErrorCount: parseErrorCount,
                outputDropWarningCount: outputDropWarningCount,
                runtimeLogCount: runtimeLogs.count,
                statusMessage: statusMessage
            )
        )
        if healthSnapshots.count > 500 {
            healthSnapshots.removeFirst(healthSnapshots.count - 500)
        }
    }
}
