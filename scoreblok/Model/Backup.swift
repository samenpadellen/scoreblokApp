import Foundation
import SwiftData

/// Een volledige reservekopie van het blok als één leesbaar bestand. Dit is
/// de vangnetlaag onder iCloud en de lokale winkel: wat hier in staat kun je
/// altijd terugzetten, ook op een ander apparaat of na een herinstallatie.
struct BackupDocument: Codable {
    var version = 1
    var createdAt = Date.now
    var players: [PlayerData] = []
    var templates: [TemplateData] = []
    var matches: [MatchData] = []

    struct PlayerData: Codable {
        var id: UUID
        var name: String
        var rampIndex: Int
        var avatarIndex: Int
        var isMe: Bool
        var isArchived: Bool
        var createdAt: Date
    }

    struct TemplateData: Codable {
        var id: UUID
        var name: String
        var mono: String
        var mode: String
        var roundCount: Int
        var winsByLowest: Bool
        var allowNegative: Bool
        var minPlayers: Int
        var maxPlayers: Int
        var eliminationLimit: Int
        var roundLabels: [String]
        var supportsJokers: Bool
        var unitLabel: String
        var showsAverages: Bool
        var subtitleNote: String
        var isBuiltIn: Bool
        var sortIndex: Int
        var scorecard: ScorecardSpec?
    }

    struct MatchData: Codable {
        var id: UUID
        var gameName: String
        var mono: String
        var mode: String
        var roundCount: Int
        var winsByLowest: Bool
        var allowNegative: Bool
        var eliminationLimit: Int
        var roundLabels: [String]
        var tracksJokers: Bool
        var unitLabel: String
        var showsAverages: Bool
        var startedAt: Date
        var lastPlayedAt: Date
        var endedAt: Date?
        var abandonedAt: Date?
        var seatOrder: [String]
        var playerIDs: [UUID]
        var rounds: [RoundData]
        var cards: [CardData]
        var scorecard: ScorecardSpec?
    }

    struct RoundData: Codable {
        var index: Int
        var createdAt: Date
        var entries: [EntryData]
    }

    struct EntryData: Codable {
        var playerID: UUID
        var value: Int?
        var jokers: Int
    }

    struct CardData: Codable {
        var playerID: UUID
        var columnKeys: [String]
        var bonusKeys: [String]
        var numbers: [String: Int]
        var penaltyCount: Int
    }
}

enum Backup {

    // MARK: - Wegschrijven

    @MainActor
    static func make(from context: ModelContext) throws -> BackupDocument {
        var document = BackupDocument()

        document.players = try context.fetch(FetchDescriptor<Player>()).map {
            .init(id: $0.id, name: $0.name, rampIndex: $0.rampIndex,
                  avatarIndex: $0.avatarIndex, isMe: $0.isMe,
                  isArchived: $0.isArchived, createdAt: $0.createdAt)
        }

        document.templates = try context.fetch(FetchDescriptor<GameTemplate>()).map {
            .init(id: $0.id, name: $0.name, mono: $0.mono, mode: $0.modeRaw,
                  roundCount: $0.roundCount, winsByLowest: $0.winsByLowest,
                  allowNegative: $0.allowNegative, minPlayers: $0.minPlayers,
                  maxPlayers: $0.maxPlayers, eliminationLimit: $0.eliminationLimit,
                  roundLabels: $0.roundLabels, supportsJokers: $0.supportsJokers,
                  unitLabel: $0.unitLabel, showsAverages: $0.showsAverages,
                  subtitleNote: $0.subtitleNote, isBuiltIn: $0.isBuiltIn,
                  sortIndex: $0.sortIndex, scorecard: $0.scorecard)
        }

        document.matches = try context.fetch(FetchDescriptor<Match>()).map { match in
            .init(id: match.id, gameName: match.gameName, mono: match.mono,
                  mode: match.modeRaw, roundCount: match.roundCount,
                  winsByLowest: match.winsByLowest, allowNegative: match.allowNegative,
                  eliminationLimit: match.eliminationLimit, roundLabels: match.roundLabels,
                  tracksJokers: match.tracksJokers, unitLabel: match.unitLabel,
                  showsAverages: match.showsAverages, startedAt: match.startedAt,
                  lastPlayedAt: match.lastPlayedAt, endedAt: match.endedAt,
                  abandonedAt: match.abandonedAt, seatOrder: match.seatOrder,
                  playerIDs: match.players.map(\.id),
                  rounds: match.orderedRounds.map { round in
                      .init(index: round.index, createdAt: round.createdAt,
                            entries: round.entries.map {
                                .init(playerID: $0.playerID, value: $0.value, jokers: $0.jokers)
                            })
                  },
                  cards: match.cards.map {
                      .init(playerID: $0.playerID, columnKeys: $0.columnKeys,
                            bonusKeys: $0.bonusKeys, numbers: $0.numbers,
                            penaltyCount: $0.penaltyCount)
                  },
                  scorecard: match.scorecard)
        }

        return document
    }

