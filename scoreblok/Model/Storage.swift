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

/// Waar de potjes staan: lokaal óf iCloud, per apparaat gekozen. Hoort
/// bewust niet te synchroniseren; elk apparaat kiest zelf.
enum StorageChoice: String, CaseIterable, Identifiable {
    case local
    case iCloud

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local: "Lokaal"
        case .iCloud: "iCloud"
        }
    }

    private static let key = "opslag.keuze"

    static var saved: StorageChoice? {
        get { UserDefaults.standard.string(forKey: key).flatMap(StorageChoice.init(rawValue:)) }
        set { UserDefaults.standard.set(newValue?.rawValue, forKey: key) }
    }
}

/// Waar de potjes staan. De regel is: een potje dat je hebt ingevuld gaat
/// nooit verloren en verdwijnt nooit stilletjes. Lukt het openen van de
/// opslag niet, dan zegt de app dat — in plaats van te beginnen met een leeg
/// blok waarvan je denkt dat je alles kwijt bent.
///
/// Lokaal en iCloud hebben elk een eigen bestand. Eerder deelden ze er één,
/// en opende de app het met `.automatic`: een "lokale" opslag synchroniseerde
/// dan gewoon mee zodra de rechten er waren.
enum Storage {

    enum Mode: Equatable {
        /// Gekoppeld aan iCloud. Of er echt gesynchroniseerd wordt, zegt
        /// CloudStatus.
        case cloud
        /// Alleen op dit apparaat, met de reden erbij.
        case local(reason: String)
        /// De opslag ging niet (goed) open. Er wordt niets weggeschreven.
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

    static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "Scoreblok", directoryHint: .isDirectory)
    }

    /// Het iCloud-bestand houdt de oude naam: versies van vóór de keuze
    /// openden dit bestand al met CloudKit, dus bestaande gegevens staan
    /// daar, met de koppeling naar iCloud erbij.
    static func storeURL(for choice: StorageChoice) -> URL {
        switch choice {
        case .iCloud: directory.appending(path: "Scoreblok.store")
        case .local: directory.appending(path: "Scoreblok-lokaal.store")
        }
    }

    static func storeExists(for choice: StorageChoice) -> Bool {
        FileManager.default.fileExists(atPath: storeURL(for: choice).path(percentEncoded: false))
    }

    /// Opent de opslag voor een keuze, zonder de modus aan te passen.
    /// Lokaal krijgt uitdrukkelijk géén CloudKit; iCloud alleen de eigen
    /// container. Alleen-lezen opent zonder CloudKit, om uit te lezen.
    static func container(for choice: StorageChoice, readOnly: Bool = false) throws -> ModelContainer {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database: ModelConfiguration.CloudKitDatabase =
            (choice == .iCloud && !readOnly) ? .private(cloudContainerID) : .none
        let configuration = ModelConfiguration(schema: schema,
                                               url: storeURL(for: choice),
                                               allowsSave: !readOnly,
                                               cloudKitDatabase: database)
        return try ModelContainer(for: schema,
                                  migrationPlan: ScoreblokMigrationPlan.self,
                                  configurations: configuration)
    }

    /// Opent de opslag voor gebruik in de app en zet de modus.
    static func open(_ choice: StorageChoice) -> ModelContainer {
        do {
            let opened = try container(for: choice)
            markOpened(choice)
            return opened
        } catch {
            let reason = error.localizedDescription
            // Nooit ongemerkt naar de andere kant: dan kijk je naar andere
            // gegevens dan je denkt. Liever je eigen potjes, alleen-lezen.
            if let readOnly = try? container(for: choice, readOnly: true) {
                mode = .failed(reason: "De opslag ging alleen-lezen open (\(reason)). Je ziet je potjes, maar er wordt niets bewaard. Maak een reservekopie.")
                return readOnly
            }
            mode = .failed(reason: "De opslag ging niet open (\(reason)). Er wordt niets bewaard.")
        }

        // Laatste redmiddel zodat de app niet omvalt. De zijbalk laat zien
        // dat er niets bewaard wordt.
        let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // swiftlint:disable:next force_try
        return try! ModelContainer(for: schema, configurations: memory)
    }

    static func markOpened(_ choice: StorageChoice) {
        mode = choice == .iCloud ? .cloud : .local(reason: "Alleen op dit apparaat")
    }

    /// Verwijdert het bestand van één kant, met de bijbehorende bestanden.
    /// Bij iCloud is dat alleen de kopie op dit apparaat: wat op de server en
    /// op je andere apparaten staat, blijft.
    static func removeStore(for choice: StorageChoice) throws {
        let url = storeURL(for: choice)
        let manager = FileManager.default
        for suffix in ["", "-shm", "-wal"] {
            let file = directory.appending(path: url.lastPathComponent + suffix)
            if manager.fileExists(atPath: file.path(percentEncoded: false)) {
                try manager.removeItem(at: file)
            }
        }
        let base = url.deletingPathExtension().lastPathComponent
        let support = directory.appending(path: ".\(base)_SUPPORT", directoryHint: .isDirectory)
        if manager.fileExists(atPath: support.path(percentEncoded: false)) {
            try? manager.removeItem(at: support)
        }
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

    /// Hoe groot de gekozen opslag is, voor de opslagkaart.
    static var storeDescription: String {
        let url = storeURL(for: StorageChoice.saved ?? .local)
        let manager = FileManager.default
        let bytes = ["", "-wal"].compactMap { suffix -> Int? in
            let path = directory.appending(path: url.lastPathComponent + suffix).path(percentEncoded: false)
            return try? manager.attributesOfItem(atPath: path)[.size] as? Int
        }.reduce(0, +)
        guard bytes > 0 else { return "Nog geen bestand" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
