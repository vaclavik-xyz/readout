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
                HStack(spacing: 8) {
                    ForEach(markers.suffix(12)) { marker in
                        HStack(spacing: 6) {
                            Text(marker.timestamp, format: .dateTime.hour().minute().second())
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.6))

                            Text(DashboardUIHelpers.alarmMarkerLabel(marker.state))
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundStyle(.black.opacity(0.82))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(DashboardUIHelpers.alarmMarkerColor(marker.state), in: Capsule())
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
