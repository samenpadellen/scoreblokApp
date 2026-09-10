import SwiftUI
import SwiftData

struct FinishScreen: View {
    let match: Match

    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @Query private var allMatches: [Match]

    /// Dit potje was het tiende van dit spel: de extra statistieken zijn net vrijgespeeld.
    private var unlocksInsights: Bool {
        match.counts && Insights.unlockingMatchID(for: match.gameName, in: allMatches) == match.id
    }

    private var standings: [Standing] { match.standings }
    @State private var scorecardURL: URL?
    @Environment(\.isCompact) private var isCompact

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                HeavyRule()
                podium
                HeavyRule()
                if unlocksInsights {
                    unlockBanner
                    HeavyRule()
                }
                actions
            }
        }
        .task(id: match.id) {
            scorecardURL = ScorecardExport.pdf(for: match)
        }
    }

    // MARK: - Kop

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Eindstand · \(match.gameName)")
                .padding(.bottom, 12)
            Text(winnerLine)
                .font(M.font(isCompact ? 34 : 42, .extraBold))
                .tracking(em: -0.03, size: isCompact ? 34 : 42)
                .foregroundStyle(M.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(meta)
                .font(M.font(13.5, .regular))
                .foregroundStyle(M.inkAlpha(0.6))
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: isCompact ? 16 : 26, leading: isCompact ? 20 : 28,
                            bottom: isCompact ? 20 : 22, trailing: isCompact ? 20 : 28))
    }

    private var winnerLine: String {
        guard let top = standings.first else { return "Geen stand" }
        switch match.mode {
        case .winnerOnly: return "\(top.player.name) wint"
        case .elimination: return "\(top.player.name) blijft over"
        default: return "\(top.player.name) wint met \(top.total)"
        }
    }

    private var meta: String {
        var parts: [String] = []
        if match.mode == .roundsCumulative || match.mode == .elimination {
            let played = match.rounds.filter { !$0.entries.isEmpty }.count
            parts.append(played == 1 ? "1 ronde" : "\(played) rondes")
        }
        parts.append(match.durationText)
        parts.append("\(match.players.count) spelers")
        switch match.mode {
        case .winnerOnly: parts.append("alleen eindvolgorde")
        case .elimination: parts.append("afvallen bij \(match.eliminationLimit)")
        default: parts.append("\(match.winsByLowest ? "laagste" : "hoogste") totaal wint")
        }
        if match.isAbandoned { parts.append("afgebroken — telt nergens mee") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Vrijgespeeld

    private var unlockBanner: some View {
        RowButton(isActive: true, minHeight: 80) {
            router.screen = .insights(match.gameName)
        } content: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("VRIJGESPEELD")
                        .font(M.font(10, .extraBold))
                        .tracking(em: 0.14, size: 10)
                        .foregroundStyle(M.red)
                    Text("Extra statistieken voor \(match.gameName)")
                        .font(M.font(isCompact ? 16 : 18, .extraBold))
                        .foregroundStyle(M.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Tien potjes gespeeld. Nu zie je wie vaker wint met wie vóór zich, wie de meeste jokers krijgt en meer.")
                        .font(M.font(12, .regular))
                        .foregroundStyle(M.inkAlpha(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text("→")
                    .font(M.font(18, .semiBold))
                    .foregroundStyle(M.red)
            }
            .padding(.horizontal, isCompact ? 20 : 28)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Podium en stand

    @ViewBuilder
    private var podium: some View {
        if isCompact {
            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 0) { podiumColumns }
                    .padding(EdgeInsets(top: 22, leading: 20, bottom: 0, trailing: 20))
                HeavyRule().padding(.top, 22)
                SectionLabel("Volledige stand")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(EdgeInsets(top: 16, leading: 20, bottom: 10, trailing: 20))
                Hairline()
                standingsList(padding: 20, minHeight: 60)
            }
        } else {
            wideePodium
        }
    }

    /// Eerst het podium, daarna de volledige stand over de hele breedte.
    /// Naast het podium kreeg de stand de restruimte, en die was zo smal dat
    /// de namen tot "J…" werden afgekapt.
    private var wideePodium: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 0) {
                podiumColumns
                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: 28, leading: 28, bottom: 0, trailing: 28))

            HeavyRule().padding(.top, 24)
            SectionLabel("Volledige stand")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 16, leading: 28, bottom: 10, trailing: 28))
            Hairline()
            standingsList(padding: 28, minHeight: 50)
        }
    }

    @ViewBuilder
    private var podiumColumns: some View {
        ForEach(Array(standings.prefix(3).enumerated()), id: \.element.id) { index, standing in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 11) {
                        PlayerMark(player: standing.player, size: isCompact ? 26 : 34)
                        Text(standing.player.name)
                            .font(M.font(isCompact ? 13 : 16, .extraBold))
                            .foregroundStyle(M.ink)
                            .lineLimit(1)
                    }
                    .padding(.bottom, 12)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(standing.total)")
                            .font(M.font(isCompact ? 26 : 36, .extraBold))
                            .tracking(em: -0.03, size: isCompact ? 26 : 36)
                            .foregroundStyle(M.paper)
                        Spacer(minLength: 12)
                        Text(["1E", "2E", "3E"][index])
                            .font(M.font(isCompact ? 9 : 10, .semiBold))
                            .tracking(em: 0.1, size: isCompact ? 9 : 10)
                            .foregroundStyle(M.paper)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: isCompact ? [120, 96, 76][index] : [168, 132, 104][index])
                    .padding(isCompact ? 12 : 14)
                    .background([M.red, M.ink, Color(hex: 0x605D5D)][index])
                }
                .frame(maxWidth: isCompact ? .infinity : 190, alignment: .leading)
                .padding(.trailing, isCompact ? 0 : 16)
                .overlay(alignment: .trailing) {
                    if !isCompact { Rectangle().fill(M.hairline).frame(width: 1) }
                }
                .padding(.trailing, isCompact ? 12 : 16)
        }
    }

    private func standingsList(padding: CGFloat, minHeight: CGFloat) -> some View {
        ForEach(standings) { standing in
            HStack(spacing: isCompact ? 12 : 14) {
                Text("\(standing.rank)")
                    .font(M.font(isCompact ? 12 : 13, .extraBold))
                    .foregroundStyle(M.inkAlpha(0.4))
                    .frame(width: isCompact ? 14 : 18, alignment: .leading)
                Text(standing.player.name)
                    .font(M.font(15, .semiBold))
                    .foregroundStyle(M.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if !isCompact {
                    Text(detail(for: standing))
                        .font(M.font(12, .regular))
                        .foregroundStyle(M.inkAlpha(0.5))
                        .lineLimit(1)
                }
                Text("\(standing.total)")
                    .font(M.font(19, .extraBold))
                    .foregroundStyle(M.ink)
                    .frame(width: 54, alignment: .trailing)
            }
            .padding(.horizontal, padding)
            .frame(minHeight: minHeight)
            .overlay(alignment: .bottom) { Hairline() }
        }
    }

    private func detail(for standing: Standing) -> String {
        switch match.mode {
        case .winnerOnly:
            return "plek \(standing.total)"
        case .scorecard:
            return "scorekaart"
        default:
            guard standing.roundsPlayed > 0 else { return "geen rondes" }
            let best = standing.bestRound.map { "beste ronde \($0)" } ?? ""
            return "\(best) · gem. \(standing.average.dutch(1))"
        }
    }

    // MARK: - Acties

    private var actions: some View {
        AnyLayout(isCompact ? AnyLayout(VStackLayout(spacing: 0))
                  : AnyLayout(HStackLayout(spacing: 0))) {
            Button { playAgain() } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nog een potje")
                        .font(M.font(18, .extraBold))
                        .foregroundStyle(M.paper)
                    Text("Zelfde spel, zelfde \(match.players.count) spelers")
                        .font(M.font(12, .regular))
                        .foregroundStyle(M.paper.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: isCompact ? 68 : 76)
                .padding(.horizontal, isCompact ? 20 : 28)
                .background(M.red)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Rectangle().fill(M.paper.opacity(0.3)).frame(width: 1)

            Button { router.screen = .stats } label: {
                Text("Naar statistieken")
                    .font(M.font(15, .extraBold))
                    .foregroundStyle(M.ink)
                    .frame(maxWidth: isCompact ? .infinity : 230, alignment: .leading)
                    .frame(minHeight: isCompact ? 60 : 76)
                    .padding(.horizontal, 24)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Rectangle().fill(M.hairline).frame(width: 1)

            if let scorecardURL {
                ShareLink(item: scorecardURL) {
                    Text("Deel het blaadje")
                        .font(M.font(15, .extraBold))
                        .foregroundStyle(M.ink)
                        .frame(maxWidth: isCompact ? .infinity : 200, alignment: .leading)
                        .frame(minHeight: isCompact ? 60 : 76)
                        .padding(.horizontal, 24)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                Rectangle().fill(M.hairline).frame(width: 1)
            }

            Button { router.screen = .play } label: {
                Text("Klaar")
                    .font(M.font(15, .semiBold))
                    .foregroundStyle(M.inkAlpha(0.6))
                    .frame(maxWidth: isCompact ? .infinity : 150, alignment: .leading)
                    .frame(minHeight: isCompact ? 60 : 76)
                    .padding(.horizontal, 24)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private func playAgain() {
        let descriptor = FetchDescriptor<GameTemplate>()
        let templates = (try? context.fetch(descriptor)) ?? []
        guard let template = templates.first(where: { $0.name == match.gameName }) else {
            router.screen = .play
            return
        }

        let players = match.orderedPlayers
        let next = Match(template: template)
        context.insert(next)
        next.seat(players)
        // Dit potje erft de regels van het vorige, niet die van het sjabloon.
        next.roundCount = match.roundCount
        next.winsByLowest = match.winsByLowest
        next.allowNegative = match.allowNegative
        next.eliminationLimit = match.eliminationLimit

        if next.mode == .scorecard {
            for player in players {
                let card = ScoreCard(playerID: player.id)
                context.insert(card)
                card.match = next
                next.cards.append(card)
            }
            router.screen = .card(next)
        } else {
            router.screen = .board(next)
        }
    }
}
