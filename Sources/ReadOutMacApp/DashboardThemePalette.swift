import SwiftUI

struct DashboardPalette {
    let backgroundTop: Color
    let backgroundBottom: Color
    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color
    let chartMultimeter: Color
    let chartUsbC: Color
    let cardStrokeDefault: Color
    let divider: Color
}

enum DashboardThemePalette {
    static func palette(for theme: DashboardTheme) -> DashboardPalette {
        switch theme {
        case .system, .dark:
            return DashboardPalette(
                backgroundTop: Color(red: 0.07, green: 0.08, blue: 0.11),
                backgroundBottom: Color(red: 0.02, green: 0.03, blue: 0.05),
                primaryText: .white,
                secondaryText: .white.opacity(0.82),
                tertiaryText: .white.opacity(0.62),
                chartMultimeter: .mint,
                chartUsbC: .orange,
                cardStrokeDefault: .white.opacity(0.14),
                divider: .white.opacity(0.15)
            )
        case .light:
            return DashboardPalette(
                backgroundTop: Color(red: 0.90, green: 0.94, blue: 0.98),
                backgroundBottom: Color(red: 0.84, green: 0.90, blue: 0.96),
                primaryText: Color(red: 0.09, green: 0.11, blue: 0.14),
                secondaryText: Color(red: 0.15, green: 0.18, blue: 0.22),
                tertiaryText: Color(red: 0.26, green: 0.30, blue: 0.35),
                chartMultimeter: Color(red: 0.11, green: 0.58, blue: 0.48),
                chartUsbC: Color(red: 0.86, green: 0.46, blue: 0.15),
                cardStrokeDefault: .black.opacity(0.12),
                divider: .black.opacity(0.14)
            )
        }
    }
}

extension DashboardTheme {
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}
