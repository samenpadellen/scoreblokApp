import Foundation
import SwiftData
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Houdt de momentopname voor de widgets bij. Wordt bijgewerkt zodra een
/// totaal verandert, niet op een tijdklok. Is de App Group nog niet
/// ingesteld, dan gebeurt er niets en werkt de app gewoon door.
enum SnapshotWriter {

    @MainActor
    static func update(from matches: [Match], players: [Player] = []) {
        guard WidgetSnapshot.containerURL != nil else { return }

        let all = matches
        let counted = all.filter(\.counts)
        let period = StatsPeriod.preferred
        let scoped = StatsEngine.matches(counted, in: period)

        // Spelers halen we uit de potjes zelf als ze niet zijn meegegeven.
        let roster = players.isEmpty
            ? Array(Set(all.flatMap(\.players).map(\.id)))
                .compactMap { id in all.flatMap(\.players).first { $0.id == id } }
            : players.filter { !$0.isArchived }

        let ranking = StatsEngine.standings(for: roster, in: scoped).prefix(4).map {
            WidgetSnapshot.RankEntry(id: $0.player.id,
                                     name: $0.player.name,
                                     initial: $0.player.initial,
                                     rampIndex: $0.player.rampIndex,
                                     avatarIndex: $0.player.avatarIndex,
                                     winRate: $0.winRate,
                                     played: $0.played)
        }

        var open: WidgetSnapshot.OpenMatch?
        if let match = all.filter(\.isOpen).max(by: { $0.lastPlayedAt < $1.lastPlayedAt }) {
            let standings = match.standings
            let leaderTotal = standings.first?.total ?? 0
            let entries = standings.map {
                WidgetSnapshot.Entry(id: $0.player.id,
                                     name: $0.player.name,
                                     initial: $0.player.initial,
                                     total: $0.total,
                                     rank: $0.rank,
                                     rampIndex: $0.player.rampIndex,
                                     avatarIndex: $0.player.avatarIndex,
                                     gap: abs($0.total - leaderTotal))
            }
            let rounds = match.orderedRounds
                .filter { !$0.entries.isEmpty }
                .suffix(3)
                .map { round in
                    WidgetSnapshot.OpenMatch.Round(
                        label: "\(round.index + 1)",
                        cells: standings.map {
                            round.value(for: $0.player.id).map { "\($0)" } ?? "·"
                        })
                }

            open = WidgetSnapshot.OpenMatch(
                id: match.id,
                gameName: match.gameName,
                mono: match.mono,
                unitLabel: match.unitLabel,
                position: position(of: match),
                rule: "\(match.winsByLowest ? "laagste" : "hoogste") totaal wint",
                startedAt: match.startedAt,
                lastPlayed: match.lastPlayedAt,
                standings: entries,
                playedRounds: Array(rounds),
                accentHex: GameAccent.of(match.gameName).onInkHex)
        }

        // Toegangsscherm en Dynamic Island volgen dezelfde stand.
        LiveScore.sync(open: open, matches: all)

        let snapshot = WidgetSnapshot(
            open: open,
            ranking: Array(ranking),
            period: period.rawValue,
            totalMatches: scoped.count,
            lastFinished: counted.compactMap(\.endedAt).max())

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
            if match.roundCount > 0 {
                "ronde \(match.currentRoundIndex + 1) van \(match.roundCount)"
            } else {
                "ronde \(match.currentRoundIndex + 1)"
            }
        }
    }

    private static func reload() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
        #endif
    }
}
