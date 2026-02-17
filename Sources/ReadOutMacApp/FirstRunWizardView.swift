import SwiftUI
import ReadOutPersistence
import ReadOutIO

struct FirstRunWizardView: View {
    @Binding var configuration: AppConfiguration

    let availablePorts: [String]
    let probeResult: PortProbeResult
    let blockingIssues: [String]
    let reason: String
    let canCancel: Bool
    let onRescan: () -> Void
    let onApplyRecommendations: () -> Void
    let onModeChanged: () -> Void
    let onConfigurationChanged: () -> Void
    let onCancel: () -> Void
    let onSave: () -> Void

    private var hardwarePorts: [String] {
        availablePorts.filter { $0 != SimulatedPort.multimeter && $0 != SimulatedPort.usbC }
    }

    private var validation: AppConfigurationValidationResult {
        AppConfigurationValidator.validate(configuration)
    }

    private var hasErrors: Bool {
        validation.hasErrors || !blockingIssues.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Form {
                Section("Mode") {
                    Picker("Device source", selection: $configuration.useSimulator) {
                        Text("Hardware").tag(false)
                        Text("Simulator").tag(true)
                    }
                    .pickerStyle(.segmented)

                    Text(configuration.useSimulator
                        ? "Simulator mode uses internal ports SIM_MULTIMETER and SIM_USBC."
                        : "Hardware mode requires detected serial ports for enabled devices.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Devices") {
                    Toggle("Enable Multimeter", isOn: $configuration.multimeterEnabled)
                    if configuration.multimeterEnabled {
                        portRow(
                            title: "Multimeter port",
                            port: $configuration.multimeterPort,
                            candidates: probeResult.multimeterCandidates
                        )
                    }

                    Toggle("Enable USB-C meter", isOn: $configuration.usbcEnabled)
                    if configuration.usbcEnabled {
                        portRow(
                            title: "USB-C port",
                            port: $configuration.usbcPort,
                            candidates: probeResult.usbcCandidates
                        )
                    }
                }

                Section("Port discovery") {
                    HStack {
                        Button("Re-scan ports") {
                            onRescan()
                        }
                        .buttonStyle(.bordered)

                        Button("Use recommended") {
                            onApplyRecommendations()
                        }
                        .buttonStyle(.borderedProminent)

                        Spacer()
                    }

                    if hardwarePorts.isEmpty {
                        Text("No hardware serial ports detected. You can continue in simulator mode.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Detected ports")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(hardwarePorts, id: \.self) { port in
                                Text(port)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                        }
                    }
                }

                Section("Validation") {
                    if blockingIssues.isEmpty, validation.issues.isEmpty {
                        Label("Configuration is ready.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        ForEach(blockingIssues, id: \.self) { issue in
                            Label(issue, systemImage: "xmark.octagon.fill")
                                .foregroundStyle(.red)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                        }

                        ForEach(validation.issues) { issue in
                            Label(
                                issue.message,
                                systemImage: issue.severity == .error
                                    ? "xmark.octagon.fill"
                                    : "exclamationmark.triangle.fill"
                            )
                            .foregroundStyle(issue.severity == .error ? .red : .orange)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .onChange(of: configuration.useSimulator) { _, _ in
                onModeChanged()
            }
            .onChange(of: configuration) { _, _ in
                onConfigurationChanged()
            }

            footer
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("First-run setup")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            Text(headerDescription(reason))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private var footer: some View {
        HStack {
            if canCancel {
                Button("Close") {
                    onCancel()
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button("Save setup") {
                onSave()
            }
            .buttonStyle(.borderedProminent)
            .disabled(hasErrors)
        }
        .padding(16)
        .background(.quaternary.opacity(0.15))
    }

    private func portRow(
        title: String,
        port: Binding<String>,
        candidates: [PortProbeCandidate]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                TextField("Serial port", text: port)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .disabled(configuration.useSimulator)

                Menu("Select") {
                    ForEach(candidates) { candidate in
                        Button(candidate.port) {
                            port.wrappedValue = candidate.port
                        }
                    }
                }
                .disabled(configuration.useSimulator || candidates.isEmpty)
            }

            if !candidates.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(candidates.prefix(3)) { candidate in
                        Text(candidateLabel(candidate))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func candidateLabel(_ candidate: PortProbeCandidate) -> String {
        let hints = candidate.matchedHints.isEmpty ? "no hints" : candidate.matchedHints.joined(separator: ", ")
        return "\(candidate.port)  | score \(candidate.score) | \(hints)"
    }

    private func headerDescription(_ reason: String) -> String {
        switch reason {
        case "missing_configuration":
            return "No existing configuration was found. Configure devices before first connect."
        case "invalid_configuration":
            return "Saved configuration is incomplete or invalid for current ports."
        case "connect_blocked":
            return "Connect was blocked due to missing or wrong ports. Fix setup to continue."
        case "load_failed":
            return "Configuration file failed to load. Review and save a new setup."
        case "manual_from_settings":
            return "Manual setup mode. You can review and update device source and port assignment."
        default:
            return "Review mode, ports, and validation before starting runtime."
        }
    }
}
