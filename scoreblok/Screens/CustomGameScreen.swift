import SwiftUI
import SwiftData

struct CustomGameScreen: View {
    let existing: GameTemplate?

    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.isCompact) private var isCompact
    @Query(sort: \GameTemplate.sortIndex) private var templates: [GameTemplate]

    @State private var name = ""
    @State private var mono = ""
    @State private var mode: ScoringMode = .roundsCumulative
    @State private var roundCount = 9
    @State private var winsByLowest = true
    @State private var allowNegative = false
    @State private var minPlayers = 2
    @State private var maxPlayers = 8
    @State private var eliminationLimit = 10
    @State private var supportsJokers = false
    @State private var unitLabel = "punten"
    @State private var roundLabels: [String] = []
    @State private var borrowedCard: String = "Keer op Keer"
    @State private var saved = false
    @State private var describing = ""
    @State private var assistant = GameAssistant()

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var canSave: Bool { !trimmedName.isEmpty && !mono.isEmpty }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                bar
                Hairline()
                header
                HeavyRule()
                assistantBlock
                identity
                Hairline()
                modeBlock
                fields
            }
        }
        .onAppear(perform: prefill)
    }

    // MARK: - Kop

    private var bar: some View {
        HStack(spacing: 16) {
            BackLink(title: "Spelen") { router.screen = .play }
            Spacer()
            if saved {
                Text("Bewaard")
                    .font(M.font(12, .semiBold))
                    .foregroundStyle(M.inkAlpha(0.5))
            }
            SolidButton(title: "Sjabloon opslaan", enabled: canSave) { save() }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScreenTitle(existing == nil ? "Eigen spel" : existing!.name)
            Text("Dezelfde editor als waarmee de ingebouwde sjablonen zijn gemaakt. Puntwaarden staan in het sjabloon, niet in code — huisregels pas je hier aan.")
                .font(M.font(13, .regular))
                .foregroundStyle(M.inkAlpha(0.6))
                .lineSpacing(5)
                .frame(maxWidth: 560, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 24, leading: 28, bottom: 18, trailing: 28))
    }

    // MARK: - Beschrijven in gewone taal

    /// Het model draait op het apparaat zelf; zonder Apple Intelligence blijft
    /// de editor gewoon met de hand te bedienen.
    private var assistantBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel("Beschrijf het spel")
                Spacer()
                if let explanation = assistant.readiness.explanation {
                    Text(explanation)
                        .font(M.font(11.5, .regular))
                        .foregroundStyle(M.inkAlpha(0.45))
                }
            }

            HStack(spacing: 10) {
                HardTextField(placeholder: "Boerenbridge, 16 rondes, je voorspelt je slagen, hoogste totaal wint",
                              text: $describing, fontSize: 14)
                    .disabled(!assistant.isReady)
                    .opacity(assistant.isReady ? 1 : 0.5)
                    .onSubmit { runAssistant() }

                SolidButton(title: assistant.state == .thinking ? "Bezig…" : "Vul in",
                            minHeight: 48,
                            enabled: assistant.isReady && assistant.state != .thinking
                                     && !describing.trimmingCharacters(in: .whitespaces).isEmpty) {
                    runAssistant()
                }
            }

            if case .failed(let message) = assistant.state {
                Text(message)
                    .font(M.font(12, .regular))
                    .foregroundStyle(M.red)
            } else {
                Text("Het voorstel vult de velden hieronder in. Alles blijft daarna aanpasbaar; er gaat niets naar een server.")
                    .font(M.font(12, .regular))
                    .foregroundStyle(M.inkAlpha(0.55))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 18, leading: 24, bottom: 20, trailing: 24))
        .background(M.paperDeep)
        .overlay(alignment: .bottom) { HeavyRule() }
    }

    private func runAssistant() {
        assistant.clearError()
        let text = describing
        Task {
            guard let suggestion = await assistant.suggest(from: text) else { return }
            apply(suggestion)
        }
    }

    private func apply(_ suggestion: GameSuggestion) {
        name = suggestion.name
        mono = suggestion.mono
        monoWasEdited = true
        mode = suggestion.mode
        roundCount = suggestion.roundCount
        winsByLowest = suggestion.winsByLowest
        allowNegative = suggestion.allowNegative
        minPlayers = suggestion.minPlayers
        maxPlayers = suggestion.maxPlayers
        eliminationLimit = suggestion.eliminationLimit
        unitLabel = suggestion.unitLabel
        roundLabels = suggestion.roundLabels
        supportsJokers = suggestion.supportsJokers
    }

    // MARK: - Naam en monogram

    private var identity: some View {
        AnyLayout(isCompact ? AnyLayout(VStackLayout(spacing: 0))
                  : AnyLayout(HStackLayout(alignment: .top, spacing: 0))) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Naam")
                HardTextField(placeholder: "Boerenbridge", text: $name)
                    .onChange(of: name) { _, _ in
                        if mono.isEmpty || !monoWasEdited { mono = suggestions.first ?? "" }
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 16, leading: isCompact ? 20 : 24,
                                bottom: 20, trailing: isCompact ? 20 : 24))
            .overlay(alignment: isCompact ? .bottom : .trailing) {
                if isCompact { Hairline() } else { Rectangle().fill(M.hairline).frame(width: 1) }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Monogram")
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { option in
                        Button {
                            mono = option
                            monoWasEdited = true
                        } label: {
                            Text(option)
                                .font(M.font(14, .extraBold))
                                .foregroundStyle(mono == option ? M.paper : M.ink)
                                .frame(width: 48, height: 48)
                                .background(mono == option ? M.ink : .clear)
                                .overlay(Rectangle().stroke(M.ruleHeavy, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 16, leading: 24, bottom: 20, trailing: 24))
        }
    }

    @State private var monoWasEdited = false

    /// Monogramvoorstellen, afgeleid van de naam.
    private var suggestions: [String] {
        let words = trimmedName.split(separator: " ").map(String.init)
        var options: [String] = []

        if let first = words.first, first.count >= 2 {
            options.append(String(first.prefix(2)).uppercased())
        }
        if words.count >= 2, let a = words[0].first, let b = words[1].first {
            options.append("\(a)\(b)".uppercased())
        }
        if let first = words.first, first.count >= 3 {
            let letters = Array(first)
            options.append("\(letters[0])\(letters[2])".uppercased())
        }
        if let first = words.first, let a = first.first, let z = first.last, first.count > 1 {
            options.append("\(a)\(z)".uppercased())
        }
        options.append(contentsOf: ["EG", "XX"])

        var unique: [String] = []
        for option in options where !unique.contains(option) && option.count == 2 {
            unique.append(option)
        }
        return Array(unique.prefix(5))
    }

    // MARK: - Scoremodus

    private var modeBlock: some View {
        VStack(spacing: 0) {
            SectionLabel("Scoremodus — de kern van het sjabloon")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 18, leading: 24, bottom: 10, trailing: 24))
            Hairline()

            ForEach(ScoringMode.allCases) { option in
                RowButton(background: mode == option ? M.redTint : .clear, minHeight: 66) {
                    mode = option
                } content: {
                    HStack(alignment: .top, spacing: isCompact ? 14 : 16) {
                        HardCheckbox(isOn: mode == option)
                            .padding(.top, 2)
                        if isCompact {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.name)
                                    .font(M.font(14.5, .extraBold))
                                    .foregroundStyle(M.ink)
                                Text(option.explanation)
                                    .font(M.font(12.5, .regular))
                                    .foregroundStyle(M.inkAlpha(0.65))
                                    .lineSpacing(3)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(option.examples)
                                    .font(M.font(11, .semiBold))
                                    .foregroundStyle(M.inkAlpha(0.45))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text(option.name)
                                .font(M.font(14.5, .extraBold))
                                .foregroundStyle(M.ink)
                                .frame(width: 190, alignment: .leading)
                            Text(option.explanation)
                                .font(M.font(12.5, .regular))
                                .foregroundStyle(M.inkAlpha(0.65))
                                .lineSpacing(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(option.examples)
                                .font(M.font(11, .semiBold))
                                .foregroundStyle(M.inkAlpha(0.45))
                                .multilineTextAlignment(.trailing)
                                .frame(width: 150, alignment: .trailing)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, isCompact ? 20 : 24)
                    .padding(.vertical, 14)
                }
                Hairline()
            }
            HeavyRule()
        }
    }

    // MARK: - Velden per modus

    private var fields: some View {
        VStack(spacing: 0) {
            switch mode {
            case .roundsCumulative:
                fieldRow(roundsField, winnerField)
                fieldRow(negativeField, playersField)
                fieldRow(jokerField, unitField)
                if !roundLabels.isEmpty { roundLabelsBlock }
            case .winnerOnly:
                fieldRow(recordField, playersField)
            case .scorecard:
                fieldRow(scorecardField, sectionsField)
                fieldRow(formulaField, playersField)
            case .finalScore:
                fieldRow(winnerField, playersField)
            case .elimination:
                fieldRow(limitField, eliminationWinnerField)
                fieldRow(negativeField, playersField)
            }
        }
    }

    private func fieldRow<A: View, B: View>(_ left: A, _ right: B) -> some View {
        HStack(alignment: .top, spacing: 0) {
            left
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .trailing) { Rectangle().fill(M.hairline).frame(width: 1) }
            right
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func field<Content: View>(_ label: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label.uppercased())
                .font(M.font(10, .semiBold))
                .tracking(em: 0.12, size: 10)
                .foregroundStyle(M.inkAlpha(0.5))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 16, leading: 24, bottom: 18, trailing: 24))
        .frame(minHeight: 96, alignment: .topLeading)
    }

    private var roundsField: some View {
        field("Aantal rondes") {
            HStack(spacing: 12) {
                Text(roundCount == 0 ? "∞" : "\(roundCount)")
                    .font(M.font(24, .extraBold))
                    .foregroundStyle(M.ink)
                    .frame(minWidth: 30, alignment: .leading)
                StepperPair(canDecrement: roundCount > 0, canIncrement: roundCount < 24) {
                    roundCount = max(0, roundCount - 1)
                } onIncrement: {
                    roundCount = min(24, roundCount + 1)
                }
                Text(roundCount == 0 ? "open einde" : "vaste lengte")
                    .font(M.font(12, .regular))
                    .foregroundStyle(M.inkAlpha(0.55))
            }
        }
    }

    private var winnerField: some View {
        field("Wie wint") {
            SegmentedBar(options: [(true, "Laagste"), (false, "Hoogste")],
                         selection: $winsByLowest, fontSize: 12.5)
                .frame(maxWidth: 260)
        }
    }

    private var negativeField: some View {
        field("Negatief toegestaan") {
            HStack(spacing: 14) {
                HardToggle(isOn: $allowNegative)
                Text(allowNegative ? "de ±-toets staat aan" : "zet de ±-toets uit")
                    .font(M.font(12, .regular))
                    .foregroundStyle(M.inkAlpha(0.55))
            }
        }
    }

    private var unitField: some View {
        field("Wat tel je") {
            HardTextField(placeholder: "punten", text: $unitLabel, fontSize: 15, minHeight: 44)
                .frame(maxWidth: 220)
        }
    }

    /// De opdrachten per ronde, zoals Jokeren die kent.
    private var roundLabelsBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Opdracht per ronde")
                .padding(EdgeInsets(top: 16, leading: 24, bottom: 10, trailing: 24))
            Hairline()
            ForEach(Array(roundLabels.enumerated()), id: \.offset) { index, label in
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(M.font(13, .regular))
                        .foregroundStyle(M.inkAlpha(0.4))
                        .frame(width: 16, alignment: .trailing)
                    Text(label)
                        .font(M.font(14, .semiBold))
                        .foregroundStyle(M.ink)
                    Spacer(minLength: 0)
                    Button {
                        roundLabels.remove(at: index)
                        roundCount = roundLabels.count
                    } label: {
                        Text("Verwijder")
                            .font(M.font(11.5, .semiBold))
                            .foregroundStyle(M.red)
                            .frame(minHeight: M.tap)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .frame(minHeight: 46)
                Hairline()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var jokerField: some View {
        field("Jokerteller") {
            HStack(spacing: 14) {
                HardToggle(isOn: $supportsJokers)
                Text(supportsJokers
                     ? "je kunt hem per potje aan- of uitzetten"
                     : "niet aangeboden bij het opzetten")
                    .font(M.font(12, .regular))
                    .foregroundStyle(M.inkAlpha(0.55))
            }
        }
    }

    private var playersField: some View {
        field("Spelers") {
            HStack(spacing: 12) {
                Text("\(minPlayers)–\(maxPlayers)")
                    .font(M.font(24, .extraBold))
                    .foregroundStyle(M.ink)
                StepperPair(canDecrement: minPlayers > 1, canIncrement: minPlayers < maxPlayers) {
                    minPlayers = max(1, minPlayers - 1)
                } onIncrement: {
                    minPlayers = min(maxPlayers, minPlayers + 1)
                }
                StepperPair(canDecrement: maxPlayers > minPlayers, canIncrement: maxPlayers < 12) {
                    maxPlayers = max(minPlayers, maxPlayers - 1)
                } onIncrement: {
                    maxPlayers = min(12, maxPlayers + 1)
                }
            }
        }
    }

    private var limitField: some View {
        field("Afvalgrens") {
            HStack(spacing: 12) {
                Text("\(eliminationLimit)")
                    .font(M.font(24, .extraBold))
                    .foregroundStyle(M.ink)
                    .frame(minWidth: 30, alignment: .leading)
                StepperPair(canDecrement: eliminationLimit > 1, canIncrement: eliminationLimit < 100) {
                    eliminationLimit = max(1, eliminationLimit - 1)
                } onIncrement: {
                    eliminationLimit = min(100, eliminationLimit + 1)
                }
                Text("strafpunten")
                    .font(M.font(12, .regular))
                    .foregroundStyle(M.inkAlpha(0.55))
            }
        }
    }

    private var eliminationWinnerField: some View {
        field("Wie wint") {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Laatste over")
                    .font(M.font(24, .extraBold))
                    .foregroundStyle(M.ink)
                Text("anderen liggen eruit")
                    .font(M.font(12, .regular))
                    .foregroundStyle(M.inkAlpha(0.55))
            }
        }
    }

    private var recordField: some View {
        field("Vastleggen") {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Eindvolgorde")
                    .font(M.font(24, .extraBold))
                    .foregroundStyle(M.ink)
                Text("of alleen de winnaar")
                    .font(M.font(12, .regular))
                    .foregroundStyle(M.inkAlpha(0.55))
            }
        }
    }

    private var scorecardField: some View {
        field("Kaart overnemen van") {
            HStack(spacing: 8) {
                ForEach(["Keer op Keer", "Yahtzee", "Qwixx"], id: \.self) { option in
                    Button { borrowedCard = option } label: {
                        Text(option)
                            .font(M.font(12.5, .extraBold))
                            .foregroundStyle(borrowedCard == option ? M.paper : M.ink)
                            .padding(.horizontal, 14)
                            .frame(minHeight: M.tap)
                            .background(borrowedCard == option ? M.ink : .clear)
                            .overlay(Rectangle().stroke(M.ruleHeavy, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var sectionsField: some View {
        field("Categorieën") {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(borrowedSpec?.columns.count ?? 0)")
                    .font(M.font(24, .extraBold))
                    .foregroundStyle(M.ink)
                Text("plus \(borrowedSpec?.bonuses.count ?? 0) bonussen")
                    .font(M.font(12, .regular))
                    .foregroundStyle(M.inkAlpha(0.55))
            }
        }
    }

    private var formulaField: some View {
        field("Formule") {
            Text(formulaDescription)
                .font(M.font(13, .regular))
                .foregroundStyle(M.inkAlpha(0.7))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var formulaDescription: String {
        guard let spec = borrowedSpec else { return "—" }
        var parts = ["som van de categorieën"]
        if !spec.bonuses.isEmpty { parts.append("+ bonussen") }
        if spec.sectionBonus != nil { parts.append("+ sectiebonus") }
        if spec.hasPenalty { parts.append("− aftrek") }
        return parts.joined(separator: " ") + ". Categorieën zelf samenstellen kan nog niet."
    }

    private var borrowedSpec: ScorecardSpec? {
        switch borrowedCard {
        case "Yahtzee": BuiltInGames.yahtzee()
        case "Qwixx": BuiltInGames.qwixx()
        default: BuiltInGames.keerOpKeer()
        }
    }

    // MARK: - Opslaan

    private func prefill() {
        guard let existing else { return }
        name = existing.name
        mono = existing.mono
        monoWasEdited = true
        mode = existing.mode
        roundCount = existing.roundCount
        winsByLowest = existing.winsByLowest
        allowNegative = existing.allowNegative
        minPlayers = existing.minPlayers
        maxPlayers = existing.maxPlayers
        eliminationLimit = existing.eliminationLimit
        supportsJokers = existing.supportsJokers
        unitLabel = existing.unitLabel
        roundLabels = existing.roundLabels
    }

    private func save() {
        let target: GameTemplate
        if let existing {
            target = existing
        } else {
            target = GameTemplate(name: trimmedName, mono: mono, mode: mode)
            target.sortIndex = (templates.map(\.sortIndex).max() ?? 0) + 1
            context.insert(target)
        }

        target.name = trimmedName
        target.mono = mono
        target.mode = mode
        target.roundCount = mode == .roundsCumulative ? roundCount : 0
        target.winsByLowest = winsByLowest
        target.allowNegative = allowNegative
        target.minPlayers = minPlayers
        target.maxPlayers = maxPlayers
        target.eliminationLimit = eliminationLimit
        target.supportsJokers = mode == .roundsCumulative && supportsJokers
        target.unitLabel = unitLabel.trimmingCharacters(in: .whitespaces).isEmpty
            ? "punten" : unitLabel.trimmingCharacters(in: .whitespaces)
        target.roundLabels = mode == .roundsCumulative ? roundLabels : []
        target.subtitleNote = ""
        target.scorecardData = mode == .scorecard ? borrowedSpec?.encoded() : nil

        saved = true
        router.screen = .play
    }
}
