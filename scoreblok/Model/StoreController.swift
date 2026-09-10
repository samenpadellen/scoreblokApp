import Foundation
import OSLog
import SwiftData
import SwiftUI

/// Kiest en beheert de opslag: lokaal óf iCloud, nooit allebei tegelijk.
///
/// Voorheen probeerde de app altijd eerst iCloud en viel hij stilletjes terug
/// op lokaal, met hetzelfde bestand voor beide. Wat je zag hing ervan af of
/// iCloud die dag meewerkte. Nu kies je, en de app houdt zich eraan:
/// - Lokaal opent een eigen bestand zonder enige koppeling met CloudKit.
/// - iCloud opent zijn eigen bestand met CloudKit, en zegt het eerlijk als
///   het account ontbreekt in plaats van ongemerkt lokaal verder te gaan.
///
/// Overstappen kopieert alles naar de andere kant, telt na, legt de keuze
/// vast, en ruimt pas daarna de oude kant op. Vooraf staat er altijd een
/// automatische reservekopie.
@MainActor
@Observable
final class StoreController {
    static let shared = StoreController()

    enum Phase: Equatable {
        case choosing
        case ready
        case working(String)

        var step: String {
            if case .working(let step) = self { return step }
            return "Opslag openen"
        }

        var isWorking: Bool {
            if case .working = self { return true }
            return false
        }
    }

    struct Notice: Equatable, Identifiable {
        let id = UUID()
        var text: String
        var isError: Bool
    }

    private(set) var choice: StorageChoice?
    private(set) var container: ModelContainer?
    /// Gaat omhoog bij elke nieuwe opslag, zodat de weergave helemaal opnieuw
    /// begint en nergens een verwijzing naar de oude blijft hangen.
    private(set) var generation = 0
    private(set) var phase: Phase = .choosing
    var notice: Notice?

    /// Zet schermen om die een kopie tonen die het opruimen gaat verwijderen.
    /// RootView vult dit in zodra hij verschijnt; daaraan ziet een overstap
    /// ook dat de weergave aan de nieuwe opslag hangt.
    @ObservationIgnored var reroute: (([PersistentIdentifier: any PersistentModel]) -> Void)?

