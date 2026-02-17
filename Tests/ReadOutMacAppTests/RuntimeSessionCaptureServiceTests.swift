import Foundation
import Testing
@testable import ReadOutMacApp
@testable import ReadOutCore

private func uniqueCaptureURL(_ suffix: String) -> URL {
    let base = FileManager.default.temporaryDirectory
    let id = UUID().uuidString
    return base.appendingPathComponent("readout-capture-\(id)-\(suffix)")
}

@Test
func runtimeSessionCaptureRoundTripPersistsRecords() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let measurement = DeviceMeasurement(
        device: .multimeter,
        mode: .dcVoltage,
        modeString: "VOLT:DC",
        primaryValue: 12.34,
        primaryUnit: "V DC",
        timestamp: now
    )
    let records = [
        RuntimeSessionCaptureService.makeRecord(
            event: .multimeterStatus(.connected, "connected"),
            offsetMilliseconds: 0
        ),
        RuntimeSessionCaptureService.makeRecord(
            event: .multimeterMeasurement(measurement),
            offsetMilliseconds: 120
        ),
        RuntimeSessionCaptureService.makeRecord(
            event: .runtimeLog(.warning, "warn"),
            offsetMilliseconds: 150
        )
    ]

    let captureURL = uniqueCaptureURL("session.json")
    try RuntimeSessionCaptureService.writeCapture(
        createdAt: now,
        records: records,
        to: captureURL
    )

    let loaded = try RuntimeSessionCaptureService.readCapture(from: captureURL)
    #expect(loaded.version == 1)
    #expect(loaded.createdAt == now)
    #expect(loaded.events == records)

    let replayedEvents = loaded.events.compactMap(RuntimeSessionCaptureService.runtimeEvent)
    #expect(replayedEvents.count == 3)
}

@Test
func runtimeSessionCaptureIgnoresInvalidRecords() {
    let invalidRecord = RuntimeSessionCaptureRecord(
        offsetMilliseconds: 10,
        eventType: "unknown",
        state: nil,
        level: nil,
        message: nil,
        measurement: nil
    )

    let event = RuntimeSessionCaptureService.runtimeEvent(from: invalidRecord)
    switch event {
    case nil:
        #expect(Bool(true))
    default:
        #expect(Bool(false))
    }
}
