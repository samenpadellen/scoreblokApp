import SwiftUI
import WidgetKit

/// Elke maat antwoordt op één vraag. Klein: wie leidt er nu. Middel: de
/// volledige stand. Groot: de stand plus de laatste rondes. Is er geen potje
/// open, dan wisselt de widget van taak en toont hij de ranglijst van de
/// speelgroep — een widget die de halve week leeg staat wordt weggehaald.
struct StandingsEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct StandingsProvider: TimelineProvider {
    func placeholder(in context: Context) -> StandingsEntry {
        StandingsEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (StandingsEntry) -> Void) {
        completion(StandingsEntry(date: .now,
                                  snapshot: context.isPreview ? .preview : WidgetSnapshot.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StandingsEntry>) -> Void) {
        // De app werkt de widget bij zodra een totaal verandert; deze
        // tijdlijn is alleen een vangnet.
        completion(Timeline(entries: [StandingsEntry(date: .now, snapshot: WidgetSnapshot.read())],
                            policy: .after(.now.addingTimeInterval(3600))))
    }
}

struct StandingsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "nl.scoreblok.standings",
                            provider: StandingsProvider()) { entry in
            StandingsWidgetView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Stand")
        .description("Wie leidt er in het potje dat nu loopt. Zonder open potje: de ranglijst.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

