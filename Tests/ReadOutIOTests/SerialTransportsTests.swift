import Foundation
import Testing
@testable import ReadOutIO

private actor MockLineIO: SerialLineIO {
    private(set) var openCount = 0
    private(set) var closeCount = 0
    private(set) var writes: [String] = []
    private var reads: [String?]

    init(reads: [String?]) {
        self.reads = reads
    }

    func open() async throws {
        openCount += 1
    }

    func close() async {
        closeCount += 1
    }

    func writeLine(_ line: String) async throws {
        writes.append(line)
    }

    func readLine() async throws -> String? {
        if reads.isEmpty {
            return nil
        }
        return reads.removeFirst()
    }

    func snapshot() -> (open: Int, close: Int, writes: [String]) {
        (openCount, closeCount, writes)
    }
}

@Test
func streamingTransportProxiesLineIO() async throws {
    let io = MockLineIO(reads: ["FRAME"])
    let transport = StreamingSerialTransport(lineIO: io)

    try await transport.open()
    let frame = try await transport.readFrame()
    await transport.close()

    #expect(frame == "FRAME")
    let snapshot = await io.snapshot()
    #expect(snapshot.open == 1)
    #expect(snapshot.close == 1)
    #expect(snapshot.writes.isEmpty == true)
}

@Test
func scpiTransportUsesFallbackWhenPrimaryIsEmpty() async throws {
    let io = MockLineIO(reads: ["", "12.34"])
    let transport = SCPIPollingTransport(lineIO: io)

    try await transport.open()
    let response = try await transport.readFrame()

    #expect(response == "12.34")
    let snapshot = await io.snapshot()
    #expect(snapshot.writes == ["MEAS?", "MEAS1:SHOW?"])
}

@Test
func portDiscoveryFiltersKnownNames() {
    let candidates = [
        "cu.usbserial-1140",
        "tty.usbmodem-001",
        "random0",
        "cu.Bluetooth-Incoming-Port",
        "tty.wchusbserialABC"
    ]

    let filtered = SerialPortDiscovery.filterCandidateNames(candidates)
    #expect(filtered == [
        "cu.usbserial-1140",
        "tty.usbmodem-001",
        "tty.wchusbserialABC"
    ])
}
