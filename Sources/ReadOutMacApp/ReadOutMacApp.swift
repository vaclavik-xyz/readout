import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

@main
struct ReadOutMacApp: App {
    @StateObject private var viewModel = DashboardViewModel()
    @StateObject private var popoutManager = DevicePopoutManager()

    init() {
        #if canImport(AppKit)
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup("readOut") {
            ContentView(viewModel: viewModel, popoutManager: popoutManager)
                .frame(minWidth: 1000, minHeight: 700)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandMenu("Dashboard") {
                Button("Pop-out Multimeter") {
                    popoutManager.show(.multimeter, viewModel: viewModel)
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button("Pop-out USB-C") {
                    popoutManager.show(.usbc, viewModel: viewModel)
                }
                .keyboardShortcut("2", modifiers: [.command])

                Divider()

                Button(viewModel.isRenderPaused ? "Resume UI" : "Pause UI") {
                    viewModel.toggleRenderPause()
                }
                .keyboardShortcut("p", modifiers: [.command])

                Button(viewModel.isRuntimeLogPanelVisible ? "Hide Logs" : "Show Logs") {
                    viewModel.toggleRuntimeLogPanelVisibility()
                }
                .keyboardShortcut("l", modifiers: [.command])
            }
        }
    }
}
