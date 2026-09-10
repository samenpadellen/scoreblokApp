import SwiftUI
import SwiftData

/// Het bord op een telefoon. Op de iPad staan spelers in kolommen en rondes
/// in rijen; dat past niet op 393 pt. Hier krijgt elke speler een rij en vul
/// je één ronde tegelijk in. De volle tabel staat eronder en schuift
/// horizontaal, maar is niet meer het invoermiddel.
struct CompactBoardScreen: View {
    @Bindable var match: Match

    @Binding var selectedRound: Int
    @Binding var selectedSeat: Int
    @Binding var entry: String
    @Binding var negative: Bool

    let canUndo: Bool
    let onUndo: () -> Void
    let onFinish: () -> Void
    let onBack: () -> Void
    let onKey: (String) -> Void
    let onSelect: (Int, Int) -> Void
    let onNextRound: () -> Void

    private var seats: [Player] { match.orderedPlayers }
    private var standings: [Standing] { match.standings }
    private var leaderID: UUID? { standings.first?.player.id }
    private var accent: GameAccent { GameAccent.of(match.gameName) }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            HeavyRule()
            Rectangle().fill(accent.base).frame(height: 3)
            roundHeader
            Hairline()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(seats.enumerated()), id: \.element.id) { seat, player in
                        playerRow(seat: seat, player: player)
                        Hairline()
                    }
                    earlierRounds
                }
            }
            keypadBar
        }
    }

    // MARK: - Balk

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Text("← Spelen")
                    .font(M.font(12.5, .semiBold))
                    .foregroundStyle(M.red)
                    .frame(minHeight: M.tap)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)

            Button(action: onUndo) {
                Text("↺ Undo")
                    .font(M.font(11.5, .extraBold))
                    .foregroundStyle(canUndo ? M.red : M.inkAlpha(0.35))
                    .padding(.horizontal, 11)
                    .frame(minHeight: 36)
                    .overlay(Rectangle().stroke(M.ruleHeavy, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(!canUndo)

            Button(action: onFinish) {
                Text("Afronden")
                    .font(M.font(11.5, .extraBold))
                    .foregroundStyle(M.paper)
                    .padding(.horizontal, 11)
                    .frame(minHeight: 36)
                    .background(M.ink)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var roundHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(roundTitle)
                .font(M.font(27, .extraBold))
                .tracking(em: -0.025, size: 27)
                .foregroundStyle(M.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            Text(roundSubtitle)
                .font(M.font(12, .regular))
                .foregroundStyle(M.inkAlpha(0.55))
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var roundTitle: String {
        if match.mode == .finalScore { return "Eindscore" }
        if let label = match.roundLabel(at: selectedRound) { return label }
        return "Ronde \(selectedRound + 1)"
    }

    private var roundSubtitle: String {
        var parts: [String] = []
        if match.hasRoundLabels {
            parts.append("ronde \(selectedRound + 1) van \(match.roundCount)")
        } else if match.roundCount > 0 {
            parts.append("van \(match.roundCount)")
        }
        parts.append("\(match.winsByLowest ? "minste" : "meeste") \(match.unitLabel) wint")
        return parts.joined(separator: " · ")
    }

    // MARK: - Eén rij per speler

    private func playerRow(seat: Int, player: Player) -> some View {
        let isSelected = seat == selectedSeat
        let value = match.value(round: selectedRound, player: player)
        let standing = standings.first { $0.player.id == player.id }

        return Button {
            onSelect(selectedRound, seat)
        } label: {
            HStack(spacing: 13) {
                PlayerMark(player: player, size: 34)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        Text(player.name)
                            .font(M.font(15.5, .semiBold))
                            .foregroundStyle(M.ink)
                            .lineLimit(1)
                        if player.id == leaderID,
                           match.rounds.contains(where: { !$0.entries.isEmpty }) {
                            Tag(text: "Leidt", background: accent.onPaper, size: 9)
                        }
                    }
                    Text(subtitle(for: player, standing: standing))
                        .font(M.font(11, .regular))
                        .foregroundStyle(M.inkAlpha(0.5))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 7) {
                    Text("DEZE RONDE")
                        .font(M.font(9.5, .semiBold))
                        .tracking(em: 0.1, size: 9.5)
                        .foregroundStyle(M.inkAlpha(0.45))
                    Text(cellText(value: value, isSelected: isSelected))
                        .font(isSelected ? M.font(20, .extraBold)
                              : (value == nil ? M.font(16, .regular) : M.font(19, .semiBold)))
                        .foregroundStyle(value == nil && !isSelected ? M.inkAlpha(0.28) : M.ink)
                        .contentTransition(.numericText())
                        .animation(M.Motion.quick, value: value)
                        .frame(minWidth: 44, alignment: .trailing)
                }

                Rectangle().fill(M.hairline).frame(width: 1, height: 44)

                VStack(alignment: .trailing, spacing: 5) {
                    Text("TOTAAL")
                        .font(M.font(9.5, .semiBold))
                        .tracking(em: 0.1, size: 9.5)
                        .foregroundStyle(M.inkAlpha(0.45))
                    Text("\(match.total(for: player))")
                        .font(M.font(24, .extraBold))
                        .tracking(em: -0.02, size: 24)
                        .foregroundStyle(M.ink)
                        .contentTransition(.numericText(value: Double(match.total(for: player))))
                        .animation(M.Motion.settle, value: match.total(for: player))
                }
                .frame(minWidth: 52, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 72)
            .background(isSelected ? M.redWash : .clear)
            .overlay { if isSelected { Rectangle().stroke(M.red, lineWidth: 2) } }
            .animation(M.Motion.quick, value: isSelected)
            .contentShape(.rect)
        }
        .buttonStyle(PressableStyle(scale: 0.99))
        .accessibilityLabel(accessibility(player: player, value: value))
    }

    private func subtitle(for player: Player, standing: Standing?) -> String {
        var parts: [String] = []
        if let rank = standing?.rank { parts.append("\(rank)e") }
        if match.tracksJokers {
            let jokers = match.totalJokers(for: player)
            if jokers > 0 { parts.append("\(jokers) jokers") }
        }
        if let standing, standing.roundsPlayed > 0, match.showsAverages {
            parts.append("gem. \(standing.average.dutch(1))")
        }
        return parts.joined(separator: " · ")
    }

    private func cellText(value: Int?, isSelected: Bool) -> String {
        guard isSelected else { return value.map { "\($0)" } ?? "·" }
        if entry.isEmpty { return value.map { "\($0)|" } ?? "|" }
        return (negative ? "−" : "") + entry + "|"
    }

    private func accessibility(player: Player, value: Int?) -> String {
        let where_ = match.roundLabel(at: selectedRound) ?? "ronde \(selectedRound + 1)"
        let total = "totaal \(match.total(for: player))"
        guard let value else { return "\(player.name), \(where_), nog niet ingevuld, \(total)" }
        return "\(player.name), \(where_), \(value) \(match.unitLabel), \(total)"
    }

    // MARK: - De volle tabel eronder

    @ViewBuilder
    private var earlierRounds: some View {
        let played = match.orderedRounds.filter { !$0.entries.isEmpty }
        if !played.isEmpty {
            SectionHeader("Eerdere rondes", insets: EdgeInsets(top: 14, leading: 20, bottom: 8, trailing: 20))

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        miniCell("R", width: 40, bold: false, dim: true)
                        ForEach(seats) { player in
                            miniCell(String(player.name.prefix(3)), width: 78, bold: true)
                        }
                    }
                    ForEach(played) { round in
                        Hairline()
                        HStack(spacing: 0) {
                            miniCell("\(round.index + 1)", width: 40, bold: false, dim: true)
                            ForEach(seats) { player in
                                miniCell(round.value(for: player.id).map { "\($0)" } ?? "·",
                                         width: 78, bold: false)
                            }
                        }
                    }
                }
            }
        }
    }

    private func miniCell(_ text: String, width: CGFloat,
                          bold: Bool, dim: Bool = false) -> some View {
        Text(text)
            .font(bold ? M.font(10, .extraBold) : M.font(dim ? 11.5 : 13, dim ? .regular : .semiBold))
            .foregroundStyle(dim ? M.inkAlpha(0.45) : M.ink)
            .frame(width: width)
            .padding(.vertical, 9)
            .overlay(alignment: .trailing) { Rectangle().fill(M.hairline).frame(width: 1) }
    }

    // MARK: - Keypad, vast in duimbereik

    private var keypadBar: some View {
        VStack(spacing: 0) {
            HeavyRule()
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(seats.indices.contains(selectedSeat) ? seats[selectedSeat].name : "—")
                        .font(M.font(14, .extraBold))
                        .foregroundStyle(M.ink)
                    Spacer(minLength: 8)
                    Text("tik het aantal \(match.unitLabel)")
                        .font(M.font(11, .regular))
                        .foregroundStyle(M.inkAlpha(0.55))
                        .lineLimit(1)
                }
                .padding(.bottom, 10)

                let rows: [[String]] = [["7", "8", "9", "⌫"], ["4", "5", "6", "±"], ["1", "2", "3", "0"]]
                VStack(spacing: 6) {
                    ForEach(rows, id: \.self) { row in
                        HStack(spacing: 6) {
                            ForEach(row, id: \.self) { key($0) }
                        }
                    }
                    key("Bevestigen", wide: true)
                }

                nextRoundButton.padding(.top, 8)
            }
            .padding(EdgeInsets(top: 12, leading: 16, bottom: 14, trailing: 16))
            .background(M.paperDeep)
        }
    }

    private func key(_ label: String, wide: Bool = false) -> some View {
        let isNumber = label.count == 1 && label.first!.isNumber
        let isConfirm = label == "Bevestigen"
        let isSign = label == "±"
        let signOn = isSign && negative
        let signDisabled = isSign && !match.allowNegative

        return Button { onKey(label) } label: {
            Text(label)
                .font(isConfirm ? M.font(14, .extraBold)
                      : isNumber ? M.font(21, .semiBold) : M.font(16, .semiBold))
                .foregroundStyle(isConfirm ? M.paper
                                 : signOn ? M.paper
                                 : signDisabled ? M.inkAlpha(0.3) : M.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(isConfirm ? M.red : signOn ? M.ink : isNumber ? M.surface : M.paperKey)
                .overlay(Rectangle().stroke(isConfirm ? M.red : M.inkAlpha(0.35), lineWidth: 1))
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .disabled(signDisabled)
        .accessibilityLabel(isConfirm ? "Bevestigen"
                            : label == "⌫" ? "Wissen"
                            : label == "±" ? "Plus of min" : label)
    }

    private var nextRoundButton: some View {
        let filled = match.isRoundFilled(selectedRound)
        let isLast = match.roundCount > 0 && selectedRound >= match.roundCount - 1
        let title = match.mode == .finalScore ? "Potje afronden"
            : (isLast && filled ? "Potje afronden" : "Ronde afronden")

        return Button(action: onNextRound) {
            Text(title)
                .font(M.font(14, .extraBold))
                .foregroundStyle(filled ? M.paper : M.ink)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .background(filled ? M.ink : Color.clear)
                .overlay(Rectangle().stroke(M.ink, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(!filled)
        .opacity(filled ? 1 : 0.55)
    }
}
