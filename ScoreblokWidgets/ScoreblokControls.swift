import AppIntents
import SwiftUI
import WidgetKit

/// Een knop in het Bedieningspaneel of op het toegangsscherm: meteen naar het
/// kiezen van een spel.
struct NewMatchControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "nl.scoreblok.control.nieuw") {
            ControlWidgetButton(action: OpenNewMatchIntent()) {
                Label("Nieuw potje", systemImage: "plus.rectangle.on.rectangle")
            }
        }
        .displayName("Nieuw potje")
        .description("Opent Scoreblok om een spel te kiezen.")
    }
}

/// Wie er leidt, zonder de app te openen. Tik en je zit in het potje.
struct StandingsControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "nl.scoreblok.control.stand",
                                   provider: LeaderValueProvider()) { leader in
            ControlWidgetButton(action: OpenStandingsIntent()) {
                Label(leader, systemImage: "list.number")
            }
        }
        .displayName("Stand")
        .description("Wie er leidt in het potje dat nu loopt.")
    }
}

struct LeaderValueProvider: ControlValueProvider {
    var previewValue: String { "Lisa · 42" }

    func currentValue() async throws -> String {
        let snapshot = await MainActor.run { WidgetSnapshot.read() }
        guard let open = snapshot?.open, let leader = open.leader else {
            return "Geen potje"
        }
        return "\(leader.name) · \(leader.total)"
    }
}
