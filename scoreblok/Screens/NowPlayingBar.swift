import SwiftUI
import TipKit

/// Balk onderin zolang er een potje loopt en je ergens anders in de app kijkt.
/// Zelfde behandeling als de "potje open"-kaart op Spelen, zodat het één ding
/// blijft: inkt, rood voor de actie, harde randen.
struct NowPlayingBar: View {
    let match: Match
    let onResume: () -> Void

    var body: some View {
        content
            .popoverTip(ResumeTip())
    }

    private var content: some View {
        Button(action: onResume) {
            HStack(spacing: 0) {
                HStack(spacing: 14) {
                    GameMark(mono: match.mono, background: M.red, size: 34)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("POTJE OPEN")
                            .font(M.font(9.5, .semiBold))
                            .tracking(em: 0.14, size: 9.5)
                            .foregroundStyle(Color(hex: 0xFF9783))
                        Text(match.gameName)
                            .font(M.font(15, .extraBold))
                            .foregroundStyle(M.paper)
                            .lineLimit(1)
                    }

                    Text(status)
                        .font(M.font(12, .regular))
                        .foregroundStyle(M.paper.opacity(0.6))
                        .lineLimit(1)
                }
                .padding(.horizontal, 24)
                .layoutPriority(0)

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    ForEach(match.standings.prefix(5)) { standing in
                        HStack(spacing: 7) {
                            PlayerMark(player: standing.player, size: 18)
                            Text("\(standing.total)")
                                .font(M.font(12, .semiBold))
                                .foregroundStyle(M.paper)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .overlay(Rectangle().stroke(M.paper.opacity(0.25), lineWidth: 1))
                    }
                }
                .padding(.trailing, 20)
                .layoutPriority(1)

                Text("Ga verder →")
                    .font(M.font(13, .extraBold))
                    .foregroundStyle(M.paper)
                    .padding(.horizontal, 20)
                    .frame(maxHeight: .infinity)
                    .background(M.red)
                    .layoutPriority(1)
            }
            .frame(height: 66)
            .background(M.ink)
            .overlay(alignment: .top) { HeavyRule() }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Waar het potje staat: bij Jokeren de opdracht, anders het rondenummer.
    private var status: String {
        switch match.mode {
        case .scorecard:
            return "scorekaart"
        case .winnerOnly:
            return "eindvolgorde"
        case .finalScore:
            return "eindscore"
        default:
            let index = match.currentRoundIndex
            if let label = match.roundLabel(at: index) {
                return "ronde \(index + 1) · \(label.lowercased())"
            }
            if match.roundCount > 0 {
                return "ronde \(index + 1) van \(match.roundCount)"
            }
            return "ronde \(index + 1)"
        }
    }
}
