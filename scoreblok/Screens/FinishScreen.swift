import SwiftUI
import SwiftData

struct FinishScreen: View {
    let match: Match

    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context

    private var standings: [Standing] { match.standings }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                HeavyRule()
                podium
                HeavyRule()
                actions
            }
        }
    }

    // MARK: - Kop

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Eindstand · \(match.gameName)")
                .padding(.bottom, 12)
            Text(winnerLine)
                .font(M.font(42, .extraBold))
                .tracking(em: -0.03, size: 42)
                .foregroundStyle(M.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(meta)
                .font(M.font(13.5, .regular))
                .foregroundStyle(M.inkAlpha(0.6))
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 26, leading: 28, bottom: 22, trailing: 28))
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

    // MARK: - Podium en stand

    private var podium: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(standings.prefix(3).enumerated()), id: \.element.id) { index, standing in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 11) {
                        PlayerMark(player: standing.player)
                        Text(standing.player.name)
                            .font(M.font(16, .extraBold))
                            .foregroundStyle(M.ink)
                            .lineLimit(1)
                    }
                    .padding(.bottom, 12)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(standing.total)")
                            .font(M.font(36, .extraBold))
                            .tracking(em: -0.03, size: 36)
                            .foregroundStyle(M.paper)
                        Spacer(minLength: 12)
                        Text(["1E PLAATS", "2E PLAATS", "3E PLAATS"][index])
                            .font(M.font(10, .semiBold))
                            .tracking(em: 0.12, size: 10)
                            .foregroundStyle(M.paper)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: [168, 132, 104][index])
                    .padding(14)
                    .background([M.red, M.ink, Color(hex: 0x605D5D)][index])
                }
                .frame(width: 190, alignment: .leading)
                .padding(.trailing, 16)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(M.hairline).frame(width: 1)
                }
                .padding(.trailing, 16)
            }

            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("Volledige stand")
                    .padding(.bottom, 10)
                ForEach(standings) { standing in
                    HStack(spacing: 14) {
                        Text("\(standing.rank)")
                            .font(M.font(13, .extraBold))
                            .foregroundStyle(M.inkAlpha(0.4))
                            .frame(width: 18, alignment: .leading)
                        Text(standing.player.name)
                            .font(M.font(15, .semiBold))
                            .foregroundStyle(M.ink)
                        Spacer(minLength: 8)
                        Text(detail(for: standing))
                            .font(M.font(12, .regular))
                            .foregroundStyle(M.inkAlpha(0.5))
                            .lineLimit(1)
                        Text("\(standing.total)")
                            .font(M.font(19, .extraBold))
                            .foregroundStyle(M.ink)
                            .frame(width: 54, alignment: .trailing)
                    }
                    .frame(minHeight: 46)
                    .overlay(alignment: .bottom) { Hairline() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 22)
        }
        .padding(EdgeInsets(top: 28, leading: 28, bottom: 0, trailing: 28))
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
        HStack(spacing: 0) {
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
                .frame(minHeight: 76)
                .padding(.horizontal, 28)
                .background(M.red)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Rectangle().fill(M.paper.opacity(0.3)).frame(width: 1)

            Button { router.screen = .stats } label: {
                Text("Naar statistieken")
                    .font(M.font(15, .extraBold))
                    .foregroundStyle(M.ink)
                    .frame(width: 230, alignment: .leading)
                    .frame(minHeight: 76)
                    .padding(.horizontal, 24)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Rectangle().fill(M.hairline).frame(width: 1)

            Button { router.screen = .play } label: {
                Text("Klaar")
                    .font(M.font(15, .semiBold))
                    .foregroundStyle(M.inkAlpha(0.6))
                    .frame(width: 150, alignment: .leading)
                    .frame(minHeight: 76)
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
