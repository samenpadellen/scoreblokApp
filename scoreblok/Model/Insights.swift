import Foundation
import SwiftData

/// Extra statistieken die je vrijspeelt door vaak hetzelfde spel te spelen.
///
/// Patronen uit een paar potjes zijn meestal toeval. Daarom komen ze pas na
/// tien potjes van één spel, vergelijkt elke uitspraak met een controle
/// (dezelfde medespeler elders aan tafel, of wat je bij toeval zou
/// verwachten), en staat er altijd bij over hoeveel potjes het gaat.
@MainActor
enum Insights {
    static let unlockAt = 10

    /// Onder dit aantal potjes per kant van een vergelijking zegt een
    /// verschil te weinig om te tonen. Met drie kwamen er op testdata
    /// meteen uitschieters als +67 procentpunt uit; vijf is strenger, en
    /// dan verschijnen er in het begin minder patronen.
    static let minimumSample = 5

    struct Progress: Identifiable {
        let gameName: String
        let mono: String
        let count: Int

        var id: String { gameName }
        var isUnlocked: Bool { count >= Insights.unlockAt }
        var remaining: Int { max(Insights.unlockAt - count, 0) }
        var fraction: Double { min(Double(count) / Double(Insights.unlockAt), 1) }
    }

    struct Line: Identifiable {
        let id = UUID()
        /// Het getal dat opvalt: "+32", "1,4", "8–2".
        let figure: String
        /// Wat dat getal is: "procentpunt", "jokers per potje".
        let unit: String
        let title: String
        let detail: String
        let players: [Player]
    }

    struct Section: Identifiable {
        let title: String
        let note: String
        let lines: [Line]

        var id: String { title }
    }

    // MARK: - Voortgang

    /// Afgeronde, meetellende potjes van één spel, oudste eerst.
    static func counted(_ matches: [Match], game: String) -> [Match] {
        matches
            .filter { $0.counts && $0.gameName == game }
            .sorted { ($0.endedAt ?? $0.startedAt) < ($1.endedAt ?? $1.startedAt) }
    }

    /// Per spel hoe ver je bent. Vrijgespeeld eerst, dan wie het dichtst bij is.
    static func progress(_ matches: [Match]) -> [Progress] {
        Dictionary(grouping: matches.filter(\.counts), by: \.gameName)
            .map { name, list in
                Progress(gameName: name, mono: list.first?.mono ?? "", count: list.count)
            }
            .sorted { a, b in
                if a.isUnlocked != b.isUnlocked { return a.isUnlocked }
                if a.count != b.count { return a.count > b.count }
                return a.gameName.localizedStandardCompare(b.gameName) == .orderedAscending
            }
    }

    /// Het potje waarmee het spel werd vrijgespeeld: het tiende.
    static func unlockingMatchID(for game: String, in matches: [Match]) -> UUID? {
        let games = counted(matches, game: game)
        return games.count >= unlockAt ? games[unlockAt - 1].id : nil
    }

    // MARK: - Inzichten

    static func sections(for game: String, in matches: [Match]) -> [Section] {
        let games = counted(matches, game: game)
        guard games.count >= unlockAt else { return [] }

        var result: [Section] = []
        let seats = seatLines(games)
        if !seats.isEmpty {
            result.append(Section(
                title: "Wie vóór je zit",
                note: "Winst met een medespeler direct vóór je aan de beurt, vergeleken met diezelfde medespeler ergens anders aan tafel.",
                lines: seats))
        }
        let jokers = jokerLines(games)
        if !jokers.isEmpty {
            result.append(Section(
                title: "Jokers",
                note: "Alleen potjes waarin de jokerteller aanstond.",
                lines: jokers))
        }
        let table = tableLines(games)
        if !table.isEmpty {
            result.append(Section(
                title: "Aan tafel",
                note: "Beginnen en voorstaan, vergeleken met wat je bij toeval zou verwachten.",
                lines: table))
        }
        let rivals = rivalLines(games)
        if !rivals.isEmpty {
            result.append(Section(
                title: "Rivalen",
                note: "Wie het vaakst vóór wie eindigt, in potjes samen.",
                lines: rivals))
        }
        return result
    }

    private static func winnerID(_ match: Match) -> UUID? {
        match.standings.first?.player.id
    }

    private struct Split {
        var withSum = 0.0
        var withCount = 0
        var otherSum = 0.0
        var otherCount = 0

