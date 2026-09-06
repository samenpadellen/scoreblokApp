import Foundation
import SwiftUI
import SwiftData

// MARK: - Speler

@Model
final class Player {
    var id: UUID = UUID()
    var name: String = ""
    /// Index in de neutrale ramp. Kleur is nooit het enige signaal.
    var rampIndex: Int = 0
    /// De meetkundige vorm van de speler; wordt willekeurig gekozen en is het
    /// tweede signaal naast de kleur.
    var avatarIndex: Int = 0
    /// De eigenaar van dit blok — "dat ben jij" in de spelerslijst.
    var isMe: Bool = false
    /// Verwijderen bestaat niet; archiveren wel.
    var isArchived: Bool = false
    var createdAt: Date = Date.now

    var matches: [Match] = []

    init(name: String, rampIndex: Int, avatarIndex: Int? = nil, isMe: Bool = false) {
        self.id = UUID()
        self.name = name
        self.rampIndex = rampIndex
        self.avatarIndex = avatarIndex ?? Int.random(in: 0..<AvatarShape.count)
        self.isMe = isMe
        self.createdAt = .now
    }

    var initial: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    var color: Color { Color(hex: M.playerRamp[rampIndex % M.playerRamp.count].bg) }
    var inkColor: Color { Color(hex: M.playerRamp[rampIndex % M.playerRamp.count].ink) }
}

// MARK: - Spel-sjabloon

@Model
final class GameTemplate {
    var id: UUID = UUID()
    var name: String = ""
    var mono: String = ""
    var modeRaw: String = ScoringMode.roundsCumulative.rawValue
    /// 0 betekent open einde — het potje loopt door tot je het afrondt.
    var roundCount: Int = 0
    var winsByLowest: Bool = true
    var allowNegative: Bool = false
    var minPlayers: Int = 2
    var maxPlayers: Int = 8
    /// Grens waarboven een speler afvalt (alleen bij de modus Afvallen).
    var eliminationLimit: Int = 10
    var scorecardData: Data?
    /// Opdracht per ronde, bijvoorbeeld "Drie op een rij". Leeg laat de app
    /// gewoon rondenummers tonen.
    var roundLabels: [String] = []
    /// Of dit spel de jokerteller kan aanbieden bij het opzetten.
    var supportsJokers: Bool = false
    var isBuiltIn: Bool = false
    /// Letterlijke ondertitel uit het sjabloon; leeg laat de app hem afleiden.
    var subtitleNote: String = ""
    var sortIndex: Int = 0
    var createdAt: Date = Date.now

    init(name: String,
         mono: String,
         mode: ScoringMode,
         roundCount: Int = 0,
         winsByLowest: Bool = true,
         allowNegative: Bool = false,
         minPlayers: Int = 2,
         maxPlayers: Int = 8,
         eliminationLimit: Int = 10,
         scorecard: ScorecardSpec? = nil,
         roundLabels: [String] = [],
         supportsJokers: Bool = false,
         isBuiltIn: Bool = false,
         subtitleNote: String = "",
         sortIndex: Int = 0) {
        self.id = UUID()
        self.name = name
        self.mono = mono
        self.modeRaw = mode.rawValue
        self.roundCount = roundCount
        self.winsByLowest = winsByLowest
        self.allowNegative = allowNegative
        self.minPlayers = minPlayers
        self.maxPlayers = maxPlayers
        self.eliminationLimit = eliminationLimit
        self.scorecardData = scorecard?.encoded()
        self.roundLabels = roundLabels
        self.supportsJokers = supportsJokers
        self.isBuiltIn = isBuiltIn
        self.subtitleNote = subtitleNote
        self.sortIndex = sortIndex
        self.createdAt = .now
    }

    var mode: ScoringMode {
        get { ScoringMode(rawValue: modeRaw) ?? .roundsCumulative }
        set { modeRaw = newValue.rawValue }
    }

    var scorecard: ScorecardSpec? { ScorecardSpec.decode(scorecardData) }

