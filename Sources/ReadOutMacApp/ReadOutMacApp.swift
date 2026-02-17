import SwiftUI

@main
struct ReadOutMacApp: App {
    @StateObject private var viewModel = DashboardViewModel()

    var body: some Scene {
        WindowGroup("readOut") {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 1000, minHeight: 700)
        }
        .windowResizability(.contentSize)
    }
}
