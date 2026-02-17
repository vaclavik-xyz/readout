import Foundation
import Testing
@testable import ReadOutMacApp
@testable import ReadOutCore
@testable import ReadOutPersistence

private func uniqueSessionCaptureURL(_ suffix: String) -> URL {
    let base = FileManager.default.temporaryDirectory
    let id = UUID().uuidString
    return base.appendingPathComponent("readout-session-\(id)-\(suffix)")
}

@MainActor
@Test
func clearChartsRemovesAllSamples() {
    let viewModel = DashboardViewModel()
    viewModel.multimeterSamples = [
        ChartSample(timestamp: Date(timeIntervalSince1970: 0), value: 1.0)
    ]
    viewModel.usbcSamples = [
        ChartSample(timestamp: Date(timeIntervalSince1970: 0), value: 2.0)
    ]
    viewModel.alarmMarkers = [
        AlarmTimelineMarker(timestamp: Date(timeIntervalSince1970: 0), state: .short, message: "SHORT")
    ]

    viewModel.clearCharts()

    #expect(viewModel.multimeterSamples.isEmpty)
    #expect(viewModel.usbcSamples.isEmpty)
    #expect(viewModel.alarmMarkers.isEmpty)
    #expect(viewModel.statusMessage == "Charts cleared")
}

@MainActor
@Test
func resetVisualStateClearsAlertPresentation() {
    let viewModel = DashboardViewModel()
    viewModel.multimeterAlert = "HIGH ALARM"
    viewModel.multimeterAlertState = .highAlarm

    viewModel.resetVisualState()

    #expect(viewModel.multimeterAlert == "OK")
    #expect(viewModel.multimeterAlertState == .none)
    #expect(viewModel.statusMessage == "Visual state reset")
}

@MainActor
@Test
func clearRuntimeLogsDropsPreviousEntries() {
    let viewModel = DashboardViewModel()
    viewModel.runtimeLogs = [
        RuntimeLogEntry(
            timestamp: Date(timeIntervalSince1970: 0),
            level: .error,
            message: "stale-log-entry"
        )
    ]

    viewModel.clearRuntimeLogs()

    #expect(viewModel.statusMessage == "Runtime logs cleared")
    #expect(viewModel.runtimeLogs.contains(where: { $0.message == "stale-log-entry" }) == false)
}

@MainActor
@Test
func restartRuntimeIgnoresRepeatedTrigger() {
    let viewModel = DashboardViewModel()

    viewModel.restartRuntime()
    viewModel.restartRuntime()

    #expect(viewModel.statusMessage == "Recovery already in progress.")
}

@MainActor
@Test
func dashboardVisibilityPersistsToConfiguration() {
    let viewModel = DashboardViewModel()

    viewModel.setDeviceVisibility(.usbc)

    #expect(viewModel.deviceVisibility == .usbc)
    #expect(viewModel.configuration.dashboardDeviceVisibility == .usbc)
}

@MainActor
@Test
func dashboardBeepMasterToggleUpdatesConfiguration() {
    let viewModel = DashboardViewModel()
    let initial = viewModel.configuration.dashboardBeepMasterEnabled

    viewModel.toggleDashboardBeep()

    #expect(viewModel.isDashboardBeepEnabled != initial)
    #expect(viewModel.configuration.dashboardBeepMasterEnabled == viewModel.isDashboardBeepEnabled)
}

@MainActor
@Test
func popoutModeSelectionPersistsToConfiguration() {
    let viewModel = DashboardViewModel()

    viewModel.setPopoutMode(.mini, for: .multimeter)
    viewModel.setPopoutMode(.compact, for: .usbc)

    #expect(viewModel.multimeterPopoutMode == .mini)
    #expect(viewModel.usbcPopoutMode == .compact)
    #expect(viewModel.configuration.multimeterPopoutMode == .mini)
    #expect(viewModel.configuration.usbcPopoutMode == .compact)
}

@MainActor
@Test
func popoutFramePersistsToConfiguration() {
    let viewModel = DashboardViewModel()
    let frame = AppConfiguration.PopoutWindowFrame(x: 120, y: 140, width: 420, height: 260)

    viewModel.setPopoutFrame(frame, for: .multimeter)

    #expect(viewModel.popoutFrame(for: .multimeter) == frame)
    #expect(viewModel.configuration.multimeterPopoutFrame == frame)
}

