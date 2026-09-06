import SwiftUI
import SwiftData

@main
struct ScoreblokApp: App {
    private let container = Storage.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)
                .tint(M.red)
        }
        .modelContainer(container)
    }
}
