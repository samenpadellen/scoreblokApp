import SwiftUI
import TipKit
import SwiftData

struct PlayScreen: View {
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @AppStorage(DemoData.matchesKey) private var demoMatches = ""
    @Query(sort: \GameTemplate.sortIndex) private var allTemplates: [GameTemplate]
    @Query(sort: \Match.startedAt, order: .reverse) private var matches: [Match]
    @Query private var players: [Player]
    @Environment(\.isNarrow) private var isNarrow
    @Environment(\.isCompact) private var isCompact
    @AppStorage(SettingsKey.startGuideHidden) private var startGuideHidden = false

    private var activePlayers: [Player] { players.filter { !$0.isArchived } }
    /// Wat er op de plank staat; de rest zit in de spellenkast.
    private var templates: [GameTemplate] { allTemplates.filter { !$0.isPutAway } }
    private var putAwayCount: Int { allTemplates.count - templates.count }
    /// Alle potjes die nog lopen, laatst gespeeld bovenaan. Ze blijven staan
    /// tot je ze afrondt, ook als dat dagen later is.
    private var openMatches: [Match] {
        matches.filter(\.isOpen).sorted { $0.lastPlayedAt > $1.lastPlayedAt }
    }

    /// De vier sjablonen die het laatst gespeeld zijn; aangevuld uit de lijst.
    private var recent: [GameTemplate] {
        var seen: [String] = []
        for match in matches where !seen.contains(match.gameName) {
            seen.append(match.gameName)
        }
        var ordered = seen.compactMap { name in templates.first { $0.name == name } }
        for template in templates where !ordered.contains(where: { $0.id == template.id }) {
            ordered.append(template)
        }
        return Array(ordered.prefix(4))
    }