@MainActor
@Test
func popoutLayoutProfileSaveApplyAndDeleteFlow() {
    let viewModel = DashboardViewModel()
    let multimeterFrame = AppConfiguration.PopoutWindowFrame(x: 90, y: 120, width: 420, height: 240)
    let usbcFrame = AppConfiguration.PopoutWindowFrame(x: 560, y: 140, width: 430, height: 250)

    viewModel.setPopoutMode(.mini, for: .multimeter)
    viewModel.setPopoutMode(.compact, for: .usbc)
    viewModel.setPopoutFrame(multimeterFrame, for: .multimeter)
    viewModel.setPopoutFrame(usbcFrame, for: .usbc)
    viewModel.saveCurrentPopoutLayoutProfile(named: "Desk")

    #expect(viewModel.popoutLayoutProfiles.count == 1)
    #expect(viewModel.activePopoutLayoutProfileName == "Desk")

    viewModel.setPopoutMode(.detailed, for: .multimeter)
    viewModel.setPopoutMode(.detailed, for: .usbc)
    _ = viewModel.applyPopoutLayoutProfile(named: "Desk")

    #expect(viewModel.multimeterPopoutMode == .mini)
    #expect(viewModel.usbcPopoutMode == .compact)
    #expect(viewModel.popoutFrame(for: .multimeter) == multimeterFrame)
    #expect(viewModel.popoutFrame(for: .usbc) == usbcFrame)
    #expect(viewModel.activePopoutLayoutProfileName == "Desk")

    viewModel.deletePopoutLayoutProfile(named: "Desk")
    #expect(viewModel.popoutLayoutProfiles.isEmpty)
    #expect(viewModel.activePopoutLayoutProfileName.isEmpty)
}

@MainActor
@Test
func renderPauseToggleChangesStateAndStatus() {
    let viewModel = DashboardViewModel()

    viewModel.toggleRenderPause()
    #expect(viewModel.isRenderPaused)
    #expect(viewModel.statusMessage == "UI rendering paused")

    viewModel.toggleRenderPause()
    #expect(viewModel.isRenderPaused == false)
    #expect(viewModel.statusMessage == "UI rendering resumed")
}

@MainActor
@Test
func pauseFreezesMeasurementPresentationUntilResume() async {
    let viewModel = DashboardViewModel()

    let measurement = DeviceMeasurement(
        device: .multimeter,
        mode: .dcVoltage,
        modeString: "VOLT:DC",
        primaryValue: 12.3456,
        primaryUnit: "V DC"
    )

    viewModel.toggleRenderPause()
    #expect(viewModel.multimeterPrimary == "---")

    viewModel.debugInjectMultimeterMeasurement(measurement)
    try? await Task.sleep(nanoseconds: 220_000_000)
    #expect(viewModel.multimeterPrimary == "---")

    viewModel.toggleRenderPause()
    #expect(viewModel.multimeterPrimary == "12.3456")
}

@MainActor
@Test
func logCaptureDisabledSuppressesInfoButKeepsWarnings() {
    let viewModel = DashboardViewModel()
    viewModel.runtimeLogs.removeAll(keepingCapacity: true)
    viewModel.isRuntimeLogCaptureEnabled = false

    viewModel.debugInjectRuntimeLog(level: .info, message: "info-muted")
    viewModel.debugInjectRuntimeLog(level: .warning, message: "warn-kept")

    #expect(viewModel.runtimeLogs.contains(where: { $0.message == "info-muted" }) == false)
    #expect(viewModel.runtimeLogs.contains(where: { $0.message == "warn-kept" }))
}

@MainActor
@Test
func coalescedRefreshDoesNotScaleLinearlyWithMeasurementBurst() async {
    let viewModel = DashboardViewModel()
    let before = viewModel.debugRefreshTickCounters()

    let baseTimestamp = Date()
    for i in 0..<400 {
        viewModel.debugInjectMultimeterMeasurement(
            DeviceMeasurement(
                device: .multimeter,
                mode: .dcVoltage,
                modeString: "VOLT:DC",
                primaryValue: Double(i) * 0.01,
                primaryUnit: "V DC",
                timestamp: baseTimestamp.addingTimeInterval(Double(i) * 0.001)
            )
        )
    }

    try? await Task.sleep(nanoseconds: 260_000_000)

    let after = viewModel.debugRefreshTickCounters()
    let appliedDelta = after.applied - before.applied

    #expect(appliedDelta > 0)
    #expect(appliedDelta < 50)
}

