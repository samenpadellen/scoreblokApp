import Foundation
import SwiftData
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Houdt de momentopname voor de widget bij. Wordt aangeroepen zodra er iets
/// aan een potje verandert; is de App Group nog niet ingesteld, dan gebeurt
/// er niets en werkt de app gewoon door.
enum SnapshotWriter {

    @MainActor
    static func update(from matches: [Match]) {
        guard WidgetSnapshot.containerURL != nil else { return }

        guard let match = matches
            .filter(\.isOpen)
            .max(by: { $0.lastPlayedAt < $1.lastPlayedAt })
        else {
            WidgetSnapshot.clear()
            reload()
            return
        }

        let snapshot = WidgetSnapshot(
            gameName: match.gameName,
            mono: match.mono,
            unitLabel: match.unitLabel,
            position: position(of: match),
            lastPlayed: match.lastPlayedAt,
            standings: match.standings.map {
                .init(id: $0.player.id,
                      name: $0.player.name,
                      initial: $0.player.initial,
                      total: $0.total,
                      rank: $0.rank,
                      rampIndex: $0.player.rampIndex,
                      avatarIndex: $0.player.avatarIndex)
            },
            isOpen: true
        )

        guard snapshot != WidgetSnapshot.read() else { return }
        snapshot.write()
        reload()
    }

    private static func position(of match: Match) -> String {
        switch match.mode {
        case .scorecard: "scorekaart"
        case .winnerOnly: "eindvolgorde"
        case .finalScore: "eindscore"
        default:
            if let label = match.roundLabel(at: match.currentRoundIndex) {
                "ronde \(match.currentRoundIndex + 1) · \(label.lowercased())"
            } else if match.roundCount > 0 {
                "ronde \(match.currentRoundIndex + 1) van \(match.roundCount)"
            } else {
                "ronde \(match.currentRoundIndex + 1)"
            }
        }
    }

    private static func reload() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
