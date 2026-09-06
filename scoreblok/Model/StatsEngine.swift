import Foundation

// MARK: - Periode

enum StatsPeriod: String, CaseIterable, Identifiable {
    case days30 = "30 dagen"
    case days90 = "90 dagen"
    case thisYear = "dit jaar"
    case all = "alles"

    var id: String { rawValue }

    /// Startdatum van de periode; `nil` betekent alles.
    func start(now: Date = .now, calendar: Calendar = .current) -> Date? {
        switch self {
        case .days30: calendar.date(byAdding: .day, value: -30, to: now)
        case .days90: calendar.date(byAdding: .day, value: -90, to: now)
        case .thisYear: calendar.date(from: calendar.dateComponents([.year], from: now))
        case .all: nil
        }
    }

    /// De even lange periode ervóór, om een trend tegen af te zetten.
    func previousRange(now: Date = .now, calendar: Calendar = .current) -> (Date, Date)? {
        guard let start = start(now: now, calendar: calendar) else { return nil }
        let length = now.timeIntervalSince(start)
        return (start.addingTimeInterval(-length), start)
    }
}

// MARK: - Resultaten

struct MatchResult: Identifiable {
    let matchID: UUID
    let gameName: String
    let mono: String
    let date: Date
    let total: Int
    let rank: Int
    let playerCount: Int
    let isWin: Bool

    var id: UUID { matchID }
}

struct PlayerStanding: Identifiable {
    let player: Player
    var played = 0
    var wins = 0
    var rankSum = 0
    var id: UUID { player.id }

    var winRate: Double { played == 0 ? 0 : Double(wins) / Double(played) }
    var averageRank: Double { played == 0 ? 0 : Double(rankSum) / Double(played) }
}

struct Streak {
    let count: Int
    let isWin: Bool

    var short: String { count == 0 ? "—" : "\(count) \(isWin ? "W" : "V")" }
    var long: String {
        count == 0 ? "geen" : "\(count) \(isWin ? (count == 1 ? "gewonnen" : "gewonnen") : "verloren")"
    }
}

struct HeadToHeadLine: Identifiable {
    let gameName: String
    let wins: Int
    let losses: Int
    let averageDifference: Double
    var id: String { gameName }

    var score: String { "\(wins)–\(losses)" }
    var fraction: Double {
        wins + losses == 0 ? 0 : Double(wins) / Double(wins + losses)
    }
}

struct RecordLine: Identifiable {
    let label: String
    let value: String
    let who: String
    var id: String { label }
}

struct MixLine: Identifiable {
    let gameName: String
    let count: Int
    let fraction: Double
    let shift: Int
    var id: String { gameName }
}

struct FormLine: Identifiable {
    let player: Player
    /// Voortschrijdend winstpercentage, oud → nieuw, als 0…1.
    let points: [Double]
    var id: UUID { player.id }

    var last: Double { points.last ?? 0 }
}

// MARK: - Rekenwerk

/// Alles wat de statistiekschermen tonen wordt hier berekend, niet opgeslagen.
enum StatsEngine {

    static func matches(_ all: [Match], in period: StatsPeriod, now: Date = .now) -> [Match] {
        let counted = all.filter(\.counts)
        guard let start = period.start(now: now) else { return counted }
        return counted.filter { ($0.endedAt ?? $0.startedAt) >= start }
    }

    static func previousMatches(_ all: [Match], in period: StatsPeriod, now: Date = .now) -> [Match] {
        guard let (from, to) = period.previousRange(now: now) else { return [] }
        return all.filter(\.counts).filter {
            let date = $0.endedAt ?? $0.startedAt
            return date >= from && date < to
        }
    }

    static func results(for player: Player, in matches: [Match]) -> [MatchResult] {
        matches
            .filter { match in match.players.contains { $0.id == player.id } }
            .sorted { ($0.endedAt ?? $0.startedAt) < ($1.endedAt ?? $1.startedAt) }
            .compactMap { match in
                guard let standing = match.standings.first(where: { $0.player.id == player.id })
                else { return nil }
                return MatchResult(matchID: match.id,
                                   gameName: match.gameName,
                                   mono: match.mono,
                                   date: match.endedAt ?? match.startedAt,
                                   total: standing.total,
                                   rank: standing.rank,
                                   playerCount: match.players.count,
                                   isWin: standing.rank == 1)
            }
    }

