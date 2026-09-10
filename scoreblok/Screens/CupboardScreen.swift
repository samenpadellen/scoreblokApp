import SwiftUI
import SwiftData

/// De spellenkast. Spellen die je niet speelt haal je uit het overzicht
/// zonder ze kwijt te raken — net als bij spelers bestaat verwijderen niet.
/// Gespeelde potjes blijven staan: die dragen hun eigen kopie van de regels.
struct CupboardScreen: View {
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.isCompact) private var isCompact
    @Query(sort: \GameTemplate.sortIndex) private var templates: [GameTemplate]
    @Query private var matches: [Match]

    private var onShelf: [GameTemplate] { templates.filter { !$0.isPutAway } }
    private var putAway: [GameTemplate] { templates.filter(\.isPutAway) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                HeavyRule()

                section("Op de plank — \(onShelf.count)",
                        note: "Deze spellen staan in het overzicht.")
                if onShelf.isEmpty { note("Alles staat in de kast.") }
                ForEach(onShelf) { template in
                    row(template, putAway: false)
                    Hairline()
                }

                section("In de kast — \(putAway.count)",
                        note: "Uit het overzicht, maar niet weg. Zet ze terug wanneer je wilt.")
                if putAway.isEmpty { note("De kast is leeg.") }
                ForEach(putAway) { template in
                    row(template, putAway: true)
                    Hairline()
                }

                Text("Een spel opbergen verandert niets aan gespeelde potjes: die dragen hun eigen kopie van de regels en blijven in de geschiedenis en de statistieken staan.")
                    .font(M.font(12.5, .regular))
                    .foregroundStyle(M.inkAlpha(0.55))
                    .lineSpacing(5)
                    .frame(maxWidth: 640, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(EdgeInsets(top: 20, leading: padding, bottom: 28, trailing: padding))
            }
        }
    }

    private var padding: CGFloat { isCompact ? 20 : 28 }

    private var header: some View {
        VStack(alignment: .leading, spacing: isCompact ? 10 : 0) {
            BackLink(title: "Spelen") { router.screen = .play }
            Text("Spellenkast")
                .font(M.font(isCompact ? 32 : 34, .extraBold))
                .tracking(em: -0.025, size: isCompact ? 32 : 34)
                .foregroundStyle(M.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: isCompact ? 8 : 12, leading: padding,
                            bottom: 16, trailing: padding))
    }

    private func section(_ title: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title, insets: EdgeInsets(top: 0, leading: padding, bottom: 0, trailing: padding))
            Text(note)
                .font(M.font(12, .regular))
                .foregroundStyle(M.inkAlpha(0.55))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 10, leading: padding, bottom: 10, trailing: padding))
        }
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func row(_ template: GameTemplate, putAway: Bool) -> some View {
        let played = matches.filter { $0.gameName == template.name && $0.counts }.count

        return HStack(spacing: 14) {
            // Groter dan elders: in de kast zoek je een spel op zijn doos.
            GameMark(mono: template.mono, name: template.name,
                     background: putAway ? M.inkAlpha(0.35) : M.ink,
                     size: isCompact ? 40 : 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(template.name)
                    .font(M.font(15, .semiBold))
                    .foregroundStyle(putAway ? M.inkAlpha(0.6) : M.ink)
                    .lineLimit(1)
                Text(played == 0 ? template.subtitle
                     : "\(template.subtitle) · \(played) gespeeld")
                    .font(M.font(11.5, .regular))
                    .foregroundStyle(M.inkAlpha(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            OutlineButton(title: putAway ? "Terug op de plank" : "In de kast",
                          tint: putAway ? M.red : M.ink) {
                template.isPutAway.toggle()
                Storage.save(context)
            }
        }
        .padding(.horizontal, padding)
        .frame(minHeight: 64)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(M.font(12.5, .regular))
            .foregroundStyle(M.inkAlpha(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, padding)
            .padding(.vertical, 18)
    }
}
