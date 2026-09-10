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
    /// Speelgroepen. Ontbreekt in reservekopieën van vóór de speelgroepen.
    var groups: [GroupData]?
    /// Profielfoto's. Ontbreekt in reservekopieën van vóór de foto's.
    var photos: [PhotoData]?

    struct PhotoData: Codable {
        var playerID: UUID
        var updatedAt: Date
        var jpeg: Data
    }

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

    struct GroupData: Codable {
        var id: UUID
        var name: String
        var createdAt: Date
        var lastSyncAt: Date?
        var memberIDs: [UUID]
        var links: [String: String]
        var imported: [String: Date]
    }
}

extension BackupDocument {
    /// Wat er in een kopie zit, om na een overstap na te tellen.
    struct Tally: Equatable, CustomStringConvertible {
        var players = 0
        var matches = 0
        var rounds = 0
        var entries = 0

        /// Bevat deze telling minstens alles van de andere?
        func covers(_ other: Tally) -> Bool {
            players >= other.players && matches >= other.matches
                && rounds >= other.rounds && entries >= other.entries
        }

        var description: String {
            "\(players) spelers, \(matches) potjes, \(rounds) rondes, \(entries) cellen"
        }
    }

    var tally: Tally {
        Tally(players: players.count,
              matches: matches.count,
              rounds: matches.reduce(0) { $0 + $1.rounds.count },
              entries: matches.reduce(0) { sum, match in
                  sum + match.rounds.reduce(0) { $0 + $1.entries.count }
              })
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

        document.groups = try context.fetch(FetchDescriptor<PlayGroup>()).map { group in
            .init(id: group.id, name: group.name, createdAt: group.createdAt,
                  lastSyncAt: group.lastSyncAt,
                  memberIDs: group.memberIDs.sorted { $0.uuidString < $1.uuidString },
                  links: Dictionary(uniqueKeysWithValues: group.links.map {
                      ($0.key.uuidString, $0.value.uuidString)
                  }),
                  imported: Dictionary(uniqueKeysWithValues: group.imported.map {
                      ($0.key.uuidString, $0.value)
                  }))
        }

        document.photos = PhotoBook.newest(try context.fetch(FetchDescriptor<PlayerPhoto>()))
            .values
            .compactMap { photo in
                photo.imageData.map { .init(playerID: photo.playerID, updatedAt: photo.updatedAt, jpeg: $0) }
            }
            .sorted { $0.playerID.uuidString < $1.playerID.uuidString }

        return document
    }

