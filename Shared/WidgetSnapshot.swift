import Foundation

/// Wat de widget van het lopende potje moet weten. De app schrijft dit weg
/// in de gedeelde map; de widget leest het. Bewust een klein bestand en niet
/// de database zelf — die blijft staan waar hij staat.
struct WidgetSnapshot: Codable, Equatable {
    struct Entry: Codable, Equatable, Identifiable {
        var id: UUID
        var name: String
        var initial: String
        var total: Int
        var rank: Int
        var rampIndex: Int
        var avatarIndex: Int
    }

    var gameName: String
    var mono: String
    var unitLabel: String
    var position: String
    var lastPlayed: Date
    var standings: [Entry]
    var isOpen: Bool

    static let appGroup = "group.nl.scoreblok.app"
    static let fileName = "widget-snapshot.json"

    /// De gedeelde map, of `nil` als de App Group nog niet is ingesteld.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    static var fileURL: URL? {
        containerURL?.appending(path: fileName)
    }

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
}
