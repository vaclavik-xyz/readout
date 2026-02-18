import Foundation
import ReadOutPersistence

@MainActor
final class PopoutLayoutService: ObservableObject {
    @Published private(set) var multimeterPopoutMode: DevicePopoutDisplayMode = .detailed
    @Published private(set) var usbcPopoutMode: DevicePopoutDisplayMode = .detailed
    @Published private(set) var popoutLayoutProfiles: [AppConfiguration.PopoutLayoutProfile] = []
    @Published private(set) var activePopoutLayoutProfileName: String = ""

    var hasPopoutLayoutProfiles: Bool {
        !popoutLayoutProfiles.isEmpty
    }

    func isActivePopoutLayoutProfile(_ name: String) -> Bool {
        activePopoutLayoutProfileName == name
    }

    func suggestedPopoutLayoutProfileName() -> String {
        let existing = Set(popoutLayoutProfiles.map(\.name))
        var index = 1
        while existing.contains("Layout \(index)") {
            index += 1
        }
        return "Layout \(index)"
    }

    func syncFromConfiguration(_ config: AppConfiguration) {
        popoutLayoutProfiles = config.popoutLayoutProfiles
        if popoutLayoutProfiles.contains(where: { $0.name == config.activePopoutLayoutProfileName }) {
            activePopoutLayoutProfileName = config.activePopoutLayoutProfileName
        } else {
            activePopoutLayoutProfileName = ""
        }
        multimeterPopoutMode = DevicePopoutDisplayMode(configurationValue: config.multimeterPopoutMode)
        usbcPopoutMode = DevicePopoutDisplayMode(configurationValue: config.usbcPopoutMode)
    }

    func popoutMode(for kind: DevicePopoutKind) -> DevicePopoutDisplayMode {
        switch kind {
        case .multimeter:
            return multimeterPopoutMode
        case .usbc:
            return usbcPopoutMode
        }
    }

    @discardableResult
    func setPopoutMode(
        _ mode: DevicePopoutDisplayMode,
        for kind: DevicePopoutKind,
        configuration: inout AppConfiguration
    ) -> Bool {
        switch kind {
        case .multimeter:
            guard multimeterPopoutMode != mode else {
                return false
            }
            clearActiveLayoutProfile(configuration: &configuration)
            multimeterPopoutMode = mode
            configuration.multimeterPopoutMode = mode.configurationValue
        case .usbc:
            guard usbcPopoutMode != mode else {
                return false
            }
            clearActiveLayoutProfile(configuration: &configuration)
            usbcPopoutMode = mode
            configuration.usbcPopoutMode = mode.configurationValue
        }
        return true
    }

    @discardableResult
    func setPopoutFrame(
        _ frame: AppConfiguration.PopoutWindowFrame,
        for kind: DevicePopoutKind,
        configuration: inout AppConfiguration
    ) -> Bool {
        switch kind {
        case .multimeter:
            guard configuration.multimeterPopoutFrame != frame else {
                return false
            }
            clearActiveLayoutProfile(configuration: &configuration)
            configuration.multimeterPopoutFrame = frame
        case .usbc:
            guard configuration.usbcPopoutFrame != frame else {
                return false
            }
            clearActiveLayoutProfile(configuration: &configuration)
            configuration.usbcPopoutFrame = frame
        }
        return true
    }

    func saveCurrentLayoutProfile(
        named rawName: String,
        configuration: inout AppConfiguration
    ) -> String? {
        guard let name = normalizedProfileName(rawName) else {
            return nil
        }

        let profile = AppConfiguration.PopoutLayoutProfile(
            name: name,
            multimeterMode: multimeterPopoutMode.configurationValue,
            usbcMode: usbcPopoutMode.configurationValue,
            multimeterFrame: configuration.multimeterPopoutFrame,
            usbcFrame: configuration.usbcPopoutFrame
        )

        if let existing = popoutLayoutProfiles.firstIndex(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) {
            popoutLayoutProfiles[existing] = profile
        } else {
            popoutLayoutProfiles.append(profile)
        }

        activePopoutLayoutProfileName = name
        configuration.popoutLayoutProfiles = popoutLayoutProfiles
        configuration.activePopoutLayoutProfileName = name
        return name
    }

    func applyLayoutProfile(
        named name: String,
        configuration: inout AppConfiguration
    ) -> Bool {
        guard let profile = popoutLayoutProfiles.first(where: { $0.name == name }) else {
            return false
        }

        multimeterPopoutMode = DevicePopoutDisplayMode(configurationValue: profile.multimeterMode)
        usbcPopoutMode = DevicePopoutDisplayMode(configurationValue: profile.usbcMode)
        configuration.multimeterPopoutMode = profile.multimeterMode
        configuration.usbcPopoutMode = profile.usbcMode
        configuration.multimeterPopoutFrame = profile.multimeterFrame
        configuration.usbcPopoutFrame = profile.usbcFrame
        activePopoutLayoutProfileName = profile.name
        configuration.activePopoutLayoutProfileName = profile.name
        configuration.popoutLayoutProfiles = popoutLayoutProfiles
        return true
    }

    func deleteLayoutProfile(
        named name: String,
        configuration: inout AppConfiguration
    ) {
        guard let index = popoutLayoutProfiles.firstIndex(where: { $0.name == name }) else {
            return
        }
        popoutLayoutProfiles.remove(at: index)
        if activePopoutLayoutProfileName == name {
            activePopoutLayoutProfileName = ""
            configuration.activePopoutLayoutProfileName = ""
        }
        configuration.popoutLayoutProfiles = popoutLayoutProfiles
    }

    private func clearActiveLayoutProfile(configuration: inout AppConfiguration) {
        guard !activePopoutLayoutProfileName.isEmpty else {
            return
        }
        activePopoutLayoutProfileName = ""
        configuration.activePopoutLayoutProfileName = ""
    }

    private func normalizedProfileName(_ rawName: String) -> String? {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return String(trimmed.prefix(48))
    }
}
