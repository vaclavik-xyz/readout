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
    private var pinStates: [DevicePopoutKind: Bool] = [:]
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
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = kind.windowTitle
        panel.setContentSize(kind.defaultSize)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.center()

        let delegate = DevicePopoutWindowDelegate { [weak self] in
            self?.panels[kind] = nil
            self?.panelDelegates[kind] = nil
        }
        panel.delegate = delegate
        panelDelegates[kind] = delegate

        if pinStates[kind] == nil {
            pinStates[kind] = true
        }
        applyPinState(for: kind, panel: panel)

        let root = DevicePopoutView(kind: kind, viewModel: viewModel, manager: self)
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

    func isPinned(_ kind: DevicePopoutKind) -> Bool {
        #if canImport(AppKit)
        return pinStates[kind] ?? true
        #else
        return false
        #endif
    }

    func setPinned(_ pinned: Bool, for kind: DevicePopoutKind) {
        #if canImport(AppKit)
        pinStates[kind] = pinned
        if let panel = panels[kind] {
            applyPinState(for: kind, panel: panel)
        }
        #endif
    }

    #if canImport(AppKit)
    private func applyPinState(for kind: DevicePopoutKind, panel: NSPanel) {
        let pinned = pinStates[kind] ?? true
        panel.level = pinned ? .floating : .normal
        panel.collectionBehavior = pinned
            ? [.canJoinAllSpaces, .fullScreenAuxiliary]
            : [.fullScreenAuxiliary]
    }
    #endif
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
    let manager: DevicePopoutManager

    private var palette: DashboardPalette {
        DashboardThemePalette.palette(for: viewModel.theme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(kind == .multimeter ? "Multimeter" : "USB-C")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.primaryText)
                Spacer()
                statusPill(kind == .multimeter ? viewModel.multimeterStatus : viewModel.usbcStatus)
            }

            if kind == .multimeter {
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.multimeterPrimary)
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .foregroundStyle(palette.primaryText)
                    Text(viewModel.multimeterSecondary)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.secondaryText)
                    Text(viewModel.multimeterMode)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(palette.tertiaryText)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.usbcVoltage)
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .foregroundStyle(palette.primaryText)
                    Text(viewModel.usbcCurrent)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.secondaryText)
                    Text("\(viewModel.usbcPower)  •  \(viewModel.usbcEnergy)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(palette.tertiaryText)
                        .lineLimit(2)
                }
            }

            Divider().overlay(palette.divider)

            HStack {
                Toggle("Always on top", isOn: Binding(
                    get: { manager.isPinned(kind) },
                    set: { manager.setPinned($0, for: kind) }
                ))
                .toggleStyle(.switch)
                .font(.system(size: 12, weight: .medium, design: .rounded))

                Spacer()

                Button("Close") {
                    manager.close(kind)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(palette.cardStrokeDefault, lineWidth: 1)
                )
        )
    }

    private func statusPill(_ status: DeviceUIState) -> some View {
        let color: Color = switch status {
        case .connected: .green
        case .connecting: .yellow
        case .error: .red
        case .disconnected: .gray
        }

        return Text(status.rawValue.capitalized)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.black.opacity(0.8))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color, in: Capsule())
    }
}
