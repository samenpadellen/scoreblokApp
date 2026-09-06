import SwiftUI
import SwiftData

struct SetupScreen: View {
    let template: GameTemplate

    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \Player.createdAt) private var allPlayers: [Player]
    @Query(sort: \Match.startedAt, order: .reverse) private var matches: [Match]

    @State private var chosen: [UUID] = []
    @State private var roundCount = 0
    @State private var winsByLowest = true
    @State private var allowNegative = false
    @State private var eliminationLimit = 10
    @State private var addingPlayer = false
    @State private var newName = ""

    private var roster: [Player] { allPlayers.filter { !$0.isArchived } }
    private var seated: [Player] { chosen.compactMap { id in roster.first { $0.id == id } } }
    private var canStart: Bool {
        seated.count >= template.minPlayers && seated.count <= template.maxPlayers
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            HeavyRule()

            GeometryReader { proxy in
                HStack(spacing: 0) {
                    ScrollView { participants }
                        .frame(width: proxy.size.width * 0.6)
                    Rectangle().fill(M.ruleHeavy).frame(width: 2)
                    ScrollView { rules }
                }
            }
        }
        .overlay { if addingPlayer { newPlayerPanel } }
        .onAppear(perform: prefill)
    }

    // MARK: - Balk

    private var toolbar: some View {
        ScreenBar(backTitle: "Spelen",
                  onBack: { router.screen = .play },
                  title: "Potje opzetten · \(template.name)") {
            OutlineButton(title: "Zelfde ploeg als vorige keer") { repeatLastTeam() }
                .opacity(lastTeam == nil ? 0.4 : 1)
                .disabled(lastTeam == nil)
            SolidButton(title: "Start potje", fontSize: 14, enabled: canStart) { start() }
        }
    }

    private var lastTeam: [Player]? {
        matches.first { $0.gameName == template.name }?.orderedPlayers
            ?? matches.first?.orderedPlayers
    }

    // MARK: - Spelers

    private var participants: some View {
        VStack(spacing: 0) {
            SectionLabel("Wie spelen mee — \(seated.count) gekozen")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 18, leading: 24, bottom: 12, trailing: 24))
            Hairline()

            GridRows(items: roster, columns: 2, trailing: { addPlayerRow }) { player in
                playerRow(player)
            }

            SectionLabel("Volgorde aan tafel")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 20, leading: 24, bottom: 12, trailing: 24))
            Hairline()

            if seated.isEmpty {
                Text("Kies eerst wie er meedoen.")
                    .font(M.font(12.5, .regular))
                    .foregroundStyle(M.inkAlpha(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
            }

            ForEach(Array(seated.enumerated()), id: \.element.id) { index, player in
                seatRow(index: index, player: player)
                Hairline()
            }

            if seated.count > template.maxPlayers || (seated.count > 0 && seated.count < template.minPlayers) {
                Text("\(template.name) speel je met \(template.minPlayers)–\(template.maxPlayers) spelers.")
                    .font(M.font(12.5, .regular))
                    .foregroundStyle(M.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(EdgeInsets(top: 16, leading: 24, bottom: 24, trailing: 24))
            }
        }
    }

    private func playerRow(_ player: Player) -> some View {
        let isOn = chosen.contains(player.id)
        return RowButton(background: isOn ? M.inkAlpha(0.045) : .clear, minHeight: 64) {
            toggle(player)
        } content: {
            HStack(spacing: 13) {
                HardCheckbox(isOn: isOn)
                Monogram(player: player)
                VStack(alignment: .leading, spacing: 3) {
                    Text(player.name)
                        .font(M.font(15, .semiBold))
                        .foregroundStyle(M.ink)
                        .lineLimit(1)
                    Text(meta(for: player))
                        .font(M.font(11.5, .regular))
                        .foregroundStyle(M.inkAlpha(0.5))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
        }
    }

    private func meta(for player: Player) -> String {
        let count = matches.filter { m in m.counts && m.players.contains { $0.id == player.id } }.count
        let potjes = count == 1 ? "1 potje" : "\(count) potjes"
        return player.isMe ? "jij · \(potjes)" : potjes
    }

    private var addPlayerRow: some View {
        RowButton(minHeight: 64) {
            newName = ""
            addingPlayer = true
        } content: {
            HStack(spacing: 13) {
                Color.clear.frame(width: 20, height: 20)
                Text("+")
                    .font(M.font(17, .extraBold))
                    .foregroundStyle(M.red)
                    .frame(width: 34, height: 34)
                    .overlay(Rectangle().stroke(M.red, lineWidth: 2))
                Text("Nieuwe speler")
                    .font(M.font(14, .extraBold))
                    .foregroundStyle(M.red)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
        }
    }

    private func seatRow(index: Int, player: Player) -> some View {
        HStack(spacing: 14) {
            Text("\(index + 1)")
                .font(M.font(13, .extraBold))
                .foregroundStyle(M.inkAlpha(0.4))
                .frame(width: 16, alignment: .leading)
            Monogram(player: player, size: 30)
            Text(player.name)
                .font(M.font(15, .semiBold))
                .foregroundStyle(M.ink)
            Spacer(minLength: 0)
            seatButton("▲", enabled: index > 0) { move(from: index, to: index - 1) }
            seatButton("▼", enabled: index < seated.count - 1) { move(from: index, to: index + 1) }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
    }

    private func seatButton(_ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(M.font(12, .regular))
                .foregroundStyle(enabled ? M.ink : M.inkAlpha(0.25))
                .frame(width: M.tap, height: M.tap)
                .overlay(Rectangle().stroke(M.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Regels

    private var rules: some View {
        VStack(spacing: 0) {
            SectionLabel("Regels voor dit potje")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 18, leading: 24, bottom: 12, trailing: 24))
            Hairline()

            switch template.mode {
            case .roundsCumulative:
                roundsRow
                Hairline()
                winnerRow
                Hairline()
                negativeRow
                Hairline()
            case .finalScore:
                winnerRow
                Hairline()
            case .elimination:
                limitRow
                Hairline()
                negativeRow
                Hairline()
            case .scorecard, .winnerOnly:
                RuleRow(title: "Vast sjabloon",
                        hint: template.mode == .scorecard
                            ? "De categorieën en de formule liggen vast in het spel."
                            : "Je legt alleen de eindvolgorde vast.") { EmptyView() }
                Hairline()
            }

            freezeNote
        }
    }

    private var roundsRow: some View {
        RuleRow(title: "Aantal rondes",
                hint: template.roundCount == 0
                    ? "Sjabloon: open einde"
                    : "Sjabloon: \(template.roundCount)") {
            HStack(spacing: 12) {
                Text(roundCount == 0 ? "∞" : "\(roundCount)")
                    .font(M.font(20, .extraBold))
                    .foregroundStyle(M.ink)
                    .frame(minWidth: 24, alignment: .trailing)
                StepperPair(canDecrement: roundCount > 0, canIncrement: roundCount < 24) {
                    roundCount = max(0, roundCount - 1)
                } onIncrement: {
                    roundCount = min(24, roundCount + 1)
                }
            }
        }
    }

    private var winnerRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Wie wint")
                .font(M.font(15, .semiBold))
                .foregroundStyle(M.ink)
            SegmentedBar(options: [(true, "Laagste totaal"), (false, "Hoogste totaal")],
                         selection: $winsByLowest)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var negativeRow: some View {
        RuleRow(title: "Negatieve punten",
                hint: "Zet de ±-toets aan op het bord") {
            HardToggle(isOn: $allowNegative)
        }
    }

    private var limitRow: some View {
        RuleRow(title: "Afvalgrens",
                hint: "Wie deze strafpunten haalt, ligt eruit") {
            HStack(spacing: 12) {
                Text("\(eliminationLimit)")
                    .font(M.font(20, .extraBold))
                    .foregroundStyle(M.ink)
                    .frame(minWidth: 24, alignment: .trailing)
                StepperPair(canDecrement: eliminationLimit > 1, canIncrement: eliminationLimit < 100) {
                    eliminationLimit = max(1, eliminationLimit - 1)
                } onIncrement: {
                    eliminationLimit = min(100, eliminationLimit + 1)
                }
            }
        }
    }

    private var freezeNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Regels bevriezen")
            Text("Bij Start potje wordt het sjabloon gekopieerd naar dit potje. Pas je \(template.name) later aan, dan verandert deze historie niet mee.")
                .font(M.font(13, .regular))
                .foregroundStyle(M.inkAlpha(0.75))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 18, leading: 24, bottom: 18, trailing: 24))
        .background(M.paperDeep)
        .overlay(alignment: .bottom) { HeavyRule() }
    }

    // MARK: - Nieuwe speler

    private var newPlayerPanel: some View {
        ModalPanel(title: "Nieuwe speler", onClose: { addingPlayer = false }) {
            VStack(alignment: .leading, spacing: 16) {
                HardTextField(placeholder: "Naam", text: $newName)
                HStack(spacing: 10) {
                    Spacer()
                    OutlineButton(title: "Annuleer") { addingPlayer = false }
                    SolidButton(title: "Toevoegen",
                                enabled: !newName.trimmingCharacters(in: .whitespaces).isEmpty) {
                        addPlayer()
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - Acties

    private func prefill() {
        roundCount = template.roundCount
        winsByLowest = template.winsByLowest
        allowNegative = template.allowNegative
        eliminationLimit = template.eliminationLimit
        if chosen.isEmpty { repeatLastTeam() }
    }

    private func repeatLastTeam() {
        guard let team = lastTeam else { return }
        chosen = team.filter { !$0.isArchived }.prefix(template.maxPlayers).map(\.id)
    }

    private func toggle(_ player: Player) {
        if let index = chosen.firstIndex(of: player.id) {
            chosen.remove(at: index)
        } else {
            chosen.append(player.id)
        }
    }

    private func move(from: Int, to: Int) {
        guard chosen.indices.contains(from), chosen.indices.contains(to) else { return }
        chosen.swapAt(from, to)
    }

    private func addPlayer() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let player = Player(name: name,
                            rampIndex: allPlayers.count % M.playerRamp.count,
                            isMe: allPlayers.isEmpty)
        context.insert(player)
        chosen.append(player.id)
        addingPlayer = false
    }

    private func start() {
        let match = Match(template: template)
        context.insert(match)
        match.seat(seated)
        // De regels van dit scherm overschrijven de bevroren kopie.
        match.roundCount = roundCount
        match.winsByLowest = winsByLowest
        match.allowNegative = allowNegative
        match.eliminationLimit = eliminationLimit

        if match.mode == .scorecard {
            for player in seated {
                let card = ScoreCard(playerID: player.id)
                context.insert(card)
                card.match = match
                match.cards.append(card)
            }
            router.screen = .card(match)
        } else {
            router.screen = .board(match)
        }
    }
}
