import SwiftUI
import ReadOutCore
import ReadOutPersistence
#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
#endif

struct DashboardHeaderView: View {
    @ObservedObject var viewModel: DashboardViewModel
    let palette: DashboardPalette
    let popoutManager: DevicePopoutManager
    @State private var isSavePopoutProfilePresented: Bool = false
    @State private var popoutProfileNameDraft: String = ""

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("readOut")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.primaryText)
                Text("Realtime measurements for Multimeter + USB-C power meter")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.secondaryText)
            }
            Spacer()

            VStack(alignment: .trailing, spacing: DesignSystem.Spacing.sm) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Picker("Device visibility", selection: Binding(
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
                    .accessibilityHint(viewModel.isRenderPaused ? "Resumes live UI updates" : "Pauses live UI updates")

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
                    .accessibilityHint(viewModel.isRuntimeActive ? "Stops device connections" : "Starts device connections")
                }

                HStack(spacing: DesignSystem.Spacing.sm) {
                    Button("Settings") { viewModel.openSettings() }
                        .buttonStyle(.bordered)

                    moreMenu
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg, style: .continuous))
        .sheet(isPresented: $isSavePopoutProfilePresented) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                Text("Save Pop-out Layout")
                    .font(.system(size: DesignSystem.Spacing.lg, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.primaryText)
                Text("Name this layout profile for quick restore.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.secondaryText)

                TextField("Layout name", text: $popoutProfileNameDraft)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Spacer()
                    Button("Cancel") {
                        isSavePopoutProfilePresented = false
                    }
                    Button("Save") {
                        viewModel.saveCurrentPopoutLayoutProfile(named: popoutProfileNameDraft)
                        isSavePopoutProfilePresented = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(DesignSystem.Spacing.lg)
            .frame(minWidth: 360)
        }
    }

    private var moreMenu: some View {
        Menu("More") {
            Menu("Runtime Controls") {
                Menu("Alarm") {
                    Button(viewModel.isAlarmAcknowledged ? "Clear Acknowledge" : "Acknowledge Active Alarm") {
                        viewModel.toggleAlarmAcknowledge()
                    }
                    .disabled(!viewModel.hasActiveAlarm && !viewModel.isAlarmAcknowledged)

                    Divider()

                    ForEach(AlarmSilencePreset.allCases) { preset in
                        Button(preset.title) {
                            viewModel.silenceAlarms(using: preset)
                        }
                    }

                    if viewModel.isAlarmSilenced {
                        Divider()
                        Button("Unsilence") {
                            viewModel.clearAlarmSilence()
                        }
                    }
                }

                Button(viewModel.isDashboardBeepEnabled ? "Beep On" : "Beep Off") {
                    viewModel.toggleDashboardBeep()
                }

                Button(viewModel.isRuntimeLogPanelVisible ? "Hide Logs" : "Show Logs") {
                    viewModel.toggleRuntimeLogPanelVisibility()
                }
            }

            Divider()

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
            Menu("Pop-out Layout Profiles") {
                Button("Save Current Layout...") {
                    popoutProfileNameDraft = viewModel.suggestedPopoutLayoutProfileName()
                    isSavePopoutProfilePresented = true
                }

                if viewModel.hasPopoutLayoutProfiles {
                    Divider()
                    ForEach(viewModel.popoutLayoutProfiles, id: \.name) { profile in
                        Button {
                            if viewModel.applyPopoutLayoutProfile(named: profile.name) {
                                popoutManager.syncOpenWindowsFromViewModel(viewModel)
                            }
                        } label: {
                            if viewModel.isActivePopoutLayoutProfile(profile.name) {
                                Label("Apply \(profile.name)", systemImage: "checkmark")
                            } else {
                                Text("Apply \(profile.name)")
                            }
                        }
                    }
                    Divider()
                    Menu("Delete Profile") {
                        ForEach(viewModel.popoutLayoutProfiles, id: \.name) { profile in
                            Button("Delete \(profile.name)") {
                                viewModel.deletePopoutLayoutProfile(named: profile.name)
                            }
                        }
                    }
                } else {
                    Text("No saved profiles")
                }
            }
            Menu("Multimeter Pop-out Mode") {
                ForEach(DevicePopoutDisplayMode.allCases) { mode in
                    Button {
                        viewModel.setPopoutMode(mode, for: .multimeter)
                    } label: {
                        if mode == viewModel.multimeterPopoutMode {
                            Label(mode.title, systemImage: "checkmark")
                        } else {
                            Text(mode.title)
                        }
                    }
                }
            }
            Menu("USB-C Pop-out Mode") {
                ForEach(DevicePopoutDisplayMode.allCases) { mode in
                    Button {
                        viewModel.setPopoutMode(mode, for: .usbc)
                    } label: {
                        if mode == viewModel.usbcPopoutMode {
                            Label(mode.title, systemImage: "checkmark")
                        } else {
                            Text(mode.title)
                        }
                    }
                }
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
            Divider()
            Menu("Debug Tools") {
                Button(viewModel.isDebugInfoVisible ? "Hide Debug Info" : "Show Debug Info") {
                    viewModel.toggleDebugInfoVisibility()
                }

                Button(viewModel.isChartInspectorEnabled ? "Disable Chart Cursor" : "Enable Chart Cursor") {
                    viewModel.toggleChartInspector()
                }

                Divider()

                Button(viewModel.isSessionCaptureActive ? "Stop Session Capture" : "Start Session Capture") {
                    if viewModel.isSessionCaptureActive {
                        viewModel.stopRuntimeSessionCapture()
                    } else {
                        viewModel.startRuntimeSessionCapture()
                    }
                }
                Button("Export Session Capture") { exportSessionCapture() }
                    .disabled(viewModel.sessionCaptureEventCount == 0)
                Button(viewModel.isSessionReplayActive ? "Stop Session Replay" : "Replay Session Capture") {
                    if viewModel.isSessionReplayActive {
                        viewModel.stopRuntimeSessionReplay()
                    } else {
                        replaySessionCapture()
                    }
                }
            }
        }
        .menuStyle(.borderlessButton)
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

    private func exportSessionCapture() {
        #if canImport(AppKit)
        let panel = NSSavePanel()
        panel.title = "Export Session Capture"
        panel.nameFieldStringValue = "readout-session-capture.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.exportRuntimeSessionCapture(to: url)
        }
        #endif
    }

    private func replaySessionCapture() {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.title = "Replay Session Capture"
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.replayRuntimeSession(from: url)
        }
        #endif
    }
}
