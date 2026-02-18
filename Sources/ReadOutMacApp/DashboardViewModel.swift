import Combine
import Foundation
import ReadOutCore
import ReadOutIO
import ReadOutPersistence

@MainActor
final class DashboardViewModel: ObservableObject {
    private enum UIRefreshMode: String {
        case normal = "normal"
        case highLoad = "high-load"
    }

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

    var multimeterSamples: [ChartSample] {
        get { chartDataService.multimeterSamples }
        set { chartDataService.multimeterSamples = newValue }
    }
    var usbcSamples: [ChartSample] {
        get { chartDataService.usbcSamples }
        set { chartDataService.usbcSamples = newValue }
    }
    var alarmMarkers: [AlarmTimelineMarker] {
        get { chartDataService.alarmMarkers }
        set { chartDataService.alarmMarkers = newValue }
    }
    var displayedMultimeterSamples: [ChartSample] { chartDataService.displayedMultimeterSamples }
    var displayedUsbCSamples: [ChartSample] { chartDataService.displayedUsbCSamples }
    var displayedAlarmMarkers: [AlarmTimelineMarker] { chartDataService.displayedAlarmMarkers }
    var displayedMultimeterConnectionMarkers: [ConnectionOverlayMarker] { chartDataService.displayedMultimeterConnectionMarkers }
    var displayedUsbCConnectionMarkers: [ConnectionOverlayMarker] { chartDataService.displayedUsbCConnectionMarkers }
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
    @Published private(set) var uiRefreshRuntimeSummary: String = "UI normal 10Hz"
    @Published private(set) var uiRefreshActualHzText: String = "--.-Hz"
    var runtimeHealthBadges: [RuntimeHealthBadge] { runtimeHealthService.runtimeHealthBadges }
    @Published var runtimeLogs: [RuntimeLogEntry] = []
    @Published var isSettingsPresented: Bool = false
    @Published var isRuntimeActive: Bool = false
    @Published var isRecoveryInProgress: Bool = false
    @Published private(set) var isSessionCaptureActive: Bool = false
    @Published private(set) var sessionCaptureEventCount: Int = 0
    @Published private(set) var isSessionReplayActive: Bool = false
    @Published var isDebugInfoVisible: Bool = false
    @Published var isChartInspectorEnabled: Bool = false
    @Published private(set) var isUIRefreshHighLoad: Bool = false
    @Published var deviceVisibility: DashboardDeviceVisibility = .both
    @Published var theme: DashboardTheme = .system
    @Published var isRuntimeLogPanelVisible: Bool = true
    @Published var isRuntimeLogCaptureEnabled: Bool = true
    @Published var isDashboardBeepEnabled: Bool = true
    var isAlarmAcknowledged: Bool { alarmControlService.isAlarmAcknowledged }
    var isAlarmSilenced: Bool { alarmControlService.isAlarmSilenced }
    var alarmSilenceRemainingText: String { alarmControlService.alarmSilenceRemainingText }
    var alarmControlSummary: String { alarmControlService.alarmControlSummary }
    var popoutLayoutProfiles: [AppConfiguration.PopoutLayoutProfile] { popoutLayoutService.popoutLayoutProfiles }
    var activePopoutLayoutProfileName: String { popoutLayoutService.activePopoutLayoutProfileName }
    var multimeterPopoutMode: DevicePopoutDisplayMode { popoutLayoutService.multimeterPopoutMode }
    var usbcPopoutMode: DevicePopoutDisplayMode { popoutLayoutService.usbcPopoutMode }
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

