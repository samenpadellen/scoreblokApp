import Foundation
import SwiftData

/// Versie 1 van het schema. Elke latere wijziging krijgt een eigen versie en
/// een migratiestap, zodat een bestaand blok nooit stilzwijgend onleesbaar
/// wordt bij een update van de app.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Player.self, GameTemplate.self, Match.self,
         MatchRound.self, ScoreEntry.self, ScoreCard.self]
    }
}

enum ScoreblokMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

/// Waar de potjes staan. De regel is: een potje dat je hebt ingevuld gaat
/// nooit verloren en verdwijnt nooit stilletjes. Lukt het openen van de
/// opslag niet, dan zegt de app dat — in plaats van te beginnen met een leeg
/// blok waarvan je denkt dat je alles kwijt bent.
enum Storage {

    enum Mode: Equatable {
        /// Lokaal én gesynchroniseerd met iCloud.
        case cloud
        /// Alleen op dit apparaat, met de reden erbij.
        case local(reason: String)
        /// De opslag ging niet open. Er wordt niets weggeschreven.
        case failed(reason: String)

        var isCloud: Bool { if case .cloud = self { true } else { false } }
        var isFailed: Bool { if case .failed = self { true } else { false } }

        var title: String {
            switch self {
            case .cloud: "iCloud"
            case .local: "Lokaal"
            case .failed: "Let op"
            }
        }

        var detail: String {
            switch self {
            case .cloud: "Synchroniseert met je andere apparaten"
            case .local(let reason): reason
            case .failed(let reason): reason
            }
        }
    }

    private(set) static var mode: Mode = .local(reason: "Nog niet geopend")
    /// Wanneer er voor het laatst met zekerheid is weggeschreven.
    private(set) static var lastSaved: Date?

    static let schema = Schema(versionedSchema: SchemaV1.self)

    /// Moet letterlijk overeenkomen met de container in het Developer-portaal
    /// en met de entitlements.
    static let cloudContainerID = "iCloud.nl.scoreblok.app"

    static let shared: ModelContainer = makeContainer()

    static func makeContainer() -> ModelContainer {
        let directory = URL.applicationSupportDirectory.appending(path: "Scoreblok", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "Scoreblok.store")

        // Eén en dezelfde winkel voor beide modi. Zo kijkt de app na een
        // mislukte iCloud-start naar exact dezelfde gegevens als daarvoor,
        // in plaats van naar een tweede, lege database.
        func open(cloud: Bool) throws -> ModelContainer {
            let configuration = ModelConfiguration(
                schema: schema,
                url: file,
                cloudKitDatabase: cloud ? .automatic : .none
            )
            return try ModelContainer(for: schema,
                                      migrationPlan: ScoreblokMigrationPlan.self,
                                      configurations: configuration)
        }

        do {
            let container = try open(cloud: true)
            // Let op: dit betekent alleen dat de winkel openging. Of er ook
            // echt gesynchroniseerd wordt hangt af van het iCloud-account;
            // dat bewaakt CloudStatus.
            mode = .cloud
            return container
        } catch {
            // Geen iCloud-rechten: gewoon lokaal verder.
        }

        do {
            let container = try open(cloud: false)
            mode = .local(reason: "Alleen op dit apparaat")
            return container
        } catch {
            mode = .failed(reason: "De opslag ging niet open. Maak een reservekopie voor je verder speelt: \(error.localizedDescription)")
        }

        // Laatste redmiddel zodat de app niet omvalt. De balk in de zijbalk
        // laat zien dat er niets bewaard wordt.
        let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // swiftlint:disable:next force_try
        return try! ModelContainer(for: schema, configurations: memory)
    }

    /// Wegschrijven met zekerheid, en onthouden wanneer dat lukte.
    @discardableResult
    @MainActor
    static func save(_ context: ModelContext) -> Bool {
        guard context.hasChanges else { return true }
        do {
            try context.save()
            lastSaved = .now
            return true
        } catch {
            mode = .failed(reason: "Opslaan lukte niet: \(error.localizedDescription)")
            return false
        }
    }

    /// Waar het bestand staat, voor de opslagkaart.
    static var storeDescription: String {
        let directory = URL.applicationSupportDirectory.appending(path: "Scoreblok")
        let file = directory.appending(path: "Scoreblok.store")
        guard let size = try? FileManager.default
            .attributesOfItem(atPath: file.path(percentEncoded: false))[.size] as? Int
        else { return "Nog geen bestand" }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}
