import Foundation
import Testing
@testable import ReadOutMacApp
import ReadOutPersistence

private actor RuntimeEventRecorder {
    private var events: [RuntimeEvent] = []

    func append(_ event: RuntimeEvent) {
        events.append(event)
    }

    func hasMultimeterStatus(_ state: DeviceUIState) -> Bool {
        events.contains {
            if case .multimeterStatus(let s, _) = $0 { return s == state }
            return false
        }
    }

    func hasUsbcStatus(_ state: DeviceUIState) -> Bool {
        events.contains {
            if case .usbcStatus(let s, _) = $0 { return s == state }
            return false
        }
    }

    func hasMultimeterError(containing text: String) -> Bool {
        events.contains {
            if case .multimeterStatus(.error, let msg) = $0 {
                return msg?.contains(text) ?? false
            }
            return false
        }
    }

    func hasUsbcError(containing text: String) -> Bool {
        events.contains {
            if case .usbcStatus(.error, let msg) = $0 {
                return msg?.contains(text) ?? false
            }
            return false
        }
    }

    func hasMultimeterMeasurement() -> Bool {
        events.contains {
            if case .multimeterMeasurement = $0 { return true }
            return false
        }
    }

    func hasUsbcMeasurement() -> Bool {
        events.contains {
            if case .usbcMeasurement = $0 { return true }
            return false
        }
    }

    func multimeterMeasurementCount() -> Int {
        events.filter {
            if case .multimeterMeasurement = $0 { return true }
            return false
        }.count
    }

    func reset() {
        events.removeAll()
    }
}

private func waitUntil(
    timeoutSeconds: TimeInterval = 2.0,
    condition: @Sendable () async -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(max(0.05, timeoutSeconds))
    while Date() < deadline {
        if await condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return false
}

// MARK: - Error Path Tests

@Test
func emptyMultimeterPortWithoutSimulatorEmitsError() async {
    let recorder = RuntimeEventRecorder()
    let runtime = ReadOutRuntime { event in
        Task { await recorder.append(event) }
    }

    var config = AppConfiguration()
    config.multimeterEnabled = true
    config.multimeterPort = ""
    config.useSimulator = false
    config.usbcEnabled = false

    await runtime.start(with: config)

    let found = await waitUntil {
        await recorder.hasMultimeterError(containing: "port is empty")
    }
    #expect(found == true)

    await runtime.stop()
}

@Test
func emptyUsbcPortWithoutSimulatorEmitsError() async {
    let recorder = RuntimeEventRecorder()
    let runtime = ReadOutRuntime { event in
        Task { await recorder.append(event) }
    }

    var config = AppConfiguration()
    config.multimeterEnabled = false
    config.usbcEnabled = true
    config.usbcPort = ""
    config.useSimulator = false

    await runtime.start(with: config)

    let found = await waitUntil {
        await recorder.hasUsbcError(containing: "port is empty")
    }
    #expect(found == true)

    await runtime.stop()
}

@Test
func disabledDevicesEmitDisconnected() async {
    let recorder = RuntimeEventRecorder()
    let runtime = ReadOutRuntime { event in
        Task { await recorder.append(event) }
    }

    var config = AppConfiguration()
    config.multimeterEnabled = false
    config.usbcEnabled = false

    await runtime.start(with: config)

    let mmDisconnected = await waitUntil {
        await recorder.hasMultimeterStatus(.disconnected)
    }
    let usbcDisconnected = await waitUntil {
        await recorder.hasUsbcStatus(.disconnected)
    }
    #expect(mmDisconnected == true)
    #expect(usbcDisconnected == true)

    await runtime.stop()
}

// MARK: - Simulator Lifecycle Tests

@Test
func simulatorStartEmitsMeasurements() async {
    let recorder = RuntimeEventRecorder()
    let runtime = ReadOutRuntime { event in
        Task { await recorder.append(event) }
    }

    var config = AppConfiguration()
    config.multimeterEnabled = true
    config.usbcEnabled = false
    config.useSimulator = true
    config.sampleRateHz = 20

    await runtime.start(with: config)

    let connected = await waitUntil {
        await recorder.hasMultimeterStatus(.connected)
    }
    #expect(connected == true)

    let hasMeasurement = await waitUntil {
        await recorder.hasMultimeterMeasurement()
    }
    #expect(hasMeasurement == true)

    await runtime.stop()
}

@Test
func simulatorBothDevicesEmitMeasurements() async {
    let recorder = RuntimeEventRecorder()
    let runtime = ReadOutRuntime { event in
        Task { await recorder.append(event) }
    }

    var config = AppConfiguration()
    config.multimeterEnabled = true
    config.usbcEnabled = true
    config.useSimulator = true
    config.sampleRateHz = 20

    await runtime.start(with: config)

    let mmMeasurement = await waitUntil {
        await recorder.hasMultimeterMeasurement()
    }
    let usbcMeasurement = await waitUntil {
        await recorder.hasUsbcMeasurement()
    }
    #expect(mmMeasurement == true)
    #expect(usbcMeasurement == true)

    await runtime.stop()
}

@Test
func stopEmitsDisconnectedForBothDevices() async {
    let recorder = RuntimeEventRecorder()
    let runtime = ReadOutRuntime { event in
        Task { await recorder.append(event) }
    }

    var config = AppConfiguration()
    config.multimeterEnabled = true
    config.usbcEnabled = true
    config.useSimulator = true
    config.sampleRateHz = 20

    await runtime.start(with: config)

    // Wait for measurements to flow before stopping.
    let flowing = await waitUntil {
        let mm = await recorder.hasMultimeterMeasurement()
        let usbc = await recorder.hasUsbcMeasurement()
        return mm && usbc
    }
    #expect(flowing == true)

    await recorder.reset()
    await runtime.stop()

    // stop() synchronously emits disconnected for both devices.
    let mmDisconnected = await waitUntil {
        await recorder.hasMultimeterStatus(.disconnected)
    }
    let usbcDisconnected = await waitUntil {
        await recorder.hasUsbcStatus(.disconnected)
    }
    #expect(mmDisconnected == true)
    #expect(usbcDisconnected == true)
}

@Test
func startStopStartDoesNotLeak() async {
    let recorder = RuntimeEventRecorder()
    let runtime = ReadOutRuntime { event in
        Task { await recorder.append(event) }
    }

    var config = AppConfiguration()
    config.multimeterEnabled = true
    config.usbcEnabled = false
    config.useSimulator = true
    config.sampleRateHz = 20

    // First cycle
    await runtime.start(with: config)
    let firstMeasurement = await waitUntil {
        await recorder.hasMultimeterMeasurement()
    }
    #expect(firstMeasurement == true)

    await runtime.stop()
    await recorder.reset()

    // Second cycle — fresh start should work.
    await runtime.start(with: config)
    let secondMeasurement = await waitUntil {
        await recorder.hasMultimeterMeasurement()
    }
    #expect(secondMeasurement == true)

    await runtime.stop()
}
