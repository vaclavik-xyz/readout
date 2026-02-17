import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

@main
struct ReadOutMacApp: App {
    @StateObject private var viewModel = DashboardViewModel()

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
            ContentView(viewModel: viewModel)
                .frame(minWidth: 1000, minHeight: 700)
        }
        .windowResizability(.contentSize)
    }
}
