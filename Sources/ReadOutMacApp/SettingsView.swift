import SwiftUI
import ReadOutPersistence
#if canImport(AppKit)
import AppKit
#endif

struct SettingsView: View {
    @Binding var configuration: AppConfiguration

    let availablePorts: [String]
    let onRefreshPorts: () -> Void
    let onOpenSetupWizard: () -> Void
    let onCancel: () -> Void
    let onSave: () -> Void

    private var validation: AppConfigurationValidationResult {
        AppConfigurationValidator.validate(configuration)
    }

    private var hasBlockingErrors: Bool {
        validation.hasErrors
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Form {
                deviceSection(
                    title: "Multimeter",
                    enabled: $configuration.multimeterEnabled,
                    port: $configuration.multimeterPort,
                    autoReconnect: $configuration.multimeterAutoReconnect,
                    outputPath: $configuration.multimeterOutputFile,
                    outputMode: $configuration.multimeterObsOutputMode,
                    customTemplate: $configuration.multimeterObsCustomTemplate,
                    valueLabel: $configuration.multimeterValueLabel,
                    csvEnabled: $configuration.multimeterCsvLoggingEnabled,
                    csvPath: $configuration.multimeterCsvLogFilePath,
                    outputSuggestedFileName: "multimeter_output.txt",
                    csvSuggestedFileName: "multimeter_log.csv"
                )

                deviceSection(
                    title: "USB-C Meter",
                    enabled: $configuration.usbcEnabled,
                    port: $configuration.usbcPort,
                    autoReconnect: $configuration.usbcAutoReconnect,
                    outputPath: $configuration.usbcOutputFile,
                    outputMode: $configuration.usbcObsOutputMode,
                    customTemplate: $configuration.usbcObsCustomTemplate,
                    valueLabel: $configuration.usbcValueLabel,
                    csvEnabled: $configuration.usbcCsvLoggingEnabled,
                    csvPath: $configuration.usbcCsvLogFilePath,
                    outputSuggestedFileName: "usbc_output.txt",
                    csvSuggestedFileName: "usbc_log.csv"
                )

                Section("Sampling") {
                    Stepper(value: $configuration.sampleRateHz, in: 1...50) {
                        Text("Sample rate: \(configuration.sampleRateHz) Hz")
                    }
                    Stepper(value: $configuration.graphHistorySeconds, in: 5...600) {
                        Text("Graph history: \(configuration.graphHistorySeconds) s")
                    }
                }

                Section("Alarms & Beep") {
                    HStack {
                        Text("SHORT threshold")
                        Spacer()
                        TextField("Threshold", value: $configuration.shortThreshold, format: .number.precision(.fractionLength(1...3)))
                            .frame(width: 90)
                            .textFieldStyle(.roundedBorder)
                        Text("Ohm")
                    }

                    Toggle("Enable meter beeper for SHORT", isOn: $configuration.beepOnShortMeter)
                    Toggle("Enable Mac beeper for SHORT", isOn: $configuration.beepOnShortPC)
                    Toggle("Enable Mac beeper for DC voltage alarms", isOn: $configuration.beepOnAlarm)

                    Picker("Mac alert sound", selection: $configuration.pcBeepSoundPreset) {
                        ForEach(AppConfiguration.MacAlertSoundPreset.allCases, id: \.self) { preset in
                            Text(soundPresetTitle(preset)).tag(preset)
                        }
                    }

                    HStack {
                        Text("Mac alert volume")
                        Slider(value: $configuration.pcBeepVolume, in: 0...1)
                        Text(configuration.pcBeepVolume, format: .number.precision(.fractionLength(2)))
                            .frame(width: 44, alignment: .trailing)
                            .foregroundStyle(.secondary)
                    }

                    Toggle("High DC voltage alarm", isOn: $configuration.dcvHighAlarmEnabled)
                    if configuration.dcvHighAlarmEnabled {
                        HStack {
                            Text("High threshold")
                            Spacer()
                            TextField("High", value: $configuration.dcvHighAlarmValue, format: .number.precision(.fractionLength(1...3)))
                                .frame(width: 90)
                                .textFieldStyle(.roundedBorder)
                            Text("V")
                        }
                    }

                    Toggle("Low DC voltage alarm", isOn: $configuration.dcvLowAlarmEnabled)
                    if configuration.dcvLowAlarmEnabled {
                        HStack {
                            Text("Low threshold")
                            Spacer()
                            TextField("Low", value: $configuration.dcvLowAlarmValue, format: .number.precision(.fractionLength(1...3)))
                                .frame(width: 90)
                                .textFieldStyle(.roundedBorder)
                            Text("V")
                        }
                    }
                }

                Section("Runtime") {
                    Toggle("Use simulator", isOn: $configuration.useSimulator)
                    Text("When enabled, app uses internal simulated ports SIM_MULTIMETER and SIM_USBC.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Capture runtime INFO logs", isOn: $configuration.runtimeLogCaptureEnabled)
                    Toggle("Show runtime log panel by default", isOn: $configuration.runtimeLogPanelVisible)

                    Stepper(value: $configuration.outputQueueCapacity, in: 8...2048, step: 8) {
                        Text("Output queue capacity: \(configuration.outputQueueCapacity)")
                    }
                    Stepper(value: $configuration.outputQueueMaxRetryAttempts, in: 0...10) {
                        Text("Output retries: \(configuration.outputQueueMaxRetryAttempts)")
                    }
                }

                Section("Appearance") {
                    Picker("Theme", selection: $configuration.dashboardTheme) {
                        ForEach(AppConfiguration.DashboardTheme.allCases, id: \.self) { theme in
                            Text(themeTitle(theme)).tag(theme)
                        }
                    }

                    Picker("Default dashboard layout", selection: $configuration.dashboardDeviceVisibility) {
                        ForEach(AppConfiguration.DashboardDeviceVisibility.allCases, id: \.self) { visibility in
                            Text(layoutTitle(visibility)).tag(visibility)
                        }
                    }
                }

                validationSection
            }
            .formStyle(.grouped)

            footer
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("readOut Settings")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Configure ports, reconnect policy, output sinks and alarms")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Refresh Ports") {
                onRefreshPorts()
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private var validationSection: some View {
        Section("Validation") {
            if validation.issues.isEmpty {
                Label("Configuration looks good.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            } else {
                ForEach(validation.issues) { issue in
                    Label(issue.message, systemImage: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(issue.severity == .error ? .red : .orange)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel") {
                onCancel()
            }
            .buttonStyle(.bordered)

            Button("Setup Wizard") {
                onOpenSetupWizard()
            }
            .buttonStyle(.bordered)

            Spacer()

            Button("Save") {
                onSave()
            }
            .buttonStyle(.borderedProminent)
            .disabled(hasBlockingErrors)
        }
        .padding(16)
        .background(.quaternary.opacity(0.15))
    }

    private func deviceSection(
        title: String,
        enabled: Binding<Bool>,
        port: Binding<String>,
        autoReconnect: Binding<Bool>,
        outputPath: Binding<String>,
        outputMode: Binding<AppConfiguration.ObsOutputMode>,
        customTemplate: Binding<String>,
        valueLabel: Binding<String>,
        csvEnabled: Binding<Bool>,
        csvPath: Binding<String>,
        outputSuggestedFileName: String,
        csvSuggestedFileName: String
    ) -> some View {
        Section(title) {
            Toggle("Enabled", isOn: enabled)
            Toggle("Auto reconnect", isOn: autoReconnect)

            HStack {
                TextField("Serial port (e.g. /dev/cu.usbserial-0001)", text: port)
                    .textFieldStyle(.roundedBorder)
                    .disabled(configuration.useSimulator)

                Button("Clear") {
                    port.wrappedValue = ""
                }
                .buttonStyle(.bordered)
                .disabled(configuration.useSimulator)
            }

            if configuration.useSimulator {
                Text("Simulator mode forces SIM ports and ignores hardware port fields.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !availablePorts.isEmpty {
                Menu("Use detected port") {
                    ForEach(availablePorts, id: \.self) { detectedPort in
                        Button(detectedPort) {
                            port.wrappedValue = detectedPort
                        }
                    }
                }
                .disabled(configuration.useSimulator)
            }

            Divider()

            pathField(
                title: "OBS output file",
                text: outputPath,
                suggestedFileName: outputSuggestedFileName
            )

            Picker("OBS output mode", selection: outputMode) {
                Text("Value only").tag(AppConfiguration.ObsOutputMode.valueOnly)
                Text("Value + unit").tag(AppConfiguration.ObsOutputMode.valueAndUnit)
                Text("Custom template").tag(AppConfiguration.ObsOutputMode.customTemplate)
            }
            .pickerStyle(.segmented)

            if outputMode.wrappedValue == .customTemplate {
                TextField("Custom template", text: customTemplate)
                    .textFieldStyle(.roundedBorder)
            }

            TextField("Value label", text: valueLabel)
                .textFieldStyle(.roundedBorder)

            Toggle("CSV logging", isOn: csvEnabled)
            if csvEnabled.wrappedValue {
                pathField(
                    title: "CSV log file",
                    text: csvPath,
                    suggestedFileName: csvSuggestedFileName
                )
            }
        }
    }

    private func pathField(
        title: String,
        text: Binding<String>,
        suggestedFileName: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                TextField(title, text: text)
                    .textFieldStyle(.roundedBorder)

                Button("Browse") {
                    browseFilePath(text, suggestedFileName: suggestedFileName)
                }
                .buttonStyle(.bordered)

                Button("Clear") {
                    text.wrappedValue = ""
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func browseFilePath(_ binding: Binding<String>, suggestedFileName: String) {
        #if canImport(AppKit)
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.title = "Choose output file"

        let currentPath = binding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !currentPath.isEmpty {
            let url = URL(fileURLWithPath: currentPath)
            panel.directoryURL = url.deletingLastPathComponent()
            panel.nameFieldStringValue = url.lastPathComponent
        } else {
            panel.nameFieldStringValue = suggestedFileName
        }

        if panel.runModal() == .OK, let selectedURL = panel.url {
            binding.wrappedValue = selectedURL.path
        }
        #endif
    }

    private func soundPresetTitle(_ preset: AppConfiguration.MacAlertSoundPreset) -> String {
        switch preset {
        case .system:
            return "System Beep"
        case .glass:
            return "Glass"
        case .sosumi:
            return "Sosumi"
        case .funk:
            return "Funk"
        }
    }

    private func themeTitle(_ theme: AppConfiguration.DashboardTheme) -> String {
        switch theme {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    private func layoutTitle(_ visibility: AppConfiguration.DashboardDeviceVisibility) -> String {
        switch visibility {
        case .both:
            return "Both devices"
        case .multimeter:
            return "Multimeter only"
        case .usbc:
            return "USB-C only"
        }
    }
}
