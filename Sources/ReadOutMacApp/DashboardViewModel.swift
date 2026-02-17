import Foundation

struct ChartSample: Identifiable {
    let id = UUID()
    let timestamp: Date
    let value: Double
}

enum DeviceUIState: String {
    case disconnected
    case connecting
    case connected
    case error
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var multimeterStatus: DeviceUIState = .disconnected
    @Published var usbcStatus: DeviceUIState = .disconnected

    @Published var multimeterPrimary: String = "---"
    @Published var multimeterSecondary: String = ""
    @Published var multimeterMode: String = "No Signal"

    @Published var usbcVoltage: String = "---"
    @Published var usbcCurrent: String = "---"
    @Published var usbcPower: String = "Power: ---"
    @Published var usbcEnergy: String = "Energy: --- mWh | --- mAh"

    @Published var multimeterSamples: [ChartSample] = []
    @Published var usbcSamples: [ChartSample] = []

    private var timer: Timer?
    private var t: Double = 0

    init() {
        startPreviewSampling()
    }

    func connectAll() {
        multimeterStatus = .connected
        usbcStatus = .connected
    }

    func disconnectAll() {
        multimeterStatus = .disconnected
        usbcStatus = .disconnected
    }

    private func startPreviewSampling() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.advancePreviewTick()
            }
        }
    }

    private func advancePreviewTick() {
        t += 0.2

        let multimeterValue = 12.0 + sin(t * 0.9) * 0.3
        multimeterPrimary = String(format: "%.4f", multimeterValue)
        multimeterSecondary = "V DC"
        multimeterMode = "DC Voltage"

        let voltage = 9.0 + sin(t * 0.5) * 0.4
        let current = 1.2 + cos(t * 1.2) * 0.2
        let power = voltage * current

        usbcVoltage = String(format: "%.3f V", voltage)
        usbcCurrent = String(format: "%.3f A", current)
        usbcPower = String(format: "Power: %.3f W", power)
        usbcEnergy = String(format: "Energy: %.1f mWh | %.1f mAh", t * 3.2, t * 0.4)

        let now = Date()
        multimeterSamples.append(ChartSample(timestamp: now, value: multimeterValue))
        usbcSamples.append(ChartSample(timestamp: now, value: power))

        if multimeterSamples.count > 300 {
            multimeterSamples.removeFirst(multimeterSamples.count - 300)
        }
        if usbcSamples.count > 300 {
            usbcSamples.removeFirst(usbcSamples.count - 300)
        }
    }
}
