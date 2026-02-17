import SwiftUI
import Charts
import ReadOutCore
#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
#endif

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
                header
                statusStrip
                cards
                alarmHistoryStrip
                charts
                if viewModel.isRuntimeLogPanelVisible {
                    runtimeLogPanel
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

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("readOut")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.primaryText)
                Text("Realtime measurements for Multimeter + USB-C power meter")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.secondaryText)
            }
            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    Picker("", selection: Binding(
                        get: { viewModel.deviceVisibility },
                        set: { viewModel.setDeviceVisibility($0) }
                    )) {
                        ForEach(DashboardDeviceVisibility.allCases) { visibility in
                            Text(visibility.title).tag(visibility)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)

                    Button(viewModel.isRenderPaused ? "Resume UI" : "Pause UI") {
                        viewModel.toggleRenderPause()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(viewModel.isRenderPaused ? .green : .yellow)

                    Button(viewModel.isRuntimeActive ? "Disconnect" : "Connect") {
                        if viewModel.isRuntimeActive {
                            viewModel.disconnectAll()
                        } else {
                            viewModel.connectAll()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(viewModel.isRuntimeActive ? .red : .blue)
                    .disabled(viewModel.isRecoveryInProgress || (!viewModel.isRuntimeActive && !viewModel.canConnectAll))
                }

                HStack(spacing: 8) {
                    Button(viewModel.isDashboardBeepEnabled ? "Beep On" : "Beep Off") {
                        viewModel.toggleDashboardBeep()
                    }
                    .buttonStyle(.bordered)

                    Button(viewModel.isRuntimeLogPanelVisible ? "Hide Logs" : "Show Logs") {
                        viewModel.toggleRuntimeLogPanelVisibility()
                    }
                    .buttonStyle(.bordered)

                    Button("Settings") { viewModel.openSettings() }
                        .buttonStyle(.bordered)

                    Menu("More") {
                        Button("Pop-out Multimeter") {
                            popoutManager.show(.multimeter, viewModel: viewModel)
                        }
                        Button("Pop-out USB-C") {
                            popoutManager.show(.usbc, viewModel: viewModel)
                        }
                        Button("Close Multimeter Pop-out") {
                            popoutManager.close(.multimeter)
                        }
                        Button("Close USB-C Pop-out") {
                            popoutManager.close(.usbc)
                        }
                        Divider()
                        Button("Refresh Ports") { viewModel.refreshPorts() }
                        Button("Restart Runtime") { viewModel.restartRuntime() }
                            .disabled(viewModel.isRecoveryInProgress)
                        Divider()
                        Button("Clear Charts") { viewModel.clearCharts() }
                        Button("Reset Alert") { viewModel.resetVisualState() }
                        Button("Clear Logs") { viewModel.clearRuntimeLogs() }
                        Divider()
                        Button("Export Logs") { exportLogs() }
                        Button("Export Diagnostics") { exportDiagnostics() }
                    }
                    .menuStyle(.borderlessButton)
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var statusStrip: some View {
        HStack(spacing: 10) {
            Label(viewModel.statusMessage, systemImage: "waveform.path.ecg")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)

            Spacer()

            Text(viewModel.configuration.useSimulator ? "Mode: Simulator" : "Mode: Hardware")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(palette.tertiaryText)

            Text(viewModel.uiRefreshRuntimeSummary)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.tertiaryText)
                .lineLimit(1)

            if viewModel.isRenderPaused {
                Text("UI Paused")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.yellow)
            }

            Text("Ports: \(viewModel.availablePorts.count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(palette.tertiaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
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
        deviceCard(
            title: "Multimeter",
            status: viewModel.multimeterStatus,
            primary: viewModel.multimeterPrimary,
            secondary: viewModel.multimeterSecondary,
            footerLeft: viewModel.multimeterMode,
            footerRight: "Alert: \(viewModel.multimeterAlert)",
            alertState: viewModel.multimeterAlertState
        )
    }

    private var usbCCard: some View {
        deviceCard(
            title: "USB-C Meter",
            status: viewModel.usbcStatus,
            primary: viewModel.usbcVoltage,
            secondary: viewModel.usbcCurrent,
            footerLeft: viewModel.usbcPower,
            footerRight: viewModel.usbcEnergy,
            alertState: nil
        )
    }

    private var charts: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Chart Range")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.secondaryText)

                Picker("", selection: $viewModel.selectedChartRange) {
                    ForEach(ChartRangePreset.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)

                Spacer()

                Text("MM: \(viewModel.displayedMultimeterSamples.count) pts | USB-C: \(viewModel.displayedUsbCSamples.count) pts")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.tertiaryText)
            }

#if DEBUG
            Text(viewModel.chartPerformanceSummary)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.tertiaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
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
        chartCard(
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
                : nil
        )
    }

    private var usbCChart: some View {
        chartCard(
            title: "USB-C Power Trend",
            color: palette.chartUsbC,
            samples: viewModel.displayedUsbCSamples,
            markers: [],
            reconnectMarkers: viewModel.displayedUsbCConnectionMarkers,
            selectedTimestamp: $selectedUsbCTimestamp,
            highThreshold: nil,
            lowThreshold: nil
        )
    }

    private var alarmHistoryStrip: some View {
        Group {
            if viewModel.deviceVisibility == .usbc || viewModel.displayedAlarmMarkers.isEmpty {
                EmptyView()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.displayedAlarmMarkers.suffix(12)) { marker in
                            HStack(spacing: 6) {
                                Text(marker.timestamp, format: .dateTime.hour().minute().second())
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.6))

                                Text(alarmMarkerLabel(marker.state))
                                    .font(.system(size: 10, weight: .black, design: .rounded))
                                    .foregroundStyle(.black.opacity(0.82))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(alarmMarkerColor(marker.state), in: Capsule())
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    private var runtimeLogPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Runtime Log")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.primaryText)
                Spacer()
                Text(viewModel.isRuntimeLogCaptureEnabled ? "capture:on" : "capture:warn+err")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(viewModel.isRuntimeLogCaptureEnabled ? .mint : .yellow)
                Text("\(viewModel.runtimeLogs.count) entries")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.tertiaryText)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.runtimeLogs.suffix(80)) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(palette.tertiaryText)

                            Text(entry.level.rawValue)
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundStyle(.black.opacity(0.85))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(logLevelColor(entry.level), in: Capsule())

                            Text(entry.message)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(palette.secondaryText)

                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 140, maxHeight: 180, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private func deviceCard(
        title: String,
        status: DeviceUIState,
        primary: String,
        secondary: String,
        footerLeft: String,
        footerRight: String,
        alertState: MeasurementAlertState?
    ) -> some View {
        let accent = alertAccentColor(alertState)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.primaryText)
                Spacer()
                statusPill(status)
                if let alertState, alertState != .none {
                    alertPill(alertState)
                }
            }
            Text(primary)
                .font(.system(size: 44, weight: .black, design: .rounded))
                .foregroundStyle(palette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(secondary)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.secondaryText)
            Divider().overlay(palette.divider)
            HStack {
                Text(footerLeft)
                Spacer()
                Text(footerRight)
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(palette.secondaryText)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(accent.opacity(0.9), lineWidth: 1.5)
                )
        )
    }

    private func chartCard(
        title: String,
        color: Color,
        samples: [ChartSample],
        markers: [AlarmTimelineMarker],
        reconnectMarkers: [ConnectionOverlayMarker],
        selectedTimestamp: Binding<Date?>,
        highThreshold: Double?,
        lowThreshold: Double?
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(palette.primaryText)

            Chart(samples) { sample in
                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Value", sample.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                AreaMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Value", sample.value)
                )
                .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [color.opacity(0.35), color.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                    )
                )

                if let highThreshold {
                    RuleMark(y: .value("High Alarm", highThreshold))
                        .foregroundStyle(.red.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [6, 4]))
                }

                if let lowThreshold {
                    RuleMark(y: .value("Low Alarm", lowThreshold))
                        .foregroundStyle(.yellow.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [6, 4]))
                }

                ForEach(markers) { marker in
                    RuleMark(x: .value("Alarm", marker.timestamp))
                        .foregroundStyle(alarmMarkerColor(marker.state).opacity(0.9))
                        .lineStyle(StrokeStyle(lineWidth: 1.0, dash: [3, 3]))
                        .annotation(position: .top, alignment: .leading) {
                            if markers.count <= 8 {
                                Text(alarmMarkerLabel(marker.state))
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundStyle(alarmMarkerColor(marker.state))
                            }
                        }
                }

                ForEach(reconnectMarkers) { marker in
                    RuleMark(x: .value("Connection Event", marker.timestamp))
                        .foregroundStyle(connectionOverlayColor(marker.state).opacity(0.85))
                        .lineStyle(StrokeStyle(lineWidth: 1.0, dash: [2, 4]))
                        .annotation(position: .top, alignment: .trailing) {
                            if reconnectMarkers.count <= 8 {
                                Text(connectionOverlayLabel(marker.state))
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundStyle(connectionOverlayColor(marker.state))
                            }
                        }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis(.hidden)
            .chartXSelection(value: selectedTimestamp)

            if let selectedTimestamp = selectedTimestamp.wrappedValue {
                chartSelectionDetails(
                    selectedTimestamp: selectedTimestamp,
                    markers: markers,
                    reconnectMarkers: reconnectMarkers
                )
            } else if !markers.isEmpty || !reconnectMarkers.isEmpty {
                Text("Hover or drag across the chart for marker details")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.tertiaryText)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 260)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(palette.cardStrokeDefault, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func chartSelectionDetails(
        selectedTimestamp: Date,
        markers: [AlarmTimelineMarker],
        reconnectMarkers: [ConnectionOverlayMarker]
    ) -> some View {
        let maxDistance = selectionDistanceSeconds()
        let nearestAlarm = ChartMarkerSelectionService.nearestAlarmMarker(
            to: selectedTimestamp,
            markers: markers,
            maxDistanceSeconds: maxDistance
        )
        let nearestConnection = ChartMarkerSelectionService.nearestConnectionMarker(
            to: selectedTimestamp,
            markers: reconnectMarkers,
            maxDistanceSeconds: maxDistance
        )

        HStack(spacing: 8) {
            Text(selectedTimestamp, format: .dateTime.hour().minute().second())
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))

            if let nearestAlarm {
                markerBadge(
                    title: alarmMarkerLabel(nearestAlarm.state),
                    detail: nearestAlarm.message,
                    color: alarmMarkerColor(nearestAlarm.state)
                )
            }

            if let nearestConnection {
                markerBadge(
                    title: connectionOverlayLabel(nearestConnection.state),
                    detail: nearestConnection.message,
                    color: connectionOverlayColor(nearestConnection.state)
                )
            }

            if nearestAlarm == nil, nearestConnection == nil {
                Text("No marker near cursor")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private func markerBadge(title: String, detail: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundStyle(.black.opacity(0.85))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(color, in: Capsule())

            Text(detail)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        }
    }

    private func selectionDistanceSeconds() -> TimeInterval {
        switch viewModel.selectedChartRange {
        case .thirtySeconds:
            return 2.5
        case .twoMinutes:
            return 8
        case .tenMinutes:
            return 20
        case .full:
            return 60
        }
    }

    private func exportLogs() {
        #if canImport(AppKit)
        let panel = NSSavePanel()
        panel.title = "Export Runtime Logs"
        panel.nameFieldStringValue = "readout-runtime.log"
        let logType = UTType(filenameExtension: "log") ?? .plainText
        panel.allowedContentTypes = [logType, .plainText]
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.exportRuntimeLogs(to: url)
        }
        #endif
    }

    private func exportDiagnostics() {
        #if canImport(AppKit)
        let panel = NSSavePanel()
        panel.title = "Export Diagnostics Bundle"
        panel.nameFieldStringValue = "readout-diagnostics.zip"
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.exportDiagnosticsBundle(to: url)
        }
        #endif
    }

    private func statusPill(_ status: DeviceUIState) -> some View {
        let color: Color = switch status {
        case .connected: .green
        case .connecting: .yellow
        case .error: .red
        case .disconnected: .gray
        }

        return Text(status.rawValue.capitalized)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.black.opacity(0.8))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color, in: Capsule())
    }

    private func alertAccentColor(_ alertState: MeasurementAlertState?) -> Color {
        guard let alertState else {
            return palette.cardStrokeDefault
        }

        switch alertState {
        case .none:
            return palette.cardStrokeDefault
        case .short:
            return .orange
        case .open:
            return .pink
        case .highAlarm:
            return .red
        case .lowAlarm:
            return .yellow
        }
    }

    private func alertPill(_ alertState: MeasurementAlertState) -> some View {
        Text(DashboardAlertService.text(for: alertState))
            .font(.system(size: 10, weight: .black, design: .rounded))
            .foregroundStyle(.black.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(alertAccentColor(alertState), in: Capsule())
    }

    private func logLevelColor(_ level: RuntimeLogLevel) -> Color {
        switch level {
        case .info:
            return .mint
        case .warning:
            return .yellow
        case .error:
            return .red
        }
    }

    private func alarmMarkerLabel(_ state: MeasurementAlertState) -> String {
        switch state {
        case .none:
            return "NONE"
        case .short:
            return "SHORT"
        case .open:
            return "OPEN"
        case .highAlarm:
            return "HIGH"
        case .lowAlarm:
            return "LOW"
        }
    }

    private func alarmMarkerColor(_ state: MeasurementAlertState) -> Color {
        switch state {
        case .none:
            return .gray
        case .short:
            return .orange
        case .open:
            return .pink
        case .highAlarm:
            return .red
        case .lowAlarm:
            return .yellow
        }
    }

    private func connectionOverlayLabel(_ state: ConnectionOverlayState) -> String {
        switch state {
        case .reconnecting:
            return "RETRY"
        case .error:
            return "ERROR"
        case .restored:
            return "RESTORED"
        }
    }

    private func connectionOverlayColor(_ state: ConnectionOverlayState) -> Color {
        switch state {
        case .reconnecting:
            return .cyan
        case .error:
            return .red
        case .restored:
            return .green
        }
    }
}
