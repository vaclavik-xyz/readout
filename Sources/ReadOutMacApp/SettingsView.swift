import SwiftUI
import ReadOutPersistence

struct SettingsView: View {
    @Binding var configuration: AppConfiguration

    let availablePorts: [String]
    let onRefreshPorts: () -> Void
    let onCancel: () -> Void
    let onSave: () -> Void

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
                    csvPath: $configuration.multimeterCsvLogFilePath
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
                    csvPath: $configuration.usbcCsvLogFilePath
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
                        Text("Ω")
                    }

                    Toggle("Enable meter beeper for SHORT", isOn: $configuration.beepOnShortMeter)
                    Toggle("Enable Mac beeper for SHORT", isOn: $configuration.beepOnShortPC)
                    Toggle("Enable Mac beeper for DC voltage alarms", isOn: $configuration.beepOnAlarm)

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
                }
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
                Text("Configure ports, reconnect policy, and output sinks")
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

    private var footer: some View {
        HStack {
            Button("Cancel") {
                onCancel()
            }
            .buttonStyle(.bordered)

            Spacer()

            Button("Save") {
                onSave()
            }
            .buttonStyle(.borderedProminent)
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
        csvPath: Binding<String>
    ) -> some View {
        Section(title) {
            Toggle("Enabled", isOn: enabled)
            Toggle("Auto reconnect", isOn: autoReconnect)

            TextField("Serial port (e.g. /dev/cu.usbserial-0001)", text: port)
                .textFieldStyle(.roundedBorder)

            if !availablePorts.isEmpty {
                Menu("Use detected port") {
                    ForEach(availablePorts, id: \.self) { detectedPort in
                        Button(detectedPort) {
                            port.wrappedValue = detectedPort
                        }
                    }
                }
            }

            Divider()

            TextField("OBS output file path", text: outputPath)
                .textFieldStyle(.roundedBorder)

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
                TextField("CSV log file path", text: csvPath)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}