    @ObservationIgnored private let cloud = CloudStatus.shared
    @ObservationIgnored private var repairTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "nl.scoreblok.app", category: "opslag")

    private init() {
        choice = StorageChoice.saved
        if let choice {
            // Staat de andere kant er nog, dan is een overstap halverwege
            // onderbroken. De gekozen kant is dan altijd compleet: de keuze
            // wordt pas vastgelegd na het natellen. Het restant gaat voor de
            // zekerheid nog in het archief, en dan weg.
            let other: StorageChoice = choice == .local ? .iCloud : .local
            if Storage.storeExists(for: other) {
                if let document = try? Self.read(other) {
                    try? Backup.archive(document, reason: "restant-\(other.rawValue)")
                }
                removeLeftover(other)
            }
            adopt(Storage.open(choice), for: choice)
        } else {
            cloud.refresh()
        }
    }

    /// Er staan al potjes van vóór de keuze tussen lokaal en iCloud. Die
    /// versies gebruikten het bestand dat nu bij iCloud hoort.
    var hasExistingData: Bool {
        choice == nil && Storage.storeExists(for: .iCloud)
    }

    // MARK: - Eerste keuze

    func choose(_ new: StorageChoice) async {
        guard choice == nil, phase == .choosing else { return }

        if new == .iCloud {
            guard await cloud.checkAccount() else {
                notice = Notice(text: "Log eerst in bij iCloud in de Instellingen-app. \(cloud.account.summary).",
                                isError: true)
                return
            }
            // Bestaande potjes staan al in het iCloud-bestand: niets te verhuizen.
            commit(.iCloud, container: Storage.open(.iCloud))
            return
        }

        guard Storage.storeExists(for: .iCloud) else {
            commit(.local, container: Storage.open(.local))
            return
        }

        phase = .working("Je potjes verhuizen naar dit apparaat")
        do {
            let target = try copyToLocal(from: .iCloud)
            commit(.local, container: target)
            removeLeftover(.iCloud)
            notice = Notice(text: "Je potjes staan nu alleen op dit apparaat.", isError: false)
        } catch {
            try? Storage.removeStore(for: .local)
            phase = .choosing
            notice = Notice(text: "Overzetten lukte niet: \(error.localizedDescription) Er is niets gewist.",
                            isError: true)
        }
    }

    // MARK: - Overstappen

    func switchTo(_ new: StorageChoice) async {
        guard let current = choice, current != new, phase == .ready else { return }

        if new == .iCloud, !(await cloud.checkAccount()) {
            notice = Notice(text: "Overstappen naar iCloud kan pas als dit apparaat is ingelogd bij iCloud. \(cloud.account.summary).",
                            isError: true)
            return
        }

        if let container { Storage.save(container.mainContext) }
        phase = .working(new == .iCloud ? "Je potjes gaan naar iCloud" : "Je potjes komen naar dit apparaat")
        repairTask?.cancel()
        repairTask = nil
        cloud.onImport = nil

        guard await release(fallback: current) else {
            notice = Notice(text: "Overstappen kon nu niet beginnen. Probeer het zo nog eens; er is niets veranderd.",
                            isError: true)
            return
        }

        do {
            switch new {
            case .local:
                commit(.local, container: try copyToLocal(from: current))
            case .iCloud:
                try await copyToICloud(from: current)
                commit(.iCloud, container: nil)
            }
            removeLeftover(current)
            notice = Notice(text: new == .iCloud
                            ? "iCloud staat aan. Je andere apparaten krijgen je potjes zodra ze online zijn."
                            : "Dit apparaat synchroniseert niet meer. In iCloud en op je andere apparaten blijft alles staan.",
                            isError: false)
        } catch {
            logger.error("Overstap mislukt: \(error.localizedDescription, privacy: .public)")
            // De weergave los van de half gevulde bestemming, die dan weg kan:
            // de bron is onaangeroerd.
            if container != nil { _ = await release(fallback: nil) }
            try? Storage.removeStore(for: new)
            adopt(Storage.open(current), for: current)
            notice = Notice(text: "Overstappen lukte niet: \(error.localizedDescription) Je potjes staan nog waar ze stonden.",
                            isError: true)
        }
    }

    /// Na het terugzetten van een reservekopie in iCloud: kan dubbelingen
    /// geven zodra dezelfde potjes van een ander apparaat binnenkomen.
    func didRestoreBackup() {
        guard choice == .iCloud, let container else { return }
        Self.pendingMerge = .now
        SyncRepair.run(in: container.mainContext, includeSameID: true) { [weak self] map in
            self?.reroute?(map)
        }
    }

    // MARK: - Verhuizen

    enum MoveError: LocalizedError {
        case incomplete(expected: String, found: String)
        case notAttached

        var errorDescription: String? {
            switch self {
            case let .incomplete(expected, found):
                "Na het overzetten klopte de telling niet (verwacht \(expected), gevonden \(found))."
            case .notAttached:
                "De nieuwe opslag kwam niet in beeld."
            }
        }
    }

    /// Laat de huidige opslag los en wacht tot de weergave hem echt heeft
    /// losgelaten. Lukt dat niet binnen tien seconden, dan neemt de app de
    /// oude opslag weer in gebruik (als die is opgegeven) en meldt `false`.
    private func release(fallback: StorageChoice?) async -> Bool {
        weak var previous = container
        container = nil
        reroute = nil
        cloud.start(containerIsCloud: false)
        let started = ContinuousClock.now
        while previous != nil, ContinuousClock.now - started < .seconds(10) {
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard let lingering = previous else { return true }
        logger.error("Opslag niet losgelaten door de weergave")
        if let fallback { adopt(lingering, for: fallback) }
        return false
    }

    /// Kopieert naar een nieuw lokaal bestand en telt na. Een lokale opslag
    /// heeft geen CloudKit en kan dus veilig worden gevuld zonder dat de
    /// weergave eraan hangt.
    private func copyToLocal(from source: StorageChoice) throws -> ModelContainer {
        let document = try Self.read(source)
        try Backup.archive(document, reason: "voor-overstap-naar-local")
        try Storage.removeStore(for: .local)
        let destination = try Storage.container(for: .local)
        try Backup.restore(document, into: destination.mainContext)
        let found = try Backup.make(from: destination.mainContext).tally
        guard found.covers(document.tally) else {
            throw MoveError.incomplete(expected: document.tally.description, found: found.description)
        }
        Storage.markOpened(.local)
        return destination
    }

    /// Naar iCloud gaat het in een andere volgorde. Wegschrijven in een
    /// iCloud-opslag die nog niet aan de weergave hing, liet de app op de
    /// simulator drie keer op drie vastlopen in SwiftData, zodra CloudKit het
    /// opzetten had opgegeven. Dezelfde opslag mét weergave schreef in
    /// dezelfde toestand zonder problemen weg. Daarom eerst koppelen, dan
    /// kopiëren — achter het voortgangsscherm, zodat niemand er tussendoor
    /// iets aan verandert.
    private func copyToICloud(from source: StorageChoice) async throws {
        let document = try Self.read(source)
        try Backup.archive(document, reason: "voor-overstap-naar-iCloud")

        // Een iCloud-bestand dat er nu nog staat is een restant: de kopie van
        // wat in iCloud staat komt vers binnen.
        try Storage.removeStore(for: .iCloud)
        let destination = try Storage.container(for: .iCloud)
        Storage.markOpened(.iCloud)
        container = destination
        generation += 1
        cloud.start(containerIsCloud: true)

        // RootView meldt zich bij het verschijnen; pas dan hangt de weergave
        // aan de nieuwe opslag.
        let mounting = ContinuousClock.now
        while reroute == nil, ContinuousClock.now - mounting < .seconds(10) {
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard reroute != nil else { throw MoveError.notAttached }

        // Eerst ophalen wat er al in iCloud staat. Wie meteen samenvoegt,
        // krijgt dezelfde potjes straks nog een keer binnen.
        phase = .working("iCloud haalt op wat er al staat")
        if !(await waitForImport(timeout: .seconds(45))) {
            logger.notice("Samenvoegen zonder afgerond ophalen; opruimen volgt na de eerstvolgende ophaalronde")
        }

        phase = .working("Je potjes gaan naar iCloud")
        try Backup.restore(document, into: destination.mainContext)
        Self.pendingMerge = .now
        let found = try Backup.make(from: destination.mainContext).tally
        guard found.covers(document.tally) else {
            throw MoveError.incomplete(expected: document.tally.description, found: found.description)
        }
    }

    /// Leest een kant uit. Het tijdelijke venster op het bestand verdwijnt
    /// zodra deze functie terugkeert, vóórdat het bestand wordt opgeruimd.
    private static func read(_ source: StorageChoice) throws -> BackupDocument {
        let reader: ModelContainer
        do {
            reader = try Storage.container(for: source, readOnly: true)
        } catch {
            reader = try Storage.container(for: source)
        }
        return try Backup.make(from: reader.mainContext)
    }

    /// Wacht tot iCloud een ophaalronde heeft afgerond, of meldt dat het
    /// misging of te lang duurde.
    private func waitForImport(timeout: Duration) async -> Bool {
        let started = Date.now
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if let at = cloud.lastImportAt, at > started { return true }
            if let sync = cloud.lastSync, !sync.succeeded, sync.at > started { return false }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return false
    }

    /// Ruimt de kant op die niet gekozen is. Alleen als de gekozen kant
    /// compleet is: na een nagetelde overstap, of bij de start na een
    /// onderbroken overstap.
    private func removeLeftover(_ side: StorageChoice) {
        guard Storage.storeExists(for: side) else { return }
        do {
            try Storage.removeStore(for: side)
        } catch {
            logger.error("Opruimen van \(side.rawValue, privacy: .public) lukte niet: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - In gebruik nemen

    /// Legt de keuze vast. Zonder container is de opslag al in beeld.
    private func commit(_ new: StorageChoice, container opened: ModelContainer?) {
        StorageChoice.saved = new
        choice = new
        if new == .local { Self.pendingMerge = nil }
        if let opened {
            adopt(opened, for: new)
        } else {
            settle(for: new)
        }
    }

    private func adopt(_ opened: ModelContainer, for choice: StorageChoice) {
        container = opened
        generation += 1
        settle(for: choice)
    }

    /// De opslag is in gebruik: synchronisatie volgen en opruimen na ophalen.
    private func settle(for choice: StorageChoice) {
        phase = .ready
        cloud.start(containerIsCloud: choice == .iCloud && Storage.mode.isCloud)
        cloud.onImport = { [weak self] in self?.repairSoon(afterImport: true) }
        repairSoon(afterImport: false)
    }

    // MARK: - Opruimen na synchroniseren

    /// Het apparaat dat zelf samenvoegde, ruimt ook letterlijke kopieën op —
    /// tot er ná dat samenvoegen een ophaalronde is geweest.
    private static let mergeKey = "opslag.samengevoegdOp"

    static var pendingMerge: Date? {
        get {
            let stamp = UserDefaults.standard.double(forKey: mergeKey)
            return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: mergeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: mergeKey)
            }
        }
    }

    private func repairSoon(afterImport: Bool) {
        repairTask?.cancel()
        repairTask = Task { [weak self] in
            // Ophaalrondes komen vaak kort na elkaar; één keer opruimen volstaat.
            try? await Task.sleep(for: .seconds(afterImport ? 2 : 1))
            guard let self, !Task.isCancelled, self.phase == .ready,
                  let container = self.container else { return }
            let merged = Self.pendingMerge
            let report = SyncRepair.run(in: container.mainContext, includeSameID: merged != nil) { map in
                self.reroute?(map)
            }
            if report.total > 0 {
                self.logger.notice("Opgeruimd na synchroniseren: \(report.description, privacy: .public)")
            }
            if let merged, afterImport, let imported = self.cloud.lastImportAt, imported > merged {
                Self.pendingMerge = nil
            }
        }
    }
}
