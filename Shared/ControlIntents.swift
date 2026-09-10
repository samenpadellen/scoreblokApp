import AppIntents
import Foundation

/// Acties voor de knoppen in het Bedieningspaneel en op het toegangsscherm.
/// Ze staan in zowel de app als de widgets, en openen Scoreblok op de juiste
/// plek via een link die de app al kent.
struct OpenNewMatchIntent: AppIntent {
    static let title: LocalizedStringResource = "Kies een spel"
    static let description = IntentDescription("Opent Scoreblok bij het kiezen van een spel.")
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "scoreblok://play")!))
    }
}

struct OpenStandingsIntent: AppIntent {
    static let title: LocalizedStringResource = "Open de stand"
    static let description = IntentDescription("Opent het potje dat nu loopt.")
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult & OpensIntent {
        let snapshot = await MainActor.run { WidgetSnapshot.read() }
        let target = snapshot?.open.map { "scoreblok://match/\($0.id.uuidString)" }
            ?? "scoreblok://play"
        return .result(opensIntent: OpenURLIntent(URL(string: target)!))
    }
}
