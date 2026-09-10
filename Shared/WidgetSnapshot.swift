import Foundation

/// Wat de widgets van de app moeten weten. De app schrijft dit weg in de
/// gedeelde map zodra een totaal verandert; de widget leest het. Bewust een
/// klein bestand en niet de database zelf.
///
/// Er staan twee dingen in: het open potje, en de ranglijst van de
/// speelgroep. Is er geen potje open, dan tonen de widgets de ranglijst in
/// plaats van een leeg kader.
struct WidgetSnapshot: Codable, Equatable {

    struct Entry: Codable, Equatable, Identifiable {
        var id: UUID
        var name: String
        var initial: String
        var total: Int
        var rank: Int
        var rampIndex: Int
        var avatarIndex: Int
        /// Verschil met de leider; 0 voor de leider zelf.
        var gap: Int
    }

    struct RankEntry: Codable, Equatable, Identifiable {
        var id: UUID
        var name: String
        var initial: String
        var rampIndex: Int
        var avatarIndex: Int
        var winRate: Double
        var played: Int
    }

    struct OpenMatch: Codable, Equatable {
        var id: UUID
        var gameName: String
        var mono: String
        var unitLabel: String
        /// "ronde 4 van 9"
        var position: String
        /// "laagste totaal wint"
        var rule: String
        var startedAt: Date
        var lastPlayed: Date
        var standings: [Entry]
        /// De gespeelde rondes, in de volgorde van `standings`.
        var playedRounds: [Round]
        /// Accentkleur van het spel, licht genoeg voor een donker vlak.
        /// Ontbreekt in momentopnamen van oudere versies.
        var accentHex: Int?

        struct Round: Codable, Equatable, Identifiable {
            var label: String
            var cells: [String]
            var id: String { label }
        }

        /// De korte vorm van `position`, zonder "van N".
        var shortPosition: String {
            guard let range = position.range(of: " van ") else { return position }
            return String(position[position.startIndex..<range.lowerBound])
        }

        /// Voorsprong van de leider op de tweede.
        var gap: Int { standings.count > 1 ? standings[1].total - standings[0].total : 0 }
        var leader: Entry? { standings.first }
    }

    var open: OpenMatch?
    var ranking: [RankEntry]
    /// "90 dagen"
    var period: String
    var totalMatches: Int
    var lastFinished: Date?

    static let appGroup = "group.nl.scoreblok.app"
    static let fileName = "widget-snapshot.json"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    static var fileURL: URL? { containerURL?.appending(path: fileName) }

    static func read() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    func write() {
        guard let url = Self.fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Waar een tik op de widget heen gaat.
    var destination: URL {
        if let open { return URL(string: "scoreblok://match/\(open.id.uuidString)")! }
        return URL(string: "scoreblok://setup")!
    }
}