    let chartDataService = ChartDataService()
    let runtimeHealthService = RuntimeHealthService()
    let popoutLayoutService = PopoutLayoutService()
    let alarmControlService = AlarmControlService(beepController: PcBeepController())
    private let configurationService = DashboardConfigurationService()
    private let configurationStore: ConfigurationStore
    private let runtimeLogStore: RuntimeLogStore
    private let diagnosticsBundleService = DiagnosticsBundleService()
    private var serviceCancellables: Set<AnyCancellable> = []
    private var recoveryTask: Task<Void, Never>?
    private var connectionTimeline: [ConnectionTimelineEntry] = []
    private var latestMultimeterAlertState: MeasurementAlertState = .none
    private var pendingMultimeterSnapshot: MultimeterPresentationSnapshot?
    private var pendingUsbCSnapshot: UsbCPresentationSnapshot?
    private var pendingRuntimeLogs: [RuntimeLogEntry] = []
    private var sessionCaptureRecords: [RuntimeSessionCaptureRecord] = []
    private var sessionCaptureStart: Date?
    private var sessionReplayTask: Task<Void, Never>?
    private let uiRefreshNormalCadenceHz = 10
    private let uiRefreshHighLoadCadenceHz = 6
    private let uiRefreshEnterHighLoadScore = 3
    private let uiRefreshExitHighLoadScore = 5
    private var uiRefreshTask: Task<Void, Never>?
    private var uiRefreshMode: UIRefreshMode = .normal
    private var uiRefreshHighLoadScore = 0
    private var uiRefreshRecoverScore = 0
    private var lastUIRefreshProcessingMs: Double = 0
    private var smoothedUIRefreshProcessingMs: Double = 0
    private var uiRefreshModeSwitchCount = 0
    private var pendingMeasurementEventsSinceLastRefresh = 0
    private var lastUIRefreshSummaryTimestamp = Date()
    private var lastUIRefreshSummaryAppliedTicks = 0
    private var lastUIRefreshSummarySkippedTicks = 0
    private var lastUIRefreshAppliedHz: Double = 0
    private var lastUIRefreshSkippedHz: Double = 0
    private var appliedUIRefreshTicks = 0
    private var skippedUIRefreshTicks = 0
#if DEBUG
    private var debugForcedUIRefreshProcessingMs: Double?
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
        refreshRuntimeHealthBadges()
        refreshAlarmControlState(now: Date(), emitStatusOnExpiry: false)
        startUIRefreshLoop()
        processCoalescedUIRefreshTick(force: true)

