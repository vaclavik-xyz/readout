import SwiftUI
import Charts
import ReadOutCore
#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
#endif

struct ContentView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.08, blue: 0.11),
                    Color(red: 0.02, green: 0.03, blue: 0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                header
                statusStrip
                cards
                charts
                runtimeLogPanel
            }
            .padding(20)
        }
        .sheet(isPresented: $viewModel.isSettingsPresented) {
            SettingsView(
                configuration: $viewModel.editableConfiguration,
                availablePorts: viewModel.availablePorts,
                onRefreshPorts: { viewModel.refreshPorts() },
                onCancel: { viewModel.cancelSettings() },
                onSave: { viewModel.saveSettings() }
            )
            .frame(minWidth: 760, minHeight: 620)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("readOut")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("Realtime measurements for Multimeter + USB-C power meter")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()

            HStack(spacing: 8) {
                Button("Refresh Ports") { viewModel.refreshPorts() }
                    .buttonStyle(.bordered)

                Button("Settings") { viewModel.openSettings() }
                    .buttonStyle(.bordered)

                Button("Clear Charts") { viewModel.clearCharts() }
                    .buttonStyle(.bordered)

                Button("Reset Alert") { viewModel.resetVisualState() }
                    .buttonStyle(.bordered)

                Button("Clear Logs") { viewModel.clearRuntimeLogs() }
                    .buttonStyle(.bordered)

                Button("Export Logs") { exportLogs() }
                    .buttonStyle(.bordered)

                Button("Restart Runtime") { viewModel.restartRuntime() }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(viewModel.isRecoveryInProgress)

                if viewModel.isRuntimeActive {
                    Button("Disconnect") { viewModel.disconnectAll() }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(viewModel.isRecoveryInProgress)
                } else {
                    Button("Connect All") { viewModel.connectAll() }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isRecoveryInProgress)
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
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)

            Spacer()

            Text(viewModel.configuration.useSimulator ? "Mode: Simulator" : "Mode: Hardware")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))

            Text("Ports: \(viewModel.availablePorts.count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
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
        HStack(spacing: 14) {
            deviceCard(
                title: "Multimeter",
                status: viewModel.multimeterStatus,
                primary: viewModel.multimeterPrimary,
                secondary: viewModel.multimeterSecondary,
                footerLeft: viewModel.multimeterMode,
                footerRight: "Alert: \(viewModel.multimeterAlert)",
                alertState: viewModel.multimeterAlertState
            )

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
    }

    private var charts: some View {
        HStack(spacing: 14) {
            chartCard(
                title: "Multimeter Trend",
                color: .mint,
                samples: viewModel.multimeterSamples,
                highThreshold: viewModel.configuration.dcvHighAlarmEnabled
                    ? viewModel.configuration.dcvHighAlarmValue
                    : nil,
                lowThreshold: viewModel.configuration.dcvLowAlarmEnabled
                    ? viewModel.configuration.dcvLowAlarmValue
                    : nil
            )
            chartCard(
                title: "USB-C Power Trend",
                color: .orange,
                samples: viewModel.usbcSamples,
                highThreshold: nil,
                lowThreshold: nil
            )
        }
    }

    private var runtimeLogPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Runtime Log")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Text("\(viewModel.runtimeLogs.count) entries")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.runtimeLogs.suffix(80)) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.6))

                            Text(entry.level.rawValue)
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundStyle(.black.opacity(0.85))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(logLevelColor(entry.level), in: Capsule())

                            Text(entry.message)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.82))

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
                    .foregroundStyle(.white)
                Spacer()
                statusPill(status)
                if let alertState, alertState != .none {
                    alertPill(alertState)
                }
            }
            Text(primary)
                .font(.system(size: 44, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(secondary)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
            Divider().overlay(.white.opacity(0.15))
            HStack {
                Text(footerLeft)
                Spacer()
                Text(footerRight)
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.7))
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
        highThreshold: Double?,
        lowThreshold: Double?
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))

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
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis(.hidden)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 260)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                )
        )
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
            return .white.opacity(0.14)
        }

        switch alertState {
        case .none:
            return .white.opacity(0.14)
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
}