    /// De regel onder de naam in de spellenlijst.
    var subtitle: String {
        if !subtitleNote.isEmpty { return subtitleNote }
        switch mode {
        case .roundsCumulative:
            let rounds = roundCount == 0 ? "open einde" : "\(roundCount) rondes"
            return "\(rounds) · \(winsByLowest ? "laagste" : "hoogste") wint"
        case .winnerOnly:
            return "alleen eindvolgorde"
        case .scorecard:
            let count = scorecard?.columns.count ?? 0
            return "scorekaart · \(count) categorieën"
        case .finalScore:
            return "één eindscore · \(winsByLowest ? "laagste" : "hoogste") wint"
        case .elimination:
            return "afvallen bij \(eliminationLimit)"
        }
    }
}

// MARK: - Potje

@Model
final class Match {
    var id: UUID = UUID()

    // Bevroren kopie van het sjabloon: pas je het spel later aan, dan
    // verandert deze historie niet mee.
    var gameName: String = ""
    var mono: String = ""
    var modeRaw: String = ScoringMode.roundsCumulative.rawValue
    var roundCount: Int = 0
    var winsByLowest: Bool = true
    var allowNegative: Bool = false
    var eliminationLimit: Int = 10
    var scorecardData: Data?
    var roundLabels: [String] = []
    /// Aangezet bij het opzetten: naast de punten houd je per ronde bij
    /// hoeveel jokers iemand had.
    var tracksJokers: Bool = false

    var startedAt: Date = Date.now
    /// Wanneer er voor het laatst iets is ingevuld. Bepaalt de volgorde van
    /// open potjes en de tekst "waar je gebleven was".
    var lastPlayedAt: Date = Date.now
    var endedAt: Date?
    /// Afgebroken potjes tellen nergens mee.
    var abandonedAt: Date?
    var seatOrder: [String] = []

    @Relationship(inverse: \Player.matches)
    var players: [Player] = []

    @Relationship(deleteRule: .cascade, inverse: \MatchRound.match)
    var rounds: [MatchRound] = []

    @Relationship(deleteRule: .cascade, inverse: \ScoreCard.match)
    var cards: [ScoreCard] = []

    init(template: GameTemplate) {
        self.id = UUID()
        self.gameName = template.name
        self.mono = template.mono
        self.modeRaw = template.modeRaw
        self.roundCount = template.roundCount
        self.winsByLowest = template.winsByLowest
        self.allowNegative = template.allowNegative
        self.eliminationLimit = template.eliminationLimit
        self.scorecardData = template.scorecardData
        self.roundLabels = template.roundLabels
        self.startedAt = .now
        self.lastPlayedAt = .now
    }

    /// Koppelt de deelnemers en legt de zitvolgorde vast. Roep dit pas aan
    /// nadat het potje in de context zit, anders raakt de relatie zoek.
    func seat(_ players: [Player]) {
        self.players = players
        self.seatOrder = players.map { $0.id.uuidString }
    }

    var mode: ScoringMode { ScoringMode(rawValue: modeRaw) ?? .roundsCumulative }
    var scorecard: ScorecardSpec? { ScorecardSpec.decode(scorecardData) }

    var isFinished: Bool { endedAt != nil }
    /// Een potje dat nog loopt: je kunt er dagen later mee verder.
    var isOpen: Bool { endedAt == nil && abandonedAt == nil }

    /// Stempelt het potje zodra er iets verandert.
    func touch() { lastPlayedAt = .now }

