import Charts
import SwiftUI

/// Het verloop van een potje: het lopende totaal van elke speler na elke
/// ronde. De winnaar in rood en dikker. Onder de grafiek een legenda met
/// markering, naam en eindstand, zodat kleur nooit het enige signaal is en
/// namen elkaar niet overlappen als de lijnen dicht bij elkaar eindigen.
struct MatchProgressChart: View {
    let match: Match

    private var played: Int {
        match.orderedRounds.filter { !$0.entries.isEmpty }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            chart
                .frame(maxHeight: .infinity)
                .revealFromLeading(delay: 0.25)
            legend
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Verloop van het potje per ronde")
    }

    private func color(for standing: Standing, leaderID: UUID?) -> Color {
        standing.player.id == leaderID ? M.red : standing.player.color
    }

    private var chart: some View {
        let standings = match.standings
        let played = played
        let leaderID = standings.first?.player.id

        return Chart {
            ForEach(standings) { standing in
                let series = Array(match.cumulative(for: standing.player).prefix(played + 1))
                let isLeader = standing.player.id == leaderID
                let color = color(for: standing, leaderID: leaderID)

                ForEach(Array(series.enumerated()), id: \.offset) { index, total in
                    LineMark(x: .value("Ronde", index),
                             y: .value("Totaal", total),
                             series: .value("Speler", standing.player.id.uuidString))
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: isLeader ? 3 : 2, lineCap: .square, lineJoin: .miter))
                }

                if let last = series.last {
                    PointMark(x: .value("Ronde", series.count - 1), y: .value("Totaal", last))
                        .symbol(.square)
                        .symbolSize(isLeader ? 64 : 36)
                        .foregroundStyle(color)
                }
            }

            if match.mode == .elimination {
                RuleMark(y: .value("Grens", match.eliminationLimit))
                    .foregroundStyle(M.inkAlpha(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .chartXScale(domain: 0...max(played, 1))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: min(max(played, 1), 9))) { _ in
                AxisGridLine().foregroundStyle(M.hairline)
                AxisValueLabel().font(M.font(10, .semiBold)).foregroundStyle(M.inkAlpha(0.5))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(M.hairline)
                AxisValueLabel().font(M.font(10, .semiBold)).foregroundStyle(M.inkAlpha(0.5))
            }
        }
        .chartLegend(.hidden)
    }

    private var legend: some View {
        let standings = match.standings
        let leaderID = standings.first?.player.id
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 14, alignment: .leading)],
                         alignment: .leading, spacing: 8) {
            ForEach(standings) { standing in
                let isLeader = standing.player.id == leaderID
                HStack(spacing: 7) {
                    Rectangle()
                        .fill(color(for: standing, leaderID: leaderID))
                        .frame(width: 14, height: isLeader ? 3 : 2)
                    PlayerMark(player: standing.player, size: 16)
                    Text(standing.player.name)
                        .font(M.font(11.5, isLeader ? .extraBold : .semiBold))
                        .foregroundStyle(isLeader ? M.red : M.ink)
                        .lineLimit(1)
                    Text("\(standing.total)")
                        .font(M.font(11.5, .extraBold))
                        .foregroundStyle(M.inkAlpha(0.6))
                }
            }
        }
    }
}
