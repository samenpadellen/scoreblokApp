import SwiftUI
import SwiftData

/// Kop-tot-kop en records. Op de iPad staan die naast de rest; op een
/// telefoon is er geen ruimte, dus krijgen ze een eigen scherm.
struct StatsDetailScreen: View {
    @Environment(Router.self) private var router
    @Environment(\.isCompact) private var isCompact
    @Query private var allMatches: [Match]
    @Query(sort: \Player.createdAt) private var players: [Player]

    @AppStorage(SettingsKey.statsPeriod) private var statsPeriod = StatsPeriod.days90.rawValue

    private var period: StatsPeriod {
        StatsPeriod(rawValue: statsPeriod) ?? .days90
    }
    private var scoped: [Match] { StatsEngine.matches(allMatches, in: period) }
    private var me: Player? { players.first(where: \.isMe) ?? players.first }
    private var padding: CGFloat { isCompact ? 20 : 28 }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                HeavyRule()
                headToHead
                HeavyRule()
                records
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            BackLink(title: "Statistieken") { router.screen = .stats }
            Text("Kop-tot-kop")
                .font(M.font(isCompact ? 32 : 34, .extraBold))
                .tracking(em: -0.025, size: isCompact ? 32 : 34)
                .foregroundStyle(M.ink)
            Text(period.rawValue)
                .font(M.font(11.5, .regular))
                .foregroundStyle(M.inkAlpha(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 8, leading: padding, bottom: 16, trailing: padding))
    }

    @ViewBuilder
    private var headToHead: some View {
        if let me, let opponent = StatsEngine.mostFrequentOpponent(of: me, in: scoped) {
            let lines = StatsEngine.headToHead(me, versus: opponent, in: scoped)
            let wins = lines.reduce(0) { $0 + $1.wins }
            let losses = lines.reduce(0) { $0 + $1.losses }
            let total = max(wins + losses, 1)

            VStack(alignment: .leading, spacing: 0) {
                Text("\(me.name) tegen \(opponent.name) · \(wins + losses) potjes samen")
                    .font(M.font(12, .regular))
                    .foregroundStyle(M.inkAlpha(0.55))
                    .padding(.bottom, 16)

                HStack(spacing: 14) {
                    Text("\(wins)")
                        .font(M.font(40, .extraBold))
                        .tracking(em: -0.03, size: 40)
                        .foregroundStyle(M.ink)
                    GeometryReader { proxy in
                        HStack(spacing: 0) {
                            Rectangle().fill(M.red)
                                .frame(width: proxy.size.width * Double(wins) / Double(total))
                            Rectangle().fill(Color(hex: 0x2D2B2B))
                                .frame(width: proxy.size.width * Double(losses) / Double(total))
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(height: 12)
                    .background(M.hairline)
                    Text("\(losses)")
                        .font(M.font(40, .extraBold))
                        .tracking(em: -0.03, size: 40)
                        .foregroundStyle(M.ink)
                }
                .padding(.bottom, 18)

                ForEach(lines) { line in
                    HStack(spacing: 12) {
                        Text(line.gameName)
                            .font(M.font(13.5, .semiBold))
                            .foregroundStyle(M.inkAlpha(0.75))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(line.score)
                            .font(M.font(14, .extraBold))
                            .foregroundStyle(M.ink)
                        Text("gem. \(Int(line.averageDifference.rounded()).signedText)")
                            .font(M.font(11.5, .regular))
                            .foregroundStyle(M.inkAlpha(0.5))
                            .frame(width: 92, alignment: .trailing)
                    }
                    .frame(minHeight: 44)
                    .overlay(alignment: .top) { Hairline() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 18, leading: padding, bottom: 20, trailing: padding))
        } else {
            Text("Nog geen medespeler om tegen af te zetten.")
                .font(M.font(12.5, .regular))
                .foregroundStyle(M.inkAlpha(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(padding)
        }
    }

    private var records: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Records")
                .font(M.font(18, .extraBold))
                .foregroundStyle(M.ink)
                .padding(.bottom, 14)

            let lines = StatsEngine.records(in: scoped)
            if lines.isEmpty {
                Text("Nog geen records.")
                    .font(M.font(12.5, .regular))
                    .foregroundStyle(M.inkAlpha(0.5))
            }
            ForEach(lines) { record in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(record.label)
                        .font(M.font(13, .regular))
                        .foregroundStyle(M.inkAlpha(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text(record.value)
                        .font(M.font(15, .extraBold))
                        .foregroundStyle(M.ink)
                    Text(record.who)
                        .font(M.font(11, .semiBold))
                        .foregroundStyle(M.inkAlpha(0.5))
                        .frame(width: 70, alignment: .trailing)
                }
                .frame(minHeight: 44)
                .overlay(alignment: .bottom) { Hairline() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 18, leading: padding, bottom: 24, trailing: padding))
    }
}