        var withAverage: Double { withSum / Double(max(withCount, 1)) }
        var otherAverage: Double { otherSum / Double(max(otherCount, 1)) }
    }

    /// Per paar (speler, medespeler) een waarde als de medespeler direct vóór
    /// de speler aan de beurt is, en als die ergens anders aan tafel zit.
    private static func predecessorSplits(_ games: [Match],
                                          value: (Match, Player) -> Double?) -> [(Player, Player, Split)] {
        var table: [String: (Player, Player, Split)] = [:]
        for match in games {
            let seats = match.orderedPlayers
            guard seats.count >= 3 else { continue }
            for (index, player) in seats.enumerated() {
                guard let measured = value(match, player) else { continue }
                let before = seats[(index + seats.count - 1) % seats.count]
                for other in seats where other.id != player.id {
                    let key = player.id.uuidString + "|" + other.id.uuidString
                    var row = table[key] ?? (player, other, Split())
                    if other.id == before.id {
                        row.2.withSum += measured
                        row.2.withCount += 1
                    } else {
                        row.2.otherSum += measured
                        row.2.otherCount += 1
                    }
                    table[key] = row
                }
            }
        }
        return table.values.filter {
            $0.2.withCount >= minimumSample && $0.2.otherCount >= minimumSample
        }
    }

    // MARK: Wie vóór je zit

