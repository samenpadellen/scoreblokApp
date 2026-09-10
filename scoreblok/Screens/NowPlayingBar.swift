import SwiftUI
import TipKit

/// Balk onderin zolang er een potje loopt en je ergens anders in de app kijkt.
/// Zelfde behandeling als de "potje open"-kaart op Spelen, zodat het één ding
/// blijft: inkt, rood voor de actie, harde randen.
struct NowPlayingBar: View {
    let match: Match
    let onResume: () -> Void

    @Environment(\.isCompact) private var isCompact
    @Environment(\.isNarrow) private var isNarrow

    var body: some View {
        content
            .popoverTip(ResumeTip())
    }

    private var content: some View {
        Button(action: onResume) {
            Group {
                if isCompact { compactLayout } else { wideLayout }
            }
            .background(M.ink)
            .overlay(alignment: .top) { HeavyRule() }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Potje open: \(match.gameName), \(status)")
        .accessibilityHint("Ga verder met tellen")
    }

    /// Op een telefoon past de rij met standen er niet naast. Eerder werd
    /// alles in 402 pt geperst: "Ga verder" brak per lettergreep af en de
    /// naam van het spel viel weg. Hier alleen wat je nodig hebt om te
    /// herkennen welk potje het is.
    private var compactLayout: some View {
        HStack(spacing: 12) {
            GameMark(mono: match.mono, name: match.gameName, background: M.red, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(match.gameName)
                    .font(M.font(14.5, .extraBold))
                    .foregroundStyle(M.paper)
                    .lineLimit(1)
                Text(status)
                    .font(M.font(11.5, .regular))
                    .foregroundStyle(M.paper.opacity(0.65))
                    .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            Text("Verder →")
                .font(M.font(12.5, .extraBold))
                .foregroundStyle(M.paper)
                .fixedSize()
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(M.red)
        }
        .padding(.horizontal, 14)
        .frame(height: 60)
    }

    private var wideLayout: some View {
        HStack(spacing: 0) {
            HStack(spacing: 14) {
                GameMark(mono: match.mono, name: match.gameName, background: M.red, size: 34)

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
            .layoutPriority(1)

            Spacer(minLength: 12)

            // Staand op een iPad is er geen ruimte voor de standen naast de
            // naam; dan liever de naam heel dan de standen erbij.
            if !isNarrow {
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
            }

            Text("Ga verder →")
                .font(M.font(13, .extraBold))
                .foregroundStyle(M.paper)
                .fixedSize()
                .padding(.horizontal, 20)
                .frame(maxHeight: .infinity)
                .background(M.red)
        }
        .frame(height: 66)
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
