import Foundation

struct OutputRetryGate {
    private(set) var blockedUntil: Date?

    mutating func shouldAttempt(at now: Date = Date()) -> Bool {
        guard let blockedUntil else {
            return true
        }
        return now >= blockedUntil
    }

    mutating func recordFailure(at now: Date = Date(), cooldownSeconds: TimeInterval = 2.0) {
        blockedUntil = now.addingTimeInterval(max(0, cooldownSeconds))
    }

    mutating func recordSuccess() {
        blockedUntil = nil
    }
}
