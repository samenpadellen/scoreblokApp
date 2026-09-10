import AppIntents
import Foundation
import SwiftData
import SwiftUI

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
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let context = try IntentStore.context()
        let matches = try context.fetch(FetchDescriptor<Match>())
        guard let match = matches.filter(\.isOpen).max(by: { $0.lastPlayedAt < $1.lastPlayedAt })
        else {
            return .result(dialog: "Er loopt op dit moment geen potje.", view: StandingsSnippet())
        }

        let standings = match.standings
        guard let leader = standings.first else {
            return .result(dialog: "\(match.gameName) is begonnen, maar er staat nog niets op het blok.",
                           view: StandingsSnippet())
        }

        let rest = standings.dropFirst()
            .map { "\($0.player.name) \($0.total)" }
            .joined(separator: ", ")
        let unit = match.unitLabel
        let line = rest.isEmpty
            ? "\(leader.player.name) staat voor met \(leader.total) \(unit)."
            : "\(leader.player.name) staat voor met \(leader.total) \(unit). Daarna \(rest)."

        let snippet = StandingsSnippet(
            title: match.gameName,
            rows: standings.map { .init(id: $0.player.id, rank: $0.rank, name: $0.player.name, total: $0.total) })
        return .result(dialog: IntentDialog(stringLiteral: "\(match.gameName): \(line)"), view: snippet)
    }
}

/// De stand zoals Siri hem laat zien: dezelfde vormgeving als de app.
struct StandingsSnippet: View {
    struct Row: Identifiable {
        var id: UUID
        var rank: Int
        var name: String
        var total: Int
    }

    var title = ""
    var rows: [Row] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !rows.isEmpty {
                Text(title.uppercased())
                    .font(M.font(10, .extraBold))
                    .tracking(em: 0.12, size: 10)
                    .foregroundStyle(M.red)
                    .padding(.bottom, 8)
                ForEach(rows.prefix(6)) { row in
                    HStack(spacing: 10) {
                        Text("\(row.rank)")
                            .font(M.font(12, .extraBold))
                            .foregroundStyle(M.inkAlpha(0.4))
                            .frame(width: 16, alignment: .leading)
                        Text(row.name)
                            .font(M.font(15, .semiBold))
                            .foregroundStyle(M.ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(row.total)")
                            .font(M.font(17, .extraBold))
                            .foregroundStyle(row.rank == 1 ? M.red : M.ink)
                    }
                    .padding(.vertical, 7)
                    .overlay(alignment: .bottom) { Rectangle().fill(M.hairline).frame(height: 1) }
                }
            }
        }
        .padding(rows.isEmpty ? 0 : 16)
        .background(rows.isEmpty ? Color.clear : M.paper)
    }
}

// MARK: - Spelers

struct PlayerStatsIntent: AppIntent {
    static let title: LocalizedStringResource = "Statistieken van een speler"
    static let description = IntentDescription(
        "Vertelt hoeveel potjes iemand speelde en won.",
        categoryName: "Scoreblok"
    )
    static let openAppWhenRun = false

    @Parameter(title: "Speler")
    var player: PlayerEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try IntentStore.context()
        let id = player.id
        guard let found = try context.fetch(FetchDescriptor<Player>(predicate: #Predicate { $0.id == id })).first
        else {
            return .result(dialog: "Die speler staat niet op het blok.")
        }
        let counted = try context.fetch(FetchDescriptor<Match>()).filter(\.counts)
        let results = StatsEngine.results(for: found, in: counted)
        guard !results.isEmpty else {
            return .result(dialog: IntentDialog(stringLiteral: "\(found.name) heeft nog geen potjes gespeeld."))
        }
        let wins = results.filter(\.isWin).count
        let rate = Int((Double(wins) / Double(results.count) * 100).rounded())
        let played = results.count == 1 ? "1 potje" : "\(results.count) potjes"
        var line = "\(found.name) speelde \(played) en won er \(wins), dat is \(rate) procent."
        if let favourite = Dictionary(grouping: results, by: \.gameName)
            .max(by: { $0.value.count < $1.value.count })?.key {
            line += " Het vaakst gespeeld: \(favourite)."
        }
        return .result(dialog: IntentDialog(stringLiteral: line))
    }
}

/// De speler als iets waar Siri en Shortcuts naar kunnen verwijzen.
struct PlayerEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Speler")
    static let defaultQuery = PlayerQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct PlayerQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [PlayerEntity] {
        try all().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [PlayerEntity] {
        let needle = SamenExchange.normalized(string)
        return try all().filter { SamenExchange.normalized($0.name).contains(needle) }
    }

    @MainActor
    func suggestedEntities() async throws -> [PlayerEntity] {
        try all()
    }

    @MainActor
    private func all() throws -> [PlayerEntity] {
        let context = try IntentStore.context()
        return try context.fetch(FetchDescriptor<Player>(sortBy: [SortDescriptor(\.name)]))
            .filter { !$0.isArchived }
            .map { PlayerEntity(id: $0.id, name: $0.name) }
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
    /// Na de eerste stappen: wie er bij het opzetten al aangevinkt staan.
    var setupPlayerIDs: [UUID]?
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
        AppShortcut(
            intent: PlayerStatsIntent(),
            phrases: [
                "Hoe vaak won \(\.$player) in \(.applicationName)",
                "Statistieken van \(\.$player) in \(.applicationName)",
                "Spelerstatistieken in \(.applicationName)"
            ],
            shortTitle: "Statistieken van een speler",
            systemImageName: "person.crop.square"
        )
    }
}
