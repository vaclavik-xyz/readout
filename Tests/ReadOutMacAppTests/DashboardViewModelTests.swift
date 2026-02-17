import Foundation
import Testing
@testable import ReadOutMacApp
@testable import ReadOutCore

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
