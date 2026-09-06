import SwiftUI
import SwiftData

struct ScorecardScreen: View {
    @Bindable var match: Match

    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context

    @State private var selectedPlayerID: UUID?
    @State private var editingColumn: ScoreColumn?
    @State private var editingText = ""
    @State private var confirmFinish = false

    private var spec: ScorecardSpec { match.scorecard ?? .empty }
    private var seats: [Player] { match.orderedPlayers }
    private var current: Player? {
        seats.first { $0.id == selectedPlayerID } ?? seats.first
    }
    private var card: ScoreCard? {
        guard let current else { return nil }
        if let existing = match.card(for: current) { return existing }
        let created = ScoreCard(playerID: current.id)
        context.insert(created)
        created.match = match
        match.cards.append(created)
        return created
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            HeavyRule()
            ScrollView {
                VStack(spacing: 0) {
                    columnsBlock
                    lowerBlocks
                }
            }
        }
        .overlay { if editingColumn != nil { numberPanel } }
        .overlay { if confirmFinish { finishPanel } }
        .onAppear { if selectedPlayerID == nil { selectedPlayerID = seats.first?.id } }
    }

    // MARK: - Balk

    private var toolbar: some View {
        ScreenBar(backTitle: "Spelen",
                  onBack: { router.screen = .play },
                  title: match.gameName,
                  subtitle: "scorekaart · \(match.winsByLowest ? "laagste" : "hoogste") wint") {
            HStack(spacing: 0) {
                ForEach(Array(seats.enumerated()), id: \.element.id) { index, player in
                    let isOn = player.id == current?.id
                    Button {
                        selectedPlayerID = player.id
                    } label: {
                        Text(player.name)
                            .font(M.font(12.5, .extraBold))
                            .foregroundStyle(isOn ? M.paper : M.ink)
                            .padding(.horizontal, 16)
                            .frame(minHeight: M.tap)
                            .background(isOn ? M.ink : .clear)
                    }
                    .buttonStyle(.plain)
                    if index < seats.count - 1 {
                        Rectangle().fill(M.ruleHeavy).frame(width: 1)
                    }
                }
            }
            .overlay(Rectangle().stroke(M.ruleHeavy, lineWidth: 1))

            SolidButton(title: "Potje afronden", fill: M.ink, fontSize: 12.5) {
                confirmFinish = true
            }
        }
    }

    // MARK: - Categorieën

    private var columnsBlock: some View {
        VStack(spacing: 0) {
            SectionLabel(spec.columnsTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 18, leading: 24, bottom: 10, trailing: 24))
            Hairline()

            let perRow = spec.columns.count > 8 ? min(spec.columns.count, 15) : max(spec.columns.count, 1)
            let rows = stride(from: 0, to: spec.columns.count, by: perRow).map { start in
                Array(spec.columns[start..<min(start + perRow, spec.columns.count)])
            }

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(row) { column in
                        columnCell(column)
                    }
                    // Vul de laatste rij op zodat het raster dichtloopt.
                    if row.count < perRow {
                        ForEach(0..<(perRow - row.count), id: \.self) { _ in
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .overlay(alignment: .trailing) {
                                    Rectangle().fill(M.hairline).frame(width: 1)
                                }
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Hairline()
            }
        }
    }

    private func columnCell(_ column: ScoreColumn) -> some View {
        let isOn = card?.columnKeys.contains(column.key) ?? false
        let number = card?.numbers[column.key]
        let filled = column.kind == .toggle ? isOn : (number != nil)

        return Button {
            tap(column)
        } label: {
            VStack(spacing: 0) {
                Text(column.label)
                    .font(M.font(column.label.count > 3 ? 12 : 17, .extraBold))
                    .foregroundStyle(filled ? M.paper : M.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                Text(column.kind == .toggle ? "\(column.value)" : (number.map { "\($0)" } ?? "—"))
                    .font(M.font(11, .regular))
                    .foregroundStyle((filled ? M.paper : M.ink).opacity(0.65))
                    .padding(.top, 7)
                Text(column.kind == .toggle ? (isOn ? "✓" : "") : "")
                    .font(M.font(11, .extraBold))
                    .foregroundStyle(M.paper)
                    .frame(minHeight: 11)
                    .padding(.top, 9)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(filled ? M.ink : Color.clear)
            .overlay(alignment: .trailing) {
                Rectangle().fill(M.hairline).frame(width: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bonussen, aftrek en eindscore

    private var lowerBlocks: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                if !spec.bonuses.isEmpty {
                    SectionLabel(spec.bonusesTitle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(EdgeInsets(top: 18, leading: 24, bottom: 10, trailing: 24))
                    Hairline()
                    ForEach(spec.bonuses) { bonus in
                        bonusRow(bonus)
                        Hairline()
                    }
                }
                if let rule = spec.sectionBonus {
                    sectionBonusRow(rule)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .trailing) { Rectangle().fill(M.hairline).frame(width: 1) }

            VStack(spacing: 0) {
                if spec.hasPenalty {
                    SectionLabel(spec.penaltyTitle ?? "")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(EdgeInsets(top: 18, leading: 24, bottom: 10, trailing: 24))
                    Hairline()
                    penaltyRow
                    Hairline()
                }
                totalBlock
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func bonusRow(_ bonus: ScoreBonus) -> some View {
        let isOn = card?.bonusKeys.contains(bonus.key) ?? false
        return RowButton(background: isOn ? M.inkAlpha(0.045) : .clear, minHeight: 52) {
            guard let card else { return }
            if isOn { card.bonusKeys.removeAll { $0 == bonus.key } }
            else { card.bonusKeys.append(bonus.key) }
        } content: {
            HStack(spacing: 14) {
                HardCheckbox(isOn: isOn)
                Text(bonus.label)
                    .font(M.font(14.5, .semiBold))
                    .foregroundStyle(M.ink)
                Spacer(minLength: 0)
                Text("\(bonus.value) punten")
                    .font(M.font(12.5, .regular))
                    .foregroundStyle(M.inkAlpha(0.5))
            }
            .padding(.horizontal, 24)
        }
    }

    private func sectionBonusRow(_ rule: SectionBonus) -> some View {
        let earned = (card?.sectionBonusPoints(spec: spec) ?? 0) > 0
        return VStack(spacing: 0) {
            SectionLabel("Sectiebonus")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 18, leading: 24, bottom: 10, trailing: 24))
            Hairline()
            HStack(spacing: 14) {
                HardCheckbox(isOn: earned)
                Text(rule.label)
                    .font(M.font(14.5, .semiBold))
                    .foregroundStyle(M.ink)
                Spacer(minLength: 0)
                Text(earned ? "+\(rule.bonus)" : "nog niet")
                    .font(M.font(12.5, .regular))
                    .foregroundStyle(M.inkAlpha(0.5))
            }
            .padding(.horizontal, 24)
            .frame(minHeight: 52)
            Hairline()
        }
    }

    private var penaltyRow: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(card?.penaltyCount ?? 0)")
                    .font(M.font(34, .extraBold))
                    .tracking(em: -0.02, size: 34)
                    .foregroundStyle(M.ink)
                Text(spec.penaltyLabel ?? "")
                    .font(M.font(11.5, .regular))
                    .foregroundStyle(M.inkAlpha(0.5))
            }
            Spacer(minLength: 0)
            StepperPair(canDecrement: (card?.penaltyCount ?? 0) > 0,
                        canIncrement: (card?.penaltyCount ?? 0) < spec.penaltyMax) {
                card?.penaltyCount = max(0, (card?.penaltyCount ?? 0) - 1)
            } onIncrement: {
                card?.penaltyCount = min(spec.penaltyMax, (card?.penaltyCount ?? 0) + 1)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(minHeight: 76)
    }

    private var totalBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Eindscore")
                .padding(.bottom, 10)
            Text(formula)
                .font(M.font(13.5, .regular))
                .foregroundStyle(M.inkAlpha(0.75))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)
            Text("\(card?.total(spec: spec) ?? 0)")
                .font(M.font(46, .extraBold))
                .tracking(em: -0.03, size: 46)
                .foregroundStyle(M.red)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 18, leading: 24, bottom: 18, trailing: 24))
        .background(M.paperDeep)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var formula: String {
        guard let card else { return "" }
        var parts = ["categorieën \(card.columnPoints(spec: spec))"]
        if !spec.bonuses.isEmpty { parts.append("+ bonussen \(card.bonusPoints(spec: spec))") }
        if spec.sectionBonus != nil { parts.append("+ sectiebonus \(card.sectionBonusPoints(spec: spec))") }
        if spec.hasPenalty {
            let label = (spec.penaltyTitle ?? "aftrek").components(separatedBy: " ").first ?? "aftrek"
            parts.append("− \(label.lowercased()) \(abs(card.penaltyPoints(spec: spec)))")
        }
        return parts.joined(separator: " ") + " ="
    }

    // MARK: - Getal invullen

    private var numberPanel: some View {
        ModalPanel(title: editingColumn?.label ?? "", onClose: { editingColumn = nil }) {
            VStack(alignment: .leading, spacing: 16) {
                HardTextField(placeholder: "0", text: $editingText, fontSize: 28, minHeight: 64)
                    .keyboardType(.numbersAndPunctuation)
                HStack(spacing: 10) {
                    OutlineButton(title: "Leegmaken") {
                        if let column = editingColumn, let card {
                            var numbers = card.numbers
                            numbers.removeValue(forKey: column.key)
                            card.numbers = numbers
                        }
                        editingColumn = nil
                    }
                    Spacer()
                    SolidButton(title: "Bewaar") { saveNumber() }
                }
            }
            .padding(20)
        }
    }

    private func tap(_ column: ScoreColumn) {
        guard let card else { return }
        switch column.kind {
        case .toggle:
            if card.columnKeys.contains(column.key) {
                card.columnKeys.removeAll { $0 == column.key }
            } else {
                card.columnKeys.append(column.key)
            }
        case .number:
            editingText = card.numbers[column.key].map { "\($0)" } ?? ""
            editingColumn = column
        }
    }

    private func saveNumber() {
        if let column = editingColumn, let card,
           let value = Int(editingText.trimmingCharacters(in: .whitespaces)) {
            var numbers = card.numbers
            numbers[column.key] = value
            card.numbers = numbers
        }
        editingColumn = nil
    }

    // MARK: - Afronden

    private var finishPanel: some View {
        ModalPanel(title: "Potje afronden?", onClose: { confirmFinish = false }) {
            VStack(alignment: .leading, spacing: 16) {
                Text("De kaarten van alle spelers worden vastgelegd en tellen mee in de statistieken.")
                    .font(M.font(13.5, .regular))
                    .foregroundStyle(M.inkAlpha(0.75))
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    OutlineButton(title: "Potje afbreken") {
                        match.abandonedAt = .now
                        match.endedAt = .now
                        confirmFinish = false
                        router.screen = .play
                    }
                    Spacer()
                    OutlineButton(title: "Terug") { confirmFinish = false }
                    SolidButton(title: "Afronden") {
                        match.endedAt = .now
                        confirmFinish = false
                        router.screen = .finish(match)
                    }
                }
            }
            .padding(20)
        }
    }
}