    /// Schrijft de reservekopie naar een bestand dat je kunt delen of bewaren.
    @MainActor
    static func write(from context: ModelContext) throws -> URL {
        let data = try encode(try make(from: context))
        let stamp = Date.now.formatted(.iso8601.year().month().day())
        let url = URL.temporaryDirectory.appending(path: "Scoreblok-reservekopie-\(stamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func encode(_ document: BackupDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    static func decode(_ data: Data) throws -> BackupDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupDocument.self, from: data)
    }

    /// Waar de automatische kopieën staan.
    static var archiveDirectory: URL {
        Storage.directory.appending(path: "Reservekopieen", directoryHint: .isDirectory)
    }

    /// Een kopie die de app zelf maakt vlak voor hij iets ingrijpends doet,
    /// zoals overstappen tussen lokaal en iCloud. De tien nieuwste blijven.
    @discardableResult
    static func archive(_ document: BackupDocument, reason: String) throws -> URL {
        let directory = archiveDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = Date.now.formatted(.iso8601).replacingOccurrences(of: ":", with: "-")
        let url = directory.appending(path: "\(reason)-\(stamp).json")
        try encode(document).write(to: url, options: .atomic)

        let keys: [URLResourceKey] = [.creationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys)) ?? []
        let newestFirst = files
            .filter { $0.pathExtension == "json" }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: Set(keys)).creationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: Set(keys)).creationDate) ?? .distantPast
                return a > b
            }
        for old in newestFirst.dropFirst(10) { try? FileManager.default.removeItem(at: old) }
        return url
    }

    // MARK: - Terugzetten

    struct Result {
        var players = 0
        var templates = 0
        var matches = 0
        /// Potjes die er al waren en zijn aangevuld.
        var updatedMatches = 0

        var summary: String {
            var text = "\(players) spelers, \(templates) spellen en \(matches) potjes teruggezet."
            if updatedMatches > 0 {
                text += " \(updatedMatches) bestaande potjes aangevuld."
            }
            return text
        }
    }

    @MainActor
    static func restore(from url: URL, into context: ModelContext) throws -> Result {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
        return try restore(try decode(Data(contentsOf: url)), into: context)
    }

    /// Zet een reservekopie terug. Bestaande onderdelen worden op id herkend
    /// en bijgewerkt; wat er niet is wordt toegevoegd. Er wordt niets gewist,
    /// zodat terugzetten nooit gegevens kost.
    ///
    /// Een potje dat er al is wordt aangevuld: ontbrekende rondes, cellen en
    /// kaarten komen erbij, en bij een verschil wint de versie die het laatst
    /// gespeeld is. Voorheen werd een bestaand potje overgeslagen. Wie lokaal
    /// verder speelde en daarna naar iCloud overstapte, raakte die rondes kwijt.
    @MainActor
    @discardableResult
    static func restore(_ document: BackupDocument, into context: ModelContext) throws -> Result {
        var result = Result()

        var players: [UUID: Player] = [:]
        for existing in try context.fetch(FetchDescriptor<Player>()) where !existing.isDeleted {
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
        for existing in try context.fetch(FetchDescriptor<GameTemplate>()) where !existing.isDeleted {
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

        var existingMatches: [UUID: Match] = [:]
        for match in try context.fetch(FetchDescriptor<Match>()) where !match.isDeleted {
            existingMatches[match.id] = match
        }
        for data in document.matches {
            if let match = existingMatches[data.id] {
                if merge(data, into: match, players: players, in: context) {
                    result.updatedMatches += 1
                }
                continue
            }

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
            existingMatches[data.id] = match
            result.matches += 1
        }

        // Speelgroepen gaan mee, zodat een overstap tussen lokaal en iCloud
        // of een teruggezette kopie de koppelingen niet vergeet.
        if let groups = document.groups {
            var existingGroups: [UUID: PlayGroup] = [:]
            for group in try context.fetch(FetchDescriptor<PlayGroup>()) where !group.isDeleted {
                existingGroups[group.id] = group
            }
            for data in groups {
                let group = existingGroups[data.id] ?? {
                    let created = PlayGroup(id: data.id, name: data.name)
                    context.insert(created)
                    existingGroups[data.id] = created
                    return created
                }()
                group.name = data.name
                group.createdAt = data.createdAt
                if let synced = data.lastSyncAt { group.lastSyncAt = synced }
                group.memberIDs = group.memberIDs.union(data.memberIDs)
                var links = group.links
                for (remote, local) in data.links {
                    if let r = UUID(uuidString: remote), let l = UUID(uuidString: local) { links[r] = l }
                }
                group.links = links
                var imported = group.imported
                for (id, stamp) in data.imported {
                    if let uuid = UUID(uuidString: id) { imported[uuid] = stamp }
                }
                group.imported = imported
            }
        }

        // Foto's: de nieuwste wint, een foto wordt nooit gewist.
        if let photos = document.photos {
            restorePhotos(photos, onlyWhenMissing: false, into: context)
        }

        Storage.save(context)
        return result
    }

    /// Zet foto's terug. Met `onlyWhenMissing` blijft een eigen foto altijd
    /// staan; zo overschrijft samen bijwerken nooit hoe jij iemand bewaard hebt.
    @MainActor
    static func restorePhotos(_ photos: [BackupDocument.PhotoData], onlyWhenMissing: Bool,
                              into context: ModelContext) {
        let local = PhotoBook.newest((try? context.fetch(FetchDescriptor<PlayerPhoto>())) ?? [])
        for data in photos {
            if let existing = local[data.playerID] {
                guard !onlyWhenMissing, data.updatedAt > existing.updatedAt else { continue }
                existing.imageData = data.jpeg
                existing.updatedAt = data.updatedAt
            } else {
                context.insert(PlayerPhoto(playerID: data.playerID, imageData: data.jpeg,
                                           updatedAt: data.updatedAt))
            }
        }
    }

    /// Vult een bestaand potje aan met wat de kopie meer heeft. Verwijdert
    /// nooit iets: een lege cel in de kopie wist geen ingevulde cel.
    @MainActor
    private static func merge(_ data: BackupDocument.MatchData, into match: Match,
                              players: [UUID: Player], in context: ModelContext) -> Bool {
        var changed = false
        let incomingIsNewer = data.lastPlayedAt > match.lastPlayedAt

        if match.endedAt == nil, let ended = data.endedAt {
            match.endedAt = ended
            changed = true
        }
        if incomingIsNewer {
            if match.abandonedAt != data.abandonedAt { match.abandonedAt = data.abandonedAt }
            match.lastPlayedAt = data.lastPlayedAt
            changed = true
        }

        let seated = Set(match.players.map(\.id))
        let missing = data.playerIDs.filter { !seated.contains($0) }.compactMap { players[$0] }
        if !missing.isEmpty {
            match.players.append(contentsOf: missing)
            changed = true
        }
        for id in data.seatOrder where !match.seatOrder.contains(id) {
            match.seatOrder.append(id)
            changed = true
        }

        for roundData in data.rounds {
            let round: MatchRound
            if let existing = match.rounds.first(where: { $0.index == roundData.index && !$0.isDeleted }) {
                round = existing
            } else {
                round = MatchRound(index: roundData.index)
                round.createdAt = roundData.createdAt
                context.insert(round)
                round.match = match
                match.rounds.append(round)
                changed = true
            }
            for entryData in roundData.entries {
                if let entry = round.entries.first(where: { $0.playerID == entryData.playerID && !$0.isDeleted }) {
                    if let incoming = entryData.value, incoming != entry.value,
                       entry.value == nil || incomingIsNewer {
                        entry.value = incoming
                        changed = true
                    }
                    if incomingIsNewer, entry.jokers != entryData.jokers {
                        entry.jokers = entryData.jokers
                        changed = true
                    }
                } else {
                    let entry = ScoreEntry(playerID: entryData.playerID, value: entryData.value)
                    entry.jokers = entryData.jokers
                    context.insert(entry)
                    round.entries.append(entry)
                    changed = true
                }
            }
        }

        for cardData in data.cards {
            if let card = match.cards.first(where: { $0.playerID == cardData.playerID && !$0.isDeleted }) {
                let isEmpty = card.columnKeys.isEmpty && card.bonusKeys.isEmpty
                    && card.numbers.isEmpty && card.penaltyCount == 0
                guard incomingIsNewer || isEmpty else { continue }
                if card.columnKeys != cardData.columnKeys || card.bonusKeys != cardData.bonusKeys
                    || card.numbers != cardData.numbers || card.penaltyCount != cardData.penaltyCount {
                    card.columnKeys = cardData.columnKeys
                    card.bonusKeys = cardData.bonusKeys
                    card.numbers = cardData.numbers
                    card.penaltyCount = cardData.penaltyCount
                    changed = true
                }
            } else {
                let card = ScoreCard(playerID: cardData.playerID)
                card.columnKeys = cardData.columnKeys
                card.bonusKeys = cardData.bonusKeys
                card.numbers = cardData.numbers
                card.penaltyCount = cardData.penaltyCount
                context.insert(card)
                card.match = match
                match.cards.append(card)
                changed = true
            }
        }
        return changed
    }
}
