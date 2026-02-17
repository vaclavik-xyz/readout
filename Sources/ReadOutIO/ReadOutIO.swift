import Foundation
import ReadOutCore

public protocol DeviceSession: Sendable {
    var id: String { get }
    func start() async
    func stop() async
}

public enum ReadOutIOBootstrap {
    public static let note = "Serial transport and reconnect state machine will be added in the next milestone."
}
