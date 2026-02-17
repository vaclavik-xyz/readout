import Foundation
import Testing
@testable import ReadOutMacApp

@MainActor
@Test
func appStartupSmokeBootstrapsDashboardViewModel() async {
    let viewModel = DashboardViewModel()

    let bootstrapped = await waitUntil(timeoutSeconds: 2.0) {
        let message = viewModel.statusMessage
        return message == "Configuration loaded"
            || message == "Welcome. Complete setup before connecting."
            || message == "Configuration requires setup fixes."
            || message.hasPrefix("Failed to load config:")
            || message == "Failed to load config. Setup wizard opened."
    }
    #expect(bootstrapped == true)

    viewModel.configuration.useSimulator = true
    viewModel.connectAll()

    let started = await waitUntil(timeoutSeconds: 2.0) {
        viewModel.statusMessage.contains("Connecting")
            || viewModel.isRuntimeActive
    }
    #expect(started == true)

    viewModel.disconnectAll()
    let stopped = await waitUntil(timeoutSeconds: 2.0) {
        viewModel.statusMessage == "Disconnected"
    }
    #expect(stopped == true)
}

@MainActor
private func waitUntil(
    timeoutSeconds: TimeInterval,
    pollIntervalSeconds: TimeInterval = 0.02,
    condition: @escaping () -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(max(0.05, timeoutSeconds))
    while Date() < deadline {
        if condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: UInt64(max(0.001, pollIntervalSeconds) * 1_000_000_000))
    }
    return false
}
