import Foundation
import Testing
@testable import ReadOutMacApp

@Test
func outputRetryGateBlocksUntilCooldownExpires() {
    var gate = OutputRetryGate()
    let t0 = Date(timeIntervalSince1970: 1_000)

    #expect(gate.shouldAttempt(at: t0) == true)

    gate.recordFailure(at: t0, cooldownSeconds: 2.0)
    #expect(gate.shouldAttempt(at: t0) == false)
    #expect(gate.shouldAttempt(at: t0.addingTimeInterval(1.9)) == false)
    #expect(gate.shouldAttempt(at: t0.addingTimeInterval(2.0)) == true)
}

@Test
func outputRetryGateResetsAfterSuccess() {
    var gate = OutputRetryGate()
    let t0 = Date(timeIntervalSince1970: 1_000)

    gate.recordFailure(at: t0, cooldownSeconds: 5.0)
    #expect(gate.shouldAttempt(at: t0.addingTimeInterval(1.0)) == false)

    gate.recordSuccess()
    #expect(gate.shouldAttempt(at: t0.addingTimeInterval(1.0)) == true)
}
