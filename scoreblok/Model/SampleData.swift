import Foundation
import SwiftData

/// Een paar maanden speelavonden, zodat de trends meteen iets laten zien.
/// De cijfers komen uit het ontwerp; de rest is deterministisch afgeleid.
enum SampleData {

    private static var seed: UInt64 = 20_260_906

    private static func next(_ bound: Int) -> Int {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((seed >> 33) % UInt64(max(bound, 1)))
    }

    /// Verdeelt een eindtotaal deterministisch over `count` rondes.
    private static func split(_ total: Int, over count: Int) -> [Int] {
        guard count > 1 else { return [total] }
        var parts: [Int] = []
        var left = total
        for index in 0..<(count - 1) {
            let remaining = count - index
            let average = max(left / remaining, 0)
            let jitter = average > 3 ? next(average) - average / 2 : 0
            let value = max(min(average + jitter, left), 0)
            parts.append(value)
            left -= value
        }
        parts.append(max(left, 0))
        return parts
    }

    static func populate(in context: ModelContext) {
        seed = 20_260_906
        BuiltInGames.seedIfNeeded(in: context)

        let templates = (try? context.fetch(FetchDescriptor<GameTemplate>())) ?? []
        func template(_ name: String) -> GameTemplate? { templates.first { $0.name == name } }

        let roster: [(String, Int, Bool)] = [
            ("Sanne", 0, true), ("Joost", 1, false), ("Mila", 2, false),
            ("Bram", 3, false), ("Femke", 4, false), ("Teun", 5, false)
        ]
        var people: [String: Player] = [:]
        for (name, ramp, isMe) in roster {
            let player = Player(name: name, rampIndex: ramp, isMe: isMe)
            context.insert(player)
            people[name] = player
        }

        // Afgeronde potjes: (spel, dagen geleden, minuten, [(speler, totaal)], rondes)
        let played: [(String, Int, Int, [(String, Int)], Int)] = [
            ("Jokeren",      1, 41, [("Mila", 31), ("Sanne", 38), ("Bram", 49), ("Joost", 53)], 9),
            ("Keer op Keer", 3, 28, [("Joost", 52), ("Sanne", 41), ("Mila", 37)], 0),
            ("Rummikub",     7, 52, [("Mila", 61), ("Sanne", 88), ("Teun", 94), ("Joost", 131)], 6),
            ("Toepen",      13, 19, [("Sanne", 6), ("Joost", 10), ("Bram", 10)], 4),
            ("Jokeren",     16, 44, [("Joost", 36), ("Sanne", 44), ("Femke", 58), ("Mila", 60)], 9),
            ("Rummikub",    24, 47, [("Sanne", 54), ("Joost", 77), ("Mila", 81)], 5),
            ("Klaverjassen", 31, 63, [("Sanne", 1642), ("Joost", 1488), ("Mila", 1301), ("Bram", 1120)], 16),
            ("Jokeren",     38, 39, [("Sanne", 29), ("Mila", 41), ("Joost", 46), ("Teun", 55)], 9),
            ("Keer op Keer", 45, 26, [("Mila", 48), ("Sanne", 44), ("Bram", 39)], 0),
            ("Kolonisten",  52, 71, [("Joost", 10), ("Sanne", 9), ("Femke", 8), ("Mila", 7)], 1),
            ("Jokeren",     60, 43, [("Sanne", 33), ("Joost", 37), ("Mila", 52), ("Bram", 58)], 9),
            ("Rummikub",    74, 55, [("Joost", 66), ("Sanne", 72), ("Teun", 90)], 6),
            ("Toepen",      88, 22, [("Mila", 4), ("Sanne", 10), ("Femke", 10)], 3),
            ("Jokeren",    103, 40, [("Sanne", 35), ("Bram", 44), ("Joost", 51)], 9),
            ("Keer op Keer", 121, 31, [("Sanne", 57), ("Joost", 45)], 0)
        ]

        for (gameName, daysAgo, minutes, scores, roundCount) in played {
            guard let tpl = template(gameName) else { continue }
            let participants = scores.compactMap { people[$0.0] }
            guard participants.count == scores.count else { continue }

            let match = Match(template: tpl)
            context.insert(match)
            match.seat(participants)
            let start = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
            match.startedAt = start
            match.endedAt = start.addingTimeInterval(Double(minutes) * 60)

            if tpl.mode == .scorecard, let spec = tpl.scorecard {
                for (index, entry) in scores.enumerated() {
                    let card = ScoreCard(playerID: participants[index].id)
                    context.insert(card)
                    fill(card, to: entry.1, spec: spec)
                    card.match = match
                    match.cards.append(card)
                }
            } else {
                let rows = tpl.mode == .finalScore ? 1 : max(roundCount, 1)
                var columns: [[Int]] = []
                for entry in scores { columns.append(split(entry.1, over: rows)) }
                for roundIndex in 0..<rows {
                    let round = MatchRound(index: roundIndex)
                    context.insert(round)
                    round.createdAt = start.addingTimeInterval(Double(roundIndex) * 240)
                    round.match = match
                    match.rounds.append(round)
                    for (index, player) in participants.enumerated() {
                        round.setValue(columns[index][roundIndex], for: player.id, in: context)
                    }
                }
            }
        }

        // Eén afgebroken potje — telt nergens mee, staat wel in de historie.
        if let pesten = template("Pesten") {
            let participants = ["Femke", "Bram", "Sanne"].compactMap { people[$0] }
            let match = Match(template: pesten)
            context.insert(match)
            match.seat(participants)
            let start = Calendar.current.date(byAdding: .day, value: -20, to: .now) ?? .now
            match.startedAt = start
            match.abandonedAt = start.addingTimeInterval(14 * 60)
            match.endedAt = match.abandonedAt
            let round = MatchRound(index: 0)
            context.insert(round)
            round.match = match
            match.rounds.append(round)
            for (index, player) in participants.enumerated() {
                round.setValue(index + 1, for: player.id, in: context)
            }
        }

        // Een lopend potje, precies de stand uit het ontwerp.
        if let jokeren = template("Jokeren") {
            let order = ["Sanne", "Joost", "Mila", "Bram"].compactMap { people[$0] }
            let match = Match(template: jokeren)
            context.insert(match)
            match.seat(order)
            match.startedAt = Calendar.current.date(byAdding: .minute, value: -52, to: .now) ?? .now
            let table: [[Int]] = [[12, 4, 22], [30, 8, 15], [4, 18, 9], [21, 25, 3]]
            for roundIndex in 0..<3 {
                let round = MatchRound(index: roundIndex)
                context.insert(round)
                round.createdAt = match.startedAt.addingTimeInterval(Double(roundIndex) * 600)
                round.match = match
                match.rounds.append(round)
                for (index, player) in order.enumerated() {
                    round.setValue(table[index][roundIndex], for: player.id, in: context)
                }
            }
        }
    }

    /// Vinkt kolommen aan tot de kaart ongeveer op `target` uitkomt.
    private static func fill(_ card: ScoreCard, to target: Int, spec: ScorecardSpec) {
        var running = 0
        var keys: [String] = []

        for column in spec.columns where column.kind == .toggle {
            if running + column.value <= target {
                keys.append(column.key)
                running += column.value
            }
        }
        card.columnKeys = keys

        var bonusKeys: [String] = []
        for bonus in spec.bonuses where running + bonus.value <= target {
            bonusKeys.append(bonus.key)
            running += bonus.value
        }
        card.bonusKeys = bonusKeys

        // Getalcategorieën vullen de rest op.
        let numberColumns = spec.columns.filter { $0.kind == .number }
        if !numberColumns.isEmpty {
            let parts = split(max(target - running, 0), over: numberColumns.count)
            var numbers: [String: Int] = [:]
            for (index, column) in numberColumns.enumerated() { numbers[column.key] = parts[index] }
            card.numbers = numbers
            running = target
        }

        if spec.hasPenalty, running > target {
            card.penaltyCount = min((running - target) / abs(spec.penaltyPerUnit), spec.penaltyMax)
        }
    }
}
