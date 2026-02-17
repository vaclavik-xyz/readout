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
