import SwiftUI
import Charts
import ReadOutCore

struct ContentView: View {
    @ObservedObject var viewModel: DashboardViewModel
    let popoutManager: DevicePopoutManager
    @State private var selectedMultimeterTimestamp: Date?
    @State private var selectedUsbCTimestamp: Date?

    private var palette: DashboardPalette {
        DashboardThemePalette.palette(for: viewModel.theme)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    palette.backgroundTop,
                    palette.backgroundBottom
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 16) {
                DashboardHeaderView(viewModel: viewModel, palette: palette, popoutManager: popoutManager)
                StatusStripView(viewModel: viewModel, palette: palette)
                if viewModel.isDebugInfoVisible {
                    RuntimeHealthStripView(badges: viewModel.runtimeHealthBadges, palette: palette)
                }
                cards
                AlarmHistoryStripView(
                    markers: viewModel.displayedAlarmMarkers,
                    deviceVisibility: viewModel.deviceVisibility,
                    palette: palette
                )
                charts
                if viewModel.isDebugInfoVisible && viewModel.isRuntimeLogPanelVisible {
                    RuntimeLogPanelView(
                        logs: viewModel.runtimeLogs,
                        isLogCaptureEnabled: viewModel.isRuntimeLogCaptureEnabled,
                        palette: palette
                    )
                }
            }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .preferredColorScheme(viewModel.theme.preferredColorScheme)
        .sheet(isPresented: $viewModel.isSettingsPresented) {
            SettingsView(
                configuration: $viewModel.editableConfiguration,
                availablePorts: viewModel.availablePorts,
                onRefreshPorts: { viewModel.refreshPorts() },
                onOpenSetupWizard: { viewModel.openFirstRunWizardFromSettings() },
                onCancel: { viewModel.cancelSettings() },
                onSave: { viewModel.saveSettings() }
            )
            .frame(minWidth: 760, minHeight: 620)
        }
        .sheet(isPresented: $viewModel.isFirstRunWizardPresented) {
            FirstRunWizardView(
                configuration: $viewModel.firstRunConfiguration,
                availablePorts: viewModel.availablePorts,
                probeResult: viewModel.firstRunProbeResult,
                blockingIssues: viewModel.firstRunBlockingIssues,
                reason: viewModel.firstRunReason,
                canCancel: viewModel.canDismissFirstRunWizard,
                onRescan: { viewModel.refreshFirstRunPorts() },
                onApplyRecommendations: { viewModel.applyFirstRunRecommendations() },
                onModeChanged: { viewModel.firstRunModeChanged() },
                onConfigurationChanged: { viewModel.firstRunConfigurationDidChange() },
                onCancel: { viewModel.dismissFirstRunWizard() },
                onSave: { viewModel.saveFirstRunWizard() }
            )
            .frame(minWidth: 760, minHeight: 620)
        }
    }

    private var cards: some View {
        Group {
            switch viewModel.deviceVisibility {
            case .both:
                HStack(spacing: 14) {
                    multimeterCard
                    usbCCard
                }
            case .multimeter:
                multimeterCard
            case .usbc:
                usbCCard
            }
        }
    }

    private var multimeterCard: some View {
        DeviceCardView(
            title: "Multimeter",
            status: viewModel.multimeterStatus,
            primary: viewModel.multimeterPrimary,
            secondary: viewModel.multimeterSecondary,
            footerLeft: viewModel.multimeterMode,
            footerRight: "Alert: \(viewModel.multimeterAlert)",
            alertState: viewModel.multimeterAlertState,
            palette: palette
        )
    }

    private var usbCCard: some View {
        DeviceCardView(
            title: "USB-C Meter",
            status: viewModel.usbcStatus,
            primary: viewModel.usbcVoltage,
            secondary: viewModel.usbcCurrent,
            footerLeft: viewModel.usbcPower,
            footerRight: viewModel.usbcEnergy,
            alertState: nil,
            palette: palette
        )
    }

    private var charts: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Chart Range")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.secondaryText)

                Picker("Chart range", selection: $viewModel.selectedChartRange) {
                    ForEach(ChartRangePreset.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)

                Spacer()

                if viewModel.isDebugInfoVisible {
                    Text("MM: \(viewModel.displayedMultimeterSamples.count) pts | USB-C: \(viewModel.displayedUsbCSamples.count) pts")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(palette.tertiaryText)
                }
            }

#if DEBUG
            if viewModel.isDebugInfoVisible {
                Text(viewModel.chartPerformanceSummary)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
#endif

            switch viewModel.deviceVisibility {
            case .both:
                HStack(spacing: 14) {
                    multimeterChart
                    usbCChart
                }
            case .multimeter:
                multimeterChart
            case .usbc:
                usbCChart
            }
        }
    }

    private var multimeterChart: some View {
        MeasurementChartView(
            title: "Multimeter Trend",
            color: palette.chartMultimeter,
            samples: viewModel.displayedMultimeterSamples,
            markers: viewModel.displayedAlarmMarkers,
            reconnectMarkers: viewModel.displayedMultimeterConnectionMarkers,
            selectedTimestamp: $selectedMultimeterTimestamp,
            highThreshold: viewModel.configuration.dcvHighAlarmEnabled
                ? viewModel.configuration.dcvHighAlarmValue
                : nil,
            lowThreshold: viewModel.configuration.dcvLowAlarmEnabled
                ? viewModel.configuration.dcvLowAlarmValue
                : nil,
            isHighLoad: viewModel.isUIRefreshHighLoad,
            isChartInspectorEnabled: viewModel.isChartInspectorEnabled,
            selectedChartRange: viewModel.selectedChartRange,
            palette: palette
        )
    }

    private var usbCChart: some View {
        MeasurementChartView(
            title: "USB-C Power Trend",
            color: palette.chartUsbC,
            samples: viewModel.displayedUsbCSamples,
            markers: [],
            reconnectMarkers: viewModel.displayedUsbCConnectionMarkers,
            selectedTimestamp: $selectedUsbCTimestamp,
            highThreshold: nil,
            lowThreshold: nil,
            isHighLoad: viewModel.isUIRefreshHighLoad,
            isChartInspectorEnabled: viewModel.isChartInspectorEnabled,
            selectedChartRange: viewModel.selectedChartRange,
            palette: palette
        )
    }
}
