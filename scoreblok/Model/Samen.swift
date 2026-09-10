import CryptoKit
import Foundation
import Security
import SwiftData

/// Samen bijwerken: twee blokken aan dezelfde tafel koppelen met een QR-code
/// en de potjes van de speelgroep uitwisselen. Zoals vroeger met een
/// linkkabel tussen twee Game Boys, maar dan zonder kabel.
enum Samen {
    static let protocolVersion = 1
    /// Bonjour-dienst; moet overeenkomen met NSBonjourServices in Info.plist.
    static let serviceType = "scoreblok-sync"
}

// MARK: - Uitnodiging

/// Wat er in de QR-code staat: een eenmalige code, de speelgroep en wie de
/// code laat zien. De code zelf gaat nooit over het netwerk rond; alleen wie
/// hem heeft gescand kan verbinden.
struct SamenInvite: Equatable, Sendable {
    let token: String
    let groupID: UUID
    let hostName: String

    init(token: String, groupID: UUID, hostName: String) {
        self.token = token
        self.groupID = groupID
        self.hostName = hostName
    }

    init?(url: URL) {
        guard url.scheme == "scoreblok", url.host() == "samen",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard let token = value("t"), token.count >= 8,
              let group = value("g").flatMap(UUID.init(uuidString:))
        else { return nil }
        self.token = token
        self.groupID = group
        self.hostName = value("n") ?? "Scoreblok"
    }