    private var others: [GameTemplate] {
        let recentIDs = Set(recent.map(\.id))
        return templates.filter { !recentIDs.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                HeavyRule()

                if !demoMatches.isEmpty {
                    demoBanner
                    HeavyRule()
                }

                if let first = openMatches.first {
                    resumeCard(first)
                    ForEach(openMatches.dropFirst()) { match in
                        Hairline()
                        openRow(match)
                    }
                    HeavyRule()
                }

                if showsStartGuide {
                    startGuide
                    HeavyRule()
                }

                SectionHeader("Laatst gespeeld", insets: EdgeInsets(top: isCompact ? 16 : 22, leading: isCompact ? 20 : 28, bottom: 8, trailing: isCompact ? 20 : 28))
                if isCompact {
                    ForEach(recent) { template in
                        phoneRow(template, prominent: true)
                        Hairline()
                    }
                } else {
                    GridRows(items: recent, columns: isNarrow ? 2 : 4) { template in
                        recentCard(template)
                    }
                }

                SectionHeader("Alle spellen", insets: EdgeInsets(top: isCompact ? 16 : 22, leading: isCompact ? 20 : 28, bottom: 8, trailing: isCompact ? 20 : 28))
                if isCompact {
                    ForEach(others) { template in
                        phoneRow(template, prominent: false)
                        Hairline()
                    }
                    phoneNewGameRow
                    Hairline()
                    phoneCupboardRow
                    Hairline()
                } else {
                    GridRows(items: others, columns: isNarrow ? 2 : 3,
                             trailing: { newGameRow }) { template in
                        compactRow(template)
                    }
                    cupboardRow
                }

                if players.isEmpty && !showsStartGuide {
                    emptyHint
                }
            }
        }
    }

    // MARK: - Kop

    private var header: some View {
        let count = Text("\(templates.count) SPELLEN · \(activePlayers.count) SPELERS")
            .font(M.font(isCompact ? 10 : 11, .semiBold))
            .tracking(em: isCompact ? 0.12 : 0.1, size: isCompact ? 10 : 11)
            .foregroundStyle(M.inkAlpha(0.5))

        return Group {
            if isCompact {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Spelen")
                        .font(M.font(32, .extraBold))
                        .tracking(em: -0.025, size: 32)
                        .foregroundStyle(M.ink)
                    count
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 12, leading: 20, bottom: 16, trailing: 20))
            } else {
                HStack(alignment: .bottom) {
                    ScreenTitle("Spelen")
                    Spacer()
                    count
                }
                .padding(EdgeInsets(top: 24, leading: 28, bottom: 18, trailing: 28))
            }
        }
    }

    // MARK: - Aan de slag

    private var hasCounted: Bool { matches.contains(where: \.counts) }

    /// Tot het eerste potje is afgerond, of tot je het wegklikt.
    private var showsStartGuide: Bool { !startGuideHidden && !hasCounted }

    private struct GuideStep {
        let title: String
        let hint: String
        let done: Bool
        let action: () -> Void
    }

    private var guideSteps: [GuideStep] {
        let enoughPlayers = activePlayers.count >= 2
        return [
            GuideStep(title: "Voeg jezelf en je medespelers toe",
                      hint: enoughPlayers ? "\(activePlayers.count) spelers staan klaar"
                                          : "Bij Spelers, of straks bij het opzetten van een potje",
                      done: enoughPlayers,
                      action: { router.screen = .players }),
            GuideStep(title: "Start je eerste potje",
                      hint: matches.isEmpty ? "Kies hieronder een spel en tik op Start potje"
                                            : "Er loopt een potje. Tik om verder te tellen",
                      done: !matches.isEmpty,
                      action: {
                          if let open = openMatches.first { resume(open) } else if let game = recent.first { start(game) }
                      }),
            GuideStep(title: "Rond het potje af",
                      hint: "Tik op Afronden als het spel voorbij is. Dan zie je de uitslag en tellen de statistieken mee",
                      done: hasCounted,
                      action: { if let open = openMatches.first { resume(open) } })
        ]
    }

    private var startGuide: some View {
        let steps = guideSteps
        let doneCount = steps.filter(\.done).count
        let next = steps.firstIndex { !$0.done }
        let inset: CGFloat = isCompact ? 20 : 28

        return VStack(spacing: 0) {
            HStack(spacing: 9) {
                Rectangle().fill(M.red).frame(width: 7, height: 7)
                Text("Aan de slag · \(doneCount) van \(steps.count) gedaan".uppercased())
                    .font(M.font(11.5, .extraBold))
                    .tracking(em: 0.12, size: 11.5)
                    .foregroundStyle(M.ink)
                Spacer(minLength: 8)
                Button {
                    withAnimation(M.Motion.settle) { startGuideHidden = true }
                } label: {
                    Text("Verbergen")
                        .font(M.font(11.5, .semiBold))
                        .foregroundStyle(M.inkAlpha(0.55))
                        .frame(minHeight: 32)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .padding(EdgeInsets(top: 6, leading: inset, bottom: 6, trailing: inset))
            .background(M.paperDeep)
            BarMeter(fraction: Double(doneCount) / Double(steps.count), height: 3, fill: M.red)

            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                RowButton(isActive: index == next, minHeight: isCompact ? 66 : 70) {
                    step.action()
                } content: {
                    HStack(spacing: 14) {
                        HardCheckbox(isOn: step.done)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.title)
                                .font(M.font(isCompact ? 14.5 : 15.5, index == next ? .extraBold : .semiBold))
                                .foregroundStyle(step.done ? M.inkAlpha(0.45) : M.ink)
                                .strikethrough(step.done, color: M.inkAlpha(0.35))
                            Text(step.hint)
                                .font(M.font(isCompact ? 11.5 : 12, .regular))
                                .foregroundStyle(M.inkAlpha(0.55))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        if !step.done {
                            Text("→")
                                .font(M.font(15, .semiBold))
                                .foregroundStyle(index == next ? M.red : M.inkAlpha(0.3))
                        }
                    }
                    .padding(.horizontal, inset)
                    .padding(.vertical, 10)
                }
                if index < steps.count - 1 { Hairline() }
            }

            Hairline()
            Button {
                withAnimation(M.Motion.settle) { _ = DemoData.fill(in: context) }
            } label: {
                HStack(spacing: 8) {
                    Text("Liever eerst rondkijken? Vul de app met voorbeeldpotjes")
                        .font(M.font(isCompact ? 12 : 12.5, .extraBold))
                        .foregroundStyle(M.inkAlpha(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text("→")
                        .font(M.font(14, .semiBold))
                        .foregroundStyle(M.inkAlpha(0.5))
                }
                .padding(.horizontal, inset)
                .frame(minHeight: 48)
                .contentShape(.rect)
            }
            .buttonStyle(PressableStyle(scale: 0.995))
        }
        .transition(.opacity)
    }

    /// Duidelijk dat het voorbeelden zijn, met de weg terug ernaast.
    private var demoBanner: some View {
        let inset: CGFloat = isCompact ? 20 : 28
        return AnyLayout(isCompact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                                   : AnyLayout(HStackLayout(alignment: .center, spacing: 16))) {
            VStack(alignment: .leading, spacing: 4) {
                Text("VOORBEELDPOTJES")
                    .font(M.font(10.5, .extraBold))
                    .tracking(em: 0.14, size: 10.5)
                    .foregroundStyle(M.red)
                Text("Je kijkt naar voorbeelden")
                    .font(M.font(isCompact ? 16 : 17, .extraBold))
                    .foregroundStyle(M.ink)
                Text("Zo zie je hoe statistieken en geschiedenis eruitzien. Zelf beginnen? Haal ze weg; je eigen spelers en potjes blijven staan.")
                    .font(M.font(12.5, .regular))
                    .foregroundStyle(M.inkAlpha(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !isCompact { Spacer(minLength: 8) }
            OutlineButton(title: "Verwijder voorbeelden", tint: M.red) {
                withAnimation(M.Motion.settle) { _ = DemoData.remove(in: context) }
            }
        }
        .padding(.horizontal, inset)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(M.activeWash)
        .overlay(alignment: .leading) { Rectangle().fill(M.red).frame(width: M.activeEdge) }
    }

    private func resume(_ match: Match) {
        router.screen = match.mode == .scorecard ? .card(match) : .board(match)
    }

    // MARK: - Doorgaan met een open potje

    private func resumeCard(_ match: Match) -> some View {
        let accent = GameAccent.of(match.gameName)
        return Button {
            router.screen = match.mode == .scorecard ? .card(match) : .board(match)
        } label: {
            AnyLayout(isNarrow ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                      : AnyLayout(HStackLayout(spacing: 0))) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("POTJE OPEN — GA VERDER")
                        .font(M.font(10, .semiBold))
                        .tracking(em: 0.14, size: 10)
                        .foregroundStyle(accent.onInk)
                        .padding(.bottom, 10)
                    Text(match.gameName)
                        .font(M.font(26, .extraBold))
                        .tracking(em: -0.02, size: 26)
                        .foregroundStyle(M.paper)
                        .lineLimit(1)
                    Text(resumeSubtitle(match))
                        .font(M.font(13, .regular))
                        .foregroundStyle(M.paper.opacity(0.65))
                        .padding(.top, 6)
                }
                .padding(EdgeInsets(top: 20, leading: 28, bottom: 20, trailing: 28))
                .layoutPriority(0)

                Spacer(minLength: 12)

                HStack(spacing: 0) {
                    ForEach(match.standings.prefix(isNarrow ? 4 : 8)) { standing in
                        VStack(alignment: .leading, spacing: 0) {
                            Spacer(minLength: 0)
                            Text(standing.player.name.uppercased())
                                .font(M.font(11, .semiBold))
                                .tracking(em: 0.08, size: 11)
                                .foregroundStyle(M.paper.opacity(0.6))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .padding(.bottom, 8)
                            Text("\(standing.total)")
                                .font(M.font(28, .extraBold))
                                .tracking(em: -0.02, size: 28)
                                .foregroundStyle(standing.rank == 1 ? accent.onInk : M.paper)
                        }
                        .frame(maxWidth: isNarrow ? .infinity : nil, alignment: .leading)
                        .frame(width: isNarrow ? nil : 104, alignment: .leading)
                        .padding(EdgeInsets(top: isNarrow ? 14 : 20, leading: isNarrow ? 12 : 16,
                                            bottom: isNarrow ? 14 : 20, trailing: isNarrow ? 12 : 16))
                        .overlay(alignment: .leading) {
                            Rectangle().fill(M.paper.opacity(0.22)).frame(width: 1)
                        }
                    }
                }
                .fixedSize(horizontal: !isNarrow, vertical: false)
                .layoutPriority(1)
                .padding(.leading, isNarrow ? (isCompact ? 8 : 28) : 0)
                .padding(.bottom, isNarrow ? 8 : 0)
            }
            .background(M.ink)
            // Het accent van het spel als brede rand: aan de kleur zie je al
            // welk potje er openstaat.
            .overlay(alignment: .leading) {
                Rectangle().fill(accent.base).frame(width: 6)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func resumeSubtitle(_ match: Match) -> String {
        "\(position(match)) · laatst gespeeld \(match.lastPlayedText)"
    }

    /// Waar het potje staat: bij spellen met opdrachten die opdracht, anders
    /// het rondenummer.
    private func position(_ match: Match) -> String {
        switch match.mode {
        case .scorecard: "Scorekaart"
        case .winnerOnly: "Eindvolgorde vastleggen"
        case .finalScore: "Eindscore invullen"
        default:
            if let label = match.roundLabel(at: match.currentRoundIndex) {
                "Ronde \(match.currentRoundIndex + 1) · \(label.lowercased())"
            } else if match.roundCount > 0 {
                "Ronde \(match.currentRoundIndex + 1) van \(match.roundCount)"
            } else {
                "Ronde \(match.currentRoundIndex + 1)"
            }
        }
    }

    /// Compacte rij voor de overige open potjes.
    private func openRow(_ match: Match) -> some View {
        RowButton(minHeight: 62, edge: GameAccent.of(match.gameName).base) {
            router.screen = match.mode == .scorecard ? .card(match) : .board(match)
        } content: {
            HStack(spacing: 14) {
                GameMark(mono: match.mono, name: match.gameName, size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(match.gameName)
                        .font(M.font(14.5, .extraBold))
                        .foregroundStyle(M.ink)
                        .lineLimit(1)
                    Text(resumeSubtitle(match))
                        .font(M.font(11.5, .regular))
                        .foregroundStyle(M.inkAlpha(0.5))
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    // Op de telefoon passen er niet meer dan twee naast de naam.
                    ForEach(match.standings.prefix(isCompact ? 2 : 5)) { standing in
                        HStack(spacing: 7) {
                            PlayerMark(player: standing.player, size: 16)
                            Text("\(standing.total)")
                                .font(M.font(11.5, .semiBold))
                                .foregroundStyle(M.ink)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .overlay(Rectangle().stroke(M.hairline, lineWidth: 1))
                    }
                }
                Text("→")
                    .font(M.font(15, .regular))
                    .foregroundStyle(M.inkAlpha(0.35))
            }
            .padding(.horizontal, 28)
        }
    }

    // MARK: - Spelkaarten

    private func recentCard(_ template: GameTemplate) -> some View {
        RowButton(minHeight: 146) {
            start(template)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                GameMark(mono: template.mono, name: template.name,
                         background: template.id == recent.first?.id ? M.red : M.ink,
                         size: 44)
                    .padding(.bottom, 14)
                Spacer(minLength: 0)
                Text(template.name)
                    .font(M.font(19, .extraBold))
                    .tracking(em: -0.01, size: 19)
                    .foregroundStyle(M.ink)
                    .padding(.bottom, 6)
                Text(template.subtitle)
                    .font(M.font(12, .regular))
                    .foregroundStyle(M.inkAlpha(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 18, leading: 18, bottom: 20, trailing: 18))
        }
    }

    private func compactRow(_ template: GameTemplate) -> some View {
        RowButton(minHeight: 66) {
            start(template)
        } content: {
            HStack(spacing: 14) {
                GameMark(mono: template.mono, name: template.name, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(template.name)
                        .font(M.font(14.5, .semiBold))
                        .foregroundStyle(M.ink)
                        .lineLimit(1)
                    Text(template.subtitle)
                        .font(M.font(11.5, .regular))
                        .foregroundStyle(M.inkAlpha(0.5))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
        }
    }

    /// Op de telefoon geen kaarten maar rijen: laatst gespeeld wat zwaarder
    /// gezet dan de rest, zoals het ontwerp voorschrijft.
    private func phoneRow(_ template: GameTemplate, prominent: Bool) -> some View {
        RowButton(minHeight: prominent ? 64 : 56) {
            start(template)
        } content: {
            HStack(spacing: 14) {
                GameMark(mono: template.mono, name: template.name,
                         background: prominent && template.id == recent.first?.id ? M.red : M.ink,
                         size: prominent ? 36 : 28)
                if prominent {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(template.name)
                            .font(M.font(15, .extraBold))
                            .foregroundStyle(M.ink)
                            .lineLimit(1)
                        Text(template.subtitle)
                            .font(M.font(11.5, .regular))
                            .foregroundStyle(M.inkAlpha(0.5))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text("→")
                        .font(M.font(15, .regular))
                        .foregroundStyle(M.inkAlpha(0.3))
                } else {
                    Text(template.name)
                        .font(M.font(14, .semiBold))
                        .foregroundStyle(M.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(template.subtitle)
                        .font(M.font(11, .regular))
                        .foregroundStyle(M.inkAlpha(0.45))
                        .lineLimit(1)
                        .layoutPriority(0)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    /// De spellenkast: spellen die je niet speelt staan hier, niet in het
    /// overzicht.
    private var phoneCupboardRow: some View {
        RowButton(minHeight: 56) {
            router.screen = .cupboard
        } content: {
            HStack(spacing: 14) {
                GameMark(mono: "··", background: M.inkAlpha(0.35), size: 28)
                Text("Spellenkast")
                    .font(M.font(14, .semiBold))
                    .foregroundStyle(M.ink)
                Spacer(minLength: 8)
                Text(putAwayCount == 0 ? "alles op de plank"
                     : "\(putAwayCount) opgeborgen")
                    .font(M.font(11, .regular))
                    .foregroundStyle(M.inkAlpha(0.45))
            }
            .padding(.horizontal, 20)
        }
    }

    private var cupboardRow: some View {
        RowButton(minHeight: 56) {
            router.screen = .cupboard
        } content: {
            HStack(spacing: 14) {
                GameMark(mono: "··", background: M.inkAlpha(0.35), size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Spellenkast")
                        .font(M.font(14.5, .semiBold))
                        .foregroundStyle(M.ink)
                    Text(putAwayCount == 0 ? "alles staat op de plank"
                         : "\(putAwayCount) opgeborgen")
                        .font(M.font(11.5, .regular))
                        .foregroundStyle(M.inkAlpha(0.5))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)
        }
        .overlay(alignment: .top) { Hairline() }
        .help("Berg spellen op die je niet speelt")
        .popoverTip(CupboardTip())
    }

    private var phoneNewGameRow: some View {
        RowButton(minHeight: 56) {
            router.screen = .custom(nil)
        } content: {
            HStack(spacing: 14) {
                Text("+")
                    .font(M.font(15, .extraBold))
                    .foregroundStyle(M.red)
                    .frame(width: 28, height: 28)
                    .overlay(Rectangle().stroke(M.red, lineWidth: 2))
                Text("Eigen spel maken")
                    .font(M.font(14, .extraBold))
                    .foregroundStyle(M.red)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
        }
    }

    private var newGameRow: some View {
        RowButton(minHeight: 66) {
            router.screen = .custom(nil)
        } content: {
            HStack(spacing: 14) {
                Text("+")
                    .font(M.font(18, .extraBold))
                    .foregroundStyle(M.red)
                    .frame(width: 34, height: 34)
                    .overlay(Rectangle().stroke(M.red, lineWidth: 2))
                Text("Eigen spel maken")
                    .font(M.font(14.5, .extraBold))
                    .foregroundStyle(M.red)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
        }
    }

    private var emptyHint: some View {
        Text("Nog geen spelers. Kies een spel — je voegt de spelers toe bij het opzetten van het potje.")
            .font(M.font(12.5, .regular))
            .foregroundStyle(M.inkAlpha(0.55))
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 20, leading: 28, bottom: 28, trailing: 28))
    }

    private func start(_ template: GameTemplate) {
        router.screen = .setup(template)
    }
}

// MARK: - Raster met harde scheidslijnen

/// Legt items in rijen van `columns` neer met haarlijnen ertussen, zodat het
/// raster ook bij een onvolledige laatste rij dichtloopt.
struct GridRows<Item: Identifiable, Cell: View, Trailing: View>: View {
    let items: [Item]
    let columns: Int
    var trailing: () -> Trailing
    @ViewBuilder let cell: (Item) -> Cell

    init(items: [Item], columns: Int,
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
         @ViewBuilder cell: @escaping (Item) -> Cell) {
        self.items = items
        self.columns = columns
        self.trailing = trailing
        self.cell = cell
    }

    private var slots: Int {
        items.count + (Trailing.self == EmptyView.self ? 0 : 1)
    }

    private var rowCount: Int {
        max(Int(ceil(Double(slots) / Double(columns))), 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rowCount, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        Group {
                            if index < items.count {
                                cell(items[index])
                            } else if index == items.count, Trailing.self != EmptyView.self {
                                trailing()
                            } else {
                                Color.clear
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .trailing) {
                            Rectangle().fill(M.hairline).frame(width: 1)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(M.hairline).frame(height: 1)
                }
            }
        }
    }
}
