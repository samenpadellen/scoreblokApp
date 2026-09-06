import SwiftUI
import SwiftData

struct PlayScreen: View {
    @Environment(Router.self) private var router
    @Query(sort: \GameTemplate.sortIndex) private var templates: [GameTemplate]
    @Query(sort: \Match.startedAt, order: .reverse) private var matches: [Match]
    @Query private var players: [Player]

    private var activePlayers: [Player] { players.filter { !$0.isArchived } }
    /// Alle potjes die nog lopen, laatst gespeeld bovenaan. Ze blijven staan
    /// tot je ze afrondt, ook als dat dagen later is.
    private var openMatches: [Match] {
        matches.filter(\.isOpen).sorted { $0.lastPlayedAt > $1.lastPlayedAt }
    }

    /// De vier sjablonen die het laatst gespeeld zijn; aangevuld uit de lijst.
    private var recent: [GameTemplate] {
        var seen: [String] = []
        for match in matches where !seen.contains(match.gameName) {
            seen.append(match.gameName)
        }
        var ordered = seen.compactMap { name in templates.first { $0.name == name } }
        for template in templates where !ordered.contains(where: { $0.id == template.id }) {
            ordered.append(template)
        }
        return Array(ordered.prefix(4))
    }

    private var others: [GameTemplate] {
        let recentIDs = Set(recent.map(\.id))
        return templates.filter { !recentIDs.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                HeavyRule()

                if let first = openMatches.first {
                    resumeCard(first)
                    ForEach(openMatches.dropFirst()) { match in
                        Hairline()
                        openRow(match)
                    }
                    HeavyRule()
                }

                SectionLabel("Laatst gespeeld")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(EdgeInsets(top: 22, leading: 28, bottom: 8, trailing: 28))
                Hairline()
                GridRows(items: recent, columns: 4) { template in
                    recentCard(template)
                }

                SectionLabel("Alle spellen")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(EdgeInsets(top: 22, leading: 28, bottom: 8, trailing: 28))
                Hairline()
                GridRows(items: others, columns: 3, trailing: { newGameRow }) { template in
                    compactRow(template)
                }

                if players.isEmpty {
                    emptyHint
                }
            }
        }
    }

    // MARK: - Kop

    private var header: some View {
        HStack(alignment: .bottom) {
            ScreenTitle("Spelen")
            Spacer()
            Text("\(templates.count) SPELLEN · \(activePlayers.count) SPELERS")
                .font(M.font(11, .semiBold))
                .tracking(em: 0.1, size: 11)
                .foregroundStyle(M.inkAlpha(0.55))
        }
        .padding(EdgeInsets(top: 24, leading: 28, bottom: 18, trailing: 28))
    }

    // MARK: - Doorgaan met een open potje

    private func resumeCard(_ match: Match) -> some View {
        Button {
            router.screen = match.mode == .scorecard ? .card(match) : .board(match)
        } label: {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("POTJE OPEN — GA VERDER")
                        .font(M.font(10, .semiBold))
                        .tracking(em: 0.14, size: 10)
                        .foregroundStyle(Color(hex: 0xFF9783))
                        .padding(.bottom, 10)
                    Text(match.gameName)
                        .font(M.font(26, .extraBold))
                        .tracking(em: -0.02, size: 26)
                        .foregroundStyle(M.paper)
                        .lineLimit(1)
                    Text(resumeSubtitle(match))
                        .font(M.font(13, .regular))
                        .foregroundStyle(M.paper.opacity(0.65))
                        .padding(.top, 6)
                }
                .padding(EdgeInsets(top: 20, leading: 28, bottom: 20, trailing: 28))
                .layoutPriority(0)

                Spacer(minLength: 12)

                HStack(spacing: 0) {
                    ForEach(match.standings) { standing in
                        VStack(alignment: .leading, spacing: 0) {
                            Spacer(minLength: 0)
                            Text(standing.player.name.uppercased())
                                .font(M.font(11, .semiBold))
                                .tracking(em: 0.08, size: 11)
                                .foregroundStyle(M.paper.opacity(0.6))
                                .lineLimit(1)
                                .padding(.bottom, 8)
                            Text("\(standing.total)")
                                .font(M.font(28, .extraBold))
                                .tracking(em: -0.02, size: 28)
                                .foregroundStyle(M.paper)
                        }
                        .frame(width: 104, alignment: .leading)
                        .padding(EdgeInsets(top: 20, leading: 16, bottom: 20, trailing: 16))
                        .overlay(alignment: .leading) {
                            Rectangle().fill(M.paper.opacity(0.22)).frame(width: 1)
                        }
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            }
            .background(M.ink)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func resumeSubtitle(_ match: Match) -> String {
        "\(position(match)) · laatst gespeeld \(match.lastPlayedText)"
    }

    /// Waar het potje staat: bij spellen met opdrachten die opdracht, anders
    /// het rondenummer.
    private func position(_ match: Match) -> String {
        switch match.mode {
        case .scorecard: "Scorekaart"
        case .winnerOnly: "Eindvolgorde vastleggen"
        case .finalScore: "Eindscore invullen"
        default:
            if let label = match.roundLabel(at: match.currentRoundIndex) {
                "Ronde \(match.currentRoundIndex + 1) · \(label.lowercased())"
            } else if match.roundCount > 0 {
                "Ronde \(match.currentRoundIndex + 1) van \(match.roundCount)"
            } else {
                "Ronde \(match.currentRoundIndex + 1)"
            }
        }
    }

    /// Compacte rij voor de overige open potjes.
    private func openRow(_ match: Match) -> some View {
        RowButton(minHeight: 62) {
            router.screen = match.mode == .scorecard ? .card(match) : .board(match)
        } content: {
            HStack(spacing: 14) {
                GameMark(mono: match.mono, size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(match.gameName)
                        .font(M.font(14.5, .extraBold))
                        .foregroundStyle(M.ink)
                        .lineLimit(1)
                    Text(resumeSubtitle(match))
                        .font(M.font(11.5, .regular))
                        .foregroundStyle(M.inkAlpha(0.5))
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    ForEach(match.standings.prefix(5)) { standing in
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
                Text("→")
                    .font(M.font(15, .regular))
                    .foregroundStyle(M.inkAlpha(0.35))
            }
            .padding(.horizontal, 28)
        }
    }

    // MARK: - Spelkaarten

    private func recentCard(_ template: GameTemplate) -> some View {
        RowButton(minHeight: 146) {
            start(template)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                GameMark(mono: template.mono,
                         background: template.id == recent.first?.id ? M.red : M.ink,
                         size: 44)
                    .padding(.bottom, 14)
                Spacer(minLength: 0)
                Text(template.name)
                    .font(M.font(19, .extraBold))
                    .tracking(em: -0.01, size: 19)
                    .foregroundStyle(M.ink)
                    .padding(.bottom, 6)
                Text(template.subtitle)
                    .font(M.font(12, .regular))
                    .foregroundStyle(M.inkAlpha(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 18, leading: 18, bottom: 20, trailing: 18))
        }
    }

    private func compactRow(_ template: GameTemplate) -> some View {
        RowButton(minHeight: 66) {
            start(template)
        } content: {
            HStack(spacing: 14) {
                GameMark(mono: template.mono, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(template.name)
                        .font(M.font(14.5, .semiBold))
                        .foregroundStyle(M.ink)
                        .lineLimit(1)
                    Text(template.subtitle)
                        .font(M.font(11.5, .regular))
                        .foregroundStyle(M.inkAlpha(0.5))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
        }
    }

    private var newGameRow: some View {
        RowButton(minHeight: 66) {
            router.screen = .custom(nil)
        } content: {
            HStack(spacing: 14) {
                Text("+")
                    .font(M.font(18, .extraBold))
                    .foregroundStyle(M.red)
                    .frame(width: 34, height: 34)
                    .overlay(Rectangle().stroke(M.red, lineWidth: 2))
                Text("Eigen spel maken")
                    .font(M.font(14.5, .extraBold))
                    .foregroundStyle(M.red)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
        }
    }

    private var emptyHint: some View {
        Text("Nog geen spelers. Kies een spel — je voegt de spelers toe bij het opzetten van het potje.")
            .font(M.font(12.5, .regular))
            .foregroundStyle(M.inkAlpha(0.55))
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 20, leading: 28, bottom: 28, trailing: 28))
    }

    private func start(_ template: GameTemplate) {
        router.screen = .setup(template)
    }
}

// MARK: - Raster met harde scheidslijnen

/// Legt items in rijen van `columns` neer met haarlijnen ertussen, zodat het
/// raster ook bij een onvolledige laatste rij dichtloopt.
struct GridRows<Item: Identifiable, Cell: View, Trailing: View>: View {
    let items: [Item]
    let columns: Int
    var trailing: () -> Trailing
    @ViewBuilder let cell: (Item) -> Cell

    init(items: [Item], columns: Int,
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
         @ViewBuilder cell: @escaping (Item) -> Cell) {
        self.items = items
        self.columns = columns
        self.trailing = trailing
        self.cell = cell
    }

    private var slots: Int {
        items.count + (Trailing.self == EmptyView.self ? 0 : 1)
    }

    private var rowCount: Int {
        max(Int(ceil(Double(slots) / Double(columns))), 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rowCount, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        Group {
                            if index < items.count {
                                cell(items[index])
                            } else if index == items.count, Trailing.self != EmptyView.self {
                                trailing()
                            } else {
                                Color.clear
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .trailing) {
                            Rectangle().fill(M.hairline).frame(width: 1)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(M.hairline).frame(height: 1)
                }
            }
        }
    }
}
