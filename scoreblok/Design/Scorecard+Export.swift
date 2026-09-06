import SwiftUI

/// Het scoreblaadje zoals je het zou uitprinten: dezelfde tekening als het
/// bord, maar zonder toetsenblok en zonder navigatie. Wordt met ImageRenderer
/// tot een pdf gemaakt zodat je het kunt delen of bewaren.
struct PrintableScorecard: View {
    let match: Match

    private var seats: [Player] { match.orderedPlayers }
    private var standings: [Standing] { match.standings }
    private let column: CGFloat = 104
    private let roundColumn: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(match.gameName)
                    .font(M.font(28, .extraBold))
                    .tracking(em: -0.02, size: 28)
                Text(subtitle)
                    .font(M.font(12, .regular))
                    .foregroundStyle(M.inkAlpha(0.6))
                Spacer()
                Wordmark(size: 14, markSize: 22)
            }
            .padding(.bottom, 16)
            HeavyRule()

            header
            HeavyRule()
            ForEach(rounds, id: \.index) { round in
                row(round)
                Hairline()
            }
            totals

            Text("Gemaakt met Scoreblok")
                .font(M.font(10, .semiBold))
                .tracking(em: 0.12, size: 10)
                .foregroundStyle(M.inkAlpha(0.4))
                .padding(.top, 18)
        }
        .padding(28)
        .frame(width: roundColumn + column * CGFloat(max(seats.count, 1)) + 56,
               alignment: .leading)
        .background(M.paper)
    }

    private var rounds: [MatchRound] {
        match.orderedRounds.filter { !$0.entries.isEmpty }
    }

    private var subtitle: String {
        var parts = [(match.endedAt ?? match.startedAt)
            .formatted(.dateTime.day().month(.wide).year())]
        parts.append("\(match.players.count) spelers")
        parts.append("\(match.winsByLowest ? "minste" : "meeste") \(match.unitLabel) wint")
        return parts.joined(separator: " · ")
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text(match.hasRoundLabels ? "RONDE · OPDRACHT" : "RONDE")
                .font(M.font(9.5, .semiBold))
                .tracking(em: 0.12, size: 9.5)
                .foregroundStyle(M.inkAlpha(0.45))
                .frame(width: roundColumn, alignment: .leading)
            ForEach(seats) { player in
                HStack(spacing: 8) {
                    PlayerMark(player: player, size: 22)
                    Text(player.name)
                        .font(M.font(12.5, .semiBold))
                        .lineLimit(1)
                }
                .frame(width: column, alignment: .leading)
            }
        }
        .padding(.vertical, 10)
    }

    private func row(_ round: MatchRound) -> some View {
        HStack(spacing: 0) {
            Group {
                if let label = match.roundLabel(at: round.index) {
                    Text("\(round.index + 1)  \(label)")
                } else {
                    Text("\(round.index + 1)")
                }
            }
            .font(M.font(12, .semiBold))
            .foregroundStyle(M.inkAlpha(0.5))
            .frame(width: roundColumn, alignment: .leading)

            ForEach(seats) { player in
                Text(round.value(for: player.id).map { "\($0)" } ?? "·")
                    .font(M.font(15, .semiBold))
                    .frame(width: column, alignment: .center)
            }
        }
        .frame(minHeight: 34)
    }

    private var totals: some View {
        HStack(spacing: 0) {
            Text("TOTAAL")
                .font(M.font(9.5, .semiBold))
                .tracking(em: 0.12, size: 9.5)
                .foregroundStyle(M.inkAlpha(0.45))
                .frame(width: roundColumn, alignment: .leading)
            ForEach(seats) { player in
                let standing = standings.first { $0.player.id == player.id }
                VStack(spacing: 2) {
                    Text("\(match.total(for: player))")
                        .font(M.font(22, .extraBold))
                        .tracking(em: -0.02, size: 22)
                    Text("\(standing?.rank ?? 0)e")
                        .font(M.font(10, .regular))
                        .foregroundStyle(M.inkAlpha(0.5))
                }
                .frame(width: column)
            }
        }
        .frame(minHeight: 52)
        .overlay(alignment: .top) { HeavyRule() }
    }
}

enum ScorecardExport {

    /// Rendert het blaadje als pdf en geeft het bestand terug.
    @MainActor
    static func pdf(for match: Match) -> URL? {
        let renderer = ImageRenderer(content: PrintableScorecard(match: match))
        renderer.proposedSize = .unspecified

        let name = match.gameName.replacingOccurrences(of: " ", with: "-")
        let date = (match.endedAt ?? match.startedAt).formatted(.iso8601.year().month().day())
        let url = URL.temporaryDirectory.appending(path: "Scoreblok-\(name)-\(date).pdf")

        var page = CGRect(x: 0, y: 0, width: 612, height: 792)
        var success = false
        renderer.render { size, draw in
            page.size = CGSize(width: size.width, height: size.height)
            guard let consumer = CGDataConsumer(url: url as CFURL),
                  let context = CGContext(consumer: consumer, mediaBox: &page, nil)
            else { return }
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
            context.closePDF()
            success = true
        }
        return success ? url : nil
    }
}
