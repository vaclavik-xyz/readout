import SwiftUI

struct RuntimeLogPanelView: View {
    let logs: [RuntimeLogEntry]
    let isLogCaptureEnabled: Bool
    let palette: DashboardPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Runtime Log")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.primaryText)
                Spacer()
                Text(isLogCaptureEnabled ? "capture:on" : "capture:warn+err")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(isLogCaptureEnabled ? .mint : .yellow)
                Text("\(logs.count) entries")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.tertiaryText)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(logs.suffix(40)) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(palette.tertiaryText)

                            Text(entry.level.rawValue)
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundStyle(.black.opacity(0.85))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(DashboardUIHelpers.logLevelColor(entry.level), in: Capsule())

                            Text(entry.message)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(palette.secondaryText)

                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 140, maxHeight: 180, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
        )
    }
}
