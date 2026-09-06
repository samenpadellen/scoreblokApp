import Foundation
import SwiftData

/// Waar de potjes staan. Bij een geldige iCloud-configuratie synchroniseert
/// SwiftData zelf via CloudKit; lukt dat niet, dan blijft alles lokaal en
/// zegt de app dat ook, in plaats van te doen alsof.
enum Storage {

    enum Mode {
        case cloud
        case local(reason: String)

        var isCloud: Bool { if case .cloud = self { true } else { false } }

        var title: String { isCloud ? "iCloud" : "Lokaal" }

        var detail: String {
            switch self {
            case .cloud: "Synchroniseert met je andere apparaten"
            case .local(let reason): reason
            }
        }
    }

    private(set) static var mode: Mode = .local(reason: "Nog niet geopend")

    /// Eén container voor de app én voor Siri en Shortcuts.
    static let shared: ModelContainer = makeContainer()

    static let schema = Schema([
        Player.self, GameTemplate.self, Match.self,
        MatchRound.self, ScoreEntry.self, ScoreCard.self
    ])

    static func makeContainer() -> ModelContainer {
        // Eerst met CloudKit. Zonder iCloud-rechten of zonder ingelogd
        // account gooit dit, en vallen we terug op de lokale winkel.
        let cloud = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        if let container = try? ModelContainer(for: schema, configurations: cloud) {
            mode = .cloud
            return container
        }

        let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: schema, configurations: local) {
            mode = .local(reason: "Alleen op dit apparaat")
            return container
        }

        // Laatste redmiddel: in het geheugen, zodat de app niet omvalt.
        mode = .local(reason: "Opslag niet beschikbaar")
        let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: memory)
    }
}