        chartDataService.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &serviceCancellables)
        runtimeHealthService.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &serviceCancellables)
        popoutLayoutService.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &serviceCancellables)
        alarmControlService.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &serviceCancellables)

        Task {
            await bootstrap()
        }
    }

    deinit {
        uiRefreshTask?.cancel()
        sessionReplayTask?.cancel()
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
                alarmControlService.resetState()
                alarmControlService.stopBeep()
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
        chartDataService.clearCharts()
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
        alarmControlService.updateBeep(for: latestMultimeterAlertState, configuration: configuration, isDashboardBeepEnabled: isDashboardBeepEnabled)
        persistConfigurationSilently()
    }

    var hasActiveAlarm: Bool {
        latestMultimeterAlertState != .none
    }

    func toggleAlarmAcknowledge() {
        guard latestMultimeterAlertState != .none || isAlarmAcknowledged else {
            setStatusMessage("No active alarm to acknowledge", level: .warning)
            return
        }
        let message = alarmControlService.toggleAcknowledge(latestAlertState: latestMultimeterAlertState)
        alarmControlService.updateBeep(for: latestMultimeterAlertState, configuration: configuration, isDashboardBeepEnabled: isDashboardBeepEnabled)
        setStatusMessage(message)
    }

    func silenceAlarms(for seconds: TimeInterval) {
        let message = alarmControlService.silenceAlarms(for: seconds, latestAlertState: latestMultimeterAlertState)
        alarmControlService.updateBeep(for: latestMultimeterAlertState, configuration: configuration, isDashboardBeepEnabled: isDashboardBeepEnabled)
        setStatusMessage(message)
    }

    func silenceAlarms(using preset: AlarmSilencePreset) {
        silenceAlarms(for: preset.seconds)
    }

    func clearAlarmSilence() {
        guard let message = alarmControlService.clearSilence(latestAlertState: latestMultimeterAlertState) else {
            return
        }
        alarmControlService.updateBeep(for: latestMultimeterAlertState, configuration: configuration, isDashboardBeepEnabled: isDashboardBeepEnabled)
        setStatusMessage(message)
    }

    func toggleRenderPause() {
        isRenderPaused.toggle()
        if isRenderPaused {
            setStatusMessage("UI rendering paused")
            refreshRuntimeHealthBadges()
            return
        }

        setStatusMessage("UI rendering resumed")
        refreshRuntimeHealthBadges()
        processCoalescedUIRefreshTick(force: true)
    }

    func toggleDebugInfoVisibility() {
        isDebugInfoVisible.toggle()
    }

    func toggleChartInspector() {
        isChartInspectorEnabled.toggle()
    }

    func popoutMode(for kind: DevicePopoutKind) -> DevicePopoutDisplayMode {
        popoutLayoutService.popoutMode(for: kind)
    }

    var hasPopoutLayoutProfiles: Bool {
        popoutLayoutService.hasPopoutLayoutProfiles
    }

    func isActivePopoutLayoutProfile(_ name: String) -> Bool {
        popoutLayoutService.isActivePopoutLayoutProfile(name)
    }

    func suggestedPopoutLayoutProfileName() -> String {
        popoutLayoutService.suggestedPopoutLayoutProfileName()
    }

    func setPopoutMode(_ mode: DevicePopoutDisplayMode, for kind: DevicePopoutKind) {
        guard popoutLayoutService.setPopoutMode(mode, for: kind, configuration: &configuration) else {
            return
        }
        editableConfiguration = configuration
        persistConfigurationSilently()
    }

    func popoutFrame(for kind: DevicePopoutKind) -> AppConfiguration.PopoutWindowFrame? {
        switch kind {
        case .multimeter:
            return configuration.multimeterPopoutFrame
        case .usbc:
            return configuration.usbcPopoutFrame
        }
    }

    func setPopoutFrame(_ frame: AppConfiguration.PopoutWindowFrame, for kind: DevicePopoutKind) {
        guard popoutLayoutService.setPopoutFrame(frame, for: kind, configuration: &configuration) else {
            return
        }
        editableConfiguration = configuration
        persistConfigurationSilently()
    }

    func saveCurrentPopoutLayoutProfile(named rawName: String) {
        guard let name = popoutLayoutService.saveCurrentLayoutProfile(named: rawName, configuration: &configuration) else {
            setStatusMessage("Pop-out profile name cannot be empty.", level: .warning)
            return
        }
        editableConfiguration = configuration
        persistConfigurationSilently()
        setStatusMessage("Pop-out profile saved: \(name)")
    }

    func applyPopoutLayoutProfile(named name: String) -> Bool {
        guard popoutLayoutService.applyLayoutProfile(named: name, configuration: &configuration) else {
            setStatusMessage("Pop-out profile not found: \(name)", level: .warning)
            return false
        }
        editableConfiguration = configuration
        persistConfigurationSilently()
        setStatusMessage("Pop-out profile applied: \(name)")
        return true
    }

    func deletePopoutLayoutProfile(named name: String) {
        popoutLayoutService.deleteLayoutProfile(named: name, configuration: &configuration)
        editableConfiguration = configuration
        persistConfigurationSilently()
        setStatusMessage("Pop-out profile deleted: \(name)")
    }

    func resetVisualState() {
        multimeterAlert = "OK"
        multimeterAlertState = .none
        latestMultimeterAlertState = .none
        pendingMultimeterSnapshot = nil
        alarmControlService.resetState()
        alarmControlService.updateBeep(for: .none, configuration: configuration, isDashboardBeepEnabled: isDashboardBeepEnabled)
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

    func startRuntimeSessionCapture() {
        sessionCaptureStart = Date()
        sessionCaptureRecords.removeAll(keepingCapacity: true)
        sessionCaptureEventCount = 0
        isSessionCaptureActive = true
        setStatusMessage("Session capture started")
    }

    func stopRuntimeSessionCapture() {
        guard isSessionCaptureActive else {
            return
        }
        isSessionCaptureActive = false
        setStatusMessage("Session capture stopped (\(sessionCaptureEventCount) events)")
    }

    func exportRuntimeSessionCapture(to destinationURL: URL) {
        guard !sessionCaptureRecords.isEmpty else {
            setStatusMessage("No captured session events to export.", level: .warning)
            return
        }

        let createdAt = sessionCaptureStart ?? Date()
        let records = sessionCaptureRecords
        Task {
            do {
                try RuntimeSessionCaptureService.writeCapture(
                    createdAt: createdAt,
                    records: records,
                    to: destinationURL
                )
                await MainActor.run {
                    setStatusMessage("Session capture exported to \(destinationURL.path)")
                }
            } catch {
                await MainActor.run {
                    setStatusMessage("Failed to export session capture: \(error.localizedDescription)", level: .error)
                }
            }
        }
    }

    func replayRuntimeSession(from sourceURL: URL) {
        sessionReplayTask?.cancel()
        sessionReplayTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let capture = try RuntimeSessionCaptureService.readCapture(from: sourceURL)
                await MainActor.run {
                    self.isSessionReplayActive = true
                    self.setStatusMessage("Session replay started (\(capture.events.count) events)")
                }

                var previousOffset = 0
                for record in capture.events {
                    if Task.isCancelled {
                        return
                    }
                    let waitMilliseconds = max(0, record.offsetMilliseconds - previousOffset)
                    previousOffset = record.offsetMilliseconds
                    if waitMilliseconds > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(waitMilliseconds) * 1_000_000)
                    }
                    guard let event = RuntimeSessionCaptureService.runtimeEvent(from: record) else {
                        continue
                    }
                    await MainActor.run {
                        self.handleRuntimeEvent(event)
                    }
                }

                await MainActor.run {
                    self.isSessionReplayActive = false
                    self.sessionReplayTask = nil
                    self.setStatusMessage("Session replay completed")
                }
            } catch {
                await MainActor.run {
                    self.isSessionReplayActive = false
                    self.sessionReplayTask = nil
                    self.setStatusMessage("Failed to replay session: \(error.localizedDescription)", level: .error)
                }
            }
        }
    }

    func stopRuntimeSessionReplay() {
        guard isSessionReplayActive else {
            return
        }
        sessionReplayTask?.cancel()
        sessionReplayTask = nil
        isSessionReplayActive = false
        setStatusMessage("Session replay stopped")
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
        captureRuntimeSessionEvent(event, at: Date())

        switch event {
        case .multimeterStatus(let state, let message):
            multimeterStatus = state
            recordConnectionTimeline(device: "multimeter", state: state, message: message)
            if state == .disconnected || state == .error {
                alarmControlService.stopBeep()
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
            runtimeHealthService.incrementRuntimeErrorCount()
            if message.lowercased().contains("parse") {
                runtimeHealthService.incrementParseErrorCount()
            }
            setStatusMessage(message, level: .error)
            appendHealthSnapshot(reason: "runtime_error")

        case .runtimeLog(let level, let message):
            runtimeHealthService.recordRuntimeLogHealth(level: level, message: message)
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
        refreshRuntimeHealthBadges()
    }

    private func handleMultimeterMeasurement(_ measurement: DeviceMeasurement) {
        let previousAlert = latestMultimeterAlertState
        let primary = MeasurementDisplayFormatter.multimeterPrimary(measurement)
        let secondary = MeasurementDisplayFormatter.multimeterSecondary(measurement)
        let mode = MeasurementDisplayFormatter.multimeterModeTitle(measurement)

        let alert = DashboardAlertService.evaluate(measurement: measurement, configuration: configuration, previousState: previousAlert)
        latestMultimeterAlertState = alert
        alarmControlService.reconcileAcknowledge(previousAlert: previousAlert, currentAlert: alert)
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

        refreshAlarmControlState(now: Date(), emitStatusOnExpiry: true)
        alarmControlService.updateBeep(for: alert, configuration: configuration, isDashboardBeepEnabled: isDashboardBeepEnabled)

        if let value = measurement.primaryValue {
            multimeterSamples.append(ChartSample(timestamp: measurement.timestamp, value: value))
            trimChartsIfNeeded()
        }

        pendingMeasurementEventsSinceLastRefresh += 1
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
        pendingMeasurementEventsSinceLastRefresh += 1
        markChartRefresh(usbc: true, reason: "usbc_measurement")
    }

    private func refreshRuntimeStateFlag() {
        let activeStates: Set<DeviceUIState> = [.connecting, .connected]
        isRuntimeActive = activeStates.contains(multimeterStatus) || activeStates.contains(usbcStatus)
    }

    private func trimChartsIfNeeded() {
        chartDataService.trimChartsIfNeeded(
            graphHistorySeconds: configuration.graphHistorySeconds,
            sampleRateHz: configuration.sampleRateHz
        )
    }

    private func runRecoverySequence() async {
        defer {
            isRecoveryInProgress = false
            recoveryTask = nil
        }

        let configSnapshot = configuration

        isRecoveryInProgress = true
        setStatusMessage("Recovery: stopping runtime...", level: .warning)
        alarmControlService.stopBeep()

        await runtime.stop()

        multimeterAlert = "OK"
        multimeterAlertState = .none
        latestMultimeterAlertState = .none
        pendingMultimeterSnapshot = nil
        pendingUsbCSnapshot = nil
        alarmControlService.resetState()
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
        popoutLayoutService.syncFromConfiguration(config)
    }

    private func configureBeepController() {
        let preset = MacAlertSoundPreset(configurationValue: configuration.pcBeepSoundPreset)
        alarmControlService.configureBeep(soundPreset: preset, volume: configuration.pcBeepVolume)
        alarmControlService.updateBeep(for: latestMultimeterAlertState, configuration: configuration, isDashboardBeepEnabled: isDashboardBeepEnabled)
    }



    private func captureRuntimeSessionEvent(_ event: RuntimeEvent, at now: Date) {
        guard isSessionCaptureActive else {
            return
        }
        let reference = sessionCaptureStart ?? now
        if sessionCaptureStart == nil {
            sessionCaptureStart = now
        }
        let offsetMs = Int((now.timeIntervalSince(reference) * 1_000).rounded())
        sessionCaptureRecords.append(
            RuntimeSessionCaptureService.makeRecord(
                event: event,
                offsetMilliseconds: max(0, offsetMs)
            )
        )
        if sessionCaptureRecords.count > 20_000 {
            sessionCaptureRecords.removeFirst(sessionCaptureRecords.count - 20_000)
        }
        sessionCaptureEventCount = sessionCaptureRecords.count
    }

    private func refreshAlarmControlState(now: Date, emitStatusOnExpiry: Bool) {
        let result = alarmControlService.refreshState(
            latestAlertState: latestMultimeterAlertState,
            now: now,
            emitStatusOnExpiry: emitStatusOnExpiry
        )
        if let message = result.expiryStatusMessage {
            setStatusMessage(message)
        }
        if result.silenceDidExpire {
            alarmControlService.updateBeep(for: latestMultimeterAlertState, configuration: configuration, isDashboardBeepEnabled: isDashboardBeepEnabled)
        }
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

        uiRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                let intervalNanos = await MainActor.run {
                    self?.activeUIRefreshIntervalNanos ?? UInt64(100_000_000)
                }
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
        chartDataService.markChartRefresh(multimeter: multimeter, usbc: usbc, markers: markers, reason: reason)
    }

    private func processCoalescedUIRefreshTick(force: Bool) {
        let now = Date()
        refreshAlarmControlState(now: now, emitStatusOnExpiry: true)
        let hasPendingPresentation = pendingMultimeterSnapshot != nil || pendingUsbCSnapshot != nil || !pendingRuntimeLogs.isEmpty
        let hasPendingCharts = chartDataService.chartRefreshPending
        let hasWork = force || hasPendingPresentation || hasPendingCharts
        guard hasWork else {
            recoverUIRefreshModeOnIdle()
            refreshUIRefreshRuntimeSummary(now: now)
            return
        }

        guard !isRenderPaused else {
            skippedUIRefreshTicks += 1
            refreshUIRefreshRuntimeSummary(now: now)
            return
        }

        let tickStart = DispatchTime.now().uptimeNanoseconds
        let measurementBurstCount = pendingMeasurementEventsSinceLastRefresh
        pendingMeasurementEventsSinceLastRefresh = 0
        appliedUIRefreshTicks += 1
        applyPendingPresentationSnapshots()
        flushPendingRuntimeLogsToUI()

        if hasPendingCharts || force {
            let showMultimeter = deviceVisibility != .usbc
            let showUsbC = deviceVisibility != .multimeter
            let chartMaxPoints = chartMaxPointsForCurrentRefreshMode(
                showingBothDevices: showMultimeter && showUsbC
            )
            let reason = chartDataService.refreshDisplayedCharts(
                selectedChartRange: selectedChartRange,
                deviceVisibility: deviceVisibility,
                maxPoints: chartMaxPoints,
                force: force
            )
#if DEBUG
            refreshChartPerformanceSummary(reason: reason)
#endif
        }

        let measuredMs = Double(DispatchTime.now().uptimeNanoseconds - tickStart) / 1_000_000
#if DEBUG
        let effectiveMs = debugForcedUIRefreshProcessingMs ?? measuredMs
#else
        let effectiveMs = measuredMs
#endif
        updateAdaptiveUIRefreshMode(
            processingMilliseconds: effectiveMs,
            hadPendingPresentation: hasPendingPresentation,
            hadPendingCharts: hasPendingCharts,
            measurementBurstCount: measurementBurstCount
        )
        refreshUIRefreshRuntimeSummary(now: now)
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

#if DEBUG
    private func refreshChartPerformanceSummary(reason: String) {
        let mm = chartDataService.lastMultimeterPipelineMetric
        let usbc = chartDataService.lastUsbCPipelineMetric
        chartPerformanceSummary =
            "Pipeline \(reason) | mode \(uiRefreshMode.rawValue) @ \(activeUIRefreshCadenceHz)Hz | " +
            "MM \(mm.sourcePointCount)→\(mm.filteredPointCount)" +
            "→\(mm.renderedPointCount) (\(formatMilliseconds(mm.processingMilliseconds))ms) | " +
            "USB-C \(usbc.sourcePointCount)→\(usbc.filteredPointCount)" +
            "→\(usbc.renderedPointCount) (\(formatMilliseconds(usbc.processingMilliseconds))ms) | " +
            "tick \(formatMilliseconds(lastUIRefreshProcessingMs))/\(formatMilliseconds(smoothedUIRefreshProcessingMs))ms | " +
            "UI ticks \(appliedUIRefreshTicks) applied / \(skippedUIRefreshTicks) skipped | switches \(uiRefreshModeSwitchCount)"
    }
#endif

    private var activeUIRefreshCadenceHz: Int {
        switch uiRefreshMode {
        case .normal:
            return uiRefreshNormalCadenceHz
        case .highLoad:
            return uiRefreshHighLoadCadenceHz
        }
    }

    private var activeUIRefreshIntervalNanos: UInt64 {
        UInt64(1_000_000_000 / max(1, activeUIRefreshCadenceHz))
    }

    private func chartMaxPointsForCurrentRefreshMode(showingBothDevices: Bool) -> Int {
        switch uiRefreshMode {
        case .normal:
            return showingBothDevices ? 150 : 180
        case .highLoad:
            return showingBothDevices ? 120 : 150
        }
    }

    private func recoverUIRefreshModeOnIdle() {
        uiRefreshHighLoadScore = max(0, uiRefreshHighLoadScore - 1)
        uiRefreshRecoverScore = min(uiRefreshExitHighLoadScore, uiRefreshRecoverScore + 1)
        guard uiRefreshMode == .highLoad, uiRefreshRecoverScore >= uiRefreshExitHighLoadScore else {
            return
        }
        switchUIRefreshMode(to: .normal, reason: "idle")
    }

    private func updateAdaptiveUIRefreshMode(
        processingMilliseconds: Double,
        hadPendingPresentation: Bool,
        hadPendingCharts: Bool,
        measurementBurstCount: Int
    ) {
        lastUIRefreshProcessingMs = processingMilliseconds
        if smoothedUIRefreshProcessingMs == 0 {
            smoothedUIRefreshProcessingMs = processingMilliseconds
        } else {
            smoothedUIRefreshProcessingMs = (smoothedUIRefreshProcessingMs * 0.75) + (processingMilliseconds * 0.25)
        }

        let overloadThreshold: Double = uiRefreshMode == .normal ? 14.0 : 18.0
        let recoveryThreshold: Double = 8.0
        let isBursting = measurementBurstCount >= 80
        let overloaded = hadPendingCharts && (smoothedUIRefreshProcessingMs >= overloadThreshold || isBursting)
        let recoverable = (!hadPendingCharts && measurementBurstCount < 20)
            || (!hadPendingPresentation && smoothedUIRefreshProcessingMs <= recoveryThreshold)

        if overloaded {
            let increment = isBursting ? uiRefreshEnterHighLoadScore : 1
            uiRefreshHighLoadScore = min(uiRefreshEnterHighLoadScore + 4, uiRefreshHighLoadScore + increment)
            uiRefreshRecoverScore = max(0, uiRefreshRecoverScore - 1)
        } else if recoverable {
            uiRefreshRecoverScore = min(uiRefreshExitHighLoadScore + 6, uiRefreshRecoverScore + 1)
            uiRefreshHighLoadScore = max(0, uiRefreshHighLoadScore - 1)
        } else {
            uiRefreshHighLoadScore = max(0, uiRefreshHighLoadScore - 1)
            uiRefreshRecoverScore = max(0, uiRefreshRecoverScore - 1)
        }

        if uiRefreshMode == .normal, uiRefreshHighLoadScore >= uiRefreshEnterHighLoadScore {
            switchUIRefreshMode(to: .highLoad, reason: "processing")
        } else if uiRefreshMode == .highLoad, uiRefreshRecoverScore >= uiRefreshExitHighLoadScore {
            switchUIRefreshMode(to: .normal, reason: "recovered")
        }
    }

    private func switchUIRefreshMode(to mode: UIRefreshMode, reason: String) {
        guard uiRefreshMode != mode else {
            return
        }
        uiRefreshMode = mode
        isUIRefreshHighLoad = mode == .highLoad
        uiRefreshModeSwitchCount += 1
        uiRefreshHighLoadScore = 0
        uiRefreshRecoverScore = 0
        appendRuntimeLog(
            "UI refresh mode: \(mode.rawValue) (\(activeUIRefreshCadenceHz)Hz, reason: \(reason))",
            level: .info,
            persist: false
        )
        refreshUIRefreshRuntimeSummary(now: Date(), force: true)
    }

    private func refreshUIRefreshRuntimeSummary(now: Date, force: Bool = false) {
        let elapsed = now.timeIntervalSince(lastUIRefreshSummaryTimestamp)
        guard force || elapsed >= 1.0 else {
            return
        }

        let appliedDelta = appliedUIRefreshTicks - lastUIRefreshSummaryAppliedTicks
        let skippedDelta = skippedUIRefreshTicks - lastUIRefreshSummarySkippedTicks
        let actualHz = elapsed > 0 ? Double(appliedDelta) / elapsed : 0
        let skippedHz = elapsed > 0 ? Double(skippedDelta) / elapsed : 0
        lastUIRefreshAppliedHz = actualHz
        lastUIRefreshSkippedHz = skippedHz

        uiRefreshRuntimeSummary = String(
            format: "UI %@ target:%dHz actual:%.1fHz skip:%.1fHz tick:%.1fms",
            uiRefreshMode.rawValue,
            activeUIRefreshCadenceHz,
            actualHz,
            skippedHz,
            smoothedUIRefreshProcessingMs
        )
        uiRefreshActualHzText = String(format: "%.1fHz", actualHz)

        lastUIRefreshSummaryTimestamp = now
        lastUIRefreshSummaryAppliedTicks = appliedUIRefreshTicks
        lastUIRefreshSummarySkippedTicks = skippedUIRefreshTicks
        refreshRuntimeHealthBadges()
    }

#if DEBUG
    private func formatMilliseconds(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
#endif

    private func appendAlarmMarkerIfNeeded(
        previousAlert: MeasurementAlertState,
        currentAlert: MeasurementAlertState,
        timestamp: Date
    ) {
        chartDataService.appendAlarmMarkerIfNeeded(
            previousAlert: previousAlert,
            currentAlert: currentAlert,
            timestamp: timestamp
        )
    }

    private func makeDiagnosticsBundleInput() -> DiagnosticsBundleInput {
        let exportedLogs = Array((runtimeLogs + pendingRuntimeLogs).suffix(500))
        return DiagnosticsBundleInput(
            exportedAt: Date(),
            configuration: configuration,
            runtimeLogs: exportedLogs,
            healthSnapshots: runtimeHealthService.diagnosticSnapshots(),
            connectionTimeline: Array(connectionTimeline.suffix(500)),
            multimeterStatus: multimeterStatus,
            usbcStatus: usbcStatus,
            isRuntimeActive: isRuntimeActive,
            statusMessage: statusMessage
        )
    }

    private func recordConnectionTimeline(device: String, state: DeviceUIState, message: String?) {
        if let message, message.contains("Retrying") {
            runtimeHealthService.incrementReconnectCount()
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

        chartDataService.recordChartConnectionEvent(entry)
        markChartRefresh(markers: true, reason: "\(device)_status")
        appendHealthSnapshot(reason: "\(device)_status")
    }

    private func refreshRuntimeHealthBadges() {
        runtimeHealthService.refreshBadges(
            uiMetrics: RuntimeHealthService.UIRefreshMetrics(
                appliedHz: lastUIRefreshAppliedHz,
                skippedHz: lastUIRefreshSkippedHz,
                smoothedProcessingMs: smoothedUIRefreshProcessingMs,
                isRenderPaused: isRenderPaused,
                isRuntimeActive: isRuntimeActive,
                mode: uiRefreshMode.rawValue,
                targetHz: activeUIRefreshCadenceHz
            ),
            outputQueueCapacity: configuration.outputQueueCapacity,
            logCount: runtimeLogs.count,
            isLogCaptureEnabled: isRuntimeLogCaptureEnabled
        )
    }

    private func appendHealthSnapshot(reason: String) {
        runtimeHealthService.appendHealthSnapshot(
            reason: reason,
            context: RuntimeHealthService.HealthSnapshotContext(
                isRuntimeActive: isRuntimeActive,
                multimeterStatus: multimeterStatus,
                usbcStatus: usbcStatus,
                runtimeLogCount: runtimeLogs.count + pendingRuntimeLogs.count,
                statusMessage: statusMessage
            )
        )
    }

#if DEBUG
    func debugInjectMultimeterMeasurement(_ measurement: DeviceMeasurement) {
        handleMultimeterMeasurement(measurement)
    }

    func debugInjectRuntimeEvent(_ event: RuntimeEvent) {
        handleRuntimeEvent(event)
    }

    func debugInjectRuntimeLog(level: RuntimeLogLevel, message: String) {
        handleRuntimeEvent(.runtimeLog(level, message))
    }

    func debugSessionCaptureSnapshot() -> (active: Bool, count: Int) {
        (isSessionCaptureActive, sessionCaptureEventCount)
    }

    func debugRefreshTickCounters() -> (applied: Int, skipped: Int) {
        (appliedUIRefreshTicks, skippedUIRefreshTicks)
    }

    func debugSetForcedUIRefreshProcessingMilliseconds(_ value: Double?) {
        debugForcedUIRefreshProcessingMs = value
    }

    func debugUIRefreshDiagnostics() -> (mode: String, targetHz: Int, lastTickMs: Double, smoothedTickMs: Double, switches: Int) {
        (
            uiRefreshMode.rawValue,
            activeUIRefreshCadenceHz,
            lastUIRefreshProcessingMs,
            smoothedUIRefreshProcessingMs,
            uiRefreshModeSwitchCount
        )
    }

    func debugForceUIRefreshSummaryUpdate() {
        refreshUIRefreshRuntimeSummary(now: Date(), force: true)
    }
#endif
}
