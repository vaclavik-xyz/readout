import Foundation
import ReadOutCore
import ReadOutIO
import ReadOutPersistence

@MainActor
final class DashboardViewModel: ObservableObject {
    private struct MultimeterPresentationSnapshot {
        let primary: String
        let secondary: String
        let mode: String
        let alertText: String
        let alertState: MeasurementAlertState
    }

    private struct UsbCPresentationSnapshot {
        let voltage: String
        let current: String
        let power: String
        let energy: String
    }

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
    @Published private(set) var displayedMultimeterSamples: [ChartSample] = []
    @Published private(set) var displayedUsbCSamples: [ChartSample] = []
    @Published private(set) var displayedAlarmMarkers: [AlarmTimelineMarker] = []
    @Published private(set) var displayedMultimeterConnectionMarkers: [ConnectionOverlayMarker] = []
    @Published private(set) var displayedUsbCConnectionMarkers: [ConnectionOverlayMarker] = []
    @Published var selectedChartRange: ChartRangePreset = .twoMinutes {
        didSet {
            markChartRefresh(multimeter: true, usbc: true, markers: true, reason: "range_changed")
            processCoalescedUIRefreshTick(force: false)
        }
    }
#if DEBUG
    @Published private(set) var chartPerformanceSummary: String = "Chart pipeline: idle"
#endif

    @Published var configuration: AppConfiguration = .init()
    @Published var editableConfiguration: AppConfiguration = .init()
    @Published var availablePorts: [String] = []
    @Published var statusMessage: String = "Ready"
    @Published var runtimeLogs: [RuntimeLogEntry] = []
    @Published var isSettingsPresented: Bool = false
    @Published var isRuntimeActive: Bool = false
    @Published var isRecoveryInProgress: Bool = false
    @Published var deviceVisibility: DashboardDeviceVisibility = .both
    @Published var theme: DashboardTheme = .system
    @Published var isRuntimeLogPanelVisible: Bool = true
    @Published var isRuntimeLogCaptureEnabled: Bool = true
    @Published var isDashboardBeepEnabled: Bool = true
    @Published var isRenderPaused: Bool = false
    @Published var isFirstRunWizardPresented: Bool = false
    @Published var firstRunConfiguration: AppConfiguration = .init()
    @Published private(set) var firstRunProbeResult: PortProbeResult = .empty
    @Published private(set) var firstRunBlockingIssues: [String] = []
    @Published private(set) var firstRunReason: String = ""

    var canConnectAll: Bool {
        connectBlockingIssues(for: configuration).isEmpty
    }

    var canDismissFirstRunWizard: Bool {
        firstRunReason == "manual_from_settings"
    }

    private let configurationService = DashboardConfigurationService()
    private let configurationStore: ConfigurationStore
    private let runtimeLogStore: RuntimeLogStore
    private let diagnosticsBundleService = DiagnosticsBundleService()
    private let pcBeepController = PcBeepController()
    private var recoveryTask: Task<Void, Never>?
    private var connectionTimeline: [ConnectionTimelineEntry] = []
    private var chartConnectionTimeline: [ConnectionTimelineEntry] = []
    private var healthSnapshots: [RuntimeHealthSnapshot] = []
    private var reconnectCount = 0
    private var runtimeErrorCount = 0
    private var parseErrorCount = 0
    private var outputDropWarningCount = 0
    private var latestMultimeterAlertState: MeasurementAlertState = .none
    private var pendingMultimeterSnapshot: MultimeterPresentationSnapshot?
    private var pendingUsbCSnapshot: UsbCPresentationSnapshot?
    private var pendingRuntimeLogs: [RuntimeLogEntry] = []
    private let uiRefreshCadenceHz = 10
    private var uiRefreshTask: Task<Void, Never>?
    private var multimeterChartDirty = true
    private var usbCChartDirty = true
    private var chartMarkersDirty = true
    private var chartRefreshPending = true
    private var pendingRefreshReasons: Set<String> = ["init"]
    private var appliedUIRefreshTicks = 0
    private var skippedUIRefreshTicks = 0
#if DEBUG
    private var lastMultimeterPipelineMetric = ChartPipelineMetric(
        sourcePointCount: 0,
        filteredPointCount: 0,
        renderedPointCount: 0,
        processingMilliseconds: 0
    )
    private var lastUsbCPipelineMetric = ChartPipelineMetric(
        sourcePointCount: 0,
        filteredPointCount: 0,
        renderedPointCount: 0,
        processingMilliseconds: 0
    )
#endif

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
        syncDashboardStateFromConfiguration(.init())
        configureBeepController()
        setStatusMessage("Config: \(configURL.path)")
        startUIRefreshLoop()
        processCoalescedUIRefreshTick(force: true)

