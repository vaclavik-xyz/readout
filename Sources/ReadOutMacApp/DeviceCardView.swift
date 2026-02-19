import SwiftUI
import ReadOutCore

struct DeviceCardView: View {
    let title: String
    let status: DeviceUIState
    let primary: String
    let secondary: String
    let footerLeft: String
    let footerRight: String
    let alertState: MeasurementAlertState?
    let palette: DashboardPalette

    @State private var connectingPulse = false

    var body: some View {
        let accent = DashboardUIHelpers.alertAccentColor(alertState, defaultColor: palette.cardStrokeDefault)

        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                Text(title)
                    .font(.system(size: DesignSystem.Spacing.lg, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.primaryText)
                Spacer()
                statusPill(status)
                    .opacity(status == .connecting ? (connectingPulse ? 0.4 : 1.0) : 1.0)
                if let alertState, alertState != .none {
                    alertPill(alertState)
                }
            }
            if status == .connected {
                connectedContent
            } else {
                stateOverlay
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xl, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xl, style: .continuous)
                        .stroke(accent.opacity(DesignSystem.Opacity.full), lineWidth: 1.5)
                )
        )
        .onChange(of: status) {
            if status == .connecting {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    connectingPulse = true
                }
            } else {
                withAnimation(.default) {
                    connectingPulse = false
                }
            }
        }
        .onAppear {
            if status == .connecting {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    connectingPulse = true
                }
            }
        }
    }

    private var connectedContent: some View {
        Group {
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
    }

    @ViewBuilder
    private var stateOverlay: some View {
        switch status {
        case .disconnected:
            VStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "cable.connector")
                    .font(.system(size: 28))
                    .foregroundStyle(palette.secondaryText.opacity(DesignSystem.Opacity.medium))
                Text("Not connected")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.secondaryText.opacity(DesignSystem.Opacity.medium))
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        case .connecting:
            VStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 28))
                    .foregroundStyle(.yellow.opacity(0.7))
                Text("Connecting...")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.yellow.opacity(0.7))
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        case .error:
            VStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.red.opacity(0.8))
                Text("Connection error")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.red.opacity(0.8))
                Text("Check device and retry")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(palette.secondaryText.opacity(DesignSystem.Opacity.medium))
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        case .connected:
            EmptyView()
        }
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

    private func alertPill(_ alertState: MeasurementAlertState) -> some View {
        Text(DashboardAlertService.text(for: alertState))
            .font(.system(size: 10, weight: .black, design: .rounded))
            .foregroundStyle(.black.opacity(0.85))
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, DesignSystem.Spacing.xs)
            .background(DashboardUIHelpers.alertAccentColor(alertState, defaultColor: palette.cardStrokeDefault), in: Capsule())
    }
}