@MainActor
@Test
func adaptiveRefreshEntersHighLoadModeUnderSustainedTickCost() async {
    let viewModel = DashboardViewModel()
    viewModel.debugSetForcedUIRefreshProcessingMilliseconds(24)

    let baseTimestamp = Date()
    for i in 0..<260 {
        viewModel.debugInjectMultimeterMeasurement(
            DeviceMeasurement(
                device: .multimeter,
                mode: .dcVoltage,
                modeString: "VOLT:DC",
                primaryValue: Double(i) * 0.01,
                primaryUnit: "V DC",
                timestamp: baseTimestamp.addingTimeInterval(Double(i) * 0.001)
            )
        )
    }

    try? await Task.sleep(nanoseconds: 700_000_000)

    let diagnostics = viewModel.debugUIRefreshDiagnostics()
    #expect(diagnostics.mode == "high-load")
    #expect(diagnostics.targetHz == 6)
    #expect(diagnostics.targetHz >= 1)
    #expect(diagnostics.targetHz <= 10)
}

@MainActor
@Test
func adaptiveRefreshReturnsToNormalAfterLoadDrops() async {
    let viewModel = DashboardViewModel()
    viewModel.debugSetForcedUIRefreshProcessingMilliseconds(24)

    let baseTimestamp = Date()
    for i in 0..<260 {
        viewModel.debugInjectMultimeterMeasurement(
            DeviceMeasurement(
                device: .multimeter,
                mode: .dcVoltage,
                modeString: "VOLT:DC",
                primaryValue: Double(i) * 0.01,
                primaryUnit: "V DC",
                timestamp: baseTimestamp.addingTimeInterval(Double(i) * 0.001)
            )
        )
    }

    try? await Task.sleep(nanoseconds: 700_000_000)
    #expect(viewModel.debugUIRefreshDiagnostics().mode == "high-load")

    viewModel.debugSetForcedUIRefreshProcessingMilliseconds(1.2)
    try? await Task.sleep(nanoseconds: 1_100_000_000)

    let diagnostics = viewModel.debugUIRefreshDiagnostics()
    #expect(diagnostics.mode == "normal")
    #expect(diagnostics.targetHz == 10)
}

@MainActor
@Test
func uiRefreshRuntimeSummaryReflectsAdaptiveMode() async {
    let viewModel = DashboardViewModel()
    viewModel.debugForceUIRefreshSummaryUpdate()
    #expect(viewModel.uiRefreshRuntimeSummary.contains("target:10Hz"))

    viewModel.debugSetForcedUIRefreshProcessingMilliseconds(24)
    let baseTimestamp = Date()
    for i in 0..<260 {
        viewModel.debugInjectMultimeterMeasurement(
            DeviceMeasurement(
                device: .multimeter,
                mode: .dcVoltage,
                modeString: "VOLT:DC",
                primaryValue: Double(i) * 0.01,
                primaryUnit: "V DC",
                timestamp: baseTimestamp.addingTimeInterval(Double(i) * 0.001)
            )
        )
    }

    try? await Task.sleep(nanoseconds: 700_000_000)
    #expect(viewModel.debugUIRefreshDiagnostics().mode == "high-load")

    viewModel.debugForceUIRefreshSummaryUpdate()
    #expect(viewModel.uiRefreshRuntimeSummary.contains("high-load"))
    #expect(viewModel.uiRefreshRuntimeSummary.contains("target:6Hz"))
}

@MainActor
@Test
func runtimeHealthBadgesExposeCoreCategories() {
    let viewModel = DashboardViewModel()
    let ids = Set(viewModel.runtimeHealthBadges.map(\.id))

    #expect(ids.contains("ui_refresh"))
    #expect(ids.contains("output_queues"))
    #expect(ids.contains("runtime_faults"))
    #expect(ids.contains("log_capture"))
}

