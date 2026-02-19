import Foundation
import Testing
@testable import ReadOutMacApp
import ReadOutPersistence

@MainActor
@Suite
struct PopoutLayoutServiceTests {
    @Test
    func syncFromConfigurationSetsState() {
        let service = PopoutLayoutService()
        var config = AppConfiguration()
        config.multimeterPopoutMode = .mini
        config.usbcPopoutMode = .compact
        config.popoutLayoutProfiles = [
            AppConfiguration.PopoutLayoutProfile(
                name: "Test",
                multimeterMode: .mini,
                usbcMode: .compact,
                multimeterFrame: nil,
                usbcFrame: nil
            )
        ]
        config.activePopoutLayoutProfileName = "Test"

        service.syncFromConfiguration(config)

        #expect(service.multimeterPopoutMode == .mini)
        #expect(service.usbcPopoutMode == .compact)
        #expect(service.popoutLayoutProfiles.count == 1)
        #expect(service.activePopoutLayoutProfileName == "Test")
    }

    @Test
    func setPopoutModeUpdatesConfiguration() {
        let service = PopoutLayoutService()
        var config = AppConfiguration()

        let changed = service.setPopoutMode(.mini, for: .multimeter, configuration: &config)

        #expect(changed)
        #expect(service.multimeterPopoutMode == .mini)
        #expect(config.multimeterPopoutMode == .mini)
    }

    @Test
    func setPopoutModeIgnoresSameValue() {
        let service = PopoutLayoutService()
        var config = AppConfiguration()

        // Default is .detailed
        let changed = service.setPopoutMode(.detailed, for: .multimeter, configuration: &config)

        #expect(!changed)
    }

    @Test
    func saveAndApplyLayoutProfile() {
        let service = PopoutLayoutService()
        var config = AppConfiguration()

        // Set distinct modes
        service.setPopoutMode(.mini, for: .multimeter, configuration: &config)
        service.setPopoutMode(.compact, for: .usbc, configuration: &config)

        // Save profile
        let savedName = service.saveCurrentLayoutProfile(named: "Test", configuration: &config)
        #expect(savedName == "Test")
        #expect(service.activePopoutLayoutProfileName == "Test")

        // Change modes
        service.setPopoutMode(.detailed, for: .multimeter, configuration: &config)
        service.setPopoutMode(.detailed, for: .usbc, configuration: &config)
        #expect(service.multimeterPopoutMode == .detailed)

        // Apply saved profile
        let applied = service.applyLayoutProfile(named: "Test", configuration: &config)
        #expect(applied)
        #expect(service.multimeterPopoutMode == .mini)
        #expect(service.usbcPopoutMode == .compact)
    }

    @Test
    func deleteLayoutProfileClearsActive() {
        let service = PopoutLayoutService()
        var config = AppConfiguration()

        service.setPopoutMode(.mini, for: .multimeter, configuration: &config)
        _ = service.saveCurrentLayoutProfile(named: "ToDelete", configuration: &config)
        #expect(service.activePopoutLayoutProfileName == "ToDelete")

        service.deleteLayoutProfile(named: "ToDelete", configuration: &config)

        #expect(service.activePopoutLayoutProfileName.isEmpty)
        #expect(service.popoutLayoutProfiles.isEmpty)
    }

    @Test
    func suggestedProfileNameIncrements() {
        let service = PopoutLayoutService()
        var config = AppConfiguration()

        service.setPopoutMode(.mini, for: .multimeter, configuration: &config)
        _ = service.saveCurrentLayoutProfile(named: "Layout 1", configuration: &config)

        let suggested = service.suggestedPopoutLayoutProfileName()
        #expect(suggested == "Layout 2")
    }

    @Test
    func profileNameNormalization() {
        let service = PopoutLayoutService()
        var config = AppConfiguration()

        // Whitespace-only returns nil
        let empty = service.saveCurrentLayoutProfile(named: "   ", configuration: &config)
        #expect(empty == nil)

        // Long name is capped at 48 chars
        let longName = String(repeating: "A", count: 60)
        let saved = service.saveCurrentLayoutProfile(named: longName, configuration: &config)
        #expect(saved != nil)
        #expect(saved!.count == 48)
    }
}
