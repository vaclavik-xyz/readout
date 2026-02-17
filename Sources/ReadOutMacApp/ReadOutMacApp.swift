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
    }
}
