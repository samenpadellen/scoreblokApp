import SwiftData
import SwiftUI

/// De eerste start, direct na de opslagkeuze. Geen uitleg vooraf maar doen:
/// je naam, je medespelers en een spel. Aan het eind staat het eerste potje
/// klaar met de juiste spelers aangevinkt. De rondleiding met uitleg blijft
/// terug te halen via Instellingen.
struct FirstRunView: View {
    enum Exit {
        /// Het potje opzetten voor dit spel, met deze spelers al gekozen.
        case setup(GameTemplate, [UUID])
        case play
    }

    let onFinish: (Exit) -> Void

    private enum Step: Int { case me = 2, friends, game }
    private enum Field { case me, friend }

    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \Player.createdAt) private var allPlayers: [Player]
    @Query(sort: \GameTemplate.sortIndex) private var allTemplates: [GameTemplate]

    @State private var step: Step = .me
    @State private var forward = true
    @State private var myName = ""
    @State private var myAvatar = Int.random(in: 0..<AvatarShape.count)
    @State private var pickedExisting: UUID?
    @State private var friendName = ""
    @State private var duplicate: String?
    /// Spelers die in deze stappen zijn aangemaakt; alleen die kun je hier weer weghalen.
    @State private var added: [UUID] = []
    @State private var chosenGame: UUID?
    @FocusState private var focus: Field?

    private var wide: Bool { sizeClass == .regular }
    private var players: [Player] { allPlayers.filter { !$0.isArchived && !$0.isDeleted } }
    private var me: Player? { players.first(where: \.isMe) }
    private var others: [Player] { players.filter { !$0.isMe } }
    private var shelf: [GameTemplate] { allTemplates.filter { !$0.isPutAway } }
    private var cupboardCount: Int { allTemplates.count - shelf.count }
    private var chosenTemplate: GameTemplate? { shelf.first { $0.id == chosenGame } }
    private var trimmedName: String { myName.trimmingCharacters(in: .whitespaces) }
    private var trimmedFriend: String { friendName.trimmingCharacters(in: .whitespaces) }
    private var canLeaveMe: Bool { !trimmedName.isEmpty || pickedExisting != nil || me != nil }

    var body: some View {
        VStack(spacing: 0) {
            header
            HeavyRule()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    IntroSteps(current: step.rawValue, title: stepTitle)
                        .padding(.bottom, wide ? 30 : 22)
                    Group {
                        switch step {
                        case .me: meStep
                        case .friends: friendsStep
                        case .game: gameStep
                        }
                    }
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .opacity))

                    // Op een iPad staan de knoppen direct onder de inhoud, niet
                    // een scherm verderop in de hoek.
                    if wide {
                        actions.padding(.top, 34)
                    }
                }
                .frame(maxWidth: wide ? 720 : .infinity, alignment: .leading)
                .padding(.horizontal, wide ? 40 : 20)
                .padding(.vertical, wide ? 40 : 22)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            if !wide {
                HeavyRule()
                footer
            }
        }
        .background(M.paper)
        .onAppear {
            if let me { myName = me.name }
        }
        .task {
            // Het toetsenbord meteen klaar, zodat je gewoon kunt beginnen te typen.
            try? await Task.sleep(for: .milliseconds(600))
            if step == .me, me == nil { focus = .me }
        }
    }

    // MARK: - Kop en voet

    private var header: some View {
        HStack(spacing: 10) {
            Wordmark(size: 15, markSize: 24)
            Spacer(minLength: 8)
            Button { finish(.play) } label: {
                Text("Overslaan")
                    .font(M.font(12.5, .semiBold))
                    .foregroundStyle(M.inkAlpha(0.6))
                    .frame(minHeight: M.tap)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Sluit de eerste stappen en ga naar Spelen")
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
    }

    private var footer: some View {
        actions
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(M.paperDeep)
    }

    private var actions: some View {
        HStack(spacing: 12) {
            if step != .me {
                Button { back() } label: {
                    Text("← Terug")
                        .font(M.font(12.5, .semiBold))
                        .foregroundStyle(M.inkAlpha(0.65))
                        .frame(minHeight: M.tap)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 8)
            switch step {
            case .me:
                SolidButton(title: "Verder", fontSize: 14, minHeight: 48, enabled: canLeaveMe) { advance() }
            case .friends:
                SolidButton(title: others.isEmpty ? "Alleen verder" : "Verder", fontSize: 14, minHeight: 48) {
                    advance()
                }
            case .game:
                SolidButton(title: chosenTemplate == nil ? "Kies een spel" : "Potje klaarzetten",
                            fontSize: 14, minHeight: 48, enabled: chosenTemplate != nil) {
                    if let template = chosenTemplate {
                        finish(.setup(template, Array(team.prefix(template.maxPlayers))))
                    }
                }
            }
        }
    }

    private var stepTitle: String {
        switch step {
        case .me: "Jij"
        case .friends: "Medespelers"
        case .game: "Eerste potje"
        }
    }

    // MARK: - Stap 2 · jij

    private var meStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Hoe heet jij?")
            lead("Zo weet Scoreblok wie ‘jij’ bent: jouw winstpercentage staat bovenaan de statistieken. Een foto en kleur kies je later bij Spelers.")

            if me == nil, !others.isEmpty {
                label("Staat je naam er al tussen?")
                VStack(spacing: 0) {
                    ForEach(others) { player in
                        let isOn = pickedExisting == player.id
                        RowButton(isActive: isOn, minHeight: 54) {
                            withAnimation(M.Motion.quick) {
                                pickedExisting = isOn ? nil : player.id
                                if !isOn { myName = "" }
                            }
                            focus = nil
                        } content: {
                            HStack(spacing: 12) {
                                HardCheckbox(isOn: isOn)
                                PlayerMark(player: player, size: 28)
                                Text(player.name)
                                    .font(M.font(15, .semiBold))
                                    .foregroundStyle(M.ink)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 16)
                        }
                        Hairline()
                    }
                }
                .overlay(alignment: .top) { HeavyRule() }
                .padding(.bottom, 22)
                label("Of typ je naam")
            }

            HStack(spacing: 12) {
                Group {
                    if let me {
                        PlayerMark(player: me, size: 52)
                    } else {
                        AvatarSwatch(avatarIndex: myAvatar, rampIndex: allPlayers.count, size: 52)
                    }
                }
                .opacity(pickedExisting == nil ? 1 : 0.35)
                field("Je naam", text: $myName, field: .me) {
                    if canLeaveMe { advance() }
                }
            }
            .onChange(of: myName) { _, name in
                if !name.isEmpty { pickedExisting = nil }
            }
        }
    }

    // MARK: - Stap 3 · medespelers

    private var friendsStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Met wie speel je?")
            lead("Voeg de mensen toe met wie je meestal speelt, één naam per keer. Meer spelers toevoegen kan later altijd.")

            HStack(spacing: 10) {
                field("Naam van een medespeler", text: $friendName, field: .friend) { addFriend() }
                SolidButton(title: "Voeg toe", fill: M.ink, fontSize: 13.5, minHeight: 52,
                            enabled: !trimmedFriend.isEmpty) { addFriend() }
            }
            .padding(.bottom, duplicate == nil ? 20 : 8)

            if let duplicate {
                Text("\(duplicate) staat er al bij.")
                    .font(M.font(12.5, .semiBold))
                    .foregroundStyle(M.red)
                    .padding(.bottom, 14)
                    .transition(.opacity)
            }

            VStack(spacing: 0) {
                if let me {
                    rosterRow(me, isYou: true)
                    Hairline()
                }
                ForEach(others) { player in
                    rosterRow(player, isYou: false)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Hairline()
                }
            }
            .overlay(alignment: .top) { HeavyRule() }

            if others.isEmpty {
                note("Nog niemand toegevoegd. Alleen beginnen kan ook; medespelers voeg je dan toe bij het opzetten van een potje.")
            }
        }
    }

    private func rosterRow(_ player: Player, isYou: Bool) -> some View {
        HStack(spacing: 12) {
            PlayerMark(player: player, size: 34)
            Text(player.name)
                .font(M.font(16, .semiBold))
                .foregroundStyle(M.ink)
                .lineLimit(1)
            if isYou {
                Tag(text: "Jij", background: M.inkAlpha(0.12), foreground: M.inkAlpha(0.7), size: 9)
            }
            Spacer(minLength: 8)
            if added.contains(player.id) {
                Button { remove(player) } label: {
                    Text("×")
                        .font(M.font(20, .regular))
                        .foregroundStyle(M.inkAlpha(0.5))
                        .frame(width: M.tap, height: M.tap)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Haal \(player.name) weg")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 56)
        .background(M.surface)
    }

    // MARK: - Stap 4 · eerste potje

    private var gameStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Wat spelen jullie?")
            lead(teamLine)

            GridRows(items: shelf, columns: wide ? 3 : 1) { template in
                gameCell(template)
            }
            .overlay(alignment: .top) { HeavyRule() }

            note("Staat je spel er niet bij? In de spellenkast liggen er nog \(cupboardCount), en onder Eigen spel maak je er zelf een.")

            demoOption
                .padding(.top, 22)
                .padding(.bottom, 6)

            Button { finish(.play) } label: {
                Text("Eerst rondkijken, zonder potje →")
                    .font(M.font(13, .extraBold))
                    .foregroundStyle(M.inkAlpha(0.7))
                    .frame(minHeight: M.tap)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    /// Voor wie eerst wil zien wat de app kan, zonder te spelen.
    private var demoOption: some View {
        RowButton(minHeight: 72, edge: M.ink) {
            DemoData.fill(in: context)
            finish(.play)
        } content: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Eerst proberen met voorbeeldpotjes")
                        .font(M.font(15, .extraBold))
                        .foregroundStyle(M.ink)
                    Text("Vult de app met zeventien afgeronde potjes, zodat je statistieken en geschiedenis meteen ziet. Met één tik weer weg; wat je zelf invult blijft staan.")
                        .font(M.font(12, .regular))
                        .foregroundStyle(M.inkAlpha(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text("→")
                    .font(M.font(16, .semiBold))
                    .foregroundStyle(M.ink)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .overlay(Rectangle().stroke(M.ruleHeavy, lineWidth: 1))
    }

    private func gameCell(_ template: GameTemplate) -> some View {
        let isOn = chosenGame == template.id
        return RowButton(isActive: isOn, minHeight: wide ? 76 : 62) {
            withAnimation(M.Motion.quick) { chosenGame = template.id }
        } content: {
            HStack(spacing: 12) {
                GameMark(mono: template.mono, name: template.name, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(template.name)
                        .font(M.font(15, .extraBold))
                        .foregroundStyle(M.ink)
                        .lineLimit(1)
                    Text(template.subtitle)
                        .font(M.font(11.5, .regular))
                        .foregroundStyle(M.inkAlpha(0.55))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isOn {
                    Text("✓")
                        .font(M.font(15, .extraBold))
                        .foregroundStyle(M.red)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
        }
    }

    /// Wie er straks aan tafel zitten: jij, wie je net toevoegde, en anders
    /// de spelers die er al waren.
    private var team: [UUID] {
        var ids: [UUID] = me.map { [$0.id] } ?? []
        ids += added.filter { id in players.contains { $0.id == id } }
        if ids.count < 2 {
            ids += others.map(\.id).filter { !ids.contains($0) }
        }
        return ids
    }

    private var teamLine: String {
        let names = team.compactMap { id in players.first { $0.id == id }?.name }
        guard !names.isEmpty else {
            return "Kies een spel. Wie er meedoen kies je daarna bij het opzetten van het potje."
        }
        let list = names.count == 1 ? names[0]
            : names.dropLast().joined(separator: ", ") + " en " + names[names.count - 1]
        return "Kies een spel. Daarna staat het potje klaar voor \(list); daar kun je nog aanpassen wie er meedoet."
    }

    // MARK: - Onderdelen

    private func title(_ text: String) -> some View {
        Text(text)
            .font(M.font(wide ? 40 : 30, .extraBold))
            .tracking(em: -0.025, size: wide ? 40 : 30)
            .foregroundStyle(M.ink)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 12)
    }

    private func lead(_ text: String) -> some View {
        Text(text)
            .font(M.font(wide ? 16 : 14.5, .regular))
            .foregroundStyle(M.inkAlpha(0.72))
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 24)
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(M.font(10.5, .extraBold))
            .tracking(em: 0.12, size: 10.5)
            .foregroundStyle(M.inkAlpha(0.6))
            .padding(.bottom, 10)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(M.font(12.5, .regular))
            .foregroundStyle(M.inkAlpha(0.58))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }

    private func field(_ placeholder: String, text: Binding<String>, field: Field,
                       onSubmit: @escaping () -> Void) -> some View {
        let active = focus == field
        return TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(M.font(18, .semiBold))
            .foregroundStyle(M.ink)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(field == .me ? .next : .done)
            .focused($focus, equals: field)
            .onSubmit(onSubmit)
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(M.surface)
            .overlay(Rectangle().stroke(active ? M.ink : M.ruleHeavy, lineWidth: active ? 2 : 1))
            .animation(M.Motion.quick, value: active)
    }

    // MARK: - Acties

    private func advance() {
        switch step {
        case .me:
            commitMe()
            go(to: .friends)
        case .friends:
            go(to: .game)
        case .game:
            break
        }
    }

    private func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        go(to: previous)
    }

    private func go(to next: Step) {
        forward = next.rawValue > step.rawValue
        focus = nil
        duplicate = nil
        withAnimation(M.Motion.settle) { step = next }
        if next == .friends {
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                if step == .friends { focus = .friend }
            }
        }
    }

    private func commitMe() {
        if let me {
            if !trimmedName.isEmpty { me.name = trimmedName }
        } else if let id = pickedExisting {
            for player in allPlayers { player.isMe = player.id == id }
        } else if !trimmedName.isEmpty {
            context.insert(Player(name: trimmedName,
                                  rampIndex: allPlayers.count % M.playerRamp.count,
                                  avatarIndex: myAvatar,
                                  isMe: true))
        }
        Storage.save(context)
    }

    private func addFriend() {
        let name = trimmedFriend
        guard !name.isEmpty else {
            focus = nil
            return
        }
        if let existing = players.first(where: { SamenExchange.normalized($0.name) == SamenExchange.normalized(name) }) {
            withAnimation(M.Motion.quick) { duplicate = existing.name }
            return
        }
        let player = Player(name: name, rampIndex: allPlayers.count % M.playerRamp.count)
        withAnimation(M.Motion.settle) {
            duplicate = nil
            context.insert(player)
            added.append(player.id)
        }
        Storage.save(context)
        friendName = ""
        Task { focus = .friend }
    }

    private func remove(_ player: Player) {
        withAnimation(M.Motion.settle) {
            added.removeAll { $0 == player.id }
            context.delete(player)
        }
        Storage.save(context)
    }

    private func finish(_ exit: Exit) {
        if step == .me, me == nil, pickedExisting != nil || !trimmedName.isEmpty {
            commitMe()
        }
        focus = nil
        onFinish(exit)
    }
}

/// De voortgang door de eerste stappen: vier vakken, het huidige in rood,
/// met eronder waar je bent.
struct IntroSteps: View {
    static let total = 4

    let current: Int
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                ForEach(1...Self.total, id: \.self) { spot in
                    Rectangle()
                        .fill(spot == current ? M.red : (spot < current ? M.ink : M.inkAlpha(0.15)))
                        .frame(height: 4)
                }
            }
            .animation(M.Motion.settle, value: current)
            Text("Stap \(current) van \(Self.total) · \(title)".uppercased())
                .font(M.font(10.5, .extraBold))
                .tracking(em: 0.14, size: 10.5)
                .foregroundStyle(M.red)
                .contentTransition(.opacity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stap \(current) van \(Self.total): \(title)")
    }
}
