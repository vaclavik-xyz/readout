import Foundation
#if canImport(AppKit)
import AppKit
#endif

final class PcBeepController: @unchecked Sendable {
    private var task: Task<Void, Never>?
    private let intervalSeconds: TimeInterval
    private var soundPreset: MacAlertSoundPreset
    private var volume: Double

    init(
        intervalSeconds: TimeInterval = 0.7,
        soundPreset: MacAlertSoundPreset = .system,
        volume: Double = 0.5
    ) {
        self.intervalSeconds = intervalSeconds
        self.soundPreset = soundPreset
        self.volume = max(0, min(1, volume))
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

    func configure(soundPreset: MacAlertSoundPreset, volume: Double) {
        self.soundPreset = soundPreset
        self.volume = max(0, min(1, volume))
    }

    private func start() {
        guard task == nil else {
            return
        }

        let interval = intervalSeconds
        task = Task {
            while !Task.isCancelled {
                await playTick()

                let nanos = UInt64(Swift.max(0, interval) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
            }
        }
    }

    private func stop() {
        task?.cancel()
        task = nil
    }

    private func playTick() async {
        #if canImport(AppKit)
        let preset = soundPreset
        let volume = self.volume
        await MainActor.run {
            guard preset != .system else {
                NSSound.beep()
                return
            }

            guard let soundName = Self.soundName(for: preset) else {
                NSSound.beep()
                return
            }

            guard let sound = NSSound(named: NSSound.Name(soundName)) else {
                NSSound.beep()
                return
            }

            sound.stop()
            sound.volume = Float(volume)
            sound.play()
        }
        #endif
    }

    static func soundName(for preset: MacAlertSoundPreset) -> String? {
        switch preset {
        case .system:
            return nil
        case .glass:
            return "Glass"
        case .sosumi:
            return "Sosumi"
        case .funk:
            return "Funk"
        }
    }
}
