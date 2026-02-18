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

    var body: some View {
        let accent = DashboardUIHelpers.alertAccentColor(alertState, defaultColor: palette.cardStrokeDefault)

        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                Text(title)
                    .font(.system(size: DesignSystem.Spacing.lg, weight: .bold, design: .rounded))
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
