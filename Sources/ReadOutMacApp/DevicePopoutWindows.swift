import SwiftUI
import ReadOutPersistence
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

        let restoredFrame = restoreFrameIfAvailable(for: kind, viewModel: viewModel)
        let initialFrame = restoredFrame ?? NSRect(origin: .zero, size: kind.defaultSize)

        let panel = NSPanel(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .utilityWindow, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = kind.windowTitle
        panel.setContentSize(initialFrame.size)
        panel.minSize = CGSize(width: 260, height: 170)
        panel.maxSize = CGSize(width: 960, height: 720)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        if restoredFrame == nil {
            panel.center()
        }

        let delegate = DevicePopoutWindowDelegate(
            onClose: { [weak self] in
                self?.panels[kind] = nil
                self?.panelDelegates[kind] = nil
            },
            onFrameChanged: { [weak viewModel] frame in
                guard let viewModel else {
                    return
                }
                let popoutFrame = AppConfiguration.PopoutWindowFrame(
                    x: frame.origin.x,
                    y: frame.origin.y,
                    width: frame.size.width,
                    height: frame.size.height
                )
                viewModel.setPopoutFrame(popoutFrame, for: kind)
            }
        )
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

    private func restoreFrameIfAvailable(
        for kind: DevicePopoutKind,
        viewModel: DashboardViewModel
    ) -> NSRect? {
        #if canImport(AppKit)
        guard let persisted = viewModel.popoutFrame(for: kind) else {
            return nil
        }
        let rawFrame = NSRect(
            x: persisted.x,
            y: persisted.y,
            width: persisted.width,
            height: persisted.height
        )
        guard rawFrame.width >= 120, rawFrame.height >= 90 else {
            return nil
        }

        if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rawFrame) }) {
            return rawFrame
        }

        guard let screen = NSScreen.main else {
            return nil
        }
        let visible = screen.visibleFrame.insetBy(dx: 24, dy: 24)
        let safeWidth = min(max(260, rawFrame.width), visible.width)
        let safeHeight = min(max(170, rawFrame.height), visible.height)
        let safeX = visible.midX - (safeWidth / 2)
        let safeY = visible.midY - (safeHeight / 2)
        return NSRect(x: safeX, y: safeY, width: safeWidth, height: safeHeight)
        #else
        return nil
        #endif
    }

    func close(_ kind: DevicePopoutKind) {
        #if canImport(AppKit)
        panels[kind]?.close()
        #endif
    }
}

#if canImport(AppKit)
@MainActor
private final class DevicePopoutWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void
    private let onFrameChanged: (NSRect) -> Void
    private var pendingPersistWorkItem: DispatchWorkItem?
    private let debounceDelay: TimeInterval = 0.25

    init(onClose: @escaping () -> Void, onFrameChanged: @escaping (NSRect) -> Void) {
        self.onClose = onClose
        self.onFrameChanged = onFrameChanged
    }

    func windowWillClose(_ notification: Notification) {
        pendingPersistWorkItem?.cancel()
        onClose()
    }

    func windowDidMove(_ notification: Notification) {
        scheduleFramePersist(notification)
    }

    func windowDidResize(_ notification: Notification) {
        scheduleFramePersist(notification)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        scheduleFramePersist(notification, immediate: true)
    }

    private func scheduleFramePersist(_ notification: Notification, immediate: Bool = false) {
        guard let window = notification.object as? NSWindow else {
            return
        }

        let frame = window.frame
        pendingPersistWorkItem?.cancel()
        let work = DispatchWorkItem { [onFrameChanged] in
            onFrameChanged(frame)
        }
        pendingPersistWorkItem = work
        if immediate {
            DispatchQueue.main.async(execute: work)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + debounceDelay, execute: work)
        }
    }
}
#endif

