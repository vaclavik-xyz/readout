import SwiftUI
import ReadOutCore

struct AlarmHistoryStripView: View {
    let markers: [AlarmTimelineMarker]
    let deviceVisibility: DashboardDeviceVisibility
    let palette: DashboardPalette

    var body: some View {
        if deviceVisibility == .usbc || markers.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(markers.suffix(12)) { marker in
                        HStack(spacing: 6) {
                            Text(marker.timestamp, format: .dateTime.hour().minute().second())
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.6))

                            Text(DashboardUIHelpers.alarmMarkerLabel(marker.state))
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundStyle(.black.opacity(DesignSystem.Opacity.strong))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(DashboardUIHelpers.alarmMarkerColor(marker.state), in: Capsule())
                        }
                        .accessibilityElement(children: .combine)
                        .padding(.horizontal, DesignSystem.Spacing.sm)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm, style: .continuous))
                    }
                }
            }
        }
    }
}