    static func newToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 12)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = "scoreblok"
        components.host = "samen"
        components.queryItems = [
            URLQueryItem(name: "v", value: String(Samen.protocolVersion)),
            URLQueryItem(name: "t", value: token),
            URLQueryItem(name: "g", value: groupID.uuidString),
            URLQueryItem(name: "n", value: hostName)
        ]
        return components.url ?? URL(string: "scoreblok://samen")!
    }

    /// Wat het apparaat met de QR-code in de buurt laat zien: een afgeleide
    /// van de code, zodat de ander het juiste apparaat vindt.
    var discoveryHash: String {
        SHA256.hash(data: Data(token.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }
}

/// Vraag om het samen-scherm te openen. Zonder uitnodiging laat dit apparaat
/// een code zien; met uitnodiging is de code van de ander gescand.
struct SamenRequest: Identifiable, Equatable {
    let id = UUID()
    let invite: SamenInvite?

    static var host: SamenRequest { SamenRequest(invite: nil) }
}

// MARK: - Wat er overgaat

struct SamenPayload: Codable {
    var protocolVersion = Samen.protocolVersion
    var groupID: UUID
    var senderName: String
    var members: [BackupDocument.PlayerData]
    var matches: [BackupDocument.MatchData]
    /// Hoe de afzender spelers van de ontvanger al koppelde: id bij de
    /// ontvanger → id bij de afzender. Daarmee koppelt de ontvanger terug
    /// zonder te hoeven vragen.
    var links: [String: String]
}

/// Verpakt een pakket in kleine, genummerde stukken, zodat ook een heel
/// seizoen potjes betrouwbaar overgaat.
enum SamenWire {
    private static let magic = Data("SBS1".utf8)
    static let chunkSize = 48_000

    struct Frame {
        let index: Int
        let total: Int
        let body: Data
    }

    static func pack(_ payload: SamenPayload) throws -> [Data] {
        let json = try JSONEncoder().encode(payload)
        let packed = try (json as NSData).compressed(using: .zlib) as Data
        let total = max(1, (packed.count + chunkSize - 1) / chunkSize)
        return (0..<total).map { index in
            var frame = magic
            frame.append(bigEndian(UInt32(index)))
            frame.append(bigEndian(UInt32(total)))
            let start = index * chunkSize
            frame.append(packed.subdata(in: start..<min(start + chunkSize, packed.count)))
            return frame
        }
    }

    static func frame(_ data: Data) -> Frame? {
        let bytes = Data(data)
        guard bytes.count >= 12, bytes.prefix(4) == magic else { return nil }
        let index = Int(readUInt32(bytes, at: 4))
        let total = Int(readUInt32(bytes, at: 8))
        guard total > 0, index < total else { return nil }
        return Frame(index: index, total: total, body: bytes.subdata(in: 12..<bytes.count))
    }

    static func unpack(_ bodies: [Data]) throws -> SamenPayload {
        let packed = bodies.reduce(Data(), +)
        let json = try (packed as NSData).decompressed(using: .zlib) as Data
        return try JSONDecoder().decode(SamenPayload.self, from: json)
    }

    private static func bigEndian(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        data.subdata(in: offset..<offset + 4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
}

// MARK: - Koppelen en samenvoegen

@MainActor
enum SamenExchange {
    enum Choice: Hashable {
        case existing(UUID)
        case new
    }

    struct Preview: Equatable {
        var newMatches = 0
        var updatedMatches = 0
        var newPlayers = 0
    }

    struct Outcome: Equatable {
        var newMatches = 0
        var updatedMatches = 0
        var newPlayers = 0
    }

    /// Wie standaard meedoet: wie al in de groep zat, en anders alleen jij.
    static func defaultMembers(group: PlayGroup?, players: [Player]) -> Set<UUID> {
        let active = players.filter { !$0.isArchived }
        if let group {
            let known = group.memberIDs.intersection(active.map(\.id))
            if !known.isEmpty { return known }
        }
        return Set(active.filter(\.isMe).map(\.id))
    }

    /// Afgeronde, meetellende potjes waarin uitsluitend deze spelers zaten.
    static func isShared(_ match: Match, members: Set<UUID>) -> Bool {
        match.counts && !match.players.isEmpty && match.players.allSatisfy { members.contains($0.id) }
    }

    /// Alle potjes waarin alleen leden van de groep speelden: voor het filter
    /// in Statistieken.
    static func matches(_ matches: [Match], in group: PlayGroup) -> [Match] {
        let members = group.memberIDs
        return matches.filter { match in
            !match.players.isEmpty && match.players.allSatisfy { members.contains($0.id) }
        }
    }

    static func payload(context: ModelContext, groupID: UUID, group: PlayGroup?,
                        members: Set<UUID>, senderName: String) throws -> SamenPayload {
        let document = try Backup.make(from: context)
        let memberData = document.players
            .filter { members.contains($0.id) }
            .map { player -> BackupDocument.PlayerData in
                var copy = player
                copy.isMe = false
                copy.isArchived = false
                return copy
            }
        let shared = document.matches.filter { match in
            match.endedAt != nil && match.abandonedAt == nil && !match.playerIDs.isEmpty
                && Set(match.playerIDs).isSubset(of: members)
        }
        var links: [String: String] = [:]
        for (remote, local) in group?.links ?? [:] where members.contains(local) {
            links[remote.uuidString] = local.uuidString
        }
        return SamenPayload(groupID: groupID, senderName: senderName, members: memberData,
                            matches: shared, links: links)
    }

    /// Voorstel wie wie is: hetzelfde id, een eerdere koppeling, de koppeling
    /// die de ander meestuurde, of dezelfde naam. Anders een nieuw profiel.
    static func suggestions(for payload: SamenPayload, group: PlayGroup?,
                            players: [Player]) -> [UUID: Choice] {
        let active = players.filter { !$0.isArchived }
        let byID = Dictionary(active.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var used = Set<UUID>()
        var result: [UUID: Choice] = [:]

        for member in payload.members {
            var pick: UUID?
            if byID[member.id] != nil {
                pick = member.id
            } else if let local = group?.links[member.id], byID[local] != nil {
                pick = local
            } else if let key = payload.links.first(where: { $0.value == member.id.uuidString })?.key,
                      let local = UUID(uuidString: key), byID[local] != nil {
                pick = local
            } else if let named = active.first(where: {
                normalized($0.name) == normalized(member.name) && !used.contains($0.id)
            }) {
                pick = named.id
            }
            if let pick, !used.contains(pick) {
                used.insert(pick)
                result[member.id] = .existing(pick)
            } else {
                result[member.id] = .new
            }
        }
        return result
    }

    /// Twee spelers van de ander die naar dezelfde persoon wijzen.
    static func hasConflict(_ choices: [UUID: Choice]) -> Bool {
        var seen = Set<UUID>()
        for choice in choices.values {
            if case .existing(let id) = choice {
                if seen.contains(id) { return true }
                seen.insert(id)
            }
        }
        return false
    }

    static func preview(_ payload: SamenPayload, choices: [UUID: Choice],
                        context: ModelContext) -> Preview {
        let local = (try? context.fetch(FetchDescriptor<Match>())) ?? []
        let byID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var preview = Preview()
        for match in payload.matches {
            if let existing = byID[match.id] {
                if match.lastPlayedAt > existing.lastPlayedAt { preview.updatedMatches += 1 }
            } else {
                preview.newMatches += 1
            }
        }
        preview.newPlayers = payload.members.filter { (choices[$0.id] ?? .new) == .new }.count
        return preview
    }

    /// Voegt de potjes van de ander samen. Vooraf een reservekopie; er wordt
    /// nooit iets gewist; hetzelfde pakket nog eens samenvoegen verandert niets.
    @discardableResult
    static func apply(_ payload: SamenPayload, choices: [UUID: Choice], localMembers: Set<UUID>,
                      groupID: UUID, groupName: String, context: ModelContext) throws -> Outcome {
        try Backup.archive(try Backup.make(from: context), reason: "voor-samen")

        var map: [String: String] = [:]
        var newPlayers: [BackupDocument.PlayerData] = []
        for member in payload.members {
            switch choices[member.id] ?? .new {
            case .existing(let local):
                map[member.id.uuidString] = local.uuidString
            case .new:
                // Een nieuw profiel houdt het id van de ander: dan herkennen
                // beide blokken dezelfde persoon voortaan vanzelf.
                map[member.id.uuidString] = member.id.uuidString
                var copy = member
                copy.isMe = false
                copy.isArchived = false
                newPlayers.append(copy)
            }
        }

        let before = Set(((try? context.fetch(FetchDescriptor<Match>())) ?? []).map(\.id))
        let matches = payload.matches.map { remap($0, with: map) }
        let document = BackupDocument(players: newPlayers, templates: [], matches: matches)
        let result = try Backup.restore(document, into: context)

        let groups = (try? context.fetch(FetchDescriptor<PlayGroup>())) ?? []
        let group = groups.first(where: { $0.id == groupID && !$0.isDeleted }) ?? {
            let created = PlayGroup(id: groupID, name: groupName)
            context.insert(created)
            return created
        }()
        group.name = groupName

        var members = group.memberIDs
        members.formUnion(localMembers)
        members.formUnion(map.values.compactMap(UUID.init(uuidString:)))
        group.memberIDs = members

        var links = group.links
        for (remote, local) in map where remote != local {
            if let r = UUID(uuidString: remote), let l = UUID(uuidString: local) { links[r] = l }
        }
        group.links = links

        // Alleen wat hier nog niet stond telt als binnengekomen. Eigen potjes
        // die via de ander terugkomen, blijven van jou.
        let stamps = Dictionary(((try? context.fetch(FetchDescriptor<Match>())) ?? []).map {
            ($0.id, $0.lastPlayedAt)
        }, uniquingKeysWith: { first, _ in first })
        var imported = group.imported
        for match in matches where !before.contains(match.id) {
            if let stamp = stamps[match.id] { imported[match.id] = stamp }
        }
        group.imported = imported
        group.lastSyncAt = .now

        Storage.save(context)
        StoreController.shared.didRestoreBackup()
        return Outcome(newMatches: result.matches, updatedMatches: result.updatedMatches,
                       newPlayers: newPlayers.count)
    }

    /// Ontkoppelen. Met `removeMatches` verdwijnen ook de potjes die via de
    /// groep binnenkwamen en sindsdien niet zijn aangepast. Vooraf een
    /// reservekopie. Geeft terug hoeveel potjes er weg zijn.
    @discardableResult
    static func unlink(_ group: PlayGroup, removeMatches: Bool, context: ModelContext) throws -> Int {
        var removed = 0
        if removeMatches {
            try Backup.archive(try Backup.make(from: context), reason: "voor-ontkoppelen")
            let imported = group.imported
            for match in (try? context.fetch(FetchDescriptor<Match>())) ?? [] where !match.isDeleted {
                guard let stamp = imported[match.id],
                      abs(match.lastPlayedAt.timeIntervalSince(stamp)) < 1 else { continue }
                context.delete(match)
                removed += 1
            }
        }
        context.delete(group)
        Storage.save(context)
        return removed
    }

    static func normalized(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "nl_NL"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func remap(_ match: BackupDocument.MatchData,
                              with map: [String: String]) -> BackupDocument.MatchData {
        func mapped(_ id: UUID) -> UUID {
            map[id.uuidString].flatMap(UUID.init(uuidString:)) ?? id
        }
        var copy = match
        copy.playerIDs = match.playerIDs.map(mapped)
        copy.seatOrder = match.seatOrder.map { map[$0] ?? $0 }
        copy.rounds = match.rounds.map { round in
            var updated = round
            updated.entries = round.entries.map { entry in
                var moved = entry
                moved.playerID = mapped(entry.playerID)
                return moved
            }
            return updated
        }
        copy.cards = match.cards.map { card in
            var moved = card
            moved.playerID = mapped(card.playerID)
            return moved
        }
        return copy
    }
}
