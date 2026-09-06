import SwiftUI
import SwiftData

struct BoardScreen: View {
    @Bindable var match: Match

    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context

    /// Geselecteerde cel: ronde-index en zitplaats.
    @State private var selectedRound = 0
    @State private var selectedSeat = 0
    @State private var entry = ""
    @State private var negative = false
    @State private var undoStack: [[Int: [UUID: Int]]] = []
    @State private var confirmFinish = false

    private var seats: [Player] { match.orderedPlayers }
    private var standings: [Standing] { match.standings }
    private var leaderID: UUID? { standings.first?.player.id }
    private var rowCount: Int { match.displayedRoundCount }
    /// De rondekolom is smal bij losse nummers en breed als er een opdracht
    /// per ronde bij staat.
    private var roundColumnWidth: CGFloat {
        match.hasRoundLabels ? 168 : M.roundColumnWidth
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            HeavyRule()

            if match.mode == .winnerOnly {
                FinishOrderBoard(match: match)
            } else {
                ScrollView { table }
                    .frame(maxHeight: .infinity)
                keypadBar
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .overlay { if confirmFinish { finishPanel } }
        .onAppear {
            selectedRound = match.currentRoundIndex
            selectedSeat = firstEmptySeat(in: selectedRound)
        }
    }

    // MARK: - Balk

    private var toolbar: some View {
        ScreenBar(backTitle: "Spelen",
                  onBack: { router.screen = .play },
                  title: match.gameName,
                  subtitle: subtitle) {
            OutlineButton(title: "↺ Undo",
                          tint: undoStack.isEmpty ? M.inkAlpha(0.35) : M.red) { undo() }
                .disabled(undoStack.isEmpty)
            SolidButton(title: "Potje afronden", fill: M.ink, fontSize: 12.5) {
                confirmFinish = true
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if match.mode == .finalScore {
            parts.append("één eindscore")
        } else if match.roundCount > 0 {
            parts.append("ronde \(selectedRound + 1) van \(match.roundCount)")
        } else {
            parts.append("ronde \(selectedRound + 1) · open einde")
        }
        if match.mode == .elimination {
            parts.append("eruit bij \(match.eliminationLimit)")
        } else {
            parts.append("\(match.winsByLowest ? "laagste" : "hoogste") wint")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Tabel

    private var table: some View {
        VStack(spacing: 0) {
            headerRow
            HeavyRule()
            ForEach(0..<rowCount, id: \.self) { index in
                scoreRow(index)
                Hairline()
            }
            averagesRow
            Hairline()
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text(match.hasRoundLabels ? "RONDE · OPDRACHT" : "RONDE")
                .font(M.font(10, .semiBold))
                .tracking(em: 0.12, size: 10)
                .foregroundStyle(M.inkAlpha(0.45))
                .padding(.horizontal, match.hasRoundLabels ? 14 : 0)
                .frame(width: roundColumnWidth,
                       alignment: match.hasRoundLabels ? .leading : .center)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.vertical, 10)
                .overlay(alignment: .trailing) { columnRule }

            ForEach(seats) { player in
                let standing = standings.first { $0.player.id == player.id }
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        Monogram(player: player, size: 30)
                        Text(player.name)
                            .font(M.font(14, .semiBold))
                            .foregroundStyle(M.ink)
                            .lineLimit(1)
                        if standing?.isEliminated == true {
                            Tag(text: "Eruit", background: M.inkAlpha(0.15), foreground: M.ink, size: 9)
                        } else if player.id == leaderID, match.rounds.contains(where: { !$0.entries.isEmpty }) {
                            Tag(text: "Leidt", background: M.red, size: 9)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, 8)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(match.total(for: player))")
                            .font(M.font(30, .extraBold))
                            .tracking(em: -0.03, size: 30)
                            .foregroundStyle(M.ink)
                        Text("\(standing?.rank ?? 0)e")
                            .font(M.font(11, .regular))
                            .foregroundStyle(M.inkAlpha(0.5))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 10, leading: 14, bottom: 8, trailing: 14))
                .background(player.id == leaderID ? M.paperDeep : .clear)
                .overlay(alignment: .trailing) { columnRule }
            }
        }
    }

    private func scoreRow(_ index: Int) -> some View {
        let isCurrent = index == match.currentRoundIndex
        return HStack(spacing: 0) {
            roundLabelCell(index, isCurrent: isCurrent)
                .frame(width: roundColumnWidth)
                .frame(minHeight: 46)
                .overlay(alignment: .trailing) { columnRule }

            ForEach(Array(seats.enumerated()), id: \.element.id) { seat, player in
                cell(round: index, seat: seat, player: player)
            }
        }
        .background(isCurrent ? M.redTint : .clear)
    }

    @ViewBuilder
    private func roundLabelCell(_ index: Int, isCurrent: Bool) -> some View {
        let dimmed = index <= match.currentRoundIndex ? M.inkAlpha(0.6) : M.inkAlpha(0.3)

        if let label = match.roundLabel(at: index) {
            HStack(spacing: 10) {
                Text("\(index + 1)")
                    .font(M.font(13, .regular))
                    .foregroundStyle(index <= match.currentRoundIndex
                                     ? M.inkAlpha(0.4) : M.inkAlpha(0.25))
                    .frame(width: 12, alignment: .trailing)
                Text(label)
                    .font(M.font(12.5, isCurrent ? .extraBold : .semiBold))
                    .foregroundStyle(dimmed)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
        } else {
            Text(match.mode == .finalScore ? "EIND" : "\(index + 1)")
                .font(M.font(isCurrent ? 14 : 13, isCurrent ? .extraBold : .regular))
                .foregroundStyle(dimmed)
        }
    }

    private func cell(round index: Int, seat: Int, player: Player) -> some View {
        let value = match.value(round: index, player: player)
        let isSelected = selectedRound == index && selectedSeat == seat
        let isLeaderColumn = player.id == leaderID

        return Button {
            select(round: index, seat: seat)
        } label: {
            Text(cellText(value: value, isSelected: isSelected))
                .font(isSelected ? M.font(20, .extraBold)
                      : (value == nil ? M.font(16, .regular) : M.font(19, .semiBold)))
                .foregroundStyle(value == nil && !isSelected ? M.inkAlpha(0.28) : M.ink)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 46)
                .background(isSelected ? M.redWash : (isLeaderColumn ? M.inkAlpha(0.05) : .clear))
                .overlay {
                    if isSelected { Rectangle().stroke(M.red, lineWidth: 2) }
                }
                .overlay(alignment: .trailing) { columnRule }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func cellText(value: Int?, isSelected: Bool) -> String {
        guard isSelected else {
            guard let value else { return "·" }
            return "\(value)"
        }
        if entry.isEmpty {
            return value.map { "\($0)|" } ?? "|"
        }
        return (negative ? "−" : "") + entry + "|"
    }

    private var averagesRow: some View {
        HStack(spacing: 0) {
            Text("GEM.")
                .font(M.font(9.5, .semiBold))
                .tracking(em: 0.1, size: 9.5)
                .foregroundStyle(M.inkAlpha(0.45))
                .frame(width: roundColumnWidth)
                .frame(minHeight: 44)
                .overlay(alignment: .trailing) { columnRule }

            ForEach(seats) { player in
                let standing = standings.first { $0.player.id == player.id }
                Text(standing.map { $0.roundsPlayed > 0 ? $0.average.dutch(1) : "—" } ?? "—")
                    .font(M.font(12.5, .regular))
                    .foregroundStyle(M.inkAlpha(0.55))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .overlay(alignment: .trailing) { columnRule }
            }
        }
        .background(M.paperDeep)
    }

    private var columnRule: some View {
        Rectangle().fill(M.hairline).frame(width: 1)
    }

    // MARK: - Invoerbalk

    private var keypadBar: some View {
        VStack(spacing: 0) {
            HeavyRule()
            HStack(alignment: .top, spacing: 26) {
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel("Invoer")
                        .padding(.bottom, 9)
                    Text(selectionLabel)
                        .font(M.font(21, .extraBold))
                        .tracking(em: -0.01, size: 21)
                        .foregroundStyle(M.ink)
                        .padding(.bottom, 6)
                    Text(selectionHint)
                        .font(M.font(12.5, .regular))
                        .foregroundStyle(M.inkAlpha(0.6))
                        .lineSpacing(5)
                        .frame(maxWidth: 300, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    nextRoundButton
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                keypad
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(M.paperDeep)
        }
    }

    private var selectionLabel: String {
        guard seats.indices.contains(selectedSeat) else { return "—" }
        let name = seats[selectedSeat].name
        if match.mode == .finalScore { return name }
        if let label = match.roundLabel(at: selectedRound) {
            return "\(name) · \(label.lowercased())"
        }
        return "\(name) · ronde \(selectedRound + 1)"
    }

    private var selectionHint: String {
        if match.isRoundFilled(selectedRound), selectedRound == match.currentRoundIndex {
            return "Ronde compleet. Rond de ronde af, of tik een cel om te corrigeren."
        }
        return match.allowNegative
            ? "Tik het aantal punten. ± maakt de invoer negatief. Bevestigen gaat naar de volgende speler."
            : "Tik het aantal punten. Bevestigen gaat naar de volgende speler in deze ronde."
    }

    private var nextRoundButton: some View {
        let filled = match.isRoundFilled(selectedRound)
        let isLast = match.roundCount > 0 && selectedRound >= match.roundCount - 1
        let title = match.mode == .finalScore ? "Potje afronden"
            : (isLast && filled ? "Potje afronden" : "Ronde afronden")

        return Button {
            advanceRound()
        } label: {
            Text(title)
                .font(M.font(14, .extraBold))
                .foregroundStyle(filled ? M.paper : M.ink)
                .padding(.horizontal, 20)
                .frame(minHeight: 48)
                .background(filled ? M.ink : Color.clear)
                .overlay(Rectangle().stroke(M.ink, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(!filled)
        .opacity(filled ? 1 : 0.55)
    }

    private var keypad: some View {
        let rows: [[String]] = [["7", "8", "9", "⌫"], ["4", "5", "6", "±"], ["1", "2", "3", "0"]]
        return VStack(spacing: 6) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { key(  $0) }
                }
            }
            key("Bevestigen", wide: true)
        }
        .fixedSize()
    }

    private func key(_ label: String, wide: Bool = false) -> some View {
        let isNumber = label.count == 1 && label.first!.isNumber
        let isConfirm = label == "Bevestigen"
        let isSign = label == "±"
        let signOn = isSign && negative
        let signDisabled = isSign && !match.allowNegative

        return Button {
            press(label)
        } label: {
            Text(label)
                .font(isConfirm ? M.font(14, .extraBold)
                      : isNumber ? M.font(21, .semiBold) : M.font(16, .semiBold))
                .foregroundStyle(isConfirm ? M.paper
                                 : signOn ? M.paper
                                 : signDisabled ? M.inkAlpha(0.3) : M.ink)
                .frame(width: wide ? 68 * 4 + 18 : 68, height: 48)
                .background(isConfirm ? M.red : signOn ? M.ink : isNumber ? M.paper : M.paperKey)
                .overlay(Rectangle().stroke(isConfirm ? M.red : M.inkAlpha(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(signDisabled)
    }

    // MARK: - Afronden

    private var finishPanel: some View {
        ModalPanel(title: "Potje afronden?", onClose: { confirmFinish = false }) {
            VStack(alignment: .leading, spacing: 16) {
                Text(finishMessage)
                    .font(M.font(13.5, .regular))
                    .foregroundStyle(M.inkAlpha(0.75))
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    OutlineButton(title: "Potje afbreken") { abandon() }
                    Spacer()
                    OutlineButton(title: "Terug") { confirmFinish = false }
                    SolidButton(title: "Afronden") { finish() }
                }
            }
            .padding(20)
        }
    }

    private var finishMessage: String {
        guard let leader = standings.first else {
            return "De eindstand wordt vastgelegd en telt mee in de statistieken."
        }
        return "\(leader.player.name) staat bovenaan met \(leader.total). De eindstand telt mee in de statistieken. Afbreken legt het potje weg zonder dat het ergens meetelt."
    }

    // MARK: - Bediening

    private func press(_ label: String) {
        switch label {
        case "⌫":
            if entry.isEmpty { negative = false } else { entry.removeLast() }
        case "±":
            if match.allowNegative { negative.toggle() }
        case "Bevestigen":
            commit()
        default:
            if entry.count < 3 { entry.append(label) }
        }
    }

    private func select(round index: Int, seat: Int) {
        selectedRound = index
        selectedSeat = seat
        entry = ""
        negative = false
    }

    private func commit() {
        guard seats.indices.contains(selectedSeat) else { return }
        let player = seats[selectedSeat]

        if entry.isEmpty {
            advanceSeat()
            return
        }

        snapshot()
        var value = Int(entry) ?? 0
        if negative && match.allowNegative { value = -value }
        round(at: selectedRound).setValue(value, for: player.id, in: context)
        entry = ""
        negative = false
        advanceSeat()
    }

    private func advanceSeat() {
        if selectedSeat + 1 < seats.count {
            selectedSeat += 1
        }
        entry = ""
        negative = false
    }

    private func firstEmptySeat(in index: Int) -> Int {
        for (seat, player) in seats.enumerated()
        where match.value(round: index, player: player) == nil { return seat }
        return 0
    }

    /// Haalt de ronde op, of maakt hem aan zodra er iets in komt te staan.
    private func round(at index: Int) -> MatchRound {
        if let existing = match.round(at: index) { return existing }
        let created = MatchRound(index: index)
        context.insert(created)
        created.match = match
        match.rounds.append(created)
        return created
    }

    private func advanceRound() {
        guard match.isRoundFilled(selectedRound) else { return }

        if match.mode == .finalScore { finish(); return }
        if match.roundCount > 0 && selectedRound >= match.roundCount - 1 { finish(); return }

        let next = selectedRound + 1
        selectedRound = next
        selectedSeat = 0
        entry = ""
        negative = false
    }

    private func finish() {
        match.endedAt = .now
        confirmFinish = false
        router.screen = .finish(match)
    }

    private func abandon() {
        match.abandonedAt = .now
        match.endedAt = .now
        confirmFinish = false
        router.screen = .play
    }

    // MARK: - Undo

    private func snapshot() {
        var state: [Int: [UUID: Int]] = [:]
        for round in match.rounds {
            var values: [UUID: Int] = [:]
            for entry in round.entries where entry.value != nil {
                values[entry.playerID] = entry.value
            }
            state[round.index] = values
        }
        undoStack.append(state)
        if undoStack.count > 20 { undoStack.removeFirst() }
    }

    private func undo() {
        guard let state = undoStack.popLast() else { return }
        for round in match.rounds {
            let values = state[round.index] ?? [:]
            for player in seats {
                round.setValue(values[player.id], for: player.id, in: context)
            }
        }
        entry = ""
        negative = false
    }
}

// MARK: - Alleen-winnaar

/// Voor spellen zonder punten: tik de spelers aan in de volgorde waarin ze
/// klaar waren.
private struct FinishOrderBoard: View {
    @Bindable var match: Match
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context

    private var seats: [Player] { match.orderedPlayers }

    private func place(of player: Player) -> Int? {
        match.value(round: 0, player: player)
    }

    private var nextPlace: Int {
        (seats.compactMap { place(of: $0) }.max() ?? 0) + 1
    }

    var body: some View {
        VStack(spacing: 0) {
            SectionLabel("Eindvolgorde — tik aan wie klaar is")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 18, leading: 28, bottom: 12, trailing: 28))
            Hairline()

            ForEach(seats) { player in
                RowButton(background: place(of: player) != nil ? M.inkAlpha(0.045) : .clear,
                          minHeight: 64) {
                    assign(player)
                } content: {
                    HStack(spacing: 14) {
                        Text(place(of: player).map { "\($0)" } ?? "·")
                            .font(M.font(15, .extraBold))
                            .foregroundStyle(place(of: player) == nil ? M.inkAlpha(0.3) : M.ink)
                            .frame(width: 22, alignment: .center)
                        Monogram(player: player)
                        Text(player.name)
                            .font(M.font(15, .semiBold))
                            .foregroundStyle(M.ink)
                        Spacer(minLength: 0)
                        if place(of: player) == 1 { Tag(text: "Won", background: M.red) }
                    }
                    .padding(.horizontal, 28)
                }
                Hairline()
            }

            HStack(spacing: 10) {
                OutlineButton(title: "Volgorde wissen") { clear() }
                Spacer()
                SolidButton(title: "Potje afronden", fill: M.ink, fontSize: 14,
                            enabled: seats.allSatisfy { place(of: $0) != nil }) {
                    match.endedAt = .now
                    router.screen = .finish(match)
                }
            }
            .padding(24)

            Spacer(minLength: 0)
        }
    }

    private func assign(_ player: Player) {
        let round = existingRound()
        if place(of: player) != nil {
            round.setValue(nil, for: player.id, in: context)
            renumber(round)
        } else {
            round.setValue(nextPlace, for: player.id, in: context)
        }
    }

    private func clear() {
        let round = existingRound()
        for player in seats { round.setValue(nil, for: player.id, in: context) }
    }

    /// Houdt de plaatsen aaneensluitend na het weghalen van iemand.
    private func renumber(_ round: MatchRound) {
        let ordered = seats
            .compactMap { player -> (Player, Int)? in
                guard let value = round.value(for: player.id) else { return nil }
                return (player, value)
            }
            .sorted { $0.1 < $1.1 }
        for (index, pair) in ordered.enumerated() {
            round.setValue(index + 1, for: pair.0.id, in: context)
        }
    }

    private func existingRound() -> MatchRound {
        if let existing = match.round(at: 0) { return existing }
        let created = MatchRound(index: 0)
        context.insert(created)
        created.match = match
        match.rounds.append(created)
        return created
    }
}