    static func standings(for players: [Player], in matches: [Match]) -> [PlayerStanding] {
        var table: [UUID: PlayerStanding] = [:]
        for player in players { table[player.id] = PlayerStanding(player: player) }

        for match in matches {
            for standing in match.standings {
                guard var row = table[standing.player.id] else { continue }
                row.played += 1
                row.rankSum += standing.rank
                if standing.rank == 1 { row.wins += 1 }
                table[standing.player.id] = row
            }
        }

        return players.compactMap { table[$0.id] }
            .filter { $0.played > 0 }
            .sorted { lhs, rhs in
                if lhs.winRate != rhs.winRate { return lhs.winRate > rhs.winRate }
                if lhs.played != rhs.played { return lhs.played > rhs.played }
                return lhs.player.name.localizedStandardCompare(rhs.player.name) == .orderedAscending
            }
    }

    /// Huidige reeks: opeenvolgende winst of verlies, geteld vanaf het laatste potje.
    static func streak(for player: Player, in matches: [Match]) -> Streak {
        let recent = Array(results(for: player, in: matches).reversed())
        guard let first = recent.first else { return Streak(count: 0, isWin: false) }
        var count = 0
        for result in recent {
            guard result.isWin == first.isWin else { break }
            count += 1
        }
        return Streak(count: count, isWin: first.isWin)
    }

    /// Langste reeks gewonnen potjes ooit.
    static func longestWinStreak(for player: Player, in matches: [Match]) -> Int {
        var best = 0, running = 0
        for result in results(for: player, in: matches) {
            running = result.isWin ? running + 1 : 0
            best = max(best, running)
        }
        return best
    }

    /// Aantal verschillende dagen waarop er gespeeld is.
    static func playDays(_ matches: [Match], calendar: Calendar = .current) -> Int {
        Set(matches.map { calendar.startOfDay(for: $0.endedAt ?? $0.startedAt) }).count
    }

    /// Voortschrijdend winstpercentage over de laatste `window` potjes.
    static func formLines(for players: [Player], in matches: [Match],
                          window: Int = 10, limit: Int = 4) -> [FormLine] {
        let ranked = players
            .map { ($0, results(for: $0, in: matches).count) }
            .filter { $0.1 >= 3 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)

        return ranked.compactMap { player in
            let results = results(for: player, in: matches)
            guard results.count >= 2 else { return nil }
            var points: [Double] = []
            for index in results.indices {
                let slice = results[max(0, index - window + 1)...index]
                let wins = slice.filter(\.isWin).count
                points.append(Double(wins) / Double(slice.count))
            }
            return FormLine(player: player, points: Array(points.suffix(window)))
        }
    }

    /// Onderlinge balans van `player` tegen `opponent`, uitgesplitst per spel.
    static func headToHead(_ player: Player, versus opponent: Player,
                           in matches: [Match]) -> [HeadToHeadLine] {
        var table: [String: (w: Int, l: Int, diff: [Int])] = [:]

        for match in matches {
            let standings = match.standings
            guard let mine = standings.first(where: { $0.player.id == player.id }),
                  let theirs = standings.first(where: { $0.player.id == opponent.id })
            else { continue }
            var row = table[match.gameName] ?? (0, 0, [])
            if mine.rank < theirs.rank { row.w += 1 } else if mine.rank > theirs.rank { row.l += 1 }
            row.diff.append(mine.total - theirs.total)
            table[match.gameName] = row
        }

        return table.map { name, row in
            let average = row.diff.isEmpty ? 0
                : Double(row.diff.reduce(0, +)) / Double(row.diff.count)
            return HeadToHeadLine(gameName: name, wins: row.w, losses: row.l,
                                  averageDifference: average)
        }
        .sorted { ($0.wins + $0.losses) > ($1.wins + $1.losses) }
    }

    /// De medespeler met wie `player` het vaakst aan tafel zat.
    static func mostFrequentOpponent(of player: Player, in matches: [Match]) -> Player? {
        var counts: [UUID: (Player, Int)] = [:]
        for match in matches where match.players.contains(where: { $0.id == player.id }) {
            for other in match.players where other.id != player.id {
                let current = counts[other.id]?.1 ?? 0
                counts[other.id] = (other, current + 1)
            }
        }
        return counts.values.max { $0.1 < $1.1 }?.0
    }

