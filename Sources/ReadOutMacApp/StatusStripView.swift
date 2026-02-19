import SwiftUI

struct StatusStripView: View {
    @ObservedObject var viewModel: DashboardViewModel
    let palette: DashboardPalette

    var body: some View {
        HStack(spacing: 10) {
            Label(viewModel.statusMessage, systemImage: "waveform.path.ecg")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)

            Spacer()

            Text(viewModel.configuration.useSimulator ? "Mode: Simulator" : "Mode: Hardware")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(palette.tertiaryText)

            Text("UI: \(viewModel.uiRefreshActualHzText)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.tertiaryText)
                .lineLimit(1)

            if viewModel.isDebugInfoVisible {
                Text(viewModel.uiRefreshRuntimeSummary)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.tertiaryText)
                    .lineLimit(1)

                if viewModel.isSessionCaptureActive || viewModel.sessionCaptureEventCount > 0 {
                    Text("Capture: \(viewModel.sessionCaptureEventCount)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(viewModel.isSessionCaptureActive ? .mint : palette.tertiaryText)
                        .lineLimit(1)
                }

                if viewModel.isSessionReplayActive {
                    Text("Replay active")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }

            if viewModel.alarmControlSummary != "Live" {
                Text("Alarm: \(viewModel.alarmControlSummary)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(viewModel.isAlarmSilenced ? .yellow : .mint)
                    .lineLimit(1)
            }

            if viewModel.isRenderPaused {
                Text("UI Paused")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.yellow)
            }

            Text("Ports: \(viewModel.availablePorts.count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(palette.tertiaryText)
        }
        .onChange(of: viewModel.isAlarmSilenced) { _, silenced in
            AccessibilityNotification.Announcement(silenced ? "Alarms silenced" : "Alarm silence ended").post()
        }
        .onChange(of: viewModel.isAlarmAcknowledged) { _, acked in
            AccessibilityNotification.Announcement(acked ? "Alarm acknowledged" : "Alarm acknowledge cleared").post()
        }
        .onChange(of: viewModel.isRenderPaused) { _, paused in
            AccessibilityNotification.Announcement(paused ? "UI paused" : "UI resumed").post()
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md, style: .continuous)
                        .stroke(.white.opacity(DesignSystem.Opacity.faint), lineWidth: 1)
                )
        )
    }
}
