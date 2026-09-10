import AppIntents
import Foundation
import SwiftData

/// Toegang tot de opslag buiten de app om, voor Siri en Shortcuts. Altijd
/// de opslag die de app zelf gebruikt, nooit een eigen tweede venster op een
/// bestand.
enum IntentStore {
    enum Failure: Error, CustomLocalizedStringResourceConvertible {
        case notChosen

        var localizedStringResource: LocalizedStringResource {
            "Open Scoreblok eerst en kies waar je potjes staan."
        }
    }

    @MainActor
    static func context() throws -> ModelContext {
        guard let container = StoreController.shared.container else { throw Failure.notChosen }
        return container.mainContext
    }
}

// MARK: - Wie staat voor

struct StandingsIntent: AppIntent {
    static let title: LocalizedStringResource = "Stand van het potje"
    static let description = IntentDescription(
        "Vertelt hoe het lopende potje ervoor staat.",
        categoryName: "Scoreblok"
    )
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try IntentStore.context()
        let matches = try context.fetch(FetchDescriptor<Match>())
        guard let match = matches.filter(\.isOpen).max(by: { $0.lastPlayedAt < $1.lastPlayedAt })
        else {
            return .result(dialog: "Er loopt op dit moment geen potje.")
        }

        let standings = match.standings
        guard let leader = standings.first else {
            return .result(dialog: "\(match.gameName) is begonnen, maar er staat nog niets op het blok.")
        }

        let rest = standings.dropFirst()
            .map { "\($0.player.name) \($0.total)" }
            .joined(separator: ", ")
        let unit = match.unitLabel
        let line = rest.isEmpty
            ? "\(leader.player.name) staat voor met \(leader.total) \(unit)."
            : "\(leader.player.name) staat voor met \(leader.total) \(unit). Daarna \(rest)."

        return .result(dialog: IntentDialog(stringLiteral: "\(match.gameName): \(line)"))
    }
}

// MARK: - Nieuw potje starten

struct StartMatchIntent: AppIntent {
    static let title: LocalizedStringResource = "Nieuw potje starten"
    static let description = IntentDescription(
        "Opent Scoreblok bij het opzetten van een potje.",
        categoryName: "Scoreblok"
    )
    static let openAppWhenRun = true

    @Parameter(title: "Spel")
    var game: GameEntity?

    @MainActor
    func perform() async throws -> some IntentResult {
        if let game { PendingAction.shared.startGameID = game.id }
        return .result()
    }
}

/// Het spel als iets waar Siri en Shortcuts naar kunnen verwijzen.
struct GameEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Spel")
    static let defaultQuery = GameQuery()

    var id: UUID
    var name: String
    var subtitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(subtitle)")
    }
}

struct GameQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [GameEntity] {
        try all().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [GameEntity] {
        try all()
    }

    @MainActor
    private func all() throws -> [GameEntity] {
        let context = try IntentStore.context()
        let templates = try context.fetch(
            FetchDescriptor<GameTemplate>(sortBy: [SortDescriptor(\.sortIndex)])
        )
        return templates.map {
            GameEntity(id: $0.id, name: $0.name, subtitle: $0.subtitle)
        }
    }
}

/// Wat de app moet doen zodra hij vanuit Siri of Shortcuts opent.
@Observable
final class PendingAction {
    @MainActor static let shared = PendingAction()
    var startGameID: UUID?
}

// MARK: - Kant-en-klare zinnen

struct ScoreblokShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StandingsIntent(),
            phrases: [
                "Wie staat voor in \(.applicationName)",
                "Wat is de stand in \(.applicationName)",
                "\(.applicationName) stand"
            ],
            shortTitle: "Stand van het potje",
            systemImageName: "list.number"
        )
        AppShortcut(
            intent: StartMatchIntent(),
            phrases: [
                "Nieuw potje in \(.applicationName)",
                "Start een potje in \(.applicationName)"
            ],
            shortTitle: "Nieuw potje",
            systemImageName: "plus"
        )
    }
}
