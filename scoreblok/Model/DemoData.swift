import Foundation
import SwiftData

/// Voorbeeldpotjes: een gevuld blok om de app te leren kennen of te laten
/// zien, ook aan wie de app beoordeelt, zonder eerst tien potjes te spelen.
/// Alles wat hier wordt aangemaakt wordt onthouden en is met één tik weer weg.
/// Eigen spelers en potjes blijven altijd staan.
@MainActor
enum DemoData {
    static let matchesKey = "voorbeeld.potjes"
    static let playersKey = "voorbeeld.spelers"

    /// Welke spellen en hoe vaak. Tien keer Jokeren speelt meteen de extra
    /// statistieken voor Jokeren vrij.
    private static let plan: [(game: String, count: Int)] = [
        ("Jokeren", 10), ("Klaverjassen", 4), ("Rummikub", 3)
    ]
    private static let names = ["Sanne", "Daan", "Noor", "Milan"]

    static var isPresent: Bool {
        !(UserDefaults.standard.string(forKey: matchesKey) ?? "").isEmpty
    }

    /// Vult de app aan tot vier spelers en zeventien afgeronde potjes, verspreid
    /// over de afgelopen tien weken. Geeft het aantal potjes terug.
    @discardableResult
    static func fill(in context: ModelContext) -> Int {
        let templates = ((try? context.fetch(FetchDescriptor<GameTemplate>())) ?? []).filter { !$0.isDeleted }
        var players = ((try? context.fetch(FetchDescriptor<Player>())) ?? []).filter { !$0.isArchived && !$0.isDeleted }
        var newPlayers: [UUID] = []
        for name in names where players.count < 4 {
            let taken = players.contains {
                SamenExchange.normalized($0.name) == SamenExchange.normalized(name)
            }
            guard !taken else { continue }
            let player = Player(name: name, rampIndex: players.count % M.playerRamp.count)
            context.insert(player)
            players.append(player)
            newPlayers.append(player.id)
        }
        let me = players.first(where: \.isMe)

        let games = plan.flatMap { Array(repeating: $0.game, count: $0.count) }.shuffled()
        let calendar = Calendar.current
        var newMatches: [UUID] = []

        for (index, game) in games.enumerated() {
            guard let template = templates.first(where: { $0.name == game }) else { continue }
            let size = min(template.maxPlayers, players.count, max(template.minPlayers, Int.random(in: 3...4)))
            guard size >= template.minPlayers else { continue }

            var table = Array(players.shuffled().prefix(size))
            if let me, !table.contains(where: { $0.id == me.id }) { table[0] = me }

            let daysAgo = Int(Double(games.count - index) * 70 / Double(games.count))
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
            let start = calendar.date(bySettingHour: Int.random(in: 19...21),
                                      minute: [0, 15, 30, 45].randomElement() ?? 0,
                                      second: 0, of: day) ?? day

            let match = Match(template: template)
            context.insert(match)
            match.seat(table)
            match.tracksJokers = template.supportsJokers

            let roundTotal = template.roundCount > 0 ? template.roundCount : 5
            for number in 0..<roundTotal {
                let round = MatchRound(index: number)
                round.createdAt = start.addingTimeInterval(Double(number) * 480)
                context.insert(round)
                round.match = match
                match.rounds.append(round)

                let out = Int.random(in: 0..<table.count)
                for (seat, player) in table.enumerated() {
                    let value = template.winsByLowest
                        ? (seat == out ? 0 : Int.random(in: 3...45))
                        : Int.random(in: 20...162)
                    round.setValue(value, for: player.id, in: context)
                    if match.tracksJokers, seat != out, Int.random(in: 0...2) == 0 {
                        round.setJokers(Int.random(in: 1...2), for: player.id, in: context)
                    }
                }
            }

            let end = start.addingTimeInterval(Double(roundTotal) * 480 + Double(Int.random(in: 60...600)))
            match.startedAt = start
            match.lastPlayedAt = end
            match.endedAt = end
            newMatches.append(match.id)
        }

        remember(newMatches, key: matchesKey)
        remember(newPlayers, key: playersKey)
        Storage.save(context)
        return newMatches.count
    }

    /// Haalt de voorbeeldpotjes weg, en de voorbeeldspelers die nergens anders
    /// in meespeelden. Geeft het aantal verwijderde potjes terug.
    @discardableResult
    static func remove(in context: ModelContext) -> Int {
        let matchIDs = Set(ids(matchesKey))
        let playerIDs = Set(ids(playersKey))
        let matches = (try? context.fetch(FetchDescriptor<Match>())) ?? []

        var removed = 0
        for match in matches where matchIDs.contains(match.id) && !match.isDeleted {
            context.delete(match)
            removed += 1
        }
        let remaining = matches.filter { !matchIDs.contains($0.id) && !$0.isDeleted }
        for player in (try? context.fetch(FetchDescriptor<Player>())) ?? [] where playerIDs.contains(player.id) {
            let playsElsewhere = remaining.contains { match in match.players.contains { $0.id == player.id } }
            if !playsElsewhere { context.delete(player) }
        }

        UserDefaults.standard.removeObject(forKey: matchesKey)
        UserDefaults.standard.removeObject(forKey: playersKey)
        Storage.save(context)
        return removed
    }

    private static func ids(_ key: String) -> [UUID] {
        (UserDefaults.standard.string(forKey: key) ?? "")
            .split(separator: ",")
            .compactMap { UUID(uuidString: String($0)) }
    }

    private static func remember(_ new: [UUID], key: String) {
        let all = ids(key) + new
        UserDefaults.standard.set(all.map(\.uuidString).joined(separator: ","), forKey: key)
    }
}