    /// "vandaag 19:12", "gisteren", "3 dagen geleden".
    var lastPlayedText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(lastPlayedAt) {
            return "vandaag \(lastPlayedAt.formatted(.dateTime.hour().minute()))"
        }
        if calendar.isDateInYesterday(lastPlayedAt) {
            return "gisteren \(lastPlayedAt.formatted(.dateTime.hour().minute()))"
        }
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: lastPlayedAt),
                                           to: calendar.startOfDay(for: .now)).day ?? 0
        if days < 7 { return "\(days) dagen geleden" }
        return lastPlayedAt.formatted(.dateTime.day().month(.abbreviated))
    }
    var isAbandoned: Bool { abandonedAt != nil }
    /// Alleen afgeronde, niet-afgebroken potjes tellen mee in de statistieken.
    var counts: Bool { isFinished && !isAbandoned }

    var orderedPlayers: [Player] {
        let order = seatOrder
        return players.sorted { a, b in
            let ia = order.firstIndex(of: a.id.uuidString) ?? Int.max
            let ib = order.firstIndex(of: b.id.uuidString) ?? Int.max
            if ia == ib { return a.name.localizedStandardCompare(b.name) == .orderedAscending }
            return ia < ib
        }
    }

    var orderedRounds: [MatchRound] { rounds.sorted { $0.index < $1.index } }

    /// Hoeveel rijen het bord toont: het sjabloon, of bij open einde de
    /// gespeelde rondes plus één lege.
    var displayedRoundCount: Int {
        if mode == .finalScore { return 1 }
        if roundCount > 0 { return roundCount }
        return max(rounds.count + 1, 1)
    }

    /// De opdracht van een ronde, als het spel die kent.
    func roundLabel(at index: Int) -> String? {
        guard roundLabels.indices.contains(index) else { return nil }
        return roundLabels[index]
    }

    var hasRoundLabels: Bool { !roundLabels.isEmpty }

    func round(at index: Int) -> MatchRound? {
        rounds.first { $0.index == index }
    }

    func value(round index: Int, player: Player) -> Int? {
        round(at: index)?.value(for: player.id)
    }

    func jokers(round index: Int, player: Player) -> Int {
        round(at: index)?.jokers(for: player.id) ?? 0
    }

    /// Alle jokers van deze speler in dit potje.
    func totalJokers(for player: Player) -> Int {
        rounds.reduce(0) { $0 + $1.jokers(for: player.id) }
    }

    func card(for player: Player) -> ScoreCard? {
        cards.first { $0.playerID == player.id }
    }

    /// Het totaal waarop de stand berust — afhankelijk van de modus.
    func total(for player: Player) -> Int {
        switch mode {
        case .scorecard:
            return card(for: player)?.total(spec: scorecard ?? .empty) ?? 0
        case .winnerOnly:
            return value(round: 0, player: player) ?? 0
        default:
            return rounds.reduce(0) { $0 + ($1.value(for: player.id) ?? 0) }
        }
    }

    /// Lopend totaal na elke ronde, beginnend bij 0.
    func cumulative(for player: Player) -> [Int] {
        var running = 0
        var series = [0]
        for round in orderedRounds {
            running += round.value(for: player.id) ?? 0
            series.append(running)
        }
        return series
    }

    func isEliminated(_ player: Player) -> Bool {
        mode == .elimination && total(for: player) >= eliminationLimit
    }

    /// Bij winnaar-alleen is een laag getal beter; verder volgt het de regel.
    private var lowerWins: Bool {
        mode == .winnerOnly ? true : winsByLowest
    }

    var standings: [Standing] {
        let scored = orderedPlayers.map { (player: $0, total: total(for: $0)) }
        let sorted = scored.sorted { lhs, rhs in
            if mode == .elimination {
                let lo = isEliminated(lhs.player), ro = isEliminated(rhs.player)
                if lo != ro { return !lo }
            }
            if lhs.total != rhs.total {
                return lowerWins ? lhs.total < rhs.total : lhs.total > rhs.total
            }
            return lhs.player.name.localizedStandardCompare(rhs.player.name) == .orderedAscending
        }
        return sorted.enumerated().map { index, item in
            let played = orderedRounds.compactMap { $0.value(for: item.player.id) }
            return Standing(player: item.player,
                            total: item.total,
                            rank: index + 1,
                            roundsPlayed: played.count,
                            bestRound: played.min(),
                            isEliminated: isEliminated(item.player))
        }
    }

    var winner: Player? { standings.first?.player }

    func rank(of player: Player) -> Int? {
        standings.first { $0.player.id == player.id }?.rank
    }

    /// Ronde-index waar de invoer nu staat: de eerste onvolledige ronde.
    var currentRoundIndex: Int {
        let limit = displayedRoundCount
        for index in 0..<max(limit, 1) where !isRoundFilled(index) { return index }
        return max(limit - 1, 0)
    }

    func isRoundFilled(_ index: Int) -> Bool {
        guard let round = round(at: index) else { return false }
        return orderedPlayers.allSatisfy { round.value(for: $0.id) != nil }
    }

    var durationText: String {
        let end = endedAt ?? abandonedAt ?? .now
        let minutes = max(Int(end.timeIntervalSince(startedAt) / 60), 0)
        return "\(minutes) min"
    }
}

