import Foundation
#if canImport(AppKit)
import AppKit
#endif

final class PcBeepController {
    private var task: Task<Void, Never>?
    private let intervalSeconds: TimeInterval

    init(intervalSeconds: TimeInterval = 0.7) {
        self.intervalSeconds = intervalSeconds
    }

    deinit {
        stop()
    }

    func setBeeping(_ enabled: Bool) {
        if enabled {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard task == nil else {
            return
        }

        let interval = intervalSeconds
        task = Task {
            while !Task.isCancelled {
                #if canImport(AppKit)
                await MainActor.run {
                    NSSound.beep()
                }
                #endif

                let nanos = UInt64(Swift.max(0, interval) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
            }
        }
    }

    private func stop() {
        task?.cancel()
        task = nil
    }
}
