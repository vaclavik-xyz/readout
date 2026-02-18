import Foundation
import SwiftUI
import Testing
@testable import ReadOutMacApp

@Test
func darkPaletteReturnsWhitePrimaryText() {
    let palette = DashboardThemePalette.palette(for: .dark)
    #expect(palette.primaryText == .white)
}

@Test
func lightPaletteReturnsDarkPrimaryText() {
    let palette = DashboardThemePalette.palette(for: .light)
    #expect(palette.primaryText != .white)
}

@Test
func systemPaletteMatchesDark() {
    let system = DashboardThemePalette.palette(for: .system)
    let dark = DashboardThemePalette.palette(for: .dark)
    #expect(system.primaryText == dark.primaryText)
    #expect(system.backgroundTop == dark.backgroundTop)
    #expect(system.chartMultimeter == dark.chartMultimeter)
    #expect(system.chartUsbC == dark.chartUsbC)
}

@Test
func lightPaletteHasDistinctBackground() {
    let light = DashboardThemePalette.palette(for: .light)
    let dark = DashboardThemePalette.palette(for: .dark)
    #expect(light.backgroundTop != dark.backgroundTop)
    #expect(light.backgroundBottom != dark.backgroundBottom)
}

@Test
func preferredColorSchemeForDark() {
    #expect(DashboardTheme.dark.preferredColorScheme == .dark)
}

@Test
func preferredColorSchemeForLight() {
    #expect(DashboardTheme.light.preferredColorScheme == .light)
}

@Test
func preferredColorSchemeForSystemIsNil() {
    #expect(DashboardTheme.system.preferredColorScheme == nil)
}
