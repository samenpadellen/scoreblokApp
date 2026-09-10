import Foundation
import SwiftData

/// Een speelgroep: jullie blok en dat van iemand anders, gekoppeld met een
/// QR-code aan dezelfde tafel. Onthoudt wie er bij hoort, wie van de ander
/// bij wie van jou hoort, en welke potjes via de groep binnenkwamen.
///
/// De lijsten staan als JSON in Data-velden: CloudKit wil eenvoudige
/// kenmerken met een standaardwaarde, en zo verandert er aan de bestaande
/// tabellen niets.
@Model
final class PlayGroup {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date.now
    var lastSyncAt: Date?
    var memberIDsData: Data?
    var linksData: Data?
    var importedData: Data?

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
        self.createdAt = .now
    }

    /// Spelers in dit blok die bij de groep horen.
    var memberIDs: Set<UUID> {
        get {
            let strings = Self.decode([String].self, from: memberIDsData) ?? []
            return Set(strings.compactMap(UUID.init(uuidString:)))
        }
        set {
            memberIDsData = Self.encode(newValue.map(\.uuidString).sorted())
        }
    }

    /// Een speler zoals de ander die kent → dezelfde persoon in dit blok.
    var links: [UUID: UUID] {
        get {
            let strings = Self.decode([String: String].self, from: linksData) ?? [:]
            var result: [UUID: UUID] = [:]
            for (remote, local) in strings {
                if let r = UUID(uuidString: remote), let l = UUID(uuidString: local) { result[r] = l }
            }
            return result
        }
        set {
            linksData = Self.encode(Dictionary(uniqueKeysWithValues: newValue.map {
                ($0.key.uuidString, $0.value.uuidString)
            }))
        }
    }

    /// Potjes die via de groep binnenkwamen, met wanneer ze toen voor het
    /// laatst gespeeld waren. Zo is te zien of je ze sindsdien aanpaste.
    var imported: [UUID: Date] {
        get {
            let stamps = Self.decode([String: Double].self, from: importedData) ?? [:]
            var result: [UUID: Date] = [:]
            for (id, stamp) in stamps {
                if let uuid = UUID(uuidString: id) { result[uuid] = Date(timeIntervalSince1970: stamp) }
            }
            return result
        }
        set {
            importedData = Self.encode(Dictionary(uniqueKeysWithValues: newValue.map {
                ($0.key.uuidString, $0.value.timeIntervalSince1970)
            }))
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }
}
