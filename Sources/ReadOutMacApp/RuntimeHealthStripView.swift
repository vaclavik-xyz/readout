import SwiftUI

struct RuntimeHealthStripView: View {
    let badges: [RuntimeHealthBadge]
    let palette: DashboardPalette

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(badges) { badge in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(DashboardUIHelpers.runtimeHealthColor(badge.severity))
                                .frame(width: 8, height: 8)
                            Text(badge.title)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(palette.secondaryText)
                        }
                        Text(badge.value)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(palette.tertiaryText)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(DashboardUIHelpers.runtimeHealthColor(badge.severity).opacity(0.35), lineWidth: 1)
                            )
                    )
                }
            }
        }
    }
}