struct Standing: Identifiable {
    let player: Player
    let total: Int
    let rank: Int
    let roundsPlayed: Int
    let bestRound: Int?
    let isEliminated: Bool

    var id: UUID { player.id }

    var average: Double {
        roundsPlayed == 0 ? 0 : Double(total) / Double(roundsPlayed)
    }
}

// MARK: - Ronde

@Model
final class MatchRound {
    var index: Int = 0
    var createdAt: Date = Date.now
    var match: Match?

    @Relationship(deleteRule: .cascade, inverse: \ScoreEntry.round)
    var entries: [ScoreEntry] = []

    init(index: Int) {
        self.index = index
        self.createdAt = .now
    }

    func value(for playerID: UUID) -> Int? {
        entries.first { $0.playerID == playerID }?.value
    }

    func setValue(_ value: Int?, for playerID: UUID, in context: ModelContext) {
        entry(for: playerID, in: context).value = value
    }

    func jokers(for playerID: UUID) -> Int {
        entries.first { $0.playerID == playerID }?.jokers ?? 0
    }

    func setJokers(_ count: Int, for playerID: UUID, in context: ModelContext) {
        entry(for: playerID, in: context).jokers = max(0, count)
    }

    private func entry(for playerID: UUID, in context: ModelContext) -> ScoreEntry {
        if let existing = entries.first(where: { $0.playerID == playerID }) { return existing }
        let created = ScoreEntry(playerID: playerID, value: nil)
        context.insert(created)
        entries.append(created)
        return created
    }
}

@Model
final class ScoreEntry {
    var playerID: UUID = UUID()
    /// Leeg blijft leeg: een niet-ingevulde cel is niet hetzelfde als nul.
    var value: Int?
    /// Aantal jokers dat deze speler in deze ronde had.
    var jokers: Int = 0
    var round: MatchRound?

    init(playerID: UUID, value: Int?) {
        self.playerID = playerID
        self.value = value
    }
}

// MARK: - Scorekaart

@Model
final class ScoreCard {
    var playerID: UUID = UUID()
    /// Aangevinkte toggle-kolommen.
    var columnKeys: [String] = []
    /// Aangevinkte bonussen.
    var bonusKeys: [String] = []
    /// Ingetikte getallen per kolom, als JSON.
    var numbersData: Data?
    var penaltyCount: Int = 0
    var match: Match?

    init(playerID: UUID) {
        self.playerID = playerID
    }

    var numbers: [String: Int] {
        get {
            guard let numbersData,
                  let decoded = try? JSONDecoder().decode([String: Int].self, from: numbersData)
            else { return [:] }
            return decoded
        }
        set { numbersData = try? JSONEncoder().encode(newValue) }
    }

    func columnPoints(spec: ScorecardSpec) -> Int {
        spec.columns.reduce(0) { sum, column in
            switch column.kind {
            case .toggle:
                return sum + (columnKeys.contains(column.key) ? column.value : 0)
            case .number:
                return sum + (numbers[column.key] ?? 0)
            }
        }
    }

    func bonusPoints(spec: ScorecardSpec) -> Int {
        spec.bonuses.reduce(0) { $0 + (bonusKeys.contains($1.key) ? $1.value : 0) }
    }

    func sectionBonusPoints(spec: ScorecardSpec) -> Int {
        guard let rule = spec.sectionBonus else { return 0 }
        let sum = spec.columns
            .filter { $0.section == rule.section }
            .reduce(0) { total, column in
                switch column.kind {
                case .toggle: return total + (columnKeys.contains(column.key) ? column.value : 0)
                case .number: return total + (numbers[column.key] ?? 0)
                }
            }
        return sum >= rule.threshold ? rule.bonus : 0
    }

    func penaltyPoints(spec: ScorecardSpec) -> Int {
        penaltyCount * spec.penaltyPerUnit
    }

    func total(spec: ScorecardSpec) -> Int {
        columnPoints(spec: spec) + bonusPoints(spec: spec)
            + sectionBonusPoints(spec: spec) + penaltyPoints(spec: spec)
    }
}
