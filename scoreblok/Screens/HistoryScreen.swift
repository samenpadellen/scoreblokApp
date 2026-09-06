import SwiftUI
import SwiftData

struct HistoryScreen: View {
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \Match.startedAt, order: .reverse) private var matches: [Match]
    @Query(sort: \Player.createdAt) private var players: [Player]

    @State private var opened: Match?
    @State private var gameFilter: String?
    @State private var playerFilter: UUID?
    @State private var yearFilter: Int?
    @Environment(\.isNarrow) private var isNarrow

    private var finished: [Match] { matches.filter { $0.isFinished } }

    private var filtered: [Match] {
        finished.filter { match in
            if let gameFilter, match.gameName != gameFilter { return false }
            if let playerFilter, !match.players.contains(where: { $0.id == playerFilter }) { return false }
            if let yearFilter {
                let year = Calendar.current.component(.year, from: match.endedAt ?? match.startedAt)
                if year != yearFilter { return false }
            }
            return true
        }
    }

    private var years: [Int] {
        Array(Set(finished.map {
            Calendar.current.component(.year, from: $0.endedAt ?? $0.startedAt)
        })).sorted(by: >)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                Hairline()
                filterBar
                HeavyRule()

                if let opened {
                    detail(opened)
                } else {
                    list
                }
            }
        }
    }

    private var header: some View {
        ScreenTitle("Geschiedenis")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 24, leading: 28, bottom: 18, trailing: 28))
    }

    private var filterBar: some View {
        HStack(spacing: 0) {
            filterMenu(label: gameFilter ?? "Alle spellen") {
                Button("Alle spellen") { gameFilter = nil }
                ForEach(Array(Set(finished.map(\.gameName))).sorted(), id: \.self) { name in
                    Button(name) { gameFilter = name }
                }
            }
            filterMenu(label: players.first { $0.id == playerFilter }?.name ?? "Alle spelers") {
                Button("Alle spelers") { playerFilter = nil }
                ForEach(players) { player in
                    Button(player.name) { playerFilter = player.id }
                }
            }
            filterMenu(label: yearFilter.map { "\($0)" } ?? "Alle jaren") {
                Button("Alle jaren") { yearFilter = nil }
                ForEach(years, id: \.self) { year in
                    Button("\(year)") { yearFilter = year }
                }
            }

            Spacer(minLength: 0)
            Text(countLine)
                .font(M.font(11.5, .regular))
                .foregroundStyle(M.inkAlpha(0.45))
                .padding(.horizontal, 28)
        }
    }

    private func filterMenu<Content: View>(label: String,
                                           @ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            Text("\(label) ▾")
                .font(M.font(12.5, .semiBold))
                .foregroundStyle(M.inkAlpha(0.65))
                .padding(.horizontal, 18)
                .frame(minHeight: 48)
        }
        .menuStyle(.borderlessButton)
        .overlay(alignment: .trailing) { Rectangle().fill(M.hairline).frame(width: 1) }
    }

    private var countLine: String {
        let abandoned = filtered.filter(\.isAbandoned).count
        let total = filtered.count
        var text = total == 1 ? "1 potje" : "\(total) potjes"
        if abandoned > 0 {
            text += " · \(abandoned) afgebroken (tellen nergens mee)"
        }
        return text
    }

    // MARK: - Lijst

    private var list: some View {
        VStack(spacing: 0) {
            if filtered.isEmpty {
                Text("Geen potjes gevonden met deze filters.")
                    .font(M.font(13, .regular))
                    .foregroundStyle(M.inkAlpha(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(28)
            }

            ForEach(filtered) { match in
                RowButton(minHeight: 70) {
                    opened = match
                } content: {
                    HStack(spacing: 18) {
                        Text((match.endedAt ?? match.startedAt)
                            .formatted(.dateTime.day().month(.abbreviated)).uppercased())
                            .font(M.font(11.5, .semiBold))
                            .foregroundStyle(M.inkAlpha(0.5))
                            .frame(width: 74, alignment: .leading)

                        GameMark(mono: match.mono, size: 34)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(match.gameName)
                                .font(M.font(15.5, .extraBold))
                                .foregroundStyle(M.ink)
                                .lineLimit(1)
                            Text(meta(match))
                                .font(M.font(11.5, .regular))
                                .foregroundStyle(M.inkAlpha(0.5))
                                .lineLimit(1)
                        }
                        .frame(width: isNarrow ? 130 : 170, alignment: .leading)

                        HStack(spacing: 8) {
                            ForEach(match.standings.prefix(isNarrow ? 3 : 5)) { standing in
                                HStack(spacing: 7) {
                                    PlayerMark(player: standing.player, size: 16)
                                    Text("\(standing.total)")
                                        .font(M.font(11.5, .semiBold))
                                        .foregroundStyle(M.ink)
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .overlay(Rectangle().stroke(M.hairline, lineWidth: 1))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Tag(text: match.isAbandoned ? "Afgebroken"
                            : "\(match.winner?.name ?? "—") won",
                            background: match.isAbandoned ? M.paperKey : M.ink,
                            foreground: match.isAbandoned ? M.inkAlpha(0.6) : M.paper)

                        Text("→")
                            .font(M.font(15, .regular))
                            .foregroundStyle(M.inkAlpha(0.35))
                    }
                    .padding(.horizontal, 28)
                }
                Hairline()
            }
        }
    }

    private func meta(_ match: Match) -> String {
        var parts: [String] = []
        switch match.mode {
        case .roundsCumulative, .elimination:
            let played = match.rounds.filter { !$0.entries.isEmpty }.count
            parts.append(played == 1 ? "1 ronde" : "\(played) rondes")
        case .scorecard: parts.append("scorekaart")
        case .winnerOnly: parts.append("geen punten")
        case .finalScore: parts.append("eindscore")
        }
        parts.append(match.durationText)
        return parts.joined(separator: " · ")
    }

    // MARK: - Terugkijken

    private func detail(_ match: Match) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                BackLink(title: "Alle potjes") { opened = nil }
                Spacer()
                Text("Regels zoals ze toen golden")
                    .font(M.font(11.5, .regular))
                    .foregroundStyle(M.inkAlpha(0.5))
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            Hairline()

            VStack(alignment: .leading, spacing: 0) {
                SectionLabel((match.endedAt ?? match.startedAt)
                    .formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute()))
                    .padding(.bottom, 10)
                Text(match.gameName)
                    .font(M.font(30, .extraBold))
                    .tracking(em: -0.02, size: 30)
                    .foregroundStyle(M.ink)
                Text(detailMeta(match))
                    .font(M.font(13, .regular))
                    .foregroundStyle(M.inkAlpha(0.6))
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 22, leading: 28, bottom: 18, trailing: 28))
            HeavyRule()

            if match.mode == .scorecard {
                scorecardSummary(match)
            } else {
                grid(match)
            }

            Text("Correcties zijn hier nog toegestaan via het potje zelf. Totalen en rangen worden dan opnieuw berekend, ook in de statistieken.")
                .font(M.font(12.5, .regular))
                .foregroundStyle(M.inkAlpha(0.55))
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 20, leading: 28, bottom: 20, trailing: 28))

            HStack(spacing: 10) {
                OutlineButton(title: match.isAbandoned ? "Toch meetellen" : "Markeer als afgebroken") {
                    match.abandonedAt = match.isAbandoned ? nil : .now
                }
                OutlineButton(title: "Heropenen") {
                    match.endedAt = nil
                    match.abandonedAt = nil
                    router.screen = match.mode == .scorecard ? .card(match) : .board(match)
                }
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
    }

    private func detailMeta(_ match: Match) -> String {
        var parts: [String] = [meta(match)]
        switch match.mode {
        case .winnerOnly: parts.append("alleen eindvolgorde")
        case .elimination: parts.append("afvallen bij \(match.eliminationLimit)")
        default: parts.append("\(match.winsByLowest ? "laagste" : "hoogste") wint")
        }
        if let winner = match.standings.first {
            parts.append("\(winner.player.name) won met \(winner.total)")
        }
        if match.isAbandoned { parts.append("afgebroken") }
        return parts.joined(separator: " · ")
    }

    private func grid(_ match: Match) -> some View {
        let seats = match.orderedPlayers
        let rounds = match.orderedRounds.filter { !$0.entries.isEmpty }

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(match.hasRoundLabels ? "RONDE · OPDRACHT" : "RONDE")
                    .font(M.font(10, .semiBold))
                    .tracking(em: 0.12, size: 10)
                    .foregroundStyle(M.inkAlpha(0.45))
                    .padding(.horizontal, match.hasRoundLabels ? 14 : 0)
                    .frame(width: match.hasRoundLabels ? 168 : M.roundColumnWidth,
                           alignment: match.hasRoundLabels ? .leading : .center)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.vertical, 10)
                    .overlay(alignment: .trailing) { Rectangle().fill(M.hairline).frame(width: 1) }

                ForEach(seats) { player in
                    let isWinner = match.standings.first?.player.id == player.id
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 10) {
                            PlayerMark(player: player, size: 28)
                            Text(player.name)
                                .font(M.font(13.5, .semiBold))
                                .foregroundStyle(M.ink)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.bottom, 8)
                        Text("\(match.total(for: player))")
                            .font(M.font(26, .extraBold))
                            .tracking(em: -0.03, size: 26)
                            .foregroundStyle(M.ink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(EdgeInsets(top: 10, leading: 14, bottom: 8, trailing: 14))
                    .background(isWinner ? M.paperDeep : .clear)
                    .overlay(alignment: .trailing) { Rectangle().fill(M.hairline).frame(width: 1) }
                }
            }
            HeavyRule()

            ForEach(rounds) { round in
                HStack(spacing: 0) {
                    Group {
                        if let label = match.roundLabel(at: round.index) {
                            HStack(spacing: 10) {
                                Text("\(round.index + 1)")
                                    .foregroundStyle(M.inkAlpha(0.35))
                                    .frame(width: 12, alignment: .trailing)
                                Text(label).lineLimit(1).minimumScaleFactor(0.85)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14)
                        } else {
                            Text(match.mode == .finalScore ? "EIND" : "\(round.index + 1)")
                        }
                    }
                    .font(M.font(12.5, .semiBold))
                    .foregroundStyle(M.inkAlpha(0.45))
                    .frame(width: match.hasRoundLabels ? 168 : M.roundColumnWidth)
                    .frame(minHeight: 44)
                        .overlay(alignment: .trailing) { Rectangle().fill(M.hairline).frame(width: 1) }

                    ForEach(seats) { player in
                        Text(round.value(for: player.id).map { "\($0)" } ?? "·")
                            .font(M.font(16, .semiBold))
                            .foregroundStyle(M.ink)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .overlay(alignment: .trailing) { Rectangle().fill(M.hairline).frame(width: 1) }
                    }
                }
                Hairline()
            }
        }
    }

    private func scorecardSummary(_ match: Match) -> some View {
        let spec = match.scorecard ?? .empty
        return VStack(spacing: 0) {
            ForEach(match.standings) { standing in
                let card = match.card(for: standing.player)
                HStack(spacing: 14) {
                    Text("\(standing.rank)")
                        .font(M.font(13, .extraBold))
                        .foregroundStyle(M.inkAlpha(0.4))
                        .frame(width: 18)
                    PlayerMark(player: standing.player, size: 28)
                    Text(standing.player.name)
                        .font(M.font(15, .semiBold))
                        .foregroundStyle(M.ink)
                    Spacer(minLength: 8)
                    Text(cardBreakdown(card, spec: spec))
                        .font(M.font(12, .regular))
                        .foregroundStyle(M.inkAlpha(0.55))
                    Text("\(standing.total)")
                        .font(M.font(19, .extraBold))
                        .foregroundStyle(M.ink)
                        .frame(width: 54, alignment: .trailing)
                }
                .padding(.horizontal, 28)
                .frame(minHeight: 52)
                Hairline()
            }
        }
    }

    private func cardBreakdown(_ card: ScoreCard?, spec: ScorecardSpec) -> String {
        guard let card else { return "geen kaart" }
        var parts = ["categorieën \(card.columnPoints(spec: spec))"]
        if !spec.bonuses.isEmpty { parts.append("bonussen \(card.bonusPoints(spec: spec))") }
        if spec.hasPenalty { parts.append("aftrek \(card.penaltyPoints(spec: spec))") }
        return parts.joined(separator: " · ")
    }
}
