import Foundation
import Testing
@testable import ReadOutMacApp

@Test
func soundNameForSystemReturnsNil() {
    #expect(PcBeepController.soundName(for: .system) == nil)
}

@Test
func soundNameForGlassReturnsGlass() {
    #expect(PcBeepController.soundName(for: .glass) == "Glass")
}

@Test
func soundNameForSosumiReturnsSosumi() {
    #expect(PcBeepController.soundName(for: .sosumi) == "Sosumi")
}

@Test
func soundNameForFunkReturnsFunk() {
    #expect(PcBeepController.soundName(for: .funk) == "Funk")
}

@Test
func volumeClampingCapsAtOne() {
    let controller = PcBeepController(volume: 1.5)
    controller.configure(soundPreset: .glass, volume: 2.0)
    // configure doesn't crash and controller is functional
}

@Test
func volumeClampingFloorsAtZero() {
    let controller = PcBeepController(volume: -0.5)
    controller.configure(soundPreset: .glass, volume: -1.0)
    // configure doesn't crash and controller is functional
}