    static func records(in matches: [Match]) -> [RecordLine] {
        var lines: [RecordLine] = []

        // Hoogste en laagste eindscore, met het spel erbij.
        var best: (Int, String, String)?
        var worst: (Int, String, String)?
        var widest: (Int, String, String)?
        var shortest: (Int, String)?

        for match in matches where match.mode != .winnerOnly {
            let standings = match.standings
            guard let top = standings.map(\.total).max(),
                  let low = standings.map(\.total).min(),
                  let topPlayer = standings.first(where: { $0.total == top })?.player,
                  let lowPlayer = standings.first(where: { $0.total == low })?.player
            else { continue }

            if best == nil || top > best!.0 { best = (top, match.gameName, topPlayer.name) }
            if worst == nil || low < worst!.0 { worst = (low, match.gameName, lowPlayer.name) }

            if standings.count > 1, let winner = standings.first {
                let gap = abs((standings.last?.total ?? 0) - winner.total)
                if widest == nil || gap > widest!.0 { widest = (gap, match.gameName, winner.player.name) }
            }
        }

        for match in matches {
            let end = match.endedAt ?? match.startedAt
            let minutes = max(Int(end.timeIntervalSince(match.startedAt) / 60), 0)
            if shortest == nil || minutes < shortest!.0 { shortest = (minutes, match.gameName) }
        }

        if let best {
            lines.append(RecordLine(label: "Hoogste score — \(best.1)",
                                    value: format(best.0), who: best.2))
        }
        if let worst {
            lines.append(RecordLine(label: "Laagste score — \(worst.1)",
                                    value: format(worst.0), who: worst.2))
        }

        var longest: (Int, String)?
        let players = Set(matches.flatMap(\.players).map(\.id))
        for match in matches {
            for player in match.players where players.contains(player.id) {
                let run = longestWinStreak(for: player, in: matches)
                if longest == nil || run > longest!.0 { longest = (run, player.name) }
            }
        }
        if let longest, longest.0 > 0 {
            lines.append(RecordLine(label: "Langste winreeks",
                                    value: longest.0 == 1 ? "1 potje" : "\(longest.0) potjes",
                                    who: longest.1))
        }
        if let widest {
            lines.append(RecordLine(label: "Grootste verschil",
                                    value: "\(widest.0) punten", who: widest.2))
        }
        if let shortest {
            lines.append(RecordLine(label: "Kortste potje",
                                    value: "\(shortest.0) minuten", who: shortest.1))
        }
        return lines
    }

    /// Wat er het meest gespeeld wordt, met de verschuiving t.o.v. de vorige periode.
    static func mix(in matches: [Match], previous: [Match]) -> [MixLine] {
        var counts: [String: Int] = [:]
        for match in matches { counts[match.gameName, default: 0] += 1 }
        var before: [String: Int] = [:]
        for match in previous { before[match.gameName, default: 0] += 1 }

        let total = max(matches.count, 1)
        return counts.map { name, count in
            MixLine(gameName: name,
                    count: count,
                    fraction: Double(count) / Double(total),
                    shift: count - (before[name] ?? 0))
        }
        .sorted { $0.count > $1.count }
    }

    /// Potjes per week over het afgelopen jaar, oud → nieuw.
    static func calendar(_ matches: [Match], weeks: Int = 52,
                         now: Date = .now, calendar: Calendar = .current) -> [Int] {
        var buckets = Array(repeating: 0, count: weeks)
        guard let start = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: now)
        else { return buckets }

        for match in matches {
            let date = match.endedAt ?? match.startedAt
            guard date >= start else { continue }
            let weeksSince = calendar.dateComponents([.weekOfYear], from: start, to: date).weekOfYear ?? 0
            let index = min(max(weeksSince, 0), weeks - 1)
            buckets[index] += 1
        }
        return buckets
    }

    private static func format(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - Opmaak

extension Double {
    /// Nederlands decimaalteken, zoals in het ontwerp ("2,3").
    func dutch(_ places: Int = 1) -> String {
        String(format: "%.\(places)f", self).replacingOccurrences(of: ".", with: ",")
    }

    var percentText: String { "\(Int((self * 100).rounded()))%" }
}

extension Int {
    var signedText: String {
        self > 0 ? "+\(self)" : (self < 0 ? "−\(abs(self))" : "0")
    }

    /// "▲ +2", "▼ −3" of "—" voor een trendregel.
    var trendText: String {
        if self == 0 { return "—" }
        return self > 0 ? "▲ +\(self)" : "▼ −\(abs(self))"
    }
}