    private static func seatLines(_ games: [Match]) -> [Line] {
        let splits = predecessorSplits(games) { match, player in
            guard let winner = winnerID(match) else { return nil }
            return winner == player.id ? 1 : 0
        }
        var scored: [(Line, Double)] = []
        for entry in splits {
            let (player, other, split) = entry
            let difference = split.withAverage - split.otherAverage
            guard abs(difference) >= 0.15 else { continue }
            let points = Int((abs(difference) * 100).rounded())
            let line = Line(
                figure: (difference > 0 ? "+" : "−") + "\(points)",
                unit: "procentpunt",
                title: difference > 0
                    ? "\(player.name) wint vaker met \(other.name) direct vóór zich"
                    : "\(player.name) wint minder vaak met \(other.name) direct vóór zich",
                detail: "\(split.withAverage.percentText) van \(split.withCount) potjes · anders \(split.otherAverage.percentText) van \(split.otherCount)",
                players: [player, other])
            scored.append((line, abs(difference)))
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(4).map { $0.0 }
    }

    // MARK: Jokers

    private static func jokerLines(_ games: [Match]) -> [Line] {
        let counted = games.filter(\.tracksJokers)
        guard counted.count >= minimumSample else { return [] }

        var scored: [(Line, Double)] = []
        let splits = predecessorSplits(counted) { match, player in
            Double(match.totalJokers(for: player))
        }
        for entry in splits {
            let (player, other, split) = entry
            let difference = split.withAverage - split.otherAverage
            guard abs(difference) >= 0.5 else { continue }
            let line = Line(
                figure: (difference > 0 ? "+" : "−") + abs(difference).dutch(1),
                unit: "jokers per potje",
                title: difference > 0
                    ? "\(player.name) krijgt meer jokers met \(other.name) direct vóór zich"
                    : "\(player.name) krijgt minder jokers met \(other.name) direct vóór zich",
                detail: "\(split.withAverage.dutch(1)) per potje over \(split.withCount) · anders \(split.otherAverage.dutch(1)) over \(split.otherCount)",
                players: [player, other])
            scored.append((line, abs(difference)))
        }
        var result = scored.sorted { $0.1 > $1.1 }.prefix(3).map { $0.0 }

        // Het verschil tussen wie gemiddeld de meeste en de minste jokers krijgt.
        var perPlayer: [UUID: (player: Player, jokers: Int, matches: Int)] = [:]
        for match in counted {
            for player in match.players {
                var row = perPlayer[player.id] ?? (player, 0, 0)
                row.jokers += match.totalJokers(for: player)
                row.matches += 1
                perPlayer[player.id] = row
            }
        }
        let averages = perPlayer.values
            .filter { $0.matches >= minimumSample }
            .map { (player: $0.player, average: Double($0.jokers) / Double($0.matches), matches: $0.matches) }
            .sorted { $0.average > $1.average }
        if let top = averages.first, let bottom = averages.last,
           top.player.id != bottom.player.id, top.average - bottom.average >= 0.3 {
            result.insert(Line(
                figure: "+" + (top.average - bottom.average).dutch(1),
                unit: "jokers per potje",
                title: "\(top.player.name) krijgt meer jokers dan \(bottom.player.name)",
                detail: "\(top.average.dutch(1)) tegen \(bottom.average.dutch(1)) per potje · over \(top.matches) en \(bottom.matches) potjes",
                players: [top.player, bottom.player]), at: 0)
        }
        return result
    }

    // MARK: Aan tafel

    private static func tableLines(_ games: [Match]) -> [Line] {
        var lines: [Line] = []

        // Wie begint.
        var starts = 0
        var startWins = 0
        var startChance = 0.0
        for match in games {
            let seats = match.orderedPlayers
            guard seats.count >= 2, !match.seatOrder.isEmpty, let winner = winnerID(match) else { continue }
            starts += 1
            startChance += 1 / Double(seats.count)
            if seats[0].id == winner { startWins += 1 }
        }
        if starts >= unlockAt / 2 {
            let rate = Double(startWins) / Double(starts)
            let chance = startChance / Double(starts)
            lines.append(Line(
                figure: rate.percentText,
                unit: "wint wie begint",
                title: rate >= chance ? "Wie begint, wint vaker dan toeval" : "Wie begint, wint minder vaak dan toeval",
                detail: "\(startWins) van \(starts) potjes · bij toeval \(chance.percentText)",
                players: []))
        }

        // Wie halverwege voorstaat.
        var halfway = 0
        var held = 0
        var halfwayChance = 0.0
        for match in games where match.mode == .roundsCumulative {
            let rounds = match.orderedRounds
            let seats = match.orderedPlayers
            guard rounds.count >= 2, seats.count >= 2, let winner = winnerID(match) else { continue }
            let half = rounds.count / 2
            let totals = seats.map { (player: $0, total: match.cumulative(for: $0)[half]) }
            let values = totals.map { $0.total }
            guard let best = match.winsByLowest ? values.min() : values.max() else { continue }
            let leaders = totals.filter { $0.total == best }
            // Gedeelde leiding zegt niets over wie standhoudt.
            guard leaders.count == 1 else { continue }
            halfway += 1
            halfwayChance += 1 / Double(seats.count)
            if leaders[0].player.id == winner { held += 1 }
        }
        if halfway >= unlockAt / 2 {
            let rate = Double(held) / Double(halfway)
            let chance = halfwayChance / Double(halfway)
            lines.append(Line(
                figure: rate.percentText,
                unit: "houdt stand",
                title: "Wie halverwege voorstaat, wint \(rate.percentText) van de potjes",
                detail: "\(held) van \(halfway) potjes · bij toeval \(chance.percentText)",
                players: []))
        }
        return lines
    }

    // MARK: Rivalen

    private static func rivalLines(_ games: [Match]) -> [Line] {
        var table: [String: (a: Player, b: Player, aAhead: Int, together: Int)] = [:]
        for match in games {
            let standings = match.standings
            for (index, first) in standings.enumerated() {
                for second in standings[(index + 1)...] {
                    let (a, b) = first.player.id.uuidString < second.player.id.uuidString
                        ? (first, second) : (second, first)
                    let key = a.player.id.uuidString + "|" + b.player.id.uuidString
                    var row = table[key] ?? (a.player, b.player, 0, 0)
                    row.together += 1
                    if a.rank < b.rank { row.aAhead += 1 }
                    table[key] = row
                }
            }
        }

        var scored: [(line: Line, fraction: Double, together: Int)] = []
        for row in table.values where row.together >= 5 {
            let aLeads = row.aAhead * 2 >= row.together
            let leader = aLeads ? row.a : row.b
            let trailer = aLeads ? row.b : row.a
            let ahead = aLeads ? row.aAhead : row.together - row.aAhead
            let fraction = Double(ahead) / Double(row.together)
            guard fraction >= 0.7 else { continue }
            scored.append((Line(
                figure: "\(ahead)–\(row.together - ahead)",
                unit: "potjes samen",
                title: "\(leader.name) eindigt meestal vóór \(trailer.name)",
                detail: "in \(fraction.percentText) van \(row.together) potjes samen",
                players: [leader, trailer]), fraction, row.together))
        }
        return scored
            .sorted { $0.fraction != $1.fraction ? $0.fraction > $1.fraction : $0.together > $1.together }
            .prefix(3)
            .map { $0.line }
    }
}