        Task {
            await bootstrap()
        }
    }

    deinit {
        uiRefreshTask?.cancel()
        pcBeepController.setBeeping(false)
    }

    func connectAll() {
        guard !isRecoveryInProgress else {
            setStatusMessage("Recovery in progress. Connect skipped.", level: .warning)
            return
        }
        let blockingIssues = connectBlockingIssues(for: configuration)
        guard blockingIssues.isEmpty else {
            if let first = blockingIssues.first {
                setStatusMessage("Connect blocked: \(first)", level: .warning)
            } else {
                setStatusMessage("Connect blocked by configuration.", level: .warning)
            }
            presentFirstRunWizard(
                reason: "connect_blocked",
                baseConfiguration: configuration
            )
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
                latestMultimeterAlertState = .none
                pendingMultimeterSnapshot = nil
                pendingUsbCSnapshot = nil
                pcBeepController.setBeeping(false)
            }
        }
    }

    func refreshPorts() {
        let discovered = configurationService.discoverPorts()
        availablePorts = discovered

        configuration = configurationService.normalized(configuration, availablePorts: discovered)
        editableConfiguration = configurationService.normalized(editableConfiguration, availablePorts: discovered)
        syncDashboardStateFromConfiguration(configuration)
        configureBeepController()
        if isFirstRunWizardPresented {
            firstRunProbeResult = configurationService.probePorts(discovered)
            firstRunBlockingIssues = connectBlockingIssues(for: firstRunConfiguration)
        }
    }

    func openSettings() {
        editableConfiguration = configuration
        isSettingsPresented = true
    }

    func cancelSettings() {
        isSettingsPresented = false
    }

    func openFirstRunWizardFromSettings() {
        isSettingsPresented = false
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard let self else { return }
            presentFirstRunWizard(
                reason: "manual_from_settings",
                baseConfiguration: self.configuration
            )
        }
    }

    func dismissFirstRunWizard() {
        isFirstRunWizardPresented = false
    }

    func refreshFirstRunPorts() {
        refreshPorts()
        firstRunProbeResult = configurationService.probePorts(availablePorts)
        firstRunBlockingIssues = connectBlockingIssues(for: firstRunConfiguration)
    }

    func applyFirstRunRecommendations() {
        let probe = firstRunProbeResult

        if let multimeterPort = probe.recommendedMultimeterPort {
            firstRunConfiguration.useSimulator = false
            firstRunConfiguration.multimeterPort = multimeterPort
            firstRunConfiguration.multimeterEnabled = true
        }

        if let usbcPort = probe.recommendedUsbCPort {
            firstRunConfiguration.usbcPort = usbcPort
            firstRunConfiguration.usbcEnabled = true
        } else if !firstRunConfiguration.useSimulator {
            firstRunConfiguration.usbcEnabled = false
            firstRunConfiguration.usbcPort = ""
        }

        if probe.recommendedMultimeterPort == nil {
            firstRunConfiguration.useSimulator = true
            firstRunConfiguration.multimeterPort = SimulatedPort.multimeter
            firstRunConfiguration.usbcPort = SimulatedPort.usbC
            firstRunConfiguration.multimeterEnabled = true
            firstRunConfiguration.usbcEnabled = true
        }

        firstRunBlockingIssues = connectBlockingIssues(for: firstRunConfiguration)
    }

    func firstRunModeChanged() {
        if firstRunConfiguration.useSimulator {
            firstRunConfiguration.multimeterPort = SimulatedPort.multimeter
            firstRunConfiguration.usbcPort = SimulatedPort.usbC
            firstRunConfiguration.multimeterEnabled = true
            firstRunConfiguration.usbcEnabled = true
        } else {
            if firstRunConfiguration.multimeterPort == SimulatedPort.multimeter {
                firstRunConfiguration.multimeterPort = firstRunProbeResult.recommendedMultimeterPort ?? ""
            }
            if firstRunConfiguration.usbcPort == SimulatedPort.usbC {
                firstRunConfiguration.usbcPort = firstRunProbeResult.recommendedUsbCPort ?? ""
            }
        }
        firstRunBlockingIssues = connectBlockingIssues(for: firstRunConfiguration)
    }

    func firstRunConfigurationDidChange() {
        firstRunBlockingIssues = connectBlockingIssues(for: firstRunConfiguration)
    }

    func saveFirstRunWizard() {
        let newConfig = configurationService.normalized(firstRunConfiguration, availablePorts: availablePorts)
        let blockingIssues = connectBlockingIssues(for: newConfig)
        guard blockingIssues.isEmpty else {
            firstRunBlockingIssues = blockingIssues
            if let first = blockingIssues.first {
                setStatusMessage("Setup blocked: \(first)", level: .warning)
            }
            return
        }

        let validation = AppConfigurationValidator.validate(newConfig)
        if validation.hasErrors {
            if let firstError = validation.issues.first(where: { $0.severity == .error }) {
                setStatusMessage("Setup validation failed: \(firstError.message)", level: .error)
            } else {
                setStatusMessage("Setup validation failed.", level: .error)
            }
            return
        }

        configuration = newConfig
        editableConfiguration = newConfig
        firstRunConfiguration = newConfig
        syncDashboardStateFromConfiguration(newConfig)
        configureBeepController()
        firstRunBlockingIssues = []
        isFirstRunWizardPresented = false
        trimChartsIfNeeded()
        markChartRefresh(multimeter: true, usbc: true, markers: true, reason: "first_run_saved")
        processCoalescedUIRefreshTick(force: true)

        Task {
            do {
                try await configurationStore.save(newConfig)
                await MainActor.run {
                    setStatusMessage("Setup saved")
                }
                if isRuntimeActive {
                    await runtime.start(with: newConfig)
                }
            } catch {
                await MainActor.run {
                    setStatusMessage("Failed to save setup: \(error.localizedDescription)", level: .error)
                }
            }
        }
    }

    func clearCharts() {
        multimeterSamples.removeAll(keepingCapacity: true)
        usbcSamples.removeAll(keepingCapacity: true)
        alarmMarkers.removeAll(keepingCapacity: true)
        chartConnectionTimeline.removeAll(keepingCapacity: true)
        multimeterChartDirty = true
        usbCChartDirty = true
        chartMarkersDirty = true
        chartRefreshPending = true
        pendingRefreshReasons.insert("charts_cleared")
        processCoalescedUIRefreshTick(force: true)
        setStatusMessage("Charts cleared")
    }

    func setChartRange(_ range: ChartRangePreset) {
        selectedChartRange = range
    }

    func setDeviceVisibility(_ visibility: DashboardDeviceVisibility) {
        guard deviceVisibility != visibility else {
            return
        }

        deviceVisibility = visibility
        configuration.dashboardDeviceVisibility = visibility.configurationValue
        editableConfiguration.dashboardDeviceVisibility = visibility.configurationValue
        markChartRefresh(multimeter: true, usbc: true, markers: true, reason: "visibility_changed")
        processCoalescedUIRefreshTick(force: true)
        persistConfigurationSilently()
    }

    func setTheme(_ theme: DashboardTheme) {
        guard self.theme != theme else {
            return
        }

        self.theme = theme
        configuration.dashboardTheme = theme.configurationValue
        editableConfiguration.dashboardTheme = theme.configurationValue
        persistConfigurationSilently()
    }

    func toggleRuntimeLogPanelVisibility() {
        isRuntimeLogPanelVisible.toggle()
        configuration.runtimeLogPanelVisible = isRuntimeLogPanelVisible
        editableConfiguration.runtimeLogPanelVisible = isRuntimeLogPanelVisible
        persistConfigurationSilently()
    }

    func toggleDashboardBeep() {
        isDashboardBeepEnabled.toggle()
        configuration.dashboardBeepMasterEnabled = isDashboardBeepEnabled
        editableConfiguration.dashboardBeepMasterEnabled = isDashboardBeepEnabled
        updatePcBeep(for: latestMultimeterAlertState)
        persistConfigurationSilently()
    }

    func toggleRenderPause() {
        isRenderPaused.toggle()
        if isRenderPaused {
            setStatusMessage("UI rendering paused")
            return
        }

        setStatusMessage("UI rendering resumed")
        processCoalescedUIRefreshTick(force: true)
    }

    func resetVisualState() {
        multimeterAlert = "OK"
        multimeterAlertState = .none
        latestMultimeterAlertState = .none
        pendingMultimeterSnapshot = nil
        updatePcBeep(for: .none)
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
        pendingRuntimeLogs.removeAll(keepingCapacity: true)
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
        editableConfiguration = newConfig
        syncDashboardStateFromConfiguration(newConfig)
        configureBeepController()
        isSettingsPresented = false
        trimChartsIfNeeded()
        markChartRefresh(multimeter: true, usbc: true, markers: true, reason: "settings_saved")
        processCoalescedUIRefreshTick(force: true)

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

        let hasPersistedConfiguration = await configurationStore.hasPersistedConfiguration()
        if !hasPersistedConfiguration {
            let initial = configurationService.initialWizardConfiguration(availablePorts: availablePorts)
            configuration = initial
            editableConfiguration = initial
            syncDashboardStateFromConfiguration(initial)
            configureBeepController()
            presentFirstRunWizard(reason: "missing_configuration", baseConfiguration: initial)
            setStatusMessage("Welcome. Complete setup before connecting.", level: .warning)
            appendHealthSnapshot(reason: "bootstrap_first_run")
            markChartRefresh(multimeter: true, usbc: true, markers: true, reason: "bootstrap_first_run")
            processCoalescedUIRefreshTick(force: true)
            return
        }

        do {
            let loaded = try await configurationStore.load()
            let normalized = configurationService.normalized(loaded, availablePorts: availablePorts)

            configuration = normalized
            editableConfiguration = normalized
            syncDashboardStateFromConfiguration(normalized)
            configureBeepController()
            let validation = AppConfigurationValidator.validate(normalized)
            let blockingIssues = connectBlockingIssues(for: normalized)
            if blockingIssues.isEmpty && !validation.hasErrors {
                setStatusMessage("Configuration loaded")
            } else {
                setStatusMessage("Configuration requires setup fixes.", level: .warning)
                presentFirstRunWizard(reason: "invalid_configuration", baseConfiguration: normalized)
            }
            appendHealthSnapshot(reason: "bootstrap_loaded")
            markChartRefresh(multimeter: true, usbc: true, markers: true, reason: "bootstrap_loaded")
            processCoalescedUIRefreshTick(force: true)
        } catch {
            let fallback = configurationService.initialWizardConfiguration(availablePorts: availablePorts)
            configuration = fallback
            editableConfiguration = fallback
            syncDashboardStateFromConfiguration(fallback)
            configureBeepController()
            presentFirstRunWizard(reason: "load_failed", baseConfiguration: fallback)
            setStatusMessage("Failed to load config. Setup wizard opened.", level: .error)
            appendHealthSnapshot(reason: "bootstrap_load_failed")
            markChartRefresh(multimeter: true, usbc: true, markers: true, reason: "bootstrap_load_failed")
            processCoalescedUIRefreshTick(force: true)
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
        let previousAlert = latestMultimeterAlertState
        let primary = MeasurementDisplayFormatter.multimeterPrimary(measurement)
        let secondary = MeasurementDisplayFormatter.multimeterSecondary(measurement)
        let mode = MeasurementDisplayFormatter.multimeterModeTitle(measurement)

        let alert = DashboardAlertService.evaluate(measurement: measurement, configuration: configuration)
        latestMultimeterAlertState = alert
        pendingMultimeterSnapshot = MultimeterPresentationSnapshot(
            primary: primary,
            secondary: secondary,
            mode: mode,
            alertText: DashboardAlertService.text(for: alert),
            alertState: alert
        )
        appendAlarmMarkerIfNeeded(
            previousAlert: previousAlert,
            currentAlert: alert,
            timestamp: measurement.timestamp
        )

        if let alertMessage = DashboardAlertService.statusMessage(for: alert) {
            setStatusMessage(alertMessage, level: .warning)
        }

        updatePcBeep(for: alert)

        if let value = measurement.primaryValue {
            multimeterSamples.append(ChartSample(timestamp: measurement.timestamp, value: value))
            trimChartsIfNeeded()
        }

        markChartRefresh(multimeter: true, markers: true, reason: "multimeter_measurement")
    }

    private func handleUsbCMeasurement(_ measurement: DeviceMeasurement) {
        let voltageText: String
        if let voltage = measurement.primaryValue {
            voltageText = String(format: "%.3f V", voltage)
        } else {
            voltageText = "---"
        }

        let currentText: String
        if let current = measurement.secondaryValue {
            currentText = String(format: "%.4f A", current)
        } else {
            currentText = "---"
        }

        let powerText: String
        if let power = measurement.powerWatts {
            powerText = String(format: "Power: %.3f W", power)
            usbcSamples.append(ChartSample(timestamp: measurement.timestamp, value: power))
            trimChartsIfNeeded()
        } else {
            powerText = "Power: ---"
        }

        let energyMWh = measurement.energyMWh.map { String(format: "%.1f", $0) } ?? "---"
        let energyMAh = measurement.energyMAh.map { String(format: "%.1f", $0) } ?? "---"
        pendingUsbCSnapshot = UsbCPresentationSnapshot(
            voltage: voltageText,
            current: currentText,
            power: powerText,
            energy: "Energy: \(energyMWh) mWh | \(energyMAh) mAh"
        )
        markChartRefresh(usbc: true, reason: "usbc_measurement")
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
        latestMultimeterAlertState = .none
        pendingMultimeterSnapshot = nil
        pendingUsbCSnapshot = nil
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
        if !shouldCaptureRuntimeLog(level: level) {
            return
        }

        if let last = lastRuntimeLogEntry(), last.message == message, last.level == level {
            return
        }

        let entry = RuntimeLogEntry(
            timestamp: Date(),
            level: level,
            message: message
        )

        if isRenderPaused {
            pendingRuntimeLogs.append(entry)
            if pendingRuntimeLogs.count > 300 {
                pendingRuntimeLogs.removeFirst(pendingRuntimeLogs.count - 300)
            }
        } else {
            appendRuntimeLogToUI(entry)
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

    private func syncDashboardStateFromConfiguration(_ config: AppConfiguration) {
        deviceVisibility = DashboardDeviceVisibility(configurationValue: config.dashboardDeviceVisibility)
        theme = DashboardTheme(configurationValue: config.dashboardTheme)
        isRuntimeLogPanelVisible = config.runtimeLogPanelVisible
        isRuntimeLogCaptureEnabled = config.runtimeLogCaptureEnabled
        isDashboardBeepEnabled = config.dashboardBeepMasterEnabled
    }

    private func configureBeepController() {
        let preset = MacAlertSoundPreset(configurationValue: configuration.pcBeepSoundPreset)
        pcBeepController.configure(soundPreset: preset, volume: configuration.pcBeepVolume)
        updatePcBeep(for: latestMultimeterAlertState)
    }

    private func updatePcBeep(for alert: MeasurementAlertState) {
        let shouldBeep = isDashboardBeepEnabled
            && DashboardAlertService.shouldBeep(for: alert, configuration: configuration)
        pcBeepController.setBeeping(shouldBeep)
    }

    private func persistConfigurationSilently() {
        let config = configuration
        Task { [configurationStore] in
            try? await configurationStore.save(config)
        }
    }

    private func appendRuntimeLogToUI(_ entry: RuntimeLogEntry) {
        runtimeLogs.append(entry)
        if runtimeLogs.count > 200 {
            runtimeLogs.removeFirst(runtimeLogs.count - 200)
        }
    }

    private func flushPendingRuntimeLogsToUI() {
        guard !pendingRuntimeLogs.isEmpty else {
            return
        }

        for entry in pendingRuntimeLogs {
            appendRuntimeLogToUI(entry)
        }
        pendingRuntimeLogs.removeAll(keepingCapacity: true)
    }

    private func shouldCaptureRuntimeLog(level: RuntimeLogLevel) -> Bool {
        if level == .info, !isRuntimeLogCaptureEnabled {
            return false
        }
        return true
    }

    private func lastRuntimeLogEntry() -> RuntimeLogEntry? {
        pendingRuntimeLogs.last ?? runtimeLogs.last
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

    private func connectBlockingIssues(for configuration: AppConfiguration) -> [String] {
        configurationService.connectBlockingIssues(
            configuration: configuration,
            availablePorts: availablePorts
        )
    }

    private func presentFirstRunWizard(reason: String, baseConfiguration: AppConfiguration?) {
        firstRunReason = reason
        firstRunProbeResult = configurationService.probePorts(availablePorts)

        var draft = baseConfiguration
            ?? configurationService.initialWizardConfiguration(availablePorts: availablePorts)

        if !draft.useSimulator {
            if draft.multimeterPort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.multimeterPort = firstRunProbeResult.recommendedMultimeterPort ?? ""
            }
            if draft.usbcPort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.usbcPort = firstRunProbeResult.recommendedUsbCPort ?? ""
            }
        }

        firstRunConfiguration = configurationService.normalized(draft, availablePorts: availablePorts)
        firstRunBlockingIssues = connectBlockingIssues(for: firstRunConfiguration)
        isFirstRunWizardPresented = true
    }

    private func startUIRefreshLoop() {
        guard uiRefreshTask == nil else {
            return
        }

        let intervalNanos = UInt64(1_000_000_000 / max(1, uiRefreshCadenceHz))
        uiRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: intervalNanos)
                await MainActor.run {
                    self?.processCoalescedUIRefreshTick(force: false)
                }
            }
        }
    }

    private func markChartRefresh(
        multimeter: Bool = false,
        usbc: Bool = false,
        markers: Bool = false,
        reason: String
    ) {
        multimeterChartDirty = multimeterChartDirty || multimeter
        usbCChartDirty = usbCChartDirty || usbc
        chartMarkersDirty = chartMarkersDirty || markers
        chartRefreshPending = true
        pendingRefreshReasons.insert(reason)
    }

    private func processCoalescedUIRefreshTick(force: Bool) {
        let hasPendingPresentation = pendingMultimeterSnapshot != nil || pendingUsbCSnapshot != nil || !pendingRuntimeLogs.isEmpty
        let hasPendingCharts = chartRefreshPending
        let hasWork = force || hasPendingPresentation || hasPendingCharts
        guard hasWork else {
            return
        }

        guard !isRenderPaused || force else {
            skippedUIRefreshTicks += 1
            return
        }

        appliedUIRefreshTicks += 1
        applyPendingPresentationSnapshots()
        flushPendingRuntimeLogsToUI()

        if hasPendingCharts || force {
            let reason = pendingRefreshReasons.sorted().joined(separator: ",")
            refreshDisplayedCharts(reason: reason.isEmpty ? "coalesced" : reason, force: force)
            pendingRefreshReasons.removeAll(keepingCapacity: true)
            chartRefreshPending = false
            multimeterChartDirty = false
            usbCChartDirty = false
            chartMarkersDirty = false
        }
    }

    private func applyPendingPresentationSnapshots() {
        if let snapshot = pendingMultimeterSnapshot {
            multimeterPrimary = snapshot.primary
            multimeterSecondary = snapshot.secondary
            multimeterMode = snapshot.mode
            multimeterAlert = snapshot.alertText
            multimeterAlertState = snapshot.alertState
            pendingMultimeterSnapshot = nil
        }

        if let snapshot = pendingUsbCSnapshot {
            usbcVoltage = snapshot.voltage
            usbcCurrent = snapshot.current
            usbcPower = snapshot.power
            usbcEnergy = snapshot.energy
            pendingUsbCSnapshot = nil
        }
    }

    private func refreshDisplayedCharts(reason: String, force: Bool) {
        let now = Date()
        let showMultimeter = deviceVisibility != .usbc
        let showUsbC = deviceVisibility != .multimeter

        if force || multimeterChartDirty {
            if showMultimeter {
                let multimeterPipeline = ChartPipelineService.process(
                    samples: multimeterSamples,
                    range: selectedChartRange,
                    now: now,
                    maxPoints: 280
                )
                displayedMultimeterSamples = multimeterPipeline.samples
#if DEBUG
                lastMultimeterPipelineMetric = multimeterPipeline.metric
#endif
            } else {
                displayedMultimeterSamples = []
#if DEBUG
                lastMultimeterPipelineMetric = ChartPipelineMetric(
                    sourcePointCount: multimeterSamples.count,
                    filteredPointCount: 0,
                    renderedPointCount: 0,
                    processingMilliseconds: 0
                )
#endif
            }
        }

        if force || usbCChartDirty {
            if showUsbC {
                let usbCPipeline = ChartPipelineService.process(
                    samples: usbcSamples,
                    range: selectedChartRange,
                    now: now,
                    maxPoints: 280
                )
                displayedUsbCSamples = usbCPipeline.samples
#if DEBUG
                lastUsbCPipelineMetric = usbCPipeline.metric
#endif
            } else {
                displayedUsbCSamples = []
#if DEBUG
                lastUsbCPipelineMetric = ChartPipelineMetric(
                    sourcePointCount: usbcSamples.count,
                    filteredPointCount: 0,
                    renderedPointCount: 0,
                    processingMilliseconds: 0
                )
#endif
            }
        }

        if force || chartMarkersDirty {
            displayedAlarmMarkers = showMultimeter ? alarmMarkersForDisplay(now: now) : []
            displayedMultimeterConnectionMarkers = showMultimeter
                ? connectionMarkersForDisplay(device: "multimeter", now: now)
                : []
            displayedUsbCConnectionMarkers = showUsbC
                ? connectionMarkersForDisplay(device: "usbc", now: now)
                : []
        }

#if DEBUG
        chartPerformanceSummary = String(
            format: "Pipeline %@ | MM %d→%d→%d (%.2fms) | USB-C %d→%d→%d (%.2fms) | UI ticks %d applied / %d skipped",
            reason,
            lastMultimeterPipelineMetric.sourcePointCount,
            lastMultimeterPipelineMetric.filteredPointCount,
            lastMultimeterPipelineMetric.renderedPointCount,
            lastMultimeterPipelineMetric.processingMilliseconds,
            lastUsbCPipelineMetric.sourcePointCount,
            lastUsbCPipelineMetric.filteredPointCount,
            lastUsbCPipelineMetric.renderedPointCount,
            lastUsbCPipelineMetric.processingMilliseconds,
            appliedUIRefreshTicks,
            skippedUIRefreshTicks
        )
#endif
    }

    private func alarmMarkersForDisplay(now: Date) -> [AlarmTimelineMarker] {
        guard let duration = selectedChartRange.durationSeconds else {
            return alarmMarkers
        }
        let threshold = now.addingTimeInterval(-duration)
        return alarmMarkers.filter { $0.timestamp >= threshold }
    }

    private func connectionMarkersForDisplay(device: String, now: Date) -> [ConnectionOverlayMarker] {
        let baseEntries = chartConnectionTimeline.filter { $0.device == device }

        let visibleEntries: [ConnectionTimelineEntry]
        if let duration = selectedChartRange.durationSeconds {
            let threshold = now.addingTimeInterval(-duration)
            visibleEntries = baseEntries.filter { $0.timestamp >= threshold }
        } else {
            visibleEntries = baseEntries
        }

        return visibleEntries.compactMap { entry in
            guard let state = connectionOverlayState(for: entry) else {
                return nil
            }

            return ConnectionOverlayMarker(
                timestamp: entry.timestamp,
                state: state,
                message: entry.message ?? state.rawValue
            )
        }
    }

    private func connectionOverlayState(for entry: ConnectionTimelineEntry) -> ConnectionOverlayState? {
        let lowered = entry.message?.lowercased() ?? ""
        if lowered.contains("retrying") {
            return .reconnecting
        }
        if entry.state == .error {
            return .error
        }
        if entry.state == .connected {
            return .restored
        }
        return nil
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
        let exportedLogs = Array((runtimeLogs + pendingRuntimeLogs).suffix(500))
        return DiagnosticsBundleInput(
            exportedAt: Date(),
            configuration: configuration,
            runtimeLogs: exportedLogs,
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

        let entry = ConnectionTimelineEntry(
            timestamp: Date(),
            device: device,
            state: state,
            message: message
        )

        connectionTimeline.append(entry)
        if connectionTimeline.count > 500 {
            connectionTimeline.removeFirst(connectionTimeline.count - 500)
        }

        chartConnectionTimeline.append(entry)
        if chartConnectionTimeline.count > 240 {
            chartConnectionTimeline.removeFirst(chartConnectionTimeline.count - 240)
        }

        markChartRefresh(markers: true, reason: "\(device)_status")
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
                runtimeLogCount: runtimeLogs.count + pendingRuntimeLogs.count,
                statusMessage: statusMessage
            )
        )
        if healthSnapshots.count > 500 {
            healthSnapshots.removeFirst(healthSnapshots.count - 500)
        }
    }
}