@MainActor
@Test
func runtimeHealthBadgeMarksOutputQueueDropsAsCritical() {
    let viewModel = DashboardViewModel()

    viewModel.debugInjectRuntimeLog(
        level: .warning,
        message: "Output queue multimeter-csv: dropped 3 writes (capacity 256, queued 255)."
    )

    let queueBadge = viewModel.runtimeHealthBadges.first(where: { $0.id == "output_queues" })
    #expect(queueBadge?.severity == .critical)
    #expect(queueBadge?.value.contains("drop 3") == true)
}

@MainActor
@Test
func runtimeHealthBadgeShowsUiWarningDuringPause() {
    let viewModel = DashboardViewModel()

    viewModel.toggleRenderPause()

    let uiBadge = viewModel.runtimeHealthBadges.first(where: { $0.id == "ui_refresh" })
    #expect(uiBadge?.severity == .warning)
}

@MainActor
@Test
func timedAlarmSilenceExpiresAutomatically() async {
    let viewModel = DashboardViewModel()

    viewModel.silenceAlarms(for: 0.2)
    #expect(viewModel.isAlarmSilenced)
    #expect(viewModel.alarmControlSummary.contains("Silenced"))

    try? await Task.sleep(nanoseconds: 520_000_000)

    #expect(viewModel.isAlarmSilenced == false)
    #expect(viewModel.alarmControlSummary == "Live")
}

@MainActor
@Test
func acknowledgeClearsWhenAlertTransitionsToDifferentState() {
    let viewModel = DashboardViewModel()

    let shortMeasurement = DeviceMeasurement(
        device: .multimeter,
        mode: .continuity,
        modeString: "CONT",
        primaryValue: 0.3,
        primaryUnit: "ohm",
        isOverload: false,
        isOpen: false,
        isShort: true
    )
    viewModel.debugInjectMultimeterMeasurement(shortMeasurement)
    viewModel.toggleAlarmAcknowledge()
    #expect(viewModel.isAlarmAcknowledged)
    #expect(viewModel.alarmControlSummary.contains("Acked"))

    viewModel.configuration.dcvHighAlarmEnabled = true
    viewModel.configuration.dcvHighAlarmValue = 5.0

    let highAlarmMeasurement = DeviceMeasurement(
        device: .multimeter,
        mode: .dcVoltage,
        modeString: "VOLT:DC",
        primaryValue: 7.2,
        primaryUnit: "V DC"
    )
    viewModel.debugInjectMultimeterMeasurement(highAlarmMeasurement)

    #expect(viewModel.isAlarmAcknowledged == false)
    #expect(viewModel.alarmControlSummary == "Live")
}

@MainActor
@Test
func sessionCaptureCountsIncomingRuntimeEvents() {
    let viewModel = DashboardViewModel()
    viewModel.startRuntimeSessionCapture()

    viewModel.debugInjectRuntimeEvent(.multimeterStatus(.connected, "connected"))
    viewModel.debugInjectRuntimeEvent(.runtimeLog(.warning, "warn"))
    viewModel.stopRuntimeSessionCapture()

    let capture = viewModel.debugSessionCaptureSnapshot()
    #expect(capture.active == false)
    #expect(capture.count >= 2)
}

@MainActor
@Test
func sessionReplayFeedsCapturedEventsIntoDashboardState() async throws {
    let viewModel = DashboardViewModel()
    let now = Date(timeIntervalSince1970: 1_800_000_100)
    let records = [
        RuntimeSessionCaptureService.makeRecord(
            event: .multimeterStatus(.connected, "Replay connected"),
            offsetMilliseconds: 0
        ),
        RuntimeSessionCaptureService.makeRecord(
            event: .runtimeError("Replay injected runtime error"),
            offsetMilliseconds: 40
        )
    ]
    let captureURL = uniqueSessionCaptureURL("replay.json")
    try RuntimeSessionCaptureService.writeCapture(createdAt: now, records: records, to: captureURL)

    viewModel.replayRuntimeSession(from: captureURL)
    try? await Task.sleep(nanoseconds: 300_000_000)

    #expect(viewModel.isSessionReplayActive == false)
    #expect(viewModel.multimeterStatus == .connected)
    #expect(viewModel.runtimeLogs.contains(where: { $0.message == "Replay injected runtime error" }))
}
