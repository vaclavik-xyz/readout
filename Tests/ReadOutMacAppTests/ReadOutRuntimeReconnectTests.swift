import Foundation
import Testing
@testable import ReadOutMacApp

@Test
func reconnectDelayFirstAttemptIsInitial() {
    let delay = ReadOutRuntime.reconnectDelay(forAttempt: 1)
    #expect(delay == 0.5)
}

@Test
func reconnectDelaySecondAttemptDoubles() {
    let delay = ReadOutRuntime.reconnectDelay(forAttempt: 2)
    #expect(delay == 1.0)
}

@Test
func reconnectDelayThirdAttemptDoubles() {
    let delay = ReadOutRuntime.reconnectDelay(forAttempt: 3)
    #expect(delay == 2.0)
}

@Test
func reconnectDelayCapsAtFiveSeconds() {
    let delay = ReadOutRuntime.reconnectDelay(forAttempt: 10)
    #expect(delay == 5.0)
}

@Test
func reconnectDelayZeroAttemptUsesInitial() {
    let delay = ReadOutRuntime.reconnectDelay(forAttempt: 0)
    #expect(delay == 0.5)
}
