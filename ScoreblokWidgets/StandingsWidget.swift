import SwiftUI
import WidgetKit

/// De stand van het lopende potje op het beginscherm. Leest de momentopname
/// die de app in de gedeelde map zet; de database zelf blijft onaangeroerd.
struct StandingsEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct StandingsProvider: TimelineProvider {
    func placeholder(in context: Context) -> StandingsEntry {
        StandingsEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (StandingsEntry) -> Void) {
        let snapshot = context.isPreview ? .preview : WidgetSnapshot.read()
        completion(StandingsEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StandingsEntry>) -> Void) {
        let entry = StandingsEntry(date: .now, snapshot: WidgetSnapshot.read())
        // De app vernieuwt de tijdlijn zelf zodra er iets verandert; dit is
        // alleen een vangnet voor het geval dat niet gebeurt.
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(1800))))
    }
}

struct StandingsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "nl.scoreblok.standings",
                            provider: StandingsProvider()) { entry in
            StandingsWidgetView(snapshot: entry.snapshot)
                .containerBackground(M.paper, for: .widget)
        }
        .configurationDisplayName("Stand")
        .description("De stand van het potje dat nu loopt.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct StandingsWidgetView: View {
    let snapshot: WidgetSnapshot?
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot {
            content(snapshot)
        } else {
            empty
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SCOREBLOK")
                .font(M.font(9.5, .semiBold))
                .tracking(em: 0.14, size: 9.5)
                .foregroundStyle(M.inkAlpha(0.5))
            Text("Geen potje open")
                .font(M.font(family == .systemSmall ? 16 : 20, .extraBold))
                .foregroundStyle(M.ink)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func content(_ snapshot: WidgetSnapshot) -> some View {
        let rows = family == .systemSmall ? 2 : (family == .systemMedium ? 4 : 8)

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(snapshot.mono)
                    .font(M.font(11, .extraBold))
                    .foregroundStyle(M.paper)
                    .frame(width: 24, height: 24)
                    .background(M.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.gameName)
                        .font(M.font(family == .systemSmall ? 14 : 16, .extraBold))
                        .foregroundStyle(M.ink)
                        .lineLimit(1)
                    if family != .systemSmall {
                        Text(snapshot.position)
                            .font(M.font(11, .regular))
                            .foregroundStyle(M.inkAlpha(0.55))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 8)

            Rectangle().fill(M.ruleHeavy).frame(height: 2)

            ForEach(snapshot.standings.prefix(rows)) { entry in
                row(entry, leading: entry.rank == 1)
                if entry.id != snapshot.standings.prefix(rows).last?.id {
                    Rectangle().fill(M.hairline).frame(height: 1)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ entry: WidgetSnapshot.Entry, leading: Bool) -> some View {
        let ramp = M.playerRamp[((entry.rampIndex % M.playerRamp.count)
                                 + M.playerRamp.count) % M.playerRamp.count]
        return HStack(spacing: 8) {
            AvatarShape(index: entry.avatarIndex)
                .fill(Color(hex: ramp.ink))
                .frame(width: 18, height: 18)
                .background(Color(hex: ramp.bg))
            Text(entry.name)
                .font(M.font(12.5, leading ? .extraBold : .semiBold))
                .foregroundStyle(M.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Text("\(entry.total)")
                .font(M.font(15, .extraBold))
                .foregroundStyle(leading ? M.red : M.ink)
                .monospacedDigit()
        }
        .padding(.vertical, 5)
    }
}

extension WidgetSnapshot {
    /// Alleen voor de voorvertoning in de widgetgalerij.
    static let preview = WidgetSnapshot(
        gameName: "Jokeren",
        mono: "JO",
        unitLabel: "kaarten",
        position: "ronde 4 · vier dezelfde",
        lastPlayed: .now,
        standings: [
            .init(id: UUID(), name: "Wouter", initial: "W", total: 16, rank: 1,
                  rampIndex: 0, avatarIndex: 2),
            .init(id: UUID(), name: "Joris", initial: "J", total: 38, rank: 2,
                  rampIndex: 2, avatarIndex: 0),
            .init(id: UUID(), name: "Eva", initial: "E", total: 42, rank: 3,
                  rampIndex: 3, avatarIndex: 8),
            .init(id: UUID(), name: "Sanne", initial: "S", total: 43, rank: 4,
                  rampIndex: 1, avatarIndex: 5)
        ],
        isOpen: true
    )
}
