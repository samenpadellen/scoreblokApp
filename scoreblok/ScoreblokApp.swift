import SwiftUI
import SwiftData

@main
struct ScoreblokApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)
                .tint(M.red)
        }
        .modelContainer(for: [Player.self, GameTemplate.self, Match.self,
                              MatchRound.self, ScoreEntry.self, ScoreCard.self])
    }
}
