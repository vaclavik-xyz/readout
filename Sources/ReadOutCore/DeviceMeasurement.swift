import Foundation

public enum DeviceKind: String, Sendable, Equatable, CaseIterable {
    case multimeter
    case usbC
}

public struct DeviceMeasurement: Sendable, Equatable {
    public let device: DeviceKind
    public let mode: MeasurementMode
    public let modeString: String
    public let primaryValue: Double?
    public let primaryUnit: String
    public let secondaryValue: Double?
    public let secondaryUnit: String
    public let powerWatts: Double?
    public let energyMWh: Double?
    public let energyMAh: Double?
    public let isOverload: Bool
    public let isOpen: Bool
    public let isShort: Bool
    public let timestamp: Date

    public init(
        device: DeviceKind,
        mode: MeasurementMode,
        modeString: String,
        primaryValue: Double?,
        primaryUnit: String,
        secondaryValue: Double? = nil,
        secondaryUnit: String = "",
        powerWatts: Double? = nil,
        energyMWh: Double? = nil,
        energyMAh: Double? = nil,
        isOverload: Bool = false,
        isOpen: Bool = false,
        isShort: Bool = false,
        timestamp: Date = Date()
    ) {
        self.device = device
        self.mode = mode
        self.modeString = modeString
        self.primaryValue = primaryValue
        self.primaryUnit = primaryUnit
        self.secondaryValue = secondaryValue
        self.secondaryUnit = secondaryUnit
        self.powerWatts = powerWatts
        self.energyMWh = energyMWh
        self.energyMAh = energyMAh
        self.isOverload = isOverload
        self.isOpen = isOpen
        self.isShort = isShort
        self.timestamp = timestamp
    }
}
