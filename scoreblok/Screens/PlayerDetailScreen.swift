import SwiftUI
import SwiftData

struct PlayerDetailScreen: View {
    @Bindable var player: Player

    @Environment(Router.self) private var router
    @Query private var players: [Player]
    @Query private var matches: [Match]

    private var counted: [Match] { matches.filter(\.counts) }
    private var results: [MatchResult] { StatsEngine.results(for: player, in: counted) }
    private var me: Player? { players.first(where: \.isMe) }

    /// Tegen wie de balans loopt: normaal tegen jou, en als dit jouw eigen
    /// profiel is tegen je vaakste medespeler.
    private var counterpart: Player? {
        if let me, me.id != player.id { return me }
        return StatsEngine.mostFrequentOpponent(of: player, in: counted)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                bar
                Hairline()
                header
                HeavyRule()
                tiles
                HeavyRule()
                lower
            }
        }
    }

    private var bar: some View {
        HStack(spacing: 16) {
            BackLink(title: "Spelers") { router.screen = .players }
            Spacer()
            OutlineButton(title: player.isArchived ? "Terughalen" : "Archiveren") {
                player.isArchived.toggle()
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
    }

    private var header: some View {
        HStack(spacing: 18) {
            Monogram(player: player, size: 64)
            VStack(alignment: .leading, spacing: 8) {
                Text(player.name)
                    .font(M.font(34, .extraBold))
                    .tracking(em: -0.02, size: 34)
                    .foregroundStyle(M.ink)
                Text(since)
                    .font(M.font(13, .regular))
                    .foregroundStyle(M.inkAlpha(0.6))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
    }

    private var since: String {
        var parts: [String] = []
        parts.append("Speelt mee sinds \(player.createdAt.formatted(.dateTime.month(.wide).year()))")
        parts.append(results.count == 1 ? "1 potje" : "\(results.count) potjes")
        if let last = results.last {
            parts.append("laatst gespeeld \(last.date.formatted(.dateTime.day().month(.abbreviated)))")
        }
        return parts.joined(separator: " · ")
    }

    private var tiles: some View {
        let wins = results.filter(\.isWin).count
        let rate = results.isEmpty ? 0 : Double(wins) / Double(results.count)
        let averageRank = results.isEmpty ? 0
            : Double(results.map(\.rank).reduce(0, +)) / Double(results.count)
        let longest = StatsEngine.longestWinStreak(for: player, in: counted)
        let streak = StatsEngine.streak(for: player, in: counted)

        let items: [(String, String, String)] = [
            ("Potjes", "\(results.count)", results.isEmpty ? "nog niets gespeeld"
                : "sinds \(player.createdAt.formatted(.dateTime.month(.abbreviated).year()))"),
            ("Winstpercentage", results.isEmpty ? "—" : rate.percentText, "\(wins) gewonnen"),
            ("Gem. eindpositie", results.isEmpty ? "—" : averageRank.dutch(1), "over alle spellen"),
            ("Langste winreeks", "\(longest)", "nu: \(streak.long)")
        ]

        return HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                FigureTile(label: item.0, value: item.1, sub: item.2, valueSize: 32, minHeight: 118)
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(M.hairline).frame(width: 1)
                    }
            }
        }
    }

    private var lower: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                SectionLabel(balanceTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(EdgeInsets(top: 18, leading: 24, bottom: 10, trailing: 24))
                Hairline()

                if let counterpart {
                    let lines = StatsEngine.headToHead(player, versus: counterpart, in: counted)
                    if lines.isEmpty {
                        note("Nog geen gedeelde potjes.")
                    }
                    ForEach(lines) { line in
                        HStack(spacing: 14) {
                            Text(line.gameName)
                                .font(M.font(14, .semiBold))
                                .foregroundStyle(M.ink)
                            Spacer(minLength: 8)
                            BarMeter(fraction: line.fraction).frame(width: 120)
                            Text(line.score)
                                .font(M.font(14, .extraBold))
                                .foregroundStyle(M.ink)
                                .frame(width: 52, alignment: .trailing)
                        }
                        .padding(.horizontal, 24)
                        .frame(minHeight: 52)
                        Hairline()
                    }
                } else {
                    note("Nog geen medespelers om tegen af te zetten.")
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .trailing) { Rectangle().fill(M.hairline).frame(width: 1) }

            VStack(spacing: 0) {
                SectionLabel("Laatste potjes")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(EdgeInsets(top: 18, leading: 24, bottom: 10, trailing: 24))
                Hairline()

                if results.isEmpty { note("Nog geen potjes gespeeld.") }

                ForEach(results.reversed().prefix(8)) { result in
                    HStack(spacing: 14) {
                        Text(result.date.formatted(.dateTime.day().month(.abbreviated)))
                            .font(M.font(11, .semiBold))
                            .foregroundStyle(M.inkAlpha(0.45))
                            .frame(width: 58, alignment: .leading)
                        Text(result.gameName)
                            .font(M.font(14, .semiBold))
                            .foregroundStyle(M.ink)
                        Spacer(minLength: 8)
                        Text("\(result.total) punten")
                            .font(M.font(12, .regular))
                            .foregroundStyle(M.inkAlpha(0.55))
                        Tag(text: result.isWin ? "Winst" : "\(result.rank)e",
                            background: result.isWin ? M.red : M.paperKey,
                            foreground: result.isWin ? M.paper : M.ink)
                    }
                    .padding(.horizontal, 24)
                    .frame(minHeight: 52)
                    Hairline()
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var balanceTitle: String {
        guard let counterpart else { return "Onderlinge balans" }
        if let me, me.id != player.id, counterpart.id == me.id {
            return "Onderlinge balans tegen jou"
        }
        return "Onderlinge balans tegen \(counterpart.name)"
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(M.font(12.5, .regular))
            .foregroundStyle(M.inkAlpha(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
    }
}