    /// Schrijft de reservekopie naar een bestand dat je kunt delen of bewaren.
    @MainActor
    static func write(from context: ModelContext) throws -> URL {
        let document = try make(from: context)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(document)

        let stamp = Date.now.formatted(.iso8601.year().month().day())
        let url = URL.temporaryDirectory.appending(path: "Scoreblok-reservekopie-\(stamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Terugzetten

    struct Result {
        var players = 0
        var templates = 0
        var matches = 0

        var summary: String {
            "\(players) spelers, \(templates) spellen en \(matches) potjes teruggezet."
        }
    }

    /// Zet een reservekopie terug. Bestaande onderdelen worden op id herkend
    /// en bijgewerkt; wat er niet is wordt toegevoegd. Er wordt niets gewist,
    /// zodat terugzetten nooit gegevens kost.
    @MainActor
    static func restore(from url: URL, into context: ModelContext) throws -> Result {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(BackupDocument.self, from: Data(contentsOf: url))

        var result = Result()

        var players: [UUID: Player] = [:]
        for existing in try context.fetch(FetchDescriptor<Player>()) {
            players[existing.id] = existing
        }
        for data in document.players {
            let player = players[data.id] ?? {
                let created = Player(name: data.name, rampIndex: data.rampIndex)
                created.id = data.id
                context.insert(created)
                players[data.id] = created
                return created
            }()
            player.name = data.name
            player.rampIndex = data.rampIndex
            player.avatarIndex = data.avatarIndex
            player.isMe = data.isMe
            player.isArchived = data.isArchived
            player.createdAt = data.createdAt
            result.players += 1
        }

        var templates: [UUID: GameTemplate] = [:]
        for existing in try context.fetch(FetchDescriptor<GameTemplate>()) {
            templates[existing.id] = existing
        }
        for data in document.templates {
            let template = templates[data.id] ?? {
                let created = GameTemplate(name: data.name, mono: data.mono, mode: .roundsCumulative)
                created.id = data.id
                context.insert(created)
                templates[data.id] = created
                return created
            }()
            template.name = data.name
            template.mono = data.mono
            template.modeRaw = data.mode
            template.roundCount = data.roundCount
            template.winsByLowest = data.winsByLowest
            template.allowNegative = data.allowNegative
            template.minPlayers = data.minPlayers
            template.maxPlayers = data.maxPlayers
            template.eliminationLimit = data.eliminationLimit
            template.roundLabels = data.roundLabels
            template.supportsJokers = data.supportsJokers
            template.unitLabel = data.unitLabel
            template.showsAverages = data.showsAverages
            template.subtitleNote = data.subtitleNote
            template.isBuiltIn = data.isBuiltIn
            template.sortIndex = data.sortIndex
            template.scorecardData = data.scorecard?.encoded()
            result.templates += 1
        }

        let existingMatches = Set(try context.fetch(FetchDescriptor<Match>()).map(\.id))
        for data in document.matches where !existingMatches.contains(data.id) {
            let template = GameTemplate(name: data.gameName, mono: data.mono, mode: .roundsCumulative)
            let match = Match(template: template)
            match.id = data.id
            match.gameName = data.gameName
            match.mono = data.mono
            match.modeRaw = data.mode
            match.roundCount = data.roundCount
            match.winsByLowest = data.winsByLowest
            match.allowNegative = data.allowNegative
            match.eliminationLimit = data.eliminationLimit
            match.roundLabels = data.roundLabels
            match.tracksJokers = data.tracksJokers
            match.unitLabel = data.unitLabel
            match.showsAverages = data.showsAverages
            match.startedAt = data.startedAt
            match.lastPlayedAt = data.lastPlayedAt
            match.endedAt = data.endedAt
            match.abandonedAt = data.abandonedAt
            match.seatOrder = data.seatOrder
            match.scorecardData = data.scorecard?.encoded()
            context.insert(match)
            match.players = data.playerIDs.compactMap { players[$0] }

            for roundData in data.rounds {
                let round = MatchRound(index: roundData.index)
                round.createdAt = roundData.createdAt
                context.insert(round)
                round.match = match
                match.rounds.append(round)
                for entryData in roundData.entries {
                    let entry = ScoreEntry(playerID: entryData.playerID, value: entryData.value)
                    entry.jokers = entryData.jokers
                    context.insert(entry)
                    round.entries.append(entry)
                }
            }

            for cardData in data.cards {
                let card = ScoreCard(playerID: cardData.playerID)
                card.columnKeys = cardData.columnKeys
                card.bonusKeys = cardData.bonusKeys
                card.numbers = cardData.numbers
                card.penaltyCount = cardData.penaltyCount
                context.insert(card)
                card.match = match
                match.cards.append(card)
            }
            result.matches += 1
        }

        Storage.save(context)
        return result
    }
}
