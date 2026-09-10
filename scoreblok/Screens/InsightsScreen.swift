import SwiftUI
import SwiftData

/// De statistieken die je vrijspeelt na tien potjes van hetzelfde spel.
/// Nog niet vrijgespeeld: wat er komt en hoe ver je bent.
struct InsightsScreen: View {
    let gameName: String

    @Environment(Router.self) private var router
    @Environment(\.isCompact) private var isCompact
    @Query private var allMatches: [Match]

    private var padding: CGFloat { isCompact ? 20 : 28 }

    var body: some View {
        let count = Insights.counted(allMatches, game: gameName).count
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(count: count)
                HeavyRule()
                if count < Insights.unlockAt {
                    locked(count: count)
                } else {
                    let sections = Insights.sections(for: gameName, in: allMatches)
                    if sections.isEmpty {
                        quiet
                    } else {
                        ForEach(sections) { section in
                            sectionView(section)
                            HeavyRule()
                        }
                    }
                    footnote
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Kop

    private func header(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            BackLink(title: "Statistieken") { router.screen = .stats }
            Text(count >= Insights.unlockAt ? "VRIJGESPEELD · \(count) POTJES" : "NOG NIET VRIJGESPEELD")
                .font(M.font(10, .semiBold))
                .tracking(em: 0.14, size: 10)
                .foregroundStyle(M.red)
            Text(gameName)
                .font(M.font(isCompact ? 32 : 34, .extraBold))
                .tracking(em: -0.025, size: isCompact ? 32 : 34)
                .foregroundStyle(M.ink)
            Text("Patronen over alle afgeronde potjes, niet alleen de gekozen periode.")
                .font(M.font(12.5, .regular))
                .foregroundStyle(M.inkAlpha(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 8, leading: padding, bottom: 18, trailing: padding))
    }

    // MARK: - Inzichten

    private func sectionView(_ section: Insights.Section) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(section.title)
                .font(M.font(18, .extraBold))
                .foregroundStyle(M.ink)
            Text(section.note)
                .font(M.font(12, .regular))
                .foregroundStyle(M.inkAlpha(0.55))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
                .padding(.bottom, 12)
            ForEach(section.lines) { line in
                Hairline()
                lineView(line)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 20, leading: padding, bottom: 16, trailing: padding))
    }

    private func lineView(_ line: Insights.Line) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.figure)
                    .font(M.font(26, .extraBold))
                    .tracking(em: -0.03, size: 26)
                    .foregroundStyle(M.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(line.unit)
                    .font(M.font(10, .semiBold))
                    .foregroundStyle(M.inkAlpha(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: isCompact ? 84 : 110, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                if !line.players.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(line.players) { player in
                            PlayerMark(player: player, size: 20)
                        }
                    }
                }
                Text(line.title)
                    .font(M.font(15, .semiBold))
                    .foregroundStyle(M.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(line.detail)
                    .font(M.font(12, .regular))
                    .foregroundStyle(M.inkAlpha(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    private var quiet: some View {
        Text("Nog geen opvallende patronen. Iedereen doet het ongeveer even goed, waar iedereen ook zit.")
            .font(M.font(14, .regular))
            .foregroundStyle(M.inkAlpha(0.65))
            .fixedSize(horizontal: false, vertical: true)
            .padding(EdgeInsets(top: 22, leading: padding, bottom: 22, trailing: padding))
    }

    private var footnote: some View {
        Text("Een patroon uit een handvol potjes kan toeval zijn. Hoe vaker je speelt, hoe betrouwbaarder het wordt.")
            .font(M.font(11.5, .regular))
            .foregroundStyle(M.inkAlpha(0.5))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(EdgeInsets(top: 18, leading: padding, bottom: 28, trailing: padding))
    }

    // MARK: - Nog niet vrijgespeeld

    private func locked(count: Int) -> some View {
        let remaining = max(Insights.unlockAt - count, 0)
        let teasers = ["Wie vaker wint met wie direct vóór zich",
                       "Wie de meeste jokers krijgt",
                       "Of beginnen of voorstaan helpt",
                       "Wie meestal vóór wie eindigt"]
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(count) van \(Insights.unlockAt) potjes")
                    .font(M.font(22, .extraBold))
                    .foregroundStyle(M.ink)
                Spacer(minLength: 8)
                Text("nog \(remaining)")
                    .font(M.font(12.5, .semiBold))
                    .foregroundStyle(M.inkAlpha(0.55))
            }
            BarMeter(fraction: Double(count) / Double(Insights.unlockAt),
                     height: 10, fill: M.red, track: M.paperDeep)
            Text("Speel nog \(remaining == 1 ? "1 potje" : "\(remaining) potjes") \(gameName) en je ziet hier:")
                .font(M.font(13.5, .regular))
                .foregroundStyle(M.inkAlpha(0.7))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            ForEach(teasers, id: \.self) { item in
                HStack(alignment: .top, spacing: 10) {
                    Rectangle().fill(M.red).frame(width: 7, height: 2).padding(.top, 8)
                    Text(item)
                        .font(M.font(13.5, .semiBold))
                        .foregroundStyle(M.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(EdgeInsets(top: 22, leading: padding, bottom: 26, trailing: padding))
    }
}