private struct DevicePopoutView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let kind: DevicePopoutKind
    @ObservedObject var viewModel: DashboardViewModel
    @State private var emphasisPulse = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let displayMode = viewModel.popoutMode(for: kind)
            let scale = popoutScale(for: size, kind: kind) * scaleMultiplier(for: displayMode)

            VStack(alignment: .leading, spacing: 12 * scale) {
                HStack {
                    Text(kind == .multimeter ? "Multimeter" : "USB-C")
                        .font(.system(size: titleFontSize(for: displayMode) * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Spacer()
                    statusPill(
                        kind == .multimeter ? viewModel.multimeterStatus : viewModel.usbcStatus,
                        scale: scale
                    )
                }
                if let alarmStatusText {
                    Text(alarmStatusText)
                        .font(.system(size: max(10, 10 * scale), weight: .bold, design: .rounded))
                        .foregroundStyle(alarmStatusColor)
                        .padding(.horizontal, 8 * scale)
                        .padding(.vertical, 4 * scale)
                        .background(alarmStatusColor.opacity(0.16), in: Capsule())
                }
                content(for: displayMode, scale: scale)
            }
            .padding(14 * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(popoutBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        emphasisBorderColor.opacity(isAlarmEmphasisVisible ? 0.95 : 0),
                        lineWidth: isAlarmEmphasisVisible ? (isAlarmEmphasisAnimated && emphasisPulse ? 3 : 2) : 0
                    )
                    .animation(.easeInOut(duration: 0.22), value: isAlarmEmphasisVisible)
            )
            .shadow(
                color: emphasisBorderColor.opacity(
                    isAlarmEmphasisVisible
                        ? (isAlarmEmphasisAnimated && emphasisPulse ? 0.35 : 0.15)
                        : 0
                ),
                radius: isAlarmEmphasisVisible ? (isAlarmEmphasisAnimated && emphasisPulse ? 14 : 8) : 0
            )
            .contextMenu {
                Menu("Display Mode") {
                    ForEach(DevicePopoutDisplayMode.allCases) { mode in
                        Button {
                            viewModel.setPopoutMode(mode, for: kind)
                        } label: {
                            if mode == displayMode {
                                Label(mode.title, systemImage: "checkmark")
                            } else {
                                Text(mode.title)
                            }
                        }
                    }
                }
            }
            .onAppear {
                if isAlarmEmphasisAnimated {
                    startAlarmEmphasisPulse()
                }
            }
            .onChange(of: isAlarmEmphasisAnimated) { _, active in
                if active {
                    startAlarmEmphasisPulse()
                } else {
                    emphasisPulse = false
                }
            }
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

    private var isAlarmEmphasisVisible: Bool {
        guard viewModel.configuration.popoutAlarmEmphasisEnabled else {
            return false
        }
        guard kind == .multimeter else {
            return false
        }

        switch viewModel.multimeterAlertState {
        case .short, .highAlarm, .lowAlarm:
            return true
        case .none, .open:
            return false
        }
    }

    private var isAlarmEmphasisAnimated: Bool {
        isAlarmEmphasisVisible && !reduceMotion
    }

    private var emphasisBorderColor: Color {
        switch viewModel.multimeterAlertState {
        case .short:
            return .red
        case .highAlarm:
            return .orange
        case .lowAlarm:
            return .cyan
        case .none, .open:
            return .clear
        }
    }

    private func startAlarmEmphasisPulse() {
        emphasisPulse = false
        withAnimation(.easeInOut(duration: 0.82).repeatForever(autoreverses: true)) {
            emphasisPulse = true
        }
    }

    private func popoutScale(for size: CGSize, kind: DevicePopoutKind) -> CGFloat {
        let base = kind.defaultSize
        let widthRatio = size.width / max(1, base.width)
        let heightRatio = size.height / max(1, base.height)
        return min(max(0.70, min(widthRatio, heightRatio)), 2.0)
    }

    private func scaleMultiplier(for mode: DevicePopoutDisplayMode) -> CGFloat {
        switch mode {
        case .mini:
            return 1.08
        case .compact:
            return 0.96
        case .detailed:
            return 1.0
        }
    }

    private func titleFontSize(for mode: DevicePopoutDisplayMode) -> CGFloat {
        switch mode {
        case .mini:
            return 15
        case .compact, .detailed:
            return 17
        }
    }

    private var alarmStatusText: String? {
        let summary = viewModel.alarmControlSummary
        guard summary != "Live" else {
            return nil
        }
        return "Alarm: \(summary)"
    }

    private var alarmStatusColor: Color {
        viewModel.isAlarmSilenced ? .yellow : .mint
    }

    @ViewBuilder
    private func content(for mode: DevicePopoutDisplayMode, scale: CGFloat) -> some View {
        switch mode {
        case .mini:
            VStack(alignment: .leading, spacing: 6 * scale) {
                Text(primaryValueText)
                    .font(.system(size: primaryFontSize(for: mode) * scale, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .foregroundStyle(.primary)
                Text(secondaryValueText)
                    .font(.system(size: secondaryFontSize(for: mode) * scale, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

        case .compact, .detailed:
            VStack(alignment: .leading, spacing: 6 * scale) {
                Text(primaryValueText)
                    .font(.system(size: primaryFontSize(for: mode) * scale, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .foregroundStyle(.primary)
                Text(secondaryValueText)
                    .font(.system(size: secondaryFontSize(for: mode) * scale, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(tertiaryValueText(for: mode))
                    .font(.system(size: tertiaryFontSize(for: mode) * scale, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(mode == .compact ? 1 : 2)
            }
        }
    }

    private var primaryValueText: String {
        switch kind {
        case .multimeter:
            return viewModel.multimeterPrimary
        case .usbc:
            return viewModel.usbcVoltage
        }
    }

    private var secondaryValueText: String {
        switch kind {
        case .multimeter:
            return viewModel.multimeterSecondary
        case .usbc:
            return viewModel.usbcCurrent
        }
    }

    private func tertiaryValueText(for mode: DevicePopoutDisplayMode) -> String {
        switch kind {
        case .multimeter:
            return viewModel.multimeterMode
        case .usbc:
            if mode == .compact {
                return viewModel.usbcPower
            }
            return "\(viewModel.usbcPower)  •  \(viewModel.usbcEnergy)"
        }
    }

    private func primaryFontSize(for mode: DevicePopoutDisplayMode) -> CGFloat {
        switch mode {
        case .mini:
            return kind == .multimeter ? 44 : 42
        case .compact:
            return kind == .multimeter ? 38 : 36
        case .detailed:
            return kind == .multimeter ? 40 : 38
        }
    }

    private func secondaryFontSize(for mode: DevicePopoutDisplayMode) -> CGFloat {
        switch mode {
        case .mini:
            return 18
        case .compact:
            return 19
        case .detailed:
            return 22
        }
    }

    private func tertiaryFontSize(for mode: DevicePopoutDisplayMode) -> CGFloat {
        switch mode {
        case .mini:
            return 0
        case .compact:
            return 11
        case .detailed:
            return 12
        }
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
