import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

enum DevicePopoutKind: String {
    case multimeter
    case usbc

    var windowTitle: String {
        switch self {
        case .multimeter:
            return "readOut — Multimeter"
        case .usbc:
            return "readOut — USB-C"
        }
    }

    var defaultSize: CGSize {
        switch self {
        case .multimeter:
            return CGSize(width: 330, height: 210)
        case .usbc:
            return CGSize(width: 340, height: 230)
        }
    }
}

@MainActor
final class DevicePopoutManager: ObservableObject {
    #if canImport(AppKit)
    private var panels: [DevicePopoutKind: NSPanel] = [:]
    private var panelDelegates: [DevicePopoutKind: DevicePopoutWindowDelegate] = [:]
    #endif

    func show(_ kind: DevicePopoutKind, viewModel: DashboardViewModel) {
        #if canImport(AppKit)
        if let panel = panels[kind] {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: kind.defaultSize),
            styleMask: [.titled, .closable, .utilityWindow, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = kind.windowTitle
        panel.setContentSize(kind.defaultSize)
        panel.minSize = CGSize(width: 260, height: 170)
        panel.maxSize = CGSize(width: 960, height: 720)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.center()

        let delegate = DevicePopoutWindowDelegate { [weak self] in
            self?.panels[kind] = nil
            self?.panelDelegates[kind] = nil
        }
        panel.delegate = delegate
        panelDelegates[kind] = delegate

        let root = DevicePopoutView(kind: kind, viewModel: viewModel)
            .preferredColorScheme(viewModel.theme.preferredColorScheme)
        panel.contentView = NSHostingView(rootView: root)
        panels[kind] = panel

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        #endif
    }

    func close(_ kind: DevicePopoutKind) {
        #if canImport(AppKit)
        panels[kind]?.close()
        #endif
    }
}

#if canImport(AppKit)
private final class DevicePopoutWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
#endif

private struct DevicePopoutView: View {
    let kind: DevicePopoutKind
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let scale = popoutScale(for: size, kind: kind)

            VStack(alignment: .leading, spacing: 12 * scale) {
                HStack {
                    Text(kind == .multimeter ? "Multimeter" : "USB-C")
                        .font(.system(size: 17 * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Spacer()
                    statusPill(
                        kind == .multimeter ? viewModel.multimeterStatus : viewModel.usbcStatus,
                        scale: scale
                    )
                }

                if kind == .multimeter {
                    VStack(alignment: .leading, spacing: 6 * scale) {
                        Text(viewModel.multimeterPrimary)
                            .font(.system(size: 40 * scale, weight: .black, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .foregroundStyle(.primary)
                        Text(viewModel.multimeterSecondary)
                            .font(.system(size: 22 * scale, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text(viewModel.multimeterMode)
                            .font(.system(size: 13 * scale, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6 * scale) {
                        Text(viewModel.usbcVoltage)
                            .font(.system(size: 38 * scale, weight: .black, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .foregroundStyle(.primary)
                        Text(viewModel.usbcCurrent)
                            .font(.system(size: 22 * scale, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text("\(viewModel.usbcPower)  •  \(viewModel.usbcEnergy)")
                            .font(.system(size: 12 * scale, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Divider().overlay(Color.primary.opacity(0.15))
            }
            .padding(14 * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(popoutBackground)
        }
    }

    private var popoutBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
    }

    private func popoutScale(for size: CGSize, kind: DevicePopoutKind) -> CGFloat {
        let base = kind.defaultSize
        let widthRatio = size.width / max(1, base.width)
        let heightRatio = size.height / max(1, base.height)
        return min(max(0.70, min(widthRatio, heightRatio)), 2.0)
    }

    private func statusPill(_ status: DeviceUIState, scale: CGFloat) -> some View {
        let color: Color = switch status {
        case .connected: .green
        case .connecting: .yellow
        case .error: .red
        case .disconnected: .gray
        }

        return Text(status.rawValue.capitalized)
            .font(.system(size: 10 * scale, weight: .bold, design: .rounded))
            .foregroundStyle(.black.opacity(0.8))
            .padding(.horizontal, 9 * scale)
            .padding(.vertical, 4 * scale)
            .background(color, in: Capsule())
    }
}
